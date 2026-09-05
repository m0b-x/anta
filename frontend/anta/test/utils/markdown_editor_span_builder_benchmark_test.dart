@Tags(['benchmark'])
library;

import 'package:anta/utils/editor_render_context.dart';
import 'package:anta/utils/markdown_color_syntax.dart';
import 'package:anta/utils/markdown_editor_span_builder.dart';
import 'package:anta/utils/money_display_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Span-build timings for the live markdown editor.
///
/// **Tagged `benchmark` and excluded from the default run** (see
/// `dart_test.yaml`) — wall-clock numbers are not a pass/fail signal, they
/// move with background load and debug-vs-release. Run deliberately:
///
/// ```powershell
/// flutter test test/utils/markdown_editor_span_builder_benchmark_test.dart --tags benchmark --run-skipped
/// ```
///
/// The assertions are catastrophe-only (they catch an accidental O(n²) or a
/// dead memo, not a 30 % regression). Read the printed table for the signal.
void main() {
  // No widget pumping: the renderer takes an [EditorRenderContext]. The
  // binding is still needed because painted runs lay a `TextPainter`
  // out through dart:ui.
  TestWidgetsFlutterBinding.ensureInitialized();

  const lineCount = 40;
  const iterations = 40;
  const stormLineCount = 20;
  const stormIterations = 20;

  test('span build of $lineCount list lines, cold vs warm', () {
    final lines = _listLines(lineCount);
    final controller = CodeLineEditingController.fromText(lines.join('\n'));
    addTearDown(controller.dispose);

    final builder = MarkdownEditorSpanBuilder()..bind(controller);
    builder.configureMoney(MoneyDisplayConfig.disabled);
    controller.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 0,
    );

    int buildAll() {
      var built = 0;
      for (var i = 0; i < lineCount; i++) {
        final span = builder.build(
          context: _renderContext,
          index: i,
          codeLine: controller.codeLines[i],
        );
        if (span != null) built++;
      }
      return built;
    }

    // Warm-up outside the measurement: first touch also builds the shared
    // line index (fence roles + task aggregates) for the whole document.
    expect(buildAll(), lineCount);

    final coldWatch = Stopwatch();
    var coldBuilt = 0;
    for (var run = 0; run < iterations; run++) {
      // Clearing the palette-keyed generation drops both span memos while
      // leaving the line index warm, so this measures span construction
      // alone — the state right after a theme/settings change.
      builder.configureColors(
        run.isEven ? _altPalette : MarkdownColorPalette.presets,
      );
      coldWatch.start();
      coldBuilt += buildAll();
      coldWatch.stop();
    }

    final warmWatch = Stopwatch();
    var warmBuilt = 0;
    for (var run = 0; run < iterations; run++) {
      warmWatch.start();
      warmBuilt += buildAll();
      warmWatch.stop();
    }

    expect(coldBuilt, lineCount * iterations);
    expect(warmBuilt, lineCount * iterations);

    final coldPerPass = coldWatch.elapsedMicroseconds / iterations;
    final warmPerPass = warmWatch.elapsedMicroseconds / iterations;

    // ignore: avoid_print
    print(
      '\n=== MarkdownEditorSpanBuilder — $lineCount list lines, '
      '$iterations passes ===\n'
      '  cold (memo cleared) : ${coldPerPass.toStringAsFixed(1)} us/pass, '
      '${(coldPerPass / lineCount).toStringAsFixed(2)} us/line\n'
      '  warm (memo hit)     : ${warmPerPass.toStringAsFixed(1)} us/pass, '
      '${(warmPerPass / lineCount).toStringAsFixed(2)} us/line\n'
      '  speedup             : '
      '${(coldPerPass / (warmPerPass == 0 ? 1 : warmPerPass)).toStringAsFixed(1)}x',
    );

    // Catastrophe-only bounds.
    expect(
      coldPerPass / lineCount,
      lessThan(2000),
      reason: 'a cold span build should be well under 2 ms per line',
    );
    expect(
      warmPerPass / lineCount,
      lessThan(200),
      reason: 'a warm build is an LRU probe; 200 us per line means no memo',
    );
    expect(
      warmPerPass,
      lessThan(coldPerPass),
      reason: 'the span memo must make a repeat pass cheaper',
    );
  });

  // The emphasis pairing worst case: every `*` closes and none opens, so
  // every closer searches the whole delimiter stack unless the pairing
  // loop keeps CommonMark's `openers_bottom` bound. Kept near the styled
  // line-length ceiling, where an O(n²) loop is most visible.
  test('span build of $stormLineCount unpairable-delimiter lines, cold', () {
    final lines = _delimiterStormLines(stormLineCount);
    final controller = CodeLineEditingController.fromText(lines.join('\n'));
    addTearDown(controller.dispose);

    final builder = MarkdownEditorSpanBuilder()..bind(controller);
    builder.configureMoney(MoneyDisplayConfig.disabled);
    controller.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 0,
    );

    int buildAll() {
      var built = 0;
      for (var i = 0; i < stormLineCount; i++) {
        final span = builder.build(
          context: _renderContext,
          index: i,
          codeLine: controller.codeLines[i],
        );
        if (span != null) built++;
      }
      return built;
    }

    expect(buildAll(), stormLineCount);

    final watch = Stopwatch();
    var built = 0;
    for (var run = 0; run < stormIterations; run++) {
      builder.configureColors(
        run.isEven ? _altPalette : MarkdownColorPalette.presets,
      );
      watch.start();
      built += buildAll();
      watch.stop();
    }
    expect(built, stormLineCount * stormIterations);

    final perPass = watch.elapsedMicroseconds / stormIterations;

    // ignore: avoid_print
    print(
      '\n=== MarkdownEditorSpanBuilder — $stormLineCount unpairable-delimiter '
      'lines (${lines.first.length} chars each), '
      '$stormIterations cold passes ===\n'
      '  cold (memo cleared) : ${perPass.toStringAsFixed(1)} us/pass, '
      '${(perPass / stormLineCount).toStringAsFixed(2)} us/line',
    );

    // Catastrophe-only bound: the O(n²) pairing loop cost ~800 us per line
    // of this shape before the `openers_bottom` bound landed.
    expect(
      perPass / stormLineCount,
      lessThan(2000),
      reason: 'a cold span build should be well under 2 ms per line',
    );
  });

  test('span build of $lineCount display-money lines, warm', () {
    final lines = <String>[..._moneyOps, ..._moneyDisplayLines(lineCount)];
    final firstDisplay = _moneyOps.length;
    final controller = CodeLineEditingController.fromText(lines.join('\n'));
    addTearDown(controller.dispose);

    final builder = MarkdownEditorSpanBuilder()..bind(controller);
    builder.configureMoney(_moneyEnabled);
    controller.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 0,
    );

    int buildDisplayLines() {
      var built = 0;
      for (var i = 0; i < lineCount; i++) {
        final index = firstDisplay + i;
        final span = builder.build(
          context: _renderContext,
          index: index,
          codeLine: controller.codeLines[index],
        );
        if (span != null) built++;
      }
      return built;
    }

    // Warm-up outside the measurement: first touch builds the shared line
    // index (fence roles, task aggregates, the money ledger) and fills the
    // positional span memo, so the measured passes are all memo hits.
    expect(buildDisplayLines(), lineCount);

    final watch = Stopwatch();
    var built = 0;
    for (var run = 0; run < iterations; run++) {
      watch.start();
      built += buildDisplayLines();
      watch.stop();
    }
    expect(built, lineCount * iterations);

    final perPass = watch.elapsedMicroseconds / iterations;

    // ignore: avoid_print
    print(
      '\n=== MarkdownEditorSpanBuilder — $lineCount display-money lines, '
      '$iterations warm passes ===\n'
      '  warm (positional memo hit) : ${perPass.toStringAsFixed(1)} us/pass, '
      '${(perPass / lineCount).toStringAsFixed(2)} us/line',
    );

    // Catastrophe-only bound.
    expect(
      perPass / lineCount,
      lessThan(200),
      reason: 'a warm build is an LRU probe; 200 us per line means no memo',
    );
  });
}

