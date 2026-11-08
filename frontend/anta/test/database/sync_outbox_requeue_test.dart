import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/crdt/synced_tables.dart';
import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';

/// Guards the re-seed of the initial merge at bind (D15): `requeueAll` queues
/// every synced row at the stamp it carries, under the key a local write
/// would have queued it with, and `maxHlc` finds the database's highest stamp.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  Future<Map<(String, String), (String, String)>> outbox() async => {
    for (final row in await db.syncOutboxDao.pending())
      (row.syncedTable, row.rowKey): (row.hlc, row.op),
  };

  Future<void> event(String id) {
    final now = DateTime.now();
    return db.calendarEventDao.upsert(
      CalendarEventsCompanion.insert(
        id: id,
        title: 'Event $id',
        category: 'gym',
        startDate: DateTime.utc(2026, 1, 1),
        ruleKind: 'daily',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  test('the registry names exactly the tables with a row stamp', () async {
    final stamped = <String>{};
    for (final table in await tableNames(db)) {
      final columns = await db.customSelect('PRAGMA table_info($table)').get();
      if (columns.any((c) => c.read<String>('name') == 'hlc_timestamp')) {
        stamped.add(table);
      }
    }

    expect({for (final t in syncedTables) t.name}, stamped);
    expect(syncedTables, hasLength(19));
    expect(
      [
        for (final t in syncedTables)
          if (t.contentAddressed) t.name,
      ],
      ['content_chunks'],
    );
  });

  test('requeueing rebuilds what local writes queued, key for key', () async {
    final live = await db.folderDao.createFolder(name: 'Live');
    final gone = await db.folderDao.createFolder(name: 'Gone');
    await db.folderDao.softDeleteFolder(gone.id);
    await event('e1');
    await event('e2');
    await db.calendarEventDao.tombstoneEventCascade('e2');
    // Days either side of a DST change in the zones the app ships to, as
    // local midnights (what the pickers hand over) and as a UTC instant.
    for (final day in [
      DateTime(2026, 3, 29),
      DateTime(2026, 10, 25),
      DateTime(2026, 11, 1),
      DateTime.utc(2026, 3, 8),
    ]) {
      await db.eventSkipDao.markSkipped('e1', day);
    }
    await db.eventSkipDao.unskip('e1', DateTime(2026, 11, 1));
    await db.eventAbsenceDao.setStatus(
      'e1',
      DateTime(2026, 3, 29),
      PresenceStatus.missed,
    );
    final now = DateTime.now();
    await db.eventOccurrenceDao.upsert(
      EventOccurrenceDescriptionsCompanion.insert(
        eventId: 'e1',
        day: DateTime(2026, 10, 25),
        description: 'Heavy',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.counterDao.insertCounter(
      CountersCompanion.insert(id: 'c1', name: 'Sets', createdAt: now),
    );
    await db.counterDao.upsertValue('c1', '', 5);
    await db.counterDao.upsertValue('c1', live.id, 3);
    final queued = await outbox();
    await db.syncOutboxDao.clear();

    final count = await db.syncOutboxDao.requeueAll(boundUid: 'me');

    expect(await outbox(), queued);
    expect(count, queued.length);
    expect(queued[('folders', gone.id)]?.$2, 'tombstone');
    expect(queued[('calendar_events', 'e2')]?.$2, 'tombstone');
    expect(
      queued.keys,
      containsAll([
        ('counter_values', counterValueRowKey('c1', '')),
        ('calendar_event_skips', dayRowKey('e1', DateTime(2026, 3, 29))),
        ('calendar_event_skips', dayRowKey('e1', DateTime.utc(2026, 3, 8))),
        ('calendar_event_absences', dayRowKey('e1', DateTime(2026, 3, 29))),
        ('calendar_event_occurrences', dayRowKey('e1', DateTime(2026, 10, 25))),
      ]),
    );
  });

  test('rows of another account are never queued', () async {
    final mine = await db.folderDao.createFolder(name: 'Mine');
    final claimed = await db.folderDao.createFolder(name: 'Claimed');
    final theirs = await db.folderDao.createFolder(name: 'Theirs');
    await db.customStatement(
      "UPDATE folders SET owner_id = 'me' WHERE id = ?",
      [claimed.id],
    );
    await db.customStatement(
      "UPDATE folders SET owner_id = 'them' WHERE id = ?",
      [theirs.id],
    );
    await db.syncOutboxDao.clear();

    await db.syncOutboxDao.requeueAll(boundUid: 'me');

    final keys = {
      for (final (table, key) in (await outbox()).keys)
        if (table == 'folders') key,
    };
    expect(keys, {mine.id, claimed.id});
  });

  test('a newer pending entry is never lowered', () async {
    final folder = await db.folderDao.createFolder(name: 'Edited');
    const newer = 'ffffffffffff:0000:elsewhere';
    await db.transaction(() => db.enqueue(db.folders, folder.id, newer));

    await db.syncOutboxDao.requeueAll(boundUid: 'me');

    expect((await outbox())[('folders', folder.id)], (newer, 'upsert'));
  });

  Future<void> chunk(
    String id,
    String? hash,
    String hlc, {
    bool deleted = false,
  }) => db.customStatement(
    'INSERT INTO content_chunks (id, note_id, chunk_index, content, '
    'is_compressed, hlc_timestamp, device_id, version, is_deleted, '
    "content_hash) VALUES (?, 'n1', 0, 'body', 0, ?, 'chunk-device', 1, ?, ?)",
    [id, hlc, if (deleted) 1 else 0, hash],
  );

  test('a chunk queues once per live hash, at the highest stamp holding '
      'it; a legacy slice and a tombstone never, yet all count among the '
      'stamps', () async {
    final folder = await db.folderDao.createFolder(name: 'Notes');
    const highest = 'fffffffffff0:0000:chunk-device';
    await chunk('legacy', null, highest);
    await chunk('k1', 'h1', '000000000001:0000:chunk-device');
    await chunk('k2', 'h1', '000000000002:0000:chunk-device');
    await chunk('gone', 'h2', '000000000003:0000:chunk-device', deleted: true);
    // The chunks go by their note's owner, so they need one.
    final note = await db.noteDao.createNote(folderId: folder.id, title: 'N');
    await db.customStatement('UPDATE content_chunks SET note_id = ?', [
      note.id,
    ]);
    await db.syncOutboxDao.clear();

    await db.syncOutboxDao.requeueAll(boundUid: 'me');

    expect(await outbox(), {
      ('folders', folder.id): (folder.hlcTimestamp, 'upsert'),
      ('notes', note.id): (note.hlcTimestamp, 'upsert'),
      ('content_chunks', 'h1'): ('000000000002:0000:chunk-device', 'upsert'),
    });
    expect(await db.syncOutboxDao.maxHlc(), highest);
  });

  test('a chunk of a note another account owns is queued neither at bind '
      'nor at the wire cutover, unless a note of ours holds it too '
      '(D16)', () async {
    final folder = await db.folderDao.createFolder(name: 'Notes');
    final mine = await db.noteDao.createNote(
      folderId: folder.id,
      title: 'Mine',
      content: 'shared text',
    );
    final theirs = await db.noteDao.createNote(
      folderId: folder.id,
      title: 'Theirs',
      content: 'their secret',
      ownerId: 'them',
    );
    await db.noteDao.createNote(
      folderId: folder.id,
      title: 'Theirs too',
      content: 'shared text',
      ownerId: 'them',
    );
    final shared = (await db.contentChunkDao.hashesOf(mine.id)).single!;
    final secret = (await db.contentChunkDao.hashesOf(theirs.id)).single!;
    Future<Set<String>> chunks() async => {
      for (final (table, key) in (await outbox()).keys)
        if (table == 'content_chunks') key,
    };

    await db.syncOutboxDao.clear();
    await db.syncOutboxDao.requeueAll(boundUid: 'me');
    expect(await chunks(), {shared});

    await db.syncOutboxDao.clear();
    await db.syncOutboxDao.requeueBodies(boundUid: 'me');
    expect(await chunks(), {shared});
    expect(await chunks(), isNot(contains(secret)));
  });

  test('the wire cutover queues every live note and live hash, no other '
      'row and no tombstone', () async {
    final folder = await db.folderDao.createFolder(name: 'Notes');
    final kept = await db.noteDao.createNote(
      folderId: folder.id,
      title: 'Kept',
      content: 'a body',
    );
    final gone = await db.noteDao.createNote(
      folderId: folder.id,
      title: 'Gone',
      content: 'another body',
    );
    await db.noteDao.softDeleteNote(gone.id);
    await event('e1');
    await db.syncOutboxDao.clear();

    final queued = await db.syncOutboxDao.requeueBodies(boundUid: 'me');

    final hash = (await db.contentChunkDao.hashesOf(kept.id)).single!;
    expect(await outbox(), {
      ('notes', kept.id): (kept.hlcTimestamp, 'upsert'),
      ('content_chunks', hash): (kept.hlcTimestamp, 'upsert'),
    });
    expect(queued, 2);
  });

  test('maxHlc is the highest row stamp, null on an empty database', () async {
    expect(await db.syncOutboxDao.maxHlc(), isNull);

    await db.folderDao.createFolder(name: 'First');
    await event('e1');
    final last = await db.folderDao.createFolder(name: 'Last');

    expect(await db.syncOutboxDao.maxHlc(), last.hlcTimestamp);
  });
}
