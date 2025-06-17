// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include "vm/mach_o.h"

#if defined(DART_PRECOMPILER)

#include <utility>

#include "openssl/sha.h"
#include "platform/mach_o.h"
#include "platform/unwinding_records.h"
#include "vm/dwarf.h"
#include "vm/dwarf_so_writer.h"
#include "vm/hash_map.h"
#include "vm/os.h"
#include "vm/unwinding_records.h"
#include "vm/zone_text_buffer.h"

namespace dart {

static constexpr intptr_t kLinearInitValue = -1;

#define DEFINE_LINEAR_FIELD_METHODS(name)                                      \
  intptr_t name() const {                                                      \
    ASSERT(name##_ != kLinearInitValue);                                       \
    return name##_;                                                            \
  }                                                                            \
  bool name##_is_set() const {                                                 \
    return name##_ != kLinearInitValue;                                        \
  }                                                                            \
  void set_##name(intptr_t value) {                                            \
    ASSERT(value != kLinearInitValue);                                         \
    ASSERT_EQUAL(name##_, kLinearInitValue);                                   \
    name##_ = value;                                                           \
  }

#define DEFINE_LINEAR_FIELD(name) intptr_t name##_ = kLinearInitValue;

// Only subclasses of MachOContents that need to be distinguished dynamically
// via Is/As checks are listed here.
#define FOR_EACH_CHECKABLE_MACHO_CONTENTS_TYPE(V)                              \
  V(MachOCommand)                                                              \
  V(MachOSegment)                                                              \
  V(MachOSection)                                                              \
  V(MachOHeader)

#define DEFINE_TYPE_CHECK_FOR(Type)                                            \
  bool Is##Type() const override {                                             \
    return true;                                                               \
  }

// All concrete subclasses of MachOContents should go here:
#define FOR_EACH_CONCRETE_MACHO_CONTENTS_TYPE(V)                               \
  V(MachOHeader)                                                               \
  V(MachOSegment)                                                              \
  V(MachOSection)                                                              \
  V(MachOSymbolTable)                                                          \
  V(MachODynamicSymbolTable)                                                   \
  V(MachOUuid)                                                                 \
  V(MachOBuildVersion)                                                         \
  V(MachOIdDylib)                                                              \
  V(MachOLoadDylib)                                                            \
  V(MachOCodeSignature)

#define DECLARE_CONTENTS_TYPE_CLASS(Type) class Type;
FOR_EACH_CHECKABLE_MACHO_CONTENTS_TYPE(DECLARE_CONTENTS_TYPE_CLASS)
FOR_EACH_CONCRETE_MACHO_CONTENTS_TYPE(DECLARE_CONTENTS_TYPE_CLASS)
#undef DECLARE_CONTENTS_TYPE_CLASS

// The interface for a SharedObjectWriter::WriteStream with MachO-specific
// utility methods.
//
// If HasHashes() is true, the stream calculates and store hashes of
// written content up to the point that FinalizeHashedContent() is called.
class MachOWriteStream : public SharedObjectWriter::WriteStream {
  template <typename T, typename S>
  using only_if_unsigned = typename std::enable_if_t<std::is_unsigned_v<T>, S>;

 public:
  explicit MachOWriteStream(const MachOWriter& macho)
      : SharedObjectWriter::WriteStream(), macho_(macho) {}

  const MachOSegment& TextSegment() const;

  // Write methods that write values of a certain size out to disk.
  // The disk are written in host endian format, which matches the
  // header's magic value (since it is also written with this).
  void Write16(uword value) { WriteBytes(&value, sizeof(uint16_t)); }
  void Write32(uint32_t value) { WriteBytes(&value, sizeof(uint32_t)); }
  void Write64(uint64_t value) { WriteBytes(&value, sizeof(uint64_t)); }
  void WriteWord(compiler::target::uword value) {
    WriteBytes(&value, sizeof(compiler::target::uword));
  }

  // Write methods that force big endian output. Used in the code signature.
  void WriteBE16(uint16_t value) { Write16(Utils::HostToBigEndian16(value)); }
  void WriteBE32(uint32_t value) { Write32(Utils::HostToBigEndian32(value)); }
  void WriteBE64(uint64_t value) { Write64(Utils::HostToBigEndian64(value)); }

  // Many load commands have adjacent uint32_t fields that correspond to an
  // offset into the file and a number of bytes or objects to read starting
  // from that offset, so abstract that out to make such writes stand out.
  void WriteOffsetCount(uintptr_t offset, uintptr_t count) {
    ASSERT(Utils::IsUint(32, offset));
    Write32(offset);
    ASSERT(Utils::IsUint(32, count));
    Write32(count);
  }

  void WriteNullTerminatedCString(const char* str) {
    WriteBytes(str, strlen(str) + 1);
  }

  // Writes the first n bytes of the given string. If the string is shorter
  // than n bytes, then the remainder of the space is padded with '\0'.
  void WriteFixedLengthCString(const char* str, intptr_t n) {
    const intptr_t len = strlen(str);
    WriteBytes(str, n - len <= 0 ? n : len);
    for (intptr_t i = n - len; i > 0; --i) {
      WriteByte('\0');
    }
  }

  bool HasValueForLabel(intptr_t label, intptr_t* value) const override;

  // The maximum size of a chunk of hashed content.
  static constexpr intptr_t kChunkSize = 1 << 12;
  static_assert(Utils::IsPowerOfTwo(kChunkSize));

  // Used for cs_code_directory::hash_type.
  static constexpr uint8_t kHashType = mach_o::CS_HASHTYPE_SHA256;
  // used for cs_code_directory::hash_size.
  static constexpr uint8_t kHashSize = SHA256_DIGEST_LENGTH;

  // Whether or not this MachOWriter supports hashing content.
  virtual bool HasHashes() const = 0;
  // The number of hashes calculated from the hashed content.
  // Assumes the hashed content has already been finalized.
  virtual intptr_t num_hashes() const = 0;
  // Writes the calculated hashes to the stream.
  // Assumes the hashed content has already been finalized.
  virtual void WriteHashes() = 0;
  // Call once all content that should be hashed has been written to the stream.
  virtual void FinalizeHashedContent() = 0;

 protected:
  const MachOWriter& macho_;

 private:
  DISALLOW_COPY_AND_ASSIGN(MachOWriteStream);
};

// A MachOWriteStream that strictly delegates to the provided BaseWriteStream
// without any internal caching.
class NonHashingMachOWriteStream
    : public SharedObjectWriter::DelegatingWriteStream,
      public MachOWriteStream {
 public:
  explicit NonHashingMachOWriteStream(BaseWriteStream* stream,
                                      const MachOWriter& macho)
      : SharedObjectWriter::DelegatingWriteStream(stream, macho),
        MachOWriteStream(macho) {}

  intptr_t Position() const override {
    return SharedObjectWriter::DelegatingWriteStream::Position();
  }
  void WriteByte(const uint8_t value) override {
    SharedObjectWriter::DelegatingWriteStream::WriteByte(value);
  }
  void WriteBytes(const void* bytes, intptr_t len) override {
    SharedObjectWriter::DelegatingWriteStream::WriteBytes(bytes, len);
  }
  intptr_t Align(intptr_t alignment, intptr_t offset = 0) override {
    return SharedObjectWriter::DelegatingWriteStream::Align(alignment, offset);
  }
  bool HasValueForLabel(intptr_t label, intptr_t* value) const override {
    return MachOWriteStream::HasValueForLabel(label, value);
  }

  bool HasHashes() const override { return false; }
  intptr_t num_hashes() const override { UNREACHABLE(); }
  void WriteHashes() override { UNREACHABLE(); }
  void FinalizeHashedContent() override { UNREACHABLE(); }

 private:
  DISALLOW_COPY_AND_ASSIGN(NonHashingMachOWriteStream);
};

// A wrapper around an BaseWriteStream that calculates hashes for kChunkSize
// chunks being flushed.
//
// FinalizeHashedContent() is called after the last write of content that
// should be hashed; further writes skip the hashing process.
// (E.g., FinalizeHashes() is called before writing the code signature in
// a Mach-O file.)
class HashingMachOWriteStream : public BaseWriteStream,
                                public MachOWriteStream {
 public:
  HashingMachOWriteStream(Zone* zone,
                          BaseWriteStream* stream,
                          const MachOWriter& macho)
      : BaseWriteStream(stream->initial_size()),
        MachOWriteStream(macho),
        zone_(zone),
        wrapped_stream_(stream),
        hashes_(zone, SHA256_DIGEST_LENGTH) {
    // So that we can use the underlying stream's Align, as all alignments
    // will be less than or equal to this alignment.
    ASSERT(Utils::IsAligned(stream->Position(), macho_.page_size()));
  }

  ~HashingMachOWriteStream() {
    // Hashed content should always been finalized earlier so the
    // hashes can be retrieved before destruction.
    ASSERT(!hashing_);
    Flush(/*chunks_only=*/false);  // Flush all bytes.
    ASSERT_EQUAL(BaseWriteStream::Position(), 0);
  }

  intptr_t Position() const override {
    return flushed_size_ + BaseWriteStream::Position();
  }
  void WriteByte(const uint8_t value) override {
    BaseWriteStream::WriteByte(value);
  }
  void WriteBytes(const void* bytes, intptr_t len) override {
    BaseWriteStream::WriteBytes(bytes, len);
  }
  intptr_t Align(intptr_t alignment, intptr_t offset = 0) override {
    ASSERT(Utils::IsPowerOfTwo(alignment));
    ASSERT(alignment <= macho_.page_size());
    return BaseWriteStream::Align(alignment, offset);
  }

  bool HasHashes() const override { return true; }
  intptr_t num_hashes() const override {
    ASSERT(!hashing_);  // Don't allow uses until hashes are finalized.
    return num_hashes_;
  }
  void WriteHashes() override {
    ASSERT(!hashing_);  // Don't allow uses until hashes are finalized.
    WriteBytes(hashes_.buffer(), num_hashes_ * kHashSize);
  }

  // First hashes and then flushes all data in the internal buffer. Afterwards,
  // the internal buffer is empty and future Flush() calls no longer perform
  // hashing before flushing to the wrapped stream.
  //
  // Changes current_ and flushed_size_ accordingly.
  void FinalizeHashedContent() override {
    Flush(/*chunks_only=*/false);
    hashing_ = false;  // End of the hashed content.
    // The only content in the hashes buffer should be the hashes themselves.
    ASSERT_EQUAL(num_hashes_ * kHashSize, hashes_.Position());
  }

 private:
  // Hashes [count] bytes of [buffer_] in [kChunkSize]-sized chunks and
  // returns the number of bytes hashed.
  intptr_t Hash(intptr_t count) {
    ASSERT(count >= 0);
    if (count > 0) {
      ASSERT(count <= BaseWriteStream::Position());
      for (intptr_t offset = 0; offset < count; offset += kChunkSize) {
        const intptr_t len = Utils::Minimum(count - offset, kChunkSize);
        SHA256(buffer_ + offset, len, digest_);
        hashes_.WriteBytes(digest_, kHashSize);
        num_hashes_ += 1;
      }
    }
    return count;
  }

  // If hashing, then hash all complete chunks and, if [chunks_only] is false,
  // a final incomplete one, then flush all hashed bytes to the wrapped stream.
  // The internal buffer is then reset to contain only unhashed bytes (if any).
  //
  // If not hashing, then all cached content is flushed immediately.
  //
  // Changes current_ and flushed_size_ accordingly.
  void Flush(bool chunks_only) {
    intptr_t size_to_flush = BaseWriteStream::Position();
    if (hashing_) {
      intptr_t size_to_hash = size_to_flush;
      if (chunks_only) {
        size_to_hash -= size_to_hash % kChunkSize;
      }
      size_to_flush = Hash(size_to_hash);
    }
    FlushBytes(size_to_flush);
  }

  // Flushes the initial [count] bytes of [buffer_] to the wrapped stream.
  //
  // Changes current_ and flushed_size_ accordingly.
  void FlushBytes(intptr_t count) {
    ASSERT(count >= 0);
    if (count == 0) return;
    const intptr_t remaining = BaseWriteStream::Position() - count;
    ASSERT(remaining >= 0);
    wrapped_stream_->WriteBytes(buffer_, count);
    flushed_size_ += count;
    if (remaining > 0) {
      memmove(buffer_, buffer_ + count, remaining);
    }
    current_ = buffer_ + remaining;
  }

  void Realloc(intptr_t new_size) override {
    Flush(/*chunks_only=*/true);
    // Check whether there's enough space after flushing.
    if (new_size <= Remaining()) return;
    // There isn't, so realloc the buffer.
    const intptr_t old_offset = BaseWriteStream::Position();
    buffer_ = zone_->Realloc(buffer_, capacity_, new_size);
    capacity_ = buffer_ != nullptr ? new_size : 0;
    current_ = buffer_ != nullptr ? buffer_ + old_offset : nullptr;
  }

  void SetPosition(intptr_t value) override {
    // Make sure we're not trying to set the position to already-flushed data.
    ASSERT(value >= flushed_size_);
    BaseWriteStream::SetPosition(value - flushed_size_);
  }

  Zone* const zone_;
  BaseWriteStream* const wrapped_stream_;
  ZoneWriteStream hashes_;
  bool hashing_ = true;
  intptr_t flushed_size_ = 0;
  intptr_t num_hashes_ = 0;
  uint8_t digest_[kHashSize];  // Used for SHA256().

  DISALLOW_COPY_AND_ASSIGN(HashingMachOWriteStream);
};

