// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'common/service_test_common.dart';
import 'common/test_helper.dart';

// AUTOGENERATED START
//
// Update these constants by running:
//
// dart pkg/vm_service/test/update_line_numbers.dart pkg/vm_service/test/step_through_switch_with_continue_test.dart
//
const LINE_A = 19;
// AUTOGENERATED END

const file = 'step_through_switch_with_continue_test.dart';

void code() /* LINE_A */ {
  switch (switchOnMe.length) {
    case 0:
      print('(got 0!');
      continue label;
    label:
    case 1:
      print('Got 0 or 1!');
      break;
    case 2:
      print('Got 2!');
      break;
    default:
      print('Got lost!');
  }
}

final switchOnMe = <String>[];
final stops = <String>[];
const expected = <String>[
  '$file:${LINE_A + 0}:10', // after 'code'

  '$file:${LINE_A + 1}:11', // on switchOnMe
  '$file:${LINE_A + 17}:28', // on switchOnMe initializer starting '['
  '$file:${LINE_A + 1}:22', // on length

  '$file:${LINE_A + 2}:10', // on 0
  '$file:${LINE_A + 3}:7', // on print
  '$file:${LINE_A + 4}:7', // on continue

  '$file:${LINE_A + 7}:7', // on print
  '$file:${LINE_A + 8}:7', // on break

  '$file:${LINE_A + 15}:1', // on ending '}'
];

final tests = <IsolateTest>[
  hasPausedAtStart,
  setBreakpointAtLine(LINE_A),
  runStepIntoThroughProgramRecordingStops(stops),
  checkRecordedStops(
    stops,
    expected,
    debugPrint: true,
    debugPrintFile: file,
    debugPrintLine: LINE_A,
  ),
];

void main([args = const <String>[]]) => runIsolateTestsSynchronous(
      args,
      tests,
      'step_through_switch_with_continue_test.dart',
      testeeConcurrent: code,
      pauseOnStart: true,
      pauseOnExit: true,
    );
