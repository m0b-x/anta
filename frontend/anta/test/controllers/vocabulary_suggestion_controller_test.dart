import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/constants/tag_catalog.dart';
import 'package:anta/constants/vocabularies.dart';
import 'package:anta/controllers/vocabulary_suggestion_controller.dart';
import 'package:anta/models/catalog_tag.dart';
import 'package:anta/models/vocabulary.dart';
import 'package:anta/models/vocabulary_item.dart';
import 'package:anta/utils/vocabulary_matcher.dart';

/// The session lifecycle, driven through a real [CodeLineEditingController].
///
/// This is where the two entry points meet the editor: a trigger character
/// typed into a line, and a ghost run engaged by a tap (which reaches us as a
/// selection covering the whole `{{ … }}`). The insertion callback applies the
/// replacement the way the editor page does, so the assertions are about the
/// text the user would actually end up with.
void main() {
  late CodeLineEditingController editor;
  late VocabularySuggestionController suggestions;

  setUp(() {
    Vocabularies.updateCache([
      const Vocabulary(
        id: 'v1',
        name: 'Exercises',
        isEnabled: true,
        sortOrder: 0,
        items: [
          VocabularyItem(
            id: 'i1',
            vocabularyId: 'v1',
            term: 'Bench Press',
            sortOrder: 0,
          ),
          VocabularyItem(
            id: 'i2',
            vocabularyId: 'v1',
            term: 'Deadlift',
            sortOrder: 1,
          ),
        ],
      ),
      const Vocabulary(
        id: 'v2',
        name: 'Meals',
        isEnabled: true,
        sortOrder: 1,
        items: [
          VocabularyItem(
            id: 'i3',
            vocabularyId: 'v2',
            term: 'Oats',
            sortOrder: 0,
          ),
        ],
      ),
    ]);

    editor = CodeLineEditingController();
    suggestions = VocabularySuggestionController(
      controller: editor,
      onInsert: (insertion) {
        editor.replaceSelection(
          insertion.text,
          CodeLineSelection(
            baseIndex: insertion.lineIndex,
            baseOffset: insertion.start,
            extentIndex: insertion.lineIndex,
            extentOffset: insertion.end,
          ),
        );
      },
    );
    suggestions.configure(enabled: true, trigger: '@');
  });

  tearDown(() {
    suggestions.dispose();
    editor.dispose();
    Vocabularies.resetCache();
  });

  /// Puts [text] on line 0 with the caret at [caret], the way typing would.
  void type(String text, {int? caret}) {
    editor.text = text;
    editor.selection = CodeLineSelection.collapsed(
      index: 0,
      offset: caret ?? text.length,
    );
  }

  /// What the input method hands the editor for line 0, the caret at the
  /// text's end and [composing] the word it has not committed yet.
  void ime(String text, {TextRange composing = TextRange.empty}) {
    editor.edit(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
        composing: composing,
      ),
    );
  }

  List<String> offered() => [
    for (final candidate
        in suggestions.value?.suggestions ?? const <VocabularyCandidate>[])
      candidate.term,
  ];

  group('the trigger session', () {
    test('opens on the trigger and filters as more is typed', () {
      type('@');
      expect(offered(), ['Bench Press', 'Deadlift', 'Oats']);

      type('@ben');
      expect(offered(), ['Bench Press']);
    });

    test('closes when nothing matches, leaving the text alone', () {
      type('@zzz');

      expect(suggestions.value, isNull);
      expect(editor.codeLines[0].text, '@zzz');
    });

    test('never opens on a weight annotation', () {
      type('- Squat 3x8 @ 60kg');

      expect(suggestions.value, isNull);
    });

    test('accepting replaces the trigger and query with plain text', () {
      type('- 3x8 @ben');

      suggestions.accept(suggestions.value!.suggestions.single);

      expect(editor.codeLines[0].text, '- 3x8 Bench Press ');
      expect(suggestions.value, isNull);
    });

    test('accepting mid-line does not add a second space', () {
      type('- @ben 3x8', caret: 6);

      suggestions.accept(suggestions.value!.suggestions.single);

      expect(editor.codeLines[0].text, '- Bench Press 3x8');
    });

    test('dismissing keeps it closed until a new query starts elsewhere', () {
      type('@ben');
      expect(suggestions.value, isNotNull);

      suggestions.dismiss();
      expect(suggestions.value, isNull);

      // Same query, re-detected: still dismissed.
      type('@ben');
      expect(suggestions.value, isNull);

      // A different anchor is a new question.
      type('word @ben');
      expect(offered(), ['Bench Press']);
    });

    test('a disabled controller never opens a session', () {
      suggestions.configure(enabled: false, trigger: '@');

      type('@ben');

      expect(suggestions.value, isNull);
    });

    test('a fence line is inert', () {
      suggestions.configure(
        enabled: true,
        trigger: '@',
        isFenceLine: (_) => true,
      );

      type('@ben');

      expect(suggestions.value, isNull);
    });

    test('no candidates means no session', () {
      Vocabularies.resetCache();

      type('@ben');

      expect(suggestions.value, isNull);
    });

    // The bar flattens a heading term only where accepting it still makes
    // a heading: after indent alone.
    test('knows whether it starts the line', () {
      type('@be');
      expect(suggestions.value?.atLineStart, isTrue);

      type('  @be');
      expect(suggestions.value?.atLineStart, isTrue);

      type('Did @be');
      expect(suggestions.value?.atLineStart, isFalse);
    });
  });

  group('the scoped trigger session', () {
    test('a named list before the colon filters inside it alone', () {
      type('@exercise:');
      expect(offered(), ['Bench Press', 'Deadlift']);

      type('@exercise:ben');
      expect(offered(), ['Bench Press']);
    });

    test('the scope hides terms that would otherwise match', () {
      type('@exercise:oat');

      // "Oats" lives in Meals.
      expect(suggestions.value, isNull);
    });

    test('several lists offer their union', () {
      type('@exercises,meals:');

      expect(offered(), ['Bench Press', 'Deadlift', 'Oats']);
    });

    test('the resolved list names travel with the session, for the bar', () {
      type('@exercise:ben');

      expect(suggestions.value?.scopeNames, ['Exercises']);
    });

    test('accepting consumes the scope along with the query', () {
      type('- 3x8 @exercise:ben');

      suggestions.accept(suggestions.value!.suggestions.single);

      expect(editor.codeLines[0].text, '- 3x8 Bench Press ');
      expect(suggestions.value, isNull);
    });

    test('an unresolvable scope falls back to the raw run, unscoped', () {
      Vocabularies.updateCache([
        const Vocabulary(
          id: 'v3',
          name: 'Templates',
          isEnabled: true,
          sortOrder: 0,
          items: [
            VocabularyItem(
              id: 'i4',
              vocabularyId: 'v3',
              term: 'Warmup: 10min',
              sortOrder: 0,
            ),
            VocabularyItem(
              id: 'i5',
              vocabularyId: 'v3',
              term: '10 Sets',
              sortOrder: 1,
            ),
          ],
        ),
      ]);

      type('@warmup:10');

      // "warmup" names no list, so the colon is an ordinary character of the
      // query and the whole run is matched: filtering on "10" alone would have
      // offered "10 Sets" first.
      expect(offered(), ['Warmup: 10min']);
    });

    test('a scope naming nothing still leaves the text alone', () {
      type('@zzz:ben');

      expect(suggestions.value, isNull);
      expect(editor.codeLines[0].text, '@zzz:ben');
    });

    test('an empty scope segment queries every list', () {
      type('@:ben');

      expect(offered(), ['Bench Press']);
    });
  });

  group('the ghost session', () {
    /// The whole-run selection `ModernEditorWrapper` applies when a ghost is
    /// tapped.
    void engageGhost(String text, int start, int end) {
      editor.text = text;
      editor.selection = CodeLineSelection(
        baseIndex: 0,
        baseOffset: start,
        extentIndex: 0,
        extentOffset: end,
      );
    }

    test('a named placeholder scopes suggestions to that list', () {
      engageGhost('- {{exercise}} 3x8', 2, 14);

      expect(offered(), ['Bench Press', 'Deadlift']);
      expect(suggestions.value?.scopeNames, ['Exercises']);
    });

    test('an unnamed placeholder offers every enabled list', () {
      engageGhost('- {{  }} 3x8', 2, 8);

      expect(offered(), ['Bench Press', 'Deadlift', 'Oats']);
      expect(suggestions.value?.scopeNames, isEmpty);
    });

    test('accepting replaces the whole run, spacing intact', () {
      engageGhost('- {{exercise}} 3x8', 2, 14);

      suggestions.accept(suggestions.value!.suggestions.first);

      expect(editor.codeLines[0].text, '- Bench Press 3x8');
    });

    test('the caret parked inside a ghost also opens a session', () {
      type('- {{exercise}} 3x8', caret: 8);

      expect(offered(), ['Bench Press', 'Deadlift']);
    });

    test('inner text that names no list is treated as a query', () {
      type('- {{dead}} 3x8', caret: 8);

      expect(offered(), ['Deadlift']);
    });

    test('typing over an engaged ghost keeps filtering from its anchor', () {
      engageGhost('- {{exercise}} 3x8', 2, 14);
      expect(suggestions.value, isNotNull);

      // Typing replaces the selected run in one edit — the braces are gone,
      // but the session must survive on the offset the ghost started at.
      editor.replaceSelection('ben');

      expect(offered(), ['Bench Press']);

      suggestions.accept(suggestions.value!.suggestions.single);
      expect(editor.codeLines[0].text, '- Bench Press 3x8');
    });

    test('the anchor scope survives typing, so other lists stay out', () {
      engageGhost('{{exercise}}', 0, 12);
      editor.replaceSelection('oat');

      // "Oats" lives in Meals; the engaged ghost named Exercises.
      expect(suggestions.value, isNull);
    });

    test('a second space abandons the anchor', () {
      engageGhost('{{exercise}}', 0, 12);
      editor.replaceSelection('ben ch x');

      expect(suggestions.value, isNull);
    });

    test('moving the caret before the anchor ends the session', () {
      engageGhost('- {{exercise}} 3x8', 2, 14);
      editor.replaceSelection('ben');
      expect(suggestions.value, isNotNull);

      editor.selection = CodeLineSelection.collapsed(index: 0, offset: 0);

      expect(suggestions.value, isNull);
    });

    test('knows whether it starts the line, before and after typing', () {
      engageGhost('{{exercise}}', 0, 12);
      expect(suggestions.value?.atLineStart, isTrue);

      engageGhost('Did {{exercise}}', 4, 16);
      expect(suggestions.value?.atLineStart, isFalse);

      // The anchor continuation pairs the line with the ghost's old start.
      editor.replaceSelection('ben');
      expect(offered(), ['Bench Press']);
      expect(suggestions.value?.atLineStart, isFalse);
    });
  });

  group('the tag session', () {
    setUp(() {
      // The catalog's order: most notes first, then the folded form.
      TagCatalog.updateCache(const [
        CatalogTag(tag: 'legpress', folded: 'legpress', noteCount: 7),
        CatalogTag(tag: 'Legday', folded: 'legday', noteCount: 5),
        CatalogTag(tag: 'legdays', folded: 'legdays', noteCount: 1),
        CatalogTag(tag: 'lunge', folded: 'lunge', noteCount: 1),
        CatalogTag(tag: 'mobile', folded: 'mobile', noteCount: 1),
        CatalogTag(tag: 'Monday', folded: 'monday', noteCount: 1),
      ]);
    });

    tearDown(TagCatalog.resetCache);

    /// Leaves [text] in the editor with the caret on [line] at [caret] (the
    /// line's end when omitted), the character before the caret arriving
    /// as a keystroke: a tag session opens on typing, never on the caret
    /// being put into a tag.
    void typeAt(String text, int line, {int? caret}) {
      final lines = text.split('\n');
      final at = caret ?? lines[line].length;
      final key = lines[line].substring(at - 1, at);
      lines[line] = lines[line].replaceRange(at - 1, at, '');
      final before = lines.join('\n');
      if (editor.text != before) editor.text = before;
      editor.selection = CodeLineSelection.collapsed(
        index: line,
        offset: at - 1,
      );
      editor.replaceSelection(key);
    }

    /// [typeAt] on line 0; shadows the plain `type`, which only puts the
    /// caret where the text ends.
    void type(String text, {int? caret}) => typeAt(text, 0, caret: caret);

    test('opens on the first character after #, ranked by the catalog '
        'inside a tier, and narrows', () {
      type('#');
      expect(suggestions.value, isNull, reason: 'a bare # may be a heading');

      type('#l');
      // `#mobile` holds `#l` as a subsequence, the matcher's last tier.
      expect(offered(), [
        '#legpress',
        '#Legday',
        '#legdays',
        '#lunge',
        '#mobile',
      ]);
      expect(suggestions.value!.start, 0);
      expect(suggestions.value!.end, 2);
      expect(suggestions.value!.atLineStart, isTrue);
      expect(suggestions.value!.scopeNames, isEmpty);

      type('squats #legd');
      expect(offered(), ['#Legday', '#legdays']);
      expect(suggestions.value!.atLineStart, isFalse);
    });

    test('closes on a space after the tag', () {
      type('#leg');
      expect(suggestions.value, isNotNull);

      type('#leg ');
      expect(suggestions.value, isNull);
    });

    test('leaves out only the tag spelled as written, letter for letter, '
        'over the whole tag', () {
      type('#Legday');
      expect(offered(), ['#legdays']);

      // Another spelling is offered, so a tag can be brought into line.
      type('#LEGDAY');
      expect(offered(), ['#Legday', '#legdays']);

      // The caret inside a finished tag: that tag is no pill to offer.
      type('#Legday sets', caret: 4);
      expect(offered(), ['#legpress', '#legdays']);
    });

    test('the same rule for this note\'s own tags', () {
      // `#Tempox` is read first, so it is the note's spelling of the tag.
      typeAt('a #Tempox\n#tempox', 1, caret: 4);
      expect(offered(), ['#Tempox']);
    });

    test('the tag a session opened on is not offered once it is edited', () {
      type('x #le');
      expect(suggestions.value, isNotNull);

      editor.replaceSelection(
        '',
        const CodeLineSelection(
          baseIndex: 0,
          baseOffset: 4,
          extentIndex: 0,
          extentOffset: 5,
        ),
      );

      expect(editor.codeLines[0].text, 'x #l');
      expect(offered(), isNot(contains('#le')));
    });

    test('reads the note\'s tags again only after an edit, never because '
        'the caret moved', () {
      typeAt('a #alpha #beta #gamma', 0, caret: 4);

      for (final caret in [12, 19, 4]) {
        editor.selection = CodeLineSelection.collapsed(index: 0, offset: caret);
      }

      expect(suggestions.noteTagScans, 1);
    });

    test('offers this note\'s own tags after the catalog\'s, read once per '
        'session', () {
      typeAt('warm-up #mobility #MONDAY\n#mo', 1);

      // `#MONDAY` is the catalog's `#Monday`, offered once in its spelling.
      expect(offered(), ['#mobile', '#Monday', '#mobility']);
      expect(suggestions.noteTagScans, 1);

      editor.replaceSelection('b');
      editor.replaceSelection('i');

      expect(editor.codeLines[1].text, '#mobi');
      expect(offered(), ['#mobile', '#mobility']);
      expect(suggestions.noteTagScans, 1, reason: 'never per keystroke');

      editor.replaceSelection(' #m');
      expect(suggestions.noteTagScans, 2, reason: 'a new tag, a new session');
    });

    test('skips the note\'s fence lines', () {
      suggestions.configure(
        enabled: true,
        trigger: '@',
        isFenceLine: (line) => line == 1,
      );
      typeAt('intro\n#mobster\n#mobs', 2);

      expect(suggestions.value, isNull);
    });

    test('works with no vocabulary at all', () {
      Vocabularies.resetCache();

      type('#lu');
      expect(offered(), ['#lunge']);

      type('@ben');
      expect(suggestions.value, isNull);
    });

    test('stays shut while autocomplete is off', () {
      suggestions.configure(enabled: false, trigger: '@');

      type('#le');

      expect(suggestions.value, isNull);
    });

    test('never opens on a fence line', () {
      suggestions.configure(
        enabled: true,
        trigger: '@',
        isFenceLine: (_) => true,
      );

      type('#le');

      expect(suggestions.value, isNull);
    });

    test('accepting writes the catalog\'s spelling over the whole tag', () {
      type('#legdya sets', caret: 4);
      expect(suggestions.value!.end, 7);

      suggestions.accept(
        suggestions.value!.suggestions.firstWhere((c) => c.term == '#Legday'),
      );
      expect(editor.codeLines[0].text, '#Legday sets');

      type('squats #lu');
      suggestions.accept(suggestions.value!.suggestions.single);
      expect(editor.codeLines[0].text, 'squats #lunge ');
    });

    test('a completion mid-line keeps the bar shut for that tag until its '
        'text changes', () {
      type('#leg x', caret: 4);
      suggestions.accept(
        suggestions.value!.suggestions.firstWhere((c) => c.term == '#Legday'),
      );

      expect(editor.codeLines[0].text, '#Legday x');
      expect(editor.selection.baseOffset, 7);
      expect(suggestions.value, isNull);

      // The same tap again: no pill is there to take it.
      final again = suggestions.value;
      if (again != null) suggestions.accept(again.suggestions.first);
      expect(editor.codeLines[0].text, '#Legday x');

      editor.replaceSelection('s');
      expect(editor.codeLines[0].text, '#Legdays x');
      expect(offered(), ['#legdays']);
    });

    test('a completion adds a space only when the tag ends the line', () {
      for (final (typed, written) in [
        ('#leg.', '#Legday.'),
        ('#leg, then', '#Legday, then'),
        ('#leg)', '#Legday)'),
        ('#leg x', '#Legday x'),
        ('#leg', '#Legday '),
      ]) {
        type(typed, caret: 4);
        suggestions.accept(
          suggestions.value!.suggestions.firstWhere(
            (c) => c.term == '#Legday',
          ),
        );
        expect(editor.codeLines[0].text, written);
        expect(suggestions.value, isNull, reason: typed);
      }
    });

    test('a dismissed tag stays shut until another tag starts', () {
      type('#le');
      suggestions.dismiss();
      expect(suggestions.value, isNull);

      type('#leg');
      expect(suggestions.value, isNull);

      type('#leg #lu');
      expect(offered(), ['#lunge']);
    });

    test('the vocabulary trigger still opens its own session, with only its '
        'own terms', () {
      type('#legday @');

      expect(offered(), ['Bench Press', 'Deadlift', 'Oats']);
    });

    test('a trigger run offering nothing leaves its tag to the tag '
        'session', () {
      type('@zzz #lu');

      expect(offered(), ['#lunge']);
    });

    test('a ghost still wins', () {
      editor.text = '{{exercise}} #le';
      editor.selection = const CodeLineSelection(
        baseIndex: 0,
        baseOffset: 0,
        extentIndex: 0,
        extentOffset: 12,
      );

      expect(offered(), ['Bench Press', 'Deadlift']);
    });

    // The bar takes the toolbar's place, undo and redo with it: a session
    // the caret alone opened would put a pill where a toolbar tap lands.
    group('opens on typing alone', () {
      test('a caret or a selection put into a tag offers nothing; typing in '
          'it does, and the session stays while the caret stays in that '
          'tag', () {
        editor.text = 'squats #Legday x';
        for (final caret in [14, 10, 9]) {
          editor.selection = CodeLineSelection.collapsed(
            index: 0,
            offset: caret,
          );
          expect(suggestions.value, isNull, reason: 'caret at $caret');
        }
        editor.selection = const CodeLineSelection(
          baseIndex: 0,
          baseOffset: 8,
          extentIndex: 0,
          extentOffset: 14,
        );
        expect(suggestions.value, isNull);
        expect(suggestions.noteTagScans, 0, reason: 'nothing typed, no read');

        editor.selection = const CodeLineSelection.collapsed(
          index: 0,
          offset: 14,
        );
        editor.replaceSelection('s');
        expect(editor.codeLines[0].text, 'squats #Legdays x');
        expect(offered(), ['#legdays']);

        editor.selection = const CodeLineSelection.collapsed(
          index: 0,
          offset: 11,
        );
        expect(offered(), contains('#Legday'), reason: 'the same tag');

        editor.selection = const CodeLineSelection.collapsed(
          index: 0,
          offset: 3,
        );
        expect(suggestions.value, isNull);
        editor.selection = const CodeLineSelection.collapsed(
          index: 0,
          offset: 11,
        );
        expect(suggestions.value, isNull, reason: 'back by the caret alone');
      });

      test('an undo or a redo opens nothing; the next typed character '
          'does', () {
        type('#leg x', caret: 4);
        suggestions.accept(
          suggestions.value!.suggestions.firstWhere((c) => c.term == '#Legday'),
        );
        expect(editor.codeLines[0].text, '#Legday x');

        editor.undo();
        expect(editor.codeLines[0].text, '#leg x');
        expect(editor.selection.baseOffset, 4);
        expect(suggestions.value, isNull, reason: 'undo is not typing');

        editor.redo();
        expect(editor.codeLines[0].text, '#Legday x');
        expect(suggestions.value, isNull, reason: 'redo is not typing');

        editor.replaceSelection('s');
        expect(offered(), ['#legdays']);
      });

      test('an undo inside an open session shuts it until the next typed '
          'character', () {
        type('#le');
        editor.replaceSelection('g');
        expect(suggestions.value, isNotNull);

        editor.undo();
        expect(suggestions.value, isNull);

        editor.replaceSelection('g');
        expect(suggestions.value, isNotNull);
      });

      test('switching autocomplete off and on leaves a completed tag '
          'shut', () {
        type('#leg x', caret: 4);
        suggestions.accept(
          suggestions.value!.suggestions.firstWhere((c) => c.term == '#Legday'),
        );

        suggestions.configure(enabled: false, trigger: '@');
        suggestions.configure(enabled: true, trigger: '@');

        expect(suggestions.value, isNull);
      });

      test('a dismissal ends when the caret leaves the tag', () {
        typeAt('#le\nplain', 0);
        suggestions.dismiss();
        expect(suggestions.value, isNull);

        editor.selection = const CodeLineSelection.collapsed(
          index: 1,
          offset: 5,
        );
        editor.selection = const CodeLineSelection.collapsed(
          index: 0,
          offset: 3,
        );
        // The line rewritten into another tag, key by key, at the same `#`.
        editor.deleteBackward();
        editor.deleteBackward();
        editor.replaceSelection('m');
        editor.replaceSelection('o');

        expect(editor.codeLines[0].text, '#mo');
        expect(offered(), ['#mobile', '#Monday']);
      });

      test('a tag that opens nothing keeps a typed-over ghost\'s session, '
          'so backspacing out of it brings the terms back', () {
        editor.text = '{{exercise}}';
        editor.selection = const CodeLineSelection(
          baseIndex: 0,
          baseOffset: 0,
          extentIndex: 0,
          extentOffset: 12,
        );
        editor.replaceSelection('ben');
        expect(offered(), ['Bench Press']);

        editor.replaceSelection(' #z');
        expect(editor.codeLines[0].text, 'ben #z');
        expect(suggestions.value, isNull);

        for (var i = 0; i < 3; i++) {
          editor.deleteBackward();
        }

        expect(editor.codeLines[0].text, 'ben');
        expect(offered(), ['Bench Press']);
      });
    });

    // A phone keyboard composes a word before it commits it.
    group('while the input method composes', () {
      test('a tag offers nothing; the commit opens it with the caret at '
          'the tag, and a completion leaves nothing composing', () {
        ime('#l', composing: const TextRange(start: 1, end: 2));
        expect(suggestions.value, isNull);
        ime('#le', composing: const TextRange(start: 1, end: 3));
        expect(suggestions.value, isNull);

        ime('#le');
        expect(editor.isComposing, isFalse);
        expect(offered(), contains('#legpress'));

        suggestions.accept(
          suggestions.value!.suggestions.firstWhere((c) => c.term == '#Legday'),
        );
        expect(editor.codeLines[0].text, '#Legday ');
        expect(editor.composing, TextRange.empty);
      });

      test('a word the keyboard only marks, then commits with the caret '
          'unmoved, opens nothing', () {
        editor.text = '#leg x';
        editor.selection = const CodeLineSelection.collapsed(
          index: 0,
          offset: 4,
        );
        // A tap: the keyboard marks the word under the caret, no text
        // changed, then commits it as it hides.
        for (final composing in const [
          TextRange(start: 1, end: 4),
          TextRange.empty,
        ]) {
          editor.edit(
            TextEditingValue(
              text: '#leg x',
              selection: const TextSelection.collapsed(offset: 4),
              composing: composing,
            ),
          );
        }

        expect(suggestions.value, isNull);
      });
    });

    group('a change nobody typed', () {
      test('a vocabulary term ending in a tag, accepted mid-line, leaves '
          'the bar shut', () {
        Vocabularies.updateCache([
          const Vocabulary(
            id: 'v1',
            name: 'Exercises',
            isEnabled: true,
            sortOrder: 0,
            items: [
              VocabularyItem(
                id: 'i1',
                vocabularyId: 'v1',
                term: 'Squat #legday',
                sortOrder: 0,
              ),
            ],
          ),
        ]);
        editor.text = '@sq x';
        editor.selection = const CodeLineSelection.collapsed(
          index: 0,
          offset: 3,
        );
        expect(offered(), ['Squat #legday']);

        suggestions.accept(suggestions.value!.suggestions.single);

        expect(editor.codeLines[0].text, 'Squat #legday x');
        expect(editor.selection.baseOffset, 13);
        expect(suggestions.value, isNull);
      });

      test('an insert the host makes from code opens nothing', () {
        var fromCode = false;
        final host = CodeLineEditingController();
        final watcher = VocabularySuggestionController(
          controller: host,
          onInsert: (_) {},
          isProgrammaticEdit: () => fromCode,
        )..configure(enabled: true, trigger: '@');
        addTearDown(() {
          watcher.dispose();
          host.dispose();
        });

        host.text = 'x';
        host.selection = const CodeLineSelection.collapsed(
          index: 0,
          offset: 1,
        );
        fromCode = true;
        host.replaceSelection(' #le');
        fromCode = false;
        expect(watcher.value, isNull);

        host.replaceSelection('g');
        expect(watcher.value, isNotNull, reason: 'typed after it, it opens');
      });

      test('a notification that carries no new value is no keystroke', () {
        type('#leg x', caret: 4);
        suggestions.accept(
          suggestions.value!.suggestions.firstWhere(
            (c) => c.term == '#Legday',
          ),
        );
        editor.undo();
        expect(suggestions.value, isNull);

        // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
        editor.notifyListeners();

        expect(suggestions.value, isNull);
      });
    });
  });

  test('the vocabulary trigger offers nothing while the input method '
      'composes, and opens on the commit', () {
    ime('@b', composing: const TextRange(start: 1, end: 2));
    expect(suggestions.value, isNull);
    ime('@be', composing: const TextRange(start: 1, end: 3));
    expect(suggestions.value, isNull);

    ime('@be');
    expect(offered(), ['Bench Press']);
  });
}
