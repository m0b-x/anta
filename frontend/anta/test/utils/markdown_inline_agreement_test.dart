import 'package:anta/constants/markdown_constants.dart';
import 'package:anta/utils/editor_render_context.dart';
import 'package:anta/utils/line_based_markdown_builder.dart';
import 'package:anta/utils/markdown_callout_syntax.dart';
import 'package:anta/utils/markdown_color_syntax.dart';
import 'package:anta/utils/markdown_editor_paint_spans.dart';
import 'package:anta/utils/markdown_editor_span_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Cross-surface guard for the one inline grammar.
///
/// `MarkdownEditorSpanBuilder` (live editor) and `LineBasedMarkdownBuilder`
/// (preview) are two independent emitters over the same
/// `MarkdownInlineGrammar` tokens. This suite renders a corpus of inline
/// lines through both and asserts they agree on
///
/// * the visible characters — the editor *conceals* markers (transparent
///   plus a 0.01 font size) while the preview *drops* them, so both
///   projections reduce to the same string, and
/// * the style of each visible character — weight, italic, strike,
///   underline, colour, background, plus the two "same intent, different
///   mechanism" flags below.
///
/// Documented, by-design surface differences are normalised inside the
/// projection so they do not read as disagreements:
///
/// 1. **monospace** — a unit reads as `mono` when the surface makes it
///    look like code, by whichever mechanism that surface uses: the
///    preview swaps in the `monospace` family (inline code at 0.9x with a
///    `codeBackground`, and every cell of a table), while the editor
///    either paints a `CodeDecoratedTextSpan` chip behind an inline code
///    run *or* sets the family itself (a table row). The flag is the
///    union of both on the editor side, so a real font disagreement is
///    still a finding; background and size are not compared on those
///    units.
/// 2. **tags** — the preview sets a `primary@0.12` background; the editor
///    paints a chip. Both project to `tag` (primary + w600), background
///    ignored.
/// 3. **headings** — only H1–H4 are in the corpus. H5/H6 blend toward
///    primary in the editor by design (a documented colour divergence),
///    and font size is not compared at all.
/// 4. **ghosts** — both dim the inner run to base@0.45 and hide the
///    `{{` / `}}`; only the editor underlines a *blank* ghost, so
///    underline is not compared on ghost-coloured units.
/// 5. **callout band** — the preview tints every line of a callout
///    block with `accent@0.10`; the editor paints no band (a run of
///    lines cannot share a background there). The tint is dropped on
///    the preview side, so the *text* colours are still compared.
/// 6. **callout icon** — the preview writes the type's emoji plus a
///    space; the editor substitutes one `EditorCalloutIconSpan` for the
///    token's `[` and paints the matching [IconData]. Both project to a
///    single `<icon>` unit (the emoji is 1–2 UTF-16 units, so this
///    happens at the leaf, before the split into code units).
///
/// Everything else that differs is a real finding — including the gap
/// space after a quote's bars, which both surfaces emit as its own
/// ambient-styled unit (the preview used to fold it into the bar run).
///
/// Quote and callout lines — the block constructs whose *content* is
/// still ordinary inline markdown — are in scope: a `_Case` may carry
/// [_Case.above] context lines, which both surfaces see (the preview
/// `prepare`s the whole document so the chunker's callout block exists,
/// the editor builds the same line out of the same buffer). Lists,
/// tasks, rules, money rows, fences and whole-line images stay out of
/// scope: those surfaces do not render comparable spans at all — the
/// preview lays them out as `WidgetSpan` rows and painted chips
/// (`￼` placeholders with widgets inside), while the editor keeps a
/// pure text run — so a unit-by-unit comparison would compare nothing.
void main() {
  // Nothing here pumps a widget: both builders take resolved values,
  // not a `BuildContext`. The binding is still needed because painted
  // runs lay a `TextPainter` out through dart:ui.
  TestWidgetsFlutterBinding.ensureInitialized();

  // The comparator is the whole point of the suite: if it stopped
  // seeing differences every corpus entry would pass vacuously.
  group('the comparator sees differences', () {
    test('a dropped marker on one surface fails', () {
      final editor = _editorUnits('a **b** c');
      final preview = _previewUnits('**b**');
      expect(_firstDifference(editor, preview), contains('visible text'));
    });

    test('a weight difference on one unit fails', () {
      final bold = _editorUnits('**b**');
      final plain = _editorUnits('b');
      expect(_firstDifference(bold, plain), contains('weight'));
    });

    test('a colour difference on one unit fails', () {
      final tinted = _editorUnits('{red:b}');
      final plain = _editorUnits('b');
      expect(_firstDifference(tinted, plain), contains('color'));
    });
  });

  group('editor and preview agree', () {
    for (final entry in _corpus) {
      test(entry.label, () {
        final editor = _editorUnits(entry.line, above: entry.above);
        final preview = _previewUnits(entry.line, above: entry.above);
        // Agreement between two empty projections proves nothing, so
        // pin that both surfaces actually rendered something. A bare
        // `###` is the one line that legitimately shows nothing.
        if (entry.line != '###') {
          expect(editor, isNotEmpty, reason: 'editor rendered nothing');
          expect(preview, isNotEmpty, reason: 'preview rendered nothing');
        }
        final diff = _firstDifference(editor, preview);
        final reason = entry.expectedDivergence;
        if (reason == null) {
          expect(
            diff,
            isNull,
            reason:
                'surfaces disagree on ${_quote(entry.line)}\n'
                '  $diff\n'
                '${_dump(entry.line, editor, preview)}',
          );
        } else {
          expect(
            diff,
            isNotNull,
            reason:
                'documented divergence no longer reproduces on '
                '${_quote(entry.line)} ($reason) — drop the marker\n'
                '${_dump(entry.line, editor, preview)}',
          );
          expect(
            diff,
            entry.expectedDiff,
            reason:
                'the pinned divergence on ${_quote(entry.line)} changed '
                'shape ($reason). Either the documented difference moved, '
                'or a second and undocumented one now comes first\n'
                '${_dump(entry.line, editor, preview)}',
          );
        }
      });
    }
  });

  // The preview drops markers, so every visible character must still
  // carry the source offset it came from or search highlighting lands on
  // the wrong glyph. Sweeping a one-unit highlight across the whole line
  // pins that mapping: each source offset paints either nothing (a
  // dropped marker) or exactly its own character, and the offsets that do
  // paint, in order, reconstruct the visible line.
  group('preview offsets', () {
    for (final entry in _offsetCorpus) {
      final line = entry.line;
      test('every visible unit keeps its source offset: ${_quote(line)}', () {
        final style = _previewStyle;
        final visible = _previewUnits(
          line,
          above: entry.above,
        ).map((u) => u.unit).join();
        final lineStart = _lineStart(entry.above);

        final painted = StringBuffer();
        for (var k = 0; k < line.length; k++) {
          final span = _previewSpan(
            line,
            above: entry.above,
            highlights: <TextRange>[
              TextRange(start: lineStart + k, end: lineStart + k + 1),
            ],
          );

          final all = _walk(span, const TextStyle(), null);
          expect(
            all.map((u) => u.text).join(),
            visible,
            reason:
                'a search highlight changed the visible text at offset $k '
                'of ${_quote(line)}',
          );
          final hit = all
              .where((u) => u.style.backgroundColor == style.highlightColor)
              .map((u) => u.text)
              .join();
          expect(
            hit,
            anyOf(isEmpty, equals(line[k])),
            reason:
                'offset $k of ${_quote(line)} highlighted ${_quote(hit)} '
                'instead of ${_quote(line[k])} (or nothing, if the unit is '
                'a dropped marker)',
          );
          painted.write(hit);
        }

        expect(
          painted.toString(),
          entry.painted ?? visible,
          reason:
              'the offsets that paint must reconstruct the visible line for '
              '${_quote(line)}',
        );
      });
    }
  });
}

