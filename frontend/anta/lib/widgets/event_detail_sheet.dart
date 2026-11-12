import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../constants/app_colors.dart';
import '../constants/calendar_categories.dart';
import '../constants/event_alerts.dart';
import '../constants/event_presence.dart';
import '../constants/event_skips.dart';
import '../constants/occurrence_descriptions.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/category_profile.dart';
import '../models/event_alert.dart';
import '../models/recurrence_rule.dart';
import '../services/alert_scheduler.dart';
import '../services/event_time_formatter.dart';
import '../utils/custom_snackbar.dart';
import '../utils/markdown_callout_syntax.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/mark_verb_labels.dart';
import '../utils/markdown_list_syntax.dart';
import '../utils/presence_stats.dart';
import 'event_read_rows.dart';
import 'form_rows.dart';
import 'overlay_snackbar.dart';

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

  /// Receives `(day, cancelled)` when the user cancels or restores a one-off
  /// here (decision B). Null leaves a one-off without the action, the
  /// [onPresenceChanged] opt-in. Unlike a series' Skip this day it writes in
  /// place: a cancelled one-off is still the event, shown as Cancelled with
  /// the way back beside it, where a skipped day would leave the sheet
  /// describing an occurrence that no longer exists.
  ///
  /// A cancel clears the day's mark (`EventSkipService.markSkipped`), so a
  /// restore — the Restore row or the snackbar's Undo, after the sheet closed
  /// too — carries in [restore] the mark the cancel took, for the caller to
  /// write back; null when the day had none.
  final void Function(DateTime day, bool cancelled, {PresenceStatus? restore})?
  onCancelChanged;

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

  /// Where this occurrence's presence and the adherence stats are read from.
  /// Null reads `EventPresence.isMissed`, the calendar's cache; the guide's
  /// practice calendar keeps its marks in memory and hands its own reader.
  final bool Function(CalendarEvent event, DateTime dayUtc)? isMissed;

  /// Where the kind the mark's words come from is read. Null reads the
  /// owner's profiles (`effectiveFor`); the guide's sandbox hands
  /// `EffectiveProfile.unprofiled`, since its practice reads none of them
  /// (decision V).
  final EffectiveProfile Function(CalendarEvent event)? profileOf;

  const EventDetailSheet({
    super.key,
    required this.event,
    required this.day,
    this.colorPalette = MarkdownColorPalette.presets,
    this.pendingOccurrenceDescription,
    this.onEventChanged,
    this.onOccurrenceChanged,
    this.onPresenceChanged,
    this.onCancelChanged,
    this.onOpenWikiLink,
    this.resolveNoteTitle,
    this.isMissed,
    this.profileOf,
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
    void Function(DateTime day, bool cancelled, {PresenceStatus? restore})?
    onCancelChanged,
    ValueChanged<String>? onOpenWikiLink,
    Future<String?> Function(String noteId)? resolveNoteTitle,
    bool Function(CalendarEvent event, DateTime dayUtc)? isMissed,
    EffectiveProfile Function(CalendarEvent event)? profileOf,
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
          onCancelChanged: onCancelChanged,
          onOpenWikiLink: onOpenWikiLink,
          resolveNoteTitle: resolveNoteTitle,
          isMissed: isMissed,
          profileOf: profileOf,
        ),
      ),
    );
  }

  @override
  State<EventDetailSheet> createState() => _EventDetailSheetState();
}

class _EventDetailSheetState extends State<EventDetailSheet> {
  /// The read rows' facts — the next occurrences, the pinned set, today —
  /// resolved **once**, shared with the read sheet of a partner's event.
  late final EventReadFacts _facts = EventReadFacts(widget.event, widget.day);

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
  late bool _missed = (widget.isMissed ?? EventPresence.isMissed)(
    widget.event,
    widget.day,
  );

  /// Adherence over the trailing window. Held in state rather than derived in
  /// `build` for the same reason as [_upcoming]: the walk covers up to 366
  /// days. Recomputed by [_setMissed] so the numbers move with the chips
  /// instead of waiting for a reopen.
  late PresenceStats? _stats = _computeStats();

  /// The event's alerts — its own, then its category's while it inherits
  /// them (**v42**) — read once from the synchronous facade. Rebuilding this
  /// list in `build` would be another map probe per scroll frame for a set
  /// that cannot change while a read-only sheet is open. A switched-off alert
  /// is left out on either side (D5): it fires for no one, the badge is
  /// already gone from the day panel and the agenda, and a row carrying only
  /// its tier reads exactly like an armed one whose registry read has not
  /// landed yet. With the last of them the group goes too.
  late final List<EventAlert> _alerts = [
    for (final alert in EventAlerts.effectiveFor(widget.event))
      if (alert.enabled) alert,
  ];

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

