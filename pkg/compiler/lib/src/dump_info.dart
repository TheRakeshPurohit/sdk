// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library;

import 'dart:convert' show JsonEncoder, JsonDecoder;

import 'package:compiler/src/js_model/js_strategy.dart';
import 'package:dart2js_info/binary_serialization.dart' as dump_info;
import 'package:dart2js_info/info.dart';
import 'package:dart2js_info/json_info_codec.dart';
import 'package:kernel/ast.dart' as ir;
import 'package:kernel/core_types.dart' as ir;

import '../compiler_api.dart' as api;
import 'common.dart';
import 'common/codegen.dart';
import 'common/elements.dart' show JElementEnvironment;
import 'common/names.dart';
import 'common/ram_usage.dart';
import 'common/tasks.dart' show CompilerTask, Measurer;
import 'constants/values.dart' show ConstantValue;
import 'deferred_load/output_unit.dart' show OutputUnit, deferredPartFileName;
import 'elements/entities.dart';
import 'elements/entity_utils.dart' as entity_utils;
import 'elements/names.dart';
import 'inferrer/abstract_value_domain.dart';
import 'inferrer/types.dart'
    show GlobalTypeInferenceMemberResult, GlobalTypeInferenceResults;
import 'js/js.dart' as js_ast;
import 'js_backend/field_analysis.dart';
import 'js_emitter/code_emitter_task.dart';
import 'js_model/elements.dart';
import 'js_model/js_world.dart' show JClosedWorld;
import 'options.dart';
import 'serialization/serialization.dart';
import 'universe/world_impact.dart' show WorldImpact;

/// Collects data used for the dump info task.
///
/// This registry collects data while JS is being emitted and stores it to be
/// processed by and used in the dump info stage. Since it holds references to
/// AST nodes it should be cleared with [DumpInfoJsAstRegistry.close] as soon
/// as the necessary data for it is extracted.
///
/// See [DumpInfoProgramData.fromEmitterResults] for how this data is processed.
class DumpInfoJsAstRegistry {
  final bool _disabled;
  final CompilerOptions options;

  final Map<Entity, List<CodeSpan>> _entityCode = {};
  final Map<ConstantValue, CodeSpan> _constantCode = {};

  // Contains impacts that will be used immediately (if codegen is being run
  // with this compiler execution) or serialized with partial dump info data.
  // Impacts are not yet transformed by CodegenImpactTransformer.
  final Map<MemberEntity, CodegenImpact> _impactRegistry = {};

  // Contains members whose impacts should be deserialized from codegen results
  // on subsequent dump info execution. Empty when dump info is being executed
  // immediately without serialization.
  final Set<MemberEntity> _serializedImpactMembers = {};

  // Temporary structures used to collect data during the visit process with a
  // low memory footprint.
  final Map<js_ast.Node, ConstantValue> _constantRegistry = {};
  final Map<js_ast.Node, List<Entity>> _entityRegistry = {};
  final List<CodeSpan> _stack = [];
  DataSinkWriter? _dataSinkWriter;
  int _impactCount = 0;

  DumpInfoJsAstRegistry(this.options)
    : _disabled =
          !options.stage.emitsDumpInfo &&
          !options.stage.shouldWriteDumpInfoData;

  bool get useBinaryFormat => options.dumpInfoFormat == DumpInfoFormat.binary;

  void registerEntityAst(Entity? entity, js_ast.Node code) {
    if (_disabled) return;
    if (entity != null) {
      (_entityRegistry[code] ??= []).add(entity);
    }
  }

  void registerConstantAst(ConstantValue constant, js_ast.Node code) {
    if (_disabled) return;
    assert(
      !_constantRegistry.containsValue(constant) ||
          _constantRegistry[code] == constant,
    );
    _constantRegistry[code] = constant;
  }

  void registerDataSinkWriter(DataSinkWriter dataSinkWriter) {
    _dataSinkWriter = dataSinkWriter..startDeferrable();
  }

  void registerImpact(
    MemberEntity member,
    CodegenImpact impact, {
    required bool isGenerated,
  }) {
    if (_disabled) return;
    if (isGenerated || options.stage.emitsDumpInfo) {
      if (options.stage.shouldWriteDumpInfoData) {
        // Serialize immediately so that we don't have to hold a reference to
        // every impact until the end of the phase.
        _dataSinkWriter!.writeMember(member);
        impact.writeToDataSink(_dataSinkWriter!);
        _impactCount++;
      } else {
        _impactRegistry[member] = impact;
      }
    } else {
      _serializedImpactMembers.add(member);
    }
  }

  bool get shouldEmitText => !useBinaryFormat;

  void enterNode(js_ast.Node node, int start) {
    if (_disabled) return;
    if (!_entityRegistry.containsKey(node) &&
        !_constantRegistry.containsKey(node)) {
      return;
    }
    final data = useBinaryFormat ? CodeSpan() : _CodeData();
    data.start = start;
    _stack.add(data);
  }

  void emit(String string) {
    if (shouldEmitText) {
      // Note: historically we emitted the full body of classes and methods, so
      // instance methods ended up emitted twice.  Once we use a different
      // encoding of dump info, we also plan to remove this duplication.
      for (var f in _stack) {
        (f as _CodeData)._text.write(string);
      }
    }
  }

  void exitNode(js_ast.Node node, int start, int end, int? closing) {
    if (_disabled) return;
    final entities = _entityRegistry.remove(node);
    final constant = _constantRegistry.remove(node);
    if (entities == null && constant == null) return;
    final data = _stack.removeLast();
    data.end = end;
    if (entities != null) {
      for (var e in entities) {
        (_entityCode[e] ??= []).add(data);
      }
    }
    if (constant != null) {
      _constantCode[constant] = data;
    }
  }

  void close() {
    assert(_stack.isEmpty);
    assert(_entityRegistry.isEmpty);
    assert(_constantRegistry.isEmpty);
    _dataSinkWriter?.endDeferrable();
    _entityCode.clear();
    _constantCode.clear();
    _serializedImpactMembers.clear();
    _impactRegistry.clear();
  }
}

/// Only includes entity types stored in [DumpInfoProgramData.entityCode].
enum _EntityType { library, cls, member }

class DumpInfoProgramData {
  final int programSize;
  final Map<OutputUnit, int> outputUnitSizes;
  /* Map<String, Map<String, String?|List<String>>> */
  final Map<String, Map<String, dynamic>> fragmentDeferredMap;
  final Iterable<ClassEntity> neededClasses;
  final Iterable<ClassEntity> neededClassTypes;
  final Map<Entity, List<CodeSpan>> entityCode;
  final Map<Entity, int> entityCodeSize;
  final Map<ConstantValue, CodeSpan> constantCode;

  /// Contains members that are live and whose impacts are serialized in the
  /// codegen results. This will be empty if dump info is being run without
  /// serialization.
  final Set<MemberEntity> serializedImpactMembers;

  /// If dump info is being without serialziation, this will contain impacts for
  /// all live members. Otherwise only contains impacts for members that were
  /// created during the emitter phase and whose impacts are therefore not
  /// included in codegen results.
  final Map<MemberEntity, CodegenImpact> registeredImpacts;

  DumpInfoProgramData._(
    this.programSize,
    this.outputUnitSizes,
    this.fragmentDeferredMap,
    this.entityCode,
    this.entityCodeSize,
    this.constantCode,
    this.serializedImpactMembers,
    this.registeredImpacts, {
    required this.neededClasses,
    required this.neededClassTypes,
  });

  factory DumpInfoProgramData.fromEmitterResults(
    CodeEmitterTask emitterTask,
    DumpInfoJsAstRegistry dumpInfoRegistry,
    int programSize,
  ) {
    final outputUnitSizes = emitterTask.emitter.generatedSizes;

    var fragmentsToLoad = emitterTask.emitter.finalizedFragmentsToLoad;
    var fragmentMerger = emitterTask.emitter.fragmentMerger;
    final fragmentDeferredMap = fragmentMerger.computeDeferredMap(
      fragmentsToLoad,
    );
    final neededClasses = emitterTask.neededClasses;
    final neededClassTypes = emitterTask.neededClassTypes;
    final entityCode = Map.of(dumpInfoRegistry._entityCode);
    final entityCodeSize = <Entity, int>{};
    entityCode.forEach((entity, spans) {
      entityCodeSize[entity] = spans.fold(
        0,
        (size, span) => size + (span.end! - span.start!),
      );
    });
    final constantCode = Map.of(dumpInfoRegistry._constantCode);
    return DumpInfoProgramData._(
      programSize,
      outputUnitSizes,
      fragmentDeferredMap,
      entityCode,
      entityCodeSize,
      constantCode,
      Set.from(dumpInfoRegistry._serializedImpactMembers),
      Map.from(dumpInfoRegistry._impactRegistry),
      neededClasses: neededClasses,
      neededClassTypes: neededClassTypes,
    );
  }

  static Entity _readEntity(DataSourceReader source) {
    final entityType = source.readEnum(_EntityType.values);
    switch (entityType) {
      case _EntityType.library:
        return source.readLibrary();
      case _EntityType.cls:
        return source.readClass();
      case _EntityType.member:
        return source.readMember();
    }
  }

  static void _writeEntity(DataSinkWriter sink, Entity entity) {
    if (entity is LibraryEntity) {
      sink.writeEnum(_EntityType.library);
      sink.writeLibrary(entity);
    } else if (entity is ClassEntity) {
      sink.writeEnum(_EntityType.cls);
      sink.writeClass(entity);
    } else if (entity is MemberEntity) {
      sink.writeEnum(_EntityType.member);
      sink.writeMember(entity);
    } else {
      throw UnsupportedError('Unsupported dump info entity: $entity');
    }
  }

