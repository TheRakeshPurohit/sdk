// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Test that pattern for-in statements do not accept a nullable iterable
/// expression (https://github.com/dart-lang/sdk/issues/54671).

void statement_sync_nullable(Iterable<int>? x) {
  for (var (y) in x) {}
  //              ^
  // [analyzer] COMPILE_TIME_ERROR.UNCHECKED_USE_OF_NULLABLE_VALUE
  // [cfe] The type 'Iterable<int>?' used in the 'for' loop must implement 'Iterable<dynamic>'.
}

void statement_sync_potentiallyNullable<T extends Iterable<int>?>(T x) {
  for (var (y) in x) {}
  //              ^
  // [analyzer] COMPILE_TIME_ERROR.UNCHECKED_USE_OF_NULLABLE_VALUE
  // [cfe] The type 'T' used in the 'for' loop must implement 'Iterable<dynamic>'.
}

Future<void> statement_async_nullable(Stream<int>? x) async {
  await for (var (y) in x) {}
  //                    ^
  // [analyzer] COMPILE_TIME_ERROR.UNCHECKED_USE_OF_NULLABLE_VALUE
  // [cfe] The type 'Stream<int>?' used in the 'for' loop must implement 'Stream<dynamic>'.
}

Future<void> statement_async_potentiallyNullable<T extends Stream<int>?>(
  T x,
) async {
  await for (var (y) in x) {}
  //                    ^
  // [analyzer] COMPILE_TIME_ERROR.UNCHECKED_USE_OF_NULLABLE_VALUE
  // [cfe] The type 'T' used in the 'for' loop must implement 'Iterable<dynamic>'.
  // [cfe] The type 'T' used in the 'for' loop must implement 'Stream<dynamic>'.
}

List<int> listElement_sync_nullable(Iterable<int>? x) => [for (var (y) in x) y];
//                                                                        ^
// [analyzer] COMPILE_TIME_ERROR.UNCHECKED_USE_OF_NULLABLE_VALUE
// [cfe] The type 'Iterable<int>?' used in the 'for' loop must implement 'Iterable<dynamic>'.

List<int> listElement_sync_potentiallyNullable<T extends Iterable<int>?>(T x) =>
    [for (var (y) in x) y];
//                   ^
// [analyzer] COMPILE_TIME_ERROR.UNCHECKED_USE_OF_NULLABLE_VALUE
// [cfe] The type 'T' used in the 'for' loop must implement 'Iterable<dynamic>'.

Future<List<int>> listElement_async_nullable(Stream<int>? x) async => [
  await for (var (y) in x) y,
  //                    ^
  // [analyzer] COMPILE_TIME_ERROR.UNCHECKED_USE_OF_NULLABLE_VALUE
  // [cfe] The type 'Stream<int>?' used in the 'for' loop must implement 'Stream<dynamic>'.
];

Future<List<int>> listElement_async_potentiallyNullable<T extends Stream<int>?>(
  T x,
) async => [await for (var (y) in x) y];
//                                ^
// [analyzer] COMPILE_TIME_ERROR.UNCHECKED_USE_OF_NULLABLE_VALUE
// [cfe] The type 'T' used in the 'for' loop must implement 'Iterable<dynamic>'.
// [cfe] The type 'T' used in the 'for' loop must implement 'Stream<dynamic>'.

Set<int> setElement_sync_nullable(Iterable<int>? x) => {for (var (y) in x) y};
//                                                                      ^
// [analyzer] COMPILE_TIME_ERROR.UNCHECKED_USE_OF_NULLABLE_VALUE
// [cfe] The type 'Iterable<int>?' used in the 'for' loop must implement 'Iterable<dynamic>'.

Set<int> setElement_sync_potentiallyNullable<T extends Iterable<int>?>(T x) => {
  for (var (y) in x) y,
  //              ^
  // [analyzer] COMPILE_TIME_ERROR.UNCHECKED_USE_OF_NULLABLE_VALUE
  // [cfe] The type 'T' used in the 'for' loop must implement 'Iterable<dynamic>'.
};

Future<Set<int>> setElement_async_nullable(Stream<int>? x) async => {
  await for (var (y) in x) y,
  //                    ^
  // [analyzer] COMPILE_TIME_ERROR.UNCHECKED_USE_OF_NULLABLE_VALUE
  // [cfe] The type 'Stream<int>?' used in the 'for' loop must implement 'Stream<dynamic>'.
};

Future<Set<int>> setElement_async_potentiallyNullable<T extends Stream<int>?>(
  T x,
) async => {await for (var (y) in x) y};
//                                ^
// [analyzer] COMPILE_TIME_ERROR.UNCHECKED_USE_OF_NULLABLE_VALUE
// [cfe] The type 'T' used in the 'for' loop must implement 'Iterable<dynamic>'.
// [cfe] The type 'T' used in the 'for' loop must implement 'Stream<dynamic>'.

Map<int, int> mapElement_sync_nullable(Iterable<int>? x) => {
  for (var (y) in x) y: y,
  //              ^
  // [analyzer] COMPILE_TIME_ERROR.UNCHECKED_USE_OF_NULLABLE_VALUE
  // [cfe] The type 'Iterable<int>?' used in the 'for' loop must implement 'Iterable<dynamic>'.
};

Map<int, int> mapElement_sync_potentiallyNullable<T extends Iterable<int>?>(
  T x,
) => {for (var (y) in x) y: y};
//                    ^
// [analyzer] COMPILE_TIME_ERROR.UNCHECKED_USE_OF_NULLABLE_VALUE
// [cfe] The type 'T' used in the 'for' loop must implement 'Iterable<dynamic>'.

Future<Map<int, int>> mapElement_async_nullable(Stream<int>? x) async => {
  await for (var (y) in x) y: y,
  //                    ^
  // [analyzer] COMPILE_TIME_ERROR.UNCHECKED_USE_OF_NULLABLE_VALUE
  // [cfe] The type 'Stream<int>?' used in the 'for' loop must implement 'Stream<dynamic>'.
};

Future<Map<int, int>> mapElement_async_potentiallyNullable<
  T extends Stream<int>?
>(T x) async => {await for (var (y) in x) y: y};
//                                     ^
// [analyzer] COMPILE_TIME_ERROR.UNCHECKED_USE_OF_NULLABLE_VALUE
// [cfe] The type 'T' used in the 'for' loop must implement 'Iterable<dynamic>'.
// [cfe] The type 'T' used in the 'for' loop must implement 'Stream<dynamic>'.

main() {}
