// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/fix.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:linter/src/lint_names.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'fix_processor.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ConvertToSpreadBulkTest);
    defineReflectiveTests(ConvertToSpreadTest);
  });
}

@reflectiveTest
class ConvertToSpreadBulkTest extends BulkFixProcessorTest {
  @override
  String get lintCode => LintNames.prefer_spread_collections;

  Future<void> test_singleFile() async {
    await resolveTestCode('''
f() {
  var ints = [1, 2, 3];
  print(['a']..addAll(ints.map((i) => i.toString()))..addAll(['c']));
}

f2() {
  bool condition;
  var things;
  var l = ['a']..addAll(condition ? things : []);
}
''');
    await assertHasFix('''
f() {
  var ints = [1, 2, 3];
  print(['a', ...ints.map((i) => i.toString())]..addAll(['c']));
}

f2() {
  bool condition;
  var things;
  var l = ['a', if (condition) ...things];
}
''');
  }
}

@reflectiveTest
class ConvertToSpreadTest extends FixProcessorLintTest {
  @override
  FixKind get kind => DartFixKind.CONVERT_TO_SPREAD;

  @override
  String get lintCode => LintNames.prefer_spread_collections;

  /// More coverage in the `convert_to_spread_test.dart` assist test.
  Future<void> test_addAll_expression() async {
    await resolveTestCode('''
f() {
  var ints = [1, 2, 3];
  print(['a']..addAll(ints.map((i) => i.toString()))..addAll(['c']));
}
''');
    await assertHasFix('''
f() {
  var ints = [1, 2, 3];
  print(['a', ...ints.map((i) => i.toString())]..addAll(['c']));
}
''');
  }
}
