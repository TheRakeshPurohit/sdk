// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';
import 'package:_fe_analyzer_shared/src/testing/features.dart';
import 'package:expect/async_helper.dart';
import 'package:compiler/src/compiler.dart';
import 'package:compiler/src/dump_info.dart';
import 'package:compiler/src/elements/entities.dart';
import 'package:compiler/src/js_model/element_map.dart';
import 'package:compiler/src/js_model/js_world.dart';
import 'package:dart2js_info/info.dart' as info;
import 'package:dart2js_info/json_info_codec.dart' as info;
import 'package:kernel/ast.dart' as ir;
import '../equivalence/id_equivalence.dart';
import '../equivalence/id_equivalence_helper.dart';

final JsonEncoder encoder = const JsonEncoder();
final JsonEncoder indentedEncoder = const JsonEncoder.withIndent('  ');

String jsonEncode(Map object, {bool indent = true}) {
  final jsonEncoder = indent ? indentedEncoder : encoder;
  // Filter block comments since they interfere with ID test comments.
  final json = jsonEncoder
      .convert(object)
      .replaceAll('/*', '')
      .replaceAll('*/', '');
  return json;
}

Map filteredJsonObject(Map object, Set<String> filteredFields) {
  Map filteredObject = {};
  object.forEach((key, value) {
    if (filteredFields.contains(key)) return;
    filteredObject[key] = value;
  });
  return filteredObject;
}

main(List<String> args) {
  asyncTest(() async {
    Directory dataDir = Directory.fromUri(Platform.script.resolve('data_new'));
    print('Testing output of new-dump-info');
    print('==================================================================');
    await checkTests(
      dataDir,
      const DumpInfoDataComputer(),
      args: args,
      testedConfigs: allSpecConfigs,
      options: ['--stage=dump-info-all', '--new-dump-info', '--enable-asserts'],
    );
  });
}

class Tags {
  static const String library = 'library';
  static const String clazz = 'class';
  static const String classType = 'classType';
  static const String closure = 'closure';
  static const String function = 'function';
  static const String typeDef = 'typedef';
  static const String field = 'field';
  static const String constant = 'constant';
  static const String holding = 'holding';
  static const String dependencies = 'dependencies';
  static const String outputUnits = 'outputUnits';
  static const String deferredFiles = 'deferredFiles';
}

class DumpInfoDataComputer extends DataComputer<Features> {
  const DumpInfoDataComputer();

  static const String wildcard = '%';

  @override
  void computeLibraryData(
    Compiler compiler,
    LibraryEntity library,
    Map<Id, ActualData<Features>> actualMap, {
    required bool verbose,
  }) {
    final converter = info.AllInfoToJsonConverter(isBackwardCompatible: true);
    DumpInfoStateData dumpInfoState = compiler.dumpInfoStateForTesting;

    final features = Features();
    final libraryInfo = dumpInfoState.entityToInfo[library];
    if (libraryInfo == null) return;

    features.addElement(
      Tags.library,
      jsonEncode(libraryInfo.accept(converter)),
    );

    // Store program-wide information on the main library.
    final name = '${library.canonicalUri.pathSegments.last}';
    if (name.startsWith('main')) {
      for (final constantInfo in dumpInfoState.info.constants) {
        features.addElement(
          Tags.constant,
          jsonEncode(constantInfo.accept(converter)),
        );
      }
      features.addElement(
        Tags.dependencies,
        jsonEncode(dumpInfoState.info.dependencies),
      );
      for (final outputUnit in dumpInfoState.info.outputUnits) {
        var outputUnitJsonObject = outputUnit.accept(converter);
        // Remove the size from the main output unit due to high noise ratio.
        if (outputUnit.name == 'main') {
          outputUnitJsonObject = filteredJsonObject(outputUnitJsonObject, {
            'size',
          });
        }
        features.addElement(Tags.outputUnits, jsonEncode(outputUnitJsonObject));
      }
      features.addElement(
        Tags.deferredFiles,
        jsonEncode(dumpInfoState.info.deferredFiles!),
      );
    }

    final id = LibraryId(library.canonicalUri);
    actualMap[id] = ActualData<Features>(
      id,
      features,
      library.canonicalUri,
      -1,
      library,
    );
  }

