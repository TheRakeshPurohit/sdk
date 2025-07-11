// Copyright (c) 2014, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Code generation for the file "AnalysisServer.java".
library;

import 'package:analyzer_utilities/html_dom.dart' as dom;
import 'package:analyzer_utilities/tools.dart';

import 'api.dart';
import 'codegen_java.dart';
import 'from_html.dart';
import 'implied_types.dart';

/// A map between the field names and values for the Element object such as:
///
/// private static final int ABSTRACT = 0x01;
const Map<String, String> _extraFieldsOnElement = {
  'ABSTRACT': '0x01',
  'CONST': '0x02',
  'FINAL': '0x04',
  'TOP_LEVEL_STATIC': '0x08',
  'PRIVATE': '0x10',
  'DEPRECATED': '0x20',
};

/// A map between the method names and field names to generate additional
/// methods on the Element object:
///
/// public boolean isFinal() {
///   return (flags & FINAL) != 0;
/// }
const Map<String, String> _extraMethodsOnElement = {
  'isAbstract': 'ABSTRACT',
  'isConst': 'CONST',
  'isDeprecated': 'DEPRECATED',
  'isFinal': 'FINAL',
  'isPrivate': 'PRIVATE',
  'isTopLevelOrStatic': 'TOP_LEVEL_STATIC',
};

/// Type references in the spec that are named something else in Java.
const Map<String, String> _typeRenames = {'Override': 'OverrideMember'};

final String pathToGenTypes = 'analysis_server/tool/spec/generated/java/types';

final GeneratedDirectory targetDir = GeneratedDirectory(pathToGenTypes, (
  pkgRoot,
) {
  var api = readApi(pkgRoot);
  var impliedTypes = computeImpliedTypes(api);
  var map = <String, FileContentsComputer>{};
  for (var impliedType in impliedTypes.values) {
    var typeNameInSpec = capitalize(impliedType.camelName);
    var isRefactoringFeedback = impliedType.kind == 'refactoringFeedback';
    var isRefactoringOption = impliedType.kind == 'refactoringOptions';
    if (impliedType.kind == 'typeDefinition' ||
        isRefactoringFeedback ||
        isRefactoringOption) {
      var type = impliedType.type;
      if (type != null && (type is TypeObject || type is TypeEnum)) {
        // This is for situations such as 'Override' where the name in the spec
        // doesn't match the java object that we generate:
        var typeNameInJava = typeNameInSpec;
        var renamedTo = _typeRenames[typeNameInSpec];
        if (renamedTo != null) {
          typeNameInJava = renamedTo;
        }
        map['$typeNameInJava.java'] = (pkgRoot) async {
          String? superclassName;
          if (isRefactoringFeedback) {
            superclassName = 'RefactoringFeedback';
          }
          if (isRefactoringOption) {
            superclassName = 'RefactoringOptions';
          }
          // configure accessors
          var generateGetters = true;
          var generateSetters = false;
          if (isRefactoringOption ||
              typeNameInSpec == 'Outline' ||
              typeNameInSpec == 'RefactoringMethodParameter') {
            generateSetters = true;
          }
          // create the visitor
          var visitor = CodegenJavaType(
            api,
            typeNameInJava,
            superclassName,
            generateGetters,
            generateSetters,
          );
          return visitor.collectCode(() {
            var doc = type.html;
            if (impliedType.apiNode is TypeDefinition) {
              doc = (impliedType.apiNode as TypeDefinition).html;
            }
            visitor.emitType(type, doc);
          });
        };
      }
    }
  }
  return map;
});

class CodegenJavaType extends CodegenJavaVisitor {
  final String className;
  final String? superclassName;
  final bool generateGetters;
  final bool generateSetters;

  CodegenJavaType(
    super.api,
    this.className,
    this.superclassName,
    this.generateGetters,
    this.generateSetters,
  );

