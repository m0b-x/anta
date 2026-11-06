import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/services/folder_name_index.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/recent_destinations_service.dart';
import 'package:anta/widgets/folder_picker_dialog.dart';

import '../database/support/db_test_support.dart';

/// The move picker opened from a note whose folder is a tombstone, with that
/// folder among the recent destinations: a tombstone a pull brought without
/// its data is stored under its id as its name, and neither the breadcrumb
/// nor the recents row may show it.
void main() {
  late AppDatabase db;
  late RecentDestinationsService recents;
  late String liveName;
  late String liveId;
  late String ghostId;

  final l10n = AppLocalizationsEn();

  setUp(() async {
    db = await openTestDatabase();
    final folders = FolderStorageService(
      repository: FolderRepository(database: db),
    );
    await folders.initialize();
    GetIt.I.registerSingleton<FolderStorageService>(folders);
    GetIt.I.registerSingleton<FolderNameIndex>(
      FolderNameIndex(folderService: folders),
    );
    recents = RecentDestinationsService();
    GetIt.I.registerSingleton<RecentDestinationsService>(recents);

    final live = await db.folderDao.createFolder(name: 'Training');
    liveName = live.name;
    liveId = live.id;
    ghostId = (await db.folderDao.createFolder(name: 'Legs')).id;
    await db.customStatement(
      'UPDATE folders SET name = id, is_deleted = 1 WHERE id = ?',
      [ghostId],
    );
    recents.record(ghostId);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  Future<void> openPicker(
    WidgetTester tester,
    String currentFolderId, {
    String? waitFor,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showFolderPickerDialog(
              context,
              currentFolderId: currentFolderId,
            ),
            child: const Text('move'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('move'));
    final shown = find.text(waitFor ?? liveName);
    for (var i = 0; i < 100 && shown.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 5));
    }
    // The folder list loads after the crumbs.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 5));
    }
  }

  testWidgets('a tombstoned current or recent folder is never named', (
    tester,
  ) async {
    await openPicker(tester, ghostId);

    expect(find.text(liveName), findsOneWidget);
    expect(find.textContaining(ghostId), findsNothing);
  });

  testWidgets('opened inside a tombstoned chain, it opens at the nearest live '
      'folder and offers only that', (tester) async {
    // Training (live) > Block (a data-less tombstone, named by its id) > Legs
    // (tombstone), with a live Sibling still under Block while the folder
    // repair waits.
    final blockId = (await tester.runAsync(
      () => db.folderDao.createFolder(name: 'Block', parentId: liveId),
    ))!.id;
    final legsId = (await tester.runAsync(
      () => db.folderDao.createFolder(name: 'Legs', parentId: blockId),
    ))!.id;
    await tester.runAsync(
      () => db.folderDao.createFolder(name: 'Sibling', parentId: blockId),
    );
    await tester.runAsync(
      () => db.customStatement(
        'UPDATE folders SET name = id, is_deleted = 1 WHERE id = ?',
        [blockId],
      ),
    );
    await tester.runAsync(
      () => db.customStatement(
        'UPDATE folders SET is_deleted = 1 WHERE id = ?',
        [legsId],
      ),
    );
    recents.clear();

    await openPicker(tester, legsId);

    expect(find.textContaining(blockId), findsNothing);
    expect(find.textContaining(blockId.toUpperCase()), findsNothing);
    expect(find.text('Sibling'), findsNothing);
    expect(find.text('Legs'), findsNothing);
    expect(
      find.text(l10n.subfoldersOf(liveName).toUpperCase()),
      findsOneWidget,
    );
    expect(find.text(l10n.moveToDestination(liveName)), findsOneWidget);
  });

  testWidgets('a chain of locally deleted folders is never named either', (
    tester,
  ) async {
    final winterId = (await tester.runAsync(
      () => db.folderDao.createFolder(name: 'Winter', parentId: liveId),
    ))!.id;
    final weekId = (await tester.runAsync(
      () => db.folderDao.createFolder(name: 'Week 1', parentId: winterId),
    ))!.id;
    await tester.runAsync(
      () => db.folderDao.softDeleteFolderWithDescendants(winterId),
    );
    recents.clear();

    await openPicker(tester, weekId);

    expect(find.textContaining('Winter'), findsNothing);
    expect(find.textContaining('Week 1'), findsNothing);
    expect(find.text(l10n.moveToDestination(liveName)), findsOneWidget);
  });

  testWidgets('the crumbs above a live folder stop at the first tombstone', (
    tester,
  ) async {
    // Training > Old (deleted here) > Current (live, the folder repair has
    // not re-filed it yet) > Gone (deleted).
    final oldId = (await tester.runAsync(
      () => db.folderDao.createFolder(name: 'Old', parentId: liveId),
    ))!.id;
    final currentId = (await tester.runAsync(
      () => db.folderDao.createFolder(name: 'Current', parentId: oldId),
    ))!.id;
    final goneId = (await tester.runAsync(
      () => db.folderDao.createFolder(name: 'Gone', parentId: currentId),
    ))!.id;
    await tester.runAsync(
      () => db.customStatement(
        'UPDATE folders SET is_deleted = 1 WHERE id IN (?, ?)',
        [oldId, goneId],
      ),
    );
    recents.clear();

    await openPicker(tester, goneId, waitFor: 'Current');

    expect(find.text('Current'), findsOneWidget);
    expect(find.textContaining('Old'), findsNothing);
    expect(find.text(liveName), findsNothing);
    expect(find.textContaining('Gone'), findsNothing);
    expect(find.text(l10n.moveToDestination('Current')), findsOneWidget);
  });
}
