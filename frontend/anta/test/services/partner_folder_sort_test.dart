import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/json_keys.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/item_label.dart';
import 'package:anta/models/partner_folder_sort.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/tables/folders_binding.dart';

import '../database/support/db_test_support.dart';

/// My sort of a partner's folder (`docs/cloud-share-surfaces-roadmap.md`
/// §6.12, "Sort preferences are mine and keep working"): the folder's own
/// columns are the partner's row, which the database never writes, so the
/// sort lives in a store of my own, laid over the folder as it is mapped and
/// dropped with the folder when its share ends.
void main() {
  const partner = 'partner';

  late StatementCounter statements;
  late AppDatabase db;
  late FolderStorageService folders;

  setUp(() async {
    statements = StatementCounter();
    db = await openTestDatabase(interceptor: statements);
    folders = FolderStorageService(repository: FolderRepository(database: db));
  });
  tearDown(() async => db.close());

  /// The partner's folder [id] as the shared reader stores it, under [hlc],
  /// with the partner's own sort columns.
  Future<void> received(
    String id, {
    String hlc = '000000000001:0000:P',
    String name = 'Recipes',
    String? notes = 'titleAsc',
    String? subfolders = 'createdDesc',
  }) async {
    await db.syncDao.setValue(SyncDao.keySharedOwner, partner);
    await db.sharedRowDao.writing(
      () => const FoldersBinding().mergeShared(
        db,
        SyncEnvelope(
          table: 'folders',
          rowKey: id,
          hlc: hlc,
          deviceId: 'P',
          version: 1,
          op: OutboxOp.upsert,
          ownerId: partner,
          data: {
            JsonKeys.id: id,
            JsonKeys.name: name,
            JsonKeys.parentId: null,
            'position': 0,
            JsonKeys.label: ItemLabel.none.storageName,
            'createdAtMs': 0,
            'updatedAtMs': 0,
            JsonKeys.noteSortOrder: notes,
            JsonKeys.subfolderSortOrder: subfolders,
          },
        ),
      ),
    );
    folders.invalidateCache();
  }

  Future<Map<String, PartnerFolderSort>> stored() =>
      SettingsService.partnerFolderSortsOf(db);

  FolderStorageService fresh() =>
      FolderStorageService(repository: FolderRepository(database: db));

  test('a sort set on the partner\'s folder is mine: answered, stored, and '
      'read back by a fresh load — the partner\'s row untouched', () async {
    await received('theirs');
    await db.syncOutboxDao.clear();

    final answered = await folders.updateFolderSortPreferences(
      folderId: 'theirs',
      noteSortOrder: 'updatedAsc',
    );

    expect(answered!.noteSortOrder, 'updatedAsc');
    expect(
      answered.subfolderSortOrder,
      'createdDesc',
      reason: 'the column not set keeps what the folder showed',
    );
    expect(await stored(), {
      'theirs': const PartnerFolderSort(
        noteSortOrder: 'updatedAsc',
        subfolderSortOrder: 'createdDesc',
      ),
    });

    final reloaded = (await fresh().getFolderById('theirs'))!;
    expect(reloaded.noteSortOrder, 'updatedAsc');
    expect(reloaded.subfolderSortOrder, 'createdDesc');
    final root = await fresh().loadPartnerTopFolders();
    expect(root.single.noteSortOrder, 'updatedAsc');

    final row = (await db.folderDao.getByIdsIncludingDeleted([
      'theirs',
    ])).single;
    expect(row.noteSortOrder, 'titleAsc', reason: 'the partner\'s row');
    expect(await db.syncOutboxDao.count(), 0, reason: 'nothing is pushed');

    final cleared = await folders.updateFolderSortPreferences(
      folderId: 'theirs',
      subfolderSortOrder: 'nameDesc',
      clearNoteSortOrder: true,
    );
    expect(cleared!.noteSortOrder, isNull);
    expect(cleared.subfolderSortOrder, 'nameDesc');
  });

  test('survives the partner\'s folder read again by a sync run, the '
      'partner\'s new sort included', () async {
    await received('theirs');
    await folders.updateFolderSortPreferences(
      folderId: 'theirs',
      subfolderSortOrder: 'nameDesc',
    );

    await received(
      'theirs',
      hlc: 'ffffffffffff:0000:P',
      name: 'Recipes 2026',
      notes: 'titleDesc',
      subfolders: 'positionAsc',
    );

    final folder = (await fresh().getFolderById('theirs'))!;
    expect(folder.name, 'Recipes 2026', reason: 'the read landed');
    expect(folder.subfolderSortOrder, 'nameDesc');
    expect(folder.noteSortOrder, 'titleAsc', reason: 'as it stood when set');
  });

  test('pruned when the folder leaves — the reader\'s removal, an '
      'eviction, the unbind\'s removal of everything', () async {
    await received('one');
    await received('two');
    await received('three');
    for (final id in ['one', 'two', 'three']) {
      await folders.updateFolderSortPreferences(
        folderId: id,
        noteSortOrder: 'titleDesc',
      );
    }

    await db.sharedRowDao.removeAbsent('folders', partner, {'two', 'three'});
    expect((await stored()).keys, unorderedEquals(['two', 'three']));

    await db.sharedRowDao.evict('folders', ['two']);
    expect((await stored()).keys, ['three']);

    await db.sharedRowDao.removeAll();
    expect(await stored(), isEmpty);
    expect(
      await db.userSettingsDao.getValue(SettingsKeys.shareFolderSorts),
      isNull,
      reason: 'the row goes with the last sort',
    );
  });

  test('a folder of mine is written as always, and costs nothing: no store '
      'is read or written for it, paired or not', () async {
    final mine = (await db.folderDao.createFolder(name: 'Mine')).id;
    await folders.loadFoldersPaginated();
    statements.reset();

    final answered = await folders.updateFolderSortPreferences(
      folderId: mine,
      noteSortOrder: 'titleAsc',
    );
    await folders.loadFoldersPaginated();
    await folders.getFolderById(mine);

    expect(answered!.noteSortOrder, 'titleAsc');
    expect(
      (await db.folderDao.getByIdsIncludingDeleted([
        mine,
      ])).single.noteSortOrder,
      'titleAsc',
    );
    expect(statements.matching('user_settings'), isEmpty);
    expect(statements.matching('owner_id'), isEmpty);

    await received('theirs');
    statements.reset();
    await folders.updateFolderSortPreferences(
      folderId: mine,
      subfolderSortOrder: 'nameDesc',
    );
    await folders.loadAllFoldersForParent(mine);
    expect(
      statements.matching('user_settings'),
      isEmpty,
      reason: 'paired: still no store for a folder of mine',
    );
    expect(await stored(), isEmpty);
  });

  test('a stored value that cannot be read costs the sorts, never the '
      'load', () async {
    await received('theirs');
    await db.userSettingsDao.setValue(SettingsKeys.shareFolderSorts, '{nope');

    final folder = (await fresh().getFolderById('theirs'))!;

    expect(folder.noteSortOrder, 'titleAsc');
  });
}