// A superclass for all objects that represent some content in the MachO output.
class MachOContents : public ZoneAllocated {
 public:
  explicit MachOContents(bool needs_offset = true, bool in_segment = true)
      // Set the file offset and/or (relative) memory address to 0 if unneeded.
      : file_offset_(needs_offset ? kLinearInitValue : 0),
        memory_address_(in_segment ? kLinearInitValue : 0) {}
  virtual ~MachOContents() {}

  struct Visitor : public ValueObject {
   public:
    Visitor() {}
    virtual ~Visitor() {}

    virtual void Default(MachOContents* c) {}

#define DEFINE_VISIT_METHOD(Type)                                              \
  virtual void Visit##Type(Type* m) {                                          \
    Default(reinterpret_cast<MachOContents*>(m));                              \
  }
    FOR_EACH_CONCRETE_MACHO_CONTENTS_TYPE(DEFINE_VISIT_METHOD)
#undef DEFINE_VISIT_METHOD

   private:
    DISALLOW_COPY_AND_ASSIGN(Visitor);
  };

  virtual void Accept(Visitor* visitor) = 0;
  virtual void VisitChildren(Visitor* visitor) {}

  // Content methods.

  // Whether WriteSelf() for this object or any nested object writes content
  // to the file. For most objects, the file offset is set to 0 at construction
  // if no content is written by it or nested objects.
  //
  // Overwrite this if the computed file offset can be 0 (e.g., the header).
  virtual bool HasContents() const { return file_offset_ != 0; }

  // Returns the size written to disk by WriteSelf().
  //
  // Only needs to be overwritten for unallocated objects or objects where
  // the number of bytes written by WriteSelf() does not match SelfMemorySize().
  virtual intptr_t SelfFileSize() const {
    if (!HasContents()) return 0;
    return SelfMemorySize();
  }

  // Writes the file contents for this object to the stream.
  //
  // Note that this does not write the load command for a command, as that
  // is handled separately by MachOCommand::WriteLoadCommand().
  //
  // Only needs to be overwritten for objects with non-zero SelfFileSize().
  virtual void WriteSelf(MachOWriteStream* stream) const {
    ASSERT_EQUAL(SelfFileSize(), 0);
    return;
  }

  // Returns whether the contents of an object is a segment or contained within
  // a segment and thus has an assigned relative memory address. If it has none,
  // then the memory offset is set to 0 at construction.
  //
  // Note: While technically load commands are in a segment due to being in the
  // header, this returns false for commands that only generate load commands.
  //
  // Should be overwritten if a segment or segment-contained object has a
  // computed relative memory address of 0 (e.g., the header).
  virtual bool IsAllocated() const { return memory_address_ != 0; }

  // Returns the size allocated in the output's memory space for this object
  // without including any allocation for nested objects.
  //
  // Should be overridden for allocated objects.
  virtual intptr_t SelfMemorySize() const {
    if (!IsAllocated()) return 0;
    UNREACHABLE();
  }

  // Utility/miscellaneous methods.

#define DEFINE_BASE_TYPE_CHECKS(Type)                                          \
  Type* As##Type() {                                                           \
    return Is##Type() ? reinterpret_cast<Type*>(this) : nullptr;               \
  }                                                                            \
  const Type* As##Type() const {                                               \
    return const_cast<Type*>(const_cast<MachOContents*>(this)->As##Type());    \
  }                                                                            \
  virtual bool Is##Type() const { return false; }

  FOR_EACH_CHECKABLE_MACHO_CONTENTS_TYPE(DEFINE_BASE_TYPE_CHECKS)
#undef DEFINE_BASE_TYPE_CHECKS

  // Returns the alignment needed for the non-header contents.
  virtual intptr_t Alignment() const {
    // No need to override for non-allocated commands with no contents.
    ASSERT(!IsAllocated() && !HasContents());
    UNREACHABLE();
  }

  // The size of the contents written to disk by WriteSelf() for this
  // object and any nested subobjects.
  //
  // Should be overwritten for objects that can have different
  // file and memory sizes.
  virtual intptr_t FileSize() const {
    if (!HasContents()) return 0;
    ASSERT(IsAllocated());
    return MemorySize();
  }

  // The size of this object and any subobjects combined in the output's memory
  // space. Note that objects may have a different MemorySize() than FileSize()
  // (e.g., a segment that contains zerofill sections).
  //
  // Should be overridden when the object contains nested objects.
  virtual intptr_t MemorySize() const { return SelfMemorySize(); }

#define FOR_EACH_CONTENTS_LINEAR_FIELD(M)                                      \
  M(file_offset)                                                               \
  M(memory_address)

  FOR_EACH_CONTENTS_LINEAR_FIELD(DEFINE_LINEAR_FIELD_METHODS);

 private:
  FOR_EACH_CONTENTS_LINEAR_FIELD(DEFINE_LINEAR_FIELD);

#undef FOR_EACH_CONTENTS_LINEAR_FIELD

  DISALLOW_COPY_AND_ASSIGN(MachOContents);
};

// Each MachO command corresponds to two parts in the file contents:
// the load command in the header that describes how to load the command
// contents and the command contents somewhere after the header.
//
// The load command is written via WriteLoadCommand() while WriteSelf()
// handles writing the command contents.
//
// Each concrete subclass of MachOCommand should define
//   static constexpr uint32_t kCommandCode = ...
// with the appropriate mach_o::LC_* constant.
class MachOCommand : public MachOContents {
 public:
  explicit MachOCommand(intptr_t cmd,
                        bool needs_offset = true,
                        bool in_segment = true)
      : MachOContents(needs_offset, in_segment), cmd_(cmd) {
    ASSERT(Utils::IsUint(32, cmd));
  }

  DEFINE_TYPE_CHECK_FOR(MachOCommand)

  // Load command fields and methods.

  // The value identifying the type of section the load command represents.
  // Should be one of the LC_* constants in platform/mach_o.h.
  uint32_t cmd() const { return cmd_; }

  // The alignment expected for load commands.
  static constexpr intptr_t kLoadCommandAlignment = compiler::target::kWordSize;

  // The size of the load command representing this command in the header.
  //
  // Note that all load commands must have a size that is a multiple of
  // kLoadCommandAlignment, so padding may be required.
  virtual uint32_t cmdsize() const = 0;

  // Each load command has a common prefix, which is written by the
  // class's WriteLoadCommand. Call the base class's implementation
  // prior to writing the rest of the load command for the subclass.
  virtual void WriteLoadCommand(MachOWriteStream* stream) const {
    stream->Write32(cmd());
    stream->Write32(cmdsize());
  }

  // Only the offset within the header is defined since the file offset
  // and memory address for the load command can be derived from the
  // header's file offset and memory address using this offset.
#define FOR_EACH_COMMAND_LINEAR_FIELD(M) M(header_offset)

  FOR_EACH_COMMAND_LINEAR_FIELD(DEFINE_LINEAR_FIELD_METHODS);

 private:
  FOR_EACH_COMMAND_LINEAR_FIELD(DEFINE_LINEAR_FIELD);

#undef FOR_EACH_COMMAND_LINEAR_FIELD

 private:
  uint32_t cmd_;

  DISALLOW_COPY_AND_ASSIGN(MachOCommand);
};

class MachOSection : public MachOContents {
#if defined(TARGET_ARCH_IS_32_BIT)
  using SectionType = mach_o::section;
#else
  using SectionType = mach_o::section_64;
#endif

 public:
  MachOSection(Zone* zone,
               const char* name,
               intptr_t type = mach_o::S_REGULAR,
               intptr_t attributes = mach_o::S_NO_ATTRIBUTES,
               bool has_contents = true,
               intptr_t alignment = MachOWriter::kPageSize)
      : MachOContents(/*needs_offset=*/has_contents,
                      /*in_segment=*/true),
        name_(name),
        flags_(mach_o::SectionFlags(type, attributes)),
        alignment_(alignment),
        portions_(zone, 0) {
    ASSERT(strlen(name) <= sizeof(SectionType::sectname));
    ASSERT(Utils::IsPowerOfTwo(alignment));
    ASSERT_EQUAL(type & mach_o::SECTION_TYPE, static_cast<uint32_t>(type));
    ASSERT_EQUAL(attributes & mach_o::SECTION_ATTRIBUTES,
                 static_cast<uint32_t>(attributes));
    if (type == mach_o::S_ZEROFILL && type == mach_o::S_GB_ZEROFILL) {
      ASSERT(!has_contents);
    }
  }

  DEFINE_TYPE_CHECK_FOR(MachOSection)

  intptr_t Alignment() const override { return alignment_; }

  const char* name() const { return name_; }

  bool HasName(const char* name) const { return strcmp(name_, name) == 0; }

  struct Portion {
    void Write(MachOWriteStream* stream, intptr_t section_start) const {
      ASSERT(bytes != nullptr);
      if (relocations != nullptr) {
        const intptr_t address = section_start + offset;
        stream->WriteBytesWithRelocations(bytes, size, address, *relocations);
      } else {
        stream->WriteBytes(bytes, size);
      }
    }

    bool ContainsSymbols() const {
      return symbol_name != nullptr ||
             (symbols != nullptr && !symbols->is_empty());
    }

    intptr_t offset;
    const char* symbol_name;
    intptr_t label;
    const uint8_t* bytes;
    intptr_t size;
    const SharedObjectWriter::RelocationArray* relocations;
    const SharedObjectWriter::SymbolDataArray* symbols;

   private:
    DISALLOW_ALLOCATION();
  };

  const GrowableArray<Portion>& portions() const { return portions_; }

  void AddPortion(
      const uint8_t* bytes,
      intptr_t size,
      const SharedObjectWriter::RelocationArray* relocations = nullptr,
      const SharedObjectWriter::SymbolDataArray* symbols = nullptr,
      const char* symbol_name = nullptr,
      intptr_t label = 0) {
    // Any named portion should also have a valid symbol label.
    ASSERT(symbol_name == nullptr || label > 0);
    ASSERT(!HasContents() || bytes != nullptr);
    ASSERT(bytes != nullptr || relocations == nullptr);
    // Make sure all portions are consistent in containing bytes.
    ASSERT(portions_.is_empty() ||
           (portions_[0].bytes != nullptr) == (bytes != nullptr));
    intptr_t offset = 0;
    if (!portions_.is_empty()) {
      const auto& last = portions_.Last();
      offset = last.offset + last.size;
    }
    // Each portion is aligned within the section.
    offset = Utils::RoundUp(offset, Alignment());
    portions_.Add(
        {offset, symbol_name, label, bytes, size, relocations, symbols});
  }

  intptr_t SelfMemorySize() const override {
    const auto& last = portions_.Last();
    return last.offset + last.size;
  }

  void WriteSelf(MachOWriteStream* stream) const override {
    if (!HasContents()) return;
    for (const auto& portion : portions_) {
      // Each portion is aligned within the section.
      stream->Align(Alignment());
      ASSERT_EQUAL(stream->Position(), file_offset() + portion.offset);
      portion.Write(stream, memory_address());
    }
  }

  const Portion* FindPortion(const char* symbol_name) const {
    for (const auto& portion : portions_) {
      if (strcmp(symbol_name, portion.symbol_name) == 0) {
        return &portion;
      }
    }
    return nullptr;
  }

  bool ContainsSymbols() const {
    for (const auto& p : portions_) {
      if (p.ContainsSymbols()) return true;
    }
    return false;
  }

  void Accept(Visitor* visitor) override { visitor->VisitMachOSection(this); }

 private:
  uint32_t HeaderInfoSize() const { return sizeof(SectionType); }

  // Called during MachOSegment::WriteLoadCommand.
  void WriteHeaderInfo(MachOWriteStream* stream, const char* segname) const {
    auto const start = stream->Position();
    stream->WriteFixedLengthCString(name_, sizeof(SectionType::sectname));
    stream->WriteFixedLengthCString(segname, sizeof(SectionType::segname));
    // While
    stream->WriteWord(memory_address());
    stream->WriteWord(MemorySize());
    stream->Write32(file_offset());
    stream->Write32(Utils::ShiftForPowerOfTwo(Alignment()));
    stream->WriteOffsetCount(0, 0);  // No relocation entries.
    stream->Write32(flags_);
    // All reserved fields are 0 for our purposes.
    stream->Write32(0);  // reserved1
    stream->Write32(0);  // reserved2
#if defined(TARGET_ARCH_IS_64_BIT)
    stream->Write32(0);  // reserved3
#endif
    ASSERT_EQUAL(stream->Position(),
                 static_cast<intptr_t>(start + HeaderInfoSize()));
  }

