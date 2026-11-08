import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/services/sync/tables/content_chunks_binding.dart';
import 'package:anta/services/sync/tables/notes_binding.dart';

import '../../support/scale_fixtures.dart';
import 'support/sync_pair.dart';

/// The limit a large note met before S6: a row whose JSON exceeded
/// [maxDocumentBytesToday] was parked before the push — never sent, counted
/// as one anonymous held-back row (`docs/scalability-roadmap.md` §2.1, the
/// "Over the cap" column).
///
/// S6 (§5.3) flipped it: the body travels as chunk documents of at most
/// 64 KB each and the note as a manifest naming them, so no note is too
/// large to cross.
void main() {
  late SyncPair pair;

  setUp(() async => pair = await SyncPair.open());
  tearDown(() async => pair.close());

  test('a note over 900,000 bytes crosses as its chunk documents and a '
      'manifest naming them, and nothing is held back', () async {
    final body = bigBody(maxDocumentBytesToday);
    expect(utf8.encode(body).length, greaterThan(maxDocumentBytesToday));
    final folder = await pair.a.db.folderDao.createFolder(name: 'Journal');
    final other = await pair.a.db.folderDao.createFolder(name: 'Training');
    final big = await writeNote(
      pair.a,
      folderId: folder.id,
      title: 'Ten years',
      body: body,
    );
    final small = await writeNote(
      pair.a,
      folderId: other.id,
      title: 'Monday',
      body: 'Squat 5x5',
    );

    final report = await pair.a.sync();

    expect(report.failure, isNull);
    expect(report.parked, 0);
    expect(pair.a.engine.current.parkedCount, 0);
    expect(await pair.a.db.syncOutboxDao.count(), 0);
    final notes = pair.gateway.rowsOf(pair.space, 'notes');
    expect(notes.keys.toSet(), {big.id, small.id});
    expect(pair.gateway.rowsOf(pair.space, 'folders').keys.toSet(), {
      folder.id,
      other.id,
    });
    final named = (notes[big.id]!.data![NotesBinding.chunksKey]! as List)
        .cast<String>();
    final chunks = pair.gateway.rowsOf(pair.space, 'content_chunks');
    expect(chunks.keys, containsAll(named));
    expect(
      named.map((hash) => ContentChunksBinding.textOf(chunks[hash]!)).join(),
      body,
      reason: 'the space alone holds the whole body',
    );
    for (final batch in pair.gateway.pushes) {
      for (final envelope in batch) {
        expect(
          envelope.wireBytes,
          lessThanOrEqualTo(ContentChunksBinding.maxGzBytes + 4096),
          reason: '${envelope.table}/${envelope.rowKey}',
        );
      }
    }
  });
}
