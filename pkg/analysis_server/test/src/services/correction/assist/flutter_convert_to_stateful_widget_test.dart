// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/assist.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'assist_processor.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(FlutterConvertToStatefulWidgetTest);
  });
}

@reflectiveTest
class FlutterConvertToStatefulWidgetTest extends AssistProcessorTest {
  @override
  AssistKind get kind => DartAssistKind.flutterConvertToStatefulWidget;

  @override
  void setUp() {
    super.setUp();
    writeTestPackageConfig(flutter: true);
  }

  Future<void> test_comment() async {
    await resolveTestCode(r'''
import 'package:flutter/material.dart';

class ^MyWidget extends StatelessWidget {
  // something for a
  final bool a = false;

  const MyWidget();

  // another for b
  final bool b = true;

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
''');
    await assertHasAssist('''
import 'package:flutter/material.dart';

class MyWidget extends StatefulWidget {

  const MyWidget();

  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  // something for a
  final bool a = false;

  // another for b
  final bool b = true;

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
''');
  }

  Future<void> test_comment_documentation() async {
    await resolveTestCode(r'''
import 'package:flutter/material.dart';

class ^MyWidget extends StatelessWidget {
  /// something for a
  final bool a = false;

  const MyWidget();

  /// another for b
  final bool b = true;

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
''');
    await assertHasAssist('''
import 'package:flutter/material.dart';

class MyWidget extends StatefulWidget {

  const MyWidget();

  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  /// something for a
  final bool a = false;

  /// another for b
  final bool b = true;

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
''');
  }

  Future<void> test_empty() async {
    await resolveTestCode(r'''
import 'package:flutter/material.dart';

class ^MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
''');
    await assertHasAssist(r'''
import 'package:flutter/material.dart';

class MyWidget extends StatefulWidget {
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
''');
  }

  Future<void> test_empty_typeParam() async {
    await resolveTestCode(r'''
import 'package:flutter/material.dart';

class ^MyWidget<T> extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
''');
    await assertHasAssist(r'''
import 'package:flutter/material.dart';

class MyWidget<T> extends StatefulWidget {
  @override
  State<MyWidget<T>> createState() => _MyWidgetState<T>();
}

class _MyWidgetState<T> extends State<MyWidget<T>> {
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
''');
  }

  Future<void> test_fields() async {
    await resolveTestCode(r'''
import 'package:flutter/material.dart';

class ^MyWidget extends StatelessWidget {
  static String staticField1 = '';
  final String instanceField1;
  final String instanceField2;
  String instanceField3 = '';
  static String staticField2 = '';
  String instanceField4 = '';
  String instanceField5 = '';
  static String staticField3 = '';

  MyWidget(this.instanceField1) : instanceField2 = '' {
    instanceField3 = '';
  }

  @override
  Widget build(BuildContext context) {
    instanceField4 = instanceField1;
    return Row(
      children: [
        Text(instanceField1),
        Text(instanceField2),
        Text(instanceField3),
        Text(instanceField4),
        Text(instanceField5),
        Text(staticField1),
        Text(staticField2),
        Text(staticField3),
      ],
    );
  }
}
''');
    await assertHasAssist(r'''
import 'package:flutter/material.dart';

class MyWidget extends StatefulWidget {
  static String staticField1 = '';
  final String instanceField1;
  final String instanceField2;
  String instanceField3 = '';
  static String staticField2 = '';
  static String staticField3 = '';

  MyWidget(this.instanceField1) : instanceField2 = '' {
    instanceField3 = '';
  }

  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  String instanceField4 = '';

  String instanceField5 = '';

  @override
  Widget build(BuildContext context) {
    instanceField4 = widget.instanceField1;
    return Row(
      children: [
        Text(widget.instanceField1),
        Text(widget.instanceField2),
        Text(widget.instanceField3),
        Text(instanceField4),
        Text(instanceField5),
        Text(MyWidget.staticField1),
        Text(MyWidget.staticField2),
        Text(MyWidget.staticField3),
      ],
    );
  }
}
''');
  }

