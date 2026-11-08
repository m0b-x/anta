import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;

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
  /// [isShown] says whether the stats bar is on screen: while it is not,
  /// an edit only marks the counts stale, and [resume] counts once when
  /// the bar comes back.
  NoteEditorStatsTracker({
    required NoteEditorStats Function() snapshot,
    bool Function()? isShown,
  }) : _snapshot = snapshot,
       _isShown = isShown ?? _alwaysShown;

  static bool _alwaysShown() => true;

  /// How long the bar may lag behind a run of ordinary keystrokes.
  static const Duration debounceDelay = Duration(milliseconds: 300);

  /// The count the bar calls characters: grapheme clusters, so an emoji or
  /// a letter with a combining mark is one, where code units made `👍` two.
  /// It walks the whole text, so it belongs in the snapshot, which runs
  /// only after the debounce or for a paste-sized change, never per key.
  /// The editor counts per line instead (`CodeLines.graphemeCount`), to
  /// the same number.
  static int countCharacters(String text) => text.characters.length;

  final bool Function() _isShown;

  /// An edit landed while the bar was hidden and has not been counted.
  bool _stale = false;

  final NoteEditorStats Function() _snapshot;
  final ValueNotifier<NoteEditorStats> _stats = ValueNotifier<NoteEditorStats>(
    emptyNoteEditorStats,
  );

  Timer? _debounce;
  // Code units, the unit [onTextChanged] reports in: at the last count, and
  // the latest reported, which becomes the baseline when the count runs.
  int _lastTextLength = 0;
  int _latestTextLength = 0;
  bool _disposed = false;

  ValueListenable<NoteEditorStats> get stats => _stats;

  /// Publishes [value] as-is, for the one case where the exact numbers are
  /// already known without asking the editor: the note's content landing.
  /// [textLength] is that content's length in code units, the baseline the
  /// next [onTextChanged] measures its delta from — required, because the
  /// stats count characters, not code units, and the two must not mix.
  void set(NoteEditorStats value, {required int textLength}) {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = null;
    _stale = false;
    _lastTextLength = _latestTextLength = textLength;
    _stats.value = value;
  }

  /// [set] for content that landed while the bar is hidden: takes the
  /// baseline without counting, and [resume] counts when the bar returns.
  void markStale({required int textLength}) {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = null;
    _stale = true;
    _lastTextLength = _latestTextLength = textLength;
  }

  /// The editor's text changed and now holds [textLength] code units.
  void onTextChanged(int textLength) {
    if (_disposed) return;
    _latestTextLength = textLength;
    if (!_isShown()) {
      _debounce?.cancel();
      _debounce = null;
      _stale = true;
      return;
    }
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

  /// The bar is on screen again: counts now if an edit landed while it was
  /// hidden, so it never shows the numbers from before.
  void resume() {
    if (_stale) refresh();
  }

  /// Counts now and publishes the result, dropping any pending debounce.
  void refresh() {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = null;
    _stale = false;
    final value = _snapshot();
    _lastTextLength = _latestTextLength;
    _stats.value = value;
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _debounce = null;
    _stats.dispose();
  }
}
