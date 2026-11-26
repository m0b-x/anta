import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:re_editor/re_editor.dart';
import 'package:uuid/uuid.dart';

import '../bloc/markdown_bar/markdown_bar_bloc.dart';
import '../constants/app_constants.dart';
import '../constants/calendar_bounds.dart';
import '../constants/event_skips.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../constants/category_profiles.dart';
import '../constants/event_alerts.dart';
import '../constants/event_priorities.dart';
import '../constants/event_title.dart';
import '../constants/font_constants.dart';
import '../constants/occurrence_descriptions.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../constants/settings_keys.dart';
import '../controllers/editor_edit_tracker.dart';
import '../controllers/editor_render_controller.dart';
import '../controllers/markdown_shortcut_inserter.dart';
import '../controllers/shortcut_applier.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/category_alert.dart';
import '../models/category_profile.dart';
import '../models/event_alert.dart';
import '../models/event_template.dart';
import '../models/custom_markdown_shortcut.dart';
import '../models/recurrence_rule.dart';
import '../models/utility_button_config.dart';
import '../repositories/note_repository.dart';
import '../services/app_navigator.dart';
import '../services/event_time_formatter.dart';
import '../services/recurrence_formatter.dart';
import '../services/settings_service.dart';
import '../services/share_service.dart'
    show ShareAvailability, ShareNotPaired, ShareReady;
import '../utils/editor_render_context.dart';
import '../utils/list_aware_paste.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/markdown_editor_span_builder.dart';
import '../utils/re_editor_search_controller.dart';
import '../utils/share_copy.dart';
import 'alert_editor_sheet.dart';
import 'app_dialogs.dart';
import 'automation_id.dart';
import 'calendar_date_picker_sheet.dart';
import 'category_picker_sheet.dart';
import 'event_alert_rows.dart';
import 'event_avatar.dart';
import 'event_description_sheet.dart';
import 'event_look_sheet.dart';
import 'event_repeat_sheet.dart';
import 'event_share_row.dart';
import 'event_template_editor_sheet.dart';
import 'form_rows.dart';
import 'markdown_bar.dart';
import 'modern_editor_wrapper.dart';
import 'note_picker_dialog.dart';
import 'overlay_snackbar.dart';
import 'scroll_progress_indicator.dart';
import 'simple_markdown_preview.dart';
import 'time_pad_sheet.dart';
import 'value_change_highlight.dart';

part 'event_editor_sheet/state.dart';
part 'event_editor_sheet/description.dart';
part 'event_editor_sheet/rules.dart';
part 'event_editor_sheet/pickers.dart';
part 'event_editor_sheet/saving.dart';
part 'event_editor_sheet/alerts_and_links.dart';
part 'event_editor_sheet/description_views.dart';
part 'event_editor_sheet/rows.dart';
part 'event_editor_sheet/description_box.dart';

/// Result returned by [EventEditorSheet.show]. `null` means cancelled.
sealed class EventEditorResult {
  const EventEditorResult();
}

class EventEditorSaved extends EventEditorResult {
  final CalendarEvent event;

  /// The occurrence the user was editing, when they said anything about it.
  /// Null means "nothing to do for any single day".
  final DateTime? occurrenceDay;

  /// What to store for [occurrenceDay]: a string writes that day's override
  /// (an empty one deliberately blanks the day), `null` **deletes** it so the
  /// day returns to the event's template. Only meaningful when
  /// [occurrenceDay] is non-null.
  ///
  /// The sheet never persists any of this itself — it reports the outcome and
  /// the page dispatches it, so writes stay on one path.
  final String? occurrenceDescription;

  /// The full set of cancelled days the user left the picker with (**v30**),
  /// or `null` when they never opened it.
  ///
  /// A whole set rather than a diff because the picker is a set editor: the
  /// page diffs it against the facade and dispatches the adds and removes, so
  /// the sheet stays write-free exactly as it is for descriptions.
  final Set<DateTime>? skippedDays;

  /// The complete alert set the form left the event with (**v40**), or `null`
  /// when this result was produced by a path that never showed them.
  ///
  /// A whole set, like [skippedDays], because `EventAlertService.replaceForEvent`
  /// is a set write: it tombstones what is missing and upserts what is there,
  /// in one transaction, so a diff computed here would be a second answer to a
  /// question the DAO already answers.
  ///
  /// `removeAfterAlert` is deliberately **not** beside it — it is a column on
  /// the event, so it rides [event] and cannot drift from what was saved.
  final List<EventAlert>? alerts;

