import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/note_storage_service.dart';

import 'support/db_test_support.dart';

/// Guards what a `[[title]]` wiki link actually resolves to, through the real
/// stack — service, repository, DAO, SQLite — because the rule is split
/// across all four and only the whole of it is the behaviour.
///
/// SQLite decides what "the same title" means (it folds the case, and its
/// `LOWER` is ASCII-only); the service decides which note wins when several
/// share a title, since titles are unique per folder, not globally. Both
/// halves are pinned here, including the non-ASCII limit — a link is a
/// promise that the same text always opens the same note, so a silent change
/// to either half breaks notes users have already written.
void main() {
  late AppDatabase db;
  late NoteStorageService service;

  setUp(() async {
    db = await openTestDatabase();
    service = NoteStorageService(repository: NoteRepository(database: db));
  });
  tearDown(() async => db.close());

  Future<String> seedFolder(String name) async {
    final folder = await db.folderDao.createFolder(name: name);
    return folder.id;
  }

  Future<Note> seedNote(String folderId, String title, {String preview = ''}) {
    return db.noteDao.createNote(
      folderId: folderId,
      title: title,
      preview: preview,
    );
  }

  /// Writes `updatedAt` directly rather than through `NoteDao.updateNote`,
  /// which stamps `DateTime.now()`. Recency has to be an assertion about the
  /// values, not about how fast the test ran.
  Future<void> setUpdatedAt(Note note, DateTime updatedAt) async {
    await db.customUpdate(
      'UPDATE notes SET updated_at = ? WHERE id = ?',
      variables: [Variable<DateTime>(updatedAt), Variable<String>(note.id)],
      updates: {db.notes},
    );
  }

  group('matching', () {
    test('an exact title resolves to its note', () async {
      final folder = await seedFolder('Training');
      // A sibling first, so the note under test lands at position 1 and the
      // assertion below cannot pass on a dropped field reading back as 0.
      await seedNote(folder, 'Warm-up');
      final note = await seedNote(folder, 'Leg Day', preview: 'squats, 5x5');
      // Fixed rather than `DateTime.now()`: the recency rule further down this
      // file reads `updatedAt`, so the row-to-metadata mapping has to carry it
      // through unchanged. A units error that still preserved *ordering* —
      // seconds read back as milliseconds — would slip past every other test
      // here, since they all only compare ids.
      final stamped = DateTime.utc(2026, 3, 14, 9, 26, 53);
      await setUpdatedAt(note, stamped);

      final resolved = await service.resolveNoteByTitle('Leg Day');

      expect(resolved?.id, note.id);
      expect(resolved?.folderId, folder);
      expect(resolved?.title, 'Leg Day');
      // Drift reads a stored `DateTime` back as a local one, so the instant is
      // the assertion, not the flag.
      expect(resolved?.updatedAt, stamped.toLocal());
      expect(resolved?.createdAt, note.createdAt);
      expect(resolved?.preview, 'squats, 5x5');
      expect(resolved?.position, 1);
    });

    test('ASCII case is folded in both directions', () async {
      final folder = await seedFolder('Training');
      final note = await seedNote(folder, 'Leg Day');

      expect((await service.resolveNoteByTitle('leg day'))?.id, note.id);
      expect((await service.resolveNoteByTitle('LEG DAY'))?.id, note.id);
      expect((await service.resolveNoteByTitle('lEg dAy'))?.id, note.id);
    });

    test('both the query and the stored title are trimmed', () async {
      final folder = await seedFolder('Training');
      final note = await seedNote(folder, 'Leg Day');
      // A title stored with its own stray whitespace — the editor's title
      // field has accepted plenty of those — is still found by the spelling
      // a user would type inside the brackets.
      final padded = await seedNote(folder, 'Push Day  ');

      expect((await service.resolveNoteByTitle('  Leg Day '))?.id, note.id);
      expect((await service.resolveNoteByTitle('Push Day'))?.id, padded.id);
    });

    test('but only of spaces on the stored side', () async {
      final folder = await seedFolder('Training');
      await seedNote(folder, 'Leg Day\t');

      // The two trims are not the same trim. SQLite's `TRIM` strips U+0020 and
      // nothing else, so the stored side keeps its tab; Dart's `trim` strips
      // all Unicode white space, so the link side can never carry one to match
      // it with. No write path trims a title — the editor's auto-save, a
      // restored backup and an imported archive all store the string they were
      // handed — so this row is reachable, and once written no `[[Leg Day]]`
      // finds it. Pinned rather than fixed: the lenient half is deliberately
      // the link, so a sloppy link still finds a clean title.
      expect(await service.resolveNoteByTitle('Leg Day'), isNull);
      // Nor does spelling the tab out, because Dart trims it off first.
      expect(await service.resolveNoteByTitle('Leg Day\t'), isNull);
    });

    test('a title resolves nothing when no note carries it', () async {
      await seedNote(await seedFolder('Training'), 'Leg Day');
      expect(await service.resolveNoteByTitle('Arm Day'), isNull);
    });

    test('a blank title resolves nothing', () async {
      await seedNote(await seedFolder('Training'), 'Leg Day');
      expect(await service.resolveNoteByTitle(''), isNull);
      expect(await service.resolveNoteByTitle('   '), isNull);
    });

    test('a partial title is not a match', () async {
      final folder = await seedFolder('Training');
      await seedNote(folder, 'Leg Day');
      // Exact only: this is a link, not a search box.
      expect(await service.resolveNoteByTitle('Leg'), isNull);
      expect(await service.resolveNoteByTitle('Leg Day 2'), isNull);
    });
  });

  group('non-ASCII titles', () {
    test('a non-ASCII title matches its own spelling', () async {
      final folder = await seedFolder('Training');
      final note = await seedNote(folder, 'Șold');

      expect((await service.resolveNoteByTitle('Șold'))?.id, note.id);
    });

    test('but its case is NOT folded — the documented limit', () async {
      final folder = await seedFolder('Training');
      await seedNote(folder, 'Șold');

      // SQLite's LOWER folds ASCII only, and both sides of the comparison go
      // through it — which is exactly why the spelling above still matches
      // itself. Folding `Ș` would need ICU, which the app does not ship.
      // Pinned rather than fixed: a link written as the title is spelled
      // always works, and that is the promise the feature makes.
      expect(await service.resolveNoteByTitle('șold'), isNull);
    });

    test('the uniqueness check and the resolver disagree about it', () async {
      final folder = await seedFolder('Training');
      final note = await seedNote(folder, 'Șold');

      // Both queries compare against the same *index expression*,
      // `LOWER(TRIM(title))` — that is what keeps both of them index-served —
      // but they normalise their *parameter* differently.
      // `noteTitleExistsInFolder` lowers it in Dart, which is Unicode-aware
      // and turns `Ș` into `ș`; `getNotesByTitle` binds the raw trimmed title
      // under SQLite's ASCII-only `LOWER(?1)`, which leaves `Ș` alone.
      expect(
        await db.noteDao.noteTitleExistsInFolder(
          folderId: folder,
          title: 'Șold',
        ),
        isFalse,
        reason:
            'the Dart-lowered `șold` cannot equal the SQLite-lowered `Șold`, '
            'so a second `Șold` in this folder is never refused as a duplicate',
      );
      // And yet the same spelling resolves. Two `Șold` notes can therefore
      // coexist in one folder and a `[[Șold]]` picks between them by recency,
      // which is the shape of the disagreement: one index expression, two
      // different rules for what the parameter means.
      expect((await service.resolveNoteByTitle('Șold'))?.id, note.id);
    });
  });

  group('tombstones', () {
    test('a deleted note is invisible to the resolver', () async {
      final folder = await seedFolder('Training');
      final note = await seedNote(folder, 'Leg Day');
      await db.noteDao.softDeleteNote(note.id);

      expect(await service.resolveNoteByTitle('Leg Day'), isNull);
    });

    test('a live namesake survives its deleted twin', () async {
      final archive = await seedFolder('Archive');
      final training = await seedFolder('Training');
      final dead = await seedNote(archive, 'Leg Day');
      final live = await seedNote(training, 'Leg Day');
      await db.noteDao.softDeleteNote(dead.id);

      expect((await service.resolveNoteByTitle('Leg Day'))?.id, live.id);
    });
  });

  group('choosing between namesakes', () {
    test('preferFolderId wins over a more recent outsider', () async {
      final training = await seedFolder('Training');
      final archive = await seedFolder('Archive');
      final here = await seedNote(training, 'Leg Day');
      final elsewhere = await seedNote(archive, 'Leg Day');
      // The outsider is the newer of the two, so recency alone would pick it.
      await setUpdatedAt(here, DateTime.utc(2026, 1, 1));
      await setUpdatedAt(elsewhere, DateTime.utc(2026, 6, 1));

      final resolved = await service.resolveNoteByTitle(
        'Leg Day',
        preferFolderId: training,
      );

      expect(resolved?.id, here.id);
      expect(resolved?.folderId, training);
    });

    test('the preference falls back when that folder has no match', () async {
      final training = await seedFolder('Training');
      final archive = await seedFolder('Archive');
      final only = await seedNote(archive, 'Leg Day');

      final resolved = await service.resolveNoteByTitle(
        'Leg Day',
        preferFolderId: training,
      );

      expect(resolved?.id, only.id);
    });

    test('the most recently updated note wins with no preference', () async {
      final training = await seedFolder('Training');
      final archive = await seedFolder('Archive');
      final older = await seedNote(training, 'Leg Day');
      final newer = await seedNote(archive, 'Leg Day');
      await setUpdatedAt(older, DateTime.utc(2026, 1, 1));
      await setUpdatedAt(newer, DateTime.utc(2026, 6, 1));

      expect((await service.resolveNoteByTitle('Leg Day'))?.id, newer.id);
    });

    test('recency also decides inside the preferred folder', () async {
      final training = await seedFolder('Training');
      final older = await seedNote(training, 'Leg Day');
      final newer = await seedNote(training, 'Leg Day');
      await setUpdatedAt(older, DateTime.utc(2026, 1, 1));
      await setUpdatedAt(newer, DateTime.utc(2026, 6, 1));

      final resolved = await service.resolveNoteByTitle(
        'Leg Day',
        preferFolderId: training,
      );

      expect(resolved?.id, newer.id);
    });

    test('a tie on updatedAt breaks by the smaller id', () async {
      final training = await seedFolder('Training');
      final archive = await seedFolder('Archive');
      final a = await seedNote(training, 'Leg Day');
      final b = await seedNote(archive, 'Leg Day');
      // Identical timestamps are reachable — an import stamps a whole archive
      // at once — and a link must still open the same note every time.
      final same = DateTime.utc(2026, 3, 1);
      await setUpdatedAt(a, same);
      await setUpdatedAt(b, same);

      final expected = a.id.compareTo(b.id) < 0 ? a.id : b.id;
      expect((await service.resolveNoteByTitle('Leg Day'))?.id, expected);
      expect((await service.resolveNoteByTitle('Leg Day'))?.id, expected);
    });
  });
}