  /// Get the name of the consumer class for responses to this request.
  @override
  String consumerName(Request request) {
    return camelJoin([request.method, 'consumer'], doCapitalize: true);
  }

  void emitType(TypeDecl type, dom.Element? html) {
    outputHeader(javaStyle: true);
    writeln('package org.dartlang.analysis.server.protocol;');
    writeln();
    if (type is TypeObject) {
      _writeTypeObject(type, html);
    } else if (type is TypeEnum) {
      _writeTypeEnum(type, html);
    }
  }

  String _getAsTypeMethodName(TypeDecl typeDecl) {
    var name = javaType(typeDecl, true);
    if (name == 'String') {
      return 'getAsString';
    } else if (name == 'boolean' || name == 'Boolean') {
      return 'getAsBoolean';
    } else if (name == 'double' || name == 'Double') {
      return 'getAsDouble';
    } else if (name == 'int' || name == 'Integer') {
      return 'getAsInt';
    } else if (name == 'long' || name == 'Long') {
      return 'getAsLong';
    } else if (name.startsWith('List') || name.endsWith('[]')) {
      return 'getAsJsonArray';
    }

    throw StateError('Unexpected type for _getAsTypeMethodName: $name');
  }

  String _getEqualsLogicForField(TypeObjectField field, String other) {
    var name = javaName(field.name);
    if (isPrimitive(field.type) && !field.optional) {
      return '$other.$name == $name';
    } else if (isArray(field.type)) {
      return 'Arrays.equals(other.$name, $name)';
    } else {
      return 'Objects.equals($other.$name, $name)';
    }
  }

  /// For some [TypeObjectField] return the [String] source for the field value
  /// for the toString generation.
  String _getToStringForField(TypeObjectField field) {
    var name = javaName(field.name);
    if (isArray(field.type)) {
      var combined =
          'Arrays.stream($name)'
          '.mapToObj(String::valueOf)'
          '.collect(Collectors.joining(", "))';
      return field.optional ? '$name == null ? "null" : $combined' : combined;
    } else if (isList(field.type)) {
      var combined =
          '$name.stream()'
          '.map(String::valueOf)'
          '.collect(Collectors.joining(", "))';
      return field.optional ? '$name == null ? "null" : $combined' : combined;
    }

    return name;
  }

  bool _isTypeFieldInUpdateContentUnionType(
    String className,
    String fieldName,
  ) {
    if ((className == 'AddContentOverlay' ||
            className == 'ChangeContentOverlay' ||
            className == 'RemoveContentOverlay') &&
        fieldName == 'type') {
      return true;
    } else {
      return false;
    }
  }

  /// This method writes extra fields and methods to the Element type.
  void _writeExtraContentInElementType() {
    //
    // Extra fields on the Element type such as:
    // private static final int ABSTRACT = 0x01;
    //
    _extraFieldsOnElement.forEach((String name, String value) {
      publicField(javaName(name), () {
        writeln('private static final int $name = $value;');
      });
    });

    //
    // Extra methods for the Element type such as:
    // public boolean isFinal() {
    //   return (flags & FINAL) != 0;
    // }
    //
    _extraMethodsOnElement.forEach((String methodName, String fieldName) {
      publicMethod(methodName, () {
        writeln('public boolean $methodName() {');
        writeln('  return (flags & $fieldName) != 0;');
        writeln('}');
      });
    });
  }

  /// For some [TypeObjectField] write out the source that adds the field
  /// information to the 'jsonObject'.
  void _writeOutJsonObjectAddStatement(TypeObjectField field) {
    var name = javaName(field.name);
    if (isDeclaredInSpec(field.type)) {
      writeln('jsonObject.add("$name", $name.toJson());');
    } else if (field.type is TypeList) {
      var listItemType = (field.type as TypeList).itemType;
      var jsonArrayName = 'jsonArray${capitalize(name)}';
      writeln('JsonArray $jsonArrayName = new JsonArray();');
      writeln('for (${javaType(listItemType)} elt : $name) {');
      indent(() {
        if (isDeclaredInSpec(listItemType)) {
          writeln('$jsonArrayName.add(elt.toJson());');
        } else {
          writeln('$jsonArrayName.add(new JsonPrimitive(elt));');
        }
      });
      writeln('}');
      writeln('jsonObject.add("$name", $jsonArrayName);');
    } else {
      writeln('jsonObject.addProperty("$name", $name);');
    }
  }

