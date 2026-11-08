import 'package:anta/constants/markdown_constants.dart';
import 'package:anta/utils/editor_render_context.dart';
import 'package:anta/utils/markdown_callout_syntax.dart';
import 'package:anta/utils/markdown_editor_span_builder.dart';
import 'package:anta/utils/markdown_list_syntax.dart';
import 'package:anta/utils/money_display_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import '../goldens/support/golden_fonts.dart';

/// Pins the live editor's visible list depth (D9–D16 of
/// docs/editor-list-nesting-roadmap.md): a nested item's glyph sits at
/// exactly level × [MarkdownConstants.listIndentPerLevelEm] ems from where
/// its indent starts, whatever spaces and tabs got it there; the content,
/// the hanging indent and the line height never move between the reveal
/// states; and the indent keeps its source code units.
///
/// Every line is laid out through the fork's own paragraph provider at a
/// phone's text width, in Roboto from the SDK cache rather than the test
/// font, so the letter spacing is derived from the advances the device
/// measures; the lone tab's first glyph also catches an engine change to
/// SkParagraph's half-spacing shift of a letter-spaced first glyph.
void main() {
  setUpAll(loadGoldenFonts);

  // 1.0, 1.3 and linear 2.0 of the 16 px editor font.
  const sizes = [16.0, 20.8, 32.0];

  group('indent depth', () {
    const cases = <({String label, String line, int level, bool money})>[
      (label: 'two spaces', line: '  - a', level: 1, money: false),
      (label: 'three spaces', line: '   - a', level: 1, money: false),
      (label: 'four spaces', line: '    - a', level: 2, money: false),
      (label: 'a lone tab', line: '\t- a', level: 1, money: false),
      (label: 'two tabs', line: '\t\t- a', level: 2, money: false),
      (label: 'a quoted nested item', line: '>   - b', level: 1, money: false),
      (label: 'a nested money row', line: r'  - $+ 5 x', level: 1, money: true),
      (label: 'a nested task', line: '  - [ ] t', level: 1, money: false),
    ];

    for (final size in sizes) {
      for (final c in cases) {
        test('${c.label} steps one level per '
            '${MarkdownConstants.listIndentPerLevelEm} em at $size px', () {
          final quoted = MarkdownCalloutSyntax.quotedListItem(c.line);
          final indentStart = quoted?.base ?? 0;
          final indent = quoted?.item.indent ?? _leadingBlanks(c.line);
          final indentEnd = indentStart + indent.length;
          final level = size * MarkdownConstants.listIndentPerLevelEm;

          final glyphX = <bool, double>{};
          for (final reveal in const [false, true]) {
            final where = '${c.label} [reveal=$reveal, $size px]';
            final span = _build(c.line, size, reveal: reveal, money: c.money);

            final plain = span.toPlainText(includePlaceholders: true);
            expect(plain.length, c.line.length, reason: where);
            expect(
              plain.substring(indentStart, indentEnd),
              indent,
              reason: 'the indent keeps its source units: $where',
            );

            final paragraph = _layout(span, size);
            expect(
              _caretX(paragraph, 0),
              0.0,
              reason: 'the caret at the line start stays at 0: $where',
            );
            // From the line start, or from the quote run's end.
            final x =
                _caretX(paragraph, indentEnd) -
                (quoted == null ? 0 : _caretX(paragraph, indentStart));
            expect(x, closeTo(c.level * level, 0.5), reason: where);
            glyphX[reveal] = x;
          }
          expect(
            glyphX[true],
            closeTo(glyphX[false]!, 0.01),
            reason: 'the indent never shifts on caret entry: ${c.label}',
          );
        });
      }
    }

    for (final size in sizes) {
      test('a lone tab draws its first glyph half its spacing in at '
          '$size px', () {
        // D16: the tab is the line's first glyph and must be spaced, so
        // SkParagraph starts its run at half the spacing while the caret
        // at offset 0 stays at 0; the 1.5 divisor puts the glyph on the
        // column anyway. A change in either number is an engine change.
        final tab = _tabAdvance(size);
        final spacing =
            (size * MarkdownConstants.listIndentPerLevelEm - tab) / 1.5;
        for (final reveal in const [false, true]) {
          final paragraph = _layout(
            _build('\t- a', size, reveal: reveal, money: false),
            size,
          );
          final run = paragraph.getRangeRects(
            const TextRange(start: 0, end: 1),
          );
          expect(_caretX(paragraph, 0), 0.0, reason: 'reveal=$reveal');
          expect(
            run.first.left,
            closeTo(spacing / 2, 0.01),
            reason: 'reveal=$reveal',
          );
        }
      });
    }
  });

  group('content start on caret entry', () {
    // D15: the raw marker a revealed bullet draws is narrower or wider than
    // the bold glyph a concealed one draws; the gap after it absorbs the
    // difference so the content and the hanging indent stay put.
    const bullets =
        <
          ({
            String line,
            int indentStart,
            int marker,
            int content,
            int level,
            bool money,
          })
        >[
          (
            line: '- a',
            indentStart: 0,
            marker: 0,
            content: 2,
            level: 0,
            money: false,
          ),
          (
            line: '  - a',
            indentStart: 0,
            marker: 2,
            content: 4,
            level: 1,
            money: false,
          ),
          (
            line: '    - a',
            indentStart: 0,
            marker: 4,
            content: 6,
            level: 2,
            money: false,
          ),
          (
            line: '* a',
            indentStart: 0,
            marker: 0,
            content: 2,
            level: 0,
            money: false,
          ),
          (
            line: '+ a',
            indentStart: 0,
            marker: 0,
            content: 2,
            level: 0,
            money: false,
          ),
          (
            line: '• a',
            indentStart: 0,
            marker: 0,
            content: 2,
            level: 0,
            money: false,
          ),
          (
            line: '> - a',
            indentStart: 2,
            marker: 2,
            content: 4,
            level: 0,
            money: false,
          ),
          (
            line: r'  - $+ 5 x',
            indentStart: 0,
            marker: 2,
            content: 4,
            level: 1,
            money: true,
          ),
        ];

    for (final size in sizes) {
      for (final c in bullets) {
        test('`${c.line}` keeps its content x at $size px', () {
          final prefixX = <bool, double>{};
          final contentX = <bool, double>{};
          for (final reveal in const [false, true]) {
            final where = '${c.line} [reveal=$reveal, $size px]';
            final span = _build(c.line, size, reveal: reveal, money: c.money);

            final plain = span.toPlainText(includePlaceholders: true);
            expect(plain.length, c.line.length, reason: where);
            expect(
              plain.substring(c.indentStart, c.marker),
              c.line.substring(c.indentStart, c.marker),
              reason: 'the indent keeps its source units: $where',
            );
            expect(
              plain[c.marker],
              reveal
                  ? c.line[c.marker]
                  : c.level % 3 == 2
                  ? '￼'
                  : MarkdownListSyntax.bulletGlyph(c.level),
              reason: 'the marker is raw on reveal, the glyph off it: $where',
            );
            expect(
              plain.substring(c.marker + 1, c.content),
              c.line.substring(c.marker + 1, c.content),
              reason: 'the gap keeps its source units: $where',
            );
            expect(span, isA<CodeHangingTextSpan>(), reason: where);
            expect(
              (span as CodeHangingTextSpan).hangingChars,
              c.content,
              reason: 'the hanging prefix ends at the content start: $where',
            );

            final paragraph = _layout(span, size);
            final from = _caretX(paragraph, c.indentStart);
            expect(
              _caretX(paragraph, c.marker) - from,
              closeTo(
                c.level * size * MarkdownConstants.listIndentPerLevelEm,
                0.5,
              ),
              reason: 'the glyph keeps its N3 column: $where',
            );
            // The marker and gap's own advance, unfloored, from the quote
            // run's end: the bars themselves differ concealed and
            // revealed, which is not this rule's.
            prefixX[reveal] =
                paragraph
                    .getRangeRects(TextRange(start: c.marker, end: c.content))
                    .last
                    .right -
                from;
            contentX[reveal] = _caretX(paragraph, c.content);
          }
          expect(
            prefixX[true],
            closeTo(prefixX[false]!, 0.01),
            reason: 'marker plus gap is one width in both states: ${c.line}',
          );
          if (c.indentStart == 0) {
            expect(
              contentX[true],
              contentX[false],
              reason: 'the content never shifts on caret entry: ${c.line}',
            );
          }
        });
      }
    }

    // A task keeps its painted box on the caret line and an ordered item
    // draws the same digits in both states; neither may move either.
    const others = <({String line, int content})>[
      (line: '  - [ ] t', content: 8),
      (line: '  1. a', content: 5),
    ];
    for (final size in sizes) {
      for (final c in others) {
        test('`${c.line}` keeps its content x at $size px', () {
          final contentX = <bool, double>{};
          for (final reveal in const [false, true]) {
            final span = _build(c.line, size, reveal: reveal, money: false);
            expect(
              span.toPlainText(includePlaceholders: true).length,
              c.line.length,
            );
            expect((span as CodeHangingTextSpan).hangingChars, c.content);
            contentX[reveal] = _caretX(_layout(span, size), c.content);
          }
          expect(
            contentX[true],
            closeTo(contentX[false]!, 0.01),
            reason: 'the content never shifts on caret entry: ${c.line}',
          );
        });
      }
    }
  });

  group('the painted square', () {
    // D17: a level-2 bullet paints its square over one placeholder unit in
    // a box as wide as the bold `•`, so its gap and content column are a
    // dot line's shifted by the indent.
    for (final size in sizes) {
      test('`    - c` keeps a dot line\'s content column at $size px', () {
        final indent = 2 * size * MarkdownConstants.listIndentPerLevelEm;
        final dotContent = _caretX(
          _layout(_build('- c', size, reveal: false, money: false), size),
          2,
        );
        final dotHeight = _layout(
          _build('- c', size, reveal: false, money: false),
          size,
        ).preferredLineHeight;
        final contentX = <bool, double>{};
        for (final reveal in const [false, true]) {
          final where = 'reveal=$reveal, $size px';
          final span = _build('    - c', size, reveal: reveal, money: false);
          final plain = span.toPlainText(includePlaceholders: true);
          expect(plain, reveal ? '    - c' : '    ￼ c', reason: where);

          final paragraph = _layout(span, size);
          expect(
            _caretX(paragraph, 4),
            closeTo(indent, 0.5),
            reason: 'the square keeps its N3 column: $where',
          );
          expect(
            paragraph.preferredLineHeight,
            dotHeight,
            reason: 'the square never grows the line: $where',
          );
          contentX[reveal] = _caretX(paragraph, 6);
        }
        expect(
          contentX[false]! - indent,
          closeTo(dotContent, 0.01),
          reason: 'the content sits where a `•` line\'s does at $size px',
        );
        expect(
          contentX[true],
          closeTo(contentX[false]!, 0.01),
          reason: 'the content never shifts on caret entry at $size px',
        );
      });
    }
  });

  group('quote content on caret entry', () {
    // D18: the bars and the raw `>`s differ in advance; the gap after the
    // run absorbs the run's difference so the content keeps its x.
    const quotes = <({String line, int content})>[
      (line: '> - a', content: 4),
      (line: '>   - b', content: 6),
      (line: '> plain text', content: 2),
      (line: '> > deep', content: 4),
    ];
    for (final size in sizes) {
      for (final c in quotes) {
        test('`${c.line}` keeps its content x at $size px', () {
          final contentX = <bool, double>{};
          for (final reveal in const [false, true]) {
            final span = _build(c.line, size, reveal: reveal, money: false);
            expect(
              span.toPlainText(includePlaceholders: true).length,
              c.line.length,
              reason: 'reveal=$reveal',
            );
            contentX[reveal] = _caretX(_layout(span, size), c.content);
          }
          expect(
            contentX[true],
            closeTo(contentX[false]!, 0.01),
            reason: 'the content never shifts on caret entry: ${c.line}',
          );
        });
      }
    }
  });

  group('line height', () {
    const lines = [
      '- a',
      '  - a',
      '   - a',
      '    - a',
      '> plain text',
      '> > deep',
      '\t- a',
      '\t\t- a',
      '* a',
      '+ a',
      '• a',
      '> - a',
      '>   - b',
      '  - [ ] t',
      '  1. a',
    ];
    for (final size in sizes) {
      test('is one value at every depth and in both states at $size px', () {
        final heights = <double>{};
        for (final reveal in const [false, true]) {
          for (final line in lines) {
            heights.add(
              _layout(
                _build(line, size, reveal: reveal, money: false),
                size,
              ).preferredLineHeight,
            );
          }
          heights.add(
            _layout(
              _build(r'  - $+ 5 x', size, reveal: reveal, money: true),
              size,
            ).preferredLineHeight,
          );
        }
        expect(heights, hasLength(1), reason: '$heights');
      });
    }
  });

  group('wrapped rows', () {
    for (final size in sizes) {
      test('hang under the content of a nested item at $size px', () {
        const line = '  - $_long';
        for (final reveal in const [false, true]) {
          final where = 'reveal=$reveal, $size px';
          final paragraph = _layout(
            _build(line, size, reveal: reveal, money: false),
            size,
          );
          expect(paragraph.lineCount, greaterThanOrEqualTo(3), reason: where);
          final content = _caretX(paragraph, 4);
          final lefts = _rowLefts(paragraph, 4, line.length);
          expect(lefts, hasLength(paragraph.lineCount), reason: where);
          for (final left in lefts) {
            expect(left, closeTo(content, 0.01), reason: where);
          }
        }
      });
    }

    // D14: past half the viewport the fork lays the line out as one
    // paragraph, so its wrapped rows start at 0; at 1.3 they still hang.
    const deep = [
      (label: 'a level-3 task', line: '      - [ ] $_long', content: 12),
      (label: 'a level-4 bullet', line: '        - $_long', content: 10),
    ];
    for (final c in deep) {
      for (final size in const [20.8, 32.0]) {
        final hangs = size < 32.0;
        test('${c.label} ${hangs ? 'hangs' : 'falls back'} at $size px', () {
          for (final reveal in const [false, true]) {
            final where = 'reveal=$reveal';
            final provider = _provider(size);
            final paragraph = provider.build(
              _build(c.line, size, reveal: reveal, money: false),
              _textWidth,
            );
            final lefts = _rowLefts(paragraph, c.content, c.line.length);
            expect(provider.isHanging(paragraph), hangs, reason: where);
            expect(paragraph.lineCount, greaterThanOrEqualTo(3), reason: where);
            for (final left in hangs ? lefts : lefts.skip(1)) {
              expect(
                left,
                closeTo(hangs ? _caretX(paragraph, c.content) : 0.0, 0.01),
                reason: where,
              );
            }
          }
        });
      }
    }
  });
}

