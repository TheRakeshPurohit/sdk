// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include "vm/compiler/backend/evaluator.h"

namespace dart {

static IntegerPtr BinaryIntegerEvaluateRaw(const Integer& left,
                                           const Integer& right,
                                           Token::Kind token_kind) {
  switch (token_kind) {
    case Token::kTRUNCDIV:
      FALL_THROUGH;
    case Token::kMOD:
      // Check right value for zero.
      if (right.Value() == 0) {
        break;  // Will throw.
      }
      FALL_THROUGH;
    case Token::kADD:
      FALL_THROUGH;
    case Token::kSUB:
      FALL_THROUGH;
    case Token::kMUL:
      return left.ArithmeticOp(token_kind, right, Heap::kOld);
    case Token::kSHL:
      FALL_THROUGH;
    case Token::kSHR:
      FALL_THROUGH;
    case Token::kUSHR:
      if (right.Value() >= 0) {
        return left.ShiftOp(token_kind, right, Heap::kOld);
      }
      break;
    case Token::kBIT_AND:
      FALL_THROUGH;
    case Token::kBIT_OR:
      FALL_THROUGH;
    case Token::kBIT_XOR:
      return left.BitOp(token_kind, right, Heap::kOld);
    case Token::kDIV:
      break;
    default:
      UNREACHABLE();
  }

  return Integer::null();
}

static IntegerPtr UnaryIntegerEvaluateRaw(const Integer& value,
                                          Token::Kind token_kind,
                                          Zone* zone) {
  switch (token_kind) {
    case Token::kNEGATE:
      return value.ArithmeticOp(Token::kMUL, Smi::Handle(zone, Smi::New(-1)),
                                Heap::kOld);
    case Token::kBIT_NOT:
      if (value.IsInteger()) {
        return Integer::New(~value.Value(), Heap::kOld);
      }
      break;
    default:
      UNREACHABLE();
  }
  return Integer::null();
}

static IntegerPtr BitLengthEvaluateRaw(const Integer& value, Zone* zone) {
  if (value.IsInteger()) {
    return Integer::New(Utils::BitLength(value.Value()), Heap::kOld);
  }
  return Integer::null();
}

int64_t Evaluator::TruncateTo(int64_t v, Representation r) {
  switch (r) {
    case kTagged: {
      const intptr_t kTruncateBits =
          kBitsPerInt64 - (compiler::target::kSmiBits + 1 /*sign bit*/);
      return Utils::ShiftLeftWithTruncation(v, kTruncateBits) >> kTruncateBits;
    }
    case kUnboxedInt32:
      return Utils::ShiftLeftWithTruncation(v, kBitsPerInt32) >> kBitsPerInt32;
    case kUnboxedUint32:
      return v & kMaxUint32;
    case kUnboxedInt64:
      return v;
    default:
      UNREACHABLE();
  }
}

IntegerPtr Evaluator::BinaryIntegerEvaluate(const Object& left,
                                            const Object& right,
                                            Token::Kind token_kind,
                                            bool is_truncating,
                                            Representation representation,
                                            Thread* thread) {
  if (!left.IsInteger() || !right.IsInteger()) {
    return Integer::null();
  }
  Zone* zone = thread->zone();
  const Integer& left_int = Integer::Cast(left);
  const Integer& right_int = Integer::Cast(right);
  Integer& result = Integer::Handle(
      zone, BinaryIntegerEvaluateRaw(left_int, right_int, token_kind));

  if (!result.IsNull()) {
    if (is_truncating) {
      const int64_t truncated = TruncateTo(result.Value(), representation);
      result = Integer::New(truncated, Heap::kOld);
      ASSERT(FlowGraph::IsConstantRepresentable(
          result, representation, /*tagged_value_must_be_smi=*/true));
    } else if (!FlowGraph::IsConstantRepresentable(
                   result, representation, /*tagged_value_must_be_smi=*/true)) {
      // If this operation is not truncating it would deoptimize on overflow.
      // Check that we match this behavior and don't produce a value that is
      // larger than something this operation can produce. We could have
      // specialized instructions that use this value under this assumption.
      return Integer::null();
    }
    result ^= result.Canonicalize(thread);
  }

  return result.ptr();
}

IntegerPtr Evaluator::UnaryIntegerEvaluate(const Object& value,
                                           Token::Kind token_kind,
                                           Representation representation,
                                           Thread* thread) {
  if (!value.IsInteger()) {
    return Integer::null();
  }
  Zone* zone = thread->zone();
  const Integer& value_int = Integer::Cast(value);
  Integer& result = Integer::Handle(
      zone, UnaryIntegerEvaluateRaw(value_int, token_kind, zone));

  if (!result.IsNull()) {
    if (!FlowGraph::IsConstantRepresentable(
            result, representation,
            /*tagged_value_must_be_smi=*/true)) {
      // If this operation is not truncating it would deoptimize on overflow.
      // Check that we match this behavior and don't produce a value that is
      // larger than something this operation can produce. We could have
      // specialized instructions that use this value under this assumption.
      return Integer::null();
    }

    result ^= result.Canonicalize(thread);
  }

  return result.ptr();
}

IntegerPtr Evaluator::BitLengthEvaluate(const Object& value,
                                        Representation representation,
                                        Thread* thread) {
  if (!value.IsInteger()) {
    return Integer::null();
  }
  Zone* zone = thread->zone();
  const Integer& value_int = Integer::Cast(value);
  Integer& result =
      Integer::Handle(zone, BitLengthEvaluateRaw(value_int, zone));

  if (!result.IsNull()) {
    if (!FlowGraph::IsConstantRepresentable(
            result, representation,
            /*tagged_value_must_be_smi=*/true)) {
      // If this operation is not truncating it would deoptimize on overflow.
      // Check that we match this behavior and don't produce a value that is
      // larger than something this operation can produce. We could have
      // specialized instructions that use this value under this assumption.
      return Integer::null();
    }

    result ^= result.Canonicalize(thread);
  }

  return result.ptr();
}

double Evaluator::EvaluateUnaryDoubleOp(const double value,
                                        Token::Kind token_kind,
                                        Representation representation) {
  // The different set of operations for float32 and float64 is due to the
  // different set of operations made available by dart:core.double and
  // dart:typed_data.Float64x2 versus dart:typed_data.Float32x4.
  if (representation == kUnboxedDouble) {
    switch (token_kind) {
      case Token::kABS:
        return fabs(value);
      case Token::kNEGATE:
        return -value;
      case Token::kSQRT:
        return sqrt(value);
      case Token::kSQUARE:
        return value * value;
      case Token::kTRUNCATE:
        return trunc(value);
      case Token::kFLOOR:
        return floor(value);
      case Token::kCEILING:
        return ceil(value);
      default:
        UNREACHABLE();
    }
  } else {
    ASSERT(representation == kUnboxedFloat);
    switch (token_kind) {
      case Token::kABS:
        return fabsf(static_cast<float>(value));
      case Token::kNEGATE:
        return -static_cast<float>(value);
      case Token::kRECIPROCAL:
        return 1.0f / static_cast<float>(value);
      case Token::kRECIPROCAL_SQRT:
        return sqrtf(1.0f / static_cast<float>(value));
      case Token::kSQRT:
        return sqrtf(static_cast<float>(value));
      case Token::kSQUARE:
        return static_cast<float>(value) * static_cast<float>(value);
      default:
        UNREACHABLE();
    }
  }
}

double Evaluator::EvaluateBinaryDoubleOp(const double left,
                                         const double right,
                                         Token::Kind token_kind,
                                         Representation representation) {
  if (representation == kUnboxedDouble) {
    switch (token_kind) {
      case Token::kADD:
        return left + right;
      case Token::kSUB:
        return left - right;
      case Token::kMUL:
        return left * right;
      case Token::kDIV:
        return Utils::DivideAllowZero(left, right);
      case Token::kMIN:
        return fmin(left, right);
      case Token::kMAX:
        return fmax(left, right);
      default:
        UNREACHABLE();
    }
  } else {
    ASSERT(representation == kUnboxedFloat);
    switch (token_kind) {
      case Token::kADD:
        return static_cast<float>(left) + static_cast<float>(right);
      case Token::kSUB:
        return static_cast<float>(left) - static_cast<float>(right);
      case Token::kMUL:
        return static_cast<float>(left) * static_cast<float>(right);
      case Token::kDIV:
        return Utils::DivideAllowZero(static_cast<float>(left),
                                      static_cast<float>(right));
      case Token::kMIN:
        return fminf(static_cast<float>(left), static_cast<float>(right));
      case Token::kMAX:
        return fmaxf(static_cast<float>(left), static_cast<float>(right));
      default:
        UNREACHABLE();
    }
  }
}

bool Evaluator::ToIntegerConstant(Value* value, int64_t* result) {
  if (!value->BindsToConstant()) {
    UnboxInstr* unbox = value->definition()->AsUnbox();
    if (unbox != nullptr) {
      switch (unbox->representation()) {
        case kUnboxedDouble:
        case kUnboxedInt64:
          return ToIntegerConstant(unbox->value(), result);
        case kUnboxedUint32:
          if (ToIntegerConstant(unbox->value(), result)) {
            *result = Evaluator::TruncateTo(*result, kUnboxedUint32);
            return true;
          }
          break;
          // No need to handle Unbox<Int32>(Constant(C)) because it gets
          // canonicalized to UnboxedConstant<Int32>(C).
        case kUnboxedInt32:
        default:
          break;
      }
    }
    return false;
  }
  const Object& constant = value->BoundConstant();
  if (constant.IsDouble()) {
    const Double& double_constant = Double::Cast(constant);
    *result = Utils::SafeDoubleToInt<int64_t>(double_constant.value());
    return (static_cast<double>(*result) == double_constant.value());
  } else if (constant.IsInteger()) {
    *result = Integer::Cast(constant).Value();
    return true;
  }
  return false;
}

}  // namespace dart
