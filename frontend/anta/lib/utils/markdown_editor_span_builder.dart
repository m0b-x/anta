import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import '../constants/markdown_constants.dart';
import 'editor_render_context.dart';
import 'ghost_text.dart';
import 'markdown_callout_syntax.dart';
import 'markdown_color_syntax.dart';
import 'markdown_editor_emitter.dart';
import 'markdown_editor_inline_emitter.dart';
import 'markdown_editor_line_index.dart';
import 'markdown_editor_money_row.dart';
import 'markdown_editor_paint_spans.dart';
import 'markdown_editor_span_cache.dart';
import 'markdown_inline_grammar.dart';
import 'markdown_line_shape.dart';
import 'markdown_list_syntax.dart';
import 'markdown_money_syntax.dart';
import 'money_display_config.dart';

/// Live markdown rendering for the re_editor text mode (the "live
/// markdown rendering" editor setting, on by default).
///
/// This library owns the renderer's entry point and its line shapes —
/// [build]'s routing, the header / quote / rule / table / list-item /
/// fence branches, and the three positional predicates (fence role,
/// callout role, indeterminate task) it reads off
/// [MarkdownEditorLineIndex]. The rest
/// of the renderer lives beside it, one responsibility per library:
/// `editor_render_context.dart` carries the theme-derived values
/// ([EditorRenderContext]) so nothing here touches a `BuildContext`;
/// `markdown_editor_span_cache.dart` owns the two span memos, the money
/// parse memo and the generation key; `markdown_editor_emitter.dart`
/// turns a source range into leaves (ghost split, conceal/dim styles,
/// the debug code-unit inventory assert);
/// `markdown_editor_inline_emitter.dart` emits
/// [MarkdownInlineGrammar] tokens and owns the inline styles;
/// `markdown_editor_money_row.dart` builds the money-ledger row; and
/// `markdown_editor_paint_spans.dart` holds the custom-painted
/// placeholder runs (money chip, task checkbox, callout icon). Callers
/// import this file alone.
///
/// Restyles one line at a time: headers at the preview's scale factors
/// (the re_editor fork gives a line whose root span sets a non-base
/// fontSize its own line height), bullets as the depth's
/// [MarkdownListSyntax.bulletGlyph] (`•` / `◦` / `▪`, cycling every
/// three levels), task boxes as
/// custom-painted placeholder marks (checked / unchecked / indeterminate
/// when a parent's subtree is partially complete),
/// every blockquote `>` as a `┃` bar — one per nesting level, so `>> a`
/// reads `┃┃ a` — with italic dimmed content,
/// `| a | b |` table rows monospace with tinted pipes (delimiter rows
/// dimmed whole),
/// `---` rules as dimmed `─` runs, `#tag` tokens tinted (render-only),
/// and `**bold**` / `*italic*` / `__bold__` / `_italic_` / `~~strike~~` /
/// `==highlight==` / `` `code` `` runs styled inline (code content at
/// [MarkdownConstants.inlineCodeScale], the preview's factor — the
/// fork's strut comes from the root span, so the line keeps its height).
/// `[text](url)`
/// links show their text tinted and underlined with the brackets + URL
/// concealed (render-only — tapping places the caret and the line
/// reveals raw for editing); bare `http(s)://` / `www.` URLs tint in
/// place with nothing concealed. Backslash escapes render the escaped
/// punctuation literally with the `\` concealed. Every one of those
/// inline constructs is found by [MarkdownInlineGrammar] — the one
/// tokenizer the preview reads too — so this surface only decides how
/// to *emit* a token, never what a token is; the line's shape (heading,
/// horizontal rule) comes from [MarkdownLineShape] for the same reason.
/// Callout blocks (a `> [!TIP] title` lead plus every contiguous quote
/// line under it) tint their bars with the type's accent: the lead
/// paints the type's icon in place of the `[` with `!TYPE]` concealed
/// and its title in accent + bold, and every body line renders plain in
/// the block's colour. Code-fence delimiter lines render monospace and
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
/// memoized per line text in an LRU (cleared when the
/// [EditorRenderContext] generation changes), so steady-state scrolling
/// and typing rebuild only the edited line and the caret's reveal
/// lines; returning the identical span instance also keeps re_editor's
/// paragraph cache on its fast path. Positional state (fence roles,
/// callout roles, indeterminate task parents) lives in
/// [MarkdownEditorLineIndex],
/// recomputed lazily per CodeLines instance and resumed at the first
/// changed segment, so a keystroke rescans ~one segment instead of the
/// whole document.
class MarkdownEditorSpanBuilder {
  static const double _quoteContentAlpha = 0.8;
  static const double _ruleAlpha = 0.3;

