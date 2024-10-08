// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/fix.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:linter/src/lint_names.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'fix_processor.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(RemoveDuplicateCaseBulkTest);
    defineReflectiveTests(RemoveDuplicateCaseTest);
  });
}

@reflectiveTest
class RemoveDuplicateCaseBulkTest extends BulkFixProcessorTest {
  @override
  String get lintCode => LintNames.no_duplicate_case_values;

  @override
  String get testPackageLanguageVersion => '2.19';

  Future<void> test_singleFile() async {
    await resolveTestCode('''
void switchInt() {
  switch (2) {
    case 1:
      print('a');
      break;
    case 2:
    case 2:
    case 3:
    case 3:
    default:
      print('?');
  }
}
''');
    await assertHasFix('''
void switchInt() {
  switch (2) {
    case 1:
      print('a');
      break;
    case 2:
    case 3:
    default:
      print('?');
  }
}
''');
  }
}

@reflectiveTest
class RemoveDuplicateCaseTest extends FixProcessorLintTest {
  @override
  FixKind get kind => DartFixKind.REMOVE_DUPLICATE_CASE;

  @override
  String get lintCode => LintNames.no_duplicate_case_values;

  @override
  String get testPackageLanguageVersion => '2.19';

  Future<void> test_fallThroughFromPrevious() async {
    await resolveTestCode('''
void switchInt() {
  switch (2) {
    case 1:
      print('a');
      break;
    case 2:
    case 3:
    case 2:
      print('b');
      break;
    default:
      print('?');
  }
}
''');
    await assertHasFix('''
void switchInt() {
  switch (2) {
    case 1:
      print('a');
      break;
    case 2:
    case 3:
      print('b');
      break;
    default:
      print('?');
  }
}
''');
  }

  Future<void> test_removeIntCase() async {
    await resolveTestCode('''
void switchInt() {
  switch (2) {
    case 1:
      print('a');
      break;
    case 2:
    case 2:
    default:
      print('?');
  }
}
''');
    await assertHasFix('''
void switchInt() {
  switch (2) {
    case 1:
      print('a');
      break;
    case 2:
    default:
      print('?');
  }
}
''');
  }

  Future<void> test_removeStringCase() async {
    await resolveTestCode('''
void switchString() {
  String v = 'a';
  switch (v) {
    case 'a':
      print('a');
      break;
    case 'b':
      print('b');
      break;
    case 'a':
      print('a');
      break;
    default:
      print('?');
  }
}
''');
    await assertHasFix('''
void switchString() {
  String v = 'a';
  switch (v) {
    case 'a':
      print('a');
      break;
    case 'b':
      print('b');
      break;
    default:
      print('?');
  }
}
''');
  }
}
