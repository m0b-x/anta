import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:re_editor/re_editor.dart';

import '../services/note_position_service.dart';

/// Owns the note editor's persisted reading position: the record read on
/// open, the join that decides when it may be applied, and the two timers
/// the page used to keep as loose fields.
///
/// The restore is a **join** because its two inputs race — the position
/// read is async, the note content arrives on a BLoC state — and applying
/// it needs both. Whichever lands last performs the restore, and
/// [restoreWhenReady] guarantees it happens exactly once: a second restore
/// would drag the caret back after the user had already moved it.
///
/// Positions are stored as **absolute** line numbers (chunk children
/// counted), never as visible indices, so a note reopened with different
/// sections folded still lands on the same line of text. Today the two
/// coincide because nothing folds; [snapshot] and [editorTarget] are the
/// seam that keeps the stored records readable when something does.
class NoteEditorPositionController {
  NoteEditorPositionController({
    required this.noteId,
    required Future<NotePositionData> Function(String noteId) loadPosition,
    required Future<void> Function(String noteId, NotePositionData position)
    savePosition,
    required void Function(NotePositionData position) onRestore,
  }) : _loadPosition = loadPosition,
       _savePosition = savePosition,
       _onRestore = onRestore;

  final Future<NotePositionData> Function(String noteId) _loadPosition;
  final Future<void> Function(String noteId, NotePositionData position)
  _savePosition;
  final void Function(NotePositionData position) _onRestore;

  /// The note being edited. Settable because a brand-new note has no id
  /// until the early create returns one, and its position must start being
  /// saved from that moment.
  String? noteId;

  /// The caret the editor held when the user switched to preview, so the
  /// way back can restore it. Page bookkeeping, never persisted.
  CodeLineSelection? savedEditorSelection;

  NotePositionData? _saved;
  bool _contentReady = false;
  bool _restored = false;
  bool _disposed = false;
  Timer? _scrollTimer;
  Timer? _saveTimer;

  /// The stored record, or null until [load] has answered. Survives the
  /// restore: the preview flag is re-read later, when the settings that
  /// decide whether preview is reachable at all have landed too.
  NotePositionData? get saved => _saved;

  bool? get savedIsPreviewMode => _saved?.isPreviewMode;

  /// Reads the stored position for [noteId] and offers it to the join.
  /// Inert for a note that does not exist yet — there is nothing stored
  /// under an id that was never assigned.
  Future<void> load() async {
    final id = noteId;
    if (id == null) return;
    final position = await _loadPosition(id);
    if (_disposed) return;
    _saved = position;
    restoreWhenReady();
  }

  /// The editor now holds the note's text, so a caret set on it will stick.
  void contentReady() {
    _contentReady = true;
    restoreWhenReady();
  }

  /// Fires [onRestore] the first time both the position and the content
  /// have landed. Safe to call from either side, and from either side
  /// again — every call after the first is a no-op.
  void restoreWhenReady() {
    if (_disposed || _restored || !_contentReady) return;
    final position = _saved;
    if (position == null) return;
    _restored = true;
    _onRestore(position);
  }

  /// Persists [position]. A no-op while the note has no id yet; the next
  /// save after the early create lands writes the full record anyway.
  Future<void> save(NotePositionData position) async {
    final id = noteId;
    if (id == null) return;
    await _savePosition(id, position);
  }

  /// Runs [action] after [delay], replacing any scroll already queued.
  /// One timer for every deferred scroll the page performs (restore on
  /// open, restore after leaving preview) — they can never both be wanted.
  void scheduleScroll(Duration delay, VoidCallback action) {
    _scrollTimer?.cancel();
    _scrollTimer = null;
    if (_disposed) return;
    _scrollTimer = Timer(delay, () {
      _scrollTimer = null;
      if (_disposed) return;
      action();
    });
  }

  /// Saves the position [snapshot] produces after [delay], coalescing a
  /// burst of calls into one write. [snapshot] is evaluated when the timer
  /// fires, so the record written is the position as of then.
  void debounceSave(Duration delay, NotePositionData Function() snapshot) {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_disposed) return;
    _saveTimer = Timer(delay, () {
      _saveTimer = null;
      if (_disposed) return;
      unawaited(save(snapshot()));
    });
  }

  /// Drops both timers and makes every later callback inert — an in-flight
  /// [load] that answers after the page is gone must not restore into a
  /// disposed editor.
  void dispose() {
    _disposed = true;
    _scrollTimer?.cancel();
    _scrollTimer = null;
    _saveTimer?.cancel();
    _saveTimer = null;
  }

  /// The record to persist for the editor's current state.
  ///
  /// The caret line goes through [CodeLineEditingController.index2lineIndex]
  /// so what is stored is the absolute line number, independent of which
  /// sections happened to be folded when the note was closed.
  static NotePositionData snapshot({
    required CodeLineEditingController controller,
    required bool isPreviewMode,
    required double previewScrollProgress,
  }) {
    final selection = controller.selection;
    final lineIndex = controller.index2lineIndex(selection.baseIndex);
    return NotePositionData(
      isPreviewMode: isPreviewMode,
      previewScrollProgress: previewScrollProgress,
      // `index2lineIndex` answers -1 for an index it cannot place; storing
      // that would persist a position no restore can honour.
      editorLineIndex: lineIndex < 0 ? 0 : lineIndex,
      editorColumnOffset: selection.baseOffset,
    );
  }

  /// Where [p] points in [controller] right now.
  ///
  /// The stored absolute line is resolved back to a visible index through
  /// [CodeLineEditingController.lineIndex2Index], which maps a line hidden
  /// inside a collapsed chunk onto its visible parent — the closest the
  /// caret can legally get to it. Line and column are both clamped, so a
  /// record saved against a longer version of the note still lands inside
  /// the document instead of throwing.
  static CodeLinePosition editorTarget(
    NotePositionData p,
    CodeLineEditingController controller,
  ) {
    final codeLines = controller.codeLines;
    final lineIndex = p.editorLineIndex.clamp(0, codeLines.lineCount - 1);
    final visible = controller
        .lineIndex2Index(lineIndex)
        .index
        .clamp(0, codeLines.length - 1);
    final offset = p.editorColumnOffset.clamp(0, codeLines[visible].length);
    return CodeLinePosition(index: visible, offset: offset);
  }
}