  /// Whether the present/missed control is offered at all: the event opts in
  /// (any shape, decision B) and the caller wired persistence.
  bool get _presenceVisible =>
      widget.onPresenceChanged != null && EventPresence.appliesTo(widget.event);

  /// Whether this one-off can be cancelled and restored in place: the caller
  /// wired the write. A series keeps Skip this day, which closes the sheet.
  bool get _cancelOffered =>
      widget.onCancelChanged != null && widget.event.rule is OneTimeRecurrence;

  /// Whether this one-off is cancelled, seeded from the facade — a sheet the
  /// Report opens on a cancelled one-off opens Cancelled — and updated
  /// locally so the rows follow the tap before the write lands.
  late bool _cancelled =
      _cancelOffered && EventSkips.isSkipped(widget.event.id, widget.day);

  /// The day's explicit mark as this sheet last knew it, for a cancel to
  /// hand back on restore: seeded from the facade, then what [_setMissed]
  /// wrote, which the facade may not hold yet. Read only where a cancel is
  /// offered — the guide's sheet keeps its marks elsewhere and offers none.
  late PresenceStatus? _mark = _cancelOffered
      ? EventPresence.marksFor(widget.event.id)[widget.day]
      : null;

  /// The mark the last cancel cleared, handed back by its restore.
  PresenceStatus? _cancelledMark;

  /// The profile the kept chip's word comes from, read once: a category's
  /// kind cannot change while a read-only sheet is open.
  late final EffectiveProfile _profile = (widget.profileOf ?? effectiveFor)(
    widget.event,
  );

  PresenceStats? _computeStats() {
    return PresenceAdherence.compute(
      widget.event,
      today: DateTime.now(),
      // The facade may not have the write yet, so this day's answer comes
      // from the local copy the chips already reflect.
      overrideDay: widget.day,
      overrideMissed: _missed,
      isMissed: widget.isMissed,
    );
  }

  /// A discrete two-state toggle has nothing to coalesce, so unlike a burst of
  /// checkbox taps this writes through immediately.
  void _setMissed(bool missed) {
    if (missed == _missed) return;
    HapticFeedback.lightImpact();
    setState(() {
      _missed = missed;
      _mark = missed ? PresenceStatus.missed : PresenceStatus.present;
      _stats = _computeStats();
    });
    widget.onPresenceChanged!(widget.day, missed);
  }

