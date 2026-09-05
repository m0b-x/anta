import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/controllers/editor_render_controller.dart';
import 'package:anta/utils/editor_render_context.dart';
import 'package:anta/utils/markdown_color_syntax.dart';
import 'package:anta/utils/money_display_config.dart';

/// The editor page's rendering seam: what a line becomes, and what the
/// two render-affecting settings do to the builder behind it.
///
/// Two invariants carry this file. First, the ghost-text fallback may
/// never add or drop a code unit: re_editor maps caret, selection and
/// search offsets through the span it returns, so a single lost character
/// desyncs the model from what the user sees. Second, `applyMoneyConfig`
/// / `applyPalette` must configure the builder on *every* call while
/// reporting a change only on a real one — the page repaints on the
/// report, but the builder's own state must never lag behind the value
/// the controller hands to the preview and the detail sheet.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ghostSpan code units', () {
    for (final line in _ghostCorpus) {
      test('preserves every code unit of "$line"', () {
        final span = _ghost(line);
        expect(
          span.toPlainText(includePlaceholders: true),
          line,
          reason: 'the rendered span must carry the source line verbatim',
        );
      });
    }

    for (final line in _plainCorpus) {
      test('returns the given span untouched for "$line"', () {
        final fallback = TextSpan(text: line, style: _style);
        final span = EditorRenderController.ghostSpan(
          codeLine: CodeLine(line),
          textSpan: fallback,
          style: _style,
          baseColor: _baseColor,
        );
        expect(
          identical(span, fallback),
          isTrue,
          reason: 'a line without a ghost run must not be rebuilt',
        );
      });
    }

    test('conceals the markers and dims the inner text', () {
      final leaves = _leaves(_ghost('a {{ set }} b'));

      expect(leaves.map((leaf) => leaf.text).toList(), [
        'a ',
        '{{',
        ' set ',
        '}}',
        ' b',
      ]);
      for (final marker in [leaves[1], leaves[3]]) {
        expect(marker.style?.color, const Color(0x00000000));
        expect(marker.style?.fontSize, 0.01);
      }
      expect(leaves[2].style?.color, _baseColor.withValues(alpha: 0.45));
      expect(leaves[0].style, _style);
      expect(leaves[4].style, _style);
    });

    test('underlines a blank placeholder so the empty slot stays visible', () {
      final blank = _leaves(_ghost('{{  }}'))[1];
      expect(blank.text, '  ');
      expect(blank.style?.decoration, TextDecoration.underline);
      expect(blank.style?.decorationColor, _baseColor.withValues(alpha: 0.45));

      final filled = _leaves(_ghost('{{ x }}'))[1];
      expect(filled.text, ' x ');
      expect(filled.style?.decoration, isNot(TextDecoration.underline));
    });

    test('renders two ghosts on one line without merging them', () {
      final leaves = _leaves(_ghost('{{a}} {{b}}'));
      expect(leaves.map((leaf) => leaf.text).toList(), [
        '{{',
        'a',
        '}}',
        ' ',
        '{{',
        'b',
        '}}',
      ]);
    });
  });

  group('money config', () {
    test('starts at the shipped defaults', () {
      expect(
        EditorRenderController().moneyConfig,
        EditorRenderController.defaultMoneyConfig,
      );
    });

    test('the shipped defaults are already applied to the builder', () {
      // The builder's own default is [MoneyDisplayConfig.disabled],
      // which equals [defaultMoneyConfig] only while
      // `SettingsKeys.defaultMoneyLedgerEnabled` is false. The
      // constructor seeds the builder so the two agree by construction
      // and re-applying the defaults is provably not a change.
      final render = EditorRenderController();

      expect(
        render.applyMoneyConfig(EditorRenderController.defaultMoneyConfig),
        isFalse,
        reason: 'the builder already renders under the shipped defaults',
      );
      expect(
        render.applyMoneyConfig(
          const MoneyDisplayConfig(
            enabled: !SettingsKeys.defaultMoneyLedgerEnabled,
            startCents: SettingsKeys.defaultMoneyStartCents,
            currencySymbol: SettingsKeys.defaultMoneyCurrencySymbol,
            currencySuffix: SettingsKeys.defaultMoneyCurrencySuffix,
          ),
        ),
        isTrue,
        reason: 'flipping the ledger away from its default is a change',
      );
    });

    test('reports a change only when the value moved', () {
      final render = EditorRenderController();

      expect(render.applyMoneyConfig(_moneyEnabled), isTrue);
      expect(render.moneyConfig, _moneyEnabled);
      expect(
        render.applyMoneyConfig(
          const MoneyDisplayConfig(
            enabled: true,
            currencySymbol: 'lei',
            currencySuffix: true,
          ),
        ),
        isFalse,
        reason: 'a value-equal config is not a change',
      );
      expect(
        render.applyMoneyConfig(MoneyDisplayConfig.disabled),
        isTrue,
        reason: 'turning the ledger off is a change',
      );
    });

    test('the builder follows the applied config', () {
      final fixture = _MoneyFixture();
      addTearDown(fixture.dispose);

      expect(
        fixture.rendersMoney,
        isFalse,
        reason: 'the ledger is off by default',
      );

      fixture.render.applyMoneyConfig(_moneyEnabled);
      expect(fixture.rendersMoney, isTrue);

      fixture.render.applyMoneyConfig(MoneyDisplayConfig.disabled);
      expect(fixture.rendersMoney, isFalse);
    });

    test('an unchanged config still configures the builder', () {
      final fixture = _MoneyFixture();
      addTearDown(fixture.dispose);

      // Desync the builder behind the controller's back, the way a
      // skipped `configureMoney` would.
      fixture.render.spanBuilder.configureMoney(_moneyEnabled);
      expect(fixture.rendersMoney, isTrue);

      expect(
        fixture.render.applyMoneyConfig(fixture.render.moneyConfig),
        isFalse,
      );
      expect(
        fixture.rendersMoney,
        isFalse,
        reason: 'the builder must be reconfigured even when nothing changed',
      );
    });
  });

  group('colour palette', () {
    test('starts at the presets', () {
      expect(EditorRenderController().palette, MarkdownColorPalette.presets);
    });

    test('reports a change only when the value moved', () {
      final render = EditorRenderController();

      expect(render.applyPalette(_customPalette), isTrue);
      expect(render.palette, _customPalette);
      expect(
        render.applyPalette(MarkdownColorPalette.decode(_customSource)),
        isFalse,
        reason: 'a value-equal palette is not a change',
      );
      expect(render.applyPalette(MarkdownColorPalette.presets), isTrue);
    });

    test('the builder follows the applied palette', () {
      final fixture = _PaletteFixture();
      addTearDown(fixture.dispose);

      expect(
        fixture.visibleText,
        '{mine:hello} and x',
        reason: 'an unknown colour name renders literally',
      );

      fixture.render.applyPalette(_customPalette);
      expect(fixture.visibleText, 'hello and x');
    });

    test('an unchanged palette still configures the builder', () {
      final fixture = _PaletteFixture();
      addTearDown(fixture.dispose);

      fixture.render.spanBuilder.configureColors(_customPalette);
      expect(fixture.visibleText, 'hello and x');

      expect(fixture.render.applyPalette(fixture.render.palette), isFalse);
      expect(
        fixture.visibleText,
        '{mine:hello} and x',
        reason: 'the builder must be reconfigured even when nothing changed',
      );
    });
  });

  group('lineInFence', () {
    test('is false with no controller bound', () {
      expect(EditorRenderController().lineInFence(0), isFalse);
    });

    test('covers the delimiters and the interior', () {
      final controller = CodeLineEditingController.fromText(
        ['plain', '```', 'code', '```', 'after'].join('\n'),
      );
      addTearDown(controller.dispose);
      final render = EditorRenderController()..bind(controller);

      expect(
        [for (int i = 0; i < 5; i++) render.lineInFence(i)],
        [false, true, true, true, false],
      );
    });

    test('the body excludes the delimiters', () {
      final controller = CodeLineEditingController.fromText(
        ['plain', '```', 'code', '```', 'after'].join('\n'),
      );
      addTearDown(controller.dispose);
      final render = EditorRenderController()..bind(controller);

      // The narrow predicate: the ``` lines are still lines the user
      // types on, so a caller that leaves verbatim code alone must not
      // treat them as part of it.
      expect(
        [for (int i = 0; i < 5; i++) render.lineInFenceBody(i)],
        [false, false, true, false, false],
      );
    });

    test('the body is false with no controller bound', () {
      expect(EditorRenderController().lineInFenceBody(0), isFalse);
    });
  });

  group('buildSpan routing', () {
    testWidgets('live rendering styles the line', (tester) async {
      final fixture = await _pumpBuildContext(tester, '## Heading');
      addTearDown(fixture.dispose);

      final span = fixture.build(liveRendering: true);

      expect(_visibleText(span), 'Heading');
      expect(
        span.toPlainText(includePlaceholders: true),
        '## Heading',
        reason: 'styling conceals the hashes, it never removes them',
      );
    });

    testWidgets('live rendering off falls back to the ghost span', (
      tester,
    ) async {
      final fixture = await _pumpBuildContext(tester, '## {{topic}}');
      addTearDown(fixture.dispose);

      final span = fixture.build(liveRendering: false);

      expect(
        _visibleText(span),
        '## topic',
        reason: 'the hashes stay raw; only the ghost markers are concealed',
      );
      expect(span.toPlainText(includePlaceholders: true), '## {{topic}}');
    });

    testWidgets('live rendering off leaves a plain line alone', (tester) async {
      final fixture = await _pumpBuildContext(tester, 'just text');
      addTearDown(fixture.dispose);

      expect(
        identical(fixture.build(liveRendering: false), fixture.fallback),
        isTrue,
      );
    });

    testWidgets('a line the markdown builder declines falls through', (
      tester,
    ) async {
      // The ledger is off, so a money row is not a styled line: the ghost
      // builder gets it, and hands back the editor's own span.
      final fixture = await _pumpBuildContext(tester, r'$$');
      addTearDown(fixture.dispose);

      expect(
        identical(fixture.build(liveRendering: true), fixture.fallback),
        isTrue,
      );
    });

    testWidgets('a rebuilt but value-equal theme keeps the span memo', (
      tester,
    ) async {
      // An ancestor that builds its `ThemeData(...)` inside `build()` hands
      // over a fresh instance every frame. `buildSpan` resolves the theme
      // on every line of every layout pass, so if that instance became a
      // new render generation the memos would be dropped continuously.
      late BuildContext captured;
      Future<void> pumpTheme(Brightness brightness) => tester.pumpWidget(
        MaterialApp(
          home: Theme(
            data: ThemeData(useMaterial3: true, brightness: brightness),
            child: Builder(
              builder: (context) {
                captured = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      await pumpTheme(Brightness.light);
      final controller = CodeLineEditingController.fromText(
        ['pad', '- **bold** item', 'pad'].join('\n'),
      );
      addTearDown(controller.dispose);
      controller.selection = const CodeLineSelection.collapsed(
        index: 0,
        offset: 0,
      );
      final render = EditorRenderController()..bind(controller);
      TextSpan build() => render.buildSpan(
        context: captured,
        index: 1,
        codeLine: controller.codeLines[1],
        textSpan: TextSpan(text: controller.codeLines[1].text, style: _style),
        style: _style,
        liveRendering: true,
      );

      final firstTheme = Theme.of(captured);
      final first = build();

      await pumpTheme(Brightness.light);

      expect(
        identical(Theme.of(captured), firstTheme),
        isFalse,
        reason: 'the fixture must hand over a distinct theme instance',
      );
      expect(
        identical(build(), first),
        isTrue,
        reason: 'an equal generation must hit the span memo',
      );

      // The control: a generation that really moved does drop it.
      await pumpTheme(Brightness.dark);

      expect(identical(build(), first), isFalse);
    });
  });
}

const TextStyle _style = TextStyle(
  fontSize: 16.0,
  height: 1.4,
  color: Color(0xFF202124),
);

const Color _baseColor = Color(0xFF202124);

const MoneyDisplayConfig _moneyEnabled = MoneyDisplayConfig(
  enabled: true,
  currencySymbol: 'lei',
  currencySuffix: true,
);

const String _customSource = 'mine=ff112233';

final MarkdownColorPalette _customPalette = MarkdownColorPalette.decode(
  _customSource,
);

/// Lines whose ghost runs the fallback must rebuild: every one of them
/// has to come back with its code units intact. The emoji entry is a
/// surrogate pair plus a variation selector, which is where a rebuild
/// that thought in characters instead of code units would break.
const List<String> _ghostCorpus = [
  '{{ name }}',
  'before {{ a }} after',
  '{{a}}{{b}}',
  '{{  }}',
  '{{ }}',
  '- [ ] task {{ weight }}',
  '{{ \u{1F3CB}️ }} lift',
  'tail after {{ x }}',
  '{{ one }} middle {{ two }} end',
];

/// Lines with no ghost run: the fallback must hand back re_editor's own
/// span rather than allocating a new tree.
const List<String> _plainCorpus = [
  'plain line',
  '',
  '{{}}',
  'unclosed {{ x',
  '{ single }',
  '## heading',
];

TextSpan _ghost(String line) => EditorRenderController.ghostSpan(
  codeLine: CodeLine(line),
  textSpan: TextSpan(text: line, style: _style),
  style: _style,
  baseColor: _baseColor,
);

typedef _Leaf = ({String text, TextStyle? style});

List<_Leaf> _leaves(InlineSpan root) {
  final leaves = <_Leaf>[];
  void walk(InlineSpan span) {
    if (span is! TextSpan) return;
    final text = span.text;
    if (text != null && text.isNotEmpty) {
      leaves.add((text: text, style: span.style));
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      walk(child);
    }
  }

  walk(root);
  return leaves;
}

/// A marker leaf: transparent and shrunk to a 0.01 font size, which is
/// exactly what a concealed marker renders as.
bool _concealed(TextStyle? style) =>
    style != null &&
    style.color == const Color(0x00000000) &&
    style.fontSize == 0.01;

/// What the reader actually sees: every leaf that is not a concealed
/// marker.
String _visibleText(InlineSpan root) => _leaves(
  root,
).where((leaf) => !_concealed(leaf.style)).map((leaf) => leaf.text).join();

/// The renderer's theme generation, built straight from a [ThemeData] —
/// the span builder takes one of these, not a [BuildContext].
final EditorRenderContext _renderContext = EditorRenderContext.fromTheme(
  ThemeData(useMaterial3: true, brightness: Brightness.light),
  _style,
);

class _MoneyFixture {
  _MoneyFixture() {
    controller = CodeLineEditingController.fromText(
      ['pad', r'$= 500', r'$+ 20 lunch', r'$$', 'pad'].join('\n'),
    );
    controller.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 0,
    );
    render = EditorRenderController()..bind(controller);
  }

  late final CodeLineEditingController controller;
  late final EditorRenderController render;

  /// Whether the `$$` total row renders as a money row. With the ledger
  /// off the builder declines the line entirely.
  bool get rendersMoney {
    final span = render.spanBuilder.build(
      context: _renderContext,
      index: 3,
      codeLine: controller.codeLines[3],
    );
    return span != null;
  }

  void dispose() => controller.dispose();
}

class _PaletteFixture {
  _PaletteFixture() {
    // `{red:x}` is a preset, so the line is always a handled one — what
    // the palette decides is whether `mine` resolves alongside it.
    controller = CodeLineEditingController.fromText(
      ['pad', '{mine:hello} and {red:x}', 'pad'].join('\n'),
    );
    controller.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 0,
    );
    render = EditorRenderController()..bind(controller);
  }

  late final CodeLineEditingController controller;
  late final EditorRenderController render;

  /// The `{mine:…}` line as the reader sees it: `hello` once the palette
  /// knows the name, the raw run while it does not.
  String get visibleText {
    final span = render.spanBuilder.build(
      context: _renderContext,
      index: 1,
      codeLine: controller.codeLines[1],
    );
    expect(span, isNotNull, reason: 'the preset run makes this a styled line');
    return _visibleText(span!);
  }

  void dispose() => controller.dispose();
}

/// [EditorRenderController.buildSpan] is the one entry point that still
/// needs a real [BuildContext] (it resolves the theme), so these cases
/// pump a [Builder] to capture one.
class _BuildSpanFixture {
  _BuildSpanFixture(this.context, this.line) {
    controller = CodeLineEditingController.fromText(
      ['pad', line, 'pad'].join('\n'),
    );
    controller.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 0,
    );
    render = EditorRenderController()..bind(controller);
    fallback = TextSpan(text: line, style: _style);
  }

  final BuildContext context;
  final String line;
  late final CodeLineEditingController controller;
  late final EditorRenderController render;
  late final TextSpan fallback;

  TextSpan build({required bool liveRendering}) => render.buildSpan(
    context: context,
    index: 1,
    codeLine: controller.codeLines[1],
    textSpan: fallback,
    style: _style,
    liveRendering: liveRendering,
  );

  void dispose() => controller.dispose();
}

Future<_BuildSpanFixture> _pumpBuildContext(
  WidgetTester tester,
  String line,
) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return _BuildSpanFixture(captured, line);
}
