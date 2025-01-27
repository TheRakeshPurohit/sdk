// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Tests the promotion of assignment expressions in if statements as described
// by https://github.com/dart-lang/language/issues/3658

// SharedOptions=--enable-experiment=inference-update-4

import '../static_type_helper.dart';

class A {
  A operator +(int i) {
    return new B();
  }
}

class B extends A {}

int? nullableInt() => 1;

testEqNull_assignIfNull() {
  int? x = null;
  if ((x ??= nullableInt()) == null) {
    x.expectStaticType<Exactly<int?>>();
  } else {
    x.expectStaticType<Exactly<int>>();
  }
  x.expectStaticType<Exactly<int?>>();
}

testEqNull_eq() {
  int? x = null;
  if ((x = nullableInt()) == null) {
    x.expectStaticType<Exactly<int?>>();
  } else {
    x.expectStaticType<Exactly<int>>();
  }
  x.expectStaticType<Exactly<int?>>();
}

testNeqNull_assignIfNull() {
  int? x = null;
  if ((x ??= nullableInt()) != null) {
    x.expectStaticType<Exactly<int>>();
  }
  x.expectStaticType<Exactly<int?>>();
}

testNeqNull_eq() {
  int? x = null;
  if ((x = nullableInt()) != null) {
    x.expectStaticType<Exactly<int>>();
  }
  x.expectStaticType<Exactly<int?>>();
}

testIs_eq() {
  int? x = null;
  if ((x = nullableInt()) is int) {
    x.expectStaticType<Exactly<int>>();
  }
  x.expectStaticType<Exactly<int?>>();
}

testIs_plusEq() {
  A x = A();
  if ((x += 1) is B) {
    x.expectStaticType<Exactly<B>>();
  }
  x.expectStaticType<Exactly<A>>();
}

testIs_postfix() {
  A x = A();
  if ((x++) is B) {
    // No promotion because the value being is checked is the value of `x`
    // before the increment, and that value isn't relevant after the increment
    // occurs.
    x.expectStaticType<Exactly<A>>();
  }
  x.expectStaticType<Exactly<A>>();
}

testIs_prefix() {
  A x = A();
  if ((++x) is B) {
    x.expectStaticType<Exactly<B>>();
  }
  x.expectStaticType<Exactly<A>>();
}

main() {
  testEqNull_assignIfNull();
  testEqNull_eq();
  testNeqNull_assignIfNull();
  testNeqNull_eq();
  testIs_eq();
  testIs_plusEq();
  testIs_postfix();
  testIs_prefix();
}
