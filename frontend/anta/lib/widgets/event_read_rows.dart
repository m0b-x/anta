import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/calendar_categories.dart';
import '../constants/event_priorities.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/partner_look.dart';
import '../models/recurrence_rule.dart';
import '../services/day_summary_resolver.dart';
import '../services/event_time_formatter.dart';
import '../services/recurrence_formatter.dart';
import '../utils/line_based_markdown_builder.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/money_display_config.dart';
import 'automation_id.dart';
import 'calendar_date_picker_sheet.dart';
import 'event_avatar.dart';
import 'form_rows.dart';
import 'simple_markdown_preview.dart';

/// The read rows of one event on one day, shared by the detail sheet of my
/// own events and the read sheet of a partner's (share surfaces §8): the
/// title row, the WHEN rows and Priority are built here once, so the two
/// sheets cannot drift apart in a word or a pixel.
///
/// Holds what the rows resolve once per sheet — the next occurrences, the
/// pinned set, today — rather than in `build`: the scan walks up to 366 days
/// and a sheet's body rebuilds on every scroll-driven frame.
class EventReadFacts {
  /// How far ahead the "next occurrence" scan looks, in days. Matches the
  /// agenda's clamp so the two never disagree about what is upcoming.
  static const int _scanDays = 366;

  /// How many upcoming dates to resolve: the next one for the row's value and
  /// the three the caption under it lists.
  static const int _maxOccurrences = 4;

  final CalendarEvent event;

  /// The occurrence being read (date-only UTC).
  final DateTime day;

  EventReadFacts(this.event, this.day);

  /// Next days the event fires on after the viewed occurrence.
  late final List<DateTime> upcoming = _computeUpcoming();

  /// The pinned set, sorted once, or null for any other rule.
  late final List<DateTime>? explicitDates =
      event.rule is SpecificDatesRecurrence
      ? (event.explicitDates!.toList()..sort())
      : null;

  /// Today, read once with [upcoming]: the Dates row's "ahead" count runs on
  /// every build, and a sheet does not straddle midnight.
  late final DateTime today = () {
    final now = DateTime.now();
    return DateTime.utc(now.year, now.month, now.day);
  }();

  List<DateTime> _computeUpcoming() {
    // A one-time event has nothing to project, and a pinned-dates event
    // reads its set from the Dates row instead.
    if (event.explicitDates != null) return const [];
    // "Next" is measured from the occurrence being viewed, never from the
    // past: opened on today or a later day, the scan starts the day after it,
    // so the row never repeats the Date row above; opened on a past day it
    // starts today — the next one that can still be attended.
    final start = day.isBefore(today)
        ? today
        : day.add(const Duration(days: 1));
    final days = <DateTime>[];
    for (var i = 0; i < _scanDays && days.length < _maxOccurrences; i++) {
      final candidate = start.add(Duration(days: i));
      if (event.occursOn(candidate)) days.add(candidate);
    }
    return days;
  }

  /// The day-panel row's twin at the top of a read sheet: the event's
  /// avatar — in [partner]'s look for a partner's event — its title at the
  /// editor's size so Edit and Back never resize it, and the category as the
  /// caption a reader wants under a name.
  FormReadTitleRow titleRow(AppLocalizations l10n, {PartnerLook? partner}) {
    final category = CalendarCategories.resolve(event.categoryId);
    return FormReadTitleRow(
      leading: EventAvatar.ofRow(
        icon: CalendarCategories.iconFor(event),
        color: EventSummaryProvider.colorFor(event, category),
        partner: partner,
        l10n: l10n,
      ),
      title: event.title,
      caption: CalendarCategories.labelOf(category, l10n),
    );
  }

  /// "Sat, May 10 · 30 years": a day with the count label appended when the
  /// event counts its occurrences, so a birthday reads as the coming age and
  /// a program as its coming week.
  String _dayLabel(DateTime date, DateFormat format, AppLocalizations l10n) {
    final label = format.format(date);
    final count = RecurrenceFormatter.countLabel(event, date, l10n);
    return count == null ? label : '$label · $count';
  }

