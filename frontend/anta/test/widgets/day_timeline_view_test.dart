import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/event_time_formatter.dart';
import 'package:anta/utils/day_timeline_layout.dart';
import 'package:anta/widgets/day_timeline_view.dart';

/// The Timeline's blocks at every text scale: a block is as tall as its
/// event is long, so its text fits the block, never the other way round —
/// one whole title line always (the scale clamped where the ambient line is
/// taller), the time row only where both lines fit — and every block says
/// its time to TalkBack whichever lines it draws. The calendar page and the
/// guide's screen stage overflowed at 2.0 on a day with short events.
void main() {
  final day = DateTime.utc(2026, 8, 10);
  const longTitle =
      'Morning mobility and stretching with the whole team before work';

  CalendarEvent event(String title, int startMinute, int minutes) =>
      CalendarEvent(
        id: title,
        title: title,
        categoryId: 'gym',
        startDate: DateTime.utc(2026, 8, 1),
        rule: const DailyRecurrence(),
        time: EventTime(startMinute: startMinute, durationMinutes: minutes),
      );

  // Overlapping columns, events under the layout's 30-minute floor, the
  // hour, the 2.0 boundary at 75 minutes, two hours.
  final crowded = [
    event(longTitle, 540, 60),
    event('Pills', 540, 5),
    event('Call', 555, 15),
    event('Standup', 570, 30),
    event('Review', 660, 74),
    event('Swim', 780, 75),
    event('Lifting', 900, 120),
    event('Read', 915, 20),
  ];

  Future<void> pump(
    WidgetTester tester,
    List<CalendarEvent> events, {
    required double scale,
    Size size = const Size(412, 915),
    Brightness brightness = Brightness.light,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.light
            ? AppTheme.light()
            : AppTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: DayTimelineView(day: day, events: events, onEventTap: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Finder blockOf(String title) =>
      find.ancestor(of: find.text(title), matching: find.byType(InkWell)).first;

  List<RenderParagraph> paragraphsOf(WidgetTester tester, String title) =>
      tester
          .renderObjectList<RenderParagraph>(
            find.descendant(
              of: blockOf(title),
              matching: find.byType(RichText),
            ),
          )
          .toList();

  int linesOf(WidgetTester tester, String title) =>
      paragraphsOf(tester, title).length;

  /// Every drawn line fits its box: a taller line is sheared at the bottom.
  void expectNoCut(WidgetTester tester, List<CalendarEvent> events) {
    for (final e in events) {
      for (final paragraph in paragraphsOf(tester, e.title)) {
        expect(
          paragraph.textSize.height,
          lessThanOrEqualTo(paragraph.size.height + precisionErrorTolerance),
          reason: e.title,
        );
      }
    }
  }

  /// The block's height is its event's span, floored as the layout floors
  /// it, whatever the text scale.
  void expectDurationHeights(WidgetTester tester, List<CalendarEvent> events) {
    for (final e in events) {
      final minutes = math.max(
        e.time!.durationMinutes!,
        DayTimelineLayout.minBlockMinutes,
      );
      expect(
        tester.getSize(blockOf(e.title)).height,
        moreOrLessEquals(minutes / 60 * DayTimelineView.hourHeight),
        reason: e.title,
      );
    }
  }

  void expectSpokenRanges(WidgetTester tester, List<CalendarEvent> events) {
    final context = tester.element(find.byType(DayTimelineView));
    for (final e in events) {
      final range = EventTimeFormatter.formatRangeOfContext(e.time!, context);
      expect(
        tester.getSemantics(blockOf(e.title)),
        isSemantics(
          label: '${e.title}, $range',
          isButton: true,
          hasTapAction: true,
        ),
        reason: e.title,
      );
    }
  }

  setUp(EventPresence.resetCache);
  tearDown(EventPresence.resetCache);

  testWidgets('at 1.0 the time row starts at 41 minutes, and every block '
      'says its time', (tester) async {
    final handle = tester.ensureSemantics();
    final boundary = [
      event('Forty', 540, 40),
      event('Forty-one', 660, 41),
      event('Forty-two', 780, 42),
      event('Floor', 900, 5),
    ];
    await pump(tester, boundary, scale: 1);
    expect(linesOf(tester, 'Forty'), 1);
    expect(linesOf(tester, 'Forty-one'), 2);
    expect(linesOf(tester, 'Forty-two'), 2);
    expect(linesOf(tester, 'Floor'), 1);
    expectNoCut(tester, boundary);
    expectDurationHeights(tester, boundary);
    expectSpokenRanges(tester, boundary);
    handle.dispose();
  });

  testWidgets('at 1.3 the time row needs 51 minutes and the floor keeps the '
      'ambient scale', (tester) async {
    final boundary = [
      event('Fifty', 540, 50),
      event('Fifty-two', 660, 52),
      event('Floor', 780, 5),
    ];
    await pump(tester, boundary, scale: 1.3);
    expect(linesOf(tester, 'Fifty'), 1);
    expect(linesOf(tester, 'Fifty-two'), 2);
    expect(
      MediaQuery.textScalerOf(tester.element(find.text('Floor'))).scale(1),
      moreOrLessEquals(1.3),
    );
    expectNoCut(tester, boundary);
  });

  for (final (size, brightness) in const [
    (Size(360, 780), Brightness.light),
    (Size(412, 915), Brightness.light),
    (Size(360, 780), Brightness.dark),
  ]) {
    testWidgets('a crowded day at 2.0 on ${size.width.toInt()} '
        '${brightness.name}: one whole title line in every block, the time '
        'from 75 minutes, no overflow', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, crowded, scale: 2, size: size, brightness: brightness);
      expectDurationHeights(tester, crowded);
      expectNoCut(tester, crowded);
      for (final e in crowded) {
        // The title is always drawn, whole.
        expect(paragraphsOf(tester, e.title).first.text.toPlainText(), e.title);
      }
      // The floor's title drawn at the largest scale whose line fits the
      // 28 dp block, under the ambient 2.0.
      final floorScale = MediaQuery.textScalerOf(
        tester.element(find.text('Pills')),
      ).scale(1);
      expect(floorScale, greaterThan(1));
      expect(floorScale, lessThan(2));
      expect(linesOf(tester, longTitle), 1);
      expect(linesOf(tester, 'Review'), 1);
      expect(linesOf(tester, 'Swim'), 2);
      expect(linesOf(tester, 'Lifting'), 2);
      expectSpokenRanges(tester, crowded);
      handle.dispose();
    });
  }
}
