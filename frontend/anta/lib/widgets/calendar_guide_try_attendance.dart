import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/calendar_categories.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/calendar_guide_content.dart';
import '../models/calendar_guide_demo.dart';
import '../services/day_summary_resolver.dart';
import '../services/event_time_formatter.dart';
import '../utils/presence_stats.dart';
import 'calendar_guide_try_card.dart';
import 'event_avatar.dart';
import 'form_rows.dart';

/// The attendance page's card: the practice calendar's Yoga — tracked, its
/// four past weeks marked as the record's table 6 says — with today's row
/// wearing the day panel's presence button, the past weeks as chips, and the
/// editor's Count occurrences rows. Under the marks, the detail sheet's own
/// count, worked out by the real arithmetic over the demo's marks.
class GuideAttendanceDemo extends GuideCardDemo {
  GuideAttendanceDemo({DateTime Function() now = DateTime.now})
    : _today = _todayUtc(now()),
      super(CalendarGuideTopic.attendance);

  static const String slug = 'attendance';

  static DateTime _todayUtc(DateTime now) =>
      DateTime.utc(now.year, now.month, now.day);

  /// Date-only UTC, read once.
  final DateTime _today;

  /// The practice calendar's world, for its Yoga and its marks: the marks
  /// live there, never in `EventPresence`. Null until the first build, which
  /// names the seed in her language.
  GuideDemoCalendar? _calendar;

  bool _counting = false;
  OccurrenceCountStyle _countStyle = OccurrenceCountStyle.numbered;

  GuideDemoCalendar _calendarFor(AppLocalizations l10n) =>
      _calendar ??= GuideDemoCalendar(
        l10n: l10n,
        today: _today,
        categories: CalendarCategories.visible,
      );

  CalendarEvent _yoga(GuideDemoCalendar calendar) =>
      calendar.byId('${GuideDemoCalendar.idPrefix}yoga')!;

  /// The detail sheet's two presence captions on one line, under the marks
  /// that make it: the count she is watching (D49).
  String _statsLine(AppLocalizations l10n) {
    final stats = _statsFor(_calendarFor(l10n));
    if (stats == null) return '';
    return _summary(
      l10n,
      stats.attended,
      stats.total,
      stats.currentStreak,
      stats.longestStreak,
    );
  }

  /// The count over the window, worked out again only after a mark
  /// changes: the line is read on every build, and the count walks up to a
  /// year of days.
  PresenceStats? _statsFor(GuideDemoCalendar calendar) {
    if (!_statsFresh) {
      _stats = PresenceAdherence.compute(
        _yoga(calendar),
        today: _today,
        isMissed: calendar.isMissed,
      );
      _statsFresh = true;
    }
    return _stats;
  }

  PresenceStats? _stats;
  bool _statsFresh = false;

  final GuideLocaleFormat _shortDates = GuideLocaleFormat(DateFormat.MMMd);

  static String _summary(
    AppLocalizations l10n,
    int attended,
    int total,
    int current,
    int best,
  ) =>
      '${l10n.eventAdherenceSummary(attended, total, PresenceAdherence.windowDays)}'
      ' · ${l10n.eventAdherenceStreak(current, best)}';

  /// The stats line at its widest, for its slot: two-digit counts stand
  /// for the widest the numbers get in a 30-day window.
  static String _widestSummary(AppLocalizations l10n) =>
      _summary(l10n, 88, 88, 88, 88);

  /// The editor's count example for a weekly event (`_countStyleExample` in
  /// `event_editor_sheet.dart`, cut to the weekly kind): its first three
  /// occurrences, so the counting origin shows before anything is saved.
  static String _countExample(
    AppLocalizations l10n,
    OccurrenceCountStyle style,
  ) {
    String at(int n) => switch (style) {
      OccurrenceCountStyle.numbered => l10n.eventNumberedWeeks(n),
      OccurrenceCountStyle.elapsed => l10n.eventElapsedWeeks(n),
    };
    final first = style == OccurrenceCountStyle.numbered ? 1 : 0;
    return '${at(first)} · ${at(first + 1)} · ${at(first + 2)}';
  }

