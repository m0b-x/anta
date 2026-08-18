import 'package:flutter/material.dart';

import '../constants/calendar_categories.dart';
import '../constants/calendar_colors.dart';
import '../constants/calendar_icons.dart';
import '../constants/event_priorities.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/event_template.dart';
import '../models/recurrence_rule.dart';
import '../services/event_template_service.dart';
import 'category_picker_sheet.dart';
import 'icon_picker_sheet.dart';

/// Repeat shape a template can capture. `SpecificDatesRecurrence` is
/// deliberately absent: a template carries no dates, so a set of explicit ones
/// is meaningless and collapses to [_TemplateRepeat.once] on capture.
enum _TemplateRepeat { once, daily, weekly, monthly, yearly, workdays, weekends }

/// Bottom-sheet form for creating or editing an [EventTemplate].
///
/// Persists through [EventTemplateService] and returns the saved template (or
/// `null` if cancelled). Mirrors `CategoryEditorSheet`'s shell — inline header
/// with `close | title | Save`, never a bottom action bar — and the event
/// editor's controls for the fields the two share, so a template is configured
/// exactly the way the event it produces would be.
class EventTemplateEditorSheet extends StatefulWidget {
  final EventTemplate? initial;

  /// Pre-filled draft for "save as template", where every field is already
  /// decided by the event form the user just built. Ignored when [initial] is
  /// set — editing an existing template starts from that template.
  final EventTemplate? draft;

  const EventTemplateEditorSheet({super.key, this.initial, this.draft});

  static Future<EventTemplate?> show(
    BuildContext context, {
    EventTemplate? initial,
    EventTemplate? draft,
  }) {
    return showModalBottomSheet<EventTemplate>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: EventTemplateEditorSheet(initial: initial, draft: draft),
      ),
    );
  }

  @override
  State<EventTemplateEditorSheet> createState() =>
      _EventTemplateEditorSheetState();
}

class _EventTemplateEditorSheetState extends State<EventTemplateEditorSheet> {
  static const int _defaultStartMinute = 9 * 60;
  static const int _defaultDurationMinutes = 60;

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  late String _categoryId;
  late _TemplateRepeat _repeat;
  late Set<int> _weekdays;
  late int _interval;
  late bool _allDay;
  late int _startMinute;
  int? _durationMinutes;
  String? _iconKey;
  int? _colorValue;
  late bool _tintIcon;
  late int _priority;
  late bool _tracksPresence;
  late bool _perOccurrenceDescriptions;
  late bool _countOccurrences;
  late OccurrenceCountStyle _countStyle;
  late bool _retroactive;

  bool _saving = false;

  bool get _isEditing => widget.initial != null;

  /// The flags below only mean anything for a rule with more than one
  /// occurrence — the same gate the event editor applies on save.
  bool get _repeats => _repeat != _TemplateRepeat.once;

