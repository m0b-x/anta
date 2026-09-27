import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/nav_destination.dart';
import 'package:anta/services/app_navigator.dart';

/// The calendar and the overview are two views of one feature, so the view
/// menu's switch never stacks them (D6 of `docs/calendar-header-roadmap.md`):
/// the page directly beneath is returned to with one pop, anything else is a
/// push. The routes carry plain bodies — the decision is made from
/// `RouteSettings.arguments` alone — so only the pop branch of the real
/// wrappers runs here; the push branch goes through a recorded callback.
void main() {
  final navigatorKey = GlobalKey<NavigatorState>();
  late _RecordingObserver observer;
  final contexts = <String, BuildContext>{};

  const calendar = NavDestination(NavDestinationKind.calendar);
  const overview = NavDestination(NavDestinationKind.calendarOverview);
  const alerts = NavDestination(NavDestinationKind.alerts);

  setUp(() {
    observer = _RecordingObserver();
    contexts.clear();
  });

  Route<void> pageRoute(
    String label, {
    NavDestination? destination,
    Widget Function(BuildContext context)? body,
  }) {
    return MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        body: Builder(
          builder: (context) {
            contexts[label] = context;
            return body?.call(context) ?? Text(label);
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
        home: const Scaffold(body: Text('root')),
      ),
    );
  }

  Future<Route<void>> push(WidgetTester tester, Route<void> route) async {
    navigatorKey.currentState!.push(route);
    await tester.pumpAndSettle();
    return route;
  }

  testWidgets('returns to the page directly beneath with one pop', (
    tester,
  ) async {
    await pumpApp(tester);
    final calendarRoute = await push(
      tester,
      pageRoute('calendar', destination: calendar),
    );
    final overviewRoute = await push(
      tester,
      pageRoute('overview', destination: overview),
    );
    observer.clear();
    var pushes = 0;

    await AppNavigator.returnOrPush(
      contexts['overview']!,
      NavDestinationKind.calendar,
      () async => pushes++,
    );
    await tester.pumpAndSettle();

    expect(pushes, 0);
    expect(observer.popped, [overviewRoute]);
    expect(observer.removed, isEmpty);
    expect(calendarRoute.isCurrent, isTrue);
  });

  testWidgets('pushes when the page beneath is another one', (tester) async {
    await pumpApp(tester);
    await push(tester, pageRoute('overview', destination: overview));
    observer.clear();
    var pushes = 0;

    await AppNavigator.returnOrPush(
      contexts['overview']!,
      NavDestinationKind.calendar,
      () async => pushes++,
    );
    await tester.pumpAndSettle();

    expect(pushes, 1);
    expect(observer.popped, isEmpty);
    expect(find.text('overview'), findsOneWidget);
  });

  testWidgets('never collapses onto the page further down', (tester) async {
    await pumpApp(tester);
    await push(tester, pageRoute('calendar', destination: calendar));
    await push(tester, pageRoute('hub', destination: alerts));
    await push(tester, pageRoute('overview', destination: overview));
    observer.clear();
    var pushes = 0;

    await AppNavigator.returnOrPush(
      contexts['overview']!,
      NavDestinationKind.calendar,
      () async => pushes++,
    );
    await tester.pumpAndSettle();

    expect(pushes, 1, reason: 'the hub the user walked through survives');
    expect(observer.popped, isEmpty);
    expect(observer.removed, isEmpty);
  });

  testWidgets('a pick in the page\'s own menu pops the page, not the menu', (
    tester,
  ) async {
    await pumpApp(tester);
    final calendarRoute = await push(
      tester,
      pageRoute('calendar', destination: calendar),
    );
    await push(
      tester,
      pageRoute(
        'overview',
        destination: overview,
        body: (context) => PopupMenuButton<int>(
          onSelected: (_) => AppNavigator.switchToCalendar(context),
          itemBuilder: (_) => const [
            PopupMenuItem<int>(value: 1, child: Text('Calendar')),
          ],
          child: const Text('Overview'),
        ),
      ),
    );

    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();

    expect(calendarRoute.isCurrent, isTrue);
    expect(find.text('calendar'), findsOneWidget);
    expect(find.text('Overview'), findsNothing);
  });

  testWidgets('the wrappers return to their own page kind', (tester) async {
    await pumpApp(tester);
    final overviewRoute = await push(
      tester,
      pageRoute('overview', destination: overview),
    );
    await push(tester, pageRoute('calendar', destination: calendar));

    await AppNavigator.switchToCalendarOverview(contexts['calendar']!);
    await tester.pumpAndSettle();
    expect(overviewRoute.isCurrent, isTrue);

    final hubRoute = await push(tester, pageRoute('hub', destination: alerts));
    final calendarRoute = await push(
      tester,
      pageRoute('calendar again', destination: calendar),
    );
    await AppNavigator.toAlertsFromCalendar(contexts['calendar again']!);
    await tester.pumpAndSettle();
    expect(hubRoute.isCurrent, isTrue);
    expect(calendarRoute.isActive, isFalse);
  });
}

class _RecordingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];
  final List<Route<dynamic>> popped = [];
  final List<Route<dynamic>> removed = [];

  void clear() {
    pushed.clear();
    popped.clear();
    removed.clear();
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
}
