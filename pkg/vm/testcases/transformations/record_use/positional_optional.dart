// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart' show RecordUse;

void main() {
  print(SomeClass.someStaticMethod(3));
  print(SomeClass.someStaticMethod());
}

class SomeClass {
  @RecordUse()
  static someStaticMethod([int i = 4]) {
    return i + 1;
  }
}
