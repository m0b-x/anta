import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../bloc/calendar/calendar_bloc.dart';
import '../constants/app_constants.dart';
import '../constants/calendar_bounds.dart';
import '../constants/event_alerts.dart';
import '../constants/event_presence.dart';
import '../constants/event_skips.dart';
import '../constants/occurrence_descriptions.dart';
import '../l10n/app_localizations.dart';
import '../models/app_permission.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/event_alert.dart';
import '../models/recurrence_rule.dart';
import '../repositories/note_repository.dart';
import '../services/app_navigator.dart';
import '../services/note_storage_service.dart';
import '../services/permission_service.dart';
import '../services/settings_service.dart';
import '../utils/alert_countdown.dart';
import '../utils/custom_snackbar.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/sheet_guard.dart';
import '../utils/wiki_link_title.dart';
import '../widgets/calendar_date_picker_sheet.dart';
import '../widgets/event_description_sheet.dart';
import '../widgets/event_detail_sheet.dart';
import '../widgets/event_editor_sheet.dart';
import '../widgets/overlay_snackbar.dart';

/// An event's trip through its sheets — the detail sheet, and from it the
/// editor, the quick description edit, the dates picker, a skip, the linked
/// note or a wiki link — for every page that opens one: the calendar and the
/// overview (D14 · A), so a row tap on either lands on the same trip.
///
/// Owned by the page's state and holding no [BuildContext]: each entry takes
/// the caller's, so every sheet opens over the page that asked and every
/// write goes through `context.read<CalendarBloc>()`, the one path
/// persistence takes. What the trip reads off the page — its appearance, its
/// palette, how many Keeps it has heard of — comes through getters read when
/// needed, never copied at construction, because each changes under a trip
/// already under way.
class EventSheetsFlow {
  EventSheetsFlow({
    required SheetGuard guard,
    required CalendarAppearance Function() appearance,
    required MarkdownColorPalette Function() palette,
    required int Function() keepsHeard,
  }) : _guard = guard,
       _appearance = appearance,
       _palette = palette,
       _keepsHeard = keepsHeard;

  /// The page's one sheet slot, shared with the page's other sheets.
  final SheetGuard _guard;

  final CalendarAppearance Function() _appearance;

  /// Resolved markdown palette, so an event's description renders with the
  /// user's custom colours in the detail sheet.
  final MarkdownColorPalette Function() _palette;

  /// How many Keeps the page has heard of; see [_detailSheetLoop].
  final int Function() _keepsHeard;

  /// Shows an event read-only first, then routes whatever the user chose
  /// there. Tapping a day-panel row used to drop straight into the edit form;
  /// now that descriptions are real content, the first thing a tap does is
  /// show them.
  ///
  /// Ticking a description checkbox there rewrites the description in place,
  /// so [current] tracks the latest version and the routed actions carry it —
  /// otherwise "edit" would reopen the form on the pre-tick text. A
  /// per-occurrence tick never touches [current]: it writes one day's row,
  /// leaving the event (and its template) exactly as it was.
  ///
  /// Editing re-enters rather than ending the trip: saving the form or backing
  /// out of it returns here, and so does a quick description edit. The three
  /// exits are the ones where reopening would describe something that is no
  /// longer there or in the way — opening the linked note (a full page), a
  /// delete, and a skip (the occurrence stops existing) — plus dismissing the
  /// sheet itself.
  Future<void> openDetail(
    BuildContext context,
    CalendarEvent event,
    DateTime day,
  ) => _guard.run<void>(() => _detailSheetLoop(context, event, day));

