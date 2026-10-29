import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/crdt_merge.dart';
import 'package:anta/database/crdt/hlc.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';

import 'support/db_test_support.dart';
import 'support/merge_contract.dart';

/// Guards `FolderDao.mergeFolder`, the remote merge a pull applies to every
/// folder row: the shared contract, plus what is particular to folders.
void main() {
  late AppDatabase db;
  late StatementCounter statements;

  setUp(() async {
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
  });
  tearDown(() async => db.close());

  Folder remote(String id, String hlc, {bool deleted = false}) {
    return Folder(
      id: id,
      name: 'Pulled',
      parentId: 'parent',
      position: 4,
      label: 2,
      createdAt: DateTime.utc(2026, 1, 2).toLocal(),
      updatedAt: DateTime.utc(2026, 1, 3).toLocal(),
      noteSortOrder: 'titleAsc',
      subfolderSortOrder: 'nameDesc',
      hlcTimestamp: hlc,
      deviceId: 'remote',
      version: 7,
      isDeleted: deleted,
      deletedAt: deleted ? DateTime.utc(2026, 1, 4).toLocal() : null,
      ownerId: 'uid-1',
    );
  }

  runMergeContract(
    MergeContract<Folder>(
      table: 'folders',
      freshKey: 'pulled',
      seedLocal: (db) async =>
          (await db.folderDao.createFolder(name: 'Training')).id,
      remote: remote,
      merge: (db, row, {floor}) => db.folderDao.mergeFolder(row, floor: floor),
      markerColumn: 'name',
      markerValue: 'Pulled',
    ),
    db: () => db,
    statements: () => statements,
  );

  test('a newer remote overwrites every data column', () async {
    final local = await db.folderDao.createFolder(name: 'Training');

    await db.folderDao.mergeFolder(remote(local.id, newerHlc));

    final row = (await db.folderDao.getFolderById(local.id))!;
    final expected = remote(local.id, newerHlc);
    expect(row.name, expected.name);
    expect(row.parentId, expected.parentId);
    expect(row.position, expected.position);
    expect(row.label, expected.label);
    expect(row.noteSortOrder, expected.noteSortOrder);
    expect(row.subfolderSortOrder, expected.subfolderSortOrder);
    expect(row.createdAt, expected.createdAt);
    expect(row.updatedAt, expected.updatedAt);
    expect(row.version, 7);
  });

  test('the push load reads tombstones, 500 keys per statement', () async {
    await db.batch((b) {
      b.insertAll(db.folders, [
        for (var i = 0; i < 1201; i++)
          remote('f$i', newerHlc, deleted: i == 1200),
      ]);
    });
    statements.reset();

    final rows = await db.folderDao.getByIdsIncludingDeleted([
      for (var i = 0; i < 1201; i++) 'f$i',
      'missing',
    ]);

    expect(rows, hasLength(1201));
    expect(rows.where((f) => f.isDeleted).single.id, 'f1200');
    expect(statements.selects, hasLength(3));
  });

  test('a tombstone keeps the data columns and cascades nothing', () async {
    final local = await db.folderDao.createFolder(name: 'Training');
    final child = await db.folderDao.createFolder(
      name: 'Legs',
      parentId: local.id,
    );

    await db.folderDao.mergeFolder(remote(local.id, newerHlc, deleted: true));

    final row = (await db.folderDao.getFolderById(local.id))!;
    expect(row.isDeleted, isTrue);
    expect(row.name, 'Training');
    expect((await db.folderDao.getFolderById(child.id))!.isDeleted, isFalse);
  });

  test('a merged tombstone dates updated_at at the delete', () async {
    final local = await db.folderDao.createFolder(name: 'Training');
    final tombstone = remote(local.id, newerHlc, deleted: true);

    await db.folderDao.mergeFolder(tombstone);

    // The deleting device stored the delete time; before this the merging
    // one kept the last edit's and the two never converged (A7 R67).
    expect((await db.folderDao.getFolderById(local.id))!.updatedAt,
        tombstone.deletedAt);
  });

  group('the parent a merge leaves behind', () {
    Folder under(String id, String? parentId, String hlc) =>
        remote(id, hlc).copyWith(parentId: Value(parentId));

    /// The queued stamp per folder row key.
    Future<Map<String, String>> queuedFolders() async => {
      for (final entry in await db.syncOutboxDao.pendingForTable('folders'))
        entry.rowKey: entry.hlc,
    };

    /// Ten minutes ahead of the test clock: above anything it has minted and
    /// inside the HLC's drift guard, so a repair that raised the clock to
    /// the move it repairs is told apart from one minted below it.
    final movedHlc = HlcTimestamp(
      wallTime: DateTime.now()
          .add(const Duration(minutes: 10))
          .millisecondsSinceEpoch,
      logicalCounter: 3,
      nodeId: 'remote',
    ).toString();

    /// Two days ahead of the test clock: past [HybridLogicalClock.maxDrift],
    /// so a raise that keeps the drift guard is told apart from one that
    /// follows the stamp.
    final farHlc = HlcTimestamp(
      wallTime: DateTime.now()
          .add(const Duration(days: 2))
          .millisecondsSinceEpoch,
      logicalCounter: 3,
      nodeId: 'remote',
    ).toString();

    /// The repaired row carries a stamp of this device's own and the queue
    /// holds that stamp, so the space converges on the break rather than
    /// pushing the parent back.
    ///
    /// Above [movedUnder], not merely different from it: a repair stamped
    /// below the move it repairs is denied by the space, the same remote
    /// parent re-applies on the next pull and the queue is re-armed every
    /// run (A7 review R131, R143).
    Future<void> expectRepairQueued(String id, String movedUnder) async {
      final row = (await db.folderDao.getFolderById(id))!;
      expect(row.hlcTimestamp.compareTo(movedUnder), greaterThan(0));
      expect((await queuedFolders())[id], row.hlcTimestamp);
    }

    test('a remote move that closes a cycle is cut to the root', () async {
      final x = await db.folderDao.createFolder(name: 'X');
      final y = await db.folderDao.createFolder(name: 'Y');

      // Each device moved one under the other and each passed its own local
      // descendant check; without the repair both folders and everything
      // under them leave the browser for good (A7 R63).
      await db.folderDao.mergeFolder(under(x.id, y.id, movedHlc));
      await db.folderDao.mergeFolder(under(y.id, x.id, movedHlc));

      expect((await db.folderDao.getFolderById(y.id))!.parentId, isNull);
      expect((await db.folderDao.getFolderById(x.id))!.parentId, y.id);
      expect(
        [for (final f in await db.folderDao.getFoldersByParent(null)) f.id],
        contains(y.id),
      );
      await expectRepairQueued(y.id, movedHlc);
    });

    test('a live row under a tombstoned parent takes the nearest live '
        'ancestor', () async {
      final root = await db.folderDao.createFolder(name: 'Root');
      final parent = await db.folderDao.createFolder(
        name: 'Parent',
        parentId: root.id,
      );
      await db.folderDao.softDeleteFolder(parent.id);

      await db.folderDao.mergeFolder(under('pulled', parent.id, movedHlc));

      // Nothing shows a live folder under a deleted one, and the merge
      // never cascades (A7 R64).
      expect((await db.folderDao.getFolderById('pulled'))!.parentId, root.id);
      await expectRepairQueued('pulled', movedHlc);
    });

    test('the repair stands back while the bind\'s initial merge is pending '
        '(A7 review R130)', () async {
      final parent = await db.folderDao.createFolder(name: 'Parent');
      await db.folderDao.softDeleteFolder(parent.id);
      await db.syncDao.setValue(SyncDao.keyBindMergePending, '1');

      await db.folderDao.mergeFolder(under('pulled', parent.id, movedHlc));

      // The parent's live envelope is still to arrive in the same pull: the
      // local rows are pre-bind, so re-parenting now would flatten the
      // subtree and push that move into the space.
      expect((await db.folderDao.getFolderById('pulled'))!.parentId, parent.id);
      expect(await queuedFolders(), isNot(contains('pulled')));
    });

    test('the repair keeps the drift guard the page advance gives up '
        '(A10 review R157)', () async {
      final parent = await db.folderDao.createFolder(name: 'Parent');
      await db.folderDao.softDeleteFolder(parent.id);

      await db.folderDao.mergeFolder(under('pulled', parent.id, farHlc));

      // The repair raises inside the puller's page transaction, which can
      // still roll back with nothing stored and no stamp behind it, so a
      // clock left days ahead of everything committed would out-stamp
      // remote rows this device never merged (R65).
      final limit = DateTime.now().add(HybridLogicalClock.maxDrift);
      expect((await db.folderDao.getFolderById('pulled'))!.parentId, isNull);
      expect(
        db.hlc.last.wallTime,
        lessThanOrEqualTo(limit.millisecondsSinceEpoch),
      );

      CrdtMerge.advanceClock(db, farHlc);

      // The page advance is the caller that follows it: it runs once the
      // page committed the stamps onto rows of this database (A5 R98).
      expect(db.hlc.last.wallTime, HlcTimestamp.parse(farHlc).wallTime);
    });

    test('a live row whose ancestors are all tombstoned goes to the root',
        () async {
      final parent = await db.folderDao.createFolder(name: 'Parent');
      await db.folderDao.softDeleteFolder(parent.id);

      await db.folderDao.mergeFolder(under('pulled', parent.id, newerHlc));

      expect((await db.folderDao.getFolderById('pulled'))!.parentId, isNull);
    });

    test('a parent this device has not received is kept', () async {
      await db.folderDao.mergeFolder(under('pulled', 'not-here', newerHlc));

      expect(
        (await db.folderDao.getFolderById('pulled'))!.parentId,
        'not-here',
      );
      expect(await queuedFolders(), isNot(contains('pulled')));
    });

    test('a live parent is left alone', () async {
      final parent = await db.folderDao.createFolder(name: 'Parent');

      await db.folderDao.mergeFolder(under('pulled', parent.id, newerHlc));

      expect((await db.folderDao.getFolderById('pulled'))!.parentId, parent.id);
      expect(await queuedFolders(), isNot(contains('pulled')));
    });
  });
}
