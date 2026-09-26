import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../constants/app_colors.dart';
import '../constants/calendar_categories.dart';
import '../constants/event_alerts.dart';
import '../constants/event_presence.dart';
import '../constants/event_priorities.dart';
import '../constants/event_skips.dart';
import '../constants/occurrence_descriptions.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/event_alert.dart';
import '../models/recurrence_rule.dart';
import '../services/alert_scheduler.dart';
import '../services/day_summary_resolver.dart';
import '../services/event_time_formatter.dart';
import '../services/recurrence_formatter.dart';
import '../utils/line_based_markdown_builder.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/markdown_list_syntax.dart';
import '../utils/money_display_config.dart';
import '../utils/presence_stats.dart';
import 'automation_id.dart';
import 'calendar_date_picker_sheet.dart';
import 'event_avatar.dart';
import 'form_rows.dart';
import 'simple_markdown_preview.dart';

/// What the user chose to do from the detail sheet.
///
/// [editDescription] carries no payload on purpose: the caller re-resolves
/// which text is being edited, using exactly the rule a checkbox tick uses, so
/// a quick edit and a tick can never write to different places.
enum EventDetailAction {
  edit,
  editDescription,
  openNote,
  skipOccurrence,
  addDate,
  showDates,
}

/// Read-only view of a single [CalendarEvent] — the editor's twin.
///
/// Tapping a day-panel row lands here rather than straight in the edit form:
/// with descriptions being real markdown content, the first thing a tap should
/// do is *show* the event. Editing stays one button away, and because the
/// page's loop reopens this sheet after every Save and every Back, the two
/// surfaces alternate on screen: this sheet keeps the editor's groups in the
/// editor's order with the editor's glyphs (the 2026-09-26 redesign,
/// `docs/event-detail-sheet-redesign-roadmap.md`), so nothing moves between
/// the two. What keeps it from being a second form is the read rule — a row
/// exists only when it carries a fact, and a group with no rows is absent.
///
/// The description renders through the same builder as the note preview, with
/// the money ledger off — a balance is a per-note concept, so `$` rows in an
/// event description stay literal text.
///
/// The sheet is always opened **for a specific [day]**, because since v24 a
/// recurring event's description can differ per occurrence.
///
/// Task checkboxes are tappable when a tick has one unambiguous meaning:
/// either the event fires on exactly one day ([OneTimeRecurrence], where the
/// tick edits the event itself), or per-occurrence descriptions are on (where
/// it materialises a row for [day] and leaves every other day alone). With the
/// setting off, a repeating event still keeps inert boxes — one string shared
/// by every occurrence would read as ticked on all of them.
class EventDetailSheet extends StatefulWidget {
  /// How far ahead the "next occurrence" scan looks, in days. Matches the
  /// agenda's clamp so the two never disagree about what is upcoming.
  static const int _scanDays = 366;

  /// How many upcoming dates to resolve: the next one for the row's value and
  /// the three the caption under it lists.
  static const int _maxOccurrences = 4;

  /// How long a checkbox toggle waits before it is handed to [onEventChanged].
  /// Ticking a short list is a burst, and every write invalidates the bloc's
  /// day cache, so the taps coalesce into one update instead of one each.
  static const Duration _writeDelay = Duration(milliseconds: 600);

  final CalendarEvent event;

  /// The occurrence being viewed (date-only UTC). Decides which description
  /// renders and which day a checkbox tick materialises.
  final DateTime day;

  final MarkdownColorPalette colorPalette;

  /// This day's text as a just-dispatched write left it, when that write may
  /// not have reached the database yet. Null means "read the facade".
  ///
  /// Closes the same race the editor sheet's `pendingOccurrenceDescription`
  /// closes, in the other direction: the page reopens this sheet in the same
  /// turn it dispatches an occurrence write, so reading the facade here would
  /// show the pre-edit text.
  ///
  /// Only meaningful while the event separates its days — the caller drops it
  /// once `OccurrenceDescriptions.appliesTo` is false, because a dormant row
  /// must not render as if it were the template.
  final String? pendingOccurrenceDescription;

