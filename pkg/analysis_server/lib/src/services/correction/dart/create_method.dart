// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/src/services/correction/fix.dart';
import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

class CreateMethod extends ResolvedCorrectionProducer {
  /// The kind of method to be created.
  final _MethodKind _kind;

  String _memberName = '';

  @override
  final CorrectionApplicability applicability;

  /// Initializes a newly created instance that will create either an equality
  /// (`operator ==`) method or `hashCode` getter based on the existing other
  /// half of the pair.
  CreateMethod.equalityOrHashCode({required super.context})
    : _kind = _MethodKind.equalityOrHashCode,
      applicability = CorrectionApplicability.acrossSingleFile;

  /// Initializes a newly created instance that will create a method based on an
  /// invocation of an undefined method.
  CreateMethod.method({required super.context})
    : _kind = _MethodKind.method,
      applicability = CorrectionApplicability.singleLocation;

  @override
  List<String> get fixArguments => [_memberName];

  @override
  FixKind get fixKind => DartFixKind.CREATE_METHOD;

  @override
  FixKind get multiFixKind => DartFixKind.CREATE_METHOD_MULTI;

  @override
  Future<void> compute(ChangeBuilder builder) => switch (_kind) {
    _MethodKind.equalityOrHashCode => _createEqualsOrHashCode(builder),
    _MethodKind.method => _createMethod(builder),
  };

  Future<void> _createEqualsOrHashCode(ChangeBuilder builder) async {
    var memberDecl = node.thisOrAncestorOfType<ClassMember>();
    if (memberDecl == null) {
      return;
    }
    // TODO(srawlins): Shouldn't this be available on enums and mixins as well?
    var classDecl = memberDecl.thisOrAncestorOfType<ClassDeclaration>();
    if (classDecl == null) {
      return;
    }

    var classElement = classDecl.declaredFragment!.element;
    var missingEquals =
        memberDecl is FieldDeclaration ||
        (memberDecl as MethodDeclaration).name.lexeme == 'hashCode';

    await builder.addDartFileEdit(file, (fileBuilder) {
      fileBuilder.insertIntoUnitMember(classDecl, (builder) {
        ExecutableElement? element;
        if (missingEquals) {
          _memberName = '==';
          element = classElement.getInheritedMember(
            Name.forLibrary(classElement.library, _memberName),
          );
        } else {
          _memberName = 'hashCode';
          element = classElement.getInheritedMember(
            Name.forLibrary(classElement.library, _memberName),
          );
        }
        if (element == null) {
          return;
        }

        builder.writeOverride(element, invokeSuper: true);
      });
    });
  }

  Future<void> _createMethod(ChangeBuilder builder) async {
    if (node is! SimpleIdentifier || node.parent is! MethodInvocation) {
      return;
    }
    _memberName = (node as SimpleIdentifier).name;
    var invocation = node.parent as MethodInvocation;
    // Prepare environment.
    Fragment? targetFragment;
    var staticModifier = false;

    CompilationUnitMember? targetNode;
    var target = invocation.realTarget;
    if (target is ExtensionOverride) {
      // This case should be handled by the "Add extension method" quick fix
      return;
    } else if (target is Identifier && target.element is ExtensionElement) {
      // This case should be handled by the "Add extension method" quick fix
      return;
    } else if (target == null) {
      targetFragment = unit.declaredFragment;
      var enclosingMember = node.thisOrAncestorOfType<ClassMember>();
      if (enclosingMember == null) {
        // If the undefined identifier isn't inside a class member, then it
        // doesn't make sense to create a method.
        return;
      }
      var enclosingMemberParent = enclosingMember.parent;
      if (enclosingMemberParent is CompilationUnitMember &&
          enclosingMemberParent is! ExtensionDeclaration) {
        targetNode = enclosingMemberParent;
        staticModifier = switch (enclosingMember) {
          ConstructorDeclaration(:var factoryKeyword) => factoryKeyword != null,
          MethodDeclaration(:var isStatic) => isStatic,
          FieldDeclaration(
            :var isStatic,
            fields: VariableDeclarationList(:var isLate),
          ) =>
            isStatic || !isLate,
        };
      }
    } else {
      var targetClassElement = getTargetInterfaceElement(target);
      if (targetClassElement == null) {
        return;
      }
      targetFragment = targetClassElement.firstFragment;
      if (targetClassElement.library.isInSdk) {
        return;
      }
      // Prepare target ClassDeclaration.
      if (targetClassElement is MixinElement) {
        var fragment = targetClassElement.firstFragment;
        targetNode = await getMixinDeclaration(fragment);
      } else if (targetClassElement is ClassElement) {
        var fragment = targetClassElement.firstFragment;
        targetNode = await getClassDeclaration(fragment);
      } else if (targetClassElement is ExtensionTypeElement) {
        var fragment = targetClassElement.firstFragment;
        targetNode = await getExtensionTypeDeclaration(fragment);
      } else if (targetClassElement is EnumElement) {
        var fragment = targetClassElement.firstFragment;
        targetNode = await getEnumDeclaration(fragment);
      }
      if (targetNode == null) {
        return;
      }
      // Maybe static.
      if (target is Identifier) {
        staticModifier =
            target.element?.kind == ElementKind.CLASS ||
            target.element?.kind == ElementKind.ENUM ||
            target.element?.kind == ElementKind.EXTENSION_TYPE ||
            target.element?.kind == ElementKind.MIXIN;
      }
      // Use different utils.
      var targetPath = targetFragment.libraryFragment!.source.fullName;
      var targetResolveResult = await unitResult.session.getResolvedUnit(
        targetPath,
      );
      if (targetResolveResult is! ResolvedUnitResult) {
        return;
      }
    }
    var targetSource = targetFragment?.libraryFragment!.source;
    if (targetSource == null) {
      return;
    }
    var targetFile = targetSource.fullName;
    // Build method source.
    await builder.addDartFileEdit(targetFile, (builder) {
      if (targetNode == null) {
        return;
      }
      builder.insertMethod(targetNode, (builder) {
        // Maybe 'static'.
        if (staticModifier) {
          builder.write('static ');
        }
        // Append return type.

        var type = inferUndefinedExpressionType(invocation);
        if (builder.writeType(type, groupName: 'RETURN_TYPE')) {
          builder.write(' ');
        }

        // Append name.
        builder.addLinkedEdit('NAME', (builder) {
          builder.write(_memberName);
        });
        builder.write('(');
        builder.writeParametersMatchingArguments(invocation.argumentList);
        builder.write(')');
        if (type?.isDartAsyncFuture == true) {
          builder.write(' async');
        }
        builder.write(' {}');
      });
      if (targetFile == file) {
        builder.addLinkedPosition(range.node(node), 'NAME');
      }
    });
  }
}

/// A representation of the kind of element that should be suggested.
enum _MethodKind { equalityOrHashCode, method }
