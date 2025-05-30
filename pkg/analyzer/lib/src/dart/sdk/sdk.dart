// Copyright (c) 2016, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// @docImport 'package:analyzer/src/context/builder.dart';
library;

import 'dart:collection';
import 'dart:io' as io;

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/exception/exception.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/file_system/memory_file_system.dart';
import 'package:analyzer/source/file_source.dart';
import 'package:analyzer/source/source.dart';
import 'package:analyzer/src/dart/sdk/sdk_utils.dart';
import 'package:analyzer/src/generated/engine.dart';
import 'package:analyzer/src/generated/java_engine_io.dart';
import 'package:analyzer/src/generated/sdk.dart';
import 'package:analyzer/src/utilities/uri_cache.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

/// Returns the version of the SDK that runs the analyzer.
Version? get runningSdkVersion {
  try {
    var regExp = RegExp(r'^(\d+\.\d+\.\d+)');
    var match = regExp.firstMatch(io.Platform.version);
    if (match == null) {
      return null;
    }

    var sdkVersionStr = match.group(1)!;
    return Version.parse(sdkVersionStr);
  } catch (_) {
    return null;
  }
}

Version languageVersionFromSdkVersion(String sdkVersionStr) {
  var sdkVersionParts = sdkVersionStr.split('.');
  var sdkVersionMajor = int.parse(sdkVersionParts[0]);
  var sdkVersionMinor = int.parse(sdkVersionParts[1]);
  return Version(sdkVersionMajor, sdkVersionMinor, 0);
}

/// An abstract implementation of a Dart SDK in which the available libraries
/// are stored in a library map. Subclasses are responsible for populating the
/// library map.
abstract class AbstractDartSdk implements DartSdk {
  /// The resource provider used to access the file system.
  late final ResourceProvider resourceProvider;

  /// A mapping from Dart library URI's to the library represented by that URI.
  LibraryMap libraryMap = LibraryMap();

  /// The mapping from Dart URI's to the corresponding sources.
  final Map<String, Source?> _uriToSourceMap = HashMap<String, Source?>();

  @override
  List<SdkLibraryImpl> get sdkLibraries => libraryMap.sdkLibraries;

  /// Return the path separator used by the resource provider.
  String get separator => resourceProvider.pathContext.separator;

  @override
  List<String> get uris => libraryMap.uris;

  /// Return info for debugging https://github.com/dart-lang/sdk/issues/35226.
  Map<String, Object> debugInfo() {
    return <String, Object>{
      'runtimeType': '$runtimeType',
      'libraryMap': libraryMap.debugInfo(),
    };
  }

  @override
  Source? fromFileUri(Uri uri) {
    File file = resourceProvider.getFile(
      resourceProvider.pathContext.fromUri(uri),
    );
    String? path = _getPath(file);
    if (path == null) {
      return null;
    }
    try {
      var uri = uriCache.parse(path);
      return FileSource(file, uri);
    } on FormatException catch (exception, stackTrace) {
      AnalysisEngine.instance.instrumentationService.logInfo(
        "Failed to create URI: $path",
        CaughtException(exception, stackTrace),
      );
    }
    return null;
  }

  String? getRelativePathFromFile(File file);

  @override
  SdkLibrary? getSdkLibrary(String dartUri) => libraryMap.getLibrary(dartUri);

  Source? internalMapDartUri(String dartUri) {
    // TODO(brianwilkerson): Figure out how to unify the implementations in the
    // two subclasses.
    String libraryName;
    String relativePath;
    int index = dartUri.indexOf('/');
    if (index >= 0) {
      libraryName = dartUri.substring(0, index);
      relativePath = dartUri.substring(index + 1);
    } else {
      libraryName = dartUri;
      relativePath = "";
    }
    SdkLibrary? library = getSdkLibrary(libraryName);
    if (library == null) {
      return null;
    }
    String srcPath;
    if (relativePath.isEmpty) {
      srcPath = library.path;
    } else {
      String libraryPath = library.path;
      int index = libraryPath.lastIndexOf(separator);
      if (index == -1) {
        index = libraryPath.lastIndexOf('/');
        if (index == -1) {
          return null;
        }
      }
      String prefix = libraryPath.substring(0, index + 1);
      srcPath = '$prefix$relativePath';
    }
    String filePath = srcPath.replaceAll('/', separator);
    try {
      File file = resourceProvider.getFile(filePath);
      var uri = uriCache.parse(dartUri);
      return FileSource(file, uri);
    } on FormatException {
      return null;
    }
  }

