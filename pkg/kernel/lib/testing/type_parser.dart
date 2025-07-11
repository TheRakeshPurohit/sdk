// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:kernel/ast.dart' show Nullability;

abstract class ParsedType {
  R accept<R, A>(Visitor<R, A> visitor, A a);
}

enum ParsedNullability {
  // Used when the type is declared with the '?' suffix.
  nullable,

  // Used when the type isn't known to be nullable or non-nullable.
  //
  // For example, the type `A` is such a type, given the declaration:
  //
  //     extension type A(int it);
  //
  // Since `A` doesn't implement `Object`, it's not non-nullable. At the same
  // time, it's not nullable either, since it doesn't end with a `?`.
  undetermined,

  // Used when the nullability suffix is omitted after the type declaration.
  omitted,
}

Nullability interpretParsedNullability(ParsedNullability parsedNullability,
    {Nullability ifOmitted = Nullability.nonNullable}) {
  switch (parsedNullability) {
    case ParsedNullability.nullable:
      return Nullability.nullable;
    case ParsedNullability.undetermined:
      return Nullability.undetermined;
    case ParsedNullability.omitted:
      return ifOmitted;
  }
}

String parsedNullabilityToString(ParsedNullability parsedNullability) {
  switch (parsedNullability) {
    case ParsedNullability.nullable:
      return '?';
    case ParsedNullability.undetermined:
      return '%';
    case ParsedNullability.omitted:
      return '';
  }
}

class ParsedNamedType extends ParsedType {
  final String name;

  final List<ParsedType> arguments;

  final ParsedNullability parsedNullability;

  ParsedNamedType(this.name, this.arguments, this.parsedNullability);

  @override
  String toString() {
    StringBuffer sb = new StringBuffer();
    sb.write(name);
    if (arguments.isNotEmpty) {
      sb.write("<");
      sb.writeAll(arguments, ", ");
      sb.write(">");
    }
    sb.write(parsedNullabilityToString(parsedNullability));
    return "$sb";
  }

  @override
  R accept<R, A>(Visitor<R, A> visitor, A a) {
    return visitor.visitNamedType(this, a);
  }
}

abstract class ParsedDeclaration extends ParsedType {
  final String name;

  ParsedDeclaration(this.name);
}

class ParsedClass extends ParsedDeclaration {
  final List<ParsedTypeVariable> typeVariables;
  final ParsedNamedType? supertype;
  final ParsedNamedType? mixedInType;
  final List<ParsedType> interfaces;
  final ParsedFunctionType? callableType;

  ParsedClass(String name, this.typeVariables, this.supertype, this.mixedInType,
      this.interfaces, this.callableType)
      : super(name);

  @override
  String toString() {
    StringBuffer sb = new StringBuffer();
    sb.write("class ");
    sb.write(name);
    if (typeVariables.isNotEmpty) {
      sb.write("<");
      sb.writeAll(typeVariables, ", ");
      sb.write(">");
    }
    if (supertype != null) {
      sb.write(" extends ");
      sb.write(supertype);
    }
    if (interfaces.isNotEmpty) {
      sb.write(" implements ");
      sb.writeAll(interfaces, ", ");
    }
    if (callableType != null) {
      sb.write("{\n  ");
      sb.write(callableType);
      sb.write("\n}");
    } else {
      sb.write(";");
    }
    return "$sb";
  }

  @override
  R accept<R, A>(Visitor<R, A> visitor, A a) {
    return visitor.visitClass(this, a);
  }
}

class ParsedExtension extends ParsedDeclaration {
  final List<ParsedTypeVariable> typeVariables;
  final ParsedNamedType onType;

  ParsedExtension(String name, this.typeVariables, this.onType) : super(name);

  @override
  String toString() {
    StringBuffer sb = new StringBuffer();
    sb.write("extension ");
    sb.write(name);
    if (typeVariables.isNotEmpty) {
      sb.write("<");
      sb.writeAll(typeVariables, ", ");
      sb.write(">");
    }
    sb.write(" on ");
    sb.write(onType);
    sb.write(";");
    return "$sb";
  }

  @override
  R accept<R, A>(Visitor<R, A> visitor, A a) {
    return visitor.visitExtension(this, a);
  }
}

class ParsedTypedef extends ParsedDeclaration {
  final List<ParsedTypeVariable> typeVariables;

  final ParsedType type;

  ParsedTypedef(String name, this.typeVariables, this.type) : super(name);

