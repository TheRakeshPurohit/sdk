// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#ifndef RUNTIME_VM_CONSTANTS_ARM_H_
#define RUNTIME_VM_CONSTANTS_ARM_H_

#ifndef RUNTIME_VM_CONSTANTS_H_
#error Do not include constants_arm.h directly; use constants.h instead.
#endif

#include "platform/assert.h"
#include "platform/globals.h"
#include "platform/utils.h"

#include "vm/constants_base.h"

namespace dart {

// LR register should not be used directly in handwritten assembly patterns,
// because it might contain return address. Instead use macross CLOBBERS_LR,
// SPILLS_RETURN_ADDRESS_FROM_LR_TO_REGISTER,
// RESTORES_RETURN_ADDRESS_FROM_REGISTER_TO_LR, SPILLS_LR_TO_FRAME,
// RESTORES_LR_FROM_FRAME, READS_RETURN_ADDRESS_FROM_LR,
// WRITES_RETURN_ADDRESS_TO_LR to get access to LR constant in a checked way.
//
// To prevent accidental use of LR constant we rename it to
// LR_DO_NOT_USE_DIRECTLY (while keeping the code in this file and other files
// which are permitted to access LR constant the same by defining LR as
// LR_DO_NOT_USE_DIRECTLY). You can also use LINK_REGISTER if you need
// to compare LR register code.
#define LR LR_DO_NOT_USE_DIRECTLY

#define R(reg) (static_cast<RegList>(1) << (reg))

// We support both VFPv3-D16 and VFPv3-D32 profiles, but currently only one at
// a time.
#if defined(DART_TARGET_OS_ANDROID) || defined(DART_TARGET_OS_LINUX)
#define VFPv3_D16
#elif defined(DART_TARGET_OS_MACOS_IOS) || defined(DART_TARGET_OS_WINDOWS)
#define VFPv3_D32
#else
#error Which VFP?
#endif

// The Linux/Android ABI and the iOS ABI differ in their choice of frame
// pointer, their treatment of R9, and the interprocedural stack alignment.

// EABI (Linux, Android, Windows)
// See "Procedure Call Standard for the ARM Architecture".
// R0-R1:  Argument / result / volatile
// R2-R3:  Argument / volatile
// R4-R10: Preserved
// R11:    Frame pointer
// R12:    Volatile
// R13:    Stack pointer
// R14:    Link register
// R15:    Program counter
// Stack alignment: 4 bytes always, 8 bytes at public interfaces

// Linux (Debian armhf), Windows and Android also differ in whether floating
// point arguments are passed in floating point registers. Linux and Windows
// use hardfp and Android uses softfp. See
// TargetCPUFeatures::hardfp_supported().

// iOS ABI
// See "iOS ABI Function Call Guide"
// R0-R1:  Argument / result / volatile
// R2-R3:  Argument / volatile
// R4-R6:  Preserved
// R7:     Frame pointer
// R8-R11: Preserved
// R12:    Volatile
// R13:    Stack pointer
// R14:    Link register
// R15:    Program counter
// Stack alignment: 4 bytes always, 4 bytes at public interfaces

// iOS passes floating point arguments in integer registers (softfp)

enum Register {
  R0 = 0,
  R1 = 1,
  R2 = 2,
  R3 = 3,
  R4 = 4,
  R5 = 5,  // PP
  R6 = 6,  // CODE_REG
  R7 = 7,  // FP on iOS, DISPATCH_TABLE_REG on non-iOS (AOT only)
  R8 = 8,
  R9 = 9,
  R10 = 10,  // THR
  R11 = 11,  // FP on non-iOS, DISPATCH_TABLE_REG on iOS (AOT only)
  R12 = 12,  // IP aka TMP
  R13 = 13,  // SP
  R14 = 14,  // LR
  R15 = 15,  // PC
  kNumberOfCpuRegisters = 16,
  kNoRegister = -1,  // Signals an illegal register.

// Aliases.
#if defined(DART_TARGET_OS_MACOS) || defined(DART_TARGET_OS_MACOS_IOS)
  FP = R7,
  NOTFP = R11,
#else
  FP = R11,
  NOTFP = R7,
#endif
  IP = R12,
  SP = R13,
  LR = R14,  // Note: direct access to this constant is not allowed. See above.
  PC = R15,
};

// Values for single-precision floating point registers.
enum SRegister {
  kNoSRegister = -1,
  S0 = 0,
  S1 = 1,
  S2 = 2,
  S3 = 3,
  S4 = 4,
  S5 = 5,
  S6 = 6,
  S7 = 7,
  S8 = 8,
  S9 = 9,
  S10 = 10,
  S11 = 11,
  S12 = 12,
  S13 = 13,
  S14 = 14,
  S15 = 15,
  S16 = 16,
  S17 = 17,
  S18 = 18,
  S19 = 19,
  S20 = 20,
  S21 = 21,
  S22 = 22,
  S23 = 23,
  S24 = 24,
  S25 = 25,
  S26 = 26,
  S27 = 27,
  S28 = 28,
  S29 = 29,
  S30 = 30,
  S31 = 31,
  kNumberOfSRegisters = 32,
};

// Values for double-precision floating point registers.
enum DRegister {
  kNoDRegister = -1,
  D0 = 0,
  D1 = 1,
  D2 = 2,
  D3 = 3,
  D4 = 4,
  D5 = 5,
  D6 = 6,
  D7 = 7,
  D8 = 8,
  D9 = 9,
  D10 = 10,
  D11 = 11,
  D12 = 12,
  D13 = 13,
  D14 = 14,
  D15 = 15,
#if defined(VFPv3_D16)
  kNumberOfDRegisters = 16,
  // Leaving these defined, but marking them as kNoDRegister to avoid polluting
  // other parts of the code with #ifdef's. Instead, query kNumberOfDRegisters
  // to see which registers are valid.
  D16 = kNoDRegister,
  D17 = kNoDRegister,
  D18 = kNoDRegister,
  D19 = kNoDRegister,
  D20 = kNoDRegister,
  D21 = kNoDRegister,
  D22 = kNoDRegister,
  D23 = kNoDRegister,
  D24 = kNoDRegister,
  D25 = kNoDRegister,
  D26 = kNoDRegister,
  D27 = kNoDRegister,
  D28 = kNoDRegister,
  D29 = kNoDRegister,
  D30 = kNoDRegister,
  D31 = kNoDRegister,
#else
  D16 = 16,
  D17 = 17,
  D18 = 18,
  D19 = 19,
  D20 = 20,
  D21 = 21,
  D22 = 22,
  D23 = 23,
  D24 = 24,
  D25 = 25,
  D26 = 26,
  D27 = 27,
  D28 = 28,
  D29 = 29,
  D30 = 30,
  D31 = 31,
  kNumberOfDRegisters = 32,
#endif
  // Number of D registers that overlap S registers.
  // One D register overlaps two S registers, so regardless of the numbers of D
  // registers, there are only 32 S registers that are overlapped.
  kNumberOfOverlappingDRegisters = 16,
};

enum QRegister {
  kNoQRegister = -1,
  Q0 = 0,
  Q1 = 1,
  Q2 = 2,
  Q3 = 3,
  Q4 = 4,
  Q5 = 5,
  Q6 = 6,
  Q7 = 7,
#if defined(VFPv3_D16)
  kNumberOfQRegisters = 8,
  Q8 = kNoQRegister,
  Q9 = kNoQRegister,
  Q10 = kNoQRegister,
  Q11 = kNoQRegister,
  Q12 = kNoQRegister,
  Q13 = kNoQRegister,
  Q14 = kNoQRegister,
  Q15 = kNoQRegister,
#else
  Q8 = 8,
  Q9 = 9,
  Q10 = 10,
  Q11 = 11,
  Q12 = 12,
  Q13 = 13,
  Q14 = 14,
  Q15 = 15,
  kNumberOfQRegisters = 16,
#endif
  // Number of Q registers that overlap S registers.
  // One Q register overlaps four S registers, so regardless of the numbers of Q
  // registers, there are only 32 S registers that are overlapped.
  kNumberOfOverlappingQRegisters = 8,
};

static inline DRegister EvenDRegisterOf(QRegister q) {
  return static_cast<DRegister>(q * 2);
}

static inline DRegister OddDRegisterOf(QRegister q) {
  return static_cast<DRegister>((q * 2) + 1);
}

static inline SRegister EvenSRegisterOf(DRegister d) {
#if defined(VFPv3_D32)
  // When we have 32 D registers, the S registers only overlap the first 16.
  // That is, there are only ever 32 S registers in any extension.
  ASSERT(d < D16);
#endif
  return static_cast<SRegister>(d * 2);
}

static inline SRegister OddSRegisterOf(DRegister d) {
#if defined(VFPv3_D32)
  ASSERT(d < D16);
#endif
  return static_cast<SRegister>((d * 2) + 1);
}

static inline QRegister QRegisterOf(DRegister d) {
  return static_cast<QRegister>(d / 2);
}
static inline QRegister QRegisterOf(SRegister s) {
  return static_cast<QRegister>(s / 4);
}
static inline DRegister DRegisterOf(SRegister s) {
  return static_cast<DRegister>(s / 2);
}

// Register aliases for floating point scratch registers.
const QRegister QTMP = Q7;                     // Overlaps with DTMP, STMP.
const DRegister DTMP = EvenDRegisterOf(QTMP);  // Overlaps with STMP.
const SRegister STMP DART_USED = EvenSRegisterOf(DTMP);

// Architecture independent aliases.
typedef QRegister FpuRegister;

const FpuRegister FpuTMP = QTMP;
const int kFpuRegisterSize = 16;
typedef simd128_value_t fpu_register_t;
const int kNumberOfFpuRegisters = kNumberOfQRegisters;
const FpuRegister kNoFpuRegister = kNoQRegister;

extern const char* const cpu_reg_names[kNumberOfCpuRegisters];
extern const char* const cpu_reg_abi_names[kNumberOfCpuRegisters];
extern const char* const fpu_reg_names[kNumberOfFpuRegisters];
extern const char* const fpu_s_reg_names[kNumberOfSRegisters];
extern const char* const fpu_d_reg_names[kNumberOfDRegisters];

// Register aliases.
const Register TMP = IP;            // Used as scratch register by assembler.
const Register TMP2 = kNoRegister;  // There is no second assembler temporary.
const Register PP = R5;  // Caches object pool pointer in generated code.
const Register DISPATCH_TABLE_REG = NOTFP;  // Dispatch table register.
const Register SPREG = SP;                  // Stack pointer register.
const Register FPREG = FP;                  // Frame pointer register.
const Register IC_DATA_REG = R9;            // ICData/MegamorphicCache register.
const Register ARGS_DESC_REG = R4;
const Register CODE_REG = R6;
// Set when calling Dart functions in JIT mode, used by LazyCompileStub.
const Register FUNCTION_REG = R0;
const Register THR = R10;  // Caches current thread in generated code.
const Register CALLEE_SAVED_TEMP = R8;

// R15 encodes APSR in the vmrs instruction.
const Register APSR = R15;

// ABI for catch-clause entry point.
const Register kExceptionObjectReg = R0;
const Register kStackTraceObjectReg = R1;

// ABI for write barrier stub.
const Register kWriteBarrierObjectReg = R1;
const Register kWriteBarrierValueReg = R0;
const Register kWriteBarrierSlotReg = R9;

// Common ABI for shared slow path stubs.
struct SharedSlowPathStubABI {
  static constexpr Register kResultReg = R0;
};

// ABI for instantiation stubs.
struct InstantiationABI {
  static constexpr Register kUninstantiatedTypeArgumentsReg = R3;
  static constexpr Register kInstantiatorTypeArgumentsReg = R2;
  static constexpr Register kFunctionTypeArgumentsReg = R1;
  static constexpr Register kResultTypeArgumentsReg = R0;
  static constexpr Register kResultTypeReg = R0;
  static constexpr Register kScratchReg = R8;
};

// Registers in addition to those listed in InstantiationABI used inside the
// implementation of the InstantiateTypeArguments stubs.
struct InstantiateTAVInternalRegs {
  // The set of registers that must be pushed/popped when probing a hash-based
  // cache due to overlap with the registers in InstantiationABI.
  static constexpr intptr_t kSavedRegisters =
#if defined(DART_PRECOMPILER)
      (1 << DISPATCH_TABLE_REG) |
#endif
      (1 << InstantiationABI::kUninstantiatedTypeArgumentsReg);

