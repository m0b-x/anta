import 'package:flutter/material.dart';

import '../constants/calendar_categories.dart';
import '../constants/calendar_colors.dart';
import '../constants/public_holidays.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/day_summary_entry.dart';
import '../models/recurrence_rule.dart';
import '../utils/event_agenda.dart';
import 'note_money_ledger_service.dart';
import 'recurrence_formatter.dart';
import 'event_time_formatter.dart';

/// Contract for anything that contributes entries to the calendar's bottom
/// "day summary" panel.
///
/// Mirrors `DayBarProvider` but produces richer entries (icon + title +
/// subtitle) instead of plain colored bars. Implementations should stay
/// cheap and side-effect free: [summaryFor] is called once per build of the
/// selected day.
abstract interface class DaySummaryProvider {
  Iterable<DaySummaryEntry> summaryFor(
    DateTime day,
    List<CalendarEvent> events,
  );
}

/// Emits a "Weekend" entry on Saturday/Sunday.
class WeekendSummaryProvider implements DaySummaryProvider {
  final AppLocalizations l10n;

  const WeekendSummaryProvider(this.l10n);

  @override
  Iterable<DaySummaryEntry> summaryFor(
    DateTime day,
    List<CalendarEvent> events,
  ) {
    if (day.weekday != DateTime.saturday && day.weekday != DateTime.sunday) {
      return const [];
    }
    return [
      DaySummaryEntry(
        key: 'weekend',
        icon: Icons.weekend_rounded,
        color: CalendarColors.weekend,
        title: l10n.dayBarWeekend,
        priority: 250,
      ),
    ];
  }
}

/// Emits a "Public holiday" entry naming the specific holiday.
class PublicHolidaySummaryProvider implements DaySummaryProvider {
  final AppLocalizations l10n;

  const PublicHolidaySummaryProvider(this.l10n);

  @override
  Iterable<DaySummaryEntry> summaryFor(
    DateTime day,
    List<CalendarEvent> events,
  ) {
    final holiday = PublicHolidays.holidayOn(day);
    if (holiday == null) return const [];
    return [
      DaySummaryEntry(
        key: 'holiday',
        icon: Icons.celebration_rounded,
        color: CalendarColors.publicHoliday,
        title: PublicHolidays.labelOf(holiday, l10n),
        subtitle: l10n.dayBarPublicHoliday,
        priority: 150,
      ),
    ];
  }
}

/// Emits one entry per [CalendarEvent] on the day.
///
/// Entries are emitted in [EventAgenda.compareWithinDay] order — the single
/// comparator for same-day event ordering, shared with the upcoming agenda —
/// and [DaySummaryResolver.resolve]'s stable sort preserves that order for
/// events of equal priority.
class EventSummaryProvider implements DaySummaryProvider {
  final AppLocalizations l10n;

  const EventSummaryProvider(this.l10n);

  @override
  Iterable<DaySummaryEntry> summaryFor(
    DateTime day,
    List<CalendarEvent> events,
  ) {
    final ordered = [...events]..sort(EventAgenda.compareWithinDay);
    return ordered.map((event) {
      final category = CalendarCategories.resolve(event.categoryId);
      // The event color tints the icon only when the user opted in
      // (tintIcon); otherwise the icon keeps its category color.
      final color = (event.colorValue != null && event.tintIcon)
          ? Color(event.colorValue!)
          : category.color;
      return DaySummaryEntry(
        key: 'event:${event.id}',
        icon: CalendarCategories.iconFor(event),
        color: color,
        title: event.title,
        subtitle: _subtitleFor(event),
        priority: event.priority - kMinEventPriority,
        event: event,
      );
    });
  }

  String? _subtitleFor(CalendarEvent event) {
    final time = event.time;
    final parts = <String>[
      if (event.rule is! OneTimeRecurrence)
        RecurrenceFormatter.format(event.rule, l10n, l10n.localeName),
      // Timed events show their range; all-day events show the explicit
      // "All day" badge so the type is never ambiguous in the list.
      if (time != null)
        EventTimeFormatter.formatRange(time, l10n)
      else
        l10n.eventAllDay,
    ];
    return parts.isEmpty ? null : parts.join(' \u00b7 ');
  }
}

/// Emits a single money entry when calendar-linked notes attribute a
/// non-zero net ledger change to the day.
///
/// Uses the same attribution rule as `MoneyDayBarProvider`: an event
/// contributes its linked note's `net` only on the UTC date of its
/// `startDate` (deduplicated by note), so recurring occurrences can never
/// double-count. The subtitle lists the titles of the notes that
/// contributed.
class MoneyDaySummaryProvider implements DaySummaryProvider {
  final AppLocalizations l10n;

  const MoneyDaySummaryProvider(this.l10n);

  @override
  Iterable<DaySummaryEntry> summaryFor(
    DateTime day,
    List<CalendarEvent> events,
  ) {
    if (events.isEmpty) return const [];
    final service = NoteMoneyLedgerService.instanceOrNull;
    if (service == null) return const [];
    final key = DateTime.utc(day.year, day.month, day.day);
    var sum = 0;
    final seen = <String>{};
    final titles = <String>[];
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
      if (!seen.add(noteId)) continue;
      final ledger = service.ledgerFor(noteId);
      if (ledger == null) continue;
      sum += ledger.net;
      titles.add(ledger.title);
    }
    if (sum == 0) return const [];
    return [
      DaySummaryEntry(
        key: 'money',
        icon: Icons.payments_outlined,
        color: sum > 0 ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
        title: l10n.moneyDaySummaryTitle(service.formatNetSigned(sum)),
        subtitle: titles.isEmpty ? null : titles.join(', '),
        priority: 90,
      ),
    ];
  }
}

/// Chains a list of [DaySummaryProvider]s and returns a sorted,
/// deduplicated list of entries for a given day.
///
/// To add a new entry type, implement [DaySummaryProvider] and pass it in —
/// no other call sites need to change.
class DaySummaryResolver {
  final List<DaySummaryProvider> providers;

  const DaySummaryResolver({required this.providers});

  /// Default resolver bundling events + public holiday + weekend.
  factory DaySummaryResolver.defaults(AppLocalizations l10n) {
    return DaySummaryResolver(
      providers: [
        EventSummaryProvider(l10n),
        PublicHolidaySummaryProvider(l10n),
        WeekendSummaryProvider(l10n),
        MoneyDaySummaryProvider(l10n),
      ],
    );
  }

  List<DaySummaryEntry> resolve(DateTime day, List<CalendarEvent> events) {
    final byKey = <String, DaySummaryEntry>{};
    for (final provider in providers) {
      for (final entry in provider.summaryFor(day, events)) {
        byKey.putIfAbsent(entry.key, () => entry);
      }
    }
    // Stable sort by priority: `List.sort` is unstable, so ties are broken
    // by insertion index instead of the old key comparison — providers
    // control the order of their own equal-priority entries (events arrive
    // pre-sorted by `EventAgenda.compareWithinDay`, which a key sort on
    // `event:<uuid>` used to scramble into id order).
    final entries = byKey.values.toList();
    final order = [for (var i = 0; i < entries.length; i++) (i, entries[i])]
      ..sort((a, b) {
        final byPriority = a.$2.priority.compareTo(b.$2.priority);
        return byPriority != 0 ? byPriority : a.$1.compareTo(b.$1);
      });
    return [for (final (_, entry) in order) entry];
  }
}
