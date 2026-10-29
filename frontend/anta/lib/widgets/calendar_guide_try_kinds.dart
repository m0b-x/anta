import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/calendar_categories.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/calendar_guide_demo.dart';
import '../models/day_bar.dart';
import '../models/recurrence_rule.dart';
import '../services/day_summary_resolver.dart';
import '../services/recurrence_formatter.dart';
import 'agenda_month_grid.dart';
import 'calendar_date_picker_sheet.dart';
import 'calendar_guide_try_card.dart';
import 'event_avatar.dart';
import 'event_repeat_sheet.dart';
import 'form_rows.dart';

/// The kinds page's card: one demo event, its Repeat row through the real
/// repeat sheet, Add date through the real multi-date picker, Skip this day
/// for a day picked through the real date picker, over this month's dots
/// showing where it falls. One event turned every way the editor can turn
/// it, so she sees what each kind does to the month.
///
/// The month is the year tiles' dot matrix, not the overview's month grid:
/// the grid's weekday row is a fixed 24 px under a 32 px line at text scale
/// 2.0, and at 360 wide its columns are narrow enough for "Mo" to wrap, so
/// on this stage it cut its own labels.
class GuideKindsDemo extends GuideCardDemo {
  GuideKindsDemo() : _today = _todayUtc();

  static const String slug = 'kinds';

  static DateTime _todayUtc() {
    final now = DateTime.now();
    return DateTime.utc(now.year, now.month, now.day);
  }

  /// Date-only UTC, read once.
  final DateTime _today;

  /// Null until the first build, which names it in her language.
  CalendarEvent? _event;
  final Set<DateTime> _skips = {};

  /// The day picked through the Date row: what Skip this day skips.
  DateTime? _picked;

  @override
  bool get needsAppearance => true;

  /// The month the dots show, and the one the pickers open on: Add date may
  /// reach a year either side, the day to skip only this month, where she
  /// can see it go.
  DateTime get _monthStart => DateTime.utc(_today.year, _today.month);
  DateTime get _monthEnd => DateTime.utc(_today.year, _today.month + 1, 0);
  DateTime get _firstDay => DateTime.utc(_today.year - 1);
  DateTime get _lastDay => DateTime.utc(_today.year + 1, 12, 31);

  static DateFormat _dates(AppLocalizations l10n) =>
      DateFormat.yMMMMEEEEd(l10n.localeName);

  @override
  String idle(AppLocalizations l10n) =>
      l10n.calendarGuideDemoOneDay(_dates(l10n).format(_today));

  @override
  List<String> candidates(AppLocalizations l10n) {
    final date = calendarGuideLongestDate(_dates(l10n));
    final title = l10n.calendarGuideDemoEventDentist;
    // The widest rule words each kind can produce: every weekday at the
    // largest interval, and each with the "always" suffix.
    const rules = <RecurrenceRule>[
      DailyRecurrence(interval: EventRepeatDraft.maxInterval),
      WeeklyRecurrence(
        weekdays: {1, 2, 3, 4, 5, 6, 7},
        interval: EventRepeatDraft.maxInterval,
      ),
      MonthlyRecurrence(interval: EventRepeatDraft.maxInterval),
      YearlyRecurrence(interval: EventRepeatDraft.maxInterval),
      WorkdaysRecurrence(),
      WeekendsRecurrence(),
      PublicHolidaysOnlyRecurrence(),
    ];
    const counts = [0, 1, 2, 22, 31];
    return [
      l10n.calendarGuideDemoOneDay(date),
      for (final rule in rules)
        for (final retroactive in const [false, true])
          for (final count in counts)
            l10n.calendarGuideDemoRepeats(
              RecurrenceFormatter.format(
                rule,
                l10n,
                l10n.localeName,
                retroactive: retroactive,
              ),
              count,
            ),
      for (final count in const [2, 22, 99]) l10n.recurrenceSpecificDates(count),
      l10n.calendarGuideDemoSkipped(date, title),
    ];
  }

  /// The record's Dentist, one time, today.
  CalendarEvent _seed(AppLocalizations l10n) => CalendarEvent(
    id: '${GuideDemoCalendar.idPrefix}kinds-dentist',
    title: l10n.calendarGuideDemoEventDentist,
    categoryId: CalendarCategories.fallback.id,
    iconKey: 'medical_services',
    startDate: _today,
    time: const EventTime(startMinute: 9 * 60, durationMinutes: 45),
  );

  /// Whether the event is on [day] here: its rule, less the days skipped
  /// in this demo — the calendar's own skips are never asked for a demo id.
  bool _occurs(CalendarEvent event, DateTime day) =>
      event.occursOnUtcDay(day) &&
      (event.rule is OneTimeRecurrence || !_skips.contains(day));

