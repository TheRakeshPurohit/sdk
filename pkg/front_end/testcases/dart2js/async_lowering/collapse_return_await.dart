// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

Future<int> bar() {
  return Future.value(123);
}

// Simple return-await statement.
Future<int> foo1() async {
  return await bar();
}

// Multiple return-await statements.
Future<int> foo2(bool x) async {
  if (x) return await Future.value(345);
  return await bar();
}

// Combination of await and non-await returns. Wrap unawaited returns.
Future<int> foo3(bool x) async {
  if (x) return 234;
  return await Future.value(123);
}

void main() {
  foo1();
  foo2(true);
  foo3(true);
}