  /// Alpha of a table row's `|` separators, tinted with the primary
  /// colour so the columns read as structure without competing with the
  /// cell text.
  static const double _tablePipeAlpha = 0.55;
  static const double _fenceDelimiterAlpha = 0.6;
  static const double _h56PrimaryBlend = 0.35;
  static const double _h6Alpha = 0.7;

  /// Lines longer than this render raw — matches the spirit of
  /// re_editor's maxLengthSingleLineRendering guard. Public so the
  /// wrapper's tap interception can refuse zones on lines that render
  /// raw for length.
  static const int maxStyledLineLength = 4096;

  CodeLineEditingController? _controller;

  /// Positional state (fence roles, callout roles, indeterminate task
  /// parents, money balances) lives
  /// in the shared incremental index: one fused rebuild per [CodeLines]
  /// change, resumed at the first changed segment instead of rescanning
  /// the whole document per keystroke.
  final MarkdownEditorLineIndex _lineIndex = MarkdownEditorLineIndex(
    maxScannedLineLength: maxStyledLineLength,
  );

  final EditorSpanCache _cache = EditorSpanCache();

  MoneyDisplayConfig _moneyConfig = MoneyDisplayConfig.disabled;

  MarkdownColorPalette _colorPalette = MarkdownColorPalette.presets;

