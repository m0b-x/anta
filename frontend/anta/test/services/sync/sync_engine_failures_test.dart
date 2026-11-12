import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/json_keys.dart';
import 'package:anta/database/crdt/hlc.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_schema.dart';
import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_status.dart';
import 'package:anta/services/sync/sync_suspension.dart';
import 'package:anta/services/sync/sync_table_binding.dart';
import 'package:anta/services/sync/sync_tables.dart';
import 'package:anta/services/sync/tables/content_chunks_binding.dart';
import 'package:anta/services/sync/tables/notes_binding.dart';

import '../../support/fake_sync_gateway.dart';
import '../../support/scale_fixtures.dart';
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
  int? get pullPageLimit => _inner.pullPageLimit;

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

/// A binding that loads like its inner one, except that a load whose keys
/// include one of [_keys] throws — one row's column this build can no longer
/// decode, which the push must narrow down to that row.
class _FaultyLoad extends _FaultyMerge {
  final Set<String> _keys;

  const _FaultyLoad(SyncTableBinding<Object> inner, this._keys)
    : super(inner, const {});

  @override
  Future<List<Object>> loadByKeys(AppDatabase db, Iterable<String> rowKeys) {
    if (rowKeys.any(_keys.contains)) {
      throw const FormatException('a column this build cannot read');
    }
    return super.loadByKeys(db, rowKeys);
  }
}

/// Every synced table, the folders' load throwing for [keys].
List<SyncTableBinding<Object>> _foldersFailingLoad(Set<String> keys) => [
  for (final binding in syncTableBindings)
    binding.table == 'folders' ? _FaultyLoad(binding, keys) : binding,
];

/// Every synced table, the folders' merge first running a statement SQLite
/// refuses for the row keys in [refused] — an error that is neither a
/// constraint nor the end of the transaction, so the savepoint rolls back
/// and only the error's type decides the page.
List<SyncTableBinding<Object>> _foldersRefusingStatement(
  Set<String> refused,
) => [
  for (final binding in syncTableBindings)
    binding.table == 'folders' ? _RefusedStatement(binding, refused) : binding,
];

class _RefusedStatement extends _FaultyMerge {
  final Set<String> _refused;

  _RefusedStatement(SyncTableBinding<Object> inner, this._refused)
    : super(inner, const {});

