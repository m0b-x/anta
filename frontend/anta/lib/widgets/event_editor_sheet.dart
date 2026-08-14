import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:re_editor/re_editor.dart';
import 'package:uuid/uuid.dart';

import '../bloc/markdown_bar/markdown_bar_bloc.dart';
import '../constants/calendar_bounds.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_colors.dart';
import '../constants/calendar_icons.dart';
import '../constants/event_priorities.dart';
import '../constants/font_constants.dart';
import '../constants/occurrence_descriptions.dart';
import '../constants/settings_keys.dart';
import '../controllers/markdown_shortcut_inserter.dart';
import '../controllers/shortcut_applier.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/custom_markdown_shortcut.dart';
import '../models/recurrence_rule.dart';
import '../models/utility_button_config.dart';
import '../repositories/note_repository.dart';
import '../services/event_time_formatter.dart';
import '../services/recurrence_formatter.dart';
import '../services/settings_service.dart';
import '../utils/list_aware_paste.dart';
import '../utils/markdown_color_syntax.dart';
import '../utils/markdown_editor_span_builder.dart';
import '../utils/re_editor_search_controller.dart';
import 'calendar_date_picker_sheet.dart';
import 'category_picker_sheet.dart';
import 'color_wheel_picker.dart';
import 'icon_picker_sheet.dart';
import 'markdown_bar.dart';
import 'modern_editor_wrapper.dart';
import 'note_picker_dialog.dart';
import 'simple_markdown_preview.dart';

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

  const EventEditorSaved(
    this.event, {
    this.occurrenceDay,
    this.occurrenceDescription,
  });
}

class EventEditorDeleted extends EventEditorResult {
  final String id;
  const EventEditorDeleted(this.id);
}

/// Top-level repeat mode shown as a segmented control.
enum _RepeatMode { oneTime, recurring }

/// Which description the editor's field is currently showing (v24). Only
/// meaningful while the scope control is visible; otherwise the field always
/// shows [allDays].
enum _DescriptionScope { allDays, thisDay }

/// Recurring frequency choices. Maps 1:1 onto a concrete [RecurrenceRule]
/// at save time (Weekly carries the user-selected weekday set).
enum _RecurrenceKind {
  daily,
  weekly,
  monthly,
  yearly,
  workdays,
  weekends,
  holidays,
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

  const EventEditorSheet({
    super.key,
    required this.defaultDate,
    this.initialEvent,
    this.occurrenceDay,
    this.pendingOccurrenceDescription,
    this.dayLoad,
    this.appearance = const CalendarAppearance(),
  });

  static Future<EventEditorResult?> show(
    BuildContext context, {
    required DateTime defaultDate,
    CalendarEvent? initialEvent,
    DateTime? occurrenceDay,
    String? pendingOccurrenceDescription,
    PickerDayLoad? dayLoad,
    CalendarAppearance appearance = const CalendarAppearance(),
  }) {
    return showModalBottomSheet<EventEditorResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: EventEditorSheet(
          defaultDate: defaultDate,
          initialEvent: initialEvent,
          occurrenceDay: occurrenceDay,
          pendingOccurrenceDescription: pendingOccurrenceDescription,
          dayLoad: dayLoad,
          appearance: appearance,
        ),
      ),
    );
  }

  @override
  State<EventEditorSheet> createState() => _EventEditorSheetState();
}

class _EventEditorSheetState extends State<EventEditorSheet> {
  /// Default start-of-day for newly enabled timed events. 9:00 is a
  /// neutral choice that suits a gym-planner; user can edit immediately.
  static const int _defaultStartMinute = 9 * 60;

  /// Default duration the first time a user enables an end time on a new
  /// timed event (60 minutes — a typical session).
  static const int _defaultDurationMinutes = 60;

  /// Upper bound for the recurrence interval ("every N …"). 99 keeps the
  /// stepper compact while comfortably covering any realistic training split.
  static const int _maxInterval = 99;

  /// Bounds of the description editor box. Roughly three lines at rest and
  /// eight when filled, after which the editor scrolls internally.
  static const double _descriptionMinHeight = 120;
  static const double _descriptionMaxHeight = 260;

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
  late final FocusNode _descriptionFocus;
  late final CodeScrollController _descriptionScroll;

  /// The wrapper requires one; the description has no search UI, so it is
  /// created, wired and thrown away with the sheet.
  late final ReEditorSearchController _descriptionSearch;

