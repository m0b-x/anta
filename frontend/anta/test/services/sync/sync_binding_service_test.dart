import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/crdt/synced_tables.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/models/sync_binding.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/sync_binding_service.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_status.dart';
import 'package:anta/services/sync/sync_status_service.dart';
import 'package:anta/services/sync/sync_suspension.dart';

import '../../database/support/db_test_support.dart';

class _ScriptedFailure implements Exception {}

/// Fails, once armed, the write of one `sync_metadata` key — or, with no key,
/// the first `owner_id` backfill `UPDATE` — a failure from inside the bind's
/// transaction, with no seam in the service.
class _FailOnKey extends QueryInterceptor {
  final String? key;
  bool armed = false;

  _FailOnKey(this.key);

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (armed && key != null && args.contains(key)) throw _ScriptedFailure();
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (armed && key == null && statement.contains('SET owner_id = ?')) {
      throw _ScriptedFailure();
    }
    return super.runUpdate(executor, statement, args);
  }
}

const _bindingKeys = [
  SettingsKeys.syncSpaceId,
  SettingsKeys.syncSpaceOwnerUid,
  SettingsKeys.syncSpaceAccountUid,
  SettingsKeys.syncSpaceBoundAt,
];

const _runKeys = [
  SyncDao.keyQuotaPausedAt,
  SyncDao.keyLastPullAt,
  SyncDao.keyLastPushAt,
];