  // Additional registers used to probe hash-based caches.
  static constexpr Register kEntryStartReg = R9;
  static constexpr Register kProbeMaskReg = R4;
  static constexpr Register kProbeDistanceReg = DISPATCH_TABLE_REG;
  static constexpr Register kCurrentEntryIndexReg =
      InstantiationABI::kUninstantiatedTypeArgumentsReg;
};

// Registers in addition to those listed in TypeTestABI used inside the
// implementation of type testing stubs that are _not_ preserved.
struct TTSInternalRegs {
  static constexpr Register kInstanceTypeArgumentsReg = R4;
  static constexpr Register kScratchReg = R9;
  static constexpr Register kSubTypeArgumentReg = R3;
  static constexpr Register kSuperTypeArgumentReg = R8;

  // Must be pushed/popped whenever generic type arguments are being checked as
  // they overlap with registers in TypeTestABI.
  static constexpr intptr_t kSavedTypeArgumentRegisters =
      (1 << kSubTypeArgumentReg) | (1 << kSuperTypeArgumentReg);

  static constexpr intptr_t kInternalRegisters =
      ((1 << kInstanceTypeArgumentsReg) | (1 << kScratchReg) |
       (1 << kSubTypeArgumentReg) | (1 << kSuperTypeArgumentReg)) &
      ~kSavedTypeArgumentRegisters;
};

// Registers in addition to those listed in TypeTestABI used inside the
// implementation of subtype test cache stubs that are _not_ preserved.
struct STCInternalRegs {
  static constexpr Register kInstanceCidOrSignatureReg = R9;