  /// Receives the event with its description rewritten after a checkbox
  /// toggle, for events whose description is shared. Null makes the boxes
  /// inert — the caller opts in by wiring the persistence. Called at most once
  /// per burst of taps, and once more on dismissal if a burst is pending.
  final ValueChanged<CalendarEvent>? onEventChanged;

  /// Receives `(day, description)` when the tick belongs to one occurrence.
  ///
  /// Deliberately separate from [onEventChanged] rather than reusing it with a
  /// rewritten event: the caller feeds that event straight into the editor as
  /// `initialEvent`, so routing a *day's* text through it would hand the
  /// editor an event whose template field holds one occurrence's text.
  final void Function(DateTime day, String description)? onOccurrenceChanged;

  /// Receives `(day, missed)` when the user changes this occurrence's
  /// presence (**v26**). Null hides the control entirely — the caller opts in
  /// by wiring the persistence, exactly like [onOccurrenceChanged]. Fired
  /// immediately: a two-state toggle has nothing to coalesce.
  final void Function(DateTime day, bool missed)? onPresenceChanged;

  /// Receives the raw inner text of a `[[title]]` the description's preview
  /// reports as tapped, **after** this sheet has already closed. Null leaves
  /// wiki links inert, exactly like [onOccurrenceChanged] — the caller opts in
  /// by wiring the navigation.
  ///
  /// The sheet never navigates itself: it pops with an [EventDetailAction] and
  /// the host acts. A wiki link has no action to pop with, so it pops with
  /// null and hands the title over instead, and the order matters both ways —
  /// a snackbar for an unresolvable title cannot be seen behind a modal sheet,
  /// and the editor for a resolvable one has to be pushed over the calendar
  /// page rather than over a sheet that is about to be dismissed.
  final ValueChanged<String>? onOpenWikiLink;

  /// Resolves the linked note's title for the Linked note row, or `null` once
  /// the note no longer exists. Null leaves the row's value empty — the caller
  /// opts in by wiring the lookup, exactly like [onOpenWikiLink], so the sheet
  /// never reaches into a repository itself and a widget test needs no
  /// service locator to open it.
  final Future<String?> Function(String noteId)? resolveNoteTitle;

  const EventDetailSheet({
    super.key,
    required this.event,
    required this.day,
    this.colorPalette = MarkdownColorPalette.presets,
    this.pendingOccurrenceDescription,
    this.onEventChanged,
    this.onOccurrenceChanged,
    this.onPresenceChanged,
    this.onOpenWikiLink,
    this.resolveNoteTitle,
  });

  /// The sub-sheet shape: as tall as its content, clamped at the editor's
  /// height, the route's own drag. There is no discard guard because the sheet
  /// holds nothing that can be lost — a pending tick is flushed on every exit.
  static Future<EventDetailAction?> show(
    BuildContext context, {
    required CalendarEvent event,
    required DateTime day,
    MarkdownColorPalette colorPalette = MarkdownColorPalette.presets,
    String? pendingOccurrenceDescription,
    ValueChanged<CalendarEvent>? onEventChanged,
    void Function(DateTime day, String description)? onOccurrenceChanged,
    void Function(DateTime day, bool missed)? onPresenceChanged,
    ValueChanged<String>? onOpenWikiLink,
    Future<String?> Function(String noteId)? resolveNoteTitle,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<EventDetailAction>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: colorScheme.pageGround,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FormMetrics.sheetRadius),
        ),
      ),
      builder: (context) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.sizeOf(context).height * FormMetrics.sheetHeightFactor,
        ),
        child: EventDetailSheet(
          event: event,
          day: day,
          colorPalette: colorPalette,
          pendingOccurrenceDescription: pendingOccurrenceDescription,
          onEventChanged: onEventChanged,
          onOccurrenceChanged: onOccurrenceChanged,
          onPresenceChanged: onPresenceChanged,
          onOpenWikiLink: onOpenWikiLink,
          resolveNoteTitle: resolveNoteTitle,
        ),
      ),
    );
  }

  @override
  State<EventDetailSheet> createState() => _EventDetailSheetState();
}

