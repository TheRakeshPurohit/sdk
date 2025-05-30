// Copyright 2015 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';

export 'package:flutter/foundation.dart' show required;
export 'package:flutter/foundation.dart' show Key, LocalKey, ValueKey;

typedef void VoidCallback();

typedef WidgetBuilder = Widget Function(BuildContext context);

abstract class BuildContext {
  bool get mounted;
  Widget get widget;
}

abstract class RenderObjectWidget extends Widget {
  const RenderObjectWidget({Key? key}) : super(key: key);
}

abstract class SingleChildRenderObjectWidget extends RenderObjectWidget {
  final Widget? child;

  const SingleChildRenderObjectWidget({Key? key, this.child}) : super(key: key);
}

abstract class State<T extends StatefulWidget> {
  BuildContext get context => null;

  bool get mounted => false;

  T get widget => null;

  Widget build(BuildContext context) => null;

  void dispose() {}

  void initState() {}

  void setState(VoidCallback fn) {}
}

abstract class StatefulWidget extends Widget {
  const StatefulWidget({Key? key}) : super(key: key);

  State createState() => null;
}

abstract class StatelessWidget extends Widget {
  const StatelessWidget({Key? key}) : super(key: key);

  Widget build(BuildContext context) => null;
}

class Widget extends DiagnosticableTree {
  final Key? key;

  const Widget({this.key});

  bool get mounted => true;

  void debugFillProperties(DiagnosticPropertiesBuilder properties) {}
}
