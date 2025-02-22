// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'static_extension_constant_lib.dart';

// Tests that it is an error to invoke an extension method during constant
// expression evaluation. The expressions should be the same as those in
// `runtimeExtensionCalls`, so that it is verified that each of them will
// invoke an extension method.

void main() {
  // The initializing expressions should be identical to the elements in
  // `runtimeExtensionCalls`.

  const c01 = ~i;
  //          ^^
  // [analyzer] COMPILE_TIME_ERROR.CONST_EVAL_EXTENSION_METHOD
  // [cfe] Constant evaluation error:
  const c02 = b & b;
  //          ^^^^^
  // [analyzer] COMPILE_TIME_ERROR.CONST_EVAL_EXTENSION_METHOD
  //            ^
  // [cfe] Constant evaluation error:
  const c03 = b | b;
  //          ^^^^^
  // [analyzer] COMPILE_TIME_ERROR.CONST_EVAL_EXTENSION_METHOD
  //            ^
  // [cfe] Constant evaluation error:
  const c04 = b ^ b;
  //          ^^^^^
  // [analyzer] COMPILE_TIME_ERROR.CONST_EVAL_EXTENSION_METHOD
  //            ^
  // [cfe] Constant evaluation error:
  const c05 = i ~/ i;
  //          ^^^^^^
  // [analyzer] COMPILE_TIME_ERROR.CONST_EVAL_EXTENSION_METHOD
  //            ^
  // [cfe] Constant evaluation error:
  const c06 = i >> i;
  //          ^^^^^^
  // [analyzer] COMPILE_TIME_ERROR.CONST_EVAL_EXTENSION_METHOD
  //            ^
  // [cfe] Constant evaluation error:
  const c08 = i << i;
  //          ^^^^^^
  // [analyzer] COMPILE_TIME_ERROR.CONST_EVAL_EXTENSION_METHOD
  //            ^
  // [cfe] Constant evaluation error:
  const c09 = i + i;
  //          ^^^^^
  // [analyzer] COMPILE_TIME_ERROR.CONST_EVAL_EXTENSION_METHOD
  //            ^
  // [cfe] Constant evaluation error:
  const c10 = -i;
  //          ^^
  // [analyzer] COMPILE_TIME_ERROR.CONST_EVAL_EXTENSION_METHOD
  // [cfe] Constant evaluation error:
  const c11 = d - d;
  //          ^^^^^
  // [analyzer] COMPILE_TIME_ERROR.CONST_EVAL_EXTENSION_METHOD
  //            ^
  // [cfe] Constant evaluation error:
  const c12 = d * d;
  //          ^^^^^
  // [analyzer] COMPILE_TIME_ERROR.CONST_EVAL_EXTENSION_METHOD
  //            ^
  // [cfe] Constant evaluation error:
  const c13 = d / d;
  //          ^^^^^
  // [analyzer] COMPILE_TIME_ERROR.CONST_EVAL_EXTENSION_METHOD
  //            ^
  // [cfe] Constant evaluation error:
  const c14 = d % d;
  //          ^^^^^
  // [analyzer] COMPILE_TIME_ERROR.CONST_EVAL_EXTENSION_METHOD
  //            ^
  // [cfe] Constant evaluation error:
  const c15 = d < i;
  //          ^^^^^
  // [analyzer] COMPILE_TIME_ERROR.CONST_EVAL_EXTENSION_METHOD
  //            ^
  // [cfe] Constant evaluation error:
  const c16 = i <= d;
  //          ^^^^^^
  // [analyzer] COMPILE_TIME_ERROR.CONST_EVAL_EXTENSION_METHOD
  //            ^
  // [cfe] Constant evaluation error:
  const c17 = d > i;
  //          ^^^^^
  // [analyzer] COMPILE_TIME_ERROR.CONST_EVAL_EXTENSION_METHOD
  //            ^
  // [cfe] Constant evaluation error:
  const c18 = i >= i;
  //          ^^^^^^
  // [analyzer] COMPILE_TIME_ERROR.CONST_EVAL_EXTENSION_METHOD
  //            ^
  // [cfe] Constant evaluation error:
  const c19 = s.length;
  //          ^^^^^^^^
  // [analyzer] COMPILE_TIME_ERROR.CONST_EVAL_EXTENSION_METHOD
  //            ^
  // [cfe] Constant evaluation error:
}