  int _daysThisMonth(CalendarEvent event) {
    var count = 0;
    for (
      var day = _monthStart;
      !day.isAfter(_monthEnd);
      day = DateTime.utc(day.year, day.month, day.day + 1)
    ) {
      if (_occurs(event, day)) count++;
    }
    return count;
  }

  String _ruleWords(AppLocalizations l10n, CalendarEvent event) =>
      RecurrenceFormatter.format(
        event.rule,
        l10n,
        l10n.localeName,
        retroactive: event.retroactive,
      );

  /// The caption for the event as it now stands: one day, its dates, or
  /// its rule and how often it falls this month.
  void _sayShape(CalendarEvent event) {
    final start = event.startDateUtc;
    final count = _daysThisMonth(event);
    say(
      (l10n) => switch (event.rule) {
        OneTimeRecurrence() => l10n.calendarGuideDemoOneDay(
          _dates(l10n).format(start),
        ),
        SpecificDatesRecurrence(:final dates) => l10n.recurrenceSpecificDates(
          dates.length,
        ),
        _ => l10n.calendarGuideDemoRepeats(_ruleWords(l10n, event), count),
      },
    );
  }

  /// The editor's decoder, `_initRecurrenceFrom` in `event_editor_sheet.dart`,
  /// cut to the draft: the editor keeps it private, and the repeat sheet
  /// edits a draft, never a rule.
  EventRepeatDraft _draftOf(CalendarEvent event) {
    final start = event.startDateUtc;
    final base = EventRepeatDraft(
      recurring: false,
      kind: RepeatKind.daily,
      weekdays: {start.weekday},
      endDate: event.endDate,
      retroactive: event.retroactive,
    );
    return switch (event.rule) {
      OneTimeRecurrence() || SpecificDatesRecurrence() => base,
      DailyRecurrence(:final interval) => base.copyWith(
        recurring: true,
        interval: interval,
      ),
      WeeklyRecurrence(:final weekdays, :final interval) => base.copyWith(
        recurring: true,
        kind: RepeatKind.weekly,
        weekdays: weekdays.isEmpty ? {start.weekday} : weekdays,
        interval: interval,
      ),
      MonthlyRecurrence(:final interval) => base.copyWith(
        recurring: true,
        kind: RepeatKind.monthly,
        interval: interval,
      ),
      YearlyRecurrence(:final interval) => base.copyWith(
        recurring: true,
        kind: RepeatKind.yearly,
        interval: interval,
      ),
      WorkdaysRecurrence() => base.copyWith(
        recurring: true,
        kind: RepeatKind.workdays,
      ),
      WeekendsRecurrence() => base.copyWith(
        recurring: true,
        kind: RepeatKind.weekends,
      ),
      PublicHolidaysOnlyRecurrence() => base.copyWith(
        recurring: true,
        kind: RepeatKind.holidays,
      ),
    };
  }

  /// The editor's encoder, `_buildRule` and `_pickRepeat` in
  /// `event_editor_sheet.dart`, applied to the event: "does not repeat"
  /// keeps the dates it was pinned to, the interval is clamped, and an end
  /// before the start is dropped.
  CalendarEvent _withDraft(CalendarEvent event, EventRepeatDraft draft) {
    final start = event.startDateUtc;
    if (!draft.recurring) {
      return event.copyWith(
        rule: event.rule is SpecificDatesRecurrence
            ? event.rule
            : const OneTimeRecurrence(),
        clearEndDate: true,
        retroactive: false,
      );
    }
    final interval = draft.interval.clamp(1, EventRepeatDraft.maxInterval);
    final RecurrenceRule rule = switch (draft.kind) {
      RepeatKind.daily => DailyRecurrence(interval: interval),
      RepeatKind.weekly => WeeklyRecurrence(
        weekdays: Set.unmodifiable(draft.weekdays),
        interval: interval,
      ),
      RepeatKind.monthly => MonthlyRecurrence(interval: interval),
      RepeatKind.yearly => YearlyRecurrence(interval: interval),
      RepeatKind.workdays => const WorkdaysRecurrence(),
      RepeatKind.weekends => const WeekendsRecurrence(),
      RepeatKind.holidays => const PublicHolidaysOnlyRecurrence(),
    };
    final end = draft.endDate;
    final endDay = end == null ? null : DateTime.utc(end.year, end.month, end.day);
    final keepsEnd = endDay != null && !endDay.isBefore(start);
    return event.copyWith(
      rule: rule,
      endDate: keepsEnd ? endDay : null,
      clearEndDate: !keepsEnd,
      retroactive: draft.retroactive,
    );
  }

