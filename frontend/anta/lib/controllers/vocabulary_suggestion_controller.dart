import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:re_editor/re_editor.dart';

import '../constants/tag_catalog.dart';
import '../constants/vocabularies.dart';
import '../models/vocabulary.dart';
import '../services/folder_search_service.dart';
import '../utils/ghost_text.dart';
import '../utils/markdown_editor_span_builder.dart';
import '../utils/tag_extractor.dart';
import '../utils/tag_trigger.dart';
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

  /// Whether only indent precedes [start] on the line. A heading term
  /// accepted there still becomes a heading, so the pill may flatten it;
  /// anywhere else the hashes stay prose and the pill must show them.
  final bool atLineStart;

  /// A `#tag` session: its range is the whole tag, and accepting adds a
  /// space only at the line's end.
  final bool isTag;

  const VocabularySuggestionSession({
    required this.lineIndex,
    required this.start,
    required this.end,
    required this.suggestions,
    this.scopeNames = const [],
    this.atLineStart = false,
    this.isTag = false,
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
/// [candidateSource] is the seam the planned slash-menu plugs into — a
/// different provider with the same session, bar and insertion path.
///
/// A third way in is a **tag** being typed (`#le`, [TagTrigger]): its
/// session offers only tags — [tagSource], the tags the notes carry, then
/// the tags of this note the catalog does not know yet — and replaces the
/// whole tag under the caret. It needs no vocabulary, and the vocabulary
/// trigger is tried first, so the two never both hold.
class VocabularySuggestionController
    extends ValueNotifier<VocabularySuggestionSession?> {
  VocabularySuggestionController({
    required CodeLineEditingController controller,
    required this.onInsert,
    List<VocabularyCandidate> Function()? candidateSource,
    List<VocabularyCandidate> Function()? tagSource,
    bool Function()? isProgrammaticEdit,
  }) : _controller = controller,
       _candidateSource = candidateSource ?? _defaultCandidates,
       _tagSource = tagSource ?? _defaultTags,
       _isProgrammaticEdit = isProgrammaticEdit,
       super(null) {
    _seen = _controller.value;
    _controller.addListener(_onEditorChanged);
  }

  final CodeLineEditingController _controller;
  final void Function(VocabularyInsertion insertion) onInsert;
  final List<VocabularyCandidate> Function() _candidateSource;
  final List<VocabularyCandidate> Function() _tagSource;

  /// Whether the host is writing into the editor from code right now — a
  /// toolbar shortcut, a counter value, a template. Such a write is no
  /// keystroke, so text it leaves ending in a tag at the caret opens
  /// nothing while the finger is still on the toolbar.
  final bool Function()? _isProgrammaticEdit;

  /// The editor's value as this controller last saw it: typing is judged
  /// against it, never against the fork's `preValue`, so a notification
  /// that carries no new value cannot pass for a keystroke.
  late CodeLineEditingValue _seen;

  /// True while [accept] hands its replacement to [onInsert]: the
  /// completion's own write is the tap, not typing.
  bool _accepting = false;

  /// Whether the composition in progress has changed the text. A keyboard
  /// marks the word under a tapped caret without changing it, and its
  /// commit must not pass for typing.
  bool _compositionEdited = false;

  /// The open tag session — its line, its `#`, and the tag as it read when
  /// the session opened, which is text being typed rather than a tag the
  /// note carries, so it is never offered back once edited.
  int _tagLine = -1;
  int _tagOffset = -1;
  String _tagOpenedAs = '';

  /// Whether the tag at [_tagLine] and [_tagOffset] has been typed in since
  /// the caret came to it. The bar takes the toolbar's place, undo and redo
  /// with it, so the caret put into a tag, an undo or a redo opens nothing:
  /// a tap meant for the toolbar would land on a pill and rewrite the tag.
  bool _tagTyped = false;

  /// This note's tags as last read, and the lines they were read from. The
  /// editor replaces its `CodeLines` on every edit and keeps them on a caret
  /// move, so their identity is the free "the text changed" signal: a new
  /// session reads again only after an edit, and a session never re-reads
  /// per keystroke — a note can be megabytes.
  List<VocabularyCandidate> _noteTags = const [];
  CodeLines? _noteTagsFrom;

  /// [_tagSource]'s list and the [_noteTags] the merge below was built
  /// from, so a catalog published mid-session is picked up without reading
  /// the note again.
  List<VocabularyCandidate>? _tagCatalog;
  List<VocabularyCandidate>? _tagCatalogNoteTags;
  List<VocabularyCandidate> _tagCandidates = const [];

  /// The tag a completion just wrote — its line, its `#` and its text. A
  /// completion that leaves the caret at a tag's end would otherwise open
  /// the bar again on that very tag, with other pills where the tapped one
  /// was; it stays shut until the tag's text changes or the caret leaves.
  int _acceptedLine = -1;
  int _acceptedOffset = -1;
  String _acceptedTag = '';

  /// How many times the note's tags were read; the per-session promise is
  /// what tests pin.
  @visibleForTesting
  int get noteTagScans => _noteTagScans;
  int _noteTagScans = 0;

  bool _enabled = false;
  String _trigger = VocabularyTrigger.defaultTrigger;
  bool Function(int lineIndex)? _isFenceLine;

  int _anchorLine = -1;
  int _anchorOffset = -1;
  Set<String>? _anchorVocabularyIds;

  int _dismissedLine = -1;
  int _dismissedStart = -1;

  /// A dismissed tag comes back once the caret leaves it. A vocabulary
  /// dismissal still lasts until a session opens elsewhere.
  bool _dismissedTag = false;

  static List<VocabularyCandidate> _defaultCandidates() =>
      Vocabularies.candidates;

  static List<VocabularyCandidate> _defaultTags() => TagCatalog.candidates;

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

    // A tag ends at the first character that is not part of it, so
    // anything after it — `.`, `,`, `)` — already closes it.
    final needsSpace = session.isTag
        ? session.end >= text.length
        : session.end >= text.length ||
              !_isSpace(text.codeUnitAt(session.end));

    _clearAnchor();
    _leaveTag();
    _clearDismissal();
    if (session.isTag) {
      _acceptedLine = session.lineIndex;
      _acceptedOffset = session.start;
      _acceptedTag = candidate.term;
    }
    value = null;

    // A host that applies the insertion later than this call is read as
    // any other write: only the synchronous one is known to be the tap's.
    _accepting = true;
    try {
      onInsert(
        VocabularyInsertion(
          lineIndex: session.lineIndex,
          start: session.start,
          end: session.end,
          text: needsSpace ? '${candidate.term} ' : candidate.term,
        ),
      );
    } finally {
      _accepting = false;
    }
  }

  /// Closes the bar and keeps it closed for this query. Moving the caret
  /// out of a dismissed tag, or starting a new query, brings it back.
  void dismiss() {
    final session = value;
    if (session != null) {
      _dismissedLine = session.lineIndex;
      _dismissedStart = session.start;
      _dismissedTag = session.isTag;
    }
    _clearAnchor();
    value = null;
  }

  @override
  void dispose() {
    _controller.removeListener(_onEditorChanged);
    super.dispose();
  }

  // ── Detection ────────────────────────────────────────────────────────

  /// Hands detection the value before this change only when the change can
  /// be typing: a new value, written neither by [accept] nor by the host
  /// from code. The composition is followed here, ahead of the guard that
  /// keeps a composing editor from offering anything.
  void _onEditorChanged() {
    final before = _seen;
    final now = _controller.value;
    _seen = now;
    if (identical(before, now)) {
      _refresh();
      return;
    }
    if (_isComposing(now.composing)) {
      if (!_isComposing(before.composing)) _compositionEdited = false;
      if (!identical(before.codeLines, now.codeLines)) {
        _compositionEdited = true;
      }
    }
    final typing = !_accepting && !(_isProgrammaticEdit?.call() ?? false);
    _refresh(previous: typing ? before : null);
    if (!_isComposing(now.composing)) _compositionEdited = false;
  }

  void _refresh({CodeLineEditingValue? previous}) {
    if (!_enabled) {
      if (value != null) value = null;
      return;
    }

    final session = _detect(previous);

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

  VocabularySuggestionSession? _detect(CodeLineEditingValue? previous) {
    // No vocabulary shuts the vocabulary paths only: a tag needs none.
    final candidates = _candidateSource();
    final vocabulary = candidates.isNotEmpty;
    if (!vocabulary) _clearAnchor();
    if (_controller.isComposing) return null;

    final selection = _controller.selection;
    final lineIndex = selection.baseIndex;
    if (selection.extentIndex != lineIndex) {
      _clearAnchor();
      _leaveTag();
      return null;
    }

    final lines = _controller.codeLines;
    if (lineIndex < 0 || lineIndex >= lines.length) {
      _clearAnchor();
      _leaveTag();
      return null;
    }

    final text = lines[lineIndex].text;
    // Only a tag can open here, and without a `#` none can: the keystroke
    // costs no fence lookup.
    if (!vocabulary && !text.contains('#')) {
      _leaveTag();
      return null;
    }
    if (text.length > MarkdownEditorSpanBuilder.maxStyledLineLength) {
      _clearAnchor();
      _leaveTag();
      return null;
    }
    if (_isFenceLine?.call(lineIndex) ?? false) {
      _clearAnchor();
      _leaveTag();
      return null;
    }

    if (vocabulary) {
      final ghost = _ghostSession(candidates, text, lineIndex, selection);
      if (ghost != null) return ghost;
    }

    if (!selection.isCollapsed) {
      _leaveTag();
    } else {
      final match = vocabulary
          ? VocabularyTrigger.matchAt(
              text,
              selection.baseOffset,
              trigger: _trigger,
            )
          : null;
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
        if (suggestions.isNotEmpty) {
          _leaveTag();
          return VocabularySuggestionSession(
            lineIndex: lineIndex,
            start: match.triggerOffset,
            end: match.queryEnd,
            suggestions: suggestions,
            scopeNames: scoped ? _scopeNames(ids) : const [],
            atLineStart: _blankBefore(text, match.triggerOffset),
          );
        }
        // A trigger run that offers nothing (`@ben #le`, the run having
        // crossed one space) leaves the tag it ends in to the tag session.
      }

      final tag = _tagSession(
        text,
        lineIndex,
        selection.baseOffset,
        previous: previous,
      );
      if (tag != null || match != null) return tag;
    }

    if (!vocabulary) return null;
    return _anchorSession(candidates, text, lineIndex, selection);
  }

  /// The tag the caret is in, offering only tags: the catalog's, in its
  /// order, then this note's own the catalog has not caught up with — the
  /// search index lags while a note is open. The tag under the caret, spelled
  /// letter for letter as it stands, is never offered: that pill would change
  /// nothing, while another spelling of it brings the tag into line.
  ///
  /// It opens only once the tag has been typed in ([_tagTyped]) and stays
  /// open while the caret stays in that tag. A vocabulary anchor survives a
  /// tag that opens nothing, so backspacing out of it brings its terms back.
  VocabularySuggestionSession? _tagSession(
    String text,
    int lineIndex,
    int caret, {
    required CodeLineEditingValue? previous,
  }) {
    final match = TagTrigger.matchAt(text, caret);
    if (match == null) {
      _leaveTag();
      return null;
    }

    if (_tagLine != lineIndex || _tagOffset != match.hashOffset) {
      _clearTag();
      if (_dismissedTag) _clearDismissal();
      _tagLine = lineIndex;
      _tagOffset = match.hashOffset;
    }
    // Text an undo or a redo puts back is not typed, and the step it
    // reverts may be a completion: the bar waits for the next keystroke,
    // the "just accepted" mark kept for it.
    if (_controller.isRestoringHistory) {
      _tagTyped = false;
      return null;
    }

    final written = text.substring(match.hashOffset, match.tagEnd);
    if (_acceptedOffset >= 0) {
      if (_acceptedLine == lineIndex &&
          _acceptedOffset == match.hashOffset &&
          _acceptedTag == written) {
        return null;
      }
      _clearAccepted();
    }

    if (!_tagTyped) {
      if (previous == null || !_typedInto(previous, lineIndex, caret, match)) {
        return null;
      }
      _tagTyped = true;
      _tagOpenedAs = written;
      _tagCatalog = null;
      final lines = _controller.codeLines;
      if (!identical(lines, _noteTagsFrom)) {
        _noteTagsFrom = lines;
        _noteTags = _readNoteTags(lines);
      }
    }
    final catalog = _tagSource();
    if (!identical(catalog, _tagCatalog) ||
        !identical(_noteTags, _tagCatalogNoteTags)) {
      _tagCatalog = catalog;
      _tagCatalogNoteTags = _noteTags;
      _tagCandidates = _withNoteTags(catalog, _noteTags, _tagOpenedAs);
    }

    final suggestions = <VocabularyCandidate>[];
    for (final candidate in VocabularyMatcher.match(
      _tagCandidates,
      match.query,
      limit: VocabularyMatcher.maxResults + 1,
    )) {
      if (candidate.term == written) continue;
      suggestions.add(candidate);
      if (suggestions.length == VocabularyMatcher.maxResults) break;
    }
    if (suggestions.isEmpty) return null;

    _clearAnchor();
    return VocabularySuggestionSession(
      lineIndex: lineIndex,
      start: match.hashOffset,
      end: match.tagEnd,
      suggestions: suggestions,
      atLineStart: _blankBefore(text, match.hashOffset),
      isTag: true,
    );
  }

  /// Whether the change from [before] is typing in [match]'s tag: on
  /// [lineIndex], the line count kept, the text changed and the change
  /// ending at [caret] — a character typed, a Backspace, a Delete, a paste
  /// — or a composition that changed the text, committed there with the
  /// caret where it was. A merge from another device is all a
  /// caret-preserving change elsewhere can be, and it ends away from the
  /// caret.
  ///
  /// One pass over the line, only while the caret is in a tag no session
  /// has opened on yet; the note is never read for it.
  bool _typedInto(
    CodeLineEditingValue before,
    int lineIndex,
    int caret,
    TagTriggerMatch match,
  ) {
    final was = before.selection;
    if (was.baseIndex != lineIndex || was.extentIndex != lineIndex) {
      return false;
    }
    final lines = _controller.codeLines;
    final previous = before.codeLines;
    if (previous.length != lines.length) return false;

    final composing = before.composing;
    if (_compositionEdited &&
        _isComposing(composing) &&
        was == _controller.selection &&
        composing.start < match.tagEnd &&
        composing.end > match.hashOffset) {
      return true;
    }
    if (identical(previous, lines)) return false;

    final old = previous[lineIndex].text;
    final now = lines[lineIndex].text;
    final shorter = old.length < now.length ? old.length : now.length;
    var prefix = 0;
    while (prefix < shorter &&
        old.codeUnitAt(prefix) == now.codeUnitAt(prefix)) {
      prefix++;
    }
    if (prefix == shorter && old.length == now.length) return false;
    var suffix = 0;
    while (suffix < shorter &&
        old.codeUnitAt(old.length - 1 - suffix) ==
            now.codeUnitAt(now.length - 1 - suffix)) {
      suffix++;
    }
    // Repeated letters let the changed run slide (an `l` typed at `#l|ll`
    // reads as one added at the end): the change ends at the caret if any
    // of its placements does.
    final overlap = shorter - prefix;
    final latestEnd = now.length - (suffix < overlap ? suffix : overlap);
    final earliestEnd = now.length - suffix;
    return earliestEnd <= caret && caret <= latestEnd;
  }

  /// This note's tags as candidates, each spelling once in the order first
  /// seen, fence lines skipped.
  List<VocabularyCandidate> _readNoteTags(CodeLines lines) {
    _noteTagScans++;
    final seen = <String>{};
    final tags = <VocabularyCandidate>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].text;
      if (!line.contains('#') || (_isFenceLine?.call(i) ?? false)) continue;
      for (final tag in extractTags(line, cache: false)) {
        if (!seen.add(tag)) continue;
        tags.add(
          VocabularyCandidate(
            term: '#$tag',
            foldedTerm: '#${normalizeForSearch(tag)}',
            vocabularyId: TagCatalog.sourceId,
            vocabularyName: '',
            vocabularySortOrder: 0,
            itemSortOrder: tags.length,
          ),
        );
      }
    }
    return tags;
  }

  /// [catalog] then the [own] tags it lacks, each folded form once, so the
  /// matcher's in-tier order ranks a tag only this note carries after every
  /// tag the notes share. [openedAs] — the tag the session opened on, as
  /// written then — is left out: it is the text being typed, so `#le` cut
  /// back to `#l` does not offer the `#le` that no longer exists.
  static List<VocabularyCandidate> _withNoteTags(
    List<VocabularyCandidate> catalog,
    List<VocabularyCandidate> own,
    String openedAs,
  ) {
    if (own.isEmpty) return catalog;
    final known = {for (final candidate in catalog) candidate.foldedTerm};
    return [
      ...catalog,
      for (final candidate in own)
        if (candidate.term != openedAs && known.add(candidate.foldedTerm))
          candidate,
    ];
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
      atLineStart: _blankBefore(text, ghost.start),
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
      atLineStart: _blankBefore(text, _anchorOffset),
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
    _leaveTag();
    _clearDismissal();
    _noteTags = const [];
    _noteTagsFrom = null;
    if (value != null) value = null;
  }

  void _clearAnchor() {
    _anchorLine = -1;
    _anchorOffset = -1;
    _anchorVocabularyIds = null;
  }

  /// The caret is in no tag: the session ends, a dismissed tag is no longer
  /// dismissed, and a completed tag may open the bar again once typed in.
  void _leaveTag() {
    _clearTag();
    _clearAccepted();
    if (_dismissedTag) _clearDismissal();
  }

  /// Ends the tag session; the note's tags stay read for the next one.
  void _clearTag() {
    if (_tagOffset < 0) return;
    _tagLine = -1;
    _tagOffset = -1;
    _tagOpenedAs = '';
    _tagTyped = false;
    _tagCatalog = null;
    _tagCatalogNoteTags = null;
    _tagCandidates = const [];
  }

  void _clearAccepted() {
    _acceptedLine = -1;
    _acceptedOffset = -1;
    _acceptedTag = '';
  }

  void _clearDismissal() {
    _dismissedLine = -1;
    _dismissedStart = -1;
    _dismissedTag = false;
  }

  static bool _isSpace(int unit) => unit == 0x20 || unit == 0x09;

  static bool _isComposing(TextRange composing) =>
      composing.end > composing.start;

  static bool _blankBefore(String text, int offset) {
    for (var i = 0; i < offset; i++) {
      if (!_isSpace(text.codeUnitAt(i))) return false;
    }
    return true;
  }
}
