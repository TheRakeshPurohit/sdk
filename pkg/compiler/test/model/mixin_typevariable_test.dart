// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library mixin_typevariable_test;

import 'package:compiler/src/elements/entities.dart';
import 'package:compiler/src/elements/types.dart';
import 'package:expect/async_helper.dart';
import 'package:expect/expect.dart';
import '../helpers/type_test_helper.dart';

void main() {
  asyncTest(() async {
    await testMixinSupertypes();
    await testNonTrivialSubstitutions();
  });
}

testMixinSupertypes() async {
  var env = await TypeEnvironment.create(r"""
      class S<S_T> {}
      mixin M1<M1_T> {}
      mixin M2<M2_T> {}
      mixin M3<M3_T> {}

      class C1<C1_T> extends S<C1_T> with M1<C1_T>, M2<C1_T>, M3<C1_T> {}
      class C2<C2_T> = S<C2_T> with M1<C2_T>, M2<C2_T>, M3<C2_T>;

      main() {
        C1();
        C2();
      }
      """, expectNoWarningsOrErrors: true);
  ClassEntity Object = env.getElement('Object') as ClassEntity;
  ClassEntity S = env.getClass('S');
  ClassEntity M1 = env.getClass('M1');
  ClassEntity M2 = env.getClass('M2');
  ClassEntity C1 = env.getClass('C1');
  ClassEntity C2 = env.getClass('C2');

  ClassEntity C1_S_M1_M2_M3 = env.elementEnvironment.getSuperClass(C1)!;
  ClassEntity C1_S_M1_M2 = env.elementEnvironment.getSuperClass(C1_S_M1_M2_M3)!;
  ClassEntity C1_S_M1 = env.elementEnvironment.getSuperClass(C1_S_M1_M2)!;

  ClassEntity C2_S_M1_M2 = env.elementEnvironment.getSuperClass(C2)!;
  ClassEntity C2_S_M1 = env.elementEnvironment.getSuperClass(C2_S_M1_M2)!;

  void testSupertypes(ClassEntity element) {
    List<DartType> typeVariables = const <DartType>[];
    if (element != Object) {
      typeVariables = env.elementEnvironment.getThisType(element).typeArguments;
      Expect.isTrue(typeVariables.length == 1);
      final typeVariable = typeVariables.first as TypeVariableType;
      Expect.equals(element, typeVariable.element.typeDeclaration);
    }
    env.elementEnvironment.forEachSupertype(element, (InterfaceType supertype) {
      if (!supertype.typeArguments.isEmpty) {
        Expect.listEquals(
          env.printTypes(typeVariables),
          env.printTypes(supertype.typeArguments),
          "Type argument mismatch on supertype $supertype of $element.",
        );
      } else {
        Expect.equals(Object, supertype.element);
      }
    });
  }

  testSupertypes(Object);
  testSupertypes(S);
  testSupertypes(M1);
  testSupertypes(M2);
  testSupertypes(C1_S_M1);
  testSupertypes(C1_S_M1_M2);
  testSupertypes(C1_S_M1_M2_M3);
  testSupertypes(C1);
  testSupertypes(C2_S_M1);
  testSupertypes(C2_S_M1_M2);
  testSupertypes(C2);
}