  /// Money parses this builder actually made (memo misses only). Debug
  /// builds only. Test-only; nothing in the app reads it.
  @visibleForTesting
  int get debugMoneyParseCount => _cache.debugMoneyParseCount;

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
      _cache.clearSpanMemos();
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
    _cache.clearSpanMemos();
  }

  /// Returns the restyled span for [codeLine], or `null` when this line
  /// is not handled (caller falls back to the ghost-text builder).
  ///
  /// [context] is the theme generation every span is built under; the
  /// caller resolves it once per generation and hands the same instance
  /// to every line, and adopting a different one drops both span memos.
  ///
  /// Guards the code-unit invariant for *every* line shape in debug
  /// builds — [EditorSpanEmitter.emit] checks the ranges it emits, but
  /// the money row, the list-marker runs, the quote bars, the table
  /// pipes, the chrome runs and the painted placeholder spans (money
  /// chip, task box, callout icon) never go through it. The check lives
  /// entirely inside an `assert`, so release builds pay nothing.
  TextSpan? build({
    required EditorRenderContext context,
    required int index,
    required CodeLine codeLine,
  }) {
    final span = _route(context: context, index: index, codeLine: codeLine);
    assert(
      span == null ||
          span.toPlainText(includePlaceholders: true).length ==
              codeLine.text.length,
      'code-unit invariant: build returned '
      '${span.toPlainText(includePlaceholders: true).length} units for a '
      '${codeLine.text.length}-unit line: ${codeLine.text}',
    );
    return span;
  }

  /// [build]'s routing, split out so the debug inventory assert can wrap
  /// every path at one place: positional shapes first — fence roles,
  /// callout membership, money display rows, indeterminate task parents,
  /// in that order — then the text-keyed memo, then [_buildLine] for the
  /// line shapes themselves. The order is the precedence: a fence wins
  /// over everything (a `> [!TIP]` inside a fence is code), and a
  /// callout line is never a money or task row.
  TextSpan? _route({
    required EditorRenderContext context,
    required int index,
    required CodeLine codeLine,
  }) {
    final controller = _controller;
    if (controller == null) return null;
    final text = codeLine.text;
    if (text.isEmpty || text.length > maxStyledLineLength) return null;

    _cache.adoptContext(context);

    // Fence status is positional, not textual — fence lines are styled
    // straight from their role and never touch the text-keyed cache.
    final fenceRole = _fenceRoleAt(controller, index);
    if (fenceRole != MarkdownFenceRole.none) {
      final fenceKey = (
        fenceRole == MarkdownFenceRole.delimiter
            ? EditorSpanCache.positionalFenceDelimiter
            : EditorSpanCache.positionalFenceInterior,
        0,
        text,
      );
      final cached = _cache.positional(fenceKey);
      if (cached != null) return cached;
      final span = _buildFenceLine(text: text, role: fenceRole, ctx: context);
      _cache.putPositional(fenceKey, span);
      return span;
    }

    final reveal = selectionCoversLine(controller.selection, index);

    final callout = _lineIndex.calloutAt(controller.codeLines, index);
    if (callout != 0) {
      if (reveal) {
        return _buildLine(
          text: text,
          ctx: context,
          reveal: true,
          callout: callout,
        );
      }
      final calloutKey = (EditorSpanCache.positionalCallout, callout, text);
      final cached = _cache.positional(calloutKey);
      if (cached != null) return cached;
      final span = _buildLine(
        text: text,
        ctx: context,
        reveal: false,
        callout: callout,
      );
      if (span != null) {
        _cache.putPositional(calloutKey, span);
      }
      return span;
    }

    // `$$` money totals, `$?` net-change, `$^` entry-diff, and `$~`
    // checkpoint-span lines display a value computed from every op line
    // above — positional state from the shared index — so they style
    // through the positional memo with the value folded into the key,
    // mirroring fences. A `$` value slot in the label makes any row
    // display a computed value, so those join the positional path too;
    // the rest of the op lines (`$+ …`) are purely textual and stay on
    // the text-keyed path below.
    //
    // Reveal lines show raw `$$` / `$?` / `$^` / `$~` and paint no chip,
    // but the row's accent (and with it the label's colour) still reads
    // off the balance — a negative total is red on both sides of a caret
    // move, and a `$!` with no target above it stays warning-tinted — so
    // the balance is resolved for the reveal path too. Only the memo is
    // skipped there: a reveal build is never cached.
    if (_moneyConfig.enabled && MarkdownMoneySyntax.leadsWithMoney(text)) {
      final money = _cache.parseMoney(text);
      if (money != null && MarkdownMoneySyntax.needsBalance(money)) {
        final balance =
            _lineIndex.moneyValueAt(controller.codeLines, index) ?? 0;
        if (reveal) {
          return _buildLine(
            text: text,
            ctx: context,
            reveal: true,
            money: money,
            moneyBalance: balance,
          );
        }
        final moneyKey = (EditorSpanCache.positionalMoney, balance, text);
        final cached = _cache.positional(moneyKey);
        if (cached != null) return cached;
        final span = _buildLine(
          text: text,
          ctx: context,
          reveal: false,
          money: money,
          moneyBalance: balance,
        );
        if (span != null) {
          _cache.putPositional(moneyKey, span);
        }
        return span;
      }
    }

    // Task-parent aggregate state is positional too (it depends on the
    // child lines), so indeterminate parents style through the
    // positional memo, mirroring fences. Reveal lines show raw markers
    // and skip the facet entirely.
    if (!reveal && _isTaskIndeterminate(controller, index)) {
      final taskKey = (EditorSpanCache.positionalTaskIndeterminate, 0, text);
      final cached = _cache.positional(taskKey);
      if (cached != null) return cached;
      final span = _buildLine(
        text: text,
        ctx: context,
        reveal: false,
        taskIndeterminate: true,
      );
      if (span != null) {
        _cache.putPositional(taskKey, span);
      }
      return span;
    }

    if (!reveal) {
      final cached = _cache.styled(text);
      if (cached != null) {
        return identical(cached, EditorSpanCache.unhandled) ? null : cached;
      }
    }
    final span = _buildLine(text: text, ctx: context, reveal: reveal);
    if (!reveal) {
      _cache.putStyled(text, span);
    }
    return span;
  }

  TextSpan? _buildLine({
    required String text,
    required EditorRenderContext ctx,
    required bool reveal,
    bool taskIndeterminate = false,
    MoneyLineMatch? money,
    int moneyBalance = 0,
    int callout = 0,
  }) {
    final ghosts = GhostText.mightContain(text)
        ? GhostText.findGhosts(text)
        : const <GhostMatch>[];

    // Money lines (`$+ 12.50 label`, `$$` total, optionally
    // header-prefixed) — grammar shared with the preview via
    // [MarkdownMoneySyntax]. Rows that display a computed value arrive
    // pre-parsed from the positional path with their balance in both
    // reveal states; op lines parse here (purely textual). A `#`-led
    // line that fails the money parse falls through to the header
    // branch.
    if (_moneyConfig.enabled && MarkdownMoneySyntax.leadsWithMoney(text)) {
      final m = money ?? _cache.parseMoney(text);
      if (m != null) {
        return EditorMoneyRowBuilder.build(
          text: text,
          m: m,
          context: ctx,
          config: _moneyConfig,
          palette: _colorPalette,
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
        ctx: ctx,
        reveal: reveal,
        ghosts: ghosts,
      );
    }

    // [MarkdownListSyntax.scanListShape] is the allocation-free
    // companion of [MarkdownListSyntax.parse] and is documented to stay
    // in lockstep with its three regexes, so this gate never hides a
    // list line — it only spares every other line (the caret line
    // included, which is rebuilt on each keystroke and never memoized)
    // the regexes plus the content substring [_buildListItem] never
    // reads. `test/utils/markdown_list_syntax_test.dart` pins the
    // lockstep over a corpus.
    if (MarkdownListSyntax.scanListShape(text) >= 0) {
      final item = MarkdownListSyntax.parse(text);
      if (item != null) {
        return _buildListItem(
          text: text,
          item: item,
          ctx: ctx,
          reveal: reveal,
          ghosts: ghosts,
          indeterminate: taskIndeterminate,
        );
      }
    }

    if (MarkdownCalloutSyntax.isBlockquoteLine(text)) {
      return _buildQuote(
        text: text,
        ctx: ctx,
        reveal: reveal,
        ghosts: ghosts,
        callout: callout,
      );
    }

    if (MarkdownLineShape.isHorizontalRule(text)) {
      return _buildRule(text: text, ctx: ctx, reveal: reveal);
    }

    if (_leadsWithPipe(text) && MarkdownLineShape.isTableRow(text)) {
      return _buildTableRow(
        text: text,
        ctx: ctx,
        reveal: reveal,
        ghosts: ghosts,
      );
    }

    final hasCandidates = MarkdownInlineGrammar.hasCandidates(text);
    if (!hasCandidates && ghosts.isEmpty) return null;
    final children = <InlineSpan>[];
    var styled = false;
    if (hasCandidates) {
      styled = EditorInlineEmitter.append(
        text: text,
        start: 0,
        end: text.length,
        contextStyle: ctx.style,
        context: ctx,
        palette: _colorPalette,
        reveal: reveal,
        ghosts: ghosts,
        out: children,
        depth: 0,
      );
    } else {
      EditorSpanEmitter.emit(
        text: text,
        start: 0,
        end: text.length,
        style: ctx.style,
        baseColor: ctx.baseColor,
        ghosts: ghosts,
        out: children,
      );
    }
    if (!styled && ghosts.isEmpty) return null;
    return TextSpan(style: ctx.style, children: children);
  }

  /// ATX heading, shaped by [MarkdownLineShape.headingAt]: the hashes
  /// and their separating space (`[hashStart, contentStart)` — empty
  /// content for a bare `###`) conceal as one chrome run, and the rest
  /// of the line renders inline at the level's scale.
  TextSpan _buildHeader({
    required String text,
    required MarkdownHeadingMatch heading,
    required EditorRenderContext ctx,
    required bool reveal,
    required List<GhostMatch> ghosts,
  }) {
    final level = heading.level;
    final start = heading.hashStart;
    final style = ctx.style;
    final baseSize = style.fontSize ?? 16.0;
    var headerStyle = style.copyWith(
      fontSize: baseSize * MarkdownConstants.editorHeaderScale(level),
      fontWeight: FontWeight.bold,
    );
    // H5/H6 keep the base size (sub-base line heights buy nothing in the
    // editor), so they distinguish themselves by colour instead: blended
    // toward primary, H6 additionally muted below H5.
    if (level >= 5) {
      final blended = Color.lerp(ctx.baseColor, ctx.primary, _h56PrimaryBlend)!;
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
            ? EditorSpanEmitter.dimStyle(headerStyle, ctx.baseColor)
            : EditorSpanEmitter.concealStyle(headerStyle),
      ),
    ];
    EditorInlineEmitter.append(
      text: text,
      start: markerEnd,
      end: text.length,
      contextStyle: headerStyle,
      context: ctx,
      palette: _colorPalette,
      reveal: reveal,
      ghosts: ghosts,
      out: children,
      depth: 0,
    );
    return TextSpan(style: headerStyle, children: children);
  }

  /// Blockquote and callout lines, shaped by
  /// [MarkdownCalloutSyntax.quoteMarkers]: every `>` is substituted 1:1
  /// with a `┃` bar (both a single code unit), so `>> a` reads `┃┃ a`
  /// and a depth-3 quote shows three bars. The single spaces between
  /// markers and the indent before them stay as source.
  ///
  /// [callout] is the packed role + type from
  /// [MarkdownEditorLineIndex.calloutAt] (`0` for a plain quote), which
  /// is what makes the three treatments positional rather than textual:
  ///
  ///   * **plain quote** — grey bars, content italic and dimmed;
  ///   * **callout lead** (`> [!TIP] title`) — bars in the type's accent
  ///     (palette shared with the preview via
  ///     [MarkdownConstants.calloutAccent]); off-caret the `[` becomes an
  ///     [EditorCalloutIconSpan] painting the type's icon and `!TYPE]`
  ///     conceals beside it, on reveal the whole `[!TYPE]` token shows
  ///     tinted so it stays readable while editing; the title renders
  ///     accent + bold, matching the preview's header;
  ///   * **callout body** — bars in the *block's* accent and content in
  ///     the ambient style (not italic, not dimmed — preview parity). A
  ///     textually lead-shaped body line (`> [!NOTE]` under an open
  ///     block) keeps its token tinted with its own type's accent but
  ///     paints no icon: it is body text, not a second header.
  ///
  /// On reveal the raw `>` shows dimmed; line height never changes. The
  /// icon is sized off the line's own font size and clamped under the
  /// line box exactly like the task checkbox. A line with exotic
  /// (non-ASCII) leading whitespace is a blockquote line to
  /// [MarkdownCalloutSyntax.isBlockquoteLine] but has no shape for
  /// [MarkdownCalloutSyntax.quoteMarkers]; it renders as quoted content
  /// with no bar rather than losing a code unit.
  TextSpan _buildQuote({
    required String text,
    required EditorRenderContext ctx,
    required bool reveal,
    required List<GhostMatch> ghosts,
    int callout = 0,
  }) {
    final style = ctx.style;
    final role = MarkdownEditorLineIndex.calloutRoleOf(callout);
    final blockType = MarkdownEditorLineIndex.calloutTypeOf(callout);
    final blockAccent = blockType == null
        ? null
        : MarkdownConstants.calloutAccent(blockType, dark: ctx.isDark);
    final children = <InlineSpan>[];
    final shape = MarkdownCalloutSyntax.quoteMarkers(text);
    final contentStyle = blockAccent == null
        ? style.copyWith(
            fontStyle: FontStyle.italic,
            color: ctx.baseColor.withValues(alpha: _quoteContentAlpha),
          )
        : style;
    if (shape == null) {
      EditorInlineEmitter.append(
        text: text,
        start: 0,
        end: text.length,
        contextStyle: contentStyle,
        context: ctx,
        palette: _colorPalette,
        reveal: reveal,
        ghosts: ghosts,
        out: children,
        depth: 0,
      );
      return TextSpan(style: style, children: children);
    }

    _emitQuoteBars(
      text: text,
      shape: shape,
      style: style,
      barStyle: reveal
          ? EditorSpanEmitter.dimStyle(style, ctx.baseColor)
          : style.copyWith(
              color:
                  blockAccent ??
                  (ctx.isDark ? Colors.grey.shade700 : Colors.grey.shade300),
              fontWeight: blockAccent == null ? null : FontWeight.bold,
            ),
      reveal: reveal,
      out: children,
    );

    var contentStart = shape.contentStart;
    var probe = contentStart;
    while (probe < text.length && text.codeUnitAt(probe) == 0x20) {
      probe++;
    }
    final lead =
        role != MarkdownCalloutRole.none &&
            probe < text.length &&
            text.codeUnitAt(probe) == 0x5B
        ? MarkdownCalloutSyntax.parseLead(text)
        : null;
    if (lead != null) {
      final tokenAccent = MarkdownConstants.calloutAccent(
        lead.type,
        dark: ctx.isDark,
      );
      if (lead.tokenStart > contentStart) {
        children.add(
          TextSpan(
            text: text.substring(contentStart, lead.tokenStart),
            style: style,
          ),
        );
      }
      if (role == MarkdownCalloutRole.lead && !reveal) {
        final baseSize = style.fontSize ?? 16.0;
        final lineBox =
            baseSize * (style.height ?? MarkdownConstants.lineHeight);
        var side = baseSize;
        if (side > lineBox * 0.85) side = lineBox * 0.85;
        children.add(
          EditorCalloutIconSpan(
            side: side,
            icon: MarkdownConstants.calloutIcon(lead.type),
            accent: tokenAccent,
          ),
        );
        children.add(
          TextSpan(
            text: text.substring(lead.tokenStart + 1, lead.tokenEnd),
            style: EditorSpanEmitter.concealStyle(style),
          ),
        );
      } else {
        children.add(
          TextSpan(
            text: text.substring(lead.tokenStart, lead.tokenEnd),
            style: style.copyWith(
              color: tokenAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }
      if (lead.titleStart > lead.tokenEnd) {
        children.add(
          TextSpan(
            text: text.substring(lead.tokenEnd, lead.titleStart),
            style: style,
          ),
        );
      }
      contentStart = lead.titleStart;
    }
    if (contentStart < text.length) {
      EditorInlineEmitter.append(
        text: text,
        start: contentStart,
        end: text.length,
        contextStyle: role == MarkdownCalloutRole.lead && blockAccent != null
            ? style.copyWith(color: blockAccent, fontWeight: FontWeight.bold)
            : contentStyle,
        context: ctx,
        palette: _colorPalette,
        reveal: reveal,
        ghosts: ghosts,
        out: children,
        depth: 0,
      );
    }
    return TextSpan(style: style, children: children);
  }

  /// A quote line's indent and `>` markers: the indent stays as source,
  /// every `>` substitutes 1:1 with `┃` (raw and dimmed on reveal), and
  /// the single space each marker may carry stays visible between the
  /// bars. Emits exactly `[0, shape.contentStart)`.
  static void _emitQuoteBars({
    required String text,
    required MarkdownQuoteShape shape,
    required TextStyle style,
    required TextStyle barStyle,
    required bool reveal,
    required List<InlineSpan> out,
  }) {
    final offsets = shape.markerOffsets;
    if (offsets[0] > 0) {
      out.add(TextSpan(text: text.substring(0, offsets[0]), style: style));
    }
    for (var i = 0; i < shape.depth; i++) {
      out.add(TextSpan(text: reveal ? '>' : '┃', style: barStyle));
      final gapStart = offsets[i] + 1;
      final gapEnd = i + 1 < shape.depth ? offsets[i + 1] : shape.contentStart;
      if (gapEnd > gapStart) {
        out.add(TextSpan(text: text.substring(gapStart, gapEnd), style: style));
      }
    }
  }

  /// Horizontal rule: every `-` / `*` / `_` is substituted 1:1 with `─`
  /// (one code unit each) and dimmed, so contiguous glyphs read as a
  /// line. Base font size is kept — like H5/H6, a sub-base line height
  /// buys nothing in the editor. On reveal the raw markers show dimmed.
  TextSpan _buildRule({
    required String text,
    required EditorRenderContext ctx,
    required bool reveal,
  }) {
    final style = ctx.style;
    if (reveal) {
      return TextSpan(
        style: style,
        children: [
          TextSpan(
            text: text,
            style: EditorSpanEmitter.dimStyle(style, ctx.baseColor),
          ),
        ],
      );
    }
    final units = List<int>.generate(text.length, (i) {
      final c = text.codeUnitAt(i);
      return EditorSpanEmitter.isSpace(c) ? c : 0x2500;
    });
    return TextSpan(
      style: style,
      children: [
        TextSpan(
          text: String.fromCharCodes(units),
          style: style.copyWith(
            color: ctx.baseColor.withValues(alpha: _ruleAlpha),
          ),
        ),
      ],
    );
  }

  /// Whether the first non-blank code unit of [text] is a `|` — the
  /// allocation-free gate in front of [MarkdownLineShape.isTableRow]'s
  /// regex, mirroring the list branch's `scanListShape` gate.
  static bool _leadsWithPipe(String text) {
    final n = text.length;
    var i = 0;
    while (i < n && EditorSpanEmitter.isSpace(text.codeUnitAt(i))) {
      i++;
    }
    return i < n && text.codeUnitAt(i) == 0x7C;
  }

  /// Tables-lite: a `| a | b |` row renders monospace with its pipes
  /// tinted, so columns line up and the structure reads at a glance
  /// without the editor ever laying out a real table (which would need
  /// the neighbouring lines, and change the line's height).
  ///
  /// Nothing is concealed or substituted — the row is the same code
  /// units in both reveal states — so the rendering stays purely
  /// textual and memoizes by line text. Cells still carry inline runs
  /// (`**bold**`, tags, ghosts) through the shared emitter. A delimiter
  /// row (`| --- | :-: |`) is structure rather than content and renders
  /// dimmed as a whole, like a horizontal rule.
  TextSpan _buildTableRow({
    required String text,
    required EditorRenderContext ctx,
    required bool reveal,
    required List<GhostMatch> ghosts,
  }) {
    final style = ctx.style;
    final mono = style.copyWith(fontFamily: 'monospace');
    final children = <InlineSpan>[];
    if (MarkdownLineShape.isTableSeparator(text)) {
      EditorSpanEmitter.emit(
        text: text,
        start: 0,
        end: text.length,
        style: mono.copyWith(
          color: ctx.baseColor.withValues(alpha: _ruleAlpha),
        ),
        baseColor: ctx.baseColor,
        ghosts: ghosts,
        out: children,
      );
      return TextSpan(style: style, children: children);
    }
    final pipeStyle = mono.copyWith(
      color: ctx.primary.withValues(alpha: _tablePipeAlpha),
    );
    var from = 0;
    var seenPipe = false;
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) != 0x7C) continue;
      if (i > from) {
        if (seenPipe) {
          _emitTableCell(
            text: text,
            start: from,
            end: i,
            mono: mono,
            ctx: ctx,
            reveal: reveal,
            ghosts: ghosts,
            out: children,
          );
        } else {
          children.add(TextSpan(text: text.substring(from, i), style: style));
        }
      }
      children.add(TextSpan(text: '|', style: pipeStyle));
      seenPipe = true;
      from = i + 1;
    }
    if (from < text.length) {
      _emitTableCell(
        text: text,
        start: from,
        end: text.length,
        mono: mono,
        ctx: ctx,
        reveal: reveal,
        ghosts: ghosts,
        out: children,
      );
    }
    return TextSpan(style: style, children: children);
  }

  /// One table cell, `[start, end)`: inline runs through the shared
  /// emitter in the monospace cell style. A cell holding nothing but
  /// spacing skips the tokenizer — the commonest cell content in a
  /// hand-aligned table.
  void _emitTableCell({
    required String text,
    required int start,
    required int end,
    required TextStyle mono,
    required EditorRenderContext ctx,
    required bool reveal,
    required List<GhostMatch> ghosts,
    required List<InlineSpan> out,
  }) {
    var blank = true;
    for (var i = start; i < end; i++) {
      if (!EditorSpanEmitter.isSpace(text.codeUnitAt(i))) {
        blank = false;
        break;
      }
    }
    if (blank) {
      EditorSpanEmitter.emit(
        text: text,
        start: start,
        end: end,
        style: mono,
        baseColor: ctx.baseColor,
        ghosts: ghosts,
        out: out,
      );
      return;
    }
    EditorInlineEmitter.append(
      text: text,
      start: start,
      end: end,
      contextStyle: mono,
      context: ctx,
      palette: _colorPalette,
      reveal: reveal,
      ghosts: ghosts,
      out: out,
      depth: 0,
    );
  }

  TextSpan _buildListItem({
    required String text,
    required MarkdownListItem item,
    required EditorRenderContext ctx,
    required bool reveal,
    required List<GhostMatch> ghosts,
    bool indeterminate = false,
  }) {
    final style = ctx.style;
    final baseColor = ctx.baseColor;
    final primary = ctx.primary;
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
            text: reveal
                ? item.marker
                : MarkdownListSyntax.bulletGlyph(item.level),
            style: reveal
                ? EditorSpanEmitter.dimStyle(style, baseColor)
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
              style: EditorSpanEmitter.dimStyle(style, baseColor),
            ),
          );
        } else {
          children.add(
            TextSpan(
              text: text.substring(item.indent.length, item.bracketStart),
              style: EditorSpanEmitter.concealStyle(style),
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
            EditorCheckboxSpan(
              side: side,
              visual: item.checked
                  ? EditorCheckboxVisual.checked
                  : indeterminate
                  ? EditorCheckboxVisual.indeterminate
                  : EditorCheckboxVisual.unchecked,
              accent: primary,
              border: baseColor.withValues(
                alpha: MarkdownConstants.uncheckedCheckboxOpacity,
              ),
              mark: ctx.onAccent,
            ),
          );
          children.add(
            TextSpan(
              text: text.substring(item.bracketStart + 1, boxEnd),
              style: EditorSpanEmitter.concealStyle(style),
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
      EditorInlineEmitter.append(
        text: text,
        start: item.contentStart,
        end: text.length,
        contextStyle: contentStyle,
        context: ctx,
        palette: _colorPalette,
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
    required EditorRenderContext ctx,
  }) {
    final style = ctx.style;
    final ghosts = GhostText.mightContain(text)
        ? GhostText.findGhosts(text)
        : const <GhostMatch>[];
    final lineStyle = role == MarkdownFenceRole.delimiter
        ? style.copyWith(
            fontFamily: 'monospace',
            color: ctx.baseColor.withValues(alpha: _fenceDelimiterAlpha),
          )
        : style.copyWith(fontFamily: 'monospace');
    final children = <InlineSpan>[];
    EditorSpanEmitter.emit(
      text: text,
      start: 0,
      end: text.length,
      style: lineStyle,
      baseColor: ctx.baseColor,
      ghosts: ghosts,
      out: children,
    );
    return TextSpan(style: style, children: children);
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

  /// Whether [index] is a line *inside* a ``` code fence, excluding the
  /// two delimiter lines. Public alongside [lineInFence] so a caller that
  /// acts on fence bodies only — the delimiters still behave like
  /// markdown — does not have to reason about roles it cannot see.
  bool lineInFenceBody(int index) {
    final controller = _controller;
    if (controller == null) return false;
    return _fenceRoleAt(controller, index) == MarkdownFenceRole.interior;
  }

  /// The callout role of the line at [index] — whether it leads a
  /// `> [!TYPE]` block, sits in one's body, or belongs to none. Public
  /// alongside [lineInFence] for the same reason: membership is
  /// positional, so a caller that reads a line as markdown cannot work
  /// it out from the line's own text.
  MarkdownCalloutRole calloutRoleAt(int index) {
    final controller = _controller;
    if (controller == null) return MarkdownCalloutRole.none;
    return _lineIndex.calloutRoleAt(controller.codeLines, index);
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
}
