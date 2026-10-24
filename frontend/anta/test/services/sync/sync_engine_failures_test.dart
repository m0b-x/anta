import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/json_keys.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_status.dart';
import 'package:anta/services/sync/sync_table_binding.dart';
import 'package:anta/services/sync/sync_tables.dart';

import 'support/sync_pair.dart';

/// A table binding that merges like [_inner], except that the row keys in
/// [_faults] throw what their factory makes — a binding bug or a database
/// fault the engine must survive.
class _FaultyMerge extends SyncTableBinding<Object> {
  final SyncTableBinding<Object> _inner;
  final Map<String, Object Function()> _faults;

  const _FaultyMerge(this._inner, this._faults);

  @override
  String get table => _inner.table;

  @override
  SyncInvalidation get invalidation => _inner.invalidation;

  @override
  Future<List<Object>> loadByKeys(AppDatabase db, Iterable<String> rowKeys) =>
      _inner.loadByKeys(db, rowKeys);

  @override
  String rowKeyOf(Object row) => _inner.rowKeyOf(row);

  @override
  Future<SyncEnvelope> encode(
    AppDatabase db,
    Object row, {
    required String boundUid,
  }) => _inner.encode(db, row, boundUid: boundUid);

  @override
  Object decode(SyncEnvelope envelope) => _inner.decode(envelope);

  @override
  Future<MergeOutcome> mergeRemote(
    AppDatabase db,
    SyncEnvelope envelope, {
    String? floor,
  }) async {
    final fault = _faults[envelope.rowKey];
    if (fault != null) throw fault();
    return _inner.mergeRemote(db, envelope, floor: floor);
  }
}

/// Every synced table, the folders' merge throwing for [faults].
List<SyncTableBinding<Object>> _foldersFaulting(
  Map<String, Object Function()> faults,
) => [
  for (final binding in syncTableBindings)
    binding.table == 'folders' ? _FaultyMerge(binding, faults) : binding,
];