  const char* const name_;
  const decltype(SectionType::flags) flags_ = 0;
  const intptr_t alignment_;
  GrowableArray<Portion> portions_;

  friend class MachOSegment;

  DISALLOW_COPY_AND_ASSIGN(MachOSection);
};

class MachOSegment : public MachOCommand {
#if defined(TARGET_ARCH_IS_32_BIT)
  using SegmentCommandType = mach_o::segment_command;
#else
  using SegmentCommandType = mach_o::segment_command_64;
#endif

 public:
#if defined(TARGET_ARCH_IS_32_BIT)
  static constexpr uint32_t kCommandCode = mach_o::LC_SEGMENT;
#else
  static constexpr uint32_t kCommandCode = mach_o::LC_SEGMENT_64;
#endif

  MachOSegment(Zone* zone,
               const char* name,
               intptr_t initial_vm_protection = mach_o::VM_PROT_READ,
               intptr_t max_vm_protection = mach_o::VM_PROT_READ)
      // We don't know if a segment has a file offset until we
      // know what it contains, so set it to 0 in ComputeOffsets()
      // if there are no contents.
      : MachOCommand(kCommandCode),
        name_(name),
        initial_vm_protection_(initial_vm_protection),
        max_vm_protection_(max_vm_protection),
        contents_(zone, 0) {
    ASSERT(Utils::IsInt(32, initial_vm_protection));
    ASSERT(Utils::IsInt(32, max_vm_protection));
    ASSERT(strlen(name) <= sizeof(SegmentCommandType::segname));
  }

  DEFINE_TYPE_CHECK_FOR(MachOSegment)

  const char* name() const { return name_; }
  const GrowableArray<MachOContents*>& contents() const { return contents_; }

  bool IsReadable() const {
    return (initial_vm_protection_ & mach_o::VM_PROT_READ) != 0;
  }
  bool IsWritable() const {
    return (initial_vm_protection_ & mach_o::VM_PROT_WRITE) != 0;
  }
  bool IsExecutable() const {
    return (initial_vm_protection_ & mach_o::VM_PROT_EXECUTE) != 0;
  }

  intptr_t Alignment() const override { return MachOWriter::kPageSize; }

  // The text segment has a file and memory offset of 0, so the superclass's
  // implementations give false negatives after ComputeOffsets.
  bool HasContents() const override { return next_contents_index_ > 0; }
  bool IsAllocated() const override { return true; }

  bool HasZerofillSections() const {
    return next_contents_index_ != contents_.length();
  }

  uint32_t cmdsize() const override {
    uword size = sizeof(SegmentCommandType);
    // The header information for sections is nested within the
    // segment load command.
    for (auto* const c : contents_) {
      if (auto* const s = c->AsMachOSection()) {
        size += s->HeaderInfoSize();
      }
    }
    ASSERT(Utils::IsUint(32, size));
    return size;
  }

  bool PadFileSizeToAlignment() const {
    // The linkedit segment should _not_ be padded to alignment, because
    // that means the code signature isn't the last contents of the file
    // when applicable.
    return !HasName(mach_o::SEG_LINKEDIT);
  }

  // Segments do not contain any header information, just nested content.
  intptr_t SelfMemorySize() const override { return 0; }

  intptr_t FileSize() const override {
    intptr_t file_size = SelfFileSize();
    for (auto* const c : contents_) {
      if (!c->HasContents()) continue;
      file_size = Utils::RoundUp(file_size, c->Alignment());
      file_size += c->FileSize();
    }
    if (PadFileSizeToAlignment()) {
      file_size = Utils::RoundUp(file_size, Alignment());
    }
    return file_size;
  }

  intptr_t UnpaddedMemorySize() const {
    intptr_t memory_size = SelfMemorySize();
    for (auto* const c : contents_) {
      ASSERT(c->IsAllocated());  // Segments never contain unallocated contents.
      memory_size = Utils::RoundUp(memory_size, c->Alignment());
      memory_size += c->MemorySize();
    }
    return memory_size;
  }

  intptr_t MemorySize() const override {
    return Utils::RoundUp(UnpaddedMemorySize(), Alignment());
  }

  // The initial segment of the Mach-O file always includes the header
  // as its first contents.
  bool IsInitial() const { return header() != nullptr; }

  // Returns the header if this is the initial segment (which contains it),
  // otherwise nullptr.
  const MachOHeader* header() const {
    return contents_.is_empty() ? nullptr : contents_[0]->AsMachOHeader();
  }

  bool HasName(const char* name) const { return strcmp(name_, name) == 0; }

  bool ContainsSymbols() const {
    for (auto* const c : contents_) {
      if (auto* const s = c->AsMachOSection()) {
        if (s->ContainsSymbols()) {
          return true;
        }
      }
    }
    return false;
  }

  void AddContents(MachOContents* c);

  bool IsDebugOnly() const {
    // Currently, the dwarf segment is the only debug-only info we add.
    return HasName(mach_o::SEG_DWARF);
  }

  void WriteLoadCommand(MachOWriteStream* stream) const override {
    MachOCommand::WriteLoadCommand(stream);
    stream->WriteFixedLengthCString(name_, sizeof(SegmentCommandType::segname));
    stream->WriteWord(memory_address());
    stream->WriteWord(MemorySize());
    stream->WriteWord(file_offset());
    // Only report the actual file size if there is non-header content.
    if (IsInitial() && next_contents_index_ == 1) {
      stream->WriteWord(0);
    } else {
      stream->WriteWord(FileSize());
    }
    stream->Write32(max_vm_protection_);
    stream->Write32(initial_vm_protection_);
    stream->Write32(NumSections());
    // The writer never uses segment flags.
    stream->Write32(0);
    // The load command for a segment also contains descriptions for its
    // sections instead of these being in separate load commands.
    for (auto* const c : contents_) {
      if (!c->IsMachOSection()) continue;
      c->AsMachOSection()->WriteHeaderInfo(stream, name_);
    }
  }

  MachOSection* FindSection(const char* name) const {
    for (auto* const c : contents_) {
      if (auto* const s = c->AsMachOSection()) {
        if (s->HasName(name)) return s;
      }
    }
    return nullptr;
  }

  intptr_t NumSections() const {
    intptr_t count = 0;
    for (auto* const c : contents_) {
      if (c->IsMachOSection()) {
        count += 1;
      }
    }
    return count;
  }

  void Accept(Visitor* visitor) override { visitor->VisitMachOSegment(this); }
  void VisitChildren(Visitor* visitor) override {
    for (auto* const c : contents_) {
      c->Accept(visitor);
    }
  }

 private:
  const char* const name_;
  bool has_contents_ = false;
  intptr_t next_contents_index_ = 0;
  mach_o::vm_prot_t initial_vm_protection_;
  mach_o::vm_prot_t max_vm_protection_;
  GrowableArray<MachOContents*> contents_;

  DISALLOW_COPY_AND_ASSIGN(MachOSegment);
};

class MachOUuid : public MachOCommand {
 public:
  static constexpr uint32_t kCommandCode = mach_o::LC_UUID;

  explicit MachOUuid(const void* bytes, intptr_t len)
      : MachOCommand(kCommandCode,
                     /*needs_offset=*/false,
                     /*in_segment=*/false),
        bytes_() {
    // Make sure the length of the byte buffer matches the UUID length, so
    // that the provided UUID isn't unexpectedly truncated or extended.
    ASSERT_EQUAL(len, sizeof(bytes_));
    memmove(bytes_, bytes, sizeof(bytes_));
  }

  uint32_t cmdsize() const override { return sizeof(mach_o::uuid_command); }

  void WriteLoadCommand(MachOWriteStream* stream) const override {
    MachOCommand::WriteLoadCommand(stream);
    stream->WriteBytes(bytes_, sizeof(bytes_));
  }

  void Accept(Visitor* visitor) override { visitor->VisitMachOUuid(this); }

 private:
  uint8_t bytes_[sizeof(mach_o::uuid_command::uuid)];
  DISALLOW_COPY_AND_ASSIGN(MachOUuid);
};

#define MACHO_XYZ_VERSION_ENCODING(x, y, z)                                    \
  static_cast<uint32_t>(((x) << 16) | ((y) << 8) | (z))

class MachOBuildVersion : public MachOCommand {
 public:
  static constexpr uint32_t kCommandCode = mach_o::LC_BUILD_VERSION;

  MachOBuildVersion()
      : MachOCommand(kCommandCode,
                     /*needs_offset=*/false,
                     /*in_segment=*/false) {}

  uint32_t cmdsize() const override {
    return sizeof(mach_o::build_version_command);
  }

  uint32_t platform() const {
#if defined(DART_TARGET_OS_MACOS_IOS)
    return mach_o::PLATFORM_IOS;
#elif defined(DART_TARGET_OS_MACOS)
    return mach_o::PLATFORM_MACOS;
#else
    return mach_o::PLATFORM_UNKNOWN;
#endif
  }

  uint32_t minos() const {
#if defined(DART_TARGET_OS_MACOS_IOS)
    // TODO(sstrickl): No minimum version for iOS currently defined.
    UNIMPLEMENTED();
#elif defined(DART_TARGET_OS_MACOS)
    return kMinMacOSVersion;
#else
    return 0;  // No version for the unknown platform.
#endif
  }

  uint32_t sdk() const {
#if defined(DART_TARGET_OS_MACOS_IOS)
    // TODO(sstrickl): No SDK version for iOS currently defined.
    UNIMPLEMENTED();
#elif defined(DART_TARGET_OS_MACOS)
    return kMacOSSdkVersion;
#else
    return 0;  // No version for the unknown platform.
#endif
  }

  void WriteLoadCommand(MachOWriteStream* stream) const override {
    MachOCommand::WriteLoadCommand(stream);
    stream->Write32(platform());
    stream->Write32(minos());
    stream->Write32(sdk());
    stream->Write32(0);  // No tool versions.
  }

  void Accept(Visitor* visitor) override {
    visitor->VisitMachOBuildVersion(this);
  }

 private:
  static constexpr auto kMinMacOSVersion = MACHO_XYZ_VERSION_ENCODING(15, 0, 0);
  static constexpr auto kMacOSSdkVersion = MACHO_XYZ_VERSION_ENCODING(15, 4, 0);

  DISALLOW_COPY_AND_ASSIGN(MachOBuildVersion);
};

class MachODylib : public MachOCommand {
 public:
  uint32_t cmdsize() const override {
    intptr_t size = NameOffset() + strlen(name_) + 1;
    return Utils::RoundUp(size, kLoadCommandAlignment);
  }

  void WriteLoadCommand(MachOWriteStream* stream) const override {
    MachOCommand::WriteLoadCommand(stream);
    stream->Write32(NameOffset());
    stream->Write32(timestamp_);
    stream->Write32(current_version_);
    stream->Write32(compatibility_version_);
    stream->WriteNullTerminatedCString(name_);
    stream->Align(kLoadCommandAlignment);
  }

  static constexpr auto kNoVersion = MACHO_XYZ_VERSION_ENCODING(0, 0, 0);

 protected:
  // This is really an abstract class, with concrete subclasses providing
  // the command code.
  MachODylib(intptr_t cmd,
             const char* name,
             intptr_t timestamp,
             intptr_t current_version = kNoVersion,
             intptr_t compatibility_version = kNoVersion)
      : MachOCommand(cmd,
                     /*needs_offset=*/false,
                     /*in_segment=*/false),
        name_(ASSERT_NOTNULL(name)),
        timestamp_(timestamp),
        current_version_(current_version),
        compatibility_version_(compatibility_version) {
    ASSERT(Utils::IsUint(32, timestamp));
    ASSERT(Utils::IsUint(32, current_version));
    ASSERT(Utils::IsUint(32, compatibility_version));
  }

 private:
  uint32_t NameOffset() const { return sizeof(mach_o::dylib_command); }

  const char* const name_;
  const uint32_t timestamp_;
  const uint32_t current_version_;
  const uint32_t compatibility_version_;

  DISALLOW_COPY_AND_ASSIGN(MachODylib);
};

class MachOIdDylib : public MachODylib {
 public:
  static constexpr uint32_t kCommandCode = mach_o::LC_ID_DYLIB;

  explicit MachOIdDylib(const char* name = kDefaultSnapshotName,
                        intptr_t current_version = kNoVersion,
                        intptr_t compatibility_version = kNoVersion)
      : MachODylib(kCommandCode,
                   name,
                   0,  // Snapshots aren't copied into user.
                   current_version,
                   compatibility_version) {}