  @override
  String toString() {
    StringBuffer sb = new StringBuffer();
    sb.write("typedef ");
    sb.write(name);
    if (typeVariables.isNotEmpty) {
      sb.write("<");
      sb.writeAll(typeVariables, ", ");
      sb.write(">");
    }
    sb.write(" ");
    sb.write(type);
    return "$sb;";
  }

  @override
  R accept<R, A>(Visitor<R, A> visitor, A a) {
    return visitor.visitTypedef(this, a);
  }
}

class ParsedExtensionTypeDeclaration extends ParsedDeclaration {
  final List<ParsedTypeVariable> typeVariables;

  final ParsedType declaredRepresentationType;

  final List<ParsedType> interfaces;

  ParsedExtensionTypeDeclaration(String name, this.typeVariables,
      this.declaredRepresentationType, this.interfaces)
      : super(name);

  @override
  String toString() {
    StringBuffer sb = new StringBuffer();
    sb.write('extension type ');
    sb.write(name);
    if (typeVariables.isNotEmpty) {
      sb.write('<');
      sb.writeAll(typeVariables, ", ");
      sb.write('>');
    }
    sb.write('(');
    sb.write(declaredRepresentationType);
    sb.write(' it)');
    if (interfaces.isNotEmpty) {
      sb.write(' implements ');
      sb.writeAll(interfaces, ", ");
    }
    return "$sb;";
  }

  @override
  R accept<R, A>(Visitor<R, A> visitor, A a) {
    return visitor.visitExtensionTypeDeclaration(this, a);
  }
}

class ParsedFunctionType extends ParsedType {
  final List<ParsedTypeVariable> typeVariables;

  final ParsedType returnType;

  final ParsedArguments arguments;

  final ParsedNullability parsedNullability;

  ParsedFunctionType(this.typeVariables, this.returnType, this.arguments,
      this.parsedNullability);

  @override
  String toString() {
    StringBuffer sb = new StringBuffer();
    if (typeVariables.isNotEmpty) {
      sb.write("<");
      sb.writeAll(typeVariables, ", ");
      sb.write(">");
    }
    sb.write(arguments);
    sb.write(" ->");
    sb.write(parsedNullabilityToString(parsedNullability));
    sb.write(" ");
    sb.write(returnType);
    return "$sb";
  }

  @override
  R accept<R, A>(Visitor<R, A> visitor, A a) {
    return visitor.visitFunctionType(this, a);
  }
}

class ParsedRecordType extends ParsedType {
  final List<ParsedType> positional;
  final List<ParsedNamedArgument> named;
  final ParsedNullability parsedNullability;

  ParsedRecordType(this.positional, this.named, this.parsedNullability);

  @override
  String toString() {
    StringBuffer sb = new StringBuffer();
    sb.write("(");
    for (int i = 0; i < positional.length; i++) {
      if (i != 0) sb.write(", ");
      sb.write(positional[i]);
    }
    if (named.isNotEmpty) {
      if (positional.isNotEmpty) sb.write(", ");
      sb.write("{");
      for (int i = 0; i < named.length; i++) {
        if (i != 0) sb.write(", ");
        sb.write(named[i]);
      }
      sb.write("}");
    }
    sb.write(")");
    return "$sb";
  }

  @override
  R accept<R, A>(Visitor<R, A> visitor, A a) {
    return visitor.visitRecordType(this, a);
  }
}

class ParsedVoidType extends ParsedType {
  @override
  String toString() => "void";

  @override
  R accept<R, A>(Visitor<R, A> visitor, A a) {
    return visitor.visitVoidType(this, a);
  }
}

class ParsedTypeVariable extends ParsedType {
  final String name;

  final ParsedType? bound;

  ParsedTypeVariable(this.name, this.bound);

  @override
  String toString() {
    if (bound == null) return name;
    StringBuffer sb = new StringBuffer();
    sb.write(name);
    sb.write(" extends ");
    sb.write(bound);
    return "$sb";
  }

  @override
  R accept<R, A>(Visitor<R, A> visitor, A a) {
    return visitor.visitTypeVariable(this, a);
  }
}

class ParsedIntersectionType extends ParsedType {
  final ParsedType a;

  final ParsedType b;

  ParsedIntersectionType(this.a, this.b);

  @override
  String toString() {
    StringBuffer sb = new StringBuffer();
    sb.write(a);
    sb.write(" & ");
    sb.write(b);
    return "$sb";
  }

