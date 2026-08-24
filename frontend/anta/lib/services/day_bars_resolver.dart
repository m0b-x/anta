import 'package:flutter/painting.dart';

import '../constants/calendar_categories.dart';
import '../constants/calendar_colors.dart';
import '../constants/event_presence.dart';
import '../constants/fasting_calendar.dart';
import '../constants/public_holidays.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/day_bar.dart';
import '../models/fasting_appearance.dart';
import 'note_money_ledger_service.dart';

/// Contract for anything that contributes bars to a calendar day cell.
///
/// Providers must be pure & cheap: [barsFor] is called by `TableCalendar`'s
/// `markerBuilder` for every visible cell on every rebuild. Avoid I/O,
/// allocations beyond what is needed, and do not call BLoCs from here.
abstract interface class DayBarProvider {
  Iterable<DayBar> barsFor(DateTime day, List<CalendarEvent> events);
}

/// Emits a weekend bar for Saturday/Sunday.
class WeekendDayBarProvider implements DayBarProvider {
  final AppLocalizations l10n;

  const WeekendDayBarProvider(this.l10n);

  @override
  Iterable<DayBar> barsFor(DateTime day, List<CalendarEvent> events) {
    if (day.weekday != DateTime.saturday && day.weekday != DateTime.sunday) {
      return const [];
    }
    return [
      DayBar(
        key: 'weekend',
        color: CalendarColors.weekend,
        priority: 250,
        semanticLabel: l10n.dayBarWeekend,
      ),
    ];
  }
}

/// Emits a public-holiday bar when the date matches `PublicHolidays`.
class PublicHolidayDayBarProvider implements DayBarProvider {
  final AppLocalizations l10n;

  const PublicHolidayDayBarProvider(this.l10n);

  @override
  Iterable<DayBar> barsFor(DateTime day, List<CalendarEvent> events) {
    if (!PublicHolidays.isHoliday(day)) return const [];
    return [
      DayBar(
        key: 'holiday',
        color: CalendarColors.publicHoliday,
        priority: 150,
        semanticLabel: l10n.dayBarPublicHoliday,
      ),
    ];
  }
}

/// Emits one bar per tradition whose configured grid style is
/// [FastingDisplayStyle.bar], in that tradition's colour and at its
/// configured placement. Traditions using another style contribute nothing
/// here (the cell wash and the bold number are the day cell's job), which is
/// why the check is per tradition rather than a single global gate.
class FastingDayBarProvider implements DayBarProvider {
  final AppLocalizations l10n;

  const FastingDayBarProvider(this.l10n);

  @override
  Iterable<DayBar> barsFor(DateTime day, List<CalendarEvent> events) {
    final infos = FastingCalendar.on(day);
    if (infos.isEmpty) return const [];
    final bars = <DayBar>[];
    for (final info in infos) {
      final style = FastingCalendar.styleOf(info.tradition);
      if (style.style != FastingDisplayStyle.bar) continue;
      bars.add(
        DayBar(
          key: 'fasting:${info.tradition.name}',
          color: style.colorOr(CalendarColors.fasting),
          priority: style.priority,
          semanticLabel:
              style.titleOverride ??
              FastingCalendar.periodNameOf(info.period, l10n),
        ),
      );
    }
    return bars;
  }
}

/// Emits one bar per event on the day.
///
/// Each bar is colored by the event's explicit color override (falling back
/// to its category color) and ordered by the event's priority: P1 sorts
/// highest in the stack and wins the day cell's limited bar slots. The bar
/// [DayBar.priority] stays in `0..kMaxEventPriority-1`, which is below the
/// contextual holiday/weekend bands so events stay dominant.
///
/// This is the one hook with the full `(event, day)` key, so it is also where
/// presence (**v26**) is applied: a missed occurrence of a tracked event is
/// either dimmed or skipped entirely, per [missedDisplay]. Skipping happens
/// **before** the bar is added, so a hidden bar never consumes one of the
/// cell's `maxDayBars` slots. Both branches cost two static map probes, which
/// keeps the provider contract (pure & cheap, called for every visible cell
/// on every rebuild) intact.
class EventDayBarProvider implements DayBarProvider {
  final CalendarMissedDisplay missedDisplay;

  const EventDayBarProvider({this.missedDisplay = CalendarMissedDisplay.faded});

