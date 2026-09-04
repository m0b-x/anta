import 'package:anta/utils/line_based_markdown_builder.dart';
import 'package:anta/utils/markdown_color_syntax.dart';
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
/// 1. **inline code** — the preview swaps in `monospace` at 0.9x with a
///    `codeBackground`; the editor paints a `CodeDecoratedTextSpan` chip
///    and changes no font. Both project to `mono`, and background/size
///    are not compared for those units.
/// 2. **tags** — the preview sets a `primary@0.12` background; the editor
///    paints a chip. Both project to `tag` (primary + w600), background
///    ignored.
/// 3. **headings** — only H1–H4 are in the corpus. H5/H6 blend toward
///    primary in the editor by design (a documented colour divergence),
///    and font size is not compared at all.
/// 4. **ghosts** — both dim the inner run to base@0.45 and hide the
///    `{{` / `}}`; only the editor underlines a *blank* ghost, so
///    underline is not compared on ghost-coloured units.
///
/// Everything else that differs is a real finding. Block chrome (lists,
/// tasks, quotes, rules, tables, money, fences, whole-line images) is
/// deliberately out of scope — those surfaces differ by design and have
/// their own suites.
void main() {
  // The comparator is the whole point of the suite: if it stopped
  // seeing differences every corpus entry would pass vacuously.
  group('the comparator sees differences', () {
    testWidgets('a dropped marker on one surface fails', (tester) async {
      final context = await _pumpForContext(tester);
      final editor = _editorUnits(context, 'a **b** c');
      final preview = _previewUnits(context, '**b**');
      expect(_firstDifference(editor, preview), contains('visible text'));
    });

    testWidgets('a weight difference on one unit fails', (tester) async {
      final context = await _pumpForContext(tester);
      final bold = _editorUnits(context, '**b**');
      final plain = _editorUnits(context, 'b');
      expect(_firstDifference(bold, plain), contains('weight'));
    });

    testWidgets('a colour difference on one unit fails', (tester) async {
      final context = await _pumpForContext(tester);
      final tinted = _editorUnits(context, '{red:b}');
      final plain = _editorUnits(context, 'b');
      expect(_firstDifference(tinted, plain), contains('color'));
    });
  });

  group('editor and preview agree', () {
    for (final entry in _corpus) {
      testWidgets(entry.label, (tester) async {
        final context = await _pumpForContext(tester);
        final editor = _editorUnits(context, entry.line);
        final preview = _previewUnits(context, entry.line);
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
    for (final line in _offsetCorpus) {
      testWidgets('every visible unit keeps its source offset: '
          '${_quote(line)}', (tester) async {
        final context = await _pumpForContext(tester);
        final style = _previewStyle(context);
        final visible = _previewUnits(context, line).map((u) => u.unit).join();

        final painted = StringBuffer();
        for (var k = 0; k < line.length; k++) {
          final builder = LineBasedMarkdownBuilder(
            style: style,
            colorPalette: MarkdownColorPalette.presets,
            searchHighlights: <TextRange>[TextRange(start: k, end: k + 1)],
          );
          addTearDown(builder.dispose);
          builder.prepare(line);
          final span = builder.buildLine(line, 0);

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
          visible,
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

  /// Set when the two surfaces are known to differ here on purpose. The
  /// test then asserts the difference *still* reproduces, so a fixed
  /// divergence cannot rot into a silently skipped entry.
  final String? expectedDivergence;

  const _Case(this.label, this.line, {this.expectedDivergence});
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
  const _Case('italic inside bold', '**a *b* c**'),
  const _Case('intraword underscores', '_a_b_'),
  const _Case('snake case is not emphasis', 'snake_case_word'),
  const _Case('dunder is bold', '__init__'),
  const _Case('emphasis mid word', 'a*b*c'),
  const _Case('spaced asterisks stay plain', '2 * 3 * 4'),
  const _Case('three closed by two', '***a**'),
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
  ),
  _Case(
    'heading with trailing spaces',
    '## Trailing heading  ',
    expectedDivergence:
        'the preview trims a heading\'s trailing blanks; the editor keeps '
        'them, again because every source code unit must survive. '
        'Whitespace-only',
  ),
  const _Case('heading with inline runs', '# **Bold** and `code` #tag'),
  const _Case('heading with nested emphasis', '## *a **b** c*'),

  // Deep nesting: both surfaces must flatten at the same depth.
  const _Case('deeply nested inline', '*_~~==[a](b)==~~_*'),
  const _Case('nine levels of emphasis', '*_*_*_*_*_x_*_*_*_*'),

  // Plain prose.
  const _Case('plain prose', 'just some ordinary words'),
];

/// Lines whose source-offset threading is worth sweeping unit by unit:
/// nesting, escapes, ghosts, code atoms, and the heading whose content
/// keeps its leading spaces.
const List<String> _offsetCorpus = <String>[
  '*a **b** c*',
  '***a**',
  r'a \*not italic\* b',
  r'\\*a*',
  r'\{{x}}',
  'a **bold {{ slot }} tail** b',
  '`a {{b}} c` d',
  'a ``x`y`` b',
  '[a `]` x](b)',
  '{red:a {{b}} c}',
  '{{ #topic }}',
  '*_~~==[a](b)==~~_*',
  'a ==teal:marked== b',
  '[#tag](url)',
  'see www.example.com/a now',
  '#   spaced heading',
  '# **Bold** and `code` #tag',
  '## *a **b** c*',
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

Future<BuildContext> _pumpForContext(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: Brightness.light),
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured;
}

LineMarkdownStyle _previewStyle(BuildContext context) =>
    LineMarkdownStyle.fromTheme(
      Theme.of(context),
      _baseStyle.fontSize!,
      textColor: _baseColor,
    );

/// Builds [line] off-caret (the caret parks on the padding line above, so
/// nothing reveals) and projects the span tree down to visible units. A
/// line the builder declines to style renders as plain text, which is
/// exactly what the editor page falls back to.
List<_Unit> _editorUnits(BuildContext context, String line) {
  final controller = CodeLineEditingController.fromText(
    <String>[_pad, line, _pad].join('\n'),
  );
  addTearDown(controller.dispose);
  final builder = MarkdownEditorSpanBuilder()..bind(controller);
  builder.configureColors(MarkdownColorPalette.presets);
  controller.selection = const CodeLineSelection.collapsed(index: 0, offset: 0);
  final span = builder.build(
    context: context,
    index: 1,
    codeLine: controller.codeLines[1],
    style: _baseStyle,
  );
  return _project(
    span ?? TextSpan(text: line, style: _baseStyle),
    context,
    editor: true,
  );
}

List<_Unit> _previewUnits(BuildContext context, String line) {
  final builder = LineBasedMarkdownBuilder(
    style: _previewStyle(context),
    colorPalette: MarkdownColorPalette.presets,
  );
  addTearDown(builder.dispose);
  builder.prepare(line);
  return _project(builder.buildLine(line, 0), context, editor: false);
}

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

/// Walks [root] in order, resolving each leaf's style by merging parents
/// down (a child `TextSpan`'s style overrides only the fields it sets),
/// and emits one entry per visible UTF-16 code unit. Placeholder spans
/// count as the single `￼` unit they substitute.
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
        for (var i = 0; i < text.length; i++) {
          out.add((text: text[i], style: style, chip: ownChip));
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
      out.add((text: '￼', style: style, chip: parentChip));
    }
  }

  visit(root, inherited, chip);
  return out;
}

List<_Unit> _project(
  InlineSpan root,
  BuildContext context, {
  required bool editor,
}) {
  final primary = Theme.of(context).colorScheme.primary;
  final ghostColor = _baseColor.withValues(alpha: 0.45);
  final codeChip = _baseColor.withValues(alpha: 0.08);
  final tagChip = primary.withValues(alpha: 0.12);

  return _walk(root, const TextStyle(), null).map((raw) {
    final style = raw.style;
    // Same intent, different mechanism: the editor paints a chip behind
    // the run, the preview restyles the text.
    final mono = editor
        ? raw.chip == codeChip
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
      // so it carries no cross-surface meaning on those units.
      background: mono || tag ? null : style.backgroundColor,
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
