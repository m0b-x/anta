import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/nav_destination.dart';
import 'package:anta/services/navigation_history_service.dart';

/// The observer is what replaced a recording scheme that only ever saw
/// pushes. Pops arrived through the system back gesture, app-bar back buttons
/// and stray `Navigator.pop` calls, and none of them were noticed — which is
/// why the old feature only half-worked. These tests exercise the events that
/// used to go unseen.
///
/// The service is left sealed (no `beginRecording`), so nothing touches a
/// database and the assertions are on the in-memory stack alone.
void main() {
  late NavigationHistoryService history;
  late NavigationHistoryObserver observer;

  final folder = NavDestination.folder(folderId: 'f1', title: 'Training');
  final note = NavDestination.note(noteId: 'n1', folderId: 'f1');
  const calendar = NavDestination(NavDestinationKind.calendar);

  setUp(() {
    history = NavigationHistoryService();
    observer = NavigationHistoryObserver(history);
  });

  tearDown(() => history.dispose());

  final navigatorKey = GlobalKey<NavigatorState>();

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        navigatorObservers: [observer],
        home: const Scaffold(body: Text('home')),
      ),
    );
  }

  Route<T> pageRoute<T>(String label, {NavDestination? destination}) {
    return MaterialPageRoute<T>(
      builder: (_) => Scaffold(body: Text(label)),
      settings: destination == null
          ? null
          : RouteSettings(name: destination.kind.name, arguments: destination),
    );
  }

  testWidgets('the root page is not itself an entry', (tester) async {
    await pumpApp(tester);

    expect(history.stack, isEmpty);
  });

  testWidgets('a stamped push is recorded', (tester) async {
    await pumpApp(tester);

    navigatorKey.currentState!.push(pageRoute('folder', destination: folder));
    await tester.pumpAndSettle();

    expect(history.stack, [folder]);
  });

  testWidgets('a chain is recorded bottom-to-top', (tester) async {
    await pumpApp(tester);

    navigatorKey.currentState!.push(pageRoute('folder', destination: folder));
    navigatorKey.currentState!.push(pageRoute('note', destination: note));
    await tester.pumpAndSettle();

    expect(history.stack, [folder, note]);
  });

  testWidgets('a pop is seen — the gap the old design had', (tester) async {
    await pumpApp(tester);

    navigatorKey.currentState!.push(pageRoute('folder', destination: folder));
    navigatorKey.currentState!.push(pageRoute('note', destination: note));
    await tester.pumpAndSettle();

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();

    expect(history.stack, [folder]);
  });

  testWidgets('popping back to the root empties the stack', (tester) async {
    await pumpApp(tester);

    navigatorKey.currentState!.push(pageRoute('calendar', destination: calendar));
    await tester.pumpAndSettle();

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();

    expect(history.stack, isEmpty);
  });

  testWidgets('an unstamped page stops recording above it', (tester) async {
    await pumpApp(tester);

    navigatorKey.currentState!.push(pageRoute('folder', destination: folder));
    navigatorKey.currentState!.push(pageRoute('shortcut editor'));
    navigatorKey.currentState!.push(pageRoute('calendar', destination: calendar));
    await tester.pumpAndSettle();

    expect(history.stack, [folder]);
  });

  testWidgets('recording resumes once the unstamped page is gone',
      (tester) async {
    await pumpApp(tester);

    navigatorKey.currentState!.push(pageRoute('folder', destination: folder));
    navigatorKey.currentState!.push(pageRoute('shortcut editor'));
    await tester.pumpAndSettle();

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    navigatorKey.currentState!.push(pageRoute('calendar', destination: calendar));
    await tester.pumpAndSettle();

    expect(history.stack, [folder, calendar]);
  });

  testWidgets('a dialog leaves the stack alone', (tester) async {
    await pumpApp(tester);

    navigatorKey.currentState!.push(pageRoute('folder', destination: folder));
    await tester.pumpAndSettle();

    showDialog<void>(
      context: navigatorKey.currentContext!,
      builder: (_) => const AlertDialog(content: Text('dialog')),
    );
    await tester.pumpAndSettle();

    expect(history.stack, [folder]);
  });

  testWidgets('a modal bottom sheet leaves the stack alone', (tester) async {
    await pumpApp(tester);

    navigatorKey.currentState!.push(pageRoute('calendar', destination: calendar));
    await tester.pumpAndSettle();

    showModalBottomSheet<void>(
      context: navigatorKey.currentContext!,
      builder: (_) => const SizedBox(height: 100),
    );
    await tester.pumpAndSettle();

    expect(history.stack, [calendar]);
  });

  testWidgets('a replacement takes the replaced route\'s place', (tester) async {
    await pumpApp(tester);

    navigatorKey.currentState!.push(pageRoute('folder', destination: folder));
    navigatorKey.currentState!.push(pageRoute('note', destination: note));
    await tester.pumpAndSettle();

    navigatorKey.currentState!.pushReplacement(
      pageRoute('calendar', destination: calendar),
    );
    await tester.pumpAndSettle();

    expect(history.stack, [folder, calendar]);
  });

  testWidgets('removing a route mid-stack leaves the stack mirroring the '
      'navigator, not the old chain', (tester) async {
    await pumpApp(tester);

    final middle = pageRoute('folder', destination: folder);
    navigatorKey.currentState!.push(middle);
    navigatorKey.currentState!.push(pageRoute('note', destination: note));
    await tester.pumpAndSettle();

    navigatorKey.currentState!.removeRoute(middle);
    await tester.pumpAndSettle();

    expect(history.stack, [note]);
  });
}
