// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:web/web.dart';

import '../../models.dart' as M;
import 'curly_block.dart';
import 'helpers/any_ref.dart';
import 'helpers/custom_element.dart';
import 'helpers/element_utils.dart';
import 'helpers/rendering_scheduler.dart';

class StronglyReachableInstancesElement extends CustomElement
    implements Renderable {
  late RenderingScheduler<StronglyReachableInstancesElement> _r;

  Stream<RenderedEvent<StronglyReachableInstancesElement>> get onRendered =>
      _r.onRendered;

  late M.IsolateRef _isolate;
  late M.ClassRef _cls;
  late M.StronglyReachableInstancesRepository _stronglyReachableInstances;
  late M.ObjectRepository _objects;
  M.InstanceSet? _result;
  bool _expanded = false;

  M.IsolateRef get isolate => _isolate;
  M.ClassRef get cls => _cls;

  factory StronglyReachableInstancesElement(
    M.IsolateRef isolate,
    M.ClassRef cls,
    M.StronglyReachableInstancesRepository stronglyReachable,
    M.ObjectRepository objects, {
    RenderingQueue? queue,
  }) {
    StronglyReachableInstancesElement e =
        new StronglyReachableInstancesElement.created();
    e._r = new RenderingScheduler<StronglyReachableInstancesElement>(
      e,
      queue: queue,
    );
    e._isolate = isolate;
    e._cls = cls;
    e._stronglyReachableInstances = stronglyReachable;
    e._objects = objects;
    return e;
  }

  StronglyReachableInstancesElement.created()
    : super.created('strongly-reachable-instances');

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
      (new CurlyBlockElement(expanded: _expanded, queue: _r.queue)
            ..content = _createContent()
            ..onToggle.listen((e) async {
              _expanded = e.control.expanded;
              e.control.disabled = true;
              await _refresh();
              e.control.disabled = false;
            }))
          .element,
    ];
  }

  Future _refresh() async {
    _result = null;
    _result = await _stronglyReachableInstances.get(_isolate, _cls);
    _r.dirty();
  }

  List<HTMLElement> _createContent() {
    if (_result == null) {
      return [new HTMLSpanElement()..textContent = 'Loading...'];
    }
    final content = _result!.instances!
        .map<HTMLElement>(
          (sample) => new HTMLDivElement()
            ..appendChild(anyRef(_isolate, sample, _objects, queue: _r.queue)),
        )
        .toList();
    content.add(
      new HTMLDivElement()..appendChildren(
        []
          ..addAll(_createShowMoreButton())
          ..add(
            new HTMLSpanElement()..textContent = ' of total ${_result!.count}',
          ),
      ),
    );
    return content;
  }

  List<HTMLElement> _createShowMoreButton() {
    final samples = _result!.instances!.toList();
    if (samples.length == _result!.count) {
      return [];
    }
    final count = samples.length;
    final button = new HTMLButtonElement()..textContent = 'show next ${count}';
    button.onClick.listen((_) async {
      button.disabled = true;
      _result = await _stronglyReachableInstances.get(
        _isolate,
        _cls,
        limit: count * 2,
      );
      _r.dirty();
    });
    return [button];
  }
}
