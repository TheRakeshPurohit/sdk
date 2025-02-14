// TODO(multitest): This was automatically migrated from a multitest and may
// contain strange or dead code.

// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Test for F-Bounded Quantification.

class FBound<F extends FBound<F>> {}

class Bar extends FBound<Bar> {}

class SubBar extends Bar {}

class Baz<T> extends FBound<Baz<T>> {}

class SubBaz<T> extends Baz<T> {}

main() {
  FBound<Bar> fb = new FBound<Bar>();

  FBound<Baz<Bar>> fbb = new FBound<Baz<Bar>>();
}
