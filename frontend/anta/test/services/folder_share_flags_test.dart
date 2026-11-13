import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/daos/shared_row_dao.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/folder.dart' as model;
import 'package:anta/models/item_label.dart';
import 'package:anta/models/movable_item.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/services/folder_storage_service.dart';

import '../database/support/db_test_support.dart';

/// Whose a folder is and whether the person shares it, as the browser, the
/// picker and the breadcrumbs read it (`docs/cloud-share-surfaces-roadmap.md`
/// §6.11–§6.12): flagged where `FolderStorageService` maps its rows, from one
/// census per database — and the belt, which refuses a write of the
/// partner's folder by name where the fences would quietly do nothing.
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

  Future<String> folder(String name, {String? under}) async =>
      (await db.folderDao.createFolder(name: name, parentId: under)).id;

  /// Hands [ids] to the partner as the shared reader stores them: their
  /// owner first, then the key that arms the fences.
  Future<void> partners(List<String> ids) async {
    for (final id in ids) {
      await db.customStatement(
        "UPDATE folders SET owner_id = '$partner' WHERE id = ?",
        [id],
      );
    }
    await db.syncDao.setValue(SyncDao.keySharedOwner, partner);
  }

  model.Folder named(List<model.Folder> list, String name) =>
      list.singleWhere((folder) => folder.name == name);

  /// What a load asked of sharing: the census and the partner's rows. Never
  /// a statement per row.
  List<String> shareReads() => [
    for (final sql in statements.statements)
      if (sql.contains('shared_pair') || sql.contains('owner_id')) sql,
  ];

  group('a folder says', () {
    late String shelf;
    late String box;
    late String deep;
    late String plain;
    late String theirs;
    late String inner;

    setUp(() async {
      shelf = await folder('Shelf');
      box = await folder('Box', under: shelf);
      deep = await folder('Deep', under: box);
      plain = await folder('Plain');
      theirs = await folder('Theirs');
      inner = await folder('Inner', under: theirs);
      await db.folderDao.setSharedPair(shelf, 'pair-1');
      await partners([theirs, inner]);
    });

    test('whether it is the partner\'s, and how the person shares it — on '
        'every load the surfaces read', () async {
      final root = (await folders.loadFoldersPaginated()).folders;
      expect(named(root, 'Shelf').share, model.FolderShare.byMark);
      expect(named(root, 'Shelf').fromPartner, isFalse);
      expect(named(root, 'Plain').share, model.FolderShare.none);
      expect(
        root.where((folder) => folder.name == 'Theirs'),
        isEmpty,
        reason:
            'the root pages the person\'s own; the partner\'s are read '
            'whole for their group',
      );
      final group = await folders.loadPartnerTopFolders();
      expect(named(group, 'Theirs').fromPartner, isTrue);
      expect(named(group, 'Theirs').share, model.FolderShare.none);

      final underShelf = await folders.loadAllFoldersForParent(shelf);
      expect(named(underShelf, 'Box').share, model.FolderShare.through(shelf));

      final one = (await folders.getFolderById(deep))!;
      expect(one.share.isShared, isTrue);
      expect(one.share.isByMark, isFalse);
      expect(one.share.throughFolderId, shelf);

      final all = await folders.loadAllFolders();
      expect(named(all, 'Inner').fromPartner, isTrue);
      expect(named(all, 'Plain').fromPartner, isFalse);

      final crumbs = await folders.getAncestors(deep);
      expect(
        [for (final f in crumbs) f.share],
        [model.FolderShare.byMark, model.FolderShare.through(shelf)],
      );
      expect(plain, isNotEmpty);
    });

    test('shared through the outer folder when a merge left a mark under '
        'its mark: the outer one covers it', () async {
      // setSharedPair clears the marks under a folder, never one above it:
      // what a merge from another device can leave.
      await db.folderDao.setSharedPair(box, 'pair-1');
      folders.invalidateCache();

      final under = await folders.loadAllFoldersForParent(shelf);

      expect(named(under, 'Box').share, model.FolderShare.through(shelf));
      expect(
        (await folders.getFolderById(deep))!.share,
        model.FolderShare.through(shelf),
      );
    });

    test('nothing of this in its JSON: the flags are transient', () async {
      final shelfModel = (await folders.getFolderById(shelf))!;
      final theirsModel = (await folders.getFolderById(theirs))!;

      expect(shelfModel.toJson(), isNot(contains('share')));
      expect(theirsModel.toJson().keys, shelfModel.toJson().keys);
      expect(model.Folder.fromJson(theirsModel.toJson()).fromPartner, isFalse);
      expect(
        shelfModel,
        isNot(shelfModel.copyWith(share: model.FolderShare.none)),
        reason: 'in equality, so a list whose sharing changed redraws',
      );
    });

    test('a paired database pays one census read for a load, never one per '
        'row, and none while the census holds', () async {
      for (var i = 0; i < 30; i++) {
        await folder('Many $i', under: shelf);
      }
      folders.invalidateCache();
      statements.reset();

      await folders.loadFoldersPaginated(parentId: shelf, pageSize: 50);

      expect(shareReads(), hasLength(1), reason: 'the census, once');

      statements.reset();
      await folders.loadFoldersPaginated(parentId: box, pageSize: 50);
      await folders.getAncestors(deep);
      expect(shareReads(), isEmpty);

      // The root's own count and page leave the partner's folders out in
      // the statements they always were — nothing is asked beside them.
      statements.reset();
      await folders.loadFoldersPaginated(pageSize: 50);
      expect(statements.count, 2);
    });

    test('the partner\'s top-level folders: one read, whole whatever '
        'a page of mine holds', () async {
      for (var i = 0; i < 30; i++) {
        await folder('Mine $i');
      }
      folders.invalidateCache();
      await folders.loadFoldersPaginated(pageSize: 5);
      statements.reset();

      final group = await folders.loadPartnerTopFolders();

      expect([for (final f in group) f.name], ['Theirs']);
      expect(
        statements.count,
        2,
        reason: 'the folders, then my sorts of them (PartnerFolderSort)',
      );
    });
  });

  test(
    'a database that holds no shared row reads no partner\'s folders',
    () async {
      await folder('A');
      await folders.loadFoldersPaginated();
      statements.reset();

      expect(await folders.loadPartnerTopFolders(), isEmpty);
      expect(statements.count, 0);
    },
  );

  group('a database that holds no mark and no shared row', () {
    test('runs no statement for sharing on any load past the census it reads '
        'once — not after its own creates, moves, renames and deletes '
        'either', () async {
      final a = await folder('A');
      final b = await folder('B');
      await folders.loadFoldersPaginated();
      statements.reset();

      await folders.loadFoldersPaginated();
      await folders.loadAllFoldersForParent(a);
      await folders.loadAllFolders();
      await folders.getFolderById(b);
      await folders.getAncestors(b);
      expect(
        statements.matching('sync_metadata'),
        isEmpty,
        reason: 'a load asks nothing of whose a row is',
      );
      final c = await folders.createFolder(name: 'C', parentId: a);
      await folders.updateFolder(folderId: c.id, name: 'C2');
      await folders.moveFolders(folderIds: [c.id], targetParentId: b);
      await folders.moveFolder(folderId: c.id, targetParentId: a);
      await folders.setFolderLabel(c.id, ItemLabel.teal);
      await folders.deleteFolder(c.id);
      await folders.loadFoldersPaginated(parentId: a);

      expect(
        statements.matching('WITH RECURSIVE s(id, root'),
        isEmpty,
        reason: 'the census stays known: none of these can bring a mark',
      );
      expect(
        statements.matching('WHERE owner_id = ?'),
        isEmpty,
        reason:
            'no write asked the belt whether its folder is the partner\'s '
            '(the create\'s own check of its parent is the DAO\'s, as before)',
      );
    });
  });

  group('the belt: a write of the partner\'s folder', () {
    late String mine;
    late String theirs;

    setUp(() async {
      mine = await folder('Mine');
      theirs = await folder('Theirs');
      await partners([theirs]);
      await db.syncOutboxDao.clear();
    });

    Future<void> refused(Future<Object?> Function() write) async {
      await expectLater(write(), throwsA(isA<SharedRowException>()));
      expect(await db.syncOutboxDao.count(), 0, reason: 'nothing written');
    }

    test('is refused by name, never answered as done', () async {
      await refused(() => folders.updateFolder(folderId: theirs, name: 'X'));
      await refused(() => folders.setFolderLabel(theirs, ItemLabel.teal));
      await refused(
        () => folders.setLabelForFolders([mine, theirs], ItemLabel.teal),
      );
      await refused(() => folders.deleteFolder(theirs));
      await refused(() => folders.deleteFolders([mine, theirs]));
      await refused(
        () => folders.moveFolder(folderId: theirs, targetParentId: mine),
      );
      await refused(
        () => folders.moveFolders(folderIds: [theirs], targetParentId: mine),
      );

      final row = (await db.folderDao.getByIdsIncludingDeleted([
        theirs,
      ])).single;
      expect(row.name, 'Theirs');
      expect(row.isDeleted, isFalse);
      expect((await folders.getFolderById(mine))!.label, ItemLabel.none);
    });

    test('and so is filing one of mine into it — a move, a re-parent, a '
        'selection, a create', () async {
      await refused(
        () => folders.moveFolder(folderId: mine, targetParentId: theirs),
      );
      await refused(
        () => folders.updateFolder(folderId: mine, parentId: theirs),
      );
      await refused(
        () => folders.moveFolders(folderIds: [mine], targetParentId: theirs),
      );
      await refused(() => folders.createFolder(name: 'New', parentId: theirs));
    });

    test('a write of my own folder still writes', () async {
      final moved = await folders.moveFolders(
        folderIds: [mine],
        targetParentId: null,
      );
      expect(moved.unchanged, {mine});
      final renamed = await folders.updateFolder(folderId: mine, name: 'Ours');
      expect(renamed!.name, 'Ours');
      expect(renamed.fromPartner, isFalse);
    });
  });

  test('a move\'s result says what it did to sharing (share surfaces '
      '§6.11)', () async {
    final shelf = await folder('Shelf');
    final box = await folder('Box');
    await db.folderDao.setSharedPair(shelf, 'pair-1');

    final into = await folders.moveFolders(
      folderIds: [box],
      targetParentId: shelf,
    );
    expect(into.shareChange, MoveShareChange.nowShared);
    expect(
      (await folders.getFolderById(box))!.share,
      model.FolderShare.through(shelf),
      reason: 'the census was dropped by the move, and read again',
    );

    final out = await folders.moveFolders(
      folderIds: [box],
      targetParentId: null,
    );
    expect(out.shareChange, MoveShareChange.noLongerShared);
  });

  test('a marked folder moved into a shared one keeps its mark and reads as '
      'shared through the outer one while it lies there', () async {
    final shelf = await folder('Shelf');
    final box = await folder('Box');
    await db.folderDao.setSharedPair(shelf, 'pair-1');
    await db.folderDao.setSharedPair(box, 'pair-1');

    final into = await folders.moveFolders(
      folderIds: [box],
      targetParentId: shelf,
    );

    expect(into.shareChange, isNull, reason: 'shared before and after');
    expect(
      (await folders.getFolderById(box))!.share,
      model.FolderShare.through(shelf),
    );
    await folders.moveFolders(folderIds: [box], targetParentId: null);
    expect((await folders.getFolderById(box))!.share, model.FolderShare.byMark);
  });

  test('a reorder never plans the partner\'s rows: their positions stay, '
      'and what it changed names mine alone', () async {
    final a = await folder('A');
    final b = await folder('B');
    final theirs = await folder('Theirs');
    final note = (await db.noteDao.createNote(folderId: theirs, title: 'T')).id;
    await partners([theirs]);
    await db.customStatement(
      "UPDATE notes SET owner_id = '$partner' WHERE id = ?",
      [note],
    );
    final before = (await db.folderDao.getByIdsIncludingDeleted([theirs]))
        .single
        .position;

    final changed = await db.folderDao.applyOrder(
      parentId: null,
      loadedOrder: [theirs, b, a],
      descending: false,
    );

    expect(changed, isNot(contains(theirs)));
    expect(
      (await db.folderDao.getByIdsIncludingDeleted([theirs])).single.position,
      before,
    );
    expect(
      await db.noteDao.applyOrder(
        folderId: theirs,
        loadedOrder: [note],
        descending: true,
      ),
      isEmpty,
      reason: 'the notes in their folder are theirs: nothing to plan',
    );
  });
}