class _EventDetailSheetState extends State<EventDetailSheet> {
  /// Next days the event fires on after the viewed occurrence. Resolved
  /// **once**: the scan walks up to 366 days and the body rebuilds on every
  /// scroll-driven frame, so doing it in `build` would re-run it each time.
  late final List<DateTime> _upcoming = _computeUpcoming();

  /// The pinned set, sorted once, or null for any other rule.
  late final List<DateTime>? _explicitDates =
      widget.event.rule is SpecificDatesRecurrence
      ? (widget.event.explicitDates!.toList()..sort())
      : null;

  /// Today, read once with [_upcoming]: the Dates row's "ahead" count runs on
  /// every build, and a sheet does not straddle midnight.
  late final DateTime _today = () {
    final now = DateTime.now();
    return DateTime.utc(now.year, now.month, now.day);
  }();

  /// Working copy of this day's description, trimmed on entry so the offsets
  /// the builder reports for a checkbox address exactly this string. Rendering
  /// a trimmed copy while rewriting the untrimmed original would shift every
  /// bracket by the leading whitespace.
  ///
  /// Resolved for [widget.day], so a per-occurrence event shows its override
  /// and every other event shows the shared description. A write still in
  /// flight beats the facade — see [EventDetailSheet.pendingOccurrenceDescription].
  late String _description =
      (widget.pendingOccurrenceDescription ??
              OccurrenceDescriptions.descriptionFor(widget.event, widget.day))
          ?.trim() ??
      '';

  Timer? _writeTimer;
  bool _pendingWrite = false;

  /// This occurrence's presence, seeded from the facade and updated locally so
  /// the chips reflect the tap before the write lands.
  late bool _missed = EventPresence.isMissed(widget.event, widget.day);

  /// Adherence over the trailing window. Held in state rather than derived in
  /// `build` for the same reason as [_upcoming]: the walk covers up to 366
  /// days. Recomputed by [_setMissed] so the numbers move with the chips
  /// instead of waiting for a reopen.
  late PresenceStats? _stats = _computeStats();

  /// The event's alerts, read once from the synchronous facade. Rebuilding
  /// this list in `build` would be another map probe per scroll frame for a
  /// set that cannot change while a read-only sheet is open.
  late final List<EventAlert> _alerts = EventAlerts.alertsFor(widget.event.id);

  /// When each alert is next due, keyed by alert id — resolved **once** from
  /// the registry, never in `build`, exactly like [_upcoming].
  ///
  /// Empty until the read lands, and empty forever on a platform with no
  /// registry at all: the row still names the alert, it simply cannot add a
  /// date to it.
  Map<String, DateTime> _nextFires = const {};

  /// The linked note's title once [EventDetailSheet.resolveNoteTitle] answers.
  /// Null with [_noteMissing] false is "not answered yet" and renders an empty
  /// value — never a flash of "Untitled Note" for a note that has a name.
  String? _noteTitle;
  bool _noteMissing = false;

  /// The body's scroll position feeds the header's hairline (a form sheet's
  /// rule): a notifier, never `setState`, so a scroll frame rebuilds a 1 px
  /// line and not the sheet.
  final ScrollController _bodyScroll = ScrollController();
  final ValueNotifier<bool> _headerScrolled = ValueNotifier<bool>(false);

  /// Whether the present/missed control is offered at all: the event opts in,
  /// the rule repeats, and the caller wired persistence.
  bool get _presenceVisible =>
      widget.onPresenceChanged != null && EventPresence.appliesTo(widget.event);

  PresenceStats? _computeStats() {
    return PresenceAdherence.compute(
      widget.event,
      today: DateTime.now(),
      // The facade may not have the write yet, so this day's answer comes
      // from the local copy the chips already reflect.
      overrideDay: widget.day,
      overrideMissed: _missed,
    );
  }

