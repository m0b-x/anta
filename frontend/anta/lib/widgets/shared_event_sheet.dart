import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/calendar_categories.dart';
import '../constants/event_alerts.dart';
import '../constants/occurrence_descriptions.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/event_alert.dart';
import '../models/note_metadata.dart';
import '../models/partner_look.dart';
import '../models/share_settings.dart';
import '../services/shared_refresh/shared_refresh_scheduler.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/share_copy.dart';
import 'alert_editor_sheet.dart';
import 'event_alert_rows.dart';
import 'event_read_rows.dart';
import 'form_rows.dart';

/// How the read sheet of a partner's event ended, when it ended on its own.
sealed class SharedEventExit {
  const SharedEventExit();
}

/// "Copy to my calendar" made [copy], an event of my own, for the caller to
/// open in the editor.
final class SharedEventCopied extends SharedEventExit {
  final CalendarEvent copy;

  const SharedEventCopied(this.copy);
}

/// The event left while the sheet was open — un-shared, deleted, the pair
/// ended — and the sheet closed rather than go on describing it.
final class SharedEventGone extends SharedEventExit {
  const SharedEventGone();
}

/// The Linked note row was tapped: [note], the partner's, flagged for the
/// caller to open read-only in the editor (§6.13).
final class SharedEventOpenNote extends SharedEventExit {
  final NoteMetadata note;

  const SharedEventOpenNote(this.note);
}

/// A partner's event, read (share surfaces §6.9, the spec's §8): the sibling
/// of `EventDetailSheet`, with the same chrome, groups and read rows, every
/// action that would write the partner's event left out, and my own alerts
/// on it in the ALERTS group's place.
///
/// What it writes is mine alone: my alerts on this event, at once, through
/// [onAlertsChanged] — the partner's alerts never reach this phone, and the
/// event, its skipped days and its per-day texts are never touched. Ticking
/// a task box is inert for the same reason.
///
/// While open it follows the event through [changes]: a change by the
/// partner redraws it in place, and when the event leaves it closes with
/// [SharedEventGone] for the caller to say so.
class SharedEventSheet extends StatefulWidget {
  final CalendarEvent event;

  /// The occurrence being read (date-only UTC): which description renders.
  final DateTime day;

  /// The surface's look, which the title row's avatar follows, and the
  /// partner's name the header and the caption say.
  final PartnerLook partner;

  final MarkdownColorPalette colorPalette;

  /// The event as the app holds it after each change, null once it is gone.
  /// Null follows nothing — the sheet shows the event it was opened with.
  final Stream<CalendarEvent?>? changes;

  /// What may ring for a partner's event on this phone; null reads the
  /// published `EventAlerts.shareAlerts`.
  final ShareAlerts? shareAlerts;

  /// The alert defaults a new alert is drafted from, as the editor drafts.
  final AlertSettings? alertSettings;

  /// Receives my whole set of own alerts on this event after each add, edit
  /// or removal, with the ids the sheet was showing before it — the only
  /// ones the write may remove — and whether an alert was added, which is
  /// when the permission check runs.
  final void Function(
    List<EventAlert> alerts, {
    required Set<String> knownIds,
    required bool added,
  })?
  onAlertsChanged;

  /// Makes the copy; null when it could not be made, and the sheet stays.
  final Future<CalendarEvent?> Function()? onCopy;

  /// The detail sheet's wiki-link contract: called with the link's text
  /// after this sheet has closed.
  final ValueChanged<String>? onOpenWikiLink;

  /// The note the event links, when it is on this phone — a note in a
  /// folder the partner shares — or null. The Linked note row shows only
  /// for an answer: a note the partner did not share is absent, never
  /// "Not found" (§6.9 item 2, C12). Null asks nothing.
  final Future<NoteMetadata?> Function(String noteId)? resolveNote;

  const SharedEventSheet({
    super.key,
    required this.event,
    required this.day,
    required this.partner,
    this.colorPalette = MarkdownColorPalette.presets,
    this.changes,
    this.shareAlerts,
    this.alertSettings,
    this.onAlertsChanged,
    this.onCopy,
    this.onOpenWikiLink,
    this.resolveNote,
  });

