// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Test mismatch in argument counts.
class Niesen {
  static int goodCall(int a, int b, int c) {
    return a + b;
  }
}

main() {
  Niesen.goodCall(1, 2, 3);

  Niesen.goodCall(1, 2, 3, 4);
  //             ^
  // [cfe] Too many positional arguments: 3 allowed, but 4 found.
  //                       ^
  // [analyzer] COMPILE_TIME_ERROR.EXTRA_POSITIONAL_ARGUMENTS
}