  final MarkdownEditorSpanBuilder _descriptionSpanBuilder =
      MarkdownEditorSpanBuilder();

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
  late String _categoryId;
  String? _iconKey;
  late DateTime _date;
  DateTime? _endDate;
  late _RepeatMode _mode;
  late _RecurrenceKind _kind;
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
  static OccurrenceCountStyle _defaultCountStyleFor(_RecurrenceKind kind) {
    return kind == _RecurrenceKind.yearly
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

  /// Recently-used custom (non-palette) colors, most-recent-first. Loaded
  /// from settings on open and updated when the user picks a wheel color.
  List<int> _recentColors = const [];

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

  bool get _isEditing => widget.initialEvent != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialEvent;
    _titleController = TextEditingController(text: initial?.title ?? '');
    _descriptionController = ListAwarePasteController(
      delegate: CodeLineEditingController(spanBuilder: _buildDescriptionSpan),
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
    // recurrence rule is known. Seeding the text is itself a revocable op, so
    // without clearHistory undo can wipe what the sheet opened with.
    _descriptionController.text = _templateBuffer;
    _descriptionController.clearHistory();
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
    _initRecurrenceFrom(initial?.rule ?? const OneTimeRecurrence());
    // Only a saved event that was actually counting carries a style the user
    // can be said to have chosen; otherwise the persisted value is just the
    // column default and the frequency should pick it.
    _countStyleTouched = initial != null && initial.countOccurrences;
    _countStyle = _countStyleTouched
        ? initial!.countStyle
        : _defaultCountStyleFor(_kind);
    // Adopt the day scope only now: it needs the recurrence rule, which
    // `_initRecurrenceFrom` has just decoded. Gated on the same condition as
    // the control itself, so a *dormant* row (setting off) can never leave the
    // field showing one day's text with nothing on screen to explain it.
    // `OccurrenceDescriptions.enabled` is safe to read synchronously here —
    // the service publishes it at DI time, unlike the settings resolved in
    // `_loadSheetSettings` below.
    if (_dayMaterialized && _scopeControlVisible) {
      _scope = _DescriptionScope.thisDay;
      _descriptionController.text = _dayBuffer;
      _descriptionController.clearHistory();
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
  }

  void _initRecurrenceFrom(RecurrenceRule rule) {
    // Sensible default weekday set anchored to the event start date.
    _weekdays = {_date.weekday};
    _interval = 1;
    _additionalDates = [];
    switch (rule) {
      case OneTimeRecurrence():
        _mode = _RepeatMode.oneTime;
        _kind = _RecurrenceKind.daily;
      case SpecificDatesRecurrence(:final dates):
        _mode = _RepeatMode.oneTime;
        _kind = _RecurrenceKind.daily;
        _additionalDates = dates.where((d) => d != _date).toList()..sort();
      case DailyRecurrence(:final interval):
        _mode = _RepeatMode.recurring;
        _kind = _RecurrenceKind.daily;
        _interval = interval;
      case WeeklyRecurrence(:final weekdays, :final interval):
        _mode = _RepeatMode.recurring;
        _kind = _RecurrenceKind.weekly;
        _weekdays = weekdays.isEmpty ? {_date.weekday} : Set.of(weekdays);
        _interval = interval;
      case MonthlyRecurrence(:final interval):
        _mode = _RepeatMode.recurring;
        _kind = _RecurrenceKind.monthly;
        _interval = interval;
      case YearlyRecurrence(:final interval):
        _mode = _RepeatMode.recurring;
        _kind = _RecurrenceKind.yearly;
        _interval = interval;
      case WorkdaysRecurrence():
        _mode = _RepeatMode.recurring;
        _kind = _RecurrenceKind.workdays;
      case WeekendsRecurrence():
        _mode = _RepeatMode.recurring;
        _kind = _RecurrenceKind.weekends;
      case PublicHolidaysOnlyRecurrence():
        _mode = _RepeatMode.recurring;
        _kind = _RecurrenceKind.holidays;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.removeListener(_relayDescriptionChange);
    _descriptionController.dispose();
    _descriptionRevision.dispose();
    _descriptionFocus.dispose();
    _descriptionScroll.dispose();
    _descriptionSearch.dispose();
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
  /// to re_editor's own span.
  TextSpan _buildDescriptionSpan({
    required BuildContext context,
    required int index,
    required CodeLine codeLine,
    required TextSpan textSpan,
    required TextStyle style,
  }) {
    if (!_liveMarkdownRendering) return textSpan;
    return _descriptionSpanBuilder.build(
          context: context,
          index: index,
          codeLine: codeLine,
          style: style,
        ) ??
        textSpan;
  }

  // --- Pure helpers -------------------------------------------------------

  DateTime _normalize(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  RecurrenceRule _buildRule() {
    if (_mode == _RepeatMode.oneTime) {
      if (_additionalDates.isEmpty) return const OneTimeRecurrence();
      return SpecificDatesRecurrence(
        dates: Set.unmodifiable(<DateTime>{_date, ..._additionalDates}),
      );
    }
    return switch (_kind) {
      _RecurrenceKind.daily => DailyRecurrence(interval: _interval),
      _RecurrenceKind.weekly => WeeklyRecurrence(
        weekdays: Set.unmodifiable(_weekdays),
        interval: _interval,
      ),
      _RecurrenceKind.monthly => MonthlyRecurrence(interval: _interval),
      _RecurrenceKind.yearly => YearlyRecurrence(interval: _interval),
      _RecurrenceKind.workdays => const WorkdaysRecurrence(),
      _RecurrenceKind.weekends => const WeekendsRecurrence(),
      _RecurrenceKind.holidays => const PublicHolidaysOnlyRecurrence(),
    };
  }

  /// Whether the currently selected frequency supports an "every N" interval.
  /// Workdays / weekends / holidays are fixed cadences, so they don't.
  static bool _kindSupportsInterval(_RecurrenceKind kind) {
    return switch (kind) {
      _RecurrenceKind.daily ||
      _RecurrenceKind.weekly ||
      _RecurrenceKind.monthly ||
      _RecurrenceKind.yearly => true,
      _RecurrenceKind.workdays ||
      _RecurrenceKind.weekends ||
      _RecurrenceKind.holidays => false,
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
          _RecurrenceKind.daily => l10n.eventNumberedDays(n),
          _RecurrenceKind.weekly => l10n.eventNumberedWeeks(n),
          _RecurrenceKind.monthly => l10n.eventNumberedMonths(n),
          _RecurrenceKind.yearly => l10n.eventNumberedYears(n),
          _ => '',
        },
        OccurrenceCountStyle.elapsed => switch (_kind) {
          _RecurrenceKind.daily => l10n.eventElapsedDays(n),
          _RecurrenceKind.weekly => l10n.eventElapsedWeeks(n),
          _RecurrenceKind.monthly => l10n.eventElapsedMonths(n),
          _RecurrenceKind.yearly => l10n.eventElapsedYears(n),
          _ => '',
        },
      };
    }

    final first = _countStyle == OccurrenceCountStyle.numbered ? 1 : 0;
    return '${at(first)} · ${at(first + 1)} · ${at(first + 2)}';
  }

  String _intervalUnitLabel(AppLocalizations l10n, _RecurrenceKind kind) {
    return switch (kind) {
      _RecurrenceKind.daily => l10n.recurrenceUnitDays(_interval),
      _RecurrenceKind.weekly => l10n.recurrenceUnitWeeks(_interval),
      _RecurrenceKind.monthly => l10n.recurrenceUnitMonths(_interval),
      _RecurrenceKind.yearly => l10n.recurrenceUnitYears(_interval),
      _ => '',
    };
  }

  bool get _canSave {
    if (_titleController.text.trim().isEmpty) return false;
    if (_mode == _RepeatMode.recurring &&
        _kind == _RecurrenceKind.weekly &&
        _weekdays.isEmpty) {
      return false;
    }
    // Both scopes, not just the visible one: text parked in the inactive
    // buffer is still about to be saved, so checking only the live controller
    // would let an over-limit day override through from the template view.
    if (!_withinLimit(_templateText, _initialTemplateLength)) return false;
    if (_scopeControlVisible &&
        !_withinLimit(_dayText, _initialDayLength)) {
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

  /// Whether to offer the "this day / all days" control.
  ///
  /// Requires a saved event (a new one has no id until `_onSave`), an
  /// occurrence to scope to (the FAB path has none), the global setting, and a
  /// rule that actually repeats. Flipping the form to one-time mid-edit hides
  /// it — see [_syncScopeToRule].
  bool get _scopeControlVisible =>
      _isEditing &&
      widget.occurrenceDay != null &&
      OccurrenceDescriptions.enabled &&
      _ruleHasManyOccurrences;

  /// Moves the field between the template and this day's text.
  ///
  /// One controller throughout — only its content changes. `clearHistory()` is
  /// mandatory, not tidiness: `set text` runs as a revocable op, so without it
  /// the toolbar's undo would pull the *other* scope's text into the active
  /// one and Save would persist it.
  void _setScope(_DescriptionScope next) {
    if (next == _scope) return;
    if (_scope == _DescriptionScope.allDays) {
      _templateBuffer = _descriptionController.text;
    } else {
      _dayBuffer = _descriptionController.text;
    }
    setState(() {
      _scope = next;
      _descriptionController.text = next == _DescriptionScope.thisDay
          ? _dayBuffer
          : _templateBuffer;
      _descriptionController.clearHistory();
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
        _descriptionController.text = _dayBuffer;
        _descriptionController.clearHistory();
      }
    });
  }

  /// Drops back to the template scope when the form stops describing a
  /// repeating rule, so the field can never show a day's text while the
  /// control that explains it is hidden. The day buffer is kept in memory and
  /// simply not written — flipping to one-time must not silently merge one
  /// occurrence's text into the template.
  void _syncScopeToRule() {
    if (_ruleHasManyOccurrences || _scope == _DescriptionScope.allDays) return;
    _dayBuffer = _descriptionController.text;
    _scope = _DescriptionScope.allDays;
    _descriptionController.text = _templateBuffer;
    _descriptionController.clearHistory();
  }

  /// Whether the chosen color is a freeform value not present in the swatch
  /// palette (so the "custom" dot reflects it instead of a palette dot).
  bool get _isCustomColor =>
      _colorValue != null &&
      !CalendarColors.swatchPalette.contains(_colorValue);

  /// Label for the retroactive scope chip. Yearly rules read naturally as
  /// "Every year"; the others fall back to "Always". Resolved through the
  /// built rule so the wording follows one switch, not two.
  String _scopeAlwaysLabel(AppLocalizations l10n) {
    return RecurrenceFormatter.scopeAlwaysLabel(_buildRule(), l10n);
  }

  String _kindLabel(AppLocalizations l10n, _RecurrenceKind k) {
    return switch (k) {
      _RecurrenceKind.daily => l10n.recurrenceDaily,
      _RecurrenceKind.weekly => l10n.recurrenceWeekly,
      _RecurrenceKind.monthly => l10n.recurrenceMonthly,
      _RecurrenceKind.yearly => l10n.recurrenceYearly,
      _RecurrenceKind.workdays => l10n.recurrenceWorkdays,
      _RecurrenceKind.weekends => l10n.recurrenceWeekends,
      _RecurrenceKind.holidays => l10n.recurrenceHolidaysOnly,
    };
  }

  // --- Interactions -------------------------------------------------------

  Future<void> _pickDate() async {
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
      if (_kind == _RecurrenceKind.weekly &&
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

  Future<void> _pickEndDate() async {
    final initial = _endDate ?? _date;
    final picked = await CalendarDatePickerSheet.pickSingle(
      context,
      initialDate: initial.isBefore(_date) ? _date : initial,
      firstDate: _date,
      lastDate: CalendarBounds.latest,
      dayLoad: widget.dayLoad,
      appearance: widget.appearance,
    );
    if (picked == null || !mounted) return;
    setState(() => _endDate = _normalize(picked));
  }

  /// Edits the whole one-time date set in a single pass. The multi picker
  /// returns the edited set; [_setOneTimeDates] stays the one place that
  /// re-derives the anchor (earliest) and the extras list from it.
  Future<void> _pickOneTimeDates() async {
    final current = <DateTime>{_date, ..._additionalDates};
    final picked = await CalendarDatePickerSheet.pickMulti(
      context,
      initialSelection: current,
      firstDate: CalendarBounds.earliest,
      lastDate: CalendarBounds.latest,
      dayLoad: widget.dayLoad,
      appearance: widget.appearance,
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
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _startMinute ~/ 60,
        minute: _startMinute % 60,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final newStart = picked.hour * 60 + picked.minute;
      // Preserve the visible duration: if a duration is set, keep the
      // *length* (so "1 hour" stays "1 hour"). This is what every native
      // calendar app does when you drag the start time.
      _startMinute = newStart;
    });
  }

  Future<void> _pickEndTime() async {
    // Initialize the picker on the current end time, or one hour after
    // start if no end is set yet.
    final currentEnd = _durationMinutes == null
        ? null
        : _startMinute + _durationMinutes!;
    final initial = currentEnd ?? (_startMinute + _defaultDurationMinutes);
    final clamped = initial % EventTime.minutesPerDay;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: clamped ~/ 60, minute: clamped % 60),
    );
    if (picked == null || !mounted) return;
    final endMinute = picked.hour * 60 + picked.minute;
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

  Future<void> _pickIcon() async {
    final picked = await IconPickerSheet.show(
      context,
      tint: CalendarCategories.resolve(_categoryId).color,
      initialKey: _iconKey,
    );
    if (picked == null || !mounted) return;
    setState(() => _iconKey = picked);
  }

  Future<void> _pickCustomColor() async {
    final picked = await ColorWheelDialog.show(
      context,
      initialColor: _colorValue,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _colorValue = picked;
      _recentColors = <int>{
        picked,
        ..._recentColors,
      }.take(SettingsKeys.maxRecentEventColors).toList();
    });
    final settings = await SettingsService.getInstance();
    await settings.addRecentEventColor(picked);
  }

  Future<void> _loadSheetSettings() async {
    final settings = await SettingsService.getInstance();
    final colors = await settings.getRecentEventColors();
    final palette = await settings.getColorPalette();
    final liveRendering = await settings.getLiveMarkdownRendering();
    final descriptionLimit = await settings.getEventDescriptionLimit();
    if (!mounted) return;
    // Both reach the editor surface non-destructively: the span memos are
    // cleared and re_editor is nudged to rebuild its display paragraphs.
    // Money stays disabled (the builder's default) — the ledger is a
    // per-note concept, so `$` rows in a description are literal text.
    _descriptionSpanBuilder.configureColors(palette);
    final rerender =
        palette != _colorPalette || liveRendering != _liveMarkdownRendering;
    setState(() {
      _recentColors = colors;
      _colorPalette = palette;
      _liveMarkdownRendering = liveRendering;
      _descriptionLimit = descriptionLimit;
    });
    if (rerender) _descriptionController.forceRepaint();
  }

  Future<void> _pickCategory() async {
    final picked = await CategoryPickerSheet.show(
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
        _kind = _RecurrenceKind.yearly;
        // Birthdays are the canonical occurrence-count use: with the birth
        // date as start, every occurrence shows the age. Pre-filled only on
        // the same fresh-event path as the yearly rule above; the style
        // follows yearly's default unless the user already chose one.
        _countOccurrences = true;
        if (!_countStyleTouched) {
          _countStyle = _defaultCountStyleFor(_RecurrenceKind.yearly);
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

  void _toggleWeekday(int weekday) {
    setState(() {
      final next = Set<int>.of(_weekdays);
      if (!next.add(weekday)) next.remove(weekday);
      _weekdays = next;
    });
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
        _kindSupportsInterval(_kind) &&
        _countOccurrences;
    final effectiveTime = _isAllDay
        ? null
        : EventTime(
            startMinute: _startMinute,
            durationMinutes: _durationMinutes,
          );
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
            rule: _buildRule(),
            endDate: effectiveEnd,
            retroactive: effectiveRetroactive,
            countOccurrences: effectiveCountOccurrences,
            countStyle: _countStyle,
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
            rule: _buildRule(),
            endDate: effectiveEnd,
            retroactive: effectiveRetroactive,
            countOccurrences: effectiveCountOccurrences,
            countStyle: _countStyle,
            time: effectiveTime,
            description: effectiveDescription,
            noteId: _noteId,
            iconKey: _iconKey,
            colorValue: _colorValue,
            tintIcon: _tintIcon,
            priority: _priority,
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
  /// Returns nothing at all once the form no longer describes a repeating
  /// rule: flipping to one-time must not merge an occurrence's text anywhere.
  (DateTime?, String?) _resolveOccurrenceOutcome(String template) {
    final day = widget.occurrenceDay;
    if (day == null || !_isEditing) return (null, null);
    if (!OccurrenceDescriptions.enabled || !_ruleHasManyOccurrences) {
      return (null, null);
    }
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

  // --- Build --------------------------------------------------------------

  /// Description input. The field stores raw markdown and renders it live
  /// (Obsidian-style) through the note editor's own span builder, so headers,
  /// lists, task boxes and inline styles read the same in both places and a
  /// tap on a checkbox toggles it. The money ledger is off (a balance is a
  /// per-note concept, so `$` rows in an event description stay literal text).
  ///
  /// The read-only preview toggle survives only for users who turned live
  /// rendering off — with it on, the editor already is the preview.
  Widget _buildDescriptionField(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    final showPreviewToggle = !_liveMarkdownRendering;
    final previewing = showPreviewToggle && _descriptionPreview;
    // Only the preview branch needs the joined source; the editor reads the
    // controller's lines directly.
    final text = previewing ? _descriptionController.text : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.eventDescription,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            // The counter follows the controller rather than `setState`, so a
            // keystroke repaints these few characters instead of the form.
            ListenableBuilder(
              listenable: _descriptionRevision,
              builder: (context, _) {
                final length = _descriptionController.textLength;
                // Reports the scope on screen, whose budget is its own.
                final over = !_activeScopeWithinLimit;
                return Text(
                  l10n.eventDescriptionCount(length, _descriptionLimit),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: over
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: over ? FontWeight.w600 : null,
                  ),
                );
              },
            ),
            if (showPreviewToggle)
              IconButton(
                tooltip: _descriptionPreview
                    ? l10n.eventDescriptionPreviewOff
                    : l10n.eventDescriptionPreviewOn,
                icon: Icon(
                  _descriptionPreview
                      ? Icons.edit_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () =>
                    setState(() => _descriptionPreview = !_descriptionPreview),
              ),
          ],
        ),
        if (_scopeControlVisible) ...[
          const SizedBox(height: 4),
          SegmentedButton<_DescriptionScope>(
            segments: [
              ButtonSegment(
                value: _DescriptionScope.allDays,
                label: Text(l10n.eventDescriptionScopeAllDays),
                icon: const Icon(Icons.repeat_rounded, size: 18),
              ),
              ButtonSegment(
                value: _DescriptionScope.thisDay,
                label: Text(l10n.eventDescriptionScopeThisDay),
                icon: const Icon(Icons.today_rounded, size: 18),
              ),
            ],
            selected: {_scope},
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            onSelectionChanged: (s) => _setScope(s.first),
          ),
          const SizedBox(height: 4),
          Text(
            _scope == _DescriptionScope.thisDay
                ? l10n.eventDescriptionScopeThisDayHint
                : l10n.eventDescriptionScopeAllDaysHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
        ],
        if (previewing)
          Container(
            constraints: const BoxConstraints(minHeight: 88, maxHeight: 220),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(4),
            ),
            child: text.trim().isEmpty
                ? Center(
                    child: Text(
                      l10n.eventDescriptionEmpty,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : SimpleMarkdownPreview(
                    data: text,
                    padding: const EdgeInsets.all(12),
                    colorPalette: _colorPalette,
                  ),
          )
        else
          Container(
            key: _descriptionKey,
            // A CodeEditor owns its own scroller, so it needs a bounded box
            // inside the sheet's scroll view. Long descriptions scroll in
            // place rather than stretching the form.
            constraints: const BoxConstraints(
              minHeight: _descriptionMinHeight,
              maxHeight: _descriptionMaxHeight,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(4),
            ),
            child: ModernEditorWrapper(
              controller: _descriptionController,
              focusNode: _descriptionFocus,
              scrollController: _descriptionScroll,
              searchController: _descriptionSearch,
              editorFontSize: FontConstants.defaultFontSize,
              onTextChanged: () {},
              checkboxTapToggle: _liveMarkdownRendering,
              showScrollIndicator: false,
            ),
          ),
        // Says *why* Save is disabled. Only appears once the description is
        // actually over budget, so the normal case has no extra row. Reports
        // whichever scope is on screen; `_canSave` checks both.
        ListenableBuilder(
          listenable: _descriptionRevision,
          builder: (context, _) {
            if (_activeScopeWithinLimit) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l10n.eventDescriptionTooLong(_descriptionLimit),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            );
          },
        ),
        // The only way back to the template once a day has its own text —
        // matching the template again is not enough, because a row that
        // exists always wins over it.
        if (_scopeControlVisible &&
            _scope == _DescriptionScope.thisDay &&
            _dayMaterialized &&
            !_dayResetRequested)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _resetDayToTemplate,
              icon: const Icon(Icons.settings_backup_restore_rounded, size: 18),
              label: Text(l10n.eventDescriptionResetDay),
            ),
          ),
      ],
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _descriptionController.makeCursorVisible();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final localeName = l10n.localeName;
    final category = CalendarCategories.resolve(_categoryId);
    final categoryColor = category.color;
    // All one-time dates (anchor + extras) as one uniform, sorted list.
    final oneTimeDates = <DateTime>{_date, ..._additionalDates}.toList()
      ..sort();
    // Custom (non-palette) color dots: the current custom color first, then
    // recently used ones, deduped and capped.
    final customColorDots = <int>{
      if (_isCustomColor) _colorValue!,
      ..._recentColors.where((c) => !CalendarColors.swatchPalette.contains(c)),
    }.take(SettingsKeys.maxRecentEventColors).toList();
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomClearance = viewInsets > viewPadding ? viewInsets : viewPadding;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomClearance),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: title + inline cancel/save so the action surface is part
          // of the sheet rather than detached at the bottom edge.
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: l10n.cancel,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(
                    _isEditing ? l10n.editEvent : l10n.addEvent,
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  // _canSave reads the description length, which changes
                  // without a form rebuild — so the button tracks the
                  // controller directly instead of forcing keystroke-wide
                  // setStates.
                  child: ListenableBuilder(
                    listenable: _descriptionRevision,
                    builder: (context, _) => FilledButton(
                      onPressed: _canSave ? _onSave : null,
                      child: Text(l10n.save),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Category-first: what kind of event this is comes before
                  // everything else — picking a category tailors the rest
                  // (the birthday built-in pre-fills yearly recurrence). No
                  // autofocus on the title for the same reason: a keyboard
                  // popping up would bury the category tile the flow starts
                  // with.
                  _GroupHeader(text: l10n.eventSectionWhat),
                  const SizedBox(height: 8),
                  _PickerTile(
                    leading: CircleAvatar(
                      backgroundColor: categoryColor.withValues(alpha: 0.18),
                      foregroundColor: categoryColor,
                      child: Icon(
                        CalendarIcons.forKey(category.iconKey) ??
                            Icons.event_rounded,
                      ),
                    ),
                    title: CalendarCategories.labelOf(category, l10n),
                    subtitle: l10n.pickCategory,
                    onTap: _pickCategory,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _titleController,
                    maxLength: 120,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: l10n.eventTitle,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  // Mode-first inside the When zone: the toggle decides what
                  // the rest of the zone renders (date chips vs start date +
                  // recurrence config), so it must sit above the content it
                  // switches — a control that mutates content above itself
                  // reads as if nothing happened.
                  _GroupHeader(text: l10n.eventSectionWhen),
                  _SectionLabel(text: l10n.repeatMode),
                  Center(
                    child: SegmentedButton<_RepeatMode>(
                      segments: [
                        ButtonSegment(
                          value: _RepeatMode.oneTime,
                          label: Text(l10n.repeatOnce),
                          icon: const Icon(Icons.looks_one_rounded),
                        ),
                        ButtonSegment(
                          value: _RepeatMode.recurring,
                          label: Text(l10n.repeatRecurring),
                          icon: const Icon(Icons.repeat_rounded),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (s) =>
                          setState(() {
                            _mode = s.first;
                            // Switching to one-time hides the scope control,
                            // so the field must stop showing a day's text.
                            _syncScopeToRule();
                          }),
                    ),
                  ),
                  if (_mode == _RepeatMode.oneTime) ...[
                    _SectionLabel(text: l10n.eventDatesLabel),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final d in oneTimeDates)
                          InputChip(
                            label: Text(DateFormat.yMMMd(localeName).format(d)),
                            onPressed: _pickOneTimeDates,
                            onDeleted: oneTimeDates.length > 1
                                ? () => _removeOneTimeDate(d)
                                : null,
                            deleteButtonTooltipMessage: l10n.eventRemoveDate,
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.add_rounded, size: 18),
                          label: Text(l10n.eventAddDate),
                          onPressed: _pickOneTimeDates,
                        ),
                      ],
                    ),
                    if (oneTimeDates.length == 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          l10n.eventDatesHint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ] else ...[
                    _SectionLabel(text: l10n.eventDate),
                    _PickerTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.calendar_today_rounded),
                      ),
                      title: DateFormat.yMMMMEEEEd(localeName).format(_date),
                      subtitle: l10n.startsOn,
                      onTap: _pickDate,
                    ),
                  ],
                  if (_mode == _RepeatMode.recurring) ...[
                    _SectionLabel(text: l10n.frequency),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final k in _RecurrenceKind.values)
                          ChoiceChip(
                            label: Text(_kindLabel(l10n, k)),
                            selected: _kind == k,
                            onSelected: (_) => setState(() {
                              _kind = k;
                              if (!_countStyleTouched) {
                                _countStyle = _defaultCountStyleFor(k);
                              }
                            }),
                          ),
                      ],
                    ),
                    if (_kindSupportsInterval(_kind)) ...[
                      _SectionLabel(text: l10n.recurrenceIntervalLabel),
                      _IntervalStepper(
                        value: _interval,
                        unitLabel: _intervalUnitLabel(l10n, _kind),
                        min: 1,
                        max: _maxInterval,
                        decrementTooltip: l10n.recurrenceIntervalDecrement,
                        incrementTooltip: l10n.recurrenceIntervalIncrement,
                        onChanged: (v) => setState(() => _interval = v),
                      ),
                    ],
                    if (_kind == _RecurrenceKind.weekly) ...[
                      _SectionLabel(text: l10n.weekdays),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var w = 1; w <= 7; w++)
                            FilterChip(
                              label: Text(
                                RecurrenceFormatter.weekdayShort(w, localeName),
                              ),
                              selected: _weekdays.contains(w),
                              onSelected: (_) => _toggleWeekday(w),
                            ),
                        ],
                      ),
                      if (_weekdays.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            l10n.weeklyDaysHint,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                    _SectionLabel(text: l10n.recurrenceScopeLabel),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(l10n.recurrenceScopeFromStart),
                          selected: !_retroactive,
                          onSelected: (_) =>
                              setState(() => _retroactive = false),
                        ),
                        ChoiceChip(
                          label: Text(_scopeAlwaysLabel(l10n)),
                          selected: _retroactive,
                          onSelected: (_) =>
                              setState(() => _retroactive = true),
                        ),
                      ],
                    ),
                    if (_retroactive)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          l10n.recurrenceScopeHint,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (_kindSupportsInterval(_kind)) ...[
                      const SizedBox(height: 16),
                      Card(
                        margin: EdgeInsets.zero,
                        child: SwitchListTile(
                          value: _countOccurrences,
                          onChanged: (v) =>
                              setState(() => _countOccurrences = v),
                          secondary: const CircleAvatar(
                            child: Icon(Icons.numbers_rounded),
                          ),
                          title: Text(l10n.eventCountOccurrences),
                          subtitle: Text(l10n.eventCountOccurrencesHint),
                        ),
                      ),
                      if (_countOccurrences) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final style in OccurrenceCountStyle.values)
                              ChoiceChip(
                                label: Text(_countStyleLabel(l10n, style)),
                                selected: _countStyle == style,
                                onSelected: (_) => setState(() {
                                  _countStyle = style;
                                  _countStyleTouched = true;
                                }),
                              ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _countStyleExample(l10n),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                    _SectionLabel(text: l10n.eventUntilLabel),
                    _PickerTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.event_busy_rounded),
                      ),
                      title: _endDate == null
                          ? l10n.eventUntilNone
                          : DateFormat.yMMMMEEEEd(localeName).format(_endDate!),
                      subtitle: _endDate == null ? l10n.eventUntilHint : null,
                      trailing: _endDate == null
                          ? const Icon(Icons.chevron_right_rounded)
                          : IconButton(
                              tooltip: l10n.resetToDefault,
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(() => _endDate = null),
                            ),
                      onTap: _pickEndDate,
                    ),
                  ],
                  _SectionLabel(text: l10n.eventTimeSection),
                  Card(
                    margin: EdgeInsets.zero,
                    child: SwitchListTile(
                      value: _isAllDay,
                      onChanged: _setAllDay,
                      secondary: const CircleAvatar(
                        child: Icon(Icons.schedule_rounded),
                      ),
                      title: Text(l10n.eventAllDay),
                      subtitle: Text(l10n.eventAllDayHint),
                    ),
                  ),
                  if (!_isAllDay) ...[
                    const SizedBox(height: 8),
                    _PickerTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.play_arrow_rounded),
                      ),
                      title: EventTimeFormatter.formatMinute(
                        _startMinute,
                        context,
                      ),
                      subtitle: l10n.eventStartTime,
                      onTap: _pickStartTime,
                    ),
                    const SizedBox(height: 8),
                    _PickerTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.stop_rounded),
                      ),
                      title: _durationMinutes == null
                          ? l10n.eventEndTimeNone
                          : EventTimeFormatter.formatMinute(
                              (_startMinute + _durationMinutes!) %
                                  EventTime.minutesPerDay,
                              context,
                            ),
                      subtitle: _durationMinutes == null
                          ? l10n.eventEndTimeHint
                          : (_startMinute + _durationMinutes! >=
                                    EventTime.minutesPerDay
                                ? l10n.eventCrossesMidnight
                                : l10n.eventEndTime),
                      trailing: _durationMinutes == null
                          ? const Icon(Icons.chevron_right_rounded)
                          : IconButton(
                              tooltip: l10n.resetToDefault,
                              icon: const Icon(Icons.close_rounded),
                              onPressed: _clearEndTime,
                            ),
                      onTap: _pickEndTime,
                    ),
                  ],
                  _GroupHeader(text: l10n.eventSectionDetails),
                  const SizedBox(height: 8),
                  _buildDescriptionField(context, l10n, theme),
                  _SectionLabel(text: l10n.iconLabel),
                  _PickerTile(
                    leading: CircleAvatar(
                      backgroundColor: categoryColor.withValues(alpha: 0.18),
                      foregroundColor: categoryColor,
                      child: Icon(
                        CalendarIcons.forKey(_iconKey) ??
                            CalendarIcons.forKey(category.iconKey) ??
                            Icons.event_rounded,
                      ),
                    ),
                    title: _iconKey == null
                        ? l10n.iconDefault
                        : l10n.iconCustom,
                    subtitle: l10n.pickIcon,
                    trailing: _iconKey == null
                        ? const Icon(Icons.chevron_right_rounded)
                        : IconButton(
                            tooltip: l10n.resetToDefault,
                            icon: const Icon(Icons.refresh_rounded),
                            onPressed: () => setState(() => _iconKey = null),
                          ),
                    onTap: _pickIcon,
                  ),
                  _SectionLabel(text: l10n.eventColor),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _EventColorDot(
                        color: categoryColor,
                        icon:
                            CalendarIcons.forKey(category.iconKey) ??
                            Icons.event_rounded,
                        selected: _colorValue == null,
                        onTap: () => setState(() => _colorValue = null),
                      ),
                      for (final swatch in CalendarColors.swatchPalette)
                        _EventColorDot(
                          color: Color(swatch),
                          selected: _colorValue == swatch,
                          onTap: () => setState(() => _colorValue = swatch),
                        ),
                      for (final c in customColorDots)
                        _EventColorDot(
                          color: Color(c),
                          selected: _colorValue == c,
                          onTap: () => setState(() => _colorValue = c),
                        ),
                      _EventColorDot(
                        icon: Icons.colorize_rounded,
                        selected: false,
                        onTap: _pickCustomColor,
                      ),
                    ],
                  ),
                  if (_colorValue != null) ...[
                    const SizedBox(height: 8),
                    Card(
                      margin: EdgeInsets.zero,
                      child: SwitchListTile(
                        value: _tintIcon,
                        onChanged: (v) => setState(() => _tintIcon = v),
                        secondary: const CircleAvatar(
                          child: Icon(Icons.brush_rounded),
                        ),
                        title: Text(l10n.eventTintIcon),
                        subtitle: Text(l10n.eventTintIconHint),
                      ),
                    ),
                  ],
                  _SectionLabel(text: l10n.eventPriority),
                  // One chip per level, P1 (highest) first. Chips replaced
                  // the numeric stepper when the scale flipped to
                  // 1-is-highest: a "+" that lowers priority (or raises the
                  // number while the label says Higher) cannot be made
                  // unambiguous, while a labeled, iconed chip can.
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (
                        var p = kMinEventPriority;
                        p <= kMaxEventPriority;
                        p++
                      )
                        ChoiceChip(
                          avatar: Icon(EventPriorities.iconFor(p), size: 18),
                          label: Text(EventPriorities.labelOf(p, l10n)),
                          visualDensity: VisualDensity.compact,
                          selected: _priority == p,
                          onSelected: (selected) {
                            if (selected) setState(() => _priority = p);
                          },
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      l10n.eventPriorityHint,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  _SectionLabel(text: l10n.eventLinkedNote),
                  _PickerTile(
                    leading: CircleAvatar(
                      backgroundColor: _noteMissing
                          ? theme.colorScheme.errorContainer
                          : null,
                      foregroundColor: _noteMissing
                          ? theme.colorScheme.onErrorContainer
                          : null,
                      child: Icon(
                        _noteId == null
                            ? Icons.note_add_outlined
                            : (_noteMissing
                                  ? Icons.warning_amber_rounded
                                  : Icons.sticky_note_2_outlined),
                      ),
                    ),
                    title: _noteId == null
                        ? l10n.eventLinkNoteHint
                        : (_noteMissing
                              ? l10n.eventLinkedNoteMissing
                              : ((_noteTitle == null || _noteTitle!.isEmpty)
                                    ? l10n.untitledNote
                                    : _noteTitle!)),
                    subtitle: _noteId == null ? null : l10n.selectNote,
                    trailing: _noteId == null
                        ? const Icon(Icons.chevron_right_rounded)
                        : IconButton(
                            tooltip: l10n.eventRemoveNoteLink,
                            icon: const Icon(Icons.link_off_rounded),
                            onPressed: _clearNote,
                          ),
                    onTap: _pickNote,
                  ),
                  if (_isEditing) ...[
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _onDelete,
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.errorContainer,
                        foregroundColor: theme.colorScheme.onErrorContainer,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      icon: const Icon(Icons.delete_rounded),
                      label: Text(l10n.delete),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _descriptionFocused
                ? _buildDescriptionBar()
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// Accent-colored group divider splitting the editor into its three zones
/// (what / when / details). One visual level above [_SectionLabel], which
/// keeps naming the individual fields inside each zone.
class _GroupHeader extends StatelessWidget {
  final String text;
  const _GroupHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Row(
        children: [
          Text(
            text,
            style: theme.textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Divider(color: color.withValues(alpha: 0.25), height: 1),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Compact "− N +" stepper for the recurrence interval, with the unit label
/// ("weeks", "months", …) next to the value so the row reads as a sentence
/// ("Repeat every  −  2  +  weeks"). Buttons disable at [min] / [max].
class _IntervalStepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final String unitLabel;
  final String decrementTooltip;
  final String incrementTooltip;
  final ValueChanged<int> onChanged;

  const _IntervalStepper({
    required this.value,
    required this.min,
    required this.max,
    required this.unitLabel,
    required this.decrementTooltip,
    required this.incrementTooltip,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canDecrement = value > min;
    final canIncrement = value < max;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton.filledTonal(
              tooltip: decrementTooltip,
              icon: const Icon(Icons.remove_rounded),
              onPressed: canDecrement ? () => onChanged(value - 1) : null,
            ),
            SizedBox(
              width: 40,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
            ),
            IconButton.filledTonal(
              tooltip: incrementTooltip,
              icon: const Icon(Icons.add_rounded),
              onPressed: canIncrement ? () => onChanged(value + 1) : null,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(unitLabel, style: theme.textTheme.bodyLarge)),
          ],
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _PickerTile({
    required this.leading,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: leading,
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

/// A circular color choice used in the event editor's color picker. A `null`
/// [color] paints a rainbow sweep to represent the "custom" entry; a non-null
/// [color] fills the dot. Shows a check when [selected], otherwise [icon].
class _EventColorDot extends StatelessWidget {
  final Color? color;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  const _EventColorDot({
    required this.selected,
    required this.onTap,
    this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = color;
    final foreground = fill == null
        ? Colors.white
        : (ThemeData.estimateBrightnessForColor(fill) == Brightness.dark
              ? Colors.white
              : Colors.black);
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: fill,
          gradient: fill == null
              ? const SweepGradient(
                  colors: [
                    Color(0xFFE53935),
                    Color(0xFFFFB300),
                    Color(0xFF43A047),
                    Color(0xFF00ACC1),
                    Color(0xFF3949AB),
                    Color(0xFF8E24AA),
                    Color(0xFFE53935),
                  ],
                )
              : null,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: theme.colorScheme.onSurface, width: 3)
              : Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: selected
            ? Icon(Icons.check_rounded, color: foreground, size: 22)
            : (icon != null ? Icon(icon, color: foreground, size: 20) : null),
      ),
    );
  }
}