  /// A discrete two-state toggle has nothing to coalesce, so unlike a burst of
  /// checkbox taps this writes through immediately.
  void _setMissed(bool missed) {
    if (missed == _missed) return;
    HapticFeedback.lightImpact();
    setState(() {
      _missed = missed;
      _stats = _computeStats();
    });
    widget.onPresenceChanged!(widget.day, missed);
  }

  /// Whether the tick belongs to this one occurrence rather than to the whole
  /// event. Drives which callback [_flushWrite] uses.
  bool get _perOccurrence =>
      widget.onOccurrenceChanged != null &&
      OccurrenceDescriptions.appliesTo(widget.event);

  /// Whether a checkbox tap edits anything at all. Either the event fires on a
  /// single day (the tick edits the event), or per-occurrence descriptions are
  /// on (the tick materialises this day). See the class doc.
  bool get _tasksInteractive {
    if (_perOccurrence) return true;
    return widget.onEventChanged != null &&
        widget.event.rule is OneTimeRecurrence;
  }

  /// Whether the description contains at least one task box, so the caption
  /// explaining why the boxes are inert only appears where there is something
  /// to tick. Read through the shared list grammar — never a second scan for a
  /// construct that already has one.
  bool get _hasTaskBox => _description
      .split('\n')
      .any(
        (line) => MarkdownListSyntax.parse(line)?.kind == MarkdownListKind.task,
      );

  @override
  void initState() {
    super.initState();
    _bodyScroll.addListener(_onBodyScroll);
    if (_alerts.isNotEmpty) unawaited(_resolveNextFires());
    if (widget.event.noteId != null) unawaited(_loadNoteTitle());
  }

  void _onBodyScroll() {
    final scrolled = _bodyScroll.hasClients && _bodyScroll.offset > 0;
    if (_headerScrolled.value != scrolled) _headerScrolled.value = scrolled;
  }

  Future<void> _resolveNextFires() async {
    final next = await AlertScheduler.nextFiresForEventById(widget.event.id);
    if (!mounted || next.isEmpty) return;
    setState(() => _nextFires = next);
  }

  Future<void> _loadNoteTitle() async {
    final resolve = widget.resolveNoteTitle;
    final id = widget.event.noteId;
    if (resolve == null || id == null) return;
    final String? title;
    try {
      title = await resolve(id);
    } catch (_) {
      // A lookup that throws — a database switched under the sheet, a
      // closed one after a relaunch — leaves the row in its loading state
      // rather than surfacing as an unhandled async error, the rule the
      // alert lookup follows inside `AlertScheduler.nextFiresForEventById`.
      return;
    }
    if (!mounted) return;
    setState(() {
      _noteMissing = title == null;
      _noteTitle = title;
    });
  }

  @override
  void dispose() {
    _bodyScroll.removeListener(_onBodyScroll);
    _bodyScroll.dispose();
    _headerScrolled.dispose();
    _writeTimer?.cancel();
    _writeTimer = null;
    // Drag-dismiss and the system back gesture never route through
    // [_close], so the last burst of taps is flushed here.
    _flushWrite();
    super.dispose();
  }

  /// Rewrites the `[ ]` / `[x]` bracket spanning [start]..[end] and schedules
  /// the persist. The UI updates immediately; only the write is delayed.
  void _toggleTask(int start, int end, bool isChecked) {
    if (start < 0 || end > _description.length || start >= end) return;
    HapticFeedback.lightImpact();
    setState(() {
      _description = _description.replaceRange(
        start,
        end,
        isChecked ? '[ ]' : '[x]',
      );
      _pendingWrite = true;
    });
    _writeTimer?.cancel();
    _writeTimer = Timer(EventDetailSheet._writeDelay, _flushWrite);
  }

  void _flushWrite() {
    _writeTimer?.cancel();
    _writeTimer = null;
    if (!_pendingWrite) return;
    _pendingWrite = false;
    if (_perOccurrence) {
      // Materialises a row for this day only; every other occurrence keeps
      // falling back to the event's template.
      widget.onOccurrenceChanged!(widget.day, _description);
      return;
    }
    widget.onEventChanged?.call(
      widget.event.copyWith(
        description: _description,
        clearDescription: _description.isEmpty,
      ),
    );
  }

