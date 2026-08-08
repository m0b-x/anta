import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../constants/calendar_categories.dart';
import '../constants/calendar_colors.dart';
import '../constants/calendar_icons.dart';
import '../constants/event_priorities.dart';
import '../constants/settings_keys.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_appearance.dart';
import '../models/calendar_event.dart';
import '../models/recurrence_rule.dart';
import '../repositories/note_repository.dart';
import '../services/event_time_formatter.dart';
import '../services/recurrence_formatter.dart';
import '../services/settings_service.dart';
import '../utils/markdown_color_syntax.dart';
import 'calendar_date_picker_sheet.dart';
import 'category_picker_sheet.dart';
import 'color_wheel_picker.dart';
import 'icon_picker_sheet.dart';
import 'note_picker_dialog.dart';
import 'simple_markdown_preview.dart';

/// Result returned by [EventEditorSheet.show]. `null` means cancelled.
sealed class EventEditorResult {
  const EventEditorResult();
}

class EventEditorSaved extends EventEditorResult {
  final CalendarEvent event;
  const EventEditorSaved(this.event);
}

class EventEditorDeleted extends EventEditorResult {
  final String id;
  const EventEditorDeleted(this.id);
}

/// Top-level repeat mode shown as a segmented control.
enum _RepeatMode { oneTime, recurring }

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
    this.dayLoad,
    this.appearance = const CalendarAppearance(),
  });

  static Future<EventEditorResult?> show(
    BuildContext context, {
    required DateTime defaultDate,
    CalendarEvent? initialEvent,
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

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
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
  bool _descriptionPreview = false;

  /// Resolved markdown colour palette for the description preview, so
  /// `{name:text}` runs show the user's custom colours.
  MarkdownColorPalette _colorPalette = MarkdownColorPalette.presets;

  bool get _isEditing => widget.initialEvent != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialEvent;
    _titleController = TextEditingController(text: initial?.title ?? '');
    _descriptionController = TextEditingController(
      text: initial?.description ?? '',
    );
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
    _countStyle = initial?.countStyle ?? OccurrenceCountStyle.numbered;
    _initRecurrenceFrom(initial?.rule ?? const OneTimeRecurrence());
    if (_noteId != null) _loadLinkedNoteTitle();
    _loadRecentColors();
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
    _descriptionController.dispose();
    super.dispose();
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

  /// Three sample labels for the current kind + style ("Day 1 · Day 2 ·
  /// Day 3", "1 year · 2 years · 3 years") so the style choice explains
  /// itself without prose. For the elapsed style the samples start at the
  /// second occurrence — the start day deliberately shows nothing there.
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

    return '${at(1)} · ${at(2)} · ${at(3)}';
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
    return true;
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
    // Fixed wide bounds, not a window around the current date: a birthday's
    // start is the birth year, which a ±20-year slide can never reach.
    final picked = await CalendarDatePickerSheet.pickSingle(
      context,
      initialDate: _date,
      firstDate: CalendarDatePickerSheet.earliestDate,
      lastDate: CalendarDatePickerSheet.latestDate,
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
      lastDate: CalendarDatePickerSheet.latestDate,
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
      firstDate: CalendarDatePickerSheet.earliestDate,
      lastDate: CalendarDatePickerSheet.latestDate,
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

  Future<void> _loadRecentColors() async {
    final settings = await SettingsService.getInstance();
    final colors = await settings.getRecentEventColors();
    final palette = await settings.getColorPalette();
    if (!mounted) return;
    setState(() {
      _recentColors = colors;
      _colorPalette = palette;
    });
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
        // date as start, every occurrence shows the age — which is the
        // elapsed style, not the numbered default. Pre-filled only on the
        // same fresh-event path as the yearly rule above.
        _countOccurrences = true;
        _countStyle = OccurrenceCountStyle.elapsed;
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
    final description = _descriptionController.text.trim();
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
    Navigator.of(context).pop(EventEditorSaved(event));
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

  /// Description input with a preview toggle. The field stores raw markdown;
  /// the preview renders it through the same builder the note preview uses,
  /// with the money ledger off (a balance is a per-note concept, so `$` rows
  /// in an event description stay literal text).
  Widget _buildDescriptionField(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    final text = _descriptionController.text;
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
        if (_descriptionPreview)
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
          TextField(
            controller: _descriptionController,
            maxLength: 2000,
            minLines: 2,
            maxLines: 5,
            textInputAction: TextInputAction.newline,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              hintText: l10n.eventDescriptionHint,
              border: const OutlineInputBorder(),
            ),
          ),
      ],
    );
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
                  child: FilledButton(
                    onPressed: _canSave ? _onSave : null,
                    child: Text(l10n.save),
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
                          setState(() => _mode = s.first),
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
                            onSelected: (_) => setState(() => _kind = k),
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
                                onSelected: (_) =>
                                    setState(() => _countStyle = style),
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
