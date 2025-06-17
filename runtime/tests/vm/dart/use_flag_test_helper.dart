// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'dart:ffi';

import 'package:expect/config.dart';
import 'package:expect/expect.dart';
import 'package:path/path.dart' as path;

final isAOTRuntime = isVmAotConfiguration;
final buildDir = path.dirname(Platform.executable);
final sdkDir = path.dirname(path.dirname(buildDir));
late final platformDill = () {
  final possiblePaths = [
    // No cross compilation.
    path.join(buildDir, 'vm_platform.dill'),
    // ${MODE}SIMARM_X64 for X64->SIMARM cross compilation.
    path.join('${buildDir}_X64', 'vm_platform.dill'),
  ];
  for (final path in possiblePaths) {
    if (File(path).existsSync()) {
      return path;
    }
  }
  throw 'Could not find vm_platform.dill for build directory $buildDir';
}();
final genKernel = path.join(
  sdkDir,
  'pkg',
  'vm',
  'tool',
  'gen_kernel' + (Platform.isWindows ? '.bat' : ''),
);
final genKernelDart = path.join('pkg', 'vm', 'bin', 'gen_kernel.dart');
final _genSnapshotBase = 'gen_snapshot' + (Platform.isWindows ? '.exe' : '');
// Lazily initialize `genSnapshot` so that tests that don't use it on platforms
// that don't have a `gen_snapshot` don't fail.
late final genSnapshot = () {
  final possiblePaths = [
    // No cross compilation.
    path.join(buildDir, _genSnapshotBase),
    // ${MODE}SIMARM_X64 for X64->SIMARM cross compilation.
    path.join('${buildDir}_X64', _genSnapshotBase),
    // ${MODE}XARM64/clang_x64 for X64->ARM64 cross compilation.
    path.join(buildDir, 'clang_x64', _genSnapshotBase),
  ];
  for (final path in possiblePaths) {
    if (File(path).existsSync()) {
      return path;
    }
  }
  throw 'Could not find gen_snapshot for build directory $buildDir';
}();
final dart = path.join(buildDir, 'dart' + (Platform.isWindows ? '.exe' : ''));
final dartPrecompiledRuntime = path.join(
  buildDir,
  'dartaotruntime' + (Platform.isWindows ? '.exe' : ''),
);
final checkedInDartVM = path.join(
  'tools',
  'sdks',
  'dart-sdk',
  'bin',
  'dart' + (Platform.isWindows ? '.exe' : ''),
);
String? llvmTool(String name, {bool verbose = false}) {
  final clangBuildTools = clangBuildToolsDir;
  if (clangBuildTools != null) {
    final toolPath = path.join(clangBuildTools, name);
    if (File(toolPath).existsSync()) {
      return toolPath;
    }
    if (verbose) {
      print('Could not find $name binary at $toolPath');
    }
    return null;
  }
  if (verbose) {
    print('Could not find $name binary');
  }
  return null;
}

final isSimulator = path.basename(buildDir).contains('SIM');

String? get clangBuildToolsDir {
  String archDir;
  switch (Abi.current()) {
    case Abi.linuxX64:
      archDir = 'linux-x64';
      break;
    case Abi.linuxArm64:
      archDir = 'linux-arm64';
      break;
    case Abi.macosX64:
      archDir = 'mac-x64';
      break;
    case Abi.macosArm64:
      archDir = 'mac-arm64';
      break;
    case Abi.windowsX64:
    case Abi.windowsArm64: // We don't have a proper host win-arm64 toolchain.
      archDir = 'win-x64';
      break;
    default:
      return null;
  }
  var clangDir = path.join(sdkDir, 'buildtools', archDir, 'clang', 'bin');
  print(clangDir);
  return Directory(clangDir).existsSync() ? clangDir : null;
}

