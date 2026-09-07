import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/database/database.dart';
import 'package:anta/models/nav_destination.dart';
import 'package:anta/pages/optimized_folder_content_page.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/folder_storage_service.dart';

import '../database/support/db_test_support.dart';

/// `popUntil` animates every route it passes (flutter#59990), so the editor's
/// "Open folder" would flicker through each note it was reached from. These
/// cases pin the shape that replaces it: the routes in between are removed
/// outright and exactly one pop is played.
///
/// Nothing here mounts a real page — the routes carry plain `Text` bodies,
/// because the whole decision is made from `RouteSettings.arguments`.
void main() {
  final navigatorKey = GlobalKey<NavigatorState>();

  late _RecordingObserver observer;
  final contexts = <String, BuildContext>{};

  final training = NavDestination.folder(folderId: 'f1', title: 'Training');
  final recipes = NavDestination.folder(folderId: 'f2', title: 'Recipes');

  setUp(() {
    observer = _RecordingObserver();
    contexts.clear();
  });

  Route<void> pageRoute(String label, {NavDestination? destination}) {
    return MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        body: Builder(
          builder: (context) {
            contexts[label] = context;
            return Text(label);
          },
        ),
      ),
      settings: destination == null
          ? null
          : RouteSettings(name: destination.kind.name, arguments: destination),
    );
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [AppNavigator.routeObserver, observer],
        home: Scaffold(
          body: Builder(
            builder: (context) {
              contexts['root'] = context;
              return const Text('root');
            },
          ),
        ),
      ),
    );
  }

  Future<void> push(WidgetTester tester, Route<void> route) async {
    navigatorKey.currentState!.push(route);
    await tester.pumpAndSettle();
  }

  testWidgets('removes every route in between and pops exactly once', (
    tester,
  ) async {
    await pumpApp(tester);
    await push(tester, pageRoute('training', destination: training));
    final folderRoute = observer.pushed.last;
    await push(
      tester,
      pageRoute(
        'note a',
        destination: NavDestination.note(noteId: 'a', folderId: 'f1'),
      ),
    );
    final intermediate = observer.pushed.last;
    await push(
      tester,
      pageRoute(
        'note b',
        destination: NavDestination.note(noteId: 'b', folderId: 'f1'),
      ),
    );
    final top = observer.pushed.last;
    observer.clear();

    await AppNavigator.popToFolder(
      contexts['note b']!,
      folderId: 'f1',
      title: 'Training',
    );
    await tester.pumpAndSettle();

    expect(observer.removed, [intermediate]);
    expect(observer.popped, [top]);
    expect(observer.pushed, isEmpty);
    expect(find.text('training'), findsOneWidget);
    expect(folderRoute.isCurrent, isTrue);
  });

  testWidgets('pops once when the folder is the route directly below', (
    tester,
  ) async {
    await pumpApp(tester);
    await push(tester, pageRoute('training', destination: training));
    await push(
      tester,
      pageRoute(
        'note a',
        destination: NavDestination.note(noteId: 'a', folderId: 'f1'),
      ),
    );
    observer.clear();

    await AppNavigator.popToFolder(
      contexts['note a']!,
      folderId: 'f1',
      title: 'Training',
    );
    await tester.pumpAndSettle();

    expect(observer.removed, isEmpty);
    expect(observer.popped, hasLength(1));
    expect(find.text('training'), findsOneWidget);
  });

  testWidgets('the folder nearest the top is the one returned to', (
    tester,
  ) async {
    await pumpApp(tester);
    await push(tester, pageRoute('training', destination: training));
    await push(tester, pageRoute('training again', destination: training));
    final nearest = observer.pushed.last;
    await push(
      tester,
      pageRoute(
        'note a',
        destination: NavDestination.note(noteId: 'a', folderId: 'f1'),
      ),
    );
    observer.clear();

    await AppNavigator.popToFolder(
      contexts['note a']!,
      folderId: 'f1',
      title: 'Training',
    );
    await tester.pumpAndSettle();

    expect(observer.removed, isEmpty);
    expect(nearest.isCurrent, isTrue);
    expect(find.text('training again'), findsOneWidget);
  });

  testWidgets('a folder that is not on the stack replaces the current page', (
    tester,
  ) async {
    await pumpApp(tester);
    await push(tester, pageRoute('recipes', destination: recipes));
    await push(
      tester,
      pageRoute(
        'note a',
        destination: NavDestination.note(noteId: 'a', folderId: 'f1'),
      ),
    );
    observer.clear();

    // Deliberately not settled: the replacement route is asserted on through
    // the observer, so the folder page it carries is never built and the
    // case stays a navigation test rather than a page test.
    AppNavigator.popToFolder(
      contexts['note a']!,
      folderId: 'f1',
      title: 'Training',
    ).ignore();

    expect(observer.replacements, hasLength(1));
    final replacement = observer.replacements.single;
    expect(replacement.newRoute!.settings.arguments, training);
    expect(
      (replacement.newRoute as MaterialPageRoute).builder(contexts['root']!),
      isA<OptimizedFolderContentPage>(),
    );
    expect(observer.removed, isEmpty);
    expect(observer.popped, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the folder already showing is left alone', (tester) async {
    await pumpApp(tester);
    await push(tester, pageRoute('training', destination: training));
    observer.clear();

    await AppNavigator.popToFolder(
      contexts['training']!,
      folderId: 'f1',
      title: 'Training',
    );
    await tester.pumpAndSettle();

    expect(observer.removed, isEmpty);
    expect(observer.popped, isEmpty);
    expect(observer.replacements, isEmpty);
    expect(find.text('training'), findsOneWidget);
  });

  /// The browser's ancestor menu ends with the root, which is `home`: it
  /// carries no folder id, so it is addressed by [Route.isFirst] rather than
  /// by a stamp. `popUntilFirst` would have played one transition per level.
  group('popToAncestor', () {
    final winter = NavDestination.folder(folderId: 'f3', title: 'Winter block');

    testWidgets('the root pops past every level in one transition', (
      tester,
    ) async {
      await pumpApp(tester);
      final home = observer.pushed.last;
      await push(tester, pageRoute('training', destination: training));
      final intermediate = observer.pushed.last;
      await push(tester, pageRoute('winter', destination: winter));
      final top = observer.pushed.last;
      observer.clear();

      await AppNavigator.popToAncestor(contexts['winter']!);
      await tester.pumpAndSettle();

      expect(observer.removed, [intermediate]);
      expect(observer.popped, [top]);
      expect(observer.replacements, isEmpty);
      expect(home.isCurrent, isTrue);
      expect(find.text('root'), findsOneWidget);
    });

    testWidgets('the root is left alone when it is already showing', (
      tester,
    ) async {
      await pumpApp(tester);
      observer.clear();

      await AppNavigator.popToAncestor(contexts['root']!);
      await tester.pumpAndSettle();

      expect(observer.removed, isEmpty);
      expect(observer.popped, isEmpty);
      expect(observer.replacements, isEmpty);
      expect(find.text('root'), findsOneWidget);
    });

    testWidgets('a folder id goes through popToFolder', (tester) async {
      await pumpApp(tester);
      await push(tester, pageRoute('training', destination: training));
      final folderRoute = observer.pushed.last;
      await push(tester, pageRoute('winter', destination: winter));
      final intermediate = observer.pushed.last;
      await push(
        tester,
        pageRoute(
          'note a',
          destination: NavDestination.note(noteId: 'a', folderId: 'f3'),
        ),
      );
      final top = observer.pushed.last;
      observer.clear();

      await AppNavigator.popToAncestor(
        contexts['note a']!,
        folderId: 'f1',
        title: 'Training',
      );
      await tester.pumpAndSettle();

      expect(observer.removed, [intermediate]);
      expect(observer.popped, [top]);
      expect(folderRoute.isCurrent, isTrue);
      expect(find.text('training'), findsOneWidget);
    });

    testWidgets('a folder id that is not on the stack rebuilds it', (
      tester,
    ) async {
      await pumpApp(tester);
      await push(tester, pageRoute('recipes', destination: recipes));
      observer.clear();

      AppNavigator.popToAncestor(
        contexts['recipes']!,
        folderId: 'f1',
        title: 'Training',
      ).ignore();

      expect(observer.replacements, hasLength(1));
      expect(
        observer.replacements.single.newRoute!.settings.arguments,
        training,
      );
      expect(observer.removed, isEmpty);
      expect(observer.popped, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  /// The editor's "Open folder" runs before the folder name has loaded and
  /// passes `''`. The fallback branch *stamps* the route it pushes, so a blank
  /// title would be persisted into the restore stack and come back as a folder
  /// page captioned with nothing. The name is read first instead.
  group('the fallback push never stamps an empty title', () {
    late AppDatabase db;
    late Folder folder;

    setUp(() async {
      db = await openTestDatabase();
      folder = await db.folderDao.createFolder(name: 'Training');
      GetIt.I.registerSingleton<FolderStorageService>(
        FolderStorageService(repository: FolderRepository(database: db)),
      );
    });

    tearDown(() async {
      await GetIt.I.reset();
      await db.close();
    });

    Future<void> drain(WidgetTester tester) => tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );

    testWidgets('an empty title is replaced by the folder\'s real name', (
      tester,
    ) async {
      await pumpApp(tester);
      await push(tester, pageRoute('recipes', destination: recipes));
      await push(
        tester,
        pageRoute(
          'note a',
          destination: NavDestination.note(noteId: 'a', folderId: folder.id),
        ),
      );
      observer.clear();

      AppNavigator.popToFolder(
        contexts['note a']!,
        folderId: folder.id,
        title: '',
      ).ignore();
      await drain(tester);

      expect(observer.replacements, hasLength(1));
      expect(
        observer.replacements.single.newRoute!.settings.arguments,
        NavDestination.folder(folderId: folder.id, title: 'Training'),
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a folder that no longer resolves is pushed unstamped', (
      tester,
    ) async {
      await pumpApp(tester);
      await push(tester, pageRoute('recipes', destination: recipes));
      observer.clear();

      AppNavigator.popToFolder(
        contexts['recipes']!,
        folderId: 'gone',
        title: '',
      ).ignore();
      await drain(tester);

      expect(observer.replacements, hasLength(1));
      expect(observer.replacements.single.newRoute!.settings.arguments, isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('a non-empty title still replaces synchronously', (
      tester,
    ) async {
      await pumpApp(tester);
      await push(tester, pageRoute('recipes', destination: recipes));
      observer.clear();

      AppNavigator.popToFolder(
        contexts['recipes']!,
        folderId: folder.id,
        title: 'Training',
      ).ignore();

      expect(observer.replacements, hasLength(1));

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

class _Replacement {
  const _Replacement(this.newRoute, this.oldRoute);

  final Route<dynamic>? newRoute;
  final Route<dynamic>? oldRoute;
}

class _RecordingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];
  final List<Route<dynamic>> popped = [];
  final List<Route<dynamic>> removed = [];
  final List<_Replacement> replacements = [];

  void clear() {
    pushed.clear();
    popped.clear();
    removed.clear();
    replacements.clear();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popped.add(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    removed.add(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    replacements.add(_Replacement(newRoute, oldRoute));
  }
}