  /// The loop itself, unguarded so the trip it runs — detail, editor, quick
  /// description edit — can reopen freely inside the one slot [_guard] took
  /// at the top.
  Future<void> _detailSheetLoop(
    BuildContext context,
    CalendarEvent event,
    DateTime day,
  ) async {
    final bloc = context.read<CalendarBloc>();
    var current = event;
    // The occurrence write is dispatched, not awaited, and the sheet pops in
    // the same turn — so the next sheet can mount before it lands. Carry the
    // text forward rather than letting it race the database.
    String? pendingOccurrence;
    // An alarm can ring over this trip, and a Keep taken on its page reaches
    // the bloc and nothing here: the open sheet goes on holding the event as
    // it opened on, "remove after it rings" still set, and whatever the trip
    // saves is the whole event. So a task ticked in that sheet, a description
    // edit, a date added or the editor's Save wrote the flag back — and the
    // event's next alarm removed the event the user had kept.
    var keepsSeen = _keepsHeard();

    // [held] as the trip may save it or hand it on. Once a Keep has been
    // heard of that the trip has not accounted for, the flag is taken from
    // the bloc's copy of the same event — the flag alone: after an edit of
    // its own the trip's copy is ahead of the bloc in everything else.
    CalendarEvent afterKeep(CalendarEvent held) {
      if (keepsSeen == _keepsHeard() || !held.removeAfterAlert) return held;
      final state = bloc.state;
      if (state is! CalendarPageLoaded) return held;
      for (final stored in state.allEvents) {
        if (stored.id != held.id) continue;
        return stored.removeAfterAlert
            ? held
            : held.copyWith(removeAfterAlert: false);
      }
      return held;
    }

    while (true) {
      // Every path back to the top of the loop already checks, but the check
      // has to be here for the analyzer to see it across the back edge.
      if (!context.mounted) return;
      final action = await EventDetailSheet.show(
        context,
        event: current,
        day: day,
        colorPalette: _palette(),
        pendingOccurrenceDescription: pendingOccurrence,
        onEventChanged: (updated) {
          // On every call, not once: the sheet that is open builds each of
          // its writes from the event it was opened on.
          current = afterKeep(updated);
          bloc.add(UpdateCalendarEvent(event: current));
        },
        onOccurrenceChanged: (occurrenceDay, description) {
          pendingOccurrence = description;
          bloc.add(
            SetOccurrenceDescription(
              eventId: current.id,
              day: occurrenceDay,
              description: description,
            ),
          );
        },
        onPresenceChanged: (occurrenceDay, missed) =>
            setOccurrencePresence(bloc, current.id, occurrenceDay, missed),
        onOpenWikiLink: (title) => _openWikiLink(context, title),
        resolveNoteTitle: _resolveNoteTitle,
      );
      if (action == null || !context.mounted) return;
      // What is handed on from here — to the quick edit, the dates picker,
      // the editor's switch — is the event as it is kept.
      current = afterKeep(current);
      switch (action) {
        case EventDetailAction.openNote:
          await openLinkedNote(context, current);
          return;
        case EventDetailAction.skipOccurrence:
          _skipOccurrence(context, bloc, current.id, day);
          return;
        case EventDetailAction.editDescription:
          final edited = await _quickEditDescription(
            context,
            bloc,
            current,
            day,
            pendingOccurrence,
          );
          current = edited.event;
          pendingOccurrence = edited.pending;
          if (!context.mounted) return;
        case EventDetailAction.addDate:
        case EventDetailAction.showDates:
          final updated = await _editExplicitDates(
            context,
            current,
            view: action == EventDetailAction.showDates
                ? CalendarDatePickerView.list
                : CalendarDatePickerView.month,
          );
          if (!context.mounted) return;
          if (updated != null) {
            current = updated;
            bloc.add(UpdateCalendarEvent(event: updated));
            if (!updated.occursOn(day)) return;
          }
        case EventDetailAction.edit:
          final result = await editorSheet(
            context,
            initialEvent: current,
            occurrenceDay: day,
            pendingOccurrenceDescription: pendingOccurrence,
            showBack: true,
          );
          if (!context.mounted) return;
          var reopen = false;
          switch (result) {
            case null:
            case EventEditorDeleted():
              break;
            case EventEditorBack():
              reopen = true;
            case EventEditorSaved():
              current = result.event;
              // The editor's switch is the user's later word. From here the
              // flag on the trip's copy is the one they saved — also while
              // that save is still on its way to the bloc, whose copy would
              // otherwise take a flag turned on again straight back off.
              keepsSeen = _keepsHeard();
              pendingOccurrence = _pendingAfterSave(
                result,
                current,
                day,
                pendingOccurrence,
              );
              reopen = _occurrenceSurvives(result, current, day);
          }
          if (!reopen) return;
      }
    }
  }

  /// What this day's text is after the editor saved, for the detail sheet the
  /// loop is about to reopen.
  ///
  /// Three cases the facade cannot answer in time: the event stopped
  /// separating its days (rows go dormant, the template governs again), the
  /// day's row was **deleted** by a reset (`occurrenceDescription` null against
  /// a non-null day), so the day now follows the template, or it was written.
  /// A null day means the editor left the table alone, and any text carried in
  /// from a checkbox tick still stands.
  static String? _pendingAfterSave(
    EventEditorSaved result,
    CalendarEvent saved,
    DateTime day,
    String? previous,
  ) {
    if (!OccurrenceDescriptions.appliesTo(saved)) return null;
    if (result.occurrenceDay != day) return previous;
    return result.occurrenceDescription ?? saved.description ?? '';
  }

