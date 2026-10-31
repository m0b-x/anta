import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/alert_payload.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/models/nav_destination.dart';
import 'package:anta/models/overview_period.dart';
import 'package:anta/pages/calendar_report_page.dart';
import 'package:anta/services/app_navigator.dart';

/// Where a digest's tap lands (S4): a report digest's payload names the
/// report page, every other — and every entry armed before the key existed
/// — the overview's List. The routes carry plain bodies stamped as the real
/// pages are, so what is checked is the navigator's decision, never a page.
void main() {
  late _RecordingObserver observer;

  const overview = NavDestination(NavDestinationKind.calendarOverview);
  const report = NavDestination(NavDestinationKind.calendarReport);

  setUp(() => observer = _RecordingObserver());
  tearDown(() {
    AppNavigator.pendingOverviewLook.value = null;
    AppNavigator.pendingReportLook.value = null;
  });

  Route<void> pageRoute(String label, {NavDestination? destination}) {
    return MaterialPageRoute<void>(
      builder: (_) => Scaffold(body: Text(label)),
      settings: destination == null
          ? null
          : RouteSettings(name: destination.kind.name, arguments: destination),
    );
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: AppNavigator.navigatorKey,
        navigatorObservers: [AppNavigator.routeObserver, observer],
        home: const Scaffold(body: Text('root')),
      ),
    );
  }

  Future<void> push(WidgetTester tester, Route<void> route) async {
    AppNavigator.navigatorKey.currentState!.push(route);
    await tester.pumpAndSettle();
  }

  final weekStart = DateTime.utc(2026, 10, 19);
  final weekEnd = DateTime.utc(2026, 10, 25);

  AlertPayload digestPayload({String? page}) {
    final json = AlertPayload(
      database: 'gym_notes',
      eventId: '',
      alertId: 'r1',
      dayUtcMs: weekStart.millisecondsSinceEpoch,
      osId: 41,
      mode: AlertMode.notify,
      title: 'Weekly report',
      timeLabel: '09:00',
      categoryId: '',
      isDigest: true,
      digestId: 'r1',
      spanStartMs: weekStart.millisecondsSinceEpoch,
      spanEndMs: weekEnd.millisecondsSinceEpoch,
      categoryIdsCsv: 'gym',
    ).toJson()..addAll({'pg': ?page});
    return AlertPayload.fromJson(json)!;
  }

  group('the period a report span reads as', () {
    test('seven days are the week', () {
      expect(
        AppNavigator.reportPeriodOf(start: weekStart, end: weekEnd),
        OverviewWeekPeriod(weekStart),
      );
    });

    test('a whole calendar month is the month, February included', () {
      expect(
        AppNavigator.reportPeriodOf(
          start: DateTime.utc(2026, 10, 1),
          end: DateTime.utc(2026, 10, 31),
        ),
        const OverviewMonthPeriod(2026, 10),
      );
      expect(
        AppNavigator.reportPeriodOf(
          start: DateTime.utc(2028, 2, 1),
          end: DateTime.utc(2028, 2, 29),
        ),
        const OverviewMonthPeriod(2028, 2),
      );
    });

    test('anything else is the span as dates', () {
      final start = DateTime.utc(2026, 10, 2);
      final end = DateTime.utc(2026, 10, 31);
      expect(
        AppNavigator.reportPeriodOf(start: start, end: end),
        OverviewCustomPeriod(start, end),
      );
      expect(
        AppNavigator.reportPeriodOf(
          start: DateTime.utc(2026, 10, 1),
          end: DateTime.utc(2026, 10, 30),
        ),
        OverviewCustomPeriod(
          DateTime.utc(2026, 10, 1),
          DateTime.utc(2026, 10, 30),
        ),
      );
    });
  });

  group('a digest tap', () {
    testWidgets('of a report collapses onto a live report and publishes '
        'the look', (tester) async {
      await pumpApp(tester);
      await push(tester, pageRoute('report', destination: report));
      await push(tester, pageRoute('above'));

      unawaited(
        AppNavigator.toDigestTarget(
          payload: digestPayload(page: AlertPayload.reportPage),
          span: (start: weekStart, end: weekEnd),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('report'), findsOneWidget);
      expect(find.text('above'), findsNothing);
      final look = AppNavigator.pendingReportLook.value;
      expect(look?.period, OverviewWeekPeriod(weekStart));
      expect(look?.categoryIds, {'gym'});
      expect(AppNavigator.pendingOverviewLook.value, isNull);
    });

    testWidgets('of a report with none open pushes the stamped report with '
        'the look in hand', (tester) async {
      await pumpApp(tester);
      observer.pushed.clear();

      unawaited(
        AppNavigator.toDigestTarget(
          payload: digestPayload(page: AlertPayload.reportPage),
          span: (start: weekStart, end: weekEnd),
        ),
      );
      final pushed = observer.pushed.single as MaterialPageRoute<void>;
      final page =
          pushed.builder(AppNavigator.navigatorKey.currentContext!)
              as CalendarReportPage;

      expect(pushed.settings.arguments, report);
      expect(page.look?.period, OverviewWeekPeriod(weekStart));
      expect(page.look?.categoryIds, {'gym'});
      expect(AppNavigator.pendingReportLook.value, isNull);
      // Taken off before a frame builds a page this suite has no bloc for.
      AppNavigator.navigatorKey.currentState!.removeRoute(pushed);
      await tester.pumpAndSettle();
    });

    testWidgets('without a page lands on the overview, as an older entry '
        'always did', (tester) async {
      await pumpApp(tester);
      await push(tester, pageRoute('overview', destination: overview));
      await push(tester, pageRoute('report', destination: report));

      unawaited(
        AppNavigator.toDigestTarget(
          payload: digestPayload(),
          span: (start: weekStart, end: weekEnd),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('overview'), findsOneWidget);
      final look = AppNavigator.pendingOverviewLook.value;
      expect(look?.start, weekStart);
      expect(look?.end, weekEnd);
      expect(look?.categoryIds, {'gym'});
      expect(AppNavigator.pendingReportLook.value, isNull);
    });
  });
}

class _RecordingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}