  static String _countStyleLabel(
    AppLocalizations l10n,
    OccurrenceCountStyle style,
  ) => switch (style) {
    OccurrenceCountStyle.numbered => l10n.eventCountStyleNumbered,
    OccurrenceCountStyle.elapsed => l10n.eventCountStyleElapsed,
  };

  /// The past occurrences inside the count's window, oldest first: the days
  /// the count reads besides today.
  List<DateTime>? _past;

  List<DateTime> _pastDays(CalendarEvent event) => [
    for (var back = PresenceAdherence.windowDays - 1; back >= 1; back--)
      if (event.occursOnUtcDay(
        DateTime.utc(_today.year, _today.month, _today.day - back),
      ))
        DateTime.utc(_today.year, _today.month, _today.day - back),
  ];

  void _flip(GuideDemoCalendar calendar, CalendarEvent event, DateTime day) {
    calendar.setPresence(event.id, day, missed: !calendar.isMissed(event, day));
    _statsFresh = false;
    did('flipped');
  }

  @override
  Widget buildStage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final calendar = _calendarFor(l10n);
    final event = _yoga(calendar);
    final category = CalendarCategories.resolve(event.categoryId);
    final time = event.time;
    final missedToday = calendar.isMissed(event, _today);
    final shortDates = _shortDates.of(l10n);
    final past = _past ??= _pastDays(event);
    String control(String name) =>
        SemanticsIds.calendarGuideTryControl(slug, name);
    return FormRowGroup(
      trailingGap: false,
      children: [
        FormPickerRow(
          leading: EventAvatar(
            icon: CalendarCategories.iconFor(event),
            color: EventSummaryProvider.colorFor(event, category),
          ),
          label: event.title,
          value: time == null
              ? l10n.eventAllDay
              : EventTimeFormatter.formatRangeOfContext(time, context),
          onTap: null,
          showChevron: false,
          // The day panel's presence button: its glyph says what a press
          // will make the day.
          trailingButton: FormTrailingButton(
            icon: missedToday
                ? Icons.event_available_rounded
                : Icons.event_busy_rounded,
            tooltip: missedToday ? l10n.eventMarkPresent : l10n.eventMarkMissed,
            identifier: control('today'),
            onPressed: () => _flip(calendar, event, _today),
          ),
        ),
        FormChipRow(
          glyph: Icons.how_to_reg_outlined,
          label: l10n.eventPresence,
          chips: [
            for (var i = 0; i < past.length; i++)
              // "Selected" alone does not say present: the chip's one node
              // carries the day's state word as its hint.
              MergeSemantics(
                child: Semantics(
                  hint: calendar.isMissed(event, past[i])
                      ? l10n.eventPresenceMissed
                      : l10n.eventPresencePresent,
                  child: FormChip(
                    label: shortDates.format(past[i]),
                    selected: !calendar.isMissed(event, past[i]),
                    identifier: control('day-$i'),
                    onTap: () => _flip(calendar, event, past[i]),
                  ),
                ),
              ),
          ],
          caption: FormCaptionSlot(
            candidates: [FormCaption(text: _widestSummary(l10n))],
            child: FormCaption(text: _statsLine(l10n)),
          ),
        ),
        FormSwitchRow(
          glyph: Icons.numbers_rounded,
          label: l10n.eventCountOccurrences,
          value: _counting,
          identifier: control('count'),
          onChanged: (value) {
            _counting = value;
            if (value) {
              did('counting');
            } else {
              changed();
            }
          },
        ),
        // Drawn while the switch is off too, disabled: the editor reveals
        // these, but here a reveal would move the caption and the page under
        // her finger.
        FormChipRow(
          chips: [
            for (final style in OccurrenceCountStyle.values)
              FormChip(
                label: _countStyleLabel(l10n, style),
                selected: _countStyle == style,
                identifier: control('count-${style.name}'),
                onTap: _counting
                    ? () {
                        _countStyle = style;
                        changed();
                      }
                    : null,
              ),
          ],
          caption: FormCaptionSlot(
            candidates: [
              for (final style in OccurrenceCountStyle.values)
                FormCaption(text: _countExample(l10n, style)),
            ],
            child: FormCaption(text: _countExample(l10n, _countStyle)),
          ),
        ),
      ],
    );
  }
}
