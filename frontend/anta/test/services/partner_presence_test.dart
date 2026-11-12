import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/services/day_summary_resolver.dart';
import 'package:anta/utils/event_agenda.dart';
import 'package:anta/utils/presence_stats.dart';
import 'package:anta/widgets/agenda_list_view.dart';

/// A partner's event is never presence-tracked on this phone
/// (`docs/cloud-share-surfaces-roadmap.md` D15): one gate,
/// `EventPresence.appliesTo` with `isMissed` behind it, and every reader of
/// presence takes it. Each case sets the partner's event beside my own of
/// the same shape, and pins that mine reads as it did.
void main() {
  final l10n = AppLocalizationsEn();
  final day = DateTime.utc(2026, 8, 12);

  /// Tracked and assumed absent: missed on every unmarked day, and marked
  /// missed on [day] as well — a mark of mine left on their event.
  CalendarEvent tracked(String id, {bool fromPartner = false}) => CalendarEvent(
    id: id,
    title: id,
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 1, 1),
    rule: const DailyRecurrence(),
    tracksPresence: true,
    assumeAbsent: true,
    fromPartner: fromPartner,
  );

  final mine = tracked('mine');
  final theirs = tracked('theirs', fromPartner: true);

  setUp(() {
    EventPresence.updateCache(
      byEvent: {
        'mine': {day: PresenceStatus.missed},
        'theirs': {day: PresenceStatus.missed},
      },
    );
  });
  tearDown(EventPresence.resetCache);

  test('the gate: never tracked, never missed — its stored mark unread', () {
    expect(EventPresence.appliesTo(theirs), isFalse);
    expect(EventPresence.isMissed(theirs, day), isFalse);
    expect(EventPresence.isMissed(theirs, DateTime.utc(2026, 8, 13)), isFalse);
    expect(EventPresence.marksFor('theirs'), {day: PresenceStatus.missed});

    expect(EventPresence.appliesTo(mine), isTrue);
    expect(EventPresence.isMissed(mine, day), isTrue);
    expect(EventPresence.isMissed(mine, DateTime.utc(2026, 8, 13)), isTrue);
  });

  test("the day panel's entry draws the plain tail", () {
    final provider = EventSummaryProvider(l10n);
    final entry = provider.entryFor(theirs, day);
    expect((entry.presenceTracked, entry.missed), (false, false));

    final own = provider.entryFor(mine, day);
    expect((own.presenceTracked, own.missed), (true, true));
  });

  test("the agenda's and the overview's entries: untracked, and never "
      'hidden as missed', () {
    final entries = AgendaListView.eventDayEntries(
      [
        EventOccurrence(event: mine, day: day),
        EventOccurrence(event: theirs, day: day),
      ],
      l10n,
      false,
      showRecurrenceLabels: false,
      missedDisplay: CalendarMissedDisplay.faded,
    );
    expect(
      [for (final e in entries) (e.eventId, e.presenceTracked, e.missed)],
      [('mine', true, true), ('theirs', false, false)],
    );

    final hidden = AgendaListView.eventDayEntries(
      [
        EventOccurrence(event: mine, day: day),
        EventOccurrence(event: theirs, day: day),
      ],
      l10n,
      false,
      showRecurrenceLabels: false,
      missedDisplay: CalendarMissedDisplay.hidden,
    );
    expect([for (final e in hidden) e.eventId], ['theirs']);

    final marks = AgendaListView.eventDayMarks([
      EventOccurrence(event: mine, day: day),
      EventOccurrence(event: theirs, day: day),
    ], missedDisplay: CalendarMissedDisplay.faded);
    expect([for (final m in marks) m.missed], [true, false]);
  });

  test('the agenda counts it as an event, never as a missed one', () {
    final summaries = EventAgenda.categorySummariesOf([
      EventOccurrence(event: mine, day: day),
      EventOccurrence(event: theirs, day: day),
    ], hideMissed: true);
    expect(summaries.single.occurrences.map((o) => o.event.id), ['theirs']);
  });

  test('no adherence figure', () {
    final today = DateTime.utc(2026, 8, 20);
    expect(PresenceAdherence.compute(theirs, today: today), isNull);
    expect(PresenceAdherence.compute(mine, today: today), isNotNull);
  });
}