  /// Whether this sheet has already asked to pop, so a second exit can never
  /// pop the route *underneath* — the calendar page, or the sheet that opened
  /// this one.
  ///
  /// The window it guards is one frame, not the exit animation: Flutter's
  /// `_ModalScopeState` (`packages/flutter/lib/src/widgets/routes.dart`) wraps
  /// the route's page in `IgnorePointer(ignoring: _shouldIgnoreFocusRequest)`,
  /// and that flag is true for as long as `route.animation.status ==
  /// AnimationStatus.reverse`, so the controls stop taking pointers the moment
  /// the pop starts. What can still re-enter is a second call in the *same*
  /// frame — two handlers fired off one gesture, or a callback invoked
  /// directly rather than through a hit test.
  bool _popped = false;

  /// Single exit funnel: a pending toggle is persisted **before** the pop so
  /// the caller routes `edit` into the editor with the description the user
  /// is looking at, not the one it opened with.
  void _close(EventDetailAction? action) {
    if (_popped) return;
    _popped = true;
    _flushWrite();
    Navigator.of(context).pop(action);
  }

  /// Closes first, then hands [title] to the host — see
  /// [EventDetailSheet.onOpenWikiLink] for why that order is the contract.
  /// Popping with null lands on the host's existing "no action" branch, so
  /// the loop that reopens this sheet stops instead of coming back.
  ///
  /// Reads [_popped] itself rather than leaning on [_close]: [_close] returns
  /// silently on an already-popped sheet, so calling the host afterwards would
  /// navigate off the back of an exit this call did not perform — and the host
  /// pushes an editor over whatever the *earlier* exit routed to.
  void _openWikiLink(String title) {
    final handler = widget.onOpenWikiLink;
    if (handler == null || _popped) return;
    _close(null);
    handler(title);
  }

  List<DateTime> _computeUpcoming() {
    final event = widget.event;
    // A one-time event has nothing to project, and a pinned-dates event
    // reads its set from the Dates row instead.
    if (event.explicitDates != null) return const [];
    // "Next" is measured from the occurrence being viewed, never from the
    // past: opened on today or a later day, the scan starts the day after it,
    // so the row never repeats the Date row above; opened on a past day it
    // starts today — the next one that can still be attended.
    final start = widget.day.isBefore(_today)
        ? _today
        : widget.day.add(const Duration(days: 1));
    final days = <DateTime>[];
    for (
      var i = 0;
      i < EventDetailSheet._scanDays &&
          days.length < EventDetailSheet._maxOccurrences;
      i++
    ) {
      final day = start.add(Duration(days: i));
      if (event.occursOn(day)) days.add(day);
    }
    return days;
  }

  /// "Sat, May 10 · 30 years": a day with the count label appended when the
  /// event counts its occurrences, so a birthday reads as the coming age and
  /// a program as its coming week.
  String _dayLabel(DateTime day, DateFormat format, AppLocalizations l10n) {
    final date = format.format(day);
    final count = RecurrenceFormatter.countLabel(widget.event, day, l10n);
    return count == null ? date : '$date · $count';
  }

  String _timeValue(BuildContext context, AppLocalizations l10n) {
    final time = widget.event.time;
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
    final event = widget.event;
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
    if (_upcoming.isEmpty) return l10n.eventDetailsNoOccurrences;
    return _dayLabel(_upcoming.first, format, l10n);
  }

  String? _thenCaption(AppLocalizations l10n, DateFormat format) {
    if (_upcoming.length < 2) return null;
    return l10n.eventDetailsThen(
      _upcoming.skip(1).map(format.format).join(' · '),
    );
  }

