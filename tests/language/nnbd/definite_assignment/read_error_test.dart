// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// To avoid having tests for the cross product of declaration forms and control
/// flow constructs, the tests in this directory are split into tests that check
/// that each different kind of variable declaration is treated appropriately
/// with respect to errors and warnings for a single control flow construct; and
/// tests that check that a reasonable subset of the possible control flow
/// patterns produce the expected definite (un)-assignment behavior.
///
/// This test checks the read component of the former.  That is, it tests
/// errors associated with reads of local variables based on definite
/// assignment.

void use(Object? x) {}

/// Test that a read of a definitely unassigned variable gives the correct error
/// for each kind of variable.
void testDefinitelyUnassignedReads<T>() {
  // It is a compile time error to read a local variable when the variable is
  // **definitely unassigned** unless the variable is non-`final`, and
  // non-`late`, and has nullable type.

  // Ok: non-final and nullably typed.
  {
    var x;
    use(x);
  }

  // Error: final.
  {
    final x;
    use(x);
    //  ^
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  // Error: not nullable.
  {
    int x;
    use(x);
    //  ^
    // [analyzer] COMPILE_TIME_ERROR.NOT_ASSIGNED_POTENTIALLY_NON_NULLABLE_LOCAL_VARIABLE
    // [cfe] Non-nullable variable 'x' must be assigned before it can be used.
  }

  // Ok: non-final and nullably typed.
  {
    int? x;
    use(x);
  }

  // Error: final and not nullable.
  {
    final int x;
    use(x);
    //  ^
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  // Error: final.
  {
    final int? x;
    use(x);
    //  ^
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  // Error: final and not nullable.
  {
    final T x;
    use(x);
    //  ^
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  // Error: late
  {
    late var x;
    use(x);
    //  ^
    // [analyzer] COMPILE_TIME_ERROR.DEFINITELY_UNASSIGNED_LATE_LOCAL_VARIABLE
    // [cfe] Late variable 'x' without initializer is definitely unassigned.
  }

  // Error: late and not nullable
  {
    late int x;
    use(x);
    //  ^
    // [analyzer] COMPILE_TIME_ERROR.DEFINITELY_UNASSIGNED_LATE_LOCAL_VARIABLE
    // [cfe] Late variable 'x' without initializer is definitely unassigned.
  }

  // Error: late
  {
    late int? x;
    use(x);
    //  ^
    // [analyzer] COMPILE_TIME_ERROR.DEFINITELY_UNASSIGNED_LATE_LOCAL_VARIABLE
    // [cfe] Late variable 'x' without initializer is definitely unassigned.
  }

  // Error: late and not nullable
  {
    late T x;
    use(x);
    //  ^
    // [analyzer] COMPILE_TIME_ERROR.DEFINITELY_UNASSIGNED_LATE_LOCAL_VARIABLE
    // [cfe] Late variable 'x' without initializer is definitely unassigned.
  }

  // Error: late and final
  {
    late final x;
    use(x);
    //  ^
    // [analyzer] COMPILE_TIME_ERROR.DEFINITELY_UNASSIGNED_LATE_LOCAL_VARIABLE
    // [cfe] Late variable 'x' without initializer is definitely unassigned.
  }

  // Error: late and final and not nullable
  {
    late final int x;
    use(x);
    //  ^
    // [analyzer] COMPILE_TIME_ERROR.DEFINITELY_UNASSIGNED_LATE_LOCAL_VARIABLE
    // [cfe] Late variable 'x' without initializer is definitely unassigned.
  }

  // Error: late and final
  {
    late final int? x;
    use(x);
    //  ^
    // [analyzer] COMPILE_TIME_ERROR.DEFINITELY_UNASSIGNED_LATE_LOCAL_VARIABLE
    // [cfe] Late variable 'x' without initializer is definitely unassigned.
  }

  // Error: late and final and not nullable
  {
    late final T x;
    use(x);
    //  ^
    // [analyzer] COMPILE_TIME_ERROR.DEFINITELY_UNASSIGNED_LATE_LOCAL_VARIABLE
    // [cfe] Late variable 'x' without initializer is definitely unassigned.
  }
}

/// Test that a read of a potentially unassigned variable gives the correct
/// error for each kind of variable.
void testPotentiallyUnassignedReads<T>(bool b, T t) {
  //  It is a compile time error to read a local variable when the variable is
  //  **potentially unassigned** unless the variable is non-final and has
  //  nullable type, or is `late`.

  // Ok: non-final and nullable.
  {
    var x;
    int y = 3;
    if (b) {
      x = y;
    }
    use(x);
  }

  // Error: final.
  {
    final x;
    int y = 3;
    if (b) {
      x = y;
    }
    use(x);
    //  ^
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  // Error: not nullable.
  {
    int x;
    int y = 3;
    if (b) {
      x = y;
    }
    use(x);
    //  ^
    // [analyzer] COMPILE_TIME_ERROR.NOT_ASSIGNED_POTENTIALLY_NON_NULLABLE_LOCAL_VARIABLE
    // [cfe] Non-nullable variable 'x' must be assigned before it can be used.
  }

  // Ok: non-final and nullable.
  {
    int? x;
    int y = 3;
    if (b) {
      x = y;
    }
    use(x);
  }

  // Error: final and not nullable.
  {
    final int x;
    int y = 3;
    if (b) {
      x = y;
    }
    use(x);
    //  ^
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  // Error: final.
  {
    final int? x;
    int y = 3;
    if (b) {
      x = y;
    }
    use(x);
    //  ^
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  // Error: final and not nullable.
  {
    final T x;
    T y = t;
    if (b) {
      x = y;
    }
    use(x);
    //  ^
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  // Ok: late.
  {
    late var x;
    int y = 3;
    if (b) {
      x = y;
    }
    use(x);
  }

  // Ok: late.
  {
    late int x;
    int y = 3;
    if (b) {
      x = y;
    }
    use(x);
  }

  // Ok: late.
  {
    late int? x;
    int y = 3;
    if (b) {
      x = y;
    }
    use(x);
  }

  // Ok: late.
  {
    late T x;
    T y = t;
    if (b) {
      x = y;
    }
    use(x);
  }

  // Ok: late.
  {
    late final x;
    int y = 3;
    if (b) {
      x = y;
    }
    use(x);
  }

  // Ok: late.
  {
    late final int x;
    int y = 3;
    if (b) {
      x = y;
    }
    use(x);
  }

  // Ok: late.
  {
    late final int? x;
    int y = 3;
    if (b) {
      x = y;
    }
    use(x);
  }

  // Ok: late.
  {
    late final T x;
    T y = t;
    if (b) {
      x = y;
    }
    use(x);
  }
}

/// Test that reading a definitely assigned variable is not an error.
void testDefinitelyAssignedReads<T>(T t) {
  // It is never an error to read a definitely assigned variable.

  {
    var x;
    int y = 3;
    x = y;
    use(x);
  }

  {
    final x;
    int y = 3;
    x = y;
    use(x);
  }

  {
    int x;
    int y = 3;
    x = y;
    use(x);
  }

  {
    int? x;
    int y = 3;
    x = y;
    use(x);
  }

  {
    final int x;
    int y = 3;
    x = y;
    use(x);
  }

  {
    final int? x;
    int y = 3;
    x = y;
    use(x);
  }

  {
    final T x;
    T y = t;
    x = y;
    use(x);
  }

  {
    late var x;
    int y = 3;
    x = y;
    use(x);
  }

  {
    late int x;
    int y = 3;
    x = y;
    use(x);
  }

  {
    late int? x;
    int y = 3;
    x = y;
    use(x);
  }

  {
    late T x;
    T y = t;
    x = y;
    use(x);
  }

  {
    late final x;
    int y = 3;
    x = y;
    use(x);
  }

  {
    late final int x;
    int y = 3;
    x = y;
    use(x);
  }

  {
    late final int? x;
    int y = 3;
    x = y;
    use(x);
  }

  {
    late final T x;
    T y = t;
    x = y;
    use(x);
  }
}

/// Test that a read of a definitely unassigned variable gives the correct error
/// for a single choice of declaration form, across a range of read constructs.
///
/// These tests declare a `final` variable of type `dynamic` with no initializer
/// and no assignments, and test that it is an error to use the variable
/// in a variety of syntactic positions.
void testDefinitelyUnassignedReadForms() {
  {
    final dynamic x;
    x;
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    use(x);
    //  ^
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    x(use);
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    x.foo;
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    x.foo();
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    x.foo = 3;
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    x?.foo;
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    x..foo;
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    x[0];
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    ([3])[x];
    //    ^
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    (x as int);
    // [error column 6, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    (x is int);
    // [error column 6, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    (x == null);
    // [error column 6, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    (null == x);
    //       ^
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    (3 == x);
    //    ^
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    (x == 3);
    // [error column 6, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    (x == 3);
    // [error column 6, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    x++;
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    ++x;
    //^
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    -x;
    // [error column 6, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    x += 3;
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    x ??= 3;
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    x ?? 3;
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    3 ?? x;
    //   ^
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [analyzer] STATIC_WARNING.DEAD_NULL_AWARE_EXPRESSION
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }
}

/// Test that a read of a potentially unassigned variable gives the correct
/// error for a single choice of declaration form, across a range of read
/// constructs.
///
/// These tests declare a `final` variable of type `dynamic` and assign to it in
/// one branch of a conditional such that the variable is potentially but not
/// definitely assigned.  The test then checks that it is an error to use the
/// variable in a variety of syntactic positions.
void testPotentiallyUnassignedReadForms(bool b) {
  {
    final dynamic x;
    if (b) {
      x = 3;
    }
    x;
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    if (b) {
      x = 3;
    }
    use(x);
    //  ^
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    if (b) {
      x = 3;
    }
    x(use);
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    if (b) {
      x = 3;
    }
    x.foo;
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    if (b) {
      x = 3;
    }
    x.foo();
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    if (b) {
      x = 3;
    }
    x.foo = 3;
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    if (b) {
      x = 3;
    }
    x?.foo;
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    if (b) {
      x = 3;
    }
    x..foo;
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    if (b) {
      x = 3;
    }
    x[0];
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    if (b) {
      x = 3;
    }
    ([3])[x];
    //    ^
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    if (b) {
      x = 3;
    }
    (x as int);
    // [error column 6, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    if (b) {
      x = 3;
    }
    (x is int);
    // [error column 6, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    if (b) {
      x = 3;
    }
    (x == null);
    // [error column 6, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    if (b) {
      x = 3;
    }
    (null == x);
    //       ^
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    if (b) {
      x = 3;
    }
    (3 == x);
    //    ^
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    if (b) {
      x = 3;
    }
    (x == 3);
    // [error column 6, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    if (b) {
      x = 3;
    }
    (x == 3);
    // [error column 6, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    if (b) {
      x = 3;
    }
    x++;
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.ASSIGNMENT_TO_FINAL_LOCAL
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' might already be assigned at this point.
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    if (b) {
      x = 3;
    }
    ++x;
    //^
    // [analyzer] COMPILE_TIME_ERROR.ASSIGNMENT_TO_FINAL_LOCAL
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' might already be assigned at this point.
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    if (b) {
      x = 3;
    }
    -x;
    // [error column 6, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    if (b) {
      x = 3;
    }
    x += 3;
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.ASSIGNMENT_TO_FINAL_LOCAL
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' might already be assigned at this point.
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    if (b) {
      x = 3;
    }
    x ??= 3;
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.ASSIGNMENT_TO_FINAL_LOCAL
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' might already be assigned at this point.
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    if (b) {
      x = 3;
    }
    x ?? 3;
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }

  {
    final dynamic x;
    if (b) {
      x = 3;
    }
    3 ?? x;
    //   ^
    // [analyzer] COMPILE_TIME_ERROR.READ_POTENTIALLY_UNASSIGNED_FINAL
    // [analyzer] STATIC_WARNING.DEAD_NULL_AWARE_EXPRESSION
    // [cfe] Final variable 'x' must be assigned before it can be used.
  }
}

/// Test that a read of a definitely assigned variable is not an error for a
/// single choice of declaration form, across a range of read constructs.
///
/// This test declares a final variable and then initializes it via an
/// assignment.  The test then verifies that it is not an error to read the
/// variable in a variety of syntactic positions.
void testDefinitelyAssignedReadForms() {
  {
    final dynamic x;
    x = 3;
    x;
  }

  {
    final dynamic x;
    x = 3;
    use(x);
  }

  {
    final dynamic x;
    x = 3;
    x(use);
  }

  {
    final dynamic x;
    x = 3;
    x.foo;
  }

  {
    final dynamic x;
    x = 3;
    x.foo();
  }

  {
    final dynamic x;
    x = 3;
    x.foo = 3;
  }

  {
    final dynamic x;
    x = 3;
    x?.foo;
  }

  {
    final dynamic x;
    x = 3;
    x..foo;
  }

  {
    final dynamic x;
    x = 3;
    x[0];
  }

  {
    final dynamic x;
    x = 3;
    ([3])[x];
  }

  {
    final dynamic x;
    x = 3;
    (x as int);
  }

  {
    final dynamic x;
    x = 3;
    (x is int);
  }

  {
    final dynamic x;
    x = 3;
    (x == null);
  }

  {
    final dynamic x;
    x = 3;
    (null == x);
  }

  {
    final dynamic x;
    x = 3;
    (3 == x);
  }

  {
    final dynamic x;
    x = 3;
    (x == 3);
  }

  {
    final dynamic x;
    x = 3;
    (x == 3);
  }

  {
    final dynamic x;
    x = 3;
    x++;
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.ASSIGNMENT_TO_FINAL_LOCAL
    // [cfe] Final variable 'x' might already be assigned at this point.
  }

  {
    final dynamic x;
    x = 3;
    ++x;
    //^
    // [analyzer] COMPILE_TIME_ERROR.ASSIGNMENT_TO_FINAL_LOCAL
    // [cfe] Final variable 'x' might already be assigned at this point.
  }

  {
    final dynamic x;
    x = 3;
    -x;
  }

  {
    final dynamic x;
    x = 3;
    x += 3;
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.ASSIGNMENT_TO_FINAL_LOCAL
    // [cfe] Final variable 'x' might already be assigned at this point.
  }

  {
    final dynamic x;
    x = 3;
    x ??= 3;
    // [error column 5, length 1]
    // [analyzer] COMPILE_TIME_ERROR.ASSIGNMENT_TO_FINAL_LOCAL
    // [cfe] Final variable 'x' might already be assigned at this point.
  }

  {
    final dynamic x;
    x = 3;
    x ?? 3;
  }

  {
    final dynamic x;
    x = 3;
    3 ?? x;
    //   ^
    // [analyzer] STATIC_WARNING.DEAD_NULL_AWARE_EXPRESSION
  }
}

void main() {
  testDefinitelyUnassignedReads<int>();
  testPotentiallyUnassignedReads<int>(true, 0);
  testDefinitelyAssignedReads<int>(0);
  testDefinitelyUnassignedReadForms();
  testPotentiallyUnassignedReadForms(true);
  testDefinitelyAssignedReadForms();
}
