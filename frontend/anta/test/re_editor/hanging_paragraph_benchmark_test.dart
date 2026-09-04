@Tags(['benchmark'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Paragraph-layout timings for the fork's hanging-indent path — the work a
/// screenful of list lines pays on every cold layout pass (a style change, a
/// theme switch, the first frame after a note opens).
///
/// **Tagged `benchmark` and excluded from the default run** (see
/// `dart_test.yaml`) because wall-clock numbers are not a pass/fail signal.
/// Run it deliberately when you want the numbers:
///
/// ```powershell
/// flutter test test/re_editor/hanging_paragraph_benchmark_test.dart --tags benchmark --run-skipped
/// ```
///
/// The cold row is the one the marker measurement cache moves: every pass
/// starts from an empty cache, so the paragraph caches never serve, while
/// the handful of distinct markers repeat across the 40 lines inside the
/// pass. The warm row is the identity-cache hit — it must stay flat.
///
/// The assertions are catastrophe-only; read the printed table for the real
/// signal.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const int lineCount = 40;
  const int iterations = 40;
  const double maxWidth = 360;

  test('hanging paragraph layout of $lineCount list lines, cold vs warm', () {
    final provider = CodeParagraphProviderForTesting()
      ..updateBaseStyle(_baseStyle);
    final List<TextSpan> spans = _listLineSpans(lineCount);

    int buildAll() {
      var wrapped = 0;
      for (final TextSpan span in spans) {
        if (provider.build(span, maxWidth).lineCount > 1) {
          wrapped++;
        }
      }
      return wrapped;
    }

    // Warm-up outside the measurement, and a check that the corpus really
    // exercises the wrapping path the hanging layout exists for.
    expect(buildAll(), greaterThan(0));

    final coldWatch = Stopwatch();
    for (int run = 0; run < iterations; run++) {
      provider.clearCache();
      coldWatch.start();
      buildAll();
      coldWatch.stop();
    }

    final warmWatch = Stopwatch();
    for (int run = 0; run < iterations; run++) {
      warmWatch.start();
      buildAll();
      warmWatch.stop();
    }

    final double coldPerPass = coldWatch.elapsedMicroseconds / iterations;
    final double warmPerPass = warmWatch.elapsedMicroseconds / iterations;

    // ignore: avoid_print
    print(
      '\n=== Hanging paragraphs — $lineCount list lines, '
      '$iterations passes ===\n'
      '  cold (cache cleared) : ${coldPerPass.toStringAsFixed(1)} us/pass, '
      '${(coldPerPass / lineCount).toStringAsFixed(2)} us/line\n'
      '  warm (identity hit)  : ${warmPerPass.toStringAsFixed(1)} us/pass, '
      '${(warmPerPass / lineCount).toStringAsFixed(2)} us/line\n'
      '  speedup              : '
      '${(coldPerPass / (warmPerPass == 0 ? 1 : warmPerPass)).toStringAsFixed(1)}x',
    );

    expect(
      coldPerPass / lineCount,
      lessThan(5000),
      reason: 'a cold line layout should be well under 5 ms',
    );
    expect(
      warmPerPass / lineCount,
      lessThan(200),
      reason:
          'a warm build is a pointer-hash probe; 200 us per line '
          'means the identity cache is dead',
    );
  });
}

const TextStyle _baseStyle = TextStyle(
  fontSize: 15,
  height: 1.4,
  color: Color(0xFF202124),
);

/// A realistic list block: plain bullets, ordered rows, task boxes with a
/// painted marker, and one nesting level — with content long enough that
/// several lines soft-wrap at the benchmark's width.
List<TextSpan> _listLineSpans(int count) => List<TextSpan>.generate(count, (
  int i,
) {
  final String content = i.isEven
      ? 'Squat ${3 + i % 3}x5 at ${60 + i} kg, belt on for the top set'
      : 'Mobility ${i}m';
  switch (i % 4) {
    case 0:
      return _hanging(
        hangingChars: 2,
        markerChildren: const [TextSpan(text: '• ', style: _baseStyle)],
        content: content,
      );
    case 1:
      return _hanging(
        hangingChars: 3,
        markerChildren: [TextSpan(text: '${i ~/ 4 + 1}. ', style: _baseStyle)],
        content: content,
      );
    case 2:
      return _hanging(
        hangingChars: 6,
        markerChildren: const [
          TextSpan(text: '- ', style: _baseStyle),
          _BenchBoxSpan(side: 12),
          TextSpan(text: ' ] ', style: _baseStyle),
        ],
        content: content,
      );
    default:
      return _hanging(
        hangingChars: 6,
        markerChildren: const [TextSpan(text: '    • ', style: _baseStyle)],
        content: content,
      );
  }
});

CodeHangingTextSpan _hanging({
  required int hangingChars,
  required List<InlineSpan> markerChildren,
  required String content,
}) => CodeHangingTextSpan(
  hangingChars: hangingChars,
  style: _baseStyle,
  children: [
    ...markerChildren,
    TextSpan(text: content, style: _baseStyle),
  ],
);

/// Stands in for the app's checkbox span: one code unit, painted by the
/// paragraph, value-equal so equal markers share one measurement.
class _BenchBoxSpan extends CodeInlinePaintSpan {
  const _BenchBoxSpan({required double side})
    : super(width: side, height: side);

  @override
  void paint(Canvas canvas, Rect rect) {}

  @override
  bool operator ==(Object other) =>
      other is _BenchBoxSpan && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}