  void Accept(Visitor* visitor) override { visitor->VisitMachOIdDylib(this); }

 private:
  static constexpr char kDefaultSnapshotName[] = "aot.snapshot";
  DISALLOW_COPY_AND_ASSIGN(MachOIdDylib);
};

class MachOLoadDylib : public MachODylib {
 public:
  static constexpr uint32_t kCommandCode = mach_o::LC_LOAD_DYLIB;

  static MachOLoadDylib* CreateLoadSystemDylib(Zone* zone) {
    return new (zone) MachOLoadDylib(kSystemDylibName, 0, kSystemCurrentVersion,
                                     kSystemCompatVersion);
  }

  void Accept(Visitor* visitor) override { visitor->VisitMachOLoadDylib(this); }

 private:
  MachOLoadDylib(const char* name,
                 intptr_t timestamp,
                 intptr_t current_version,
                 intptr_t compatibility_version)
      : MachODylib(kCommandCode,
                   name,
                   timestamp,
                   current_version,
                   compatibility_version) {}

  static constexpr char kSystemDylibName[] = "/usr/lib/libSystem.B.dylib";
  static constexpr auto kSystemCurrentVersion =
      MACHO_XYZ_VERSION_ENCODING(1351, 0, 0);
  static constexpr auto kSystemCompatVersion =
      MACHO_XYZ_VERSION_ENCODING(1, 0, 0);

  DISALLOW_COPY_AND_ASSIGN(MachOLoadDylib);
};

#undef MACHO_XYZ_VERSION_ENCODING

class MachOSymbolTable : public MachOCommand {
 public:
  static constexpr uint32_t kCommandCode = mach_o::LC_SYMTAB;

  explicit MachOSymbolTable(Zone* zone)
      : MachOCommand(kCommandCode),
        zone_(zone),
        strings_(zone),
        symbols_(zone, 0),
        by_label_index_(zone) {}

  class StringTable : public ValueObject {
   public:
    explicit StringTable(Zone* zone) : text_(zone), text_indices_(zone) {
      // Ensure the string containing a single space is always at index 0.
      const intptr_t index = Add(" ");
      ASSERT_EQUAL(index, 0);
      // Assign the empty string the index of the null byte in the
      // string added above.
      text_indices_.Insert({"", index + 1});
    }

    intptr_t Add(const char* str) {
      ASSERT(str != nullptr);
      if (auto const kv = text_indices_.Lookup(str)) {
        return kv->value;
      }
      intptr_t offset = text_.length();
      text_.AddString(str);
      text_.AddChar('\0');
      text_indices_.Insert({str, offset});
      return offset;
    }

    const char* At(intptr_t index) const {
      if (index >= text_.length()) return nullptr;
      return text_.buffer() + index;
    }

    intptr_t FileSize() const { return text_.length(); }

    void Write(MachOWriteStream* stream) const {
      stream->WriteBytes(text_.buffer(), text_.length());
    }

   private:
    ZoneTextBuffer text_;
    CStringIntMap text_indices_;
    DISALLOW_COPY_AND_ASSIGN(StringTable);
  };

  struct Symbol {
    Symbol(intptr_t n_idx,
           intptr_t n_type,
           intptr_t n_sect,
           intptr_t n_desc,
           uword n_value)
        : name_index(n_idx),
          type(n_type),
          section_index(n_sect),
          description(n_desc),
          value(n_value) {
      ASSERT(Utils::IsUint(32, n_idx));
      ASSERT(Utils::IsUint(8, n_type));
      ASSERT(Utils::IsUint(8, n_sect));
      ASSERT(Utils::IsUint(16, n_desc));
      ASSERT(Utils::IsUint(sizeof(compiler::target::uword) * kBitsPerByte,
                           n_value));
    }

    void Write(MachOWriteStream* stream) const {
      const intptr_t start = stream->Position();
      stream->Write32(name_index);
      stream->WriteByte(type);
      stream->WriteByte(section_index);
      stream->Write16(description);
      stream->WriteWord(value);
      ASSERT_EQUAL(stream->Position() - start, sizeof(mach_o::nlist));
    }

    // The index of the name in the symbol table's string table.
    uint32_t name_index;
    // See the mach_o::N_* constants for the encoding of this field.
    uint8_t type;
    // The section to which this symbol belongs if not equal to mach_o::NO_SECT.
    // The sections are indexed by their appearance in the load commands
    // (e.g., the first section of the first segment command that contains
    // sections has index 1, and the first section of the second segment command
    // that contains sections has index [k + 1] if the first segment contains
    // [k] sections).
    uint8_t section_index;
    // See the mach_o::N_* constants for the encoding of this field.
    uint16_t description;
    // For symbols where section_index != macho_o::NO_SECT, this is the section
    // offset until finalization, when it is converted to the offset into the
    // snapshot.
    compiler::target::uword value;

    DISALLOW_ALLOCATION();
  };

  const StringTable& strings() const { return strings_; }
  const GrowableArray<Symbol>& symbols() const { return symbols_; }
  DEBUG_ONLY(intptr_t max_label() const { return max_label_; })

  void AddSymbol(const char* name,
                 intptr_t type,
                 intptr_t section_index,
                 intptr_t description,
                 uword value,
                 intptr_t label = -1) {
    // Section symbols should always have labels, and other symbols
    // (including symbolic debugging symbols) do not.
    if ((type & mach_o::N_STAB) != 0) {
      ASSERT(label <= 0);
    } else {
      ASSERT_EQUAL((type & mach_o::N_TYPE) == mach_o::N_SECT, label > 0);
    }
    ASSERT(!file_offset_is_set());  // Can grow until offsets computed.
    auto const name_index = strings_.Add(name);
    ASSERT(*name == '\0' || name_index != 0);
    const intptr_t new_index = num_symbols();
    symbols_.Add({name_index, type, section_index, description, value});
    if (label > 0) {
      DEBUG_ONLY(max_label_ = max_label_ > label ? max_label_ : label);
      // Store an 1-based index since 0 is kNoValue for IntMap.
      by_label_index_.Insert(label, new_index + 1);
    }
  }

  const Symbol* FindLabel(intptr_t label) const {
    ASSERT(label > 0);
    // The stored index is 1-based.
    const intptr_t symbols_index = by_label_index_.Lookup(label) - 1;
    if (symbols_index < 0) return nullptr;  // Not found.
    return &symbols_[symbols_index];
  }

  void Initialize(const char* path,
                  const GrowableArray<MachOSection*>& sections,
                  bool is_stripped);

  void UpdateSectionIndices(const GrowableArray<intptr_t>& index_map) {
    const intptr_t map_size = index_map.length();
#if defined(DEBUG)
    for (intptr_t i = 0; i < map_size; i++) {
      const intptr_t new_index = index_map[i];
      ASSERT(Utils::IsUint(8, new_index));
      ASSERT(new_index < map_size);
      if (i == mach_o::NO_SECT) {
        ASSERT_EQUAL(new_index, mach_o::NO_SECT);
      } else {
        ASSERT(new_index != mach_o::NO_SECT);
      }
    }
#endif
    for (auto& symbol : symbols_) {
      const uint8_t old_index = symbol.section_index;
      ASSERT(old_index < map_size);
      symbol.section_index = index_map[old_index];
    }
  }

  void Finalize(const GrowableArray<uword>& address_map) {
    const intptr_t map_size = address_map.length();
#if defined(DEBUG)
    for (intptr_t i = 0; i < map_size; i++) {
      if (i == mach_o::NO_SECT) {
        // The entry for NO_SECT must be 0 so that symbols with that index,
        // like global symbols, are unchanged.
        ASSERT_EQUAL(address_map[mach_o::NO_SECT], 0);
      } else {
        // No valid section begins at the start of the snapshot.
        ASSERT(address_map[i] > 0);
      }
    }
#endif
    for (auto& symbol : symbols_) {
      ASSERT(symbol.section_index < map_size);
      symbol.value += address_map[symbol.section_index];
    }
  }

  uint32_t cmdsize() const override { return sizeof(mach_o::symtab_command); }

  intptr_t SelfMemorySize() const override {
    return SymbolsSize() + strings_.FileSize();
  }

  intptr_t Alignment() const override { return compiler::target::kWordSize; }

  void WriteLoadCommand(MachOWriteStream* stream) const override {
    MachOCommand::WriteLoadCommand(stream);
    stream->WriteOffsetCount(file_offset(), num_symbols());
    stream->WriteOffsetCount(file_offset() + SymbolsSize(),
                             strings_.FileSize());
  }

  void WriteSelf(MachOWriteStream* stream) const override {
    for (const auto& symbol : symbols_) {
      symbol.Write(stream);
    }
    strings_.Write(stream);
  }

  intptr_t num_symbols() const { return symbols_.length(); }

  void Accept(Visitor* visitor) override {
    visitor->VisitMachOSymbolTable(this);
  }

#define FOR_EACH_SYMBOL_TABLE_LINEAR_FIELD(M)                                  \
  M(num_local_symbols)                                                         \
  M(num_external_symbols)

  FOR_EACH_SYMBOL_TABLE_LINEAR_FIELD(DEFINE_LINEAR_FIELD_METHODS);

 private:
  intptr_t SymbolsSize() const { return num_symbols() * sizeof(mach_o::nlist); }

  Zone* const zone_;
  StringTable strings_;
  GrowableArray<Symbol> symbols_;
  // Maps symbol labels (positive integers) to indexes in symbols_.
  IntMap<intptr_t> by_label_index_;
  DEBUG_ONLY(intptr_t max_label_ = 0;)  // For consistency checks.

  FOR_EACH_SYMBOL_TABLE_LINEAR_FIELD(DEFINE_LINEAR_FIELD);
#undef FOR_EACH_SYMBOL_TABLE_LINEAR_FIELD

  DISALLOW_COPY_AND_ASSIGN(MachOSymbolTable);
};

class MachODynamicSymbolTable : public MachOCommand {
 public:
  static constexpr uint32_t kCommandCode = mach_o::LC_DYSYMTAB;

  explicit MachODynamicSymbolTable(const MachOSymbolTable& table)
      : MachOCommand(kCommandCode), table_(table) {}

  uint32_t cmdsize() const override { return sizeof(mach_o::dysymtab_command); }

  intptr_t Alignment() const override { return compiler::target::kWordSize; }

  void WriteLoadCommand(MachOWriteStream* stream) const override {
    MachOCommand::WriteLoadCommand(stream);
    // The symbol table contains local symbols and then external symbols.
    intptr_t index = 0;
    stream->WriteOffsetCount(index, table_.num_local_symbols());
    index += table_.num_local_symbols();
    stream->WriteOffsetCount(index, table_.num_external_symbols());
    index += table_.num_external_symbols();
    // No undefined symbols.
    stream->WriteOffsetCount(index, 0);
    // The rest of the fields are 0-filled.
    for (intptr_t i = 0; i < kUnusedOffsetCountPairs; ++i) {
      stream->WriteOffsetCount(0, 0);
    }
  }

  // Currently no contents are written to the linkedit segment, as the
  // only non-zero fields are indexes/counts into the symbol table.
  intptr_t SelfMemorySize() const override { return 0; }

  void Accept(Visitor* visitor) override {
    visitor->VisitMachODynamicSymbolTable(this);
  }

 private:
  static constexpr intptr_t kUnusedOffsetCountPairs = 6;

  const MachOSymbolTable& table_;
  DISALLOW_COPY_AND_ASSIGN(MachODynamicSymbolTable);
};

class MachOLinkEditData : public MachOCommand {
 public:
  uint32_t cmdsize() const override {
    return sizeof(mach_o::linkedit_data_command);
  }

  void WriteLoadCommand(MachOWriteStream* stream) const override {
    MachOCommand::WriteLoadCommand(stream);
    stream->WriteOffsetCount(file_offset(), FileSize());
  }

 protected:
  // This is really an abstract class, with concrete subclasses providing
  // the command code.
  explicit MachOLinkEditData(intptr_t cmd)
      : MachOCommand(cmd, /*needs_offset=*/true, /*in_segment=*/true) {}

 private:
  DISALLOW_COPY_AND_ASSIGN(MachOLinkEditData);
};

class MachOCodeSignature : public MachOLinkEditData {
 public:
  static constexpr uint32_t kCommandCode = mach_o::LC_CODE_SIGNATURE;

  explicit MachOCodeSignature(const char* identifier)
      : MachOLinkEditData(kCommandCode), identifier_(identifier) {}

  static constexpr intptr_t kHeaderAlignment = 8;
  static constexpr intptr_t kHashAlignment = 16;

  intptr_t Alignment() const override { return kHashAlignment; }

  intptr_t SelfMemorySize() const override {
    return DirectoryOffset() + DirectoryLength();
  }