/// A phone's text width: 360 dp less the editor's 20 dp left and 36 dp
/// right padding. The fork's hanging rule allows a prefix up to half.
const double _textWidth = 304;

const String _long =
    'stretch the hamstrings for thirty seconds on each side, then roll '
    'the calves and the upper back before the first working set of squats';

String _leadingBlanks(String line) {
  var i = 0;
  while (i < line.length && (line[i] == ' ' || line[i] == '\t')) {
    i++;
  }
  return line.substring(0, i);
}

TextStyle _style(double size) => TextStyle(
  fontFamily: 'Roboto',
  fontSize: size,
  height: MarkdownConstants.lineHeight,
  color: const Color(0xFF202124),
);

CodeParagraphProviderForTesting _provider(double size) =>
    CodeParagraphProviderForTesting()..updateBaseStyle(_style(size));

IParagraph _layout(TextSpan span, double size) =>
    _provider(size).build(span, _textWidth);

double _caretX(IParagraph paragraph, int offset) =>
    paragraph.getOffset(TextPosition(offset: offset))!.dx;

/// The left edge of every visual row the range `[start, end)` covers, in
/// row order.
List<double> _rowLefts(IParagraph paragraph, int start, int end) {
  final byTop = <double, double>{};
  for (final rect in paragraph.getRangeRects(
    TextRange(start: start, end: end),
  )) {
    final top = rect.top.roundToDouble();
    final left = byTop[top];
    if (left == null || rect.left < left) byTop[top] = rect.left;
  }
  final tops = byTop.keys.toList()..sort();
  return [for (final top in tops) byTop[top]!];
}

