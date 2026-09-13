import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/database/database.dart';
import 'package:anta/models/item_label.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/folder_search_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/note_storage_service.dart';

import '../database/support/db_test_support.dart';

/// A colour label narrows whatever pass is showing, and on its own — with
/// nothing typed — it is not a search at all but a **listing**: "everything
/// red" is a question, and `labelledNotes` is what answers it, out of SQLite
/// rather than out of a page of notes held in memory.
///
/// The line that needs pinning is between the two. An empty query finds
/// nothing in `quickSearch` whatever the filter says, because a search with
/// no text to match would be a full page read on every cleared field.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late FolderStorageService folders;
  late NoteStorageService notes;
  late FolderSearchService search;

  late String trainingId;
  late String winterId;
  late String groceriesId;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = await openTestDatabase();
    folders = FolderStorageService(repository: FolderRepository(database: db));
    await folders.initialize();
    notes = NoteStorageService(repository: NoteRepository(database: db));
    await notes.initialize();
    search = FolderSearchService(storageService: notes);
    await search.initialize();

    trainingId = (await folders.createFolder(name: 'Training')).id;
    winterId = (await folders.createFolder(
      name: 'Winter block',
      parentId: trainingId,
    )).id;
    groceriesId = (await folders.createFolder(name: 'Groceries')).id;

    Future<void> note(String folderId, String title, ItemLabel label) async {
      final created = await notes.createNote(
        folderId: folderId,
        title: title,
        content: 'squat and press',
      );
      if (label != ItemLabel.none) {
        await notes.setNoteLabel(created.id, label);
      }
    }

    await note(trainingId, 'Squat plan', ItemLabel.red);
    await note(winterId, 'Week 1 session', ItemLabel.red);
    await note(winterId, 'Deload week', ItemLabel.teal);
    await note(groceriesId, 'Shopping', ItemLabel.red);
    await note(trainingId, 'Warm-up notes', ItemLabel.none);
  });

  tearDown(() async => db.close());

  group('SearchFilter.labels', () {
    NoteMetadata labelled(ItemLabel label, {String? folderId}) => NoteMetadata(
      id: 'n',
      folderId: folderId ?? trainingId,
      title: 't',
      preview: 'p',
      contentLength: 1,
      chunkCount: 1,
      isCompressed: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      label: label,
    );

    test('an empty set is no filter, not a filter matching nothing', () {
      const filter = SearchFilter();
      expect(filter.matches(labelled(ItemLabel.none)), isTrue);
      expect(filter.matches(labelled(ItemLabel.blue)), isTrue);
    });

    test('one colour admits that colour only', () {
      const filter = SearchFilter(labels: {ItemLabel.red});
      expect(filter.matches(labelled(ItemLabel.red)), isTrue);
      expect(filter.matches(labelled(ItemLabel.teal)), isFalse);
      expect(filter.matches(labelled(ItemLabel.none)), isFalse);
    });

    test('several colours are OR-ed, never AND-ed', () {
      const filter = SearchFilter(labels: {ItemLabel.red, ItemLabel.teal});
      expect(filter.matches(labelled(ItemLabel.red)), isTrue);
      expect(filter.matches(labelled(ItemLabel.teal)), isTrue);
      expect(filter.matches(labelled(ItemLabel.blue)), isFalse);
    });

    test('a colour narrows inside a folder scope, it does not widen it', () {
      final filter = SearchFilter(
        folderIds: {trainingId},
        labels: const {ItemLabel.red},
      );
      expect(filter.matches(labelled(ItemLabel.red)), isTrue);
      expect(
        filter.matches(labelled(ItemLabel.red, folderId: groceriesId)),
        isFalse,
      );
    });
  });

  /// The listing a colour chip produces with the field empty. It reads the
  /// colour out of SQLite rather than filtering a page of notes in memory,
  /// which is what makes the cap mean "rows shown" and what stops a labelled
  /// note older than the newest few hundred from disappearing.
  group('labelledNotes', () {
    test('a colour alone lists every note wearing it', () async {
      final listing = await search.labelledNotes(
        labels: const {ItemLabel.red},
        limit: 50,
      );

      expect(
        listing.results.map((r) => r.metadata.title),
        unorderedEquals(<String>['Shopping', 'Week 1 session', 'Squat plan']),
      );
      expect(listing.total, 3);
    });

    /// The idle list this listing stands in for is newest-first, so this one
    /// is too.
    test('the rows come back newest first', () async {
      // Straight to the column: `updated_at` is stored to the second, so
      // five notes created inside one test tick are a five-way tie that the
      // id tiebreak, not recency, would settle.
      await db.customStatement(
        "UPDATE notes SET updated_at = updated_at + 600 "
        "WHERE title = 'Squat plan'",
      );

      final listing = await search.labelledNotes(
        labels: const {ItemLabel.red},
        limit: 50,
      );

      expect(listing.results.first.metadata.title, 'Squat plan');
    });

    test('those rows carry no match offsets to highlight', () async {
      final listing = await search.labelledNotes(
        labels: const {ItemLabel.red},
        limit: 50,
      );

      expect(listing.results.every((r) => r.matches.isEmpty), isTrue);
    });

    test('several colours are OR-ed', () async {
      final listing = await search.labelledNotes(
        labels: const {ItemLabel.red, ItemLabel.teal},
        limit: 50,
      );

      expect(listing.results, hasLength(4));
      expect(
        listing.results.map((r) => r.metadata.title),
        contains('Deload week'),
      );
      expect(listing.total, 4);
    });

    test('the folder scope still applies', () async {
      final listing = await search.labelledNotes(
        labels: const {ItemLabel.red},
        folderIds: await folders.subtreeIds(trainingId),
        limit: 50,
      );

      expect(
        listing.results.map((r) => r.metadata.title),
        unorderedEquals(<String>['Week 1 session', 'Squat plan']),
      );
      expect(listing.total, 2);
    });

    test('an empty folder scope beats a colour', () async {
      final listing = await search.labelledNotes(
        labels: const {ItemLabel.red},
        folderIds: const {},
        limit: 50,
      );

      expect(listing.results, isEmpty);
      expect(listing.total, 0);
    });

    test('no colour lists nothing', () async {
      final listing = await search.labelledNotes(labels: const {}, limit: 50);

      expect(listing.results, isEmpty);
      expect(listing.total, 0);
    });

    /// The bug this method exists for: the old pass read the newest 300 notes
    /// and kept the coloured ones, so a red note with 300 newer unlabelled
    /// notes above it was simply not there — and no amount of raising the cap
    /// makes that right.
    test(
      'a labelled note older than 300 newer notes is still listed',
      () async {
        await _seedNewerNotes(db, folderId: groceriesId, count: 300);

        final listing = await search.labelledNotes(
          labels: const {ItemLabel.red},
          limit: 50,
        );

        expect(
          listing.results.map((r) => r.metadata.title),
          contains('Squat plan'),
        );
        expect(listing.total, 3);
      },
    );

    test('the total counts past the cap the listing stops at', () async {
      final listing = await search.labelledNotes(
        labels: const {ItemLabel.red},
        limit: 2,
      );

      expect(listing.results, hasLength(2));
      expect(
        listing.total,
        3,
        reason:
            'the header says how many notes the colour gathers, not how many '
            'rows fitted under the cap',
      );
    });
  });

  group('quickSearch with an empty query', () {
    test('no colour still finds nothing at all', () async {
      expect(await search.quickSearch(''), isEmpty);
      expect(await search.quickSearch('   '), isEmpty);
    });

    test('a colour does not make an empty query a listing', () async {
      expect(
        await search.quickSearch('', labels: const {ItemLabel.red}, limit: 50),
        isEmpty,
        reason:
            'with nothing typed there is nothing to search; the colour is a '
            'listing, and labelledNotes is what answers it',
      );
    });
  });

  group('quickSearch with a query', () {
    test('a colour narrows the hits rather than replacing them', () async {
      final all = await search.quickSearch('week', limit: 50);
      expect(all.map((r) => r.metadata.title), hasLength(2));

      final teal = await search.quickSearch(
        'week',
        labels: const {ItemLabel.teal},
        limit: 50,
      );

      expect(teal.map((r) => r.metadata.title), ['Deload week']);
    });

    test('a colour nothing in the query wears finds nothing', () async {
      final results = await search.quickSearch(
        'deload',
        labels: const {ItemLabel.red},
        limit: 50,
      );

      expect(results, isEmpty);
    });
  });

  group('the indexed pass', () {
    test('filters by colour too', () async {
      final results = await search.search(
        'squat',
        filter: const SearchFilter(labels: {ItemLabel.teal}),
      );

      expect(results.map((r) => r.metadata.title), ['Deload week']);
    });

    test('colour and folder scope compose', () async {
      final results = await search.search(
        'squat',
        filter: SearchFilter(
          folderIds: await folders.subtreeIds(trainingId),
          labels: const {ItemLabel.red},
        ),
      );

      expect(
        results.map((r) => r.metadata.title),
        unorderedEquals(<String>['Squat plan', 'Week 1 session']),
      );
    });
  });

  group('labelsInUse', () {
    test('offers only the colours notes actually wear', () async {
      expect(await notes.labelsInUse(), [ItemLabel.red, ItemLabel.teal]);
    });

    test('a folder scope narrows the offer', () async {
      expect(await notes.labelsInUse(folderIds: {groceriesId}), [
        ItemLabel.red,
      ]);
    });
  });
}

/// [count] unlabelled notes stamped newer than everything the suite seeded,
/// inserted straight into the table: this is about what a *read* can find, so
/// the chunk and FTS writes the DAO would do are cost without a subject.
Future<void> _seedNewerNotes(
  AppDatabase db, {
  required String folderId,
  required int count,
}) async {
  final newer = DateTime.now().add(const Duration(days: 1));
  await db.batch((batch) {
    for (var i = 0; i < count; i++) {
      batch.insert(
        db.notes,
        NotesCompanion.insert(
          id: 'filler$i',
          folderId: folderId,
          title: 'Filler $i',
          hlcTimestamp: '0',
          deviceId: 'test',
          createdAt: newer,
          updatedAt: newer,
        ),
      );
    }
  });
}
