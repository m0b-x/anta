import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/partner_look.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/models/share_settings.dart';
import 'package:anta/services/event_time_formatter.dart';
import 'package:anta/utils/day_timeline_layout.dart';
import 'package:anta/utils/marker_contrast.dart';
import 'package:anta/widgets/day_timeline_view.dart';
import 'package:anta/widgets/user_avatar.dart';

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
    PartnerLook partnerLook = const PartnerLook(),
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
          body: DayTimelineView(
            day: day,
            events: events,
            onEventTap: (_) {},
            partnerLook: partnerLook,
          ),
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

  testWidgets('a partner\'s block and all-day chip say whose they are '
      'first; mine say what they always said', (tester) async {
    final handle = tester.ensureSemantics();
    CalendarEvent theirs(CalendarEvent of) => CalendarEvent(
      id: of.id,
      title: of.title,
      categoryId: of.categoryId,
      startDate: of.startDate,
      rule: of.rule,
      time: of.time,
      fromPartner: true,
    );
    final shift = theirs(event('Night shift', 600, 60));
    final trip = theirs(
      CalendarEvent(
        id: 'trip',
        title: 'Trip',
        categoryId: 'gym',
        startDate: DateTime.utc(2026, 8, 1),
        rule: const DailyRecurrence(),
      ),
    );
    final mine = event('Swim', 780, 75);
    await pump(
      tester,
      [shift, trip, mine],
      scale: 1,
      partnerLook: const PartnerLook(name: 'Maria'),
    );

    final context = tester.element(find.byType(DayTimelineView));
    String range(CalendarEvent e) =>
        EventTimeFormatter.formatRangeOfContext(e.time!, context);
    expect(
      tester.getSemantics(blockOf('Night shift')),
      isSemantics(
        label: 'From Maria, Night shift, ${range(shift)}',
        isButton: true,
        hasTapAction: true,
      ),
    );
    expectSpokenRanges(tester, [mine]);
    expect(find.bySemanticsLabel('From Maria, Trip'), findsOneWidget);
    handle.dispose();
  });

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

  // Slice A2: a partner's block and chip wear the look in the box mine
  // takes — the Outlined ring on the Material's foreground, the Avatar face
  // at the end of the title line — so nothing on the panel moves.
  group('a partner\'s look', () {
    const phone = Size(360, 780);
    const yellow = 0xFFFDD835;
    const brown = 0xFF6D4C41;
    const blue = 0xFF1E88E5;

    CalendarEvent of(
      String title,
      int? startMinute,
      int minutes, {
      bool fromPartner = false,
      int colorValue = blue,
    }) => CalendarEvent(
      id: title,
      title: title,
      categoryId: 'gym',
      startDate: DateTime.utc(2026, 8, 1),
      rule: const DailyRecurrence(),
      time: startMinute == null
          ? null
          : EventTime(startMinute: startMinute, durationMinutes: minutes),
      colorValue: colorValue,
      fromPartner: fromPartner,
    );

    // A two-column hour, a two-column quarter hour under the layout's
    // floor, a long two-hour block of theirs, one of mine alone, and an
    // all-day chip each.
    List<CalendarEvent> day({required bool partner}) => [
      of('Holiday', null, 0),
      of('Birthday', null, 0, fromPartner: partner),
      of('Gym', 600, 60),
      of('Night shift handover', 600, 60, fromPartner: partner),
      of('Pills', 720, 15),
      of('Call', 720, 15, fromPartner: partner),
      of(longTitle, 840, 120, fromPartner: partner),
      of('Swim', 1020, 75),
    ];
    const theirs = ['Night shift handover', 'Call', longTitle];

    Finder chipOf(String title) =>
        find.ancestor(of: find.text(title), matching: find.byType(ActionChip));

    Finder faceIn(Finder of) =>
        find.descendant(of: of, matching: find.byType(UserAvatar));

    Material materialOf(WidgetTester tester, String title) => tester
        .widgetList<Material>(
          find.ancestor(of: blockOf(title), matching: find.byType(Material)),
        )
        .first;

    double ratio(Color a, Color b) => MarkerContrast.contrastRatio(
      a.computeLuminance(),
      b.computeLuminance(),
    );

    Map<String, Rect> boxes(WidgetTester tester, List<CalendarEvent> events) =>
        {
          for (final e in events)
            e.title: tester.getRect(
              e.time == null ? chipOf(e.title) : blockOf(e.title),
            ),
        };

    for (final scale in const [1.0, 1.3, 2.0]) {
      testWidgets('at $scale every look keeps every block\'s and chip\'s box '
          'and every title\'s place', (tester) async {
        await pump(tester, day(partner: false), scale: scale, size: phone);
        final mine = boxes(tester, day(partner: false));
        final titles = {
          for (final e in day(partner: false))
            e.title: tester.getRect(find.text(e.title)),
        };

        for (final look in ShareEventLook.values) {
          await pump(
            tester,
            day(partner: true),
            scale: scale,
            size: phone,
            partnerLook: PartnerLook(look: look),
          );
          expect(boxes(tester, day(partner: true)), mine, reason: look.name);
          for (final e in day(partner: true)) {
            final title = tester.getRect(find.text(e.title));
            final avatarBlock =
                look == ShareEventLook.avatar && theirs.contains(e.title);
            // Under the Avatar look the title keeps its place and gives the
            // face its room at the end; elsewhere it is mine to the pixel.
            expect(
              avatarBlock ? title.topLeft : title,
              avatarBlock ? titles[e.title]!.topLeft : titles[e.title],
              reason: '${look.name} ${e.title}',
            );
          }
        }
      });
    }

    testWidgets('the Avatar face is 20 dp, at the title line\'s end and '
        'centred on it, and the title gives it 24 dp', (tester) async {
      for (final scale in const [1.0, 1.3, 2.0]) {
        await pump(
          tester,
          day(partner: true),
          scale: scale,
          size: phone,
          partnerLook: const PartnerLook(look: ShareEventLook.avatar),
        );
        for (final title in theirs) {
          final block = tester.getRect(blockOf(title));
          final face = tester.getRect(faceIn(blockOf(title)));
          final line = tester.getRect(find.text(title));
          final reason = '$scale $title';
          expect(face.size, const Size.square(20), reason: reason);
          // The block's 6 dp end padding.
          expect(face.right, moreOrLessEquals(block.right - 6), reason: reason);
          expect(
            face.center.dy,
            moreOrLessEquals(line.center.dy, epsilon: 1),
            reason: reason,
          );
          final paragraph = tester.renderObject<RenderParagraph>(
            find.text(title),
          );
          expect(
            paragraph.constraints.maxWidth,
            moreOrLessEquals(
              block.width -
                  3 -
                  12 -
                  2 * RowMetrics.partnerAvatarRadius -
                  DayTimelineView.partnerFaceGap,
            ),
            reason: reason,
          );
        }
        // The chip's face takes the glyph's slot.
        expect(
          tester.getSize(faceIn(chipOf('Birthday'))),
          const Size.square(20),
        );
        expect(faceIn(blockOf('Gym')), findsNothing);
        expect(faceIn(chipOf('Holiday')), findsNothing);
      }
    });

    testWidgets('the face is dropped in a block under 64 dp of content: four '
        'columns on a 360 dp phone, never three', (tester) async {
      List<CalendarEvent> columns(int count, int start) => [
        for (var i = 0; i < count; i++)
          of('C$count-$i', start, 60, fromPartner: true),
      ];
      await pump(
        tester,
        [...columns(3, 540), ...columns(4, 720)],
        scale: 1,
        size: phone,
        partnerLook: const PartnerLook(look: ShareEventLook.avatar),
      );
      for (var i = 0; i < 3; i++) {
        expect(faceIn(blockOf('C3-$i')), findsOneWidget);
      }
      for (var i = 0; i < 4; i++) {
        expect(
          tester.getSize(blockOf('C4-$i')).width - 3 - 12,
          lessThan(
            2 * RowMetrics.partnerAvatarRadius +
                DayTimelineView.partnerFaceGap +
                DayTimelineView.partnerFaceMinTitleWidth,
          ),
        );
        expect(faceIn(blockOf('C4-$i')), findsNothing);
      }
    });

    for (final (brightness, color) in const [
      (Brightness.light, yellow),
      (Brightness.dark, brown),
    ]) {
      testWidgets('Outlined in ${brightness.name}: a hollow block and chip '
          'whose ring meets 3:1 on the ground; mine as they were', (
        tester,
      ) async {
        await pump(
          tester,
          [
            of('Mine', 600, 60, colorValue: color),
            of('Theirs', 600, 60, fromPartner: true, colorValue: color),
            of('My day', null, 0, colorValue: color),
            of('Their day', null, 0, fromPartner: true, colorValue: color),
          ],
          scale: 1,
          size: phone,
          brightness: brightness,
          partnerLook: const PartnerLook(),
        );
        final context = tester.element(find.byType(DayTimelineView));
        final ground = Theme.of(context).colorScheme.pageGround;
        final raw = Color(color);
        // Each colour is one that fails the floor raw on its theme's ground.
        expect(ratio(raw, ground), lessThan(3));

        final block = materialOf(tester, 'Theirs');
        expect(block.color, Colors.transparent);
        final side = (block.shape! as RoundedRectangleBorder).side;
        expect(side.width, FormMetrics.shareOutlineWidth);
        expect(side.color, MarkerContrast.atLeast(raw, ground));
        expect(ratio(side.color, ground), greaterThanOrEqualTo(3));

        final chip = tester.widget<ActionChip>(chipOf('Their day'));
        expect(chip.backgroundColor, Colors.transparent);
        expect(chip.side!.width, 1.0);
        expect(ratio(chip.side!.color, ground), greaterThanOrEqualTo(3));

        final mine = materialOf(tester, 'Mine');
        expect(mine.color, raw.withValues(alpha: 0.16));
        expect(mine.shape, isNull);
        expect(mine.borderRadius, BorderRadius.circular(6));
        final myChip = tester.widget<ActionChip>(chipOf('My day'));
        expect(myChip.side, isNull);
        expect(myChip.backgroundColor, raw.withValues(alpha: 0.12));
        expect(faceIn(find.byType(DayTimelineView)), findsNothing);
      });
    }

    testWidgets('Like mine draws a partner\'s block and chip as mine', (
      tester,
    ) async {
      await pump(
        tester,
        [
          of('Theirs', 600, 60, fromPartner: true, colorValue: yellow),
          of('Their day', null, 0, fromPartner: true, colorValue: yellow),
        ],
        scale: 1,
        size: phone,
        partnerLook: const PartnerLook(look: ShareEventLook.plain),
      );
      final block = materialOf(tester, 'Theirs');
      expect(block.color, const Color(yellow).withValues(alpha: 0.16));
      expect(block.shape, isNull);
      expect(tester.widget<ActionChip>(chipOf('Their day')).side, isNull);
      expect(faceIn(find.byType(DayTimelineView)), findsNothing);
    });
  });

  // Today's now line is drawn over the blocks; it once swallowed the tap
  // wherever it crossed one, and the guide's Timeline test went red on any
  // run whose clock put the line through the block's label.
  testWidgets('a tap where the now line crosses a block opens its event', (
    tester,
  ) async {
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final minute = now.hour * 60 + now.minute;
    // An hour around now that never leaves the day.
    final start = math.min(math.max(minute - 30, 0), 23 * 60);
    final tapped = <String>[];
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: DayTimelineView(
            day: today,
            events: [
              CalendarEvent(
                id: 'now',
                title: 'Now',
                categoryId: 'gym',
                startDate: today,
                time: EventTime(startMinute: start, durationMinutes: 60),
              ),
            ],
            onEventTap: (event) => tapped.add(event.id),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(blockOf('Now'));
    await tester.pumpAndSettle();

    final line = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_NowIndicator',
    );
    expect(line, findsOneWidget);
    final block = tester.getRect(blockOf('Now'));
    final crossing = Offset(block.center.dx, tester.getRect(line).center.dy);
    expect(block.contains(crossing), isTrue);
    await tester.tapAt(crossing);
    await tester.pumpAndSettle();
    expect(tapped, ['now']);
  });
}