  void WriteSelf(MachOWriteStream* stream) const override {
    // The code signature marks the end of the hashed content, as
    // it contains the hashes that ensure the previous content has
    // not been modified (modulo hash collisions).
    stream->FinalizeHashedContent();
    ASSERT_EQUAL(stream->num_hashes(), ExpectedNumHashes());
    const intptr_t start = stream->Position();
    // The superblob header, which includes a single blob index.
    stream->WriteBE32(mach_o::CSMAGIC_EMBEDDED_SIGNATURE);  // magic
    stream->WriteBE32(FileSize());                          // length
    stream->WriteBE32(1);                                   // count
    // Blob index for the code directory.
    stream->WriteBE32(mach_o::CSSLOT_CODEDIRECTORY);  // type
    stream->WriteBE32(DirectoryOffset());             // offset
    stream->Align(kHeaderAlignment);
    // Now the header for the code directory.
    ASSERT_EQUAL(stream->Position() - start, DirectoryOffset());
    const intptr_t directory_start = stream->Position();
    stream->WriteBE32(mach_o::CSMAGIC_CODEDIRECTORY);                // magic
    stream->WriteBE32(DirectoryLength());                            // length
    stream->WriteBE32(mach_o::CS_SUPPORTSEXECSEG);                   // version
    stream->WriteBE32(mach_o::CS_ADHOC | mach_o::CS_LINKER_SIGNED);  // flags
    stream->WriteBE32(HashOffset());
    stream->WriteBE32(IdentOffset());
    stream->WriteBE32(0);                     // num special slots (hashes)
    stream->WriteBE32(stream->num_hashes());  // num code slots (hashes)
    stream->WriteBE32(file_offset());         // code limit
    stream->WriteByte(MachOWriteStream::kHashSize);
    stream->WriteByte(MachOWriteStream::kHashType);
    stream->WriteByte(0);  // platform
    // The page size is represented by its base 2 logarithm.
    stream->WriteByte(Utils::ShiftForPowerOfTwo(MachOWriteStream::kChunkSize));
    stream->WriteBE32(0);  // spare2 (always 0)
    // version >= 0x20100 (CS_SUPPORTSSCATTER)
    stream->WriteBE32(0);  // scatter offset
    // version >= 0x20200 (CS_SUPPORTSTEAMID)
    stream->WriteBE32(0);  // teamid offset
    // version >= 0x20300 (CS_SUPPORTSCODELIMIT64)
    stream->WriteBE32(0);  // spare3 (always 0)
    stream->WriteBE64(0);  // code limit (64-bit)
    // version >= 0x20400 (CS_SUPPORTSEXECSEG)
    stream->WriteBE64(stream->TextSegment().file_offset());  // offset
    stream->WriteBE64(stream->TextSegment().FileSize());     // limit
    stream->WriteBE64(0);                                    // flags
    stream->Align(kHeaderAlignment);
    ASSERT_EQUAL(stream->Position() - directory_start, IdentOffset());
    stream->WriteFixedLengthCString(identifier_, strlen(identifier_) + 1);
    stream->Align(kHashAlignment);
    ASSERT_EQUAL(stream->Position() - directory_start, HashOffset());
    stream->WriteHashes();
    ASSERT_EQUAL(stream->Position() - directory_start, DirectoryLength());
  }

  void Accept(Visitor* visitor) override {
    visitor->VisitMachOCodeSignature(this);
  }

 private:
  // The offset of the code directory in the code signature.
  intptr_t DirectoryOffset() const {
    // A single blob index for the code directory.
    const intptr_t offset =
        sizeof(mach_o::cs_superblob) + sizeof(mach_o::cs_blob_index);
    return Utils::RoundUp(offset, kHeaderAlignment);
  }

  intptr_t DirectoryLength() const {
    return HashOffset() + ExpectedNumHashes() * MachOWriteStream::kHashSize;
  }

  // The offset of the identifier within the code directory.
  intptr_t IdentOffset() const {
    // Include the directory offset to ensure proper alignment, but the
    // returned value is relative to the code directory start.
    intptr_t signature_offset =
        DirectoryOffset() + sizeof(mach_o::cs_code_directory);
    return Utils::RoundUp(signature_offset, kHeaderAlignment) -
           DirectoryOffset();
  }

  // The offset of the list of hashes within the code directory.
  intptr_t HashOffset() const {
    // Include the directory offset to ensure proper alignment, but the
    // returned value is relative to the code directory start.
    const intptr_t signature_offset =
        DirectoryOffset() + IdentOffset() + strlen(identifier_) + 1;
    return Utils::RoundUp(signature_offset, kHashAlignment) - DirectoryOffset();
  }

  intptr_t ExpectedNumHashes() const {
    // The actual hashes are stored in the stream, which isn't available yet.
    // However, if the file offsets of the code signature has been computed, the
    // number of hashes that should be contained in the stream can be computed.
    const intptr_t chunk_size = MachOWriteStream::kChunkSize;
    return (file_offset() + chunk_size - 1) / chunk_size;
  }

  const char* const identifier_;

  DISALLOW_COPY_AND_ASSIGN(MachOCodeSignature);
};

// A representation of the header of the Mach-O file. This contains
// any commands that have load commands within the header.
class MachOHeader : public MachOContents {
#if defined(TARGET_ARCH_IS_32_BIT)
  using HeaderType = mach_o::mach_header;
#else
  using HeaderType = mach_o::mach_header_64;
#endif

  using SnapshotType = SharedObjectWriter::Type;

 public:
  MachOHeader(Zone* zone,
              SnapshotType type,
              bool is_stripped,
              const char* identifier,
              const char* path,
              Dwarf* dwarf)
      : MachOContents(),
        zone_(zone),
        type_(type),
        is_stripped_(is_stripped),
        identifier_(identifier != nullptr ? identifier : ""),
        path_(path),
        dwarf_(dwarf),
        commands_(zone, 0),
        full_symtab_(zone) {
#if defined(DART_TARGET_OS_MACOS)
    // A non-nullptr identifier must be provided for MacOS targets.
    ASSERT(identifier != nullptr);
#endif
    // Unstripped content must have DWARF information available.
    ASSERT(dwarf != nullptr || is_stripped_);
    // Only snapshots should be stripped.
    ASSERT(!is_stripped_ || type == SnapshotType::Snapshot);
  }

  DEFINE_TYPE_CHECK_FOR(MachOHeader)

  Zone* zone() const { return zone_; }
  const GrowableArray<MachOCommand*>& commands() const { return commands_; }
  const MachOSymbolTable& relocation_symbol_table() const {
    return full_symtab_;
  }
  const MachOSegment& text_segment() const {
    ASSERT(text_segment_ != nullptr);
    return *text_segment_;
  }

  intptr_t NumSections() const {
    intptr_t num_sections = 0;
    for (auto* const command : commands()) {
      if (auto* const s = command->AsMachOSegment()) {
        num_sections += s->NumSections();
      }
    }
    return num_sections;
  }

  // The contents of the header is always at offset/address 0, so the
  // superclass's check returns a false negative here after ComputeOffsets.
  bool HasContents() const override { return true; }
  bool IsAllocated() const override { return true; }
  intptr_t Alignment() const override { return compiler::target::kWordSize; }

  // The header uses the default MemorySize() implementation, because
  // VisitChildren() doesn't visit the load commands and so the header is
  // not considered to contain nested content.
  //
  // This should be used if the size of the header without the load commands
  // is desired.
  intptr_t SizeWithoutLoadCommands() const {
    const intptr_t size = sizeof(HeaderType);
    ASSERT(Utils::IsAligned(size, MachOCommand::kLoadCommandAlignment));
    return size;
  }

  intptr_t SelfMemorySize() const override {
    intptr_t size = SizeWithoutLoadCommands();
    for (auto* const command : commands_) {
      size += command->cmdsize();
    }
    return size;
  }

  uint32_t filetype() const {
    if (type_ == SnapshotType::Snapshot) {
      return mach_o::MH_DYLIB;
    }
    ASSERT(type_ == SnapshotType::DebugInfo);
    return mach_o::MH_DSYM;
  }

  uint32_t flags() const {
    if (type_ == SnapshotType::Snapshot) {
      return mach_o::MH_NOUNDEFS | mach_o::MH_DYLDLINK |
             mach_o::MH_NO_REEXPORTED_DYLIBS;
    }
    ASSERT(type_ == SnapshotType::DebugInfo);
    return 0;
  }

  mach_o::cpu_type_t cpu_type() const {
#if defined(TARGET_ARCH_X64)
    return mach_o::CPU_TYPE_X86_64;
#elif defined(TARGET_ARCH_ARM64)
    return mach_o::CPU_TYPE_ARM64;
#elif defined(TARGET_ARCH_IA32)
    return mach_o::CPU_TYPE_I386;
#elif defined(TARGET_ARCH_ARM)
    return mach_o::CPU_TYPE_ARM;
#else
    // This architecture doesn't have specific constants defined in
    // <mach/machine.h>, so just mark it as ANY since the snapshot
    // header check also catches architecture mismatches.
    return mach_o::CPU_TYPE_ANY;
#endif
  }

  mach_o::cpu_subtype_t cpu_subtype() const {
#if defined(TARGET_ARCH_X64)
    return mach_o::CPU_SUBTYPE_X86_64_ALL;
#elif defined(TARGET_ARCH_ARM64)
    return mach_o::CPU_SUBTYPE_ARM64_ALL;
#elif defined(TARGET_ARCH_IA32)
    return mach_o::CPU_SUBTYPE_I386_ALL;
#elif defined(TARGET_ARCH_ARM)
    return mach_o::CPU_SUBTYPE_ARM_ALL;
#else
    // This architecture doesn't have specific constants defined in
    // <mach/machine.h>, so just mark it as ANY since the snapshot
    // header check also catches architecture mismatches.
    return mach_o::CPU_SUBTYPE_ANY;
#endif
  }

  void WriteSelf(MachOWriteStream* stream) const override {
    intptr_t start = stream->Position();
    ASSERT_EQUAL(start, 0);
#if defined(TARGET_ARCH_IS_32_BIT)
    stream->Write32(mach_o::MH_MAGIC);
#else
    stream->Write32(mach_o::MH_MAGIC_64);
#endif
    stream->Write32(cpu_type());
    stream->Write32(cpu_subtype());
    stream->Write32(filetype());
    stream->Write32(commands_.length());
    uint32_t sizeofcmds = 0;
    for (auto* const command : commands_) {
      sizeofcmds += command->cmdsize();
    }
    stream->Write32(sizeofcmds);
    stream->Write32(flags());
#if !defined(TARGET_ARCH_IS_32_BIT)
    stream->Write32(0);  // Reserved field.
#endif
    ASSERT_EQUAL(stream->Position() - start, sizeof(HeaderType));
    for (auto* const command : commands_) {
      const intptr_t load_start = stream->Position();
      ASSERT_EQUAL(load_start, start + command->header_offset());
      command->WriteLoadCommand(stream);
      ASSERT_EQUAL(stream->Position() - load_start,
                   static_cast<intptr_t>(command->cmdsize()));
    }
  }

  // Returns the command with the given concrete subclass of MachOCommand
  // (that is, a subclass that defines a kCommandCode constant). Should only
  // be used for commands that appear at most once (e.g., not segments).
  template <typename T>
  T* FindCommand() const {
    return reinterpret_cast<T*>(FindCommand(T::kCommandCode));
  }

  // Returns the command with the given command code. Should only be used
  // for commands that appear at most once (e.g., not segments).
  MachOCommand* FindCommand(uint32_t cmd) const {
    MachOCommand* result = nullptr;
    for (auto* const command : commands_) {
      if (command->cmd() == cmd) {
        ASSERT(result == nullptr);
        result = command;
#if !defined(DEBUG)
        break;  // No checking, so don't continue iterating.
#endif
      }
    }
    return result;
  }

  // Returns whether there is a command has the given command code.
  bool HasCommand(uint32_t cmd) const {
    for (auto* const command : commands_) {
      if (command->cmd() == cmd) return true;
    }
    return false;
  }

  // Returns the segment with name [name] or nullptr if there is none.
  MachOSegment* FindSegment(const char* name) const {
    for (auto* const command : commands_) {
      if (auto* const s = command->AsMachOSegment()) {
        if (s->HasName(name)) return s;
      }
    }
    return nullptr;
  }

  // Returns the section with name [sectname] in segment [segname]
  // or nullptr if there is none.
  MachOSection* FindSection(const char* segname, const char* sectname) const {
    auto* const s = FindSegment(segname);
    if (s == nullptr) return nullptr;
    return s->FindSection(sectname);
  }

  MachOSegment* EnsureTextSegment() {
    if (text_segment_ == nullptr) {
      // Make sure it didn't get added outside this method.
      ASSERT(FindSegment(mach_o::SEG_TEXT) == nullptr);
      auto const vm_protection = mach_o::VM_PROT_READ | mach_o::VM_PROT_EXECUTE;
      text_segment_ = new (zone())
          MachOSegment(zone(), mach_o::SEG_TEXT, vm_protection, vm_protection);
      commands_.Add(text_segment_);
    }
    return text_segment_;
  }

