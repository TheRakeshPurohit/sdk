// Copyright (c) 2014, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/status.dart';
import 'package:analysis_server/src/services/refactoring/legacy/naming_conventions.dart';
import 'package:analysis_server/src/services/refactoring/legacy/refactoring.dart';
import 'package:analysis_server/src/services/refactoring/legacy/rename.dart';
import 'package:analyzer/dart/element/element.dart';

/// A [Refactoring] for renaming [LabelElement]s.
class RenameLabelRefactoringImpl extends RenameRefactoringImpl {
  RenameLabelRefactoringImpl(
    super.workspace,
    super.sessionHelper,
    LabelElement super.element,
  ) : super();

  @override
  LabelElement get element => super.element as LabelElement;

  @override
  String get refactoringName => 'Rename Label';

  @override
  Future<RefactoringStatus> checkFinalConditions() {
    var result = RefactoringStatus();
    return Future.value(result);
  }

  @override
  RefactoringStatus checkNewName() {
    var result = super.checkNewName();
    result.addStatus(validateLabelName(newName));
    return result;
  }

  @override
  Future<void> fillChange() {
    var processor = RenameProcessor(workspace, sessionHelper, change, newName);
    return processor.renameElement(element);
  }
}
