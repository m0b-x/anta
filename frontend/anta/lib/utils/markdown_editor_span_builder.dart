import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../constants/markdown_constants.dart';
import 'ghost_text.dart';
import 'lru_cache.dart';
import 'markdown_callout_syntax.dart';
import 'markdown_color_syntax.dart';
import 'markdown_editor_line_index.dart';
import 'markdown_inline_grammar.dart';
import 'markdown_line_shape.dart';
import 'markdown_list_syntax.dart';
import 'markdown_money_syntax.dart';
import 'money_display_config.dart';

/// Live markdown rendering for the re_editor text mode (the "live
/// markdown rendering" editor setting, on by default).
///
/// Restyles one line at a time: headers at the preview's scale factors
/// (the re_editor fork gives a line whose root span sets a non-base
/// fontSize its own line height), bullets as `•`, task boxes as
/// custom-painted placeholder marks (checked / unchecked / indeterminate
/// when a parent's subtree is partially complete),
/// blockquote `>` as a `┃` bar with italic dimmed content,
/// `---` rules as dimmed `─` runs, `#tag` tokens tinted (render-only),
/// and `**bold**` / `*italic*` / `__bold__` / `_italic_` / `~~strike~~` /
/// `==highlight==` / `` `code` `` runs styled inline. `[text](url)`
/// links show their text tinted and underlined with the brackets + URL
/// concealed (render-only — tapping places the caret and the line
/// reveals raw for editing); bare `http(s)://` / `www.` URLs tint in
/// place with nothing concealed. Backslash escapes render the escaped
/// punctuation literally with the `\` concealed. Every one of those
/// inline constructs is found by [MarkdownInlineGrammar] — the one
/// tokenizer the preview reads too — so this surface only decides how
/// to *emit* a token, never what a token is; the line's shape (heading,
/// horizontal rule) comes from [MarkdownLineShape] for the same reason.
/// Callout lead lines
/// (`> [!TIP] title`) tint the quote bar and the `[!TYPE]` token with
/// the type's accent. Code-fence delimiter lines render monospace and
/// dimmed, fence interiors monospace over the inline-code background.
/// H5/H6 stay at base size but blend toward the primary colour (H6
/// additionally muted) so they read as headings. Ghost `{{ … }}`
/// runs compose with all of it: their markers stay concealed and the
/// inner text renders dimmed in whatever style surrounds it. Lines
/// covered by the selection render their markdown markers raw (dimmed)
/// so editing never happens on concealed characters.
///
/// Hard invariant (shared with the ghost-text builder): the returned
/// span always contains exactly the source line's UTF-16 code units —
/// markers are concealed or substituted 1:1, never inserted or removed —
/// so caret/selection offsets stay in sync with the model.
///
/// Performance model: everything is O(visible lines). Built spans are
/// memoized per line text in an LRU (cleared when the style/theme
/// generation changes), so steady-state scrolling and typing rebuild
/// only the edited line and the caret's reveal lines; returning the
/// identical span instance also keeps re_editor's paragraph cache on its
/// fast path. Positional state (fence roles, indeterminate task
/// parents) lives in [MarkdownEditorLineIndex], recomputed lazily per
/// CodeLines instance and resumed at the first changed segment, so a
/// keystroke rescans ~one segment instead of the whole document.
class MarkdownEditorSpanBuilder {
  static const Color _transparent = Color(0x00000000);
  static const double _concealedFontSize = 0.01;
  static const double _dimAlpha = 0.45;
  static const double _codeBackgroundAlpha = 0.08;
  static const double _quoteContentAlpha = 0.8;
  static const double _ruleAlpha = 0.3;
  static const double _tagBackgroundAlpha = 0.12;
  static const double _fenceDelimiterAlpha = 0.6;
  static const double _h56PrimaryBlend = 0.35;
  static const double _h6Alpha = 0.7;

  /// Lines longer than this render raw — matches the spirit of
  /// re_editor's maxLengthSingleLineRendering guard. Public so the
  /// wrapper's tap interception can refuse zones on lines that render
  /// raw for length.
  static const int maxStyledLineLength = 4096;

  static const int _spanCacheSize = 1024;

  /// Sentinel cached for lines this builder leaves unhandled, so misses
  /// and "raw" lines are distinguishable with a single lookup.
  static const TextSpan _unhandled = TextSpan();

  CodeLineEditingController? _controller;

  /// Positional state (fence roles + indeterminate task parents) lives
  /// in the shared incremental index: one fused rebuild per [CodeLines]
  /// change, resumed at the first changed segment instead of rescanning
  /// the whole document per keystroke.
  final MarkdownEditorLineIndex _lineIndex = MarkdownEditorLineIndex(
    maxScannedLineLength: maxStyledLineLength,
  );

  final LruCache<String, TextSpan> _spanCache = LruCache(
    maxSize: _spanCacheSize,
  );

  /// Positionally-styled lines (fence delimiter/interior, indeterminate
  /// task parents) can't share [_spanCache] — the same text renders
  /// differently depending on surrounding lines — but they still must
  /// return identical span instances so re_editor's paragraph cache
  /// stays on its fast path. Hence a small memo keyed by role + text
  /// ('d:'/'i:' fence roles, 't:' indeterminate task).
  static const int _positionalSpanCacheSize = 128;
  final LruCache<String, TextSpan> _positionalSpanCache = LruCache(
    maxSize: _positionalSpanCacheSize,
  );

  /// Money parsing is text-only but expensive (a hand-written scanner
  /// over the whole line), and the positional path has to know the row's
  /// kind *before* it can build its balance-keyed memo key — so every
  /// visible display-money line would re-parse on each layout pass even
  /// on a memo hit. This text-keyed memo makes the parse once-per-line
  /// instead, in front of both call sites.
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

  /// Never cleared: the parse is a pure function of the line text, so no
  /// configuration change can stale an entry, and the LRU bounds it.
  final LruCache<String, MoneyLineMatch> _moneyParseMemo = LruCache(
    maxSize: _moneyParseMemoSize,
  );

  /// Counts the [MarkdownMoneySyntax.parse] calls this builder actually
  /// makes (memo misses only). Debug builds only — the increment lives
  /// inside an [assert]. Test-only; nothing in the app reads it.
  @visibleForTesting
  int debugMoneyParseCount = 0;

  TextStyle? _cacheStyle;
  Color? _cacheBaseColor;
  Color? _cachePrimary;
  bool _isDark = false;

  /// Contrast colour for the check mark on a [_cachePrimary]-filled
  /// box; refreshed with the other theme-generation fields.
  Color _cacheOnAccent = Colors.white;

  MoneyDisplayConfig _moneyConfig = MoneyDisplayConfig.disabled;

  MarkdownColorPalette _colorPalette = MarkdownColorPalette.presets;

  void bind(CodeLineEditingController controller) {
    _controller = controller;
  }

  /// Applies the resolved money display configuration as one
  /// value-equal object. Called by the page on note load and when the
  /// settings change; a change to any span-visible field invalidates
  /// the span memos and the line index's ledger, same lifecycle as a
  /// theme change. When disabled, `$` lines render as plain text — see
  /// the guard in [_buildLine] and the positional branch in [build].
  /// (Start-balance changes skip the memo clear: positional keys carry
  /// the value, and op rows don't show it.)
  void configureMoney(MoneyDisplayConfig config) {
    if (config.enabled != _moneyConfig.enabled ||
        config.currencySymbol != _moneyConfig.currencySymbol ||
        config.currencySuffix != _moneyConfig.currencySuffix) {
      _clearSpanMemos();
    }
    _moneyConfig = config;
    _lineIndex.configureMoney(
      enabled: config.enabled,
      startCents: config.startCents,
    );
  }

  /// Applies the resolved colour palette for `{name:text}` runs and
  /// `==name:text==` highlights. Called by the page on note load and
  /// after returning from settings. A palette change invalidates the
  /// span memos — same lifecycle as a theme or money-config change —
  /// because cached spans hold already-resolved colours.
  ///
  /// Comparison is one string compare on the palette's persisted source
  /// (with an `identical` short-circuit), so re-applying an unchanged
  /// palette costs nothing and never clears a warm cache.
  void configureColors(MarkdownColorPalette palette) {
    if (palette == _colorPalette) return;
    _colorPalette = palette;
    _clearSpanMemos();
  }

  /// Drops both span memos — the text-keyed one and the positional one —
  /// which always invalidate together: every cached span holds
  /// already-resolved colours and metrics, so a theme, style, palette or
  /// money-display change makes all of them stale at once. The money
  /// parse memo is text-only and outlives all of it.
  void _clearSpanMemos() {
    _spanCache.clear();
    _positionalSpanCache.clear();
  }

