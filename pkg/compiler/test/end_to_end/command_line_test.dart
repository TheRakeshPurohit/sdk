// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// Test the command line options of dart2js.

import 'dart:async';

import 'package:expect/async_helper.dart';
import 'package:expect/expect.dart';

import 'package:compiler/compiler_api.dart' as api;
import 'package:compiler/src/commandline_options.dart';
import 'package:compiler/src/dart2js.dart' as entry;
import 'package:compiler/src/options.dart' show CompilerOptions, CompilerStage;

main() {
  entry.enableWriteString = false;
  asyncTest(() async {
    // Full compile from Dart source
    await test(['foo.dart'], out: 'out.js');
    await test(['foo.dart', '-ofoo.js'], out: 'foo.js');
    await test(['foo.dart', '--out=foo.js'], out: 'foo.js');
    await test(['foo.dart', '--out=/some/path/'], out: '/some/path/out.js');
    await test(['foo.dart', '--out=prefix-'], out: 'prefix-');
    await test([
      'foo.dart',
      '--out=/some/path/prefix-',
    ], out: '/some/path/prefix-');

    // Full compile from dill
    await test(['foo.dill'], allFromDill: true, out: 'out.js');
    await test(['foo.dill', '-ofoo.js'], allFromDill: true, out: 'foo.js');
    await test(['foo.dill', '--out=foo.js'], allFromDill: true, out: 'foo.js');
    await test(
      ['foo.dill', '--out=/some/path/'],
      allFromDill: true,
      out: '/some/path/out.js',
    );
    await test(
      ['foo.dill', '--out=prefix-'],
      allFromDill: true,
      out: 'prefix-',
    );
    await test(
      ['foo.dill', '--out=/some/path/prefix-'],
      allFromDill: true,
      out: '/some/path/prefix-',
    );

    // Run CFE only
    await test(['${Flags.stage}=cfe', 'foo.dart'], out: 'out.dill');
    await test([
      '${Flags.stage}=cfe',
      '--out=out1.dill',
      'foo.dart',
    ], out: 'out1.dill');
    await test([Flags.cfeOnly, 'foo.dart'], out: 'out.dill');
    await test([
      Flags.cfeOnly,
      'foo.dart',
      '--out=out1.dill',
    ], out: 'out1.dill');
    await test([Flags.cfeOnly, 'foo.dart', '-oout1.dill'], out: 'out1.dill');
    await test([Flags.cfeOnly, 'foo.dart', '--out=prefix-'], out: 'prefix-');
    await test([
      Flags.cfeOnly,
      'foo.dart',
      '--out=/some/path/prefix-',
    ], out: '/some/path/prefix-');
    await test([
      'foo.dart',
      '${Flags.stage}=cfe',
      '--out=/some/path/',
    ], out: '/some/path/out.dill');
    await test([
      'foo.dart',
      '${Flags.stage}=cfe',
      '--out=prefix-',
    ], out: 'prefix-out.dill');
    await test([
      'foo.dart',
      '${Flags.stage}=cfe',
      '--out=/some/path/prefix-',
    ], out: '/some/path/prefix-out.dill');

    // Run CFE only from dill
    await test(
      ['${Flags.stage}=cfe', 'foo.dill'],
      cfeFromDill: true,
      out: 'out.dill',
    );
    await test(
      ['${Flags.stage}=cfe', '--out=out1.dill', 'foo.dill'],
      cfeFromDill: true,
      out: 'out1.dill',
    );
    await test([Flags.cfeOnly, 'foo.dill'], cfeFromDill: true, out: 'out.dill');
    await test([
      Flags.cfeOnly,
      'foo.dill',
      '--out=out1.dill',
    ], out: 'out1.dill');
    await test(
      [Flags.cfeOnly, 'foo.dill', '-oout1.dill'],
      cfeFromDill: true,
      out: 'out1.dill',
    );
    await test(
      [Flags.cfeOnly, 'foo.dill', '--out=prefix-'],
      cfeFromDill: true,
      out: 'prefix-',
    );
    await test(
      [Flags.cfeOnly, 'foo.dill', '--out=/some/path/prefix-'],
      cfeFromDill: true,
      out: '/some/path/prefix-',
    );
    await test(
      ['foo.dill', '${Flags.stage}=cfe', '--out=/some/path/'],
      cfeFromDill: true,
      out: '/some/path/out.dill',
    );
    await test(
      ['foo.dill', '${Flags.stage}=cfe', '--out=prefix-'],
      cfeFromDill: true,
      out: 'prefix-out.dill',
    );
    await test(
      ['foo.dill', '${Flags.stage}=cfe', '--out=/some/path/prefix-'],
      cfeFromDill: true,
      out: '/some/path/prefix-out.dill',
    );

    // Run deferred load ids only
    await test([
      '${Flags.stage}=deferred-load-ids',
      'foo.dill',
      '${Flags.deferredLoadIdMapUri}=load_ids.data',
    ], writeDeferredLoadIds: 'load_ids.data');
    await test([
      '${Flags.stage}=deferred-load-ids',
      'foo.dill',
    ], writeDeferredLoadIds: 'deferred_load_ids.data');

    // Run closed world only
    await test([
      '${Flags.stage}=closed-world',
      'foo.dill',
    ], writeClosedWorld: 'world.data');
    await test([
      '${Flags.stage}=closed-world',
      '${Flags.inputDill}=foo.dill',
    ], writeClosedWorld: 'world.data');
    await test([
      '${Flags.stage}=closed-world',
      'foo.dill',
    ], writeClosedWorld: 'world.data');
    await test([
      '${Flags.stage}=closed-world',
      '${Flags.closedWorldUri}=world1.data',
      'foo.dill',
    ], writeClosedWorld: 'world1.data');
    await test([
      'foo.dill',
      '${Flags.stage}=closed-world',
      '--out=/some/path/',
    ], writeClosedWorld: '/some/path/world.data');
    await test([
      'foo.dill',
      '${Flags.stage}=closed-world',
      '--out=prefix-',
    ], writeClosedWorld: 'prefix-world.data');
    await test([
      'foo.dill',
      '${Flags.stage}=closed-world',
      '--out=/some/path/prefix-',
    ], writeClosedWorld: '/some/path/prefix-world.data');
    await test([
      '${Flags.stage}=closed-world',
      'foo.dart',
    ], writeClosedWorld: 'world.data');

    // Run global inference only
    await test(
      ['${Flags.stage}=global-inference', 'foo.dill'],
      readClosedWorld: 'world.data',
      writeData: 'global.data',
    );
    await test(
      ['${Flags.stage}=global-inference', '${Flags.inputDill}=foo.dill'],
      readClosedWorld: 'world.data',
      writeData: 'global.data',
    );
    await test(
      [
        '${Flags.stage}=global-inference',
        '${Flags.closedWorldUri}=world1.data',
        'foo.dill',
      ],
      readClosedWorld: 'world1.data',
      writeData: 'global.data',
    );
    await test(
      [
        '${Flags.stage}=global-inference',
        '${Flags.globalInferenceUri}=global1.data',
        'foo.dill',
      ],
      readClosedWorld: 'world.data',
      writeData: 'global1.data',
    );
    await test(
      ['foo.dill', '${Flags.stage}=global-inference', '--out=/some/path/'],
      readClosedWorld: '/some/path/world.data',
      writeData: '/some/path/global.data',
    );
    await test(
      ['foo.dill', '${Flags.stage}=global-inference', '--out=prefix-'],
      readClosedWorld: 'prefix-world.data',
      writeData: 'prefix-global.data',
    );
    await test(
      [
        'foo.dill',
        '${Flags.stage}=global-inference',
        '--out=/some/path/prefix-',
      ],
      readClosedWorld: '/some/path/prefix-world.data',
      writeData: '/some/path/prefix-global.data',
    );
    await test(
      [
        'foo.dill',
        '${Flags.stage}=global-inference',
        '--out=/some/path/foo.data',
      ],
      readClosedWorld: '/some/path/foo.dataworld.data',
      writeData: '/some/path/foo.dataglobal.data',
    );
    await test(
      ['foo.dart', '${Flags.stage}=global-inference'],
      readClosedWorld: 'world.data',
      writeData: 'global.data',
    );

    // Run codegen only
    await test(
      [
        '${Flags.stage}=codegen',
        '${Flags.codegenShard}=10',
        '${Flags.codegenShards}=11',
        'foo.dill',
      ],
      readClosedWorld: 'world.data',
      readData: 'global.data',
      writeCodegen: 'codegen',
      codegenShard: 10,
      codegenShards: 11,
    );
    await test(
      [
        '${Flags.stage}=codegen',
        '${Flags.codegenShard}=10',
        '${Flags.codegenShards}=11',
        '${Flags.inputDill}=foo.dill',
      ],
      readClosedWorld: 'world.data',
      readData: 'global.data',
      writeCodegen: 'codegen',
      codegenShard: 10,
      codegenShards: 11,
    );
    await test(
      [
        '${Flags.stage}=codegen',
        '${Flags.closedWorldUri}=world1.data',
        '${Flags.globalInferenceUri}=global1.data',
        '${Flags.codegenShard}=10',
        '${Flags.codegenShards}=11',
        'foo.dill',
      ],
      readClosedWorld: 'world1.data',
      readData: 'global1.data',
      writeCodegen: 'codegen',
      codegenShard: 10,
      codegenShards: 11,
    );
    await test(
      [
        '${Flags.stage}=codegen',
        '${Flags.codegenUri}=codegen1',
        '${Flags.codegenShard}=10',
        '${Flags.codegenShards}=11',
        'foo.dill',
      ],
      readClosedWorld: 'world.data',
      readData: 'global.data',
      writeCodegen: 'codegen1',
      codegenShard: 10,
      codegenShards: 11,
    );
    await test(
      [
        'foo.dill',
        '${Flags.stage}=codegen',
        '--out=/some/path/',
        '${Flags.codegenShard}=10',
        '${Flags.codegenShards}=11',
      ],
      readClosedWorld: '/some/path/world.data',
      readData: '/some/path/global.data',
      writeCodegen: '/some/path/codegen',
      codegenShard: 10,
      codegenShards: 11,
    );
    await test(
      [
        'foo.dill',
        '${Flags.stage}=codegen',
        '--out=prefix-',
        '${Flags.codegenShard}=10',
        '${Flags.codegenShards}=11',
      ],
      readClosedWorld: 'prefix-world.data',
      readData: 'prefix-global.data',
      writeCodegen: 'prefix-codegen',
      codegenShard: 10,
      codegenShards: 11,
    );
    await test(
      [
        'foo.dill',
        '${Flags.stage}=codegen',
        '--out=/some/path/prefix-',
        '${Flags.codegenShard}=10',
        '${Flags.codegenShards}=11',
      ],
      readClosedWorld: '/some/path/prefix-world.data',
      readData: '/some/path/prefix-global.data',
      writeCodegen: '/some/path/prefix-codegen',
      codegenShard: 10,
      codegenShards: 11,
    );
    await test(
      [
        'foo.dill',
        '${Flags.stage}=codegen',
        '--out=/some/path/foo.data',
        '${Flags.codegenShard}=10',
        '${Flags.codegenShards}=11',
      ],
      readClosedWorld: '/some/path/foo.dataworld.data',
      readData: '/some/path/foo.dataglobal.data',
      writeCodegen: '/some/path/foo.datacodegen',
      codegenShard: 10,
      codegenShards: 11,
    );
    await test(
      [
        'foo.dill',
        '${Flags.stage}=codegen',
        '--out=foo.data',
        '${Flags.codegenShard}=10',
        '${Flags.codegenShards}=11',
      ],
      readClosedWorld: 'foo.dataworld.data',
      readData: 'foo.dataglobal.data',
      writeCodegen: 'foo.datacodegen',
      codegenShard: 10,
      codegenShards: 11,
    );
    await test(
      [
        '${Flags.stage}=codegen',
        '${Flags.codegenShard}=10',
        '${Flags.codegenShards}=11',
        'foo.dart',
      ],
      readClosedWorld: 'world.data',
      readData: 'global.data',
      writeCodegen: 'codegen',
      codegenShard: 10,
      codegenShards: 11,
    );

    // Run emitter only
    await test(
      ['${Flags.stage}=emit-js', '${Flags.codegenShards}=11', 'foo.dill'],
      readClosedWorld: 'world.data',
      readData: 'global.data',
      readCodegen: 'codegen',
      codegenShards: 11,
      out: 'out.js',
    );
    await test(
      [
        '${Flags.stage}=emit-js',
        '${Flags.codegenShards}=11',
        '${Flags.inputDill}=foo.dill',
      ],
      readClosedWorld: 'world.data',
      readData: 'global.data',
      readCodegen: 'codegen',
      codegenShards: 11,
      out: 'out.js',
    );
    await test(
      [
        '${Flags.stage}=emit-js',
        '${Flags.closedWorldUri}=world1.data',
        '${Flags.globalInferenceUri}=global1.data',
        '${Flags.codegenUri}=codegen1',
        '${Flags.codegenShards}=11',
        'foo.dill',
      ],
      readClosedWorld: 'world1.data',
      readData: 'global1.data',
      readCodegen: 'codegen1',
      codegenShards: 11,
      out: 'out.js',
    );
    await test(
      [
        '${Flags.stage}=emit-js',
        '--out=out.js',
        '${Flags.codegenShards}=11',
        'foo.dill',
      ],
      readClosedWorld: 'world.data',
      readData: 'global.data',
      readCodegen: 'codegen',
      codegenShards: 11,
      out: 'out.js',
    );
    await test(
      [
        'foo.dill',
        '${Flags.stage}=emit-js',
        '--out=/some/path/',
        '${Flags.codegenShards}=11',
      ],
      readClosedWorld: '/some/path/world.data',
      readData: '/some/path/global.data',
      readCodegen: '/some/path/codegen',
      codegenShards: 11,
      out: '/some/path/out.js',
    );
    await test(
      [
        'foo.dill',
        '${Flags.stage}=emit-js',
        '--out=prefix-',
        '${Flags.codegenShards}=11',
      ],
      readClosedWorld: 'prefix-world.data',
      readData: 'prefix-global.data',
      readCodegen: 'prefix-codegen',
      codegenShards: 11,
      out: 'prefix-out.js',
    );
    await test(
      [
        'foo.dill',
        '${Flags.stage}=emit-js',
        '--out=/some/path/prefix-',
        '${Flags.codegenShards}=11',
      ],
      readClosedWorld: '/some/path/prefix-world.data',
      readData: '/some/path/prefix-global.data',
      readCodegen: '/some/path/prefix-codegen',
      codegenShards: 11,
      out: '/some/path/prefix-out.js',
    );
    await test(
      ['${Flags.stage}=emit-js', '${Flags.codegenShards}=11', 'foo.dart'],
      readClosedWorld: 'world.data',
      readData: 'global.data',
      readCodegen: 'codegen',
      codegenShards: 11,
      out: 'out.js',
    );

    // Run codegen and emitter only
    await test(
      ['${Flags.stage}=codegen-emit-js', 'foo.dill'],
      readClosedWorld: 'world.data',
      readData: 'global.data',
      out: 'out.js',
    );
    await test(
      ['${Flags.stage}=codegen-emit-js', '${Flags.inputDill}=foo.dill'],
      readClosedWorld: 'world.data',
      readData: 'global.data',
      out: 'out.js',
    );
    await test(
      [
        '${Flags.stage}=codegen-emit-js',
        '${Flags.closedWorldUri}=world1.data',
        '${Flags.globalInferenceUri}=global1.data',
        'foo.dill',
      ],
      readClosedWorld: 'world1.data',
      readData: 'global1.data',
      out: 'out.js',
    );
    await test(
      ['${Flags.stage}=codegen-emit-js', '--out=out.js', 'foo.dill'],
      readClosedWorld: 'world.data',
      readData: 'global.data',
      out: 'out.js',
    );
    await test(
      ['foo.dill', '${Flags.stage}=codegen-emit-js', '--out=/some/path/'],
      readClosedWorld: '/some/path/world.data',
      readData: '/some/path/global.data',
      out: '/some/path/out.js',
    );
    await test(
      ['foo.dill', '${Flags.stage}=codegen-emit-js', '--out=prefix-'],
      readClosedWorld: 'prefix-world.data',
      readData: 'prefix-global.data',
      out: 'prefix-out.js',
    );
    await test(
      [
        'foo.dill',
        '${Flags.stage}=codegen-emit-js',
        '--out=/some/path/prefix-',
      ],
      readClosedWorld: '/some/path/prefix-world.data',
      readData: '/some/path/prefix-global.data',
      out: '/some/path/prefix-out.js',
    );
    await test(
      ['${Flags.stage}=codegen-emit-js', 'foo.dart'],
      readClosedWorld: 'world.data',
      readData: 'global.data',
      out: 'out.js',
    );

    // Invalid states with stage flag
    // Codegen stage
    await test(
      [
        '${Flags.stage}=codegen',
        '${Flags.codegenUri}=codegen',
        '${Flags.codegenShards}=1',
        'foo.dill',
      ],
      readCodegen: 'codegen',
      out: 'out.js',
      exitCode: 1,
    );
    await test(
      [
        '${Flags.stage}=codegen',
        '${Flags.codegenUri}=codegen',
        '${Flags.codegenShard}=0',
        'foo.dill',
      ],
      readCodegen: 'codegen',
      out: 'out.js',
      exitCode: 1,
    );

    // JS Emitter stage
    await test(['${Flags.stage}=emit-js', 'foo.dart'], exitCode: 1);

    // Omit memory summary.
    await test(['--omit-memory-summary', 'foo.dart'], out: 'out.js');
  });
}