  /// The detail sheet's sub-sheet shape: content-tall, clamped at the
  /// editor's height, the route's own drag, no guard — nothing here can be
  /// lost, since every alert is written as it is made.
  static Future<SharedEventExit?> show(
    BuildContext context, {
    required CalendarEvent event,
    required DateTime day,
    required PartnerLook partner,
    MarkdownColorPalette colorPalette = MarkdownColorPalette.presets,
    Stream<CalendarEvent?>? changes,
    ShareAlerts? shareAlerts,
    AlertSettings? alertSettings,
    void Function(
      List<EventAlert> alerts, {
      required Set<String> knownIds,
      required bool added,
    })?
    onAlertsChanged,
    Future<CalendarEvent?> Function()? onCopy,
    ValueChanged<String>? onOpenWikiLink,
    Future<NoteMetadata?> Function(String noteId)? resolveNote,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<SharedEventExit>(
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
        // The sheet resizes while open — an alert added through the alert
        // sheet, a change by the partner — so its semantics geometry is
        // re-read once the route above has left.
        child: FormSheetSemanticsRefresh(
          child: SharedEventSheet(
            event: event,
            day: day,
            partner: partner,
            colorPalette: colorPalette,
            changes: changes,
            shareAlerts: shareAlerts,
            alertSettings: alertSettings,
            onAlertsChanged: onAlertsChanged,
            onCopy: onCopy,
            onOpenWikiLink: onOpenWikiLink,
            resolveNote: resolveNote,
          ),
        ),
      ),
    );
  }

  @override
  State<SharedEventSheet> createState() => _SharedEventSheetState();
}

class _SharedEventSheetState extends State<SharedEventSheet> {
  late CalendarEvent _event = widget.event;

  /// Re-made with each change of the event, never per frame.
  late EventReadFacts _facts = EventReadFacts(_event, widget.day);

  late String _description = _descriptionOf(_event);

  /// My own alerts on this event, as this sheet last wrote them.
  late List<EventAlert> _alerts = EventAlerts.alertsFor(widget.event.id);

  StreamSubscription<CalendarEvent?>? _changes;

  final ScrollController _bodyScroll = ScrollController();
  final ValueNotifier<bool> _headerScrolled = ValueNotifier<bool>(false);

  /// Whether this sheet has asked to pop: the leave, a copy and the ✕ can
  /// land in one frame, and a second pop would take the route underneath.
  bool _popped = false;

  bool _copying = false;

  /// The event left while a copy was being made; see [_copy].
  bool _leftDuringCopy = false;

  ShareAlerts get _shareAlerts => widget.shareAlerts ?? EventAlerts.shareAlerts;

  String _descriptionOf(CalendarEvent event) =>
      OccurrenceDescriptions.descriptionFor(event, widget.day)?.trim() ?? '';

  /// The linked note as [SharedEventSheet.resolveNote] last answered.
  NoteMetadata? _note;

  /// Counts the lookups, so a late answer for a link the event no longer
  /// holds is dropped.
  int _noteLookups = 0;

  @override
  void initState() {
    super.initState();
    _bodyScroll.addListener(_onBodyScroll);
    _changes = widget.changes?.listen(_onChange);
    unawaited(_resolveNote(_event.noteId));
  }

  Future<void> _resolveNote(String? noteId) async {
    final lookup = ++_noteLookups;
    final resolve = widget.resolveNote;
    NoteMetadata? note;
    if (noteId != null && resolve != null) {
      try {
        note = await resolve(noteId);
      } catch (e) {
        // A lookup that throws leaves the row out, as a note not shared does.
        debugPrint('[SharedEventSheet] linked note not read: $e');
      }
    }
    if (!mounted || lookup != _noteLookups || note == _note) return;
    setState(() => _note = note);
  }

  /// Asked again at the tap: the note may have left the phone since the
  /// row was drawn, and the editor must not open on nothing. Gone, the row
  /// goes and nothing opens.
  Future<void> _openNote(NoteMetadata shown) async {
    final resolve = widget.resolveNote;
    if (resolve == null || _popped) return;
    NoteMetadata? current;
    try {
      current = await resolve(shown.id);
    } catch (e) {
      debugPrint('[SharedEventSheet] linked note not read: $e');
    }
    if (!mounted || _popped) return;
    if (current == null) {
      _noteLookups++;
      setState(() => _note = null);
      return;
    }
    _close(SharedEventOpenNote(current));
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    _bodyScroll.removeListener(_onBodyScroll);
    _bodyScroll.dispose();
    _headerScrolled.dispose();
    super.dispose();
  }