  void Finalize();

  void Accept(Visitor* visitor) override { visitor->VisitMachOHeader(this); }

  // Since the header is in the initial segment, visiting the load commands
  // here and also visiting the header in MachOSegment::VisitChildren() would
  // cause a cycle if, say, Default() is overridden to be recursive.
  // Thus, the default VisitChildren implementation here does no recursion,
  void VisitChildren(Visitor* visitor) override {}
  void VisitSegments(Visitor* visitor) {
    for (auto* const c : commands_) {
      if (!c->IsMachOSegment()) continue;
      c->Accept(visitor);
    }
  }

 private:
  void GenerateUuid();
  void CreateBSS();
  void GenerateUnwindingInformation();
  void GenerateMiscellaneousCommands();
  void InitializeSymbolTables();
  void FinalizeDwarfSections();
  void FinalizeCommands();
  void ComputeOffsets();

  // Returns the symbol table that is included in the output, which
  // may or may not be the full symbol table.
  //
  // Returns nullptr if called before symbol table initialization.
  MachOSymbolTable* IncludedSymbolTable() {
    // True when the symbol tables haven't been initialized.
    if (full_symtab_.symbols().is_empty()) return nullptr;
    // The full symbol table is reused for unstripped contents.
    if (!is_stripped_) return &full_symtab_;
    return FindCommand<MachOSymbolTable>();
  }

  Zone* const zone_;
  const SnapshotType type_;
  // Used to determine whether to include non-global symbols in the
  // symbol table written to disk.
  bool const is_stripped_;
  // The identifier, used in the LC_ID_DYLIB command and the code signature.
  const char* const identifier_;
  // The absolute path, used to create an N_OSO symbolic debugging variable
  // in unstripped snapshots.
  const char* const path_;
  Dwarf* const dwarf_;
  GrowableArray<MachOCommand*> commands_;
  // Contains all symbols for relocation calculations.
  MachOSymbolTable full_symtab_;
  MachOSegment* text_segment_ = nullptr;

  DISALLOW_COPY_AND_ASSIGN(MachOHeader);
};

void MachOSegment::AddContents(MachOContents* c) {
  ASSERT(c != nullptr);
  // Segment contents are always allocated.
  ASSERT(c->IsAllocated());
  // The order of segment contents is as follows:
  // 1) The header (if this is the initial segment).
  // 2) Content-containing sections and commands (in the linkedit segment).
  // 3) Sections without contents like zerofill sections.
  if (c->IsMachOHeader()) {
    ASSERT(c->AsMachOHeader()->commands()[0] == this);
    contents_.InsertAt(0, c);
    next_contents_index_ += 1;
  } else if (c->HasContents()) {
    ASSERT_EQUAL(c->IsMachOCommand(), HasName(mach_o::SEG_LINKEDIT));
    contents_.InsertAt(next_contents_index_, c);
    next_contents_index_ += 1;
  } else {
    ASSERT(c->IsMachOSection());
    contents_.Add(c);
  }
}

bool MachOWriteStream::HasValueForLabel(intptr_t label, intptr_t* value) const {
  ASSERT(value != nullptr);
  const auto& header = macho_.header();
  if (label == SharedObjectWriter::kBuildIdLabel) {
    // Unlike ELF, the uuid is not in a MachO section and so can't have a symbol
    // assigned. Instead, we look up its load command offset in the header.
    auto* const uuid = header.FindCommand<MachOUuid>();
    if (uuid == nullptr) return false;
    *value = header.file_offset() + uuid->header_offset();
    return true;
  }
  const auto& symtab = header.relocation_symbol_table();
  auto* const symbol = symtab.FindLabel(label);
  if (symbol == nullptr) return false;
  *value = symbol->value;
  return true;
}

const MachOSegment& MachOWriteStream::TextSegment() const {
  return macho_.header().text_segment();
}

MachOWriter::MachOWriter(Zone* zone,
                         BaseWriteStream* stream,
                         Type type,
                         const char* id,
                         const char* path,
                         Dwarf* dwarf)
    : SharedObjectWriter(zone, stream, type, dwarf),
      header_(*new (zone)
                  MachOHeader(zone, type, IsStripped(dwarf), id, path, dwarf)) {
}

void MachOWriter::AddText(const char* name,
                          intptr_t label,
                          const uint8_t* bytes,
                          intptr_t size,
                          const ZoneGrowableArray<Relocation>* relocations,
                          const ZoneGrowableArray<SymbolData>* symbols) {
  auto* const text_segment = header_.EnsureTextSegment();
  auto* text_section = text_segment->FindSection(mach_o::SECT_TEXT);
  if (text_section == nullptr) {
    const bool has_contents = type_ == Type::Snapshot;
    const intptr_t attributes =
        mach_o::S_ATTR_PURE_INSTRUCTIONS | mach_o::S_ATTR_SOME_INSTRUCTIONS;
    text_section = new (zone()) MachOSection(
        zone(), mach_o::SECT_TEXT, mach_o::S_REGULAR, attributes, has_contents);
    text_segment->AddContents(text_section);
  }
  text_section->AddPortion(bytes, size, relocations, symbols, name, label);
}

void MachOWriter::AddROData(const char* name,
                            intptr_t label,
                            const uint8_t* bytes,
                            intptr_t size,
                            const ZoneGrowableArray<Relocation>* relocations,
                            const ZoneGrowableArray<SymbolData>* symbols) {
  // Const data goes in the text segment, not the data one.
  auto* const text_segment = header_.EnsureTextSegment();
  auto* const_section = text_segment->FindSection(mach_o::SECT_CONST);
  if (const_section == nullptr) {
    const bool has_contents = type_ == Type::Snapshot;
    const_section =
        new (zone()) MachOSection(zone(), mach_o::SECT_CONST, mach_o::S_REGULAR,
                                  mach_o::S_NO_ATTRIBUTES, has_contents);
    text_segment->AddContents(const_section);
  }
  const_section->AddPortion(bytes, size, relocations, symbols, name, label);
}

class WriteVisitor : public MachOContents::Visitor {
 public:
  explicit WriteVisitor(MachOWriteStream* stream) : stream_(stream) {}

  void Default(MachOContents* contents) override {
    if (!contents->HasContents()) return;
    stream_->Align(contents->Alignment());
    const intptr_t start = stream_->Position();
    ASSERT_EQUAL(start, contents->file_offset());
    contents->WriteSelf(stream_);
    ASSERT_EQUAL(stream_->Position() - start, contents->SelfFileSize());
    contents->VisitChildren(this);
    // Segments include post-nested content alignment.
    if (auto* const s = contents->AsMachOSegment()) {
      if (s->PadFileSizeToAlignment()) {
        stream_->Align(contents->Alignment());
      }
    }
    ASSERT_EQUAL(stream_->Position() - start, contents->FileSize());
  }

 private:
  MachOWriteStream* stream_;
  DISALLOW_COPY_AND_ASSIGN(WriteVisitor);
};

void MachOWriter::Finalize() {
  header_.Finalize();
  if (header_.HasCommand(MachOCodeSignature::kCommandCode)) {
    HashingMachOWriteStream wrapped(zone_, unwrapped_stream_, *this);
    WriteVisitor visitor(&wrapped);
    header_.VisitSegments(&visitor);
  } else {
    NonHashingMachOWriteStream wrapped(unwrapped_stream_, *this);
    WriteVisitor visitor(&wrapped);
    header_.VisitSegments(&visitor);
  }
}

void MachOHeader::Finalize() {
  // Generate the UUID now that we have all user-provided sections.
  GenerateUuid();

  // We add a BSS section for all Mach-O output with text sections, even in
  // the separate debugging information, to ensure that relocated addresses
  // are consistent between snapshots and the corresponding separate
  // debugging information.
  CreateBSS();

  // Generate appropriate unwinding information for the target platform,
  // for example, unwinding records on Windows.
  GenerateUnwindingInformation();

  FinalizeDwarfSections();

  // Create and initialize the dynamic and static symbol tables.
  InitializeSymbolTables();

  // Generate miscellenous load commands needed for the final output.
  GenerateMiscellaneousCommands();

  // Reorders the added commands as well as adding segments and commands
  // that must appear at the end of the file.
  FinalizeCommands();

  // Calculate file and memory offsets, and finalizes symbol values in any
  // symbol tables.
  ComputeOffsets();
}

void MachOWriter::AssertConsistency(const MachOWriter* snapshot,
                                    const MachOWriter* debug_info) {
#if defined(DEBUG)
  // For now, just check that the symbol information for both match
  // in that all labelled symbols used for relocation have the same
  // value.
  const auto& snapshot_symtab = snapshot->header().relocation_symbol_table();
  const auto& debug_info_symtab =
      debug_info->header().relocation_symbol_table();

  intptr_t max_label = snapshot_symtab.max_label();
  ASSERT_EQUAL(max_label, debug_info_symtab.max_label());
  for (intptr_t i = 1; i < max_label; ++i) {
    if (auto* const snapshot_symbol = snapshot_symtab.FindLabel(i)) {
      auto* const debug_info_symbol = debug_info_symtab.FindLabel(i);
      ASSERT(debug_info_symbol != nullptr);
      if (snapshot_symbol->value != debug_info_symbol->value) {
        FATAL("Snapshot: %s -> %" Px64 ", %s -> %" Px64 "",
              snapshot_symtab.strings().At(snapshot_symbol->name_index),
              static_cast<uint64_t>(snapshot_symbol->value),
              debug_info_symtab.strings().At(debug_info_symbol->name_index),
              static_cast<uint64_t>(debug_info_symbol->value));
      }
    } else {
      ASSERT(debug_info_symtab.FindLabel(i) == nullptr);
    }
  }
#endif
}

static uint32_t HashPortion(const MachOSection::Portion& portion) {
  if (portion.bytes == nullptr) return 0;
  const uint32_t hash = Utils::StringHash(portion.bytes, portion.size);
  // Ensure a non-zero return.
  return hash == 0 ? 1 : hash;
}

// For the UUID, we generate a 128-bit hash, where each 32 bits is a
// hash of the contents of the following segments in order:
//
// .text(VM) | .text(Isolate) | .rodata(VM) | .rodata(Isolate)
//
// Any component of the build ID which does not have an associated section
// in the output is kept as 0.
void MachOHeader::GenerateUuid() {
  // Not idempotent.
  ASSERT(!HasCommand(MachOUuid::kCommandCode));
  // Currently, we construct the UUID out of data from two different
  // sections in the text segment: the text section and the const section.
  auto* const text_segment = FindSegment(mach_o::SEG_TEXT);
  if (text_segment == nullptr) return;

  auto* const text_section = text_segment->FindSection(mach_o::SECT_TEXT);
  // If there is no text section, then a UUID is not needed, as it is only
  // used to symbolicize non-symbolic stack traces.
  if (text_section == nullptr) return;

  auto* const vm_instructions =
      text_section->FindPortion(kVmSnapshotInstructionsAsmSymbol);
  auto* const isolate_instructions =
      text_section->FindPortion(kIsolateSnapshotInstructionsAsmSymbol);
  // All MachO snapshots have at least one of the two instruction sections.
  ASSERT(vm_instructions != nullptr || isolate_instructions != nullptr);

  auto* const data_section = text_segment->FindSection(mach_o::SECT_CONST);
  auto* const vm_data =
      data_section == nullptr
          ? nullptr
          : data_section->FindPortion(kVmSnapshotDataAsmSymbol);
  auto* const isolate_data =
      data_section == nullptr
          ? nullptr
          : data_section->FindPortion(kIsolateSnapshotDataAsmSymbol);

  uint32_t hashes[4];
  hashes[0] = vm_instructions == nullptr ? 0 : HashPortion(*vm_instructions);
  hashes[1] =
      isolate_instructions == nullptr ? 0 : HashPortion(*isolate_instructions);
  hashes[2] = vm_data == nullptr ? 0 : HashPortion(*vm_data);
  hashes[3] = isolate_data == nullptr ? 0 : HashPortion(*isolate_data);

  auto* const uuid_command = new (zone()) MachOUuid(hashes, sizeof(hashes));
  commands_.Add(uuid_command);
}

