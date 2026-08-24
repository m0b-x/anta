import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/utils/event_agenda.dart';
import 'package:anta/widgets/agenda_list_view.dart';
import 'package:anta/widgets/markdown_inline_text.dart';

/// Regression coverage for the summary card clipping bug: a category card's
/// subtitle used to be one `Text` inside an `IntrinsicHeight`-forced tile, so
/// a subtitle long enough to wrap sliced its second line in half instead of
/// growing the card. The date range now renders on its own line, and the
/// card grows to whatever height its content actually needs.
void main() {
  final l10n = AppLocalizationsEn();

  setUpAll(() => initializeDateFormatting('en'));

  CalendarEvent event(String id, String title, String categoryId) =>
      CalendarEvent(
        id: id,
        title: title,
        categoryId: categoryId,
        startDate: DateTime.utc(2026, 8, 26),
        rule: const DailyRecurrence(),
      );

  Future<void> pumpRows(WidgetTester tester, List<AgendaRow> rows) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: AgendaListView(
              rows: rows,
              onDaySelected: (_) {},
              onEditEvent: (_, _) {},
              onOpenNote: (_) {},
              emptyTitle: '',
              emptyHint: '',
            ),
          ),
        ),
      ),
    );
  }

  /// The range `Text`'s rect must sit fully inside its card's rect — the
  /// exact geometry the old `IntrinsicHeight` bug violated, since the Card's
  /// own reported height came from a too-short intrinsic estimate while the
  /// wrapped line still painted at the taller, correct offset.
  void expectNotClipped(WidgetTester tester, Finder cardFinder, String text) {
    final cardRect = tester.getRect(cardFinder);
    final textFinder = find.descendant(
      of: cardFinder,
      matching: find.text(text),
    );
    expect(textFinder, findsOneWidget);
    final textRect = tester.getRect(textFinder);

    expect(textRect.top, greaterThanOrEqualTo(cardRect.top));
    expect(textRect.bottom, lessThanOrEqualTo(cardRect.bottom + 0.5));

    // Confirms the range rendered in full rather than being silently
    // ellipsized — the "must always be visible" requirement, distinct from
    // the clipping check above.
    final paragraph = tester.renderObject<RenderParagraph>(textFinder);
    expect(paragraph.didExceedMaxLines, isFalse);
  }

  testWidgets(
    'a long date range renders on its own line and is never clipped',
    (tester) async {
      final summary = EventCategorySummary(
        categoryId: 'gym',
        occurrences: [
          for (var i = 0; i < 90; i++)
            EventOccurrence(
              event: event('e1', 'Leg day', 'gym'),
              day: DateTime.utc(2026, 8, 26).add(Duration(days: i)),
            ),
        ],
        eventCount: 1,
        first: DateTime.utc(2026, 8, 26),
        last: DateTime.utc(2026, 11, 23),
      );

      final rows = buildAgendaRows(
        occurrences: const [],
        holidayDays: const [],
        fastingDays: const [],
        l10n: l10n,
        showRecurrenceLabels: true,
        missedDisplay: CalendarMissedDisplay.faded,
        eventSummaries: [summary],
      );
      final row = rows.single as AgendaEventSummaryRow;

      await pumpRows(tester, rows);

      // Line 1 is the count portion only — the range moved off it.
      expect(row.entry.subtitle, '1 event · 90× in window');
      expect(row.rangeLabel, 'Aug 26 – Nov 23');
      expect(find.text('1 event · 90× in window'), findsOneWidget);

      expectNotClipped(tester, find.byType(Card), 'Aug 26 – Nov 23');
    },
  );

  testWidgets('a short-subtitle card stays compact beside a long one', (
    tester,
  ) async {
    final longSummary = EventCategorySummary(
      categoryId: 'gym',
      occurrences: [
        EventOccurrence(
          event: event('e1', 'Leg day', 'gym'),
          day: DateTime.utc(2026, 8, 26),
        ),
      ],
      eventCount: 1,
      first: DateTime.utc(2026, 8, 26),
      last: DateTime.utc(2026, 11, 23),
    );
    final shortSummary = EventCategorySummary(
      categoryId: 'mobility',
      occurrences: [
        EventOccurrence(
          event: event('e2', 'Stretch', 'mobility'),
          day: DateTime.utc(2026, 8, 26),
        ),
      ],
      eventCount: 1,
      first: DateTime.utc(2026, 8, 26),
      last: DateTime.utc(2026, 8, 26),
    );

    final rows = buildAgendaRows(
      occurrences: const [],
      holidayDays: const [],
      fastingDays: const [],
      l10n: l10n,
      showRecurrenceLabels: true,
      missedDisplay: CalendarMissedDisplay.faded,
      // Both cards share the event band (priority 0); insertion order is the
      // tie-break, so `longSummary` renders first — see
      // `agenda_rows_test.dart`'s "cards at equal priority keep a stable
      // order" coverage.
      eventSummaries: [longSummary, shortSummary],
    );

    await pumpRows(tester, rows);

    final cardFinder = find.byType(Card);
    expect(cardFinder, findsNWidgets(2));

    expectNotClipped(tester, cardFinder.at(0), 'Aug 26 – Nov 23');
    expectNotClipped(tester, cardFinder.at(1), 'Aug 26 – Aug 26');

    final longHeight = tester.getRect(cardFinder.at(0)).height;
    final shortHeight = tester.getRect(cardFinder.at(1)).height;

    // Both cards carry the same two-line shape (count line + range line), so
    // they should be the same height — neither stretched to match the
    // other's content, and neither padded out with unused space.
    expect(shortHeight, closeTo(longHeight, 0.5));
  });

  /// The range lines are both `maxLines: 1`, so they can no longer wrap and
  /// no longer exercise the `IntrinsicHeight` half of the fix on their own.
  /// A description can still grow — `MarkdownInlineText` wraps to two lines —
  /// so this is the case that actually fails if the tile is put back inside
  /// an `IntrinsicHeight`.
  testWidgets('a wrapping description grows the card instead of clipping', (
    tester,
  ) async {
    final described = CalendarEvent(
      id: 'e3',
      title: 'Leg day',
      categoryId: 'gym',
      startDate: DateTime.utc(2026, 8, 26),
      rule: const DailyRecurrence(),
      description:
          'Back squat five by five, then romanian deadlifts and a long '
          'accessory block that has to wrap onto a second rendered line.',
    );

    final rows = buildAgendaRows(
      occurrences: [
        EventOccurrence(event: described, day: DateTime.utc(2026, 8, 26)),
      ],
      holidayDays: const [],
      fastingDays: const [],
      l10n: l10n,
      showRecurrenceLabels: true,
      missedDisplay: CalendarMissedDisplay.faded,
    );

    await pumpRows(tester, rows);

    final cardFinder = find.byType(Card);
    expect(cardFinder, findsOneWidget);

    final descriptionFinder = find.descendant(
      of: cardFinder,
      matching: find.byType(MarkdownInlineText),
    );
    expect(descriptionFinder, findsOneWidget);

    final cardRect = tester.getRect(cardFinder);
    final descriptionRect = tester.getRect(descriptionFinder);

    // The description actually wrapped — otherwise the assertion below would
    // pass trivially on a one-line tile and prove nothing.
    expect(descriptionRect.height, greaterThan(20.0));
    expect(descriptionRect.bottom, lessThanOrEqualTo(cardRect.bottom + 0.5));
  });
}