// ---------------------------------------------------------------------------
// Corpus
// ---------------------------------------------------------------------------

class _Case {
  final String label;
  final String line;

  /// Lines placed directly above [line], for the block constructs whose
  /// rendering depends on context: a callout body only knows its accent
  /// from the lead line above it. Both surfaces render the same
  /// document, so neither can be fed a shape the other never sees.
  final List<String> above;

  /// Set when the two surfaces are known to differ here on purpose. The
  /// test then asserts the difference *still* reproduces, so a fixed
  /// divergence cannot rot into a silently skipped entry.
  final String? expectedDivergence;

  /// The exact first difference [_firstDifference] reports for this
  /// entry, pinned alongside [expectedDivergence]. Without it a pin
  /// swallows *any* disagreement on the line, so a second, unrelated
  /// regression would hide behind the documented one.
  final String? expectedDiff;

  const _Case(
    this.label,
    this.line, {
    this.above = const <String>[],
    this.expectedDivergence,
    this.expectedDiff,
  }) : assert(
         (expectedDivergence == null) == (expectedDiff == null),
         'a documented divergence must pin the difference it produces',
       );
}

final List<_Case> _corpus = <_Case>[
  // Emphasis: flanking, the rule of three, and partially spent runs.
  const _Case('bold', 'a **bold** b'),
  const _Case('italic asterisk', 'a *italic* b'),
  const _Case('bold underscore', 'a __bold__ b'),
  const _Case('italic underscore', 'a _italic_ b'),
  const _Case('bold italic asterisks', 'a ***both*** b'),
  const _Case('bold italic underscores', 'a ___both___ b'),
  const _Case('triple asterisk run', '***x***'),
  const _Case('triple underscore run', '___x___'),
  const _Case('bold outside italic', '*a **b** c*'),
  // A ghost sitting in concealed chrome: the preview drops the whole
  // url, the editor conceals it, so nothing of the ghost may paint.
  const _Case('ghost inside a link url', '[docs]({{ url }})'),
  _Case(
    'image mid line',
    'a ![x](y) b',
    expectedDivergence:
        'the preview renders `!` + a link on the alt text; the editor keeps '
        'the image source raw',
    expectedDiff: 'visible text: editor "a ![x](y) b" vs preview "a !x b"',
  ),
  const _Case('italic inside bold', '**a *b* c**'),
  const _Case('intraword underscores', '_a_b_'),
  const _Case('snake case is not emphasis', 'snake_case_word'),
  const _Case('dunder is bold', '__init__'),
  const _Case('emphasis mid word', 'a*b*c'),
  const _Case('spaced asterisks stay plain', '2 * 3 * 4'),
  const _Case('three closed by two', '***a**'),
  const _Case('emphasised bare url', 'see *https://a.com* now'),
  const _Case('bold bare url', '**https://a.com**'),
  const _Case(
    'ghost past the nesting depth',
    '{red:{red:{red:{red:{red:{red:{red:{red:{{g}}}}}}}}}}',
  ),
  const _Case('two closed by three', '**a***'),
  const _Case('bare double asterisk', '**'),
  const _Case('trailing asterisk', 'a*'),
  const _Case('leading asterisk', '*a'),
  const _Case('non ascii word char before underscore', 'ș_a_'),
  const _Case('interleaved emphasis', '*a _b* c_'),

  // Strikethrough and highlight (two-at-a-time runs).
  const _Case('strikethrough', 'a ~~gone~~ b'),
  const _Case('triple tilde', '~~~x~~~'),
  const _Case('single tilde stays plain', '~x~'),
  const _Case('highlight plain', '==x=='),
  const _Case('highlight in prose', 'a ==marked== b'),
  const _Case('highlight tinted', '==teal:x=='),
  const _Case('highlight tinted in prose', 'a ==teal:marked== b'),
  const _Case('highlight unresolved name', '==note: x=='),
  const _Case('highlight unresolved in prose', 'a ==note: see below== b'),
  const _Case('tinted highlight then text', '==red:x== y'),

  // Code atoms: matched-length fences, unclosed runs, spaces inside.
  const _Case('inline code', 'a `code()` b'),
  const _Case('double backtick code', 'a ``x`y`` b'),
  const _Case('double backtick run', '``a`b``'),
  const _Case('single backtick run', '`a`'),
  const _Case('code with inner spaces', '` a `'),
  const _Case('unclosed backtick', '`a'),
  const _Case('backslash is literal in code', r'`a\`b`'),
  const _Case('emphasis opener inside code', '*a `b* c`'),
  const _Case('code span inside link text', '[a `]` x](b)'),
  const _Case('tag inside code stays literal', 'run `git tag #v1x` now'),

  // Escapes.
  const _Case('escaped asterisks', r'\*a\*'),
  const _Case('escaped asterisks in prose', r'a \*not italic\* b'),
  const _Case('escaped backslash then italic', r'\\*a*'),
  const _Case('escaped brace before ghost', r'\{{x}}'),
  const _Case('escaped link bracket', r'\[a](b)'),
  const _Case('escaped image bang', r'\![a](b)'),
  const _Case('escaped hash', r'\#not a tag'),
  const _Case('escaped backslash alone', r'a \\ b'),

  // Links, images, bare URLs.
  const _Case('inline link', '[a](b)'),
  const _Case(
    'inline link in prose',
    'see [the docs](https://example.com/a) now',
  ),
  const _Case('link inside bold', '**a [b](c) d**'),
  const _Case('link inside emphasis', '*see [docs](https://example.com)*'),
  const _Case('bold wrapping a link', '**[a](b)**'),
  const _Case('bare https url', 'see https://example.com/a now'),
  const _Case('bare www url', 'see www.example.com/a now'),
  const _Case('bare url then ghost', 'www.a.com{{x}}'),
  _Case(
    'whole-line image',
    '![a](b)',
    expectedDivergence:
        'the preview renders a whole line image as a 🖼 glyph plus the alt '
        'text; the editor leaves `![a](b)` raw so the source stays editable',
    expectedDiff: 'visible text: editor "![a](b)" vs preview "🖼 a"',
  ),

  // Colours.
  const _Case('coloured text', 'a {red:danger} b'),
  const _Case('unresolved colour name', 'a {note:danger} b'),
  const _Case('colour inside bold', '**bold {blue:inner} tail**'),
  const _Case('ghost inside colour', '{red:a {{b}} c}'),

  // Tags.
  const _Case('tag in prose', 'see #project now'),
  const _Case('tag with slash', 'lifting #gym/legs today'),
  const _Case('tag inside italic', '*#tag*'),
  const _Case('tag inside link text', '[#tag](url)'),
  const _Case('digit after hash is not a tag', 'set #1'),
  const _Case('hash mid word is not a tag', 'no#42'),
  const _Case('tag then ghost', '#tag {{x}}'),

  // Ghosts, alone and composed.
  const _Case('ghost alone', 'hello {{ name }} there'),
  const _Case('blank ghost', 'hello {{}} there'),
  const _Case('ghost then emphasis', '{{a}} *b*'),
  const _Case('ghost wrapping an emphasis closer', '**a {{b** c}}'),
  const _Case('ghost wrapping a backtick', '`a {{b` c}}'),
  const _Case('ghost inside a code span', '`a {{b}} c` d'),
  const _Case('ghost wrapping a link close', '[a {{b](c) d}}'),
  const _Case('tag inside a ghost', '{{ #topic }}'),
  const _Case('ghost inside bold', 'a **bold {{ slot }} tail** b'),
  const _Case('ghost inside link text', 'a [see {{ what }}](https://x.dev) b'),
  const _Case('ghost inside colour run', 'a {red:take {{ n }} pills} b'),
  const _Case('ghost beside a colour run', 'a {{ x }} and {red:y} b'),

  // Headings (H1-H4 only; H5/H6 diverge on colour by design).
  const _Case('h1', '# Heading one'),
  const _Case('h2', '## Heading two'),
  const _Case('h3', '### Heading three'),
  const _Case('h4', '#### Heading four'),
  const _Case('seven hashes are prose', '####### Seven hashes'),
  const _Case('bare hashes are an empty heading', '###'),
  const _Case('heading with extra spaces', '#   spaced heading'),
  _Case(
    'indented heading',
    '  ## Indented heading',
    expectedDivergence:
        'the editor keeps a heading\'s leading indent visible (it may never '
        'drop a code unit); the preview drops it with the hashes. '
        'Whitespace-only, so the reader sees the same glyphs',
    expectedDiff:
        'visible text: editor "  Indented heading" vs preview "Indented heading"',
  ),
  _Case(
    'heading with trailing spaces',
    '## Trailing heading  ',
    expectedDivergence:
        'the preview trims a heading\'s trailing blanks; the editor keeps '
        'them, again because every source code unit must survive. '
        'Whitespace-only',
    expectedDiff:
        'visible text: editor "Trailing heading  " vs preview "Trailing heading"',
  ),
  const _Case('heading with inline runs', '# **Bold** and `code` #tag'),
  const _Case('heading with nested emphasis', '## *a **b** c*'),

  // Deep nesting: both surfaces must flatten at the same depth.
  const _Case('deeply nested inline', '*_~~==[a](b)==~~_*'),
  const _Case('nine levels of emphasis', '*_*_*_*_*_x_*_*_*_*'),

  // Blockquotes: one `┃` per `>` marker, content inline-formatted.
  const _Case('quote', '> quote'),
  const _Case('quote with an inline run', '> quote with **bold**'),
  const _Case('nested quote', '>> nested'),
  _Case(
    'spaced nested quote',
    '> > spaced nested',
    expectedDivergence:
        'the preview packs the bars together and writes one trailing space '
        '(`┃┃ `); the editor keeps the source space between the markers '
        '(`┃ ┃ `) because it may never drop a code unit. Whitespace-only, '
        'and the quoted content styles identically',
    expectedDiff:
        'visible text: editor "┃ ┃ spaced nested" vs preview "┃┃ spaced nested"',
  ),
  const _Case('deep quote', '>>> deep'),
  _Case(
    'deep spaced quote',
    '> > > deep spaced',
    expectedDivergence:
        'as the spaced nested quote: the preview drops the spaces between '
        'the `>` markers, the editor keeps them. Whitespace-only',
    expectedDiff:
        'visible text: editor "┃ ┃ ┃ deep spaced" vs preview "┃┃┃ deep spaced"',
  ),
  _Case(
    'indented quote',
    '  > indented quote',
    expectedDivergence:
        'the same policy as the indented heading — the editor keeps the '
        'leading indent visible, the preview drops it with the marker run. '
        'Whitespace-only',
    expectedDiff:
        'visible text: editor "  ┃ indented quote" vs preview "┃ indented quote"',
  ),
  _Case(
    'quote indented with a form feed',
    '> flagged quote',
    expectedDivergence:
        'exotic leading whitespace is indent to both surfaces, so both draw '
        'the bar and italicise the same content — but the editor keeps the '
        'indent unit visible where the preview drops it, exactly as for the '
        'space-indented quote above. Whitespace-only',
    expectedDiff:
        'visible text: editor "┃ flagged quote" vs '
        'preview "┃ flagged quote"',
  ),

  // Callout leads: icon, `[!TYPE]` consumed, title accent + bold.
  const _Case('callout lead tip', '> [!TIP] Rest between sets'),
  const _Case('callout lead warning', '> [!WARNING] Watch the knee'),
  const _Case('callout lead pr', '> [!PR] 140 kg deadlift'),
  const _Case('callout lead with a bold title', '> [!NOTE] **big** day'),
  _Case(
    'callout lead without a title',
    '> [!TIP]',
    expectedDivergence:
        'the preview synthesises the type label ("Tip") as a header; the '
        'editor may not add code units the source does not have, so it '
        'shows the icon and nothing else',
    expectedDiff: 'visible text: editor "┃ <icon>" vs preview "┃ <icon> Tip"',
  ),

  // Callout bodies: the block accent on the bars, plain content.
  const _Case(
    'callout body',
    '> keep the bar loose',
    above: <String>['> [!TIP] x'],
  ),
  const _Case(
    'nested callout body',
    '>> nested note',
    above: <String>['> [!TIP] x'],
  ),
  const _Case(
    'callout body with inline code',
    '> hold `3s` at the top',
    above: <String>['> [!WARNING] x'],
  ),
  _Case(
    'a nested lead is body text',
    '> [!NOTE] inner',
    above: <String>['> [!TIP] x'],
    expectedDivergence:
        'both surfaces agree the line is body text of the open tip block — '
        'no icon, no second header — but the preview renders the `[!NOTE]` '
        'token as literal body text while the editor keeps it tinted in the '
        "note accent at w600, so a lead you are still typing stays legible "
        'as the token it is',
    expectedDiff:
        'unit 2 "[" — weight: editor FontWeight.w600 vs preview FontWeight.w400',
  ),

  // Tables-lite: the editor keeps the row's own units, the preview lays
  // a real table out.
  _Case(
    'table row',
    '| set | reps |',
    expectedDivergence:
        'the preview re-joins trimmed cells with " │ "; the editor keeps '
        'every source unit (pipes and padding included) so the row stays '
        'editable',
    expectedDiff:
        'visible text: editor "| set | reps |" vs preview "set │ reps"',
  ),
  _Case(
    'table separator row',
    '| --- | --- |',
    expectedDivergence:
        'the preview draws a fixed 30-glyph rule; the editor dims the row '
        'in place',
    expectedDiff:
        'visible text: editor "| --- | --- |" vs preview "──────────────────────────────"',
  ),

  // Plain prose.
  const _Case('plain prose', 'just some ordinary words'),
];