  static CodeSpan _readCodeSpan(DataSourceReader source, bool includeText) {
    final start = source.readInt();
    final end = source.readInt();
    final savedText = source.readStringOrNull();
    final text = includeText ? savedText : null;
    return CodeSpan(start: start, end: end, text: text);
  }

  static void _writeCodeSpan(DataSinkWriter sink, CodeSpan codeSpan) {
    sink.writeInt(codeSpan.start!);
    sink.writeInt(codeSpan.end!);
    sink.writeStringOrNull(codeSpan.text);
  }

  factory DumpInfoProgramData.readFromDataSource(
    DataSourceReader source, {
    required bool includeCodeText,
  }) {
    late int impactCount;
    final registeredImpactsDeferrable = source.readDeferrable((
      DataSourceReader source,
    ) {
      final impacts = <MemberEntity, CodegenImpact>{};
      for (var i = 0; i < impactCount; i++) {
        final member = source.readMember();
        final impact = CodegenImpact.readFromDataSource(source);
        impacts[member] = impact;
      }
      return impacts;
    });
    impactCount = source.readInt();
    final programSize = source.readInt();
    final outputUnitSizesLength = source.readInt();
    final outputUnitSizes = <OutputUnit, int>{};
    for (int i = 0; i < outputUnitSizesLength; i++) {
      final outputUnit = source.readOutputUnitReference();
      final size = source.readInt();
      outputUnitSizes[outputUnit] = size;
    }
    final fragmentDeferredMap = source.readStringMap(
      () => source.readStringMap(
        () => JsonDecoder().convert(source.readString()),
      ),
    );
    final neededClasses = source.readList(source.readClass);
    final neededClassTypes = source.readList(source.readClass);
    final entityCodeLength = source.readInt();
    final entityCode = <Entity, List<CodeSpan>>{};
    final entityCodeSize = <Entity, int>{};
    for (int i = 0; i < entityCodeLength; i++) {
      final entity = _readEntity(source);
      final size = source.readInt();
      final codeSpans = source.readList(
        () => _readCodeSpan(source, includeCodeText),
      );
      entityCode[entity] = codeSpans;
      entityCodeSize[entity] = size;
    }
    final constantCode = <ConstantValue, CodeSpan>{};
    final costantCodeLength = source.readInt();
    for (int i = 0; i < costantCodeLength; i++) {
      final constant = source.readConstant();
      final codeSpan = _readCodeSpan(source, includeCodeText);
      constantCode[constant] = codeSpan;
    }
    final serializedImpactMembers = source.readMembers().toSet();
    return DumpInfoProgramData._(
      programSize,
      outputUnitSizes,
      fragmentDeferredMap,
      entityCode,
      entityCodeSize,
      constantCode,
      serializedImpactMembers,
      registeredImpactsDeferrable.loaded(),
      neededClasses: neededClasses,
      neededClassTypes: neededClassTypes,
    );
  }

  void writeToDataSink(DataSinkWriter sink, DumpInfoJsAstRegistry registry) {
    sink.writeInt(registry._impactCount);
    sink.writeInt(programSize);
    sink.writeInt(outputUnitSizes.length);
    outputUnitSizes.forEach((outputUnit, size) {
      sink.writeOutputUnitReference(outputUnit);
      sink.writeInt(size);
    });
    sink.writeStringMap(fragmentDeferredMap, (Map<String, dynamic> innerMap) {
      sink.writeStringMap(
        innerMap,
        (value) => sink.writeString(JsonEncoder().convert(value)),
      );
    });
    sink.writeList(neededClasses, sink.writeClass);
    sink.writeList(neededClassTypes, sink.writeClass);
    assert(entityCode.length == entityCodeSize.length);
    sink.writeInt(entityCode.length);
    entityCode.forEach((entity, codeSpans) {
      final size = entityCodeSize[entity]!;
      _writeEntity(sink, entity);
      sink.writeInt(size);
      sink.writeList(
        codeSpans,
        (CodeSpan codeSpan) => _writeCodeSpan(sink, codeSpan),
      );
    });
    sink.writeInt(constantCode.length);
    constantCode.forEach((constant, codeSpan) {
      sink.writeConstant(constant);
      _writeCodeSpan(sink, codeSpan);
    });
    sink.writeMembers(serializedImpactMembers);
  }
}

class ElementInfoCollector {
  final CompilerOptions options;
  final JClosedWorld closedWorld;
  final GlobalTypeInferenceResults _globalInferenceResults;
  final DumpInfoTask dumpInfoTask;

  JElementEnvironment get environment => closedWorld.elementEnvironment;

  final state = DumpInfoStateData();

  ElementInfoCollector(
    this.options,
    this.dumpInfoTask,
    this.closedWorld,
    this._globalInferenceResults,
  );

  void run() {
    dumpInfoTask._dumpInfoData.constantCode.forEach((constant, span) {
      // TODO(sigmund): add dependencies on other constants
      var info = ConstantInfo(
        size: span.end! - span.start!,
        code: [span],
        outputUnit: _unitInfoForConstant(constant),
      );
      state.constantToInfo[constant] = info;
      state.info.constants.add(info);
    });
    environment.libraries.forEach(visitLibrary);
  }

  /// Whether to emit information about [entity].
  ///
  /// By default we emit information for any entity that contributes to the
  /// output size. Either because it is a function being emitted or inlined,
  /// or because it is an entity that holds dependencies to other entities.
  bool shouldKeep(Entity entity) {
    return dumpInfoTask.impacts.containsKey(entity) ||
        dumpInfoTask.inlineCount.containsKey(entity);
  }

  LibraryInfo? visitLibrary(LibraryEntity lib) {
    String libname = environment.getLibraryName(lib);
    if (libname.isEmpty) {
      libname = '<unnamed>';
    }
    int size = dumpInfoTask.sizeOf(lib);
    LibraryInfo info = LibraryInfo(libname, lib.canonicalUri, null, size);
    state.entityToInfo[lib] = info;

    environment.forEachLibraryMember(lib, (MemberEntity member) {
      if (member.isFunction || member.isGetter || member.isSetter) {
        final functionInfo = visitFunction(member as FunctionEntity);
        if (functionInfo != null) {
          info.topLevelFunctions.add(functionInfo);
          functionInfo.parent = info;
        }
      } else if (member is FieldEntity) {
        final fieldInfo = visitField(member);
        if (fieldInfo != null) {
          info.topLevelVariables.add(fieldInfo);
          fieldInfo.parent = info;
        }
      }
    });

    environment.forEachClass(lib, (ClassEntity clazz) {
      final classTypeInfo = visitClassType(clazz);
      if (classTypeInfo != null) {
        info.classTypes.add(classTypeInfo);
        classTypeInfo.parent = info;
      }

      final classInfo = visitClass(clazz);
      if (classInfo != null) {
        info.classes.add(classInfo);
        classInfo.parent = info;
      }
    });

    if (info.isEmpty && !shouldKeep(lib)) return null;
    state.info.libraries.add(info);
    return info;
  }

  GlobalTypeInferenceMemberResult _resultOfMember(MemberEntity e) =>
      _globalInferenceResults.resultOfMember(e);

  AbstractValue _resultOfParameter(Local e, MemberEntity? member) =>
      _globalInferenceResults.resultOfParameter(e, member);

  FieldInfo? visitField(FieldEntity field) {
    AbstractValue inferredType = _resultOfMember(field).type;
    // If a field has an empty inferred type it is never used.
    if (closedWorld.abstractValueDomain
        .isEmpty(inferredType)
        .isDefinitelyTrue) {
      return null;
    }

    int size = dumpInfoTask.sizeOf(field);
    List<CodeSpan> code = dumpInfoTask.codeOf(field);

    // TODO(het): Why doesn't `size` account for the code size already?
    size += code.length;

    FieldInfo info = FieldInfo(
      name: field.name!,
      type: '${environment.getFieldType(field)}',
      inferredType: '$inferredType',
      code: code,
      outputUnit: _unitInfoForMember(field),
      isConst: field.isConst,
    );
    state.entityToInfo[field] = info;
    final fieldData = closedWorld.fieldAnalysis.getFieldData(field as JField);
    if (fieldData.initialValue != null) {
      info.initializer =
          state.constantToInfo[fieldData.initialValue] as ConstantInfo?;
    }

    if (options.experimentCallInstrumentation) {
      // We use field.hashCode because it is globally unique and it is
      // available while we are doing codegen.
      info.coverageId = '${field.hashCode}';
    }

    int closureSize = _addClosureInfo(info, field);
    info.size = size + closureSize;

    state.info.fields.add(info);
    return info;
  }

  ClassTypeInfo? visitClassType(ClassEntity clazz) {
    // Omit class type if it is not needed.
    ClassTypeInfo classTypeInfo = ClassTypeInfo(
      name: clazz.name,
      outputUnit: _unitInfoForClassType(clazz),
    );

    // TODO(joshualitt): Get accurate size information for class types.
    classTypeInfo.size = 0;

    bool isNeeded = dumpInfoTask._dumpInfoData.neededClassTypes.contains(clazz);
    if (!isNeeded) {
      return null;
    }

    state.info.classTypes.add(classTypeInfo);
    return classTypeInfo;
  }

  /// Returns all immediately extended, implemented, or mixed-in types of
  /// [clazz].
  List<ClassEntity> getImmediateSupers(ClassEntity clazz) {
    final superclass = environment.getSuperClass(
      clazz,
      skipUnnamedMixinApplications: true,
    );
    // Ignore 'Object' to reduce overhead.
    return [
      if (superclass != null &&
          superclass != closedWorld.commonElements.objectClass)
        superclass,
      ...closedWorld.dartTypes.getInterfaces(clazz).map((i) => i.element),
    ];
  }