  static constexpr intptr_t kInternalRegisters =
      (1 << kInstanceCidOrSignatureReg);
};

// Calling convention when calling TypeTestingStub and SubtypeTestCacheStub.
struct TypeTestABI {
  static constexpr Register kInstanceReg = R0;
  static constexpr Register kDstTypeReg = R8;
  static constexpr Register kInstantiatorTypeArgumentsReg = R2;
  static constexpr Register kFunctionTypeArgumentsReg = R1;
  static constexpr Register kSubtypeTestCacheReg = R3;
  static constexpr Register kScratchReg = R4;

  // For calls to SubtypeNTestCacheStub. Must not be the same as any non-scratch
  // register above.
  static constexpr Register kSubtypeTestCacheResultReg = kScratchReg;
  // For calls to InstanceOfStub.
  static constexpr Register kInstanceOfResultReg = kInstanceReg;

  static constexpr intptr_t kPreservedAbiRegisters =
      (1 << kInstanceReg) | (1 << kDstTypeReg) |
      (1 << kInstantiatorTypeArgumentsReg) | (1 << kFunctionTypeArgumentsReg);

  static constexpr intptr_t kNonPreservedAbiRegisters =
      TTSInternalRegs::kInternalRegisters |
      STCInternalRegs::kInternalRegisters | (1 << kSubtypeTestCacheReg) |
      (1 << kScratchReg) | (1 << kSubtypeTestCacheResultReg) | (1 << CODE_REG);

  static constexpr intptr_t kAbiRegisters =
      kPreservedAbiRegisters | kNonPreservedAbiRegisters;
};

// Calling convention when calling AssertSubtypeStub.
struct AssertSubtypeABI {
  static constexpr Register kSubTypeReg = R0;
  static constexpr Register kSuperTypeReg = R8;
  static constexpr Register kInstantiatorTypeArgumentsReg = R2;
  static constexpr Register kFunctionTypeArgumentsReg = R1;
  static constexpr Register kDstNameReg = R3;

  static constexpr intptr_t kAbiRegisters =
      (1 << kSubTypeReg) | (1 << kSuperTypeReg) |
      (1 << kInstantiatorTypeArgumentsReg) | (1 << kFunctionTypeArgumentsReg) |
      (1 << kDstNameReg);

  // No result register, as AssertSubtype is only run for side effect
  // (throws if the subtype check fails).
};

// ABI for InitStaticFieldStub.
struct InitStaticFieldABI {
  static constexpr Register kFieldReg = R2;
  static constexpr Register kResultReg = R0;
};

// Registers used inside the implementation of InitLateStaticFieldStub.
struct InitLateStaticFieldInternalRegs {
  static constexpr Register kAddressReg = R3;
  static constexpr Register kScratchReg = R4;
};

// ABI for InitInstanceFieldStub.
struct InitInstanceFieldABI {
  static constexpr Register kInstanceReg = R1;
  static constexpr Register kFieldReg = R2;
  static constexpr Register kResultReg = R0;
};

// Registers used inside the implementation of InitLateInstanceFieldStub.
struct InitLateInstanceFieldInternalRegs {
  static constexpr Register kAddressReg = R3;
  static constexpr Register kScratchReg = R4;
};

// ABI for LateInitializationError stubs.
struct LateInitializationErrorABI {
  static constexpr Register kFieldReg = R9;
};

// ABI for FieldAccessError stubs.
struct FieldAccessErrorABI {
  static constexpr Register kFieldReg = R9;
};

// ABI for ThrowStub.
struct ThrowABI {
  static constexpr Register kExceptionReg = R0;
};

// ABI for ReThrowStub.
struct ReThrowABI {
  static constexpr Register kExceptionReg = R0;
  static constexpr Register kStackTraceReg = R1;
};

// ABI for RangeErrorStub.
struct RangeErrorABI {
  static constexpr Register kLengthReg = R0;
  static constexpr Register kIndexReg = R1;
};

// ABI for AllocateObjectStub.
struct AllocateObjectABI {
  static constexpr Register kResultReg = R0;
  static constexpr Register kTypeArgumentsReg = R3;
  static constexpr Register kTagsReg = R2;
};

// ABI for AllocateClosureStub.
struct AllocateClosureABI {
  static constexpr Register kResultReg = AllocateObjectABI::kResultReg;
  static constexpr Register kFunctionReg = R1;
  static constexpr Register kContextReg = R2;
  static constexpr Register kInstantiatorTypeArgsReg = R3;
  static constexpr Register kScratchReg = R4;
};

// ABI for AllocateMintShared*Stub.
struct AllocateMintABI {
  static constexpr Register kResultReg = AllocateObjectABI::kResultReg;
  static constexpr Register kTempReg = R1;
};

// ABI for Allocate{Mint,Double,Float32x4,Float64x2}Stub.
struct AllocateBoxABI {
  static constexpr Register kResultReg = AllocateObjectABI::kResultReg;
  static constexpr Register kTempReg = R1;
};

// ABI for AllocateArrayStub.
struct AllocateArrayABI {
  static constexpr Register kResultReg = AllocateObjectABI::kResultReg;
  static constexpr Register kLengthReg = R2;
  static constexpr Register kTypeArgumentsReg = R1;
};

// ABI for AllocateRecordStub.
struct AllocateRecordABI {
  static constexpr Register kResultReg = AllocateObjectABI::kResultReg;
  static constexpr Register kShapeReg = R1;
  static constexpr Register kTemp1Reg = R2;
  static constexpr Register kTemp2Reg = R3;
};

// ABI for AllocateSmallRecordStub (AllocateRecord2, AllocateRecord2Named,
// AllocateRecord3, AllocateRecord3Named).
struct AllocateSmallRecordABI {
  static constexpr Register kResultReg = AllocateObjectABI::kResultReg;
  static constexpr Register kShapeReg = R1;
  static constexpr Register kValue0Reg = R2;
  static constexpr Register kValue1Reg = R3;
  static constexpr Register kValue2Reg = R4;
  static constexpr Register kTempReg = R9;
};

// ABI for AllocateTypedDataArrayStub.
struct AllocateTypedDataArrayABI {
  static constexpr Register kResultReg = AllocateObjectABI::kResultReg;
  static constexpr Register kLengthReg = R4;
};

// ABI for BoxDoubleStub.
struct BoxDoubleStubABI {
  static constexpr FpuRegister kValueReg = Q0;
  static constexpr Register kTempReg = R1;
  static constexpr Register kResultReg = R0;
};

// ABI for DoubleToIntegerStub.
struct DoubleToIntegerStubABI {
  static constexpr FpuRegister kInputReg = Q0;
  static constexpr Register kRecognizedKindReg = R0;
  static constexpr Register kResultReg = R0;
};

// ABI for SuspendStub (AwaitStub, AwaitWithTypeCheckStub, YieldAsyncStarStub,
// SuspendSyncStarAtStartStub, SuspendSyncStarAtYieldStub).
struct SuspendStubABI {
  static constexpr Register kArgumentReg = R0;
  static constexpr Register kTypeArgsReg = R1;  // Can be the same as kTempReg
  static constexpr Register kTempReg = R1;
  static constexpr Register kFrameSizeReg = R2;
  static constexpr Register kSuspendStateReg = R3;
  static constexpr Register kFunctionDataReg = R4;
  static constexpr Register kSrcFrameReg = R8;
  static constexpr Register kDstFrameReg = R9;