  /// The ids [alerts] was seeded from, which bound what the save may remove:
  /// an alert that arrived by sync while the form was open is in neither set
  /// and survives, instead of reading as one the user deleted. Null wherever
  /// [alerts] is.
  final Set<String>? knownAlertIds;

  /// The event's own share mark as the form left it, or `null` when the
  /// form showed no share row (not paired, the guide's sandbox).
  ///
  /// Beside [event] rather than on it: `CalendarEvent.markedShared` is
  /// never written by a save (a new event has no row to mark yet), so the
  /// flow sets the mark through the share service once the event is stored.
  final bool? shared;

  const EventEditorSaved(
    this.event, {
    this.occurrenceDay,
    this.occurrenceDescription,
    this.skippedDays,
    this.alerts,
    this.knownAlertIds,
    this.shared,
  });
}

class EventEditorDeleted extends EventEditorResult {
  final String id;
  const EventEditorDeleted(this.id);
}

/// The user left the form to go back where they came from, discarding their
/// edits exactly as the close button does.
///
/// A distinct result rather than a second modal route stacked on the detail
/// sheet: the caller reopens the sheet it owns, so there is never a second
/// barrier, and the editor keeps its one rule — it reports what the user did
/// and the page dispatches it. Only reachable when
/// [EventEditorSheet.showBack] is set.
class EventEditorBack extends EventEditorResult {
  const EventEditorBack();
}

/// Top-level repeat mode shown as a segmented control.
enum _RepeatMode { oneTime, recurring }

/// Which description the editor's field is currently showing (v24). Only
/// meaningful while the scope control is visible; otherwise the field always
/// shows [allDays].
enum _DescriptionScope { allDays, thisDay }

/// The three positions of the day-rail control, mapping onto the nullable
/// `CalendarEvent.showInDayRail` column. A `SegmentedButton` needs a
/// non-nullable value type, and `null` — *auto* — is a real choice here, not
/// the absence of one.
enum _DayRailChoice {
  auto(null),
  always(true),
  never(false);

  final bool? value;

  const _DayRailChoice(this.value);

  static _DayRailChoice of(bool? value) => switch (value) {
    null => auto,
    true => always,
    false => never,
  };
}

/// Bottom-sheet form for creating or editing a [CalendarEvent].
class EventEditorSheet extends StatefulWidget {
  final CalendarEvent? initialEvent;
  final DateTime defaultDate;

  /// The occurrence the user opened the editor from (date-only UTC), or null
  /// when there isn't one — the FAB path, where a brand-new event has no
  /// occurrence yet. Non-null is what unlocks the "this day / all days"
  /// description scope control.
  final DateTime? occurrenceDay;

  /// A just-written override for [occurrenceDay] that may not have reached the
  /// database yet, used instead of reading the facade.
  ///
  /// Closes a real race: the detail sheet flushes a checkbox tick as a bloc
  /// event and pops in the same turn, so the editor can mount before that
  /// write lands. Reading the facade there would show the pre-tick text and a
  /// subsequent save could overwrite the tick.
  final String? pendingOccurrenceDescription;

  /// How busy a day already is, forwarded to the date picker so a day that
  /// already carries events is visible while scheduling. Callers pass the
  /// calendar bloc's memoized per-day lookup — never a fresh query.
  final PickerDayLoad? dayLoad;

  /// Calendar look & feel, forwarded to the date picker so its grid matches
  /// the real one on the first frame. Passed down rather than re-read: the
  /// page already holds a current copy and refreshes it on settings return.
  final CalendarAppearance appearance;

  /// Whether there is a sheet behind this one to return to, which turns the
  /// leading close button into a back button. Left false on the paths that
  /// open the editor directly (the FAB, the agenda pencil, quick-add): a
  /// brand-new event has nothing behind it.
  ///
  /// Back and close leave the same way — both ask first when the form is
  /// dirty and discard the same edits — and differ only in where the user
  /// lands. Which is why back *replaces* close rather than joining it: two
  /// adjacent buttons that differ only in destination is a distinction too
  /// fine to hang a second icon on.
  final bool showBack;

  /// The calendar guide's demos open the real form over a throwaway event.
  /// Save and Delete still only return their result, so what is left out is
  /// what writes on its own: Save as template, the Linked note row (a demo
  /// event must not point at a real note), Create category in the picker,
  /// palette editing in Icon & color and the recent-icon record its icon
  /// picker keeps.
  final bool sandbox;