void MachOHeader::CreateBSS() {
  // No text section means no BSS section.
  auto* const text_section = FindSection(mach_o::SEG_TEXT, mach_o::SECT_TEXT);
  ASSERT(text_section != nullptr);

  // Not idempotent. Currently the data segment only contains BSS data, so it
  // shouldn't already exist.
  ASSERT(FindSegment(mach_o::SEG_DATA) == nullptr);
  auto const vm_protection = mach_o::VM_PROT_READ | mach_o::VM_PROT_WRITE;
  auto* const data_segment = new (zone())
      MachOSegment(zone(), mach_o::SEG_DATA, vm_protection, vm_protection);
  commands_.Add(data_segment);

  auto* const bss_section =
      new (zone()) MachOSection(zone(), mach_o::SECT_BSS, mach_o::S_ZEROFILL,
                                mach_o::S_NO_ATTRIBUTES, /*has_contents=*/false,
                                /*alignment=*/compiler::target::kWordSize);
  data_segment->AddContents(bss_section);

  for (const auto& portion : text_section->portions()) {
    size_t size;
    const char* symbol_name;
    intptr_t label;
    // First determine whether this is the VM's text portion or the isolate's.
    if (strcmp(portion.symbol_name, kVmSnapshotInstructionsAsmSymbol) == 0) {
      size = BSS::kVmEntryCount * compiler::target::kWordSize;
      symbol_name = kVmSnapshotBssAsmSymbol;
      label = SharedObjectWriter::kVmBssLabel;
    } else if (strcmp(portion.symbol_name,
                      kIsolateSnapshotInstructionsAsmSymbol) == 0) {
      size = BSS::kIsolateGroupEntryCount * compiler::target::kWordSize;
      symbol_name = kIsolateSnapshotBssAsmSymbol;
      label = SharedObjectWriter::kIsolateBssLabel;
    } else {
      // Not VM or isolate text.
      UNREACHABLE();
    }

    // For the BSS section, we add the section symbols as local symbols in the
    // static symbol table, as these addresses are only used for relocation.
    // (This matches the behavior in the assembly output.)
    auto* symbols = new (zone_) SharedObjectWriter::SymbolDataArray(zone_, 1);
    symbols->Add({symbol_name, SharedObjectWriter::SymbolData::Type::Section, 0,
                  size, label});
    bss_section->AddPortion(/*bytes=*/nullptr, size, /*relocations=*/nullptr,
                            symbols);
  }
}

void MachOHeader::GenerateUnwindingInformation() {
#if !defined(TARGET_ARCH_IA32)
  // Unwinding information is added to the text segment in Mach-O files.
  // Thus, we need the size of the unwinding information even for debugging
  // information, since adding the unwinding information changes the memory size
  // of the initial text segment and thus changes the values for symbols
  // of sections in later segments.
  //
  // However, since the debugging information should never be loaded by
  // the Mach-O loader, we don't actually need to generate the instructions,
  // just use an appropriate zerofill section for it.
  const bool use_zerofill = type_ == SnapshotType::DebugInfo;
  auto const section_type =
      use_zerofill ? mach_o::S_ZEROFILL : mach_o::S_REGULAR;

#if defined(DART_TARGET_OS_MACOS)
  // TODO(dartbug.com/60307): Add compact unwind information.
  USE(section_type);
#else
  ASSERT(text_segment_ != nullptr);
  if (auto* const text_section =
          text_segment_->FindSection(mach_o::SECT_TEXT)) {
    ASSERT(use_zerofill || !text_segment_->HasZerofillSections());
    // Not idempotent.
    ASSERT(text_segment_->FindSection(mach_o::SECT_EH_FRAME) == nullptr);

    // For the __eh_frame section, the easiest way to determine the size is to
    // generate the contents and just discard them if using zerofill.
    GrowableArray<Dwarf::FrameDescriptionEntry> fdes(zone_, 0);
    for (const auto& portion : text_section->portions()) {
      ASSERT(portion.label != 0);
      fdes.Add({portion.label, portion.size});
    }

    ZoneWriteStream stream(zone(), DwarfSharedObjectStream::kInitialBufferSize);
    DwarfSharedObjectStream dwarf_stream(zone_, &stream);
    Dwarf::WriteCallFrameInformationRecords(&dwarf_stream, fdes);

    auto* const eh_frame = new (zone())
        MachOSection(zone(), mach_o::SECT_EH_FRAME, section_type,
                     mach_o::S_NO_ATTRIBUTES, /*has_contents=*/!use_zerofill,
                     /*alignment=*/compiler::target::kWordSize);
    eh_frame->AddPortion(use_zerofill ? nullptr : dwarf_stream.buffer(),
                         dwarf_stream.bytes_written(),
                         use_zerofill ? nullptr : dwarf_stream.relocations());
    text_segment_->AddContents(eh_frame);
  }
#endif  // defined(DART_TARGET_OS_MACOS)

#if defined(UNWINDING_RECORDS_WINDOWS_PRECOMPILER)
  // Append Windows unwinding instructions as a __unwind_info section at
  // the end of any executable segments.
  for (auto* const command : commands_) {
    if (auto* const segment = command->AsMachOSegment()) {
      if (segment->IsExecutable()) {
        ASSERT(use_zerofill || !segment->HasZerofillSections());
        // Not idempotent.
        ASSERT(segment->FindSection(mach_o::SECT_UNWIND_INFO) == nullptr);

        auto* const unwinding_records = new (zone()) MachOSection(
            zone(), mach_o::SECT_UNWIND_INFO, section_type,
            mach_o::S_NO_ATTRIBUTES,
            /*has_contents=*/!use_zerofill, compiler::target::kWordSize);
        const intptr_t records_size = UnwindingRecordsPlatform::SizeInBytes();
        const intptr_t section_start = Utils::RoundUp(
            segment->UnpaddedMemorySize(), unwinding_records->Alignment());
        const uint8_t* bytes = nullptr;
        if (!use_zerofill) {
          ZoneWriteStream stream(zone(), /*initial_size=*/records_size);
          uint8_t* unwinding_instructions =
              zone()->Alloc<uint8_t>(records_size);
          stream.WriteBytes(UnwindingRecords::GenerateRecordsInto(
                                section_start, unwinding_instructions),
                            records_size);
          ASSERT_EQUAL(records_size, stream.Position());
          bytes = stream.buffer();
        }
        unwinding_records->AddPortion(bytes, records_size);
        segment->AddContents(unwinding_records);
        ASSERT_EQUAL(section_start + records_size,
                     segment->UnpaddedMemorySize());
      }
    }
  }
#endif  // defined(DART_TARGET_OS_WINDOWS) && defined(TARGET_ARCH_IS_64_BIT)
#endif  // !defined(TARGET_ARCH_IA32)
}

void MachOHeader::GenerateMiscellaneousCommands() {
  // Not idempotent;
  ASSERT(!HasCommand(MachOBuildVersion::kCommandCode));
  ASSERT(!HasCommand(MachOIdDylib::kCommandCode));
  ASSERT(!HasCommand(MachOLoadDylib::kCommandCode));

  commands_.Add(new (zone_) MachOBuildVersion());
  if (type_ == SnapshotType::Snapshot) {
    commands_.Add(new (zone_) MachOIdDylib(identifier_));
#if defined(DART_TARGET_OS_MACOS) || defined(DART_TARGET_OS_MACOS_IOS)
    commands_.Add(MachOLoadDylib::CreateLoadSystemDylib(zone_));
#endif
  }
}

void MachOHeader::InitializeSymbolTables() {
  // Not idempotent.
  ASSERT_EQUAL(full_symtab_.num_symbols(), 0);
  ASSERT(!HasCommand(MachOSymbolTable::kCommandCode));

  // Grab all the sections in order.
  GrowableArray<MachOSection*> sections(zone_, 0);
  for (auto* const command : commands_) {
    // Should be run before ComputeOffsets.
    ASSERT(!command->HasContents() || !command->file_offset_is_set());
    if (auto* const s = command->AsMachOSegment()) {
      for (auto* const c : s->contents()) {
        if (auto* const section = c->AsMachOSection()) {
          sections.Add(section);
        }
      }
    }
  }

  // This symbol table is for the MachOWriter's internal use. All symbols
  // should be added to it so the writer can resolve relocations.
  full_symtab_.Initialize(path_, sections, /*is_stripped=*/false);
  auto* table = &full_symtab_;
  if (is_stripped_) {
    // Create a separate symbol table that is actually written to the output.
    // This one will only contain what's needed for the dynamic symbol table.
    auto* const table = new (zone()) MachOSymbolTable(zone());
    table->Initialize(path_, sections, is_stripped_);
  }
  commands_.Add(table);

  // For snapshots, include a dynamic symbol table as well.
  if (type_ == SnapshotType::Snapshot) {
    auto* const dynamic_symtab = new (zone()) MachODynamicSymbolTable(*table);
    commands_.Add(dynamic_symtab);
  }
}

void MachOHeader::FinalizeDwarfSections() {
  if (dwarf_ == nullptr) return;

  // Currently we only output DWARF information involving code.
#if defined(DEBUG)
  auto* const text_segment = FindSegment(mach_o::SEG_TEXT);
  ASSERT(text_segment != nullptr);
  ASSERT(text_segment->FindSection(mach_o::SECT_TEXT) != nullptr);
#endif

  // Create the DWARF segment, which should not already exist.
  ASSERT(FindSegment(mach_o::SEG_DWARF) == nullptr);
  auto const init_vm_protection = mach_o::VM_PROT_READ | mach_o::VM_PROT_WRITE;
  auto const max_vm_protection = init_vm_protection | mach_o::VM_PROT_EXECUTE;
  auto* const dwarf_segment = new (zone()) MachOSegment(
      zone(), mach_o::SEG_DWARF, init_vm_protection, max_vm_protection);
  commands_.Add(dwarf_segment);

  const intptr_t alignment = 1;  // No extra padding.
  auto add_debug = [&](const char* name,
                       const DwarfSharedObjectStream& stream) {
    ASSERT(!dwarf_segment->FindSection(name));
    auto* const section = new (zone())
        MachOSection(zone(), name, mach_o::S_REGULAR, mach_o::S_ATTR_DEBUG,
                     /*has_contents=*/true, alignment);
    section->AddPortion(stream.buffer(), stream.bytes_written(),
                        stream.relocations());
    dwarf_segment->AddContents(section);
  };

  {
    ZoneWriteStream stream(zone(), DwarfSharedObjectStream::kInitialBufferSize);
    DwarfSharedObjectStream dwarf_stream(zone_, &stream);
    dwarf_->WriteAbbreviations(&dwarf_stream);
    add_debug(mach_o::SECT_DEBUG_ABBREV, dwarf_stream);
  }

  {
    ZoneWriteStream stream(zone(), DwarfSharedObjectStream::kInitialBufferSize);
    DwarfSharedObjectStream dwarf_stream(zone_, &stream);
    dwarf_->WriteDebugInfo(&dwarf_stream);
    add_debug(mach_o::SECT_DEBUG_INFO, dwarf_stream);
  }

  {
    ZoneWriteStream stream(zone(), DwarfSharedObjectStream::kInitialBufferSize);
    DwarfSharedObjectStream dwarf_stream(zone_, &stream);
    dwarf_->WriteLineNumberProgram(&dwarf_stream);
    add_debug(mach_o::SECT_DEBUG_LINE, dwarf_stream);
  }
}

