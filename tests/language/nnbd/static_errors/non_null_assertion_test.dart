// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Formatting can break multitests, so don't format them.
// dart format off

void main() {
  void x;
  int i;
  int? iq;
  x!; //# 00: compile-time error
  i!; //# 01: compile-time error
  iq!; //# 02: runtime error
}