const MoneyDisplayConfig _moneyEnabled = MoneyDisplayConfig(
  enabled: true,
  currencySymbol: 'lei',
  currencySuffix: true,
);

/// Op rows above the measured block so every display row has a balance,
/// a net change, an entry window and a checkpoint window to compute.
const List<String> _moneyOps = <String>[
  r'$= 500',
  r'$+ 12.50 coffee',
  r'$- 8 lunch',
  r'$= 700',
  r'$+ 20 groceries',
  r'$- 5 bus',
];

/// The four display kinds, each distinct in text so the positional memo
/// holds one entry per line (mirroring a real ledger note's mix).
List<String> _moneyDisplayLines(int count) => List<String>.generate(count, (i) {
  switch (i % 4) {
    case 0:
      return '\$\$ Running sum $i: \$';
    case 1:
      return '\$? net change $i';
    case 2:
      return '\$^ 2 last two entries $i';
    default:
      return '\$~ 2 teal: Change $i: \$';
  }
});

const TextStyle _baseStyle = TextStyle(
  fontSize: 16.0,
  height: 1.4,
  color: Color(0xFF202124),
);

/// The renderer's theme generation, built straight from a [ThemeData] —
/// the page resolves one of these per generation and hands the same
/// instance to every line, which is what these passes reproduce.
final EditorRenderContext _renderContext = EditorRenderContext.fromTheme(
  ThemeData(useMaterial3: true, brightness: Brightness.light),
  _baseStyle,
);

final MarkdownColorPalette _altPalette = MarkdownColorPalette.decode(
  'benchcold=ff112233',
);

/// Near-ceiling lines of `a* ` repeats: every `*` is flanked so it can
/// only close, so no closer ever finds an opener. Each line carries its
/// own prefix so the positional span memo holds one entry per line, and
/// one real `**b**` at the end so the builder actually emits a span.
List<String> _delimiterStormLines(int count) =>
    List<String>.generate(count, (i) => 'row$i ${'a* ' * 1359}**b**');

/// A realistic training-log list block: plain bullets, nested bullets,
/// ordered rows, task boxes, and inline runs — the shapes the editor
/// actually rebuilds while scrolling.
List<String> _listLines(int count) => List<String>.generate(count, (i) {
  switch (i % 5) {
    case 0:
      return '- Squat ${3 + i % 3}x5 @ ${60 + i} kg';
    case 1:
      return '  - tempo **3-1-1**, `RPE ${6 + i % 3}`';
    case 2:
      return '${i ~/ 5 + 1}. Accessory block #legs';
    case 3:
      return '- [${i % 2 == 0 ? 'x' : ' '}] Mobility ${i}m';
    default:
      return '    - note: [form cue](https://example.com/cue/$i)';
  }
});
