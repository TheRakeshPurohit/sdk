// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

class Ticker {
  final Stopwatch sw = new Stopwatch()..start();

  bool isVerbose;

  late Duration previousTick;

  Ticker({this.isVerbose = true}) {
    previousTick = sw.elapsed;
  }

  void logMs(Object message) {
    log(
        // Coverage-ignore(suite): Not run.
        (Duration elapsed, Duration sinceStart) {
      print("$sinceStart: $message in ${elapsed.inMilliseconds}ms.");
    });
  }

  void log(void f(Duration elapsed, Duration sinceStart)) {
    Duration elapsed = sw.elapsed;
    try {
      if (isVerbose) {
        // Coverage-ignore-block(suite): Not run.
        f(elapsed - previousTick, elapsed);
      }
    } finally {
      previousTick = sw.elapsed;
    }
  }

  void reset() {
    sw.reset();
    previousTick = sw.elapsed;
  }
}
