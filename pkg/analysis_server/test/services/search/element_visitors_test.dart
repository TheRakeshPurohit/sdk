// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/search/element_visitors.dart';
import 'package:analyzer/dart/element/element2.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../../abstract_single_unit.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(FindElementByNameOffsetTest);
  });
}

@reflectiveTest
class FindElementByNameOffsetTest extends AbstractSingleUnitTest {
  Element2 get testUnitElement => testLibraryElement;

  Future<void> test_class() async {
    await resolveTestCode(r'''
class AAA {}
class BBB {}
''');
    _assertElement(6, ElementKind.CLASS, 'AAA');
    _assertElement(19, ElementKind.CLASS, 'BBB');
  }

  Future<void> test_function() async {
    await resolveTestCode(r'''
void aaa() {}
void bbb() {}
''');
    _assertElement(5, ElementKind.FUNCTION, 'aaa');
    _assertElement(19, ElementKind.FUNCTION, 'bbb');
  }

  Future<void> test_null() async {
    await resolveTestCode(r'''
class AAA {}
class BBB {}
''');
    expect(findElementByNameOffset2(null, 0), isNull);

    expect(findElementByNameOffset2(testUnitElement, 0), isNull);
    expect(findElementByNameOffset2(testUnitElement, 1), isNull);

    expect(findElementByNameOffset2(testUnitElement, 5), isNull);
    expect(findElementByNameOffset2(testUnitElement, 7), isNull);
  }

  Future<void> test_topLevelVariable() async {
    await resolveTestCode(r'''
int? aaa, bbb;
int? ccc;
''');
    _assertElement(5, ElementKind.TOP_LEVEL_VARIABLE, 'aaa');
    _assertElement(10, ElementKind.TOP_LEVEL_VARIABLE, 'bbb');
    _assertElement(20, ElementKind.TOP_LEVEL_VARIABLE, 'ccc');
  }

  void _assertElement(int nameOffset, ElementKind kind, String name) {
    var element = findElementByNameOffset2(testUnitElement, nameOffset)!;
    expect(element.kind, kind);
    expect(element.name3, name);
  }
}
