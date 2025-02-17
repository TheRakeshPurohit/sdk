// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library;

import 'package:compiler/src/dart2js.dart' as dart2js;
import 'dart:io' show Platform;

const iterationsFlagPrefix = "--iterations=";
void main(List<String> args) {
  Stopwatch sw = Stopwatch();
  int count = 0;
  int? maxCount;
  if (args.isNotEmpty && args[0].startsWith(iterationsFlagPrefix)) {
    maxCount = int.parse(args[0].substring(iterationsFlagPrefix.length));
    args = args.sublist(1);
  }
  if (maxCount == null) {
    print(
      "Running indefinitely.\n"
      "Use '$iterationsFlagPrefix<count>' to set a repetition count"
      " (as first flag).",
    );
  }
  args = [
    "--suppress-warnings",
    "--suppress-hints",
    "--libraries-spec="
        "${Platform.script.resolve('../../../sdk/lib/libraries.json').toFilePath()}",
    ...args,
  ];
  void iterate() {
    count++;
    sw.reset();
    sw.start();
    dart2js
        .internalMain(args)
        .then((_) {
          print("$count: ${sw.elapsedMilliseconds}ms");
        })
        .then((_) {
          if (maxCount == null || count < maxCount) {
            iterate();
          }
        });
  }

  iterate();
}
