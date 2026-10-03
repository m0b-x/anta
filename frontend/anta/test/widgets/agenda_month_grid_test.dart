import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:table_calendar/table_calendar.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/utils/calendar_days_of_week.dart';
import 'package:anta/widgets/agenda_month_grid.dart';
import 'package:anta/widgets/calendar_day_cell.dart';

import 'support/layout_errors.dart';

/// The mini month grid of the day list and the overview page. Tier 3 (D6,
/// D7 of `docs/calendar-language-tier-3-roadmap.md`): its weekday row is the
/// calendar page's, and its day numbers — the page's own cells — stay whole
/// at any text scale.
void main() {
  Future<List<FlutterErrorDetails>> pumpGrid(
    WidgetTester tester, {
    CalendarAppearance appearance = const CalendarAppearance(),
    Locale locale = const Locale('en'),
    double textScale = 1.0,
    Size? size,
  }) async {
    if (size != null) {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
    }
    return layoutErrorsDuring(() async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: locale,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: Column(
              children: [
                AgendaMonthGrid(
                  month: DateTime.utc(2026, 10, 1),
                  firstDay: DateTime.utc(2026, 10, 1),
                  lastDay: DateTime.utc(2026, 10, 31),
                  today: DateTime.utc(2026, 10, 3),
                  selectedDay: null,
                  appearance: appearance,
                  hasEntry: (_) => true,
                  barsFor: (_) => null,
                  onDaySelected: (_) {},
                  onPageChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    });
  }

  Finder weekdayLabel(DateTime day) =>
      find.text(DateFormat.E('de').format(day));

  testWidgets('at 200 % German on a narrow phone a two-digit day number '
      'stays on one line inside its chip, and nothing overflows', (
    tester,
  ) async {
    final errors = await pumpGrid(
      tester,
      locale: const Locale('de'),
      textScale: 2.0,
      size: const Size(360, 780),
    );
    expect(errors, isEmpty);

    final number = find.text('28').hitTestable();
    expect(number, findsOneWidget);
    final text = tester.widget<Text>(number);
    expect(text.maxLines, 1);
    expect(text.softWrap, isFalse);
    expect(
      tester.renderObject<RenderParagraph>(number).didExceedMaxLines,
      isFalse,
    );
    // The chip is the nearest box around the number; the number's painted
    // rect sits inside it whatever the font — the test font is twice
    // Roboto's width, which is what makes this a proof rather than a pass.
    final chip = tester.getRect(
      find.ancestor(of: number, matching: find.byType(Container)).first,
    );
    final rect = tester.getRect(number);
    expect(
      chip.width,
      moreOrLessEquals(CalendarDayCell.chipSize, epsilon: 0.01),
    );
    expect(rect.left, greaterThanOrEqualTo(chip.left - 0.01));
    expect(rect.right, lessThanOrEqualTo(chip.right + 0.01));
    expect(rect.top, greaterThanOrEqualTo(chip.top - 0.01));
    expect(rect.bottom, lessThanOrEqualTo(chip.bottom + 0.01));
    expect(rect.height, lessThanOrEqualTo(chip.height + 0.01));
    // The weekday row is whole at this scale too.
    expect(weekdayLabel(DateTime(2026, 9, 28)), findsOneWidget);
  });

  testWidgets('at 100 % a day number is drawn at its own size, where it '
      'was', (tester) async {
    final errors = await pumpGrid(tester);
    expect(errors, isEmpty);
    final number = find.text('28').hitTestable();
    final chip = tester.getRect(
      find.ancestor(of: number, matching: find.byType(Container)).first,
    );
    final rect = tester.getRect(number);
    final style = tester.widget<Text>(number).style!;
    // Not scaled: one line of the number's own font, centred in the chip.
    expect(rect.height, moreOrLessEquals(style.fontSize!, epsilon: 0.01));
    expect(rect.center.dx, moreOrLessEquals(chip.center.dx, epsilon: 0.01));
    expect(rect.center.dy, moreOrLessEquals(chip.center.dy, epsilon: 0.01));
  });

  testWidgets("the weekday row is the page's: 24 dp, labelMedium at 600, "
      'the weekend in the error colour only while weekends are '
      'highlighted', (tester) async {
    await pumpGrid(tester, locale: const Locale('de'));

    final monday = weekdayLabel(DateTime(2026, 9, 28));
    expect(monday, findsOneWidget);
    final theme = Theme.of(tester.element(monday));
    final weekday = tester.widget<Text>(monday);
    expect(weekday.style?.fontSize, theme.textTheme.labelMedium!.fontSize);
    expect(weekday.style?.fontWeight, FontWeight.w600);
    expect(weekday.style?.color, theme.colorScheme.onSurfaceVariant);
    final saturday = weekdayLabel(DateTime(2026, 10, 3));
    expect(
      tester.widget<Text>(saturday).style?.color,
      theme.colorScheme.onSurfaceVariant,
    );
    expect(
      tester
          .widget<TableCalendar<void>>(find.byType(TableCalendar<void>))
          .daysOfWeekHeight,
      CalendarDaysOfWeek.height,
    );

    await pumpGrid(
      tester,
      locale: const Locale('de'),
      appearance: const CalendarAppearance(highlightWeekends: true),
    );
    expect(
      tester.widget<Text>(saturday).style?.color,
      theme.colorScheme.error.withValues(alpha: 0.85),
    );
    expect(
      tester.widget<Text>(monday).style?.color,
      theme.colorScheme.onSurfaceVariant,
    );
  });
}
