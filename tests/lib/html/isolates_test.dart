// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library IsolatesTest;

import 'package:expect/legacy/async_minitest.dart'; // ignore: deprecated_member_use
import 'dart:async';
import 'dart:html';
import 'dart:convert';
import 'dart:isolate' as isolate;

String responseFor(message) => 'response for $message';

void isolateEntry(isolate.SendPort initialReplyTo) {
  var port = new isolate.ReceivePort();
  initialReplyTo.send(port.sendPort);

  bool wasThrown = false;
  try {
    window.alert('Test');
  } catch (e) {
    wasThrown = true;
  }
  // If wasn't thrown, do not listen to messages to make test fail.
  if (!wasThrown) {
    return;
  }

  // Check that convert library was loaded to isolate.
  json.encode([1, 2, 3]);

  port.listen((message) {
    var data = message[0];
    var replyTo = message[1];
    replyTo.send(responseFor(data));
  });
}

Future sendReceive(isolate.SendPort port, msg) {
  var response = new isolate.ReceivePort();
  port.send([msg, response.sendPort]);
  return response.first;
}

main() {
  test('IsolateSpawn', () {
    var port = new isolate.ReceivePort();
    isolate.Isolate.spawn(isolateEntry, port.sendPort);
    port.close();
  });
  test('NonDOMIsolates', () {
    var callback = expectAsync(() {});
    var response = new isolate.ReceivePort();
    var remote = isolate.Isolate.spawn(isolateEntry, response.sendPort);
    response.first.then((port) {
      final msg1 = 'foo';
      final msg2 = 'bar';
      sendReceive(port, msg1).then((response) {
        expect(response, equals(responseFor(msg1)));
        sendReceive(port, msg2).then((response) {
          expect(response, equals(responseFor(msg2)));
          callback();
        });
      });
    });
  });
}