  /// Whether [day] still has an occurrence to show after the save. The form
  /// can move the date, change the rule, pull in the end date, or cancel this
  /// very day in its skip picker — reopening the sheet on any of those would
  /// describe an occurrence that no longer exists.
  ///
  /// The skip set is read from the result rather than from `EventSkips`: it is
  /// dispatched asynchronously, so the facade may not carry it yet.
  static bool _occurrenceSurvives(
    EventEditorSaved result,
    CalendarEvent saved,
    DateTime day,
  ) {
    if (result.skippedDays?.contains(day) ?? false) return false;
    return saved.occursOn(day);
  }

  /// Edits one description from the detail sheet, without the form.
  ///
  /// Writes exactly where a checkbox tick writes — no scope picker, so the two
  /// can never disagree about which text they are editing. A per-occurrence
  /// event therefore edits *this day* here and its template only in the full
  /// editor, which is what the caption says out loud.
  Future<({CalendarEvent event, String? pending})> _quickEditDescription(
    BuildContext context,
    CalendarBloc bloc,
    CalendarEvent event,
    DateTime day,
    String? pending,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final unchanged = (event: event, pending: pending);
    final perOccurrence = OccurrenceDescriptions.appliesTo(event);
    // Seeded from the raw text, never the detail sheet's trimmed render: a
    // Done with no edits must be able to compare equal below.
    final seed = perOccurrence
        ? (pending ?? OccurrenceDescriptions.descriptionFor(event, day) ?? '')
        : (event.description ?? '');
    final settings = await SettingsService.getInstance();
    final limit = await settings.getEventDescriptionLimit();
    if (!context.mounted) return unchanged;
    final edited = await EventDescriptionSheet.show(
      context,
      initialText: seed,
      heading: event.title,
      limit: limit,
      grandfatheredLength: seed.length,
      scopeCaption: perOccurrence
          ? l10n.eventDescriptionScopeThisDayHint
          : (event.rule is OneTimeRecurrence
                ? null
                : l10n.eventDescriptionAppliesAllOccurrences),
      colorPalette: _palette(),
    );
    // An unchanged Done must not write. On a day with no row of its own it
    // would materialise one identical to the template, forking that day from
    // the template forever; on the event it would bump the version and the
    // HLC for nothing.
    if (edited == null || edited == seed) return unchanged;
    if (perOccurrence) {
      // Empty is a deliberately blanked day, not a reset: the day stays
      // exactly as the user left it. Returning to the template is what the
      // editor's "reset this day" is for.
      bloc.add(
        SetOccurrenceDescription(
          eventId: event.id,
          day: day,
          description: edited,
        ),
      );
      return (event: event, pending: edited);
    }
    final updated = event.copyWith(
      description: edited,
      clearDescription: edited.isEmpty,
    );
    bloc.add(UpdateCalendarEvent(event: updated));
    return (event: updated, pending: pending);
  }

  /// Cancels one occurrence, with an undo. Routed through the flow rather
  /// than written from the sheet so every skip — this one and the editor's
  /// bulk picker — lands on the same path.
  void _skipOccurrence(
    BuildContext context,
    CalendarBloc bloc,
    String eventId,
    DateTime day,
  ) {
    final l10n = AppLocalizations.of(context)!;
    bloc.add(SetOccurrenceSkipped(eventId: eventId, day: day));
    CustomSnackbar.showWithAction(
      context,
      message: l10n.eventOccurrenceSkipped,
      actionLabel: l10n.undo,
      onAction: () =>
          bloc.add(ClearOccurrenceSkipped(eventId: eventId, day: day)),
    );
  }

  /// Opens the form and dispatches whatever it reports, then hands the result
  /// back so a caller that owns a sheet behind this one can decide what to do
  /// next. Every caller still gets the dispatch for free; only the detail
  /// sheet's loop reads the return value.
  Future<EventEditorResult?> openEditor(
    BuildContext context, {
    CalendarEvent? initialEvent,
    DateTime? day,
    DateTime? occurrenceDay,
    String? pendingOccurrenceDescription,
    bool showBack = false,
  }) => _guard.run<EventEditorResult?>(
    () => editorSheet(
      context,
      initialEvent: initialEvent,
      day: day,
      occurrenceDay: occurrenceDay,
      pendingOccurrenceDescription: pendingOccurrenceDescription,
      showBack: showBack,
    ),
  );

