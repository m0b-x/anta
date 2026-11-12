import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/database/daos/shared_row_dao.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_indexes.dart';
import 'package:anta/database/migrations/database_migrations.dart';
import 'package:anta/database/migrations/database_schema.dart';
import 'package:anta/database/migrations/shared_row_fences.dart';
import 'package:anta/models/item_label.dart';

import 'support/db_test_support.dart';

/// The fences (`docs/cloud-sharing-foundations.md` §7, `SharedRowFences`):
/// a row another account shares with this one is stored, changed and
/// removed by the reader of shared rows alone. Every other write of one
/// does nothing — whatever path it takes, one row or many — while the
/// person's own rows in the same statement are written as before.
void main() {
  late AppDatabase db;

  const partner = 'partner';
  final day = DateTime.utc(2026, 6, 1);

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  Future<void> event(String id, {String title = 'Event'}) =>
      db.calendarEventDao.upsert(
        CalendarEventsCompanion.insert(
          id: id,
          title: title,
          category: 'general',
          startDate: day,
          ruleKind: 'weekly',
          createdAt: day,
          updatedAt: day,
        ),
      );

  Future<T> one<T>(String sql, [List<Object?> args = const []]) async {
    final row = await db
        .customSelect(sql, variables: [for (final a in args) Variable(a)])
        .getSingle();
    return row.data.values.single as T;
  }

  /// What the reader would have stored: a shared event with a skipped day
  /// and a day's text, a shared folder with a note in it, and beside them
  /// rows of the person's own.
  late String sharedFolder;
  late String sharedNote;
  late String ownFolder;
  late String ownNote;

  Future<void> seed() async {
    await event('shared');
    await event('own');
    await db.eventSkipDao.markSkipped('shared', day);
    await db.eventOccurrenceDao.upsert(
      EventOccurrenceDescriptionsCompanion.insert(
        eventId: 'shared',
        day: day,
        description: 'The owner\'s text',
        createdAt: day,
        updatedAt: day,
      ),
    );
    sharedFolder = (await db.folderDao.createFolder(name: 'Theirs')).id;
    sharedNote = (await db.noteDao.createNote(
      folderId: sharedFolder,
      title: 'Their note',
      preview: 'Their text',
      content: 'Their text',
    )).id;
    ownFolder = (await db.folderDao.createFolder(name: 'Mine')).id;
    ownNote = (await db.noteDao.createNote(
      folderId: ownFolder,
      title: 'My note',
      preview: 'My text',
      content: 'My text',
    )).id;
    // As the reader stores them: under the partner's account.
    for (final (table, where, arg) in [
      ('calendar_events', 'id = ?', 'shared'),
      ('calendar_event_skips', 'event_id = ?', 'shared'),
      ('calendar_event_occurrences', 'event_id = ?', 'shared'),
      ('folders', 'id = ?', sharedFolder),
      ('notes', 'id = ?', sharedNote),
    ]) {
      await db.customStatement(
        "UPDATE $table SET owner_id = '$partner' WHERE $where",
        [arg],
      );
    }
    await db.syncDao.setValue(SyncDao.keySharedOwner, partner);
    await db.syncOutboxDao.clear();
  }

  test('while a database holds no shared row every write runs as it always '
      'did, whatever owner a row carries', () async {
    await event('e1');
    await db.customStatement(
      "UPDATE calendar_events SET owner_id = 'anyone' WHERE id = 'e1'",
    );

    await event('e1', title: 'Renamed');
    expect(
      await one<String>("SELECT title FROM calendar_events WHERE id = 'e1'"),
      'Renamed',
    );
    await db.customStatement("DELETE FROM calendar_events WHERE id = 'e1'");
    expect(await one<int>('SELECT COUNT(*) FROM calendar_events'), 0);
  });

  group('a shared row', () {
    setUp(seed);

    test('is not changed by a save, a rename, a move, a label or a delete '
        'through the app\'s own writers — each does nothing, and the two an '
        'editor would take for a save that was kept say so', () async {
      await event('shared', title: 'Changed here');
      await db.calendarEventDao.tombstoneEventCascade('shared');
      await db.calendarEventDao.softDeleteById('shared');
      await db.folderDao.updateFolder(id: sharedFolder, name: 'Renamed here');
      await db.folderDao.updateFolderLabel(
        id: sharedFolder,
        label: ItemLabel.teal,
      );
      await db.folderDao.moveFolder(
        id: sharedFolder,
        targetParentId: ownFolder,
      );
      await db.folderDao.softDeleteFolderWithDescendants(sharedFolder);
      await db.syncOutboxDao.clear();
      await expectLater(
        db.noteDao.updateNote(
          id: sharedNote,
          title: 'Renamed here',
          preview: 'Changed here',
          content: 'Changed here',
        ),
        throwsA(isA<SharedRowException>()),
      );
      await expectLater(
        db.noteDao.moveNote(id: sharedNote, targetFolderId: ownFolder),
        throwsA(isA<SharedRowException>()),
      );
      expect(
        await db.syncOutboxDao.count(),
        0,
        reason: 'a refused save queues nothing — not a chunk never stored',
      );
      await db.noteDao.softDeleteNote(sharedNote);

      final sharedEvent = (await db.calendarEventDao.getByIdsIncludingDeleted([
        'shared',
      ])).single;
      expect(sharedEvent.title, 'Event');
      expect(sharedEvent.isDeleted, isFalse);
      final folder = (await db.folderDao.getByIdsIncludingDeleted([
        sharedFolder,
      ])).single;
      expect(folder.name, 'Theirs');
      expect(folder.parentId, isNull);
      expect(folder.label, ItemLabel.none.storageValue);
      expect(folder.isDeleted, isFalse);
      final note = (await db.noteDao.getByIdsIncludingDeleted([
        sharedNote,
      ])).single;
      expect(note.title, 'Their note');
      expect(note.folderId, sharedFolder);
      expect(note.isDeleted, isFalse);
      expect(await db.contentChunkDao.loadContent(sharedNote), 'Their text');
    });

    test('nor its skipped days and day texts, while a presence mark of the '
        'person\'s own on it is theirs to keep', () async {
      final later = DateTime.utc(2026, 6, 8);

      await db.eventSkipDao.markSkipped('shared', later);
      await db.eventOccurrenceDao.upsert(
        EventOccurrenceDescriptionsCompanion.insert(
          eventId: 'shared',
          day: day,
          description: 'Changed here',
          createdAt: day,
          updatedAt: day,
        ),
      );
      await db.eventAbsenceDao.setStatus('shared', day, PresenceStatus.present);

      expect(
        await one<int>(
          "SELECT COUNT(*) FROM calendar_event_skips WHERE event_id = 'shared'",
        ),
        1,
      );
      expect(
        await one<String>(
          'SELECT description FROM calendar_event_occurrences '
          "WHERE event_id = 'shared'",
        ),
        'The owner\'s text',
      );
      expect(
        await one<int>(
          'SELECT COUNT(*) FROM calendar_event_absences '
          "WHERE event_id = 'shared'",
        ),
        1,
      );
    });

    test('keeps what the person marked on it when they delete it, or delete '
        'every event of theirs: the event stays, so its presence marks stay '
        'live and nothing of it is queued', () async {
      await db.eventAbsenceDao.setStatus('shared', day, PresenceStatus.present);
      await db.eventAbsenceDao.setStatus('own', day, PresenceStatus.present);
      await db.syncOutboxDao.clear();
      Future<Map<String, int>> marks() async => {
        for (final row
            in await db
                .customSelect(
                  'SELECT event_id, is_deleted FROM calendar_event_absences',
                )
                .get())
          row.read<String>('event_id'): row.read<int>('is_deleted'),
      };

      await db.calendarEventDao.tombstoneEventCascade('shared');

      expect(await marks(), {'shared': 0, 'own': 0});
      expect(await db.syncOutboxDao.count(), 0);

      final wiped = await db.calendarEventDao.tombstoneAll(ownerUid: null);

      expect(wiped, ['own']);
      expect(await marks(), {'shared': 0, 'own': 1});
      expect(
        await one<int>(
          "SELECT is_deleted FROM calendar_events WHERE id = 'shared'",
        ),
        0,
      );
    });

    test('deleted by its owner, does not take the counts the person kept on '
        'it: the sweep that follows a deleted note is for notes of their '
        'own', () async {
      final now = DateTime.now();
      await db.counterDao.insertCounter(
        CountersCompanion.insert(
          id: 'laps',
          name: 'Laps',
          createdAt: now,
          scope: const Value('perNote'),
        ),
      );
      await db.counterDao.upsertValue('laps', sharedNote, 3);
      await db.counterDao.upsertValue('laps', ownNote, 5);
      // Both notes deleted after the counts: the shared one by its owner,
      // as the reader stores a tombstone; the own one by a pulled delete.
      await db.sharedRowDao.writing(
        () => db.customStatement(
          "UPDATE notes SET is_deleted = 1, deleted_at = ?, "
          "hlc_timestamp = 'ffffffffffff:0000:Z'",
          [now.millisecondsSinceEpoch ~/ 1000],
        ),
      );

      final swept = await db.counterDao.sweepOrphanValues();

      expect(swept, ['laps|$ownNote']);
      expect(
        await one<int>(
          'SELECT is_deleted FROM counter_values WHERE note_id = ?',
          [sharedNote],
        ),
        0,
      );
    });

    test('is passed over by a statement over many rows, which writes every '
        'row of the person\'s own all the same', () async {
      await db.customStatement("UPDATE calendar_events SET title = 'All'");
      await db.customStatement("UPDATE notes SET title = 'All'");
      await db.customStatement('DELETE FROM calendar_event_skips');
      await db.eventSkipDao.markSkipped('own', day);
      await db.customStatement('DELETE FROM calendar_event_skips');

      expect(
        {
          for (final row
              in await db
                  .customSelect('SELECT id, title FROM calendar_events')
                  .get())
            row.read<String>('id'): row.read<String>('title'),
        },
        {'shared': 'Event', 'own': 'All'},
      );
      expect(
        {
          for (final row
              in await db.customSelect('SELECT id, title FROM notes').get())
            row.read<String>('id'): row.read<String>('title'),
        },
        {sharedNote: 'Their note', ownNote: 'All'},
      );
      expect(
        await one<String>('SELECT event_id FROM calendar_event_skips'),
        'shared',
      );
    });

    test('cannot be made up or re-owned: no row is stored as the partner\'s '
        'and none of the person\'s own is turned into one', () async {
      await db
          .into(db.calendarEvents)
          .insert(
            CalendarEventsCompanion.insert(
              id: 'forged',
              title: 'Forged',
              category: 'general',
              startDate: day,
              ruleKind: 'weekly',
              createdAt: day,
              updatedAt: day,
              ownerId: const Value(partner),
            ),
          );
      await db.customStatement(
        "UPDATE calendar_events SET owner_id = '$partner' WHERE id = 'own'",
      );
      await db.customStatement(
        "UPDATE calendar_events SET owner_id = NULL WHERE id = 'shared'",
      );

      expect(
        await one<int>(
          "SELECT COUNT(*) FROM calendar_events WHERE id = 'forged'",
        ),
        0,
      );
      expect(
        await one<String?>(
          "SELECT owner_id FROM calendar_events WHERE id = 'own'",
        ),
        isNull,
      );
      expect(
        await one<String?>(
          "SELECT owner_id FROM calendar_events WHERE id = 'shared'",
        ),
        partner,
      );
    });

    test('takes nothing of the person\'s own under it: a note or a folder '
        'created inside a shared folder is refused by name, and one moved '
        'in stays where it was', () async {
      await expectLater(
        db.noteDao.createNote(folderId: sharedFolder, title: 'Mine, in theirs'),
        throwsA(isA<SharedRowException>()),
      );
      await expectLater(
        db.folderDao.createFolder(
          name: 'Mine, in theirs',
          parentId: sharedFolder,
        ),
        throwsA(isA<SharedRowException>()),
      );
      // An import into one says why, where its read-back of a row that was
      // never stored used to fail with no word of it.
      await expectLater(
        db.noteDao.importNote(
          folderId: sharedFolder,
          title: 'Imported',
          createdAt: day,
          updatedAt: day,
          content: 'Imported text',
        ),
        throwsA(isA<SharedRowException>()),
      );
      await expectLater(
        db.folderDao.importFolder(
          name: 'Imported',
          parentId: sharedFolder,
          createdAt: day,
        ),
        throwsA(isA<SharedRowException>()),
      );
      await db.syncOutboxDao.clear();
      await expectLater(
        db.noteDao.moveNote(id: ownNote, targetFolderId: sharedFolder),
        throwsA(isA<SharedRowException>()),
      );
      expect(await db.syncOutboxDao.count(), 0);
      await db.folderDao.moveFolder(
        id: ownFolder,
        targetParentId: sharedFolder,
      );
      // Nor is a chunk of the person's own moved under a shared note.
      await db.customStatement(
        'UPDATE content_chunks SET note_id = ? WHERE note_id = ?',
        [sharedNote, ownNote],
      );
      expect(await db.contentChunkDao.loadContent(ownNote), 'My text');

      expect(
        await one<int>('SELECT COUNT(*) FROM notes WHERE folder_id = ?', [
          sharedFolder,
        ]),
        1,
      );
      expect(
        await one<int>('SELECT COUNT(*) FROM folders WHERE parent_id = ?', [
          sharedFolder,
        ]),
        0,
      );
      expect(
        (await db.noteDao.getByIdsIncludingDeleted([ownNote])).single.folderId,
        ownFolder,
      );
      expect(
        (await db.folderDao.getByIdsIncludingDeleted([
          ownFolder,
        ])).single.parentId,
        isNull,
      );
    });

    test('is not the person\'s to share', () async {
      expect(await db.folderDao.setSharedPair(sharedFolder, 'pair-1'), isFalse);
      expect(
        await db.calendarEventDao.setSharedPair('shared', 'pair-1'),
        isFalse,
      );
      expect(await db.syncDao.anyShareMark(), isFalse);
      expect(await db.syncOutboxDao.count(), 0);
    });

    test('is told from the person\'s own by one question, which a surface '
        'asks before it offers an edit', () async {
      final dao = db.sharedRowDao;

      expect(await dao.isShared('calendar_events', 'shared'), isTrue);
      expect(await dao.isShared('calendar_events', 'own'), isFalse);
      expect(await dao.isShared('folders', sharedFolder), isTrue);
      expect(await dao.isShared('notes', ownNote), isFalse);
      expect(await dao.isShared('notes', 'no-such-note'), isFalse);
      expect(
        await dao.sharedAmong('calendar_events', ['shared', 'own', 'none']),
        ['shared'],
      );
    });

    test('is the reader\'s to write: inside its transaction every write of '
        'one goes through, and the way in closes behind it — on a rollback '
        'too', () async {
      await db.sharedRowDao.writing(
        () => db.customStatement(
          "UPDATE calendar_events SET title = 'The owner renamed it' "
          "WHERE id = 'shared'",
        ),
      );
      expect(
        await one<String>(
          "SELECT title FROM calendar_events WHERE id = 'shared'",
        ),
        'The owner renamed it',
      );
      expect(await db.syncDao.getValue(SyncDao.keySharedWriting), isNull);

      await expectLater(
        db.sharedRowDao.writing(() async {
          await db.customStatement(
            "DELETE FROM calendar_events WHERE id = 'shared'",
          );
          throw StateError('the page failed');
        }),
        throwsStateError,
      );
      expect(await db.syncDao.getValue(SyncDao.keySharedWriting), isNull);
      expect(
        await one<int>(
          "SELECT COUNT(*) FROM calendar_events WHERE id = 'shared'",
        ),
        1,
        reason: 'rolled back with the rest',
      );
      await event('shared', title: 'Changed here');
      expect(
        await one<String>(
          "SELECT title FROM calendar_events WHERE id = 'shared'",
        ),
        'The owner renamed it',
      );
    });

    test('gives way to a row of the person\'s own under the same id: it is '
        'removed, with its text, and only it', () async {
      await db.sharedRowDao.evict('notes', [sharedNote, ownNote]);

      expect(await db.noteDao.getByIdsIncludingDeleted([sharedNote]), isEmpty);
      expect(
        await one<int>(
          'SELECT COUNT(*) FROM content_chunks WHERE note_id = ?',
          [sharedNote],
        ),
        0,
      );
      expect(
        await db.noteDao.getByIdsIncludingDeleted([ownNote]),
        hasLength(1),
      );
      expect(await db.contentChunkDao.loadContent(ownNote), 'My text');
    });

    test(
      'given way to, takes along what hung under it — an event its '
      'skipped days and day texts, a folder the shared notes inside it — '
      'while a shared folder under it stays shared, at the top level',
      () async {
        // A shared folder inside the shared one, with a note of its own, as
        // the reader would have stored them.
        final inner = (await db.folderDao.createFolder(name: 'Inner')).id;
        final innerNote = (await db.noteDao.createNote(
          folderId: inner,
          title: 'Deep',
          preview: 'Deep',
          content: 'Deep',
        )).id;
        await db.sharedRowDao.writing(() async {
          await db.customStatement(
            'UPDATE folders SET owner_id = ?, parent_id = ? WHERE id = ?',
            [partner, sharedFolder, inner],
          );
          await db.customStatement(
            'UPDATE notes SET owner_id = ? WHERE id = ?',
            [partner, innerNote],
          );
        });
        await db.syncOutboxDao.clear();

        await db.sharedRowDao.evict('calendar_events', ['shared', 'own']);
        await db.sharedRowDao.evict('folders', [sharedFolder, ownFolder]);

        expect(
          await one<int>(
            "SELECT COUNT(*) FROM calendar_events WHERE id IN ('shared', 'own')",
          ),
          1,
          reason: 'the person\'s own event stays',
        );
        for (final days in [
          'calendar_event_skips',
          'calendar_event_occurrences',
        ]) {
          expect(
            await one<int>(
              "SELECT COUNT(*) FROM $days WHERE event_id = 'shared'",
            ),
            0,
            reason: days,
          );
        }
        expect(
          await db.folderDao.getByIdsIncludingDeleted([sharedFolder]),
          isEmpty,
        );
        expect(
          await db.noteDao.getByIdsIncludingDeleted([sharedNote]),
          isEmpty,
        );
        final kept = (await db.folderDao.getByIdsIncludingDeleted([
          inner,
        ])).single;
        expect(kept.ownerId, partner);
        expect(kept.parentId, isNull);
        expect(await db.contentChunkDao.loadContent(innerNote), 'Deep');
        expect(
          await db.folderDao.getByIdsIncludingDeleted([ownFolder]),
          hasLength(1),
        );
        expect(await db.contentChunkDao.loadContent(ownNote), 'My text');
        expect(await db.syncOutboxDao.count(), 0, reason: 'nothing is queued');
      },
    );

    test(
      'is taken out by an import that carries an event of the person\'s '
      'own under its id, day rows and all: the replace would have removed '
      'it silently and left those hanging under the person\'s event',
      () async {
        await db.calendarEventDao.importAll([
          CalendarEventsCompanion.insert(
            id: 'shared',
            title: 'Mine, restored',
            category: 'general',
            startDate: day,
            ruleKind: 'weekly',
            createdAt: day,
            updatedAt: day,
          ),
        ]);

        final restored = (await db.calendarEventDao.getByIdsIncludingDeleted([
          'shared',
        ])).single;
        expect(restored.title, 'Mine, restored');
        expect(restored.ownerId, isNull);
        for (final days in [
          'calendar_event_skips',
          'calendar_event_occurrences',
        ]) {
          expect(
            await one<int>(
              "SELECT COUNT(*) FROM $days WHERE event_id = 'shared'",
            ),
            0,
            reason: days,
          );
        }
        expect(
          await db.syncOutboxDao.count(),
          1,
          reason: 'the own event, queued',
        );
      },
    );
  });

  test('a database that got its fences from an earlier build takes the '
      'current ones in the next step: a fence is created only when absent, '
      'so one whose body changed would otherwise keep its first body for '
      'good', () async {
    Future<Map<String, String>> fences() async => {
      for (final row
          in await db
              .customSelect(
                "SELECT name, sql FROM sqlite_master WHERE type = 'trigger'",
              )
              .get())
        row.read<String>('name'): row.read<String>('sql'),
    };
    final current = await fences();
    // As the v54 build left it: the chunk-update fence looking at the old
    // note only — and a fence a later build no longer has.
    await db.customStatement('DROP TRIGGER shared_fence_chunks_update');
    await db.customStatement(
      'CREATE TRIGGER shared_fence_chunks_update BEFORE UPDATE ON '
      'content_chunks WHEN 0 BEGIN SELECT RAISE(IGNORE); END',
    );
    await db.customStatement(
      'CREATE TRIGGER shared_fence_retired BEFORE DELETE ON content_chunks '
      'WHEN 0 BEGIN SELECT RAISE(IGNORE); END',
    );
    await DatabaseIndexes(db).createSharedRowFences();
    expect(
      (await fences())['shared_fence_chunks_update'],
      isNot(current['shared_fence_chunks_update']),
      reason: 'creating again leaves an existing fence as it is',
    );

    await DatabaseMigrations(db).runMigrations(
      db.createMigrator(),
      DatabaseSchema.v54SharedRowFences,
      DatabaseSchema.v55FencesAgain,
    );

    expect(await fences(), current);
  });

  test('every fence is created by name on a fresh database, one statement '
      'each, and creating them again changes nothing', () async {
    Future<Set<String>> triggers() async => {
      for (final row
          in await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'trigger'",
              )
              .get())
        row.read<String>('name'),
    };

    final created = await triggers();
    expect(created, hasLength(SharedRowFences.statements.length));
    expect(created.every((name) => name.startsWith('shared_fence_')), isTrue);

    for (final statement in SharedRowFences.statements) {
      await db.customStatement(statement);
    }
    expect(await triggers(), created);
  });
}
