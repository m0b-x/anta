import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/vocabulary_item.dart';

/// What separates a section header from a term.
///
/// The marker is two characters precisely so a real term can keep a single
/// semicolon; these cases pin that boundary, since getting it wrong would
/// silently stop suggesting something the user typed.
void main() {
  group('isCommentText', () {
    test('recognises the marker at the start of the line', () {
      expect(VocabularyItem.isCommentText(';; Chest'), isTrue);
      expect(VocabularyItem.isCommentText(';;Chest'), isTrue);
      expect(VocabularyItem.isCommentText(';;'), isTrue);
    });

    test('tolerates leading whitespace, so an indented header still reads', () {
      expect(VocabularyItem.isCommentText('   ;; Chest'), isTrue);
      expect(VocabularyItem.isCommentText('\t;; Chest'), isTrue);
    });

    test('leaves a term carrying a single semicolon alone', () {
      expect(VocabularyItem.isCommentText('; Chest'), isFalse);
      expect(VocabularyItem.isCommentText('Squat; paused'), isFalse);
      expect(VocabularyItem.isCommentText('Bench Press'), isFalse);
    });

    test('only the start of the line counts', () {
      expect(VocabularyItem.isCommentText('Squat ;; heavy'), isFalse);
    });

    test('an empty line is not a header', () {
      expect(VocabularyItem.isCommentText(''), isFalse);
      expect(VocabularyItem.isCommentText('   '), isFalse);
    });
  });

  group('commentLabel', () {
    VocabularyItem itemFor(String term) =>
        VocabularyItem(id: 'i1', vocabularyId: 'v1', term: term, sortOrder: 0);

    test('strips the marker and the space after it', () {
      expect(itemFor(';; Chest').commentLabel, 'Chest');
      expect(itemFor(';;Chest').commentLabel, 'Chest');
      expect(itemFor('  ;;   Chest  ').commentLabel, 'Chest');
    });

    test('a bare marker labels nothing, rather than throwing', () {
      expect(itemFor(';;').commentLabel, '');
    });
  });

  test('isComment reads the term the item carries', () {
    final header = VocabularyItem(
      id: 'i1',
      vocabularyId: 'v1',
      term: ';; Chest',
      sortOrder: 0,
    );
    final term = VocabularyItem(
      id: 'i2',
      vocabularyId: 'v1',
      term: 'Bench Press',
      sortOrder: 1,
    );

    expect(header.isComment, isTrue);
    expect(term.isComment, isFalse);
  });
}
