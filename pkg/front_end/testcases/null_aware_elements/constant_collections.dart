// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

const int? expr1 = 5;
const List<int> literal1 = <int>[?expr1];
const List<int> literal1expected = const <int>[5];

const String? expr2 = null;
const Set<String> literal2 = <String>{?expr2};
const Set<String> literal2expected = const <String>{};

const int? key3a = 1;
const int? key3b = null;
const bool value3 = false;
const Map<int, bool> literal3a = <int, bool>{?key3a: value3};
const Map<int, bool> literal3aExpected = <int, bool>{1: false};
const Map<int, bool> literal3b = <int, bool>{?key3b: value3};
const Map<int, bool> literal3bExpected = <int, bool>{};

const Symbol key4 = #key4;
const int? value4a = 0;
const int? value4b = null;
const Map<Symbol, int> literal4a = <Symbol, int>{key4: ?value4a};
const Map<Symbol, int> literal4aExpected = <Symbol, int>{#key4: 0};
const Map<Symbol, int> literal4b = <Symbol, int>{key4: ?value4b};
const Map<Symbol, int> literal4bExpected = <Symbol, int>{};

const bool? key5a = true;
const bool? key5b = null;
const String? value5a = "value5a";
const String? value5b = null;
const Map<bool, String> literal5aa = <bool, String>{?key5a: ?value5a};
const Map<bool, String> literal5aaExpected = <bool, String>{true: "value5a"};
const Map<bool, String> literal5ab = <bool, String>{?key5a: ?value5b};
const Map<bool, String> literal5abExpected = <bool, String>{};
const Map<bool, String> literal5ba = <bool, String>{?key5b: ?value5a};
const Map<bool, String> literal5baExpected = <bool, String>{};
const Map<bool, String> literal5bb = <bool, String>{?key5b: ?value5b};
const Map<bool, String> literal5bbExpected = <bool, String>{};

class Verifier {
  const Verifier.test1() : assert(identical(literal1, literal1expected));
  const Verifier.test2() : assert(identical(literal2, literal2expected));
  const Verifier.test3a() : assert(identical(literal3a, literal3aExpected));
  const Verifier.test3b() : assert(identical(literal3b, literal3bExpected));
  const Verifier.test4a() : assert(identical(literal4a, literal4aExpected));
  const Verifier.test4b() : assert(identical(literal4b, literal4bExpected));
  const Verifier.test5aa() : assert(identical(literal5aa, literal5aaExpected));
  const Verifier.test5ab() : assert(identical(literal5ab, literal5abExpected));
  const Verifier.test5ba() : assert(identical(literal5ba, literal5baExpected));
  const Verifier.test5bb() : assert(identical(literal5bb, literal5bbExpected));
}

Verifier test1 = const Verifier.test1();
Verifier test2 = const Verifier.test2();
Verifier test3a = const Verifier.test3a();
Verifier test3b = const Verifier.test3b();
Verifier test4a = const Verifier.test4a();
Verifier test4b = const Verifier.test4b();
Verifier test5aa = const Verifier.test5aa();
Verifier test5ab = const Verifier.test5ab();
Verifier test5ba = const Verifier.test5ba();
Verifier test5bb = const Verifier.test5bb();
