import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/database/database.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/body_search_indexer.dart';
import 'package:anta/services/folder_search_service.dart';
import 'package:anta/services/note_storage_service.dart';

import '../database/support/db_test_support.dart';
import 'support/body_index_support.dart';
import 'support/legacy_search_index.dart';

/// Holds the body index (S11, `docs/scalability-roadmap.md` §5.5) to the
/// in-memory index it replaced: for every query over a corpus of scripts,
/// folds and word shapes, the same notes are hits and each scores the same.
const _corpus = <(String, String)>[
  ('Squat day', 'heavy squat triples, then 5x5 bench'),
  ('Squat volume', 'squat sets and reps, squat again'),
  ('PR log', 'new PR on the ab wheel and deadlift'),
  ('Ședință de forță', 'Antrenament în sală: genuflexiuni și împins'),
  ('Sedinta veche', 'forta cu sedila: şedinţă, ţinută'),
  ('Kniebeugenvariante', 'Übungsplan Oberkörper, Straße zum Studio'),
  ('Приседания', 'Приседания со штангой, жим лёжа'),
  ('Άσκηση', 'Βαθύ κάθισμα με μπάρα'),
  ('深蹲训练', '今天深蹲五组 squat'),
  ('Emoji notes', '💪 squat PR 🎉 felt strong'),
  ('Short words', 'ab cd ef go up'),
  ('Underscored', 'snake_case and mixed123 tokens'),
];

const _queries = <String>[
  'squat',
  'quat',
  'uat',
  'sq',
  'pr',
  'ab',
  'squat pr',
  'bench squat',
  '5x5',
  '5x',
  'x5',
  'sedinta',
  'ședință',
  'şedinţă',
  'forta',
  'forță',
  'genuflex',
  'flexiuni',
  'straße',
  'strasse',
  'kniebeuge',
  'beugen',
  'übung',
  'ubung',
  'oberkörper',
  'körper',
  'присед',
  'штанг',
  'жим',
  'ед',
  'άσκηση',
  'κάθισμα',
  'θισ',
  '深蹲',
  '蹲训',
  '训练',
  'snake_case',
  'case',
  'mixed',
  '123',
  'up',
  'go up',
  'zz',
  'a',
  '💪',
  'nothing here',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FolderSearchService search;
  late Future<BodySearchIndexer> Function() indexer;
  final oracle = LegacySearchIndex();
  final titles = <String, String>{};

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    db = await openTestDatabase();
    final notes = NoteStorageService(repository: NoteRepository(database: db));
    await notes.initialize();
    indexer = bodyIndexerOver(db);
    search = FolderSearchService(storageService: notes, indexer: indexer);
    final folder = await db.folderDao.createFolder(name: 'Corpus');
    for (final (title, body) in _corpus) {
      final note = await notes.createNote(
        folderId: folder.id,
        title: title,
        content: body,
      );
      oracle.addNote(note.id, title, body);
      titles[note.id] = title;
    }
    await search.buildIndex();
  });

  tearDownAll(() async {
    await search.close();
    await db.close();
  });

  for (final query in _queries) {
    test(
      '"$query" finds what the in-memory index found, scored alike',
      () async {
        final results = await search.search(query, limit: 1000);
        final expected = oracle.search(query);

        expect(
          {for (final r in results) titles[r.metadata.id]},
          {for (final id in expected) titles[id]},
        );
        for (final result in results) {
          expect(
            result.relevanceScore,
            oracle.getRelevanceScore(result.metadata.id, query),
            reason: titles[result.metadata.id],
          );
        }

        // The trigram match alone, before any body is scored, is already the
        // hit set: the projection reproduces the rules rather than
        // approximating them.
        final words = tokenizeForSearch(query);
        if (words.isEmpty) return;
        final candidates = await (await indexer()).candidates(words);
        expect(
          {for (final note in candidates) note.title},
          {for (final id in expected) titles[id]},
          reason: 'the FTS candidates for "$query"',
        );
      },
    );
  }

  test('the corpus is not trivially empty for the scripts it covers', () async {
    for (final query in ['присед', 'κάθισμα', '深蹲', 'forta', 'strasse']) {
      expect(await search.search(query), isNotEmpty, reason: query);
    }
  });

  test('a projection is its tokens, each set off by one space', () {
    expect(
      searchProjection('Straße', 'Ședință 💪 a PR'),
      ' strasse sedinta pr ',
    );
  });
}
