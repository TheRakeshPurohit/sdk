// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/source/source.dart';
import 'package:analyzer/src/context/packages.dart';
import 'package:analyzer/src/workspace/simple.dart';
import 'package:analyzer/src/workspace/workspace.dart';

/// Information about a default Dart workspace.
///
/// A BasicWorkspace should only be used when no other workspace type is valid.
class BasicWorkspace extends SimpleWorkspace {
  /// The singular package in this workspace.
  ///
  /// Each basic workspace is itself one package.
  late final BasicWorkspacePackage theOnlyPackage;

  BasicWorkspace._(ResourceProvider provider, Packages packages, Folder root)
    : super(provider, packages, root.path) {
    theOnlyPackage = BasicWorkspacePackage(root, this);
  }

  @override
  WorkspacePackageImpl? findPackageFor(String filePath) {
    Folder folder = provider.getFolder(filePath);
    if (provider.pathContext.isWithin(root, folder.path)) {
      return theOnlyPackage;
    } else {
      return null;
    }
  }

  /// Find the basic workspace that contains the given [path].
  ///
  /// As a [BasicWorkspace] is not defined by any marker files or build
  /// artifacts, this simply creates a BasicWorkspace with [path] as the [root]
  /// (or [path]'s parent if [path] points to a file).
  static BasicWorkspace find(
    ResourceProvider provider,
    Packages packages,
    String path,
  ) {
    Resource resource = provider.getResource(path);
    if (resource is File) {
      resource = resource.parent;
    }
    return BasicWorkspace._(provider, packages, resource as Folder);
  }
}

/// Information about a package defined in a [BasicWorkspace].
///
/// Separate from [Packages] or package maps, this class is designed to simply
/// understand whether arbitrary file paths represent libraries declared within
/// a given package in a [BasicWorkspace].
class BasicWorkspacePackage extends WorkspacePackageImpl {
  @override
  final Folder root;

  @override
  final SimpleWorkspace workspace;

  BasicWorkspacePackage(this.root, this.workspace);

  @override
  bool get canHavePublicApi => false;

  @override
  bool contains(Source source) {
    // When dealing with a BasicWorkspace, [source] will always have a valid
    // fullName.
    String filePath = source.fullName;
    // There is a 1-1 relationship between [BasicWorkspace]s and
    // [BasicWorkspacePackage]s. If a file is in a package's workspace, then it
    // is in the package as well.
    return workspace.provider.pathContext.isWithin(root.path, filePath);
  }

  @override
  Packages packagesAvailableTo(String libraryPath) => workspace.packages;

  @override
  bool sourceIsInPublicApi(Source source) {
    // Since every source file in a BasicPackage is in the same directory, they
    // are all in the public API of the package. A file in a subdirectory
    // is in a separate package.
    return true;
  }
}