  @override
  R accept<R, A>(Visitor<R, A> visitor, A a) {
    return visitor.visitIntersectionType(this, a);
  }
}

class ParsedArguments {
  final List<ParsedType> required;
  final List<ParsedType> positional;
  final List<ParsedNamedArgument> named;

  ParsedArguments(this.required, this.positional, this.named)
      : assert(positional.isEmpty || named.isEmpty);

  @override
  String toString() {
    StringBuffer sb = new StringBuffer();
    sb.write("(");
    sb.writeAll(required, ", ");
    if (positional.isNotEmpty) {
      if (required.isNotEmpty) {
        sb.write(", ");
      }
      sb.write("[");
      sb.writeAll(positional, ", ");
      sb.write("]");
    } else if (named.isNotEmpty) {
      if (required.isNotEmpty) {
        sb.write(", ");
      }
      if (named.isNotEmpty) {
        sb.write("{");
        sb.writeAll(named, ", ");
        sb.write("}");
      }
    }
    sb.write(")");
    return "$sb";
  }
}

class ParsedNamedArgument {
  final bool isRequired;
  final ParsedType type;
  final String name;

  ParsedNamedArgument(this.isRequired, this.type, this.name);

  @override
  String toString() {
    StringBuffer sb = new StringBuffer();
    if (isRequired) {
      sb.write('required ');
    }
    sb.write(type);
    sb.write(' ');
    sb.write(name);
    return sb.toString();
  }
}

class Token {
  final int charOffset;
  final String? text;
  final bool isIdentifier;

  Token? next;

  Token(this.charOffset, this.text, {this.isIdentifier = false});

  bool get isEof => text == null;
}

class Parser {
  Token peek;

  String source;

  Parser(this.peek, this.source);

  bool get atEof => peek.isEof;

  void advance() {
    peek = peek.next!;
  }

  String computeLocation() {
    return "${source.substring(0, peek.charOffset)}\n>>>"
        "\n${source.substring(peek.charOffset)}";
  }

  void expect(String string) {
    if (string != peek.text) {
      throw "Expected '$string', "
          "but got '${peek.text}'\n${computeLocation()}";
    }
    advance();
  }

  bool optional(String value) {
    return value == peek.text;
  }

  bool optionalAdvance(String value) {
    if (optional(value)) {
      advance();
      return true;
    } else {
      return false;
    }
  }

  ParsedNullability parseNullability() {
    ParsedNullability result = ParsedNullability.omitted;
    if (optionalAdvance("?")) {
      result = ParsedNullability.nullable;
    } else if (optionalAdvance("%")) {
      result = ParsedNullability.undetermined;
    }
    return result;
  }

  ParsedType parseType() {
    if (optional("class")) return parseClass();
    if (optional("typedef")) return parseTypedef();
    if (optional("extension")) {
      expect("extension");
      if (optional("type")) {
        return parseExtensionTypeDeclaration();
      }
      return parseExtension();
    }
    List<ParsedType> results = <ParsedType>[];
    do {
      ParsedType type;
      if (optional("(") || optional("<")) {
        type = parseFunctionOrRecordType();
      } else if (optionalAdvance("void")) {
        type = new ParsedNamedType(
            "void", <ParsedType>[], ParsedNullability.nullable);
        optionalAdvance("?");
      } else if (optionalAdvance("invalid")) {
        type = new ParsedNamedType(
            "invalid", <ParsedType>[], ParsedNullability.nullable);
      } else {
        String name = parseName();
        List<ParsedType> arguments = <ParsedType>[];
        if (optional("<")) {
          advance();
          arguments.add(parseType());
          while (optional(",")) {
            advance();
            arguments.add(parseType());
          }
          expect(">");
        }
        ParsedNullability parsedNullability = parseNullability();
        type = new ParsedNamedType(name, arguments, parsedNullability);
      }
      results.add(type);
    } while (optionalAdvance("&"));
    // Parse `A & B & C` as `A & (B & C)` and not `(A & B) & C`.
    ParsedType? result;
    for (ParsedType type in results.reversed) {
      if (result == null) {
        result = type;
      } else {
        result = new ParsedIntersectionType(type, result);
      }
    }
    return result!;
  }

  ParsedType parseReturnType() {
    if (optionalAdvance("void")) return new ParsedVoidType();
    return parseType();
  }

