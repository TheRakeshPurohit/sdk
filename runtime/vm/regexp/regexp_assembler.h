// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#ifndef RUNTIME_VM_REGEXP_REGEXP_ASSEMBLER_H_
#define RUNTIME_VM_REGEXP_REGEXP_ASSEMBLER_H_

#include "vm/object.h"

#if !defined(DART_PRECOMPILED_RUNTIME)
#include "vm/compiler/assembler/assembler.h"
#include "vm/compiler/backend/il.h"
#endif  // !defined(DART_PRECOMPILED_RUNTIME)

namespace dart {

// Utility function for the DotPrinter
void PrintUtf16(uint16_t c);

// Compares two-byte strings case insensitively as UCS2.
// Called from generated RegExp code.
extern "C" uword /*BoolPtr*/ DLRT_CaseInsensitiveCompareUCS2(
    uword /*StringPtr*/ str_raw,
    uword /*SmiPtr*/ lhs_index_raw,
    uword /*SmiPtr*/ rhs_index_raw,
    uword /*SmiPtr*/ length_raw);

// Compares two-byte strings case insensitively as UTF16.
// Called from generated RegExp code.
extern "C" uword /*BoolPtr*/ DLRT_CaseInsensitiveCompareUTF16(
    uword /*StringPtr*/ str_raw,
    uword /*SmiPtr*/ lhs_index_raw,
    uword /*SmiPtr*/ rhs_index_raw,
    uword /*SmiPtr*/ length_raw);

/// Convenience wrapper around a BlockEntryInstr pointer.
class BlockLabel : public ValueObject {
  // Used by the IR assembler.
 public:
  BlockLabel();
  ~BlockLabel() { ASSERT(!is_linked()); }

  intptr_t pos() const { return pos_; }
  bool is_bound() const { return is_bound_; }
  bool is_linked() const { return !is_bound_ && is_linked_; }
#if !defined(DART_PRECOMPILED_RUNTIME)
  JoinEntryInstr* block() const { return block_; }
#endif  // !defined(DART_PRECOMPILED_RUNTIME)

  void Unuse() {
    pos_ = -1;
    is_bound_ = false;
    is_linked_ = false;
  }

  void BindTo(intptr_t pos) {
    pos_ = pos;
#if !defined(DART_PRECOMPILED_RUNTIME)
    if (block_ != nullptr) block_->set_block_id(pos);
#endif  // !defined(DART_PRECOMPILED_RUNTIME)
    is_bound_ = true;
    is_linked_ = false;
    ASSERT(is_bound());
  }

  // Used by bytecode assembler to form a linked list out of
  // forward jumps to an unbound label.
  void LinkTo(intptr_t pos) {
#if !defined(DART_PRECOMPILED_RUNTIME)
    ASSERT(block_ == nullptr);
#endif
    ASSERT(!is_bound_);
    pos_ = pos;
    is_linked_ = true;
  }

  // Used by IR builder to mark block label as used.
  void SetLinked() {
#if !defined(DART_PRECOMPILED_RUNTIME)
    ASSERT(block_ != nullptr);
#endif
    if (!is_bound_) {
      is_linked_ = true;
    }
  }

 private:
  bool is_bound_ = false;
  bool is_linked_ = false;
  intptr_t pos_ = -1;
#if !defined(DART_PRECOMPILED_RUNTIME)
  JoinEntryInstr* block_ = nullptr;
#endif  // !defined(DART_PRECOMPILED_RUNTIME)
};

class RegExpMacroAssembler : public ZoneAllocated {
 public:
  // The implementation must be able to handle at least:
  static constexpr intptr_t kMaxRegister = (1 << 16) - 1;
  static constexpr intptr_t kMaxCPOffset = (1 << 15) - 1;
  static constexpr intptr_t kMinCPOffset = -(1 << 15);

  static constexpr intptr_t kTableSizeBits = 7;
  static constexpr intptr_t kTableSize = 1 << kTableSizeBits;
  static constexpr intptr_t kTableMask = kTableSize - 1;