  @override
  Source? mapDartUri(String dartUri) {
    Source? source = _uriToSourceMap[dartUri];
    if (source == null) {
      source = internalMapDartUri(dartUri);
      _uriToSourceMap[dartUri] = source;
    }
    return source;
  }

  @override
  Uri? pathToUri(String path) {
    var file = resourceProvider.getFile(path);

    var uriStr = _getPath(file);
    if (uriStr == null) {
      return null;
    }

    try {
      return uriCache.parse(uriStr);
    } on FormatException {
      return null;
    }
  }

  // TODO(scheglov): This name is misleading, returns `dart:foo/bar.dart`.
  String? _getPath(File file) {
    // TODO(scheglov): Ideally, all `SdkLibrary` should have `File`, with
    // an absolute path, not a relative `path`. For now, we do this only
    // for building SDK summary with `dart:ui`, included from outside
    // of the SDK root.
    for (var library in libraryMap.sdkLibraries) {
      var pathContext = resourceProvider.pathContext;
      if (pathContext.isAbsolute(library.path)) {
        if (library.path == file.path) {
          return library.shortName;
        }
      }
    }
    for (var library in libraryMap.sdkLibraries) {
      var pathContext = resourceProvider.pathContext;
      if (pathContext.isAbsolute(library.path)) {
        String? relativePathIfInside = getRelativePathIfInside(
          library.path,
          file.path,
        );
        if (relativePathIfInside != null) {
          var relPath = relativePathIfInside.replaceAll(separator, '/');
          return '${library.shortName}/$relPath';
        }
      }
    }

    String? filePath = getRelativePathFromFile(file);
    if (filePath == null) {
      return null;
    }

    return getImportUriIfMatchesRelativeSdkPath(
      libraryMap.sdkLibraries,
      filePath,
      separator,
    );
  }
}

/// An SDK backed by URI mappings derived from an `_embedder.yaml` file.
class EmbedderSdk extends AbstractDartSdk {
  static const String _dartColonPrefix = 'dart:';

  static const String _embeddedLibMapKey = 'embedded_libs';

  late final Version _languageVersion;

  final Map<String, String> _urlMappings = HashMap<String, String>();

  // TODO(scheglov): Make [languageVersion] required.
  /// https://github.com/dart-lang/sdk/issues/42890
  EmbedderSdk(
    ResourceProvider resourceProvider,
    Map<Folder, YamlMap>? embedderYamls, {
    Version? languageVersion,
  }) {
    this.resourceProvider = resourceProvider;
    _languageVersion =
        languageVersion ?? languageVersionFromSdkVersion(io.Platform.version);
    embedderYamls?.forEach(_processEmbedderYaml);
  }

  @override
  String? get allowedExperimentsJson {
    var coreSource = mapDartUri('dart:core');
    if (coreSource != null) {
      var coreFile = resourceProvider.getFile(coreSource.fullName);
      var embeddedFolder = coreFile.parent.parent;
      try {
        return embeddedFolder
            .getChildAssumingFolder('_internal')
            .getChildAssumingFile('allowed_experiments.json')
            .readAsStringSync();
      } catch (_) {}
    }
    return null;
  }

  @override
  Version get languageVersion => _languageVersion;

  @override
  // TODO(danrubel): Determine SDK version
  String get sdkVersion => '0';

  /// The URL mappings for this SDK.
  Map<String, String> get urlMappings => _urlMappings;