  // Number of bytes to skip after
  // suspend stub return address in order to resume.
  static constexpr intptr_t kResumePcDistance = 0;
};

// ABI for InitSuspendableFunctionStub (InitAsyncStub, InitAsyncStarStub,
// InitSyncStarStub).
struct InitSuspendableFunctionStubABI {
  static constexpr Register kTypeArgsReg = R0;
};

// ABI for ResumeStub
struct ResumeStubABI {
  static constexpr Register kSuspendStateReg = R2;
  static constexpr Register kTempReg = R0;
  // Registers for the frame copying (the 1st part).
  static constexpr Register kFrameSizeReg = R1;
  static constexpr Register kSrcFrameReg = R3;
  static constexpr Register kDstFrameReg = R4;
  // Registers for control transfer.
  // (the 2nd part, can reuse registers from the 1st part)
  static constexpr Register kResumePcReg = R1;
  // Can also reuse kSuspendStateReg but should not conflict with CODE_REG/PP.
  static constexpr Register kExceptionReg = R3;
  static constexpr Register kStackTraceReg = R4;
};

// ABI for ReturnStub (ReturnAsyncStub, ReturnAsyncNotFutureStub,
// ReturnAsyncStarStub).
struct ReturnStubABI {
  static constexpr Register kSuspendStateReg = R2;
};

// ABI for AsyncExceptionHandlerStub.
struct AsyncExceptionHandlerStubABI {
  static constexpr Register kSuspendStateReg = R2;
};

// ABI for CloneSuspendStateStub.
struct CloneSuspendStateStubABI {
  static constexpr Register kSourceReg = R0;
  static constexpr Register kDestinationReg = R1;
  static constexpr Register kTempReg = R2;
  static constexpr Register kFrameSizeReg = R3;
  static constexpr Register kSrcFrameReg = R4;
  static constexpr Register kDstFrameReg = R8;
};

// ABI for FfiAsyncCallbackSendStub.
struct FfiAsyncCallbackSendStubABI {
  static constexpr Register kArgsReg = R0;
};

// ABI for DispatchTableNullErrorStub and consequently for all dispatch
// table calls (though normal functions will not expect or use this
// register). This ABI is added to distinguish memory corruption errors from
// null errors.
struct DispatchTableNullErrorABI {
  static constexpr Register kClassIdReg = R0;
};

// TODO(regis): Add ABIs for type testing stubs and is-type test stubs instead
// of reusing the constants of the instantiation stubs ABI.

// List of registers used in load/store multiple.
typedef uint16_t RegList;
const RegList kAllCpuRegistersList = 0xFFFF;
const RegList kAllFpuRegistersList = (1 << kNumberOfFpuRegisters) - 1;

// C++ ABI call registers.
const RegList kAbiArgumentCpuRegs =
    (1 << R0) | (1 << R1) | (1 << R2) | (1 << R3);
const RegList kAbiVolatileCpuRegs = kAbiArgumentCpuRegs | (1 << IP) | (1 << LR);
#if defined(DART_TARGET_OS_MACOS) || defined(DART_TARGET_OS_MACOS_IOS)
const RegList kAbiPreservedCpuRegs =
    (1 << R4) | (1 << R5) | (1 << R6) | (1 << R8) | (1 << R10) | (1 << R11);
const int kAbiPreservedCpuRegCount = 6;
#else
const RegList kAbiPreservedCpuRegs = (1 << R4) | (1 << R5) | (1 << R6) |
                                     (1 << R7) | (1 << R8) | (1 << R9) |
                                     (1 << R10);
const int kAbiPreservedCpuRegCount = 7;
#endif
const QRegister kAbiFirstPreservedFpuReg = Q4;
const QRegister kAbiLastPreservedFpuReg = Q7;
const int kAbiPreservedFpuRegCount = 4;

const RegList kReservedCpuRegisters = (1 << SPREG) | (1 << FPREG) | (1 << TMP) |
                                      (1 << PP) | (1 << THR) | (1 << LR) |
                                      (1 << PC) | (1 << NOTFP);
constexpr intptr_t kNumberOfReservedCpuRegisters =
    Utils::CountOneBits32(kReservedCpuRegisters);
// CPU registers available to Dart allocator.
constexpr RegList kDartAvailableCpuRegs =
    kAllCpuRegistersList & ~kReservedCpuRegisters;
constexpr int kNumberOfDartAvailableCpuRegs =
    kNumberOfCpuRegisters - kNumberOfReservedCpuRegisters;
// No reason to prefer certain registers on ARM.
constexpr int kRegisterAllocationBias = 0;
const intptr_t kStoreBufferWrapperSize = 24;
// Registers available to Dart that are not preserved by runtime calls.
const RegList kDartVolatileCpuRegs =
    kDartAvailableCpuRegs & ~kAbiPreservedCpuRegs;
#if defined(DART_TARGET_OS_MACOS) || defined(DART_TARGET_OS_MACOS_IOS)
const int kDartVolatileCpuRegCount = 6;
#else
const int kDartVolatileCpuRegCount = 5;
#endif

const RegList kAbiVolatileFpuRegs = R(Q0) | R(Q1) | R(Q2) | R(Q3);

const RegList kFpuRegistersWithoutSOverlap =
    kAllFpuRegistersList &
    ~((1 << QRegister::kNumberOfOverlappingQRegisters) - 1);

class CallingConventions {
 public:
  static constexpr intptr_t kArgumentRegisters = kAbiArgumentCpuRegs;
  static const Register ArgumentRegisters[];
  static constexpr intptr_t kNumArgRegs = 4;
  static constexpr Register kPointerToReturnStructRegisterCall = R0;

