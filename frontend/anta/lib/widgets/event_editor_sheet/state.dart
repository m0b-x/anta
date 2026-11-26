part of '../event_editor_sheet.dart';

/// Natural count style for [kind].
///
/// Yearly is **elapsed**: a yearly counted event is an anniversary, and an
/// anniversary is measured in elapsed time. Numbering it instead is off by
/// one against how everyone reads a birthday — someone born in 2000 has
/// their 27th *occurrence* in 2026, but they turn 26, so "Year 27" reads
/// as a mistake even though it counts correctly. Shorter cadences keep
/// numbering, where "Day 1 / Week 3" is exactly the training-program
/// reading people want.
OccurrenceCountStyle _defaultCountStyleFor(RepeatKind kind) {
  return kind == RepeatKind.yearly
      ? OccurrenceCountStyle.elapsed
      : OccurrenceCountStyle.numbered;
}

/// The alerts an event in [categoryId] inherits — through the resolved
/// category, the rendering rule `EventAlerts.effectiveFor` follows, so an
/// unknown id reads as Other's. Enabled ones only: an alert the category
/// editor paused (D5) fires for no event, and is shown only there.
List<CategoryAlert> _categoryAlertsOf(String categoryId) => [
  for (final alert in EventAlerts.categoryAlertsFor(
    CalendarCategories.resolve(categoryId).id,
  ))
    if (alert.enabled) alert,
];

/// What the event editor holds between builds, and what is read straight
/// off it. The sheet's State is this class with the mixins of the sibling
/// files applied in the order [_EventEditorSheetState] lists them, and each
/// of them sees only the ones before it.
abstract class _EventEditorState extends State<EventEditorSheet> {
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
  /// Nothing in this sheet may listen to the controller directly: a
  /// notification can land while the framework is building, and every
  /// `ListenableBuilder` mounted above the editor (the Save button, the
  /// counter, the over-limit hint) is already clean by then, so its
  /// `markNeedsBuild` throws "setState() called during build". Until
  /// 2026-10-01 that happened on the sheet's very first frame — re_editor's
  /// delegate handoff notified from the editor's `initState` on every mount;
  /// it still does when a controller is swapped into a mounted editor.
  ///
  /// Keystrokes arrive outside the frame and take the synchronous path; only a
  /// mid-build notification is deferred, and repeats coalesce into one bump.
  final ValueNotifier<int> _descriptionRevision = ValueNotifier<int>(0);
  bool _revisionBumpScheduled = false;

  /// One caret reveal per frame, however many notifications an edit fires.
  bool _caretRevealScheduled = false;

  /// True from the description taking focus until its focus reveal has run.
  /// The keyboard is rising through that window, and a caret reveal on every
  /// inset frame followed by the centring would move the form twice.
  bool _focusRevealPending = false;

  /// The form viewport's height at its last metrics report; see
  /// [_onFormMetrics].
  double? _formViewportHeight;

  /// The preview's scroller while live rendering is off and the cell shows
  /// the rendered text; the cell's scroll rail reads whichever of the two
  /// surfaces is mounted.
  final ScrollController _descriptionPreviewScroll = ScrollController();

  /// Ticks when either description surface reports new scroll metrics, so
  /// the rail appears in the frame after the text first overflows instead of
  /// at its next periodic check.
  final ValueNotifier<int> _descriptionMetricsTick = ValueNotifier<int>(0);

  /// Anchors the scroll-into-view on focus.
  final GlobalKey _descriptionKey = GlobalKey();
  final ScrollController _bodyScroll = ScrollController();
  final FormHeaderHairline _hairline = FormHeaderHairline();
  late String _initialFingerprint;

  /// [_alertsFingerprint] as the sheet opened, re-taken when — and only when —
  /// [_seedDefaultAlert] actually adds the settings default.
  late String _initialAlertsFingerprint;
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

  /// Whether the event records which of its occurrences were kept or missed —
  /// any shape since decision B of the analytics record: a one-off dentist
  /// visit is attended or missed like a weekly session. Offered where
  /// [_presenceOffered] says.
  bool _tracksPresence = false;

  /// Whether the owner has set the presence switch or its default here — the
  /// [_assumeAbsentFromTouched] idiom. Until they do, a new event's two
  /// presence flags follow its category's kind (decision U) and re-resolve
  /// on every category pick; after, a pick leaves their answer alone.
  bool _presenceTouched = false;

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
  /// by [_ruleHasManyOccurrences]: a one-off follows auto, so the control
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