  ClassInfo? visitClass(ClassEntity clazz) {
    // True if [info] can be safely removed from the output.
    bool filterClassInfo(ClassInfo info) =>
        !dumpInfoTask._dumpInfoData.neededClasses.contains(clazz) &&
        info.fields.isEmpty &&
        info.functions.isEmpty;

    ClassInfo? classInfo = state.entityToInfo[clazz] as ClassInfo?;
    if (classInfo != null) {
      return filterClassInfo(classInfo) ? null : classInfo;
    }
    final supers = <ClassInfo>[];
    getImmediateSupers(clazz).forEach((superInterface) {
      final superclass = environment.lookupClass(
        superInterface.library,
        superInterface.name,
      );
      if (superclass == null) return;
      final classInfo = visitClass(superclass);
      if (classInfo == null) return;
      supers.add(classInfo);
    });
    classInfo = ClassInfo(
      name: clazz.name,
      isAbstract: clazz.isAbstract,
      supers: supers,
      outputUnit: _unitInfoForClass(clazz),
    );
    state.entityToInfo[clazz] = classInfo;

    int size = dumpInfoTask.sizeOf(clazz);
    environment.forEachLocalClassMember(clazz, (member) {
      if (member.isFunction || member.isGetter || member.isSetter) {
        final functionInfo = visitFunction(member as FunctionEntity);
        if (functionInfo != null) {
          classInfo!.functions.add(functionInfo);
          functionInfo.parent = classInfo;
          for (var closureInfo in functionInfo.closures) {
            size += closureInfo.size;
          }
        }
      } else if (member is FieldEntity) {
        final fieldInfo = visitField(member);
        if (fieldInfo != null) {
          classInfo!.fields.add(fieldInfo);
          fieldInfo.parent = classInfo;
          for (var closureInfo in fieldInfo.closures) {
            size += closureInfo.size;
          }
        }
      } else {
        throw StateError('Class member not a function or field');
      }
    });
    environment.forEachConstructor(clazz, (constructor) {
      final functionInfo = visitFunction(constructor);
      if (functionInfo != null) {
        classInfo!.functions.add(functionInfo);
        functionInfo.parent = classInfo;
        for (var closureInfo in functionInfo.closures) {
          size += closureInfo.size;
        }
      }
    });

    classInfo.size = size;

    if (filterClassInfo(classInfo)) {
      return null;
    }

    state.info.classes.add(classInfo);
    return classInfo;
  }

  ClosureInfo? visitClosureClass(ClassEntity element) {
    ClosureInfo closureInfo = ClosureInfo(
      name: element.name,
      outputUnit: _unitInfoForClass(element),
      size: dumpInfoTask.sizeOf(element),
    );
    state.entityToInfo[element] = closureInfo;

    final callMethod = closedWorld.elementEnvironment.lookupClassMember(
      element,
      Names.call,
    );

    final functionInfo = visitFunction(callMethod as FunctionEntity);
    if (functionInfo == null) return null;
    closureInfo.function = functionInfo;
    functionInfo.parent = closureInfo;

    state.info.closures.add(closureInfo);
    return closureInfo;
  }

  FunctionInfo? visitFunction(FunctionEntity function) {
    int size = dumpInfoTask.sizeOf(function);
    // TODO(sigmund): consider adding a small info to represent unreachable
    // code here.
    if (size == 0 && !shouldKeep(function)) return null;

    // TODO(het): use 'toString' instead of 'text'? It will add '=' for setters
    String name = function.memberName.text;
    int? kind;
    if (function.isStatic || function.isTopLevel) {
      kind = FunctionInfo.TOP_LEVEL_FUNCTION_KIND;
    } else if (function.enclosingClass != null) {
      kind = FunctionInfo.METHOD_FUNCTION_KIND;
    }

    if (function is ConstructorEntity) {
      name = name == ""
          ? function.enclosingClass.name
          : "${function.enclosingClass.name}.${function.name}";
      kind = FunctionInfo.CONSTRUCTOR_FUNCTION_KIND;
    }

    FunctionModifiers modifiers = FunctionModifiers(
      isStatic: function.isStatic,
      isConst: function.isConst,
      isFactory: function is ConstructorEntity
          ? function.isFactoryConstructor
          : false,
      isExternal: function.isExternal,
    );
    List<CodeSpan> code = dumpInfoTask.codeOf(function);

    List<ParameterInfo> parameters = <ParameterInfo>[];
    List<String> inferredParameterTypes = <String>[];

    closedWorld.elementEnvironment.forEachParameterAsLocal(
      _globalInferenceResults.globalLocalsMap,
      function,
      (parameter) {
        inferredParameterTypes.add(
          '${_resultOfParameter(parameter, function)}',
        );
      },
    );
    int parameterIndex = 0;
    closedWorld.elementEnvironment.forEachParameter(function, (type, name, _) {
      // Synthesized parameters have no name. This can happen on parameters of
      // setters derived from lowering late fields.
      parameters.add(
        ParameterInfo(
          name ?? '#t$parameterIndex',
          inferredParameterTypes[parameterIndex++],
          '$type',
        ),
      );
    });

    final functionType = environment.getFunctionType(function);
    String returnType = '${functionType.returnType}';

    String inferredReturnType = '${_resultOfMember(function).returnType}';
    String sideEffects =
        '${_globalInferenceResults.inferredData.getSideEffectsOfElement(function)}';

    int inlinedCount = dumpInfoTask.inlineCount[function] ?? 0;

    FunctionInfo info = FunctionInfo(
      name: name,
      functionKind: kind!,
      modifiers: modifiers,
      returnType: returnType,
      inferredReturnType: inferredReturnType,
      parameters: parameters,
      sideEffects: sideEffects,
      inlinedCount: inlinedCount,
      code: code,
      type: functionType.toString(),
      outputUnit: _unitInfoForMember(function),
    );
    state.entityToInfo[function] = info;

    int closureSize = _addClosureInfo(info, function);
    size += closureSize;

    if (options.experimentCallInstrumentation) {
      // We use function.hashCode because it is globally unique and it is
      // available while we are doing codegen.
      info.coverageId = '${function.hashCode}';
    }

    info.size = size;

    state.info.functions.add(info);
    return info;
  }

  /// Adds closure information to [info], using all nested closures in [member].
  ///
  /// Returns the total size of the nested closures, to add to the info size.
  int _addClosureInfo(Info info, MemberEntity member) {
    assert(info is FunctionInfo || info is FieldInfo);
    int size = 0;
    List<ClosureInfo> nestedClosures = <ClosureInfo>[];
    environment.forEachNestedClosure(member, (closure) {
      final closureInfo = visitClosureClass(closure.enclosingClass!);
      if (closureInfo != null) {
        closureInfo.parent = info;
        nestedClosures.add(closureInfo);
        size += closureInfo.size;
      }
    });
    if (info is FunctionInfo) info.closures = nestedClosures;
    if (info is FieldInfo) info.closures = nestedClosures;

    return size;
  }

  OutputUnitInfo _infoFromOutputUnit(OutputUnit outputUnit) {
    return state.outputToInfo.putIfAbsent(outputUnit, () {
      // Dump-info currently only works with the full emitter. If another
      // emitter is used it will fail here.
      final filename = outputUnit.isMainOutput
          ? (options.outputUri?.pathSegments.last ?? 'out')
          : deferredPartFileName(options, outputUnit.name);
      OutputUnitInfo info = OutputUnitInfo(
        filename,
        outputUnit.name,
        dumpInfoTask._dumpInfoData.outputUnitSizes[outputUnit]!,
      );
      info.imports.addAll(
        closedWorld.outputUnitData.getImportNames(outputUnit),
      );
      state.info.outputUnits.add(info);
      return info;
    });
  }

  OutputUnitInfo _unitInfoForMember(MemberEntity entity) {
    return _infoFromOutputUnit(
      closedWorld.outputUnitData.outputUnitForMember(entity),
    );
  }

  OutputUnitInfo _unitInfoForClass(ClassEntity entity) {
    return _infoFromOutputUnit(
      closedWorld.outputUnitData.outputUnitForClass(entity, allowNull: true),
    );
  }

  OutputUnitInfo _unitInfoForClassType(ClassEntity entity) {
    return _infoFromOutputUnit(
      closedWorld.outputUnitData.outputUnitForClassType(
        entity,
        allowNull: true,
      ),
    );
  }

  OutputUnitInfo _unitInfoForConstant(ConstantValue constant) {
    final outputUnit = closedWorld.outputUnitData.outputUnitForConstant(
      constant,
    );
    return _infoFromOutputUnit(outputUnit);
  }
}

class KernelInfoCollector {
  final ir.Component component;
  final CompilerOptions options;
  final JClosedWorld closedWorld;
  final DumpInfoTask dumpInfoTask;
  final state = DumpInfoStateData();
  final ir.CoreTypes coreTypes;

  JElementEnvironment get environment => closedWorld.elementEnvironment;

  KernelInfoCollector(
    this.component,
    this.options,
    this.dumpInfoTask,
    this.closedWorld,
  ) : coreTypes = ir.CoreTypes(component);

  void run() {
    // TODO(markzipan): Add CFE constants to `state.info.constants`.
    component.libraries.forEach(visitLibrary);
  }

