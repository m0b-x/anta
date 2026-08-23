/// Where a vocabulary suggestion session starts and what the user has typed
/// into it — the ephemeral half of the feature.
///
/// This is a *typing* grammar, not a document grammar: nothing it recognizes is
/// ever persisted, rendered or exported, so neither the preview builder nor the
/// editor span builder consumes it. It lives beside the other grammar modules
/// because the rule for "is the caret inside a query" must have exactly one
/// definition, the same reason `GhostText` and `MarkdownTagSyntax` do.
///
/// The single hard requirement: never hijack text the user meant literally.
/// `3x8 @ 60kg`, `5x5@100kg` and `a@b.com` must all stay ordinary text, which
/// is why the trigger needs whitespace before it and a non-space after it.
library;

import 'ghost_text.dart';

/// An open query: the trigger character at [triggerOffset] and the [query] run
/// between it and the caret at [queryEnd].
///
/// Accepting a suggestion replaces `[triggerOffset, queryEnd)` — the trigger
/// character is consumed along with the typed text, so what lands in the note
/// is plain prose.
///
/// [scopeTokens] is what the user wrote before the first `:` of the run
/// (`@exercise:ben`, `@exercises,meals:oat`), unresolved: this module never
/// looks at the user's lists. Empty means an unscoped query. Resolution can
/// fail, so the caller needs the run back verbatim to fall through to an
/// unscoped match — it is `line.substring(triggerOffset + 1, queryEnd)`.
class VocabularyTriggerMatch {
  final int triggerOffset;
  final int queryEnd;
  final String query;
  final List<String> scopeTokens;

  const VocabularyTriggerMatch({
    required this.triggerOffset,
    required this.queryEnd,
    required this.query,
    this.scopeTokens = const [],
  });
}

class VocabularyTrigger {
  VocabularyTrigger._();

  static const String defaultTrigger = '@';

  /// Trigger characters offered in settings. Each is punctuation that is rare
  /// mid-word, so a session opening is always something the user asked for.
  static const List<String> availableTriggers = ['@', ':', ';', '\\', '~'];

  /// Longest run that still counts as a query. Past this the user is writing a
  /// sentence, not looking something up.
  static const int maxQueryLength = 64;

  /// The query the caret sits in, or `null` when there is none.
  ///
  /// [line] is a single line of the document and [caret] an offset into it.
  /// A session is open when, scanning back from the caret, we reach [trigger]
  /// with whitespace (or the line start) before it, having crossed at most one
  /// space — so `@bench p` keeps filtering while `@bench press x` gives up and
  /// hands the line back to plain typing.
  ///
  /// Returns `null` inside a ghost run: an engaged `{{…}}` owns its range and
  /// runs its own session.
  ///
  /// The first `:` **of the run** splits an optional scope segment off the
  /// front (`@exercise:ben`), comma-separated for several lists. Splitting the
  /// run rather than the line keeps `:` usable as a trigger character itself,
  /// and leaves prose colons (`sets: @ben`) outside the query entirely.
  ///
  /// Callers apply the editor-state guards this cannot see: collapsed selection
  /// only, not while the IME is composing, not on a fence line, and not on
  /// lines past `MarkdownEditorSpanBuilder.maxStyledLineLength`.
  static VocabularyTriggerMatch? matchAt(
    String line,
    int caret, {
    String trigger = defaultTrigger,
  }) {
    if (trigger.length != 1) return null;
    if (caret < 1 || caret > line.length) return null;
    if (!line.contains(trigger)) return null;

    final triggerUnit = trigger.codeUnitAt(0);
    final lowest = caret - maxQueryLength - 1;
    var spaces = 0;

    for (var i = caret - 1; i >= 0 && i >= lowest; i--) {
      final unit = line.codeUnitAt(i);

      if (unit == triggerUnit) {
        if (i > 0 && !_isSpace(line.codeUnitAt(i - 1))) return null;
        if (caret > i + 1 && _isSpace(line.codeUnitAt(i + 1))) return null;
        if (GhostText.ghostAtOffset(line, i) != null) return null;
        return _split(i, caret, line.substring(i + 1, caret));
      }

      if (_isSpace(unit)) {
        if (++spaces > 1) return null;
      }
    }

    return null;
  }

  /// Splits [run] into its scope segment and query.
  ///
  /// Tokens are trimmed and empties dropped, but never folded: matching them
  /// against list names is the resolver's job, and this module stays free of
  /// the vocabulary cache. A run whose scope segment holds nothing usable
  /// (`@:ben`) is an ordinary query for what follows the colon — an
  /// unresolvable scope must never cost the user a keystroke.
  static VocabularyTriggerMatch _split(int triggerOffset, int caret, String run) {
    final colon = run.indexOf(':');
    if (colon < 0) {
      return VocabularyTriggerMatch(
        triggerOffset: triggerOffset,
        queryEnd: caret,
        query: run,
      );
    }

    final tokens = <String>[];
    for (final token in run.substring(0, colon).split(',')) {
      final trimmed = token.trim();
      if (trimmed.isNotEmpty) tokens.add(trimmed);
    }

    return VocabularyTriggerMatch(
      triggerOffset: triggerOffset,
      queryEnd: caret,
      query: run.substring(colon + 1),
      scopeTokens: tokens.isEmpty ? const [] : List.unmodifiable(tokens),
    );
  }

  static bool _isSpace(int unit) => unit == 0x20 || unit == 0x09;
}