/// One line of the offset sweep.
class _OffsetCase {
  final String line;
  final List<String> above;

  /// What the offsets that *do* paint must spell, when that is not the
  /// whole visible line. A block construct draws chrome of its own — a
  /// quote's `┃` bars, a callout's icon, a table's ` │ ` separators —
  /// which stands for no source unit and so can never be highlighted.
  /// Everything else must still be a bijection.
  final String? painted;

  const _OffsetCase(this.line, {this.above = const <String>[], this.painted});
}

/// Lines whose source-offset threading is worth sweeping unit by unit:
/// nesting, escapes, ghosts, code atoms, the heading whose content
/// keeps its leading spaces, and the block constructs whose content sits
/// behind synthesized chrome.
const List<_OffsetCase> _offsetCorpus = <_OffsetCase>[
  _OffsetCase('*a **b** c*'),
  _OffsetCase('***a**'),
  _OffsetCase(r'a \*not italic\* b'),
  _OffsetCase(r'\\*a*'),
  _OffsetCase(r'\{{x}}'),
  _OffsetCase('a **bold {{ slot }} tail** b'),
  _OffsetCase('`a {{b}} c` d'),
  _OffsetCase('a ``x`y`` b'),
  _OffsetCase('[a `]` x](b)'),
  _OffsetCase('{red:a {{b}} c}'),
  _OffsetCase('{{ #topic }}'),
  _OffsetCase('*_~~==[a](b)==~~_*'),
  _OffsetCase('a ==teal:marked== b'),
  _OffsetCase('[#tag](url)'),
  _OffsetCase('{red:**`a {{g}} b`**}'),
  _OffsetCase(r'{red:[a \* b](u)}'),
  _OffsetCase('see www.example.com/a now'),
  _OffsetCase('#   spaced heading'),
  _OffsetCase('# **Bold** and `code` #tag'),
  _OffsetCase('## *a **b** c*'),
  _OffsetCase('see *https://a.com* now'),
  _OffsetCase('{red:{red:{red:{red:{red:{red:{red:{red:{{g}}}}}}}}}}'),
  _OffsetCase('> quote', painted: 'quote'),
  _OffsetCase('>> nested', painted: 'nested'),
  _OffsetCase('> [!TIP] Rest', painted: 'Rest'),
  _OffsetCase('> keep it', above: <String>['> [!TIP] x'], painted: 'keep it'),
  _OffsetCase('| a | b |', painted: 'ab'),
];

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