  @override
  void computeClassData(
    Compiler compiler,
    ClassEntity cls,
    Map<Id, ActualData<Features>> actualMap, {
    bool verbose = false,
  }) {
    final converter = info.AllInfoToJsonConverter(isBackwardCompatible: true);
    DumpInfoStateData dumpInfoState = compiler.dumpInfoStateForTesting;

    final features = Features();
    final classInfo = dumpInfoState.entityToInfo[cls];
    if (classInfo == null) return;

    features.addElement(Tags.clazz, jsonEncode(classInfo.accept(converter)));
    final classTypeInfos = dumpInfoState.info.classTypes.where(
      (i) => i.name == classInfo.name,
    );
    assert(
      classTypeInfos.length < 2,
      'Ambiguous class type info resolution. '
      'Expected 0 or 1 elements, found: $classTypeInfos',
    );
    if (classTypeInfos.length == 1) {
      features.addElement(
        Tags.classType,
        jsonEncode(classTypeInfos.first.accept(converter)),
      );
    }

    JClosedWorld closedWorld = compiler.backendClosedWorldForTesting!;
    JsToElementMap elementMap = closedWorld.elementMap;
    ir.Class node = elementMap.getClassDefinition(cls).node as ir.Class;
    ClassId id = ClassId(node.name);
    ir.TreeNode nodeWithOffset = computeTreeNodeWithOffset(node)!;
    actualMap[id] = ActualData<Features>(
      id,
      features,
      nodeWithOffset.location!.file,
      nodeWithOffset.fileOffset,
      cls,
    );
  }

  @override
  void computeMemberData(
    Compiler compiler,
    MemberEntity member,
    Map<Id, ActualData<Features>> actualMap, {
    bool verbose = false,
  }) {
    final converter = info.AllInfoToJsonConverter(isBackwardCompatible: true);
    DumpInfoStateData dumpInfoState = compiler.dumpInfoStateForTesting;

    final features = Features();
    final functionInfo = dumpInfoState.entityToInfo[member];
    if (functionInfo == null) return;

    if (functionInfo is info.FunctionInfo) {
      features.addElement(
        Tags.function,
        jsonEncode(functionInfo.accept(converter)),
      );
      for (final use in functionInfo.uses) {
        features.addElement(
          Tags.holding,
          jsonEncode(converter.visitDependencyInfo(use), indent: false),
        );
      }
      for (final closure in functionInfo.closures) {
        features.addElement(
          Tags.closure,
          jsonEncode(closure.accept(converter)),
        );
        features.addElement(
          Tags.function,
          jsonEncode(closure.function.accept(converter)),
        );
      }
    }

    if (functionInfo is info.FieldInfo) {
      features.addElement(
        Tags.function,
        jsonEncode(functionInfo.accept(converter)),
      );
      for (final use in functionInfo.uses) {
        features.addElement(
          Tags.holding,
          jsonEncode(converter.visitDependencyInfo(use), indent: false),
        );
      }
      for (final closure in functionInfo.closures) {
        features.addElement(
          Tags.closure,
          jsonEncode(closure.accept(converter)),
        );
        features.addElement(
          Tags.function,
          jsonEncode(closure.function.accept(converter)),
        );
      }
    }

    JClosedWorld closedWorld = compiler.backendClosedWorldForTesting!;
    JsToElementMap elementMap = closedWorld.elementMap;
    final node = elementMap.getMemberDefinition(member).node as ir.Member;
    Id id = computeMemberId(node);
    ir.TreeNode nodeWithOffset = computeTreeNodeWithOffset(node)!;
    actualMap[id] = ActualData<Features>(
      id,
      features,
      nodeWithOffset.location!.file,
      nodeWithOffset.fileOffset,
      member,
    );
  }

