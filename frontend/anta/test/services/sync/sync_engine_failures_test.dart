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
/// fault the engine must survive. A key also in [_partWay] merges first and
/// throws after, so its writes are there when the throw comes.
class _FaultyMerge extends SyncTableBinding<Object> {
  final SyncTableBinding<Object> _inner;
  final Map<String, Object Function()> _faults;
  final Set<String> _partWay;

  const _FaultyMerge(this._inner, this._faults, [this._partWay = const {}]);

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
    if (fault == null) return _inner.mergeRemote(db, envelope, floor: floor);
    if (_partWay.contains(envelope.rowKey)) {
      await _inner.mergeRemote(db, envelope, floor: floor);
    }
    throw fault();
  }
}

/// Every synced table, the folders' merge throwing for [faults] — after
/// merging for the keys in [partWay].
List<SyncTableBinding<Object>> _foldersFaulting(
  Map<String, Object Function()> faults, {
  Set<String> partWay = const {},
}) => [
  for (final binding in syncTableBindings)
    binding.table == 'folders'
        ? _FaultyMerge(binding, faults, partWay)
        : binding,
];

/// [length] characters of a note body that fills many database pages.
String _noise(int length) => String.fromCharCodes([
  for (var i = 0; i < length; i++) 33 + (i * 7919 + i ~/ 13 * 104729) % 90,
]);

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

  test('a drain with two rows the rules refuse reads the space once', () async {
    final folders = [
      for (final name in ['One', 'Two', 'Three'])
        await a().db.folderDao.createFolder(name: name),
    ];
    for (final folder in [folders[0], folders[2]]) {
      pair.gateway.refuse(
        'folders',
        folder.id,
        SyncGatewayFailure.permissionDenied,
      );
    }

    final report = await a().sync();

    expect(report.parked, 2);
    expect(spaceFolders().keys, [folders[1].id]);
    expect(pair.gateway.readSpaceCalls, 1);
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

    test('a merge that writes and then throws leaves none of its writes: '
        'its row parks, the others apply, the cursor moves', () async {
      await pair.close();
      pair = await SyncPair.open(
        tables: _foldersFaulting({
          'partway': () => StateError('after its write'),
        }, partWay: {'partway'}),
      );
      for (final (i, id) in ['first', 'partway', 'last'].indexed) {
        pair.gateway.plant(
          pair.space,
          folderEnvelope(id, '00000000000${i + 1}:0000:C'),
        );
      }

      final report = await a().sync();

      expect(report.failure, isNull);
      expect(report.parked, 1);
      expect(await a().db.folderDao.getFolderById('partway'), isNull);
      expect(await a().db.folderDao.getFolderById('first'), isNotNull);
      expect(await a().db.folderDao.getFolderById('last'), isNotNull);
      expect(
        await a().db.syncDao.getValue(SyncDao.keyPullCursor('folders')),
        '3',
      );
    });

    test('a parked key that merges later is no longer counted parked', () async {
      pair.gateway.plant(
        pair.space,
        folderEnvelope(
          'late',
          '000000000001:0000:C',
          data: {JsonKeys.id: 'late'},
        ),
      );
      expect((await a().sync()).parked, 1);
      expect(a().engine.current.parkedCount, 1);

      pair.gateway.plant(
        pair.space,
        folderEnvelope('late', '000000000002:0000:C'),
      );
      final report = await a().sync();

      expect(report.parked, 0);
      expect(await a().db.folderDao.getFolderById('late'), isNotNull);
      expect(a().engine.current.parkedCount, 0);
    });

    test('a merge that fills the disk fails its page whole: the run reports '
        'it, the cursor stays, and the next run applies the page once there '
        'is room', () async {
      final b = pair.b;
      final folder = await b.db.folderDao.createFolder(name: 'Big');
      await b.sync();
      await a().sync();
      final note = await writeNote(
        b,
        folderId: folder.id,
        title: 'Big',
        body: _noise(400000),
      );
      await b.sync();
      final cursor = await a().db.syncDao.getValue(
        SyncDao.keyPullCursor('notes'),
      );
      final pages =
          (await a().db.customSelect('PRAGMA page_count').getSingle())
                  .data
                  .values
                  .first
              as int;
      await a().db.customStatement('PRAGMA max_page_count = ${pages + 3}');

      final full = await a().sync();

      expect(full.failure, SyncGatewayFailure.unknown);
      expect(full.parked, 0);
      expect(
        await a().db.syncDao.getValue(SyncDao.keyPullCursor('notes')),
        cursor,
      );
      expect(await a().db.noteDao.getNoteById(note.id), isNull);

      await a().db.customSelect('PRAGMA max_page_count = 1073741823').get();
      final next = await a().sync();

      expect(next.failure, isNull);
      expect(await a().db.noteDao.getNoteById(note.id), isNotNull);
      expect(a().engine.current.parkedCount, 0);
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

  group('faults under the floor', () {
    SyncDevice b() => pair.b;

    test('an envelope that parks retires the local row it would have beaten: '
        'the newer text stays in the space and on A, the stale one is pushed '
        'nowhere', () async {
      final faults = <String, Object Function()>{};
      await pair.close();
      pair = await SyncPair.open(bind: false, tables: _foldersFaulting(faults));
      await pair.bind(a());
      await pair.bind(b());
      final folder = await a().db.folderDao.createFolder(name: 'Y');
      await a().sync();
      await b().sync();
      await a().db.folderDao.updateFolder(id: folder.id, name: 'Y from A');
      await a().sync();
      // Newer than A's edit but made before the unbind: at or below the floor
      // the rebind writes, so the space's version wins it.
      await b().db.folderDao.updateFolder(id: folder.id, name: 'Y from B');
      await b().binding.unbind();
      await pair.bind(b());
      faults[folder.id] = () => StateError('a local fault on B');

      final report = await b().sync();
      faults.clear();
      await a().sync();

      expect(report.parked, 1);
      String? name(SyncEnvelope? e) => e?.data?[JsonKeys.name] as String?;
      expect(name(spaceFolders()[folder.id]), 'Y from A');
      expect(
        [
          for (final batch in pair.gateway.pushes)
            for (final e in batch)
              if (e.rowKey == folder.id) name(e),
        ],
        isNot(contains('Y from B')),
      );
      expect(
        [
          for (final entry in await b().db.syncOutboxDao.pending())
            entry.rowKey,
        ],
        isNot(contains(folder.id)),
        reason: 'retired, so no later session pushes it either',
      );
      expect(
        (await a().db.folderDao.getFolderById(folder.id))!.name,
        'Y from A',
      );

      // The parked row is missing on B until it is pushed again (record §8);
      // the next push of it lands and B's park list lets go of it.
      await a().db.folderDao.updateFolder(id: folder.id, name: 'Y again');
      await a().sync();
      await b().sync();
      expect(
        (await b().db.folderDao.getFolderById(folder.id))!.name,
        'Y again',
      );
      expect(b().engine.current.parkedCount, 0);
    });

    test('a table that faults on every run holds back only its own rows: the '
        'others are pushed on the first run and the flag stays', () async {
      await pair.close();
      pair = await SyncPair.open(bind: false);
      await pair.bind(a());
      await a().db.folderDao.createFolder(name: 'A folder');
      await a().sync();
      final preBind = await b().db.folderDao.createFolder(name: 'B pre-bind');
      await pair.bind(b());
      await b().db.calendarCategoryDao.insertCategory(
        birthdayCategory(name: 'B cat'),
      );
      b().hooks.onBeforePage = (table) async {
        if (table == 'folders') throw StateError('fails for good');
      };

      for (var run = 0; run < 3; run++) {
        final report = await b().sync();

        expect(report.failure, SyncGatewayFailure.unknown, reason: 'run $run');
        expect(
          pair.gateway.rowsOf(pair.space, 'calendar_categories').keys,
          ['birthday'],
          reason: 'run $run',
        );
        expect(spaceFolders(), isNot(contains(preBind.id)), reason: 'run $run');
        expect(
          await b().db.syncDao.getValue(SyncDao.keyBindMergePending),
          isNotNull,
          reason: 'run $run',
        );
      }

      b().hooks.onBeforePage = null;
      final healed = await b().sync();

      expect(healed.failure, isNull);
      expect(spaceFolders(), contains(preBind.id));
      expect(
        await b().db.syncDao.getValue(SyncDao.keyBindMergePending),
        isNull,
      );
    });
  });
}
