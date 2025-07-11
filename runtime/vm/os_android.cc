// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include "vm/globals.h"
#if defined(DART_HOST_OS_ANDROID)

#include "vm/os.h"

#include <android/api-level.h>  // NOLINT
#include <android/log.h>        // NOLINT
#include <dlfcn.h>              // NOLINT
#include <elf.h>                // NOLINT
#include <errno.h>              // NOLINT
#include <limits.h>             // NOLINT
#include <malloc.h>             // NOLINT
#include <sys/resource.h>       // NOLINT
#include <sys/time.h>           // NOLINT
#include <sys/types.h>          // NOLINT
#include <time.h>               // NOLINT
#include <unistd.h>             // NOLINT

#include "platform/utils.h"
#include "vm/code_observers.h"
#include "vm/dart.h"
#include "vm/image_snapshot.h"
#include "vm/isolate.h"
#include "vm/timeline.h"
#include "vm/zone.h"

namespace dart {

DEFINE_FLAG(bool,
            android_log_to_stderr,
            false,
            "Send Dart VM logs to stdout and stderr instead of the Android "
            "system logs.");

// Android CodeObservers.

#ifndef PRODUCT

DEFINE_FLAG(bool,
            generate_perf_events_symbols,
            false,
            "Generate events symbols for profiling with perf");

class PerfCodeObserver : public CodeObserver {
 public:
  PerfCodeObserver() : out_file_(nullptr) {
    Dart_FileOpenCallback file_open = Dart::file_open_callback();
    if (file_open == nullptr) {
      return;
    }
    intptr_t pid = getpid();
    char* filename = OS::SCreate(nullptr, "/tmp/perf-%" Pd ".map", pid);
    out_file_ = (*file_open)(filename, true);
    free(filename);
  }

  ~PerfCodeObserver() {
    Dart_FileCloseCallback file_close = Dart::file_close_callback();
    if ((file_close == nullptr) || (out_file_ == nullptr)) {
      return;
    }
    (*file_close)(out_file_);
  }

  virtual bool IsActive() const {
    return FLAG_generate_perf_events_symbols && (out_file_ != nullptr);
  }

  virtual void Notify(const char* name,
                      uword base,
                      uword prologue_offset,
                      uword size,
                      bool optimized,
                      const CodeComments* comments) {
    Dart_FileWriteCallback file_write = Dart::file_write_callback();
    if ((file_write == nullptr) || (out_file_ == nullptr)) {
      return;
    }
    const char* marker = optimized ? "*" : "";
    char* buffer =
        OS::SCreate(Thread::Current()->zone(), "%" Px " %" Px " %s%s\n", base,
                    size, marker, name);
    (*file_write)(buffer, strlen(buffer), out_file_);
  }

 private:
  void* out_file_;

  DISALLOW_COPY_AND_ASSIGN(PerfCodeObserver);
};

#endif  // !PRODUCT

intptr_t OS::ProcessId() {
  return static_cast<intptr_t>(getpid());
}

static bool LocalTime(int64_t seconds_since_epoch, tm* tm_result) {
  time_t seconds = static_cast<time_t>(seconds_since_epoch);
  if (seconds != seconds_since_epoch) return false;
  struct tm* error_code = localtime_r(&seconds, tm_result);
  return error_code != nullptr;
}

const char* OS::GetTimeZoneName(int64_t seconds_since_epoch) {
  tm decomposed;
  bool succeeded = LocalTime(seconds_since_epoch, &decomposed);
  // If unsuccessful, return an empty string like V8 does.
  return (succeeded && (decomposed.tm_zone != nullptr)) ? decomposed.tm_zone
                                                        : "";
}

int OS::GetTimeZoneOffsetInSeconds(int64_t seconds_since_epoch) {
  tm decomposed;
  bool succeeded = LocalTime(seconds_since_epoch, &decomposed);
  // Even if the offset was 24 hours it would still easily fit into 32 bits.
  // If unsuccessful, return zero like V8 does.
  return succeeded ? static_cast<int>(decomposed.tm_gmtoff) : 0;
}

int64_t OS::GetCurrentTimeMillis() {
  return GetCurrentTimeMicros() / 1000;
}

int64_t OS::GetCurrentTimeMicros() {
  // gettimeofday has microsecond resolution.
  struct timeval tv;
  if (gettimeofday(&tv, nullptr) < 0) {
    UNREACHABLE();
    return 0;
  }
  return (static_cast<int64_t>(tv.tv_sec) * 1000000) + tv.tv_usec;
}

int64_t OS::GetCurrentMonotonicTicks() {
  struct timespec ts;
  if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
    UNREACHABLE();
    return 0;
  }
  // Convert to nanoseconds.
  int64_t result = ts.tv_sec;
  result *= kNanosecondsPerSecond;
  result += ts.tv_nsec;
  return result;
}

