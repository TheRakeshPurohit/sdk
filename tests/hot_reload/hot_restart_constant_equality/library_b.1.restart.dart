// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'library_a.dart';

int variableToModifyToForceRecompile = 45;
B get value2 => const B(2);

/** DIFF **/
/*
 
 import 'library_a.dart';
 
-int variableToModifyToForceRecompile = 23;
+int variableToModifyToForceRecompile = 45;
 B get value2 => const B(2);
*/