  @override
  String getRelativePathFromFile(File file) => file.path;

  @override
  Source? internalMapDartUri(String dartUri) {
    String libraryName;
    String relativePath;
    int index = dartUri.indexOf('/');
    if (index >= 0) {
      libraryName = dartUri.substring(0, index);
      relativePath = dartUri.substring(index + 1);
    } else {
      libraryName = dartUri;
      relativePath = "";
    }
    SdkLibrary? library = getSdkLibrary(libraryName);
    if (library == null) {
      return null;
    }
    String srcPath;
    if (relativePath.isEmpty) {
      srcPath = library.path;
    } else {
      String libraryPath = library.path;
      int index = libraryPath.lastIndexOf(separator);
      if (index == -1) {
        index = libraryPath.lastIndexOf('/');
        if (index == -1) {
          return null;
        }
      }
      String prefix = libraryPath.substring(0, index + 1);
      srcPath = '$prefix$relativePath';
    }
    String filePath = srcPath.replaceAll('/', separator);
    try {
      File file = resourceProvider.getFile(filePath);
      var uri = uriCache.parse(dartUri);
      return FileSource(file, uri);
    } on FormatException {
      return null;
    }
  }

  /// Install the mapping from [name] to [libDir]/[file].
  void _processEmbeddedLibs(String name, String file, Folder libDir) {
    if (!name.startsWith(_dartColonPrefix)) {
      // SDK libraries must begin with 'dart:'.
      return;
    }
    String libPath = libDir.canonicalizePath(file);
    _urlMappings[name] = libPath;
    SdkLibraryImpl library = SdkLibraryImpl(name);
    library.path = libPath;
    libraryMap.setLibrary(name, library);
  }

  /// Given the 'embedderYamls' from [EmbedderYamlLocator] check each one for
  /// the top level key 'embedded_libs'. Under the 'embedded_libs' key are key
  /// value pairs. Each key is a 'dart:' library uri and each value is a path
  /// (relative to the directory containing `_embedder.yaml`) to a dart script
  /// for the given library. For example:
  ///
  /// embedded_libs:
  ///   'dart:io': '../../sdk/io/io.dart'
  ///
  /// If a key doesn't begin with `dart:` it is ignored.
  void _processEmbedderYaml(Folder libDir, YamlMap map) {
    var embeddedLibs = map[_embeddedLibMapKey] as YamlNode;
    if (embeddedLibs is YamlMap) {
      embeddedLibs.forEach(
        (k, v) => _processEmbeddedLibs(k as String, v as String, libDir),
      );
    }
  }
}

/// A Dart SDK installed in a specified directory. Typical Dart SDK layout is
/// something like...
///
///     dart-sdk/
///        bin/
///           dart[.exe]  <-- VM
///        lib/
///           core/
///              core.dart
///              ... other core library files ...
///           ... other libraries ...
///        util/
///           ... Dart utilities ...
///     Chromium/   <-- Dartium typically exists in a sibling directory
class FolderBasedDartSdk extends AbstractDartSdk {
  /// The name of the directory within the SDK directory that contains
  /// executables.
  static const String _binDirectoryName = "bin";

  /// The name of the directory within the SDK directory that contains
  /// documentation for the libraries.
  static const String _docsDirectoryName = "docs";

  /// The name of the directory within the SDK directory that contains the
  /// sdk_library_metadata directory.
  static const String _internalDir = "_internal";

  /// The name of the sdk_library_metadata directory that contains the package
  /// holding the libraries.dart file.
  static const String _sdkLibraryMetadataDir = "sdk_library_metadata";

  /// The name of the directory within the sdk_library_metadata that contains
  /// libraries.dart.
  static const String _sdkLibraryMetadataLibDir = "lib";

  /// The name of the directory within the SDK directory that contains the
  /// libraries.
  static const String _libDirectoryName = "lib";

  /// The name of the libraries file.
  static const String _librariesFile = "libraries.dart";

