import 'package:flutter/foundation.dart';
import 'package:re_editor/re_editor.dart';

import '../constants/vocabularies.dart';
import '../models/vocabulary.dart';
import '../utils/ghost_text.dart';
import '../utils/markdown_editor_span_builder.dart';
import '../utils/vocabulary_matcher.dart';
import '../utils/vocabulary_trigger.dart';

/// An open suggestion session: what to replace, and what to offer.
///
/// `[start, end)` is a range on [lineIndex] — the trigger plus what has been
/// typed after it, or the whole `{{ … }}` run of an engaged ghost.
///
/// [scopeNames] carries the lists a scoped session is confined to, resolved to
/// their display names for the bar's label. Empty means unscoped — every
/// enabled list is in play. These are the user's own list names, so they never
/// pass through `AppLocalizations`.
class VocabularySuggestionSession {
  final int lineIndex;
  final int start;
  final int end;
  final List<VocabularyCandidate> suggestions;
  final List<String> scopeNames;

  const VocabularySuggestionSession({
    required this.lineIndex,
    required this.start,
    required this.end,
    required this.suggestions,
    this.scopeNames = const [],
  });

  bool sameAnchor(VocabularySuggestionSession? other) =>
      other != null && other.lineIndex == lineIndex && other.start == start;
}

/// A replacement the host page should apply to the editor.
class VocabularyInsertion {
  final int lineIndex;
  final int start;
  final int end;
  final String text;

  const VocabularyInsertion({
    required this.lineIndex,
    required this.start,
    required this.end,
    required this.text,
  });
}

