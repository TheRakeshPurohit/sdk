// Copyright (c) 2016, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:collection/collection.dart' show IterableExtension;

import '../analyzer.dart';
import '../extensions.dart';
import '../linter_lint_codes.dart';

const _desc = r"Don't override fields.";

Iterable<InterfaceType> _findAllSupertypesAndMixins(
    InterfaceType? interface, List<InterfaceType> accumulator) {
  if (interface == null ||
      interface.isDartCoreObject ||
      accumulator.contains(interface)) {
    return accumulator;
  }

  accumulator.add(interface);
  var superclass = interface.superclass;
  var interfaces = <InterfaceType>[];
  if (superclass != null) {
    interfaces.add(superclass);
  }
  interfaces
    ..addAll(interface.element.mixins)
    ..addAll(_findAllSupertypesAndMixins(superclass, accumulator));
  return interfaces.where((i) => i != interface);
}

Iterable<InterfaceType> _findAllSupertypesInMixin(MixinElement mixinElement) {
  var supertypes = <InterfaceType>[];
  var accumulator = <InterfaceType>[];
  for (var type in mixinElement.superclassConstraints) {
    supertypes.add(type);
    supertypes.addAll(_findAllSupertypesAndMixins(type, accumulator));
  }
  return supertypes;
}

class OverriddenFields extends LintRule {
  OverriddenFields()
      : super(
          name: LintNames.overridden_fields,
          description: _desc,
        );

  @override
  LintCode get lintCode => LinterLintCode.overridden_fields;

  @override
  void registerNodeProcessors(
      NodeLintRegistry registry, LinterContext context) {
    var visitor = _Visitor(this);
    registry.addFieldDeclaration(this, visitor);
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  final LintRule rule;

  _Visitor(this.rule);

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    if (node.isAugmentation) return;
    if (node.isStatic) return;

    for (var variable in node.fields.variables) {
      var declaredField = variable.declaredElement;
      if (declaredField != null) {
        var overriddenField = _getOverriddenMember(declaredField);
        if (overriddenField != null && !overriddenField.isAbstract) {
          rule.reportLintForToken(variable.name,
              arguments: [overriddenField.enclosingElement3.displayName]);
        }
      }
    }
  }

  PropertyAccessorElement? _getOverriddenMember(Element member) {
    var memberName = member.name;
    var library = member.library;
    bool isOverriddenMember(PropertyAccessorElement a) {
      if (memberName == null || a.isStatic) {
        return false;
      }
      if (a.isSynthetic && a.name == memberName) {
        // Ensure that private members are overriding a member of the same library.
        if (Identifier.isPrivateName(memberName)) {
          return library == a.library;
        }
        return true;
      }
      return false;
    }

    bool containsOverriddenMember(InterfaceType i) =>
        i.accessors.any(isOverriddenMember);
    var enclosingElement = member.enclosingElement3;
    if (enclosingElement is! InterfaceElement) {
      return null;
    }
    var classElement = enclosingElement;

    Iterable<InterfaceType> interfaces;
    if (classElement is MixinElement) {
      interfaces = _findAllSupertypesInMixin(classElement);
    } else {
      interfaces =
          _findAllSupertypesAndMixins(classElement.thisType, <InterfaceType>[]);
    }
    var interface = interfaces.firstWhereOrNull(containsOverriddenMember);
    return interface?.accessors.firstWhere(isOverriddenMember);
  }
}
