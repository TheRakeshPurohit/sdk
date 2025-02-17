// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Loads a human-readable source map and outputs the source map file for it.

library save;

import 'dart:convert';
import 'dart:io';
import 'package:source_maps/source_maps.dart';
import '../helpers/lax_json.dart' as lazon;

void main(List<String> args) {
  if (args.isEmpty) {
    print('''
Usage: save <dir-containing 'out.js.map2'>
   or: save <human-readable-source-map-file> [<source-map-file>]''');
    exit(1);
  }

  File humanReadableSourceMapFile;
  File? sourceMapFile;
  if (args.length == 1 && Directory(args[0]).existsSync()) {
    humanReadableSourceMapFile = File('${args[0]}/out.js.map2');
    sourceMapFile = File('${args[0]}/out.js.map');
  } else {
    humanReadableSourceMapFile = File(args[0]);
    if (args.length > 1) {
      sourceMapFile = File(args[1]);
    }
  }

  String humanReadableSourceMap = humanReadableSourceMapFile.readAsStringSync();
  SingleMapping mapping = convertFromHumanReadableSourceMap(
    humanReadableSourceMap,
  );

  if (sourceMapFile != null) {
    sourceMapFile.writeAsStringSync(json.encoder.convert(mapping.toJson()));
  } else {
    print(new JsonEncoder.withIndent('  ').convert(mapping.toJson()));
  }
}

SingleMapping convertFromHumanReadableSourceMap(String json) {
  Map inputMap = lazon.decode(json);
  Map urls = inputMap['sources'];
  List<String?> sources = List.filled(urls.length, null);
  urls.forEach((dynamic index, dynamic url) {
    int i = int.parse(index);
    assert(sources[i] == null);
    sources[i] = url;
  });
  List lines = inputMap['lines'];
  Map<String, int> names = <String, int>{};
  Map<int, TargetLineEntry> lineEntryMap = {};

  for (Map line in lines) {
    String targetString = line['target']!;
    String? sourceString = line['source'];
    String? name = line['name'];
    int? nameIndex;
    if (name != null) {
      nameIndex = names.putIfAbsent(name, () => names.length);
    }

    int? columnEnd;
    int commaPos = targetString.indexOf(',');
    final lineNo = int.parse(targetString.substring(0, commaPos)) - 1;
    if (lineNo < 0) {
      throw ArgumentError('target line must be > 0: $lineNo');
    }
    targetString = targetString.substring(commaPos + 1);
    int dashPos = targetString.indexOf('-');
    final columnStart = int.parse(targetString.substring(0, dashPos)) - 1;
    if (columnStart < 0) {
      throw ArgumentError('target column start must be > 0: $columnStart');
    }
    targetString = targetString.substring(dashPos + 1);
    if (!targetString.isEmpty) {
      columnEnd = int.parse(targetString) - 1;
      if (columnEnd < 0) {
        throw ArgumentError('target column end must be > 0: $columnEnd');
      }
    }

    int? sourceUrlId;
    int? sourceLine;
    int? sourceColumn;
    if (sourceString != null) {
      int colonPos = sourceString.indexOf(':');
      sourceUrlId = int.parse(sourceString.substring(0, colonPos));
      if (sourceUrlId < 0) {
        throw ArgumentError('source url id end must be > 0: $sourceUrlId');
      } else if (sourceUrlId >= sources.length) {
        throw ArgumentError(
          'source url id end must be < ${sources.length}: $sourceUrlId',
        );
      }

      sourceString = sourceString.substring(colonPos + 1);
      int commaPos = sourceString.indexOf(',');
      sourceLine = int.parse(sourceString.substring(0, commaPos)) - 1;
      if (sourceLine < 0) {
        throw ArgumentError('source line end must be > 0: $sourceLine');
      }
      sourceString = sourceString.substring(commaPos + 1);
      sourceColumn = int.parse(sourceString) - 1;
      if (sourceColumn < 0) {
        throw ArgumentError('source column must be > 0: $sourceColumn');
      }
    }

    TargetLineEntry lineEntry = lineEntryMap.putIfAbsent(
      lineNo,
      () => TargetLineEntry(lineNo, []),
    );
    lineEntry.entries.add(
      TargetEntry(
        columnStart,
        sourceUrlId,
        sourceLine,
        sourceColumn,
        nameIndex,
      ),
    );
    if (columnEnd != null) {
      lineEntry.entries.add(TargetEntry(columnEnd));
    }
  }

  List<TargetLineEntry> lineEntries = lineEntryMap.values.toList();

  var outputMap = <String, dynamic>{
    'version': 3,
    'sourceRoot': inputMap['sourceRoot'],
    'file': inputMap['file'],
    'sources': sources,
    'names': names.keys.toList(),
    'mappings': '',
  };

  SingleMapping mapping = SingleMapping.fromJson(outputMap);
  mapping.lines.addAll(lineEntries);
  return mapping;
}
