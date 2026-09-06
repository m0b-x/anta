import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/nav_destination.dart';
import 'package:anta/pages/optimized_folder_content_page.dart';
import 'package:anta/services/app_navigator.dart';

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