int64_t OS::GetCurrentMonotonicFrequency() {
  return kNanosecondsPerSecond;
}

int64_t OS::GetCurrentMonotonicMicros() {
  int64_t ticks = GetCurrentMonotonicTicks();
  ASSERT(GetCurrentMonotonicFrequency() == kNanosecondsPerSecond);
  return ticks / kNanosecondsPerMicrosecond;
}

int64_t OS::GetCurrentThreadCPUMicros() {
  struct timespec ts;
  if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts) != 0) {
    UNREACHABLE();
    return -1;
  }
  int64_t result = ts.tv_sec;
  result *= kMicrosecondsPerSecond;
  result += (ts.tv_nsec / kNanosecondsPerMicrosecond);
  return result;
}

int64_t OS::GetCurrentMonotonicMicrosForTimeline() {
#if defined(SUPPORT_TIMELINE)
  if (Timeline::recorder_discards_clock_values()) return -1;
  return GetCurrentMonotonicMicros();
#else
  return -1;
#endif
}

// TODO(5411554):  May need to hoist these architecture dependent code
// into a architecture specific file e.g: os_ia32_linux.cc
intptr_t OS::ActivationFrameAlignment() {
#if defined(TARGET_ARCH_IA32) || defined(TARGET_ARCH_X64) ||                   \
    defined(TARGET_ARCH_ARM64) || defined(TARGET_ARCH_RISCV64)
  const int kMinimumAlignment = 16;
#elif defined(TARGET_ARCH_ARM)
  const int kMinimumAlignment = 8;
#else
#error Unsupported architecture.
#endif
  intptr_t alignment = kMinimumAlignment;
  // TODO(5411554): Allow overriding default stack alignment for
  // testing purposes.
  // Flags::DebugIsInt("stackalign", &alignment);
  ASSERT(Utils::IsPowerOfTwo(alignment));
  ASSERT(alignment >= kMinimumAlignment);
  return alignment;
}

int OS::NumberOfAvailableProcessors() {
  return sysconf(_SC_NPROCESSORS_ONLN);
}

uintptr_t OS::CurrentRSS() {
  // The second value in /proc/self/statm is the current RSS in pages.
  // It is not possible to use getrusage() because the interested fields are not
  // implemented by the linux kernel.
  FILE* statm = fopen("/proc/self/statm", "r");
  if (statm == nullptr) {
    return 0;
  }
  int64_t current_rss_pages = 0;
  int matches = fscanf(statm, "%*s%" Pd64 "", &current_rss_pages);
  fclose(statm);
  if (matches != 1) {
    return 0;
  }
  return current_rss_pages * getpagesize();
}

void OS::Sleep(int64_t millis) {
  int64_t micros = millis * kMicrosecondsPerMillisecond;
  SleepMicros(micros);
}

void OS::SleepMicros(int64_t micros) {
  struct timespec req;  // requested.
  struct timespec rem;  // remainder.
  int64_t seconds = micros / kMicrosecondsPerSecond;
  micros = micros - seconds * kMicrosecondsPerSecond;
  int64_t nanos = micros * kNanosecondsPerMicrosecond;
  req.tv_sec = seconds;
  req.tv_nsec = nanos;
  while (true) {
    int r = nanosleep(&req, &rem);
    if (r == 0) {
      break;
    }
    // We should only ever see an interrupt error.
    ASSERT(errno == EINTR);
    // Copy remainder into requested and repeat.
    req = rem;
  }
}

void OS::DebugBreak() {
  __builtin_trap();
}

DART_NOINLINE uintptr_t OS::GetProgramCounter() {
  return reinterpret_cast<uintptr_t>(
      __builtin_extract_return_addr(__builtin_return_address(0)));
}

void OS::Print(const char* format, ...) {
  va_list args;
  va_start(args, format);
  if (FLAG_android_log_to_stderr) {
    vfprintf(stderr, format, args);
  } else {
    // Forward to the Android log for remote access.
    __android_log_vprint(ANDROID_LOG_INFO, "DartVM", format, args);
  }
  va_end(args);
}

void OS::VFPrint(FILE* stream, const char* format, va_list args) {
  vfprintf(stream, format, args);
  fflush(stream);
}

char* OS::SCreate(Zone* zone, const char* format, ...) {
  va_list args;
  va_start(args, format);
  char* buffer = VSCreate(zone, format, args);
  va_end(args);
  return buffer;
}