  LibraryInfo? visitLibrary(ir.Library lib) {
    final libEntity = environment.lookupLibrary(lib.importUri);
    if (libEntity == null) return null;

    String? libname = lib.name;
    if (libname == null || libname.isEmpty) {
      libname = '${lib.importUri}';
    }
    LibraryInfo info = LibraryInfo(libname, lib.importUri, null, 0);

    for (var member in lib.members) {
      final memberEntity = environment.lookupLibraryMember(
        libEntity,
        member.name.text,
      );
      if (memberEntity == null) continue;
      final function = member.function;
      if (function != null) {
        final functionInfo = visitFunction(
          function,
          functionEntity: memberEntity as FunctionEntity,
        );
        if (functionInfo != null) {
          info.topLevelFunctions.add(functionInfo);
          functionInfo.parent = info;
        }
      } else {
        final fieldInfo = visitField(
          member as ir.Field,
          fieldEntity: memberEntity as FieldEntity,
        );
        if (fieldInfo != null) {
          info.topLevelVariables.add(fieldInfo);
          fieldInfo.parent = info;
        }
      }
    }

    for (var clazz in lib.classes) {
      final classEntity = environment.lookupClass(libEntity, clazz.name);
      if (classEntity == null) continue;

      final classTypeInfo = visitClassType(clazz);
      if (classTypeInfo != null) {
        info.classTypes.add(classTypeInfo);
        classTypeInfo.parent = info;
      }

      final classInfo = visitClass(clazz, classEntity: classEntity);
      if (classInfo != null) {
        info.classes.add(classInfo);
        classInfo.parent = info;
      }
    }

    state.info.libraries.add(info);
    return info;
  }

  FieldInfo? visitField(ir.Field field, {required FieldEntity fieldEntity}) {
    FieldInfo info = FieldInfo.fromKernel(
      name: field.name.text,
      type: field.type.toStringInternal(),
      isConst: field.isConst,
    );

    if (options.experimentCallInstrumentation) {
      // We use field.hashCode because it is globally unique and it is
      // available while we are doing codegen.
      info.coverageId = '${field.hashCode}';
    }

    _addClosureInfo(
      info,
      field,
      libraryEntity: fieldEntity.library,
      memberEntity: fieldEntity,
    );

    state.info.fields.add(info);
    return info;
  }

  ClassTypeInfo? visitClassType(ir.Class clazz) {
    ClassTypeInfo classTypeInfo = ClassTypeInfo(name: clazz.name);
    state.info.classTypes.add(classTypeInfo);
    return classTypeInfo;
  }

  ClassInfo? visitClass(ir.Class clazz, {required ClassEntity classEntity}) {
    if (state.entityToInfo[classEntity] != null) {
      return state.entityToInfo[classEntity] as ClassInfo?;
    }

    final supers = <ClassInfo>[];
    for (var supertype in clazz.supers) {
      final superclass = supertype.classNode;
      // Ignore 'Object' to reduce overhead.
      if (superclass == coreTypes.objectClass) {
        continue;
      }
      final superclassLibrary = environment.lookupLibrary(
        superclass.enclosingLibrary.importUri,
      )!;
      final superclassEntity = environment.lookupClass(
        superclassLibrary,
        superclass.name,
      );
      if (superclassEntity == null) continue;
      final classInfo = visitClass(superclass, classEntity: superclassEntity);
      if (classInfo != null) supers.add(classInfo);
    }

    ClassInfo classInfo = ClassInfo.fromKernel(
      name: clazz.name,
      isAbstract: clazz.isAbstract,
      supers: supers,
    );
    state.entityToInfo[classEntity] = classInfo;

    for (var member in clazz.members) {
      final isSetter = member is ir.Procedure && member.isSetter;
      // clazz.members includes constructors
      final name = Name(
        member.name.text,
        member.name.isPrivate ? member.name.library!.importUri : null,
        isSetter: isSetter,
      );
      final memberEntity =
          environment.lookupLocalClassMember(classEntity, name) ??
          environment.lookupConstructor(classEntity, member.name.text);
      if (memberEntity == null) continue;

      final function = member.function;
      if (function != null) {
        // Multiple kernel members can map to single JWorld member
        // (e.g., when one of a getter/field pair are tree-shaken),
        // so avoid duplicating the downstream info object.
        if (memberEntity is FunctionEntity) {
          final functionInfo = visitFunction(
            function,
            functionEntity: memberEntity,
          );
          if (functionInfo != null) {
            classInfo.functions.add(functionInfo);
            functionInfo.parent = classInfo;
          }
        }
      } else {
        final fieldInfo = visitField(
          member as ir.Field,
          fieldEntity: memberEntity as FieldEntity,
        );
        if (fieldInfo != null) {
          classInfo.fields.add(fieldInfo);
          fieldInfo.parent = classInfo;
        }
      }
    }

    state.info.classes.add(classInfo);
    return classInfo;
  }

  FunctionInfo? visitFunction(
    ir.FunctionNode function, {
    required FunctionEntity functionEntity,
    LocalFunctionInfo? localFunctionInfo,
  }) {
    final parent = function.parent;
    bool isClosureCallMethod = parent is ir.LocalFunction;
    String name = isClosureCallMethod ? 'call' : parent!.toStringInternal();
    bool isConstructor = parent is ir.Constructor;
    bool isFactory = parent is ir.Procedure && parent.isFactory;
    // Kernel `isStatic` refers to static members, constructors, and top-level
    // members.
    bool isTopLevel =
        (parent is ir.Field && parent.isStatic) ||
        (parent is ir.Procedure && parent.isStatic) ||
        (parent is ir.Member && parent.enclosingClass == null);
    bool isStaticMember =
        ((parent is ir.Field && parent.isStatic) ||
            (parent is ir.Procedure && parent.isStatic)) &&
        (parent is ir.Member && parent.enclosingClass != null) &&
        !isConstructor &&
        !isFactory;
    bool isConst = parent is ir.Member && parent.isConst;
    bool isExternal = parent is ir.Member && parent.isExternal;
    bool isMethod =
        isClosureCallMethod ||
        (parent is ir.Member && parent.enclosingClass != null);
    bool isGetter = parent is ir.Procedure && parent.isGetter;
    bool isSetter = parent is ir.Procedure && parent.isSetter;
    late int kind;
    if (isStaticMember || isTopLevel) {
      kind = FunctionInfo.TOP_LEVEL_FUNCTION_KIND;
    } else if (isMethod) {
      kind = FunctionInfo.METHOD_FUNCTION_KIND;
    }
    if (isConstructor || isFactory) {
      kind = FunctionInfo.CONSTRUCTOR_FUNCTION_KIND;
      String functionName = function.toStringInternal();
      name = functionName.isEmpty ? name : '$name$functionName';
    } else {
      if (parent!.parent is ir.Class && name.contains('.')) {
        name = name.split('.')[1];
      }
    }
    if (name.endsWith('.')) name = name.substring(0, name.length - 1);

    FunctionModifiers modifiers = FunctionModifiers(
      isStatic: isStaticMember,
      isConst: isConst,
      isFactory: isFactory,
      isExternal: isExternal,
      isGetter: isGetter,
      isSetter: isSetter,
    );

    // TODO(markzipan): Determine if it's safe to default to nonNullable here.
    final nullability = parent is ir.Member
        ? parent.enclosingLibrary.nonNullable
        : ir.Nullability.nonNullable;
    final functionType = function.computeFunctionType(nullability);

    FunctionInfo info = FunctionInfo.fromKernel(
      name: name,
      functionKind: kind,
      modifiers: modifiers,
      returnType: function.returnType.toStringInternal(),
      type: functionType.toStringInternal(),
    );

    final functionParent = function.parent;
    if (functionParent is ir.Member) {
      _addClosureInfo(
        info,
        functionParent,
        libraryEntity: functionEntity.library,
        memberEntity: functionEntity,
      );
    } else {
      // This branch is only reached when function is a 'call' method.
      // TODO(markzipan): Ensure call methods never have children.
      info.closures = [];
    }

    if (options.experimentCallInstrumentation) {
      // We use function.hashCode because it is globally unique and it is
      // available while we are doing codegen.
      info.coverageId = '${function.hashCode}';
    }

    state.info.functions.add(info);
    return info;
  }

  /// Adds closure information to [info], using all nested closures in [member].
  void _addClosureInfo(
    Info info,
    ir.Member member, {
    required LibraryEntity libraryEntity,
    required MemberEntity memberEntity,
  }) {
    final localFunctionInfoCollector = LocalFunctionInfoCollector();
    member.accept(localFunctionInfoCollector);
    List<ClosureInfo> nestedClosures = <ClosureInfo>[];
    localFunctionInfoCollector.localFunctions.forEach((key, value) {
      late FunctionEntity closureEntity;
      int closureOrder = value.order;
      environment.forEachNestedClosure(memberEntity, (closure) {
        if (closure.enclosingClass!.name == value.name &&
            (closureOrder-- == 0)) {
          closureEntity = closure;
        }
      });
      final closureClassEntity = closureEntity.enclosingClass!;
      final closureInfo = ClosureInfo.fromKernel(name: value.disambiguatedName);

      final callMethod = closedWorld.elementEnvironment.lookupClassMember(
        closureClassEntity,
        Names.call,
      );
      final functionInfo = visitFunction(
        key.function,
        functionEntity: callMethod as FunctionEntity,
        localFunctionInfo: value,
      );

      closureInfo.function = functionInfo!;
      functionInfo.parent = closureInfo;
      state.info.closures.add(closureInfo);

      closureInfo.parent = info;
      nestedClosures.add(closureInfo);
    });
    if (info is FunctionInfo) info.closures = nestedClosures;
    if (info is FieldInfo) info.closures = nestedClosures;
  }
}

/// Maps JWorld Entity objects to disambiguated names in order to map them
/// to/from Kernel.
///
/// This is primarily used for naming closure objects, which rely on Entity
/// object identity to determine uniqueness.
///
/// Note: this relies on the Kernel traversal order to determine order, which
/// may change in the future.
class EntityDisambiguator {
  final nameFrequencies = <String, int>{};
  final entityNames = <Entity, String>{};