  enum {
    kParamRegExpIndex = 0,
    kParamStringIndex,
    kParamStartOffsetIndex,
    kParamCount
  };

  enum IrregexpImplementation { kBytecodeImplementation, kIRImplementation };

  explicit RegExpMacroAssembler(Zone* zone);
  virtual ~RegExpMacroAssembler();
  // The maximal number of pushes between stack checks. Users must supply
  // kCheckStackLimit flag to push operations (instead of kNoStackLimitCheck)
  // at least once for every stack_limit() pushes that are executed.
  virtual intptr_t stack_limit_slack() = 0;
  virtual bool CanReadUnaligned() = 0;
  virtual void AdvanceCurrentPosition(intptr_t by) = 0;  // Signed cp change.
  virtual void AdvanceRegister(intptr_t reg, intptr_t by) = 0;  // r[reg] += by.
  // Continues execution from the position pushed on the top of the backtrack
  // stack by an earlier PushBacktrack(BlockLabel*).
  virtual void Backtrack() = 0;
  virtual void BindBlock(BlockLabel* label) = 0;
  virtual void CheckAtStart(BlockLabel* on_at_start) = 0;
  // Dispatch after looking the current character up in a 2-bits-per-entry
  // map.  The destinations vector has up to 4 labels.
  virtual void CheckCharacter(unsigned c, BlockLabel* on_equal) = 0;
  // Bitwise and the current character with the given constant and then
  // check for a match with c.
  virtual void CheckCharacterAfterAnd(unsigned c,
                                      unsigned and_with,
                                      BlockLabel* on_equal) = 0;
  virtual void CheckCharacterGT(uint16_t limit, BlockLabel* on_greater) = 0;
  virtual void CheckCharacterLT(uint16_t limit, BlockLabel* on_less) = 0;
  virtual void CheckGreedyLoop(BlockLabel* on_tos_equals_current_position) = 0;
  virtual void CheckNotAtStart(intptr_t cp_offset,
                               BlockLabel* on_not_at_start) = 0;
  virtual void CheckNotBackReference(intptr_t start_reg,
                                     bool read_backward,
                                     BlockLabel* on_no_match) = 0;
  virtual void CheckNotBackReferenceIgnoreCase(intptr_t start_reg,
                                               bool read_backward,
                                               bool unicode,
                                               BlockLabel* on_no_match) = 0;
  // Check the current character for a match with a literal character.  If we
  // fail to match then goto the on_failure label.  End of input always
  // matches.  If the label is null then we should pop a backtrack address off
  // the stack and go to that.
  virtual void CheckNotCharacter(unsigned c, BlockLabel* on_not_equal) = 0;
  virtual void CheckNotCharacterAfterAnd(unsigned c,
                                         unsigned and_with,
                                         BlockLabel* on_not_equal) = 0;
  // Subtract a constant from the current character, then and with the given
  // constant and then check for a match with c.
  virtual void CheckNotCharacterAfterMinusAnd(uint16_t c,
                                              uint16_t minus,
                                              uint16_t and_with,
                                              BlockLabel* on_not_equal) = 0;
  virtual void CheckCharacterInRange(uint16_t from,
                                     uint16_t to,  // Both inclusive.
                                     BlockLabel* on_in_range) = 0;
  virtual void CheckCharacterNotInRange(uint16_t from,
                                        uint16_t to,  // Both inclusive.
                                        BlockLabel* on_not_in_range) = 0;

  // The current character (modulus the kTableSize) is looked up in the byte
  // array, and if the found byte is non-zero, we jump to the on_bit_set label.
  virtual void CheckBitInTable(const TypedData& table,
                               BlockLabel* on_bit_set) = 0;

  // Checks for preemption and serves as an OSR entry.
  virtual void CheckPreemption(bool is_backtrack) {}