  static constexpr intptr_t kFpuArgumentRegisters = 0;

  static const FpuRegister FpuArgumentRegisters[];
  static constexpr intptr_t kNumFpuArgRegs = 4;
  static const DRegister FpuDArgumentRegisters[];
  static constexpr intptr_t kNumDFpuArgRegs = 8;
  static const SRegister FpuSArgumentRegisters[];
  static constexpr intptr_t kNumSFpuArgRegs = 16;

  static constexpr bool kArgumentIntRegXorFpuReg = false;

  static constexpr intptr_t kCalleeSaveCpuRegisters = kAbiPreservedCpuRegs;

  // Whether larger than wordsize arguments are aligned to even registers.
  static constexpr AlignmentStrategy kArgumentRegisterAlignment =
      kAlignedToWordSizeAndValueSize;
  static constexpr AlignmentStrategy kArgumentRegisterAlignmentVarArgs =
      kArgumentRegisterAlignment;

  // How stack arguments are aligned.
  static constexpr AlignmentStrategy kArgumentStackAlignment =
      kAlignedToWordSizeAndValueSize;
  static constexpr AlignmentStrategy kArgumentStackAlignmentVarArgs =
      kArgumentStackAlignment;

  // How fields in compounds are aligned.
#if defined(DART_TARGET_OS_MACOS_IOS)
  static constexpr AlignmentStrategy kFieldAlignment =
      kAlignedToValueSizeBut8AlignedTo4;
#else
  static constexpr AlignmentStrategy kFieldAlignment = kAlignedToValueSize;
#endif

  // Whether 1 or 2 byte-sized arguments or return values are passed extended
  // to 4 bytes.
  static constexpr ExtensionStrategy kReturnRegisterExtension = kExtendedTo4;
  static constexpr ExtensionStrategy kArgumentRegisterExtension = kExtendedTo4;
  static constexpr ExtensionStrategy kArgumentStackExtension = kExtendedTo4;

  static constexpr Register kReturnReg = R0;
  static constexpr Register kSecondReturnReg = R1;
  static constexpr FpuRegister kReturnFpuReg = Q0;
  static constexpr Register kPointerToReturnStructRegisterReturn = kReturnReg;

  // We choose these to avoid overlap between themselves and reserved registers.
  static constexpr Register kFirstNonArgumentRegister = R8;
  static constexpr Register kSecondNonArgumentRegister = R9;
  static constexpr Register kFfiAnyNonAbiRegister = R4;
  static constexpr Register kStackPointerRegister = SPREG;

  COMPILE_ASSERT(
      ((R(kFirstNonArgumentRegister) | R(kSecondNonArgumentRegister)) &
       (kArgumentRegisters | R(kPointerToReturnStructRegisterCall))) == 0);
};

// Register based calling convention used for Dart functions.
//
// See |compiler::ComputeCallingConvention| for more details.
struct DartCallingConvention {
  static constexpr Register kCpuRegistersForArgs[] = {R1, R2, R3, R8};
  static constexpr FpuRegister kFpuRegistersForArgs[] = {Q0, Q1, Q2, Q3};
};

#undef R

// Values for the condition field as defined in section A3.2.
enum Condition {
  kNoCondition = -1,
  EQ = 0,                  // equal
  NE = 1,                  // not equal
  CS = 2,                  // carry set/unsigned higher or same
  CC = 3,                  // carry clear/unsigned lower
  MI = 4,                  // minus/negative
  PL = 5,                  // plus/positive or zero
  VS = 6,                  // overflow
  VC = 7,                  // no overflow
  HI = 8,                  // unsigned higher
  LS = 9,                  // unsigned lower or same
  GE = 10,                 // signed greater than or equal
  LT = 11,                 // signed less than
  GT = 12,                 // signed greater than
  LE = 13,                 // signed less than or equal
  AL = 14,                 // always (unconditional)
  kSpecialCondition = 15,  // special condition (refer to section A3.2.1)
  kNumberOfConditions = 16,

  // Platform-independent variants declared for all platforms
  EQUAL = EQ,
  ZERO = EQUAL,
  NOT_EQUAL = NE,
  NOT_ZERO = NOT_EQUAL,
  LESS = LT,
  LESS_EQUAL = LE,
  GREATER_EQUAL = GE,
  GREATER = GT,
  UNSIGNED_LESS = CC,
  UNSIGNED_LESS_EQUAL = LS,
  UNSIGNED_GREATER = HI,
  UNSIGNED_GREATER_EQUAL = CS,
  OVERFLOW = VS,
  NO_OVERFLOW = VC,

  kInvalidCondition = 16
};

static inline Condition InvertCondition(Condition c) {
  COMPILE_ASSERT((EQ ^ NE) == 1);
  COMPILE_ASSERT((CS ^ CC) == 1);
  COMPILE_ASSERT((MI ^ PL) == 1);
  COMPILE_ASSERT((VS ^ VC) == 1);
  COMPILE_ASSERT((HI ^ LS) == 1);
  COMPILE_ASSERT((GE ^ LT) == 1);
  COMPILE_ASSERT((GT ^ LE) == 1);
  ASSERT(c != AL);
  ASSERT(c != kSpecialCondition);
  ASSERT(c != kInvalidCondition);
  return static_cast<Condition>(c ^ 1);
}

// Opcodes for Data-processing instructions (instructions with a type 0 and 1)
// as defined in section A3.4
enum Opcode {
  kNoOperand = -1,
  AND = 0,   // Logical AND
  EOR = 1,   // Logical Exclusive OR
  SUB = 2,   // Subtract
  RSB = 3,   // Reverse Subtract
  ADD = 4,   // Add
  ADC = 5,   // Add with Carry
  SBC = 6,   // Subtract with Carry
  RSC = 7,   // Reverse Subtract with Carry
  TST = 8,   // Test
  TEQ = 9,   // Test Equivalence
  CMP = 10,  // Compare
  CMN = 11,  // Compare Negated
  ORR = 12,  // Logical (inclusive) OR
  MOV = 13,  // Move
  BIC = 14,  // Bit Clear
  MVN = 15,  // Move Not
  kMaxOperand = 16
};

// Shifter types for Data-processing operands as defined in section A5.1.2.
enum Shift {
  kNoShift = -1,
  LSL = 0,  // Logical shift left
  LSR = 1,  // Logical shift right
  ASR = 2,  // Arithmetic shift right
  ROR = 3,  // Rotate right
  kMaxShift = 4
};

// Constants used for the decoding or encoding of the individual fields of
// instructions. Based on the "Figure 3-1 ARM instruction set summary".
enum InstructionFields {
  kConditionShift = 28,
  kConditionBits = 4,
  kTypeShift = 25,
  kTypeBits = 3,
  kLinkShift = 24,
  kLinkBits = 1,
  kUShift = 23,
  kUBits = 1,
  kOpcodeShift = 21,
  kOpcodeBits = 4,
  kSShift = 20,
  kSBits = 1,
  kRnShift = 16,
  kRnBits = 4,
  kRdShift = 12,
  kRdBits = 4,
  kRsShift = 8,
  kRsBits = 4,
  kRmShift = 0,
  kRmBits = 4,