/// Watches the caret and decides when the editor should be offering terms.
///
/// Two ways in, one session out:
///  * a **trigger character** typed after whitespace (`@ben`), and
///  * an **engaged ghost** (`{{exercise}}`) — the wrapper selects the whole run
///    on tap, which this reads straight off the selection, so nothing needs to
///    couple to the wrapper's tap state.
///
/// Both can scope themselves to particular lists: a ghost whose inner text
/// names a vocabulary (`{{exercise}}`), and a trigger run carrying a scope
/// segment (`@exercise:ben`, `@exercises,meals:oat`). Once the user types over
/// a ghost run the braces are gone, so the start offset is remembered as an
/// anchor — along with its scope — and the session keeps filtering from there.
///
/// Nothing here ever blocks typing: an empty result set closes the bar and the
/// characters stay exactly as written. A scope segment that names no list is
/// not an error either — it becomes an unscoped query over the run exactly as
/// written, colon and all, while an omitted one (`@:ben`) is an unscoped query
/// for what follows it.
///
/// [candidateSource] is the seam the tag roadmap's `#tag` autocomplete and the
/// planned slash-menu plug into — a different provider with the same session,
/// bar and insertion path.
class VocabularySuggestionController
    extends ValueNotifier<VocabularySuggestionSession?> {
  VocabularySuggestionController({
    required CodeLineEditingController controller,
    required this.onInsert,
    List<VocabularyCandidate> Function()? candidateSource,
  }) : _controller = controller,
       _candidateSource = candidateSource ?? _defaultCandidates,
       super(null) {
    _controller.addListener(_refresh);
  }

  final CodeLineEditingController _controller;
  final void Function(VocabularyInsertion insertion) onInsert;
  final List<VocabularyCandidate> Function() _candidateSource;

  bool _enabled = false;
  String _trigger = VocabularyTrigger.defaultTrigger;
  bool Function(int lineIndex)? _isFenceLine;

  int _anchorLine = -1;
  int _anchorOffset = -1;
  Set<String>? _anchorVocabularyIds;

  int _dismissedLine = -1;
  int _dismissedStart = -1;

  static List<VocabularyCandidate> _defaultCandidates() =>
      Vocabularies.candidates;

  /// Applies the user's settings. Cheap to call on every settings return —
  /// re-detects only when something actually changed.
  void configure({
    required bool enabled,
    required String trigger,
    bool Function(int lineIndex)? isFenceLine,
  }) {
    final resolved = trigger.isEmpty
        ? VocabularyTrigger.defaultTrigger
        : trigger;
    _isFenceLine = isFenceLine;
    if (_enabled == enabled && _trigger == resolved) return;
    _enabled = enabled;
    _trigger = resolved;
    if (!_enabled) {
      _close();
      return;
    }
    _refresh();
  }

  /// Replaces the session's range with [candidate], through the host page so
  /// the editor's own change bookkeeping stays correct.
  ///
  /// A trailing space is added only when the next character is not already one,
  /// so accepting at the end of a line keeps typing flowing while filling
  /// `{{exercise}} 3x8` leaves the spacing that was already there.
  void accept(VocabularyCandidate candidate) {
    final session = value;
    if (session == null) return;

    final lines = _controller.codeLines;
    if (session.lineIndex < 0 || session.lineIndex >= lines.length) {
      _close();
      return;
    }
    final text = lines[session.lineIndex].text;
    if (session.end > text.length) {
      _close();
      return;
    }

    final needsSpace =
        session.end >= text.length || !_isSpace(text.codeUnitAt(session.end));

    _clearAnchor();
    _clearDismissal();
    value = null;

    onInsert(
      VocabularyInsertion(
        lineIndex: session.lineIndex,
        start: session.start,
        end: session.end,
        text: needsSpace ? '${candidate.term} ' : candidate.term,
      ),
    );
  }

  /// Closes the bar and keeps it closed for this query. Moving the caret
  /// somewhere else, or starting a new query, brings it back.
  void dismiss() {
    final session = value;
    if (session != null) {
      _dismissedLine = session.lineIndex;
      _dismissedStart = session.start;
    }
    _clearAnchor();
    value = null;
  }

  @override
  void dispose() {
    _controller.removeListener(_refresh);
    super.dispose();
  }

  // ── Detection ────────────────────────────────────────────────────────

  void _refresh() {
    if (!_enabled) {
      if (value != null) value = null;
      return;
    }

    final session = _detect();

    if (session != null &&
        session.lineIndex == _dismissedLine &&
        session.start == _dismissedStart) {
      if (value != null) value = null;
      return;
    }
    if (session != null && !session.sameAnchor(value)) {
      _clearDismissal();
    }

    if (session == null) {
      if (value != null) value = null;
      return;
    }
    value = session;
  }

  VocabularySuggestionSession? _detect() {
    final candidates = _candidateSource();
    if (candidates.isEmpty) {
      _clearAnchor();
      return null;
    }
    if (_controller.isComposing) return null;

    final selection = _controller.selection;
    final lineIndex = selection.baseIndex;
    if (selection.extentIndex != lineIndex) {
      _clearAnchor();
      return null;
    }

    final lines = _controller.codeLines;
    if (lineIndex < 0 || lineIndex >= lines.length) {
      _clearAnchor();
      return null;
    }

    final text = lines[lineIndex].text;
    if (text.length > MarkdownEditorSpanBuilder.maxStyledLineLength) {
      _clearAnchor();
      return null;
    }
    if (_isFenceLine?.call(lineIndex) ?? false) {
      _clearAnchor();
      return null;
    }

    final ghost = _ghostSession(candidates, text, lineIndex, selection);
    if (ghost != null) return ghost;

    if (selection.isCollapsed) {
      final match = VocabularyTrigger.matchAt(
        text,
        selection.baseOffset,
        trigger: _trigger,
      );
      if (match != null) {
        _clearAnchor();

        final ids = match.scopeTokens.isEmpty
            ? null
            : Vocabularies.idsForScopeTokens(match.scopeTokens);
        final scoped = ids != null && ids.isNotEmpty;

        final suggestions = VocabularyMatcher.match(
          candidates,
          ids != null && ids.isEmpty
              ? text.substring(match.triggerOffset + 1, match.queryEnd)
              : match.query,
          vocabularyIds: scoped ? ids : null,
        );
        if (suggestions.isEmpty) return null;

        return VocabularySuggestionSession(
          lineIndex: lineIndex,
          start: match.triggerOffset,
          end: match.queryEnd,
          suggestions: suggestions,
          scopeNames: scoped ? _scopeNames(ids) : const [],
        );
      }
    }

    return _anchorSession(candidates, text, lineIndex, selection);
  }

  /// A ghost run the caret is in, either selected whole (just tapped) or with
  /// the caret parked inside it (tapped a second time, editing in place).
  VocabularySuggestionSession? _ghostSession(
    List<VocabularyCandidate> candidates,
    String text,
    int lineIndex,
    CodeLineSelection selection,
  ) {
    if (!GhostText.mightContain(text)) return null;

    final base = selection.baseOffset;
    final extent = selection.extentOffset;
    final low = base < extent ? base : extent;
    final high = base < extent ? extent : base;

    GhostMatch? ghost;
    if (low == high) {
      ghost = GhostText.ghostAtOffset(text, low);
    } else {
      final run = GhostText.matchAt(text, low);
      if (run != null && run.end == high) ghost = run;
    }
    if (ghost == null) return null;

    final inner = text.substring(ghost.innerStart, ghost.innerEnd).trim();
    final Vocabulary? scope = Vocabularies.byName(inner);
    final query = scope == null ? inner : '';

    _anchorLine = lineIndex;
    _anchorOffset = ghost.start;
    _anchorVocabularyIds = scope == null ? null : {scope.id};

    final suggestions = VocabularyMatcher.match(
      candidates,
      query,
      vocabularyIds: _anchorVocabularyIds,
    );
    if (suggestions.isEmpty) return null;

    return VocabularySuggestionSession(
      lineIndex: lineIndex,
      start: ghost.start,
      end: ghost.end,
      suggestions: suggestions,
      scopeNames: scope == null ? const [] : [scope.name],
    );
  }

  /// Keeps a ghost's session alive once the user has typed over the run: the
  /// braces are gone, but the offset the ghost started at still marks where the
  /// term begins.
  VocabularySuggestionSession? _anchorSession(
    List<VocabularyCandidate> candidates,
    String text,
    int lineIndex,
    CodeLineSelection selection,
  ) {
    if (_anchorOffset < 0 || _anchorLine != lineIndex) return null;
    if (!selection.isCollapsed) {
      _clearAnchor();
      return null;
    }

    final caret = selection.baseOffset;
    if (_anchorOffset > text.length ||
        caret < _anchorOffset ||
        caret > text.length ||
        caret - _anchorOffset > VocabularyTrigger.maxQueryLength) {
      _clearAnchor();
      return null;
    }

    final run = text.substring(_anchorOffset, caret);
    var spaces = 0;
    for (var i = 0; i < run.length; i++) {
      if (_isSpace(run.codeUnitAt(i)) && ++spaces > 1) {
        _clearAnchor();
        return null;
      }
    }

    final ids = _anchorVocabularyIds;
    final suggestions = VocabularyMatcher.match(
      candidates,
      run,
      vocabularyIds: ids,
    );
    if (suggestions.isEmpty) return null;

    return VocabularySuggestionSession(
      lineIndex: lineIndex,
      start: _anchorOffset,
      end: caret,
      suggestions: suggestions,
      scopeNames: ids == null ? const [] : _scopeNames(ids),
    );
  }

  /// The display names behind a resolved scope, for the bar's label. Ids the
  /// facade no longer knows are dropped rather than rendered blank — a list can
  /// be deleted while a session is open.
  List<String> _scopeNames(Set<String> ids) {
    final names = <String>[];
    for (final id in ids) {
      final name = Vocabularies.byId(id)?.name;
      if (name != null) names.add(name);
    }
    return names;
  }

  void _close() {
    _clearAnchor();
    _clearDismissal();
    if (value != null) value = null;
  }

  void _clearAnchor() {
    _anchorLine = -1;
    _anchorOffset = -1;
    _anchorVocabularyIds = null;
  }

  void _clearDismissal() {
    _dismissedLine = -1;
    _dismissedStart = -1;
  }

  static bool _isSpace(int unit) => unit == 0x20 || unit == 0x09;
}
