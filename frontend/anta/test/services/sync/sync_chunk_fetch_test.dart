import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/json_keys.dart';
import 'package:anta/database/chunking/chunk_hasher.dart';
import 'package:anta/database/chunking/content_chunker.dart';
import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/tables/content_chunks_binding.dart';
import 'package:anta/services/sync/tables/notes_binding.dart';

import '../../support/fake_sync_gateway.dart';
import '../../support/scale_fixtures.dart';
import 'support/sync_pair.dart';

/// The pull side of the chunked wire (scalability record S6b): a page of
/// manifests has the chunks it names and this device lacks read from the
/// space by hash, outside the page's transaction and before its merges; a
/// chunk the space does not hold parks the note that names it, and only
/// that note.
void main() {
  late SyncPair pair;
  SyncDevice a() => pair.a;
  SyncDevice b() => pair.b;

  setUp(() async => pair = await SyncPair.open());
  tearDown(() async => pair.close());

  /// The chunk keys each `readRows` call asked for, from [from] on.
  List<List<String>> chunkReads({int from = 0}) => [
    for (final (i, keys) in pair.gateway.rowReadKeys.indexed)
      if (i >= from && pair.gateway.rowReads[i].startsWith('content_chunks:'))
        keys,
  ];

  /// The notes the last runs handed to `afterPage` on [device].
  int notesApplied(SyncDevice device) => [
    for (final (table, rows) in device.hooks.pages)
      if (table == 'notes') ...rows,
  ].length;

  Future<String> bodyOn(SyncDevice device, String id) =>
      device.db.contentChunkDao.loadContent(id);

  /// A chunk document for [text], as a device pushing it would write it.
  SyncEnvelope chunkDocument(String text, String hlc) {
    final hash = ChunkHasher.hash(text);
    return SyncEnvelope(
      table: 'content_chunks',
      rowKey: hash,
      hlc: hlc,
      deviceId: 'A',
      version: 1,
      op: OutboxOp.upsert,
      ownerId: syncUid,
      data: {
        ContentChunksBinding.hashKey: hash,
        ContentChunksBinding.gzKey: Uint8List.fromList(
          gzip.encode(utf8.encode(text)),
        ),
        ContentChunksBinding.lengthKey: text.length,
      },
    );
  }

  SyncEnvelope withData(SyncEnvelope envelope, Map<String, Object?> data) =>
      SyncEnvelope(
        table: envelope.table,
        rowKey: envelope.rowKey,
        hlc: envelope.hlc,
        deviceId: envelope.deviceId,
        version: envelope.version,
        op: envelope.op,
        ownerId: envelope.ownerId,
        data: data,
      );

  test(
    'a one-character edit near the top of a 300 KB note reaches B as at '
    'most two chunk documents and one manifest, and B\'s body is A\'s',
    () async {
      final folder = await a().db.folderDao.createFolder(name: 'Log');
      final body = bigBody(300 * 1000);
      final note = await writeNote(
        a(),
        folderId: folder.id,
        title: 'Training log',
        body: body,
      );
      await a().sync();
      await b().sync();
      expect(await bodyOn(b(), note.id), body);
      final edited = editNearTop(body);
      await editNote(a(), note.id, edited);
      await a().sync();
      final from = pair.gateway.rowReads.length;
      b().hooks.clear();

      final report = await b().sync();

      expect(report.failure, isNull);
      expect(report.parked, 0);
      final fetched = [for (final keys in chunkReads(from: from)) ...keys];
      expect(fetched.length, inInclusiveRange(1, 2));
      expect(notesApplied(b()), 1);
      expect(await bodyOn(b(), note.id), edited);
      final manifest = pair.gateway.rowsOf(pair.space, 'notes')[note.id]!;
      final chunks = pair.gateway.rowsOf(pair.space, 'content_chunks');
      expect(
        FakeSyncGateway.bytesOf([
          manifest,
          for (final h in fetched) chunks[h]!,
        ]),
        lessThanOrEqualTo(20 * 1024),
      );
    },
  );

  test(
    'a rename reaches B as one document under 4 KB and reads no chunk',
    () async {
      final folder = await a().db.folderDao.createFolder(name: 'Log');
      final note = await writeNote(
        a(),
        folderId: folder.id,
        title: 'Training log',
        body: bigBody(300 * 1000),
      );
      await a().sync();
      await b().sync();
      await a().db.noteDao.updateNote(id: note.id, title: 'Season log');
      await a().sync();
      final from = pair.gateway.rowReads.length;
      b().hooks.clear();

      await b().sync();

      expect(chunkReads(from: from), isEmpty);
      expect(notesApplied(b()), 1);
      expect((await b().db.noteDao.getNoteById(note.id))!.title, 'Season log');
      final manifest = pair.gateway.rowsOf(pair.space, 'notes')[note.id]!;
      expect(manifest.wireBytes, lessThan(4 * 1024));
    },
  );

  test('a 5 MB note crosses in several parts with its manifest last, and B '
      'reads its chunks thirty at most a call and assembles it', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Journal');
    // About 5 MB of text gzip cannot shrink: more than one part.
    final body = noiseBody(2500000, seed: 1);
    final note = await writeNote(
      a(),
      folderId: folder.id,
      title: 'Ten years',
      body: body,
    );

    final (pushed, _) = await a().syncFiringSpacing();

    expect(pushed.failure, isNull);
    final manifest = pair.gateway.rowsOf(pair.space, 'notes')[note.id]!;
    final named = (manifest.data![NotesBinding.chunksKey]! as List)
        .cast<String>();
    int partOf(String key) =>
        pair.gateway.pushes.indexWhere((b) => b.any((e) => e.rowKey == key));
    final spanned = {for (final hash in named) partOf(hash)};
    expect(spanned.length, greaterThan(1));
    expect(partOf(note.id), spanned.reduce((x, y) => x > y ? x : y));

    final report = await b().sync();

    expect(report.failure, isNull);
    expect(report.parked, 0);
    final reads = chunkReads();
    expect(reads.length, greaterThan(1));
    for (final keys in reads) {
      expect(keys.length, lessThanOrEqualTo(SyncGateway.rowReadBatch));
    }
    expect({for (final keys in reads) ...keys}, named.toSet());
    expect(await bodyOn(b(), note.id), body);
  });

  test('a chunk two notes of a page share is read once, and the chunks a '
      'pull read queue nothing', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Log');
    final one = await writeNote(
      a(),
      folderId: folder.id,
      title: 'Monday',
      body: 'Squat 5x5',
    );
    final two = await writeNote(
      a(),
      folderId: folder.id,
      title: 'Thursday',
      body: 'Squat 5x5',
    );
    await a().sync();

    await b().sync();

    expect(chunkReads(), [
      [ChunkHasher.hash('Squat 5x5')],
    ]);
    expect(await bodyOn(b(), one.id), 'Squat 5x5');
    expect(await bodyOn(b(), two.id), 'Squat 5x5');
    expect(await b().db.syncOutboxDao.count(), 0);
  });

  test('a document an older build wrote, its body whole, merges and queues '
      'the chunks it is stored as, which the same run pushes', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Log');
    await a().sync();
    await b().sync();
    // Written on A and never pushed: the space holds none of its chunks.
    final note = await writeNote(
      a(),
      folderId: folder.id,
      title: 'Old build',
      body: bigBody(40 * 1000),
    );
    final manifest = await const NotesBinding().encode(
      a().db,
      note,
      boundUid: syncUid,
    );
    final body = await bodyOn(a(), note.id);
    pair.gateway.plant(
      pair.space,
      withData(
        manifest,
        {...manifest.data!}
          ..remove(NotesBinding.chunksKey)
          ..remove(NotesBinding.bodyHashKey)
          ..[JsonKeys.content] = body,
      ),
    );
    pair.gateway.pushes.clear();

    final report = await b().sync();

    expect(report.failure, isNull);
    expect(await bodyOn(b(), note.id), body);
    final hashes = await b().db.contentChunkDao.hashesOf(note.id);
    expect(hashes, isNot(contains(null)));
    final sent = [for (final batch in pair.gateway.pushes) ...batch];
    expect({
      for (final envelope in sent)
        if (envelope.table == 'content_chunks') envelope.rowKey,
    }, hashes.toSet());
    expect(sent.where((e) => e.table == 'notes'), isEmpty);
    expect(chunkReads(), isEmpty);
    expect(await b().db.syncOutboxDao.count(), 0);
  });

  test('a manifest naming a chunk the space does not hold parks with the '
      'count in its reason, the page\'s other notes merge, and the park is '
      'retried at the next start until the chunk lands', () async {
    final logs = <String>[];
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    addTearDown(() => debugPrint = print);
    final folder = await a().db.folderDao.createFolder(name: 'Log');
    final kept = await writeNote(
      a(),
      folderId: folder.id,
      title: 'Kept',
      body: 'Bench 3x8',
    );
    final lost = await writeNote(
      a(),
      folderId: folder.id,
      title: 'Lost',
      body: 'Row 4x10',
    );
    await a().sync();
    // The space's version of `lost` names a chunk it was never sent.
    const missing = 'Deadlift 1x5';
    final pushed = pair.gateway.rowsOf(pair.space, 'notes')[lost.id]!;
    pair.gateway.plant(
      pair.space,
      withData(pushed, {
        ...pushed.data!,
        NotesBinding.chunksKey: [ChunkHasher.hash(missing)],
        NotesBinding.bodyHashKey: ChunkHasher.hash(missing),
      }),
    );

    final report = await b().sync();

    expect(report.failure, isNull);
    expect(report.parked, 1);
    expect(await bodyOn(b(), kept.id), 'Bench 3x8');
    expect(await b().db.noteDao.getNoteById(lost.id), isNull);
    expect(logs.where((line) => line.contains('parked notes/${lost.id}')), [
      contains(
        '1 of 1 chunks are neither on this device nor readable in the '
        'space',
      ),
    ]);
    expect(
      await b().db.syncDao.getValue(SyncDao.keyPullParked('notes', lost.id)),
      endsWith('|${pushed.hlc}|awaitingText'),
    );

    await b().engine.stop();
    await b().engine.start();
    await b().settle();

    expect(b().engine.current.parkedCount, 1, reason: 'still missing');

    pair.gateway.plant(pair.space, chunkDocument(missing, pushed.hlc));
    await b().engine.stop();
    await b().engine.start();
    await b().settle();

    expect(b().engine.current.parkedCount, 0);
    expect(await bodyOn(b(), lost.id), missing);
    expect(
      await b().db.syncDao.getValue(SyncDao.keyPullParked('notes', lost.id)),
      isNull,
    );
    expect(await b().db.syncOutboxDao.count(), 0);
  });

  test('a chunk document that does not hold its hash\'s text parks the note '
      'naming it', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Log');
    final note = await writeNote(
      a(),
      folderId: folder.id,
      title: 'Log',
      body: 'Press 5x5',
    );
    await a().sync();
    final hash = ChunkHasher.hash('Press 5x5');
    // Another text of the same length under the hash: it inflates, and
    // only the hash check refuses it.
    final forged = chunkDocument('Press 5x6', 'any');
    pair.gateway.plant(
      pair.space,
      SyncEnvelope(
        table: forged.table,
        rowKey: hash,
        hlc: forged.hlc,
        deviceId: forged.deviceId,
        version: forged.version,
        op: forged.op,
        ownerId: forged.ownerId,
        data: {...forged.data!, ContentChunksBinding.hashKey: hash},
      ),
    );

    final report = await b().sync();

    expect(report.failure, isNull);
    expect(report.parked, 1);
    expect(await b().db.noteDao.getNoteById(note.id), isNull);
  });

  test('a chunk read that times out fails the run, parks nothing and leaves '
      'the page size alone', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Log');
    final note = await writeNote(
      a(),
      folderId: folder.id,
      title: 'Log',
      body: 'Lunges 3x12',
    );
    await a().sync();
    pair.gateway.onPullPage = (table) async {
      if (table != 'notes') return;
      pair.gateway.onPullPage = null;
      pair.gateway.failNextWithException(const SyncGatewayException.timedOut());
    };

    final failed = await b().sync();

    expect(failed.failure, isNotNull);
    expect(failed.parked, 0);
    expect(b().engine.current.parkedCount, 0);
    expect(await b().db.noteDao.getNoteById(note.id), isNull);
    expect(chunkReads(), isEmpty);

    pair.gateway.pullTakes.clear();
    final report = await b().sync();

    expect(report.failure, isNull);
    expect(pair.gateway.pullTakes, contains('notes:${NotesBinding.pageLimit}'));
    expect(await bodyOn(b(), note.id), 'Lunges 3x12');
  });

  group('under the bind floor', () {
    test('this device\'s own older manifest, after an edit it never pushed '
        'and a Stop syncing, wins with its body, never an empty one', () async {
      final folder = await b().db.folderDao.createFolder(name: 'Log');
      final body = bigBody(30 * 1000);
      final note = await writeNote(
        b(),
        folderId: folder.id,
        title: 'Log',
        body: body,
      );
      await b().sync();
      await editNote(b(), note.id, 'Written offline, never pushed');
      await b().binding.unbind();
      await pair.bind(b());

      final report = await b().sync();

      expect(report.failure, isNull);
      expect(report.parked, 0);
      expect(await bodyOn(b(), note.id), body);
    });

    test('one whose chunks are nowhere parks and leaves the local body as it '
        'was', () async {
      final db = b().db;
      const text = 'the newer local text the space never got';
      final local = await db.noteDao.createNote(
        folderId: 'f1',
        title: 'N',
        content: text,
      );
      final mine = await const NotesBinding().encode(
        db,
        local,
        boundUid: syncUid,
      );
      final older = SyncEnvelope(
        table: mine.table,
        rowKey: mine.rowKey,
        hlc: '000000000001:0000:${db.deviceId}',
        deviceId: db.deviceId,
        version: 1,
        op: mine.op,
        ownerId: syncUid,
        data: {
          ...mine.data!,
          NotesBinding.chunksKey: [ChunkHasher.hash('lost')],
          NotesBinding.bodyHashKey: ChunkHasher.hash('lost'),
        },
      );

      await expectLater(
        db.transaction(
          () => const NotesBinding().mergeRemote(
            db,
            older,
            floor: local.hlcTimestamp,
          ),
        ),
        throwsFormatException,
      );
      expect(await bodyOn(b(), local.id), text);
    });
  });

  test(
    'a chunk replaced on this device between the page\'s reads and its '
    'merge fails the page, parks nothing, and the next run merges it',
    () async {
      final folder = await a().db.folderDao.createFolder(name: 'Log');
      await a().sync();
      await b().sync();
      // B holds the text in a note of its own, so the page does not read it.
      final own = await writeNote(
        b(),
        folderId: folder.id,
        title: 'Own',
        body: 'Squat 5x5',
      );
      final note = await writeNote(
        a(),
        folderId: folder.id,
        title: 'Theirs',
        body: 'Squat 5x5',
      );
      await a().sync();
      b().hooks.onBeforePage = (table) async {
        if (table != 'notes') return;
        b().hooks.onBeforePage = null;
        await editNote(b(), own.id, 'Bench 3x8');
      };

      final failed = await b().sync();

      expect(failed.failure, isNotNull);
      expect(failed.parked, 0);
      expect(b().engine.current.parkedCount, 0);
      expect(await b().db.noteDao.getNoteById(note.id), isNull);

      final report = await b().sync();

      expect(report.failure, isNull);
      expect(report.parked, 0);
      expect(await bodyOn(b(), note.id), 'Squat 5x5');
    },
  );

  for (final size in [100, 20000]) {
    test('a body of $size code units with a lone surrogate syncs, and B '
        'holds the text A stored', () async {
      final folder = await a().db.folderDao.createFolder(name: 'Log');
      final note = await writeNote(
        a(),
        folderId: folder.id,
        title: 'Log',
        body: '${'a' * size}\uD83D tail',
      );

      final pushed = await a().sync();
      final pulled = await b().sync();

      expect(pushed.parked, 0);
      expect(pulled.parked, 0);
      final stored = await bodyOn(a(), note.id);
      expect(stored, '${'a' * size}� tail');
      expect(await bodyOn(b(), note.id), stored);
      expect(await a().db.syncOutboxDao.count(), 0);
    });
  }

  test('a page whose missing chunks outgrow the fetch budget is halved and '
      'pulled again from the same cursor until it fits, and the page after '
      'it is pulled at the table\'s own size again', () async {
    final folder = await a().db.folderDao.createFolder(name: 'Years');
    final notes = [
      for (var i = 0; i < 4; i++)
        await writeNote(
          a(),
          folderId: folder.id,
          title: 'Year $i',
          // Compressible, and no chunk shared between the notes.
          body: bigBody(3000000).replaceAll('Week', 'Year $i, week'),
        ),
    ];
    final chunkCounts = [
      for (final note in notes)
        (await a().db.contentChunkDao.hashesOf(note.id)).toSet().length,
    ];
    const most = SyncEngine.chunkFetchBudget ~/ ContentChunker.maxCodeUnits;
    expect(chunkCounts.reduce((x, y) => x + y), greaterThan(most));
    expect(chunkCounts[0] + chunkCounts[1], lessThanOrEqualTo(most));
    expect(chunkCounts[2] + chunkCounts[3], lessThanOrEqualTo(most));
    final (pushed, _) = await a().syncFiringSpacing();
    expect(pushed.failure, isNull);
    pair.gateway.pullTakes.clear();

    final report = await b().sync();

    expect(report.failure, isNull);
    expect(report.parked, 0);
    expect(
      [
        for (final take in pair.gateway.pullTakes)
          if (take.startsWith('notes:')) take,
      ],
      [
        'notes:${NotesBinding.pageLimit}',
        'notes:2',
        'notes:${NotesBinding.pageLimit}',
      ],
    );
    for (final note in notes) {
      expect(await bodyOn(b(), note.id), await bodyOn(a(), note.id));
    }
  }, timeout: const Timeout(Duration(minutes: 3)));

  group('the wire cutover', () {
    test(
      're-reads every note: a manifest an older build passed by lands',
      () async {
        final folder = await a().db.folderDao.createFolder(name: 'Log');
        final skipped = await writeNote(
          a(),
          folderId: folder.id,
          title: 'Skipped',
          body: 'Deadlift 1x5',
        );
        await a().sync();
        await b().sync();
        pair.gateway.elapse(const Duration(hours: 1));
        await writeNote(a(), folderId: folder.id, title: 'Later', body: 'Row');
        await a().sync();
        await b().sync();
        // B as the older build left it: its cursor past a manifest it never
        // merged, its wire one below this build's.
        await b().db.customStatement(
          'DELETE FROM content_chunks WHERE note_id = ?',
          [skipped.id],
        );
        await b().db.customStatement('DELETE FROM notes WHERE id = ?', [
          skipped.id,
        ]);
        await b().db.syncDao.setValue(
          SyncDao.keyWireVersion,
          '${syncSchema - 1}',
        );

        final report = await b().sync();

        expect(report.failure, isNull);
        expect(await bodyOn(b(), skipped.id), 'Deadlift 1x5');
        expect(
          await b().db.syncDao.getValue(SyncDao.keyWireVersion),
          '$syncSchema',
        );
      },
    );

    test('is done only once its re-read reached the end: a drain-only run '
        'before then pushes no note, the next full run completes it', () async {
      final folder = await a().db.folderDao.createFolder(name: 'Log');
      await writeNote(a(), folderId: folder.id, title: 'Log', body: 'Row');
      await a().engine.start();
      await a().settle();
      await a().db.syncDao.setValue(
        SyncDao.keyWireVersion,
        '${syncSchema - 1}',
      );
      pair.gateway.onPullPage = (table) async {
        if (table != 'notes') return;
        pair.gateway.onPullPage = null;
        throw const SyncGatewayException(SyncGatewayFailure.offline);
      };

      final failed = await a().sync();

      expect(failed.failure, isNotNull);
      expect(
        await a().db.syncDao.getValue(SyncDao.keyWireVersion),
        '${syncSchema - 1}',
      );
      pair.gateway.pushes.clear();

      await a().engine.onAppBackgrounded();

      expect([
        for (final batch in pair.gateway.pushes)
          for (final envelope in batch)
            if (envelope.table == 'notes') envelope.rowKey,
      ], isEmpty);

      a().engine.onAppResumed();
      await a().settle();
      final report = await a().sync();

      expect(report.failure, isNull);
      expect(
        await a().db.syncDao.getValue(SyncDao.keyWireVersion),
        '$syncSchema',
      );
      expect(await a().db.syncOutboxDao.count(), 0);
    });

    test('uploads each chunk once per space: the second device, pulling the '
        'first one\'s manifests, pushes no chunk and no note', () async {
      final folder = await a().db.folderDao.createFolder(name: 'Log');
      final notes = [
        for (var i = 0; i < 3; i++)
          await writeNote(
            a(),
            folderId: folder.id,
            title: 'Note $i',
            body: bigBody(30 * 1000).replaceAll('Week', 'Note $i, week'),
          ),
      ];
      await a().sync();
      await b().sync();
      // The space as the build before the cutover left it: every note's
      // body whole in its document, at the stamp both devices hold.
      for (final note in notes) {
        final manifest = pair.gateway.rowsOf(pair.space, 'notes')[note.id]!;
        pair.gateway.plant(
          pair.space,
          withData(
            manifest,
            {...manifest.data!}
              ..remove(NotesBinding.chunksKey)
              ..remove(NotesBinding.bodyHashKey)
              ..[JsonKeys.content] = await bodyOn(a(), note.id),
          ),
        );
      }
      for (final device in [a(), b()]) {
        await device.db.syncDao.setValue(
          SyncDao.keyWireVersion,
          '${syncSchema - 1}',
        );
      }

      final first = await a().sync();
      pair.gateway.pushes.clear();
      final second = await b().sync();

      expect(first.failure, isNull);
      expect(first.pushedRows, greaterThan(notes.length));
      for (final note in notes) {
        expect(
          pair.gateway.rowsOf(pair.space, 'notes')[note.id]!.data,
          contains(NotesBinding.chunksKey),
        );
      }
      expect(second.failure, isNull);
      expect(second.pushedRows, 0);
      expect(pair.gateway.pushes, isEmpty);
      expect(await b().db.syncOutboxDao.count(), 0);
    });
  });
}
