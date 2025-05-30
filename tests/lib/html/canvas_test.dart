// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library CanvasTest;

import 'dart:html';

import 'package:expect/legacy/async_minitest.dart'; // ignore: deprecated_member_use

main() {
  CanvasElement canvas;
  CanvasRenderingContext2D context;
  int width = 100;
  int height = 100;

  canvas = new CanvasElement(width: width, height: height);
  document.body!.append(canvas);

  context = canvas.context2D;

  test('CreateImageData', () {
    ImageData image = context.createImageData(canvas.width, canvas.height);
    List<int> data = image.data;

    expect(data.length, 40000);
    checkPixel(data, 0, [0, 0, 0, 0]);
    checkPixel(data, width * height - 1, [0, 0, 0, 0]);

    data[100] = 200;
    expect(data[100], equals(200));
  });

  test('toDataUrl', () {
    var canvas = new CanvasElement(width: 100, height: 100);
    var context = canvas.context2D;
    context.fillStyle = 'red';
    context.fill();

    var url = canvas.toDataUrl();

    var img = new ImageElement();
    img.onLoad.listen(
      expectAsync((_) {
        expect(img.complete, true);
      }),
    );
    img.onError.listen((_) {
      fail('URL failed to load.');
    });
    img.src = url;
  });
}

void checkPixel(List<int> data, int offset, List<int> rgba) {
  offset *= 4;
  for (var i = 0; i < 4; ++i) {
    expect(data[offset + i], equals(rgba[i]));
  }
}
