import 'package:anta/constants/markdown_constants.dart';
import 'package:anta/utils/editor_render_context.dart';
import 'package:anta/utils/markdown_color_syntax.dart';
import 'package:anta/utils/markdown_editor_span_builder.dart';
import 'package:anta/utils/markdown_editor_span_cache.dart';
import 'package:anta/utils/markdown_inline_grammar.dart';
import 'package:anta/utils/money_display_config.dart';
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
/// * a root `fontSize` that does not move between reveal states (a caret
///   move must never change a line's height).
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
          _expectCodeUnits(entry.line, span, where);
        }

        final off = spans[false];
        final on = spans[true];
        final where = '${entry.label} [money=$money]';
        expect(
          off == null,
          on == null,
          reason: 'handled-ness must not depend on reveal: $where',
        );
        expect(
          off?.style?.fontSize,
          on?.style?.fontSize,
          reason: 'root fontSize must not move between reveal states: $where',
        );

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
  0x2503: '>', // ┃ — blockquote bar
  0x2500: '-*_', // ─ — horizontal rule
  0x03A3: r'$', // Σ — `$$` total marker with a value slot
  0x25CE: '!', // ◎ — `$!` marker, and the `$!` target op glyph
  0x0394: '?^~', // Δ — `$?` / `$^` / `$~` markers with a value slot
  0x2212: '-', // − — `$-` op glyph
  0x00D7: '*', // × — `$*` op glyph
  0x00F7: '/', // ÷ — `$/` op glyph
  0x0021: r'$', // ! — money error row marker
  0xFFFC: r'[$?^~!:', // placeholder run — checkbox, money chip, op glyph
};

/// One visible piece of a built line: a text leaf that is not concealed,
/// or a placeholder run (a checkbox, a money chip, an op glyph).
class _Leaf {
  final String text;
  final TextStyle? style;
  final InlineSpan span;

  const _Leaf(this.text, this.style, this.span);
}

typedef _Render = ({TextSpan span, List<_Leaf> leaves, String visibleText});

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

/// A marker span: transparent and shrunk to a 0.01 font size, which is
/// exactly what the builder's `_concealStyle` produces.
bool _concealed(TextStyle? style) =>
    style != null &&
    style.color == const Color(0x00000000) &&
    style.fontSize == 0.01;

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

void _expectCodeUnits(String source, InlineSpan span, String where) {
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
  const _Case('image stays raw', '![alt](https://example.com/a.png)'),
  const _Case('link inside emphasis', '*see [docs](https://example.com)*'),

  // Tags.
  const _Case('tag', 'lifting #legs today'),
  const _Case('nested tag', 'lifting #gym/legs today'),
  const _Case('hash mid word is not a tag', 'issue no#42 today'),

  // Quotes, callouts, rules.
  const _Case('quote', '> a quoted line'),
  const _Case('indented quote', '  > an indented quote'),
  const _Case('callout lead', '> [!TIP] Rest between sets'),
  const _Case('callout continuation', '> body of the callout'),
  const _Case('rule dashes', '---'),
  const _Case('rule asterisks', '***'),
  const _Case('rule underscores', '_____'),
  const _Case('rule with trailing space', '---  '),

  // Lists and tasks.
  const _Case('bullet dash', '- squat'),
  const _Case('bullet star', '* squat'),
  const _Case('bullet plus', '+ squat'),
  const _Case('nested bullet', '  - deeper'),
  const _Case('double nested bullet', '    - deepest'),
  const _Case('ordered dot', '1. first'),
  const _Case('ordered paren', '2) second'),
  const _Case('task unchecked', '- [ ] warm up'),
  const _Case('task checked', '- [x] warm up'),
  _Case(
    'task indeterminate parent',
    '- [ ] parent',
    below: const <String>['  - [x] done child', '  - [ ] open child'],
  ),
  const _Case('list with inline runs', '- **heavy** `3x5` #legs'),

  // Ghost text, on its own and composed.
  const _Case('ghost alone', 'hello {{ name }} there'),
  const _Case('ghost blank', 'hello {{}} there'),
  const _Case('ghost inside emphasis', 'a **bold {{ slot }} tail** b'),
  const _Case('ghost inside link text', 'a [see {{ what }}](https://x.dev) b'),
  const _Case('ghost inside colour run', 'a {red:take {{ n }} pills} b'),
  const _Case('ghost with braces around', 'a {{ x }} and {red:y} b'),

  // Escapes.
  const _Case('escaped asterisks', r'a \*not italic\* b'),
  const _Case('escaped hash', r'\#not a tag'),
  const _Case('escaped brace before ghost', r'a \{{ x }} b'),
  const _Case('escaped backslash', r'a \\ b'),

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

  // GFM table rows render raw in the editor.
  const _Case('table row', '| set | reps |'),
  const _Case('table divider', '| --- | --- |'),

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
  const _Case('money ordered list marker', r'1. $+ 50 tip'),
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
