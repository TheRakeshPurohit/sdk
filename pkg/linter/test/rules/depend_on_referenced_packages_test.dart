// Copyright (c) 2023, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/utilities/package_config_file_builder.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../rule_test_support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(DependOnReferencedPackagesTest);
  });
}

@reflectiveTest
class DependOnReferencedPackagesTest extends LintRuleTest {
  @override
  bool get addMetaPackageDep => true;

  @override
  String get lintRule => LintNames.depend_on_referenced_packages;

  String get sourceReferencingMeta => r'''
import 'package:meta/meta.dart';

@visibleForTesting
class C {}
''';

  test_referencedInBin_listedInDevDeps() async {
    newFile(testPackagePubspecPath, r'''
name: fancy
version: 1.1.1

dev_dependencies:
  meta: any
''');
    var binFile = newFile(
      '$testPackageRootPath/bin/bin.dart',
      sourceReferencingMeta,
    );
    await assertDiagnosticsInFile(binFile.path, [lint(7, 24)]);
  }

  void test_referencedInBuildHook_listedInDeps() async {
    newFile(testPackagePubspecPath, r'''
name: fancy
version: 1.1.1

dependencies:
  meta: any
''');
    var hookFile = newFile(
      '$testPackageRootPath/hook/build.dart',
      sourceReferencingMeta,
    );
    await assertNoDiagnosticsInFile(hookFile.path);
  }

  void test_referencedInBuildHook_listedInDevDeps() async {
    newFile(testPackagePubspecPath, r'''
name: fancy
version: 1.1.1

dev_dependencies:
  meta: any
''');
    var hookFile = newFile(
      '$testPackageRootPath/hook/build.dart',
      sourceReferencingMeta,
    );
    await assertDiagnosticsInFile(hookFile.path, [lint(7, 24)]);
  }

  void test_referencedInBuildHook_missingFromPubspec() async {
    newFile(testPackagePubspecPath, r'''
name: fancy
version: 1.1.1
''');
    var hookFile = newFile(
      '$testPackageRootPath/hook/build.dart',
      sourceReferencingMeta,
    );
    await assertDiagnosticsInFile(hookFile.path, [lint(7, 24)]);
  }

  test_referencedInLib_flutterGen() async {
    var packageConfigBuilder = PackageConfigFileBuilder();
    packageConfigBuilder.add(
      name: 'flutter_gen',
      rootPath: '$workspaceRootPath/flutter_gen',
    );
    writeTestPackageConfig(packageConfigBuilder);
    newFile(testPackagePubspecPath, r'''
name: test
version: 1.1.1
''');
    newFile('$workspaceRootPath/flutter_gen/lib/gen.dart', 'var x = 1;');
    await assertNoDiagnostics(r'''
import 'package:flutter_gen/gen.dart';

var y = x;
''');
  }

  test_referencedInLib_listedInDeps() async {
    newFile(testPackagePubspecPath, r'''
name: fancy
version: 1.1.1

dependencies:
  meta: any
''');
    await assertNoDiagnostics(sourceReferencingMeta);
  }

  test_referencedInLib_listedInDevDeps() async {
    newFile(testPackagePubspecPath, r'''
name: fancy
version: 1.1.1

dev_dependencies:
  meta: any
''');
    await assertDiagnostics(sourceReferencingMeta, [lint(7, 24)]);
  }

  test_referencedInLib_missingFromPubspec() async {
    newFile(testPackagePubspecPath, r'''
name: fancy
version: 1.1.1
''');
    await assertDiagnostics(sourceReferencingMeta, [lint(7, 24)]);
  }

  test_referencedInLib_selfPackage() async {
    newFile(testPackagePubspecPath, r'''
name: test
version: 1.1.1
''');
    newFile('$testPackageRootPath/lib/lib.dart', 'var x = 1;');
    await assertNoDiagnostics(r'''
import 'package:test/lib.dart';

var y = x;
''');
  }

  void test_referencedInLinkHook_listedInDevDeps() async {
    newFile(testPackagePubspecPath, r'''
name: fancy
version: 1.1.1

dev_dependencies:
  meta: any
''');
    var hookFile = newFile(
      '$testPackageRootPath/hook/link.dart',
      sourceReferencingMeta,
    );
    await assertDiagnosticsInFile(hookFile.path, [lint(7, 24)]);
  }

  test_referencedInTest_listedInDevDeps() async {
    newFile(testPackagePubspecPath, r'''
name: fancy
version: 1.1.1

dev_dependencies:
  meta: any
''');
    var testFile = newFile(
      '$testPackageRootPath/test/test.dart',
      sourceReferencingMeta,
    );
    await assertNoDiagnosticsInFile(testFile.path);
  }
}
