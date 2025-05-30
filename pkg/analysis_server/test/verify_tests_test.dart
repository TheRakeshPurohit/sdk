// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer_testing/package_root.dart' as package_root;
import 'package:analyzer_utilities/verify_tests.dart';
import 'package:path/path.dart' as path;

void main() {
  var provider = PhysicalResourceProvider.INSTANCE;
  var packageRoot = provider.pathContext.normalize(package_root.packageRoot);
  var pathToAnalyze = provider.pathContext.join(packageRoot, 'analysis_server');
  var testDirPath = provider.pathContext.join(pathToAnalyze, 'test');
  _VerifyTests(
    testDirPath,
    excludedPaths: [provider.pathContext.join(testDirPath, 'mock_packages')],
  ).build();
}

class _VerifyTests extends VerifyTests {
  _VerifyTests(super.testDirPath, {super.excludedPaths});

  @override
  bool isExpensive(Resource resource) {
    return resource.shortName == 'integration' ||
        resource.shortName == 'benchmarks_test.dart';
  }

  @override
  bool isOkAsAdditionalTestAllImport(Folder folder, String uri) {
    var pathContext = folder.provider.pathContext;

    if (folder.path == pathContext.join(testDirPath, 'lsp') &&
        uri == '../src/lsp/lsp_packet_transformer_test.dart') {
      // `lsp/test_all.dart` also runs this one test in `lsp/src` for
      // convenience.
      return true;
    }
    if (folder.path == testDirPath &&
        uri == '../tool/spec/check_all_test.dart') {
      // The topmost `test_all.dart` also runs this one test in `tool` for
      // convenience.
      return true;
    }

    // Allow for updating textual expectations.
    if (path.url.basename(uri) == 'text_expectations.dart') {
      if (folder.path ==
          pathContext.join(testDirPath, 'services', 'completion', 'dart')) {
        return true;
      }
    }

    return super.isOkAsAdditionalTestAllImport(folder, uri);
  }
}
