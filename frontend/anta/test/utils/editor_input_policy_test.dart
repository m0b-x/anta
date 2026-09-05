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

  /// A link at `[2, 32)` whose text holds a `{{ … }}` ghost at `[6, 13)`.
  const ghostInLinkLine = 'a [do {{ x }} cs](https://x.dev) b';

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
      'a bare url is not a link zone — it renders as itself',
      text: 'see https://x.dev now',
      offset: 8,
    ),
    tapRow(
      'an unclosed link is literal text',
      text: '[docs](https://x.dev',
      offset: 3,
    ),
    tapRow(
      'a link wrapped in a colour run still opens',
      text: '{red:[docs](u)}',
      offset: 7,
      expected: const EditorOpenLinkAction('u'),
    ),
    tapRow(
      'a link wrapped in emphasis still opens',
      text: '*[docs](u)*',
      offset: 3,
      expected: const EditorOpenLinkAction('u'),
    ),
    tapRow(
      'two adjacent links are two zones, not one',
      text: '[a](b)[c](d)',
      offset: 1,
      expected: const EditorOpenLinkAction('b'),
    ),
    tapRow(
      'the second of two adjacent links opens its own url',
      text: '[a](b)[c](d)',
      offset: 7,
      expected: const EditorOpenLinkAction('d'),
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
    tapRow('a plain bullet is not a checkbox zone', text: '- squat', offset: 0),
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
    tapRow(r'the $~ count digits stay editable', text: r'$~ 2 span', offset: 3),
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
      'a money row carried by a list item still opens the sheet',
      text: r'- $$ total',
      offset: 2,
      expected: const EditorOpenMoneyAction(lineIndex),
    ),
    tapRow(
      "that row's list marker stays editable",
      text: r'- $$ total',
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
    tapRow(
      "a task line's box toggles while its link stays its own zone",
      text: '- [ ] [docs](u)',
      offset: 3,
      expected: const EditorToggleTaskAction(lineIndex),
    ),
    tapRow(
      "that task line's link still opens",
      text: '- [ ] [docs](u)',
      offset: 8,
      expected: const EditorOpenLinkAction('u'),
    ),

    // --- a construct straddling a ghost run ----------------------------
    tapRow(
      'the link half before a ghost inside its text still opens',
      text: ghostInLinkLine,
      offset: 4,
      expected: const EditorOpenLinkAction('https://x.dev'),
    ),
    tapRow(
      'the ghost inside a link text still wins',
      text: ghostInLinkLine,
      offset: 9,
    ),
    tapRow(
      'the link half after that ghost still opens',
      text: ghostInLinkLine,
      offset: 15,
      expected: const EditorOpenLinkAction('https://x.dev'),
    ),
  ];

  group('resolveTap', () {
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

  List<EditorTapZone> zonesFor(
    String? text, {
    bool revealed = false,
    bool inFence = false,
    bool checkbox = true,
    bool links = true,
    bool money = true,
    bool tags = true,
  }) => EditorInputPolicy.zonesOf(
    lineText: text,
    lineIndex: lineIndex,
    lineRevealed: revealed,
    inFence: inFence,
    zones: EditorTapZones(
      checkbox: checkbox,
      links: links,
      money: money,
      tags: tags,
      palette: palette,
    ),
  );

  group('zonesOf agrees with resolveTap', () {
    for (final row in rows) {
      test(row.name, () {
        final zoneList = zonesFor(
          row.text,
          revealed: row.revealed,
          inFence: row.inFence,
          checkbox: row.checkbox,
          links: row.links,
          money: row.money,
          tags: row.tags,
        );
        final length = row.text?.length ?? 0;

        for (final zone in zoneList) {
          expect(zone.start, greaterThanOrEqualTo(0));
          expect(zone.start, lessThan(zone.end));
          expect(zone.end, lessThanOrEqualTo(length));
        }
        for (int i = 1; i < zoneList.length; i++) {
          expect(
            zoneList[i].start,
            greaterThanOrEqualTo(zoneList[i - 1].end),
            reason: 'zones must be sorted and non-overlapping',
          );
        }

        for (int offset = 0; offset < length; offset++) {
          final resolved = EditorInputPolicy.resolveTap(
            lineText: row.text,
            lineIndex: lineIndex,
            offset: offset,
            lineRevealed: row.revealed,
            inFence: row.inFence,
            zones: EditorTapZones(
              checkbox: row.checkbox,
              links: row.links,
              money: row.money,
              tags: row.tags,
              palette: palette,
            ),
          );
          final covering = zoneList
              .where((zone) => offset >= zone.start && offset < zone.end)
              .toList();
          expect(
            covering.length,
            lessThanOrEqualTo(1),
            reason: 'offset $offset is covered twice',
          );
          expect(
            covering.isEmpty ? null : covering.single.action,
            resolved,
            reason: 'offset $offset disagrees',
          );
        }
      });
    }
  });

  group('zonesOf', () {
    test('a null line enumerates nothing', () {
      expect(zonesFor(null), isEmpty);
    });

    test('an empty line enumerates nothing', () {
      expect(zonesFor(''), isEmpty);
    });

    test('a revealed (caret) line enumerates nothing', () {
      expect(zonesFor('- [ ] $linkLine', revealed: true), isEmpty);
    });

    test('a fence line enumerates nothing', () {
      expect(zonesFor('- [ ] $linkLine', inFence: true), isEmpty);
    });

    test('a line past maxStyledLineLength enumerates nothing', () {
      final long = tagLine.padRight(
        MarkdownEditorSpanBuilder.maxStyledLineLength + 1,
        'x',
      );
      expect(zonesFor(long), isEmpty);
    });

    test('a construct-free line enumerates nothing', () {
      expect(zonesFor('squat 5x5'), isEmpty);
    });

    test('two adjacent links produce two ranges, not one', () {
      expect(zonesFor('[a](https://x.dev)[b](https://x.dev)'), const [
        EditorTapZone(
          start: 1,
          end: 18,
          action: EditorOpenLinkAction('https://x.dev'),
        ),
        EditorTapZone(
          start: 19,
          end: 36,
          action: EditorOpenLinkAction('https://x.dev'),
        ),
      ]);
    });

    test('a task line with a link produces two ranges in order', () {
      expect(zonesFor('- [ ] see [docs](https://x.dev)'), const [
        EditorTapZone(
          start: 0,
          end: 6,
          action: EditorToggleTaskAction(lineIndex),
        ),
        EditorTapZone(
          start: 11,
          end: 31,
          action: EditorOpenLinkAction('https://x.dev'),
        ),
      ]);
    });

    test('a ghost run inside a link splits it into its two halves', () {
      expect(zonesFor(ghostInLinkLine), const [
        EditorTapZone(
          start: 3,
          end: 7,
          action: EditorOpenLinkAction('https://x.dev'),
        ),
        EditorTapZone(
          start: 13,
          end: 32,
          action: EditorOpenLinkAction('https://x.dev'),
        ),
      ]);
    });

    test('the money chip and its moved value slot are both zones', () {
      expect(zonesFor(r'$$ Current sum: $'), const [
        EditorTapZone(
          start: 0,
          end: 3,
          action: EditorOpenMoneyAction(lineIndex),
        ),
        EditorTapZone(
          start: 16,
          end: 17,
          action: EditorOpenMoneyAction(lineIndex),
        ),
      ]);
    });

    test('a tag zone excludes the leading hash offset', () {
      expect(zonesFor(tagLine), const [
        EditorTapZone(
          start: 5,
          end: 12,
          action: EditorOpenTagAction('#project'),
        ),
      ]);
    });

    test('a nested tag is swallowed by the link that outranks it', () {
      expect(zonesFor('[#project](https://x.dev)'), const [
        EditorTapZone(
          start: 1,
          end: 25,
          action: EditorOpenLinkAction('https://x.dev'),
        ),
      ]);
      expect(zonesFor('[#project](https://x.dev)', links: false), const [
        EditorTapZone(
          start: 2,
          end: 9,
          action: EditorOpenTagAction('#project'),
        ),
      ]);
    });

    test('a disabled zone enumerates nothing for its construct', () {
      expect(zonesFor('- [ ] squat', checkbox: false), isEmpty);
      expect(zonesFor(linkLine, links: false), isEmpty);
      expect(zonesFor(r'$$ balance', money: false), isEmpty);
      expect(zonesFor(tagLine, tags: false), isEmpty);
    });
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

    test('an off-grid line snaps to the indent grid, like the fork', () {
      // `_applyTextIndent` / `_applyTextOutdent` in the fork's
      // `_code_line.dart` move by `leading % unit` when that is non-zero,
      // so a multi-line Tab lands ` - a` on column 2. A single-line Tab
      // that always moved a whole unit put it on column 3 instead, and
      // the same line indented one way could not be outdented the other.
      expect(
        EditorInputPolicy.listIndent(lineText: ' - squat', outdent: false),
        const EditorListIndent('  - squat', 1),
      );
      expect(
        EditorInputPolicy.listIndent(lineText: '   - squat', outdent: true),
        const EditorListIndent('  - squat', -1),
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

    test('a bail-out spends the arming, so the next caret move is '
        'not a tap', () {
      // The arming belongs to the caret change it was armed for. Left up
      // through a bail-out, it engaged the *next* change — and a keyboard
      // caret move inside the host's 350 ms window fires no pointer event
      // at all, so a run would select itself with nothing tapped.
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
      expect(engagement.armed, isFalse);

      expect(
        engagement.caretChanged(selection: caretAt(8), lineText: ghostLine),
        const GhostNone(),
      );
      expect(engagement.engaged, isFalse);
    });

    test('a collapsed caret on a run boundary disengages it', () {
      // `containsStrict` puts the boundaries outside the run, so a caret
      // parked on one is outside too — otherwise the next tap in the
      // middle reads as the second tap and edits in place instead of
      // selecting the run.
      for (final offset in const <int>[runStart, runEnd]) {
        final engagement = engaged();
        engagement.caretChanged(
          selection: caretAt(offset),
          lineText: ghostLine,
        );
        expect(
          engagement.engaged,
          isFalse,
          reason: 'caret at $offset kept the engagement',
        );
      }
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