  String name(Entity entity) {
    final disambiguatedName = entityNames[entity];
    if (disambiguatedName != null) {
      return disambiguatedName;
    }
    final entityName = entity.name!;
    nameFrequencies[entityName] = (nameFrequencies[entityName] ?? -1) + 1;
    final order = nameFrequencies[entityName]!;
    entityNames[entity] = order == 0 ? entityName : '$entityName%${order - 1}';

    return entityNames[entity]!;
  }
}

/// Annotates [KernelInfoCollector] with info extracted from closed-world
/// analysis.
class DumpInfoAnnotator {
  final KernelInfoCollector kernelInfo;
  final CompilerOptions options;
  final JClosedWorld closedWorld;
  final GlobalTypeInferenceResults _globalInferenceResults;
  final DumpInfoTask dumpInfoTask;
  final entityDisambiguator = EntityDisambiguator();

  JElementEnvironment get environment => closedWorld.elementEnvironment;

  DumpInfoAnnotator(
    this.kernelInfo,
    this.options,
    this.dumpInfoTask,
    this.closedWorld,
    this._globalInferenceResults,
  );

  void run() {
    dumpInfoTask._dumpInfoData.constantCode.forEach((constant, span) {
      // TODO(sigmund): add dependencies on other constants
      var info = ConstantInfo(
        size: span.end! - span.start!,
        code: [span],
        outputUnit: _unitInfoForConstant(constant),
      );
      kernelInfo.state.constantToInfo[constant] = info;
      info.treeShakenStatus = TreeShakenStatus.Live;
      kernelInfo.state.info.constants.add(info);
    });
    environment.libraries.forEach(visitLibrary);
  }

  /// Whether to emit information about [entity].
  ///
  /// By default we emit information for any entity that contributes to the
  /// output size. Either because it is a function being emitted or inlined,
  /// or because it is an entity that holds dependencies to other entities.
  bool shouldKeep(Entity entity) {
    return dumpInfoTask.impacts.containsKey(entity) ||
        dumpInfoTask.inlineCount.containsKey(entity);
  }

  LibraryInfo? visitLibrary(LibraryEntity lib) {
    var kLibraryInfos = kernelInfo.state.info.libraries.where(
      (i) => '${i.uri}' == '${lib.canonicalUri}',
    );
    assert(
      kLibraryInfos.length == 1,
      'Ambiguous library resolution. '
      'Expected singleton, found $kLibraryInfos',
    );
    var kLibraryInfo = kLibraryInfos.first;
    kernelInfo.state.entityToInfo[lib] = kLibraryInfo;

    String libname = environment.getLibraryName(lib);
    if (libname.isEmpty) {
      libname = '${lib.canonicalUri}';
    }
    assert(kLibraryInfo.name == libname);
    kLibraryInfo.size = dumpInfoTask.sizeOf(lib);

    environment.forEachLibraryMember(lib, (MemberEntity member) {
      if (member.isFunction || member.isGetter || member.isSetter) {
        visitFunction(member as FunctionEntity, libname);
      } else if (member is FieldEntity) {
        visitField(member, libname);
      } else {
        throw StateError('Class member not a function or field');
      }
    });

    environment.forEachClass(lib, (ClassEntity clazz) {
      visitClassType(clazz, libname);
      visitClass(clazz, libname);
    });

    bool hasLiveFields = [
      ...kLibraryInfo.topLevelFunctions,
      ...kLibraryInfo.topLevelVariables,
      ...kLibraryInfo.classes,
      ...kLibraryInfo.classTypes,
    ].any((i) => i.treeShakenStatus == TreeShakenStatus.Live);
    if (!hasLiveFields && !shouldKeep(lib)) return null;
    kLibraryInfo.treeShakenStatus = TreeShakenStatus.Live;
    return kLibraryInfo;
  }

  GlobalTypeInferenceMemberResult _resultOfMember(MemberEntity e) =>
      _globalInferenceResults.resultOfMember(e);

  AbstractValue _resultOfParameter(Local e, MemberEntity? member) =>
      _globalInferenceResults.resultOfParameter(e, member);

  // TODO(markzipan): [parentName] is used for disambiguation, but this might
  // not always be valid. Check and validate later.
  FieldInfo? visitField(FieldEntity field, String parentName) {
    final inferredType = _resultOfMember(field).type;
    // If a field has an empty inferred type it is never used.
    if (closedWorld.abstractValueDomain
        .isEmpty(inferredType)
        .isDefinitelyTrue) {
      return null;
    }

    final kFieldInfos = kernelInfo.state.info.fields
        .where(
          (f) =>
              f.name == field.name &&
              fullyResolvedNameForInfo(f.parent) == parentName,
        )
        .toList();
    assert(
      kFieldInfos.length == 1,
      'Ambiguous field resolution. '
      'Expected singleton, found $kFieldInfos',
    );
    final kFieldInfo = kFieldInfos.first;
    kernelInfo.state.entityToInfo[field] = kFieldInfo;

    int size = dumpInfoTask.sizeOf(field);
    List<CodeSpan> code = dumpInfoTask.codeOf(field);

    // TODO(het): Why doesn't `size` account for the code size already?
    size += code.length;

    kFieldInfo.outputUnit = _unitInfoForMember(field);
    kFieldInfo.inferredType = '$inferredType';
    kFieldInfo.code = code;
    kFieldInfo.treeShakenStatus = TreeShakenStatus.Live;

    FieldAnalysisData fieldData = closedWorld.fieldAnalysis.getFieldData(
      field as JField,
    );
    if (fieldData.initialValue != null) {
      kFieldInfo.initializer =
          kernelInfo.state.constantToInfo[fieldData.initialValue]
              as ConstantInfo?;
    }

    int closureSize = _addClosureInfo(kFieldInfo, field);
    kFieldInfo.size = size + closureSize;
    return kFieldInfo;
  }

  // TODO(markzipan): [parentName] is used for disambiguation, but this might
  // not always be valid. Check and validate later.
  ClassTypeInfo? visitClassType(ClassEntity clazz, String parentName) {
    var kClassTypeInfos = kernelInfo.state.info.classTypes.where(
      (i) => i.name == clazz.name && i.parent!.name == parentName,
    );
    assert(
      kClassTypeInfos.length == 1,
      'Ambiguous class type resolution. '
      'Expected singleton, found $kClassTypeInfos',
    );
    var kClassTypeInfo = kClassTypeInfos.first;

    // TODO(joshualitt): Get accurate size information for class types.
    kClassTypeInfo.size = 0;

    // Omit class type if it is not needed.
    bool isNeeded = dumpInfoTask._dumpInfoData.neededClassTypes.contains(clazz);
    if (!isNeeded) return null;

    assert(kClassTypeInfo.name == clazz.name);
    kClassTypeInfo.outputUnit = _unitInfoForClassType(clazz);
    kClassTypeInfo.treeShakenStatus = TreeShakenStatus.Live;
    return kClassTypeInfo;
  }

  // TODO(markzipan): [parentName] is used for disambiguation, but this might
  // not always be valid. Check and validate later.
  ClassInfo? visitClass(ClassEntity clazz, String parentName) {
    final kClassInfos = kernelInfo.state.info.classes
        .where(
          (i) =>
              i.name == clazz.name &&
              fullyResolvedNameForInfo(i.parent) == parentName,
        )
        .toList();
    assert(
      kClassInfos.length == 1,
      'Ambiguous class resolution. '
      'Expected singleton, found $kClassInfos',
    );
    final kClassInfo = kClassInfos.first;
    kernelInfo.state.entityToInfo[clazz] = kClassInfo;

    /// Add synthetically injected superclasses like `Interceptor` and
    /// `LegacyJavaScriptObject`.
    final syntheticSuperclass = closedWorld.commonElements.getDefaultSuperclass(
      clazz,
      closedWorld.nativeData,
    );
    if (syntheticSuperclass != closedWorld.commonElements.objectClass) {
      final classInfo = kernelInfo.state.entityToInfo[syntheticSuperclass];
      if (classInfo != null) {
        kClassInfo.supers.add(classInfo as ClassInfo);
      }
    }

    int size = dumpInfoTask.sizeOf(clazz);
    final disambiguatedMemberName = '$parentName/${clazz.name}';
    environment.forEachLocalClassMember(clazz, (member) {
      // Skip certain incongruent locals that during method alias installation.
      if (member is JMethod && member.enclosingClass!.name != clazz.name) {
        return;
      }
      if (member.isFunction || member.isGetter || member.isSetter) {
        final functionInfo = visitFunction(
          member as FunctionEntity,
          disambiguatedMemberName,
        );
        if (functionInfo != null) {
          for (var closureInfo in functionInfo.closures) {
            size += closureInfo.size;
          }
        }
      } else if (member is FieldEntity) {
        final fieldInfo = visitField(member, disambiguatedMemberName);
        if (fieldInfo != null) {
          for (var closureInfo in fieldInfo.closures) {
            size += closureInfo.size;
          }
        }
      } else {
        throw StateError('Class member not a function or field');
      }
    });
    environment.forEachConstructor(clazz, (constructor) {
      final functionInfo = visitFunction(constructor, disambiguatedMemberName);
      if (functionInfo != null) {
        for (var closureInfo in functionInfo.closures) {
          size += closureInfo.size;
        }
      }
    });
    kClassInfo.size = size;

    bool hasLiveFields = [
      ...kClassInfo.fields,
      ...kClassInfo.functions,
    ].any((i) => i.treeShakenStatus == TreeShakenStatus.Live);
    if (!dumpInfoTask._dumpInfoData.neededClasses.contains(clazz) &&
        !hasLiveFields) {
      return null;
    }

    kClassInfo.outputUnit = _unitInfoForClass(clazz);
    kClassInfo.treeShakenStatus = TreeShakenStatus.Live;
    return kClassInfo;
  }

