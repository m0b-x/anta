import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/crdt/hlc.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_schema.dart';

import 'support/db_test_support.dart';

/// Guards the persisted clock (D6): the highest HLC a write queued is stored
/// in `sync_metadata['last_hlc']` inside that write's transaction, and the
/// next open seeds the clock from it — so a restart, or a wall clock set
/// back, never mints a stamp below a row already written. Once transport
/// exists, such a stamp would lose last-writer-wins to an older edit.
void main() {
  Future<String?> lastHlc(AppDatabase db) =>
      db.syncDao.getValue(SyncDao.keyLastHlc);

  group('a write stores its stamp', () {
    late AppDatabase db;
    late StatementCounter counter;

    setUp(() async {
      counter = StatementCounter();
      db = await openTestDatabase(interceptor: counter);
    });
    tearDown(() async => db.close());

    test('one write stores the HLC its row carries', () async {
      final folder = await db.folderDao.createFolder(name: 'Gym');

      expect(await lastHlc(db), folder.hlcTimestamp);
    });

    test('two writes in a row leave the second', () async {
      await db.folderDao.createFolder(name: 'First');
      final second = await db.folderDao.createFolder(name: 'Second');

      expect(await lastHlc(db), second.hlcTimestamp);
    });

    test('a cascade under one HLC writes the clock once', () async {
      await db.calendarEventDao.upsert(
        CalendarEventsCompanion.insert(
          id: 'e1',
          title: 'Leg day',
          category: 'gym',
          startDate: DateTime.utc(2026, 1, 1),
          ruleKind: 'daily',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await db.eventSkipDao.markSkipped('e1', DateTime.utc(2026, 2, i + 1));
      }
      counter.reset();

      await db.calendarEventDao.tombstoneEventCascade('e1');

      expect(
        counter.executions('sync_metadata'),
        1,
        reason: counter.statements.join('\n'),
      );
      final event = await (db.select(
        db.calendarEvents,
      )..where((e) => e.id.equals('e1'))).getSingle();
      expect(await lastHlc(db), event.hlcTimestamp);
    });

    test('enqueueMany with fifty keys writes the clock once', () async {
      final stamp = db.newStamp();
      counter.reset();

      await db.transaction(
        () => db.enqueueMany(db.folders, [
          for (var i = 0; i < 50; i++) 'f$i',
        ], stamp.hlc),
      );

      expect(counter.executions('sync_metadata'), 1);
      expect(await lastHlc(db), stamp.hlc);
    });

    test('fifty enqueueIn in one batch write the clock once', () async {
      final stamp = db.newStamp();
      counter.reset();

      await db.batch((b) {
        for (var i = 0; i < 50; i++) {
          db.enqueueIn(b, db.folders, 'f$i', stamp.hlc);
        }
      });

      expect(counter.executions('sync_metadata'), 1);
      expect(await lastHlc(db), stamp.hlc);
    });

    test('an import of forty pre-stamped rows writes the clock once', () async {
      final now = DateTime.now();
      counter.reset();

      await db.calendarEventDao.importAll([
        for (var i = 0; i < 40; i++)
          CalendarEventsCompanion.insert(
            id: 'e$i',
            title: 'Event $i',
            category: 'gym',
            startDate: DateTime.utc(2026, 1, 1),
            ruleKind: 'daily',
            createdAt: now,
            updatedAt: now,
          ),
      ]);

      expect(
        counter.executions('sync_metadata'),
        1,
        reason: counter.statements.join('\n'),
      );
      final highest = await db.syncOutboxDao.maxHlc();
      expect(await lastHlc(db), highest);
    });

    test('a throwing transaction leaves the committed value', () async {
      final committed = await db.folderDao.createFolder(name: 'Kept');

      await expectLater(
        db.transaction(() async {
          final stamp = db.newStamp();
          await db.enqueue(db.folders, 'doomed', stamp.hlc);
          throw StateError('the write fails after queueing');
        }),
        throwsStateError,
      );
      expect(await lastHlc(db), committed.hlcTimestamp);

      // The instance believes the rolled-back stamp was stored; the next
      // stamp is above it and stores itself all the same.
      final next = await db.folderDao.createFolder(name: 'Next');
      expect(await lastHlc(db), next.hlcTimestamp);
    });

    test('persistClock stores the clock a merge advanced', () async {
      await db.folderDao.createFolder(name: 'Local');
      final remote = HlcTimestamp(
        wallTime: DateTime.now()
            .add(const Duration(minutes: 10))
            .millisecondsSinceEpoch,
        logicalCounter: 3,
        nodeId: 'remote-device',
      );
      db.hlc.update(remote);

      await db.persistClock();

      final stored = HlcTimestamp.parse((await lastHlc(db))!);
      expect(stored, db.hlc.last);
      expect(stored.wallTime, remote.wallTime);
      expect(stored.logicalCounter, remote.logicalCounter);
    });

    test('the stored clock never moves backwards', () async {
      const ahead = 'ffffffffffff:0000:elsewhere';
      await db.syncDao.setValue(SyncDao.keyLastHlc, ahead);

      await db.persistClock();
      await db.folderDao.createFolder(name: 'Behind');

      expect(await lastHlc(db), ahead);
    });
  });

  group('seeding from the store', () {
    late Directory tempDir;
    late File file;
    final behind = DateTime.utc(2001, 1, 1);

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('anta_clock_seed');
      file = File('${tempDir.path}/clock.sqlite');
    });
    tearDown(() async => tempDir.delete(recursive: true));

    Future<String> writeOnce() async {
      final first = AppDatabase.forTesting(NativeDatabase(file));
      final folder = await first.folderDao.createFolder(name: 'Before');
      expect(await lastHlc(first), folder.hlcTimestamp);
      await first.close();
      return folder.hlcTimestamp;
    }

    test('a restart with the wall behind stamps above the last row', () async {
      final stored = await writeOnce();

      final reopened = AppDatabase.forTesting(
        NativeDatabase(file),
        wallClock: () => behind,
      );
      addTearDown(reopened.close);
      await reopened.seedClockFromStore();
      final after = await reopened.folderDao.createFolder(name: 'After');

      expect(after.hlcTimestamp.compareTo(stored), greaterThan(0));
      expect(
        HlcTimestamp.parse(after.hlcTimestamp) >= HlcTimestamp.parse(stored),
        isTrue,
      );
      expect(reopened.hlc.seedAhead, greaterThan(Duration.zero));
    });

    test('an upgrade seeds before its first step', () async {
      final stored = await writeOnce();
      final previous = AppDatabase.forTesting(NativeDatabase(file));
      await previous.customStatement(
        'PRAGMA user_version = ${DatabaseSchema.currentVersion - 1}',
      );
      await previous.close();

      final upgraded = AppDatabase.forTesting(
        NativeDatabase(file),
        wallClock: () => behind,
      );
      addTearDown(upgraded.close);
      await upgraded.customSelect('SELECT 1').get();

      expect(upgraded.hlc.last.toString().compareTo(stored), greaterThan(0));
      // Whatever the steps backfilled is covered by the stored clock.
      final highest = (await upgraded.syncOutboxDao.maxHlc())!;
      expect(
        (await lastHlc(upgraded))!.compareTo(highest),
        greaterThanOrEqualTo(0),
      );
    });

    test('an upgrade without a stored clock seeds from the rows', () async {
      final stored = await writeOnce();
      final previous = AppDatabase.forTesting(NativeDatabase(file));
      await previous.syncDao.deleteValue(SyncDao.keyLastHlc);
      await previous.customStatement(
        'PRAGMA user_version = ${DatabaseSchema.currentVersion - 1}',
      );
      await previous.close();

      final upgraded = AppDatabase.forTesting(
        NativeDatabase(file),
        wallClock: () => behind,
      );
      addTearDown(upgraded.close);
      await upgraded.seedClockFromStore();
      final after = await upgraded.folderDao.createFolder(name: 'After');

      expect(after.hlcTimestamp.compareTo(stored), greaterThan(0));
    });

    test('rows stamped before the clock was stored seed it once', () async {
      final stored = await writeOnce();
      final previous = AppDatabase.forTesting(NativeDatabase(file));
      await previous.syncDao.deleteValue(SyncDao.keyLastHlc);
      await previous.close();

      final reopened = AppDatabase.forTesting(
        NativeDatabase(file),
        wallClock: () => behind,
      );
      addTearDown(reopened.close);
      await reopened.seedClockFromStore();

      expect(await lastHlc(reopened), stored);
      final after = await reopened.folderDao.createFolder(name: 'After');
      expect(after.hlcTimestamp.compareTo(stored), greaterThan(0));
    });

    test('without a stored value the clock stays on the wall', () async {
      final db = AppDatabase.forTesting(
        NativeDatabase.memory(),
        wallClock: () => behind,
      );
      addTearDown(db.close);

      await db.seedClockFromStore();

      expect(db.hlc.last.wallTime, behind.millisecondsSinceEpoch);
      expect(db.hlc.seedAhead, Duration.zero);
    });

    test('an unreadable stored value is ignored and replaced', () async {
      final db = AppDatabase.forTesting(
        NativeDatabase.memory(),
        wallClock: () => behind,
      );
      addTearDown(db.close);

      // Both sort above every hex stamp, so the forward-only write could
      // never replace them.
      for (final garbage in ['not a stamp', 'zz:yy:node']) {
        await db.syncDao.setValue(SyncDao.keyLastHlc, garbage);
        await db.seedClockFromStore();
        expect(db.hlc.last.wallTime, behind.millisecondsSinceEpoch);

        final folder = await db.folderDao.createFolder(name: garbage);
        expect(await lastHlc(db), folder.hlcTimestamp);
      }
    });
  });
}