  void _onBodyScroll() {
    final scrolled = _bodyScroll.hasClients && _bodyScroll.offset > 0;
    if (_headerScrolled.value != scrolled) _headerScrolled.value = scrolled;
  }

  /// A change redraws in place; a leave — gone, or no longer the partner's —
  /// closes the sheet, unless a copy is being made: the copy then decides
  /// how the sheet ends ([_copy]).
  void _onChange(CalendarEvent? event) {
    if (!mounted || _popped) return;
    if (event == null || !event.fromPartner) {
      if (_copying) {
        _leftDuringCopy = true;
        return;
      }
      _close(const SharedEventGone());
      return;
    }
    if (event == _event) return;
    final relinked = event.noteId != _event.noteId;
    setState(() {
      _event = event;
      _facts = EventReadFacts(event, widget.day);
      _description = _descriptionOf(event);
    });
    if (relinked) unawaited(_resolveNote(event.noteId));
  }

  /// Pops this sheet's own route with [exit]. A leave can land while an
  /// alert editor or a permission dialog sits above the sheet; those are
  /// closed first — an alert on an event that is gone has nothing to save —
  /// so the result reaches the route that expects it, never theirs.
  void _close(SharedEventExit? exit) {
    if (_popped) return;
    final route = ModalRoute.of(context);
    // A sheet already on its way out (a drag, the barrier) has nothing left
    // to pop.
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    if (!route.isCurrent) navigator.popUntil((above) => above == route);
    _popped = true;
    navigator.pop(exit);
  }

  void _openWikiLink(String title) {
    final handler = widget.onOpenWikiLink;
    if (handler == null || _popped) return;
    _close(null);
    handler(title);
  }

  void _write(List<EventAlert> next, {required bool added}) {
    final known = {for (final alert in _alerts) alert.id};
    setState(() => _alerts = List.unmodifiable(next));
    widget.onAlertsChanged?.call(_alerts, knownIds: known, added: added);
  }

  Future<void> _addAlert() async {
    if (_alerts.length >= kMaxAlertsPerEvent) return;
    final defaults = widget.alertSettings;
    final draft = AlertEditorSheet.draft(
      eventId: _event.id,
      allDay: _event.allDay,
      timedDefault: defaults?.timedDefault,
      allDayDefault: defaults?.allDayDefault,
    );
    final result = await AlertEditorSheet.show(
      context,
      alert: draft,
      event: _event,
      canRemove: false,
    );
    if (!mounted || _popped) return;
    if (result case AlertEditorSaved(:final alert)) {
      _write([..._alerts, alert], added: true);
    }
  }

  Future<void> _editAlert(EventAlert alert) async {
    final result = await AlertEditorSheet.show(
      context,
      alert: alert,
      event: _event,
    );
    if (!mounted || _popped || result == null) return;
    switch (result) {
      case AlertEditorRemoved():
        _removeAlert(alert);
      case AlertEditorSaved(alert: final saved):
        _write([
          for (final existing in _alerts)
            if (existing.id == saved.id) saved else existing,
        ], added: false);
    }
  }

  void _removeAlert(EventAlert alert) {
    _write([
      for (final existing in _alerts)
        if (existing.id != alert.id) existing,
    ], added: false);
  }

  /// A copy that was made wins over a leave heard while it was made: the
  /// copy exists either way, and the sheet closes with it rather than say
  /// the event left.
  Future<void> _copy() async {
    final onCopy = widget.onCopy;
    if (onCopy == null || _copying || _popped) return;
    _copying = true;
    final copy = await onCopy();
    _copying = false;
    if (!mounted) return;
    if (copy != null) {
      _close(SharedEventCopied(copy));
    } else if (_leftDuringCopy) {
      _close(const SharedEventGone());
    }
  }