  ClosureInfo? visitClosureClass(ClassEntity element) {
    final disambiguatedElementName = entityDisambiguator.name(element);
    final kClosureInfos = kernelInfo.state.info.closures
        .where((info) => info.name == disambiguatedElementName)
        .toList();
    assert(
      kClosureInfos.length == 1,
      'Ambiguous closure resolution. '
      'Expected singleton, found $kClosureInfos',
    );
    final kClosureInfo = kClosureInfos.first;
    kernelInfo.state.entityToInfo[element] = kClosureInfo;

    kClosureInfo.outputUnit = _unitInfoForClass(element);
    kClosureInfo.size = dumpInfoTask.sizeOf(element);

    final callMethod = closedWorld.elementEnvironment.lookupClassMember(
      element,
      Names.call,
    );

    final functionInfo = visitFunction(
      callMethod as FunctionEntity,
      disambiguatedElementName,
      isClosure: true,
    );
    if (functionInfo == null) return null;

    kClosureInfo.treeShakenStatus = TreeShakenStatus.Live;
    return kClosureInfo;
  }

  // TODO(markzipan): [parentName] is used for disambiguation, but this might
  // not always be valid. Check and validate later.
  FunctionInfo? visitFunction(
    FunctionEntity function,
    String parentName, {
    bool isClosure = false,
  }) {
    int size = dumpInfoTask.sizeOf(function);
    if (size == 0 && !shouldKeep(function)) return null;

    var compareName = function.name;
    if (function is ConstructorEntity) {
      compareName = compareName == ""
          ? function.enclosingClass.name
          : "${function.enclosingClass.name}.${function.name}";
    }

    // Multiple kernel members can sometimes map to a single JElement.
    // [isSetter] and [isGetter] are required for disambiguating these cases.
    final kFunctionInfos = kernelInfo.state.info.functions
        .where(
          (i) =>
              i.name == compareName &&
              (isClosure
                      ? i.parent!.name
                      : fullyResolvedNameForInfo(i.parent)) ==
                  parentName &&
              !(function.isGetter ^ i.modifiers.isGetter) &&
              !(function.isSetter ^ i.modifiers.isSetter),
        )
        .toList();
    assert(
      kFunctionInfos.length <= 1,
      'Ambiguous function resolution. '
      'Expected single or none, found $kFunctionInfos',
    );
    if (kFunctionInfos.isEmpty) return null;
    final kFunctionInfo = kFunctionInfos.first;
    kernelInfo.state.entityToInfo[function] = kFunctionInfo;

    List<CodeSpan> code = dumpInfoTask.codeOf(function);
    List<ParameterInfo> parameters = <ParameterInfo>[];
    List<String> inferredParameterTypes = <String>[];

    closedWorld.elementEnvironment.forEachParameterAsLocal(
      _globalInferenceResults.globalLocalsMap,
      function,
      (parameter) {
        inferredParameterTypes.add(
          '${_resultOfParameter(parameter, function)}',
        );
      },
    );
    int parameterIndex = 0;
    closedWorld.elementEnvironment.forEachParameter(function, (type, name, _) {
      // Synthesized parameters have no name. This can happen on parameters of
      // setters derived from lowering late fields.
      parameters.add(
        ParameterInfo(
          name ?? '#t$parameterIndex',
          inferredParameterTypes[parameterIndex++],
          '$type',
        ),
      );
    });

    String inferredReturnType = '${_resultOfMember(function).returnType}';
    String sideEffects =
        '${_globalInferenceResults.inferredData.getSideEffectsOfElement(function)}';
    int inlinedCount = dumpInfoTask.inlineCount[function] ?? 0;

    kFunctionInfo.inferredReturnType = inferredReturnType;
    kFunctionInfo.sideEffects = sideEffects;
    kFunctionInfo.inlinedCount = inlinedCount;
    kFunctionInfo.code = code;
    kFunctionInfo.parameters = parameters;
    kFunctionInfo.outputUnit = _unitInfoForMember(function);

    int closureSize = _addClosureInfo(kFunctionInfo, function);
    kFunctionInfo.size = size + closureSize;

    kFunctionInfo.treeShakenStatus = TreeShakenStatus.Live;
    return kFunctionInfo;
  }

  /// Adds closure information to [info], using all nested closures in [member].
  ///
  /// Returns the total size of the nested closures, to add to the info size.
  int _addClosureInfo(BasicInfo info, MemberEntity member) {
    assert(info is FunctionInfo || info is FieldInfo);
    int size = 0;
    environment.forEachNestedClosure(member, (closure) {
      final closureInfo = visitClosureClass(closure.enclosingClass!);
      if (closureInfo != null) {
        closureInfo.treeShakenStatus = TreeShakenStatus.Live;
        size += closureInfo.size;
      }
    });
    return size;
  }

  OutputUnitInfo _infoFromOutputUnit(OutputUnit outputUnit) {
    return kernelInfo.state.outputToInfo.putIfAbsent(outputUnit, () {
      // Dump-info currently only works with the full emitter. If another
      // emitter is used it will fail here.
      final filename = outputUnit.isMainOutput
          ? (options.outputUri?.pathSegments.last ?? 'out')
          : deferredPartFileName(options, outputUnit.name);
      OutputUnitInfo info = OutputUnitInfo(
        filename,
        outputUnit.name,
        dumpInfoTask._dumpInfoData.outputUnitSizes[outputUnit]!,
      );
      info.treeShakenStatus = TreeShakenStatus.Live;
      info.imports.addAll(
        closedWorld.outputUnitData.getImportNames(outputUnit),
      );
      kernelInfo.state.info.outputUnits.add(info);
      return info;
    });
  }

  OutputUnitInfo _unitInfoForMember(MemberEntity entity) {
    return _infoFromOutputUnit(
      closedWorld.outputUnitData.outputUnitForMember(entity),
    );
  }

  OutputUnitInfo _unitInfoForClass(ClassEntity entity) {
    return _infoFromOutputUnit(
      closedWorld.outputUnitData.outputUnitForClass(entity, allowNull: true),
    );
  }

  OutputUnitInfo _unitInfoForClassType(ClassEntity entity) {
    return _infoFromOutputUnit(
      closedWorld.outputUnitData.outputUnitForClassType(
        entity,
        allowNull: true,
      ),
    );
  }

  OutputUnitInfo _unitInfoForConstant(ConstantValue constant) {
    OutputUnit outputUnit = closedWorld.outputUnitData.outputUnitForConstant(
      constant,
    );
    return _infoFromOutputUnit(outputUnit);
  }
}

class Selection {
  final Entity selectedEntity;
  final Object? receiverConstraint;
  Selection(this.selectedEntity, this.receiverConstraint);
}

/// Interface used to record information from different parts of the compiler so
/// we can emit them in the dump-info task.
// TODO(sigmund,het): move more features here. Ideally the dump-info task
// shouldn't reach into internals of other parts of the compiler. For example,
// we currently reach into the full emitter and as a result we don't support
// dump-info when using the startup-emitter (issue #24190).
abstract class InfoReporter {
  void reportInlined(FunctionEntity element, MemberEntity inlinedFrom);
}

class DumpInfoTask extends CompilerTask implements InfoReporter {
  final CompilerOptions options;
  final api.CompilerOutput outputProvider;
  final DiagnosticReporter reporter;
  final Measurer measurer;
  final bool useBinaryFormat;

  DumpInfoTask(this.options, this.measurer, this.outputProvider, this.reporter)
    : useBinaryFormat = options.dumpInfoFormat == DumpInfoFormat.binary,
      super(measurer);

  @override
  String get name => "Dump Info";

  /// The size of the generated output.
  late DumpInfoProgramData _dumpInfoData;

  final Map<Entity, int> inlineCount = <Entity, int>{};

  // A mapping from an entity to a list of entities that are
  // inlined inside of it.
  final Map<Entity, List<Entity>> inlineMap = <Entity, List<Entity>>{};

  final Map<MemberEntity, WorldImpact> impacts = {};

  /// Register the size of the generated output.
  void registerDumpInfoProgramData(DumpInfoProgramData dumpInfoData) {
    _dumpInfoData = dumpInfoData;
  }

  @override
  void reportInlined(FunctionEntity element, MemberEntity inlinedFrom) {
    inlineCount.update(element, (i) => i + 1, ifAbsent: () => 1);
    inlineMap.putIfAbsent(inlinedFrom, () => <Entity>[]);
    inlineMap[inlinedFrom]!.add(element);
  }

  void unregisterImpact(MemberEntity impactSource) {
    impacts.remove(impactSource);
  }

  /// Returns an iterable of [Selection]s that are used by [entity]. Each
  /// [Selection] contains an entity that is used and the selector that
  /// selected the entity.
  Iterable<Selection> getRetaining(
    MemberEntity entity,
    JClosedWorld closedWorld,
  ) {
    final impact = impacts[entity];
    if (impact == null) return const <Selection>[];

    var selections = <Selection>[];
    impact.forEachDynamicUse((_, dynamicUse) {
      final mask = dynamicUse.receiverConstraint as AbstractValue?;
      selections.addAll(
        closedWorld
            // TODO(het): Handle `call` on `Closure` through
            // `world.includesClosureCall`.
            .locateMembers(dynamicUse.selector, mask)
            .map((MemberEntity e) => Selection(e, mask)),
      );
    });
    impact.forEachStaticUse((_, staticUse) {
      selections.add(Selection(staticUse.element, null));
    });
    unregisterImpact(entity);
    return selections;
  }

