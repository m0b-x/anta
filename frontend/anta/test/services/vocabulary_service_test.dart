import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/vocabularies.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/vocabulary_service.dart';

import '../database/support/db_test_support.dart';

/// The workflow layer: turning a block of typed lines into terms, publishing
/// the synchronous facade the editor reads, and surviving a backup round-trip.
void main() {
  late AppDatabase db;
  late VocabularyService service;

  setUp(() async {
    db = await openTestDatabase();
    VocabularyService.reset();
    service = await VocabularyService.forTesting(db);
  });

  tearDown(() async {
    VocabularyService.reset();
    await db.close();
  });

  group('parseTerms', () {
    test('trims lines and drops blanks', () {
      const raw = '  Bench Press \n\n\tDeadlift\n   \nSquat\n';

      expect(VocabularyService.parseTerms(raw), [
        'Bench Press',
        'Deadlift',
        'Squat',
      ]);
    });

    test('drops duplicates folded, keeping the first spelling', () {
      const raw = 'Bench Press\nbench press\nBENCH PRESS\nDeadlift';

      expect(VocabularyService.parseTerms(raw), ['Bench Press', 'Deadlift']);
    });

    test('treats diacritic variants as the same term', () {
      const raw = 'Împins\nimpins';

      expect(VocabularyService.parseTerms(raw), ['Împins']);
    });

    test('round-trips through formatTerms', () {
      const terms = ['Bench Press', 'Deadlift'];

      expect(
        VocabularyService.parseTerms(VocabularyService.formatTerms(terms)),
        terms,
      );
    });

    test('an empty block is no terms, not one blank term', () {
      expect(VocabularyService.parseTerms('   \n\n'), isEmpty);
    });
  });

  group('the published facade', () {
    test('carries enabled terms, pre-folded, in list order', () async {
      await service.createVocabulary(
        name: 'Exercises',
        terms: const ['Împins la piept', 'Deadlift'],
      );

      final candidates = Vocabularies.candidates;
      expect([for (final c in candidates) c.term], [
        'Împins la piept',
        'Deadlift',
      ]);
      expect(candidates.first.foldedTerm, 'impins la piept');
      expect(candidates.first.vocabularyName, 'Exercises');
      expect(Vocabularies.hasCandidates, isTrue);
    });

    test('a disabled list contributes no candidates but stays listed', () async {
      final created = await service.createVocabulary(
        name: 'Exercises',
        terms: const ['Bench Press'],
      );

      await service.setEnabled(created.id, false);

      expect(Vocabularies.candidates, isEmpty);
      expect(Vocabularies.all, hasLength(1));
      expect(Vocabularies.all.single.isEnabled, isFalse);
      expect(Vocabularies.all.single.items, hasLength(1));
    });

    test('resolves a placeholder name, tolerating singular and plural', () async {
      await service.createVocabulary(
        name: 'Exercises',
        terms: const ['Bench Press'],
      );

      expect(Vocabularies.byName('Exercises')?.name, 'Exercises');
      expect(Vocabularies.byName('exercise')?.name, 'Exercises');
      expect(Vocabularies.byName('  EXERCISES  ')?.name, 'Exercises');
      expect(Vocabularies.byName('meals'), isNull);
      expect(Vocabularies.byName(''), isNull);
    });

    test('a disabled list never resolves by name', () async {
      final created = await service.createVocabulary(
        name: 'Exercises',
        terms: const ['Bench Press'],
      );
      await service.setEnabled(created.id, false);

      expect(Vocabularies.byName('exercises'), isNull);
    });

    test('resolves a trigger scope by folded prefix', () async {
      final exercises = await service.createVocabulary(
        name: 'Exercises',
        terms: const ['Bench Press'],
      );
      await service.createVocabulary(name: 'Push Day', terms: const ['Dips']);

      expect(Vocabularies.idsForScopeTokens(['exer']), {exercises.id});
      expect(Vocabularies.idsForScopeTokens(['EXERCISES']), {exercises.id});
      expect(Vocabularies.idsForScopeTokens(['  exer  ']), {exercises.id});
      // A multi-word list is reachable by its first word.
      expect(Vocabularies.idsForScopeTokens(['push']), hasLength(1));
    });

    test('a scope token keeps the placeholder plural tolerance', () async {
      final created = await service.createVocabulary(
        name: 'Exercise',
        terms: const ['Bench Press'],
      );

      expect(Vocabularies.idsForScopeTokens(['exercises']), {created.id});
    });

    test('several tokens union, and one token may name several lists', () async {
      final exercises = await service.createVocabulary(
        name: 'Exercises',
        terms: const ['Bench Press'],
      );
      final meals = await service.createVocabulary(
        name: 'Meals',
        terms: const ['Oats'],
      );
      final everyone = await service.createVocabulary(
        name: 'Everyone',
        terms: const ['Ana'],
      );

      expect(Vocabularies.idsForScopeTokens(['exercises', 'meals']), {
        exercises.id,
        meals.id,
      });
      // "e" is a prefix of both "Exercises" and "Everyone" — the union is the
      // scope, not an ambiguity to reject.
      expect(Vocabularies.idsForScopeTokens(['e']), {
        exercises.id,
        everyone.id,
      });
    });

    test('a scope resolves to nothing rather than guessing', () async {
      final created = await service.createVocabulary(
        name: 'Exercises',
        terms: const ['Bench Press'],
      );
      await service.createVocabulary(name: 'Meals', terms: const ['Oats']);
      await service.setEnabled(created.id, false);

      // Disabled lists never resolve, and neither does a token naming none.
      expect(Vocabularies.idsForScopeTokens(['exercises']), isEmpty);
      expect(Vocabularies.idsForScopeTokens(['zzz']), isEmpty);
      expect(Vocabularies.idsForScopeTokens(['   ']), isEmpty);
      expect(Vocabularies.idsForScopeTokens(const []), isEmpty);
    });

    test('reset clears the facade so a closed database cannot leak', () async {
      await service.createVocabulary(
        name: 'Exercises',
        terms: const ['Bench Press'],
      );

      VocabularyService.reset();

      expect(Vocabularies.candidates, isEmpty);
      expect(Vocabularies.all, isEmpty);
      expect(Vocabularies.hasCandidates, isFalse);
    });
  });

  group('mutations', () {
    test('an edit replaces name, terms and enabled state together', () async {
      final created = await service.createVocabulary(
        name: 'Exercises',
        terms: const ['Bench Press', 'Deadlift'],
      );

      await service.updateVocabulary(
        id: created.id,
        name: 'Lifts',
        terms: const ['Deadlift', 'Squat'],
        isEnabled: false,
      );

      final stored = service.vocabularies.single;
      expect(stored.name, 'Lifts');
      expect(stored.isEnabled, isFalse);
      expect(stored.terms, ['Deadlift', 'Squat']);
    });

    test('deleting removes it from the facade', () async {
      final created = await service.createVocabulary(
        name: 'Exercises',
        terms: const ['Bench Press'],
      );

      await service.deleteVocabulary(created.id);

      expect(service.vocabularies, isEmpty);
      expect(Vocabularies.candidates, isEmpty);
    });

    test('reorder changes which list wins a tie', () async {
      final first = await service.createVocabulary(
        name: 'Exercises',
        terms: const ['Row'],
      );
      final second = await service.createVocabulary(
        name: 'Meals',
        terms: const ['Rice'],
      );

      await service.reorder([second.id, first.id]);

      expect([for (final v in service.vocabularies) v.name], [
        'Meals',
        'Exercises',
      ]);
      expect(Vocabularies.candidates.first.vocabularyName, 'Meals');
    });
  });

  group('backup', () {
    test('export/import round-trips lists with their terms', () async {
      await service.createVocabulary(
        name: 'Exercises',
        terms: const ['Bench Press', 'Deadlift'],
      );
      final disabled = await service.createVocabulary(
        name: 'Meals',
        terms: const ['Oats'],
      );
      await service.setEnabled(disabled.id, false);

      final exported = await service.exportData();
      await service.importData(exported);

      final restored = service.vocabularies;
      expect([for (final v in restored) v.name], ['Exercises', 'Meals']);
      expect(restored.first.terms, ['Bench Press', 'Deadlift']);
      expect(restored.last.isEnabled, isFalse);
      expect(restored.last.terms, ['Oats']);
    });

    test('import replaces rather than merges', () async {
      await service.createVocabulary(
        name: 'Exercises',
        terms: const ['Bench Press'],
      );
      final exported = await service.exportData();
      await service.createVocabulary(name: 'Meals', terms: const ['Oats']);

      await service.importData(exported);

      expect([for (final v in service.vocabularies) v.name], ['Exercises']);
    });

    test('malformed rows are skipped, not fatal', () async {
      await service.importData([
        'not a map',
        {'name': 'No id'},
        {'id': 'v1', 'name': 'Exercises', 'items': 'not a list'},
        {
          'id': 'v2',
          'name': 'Meals',
          'items': [
            {'term': '   '},
            {'term': 'Oats'},
          ],
        },
      ]);

      final names = [for (final v in service.vocabularies) v.name];
      expect(names, ['Exercises', 'Meals']);
      expect(service.vocabularies.first.terms, isEmpty);
      expect(service.vocabularies.last.terms, ['Oats']);
    });

    test('clearAllForImport empties both tables', () async {
      await service.createVocabulary(
        name: 'Exercises',
        terms: const ['Bench Press'],
      );

      await service.clearAllForImport();

      expect(service.vocabularies, isEmpty);
      expect(await db.vocabularyDao.getAllItems(), isEmpty);
    });
  });
}
