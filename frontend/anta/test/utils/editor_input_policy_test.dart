import 'package:anta/utils/editor_input_policy.dart';
import 'package:anta/utils/markdown_color_syntax.dart';
import 'package:anta/utils/markdown_editor_span_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// The live editor's input policy, one row per rule.
///
/// The wrapper's tap zones used to be testable only by geometry against a
/// mounted `CodeEditor` (see `modern_editor_wrapper_tag_tap_test.dart`),
/// which pins that the zones are *wired*. What they *are* — every
/// pass-through rule, every zone boundary, and the precedence between
/// them — belongs here, where a row costs a millisecond instead of a
/// pumped frame, and where a rule can be stated instead of aimed at.
void main() {
  const palette = MarkdownColorPalette.presets;
  const lineIndex = 3;

  /// A `[docs](https://x.dev)` link at `[2, 23)`, url at `[9, 22)`.
  const linkLine = 'a [docs](https://x.dev) b';

  /// A `#project` tag at `[4, 12)`.
  const tagLine = 'see #project now';

  /// A `{{ … }}` ghost run at `[4, 14)`.
  const ghostLine = 'see {{ name }} now';

  group('resolveTap', () {
    final rows = <TapRow>[
      // --- pass-through rules -------------------------------------------
      tapRow('an out-of-range line index passes through', expected: null),
      tapRow(
        'a revealed (caret) line passes through — its markdown is raw',
        text: tagLine,
        offset: 6,
        revealed: true,
      ),
      tapRow(
        'a fence line passes through — fence text renders raw',
        text: tagLine,
        offset: 6,
        inFence: true,
      ),
      tapRow(
        'a line past maxStyledLineLength passes through',
        text: tagLine.padRight(
          MarkdownEditorSpanBuilder.maxStyledLineLength + 1,
          'x',
        ),
        offset: 6,
      ),
      tapRow(
        'a line exactly at maxStyledLineLength still resolves',
        text: tagLine.padRight(
          MarkdownEditorSpanBuilder.maxStyledLineLength,
          'x',
        ),
        offset: 6,
        expected: const EditorOpenTagAction('#project'),
      ),
      tapRow(
        'a tap clamped to the line-end offset passes through',
        text: tagLine,
        offset: tagLine.length,
      ),
      tapRow(
        'a tap past the line end passes through',
        text: tagLine,
        offset: tagLine.length + 40,
      ),

      // --- ghosts win ----------------------------------------------------
      tapRow(
        'a tap inside a ghost run passes through — the tag in it loses',
        text: '{{ #project }}',
        offset: 6,
      ),
      tapRow(
        'a tap inside a ghost run passes through — the link in it loses',
        text: '{{ [docs](https://x.dev) }}',
        offset: 7,
      ),
      tapRow(
        'a tap outside the ghost on the same line still resolves',
        text: '$ghostLine #project',
        offset: 21,
        expected: const EditorOpenTagAction('#project'),
      ),

      // --- link zone -----------------------------------------------------
      tapRow(
        "the link construct's opening boundary passes through",
        text: linkLine,
        offset: 2,
      ),
      tapRow(
        "the link construct's closing boundary passes through",
        text: linkLine,
        offset: 23,
      ),
      tapRow(
        'a tap inside the link text opens the url',
        text: linkLine,
        offset: 5,
        expected: const EditorOpenLinkAction('https://x.dev'),
      ),
      tapRow(
        'a tap inside the concealed url opens it too',
        text: linkLine,
        offset: 12,
        expected: const EditorOpenLinkAction('https://x.dev'),
      ),
      tapRow(
        'an image never opens — it renders raw',
        text: 'a ![img](https://x.dev) b',
        offset: 6,
      ),
      tapRow(
        'an escaped opening bracket is not a link',
        text: r'a \[docs](https://x.dev) b',
        offset: 7,
      ),
      tapRow(
        'a link inside an inline-code run is literal',
        text: 'a `[docs](https://x.dev)` b',
        offset: 7,
      ),
      tapRow(
        'links disabled: the same tap passes through',
        text: linkLine,
        offset: 5,
        links: false,
      ),

      // --- checkbox zone -------------------------------------------------
      tapRow(
        'a tap on the list marker toggles the box',
        text: '- [ ] squat',
        offset: 0,
        expected: const EditorToggleTaskAction(lineIndex),
      ),
      tapRow(
        'a tap on the closing bracket toggles the box',
        text: '- [ ] squat',
        offset: 5,
        expected: const EditorToggleTaskAction(lineIndex),
      ),
      tapRow(
        'the content right of the box stays editable',
        text: '- [ ] squat',
        offset: 6,
      ),
      tapRow(
        'the indent left of the marker stays editable',
        text: '  - [ ] squat',
        offset: 1,
      ),
      tapRow(
        'an indented zone starts at its marker',
        text: '  - [ ] squat',
        offset: 2,
        expected: const EditorToggleTaskAction(lineIndex),
      ),
      tapRow(
        'an indented zone ends at its closing bracket',
        text: '  - [ ] squat',
        offset: 7,
        expected: const EditorToggleTaskAction(lineIndex),
      ),
      tapRow(
        'a plain bullet is not a checkbox zone',
        text: '- squat',
        offset: 0,
      ),
      tapRow(
        'checkbox disabled: the same tap passes through',
        text: '- [ ] squat',
        offset: 0,
        checkbox: false,
      ),

      // --- money zone ----------------------------------------------------
      tapRow(
        r'the $$ chip opens the ledger detail',
        text: r'$$ balance',
        offset: 0,
        expected: const EditorOpenMoneyAction(lineIndex),
      ),
      tapRow(
        'the chip reaches up to the amount range',
        text: r'$$ balance',
        offset: 2,
        expected: const EditorOpenMoneyAction(lineIndex),
      ),
      tapRow(
        'the label text of a display row stays editable',
        text: r'$$ balance',
        offset: 3,
      ),
      tapRow(
        r'the $? chip opens the ledger detail',
        text: r'$? change',
        offset: 1,
        expected: const EditorOpenMoneyAction(lineIndex),
      ),
      tapRow(
        r'a bare $! chip opens the ledger detail',
        text: r'$!',
        offset: 0,
        expected: const EditorOpenMoneyAction(lineIndex),
      ),
      tapRow(
        r'the $^ chip opens the ledger detail',
        text: r'$^ 3 recent',
        offset: 1,
        expected: const EditorOpenMoneyAction(lineIndex),
      ),
      tapRow(
        r'the $^ count digits stay editable',
        text: r'$^ 3 recent',
        offset: 3,
      ),
      tapRow(
        r'the $~ chip opens the ledger detail',
        text: r'$~ 2 span',
        offset: 1,
        expected: const EditorOpenMoneyAction(lineIndex),
      ),
      tapRow(
        r'the $~ count digits stay editable',
        text: r'$~ 2 span',
        offset: 3,
      ),
      tapRow(
        'a value slot moved into the label is a zone too',
        text: r'$$ Current sum: $',
        offset: 16,
        expected: const EditorOpenMoneyAction(lineIndex),
      ),
      tapRow(
        'the space beside a value slot is not',
        text: r'$$ Current sum: $',
        offset: 15,
      ),
      tapRow(
        r'a $= op row never opens the sheet',
        text: r'$= 500 lunch',
        offset: 0,
      ),
      tapRow(
        r'a $+ op row never opens the sheet',
        text: r'$+ 50 coffee',
        offset: 0,
      ),
      tapRow(
        r'a $! N declaration never opens the sheet',
        text: r'$! 500 rent',
        offset: 0,
      ),
      tapRow(
        'money disabled: the same tap passes through',
        text: r'$$ balance',
        offset: 0,
        money: false,
      ),

      // --- tag zone ------------------------------------------------------
      tapRow(
        'a tap inside a #tag opens the search with the leading #',
        text: tagLine,
        offset: 6,
        expected: const EditorOpenTagAction('#project'),
      ),
      tapRow(
        "the tag construct's opening boundary passes through",
        text: tagLine,
        offset: 4,
      ),
      tapRow('a digit-led #1 is not a tag', text: '#1 place', offset: 1),
      tapRow('heading hashes are not a tag', text: '# Heading', offset: 1),
      tapRow(
        'a tag inside an inline-code run is literal',
        text: '`#project`',
        offset: 3,
      ),
      tapRow(
        'a tag nested in bold is still a tag',
        text: '**see #project**',
        offset: 9,
        expected: const EditorOpenTagAction('#project'),
      ),
      tapRow(
        "a tag in a money row's label opens the tag, not the sheet",
        text: r'$$ #project',
        offset: 4,
        expected: const EditorOpenTagAction('#project'),
      ),
      tapRow(
        'tags disabled: the same tap passes through',
        text: tagLine,
        offset: 6,
        tags: false,
      ),

      // --- precedence: checkbox > link > money > tag ----------------------
      tapRow(
        'the checkbox zone outranks a link that starts inside it',
        text: '- [ ](https://x.dev)',
        offset: 3,
        expected: const EditorToggleTaskAction(lineIndex),
      ),
      tapRow(
        'without the checkbox zone that same tap opens the link',
        text: '- [ ](https://x.dev)',
        offset: 3,
        checkbox: false,
        expected: const EditorOpenLinkAction('https://x.dev'),
      ),
      tapRow(
        'the link zone outranks a tag nested in its text',
        text: '[#project](https://x.dev)',
        offset: 3,
        expected: const EditorOpenLinkAction('https://x.dev'),
      ),
      tapRow(
        'without the link zone that same tap opens the tag',
        text: '[#project](https://x.dev)',
        offset: 3,
        links: false,
        expected: const EditorOpenTagAction('#project'),
      ),
    ];

    for (final row in rows) {
      test(row.name, () {
        expect(
          EditorInputPolicy.resolveTap(
            lineText: row.text,
            lineIndex: lineIndex,
            offset: row.offset,
            lineRevealed: row.revealed,
            inFence: row.inFence,
            zones: EditorTapZones(
              checkbox: row.checkbox,
              links: row.links,
              money: row.money,
              tags: row.tags,
              palette: palette,
            ),
          ),
          row.expected,
        );
      });
    }
  });

  group('toggledTaskLine', () {
    const cases = <String, String?>{
      '- [ ] squat': '- [x] squat',
      '- [x] squat': '- [ ] squat',
      '- [X] squat': '- [ ] squat',
      '  * [ ] squat': '  * [x] squat',
      '- [ ]': '- [x]',
      '- squat': null,
      '1. squat': null,
      'squat': null,
      '': null,
    };

    cases.forEach((line, expected) {
      test(
        '"$line" flips to ${expected == null ? 'nothing' : '"$expected"'}',
        () {
          expect(EditorInputPolicy.toggledTaskLine(line), expected);
        },
      );
    });
  });

  group('listIndent', () {
    test('indenting adds one unit and shifts the caret by it', () {
      expect(
        EditorInputPolicy.listIndent(lineText: '- squat', outdent: false),
        const EditorListIndent('  - squat', 2),
      );
      expect(
        EditorInputPolicy.listIndent(lineText: '1. squat', outdent: false),
        const EditorListIndent('  1. squat', 2),
      );
      expect(
        EditorInputPolicy.listIndent(lineText: '- [ ] squat', outdent: false),
        const EditorListIndent('  - [ ] squat', 2),
      );
    });

    test('outdenting removes a whole unit when there is one', () {
      expect(
        EditorInputPolicy.listIndent(lineText: '  - squat', outdent: true),
        const EditorListIndent('- squat', -2),
      );
      expect(
        EditorInputPolicy.listIndent(lineText: '    - squat', outdent: true),
        const EditorListIndent('  - squat', -2),
      );
    });

    test('outdenting removes a single leading space or tab', () {
      expect(
        EditorInputPolicy.listIndent(lineText: ' - squat', outdent: true),
        const EditorListIndent('- squat', -1),
      );
      expect(
        EditorInputPolicy.listIndent(lineText: '\t- squat', outdent: true),
        const EditorListIndent('- squat', -1),
      );
    });

    test('outdenting at column 0 consumes the key and changes nothing', () {
      expect(
        EditorInputPolicy.listIndent(lineText: '- squat', outdent: true),
        const EditorListIndent('- squat', 0),
      );
    });

    test('a non-list line declines in both directions', () {
      expect(
        EditorInputPolicy.listIndent(lineText: 'squat 5x5', outdent: false),
        isNull,
      );
      expect(
        EditorInputPolicy.listIndent(lineText: '  squat 5x5', outdent: true),
        isNull,
      );
    });
  });

  group('GhostEngagement', () {
    const line = 2;
    // The ghost run of [ghostLine] — `{{ name }}` at [4, 14).
    const runStart = 4;
    const runEnd = 14;

    CodeLineSelection caretAt(int offset, {int index = line}) =>
        CodeLineSelection.collapsed(index: index, offset: offset);

    GhostEngagement engaged() {
      final engagement = GhostEngagement()..arm();
      expect(
        engagement.caretChanged(selection: caretAt(8), lineText: ghostLine),
        const GhostSelectRun(lineIndex: line, start: runStart, end: runEnd),
      );
      expect(engagement.engaged, isTrue);
      return engagement;
    }

    test('an unarmed caret change never engages', () {
      final engagement = GhostEngagement();
      expect(
        engagement.caretChanged(selection: caretAt(8), lineText: ghostLine),
        const GhostNone(),
      );
      expect(engagement.engaged, isFalse);
    });

    test('an armed tap inside a run selects the whole run and disarms', () {
      final engagement = engaged();
      expect(engagement.armed, isFalse);
    });

    test('the run stays engaged while the whole-run selection lands', () {
      final engagement = engaged();
      expect(
        engagement.caretChanged(
          selection: const CodeLineSelection(
            baseIndex: line,
            baseOffset: runStart,
            extentIndex: line,
            extentOffset: runEnd,
          ),
          lineText: ghostLine,
        ),
        const GhostNone(),
      );
      expect(engagement.engaged, isTrue);
    });

    test('a second tap on the same run edits in place and disengages', () {
      final engagement = engaged()..arm();
      expect(
        engagement.caretChanged(selection: caretAt(9), lineText: ghostLine),
        const GhostEditInPlace(),
      );
      expect(engagement.engaged, isFalse);
      expect(engagement.armed, isFalse);
    });

    test('a non-collapsed selection never engages', () {
      final engagement = GhostEngagement()..arm();
      expect(
        engagement.caretChanged(
          selection: const CodeLineSelection(
            baseIndex: line,
            baseOffset: 6,
            extentIndex: line,
            extentOffset: 9,
          ),
          lineText: ghostLine,
        ),
        const GhostNone(),
      );
      expect(engagement.engaged, isFalse);
    });

    test('an out-of-range caret line never engages', () {
      final engagement = GhostEngagement()..arm();
      expect(
        engagement.caretChanged(selection: caretAt(8), lineText: null),
        const GhostNone(),
      );
      expect(engagement.engaged, isFalse);
    });

    test('a run boundary offset never engages', () {
      final engagement = GhostEngagement()..arm();
      expect(
        engagement.caretChanged(
          selection: caretAt(runStart),
          lineText: ghostLine,
        ),
        const GhostNone(),
      );
      expect(engagement.engaged, isFalse);
    });

    test('a line without a ghost never engages', () {
      final engagement = GhostEngagement()..arm();
      expect(
        engagement.caretChanged(selection: caretAt(3), lineText: tagLine),
        const GhostNone(),
      );
      expect(engagement.engaged, isFalse);
    });

    test('editing the engaged line disengages the run', () {
      final engagement = engaged();
      engagement.caretChanged(
        selection: caretAt(8),
        lineText: 'see {{ nome }} now',
      );
      expect(engagement.engaged, isFalse);
    });

    test('a caret moving out of the run disengages it', () {
      final engagement = engaged();
      engagement.caretChanged(selection: caretAt(16), lineText: ghostLine);
      expect(engagement.engaged, isFalse);
    });

    test('a selection reaching past the run disengages it', () {
      final engagement = engaged();
      engagement.caretChanged(
        selection: const CodeLineSelection(
          baseIndex: line,
          baseOffset: runStart,
          extentIndex: line,
          extentOffset: runEnd + 1,
        ),
        lineText: ghostLine,
      );
      expect(engagement.engaged, isFalse);
    });

    test('a caret moving to another line disengages the run', () {
      final engagement = engaged();
      engagement.caretChanged(
        selection: caretAt(8, index: line + 1),
        lineText: ghostLine,
      );
      expect(engagement.engaged, isFalse);
    });

    test('a caret line that vanished disengages the run', () {
      final engagement = engaged();
      engagement.caretChanged(selection: caretAt(8), lineText: null);
      expect(engagement.engaged, isFalse);
    });

    test('reset drops both the arming and the engagement', () {
      final engagement = engaged()..arm();
      engagement.reset();
      expect(engagement.armed, isFalse);
      expect(engagement.engaged, isFalse);
      expect(
        engagement.caretChanged(selection: caretAt(8), lineText: ghostLine),
        const GhostNone(),
      );
    });

    test('disarm stops the next caret change from engaging', () {
      final engagement = GhostEngagement()
        ..arm()
        ..disarm();
      expect(
        engagement.caretChanged(selection: caretAt(8), lineText: ghostLine),
        const GhostNone(),
      );
      expect(engagement.engaged, isFalse);
    });
  });
}

/// One row of the [EditorInputPolicy.resolveTap] table.
typedef TapRow = ({
  String name,
  String? text,
  int offset,
  bool revealed,
  bool inFence,
  bool checkbox,
  bool links,
  bool money,
  bool tags,
  EditorTapAction? expected,
});

/// Builds a row. Every zone is enabled by default, so a row that expects
/// `null` proves the pass-through rule rather than a missing zone.
TapRow tapRow(
  String name, {
  String? text,
  int offset = 0,
  bool revealed = false,
  bool inFence = false,
  bool checkbox = true,
  bool links = true,
  bool money = true,
  bool tags = true,
  EditorTapAction? expected,
}) => (
  name: name,
  text: text,
  offset: offset,
  revealed: revealed,
  inFence: inFence,
  checkbox: checkbox,
  links: links,
  money: money,
  tags: tags,
  expected: expected,
);