  /// Returns the size of the source code that was generated for an entity.
  /// If no source code was produced, return 0.
  int sizeOf(Entity entity) {
    return _dumpInfoData.entityCodeSize[entity] ?? 0;
  }

  List<CodeSpan> codeOf(MemberEntity entity) {
    return _dumpInfoData.entityCode[entity] ?? const [];
  }

  void _populateImpacts(
    JClosedWorld closedWorld,
    CodegenResults codegenResults,
    JsBackendStrategy backendStrategy,
  ) {
    backendStrategy.initialize(closedWorld, codegenResults.codegenInputs);

    _dumpInfoData.registeredImpacts.forEach((member, impact) {
      impacts[member] = backendStrategy.transformCodegenImpact(impact);
    });
    for (final member in _dumpInfoData.serializedImpactMembers) {
      final (:result, :isGenerated) = codegenResults.getCodegenResults(member);
      assert(!isGenerated, 'Should not be generating impact: $member');
      impacts[member] = backendStrategy.transformCodegenImpact(result.impact);
    }
  }

  Future<DumpInfoStateData> dumpInfo(
    JClosedWorld closedWorld,
    GlobalTypeInferenceResults globalInferenceResults,
    CodegenResults codegenResults,
    JsBackendStrategy backendStrategy,
  ) async {
    late DumpInfoStateData dumpInfoState;
    await measure(() async {
      _populateImpacts(closedWorld, codegenResults, backendStrategy);

      ElementInfoCollector elementInfoCollector = ElementInfoCollector(
        options,
        this,
        closedWorld,
        globalInferenceResults,
      )..run();

      dumpInfoState = await buildDumpInfoData(
        closedWorld,
        elementInfoCollector,
      );
      if (useBinaryFormat) {
        dumpInfoBinary(dumpInfoState.info);
      } else {
        dumpInfoJson(dumpInfoState.info);
      }
      return;
    });
    return dumpInfoState;
  }

  Future<DumpInfoStateData> dumpInfoNew(
    ir.Component component,
    JClosedWorld closedWorld,
    GlobalTypeInferenceResults globalInferenceResults,
    CodegenResults codegenResults,
    JsBackendStrategy backendStrategy,
  ) async {
    late DumpInfoStateData dumpInfoState;
    await measure(() async {
      _populateImpacts(closedWorld, codegenResults, backendStrategy);

      KernelInfoCollector kernelInfoCollector = KernelInfoCollector(
        component,
        options,
        this,
        closedWorld,
      )..run();

      DumpInfoAnnotator(
        kernelInfoCollector,
        options,
        this,
        closedWorld,
        globalInferenceResults,
      ).run();

      dumpInfoState = await buildDumpInfoDataNew(
        closedWorld,
        kernelInfoCollector,
      );
      TreeShakingInfoVisitor().filter(dumpInfoState.info);

      if (useBinaryFormat) {
        dumpInfoBinary(dumpInfoState.info);
      } else {
        dumpInfoJson(dumpInfoState.info);
      }
    });
    return dumpInfoState;
  }

  void dumpInfoJson(AllInfo data) {
    JsonEncoder encoder = const JsonEncoder.withIndent('  ');
    final name = (options.outputUri?.pathSegments.last ?? 'out');
    final outputSink = outputProvider.createOutputSink(
      name,
      'info.json',
      api.OutputType.dumpInfo,
    );
    final sink = encoder.startChunkedConversion(
      _BufferedStringOutputSink(outputSink),
    );
    sink.add(AllInfoJsonCodec(isBackwardCompatible: true).encode(data));
    reporter.reportInfoMessage(noLocationSpannable, MessageKind.generic, {
      'text':
          'Learn how to process the dumped .info.json file at '
          'https://dart.dev/go/dart2js-info',
    });
  }

  void dumpInfoBinary(AllInfo data) {
    final name = "${options.outputUri?.pathSegments.last ?? 'out'}.info.data";
    Sink<List<int>> sink = outputProvider.createBinarySink(
      options.outputUri!.resolve(name),
    );
    dump_info.encode(data, sink);
    reporter.reportInfoMessage(noLocationSpannable, MessageKind.generic, {
      'text':
          'Learn how to parse and process the dumped .info.data file at '
          'https://dart.dev/go/dart2js-info',
    });
  }

  Future<DumpInfoStateData> buildDumpInfoData(
    JClosedWorld closedWorld,
    ElementInfoCollector infoCollector,
  ) async {
    Stopwatch stopwatch = Stopwatch();
    stopwatch.start();

    DumpInfoStateData result = infoCollector.state;

    // Recursively build links to function uses
    final functionEntities = infoCollector.state.entityToInfo.keys
        .whereType<FunctionEntity>();
    for (final entity in functionEntities) {
      final info = infoCollector.state.entityToInfo[entity] as FunctionInfo;
      Iterable<Selection> uses = getRetaining(entity, closedWorld);
      // Don't bother recording an empty list of dependencies.
      for (Selection selection in uses) {
        // Don't register dart2js builtin functions that are not recorded.
        final useInfo =
            infoCollector.state.entityToInfo[selection.selectedEntity];
        if (useInfo == null) continue;
        info.uses.add(
          DependencyInfo(useInfo, selection.receiverConstraint?.toString()),
        );
      }
    }

    // Recursively build links to field uses
    final fieldEntity = infoCollector.state.entityToInfo.keys
        .whereType<FieldEntity>();
    for (final entity in fieldEntity) {
      final info = infoCollector.state.entityToInfo[entity] as FieldInfo;
      Iterable<Selection> uses = getRetaining(entity, closedWorld);
      // Don't bother recording an empty list of dependencies.
      for (Selection selection in uses) {
        final useInfo =
            infoCollector.state.entityToInfo[selection.selectedEntity];
        if (useInfo == null) continue;
        info.uses.add(
          DependencyInfo(useInfo, selection.receiverConstraint?.toString()),
        );
      }
    }

    // Track dependencies that come from inlining.
    for (Entity entity in inlineMap.keys) {
      final outerInfo = infoCollector.state.entityToInfo[entity] as CodeInfo?;
      if (outerInfo == null) continue;
      for (final inlined in inlineMap[entity]!) {
        final inlinedInfo = infoCollector.state.entityToInfo[inlined];
        if (inlinedInfo == null) continue;
        outerInfo.uses.add(DependencyInfo(inlinedInfo, 'inlined'));
      }
    }

    result.info.deferredFiles = _dumpInfoData.fragmentDeferredMap;
    stopwatch.stop();

    final ramUsage =
        (options.omitMemorySummary ? null : await currentHeapCapacityInMb()) ??
        'N/A MB';

    result.info.program = ProgramInfo(
      entrypoint:
          infoCollector.state.entityToInfo[closedWorld
                  .elementEnvironment
                  .mainFunction]
              as FunctionInfo,
      size: _dumpInfoData.programSize,
      ramUsage: ramUsage,
      dart2jsVersion: options.hasBuildId ? options.buildId : null,
      compilationMoment: DateTime.now(),
      compilationDuration: measurer.elapsedWallClock,
      toJsonDuration: Duration(milliseconds: stopwatch.elapsedMilliseconds),
      dumpInfoDuration: Duration(milliseconds: timing),
      noSuchMethodEnabled: closedWorld.backendUsage.isNoSuchMethodUsed,
      isRuntimeTypeUsed: closedWorld.backendUsage.isRuntimeTypeUsed,
      isIsolateInUse: false,
      isFunctionApplyUsed: closedWorld.backendUsage.isFunctionApplyUsed,
      minified: options.enableMinification,
    );

    return result;
  }

  Future<DumpInfoStateData> buildDumpInfoDataNew(
    JClosedWorld closedWorld,
    KernelInfoCollector infoCollector,
  ) async {
    Stopwatch stopwatch = Stopwatch();
    stopwatch.start();

    DumpInfoStateData result = infoCollector.state;

    // Recursively build links to function uses
    final functionEntities = infoCollector.state.entityToInfo.keys
        .whereType<FunctionEntity>();
    for (final entity in functionEntities) {
      final info = infoCollector.state.entityToInfo[entity] as FunctionInfo;
      Iterable<Selection> uses = getRetaining(entity, closedWorld);
      // Don't bother recording an empty list of dependencies.
      for (Selection selection in uses) {
        // Don't register dart2js builtin functions that are not recorded.
        final useInfo =
            infoCollector.state.entityToInfo[selection.selectedEntity];
        if (useInfo == null) continue;
        if (useInfo.treeShakenStatus != TreeShakenStatus.Live) continue;
        info.uses.add(
          DependencyInfo(useInfo, selection.receiverConstraint?.toString()),
        );
      }
    }

    // Recursively build links to field uses
    final fieldEntity = infoCollector.state.entityToInfo.keys
        .whereType<FieldEntity>();
    for (final entity in fieldEntity) {
      final info = infoCollector.state.entityToInfo[entity] as FieldInfo;
      Iterable<Selection> uses = getRetaining(entity, closedWorld);
      // Don't bother recording an empty list of dependencies.
      for (Selection selection in uses) {
        final useInfo =
            infoCollector.state.entityToInfo[selection.selectedEntity];
        if (useInfo == null) continue;
        if (useInfo.treeShakenStatus != TreeShakenStatus.Live) continue;
        info.uses.add(
          DependencyInfo(useInfo, selection.receiverConstraint?.toString()),
        );
      }
    }

    // Track dependencies that come from inlining.
    for (Entity entity in inlineMap.keys) {
      final outerInfo = infoCollector.state.entityToInfo[entity] as CodeInfo?;
      if (outerInfo == null) continue;
      for (final inlined in inlineMap[entity]!) {
        final inlinedInfo = infoCollector.state.entityToInfo[inlined];
        if (inlinedInfo == null) continue;
        if (inlinedInfo.treeShakenStatus != TreeShakenStatus.Live) continue;
        outerInfo.uses.add(DependencyInfo(inlinedInfo, 'inlined'));
      }
    }

    result.info.deferredFiles = _dumpInfoData.fragmentDeferredMap;
    stopwatch.stop();

    final ramUsage =
        (options.omitMemorySummary ? null : await currentHeapCapacityInMb()) ??
        'N/A MB';

    result.info.program = ProgramInfo(
      entrypoint:
          infoCollector.state.entityToInfo[closedWorld
                  .elementEnvironment
                  .mainFunction]
              as FunctionInfo,
      size: _dumpInfoData.programSize,
      ramUsage: ramUsage,
      dart2jsVersion: options.hasBuildId ? options.buildId : null,
      compilationMoment: DateTime.now(),
      compilationDuration: measurer.elapsedWallClock,
      toJsonDuration: Duration(milliseconds: stopwatch.elapsedMilliseconds),
      dumpInfoDuration: Duration(milliseconds: timing),
      noSuchMethodEnabled: closedWorld.backendUsage.isNoSuchMethodUsed,
      isRuntimeTypeUsed: closedWorld.backendUsage.isRuntimeTypeUsed,
      isIsolateInUse: false,
      isFunctionApplyUsed: closedWorld.backendUsage.isFunctionApplyUsed,
      minified: options.enableMinification,
    );

    return result;
  }
}

