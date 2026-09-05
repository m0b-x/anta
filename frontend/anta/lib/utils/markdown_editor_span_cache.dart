import 'package:flutter/material.dart';

import 'editor_render_context.dart';
import 'lru_cache.dart';
import 'markdown_money_syntax.dart';

/// Key of the positional span memo: the reason a line's rendering is
/// positional ([EditorSpanCache.positionalFenceDelimiter] and friends),
/// the value that distinguishes two renderings of the same text (a money
/// row's balance; `0` for every tag that has none), and the line text.
///
/// A record rather than an interpolated string on purpose: the tag and
/// the value fold into the key without copying the line, so a memo hit
/// on the typing path allocates nothing but the key itself.
typedef PositionalSpanKey = (int tag, int value, String text);

/// The live editor renderer's memos, and the theme generation they are
/// valid under.
///
/// Three caches with three different lifetimes:
///
/// * [styled] — the text-keyed span LRU. A line whose rendering depends
///   only on its own text returns the *identical* span instance on a
///   repeat build, which is what keeps re_editor's paragraph cache on
///   its fast path.
/// * [positional] — the small LRU for lines whose rendering depends on
///   the lines around them (fence roles, indeterminate task parents,
///   money rows carrying a computed balance). The same text can render
///   differently, so the role — and the value — go into the key: a
///   [PositionalSpanKey] record, never an interpolated string. Records
///   have structural equality and hashing in Dart 3, so the key is as
///   good as a composed string without copying the line on every
///   lookup — and every lookup here is on the typing path.
/// * [parseMoney] — the money parse memo. The parse is a pure function
///   of the line text, so no configuration change can stale it and it
///   is never cleared; the LRU is its only bound.
///
/// The two span memos always invalidate together — every cached span
/// holds already-resolved colours and metrics — which is what
/// [adoptContext] and [clearSpanMemos] enforce.
class EditorSpanCache {
  /// Sentinel cached for lines the renderer leaves unhandled, so misses
  /// and "raw" lines are distinguishable with a single lookup.
  static const TextSpan unhandled = TextSpan();

  /// [PositionalSpanKey] tag: a ``` fence delimiter line.
  static const int positionalFenceDelimiter = 0;

  /// [PositionalSpanKey] tag: a line inside a ``` fence.
  static const int positionalFenceInterior = 1;

  /// [PositionalSpanKey] tag: an unchecked task line whose subtree is
  /// partially complete, so its box renders indeterminate.
  static const int positionalTaskIndeterminate = 2;

  /// [PositionalSpanKey] tag: a money row that displays a computed
  /// value; the key's `value` slot carries that row's balance.
  static const int positionalMoney = 3;

  static const int _spanCacheSize = 1024;
  static const int _positionalSpanCacheSize = 128;
  static const int _moneyParseMemoSize = 256;

  /// Sentinel cached for lines that lead with `$` but do not parse as a
  /// money row, so a negative result costs one lookup too. Compared by
  /// [identical]; none of its fields are ever read.
  static const MoneyLineMatch _notMoney = MoneyLineMatch(
    kind: MoneyLineKind.total,
    markerStart: -1,
    markerEnd: -1,
    amountStart: -1,
    amountEnd: -1,
    labelStart: -1,
    labelEnd: -1,
    amountFixed: 0,
  );

  final LruCache<String, TextSpan> _spanCache = LruCache(
    maxSize: _spanCacheSize,
  );

  final LruCache<PositionalSpanKey, TextSpan> _positionalSpanCache = LruCache(
    maxSize: _positionalSpanCacheSize,
  );

  final LruCache<String, MoneyLineMatch> _moneyParseMemo = LruCache(
    maxSize: _moneyParseMemoSize,
  );

  EditorRenderContext? _renderContext;

  /// Counts the [MarkdownMoneySyntax.parse] calls this cache actually
  /// makes (memo misses only). Debug builds only — the increment lives
  /// inside an [assert]. Surfaced to tests through the span builder;
  /// nothing in the app reads it.
  int debugMoneyParseCount = 0;

  /// The generation every cached span was built under, or `null` before
  /// the first build.
  EditorRenderContext? get renderContext => _renderContext;

  /// Adopts [context] as the current generation, dropping both span
  /// memos when it is a different one. Returns whether that happened —
  /// a theme, style or palette generation change is exactly what makes
  /// every cached span stale at once.
  bool adoptContext(EditorRenderContext context) {
    final current = _renderContext;
    if (current != null &&
        (identical(context, current) || context == current)) {
      return false;
    }
    _renderContext = context;
    clearSpanMemos();
    return true;
  }

  /// Drops both span memos — the text-keyed one and the positional one —
  /// which always invalidate together: every cached span holds
  /// already-resolved colours and metrics, so a theme, style, palette or
  /// money-display change makes all of them stale at once. The money
  /// parse memo is text-only and outlives all of it.
  void clearSpanMemos() {
    _spanCache.clear();
    _positionalSpanCache.clear();
  }

  /// The memoized span for a purely textual line, [unhandled] when the
  /// renderer declined it, or `null` on a miss.
  TextSpan? styled(String text) => _spanCache.get(text);

  /// Memoizes [span], or [unhandled] when the renderer declined the
  /// line, so a repeat build costs one lookup either way.
  void putStyled(String text, TextSpan? span) =>
      _spanCache.put(text, span ?? unhandled);

  /// The memoized span for a positionally-styled line, or `null`.
  TextSpan? positional(PositionalSpanKey key) => _positionalSpanCache.get(key);

  /// Memoizes [span] under [key]. Only ever called for off-caret lines:
  /// a reveal build is never memoized, positionally or textually.
  void putPositional(PositionalSpanKey key, TextSpan span) =>
      _positionalSpanCache.put(key, span);

  /// [MarkdownMoneySyntax.parse] behind the parse memo. The result is a
  /// pure function of the line text and [MoneyLineMatch] is immutable,
  /// so instances are safe to share; a `null` parse memoizes as
  /// [_notMoney] so lines that lead with `$` without being money rows
  /// stop re-scanning too.
  ///
  /// Money parsing is text-only but expensive (a hand-written scanner
  /// over the whole line), and the positional path has to know the row's
  /// kind *before* it can build its balance-keyed memo key — so every
  /// visible display-money line would re-parse on each layout pass even
  /// on a memo hit without this.
  MoneyLineMatch? parseMoney(String text) {
    final cached = _moneyParseMemo.get(text);
    if (cached != null) return identical(cached, _notMoney) ? null : cached;
    assert(() {
      debugMoneyParseCount++;
      return true;
    }());
    final parsed = MarkdownMoneySyntax.parse(text);
    _moneyParseMemo.put(text, parsed ?? _notMoney);
    return parsed;
  }
}