/// The tab advance the renderer measures, through a plain [TextPainter].
double _tabAdvance(double size) {
  final painter = TextPainter(
    text: TextSpan(text: '\t|', style: _style(size)),
    textDirection: TextDirection.ltr,
  )..layout();
  addTearDown(painter.dispose);
  return painter.getOffsetForCaret(const TextPosition(offset: 1), Rect.zero).dx;
}

const MoneyDisplayConfig _money = MoneyDisplayConfig(
  enabled: true,
  currencySymbol: 'lei',
  currencySuffix: true,
);

/// Builds [line] as the second line of a document, the caret on the pad
/// line above it (concealed) or at the line's end (revealed — a task's
/// box stays painted there, as it does on the caret line).
TextSpan _build(
  String line,
  double size, {
  required bool reveal,
  required bool money,
}) {
  final controller = CodeLineEditingController.fromText('\n$line');
  addTearDown(controller.dispose);
  final builder = MarkdownEditorSpanBuilder()..bind(controller);
  builder.configureMoney(money ? _money : MoneyDisplayConfig.disabled);
  controller.selection = CodeLineSelection.collapsed(
    index: reveal ? 1 : 0,
    offset: reveal ? line.length : 0,
  );
  return builder.build(
    context: EditorRenderContext.fromTheme(
      ThemeData(useMaterial3: true, brightness: Brightness.light),
      _style(size),
    ),
    index: 1,
    codeLine: controller.codeLines[1],
  )!;
}