  @override
  Iterable<DayBar> barsFor(DateTime day, List<CalendarEvent> events) {
    if (events.isEmpty) return const [];
    // Same-day order comes from the one shared comparator, exactly as the
    // day summary does — otherwise equal-priority stripes fall back to the
    // resolver's key tie-break (`event:<uuid>`) and the grid disagrees with
    // the panel about which event is on top. `events` already arrives
    // sorted by `EventAgenda.compareWithinDay`: `CalendarBloc.eventsForDay`
    // sorts once when a day's memo entry is built (3.3), so this trusts that
    // order instead of copying and re-sorting on every cell, every frame.
    final bars = <DayBar>[];
    for (final event in events) {
      final missed =
          EventPresence.appliesTo(event) &&
          EventPresence.isMissed(event.id, day);
      if (missed && missedDisplay == CalendarMissedDisplay.hidden) continue;
      var color = event.colorValue != null
          ? Color(event.colorValue!)
          : CalendarCategories.resolve(event.categoryId).color;
      if (missed) {
        color = color.withValues(alpha: CalendarColors.missedEventAlpha);
      }
      bars.add(
        DayBar(
          key: 'event:${event.id}',
          color: color,
          priority: event.priority - kMinEventPriority,
          semanticLabel: event.title,
        ),
      );
    }
    return bars;
  }
}

/// Emits a single money bar when calendar-linked notes attribute a
/// non-zero net ledger change to the day.
///
/// Attribution rule: an event contributes its linked note's `net` only on
/// the UTC date of its `startDate`, so recurring occurrences can never
/// double-count a note; notes are additionally deduplicated per day. Reads
/// the [NoteMoneyLedgerService] cache synchronously — no data means no bar.
class MoneyDayBarProvider implements DayBarProvider {
  final AppLocalizations l10n;

  const MoneyDayBarProvider(this.l10n);

  @override
  Iterable<DayBar> barsFor(DateTime day, List<CalendarEvent> events) {
    if (events.isEmpty) return const [];
    final service = NoteMoneyLedgerService.instanceOrNull;
    if (service == null) return const [];
    final key = DateTime.utc(day.year, day.month, day.day);
    var sum = 0;
    Set<String>? seen;
    for (final event in events) {
      final noteId = event.noteId;
      if (noteId == null) continue;
      // Re-derive the start date's UTC day via epoch milliseconds so the
      // key matches `CalendarEventService._dateOnlyUtc` in every timezone.
      final startUtc = DateTime.fromMillisecondsSinceEpoch(
        event.startDate.millisecondsSinceEpoch,
        isUtc: true,
      );
      if (DateTime.utc(startUtc.year, startUtc.month, startUtc.day) != key) {
        continue;
      }
      seen ??= <String>{};
      if (!seen.add(noteId)) continue;
      final ledger = service.ledgerFor(noteId);
      if (ledger == null) continue;
      sum += ledger.net;
    }
    if (sum == 0) return const [];
    return [
      DayBar(
        key: 'money',
        color: sum > 0
            ? CalendarColors.moneyPositive
            : CalendarColors.moneyNegative,
        priority: 90,
        semanticLabel: l10n.moneyDaySummaryTitle(service.formatNetSigned(sum)),
      ),
    ];
  }
}

/// Chains a list of [DayBarProvider]s and returns a sorted, deduplicated
/// list of bars for a given day.
///
/// To add a new bar type, implement [DayBarProvider] and pass it into the
/// constructor — no other call sites need to change.
///
/// Note: this resolver does **not** cap the returned list. The
/// [CalendarDayBars] widget decides how many bars to render and renders a
/// "+N" overflow indicator for the remainder, controlled by the user's
/// `calendarMaxDayBars` setting.
class DayBarsResolver {
  final List<DayBarProvider> providers;

  const DayBarsResolver({required this.providers});

  /// Default resolver bundling weekend + public holiday + event categories.
  factory DayBarsResolver.defaults(
    AppLocalizations l10n, {
    CalendarMissedDisplay missedDisplay = CalendarMissedDisplay.faded,
  }) {
    return DayBarsResolver(
      providers: [
        EventDayBarProvider(missedDisplay: missedDisplay),
        PublicHolidayDayBarProvider(l10n),
        FastingDayBarProvider(l10n),
        WeekendDayBarProvider(l10n),
        MoneyDayBarProvider(l10n),
      ],
    );
  }

  List<DayBar> resolve(DateTime day, List<CalendarEvent> events) {
    final byKey = <String, DayBar>{};
    for (final provider in providers) {
      for (final bar in provider.barsFor(day, events)) {
        byKey.putIfAbsent(bar.key, () => bar);
      }
    }
    // Stable sort by priority, mirroring `DaySummaryResolver.resolve`:
    // `List.sort` is unstable, so ties break by insertion index instead of
    // by key — providers control the order of their own equal-priority
    // bars (events arrive pre-sorted by `EventAgenda.compareWithinDay`,
    // which a key sort on `event:<uuid>` used to scramble into id order).
    final bars = byKey.values.toList();
    final order = [for (var i = 0; i < bars.length; i++) (i, bars[i])]
      ..sort((a, b) {
        final byPriority = a.$2.priority.compareTo(b.$2.priority);
        return byPriority != 0 ? byPriority : a.$1.compareTo(b.$1);
      });
    return [for (final (_, bar) in order) bar];
  }
}
