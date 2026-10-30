import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/app_spacing.dart';
import '../constants/calendar_bounds.dart';
import '../constants/calendar_categories.dart';
import '../constants/occurrence_descriptions.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/calendar_guide_content.dart';
import '../models/calendar_guide_demo.dart';
import '../models/recurrence_rule.dart';
import '../services/day_summary_resolver.dart';
import '../services/event_time_formatter.dart';
import '../services/settings_service.dart';
import '../utils/event_agenda.dart';
import '../utils/guide_locale_format.dart';
import 'calendar_add_fab.dart';
import 'calendar_date_picker_sheet.dart';
import 'calendar_guide_stage_slot.dart';
import 'calendar_guide_try_card.dart';
import 'event_avatar.dart';
import 'event_description_sheet.dart';
import 'event_detail_sheet.dart';
import 'event_editor_sheet.dart';
import 'event_template_picker_sheet.dart';
import 'form_rows.dart';

/// The events page's card: three demo events as rows and the calendar's own
/// + button. A row opens the real detail sheet and, from it, the real editor
/// in its sandbox mode; + adds through the same editor, and its long press
/// offers the owner's own templates. Every answer lands in this demo.
class GuideEventsDemo extends GuideCardDemo {
  GuideEventsDemo({DateTime Function() now = DateTime.now})
    : _today = _todayUtc(now()),
      super(CalendarGuideTopic.events.cards.single);

  static const String slug = 'events';

  /// What she adds beyond the three seed rows before the oldest of hers
  /// makes room: the demo stays a demo, not a list to manage.
  static const int maxAdded = 3;

  static DateTime _todayUtc(DateTime now) =>
      DateTime.utc(now.year, now.month, now.day);

  /// Date-only UTC, read once, as the practice page reads it.
  final DateTime _today;

  /// The add button stays round: nothing on this page scrolls it away.
  final ValueNotifier<bool> _fabExtended = ValueNotifier<bool>(false);

  /// Null until the first build, which names the seed in her language. The
  /// seed also sizes the stage.
  List<CalendarEvent>? _seedEvents;
  List<CalendarEvent>? _events;
  final Map<String, Set<DateTime>> _skips = {};

  /// The days' own texts of an event that keeps one per day, written by the
  /// detail sheet's quick edit and read back into the sheet.
  final Map<String, Map<DateTime, String>> _descriptions = {};
  int _nextId = 0;

  String? _descriptionOn(String id, DateTime day) => _descriptions[id]?[day];

  @override
  bool get needsAppearance => true;

  @override
  void dispose() {
    _fabExtended.dispose();
    super.dispose();
  }

  /// The Skipped report's date, short as the band's (D52): the long weekday
  /// date made the report the slot's tallest line, and the stage started
  /// below a 780 screen at 2.0 in German.
  final GuideLocaleFormat _dates = GuideLocaleFormat(DateFormat.MMMEd);

  @override
  List<String> reports(AppLocalizations l10n) {
    final quote = calendarGuideLongestQuote;
    final date = calendarGuideLongestDate(_dates.of(l10n));
    return [
      l10n.calendarGuideDemoSkipped(date, quote),
      l10n.calendarGuideWouldOpen(l10n.quickAlarmTitle),
    ];
  }

  /// The three seed rows of the record's table 6 — a timed one-time event,
  /// a weekly one and an all-day monthly one — in the built-in categories,
  /// each with its own glyph, so they look like three different things.
  List<CalendarEvent> _seed(AppLocalizations l10n) {
    return [
      CalendarEvent(
        id: '${GuideDemoCalendar.idPrefix}dentist',
        title: l10n.calendarGuideDemoEventDentist,
        categoryId: CalendarCategories.fallback.id,
        iconKey: 'medical_services',
        startDate: _today,
        time: const EventTime(startMinute: 9 * 60, durationMinutes: 45),
      ),
      CalendarEvent(
        id: '${GuideDemoCalendar.idPrefix}yoga',
        title: l10n.calendarGuideDemoEventYoga,
        categoryId: CalendarEventCategory.mobility.name,
        startDate: DateTime.utc(_today.year, _today.month, _today.day - 28),
        rule: WeeklyRecurrence(weekdays: {_today.weekday}),
        time: const EventTime(startMinute: 18 * 60, durationMinutes: 60),
      ),
      CalendarEvent(
        id: '${GuideDemoCalendar.idPrefix}rent',
        title: l10n.calendarGuideDemoEventRent,
        categoryId: CalendarCategories.fallback.id,
        iconKey: 'payments',
        startDate: DateTime.utc(_today.year, _today.month - 2, 1),
        rule: const MonthlyRecurrence(),
      ),
    ];
  }

  /// The seed's ids, which the cap never drops.
  static final Set<String> _seedIds = {
    '${GuideDemoCalendar.idPrefix}dentist',
    '${GuideDemoCalendar.idPrefix}yoga',
    '${GuideDemoCalendar.idPrefix}rent',
  };

  /// The control name of [event]'s row: its id without the demo prefix.
  static String rowControl(String eventId) =>
      'row-${eventId.replaceFirst(GuideDemoCalendar.idPrefix, '')}';

