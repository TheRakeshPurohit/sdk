// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Formatting can break multitests, so don't format them.
// dart format off

void f(Object x) {
  if (x is! String) {
    x.length; //# 01: compile-time error
  } else {
    x.length; //# 02: ok
  }
  x.length; //# 03: compile-time error
}

void main() {}