  // Checks whether the given offset from the current position is before
  // the end of the string.  May overwrite the current character.
  virtual void CheckPosition(intptr_t cp_offset, BlockLabel* on_outside_input) {
    LoadCurrentCharacter(cp_offset, on_outside_input, true);
  }
  // Check whether a standard/default character class matches the current
  // character. Returns false if the type of special character class does
  // not have custom support.
  // May clobber the current loaded character.
  virtual bool CheckSpecialCharacterClass(uint16_t type,
                                          BlockLabel* on_no_match) {
    return false;
  }
  virtual void Fail() = 0;
  // Check whether a register is >= a given constant and go to a label if it
  // is.  Backtracks instead if the label is nullptr.
  virtual void IfRegisterGE(intptr_t reg,
                            intptr_t comparand,
                            BlockLabel* if_ge) = 0;
  // Check whether a register is < a given constant and go to a label if it is.
  // Backtracks instead if the label is nullptr.
  virtual void IfRegisterLT(intptr_t reg,
                            intptr_t comparand,
                            BlockLabel* if_lt) = 0;
  // Check whether a register is == to the current position and go to a
  // label if it is.
  virtual void IfRegisterEqPos(intptr_t reg, BlockLabel* if_eq) = 0;
  virtual IrregexpImplementation Implementation() = 0;
  // The assembler is closed, iff there is no current instruction assigned.
  virtual bool IsClosed() const = 0;
  // Jump to the target label without setting it as the current instruction.
  virtual void GoTo(BlockLabel* to) = 0;
  virtual void LoadCurrentCharacter(intptr_t cp_offset,
                                    BlockLabel* on_end_of_input,
                                    bool check_bounds = true,
                                    intptr_t characters = 1) = 0;
  virtual void PopCurrentPosition() = 0;
  virtual void PopRegister(intptr_t register_index) = 0;
  // Prints string within the generated code. Used for debugging.
  virtual void Print(const char* str) = 0;
  // Prints all emitted blocks.
  virtual void PrintBlocks() = 0;
  // Pushes the label on the backtrack stack, so that a following Backtrack
  // will go to this label. Always checks the backtrack stack limit.
  virtual void PushBacktrack(BlockLabel* label) = 0;
  virtual void PushCurrentPosition() = 0;
  virtual void PushRegister(intptr_t register_index) = 0;
  virtual void ReadCurrentPositionFromRegister(intptr_t reg) = 0;
  virtual void ReadStackPointerFromRegister(intptr_t reg) = 0;
  virtual void SetCurrentPositionFromEnd(intptr_t by) = 0;
  virtual void SetRegister(intptr_t register_index, intptr_t to) = 0;
  // Return whether the matching (with a global regexp) will be restarted.
  virtual bool Succeed() = 0;
  virtual void WriteCurrentPositionToRegister(intptr_t reg,
                                              intptr_t cp_offset) = 0;
  virtual void ClearRegisters(intptr_t reg_from, intptr_t reg_to) = 0;
  virtual void WriteStackPointerToRegister(intptr_t reg) = 0;

  // Check that we are not in the middle of a surrogate pair.
  void CheckNotInSurrogatePair(intptr_t cp_offset, BlockLabel* on_failure);

  // Controls the generation of large inlined constants in the code.
  void set_slow_safe(bool ssc) { slow_safe_compiler_ = ssc; }
  bool slow_safe() { return slow_safe_compiler_; }

  enum GlobalMode {
    NOT_GLOBAL,
    GLOBAL,
    GLOBAL_NO_ZERO_LENGTH_CHECK,
    GLOBAL_UNICODE
  };
  // Set whether the regular expression has the global flag.  Exiting due to
  // a failure in a global regexp may still mean success overall.
  inline void set_global_mode(GlobalMode mode) { global_mode_ = mode; }
  inline bool global() { return global_mode_ != NOT_GLOBAL; }
  inline bool global_with_zero_length_check() {
    return global_mode_ == GLOBAL || global_mode_ == GLOBAL_UNICODE;
  }
  inline bool global_unicode() { return global_mode_ == GLOBAL_UNICODE; }

  Zone* zone() const { return zone_; }

 private:
  bool slow_safe_compiler_;
  GlobalMode global_mode_;
  Zone* zone_;
};

}  // namespace dart

#endif  // RUNTIME_VM_REGEXP_REGEXP_ASSEMBLER_H_
