import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/app_colors.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_colors.dart';
import '../constants/guide_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/calendar_guide_demo.dart';
import '../models/recurrence_rule.dart';
import '../services/day_summary_resolver.dart';
import '../services/recurrence_formatter.dart';
import '../utils/calendar_week_start.dart';
import 'calendar_date_picker_sheet.dart';
import 'calendar_guide_try_card.dart';
import 'event_avatar.dart';
import 'event_repeat_sheet.dart';
import 'form_rows.dart';
import 'month_dot_matrix.dart';

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
  GuideKindsDemo({DateTime Function() now = DateTime.now})
    : _today = _todayUtc(now());

  static const String slug = 'kinds';

  static DateTime _todayUtc(DateTime now) =>
      DateTime.utc(now.year, now.month, now.day);

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

  final GuideLocaleFormat _dates = GuideLocaleFormat(DateFormat.yMMMMEEEEd);

  /// The Date row's value.
  final GuideLocaleFormat _shortDates = GuideLocaleFormat(DateFormat.yMMMEd);

  @override
  String idle(AppLocalizations l10n) =>
      l10n.calendarGuideDemoOneDay(_dates.of(l10n).format(_today));

  /// The widest rule words each kind can produce: every weekday at the
  /// largest interval. The formatter writes no end date, so an Until adds
  /// nothing to them.
  static const List<RecurrenceRule> _widestRules = [
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

  /// Every rule's widest words, each with the "always" suffix too.
  static Iterable<String> _widestRuleWords(AppLocalizations l10n) sync* {
    for (final rule in _widestRules) {
      for (final retroactive in const [false, true]) {
        yield RecurrenceFormatter.format(
          rule,
          l10n,
          l10n.localeName,
          retroactive: retroactive,
        );
      }
    }
  }

  @override
  List<String> candidates(AppLocalizations l10n) {
    final date = calendarGuideLongestDate(_dates.of(l10n));
    final title = l10n.calendarGuideDemoEventDentist;
    const counts = [0, 1, 2, 22, 31];
    return [
      l10n.calendarGuideDemoOneDay(date),
      for (final words in _widestRuleWords(l10n))
        for (final count in counts) l10n.calendarGuideDemoRepeats(words, count),
      for (final count in const [2, 22, 99])
        l10n.recurrenceSpecificDates(count),
      l10n.calendarGuideDemoSkipped(date, title),
    ];
  }

  /// What the rows that carry the rule's words and the picked day are
  /// sized for — every kind's widest words, and the widest short date — so
  /// a rule or a day changes words and never the stage. Once per language.
  ({List<String> words, String date}) _rowSizes(AppLocalizations l10n) {
    if (_rowSizesLocale != l10n.localeName) {
      _rowSizesLocale = l10n.localeName;
      _rowSizesCache = (
        words: {
          l10n.recurrenceNone,
          l10n.recurrenceSpecificDates(99),
          ..._widestRuleWords(l10n),
        }.toList(),
        date: calendarGuideLongestDate(_shortDates.of(l10n)),
      );
    }
    return _rowSizesCache;
  }

  ({List<String> words, String date}) _rowSizesCache = (
    words: const [],
    date: '',
  );
  String? _rowSizesLocale;

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

  /// [event]'s rule in words, written again only when the event or the
  /// language changes: the stage and the caption read it on every build.
  String _ruleWords(AppLocalizations l10n, CalendarEvent event) {
    if (!identical(event, _wordsEvent) || l10n.localeName != _wordsLocale) {
      _wordsEvent = event;
      _wordsLocale = l10n.localeName;
      _words = RecurrenceFormatter.format(
        event.rule,
        l10n,
        l10n.localeName,
        retroactive: event.retroactive,
      );
    }
    return _words;
  }

  CalendarEvent? _wordsEvent;
  String? _wordsLocale;
  String _words = '';

  /// The caption for the event as it now stands: one day, its dates, or
  /// its rule and how often it falls this month.
  void _sayShape(CalendarEvent event) {
    final start = event.startDateUtc;
    final count = _daysThisMonth(event);
    say(
      (l10n) => switch (event.rule) {
        OneTimeRecurrence() => l10n.calendarGuideDemoOneDay(
          _dates.of(l10n).format(start),
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
    final endDay = end == null
        ? null
        : DateTime.utc(end.year, end.month, end.day);
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

  /// The repeat sheet's last answer. The editor keeps its kind, interval,
  /// weekdays, end and "also before" through a switch to "does not repeat"
  /// for as long as it is open, so turning Repeat back on finds the rule she
  /// had; the event here keeps none of them once it stops repeating, so the
  /// demo keeps them for it.
  EventRepeatDraft? _lastDraft;

  static bool _repeats(CalendarEvent event) =>
      event.rule is! OneTimeRecurrence &&
      event.rule is! SpecificDatesRecurrence;

  Future<void> _repeat(BuildContext context, CalendarEvent event) async {
    final last = _lastDraft;
    final draft = _repeats(event) || last == null
        ? _draftOf(event)
        : last.copyWith(recurring: false);
    final picked = await EventRepeatSheet.show(
      context,
      draft: draft,
      startDate: event.startDateUtc,
      appearance: appearance,
    );
    if (picked == null) return;
    _lastDraft = picked;
    if (picked == draft) return;
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

  /// The month's marked and faded days, worked out again only when the
  /// event or its skips change, never on a rebuild that changed neither.
  ({int marked, int missed}) _masksOf(CalendarEvent event) {
    final key = (event, _skips.length);
    if (!identical(key.$1, _masksKey?.$1) || key.$2 != _masksKey?.$2) {
      _masksKey = key;
      _masks = (
        marked: _maskOf((day) => _occurs(event, day)),
        // A skipped day still belongs to a repeating event's pattern:
        // faded, as a missed one is, never gone.
        missed: event.rule is OneTimeRecurrence
            ? 0
            : _maskOf(
                (day) => event.occursOnUtcDay(day) && _skips.contains(day),
              ),
      );
    }
    return _masks;
  }

  (CalendarEvent, int)? _masksKey;
  ({int marked, int missed}) _masks = (marked: 0, missed: 0);

  void _skip(CalendarEvent event, DateTime day) {
    _skips.add(day);
    _picked = null;
    final title = calendarGuideQuote(event.title);
    say(
      (l10n) =>
          l10n.calendarGuideDemoSkipped(_dates.of(l10n).format(day), title),
    );
  }

  @override
  Widget buildStage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final event = _event ??= _seed(l10n);
    final colorScheme = Theme.of(context).colorScheme;
    final category = CalendarCategories.resolve(event.categoryId);
    final colorValue = event.colorValue;
    // The bar rule, not the avatar's: the event's own colour, else its
    // category's.
    final color = colorValue == null ? category.color : Color(colorValue);
    final words = _ruleWords(l10n, event);
    final picked = _picked;
    final canSkip =
        event.rule is! OneTimeRecurrence &&
        picked != null &&
        _occurs(event, picked);
    String control(String name) =>
        SemanticsIds.calendarGuideTryControl(slug, name);
    final sizes = _rowSizes(l10n);
    final masks = _masksOf(event);
    final avatar = EventAvatar(
      icon: CalendarCategories.iconFor(event),
      color: EventSummaryProvider.colorFor(event, category),
    );
    Widget titleRow(String words) =>
        FormReadTitleRow(leading: avatar, title: event.title, caption: words);
    Widget repeatRow(String words, {VoidCallback? onTap, String? id}) =>
        FormPickerRow(
          glyph: Icons.repeat_rounded,
          label: l10n.eventRepeat,
          value: words,
          identifier: id,
          onTap: onTap,
        );
    Widget dayRow(String? value, {VoidCallback? onTap, String? id}) =>
        FormPickerRow(
          glyph: Icons.calendar_today_outlined,
          label: l10n.eventDateLabel,
          value: value,
          identifier: id,
          onTap: onTap,
        );
    // A row as tall as the tallest of its candidates: the words wrap at a
    // large text size, and the row must not move what is under it when they
    // change. The group reads the hairline off its direct child, so the
    // wrapper carries the row's own indent.
    Widget sized(double indent, Iterable<Widget> candidates, Widget row) =>
        FormIndentedRow(
          dividerIndent: indent,
          child: FormCaptionSlot(
            alignment: AlignmentDirectional.centerStart,
            candidates: candidates.toList(),
            child: row,
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormRowGroup(
          children: [
            sized(
              FormMetrics.dividerIndentTitle,
              sizes.words.map(titleRow),
              titleRow(words),
            ),
            sized(
              FormMetrics.dividerIndentGlyph,
              [for (final w in sizes.words) repeatRow(w, onTap: () {})],
              repeatRow(
                words,
                id: control('repeat'),
                onTap: () => _repeat(context, event),
              ),
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
            sized(
              FormMetrics.dividerIndentGlyph,
              [dayRow(null, onTap: () {}), dayRow(sizes.date, onTap: () {})],
              dayRow(
                picked == null ? null : _shortDates.of(l10n).format(picked),
                id: control('day'),
                onTap: () => _pickDay(context, event),
              ),
            ),
            // A one-day event has nothing to skip, and the picked day must
            // be one it falls on; disabled until both hold.
            FormActionRow(
              glyph: Icons.event_busy_outlined,
              label: l10n.eventSkipOccurrence,
              identifier: control('skip'),
              onTap: canSkip ? () => _skip(event, picked) : null,
            ),
          ],
        ),
        // Drawn as the year tiles draw it, at a size she can read; what it
        // shows, the caption says.
        ExcludeSemantics(
          child: Center(
            child: SizedBox(
              width: MonthDotMatrix.width * GuideMetrics.stageMatrixScale,
              height: MonthDotMatrix.height * GuideMetrics.stageMatrixScale,
              child: FittedBox(
                child: MonthDotMatrix(
                  daysInMonth: _monthEnd.day,
                  firstWeekdayColumn: weekdayColumnOf(
                    _monthStart,
                    appearance.weekStart,
                  ),
                  markedMask: masks.marked,
                  missedMask: masks.missed,
                  windowMask: (1 << _monthEnd.day) - 1,
                  todayIndex: _today.day - 1,
                  markedColor: color,
                  missedColor: color.withValues(
                    alpha: CalendarColors.missedEventAlpha,
                  ),
                  unmarkedColor: colorScheme.outline.withValues(
                    alpha: MonthDotMatrix.unmarkedAlpha,
                  ),
                  outsideColor: colorScheme.outline.withValues(
                    alpha: MonthDotMatrix.outsideAlpha,
                  ),
                  todayColor: appearance.accentOr(colorScheme.primary),
                  backgroundColor: colorScheme.pageGround,
                  outlineColor: colorScheme.outline,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
