// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/src/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_dart.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_yaml.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_workspace.dart';

/// A builder used to build a [SourceChange].
///
/// Clients may not extend, implement or mix-in this class.
abstract class ChangeBuilder {
  /// Initializes a newly created change builder.
  ///
  /// If the builder is used to create changes for Dart files, then either a
  /// [session] or a [workspace] must be provided (but not both).
  ///
  /// Note that omitting [eol], the EOL sequence to use, can result in
  /// inconsistent EOL sequences being added to files.
  // TODO(srawlins): Should `eol` be required? Each `DartFileEditBuilderImpl`
  //  has a `ResolvedUnitResult` that can be relied on to detect the existing
  //  EOL sequences, so could `eol` be removed? (dantup: but non-Dart builders?)
  factory ChangeBuilder(
      {AnalysisSession session,
      ChangeWorkspace workspace,
      String eol}) = ChangeBuilderImpl;

  /// Return the range of the selection for the change being built, or `null` if
  /// there is no selection.
  SourceRange? get selectionRange;

  /// Return the source change that was built. The source change will not be
  /// complete until all of the futures returned by the add*FileEdit methods
  /// have completed.
  SourceChange get sourceChange;

  /// Use the [buildFileEdit] function to create a collection of edits to the
  /// file with the given [path]. The edits will be added to the source change
  /// that is being built.
  ///
  /// The builder passed to the [buildFileEdit] function has additional support
  /// for working with Dart source files.
  ///
  /// Setting [createEditsForImports] to `false` will prevent edits being
  /// produced to add `import` statements for any unimported types.
  Future<void> addDartFileEdit(String path,
      FutureOr<void> Function(DartFileEditBuilder builder) buildFileEdit,
      {@Deprecated('No longer supported')
      ImportPrefixGenerator importPrefixGenerator,
      bool createEditsForImports = true});

  /// Use the [buildFileEdit] function to create a collection of edits to the
  /// file with the given [path]. The edits will be added to the source change
  /// that is being built.
  ///
  /// The builder passed to the [buildFileEdit] function has no special support
  /// for any particular kind of file.
  Future<void> addGenericFileEdit(
      String path, void Function(FileEditBuilder builder) buildFileEdit);

  /// Use the [buildFileEdit] function to create a collection of edits to the
  /// file with the given [path]. The edits will be added to the source change
  /// that is being built.
  ///
  /// The builder passed to the [buildFileEdit] function has additional support
  /// for working with YAML source files.
  Future<void> addYamlFileEdit(
      String path, void Function(YamlFileEditBuilder builder) buildFileEdit);

  /// Return a copy of this change builder that is constructed in such as was
  /// that changes to the copy will not effect this change builder.
  @Deprecated('Copying change builders is expensive, so it is no longer '
      'supported. There is no replacement.')
  ChangeBuilder copy();

  /// Return `true` if this builder already has edits for the file with the
  /// given [path].
  bool hasEditsFor(String path);

  /// Set the selection for the change being built to the given [position].
  void setSelection(Position position);
}

/// A builder used to build a [SourceEdit] as part of a [SourceFileEdit].
///
/// Clients may not extend, implement or mix-in this class.
abstract class EditBuilder {
  /// Add a region of text that is part of the linked edit group with the given
  /// [groupName]. The [buildLinkedEdit] function is used to write the content
  /// of the region of text and to add suggestions for other possible values for
  /// that region.
  void addLinkedEdit(String groupName,
      void Function(LinkedEditBuilder builder) buildLinkedEdit);

  /// Add the given text as a linked edit group with the given [groupName]. If
  /// both a [kind] and a list of [suggestions] are provided, they will be added
  /// as suggestions to the group with the given kind.
  ///
  /// Throws an [ArgumentError] if either [kind] or [suggestions] are provided
  /// without the other.
  void addSimpleLinkedEdit(String groupName, String text,
      {LinkedEditSuggestionKind kind, List<String> suggestions});

  /// Set the selection to cover all of the code written by the given [writer].
  void selectAll(void Function() writer);

  /// Set the selection to the current location within the edit being built.
  void selectHere();

  /// Add the given [string] to the content of the current edit.
  void write(String string);

  /// Add the given [string] to the content of the current edit and then add an
  /// end-of-line marker.
  void writeln([String string]);
}

/// A builder used to build a [SourceFileEdit] within a [SourceChange].
///
/// Clients may not extend, implement or mix-in this class.
abstract class FileEditBuilder {
  /// Add a deletion of text specified by the given [range]. The [range] is
  /// relative to the original source. This is fully equivalent to
  ///
  ///     addSimpleReplacement(range, '');
  void addDeletion(SourceRange range);

  /// Add an insertion of text at the given [offset]. The [offset] is relative
  /// to the original source. The [buildEdit] function is used to write the text
  /// to be inserted. This is fully equivalent to
  ///
  ///     addReplacement(new SourceRange(offset, 0), buildEdit);
  void addInsertion(int offset, void Function(EditBuilder builder) buildEdit);

  /// Add the region of text specified by the given [range] to the linked edit
  /// group with the given [groupName]. The [range] is relative to the original
  /// source. This is typically used to include preexisting regions of text in
  /// a group. If the region to be included is part of newly generated text,
  /// then the method [EditBuilder.addLinkedEdit] should be used instead.
  void addLinkedPosition(SourceRange range, String groupName);

  /// Add a replacement of text specified by the given [range]. The [range] is
  /// relative to the original source. The [buildEdit] function is used to write
  /// the text that will replace the specified region.
  void addReplacement(
      SourceRange range, void Function(EditBuilder builder) buildEdit);

  /// Add an insertion of the given [text] at the given [offset]. The [offset]
  /// is relative to the original source. This is fully equivalent to
  ///
  ///     addInsertion(offset, (EditBuilder builder) {
  ///       builder.write(text);
  ///     });
  void addSimpleInsertion(int offset, String text);

  /// Add a replacement of the text specified by the given [range]. The [range]
  /// is relative to the original source. The original content will be replaced
  /// by the given [text]. This is fully equivalent to
  ///
  ///     addReplacement(offset, length, (EditBuilder builder) {
  ///       builder.write(text);
  ///     });
  void addSimpleReplacement(SourceRange range, String text);
}

/// A builder used to build a [LinkedEdit] region within an edit.
///
/// Clients may not extend, implement or mix-in this class.
abstract class LinkedEditBuilder {
  /// Add the given [value] as a suggestion with the given [kind].
  void addSuggestion(LinkedEditSuggestionKind kind, String value);

  /// Add each of the given [values] as a suggestion with the given [kind].
  void addSuggestions(LinkedEditSuggestionKind kind, Iterable<String> values);

  /// Add the given [string] to the content of the current edit.
  void write(String string);

  /// Add the given [string] to the content of the current edit and then add an
  /// end-of-line marker.
  void writeln([String string]);
}