Future<void> assembleSnapshot(
  String assemblyPath,
  String snapshotPath, {
  bool debug = false,
}) async {
  if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) {
    throw "Unsupported platform ${Platform.operatingSystem} for assembling";
  }

  final ccFlags = <String>[];
  final ldFlags = <String>[];
  String cc = 'gcc';
  String shared = '-shared';

  final clangBuildTools = clangBuildToolsDir;
  if (clangBuildTools != null) {
    cc = path.join(clangBuildTools, Platform.isWindows ? 'clang.exe' : 'clang');
  } else {
    throw 'Cannot assemble for ${path.basename(buildDir)} '
        'without //buildtools on ${Platform.operatingSystem}';
  }

  if (Platform.isMacOS) {
    shared = '-dynamiclib';
    // Tell Mac linker to give up generating eh_frame from dwarf.
    ldFlags.add('-Wl,-no_compact_unwind');
    if (buildDir.endsWith('ARM64')) {
      ccFlags.add('--target=arm64-apple-darwin');
    } else {
      ccFlags.add('--target=x86_64-apple-darwin');
    }
  } else if (Platform.isLinux) {
    if (buildDir.endsWith('ARM')) {
      ccFlags.add('--target=armv7-linux-gnueabihf');
    } else if (buildDir.endsWith('ARM64')) {
      ccFlags.add('--target=aarch64-linux-gnu');
    } else if (buildDir.endsWith('X64')) {
      ccFlags.add('--target=x86_64-linux-gnu');
    } else if (buildDir.endsWith('RISCV64')) {
      ccFlags.add('--target=riscv64-linux-gnu');
    }
  }

  if (debug) {
    ccFlags.add('-g');
  }

  await run(cc, <String>[
    ...ccFlags,
    ...ldFlags,
    '-nostdlib',
    shared,
    '-o',
    snapshotPath,
    assemblyPath,
  ]);
}

Future<void> stripSnapshot(
  String snapshotPath,
  String strippedPath, {
  bool forceElf = false,
}) async {
  if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) {
    throw "Unsupported platform ${Platform.operatingSystem} for stripping";
  }

  var strip = 'strip';

  final clangBuildTools = clangBuildToolsDir;
  if (clangBuildTools != null) {
    strip = path.join(
      clangBuildTools,
      Platform.isWindows ? 'llvm-strip.exe' : 'llvm-strip',
    );
  } else {
    throw 'Cannot strip ELF files for ${path.basename(buildDir)} '
        'without //buildtools on ${Platform.operatingSystem}';
  }

  await run(strip, <String>['-o', strippedPath, snapshotPath]);
}

Future<ProcessResult> runHelper(
  String executable,
  List<String> args, {
  bool printStdout = true,
  bool printStderr = true,
}) async {
  print('Running $executable ${args.join(' ')}');

  final result = await Process.run(executable, args);
  print('Subcommand terminated with exit code ${result.exitCode}.');
  if (printStdout && result.stdout.isNotEmpty) {
    print('Subcommand stdout:');
    print(result.stdout);
  }
  if (printStderr && result.stderr.isNotEmpty) {
    print('Subcommand stderr:');
    print(result.stderr);
  }

  return result;
}

Future<bool> testExecutable(String executable) async {
  try {
    final result = await runHelper(executable, <String>['--version']);
    return result.exitCode == 0;
  } on ProcessException catch (e) {
    print('Got process exception: $e');
    return false;
  }
}

Future<void> run(String executable, List<String> args) async {
  final result = await runHelper(executable, args);

  if (result.exitCode != 0) {
    throw 'Command failed with unexpected exit code (was ${result.exitCode})';
  }
}

Future<void> runSilent(String executable, List<String> args) async {
  final result = await runHelper(
    executable,
    args,
    printStdout: false,
    printStderr: false,
  );

  if (result.exitCode != 0) {
    throw 'Command failed with unexpected exit code (was ${result.exitCode})';
  }
}

Future<List<String>> runOutput(String executable, List<String> args) async {
  final result = await runHelper(executable, args);

  if (result.exitCode != 0) {
    throw 'Command failed with unexpected exit code (was ${result.exitCode})';
  }
  Expect.isTrue(result.stdout.isNotEmpty);
  Expect.isTrue(result.stderr.isEmpty);

  return LineSplitter.split(result.stdout).toList(growable: false);
}

Future<List<String>> runError(String executable, List<String> args) async {
  final result = await runHelper(executable, args);

  if (result.exitCode == 0) {
    throw 'Command did not fail with non-zero exit code';
  }
  Expect.isTrue(result.stdout.isEmpty);
  Expect.isTrue(result.stderr.isNotEmpty);

  return LineSplitter.split(result.stderr).toList(growable: false);
}

const keepTempKey = 'KEEP_TEMPORARY_DIRECTORIES';

Future<void> withTempDir(String name, Future<void> fun(String dir)) async {
  final tempDir = Directory.systemTemp.createTempSync(name);
  try {
    await fun(tempDir.path);
  } finally {
    if (!Platform.environment.containsKey(keepTempKey) ||
        Platform.environment[keepTempKey]!.isEmpty) {
      tempDir.deleteSync(recursive: true);
    }
  }
}