  ParsedType /* ParsedFunctionType|ParsedRecordType */
      parseFunctionOrRecordType() {
    List<ParsedTypeVariable> typeVariables = parseTypeVariablesOpt();
    ParsedArguments arguments = parseArguments();
    if (optional("-")) {
      // FunctionType.
      expect("-");
      expect(">");
      ParsedNullability parsedNullability = parseNullability();
      ParsedType returnType = parseReturnType();
      return new ParsedFunctionType(
          typeVariables, returnType, arguments, parsedNullability);
    } else {
      // RecordType.
      if (typeVariables.isNotEmpty) {
        throw "Type variables are detected on a record type.";
      }
      if (arguments.positional.isNotEmpty) {
        throw "Records can't have optional positional fields.";
      }
      ParsedNullability parsedNullability = parseNullability();
      return new ParsedRecordType(
          arguments.required, arguments.named, parsedNullability);
    }
  }

  String parseName() {
    if (!peek.isIdentifier) {
      throw "Expected a name, "
          "but got '${peek.text}'\n${computeLocation()}";
    }
    String result = peek.text!;
    advance();
    return result;
  }

  ParsedArguments parseArguments() {
    List<ParsedType> requiredArguments = <ParsedType>[];
    List<ParsedType> positionalArguments = <ParsedType>[];
    List<ParsedNamedArgument> namedArguments = <ParsedNamedArgument>[];
    expect("(");
    do {
      if (optional(")")) break;
      if (optionalAdvance("[")) {
        do {
          positionalArguments.add(parseType());
        } while (optionalAdvance(","));
        expect("]");
        break;
      } else if (optionalAdvance("{")) {
        do {
          bool isRequired = optionalAdvance("required");
          ParsedType type = parseType();
          String name = parseName();
          namedArguments.add(new ParsedNamedArgument(isRequired, type, name));
        } while (optionalAdvance(","));
        expect("}");
        break;
      } else {
        requiredArguments.add(parseType());
      }
    } while (optionalAdvance(","));
    expect(")");
    return new ParsedArguments(
        requiredArguments, positionalArguments, namedArguments);
  }

  List<ParsedTypeVariable> parseTypeVariablesOpt() {
    List<ParsedTypeVariable> typeVariables = <ParsedTypeVariable>[];
    if (optionalAdvance("<")) {
      do {
        typeVariables.add(parseTypeVariable());
      } while (optionalAdvance(","));
      expect(">");
    }
    return typeVariables;
  }

  ParsedTypeVariable parseTypeVariable() {
    String name = parseName();
    ParsedType? bound;
    if (optionalAdvance("extends")) {
      bound = parseType();
    }
    return new ParsedTypeVariable(name, bound);
  }

  ParsedClass parseClass() {
    expect("class");
    String name = parseName();
    List<ParsedTypeVariable> typeVariables = parseTypeVariablesOpt();
    ParsedNamedType? supertype;
    ParsedNamedType? mixedInType;
    if (optionalAdvance("extends")) {
      supertype = parseType() as ParsedNamedType;
      if (optionalAdvance("with")) {
        mixedInType = parseType() as ParsedNamedType;
      }
    }
    List<ParsedType> interfaces = <ParsedType>[];
    if (optionalAdvance("implements")) {
      do {
        interfaces.add(parseType());
      } while (optionalAdvance(","));
    }
    ParsedFunctionType? callableType;
    if (optionalAdvance("{")) {
      callableType = parseFunctionOrRecordType() as ParsedFunctionType?;
      expect("}");
    } else {
      expect(";");
    }
    return new ParsedClass(
        name, typeVariables, supertype, mixedInType, interfaces, callableType);
  }

  ParsedExtension parseExtension() {
    String name = parseName();
    List<ParsedTypeVariable> typeVariables = parseTypeVariablesOpt();
    expect("on");
    ParsedNamedType onType = parseType() as ParsedNamedType;
    expect(";");
    return new ParsedExtension(name, typeVariables, onType);
  }

  ParsedExtensionTypeDeclaration parseExtensionTypeDeclaration() {
    expect("type");
    String name = parseName();
    List<ParsedTypeVariable> typeVariables = parseTypeVariablesOpt();
    expect("(");
    ParsedType declaredRepresentationType = parseType();
    expect("it");
    expect(")");
    List<ParsedType> interfaces = <ParsedType>[];
    if (optionalAdvance("implements")) {
      do {
        interfaces.add(parseType());
      } while (optionalAdvance(","));
    }
    expect(";");
    return new ParsedExtensionTypeDeclaration(
        name, typeVariables, declaredRepresentationType, interfaces);
  }