  /// Cancels or restores the one-off without closing the sheet. A cancel
  /// clears the day's mark (`EventSkipService.markSkipped`), so it keeps the
  /// mark it is about to lose and the restore hands it back: a Done one-off
  /// cancelled by mistake is Done again, never missed by the assumed answer.
  void _setCancelled(bool cancelled) {
    if (cancelled == _cancelled) return;
    HapticFeedback.lightImpact();
    final onCancelChanged = widget.onCancelChanged!;
    final day = widget.day;
    final restore = cancelled ? _mark : _cancelledMark;
    setState(() {
      _cancelled = cancelled;
      if (cancelled) {
        _cancelledMark = restore;
        _mark = null;
      } else {
        _mark = restore;
        _cancelledMark = null;
        _missed = restore == null
            ? (widget.isMissed ?? EventPresence.isMissed)(widget.event, day)
            : restore == PresenceStatus.missed;
        _stats = _computeStats();
      }
    });
    if (!cancelled) {
      onCancelChanged(day, false, restore: restore);
      OverlaySnackbar.hide();
      return;
    }
    onCancelChanged(day, true);
    final l10n = AppLocalizations.of(context)!;
    CustomSnackbar.showWithAction(
      context,
      message: l10n.eventCancelled,
      actionLabel: l10n.undo,
      overSheet: true,
      // The bar outlives the sheet: once it is gone, the undo writes alone,
      // with the mark this cancel took.
      onAction: () => mounted
          ? _setCancelled(false)
          : onCancelChanged(day, false, restore: restore),
    );
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
        (line) =>
            (MarkdownListSyntax.parse(line) ??
                    MarkdownCalloutSyntax.quotedListItem(line)?.item)
                ?.kind ==
            MarkdownListKind.task,
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

  /// The presence pair. As a [template] it carries no ids and no taps: the
  /// invisible box the Cancelled row is sized by.
  FormChipRow _presenceRow(AppLocalizations l10n, {bool template = false}) {
    final stats = _stats;
    return FormChipRow(
      glyph: Icons.how_to_reg_outlined,
      label: l10n.eventPresence,
      chips: [
        FormChip(
          label: markVerbLabel(l10n, _profile),
          selected: !_missed,
          identifier: template ? null : SemanticsIds.eventDetailPresent,
          onTap: template ? null : () => _setMissed(false),
        ),
        FormChip(
          label: l10n.eventPresenceMissed,
          selected: _missed,
          identifier: template ? null : SemanticsIds.eventDetailMissed,
          onTap: template ? null : () => _setMissed(true),
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
    );
  }

  List<Widget> _buildOccurrenceRows(AppLocalizations l10n) {
    final event = widget.event;
    // A cancelled one-off: Cancelled where the presence pair stood, at its
    // height (an invisible template under it), and Restore where Cancel did,
    // so the finger that cancelled rests on the inert row rather than on the
    // way back, and nothing below moves. Without the pair there is one slot,
    // so Restore takes Cancel's and carries the Cancelled word as its value:
    // one row for one row. Restore always stands on Cancel's template, the
    // longer label in every language, so the slot keeps its height.
    if (_cancelled) {
      void restore() => _setCancelled(false);
      if (!_presenceVisible) {
        return [
          _inCancelSlot(
            l10n,
            FormPickerRow(
              glyph: Icons.restore_rounded,
              glyphColor: Theme.of(context).colorScheme.primary,
              label: l10n.eventRestoreEvent,
              labelColor: Theme.of(context).colorScheme.primary,
              value: l10n.eventCancelledState,
              identifier: SemanticsIds.eventDetailRestore,
              onTap: restore,
              showChevron: false,
              singleLine: true,
            ),
          ),
        ];
      }
      final cancelled = FormPickerRow(
        glyph: Icons.event_busy_outlined,
        label: l10n.eventCancelledState,
        onTap: null,
        showChevron: false,
      );
      return [
        FormIndentedRow(
          dividerIndent: cancelled.dividerIndent,
          child: Stack(
            children: [
              Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: _presenceRow(l10n, template: true),
              ),
              Positioned.fill(child: cancelled),
            ],
          ),
        ),
        _inCancelSlot(
          l10n,
          FormActionRow(
            glyph: Icons.restore_rounded,
            identifier: SemanticsIds.eventDetailRestore,
            label: l10n.eventRestoreEvent,
            onTap: restore,
          ),
        ),
      ];
    }
    return [
      if (_presenceVisible) _presenceRow(l10n),
      if (_cancelOffered)
        _cancelRow(l10n)
      // Skipping a series' day closes the sheet with an action rather than
      // writing here: the occurrence stops existing, so the day panel behind
      // this sheet — and the sheet itself — would be describing something
      // that is gone. A one-off without the wiring offers neither.
      else if (event.rule is! OneTimeRecurrence &&
          EventSkips.appliesTo(event) &&
          !EventSkips.isSkipped(event.id, widget.day))
        FormActionRow(
          glyph: Icons.event_busy_outlined,
          identifier: SemanticsIds.eventDetailSkip,
          label: l10n.eventSkipOccurrence,
          onTap: () => _close(EventDetailAction.skipOccurrence),
        ),
    ];
  }

  FormActionRow _cancelRow(AppLocalizations l10n) => FormActionRow(
    glyph: Icons.event_busy_outlined,
    identifier: SemanticsIds.eventDetailCancel,
    label: l10n.eventCancelEvent,
    onTap: () => _setCancelled(true),
  );

  /// [row] at the Cancel row's height (an invisible template under it).
  Widget _inCancelSlot(AppLocalizations l10n, Widget row) {
    return FormIndentedRow(
      dividerIndent: FormMetrics.dividerIndentGlyph,
      child: Stack(
        children: [
          Visibility(
            visible: false,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: _cancelRow(l10n),
          ),
          Positioned.fill(child: row),
        ],
      ),
    );
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
          label: alert.describe(
            l10n,
            event,
            formatMinute: (minute) =>
                EventTimeFormatter.formatMinute(minute, context),
          ),
          value: _alertValue(context, alert, l10n, localeName),
          // An inherited alert says where it comes from; the editor it
          // opens shows it read-only, beside the switch that drops it.
          caption: switch (alert.categoryId) {
            final categoryId? => l10n.eventAlertFromCategory(
              CalendarCategories.labelOf(
                CalendarCategories.resolve(categoryId),
                l10n,
              ),
            ),
            null => null,
          },
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
    return [
      ?_facts.priorityRow(l10n),
      if (widget.event.noteId != null) _buildNoteRow(l10n, colorScheme),
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
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final localeName = l10n.localeName;
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
      (
        l10n.eventSectionWhen,
        _facts.whenRows(
          context,
          l10n,
          onShowDates: () => _close(EventDetailAction.showDates),
          onAddDate: () => _close(EventDetailAction.addDate),
        ),
      ),
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
                    // The editor needs Category as a picker row, a reader
                    // does not: it is the title row's caption here.
                    _facts.titleRow(l10n),
                    EventDescriptionCell(
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