const String _pad = 'padding line';

const Color _baseColor = Color(0xFF202124);

const TextStyle _baseStyle = TextStyle(
  fontSize: 16.0,
  height: 1.4,
  color: _baseColor,
);

/// The one theme both surfaces resolve from — built directly, never
/// pumped: the editor renderer takes an [EditorRenderContext] and the
/// preview builder a [LineMarkdownStyle], so neither needs a widget
/// tree.
final ThemeData _theme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.light,
);

final EditorRenderContext _editorContext = EditorRenderContext.fromTheme(
  _theme,
  _baseStyle,
);

final LineMarkdownStyle _previewStyle = LineMarkdownStyle.fromTheme(
  _theme,
  _baseStyle.fontSize!,
  textColor: _baseColor,
);

/// The document a case renders inside: a padding line, the case's
/// [above] context, the line under test, and a trailing padding line.
/// Both surfaces see exactly this, so a block construct (a callout
/// body's accent, a chunker block extent) resolves the same way on each.
List<String> _document(String line, List<String> above) => <String>[
  _pad,
  ...above,
  line,
  _pad,
];

/// Index of the line under test inside [_document].
int _lineIndex(List<String> above) => 1 + above.length;

/// Source offset where the line under test starts inside [_document].
int _lineStart(List<String> above) => _document(
  '',
  above,
).take(_lineIndex(above)).fold(0, (sum, l) => sum + l.length + 1);