  // Immediate instruction fields encoding.
  kRotateShift = 8,
  kRotateBits = 4,
  kImmed8Shift = 0,
  kImmed8Bits = 8,

  // Shift instruction register fields encodings.
  kShiftImmShift = 7,
  kShiftRegisterShift = 8,
  kShiftImmBits = 5,
  kShiftShift = 5,
  kShiftBits = 2,

  // Load/store instruction offset field encoding.
  kOffset12Shift = 0,
  kOffset12Bits = 12,
  kOffset12Mask = 0x00000fff,

  // Mul instruction register field encodings.
  kMulRdShift = 16,
  kMulRdBits = 4,
  kMulRnShift = 12,
  kMulRnBits = 4,

  // ldrex/strex register field encodings.
  kLdrExRnShift = 16,
  kLdrExRtShift = 12,
  kStrExRnShift = 16,
  kStrExRdShift = 12,
  kStrExRtShift = 0,

  // Media operation field encodings.
  kMediaOp1Shift = 20,
  kMediaOp1Bits = 5,
  kMediaOp2Shift = 5,
  kMediaOp2Bits = 3,

  // udiv/sdiv instruction register field encodings.
  kDivRdShift = 16,
  kDivRdBits = 4,
  kDivRmShift = 8,
  kDivRmBits = 4,
  kDivRnShift = 0,
  kDivRnBits = 4,

  // sbfx/ubfx instruction register and immediate field encodings.
  kBitFieldExtractWidthShift = 16,
  kBitFieldExtractWidthBits = 5,
  kBitFieldExtractLSBShift = 7,
  kBitFieldExtractLSBBits = 5,
  kBitFieldExtractRnShift = 0,
  kBitFieldExtractRnBits = 4,

  // MRC instruction offset field encoding.
  kCRmShift = 0,
  kCRmBits = 4,
  kOpc2Shift = 5,
  kOpc2Bits = 3,
  kCoprocShift = 8,
  kCoprocBits = 4,
  kCRnShift = 16,
  kCRnBits = 4,
  kOpc1Shift = 21,
  kOpc1Bits = 3,

  kBranchOffsetMask = 0x00ffffff
};

enum ScaleFactor {
  TIMES_1 = 0,
  TIMES_2 = 1,
  TIMES_4 = 2,
  TIMES_8 = 3,
  TIMES_16 = 4,
// Don't use (dart::)kWordSizeLog2, as this needs to work for crossword as
// well. If this is included, we know the target is 32 bit.
#if defined(TARGET_ARCH_IS_32_BIT)
  // Used for Smi-boxed indices.
  TIMES_HALF_WORD_SIZE = kInt32SizeLog2 - 1,
  // Used for unboxed indices.
  TIMES_WORD_SIZE = kInt32SizeLog2,
#else
#error "Unexpected word size"
#endif
#if !defined(DART_COMPRESSED_POINTERS)
  TIMES_COMPRESSED_WORD_SIZE = TIMES_WORD_SIZE,
#else
#error Cannot compress ARM32
#endif
  // Used for Smi-boxed indices.
  TIMES_COMPRESSED_HALF_WORD_SIZE = TIMES_COMPRESSED_WORD_SIZE - 1,
};

// The class Instr enables access to individual fields defined in the ARM
// architecture instruction set encoding as described in figure A3-1.
//
// Example: Test whether the instruction at ptr sets the condition code bits.
//
// bool InstructionSetsConditionCodes(byte* ptr) {
//   Instr* instr = Instr::At(ptr);
//   int type = instr->TypeField();
//   return ((type == 0) || (type == 1)) && instr->HasS();
// }
//
class Instr {
 public:
  enum { kInstrSize = 4, kInstrSizeLog2 = 2, kPCReadOffset = 8 };

  static constexpr int32_t kNopInstruction =  // nop
      ((AL << kConditionShift) | (0x32 << 20) | (0xf << 12));

  static constexpr int32_t kBreakPointCode = 0xdeb0;  // For breakpoint.
  static constexpr int32_t kSimulatorBreakCode =
      0xdeb2;  // For breakpoint in sim.
  static constexpr int32_t kSimulatorRedirectCode = 0xca11;  // For redirection.

  // Breakpoint instruction filling assembler code buffers in debug mode.
  static constexpr int32_t kBreakPointInstruction =  // bkpt(0xdeb0)
      ((AL << kConditionShift) | (0x12 << 20) | (0xdeb << 8) | (0x7 << 4));

  // Breakpoint instruction used by the simulator.
  // Should be distinct from kBreakPointInstruction and from a typical user
  // breakpoint inserted in generated code for debugging, e.g. bkpt(0).
  static constexpr int32_t kSimulatorBreakpointInstruction =
      // svc #kBreakpointSvcCode
      ((AL << kConditionShift) | (0xf << 24) | kSimulatorBreakCode);

  // Runtime call redirection instruction used by the simulator.
  static constexpr int32_t kSimulatorRedirectInstruction =
      ((AL << kConditionShift) | (0xf << 24) | kSimulatorRedirectCode);

  // Get the raw instruction bits.
  inline int32_t InstructionBits() const {
    return *reinterpret_cast<const int32_t*>(this);
  }

  // Set the raw instruction bits to value.
  inline void SetInstructionBits(int32_t value) {
    *reinterpret_cast<int32_t*>(this) = value;
  }

  // Read one particular bit out of the instruction bits.
  inline int Bit(int nr) const { return (InstructionBits() >> nr) & 1; }

  // Read a bit field out of the instruction bits.
  inline int Bits(int shift, int count) const {
    return (InstructionBits() >> shift) & ((1 << count) - 1);
  }

