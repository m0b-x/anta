import 'package:flutter/material.dart';

import '../constants/calendar_categories.dart';
import '../constants/calendar_colors.dart';
import '../constants/calendar_weekend.dart';
import '../constants/event_presence.dart';
import '../constants/fasting_calendar.dart';
import '../constants/occurrence_descriptions.dart';
import '../constants/public_holidays.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_category.dart';
import '../models/calendar_event.dart';
import '../models/day_summary_entry.dart';
import '../models/recurrence_rule.dart';
import '../utils/event_agenda.dart';
import 'note_money_ledger_service.dart';
import 'recurrence_formatter.dart';
import 'event_time_formatter.dart';
import 'resolver_chain.dart';

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
    if (!CalendarWeekend.isWeekend(day)) return const [];
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

/// Emits one entry per enabled fasting tradition that marks the day,
/// titled with the fast's name and subtitled with the day's rule
/// ("Great Lent · Fish allowed"). Reads [FastingCalendar]'s memoized
/// per-year maps, so a lookup is O(1) after the first day of a year.
class FastingSummaryProvider implements DaySummaryProvider {
  final AppLocalizations l10n;

  const FastingSummaryProvider(this.l10n);

  @override
  Iterable<DaySummaryEntry> summaryFor(
    DateTime day,
    List<CalendarEvent> events,
  ) {
    final infos = FastingCalendar.on(day);
    if (infos.isEmpty) return const [];
    return [
      for (final info in infos)
        if (FastingCalendar.styleOf(info.tradition) case final style)
          DaySummaryEntry(
            key: 'fasting:${info.tradition.name}',
            icon: FastingCalendar.iconFor(info.tradition),
            color: FastingCalendar.colorOf(info.tradition),
            // A custom title replaces the computed period name outright —
            // someone who writes "Post" wants that on every Orthodox day,
            // not the specific fast's name.
            title:
                style.titleOverride ??
                FastingCalendar.periodNameOf(info.period, l10n),
            subtitle: FastingCalendar.regimeNameOf(info.regime, l10n),
            // Raw markdown, rendered clamped by the row exactly like an
            // event's description (money disabled, no tap recognizers).
            description: style.description,
            priority: style.priority,
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

  /// Whether row subtitles mention the repeat pattern ("Daily", "Every 2
  /// weeks", …). User-controlled via the calendar appearance settings —
  /// timed routines make the pattern read as redundant next to the time.
  final bool showRecurrence;

  const EventSummaryProvider(this.l10n, {this.showRecurrence = true});

  /// The colour an event's icon surfaces wear: its own colour only while the
  /// user opted into tinting the icon with it, else its category's. The one
  /// rule for the day panel, the agenda rows, the category card and the
  /// detail sheet.
  static Color colorFor(CalendarEvent event, CalendarCategory category) {
    final value = event.colorValue;
    return value != null && event.tintIcon ? Color(value) : category.color;
  }

  @override
  Iterable<DaySummaryEntry> summaryFor(
    DateTime day,
    List<CalendarEvent> events,
  ) {
    // `events` already arrives sorted by `EventAgenda.compareWithinDay`:
    // `CalendarBloc.eventsForDay` sorts once when a day's memo entry is
    // built (3.3), so this trusts that order instead of copying and
    // re-sorting on every panel build.
    return events.map((event) => entryFor(event, day));
  }

  /// One event's entry for one day — what [summaryFor] emits per event, for
  /// callers that already hold the pair and would otherwise allocate a
  /// one-element list per occurrence.
  DaySummaryEntry entryFor(CalendarEvent event, DateTime day) {
    final category = CalendarCategories.resolve(event.categoryId);
    // Two static map probes, resolved here rather than in each row so the
    // day panel, the agenda and the timeline can never disagree about
    // whether a given occurrence was missed.
    final presenceTracked = EventPresence.appliesTo(event);
    final colorValue = event.colorValue;
    return DaySummaryEntry(
      key: event.barKey,
      icon: CalendarCategories.iconFor(event),
      color: colorFor(event, category),
      stripeAccent: colorValue == null ? null : Color(colorValue),
      title: event.title,
      subtitle: _subtitleFor(event, day),
      description: _descriptionFor(event, day),
      priority: event.priority - kMinEventPriority,
      event: event,
      presenceTracked: presenceTracked,
      missed: presenceTracked && EventPresence.isMissed(event, day),
    );
  }

  /// The template description trimmed once per event: a year of a daily
  /// event is a few hundred entries over the same string.
  static final Expando<String> _trimmedTemplates = Expando<String>();

  /// Raw markdown description for this event **on this day**, or null when it
  /// has none. Emitted unrendered on purpose: the row decides how much of it
  /// fits.
  ///
  /// Resolution goes through [OccurrenceDescriptions.descriptionFor], which
  /// degrades to `event.description` whenever per-occurrence descriptions are
  /// off or the event fires on a single day. An override that is deliberately
  /// empty maps to null here, so that day loses its notes badge while its
  /// siblings keep theirs.
  String? _descriptionFor(CalendarEvent event, DateTime day) {
    final raw = OccurrenceDescriptions.descriptionFor(event, day);
    if (raw == null) return null;
    final trimmed = identical(raw, event.description)
        ? (_trimmedTemplates[event] ??= raw.trim())
        : raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// The subtitle's day-invariant tail per event — the repeat pattern, the
  /// time or "All day", the removal note — memoized by event identity. The
  /// agenda formats one subtitle per occurrence, so without this a daily
  /// event across a year formatted the same three strings a few hundred
  /// times; an edited event is a new object and misses on its own.
  static final Expando<_SubtitleTail> _tails = Expando<_SubtitleTail>();

  String _tailFor(CalendarEvent event) {
    final cached = _tails[event];
    if (cached != null &&
        cached.localeName == l10n.localeName &&
        cached.showRecurrence == showRecurrence) {
      return cached.text;
    }
    final time = event.time;
    final text = <String>[
      if (showRecurrence && event.rule is! OneTimeRecurrence)
        RecurrenceFormatter.format(
          event.rule,
          l10n,
          l10n.localeName,
          retroactive: event.retroactive,
        ),
      // Timed events show their range; all-day events show the explicit
      // "All day" badge so the type is never ambiguous in the list.
      if (time != null)
        EventTimeFormatter.formatRange(time, l10n)
      else
        l10n.eventAllDay,
      // A3 (\u00a72.2). Last, because it is the least of the three facts on an
      // ordinary day and the first that should be ellipsized \u2014 and here
      // rather than in the row, so the day panel, the agenda and the agenda's
      // search text stay in step.
      if (event.removeAfterAlert) l10n.eventRemovedAfterAlert,
    ].join(' \u00b7 ');
    _tails[event] = _SubtitleTail(l10n.localeName, showRecurrence, text);
    return text;
  }

  String? _subtitleFor(CalendarEvent event, DateTime day) {
    final tail = _tailFor(event);
    if (!event.countOccurrences) return tail;
    // The count label leads the subtitle: for a birthday the age (and for a
    // program its "Week N") is the headline fact, and trailing segments are
    // the first to be ellipsized. The one day-dependent segment, so the one
    // formatted per occurrence.
    final elapsed = RecurrenceFormatter.countLabel(
      event,
      DateTime.utc(day.year, day.month, day.day),
      l10n,
    );
    return elapsed == null ? tail : '$elapsed \u00b7 $tail';
  }
}

class _SubtitleTail {
  final String localeName;
  final bool showRecurrence;
  final String text;

  const _SubtitleTail(this.localeName, this.showRecurrence, this.text);
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
        color: sum > 0
            ? CalendarColors.moneyPositive
            : CalendarColors.moneyNegative,
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

  /// Counts [DaySummaryResolver.defaults] invocations — each allocates five
  /// stateless providers. Incremented inside an `assert`, so both the
  /// statement and its closure are stripped from profile and release builds,
  /// mirroring `CalendarEvent.debugOccursOnCalls`.
  ///
  /// The providers depend only on the localization and the recurrence-label
  /// setting, so a caller building this from `build` is throwing away five
  /// identical objects per frame. There is no other seam a test could watch
  /// the memo through — the resolver is private state on the panel, and its
  /// output is a fresh list either way (**4.3**).
  @visibleForTesting
  static int debugDefaultsBuilds = 0;

  /// Default resolver bundling events + public holiday + weekend.
  factory DaySummaryResolver.defaults(
    AppLocalizations l10n, {
    bool showRecurrence = true,
    bool showHolidays = true,
    bool showFasting = true,
    bool showMoney = true,
  }) {
    assert(() {
      debugDefaultsBuilds++;
      return true;
    }());
    return DaySummaryResolver(
      providers: [
        EventSummaryProvider(l10n, showRecurrence: showRecurrence),
        // The layer flags compose the provider list, exactly as they do in
        // `DayBarsResolver.defaults` — the grid and this panel must hide the
        // same annotations, so they read the same three flags.
        if (showHolidays) PublicHolidaySummaryProvider(l10n),
        if (showFasting) FastingSummaryProvider(l10n),
        WeekendSummaryProvider(l10n),
        if (showMoney) MoneyDaySummaryProvider(l10n),
      ],
    );
  }

  List<DaySummaryEntry> resolve(DateTime day, List<CalendarEvent> events) =>
      resolveChain(providers.map((p) => p.summaryFor(day, events)));
}