  /// The persisted cancelled days as the sheet opened, read once — the
  /// fingerprint's side of [_skippedDays].
  ///
  /// A snapshot, because `EventSkipService.reload()` republishes the whole
  /// facade on every sync pull: fingerprinting the live set made an untouched
  /// editor claim unsaved changes the moment a pull merged a skip for this
  /// event, leaving the discard dialog with nothing to discard. Every other
  /// input in [_fingerprint] is a snapshot too, so [_skippedDays] stays the
  /// only thing that can move this one.
  late final Set<DateTime> _initialSkippedDays =
      widget.initialSkippedDays ??
      EventSkips.daysFor(widget.initialEvent?.id ?? '');

  /// Whether the event keeps one description per occurrence instead of one
  /// shared by every day, with its own description as the template each day
  /// starts from. Gated by [_ruleHasManyOccurrences] — an event that fires
  /// once has nothing to separate.
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

  /// The app-wide haptics setting, resolved with the rest of the sheet's
  /// settings, so a description box toggled here clicks exactly when one
  /// in a note does.
  bool _hapticsEnabled = SettingsKeys.defaultHapticFeedback;

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

  /// The text [_dayBuffer] was seeded with, so the copy-on-write guard can
  /// tell an untouched day from an edited one.
  ///
  /// Compared against *this* and not against the template as the form now
  /// holds it: an edit in the shared scope moves the template and leaves the
  /// day buffer on the text it was seeded from, and reading that gap as a
  /// divergence forked the day the editor was opened from and pinned it to
  /// the pre-edit text.
  late final String _daySeedText;

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

  /// The ids [_alerts] was seeded with. Rides the result so the write
  /// tombstones only the rows this form was actually showing: a pull can add
  /// an alert to this event while the sheet is open, and a whole-set save
  /// would otherwise delete it without it ever having been on screen.
  Set<String> _seededAlertIds = const {};

  /// Draft state for `CalendarEvent.removeAfterAlert` (**A3**). Meaningless
  /// unless the event is one-time and carries an alarm, and cleared on save in
  /// that case — the same shape [_assumeAbsent] follows.
  bool _removeAfterAlert = false;

  /// Draft state for `CalendarEvent.categoryAlerts` (**v42**, D3): whether
  /// this event inherits its category's alerts.
  bool _categoryAlerts = true;

  /// Draft state for the event's own share mark (share surfaces §6.6). Kept
  /// as the person left it while the category shares the event anyway, so
  /// moving it to an unshared category again shows the choice they made.
  bool _markedShared = false;

  /// The event's mark as stored: as it opened, then the opener's answer
  /// after each trip to Sync & sharing. The draft is dirty by a switch that
  /// differs from it, so a re-seed on the return leaves the form clean.
  bool _storedMark = false;

  /// [EventEditorSheet.shareAvailability], then the opener's answer again
  /// after each trip to Sync & sharing from the share row.
  late ShareAvailability _shareAvailability = widget.shareAvailability;

  /// The alerts the category the form currently has would hand down, read
  /// synchronously from the facade. Shown read-only beside the own ones; never
  /// part of [_alerts], so the cap, the remove-after gate and the saved set
  /// stay the event's own.
  ///
  /// Memoized against the picked category **and** `EventAlerts.revision`
  /// rather than resolved once on open: a pull, or the category editor reached
  /// through the picker's inline create, can write a category's alerts while
  /// this sheet is open, and the inherited rows — and the Category alerts
  /// switch they gate — would otherwise keep showing the set the sheet opened
  /// on. Re-reading a facade on every rebuild is what the agenda rows do.
  List<CategoryAlert> get _inheritedAlerts {
    final revision = EventAlerts.revision;
    if (revision != _inheritedRevision || _inheritedCategoryId != _categoryId) {
      _inheritedRevision = revision;
      _inheritedCategoryId = _categoryId;
      _inheritedCache = _categoryAlertsOf(_categoryId);
    }
    return _inheritedCache;
  }

  List<CategoryAlert> _inheritedCache = const [];
  int _inheritedRevision = -1;
  String? _inheritedCategoryId;

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

  // --- Pure helpers -------------------------------------------------------

  DateTime _normalize(DateTime d) => DateTime.utc(d.year, d.month, d.day);
}