testNonTrivialSubstitutions() async {
  var env = await TypeEnvironment.create(r"""
      class X {}
      class A<A_T> {}
      mixin B<B_T, B_S> {}

      class C1<C1_T> extends A with B {}
      class C2<C2_T> = A with B;

      class D1<D1_T> extends A<D1_T> with B<D1_T, A<D1_T>> {}
      class D2<D2_T> = A<D2_T> with B<D2_T, A<D2_T>>;

      class E1<E1_T> extends A<X> with B<X, A<X>> {}
      class E2<E2_T> = A<X> with B<X, A<X>>;

      class F1<F1_T> extends A<X> with B<X, B<F1_T, X>> {}
      class F2<F2_T> = A<X> with B<X, B<F2_T, X>>;

      main() {
        C1();
        C2();
        D1();
        D2();
        E1();
        E2();
        F1();
        F2();
      }
      """, expectNoWarningsOrErrors: true);
  var types = env.types;
  DartType _dynamic = env['dynamic'];
  DartType X = env['X'];

  ClassEntity Object = env.getElement('Object') as ClassEntity;
  ClassEntity A = env.getClass('A');
  ClassEntity B = env.getClass('B');
  ClassEntity C1 = env.getClass('C1');
  ClassEntity C2 = env.getClass('C2');
  ClassEntity D1 = env.getClass('D1');
  ClassEntity D2 = env.getClass('D2');
  ClassEntity E1 = env.getClass('E1');
  ClassEntity E2 = env.getClass('E2');
  ClassEntity F1 = env.getClass('F1');
  ClassEntity F2 = env.getClass('F2');

  void testSupertypes(
    ClassEntity element,
    Map<ClassEntity, List<DartType>> typeArguments,
  ) {
    List<DartType> typeVariables = const <DartType>[];
    if (element != Object) {
      typeVariables = env.elementEnvironment.getThisType(element).typeArguments;
      if (env.elementEnvironment.isUnnamedMixinApplication(element)) {
        // Kernel doesn't add type variables to unnamed mixin applications when
        // these aren't need for its supertypes.
        Expect.isTrue(typeVariables.length <= 1);
      } else {
        Expect.isTrue(typeVariables.length == 1);
      }
      if (typeVariables.isNotEmpty) {
        final typeVariable = typeVariables.first as TypeVariableType;
        Expect.equals(element, typeVariable.element.typeDeclaration);
      }
    }
    env.elementEnvironment.forEachSupertype(element, (InterfaceType supertype) {
      if (typeArguments.containsKey(supertype.element)) {
        Expect.listEquals(
          env.printTypes(typeArguments[supertype.element]!),
          env.printTypes(supertype.typeArguments),
          "Type argument mismatch on supertype $supertype of $element.",
        );
      } else if (!supertype.typeArguments.isEmpty) {
        Expect.listEquals(
          env.printTypes(typeVariables),
          env.printTypes(supertype.typeArguments),
          "Type argument mismatch on supertype $supertype of $element.",
        );
      } else if (env.elementEnvironment.isUnnamedMixinApplication(
        supertype.element,
      )) {
        // Kernel doesn't add type variables to unnamed mixin applications when
        // these aren't need for its supertypes.
        Expect.isTrue(
          supertype.typeArguments.isEmpty,
          "Type argument mismatch on supertype $supertype of $element.",
        );
      } else {
        Expect.equals(
          Object,
          supertype.element,
          "Type argument mismatch on supertype $supertype of $element.",
        );
      }
    });
  }

  testSupertypes(C1, {
    A: [_dynamic],
    B: [_dynamic, _dynamic],
  });
  testSupertypes(env.elementEnvironment.getSuperClass(C1)!, {
    A: [_dynamic],
    B: [_dynamic, _dynamic],
  });
  testSupertypes(C2, {
    A: [_dynamic],
    B: [_dynamic, _dynamic],
  });

  DartType D1_T = env.elementEnvironment.getThisType(D1).typeArguments.first;
  testSupertypes(D1, {
    A: [D1_T],
    B: [
      D1_T,
      instantiate(types, A, [D1_T]),
    ],
  });
  DartType D1_superclass_T = env.elementEnvironment
      .getThisType(env.elementEnvironment.getSuperClass(D1)!)
      .typeArguments
      .first;
  testSupertypes(env.elementEnvironment.getSuperClass(D1)!, {
    A: [D1_superclass_T],
    B: [
      D1_superclass_T,
      instantiate(types, A, [D1_superclass_T]),
    ],
  });
  DartType D2_T = env.elementEnvironment.getThisType(D2).typeArguments.first;
  testSupertypes(D2, {
    A: [D2_T],
    B: [
      D2_T,
      instantiate(types, A, [D2_T]),
    ],
  });

  testSupertypes(E1, {
    A: [X],
    B: [
      X,
      instantiate(types, A, [X]),
    ],
  });
  testSupertypes(env.elementEnvironment.getSuperClass(E1)!, {
    A: [X],
    B: [
      X,
      instantiate(types, A, [X]),
    ],
  });
  testSupertypes(E2, {
    A: [X],
    B: [
      X,
      instantiate(types, A, [X]),
    ],
  });

  DartType F1_T = env.elementEnvironment.getThisType(F1).typeArguments.first;
  testSupertypes(F1, {
    A: [X],
    B: [
      X,
      instantiate(types, B, [F1_T, X]),
    ],
  });
  DartType F1_superclass_T = env.elementEnvironment
      .getThisType(env.elementEnvironment.getSuperClass(F1)!)
      .typeArguments
      .first;
  testSupertypes(env.elementEnvironment.getSuperClass(F1)!, {
    A: [X],
    B: [
      X,
      instantiate(types, B, [F1_superclass_T, X]),
    ],
  });
  DartType F2_T = env.elementEnvironment.getThisType(F2).typeArguments.first;
  testSupertypes(F2, {
    A: [X],
    B: [
      X,
      instantiate(types, B, [F2_T, X]),
    ],
  });
}
