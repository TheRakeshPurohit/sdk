// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:_fe_analyzer_shared/src/base/analyzer_public_api.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/source/source.dart';
import 'package:analyzer/src/context/packages.dart';
import 'package:analyzer/src/generated/sdk.dart';
import 'package:analyzer/src/generated/source.dart'
    show SourceFactory, UriResolver;
import 'package:analyzer/src/summary/api_signature.dart';
import 'package:analyzer/src/summary/package_bundle_reader.dart';
import 'package:analyzer/src/workspace/blaze.dart';
import 'package:analyzer/workspace/workspace.dart';
import 'package:meta/meta.dart';
import 'package:pub_semver/pub_semver.dart';

/// Abstract superclass of classes that provide information about the workspace
/// in which analysis is being performed.
abstract class Workspace {
  /// Return true iff this [Workspace] is a [BlazeWorkspace].
  bool get isBlaze => false;

  /// Return `true` if the read state of configuration files is consistent
  /// with their current state on the file system.
  @internal
  bool get isConsistentWithFileSystem => true;

  /// The [UriResolver] that can resolve `package` URIs.
  UriResolver get packageUriResolver;

  /// The absolute workspace root path.
  String get root;

  /// If this workspace has any configuration that affects resolution
  /// (for example diagnostics), then this configuration should be included
  /// into the result key.
  ///
  /// The resolution salt is later added to the key of every file.
  @internal
  void contributeToResolutionSalt(ApiSignature buffer) {}

  /// Create the source factory that should be used to resolve Uris to
  /// [Source]s. The [sdk] may be `null`. The [summaryData] can also be `null`.
  SourceFactory createSourceFactory(
    DartSdk? sdk,
    SummaryDataStore? summaryData,
  );

  /// Find the [WorkspacePackage] where the library at [filePath] is defined.
  ///
  /// Separate from [Packages] or package maps, this method is designed to find
  /// the package, by its root, in which a library at an arbitrary path is
  /// defined.
  WorkspacePackageImpl? findPackageFor(String filePath);
}

/// Abstract superclass of classes that provide information about a package
/// defined in a Workspace.
///
/// Separate from [Packages] or package maps, this class is designed to simply
/// understand whether arbitrary file paths represent libraries declared within
/// a given package in a Workspace.
abstract class WorkspacePackageImpl implements WorkspacePackage {
  @override
  bool get canHavePublicApi => true;

  /// Return the experiments enabled for all files in the package.
  ///
  /// Return `null` if this package does not have enabled experiments.
  List<String>? get enabledExperiments => null;

  /// Return the language version override for all files in the package.
  ///
  /// We use [enabledExperiments] to enable Null Safety for selected packages
  /// when it is not enabled by default in the SDK, and use [languageVersion]
  /// to disable Null Safety for packages that are not migrated yet.
  ///
  /// Return `null` if this package does not have a language version override.
  Version? get languageVersion => null;

  Workspace get workspace;

  /// Whether this compilation unit [source] is not within the `lib` or `bin`
  /// directories in [root]'s directory tree, and hence the imports can be
  /// listed in the 'dev_dependencies' section of the 'pubspec.yaml' file.
  bool canBeDevDependency(Source source) {
    var cuPath = source.fullName;
    var libDir = root.getChildAssumingFolder('lib');
    var binDir = root.getChildAssumingFolder('bin');
    return !(libDir.contains(cuPath) || binDir.contains(cuPath));
  }

  /// Return a file path for the location of [source].
  ///
  /// If [source]'s URI scheme is package, it's fullName might be unusable (for
  /// example, the case of a [InSummarySource]). In this case, use
  /// [workspace]'s package URI resolver to fetch the file path.
  String? filePathFromSource(Source source) {
    if (source.uri.isScheme('package')) {
      return workspace.packageUriResolver.resolveAbsolute(source.uri)?.fullName;
    } else {
      return source.fullName;
    }
  }

  @override
  bool isInTestDirectory(File file) {
    return false;
  }

  /// Return a map from the names of packages to the absolute and normalized
  /// path of the root of those packages for all of the packages that could
  /// validly be imported by the library with the given [libraryPath].
  Packages packagesAvailableTo(String libraryPath);

  /// Return whether [source] is located in this package's public API.
  bool sourceIsInPublicApi(Source source);
}

/// An interface for a workspace that contains a default analysis options file.
/// Classes that provide information of such a workspace should implement this
/// interface.
@AnalyzerPublicApi(message: 'public exported')
class WorkspaceWithDefaultAnalysisOptions {
  /// The URI for the default analysis options file.
  static const String uri = 'package:dart.analysis_options/default.yaml';

  ///  The URI for third_party analysis options file.
  static const String thirdPartyUri =
      'package:dart.analysis_options/third_party.yaml';
}