  Future<void> test_getters() async {
    await resolveTestCode(r'''
import 'package:flutter/material.dart';

class ^MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(staticGetter1),
        Text(staticGetter2),
        Text(instanceGetter1),
        Text(instanceGetter2),
      ],
    );
  }

  static String get staticGetter1 => '';

  String get instanceGetter1 => '';

  static String get staticGetter2 => '';

  String get instanceGetter2 => '';
}
''');
    await assertHasAssist(r'''
import 'package:flutter/material.dart';

class MyWidget extends StatefulWidget {
  @override
  State<MyWidget> createState() => _MyWidgetState();

  static String get staticGetter1 => '';

  static String get staticGetter2 => '';
}

class _MyWidgetState extends State<MyWidget> {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(MyWidget.staticGetter1),
        Text(MyWidget.staticGetter2),
        Text(instanceGetter1),
        Text(instanceGetter2),
      ],
    );
  }

  String get instanceGetter1 => '';

  String get instanceGetter2 => '';
}
''');
  }

  Future<void> test_methods() async {
    await resolveTestCode(r'''
import 'package:flutter/material.dart';

class ^MyWidget extends StatelessWidget {
  static String staticField = '';
  final String instanceField1;
  String instanceField2 = '';

  MyWidget(this.instanceField1);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(instanceField1),
        Text(instanceField2),
        Text(staticField),
      ],
    );
  }

  void instanceMethod1() {
    instanceMethod1();
    instanceMethod2();
    staticMethod1();
  }

  static void staticMethod1() {
    print('static 1');
  }

  void instanceMethod2() {
    print('instance 2');
  }

  static void staticMethod2() {
    print('static 2');
  }
}
''');
    await assertHasAssist(r'''
import 'package:flutter/material.dart';

class MyWidget extends StatefulWidget {
  static String staticField = '';
  final String instanceField1;

  MyWidget(this.instanceField1);

  @override
  State<MyWidget> createState() => _MyWidgetState();

  static void staticMethod1() {
    print('static 1');
  }

  static void staticMethod2() {
    print('static 2');
  }
}

class _MyWidgetState extends State<MyWidget> {
  String instanceField2 = '';

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(widget.instanceField1),
        Text(instanceField2),
        Text(MyWidget.staticField),
      ],
    );
  }

  void instanceMethod1() {
    instanceMethod1();
    instanceMethod2();
    MyWidget.staticMethod1();
  }

  void instanceMethod2() {
    print('instance 2');
  }
}
''');
  }

  Future<void> test_noExtraUnderscore() async {
    await resolveTestCode(r'''
import 'package:flutter/material.dart';

class ^_MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
''');
    await assertHasAssist(r'''
import 'package:flutter/material.dart';

class _MyWidget extends StatefulWidget {
  @override
  State<_MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<_MyWidget> {
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
''');
  }

  Future<void> test_notClass() async {
    await resolveTestCode('''
import 'package:flutter/material.dart';
^void f() {}
''');
    await assertNoAssist();
  }

  Future<void> test_notStatelessWidget() async {
    await resolveTestCode('''
import 'package:flutter/material.dart';
class ^MyWidget extends Text {
  MyWidget() : super('');
}
''');
    await assertNoAssist();
  }

  Future<void> test_notWidget() async {
    await resolveTestCode('''
import 'package:flutter/material.dart';
class ^MyWidget {}
''');
    await assertNoAssist();
  }

  Future<void> test_simple() async {
    await resolveTestCode(r'''
import 'package:flutter/material.dart';

class ^MyWidget extends StatelessWidget {
  final String aaa;
  final String bbb;

  const MyWidget(this.aaa, this.bbb);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(aaa),
        Text(bbb),
        Text('$aaa'),
        Text('${bbb}'),
      ],
    );
  }
}
''');
    await assertHasAssist(r'''
import 'package:flutter/material.dart';

class MyWidget extends StatefulWidget {
  final String aaa;
  final String bbb;

  const MyWidget(this.aaa, this.bbb);

  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(widget.aaa),
        Text(widget.bbb),
        Text('${widget.aaa}'),
        Text('${widget.bbb}'),
      ],
    );
  }
}
''');
  }
}