  // Accessors for the different named fields used in the ARM encoding.
  // The naming of these accessor corresponds to figure A3-1.
  // Generally applicable fields
  inline Condition ConditionField() const {
    return static_cast<Condition>(Bits(kConditionShift, kConditionBits));
  }
  inline int TypeField() const { return Bits(kTypeShift, kTypeBits); }
  inline int SubtypeField() const { return Bit(4); }

  inline Register RnField() const {
    return static_cast<Register>(Bits(kRnShift, kRnBits));
  }
  inline Register RdField() const {
    return static_cast<Register>(Bits(kRdShift, kRdBits));
  }

  // Fields used in Data processing instructions
  inline Opcode OpcodeField() const {
    return static_cast<Opcode>(Bits(kOpcodeShift, kOpcodeBits));
  }
  inline int SField() const { return Bits(kSShift, kSBits); }
  // with register
  inline Register RmField() const {
    return static_cast<Register>(Bits(kRmShift, kRmBits));
  }
  inline Shift ShiftField() const {
    return static_cast<Shift>(Bits(kShiftShift, kShiftBits));
  }
  inline int RegShiftField() const { return Bit(4); }
  inline Register RsField() const {
    return static_cast<Register>(Bits(kRsShift, kRsBits));
  }
  inline int ShiftAmountField() const {
    return Bits(kShiftImmShift, kShiftImmBits);
  }
  // with immediate
  inline int RotateField() const { return Bits(kRotateShift, kRotateBits); }
  inline int Immed8Field() const { return Bits(kImmed8Shift, kImmed8Bits); }

  // Fields used in Load/Store instructions
  inline int PUField() const { return Bits(23, 2); }
  inline int BField() const { return Bit(22); }
  inline int WField() const { return Bit(21); }
  inline int LField() const { return Bit(20); }
  // with register uses same fields as Data processing instructions above
  // with immediate
  inline int Offset12Field() const {
    return Bits(kOffset12Shift, kOffset12Bits);
  }
  // multiple
  inline int RlistField() const { return Bits(0, 16); }
  // extra loads and stores
  inline int SignField() const { return Bit(6); }
  inline int HField() const { return Bit(5); }
  inline int ImmedHField() const { return Bits(8, 4); }
  inline int ImmedLField() const { return Bits(0, 4); }

  // Fields used in Branch instructions
  inline int LinkField() const { return Bits(kLinkShift, kLinkBits); }
  inline int32_t SImmed24Field() const {
    uint32_t bits = InstructionBits();
    return static_cast<int32_t>(bits << 8) >> 8;
  }

  // Fields used in Supervisor Call instructions
  inline uint32_t SvcField() const { return Bits(0, 24); }

  // Field used in Breakpoint instruction
  inline uint16_t BkptField() const {
    return ((Bits(8, 12) << 4) | Bits(0, 4));
  }

  // Field used in 16-bit immediate move instructions
  inline uint16_t MovwField() const {
    return ((Bits(16, 4) << 12) | Bits(0, 12));
  }

  // Field used in VFP float immediate move instruction
  inline float ImmFloatField() const {
    uint32_t imm32 = (Bit(19) << 31) | (((1 << 5) - Bit(18)) << 25) |
                     (Bits(16, 2) << 23) | (Bits(0, 4) << 19);
    return bit_cast<float, uint32_t>(imm32);
  }

  // Field used in VFP double immediate move instruction
  inline double ImmDoubleField() const {
    uint64_t imm64 = (Bit(19) * (1LL << 63)) | (((1LL << 8) - Bit(18)) << 54) |
                     (Bits(16, 2) * (1LL << 52)) | (Bits(0, 4) * (1LL << 48));
    return bit_cast<double, uint64_t>(imm64);
  }

  // Shared fields used in media instructions.
  inline int MediaOp1Field() const {
    return static_cast<Register>(Bits(kMediaOp1Shift, kMediaOp1Bits));
  }
  inline int MediaOp2Field() const {
    return static_cast<Register>(Bits(kMediaOp2Shift, kMediaOp2Bits));
  }

  // Fields used in division instructions.
  inline bool IsDivUnsigned() const { return Bit(21) == 0b1; }
  inline Register DivRdField() const {
    return static_cast<Register>(Bits(kDivRdShift, kDivRdBits));
  }
  inline Register DivRmField() const {
    return static_cast<Register>(Bits(kDivRmShift, kDivRmBits));
  }
  inline Register DivRnField() const {
    return static_cast<Register>(Bits(kDivRnShift, kDivRnBits));
  }

  // Fields used in bit field extract instructions.
  inline bool IsBitFieldExtractSignExtended() const { return Bit(22) == 0; }
  inline uint8_t BitFieldExtractWidthField() const {
    return Bits(kBitFieldExtractWidthShift, kBitFieldExtractWidthBits);
  }
  inline uint8_t BitFieldExtractLSBField() const {
    return Bits(kBitFieldExtractLSBShift, kBitFieldExtractLSBBits);
  }
  inline Register BitFieldExtractRnField() const {
    return static_cast<Register>(
        Bits(kBitFieldExtractRnShift, kBitFieldExtractRnBits));
  }

  // Test for data processing instructions of type 0 or 1.
  // See "ARM Architecture Reference Manual ARMv7-A and ARMv7-R edition",
  // section A5.1 "ARM instruction set encoding".
  inline bool IsDataProcessing() const {
    ASSERT(ConditionField() != kSpecialCondition);
    ASSERT(Bits(26, 2) == 0);  // Type 0 or 1.
    return ((Bits(20, 5) & 0x19) != 0x10) &&
           ((Bit(25) == 1) ||  // Data processing immediate.
            (Bit(4) == 0) ||   // Data processing register.
            (Bit(7) == 0));    // Data processing register-shifted register.
  }

  // Tests for special encodings of type 0 instructions (extra loads and stores,
  // as well as multiplications, synchronization primitives, and miscellaneous).
  // Can only be called for a type 0 or 1 instruction.
  inline bool IsMiscellaneous() const {
    ASSERT(Bits(26, 2) == 0);  // Type 0 or 1.
    return ((Bit(25) == 0) && ((Bits(20, 5) & 0x19) == 0x10) && (Bit(7) == 0));
  }
  inline bool IsMultiplyOrSyncPrimitive() const {
    ASSERT(Bits(26, 2) == 0);  // Type 0 or 1.
    return ((Bit(25) == 0) && (Bits(4, 4) == 9));
  }

  // Test for Supervisor Call instruction.
  inline bool IsSvc() const {
    return ((InstructionBits() & 0x0f000000) == 0x0f000000);
  }

  // Test for Breakpoint instruction.
  inline bool IsBkpt() const {
    return ((InstructionBits() & 0x0ff000f0) == 0x01200070);
  }

