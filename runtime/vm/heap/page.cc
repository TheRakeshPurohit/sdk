// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include "vm/heap/page.h"

#include "platform/assert.h"
#include "platform/leak_sanitizer.h"
#include "vm/dart.h"
#include "vm/heap/become.h"
#include "vm/heap/compactor.h"
#include "vm/heap/marker.h"
#include "vm/heap/safepoint.h"
#include "vm/heap/sweeper.h"
#include "vm/lockers.h"
#include "vm/log.h"
#include "vm/object.h"
#include "vm/object_set.h"
#include "vm/os_thread.h"
#include "vm/virtual_memory.h"

namespace dart {

// This cache needs to be at least as big as FLAG_new_gen_semi_max_size or
// munmap will noticeably impact performance.
static constexpr intptr_t kPageCacheCapacity = 128 * kWordSize;
static Mutex* page_cache_mutex = nullptr;
static VirtualMemory* page_cache[2][kPageCacheCapacity] = {{nullptr},
                                                           {nullptr}};
static intptr_t page_cache_size[2] = {0, 0};

void Page::Init() {
  ASSERT(page_cache_mutex == nullptr);
  page_cache_mutex = new Mutex();
}

void Page::ClearCache() {
  MutexLocker ml(page_cache_mutex);
  for (intptr_t i = 0; i < 2; i++) {
    ASSERT(page_cache_size[i] >= 0);
    ASSERT(page_cache_size[i] <= kPageCacheCapacity);
    while (page_cache_size[i] > 0) {
      delete page_cache[i][--page_cache_size[i]];
    }
  }
}

void Page::Cleanup() {
  ClearCache();
  delete page_cache_mutex;
  page_cache_mutex = nullptr;
}

intptr_t Page::CachedSize() {
  MutexLocker ml(page_cache_mutex);
  intptr_t pages = 0;
  for (intptr_t i = 0; i < 2; i++) {
    pages += page_cache_size[i];
  }
  return pages * kPageSize;
}

static bool CanUseCache(uword flags) {
  return (flags & (Page::kImage | Page::kLarge | Page::kVMIsolate)) == 0;
}

static intptr_t CacheIndex(uword flags) {
  return (flags & Page::kExecutable) != 0 ? 1 : 0;
}

Page* Page::Allocate(intptr_t size, uword flags) {
  const bool executable = (flags & Page::kExecutable) != 0;
  const bool compressed = !executable;
  const char* name = executable ? "dart-code" : "dart-heap";

  VirtualMemory* memory = nullptr;
  if (CanUseCache(flags)) {
    // We don't automatically use the cache based on size and type because a
    // large page that happens to be the same size as a regular page can't
    // use the cache. Large pages are expected to be zeroed on allocation but
    // cached pages are dirty.
    ASSERT(size == kPageSize);
    MutexLocker ml(page_cache_mutex);
    intptr_t index = CacheIndex(flags);
    ASSERT(page_cache_size[index] >= 0);
    ASSERT(page_cache_size[index] <= kPageCacheCapacity);
    if (page_cache_size[index] > 0) {
      memory = page_cache[index][--page_cache_size[index]];
    }
  }
  if (memory == nullptr) {
    memory = VirtualMemory::AllocateAligned(size, kPageSize, executable,
                                            compressed, name);
  }
  if (memory == nullptr) {
    return nullptr;  // Out of memory.
  }

  if ((flags & kNew) != 0) {
    // Initialized by generated code.
    MSAN_UNPOISON(memory->address(), size);

#if defined(DEBUG)
    // Allocation stubs check that the TLAB hasn't been corrupted.
    uword* cursor = reinterpret_cast<uword*>(memory->address());
    uword* end = reinterpret_cast<uword*>(memory->end());
    while (cursor < end) {
      *cursor++ = kAllocationCanary;
    }
#endif
  }

  Page* result = reinterpret_cast<Page*>(memory->address());
  ASSERT(result != nullptr);
  result->flags_ = flags;
  result->memory_ = memory;
  result->next_ = nullptr;
  result->forwarding_page_ = nullptr;
  result->card_table_ = nullptr;
  result->progress_bar_ = 0;
  result->owner_ = nullptr;
  result->top_ = 0;
  result->end_ = 0;
  result->survivor_end_ = 0;
  result->resolved_top_ = 0;
  result->live_bytes_ = 0;

  if ((flags & kNew) != 0) {
    uword top = result->object_start();
    uword end =
        memory->end() - kNewObjectAlignmentOffset - kAllocationRedZoneSize;
    result->top_ = top;
    result->end_ = end;
    result->survivor_end_ = top;
    result->resolved_top_ = top;
  }

  LSAN_REGISTER_ROOT_REGION(result, sizeof(*result));

  return result;
}

void Page::Deallocate() {
  if (is_image()) {
    delete memory_;
    // For a heap page from a snapshot, the Page object lives in the malloc
    // heap rather than the page itself.
    free(this);
    return;
  }

  free(card_table_);

  // Load before unregistering with LSAN, or LSAN will temporarily think it has
  // been leaked.
  VirtualMemory* memory = memory_;

  LSAN_UNREGISTER_ROOT_REGION(this, sizeof(*this));

  const uword flags = flags_;
  if (CanUseCache(flags)) {
    ASSERT(memory->size() == kPageSize);

    // Allow caching up to one new-space worth of pages to avoid the cost unmap
    // when freeing from-space. Using ThresholdInWords both accounts for
    // new-space scaling with the number of mutators, and prevents the cache
    // from staying big after new-space shrinks.
    intptr_t limit = 0;
    IsolateGroup* group = IsolateGroup::Current();
    if ((group != nullptr) && ((flags_ & kNew) != 0)) {
      limit = group->heap()->new_space()->ThresholdInWords() / kPageSizeInWords;
    }
    limit = Utils::Maximum(limit, FLAG_new_gen_semi_max_size * MB / kPageSize);
    limit = Utils::Minimum(limit, kPageCacheCapacity);

    MutexLocker ml(page_cache_mutex);
    intptr_t index = CacheIndex(flags);
    ASSERT(page_cache_size[index] >= 0);
    ASSERT(page_cache_size[index] <= kPageCacheCapacity);
    if (page_cache_size[index] < limit) {
      intptr_t size = memory->size();
      if ((flags & kExecutable) != 0 && FLAG_write_protect_code) {
        // Reset to initial protection.
        memory->Protect(VirtualMemory::kReadWrite);
      }
#if defined(DEBUG)
      if ((flags & kExecutable) != 0) {
        uword* cursor = reinterpret_cast<uword*>(memory->address());
        uword* end = reinterpret_cast<uword*>(memory->end());
        while (cursor < end) {
          *cursor++ = kBreakInstructionFiller;
        }
      } else {
        memset(memory->address(), Heap::kZapByte, size);
      }
#endif
      MSAN_POISON(memory->address(), size);
      page_cache[index][page_cache_size[index]++] = memory;
      memory = nullptr;
    }
  }
  delete memory;
}

void Page::VisitObjects(ObjectVisitor* visitor) const {
  ASSERT(Thread::Current()->OwnsGCSafepoint() ||
         (Thread::Current()->task_kind() == Thread::kIncrementalCompactorTask));
  NoSafepointScope no_safepoint;
  uword obj_addr = object_start();
  uword end_addr = object_end();
  while (obj_addr < end_addr) {
    ObjectPtr raw_obj = UntaggedObject::FromAddr(obj_addr);
    visitor->VisitObject(raw_obj);
    obj_addr += raw_obj->untag()->HeapSize();
  }
  ASSERT(obj_addr == end_addr);
}

void Page::VisitObjectsUnsafe(ObjectVisitor* visitor) const {
  uword obj_addr = object_start();
  uword end_addr = object_end();
  while (obj_addr < end_addr) {
    ObjectPtr raw_obj = UntaggedObject::FromAddr(obj_addr);
    visitor->VisitObject(raw_obj);
    obj_addr += raw_obj->untag()->HeapSize();
  }
}

void Page::VisitObjectPointers(ObjectPointerVisitor* visitor) const {
  ASSERT(Thread::Current()->OwnsGCSafepoint() ||
         (Thread::Current()->task_kind() == Thread::kCompactorTask) ||
         (Thread::Current()->task_kind() == Thread::kMarkerTask));
  NoSafepointScope no_safepoint;
  uword obj_addr = object_start();
  uword end_addr = object_end();
  while (obj_addr < end_addr) {
    ObjectPtr raw_obj = UntaggedObject::FromAddr(obj_addr);
    obj_addr += raw_obj->untag()->VisitPointers(visitor);
  }
  ASSERT(obj_addr == end_addr);
}

void Page::VisitRememberedCards(PredicateObjectPointerVisitor* visitor,
                                bool only_marked) {
  ASSERT(Thread::Current()->OwnsGCSafepoint() ||
         (Thread::Current()->task_kind() == Thread::kScavengerTask) ||
         (Thread::Current()->task_kind() == Thread::kIncrementalCompactorTask));
  NoSafepointScope no_safepoint;

  if (card_table_ == nullptr) {
    return;
  }

  ArrayPtr obj =
      static_cast<ArrayPtr>(UntaggedObject::FromAddr(object_start()));
  ASSERT(obj->IsArray() || obj->IsImmutableArray());
  ASSERT(obj->untag()->IsCardRemembered());
  if (only_marked && !obj->untag()->IsMarked()) return;
  CompressedObjectPtr* obj_from = obj->untag()->from();
  CompressedObjectPtr* obj_to =
      obj->untag()->to(Smi::Value(obj->untag()->length()));
  uword heap_base = obj.heap_base();

  const size_t size_in_bits = card_table_size();
  const size_t size_in_words =
      Utils::RoundUp(size_in_bits, kBitsPerWord) >> kBitsPerWordLog2;
  for (;;) {
    const size_t word_offset = progress_bar_.fetch_add(1);
    if (word_offset >= size_in_words) break;

    uword cell = card_table_[word_offset];
    if (cell == 0) continue;

    for (intptr_t bit_offset = 0; bit_offset < kBitsPerWord; bit_offset++) {
      const uword bit_mask = static_cast<uword>(1) << bit_offset;
      if ((cell & bit_mask) == 0) continue;
      const intptr_t i = (word_offset << kBitsPerWordLog2) + bit_offset;

      CompressedObjectPtr* card_from =
          reinterpret_cast<CompressedObjectPtr*>(this) +
          (i << kSlotsPerCardLog2);
      CompressedObjectPtr* card_to =
          reinterpret_cast<CompressedObjectPtr*>(card_from) +
          (1 << kSlotsPerCardLog2) - 1;
      // Minus 1 because to is inclusive.

      if (card_from < obj_from) {
        // First card overlaps with header.
        card_from = obj_from;
      }
      if (card_to > obj_to) {
        // Last card(s) may extend past the object. Array truncation can make
        // this happen for more than one card.
        card_to = obj_to;
      }

      bool has_new_target = visitor->PredicateVisitCompressedPointers(
          heap_base, card_from, card_to);

      if (!has_new_target) {
        cell ^= bit_mask;
      }
    }
    card_table_[word_offset] = cell;
  }
}

void Page::ResetProgressBar() {
  progress_bar_ = 0;
}

void Page::WriteProtect(bool read_only) {
  ASSERT(!is_image());
  if (is_executable() && read_only) {
    // Handle making code executable in a special way.
    memory_->WriteProtectCode();
  } else {
    memory_->Protect(read_only ? VirtualMemory::kReadOnly
                               : VirtualMemory::kReadWrite);
  }
}

}  // namespace dart