  /// A change of rule leaves a picked day the event no longer falls on
  /// unpicked: the grid would no longer let her pick it.
  void _update(CalendarEvent event) {
    _event = event;
    final picked = _picked;
    if (picked != null && !_occurs(event, picked)) _picked = null;
    _sayShape(event);
  }

  Future<void> _repeat(BuildContext context, CalendarEvent event) async {
    final draft = _draftOf(event);
    final picked = await EventRepeatSheet.show(
      context,
      draft: draft,
      startDate: event.startDateUtc,
      appearance: appearance,
    );
    if (picked == null || picked == draft) return;
    _update(_withDraft(event, picked));
  }

  Future<void> _addDate(BuildContext context, CalendarEvent event) async {
    final dates = event.explicitDates;
    if (dates == null) return;
    final picked = await CalendarDatePickerSheet.pickMulti(
      context,
      initialSelection: dates,
      firstDate: _firstDay,
      lastDate: _lastDay,
      appearance: appearance,
    );
    if (picked == null || setEquals(picked, dates)) return;
    _update(event.withExplicitDates(picked));
  }

  /// The real single-day picker over this month, its days marked where the
  /// event falls.
  Future<void> _pickDay(BuildContext context, CalendarEvent event) async {
    final picked = await CalendarDatePickerSheet.pickSingle(
      context,
      initialDate: _picked ?? _today,
      firstDate: _monthStart,
      lastDate: _monthEnd,
      appearance: appearance,
      dayLoad: (day) => _occurs(event, day) ? 1 : 0,
    );
    if (picked == null) return;
    _picked = DateTime.utc(picked.year, picked.month, picked.day);
    changed();
  }

  /// This month's days as the dot matrix's bits: day 1 is bit 0.
  int _maskOf(bool Function(DateTime day) test) {
    var mask = 0;
    for (var i = 0; i < _monthEnd.day; i++) {
      if (test(DateTime.utc(_today.year, _today.month, i + 1))) mask |= 1 << i;
    }
    return mask;
  }

  void _skip(CalendarEvent event, DateTime day) {
    _skips.add(day);
    _picked = null;
    final title = calendarGuideQuote(event.title);
    say(
      (l10n) => l10n.calendarGuideDemoSkipped(_dates(l10n).format(day), title),
    );
  }

  @override
  Widget buildStage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final event = _event ??= _seed(l10n);
    final category = CalendarCategories.resolve(event.categoryId);
    final colorValue = event.colorValue;
    // The bar rule, not the avatar's: the event's own colour, else its
    // category's.
    final bars = [
      DayBar(
        key: event.barKey,
        color: colorValue == null ? category.color : Color(colorValue),
        priority: event.priority - kMinEventPriority,
        semanticLabel: event.title,
      ),
    ];
    final words = _ruleWords(l10n, event);
    final picked = _picked;
    String control(String name) =>
        SemanticsIds.calendarGuideTryControl(slug, name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormRowGroup(
          children: [
            FormReadTitleRow(
              leading: EventAvatar(
                icon: CalendarCategories.iconFor(event),
                color: EventSummaryProvider.colorFor(event, category),
              ),
              title: event.title,
              caption: words,
            ),
            FormPickerRow(
              glyph: Icons.repeat_rounded,
              label: l10n.eventRepeat,
              value: words,
              identifier: control('repeat'),
              onTap: () => _repeat(context, event),
            ),
            // Disabled, never hidden: a repeating event has no dates of its
            // own to add to.
            FormActionRow(
              glyph: Icons.add_rounded,
              label: l10n.eventAddDate,
              identifier: control('add-date'),
              onTap: event.explicitDates == null
                  ? null
                  : () => _addDate(context, event),
            ),
            // A one-day event has nothing to skip, and a day must be picked
            // first; disabled until both hold.
            FormActionRow(
              glyph: Icons.event_busy_outlined,
              label: l10n.eventSkipOccurrence,
              identifier: control('skip'),
              onTap: event.rule is OneTimeRecurrence || picked == null
                  ? null
                  : () => _skip(event, picked),
            ),
          ],
        ),
        AgendaMonthGrid(
          month: _month,
          firstDay: _firstDay,
          lastDay: _lastDay,
          today: _today,
          selectedDay: picked,
          appearance: appearance,
          hasEntry: (day) => _occurs(event, day),
          barsFor: (day) => _occurs(event, day) ? bars : null,
          onDaySelected: (day) {
            _picked = day;
            changed();
          },
          // The grid pages itself; the month is kept so a rebuild leaves it
          // where she swiped to.
          onPageChanged: (month) => _month = month,
        ),
      ],
    );
  }
}