  String _timeValue(BuildContext context, AppLocalizations l10n) {
    final time = event.time;
    if (time == null) return l10n.eventAllDay;
    // The device's 12h/24h preference, as the alert rows below and the
    // editor's Starts / Ends read it — one clock on the sheet and across
    // the Edit → Back loop. The panel row behind is service-side text and
    // cannot follow the preference; that gap is older than this sheet.
    final range = EventTimeFormatter.formatRangeOfContext(time, context);
    final duration = time.durationMinutes;
    if (duration == null) return range;
    return '$range · ${EventTimeFormatter.formatDuration(duration, l10n)}';
  }

  /// Exactly the editor's Repeat value, "until" included, so Edit and Back
  /// show one string for the rule.
  String _repeatValue(AppLocalizations l10n, String localeName) {
    final label = RecurrenceFormatter.format(
      event.rule,
      l10n,
      localeName,
      retroactive: event.retroactive,
    );
    final end = event.endDate;
    if (end == null) return label;
    return l10n.recurrenceUntilSuffix(
      label,
      DateFormat.yMMMd(localeName).format(end),
    );
  }

  String _nextValue(AppLocalizations l10n, DateFormat format) {
    if (upcoming.isEmpty) return l10n.eventDetailsNoOccurrences;
    return _dayLabel(upcoming.first, format, l10n);
  }

  String? _thenCaption(AppLocalizations l10n, DateFormat format) {
    if (upcoming.length < 2) return null;
    return l10n.eventDetailsThen(
      upcoming.skip(1).map(format.format).join(' · '),
    );
  }

  /// The WHEN group's rows. [onShowDates] makes the pinned set's bundled
  /// row a way into its list, null leaves it a read row; [onAddDate] adds
  /// the Add date row, which writes and so exists only where the event is
  /// mine.
  List<Widget> whenRows(
    BuildContext context,
    AppLocalizations l10n, {
    VoidCallback? onShowDates,
    VoidCallback? onAddDate,
  }) {
    final localeName = l10n.localeName;
    final dayFormat = DateFormat.yMMMEd(localeName);
    final shortFormat = DateFormat.MMMEd(localeName);
    final periodic =
        event.rule is! OneTimeRecurrence &&
        event.rule is! SpecificDatesRecurrence;
    return [
      // The occurrence the sheet was opened for, not the series start — it is
      // the day the presence chips below mark and the day whose description
      // renders above. A one-time event's occurrence *is* its date.
      FormPickerRow(
        glyph: Icons.calendar_today_outlined,
        label: l10n.eventDateLabel,
        value: _dayLabel(day, dayFormat, l10n),
        onTap: null,
        showChevron: false,
      ),
      // A pinned set never gets per-date rows here: the editor's exist for
      // their ✕, and a reader has nothing to do per date. One bundled row
      // reads the set back and opens the list that holds all of it.
      if (explicitDates case final dates?)
        FormPickerRow(
          glyph: Icons.event_note_outlined,
          identifier: SemanticsIds.eventDetailDates,
          label: l10n.eventDatesLabel,
          value: CalendarDatePickerSheet.datesValue(l10n, dates, today),
          onTap: onShowDates,
          showChevron: onShowDates != null,
        ),
      if (event.explicitDates != null && onAddDate != null)
        FormActionRow(
          glyph: Icons.add_rounded,
          identifier: SemanticsIds.eventDetailAddDate,
          label: l10n.eventAddDate,
          onTap: onAddDate,
        ),
      FormPickerRow(
        glyph: Icons.schedule_outlined,
        label: l10n.eventTime,
        value: _timeValue(context, l10n),
        onTap: null,
        showChevron: false,
      ),
      if (periodic) ...[
        FormPickerRow(
          glyph: Icons.repeat_rounded,
          label: l10n.eventRepeat,
          value: _repeatValue(l10n, localeName),
          onTap: null,
          showChevron: false,
        ),
        // The anchor the pattern is measured from, only when it is not the
        // day already at the top of the group. Both dates are date-only UTC,
        // so plain equality is exact.
        if (day != event.startDate)
          FormPickerRow(
            glyph: Icons.event_repeat_outlined,
            label: l10n.eventDate,
            value: dayFormat.format(event.startDate),
            onTap: null,
            showChevron: false,
          ),
        FormPickerRow(
          glyph: Icons.next_plan_outlined,
          label: l10n.eventDetailsNext,
          value: _nextValue(l10n, shortFormat),
          caption: _thenCaption(l10n, shortFormat),
          onTap: null,
          showChevron: false,
        ),
      ],
    ];
  }

