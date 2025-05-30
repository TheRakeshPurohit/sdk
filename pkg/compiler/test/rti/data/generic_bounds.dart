// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:compiler/src/util/testing.dart';

/*spec.class: Class1a:explicit=[Class1a]*/
class Class1a {}

class Class1b extends Class1a {}

/*spec.class: Class2a:explicit=[Class2a<num>],needsArgs*/
class Class2a<T> {}

class Class2b<T> extends Class2a<T> {}

/*spec.member: method1:needsArgs,selectors=[Selector(call, call, arity=0, types=1)]*/
method1<T extends Class1a>() => null;

/*spec.member: method2:needsArgs,selectors=[Selector(call, call, arity=0, types=1)]*/
method2<T extends Class2a<num>>() => null;

method3<T>() => null;

class Class3 {
  /*spec.member: Class3.method4:needsArgs,selectors=[Selector(call, method4, arity=0, types=1)]*/
  method4<T extends Class1a>() => null;

  /*spec.member: Class3.method5:needsArgs,selectors=[Selector(call, method5, arity=0, types=1)]*/
  method5<T extends Class2a<num>>() => null;

  method6<T>() => null;
}

/*spec.class: Class4:explicit=[Class4]*/
class Class4 {}

/*spec.member: method10:needsArgs*/
method10<T extends Class4>() => null;

main() {
  /*spec.needsArgs,selectors=[Selector(call, call, arity=0, types=1)]*/
  /*prod.*/
  method7<T extends Class1a>() => null;

  /*spec.needsArgs,selectors=[Selector(call, call, arity=0, types=1)]*/
  /*prod.*/
  method8<T extends Class2a<num>>() => null;

  /**/
  method9<T>() => null;

  dynamic f1 = method1;
  dynamic f2 = method2;
  dynamic f3 = method3;
  dynamic c3 = Class3();
  dynamic f7 = method7;
  dynamic f8 = method8;
  dynamic f9 = method9;

  f1<Class1b>();
  f2<Class2b<int>>();
  f3<int>();
  c3.method4<Class1b>();
  c3.method5<Class2b<int>>();
  c3.method6<int>();
  f7<Class1b>();
  f8<Class2b<int>>();
  f9<int>();

  makeLive(/**/ () => f1<Class2a<num>>());
  makeLive(/**/ () => f2<Class2b<String>>());
  makeLive(/**/ () => c3.method4<Class2a<num>>());
  makeLive(/**/ () => c3.method5<Class2b<String>>());
  makeLive(/**/ () => f7<Class2a<num>>());
  makeLive(/**/ () => f8<Class2b<String>>());

  method10();
}