  // VFP register fields.
  inline SRegister SnField() const {
    return static_cast<SRegister>((Bits(kRnShift, kRnBits) << 1) + Bit(7));
  }
  inline SRegister SdField() const {
    return static_cast<SRegister>((Bits(kRdShift, kRdBits) << 1) + Bit(22));
  }
  inline SRegister SmField() const {
    return static_cast<SRegister>((Bits(kRmShift, kRmBits) << 1) + Bit(5));
  }
  inline DRegister DnField() const {
    return static_cast<DRegister>(Bits(kRnShift, kRnBits) + (Bit(7) << 4));
  }
  inline DRegister DdField() const {
    return static_cast<DRegister>(Bits(kRdShift, kRdBits) + (Bit(22) << 4));
  }
  inline DRegister DmField() const {
    return static_cast<DRegister>(Bits(kRmShift, kRmBits) + (Bit(5) << 4));
  }
  inline QRegister QnField() const {
    const intptr_t bits = Bits(kRnShift, kRnBits) + (Bit(7) << 4);
    return static_cast<QRegister>(bits >> 1);
  }
  inline QRegister QdField() const {
    const intptr_t bits = Bits(kRdShift, kRdBits) + (Bit(22) << 4);
    return static_cast<QRegister>(bits >> 1);
  }
  inline QRegister QmField() const {
    const intptr_t bits = Bits(kRmShift, kRmBits) + (Bit(5) << 4);
    return static_cast<QRegister>(bits >> 1);
  }

  // Test for VFP data processing or single transfer instructions of type 7.
  inline bool IsVFPDataProcessingOrSingleTransfer() const {
    ASSERT(ConditionField() != kSpecialCondition);
    ASSERT(TypeField() == 7);
    return ((Bit(24) == 0) && (Bits(9, 3) == 5));
    // Bit(4) == 0: Data Processing
    // Bit(4) == 1: 8, 16, or 32-bit Transfer between ARM Core and VFP
  }

  // Test for VFP 64-bit transfer instructions of type 6.
  inline bool IsVFPDoubleTransfer() const {
    ASSERT(ConditionField() != kSpecialCondition);
    ASSERT(TypeField() == 6);
    return ((Bits(21, 4) == 2) && (Bits(9, 3) == 5) &&
            ((Bits(4, 4) & 0xd) == 1));
  }

  // Test for VFP load and store instructions of type 6.
  inline bool IsVFPLoadStore() const {
    ASSERT(ConditionField() != kSpecialCondition);
    ASSERT(TypeField() == 6);
    return ((Bits(20, 5) & 0x12) == 0x10) && (Bits(9, 3) == 5);
  }

  // Test for VFP multiple load and store instructions of type 6.
  inline bool IsVFPMultipleLoadStore() const {
    ASSERT(ConditionField() != kSpecialCondition);
    ASSERT(TypeField() == 6);
    int32_t puw = (PUField() << 1) | Bit(21);  // don't care about D bit
    return (Bits(9, 3) == 5) && ((puw == 2) || (puw == 3) || (puw == 5));
  }

  inline bool IsSIMDDataProcessing() const {
    ASSERT(ConditionField() == kSpecialCondition);
    return (Bits(25, 3) == 1);
  }

  inline bool IsSIMDLoadStore() const {
    ASSERT(ConditionField() == kSpecialCondition);
    return (Bits(24, 4) == 4) && (Bit(20) == 0);
  }

  // Tests for media instructions of type 3.
  inline bool IsMedia() const {
    ASSERT_EQUAL(TypeField(), 3);
    return SubtypeField() == 1;
  }

  inline bool IsDivision() const {
    ASSERT(ConditionField() != kSpecialCondition);
    ASSERT(IsMedia());
    // B21 determines whether the division is signed or unsigned.
    return (((MediaOp1Field() & 0b11101) == 0b10001) &&
            (MediaOp2Field() == 0b000));
  }

  inline bool IsRbit() const {
    ASSERT(ConditionField() != kSpecialCondition);
    ASSERT(IsMedia());
    // B19-B16 and B11-B8 are always set for rbit.
    return ((MediaOp1Field() == 0b01111) && (MediaOp2Field() == 0b001) &&
            (Bits(8, 4) == 0b1111) && (Bits(16, 4) == 0b1111));
  }

  inline bool IsBitFieldExtract() const {
    ASSERT(ConditionField() != kSpecialCondition);
    ASSERT(IsMedia());
    // B22 determines whether extracted value is sign extended or not, and
    // op bits B20 and B7 are part of the width and LSB fields, respectively.
    return ((MediaOp1Field() & 0b11010) == 0b11010) &&
           ((MediaOp2Field() & 0b011) == 0b10);
  }

  // Special accessors that test for existence of a value.
  inline bool HasS() const { return SField() == 1; }
  inline bool HasB() const { return BField() == 1; }
  inline bool HasW() const { return WField() == 1; }
  inline bool HasL() const { return LField() == 1; }
  inline bool HasSign() const { return SignField() == 1; }
  inline bool HasH() const { return HField() == 1; }
  inline bool HasLink() const { return LinkField() == 1; }

  // Instructions are read out of a code stream. The only way to get a
  // reference to an instruction is to convert a pointer. There is no way
  // to allocate or create instances of class Instr.
  // Use the At(pc) function to create references to Instr.
  static Instr* At(uword pc) { return reinterpret_cast<Instr*>(pc); }

 private:
  DISALLOW_ALLOCATION();
  DISALLOW_IMPLICIT_CONSTRUCTORS(Instr);
};

// Floating-point reciprocal estimate and step (see pages A2-85 and A2-86 of
// ARM Architecture Reference Manual ARMv7-A edition).
float ReciprocalEstimate(float op);
float ReciprocalStep(float op1, float op2);

// Floating-point reciprocal square root estimate and step (see pages A2-87 to
// A2-90 of ARM Architecture Reference Manual ARMv7-A edition).
float ReciprocalSqrtEstimate(float op);
float ReciprocalSqrtStep(float op1, float op2);

constexpr uword kBreakInstructionFiller = 0xE1200070;   // bkpt #0
constexpr uword kDataMemoryBarrier = 0xf57ff050 | 0xb;  // dmb ish

struct LinkRegister {
  const int32_t code = LR;
};

constexpr bool operator==(Register r, LinkRegister) {
  return r == LR;
}

constexpr bool operator!=(Register r, LinkRegister lr) {
  return !(r == lr);
}

inline Register ConcreteRegister(LinkRegister) {
  return LR;
}

#undef LR

#define LINK_REGISTER (LinkRegister())

// Prioritize code size over performance.
const intptr_t kPreferredLoopAlignment = 1;

}  // namespace dart

#endif  // RUNTIME_VM_CONSTANTS_ARM_H_