Future test(
  List<String> arguments, {
  int? exitCode,
  String? out,
  bool allFromDill = false,
  bool cfeFromDill = false,
  bool cfeModularAnalysis = false,
  String? readClosedWorld,
  String? writeClosedWorld,
  String? writeDeferredLoadIds,
  String? readData,
  String? writeData,
  String? readCodegen,
  String? writeCodegen,
  int? codegenShard,
  int? codegenShards,
}) async {
  print('--------------------------------------------------------------------');
  print('dart2js ${arguments.join(' ')}');
  print('--------------------------------------------------------------------');
  entry.CompileFunc oldCompileFunc = entry.compileFunc;
  entry.ExitFunc oldExitFunc = entry.exitFunc;

  late final CompilerOptions options;
  int? actualExitCode;
  entry.compileFunc = (_options, input, diagnostics, output) {
    options = _options;
    return Future<api.CompilationResult>.value(api.CompilationResult(null));
  };
  entry.exitFunc = (_exitCode) {
    actualExitCode = _exitCode;
    throw 'exited';
  };
  try {
    await entry.compilerMain(arguments);
  } catch (e, s) {
    Expect.equals('exited', e, "Unexpected exception: $e\n$s");
  }
  Expect.equals(exitCode, actualExitCode, "Unexpected exit code");
  if (actualExitCode == null) {
    Expect.equals(toUri(out), options.outputUri, "Unexpected output uri.");
    if (allFromDill || cfeFromDill) {
      Expect.isNotNull(options.compilationTarget.path.endsWith('.dill'));
    }
    if (writeDeferredLoadIds == null) {
      Expect.notEquals(options.stage, CompilerStage.deferredLoadIds);
    } else {
      Expect.equals(options.stage, CompilerStage.deferredLoadIds);
      Expect.equals(
        toUri(writeDeferredLoadIds),
        options.dataUriForStage(CompilerStage.deferredLoadIds),
        "Unexpected writeDeferredLoadIds uri",
      );
    }
    if (readClosedWorld == null) {
      Expect.isFalse(options.stage.shouldReadClosedWorld);
    } else {
      Expect.isTrue(options.stage.shouldReadClosedWorld);
      Expect.equals(
        toUri(readClosedWorld),
        options.dataUriForStage(CompilerStage.closedWorld),
        "Unexpected readClosedWorld uri",
      );
    }
    if (writeClosedWorld == null) {
      Expect.notEquals(options.stage, CompilerStage.closedWorld);
    } else {
      Expect.equals(options.stage, CompilerStage.closedWorld);
      Expect.equals(
        toUri(writeClosedWorld),
        options.dataUriForStage(CompilerStage.closedWorld),
        "Unexpected writeClosedWorld uri",
      );
    }
    if (readData == null) {
      Expect.isFalse(options.stage.shouldReadGlobalInference);
    } else {
      Expect.isTrue(options.stage.shouldReadGlobalInference);
      Expect.equals(
        toUri(readData),
        options.dataUriForStage(CompilerStage.globalInference),
        "Unexpected readData uri",
      );
    }
    if (writeData == null) {
      Expect.notEquals(options.stage, CompilerStage.globalInference);
    } else {
      Expect.equals(options.stage, CompilerStage.globalInference);
      Expect.equals(
        toUri(writeData),
        options.dataUriForStage(CompilerStage.globalInference),
        "Unexpected writeData uri",
      );
    }
    if (readCodegen == null) {
      Expect.isFalse(options.stage.shouldReadCodegenShards);
    } else {
      Expect.isTrue(options.stage.shouldReadCodegenShards);
      Expect.equals(
        toUri(readCodegen),
        options.dataUriForStage(CompilerStage.codegenSharded),
        "Unexpected readCodegen uri",
      );
    }
    if (writeCodegen == null) {
      Expect.notEquals(options.stage, CompilerStage.codegenSharded);
    } else {
      Expect.equals(options.stage, CompilerStage.codegenSharded);
      Expect.equals(
        toUri(writeCodegen),
        options.dataUriForStage(CompilerStage.codegenSharded),
        "Unexpected writeCodegen uri",
      );
    }
    Expect.equals(
      codegenShard,
      options.codegenShard,
      "Unexpected codegenShard uri",
    );
    Expect.equals(
      codegenShards,
      options.codegenShards,
      "Unexpected codegenShards uri",
    );
  }

  entry.compileFunc = oldCompileFunc;
  entry.exitFunc = oldExitFunc;
}

Uri? toUri(String? path) => path != null ? Uri.base.resolve(path) : null;
