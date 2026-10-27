import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/core/di/injection.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/sync/app_sync_apply_hooks.dart';
import 'package:anta/services/sync/conflict_copy_title.dart';
import 'package:anta/services/sync/sync_apply_hooks.dart';
import 'package:anta/services/sync/sync_table_binding.dart';

/// The production hooks after the user switched databases mid-session, with
/// the repositories resolved through GetIt as the app resolves them: the
/// conflict copy must land in the switched-to database instead of throwing
/// out of the page's transaction (A5 review R100), and a merged note must
/// still be announced (R101).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final now = DateTime(2026, 10, 27, 8, 15);

  /// Database names are unique per test: `AppDatabase` keeps the open it
  /// handed out under its name, and the `DatabaseManager` singleton's
  /// `SharedPreferences` keeps its own cache, so a second test reusing a
  /// name would be handed the first one's closed database.
  var round = 0;

  setUpAll(() => initializeDateFormatting('en'));

  setUp(() async {
    round++;
    tempDir = await Directory.systemTemp.createTemp('anta_hooks_switch');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    await (await DatabaseManager.getInstance()).setActiveDatabaseName(
      'before_$round',
    );
    getIt.registerSingleton<AppDatabase>(await AppDatabase.getInstance());
    registerRepositorySingletons();
    getIt.registerSingleton<NoteStorageService>(
      NoteStorageService(repository: getIt<NoteRepository>()),
    );
  });

  tearDown(() async {
    await getIt.reset();
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  /// The app's hooks: only the language and the clock are pinned, so the
  /// repositories and the storage service come from GetIt.
  AppSyncApplyHooks appHooks() => AppSyncApplyHooks(
    strings: () async => lookupAppLocalizations(const Locale('en')),
    now: () => now,
  );

  /// The switch the database settings page performs, with the restart
  /// dialog dismissed: the active name moves and the next open closes the
  /// previous database before announcing the new one.
  Future<AppDatabase> switchDatabase() async {
    final manager = await DatabaseManager.getInstance();
    await manager.setActiveDatabaseName('after_$round');
    final db = await AppDatabase.getInstance();
    await pumpEventQueue();
    return db;
  }

  test('files a conflict copy in the switched-to database', () async {
    final before = getIt<AppDatabase>();
    final loser = await before.noteDao.createNote(
      folderId: '',
      title: 'Plan',
      content: 'the text that lost',
    );

    final after = await switchDatabase();

    final copyId = await appHooks().fileConflictCopy(
      SyncNoteConflict(loser: loser, loserContent: 'the text that lost'),
    );

    expect(copyId, isNotNull);
    final copy = await after.noteDao.getNoteById(copyId!);
    expect(
      copy?.title,
      conflictCopyTitle(
        lookupAppLocalizations(const Locale('en')),
        'Plan',
        now,
      ),
    );
    expect(
      await getIt<NoteRepository>().loadContent(copyId),
      'the text that lost',
    );
  });

  test('announces a note merged into the switched-to database', () async {
    final after = await switchDatabase();
    final merged = await after.noteDao.createNote(
      folderId: 'f1',
      title: 'Merged',
    );

    final seen = <NoteChange>[];
    final sub = getIt<NoteStorageService>().changes.listen(seen.add);
    addTearDown(sub.cancel);

    await appHooks().afterPage('notes', [
      SyncAppliedRow(
        rowKey: merged.id,
        result: MergeResult.inserted,
        tombstone: false,
      ),
    ]);
    await pumpEventQueue();

    expect(seen.map((change) => change.noteId), [merged.id]);
    expect(seen.single.type, NoteChangeType.created);
    expect(seen.single.remote, isTrue);
  });
}