  /// The name of the pub executable on windows.
  static const String _pubExecutableNameWin = "pub.bat";

  /// The name of the pub executable on non-windows operating systems.
  static const String _pubExecutableName = "pub";

  /// The name of the file within the SDK directory that contains the version
  /// number of the SDK.
  static const String _versionFileName = "version";

  /// The directory containing the SDK.
  final Folder _sdkDirectory;

  /// The directory within the SDK directory that contains the libraries.
  Folder? _libraryDirectory;

  /// The revision number of this SDK, or `"0"` if the revision number cannot be
  /// discovered.
  String? _sdkVersion;

  /// The cached language version of this SDK.
  Version? _languageVersion;

  /// The file containing the pub executable.
  File? _pubExecutable;

  /// Initialize a newly created SDK to represent the Dart SDK installed in the
  /// [sdkDirectory].
  FolderBasedDartSdk(ResourceProvider resourceProvider, Folder sdkDirectory)
    : _sdkDirectory = sdkDirectory {
    this.resourceProvider = resourceProvider;
    libraryMap = initialLibraryMap();
  }

  @override
  String get allowedExperimentsJson {
    return _sdkDirectory
        .getChildAssumingFolder('lib')
        .getChildAssumingFolder('_internal')
        .getChildAssumingFile('allowed_experiments.json')
        .readAsStringSync();
  }

  /// Return the directory containing the SDK.
  Folder get directory => _sdkDirectory;

  /// Return the directory containing documentation for the SDK.
  Folder get docDirectory =>
      _sdkDirectory.getChildAssumingFolder(_docsDirectoryName);

  @override
  Version get languageVersion {
    if (_languageVersion == null) {
      var sdkVersionStr =
          _sdkDirectory
              .getChildAssumingFile(_versionFileName)
              .readAsStringSync();
      _languageVersion = languageVersionFromSdkVersion(sdkVersionStr);
    }

    return _languageVersion!;
  }

  /// Return the directory within the SDK directory that contains the libraries.
  Folder get libraryDirectory {
    return _libraryDirectory ??= _sdkDirectory.getChildAssumingFolder(
      _libDirectoryName,
    );
  }

  /// Return the file containing the Pub executable, or `null` if it does not
  /// exist.
  File get pubExecutable {
    return _pubExecutable ??= _sdkDirectory
        .getChildAssumingFolder(_binDirectoryName)
        .getChildAssumingFile(
          OSUtilities.isWindows() ? _pubExecutableNameWin : _pubExecutableName,
        );
  }

  /// Return the revision number of this SDK, or `"0"` if the revision number
  /// cannot be discovered.
  @override
  String get sdkVersion {
    if (_sdkVersion == null) {
      File revisionFile = _sdkDirectory.getChildAssumingFile(_versionFileName);
      try {
        String revision = revisionFile.readAsStringSync();
        _sdkVersion = revision.trim();
      } on FileSystemException {
        return _sdkVersion = DartSdk.DEFAULT_VERSION;
      }
    }
    return _sdkVersion!;
  }

  /// Determine the search order for trying to locate the [_librariesFile].
  Iterable<File> get _libraryMapLocations sync* {
    yield libraryDirectory
        .getChildAssumingFolder(_internalDir)
        .getChildAssumingFolder(_sdkLibraryMetadataDir)
        .getChildAssumingFolder(_sdkLibraryMetadataLibDir)
        .getChildAssumingFile(_librariesFile);
    yield libraryDirectory
        .getChildAssumingFolder(_internalDir)
        .getChildAssumingFile(_librariesFile);
  }

  /// Return info for debugging https://github.com/dart-lang/sdk/issues/35226.
  @override
  Map<String, Object> debugInfo() {
    var result = super.debugInfo();
    result['directory'] = _sdkDirectory.path;
    return result;
  }

  @override
  String? getRelativePathFromFile(File file) {
    String filePath = file.path;
    String libPath = libraryDirectory.path;
    if (!filePath.startsWith("$libPath$separator")) {
      return null;
    }
    return filePath.substring(libPath.length + 1);
  }

