// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library source_inset_element;

import 'dart:async';

import 'package:web/web.dart';

import '../../models.dart' as M;
import 'helpers/custom_element.dart';
import 'helpers/rendering_scheduler.dart';
import 'script_inset.dart';

class SourceInsetElement extends CustomElement implements Renderable {
  late RenderingScheduler<SourceInsetElement> _r;

  Stream<RenderedEvent<SourceInsetElement>> get onRendered => _r.onRendered;

  late M.IsolateRef _isolate;
  late M.SourceLocation _location;
  late M.ScriptRepository _scripts;
  late M.ObjectRepository _objects;
  late M.EventRepository _events;
  int? _currentPos;
  late bool _inDebuggerContext;
  late Iterable _variables;

  M.IsolateRef get isolate => _isolate;
  M.SourceLocation get location => _location;

  factory SourceInsetElement(
    M.IsolateRef isolate,
    M.SourceLocation location,
    M.ScriptRepository scripts,
    M.ObjectRepository objects,
    M.EventRepository events, {
    int? currentPos,
    bool inDebuggerContext = false,
    Iterable variables = const [],
    RenderingQueue? queue,
  }) {
    SourceInsetElement e = new SourceInsetElement.created();
    e._r = new RenderingScheduler<SourceInsetElement>(e, queue: queue);
    e._isolate = isolate;
    e._location = location;
    e._scripts = scripts;
    e._objects = objects;
    e._events = events;
    e._currentPos = currentPos;
    e._inDebuggerContext = inDebuggerContext;
    e._variables = variables;
    return e;
  }

  SourceInsetElement.created() : super.created('source-inset');

  @override
  void attached() {
    super.attached();
    _r.enable();
  }

  @override
  void detached() {
    super.detached();
    removeChildren();
    _r.disable(notify: true);
  }

  void render() {
    children = <HTMLElement>[
      new ScriptInsetElement(
        _isolate,
        _location.script!,
        _scripts,
        _objects,
        _events,
        startPos: _location.tokenPos,
        endPos: _location.endTokenPos,
        currentPos: _currentPos,
        inDebuggerContext: _inDebuggerContext,
        variables: _variables,
        queue: _r.queue,
      ).element,
    ];
  }
}