  /// [event] under a demo id: the editor stamps a bare uuid, and no stored
  /// event carries the prefix, so nothing a shared widget looks up by id can
  /// find the owner's data under it.
  CalendarEvent _demoId(CalendarEvent event) =>
      event.id.startsWith(GuideDemoCalendar.idPrefix)
      ? event
      : event.copyWith(id: '${GuideDemoCalendar.idPrefix}${event.id}');

  bool _occursOn(CalendarEvent event, DateTime day) =>
      event.occursOnUtcDay(day) && !(_skips[event.id]?.contains(day) ?? false);

  /// The day a row stands for: today when the event is on today, else its
  /// next day within a year, else its start.
  DateTime _dayOf(CalendarEvent event) {
    for (var offset = 0; offset <= 366; offset++) {
      final day = DateTime.utc(_today.year, _today.month, _today.day + offset);
      if (_occursOn(event, day)) return day;
    }
    return event.startDateUtc;
  }

  void _add(CalendarEvent event) {
    final events = _events!;
    final added = [
      for (final e in events)
        if (!_seedIds.contains(e.id)) e,
    ];
    final drop = added.length >= maxAdded ? added.first.id : null;
    _events = [
      for (final e in events)
        if (e.id != drop) e,
      event,
    ];
    if (drop != null) _skips.remove(drop);
  }

  void _replace(CalendarEvent event) {
    _events = [for (final e in _events!) e.id == event.id ? event : e];
  }

  void _remove(String id) {
    _events = [
      for (final e in _events!)
        if (e.id != id) e,
    ];
    _skips.remove(id);
  }

  Future<void> _addEvent(BuildContext context, DateTime day) async {
    final result = await EventEditorSheet.show(
      context,
      defaultDate: day,
      appearance: appearance,
      sandbox: true,
    );
    if (result is! EventEditorSaved) return;
    final event = _demoId(result.event);
    _add(event);
    final skipped = result.skippedDays;
    if (skipped != null && skipped.isNotEmpty) _skips[event.id] = {...skipped};
    did('added');
  }

  /// The add button's long press: the owner's own templates, read only, the
  /// one picked stamped out into the demo.
  Future<void> _addFromTemplate(BuildContext context, DateTime day) async {
    final choice = await EventTemplatePickerSheet.show(context);
    if (choice == null || !context.mounted) return;
    switch (choice) {
      case EventTemplatePicked(:final template):
        final event = template.buildEvent(
          id: '${GuideDemoCalendar.idPrefix}template-${_nextId++}',
          startDate: day,
        );
        _add(event);
        did('added');
      case EventTemplateBlank():
        await _addEvent(context, day);
      case EventTemplateQuickAlarm():
        say((l10n) => l10n.calendarGuideWouldOpen(l10n.quickAlarmTitle));
    }
  }

  /// The calendar's trip through an event's sheets, cut to what this page
  /// teaches: the detail sheet, then the editor from its Edit, with Back
  /// returning to the detail; a skip, a description and the dates the
  /// detail sheet changes are kept too.
  ///
  /// The coach steps the trip makes reach the line only when it returns: a
  /// sheet's barrier blocks the card's semantics, so a line changed under
  /// it would never be announced.
  Future<void> _open(BuildContext context, CalendarEvent event) async {
    final steps = ['opened'];
    void settle() {
      if (!context.mounted) return;
      for (final step in steps) {
        did(step);
      }
      steps.clear();
    }

    try {
      await _trip(context, event, steps, settle);
    } finally {
      settle();
    }
  }