  @override
  Future<MergeOutcome> mergeRemote(
    AppDatabase db,
    SyncEnvelope envelope, {
    String? floor,
  }) async {
    if (_refused.contains(envelope.rowKey)) {
      await db.customSelect('SELECT * FROM no_such_table').get();
    }
    return super.mergeRemote(db, envelope, floor: floor);
  }
}

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
      expect(
        a().engine.current.lastFailure?.failure,
        SyncGatewayFailure.offline,
      );
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
    // 04:00 in Los Angeles: the reset is twenty hours away.
    final pausedAt = DateTime.utc(2026, 11, 8, 12);
    a().now = () => pausedAt;
    pair.gateway.failNextWith(SyncGatewayFailure.quotaExhausted);

    final report = await a().sync();

    expect(report.failure, SyncGatewayFailure.quotaExhausted);
    expect(a().engine.current.pause, SyncPause.quotaExhausted);
    expect(
      await a().db.syncDao.getValue(SyncDao.keyQuotaPausedAt),
      '${pausedAt.millisecondsSinceEpoch}',
    );
    expect(a().engine.current.quotaPausedAt, pausedAt);
    expect(a().scheduler.pending, [const Duration(hours: 1)]);

    a().scheduler.fire();
    await a().settle();

    expect(spaceFolders().keys, [folder.id]);
    expect(a().engine.current.pause, SyncPause.none);
    expect(await a().db.syncDao.getValue(SyncDao.keyQuotaPausedAt), isNull);
  });

  test('a quota pause within the hour of the reset retries five minutes '
      'after it', () async {
    await a().db.folderDao.createFolder(name: 'Training');
    // 23:30 in Los Angeles, standard time: the reset is 30 minutes away.
    a().now = () => DateTime.utc(2026, 11, 8, 7, 30);
    pair.gateway.failNextWith(SyncGatewayFailure.quotaExhausted);

    await a().sync();

    expect(a().scheduler.pending, [const Duration(minutes: 35)]);
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
      expect(
        await a().db.syncOutboxDao.count(),
        1,
        reason: 'retried next launch',
      );

      expect(
        (await a().sync()).pushedRows,
        0,
        reason: 'parked for the session',
      );
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

    // A note no longer parks for its size (S6): a refusal parks it the same
    // way, at its stamp.
    test('a parked note edited since is pushed at once', () async {
      final folder = await a().db.folderDao.createFolder(name: 'Big');
      final note = await writeNote(
        a(),
        folderId: folder.id,
        title: 'Huge',
        body: 'refused',
      );
      pair.gateway.refuse('notes', note.id, SyncGatewayFailure.invalidData);
      expect((await a().sync()).parked, 1);
      pair.gateway.accept('notes', note.id);

      await editNote(a(), note.id, 'short now');
      final report = await a().sync();

      expect(report.pushedRows, 2, reason: 'its new chunk and the manifest');
      expect(pair.gateway.rowsOf(pair.space, 'notes').keys, [note.id]);
      expect(a().engine.current.parkedCount, 0);
      expect(await a().db.syncOutboxDao.count(), 0);
    });

    test('a refused chunk parks the manifest naming it unsent: the bisect '
        'never lands a manifest without its chunks, and both land once the '
        'refusal lifts', () async {
      final folder = await a().db.folderDao.createFolder(name: 'Log');
      final note = await writeNote(
        a(),
        folderId: folder.id,
        title: 'Log',
        body: bigBody(60 * 1000),
      );
      final hashes = (await a().db.contentChunkDao.hashesOf(
        note.id,
      )).cast<String>();
      expect(hashes.length, greaterThan(2));
      final refused = hashes.first;
      pair.gateway.refuse(
        'content_chunks',
        refused,
        SyncGatewayFailure.invalidData,
      );

      final report = await a().sync();

      expect(report.parked, 2, reason: 'the chunk and its manifest');
      final chunks = pair.gateway.rowsOf(pair.space, 'content_chunks');
      expect(chunks.keys, unorderedEquals(hashes.skip(1)));
      expect(
        pair.gateway.rowsOf(pair.space, 'notes'),
        isNot(contains(note.id)),
      );
      expect(
        (await a().db.syncOutboxDao.pending()).map((e) => e.rowKey),
        unorderedEquals([refused, note.id]),
      );
      final onB = await pair.b.sync();
      expect(onB.parked, 0);
      expect(await pair.b.db.noteDao.getNoteById(note.id), isNull);

      pair.gateway.accept('content_chunks', refused);
      await a().engine.stop();
      await a().engine.start();
      await a().settle();

      expect(
        pair.gateway.rowsOf(pair.space, 'content_chunks'),
        contains(refused),
      );
      expect(pair.gateway.rowsOf(pair.space, 'notes'), contains(note.id));
      expect(await a().db.syncOutboxDao.count(), 0);
      await pair.b.sync();
      expect(
        await pair.b.db.contentChunkDao.loadContent(note.id),
        await a().db.contentChunkDao.loadContent(note.id),
      );
    });

    test('a note another account owns has none of its chunks pushed into '
        'this space when it is saved (D16)', () async {
      final folder = await a().db.folderDao.createFolder(name: 'Shared');
      const secret = 'Another account\'s plan';
      final theirs = await a().db.noteDao.createNote(
        folderId: folder.id,
        title: 'Theirs',
        content: secret,
        ownerId: 'them',
      );
      await editNote(a(), theirs.id, '$secret, edited here');

      await a().sync();

      expect(pair.gateway.rowsOf(pair.space, 'content_chunks'), isEmpty);
      expect([
        for (final entry in await a().db.syncOutboxDao.pending())
          if (entry.syncedTable == 'content_chunks') entry,
      ], isEmpty);
    });

    test('a text another account\'s note held first is still pushed for our '
        'note that holds it too, ahead of our manifest', () async {
      final folder = await a().db.folderDao.createFolder(name: 'Shared');
      // Past the wire cutover, whose re-queue would cover the gap.
      await a().sync();
      const text = 'Squat 5x5';
      await a().db.noteDao.createNote(
        folderId: folder.id,
        title: 'Theirs',
        content: text,
        ownerId: 'them',
      );
      // Held as a restore leaves it: unqueued, as the bind's re-seed keeps
      // every row of another account (D16).
      await a().db.syncOutboxDao.clear();
      final mine = await writeNote(
        a(),
        folderId: folder.id,
        title: 'Mine',
        body: text,
      );

      await a().sync();
      final onB = await pair.b.sync();

      final hash = (await a().db.contentChunkDao.hashesOf(mine.id)).single!;
      expect(pair.gateway.rowsOf(pair.space, 'content_chunks').keys, [hash]);
      expect(onB.parked, 0);
      expect(await pair.b.db.contentChunkDao.loadContent(mine.id), text);
    });

    test('a manifest in a later part waits on a chunk the bisect parked in '
        'an earlier one, though that chunk was pushed in the drain', () async {
      final folder = await a().db.folderDao.createFolder(name: 'Log');
      await a().sync();
      const text = 'Bench 3x8';
      final first = await writeNote(
        a(),
        folderId: folder.id,
        title: 'Monday',
        body: text,
      );
      final second = await writeNote(
        a(),
        folderId: folder.id,
        title: 'Thursday',
        body: text,
      );
      final hash = (await a().db.contentChunkDao.hashesOf(first.id)).single!;
      // The chunk and the first manifest in one part, the second manifest in
      // the next.
      pair.gateway.maxBatch = 2;
      pair.gateway.refuse(
        'content_chunks',
        hash,
        SyncGatewayFailure.invalidData,
      );

      final report = await a().sync();

      expect(report.parked, 3);
      expect(
        pair.gateway.rowsOf(pair.space, 'notes'),
        isNot(anyOf(contains(first.id), contains(second.id))),
      );
    });

    test(
      'more than twenty refused rows in one drain means no access',
      () async {
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
      },
    );
  });

  test('a drain with two rows the rules refuse reads the space for the batch, '
      'then once per row before it is parked', () async {
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
    expect(pair.gateway.readSpaceCalls, 3);
  });

  test('fifteen rows the rules refuse: the first drain reads the space once '
      'per row, every later one only for the batch, since a park tried again '
      'is a known refusal (review K1)', () async {
    for (var i = 0; i < 15; i++) {
      final folder = await a().db.folderDao.createFolder(name: 'Refused $i');
      pair.gateway.refuse(
        'folders',
        folder.id,
        SyncGatewayFailure.permissionDenied,
      );
    }

    final reads = <int>[];
    for (var sync = 0; sync < 3; sync++) {
      pair.gateway.readSpaceCalls = 0;
      final report = await a().sync();
      expect(report.parked, 15);
      expect(report.failure, isNull);
      reads.add(pair.gateway.readSpaceCalls);
    }

    expect(reads, [16, 1, 1]);
    expect(a().engine.current.pause, SyncPause.none);
    expect(a().engine.current.parkedCount, 15);
  });

  group('a denied push is diagnosed', () {
    test('a deleted space pauses as deleted', () async {
      await a().db.folderDao.createFolder(name: 'Training');
      pair.gateway.consoleDeleteSpace(pair.space);

      final report = await a().sync();

      expect(report.failure, SyncGatewayFailure.permissionDenied);
      expect(a().engine.current.pause, SyncPause.spaceDeleted);
      expect(a().scheduler.pending, isEmpty, reason: 'no retry when deleted');
      expect((await a().sync()).skipped, SyncRunSkip.spaceDeleted);
    });

    test('a space marked for deletion pauses as deleted and keeps the '
        'outbox', () async {
      await a().db.folderDao.createFolder(name: 'Training');
      await pair.gateway.markSpaceDeleted(pair.space);

      final report = await a().sync();

      expect(report.failure, SyncGatewayFailure.permissionDenied);
      expect(report.parked, 0, reason: 'the space refused, not the row');
      expect(a().engine.current.pause, SyncPause.spaceDeleted);
      expect(a().scheduler.pending, isEmpty, reason: 'no retry when deleted');
      expect(await a().db.syncOutboxDao.count(), 1);
      expect(pair.gateway.rowsOf(pair.space, 'folders'), isEmpty);
    });

    test('a space marked mid-drain pauses as deleted though an earlier batch '
        'held a refused row: the later rows are not parked (review '
        'F5)', () async {
      final folders = [
        for (final name in ['One', 'Two', 'Three'])
          await a().db.folderDao.createFolder(name: name),
      ];
      pair.gateway
        ..maxBatch = 1
        ..refuse('folders', folders[0].id, SyncGatewayFailure.permissionDenied)
        ..onPushBatch = (batch) async {
          if (batch.single.rowKey == folders[1].id) {
            await pair.gateway.markSpaceDeleted(pair.space);
          }
        };

      final report = await a().sync();

      expect(report.failure, SyncGatewayFailure.permissionDenied);
      expect(report.parked, 1, reason: 'only the row the rules refused');
      expect(a().engine.current.pause, SyncPause.spaceDeleted);
      expect(pair.gateway.readSpaceCalls, 2, reason: 'once per denied batch');
      expect(spaceFolders().keys, [folders[1].id]);
    });

    test('a space marked during one batch\'s bisect pauses as deleted: only '
        'the row the rules refused is parked (review G5)', () async {
      final folders = [
        for (final name in ['One', 'Two', 'Three', 'Four'])
          await a().db.folderDao.createFolder(name: name),
      ];
      pair.gateway
        ..maxBatch = 4
        ..refuse('folders', folders[0].id, SyncGatewayFailure.permissionDenied)
        ..onPushBatch = (batch) async {
          if (batch.any((row) => row.rowKey == folders[1].id)) {
            await pair.gateway.markSpaceDeleted(pair.space);
          }
        };

      final report = await a().sync();

      expect(report.failure, SyncGatewayFailure.permissionDenied);
      expect(report.parked, 1, reason: 'only the row the rules refused');
      expect(a().engine.current.pause, SyncPause.spaceDeleted);
      expect(spaceFolders().keys, [folders[1].id]);
      expect(
        pair.gateway.readSpaceCalls,
        3,
        reason:
            'the batch\'s diagnosis, then one read per row about to be '
            'parked',
      );
    });

    test('a refusal whose space then reads gone turns into the deleted '
        'pause at the next "Sync now"', () async {
      pair.gateway.failNextWith(SyncGatewayFailure.permissionDenied);
      await a().sync();
      expect(a().engine.current.pause, SyncPause.noAccess);
      pair.gateway.consoleDeleteSpace(pair.space);
      pair.gateway.calls.clear();

      final report = await a().sync();

      expect(report.skipped, SyncRunSkip.spaceDeleted);
      expect(pair.gateway.readSpaceCalls, 1);
      expect(pair.gateway.calls, isEmpty, reason: 'nothing pulled or pushed');
      expect(a().engine.current.pause, SyncPause.spaceDeleted);
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

    // The chunked wire's gate (scalability record S6): a 45 build would
    // read a manifest as a note with no body.
    test(
      'a space this build wrote holds a build at 45 to appOutdated',
      () async {
        expect(DatabaseSchema.bodyWireVersion, 46);
        expect(syncSchema, greaterThanOrEqualTo(46));
        await pair.close();
        pair = await SyncPair.open(buildSchema: 45);
        await a().db.folderDao.createFolder(name: 'Training');

        final report = await a().sync();

        expect(report.failure, SyncGatewayFailure.permissionDenied);
        expect(a().engine.current.pause, SyncPause.appOutdated);
        expect((await a().sync()).skipped, SyncRunSkip.appOutdated);
      },
    );

    // The category's mark (share surfaces §7.4): a 47 build would push a
    // shared category back without its mark and encode its events as
    // private, ending the share unasked.
    test(
      'a space this build wrote holds a build at 47 to appOutdated',
      () async {
        expect(DatabaseSchema.categoryShareWireVersion, 48);
        expect(syncSchema, greaterThanOrEqualTo(48));
        await pair.close();
        pair = await SyncPair.open(buildSchema: 47);
        await a().db.folderDao.createFolder(name: 'Training');

        final report = await a().sync();

        expect(report.failure, SyncGatewayFailure.permissionDenied);
        expect(a().engine.current.pause, SyncPause.appOutdated);
        expect((await a().sync()).skipped, SyncRunSkip.appOutdated);
      },
    );

    test('a space at a newer schema does not lift a noAccess pause', () async {
      await a().db.folderDao.createFolder(name: 'Training');
      pair.gateway.failNextWith(SyncGatewayFailure.permissionDenied);
      await a().sync();
      expect(a().engine.current.pause, SyncPause.noAccess);
      await pair.gateway.pushBatch(
        pair.space,
        const [],
        pushedBy: 'C',
        schema: syncSchema + 1,
      );
      pair.gateway.calls.clear();

      final report = await a().sync();

      // The skip names the pause the re-read left (review F13).
      expect(report.skipped, SyncRunSkip.appOutdated);
      expect(pair.gateway.calls, isEmpty, reason: 'nothing pulled or pushed');
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

    test('a page leaves a seed covering the stamps it committed, a stamp past '
        'the drift guard included (A7 review R132)', () async {
      // Two hours ahead: past `HybridLogicalClock.maxDrift`, the distance a
      // stamp has to run for the seed to be the only thing holding it. The
      // stored seed is what the next open mints from, and no committed row
      // may carry a stamp above it, or the first edit on this row mints
      // under it and loses.
      final ahead = HlcTimestamp(
        wallTime: DateTime.now()
            .add(const Duration(hours: 2))
            .millisecondsSinceEpoch,
        logicalCounter: 0,
        nodeId: 'C',
      ).toString();
      pair.gateway.plant(pair.space, folderEnvelope('far', ahead));

      await a().sync();

      expect(
        (await a().db.folderDao.getFolderById('far'))!.hlcTimestamp,
        ahead,
      );
      final seed = await a().db.syncDao.getValue(SyncDao.keyLastHlc);
      expect(seed, isNotNull);
      expect(seed!.compareTo(ahead), greaterThanOrEqualTo(0));
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
        tables: _foldersFaulting(
          {'partway': () => StateError('after its write')},
          partWay: {'partway'},
        ),
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

    test(
      'a parked key that merges later is no longer counted parked',
      () async {
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
      },
    );

    // Every wait is the engine's own (`sync` awaits `whenIdle`): a background
    // database answers a round trip later than an in-memory one, which a
    // fixed settle does not cover.
    Future<void> diskFull() async {
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
    }

    for (final background in [false, true]) {
      final where = background ? ' — on background-isolate databases' : '';

      test('a merge that fills the disk fails its page whole: the run reports '
          'it, the cursor stays, and the next run applies the page once there '
          'is room$where', () async {
        if (background) {
          await pair.close();
          pair = await SyncPair.open(background: true);
        }
        await diskFull();
      });

      test('a merge whose statement SQLite refuses fails its page whole, the '
          'error unwrapped from the isolate$where', () async {
        final refused = <String>{};
        await pair.close();
        pair = await SyncPair.open(
          background: background,
          tables: _foldersRefusingStatement(refused),
        );
        final b = pair.b;
        final folder = await b.db.folderDao.createFolder(name: 'Refused');
        await b.sync();
        refused.add(folder.id);

        final failed = await a().sync();

        expect(failed.failure, SyncGatewayFailure.unknown);
        expect(failed.parked, 0);
        expect(
          await a().db.syncDao.getValue(SyncDao.keyPullCursor('folders')),
          isNull,
        );
        expect(await a().db.folderDao.getFolderById(folder.id), isNull);

        refused.clear();
        final next = await a().sync();

        expect(next.failure, isNull);
        expect(await a().db.folderDao.getFolderById(folder.id), isNotNull);
        expect(a().engine.current.parkedCount, 0);
      });
    }

    test(
      'an entry whose row was hard-deleted is retired, nothing pushed',
      () async {
        final folder = await a().db.folderDao.createFolder(name: 'Wiped');
        await a().db.customStatement('DELETE FROM folders WHERE id = ?', [
          folder.id,
        ]);

        final report = await a().sync();

        expect(report.pushedRows, 0);
        expect(pair.gateway.pushes, isEmpty);
        expect(await a().db.syncOutboxDao.count(), 0);
      },
    );

    test('a load fault is bisected to its own rows: the rest of the table '
        'still pushes', () async {
      final keys = <String>{};
      await pair.close();
      pair = await SyncPair.open(tables: _foldersFailingLoad(keys));
      final folders = [
        for (final name in ['One', 'Two', 'Three', 'Four'])
          await a().db.folderDao.createFolder(name: name),
      ];
      keys.add(folders[1].id);

      final report = await a().sync();

      expect(report.failure, isNull);
      expect(report.parked, 1);
      expect(report.pushedRows, 3);
      expect(spaceFolders().keys.toSet(), {
        folders[0].id,
        folders[2].id,
        folders[3].id,
      });
      expect(await a().db.syncOutboxDao.count(), 1);
    });

    test('an entry naming a table no binding covers fails the run rather '
        'than parking the table', () async {
      await pair.close();
      pair = await SyncPair.open(
        tables: [
          for (final binding in syncTableBindings)
            if (binding.table != 'folders') binding,
        ],
      );
      await a().db.folderDao.createFolder(name: 'Orphan');

      final report = await a().sync();

      expect(report.failure, SyncGatewayFailure.unknown);
      expect(report.parked, 1);
      expect(await a().db.syncOutboxDao.count(), 1);
    });

    test('the entry it failed on is parked, so the next run gets past it '
        '(A7 review R134)', () async {
      await pair.close();
      pair = await SyncPair.open(
        tables: [
          for (final binding in syncTableBindings)
            if (binding.table != 'folders') binding,
        ],
      );
      await a().db.folderDao.createFolder(name: 'Orphan');
      await a().sync();

      await a().db.calendarEventDao.upsert(eventRow('e1'));
      final second = await a().sync();

      // Without the park the run throws at the same entry for good, and no
      // row of any table is ever pushed again.
      expect(second.failure, isNull);
      expect(second.pushedRows, 1);
      expect(
        pair.gateway.rowsOf(pair.space, 'calendar_events'),
        contains('e1'),
      );
    });

    test(
      'a batch goes out in the queue\'s order, not table by table',
      () async {
        final first = await a().db.folderDao.createFolder(name: 'First');
        await a().db.calendarEventDao.upsert(eventRow('e1'));
        final last = await a().db.folderDao.createFolder(name: 'Last');

        await a().sync();

        expect(
          [for (final envelope in pair.gateway.pushes.single) envelope.rowKey],
          [first.id, 'e1', last.id],
        );
      },
    );

    test('an edit landing during the push keeps its entry queued, and the '
        'next drain sends it', () async {
      final folder = await a().db.folderDao.createFolder(name: 'First');
      pair.gateway.onPushBatch = (batch) async {
        pair.gateway.onPushBatch = null;
        await a().db.folderDao.updateFolder(id: folder.id, name: 'Edited');
      };

      final first = await a().sync();

      expect(
        first.pushedRows,
        2,
        reason: 'the entry the edit raised survived the acknowledgement',
      );
      expect(spaceFolders()[folder.id]?.data?[JsonKeys.name], 'Edited');
      expect(await a().db.syncOutboxDao.count(), 0);

      expect((await a().sync()).pushedRows, 0);
    });

    test('a restore beginning during the push leaves the batch '
        'unacknowledged', () async {
      await a().db.folderDao.createFolder(name: 'In flight');
      final restore = Completer<void>();
      pair.gateway.onPushBatch = (batch) async {
        pair.gateway.onPushBatch = null;
        unawaited(SyncSuspension.run(() => restore.future));
      };

      final report = await a().sync();
      restore.complete();
      await pumpEventQueue();

      expect(report.skipped, SyncRunSkip.suspended);
      expect(await a().db.syncOutboxDao.count(), 1);
    });

    // It was parked before the push until S6 carried a body in pieces.
    test('a note over 900 KB crosses as its chunk documents and a manifest, '
        'in one push, with nothing parked', () async {
      final folder = await a().db.folderDao.createFolder(name: 'Big');
      final note = await writeNote(
        a(),
        folderId: folder.id,
        title: 'Huge',
        body: noiseBody(475000, seed: 1),
      );

      final report = await a().sync();

      expect(report.parked, 0);
      expect(spaceFolders().keys, [folder.id]);
      final manifest = pair.gateway.rowsOf(pair.space, 'notes')[note.id];
      final named = (manifest!.data![NotesBinding.chunksKey]! as List)
          .cast<String>();
      expect(named.length, greaterThan(1));
      expect(
        pair.gateway.rowsOf(pair.space, 'content_chunks').keys,
        unorderedEquals(named.toSet()),
      );
      expect(
        FakeSyncGateway.bytesOf(pair.gateway.pushes.single),
        greaterThan(maxDocumentBytesToday),
      );
      expect(a().engine.current.parkedCount, 0);
      expect(await a().db.syncOutboxDao.count(), 0);
    });

    test('a drain cuts its parts by a byte budget that starts at 2 MiB and '
        'doubles after each full part: a folder and ten notes of 850 KB go '
        'out as parts filled to 2 MiB, to 4 MiB, and the rest', () async {
      final folder = await a().db.folderDao.createFolder(name: 'Big');
      for (var i = 0; i < 10; i++) {
        await writeNote(
          a(),
          folderId: folder.id,
          title: 'Big $i',
          body: noiseBody(425000, seed: i),
        );
      }

      final (report, spacings) = await a().syncFiringSpacing();

      expect(report.failure, isNull);
      expect(report.parked, 0);
      // A part ends at a chunk, wherever its note's other chunks fall: each
      // full part is within one chunk document of its budget (S10; it was
      // three, four and four notes before S6, nine and one under the fixed
      // 8 MiB cut).
      final bytes = [
        for (final batch in pair.gateway.pushes) FakeSyncGateway.bytesOf(batch),
      ];
      expect(bytes, hasLength(3));
      const mib = 1024 * 1024;
      const slack = ContentChunksBinding.maxGzBytes;
      expect(bytes[0], inInclusiveRange(2 * mib - slack, 2 * mib));
      expect(bytes[1], inInclusiveRange(4 * mib - slack, 4 * mib));
      expect(bytes[2], lessThanOrEqualTo(8 * mib));
      expect(
        [for (final batch in pair.gateway.pushes) batch.length],
        [95, 195, 173],
      );
      expect(spacings, 2, reason: 'the two parts cut by bytes wait');
      expect(pair.gateway.rowsOf(pair.space, 'notes'), hasLength(10));
      expect(await a().db.syncOutboxDao.count(), 0);
    });

    test(
      'a key parked on pull keeps its local edit out of the drain',
      () async {
        final faults = <String, Object Function()>{};
        await pair.close();
        pair = await SyncPair.open(tables: _foldersFaulting(faults));
        final b = pair.b;
        final folder = await a().db.folderDao.createFolder(name: 'Y');
        await a().sync();
        await b.sync();
        await b.db.folderDao.updateFolder(id: folder.id, name: 'Y from B');
        await b.sync();
        await a().db.folderDao.updateFolder(id: folder.id, name: 'Y from A');
        faults[folder.id] = () => StateError('a local fault on A');

        final report = await a().sync();

        expect(report.parked, 1);
        expect(
          spaceFolders()[folder.id]?.data?[JsonKeys.name],
          'Y from B',
          reason: 'A lacks the space\'s version, which may be the newer one',
        );
        expect(
          [
            for (final entry in await a().db.syncOutboxDao.pending())
              entry.rowKey,
          ],
          [folder.id],
        );
      },
    );
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
      expect([
        for (final batch in pair.gateway.pushes)
          for (final e in batch)
            if (e.rowKey == folder.id) name(e),
      ], isNot(contains('Y from B')));
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
