// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:web/web.dart';

import 'package:observatory/models.dart' as M show IsolateRef, PcDescriptorsRef;
import 'package:observatory/src/elements/helpers/custom_element.dart';
import 'package:observatory/src/elements/helpers/rendering_scheduler.dart';
import 'package:observatory/src/elements/helpers/uris.dart';

class PcDescriptorsRefElement extends CustomElement implements Renderable {
  late RenderingScheduler<PcDescriptorsRefElement> _r;

  Stream<RenderedEvent<PcDescriptorsRefElement>> get onRendered =>
      _r.onRendered;

  late M.IsolateRef _isolate;
  late M.PcDescriptorsRef _descriptors;

  M.IsolateRef get isolate => _isolate;
  M.PcDescriptorsRef get descriptors => _descriptors;

  factory PcDescriptorsRefElement(
      M.IsolateRef isolate, M.PcDescriptorsRef descriptors,
      {RenderingQueue? queue}) {
    PcDescriptorsRefElement e = new PcDescriptorsRefElement.created();
    e._r = new RenderingScheduler<PcDescriptorsRefElement>(e, queue: queue);
    e._isolate = isolate;
    e._descriptors = descriptors;
    return e;
  }

  PcDescriptorsRefElement.created() : super.created('pc-ref');

  @override
  void attached() {
    super.attached();
    _r.enable();
  }

  @override
  void detached() {
    super.detached();
    _r.disable(notify: true);
    removeChildren();
  }

  void render() {
    final text = (_descriptors.name == null || _descriptors.name == '')
        ? 'PcDescriptors'
        : _descriptors.name;
    children = <HTMLElement>[
      new HTMLAnchorElement()
        ..href = Uris.inspect(_isolate, object: _descriptors)
        ..text = text ?? ''
    ];
  }
}
