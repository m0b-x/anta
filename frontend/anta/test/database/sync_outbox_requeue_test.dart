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
    expect(syncedTables, hasLength(18));
    expect(
      [
        for (final t in syncedTables)
          if (t.travelsWithParent) t.name,
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

  test('content chunks are never queued but count among the stamps', () async {
    final folder = await db.folderDao.createFolder(name: 'Notes');
    const highest = 'fffffffffff0:0000:chunk-device';
    await db.customStatement(
      'INSERT INTO content_chunks (id, note_id, chunk_index, content, '
      "is_compressed, hlc_timestamp, device_id, version) VALUES ('k1', "
      "'n1', 0, 'body', 0, ?, 'chunk-device', 1)",
      [highest],
    );
    await db.syncOutboxDao.clear();

    await db.syncOutboxDao.requeueAll(boundUid: 'me');

    expect((await outbox()).keys, [('folders', folder.id)]);
    expect(await db.syncOutboxDao.maxHlc(), highest);
  });

  test('maxHlc is the highest row stamp, null on an empty database', () async {
    expect(await db.syncOutboxDao.maxHlc(), isNull);

    await db.folderDao.createFolder(name: 'First');
    await event('e1');
    final last = await db.folderDao.createFolder(name: 'Last');

    expect(await db.syncOutboxDao.maxHlc(), last.hlcTimestamp);
  });
}