  /// DETAILS' Priority, read, while it is not the default.
  FormPickerRow? priorityRow(AppLocalizations l10n) {
    if (event.priority == kDefaultEventPriority) return null;
    return FormPickerRow(
      glyph: Icons.flag_outlined,
      label: l10n.eventPriority,
      value: EventPriorities.labelOf(event.priority, l10n),
      onTap: null,
      showChevron: false,
    );
  }
}

/// The editor's description cell read back: the same padding, so one line is
/// a 48 dp row and the text sits where the editor's caret line sits, the
/// pencil where the editor's expand button sits. Rendered in full, with no
/// scrollable of its own — the sheet's body owns every vertical drag.
///
/// Empty, the whole cell is the way into the quick edit; the pencil stays in
/// both states so the target the hand learned does not move. With no
/// [onEdit] — a partner's event, which is read here and never written —
/// there is no pencil and the text runs to the group's own inset (decision
/// p), and an empty cell is never built.
class EventDescriptionCell extends FormDividedRow {
  final String text;
  final String? placeholder;
  final String? editTooltip;
  final String? identifier;
  final MarkdownColorPalette colorPalette;
  final CheckboxTapCallback? onCheckboxTap;
  final WikiLinkTapCallback? onTapWikiLink;
  final VoidCallback? onEdit;
  final String? inertCaption;

  const EventDescriptionCell({
    super.key,
    required this.text,
    required this.colorPalette,
    required this.onCheckboxTap,
    required this.onTapWikiLink,
    this.placeholder,
    this.editTooltip,
    this.identifier,
    this.onEdit,
    this.inertCaption,
  }) : assert(
         onEdit == null ||
             (placeholder != null && editTooltip != null && identifier != null),
       );

  @override
  double get dividerIndent => FormMetrics.dividerIndentPlain;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final edit = onEdit;
    final empty = text.isEmpty;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: FormMetrics.rowMinHeight),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          RowMetrics.groupInset,
          FormMetrics.descriptionCellPadding,
          edit == null ? RowMetrics.groupInset : FormMetrics.trailingButtonSize,
          FormMetrics.descriptionCellPadding,
        ),
        child: empty
            ? Text(
                placeholder ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: FormMetrics.descriptionFontSize,
                  height:
                      FormMetrics.descriptionLineHeight /
                      FormMetrics.descriptionFontSize,
                  color: colorScheme.onSurfaceVariant,
                ),
              )
            : SimpleMarkdownPreview(
                data: text,
                fontSize: FormMetrics.descriptionFontSize,
                padding: EdgeInsets.zero,
                scrollable: false,
                colorPalette: colorPalette,
                moneyConfig: MoneyDisplayConfig.disabled,
                onCheckboxTap: onCheckboxTap,
                onTapWikiLink: onTapWikiLink,
              ),
      ),
    );
    if (edit == null) return content;
    final caption = inertCaption;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Passthrough, not loose: a loose stack would size the ink well to
        // the placeholder's own width, and a thumb landing right of the
        // words would hit nothing. The column above is stretched, so this
        // hands the well the whole cell.
        Stack(
          fit: StackFit.passthrough,
          children: [
            if (empty)
              MergeSemantics(
                child: Semantics(
                  button: true,
                  child: InkWell(onTap: edit, child: content),
                ),
              )
            else
              content,
            Positioned(
              top: 0,
              right: 0,
              child: AutomationId(
                identifier: identifier!,
                child: FormTrailingButton(
                  icon: Icons.edit_note_rounded,
                  tooltip: editTooltip!,
                  onPressed: edit,
                ),
              ),
            ),
          ],
        ),
        if (caption != null)
          FormCaption(
            text: caption,
            padding: const EdgeInsets.fromLTRB(
              RowMetrics.groupInset,
              0,
              RowMetrics.groupInset,
              FormMetrics.descriptionCaptionBottomPadding,
            ),
          ),
      ],
    );
  }
}