  /// "Reminder · Next Mon, Sep 21 06:50": the kind, plus what the registry
  /// says is armed when it says anything at all.
  String _alertValue(
    BuildContext context,
    EventAlert alert,
    AppLocalizations l10n,
    String localeName,
  ) {
    final kind = alert.isAlarm
        ? l10n.eventAlertModeRing
        : l10n.eventAlertModeNotify;
    final next = _nextFires[alert.id];
    if (next == null) return kind;
    // The clock half goes through `MaterialLocalizations`, not a bare `intl`
    // skeleton: this is widget code, so it can honour the device's 12h/24h
    // preference — the rule `EventTimeFormatter.formatRangeOfContext` follows.
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(next),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final when = '${DateFormat.MMMEd(localeName).format(next)} $time';
    return '$kind · ${l10n.eventAlertNext(when)}';
  }

  List<Widget> _buildWhenRows(
    BuildContext context,
    AppLocalizations l10n,
    String localeName,
  ) {
    final event = widget.event;
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
        value: _dayLabel(widget.day, dayFormat, l10n),
        onTap: null,
        showChevron: false,
      ),
      // A pinned set never gets per-date rows here: the editor's exist for
      // their ✕, and a reader has nothing to do per date. One bundled row
      // reads the set back and opens the list that holds all of it.
      if (_explicitDates case final dates?)
        FormPickerRow(
          glyph: Icons.event_note_outlined,
          identifier: SemanticsIds.eventDetailDates,
          label: l10n.eventDatesLabel,
          value: CalendarDatePickerSheet.datesValue(l10n, dates, _today),
          onTap: () => _close(EventDetailAction.showDates),
        ),
      if (event.explicitDates != null)
        FormActionRow(
          glyph: Icons.add_rounded,
          identifier: SemanticsIds.eventDetailAddDate,
          label: l10n.eventAddDate,
          onTap: () => _close(EventDetailAction.addDate),
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
        if (widget.day != event.startDate)
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

  List<Widget> _buildOccurrenceRows(AppLocalizations l10n) {
    final event = widget.event;
    final stats = _stats;
    return [
      if (_presenceVisible)
        FormChipRow(
          glyph: Icons.how_to_reg_outlined,
          label: l10n.eventPresence,
          chips: [
            FormChip(
              label: l10n.eventPresencePresent,
              selected: !_missed,
              identifier: SemanticsIds.eventDetailPresent,
              onTap: () => _setMissed(false),
            ),
            FormChip(
              label: l10n.eventPresenceMissed,
              selected: _missed,
              identifier: SemanticsIds.eventDetailMissed,
              onTap: () => _setMissed(true),
            ),
          ],
          caption: stats == null
              ? null
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FormCaption(
                      text: l10n.eventAdherenceSummary(
                        stats.attended,
                        stats.total,
                        PresenceAdherence.windowDays,
                      ),
                    ),
                    FormCaption(
                      text: l10n.eventAdherenceStreak(
                        stats.currentStreak,
                        stats.longestStreak,
                      ),
                    ),
                  ],
                ),
        ),
      // Cancelling closes the sheet with an action rather than writing here:
      // the occurrence stops existing, so the day panel behind this sheet —
      // and the sheet itself — would be describing something that is gone.
      if (EventSkips.appliesTo(event) &&
          !EventSkips.isSkipped(event.id, widget.day))
        FormActionRow(
          glyph: Icons.event_busy_outlined,
          identifier: SemanticsIds.eventDetailSkip,
          label: l10n.eventSkipOccurrence,
          onTap: () => _close(EventDetailAction.skipOccurrence),
        ),
    ];
  }

  List<Widget> _buildAlertRows(
    BuildContext context,
    AppLocalizations l10n,
    String localeName,
  ) {
    if (_alerts.isEmpty) return const [];
    final event = widget.event;
    return [
      // Tapping opens the editor, which is where an alert is changed — this
      // sheet writes nothing.
      for (final alert in _alerts)
        FormPickerRow(
          glyph: alert.isAlarm
              ? Icons.alarm_outlined
              : Icons.notifications_outlined,
          label: alert.describe(l10n, event),
          value: _alertValue(context, alert, l10n, localeName),
          onTap: () => _close(EventDetailAction.edit),
        ),
      if (event.removeAfterAlert)
        FormPickerRow(
          glyph: Icons.auto_delete_outlined,
          label: l10n.eventAlertRemoveAfter,
          onTap: null,
          showChevron: false,
        ),
    ];
  }

  List<Widget> _buildDetailRows(
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    final event = widget.event;
    return [
      if (event.priority != kDefaultEventPriority)
        FormPickerRow(
          glyph: Icons.flag_outlined,
          label: l10n.eventPriority,
          value: EventPriorities.labelOf(event.priority, l10n),
          onTap: null,
          showChevron: false,
        ),
      if (event.noteId != null) _buildNoteRow(l10n, colorScheme),
    ];
  }

  /// The editor's three linked-note states (D19): an empty value while the
  /// title loads, the title, or "Not found" in `error` with the full sentence
  /// as the semantics label. The row still pops [EventDetailAction.openNote]
  /// when the note is gone — the host answers with its snackbar, the same
  /// path the old button took.
  Widget _buildNoteRow(AppLocalizations l10n, ColorScheme colorScheme) {
    if (_noteMissing) {
      return FormPickerRow(
        glyph: Icons.warning_amber_rounded,
        glyphColor: colorScheme.error,
        identifier: SemanticsIds.eventDetailNote,
        label: l10n.eventLinkedNote,
        value: l10n.eventLinkedNoteNotFound,
        valueColor: colorScheme.error,
        semanticsLabel: l10n.eventLinkedNoteMissing,
        onTap: () => _close(EventDetailAction.openNote),
      );
    }
    final title = _noteTitle;
    return FormPickerRow(
      glyph: Icons.sticky_note_2_outlined,
      identifier: SemanticsIds.eventDetailNote,
      label: l10n.eventLinkedNote,
      value: title == null ? '' : (title.isEmpty ? l10n.untitledNote : title),
      onTap: () => _close(EventDetailAction.openNote),
    );
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final localeName = l10n.localeName;
    final category = CalendarCategories.resolve(event.categoryId);
    // The larger of the keyboard inset and the system's bottom inset pads the
    // scroll view, never the whole body — the clearance rule every calendar
    // sheet follows (`sheet_bottom_clearance_test.dart`).
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );
    final occurrenceRows = _buildOccurrenceRows(l10n);
    final alertRows = _buildAlertRows(context, l10n, localeName);
    final detailRows = _buildDetailRows(l10n, colorScheme);
    // The read rule: a group exists only while it has a fact to carry.
    final sections = <(String, List<Widget>)>[
      (l10n.eventSectionWhen, _buildWhenRows(context, l10n, localeName)),
      if (occurrenceRows.isNotEmpty)
        (l10n.recurrenceScopeLabel, occurrenceRows),
      if (alertRows.isNotEmpty) (l10n.eventAlerts, alertRows),
      if (detailRows.isNotEmpty) (l10n.eventSectionDetails, detailRows),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FormSheetHandle(),
        FormSheetHeader(
          leadingIcon: Icons.close_rounded,
          leadingTooltip: l10n.close,
          onLeading: () => _close(null),
          leadingIdentifier: SemanticsIds.eventDetailClose,
          title: l10n.eventDetailsTitle,
          scrolled: _headerScrolled,
          trailingInset: FormMetrics.headerActionInset,
          trailing: FormHeaderTextButton(
            label: l10n.edit,
            identifier: SemanticsIds.eventDetailEdit,
            onPressed: () => _close(EventDetailAction.edit),
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            controller: _bodyScroll,
            padding: EdgeInsets.fromLTRB(
              RowMetrics.groupInset,
              FormMetrics.bodyTop,
              RowMetrics.groupInset,
              FormMetrics.bodyBottom + clearance,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                FormRowGroup(
                  children: [
                    _TitleRow(
                      icon: CalendarCategories.iconFor(event),
                      color: EventSummaryProvider.colorFor(event, category),
                      title: event.title,
                      caption: CalendarCategories.labelOf(category, l10n),
                    ),
                    _DescriptionCell(
                      text: _description,
                      placeholder: l10n.eventDescriptionAdd,
                      editTooltip: l10n.eventDescriptionEdit,
                      identifier: SemanticsIds.eventDetailDescription,
                      colorPalette: widget.colorPalette,
                      onCheckboxTap: _tasksInteractive ? _toggleTask : null,
                      onTapWikiLink: widget.onOpenWikiLink == null
                          ? null
                          : _openWikiLink,
                      onEdit: () => _close(EventDetailAction.editDescription),
                      // With editing gone from this sheet, inert boxes are the
                      // only unresponsive thing left on it — so they get a
                      // reason rather than looking broken. Doubles as
                      // discovery for the per-day switch.
                      inertCaption: !_tasksInteractive && _hasTaskBox
                          ? l10n.eventDescriptionTickAllOccurrences
                          : null,
                    ),
                  ],
                ),
                for (var i = 0; i < sections.length; i++) ...[
                  FormSectionLabel(text: sections[i].$1),
                  FormRowGroup(
                    trailingGap: i < sections.length - 1,
                    children: sections[i].$2,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The day-panel row's twin at the top of the sheet: the event's avatar, its
/// title at the editor's size so Edit and Back never resize it, and the
/// category as the caption a reader wants under a name — the editor needs
/// Category as a picker row, a reader does not.
class _TitleRow extends FormDividedRow {
  final IconData icon;
  final Color color;
  final String title;
  final String caption;

  const _TitleRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.caption,
  });

  @override
  double get dividerIndent => FormMetrics.dividerIndentTitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: FormMetrics.twoLineRowMinHeight,
        ),
        child: Padding(
          padding: RowMetrics.twoLinePadding,
          child: Row(
            children: [
              EventAvatar(icon: icon, color: color),
              const SizedBox(width: FormMetrics.gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: FormMetrics.titleFontSize,
                        height: FormMetrics.titleLineHeight,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: RowMetrics.lineGap),
                    Text(
                      caption,
                      style: TextStyle(
                        fontSize: FormMetrics.captionSize,
                        height: 18 / FormMetrics.captionSize,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The editor's description cell read back: the same padding, so one line is
/// a 48 dp row and the text sits where the editor's caret line sits, the
/// pencil where the editor's expand button sits. Rendered in full, with no
/// scrollable of its own — the sheet's body owns every vertical drag.
///
/// Empty, the whole cell is the way into the quick edit; the pencil stays in
/// both states so the target the hand learned does not move.
class _DescriptionCell extends FormDividedRow {
  final String text;
  final String placeholder;
  final String editTooltip;
  final String identifier;
  final MarkdownColorPalette colorPalette;
  final CheckboxTapCallback? onCheckboxTap;
  final WikiLinkTapCallback? onTapWikiLink;
  final VoidCallback onEdit;
  final String? inertCaption;

  const _DescriptionCell({
    required this.text,
    required this.placeholder,
    required this.editTooltip,
    required this.identifier,
    required this.colorPalette,
    required this.onCheckboxTap,
    required this.onTapWikiLink,
    required this.onEdit,
    required this.inertCaption,
  });

  @override
  double get dividerIndent => FormMetrics.dividerIndentPlain;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final empty = text.isEmpty;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: FormMetrics.rowMinHeight),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RowMetrics.groupInset,
          FormMetrics.descriptionCellPadding,
          FormMetrics.trailingButtonSize,
          FormMetrics.descriptionCellPadding,
        ),
        child: empty
            ? Text(
                placeholder,
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
                  child: InkWell(onTap: onEdit, child: content),
                ),
              )
            else
              content,
            Positioned(
              top: 0,
              right: 0,
              child: AutomationId(
                identifier: identifier,
                child: FormTrailingButton(
                  icon: Icons.edit_note_rounded,
                  tooltip: editTooltip,
                  onPressed: onEdit,
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