char* OS::VSCreate(Zone* zone, const char* format, va_list args) {
  // Measure.
  va_list measure_args;
  va_copy(measure_args, args);
  intptr_t len = Utils::VSNPrint(nullptr, 0, format, measure_args);
  va_end(measure_args);

  char* buffer;
  if (zone) {
    buffer = zone->Alloc<char>(len + 1);
  } else {
    buffer = reinterpret_cast<char*>(malloc(len + 1));
  }
  ASSERT(buffer != nullptr);

  // Print.
  va_list print_args;
  va_copy(print_args, args);
  Utils::VSNPrint(buffer, len + 1, format, print_args);
  va_end(print_args);
  return buffer;
}

bool OS::ParseInitialInt64(const char* str, int64_t* value, char** end) {
  ASSERT(str != nullptr && strlen(str) > 0 && value != nullptr &&
         end != nullptr);
  int32_t base = 10;
  int i = 0;
  if (str[0] == '-') {
    i = 1;
  } else if (str[0] == '+') {
    i = 1;
  }
  if ((str[i] == '0') && (str[i + 1] == 'x' || str[i + 1] == 'X') &&
      (str[i + 2] != '\0')) {
    base = 16;
  }
  errno = 0;
  if (base == 16) {
    // Unsigned 64-bit hexadecimal integer literals are allowed but
    // immediately interpreted as signed 64-bit integers.
    *value = static_cast<int64_t>(strtoull(str, end, base));
  } else {
    *value = strtoll(str, end, base);
  }
  return (errno == 0) && (*end != str);
}

void OS::RegisterCodeObservers() {
#ifndef PRODUCT
  if (FLAG_generate_perf_events_symbols) {
    CodeObservers::Register(new PerfCodeObserver);
  }
#endif  // !PRODUCT
}

void OS::PrintErr(const char* format, ...) {
  va_list args;
  va_start(args, format);
  if (FLAG_android_log_to_stderr) {
    vfprintf(stderr, format, args);
  } else {
    // Forward to the Android log for remote access.
    __android_log_vprint(ANDROID_LOG_ERROR, "DartVM", format, args);
  }
  va_end(args);
}

void OS::Init() {
  // Calling tzset() is only necessary in Android API version 25 or earlier.
  if (android_get_device_api_level() < 26) {
    // In API version 25, calling tzset() results in a ~0.5% increase in
    // Flutter startup latency. In API version 31, calling tzset() results in
    // a >25% increase in startup latency.
    tzset();
  }
}

void OS::Cleanup() {}

void OS::PrepareToAbort() {}

void OS::Abort() {
  PrepareToAbort();
  abort();
}

void OS::Exit(int code) {
  exit(code);
}

// Used to choose between Elf32/Elf64 types based on host archotecture bitsize.
#if defined(ARCH_IS_64_BIT)
#define ElfW(Type) Elf64_##Type
#else
#define ElfW(Type) Elf32_##Type
#endif

OS::BuildId OS::GetAppBuildId(const uint8_t* snapshot_instructions) {
  // First return the build ID information from the instructions image if
  // available.
  const Image instructions_image(snapshot_instructions);
  if (auto* const image_build_id = instructions_image.build_id()) {
    return {instructions_image.build_id_length(), image_build_id};
  }
  const uint8_t* dso_base = GetAppDSOBase(snapshot_instructions);
  const ElfW(Ehdr) & elf_header =
      *reinterpret_cast<const ElfW(Ehdr)*>(dso_base);
  const ElfW(Phdr)* const phdr_array =
      reinterpret_cast<const ElfW(Phdr)*>(dso_base + elf_header.e_phoff);
  for (intptr_t i = 0; i < elf_header.e_phnum; i++) {
    const ElfW(Phdr) & header = phdr_array[i];
    if (header.p_type != PT_NOTE) continue;
    if ((header.p_flags & PF_R) != PF_R) continue;
    const uint8_t* const note_addr = dso_base + header.p_vaddr;
    const Elf32_Nhdr& note_header =
        *reinterpret_cast<const Elf32_Nhdr*>(note_addr);
    if (note_header.n_type != NT_GNU_BUILD_ID) continue;
    const char* const note_contents =
        reinterpret_cast<const char*>(note_addr + sizeof(Elf32_Nhdr));
    // The note name contains the null terminator as well.
    if (note_header.n_namesz != strlen(ELF_NOTE_GNU) + 1) continue;
    if (strncmp(ELF_NOTE_GNU, note_contents, note_header.n_namesz) == 0) {
      return {static_cast<intptr_t>(note_header.n_descsz),
              reinterpret_cast<const uint8_t*>(note_contents +
                                               note_header.n_namesz)};
    }
  }
  return {0, nullptr};
}

}  // namespace dart

#endif  // defined(DART_HOST_OS_ANDROID)