  /// The event's cancelled days and its own alerts as the caller keeps them,
  /// in place of `EventSkips` / `EventAlerts`. Null reads the facades; the
  /// guide's practice calendar keeps both in memory, so the facades hold
  /// nothing for its events.
  final Set<DateTime>? initialSkippedDays;
  final List<EventAlert>? initialAlerts;

  /// Whether this database can share and with whom, read by the opener as
  /// [dayLoad] is: the share row is absent while [ShareNotPaired], so a
  /// person who never paired sees the form as it always was.
  final ShareAvailability shareAvailability;

  /// Asks the opener for [shareAvailability] again, once Sync & sharing —
  /// pushed from the dimmed share row — returns: sync turned on there
  /// enables the row the person left it for. With it comes the event's mark
  /// as stored now (false for a new event), since that page can stop every
  /// share. Null keeps the first answers.
  final Future<({ShareAvailability availability, bool markedShared})>
  Function()?
  rereadShare;

  const EventEditorSheet({
    super.key,
    required this.defaultDate,
    this.initialEvent,
    this.occurrenceDay,
    this.pendingOccurrenceDescription,
    this.dayLoad,
    this.appearance = const CalendarAppearance(),
    this.showBack = false,
    this.sandbox = false,
    this.initialSkippedDays,
    this.initialAlerts,
    this.shareAvailability = const ShareNotPaired(),
    this.rereadShare,
  });

  static Future<EventEditorResult?> show(
    BuildContext context, {
    required DateTime defaultDate,
    CalendarEvent? initialEvent,
    DateTime? occurrenceDay,
    String? pendingOccurrenceDescription,
    PickerDayLoad? dayLoad,
    CalendarAppearance appearance = const CalendarAppearance(),
    bool showBack = false,
    bool sandbox = false,
    Set<DateTime>? initialSkippedDays,
    List<EventAlert>? initialAlerts,
    ShareAvailability shareAvailability = const ShareNotPaired(),
    Future<({ShareAvailability availability, bool markedShared})> Function()?
    rereadShare,
  }) {
    return showModalBottomSheet<EventEditorResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (_) => FractionallySizedBox(
        heightFactor: FormMetrics.sheetHeightFactor,
        child: EventEditorSheet(
          defaultDate: defaultDate,
          initialEvent: initialEvent,
          occurrenceDay: occurrenceDay,
          pendingOccurrenceDescription: pendingOccurrenceDescription,
          dayLoad: dayLoad,
          appearance: appearance,
          showBack: showBack,
          sandbox: sandbox,
          initialSkippedDays: initialSkippedDays,
          initialAlerts: initialAlerts,
          shareAvailability: shareAvailability,
          rereadShare: rereadShare,
        ),
      ),
    );
  }

  @override
  State<EventEditorSheet> createState() => _EventEditorSheetState();
}

