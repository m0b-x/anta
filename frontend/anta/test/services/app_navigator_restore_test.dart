import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/nav_destination.dart';
import 'package:anta/pages/all_notes_page.dart';
import 'package:anta/models/restore_location_mode.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/navigation_history_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';

/// Launch restore, against the real database and the app's own
/// [AppNavigator] — the half of the feature the observer suite cannot reach.
///
/// The replay is deliberately two-phase: phase 1 resolves the whole chain,
/// phase 2 pushes without ever awaiting a push. Both halves are asserted
/// through a recording observer rather than by settling the pages, because
/// what is under test is *which routes land and how they are stamped*, not
/// what a folder page paints. The routes are never built: the tree is torn
/// down before a frame that would build them.
void main() {
  late AppDatabase db;
  late SettingsService settings;
  late NoteRepository noteRepository;
  late NoteStorageService notes;
  late FolderStorageService folders;
  late NavigationHistoryService history;
  late _RecordingObserver observer;

  setUp(() async {
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);

    noteRepository = NoteRepository(database: db);
    notes = NoteStorageService(repository: noteRepository);
    await notes.initialize();
    folders = FolderStorageService(repository: FolderRepository(database: db));
    await folders.initialize();
    history = NavigationHistoryService(
      writeDebounce: const Duration(milliseconds: 10),
    );
    observer = _RecordingObserver();

    GetIt.I.registerSingleton<NoteRepository>(noteRepository);
    GetIt.I.registerSingleton<FolderStorageService>(folders);
    GetIt.I.registerSingleton<NoteStorageService>(notes);
    GetIt.I.registerSingleton<NavigationHistoryService>(history);
  });

  tearDown(() async {
    history.dispose();
    await GetIt.I.reset();
    SettingsService.reset();
    DatabaseLifecycle.notifyDatabaseSwitching();
    await db.close();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: AppNavigator.navigatorKey,
        navigatorObservers: [
          AppNavigator.routeObserver,
          NavigationHistoryObserver(history),
          observer,
        ],
        home: const Scaffold(body: Text('root')),
      ),
    );
  }

  /// Tears the app down before any frame builds the restored pages — the
  /// suite is about routes, and building a folder page would drag in every
  /// bloc it reads.
  Future<void> teardownApp(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  /// Runs the replay for real: drift answers on futures `FakeAsync` would
  /// never complete, and no frame is pumped, so the pushed routes stay
  /// unbuilt.
  Future<void> restore(WidgetTester tester) =>
      tester.runAsync(() => AppNavigator.restoreLastLocation()).then((_) {});

  List<NavDestination> restoredDestinations() => [
    for (final route in observer.pushed)
      if (route.settings.arguments is NavDestination)
        route.settings.arguments as NavDestination,
  ];

  Widget pageOf(Route<dynamic> route, BuildContext context) {
    return (route as PageRouteBuilder<Object?>).pageBuilder(
      context,
      const AlwaysStoppedAnimation<double>(1),
      const AlwaysStoppedAnimation<double>(0),
    );
  }

  testWidgets('parked on Recent restores AllNotesPage in recent mode', (
    tester,
  ) async {
    await settings.saveLastLocationStack(const [
      NavDestination(NavDestinationKind.recentNotes),
    ]);
    await pumpApp(tester);
    observer.clear();

    await restore(tester);

    expect(restoredDestinations(), const [
      NavDestination(NavDestinationKind.recentNotes),
    ]);
    final page = pageOf(
      observer.pushed.single,
      AppNavigator.navigatorKey.currentContext!,
    );
    expect(page, isA<AllNotesPage>());
    expect((page as AllNotesPage).mode, AllNotesMode.recent);

    await teardownApp(tester);
  });

  testWidgets('parked on All notes restores it in all mode', (tester) async {
    await settings.saveLastLocationStack(const [
      NavDestination(NavDestinationKind.allNotes),
    ]);
    await pumpApp(tester);
    observer.clear();

    await restore(tester);

    expect(restoredDestinations(), const [
      NavDestination(NavDestinationKind.allNotes),
    ]);
    final page = pageOf(
      observer.pushed.single,
      AppNavigator.navigatorKey.currentContext!,
    );
    expect(page, isA<AllNotesPage>());
    expect((page as AllNotesPage).mode, AllNotesMode.all);

    await teardownApp(tester);
  });

  testWidgets('a deleted folder truncates the chain at its parent', (
    tester,
  ) async {
    final training = await folders.createFolder(name: 'Training');
    final winter = await folders.createFolder(
      name: 'Winter block',
      parentId: training.id,
    );
    await settings.saveLastLocationStack([
      NavDestination.folder(folderId: training.id, title: 'Training'),
      NavDestination.folder(folderId: winter.id, title: 'Winter block'),
    ]);
    await folders.deleteFolder(winter.id);

    await pumpApp(tester);
    observer.clear();

    await restore(tester);

    expect(restoredDestinations(), [
      NavDestination.folder(folderId: training.id, title: 'Training'),
    ]);

    await teardownApp(tester);
  });

  testWidgets('a folder title is refreshed rather than trusted', (
    tester,
  ) async {
    final training = await folders.createFolder(name: 'Training');
    await settings.saveLastLocationStack([
      NavDestination.folder(folderId: training.id, title: 'Old name'),
    ]);
    await folders.updateFolder(folderId: training.id, name: 'Renamed');

    await pumpApp(tester);
    observer.clear();

    await restore(tester);

    expect(restoredDestinations(), [
      NavDestination.folder(folderId: training.id, title: 'Renamed'),
    ]);

    await teardownApp(tester);
  });

  testWidgets('a moved note is followed into its new folder', (tester) async {
    final training = await folders.createFolder(name: 'Training');
    final recipes = await folders.createFolder(name: 'Recipes');
    final note = await notes.createNote(
      folderId: training.id,
      title: 'Wednesday',
      content: 'squat',
    );
    await settings.saveLastLocationStack([
      NavDestination.folder(folderId: training.id, title: 'Training'),
      NavDestination.note(noteId: note.id, folderId: training.id),
    ]);
    await notes.moveNote(noteId: note.id, targetFolderId: recipes.id);

    await pumpApp(tester);
    observer.clear();

    await restore(tester);

    // The note follows its move; the folder entry beneath it is *not*
    // re-resolved, so Back lands on the folder that was recorded.
    expect(restoredDestinations(), [
      NavDestination.folder(folderId: training.id, title: 'Training'),
      NavDestination.note(noteId: note.id, folderId: recipes.id),
    ]);

    await teardownApp(tester);
  });

  testWidgets('a soft-deleted note truncates', (tester) async {
    final training = await folders.createFolder(name: 'Training');
    final note = await notes.createNote(
      folderId: training.id,
      title: 'Wednesday',
      content: 'squat',
    );
    await settings.saveLastLocationStack([
      NavDestination.folder(folderId: training.id, title: 'Training'),
      NavDestination.note(noteId: note.id, folderId: training.id),
    ]);
    await notes.deleteNote(note.id);

    await pumpApp(tester);
    observer.clear();

    await restore(tester);

    expect(restoredDestinations(), [
      NavDestination.folder(folderId: training.id, title: 'Training'),
    ]);

    await teardownApp(tester);
  });

  testWidgets('no push is awaited — every restored route lands in one pass', (
    tester,
  ) async {
    final training = await folders.createFolder(name: 'Training');
    final winter = await folders.createFolder(
      name: 'Winter block',
      parentId: training.id,
    );
    final note = await notes.createNote(
      folderId: winter.id,
      title: 'Wednesday',
      content: 'squat',
    );
    await settings.saveLastLocationStack([
      NavDestination.folder(folderId: training.id, title: 'Training'),
      NavDestination.folder(folderId: winter.id, title: 'Winter block'),
      NavDestination.note(noteId: note.id, folderId: winter.id),
    ]);

    await pumpApp(tester);
    observer.clear();

    await restore(tester);

    // A Navigator push future completes when the route is *popped*, so
    // awaiting the first one would leave the rest queued behind the user's
    // next Back. All three exist the moment the replay returns.
    expect(observer.pushed, hasLength(3));
    expect(restoredDestinations().map((d) => d.kind), [
      NavDestinationKind.folder,
      NavDestinationKind.folder,
      NavDestinationKind.note,
    ]);
    for (final route in observer.pushed) {
      expect(route.isActive, isTrue);
    }

    await teardownApp(tester);
  });

  testWidgets('recording is unsealed even when the mode is off', (
    tester,
  ) async {
    await settings.setRestoreLocationMode(RestoreLocationMode.off);
    await settings.saveLastLocationStack(const [
      NavDestination(NavDestinationKind.calendar),
    ]);
    await pumpApp(tester);
    observer.clear();

    await restore(tester);

    expect(observer.pushed, isEmpty);
    expect(history.isRecording, isTrue);

    await teardownApp(tester);
  });

  testWidgets('recording is unsealed when there is nothing to restore', (
    tester,
  ) async {
    await settings.saveLastLocationStack(const []);
    await pumpApp(tester);
    observer.clear();

    await restore(tester);

    expect(observer.pushed, isEmpty);
    expect(history.isRecording, isTrue);

    await teardownApp(tester);
  });

  testWidgets('a user push during resolution cancels the replay', (
    tester,
  ) async {
    final training = await folders.createFolder(name: 'Training');
    await settings.saveLastLocationStack([
      NavDestination.folder(folderId: training.id, title: 'Training'),
    ]);
    await pumpApp(tester);
    observer.clear();

    await tester.runAsync(() async {
      // Phase 1 is several database round-trips long. The user taps a folder
      // row inside that window; burying their page under the remembered
      // chain is the bug this guards.
      final replay = AppNavigator.restoreLastLocation();
      AppNavigator.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('the user tapped this')),
        ),
      );
      final userPush = observer.pushed.single;
      await replay;
      expect(observer.pushed, [userPush]);
    });

    expect(history.isRecording, isTrue);

    await teardownApp(tester);
  });
}

class _RecordingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  void clear() => pushed.clear();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}
