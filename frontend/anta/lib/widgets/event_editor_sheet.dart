import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:re_editor/re_editor.dart';
import 'package:uuid/uuid.dart';

import '../bloc/markdown_bar/markdown_bar_bloc.dart';
import '../constants/app_colors.dart';
import '../constants/calendar_bounds.dart';
import '../constants/event_skips.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../constants/event_alerts.dart';
import '../constants/event_priorities.dart';
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
import '../models/event_alert.dart';
import '../models/event_template.dart';
import '../models/custom_markdown_shortcut.dart';
import '../models/recurrence_rule.dart';
import '../models/utility_button_config.dart';
import '../repositories/note_repository.dart';
import '../services/event_time_formatter.dart';
import '../services/recurrence_formatter.dart';
import '../services/settings_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/editor_render_context.dart';
import '../utils/list_aware_paste.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/markdown_editor_span_builder.dart';
import '../utils/re_editor_search_controller.dart';
import 'alert_editor_sheet.dart';
import 'automation_id.dart';
import 'calendar_date_picker_sheet.dart';
import 'category_picker_sheet.dart';
import 'event_avatar.dart';
import 'event_description_sheet.dart';
import 'event_look_sheet.dart';
import 'event_repeat_sheet.dart';
import 'event_template_editor_sheet.dart';
import 'form_rows.dart';
import 'markdown_bar.dart';
import 'modern_editor_wrapper.dart';
import 'note_picker_dialog.dart';
import 'simple_markdown_preview.dart';
import 'time_pad_sheet.dart';
import 'value_change_highlight.dart';

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

  const EventEditorSaved(
    this.event, {
    this.occurrenceDay,
    this.occurrenceDescription,
    this.skippedDays,
    this.alerts,
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

  const EventEditorSheet({
    super.key,
    required this.defaultDate,
    this.initialEvent,
    this.occurrenceDay,
    this.pendingOccurrenceDescription,
    this.dayLoad,
    this.appearance = const CalendarAppearance(),
    this.showBack = false,
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
  }) {
    return showModalBottomSheet<EventEditorResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (_) => FractionallySizedBox(
        heightFactor: _EventEditorSheetState._sheetHeightFactor,
        child: EventEditorSheet(
          defaultDate: defaultDate,
          initialEvent: initialEvent,
          occurrenceDay: occurrenceDay,
          pendingOccurrenceDescription: pendingOccurrenceDescription,
          dayLoad: dayLoad,
          appearance: appearance,
          showBack: showBack,
        ),
      ),
    );
  }

  @override
  State<EventEditorSheet> createState() => _EventEditorSheetState();
}