  /// This parses a general typedef on this form:
  ///
  ///     typedef <name> <type-variables-opt> <type> ;
  ///
  /// This is unlike Dart typedef.
  ParsedTypedef parseTypedef() {
    expect("typedef");
    String name = parseName();
    List<ParsedTypeVariable> typeVariables = parseTypeVariablesOpt();
    ParsedType type = parseType();
    expect(";");
    return new ParsedTypedef(name, typeVariables, type);
  }
}

final int codeUnitUppercaseA = 'A'.codeUnitAt(0);
final int codeUnitUppercaseZ = 'Z'.codeUnitAt(0);

bool isUppercaseLetter(int c) =>
    codeUnitUppercaseA <= c && c <= codeUnitUppercaseZ;

final int codeUnitLowercaseA = 'a'.codeUnitAt(0);
final int codeUnitLowercaseZ = 'z'.codeUnitAt(0);

bool isLowercaseLetter(int c) =>
    codeUnitLowercaseA <= c && c <= codeUnitLowercaseZ;

final int codeUnitUnderscore = '_'.codeUnitAt(0);

bool isUnderscore(int c) => c == codeUnitUnderscore;

final int codeUnit0 = '0'.codeUnitAt(0);
final int codeUnit9 = '9'.codeUnitAt(0);

bool isNumber(int c) => codeUnit0 <= c && c <= codeUnit9;

bool isNameStart(int c) =>
    isUppercaseLetter(c) || isLowercaseLetter(c) || isUnderscore(c);

bool isNamePart(int c) => isNameStart(c) || isNumber(c);

final int codeUnitLineFeed = '\n'.codeUnitAt(0);
final int codeUnitCarriageReturn = '\r'.codeUnitAt(0);
final int codeUnitTab = '\t'.codeUnitAt(0);
final int codeUnitSpace = ' '.codeUnitAt(0);

bool isWhiteSpace(int c) =>
    c == codeUnitCarriageReturn ||
    c == codeUnitLineFeed ||
    c == codeUnitTab ||
    c == codeUnitSpace;

Token scanString(String text) {
  int offset = 0;
  Token? first;
  Token? current;
  while (offset < text.length) {
    int c = text.codeUnitAt(offset);
    if (isWhiteSpace(c)) {
      offset++;
      continue;
    }
    Token token;
    if (isNameStart(c)) {
      int startOffset = offset;
      offset++;
      while (offset < text.length) {
        int c = text.codeUnitAt(offset);
        if (isNamePart(c)) {
          offset++;
        } else {
          break;
        }
      }
      token = new Token(startOffset, text.substring(startOffset, offset),
          isIdentifier: true);
    } else {
      token = new Token(offset, text.substring(offset, offset + 1));
      offset += 1;
    }
    first ??= token;
    current?.next = token;
    current = token;
  }
  Token eof = new Token(offset, null);
  if (current == null) {
    current = first = eof;
  } else {
    current.next = eof;
  }
  return first!;
}

List<ParsedType> parse(String text) {
  Parser parser = new Parser(scanString(text), text);
  List<ParsedType> types = <ParsedType>[];
  while (!parser.atEof) {
    types.add(parser.parseType());
  }
  return types;
}

List<ParsedTypeVariable> parseTypeVariables(String text) {
  Parser parser = new Parser(scanString(text), text);
  List<ParsedTypeVariable> result = parser.parseTypeVariablesOpt();
  if (!parser.atEof) {
    throw "Expected EOF, but got '${parser.peek.text}'\n"
        "${parser.computeLocation()}";
  }
  return result;
}

abstract class Visitor<R, A> {
  R visitNamedType(ParsedNamedType node, A a);

  R visitClass(ParsedClass node, A a);

  R visitExtension(ParsedExtension node, A a);

  R visitExtensionTypeDeclaration(ParsedExtensionTypeDeclaration node, A a);

  R visitTypedef(ParsedTypedef node, A a);

  R visitFunctionType(ParsedFunctionType node, A a);

  R visitRecordType(ParsedRecordType node, A a);

  R visitVoidType(ParsedVoidType node, A a);

  R visitTypeVariable(ParsedTypeVariable node, A a);

  R visitIntersectionType(ParsedIntersectionType node, A a);
}