/// Builds [line] off-caret (the caret parks on the first padding line,
/// so nothing reveals) and projects the span tree down to visible units.
/// A line the builder declines to style renders as plain text, which is
/// exactly what the editor page falls back to.
List<_Unit> _editorUnits(String line, {List<String> above = const <String>[]}) {
  final controller = CodeLineEditingController.fromText(
    _document(line, above).join('\n'),
  );
  addTearDown(controller.dispose);
  final builder = MarkdownEditorSpanBuilder()..bind(controller);
  builder.configureColors(MarkdownColorPalette.presets);
  controller.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);
  final index = _lineIndex(above);
  final span = builder.build(
    context: _editorContext,
    index: index,
    codeLine: controller.codeLines[index],
  );
  return _project(
    span ?? TextSpan(text: line, style: _baseStyle),
    editor: true,
  );
}

/// The preview's span for [line] inside [_document]. [prepare] takes the
/// whole source — the chunker's block scan is what tells the renderer a
/// line belongs to a callout — and [LineBasedMarkdownBuilder.buildLine]
/// takes the line's index in that source.
TextSpan _previewSpan(
  String line, {
  List<String> above = const <String>[],
  List<TextRange>? highlights,
}) {
  final builder = LineBasedMarkdownBuilder(
    style: _previewStyle,
    colorPalette: MarkdownColorPalette.presets,
    searchHighlights: highlights,
  );
  addTearDown(builder.dispose);
  builder.prepare(_document(line, above).join('\n'));
  return builder.buildLine(line, _lineIndex(above));
}

