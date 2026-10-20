import 'dart:ui' as ui;

import 'package:anta/constants/markdown_constants.dart';
import 'package:anta/utils/editor_render_context.dart';
import 'package:anta/utils/markdown_callout_syntax.dart';
import 'package:anta/utils/markdown_color_syntax.dart';
import 'package:anta/utils/markdown_editor_line_index.dart';
import 'package:anta/utils/markdown_editor_paint_spans.dart';
import 'package:anta/utils/markdown_editor_span_builder.dart';
import 'package:anta/utils/markdown_editor_span_cache.dart';
import 'package:anta/utils/markdown_inline_grammar.dart';
import 'package:anta/utils/markdown_line_shape.dart';
import 'package:anta/utils/markdown_link_patterns.dart';
import 'package:anta/utils/money_display_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Guards the live editor's hard invariant: the span returned for a line
/// carries exactly that line's UTF-16 code units, in order, with markers
/// either concealed or substituted 1:1. Every corpus entry runs through
/// `reveal on/off` x `money on/off` and asserts
///
/// * `toPlainText(includePlaceholders: true).length == line.length`,
/// * code-unit equality once the documented 1:1 substitutions are mapped
///   back (see [_substitutions]),
/// * an identical span instance on a repeated off-caret build (the memo
///   must return the same object or re_editor's paragraph cache misses),
/// * a root span whose type, `fontSize`, `height` and `fontFamily` do
///   not move between reveal states — the fork keys a line's own height
///   off exactly those, so a caret move must never reflow the document.
void main() {
  // Nothing here pumps a widget: the renderer takes an
  // [EditorRenderContext], not a `BuildContext`. The binding is still
  // needed because the money chip lays a `TextPainter` out through
  // dart:ui.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('inline candidate pre-check', () {
    test('is a superset of what the tokenizer can open', () {
      // The quick reject in front of the tokenizer (and the editor's
      // paragraph pre-check) must accept every line the tokenizer
      // would find something in — or that construct silently stops
      // rendering on plain lines.
      for (final entry in _corpus) {
        final tokens = MarkdownInlineGrammar.tokenize(
          entry.line,
          palette: MarkdownColorPalette.presets,
        );
        if (tokens.any((t) => t is! InlineGhost)) {
          expect(
            MarkdownInlineGrammar.hasCandidates(entry.line),
            isTrue,
            reason: 'pre-check rejects a tokenizable line: ${entry.label}',
          );
        }
      }
    });
  });

  for (final entry in _corpus) {
    test(entry.label, () {
      final document = <String>[
        _pad,
        ...entry.above,
        entry.line,
        ...entry.below,
        _pad,
      ];
      final index = 1 + entry.above.length;
      final controller = CodeLineEditingController.fromText(
        document.join('\n'),
      );
      addTearDown(controller.dispose);

      for (final money in const [false, true]) {
        final builder = MarkdownEditorSpanBuilder()..bind(controller);
        builder.configureMoney(
          money ? _moneyEnabled : MoneyDisplayConfig.disabled,
        );

        final spans = <bool, TextSpan?>{};
        for (final reveal in const [false, true]) {
          controller.selection = CodeLineSelection.collapsed(
            index: reveal ? index : 0,
            offset: 0,
          );
          final span = builder.build(
            context: _renderContext,
            index: index,
            codeLine: controller.codeLines[index],
          );
          spans[reveal] = span;
          final where = '${entry.label} [money=$money reveal=$reveal]';
          if (span == null) continue;
          _expectCodeUnits(entry.line, span, where, above: entry.above);
        }

        final off = spans[false];
        final on = spans[true];
        final where = '${entry.label} [money=$money]';
        expect(
          off == null,
          on == null,
          reason: 'handled-ness must not depend on reveal: $where',
        );
        // Everything the fork reads off a line's root span to decide
        // that line's own height. If any of it moved on a caret move,
        // the document would reflow under the user's thumb.
        expect(
          off.runtimeType,
          on.runtimeType,
          reason: 'root span type must not move between reveal states: $where',
        );
        expect(
          off?.style?.fontSize,
          on?.style?.fontSize,
          reason: 'root fontSize must not move between reveal states: $where',
        );
        expect(
          off?.style?.height,
          on?.style?.height,
          reason: 'root height must not move between reveal states: $where',
        );
        expect(
          off?.style?.fontFamily,
          on?.style?.fontFamily,
          reason: 'root fontFamily must not move between reveal states: $where',
        );

        // A caret at the line's end sits past every list marker, so a
        // task keeps its painted box on the caret line — a third reveal
        // state, under the same code-unit and line-height rules.
        controller.selection = CodeLineSelection.collapsed(
          index: index,
          offset: entry.line.length,
        );
        final tail = builder.build(
          context: _renderContext,
          index: index,
          codeLine: controller.codeLines[index],
        );
        expect(
          tail == null,
          off == null,
          reason: 'handled-ness must not depend on the caret offset: $where',
        );
        if (tail != null) {
          _expectCodeUnits(
            entry.line,
            tail,
            '$where [caret at end]',
            above: entry.above,
          );
          expect(
            tail.runtimeType,
            off.runtimeType,
            reason: 'root span type must not follow the caret: $where',
          );
          expect(
            tail.style?.fontSize,
            off?.style?.fontSize,
            reason: 'root fontSize must not follow the caret: $where',
          );
          expect(
            tail.style?.height,
            off?.style?.height,
            reason: 'root height must not follow the caret: $where',
          );
          expect(
            tail.style?.fontFamily,
            off?.style?.fontFamily,
            reason: 'root fontFamily must not follow the caret: $where',
          );
        }

        controller.selection = const CodeLineSelection.collapsed(
          index: 0,
          offset: 0,
        );
        final again = builder.build(
          context: _renderContext,
          index: index,
          codeLine: controller.codeLines[index],
        );
        if (off == null) {
          expect(again, isNull, reason: 'memo must stay null-stable: $where');
        } else {
          expect(
            identical(again, off),
            isTrue,
            reason: 'memo must return the identical span instance: $where',
          );
        }
      }
    });
  }

  // The code-unit suite above proves nothing is lost; this one proves
  // the right things are *hidden*. Concealed leaves (transparent + the
  // 0.01 fontSize) are dropped, and what is left is what the user sees.
  group('visible rendering', () {
    test('nested emphasis styles only the inner run bold', () {
      final render = _renderOffCaret('*a **b** c*');
      expect(render.visibleText, 'a b c');
      for (final leaf in render.leaves) {
        expect(
          leaf.style?.fontStyle,
          FontStyle.italic,
          reason: 'the whole run is italic: "${leaf.text}"',
        );
      }
      final inner = render.leaves.singleWhere((leaf) => leaf.text == 'b');
      expect(inner.style?.fontWeight, FontWeight.bold);
      for (final leaf in render.leaves.where((leaf) => leaf.text != 'b')) {
        expect(
          leaf.style?.fontWeight,
          isNot(FontWeight.bold),
          reason: 'only the inner run is bold: "${leaf.text}"',
        );
      }
    });

    test('a triple underscore run is one bold-italic token', () {
      final render = _renderOffCaret('___both___');
      expect(render.visibleText, 'both');
      final leaf = render.leaves.single;
      expect(leaf.style?.fontWeight, FontWeight.bold);
      expect(leaf.style?.fontStyle, FontStyle.italic);
    });

    test('a double-backtick fence keeps a single backtick inside', () {
      final render = _renderOffCaret('``x`y``');
      expect(render.visibleText, 'x`y');
      expect(render.leaves.single.span, isA<CodeDecoratedTextSpan>());
    });

    test('bare hashes render as an empty heading', () {
      final render = _renderOffCaret('###');
      expect(render.visibleText, isEmpty);
      expect(
        render.span.style?.fontSize,
        _baseStyle.fontSize! * MarkdownConstants.h3Scale,
      );
    });

    test('a closing hash run conceals with the leading hashes', () {
      expect(_renderOffCaret('## Week 3 ##').visibleText, 'Week 3');
      expect(_renderOffCaret('## Week 3 ##  ').visibleText, 'Week 3');
      expect(_renderOffCaret('## Title##').visibleText, 'Title##');
    });

    test('a closing hash run dims on reveal like the leading hashes', () {
      final pair = _renderBothStates('## Week 3 ##', money: false);
      expect(pair.on.visibleText, '## Week 3 ##');
      expect(_concealedRuns(pair.on.span), isEmpty);
      final lead = pair.on.leaves.first.style;
      final close = pair.on.leaves.last.style;
      expect(pair.on.leaves.last.text, endsWith('##'));
      expect(close?.color, lead?.color);
      expect(close?.fontSize, lead?.fontSize);
      expect(pair.off.visibleText, 'Week 3');
    });

    test('a spaced rule renders as a rule, never as a bullet', () {
      expect(_renderOffCaret('- - -').visibleText, '─────');
      expect(_renderOffCaret('* * *').visibleText, '─────');
      expect(_renderOffCaret('_ _ _').visibleText, '─────');
    });

    test('a spaced rule reads solid, its indent and tail as typed', () {
      expect(_renderOffCaret('-\t- -').visibleText, '─────');
      expect(_renderOffCaret('   - -  -  ').visibleText, '   ──────  ');
      expect(_renderBothStates('- - -').on.visibleText, '- - -');
    });

    test('an emphasis-wrapped diff row conceals its count', () {
      final render = _renderOffCaret(
        r'*$^ 2*',
        above: const <String>[r'$= 500', r'$+ 20 x', r'$- 5 y'],
        money: true,
      );
      expect(
        render.visibleText.contains('2'),
        isFalse,
        reason: 'the window count is chrome: ${render.visibleText}',
      );
      expect(
        render.leaves.where((leaf) => leaf.span is PlaceholderSpan).length,
        1,
        reason: 'the money chip is the row\'s only visible glyph',
      );
    });

    test('a callout lead paints its icon, bar and title in the accent', () {
      final pair = _renderBothStates(
        '> [!TIP] Rest between sets',
        money: false,
      );
      final accent = MarkdownConstants.calloutAccent(
        MarkdownCalloutType.tip,
        dark: false,
      );

      expect(pair.off.visibleText, '┃ ￼ Rest between sets');
      final icon = pair.off.leaves
          .singleWhere((leaf) => leaf.span is PlaceholderSpan)
          .span;
      expect(icon, isA<EditorCalloutIconSpan>());
      expect((icon as EditorCalloutIconSpan).accent, accent);
      expect(icon.icon, MarkdownConstants.calloutIcon(MarkdownCalloutType.tip));
      expect(pair.off.leaves.first.text, '┃');
      expect(pair.off.leaves.first.style?.color, accent);
      final title = pair.off.leaves.singleWhere(
        (leaf) => leaf.text == 'Rest between sets',
      );
      expect(title.style?.color, accent);
      expect(title.style?.fontWeight, FontWeight.bold);

      // On reveal the recognised token stays readable while editing:
      // tinted in place, with no icon standing in for the `[`.
      expect(pair.on.visibleText, '> [!TIP] Rest between sets');
      expect(
        pair.on.leaves.any((leaf) => leaf.span is PlaceholderSpan),
        isFalse,
        reason: 'a reveal line paints no icon',
      );
      final token = pair.on.leaves.singleWhere((leaf) => leaf.text == '[!TIP]');
      expect(token.style?.color, accent);
      expect(token.style?.fontWeight, FontWeight.w600);
    });

    test('a two-space lead keeps its gap and still paints the icon', () {
      final render = _renderOffCaret('>  [!TIP] x');
      final accent = MarkdownConstants.calloutAccent(
        MarkdownCalloutType.tip,
        dark: false,
      );

      // The bar, then both source spaces, then the icon standing in for
      // the token's `[`, then the space after `]`, then the title.
      expect(render.visibleText, '┃  ￼ x');
      final icon = render.leaves
          .singleWhere((leaf) => leaf.span is PlaceholderSpan)
          .span;
      expect(icon, isA<EditorCalloutIconSpan>());
      expect((icon as EditorCalloutIconSpan).accent, accent);
      expect(icon.icon, MarkdownConstants.calloutIcon(MarkdownCalloutType.tip));
    });

    test('a titleless lead paints its type word title-cased as the title', () {
      final pair = _renderBothStates('> [!WARNING]', money: false);
      final accent = MarkdownConstants.calloutAccent(
        MarkdownCalloutType.warning,
        dark: false,
      );
      expect(pair.off.visibleText, '┃ ￼Warning');
      final title = pair.off.leaves.singleWhere(
        (leaf) => leaf.text == 'Warning',
      );
      expect(title.style?.color, accent);
      expect(title.style?.fontWeight, FontWeight.bold);
      expect(pair.on.visibleText, '> [!WARNING]', reason: 'raw on reveal');
    });

    test('a fold marker conceals with the token, dimmed on reveal', () {
      final pair = _renderBothStates('> [!WARNING]- Knee', money: false);
      expect(pair.off.visibleText, '┃ ￼ Knee');
      expect(pair.on.visibleText, '> [!WARNING]- Knee');
      final marker = pair.on.leaves.singleWhere((leaf) => leaf.text == '-');
      expect(
        marker.style?.color,
        _renderContext.baseColor.withValues(alpha: _dimAlpha),
        reason: 'dimmed like every revealed marker, not the token accent',
      );
      expect(marker.style?.fontWeight, isNot(FontWeight.w600));
      expect(
        _renderOffCaret('> [!TIP]-').visibleText,
        '┃ ￼Tip',
        reason: 'a folded lead with no title still titles its type',
      );
      expect(
        _renderOffCaret('> [!TIP] - x').visibleText,
        '┃ ￼ - x',
        reason: 'a `-` after a blank is title text',
      );
    });

    test('aliases, new kinds and unknown words paint their own icon', () {
      IconData iconOf(String line) =>
          (_renderOffCaret(line).leaves
                      .singleWhere((leaf) => leaf.span is PlaceholderSpan)
                      .span
                  as EditorCalloutIconSpan)
              .icon;
      expect(
        iconOf('> [!hint] x'),
        MarkdownConstants.calloutIcon(MarkdownCalloutType.tip),
      );
      expect(
        iconOf('> [!bug] x'),
        MarkdownConstants.calloutIcon(MarkdownCalloutType.bug),
      );
      expect(
        iconOf('> [!drill]'),
        MarkdownConstants.calloutIcon(MarkdownCalloutType.note),
      );
      expect(_renderOffCaret('> [!drill]').visibleText, '┃ ￼Drill');
    });

    test('a titleless lead keeps a gap after its icon, in width only', () {
      EditorCalloutIconSpan iconOf(String line) =>
          _renderOffCaret(
                line,
              ).leaves.singleWhere((leaf) => leaf.span is PlaceholderSpan).span
              as EditorCalloutIconSpan;
      final bare = iconOf('> [!WARNING]');
      final titled = iconOf('> [!WARNING] x');
      expect(titled.gap, 0, reason: 'the source blank already separates');
      expect(bare.gap, greaterThan(0));
      expect(bare.width, titled.width + bare.gap);
      expect(bare.height, titled.height, reason: 'the line height holds');
    });

    test('a token naming no type word stays a plain quote', () {
      expect(
        _renderOffCaret(
          '> [![badge](https://x/b.svg)](https://x)',
        ).leaves.any((leaf) => leaf.span is EditorCalloutIconSpan),
        isFalse,
      );
      expect(
        _renderOffCaret('> [!two words] x').visibleText,
        '┃ [!two words] x',
      );
    });

    test('a titleless token on a body line is body text', () {
      final render = _renderOffCaret(
        '> [!NOTE]',
        above: const <String>['> [!TIP] x'],
      );
      expect(render.visibleText, '┃ [!NOTE]');
    });

    test('a tab after `>` reads a top-level quoted bullet', () {
      expect(_renderOffCaret('>\t- squat').visibleText, '┃\t• squat');
    });

    test('a token on a body line is body text, not a foreign accent', () {
      final render = _renderOffCaret(
        '> [!NOTE] y',
        above: const <String>['> [!TIP] x'],
      );
      expect(render.visibleText, '┃ [!NOTE] y');
      final note = MarkdownConstants.calloutAccent(
        MarkdownCalloutType.note,
        dark: false,
      );
      expect(render.leaves.where((leaf) => leaf.style?.color == note), isEmpty);
      expect(
        render.leaves.any((leaf) => leaf.span is PlaceholderSpan),
        isFalse,
      );
    });

    test('a quoted task paints its box behind the bar', () {
      final render = _renderOffCaret('> - [ ] warm-up');
      expect(render.visibleText, '┃ ￼ warm-up');
      expect(
        render.leaves.map((leaf) => leaf.span).whereType<EditorCheckboxSpan>(),
        hasLength(1),
      );
      expect(render.span, isA<CodeHangingTextSpan>());
      expect((render.span as CodeHangingTextSpan).hangingChars, 8);
      final ticked = _renderOffCaret(
        '> - [x] done',
        above: const <String>['> [!TODO] Today'],
      );
      final box = ticked.leaves
          .map((leaf) => leaf.span)
          .whereType<EditorCheckboxSpan>()
          .single;
      expect(box.visual, EditorCheckboxVisual.checked);
    });

    test('quoted bullets, numbers and headings render behind the bars', () {
      expect(_renderOffCaret('> - squat').visibleText, '┃ • squat');
      expect(_renderOffCaret('>   - deep').visibleText, '┃   ◦ deep');
      expect(_renderOffCaret('> > - inner').visibleText, '┃ ┃ • inner');
      expect(_renderOffCaret('> 1. bench').visibleText, '┃ 1. bench');
      final heading = _renderOffCaret('> # Week 3');
      expect(heading.visibleText, '┃ Week 3');
      final week = heading.leaves.singleWhere((leaf) => leaf.text == 'Week 3');
      expect(
        week.style?.fontSize,
        greaterThan(_renderContext.style.fontSize!),
        reason: 'a quoted heading keeps its scale',
      );
    });

    // The leaves sit under the heading's root span, so the weight they
    // render with is the root's style merged with their own.
    test('a quoted heading leaves its bar and blank at the bar weight', () {
      final heading = _renderOffCaret('> # Week 3');
      final root = heading.span.style!;
      expect(root.fontWeight, MarkdownConstants.headingWeight);
      final bar = heading.leaves.firstWhere((leaf) => leaf.text == '┃');
      final blank = heading.leaves.firstWhere((leaf) => leaf.text == ' ');
      expect(root.merge(bar.style).fontWeight, isNot(root.fontWeight));
      expect(root.merge(blank.style).fontWeight, isNot(root.fontWeight));
      final week = heading.leaves.singleWhere((leaf) => leaf.text == 'Week 3');
      expect(root.merge(week.style).fontWeight, root.fontWeight);
    });

    test('a revealed quoted heading leaves its marker and blank light', () {
      final heading = _renderBothStates('> # Week 3', money: false).on;
      final root = heading.span.style!;
      final marker = heading.leaves.firstWhere((leaf) => leaf.text == '>');
      final blank = heading.leaves.firstWhere((leaf) => leaf.text == ' ');
      expect(root.merge(marker.style).fontWeight, isNot(root.fontWeight));
      expect(root.merge(blank.style).fontWeight, isNot(root.fontWeight));
    });

    test('a quoted bullet glyph stands upright in the italic quote', () {
      final render = _renderOffCaret('> - squat');
      final glyph = render.leaves.singleWhere((leaf) => leaf.text == '•');
      expect(glyph.style?.fontStyle, FontStyle.normal);
      final content = render.leaves.singleWhere((leaf) => leaf.text == 'squat');
      expect(content.style?.fontStyle, FontStyle.italic);
    });

    test('a quoted ordered marker stands upright in the italic quote', () {
      final render = _renderOffCaret('> 1. bench');
      final marker = render.leaves.singleWhere((leaf) => leaf.text == '1.');
      expect(marker.style?.fontStyle, FontStyle.normal);
      final content = render.leaves.singleWhere((leaf) => leaf.text == 'bench');
      expect(content.style?.fontStyle, FontStyle.italic);
    });

    test('a callout body renders plain in the block accent', () {
      final render = _renderOffCaret(
        '> body',
        above: const <String>['> [!TIP] x'],
      );
      final accent = MarkdownConstants.calloutAccent(
        MarkdownCalloutType.tip,
        dark: false,
      );
      expect(render.visibleText, '┃ body');
      expect(render.leaves.first.style?.color, accent);
      final content = render.leaves.singleWhere((leaf) => leaf.text == 'body');
      expect(
        content.style?.color,
        _renderContext.baseColor,
        reason: 'body text is preview-plain, not the dimmed quote alpha',
      );
      expect(content.style?.fontStyle, isNot(FontStyle.italic));
    });

    test('a plain quote keeps the italic dimmed treatment', () {
      final render = _renderOffCaret('> quote');
      final content = render.leaves.singleWhere((leaf) => leaf.text == 'quote');
      expect(content.style?.fontStyle, FontStyle.italic);
      expect(content.style?.color, isNot(_renderContext.baseColor));
    });

    test('every quote marker becomes its own bar', () {
      expect(
        _renderOffCaret(
          '>> deeper',
          above: const <String>['> [!TIP] x'],
        ).visibleText,
        '┃┃ deeper',
      );
      expect(_renderOffCaret('>>> deep').visibleText, '┃┃┃ deep');
      expect(_renderOffCaret('> > > deep').visibleText, '┃ ┃ ┃ deep');
    });

    // A line whose indent is exotic whitespace is a blockquote line to
    // the grammar, so it must draw its bars like any other — the indent
    // stays as source (the editor may not drop a code unit) and the bar
    // takes the block accent when one is open.
    test('an exotic-whitespace indent still draws the block bar', () {
      final render = _renderOffCaret(
        ' > body',
        above: const <String>['> [!TIP] x'],
      );
      expect(render.visibleText, ' ┃ body');
      final bar = render.leaves.singleWhere((leaf) => leaf.text == '┃');
      expect(
        bar.style?.color,
        MarkdownConstants.calloutAccent(MarkdownCalloutType.tip, dark: false),
      );
    });

    test('a form-feed indented quote is a plain grey quote', () {
      final render = _renderOffCaret('> quoted');
      expect(render.visibleText, '┃ quoted');
      final bar = render.leaves.singleWhere((leaf) => leaf.text == '┃');
      expect(bar.style?.color, Colors.grey.shade300);
      expect(
        bar.style?.fontWeight,
        isNot(FontWeight.bold),
        reason: 'only a callout bar is bold',
      );
    });

    test('the bullet glyph cycles with nesting depth', () {
      expect(_renderOffCaret('- a').visibleText, '• a');
      expect(_renderOffCaret('  - a').visibleText, '  ◦ a');
      expect(_renderOffCaret('    - a').visibleText, '    ▪ a');
      expect(_renderOffCaret('      - a').visibleText, '      • a');
    });

    test('a nested money row takes the depth-1 glyph too', () {
      final render = _renderOffCaret(r'  - $+ 5 x', money: true);
      expect(
        render.leaves.any((leaf) => leaf.text == '◦'),
        isTrue,
        reason: 'the money row shares the list glyph: ${render.visibleText}',
      );
    });

    test('a table row tints its pipes and sets the cells monospace', () {
      final render = _renderOffCaret('| set | reps |');
      final pipes = render.leaves.where((leaf) => leaf.text == '|').toList();
      expect(pipes.length, 3);
      for (final pipe in pipes) {
        expect(pipe.style?.fontFamily, 'monospace');
        expect(
          pipe.style?.color,
          _renderContext.primary.withValues(alpha: _tablePipeAlpha),
        );
      }
      for (final leaf in render.leaves) {
        expect(
          leaf.style?.fontFamily,
          'monospace',
          reason: 'cells align only if every leaf is monospace: "${leaf.text}"',
        );
      }
      expect(
        render.span.style?.fontFamily,
        _baseStyle.fontFamily,
        reason: 'the root keeps the base family, so the line height holds',
      );
    });

    // A `|` the reader typed inside a ghost slot is content, not a cell
    // boundary: splitting there would cut the ghost run in half and give
    // the row a separator the table does not have.
    test('a pipe inside a ghost run is cell content, not a separator', () {
      const line = '| {{a|b}} |';
      final render = _renderOffCaret(line);
      expect(
        render.span.toPlainText(includePlaceholders: true).length,
        line.length,
        reason: 'the ghost markers conceal, they do not disappear',
      );
      expect(render.visibleText, '| a|b |');

      final tint = _renderContext.primary.withValues(alpha: _tablePipeAlpha);
      final pipes = render.leaves
          .where((leaf) => leaf.text == '|' && leaf.style?.color == tint)
          .toList();
      expect(
        pipes.length,
        2,
        reason: 'only the row\'s own pipes are separators',
      );
      for (final pipe in pipes) {
        expect(pipe.style?.fontFamily, 'monospace');
      }
      final inner = render.leaves.singleWhere(
        (leaf) => leaf.text.contains('|') && leaf.style?.color != tint,
      );
      expect(
        inner.style?.color,
        _renderContext.baseColor.withValues(alpha: 0.45),
        reason: 'the inner pipe is dimmed ghost content',
      );
    });

    test('an escaped pipe is cell content with its backslash concealed', () {
      const line = r'| a \| b | c |';
      final render = _renderOffCaret(line);
      expect(
        render.span.toPlainText(includePlaceholders: true).length,
        line.length,
      );
      expect(render.visibleText, '| a | b | c |');
      expect(_concealedRuns(render.span), <String>[r'\']);
      final tint = _renderContext.primary.withValues(alpha: _tablePipeAlpha);
      expect(
        render.leaves.where((leaf) => leaf.style?.color == tint).length,
        3,
        reason: 'the row has two cells; the escaped pipe is no separator',
      );
      for (final leaf in render.leaves) {
        expect(leaf.style?.fontFamily, 'monospace');
      }
    });

    test('a wiki alias pipe stays in its cell, which shows the alias', () {
      const line = '| [[Session 1|legs]] | x |';
      final render = _renderOffCaret(line);
      expect(
        render.span.toPlainText(includePlaceholders: true).length,
        line.length,
      );
      expect(render.visibleText, '| legs | x |');
      expect(_concealedRuns(render.span), <String>['[[Session 1|', ']]']);
      final tint = _renderContext.primary.withValues(alpha: _tablePipeAlpha);
      expect(
        render.leaves.where((leaf) => leaf.style?.color == tint).length,
        3,
      );
      final alias = render.leaves.singleWhere((leaf) => leaf.text == 'legs');
      expect(alias.style?.color, _renderContext.primary);
      expect(alias.style?.fontFamily, 'monospace');
    });

    int tintedPipes(_Render render) {
      final tint = _renderContext.primary.withValues(alpha: _tablePipeAlpha);
      return render.leaves.where((leaf) => leaf.style?.color == tint).length;
    }

    test('a revealed escaped pipe shows its backslash and splits nothing', () {
      final pair = _renderBothStates(r'| a \| b | c |', money: false);
      expect(pair.on.visibleText, r'| a \| b | c |');
      expect(_concealedRuns(pair.on.span), isEmpty);
      expect(tintedPipes(pair.on), 3);
      expect(tintedPipes(pair.off), 3);
    });

    test('an escaped closing pipe is the last cell\'s content', () {
      final render = _renderOffCaret(r'| a | b \|');
      expect(render.visibleText, '| a | b |');
      expect(_concealedRuns(render.span), <String>[r'\']);
      expect(tintedPipes(render), 2);
    });

    test('a refused wiki link leaves its pipe a cell boundary', () {
      // A closed code span inside the brackets, and a `[[` inside a code
      // span, build no link in the cell's tokenize, so the pipe splits.
      expect(tintedPipes(_renderOffCaret('| [[Bench|`PR`]] | x |')), 4);
      expect(tintedPipes(_renderOffCaret('| `[[x` | y]] |')), 3);
    });

    test("Obsidian's escaped alias is one raw cell, never a link", () {
      final render = _renderOffCaret(r'| [[Squat\|legs]] | 3x5 |');
      expect(render.visibleText, '| [[Squat|legs]] | 3x5 |');
      expect(_concealedRuns(render.span), <String>[r'\']);
      expect(tintedPipes(render), 3);
      expect(
        render.leaves.where(
          (leaf) => leaf.style?.color == _renderContext.primary,
        ),
        isEmpty,
        reason: 'no link colour, so no tap that would open "Squat\\"',
      );
    });

    test('a delimiter row renders dimmed monospace as a whole', () {
      final render = _renderOffCaret('| --- | --- |');
      expect(render.visibleText, '| --- | --- |');
      for (final leaf in render.leaves) {
        expect(leaf.style?.fontFamily, 'monospace');
        expect(
          leaf.style?.color,
          _renderContext.baseColor.withValues(alpha: _ruleAlpha),
        );
      }
    });

    test('a table row inside a fence is fence interior', () {
      final render = _renderOffCaret('| a | b |', above: const <String>['```']);
      final tinted = _renderContext.primary.withValues(alpha: _tablePipeAlpha);
      for (final leaf in render.leaves) {
        expect(leaf.style?.fontFamily, 'monospace');
        expect(
          leaf.style?.color,
          isNot(tinted),
          reason: 'a fence wins over the table shape',
        );
      }
    });

    test('inline code content shrinks without moving the root size', () {
      final render = _renderOffCaret('a `code` b');
      final code = render.leaves.singleWhere((leaf) => leaf.text == 'code');
      expect(
        code.style?.fontSize,
        _baseStyle.fontSize! * MarkdownConstants.inlineCodeScale,
      );
      expect(render.span.style?.fontSize, _baseStyle.fontSize);

      final heading = _renderOffCaret('## a `code` b');
      final headerSize = heading.span.style!.fontSize!;
      expect(headerSize, _baseStyle.fontSize! * MarkdownConstants.h2Scale);
      expect(
        heading.leaves
            .singleWhere((leaf) => leaf.text == 'code')
            .style
            ?.fontSize,
        headerSize * MarkdownConstants.inlineCodeScale,
      );
    });

    test('a wiki link conceals its brackets and tints its title', () {
      final render = _renderOffCaret('[[a]]');
      expect(render.visibleText, 'a');
      expect(
        _concealedRuns(render.span),
        <String>['[[', ']]'],
        reason: 'all four bracket units are concealed chrome',
      );
      final title = render.leaves.single;
      expect(title.text, 'a');
      expect(title.style?.color, _renderContext.primary);
      expect(
        title.style?.decoration?.contains(TextDecoration.underline),
        isTrue,
        reason: 'the title wears the same style as a [text](url) link text',
      );
    });

    test('a revealed wiki link dims its brackets and keeps the title', () {
      final pair = _renderBothStates('[[a]]', money: false);
      expect(pair.on.visibleText, '[[a]]');
      expect(
        _concealedRuns(pair.on.span),
        isEmpty,
        reason: 'a reveal line conceals nothing — the source is editable',
      );
      final dim = _renderContext.baseColor.withValues(alpha: _dimAlpha);
      for (final marker in pair.on.leaves.where(
        (leaf) => leaf.text == '[[' || leaf.text == ']]',
      )) {
        expect(marker.style?.color, dim);
        expect(
          marker.style?.fontSize,
          _baseStyle.fontSize,
          reason: 'a dimmed marker is visible, not collapsed',
        );
      }
      final title = pair.on.leaves.singleWhere((leaf) => leaf.text == 'a');
      expect(title.style?.color, _renderContext.primary);
      expect(
        title.style?.decoration?.contains(TextDecoration.underline),
        isTrue,
      );
    });

    test('an aliased link shows only the alias, in the link style', () {
      final render = _renderOffCaret('[[Squat Day|legs]]');
      expect(render.visibleText, 'legs');
      expect(
        _concealedRuns(render.span),
        <String>['[[Squat Day|', ']]'],
        reason: 'the title and the pipe join the concealed chrome',
      );
      final alias = render.leaves.single;
      expect(alias.style?.color, _renderContext.primary);
      expect(
        alias.style?.decoration?.contains(TextDecoration.underline),
        isTrue,
      );

      final pair = _renderBothStates('[[Squat Day|legs]]', money: false);
      expect(pair.on.visibleText, '[[Squat Day|legs]]');
      expect(_concealedRuns(pair.on.span), isEmpty);
    });

    test('a blank alias shows the title', () {
      final render = _renderOffCaret('[[a| ]]');
      expect(render.visibleText, 'a');
      expect(_concealedRuns(render.span), <String>['[[', '| ]]']);
    });

    test('a second pipe leaves the construct plain source', () {
      expect(
        _buildOffCaret('[[a|b|c]]'),
        isNull,
        reason: 'a line with no construct on it is declined outright',
      );
    });

    test('a ghost in the title keeps the brackets visible', () {
      final render = _renderOffCaret('[[a {{g}} b]]');
      expect(render.visibleText, '[[a g b]]');
      expect(
        _concealedRuns(render.span),
        <String>['{{', '}}'],
        reason: 'only the ghost markers conceal — the construct is literal',
      );
      for (final leaf in render.leaves.where(
        (leaf) => leaf.text.contains('['),
      )) {
        expect(leaf.style?.color, _renderContext.baseColor);
        expect(
          leaf.style?.decoration ?? TextDecoration.none,
          TextDecoration.none,
        );
      }
    });

    test("an embed's bang becomes the dimmed picture glyph", () {
      final dim = _renderContext.baseColor.withValues(alpha: _dimAlpha);
      final render = _renderOffCaret('![[a]]');
      expect(render.visibleText, '${MarkdownLinkPatterns.imageGlyph}a');
      expect(_concealedRuns(render.span), <String>['[[', ']]']);
      final glyph = render.leaves.first;
      expect(glyph.text, MarkdownLinkPatterns.imageGlyph);
      expect(glyph.style?.color, dim);
      final title = render.leaves.last;
      expect(title.text, 'a');
      expect(title.style?.color, _renderContext.primary);

      final pair = _renderBothStates('![[a]]', money: false);
      expect(pair.on.visibleText, '![[a]]');
      expect(pair.on.leaves.first.text, '!');
      expect(pair.on.leaves.first.style?.color, dim);
    });

    test('an image shows the glyph and its alt dimmed, chrome concealed', () {
      final dim = _renderContext.baseColor.withValues(alpha: _dimAlpha);
      final render = _renderOffCaret('a ![leg day](https://x.y/a.png "T") b');
      expect(
        render.visibleText,
        'a ${MarkdownLinkPatterns.imageGlyph}leg day b',
      );
      expect(_concealedRuns(render.span), <String>[
        '[',
        '](https://x.y/a.png "T")',
      ]);
      final alt = render.leaves.singleWhere((leaf) => leaf.text == 'leg day');
      expect(alt.style?.color, dim);
      expect(
        alt.style?.decoration ?? TextDecoration.none,
        TextDecoration.none,
        reason: 'an image is not a link: no underline, no zone',
      );

      final pair = _renderBothStates('![a](u)', money: false);
      expect(pair.on.visibleText, '![a](u)');
      expect(_concealedRuns(pair.on.span), isEmpty);
    });

    test('an image with an empty alt is the glyph alone', () {
      final render = _renderOffCaret('a ![](https://x.y/a.png) b');
      expect(render.visibleText, 'a ${MarkdownLinkPatterns.imageGlyph} b');
      expect(_concealedRuns(render.span), <String>[
        '[',
        '](https://x.y/a.png)',
      ]);
    });

    test('an angle autolink conceals its brackets and tints the inside', () {
      final render = _renderOffCaret('see <https://x.y> now');
      expect(render.visibleText, 'see https://x.y now');
      expect(_concealedRuns(render.span), <String>['<', '>']);
      final url = render.leaves.singleWhere(
        (leaf) => leaf.text == 'https://x.y',
      );
      expect(url.style?.color, _renderContext.primary);
      expect(url.style?.decoration?.contains(TextDecoration.underline), isTrue);
    });

    test("a link's title is concealed with its destination", () {
      final render = _renderOffCaret('[t](https://x.com/s "Guide")');
      expect(render.visibleText, 't');
      expect(_concealedRuns(render.span), <String>[
        '[',
        '](https://x.com/s "Guide")',
      ]);
    });

    test('a wiki link inside bold takes the weight and the link colour', () {
      final render = _renderOffCaret('**[[a]]**');
      expect(render.visibleText, 'a');
      final title = render.leaves.single;
      expect(title.style?.fontWeight, FontWeight.bold);
      expect(title.style?.color, _renderContext.primary);
      expect(
        title.style?.decoration?.contains(TextDecoration.underline),
        isTrue,
      );
    });

    // The title is literal all the way down — a note really can be named
    // `**a**` — so its markers are title text, not emphasis chrome.
    test('emphasis markers inside a title are title text', () {
      final render = _renderOffCaret('[[**a**]]');
      expect(render.visibleText, '**a**');
      expect(_concealedRuns(render.span), <String>['[[', ']]']);
      final title = render.leaves.single;
      expect(title.text, '**a**');
      expect(title.style?.color, _renderContext.primary);
      expect(title.style?.fontWeight, isNot(FontWeight.bold));
    });
  });

  group('entities and hard breaks', () {
    test("an entity's ampersand shows the decoded character", () {
      final render = _renderOffCaret('a &copy; b &#x2014;');
      expect(render.visibleText, 'a © b —');
      expect(_concealedRuns(render.span), <String>['copy;', '#x2014;']);
    });

    test('an entity reads as its dimmed source on reveal', () {
      final pair = _renderBothStates('a &amp; b', money: false);
      expect(pair.on.visibleText, 'a &amp; b');
      expect(_concealedRuns(pair.on.span), isEmpty);
      final dim = _renderContext.baseColor.withValues(alpha: _dimAlpha);
      final source = pair.on.leaves.where(
        (leaf) => leaf.text == '&' || leaf.text == 'amp;',
      );
      expect(source.map((leaf) => leaf.text).join(), '&amp;');
      for (final leaf in source) {
        expect(leaf.style?.color, dim, reason: leaf.text);
      }
    });

    test('an unknown entity stays plain source', () {
      expect(_buildOffCaret('a &nope; b'), isNull);
    });

    test('a trailing backslash is concealed off-caret and dim on reveal', () {
      final pair = _renderBothStates(r'next line\', money: false);
      expect(pair.off.visibleText, 'next line');
      expect(_concealedRuns(pair.off.span), <String>[r'\']);
      expect(pair.on.visibleText, r'next line\');
      expect(_concealedRuns(pair.on.span), isEmpty);
      final slash = pair.on.leaves.singleWhere((leaf) => leaf.text == r'\');
      expect(
        slash.style?.color,
        _renderContext.baseColor.withValues(alpha: _dimAlpha),
      );
    });

    test('a url, a heading, a callout title and a money row keep it', () {
      for (final line in const <String>[
        r'see https://a.com/x\',
        r'# a\',
        r'> [!NOTE] Title\',
      ]) {
        final render = _renderOffCaret(line);
        expect(render.visibleText, endsWith(r'\'), reason: line);
        expect(_concealedRuns(render.span), isNot(contains(r'\')));
      }
      final money = _renderBothStates(r'$+ 5 coffee\', money: true);
      expect(money.off.visibleText, endsWith(r'\'));
    });

    test('an escaped trailing backslash keeps its escaped half', () {
      final render = _renderOffCaret(r'a\\');
      expect(render.visibleText, r'a\');
    });

    test('a line that is only a backslash stays plain source', () {
      expect(_buildOffCaret(r'\'), isNull);
    });
  });

  // Fence pairing, `%%` comments and the hard break all read other lines,
  // so each case builds one line of a real multi-line document.
  group('fences, comments and the positional hard break', () {
    TextSpan? at(List<String> lines, int index, {required int caretLine}) {
      final controller = CodeLineEditingController.fromText(lines.join('\n'));
      addTearDown(controller.dispose);
      final builder = MarkdownEditorSpanBuilder()..bind(controller);
      builder.configureMoney(MoneyDisplayConfig.disabled);
      controller.selection = CodeLineSelection.collapsed(
        index: caretLine,
        offset: 0,
      );
      return builder.build(
        context: _renderContext,
        index: index,
        codeLine: controller.codeLines[index],
      );
    }

    final dim = _renderContext.baseColor.withValues(alpha: _dimAlpha);

    test('a trailing backslash conceals only before a non-blank line', () {
      expect(_concealedRuns(at([r'a\', 'b'], 0, caretLine: 1)!), [r'\']);
      expect(at([_pad, r'a\'], 1, caretLine: 0), isNull);
      expect(at([_pad, r'a\', '', 'b'], 1, caretLine: 0), isNull);
      expect(at([_pad, r'a\', ' \t', 'b'], 1, caretLine: 0), isNull);
      final path = at([_pad, r'- D:\Backups\'], 1, caretLine: 0)!;
      expect(
        _visibleLeaves(path).map((leaf) => leaf.text).join(),
        endsWith(r'D:\Backups\'),
      );
      expect(_concealedRuns(path), isNot(contains(r'\')));
    });

    test('a trailing backslash conceals only where the paragraph goes on', () {
      String? concealed(List<String> lines) {
        // A plain line with a literal tail builds no styled span at all.
        final span = at(lines, 0, caretLine: lines.length - 1);
        if (span == null) return null;
        return _concealedRuns(span).contains(r'\') ? r'\' : null;
      }

      const pad = _pad;
      expect(concealed([r'- D:\a\', r'- D:\b\', pad]), isNull);
      expect(concealed([r'a\', '# H', pad]), isNull);
      expect(concealed([r'a\', '```', pad]), isNull);
      expect(concealed([r'a\', '***', pad]), isNull);
      expect(concealed([r'a\', '%%', pad]), isNull);
      expect(concealed([r'a\', '| a | b |', pad]), isNull);
      expect(concealed([r'a\', '> quoted', pad]), isNull);
      expect(concealed([r'> a\', 'b', pad]), isNull);
      expect(concealed([r'> a\', '> - b', pad]), isNull);
      expect(concealed([r'a\', 'b', '===', pad]), isNull);
      expect(concealed([r'> a\', '> > b', pad]), isNull);
      expect(concealed([r'> a\', '> [!TIP] x', pad]), isNull);
      expect(concealed([r'a\', 'b', 'c', pad]), r'\');
      expect(concealed([r'- item\', '  more', pad]), r'\');
      expect(concealed([r'> a\', '> b', pad]), r'\');
    });

    test('a callout body and a quote follow the next line too', () {
      final body = ['> [!TIP] x', r'> body\'];
      // Only a quote line continues a quote's paragraph (sweep S2).
      expect(_concealedRuns(at([...body, '> more', _pad], 1, caretLine: 3)!), [
        r'\',
      ]);
      expect(
        _concealedRuns(at([...body, _pad], 1, caretLine: 2)!),
        isNot(contains(r'\')),
      );
      expect(
        _concealedRuns(at([_pad, ...body], 2, caretLine: 0)!),
        isNot(contains(r'\')),
      );
      expect(
        _concealedRuns(at([_pad, r'> quoted\'], 1, caretLine: 0)!),
        isNot(contains(r'\')),
      );
    });

    test('the memo re-renders a line when the line below it changes', () {
      final controller = CodeLineEditingController.fromText(
        <String>[r'a\', 'b', _pad].join('\n'),
      );
      addTearDown(controller.dispose);
      final builder = MarkdownEditorSpanBuilder()..bind(controller);
      builder.configureMoney(MoneyDisplayConfig.disabled);
      controller.selection = const CodeLineSelection.collapsed(
        index: 2,
        offset: 0,
      );
      TextSpan? first() => builder.build(
        context: _renderContext,
        index: 0,
        codeLine: controller.codeLines[0],
      );

      final broken = first();
      expect(_concealedRuns(broken!), [r'\']);
      expect(identical(first(), broken), isTrue);

      controller.codeLines = controller.codeLines.replaceLine(1, CodeLine(''));
      expect(first(), isNull, reason: 'a blank line below keeps the `\\`');

      controller.codeLines = controller.codeLines.replaceLine(1, CodeLine('c'));
      expect(_concealedRuns(first()!), [r'\']);
    });

    // The callout memo is positional and outlives an edit, so its key must
    // carry the literal-tail bit: one builder, the line below flipped
    // between blank and not.
    for (final (name, lines, below) in [
      ('a callout body', [_pad, '> [!TIP] x', r'> body\', '> more'], 3),
    ]) {
      test('$name re-renders when the line below turns blank and back', () {
        final controller = CodeLineEditingController.fromText(lines.join('\n'));
        addTearDown(controller.dispose);
        final builder = MarkdownEditorSpanBuilder()..bind(controller);
        builder.configureMoney(MoneyDisplayConfig.disabled);
        controller.selection = const CodeLineSelection.collapsed(
          index: 0,
          offset: 0,
        );
        TextSpan line() => builder.build(
          context: _renderContext,
          index: below - 1,
          codeLine: controller.codeLines[below - 1],
        )!;
        final String original = lines[below];

        expect(_concealedRuns(line()), contains(r'\'));
        controller.codeLines = controller.codeLines.replaceLine(
          below,
          CodeLine(''),
        );
        expect(_concealedRuns(line()), isNot(contains(r'\')));
        controller.codeLines = controller.codeLines.replaceLine(
          below,
          CodeLine(original),
        );
        expect(_concealedRuns(line()), contains(r'\'));
      });
    }

    test('a tilde fence dims its delimiters like a backtick one', () {
      final lines = ['~~~ py', 'x = 1', '~~~', _pad];
      for (final index in [0, 2]) {
        final leaves = _visibleLeaves(at(lines, index, caretLine: 3)!);
        for (final leaf in leaves) {
          expect(leaf.style?.fontFamily, 'monospace');
          expect(leaf.style?.color, isNot(_renderContext.baseColor));
        }
      }
      final body = _visibleLeaves(at(lines, 1, caretLine: 3)!);
      expect(body.single.style?.fontFamily, 'monospace');
    });

    test('a one-line ```npm i``` is inline code, not a fence', () {
      final span = at(['```npm i```', '- [ ] a', _pad], 0, caretLine: 2)!;
      expect(_concealedRuns(span), ['```', '```']);
      expect(at(['```npm i```', '- [ ] a', _pad], 1, caretLine: 2), isNotNull);
    });

    test('a block comment dims every line in both reveal states', () {
      final lines = ['%%', 'secret #tag', '%%', _pad];
      for (final index in [0, 1, 2]) {
        for (final caret in [index, 3]) {
          final span = at(lines, index, caretLine: caret)!;
          expect(_concealedRuns(span), isEmpty);
          for (final leaf in _visibleLeaves(span)) {
            expect(leaf.style?.color, dim, reason: '$index/$caret');
          }
        }
      }
    });

    // S2.7 — the properties block renders as a comment block does: no
    // rule, no setext H2 under the last property, nothing concealed.
    test('a front matter dims every line in both reveal states', () {
      // C1 fix pass T7 — a task-shaped item under a key paints no box, and
      // every line keeps its code units.
      final lines = [
        '---',
        'tags: [a]',
        'todo:',
        '- [ ] x',
        'title: x',
        '---',
        '# H',
        _pad,
      ];
      for (final index in [0, 1, 2, 3, 4, 5]) {
        for (final caret in [index, 7]) {
          final span = at(lines, index, caretLine: caret)!;
          expect(_concealedRuns(span), isEmpty);
          expect(span.toPlainText(), lines[index], reason: '$index/$caret');
          span.visitChildren((child) {
            expect(child.runtimeType, TextSpan, reason: '$index/$caret');
            return true;
          });
          for (final leaf in _visibleLeaves(span)) {
            expect(leaf.style?.color, dim, reason: '$index/$caret');
          }
        }
      }
    });

    test('an inline comment conceals off-caret and dims on reveal', () {
      final lines = ['a %%x #t%% b', _pad];
      expect(_concealedRuns(at(lines, 0, caretLine: 1)!), ['%%x #t%%']);
      final on = at(lines, 0, caretLine: 0)!;
      expect(_concealedRuns(on), isEmpty);
      final comment = _visibleLeaves(
        on,
      ).singleWhere((leaf) => leaf.text == '%%x #t%%');
      expect(comment.style?.color, dim);
    });
  });

  // A callout body's rendering is a function of the lead above it, which
  // is positional state. The memo has to key on that, or a body keeps
  // the colour of a block that has since changed type.
  group('positional callout memo', () {
    test('a body follows the lead above it, not its own text', () {
      final controller = CodeLineEditingController.fromText(
        <String>['> [!TIP] x', '> body', _pad].join('\n'),
      );
      addTearDown(controller.dispose);
      final builder = MarkdownEditorSpanBuilder()..bind(controller);
      builder.configureMoney(MoneyDisplayConfig.disabled);
      controller.selection = const CodeLineSelection.collapsed(
        index: 2,
        offset: 0,
      );

      TextSpan? body() => builder.build(
        context: _renderContext,
        index: 1,
        codeLine: controller.codeLines[1],
      );

      final tip = MarkdownConstants.calloutAccent(
        MarkdownCalloutType.tip,
        dark: false,
      );
      final warning = MarkdownConstants.calloutAccent(
        MarkdownCalloutType.warning,
        dark: false,
      );

      final first = body();
      expect(first, isNotNull);
      expect(_barColour(first!), tip);
      expect(builder.calloutRoleAt(0), MarkdownCalloutRole.lead);
      expect(builder.calloutRoleAt(1), MarkdownCalloutRole.body);
      expect(builder.calloutRoleAt(2), MarkdownCalloutRole.none);
      expect(
        identical(body(), first),
        isTrue,
        reason: 'an unchanged block must hit the positional memo',
      );

      controller.codeLines = controller.codeLines.replaceLine(
        0,
        CodeLine('> [!WARNING] x'),
      );
      final warned = body();
      expect(
        identical(warned, first),
        isFalse,
        reason: 'the block changed type, so the body must re-render',
      );
      expect(_barColour(warned!), warning);
      expect(builder.calloutRoleAt(1), MarkdownCalloutRole.body);

      controller.codeLines = controller.codeLines.replaceLine(
        2,
        CodeLine('another padding line'),
      );
      expect(
        identical(body(), warned),
        isTrue,
        reason: 'an edit outside the block must not disturb the memo',
      );

      controller.codeLines = controller.codeLines.replaceLine(
        0,
        CodeLine('> x'),
      );
      final plain = body();
      expect(builder.calloutRoleAt(0), MarkdownCalloutRole.none);
      expect(builder.calloutRoleAt(1), MarkdownCalloutRole.none);
      final content = _visibleLeaves(
        plain!,
      ).singleWhere((leaf) => leaf.text == 'body');
      expect(content.style?.fontStyle, FontStyle.italic);
      expect(content.style?.color, isNot(warning));
    });

    test('a lead inside a fence renders as fence interior', () {
      final render = _renderOffCaret(
        '> [!TIP] x',
        above: const <String>['```'],
      );
      expect(
        render.leaves.any((leaf) => leaf.span is PlaceholderSpan),
        isFalse,
        reason: 'a fenced lead is code, not a callout',
      );
      for (final leaf in render.leaves) {
        expect(leaf.style?.fontFamily, 'monospace');
      }
    });
  });

  // A display row's accent — and with it the colour of its label — is a
  // function of the balance above it, which is positional state. A
  // reveal build paints no chip, but it still has to resolve that
  // balance: colour must not depend on where the caret is.
  group('money accent survives a caret move', () {
    test('a negative total stays negative on the caret line', () {
      final pair = _renderBothStates(
        r'$$ balance',
        above: const <String>[r'$= 500', r'$- 900 rent'],
      );
      final off = _labelColour(pair.off, 'balance');
      final on = _labelColour(pair.on, 'balance');

      expect(
        on,
        off,
        reason:
            'the row accent must not move between reveal states\n'
            '  off-caret: ${pair.off.visibleText}\n'
            '  on-caret:  ${pair.on.visibleText}',
      );
      expect(
        off,
        MarkdownConstants.moneyNegative(dark: false),
        reason: 'the running balance is 500 - 900',
      );
      expect(
        off,
        isNot(_renderContext.primary),
        reason: 'a zero balance would render primary — that is the bug',
      );
    });

    test('a target status with no target stays warning-tinted', () {
      final pair = _renderBothStates(r'$! left');
      final off = _labelColour(pair.off, 'left');
      final on = _labelColour(pair.on, 'left');

      expect(on, off, reason: 'the no-target warning must survive reveal');
      expect(off, MarkdownConstants.moneyWarning(dark: false));
    });

    test('a target status reads its declaration on the caret line', () {
      final pair = _renderBothStates(
        r'$! left',
        above: const <String>[r'$! 1000', r'$= 200'],
      );
      final off = _labelColour(pair.off, 'left');

      expect(_labelColour(pair.on, 'left'), off);
      expect(
        off,
        isNot(MarkdownConstants.moneyWarning(dark: false)),
        reason: 'a declaration precedes the row, so it is not a no-target',
      );
    });
  });

  // The positional memo's key carries the row's balance, so the same
  // text renders differently above different ledgers — and identically
  // above the same one.
  group('positional money memo', () {
    test('keys on the balance, not on the row text alone', () {
      final controller = CodeLineEditingController.fromText(
        <String>[r'$= 500', r'$$ balance', _pad].join('\n'),
      );
      addTearDown(controller.dispose);
      final builder = MarkdownEditorSpanBuilder()..bind(controller);
      builder.configureMoney(_moneyEnabled);
      controller.selection = const CodeLineSelection.collapsed(
        index: 2,
        offset: 0,
      );

      TextSpan? total() => builder.build(
        context: _renderContext,
        index: 1,
        codeLine: controller.codeLines[1],
      );

      final first = total();
      expect(first, isNotNull);
      expect(
        identical(total(), first),
        isTrue,
        reason: 'an unchanged balance must hit the positional memo',
      );

      controller.codeLines = controller.codeLines.replaceLine(
        0,
        CodeLine(r'$= 900'),
      );
      final moved = total();
      expect(
        identical(moved, first),
        isFalse,
        reason: 'editing the line above must re-render the total',
      );

      controller.codeLines = controller.codeLines.replaceLine(
        0,
        CodeLine(r'$= 500'),
      );
      expect(
        identical(total(), first),
        isTrue,
        reason: 'the original balance must find its original span again',
      );
    });
  });

  // Enter-continuation leaves empty items behind constantly. They have a
  // marker but no content paragraph, so the fork's hanging-indent root
  // must not be used — there is nothing to hang.
  group('empty list items', () {
    for (final line in const <String>['- ', '* ', '1. ', '1) ', '- [ ] ']) {
      test('"$line" keeps a plain root in both reveal states', () {
        final pair = _renderBothStates(line, money: false);
        for (final render in <_Render>[pair.off, pair.on]) {
          expect(
            render.span,
            isA<TextSpan>().having(
              (span) => span is CodeHangingTextSpan,
              'is a hanging span',
              isFalse,
            ),
            reason: 'an empty item has no content to hang under',
          );
        }
      });
    }
  });

  // E6 + E5: on the caret line a task's box stays painted until the caret
  // enters its marker, and an unfocused editor reveals nothing at all.
  group('the box on the caret line', () {
    /// Builds [line] (with [below] after it) under [selectionOn], which
    /// receives the line's index, on a builder bound to [focus] when one
    /// is given.
    _Render renderUnder(
      String line,
      CodeLineSelection Function(int index) selectionOn, {
      List<String> below = const <String>[],
      FocusNode? focus,
      ValueListenable<bool>? findActive,
    }) {
      final controller = CodeLineEditingController.fromText(
        <String>[_pad, line, ...below, _pad].join('\n'),
      );
      addTearDown(controller.dispose);
      final builder = MarkdownEditorSpanBuilder()
        ..bind(controller)
        ..bindFocus(focus)
        ..bindRevealWhenUnfocused(findActive);
      controller.selection = selectionOn(1);
      final span = builder.build(
        context: _renderContext,
        index: 1,
        codeLine: controller.codeLines[1],
      );
      expect(span, isNotNull, reason: 'expected a styled span for: $line');
      _expectCodeUnits(line, span!, 'caret line: $line');
      final leaves = _visibleLeaves(span);
      return (
        span: span,
        leaves: leaves,
        visibleText: leaves.map((leaf) => leaf.text).join(),
      );
    }

    CodeLineSelection caretAt(int offset) =>
        CodeLineSelection.collapsed(index: 1, offset: offset);

    EditorCheckboxSpan? boxOf(_Render render) => render.leaves
        .map((leaf) => leaf.span)
        .whereType<EditorCheckboxSpan>()
        .firstOrNull;

    test('a quoted task follows the caret past its quote run', () {
      const quoted = '> - [ ] warm-up';
      expect(
        boxOf(renderUnder(quoted, (_) => caretAt(quoted.length))),
        isNotNull,
        reason: 'past the marker the box stays painted',
      );
      expect(
        boxOf(renderUnder(quoted, (_) => caretAt(1))),
        isNotNull,
        reason: 'on the bar the caret is not in the marker',
      );
      expect(boxOf(renderUnder(quoted, (_) => caretAt(2))), isNull);
      expect(boxOf(renderUnder(quoted, (_) => caretAt(5))), isNull);

      // A callout body reveals through the positional route, which must
      // hand the caret through as well.
      final controller = CodeLineEditingController.fromText(
        <String>[_pad, '> [!TODO] Today', quoted, _pad].join('\n'),
      );
      addTearDown(controller.dispose);
      final builder = MarkdownEditorSpanBuilder()..bind(controller);
      controller.selection = const CodeLineSelection.collapsed(
        index: 2,
        offset: quoted.length,
      );
      final span = builder.build(
        context: _renderContext,
        index: 2,
        codeLine: controller.codeLines[2],
      )!;
      expect(
        _visibleLeaves(span).map((leaf) => leaf.span),
        contains(isA<EditorCheckboxSpan>()),
        reason: 'a callout body hands the caret through too',
      );
    });

    const line = '- [ ] squat **5x5**';

    test('a caret past the marker keeps the box and reveals the content', () {
      final render = renderUnder(line, (_) => caretAt(line.length));
      expect(boxOf(render), isNotNull, reason: 'the box stays painted');
      expect(
        render.visibleText,
        '￼ squat **5x5**',
        reason: 'the marker conceals as off-caret, the content stays raw',
      );
    });

    test('a caret inside the marker reveals it raw', () {
      for (final offset in const [0, 3, 5]) {
        final render = renderUnder(line, (_) => caretAt(offset));
        expect(boxOf(render), isNull, reason: 'caret at $offset');
        expect(render.visibleText, line, reason: 'caret at $offset');
      }
    });

    // Enter continues `- [ ] ` with the caret at contentStart; a raw
    // marker there would turn into the box under the first typed letter.
    test('a caret at contentStart keeps the box painted', () {
      expect(boxOf(renderUnder(line, (_) => caretAt(6))), isNotNull);
      expect(boxOf(renderUnder('- [ ] ', (_) => caretAt(6))), isNotNull);
    });

    test('a caret inside the indent keeps the box', () {
      const nested = '  - [ ] squat';
      expect(boxOf(renderUnder(nested, (_) => caretAt(1))), isNotNull);
      expect(boxOf(renderUnder(nested, (_) => caretAt(2))), isNull);
    });

    test('a range selection over the line reveals the marker raw', () {
      final render = renderUnder(
        line,
        (index) => CodeLineSelection(
          baseIndex: index,
          baseOffset: 8,
          extentIndex: index,
          extentOffset: line.length,
        ),
      );
      expect(boxOf(render), isNull);
      expect(render.visibleText, line);
    });

    test('an indeterminate parent keeps its visual on the caret line', () {
      final render = renderUnder(
        '- [ ] parent',
        (_) => caretAt('- [ ] parent'.length),
        below: const <String>['  - [x] a', '  - [ ] b'],
      );
      expect(boxOf(render)?.visual, EditorCheckboxVisual.indeterminate);
    });

    test('an unfocused editor renders the caret line off-caret', () {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      expect(focus.hasFocus, isFalse);
      final unfocused = renderUnder(line, (_) => caretAt(0), focus: focus);
      expect(
        unfocused.visibleText,
        _renderOffCaret(line).visibleText,
        reason: 'no focus, no reveal — even with the caret in the marker',
      );
      expect(boxOf(unfocused), isNotNull);
    });

    // Y1: find selects its match while the search field holds focus.
    test('an active find session reveals the match line unfocused', () {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      const link = '[video](https://youtube.com/x)';
      final findActive = ValueNotifier<bool>(true);
      addTearDown(findActive.dispose);
      CodeLineSelection match(int index) => CodeLineSelection(
        baseIndex: index,
        baseOffset: 16,
        extentIndex: index,
        extentOffset: 23,
      );
      final searching = renderUnder(
        link,
        match,
        focus: focus,
        findActive: findActive,
      );
      expect(searching.visibleText, link, reason: 'the url shows raw');
      findActive.value = false;
      final closed = renderUnder(
        link,
        match,
        focus: focus,
        findActive: findActive,
      );
      expect(closed.visibleText, _renderOffCaret(link).visibleText);
    });
  });

  group('custom task states', () {
    EditorCheckboxSpan boxOf(_Render render) => render.leaves
        .map((leaf) => leaf.span)
        .whereType<EditorCheckboxSpan>()
        .single;

    TextDecoration? decorationOf(_Render render, String text) => render.leaves
        .singleWhere((leaf) => leaf.text == text)
        .style
        ?.decoration;

    test('a cancelled box paints its cross and strikes its content', () {
      final render = _renderOffCaret('- [-] skipped');
      final box = boxOf(render);
      expect(box.visual, EditorCheckboxVisual.custom);
      expect(box.state, '-');
      expect(decorationOf(render, 'skipped'), TextDecoration.lineThrough);
    });

    test('the other states paint their unit and leave the content plain', () {
      for (final state in ['/', '>', '<', '?', '!', '*', 'y']) {
        final render = _renderOffCaret('- [$state] item');
        final box = boxOf(render);
        expect(box.visual, EditorCheckboxVisual.custom, reason: state);
        expect(box.state, state);
        expect(
          decorationOf(render, 'item'),
          isNot(TextDecoration.lineThrough),
          reason: state,
        );
      }
    });

    test('the open and done boxes carry no state', () {
      expect(boxOf(_renderOffCaret('- [ ] a')).state, '');
      expect(boxOf(_renderOffCaret('- [x] a')).state, '');
    });

    test('a custom parent keeps its own mark over mixed children', () {
      final controller = CodeLineEditingController.fromText(
        <String>[
          _pad,
          '- [-] parent',
          '  - [x] done',
          '  - [ ] open',
        ].join('\n'),
      );
      addTearDown(controller.dispose);
      final builder = MarkdownEditorSpanBuilder()..bind(controller);
      builder.configureMoney(MoneyDisplayConfig.disabled);
      final span = builder.build(
        context: _renderContext,
        index: 1,
        codeLine: controller.codeLines[1],
      )!;
      final box = _visibleLeaves(
        span,
      ).map((leaf) => leaf.span).whereType<EditorCheckboxSpan>().single;
      expect(box.visual, EditorCheckboxVisual.custom);
    });

    test('a custom-state box is value-equal only to the same state', () {
      EditorCheckboxSpan box(String state) => EditorCheckboxSpan(
        side: 10,
        visual: EditorCheckboxVisual.custom,
        accent: Colors.blue,
        border: Colors.grey,
        mark: Colors.white,
        state: state,
      );
      expect(box('-'), box('-'));
      expect(box('-'), isNot(box('/')));
      expect(box('-').hashCode, box('-').hashCode);
    });

    // A dash would read as the indeterminate parent's bar.
    test('a cancelled box paints a cross, not a dash', () {
      const border = Color(0xFF808080);
      const box = EditorCheckboxSpan(
        side: 20,
        visual: EditorCheckboxVisual.custom,
        accent: Color(0xFF2050C0),
        border: border,
        mark: Color(0xFFFFFFFF),
        state: '-',
      );
      void paint(Canvas canvas) =>
          box.paint(canvas, const Rect.fromLTWH(0, 0, 20, 20));
      expect(
        paint,
        paints
          ..rrect(color: border)
          ..line(color: border)
          ..line(color: border),
      );
    });

    test('every state paints, past the glyph cache bound too', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      void paint(String state, double side) {
        final recorder = ui.PictureRecorder();
        EditorCheckboxSpan(
          side: side,
          visual: EditorCheckboxVisual.custom,
          accent: Colors.blue,
          border: Colors.grey,
          mark: Colors.white,
          state: state,
        ).paint(Canvas(recorder), Rect.fromLTWH(0, 0, side, side));
        recorder.endRecording().dispose();
      }

      for (final state in const ['-', '/', '>', '<', '*', '?', '!', 'y']) {
        expect(() => paint(state, 14), returnsNormally, reason: state);
      }
      // Each size is its own cache key: 40 of them overrun the bound, so
      // the cache disposes its painters and lays the next glyph out anew.
      for (var i = 0; i < 40; i++) {
        expect(() => paint('?', 10.0 + i), returnsNormally);
      }
      expect(() => paint('?', 14), returnsNormally);
    });
  });

  group('setext headings', () {
    late CodeLineEditingController controller;
    late MarkdownEditorSpanBuilder builder;

    void open(List<String> lines) {
      controller = CodeLineEditingController.fromText(
        <String>[...lines, _pad].join('\n'),
      );
      addTearDown(controller.dispose);
      builder = MarkdownEditorSpanBuilder()..bind(controller);
      builder.configureMoney(MoneyDisplayConfig.disabled);
      controller.selection = CodeLineSelection.collapsed(
        index: lines.length,
        offset: 0,
      );
    }

    TextSpan? at(int index) => builder.build(
      context: _renderContext,
      index: index,
      codeLine: controller.codeLines[index],
    );

    void replace(int index, String text) {
      controller.codeLines = controller.codeLines.replaceLine(
        index,
        CodeLine(text),
      );
    }

    test('the text line takes its level\'s heading scale', () {
      open(['Title', '===', 'Sub', '---']);
      final base = _renderContext.style.fontSize!;
      expect(
        at(0)!.style!.fontSize,
        base * MarkdownConstants.editorHeaderScale(1),
      );
      expect(
        at(2)!.style!.fontSize,
        base * MarkdownConstants.editorHeaderScale(2),
      );
    });

    // C1 fix pass T7 — the front matter route is positional and checked
    // before the text memo, so lines a warm builder memoized as a rule and
    // as prose turn dim once the closer is typed, and back once it breaks.
    test('a front matter flips through a warm builder', () {
      final dim = _renderContext.baseColor.withValues(alpha: _dimAlpha);
      // A plain line the renderer declines builds no span at all.
      bool dimmed(int index) {
        final span = at(index);
        return span != null &&
            _visibleLeaves(span).every((leaf) => leaf.style?.color == dim);
      }

      open(['---', 'tags: a', 'body', 'more']);
      final rule = at(0);
      expect(dimmed(1), isFalse);

      replace(2, '---');
      expect(dimmed(0), isTrue);
      expect(dimmed(1), isTrue);
      expect(dimmed(2), isTrue);

      replace(1, 'tags a');
      expect(dimmed(1), isFalse);
      expect(
        at(1)!.style!.fontSize,
        _renderContext.style.fontSize! * MarkdownConstants.editorHeaderScale(2),
        reason: 'the broken property is a setext H2 over the old closer',
      );
      expect(at(0)?.toPlainText(), rule?.toPlainText());
    });

    test('the underline draws ─ for its markers, never concealed', () {
      open(['Title', '  ====  ']);
      final span = at(1)!;
      expect(span.toPlainText(), '  ────  ');
      expect(_concealedRuns(span), isEmpty);
    });

    test('the pair follows its neighbours through the positional memo', () {
      open(['Title', '===']);
      final heading = at(0)!;
      expect(identical(at(0), heading), isTrue, reason: 'memo hit');
      expect(at(1)!.toPlainText(), '───');

      replace(1, 'more prose');
      expect(at(0), isNull, reason: 'no underline, plain prose again');
      expect(at(1), isNull);

      replace(1, '===');
      expect(at(0)!.style!.fontSize, heading.style!.fontSize);

      replace(0, '- a');
      expect(at(1), isNull, reason: '=== under a list item is text');
    });

    test('the same text off a pair never reads the pair\'s memo', () {
      open(['Title', '===', 'Title', 'x']);
      expect(at(0), isNotNull);
      expect(at(2), isNull);
    });

    test('a fenced line is no text line, a fence close no underline', () {
      open(['```', 'Title', '===', '```', '===']);
      expect(
        at(1)!.style!.fontSize,
        isNot(
          _renderContext.style.fontSize! *
              MarkdownConstants.editorHeaderScale(1),
        ),
      );
      expect(at(2)?.toPlainText(), isNot(contains('─')));
      expect(at(4), isNull);
    });

    test('a line-led neighbour keeps --- a rule and === text', () {
      // The editor draws a `---` underline and a rule alike, so the text
      // line's own span is what tells a pair from a line-led neighbour.
      for (final above in const ['> quote', '> [!TIP] x', r'$= 500']) {
        open([above, 'x']);
        builder.configureMoney(_moneyEnabled);
        final alone = at(0);
        open([above, '---', above, '===']);
        builder.configureMoney(_moneyEnabled);
        expect(at(0), alone, reason: '$above takes no heading');
        expect(at(2), alone, reason: '$above takes no heading');
        expect(at(3), isNull, reason: '$above: === is prose');
      }
    });

    test('an underline at line 0 has no text line above it', () {
      open(['', '---']);
      final rule = at(1)!;
      open(['---', 'x']);
      expect(at(0), rule);
      open(['===', 'x']);
      expect(at(0), isNull);
    });

    test('a neighbour past the length guard cancels the pair', () {
      // The editor draws a line over the guard raw, so neither half of a
      // pair it belongs to is styled; the preview has no guard.
      open([
        'Title',
        '=' * (MarkdownEditorSpanBuilder.maxStyledLineLength + 1),
      ]);
      expect(at(0), isNull, reason: 'the text line stays prose');
      open([_longLine, '===']);
      expect(at(1), isNull, reason: 'the underline stays prose');
    });

    test('the caret line keeps the heading height', () {
      open(['Title', '===']);
      final off = at(0)!;
      final offUnderline = at(1)!;
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 2,
      );
      expect(at(0)!.style!.fontSize, off.style!.fontSize);
      controller.selection = const CodeLineSelection.collapsed(
        index: 1,
        offset: 1,
      );
      final on = at(1)!;
      expect(on.toPlainText(), '===', reason: 'raw markers on reveal');
      expect(on.style!.fontSize, offUnderline.style!.fontSize);
    });
  });

  group('money parse is memoised', () {
    test('parses once per distinct line text', () {
      final controller = CodeLineEditingController.fromText(
        _moneyMemoDocument.join('\n'),
      );
      addTearDown(controller.dispose);
      final builder = MarkdownEditorSpanBuilder()..bind(controller);
      builder.configureMoney(_moneyEnabled);

      TextSpan? buildAt(int index) => builder.build(
        context: _renderContext,
        index: index,
        codeLine: controller.codeLines[index],
      );

      for (final index in _moneyMemoRows) {
        final line = _moneyMemoDocument[index];
        final before = builder.debugMoneyParseCount;

        // Off-caret: the caret parks on the padding line 0.
        controller.selection = const CodeLineSelection.collapsed(
          index: 0,
          offset: 0,
        );
        final first = buildAt(index);
        expect(
          builder.debugMoneyParseCount,
          before + 1,
          reason: 'a first build must parse exactly once: $line',
        );

        final second = buildAt(index);
        expect(
          builder.debugMoneyParseCount,
          before + 1,
          reason: 'a repeat off-caret build must hit the parse memo: $line',
        );
        expect(
          identical(first, second),
          isTrue,
          reason: 'the span memo must still return one instance: $line',
        );

        // On the caret line the row renders raw and reparses through
        // [_buildLine] — same text, so still a memo hit.
        controller.selection = CodeLineSelection.collapsed(
          index: index,
          offset: 0,
        );
        buildAt(index);
        expect(
          builder.debugMoneyParseCount,
          before + 1,
          reason: 'a reveal build must hit the parse memo: $line',
        );
      }

      expect(
        builder.debugMoneyParseCount,
        _moneyMemoRows.length,
        reason: 'exactly one parse per distinct line text',
      );
    });
  });

  // The render context is the span memos' generation key: an equal one
  // must keep a warm cache (the page rebuilds it whenever the fork hands
  // over a new style instance), a different one must drop it.
  group('render context generation', () {
    // S2 C16 — the quote bars' ground is resolved once per generation, so
    // a quote line's build allocates no style for it.
    test('the quote bar ground is one instance per generation', () {
      final cache = EditorSpanCache();
      final ground = cache.quoteBarGround(_renderContext);
      expect(identical(cache.quoteBarGround(_renderContext), ground), isTrue);
      expect(
        ground.fontWeight,
        _renderContext.style.fontWeight ?? FontWeight.normal,
      );
      final bold = EditorRenderContext(
        style: _renderContext.style.copyWith(fontWeight: FontWeight.bold),
        baseColor: _renderContext.baseColor,
        primary: _renderContext.primary,
        isDark: _renderContext.isDark,
      );
      expect(identical(cache.quoteBarGround(bold), bold.style), isTrue);
    });

    // C1 fix pass C7 / T5 — through the builder: two quote lines' bars
    // share one style per accent, so a line's build copies none.
    test('quote lines share one bar style per accent and generation', () {
      final controller = CodeLineEditingController.fromText(
        ['> one', '> two words', '> [!TIP] t', '> body', _pad].join('\n'),
      );
      addTearDown(controller.dispose);
      final builder = MarkdownEditorSpanBuilder()..bind(controller);
      builder.configureMoney(MoneyDisplayConfig.disabled);
      controller.selection = const CodeLineSelection.collapsed(
        index: 4,
        offset: 0,
      );
      TextStyle? barOf(int index) => _visibleLeaves(
        builder.build(
          context: _renderContext,
          index: index,
          codeLine: controller.codeLines[index],
        )!,
      ).firstWhere((leaf) => leaf.text.contains('┃')).style;

      expect(identical(barOf(0), barOf(1)), isTrue);
      expect(identical(barOf(2), barOf(3)), isTrue);
      expect(identical(barOf(0), barOf(2)), isFalse, reason: 'own accent');
    });

    test('an equal context keeps the memos, a different one drops them', () {
      final cache = EditorSpanCache();
      expect(cache.renderContext, isNull);
      expect(cache.adoptContext(_renderContext), isTrue);

      final same = EditorRenderContext(
        style: _renderContext.style,
        baseColor: _renderContext.baseColor,
        primary: _renderContext.primary,
        isDark: _renderContext.isDark,
      );
      expect(same, _renderContext);
      expect(
        cache.adoptContext(same),
        isFalse,
        reason: 'an equal generation must not clear a warm cache',
      );

      final darker = EditorRenderContext(
        style: _renderContext.style,
        baseColor: _renderContext.baseColor,
        primary: _renderContext.primary,
        isDark: true,
      );
      expect(cache.adoptContext(darker), isTrue);
      expect(cache.renderContext, darker);
    });

    test('a rebuilt but value-equal theme reuses the cached context', () {
      // A surface whose ancestor builds `ThemeData(...)` inside its own
      // `build()` hands the cache a fresh instance every frame. Identity
      // cannot absorb that, so the value comparison has to — otherwise
      // the span memos are dropped on every layout pass.
      final cache = EditorRenderContextCache();
      final first = cache.of(_freshTheme(), _baseStyle);
      final second = cache.of(_freshTheme(), _baseStyle);

      expect(
        identical(_freshTheme(), _freshTheme()),
        isFalse,
        reason: 'the fixture must hand over two distinct instances',
      );
      expect(
        identical(second, first),
        isTrue,
        reason: 'a value-equal generation must reuse the cached instance',
      );

      final dark = cache.of(
        ThemeData(useMaterial3: true, brightness: Brightness.dark),
        _baseStyle,
      );
      expect(identical(dark, first), isFalse);
      expect(
        identical(cache.of(_freshTheme(), _baseStyle), first),
        isFalse,
        reason: 'the cache holds one generation, not a history of them',
      );
    });

    test('a rebuilt but equal context keeps the identical span', () {
      final controller = CodeLineEditingController.fromText(
        <String>[_pad, '- **bold** item', _pad].join('\n'),
      );
      addTearDown(controller.dispose);
      final builder = MarkdownEditorSpanBuilder()..bind(controller);
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 0,
      );
      final first = builder.build(
        context: _renderContext,
        index: 1,
        codeLine: controller.codeLines[1],
      );
      final second = builder.build(
        context: EditorRenderContext.fromTheme(
          ThemeData(useMaterial3: true, brightness: Brightness.light),
          _baseStyle,
        ),
        index: 1,
        codeLine: controller.codeLines[1],
      );
      expect(first, isNotNull);
      expect(
        identical(first, second),
        isTrue,
        reason: 'an equal generation must hit the span memo',
      );
    });
  });

  group('code chips and hanging quotes', () {
    final base = _renderContext.style.fontSize!;
    final codeSize = base * MarkdownConstants.inlineCodeScale;

    TextSpan lineOf(List<String> lines, int index, {required int caretLine}) {
      final controller = CodeLineEditingController.fromText(lines.join('\n'));
      addTearDown(controller.dispose);
      final builder = MarkdownEditorSpanBuilder()..bind(controller);
      builder.configureMoney(MoneyDisplayConfig.disabled);
      controller.selection = CodeLineSelection.collapsed(
        index: caretLine,
        offset: 0,
      );
      final span = builder.build(
        context: _renderContext,
        index: index,
        codeLine: controller.codeLines[index],
      );
      expect(span, isNotNull, reason: lines[index]);
      return span!;
    }

    test('inline code is monospace at the code scale inside its chip', () {
      final render = _renderOffCaret('a `code()` b');
      final chipped = render.leaves
          .where((leaf) => leaf.span is CodeDecoratedTextSpan)
          .toList();
      expect(chipped.map((leaf) => leaf.text).join(), 'code()');
      for (final leaf in chipped) {
        expect(leaf.style?.fontFamily, 'monospace');
        expect(leaf.style?.fontSize, codeSize);
      }
      expect(
        render.span.style?.fontSize,
        base,
        reason: 'the root keeps the strut',
      );
      expect(render.span.style?.fontFamily, _renderContext.style.fontFamily);
    });

    test('a ghost inside a code span keeps the prose font', () {
      final render = _renderOffCaret('`a {{b}} c` d');
      final ghost = render.leaves.firstWhere((leaf) => leaf.text == 'b');
      expect(ghost.style?.fontFamily, isNot('monospace'));
      expect(ghost.span, isNot(isA<CodeDecoratedTextSpan>()));
    });

    test('fence delimiters and interior sit on the code chip at the code '
        'scale, the root at the line style in both reveal states', () {
      final lines = ['```dart', 'final x = 1;', '```', _pad];
      for (final index in [0, 1, 2]) {
        for (final caretLine in [index, 3]) {
          final span = lineOf(lines, index, caretLine: caretLine);
          expect(span.style, _renderContext.style, reason: lines[index]);
          final leaves = _visibleLeaves(span);
          expect(leaves, isNotEmpty);
          for (final leaf in leaves) {
            expect(leaf.span, isA<CodeDecoratedTextSpan>(), reason: leaf.text);
            expect(leaf.style?.fontFamily, 'monospace');
            expect(leaf.style?.fontSize, codeSize);
          }
        }
      }
    });

    test('a block comment keeps the prose font and no chip', () {
      final span = lineOf(['%%', 'hidden', '%%', _pad], 1, caretLine: 3);
      for (final leaf in _visibleLeaves(span)) {
        expect(leaf.span, isNot(isA<CodeDecoratedTextSpan>()));
        expect(leaf.style?.fontFamily, isNot('monospace'));
      }
    });

    test('a 200-character quote line hangs at its content start in both '
        'reveal states', () {
      final words = List.filled(40, 'reps').join(' ');
      final line = '> ${words.substring(0, 198)}';
      expect(line.length, 200);
      final pair = _renderBothStates(line, money: false);
      for (final render in [pair.off, pair.on]) {
        expect(render.span, isA<CodeHangingTextSpan>());
        expect((render.span as CodeHangingTextSpan).hangingChars, 2);
        expect(render.span.style, _renderContext.style);
      }
      expect(pair.off.visibleText.length, line.length);
    });

    test('nested quotes and callouts hang past every bar', () {
      final nested = _renderOffCaret('> > second level');
      expect((nested.span as CodeHangingTextSpan).hangingChars, 4);
      final lead = _renderOffCaret('> [!NOTE] Warm-up first');
      expect((lead.span as CodeHangingTextSpan).hangingChars, 2);
      final body = _renderOffCaret(
        '> keep the elbows in',
        above: const <String>['> [!TIP] Form'],
      );
      expect((body.span as CodeHangingTextSpan).hangingChars, 2);
    });

    test('a quoted heading hangs past the bar at the heading scale in both '
        'reveal states', () {
      const line = '> ## Warm-up sets before the working weight';
      final pair = _renderBothStates(line, money: false);
      for (final render in [pair.off, pair.on]) {
        final span = render.span as CodeHangingTextSpan;
        expect(span.hangingChars, 2);
        expect(
          span.style?.fontSize,
          greaterThan(_renderContext.style.fontSize!),
          reason: 'the root keeps the heading style the line height reads',
        );
      }
      expect(pair.off.span.toPlainText().length, line.length);
      // An unquoted heading has no bars to hang past.
      expect(
        _renderOffCaret('## Warm-up').span,
        isNot(isA<CodeHangingTextSpan>()),
      );
    });

    test('the fork lays the real quote spans out hanging past the bar', () {
      final words = List.filled(40, 'reps').join(' ').substring(0, 198);
      final pair = _renderBothStates('> $words', money: false);
      final renders = <String, _Render>{
        'quote, concealed': pair.off,
        'quote, revealed': pair.on,
        'callout lead': _renderOffCaret('> [!NOTE] $words'),
        'callout body': _renderOffCaret(
          '> $words',
          above: const <String>['> [!TIP] Form'],
        ),
        'no blank after the bar': _renderOffCaret('>$words'),
        'quoted heading': _renderOffCaret('> ## $words'),
      };
      for (final MapEntry(key: name, value: render) in renders.entries) {
        final span = render.span as CodeHangingTextSpan;
        final provider = CodeParagraphProviderForTesting()
          ..updateBaseStyle(_renderContext.style);
        final paragraph = provider.build(span, 240);
        expect(provider.isHanging(paragraph), isTrue, reason: name);
        expect(paragraph.lineCount, greaterThan(1), reason: name);
        expect(
          provider.markerCacheContains(
            provider.truncate(span, span.hangingChars),
          ),
          isTrue,
          reason: '$name: the bar prefix is a one-line marker',
        );
        final rects = paragraph.getRangeRects(
          TextRange(start: span.hangingChars, end: paragraph.length),
        );
        final indent = rects.first.left;
        expect(indent, greaterThan(0), reason: name);
        for (final rect in rects) {
          expect(rect.left, greaterThanOrEqualTo(indent - 0.5), reason: name);
        }
      }
    });

    test('a quote line with no content does not hang', () {
      expect(_renderOffCaret('> ').span, isNot(isA<CodeHangingTextSpan>()));
    });
  });
}

const String _pad = 'padding line';

/// Two checkpoints so every display row below has a balance, a net
/// change and a `$~` window to compute.
const List<String> _moneyMemoDocument = <String>[
  _pad,
  r'$= 500',
  r'$= 700',
  r'$$ total',
  r'$? net change',
  r'$+ 50 coffee',
  r'$~ 2 teal: Change: $',
  r'$5 coffee',
  _pad,
];

/// The rows built by the memo tests: two balance-keyed display rows, a
/// purely textual op row, a display row with an accent and a value slot,
/// and a line that leads with `$` without being money at all.
const List<int> _moneyMemoRows = <int>[3, 4, 5, 6, 7];

const TextStyle _baseStyle = TextStyle(
  fontSize: 16.0,
  height: 1.4,
  color: Color(0xFF202124),
);

/// The renderer's theme generation, built straight from a [ThemeData] —
/// the whole point of [EditorRenderContext] is that no widget tree is
/// needed to render a line.
final EditorRenderContext _renderContext = EditorRenderContext.fromTheme(
  ThemeData(useMaterial3: true, brightness: Brightness.light),
  _baseStyle,
);

const MoneyDisplayConfig _moneyEnabled = MoneyDisplayConfig(
  enabled: true,
  currencySymbol: 'lei',
  currencySuffix: true,
);

/// Every rendered code unit that is allowed to differ from its source
/// unit, mapped to the source characters it may stand in for. Each entry
/// is a documented 1:1 substitution in
/// `lib/utils/markdown_editor_span_builder.dart`.
const Map<int, String> _substitutions = <int, String>{
  0x2022: '-*+•', // • — list bullet (and a money row's list marker)
  0x25E6: '-*+•', // ◦ — the same bullet one nesting level deeper
  0x25AA: '-*+•', // ▪ — and two levels deeper (the cycle wraps at three)
  0x2503: '>', // ┃ — blockquote bar
  // ─ — horizontal rule, the blanks between markers too; a setext
  // underline's `=` / `-` run
  0x2500: '-*_ \t=',
  0x03A3: r'$', // Σ — `$$` total marker with a value slot
  0x25CE: '!', // ◎ — `$!` marker, and the `$!` target op glyph
  0x0394: '?^~', // Δ — `$?` / `$^` / `$~` markers with a value slot
  0x2212: '-', // − — `$-` op glyph
  0x00D7: '*&', // × — `$*` op glyph, and `&times;`
  0x00F7: '/', // ÷ — `$/` op glyph
  // an HTML entity's `&` shows its decoded character (the corpus's)
  0x00A9: '&', // © — `&copy;`, `&#169;`
  0x2014: '&', // — — `&mdash;`, `&#x2014;`
  0x00A0: '&', // no-break space — `&nbsp;`
  0x003C: '&', // < — `&lt;`
  0x0021: r'$', // ! — money error row marker
  0x25A3: '!', // ▣ — an image's or an embed's `!` (the picture glyph)
  // placeholder run — checkbox (off-caret, and on the caret line while
  // the caret is past the marker), money chip, op glyph
  0xFFFC: r'[$?^~!:',
};

/// The one substitution [_substitutions] cannot list, because it maps
/// letters to letters: a titleless callout lead paints its type word
/// title-cased over the word's own units (`[!WARNING]` reads `Warning`).
/// Allowed at offset [i] only as a case change of a unit inside the word
/// between `[!` and `]`, on a lead with nothing but a fold marker after
/// the token. Located here without the parser, so the code-unit check
/// never takes the renderer's own label as its expectation.
bool _isLabelCaseMap(String source, int i, int want, int got) {
  final open = source.indexOf('[!');
  if (open < 0) return false;
  final close = source.indexOf(']', open + 2);
  if (close < 0 || i < open + 2 || i >= close) return false;
  var after = source.substring(close + 1);
  if (after.startsWith('-') || after.startsWith('+')) {
    after = after.substring(1);
  }
  if (after.trim().isNotEmpty) return false;
  final w = String.fromCharCode(want);
  final g = String.fromCharCode(got);
  return g == w.toUpperCase() || g == w.toLowerCase();
}

/// One visible piece of a built line: a text leaf that is not concealed,
/// or a placeholder run (a checkbox, a money chip, an op glyph).
class _Leaf {
  final String text;
  final TextStyle? style;
  final InlineSpan span;

  const _Leaf(this.text, this.style, this.span);
}

typedef _Render = ({TextSpan span, List<_Leaf> leaves, String visibleText});

/// One line rendered in both reveal states: `off` with the caret
/// elsewhere (markers concealed), `on` with the caret on the line.
typedef _RevealPair = ({_Render off, _Render on});

/// Builds [line] off-caret (the caret parks on the padding line 0, or a
/// collapsed selection would reveal the line under test) and projects the
/// span tree down to what the reader actually sees. A fresh builder per
/// call, because `configureMoney` clears the memos of a warm one.
_Render _renderOffCaret(
  String line, {
  List<String> above = const <String>[],
  bool money = false,
}) {
  final document = <String>[_pad, ...above, line, _pad];
  final index = 1 + above.length;
  final controller = CodeLineEditingController.fromText(document.join('\n'));
  addTearDown(controller.dispose);
  final builder = MarkdownEditorSpanBuilder()..bind(controller);
  builder.configureMoney(money ? _moneyEnabled : MoneyDisplayConfig.disabled);
  controller.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);
  final span = builder.build(
    context: _renderContext,
    index: index,
    codeLine: controller.codeLines[index],
  );
  expect(span, isNotNull, reason: 'expected a styled span for: $line');
  final leaves = _visibleLeaves(span!);
  return (
    span: span,
    leaves: leaves,
    visibleText: leaves.map((leaf) => leaf.text).join(),
  );
}

/// A freshly constructed light theme, value-equal to the one behind
/// [_renderContext] and never identical to another call's result — the
/// shape an ancestor that builds its `ThemeData(...)` inside `build()`
/// hands to [EditorRenderContextCache] on every frame.
ThemeData _freshTheme() =>
    ThemeData(useMaterial3: true, brightness: Brightness.light);

/// The same [line] built twice with one builder: once with the caret
/// parked on the padding line (concealed markers) and once with it on
/// the line itself (reveal). One builder for both, so the reveal build
/// cannot be answered out of the memo the off-caret build filled.
_RevealPair _renderBothStates(
  String line, {
  List<String> above = const <String>[],
  bool money = true,
}) {
  final document = <String>[_pad, ...above, line, _pad];
  final index = 1 + above.length;
  final controller = CodeLineEditingController.fromText(document.join('\n'));
  addTearDown(controller.dispose);
  final builder = MarkdownEditorSpanBuilder()..bind(controller);
  builder.configureMoney(money ? _moneyEnabled : MoneyDisplayConfig.disabled);

  _Render at(int caretLine) {
    controller.selection = CodeLineSelection.collapsed(
      index: caretLine,
      offset: 0,
    );
    final span = builder.build(
      context: _renderContext,
      index: index,
      codeLine: controller.codeLines[index],
    );
    expect(span, isNotNull, reason: 'expected a styled span for: $line');
    final leaves = _visibleLeaves(span!);
    return (
      span: span,
      leaves: leaves,
      visibleText: leaves.map((leaf) => leaf.text).join(),
    );
  }

  return (off: at(0), on: at(index));
}

/// The colour a money row paints [label] in — its `labelStyle`, which
/// carries the row's accent on both surfaces.
Color? _labelColour(_Render render, String label) => render.leaves
    .firstWhere(
      (leaf) => leaf.text.trim() == label,
      orElse: () =>
          throw StateError('no "$label" leaf in: ${render.visibleText}'),
    )
    .style
    ?.color;

/// The colour of a quote/callout line's first `┃` bar — grey for a plain
/// quote, the block's accent inside a callout.
Color? _barColour(TextSpan span) =>
    _visibleLeaves(span).firstWhere((leaf) => leaf.text == '┃').style?.color;

/// Mirrors `MarkdownEditorSpanBuilder._tablePipeAlpha`: a table row's `|`
/// separators are the primary colour at this alpha.
const double _tablePipeAlpha = 0.55;

/// Mirrors `MarkdownEditorSpanBuilder._ruleAlpha`: the tone a horizontal
/// rule and a table delimiter row render in.
const double _ruleAlpha = 0.3;

/// Mirrors `EditorSpanEmitter.dimAlpha`: the tone a marker renders in on
/// a reveal (caret) line, where it is present but receding rather than
/// concealed.
const double _dimAlpha = 0.45;

/// A marker span: transparent and shrunk to a 0.01 font size, which is
/// exactly what the builder's `_concealStyle` produces.
bool _concealed(TextStyle? style) =>
    style != null &&
    style.color == const Color(0x00000000) &&
    style.fontSize == 0.01;

/// The text of every concealed run in [root], in document order — the
/// counterpart of [_visibleLeaves] for the invariants that are about
/// what a line *hides*. Each run is emitted whole (`emitChrome` appends
/// one span per marker range), so the list reads as the markers
/// themselves rather than as code units.
List<String> _concealedRuns(InlineSpan root) {
  final runs = <String>[];
  void walk(InlineSpan span) {
    if (span is TextSpan) {
      final text = span.text;
      if (text != null && text.isNotEmpty && _concealed(span.style)) {
        runs.add(text);
      }
      span.children?.forEach(walk);
    }
  }

  walk(root);
  return runs;
}

/// The off-caret span for [line], `null` included. A line the builder
/// declines renders as plain source through the page's own fallback,
/// which is the assertion for every construct the grammar refuses.
TextSpan? _buildOffCaret(String line) {
  final controller = CodeLineEditingController.fromText(
    <String>[_pad, line, _pad].join('\n'),
  );
  addTearDown(controller.dispose);
  final builder = MarkdownEditorSpanBuilder()..bind(controller);
  builder.configureMoney(MoneyDisplayConfig.disabled);
  controller.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);
  return builder.build(
    context: _renderContext,
    index: 1,
    codeLine: controller.codeLines[1],
  );
}

List<_Leaf> _visibleLeaves(InlineSpan root) {
  final leaves = <_Leaf>[];
  void walk(InlineSpan span) {
    if (span is TextSpan) {
      final text = span.text;
      if (text != null && text.isNotEmpty && !_concealed(span.style)) {
        leaves.add(_Leaf(text, span.style, span));
      }
      final children = span.children;
      if (children != null) {
        for (final child in children) {
          walk(child);
        }
      }
    } else if (span is PlaceholderSpan) {
      leaves.add(_Leaf('￼', span.style, span));
    }
  }

  walk(root);
  return leaves;
}

void _expectCodeUnits(
  String source,
  InlineSpan span,
  String where, {
  List<String> above = const <String>[],
}) {
  // Only a line under no quote line can open a callout block, so only
  // there may the type word's case map apply (F10 e: a token on a body
  // line is body text).
  final leadLine = above.isEmpty || !above.last.trimLeft().startsWith('>');
  final plain = span.toPlainText(includePlaceholders: true);
  expect(
    plain.length,
    source.length,
    reason:
        'code-unit count changed: $where\n'
        '  source: ${_visible(source)}\n'
        '  render: ${_visible(plain)}',
  );
  if (plain.length != source.length) return;
  for (var i = 0; i < source.length; i++) {
    final want = source.codeUnitAt(i);
    final got = plain.codeUnitAt(i);
    if (want == got) continue;
    if (leadLine && _isLabelCaseMap(source, i, want, got)) continue;
    final allowed = _substitutions[got];
    expect(
      allowed != null && allowed.codeUnits.contains(want),
      isTrue,
      reason:
          'undocumented substitution at offset $i '
          '(U+${want.toRadixString(16).padLeft(4, '0').toUpperCase()} -> '
          'U+${got.toRadixString(16).padLeft(4, '0').toUpperCase()}): $where\n'
          '  source: ${_visible(source)}\n'
          '  render: ${_visible(plain)}',
    );
    // The rule row lists the blanks for spaced rules only: a blank drawn
    // as `─` on any other line is a stray substitution.
    if (got == 0x2500 && (want == 0x20 || want == 0x09)) {
      expect(
        MarkdownLineShape.isHorizontalRule(source),
        isTrue,
        reason:
            'a blank drawn as a rule glyph off a rule at offset $i: $where\n'
            '  source: ${_visible(source)}\n'
            '  render: ${_visible(plain)}',
      );
    }
  }
}

String _visible(String s) => s
    .replaceAll('\t', '\\t')
    .replaceAll('\u0000', '\\0')
    .replaceAll('￼', '<box>');

class _Case {
  final String label;
  final String line;
  final List<String> above;
  final List<String> below;

  const _Case(
    this.label,
    this.line, {
    this.above = const <String>[],
    this.below = const <String>[],
  });
}

final String _longLine =
    'x' * (MarkdownEditorSpanBuilder.maxStyledLineLength + 1);

final List<_Case> _corpus = <_Case>[
  // Headings H1-H6 plus the divergences named in the review's §1.3 table.
  const _Case('h1', '# Heading one'),
  const _Case('h2', '## Heading two'),
  const _Case('h3', '### Heading three'),
  const _Case('h4', '#### Heading four'),
  const _Case('h5', '##### Heading five'),
  const _Case('h6', '###### Heading six'),
  const _Case('h7 is not a heading', '####### Seven hashes'),
  const _Case('hashes with no trailing space', '###'),
  const _Case('indented heading', '  ## Indented heading'),
  const _Case('heading with inline runs', '## **Bold** and `code` #tag'),
  const _Case('inline code inside a heading', '## a `code` b'),
  const _Case('closing hashes', '## Week 3 ##'),
  const _Case('closing hashes with trailing blanks', '### Title   ###  '),
  const _Case('glued closing hashes', '## Title##'),
  const _Case('only closing hashes', '## ##'),
  // Setext pairs: each line positional on the other.
  const _Case('setext h1 text', 'Title', below: <String>['===']),
  const _Case('setext h2 text', 'Sub', below: <String>['---']),
  const _Case(
    'setext text with inline runs',
    '**Big** `x` #t',
    below: <String>['===='],
  ),
  const _Case('setext h1 underline', '===', above: <String>['Title']),
  const _Case('setext h2 underline', '---', above: <String>['Sub']),
  const _Case(
    'setext underline indented',
    '   ====  ',
    above: <String>['Title'],
  ),
  const _Case('--- under a list item is a rule', '---', above: <String>['- a']),
  const _Case('--- under a heading is a rule', '---', above: <String>['# H']),
  const _Case(
    '=== under a fence is text',
    '===',
    above: <String>['```', 'x', '```'],
  ),

  // Emphasis / code / strike / highlight.
  const _Case('bold', 'a **bold** b'),
  const _Case('italic asterisk', 'a *italic* b'),
  const _Case('bold underscore', 'a __bold__ b'),
  const _Case('italic underscore', 'a _italic_ b'),
  const _Case('bold italic', 'a ***both*** b'),
  const _Case('triple underscore', 'a ___both___ b'),
  const _Case('strikethrough', 'a ~~gone~~ b'),
  const _Case('highlight plain', 'a ==marked== b'),
  const _Case('highlight named', 'a ==teal:marked== b'),
  const _Case('highlight unresolved name', 'a ==note: see below== b'),
  const _Case('inline code', 'a `code()` b'),
  const _Case('double backtick code', 'a ``x`y`` b'),
  const _Case('overlapping emphasis', '*a **b** c*'),
  const _Case('snake case is not emphasis', 'some_variable_name here'),
  const _Case('spaced asterisks stay plain', '2 * 3 * 4 = 24'),

  // Colours.
  const _Case('coloured text', 'a {red:danger} b'),
  const _Case('unresolved colour name', 'a {note:danger} b'),
  const _Case('nested colour in bold', '**bold {blue:inner} tail**'),

  // Links.
  const _Case('inline link', 'see [the docs](https://example.com/a) now'),
  const _Case('bare https url', 'see https://example.com/a now'),
  const _Case('bare www url', 'see www.example.com/a now'),
  const _Case(
    'image chrome behind the picture glyph',
    '![alt](https://example.com/a.png)',
  ),
  const _Case('image mid line with a title', 'a ![x](u "t") b'),
  const _Case('image with an empty alt', 'a ![](https://x.y/a.png) b'),
  const _Case('link inside emphasis', '*see [docs](https://example.com)*'),
  const _Case('link with a title', '[t](https://x.com/s "Guide")'),
  const _Case(
    'link with balanced parens',
    '[w](https://en.wikipedia.org/wiki/Foo_(bar)) x',
  ),
  const _Case('link with an angle destination', '[t](<a b>)'),
  const _Case(
    'bare url with balanced parens',
    'https://en.wikipedia.org/wiki/Squat_(exercise).',
  ),
  const _Case('angle autolink', 'see <https://x.y> now'),
  const _Case('angle email autolink', '<me@example.com>'),
  const _Case('angle brackets around prose', 'a <b> c'),

  // Wiki links: `[[` and `]]` conceal like a link's brackets, the title
  // is literal, and every shape the grammar refuses has to survive as
  // raw source — the four bracket units are never dropped either way.
  const _Case('wiki link alone', '[[a]]'),
  const _Case('wiki link in prose', 'see [[Squat Progression]] now'),
  const _Case('wiki link with a padded title', '[[ a ]]'),
  const _Case('wiki link inside bold', '**[[a]]**'),
  const _Case('wiki link inside italic prose', '*x [[a]] y*'),
  const _Case('wiki link inside a colour run', 'a {red:[[note]]} b'),
  const _Case('wiki link inside a highlight', '==[[a]]=='),
  const _Case('wiki link inside strikethrough', '~~[[a]]~~'),
  const _Case('two adjacent wiki links', '[[a]][[b]]'),
  const _Case('wiki link tight against a ghost', '[[a]]{{g}}'),
  const _Case('wiki link beside a link and a tag', '[[a]] and [b](c) and #t'),
  const _Case('wiki link followed by parens', '[[a]](b)'),
  const _Case('embed before a wiki link', '![[a]]'),
  const _Case('aliased wiki link', '[[a|b]]'),
  const _Case('aliased embed', 'x ![[a|b]] y'),
  const _Case('wiki link with a blank alias', '[[a| ]]'),
  const _Case('a second pipe is literal', '[[a|b|c]]'),
  const _Case('a ghost in the title is literal', '[[a {{g}} b]]'),
  const _Case('escaped wiki open is literal', r'\[[a]]'),
  const _Case('wiki link inside a code span is literal', '`[[a]]`'),
  const _Case('emphasis markers in a title are raw', '[[**a**]]'),
  const _Case('a hash in a title is raw', '[[#tag]]'),
  const _Case('a url in a title is raw', '[[https://a.com]]'),
  const _Case('a third bracket stays literal text', '[[a]]]'),
  const _Case('a leading third bracket stays literal text', '[[[a]]]'),
  const _Case('an empty title is literal', '[[]]'),
  const _Case('a blank title is literal', '[[ ]]'),
  const _Case('wiki link in a heading', '# [[a]]'),
  const _Case('wiki link in a bullet', '- [[a]]'),
  const _Case('wiki link in a task item', '- [ ] [[a]]'),
  const _Case('wiki link in a quote', '> [[a]]'),
  const _Case('wiki link in a table row', '| [[a]] |'),
  const _Case('wiki link in a money label', r'$+ 50 [[groceries]]'),
  _Case(
    'wiki link in a bulleted money label',
    r'- $$ [[a]]',
    above: const <String>[r'$= 500'],
  ),
  const _Case('wiki link in a callout title', '> [!TIP] [[a]]'),
  _Case(
    'wiki link in a callout body',
    '> see [[a]]',
    above: const <String>['> [!TIP] x'],
  ),
  _Case('wiki link inside a fence', '[[a]]', above: const <String>['```']),

  // Tags.
  const _Case('tag', 'lifting #legs today'),
  const _Case('nested tag', 'lifting #gym/legs today'),
  const _Case('nested digit-led tag', 'run #program/5x5 today'),
  const _Case('digit-led tags', 'did #5x5 and #1rm'),
  const _Case('all-digit hash is not a tag', 'set #123 done'),
  const _Case('hash mid word is not a tag', 'issue no#42 today'),

  // Quotes, callouts, rules.
  const _Case('quote', '> a quoted line'),
  const _Case('indented quote', '  > an indented quote'),
  const _Case('callout lead', '> [!TIP] Rest between sets'),
  const _Case('callout continuation', '> body of the callout'),

  // Callout leads: every recognised type, then the spacing shapes the
  // grammar accepts and the ones it refuses.
  const _Case('callout lead note', '> [!NOTE] Take it easy'),
  const _Case('callout lead tip', '> [!TIP] Rest between sets'),
  const _Case('callout lead important', '> [!IMPORTANT] Brace first'),
  const _Case('callout lead warning', '> [!WARNING] Knees out'),
  const _Case('callout lead caution', '> [!CAUTION] Belt on'),
  const _Case('callout lead success', '> [!SUCCESS] Every set hit'),
  const _Case('callout lead pr', '> [!PR] New best'),
  const _Case('callout lead with no title', '> [!TIP]'),
  const _Case('callout lead with two spaces', '>  [!TIP] x'),
  const _Case('callout lead with no space', '>[!TIP] x'),
  // F9 fold markers, F10 default titles, aliases, new kinds, unknown words.
  const _Case('callout lead folded with a title', '> [!WARNING]- Knee'),
  const _Case('callout lead unfolded with a title', '> [!TIP]+ title'),
  const _Case('callout lead folded with no title', '> [!TIP]-'),
  const _Case('callout lead with a spaced dash title', '> [!TIP] - x'),
  const _Case('callout lead alias', '> [!hint]'),
  const _Case('callout lead new kind', '> [!bug] Squeaky knee'),
  const _Case('callout lead unknown word', '> [!drill]'),
  const _Case('callout lead spaced word', '> [! tip ]'),
  const _Case('callout lead spaced kind', '> [! pr ]'),
  const _Case('callout lead non-ASCII word', '> [!ßtraße]'),
  const _Case('indented callout lead folded', '  > [!WARNING]-'),
  const _Case('quoted linked badge', '> [![a](u)](l)'),
  const _Case('quote with a two-word token', '> [!two words] x'),
  _Case(
    'callout body with a foreign token',
    '> [!NOTE] y',
    above: const <String>['> [!TIP] x'],
  ),
  _Case(
    'callout body with a titleless foreign token',
    '> [!NOTE]',
    above: const <String>['> [!TIP] x'],
  ),
  const _Case('quoted bullet after a tab', '>\t- squat'),
  const _Case('quoted task after a tab', '>\t- [ ] warm-up'),
  // F15 lists, tasks and headings past the `>` run.
  const _Case('quoted task', '> - [ ] warm-up'),
  const _Case('quoted ticked task', '> - [x] warm-up'),
  const _Case('quoted bullet', '> - squat'),
  const _Case('quoted nested bullet', '>   - deep'),
  const _Case('quoted ordered item', '> 1. bench'),
  const _Case('quoted heading', '> # Week 3'),
  const _Case('nested quoted bullet', '> > - inner'),
  _Case(
    'quoted task in a callout body',
    '> - [ ] warm-up',
    above: const <String>['> [!TODO] Today'],
  ),
  _Case(
    'quoted heading in a callout body',
    '> ## Legs',
    above: const <String>['> [!NOTE] x'],
  ),
  _Case('callout body', '> body', above: const <String>['> [!TIP] x']),
  _Case(
    'nested lead is body text',
    '> [!NOTE] inner',
    above: const <String>['> [!TIP] x'],
  ),
  _Case(
    'callout body at quote depth 2',
    '>> deeper',
    above: const <String>['> [!TIP] x'],
  ),
  _Case(
    'callout body that is only a marker',
    '>',
    above: const <String>['> [!TIP] x'],
  ),
  // Exotic leading whitespace: a blockquote line to the grammar, so it
  // renders bars — and the indent unit itself must survive.
  _Case(
    'callout body indented with a no-break space',
    ' > body',
    above: const <String>['> [!TIP] x'],
  ),
  const _Case('form-feed indented quote', '> quoted'),
  const _Case('nested quote depth 3', '>>> deep'),
  const _Case('nested quote depth 3 spaced', '> > > deep'),
  const _Case('empty quote', '>'),

  // Callout leads composed with the inline constructs.
  const _Case('callout lead with a ghost', '> [!TIP] {{ rest }} between sets'),
  const _Case('callout lead with a tag', '> [!TIP] rest #legs'),
  const _Case('callout lead with a money row', r'> [!TIP] $+ 5 snack'),
  _Case(
    'callout body with a ghost',
    '> keep {{ what }} loose',
    above: const <String>['> [!TIP] x'],
  ),
  const _Case('rule dashes', '---'),
  const _Case('rule asterisks', '***'),
  const _Case('rule underscores', '_____'),
  const _Case('rule with trailing space', '---  '),
  const _Case('spaced rule dashes', '- - -'),
  const _Case('spaced rule asterisks', '* * *'),
  const _Case('spaced rule underscores', '_ _ _'),
  const _Case('mixed-spacing rule', '  -  --\t-'),

  // Lists and tasks.
  const _Case('bullet dash', '- squat'),
  const _Case('bullet star', '* squat'),
  const _Case('bullet plus', '+ squat'),
  const _Case('nested bullet', '  - deeper'),
  const _Case('double nested bullet', '    - deepest'),

  // The bullet glyph cycles •/◦/▪ with the item's nesting level and
  // wraps at three, so every depth is a 1:1 substitution of one marker
  // code unit for one glyph code unit.
  const _Case('bullet at depth 0', '- a'),
  const _Case('bullet at depth 1', '  - a'),
  const _Case('bullet at depth 2', '    - a'),
  const _Case('bullet at depth 3 wraps', '      - a'),
  const _Case('source bullet glyph at depth 1', '  • a'),
  const _Case('ordered dot', '1. first'),
  const _Case('ordered paren', '2) second'),
  const _Case('task unchecked', '- [ ] warm up'),
  const _Case('task checked', '- [x] warm up'),
  _Case(
    'task indeterminate parent',
    '- [ ] parent',
    below: const <String>['  - [x] done child', '  - [ ] open child'],
  ),
  const _Case('task cancelled', '- [-] skipped'),
  const _Case('task in progress', '- [/] halfway'),
  const _Case('task forwarded', '* [>] next week'),
  const _Case('task scheduled', '- [<] booked'),
  const _Case('task question', '- [?] maybe'),
  const _Case('task important', '- [!] knee'),
  const _Case('task star', '- [*] pr'),
  const _Case('task any other unit', '- [y] yes'),
  const _Case('task custom state, empty', '- [-]'),
  const _Case('quoted task cancelled', '> - [-] skipped'),
  _Case(
    'task cancelled parent over mixed children',
    '- [-] parent',
    below: const <String>['  - [x] done child', '  - [ ] open child'],
  ),
  const _Case('list with inline runs', '- **heavy** `3x5` #legs'),

  // Empty list items — the shape Enter-continuation leaves behind. The
  // marker still renders, but there is no content paragraph to hang
  // under, so the root must stay a plain span.
  const _Case('bullet with no content', '- '),
  const _Case('bullet star with no content', '* '),
  const _Case('ordered dot with no content', '1. '),
  const _Case('ordered paren with no content', '1) '),
  const _Case('task with no content', '- [ ] '),

  // Ghost text, on its own and composed.
  const _Case('ghost alone', 'hello {{ name }} there'),
  const _Case('ghost blank', 'hello {{}} there'),
  const _Case('ghost inside emphasis', 'a **bold {{ slot }} tail** b'),
  const _Case('ghost inside link text', 'a [see {{ what }}](https://x.dev) b'),
  const _Case('ghost inside colour run', 'a {red:take {{ n }} pills} b'),
  const _Case('ghost with braces around', 'a {{ x }} and {red:y} b'),
  const _Case('ghost is the whole line', '{{ topic }}'),

  // Escapes.
  const _Case('escaped asterisks', r'a \*not italic\* b'),
  const _Case('escaped hash', r'\#not a tag'),
  const _Case('escaped brace before ghost', r'a \{{ x }} b'),
  const _Case('escaped backslash', r'a \\ b'),
  const _Case('named entities', 'a &copy; b &nbsp;c &lt;d'),
  const _Case('numeric entities', '&#169; and &#x2014; and &times;'),
  const _Case('entity in bold', '**&mdash;**'),
  const _Case('unknown entity', '&nope; AT&T'),
  const _Case('trailing backslash', r'next line\'),
  const _Case('escaped trailing backslash', r'a\\'),
  const _Case('hard break in a list item', r'- item\'),
  const _Case('hard break in a quote', r'> quoted\'),
  const _Case('one-line triple-backtick code', '```npm i```'),
  const _Case('inline comment', 'a %%x #t [l](u)%% b'),
  const _Case('unclosed comment', 'a %%x **b**'),
  const _Case('adjacent comments', '%%a%%%%b%%'),
  const _Case('url ending in a backslash', r'see https://a.com/x\'),
  const _Case('heading ending in a backslash', r'# a\'),
  const _Case('callout title ending in a backslash', r'> [!NOTE] Title\'),
  const _Case('money label ending in a backslash', r'$+ 5 coffee\'),
  const _Case('slot then a backslash', r'$$ Sum: $ \'),
  const _Case('invisible numeric references', '&#x2028; &#x202E; &#150;'),
  const _Case('romanian quotes around underscores', '„_foarte greu_“'),
  const _Case('digit-flanked stars', 'Squat 3*10, Bench 3*8'),

  // Fences.
  const _Case('fence open', '```dart'),
  _Case('fence interior', 'final x = 1;', above: const <String>['```dart']),
  _Case(
    'fence interior with markdown',
    '- **not a list**',
    above: const <String>['```'],
  ),
  _Case('fence close', '```', above: const <String>['```dart', 'code']),

  // Unicode, tabs, long lines.
  const _Case('surrogate pair bullet', '- 🎉 party 🎉 done'),
  const _Case('surrogate pair heading', '# 👍 great 👨‍👩‍👧 day'),
  const _Case('surrogate inside emphasis', 'a **🎉 party** b'),
  const _Case('leading tab bullet', '\t- tabbed item'),
  const _Case('tab inside content', '- col a\tcol b'),
  const _Case('tab indented heading', '\t## tabbed heading'),
  _Case('over the raw-render length guard', _longLine),

  // Tables-lite: rows render monospace with tinted pipes and delimiter
  // rows dimmed whole — nothing is concealed or substituted, so the row
  // carries the same code units in both reveal states.
  const _Case('table row', '| set | reps |'),
  const _Case('table divider', '| --- | --- |'),
  const _Case('table divider with alignment', '|:--:|--:|'),
  const _Case('indented table row', '  | a | b |'),
  const _Case('table row with trailing space', '| a |  '),
  const _Case('table row with inline runs', '| **a** | `code` | #tag |'),
  const _Case('table row with a piped ghost', '| {{a|b}} |'),
  const _Case('table row with an escaped pipe', r'| a \| b | c |'),
  const _Case(
    'table row with an aliased wiki link',
    '| [[Session 1|legs]] | x |',
  ),
  const _Case('table row with an escaped closing pipe', r'| a | b \|'),
  const _Case('table row with a refused wiki link', '| [[Bench|`PR`]] | x |'),
  const _Case('table row with an escaped wiki alias', r'| [[Squat\|legs]] |'),
  const _Case('table row with brackets in a code span', '| `[[x` | y]] |'),
  _Case('table row inside a fence', '| a | b |', above: const <String>['```']),

  // Money: every row kind.
  const _Case('money set', r'$= 500'),
  const _Case('money add', r'$+ 12.50 coffee'),
  const _Case('money subtract', r'$- 8 lunch'),
  const _Case('money multiply', r'$* 2 doubled'),
  const _Case('money divide', r'$/ 4 split'),
  _Case('money total', r'$$', above: const <String>[r'$= 500']),
  _Case(
    'money total with label',
    r'$$ running sum',
    above: const <String>[r'$= 500'],
  ),
  _Case(
    'money total with value slot',
    r'$$ Current sum: $',
    above: const <String>[r'$= 500'],
  ),
  _Case(
    'money net change',
    r'$?',
    above: const <String>[r'$= 500', r'$+ 20 x'],
  ),
  _Case(
    'money entry diff',
    r'$^ 2',
    above: const <String>[r'$= 500', r'$+ 20 x', r'$- 5 y'],
  ),
  _Case(
    'money checkpoint span',
    r'$~ 2',
    above: const <String>[r'$= 500', r'$= 700'],
  ),
  _Case(
    'money span with accent and slot',
    r'$~ 2 teal: Change: $ dollars',
    above: const <String>[r'$= 500', r'$= 700'],
  ),
  const _Case('money target declaration', r'$! 1000'),
  _Case('money remaining status', r'$!', above: const <String>[r'$! 1000']),
  const _Case('money remaining with no target', r'$!'),
  const _Case('money not a marker', r'$!important stays text'),

  // Money: the four composable chrome layers.
  const _Case('money with accent token', r'$+ blue: 250 rent'),
  const _Case('money with unresolved accent', r'$+ note: 250 rent'),
  const _Case('money heading prefix', r'## $$'),
  const _Case('money heading no space', r'##$$'),
  const _Case('money list marker', r'- $= 500'),
  _Case(
    'money list marker on a display row',
    r'- $$ total',
    above: const <String>[r'$= 500'],
  ),
  const _Case('money ordered list marker', r'1. $+ 50 tip'),
  const _Case('money nested list marker', r'  - $+ 5 x'),
  _Case(
    'money nested list marker on a display row',
    r'  - $$ total',
    above: const <String>[r'$= 500'],
  ),
  const _Case('money emphasis wrapper', r'*$~ 2 Change: $ *'),
  const _Case('money emphasis wrapped diff', r'*$^ 2*'),
  const _Case('money all four chrome layers', r'- ## **$= teal: 500**'),
  const _Case('money emphasis unclosed stays raw', r'*$= 500'),

  // Money: label-first, currency, slots, errors.
  const _Case('money label first', r'$= Net worth: 5000'),
  const _Case(
    'money label first trailing',
    r'$= Net worth: 5000 lei as of now',
  ),
  const _Case('money inline currency', r'$= 500 lei'),
  const _Case('money op value slot', r'$+ 12.50 now $'),
  const _Case('money target label first', r'### $! yellow: Groceries: 500'),
  const _Case('money error divide by zero', r'$/ 0'),
  const _Case('money error non numeric', r'$+ abc'),
  const _Case('money error too large', r'$+ 999999999999 huge'),
  const _Case('money error too many decimals', r'$+ 1.234 odd'),
  const _Case('money error bulleted', r'- $/ 0 broken'),
  const _Case('dollar text is not money', r'- $100 coffee'),
  const _Case('money ghost in label', r'$+ 12.50 {{ what for }}'),

  // The shared inline grammar (MarkdownInlineGrammar): flanking, the
  // rule of three, matched-length fences, atoms winning over delimiters,
  // and the constructs that compose inside one another.
  _Case(
    'money emphasis wrapped diff with a balance above',
    r'*$^ 2*',
    above: const <String>[r'$= 500', r'$+ 20 x', r'$- 5 y'],
  ),
  const _Case('image with styled alt text', '![*a*](b)'),
  const _Case('escaped image bang', r'\![a](b)'),
  const _Case('code span with inner spaces', '` a `'),
  const _Case('triple tilde', '~~~x~~~'),
  const _Case('emphasis mid word', 'a*b*c'),
  const _Case('three asterisks closed by two', '***a**'),
  const _Case('dunder is bold', '__init__'),
  const _Case('interleaved emphasis', '*a _b* c_'),
  const _Case('ghost then emphasis', '{{a}} *b*'),
  const _Case('link inside bold', '**a [b](c) d**'),
  const _Case('tinted highlight then text', '==red:x== y'),
  const _Case('tag inside italic', '*#tag*'),
  const _Case('code span inside link text', '[a `]` x](b)'),
  const _Case('emphasis closer inside ghost', '**a {{b** c}}'),
  const _Case('emphasis opener inside code span', '*a `b* c`'),
  const _Case('deeply nested inline', '*_~~==[a](b)==~~_*'),

  // Plain prose and blanks.
  const _Case('plain prose', 'just some ordinary words'),
  const _Case('single space', ' '),
];
