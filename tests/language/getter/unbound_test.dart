// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
// Verify that an unbound getter is properly resolved at runtime.

class A {
  const A();
  foo() {
    return y;
    //     ^
    // [analyzer] COMPILE_TIME_ERROR.UNDEFINED_IDENTIFIER
    // [cfe] The getter 'y' isn't defined for the type 'A'.
  }
}

main() {
  new A().foo();
}