  /// The detail sheet's Add date and All dates: the pinned set in the multi
  /// picker, saved back through [CalendarEvent.withExplicitDates] so this
  /// path and the editor's agree on the anchor and the one-time flags. Null
  /// when nothing changed.
  Future<CalendarEvent?> _editExplicitDates(
    BuildContext context,
    CalendarEvent event, {
    required CalendarDatePickerView view,
  }) async {
    final dates = event.explicitDates;
    if (dates == null) return null;
    final eventsForDay = context.read<CalendarBloc>().eventsForDay;
    final picked = await CalendarDatePickerSheet.pickMulti(
      context,
      initialSelection: dates,
      firstDate: CalendarBounds.earliest,
      lastDate: CalendarBounds.latest,
      dayLoad: (day) => eventsForDay(day).length,
      appearance: _appearance(),
      initialView: view,
    );
    if (picked == null || setEquals(picked, dates)) return null;
    return event.withExplicitDates(picked);
  }

  /// Unguarded body of [openEditor], for the callers that already hold the
  /// sheet slot — the detail sheet's edit loop and the template quick-add.
  Future<EventEditorResult?> editorSheet(
    BuildContext context, {
    CalendarEvent? initialEvent,
    DateTime? day,
    DateTime? occurrenceDay,
    String? pendingOccurrenceDescription,
    bool showBack = false,
  }) async {
    // The bloc's per-day lookup is already memoized and O(1), so handing it
    // to the picker costs nothing and lets the grid show which days are
    // already busy while the user schedules.
    final eventsForDay = context.read<CalendarBloc>().eventsForDay;
    final result = await EventEditorSheet.show(
      context,
      defaultDate: initialEvent?.startDate ?? day ?? DateTime.now(),
      initialEvent: initialEvent,
      occurrenceDay: occurrenceDay,
      pendingOccurrenceDescription: pendingOccurrenceDescription,
      dayLoad: (day) => eventsForDay(day).length,
      appearance: _appearance(),
      showBack: showBack,
    );
    if (result == null || !context.mounted) return result;
    final bloc = context.read<CalendarBloc>();
    switch (result) {
      case EventEditorSaved(:final event, :final alerts):
        // Read before the dispatch: once the write lands, the facade answers
        // with the alerts being saved.
        final previousAlerts = initialEvent == null
            ? const <EventAlert>[]
            : EventAlerts.alertsFor(initialEvent.id);
        if (initialEvent == null) {
          bloc.add(CreateCalendarEvent(event: event, alerts: alerts));
        } else {
          bloc.add(UpdateCalendarEvent(event: event, alerts: alerts));
        }
        // The event write lands first so a day override can never reference an
        // event the bloc has not seen yet.
        _dispatchOccurrenceResult(bloc, event.id, result);
        unawaited(
          _afterAlertsSaved(
            context,
            result,
            previousEvent: initialEvent,
            previousAlerts: previousAlerts,
          ),
        );
      case EventEditorDeleted(:final id):
        bloc.add(DeleteCalendarEvent(eventId: id));
      // Nothing was decided, so there is nothing to write.
      case EventEditorBack():
        break;
    }
    return result;
  }

  /// What a save that carried alerts is followed by: the permission check,
  /// then — unless that one had to say an alert cannot ring — how long until
  /// the next one ([AlertCountdown]), the confirmation a phone's own clock
  /// gives when an alarm is set.
  ///
  /// A user action: the alerts are already saved, so a refusal costs nothing
  /// but the ring. One message at most, and the blocked one wins — a
  /// countdown to an alert that will not sound is the wrong thing to read.
  ///
  /// The page's own bar while the page is what is on screen, where it takes
  /// turns with every other notice raised there. While one of the page's
  /// sheets holds the slot — a save made from the detail sheet reopens that
  /// sheet at once — a `Scaffold`'s bar is drawn under it, and the overlay is
  /// the one place the line can be read.
  Future<void> _afterAlertsSaved(
    BuildContext context,
    EventEditorSaved saved, {
    required CalendarEvent? previousEvent,
    required List<EventAlert> previousAlerts,
  }) async {
    final alerts = saved.alerts;
    if (alerts == null || alerts.isEmpty) return;
    if (await _checkAlertPermissions(context, alerts)) return;
    try {
      final settings = await SettingsService.getInstance();
      final defaults = await settings.getAlertSettings();
      if (!context.mounted) return;
      final now = DateTime.now();
      final next = AlertCountdown.afterSave(
        event: saved.event,
        alerts: alerts,
        defaults: defaults,
        now: now,
        previousEvent: previousEvent,
        previousAlerts: previousAlerts,
        skippedDays: saved.skippedDays,
      );
      if (next == null) return;
      final message = AlertCountdown.message(
        next,
        now,
        AppLocalizations.of(context)!,
      );
      if (_guard.isOpen) {
        OverlaySnackbar.show(
          context,
          message,
          duration: AppConstants.snackbarDuration,
        );
      } else {
        CustomSnackbar.show(context, message);
      }
    } catch (e) {
      debugPrint('[EventSheetsFlow] alert countdown skipped: $e');
    }
  }