class _BufferedStringOutputSink implements Sink<String> {
  StringBuffer buffer = StringBuffer();
  final Sink<String> outputSink;
  static const int _maxLength = 1024 * 1024 * 500;

  _BufferedStringOutputSink(this.outputSink);

  @override
  void add(String data) {
    buffer.write(data);
    if (buffer.length > _maxLength) {
      outputSink.add(buffer.toString());
      buffer.clear();
    }
  }

  @override
  void close() {
    outputSink.add(buffer.toString());
    outputSink.close();
  }
}

/// Helper class to store what dump-info will show for a piece of code.
// TODO(sigmund): delete once we no longer emit text by default.
class _CodeData extends CodeSpan {
  final StringBuffer _text = StringBuffer();

  @override
  String get text => '$_text';
  int get length => end! - start!;
}

/// Holds dump-info's mutable state.
class DumpInfoStateData {
  final AllInfo info = AllInfo();
  final Map<Entity, Info> entityToInfo = <Entity, Info>{};
  final Map<ConstantValue, Info> constantToInfo = <ConstantValue, Info>{};
  final Map<OutputUnit, OutputUnitInfo> outputToInfo = {};

  DumpInfoStateData();
}

class LocalFunctionInfo {
  final ir.LocalFunction localFunction;
  final String name;
  final int order;
  bool isInvoked = false;

  LocalFunctionInfo(this.localFunction, this.name, this.order);

  String get disambiguatedName => order == 0 ? name : '$name%${order - 1}';
}

class LocalFunctionInfoCollector extends ir.RecursiveVisitor {
  final localFunctions = <ir.LocalFunction, LocalFunctionInfo>{};
  final localFunctionNameCount = <String, int>{};

  LocalFunctionInfo generateLocalFunctionInfo(ir.LocalFunction localFunction) {
    final name = _computeClosureName(localFunction);
    localFunctionNameCount[name] = (localFunctionNameCount[name] ?? -1) + 1;
    return LocalFunctionInfo(
      localFunction,
      name,
      localFunctionNameCount[name]!,
    );
  }

  @override
  void visitFunctionExpression(ir.FunctionExpression node) {
    assert(!localFunctions.containsKey(node));
    localFunctions[node] = generateLocalFunctionInfo(node);
    defaultExpression(node);
  }

  @override
  void visitFunctionDeclaration(ir.FunctionDeclaration node) {
    assert(!localFunctions.containsKey(node));
    localFunctions[node] = generateLocalFunctionInfo(node);
    defaultStatement(node);
  }

  @override
  void visitLocalFunctionInvocation(ir.LocalFunctionInvocation node) {
    if (localFunctions[node.localFunction] == null) {
      visitFunctionDeclaration(node.localFunction);
    }
    localFunctions[node.localFunction]!.isInvoked = true;
  }
}

// Returns a non-unique name for the given closure element.
//
// Must be kept logically identical to js_model/element_map_impl.dart.
String _computeClosureName(ir.TreeNode treeNode) {
  String reconstructConstructorName(ir.Member node) {
    String className = node.enclosingClass!.name;
    return node.name.text == '' ? className : '$className\$${node.name.text}';
  }

  var parts = <String>[];
  // First anonymous is called 'closure', outer ones called '' to give a
  // compound name where increasing nesting level corresponds to extra
  // underscores.
  var anonymous = 'closure';
  ir.TreeNode? current = treeNode;
  while (current != null) {
    var node = current;
    if (node is ir.FunctionExpression) {
      parts.add(anonymous);
      anonymous = '';
    } else if (node is ir.FunctionDeclaration) {
      final name = node.variable.name;
      if (name != null && name != "") {
        parts.add(entity_utils.operatorNameToIdentifier(name)!);
      } else {
        parts.add(anonymous);
        anonymous = '';
      }
    } else if (node is ir.Class) {
      parts.add(node.name);
      break;
    } else if (node is ir.Procedure) {
      if (node.kind == ir.ProcedureKind.Factory) {
        parts.add(reconstructConstructorName(node));
      } else {
        parts.add(entity_utils.operatorNameToIdentifier(node.name.text)!);
      }
    } else if (node is ir.Constructor) {
      parts.add(reconstructConstructorName(node));
      break;
    } else if (node is ir.Field) {
      // Add the field name for closures in field initializers.
      String name = node.name.text;
      parts.add(name);
    }
    current = current.parent;
  }
  return parts.reversed.join('_');
}

/// Filters dead code from Dart2JS [Info] trees.
class TreeShakingInfoVisitor extends InfoVisitor<void> {
  List<T> filterDeadInfo<T extends Info>(List<T> infos) {
    return infos
        .where((info) => info.treeShakenStatus == TreeShakenStatus.Live)
        .toList();
  }

  void filter(AllInfo info) {
    info.program = info.program;
    info.libraries = filterDeadInfo<LibraryInfo>(info.libraries);
    info.functions = filterDeadInfo<FunctionInfo>(info.functions);
    info.typedefs = filterDeadInfo<TypedefInfo>(info.typedefs);
    info.typedefs = filterDeadInfo<TypedefInfo>(info.typedefs);
    info.classes = filterDeadInfo<ClassInfo>(info.classes);
    info.classTypes = filterDeadInfo<ClassTypeInfo>(info.classTypes);
    info.fields = filterDeadInfo<FieldInfo>(info.fields);
    info.constants = filterDeadInfo<ConstantInfo>(info.constants);
    info.closures = filterDeadInfo<ClosureInfo>(info.closures);
    info.outputUnits = filterDeadInfo<OutputUnitInfo>(info.outputUnits);
    info.deferredFiles = info.deferredFiles;
    // TODO(markzipan): 'dependencies' is always empty. Revisit this if/when
    // this holds meaningful information.
    info.dependencies = info.dependencies;
    info.accept(this);
  }

  @override
  void visitAll(AllInfo info) {
    info.libraries = filterDeadInfo<LibraryInfo>(info.libraries);
    info.constants = filterDeadInfo<ConstantInfo>(info.constants);

    info.libraries.forEach(visitLibrary);
    info.constants.forEach(visitConstant);
  }

  @override
  void visitProgram(ProgramInfo info) {}

  @override
  void visitLibrary(LibraryInfo info) {
    info.topLevelFunctions = filterDeadInfo<FunctionInfo>(
      info.topLevelFunctions,
    );
    info.topLevelVariables = filterDeadInfo<FieldInfo>(info.topLevelVariables);
    info.classes = filterDeadInfo<ClassInfo>(info.classes);
    info.classTypes = filterDeadInfo<ClassTypeInfo>(info.classTypes);
    info.typedefs = filterDeadInfo<TypedefInfo>(info.typedefs);

    info.topLevelFunctions.forEach(visitFunction);
    info.topLevelVariables.forEach(visitField);
    info.classes.forEach(visitClass);
    info.classTypes.forEach(visitClassType);
    info.typedefs.forEach(visitTypedef);
  }

  @override
  void visitClass(ClassInfo info) {
    info.functions = filterDeadInfo<FunctionInfo>(info.functions);
    info.fields = filterDeadInfo<FieldInfo>(info.fields);
    info.supers = filterDeadInfo<ClassInfo>(info.supers);

    info.functions.forEach(visitFunction);
    info.fields.forEach(visitField);
    info.supers.forEach(visitClass);
  }

  @override
  void visitClassType(ClassTypeInfo info) {}

  @override
  void visitField(FieldInfo info) {
    info.closures = filterDeadInfo<ClosureInfo>(info.closures);

    info.closures.forEach(visitClosure);
  }

  @override
  void visitConstant(ConstantInfo info) {}

  @override
  void visitFunction(FunctionInfo info) {
    info.closures = filterDeadInfo<ClosureInfo>(info.closures);

    info.closures.forEach(visitClosure);
  }

  @override
  void visitTypedef(TypedefInfo info) {}
  @override
  void visitOutput(OutputUnitInfo info) {}
  @override
  void visitClosure(ClosureInfo info) {
    visitFunction(info.function);
  }
}

/// Returns a fully resolved name for [info] for disambiguation.
String fullyResolvedNameForInfo(Info? info) {
  if (info == null) return '';
  var name = info.name;
  var currentInfo = info;
  while (currentInfo.parent != null) {
    currentInfo = currentInfo.parent!;
    name = '${currentInfo.name}/$name';
  }
  return name;
}