  List<Widget> _yoursRows(AppLocalizations l10n, {required bool off}) {
    final inherited = _shareAlerts == ShareAlerts.category
        ? [
            // A partner's event follows the setting alone: its own Category
            // alerts switch is the partner's and is not read.
            for (final alert in EventAlerts.inheritedFor(
              _event,
              own: _alerts,
              ignoreOptOut: true,
            ))
              if (alert.enabled) alert,
          ]
        : const <EventAlert>[];
    return eventAlertRows(
      context,
      l10n: l10n,
      previewEvent: _event,
      alerts: _alerts,
      inherited: inherited,
      categoryLabel: CalendarCategories.labelOf(
        CalendarCategories.resolve(_event.categoryId),
        l10n,
      ),
      onEdit: _editAlert,
      onRemove: _removeAlert,
      onAdd: _addAlert,
      addIdentifier: SemanticsIds.sharedEventAddAlert,
      enabled: !off,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final name = ShareCopy.partnerName(l10n, widget.partner.name);
    final off = _shareAlerts == ShareAlerts.off;
    // The larger of the keyboard inset and the system's bottom inset pads the
    // scroll view — the clearance rule every calendar sheet follows.
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );
    final priority = _facts.priorityRow(l10n);
    final note = _note;
    return Semantics(
      container: true,
      identifier: SemanticsIds.sharedEventSheet,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FormSheetHandle(),
          // A name is the whole title here, so it takes its own lines at
          // large text rather than be cut (decision i).
          FormSheetHeader(
            leadingIcon: Icons.close_rounded,
            leadingTooltip: l10n.close,
            onLeading: () => _close(null),
            title: l10n.shareFromPartner(name),
            scrolled: _headerScrolled,
            trailing: const SizedBox.shrink(),
            stackTitleAtLargeText: true,
            titleIsHeading: true,
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
                      _facts.titleRow(l10n, partner: widget.partner),
                      // Read, never written: no pencil, inert task boxes,
                      // and no cell at all without a text.
                      if (_description.isNotEmpty)
                        EventDescriptionCell(
                          text: _description,
                          colorPalette: widget.colorPalette,
                          onCheckboxTap: null,
                          onTapWikiLink: widget.onOpenWikiLink == null
                              ? null
                              : _openWikiLink,
                        ),
                    ],
                  ),
                  FormSectionLabel(text: l10n.eventSectionWhen),
                  // The pinned set's row stays a read row: its list is the
                  // multi-date picker, which writes (decision z).
                  FormRowGroup(children: _facts.whenRows(context, l10n)),
                  FormSectionLabel(text: l10n.sharedEventYours),
                  FormRowGroup(
                    trailingGap: !off,
                    children: _yoursRows(l10n, off: off),
                  ),
                  if (off) ...[
                    FormCaption(
                      text: l10n.shareAlertsOffCaption,
                      padding: FormMetrics.groupCaptionPadding,
                    ),
                    // A section label has no top padding of its own and the
                    // caption no bottom one: the gap a group would leave.
                    const SizedBox(height: RowMetrics.groupGap),
                  ],
                  // The Linked note row only for a note in a folder the
                  // partner shares, opened read-only; any other link shows
                  // no row at all, never "Not found".
                  if (priority != null || note != null) ...[
                    FormSectionLabel(text: l10n.eventSectionDetails),
                    FormRowGroup(
                      children: [
                        ?priority,
                        if (note != null)
                          FormPickerRow(
                            glyph: Icons.sticky_note_2_outlined,
                            identifier: SemanticsIds.sharedEventNote,
                            label: l10n.eventLinkedNote,
                            value: note.title.isEmpty
                                ? l10n.untitledNote
                                : note.title,
                            onTap: () => _openNote(note),
                          ),
                      ],
                    ),
                  ],
                  FormRowGroup(
                    trailingGap: false,
                    children: [
                      FormActionRow(
                        glyph: Icons.content_copy_rounded,
                        label: l10n.sharedEventCopy,
                        identifier: SemanticsIds.sharedEventCopy,
                        onTap: _copy,
                      ),
                    ],
                  ),
                  FormCaption(
                    text: SharedRefreshAvailability.isSupported
                        ? l10n.sharedEventCaptionFresh(name)
                        : l10n.sharedEventCaption(name),
                    padding: FormMetrics.groupCaptionPadding,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
