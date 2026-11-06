import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
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
  late String liveName;
  late String ghostId;

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
    final recents = RecentDestinationsService();
    GetIt.I.registerSingleton<RecentDestinationsService>(recents);

    liveName = (await db.folderDao.createFolder(name: 'Training')).name;
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

  testWidgets('a tombstoned current or recent folder is never named', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showFolderPickerDialog(context, currentFolderId: ghostId),
            child: const Text('move'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('move'));
    for (var i = 0; i < 100 && find.text(liveName).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 5));
    }

    expect(find.text(liveName), findsOneWidget);
    expect(find.textContaining(ghostId), findsNothing);
  });
}
