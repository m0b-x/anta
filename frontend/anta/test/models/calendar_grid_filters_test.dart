import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_grid_filters.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/models/upcoming_agenda_filters.dart';

/// `CalendarGridFilters` is the whole calendar grid's narrowing rule, and its
/// two contracts are easy to break quietly: **every axis reads the event
/// alone** (so the bloc can apply it once per change rather than once per
/// candidate per day), and **an inactive filter hands back the very list it
/// was given** (so the bloc's `identical`-guarded partition and the widgets'
/// `identical` rebuild gates behave exactly as they did before filters
/// existed).
void main() {
  final today = DateTime.utc(2026, 9, 1);

  CalendarEvent event({
    String id = 'e1',
    String categoryId = 'gym',
    RecurrenceRule rule = const DailyRecurrence(),
    DateTime? endDate,
    EventTime? time,
    String? noteId,
    String? description,
    bool tracksPresence = false,
    bool countOccurrences = false,
    int priority = kDefaultEventPriority,
  }) {
    return CalendarEvent(
      id: id,
      title: 'Event $id',
      categoryId: categoryId,
      startDate: DateTime.utc(2026, 1, 1),
      rule: rule,
      endDate: endDate,
      time: time,
      noteId: noteId,
      description: description,
      tracksPresence: tracksPresence,
      countOccurrences: countOccurrences,
      priority: priority,
    );
  }

  bool allows(CalendarGridFilters filters, CalendarEvent e) =>
      filters.allows(e, todayUtc: today);

  group('the filter off', () {
    test('is the default, and counts nothing', () {
      expect(CalendarGridFilters.none.isEmpty, isTrue);
      expect(CalendarGridFilters.none.activeCount, 0);
    });

    test('hands back the same list instance', () {
      final events = [event()];

      expect(
        identical(CalendarGridFilters.none.apply(events, todayUtc: today), events),
        isTrue,
      );
    });

    test('an empty priority set means every priority, not none', () {
      const filters = CalendarGridFilters(priorities: {});

      expect(filters.isEmpty, isTrue);
      expect(allows(filters, event(priority: kMinEventPriority)), isTrue);
      expect(allows(filters, event(priority: kMaxEventPriority)), isTrue);
    });
  });

  group('axes', () {
    test('recurrence keeps exactly one side', () {
      const recurring = CalendarGridFilters(
        eventType: AgendaEventType.recurring,
      );
      const oneTime = CalendarGridFilters(eventType: AgendaEventType.oneTime);
      final daily = event(rule: const DailyRecurrence());
      final once = event(rule: const OneTimeRecurrence());

      expect(allows(recurring, daily), isTrue);
      expect(allows(recurring, once), isFalse);
      expect(allows(oneTime, daily), isFalse);
      expect(allows(oneTime, once), isTrue);
    });

    /// A set of explicit dates is a list of distinct occasions, so it counts
    /// as recurring — the same call `EventAgenda` and `EventPresence` make.
    test('specific dates count as recurring', () {
      const filters = CalendarGridFilters(eventType: AgendaEventType.recurring);
      final dates = event(
        rule: SpecificDatesRecurrence(dates: {DateTime.utc(2026, 3, 4)}),
      );

      expect(allows(filters, dates), isTrue);
    });

    test('timing splits on the time annotation', () {
      const timed = CalendarGridFilters(timing: CalendarEventTiming.timed);
      const allDay = CalendarGridFilters(timing: CalendarEventTiming.allDay);
      final at9 = event(time: const EventTime(startMinute: 540));
      final whenever = event();

      expect(allows(timed, at9), isTrue);
      expect(allows(timed, whenever), isFalse);
      expect(allows(allDay, at9), isFalse);
      expect(allows(allDay, whenever), isTrue);
    });

    test('priorities keep only the selected levels', () {
      const filters = CalendarGridFilters(priorities: {1, 2});

      expect(allows(filters, event(priority: 1)), isTrue);
      expect(allows(filters, event(priority: 2)), isTrue);
      expect(allows(filters, event(priority: 3)), isFalse);
    });

    /// The gate is `EventPresence.appliesTo`, not the bare flag: a one-time
    /// event has no attendance to keep, so it is never a tracked commitment
    /// however its column reads.
    test('tracked-only follows presence applicability, not the flag', () {
      const filters = CalendarGridFilters(trackedOnly: true);

      expect(allows(filters, event(tracksPresence: true)), isTrue);
      expect(allows(filters, event(tracksPresence: false)), isFalse);
      expect(
        allows(
          filters,
          event(tracksPresence: true, rule: const OneTimeRecurrence()),
        ),
        isFalse,
      );
    });

    test('linked-notes-only keeps events carrying a note id', () {
      const filters = CalendarGridFilters(linkedNotesOnly: true);

      expect(allows(filters, event(noteId: 'n1')), isTrue);
      expect(allows(filters, event()), isFalse);
    });

    test('hide-ended drops only events whose end date is past', () {
      const filters = CalendarGridFilters(hideEnded: true);

      expect(allows(filters, event(endDate: DateTime.utc(2026, 8, 31))), isFalse);
      // Ending today is not ended: the event still occurs on the day the
      // calendar is showing.
      expect(allows(filters, event(endDate: today)), isTrue);
      expect(allows(filters, event(endDate: DateTime.utc(2026, 12, 31))), isTrue);
      expect(allows(filters, event()), isTrue);
    });

    test('hidden categories are a denylist', () {
      const filters = CalendarGridFilters(hiddenCategoryIds: {'gym'});

      expect(allows(filters, event(categoryId: 'gym')), isFalse);
      expect(allows(filters, event(categoryId: 'cardio')), isTrue);
    });

    test('with-description ignores an empty string', () {
      const filters = CalendarGridFilters(withDescriptionOnly: true);

      expect(allows(filters, event(description: 'focus on hamstrings')), isTrue);
      expect(allows(filters, event(description: '')), isFalse);
      expect(allows(filters, event()), isFalse);
    });

    test('counted keeps the events carrying an occurrence label', () {
      const filters = CalendarGridFilters(countedOnly: true);

      expect(allows(filters, event(countOccurrences: true)), isTrue);
      expect(allows(filters, event()), isFalse);
    });

    /// With no ledger service resolved, no event can have money — so the axis
    /// hides everything rather than quietly passing everything through, which
    /// is the safe direction for an "only show" filter.
    test('with-money needs a linked note before it can have a ledger', () {
      const filters = CalendarGridFilters(moneyOnly: true);

      expect(allows(filters, event(noteId: 'n1')), isFalse);
      expect(allows(filters, event()), isFalse);
    });
  });

  group('the occurrence axis', () {
    test('is off for every event-level filter', () {
      const filters = CalendarGridFilters(
        trackedOnly: true,
        priorities: {1},
        hideEnded: true,
      );

      expect(filters.hasOccurrenceAxis, isFalse);
      expect(filters.allowsOccurrence(event(), today), isTrue);
    });

    /// The whole reason `missedOnly` cannot live in [CalendarGridFilters.apply]
    /// — it is the only axis whose answer depends on the day, which is what
    /// makes the presence handlers start invalidating the day cache.
    test('missed-only is the one axis that needs the day', () {
      const filters = CalendarGridFilters(missedOnly: true);

      expect(filters.hasOccurrenceAxis, isTrue);
      // No presence cache configured, so nothing is marked missed.
      expect(
        filters.allowsOccurrence(event(tracksPresence: true), today),
        isFalse,
      );
      // And it never survives the event-level pass being unaware of it.
      expect(allows(filters, event(tracksPresence: true)), isTrue);
    });

    test('leaves the event list alone', () {
      final events = [event(), event(id: 'e2')];
      const filters = CalendarGridFilters(missedOnly: true);

      expect(identical(filters.apply(events, todayUtc: today), events), isTrue);
    });
  });

  group('layers and the panel opt-out', () {
    test('a layer counts only while it is off', () {
      expect(CalendarGridFilters.none.activeCount, 0);
      expect(
        const CalendarGridFilters(showFasting: false).activeCount,
        1,
      );
      expect(
        const CalendarGridFilters(
          showHolidays: false,
          showFasting: false,
          showMoney: false,
        ).activeCount,
        3,
      );
    });

    test('layers never narrow the event list', () {
      final events = [event()];
      const filters = CalendarGridFilters(
        showHolidays: false,
        showFasting: false,
        showMoney: false,
      );

      expect(identical(filters.apply(events, todayUtc: today), events), isTrue);
      expect(allows(filters, event()), isTrue);
    });

    /// It widens, so it can never be the reason something is missing — which
    /// is why it earns neither a count nor a summary chip.
    test('the panel opt-out is not a restriction', () {
      const filters = CalendarGridFilters(panelShowsAll: true);

      expect(filters.activeCount, 0);
      expect(filters.isEmpty, isTrue);
    });

    test('reset clears the filters but keeps the panel opt-out', () {
      const filters = CalendarGridFilters(
        panelShowsAll: true,
        trackedOnly: true,
        showMoney: false,
        priorities: {1},
      );

      final cleared = filters.cleared();

      expect(cleared.isEmpty, isTrue);
      expect(cleared.showMoney, isTrue);
      expect(cleared.panelShowsAll, isTrue);
    });
  });

  group('persistence', () {
    test('nothing set encodes to nothing at all', () {
      expect(CalendarGridFilters.none.encode(), isEmpty);
    });

    test('round-trips every axis', () {
      const filters = CalendarGridFilters(
        hiddenCategoryIds: {'gym', 'cardio'},
        priorities: {1, 4},
        eventType: AgendaEventType.oneTime,
        timing: CalendarEventTiming.allDay,
        trackedOnly: true,
        linkedNotesOnly: true,
        moneyOnly: true,
        withDescriptionOnly: true,
        countedOnly: true,
        missedOnly: true,
        hideEnded: true,
        showHolidays: false,
        showFasting: false,
        showMoney: false,
        panelShowsAll: true,
      );

      expect(CalendarGridFilters.decode(filters.encode()), filters);
    });

    /// Only non-defaults are written, so a build that adds an axis reads an
    /// older blob correctly — the absent field takes its default, which for a
    /// layer is **on**.
    test('an absent field decodes to its default', () {
      final decoded = CalendarGridFilters.decode('{"trackedOnly":true}');

      expect(decoded.trackedOnly, isTrue);
      expect(decoded.showHolidays, isTrue);
      expect(decoded.showFasting, isTrue);
      expect(decoded.showMoney, isTrue);
      expect(decoded.priorities, isEmpty);
      expect(decoded.eventType, AgendaEventType.all);
    });

    test('junk degrades to nothing filtered rather than throwing', () {
      expect(CalendarGridFilters.decode(null), CalendarGridFilters.none);
      expect(CalendarGridFilters.decode(''), CalendarGridFilters.none);
      expect(CalendarGridFilters.decode('not json'), CalendarGridFilters.none);
      expect(CalendarGridFilters.decode('[1,2]'), CalendarGridFilters.none);
    });

    test('a field holding the wrong type falls back to its default', () {
      final decoded = CalendarGridFilters.decode(
        '{"trackedOnly":"yes","priorities":7,"eventType":"bogus",'
        '"showMoney":"no"}',
      );

      expect(decoded.trackedOnly, isFalse);
      expect(decoded.priorities, isEmpty);
      expect(decoded.eventType, AgendaEventType.all);
      expect(decoded.showMoney, isTrue);
      expect(decoded, CalendarGridFilters.none);
    });

    test('out-of-range priorities are dropped on read', () {
      final decoded = CalendarGridFilters.decode('{"priorities":"0,2,9,x"}');

      expect(decoded.priorities, {2});
    });
  });

  group('composition', () {
    test('axes are ANDed, and each counts once', () {
      const filters = CalendarGridFilters(
        hiddenCategoryIds: {'gym', 'cardio'},
        priorities: {1},
        eventType: AgendaEventType.recurring,
        trackedOnly: true,
      );

      expect(filters.isEmpty, isFalse);
      expect(filters.activeCount, 4);
      expect(
        allows(
          filters,
          event(categoryId: 'mobility', priority: 1, tracksPresence: true),
        ),
        isTrue,
      );
      // Every other event fails on exactly one axis.
      expect(
        allows(filters, event(categoryId: 'gym', priority: 1, tracksPresence: true)),
        isFalse,
      );
      expect(
        allows(
          filters,
          event(categoryId: 'mobility', priority: 2, tracksPresence: true),
        ),
        isFalse,
      );
      expect(
        allows(
          filters,
          event(categoryId: 'mobility', priority: 1, tracksPresence: false),
        ),
        isFalse,
      );
      expect(
        allows(
          filters,
          event(
            categoryId: 'mobility',
            priority: 1,
            tracksPresence: true,
            rule: const OneTimeRecurrence(),
          ),
        ),
        isFalse,
      );
    });

    test('apply narrows the list and preserves order', () {
      final events = [
        event(id: 'a', priority: 1),
        event(id: 'b', priority: 4),
        event(id: 'c', priority: 1),
      ];
      const filters = CalendarGridFilters(priorities: {1});

      final visible = filters.apply(events, todayUtc: today);

      expect(visible.map((e) => e.id), ['a', 'c']);
      expect(identical(visible, events), isFalse);
    });

    test('copyWith leaves the untouched axes alone', () {
      const filters = CalendarGridFilters(
        priorities: {1},
        trackedOnly: true,
        hiddenCategoryIds: {'gym'},
      );

      final next = filters.copyWith(trackedOnly: false);

      expect(next.trackedOnly, isFalse);
      expect(next.priorities, {1});
      expect(next.hiddenCategoryIds, {'gym'});
    });
  });
}
