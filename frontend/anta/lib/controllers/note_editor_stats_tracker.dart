import 'dart:async';

import 'package:flutter/foundation.dart';

import '../constants/markdown_constants.dart';
import '../widgets/note_editor_chrome.dart';

/// Publishes the editor's line and character counts for the stats bar.
///
/// Counting is cheap but not free, and it happens on the typing path, so
/// the tracker trades freshness for it in exactly one direction: small
/// edits coalesce into one update [debounceDelay] after the user pauses,
/// while an edit large enough to be a paste or a delete of a whole block
/// ([MarkdownConstants.contentChangeDeltaThreshold]) updates at once —
/// that is the change a reader would notice the bar failing to reflect.
class NoteEditorStatsTracker {
  NoteEditorStatsTracker({required NoteEditorStats Function() snapshot})
    : _snapshot = snapshot;

  /// How long the bar may lag behind a run of ordinary keystrokes.
  static const Duration debounceDelay = Duration(milliseconds: 300);

  final NoteEditorStats Function() _snapshot;
  final ValueNotifier<NoteEditorStats> _stats = ValueNotifier<NoteEditorStats>(
    emptyNoteEditorStats,
  );

  Timer? _debounce;
  int _lastTextLength = 0;
  bool _disposed = false;

  ValueListenable<NoteEditorStats> get stats => _stats;

  /// Publishes [value] as-is, for the one case where the exact numbers are
  /// already known without asking the editor: the note's content landing.
  void set(NoteEditorStats value) {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = null;
    _lastTextLength = value.charCount;
    _stats.value = value;
  }

  /// The editor's text changed and now holds [textLength] code units.
  void onTextChanged(int textLength) {
    if (_disposed) return;
    final delta = (textLength - _lastTextLength).abs();
    if (delta > MarkdownConstants.contentChangeDeltaThreshold) {
      refresh();
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(debounceDelay, () {
      _debounce = null;
      refresh();
    });
  }

  /// Counts now and publishes the result, dropping any pending debounce.
  void refresh() {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = null;
    final value = _snapshot();
    _lastTextLength = value.charCount;
    _stats.value = value;
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _debounce = null;
    _stats.dispose();
  }
}