  @override
  DataInterpreter<Features> get dataValidator =>
      const JsonFeaturesDataInterpreter(wildcard: wildcard);
}

/// Feature interpreter for Features with Json values.
///
/// The data annotation reader conserves whitespace visually while ignoring
/// them during comparison.
class JsonFeaturesDataInterpreter implements DataInterpreter<Features> {
  final String? wildcard;
  final JsonEncoder encoder = const JsonEncoder();

  const JsonFeaturesDataInterpreter({this.wildcard});

  @override
  String? isAsExpected(Features actualFeatures, String? expectedData) {
    if (wildcard != null && expectedData == wildcard) {
      return null;
    } else if (expectedData == '') {
      return actualFeatures.isNotEmpty ? "Expected empty data." : null;
    } else {
      List<String> errorsFound = [];
      Features expectedFeatures = Features.fromText(expectedData);
      Set<String> validatedFeatures = Set<String>();
      expectedFeatures.forEach((String key, Object expectedValue) {
        validatedFeatures.add(key);
        Object? actualValue = actualFeatures[key];
        if (!actualFeatures.containsKey(key)) {
          errorsFound.add('No data found for $key');
        } else if (expectedValue == '') {
          if (actualValue != '') {
            errorsFound.add('Non-empty data found for $key');
          }
        } else if (wildcard != null && expectedValue == wildcard) {
          return;
        } else if (expectedValue is List) {
          if (actualValue is List) {
            List actualList = actualValue.toList();
            for (String expectedObject in expectedValue) {
              String expectedText = jsonEncode(
                jsonDecode(expectedObject),
                indent: false,
              );
              bool matchFound = false;
              if (wildcard != null && expectedText.endsWith(wildcard!)) {
                // Wildcard matcher.
                String prefix = expectedText.substring(
                  0,
                  expectedText.indexOf(wildcard!),
                );
                List matches = [];
                for (String actualObject in actualList) {
                  final formattedActualObject = jsonEncode(
                    jsonDecode(actualObject),
                    indent: false,
                  );
                  if (formattedActualObject.startsWith(prefix)) {
                    matches.add(actualObject);
                    matchFound = true;
                  }
                }
                for (Object match in matches) {
                  actualList.remove(match);
                }
              } else {
                for (String actualObject in actualList) {
                  final formattedActualObject = jsonEncode(
                    jsonDecode(actualObject),
                    indent: false,
                  );
                  if (expectedText == formattedActualObject) {
                    actualList.remove(actualObject);
                    matchFound = true;
                    break;
                  }
                }
              }
              if (!matchFound) {
                errorsFound.add("No match found for $key=[$expectedText]");
              }
            }
            if (actualList.isNotEmpty) {
              errorsFound.add(
                "Extra data found $key=[${actualList.join(',')}]",
              );
            }
          } else {
            errorsFound.add(
              "List data expected for $key: "
              "expected '$expectedValue', found '${actualValue}'",
            );
          }
        } else if (expectedValue != actualValue) {
          errorsFound.add(
            "Mismatch for $key: expected '$expectedValue', "
            "found '${actualValue}'",
          );
        }
      });
      actualFeatures.forEach((String key, Object value) {
        if (!validatedFeatures.contains(key)) {
          if (value == '') {
            errorsFound.add("Extra data found '$key'");
          } else {
            errorsFound.add("Extra data found $key=$value");
          }
        }
      });
      return errorsFound.isNotEmpty ? errorsFound.join('\n ') : null;
    }
  }

  @override
  String getText(Features actualData, [String? indentation]) {
    return actualData.getText(indentation);
  }

  @override
  bool isEmpty(Features? actualData) {
    return actualData == null || actualData.isEmpty;
  }
}
