// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/protocol/protocol_generated.dart';
import 'package:analysis_server/src/utilities/extensions/ast.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

/// A computer for [CompilationUnit] closing labels.
class DartUnitClosingLabelsComputer {
  final LineInfo _lineInfo;
  final CompilationUnit _unit;
  final List<ClosingLabel> _closingLabels = [];
  final Set<ClosingLabel> hasNestingSet = {};
  final Set<ClosingLabel> isSingleLineSet = {};

  DartUnitClosingLabelsComputer(this._lineInfo, this._unit);

  /// Returns a list of closing labels, not `null`.
  List<ClosingLabel> compute() {
    _unit.accept(_DartUnitClosingLabelsComputerVisitor(this));

    return _closingLabels.where((ClosingLabel label) {
      // Filter labels that don't have some nesting.
      // Filter labels that start and end on the same line.
      return hasNestingSet.contains(label) && !isSingleLineSet.contains(label);
    }).toList();
  }

  void setHasNesting(ClosingLabel label) {
    hasNestingSet.add(label);
  }

  void setSingleLine(ClosingLabel label) {
    isSingleLineSet.add(label);
  }
}

/// An AST visitor for [DartUnitClosingLabelsComputer].
class _DartUnitClosingLabelsComputerVisitor extends RecursiveAstVisitor<void> {
  final DartUnitClosingLabelsComputer computer;

  int interpolatedStringsEntered = 0;
  List<ClosingLabel> labelStack = [];

  _DartUnitClosingLabelsComputerVisitor(this.computer);

  ClosingLabel? get _currentLabel =>
      labelStack.isEmpty ? null : labelStack.last;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    var labelText = node.constructorName.type.qualifiedName;
    var name = node.constructorName.name;
    if (name != null) {
      labelText += '.${name.name}';
    }
    // We override the node used for doing line calculations because otherwise
    // constructors that split over multiple lines (but have parens on same
    // line) would incorrectly get labels, because node.start on an instance
    // creation expression starts at the start of the expression.
    var label = _addLabel(node, labelText, checkLinesUsing: node.argumentList);

    if (label != null) _pushLabel(label);

    try {
      super.visitInstanceCreationExpression(node);
    } finally {
      if (label != null) _popLabel();
    }
  }

  @override
  void visitListLiteral(ListLiteral node) {
    var args = node.typeArguments?.arguments;
    var typeName = args != null ? args[0].toString() : null;

    ClosingLabel? label;

    if (typeName != null) {
      label = _addLabel(node, '<$typeName>[]');
    }

    if (label != null) _pushLabel(label);

    try {
      super.visitListLiteral(node);
    } finally {
      if (label != null) _popLabel();
    }
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    interpolatedStringsEntered++;
    try {
      super.visitStringInterpolation(node);
    } finally {
      interpolatedStringsEntered--;
    }
  }

  ClosingLabel? _addLabel(
    AstNode node,
    String label, {
    AstNode? checkLinesUsing,
  }) {
    // Never add labels if we're inside strings.
    if (interpolatedStringsEntered > 0) {
      return null;
    }

    checkLinesUsing = checkLinesUsing ?? node;

    var start = computer._lineInfo.getLocation(checkLinesUsing.offset);
    var end = computer._lineInfo.getLocation(checkLinesUsing.end - 1);

    var closingLabel = ClosingLabel(node.offset, node.length, label);

    var spannedLines = end.lineNumber - start.lineNumber;
    if (spannedLines < 1) {
      computer.setSingleLine(closingLabel);
    }

    var parent = _currentLabel;
    if (parent != null) {
      computer.setHasNesting(parent);
      computer.setHasNesting(closingLabel);
    }

    computer._closingLabels.add(closingLabel);

    return closingLabel;
  }

  void _popLabel() {
    labelStack.removeLast();
  }

  void _pushLabel(ClosingLabel label) {
    labelStack.add(label);
  }
}
