import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_table_binding.dart';
import 'package:anta/services/sync/sync_tables.dart';
import 'package:anta/services/sync/tables/content_chunks_binding.dart';
import 'package:anta/services/sync/tables/notes_binding.dart';

import '../../support/fake_sync_gateway.dart';
import '../../support/scale_fixtures.dart';
import 'support/sync_pair.dart';

const int _mib = 1024 * 1024;

/// How far under its budget a full part may end: one chunk document, the
/// row that did not fit.
const int _slack = ContentChunksBinding.maxGzBytes;

/// A binding that works like its inner one and writes `encode:<rowKey>` to
/// [_log] for every row it encodes — where a note's body is read — so a
/// test sees how far past a part's cut the drain read.
class _CountingEncode extends SyncTableBinding<Object> {
  final SyncTableBinding<Object> _inner;
  final List<String> _log;

  const _CountingEncode(this._inner, this._log);

  @override
  String get table => _inner.table;

  @override
  SyncInvalidation get invalidation => _inner.invalidation;

  @override
  int? get pullPageLimit => _inner.pullPageLimit;

  @override
  bool get pulls => _inner.pulls;

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
  }) {
    _log.add('encode:${_inner.rowKeyOf(row)}');
    return _inner.encode(db, row, boundUid: boundUid);
  }

  @override
  Object decode(SyncEnvelope envelope) => _inner.decode(envelope);

  @override
  Future<MergeOutcome> mergeRemote(
    AppDatabase db,
    SyncEnvelope envelope, {
    String? floor,
  }) => _inner.mergeRemote(db, envelope, floor: floor);
}

/// Every synced table, the encodes of the notes and of their chunks — every
/// row that reads a body — written to [log].
List<SyncTableBinding<Object>> _bodiesCounted(List<String> log) => [
  for (final binding in syncTableBindings)
    binding.table == 'notes' || binding.table == 'content_chunks'
        ? _CountingEncode(binding, log)
        : binding,
];

