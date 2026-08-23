import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/constants/vocabularies.dart';
import 'package:anta/controllers/vocabulary_suggestion_controller.dart';
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
  });
}