  /// Raises the system notification prompt the **first** time an alert is
  /// saved (§6.1), and says so every time an alert is saved that cannot ring —
  /// which is what it answers: whether it had to.
  ///
  /// The prompt is contextual and latched: it follows a user action, the alert
  /// is already persisted so a refusal costs nothing but the ring, and a
  /// denial is never asked about again from here — the launch dialog and the
  /// Permissions page are where it can still be granted. The snackbar is not
  /// latched, because an alert saved without an essential permission is an
  /// alert that silently never fires. Everything here is best-effort; a build
  /// with no permission service simply never asks.
  Future<bool> _checkAlertPermissions(
    BuildContext context,
    List<EventAlert> alerts,
  ) async {
    try {
      if (!GetIt.I.isRegistered<PermissionService>()) return false;
      final permissions = GetIt.I<PermissionService>();
      final settings = await SettingsService.getInstance();
      var snapshot = await permissions.refresh();
      if (!await settings.getAlertNotificationsAsked()) {
        if (snapshot.isMissing(AppPermission.notifications)) {
          snapshot = await permissions.promptFor(const [
            AppPermission.notifications,
          ]);
        }
        await settings.setAlertNotificationsAsked(true);
      }
      if (!snapshot.needsAttention) return false;
      if (!context.mounted) return true;
      final l10n = AppLocalizations.of(context)!;
      CustomSnackbar.showWithAction(
        context,
        message: l10n.permissionsAlertBlocked,
        actionLabel: l10n.permissionsReview,
        onAction: () {
          if (context.mounted) AppNavigator.toPermissions(context);
        },
      );
      return true;
    } catch (e) {
      debugPrint('[EventSheetsFlow] alert permission check skipped: $e');
      return false;
    }
  }

  /// Single funnel for presence marks, whichever surface produced them — the
  /// detail sheet's segmented control or the day panel's quick toggle. Both
  /// write through the bloc, which bumps `occurrenceRevision` and deliberately
  /// leaves the day cache warm: a missed occurrence still occurs.
  ///
  /// The `bool missed` widget boundary stays: a toggle is what both surfaces
  /// offer. Since **v37** either side of it writes an explicit
  /// [PresenceStatus] — returning a day to the event's own default is
  /// `clearMark`, which no UI reaches.
  static void setOccurrencePresence(
    CalendarBloc bloc,
    String eventId,
    DateTime day,
    bool missed,
  ) {
    bloc.add(
      SetOccurrencePresence(
        eventId: eventId,
        day: day,
        status: missed ? PresenceStatus.missed : PresenceStatus.present,
      ),
    );
  }

  /// Routes the editor's occurrence outcome. The sheet never writes; it
  /// reports what the user did and the flow dispatches it, so persistence
  /// stays on one path.
  void _dispatchOccurrenceResult(
    CalendarBloc bloc,
    String eventId,
    EventEditorSaved result,
  ) {
    _dispatchSkipResult(bloc, eventId, result);
    final occurrenceDay = result.occurrenceDay;
    if (occurrenceDay == null) return;
    final description = result.occurrenceDescription;
    if (description == null) {
      bloc.add(
        ClearOccurrenceDescription(eventId: eventId, day: occurrenceDay),
      );
    } else {
      bloc.add(
        SetOccurrenceDescription(
          eventId: eventId,
          day: occurrenceDay,
          description: description,
        ),
      );
    }
  }

