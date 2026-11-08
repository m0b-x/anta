import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_sync_gateway.dart';
import '../../support/scale_fixtures.dart';
import 'support/sync_pair.dart';

/// The bytes one auto-save of a one-character edit puts on the wire for a
/// 100,000-code-unit note, sized as the pusher sizes a part before it sends
/// it: `SyncEnvelope.wireBytes` over every document of the push.
///
/// A note travels as a manifest naming its chunks, each chunk a document of
/// its own (`docs/scalability-roadmap.md` §5.3 S6), so a one-letter change
/// sends the chunks it reached and the manifest — under 20 KB, where the
/// whole body went before (106,727 bytes for this edit, S3's pin).
void main() {
  late SyncPair pair;

  setUp(() async => pair = await SyncPair.open());
  tearDown(() async => pair.close());

  test('a one-character save of a 100,000-code-unit note sends the chunks it '
      'reached and the manifest, under 20 KB', () async {
    final body = bigBody(100000);
    final folder = await pair.a.db.folderDao.createFolder(name: 'Log');
    final note = await writeNote(
      pair.a,
      folderId: folder.id,
      title: 'Training log',
      body: body,
    );
    await pair.a.sync();
    final edited = editNearTop(body);
    await editNote(pair.a, note.id, edited);
    pair.gateway.pushes.clear();

    final report = await pair.a.sync();

    expect(report.failure, isNull);
    expect(report.parked, 0);
    final sent = [for (final batch in pair.gateway.pushes) ...batch];
    expect(
      [
        for (final envelope in sent)
          if (envelope.table == 'notes') envelope.rowKey,
      ],
      [note.id],
    );
    expect(sent.map((e) => e.table).toSet(), {'notes', 'content_chunks'});
    expect(FakeSyncGateway.bytesOf(sent), lessThanOrEqualTo(20 * 1024));
  });
}
