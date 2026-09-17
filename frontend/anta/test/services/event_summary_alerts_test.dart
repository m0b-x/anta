import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/agenda_search_text.dart';
import 'package:anta/services/day_summary_resolver.dart';

/// "removed after it rings" is composed **once**, in the subtitle, and the
/// agenda's search text mirrors it — the rule that keeps the agenda findable
/// by whatever a row shows.
void main() {
  final l10n = AppLocalizationsEn();

  setUpAll(() => initializeDateFormatting('en'));

  final day = DateTime.utc(2026, 9, 20);

  CalendarEvent eventOf({bool removeAfterAlert = false}) => CalendarEvent(
    id: 'e1',
    title: 'Wake up',
    categoryId: 'other',
    startDate: day,
    rule: const OneTimeRecurrence(),
    time: const EventTime(startMinute: 7 * 60),
    removeAfterAlert: removeAfterAlert,
  );

  String? subtitleOf(CalendarEvent event) {
    return EventSummaryProvider(l10n).summaryFor(day, [event]).first.subtitle;
  }

  test('the subtitle says so, last', () {
    final subtitle = subtitleOf(eventOf(removeAfterAlert: true));

    expect(subtitle, endsWith('removed after it rings'));
    expect(subtitle, contains('7:00'));
  });

  test('an ordinary event says nothing of the kind', () {
    expect(subtitleOf(eventOf()), isNot(contains('removed')));
  });

  test('the agenda can be searched for it', () {
    expect(
      AgendaSearchText.forEvent(eventOf(removeAfterAlert: true), l10n),
      contains('removed after it rings'),
    );
    expect(
      AgendaSearchText.forEvent(eventOf(), l10n),
      isNot(contains('removed')),
    );
  });
}
