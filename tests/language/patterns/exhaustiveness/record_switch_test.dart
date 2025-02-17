// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

enum E { a, b }

const r0 = (E.a, false);
const r1 = (E.b, false);
const r2 = (E.a, true);
const r3 = (E.b, true);

void exhaustiveSwitch((E, bool) r) {
  switch (r) /* Ok */ {
    case r0:
      print('(a, false)');
      break;
    case r1:
      print('(b, false)');
      break;
    case r2:
      print('(a, true)');
      break;
    case r3:
      print('(b, true)');
      break;
  }
}

void nonExhaustiveSwitch1((E, bool) r) {
  switch (r) /* Error */ {
    // [error column 3, length 6]
    // [analyzer] COMPILE_TIME_ERROR.NON_EXHAUSTIVE_SWITCH_STATEMENT
    //    ^
    // [cfe] The type '(E, bool)' is not exhaustively matched by the switch cases since it doesn't match '(E.b, false)'.
    case r0:
      print('(a, false)');
      break;
    case r2:
      print('(a, true)');
      break;
    case r3:
      print('(b, true)');
      break;
  }
}

void nonExhaustiveSwitch2((E, bool) r) {
  switch (r) /* Error */ {
    // [error column 3, length 6]
    // [analyzer] COMPILE_TIME_ERROR.NON_EXHAUSTIVE_SWITCH_STATEMENT
    //    ^
    // [cfe] The type '(E, bool)' is not exhaustively matched by the switch cases since it doesn't match '(E.a, false)'.
    case r1:
      print('(b, false)');
      break;
    case r2:
      print('(a, true)');
      break;
    case r3:
      print('(b, true)');
      break;
  }
}

void nonExhaustiveSwitchWithDefault((E, bool) r) {
  switch (r) /* Ok */ {
    case r0:
      print('(a, false)');
      break;
    default:
      print('default');
      break;
  }
}

void exhaustiveNullableSwitch((E, bool)? r) {
  switch (r) /* Ok */ {
    case r0:
      print('(a, false)');
      break;
    case r1:
      print('(b, false)');
      break;
    case r2:
      print('(a, true)');
      break;
    case r3:
      print('(b, true)');
      break;
    case null:
      print('null');
      break;
  }
}

void nonExhaustiveNullableSwitch1((E, bool)? r) {
  switch (r) /* Error */ {
    // [error column 3, length 6]
    // [analyzer] COMPILE_TIME_ERROR.NON_EXHAUSTIVE_SWITCH_STATEMENT
    //    ^
    // [cfe] The type '(E, bool)?' is not exhaustively matched by the switch cases since it doesn't match 'null'.
    case r0:
      print('(a, false)');
      break;
    case r1:
      print('(b, false)');
      break;
    case r2:
      print('(a, true)');
      break;
    case r3:
      print('(b, true)');
      break;
  }
}

void nonExhaustiveNullableSwitch2((E, bool)? r) {
  switch (r) /* Error */ {
    // [error column 3, length 6]
    // [analyzer] COMPILE_TIME_ERROR.NON_EXHAUSTIVE_SWITCH_STATEMENT
    //    ^
    // [cfe] The type '(E, bool)?' is not exhaustively matched by the switch cases since it doesn't match '(E.b, false)'.
    case r0:
      print('(a, false)');
      break;
    case r2:
      print('(a, true)');
      break;
    case r3:
      print('(b, true)');
      break;
    case null:
      print('null');
      break;
  }
}

void unreachableCase1((E, bool) r) {
  switch (r) /* Ok */ {
    case r0:
      print('(a, false) #1');
      break;
    case r1:
      print('(b, false)');
      break;
    case r2:
      print('(a, true)');
      break;
    case r3:
      print('(b, true)');
      break;
    case r0: // Unreachable
      // [error column 5, length 4]
      // [analyzer] STATIC_WARNING.UNREACHABLE_SWITCH_CASE
      print('(a, false) #2');
      break;
  }
}

void unreachableCase2((E, bool) r) {
  // TODO(johnniwinther): Should we avoid the unreachable error here?
  switch (r) /* Error */ {
    case r0:
      print('(a, false)');
      break;
    case r1:
      print('(b, false)');
      break;
    case r2:
      print('(a, true)');
      break;
    case r3:
      print('(b, true)');
      break;
    case null: // Unreachable
      print('null');
      break;
  }
}

void unreachableCase3((E, bool)? r) {
  switch (r) /* Ok */ {
    case r0:
      print('(a, false)');
      break;
    case r1:
      print('(b, false)');
      break;
    case r2:
      print('(a, true)');
      break;
    case r3:
      print('(b, true)');
      break;
    case null:
      print('null1');
      break;
    case null: // Unreachable
      // [error column 5, length 4]
      // [analyzer] STATIC_WARNING.UNREACHABLE_SWITCH_CASE
      print('null2');
      break;
  }
}

void unreachableDefault((E, bool) r) {
  switch (r) /* Ok */ {
    case r0:
      print('(a, false)');
      break;
    case r1:
      print('(b, false)');
      break;
    case r2:
      print('(a, true)');
      break;
    case r3:
      print('(b, true)');
      break;
    default: // Unreachable
      // [error column 5, length 7]
      // [analyzer] STATIC_WARNING.UNREACHABLE_SWITCH_DEFAULT
      print('default');
      break;
  }
}