void main() {
  late AppDatabase db;
  late SettingsService settings;
  late SyncBindingService service;

  setUp(() async {
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);
    service = SyncBindingService.forTesting(db, settings);
  });

  tearDown(() async {
    SyncBindingService.reset();
    SettingsService.reset();
    await db.close();
  });

  final binding = SyncBinding(
    spaceId: 'space-1',
    ownerUid: 'owner-1',
    accountUid: 'account-1',
    boundAt: DateTime.utc(2026, 10, 23, 9, 30),
  );

  test('a binding round-trips as one value', () async {
    await settings.setSyncBinding(binding);

    expect(await service.read(), binding);
  });

  test('a binding missing its account reads as unbound', () async {
    await settings.setSyncBinding(binding);
    await db.userSettingsDao.deleteValue(SettingsKeys.syncSpaceAccountUid);

    expect(await service.read(), isNull);
  });

  test(
    'unbind clears the binding and the queue and writes the floor',
    () async {
      await settings.setSyncBinding(binding);
      await db.folderDao.createFolder(name: 'First');
      final last = await db.folderDao.createFolder(name: 'Last');
      expect(await db.syncOutboxDao.count(), greaterThan(0));

      await service.unbind();

      for (final key in _bindingKeys) {
        expect(await db.userSettingsDao.getValue(key), isNull, reason: key);
      }
      expect(await service.read(), isNull);
      expect(await db.syncOutboxDao.count(), 0);
      expect(await service.bindFloor(), last.hlcTimestamp);
    },
  );

  test('the floor is the clock, never a held row stamp above it', () async {
    final row = await db.folderDao.createFolder(name: 'Row');
    // A merge stored a far-ahead remote stamp the clock held back.
    const held = 'ffffffffffff:0000:elsewhere';
    await db.customStatement(
      'UPDATE folders SET hlc_timestamp = ? WHERE id = ?',
      [held, row.id],
    );

    await service.writeBindFloor();

    final floor = await service.bindFloor();
    expect(floor, await db.syncDao.getValue(SyncDao.keyLastHlc));
    expect(floor!.compareTo(held), lessThan(0));
    final after = await db.folderDao.createFolder(name: 'After');
    expect(after.hlcTimestamp.compareTo(floor), greaterThan(0));
  });

  test('the floor stores the clock first, so it covers every mint', () async {
    await db.folderDao.createFolder(name: 'Row');
    final minted = db.newStamp().hlc;

    await service.writeBindFloor();

    expect(await service.bindFloor(), minted);
    expect(await db.syncDao.getValue(SyncDao.keyLastHlc), minted);
  });

  test('a later floor overwrites an earlier one', () async {
    await db.syncDao.setValue(SyncDao.keyBindFloor, 'ffffffffffff:0000:old');
    final row = await db.folderDao.createFolder(name: 'Row');

    await service.writeBindFloor();

    expect(await service.bindFloor(), row.hlcTimestamp);
  });

  group('bind', () {
    const space = SyncSpaceRef(ownerUid: 'owner-1', spaceId: 'space-1');

    Future<int> unowned(String table) async {
      final row = await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM $table WHERE owner_id IS NULL',
          )
          .getSingle();
      return row.read<int>('n');
    }

    Future<void> seedPullState() async {
      await db.syncDao.setValue(SyncDao.keyPullCursor('notes'), 'cursor');
      await db.syncDao.setValue(SyncDao.keyPullSeen('notes'), 'seen');
      await db.syncDao.setValue(SyncDao.keyPullCursor('folders'), 'cursor');
    }

    Future<void> expectNoPullState() async {
      expect(await db.syncDao.getValue(SyncDao.keyPullCursor('notes')), isNull);
      expect(await db.syncDao.getValue(SyncDao.keyPullSeen('notes')), isNull);
      expect(
        await db.syncDao.getValue(SyncDao.keyPullCursor('folders')),
        isNull,
      );
    }

    test('stores the binding, owns, re-queues, resets the pull, floors '
        'a never-bound database', () async {
      final folder = await db.folderDao.createFolder(name: 'Training');
      final note = await db.noteDao.createNote(
        folderId: folder.id,
        title: 'Log',
        content: 'body',
      );
      await db.counterDao.insertCounterWithValue(
        CountersCompanion(
          id: const Value('c1'),
          name: const Value('Sets'),
          createdAt: Value(DateTime.utc(2026, 10, 1)),
        ),
        1,
      );
      await db.syncOutboxDao.clear();
      await seedPullState();
      expect(await service.bindFloor(), isNull);

      await service.bind(space: space, accountUid: 'account-1');

      final bound = (await service.read())!;
      expect(
        (bound.spaceId, bound.ownerUid, bound.accountUid),
        ('space-1', 'owner-1', 'account-1'),
      );
      expect(bound.boundAt, isNotNull);
      for (final table in syncedTables) {
        if (table.travelsWithParent) continue;
        expect(await unowned(table.name), 0, reason: table.name);
      }
      expect(
        await unowned('content_chunks'),
        greaterThan(0),
        reason: 'chunks travel inside their note and stay unowned',
      );
      final queued = {
        for (final e in await db.syncOutboxDao.pending())
          '${e.syncedTable}/${e.rowKey}',
      };
      expect(
        queued,
        containsAll([
          'folders/${folder.id}',
          'notes/${note.id}',
          'counters/c1',
          'counter_values/c1|',
        ]),
      );
      expect(queued.where((k) => k.startsWith('content_chunks/')), isEmpty);
      await expectNoPullState();
      expect(await db.syncDao.getValue(SyncDao.keyBindMergePending), '1');
      expect(await service.bindFloor(), isNotNull);
    });

    test('keeps the floor a restore or an unbind wrote', () async {
      await db.syncDao.setValue(SyncDao.keyBindFloor, '000000000005:0000:old');

      await service.bind(space: space, accountUid: 'account-1');

      expect(await service.bindFloor(), '000000000005:0000:old');
    });

    test('never re-owns a row another account owns', () async {
      final folder = await db.folderDao.createFolder(name: 'Shared');
      await db.customStatement('UPDATE folders SET owner_id = ? WHERE id = ?', [
        'partner',
        folder.id,
      ]);

      await service.bind(space: space, accountUid: 'account-1');

      expect((await db.folderDao.getFolderById(folder.id))!.ownerId, 'partner');
    });

    test('over an existing binding is refused, and writes nothing', () async {
      await settings.setSyncBinding(binding);
      await db.folderDao.createFolder(name: 'Training');
      await db.syncOutboxDao.clear();

      await expectLater(
        service.bind(space: space, accountUid: 'account-2'),
        throwsStateError,
      );

      expect(await service.read(), binding);
      expect(await unowned('folders'), 1);
      expect(await db.syncOutboxDao.count(), 0);
      expect(await db.syncDao.getValue(SyncDao.keyBindMergePending), isNull);
    });

    test('clears the quota pause and the last-run times', () async {
      await db.syncDao.setValue(SyncDao.keyQuotaPausedAt, '1');
      await db.syncDao.setValue(SyncDao.keyLastPullAt, '2');
      await db.syncDao.setValue(SyncDao.keyLastPushAt, '3');

      await service.bind(space: space, accountUid: 'account-1');

      for (final key in _runKeys) {
        expect(await db.syncDao.getValue(key), isNull, reason: key);
      }
    });

    test('is refused while sync is suspended, and writes nothing', () async {
      await db.folderDao.createFolder(name: 'Training');

      await SyncSuspension.run(() async {
        await expectLater(
          service.bind(space: space, accountUid: 'account-1'),
          throwsStateError,
        );
      });

      expect(await service.read(), isNull);
      expect(await unowned('folders'), 1);
    });

    // The first backfill UPDATE, the flag's insert and the floor's insert:
    // the start, the middle and the end of the transaction.
    for (final (label, key) in [
      ('the first backfill', null),
      ('the merge flag', SyncDao.keyBindMergePending),
      ('the floor', SyncDao.keyBindFloor),
    ]) {
      test('a failure at $label leaves nothing bound', () async {
        final failing = _FailOnKey(key);
        final other = await openTestDatabase(interceptor: failing);
        addTearDown(other.close);
        SettingsService.reset();
        final otherSettings = SettingsService.forTesting(other);
        final otherService = SyncBindingService.detached(other, otherSettings);
        await other.folderDao.createFolder(name: 'Training');
        await other.syncOutboxDao.clear();
        await other.syncDao.setValue(SyncDao.keyPullCursor('notes'), 'cursor');
        failing.armed = true;

        await expectLater(
          otherService.bind(space: space, accountUid: 'account-1'),
          throwsA(isA<_ScriptedFailure>()),
        );

        expect(await otherService.read(), isNull);
        final unownedRow = await other
            .customSelect(
              'SELECT COUNT(*) AS n FROM folders WHERE owner_id IS NULL',
            )
            .getSingle();
        expect(
          unownedRow.read<int>('n'),
          1,
          reason: 'the backfill rolled back',
        );
        expect(await other.syncOutboxDao.count(), 0, reason: 'nothing queued');
        expect(
          await other.syncDao.getValue(SyncDao.keyPullCursor('notes')),
          'cursor',
        );
        expect(
          await other.syncDao.getValue(SyncDao.keyBindMergePending),
          isNull,
        );
        expect(await otherService.bindFloor(), isNull);
      });
    }

    test('unbind deletes the pull state, the merge switch, the quota pause '
        'and the last-run times', () async {
      await service.bind(space: space, accountUid: 'account-1');
      await seedPullState();
      for (final key in _runKeys) {
        await db.syncDao.setValue(key, '1');
      }

      await service.unbind();

      await expectNoPullState();
      expect(await db.syncDao.getValue(SyncDao.keyBindMergePending), isNull);
      for (final key in _runKeys) {
        expect(await db.syncDao.getValue(key), isNull, reason: key);
      }
      expect(await service.read(), isNull);
    });

    test('two detached services bind two databases apart', () async {
      final other = await openTestDatabase();
      addTearDown(other.close);
      // forTesting hands out the singleton: reset it to get the second
      // database's own settings; the first instance keeps working.
      SettingsService.reset();
      final otherSettings = SettingsService.forTesting(other);
      final first = SyncBindingService.detached(db, settings);
      final second = SyncBindingService.detached(other, otherSettings);

      await first.bind(space: space, accountUid: 'account-1');
      await second.bind(
        space: const SyncSpaceRef(ownerUid: 'owner-2', spaceId: 'space-2'),
        accountUid: 'account-2',
      );

      expect((await first.read())!.spaceId, 'space-1');
      expect((await second.read())!.spaceId, 'space-2');
      final status = await SyncStatusService.detached(
        other,
        second,
      ).read(user: const AppUser(uid: 'account-1'));
      expect(status.binding!.spaceId, 'space-2');
      expect(status.pause, SyncPause.accountMismatch);
    });
  });

  test('an opened database with no rows writes its clock', () async {
    await db.seedClockFromStore();
    final clock = await db.syncDao.getValue(SyncDao.keyLastHlc);
    expect(clock, isNotNull);

    await service.writeBindFloor();

    expect(await service.bindFloor(), clock);
  });
}
