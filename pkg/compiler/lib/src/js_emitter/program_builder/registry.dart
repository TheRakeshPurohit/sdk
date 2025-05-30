// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'program_builder.dart';

class LibraryContents {
  final List<ClassEntity> classes = [];
  final List<MemberEntity> members = [];
  final List<ClassEntity> classTypes = [];
}

/// Maps [LibraryEntity]s to their classes, members, and class types.
///
/// Fundamentally, this class nicely encapsulates a
/// `Map<LibraryEntity, Tuple<classes, members, class types>>`.
///
/// where both classes and class types are lists of [ClassEntity] and
/// members is a list of [MemberEntity].
///
/// There exists exactly one instance per [OutputUnit].
class LibrariesMap {
  final Map<LibraryEntity, LibraryContents> _mapping = {};

  // It is very common to access the same library multiple times in a row, so
  // we cache the last access.
  LibraryEntity? _lastLibrary;
  late LibraryContents _lastMapping;

  /// A unique name representing this instance.
  final String name;
  final OutputUnit outputUnit;

  LibrariesMap.main(this.outputUnit) : name = "";

  LibrariesMap.deferred(this.outputUnit, this.name) {
    assert(name != "");
  }

  LibraryContents _getMapping(LibraryEntity library) {
    if (_lastLibrary != library) {
      _lastLibrary = library;
      _lastMapping = _mapping.putIfAbsent(library, () => LibraryContents());
    }
    return _lastMapping;
  }

  void addClass(LibraryEntity library, ClassEntity element) {
    _getMapping(library).classes.add(element);
  }

  void addClassType(LibraryEntity library, ClassEntity element) {
    _getMapping(library).classTypes.add(element);
  }

  void addMember(LibraryEntity library, MemberEntity element) {
    _getMapping(library).members.add(element);
  }

  int get length => _mapping.length;

  Iterable<MapEntry<LibraryEntity, LibraryContents>> get entries =>
      _mapping.entries;

  void forEach(
    void Function(
      LibraryEntity library,
      List<ClassEntity> classes,
      List<MemberEntity> members,
      List<ClassEntity> classTypeData,
    )
    f,
  ) {
    _mapping.forEach((LibraryEntity library, LibraryContents mapping) {
      f(library, mapping.classes, mapping.members, mapping.classTypes);
    });
  }
}

/// Keeps track of all elements and holders.
///
/// This class assigns each registered element to its [LibrariesMap] (which are
/// in bijection with [OutputUnit]s).
///
/// Registered holders are assigned a name.
class Registry {
  final OutputUnit _mainOutputUnit;
  final Sorter _sorter;
  final Map<OutputUnit, LibrariesMap> _deferredLibrariesMap = {};

  /// Cache for the last seen output unit.
  OutputUnit? _lastOutputUnit;
  late LibrariesMap _lastLibrariesMap;

  Iterable<LibrariesMap> get deferredLibrariesMap =>
      _deferredLibrariesMap.values;

  // Add one for the main libraries map.
  int get librariesMapCount => _deferredLibrariesMap.length + 1;

  late final LibrariesMap mainLibrariesMap;

  Registry(this._mainOutputUnit, this._sorter);

  LibrariesMap _mapUnitToLibrariesMap(OutputUnit targetUnit) {
    if (targetUnit == _lastOutputUnit) return _lastLibrariesMap;

    final result = (targetUnit == _mainOutputUnit)
        ? mainLibrariesMap
        : _deferredLibrariesMap[targetUnit]!;

    _lastOutputUnit = targetUnit;
    _lastLibrariesMap = result;
    return result;
  }

  void registerOutputUnit(OutputUnit outputUnit) {
    if (outputUnit == _mainOutputUnit) {
      mainLibrariesMap = LibrariesMap.main(_mainOutputUnit);
    } else {
      assert(!_deferredLibrariesMap.containsKey(outputUnit));
      String name = outputUnit.name;
      _deferredLibrariesMap[outputUnit] = LibrariesMap.deferred(
        outputUnit,
        name,
      );
    }
  }

  /// Adds all elements to their respective libraries in the correct
  /// libraries map.
  void registerClasses(OutputUnit outputUnit, Iterable<ClassEntity> elements) {
    LibrariesMap targetLibrariesMap = _mapUnitToLibrariesMap(outputUnit);
    for (ClassEntity element in _sorter.sortClasses(elements)) {
      targetLibrariesMap.addClass(element.library, element);
    }
  }

  /// Adds all elements to their respective libraries in the correct
  /// libraries map.
  void registerClassTypes(
    OutputUnit outputUnit,
    Iterable<ClassEntity> elements,
  ) {
    LibrariesMap targetLibrariesMap = _mapUnitToLibrariesMap(outputUnit);
    for (ClassEntity element in _sorter.sortClasses(elements)) {
      targetLibrariesMap.addClassType(element.library, element);
    }
  }

  /// Adds all elements to their respective libraries in the correct
  /// libraries map.
  void registerMembers(OutputUnit outputUnit, Iterable<MemberEntity> elements) {
    LibrariesMap targetLibrariesMap = _mapUnitToLibrariesMap(outputUnit);
    for (MemberEntity element in _sorter.sortMembers(elements)) {
      targetLibrariesMap.addMember(element.library, element);
    }
  }

  void registerConstant(OutputUnit outputUnit, ConstantValue constantValue) {
    // Ignore for now.
  }
}