  /// Read all of the configuration files to initialize the library maps.
  /// Return the initialized library map.
  LibraryMap initialLibraryMap() {
    List<String> searchedPaths = <String>[];
    late StackTrace lastStackTrace;
    late Object lastException;
    for (File librariesFile in _libraryMapLocations) {
      try {
        String contents = librariesFile.readAsStringSync();
        return SdkLibrariesReader().readFromFile(librariesFile, contents);
      } catch (exception, stackTrace) {
        print('[exception: $exception][stackTrace: $stackTrace]');
        searchedPaths.add(librariesFile.path);
        lastException = exception;
        lastStackTrace = stackTrace;
      }
    }
    StringBuffer buffer = StringBuffer();
    buffer.writeln('Could not initialize the library map from $searchedPaths');
    if (resourceProvider is MemoryResourceProvider) {
      (resourceProvider as MemoryResourceProvider).writeOn(buffer);
    }
    // TODO(39284): should this exception be silent?
    AnalysisEngine.instance.instrumentationService.logException(
      SilentException(buffer.toString(), lastException, lastStackTrace),
    );
    return LibraryMap();
  }

  @override
  Source? internalMapDartUri(String dartUri) {
    String libraryName;
    String relativePath;
    int index = dartUri.indexOf('/');
    if (index >= 0) {
      libraryName = dartUri.substring(0, index);
      relativePath = dartUri.substring(index + 1);
    } else {
      libraryName = dartUri;
      relativePath = "";
    }
    SdkLibrary? library = getSdkLibrary(libraryName);
    if (library == null) {
      return null;
    }
    try {
      File file = libraryDirectory.getChildAssumingFile(library.path);
      if (relativePath.isNotEmpty) {
        File relativeFile = file.parent.getChildAssumingFile(relativePath);
        if (relativeFile.path == file.path) {
          // The relative file is the library, so return a Source for the
          // library rather than the part format.
          var uri = uriCache.parse(library.shortName);
          return FileSource(file, uri);
        }
        file = relativeFile;
      }
      var uri = uriCache.parse(dartUri);
      return FileSource(file, uri);
    } on FormatException {
      return null;
    }
  }
}

/// An object used to read and parse the libraries file
/// (dart-sdk/lib/_internal/sdk_library_metadata/lib/libraries.dart) for
/// information about the libraries in an SDK. The library information is
/// represented as a Dart file containing a single top-level variable whose
/// value is a const map. The keys of the map are the names of libraries defined
/// in the SDK and the values in the map are info objects defining the library.
/// For example, a subset of a typical SDK might have a libraries file that
/// looks like the following:
///
///     final Map<String, LibraryInfo> LIBRARIES = const <LibraryInfo> {
///       // Used by VM applications
///       "builtin" : const LibraryInfo(
///         "builtin/builtin_runtime.dart",
///         category: "Server",
///         platforms: VM_PLATFORM),
///
///       "compiler" : const LibraryInfo(
///         "compiler/compiler.dart",
///         category: "Tools",
///         platforms: 0),
///     };
class SdkLibrariesReader {
  /// Return the library map read from the given [file], given that the content
  /// of the file is already known to be [libraryFileContents].
  LibraryMap readFromFile(File file, String libraryFileContents) {
    // TODO(paulberry): initialize the feature set appropriately based on the
    // version of the SDK we are reading, and enable flags.
    var featureSet = FeatureSet.latestLanguageVersion();

    var parseResult = parseString(
      content: libraryFileContents,
      featureSet: featureSet,
      throwIfDiagnostics: false,
      path: file.path,
    );
    var unit = parseResult.unit;

    var libraryBuilder = SdkLibrariesReader_LibraryBuilder();
    if (parseResult.errors.isEmpty) {
      unit.accept(libraryBuilder);
    }
    return libraryBuilder.librariesMap;
  }
}