void MachOHeader::FinalizeCommands() {
  // Not idempotent.
  ASSERT(FindSegment(mach_o::SEG_LINKEDIT) == nullptr);
  ASSERT(!HasCommand(MachOCodeSignature::kCommandCode));

  intptr_t num_commands = commands_.length();
  // We shouldn't be writing empty Mach-O snapshots.
  ASSERT(num_commands != 0);
  GrowableArray<MachOCommand*> reordered_commands(zone_, num_commands);

  // Now do a single pass over the commands, sorting them into bins based on
  // the desired final ordering and also calculating a map from old section
  // indices in the old order to new section indices in the new order.

  // First, any commands that are only part of the header.
  GrowableArray<MachOCommand*> header_only_commands(zone_, 0);

  // Ensure the text segment is the initial segment. This means the
  // text segment contains the header in its file contents/memory space.
  MachOSegment* text_segment = text_segment_;
  // We should be writing instructions and/or const data.
  ASSERT(text_segment != nullptr);

  // Then all segments that have defined symbols. These segments
  // are present in both snapshots and separate debugging information,
  // and the symbols defined in these sections should have consistent
  // relocated memory addresses in both.
  GrowableArray<MachOSegment*> symbol_segments(zone_, 0);

  // Then all other segments added prior to calling this function.
  // These need to be before the linkedit segment, which is created
  // below, so that they are also protected by the code signature
  // (if there is one).
  GrowableArray<MachOSegment*> other_segments(zone_, 0);

  // Next comes any non-segment load commands that have allocated content
  // outside of the header like the symbol table. A linkedit segment
  // is created later to contain the non-header contents of these commands.
  GrowableArray<MachOCommand*> linkedit_commands(zone_, 0);

  // Maps segments to the section count and old initial section index for
  // that segment. (Sections are not reordered during this, so this is
  // all that's needed to calculate new section indices.)
  using SegmentMapTrait =
      RawPointerKeyValueTrait<const MachOSegment,
                              std::pair<intptr_t, intptr_t>>;
  DirectChainedHashMap<SegmentMapTrait> section_info(zone_, num_commands);
  intptr_t num_sections = 0;
  for (auto* const command : commands_) {
    // Check that we're not reordering after offsets have been computed.
    ASSERT(!command->HasContents() || !command->file_offset_is_set());
    if (auto* const s = command->AsMachOSegment()) {
      const intptr_t count = s->NumSections();
      if (count != 0) {
        // Section indices start from 1.
        section_info.Insert({s, {count, num_sections + 1}});
        num_sections += count;
      }
      if (s->HasName(mach_o::SEG_TEXT)) {
        ASSERT(text_segment == s);
      } else if (s->ContainsSymbols()) {
        symbol_segments.Add(s);
      } else {
        other_segments.Add(s);
      }
    } else if (!command->HasContents()) {
      header_only_commands.Add(command);
    } else {
      linkedit_commands.Add(command);
    }
  }

  // We should always have a symbol table, even in stripped files where
  // it only contains global exported symbols, which means there should
  // be a linkedit segment.
  ASSERT(!linkedit_commands.is_empty());
  auto* const linkedit_segment =
      new (zone_) MachOSegment(zone_, mach_o::SEG_LINKEDIT);
  num_commands += 1;
  for (auto* const c : linkedit_commands) {
    linkedit_segment->AddContents(c);
  }
  if (type_ == SnapshotType::Snapshot) {
    // Also include an embedded ad-hoc linker signed code signature as the
    // last contents of the linkedit segment (which is the last segment).
    auto* const signature = new (zone_) MachOCodeSignature(identifier_);
    linkedit_segment->AddContents(signature);
    linkedit_commands.Add(signature);
    num_commands += 1;
  }

  GrowableArray<MachOSegment*> segments(
      zone_, symbol_segments.length() + other_segments.length() + 2);
  // Put the text, data, and linkedit segments in the expected ordering.
  segments.Add(text_segment);
  segments.AddArray(symbol_segments);
  segments.AddArray(other_segments);
  segments.Add(linkedit_segment);

  // The initial segment in the file should have the header as its initial
  // contents. Since the header is not a section, this won't change the
  // section numbering.
  segments[0]->AddContents(this);

  // Now populate reordered_commands.
  reordered_commands.AddArray(header_only_commands);

  // While adding segments, also map old section indices to new ones. Include
  // a map of mach_o::NO_SECT to mach_o::NO_SECT so that changing the section
  // index on a non-section symbol is a no-op.
  GrowableArray<intptr_t> index_map(zone_, num_sections + 1);
  index_map.FillWith(mach_o::NO_SECT, 0, num_sections + 1);
  // Section indices start from 1.
  intptr_t current_section_index = 1;
  for (auto* const s : segments) {
    reordered_commands.Add(s);
    auto* const kv = section_info.Lookup(s);
    if (kv != nullptr) {
      const auto& [num_sections, old_start] = SegmentMapTrait::ValueOf(*kv);
      ASSERT(num_sections > 0);  // Otherwise it's not in the map.
      ASSERT(old_start != mach_o::NO_SECT);
      for (intptr_t i = 0; i < num_sections; ++i) {
        ASSERT(current_section_index != mach_o::NO_SECT);
        index_map[old_start + i] = current_section_index++;
      }
    }
  }
  reordered_commands.AddArray(linkedit_commands);

  // All sections should have been accounted for in the loops above as well as
  // the new linkedit segment (and, if applicable, the code signature).
  ASSERT_EQUAL(reordered_commands.length(), num_commands);
  // Replace the content of commands_ with the reordered commands.
  commands_.Clear();
  commands_.AddArray(reordered_commands);

  // This must be true for uses of the map to be correct.
  ASSERT_EQUAL(index_map[mach_o::NO_SECT], mach_o::NO_SECT);
#if defined(DEBUG)
  for (intptr_t i = 1; i < num_sections; ++i) {
    ASSERT(index_map[i] != mach_o::NO_SECT);
  }
#endif

  // Update the section indices of any section-owned symbols.
  full_symtab_.UpdateSectionIndices(index_map);
  auto* const table = IncludedSymbolTable();
  if (table != &full_symtab_) {
    ASSERT(is_stripped_);
    table->UpdateSectionIndices(index_map);
  }
}

struct ContentOffsetsVisitor : public MachOContents::Visitor {
  explicit ContentOffsetsVisitor(Zone* zone) : address_map(zone, 1) {
    // Add NO_SECT -> 0 mapping.
    address_map.Add(0);
  }

  void Default(MachOContents* contents) {
    ASSERT_EQUAL(contents->IsMachOHeader(), file_offset == 0);
    ASSERT_EQUAL(contents->IsMachOHeader(), memory_address == 0);
    // Increment the file and memory offsets by the appropriate amounts.
    if (contents->HasContents()) {
      file_offset = Utils::RoundUp(file_offset, contents->Alignment());
      contents->set_file_offset(file_offset);
      file_offset += contents->SelfFileSize();
    }
    if (contents->IsAllocated()) {
      memory_address = Utils::RoundUp(memory_address, contents->Alignment());
      contents->set_memory_address(memory_address);
      memory_address += contents->SelfMemorySize();
    }
    contents->VisitChildren(this);
    if (contents->HasContents()) {
      ASSERT_EQUAL(file_offset, contents->file_offset() + contents->FileSize());
    }
    if (contents->IsAllocated()) {
      ASSERT_EQUAL(memory_address,
                   contents->memory_address() + contents->MemorySize());
    }
  }

  void VisitMachOSegment(MachOSegment* segment) {
    ASSERT_EQUAL(segment->IsInitial(), file_offset == 0);
    ASSERT_EQUAL(segment->IsInitial(), memory_address == 0);
    // Segments are always allocated and we set the file offset even
    // when the segment doesn't actually write any contents.
    file_offset = Utils::RoundUp(file_offset, segment->Alignment());
    segment->set_file_offset(file_offset);
    file_offset += segment->SelfFileSize();
    memory_address = Utils::RoundUp(memory_address, segment->Alignment());
    segment->set_memory_address(memory_address);
    memory_address += segment->SelfMemorySize();
    segment->VisitChildren(this);
    if (segment->PadFileSizeToAlignment()) {
      file_offset = Utils::RoundUp(file_offset, segment->Alignment());
    }
    memory_address = Utils::RoundUp(memory_address, segment->Alignment());
    ASSERT_EQUAL(file_offset, segment->file_offset() + segment->FileSize());
    ASSERT_EQUAL(memory_address,
                 segment->memory_address() + segment->MemorySize());
  }

  void VisitMachOSection(MachOSection* section) {
    // Sections do not contain other sections, so the visitor can use the
    // default behavior without worrying about adding to the address map in
    // the wrong order.
    Visitor::VisitMachOSection(section);
    address_map.Add(section->memory_address());
  }

  // Maps indices of allocated sections in the section table to memory offsets.
  // Note that sections are 1-indexed, with 0 (NO_SECT) mapping to 0.
  GrowableArray<uword> address_map;
  intptr_t file_offset = 0;
  intptr_t memory_address = 0;

 private:
  DISALLOW_COPY_AND_ASSIGN(ContentOffsetsVisitor);
};

void MachOHeader::ComputeOffsets() {
  intptr_t header_offset = SizeWithoutLoadCommands();
  for (auto* const c : commands_) {
    ASSERT(
        Utils::IsAligned(header_offset, MachOCommand::kLoadCommandAlignment));
    c->set_header_offset(header_offset);
    header_offset += c->cmdsize();
  }

  ContentOffsetsVisitor visitor(zone());
  // All commands with non-header content should be part of a segment.
  // In addition, the header is visited during the initial segment.
  VisitSegments(&visitor);

  // Finalize the dynamic symbol table, now that the file offset for the
  // symbol table has been calculated.

  // Entry for NO_SECT + 1-indexed entries for sections.
  ASSERT_EQUAL(visitor.address_map.length(), NumSections() + 1);

  // Adjust addresses in symbol tables as we now have section memory offsets.
  full_symtab_.Finalize(visitor.address_map);
  auto* const table = IncludedSymbolTable();
  if (table != &full_symtab_) {
    ASSERT(is_stripped_);
    table->Finalize(visitor.address_map);
  }
}

void MachOSymbolTable::Initialize(const char* path,
                                  const GrowableArray<MachOSection*>& sections,
                                  bool is_stripped) {
  // Not idempotent.
  ASSERT(!num_local_symbols_is_set());

  // If symbolic debugging symbols are emitted, then any section
  // symbols are marked as alternate entries in favor of the symbolic
  // debugging symbols.
  const intptr_t desc = is_stripped ? 0 : mach_o::N_ALT_ENTRY;

  // For unstripped symbol tables, we do two initial passes. In the first
  // pass, we add section symbols for local static symbols.
  if (!is_stripped) {
    for (intptr_t i = 0, n = sections.length(); i < n; ++i) {
      auto* const section = sections[i];
      const intptr_t section_index = i + 1;  // 1-indexed, as 0 is NO_SECT.
      for (const auto& portion : section->portions()) {
        if (portion.symbols != nullptr) {
          for (const auto& symbol_data : *portion.symbols) {
            AddSymbol(symbol_data.name, mach_o::N_SECT, section_index, desc,
                      portion.offset + symbol_data.offset, symbol_data.label);
          }
        }
      }
    }

    // In the second pass, we add appropriate symbolic debugging symbols.
    using Type = SharedObjectWriter::SymbolData::Type;
    if (path != nullptr) {
      // The value of the OSO symbolic debugging symbol is the mtime of the
      // object file. However, clang may warn about a mismatch if this is not
      // 0 and differs from the actual mtime of the object file, so just use 0.
      AddSymbol(path, mach_o::N_OSO, /*section_index=*/0,
                /*description=*/1, /*value=*/0);
    }
    auto add_symbolic_debugging_symbols =
        [&](const char* name, Type type, intptr_t section_index,
            intptr_t offset, intptr_t size, bool is_global) {
          switch (type) {
            case Type::Function: {
              AddSymbol("", mach_o::N_BNSYM, section_index, /*description=*/0,
                        offset);
              AddSymbol(name, mach_o::N_FUN, section_index, /*description=*/0,
                        offset);
              // The size is output as an unnamed N_FUN symbol with no section
              // following the actual N_FUN symbol.
              AddSymbol("", mach_o::N_FUN, mach_o::NO_SECT, /*description=*/0,
                        size);
              AddSymbol("", mach_o::N_ENSYM, section_index, /*description=*/0,
                        offset + size);

              break;
            }
            case Type::Section:
            case Type::Object: {
              if (is_global) {
                AddSymbol(name, mach_o::N_GSYM, mach_o::NO_SECT,
                          /*description=*/0,
                          /*value=*/0);
              } else {
                AddSymbol(name, mach_o::N_STSYM, section_index,
                          /*description=*/0, offset);
              }
              break;
            }
          }
        };

    for (intptr_t i = 0, n = sections.length(); i < n; ++i) {
      auto* const section = sections[i];
      const intptr_t section_index = i + 1;  // 1-indexed, as 0 is NO_SECT.
      // We handle global symbols for text sections slightly differently than
      // those for other sections.
      const bool is_text_section = section->HasName(mach_o::SECT_TEXT);
      for (const auto& portion : section->portions()) {
        if (portion.symbol_name != nullptr) {
          // Matching the symbolic debugging symbols created for assembled
          // snapshots.
          auto const type = is_text_section ? Type::Function : Type::Section;
          // The "size" of a function symbol created for start of a text portion
          // is up to the first function symbol.
          auto const size = is_text_section && portion.symbols != nullptr
                                ? portion.symbols->At(0).offset
                                : portion.size;
          add_symbolic_debugging_symbols(portion.symbol_name, type,
                                         section_index, portion.offset, size,
                                         /*is_global=*/true);
        }
        if (portion.symbols != nullptr) {
          for (const auto& symbol_data : *portion.symbols) {
            add_symbolic_debugging_symbols(
                symbol_data.name, symbol_data.type, section_index,
                portion.offset + symbol_data.offset, symbol_data.size,
                /*is_global=*/false);
          }
        }
      }
    }
  }
  set_num_local_symbols(num_symbols());

  // In the final pass, we add external symbols for section global symbols
  // (so added to both stripped and unstripped symbol tables).
  for (intptr_t i = 0, n = sections.length(); i < n; ++i) {
    auto* const section = sections[i];
    const intptr_t section_index = i + 1;  // 1-indexed, as 0 is NO_SECT.
    for (const auto& portion : section->portions()) {
      if (portion.symbol_name != nullptr) {
        AddSymbol(portion.symbol_name, mach_o::N_SECT | mach_o::N_EXT,
                  section_index, desc, portion.offset, portion.label);
      }
    }
  }
  set_num_external_symbols(num_symbols() - num_local_symbols());
}

}  // namespace dart

#endif  // defined(DART_PRECOMPILER)