List<_Unit> _previewUnits(
  String line, {
  List<String> above = const <String>[],
}) => _project(_previewSpan(line, above: above), editor: false);

// ---------------------------------------------------------------------------
// Projection
// ---------------------------------------------------------------------------

/// One visible code unit and the styling a reader perceives on it.
typedef _Unit = ({
  String unit,
  FontWeight weight,
  bool italic,
  bool strike,
  bool underline,
  bool mono,
  bool tag,
  bool ghost,
  Color? color,
  Color? background,
});

/// A raw walked leaf: one code unit with its fully inherited style and
/// the chip (if any) painted behind its run.
typedef _Raw = ({String text, TextStyle style, Color? chip});

/// A marker span: transparent and shrunk to a 0.01 font size, exactly
/// what the editor's `_concealStyle` produces. Never emitted by the
/// preview, which drops markers outright.
bool _concealed(TextStyle style) =>
    style.color == const Color(0x00000000) && style.fontSize == 0.01;

/// The unit both surfaces' callout icon projects to: the editor paints
/// an [IconData] into a placeholder, the preview writes an emoji, and
/// the two carry a different number of UTF-16 units.
const String _iconUnit = '<icon>';

/// The preview's icon runs, one per callout type (`'💡 '`), matched
/// whole at the leaf because an emoji may be a surrogate pair.
final Set<String> _previewIconRuns = <String>{
  for (final type in MarkdownCalloutType.values)
    '${MarkdownCalloutSyntax.iconFor(type)} ',
};

