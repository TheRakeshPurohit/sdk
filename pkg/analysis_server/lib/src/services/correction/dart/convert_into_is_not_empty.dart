// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:_fe_analyzer_shared/src/scanner/token.dart';
import 'package:analysis_server/src/services/correction/assist.dart';
import 'package:analysis_server/src/services/search/hierarchy.dart';
import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer_plugin/utilities/assist/assist.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

class ConvertIntoIsNotEmpty extends ResolvedCorrectionProducer {
  ConvertIntoIsNotEmpty({required super.context});

  @override
  CorrectionApplicability get applicability =>
      // TODO(applicability): comment on why.
      CorrectionApplicability.singleLocation;

  @override
  AssistKind get assistKind => DartAssistKind.convertIntoIsNotEmpty;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    if (node is! SimpleIdentifier) {
      return;
    }

    // Prepare `expr.isEmpty`.
    SimpleIdentifier isEmptyIdentifier;
    AstNode isEmptyAccess;
    var identifier = node as SimpleIdentifier;
    var parent = identifier.parent;
    if (parent is PropertyAccess) {
      // Normal case (but rare).
      isEmptyIdentifier = parent.propertyName;
      isEmptyAccess = parent;
    } else if (parent is PrefixedIdentifier) {
      // Usual case.
      isEmptyIdentifier = parent.identifier;
      isEmptyAccess = parent;
    } else {
      return;
    }

    // Should be `isEmpty`.
    var propertyElement = isEmptyIdentifier.element;
    if (propertyElement == null || 'isEmpty' != propertyElement.name) {
      return;
    }
    // Should have `isNotEmpty`.
    var propertyTarget = propertyElement.enclosingElement;
    if (propertyTarget == null ||
        getChildren(propertyTarget, 'isNotEmpty').isEmpty) {
      return;
    }
    // Should be in `PrefixExpression`.
    if (isEmptyAccess.parent is! PrefixExpression) {
      return;
    }
    var prefixExpression = isEmptyAccess.parent as PrefixExpression;
    // Should be `!`.
    if (prefixExpression.operator.type != TokenType.BANG) {
      return;
    }

    await builder.addDartFileEdit(file, (builder) {
      builder.addDeletion(
        range.startStart(prefixExpression, prefixExpression.operand),
      );
      builder.addSimpleReplacement(range.node(isEmptyIdentifier), 'isNotEmpty');
    });
  }
}