class _EventEditorSheetState extends _EventEditorState
    with
        _EventEditorDescription,
        _EventEditorRules,
        _EventEditorPickers,
        _EventEditorSaving,
        _EventEditorAlertsAndLinks,
        _EventEditorDescriptionViews,
        _EventEditorRows {
  /// Default start-of-day for newly enabled timed events. 9:00 is a
  /// neutral choice that suits a gym-planner; user can edit immediately.
  static const int _defaultStartMinute = 9 * 60;
  static const double _priorityMenuWidth = FormMetrics.menuWidth;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialEvent;
    _titleController = TextEditingController(text: initial?.title ?? '');
    _descriptionController = ListAwarePasteController(
      delegate: CodeLineEditingController(spanBuilder: _buildDescriptionSpan),
      isFenceLine: _descriptionSpanBuilder.lineInFence,
    );
    _descriptionEdits = EditorEditTracker(
      controller: _descriptionController,
      // No width reflow here: the field has no auto-break setting and no
      // measured width, so the tracker is only ever the Enter half.
      autoBreakLongLines: () => false,
      pasteContext: () => null,
      onLinesReformatted: (_) {},
      isFenceLine: _descriptionSpanBuilder.lineInFence,
    );
    _templateBuffer = initial?.description ?? '';
    // Copy-on-write seed: a day with no row of its own starts from the
    // template, so a checklist written once is what every session begins
    // with. Only an edit that actually diverges materializes a row.
    // A write still in flight beats the facade — see
    // [EventEditorSheet.pendingOccurrenceDescription].
    final storedOverride =
        widget.pendingOccurrenceDescription ??
        ((initial != null && widget.occurrenceDay != null)
            ? OccurrenceDescriptions.overrideFor(
                initial.id,
                widget.occurrenceDay!,
              )
            : null);
    _dayMaterialized = storedOverride != null;
    _dayBuffer = storedOverride ?? _templateBuffer;
    _daySeedText = _dayBuffer;
    _initialTemplateLength = _templateBuffer.length;
    _initialDayLength = _dayBuffer.length;
    // Seeded in the shared scope; the day scope is adopted below, once the
    // recurrence rule is known. Seeding is a load, not an edit: `set text`
    // would be revocable and undo could wipe what the sheet opened with.
    _descriptionController.loadText(_templateBuffer);
    // Every seed is what the next keystroke diffs against; without this
    // the whole loaded text reads as a paste.
    _descriptionEdits.syncLength();
    _descriptionSpanBuilder.bind(_descriptionController);
    _descriptionFocus = FocusNode()..addListener(_onDescriptionFocusChanged);
    // The wrapper's taps read real focus, so the rendering must too: an
    // unfocused description shows its caret line rendered, box and all.
    _descriptionSpanBuilder.bindFocus(_descriptionFocus);
    _descriptionScroll = CodeScrollController();
    _descriptionSearch = ReEditorSearchController()
      ..initialize(_descriptionController);
    _categoryId = initial?.categoryId ?? CalendarCategories.defaultForNewEvent;
    _iconKey = initial?.iconKey;
    _date = _normalize(initial?.startDate ?? widget.defaultDate);
    _endDate = initial?.endDate == null ? null : _normalize(initial!.endDate!);
    final initialTime = initial?.time;
    _isAllDay = initialTime == null;
    _startMinute = initialTime?.startMinute ?? _defaultStartMinute;
    _durationMinutes = initialTime?.durationMinutes;
    // A demo event points at no note, so the sandbox never reads one either.
    _noteId = widget.sandbox ? null : initial?.noteId;
    _colorValue = initial?.colorValue;
    _tintIcon = initial?.tintIcon ?? true;
    _priority = initial?.priority ?? kDefaultEventPriority;
    _retroactive = initial?.retroactive ?? false;
    _countOccurrences = initial?.countOccurrences ?? false;
    _tracksPresence = initial?.tracksPresence ?? false;
    _trackedAtOpen = _tracksPresence;
    _assumeAbsent = initial?.assumeAbsent ?? false;
    _applyKindPresenceDefaults();
    _assumeAbsentFrom = initial?.assumeAbsentFrom == null
        ? null
        : _normalize(initial!.assumeAbsentFrom!);
    _showInDayRail = initial?.showInDayRail;
    _perOccurrenceDescriptions = initial?.perOccurrenceDescriptions ?? false;
    // Synchronous on purpose: the facade is published before the calendar
    // page can open this sheet, so an existing event's alerts are on screen in
    // the first frame rather than appearing under the user's thumb. A new
    // event's default arrives with [_loadSheetSettings] — there is nothing to
    // read here for an event that does not exist yet.
    _alerts = initial == null
        ? const []
        : List<EventAlert>.of(
            widget.initialAlerts ?? EventAlerts.alertsFor(initial.id),
          );
    _seededAlertIds = {for (final alert in _alerts) alert.id};
    _removeAfterAlert = initial?.removeAfterAlert ?? false;
    _categoryAlerts = initial?.categoryAlerts ?? true;
    _markedShared = initial?.markedShared ?? false;
    _storedMark = _markedShared;
    _initRecurrenceFrom(initial?.rule ?? const OneTimeRecurrence());
    // Only a saved event that was actually counting carries a style the user
    // can be said to have chosen; otherwise the persisted value is just the
    // column default and the frequency should pick it.
    _countStyleTouched = initial != null && initial.countOccurrences;
    _countStyle = _countStyleTouched
        ? initial!.countStyle
        : _defaultCountStyleFor(_kind);
    // Adopt the day scope only now: it needs the recurrence rule, which
    // `_initRecurrenceFrom` has just decoded, and the event's own flag, seeded
    // just above. Gated on the same condition as the control itself, so a
    // *dormant* row (flag off) can never leave the field showing one day's
    // text with nothing on screen to explain it.
    if (_dayMaterialized && _scopeControlVisible) {
      _scope = _DescriptionScope.thisDay;
      _descriptionController.loadText(_dayBuffer);
      _descriptionEdits.syncLength();
    }
    // Subscribed last, after every seeding write above, so opening the sheet
    // costs no spurious relay bump.
    _descriptionController.addListener(_relayDescriptionChange);
    if (_noteId != null) _loadLinkedNoteTitle();
    _loadSheetSettings();
    // The bar bloc is app-wide and only the note editor loads it, so from a
    // cold start into the calendar it is still Initial. Resolving with a null
    // note id yields the active profile — the right default for a field that
    // belongs to no note. An already-loaded bar is left alone.
    final barBloc = context.read<MarkdownBarBloc>();
    if (barBloc.state is! MarkdownBarLoaded) {
      barBloc.add(const LoadMarkdownBar());
    }
    _initialFingerprint = _fingerprint();
    _initialAlertsFingerprint = _alertsFingerprint();
  }

  void _initRecurrenceFrom(RecurrenceRule rule) {
    // Sensible default weekday set anchored to the event start date.
    _weekdays = {_date.weekday};
    _interval = 1;
    _additionalDates = [];
    switch (rule) {
      case OneTimeRecurrence():
        _mode = _RepeatMode.oneTime;
        _kind = RepeatKind.daily;
      case SpecificDatesRecurrence(:final dates):
        _mode = _RepeatMode.oneTime;
        _kind = RepeatKind.daily;
        _additionalDates = dates.where((d) => d != _date).toList()..sort();
      case DailyRecurrence(:final interval):
        _mode = _RepeatMode.recurring;
        _kind = RepeatKind.daily;
        _interval = interval;
      case WeeklyRecurrence(:final weekdays, :final interval):
        _mode = _RepeatMode.recurring;
        _kind = RepeatKind.weekly;
        _weekdays = weekdays.isEmpty ? {_date.weekday} : Set.of(weekdays);
        _interval = interval;
      case MonthlyRecurrence(:final interval):
        _mode = _RepeatMode.recurring;
        _kind = RepeatKind.monthly;
        _interval = interval;
      case YearlyRecurrence(:final interval):
        _mode = _RepeatMode.recurring;
        _kind = RepeatKind.yearly;
        _interval = interval;
      case WorkdaysRecurrence():
        _mode = _RepeatMode.recurring;
        _kind = RepeatKind.workdays;
      case WeekendsRecurrence():
        _mode = _RepeatMode.recurring;
        _kind = RepeatKind.weekends;
      case PublicHolidaysOnlyRecurrence():
        _mode = _RepeatMode.recurring;
        _kind = RepeatKind.holidays;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyScroll.dispose();
    _hairline.dispose();
    _descriptionController.removeListener(_relayDescriptionChange);
    _descriptionController.dispose();
    _descriptionRevision.dispose();
    _descriptionMetricsTick.dispose();
    _descriptionPreviewScroll.dispose();
    _descriptionSpanBuilder.bindFocus(null);
    _descriptionFocus.dispose();
    _descriptionScroll.dispose();
    _descriptionSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final localeName = l10n.localeName;
    final category = CalendarCategories.resolve(_categoryId);
    final categoryColor = category.color;
    final accent = (_colorValue != null && _tintIcon)
        ? Color(_colorValue!)
        : categoryColor;
    final eventColor = _colorValue == null
        ? categoryColor
        : Color(_colorValue!);
    final icon =
        CalendarIcons.forKey(_iconKey) ??
        CalendarIcons.forKey(category.iconKey) ??
        Icons.event_rounded;
    final oneTimeDates = <DateTime>{_date, ..._additionalDates}.toList()
      ..sort();
    final dateFormat = DateFormat.yMMMEd(localeName);
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomClearance = viewInsets > viewPadding ? viewInsets : viewPadding;

    final frame = FormSheetFrame(
      onLeave: _leave,
      isClean: () => !_isDirty,
      onDismiss: _popDiscarding,
      chrome: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FormSheetHandle(),
          FormSheetHeader(
            leadingIcon: widget.showBack
                ? Icons.arrow_back_rounded
                : Icons.close_rounded,
            leadingTooltip: widget.showBack ? l10n.back : l10n.cancel,
            onLeading: _leave,
            leadingIdentifier: SemanticsIds.eventClose,
            title: _isEditing ? l10n.editEvent : l10n.addEvent,
            stackTitleAtLargeText: true,
            scrolled: _hairline.scrolled,
            trailing: ListenableBuilder(
              listenable: Listenable.merge([
                _descriptionRevision,
                _titleController,
              ]),
              builder: (context, _) => AutomationId(
                identifier: SemanticsIds.eventSave,
                child: FilledButton(
                  onPressed: _canSave ? _onSave : null,
                  child: Text(
                    l10n.save,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: [
        Expanded(
          child: _hairline.watch(
            child: Semantics(
              identifier: SemanticsIds.eventForm,
              child: SingleChildScrollView(
                controller: _bodyScroll,
                padding: EdgeInsets.fromLTRB(
                  RowMetrics.groupInset,
                  FormMetrics.bodyTop,
                  RowMetrics.groupInset,
                  FormMetrics.bodyBottom +
                      (_descriptionFocused ? 0 : bottomClearance),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FormRowGroup(
                      children: [
                        _buildTitleRow(l10n, icon, accent),
                        FormPickerRow(
                          glyph: Icons.category_rounded,
                          identifier: SemanticsIds.eventCategory,
                          label: l10n.eventCategory,
                          value: CalendarCategories.labelOf(category, l10n),
                          onTap: _pickCategory,
                        ),
                        FormPickerRow(
                          glyph: Icons.palette_outlined,
                          identifier: SemanticsIds.eventLook,
                          label: l10n.eventAppearance,
                          value: _iconKey != null || _colorValue != null
                              ? l10n.eventLookCustom
                              : l10n.eventLookDefault,
                          valueLeading: FormValueDot(color: eventColor),
                          onTap: _pickLook,
                          dividerIndent: FormMetrics.dividerIndentPlain,
                        ),
                        _buildDescriptionCell(l10n, theme),
                      ],
                    ),
                    FormSectionLabel(text: l10n.eventSectionWhen),
                    FormRowGroup(
                      children: _buildWhenRows(l10n, dateFormat, oneTimeDates),
                    ),
                    if (_presenceOffered) ...[
                      FormSectionLabel(text: l10n.recurrenceScopeLabel),
                      FormRowGroup(
                        children: _buildOccurrenceRows(l10n, dateFormat),
                      ),
                    ],
                    FormSectionLabel(text: l10n.eventAlerts),
                    FormRowGroup(children: _buildAlertRows(l10n)),
                    FormSectionLabel(text: l10n.eventSectionDetails),
                    FormRowGroup(
                      // The last group when the sandbox drops the actions
                      // below, and a last group ends without a gap.
                      trailingGap: !widget.sandbox || _isEditing,
                      children: [
                        FormMenuRow<int>(
                          glyph: Icons.flag_outlined,
                          identifier: SemanticsIds.eventPriority,
                          label: l10n.eventPriority,
                          value: EventPriorities.labelOf(_priority, l10n),
                          selected: _priority,
                          menuWidth: _priorityMenuWidth,
                          items: [
                            for (
                              var p = kMinEventPriority;
                              p <= kMaxEventPriority;
                              p++
                            )
                              FormMenuItem(
                                value: p,
                                label: EventPriorities.labelOf(p, l10n),
                                icon: EventPriorities.iconFor(p),
                              ),
                          ],
                          onSelected: (p) => setState(() => _priority = p),
                        ),
                        if (!widget.sandbox) _buildLinkedNoteRow(l10n, theme),
                        if (_shareRowShown) _buildShareRow(l10n),
                      ],
                    ),
                    // A sandboxed new event has no action left to offer, and
                    // an empty group would still draw its gap.
                    if (!widget.sandbox || _isEditing)
                      FormRowGroup(
                        trailingGap: false,
                        children: [
                          if (!widget.sandbox)
                            ListenableBuilder(
                              listenable: _titleController,
                              builder: (context, _) => FormActionRow(
                                glyph: Icons.bookmark_add_outlined,
                                identifier: SemanticsIds.eventSaveAsTemplate,
                                label: l10n.saveAsTemplate,
                                onTap: _titleController.text.trim().isEmpty
                                    ? null
                                    : _onSaveAsTemplate,
                              ),
                            ),
                          if (_isEditing)
                            FormActionRow(
                              glyph: Icons.delete_outline_rounded,
                              identifier: SemanticsIds.eventDelete,
                              label: l10n.deleteEvent,
                              destructive: true,
                              onTap: _onDelete,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _descriptionFocused
              ? Padding(
                  padding: EdgeInsets.only(bottom: bottomClearance),
                  child: _buildDescriptionBar(),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _onFormMetrics,
      child: frame,
    );
  }
}
