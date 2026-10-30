import 'dart:async';

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

  group('three views (D36.1)', () {
    const report = NavDestination(NavDestinationKind.calendarReport);

    int liveRoutes() => AppNavigator.routeObserver.pageRoutes
        .where((route) => route.isActive)
        .length;

    testWidgets('calendar → overview → report → Calendar → Overview → '
        'Report never grows the stack', (tester) async {
      await pumpApp(tester);
      final calendarRoute = await push(
        tester,
        pageRoute('calendar', destination: calendar),
      );
      await push(tester, pageRoute('overview', destination: overview));
      await push(tester, pageRoute('report', destination: report));
      final deepest = liveRoutes();
      observer.clear();
      var pushes = 0;

      await AppNavigator.switchCalendarView(
        contexts['report']!,
        NavDestinationKind.calendar,
        () async => pushes++,
      );
      await tester.pumpAndSettle();
      expect(pushes, 0);
      expect(calendarRoute.isCurrent, isTrue);
      expect(observer.popped, hasLength(1), reason: 'one transition');
      expect(liveRoutes(), deepest - 2);

      // The pushes the menu would make from the calendar, then back down.
      await push(tester, pageRoute('overview 2', destination: overview));
      await push(tester, pageRoute('report 2', destination: report));
      await AppNavigator.switchCalendarView(
        contexts['report 2']!,
        NavDestinationKind.calendarOverview,
        () async => pushes++,
      );
      await tester.pumpAndSettle();
      expect(pushes, 0);
      expect(find.text('overview 2'), findsOneWidget);
      expect(liveRoutes(), deepest - 1);

      await AppNavigator.switchCalendarView(
        contexts['overview 2']!,
        NavDestinationKind.calendarReport,
        () async => pushes++,
      );
      expect(pushes, 1, reason: 'no report beneath: a push');
    });

    testWidgets('the real wrapper pops the report and the overview off the '
        'calendar', (tester) async {
      await pumpApp(tester);
      final calendarRoute = await push(
        tester,
        pageRoute('calendar', destination: calendar),
      );
      final overviewRoute = await push(
        tester,
        pageRoute('overview', destination: overview),
      );
      await push(tester, pageRoute('report', destination: report));

      await AppNavigator.switchToCalendar(contexts['report']!);
      await tester.pumpAndSettle();
      expect(calendarRoute.isCurrent, isTrue);
      expect(overviewRoute.isActive, isFalse);
    });

    testWidgets('a page of another kind above the target still pushes', (
      tester,
    ) async {
      await pumpApp(tester);
      await push(tester, pageRoute('calendar', destination: calendar));
      await push(tester, pageRoute('hub', destination: alerts));
      await push(tester, pageRoute('report', destination: report));
      observer.clear();
      var pushes = 0;

      await AppNavigator.switchCalendarView(
        contexts['report']!,
        NavDestinationKind.calendar,
        () async => pushes++,
      );
      await tester.pumpAndSettle();
      expect(pushes, 1, reason: 'the hub the user walked through survives');
      expect(observer.popped, isEmpty);
      expect(observer.removed, isEmpty);
    });
  });

  group('an alert tap (D36.1)', () {
    /// The app on the navigator the alert paths use. The calendar the tap
    /// pushes is taken off again before a frame builds it: what is checked
    /// is where it goes, not the page.
    Future<void> pumpAlertApp(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: AppNavigator.navigatorKey,
          navigatorObservers: [AppNavigator.routeObserver, observer],
          home: const Scaffold(body: Text('root')),
        ),
      );
    }

    Future<void> pushAlert(WidgetTester tester, Route<void> route) async {
      AppNavigator.navigatorKey.currentState!.push(route);
      await tester.pumpAndSettle();
    }

    for (final kind in [
      NavDestinationKind.calendarOverview,
      NavDestinationKind.calendarReport,
    ]) {
      testWidgets('over a ${kind.name} above the calendar, the calendar is '
          'pushed, named and unstamped', (tester) async {
        addTearDown(() => AppNavigator.pendingCalendarOccurrence.value = null);
        await pumpAlertApp(tester);
        await pushAlert(tester, pageRoute('calendar', destination: calendar));
        final viewRoute = pageRoute('view', destination: NavDestination(kind));
        await pushAlert(tester, viewRoute);
        observer.clear();

        unawaited(
          AppNavigator.toCalendarOccurrence(
            day: DateTime.utc(2026, 10, 30),
            eventId: 'e1',
          ),
        );
        final pushed = observer.pushed.single;
        expect(pushed.settings.name, AppNavigator.occurrenceCalendarRouteName);
        expect(pushed.settings.arguments, isNull);
        expect(viewRoute.isActive, isTrue);
        expect(AppNavigator.pendingCalendarOccurrence.value, isNull);
        AppNavigator.navigatorKey.currentState!.removeRoute(pushed);
        await tester.pumpAndSettle();
      });
    }

    testWidgets('over the calendar alone, it collapses', (tester) async {
      addTearDown(() => AppNavigator.pendingCalendarOccurrence.value = null);
      await pumpAlertApp(tester);
      final calendarRoute = pageRoute('calendar', destination: calendar);
      await pushAlert(tester, calendarRoute);
      await pushAlert(tester, pageRoute('hub', destination: alerts));
      observer.clear();

      unawaited(
        AppNavigator.toCalendarOccurrence(
          day: DateTime.utc(2026, 10, 30),
          eventId: 'e1',
        ),
      );
      await tester.pumpAndSettle();
      expect(observer.pushed, isEmpty);
      expect(calendarRoute.isCurrent, isTrue);
      expect(AppNavigator.pendingCalendarOccurrence.value?.eventId, 'e1');
    });
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