  @override
  void initState() {
    super.initState();
    final source = widget.initial ?? widget.draft;
    _nameController = TextEditingController(text: source?.name ?? '');
    _descriptionController = TextEditingController(
      text: source?.description ?? '',
    );
    _categoryId = source?.categoryId ?? kDefaultCategoryId;

    final rule = source?.rule ?? const OneTimeRecurrence();
    _repeat = _repeatOf(rule);
    _weekdays = rule is WeeklyRecurrence ? {...rule.weekdays} : <int>{};
    _interval = _intervalOf(rule);

    final time = source?.time;
    _allDay = time == null;
    _startMinute = time?.startMinute ?? _defaultStartMinute;
    _durationMinutes = time?.durationMinutes;

    _iconKey = source?.iconKey;
    _colorValue = source?.colorValue;
    _tintIcon = source?.tintIcon ?? true;
    _priority = source?.priority ?? kDefaultEventPriority;
    _tracksPresence = source?.tracksPresence ?? false;
    _perOccurrenceDescriptions = source?.perOccurrenceDescriptions ?? false;
    _countOccurrences = source?.countOccurrences ?? false;
    _countStyle = source?.countStyle ?? OccurrenceCountStyle.numbered;
    _retroactive = source?.retroactive ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  static _TemplateRepeat _repeatOf(RecurrenceRule rule) => switch (rule) {
    DailyRecurrence() => _TemplateRepeat.daily,
    WeeklyRecurrence() => _TemplateRepeat.weekly,
    MonthlyRecurrence() => _TemplateRepeat.monthly,
    YearlyRecurrence() => _TemplateRepeat.yearly,
    WorkdaysRecurrence() => _TemplateRepeat.workdays,
    WeekendsRecurrence() => _TemplateRepeat.weekends,
    // Holidays-only and specific-dates both collapse: the first has no
    // template-level knob to configure, the second carries dates.
    _ => _TemplateRepeat.once,
  };

  static int _intervalOf(RecurrenceRule rule) => switch (rule) {
    DailyRecurrence(:final interval) => interval,
    WeeklyRecurrence(:final interval) => interval,
    MonthlyRecurrence(:final interval) => interval,
    YearlyRecurrence(:final interval) => interval,
    _ => 1,
  };

  RecurrenceRule get _rule => switch (_repeat) {
    _TemplateRepeat.once => const OneTimeRecurrence(),
    _TemplateRepeat.daily => DailyRecurrence(interval: _interval),
    _TemplateRepeat.weekly => WeeklyRecurrence(
      weekdays: _weekdays,
      interval: _interval,
    ),
    _TemplateRepeat.monthly => MonthlyRecurrence(interval: _interval),
    _TemplateRepeat.yearly => YearlyRecurrence(interval: _interval),
    _TemplateRepeat.workdays => const WorkdaysRecurrence(),
    _TemplateRepeat.weekends => const WeekendsRecurrence(),
  };

  bool get _canSave => !_saving && _nameController.text.trim().isNotEmpty;

  /// Whether the interval stepper applies. The contextual kinds (workdays,
  /// weekends) have no "every N" to configure.
  bool get _hasInterval =>
      _repeat == _TemplateRepeat.daily ||
      _repeat == _TemplateRepeat.weekly ||
      _repeat == _TemplateRepeat.monthly ||
      _repeat == _TemplateRepeat.yearly;

  Color get _tint => _colorValue != null
      ? Color(_colorValue!)
      : CalendarCategories.resolve(_categoryId).color;

  IconData get _icon {
    final override = CalendarIcons.forKey(_iconKey);
    if (override != null) return override;
    final category = CalendarCategories.resolve(_categoryId);
    return CalendarIcons.forKey(category.iconKey) ?? Icons.event_rounded;
  }

  Future<void> _pickCategory() async {
    final picked = await CategoryPickerSheet.show(
      context,
      selectedId: _categoryId,
    );
    if (picked == null || !mounted) return;
    setState(() => _categoryId = picked);
  }

  Future<void> _pickIcon() async {
    final picked = await IconPickerSheet.show(
      context,
      tint: _tint,
      initialKey: _iconKey,
    );
    if (picked == null || !mounted) return;
    setState(() => _iconKey = picked);
  }

  Future<void> _pickTime({required bool start}) async {
    final base = start
        ? _startMinute
        : (_startMinute + (_durationMinutes ?? _defaultDurationMinutes));
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: (base ~/ 60) % 24,
        minute: base % 60,
      ),
    );
    if (picked == null || !mounted) return;
    final minutes = picked.hour * 60 + picked.minute;
    setState(() {
      if (start) {
        _startMinute = minutes;
      } else {
        // An end before the start would be a negative duration; treat it as
        // spanning midnight, exactly as the event editor's time range does.
        final raw = minutes - _startMinute;
        _durationMinutes = raw > 0 ? raw : raw + EventTime.minutesPerDay;
      }
    });
  }

  EventTemplate _buildTemplate() {
    final description = _descriptionController.text.trim();
    return EventTemplate(
      id: widget.initial?.id ?? '',
      name: _nameController.text.trim(),
      categoryId: _categoryId,
      rule: _rule,
      time: _allDay
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
      // Cleared rather than parked when the rule cannot carry them, so a
      // template never stores a flag its own rule contradicts.
      retroactive: _repeats && _retroactive,
      countOccurrences: _repeats && _countOccurrences,
      countStyle: _countStyle,
      tracksPresence: _repeats && _tracksPresence,
      perOccurrenceDescriptions: _repeats && _perOccurrenceDescriptions,
      sortOrder: widget.initial?.sortOrder ?? 0,
    );
  }

  Future<void> _onSave() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final service = await EventTemplateService.getInstance();
    final template = _buildTemplate();
    final EventTemplate saved;
    if (widget.initial == null) {
      saved = await service.create(template);
    } else {
      await service.updateTemplate(template);
      saved = template;
    }
    if (!mounted) return;
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomClearance = viewInsets > viewPadding ? viewInsets : viewPadding;
    final category = CalendarCategories.resolve(_categoryId);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomClearance),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                    _isEditing ? l10n.editTemplate : l10n.createTemplate,
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
                  Center(
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: _tint.withValues(alpha: 0.18),
                      foregroundColor: _tint,
                      child: Icon(_icon, size: 28),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Category first, exactly as in the event editor: picking it
                  // decides the colour and icon everything below falls back to.
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: category.color.withValues(alpha: 0.18),
                        foregroundColor: category.color,
                        child: Icon(
                          CalendarIcons.forKey(category.iconKey) ??
                              Icons.event_rounded,
                        ),
                      ),
                      title: Text(l10n.eventType),
                      subtitle: Text(
                        CalendarCategories.labelOf(category, l10n),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _pickCategory,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    autofocus: !_isEditing && widget.draft == null,
                    maxLength: 60,
                    textInputAction: TextInputAction.done,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: l10n.templateName,
                      hintText: l10n.templateNameHint,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),

                  _SectionLabel(text: l10n.repeatMode),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final repeat in _TemplateRepeat.values)
                        ChoiceChip(
                          label: Text(_repeatLabel(l10n, repeat)),
                          visualDensity: VisualDensity.compact,
                          selected: _repeat == repeat,
                          onSelected: (selected) {
                            if (selected) setState(() => _repeat = repeat);
                          },
                        ),
                    ],
                  ),
                  if (_hasInterval) ...[
                    const SizedBox(height: 12),
                    _IntervalStepper(
                      value: _interval,
                      onChanged: (value) => setState(() => _interval = value),
                    ),
                  ],
                  if (_repeat == _TemplateRepeat.weekly) ...[
                    const SizedBox(height: 12),
                    _WeekdaySelector(
                      selected: _weekdays,
                      onToggle: (day) => setState(() {
                        if (!_weekdays.remove(day)) _weekdays.add(day);
                      }),
                    ),
                  ],

                  _SectionLabel(text: l10n.eventTimeSection),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _allDay,
                    title: Text(l10n.eventAllDay),
                    subtitle: Text(l10n.eventAllDayHint),
                    onChanged: (value) => setState(() => _allDay = value),
                  ),
                  if (!_allDay) ...[
                    Card(
                      margin: EdgeInsets.zero,
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.schedule_rounded),
                            title: Text(l10n.eventStartTime),
                            subtitle: Text(_formatMinutes(context, _startMinute)),
                            onTap: () => _pickTime(start: true),
                          ),
                          ListTile(
                            leading: const Icon(Icons.timelapse_rounded),
                            title: Text(l10n.eventEndTime),
                            subtitle: Text(
                              _durationMinutes == null
                                  ? l10n.eventEndTimeNone
                                  : _formatMinutes(
                                      context,
                                      (_startMinute + _durationMinutes!) %
                                          EventTime.minutesPerDay,
                                    ),
                            ),
                            trailing: _durationMinutes == null
                                ? null
                                : IconButton(
                                    tooltip: l10n.eventEndTimeNone,
                                    icon: const Icon(Icons.clear_rounded),
                                    onPressed: () => setState(
                                      () => _durationMinutes = null,
                                    ),
                                  ),
                            onTap: () => _pickTime(start: false),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  TextField(
                    controller: _descriptionController,
                    maxLines: 5,
                    minLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: l10n.eventDescription,
                      alignLabelWithHint: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),

                  _SectionLabel(text: l10n.iconLabel),
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _tint.withValues(alpha: 0.18),
                        foregroundColor: _tint,
                        child: Icon(_icon),
                      ),
                      title: Text(l10n.pickIcon),
                      trailing: _iconKey == null
                          ? const Icon(Icons.chevron_right_rounded)
                          : IconButton(
                              tooltip: l10n.reset,
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () => setState(() => _iconKey = null),
                            ),
                      onTap: _pickIcon,
                    ),
                  ),

                  _SectionLabel(text: l10n.eventColor),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      // The category default reads as a swatch of its own, so
                      // "no override" is a choice rather than a missing one.
                      _ColorDot(
                        color: category.color,
                        icon: Icons.auto_awesome_rounded,
                        tooltip: l10n.categoryDefault,
                        selected: _colorValue == null,
                        onTap: () => setState(() => _colorValue = null),
                      ),
                      for (final swatch in CalendarColors.swatchPalette)
                        _ColorDot(
                          color: Color(swatch),
                          selected: _colorValue == swatch,
                          onTap: () => setState(() => _colorValue = swatch),
                        ),
                    ],
                  ),
                  if (_colorValue != null)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _tintIcon,
                      title: Text(l10n.eventTintIcon),
                      onChanged: (value) => setState(() => _tintIcon = value),
                    ),

                  _SectionLabel(text: l10n.eventPriority),
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

                  // The repeat-only options. Hidden rather than disabled for a
                  // one-time template: there is nothing to explain, and the
                  // save path clears them anyway.
                  if (_repeats) ...[
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _tracksPresence,
                      title: Text(l10n.eventTrackPresence),
                      subtitle: Text(l10n.eventTrackPresenceDesc),
                      onChanged: (value) =>
                          setState(() => _tracksPresence = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _perOccurrenceDescriptions,
                      title: Text(l10n.eventPerOccurrenceDescriptions),
                      subtitle: Text(l10n.eventPerOccurrenceDescriptionsDesc),
                      onChanged: (value) =>
                          setState(() => _perOccurrenceDescriptions = value),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _countOccurrences,
                      title: Text(l10n.eventCountOccurrences),
                      subtitle: Text(l10n.eventCountOccurrencesHint),
                      onChanged: (value) =>
                          setState(() => _countOccurrences = value),
                    ),
                    // Scope is chips, not a switch — the same control the
                    // event editor uses, so the two forms cannot describe the
                    // same field in two different vocabularies.
                    _SectionLabel(text: l10n.recurrenceScopeLabel),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(l10n.recurrenceScopeFromStart),
                          visualDensity: VisualDensity.compact,
                          selected: !_retroactive,
                          onSelected: (_) =>
                              setState(() => _retroactive = false),
                        ),
                        ChoiceChip(
                          label: Text(
                            _repeat == _TemplateRepeat.yearly
                                ? l10n.recurrenceScopeEveryYear
                                : l10n.recurrenceScopeAlways,
                          ),
                          visualDensity: VisualDensity.compact,
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
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _repeatLabel(AppLocalizations l10n, _TemplateRepeat repeat) {
    return switch (repeat) {
      _TemplateRepeat.once => l10n.repeatOnce,
      _TemplateRepeat.daily => l10n.recurrenceDaily,
      _TemplateRepeat.weekly => l10n.recurrenceWeekly,
      _TemplateRepeat.monthly => l10n.recurrenceMonthly,
      _TemplateRepeat.yearly => l10n.recurrenceYearly,
      _TemplateRepeat.workdays => l10n.recurrenceWorkdays,
      _TemplateRepeat.weekends => l10n.recurrenceWeekends,
    };
  }

  static String _formatMinutes(BuildContext context, int minutes) {
    // `TimeOfDay.format` honours the locale's 24h/12h preference, which is
    // where every other time label in the calendar gets it from.
    return TimeOfDay(
      hour: (minutes ~/ 60) % 24,
      minute: minutes % 60,
    ).format(context);
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

/// "Every N" stepper, clamped to 1..99 like the event editor's.
class _IntervalStepper extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _IntervalStepper({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text('$value', style: theme.textTheme.titleLarge),
        ),
        IconButton.filledTonal(
          onPressed: value < 99 ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

/// Weekday toggles for a weekly rule. Labels come from `intl` via the
/// localized `MaterialLocalizations`, never an ARB weekday matrix.
class _WeekdaySelector extends StatelessWidget {
  final Set<int> selected;
  final ValueChanged<int> onToggle;

  const _WeekdaySelector({required this.selected, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final materialL10n = MaterialLocalizations.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (var day = DateTime.monday; day <= DateTime.sunday; day++)
          FilterChip(
            label: Text(
              materialL10n.narrowWeekdays[day % DateTime.daysPerWeek],
            ),
            visualDensity: VisualDensity.compact,
            selected: selected.contains(day),
            onSelected: (_) => onToggle(day),
          ),
      ],
    );
  }
}

/// Tappable colour dot, mirroring the event editor's swatch row.
class _ColorDot extends StatelessWidget {
  final Color color;
  final IconData? icon;
  final String? tooltip;
  final bool selected;
  final VoidCallback onTap;

  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
    this.icon,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    final dot = InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? theme.colorScheme.onSurface
                : theme.colorScheme.outlineVariant,
            width: selected ? 2.5 : 1,
          ),
        ),
        child: Icon(
          selected ? Icons.check_rounded : icon,
          size: 20,
          color: onColor,
        ),
      ),
    );
    return tooltip == null ? dot : Tooltip(message: tooltip!, child: dot);
  }
}