  /// Applies the editor's cancelled-days set as a diff against what is
  /// persisted, so an unchanged day costs no write and no version bump.
  ///
  /// A null set means the picker was never opened — leave the table alone.
  void _dispatchSkipResult(
    CalendarBloc bloc,
    String eventId,
    EventEditorSaved result,
  ) {
    final next = result.skippedDays;
    if (next == null) return;
    final current = EventSkips.daysFor(eventId);
    for (final day in next.difference(current)) {
      bloc.add(SetOccurrenceSkipped(eventId: eventId, day: day));
    }
    for (final day in current.difference(next)) {
      bloc.add(ClearOccurrenceSkipped(eventId: eventId, day: day));
    }
  }

  /// The linked note's title for the detail sheet's row, or null once the
  /// note is gone. The same lookup [openLinkedNote] makes, so the row and
  /// the tap agree on what "missing" means — `getNotesByIds` filters soft
  /// deletes where `getNoteById` does not.
  static Future<String?> _resolveNoteTitle(String noteId) async {
    final notes = await GetIt.I<NoteRepository>().getNotesByIds([noteId]);
    return notes.isEmpty ? null : notes.first.title;
  }

  /// Open the workout note linked to [event]. The folder is resolved from
  /// the note at tap time (not stored on the event), so the link survives
  /// the note being moved. The note opens in the standard editor, which
  /// restores its own persisted view (code-editing or markdown preview).
  ///
  /// Uses [NoteRepository.getNotesByIds] (not `getNoteById`) because only it
  /// filters out soft-deleted notes, so a deleted linked note reads as
  /// missing and surfaces a non-blocking error instead of opening a ghost.
  Future<void> openLinkedNote(BuildContext context, CalendarEvent event) async {
    final noteId = event.noteId;
    if (noteId == null) return;
    final l10n = AppLocalizations.of(context)!;
    final repository = GetIt.I<NoteRepository>();
    final notes = await repository.getNotesByIds([noteId]);
    if (!context.mounted) return;
    final note = notes.isEmpty ? null : notes.first;
    if (note == null) {
      CustomSnackbar.showError(context, l10n.eventLinkedNoteMissing);
      return;
    }
    // Pass the metadata mapped from the row we already fetched: the editor
    // seeds its title bar from it, so a metadata-less push showed
    // "New note" instead of the note's real title.
    AppNavigator.toNoteEditor(
      context,
      folderId: note.folderId,
      noteId: note.id,
      metadata: repository.noteToMetadata(note),
    );
  }

  /// Open the note a `[[title]]` in an event description names. Reached from
  /// the detail sheet, which has already begun closing (it popped with no
  /// action, its exit animation may still be running) by the time this runs —
  /// so the editor pushes over the page beneath and a snackbar for a title
  /// that resolves to nothing is actually visible.
  ///
  /// That push still reaches the page's [RouteAware], exactly as the
  /// linked-note button's does: a route the navigator has popped leaves the
  /// "present" range of its history while it animates out, so
  /// `RouteObserver<PageRoute>` reports the push against the page's own
  /// [PageRoute] rather than against the dismissing sheet (a [PopupRoute],
  /// which it would have ignored) — [RouteAware.didPushNext] and
  /// [RouteAware.didPopNext] pair up as usual and whatever the page suspends
  /// while covered stays suspended for the trip.
  ///
  /// The lookup takes the full trimmed title; only the "not found" message is
  /// bounded, because a note can genuinely be named by a long line and a
  /// snackbar cannot show one.
  ///
  /// No folder preference, unlike the editor's version of this: a calendar
  /// event belongs to no folder, so there is no neighbourhood for the link to
  /// prefer and the most recently updated match wins outright.
  Future<void> _openWikiLink(BuildContext context, String rawTitle) async {
    final title = rawTitle.trim();
    if (title.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    try {
      final note = await GetIt.I<NoteStorageService>().resolveNoteByTitle(
        title,
      );
      if (!context.mounted) return;
      if (note == null) {
        CustomSnackbar.show(
          context,
          l10n.wikiLinkNoteNotFound(WikiLinkTitle.forDisplay(title)),
        );
        return;
      }
      AppNavigator.toNoteEditor(
        context,
        folderId: note.folderId,
        noteId: note.id,
        metadata: note,
      );
    } catch (e) {
      // The sheet is already gone, so a failed lookup would otherwise read as
      // a tap that did nothing at all.
      if (!context.mounted) return;
      CustomSnackbar.showError(context, l10n.error('$e'));
    }
  }
}
