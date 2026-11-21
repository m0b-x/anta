import 'package:flutter_test/flutter_test.dart';

import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/day_summary_entry.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/day_summary_resolver.dart';
import 'package:anta/services/note_money_ledger_service.dart';

/// The day panel's money line counts a linked note for an event only when
/// the note is mine or the event is the partner's too (review A11, second
/// leg): an event of mine linked, before the picker listed my notes alone,
/// to a partner's note never brings the partner's money into my day.
void main() {
  final day = DateTime.utc(2026, 8, 10);

  CalendarEvent linked(String id, String noteId, {bool fromPartner = false}) =>
      CalendarEvent(
        id: id,
        title: id,
        categoryId: 'gym',
        startDate: day,
        rule: const OneTimeRecurrence(),
        noteId: noteId,
        fromPartner: fromPartner,
      );

  setUp(
    () => NoteMoneyLedgerService.seedForTesting({
      'theirs': (balance: 800, net: 800, title: 'Theirs', fromPartner: true),
      'mine': (balance: -500, net: -500, title: 'Mine', fromPartner: false),
    }),
  );
  tearDown(NoteMoneyLedgerService.reset);

  Iterable<DaySummaryEntry> summaryOf(List<CalendarEvent> events) =>
      MoneyDaySummaryProvider(AppLocalizationsEn()).summaryFor(day, events);

  test('an event of mine never counts a partner\'s note', () {
    expect(summaryOf([linked('e1', 'theirs')]), isEmpty);
    expect(
      summaryOf([linked('e1', 'theirs'), linked('e2', 'mine')]).single.subtitle,
      'Mine',
    );
  });

  test('the partner\'s own event keeps its money, whichever event of the day '
      'names the note first', () {
    expect(
      summaryOf([linked('p1', 'theirs', fromPartner: true)]).single.subtitle,
      'Theirs',
    );
    expect(
      summaryOf([
        linked('e1', 'theirs'),
        linked('p1', 'theirs', fromPartner: true),
      ]).single.subtitle,
      'Theirs',
    );
  });
}