  void _writeTypeEnum(TypeDecl type, dom.Element? html) {
    javadocComment(
      toHtmlVisitor.collectHtml(() {
        toHtmlVisitor.translateHtml(html);
        toHtmlVisitor.br();
        toHtmlVisitor.write('@coverage dart.server.generated.types');
      }),
    );
    makeClass('public class $className', () {
      var typeEnum = type as TypeEnum;
      var values = typeEnum.values;
      //
      // enum fields
      //
      for (var value in values) {
        privateField(javaName(value.value), () {
          javadocComment(
            toHtmlVisitor.collectHtml(() {
              toHtmlVisitor.translateHtml(value.html);
            }),
          );
          writeln(
            'public static final String ${value.value} = "${value.value}";',
          );
        });
      }
    });
  }

  void _writeTypeObject(TypeDecl type, dom.Element? html) {
    writeln('import java.util.Arrays;');
    writeln('import java.util.ArrayList;');
    writeln('import java.util.List;');
    writeln('import java.util.Map;');
    writeln('import java.util.Objects;');
    writeln('import java.util.stream.Collectors;');
    writeln('import com.google.dart.server.utilities.general.JsonUtilities;');
    writeln('import com.google.gson.JsonArray;');
    writeln('import com.google.gson.JsonElement;');
    writeln('import com.google.gson.JsonObject;');
    writeln('import com.google.gson.JsonPrimitive;');
    writeln();
    javadocComment(
      toHtmlVisitor.collectHtml(() {
        toHtmlVisitor.translateHtml(html);
        toHtmlVisitor.br();
        toHtmlVisitor.write('@coverage dart.server.generated.types');
      }),
    );
    writeln('@SuppressWarnings("unused")');
    var header = 'public class $className';
    if (superclassName != null) {
      header += ' extends $superclassName';
    }
    makeClass(header, () {
      //
      // fields
      //

      //
      // public static final "EMPTY_LIST" field
      //
      publicField(javaName('EMPTY_LIST'), () {
        writeln('public static final List<$className> EMPTY_LIST = List.of();');
      });

      //
      // "private static String name;" fields:
      //
      var typeObject = type as TypeObject;
      var fields = typeObject.fields;
      for (var field in fields) {
        var type = javaFieldType(field);
        var name = javaName(field.name);
        if (!(className == 'Outline' && name == 'children')) {
          privateField(name, () {
            javadocComment(
              toHtmlVisitor.collectHtml(() {
                toHtmlVisitor.translateHtml(field.html);
              }),
            );
            if (generateSetters) {
              writeln('private $type $name;');
            } else {
              writeln('private final $type $name;');
            }
          });
        }
      }
      if (className == 'Outline') {
        privateField(javaName('parent'), () {
          writeln('private final Outline parent;');
        });
        privateField(javaName('children'), () {
          writeln('private List<Outline> children;');
        });
      }
      if (className == 'NavigationRegion') {
        privateField(javaName('targetObjects'), () {
          writeln(
            'private final List<NavigationTarget> targetObjects = new ArrayList<>();',
          );
        });
      }
      if (className == 'NavigationTarget') {
        privateField(javaName('file'), () {
          writeln('private String file;');
        });
      }

      //
      // constructor
      //
      constructor(className, () {
        javadocComment(
          toHtmlVisitor.collectHtml(() {
            toHtmlVisitor.write('Constructor for {@link $className}.');
          }),
        );
        write('public $className(');
        // write out parameters to constructor
        var parameters = <String>[];
        if (className == 'Outline') {
          parameters.add('Outline parent');
        }
        for (var field in fields) {
          var type = javaFieldType(field);
          var name = javaName(field.name);
          if (!_isTypeFieldInUpdateContentUnionType(className, field.name) &&
              !(className == 'Outline' && name == 'children')) {
            parameters.add('$type $name');
          }
        }
        write(parameters.join(', '));
        writeln(') {');
        // write out the assignments in the body of the constructor
        indent(() {
          if (className == 'Outline') {
            writeln('this.parent = parent;');
          }
          for (var field in fields) {
            var name = javaName(field.name);
            if (!_isTypeFieldInUpdateContentUnionType(className, field.name) &&
                !(className == 'Outline' && name == 'children')) {
              writeln('this.$name = $name;');
            } else if (className == 'AddContentOverlay') {
              writeln('this.type = "add";');
            } else if (className == 'ChangeContentOverlay') {
              writeln('this.type = "change";');
            } else if (className == 'RemoveContentOverlay') {
              writeln('this.type = "remove";');
            }
          }
        });
        writeln('}');
      });

      //
      // getter methods
      //
      if (generateGetters) {
        for (var field in fields) {
          var type = javaFieldType(field);
          var name = javaName(field.name);
          publicMethod('get$name', () {
            javadocComment(
              toHtmlVisitor.collectHtml(() {
                toHtmlVisitor.translateHtml(field.html);
              }),
            );
            if (type == 'boolean') {
              writeln('public $type $name() {');
            } else {
              writeln('public $type get${capitalize(name)}() {');
            }
            writeln('  return $name;');
            writeln('}');
          });
        }
      }

      //
      // setter methods
      //
      if (generateSetters) {
        for (var field in fields) {
          var type = javaFieldType(field);
          var name = javaName(field.name);
          publicMethod('set$name', () {
            javadocComment(
              toHtmlVisitor.collectHtml(() {
                toHtmlVisitor.translateHtml(field.html);
              }),
            );
            var setterName = 'set${capitalize(name)}';
            writeln('public void $setterName($type $name) {');
            writeln('  this.$name = $name;');
            writeln('}');
          });
        }
      }

      if (className == 'NavigationRegion') {
        publicMethod('lookupTargets', () {
          writeln(
            'public void lookupTargets(List<NavigationTarget> allTargets) {',
          );
          writeln('  for (int targetIndex : targets) {');
          writeln('    NavigationTarget target = allTargets.get(targetIndex);');
          writeln('    targetObjects.add(target);');
          writeln('  }');
          writeln('}');
        });
        publicMethod('getTargetObjects', () {
          writeln('public List<NavigationTarget> getTargetObjects() {');
          writeln('  return targetObjects;');
          writeln('}');
        });
      }
      if (className == 'NavigationTarget') {
        publicMethod('lookupFile', () {
          writeln('public void lookupFile(String[] allTargetFiles) {');
          writeln('  file = allTargetFiles[fileIndex];');
          writeln('}');
        });
        publicMethod('getFile', () {
          writeln('public String getFile() {');
          writeln('  return file;');
          writeln('}');
        });
      }

      //
      // fromJson(JsonObject) factory constructor, example:
      //      public JsonObject toJson(JsonObject jsonObject) {
      //          String x = jsonObject.get("x").getAsString();
      //          return new Y(x);
      //        }
      if (className != 'Outline') {
        publicMethod('fromJson', () {
          writeln('public static $className fromJson(JsonObject jsonObject) {');
          indent(() {
            for (var field in fields) {
              write('${javaFieldType(field)} ${javaName(field.name)} = ');
              if (field.optional) {
                write(
                  'jsonObject.get("${javaName(field.name)}") == null ? null : ',
                );
              }
              if (isDeclaredInSpec(field.type)) {
                write('${javaFieldType(field)}.fromJson(');
                write(
                  'jsonObject.get("${javaName(field.name)}").getAsJsonObject())',
                );
              } else {
                if (isList(field.type)) {
                  if (javaFieldType(field).endsWith('<String>')) {
                    write(
                      'JsonUtilities.decodeStringList(jsonObject.get("${javaName(field.name)}").${_getAsTypeMethodName(field.type)}())',
                    );
                  } else {
                    write(
                      '${javaType((field.type as TypeList).itemType)}.fromJsonArray(jsonObject.get("${javaName(field.name)}").${_getAsTypeMethodName(field.type)}())',
                    );
                  }
                } else if (isArray(field.type)) {
                  if (javaFieldType(field).startsWith('int')) {
                    write(
                      'JsonUtilities.decodeIntArray(jsonObject.get("${javaName(field.name)}").${_getAsTypeMethodName(field.type)}())',
                    );
                  }
                } else {
                  write(
                    'jsonObject.get("${javaName(field.name)}").${_getAsTypeMethodName(field.type)}()',
                  );
                }
              }
              writeln(';');
            }
            write('return new $className(');
            var parameters = <String>[];
            for (var field in fields) {
              if (!_isTypeFieldInUpdateContentUnionType(
                className,
                field.name,
              )) {
                parameters.add(javaName(field.name));
              }
            }
            write(parameters.join(', '));
            writeln(');');
          });
          writeln('}');
        });
      } else {
        publicMethod('fromJson', () {
          writeln(
            '''public static Outline fromJson(Outline parent, JsonObject outlineObject) {
  JsonObject elementObject = outlineObject.get("element").getAsJsonObject();
  Element element = Element.fromJson(elementObject);
  int offset = outlineObject.get("offset").getAsInt();
  int length = outlineObject.get("length").getAsInt();
  int codeOffset = outlineObject.get("codeOffset").getAsInt();
  int codeLength = outlineObject.get("codeLength").getAsInt();

  // create outline object
  Outline outline = new Outline(parent, element, offset, length, codeOffset, codeLength);

  // compute children recursively
  List<Outline> childrenList = new ArrayList<>();
  JsonElement childrenJsonArray = outlineObject.get("children");
  if (childrenJsonArray instanceof JsonArray jsonChildren) {
    for (JsonElement jsonElement : jsonChildren) {
      JsonObject childObject = jsonElement.getAsJsonObject();
      childrenList.add(fromJson(outline, childObject));
    }
  }
  outline.setChildren(childrenList);
  return outline;
}''',
          );
        });
        publicMethod('getParent', () {
          writeln('''public Outline getParent() {
  return parent;
}''');
        });
      }

      //
      // fromJson(JsonArray) factory constructor
      //
      if (className != 'Outline' &&
          className != 'RefactoringFeedback' &&
          className != 'RefactoringOptions') {
        publicMethod('fromJsonArray', () {
          writeln(
            'public static List<$className> fromJsonArray(JsonArray jsonArray) {',
          );
          indent(() {
            writeln('if (jsonArray == null) {');
            writeln('  return EMPTY_LIST;');
            writeln('}');
            writeln(
              'List<$className> list = new ArrayList<>(jsonArray.size());',
            );
            writeln('for (final JsonElement element : jsonArray) {');
            writeln('  list.add(fromJson(element.getAsJsonObject()));');
            writeln('}');
            writeln('return list;');
          });
          writeln('}');
        });
      }

      //
      // toJson() method, example:
      //      public JsonObject toJson() {
      //          JsonObject jsonObject = new JsonObject();
      //          jsonObject.addProperty("x", x);
      //          jsonObject.addProperty("y", y);
      //          return jsonObject;
      //        }
      if (className != 'Outline') {
        publicMethod('toJson', () {
          if (superclassName != null) {
            writeln('@Override');
          }
          writeln('public JsonObject toJson() {');
          indent(() {
            writeln('JsonObject jsonObject = new JsonObject();');
            for (var field in fields) {
              if (!isObject(field.type)) {
                if (field.optional) {
                  writeln('if (${javaName(field.name)} != null) {');
                  indent(() {
                    _writeOutJsonObjectAddStatement(field);
                  });
                  writeln('}');
                } else {
                  _writeOutJsonObjectAddStatement(field);
                }
              }
            }
            writeln('return jsonObject;');
          });
          writeln('}');
        });
      }

      //
      // equals() method
      //
      publicMethod('equals', () {
        writeln('@Override');
        writeln('public boolean equals(Object obj) {');
        indent(() {
          writeln('if (obj instanceof $className other) {');
          indent(() {
            writeln('return');
            indent(() {
              var equalsForField = <String>[];
              for (var field in fields) {
                equalsForField.add(_getEqualsLogicForField(field, 'other'));
              }
              if (equalsForField.isNotEmpty) {
                write(equalsForField.join(' && \n'));
              } else {
                write('true');
              }
            });
            writeln(';');
          });
          writeln('}');
          writeln('return false;');
        });
        writeln('}');
      });

      //
      // containsInclusive(int x)
      //
      if (className == 'HighlightRegion' ||
          className == 'NavigationRegion' ||
          className == 'Outline') {
        publicMethod('containsInclusive', () {
          writeln('public boolean containsInclusive(int x) {');
          indent(() {
            writeln('return offset <= x && x <= offset + length;');
          });
          writeln('}');
        });
      }

      //
      // contains(int x)
      //
      if (className == 'Occurrences') {
        publicMethod('containsInclusive', () {
          writeln('public boolean containsInclusive(int x) {');
          indent(() {
            writeln('for (int offset : offsets) {');
            writeln('  if (offset <= x && x <= offset + length) {');
            writeln('    return true;');
            writeln('  }');
            writeln('}');
            writeln('return false;');
          });
          writeln('}');
        });
      }

      //
      // hashCode
      //
      publicMethod('hashCode', () {
        writeln('@Override');
        writeln('public int hashCode() {');
        indent(() {
          write('return Objects.hash(');
          if (fields.isNotEmpty) {
            writeln();
          }
          for (var i = 0; i < fields.length; i++) {
            var field = fields[i];
            indent(() {
              var fieldName = javaName(field.name);
              if (isArray(field.type)) {
                write('Arrays.hashCode($fieldName)');
              } else {
                write(fieldName);
              }
              if (i + 1 != fields.length) {
                write(', ');
              }
              writeln();
            });
          }
          writeln(');');
        });
        writeln('}');
      });

      //
      // toString
      //
      publicMethod('toString', () {
        writeln('@Override');
        writeln('public String toString() {');
        indent(() {
          writeln('StringBuilder builder = new StringBuilder();');
          writeln('builder.append("[");');
          for (var i = 0; i < fields.length; i++) {
            writeln('builder.append("${javaName(fields[i].name)}=");');
            writeln('builder.append(${_getToStringForField(fields[i])});');
            if (i + 1 != fields.length) {
              // This is not the last field, so append a comma.
              writeln('builder.append(", ");');
            }
          }
          writeln('builder.append("]");');
          writeln('return builder.toString();');
        });
        writeln('}');
      });

      if (className == 'Element') {
        _writeExtraContentInElementType();
      }

      //
      // getBestName()
      //
      if (className == 'TypeHierarchyItem') {
        publicMethod('getBestName', () {
          writeln('public String getBestName() {');
          indent(() {
            writeln('if (displayName == null) {');
            writeln('  return classElement.getName();');
            writeln('} else {');
            writeln('  return displayName;');
            writeln('}');
          });
          writeln('}');
        });
      }
    });
  }
}
