// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/fix.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:linter/src/lint_names.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'fix_processor.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(InlineTypedefBulkTest);
    defineReflectiveTests(InlineTypedefTest);
    defineReflectiveTests(InlineTypedefWithNullSafetyTest);
  });
}

@reflectiveTest
class InlineTypedefBulkTest extends BulkFixProcessorTest {
  @override
  String get lintCode => LintNames.avoid_private_typedef_functions;

  Future<void> test_singleFile() async {
    await resolveTestCode('''
typedef _F1 = void Function(int);
typedef _F2<T> = void Function(T);
void g(_F2<_F1> f) {}
''');
    // Eventually both fixes will be applied but for now we're satisfied that
    // the results are clean.
    await assertHasFix('''
typedef _F2<T> = void Function(T);
void g(_F2<void Function(int)> f) {}
''');
  }
}

@reflectiveTest
class InlineTypedefTest extends FixProcessorLintTest {
  @override
  FixKind get kind => DartFixKind.INLINE_TYPEDEF;

  @override
  String get lintCode => LintNames.avoid_private_typedef_functions;

  Future<void> test_generic_parameter_optionalNamed() async {
    await resolveTestCode('''
typedef _F = Function({int i});
void g(_F f) {}
''');
    await assertHasFix('''
void g(Function({int i}) f) {}
''');
  }

  Future<void> test_generic_parameter_optionalPositional_withName() async {
    await resolveTestCode('''
typedef _F = Function([int i]);
void g(_F f) {}
''');
    await assertHasFix('''
void g(Function([int]) f) {}
''');
  }

  Future<void> test_generic_parameter_optionalPositional_withoutName() async {
    await resolveTestCode('''
typedef _F = Function([int]);
void g(_F f) {}
''');
    await assertHasFix('''
void g(Function([int]) f) {}
''');
  }

  Future<void> test_generic_parameter_requiredPositional_withName() async {
    await resolveTestCode('''
typedef _F = Function(int i);
void g(_F f) {}
''');
    await assertHasFix('''
void g(Function(int) f) {}
''');
  }

  Future<void> test_generic_parameter_requiredPositional_withoutName() async {
    await resolveTestCode('''
typedef _F = Function(int);
void g(_F f) {}
''');
    await assertHasFix('''
void g(Function(int) f) {}
''');
  }

  Future<void> test_generic_returnType() async {
    await resolveTestCode('''
typedef _F = void Function();
void g(_F f) {}
''');
    await assertHasFix('''
void g(void Function() f) {}
''');
  }

  Future<void> test_generic_typeParameters() async {
    await resolveTestCode('''
typedef _F = Function<T>(T);
void g(_F f) {}
''');
    await assertHasFix('''
void g(Function<T>(T) f) {}
''');
  }

  Future<void> test_nonGeneric_parameter_requiredPositional_typed() async {
    await resolveTestCode('''
typedef _F(int i);
void g(_F f) {}
''');
    await assertHasFix('''
void g(Function(int) f) {}
''');
  }

  Future<void> test_nonGeneric_parameter_requiredPositional_untyped() async {
    await resolveTestCode('''
typedef _F(i);
void g(_F f) {}
''');
    await assertHasFix('''
void g(Function(dynamic) f) {}
''');
  }

  Future<void> test_nonGeneric_returnType() async {
    await resolveTestCode('''
typedef void _F();
void g(_F f) {}
''');
    await assertHasFix('''
void g(void Function() f) {}
''');
  }

  Future<void> test_nonGeneric_typeParameters() async {
    await resolveTestCode('''
typedef _F<T>(T t);
void g(_F f) {}
''');
    await assertHasFix('''
void g(Function<T>(T) f) {}
''');
  }
}

@reflectiveTest
class InlineTypedefWithNullSafetyTest extends InlineTypedefTest
    with WithNullSafetyLintMixin {
  Future<void> test_generic_parameter_requiredNamed() async {
    await resolveTestCode('''
typedef _F = Function({required int i});
void g(_F f) {}
''');
    await assertHasFix('''
void g(Function({required int i}) f) {}
''');
  }

  Future<void> test_nonGeneric_parameter_requiredNamed() async {
    await resolveTestCode('''
typedef _F({required int i});
void g(_F f) {}
''');
    await assertHasFix('''
void g(Function({required int i}) f) {}
''');
  }
}