/// How a run sizes its calls for a slow link (scalability record S10): the
/// pull page per table and its halving on a timeout, the push part cut by a
/// byte budget as rows are encoded, the spacing between parts, the push
/// budget's reset once the outbox is empty, and the overlap re-read walked
/// to its end within a run and begun again by the next.
void main() {
  late SyncPair pair;
  SyncDevice a() => pair.a;
  SyncDevice b() => pair.b;

  setUp(() async => pair = await SyncPair.open());
  tearDown(() async => pair.close());

  /// The page sizes asked for [table], in order.
  List<String> takes(String table) => [
    for (final take in pair.gateway.pullTakes)
      if (take.startsWith('$table:')) take,
  ];

  /// The seed of the next note [notesOn] writes in this test.
  var seed = 0;
  setUp(() => seed = 0);

  /// [count] notes of [size] code units of [noiseBody] on [device], under
  /// one folder: about twice [size] in bytes on the wire, no chunk shared
  /// with another note.
  Future<List<Note>> notesOn(SyncDevice device, int count, int size) async {
    final folder = await device.db.folderDao.createFolder(name: 'Long');
    return [
      for (var i = 0; i < count; i++)
        await writeNote(
          device,
          folderId: folder.id,
          title: 'Note $i',
          body: noiseBody(size, seed: seed++),
        ),
    ];
  }

  /// Each push's bytes, as the pusher counts them against its budget.
  List<int> partBytes() => [
    for (final batch in pair.gateway.pushes) FakeSyncGateway.bytesOf(batch),
  ];

  /// Each push's document count.
  List<int> partLengths() => [
    for (final batch in pair.gateway.pushes) batch.length,
  ];

  group('pull pages', () {
    test('notes are pulled fifty to a page, every other table at the '
        'gateway\'s maxBatch', () async {
      await notesOn(b(), 60, 10);
      await b().sync();
      pair.gateway.pullTakes.clear();

      final report = await a().sync();

      expect(report.failure, isNull);
      expect(takes('notes'), ['notes:50', 'notes:50']);
      expect(takes('folders'), ['folders:500']);
      expect(await a().db.select(a().db.notes).get(), hasLength(60));
    });

    test('a timed-out page halves that table\'s page, later runs pull with '
        'it past an emptied outbox, and a start restores it', () async {
      await notesOn(b(), 60, 10);
      await b().sync();
      // The call after the folders' only page is the notes' first.
      pair.gateway.onPullPage = (table) async {
        if (table != 'folders') return;
        pair.gateway.onPullPage = null;
        pair.gateway.failNextWithException(
          const SyncGatewayException.timedOut(),
        );
      };

      final failed = await a().sync();

      expect(failed.failure, SyncGatewayFailure.offline);
      expect(
        a().engine.current.lastFailure?.failure,
        SyncGatewayFailure.offline,
      );

      pair.gateway.pullTakes.clear();
      final retried = await a().sync();

      expect(retried.failure, isNull);
      expect(takes('notes'), ['notes:25', 'notes:25', 'notes:25']);
      expect(await a().db.select(a().db.notes).get(), hasLength(60));
      expect(await a().db.syncOutboxDao.count(), 0);

      await notesOn(b(), 1, 10);
      await b().sync();
      pair.gateway.pullTakes.clear();
      await a().sync();

      expect(takes('notes'), [
        'notes:25',
      ], reason: 'a slow link outlasts an emptied outbox');

      pair.gateway.pullTakes.clear();
      await a().engine.start();
      await a().settle();

      expect(takes('notes'), ['notes:50']);
    });

    test('a second timeout in a row quarters the page', () async {
      await notesOn(b(), 30, 10);
      await b().sync();
      var timeouts = 2;
      pair.gateway.onPullPage = (table) async {
        if (table == 'notes' && timeouts-- > 0) {
          throw const SyncGatewayException.timedOut();
        }
      };

      expect((await a().sync()).failure, SyncGatewayFailure.offline);
      expect((await a().sync()).failure, SyncGatewayFailure.offline);
      pair.gateway.pullTakes.clear();
      final report = await a().sync();

      expect(report.failure, isNull);
      // 50, halved to 25, quartered to 6.
      expect(takes('notes'), [for (var i = 0; i < 5; i++) 'notes:6']);
    });

    test('a 900 KB note pulls over a 0.25 Mbit/s link after at most six '
        'halvings', () async {
      await notesOn(b(), 8, 440000);
      final (pushed, _) = await b().syncFiringSpacing();
      expect(pushed.failure, isNull);
      expect(pair.gateway.rowsOf(pair.space, 'notes'), hasLength(8));
      // What 0.25 Mbit/s carries inside the call's 60 s.
      pair.gateway.pullBytesPerCall = 250000 ~/ 8 * 60;

      var timeouts = 0;
      SyncRunReport report;
      do {
        report = await a().sync();
        if (report.failure != null) {
          expect(report.failure, SyncGatewayFailure.offline);
          timeouts++;
        }
      } while (report.failure != null && timeouts <= 6);

      expect(timeouts, lessThanOrEqualTo(6));
      expect(report.failure, isNull);
      expect(await a().db.select(a().db.notes).get(), hasLength(8));
    });
  });

  group('push parts', () {
    test('a part is the prefix the budget holds: no body past its cut is '
        'read, and the next part goes on from there', () async {
      final log = <String>[];
      await pair.close();
      pair = await SyncPair.open(tables: _bodiesCounted(log));
      // About 850 KB a note on the wire.
      await notesOn(a(), 10, 425000);
      final queue = [
        for (final entry in await a().db.syncOutboxDao.pending()) entry.rowKey,
      ];
      final parts = <List<String>>[];
      pair.gateway.onPushBatch = (batch) async {
        parts.add([for (final envelope in batch) envelope.rowKey]);
        log.add('push');
      };

      final (report, _) = await a().syncFiringSpacing();

      expect(report.failure, isNull);
      // End to end, the parts are the queue in its order: each the prefix of
      // what the last one left, each note's chunks ahead of its manifest.
      expect(parts.expand((part) => part).toList(), queue);
      // Between two pushes nothing is read but the part and the one row past
      // its cut, which the next part reads again first.
      var part = 0;
      var read = <String>[];
      for (final line in log) {
        if (line != 'push') {
          read.add(line.substring('encode:'.length));
          continue;
        }
        final past = [
          for (final key in read)
            if (!parts[part].contains(key)) key,
        ];
        expect(past.length, lessThanOrEqualTo(1), reason: 'part $part');
        if (past.isNotEmpty) {
          expect(parts[part + 1].first, past.single, reason: 'part $part');
        }
        read = [];
        part++;
      }
      expect(part, parts.length);
      expect(partBytes()[0], inInclusiveRange(2 * _mib - _slack, 2 * _mib));
      expect(partBytes()[1], inInclusiveRange(4 * _mib - _slack, 4 * _mib));
      // Documents, chunks and manifests; was [3, 4, 4] notes before S6.
      expect(partLengths(), [95, 195, 173]);
      expect(await a().db.syncOutboxDao.count(), 0);
    });

    test('a manifest never goes ahead of a chunk it names: chunks queued '
        'after it go first, over as many parts as they take, and the '
        'manifest with the last of them', () async {
      // About 5 MB: its chunks alone overflow the 4 MiB part.
      final big = (await notesOn(a(), 1, 2500000)).single;
      await notesOn(a(), 2, 425000);
      // Every chunk entry behind every manifest, as a re-queue leaves a chunk
      // two notes share: at the newer note's stamp.
      await a().db.customUpdate(
        "UPDATE sync_outbox SET hlc = (SELECT MAX(hlc) FROM sync_outbox) "
        "|| '~' WHERE table_name = 'content_chunks'",
        updates: {a().db.syncOutbox},
      );

      final (report, _) = await a().syncFiringSpacing();

      expect(report.failure, isNull);
      expect(report.parked, 0);
      final sent = [for (final batch in pair.gateway.pushes) ...batch];
      final firstAt = <String, int>{};
      for (final (i, envelope) in sent.indexed) {
        firstAt.putIfAbsent(envelope.rowKey, () => i);
      }
      for (final (i, envelope) in sent.indexed) {
        if (envelope.table != 'notes') continue;
        final named = envelope.data![NotesBinding.chunksKey]! as List;
        for (final hash in named.cast<String>()) {
          expect(firstAt[hash], lessThan(i), reason: envelope.rowKey);
        }
      }
      int partOf(String key) =>
          pair.gateway.pushes.indexWhere((b) => b.any((e) => e.rowKey == key));
      final bigManifest = pair.gateway.rowsOf(pair.space, 'notes')[big.id]!;
      final spanned = {
        for (final hash in bigManifest.data![NotesBinding.chunksKey]! as List)
          partOf(hash as String),
      };
      expect(spanned.length, greaterThan(1));
      expect(partOf(big.id), spanned.reduce((a, b) => a > b ? a : b));
      expect(await a().db.syncOutboxDao.count(), 0);
      // The folder and as many of the big note's chunks as fill the 2 MiB
      // part, then 4 MiB of them, then the rest with the three manifests;
      // was [1, 96, 168, 90] while a note's chunks went into a part all
      // together or not at all.
      expect(partLengths(), [97, 184, 74]);
    });

    test('a manifest\'s chunks are encoded as they go into parts: each once '
        'in the drain, however many parts the note spans', () async {
      final log = <String>[];
      await pair.close();
      pair = await SyncPair.open(tables: _bodiesCounted(log));
      // About 5 MB that gzip cannot shrink: more than the first part holds,
      // so one chunk is encoded for a part it does not fit.
      final big = (await notesOn(a(), 1, 2500000)).single;
      // Every chunk entry behind the manifest, so it is the manifest that
      // brings them into the parts.
      await a().db.customUpdate(
        "UPDATE sync_outbox SET hlc = (SELECT MAX(hlc) FROM sync_outbox) "
        "|| '~' WHERE table_name = 'content_chunks'",
        updates: {a().db.syncOutbox},
      );

      final (report, _) = await a().syncFiringSpacing();

      expect(report.failure, isNull);
      expect(pair.gateway.pushes.length, greaterThan(1));
      final hashes = (await a().db.contentChunkDao.hashesOf(
        big.id,
      )).cast<String>().toSet();
      final encodes = <String, int>{};
      for (final line in log) {
        final key = line.substring('encode:'.length);
        encodes[key] = (encodes[key] ?? 0) + 1;
      }
      expect(
        {for (final hash in hashes) hash: encodes[hash]},
        {for (final hash in hashes) hash: 1},
      );
      expect(await a().db.syncOutboxDao.count(), 0);
    });

    test('a part cut by bytes waits the spacing before the next one, and '
        'the budget doubles after the full part', () async {
      // About 5 MB in all: more than 2 MiB is left after the first part.
      await notesOn(a(), 6, 425000);
      final clock = DateTime.utc(2026, 11, 8);
      a().now = () => clock;

      var done = false;
      final run = a().sync().whenComplete(() => done = true);
      while (!a().scheduler.pending.contains(SyncEngine.minPartSpacing)) {
        expect(done, isFalse);
        await Future<void>.delayed(Duration.zero);
      }
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(partBytes(), [inInclusiveRange(2 * _mib - _slack, 2 * _mib)]);

      expect(a().scheduler.fire(SyncEngine.minPartSpacing), 1);
      final report = await run;

      expect(report.failure, isNull);
      // 2 MiB, then the rest in one part of more than 2 MiB: the budget
      // doubled. Was [3, 2] notes of 850 KB before S6.
      expect(partBytes(), hasLength(2));
      expect(partBytes()[1], inInclusiveRange(2 * _mib + 1, 4 * _mib));
      expect(partLengths(), [95, 184]);
    });

    test('a timed-out push halves the budget and holds it there until the '
        'outbox is empty, then the next drain starts at 2 MiB again', () async {
      await notesOn(a(), 4, 425000);
      // Less than 2 MiB, more than 1 MiB.
      pair.gateway.pushBytesPerCall = 1500000;

      final failed = await a().syncFiringSpacing();

      expect(failed.$1.failure, SyncGatewayFailure.offline);
      expect(pair.gateway.pushes, isEmpty);

      final (report, _) = await a().syncFiringSpacing();

      expect(report.failure, isNull);
      // 1 MiB to a part, and no growth back past the size that timed out:
      // every part but the last is full at 1 MiB.
      final halved = partBytes();
      for (final bytes in halved.take(halved.length - 1)) {
        expect(bytes, inInclusiveRange(_mib - _slack, _mib));
      }
      expect(halved.last, lessThanOrEqualTo(_mib));
      // Was [2, 1, 1, 1] notes of 850 KB before S6.
      final halvedLengths = partLengths();
      expect(await a().db.syncOutboxDao.count(), 0);

      pair.gateway.pushes.clear();
      pair.gateway.pushBytesPerCall = null;
      await notesOn(a(), 3, 425000);
      final (again, _) = await a().syncFiringSpacing();

      expect(again.failure, isNull);
      // 2 MiB again, then the rest. Was [3, 1] before S6.
      expect(partBytes(), hasLength(2));
      expect(partBytes()[0], inInclusiveRange(2 * _mib - _slack, 2 * _mib));
      expect(
        [halvedLengths, partLengths()],
        [
          [48, 47, 47, 40],
          [102, 42],
        ],
      );
    });

    test('a thousand-note outbox — twice the count cut — goes out holding '
        'one part and one row of bodies at a time', () async {
      final log = <String>[];
      await pair.close();
      pair = await SyncPair.open(tables: _bodiesCounted(log));
      // About 20 KB a note on the wire, in two or three chunks.
      await notesOn(a(), 1000, 10000);
      final chunks =
          (await a().db
                  .customSelect(
                    'SELECT COUNT(DISTINCT content_hash) AS n FROM content_chunks',
                  )
                  .getSingle())
              .read<int>('n');
      final parts = <Set<String>>[];
      pair.gateway.onPushBatch = (batch) async {
        parts.add({for (final envelope in batch) envelope.rowKey});
        log.add('push');
      };

      final (report, _) = await a().syncFiringSpacing();

      expect(report.failure, isNull);
      // The folder, the manifests and their chunks; was 1001 before S6.
      expect(report.pushedRows, 1001 + chunks);
      expect(await a().db.syncOutboxDao.count(), 0);
      var read = <String>[];
      var part = 0;
      for (final line in log) {
        if (line == 'push') {
          final past = read.where((key) => !parts[part].contains(key));
          expect(past.length, lessThanOrEqualTo(1), reason: 'part $part');
          read = [];
          part++;
        } else {
          read.add(line.substring('encode:'.length));
        }
      }
      expect(part, parts.length);
      expect(
        parts.map((p) => p.length).reduce((a, b) => a > b ? a : b),
        lessThanOrEqualTo(pair.gateway.maxBatch),
        reason: 'a part is cut by count as well as by bytes',
      );
    });

    test('a stop during the spacing ends the wait: the run halts before its '
        'next push and leaves no timer behind', () async {
      await notesOn(a(), 4, 425000);
      final clock = DateTime.utc(2026, 11, 8);
      a().now = () => clock;
      final run = a().sync();
      while (!a().scheduler.pending.contains(SyncEngine.minPartSpacing)) {
        await Future<void>.delayed(Duration.zero);
      }

      await a().engine.stop();
      final report = await run;

      expect(report.skipped, SyncRunSkip.stopped);
      expect(partBytes(), [inInclusiveRange(2 * _mib - _slack, 2 * _mib)]);
      expect(a().scheduler.pending, isNot(contains(SyncEngine.minPartSpacing)));
    });
  });

  group('the overlap re-read', () {
    /// B's ten folders in the space; the keys in the order they arrived.
    Future<List<String>> tenFolders() async {
      for (var i = 0; i < 10; i++) {
        await b().db.folderDao.createFolder(name: 'Folder $i');
      }
      await b().sync();
      return pair.gateway.rowsOf(pair.space, 'folders').keys.toList();
    }

    /// Resumed pulls re-read six documents before the cursor, two to a page.
    void crowdTheWindow() {
      pair.gateway.maxBatch = 2;
      pair.gateway.replayOnResume = 6;
    }

    /// The next folders page past the [nth] of the current run times out.
    void timeOutFoldersPage(int nth) {
      var page = 0;
      pair.gateway.onPullPage = (table) async {
        if (table == 'folders' && ++page == nth) {
          throw const SyncGatewayException.timedOut();
        }
      };
    }

    List<String> pulledFolders() => [
      for (final (table, rows) in a().hooks.pages)
        if (table == 'folders')
          for (final row in rows) row.rowKey,
    ];

    Future<String?> settledMark() =>
        a().db.syncDao.getValue(SyncDao.keyPullSettled('folders'));

    test('a window larger than a page is re-read to its end in one run, each '
        'document once, and the cursor never moves back', () async {
      final keys = await tenFolders();
      await a().sync();
      crowdTheWindow();
      final cursor = await a().db.syncDao.getValue(
        SyncDao.keyPullCursor('folders'),
      );
      a().hooks.clear();

      final report = await a().sync();

      expect(report.failure, isNull);
      expect(pulledFolders(), keys.sublist(4));
      expect(
        await a().db.syncDao.getValue(SyncDao.keyPullCursor('folders')),
        cursor,
      );
    });

    test('a timeout inside a re-read starts the next run\'s re-read over: a '
        'write that became visible after the cut arrives, and the table '
        'settles only after a complete walk', () async {
      pair.gateway.timedCursors = true;
      final keys = await tenFolders();
      // Received inside the window, not yet visible to a query.
      pair.gateway.unreadable.add(('folders', keys[4]));
      await a().sync();
      crowdTheWindow();
      timeOutFoldersPage(2);

      expect((await a().sync()).failure, SyncGatewayFailure.offline);
      expect(await settledMark(), isNull);

      pair.gateway.unreadable.clear();
      await a().db.syncDao.setValue(
        SyncDao.keyServerSeen,
        '${DateTime.utc(2027).microsecondsSinceEpoch}',
      );
      timeOutFoldersPage(3);

      expect((await a().sync()).failure, SyncGatewayFailure.offline);
      final ids = [
        for (final folder in await a().db.select(a().db.folders).get())
          folder.id,
      ];
      expect(ids, contains(keys[4]), reason: 'the window was read again');
      expect(await settledMark(), isNull, reason: 'that walk was cut too');

      pair.gateway.onPullPage = null;
      expect((await a().sync()).failure, isNull);

      expect(
        await settledMark(),
        await a().db.syncDao.getValue(SyncDao.keyPullCursor('folders')),
      );
    });
  });
}
