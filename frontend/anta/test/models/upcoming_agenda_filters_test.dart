import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/upcoming_agenda_filters.dart';
import 'package:anta/utils/event_agenda.dart';

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

  group('AgendaPeriodMode.fromName', () {
    test('round-trips every value', () {
      for (final mode in AgendaPeriodMode.values) {
        expect(AgendaPeriodMode.fromName(mode.name), mode);
      }
    });

    test('falls back to rollingDays for null and for unknown names', () {
      // An absent key is every existing install, where the window was
      // `rangeDays` counted forward and nothing else.
      expect(AgendaPeriodMode.fromName(null), AgendaPeriodMode.rollingDays);
      expect(AgendaPeriodMode.fromName(''), AgendaPeriodMode.rollingDays);
      expect(
        AgendaPeriodMode.fromName('someFutureMode'),
        AgendaPeriodMode.rollingDays,
      );
    });
  });

  group('UpcomingAgendaFilters.presetWindow', () {
    final anchor = DateTime.utc(2026, 8, 29);

    test('defaults to the rolling window that shipped', () {
      const filters = UpcomingAgendaFilters();
      expect(filters.periodMode, AgendaPeriodMode.rollingDays);
      expect(filters.presetWindow(anchor), (
        anchor,
        DateTime.utc(2026, 9, 27),
      ));
    });

    test('rollingDays counts rangeDays inclusive of the anchor', () {
      const filters = UpcomingAgendaFilters(rangeDays: 7);
      expect(filters.presetWindow(anchor), (anchor, DateTime.utc(2026, 9, 4)));
    });

    test('wholeYear spans the anchor year, reaching into the past', () {
      // The point of the mode: a birthday in March is still findable in
      // August, which a forward-only window can never do.
      const filters = UpcomingAgendaFilters(
        periodMode: AgendaPeriodMode.wholeYear,
      );
      expect(filters.presetWindow(anchor), (
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 12, 31),
      ));
    });

    test('wholeYear follows the anchor into another year', () {
      const filters = UpcomingAgendaFilters(
        periodMode: AgendaPeriodMode.wholeYear,
      );
      expect(filters.presetWindow(DateTime.utc(2028, 3, 2)), (
        DateTime.utc(2028, 1, 1),
        DateTime.utc(2028, 12, 31),
      ));
    });

    test('a leap year fits inside the scan cap', () {
      // 2028 is 366 days, which is exactly `EventAgenda.maxRangeDays`. One day
      // more and `resolveRange` would silently clip December off the window
      // the header claims to show.
      const filters = UpcomingAgendaFilters(
        periodMode: AgendaPeriodMode.wholeYear,
      );
      final (start, end) = filters.presetWindow(DateTime.utc(2028, 6, 1));
      expect(end.difference(start).inDays + 1, EventAgenda.maxRangeDays);
      expect(EventAgenda.resolveRange(start, end), (start, end));
    });

    test('restOfYear runs from the anchor to 31 December', () {
      const filters = UpcomingAgendaFilters(
        periodMode: AgendaPeriodMode.restOfYear,
      );
      expect(filters.presetWindow(anchor), (anchor, DateTime.utc(2026, 12, 31)));
    });

    test('restOfYear degenerates to a single day on 31 December', () {
      const filters = UpcomingAgendaFilters(
        periodMode: AgendaPeriodMode.restOfYear,
      );
      final lastDay = DateTime.utc(2026, 12, 31);
      expect(filters.presetWindow(lastDay), (lastDay, lastDay));
      // Still a resolvable window rather than an empty one, so the panel shows
      // that day instead of falling back to a degenerate range.
      expect(EventAgenda.resolveRange(lastDay, lastDay), (lastDay, lastDay));
    });

    test('ignores rangeDays in the year modes', () {
      const filters = UpcomingAgendaFilters(
        periodMode: AgendaPeriodMode.wholeYear,
        rangeDays: 7,
      );
      expect(filters.presetWindow(anchor).$2, DateTime.utc(2026, 12, 31));
    });

    test('normalizes a timestamped anchor to its date', () {
      const filters = UpcomingAgendaFilters(
        periodMode: AgendaPeriodMode.restOfYear,
      );
      expect(
        filters.presetWindow(DateTime.utc(2026, 8, 29, 17, 42)).$1,
        DateTime.utc(2026, 8, 29),
      );
    });
  });

  group('UpcomingAgendaFilters.periodMode', () {
    test('copyWith carries it and leaves the rest alone', () {
      const base = UpcomingAgendaFilters(rangeDays: 90, showHolidays: true);
      final next = base.copyWith(periodMode: AgendaPeriodMode.wholeYear);

      expect(next.periodMode, AgendaPeriodMode.wholeYear);
      // Kept, so dropping the year view returns to the rolling window the user
      // last chose rather than to the default.
      expect(next.rangeDays, 90);
      expect(next.showHolidays, isTrue);
    });

    test('is part of equality, so a mode change reaches the panel', () {
      expect(
        const UpcomingAgendaFilters(periodMode: AgendaPeriodMode.wholeYear),
        isNot(const UpcomingAgendaFilters()),
      );
    });

    test('counts as a window restriction, so it earns a summary chip', () {
      // Wider than the default is still "not the default window", exactly as
      // the 90-day preset is — the count exists so every non-default window
      // has a chip that undoes it.
      for (final mode in AgendaPeriodMode.values) {
        expect(
          UpcomingAgendaFilters(periodMode: mode).restrictiveFilterCount,
          mode == AgendaPeriodMode.rollingDays ? 0 : 1,
        );
      }
    });

    test('does not double-count with a non-default rangeDays', () {
      expect(
        const UpcomingAgendaFilters(
          periodMode: AgendaPeriodMode.wholeYear,
          rangeDays: 90,
        ).restrictiveFilterCount,
        1,
      );
    });
  });
}