/// How the engine survives a space that refuses, a network that is gone, a
/// quota that ran out and rows that cannot cross — always against A alone,
/// "Sync now" driving it and the scheduler holding its retries.
void main() {
  late SyncPair pair;
  SyncDevice a() => pair.a;

  setUp(() async => pair = await SyncPair.open());
  tearDown(() async => pair.close());

  Map<String, SyncEnvelope> spaceFolders() =>
      pair.gateway.rowsOf(pair.space, 'folders');

  group('back-off', () {
    test('offline is reported, held 30 s, and the retry drains', () async {
      final folder = await a().db.folderDao.createFolder(name: 'Training');
      pair.gateway.failNextWith(SyncGatewayFailure.offline);

      final report = await a().sync();

      expect(report.failure, SyncGatewayFailure.offline);
      expect(a().engine.current.lastFailure?.failure, SyncGatewayFailure.offline);
      expect(a().scheduler.pending, [const Duration(seconds: 30)]);
      expect(spaceFolders(), isEmpty);

      a().scheduler.fire();
      await a().settle();

      expect(spaceFolders().keys, [folder.id]);
      expect(a().engine.current.lastFailure, isNull);
      expect(a().scheduler.pending, isEmpty);
    });

    test('the waits grow 30 s, 1 min, 2 min and reset on a success', () async {
      await a().db.folderDao.createFolder(name: 'Training');
      pair.gateway.failNextWith(SyncGatewayFailure.offline);
      await a().sync();
      final waits = [...a().scheduler.pending];
      for (var i = 0; i < 2; i++) {
        pair.gateway.failNextWith(SyncGatewayFailure.unknown);
        a().scheduler.fire();
        await a().settle();
        waits.addAll(a().scheduler.pending);
      }
      expect(waits, const [
        Duration(seconds: 30),
        Duration(minutes: 1),
        Duration(minutes: 2),
      ]);

      a().scheduler.fire();
      await a().settle();
      expect(spaceFolders(), hasLength(1));

      pair.gateway.failNextWith(SyncGatewayFailure.offline);
      await a().sync();
      expect(a().scheduler.pending, [const Duration(seconds: 30)]);
    });
  });

  test('quota pauses, is stored, retries in an hour and clears on the next '
      'success', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Training');
    pair.gateway.failNextWith(SyncGatewayFailure.quotaExhausted);

    final report = await a().sync();

    expect(report.failure, SyncGatewayFailure.quotaExhausted);
    expect(a().engine.current.pause, SyncPause.quotaExhausted);
    expect(await a().db.syncDao.getValue(SyncDao.keyQuotaPausedAt), isNotNull);
    expect(a().scheduler.pending, [const Duration(hours: 1)]);

    a().scheduler.fire();
    await a().settle();

    expect(spaceFolders().keys, [folder.id]);
    expect(a().engine.current.pause, SyncPause.none);
    expect(await a().db.syncDao.getValue(SyncDao.keyQuotaPausedAt), isNull);
  });

  test('a stored quota mark is deleted by any call that reaches the space, '
      'even in a run that fails later', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Training');
    pair.gateway.refuse('folders', folder.id, SyncGatewayFailure.unknown);
    await a().db.syncDao.setValue(SyncDao.keyQuotaPausedAt, '1');

    final report = await a().sync();

    expect(report.failure, SyncGatewayFailure.unknown);
    expect(await a().db.syncDao.getValue(SyncDao.keyQuotaPausedAt), isNull);
  });

  test('a closed database completes "Sync now" with an unknown failure '
      'instead of hanging', () async {
    await a().db.close();

    final report = await a().engine.syncNow().timeout(
      const Duration(seconds: 5),
    );

    expect(report.failure, SyncGatewayFailure.unknown);
    expect(report.skipped, isNull);
  });

  group('refused rows', () {
    test('an oversized row refused as invalidData is parked, the rest '
        'pushed', () async {
      final folders = [
        for (final name in ['One', 'Two', 'Three'])
          await a().db.folderDao.createFolder(name: name),
      ];
      pair.gateway.refuse(
        'folders',
        folders[1].id,
        SyncGatewayFailure.invalidData,
      );

      final report = await a().sync();

      expect(report.failure, isNull);
      expect(report.parked, 1);
      expect(spaceFolders().keys.toSet(), {folders[0].id, folders[2].id});
      expect(a().engine.current.parkedCount, 1);
      expect(await a().db.syncOutboxDao.count(), 1, reason: 'retried next launch');

      expect((await a().sync()).pushedRows, 0, reason: 'parked for the session');
    });

    test('a row the rules refuse, with the space readable at this schema, '
        'is parked the same way', () async {
      final folders = [
        for (final name in ['One', 'Two'])
          await a().db.folderDao.createFolder(name: name),
      ];
      pair.gateway.refuse(
        'folders',
        folders[0].id,
        SyncGatewayFailure.permissionDenied,
      );

      final report = await a().sync();

      expect(report.failure, isNull);
      expect(spaceFolders().keys, [folders[1].id]);
      expect(a().engine.current.parkedCount, 1);
      expect(a().engine.current.pause, SyncPause.none);
    });

    test('one row refused as invalidData and one as a rule refusal in one '
        'batch are both parked, the rest pushed, access kept', () async {
      final folders = [
        for (final name in ['One', 'Two', 'Three', 'Four'])
          await a().db.folderDao.createFolder(name: name),
      ];
      pair.gateway
        ..refuse('folders', folders[0].id, SyncGatewayFailure.invalidData)
        ..refuse('folders', folders[3].id, SyncGatewayFailure.permissionDenied);

      final report = await a().sync();

      expect(report.failure, isNull);
      expect(report.parked, 2);
      expect(spaceFolders().keys.toSet(), {folders[1].id, folders[2].id});
      expect(a().engine.current.pause, SyncPause.none);
      expect((await a().sync()).skipped, isNull);
    });

    test('a parked note shortened since is pushed at once', () async {
      final folder = await a().db.folderDao.createFolder(name: 'Big');
      final note = await writeNote(
        a(),
        folderId: folder.id,
        title: 'Huge',
        body: 'x' * 950000,
      );
      expect((await a().sync()).parked, 1);

      await editNote(a(), note.id, 'short now');
      final report = await a().sync();

      expect(report.pushedRows, 1);
      expect(pair.gateway.rowsOf(pair.space, 'notes').keys, [note.id]);
      expect(a().engine.current.parkedCount, 0);
      expect(await a().db.syncOutboxDao.count(), 0);
    });

    test('more than twenty refused rows in one drain means no access', () async {
      for (var i = 0; i < 25; i++) {
        final folder = await a().db.folderDao.createFolder(name: 'F$i');
        pair.gateway.refuse(
          'folders',
          folder.id,
          SyncGatewayFailure.permissionDenied,
        );
      }

      final report = await a().sync();

      expect(report.failure, SyncGatewayFailure.permissionDenied);
      expect(a().engine.current.pause, SyncPause.noAccess);
      expect(a().engine.current.parkedCount, 21);
      expect((await a().sync()).skipped, SyncRunSkip.noAccess);
    });
  });

  group('a denied push is diagnosed', () {
    test('a deleted space means no access', () async {
      await a().db.folderDao.createFolder(name: 'Training');
      pair.gateway.deleteSpace(pair.space);

      final report = await a().sync();

      expect(report.failure, SyncGatewayFailure.permissionDenied);
      expect(a().engine.current.pause, SyncPause.noAccess);
      expect(a().scheduler.pending, isEmpty, reason: 'no retry on no access');
      expect((await a().sync()).skipped, SyncRunSkip.noAccess);
    });

    test('a space at a newer schema means the app is outdated', () async {
      await a().db.folderDao.createFolder(name: 'Training');
      await pair.gateway.pushBatch(
        pair.space,
        const [],
        pushedBy: 'C',
        schema: syncSchema + 1,
      );

      final report = await a().sync();

      expect(report.failure, SyncGatewayFailure.permissionDenied);
      expect(a().engine.current.pause, SyncPause.appOutdated);
      expect((await a().sync()).skipped, SyncRunSkip.appOutdated);
    });
  });

  group('per-envelope faults', () {
    test('malformed documents are parked, the page\'s other rows apply and '
        'the cursor moves past them', () async {
      final good = folderEnvelope('good', '000000000001:0000:C');
      final missing = folderEnvelope(
        'missing',
        '000000000002:0000:C',
        data: {JsonKeys.id: 'missing'},
      );
      final empty = folderEnvelope('empty', '000000000003:0000:C', name: '');
      final last = folderEnvelope('last', '000000000004:0000:C');
      for (final envelope in [good, missing, empty, last]) {
        pair.gateway.plant(pair.space, envelope);
      }

      final report = await a().sync();

      expect(report.failure, isNull);
      expect(report.parked, 2);
      expect(a().engine.current.parkedCount, 2);
      expect(await a().db.folderDao.getFolderById('good'), isNotNull);
      expect(await a().db.folderDao.getFolderById('last'), isNotNull);
      expect(await a().db.folderDao.getFolderById('missing'), isNull);
      expect(await a().db.folderDao.getFolderById('empty'), isNull);
      expect(
        await a().db.syncDao.getValue(SyncDao.keyPullCursor('folders')),
        '4',
      );
      final rows = [for (final page in a().hooks.pages) ...page.$2];
      expect(rows.map((r) => r.rowKey), ['good', 'last']);
    });

    test('a merge that throws a StateError or an ArgumentError parks its row '
        'with a warning, the others apply, the cursor moves and the drain '
        'goes on', () async {
      await pair.close();
      pair = await SyncPair.open(
        tables: _foldersFaulting({
          'state': () => StateError('a binding bug'),
          'argument': () => ArgumentError('a bad key'),
        }),
      );
      final logs = <String>[];
      final print = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
      addTearDown(() => debugPrint = print);
      for (final (i, id) in ['good', 'state', 'argument', 'last'].indexed) {
        pair.gateway.plant(
          pair.space,
          folderEnvelope(id, '00000000000${i + 1}:0000:C'),
        );
      }
      final mine = await a().db.folderDao.createFolder(name: 'Mine');

      final report = await a().sync();

      expect(report.failure, isNull);
      expect(report.parked, 2);
      expect(await a().db.folderDao.getFolderById('good'), isNotNull);
      expect(await a().db.folderDao.getFolderById('last'), isNotNull);
      expect(await a().db.folderDao.getFolderById('state'), isNull);
      expect(
        await a().db.syncDao.getValue(SyncDao.keyPullCursor('folders')),
        '4',
      );
      expect(spaceFolders(), contains(mine.id));
      expect(
        logs,
        contains(
          allOf(contains('warning'), contains('StateError'), contains('state')),
        ),
      );
      expect(
        logs,
        contains(allOf(contains('warning'), contains('probably a bug'))),
      );

      final later = await a().db.folderDao.createFolder(name: 'Later');
      final next = await a().sync();
      // Only the echo of its own push comes back; the parked rows lie behind
      // the cursor.
      expect((next.pulledRows, next.pushedRows, next.parked), (1, 1, 0));
      expect(spaceFolders(), contains(later.id));
    });

    test('a merge that throws a gateway failure rolls its page back: no row '
        'of it applied, the cursor unchanged', () async {
      await pair.close();
      pair = await SyncPair.open(
        tables: _foldersFaulting({
          'bad': () => const SyncGatewayException(
            SyncGatewayFailure.unknown,
            'mid-page',
          ),
        }),
      );
      for (final (i, id) in ['first', 'bad', 'last'].indexed) {
        pair.gateway.plant(
          pair.space,
          folderEnvelope(id, '00000000000${i + 1}:0000:C'),
        );
      }

      final report = await a().sync();

      expect(report.failure, SyncGatewayFailure.unknown);
      expect(await a().db.select(a().db.folders).get(), isEmpty);
      expect(
        await a().db.syncDao.getValue(SyncDao.keyPullCursor('folders')),
        isNull,
      );
    });

    test('an entry whose row was hard-deleted is retired, nothing pushed', () async {
      final folder = await a().db.folderDao.createFolder(name: 'Wiped');
      await a().db.customStatement('DELETE FROM folders WHERE id = ?', [
        folder.id,
      ]);

      final report = await a().sync();

      expect(report.pushedRows, 0);
      expect(pair.gateway.pushes, isEmpty);
      expect(await a().db.syncOutboxDao.count(), 0);
    });

    test('a note over 900 KB is parked before the push', () async {
      final folder = await a().db.folderDao.createFolder(name: 'Big');
      final note = await writeNote(
        a(),
        folderId: folder.id,
        title: 'Huge',
        body: 'x' * 950000,
      );

      final report = await a().sync();

      expect(report.parked, 1);
      expect(spaceFolders().keys, [folder.id]);
      expect(pair.gateway.rowsOf(pair.space, 'notes'), isEmpty);
      expect(pair.gateway.calls.where((c) => c.startsWith('push')), hasLength(1));
      expect(a().engine.current.parkedCount, 1);
      expect(
        (await a().db.syncOutboxDao.pending()).single.rowKey,
        note.id,
      );
    });
  });
}