  /// [MarkdownMoneySyntax.parse] behind [_moneyParseMemo]. The result is
  /// a pure function of the line text and [MoneyLineMatch] is immutable,
  /// so instances are safe to share; a `null` parse memoizes as
  /// [_notMoney] so lines that lead with `$` without being money rows
  /// stop re-scanning too.
  MoneyLineMatch? _parseMoney(String text) {
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

  /// Returns the restyled span for [codeLine], or `null` when this line
  /// is not handled (caller falls back to the ghost-text builder).
  TextSpan? build({
    required BuildContext context,
    required int index,
    required CodeLine codeLine,
    required TextStyle style,
  }) {
    final controller = _controller;
    if (controller == null) return null;
    final text = codeLine.text;
    if (text.isEmpty || text.length > maxStyledLineLength) return null;

    final theme = Theme.of(context);
    final baseColor =
        style.color ?? theme.textTheme.bodyLarge?.color ?? Colors.grey;
    final primary = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;
    if (style != _cacheStyle ||
        baseColor != _cacheBaseColor ||
        primary != _cachePrimary ||
        isDark != _isDark) {
      _clearSpanMemos();
      _cacheStyle = style;
      _cacheBaseColor = baseColor;
      _cachePrimary = primary;
      _isDark = isDark;
      _cacheOnAccent =
          ThemeData.estimateBrightnessForColor(primary) == Brightness.dark
          ? Colors.white
          : Colors.black87;
    }

    // Fence status is positional, not textual — fence lines are styled
    // straight from their role and never touch the text-keyed cache.
    final fenceRole = _fenceRoleAt(controller, index);
    if (fenceRole != MarkdownFenceRole.none) {
      final fenceKey = fenceRole == MarkdownFenceRole.delimiter
          ? 'd:$text'
          : 'i:$text';
      final cached = _positionalSpanCache.get(fenceKey);
      if (cached != null) return cached;
      final span = _buildFenceLine(
        text: text,
        role: fenceRole,
        style: style,
        baseColor: baseColor,
      );
      _positionalSpanCache.put(fenceKey, span);
      return span;
    }

    final reveal = selectionCoversLine(controller.selection, index);

    // `$$` money totals, `$?` net-change, `$^` entry-diff, and `$~`
    // checkpoint-span lines display a value computed from every op line
    // above — positional state from the shared index — so they style
    // through the positional memo with the value folded into the key,
    // mirroring fences. Reveal lines show raw `$$` / `$?` / `$^` / `$~`
    // and skip the paint. A `$` value slot in the label makes any row
    // display a computed value, so those join the positional path too;
    // the rest of the op lines (`$+ …`) are purely textual and stay on
    // the text-keyed path below.
    if (!reveal &&
        _moneyConfig.enabled &&
        MarkdownMoneySyntax.leadsWithMoney(text)) {
      final money = _parseMoney(text);
      if (money != null && MarkdownMoneySyntax.needsBalance(money)) {
        final balance =
            _lineIndex.moneyValueAt(controller.codeLines, index) ?? 0;
        final moneyKey = 'm:$balance:$text';
        final cached = _positionalSpanCache.get(moneyKey);
        if (cached != null) return cached;
        final span = _buildLine(
          text: text,
          style: style,
          baseColor: baseColor,
          primary: primary,
          reveal: false,
          money: money,
          moneyBalance: balance,
        );
        if (span != null) {
          _positionalSpanCache.put(moneyKey, span);
        }
        return span;
      }
    }

    // Task-parent aggregate state is positional too (it depends on the
    // child lines), so indeterminate parents style through the
    // positional memo, mirroring fences. Reveal lines show raw markers
    // and skip the facet entirely.
    if (!reveal && _isTaskIndeterminate(controller, index)) {
      final taskKey = 't:$text';
      final cached = _positionalSpanCache.get(taskKey);
      if (cached != null) return cached;
      final span = _buildLine(
        text: text,
        style: style,
        baseColor: baseColor,
        primary: primary,
        reveal: false,
        taskIndeterminate: true,
      );
      if (span != null) {
        _positionalSpanCache.put(taskKey, span);
      }
      return span;
    }

    if (!reveal) {
      final cached = _spanCache.get(text);
      if (cached != null) {
        return identical(cached, _unhandled) ? null : cached;
      }
    }
    final span = _buildLine(
      text: text,
      style: style,
      baseColor: baseColor,
      primary: primary,
      reveal: reveal,
    );
    if (!reveal) {
      _spanCache.put(text, span ?? _unhandled);
    }
    return span;
  }

  TextSpan? _buildLine({
    required String text,
    required TextStyle style,
    required Color baseColor,
    required Color primary,
    required bool reveal,
    bool taskIndeterminate = false,
    MoneyLineMatch? money,
    int moneyBalance = 0,
  }) {
    final ghosts = GhostText.mightContain(text)
        ? GhostText.findGhosts(text)
        : const <GhostMatch>[];

    // Money lines (`$+ 12.50 label`, `$$` total, optionally
    // header-prefixed) — grammar shared with the preview via
    // [MarkdownMoneySyntax]. Non-reveal totals arrive pre-parsed from
    // the positional path with their balance; op lines and reveal-mode
    // totals parse here (purely textual either way). A `#`-led line
    // that fails the money parse falls through to the header branch.
    if (_moneyConfig.enabled && MarkdownMoneySyntax.leadsWithMoney(text)) {
      final m = money ?? _parseMoney(text);
      if (m != null) {
        return _buildMoneyLine(
          text: text,
          m: m,
          style: style,
          baseColor: baseColor,
          primary: primary,
          reveal: reveal,
          ghosts: ghosts,
          balance: moneyBalance,
        );
      }
    }

    // Heading shape comes from [MarkdownLineShape] — the one predicate
    // the preview and the line-height calculator read — so leading
    // indent (a frequent leftover of list Enter-continuation) and a
    // bare `###` classify identically on every surface.
    final heading = MarkdownLineShape.headingAt(text);
    if (heading != null) {
      return _buildHeader(
        text: text,
        heading: heading,
        style: style,
        baseColor: baseColor,
        primary: primary,
        reveal: reveal,
        ghosts: ghosts,
      );
    }

    final item = MarkdownListSyntax.parse(text);
    if (item != null) {
      return _buildListItem(
        text: text,
        item: item,
        style: style,
        baseColor: baseColor,
        primary: primary,
        reveal: reveal,
        ghosts: ghosts,
        indeterminate: taskIndeterminate,
      );
    }

    if (MarkdownCalloutSyntax.isBlockquoteLine(text)) {
      return _buildQuote(
        text: text,
        style: style,
        baseColor: baseColor,
        primary: primary,
        reveal: reveal,
        ghosts: ghosts,
      );
    }

    if (MarkdownLineShape.isHorizontalRule(text)) {
      return _buildRule(
        text: text,
        style: style,
        baseColor: baseColor,
        reveal: reveal,
      );
    }

    final hasCandidates = MarkdownInlineGrammar.hasCandidates(text);
    if (!hasCandidates && ghosts.isEmpty) return null;
    final children = <InlineSpan>[];
    var styled = false;
    if (hasCandidates) {
      styled = _appendInline(
        text: text,
        start: 0,
        end: text.length,
        contextStyle: style,
        baseColor: baseColor,
        primary: primary,
        reveal: reveal,
        ghosts: ghosts,
        out: children,
        depth: 0,
      );
    } else {
      _emit(
        text: text,
        start: 0,
        end: text.length,
        style: style,
        baseColor: baseColor,
        ghosts: ghosts,
        out: children,
      );
    }
    if (!styled && ghosts.isEmpty) return null;
    return TextSpan(style: style, children: children);
  }

  /// Money-ledger line. Op rows conceal the `$` and render the op char
  /// in its accent (`-`/`*`//` substituted 1:1 with `−`/`×`/`÷`), the
  /// amount tinted, and the label with full inline styling — purely
  /// textual, so they live in the text-keyed memo. `$$` / `$?` / `$^`
  /// rows conceal the first `$` and substitute the second char 1:1 with
  /// a painted chip showing the computed [balance] (positional — cached
  /// upstream with the value in the key). On reveal both show raw
  /// dimmed markers, and the display rows paint nothing so the user
  /// edits real text; only marker conceal/substitution differs between
  /// reveal states, never line height.
  ///
  /// A heading prefix conceals its hashes and scales the row via the
  /// root span's fontSize (the fork gives such a line its own height,
  /// same as [_buildHeader] — identical in both reveal states). A
  /// resolved accent token is concealed and overrides the semantic
  /// accent; an unresolved one stays visible as plain source text.
  /// A money row's list-marker prefix, `[listMarkerStart, markerStart)`:
  /// the bullet substitutes 1:1 with `•` exactly like [_buildListItem]
  /// (ordered numbers stay as typed, tinted), and the gap spaces keep
  /// their width — every code unit at its offset, reading as a list
  /// item. Callers emit `[0, listMarkerStart)` (the indent) themselves.
  void _emitMoneyListMarker({
    required String text,
    required MoneyLineMatch m,
    required int gapEnd,
    required TextStyle style,
    required Color baseColor,
    required Color primary,
    required bool reveal,
    required List<InlineSpan> out,
  }) {
    final mc = text.codeUnitAt(m.listMarkerStart);
    if (mc >= 0x30 && mc <= 0x39) {
      out.add(
        TextSpan(
          text: text.substring(m.listMarkerStart, m.listMarkerEnd),
          style: style.copyWith(color: primary, fontWeight: FontWeight.w600),
        ),
      );
    } else {
      out.add(
        TextSpan(
          text: reveal
              ? text.substring(m.listMarkerStart, m.listMarkerEnd)
              : '•',
          style: reveal
              ? _dimStyle(style, baseColor)
              : style.copyWith(color: primary, fontWeight: FontWeight.bold),
        ),
      );
    }
    // [gapEnd] is where the next chrome piece begins: heading hashes,
    // an emphasis opener, or the `$` itself — the caller knows.
    if (m.listMarkerEnd < gapEnd) {
      out.add(
        TextSpan(text: text.substring(m.listMarkerEnd, gapEnd), style: style),
      );
    }
  }

  /// The emphasis closing run (plus any trailing spaces): chrome,
  /// concealed off-caret and dimmed raw on reveal, appended after all
  /// content so the code-unit inventory stays complete. Error rows skip
  /// this — their raw warn emit already covers to the line end.
  void _emitEmphasisCloser({
    required String text,
    required MoneyLineMatch m,
    required TextStyle style,
    required Color baseColor,
    required bool reveal,
    required List<InlineSpan> out,
  }) {
    if (m.emphasisCloseStart < 0) return;
    out.add(
      TextSpan(
        text: text.substring(m.emphasisCloseStart),
        style: reveal ? _dimStyle(style, baseColor) : _concealStyle(style),
      ),
    );
  }

  /// Money-row root span: plain normally, the fork's hanging span when
  /// the row carries a list-marker prefix so soft-wrapped continuation
  /// aligns under the `$` like any list item's content. Identical in
  /// both reveal states, exactly like [_buildListItem]'s root.
  TextSpan _finishMoneyLine(
    MoneyLineMatch m,
    TextStyle style,
    List<InlineSpan> children,
  ) {
    if (m.listMarkerStart < 0) {
      return TextSpan(style: style, children: children);
    }
    return CodeHangingTextSpan(
      hangingChars: m.markerStart,
      style: style,
      children: children,
    );
  }

  TextSpan _buildMoneyLine({
    required String text,
    required MoneyLineMatch m,
    required TextStyle style,
    required Color baseColor,
    required Color primary,
    required bool reveal,
    required List<GhostMatch> ghosts,
    required int balance,
  }) {
    // Error rows keep the source text — the editor must never change a
    // line's code units, so the message itself lives in the preview and
    // the detail sheet. Off-caret the `$` substitutes 1:1 with the `!`
    // the warning promises and the row tints yellow over a subtle
    // band; on reveal the raw source shows warn-tinted, no substitution.
    // Deliberately unscaled by any heading prefix (matching the
    // preview): both reveal states share the base height.
    if (MarkdownMoneySyntax.hasError(m)) {
      final warn = MarkdownConstants.moneyWarning(dark: _isDark);
      final children = <InlineSpan>[];
      // Pre-marker chrome: heading hashes and/or emphasis opener,
      // contiguous by grammar; the emphasis closer needs no handling
      // here — the raw warn emit below covers to the line end.
      final chromeFrom = m.headerStart >= 0
          ? m.headerStart
          : m.emphasisStart >= 0
          ? m.emphasisStart
          : m.markerStart;
      final lead = m.listMarkerStart >= 0 ? m.listMarkerStart : chromeFrom;
      if (lead > 0) {
        children.add(TextSpan(text: text.substring(0, lead), style: style));
      }
      if (reveal) {
        _emit(
          text: text,
          start: lead,
          end: text.length,
          style: style.copyWith(color: warn),
          baseColor: baseColor,
          ghosts: ghosts,
          out: children,
        );
        return _finishMoneyLine(m, style, children);
      }
      final warnStyle = style.copyWith(
        color: warn,
        backgroundColor: warn.withValues(alpha: 0.1),
      );
      if (m.listMarkerStart >= 0) {
        // A broken bulleted row keeps its list marker, so the list
        // reads intact around the yellow row.
        _emitMoneyListMarker(
          text: text,
          m: m,
          gapEnd: chromeFrom,
          style: style,
          baseColor: baseColor,
          primary: primary,
          reveal: false,
          out: children,
        );
      }
      if (chromeFrom < m.markerStart) {
        children.add(
          TextSpan(
            text: text.substring(chromeFrom, m.markerStart),
            style: _concealStyle(style),
          ),
        );
      }
      children.add(
        TextSpan(
          text: '!',
          style: warnStyle.copyWith(fontWeight: FontWeight.bold),
        ),
      );
      _emit(
        text: text,
        start: m.markerStart + 1,
        end: text.length,
        style: warnStyle,
        baseColor: baseColor,
        ghosts: ghosts,
        out: children,
      );
      return _finishMoneyLine(m, style, children);
    }

    // The list-marker prefix is chrome *outside* the row's own styling:
    // it must render exactly like [_buildListItem]'s, or a bulleted
    // money row stops aligning with its plain siblings. Captured before
    // the heading/emphasis mutations below — a heading-scaled bullet is
    // bigger and a bold one has a wider trailing space, either of which
    // pushes the row's marker (and everything after it) off the list's
    // left edge.
    final listStyle = style;
    if (m.headerLevel > 0) {
      style = style.copyWith(
        fontSize: (style.fontSize ?? 16.0) * _headerScale(m.headerLevel),
        fontWeight: FontWeight.bold,
      );
    }
    // An emphasis wrapper styles the whole row; its marker runs conceal
    // with the rest of the pre-marker chrome below, and the closer is
    // appended (concealed) at the end of every path, so all code units
    // keep their offsets.
    if (m.emphasisLen > 0) {
      style = style.copyWith(
        fontStyle: m.emphasisItalic ? FontStyle.italic : null,
        fontWeight: m.emphasisBold ? FontWeight.bold : null,
      );
    }
    // The pre-marker chrome run: heading hashes and/or emphasis opener,
    // contiguous by grammar, concealed as one — `_buildHeader` does the
    // same for its `level + 1` chars.
    final chromeFrom = m.headerStart >= 0
        ? m.headerStart
        : m.emphasisStart >= 0
        ? m.emphasisStart
        : m.markerStart;
    final children = <InlineSpan>[];
    if (m.listMarkerStart >= 0) {
      // List-marker prefix: the indent stays visible so nesting keeps
      // its width, then the marker renders exactly like a list item's —
      // in [listStyle], the row's *unstyled* base, so the bullet sits on
      // the same left edge as every sibling bullet. Heading hashes / an
      // emphasis opener may follow (`- ## $$`, `- *$~ 2 x*`) — they
      // conceal below just like the list-less shapes.
      if (m.listMarkerStart > 0) {
        children.add(
          TextSpan(
            text: text.substring(0, m.listMarkerStart),
            style: listStyle,
          ),
        );
      }
      _emitMoneyListMarker(
        text: text,
        m: m,
        gapEnd: chromeFrom,
        style: listStyle,
        baseColor: baseColor,
        primary: primary,
        reveal: reveal,
        out: children,
      );
    } else if (chromeFrom > 0) {
      children.add(TextSpan(text: text.substring(0, chromeFrom), style: style));
    }
    if (chromeFrom < m.markerStart) {
      children.add(
        TextSpan(
          text: text.substring(chromeFrom, m.markerStart),
          style: reveal ? _dimStyle(style, baseColor) : _concealStyle(style),
        ),
      );
    }

    MarkdownColorSpec? accentSpec;
    if (m.accentStart >= 0) {
      accentSpec = _colorPalette.lookup(
        text.substring(m.accentStart, m.accentEnd),
      );
    }

    // Glyph and semantic accent come from the shared palette (same two
    // functions the preview reads). Display kinds carry no op glyph
    // here — their chip paints the glyph itself — and `$! N`
    // declarations render source-faithfully like op rows (`!` → `◎`
    // amount-first; written label-first the row is a statement and the
    // glyph is suppressed, the `:` staying visible as typed). The
    // remaining budget lives on the bare `$!` status chip. A `$!`
    // status row with no target above it warns instead of reading green
    // off the sentinel; a resolved accent token overrides the semantic
    // colour either way.
    final bool noTarget =
        m.kind == MoneyLineKind.remaining &&
        MarkdownMoneySyntax.isNoTarget(balance);
    Color accent = noTarget
        ? MarkdownConstants.moneyWarning(dark: _isDark)
        : MarkdownConstants.moneyAccent(
            m.kind,
            balance,
            dark: _isDark,
            primary: primary,
          );
    final String opGlyph = MarkdownMoneySyntax.isDisplayKind(m.kind)
        ? ''
        : MarkdownMoneySyntax.glyph(m.kind);
    if (accentSpec != null) {
      accent = accentSpec.text(dark: _isDark);
    }
    final accentStyle = style.copyWith(
      color: accent,
      fontWeight: FontWeight.w600,
    );
    // The label takes the row's accent — resolved colour token when
    // there is one, otherwise the semantic sign colour — matching the
    // preview. Colour only, so the base weight stays and the value
    // still leads.
    final labelStyle = style.copyWith(color: accent);

    // The accent token region: concealed when resolved (it is chrome,
    // like `{name:`), left as plain source text when it does not
    // resolve — nothing is ever silently eaten.
    // [concealGaps] hides the spaces around the token as well, for rows
    // whose whole marker run is chrome (label-first, where the op glyph
    // renders at the `:` instead) — otherwise they indent the row.
    void emitAccentToken(int from, int to, {bool concealGaps = false}) {
      final gapStyle = concealGaps ? _concealStyle(style) : style;
      if (from < m.accentStart) {
        children.add(
          TextSpan(text: text.substring(from, m.accentStart), style: gapStyle),
        );
      }
      children.add(
        TextSpan(
          text: text.substring(m.accentStart, m.accentEnd + 1),
          style: reveal ? _dimStyle(style, baseColor) : _concealStyle(style),
        ),
      );
      if (m.accentEnd + 1 < to) {
        children.add(
          TextSpan(text: text.substring(m.accentEnd + 1, to), style: gapStyle),
        );
      }
    }

    // One shared derivation of the row's shape (same object the preview
    // builds), so the surfaces cannot disagree on flags or slot. Label
    // text still renders from the raw match offsets — this surface is
    // source-faithful and keeps the currency word visible.
    final layout = MoneyRowLayout.of(text, m, _moneyConfig.currencySymbol);
    final isDisplay = layout.isDisplay;
    final slot = layout.slot;
    final hasSlot = slot >= 0;
    // Label-first rows (`$= Net worth: 5000`) read as an equation: the
    // op glyph renders at the `:` instead of leading the row. Needed
    // this early because it changes how the marker itself is emitted.
    final bool amountTrails = layout.labelFirst;
    // A count-taking display row may carry its accent token *after* the
    // count (`$~ 2 teal:`); the token then sits between the count and the
    // label rather than in the marker gap, and is concealed there instead.
    final bool accentAfterCount = layout.accentAfterCount;
    if (isDisplay) {
      if (reveal) {
        children.add(
          TextSpan(
            text: text.substring(m.markerStart, m.markerEnd),
            style: _dimStyle(style, baseColor),
          ),
        );
      } else if (hasSlot) {
        // The chip moved to the label's slot, so the marker renders like
        // an op row: `$` concealed, second char substituted 1:1 with the
        // kind's glyph. The substitution must stay one code unit wide or
        // the caret drifts, so `Δ=` narrows to `Δ` here — the `$^` count
        // digits and the signed value carry the distinction from `$?`.
        // (`Σ` and `◎` are already single code units.)
        children.add(TextSpan(text: r'$', style: _concealStyle(style)));
        children.add(
          TextSpan(
            text: switch (m.kind) {
              MoneyLineKind.total => 'Σ',
              MoneyLineKind.remaining => '◎',
              _ => 'Δ',
            },
            style: accentStyle,
          ),
        );
      } else {
        children.add(TextSpan(text: r'$', style: _concealStyle(style)));
        children.add(
          _moneyTotalSpan(
            style: style,
            accent: accent,
            balance: balance,
            kind: m.kind,
          ),
        );
      }
    } else {
      children.add(
        TextSpan(
          text: r'$',
          style: reveal ? _dimStyle(style, baseColor) : _concealStyle(style),
        ),
      );
      // On a label-first row the glyph renders at the `:` further along,
      // so the op char is concealed here instead of substituted. It must
      // still be emitted as its own source char — concealed, not
      // dropped — or every offset after it shifts by one.
      children.add(
        TextSpan(
          text: (reveal || amountTrails)
              ? text.substring(m.markerStart + 1, m.markerEnd)
              : opGlyph,
          style: reveal
              ? _dimStyle(style, baseColor)
              : amountTrails
              ? _concealStyle(style)
              : accentStyle,
        ),
      );
    }

    // Emits a label region, substituting the value slot's lone `$` 1:1
    // with the painted value — exactly like the second `$` of a `$$`
    // marker. Featured as a tinted chip on display rows, dimmed and
    // unfilled on op rows and `$=`/`$!` declarations, mirroring the
    // preview's pill/annotation split. On reveal the slot stays literal
    // text so the user edits real source.
    void emitLabelRegion(int from, int to) {
      if (from >= to) return;
      if (hasSlot && !reveal && slot >= from && slot < to) {
        if (from < slot) {
          _appendInline(
            text: text,
            start: from,
            end: slot,
            contextStyle: labelStyle,
            baseColor: baseColor,
            primary: primary,
            reveal: reveal,
            ghosts: ghosts,
            out: children,
            depth: 0,
          );
        }
        children.add(
          _moneyTotalSpan(
            style: style,
            // Display rows keep their row accent (sentinel and pinned
            // resolve to the warning inside); op rows and the `$=`/`$!`
            // declaration slot spellings take the dimmed bare-number
            // look their preview annotation has.
            accent: isDisplay ? accent : baseColor.withValues(alpha: 0.5),
            balance: balance,
            kind: m.kind,
            atSlot: true,
            filled: isDisplay,
          ),
        );
        if (slot + 1 < to) {
          _appendInline(
            text: text,
            start: slot + 1,
            end: to,
            contextStyle: labelStyle,
            baseColor: baseColor,
            primary: primary,
            reveal: reveal,
            ghosts: ghosts,
            out: children,
            depth: 0,
          );
        }
      } else {
        _appendInline(
          text: text,
          start: from,
          end: to,
          contextStyle: labelStyle,
          baseColor: baseColor,
          primary: primary,
          reveal: reveal,
          ghosts: ghosts,
          out: children,
          depth: 0,
        );
      }
    }

    // A count-taking display row's window count (`$^ 2`, `$~ ALL`) is
    // syntax, not content — it selects the window the row measures just
    // as the accent token selects its colour — so the whole chrome run
    // from the marker to the label (spaces, accent token, count, in
    // either order) is concealed as one, keeping only the single space
    // that separates the painted chip from the label. Concealed, never
    // dropped: every source char stays in the span tree at its true
    // offset, so caret arithmetic is untouched and reveal (caret on the
    // line) shows the count again for editing. An unresolved accent
    // token opts the row out — nothing the parser could not resolve is
    // ever silently eaten — matching the preview, which simply declines
    // to paint the same run.
    final bool concealCount =
        isDisplay &&
        !reveal &&
        m.amountEnd > m.amountStart &&
        (m.accentStart < 0 || accentSpec != null);
    if (concealCount) {
      // The parser skips spaces to reach the label, so whenever a label
      // follows there is a space right before it to leave visible.
      // Bounded by [MoneyRowLayout.contentEnd], never the line length:
      // on an emphasis-wrapped row (`*$^ 2*`) the label is empty and
      // starts at the closer, and testing against the line length would
      // read that as "a label follows" and leave the count visible.
      final int keep = m.labelStart < layout.contentEnd
          ? m.labelStart - 1
          : m.labelStart;
      if (m.markerEnd < keep) {
        children.add(
          TextSpan(
            text: text.substring(m.markerEnd, keep),
            style: _concealStyle(style),
          ),
        );
      }
      if (keep < m.labelStart) {
        children.add(
          TextSpan(text: text.substring(keep, m.labelStart), style: style),
        );
      }
      emitLabelRegion(m.labelStart, layout.contentEnd);
      _emitEmphasisCloser(
        text: text,
        m: m,
        style: style,
        baseColor: baseColor,
        reveal: reveal,
        out: children,
      );
      return _finishMoneyLine(m, style, children);
    }

    // Between the marker and whatever comes first sit only spaces and
    // the optional accent token (parse-guaranteed, so no ghost can start
    // here). On a label-first row (`$- Loss: 5000`) that run ends at the
    // label instead of the amount — every span below stays a contiguous
    // source range in document order, which is what keeps editor offsets
    // 1:1 regardless of which order the row was written in.
    final int gapEnd = amountTrails ? m.labelStart : m.amountStart;
    // On a label-first row the glyph has moved to the `:`, so this whole
    // run is chrome and must not take up width. The exception is an
    // unresolved accent token, which stays visible as literal source
    // (nothing is ever silently eaten) and brings its spacing with it.
    final bool chromeGap = amountTrails && !reveal;
    if (m.markerEnd < gapEnd) {
      if (accentSpec != null && !accentAfterCount) {
        emitAccentToken(m.markerEnd, gapEnd, concealGaps: chromeGap);
      } else {
        children.add(
          TextSpan(
            text: text.substring(m.markerEnd, gapEnd),
            style: chromeGap && m.accentStart < 0
                ? _concealStyle(style)
                : style,
          ),
        );
      }
    }
    if (amountTrails) {
      if (reveal || m.kind == MoneyLineKind.target) {
        // Raw source while editing: the `:` stays a plain character and
        // the marker above shows its dimmed `$=`. A `$!` declaration
        // keeps its `:` in *both* states — written label-first it is a
        // statement, not an equation, so no target glyph renders and
        // `### $! yellow: Groceries: 500` reads "Groceries: 500"
        // (matching the preview's icon suppression).
        emitLabelRegion(m.labelStart, m.labelEnd);
      } else {
        emitLabelRegion(m.labelStart, m.labelEnd - 1);
        // The `:` is chrome here, replaced by the op glyph so the row
        // reads `Net worth = 5000`. It goes through the placeholder
        // mechanism rather than a 1:1 text swap because the source has
        // no character before the `:` to render as a space — a plain
        // substitution would read `Net worth= 5000`.
        children.add(_glyphSpan(style: style, accent: accent, glyph: opGlyph));
      }
      if (m.labelEnd < m.amountStart) {
        children.add(
          TextSpan(
            text: text.substring(m.labelEnd, m.amountStart),
            style: style,
          ),
        );
      }
      _emit(
        text: text,
        start: m.amountStart,
        end: m.amountEnd,
        style: accentStyle,
        baseColor: baseColor,
        ghosts: ghosts,
        out: children,
      );
      // Free trailing text after the amount (`$= Worth: 500 lei so
      // far`): a label region like any other, slot included. The
      // currency word stays visible as typed — this surface renders
      // source faithfully, same as amounts.
      emitLabelRegion(m.amountEnd, layout.contentEnd);
    } else {
      // The amount run covers op amounts and `$^ N` count digits alike —
      // display rows without a count have an empty range.
      if (m.amountStart < m.amountEnd) {
        _emit(
          text: text,
          start: m.amountStart,
          end: m.amountEnd,
          style: accentStyle,
          baseColor: baseColor,
          ghosts: ghosts,
          out: children,
        );
      }
      if (accentAfterCount && accentSpec != null) {
        // A resolved accent written after the count is chrome, exactly
        // like an accent-first row: conceal the token between the count
        // and the label, then render the label proper. An unresolved
        // token falls through to the label run and stays visible as typed.
        emitAccentToken(m.amountEnd, m.labelStart);
        emitLabelRegion(m.labelStart, layout.contentEnd);
      } else {
        emitLabelRegion(m.amountEnd, layout.contentEnd);
      }
    }
    _emitEmphasisCloser(
      text: text,
      m: m,
      style: style,
      baseColor: baseColor,
      reveal: reveal,
      out: children,
    );
    return _finishMoneyLine(m, style, children);
  }

  /// A single op glyph painted into a label-first row's `:` placeholder,
  /// carrying the horizontal padding a 1:1 text substitution cannot: the
  /// source has no character before the `:` to render as a space, so a
  /// plain swap would read `Net worth= 5000`. Same fork
  /// [CodeInlinePaintSpan] mechanism as the money chip, unfilled — and
  /// like op rows generally it depends only on the line text, so it
  /// rides the text-keyed span memo and lays out once per unique line.
  _EditorMoneyTotalSpan _glyphSpan({
    required TextStyle style,
    required Color accent,
    required String glyph,
  }) {
    final fontSize = style.fontSize ?? 16.0;
    final painter = TextPainter(
      text: TextSpan(
        text: glyph,
        style: style.copyWith(
          color: accent,
          fontWeight: FontWeight.w600,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final lineBox = fontSize * (style.height ?? MarkdownConstants.lineHeight);
    final maxHeight = lineBox * 0.9;
    final height = painter.height > maxHeight ? maxHeight : painter.height;
    return _EditorMoneyTotalSpan(
      width: painter.width + fontSize * 0.6,
      height: height,
      painter: painter,
      label: glyph,
      accent: accent,
      chip: const Color(0x00000000),
      radius: 0,
    );
  }

  /// Builds the painted chip for a `$$` total (`Σ` + balance), a `$?`
  /// net change (`Δ` + signed change), a bare `$!` target status (`◎` +
  /// remaining budget, or "no target"), a `$^` entry diff (`Δ=` +
  /// signed move), or a `$~` checkpoint span (`Δ~` + signed move), laid
  /// out once here (memoized upstream via the positional span cache)
  /// and painted into the placeholder box.
  /// The box height stays under the line's strut height so the line
  /// never grows.
  ///
  /// [atSlot] drops the leading glyph — a row whose value sits in a
  /// label slot already renders that glyph at its marker, and the label
  /// itself says what the number is. [filled] draws the rounded chip
  /// behind it; op rows pass `false` for the dimmed bare-number look
  /// their trailing `=` annotation has in the preview.
  _EditorMoneyTotalSpan _moneyTotalSpan({
    required TextStyle style,
    required Color accent,
    required int balance,
    required MoneyLineKind kind,
    bool atSlot = false,
    bool filled = true,
  }) {
    // A value pinned at the clamp limit paints in the warning accent —
    // the number shown is the cap, not real arithmetic. Checked here so
    // the marker chip and the slot chip can never disagree. A bare `$!`
    // with no target above it is the same shape of exception: the
    // sentinel is not money, so the chip says "no target" in the same
    // warning accent instead of formatting it.
    final noTarget =
        kind == MoneyLineKind.remaining &&
        MarkdownMoneySyntax.isNoTarget(balance);
    if (noTarget || MarkdownMoneySyntax.valuePinned(balance)) {
      accent = MarkdownConstants.moneyWarning(dark: _isDark);
    }
    final signed = MarkdownMoneySyntax.isSignedKind(kind);
    final value = noTarget
        ? 'no target'
        : signed
        ? MarkdownMoneySyntax.formatCentsSignedWithSymbol(
            balance,
            symbol: _moneyConfig.currencySymbol,
            suffix: _moneyConfig.currencySuffix,
          )
        : MarkdownMoneySyntax.formatCentsWithSymbol(
            balance,
            symbol: _moneyConfig.currencySymbol,
            suffix: _moneyConfig.currencySuffix,
          );
    // Chip glyph from the shared palette; only display kinds reach the
    // non-slot label (op-row chips always sit at a slot).
    final label = atSlot ? value : '${MarkdownMoneySyntax.glyph(kind)} $value';
    final fontSize = style.fontSize ?? 16.0;
    final lineBox = fontSize * (style.height ?? MarkdownConstants.lineHeight);
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: style.copyWith(
          color: accent,
          fontWeight: FontWeight.bold,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final hPad = fontSize * 0.3;
    var chipHeight = painter.height + fontSize * 0.12;
    final maxHeight = lineBox * 0.9;
    if (chipHeight > maxHeight) chipHeight = maxHeight;
    return _EditorMoneyTotalSpan(
      width: painter.width + hPad * 2,
      height: chipHeight,
      painter: painter,
      label: label,
      accent: accent,
      chip: filled
          ? accent.withValues(alpha: _tagBackgroundAlpha)
          : const Color(0x00000000),
      radius: fontSize * 0.35,
    );
  }

  /// ATX heading, shaped by [MarkdownLineShape.headingAt]: the hashes
  /// and their separating space (`[hashStart, contentStart)` — empty
  /// content for a bare `###`) conceal as one chrome run, and the rest
  /// of the line renders inline at the level's scale.
  TextSpan _buildHeader({
    required String text,
    required MarkdownHeadingMatch heading,
    required TextStyle style,
    required Color baseColor,
    required Color primary,
    required bool reveal,
    required List<GhostMatch> ghosts,
  }) {
    final level = heading.level;
    final start = heading.hashStart;
    final baseSize = style.fontSize ?? 16.0;
    var headerStyle = style.copyWith(
      fontSize: baseSize * _headerScale(level),
      fontWeight: FontWeight.bold,
    );
    // H5/H6 keep the base size (sub-base line heights buy nothing in the
    // editor), so they distinguish themselves by colour instead: blended
    // toward primary, H6 additionally muted below H5.
    if (level >= 5) {
      final blended = Color.lerp(baseColor, primary, _h56PrimaryBlend)!;
      headerStyle = headerStyle.copyWith(
        color: level == 5 ? blended : blended.withValues(alpha: _h6Alpha),
      );
    }
    // [start] is past any leading indent — kept visible (like list
    // indent) while the hashes + their space conceal, so an indented
    // header keeps its width and only the chrome disappears.
    final markerEnd = heading.contentStart;
    final children = <InlineSpan>[
      if (start > 0)
        TextSpan(text: text.substring(0, start), style: headerStyle),
      TextSpan(
        text: text.substring(start, markerEnd),
        style: reveal
            ? _dimStyle(headerStyle, baseColor)
            : _concealStyle(headerStyle),
      ),
    ];
    _appendInline(
      text: text,
      start: markerEnd,
      end: text.length,
      contextStyle: headerStyle,
      baseColor: baseColor,
      primary: primary,
      reveal: reveal,
      ghosts: ghosts,
      out: children,
      depth: 0,
    );
    return TextSpan(style: headerStyle, children: children);
  }

  /// Blockquote line: the `>` is substituted 1:1 with a `┃` bar (both a
  /// single code unit) tinted like the preview's quote bar, and the
  /// content renders italic and dimmed with inline styling intact.
  /// Callout lead lines (`> [!TIP] title`) tint the bar and the
  /// `[!TYPE]` token with the type's accent (palette shared with the
  /// preview via [MarkdownConstants.calloutAccent]); the token stays
  /// tinted on reveal since nothing in it is concealed. Continuation
  /// lines keep the plain-quote treatment — the styling stays purely
  /// textual so the span memo stays valid. On reveal the raw `>` shows
  /// dimmed; line height never changes.
  TextSpan _buildQuote({
    required String text,
    required TextStyle style,
    required Color baseColor,
    required Color primary,
    required bool reveal,
    required List<GhostMatch> ghosts,
  }) {
    var gt = 0;
    while (text.codeUnitAt(gt) != 0x3E) {
      gt++;
    }
    final lead = MarkdownCalloutSyntax.parseLead(text);
    final accent = lead != null
        ? MarkdownConstants.calloutAccent(lead.type, dark: _isDark)
        : null;
    final children = <InlineSpan>[];
    if (gt > 0) {
      children.add(TextSpan(text: text.substring(0, gt), style: style));
    }
    children.add(
      TextSpan(
        text: reveal ? '>' : '┃',
        style: reveal
            ? _dimStyle(style, baseColor)
            : style.copyWith(
                color:
                    accent ??
                    (_isDark ? Colors.grey.shade700 : Colors.grey.shade300),
              ),
      ),
    );
    var contentStart = gt + 1;
    if (lead != null && accent != null) {
      if (lead.tokenStart > contentStart) {
        children.add(
          TextSpan(
            text: text.substring(contentStart, lead.tokenStart),
            style: style,
          ),
        );
      }
      children.add(
        TextSpan(
          text: text.substring(lead.tokenStart, lead.tokenEnd),
          style: style.copyWith(color: accent, fontWeight: FontWeight.w600),
        ),
      );
      contentStart = lead.tokenEnd;
    }
    if (contentStart < text.length) {
      _appendInline(
        text: text,
        start: contentStart,
        end: text.length,
        contextStyle: style.copyWith(
          fontStyle: FontStyle.italic,
          color: baseColor.withValues(alpha: _quoteContentAlpha),
        ),
        baseColor: baseColor,
        primary: primary,
        reveal: reveal,
        ghosts: ghosts,
        out: children,
        depth: 0,
      );
    }
    return TextSpan(style: style, children: children);
  }

  /// Horizontal rule: every `-` / `*` / `_` is substituted 1:1 with `─`
  /// (one code unit each) and dimmed, so contiguous glyphs read as a
  /// line. Base font size is kept — like H5/H6, a sub-base line height
  /// buys nothing in the editor. On reveal the raw markers show dimmed.
  TextSpan _buildRule({
    required String text,
    required TextStyle style,
    required Color baseColor,
    required bool reveal,
  }) {
    if (reveal) {
      return TextSpan(
        style: style,
        children: [TextSpan(text: text, style: _dimStyle(style, baseColor))],
      );
    }
    final units = List<int>.generate(text.length, (i) {
      final c = text.codeUnitAt(i);
      return _isSpace(c) ? c : 0x2500;
    });
    return TextSpan(
      style: style,
      children: [
        TextSpan(
          text: String.fromCharCodes(units),
          style: style.copyWith(color: baseColor.withValues(alpha: _ruleAlpha)),
        ),
      ],
    );
  }

  TextSpan _buildListItem({
    required String text,
    required MarkdownListItem item,
    required TextStyle style,
    required Color baseColor,
    required Color primary,
    required bool reveal,
    required List<GhostMatch> ghosts,
    bool indeterminate = false,
  }) {
    final children = <InlineSpan>[];
    if (item.indent.isNotEmpty) {
      children.add(TextSpan(text: item.indent, style: style));
    }
    var contentStyle = style;

    switch (item.kind) {
      case MarkdownListKind.bullet:
        final markerEnd = item.indent.length + item.marker.length;
        children.add(
          TextSpan(
            text: reveal ? item.marker : '•',
            style: reveal
                ? _dimStyle(style, baseColor)
                : style.copyWith(color: primary, fontWeight: FontWeight.bold),
          ),
        );
        if (markerEnd < item.contentStart) {
          children.add(
            TextSpan(
              text: text.substring(markerEnd, item.contentStart),
              style: style,
            ),
          );
        }
      case MarkdownListKind.ordered:
        final markerEnd =
            item.indent.length + item.marker.length + item.delimiter.length;
        children.add(
          TextSpan(
            text: '${item.marker}${item.delimiter}',
            style: style.copyWith(color: primary, fontWeight: FontWeight.w600),
          ),
        );
        if (markerEnd < item.contentStart) {
          children.add(
            TextSpan(
              text: text.substring(markerEnd, item.contentStart),
              style: style,
            ),
          );
        }
      case MarkdownListKind.task:
        final boxEnd = item.bracketStart + 3;
        if (reveal) {
          children.add(
            TextSpan(
              text: text.substring(item.indent.length, boxEnd),
              style: _dimStyle(style, baseColor),
            ),
          );
        } else {
          children.add(
            TextSpan(
              text: text.substring(item.indent.length, item.bracketStart),
              style: _concealStyle(style),
            ),
          );
          // The box substitutes 1:1 for the `[` code unit as a
          // placeholder run (fork's CodeInlinePaintSpan): custom-painted,
          // sized off the line's own font size, and centered on the line
          // box by the paragraph layout itself — no font-metric fudging.
          // Clamped under the strut height so the line never grows.
          final baseSize = style.fontSize ?? 16.0;
          final lineBox =
              baseSize * (style.height ?? MarkdownConstants.lineHeight);
          var side = baseSize * MarkdownConstants.editorCheckboxScale;
          if (side > lineBox * 0.85) side = lineBox * 0.85;
          children.add(
            _EditorCheckboxSpan(
              side: side,
              visual: item.checked
                  ? _CheckboxVisual.checked
                  : indeterminate
                  ? _CheckboxVisual.indeterminate
                  : _CheckboxVisual.unchecked,
              accent: primary,
              border: baseColor.withValues(
                alpha: MarkdownConstants.uncheckedCheckboxOpacity,
              ),
              mark: _cacheOnAccent,
            ),
          );
          children.add(
            TextSpan(
              text: text.substring(item.bracketStart + 1, boxEnd),
              style: _concealStyle(style),
            ),
          );
        }
        if (boxEnd < item.contentStart) {
          children.add(
            TextSpan(
              text: text.substring(boxEnd, item.contentStart),
              style: style,
            ),
          );
        }
        if (item.checked) {
          final checkedColor = baseColor.withValues(
            alpha: MarkdownConstants.checkedTextOpacity,
          );
          contentStyle = style.copyWith(
            color: checkedColor,
            decoration: TextDecoration.lineThrough,
            decorationColor: checkedColor,
          );
        }
    }

    if (item.contentStart < text.length) {
      _appendInline(
        text: text,
        start: item.contentStart,
        end: text.length,
        contextStyle: contentStyle,
        baseColor: baseColor,
        primary: primary,
        reveal: reveal,
        ghosts: ghosts,
        out: children,
        depth: 0,
      );
      // Hanging indent: the fork lays out the marker prefix and the
      // content as two paragraphs, so soft-wrapped continuation lines
      // align under the content (Obsidian-style). Code units and span
      // order are untouched — this only tags the root span.
      return CodeHangingTextSpan(
        hangingChars: item.contentStart,
        style: style,
        children: children,
      );
    }
    return TextSpan(style: style, children: children);
  }

  /// Appends spans covering [start]..[end], styling every inline
  /// construct [MarkdownInlineGrammar] finds there — emphasis, strike,
  /// highlight, inline code, `[text](url)` links and images, bare URLs,
  /// `#tag` tokens, `{name:text}` colours, ghost runs and backslash
  /// escapes — against [contextStyle]. The grammar is shared with the
  /// preview: this method never scans for a construct of its own, it
  /// only decides how each token is emitted (conceal vs drop is the one
  /// difference between the two surfaces), and it recurses into a
  /// container's inner range for the nested tokens. Gaps between tokens
  /// are plain text.
  ///
  /// Ghost runs come back as tokens and are emitted through the
  /// ghost-aware [_emit] like everything else, so their markers stay
  /// concealed inside whatever style surrounds them. They are not
  /// "styling" on their own — the caller falls back to the ghost-only
  /// builder when nothing else matched.
  ///
  /// Nesting is bounded by [MarkdownInlineGrammar.maxNestingDepth]: past
  /// it the tokenizer returns nothing, so the inner range emits plain
  /// through the gap path on both surfaces alike. Returns whether any
  /// non-ghost token was found.
  bool _appendInline({
    required String text,
    required int start,
    required int end,
    required TextStyle contextStyle,
    required Color baseColor,
    required Color primary,
    required bool reveal,
    required List<GhostMatch> ghosts,
    required List<InlineSpan> out,
    required int depth,
  }) {
    final tokens = MarkdownInlineGrammar.tokenize(
      text,
      start: start,
      end: end,
      ghosts: ghosts,
      palette: _colorPalette,
      depth: depth,
    );
    if (tokens.isEmpty) {
      _emit(
        text: text,
        start: start,
        end: end,
        style: contextStyle,
        baseColor: baseColor,
        ghosts: ghosts,
        out: out,
      );
      return false;
    }

    final markerStyle = reveal
        ? _dimStyle(contextStyle, baseColor)
        : _concealStyle(contextStyle);
    var styled = false;
    var plainFrom = start;
    for (final token in tokens) {
      if (plainFrom < token.start) {
        _emit(
          text: text,
          start: plainFrom,
          end: token.start,
          style: contextStyle,
          baseColor: baseColor,
          ghosts: ghosts,
          out: out,
        );
      }
      plainFrom = token.end;
      switch (token) {
        case InlineGhost():
          // [_emit] already splits ghosts out of any range; a ghost
          // token just marks where one is, and styles nothing.
          _emit(
            text: text,
            start: token.start,
            end: token.end,
            style: contextStyle,
            baseColor: baseColor,
            ghosts: ghosts,
            out: out,
          );
        case InlineEscape():
          // The escaped punctuation renders literally with the `\`
          // concealed off-caret, dimmed on reveal. Never inside a ghost
          // by the grammar, so no ghost split is needed here.
          out.add(TextSpan(text: r'\', style: markerStyle));
          out.add(
            TextSpan(
              text: text.substring(token.charStart, token.end),
              style: contextStyle,
            ),
          );
          styled = true;
        case InlineCode():
          // Code spans are literal all the way down: no recursion, and
          // the chip is painted at the emit site (CodeDecoratedTextSpan)
          // rather than as a per-glyph background.
          _emitChrome(text, token.start, token.innerStart, markerStyle, out);
          _emit(
            text: text,
            start: token.innerStart,
            end: token.innerEnd,
            style: contextStyle,
            baseColor: baseColor,
            ghosts: ghosts,
            out: out,
            decoration: _codeDecoration(contextStyle, baseColor),
          );
          _emitChrome(text, token.innerEnd, token.end, markerStyle, out);
          styled = true;
        case InlineLink():
          // `![image](url)` stays raw in the editor — the preview owns
          // image rendering — so its chrome is emitted plain and the alt
          // text keeps the surrounding style. A real link tints and
          // underlines its text with `[` and `](url)` concealed.
          final isImage = token.isImage;
          _emit(
            text: text,
            start: token.start,
            end: token.textStart,
            style: isImage ? contextStyle : markerStyle,
            baseColor: baseColor,
            ghosts: ghosts,
            out: out,
          );
          _appendInline(
            text: text,
            start: token.textStart,
            end: token.textEnd,
            contextStyle: isImage
                ? contextStyle
                : _linkStyle(contextStyle, primary),
            baseColor: baseColor,
            primary: primary,
            reveal: reveal,
            ghosts: ghosts,
            out: out,
            depth: depth + 1,
          );
          _emit(
            text: text,
            start: token.textEnd,
            end: token.end,
            style: isImage ? contextStyle : markerStyle,
            baseColor: baseColor,
            ghosts: ghosts,
            out: out,
          );
          styled = true;
        case InlineColor():
          // `{name:` and `}` are concealed (transparent + ~0 size) so
          // the line keeps every source code unit.
          _emitChrome(text, token.start, token.innerStart, markerStyle, out);
          _appendInline(
            text: text,
            start: token.innerStart,
            end: token.innerEnd,
            contextStyle: contextStyle.copyWith(
              color: token.spec.text(dark: _isDark),
            ),
            baseColor: baseColor,
            primary: primary,
            reveal: reveal,
            ghosts: ghosts,
            out: out,
            depth: depth + 1,
          );
          _emitChrome(text, token.innerEnd, token.end, markerStyle, out);
          styled = true;
        case InlineTag():
          _emit(
            text: text,
            start: token.start,
            end: token.end,
            style: contextStyle.copyWith(
              color: primary,
              fontWeight: FontWeight.w600,
            ),
            baseColor: baseColor,
            ghosts: ghosts,
            out: out,
            decoration: _tagDecoration(contextStyle, primary),
          );
          styled = true;
        case InlineUrl():
          _emit(
            text: text,
            start: token.start,
            end: token.end,
            style: _linkStyle(contextStyle, primary),
            baseColor: baseColor,
            ghosts: ghosts,
            out: out,
          );
          styled = true;
        case InlineEmphasis():
          _emitChrome(text, token.start, token.innerStart, markerStyle, out);
          // `==name:text==` tints the highlight and conceals the
          // `name:` prefix as chrome alongside the `==` markers; an
          // unresolved name never reaches here (the tokenizer leaves it
          // as content) so nothing is ever silently eaten.
          final TextStyle runStyle;
          if (token.contentStart > token.innerStart) {
            _emitChrome(
              text,
              token.innerStart,
              token.contentStart,
              markerStyle,
              out,
            );
            runStyle = contextStyle.copyWith(
              backgroundColor: token.tintSpec!.highlight(dark: _isDark),
            );
          } else {
            runStyle = _runStyle(contextStyle, token.kind);
          }
          _appendInline(
            text: text,
            start: token.contentStart,
            end: token.innerEnd,
            contextStyle: runStyle,
            baseColor: baseColor,
            primary: primary,
            reveal: reveal,
            ghosts: ghosts,
            out: out,
            depth: depth + 1,
          );
          _emitChrome(text, token.innerEnd, token.end, markerStyle, out);
          styled = true;
      }
    }
    if (plainFrom < end) {
      _emit(
        text: text,
        start: plainFrom,
        end: end,
        style: contextStyle,
        baseColor: baseColor,
        ghosts: ghosts,
        out: out,
      );
    }
    return styled;
  }

  /// Chrome the grammar guarantees ghost-free — delimiter runs, backtick
  /// fences, `{name:` and `}` — emitted as one span: the substring is
  /// the range, so the code-unit inventory holds by construction and
  /// the ghost split + debug inventory walk of [_emit] would be wasted.
  static void _emitChrome(
    String text,
    int start,
    int end,
    TextStyle style,
    List<InlineSpan> out,
  ) {
    if (start < end) {
      out.add(TextSpan(text: text.substring(start, end), style: style));
    }
  }

  /// Emits [start]..[end] in [style], splitting around ghost runs so
  /// their markers render concealed and their inner text dimmed (with an
  /// underline when blank, so the empty slot stays findable) — the same
  /// treatment as the standalone ghost builder, but inheriting the
  /// surrounding markdown style.
  ///
  /// Guards the code-unit invariant in debug builds: the spans appended
  /// to [out] for `[start, end)` must total exactly `end - start` UTF-16
  /// code units (a placeholder run counting as the one unit it
  /// substitutes). The check lives entirely inside `assert`s, so release
  /// builds pay nothing and allocate nothing for it.
  void _emit({
    required String text,
    required int start,
    required int end,
    required TextStyle style,
    required Color baseColor,
    required List<GhostMatch> ghosts,
    required List<InlineSpan> out,
    CodeTextDecoration? decoration,
  }) {
    var mark = 0;
    assert(() {
      mark = out.length;
      return true;
    }());
    _emitRange(
      text: text,
      start: start,
      end: end,
      style: style,
      baseColor: baseColor,
      ghosts: ghosts,
      out: out,
      decoration: decoration,
    );
    assert(
      _unitsAppendedFrom(out, mark) == (end > start ? end - start : 0),
      'code-unit invariant: _emit appended '
      '${_unitsAppendedFrom(out, mark)} units for [$start, $end) of a '
      '${text.length}-unit line',
    );
  }

  /// UTF-16 code units carried by `out[from..]`, counting each
  /// placeholder run as the single source unit it substitutes. Only ever
  /// invoked from an `assert`.
  static int _unitsAppendedFrom(List<InlineSpan> out, int from) {
    var units = 0;
    for (var i = from; i < out.length; i++) {
      units += _unitsOf(out[i]);
    }
    return units;
  }

  static int _unitsOf(InlineSpan span) {
    if (span is PlaceholderSpan) return 1;
    if (span is TextSpan) {
      var units = span.text?.length ?? 0;
      final children = span.children;
      if (children != null) {
        for (final child in children) {
          units += _unitsOf(child);
        }
      }
      return units;
    }
    return 0;
  }

  void _emitRange({
    required String text,
    required int start,
    required int end,
    required TextStyle style,
    required Color baseColor,
    required List<GhostMatch> ghosts,
    required List<InlineSpan> out,
    CodeTextDecoration? decoration,
  }) {
    if (start >= end) return;
    if (ghosts.isEmpty) {
      out.add(_plainSpan(text.substring(start, end), style, decoration));
      return;
    }
    var pos = start;
    for (final g in ghosts) {
      if (g.end <= pos) continue;
      if (g.start >= end) break;
      if (g.start > pos) {
        out.add(_plainSpan(text.substring(pos, g.start), style, decoration));
      }
      final ghostColor = baseColor.withValues(alpha: _dimAlpha);
      var innerStyle = style.copyWith(color: ghostColor);
      if (_ghostBlank(text, g)) {
        innerStyle = innerStyle.copyWith(
          decoration: TextDecoration.underline,
          decorationColor: ghostColor,
        );
      }
      final concealStyle = _concealStyle(style);
      _emitClamped(text, g.start, g.innerStart, pos, end, concealStyle, out);
      _emitClamped(text, g.innerStart, g.innerEnd, pos, end, innerStyle, out);
      _emitClamped(text, g.innerEnd, g.end, pos, end, concealStyle, out);
      pos = g.end < end ? g.end : end;
      if (pos >= end) return;
    }
    if (pos < end) {
      out.add(_plainSpan(text.substring(pos, end), style, decoration));
    }
  }

  /// A plain emitted segment: an ordinary [TextSpan], or a
  /// [CodeDecoratedTextSpan] when the run paints a chip behind itself
  /// (tags, inline code). Ghost segments inside a decorated run keep
  /// plain spans — the ghost treatment wins there.
  static InlineSpan _plainSpan(
    String text,
    TextStyle style,
    CodeTextDecoration? decoration,
  ) => decoration == null
      ? TextSpan(text: text, style: style)
      : CodeDecoratedTextSpan(decoration: decoration, text: text, style: style);

  void _emitClamped(
    String text,
    int from,
    int to,
    int lo,
    int hi,
    TextStyle style,
    List<InlineSpan> out,
  ) {
    final a = from > lo ? from : lo;
    final b = to < hi ? to : hi;
    if (a < b) {
      out.add(TextSpan(text: text.substring(a, b), style: style));
    }
  }

  TextStyle _linkStyle(TextStyle context, Color primary) => context.copyWith(
    color: primary,
    decoration: TextDecoration.underline,
    decorationColor: primary,
  );

  /// The style a matched delimiter pair applies to its content. An
  /// untinted `==highlight==` keeps the legacy amber, which is what the
  /// palette's `yellow` preset resolves to; a tinted one never reaches
  /// here (the caller applies the resolved highlight instead).
  TextStyle _runStyle(
    TextStyle context,
    InlineEmphasisKind kind,
  ) => switch (kind) {
    InlineEmphasisKind.boldItalic => context.copyWith(
      fontWeight: FontWeight.bold,
      fontStyle: FontStyle.italic,
    ),
    InlineEmphasisKind.bold => context.copyWith(fontWeight: FontWeight.bold),
    InlineEmphasisKind.italic => context.copyWith(fontStyle: FontStyle.italic),
    InlineEmphasisKind.strikethrough => context.copyWith(
      decoration: TextDecoration.lineThrough,
      decorationColor: context.color,
    ),
    InlineEmphasisKind.highlight => context.copyWith(
      backgroundColor: _isDark
          ? MarkdownConstants.markBackgroundDark
          : MarkdownConstants.markBackgroundLight,
    ),
  };

  /// Stadium pill behind a `#tag` run. Radius past half the chip height
  /// clamps to a stadium; the vertical inset trims the strut-height box
  /// to ~1.06em so pills read uniform at every editor font size.
  CodeTextDecoration _tagDecoration(TextStyle context, Color primary) {
    final size = context.fontSize ?? 16.0;
    return CodeTextDecoration(
      color: primary.withValues(alpha: _tagBackgroundAlpha),
      radius: size,
      horizontalPadding: size * 0.15,
      verticalInset: size * 0.22,
    );
  }

  /// Rounded chip behind inline `` `code` `` content (markers stay
  /// outside the chip).
  CodeTextDecoration _codeDecoration(TextStyle context, Color baseColor) {
    final size = context.fontSize ?? 16.0;
    return CodeTextDecoration(
      color: baseColor.withValues(alpha: _codeBackgroundAlpha),
      radius: size * 0.25,
      horizontalPadding: size * 0.1,
      verticalInset: size * 0.16,
    );
  }

  double _headerScale(int level) {
    switch (level) {
      case 1:
        return MarkdownConstants.h1Scale;
      case 2:
        return MarkdownConstants.h2Scale;
      case 3:
        return MarkdownConstants.h3Scale;
      case 4:
        return MarkdownConstants.h4Scale;
      default:
        // H5/H6 never drop below the base size — a line shorter than the
        // editor's base line height has no upside in the editor.
        return 1.0;
    }
  }

  TextStyle _dimStyle(TextStyle context, Color baseColor) => context.copyWith(
    color: baseColor.withValues(alpha: _dimAlpha),
    fontWeight: FontWeight.normal,
  );

  TextStyle _concealStyle(TextStyle context) =>
      context.copyWith(color: _transparent, fontSize: _concealedFontSize);

  bool _isSpace(int codeUnit) => codeUnit == 0x20 || codeUnit == 0x09;

  bool _ghostBlank(String text, GhostMatch g) {
    for (var i = g.innerStart; i < g.innerEnd; i++) {
      if (!_isSpace(text.codeUnitAt(i))) return false;
    }
    return true;
  }

  /// Whether the selection covers (reveals) [index]. Public and static
  /// so the wrapper's tap interception uses the exact same reveal
  /// predicate as the rendering — the two must never disagree.
  static bool selectionCoversLine(CodeLineSelection selection, int index) {
    final a = selection.baseIndex;
    final b = selection.extentIndex;
    return a < b ? (index >= a && index <= b) : (index >= b && index <= a);
  }

  /// Whether [index] is inside (or delimiting) a ``` code fence. Public
  /// so the wrapper's tap interception can refuse to treat fence text as
  /// a link or checkbox; rendering resolves roles via [_fenceRoleAt].
  bool lineInFence(int index) {
    final controller = _controller;
    if (controller == null) return false;
    return _fenceRoleAt(controller, index) != MarkdownFenceRole.none;
  }

  /// Fence-awareness: grammar and positional state come from the shared
  /// incremental index ([MarkdownChunker.isFenceDelimiter] +
  /// [MarkdownEditorLineIndex]). Delimiter and interior lines carry
  /// distinct roles so they can style differently; both are positional,
  /// so neither touches the memo.
  MarkdownFenceRole _fenceRoleAt(
    CodeLineEditingController controller,
    int index,
  ) => _lineIndex.fenceRoleAt(controller.codeLines, index);

  /// Whether the task line at [index] renders its unchecked box as
  /// indeterminate: its subtree holds at least one checked and at least
  /// one unchecked task. Aggregation lives in the shared index.
  bool _isTaskIndeterminate(CodeLineEditingController controller, int index) =>
      _lineIndex.taskIndeterminate(controller.codeLines, index);

  /// Code-fence lines mirror the preview's treatment at base size: ```
  /// delimiter lines render monospace and dimmed, interior lines plain
  /// monospace. No per-line background: an empty interior line can't
  /// paint one (no glyphs, and inserting characters is forbidden), so a
  /// background would render striped around blank lines. Nothing is
  /// concealed, so the styling holds on reveal lines too (same rule as
  /// tags), and ghosts compose on delimiter and interior lines alike.
  TextSpan _buildFenceLine({
    required String text,
    required MarkdownFenceRole role,
    required TextStyle style,
    required Color baseColor,
  }) {
    final ghosts = GhostText.mightContain(text)
        ? GhostText.findGhosts(text)
        : const <GhostMatch>[];
    final lineStyle = role == MarkdownFenceRole.delimiter
        ? style.copyWith(
            fontFamily: 'monospace',
            color: baseColor.withValues(alpha: _fenceDelimiterAlpha),
          )
        : style.copyWith(fontFamily: 'monospace');
    final children = <InlineSpan>[];
    _emit(
      text: text,
      start: 0,
      end: text.length,
      style: lineStyle,
      baseColor: baseColor,
      ghosts: ghosts,
      out: children,
    );
    return TextSpan(style: style, children: children);
  }
}

/// The live editor's `$$` money total: a rounded chip with the running
/// balance custom-painted into a placeholder run (fork's
/// [CodeInlinePaintSpan]), substituting 1:1 for the second `$` code
/// unit (the first stays concealed beside it). The [TextPainter] is
/// laid out once at construction and reused every frame; equality is
/// value-based (label + colours + geometry) so re_editor's paragraph
/// cache stays on its fast path when the balance is unchanged.
class _EditorMoneyTotalSpan extends CodeInlinePaintSpan {
  final TextPainter painter;
  final String label;
  final Color accent;
  final Color chip;
  final double radius;

  const _EditorMoneyTotalSpan({
    required super.width,
    required super.height,
    required this.painter,
    required this.label,
    required this.accent,
    required this.chip,
    required this.radius,
  });

  static final Paint _chipPaint = Paint()..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Rect rect) {
    // Unfilled (op-row slot) values paint the number alone — the dimmed
    // annotation look the preview gives their trailing `= balance`.
    if (chip.a > 0) {
      _chipPaint.color = chip;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        _chipPaint,
      );
    }
    painter.paint(
      canvas,
      Offset(
        rect.left + (rect.width - painter.width) / 2,
        rect.top + (rect.height - painter.height) / 2,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _EditorMoneyTotalSpan &&
          other.label == label &&
          other.accent == accent &&
          other.chip == chip &&
          other.radius == radius &&
          other.width == width &&
          other.height == height &&
          other.style == style;

  @override
  int get hashCode =>
      Object.hash(label, accent, chip, radius, width, height, style);
}

/// Which glyph the editor checkbox paints. `indeterminate` is a purely
/// visual facet of an unchecked box whose child tasks are partially
/// complete — the source text stays `[ ]`, and a tap still checks it.
enum _CheckboxVisual { unchecked, checked, indeterminate }

/// The live editor's task checkbox: a rounded box custom-painted into a
/// placeholder run (fork's [CodeInlinePaintSpan]), replacing the old
/// icon-font glyph. The paragraph layout centers the reserved box on
/// the line box (PlaceholderAlignment.middle) and its side scales with
/// the line's own font size, so the mark stays proportional and
/// vertically centered at every editor text-size setting, independent
/// of any font's metrics. Substitutes 1:1 for the `[` code unit; the
/// `x]` stays concealed beside it.
class _EditorCheckboxSpan extends CodeInlinePaintSpan {
  final _CheckboxVisual visual;
  final Color accent;
  final Color border;
  final Color mark;

  const _EditorCheckboxSpan({
    required double side,
    required this.visual,
    required this.accent,
    required this.border,
    required this.mark,
  }) : super(width: side, height: side);

  // Glyph geometry as fractions of the box side.
  static const double _strokeFrac = 0.09;
  static const double _minStroke = 1.4;
  static const double _radiusFrac = 0.21;
  static const double _insetFrac = 0.05;

  // Paint objects are shared across all checkboxes (single-threaded UI
  // painting) so per-frame drawing allocates nothing but the check path.
  static final Paint _fillPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _strokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round;
  static final Paint _markPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Rect rect) {
    final side = rect.height;
    var stroke = side * _strokeFrac;
    if (stroke < _minStroke) stroke = _minStroke;
    final box = rect.deflate(side * _insetFrac + stroke / 2);
    final rrect = RRect.fromRectAndRadius(
      box,
      Radius.circular(side * _radiusFrac),
    );
    switch (visual) {
      case _CheckboxVisual.unchecked:
        _strokePaint
          ..color = border
          ..strokeWidth = stroke;
        canvas.drawRRect(rrect, _strokePaint);
      case _CheckboxVisual.checked:
        _fillPaint.color = accent;
        canvas.drawRRect(rrect, _fillPaint);
        _markPaint
          ..color = mark
          ..strokeWidth = stroke * 1.15;
        final check = Path()
          ..moveTo(box.left + box.width * 0.24, box.top + box.height * 0.53)
          ..lineTo(box.left + box.width * 0.43, box.top + box.height * 0.72)
          ..lineTo(box.left + box.width * 0.78, box.top + box.height * 0.30);
        canvas.drawPath(check, _markPaint);
      case _CheckboxVisual.indeterminate:
        _strokePaint
          ..color = accent
          ..strokeWidth = stroke;
        canvas.drawRRect(rrect, _strokePaint);
        _markPaint
          ..color = accent
          ..strokeWidth = stroke * 1.3;
        canvas.drawLine(
          Offset(box.left + box.width * 0.28, box.center.dy),
          Offset(box.right - box.width * 0.28, box.center.dy),
          _markPaint,
        );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _EditorCheckboxSpan &&
          other.visual == visual &&
          other.accent == accent &&
          other.border == border &&
          other.mark == mark &&
          other.width == width &&
          other.height == height &&
          other.style == style;

  @override
  int get hashCode =>
      Object.hash(visual, accent, border, mark, width, height, style);
}
