import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/upcoming_agenda_filters.dart';

/// The fasting presentation is persisted **by name**, so the axis that matters
/// is forward compatibility: a value written by a newer build must degrade to
/// today's behaviour rather than throw or silently pick the most condensed
/// presentation. `periods` is that fallback because it is what shipped.
void main() {
  group('AgendaFastingDisplay.fromName', () {
    test('round-trips every value', () {
      for (final display in AgendaFastingDisplay.values) {
        expect(AgendaFastingDisplay.fromName(display.name), display);
      }
    });

    test('falls back to periods for null and for unknown names', () {
      expect(AgendaFastingDisplay.fromName(null), AgendaFastingDisplay.periods);
      expect(AgendaFastingDisplay.fromName(''), AgendaFastingDisplay.periods);
      expect(
        AgendaFastingDisplay.fromName('someFutureMode'),
        AgendaFastingDisplay.periods,
      );
    });
  });

  group('UpcomingAgendaFilters.fastingDisplay', () {
    test('defaults to periods — the behaviour that shipped', () {
      expect(
        const UpcomingAgendaFilters().fastingDisplay,
        AgendaFastingDisplay.periods,
      );
    });

    test('copyWith carries it and leaves the rest alone', () {
      const base = UpcomingAgendaFilters(rangeDays: 90, showFasting: true);
      final next = base.copyWith(fastingDisplay: AgendaFastingDisplay.summary);

      expect(next.fastingDisplay, AgendaFastingDisplay.summary);
      expect(next.rangeDays, 90);
      expect(next.showFasting, isTrue);
    });

    test('copyWith without it preserves the current value', () {
      const base = UpcomingAgendaFilters(
        fastingDisplay: AgendaFastingDisplay.everyDay,
      );

      expect(
        base.copyWith(rangeDays: 7).fastingDisplay,
        AgendaFastingDisplay.everyDay,
      );
    });

    test('is part of equality, so a mode change reaches the panel', () {
      // The panel and the view both diff filters by value; leaving this out of
      // `props` would make switching presentation a silent no-op.
      expect(
        const UpcomingAgendaFilters(
          fastingDisplay: AgendaFastingDisplay.summary,
        ),
        isNot(const UpcomingAgendaFilters()),
      );
      expect(
        const UpcomingAgendaFilters(
          fastingDisplay: AgendaFastingDisplay.periods,
        ),
        const UpcomingAgendaFilters(),
      );
    });

    test('never counts as a restrictive filter', () {
      // It condenses rows; it never hides content. The badge and the summary
      // chips answer "why is something missing", which this can never cause.
      for (final display in AgendaFastingDisplay.values) {
        expect(
          UpcomingAgendaFilters(fastingDisplay: display).restrictiveFilterCount,
          0,
        );
      }
    });
  });

  group('AgendaHolidayDisplay.fromName', () {
    test('round-trips every value', () {
      for (final display in AgendaHolidayDisplay.values) {
        expect(AgendaHolidayDisplay.fromName(display.name), display);
      }
    });

    test('falls back to everyDay for null and for unknown names', () {
      expect(
        AgendaHolidayDisplay.fromName(null),
        AgendaHolidayDisplay.everyDay,
      );
      expect(AgendaHolidayDisplay.fromName(''), AgendaHolidayDisplay.everyDay);
      // Deliberately the *opposite* fallback from the fasting axis: `periods`
      // is what fasting shipped with, `everyDay` is what holidays shipped with.
      expect(
        AgendaHolidayDisplay.fromName('someFutureMode'),
        AgendaHolidayDisplay.everyDay,
      );
    });
  });

  group('UpcomingAgendaFilters.holidayDisplay', () {
    test('defaults to everyDay — the behaviour that shipped', () {
      expect(
        const UpcomingAgendaFilters().holidayDisplay,
        AgendaHolidayDisplay.everyDay,
      );
    });

    test('copyWith carries it without disturbing the fasting axis', () {
      const base = UpcomingAgendaFilters(
        fastingDisplay: AgendaFastingDisplay.summary,
      );
      final next = base.copyWith(holidayDisplay: AgendaHolidayDisplay.summary);

      expect(next.holidayDisplay, AgendaHolidayDisplay.summary);
      expect(next.fastingDisplay, AgendaFastingDisplay.summary);
    });

    test('is part of equality, so a mode change reaches the panel', () {
      expect(
        const UpcomingAgendaFilters(
          holidayDisplay: AgendaHolidayDisplay.summary,
        ),
        isNot(const UpcomingAgendaFilters()),
      );
    });

    test('never counts as a restrictive filter', () {
      for (final display in AgendaHolidayDisplay.values) {
        expect(
          UpcomingAgendaFilters(holidayDisplay: display).restrictiveFilterCount,
          0,
        );
      }
    });
  });

  group('AgendaEventDisplay.fromName', () {
    test('round-trips every value', () {
      for (final display in AgendaEventDisplay.values) {
        expect(AgendaEventDisplay.fromName(display.name), display);
      }
    });

    test('falls back to everyOccurrence for null and unknown names', () {
      // The events axis is entirely opt-in, so an unreadable value must land
      // on the uncondensed listing rather than on either collapse.
      expect(
        AgendaEventDisplay.fromName(null),
        AgendaEventDisplay.everyOccurrence,
      );
      expect(
        AgendaEventDisplay.fromName('someFutureMode'),
        AgendaEventDisplay.everyOccurrence,
      );
    });
  });

  group('UpcomingAgendaFilters.eventDisplay', () {
    test('defaults to everyOccurrence — condensing is opt-in', () {
      expect(
        const UpcomingAgendaFilters().eventDisplay,
        AgendaEventDisplay.everyOccurrence,
      );
    });

    test('copyWith carries it without disturbing the other two axes', () {
      const base = UpcomingAgendaFilters(
        fastingDisplay: AgendaFastingDisplay.summary,
        holidayDisplay: AgendaHolidayDisplay.summary,
      );
      final next = base.copyWith(eventDisplay: AgendaEventDisplay.summary);

      expect(next.eventDisplay, AgendaEventDisplay.summary);
      expect(next.fastingDisplay, AgendaFastingDisplay.summary);
      expect(next.holidayDisplay, AgendaHolidayDisplay.summary);
    });

    test('is part of equality, so a mode change reaches the panel', () {
      expect(
        const UpcomingAgendaFilters(eventDisplay: AgendaEventDisplay.summary),
        isNot(const UpcomingAgendaFilters()),
      );
    });

    test('never counts as a restrictive filter', () {
      for (final display in AgendaEventDisplay.values) {
        expect(
          UpcomingAgendaFilters(eventDisplay: display).restrictiveFilterCount,
          0,
        );
      }
    });
  });
}