  /// The trip's sheets; each coach step made is added to [steps], and
  /// [settle] applies them before a report the trip ends on.
  Future<void> _trip(
    BuildContext context,
    CalendarEvent event,
    List<String> steps,
    VoidCallback settle,
  ) async {
    var current = event;
    final day = _dayOf(event);
    while (true) {
      if (!context.mounted) return;
      final action = await EventDetailSheet.show(
        context,
        event: current,
        day: day,
        // Only while the event keeps one text per day, as the practice page
        // passes it: a dormant row must not show as the event's text.
        pendingOccurrenceDescription: OccurrenceDescriptions.appliesTo(current)
            ? _descriptionOn(current.id, day)
            : null,
      );
      if (action == null || !context.mounted) return;
      switch (action) {
        case EventDetailAction.skipOccurrence:
          (_skips[current.id] ??= {}).add(day);
          final title = calendarGuideQuote(current.title);
          // The report stands over the steps the trip made, not under them.
          settle();
          say(
            (l10n) => l10n.calendarGuideDemoSkipped(
              _dates.of(l10n).format(day),
              title,
            ),
          );
          return;
        case EventDetailAction.edit:
          final result = await EventEditorSheet.show(
            context,
            defaultDate: day,
            initialEvent: current,
            appearance: appearance,
            showBack: true,
            sandbox: true,
            initialSkippedDays: _skips[current.id] ?? const {},
          );
          switch (result) {
            case null:
              return;
            case EventEditorBack():
              continue;
            case EventEditorDeleted():
              _remove(current.id);
              steps.add('deleted');
              return;
            case EventEditorSaved():
              current = result.event;
              _replace(current);
              final skipped = result.skippedDays;
              if (skipped != null) _skips[current.id] = {...skipped};
              steps.add('changed');
              // The stage under the sheet redraws; the line waits.
              notifyListeners();
              if (!_occursOn(current, day)) return;
          }
        // The practice page's handling (`_eventTrip`), on this demo's list.
        case EventDetailAction.editDescription:
          final edited = await _editDescription(context, current, day);
          if (edited == null || !context.mounted) continue;
          current = edited;
          steps.add('changed');
          notifyListeners();
        case EventDetailAction.addDate:
        case EventDetailAction.showDates:
          final dates = current.explicitDates;
          if (dates == null) continue;
          final picked = await CalendarDatePickerSheet.pickMulti(
            context,
            initialSelection: dates,
            firstDate: CalendarBounds.earliest,
            lastDate: CalendarBounds.latest,
            dayLoad: (d) => _events!.where((e) => _occursOn(e, d)).length,
            appearance: appearance,
            initialView: action == EventDetailAction.showDates
                ? CalendarDatePickerView.list
                : CalendarDatePickerView.month,
          );
          if (!context.mounted) return;
          if (picked == null || setEquals(picked, dates)) continue;
          current = current.withExplicitDates(picked);
          _replace(current);
          steps.add('changed');
          notifyListeners();
          if (!_occursOn(current, day)) return;
        // A demo event carries no note: the sandboxed editor has no Linked
        // note row.
        case EventDetailAction.openNote:
          return;
      }
    }
  }

  /// The detail sheet's quick description edit, as the practice page opens
  /// it (`_editDescription`): the day's own text for an event that keeps
  /// one per day, else the event's. Null when nothing changed.
  Future<CalendarEvent?> _editDescription(
    BuildContext context,
    CalendarEvent event,
    DateTime day,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final perDay = OccurrenceDescriptions.appliesTo(event);
    final seed = perDay
        ? (_descriptionOn(event.id, day) ?? event.description ?? '')
        : (event.description ?? '');
    final settings = await SettingsService.getInstance();
    final limit = await settings.getEventDescriptionLimit();
    if (!context.mounted) return null;
    final edited = await EventDescriptionSheet.show(
      context,
      initialText: seed,
      heading: event.title,
      limit: limit,
      grandfatheredLength: seed.length,
      scopeCaption: perDay
          ? l10n.eventDescriptionScopeThisDayHint
          : (event.rule is OneTimeRecurrence
                ? null
                : l10n.eventDescriptionAppliesAllOccurrences),
    );
    if (edited == null || edited == seed) return null;
    if (perDay) {
      (_descriptions[event.id] ??= {})[day] = edited;
      return event;
    }
    final updated = event.copyWith(
      description: edited,
      clearDescription: edited.isEmpty,
    );
    _replace(updated);
    return updated;
  }

  Widget _row(BuildContext context, CalendarEvent event) {
    final l10n = AppLocalizations.of(context)!;
    final category = CalendarCategories.resolve(event.categoryId);
    final time = event.time;
    return FormPickerRow(
      leading: EventAvatar(
        icon: CalendarCategories.iconFor(event),
        color: EventSummaryProvider.colorFor(event, category),
      ),
      label: event.title,
      value: time == null
          ? l10n.eventAllDay
          : EventTimeFormatter.formatRangeOfContext(time, context),
      identifier: SemanticsIds.calendarGuideTryControl(
        slug,
        rowControl(event.id),
      ),
      onTap: () => _open(context, event),
    );
  }

  Widget _rows(BuildContext context, List<CalendarEvent> events) {
    if (events.isEmpty) return const SizedBox.shrink();
    final sorted = [...events]..sort(EventAgenda.compareWithinDay);
    return FormRowGroup(
      trailingGap: false,
      children: [for (final event in sorted) _row(context, event)],
    );
  }

  @override
  Widget buildStage(BuildContext context) {
    final seed = _seedEvents ??= _seed(AppLocalizations.of(context)!);
    final events = _events ??= seed;
    return Stack(
      children: [
        // The stage's height: the three seed rows over the add button's
        // clearance, laid out unseen, so adding or deleting a row never
        // moves the card or the page under her finger. The rows scroll
        // inside it once she has added more.
        ExcludeSemantics(
          child: ExcludeFocus(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _rows(context, seed),
                    const SizedBox(height: AppSpacing.fabClearance),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: GuideStageSlot(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: AppSpacing.fabClearance),
              child: _rows(context, events),
            ),
          ),
        ),
        PositionedDirectional(
          end: 0,
          bottom: 0,
          child: CalendarAddFab(
            selectedDay: _today,
            appearance: appearance,
            extended: _fabExtended,
            identifier: SemanticsIds.calendarGuideTryControl(slug, 'add'),
            onPressed: (day) => _addEvent(context, day),
            onLongPressed: (day) => _addFromTemplate(context, day),
          ),
        ),
      ],
    );
  }
}