class _EventEditorSheetState extends State<EventEditorSheet>
    with SingleTickerProviderStateMixin {
  /// Default start-of-day for newly enabled timed events. 9:00 is a
  /// neutral choice that suits a gym-planner; user can edit immediately.
  static const int _defaultStartMinute = 9 * 60;

  /// Default duration the first time a user enables an end time on a new
  /// timed event (60 minutes — a typical session).
  static const int _defaultDurationMinutes = 60;

  static const double _sheetHeightFactor = 0.92;
  static const int _maxInlineDates = 3;
  static const double _titleFontSize = 20;
  static const double _titleLineHeight = 1.3;
  static const double _titleTopInset = 7;
  static const double _titleRowVerticalPadding = 8;
  static const double _counterTopInset = 2;
  static const double _descriptionCounterTopInset = 4;
  static const int _titleMaxLength = 120;
  static const int _titleCounterFrom = 100;
  static const double _descriptionFontSize = 15;
  static const double _descriptionLineHeight = 22;
  static const int _descriptionMaxLines = 10;
  static const double _descriptionCellPadding = 13;
  static const double _scopeStripHeight = 44;
  static const double _priorityMenuWidth = 220;
  static const double _dayRailMenuWidth = 180;
  static const double _dismissVelocity = 700;
  static const Duration _snapBackDuration = Duration(milliseconds: 150);
  static const Duration _revealDuration = Duration(milliseconds: 250);

  /// Utility buttons the description bar carries. Font sizing, sharing, bar
  /// switching, counters and scroll jumps all belong to a note, not to a
  /// 2000-character field; settings and reorder are suppressed by flag.
  static const List<UtilityButtonConfig> _descriptionUtilities = [
    UtilityButtonConfig(id: UtilityButtonId.undo),
    UtilityButtonConfig(id: UtilityButtonId.redo),
    UtilityButtonConfig(id: UtilityButtonId.paste),
  ];

  late final TextEditingController _titleController;

  /// The description is edited in the same re_editor surface the note editor
  /// uses, so live markdown rendering, tap-to-toggle checkboxes, list
  /// continuation and the markdown bar all behave identically here. The
  /// stored value is still plain markdown source on the event row — nothing
  /// about this widget is persisted.
  late final CodeLineEditingController _descriptionController;

  /// Enter list continuation and the re-entrancy guard for programmatic
  /// inserts — the same tracker the note editor and the description sheet
  /// run, so a `- ` typed here continues exactly as it does there. Holds
  /// no resources, so nothing to dispose.
  late final EditorEditTracker _descriptionEdits;

  late final FocusNode _descriptionFocus;
  late final CodeScrollController _descriptionScroll;

  /// The wrapper requires one; the description has no search UI, so it is
  /// created, wired and thrown away with the sheet.
  late final ReEditorSearchController _descriptionSearch;

  final MarkdownEditorSpanBuilder _descriptionSpanBuilder =
      MarkdownEditorSpanBuilder();

  /// The renderer's theme generation, resolved once per theme/style
  /// change instead of once per line.
  final EditorRenderContextCache _descriptionRenderContext =
      EditorRenderContextCache();

  /// Build-safe relay for [_descriptionController]'s notifications.
  ///
  /// Nothing in this sheet may listen to the controller directly. re_editor's
  /// `_CodeEditorState.initState` wraps the controller in its own delegate and
  /// the `delegate =` setter calls `notifyListeners()` **synchronously** — and
  /// `initState` runs while the framework is building. Every `ListenableBuilder`
  /// mounted above the editor (the Save button, the counter, the over-limit
  /// hint) is already clean by then, so its `markNeedsBuild` throws
  /// "setState() called during build" on the sheet's very first frame.
  ///
  /// Keystrokes arrive outside the frame and take the synchronous path; only a
  /// mid-build notification is deferred, and repeats coalesce into one bump.
  final ValueNotifier<int> _descriptionRevision = ValueNotifier<int>(0);
  bool _revisionBumpScheduled = false;

  /// Anchors the scroll-into-view on focus.
  final GlobalKey _descriptionKey = GlobalKey();
  final GlobalKey _sheetKey = GlobalKey();
  final ScrollController _bodyScroll = ScrollController();
  final ValueNotifier<bool> _headerScrolled = ValueNotifier<bool>(false);
  final ValueNotifier<double> _dragOffset = ValueNotifier<double>(0);
  late final AnimationController _snapBack;
  double _snapFrom = 0;
  late String _initialFingerprint;
  bool _leaving = false;
  late String _categoryId;
  String? _iconKey;
  late DateTime _date;
  DateTime? _endDate;
  late _RepeatMode _mode;
  late RepeatKind _kind;
  late Set<int> _weekdays;

  /// Recurrence interval ("every N …"). Always ≥ 1; only meaningful for the
  /// periodic kinds (daily/weekly/monthly/yearly). Carried across kind
  /// switches so toggling daily↔weekly keeps the chosen number.
  int _interval = 1;

  /// Whether the rule also fires before [_date]. Only meaningful (and only
  /// shown) for recurring events — one-time and specific-date sets have
  /// exact membership.
  bool _retroactive = false;

  /// Whether each occurrence carries a count label derived from [_date].
  /// Only meaningful (and only shown) for the periodic kinds — the same set
  /// that supports an interval.
  bool _countOccurrences = false;

  /// Whether the event records which of its occurrences were missed. Only
  /// meaningful for a rule with more than one occurrence — an event that
  /// fires once has no attendance to keep — which is exactly the set
  /// [_ruleHasManyOccurrences] describes, so specific-dates participates.
  bool _tracksPresence = false;

  /// Whether unmarked occurrences read as **missed** rather than attended
  /// (**v37**). Draft state for `CalendarEvent.assumeAbsent`; meaningless
  /// while [_tracksPresence] is off, and cleared on save in that case.
  bool _assumeAbsent = false;

  /// Optional date-only UTC lower bound for [_assumeAbsent], or `null` for
  /// "start of event". Only offered while editing: a brand-new event has no
  /// history for a from-date to protect.
  DateTime? _assumeAbsentFrom;

  /// Whether the user has picked or cleared [_assumeAbsentFrom] themselves —
  /// the [_countStyleTouched] idiom. The seed in [_selectAssumeAbsent] fires
  /// only while this is false, so a boundary the user deliberately cleared to
  /// "start of event" cannot come back on the next toggle.
  bool _assumeAbsentFromTouched = false;

  /// Whether the event shows on the day-cell rail: `null` = auto (follow
  /// [_tracksPresence]), `true` = always, `false` = never.
  ///
  /// Tri-state on purpose — auto is what makes the column need no backfill and
  /// what keeps a newly tracked event on the rail without a second tap. Gated
  /// by [_ruleHasManyOccurrences] like [_tracksPresence]: the membership
  /// predicate excludes one-time events whatever this says, so the control
  /// must not offer a choice that cannot take effect.
  bool? _showInDayRail;

  /// Whether the calendar is actually drawing a rail, read once with the
  /// sheet's other settings.
  ///
  /// The control is gated on this as well as on [_ruleHasManyOccurrences], for
  /// the same reason: the rail is off by default, so without it every editor
  /// would carry a labelled tri-state plus a hint for a channel that paints
  /// nothing anywhere in the app. A stored override survives the rail being
  /// switched off — it is simply not offered while it cannot take effect.
  bool _dayRailEnabled = false;

  /// The cancelled days the user is editing (**v30**), or `null` while they
  /// have not opened the picker.
  ///
  /// Draft state: nothing is written until Save, and `null` is what tells the
  /// page to leave the skip table alone entirely. Seeded from the facade on
  /// first open rather than in `initState`, so an event with no skips costs
  /// nothing.
  Set<DateTime>? _skippedDays;

  /// Whether the event keeps one description per occurrence instead of one
  /// shared by every day, with its own description as the template each day
  /// starts from. Gated by [_ruleHasManyOccurrences] like [_tracksPresence] —
  /// an event that fires once has nothing to separate.
  ///
  /// Draft state, not the saved row: the scope control below reads it through
  /// [_scopeGateOpen], so flipping the switch reveals or hides that control
  /// immediately instead of only after Save.
  bool _perOccurrenceDescriptions = false;

  /// Label shape for counted occurrences: numbered ("Day 1", start day is
  /// the first) or elapsed ("30 years", the birthday/anniversary style).
  OccurrenceCountStyle _countStyle = OccurrenceCountStyle.numbered;

  /// Whether the user has explicitly picked a count style here. Until they
  /// do, the style follows the frequency's natural default and re-resolves
  /// when the frequency changes — the same "only re-anchor an implicit
  /// default" rule [_pickDate] applies to the weekday set.
  bool _countStyleTouched = false;

  /// Natural count style for [kind].
  ///
  /// Yearly is **elapsed**: a yearly counted event is an anniversary, and an
  /// anniversary is measured in elapsed time. Numbering it instead is off by
  /// one against how everyone reads a birthday — someone born in 2000 has
  /// their 27th *occurrence* in 2026, but they turn 26, so "Year 27" reads
  /// as a mistake even though it counts correctly. Shorter cadences keep
  /// numbering, where "Day 1 / Week 3" is exactly the training-program
  /// reading people want.
  static OccurrenceCountStyle _defaultCountStyleFor(RepeatKind kind) {
    return kind == RepeatKind.yearly
        ? OccurrenceCountStyle.elapsed
        : OccurrenceCountStyle.numbered;
  }

  /// Time-of-day state. The trio is the editor's working copy of the
  /// model's [EventTime]; it's serialized back into one on save.
  ///
  /// - `_isAllDay = true`  → [_startMinute] / [_durationMinutes] are
  ///   ignored (kept around so toggling back doesn't lose the previous
  ///   pick).
  /// - `_isAllDay = false` → [_startMinute] is the start;
  ///   [_durationMinutes] is null (no end) or positive.
  late bool _isAllDay;
  late int _startMinute;
  int? _durationMinutes;

  /// Linked workout note state. [_noteId] is the only value persisted onto
  /// the event; [_noteTitle] is a display cache resolved on open / pick and
  /// [_noteMissing] is set when the previously-linked note no longer exists
  /// (deleted) so the tile can surface that instead of a blank title.
  String? _noteId;
  String? _noteTitle;
  bool _noteMissing = false;

  /// Optional per-event color override (32-bit ARGB). `null` = use the
  /// category color. [_tintIcon] decides whether it also tints the icon.
  int? _colorValue;
  bool _tintIcon = true;

  /// Display priority in `[kMinEventPriority, kMaxEventPriority]`.
  int _priority = kDefaultEventPriority;

  /// Extra one-off dates for a one-time event (date-only UTC, sorted, never
  /// containing [_date]). When non-empty, the event saves as a
  /// [SpecificDatesRecurrence] covering [_date] plus these dates.
  late List<DateTime> _additionalDates;

  /// Today, read once: the bundled Dates row counts the dates still ahead on
  /// every build, and a modal form does not straddle midnight.
  late final DateTime _today = _normalize(DateTime.now());

  /// Whether the description field is showing its rendered markdown instead
  /// of the raw source. View-only state — the stored value is always source.
  /// Only reachable while live rendering is off: with it on, the editor
  /// already *is* the preview and a second read-only mode is dead weight.
  bool _descriptionPreview = false;

  /// Mirrors [_descriptionFocus], so the markdown bar's presence is driven by
  /// a rebuild rather than by reading the focus node during layout.
  bool _descriptionFocused = false;

  /// Global "live markdown rendering" setting, honoured here so the
  /// description reads the same way the note editor does. Resolved after the
  /// first frame; the flip is applied with a repaint nudge, never a remount
  /// (remounting a CodeEditor mid-initialization crashes re_editor's
  /// controller-delegate handoff).
  bool _liveMarkdownRendering = SettingsKeys.defaultLiveMarkdownRendering;

  /// Character budget for the description (Calendar Settings). Enforced by
  /// blocking Save, never by truncating — the description is markdown the
  /// user typed, and silently dropping its tail is the one outcome worse
  /// than refusing to save.
  int _descriptionLimit = SettingsKeys.defaultEventDescriptionLimit;

  /// Lengths the two descriptions had when the sheet opened. An event written
  /// under a larger budget stays editable after the limit is lowered: the
  /// guard blocks *growing* past the limit, so nobody is locked out of an
  /// event they already have. Tracked per scope — a grandfathered template
  /// must not license an unrelated over-limit day override.
  late final int _initialTemplateLength;
  late final int _initialDayLength;

  /// Which description the field is showing. The controller always holds the
  /// active scope's text; the inactive one lives in its buffer below.
  _DescriptionScope _scope = _DescriptionScope.allDays;

  /// The inactive scope's text. Only one of these is live at a time — the
  /// other mirrors the controller. Buffering in plain strings rather than
  /// swapping controllers is deliberate: [ModernEditorWrapper] binds its
  /// listener in `initState` with no `didUpdateWidget`, so a second controller
  /// would orphan that listener (and the span builder, and the search
  /// controller) and drag re_editor through a delegate handoff nothing else
  /// in this app exercises.
  String _templateBuffer = '';
  String _dayBuffer = '';

  /// Whether [widget.occurrenceDay] already had a stored override when the
  /// sheet opened. Decides whether saving an unchanged day scope still writes
  /// a row (it does — the row already existed) or writes nothing.
  bool _dayMaterialized = false;

  /// Set by the "reset to template" action: save then *deletes* the day's
  /// row rather than writing text, which is the only way back once a day has
  /// been materialized.
  bool _dayResetRequested = false;

  /// The day text as the reset left it. The request stands while the day scope
  /// still holds exactly this, and is outranked once the user types something
  /// else there. Compared against the snapshot rather than the *current*
  /// template so that editing the template afterwards still deletes the row —
  /// a reset day should follow the new template, not be pinned to the old one.
  String _dayResetBaseline = '';

  /// Resolved markdown colour palette for the description preview, so
  /// `{name:text}` runs show the user's custom colours.
  MarkdownColorPalette _colorPalette = MarkdownColorPalette.presets;

  /// The event's alerts as the sheet is editing them (**v40**).
  ///
  /// Draft state like the skip set: nothing is written here, the list rides
  /// the result and `CalendarBloc` persists it through
  /// `EventAlertService.replaceForEvent`. Seeded from the synchronous
  /// [EventAlerts] facade for an existing event, and from the Calendar-settings
  /// default for a new one — which arrives with [_loadSheetSettings], after
  /// the first frame.
  List<EventAlert> _alerts = const [];

  /// Whether the user has added, edited or removed an alert themselves. The
  /// asynchronous seed below only fires while this is false, so a default
  /// landing late can never overwrite a choice already made.
  bool _alertsTouched = false;

  /// Draft state for `CalendarEvent.removeAfterAlert` (**A3**). Meaningless
  /// unless the event is one-time and carries an alarm, and cleared on save in
  /// that case — the same shape [_assumeAbsent] follows.
  bool _removeAfterAlert = false;

  TimedAlertDefault? _timedAlertDefault;
  AllDayAlertDefault? _allDayAlertDefault;

  bool get _isEditing => widget.initialEvent != null;

  /// Whether the event fires on exactly one day, which is the only shape
  /// "remove after it rings" can mean anything on: deleting a weekly event
  /// because Monday rang would take Wednesday and Friday with it.
  bool get _isOneTimeEvent =>
      _mode == _RepeatMode.oneTime && _additionalDates.isEmpty;

  bool get _hasAlarmAlert => _alerts.any((alert) => alert.isAlarm);

  /// A stand-in event carrying the one property [EventAlert.describe] reads —
  /// the derived `allDay` — as the *form* currently has it.
  ///
  /// Built rather than taken from `widget.initialEvent` on purpose: toggling
  /// All day has to re-describe every alert row immediately, and the saved
  /// event still says what it said when the sheet opened.
  CalendarEvent get _alertPreviewEvent => CalendarEvent(
    id: widget.initialEvent?.id ?? '',
    title: '',
    categoryId: _categoryId,
    startDate: _date,
    rule: const OneTimeRecurrence(),
    time: _isAllDay ? null : EventTime(startMinute: _startMinute),
  );

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
    _descriptionScroll = CodeScrollController();
    _descriptionSearch = ReEditorSearchController()
      ..initialize(_descriptionController);
    _categoryId = initial?.categoryId ?? kDefaultCategoryId;
    _iconKey = initial?.iconKey;
    _date = _normalize(initial?.startDate ?? widget.defaultDate);
    _endDate = initial?.endDate == null ? null : _normalize(initial!.endDate!);
    final initialTime = initial?.time;
    _isAllDay = initialTime == null;
    _startMinute = initialTime?.startMinute ?? _defaultStartMinute;
    _durationMinutes = initialTime?.durationMinutes;
    _noteId = initial?.noteId;
    _colorValue = initial?.colorValue;
    _tintIcon = initial?.tintIcon ?? true;
    _priority = initial?.priority ?? kDefaultEventPriority;
    _retroactive = initial?.retroactive ?? false;
    _countOccurrences = initial?.countOccurrences ?? false;
    _tracksPresence = initial?.tracksPresence ?? false;
    _assumeAbsent = initial?.assumeAbsent ?? false;
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
        : List<EventAlert>.of(EventAlerts.alertsFor(initial.id));
    _removeAfterAlert = initial?.removeAfterAlert ?? false;
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
    _bodyScroll.addListener(_onBodyScroll);
    _snapBack = AnimationController(vsync: this, duration: _snapBackDuration)
      ..addListener(_onSnapBackTick);
    _initialFingerprint = _fingerprint();
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
    _bodyScroll.removeListener(_onBodyScroll);
    _bodyScroll.dispose();
    _headerScrolled.dispose();
    _descriptionController.removeListener(_relayDescriptionChange);
    _descriptionController.dispose();
    _descriptionRevision.dispose();
    _descriptionFocus.dispose();
    _descriptionScroll.dispose();
    _descriptionSearch.dispose();
    _snapBack.dispose();
    _dragOffset.dispose();
    super.dispose();
  }

  /// Republishes a controller notification on [_descriptionRevision], moving
  /// it out of the build phase when it arrives during one. See that field for
  /// why a direct listener is unsafe here.
  void _relayDescriptionChange() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    final duringFrame =
        phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;
    if (!duringFrame) {
      _descriptionRevision.value++;
      return;
    }
    if (_revisionBumpScheduled) return;
    _revisionBumpScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revisionBumpScheduled = false;
      if (mounted) _descriptionRevision.value++;
    });
  }

  void _onDescriptionFocusChanged() {
    final hasFocus = _descriptionFocus.hasFocus;
    if (hasFocus == _descriptionFocused || !mounted) return;
    setState(() => _descriptionFocused = hasFocus);
    if (hasFocus) _revealDescription();
  }

  /// Scrolls the description into view when it takes focus. A CodeEditor is
  /// not an [EditableText], so nothing does this automatically, and the field
  /// sits far enough down the form that the rising keyboard would otherwise
  /// cover the line being typed. The delay lets the keyboard inset and the
  /// markdown bar settle first, so the target rect is the final one.
  void _revealDescription() {
    Future.delayed(const Duration(milliseconds: 320), () {
      if (!mounted || !_descriptionFocus.hasFocus) return;
      final target = _descriptionKey.currentContext;
      if (target == null || !target.mounted) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.5,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  /// Restyles one description line, exactly as the note editor does.
  /// Unhandled lines (and every line while live rendering is off) fall back
  /// to the ghost-text builder, which leaves a line without a `{{ … }}` run
  /// as re_editor's own span — the same routing
  /// [EditorRenderController.buildSpan] does for the note editor, so a ghost
  /// never renders raw on one surface and concealed on another.
  TextSpan _buildDescriptionSpan({
    required BuildContext context,
    required int index,
    required CodeLine codeLine,
    required TextSpan textSpan,
    required TextStyle style,
  }) {
    final render = _descriptionRenderContext.of(Theme.of(context), style);
    if (_liveMarkdownRendering) {
      final span = _descriptionSpanBuilder.build(
        context: render,
        index: index,
        codeLine: codeLine,
      );
      if (span != null) return span;
    }
    return EditorRenderController.ghostSpan(
      codeLine: codeLine,
      textSpan: textSpan,
      style: style,
      baseColor: render.baseColor,
    );
  }

  // --- Pure helpers -------------------------------------------------------

  DateTime _normalize(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  void _blur() => FocusManager.instance.primaryFocus?.unfocus();

  RecurrenceRule _buildRule() {
    if (_mode == _RepeatMode.oneTime) {
      if (_additionalDates.isEmpty) return const OneTimeRecurrence();
      return SpecificDatesRecurrence(
        dates: Set.unmodifiable(<DateTime>{_date, ..._additionalDates}),
      );
    }
    return switch (_kind) {
      RepeatKind.daily => DailyRecurrence(interval: _interval),
      RepeatKind.weekly => WeeklyRecurrence(
        weekdays: Set.unmodifiable(_weekdays),
        interval: _interval,
      ),
      RepeatKind.monthly => MonthlyRecurrence(interval: _interval),
      RepeatKind.yearly => YearlyRecurrence(interval: _interval),
      RepeatKind.workdays => const WorkdaysRecurrence(),
      RepeatKind.weekends => const WeekendsRecurrence(),
      RepeatKind.holidays => const PublicHolidaysOnlyRecurrence(),
    };
  }

  String _countStyleLabel(AppLocalizations l10n, OccurrenceCountStyle style) {
    return switch (style) {
      OccurrenceCountStyle.numbered => l10n.eventCountStyleNumbered,
      OccurrenceCountStyle.elapsed => l10n.eventCountStyleElapsed,
    };
  }

  /// Labels for the **first three occurrences** under the current kind and
  /// style ("Day 1 · Day 2 · Day 3" against "0 years · 1 year · 2 years"),
  /// so the counting origin — the entire difference between the two styles —
  /// is visible before saving rather than discovered on the calendar.
  String _countStyleExample(AppLocalizations l10n) {
    String at(int n) {
      return switch (_countStyle) {
        OccurrenceCountStyle.numbered => switch (_kind) {
          RepeatKind.daily => l10n.eventNumberedDays(n),
          RepeatKind.weekly => l10n.eventNumberedWeeks(n),
          RepeatKind.monthly => l10n.eventNumberedMonths(n),
          RepeatKind.yearly => l10n.eventNumberedYears(n),
          _ => '',
        },
        OccurrenceCountStyle.elapsed => switch (_kind) {
          RepeatKind.daily => l10n.eventElapsedDays(n),
          RepeatKind.weekly => l10n.eventElapsedWeeks(n),
          RepeatKind.monthly => l10n.eventElapsedMonths(n),
          RepeatKind.yearly => l10n.eventElapsedYears(n),
          _ => '',
        },
      };
    }

    final first = _countStyle == OccurrenceCountStyle.numbered ? 1 : 0;
    return '${at(first)} · ${at(first + 1)} · ${at(first + 2)}';
  }

  bool get _canSave {
    if (_titleController.text.trim().isEmpty) return false;
    if (_mode == _RepeatMode.recurring &&
        _kind == RepeatKind.weekly &&
        _weekdays.isEmpty) {
      return false;
    }
    // Both scopes, not just the visible one: text parked in the inactive
    // buffer is still about to be saved, so checking only the live controller
    // would let an over-limit day override through from the template view.
    if (!_withinLimit(_templateText, _initialTemplateLength)) return false;
    if (_scopeControlVisible && !_withinLimit(_dayText, _initialDayLength)) {
      return false;
    }
    return true;
  }

  /// Whether [text] may be saved at its current length. Over the limit is
  /// allowed only while it is no longer than it already was, so lowering the
  /// setting blocks growth instead of locking the user out.
  bool _withinLimit(String text, int grandfathered) =>
      text.length <= _descriptionLimit || text.length <= grandfathered;

  /// Whether the *active* scope is within its own budget — what the counter
  /// and the over-limit hint report.
  bool get _activeScopeWithinLimit => _scope == _DescriptionScope.thisDay
      ? _withinLimit(_dayText, _initialDayLength)
      : _withinLimit(_templateText, _initialTemplateLength);

  /// The template's current text — from the controller when it is the active
  /// scope, otherwise from its buffer.
  String get _templateText => _scope == _DescriptionScope.allDays
      ? _descriptionController.text
      : _templateBuffer;

  /// This day's current text, same rule as [_templateText].
  String get _dayText => _scope == _DescriptionScope.thisDay
      ? _descriptionController.text
      : _dayBuffer;

  /// Whether the rule the form currently describes has more than one
  /// occurrence. Equivalent to `_buildRule() is! OneTimeRecurrence` without
  /// building a rule object on every frame — `_mode == oneTime` with extra
  /// dates is a `SpecificDatesRecurrence`, which *is* multi-occurrence.
  bool get _ruleHasManyOccurrences =>
      _mode == _RepeatMode.recurring || _additionalDates.isNotEmpty;

  /// Whether the form currently describes an event whose days are separable:
  /// a rule with more than one occurrence, opted into per-occurrence
  /// descriptions. Read from the draft flag rather than the saved row, so the
  /// switch takes effect the moment it is flipped.
  bool get _scopeGateOpen =>
      _ruleHasManyOccurrences && _perOccurrenceDescriptions;

  /// Whether to offer the "this day / all days" control.
  ///
  /// Requires a saved event (a new one has no id until `_onSave`), an
  /// occurrence to scope to (the FAB path has none), and an open scope gate.
  /// Flipping the form to one-time — or the switch off — mid-edit hides it,
  /// see [_syncScopeToRule].
  bool get _scopeControlVisible =>
      _isEditing && widget.occurrenceDay != null && _scopeGateOpen;

  /// Moves the field between the template and this day's text.
  ///
  /// One controller throughout — only its content changes. The swap goes
  /// through `loadText`, never `set text`: a revocable write would let the
  /// toolbar's undo pull the *other* scope's text into the active one, and
  /// Save would persist it.
  void _setScope(_DescriptionScope next) {
    if (next == _scope) return;
    if (_scope == _DescriptionScope.allDays) {
      _templateBuffer = _descriptionController.text;
    } else {
      _dayBuffer = _descriptionController.text;
    }
    setState(() {
      _scope = next;
      _descriptionController.loadText(
        next == _DescriptionScope.thisDay ? _dayBuffer : _templateBuffer,
      );
      _descriptionEdits.syncLength();
    });
  }

  /// Returns this day to the template. Deleting the row is the only way back
  /// once a day has been materialized, so it is an explicit action rather
  /// than something inferred from the text matching again.
  void _resetDayToTemplate() {
    setState(() {
      _dayResetRequested = true;
      _dayBuffer = _templateText;
      _dayResetBaseline = _dayBuffer;
      if (_scope == _DescriptionScope.thisDay) {
        _descriptionController.loadText(_dayBuffer);
        _descriptionEdits.syncLength();
      }
    });
  }

  /// Drops back to the template scope when the form stops describing separable
  /// days — the rule is no longer repeating, or the per-day switch went off —
  /// so the field can never show a day's text while the control that explains
  /// it is hidden. The day buffer is kept in memory and simply not written:
  /// closing the gate must not silently merge one occurrence's text into the
  /// template.
  void _syncScopeToRule() {
    if (_scopeGateOpen || _scope == _DescriptionScope.allDays) return;
    _dayBuffer = _descriptionController.text;
    _scope = _DescriptionScope.allDays;
    _descriptionController.loadText(_templateBuffer);
    _descriptionEdits.syncLength();
  }

  // --- Interactions -------------------------------------------------------

  Future<void> _pickDate() async {
    _blur();
    // The shared domain, not a window around the current date: a birthday's
    // start is the birth year, which a ±20-year slide could never reach.
    final picked = await CalendarDatePickerSheet.pickSingle(
      context,
      initialDate: _date,
      firstDate: CalendarBounds.earliest,
      lastDate: CalendarBounds.latest,
      dayLoad: widget.dayLoad,
      appearance: widget.appearance,
    );
    if (picked == null || !mounted) return;
    setState(() {
      final next = _normalize(picked);
      // Keep the weekday selection in sync when it was implicitly anchored
      // to the previous date (single weekday matching old _date.weekday).
      if (_kind == RepeatKind.weekly &&
          _weekdays.length == 1 &&
          _weekdays.first == _date.weekday) {
        _weekdays = {next.weekday};
      }
      _date = next;
      // A new primary date must never also live in the extra-dates list.
      _additionalDates = _additionalDates.where((d) => d != next).toList();
      // If the recurrence end is now before the new start, drop it rather
      // than silently producing an event that never occurs.
      if (_endDate != null && _endDate!.isBefore(next)) {
        _endDate = null;
      }
    });
  }

  /// The cancelled days currently in play: the draft once the picker has been
  /// opened, otherwise whatever is persisted.
  Set<DateTime> get _effectiveSkippedDays =>
      _skippedDays ?? EventSkips.daysFor(widget.initialEvent?.id ?? '');

  /// Reviews and edits the cancelled days as a set.
  ///
  /// `pickMulti` is exactly the right control here and needs no new UI: it is
  /// semantics-free, it already shows which days are busy, and un-skipping is
  /// just deselecting. Nothing is written until Save.
  Future<void> _pickSkippedDays() async {
    _blur();
    final picked = await CalendarDatePickerSheet.pickMulti(
      context,
      initialSelection: _effectiveSkippedDays,
      firstDate: CalendarBounds.earliest,
      lastDate: CalendarBounds.latest,
      dayLoad: widget.dayLoad,
      appearance: widget.appearance,
      allowEmpty: true,
    );
    if (picked == null || !mounted) return;
    setState(() => _skippedDays = {for (final d in picked) _normalize(d)});
  }

  /// Applies an Assume present / Assume absent pick, seeding the from-date the
  /// first time an existing event is flipped over.
  ///
  /// The seed is the day the editor was opened from — the occurrence whose
  /// detail sheet the user came through — falling back to today. It only fires
  /// for an event that was **saved** as assume-present: an event already on
  /// the inverted default keeps whatever boundary it has, including none, so
  /// toggling back and forth inside one session cannot invent one.
  ///
  /// Must run inside a `setState`; the caller owns that.
  void _selectAssumeAbsent(bool value) {
    _assumeAbsent = value;
    if (!value) return;
    if (_isEditing &&
        widget.initialEvent!.assumeAbsent == false &&
        _assumeAbsentFrom == null &&
        !_assumeAbsentFromTouched) {
      _assumeAbsentFrom = _normalize(widget.occurrenceDay ?? DateTime.now());
    }
  }

  /// Picks the day the inverted presence default starts from (**v37**).
  ///
  /// Single-date, [_pickEndDate]'s argument set, and the result goes through
  /// [_normalize] like every other date this form holds — the boundary is
  /// compared against date-only UTC days on every read path. Nothing is
  /// written until Save.
  Future<void> _pickAssumeAbsentFrom() async {
    _blur();
    final picked = await CalendarDatePickerSheet.pickSingle(
      context,
      initialDate: _assumeAbsentFrom ?? _date,
      firstDate: CalendarBounds.earliest,
      // A boundary past the last occurrence would leave "Assume absent"
      // selected with no day it could ever apply to.
      lastDate:
          (_mode == _RepeatMode.recurring ? _endDate : null) ??
          CalendarBounds.latest,
      dayLoad: widget.dayLoad,
      appearance: widget.appearance,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _assumeAbsentFrom = _normalize(picked);
      _assumeAbsentFromTouched = true;
    });
  }

  /// Edits the whole one-time date set in a single pass. The multi picker
  /// returns the edited set; [_setOneTimeDates] stays the one place that
  /// re-derives the anchor (earliest) and the extras list from it.
  Future<void> _pickOneTimeDates({
    CalendarDatePickerView view = CalendarDatePickerView.month,
  }) async {
    _blur();
    final current = <DateTime>{_date, ..._additionalDates};
    final picked = await CalendarDatePickerSheet.pickMulti(
      context,
      initialSelection: current,
      firstDate: CalendarBounds.earliest,
      lastDate: CalendarBounds.latest,
      dayLoad: widget.dayLoad,
      appearance: widget.appearance,
      initialView: view,
    );
    if (picked == null || !mounted || picked.isEmpty) return;
    _setOneTimeDates(picked);
  }

  void _removeOneTimeDate(DateTime date) {
    final next = <DateTime>{_date, ..._additionalDates}..remove(date);
    if (next.isEmpty) return;
    _setOneTimeDates(next);
  }

  /// Re-derives [_date] (earliest) and [_additionalDates] (the rest) from a
  /// full one-time date set so the chip list always reads as one uniform,
  /// sorted collection with the earliest auto-anchoring the event.
  void _setOneTimeDates(Set<DateTime> dates) {
    final sorted = dates.toList()..sort();
    setState(() {
      _date = sorted.first;
      _additionalDates = sorted.skip(1).toList();
      // Dropping back to a single date makes this a one-time event, which has
      // no occurrences to scope to.
      _syncScopeToRule();
    });
  }

  Future<void> _pickStartTime() async {
    _blur();
    final l10n = AppLocalizations.of(context)!;
    final duration = _durationMinutes;
    final picked = await TimePadSheet.pick(
      context,
      initialMinute: _startMinute,
      title: l10n.eventStartTime,
      caption: duration == null
          ? null
          : TimePadCaptions.endsAfter(l10n, duration),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final newStart = picked;
      // Preserve the visible duration: if a duration is set, keep the
      // *length* (so "1 hour" stays "1 hour"). This is what every native
      // calendar app does when you drag the start time.
      _startMinute = newStart;
    });
  }

  Future<void> _pickEndTime() async {
    _blur();
    // Initialize the picker on the current end time, or one hour after
    // start if no end is set yet.
    final currentEnd = _durationMinutes == null
        ? null
        : _startMinute + _durationMinutes!;
    final initial = currentEnd ?? (_startMinute + _defaultDurationMinutes);
    final clamped = initial % EventTime.minutesPerDay;
    final l10n = AppLocalizations.of(context)!;
    final picked = await TimePadSheet.pick(
      context,
      initialMinute: clamped,
      title: l10n.eventEndTime,
      periodAfter: _startMinute,
      caption: TimePadCaptions.afterStart(l10n, _startMinute),
    );
    if (picked == null || !mounted) return;
    final endMinute = picked;
    setState(() {
      // If user picks an end ≤ start, treat it as next-day (cross-midnight).
      // This is the only sane interpretation when the picker has no day
      // concept; the model and formatter both handle it.
      var duration = endMinute - _startMinute;
      if (duration <= 0) duration += EventTime.minutesPerDay;
      _durationMinutes = duration;
    });
  }

  void _clearEndTime() {
    setState(() => _durationMinutes = null);
  }

  void _setAllDay(bool value) {
    setState(() {
      _isAllDay = value;
      // Toggling on: keep _startMinute / _durationMinutes around so a
      // mistaken toggle is reversible. Toggling off: nothing to do — the
      // existing values become live again.
    });
  }

  /// Gives a brand-new event the alert the Calendar settings say it should
  /// start with (§5.1). Runs inside [_loadSheetSettings]'s `setState`.
  ///
  /// Three guards, each closing a way the seed could be a lie: an existing
  /// event's alerts are its own, a user who already added one has said what
  /// they want, and a default of `none` means new events get nothing at all.
  void _seedDefaultAlert() {
    if (_isEditing || _alertsTouched || _alerts.isNotEmpty) return;
    final hasDefault = _isAllDay
        ? _allDayAlertDefault != null
        : _timedAlertDefault != null;
    if (!hasDefault) return;
    _alerts = [
      AlertEditorSheet.draft(
        eventId: '',
        allDay: _isAllDay,
        timedDefault: _timedAlertDefault,
        allDayDefault: _allDayAlertDefault,
      ),
    ];
  }

  /// Opens the alert sheet on a brand-new alert, and keeps it only if the user
  /// saves. Never offers Remove there: closing the sheet already means "no".
  Future<void> _addAlert() async {
    _blur();
    if (_alerts.length >= kMaxAlertsPerEvent) return;
    final draft = AlertEditorSheet.draft(
      eventId: widget.initialEvent?.id ?? '',
      allDay: _isAllDay,
      timedDefault: _timedAlertDefault,
      allDayDefault: _allDayAlertDefault,
    );
    final result = await AlertEditorSheet.show(
      context,
      alert: draft,
      event: _alertPreviewEvent,
      canRemove: false,
      showRemoveAfter: _isOneTimeEvent,
      removeAfterAlert: _removeAfterAlert,
    );
    if (!mounted) return;
    switch (result) {
      case null:
      case AlertEditorRemoved():
        return;
      case AlertEditorSaved(:final alert, :final removeAfterAlert):
        setState(() {
          _alertsTouched = true;
          _alerts = [..._alerts, alert];
          if (_isOneTimeEvent) _removeAfterAlert = removeAfterAlert;
        });
    }
  }

  Future<void> _editAlert(EventAlert alert) async {
    _blur();
    final result = await AlertEditorSheet.show(
      context,
      alert: alert,
      event: _alertPreviewEvent,
      showRemoveAfter: _isOneTimeEvent,
      removeAfterAlert: _removeAfterAlert,
    );
    if (!mounted || result == null) return;
    setState(() {
      _alertsTouched = true;
      switch (result) {
        case AlertEditorRemoved():
          _alerts = [
            for (final a in _alerts)
              if (a.id != alert.id) a,
          ];
        case AlertEditorSaved(:final alert, :final removeAfterAlert):
          _alerts = [
            for (final existing in _alerts)
              if (existing.id == alert.id) alert else existing,
          ];
          if (_isOneTimeEvent) _removeAfterAlert = removeAfterAlert;
      }
    });
  }

  void _removeAlert(EventAlert alert) {
    setState(() {
      _alertsTouched = true;
      _alerts = [
        for (final a in _alerts)
          if (a.id != alert.id) a,
      ];
    });
  }

  Future<void> _loadSheetSettings() async {
    final settings = await SettingsService.getInstance();
    final palette = await settings.getColorPalette();
    final liveRendering = await settings.getLiveMarkdownRendering();
    final descriptionLimit = await settings.getEventDescriptionLimit();
    final railStyle = await settings.getCalendarDayRailStyle();
    final alertSettings = await settings.getAlertSettings();
    if (!mounted) return;
    // Both reach the editor surface non-destructively: the span memos are
    // cleared and re_editor is nudged to rebuild its display paragraphs.
    // Money stays disabled (the builder's default) — the ledger is a
    // per-note concept, so `$` rows in a description are literal text.
    _descriptionSpanBuilder.configureColors(palette);
    final rerender =
        palette != _colorPalette || liveRendering != _liveMarkdownRendering;
    final wasClean = !_isDirty;
    setState(() {
      _colorPalette = palette;
      _liveMarkdownRendering = liveRendering;
      _descriptionLimit = descriptionLimit;
      _dayRailEnabled = railStyle != DayRailStyle.none;
      _timedAlertDefault = alertSettings.timedDefault;
      _allDayAlertDefault = alertSettings.allDayDefault;
      _seedDefaultAlert();
    });
    if (wasClean) _initialFingerprint = _fingerprint();
    if (rerender) {
      _descriptionController.forceRepaint();
      _relayDescriptionChange();
    }
  }

  Future<void> _pickCategory() async {
    _blur();
    final picked = await CategoryPickerSheet.pickSingle(
      context,
      selectedId: _categoryId,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _categoryId = picked;
      // Birthdays are inherently yearly. When the user tags a brand-new,
      // still-one-time event as a birthday, pre-fill a yearly recurrence so it
      // repeats every year with no extra taps. A recurrence the user already
      // configured is left untouched.
      if (picked == kBirthdayCategoryId && _mode == _RepeatMode.oneTime) {
        _mode = _RepeatMode.recurring;
        _kind = RepeatKind.yearly;
        // Birthdays are the canonical occurrence-count use: with the birth
        // date as start, every occurrence shows the age. Pre-filled only on
        // the same fresh-event path as the yearly rule above; the style
        // follows yearly's default unless the user already chose one.
        _countOccurrences = true;
        if (!_countStyleTouched) {
          _countStyle = _defaultCountStyleFor(RepeatKind.yearly);
        }
      }
    });
  }

  /// Resolve the display title for the currently linked note. If the note
  /// no longer exists — hard-deleted or soft-deleted — flag it so the tile
  /// shows a "missing" state instead of a blank label. The stale id is kept
  /// until the user explicitly removes or replaces the link.
  ///
  /// Uses [NoteRepository.getNotesByIds] rather than `getNoteById` because
  /// only the former filters out soft-deleted notes (the app deletes notes
  /// soft), so a deleted note correctly reads as missing here.
  Future<void> _loadLinkedNoteTitle() async {
    final id = _noteId;
    if (id == null) return;
    final notes = await GetIt.I<NoteRepository>().getNotesByIds([id]);
    if (!mounted) return;
    final note = notes.isEmpty ? null : notes.first;
    setState(() {
      if (note == null) {
        _noteMissing = true;
        _noteTitle = null;
      } else {
        _noteMissing = false;
        _noteTitle = note.title;
      }
    });
  }

  Future<void> _pickNote() async {
    _blur();
    final picked = await showNotePickerDialog(context);
    if (picked == null || !mounted) return;
    setState(() {
      _noteId = picked.id;
      _noteTitle = picked.title;
      _noteMissing = false;
    });
  }

  void _clearNote() {
    setState(() {
      _noteId = null;
      _noteTitle = null;
      _noteMissing = false;
    });
  }

  /// Captures the current form as a reusable template.
  ///
  /// Opens the template editor pre-filled rather than saving silently: the
  /// template needs a name of its own (the event's title is only a default),
  /// and seeing the captured fields before they are stored is what makes the
  /// action trustworthy. The event form is left untouched and the sheet stays
  /// open — this is a side action, not a save.
  ///
  /// Persisting goes straight through `EventTemplateService`, the same
  /// service-direct pattern `CategoryPickerSheet`'s inline create already uses
  /// from inside this sheet, so no result-type plumbing is involved.
  Future<void> _onSaveAsTemplate() async {
    _blur();
    final title = _titleController.text.trim();
    if (title.isEmpty) return;
    final description = _templateText.trim();
    // A template carries no dates, so a multi-date one-time event collapses
    // to a plain one-time rule; the same repeat-only guards as `_onSave`
    // otherwise apply, and the template editor re-applies them on its save.
    final rule = _mode == _RepeatMode.recurring
        ? _buildRule()
        : const OneTimeRecurrence();
    final draft = EventTemplate(
      id: '',
      name: title,
      categoryId: _categoryId,
      rule: rule,
      time: _isAllDay
          ? null
          : EventTime(
              startMinute: _startMinute,
              durationMinutes: _durationMinutes,
            ),
      description: description.isEmpty ? null : description,
      iconKey: _iconKey,
      colorValue: _colorValue,
      tintIcon: _tintIcon,
      priority: _priority,
      retroactive: _mode == _RepeatMode.recurring && _retroactive,
      countOccurrences:
          _mode == _RepeatMode.recurring &&
          _kind.supportsInterval &&
          _countOccurrences,
      countStyle: _countStyle,
      tracksPresence: _ruleHasManyOccurrences && _tracksPresence,
      assumeAbsent: _ruleHasManyOccurrences && _tracksPresence && _assumeAbsent,
      perOccurrenceDescriptions:
          _ruleHasManyOccurrences && _perOccurrenceDescriptions,
    );

    final saved = await EventTemplateEditorSheet.show(context, draft: draft);
    if (saved == null || !mounted) return;
    CustomSnackbar.showSuccess(
      context,
      AppLocalizations.of(context)!.templateSaved,
    );
  }

  void _onSave() {
    if (!_canSave) return;
    final title = _titleController.text.trim();
    // Always the template, whichever scope the field happens to be showing —
    // `description` on the event row is the shared text by definition.
    final description = _templateText.trim();
    final effectiveDescription = description.isEmpty ? null : description;
    final base = widget.initialEvent;
    // One-time events ignore endDate — their start date is their end.
    final effectiveEnd = _mode == _RepeatMode.recurring ? _endDate : null;
    // Same guard for the scope flag: an exact-membership rule can never be
    // retroactive, so a one-time event never carries a stale `true`.
    final effectiveRetroactive = _mode == _RepeatMode.recurring && _retroactive;
    // And for the occurrence count: only periodic kinds have a unit to count
    // in, so kind switches can never persist a stale `true`.
    final effectiveCountOccurrences =
        _mode == _RepeatMode.recurring &&
        _kind.supportsInterval &&
        _countOccurrences;
    // And for presence: editing a tracked event down to a single day clears
    // the opt-in, exactly as the two flags above do. The absence rows survive
    // untouched, so re-ticking the switch restores every mark.
    final effectiveTracksPresence = _ruleHasManyOccurrences && _tracksPresence;
    // The presence **default** rides the opt-in it qualifies: an untracked
    // event has no unmarked days to reinterpret, so it never persists an
    // inverted default. The from-date only means something while the default
    // is inverted, so it clears with it rather than lingering as a boundary
    // for nothing.
    final effectiveAssumeAbsent = effectiveTracksPresence && _assumeAbsent;
    final effectiveAssumeAbsentFrom = effectiveAssumeAbsent
        ? _assumeAbsentFrom
        : null;
    // The rail override follows the same gate, but resolves to NULL rather
    // than `false` when it closes: NULL is *auto*, so an event edited down to
    // one day and back again returns to following its presence flag instead of
    // carrying a "never" nobody chose.
    final effectiveShowInDayRail = _ruleHasManyOccurrences
        ? _showInDayRail
        : null;
    // Same shape for the per-day descriptions opt-in, and the same guarantee:
    // editing the event down to a single day clears the flag while the
    // occurrence rows survive, so re-ticking the switch brings every day's
    // text back.
    final effectivePerOccurrenceDescriptions =
        _ruleHasManyOccurrences && _perOccurrenceDescriptions;
    final effectiveTime = _isAllDay
        ? null
        : EventTime(
            startMinute: _startMinute,
            durationMinutes: _durationMinutes,
          );
    // A3 rides the same rule its switch is gated on, for the same reason the
    // flags above do: an event edited into a series, or left with nothing that
    // rings, must not keep a promise to delete itself.
    final savedRule = _buildRule();
    final effectiveRemoveAfterAlert =
        _removeAfterAlert && _hasAlarmAlert && savedRule is OneTimeRecurrence;
    // For a multi-date one-time event, anchor the start on the earliest date
    // so ordering / "starts on" reflect the real first occurrence.
    final effectiveStart =
        (_mode == _RepeatMode.oneTime && _additionalDates.isNotEmpty)
        ? <DateTime>{
            _date,
            ..._additionalDates,
          }.reduce((a, b) => a.isBefore(b) ? a : b)
        : _date;
    final event = base == null
        ? CalendarEvent(
            id: const Uuid().v4(),
            title: title,
            categoryId: _categoryId,
            startDate: effectiveStart,
            rule: savedRule,
            endDate: effectiveEnd,
            retroactive: effectiveRetroactive,
            countOccurrences: effectiveCountOccurrences,
            countStyle: _countStyle,
            tracksPresence: effectiveTracksPresence,
            assumeAbsent: effectiveAssumeAbsent,
            assumeAbsentFrom: effectiveAssumeAbsentFrom,
            showInDayRail: effectiveShowInDayRail,
            perOccurrenceDescriptions: effectivePerOccurrenceDescriptions,
            removeAfterAlert: effectiveRemoveAfterAlert,
            time: effectiveTime,
            description: effectiveDescription,
            noteId: _noteId,
            iconKey: _iconKey,
            colorValue: _colorValue,
            tintIcon: _tintIcon,
            priority: _priority,
          )
        : base.copyWith(
            title: title,
            categoryId: _categoryId,
            startDate: effectiveStart,
            rule: savedRule,
            endDate: effectiveEnd,
            retroactive: effectiveRetroactive,
            countOccurrences: effectiveCountOccurrences,
            countStyle: _countStyle,
            tracksPresence: effectiveTracksPresence,
            assumeAbsent: effectiveAssumeAbsent,
            assumeAbsentFrom: effectiveAssumeAbsentFrom,
            showInDayRail: effectiveShowInDayRail,
            perOccurrenceDescriptions: effectivePerOccurrenceDescriptions,
            removeAfterAlert: effectiveRemoveAfterAlert,
            time: effectiveTime,
            description: effectiveDescription,
            noteId: _noteId,
            iconKey: _iconKey,
            colorValue: _colorValue,
            tintIcon: _tintIcon,
            priority: _priority,
            clearShowInDayRail: effectiveShowInDayRail == null,
            clearAssumeAbsentFrom: effectiveAssumeAbsentFrom == null,
            clearEndDate: effectiveEnd == null,
            clearTime: effectiveTime == null,
            clearDescription: effectiveDescription == null,
            clearNoteId: _noteId == null,
            clearIconKey: _iconKey == null,
            clearColorValue: _colorValue == null,
          );
    final (occurrenceDay, occurrenceDescription) = _resolveOccurrenceOutcome(
      description,
    );
    Navigator.of(context).pop(
      EventEditorSaved(
        event,
        occurrenceDay: occurrenceDay,
        occurrenceDescription: occurrenceDescription,
        // Only when the picker was actually opened, and only while the saved
        // rule can still carry skips — editing an event down to a single day
        // must not dispatch skips against a rule that has no occurrences to
        // cancel. The rows survive untouched either way, exactly like the
        // absence and description rows.
        skippedDays: _skippedDays != null && event.rule is! OneTimeRecurrence
            ? _skippedDays
            : null,
        alerts: List<EventAlert>.unmodifiable(_alerts),
      ),
    );
  }

  /// What saving should do to this day's row, as `(day, description)`.
  ///
  /// A null day means "leave the occurrence table alone"; a non-null day with
  /// a null description means "delete that row". The copy-on-write rule lives
  /// here: an untouched day whose text still equals [template] writes nothing,
  /// so a sparse table stays sparse. A day that already had a row keeps it
  /// even when its text matches again — only the explicit reset removes one.
  ///
  /// Returns nothing at all once the scope gate is closed — a rule that no
  /// longer repeats, or the per-day switch turned off: closing it must not
  /// merge an occurrence's text anywhere.
  (DateTime?, String?) _resolveOccurrenceOutcome(String template) {
    final day = widget.occurrenceDay;
    if (day == null || !_isEditing || !_scopeGateOpen) return (null, null);
    final dayText = _dayText.trim();
    // The reset survives a scope switch (which is why it isn't cleared there)
    // and survives editing the template afterwards — the day should follow the
    // *new* shared text, which is what deleting the row achieves. Only typing
    // something else into the day scope outranks it.
    if (_dayResetRequested && dayText == _dayResetBaseline.trim()) {
      return (day, null);
    }
    if (!_dayMaterialized && dayText == template) return (null, null);
    return (day, dayText);
  }

  Future<void> _onDelete() async {
    _blur();
    final base = widget.initialEvent;
    if (base == null) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.deleteEvent),
          content: Text(l10n.deleteEventConfirm(base.title)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.delete),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    Navigator.of(context).pop(EventEditorDeleted(base.id));
  }

  void _onBodyScroll() {
    final scrolled = _bodyScroll.hasClients && _bodyScroll.offset >= 1;
    if (scrolled != _headerScrolled.value) _headerScrolled.value = scrolled;
  }

  int get _descriptionCounterFrom => (_descriptionLimit * 9 / 10).ceil();

  void _setPerOccurrenceDescriptions(bool value) {
    setState(() {
      _perOccurrenceDescriptions = value;
      if (!value) _syncScopeToRule();
    });
    if (!value || !_scopeControlVisible) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _descriptionKey.currentContext;
      if (target == null || !target.mounted) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.5,
        duration: _revealDuration,
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _pickRepeat() async {
    _blur();
    final result = await EventRepeatSheet.show(
      context,
      draft: EventRepeatDraft(
        recurring: _mode == _RepeatMode.recurring,
        kind: _kind,
        interval: _interval,
        weekdays: _weekdays,
        endDate: _endDate,
        retroactive: _retroactive,
      ),
      startDate: _date,
      appearance: widget.appearance,
      dayLoad: widget.dayLoad,
    );
    if (result == null || !mounted) return;
    setState(() {
      _mode = result.recurring ? _RepeatMode.recurring : _RepeatMode.oneTime;
      _kind = result.kind;
      _interval = result.interval.clamp(1, EventRepeatDraft.maxInterval);
      _weekdays = Set<int>.of(result.weekdays);
      _endDate = result.endDate == null ? null : _normalize(result.endDate!);
      _retroactive = result.retroactive;
      if (!_countStyleTouched) _countStyle = _defaultCountStyleFor(_kind);
      _syncScopeToRule();
    });
  }

  /// The bundled row's value: the count and span on the first line, then the
  /// next date and how many are still ahead, so the set reads back without
  /// opening the picker.
  String _datesValue(AppLocalizations l10n, List<DateTime> dates) {
    final summary = CalendarDatePickerSheet.summaryLabel(l10n, dates);
    final ahead = dates.where((d) => !d.isBefore(_today)).toList();
    if (ahead.isEmpty) return '$summary\n${l10n.eventDatesAllPast}';
    final next = l10n.eventDatesNext(
      DateFormat.MMMEd(l10n.localeName).format(ahead.first),
    );
    return '$summary\n$next · ${l10n.eventDatesAhead(ahead.length, dates.length)}';
  }

  String _repeatValue(AppLocalizations l10n) {
    if (_mode == _RepeatMode.oneTime) {
      return _additionalDates.isEmpty
          ? l10n.recurrenceDoesNotRepeat
          : l10n.recurrenceSpecificDates(_additionalDates.length + 1);
    }
    final rule = RecurrenceFormatter.format(
      _buildRule(),
      l10n,
      l10n.localeName,
      retroactive: _retroactive,
    );
    final end = _endDate;
    if (end == null) return rule;
    return l10n.recurrenceUntilSuffix(
      rule,
      DateFormat.yMMMd(l10n.localeName).format(end),
    );
  }

  Future<void> _pickLook() async {
    _blur();
    final result = await EventLookSheet.show(
      context,
      draft: EventLookDraft(
        iconKey: _iconKey,
        colorValue: _colorValue,
        tintIcon: _tintIcon,
      ),
      category: CalendarCategories.resolve(_categoryId),
    );
    if (result == null || !mounted) return;
    setState(() {
      _iconKey = result.iconKey;
      _colorValue = result.colorValue;
      _tintIcon = result.tintIcon;
    });
  }

  String _dayRailLabel(AppLocalizations l10n, _DayRailChoice choice) {
    return switch (choice) {
      _DayRailChoice.auto => l10n.eventShowInDayRailAuto,
      _DayRailChoice.always => l10n.eventShowInDayRailAlways,
      _DayRailChoice.never => l10n.eventShowInDayRailNever,
    };
  }

  String _fingerprint() {
    final weekdays = _weekdays.toList()..sort();
    final skipped = _effectiveSkippedDays.toList()..sort();
    final alerts = _alerts.map((alert) => alert.props.join(',')).join(';');
    return [
      _titleController.text,
      _templateText,
      _dayText,
      _dayResetRequested,
      _categoryId,
      _iconKey,
      _colorValue,
      _tintIcon,
      _date,
      _additionalDates,
      _mode,
      _kind,
      _interval,
      weekdays,
      _endDate,
      _retroactive,
      _isAllDay,
      _startMinute,
      _durationMinutes,
      alerts,
      _removeAfterAlert,
      _countOccurrences,
      _countStyle,
      _tracksPresence,
      _assumeAbsent,
      _assumeAbsentFrom,
      _showInDayRail,
      _perOccurrenceDescriptions,
      skipped,
      _noteId,
      _priority,
    ].join('\u0000');
  }

  bool get _isDirty => _fingerprint() != _initialFingerprint;

  Future<bool> _confirmLeave() async {
    if (!_isDirty) return true;
    final l10n = AppLocalizations.of(context)!;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.unsavedChanges),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.keepEditing),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.discardChanges),
            ),
          ],
        );
      },
    );
    return discard ?? false;
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    try {
      final leave = await _confirmLeave();
      if (!leave || !mounted) return;
      _popDiscarding();
    } finally {
      _leaving = false;
    }
  }

  void _popDiscarding() {
    Navigator.of(context).pop(widget.showBack ? const EventEditorBack() : null);
  }

  void _onDragStart(DragStartDetails details) {
    _snapBack.stop();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _dragOffset.value = math.max(0, _dragOffset.value + details.delta.dy);
  }

  void _onDragCancel() {
    _animateSnapBack();
  }

  Future<void> _onDragEnd(DragEndDetails details) async {
    if (_leaving) {
      await _animateSnapBack();
      return;
    }
    final velocity =
        details.primaryVelocity ?? details.velocity.pixelsPerSecond.dy;
    final height =
        _sheetKey.currentContext?.size?.height ??
        MediaQuery.sizeOf(context).height * _sheetHeightFactor;
    final dismiss =
        velocity > _dismissVelocity || _dragOffset.value > height / 4;
    if (!dismiss) {
      await _animateSnapBack();
      return;
    }
    if (!_isDirty) {
      _popDiscarding();
      return;
    }
    await _animateSnapBack();
    if (!mounted) return;
    await _leave();
  }

  Future<void> _animateSnapBack() async {
    _snapFrom = _dragOffset.value;
    if (_snapFrom == 0) return;
    try {
      await _snapBack.forward(from: 0).orCancel;
    } on TickerCanceled {
      return;
    }
  }

  void _onSnapBackTick() {
    final progress = Curves.easeOut.transform(_snapBack.value);
    _dragOffset.value = _snapFrom * (1 - progress);
  }

  Widget _buildTitleRow(
    AppLocalizations l10n,
    ThemeData theme,
    IconData icon,
    Color accent,
  ) {
    final colorScheme = theme.colorScheme;
    return _IndentedRow(
      dividerIndent: FormMetrics.dividerIndentTitle,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: FormMetrics.titleRowMinHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RowMetrics.groupInset,
            vertical: _titleRowVerticalPadding,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EventAvatar(icon: icon, color: accent),
              const SizedBox(width: FormMetrics.gap),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: _titleTopInset),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AutomationId(
                        identifier: SemanticsIds.eventTitle,
                        child: TextField(
                        controller: _titleController,
                        autofocus: !_isEditing,
                        maxLines: null,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.done,
                        inputFormatters: [
                          FilteringTextInputFormatter.deny('\n'),
                        ],
                        maxLength: _titleMaxLength,
                        buildCounter:
                            (
                              context, {
                              required currentLength,
                              required isFocused,
                              maxLength,
                            }) => null,
                        style: TextStyle(
                          fontSize: _titleFontSize,
                          fontWeight: FontWeight.w500,
                          height: _titleLineHeight,
                          color: colorScheme.onSurface,
                        ),
                        decoration: InputDecoration.collapsed(
                          hintText: l10n.eventTitle,
                          hintStyle: TextStyle(
                            fontSize: _titleFontSize,
                            fontWeight: FontWeight.w400,
                            height: _titleLineHeight,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      ),
                      ListenableBuilder(
                        listenable: _titleController,
                        builder: (context, _) {
                          final length =
                              _titleController.text.characters.length;
                          if (length < _titleCounterFrom) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(
                              top: _counterTopInset,
                            ),
                            child: Text(
                              l10n.eventTitleCount(length, _titleMaxLength),
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: FormMetrics.counterSize,
                                height: 16 / FormMetrics.counterSize,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                                color: length >= _titleMaxLength
                                    ? colorScheme.error
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScopeStrip(AppLocalizations l10n, ThemeData theme) {
    final showReset =
        _scope == _DescriptionScope.thisDay &&
        _dayMaterialized &&
        !_dayResetRequested;
    return SizedBox(
      height: _scopeStripHeight,
      child: Padding(
        padding: const EdgeInsets.only(left: RowMetrics.groupInset, right: 4),
        child: Row(
          children: [
            FormChip(
              label: l10n.eventDescriptionScopeAllDays,
              selected: _scope == _DescriptionScope.allDays,
              tapTarget: _scopeStripHeight,
              onTap: () => _setScope(_DescriptionScope.allDays),
            ),
            const SizedBox(width: FormMetrics.chipSpacing),
            FormChip(
              label: l10n.eventDescriptionScopeThisDay,
              selected: _scope == _DescriptionScope.thisDay,
              tapTarget: _scopeStripHeight,
              onTap: () => _setScope(_DescriptionScope.thisDay),
            ),
            Expanded(
              child: showReset
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _resetDayToTemplate,
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, _scopeStripHeight),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          textStyle: const TextStyle(
                            fontSize: FormMetrics.captionSize,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        child: Text(
                          l10n.eventDescriptionResetDayShort,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          semanticsLabel: l10n.eventDescriptionResetDay,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDescriptionCell(AppLocalizations l10n, ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final showPreviewToggle = !_liveMarkdownRendering;
    final previewing = showPreviewToggle && _descriptionPreview;
    final rightInset = showPreviewToggle
        ? FormMetrics.trailingButtonSize * 2
        : FormMetrics.trailingButtonSize;
    final Widget surface;
    if (previewing) {
      final text = _descriptionController.text;
      surface = ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: _descriptionLineHeight,
          maxHeight: _descriptionLineHeight * _descriptionMaxLines,
        ),
        child: text.trim().isEmpty
            ? const SizedBox.shrink()
            : SimpleMarkdownPreview(
                data: text,
                padding: EdgeInsets.zero,
                colorPalette: _colorPalette,
              ),
      );
    } else {
      surface = _DescriptionBox(
        revision: _descriptionRevision,
        measure: () => _descriptionScroll.contentHeight,
        minHeight: _descriptionLineHeight,
        maxHeight: _descriptionLineHeight * _descriptionMaxLines,
        child: ModernEditorWrapper(
          controller: _descriptionController,
          focusNode: _descriptionFocus,
          scrollController: _descriptionScroll,
          searchController: _descriptionSearch,
          editorFontSize: _descriptionFontSize,
          editorLineHeight: _descriptionLineHeight / _descriptionFontSize,
          editorPadding: EdgeInsets.zero,
          paintGround: false,
          onTextChanged: _descriptionEdits.onTextChanged,
          checkboxTapToggle: _liveMarkdownRendering,
          showScrollIndicator: false,
        ),
      );
    }
    return _IndentedRow(
      dividerIndent: FormMetrics.dividerIndentPlain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_scopeControlVisible) _buildScopeStrip(l10n, theme),
          Stack(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  RowMetrics.groupInset,
                  _descriptionCellPadding,
                  rightInset,
                  _descriptionCellPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    KeyedSubtree(key: _descriptionKey, child: surface),
                    ListenableBuilder(
                      listenable: _descriptionRevision,
                      builder: (context, _) {
                        final length = _descriptionController.textLength;
                        final over = !_activeScopeWithinLimit;
                        if (!over && length < _descriptionCounterFrom) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(
                            top: _descriptionCounterTopInset,
                          ),
                          child: Text(
                            l10n.eventDescriptionCount(
                              length,
                              _descriptionLimit,
                            ),
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontSize: FormMetrics.counterSize,
                              height: 16 / FormMetrics.counterSize,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                              color: over
                                  ? colorScheme.error
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              if (!previewing)
                Positioned(
                  left: RowMetrics.groupInset,
                  top: _descriptionCellPadding,
                  right: rightInset,
                  child: IgnorePointer(
                    child: ListenableBuilder(
                      listenable: _descriptionRevision,
                      builder: (context, _) {
                        if (_descriptionController.textLength > 0) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          l10n.eventDescriptionAdd,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: _descriptionFontSize,
                            height:
                                _descriptionLineHeight / _descriptionFontSize,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              Positioned(
                top: 0,
                right: 0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showPreviewToggle)
                      FormTrailingButton(
                        icon: _descriptionPreview
                            ? Icons.edit_outlined
                            : Icons.visibility_outlined,
                        tooltip: _descriptionPreview
                            ? l10n.eventDescriptionPreviewOff
                            : l10n.eventDescriptionPreviewOn,
                        onPressed: () => setState(
                          () => _descriptionPreview = !_descriptionPreview,
                        ),
                      ),
                    FormTrailingButton(
                      icon: Icons.open_in_full_rounded,
                      tooltip: l10n.eventDescriptionExpand,
                      onPressed: _openDescriptionSheet,
                    ),
                  ],
                ),
              ),
            ],
          ),
          ListenableBuilder(
            listenable: _descriptionRevision,
            builder: (context, _) {
              if (_activeScopeWithinLimit) return const SizedBox.shrink();
              return FormCaption(
                text: l10n.eventDescriptionTooLong(_descriptionLimit),
                error: true,
                padding: const EdgeInsets.fromLTRB(
                  RowMetrics.groupInset,
                  0,
                  RowMetrics.groupInset,
                  12,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// The markdown bar, shown only while the description has focus. It sits
  /// below the sheet's scroll view so appearing costs the form no layout
  /// shift — the sheet's height is fixed, so the bar takes its strip from
  /// the scrollable area.
  ///
  /// Counter-bound shortcuts are filtered out: `{c1}` resolves against a note
  /// context an event does not have, and wiring them to the global counters
  /// would mutate them from a calendar sheet.
  ///
  /// Undo/redo enablement follows the controller through a [ListenableBuilder]
  /// rather than `setState`, so a keystroke repaints the bar instead of the
  /// whole form.
  Widget _buildDescriptionBar() {
    return BlocBuilder<MarkdownBarBloc, MarkdownBarState>(
      builder: (context, state) {
        if (state is! MarkdownBarLoaded) return const SizedBox.shrink();
        final shortcuts = state.currentShortcuts
            .where((s) => s.effectiveCounters.isEmpty)
            .toList();
        return ListenableBuilder(
          listenable: _descriptionRevision,
          builder: (context, _) => MarkdownBar(
            shortcuts: shortcuts,
            isPreviewMode: false,
            canUndo: _descriptionController.canUndo,
            canRedo: _descriptionController.canRedo,
            previewFontSize: FontConstants.defaultFontSize,
            splitEnabled: false,
            showSettings: false,
            showReorder: false,
            utilityConfigs: _descriptionUtilities,
            onUndo: _descriptionController.undo,
            onRedo: _descriptionController.redo,
            onPaste: _descriptionController.paste,
            onDecreaseFontSize: () {},
            onIncreaseFontSize: () {},
            onSettings: () {},
            onShortcutPressed: _handleDescriptionShortcut,
          ),
        );
      },
    );
  }

  /// Applies a bar shortcut to the description. Mirrors the note editor's
  /// routing: the ghost / colour-slot shortcuts have bespoke inserts, and
  /// everything else goes through the shared applier as one undo entry.
  /// Counter mutation is unreachable — those shortcuts never reach the bar.
  void _handleDescriptionShortcut(CustomMarkdownShortcut shortcut) {
    // Guarded like every programmatic insert in the note editor: the
    // notification it fires must not be diffed as typing, and the length
    // must be resynced or the next keystroke is.
    _descriptionEdits.runGuarded(() {
      if (MarkdownShortcutInserter.handles(shortcut)) {
        MarkdownShortcutInserter.apply(_descriptionController, shortcut);
      } else {
        _descriptionController.runRevocableOp(() {
          ShortcutApplier.apply(
            controller: _descriptionController,
            shortcut: shortcut,
            mutateCounter: (_, _) async => null,
          );
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _descriptionController.makeCursorVisible();
    });
  }

  /// Opens the description in a full-height sheet and folds the result back
  /// into the field.
  ///
  /// Seeded from the controller — **the active scope only**. The scope control
  /// stays behind in the form and the sheet never sees it, which is what keeps
  /// the sheet a pure text-in / text-out widget and the two-buffer
  /// copy-on-write logic in exactly one place. Nothing is saved here either:
  /// this edits the in-flight controller, and the form still saves.
  Future<void> _openDescriptionSheet() async {
    _blur();
    final l10n = AppLocalizations.of(context)!;
    final initial = _descriptionController.text;
    final onDay = _scopeControlVisible && _scope == _DescriptionScope.thisDay;
    final result = await EventDescriptionSheet.show(
      context,
      initialText: initial,
      heading: _titleController.text.trim(),
      // Each scope carries its own budget and its own grandfather, so the
      // sheet is handed the active one's.
      limit: _descriptionLimit,
      grandfatheredLength: onDay ? _initialDayLength : _initialTemplateLength,
      scopeCaption: _scopeControlVisible
          ? (onDay
                ? l10n.eventDescriptionScopeThisDayHint
                : l10n.eventDescriptionScopeAllDaysHint)
          : null,
      colorPalette: _colorPalette,
    );
    if (result == null || !mounted || result == initial) return;
    // `loadText` for the same reason a scope swap uses it: `set text` is a
    // revocable op, so undo would otherwise pull back the text the sheet
    // replaced. The active scope's buffer is the controller itself, so there
    // is nothing else to mirror into. `setState` refreshes the reset button
    // and, while live rendering is off, the read-only preview.
    setState(() {
      _descriptionController.loadText(result);
      _descriptionEdits.syncLength();
    });
  }

  List<Widget> _buildWhenRows(
    AppLocalizations l10n,
    DateFormat dateFormat,
    List<DateTime> oneTimeDates,
  ) {
    final oneTime = _mode == _RepeatMode.oneTime;
    final endMinute = _durationMinutes == null
        ? null
        : (_startMinute + _durationMinutes!) % EventTime.minutesPerDay;
    final crossesMidnight =
        _durationMinutes != null &&
        _startMinute + _durationMinutes! >= EventTime.minutesPerDay;
    return [
      if (oneTime && oneTimeDates.length == 1)
        FormPickerRow(
          glyph: Icons.calendar_today_outlined,
          identifier: SemanticsIds.eventDate,
                            label: l10n.eventDateLabel,
          value: dateFormat.format(_date),
          onTap: _pickDate,
        )
      else if (oneTime && oneTimeDates.length > _maxInlineDates)
        FormPickerRow(
          glyph: Icons.calendar_today_outlined,
          identifier: SemanticsIds.eventDates,
                            label: l10n.eventDatesLabel,
          value: _datesValue(l10n, oneTimeDates),
          onTap: () => _pickOneTimeDates(view: CalendarDatePickerView.list),
        )
      else if (oneTime)
        for (final date in oneTimeDates)
          FormPickerRow(
            glyph: Icons.calendar_today_outlined,
            label: dateFormat.format(date),
            onTap: _pickOneTimeDates,
            trailingButton: FormTrailingButton(
              icon: Icons.close_rounded,
              tooltip: l10n.eventRemoveDate,
              onPressed: () => _removeOneTimeDate(date),
            ),
          )
      else
        FormPickerRow(
          glyph: Icons.calendar_today_outlined,
          identifier: SemanticsIds.eventDate,
                            label: l10n.eventDate,
          value: dateFormat.format(_date),
          onTap: _pickDate,
        ),
      if (oneTime)
        FormActionRow(
          glyph: Icons.add_rounded,
          identifier: SemanticsIds.eventAddDate,
                            label: l10n.eventAddDate,
          onTap: _pickOneTimeDates,
        ),
      FormSwitchRow(
        glyph: Icons.schedule_outlined,
        identifier: SemanticsIds.eventAllDay,
                            label: l10n.eventAllDay,
        value: _isAllDay,
        onChanged: _setAllDay,
      ),
      if (!_isAllDay) ...[
        ValueChangeHighlight(
          value: _startMinute,
          child: FormPickerRow(
            subRow: true,
            identifier: SemanticsIds.eventStarts,
                            label: l10n.eventStarts,
            value: EventTimeFormatter.formatMinute(_startMinute, context),
            onTap: _pickStartTime,
          ),
        ),
        ValueChangeHighlight(
          value: endMinute,
          child: endMinute == null
              ? FormPickerRow(
                  subRow: true,
                  identifier: SemanticsIds.eventEnds,
                            label: l10n.eventEnds,
                  value: l10n.eventEndTimeNone,
                  onTap: _pickEndTime,
                )
              : FormPickerRow(
                  subRow: true,
                  label: crossesMidnight
                      ? l10n.eventCrossesMidnight
                      : l10n.eventEnds,
                  value:
                      '${EventTimeFormatter.formatMinute(endMinute, context)}'
                      ' · '
                      '${EventTimeFormatter.formatDuration(_durationMinutes!, l10n)}',
                  onTap: _pickEndTime,
                  trailingButton: FormTrailingButton(
                    icon: Icons.close_rounded,
                    tooltip: l10n.eventEndTimeRemove,
                    onPressed: _clearEndTime,
                  ),
                ),
        ),
      ],
      FormPickerRow(
        glyph: Icons.repeat_rounded,
        identifier: SemanticsIds.eventRepeat,
                            label: l10n.eventRepeat,
        value: _repeatValue(l10n),
        onTap: _pickRepeat,
      ),
    ];
  }

  List<Widget> _buildOccurrenceRows(
    AppLocalizations l10n,
    DateFormat dateFormat,
  ) {
    final recurring = _mode == _RepeatMode.recurring;
    return [
      if (recurring && _kind.supportsInterval) ...[
        FormSwitchRow(
          glyph: Icons.numbers_rounded,
          label: l10n.eventCountOccurrences,
          value: _countOccurrences,
          onChanged: (v) => setState(() => _countOccurrences = v),
        ),
        if (_countOccurrences)
          FormChipRow(
            chips: [
              for (final style in OccurrenceCountStyle.values)
                FormChip(
                  label: _countStyleLabel(l10n, style),
                  selected: _countStyle == style,
                  onTap: () => setState(() {
                    _countStyle = style;
                    _countStyleTouched = true;
                  }),
                ),
            ],
            caption: FormCaption(text: _countStyleExample(l10n)),
          ),
      ],
      FormSwitchRow(
        glyph: Icons.how_to_reg_outlined,
        label: l10n.eventTrackPresence,
        value: _tracksPresence,
        onChanged: (v) => setState(() => _tracksPresence = v),
      ),
      if (_tracksPresence) ...[
        FormChipRow(
          chips: [
            FormChip(
              label: l10n.eventAssumePresent,
              selected: !_assumeAbsent,
              onTap: () => setState(() => _selectAssumeAbsent(false)),
            ),
            FormChip(
              label: l10n.eventAssumeAbsent,
              selected: _assumeAbsent,
              onTap: () => setState(() => _selectAssumeAbsent(true)),
            ),
          ],
        ),
        if (_assumeAbsent && _isEditing)
          FormPickerRow(
            subRow: true,
            label: l10n.eventAssumeAbsentFrom,
            value: _assumeAbsentFrom == null
                ? l10n.eventAssumeAbsentFromStart
                : dateFormat.format(_assumeAbsentFrom!),
            onTap: _pickAssumeAbsentFrom,
            trailingButton: _assumeAbsentFrom == null
                ? null
                : FormTrailingButton(
                    icon: Icons.close_rounded,
                    tooltip: l10n.resetToDefault,
                    onPressed: () => setState(() {
                      _assumeAbsentFrom = null;
                      _assumeAbsentFromTouched = true;
                    }),
                  ),
          ),
      ],
      if (_dayRailEnabled)
        FormMenuRow<_DayRailChoice>(
          glyph: Icons.vertical_split_outlined,
          label: l10n.eventShowInDayRail,
          value: _dayRailLabel(l10n, _DayRailChoice.of(_showInDayRail)),
          selected: _DayRailChoice.of(_showInDayRail),
          menuWidth: _dayRailMenuWidth,
          items: [
            for (final choice in _DayRailChoice.values)
              FormMenuItem(value: choice, label: _dayRailLabel(l10n, choice)),
          ],
          onSelected: (choice) => setState(() => _showInDayRail = choice.value),
        ),
      FormSwitchRow(
        glyph: Icons.event_note_outlined,
        label: l10n.eventPerOccurrenceDescriptions,
        value: _perOccurrenceDescriptions,
        onChanged: _setPerOccurrenceDescriptions,
      ),
      if (_isEditing)
        FormPickerRow(
          glyph: Icons.event_busy_outlined,
          label: l10n.eventSkippedDays,
          value: _effectiveSkippedDays.isEmpty
              ? l10n.eventNoSkippedDays
              : l10n.eventSkippedDaysCount(_effectiveSkippedDays.length),
          onTap: _pickSkippedDays,
        ),
    ];
  }

  List<Widget> _buildAlertRows(AppLocalizations l10n) {
    return [
      for (final alert in _alerts)
        FormPickerRow(
          glyph: alert.isAlarm
              ? Icons.alarm_outlined
              : Icons.notifications_outlined,
          label: alert.describe(l10n, _alertPreviewEvent),
          value: alert.isAlarm
              ? l10n.eventAlertModeRing
              : l10n.eventAlertModeNotify,
          onTap: () => _editAlert(alert),
          trailingButton: FormTrailingButton(
            icon: Icons.close_rounded,
            tooltip: l10n.eventAlertRemove,
            onPressed: () => _removeAlert(alert),
          ),
        ),
      if (_alerts.length < kMaxAlertsPerEvent)
        AutomationId(
          identifier: SemanticsIds.eventAlertAdd,
          child: FormActionRow(
            glyph: Icons.add_rounded,
            label: l10n.eventAlertAdd,
            onTap: _addAlert,
          ),
        ),
      if (_isOneTimeEvent && _hasAlarmAlert)
        AutomationId(
          identifier: SemanticsIds.eventAlertRemoveAfter,
          child: FormSwitchRow(
            glyph: Icons.auto_delete_outlined,
            label: l10n.eventAlertRemoveAfter,
            value: _removeAfterAlert,
            onChanged: (value) => setState(() => _removeAfterAlert = value),
          ),
        ),
    ];
  }

  Widget _buildLinkedNoteRow(AppLocalizations l10n, ThemeData theme) {
    final colorScheme = theme.colorScheme;
    if (_noteId == null) {
      return FormPickerRow(
        glyph: Icons.sticky_note_2_outlined,
        identifier: SemanticsIds.eventLinkedNote,
                            label: l10n.eventLinkedNote,
        value: l10n.eventLinkedNoteNone,
        onTap: _pickNote,
      );
    }
    final unlink = FormTrailingButton(
      icon: Icons.link_off_rounded,
      tooltip: l10n.eventRemoveNoteLink,
      onPressed: _clearNote,
    );
    if (_noteMissing) {
      return FormPickerRow(
        glyph: Icons.warning_amber_rounded,
        glyphColor: colorScheme.error,
        identifier: SemanticsIds.eventLinkedNote,
                            label: l10n.eventLinkedNote,
        value: l10n.eventLinkedNoteNotFound,
        valueColor: colorScheme.error,
        semanticsLabel: l10n.eventLinkedNoteMissing,
        onTap: _pickNote,
        trailingButton: unlink,
      );
    }
    final title = _noteTitle;
    return FormPickerRow(
      glyph: Icons.sticky_note_2_outlined,
      identifier: SemanticsIds.eventLinkedNote,
                            label: l10n.eventLinkedNote,
      value: title == null ? '' : (title.isEmpty ? l10n.untitledNote : title),
      onTap: _pickNote,
      trailingButton: unlink,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _leave();
      },
      child: ValueListenableBuilder<double>(
        valueListenable: _dragOffset,
        builder: (context, offset, child) =>
            Transform.translate(offset: Offset(0, offset), child: child),
        child: Material(
          key: _sheetKey,
          color: colorScheme.pageGround,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(FormMetrics.sheetRadius),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: _onDragStart,
                onVerticalDragUpdate: _onDragUpdate,
                onVerticalDragEnd: _onDragEnd,
                onVerticalDragCancel: _onDragCancel,
                child: Column(
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
                      scrolled: _headerScrolled,
                      trailing: ListenableBuilder(
                        listenable: Listenable.merge([
                          _descriptionRevision,
                          _titleController,
                        ]),
                        builder: (context, _) => AutomationId(
                          identifier: SemanticsIds.eventSave,
                          child: FilledButton(
                            onPressed: _canSave ? _onSave : null,
                            child: Text(l10n.save),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
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
                          _buildTitleRow(l10n, theme, icon, accent),
                          FormPickerRow(
                            glyph: Icons.label_outlined,
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
                            valueLeading: _ColorDot(color: eventColor),
                            onTap: _pickLook,
                            dividerIndent: FormMetrics.dividerIndentPlain,
                          ),
                          _buildDescriptionCell(l10n, theme),
                        ],
                      ),
                      FormSectionLabel(text: l10n.eventSectionWhen),
                      FormRowGroup(
                        children: _buildWhenRows(
                          l10n,
                          dateFormat,
                          oneTimeDates,
                        ),
                      ),
                      if (_ruleHasManyOccurrences) ...[
                        FormSectionLabel(text: l10n.recurrenceScopeLabel),
                        FormRowGroup(
                          children: _buildOccurrenceRows(l10n, dateFormat),
                        ),
                      ],
                      FormSectionLabel(text: l10n.eventAlerts),
                      FormRowGroup(children: _buildAlertRows(l10n)),
                      FormSectionLabel(text: l10n.eventSectionDetails),
                      FormRowGroup(
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
                          _buildLinkedNoteRow(l10n, theme),
                        ],
                      ),
                      FormRowGroup(
                        trailingGap: false,
                        children: [
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
          ),
        ),
      ),
    );
  }
}

class _IndentedRow extends FormDividedRow {
  final Widget child;

  @override
  final double dividerIndent;

  const _IndentedRow({required this.dividerIndent, required this.child});

  @override
  Widget build(BuildContext context) => child;
}

class _ColorDot extends StatelessWidget {
  static const double size = 10;

  final Color color;

  const _ColorDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _DescriptionBox extends SingleChildRenderObjectWidget {
  final Listenable revision;
  final double? Function() measure;
  final double minHeight;
  final double maxHeight;

  const _DescriptionBox({
    required this.revision,
    required this.measure,
    required this.minHeight,
    required this.maxHeight,
    required Widget super.child,
  });

  @override
  _RenderDescriptionBox createRenderObject(BuildContext context) {
    return _RenderDescriptionBox(
      revision: revision,
      measure: measure,
      minHeight: minHeight,
      maxHeight: maxHeight,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderDescriptionBox renderObject,
  ) {
    renderObject
      ..revision = revision
      ..measure = measure
      ..minHeight = minHeight
      ..maxHeight = maxHeight;
  }
}

class _RenderDescriptionBox extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  static const int _maxPasses = 3;

  Listenable _revision;
  double? Function() measure;
  double _minHeight;
  double _maxHeight;
  double _height;

  _RenderDescriptionBox({
    required Listenable revision,
    required this.measure,
    required double minHeight,
    required double maxHeight,
  }) : _revision = revision,
       _minHeight = minHeight,
       _maxHeight = maxHeight,
       _height = minHeight;

  set revision(Listenable value) {
    if (identical(value, _revision)) return;
    if (attached) _revision.removeListener(markNeedsLayout);
    _revision = value;
    if (attached) _revision.addListener(markNeedsLayout);
  }

  set minHeight(double value) {
    if (value == _minHeight) return;
    _minHeight = value;
    markNeedsLayout();
  }

  set maxHeight(double value) {
    if (value == _maxHeight) return;
    _maxHeight = value;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _revision.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _revision.removeListener(markNeedsLayout);
    super.detach();
  }

  double _clamp(double height) => height.clamp(_minHeight, _maxHeight);

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final child = this.child;
    if (child == null) {
      size = constraints.constrain(Size(width, _clamp(_height)));
      return;
    }
    var height = _clamp(_height);
    for (var pass = 0; pass < _maxPasses; pass++) {
      child.layout(
        BoxConstraints.tightFor(width: width, height: height),
        parentUsesSize: true,
      );
      final content = measure();
      if (content == null) break;
      final next = _clamp(content);
      if ((next - height).abs() < 0.5) break;
      height = next;
      if (pass == _maxPasses - 1) {
        child.layout(
          BoxConstraints.tightFor(width: width, height: height),
          parentUsesSize: true,
        );
      }
    }
    _height = height;
    size = constraints.constrain(Size(width, height));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    return constraints.constrain(Size(constraints.maxWidth, _clamp(_height)));
  }

  @override
  double computeMinIntrinsicHeight(double width) => _clamp(_height);

  @override
  double computeMaxIntrinsicHeight(double width) => _clamp(_height);

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => 0;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child != null) context.paintChild(child, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return child?.hitTest(result, position: position) ?? false;
  }
}