/// The preview's callout band, one tint per type. Light theme only —
/// the whole suite resolves from [_theme].
final Set<Color> _calloutTints = <Color>{
  for (final type in MarkdownCalloutType.values)
    MarkdownConstants.calloutAccent(type, dark: false).withValues(alpha: 0.10),
};

/// Walks [root] in order, resolving each leaf's style by merging parents
/// down (a child `TextSpan`'s style overrides only the fields it sets),
/// and emits one entry per visible UTF-16 code unit. Placeholder spans
/// count as the single `￼` unit they substitute — except the callout
/// icon, which projects to [_iconUnit] on both surfaces.
List<_Raw> _walk(InlineSpan root, TextStyle inherited, Color? chip) {
  final out = <_Raw>[];
  void visit(InlineSpan span, TextStyle parent, Color? parentChip) {
    final style = parent.merge(span.style);
    if (span is TextSpan) {
      final ownChip = span is CodeDecoratedTextSpan
          ? span.decoration.color
          : parentChip;
      final text = span.text;
      if (text != null && text.isNotEmpty && !_concealed(style)) {
        if (_previewIconRuns.contains(text)) {
          out.add((text: _iconUnit, style: style, chip: ownChip));
          out.add((text: ' ', style: style, chip: ownChip));
        } else {
          for (var i = 0; i < text.length; i++) {
            out.add((text: text[i], style: style, chip: ownChip));
          }
        }
      }
      final children = span.children;
      if (children != null) {
        for (final child in children) {
          visit(child, style, ownChip);
        }
      }
      return;
    }
    if (span is PlaceholderSpan) {
      out.add((
        text: span is EditorCalloutIconSpan ? _iconUnit : '￼',
        style: style,
        chip: parentChip,
      ));
    }
  }

  visit(root, inherited, chip);
  return out;
}

