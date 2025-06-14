// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/assist.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'assist_processor.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(SplitAndConditionTest);
  });
}

@reflectiveTest
class SplitAndConditionTest extends AssistProcessorTest {
  @override
  AssistKind get kind => DartAssistKind.splitAndCondition;

  Future<void> test_hasElse() async {
    await resolveTestCode('''
void f() {
  if (1 == 1 ^&& 2 == 2) {
    print(1);
  } else {
    print(2);
  }
}
''');
    await assertNoAssist();
  }

  Future<void> test_innerAndExpression() async {
    await resolveTestCode('''
void f() {
  if (1 == 1 ^&& 2 == 2 && 3 == 3) {
    print(0);
  }
}
''');
    await assertHasAssist('''
void f() {
  if (1 == 1) {
    if (2 == 2 && 3 == 3) {
      print(0);
    }
  }
}
''');
  }

  Future<void> test_notAnd() async {
    await resolveTestCode('''
void f() {
  if (1 == 1 ^|| 2 == 2) {
    print(0);
  }
}
''');
    await assertNoAssist();
  }

  Future<void> test_notOnOperator() async {
    await resolveTestCode('''
void ^f() {
  if (1 == 1 && 2 == 2) {
    print(0);
  }
  print(3 == 3 && 4 == 4);
}
''');
    await assertNoAssist();
  }

  Future<void> test_notPartOfIf() async {
    await resolveTestCode('''
void f() {
  print(1 == 1 ^&& 2 == 2);
}
''');
    await assertNoAssist();
  }

  Future<void> test_notTopLevelAnd() async {
    await resolveTestCode('''
void f() {
  if (true || (1 == 1 /*0*/&& 2 == 2)) {
    print(0);
  }
  if (true && (3 == 3 /*1*/&& 4 == 4)) {
    print(0);
  }
}
''');
    await assertNoAssist();
    await assertNoAssist(1);
  }

  Future<void> test_selectionTooLarge() async {
    await resolveTestCode('''
void f() {
  if (1 == 1 [!&& 2!] == 2) {
    print(0);
  }
  print(3 == 3 && 4 == 4);
}
''');
    await assertNoAssist();
  }

  Future<void> test_thenBlock() async {
    await resolveTestCode('''
void f() {
  if (true ^&& false) {
    print(0);
    if (3 == 3) {
      print(1);
    }
  }
}
''');
    await assertHasAssist('''
void f() {
  if (true) {
    if (false) {
      print(0);
      if (3 == 3) {
        print(1);
      }
    }
  }
}
''');
  }

  Future<void> test_thenStatement() async {
    await resolveTestCode('''
void f() {
  if (true ^&& false)
    print(0);
}
''');
    await assertHasAssist('''
void f() {
  if (true)
    if (false)
      print(0);
}
''');
  }
}
