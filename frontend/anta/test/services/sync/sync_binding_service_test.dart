import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import 'package:anta/services/sync/sync_space_registry.dart';
import 'package:anta/services/sync/sync_status.dart';
import 'package:anta/services/sync/sync_status_service.dart';
import 'package:anta/services/sync/sync_suspension.dart';

import '../../database/support/db_test_support.dart';

class _ScriptedFailure implements Exception {}

/// A registry whose every write fails, as a full preferences store would.
class _ThrowingRegistry extends SyncSpaceRegistry {
  _ThrowingRegistry(super.prefs) : super(databaseExists: (_) async => true);

  @override
  Future<void> claim(SyncSpaceRef space, String databaseName) =>
      Future.error(_ScriptedFailure());

  @override
  Future<void> release(String databaseName) => Future.error(_ScriptedFailure());
}

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

/// The typed refusal the Sharing page words (review R39), its debug text
/// kept.
Matcher _refusal(SyncBindRefusalReason reason) => isA<SyncBindRefusal>()
    .having((e) => e.reason, 'reason', reason)
    .having((e) => e.message, 'message', startsWith('Cannot bind while'));

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

  group('an unbind releases the account\'s rows '
      '(cloud-multi-user-roadmap §6.1 f)', () {
    const space = SyncSpaceRef(ownerUid: 'account-1', spaceId: 'space-1');

    Future<String?> ownerOf(String id) async {
      final row = await db
          .customSelect(
            'SELECT owner_id FROM folders WHERE id = ?',
            variables: [Variable<String>(id)],
          )
          .getSingle();
      return row.read<String?>('owner_id');
    }

    Future<void> ownedBy(String id, String uid) => db.customStatement(
      'UPDATE folders SET owner_id = ? WHERE id = ?',
      [uid, id],
    );

    /// How many rows across every synced table [uid] owns.
    Future<int> rowsOwnedBy(String uid) async {
      var rows = 0;
      for (final synced in syncedTables) {
        final row = await db
            .customSelect(
              'SELECT COUNT(*) AS n FROM ${synced.name} WHERE owner_id = ?',
              variables: [Variable<String>(uid)],
            )
            .getSingle();
        rows += row.read<int>('n');
      }
      return rows;
    }

    test('every row the bound account owns is unowned again, on every '
        'table; a partner\'s row keeps its owner', () async {
      final mine = await db.folderDao.createFolder(name: 'Mine');
      final shared = await db.folderDao.createFolder(name: 'Shared');
      await db.noteDao.createNote(folderId: mine.id, title: 'Squats');
      await service.bind(space: space, accountUid: 'account-1');
      await ownedBy(shared.id, 'partner');
      // The folder and the note: two tables.
      expect(await rowsOwnedBy('account-1'), 2);

      await service.unbind();

      expect(await rowsOwnedBy('account-1'), 0);
      expect(await ownerOf(mine.id), isNull);
      expect(await ownerOf(shared.id), 'partner');
    });

    test('so the next bind takes every row up, whichever account binds — '
        'the same person back under a new uid uploads everything', () async {
      final folder = await db.folderDao.createFolder(name: 'Training');
      await service.bind(space: space, accountUid: 'account-1');
      await service.unbind();
      expect(await db.syncOutboxDao.count(), 0);

      await service.bind(
        space: const SyncSpaceRef(ownerUid: 'account-2', spaceId: 'space-2'),
        accountUid: 'account-2',
      );

      expect(await ownerOf(folder.id), 'account-2');
      expect(await rowsOwnedBy('account-1'), 0);
      final queued = await db.syncOutboxDao.pending(limit: 1000);
      expect(
        queued.where((entry) => entry.rowKey == folder.id),
        hasLength(1),
        reason: 'a row left to the first account would never be uploaded',
      );
    });

    test('only the account that bound is released: a space owner\'s row, '
        'where the two differ, is somebody else\'s and keeps its '
        'owner', () async {
      final a = await db.folderDao.createFolder(name: 'A');
      final b = await db.folderDao.createFolder(name: 'B');
      expect(binding.ownerUid, isNot(binding.accountUid));
      await settings.setSyncBinding(binding);
      await ownedBy(a.id, binding.accountUid);
      await ownedBy(b.id, binding.ownerUid);

      await service.unbind();

      expect(await ownerOf(a.id), isNull);
      expect(await ownerOf(b.id), binding.ownerUid);
    });

    test('the heal\'s unbind releases them as Stop syncing does', () async {
      final folder = await db.folderDao.createFolder(name: 'Copy');
      await service.bind(space: space, accountUid: 'account-1');

      await service.unbind(raiseFloor: false);

      expect(await ownerOf(folder.id), isNull);
    });

    test('Stop syncing tells the push registry which account left, once '
        'committed, and drops every poke owed with the outbox', () async {
      final left = <String>[];
      SyncBindingService.onUnbound = left.add;
      addTearDown(() => SyncBindingService.onUnbound = null);
      await service.bind(space: space, accountUid: 'account-1');
      await db.syncDao.oweSharePoke(pairId: 'pair-1', urgent: true);

      await service.unbind();

      expect(left, ['account-1']);
      expect(
        await db.syncDao.valuesByPrefix(SyncDao.sharePokeOwedPrefix),
        isEmpty,
      );
      await service.unbind();
      expect(left, ['account-1'], reason: 'nothing was bound the second time');
    });

    test('unbound already, nothing is released: a partner\'s rows and an '
        'earlier account\'s alike stay as they are', () async {
      final folder = await db.folderDao.createFolder(name: 'Old');
      await ownedBy(folder.id, 'someone');

      await service.unbind();

      expect(await ownerOf(folder.id), 'someone');
    });
  });

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
        if (table.contentAddressed) continue;
        expect(await unowned(table.name), 0, reason: table.name);
      }
      expect(
        await unowned('content_chunks'),
        greaterThan(0),
        reason: 'a chunk is pushed under the bound account, its row unowned',
      );
      final queued = {
        for (final e in await db.syncOutboxDao.pending())
          '${e.syncedTable}/${e.rowKey}',
      };
      final hash = (await db.contentChunkDao.hashesOf(note.id)).single;
      expect(
        queued,
        containsAll([
          'folders/${folder.id}',
          'notes/${note.id}',
          'content_chunks/$hash',
          'counters/c1',
          'counter_values/c1|',
        ]),
      );
      await expectNoPullState();
      expect(await db.syncDao.getValue(SyncDao.keyBindMergePending), '1');
      expect(await service.bindFloor(), isNotNull);
    });

    test('keeps the floor a restore or an unbind wrote', () async {
      await db.syncDao.setValue(SyncDao.keyBindFloor, '000000000005:0000:old');

      await service.bind(space: space, accountUid: 'account-1');

      expect(await service.bindFloor(), '000000000005:0000:old');
    });

    test('Stop syncing raises the floor to the clock; the heal\'s unbind '
        'leaves it where it stood (review X-1)', () async {
      await service.bind(space: space, accountUid: 'account-1');
      final atBind = await service.bindFloor();
      await db.folderDao.createFolder(name: 'After the bind');

      await service.unbind(raiseFloor: false);

      expect(await service.read(), isNull);
      expect(await db.syncOutboxDao.count(), 0);
      expect(await service.bindFloor(), atBind);

      await service.bind(space: space, accountUid: 'account-1');
      await db.folderDao.createFolder(name: 'Before the stop');
      await service.unbind();

      expect(await service.bindFloor(), isNot(atBind));
      expect(await service.bindFloor(), db.hlc.last.toString());
    });

    test('mints a fresh replica id at every bind and unbind, never the '
        'device id (S20)', () async {
      final unbound = await db.syncDao.replicaId();

      await service.bind(space: space, accountUid: 'account-1');
      final bound = await db.syncDao.getValue(SyncDao.keyReplicaId);
      await service.unbind();
      final released = await db.syncDao.getValue(SyncDao.keyReplicaId);
      await service.bind(space: space, accountUid: 'account-1');
      final rebound = await db.syncDao.getValue(SyncDao.keyReplicaId);

      expect({unbound, bound, released, rebound}, hasLength(4));
      expect([bound, released, rebound], isNot(contains(db.deviceId)));
    });

    test('a database with no replica id mints one at its first tap and '
        'keeps it (S20)', () async {
      expect(await db.syncDao.getValue(SyncDao.keyReplicaId), isNull);

      await db.counterDao.applyCount('c1', '', delta: 1, startValue: 0);
      final minted = await db.syncDao.getValue(SyncDao.keyReplicaId);
      await db.counterDao.applyCount('c1', '', delta: 1, startValue: 0);

      expect(minted, isNotNull);
      expect(await db.syncDao.getValue(SyncDao.keyReplicaId), minted);
      final row = await db.select(db.counterValues).getSingle();
      expect(row.shards, '{"$minted":[2,0]}');
      expect(row.value, 2);
    });

    test(
      'a replica id minted under another install\'s device id is replaced '
      'at the first read, the old shard kept in the count (re-review N1)',
      () async {
        await db.syncDao.setValue(SyncDao.keyReplicaId, 'old-phone-replica');
        await db.syncDao.setValue(SyncDao.keyReplicaIdDevice, db.deviceId);
        await db.counterDao.applyCount('c1', '', delta: 3, startValue: 0);
        // The file as Android backup lands it on a new phone: its sync_metadata
        // whole, the install's device id not.
        await db.syncDao.setValue(SyncDao.keyReplicaIdDevice, 'old-phone');

        final fresh = await db.syncDao.replicaId();
        await db.counterDao.applyCount('c1', '', delta: 2, startValue: 0);

        expect(fresh, isNot('old-phone-replica'));
        expect(await db.syncDao.replicaId(), fresh);
        expect(
          await db.syncDao.getValue(SyncDao.keyReplicaIdDevice),
          db.deviceId,
        );
        final row = await db.select(db.counterValues).getSingle();
        expect(row.value, 5);
        expect(row.shards, contains('"old-phone-replica":[3,0]'));
        expect(row.shards, contains('"$fresh":[2,0]'));
      },
    );

    test('clears the note of a heal that unbound this database as a copy '
        '(review X-2)', () async {
      await db.syncDao.setValue(SyncDao.keyHealUnboundFrom, 'phone');

      await service.bind(space: space, accountUid: 'account-1');

      expect(await db.syncDao.getValue(SyncDao.keyHealUnboundFrom), isNull);
    });

    test('takes up a row still naming an account that no longer binds this '
        'database, and queues it: an unbound database holds only this '
        'device\'s own rows (cloud-multi-user-roadmap §6.1 f)', () async {
      // As a build from before an unbind released its rows left it, or an
      // imported backup of a synced database did.
      final folder = await db.folderDao.createFolder(name: 'Left behind');
      await db.customStatement('UPDATE folders SET owner_id = ? WHERE id = ?', [
        'an-earlier-account',
        folder.id,
      ]);
      await db.syncOutboxDao.clear();

      await service.bind(space: space, accountUid: 'account-1');

      expect(
        (await db.folderDao.getFolderById(folder.id))!.ownerId,
        'account-1',
      );
      final queued = await db.syncOutboxDao.pending(limit: 1000);
      expect(queued.where((entry) => entry.rowKey == folder.id), hasLength(1));
    });

    test('over an existing binding is refused, and writes nothing', () async {
      await settings.setSyncBinding(binding);
      await db.folderDao.createFolder(name: 'Training');
      await db.syncOutboxDao.clear();

      await expectLater(
        service.bind(space: space, accountUid: 'account-2'),
        throwsA(_refusal(SyncBindRefusalReason.alreadyBound)),
      );

      expect(await service.read(), binding);
      expect(await unowned('folders'), 1);
      expect(await db.syncOutboxDao.count(), 0);
      expect(await db.syncDao.getValue(SyncDao.keyBindMergePending), isNull);
    });

    test('two binds started together: the second is refused, not applied over '
        'the first', () async {
      final folder = await db.folderDao.createFolder(name: 'Training');

      final outcomes = await Future.wait([
        for (final uid in ['account-1', 'account-2'])
          service
              .bind(space: space, accountUid: uid)
              .then<Object?>((_) => null, onError: (Object error) => error),
      ]);

      expect(outcomes.whereType<SyncBindRefusal>(), [
        _refusal(SyncBindRefusalReason.alreadyBound),
      ]);
      expect((await service.read())!.accountUid, 'account-1');
      expect(
        (await db.folderDao.getFolderById(folder.id))!.ownerId,
        'account-1',
      );
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
          throwsA(_refusal(SyncBindRefusalReason.suspended)),
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

    group('the install registry', () {
      late SharedPreferences prefs;
      late SyncSpaceRegistry registry;
      late SyncBindingService registered;

      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        prefs = await SharedPreferences.getInstance();
        registry = SyncSpaceRegistry(prefs, databaseExists: (_) async => true);
        registered = SyncBindingService.detached(
          db,
          settings,
          registry: registry,
          databaseName: 'training',
        );
      });

      test('a bind claims the space for this database', () async {
        await registered.bind(space: space, accountUid: 'account-1');

        expect(await registry.holderOf(space), 'training');
      });

      test('a refused bind claims nothing', () async {
        await settings.setSyncBinding(binding);

        await expectLater(
          registered.bind(space: space, accountUid: 'account-1'),
          throwsA(isA<SyncBindRefusal>()),
        );

        expect(registry.claims(), isEmpty);
      });

      test('an unbind releases the claim', () async {
        await registered.bind(space: space, accountUid: 'account-1');

        await registered.unbind();

        expect(registry.claims(), isEmpty);
      });

      test('a space another database holds is refused, naming it, and '
          'nothing is written (review BA-L4)', () async {
        await registry.claim(space, 'errands');

        await expectLater(
          registered.bind(space: space, accountUid: 'account-1'),
          throwsA(
            allOf(
              _refusal(SyncBindRefusalReason.spaceHeldByAnotherDatabase),
              isA<SyncBindRefusal>().having(
                (e) => e.holderDatabase,
                'holderDatabase',
                'errands',
              ),
            ),
          ),
        );

        expect(await registered.read(), isNull);
        expect(await db.syncDao.getValue(SyncDao.keyBindMergePending), isNull);
        expect(registry.claims(), [
          const SyncSpaceClaim(space: space, databaseName: 'errands'),
        ]);
      });

      test('this database\'s own claim is not in its way', () async {
        await registry.claim(space, 'training');

        await registered.bind(space: space, accountUid: 'account-1');

        expect(await registered.read(), isNotNull);
      });

      test('the earlier refusals keep their order: a bound database is '
          'refused as bound, a held space notwithstanding', () async {
        await settings.setSyncBinding(binding);
        await registry.claim(space, 'errands');

        await expectLater(
          registered.bind(space: space, accountUid: 'account-1'),
          throwsA(_refusal(SyncBindRefusalReason.alreadyBound)),
        );
        await SyncSuspension.run(() async {
          await expectLater(
            registered.bind(space: space, accountUid: 'account-1'),
            throwsA(_refusal(SyncBindRefusalReason.suspended)),
          );
        });
      });

      test('a registry that cannot be written fails neither the bind nor '
          'the unbind', () async {
        final failing = SyncBindingService.detached(
          db,
          settings,
          registry: _ThrowingRegistry(prefs),
          databaseName: 'training',
        );

        await failing.bind(space: space, accountUid: 'account-1');
        expect(await failing.read(), isNotNull);
        await failing.unbind();
        expect(await failing.read(), isNull);
      });
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
