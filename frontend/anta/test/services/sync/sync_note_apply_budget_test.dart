import 'package:flutter_test/flutter_test.dart';

import '../../support/scale_fixtures.dart';
import 'support/sync_pair.dart';

/// What the receiving device writes to `content_chunks` when a one-character
/// save of a large note arrives, counted the way
/// `test/database/note_body_write_budget_test.dart` counts the writer's
/// save: exact statements of every kind, so a slice that changes how a body
/// is stored or carried (`docs/scalability-roadmap.md` §5.3 S6) shows its
/// cost here in its own diff.
///
/// A note still travels whole (D14). Before S4 (§5.2) the merge replaced
/// the body whole — one DELETE of every slice, then every slice inserted
/// again: 11 INSERTs at 100,000 code units, 31 at 300,000. Since S4 it runs
/// the writer's own plan over its stored chunks, so it writes only the
/// chunks the edit reached.
void main() {
  late SyncPair pair;

  setUp(() async => pair = await SyncPair.open());
  tearDown(() async => pair.close());

  for (final (size, updates, inserts, deletes) in [
    (100000, 0, 1, 1),
    (300000, 0, 1, 1),
  ]) {
    test('B applies a one-character save of a $size-code-unit body by '
        'replacing only the chunk it reached', () async {
      final body = bigBody(size);
      final folder = await pair.a.db.folderDao.createFolder(name: 'Log');
      final note = await writeNote(
        pair.a,
        folderId: folder.id,
        title: 'Training log',
        body: body,
      );
      await pair.a.sync();
      await pair.b.sync();
      final edited = editNearTop(body);
      await editNote(pair.a, note.id, edited);
      await pair.a.sync();
      pair.b.statements.reset();

      final report = await pair.b.sync();

      expect(report.pulledRows, 1);
      expect(await pair.b.db.contentChunkDao.loadContent(note.id), edited);
      final statements = pair.b.statements;
      expect(
        (
          updates: statements.executions('UPDATE "content_chunks"'),
          inserts: statements.executions('INSERT INTO "content_chunks"'),
          deletes: statements.executions('DELETE FROM "content_chunks"'),
        ),
        (updates: updates, inserts: inserts, deletes: deletes),
        reason: 'the stored chunks the edit did not reach are kept',
      );
      expect(updates + inserts + deletes, lessThanOrEqualTo(4));
    });
  }
}
