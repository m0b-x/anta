import 'package:flutter_test/flutter_test.dart';

import 'support/sync_pair.dart';

/// How a drain cuts the outbox into calls: one `pushBatch` per
/// `maxBatch` queued rows, the queue counted as the outbox holds it — a
/// bind's own seeded rows included — not as the test wrote it. S10
/// (`docs/scalability-roadmap.md` §5.4) recuts a batch by bytes; with rows
/// this small the count cut is the one that holds, and a change to it shows
/// here.
void main() {
  late SyncPair pair;

  setUp(() async => pair = await SyncPair.open());
  tearDown(() async => pair.close());

  test('ten folders at maxBatch 3 push in ceil(pending / 3) calls', () async {
    pair.gateway.maxBatch = 3;
    for (var i = 0; i < 10; i++) {
      await pair.a.db.folderDao.createFolder(name: 'Folder $i');
    }
    final pending = (await pair.a.db.syncOutboxDao.pending()).length;
    expect(pending, greaterThanOrEqualTo(10));
    pair.gateway.calls.clear();

    final report = await pair.a.sync();

    expect(report.pushedRows, pending);
    // Ten rows and four calls today.
    expect(
      pair.gateway.calls.where((c) => c == 'push:A'),
      hasLength((pending / 3).ceil()),
    );
    expect(await pair.a.db.syncOutboxDao.count(), 0);
  });
}