List<_Unit> _project(InlineSpan root, {required bool editor}) {
  final primary = _editorContext.primary;
  final ghostColor = _baseColor.withValues(alpha: 0.45);
  final codeChip = _baseColor.withValues(alpha: 0.08);
  final tagChip = primary.withValues(alpha: 0.12);

  return _walk(root, const TextStyle(), null).map((raw) {
    final style = raw.style;
    // Same intent, different mechanism: the editor paints a chip behind
    // the run, the preview restyles the text.
    final mono = editor
        ? raw.chip == codeChip || style.fontFamily == 'monospace'
        : style.fontFamily == 'monospace';
    final tag = editor
        ? raw.chip == tagChip
        : style.backgroundColor == tagChip &&
              style.fontWeight == FontWeight.w600;
    return (
      unit: raw.text,
      weight: style.fontWeight ?? FontWeight.normal,
      italic: style.fontStyle == FontStyle.italic,
      strike: style.decoration?.contains(TextDecoration.lineThrough) ?? false,
      underline: style.decoration?.contains(TextDecoration.underline) ?? false,
      mono: mono,
      tag: tag,
      ghost: style.color == ghostColor,
      color: style.color,
      // Both chip mechanisms reserve the background slot for themselves,
      // so it carries no cross-surface meaning on those units — and the
      // preview's callout band is a block-level tint the editor cannot
      // paint at all, so it is dropped rather than compared.
      background: mono || tag || _calloutTints.contains(style.backgroundColor)
          ? null
          : style.backgroundColor,
    );
  }).toList();
}

// ---------------------------------------------------------------------------
// Comparison + reporting
// ---------------------------------------------------------------------------

String? _firstDifference(List<_Unit> editor, List<_Unit> preview) {
  final editorText = editor.map((u) => u.unit).join();
  final previewText = preview.map((u) => u.unit).join();
  if (editorText != previewText) {
    return 'visible text: editor ${_quote(editorText)} vs '
        'preview ${_quote(previewText)}';
  }
  for (var i = 0; i < editor.length; i++) {
    final e = editor[i];
    final p = preview[i];
    final fields = <String, (Object?, Object?)>{
      'weight': (e.weight, p.weight),
      'italic': (e.italic, p.italic),
      'strike': (e.strike, p.strike),
      'mono': (e.mono, p.mono),
      'tag': (e.tag, p.tag),
      'color': (e.color, p.color),
      'background': (e.background, p.background),
      // A blank ghost is underlined in the editor only, so underline is
      // only meaningful off the ghost path.
      if (!e.ghost && !p.ghost) 'underline': (e.underline, p.underline),
    };
    for (final field in fields.entries) {
      final (a, b) = field.value;
      if (a != b) {
        return 'unit $i ${_quote(e.unit)} — ${field.key}: editor $a vs '
            'preview $b';
      }
    }
  }
  return null;
}

String _dump(String line, List<_Unit> editor, List<_Unit> preview) =>
    '  source : ${_quote(line)}\n'
    '  editor : ${_describe(editor)}\n'
    '  preview: ${_describe(preview)}';

String _describe(List<_Unit> units) => units
    .map((u) {
      final flags = <String>[
        if (u.weight != FontWeight.normal) 'w${u.weight.value}',
        if (u.italic) 'i',
        if (u.strike) 's',
        if (u.underline) 'u',
        if (u.mono) 'code',
        if (u.tag) 'tag',
        if (u.ghost) 'ghost',
        if (u.color != null) 'c${_hex(u.color!)}',
        if (u.background != null) 'bg${_hex(u.background!)}',
      ];
      return '${_quote(u.unit)}[${flags.join(',')}]';
    })
    .join(' ');

String _hex(Color color) =>
    color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();

String _quote(String s) =>
    '"'
    '${s.replaceAll('￼', '<box>').replaceAll('\n', r'\n')}'
    '"';
