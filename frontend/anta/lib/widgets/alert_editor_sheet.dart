import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import '../constants/event_alerts.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/event_alert.dart';
import '../services/alert_gateway.dart';
import '../services/event_time_formatter.dart';
import 'automation_id.dart';

/// What the sheet reports back. `null` from [AlertEditorSheet.show] means the
/// user closed it without deciding anything.
sealed class AlertEditorResult {
  const AlertEditorResult();
}

/// The alert as it now stands, plus the event-level "remove after it rings"
/// decision the sheet is allowed to carry (**A3**).
///
/// The switch rides the result rather than being written here for the same
/// reason the event editor writes nothing: the sheet is a draft surface, and
/// the page that owns the event is the one place its row is persisted.
class AlertEditorSaved extends AlertEditorResult {
  final EventAlert alert;
  final bool removeAfterAlert;

  const AlertEditorSaved(this.alert, {this.removeAfterAlert = false});
}

/// The user asked for this alert to go away.
class AlertEditorRemoved extends AlertEditorResult {
  const AlertEditorRemoved();
}

/// Which free-form unit the custom offset row is counting in. Only ever a
/// *view* of [EventAlert.offsetMinutes] — the model stores minutes and nothing
/// else, so a unit can never be persisted out of step with a number.
enum _OffsetUnit {
  minutes(1),
  hours(Duration.minutesPerHour),
  days(EventAlert.minutesPerDay);

  final int multiplier;

  const _OffsetUnit(this.multiplier);
}

/// Draft-and-Save editor for exactly one [EventAlert] (§5.2).
///
/// Nothing here writes: the sheet pops with an [AlertEditorResult] and the
/// surface that owns the event — the event editor, or the Calendar settings
/// row holding a default — decides what that means. That is what lets the same
/// sheet edit an alert on an event and the template a new event is seeded
/// from, without either path growing a second copy of the timing controls.
///
/// [event] is what decides whether the timing section asks for minutes before
/// a start or for a day and a time: the derived [CalendarEvent.allDay], never
/// a flag of its own. Both offset sets survive the edit either way, exactly as
/// [EventAlert] promises.
class AlertEditorSheet extends StatefulWidget {
  /// The alert being edited. A brand-new one arrives seeded, so there is no
  /// "create" mode to tell apart.
  final EventAlert alert;

  /// The event the alert belongs to — or a stand-in with the right
  /// [CalendarEvent.allDay] shape when a settings default is being edited.
  final CalendarEvent event;

  /// Whether the footer offers to remove this alert. False for the settings
  /// defaults, where removal means something else entirely ("no default"), and
  /// true everywhere an alert actually exists on an event.
  final bool canRemove;

  /// Whether the **event-level** remove-after-it-rings switch is offered here.
  /// Only for a one-time event, and only while the alert is an alarm — the
  /// same rule the event editor's own copy of the switch follows.
  final bool showRemoveAfter;

  final bool removeAfterAlert;

  const AlertEditorSheet({
    super.key,
    required this.alert,
    required this.event,
    this.canRemove = true,
    this.showRemoveAfter = false,
    this.removeAfterAlert = false,
  });

  static Future<AlertEditorResult?> show(
    BuildContext context, {
    required EventAlert alert,
    required CalendarEvent event,
    bool canRemove = true,
    bool showRemoveAfter = false,
    bool removeAfterAlert = false,
  }) {
    return showModalBottomSheet<AlertEditorResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.7,
        child: AlertEditorSheet(
          alert: alert,
          event: event,
          canRemove: canRemove,
          showRemoveAfter: showRemoveAfter,
          removeAfterAlert: removeAfterAlert,
        ),
      ),
    );
  }

  /// A blank alert for [eventId], seeded from the settings default that
  /// matches [allDay].
  ///
  /// The one place a new alert is minted, so the editor's "Add alert" and the
  /// first alert of a brand-new event cannot disagree about what a default
  /// means.
  static EventAlert draft({
    required String eventId,
    required bool allDay,
    TimedAlertDefault? timedDefault,
    AllDayAlertDefault? allDayDefault,
  }) {
    if (allDay) {
      return EventAlert(
        id: const Uuid().v4(),
        eventId: eventId,
        mode: allDayDefault?.mode ?? AlertMode.notify,
        daysBefore: allDayDefault?.daysBefore ?? 0,
        dayMinute: allDayDefault?.dayMinute,
      );
    }
    return EventAlert(
      id: const Uuid().v4(),
      eventId: eventId,
      mode: timedDefault?.mode ?? AlertMode.notify,
      offsetMinutes: timedDefault?.offsetMinutes ?? 0,
    );
  }

  @override
  State<AlertEditorSheet> createState() => _AlertEditorSheetState();
}

class _AlertEditorSheetState extends State<AlertEditorSheet> {
  /// Offsets the timed chips offer, in minutes. "At start" is the leading
  /// zero; everything else is what a calendar app is expected to have without
  /// a trip through Custom.
  static const List<int> _timedPresets = [
    0,
    5,
    10,
    15,
    30,
    Duration.minutesPerHour,
    EventAlert.minutesPerDay,
  ];

  /// Whole days the all-day chips offer.
  static const List<int> _allDayPresets = [0, 1, 7];

  /// Ceilings for the custom row, per unit. Generous rather than principled:
  /// the horizon (30 days) is what actually bounds a usable offset, and these
  /// only keep the stepper from running away under a held finger.
  static const Map<_OffsetUnit, int> _customMax = {
    _OffsetUnit.minutes: 59,
    _OffsetUnit.hours: 23,
    _OffsetUnit.days: 30,
  };

  late AlertMode _mode;
  late int _offsetMinutes;
  late int _daysBefore;
  late int? _dayMinute;
  late bool _removeAfter;

  /// Whether the free-form row is open. Sticky once opened, so a value that
  /// happens to land on a preset does not fold the row away mid-edit.
  late bool _customOpen;
  late _OffsetUnit _customUnit;
  late int _customValue;

  /// Whether the platform will let an alarm take over the screen. Null until
  /// the gateway has answered; the warning only appears on a definite "no",
  /// so a slow round trip never accuses a phone that is fine.
  bool? _fullScreenAllowed;

  bool get _allDay => widget.event.allDay;

  @override
  void initState() {
    super.initState();
    final alert = widget.alert;
    _mode = alert.mode;
    _offsetMinutes = alert.offsetMinutes;
    _daysBefore = alert.daysBefore;
    _dayMinute = alert.dayMinute;
    _removeAfter = widget.removeAfterAlert;
    _customOpen = _allDay
        ? !_allDayPresets.contains(_daysBefore)
        : !_timedPresets.contains(_offsetMinutes);
    final unit = _unitFor(_allDay ? _daysBefore * EventAlert.minutesPerDay : _offsetMinutes);
    _customUnit = _allDay ? _OffsetUnit.days : unit;
    _customValue = _customValueFor(_customUnit);
    _resolvePermissions();
  }

  /// Asks the gateway once whether full-screen alarms are allowed, so the
  /// alarm hint can say what will actually happen. Best-effort: a build with
  /// no binding, or a platform that cannot answer, simply says nothing.
  Future<void> _resolvePermissions() async {
    AlertGateway? gateway;
    try {
      gateway = GetIt.I<AlertGateway>();
    } catch (_) {
      return;
    }
    final permissions = await gateway.permissions();
    if (!mounted) return;
    setState(() {
      _fullScreenAllowed =
          permissions.fullScreenIntent != AlertPermissionState.denied;
    });
  }

  static _OffsetUnit _unitFor(int minutes) {
    if (minutes > 0 && minutes % EventAlert.minutesPerDay == 0) {
      return _OffsetUnit.days;
    }
    if (minutes > 0 && minutes % Duration.minutesPerHour == 0) {
      return _OffsetUnit.hours;
    }
    return _OffsetUnit.minutes;
  }

  int _customValueFor(_OffsetUnit unit) {
    final minutes = _allDay
        ? _daysBefore * EventAlert.minutesPerDay
        : _offsetMinutes;
    final value = minutes ~/ unit.multiplier;
    return value.clamp(1, _customMax[unit]!);
  }

  void _setCustomUnit(_OffsetUnit unit) {
    setState(() {
      _customUnit = unit;
      _customValue = _customValue.clamp(1, _customMax[unit]!);
      _applyCustom();
    });
  }

  void _setCustomValue(int value) {
    setState(() {
      _customValue = value;
      _applyCustom();
    });
  }

  void _applyCustom() {
    final minutes = _customValue * _customUnit.multiplier;
    if (_allDay) {
      _daysBefore = _customUnit == _OffsetUnit.days ? _customValue : 0;
    } else {
      _offsetMinutes = minutes;
    }
  }

  Future<void> _pickDayMinute() async {
    final current = _dayMinute ?? kDefaultAlertDayMinute;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null || !mounted) return;
    setState(() => _dayMinute = picked.hour * 60 + picked.minute);
  }

  /// The alert as the sheet currently describes it. Both offset sets ride
  /// along untouched — the timing section edits the one this event's shape
  /// asks for, and the other keeps whatever it said, which is exactly what
  /// makes flipping an event to all-day and back non-destructive.
  EventAlert get _draft => widget.alert.copyWith(
    mode: _mode,
    offsetMinutes: _offsetMinutes,
    daysBefore: _daysBefore,
    dayMinute: _dayMinute,
    clearDayMinute: _dayMinute == null,
  );

  void _save() {
    Navigator.of(
      context,
    ).pop(AlertEditorSaved(_draft, removeAfterAlert: _removeAfter));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
    final bottomClearance = viewInsets > viewPadding ? viewInsets : viewPadding;
    final isAlarm = _mode == AlertMode.ring;
    final captionStyle = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );

    // The clearance rides the scroll view rather than the whole body: the box
    // is a fixed fraction of the screen and does not shrink for the keyboard,
    // so padding the body would collapse the content under a tall IME and
    // leave a blank sheet that hit-tests nothing.
    return Column(
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
                  l10n.eventAlert,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: AutomationId(
                  identifier: SemanticsIds.alertSheetSave,
                  child: FilledButton(
                    onPressed: _save,
                    child: Text(l10n.save),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 24 + bottomClearance),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionLabel(text: l10n.eventAlertTypeSection),
                SegmentedButton<AlertMode>(
                  segments: [
                    ButtonSegment(
                      value: AlertMode.notify,
                      icon: const Icon(Icons.notifications_active_rounded),
                      label: Text(l10n.eventAlertModeNotify),
                    ),
                    ButtonSegment(
                      value: AlertMode.ring,
                      icon: const Icon(Icons.alarm_rounded),
                      label: Text(l10n.eventAlertModeRing),
                    ),
                  ],
                  selected: {_mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) => setState(() {
                    _mode = selection.first;
                    // A reminder cannot be what deletes an event: the switch
                    // belongs to the alarm tier, and leaving it armed while
                    // the tier that honours it is gone would be a promise
                    // nothing keeps.
                    if (_mode != AlertMode.ring) _removeAfter = false;
                  }),
                ),
                const SizedBox(height: 8),
                Text(
                  isAlarm ? l10n.eventAlertRingHint : l10n.eventAlertNotifyHint,
                  style: captionStyle,
                ),
                if (isAlarm && _fullScreenAllowed == false) ...[
                  const SizedBox(height: 4),
                  Text(
                    l10n.eventAlertFullScreenOff,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.tertiary,
                    ),
                  ),
                ],
                _SectionLabel(text: l10n.eventAlertWhenSection),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _allDay
                      ? _allDayChips(l10n)
                      : _timedChips(l10n),
                ),
                if (_customOpen) ...[
                  const SizedBox(height: 12),
                  if (!_allDay)
                    SegmentedButton<_OffsetUnit>(
                      segments: [
                        ButtonSegment(
                          value: _OffsetUnit.minutes,
                          label: Text(l10n.eventAlertUnitMinutes),
                        ),
                        ButtonSegment(
                          value: _OffsetUnit.hours,
                          label: Text(l10n.eventAlertUnitHours),
                        ),
                        ButtonSegment(
                          value: _OffsetUnit.days,
                          label: Text(l10n.eventAlertUnitDays),
                        ),
                      ],
                      selected: {_customUnit},
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                      onSelectionChanged: (selection) =>
                          _setCustomUnit(selection.first),
                    ),
                  const SizedBox(height: 8),
                  _OffsetStepper(
                    value: _customValue,
                    min: 1,
                    max: _customMax[_customUnit]!,
                    unitLabel: _describe(l10n),
                    decrementTooltip: l10n.eventAlertOffsetDecrement,
                    incrementTooltip: l10n.eventAlertOffsetIncrement,
                    onChanged: _setCustomValue,
                  ),
                ],
                if (_allDay) ...[
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.schedule_rounded),
                      ),
                      title: Text(
                        EventTimeFormatter.formatRange(
                          EventTime(
                            startMinute: _dayMinute ?? kDefaultAlertDayMinute,
                          ),
                          l10n,
                        ),
                      ),
                      subtitle: Text(l10n.eventAlertTimeOfDay),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _pickDayMinute,
                    ),
                  ),
                ],
                if (widget.showRemoveAfter && isAlarm) ...[
                  const SizedBox(height: 16),
                  Card(
                    margin: EdgeInsets.zero,
                    child: SwitchListTile(
                      value: _removeAfter,
                      onChanged: (value) =>
                          setState(() => _removeAfter = value),
                      secondary: const CircleAvatar(
                        child: Icon(Icons.auto_delete_outlined),
                      ),
                      title: Text(l10n.eventAlertRemoveAfter),
                      subtitle: Text(l10n.eventAlertRemoveAfterHint),
                    ),
                  ),
                ],
                if (widget.canRemove) ...[
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.errorContainer,
                      foregroundColor: colorScheme.onErrorContainer,
                    ),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(const AlertEditorRemoved()),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: Text(l10n.eventAlertRemove),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// The one formatter, again: the chips, the stepper's unit label and every
  /// other surface read [EventAlert.describe] rather than composing their own
  /// sentence out of the same numbers.
  String _describe(AppLocalizations l10n) => _draft.describe(l10n, widget.event);

  List<Widget> _timedChips(AppLocalizations l10n) {
    return [
      for (final preset in _timedPresets)
        ChoiceChip(
          label: Text(
            widget.alert
                .copyWith(offsetMinutes: preset)
                .describe(l10n, widget.event),
          ),
          selected: !_customOpen && _offsetMinutes == preset,
          onSelected: (_) => setState(() {
            _customOpen = false;
            _offsetMinutes = preset;
          }),
        ),
      ChoiceChip(
        label: Text(l10n.eventAlertCustom),
        selected: _customOpen,
        onSelected: (_) => setState(() {
          _customOpen = true;
          _customUnit = _unitFor(_offsetMinutes);
          _customValue = _customValueFor(_customUnit);
          _applyCustom();
        }),
      ),
    ];
  }

  List<Widget> _allDayChips(AppLocalizations l10n) {
    return [
      for (final preset in _allDayPresets)
        ChoiceChip(
          label: Text(_allDayLabel(l10n, preset)),
          selected: !_customOpen && _daysBefore == preset,
          onSelected: (_) => setState(() {
            _customOpen = false;
            _daysBefore = preset;
          }),
        ),
      ChoiceChip(
        label: Text(l10n.eventAlertCustom),
        selected: _customOpen,
        onSelected: (_) => setState(() {
          _customOpen = true;
          _customUnit = _OffsetUnit.days;
          _customValue = _customValueFor(_OffsetUnit.days);
          _applyCustom();
        }),
      ),
    ];
  }

  static String _allDayLabel(AppLocalizations l10n, int daysBefore) {
    return switch (daysBefore) {
      0 => l10n.eventAlertOnTheDay,
      1 => l10n.eventAlertTheDayBefore,
      _ => l10n.eventAlertAWeekBefore,
    };
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

/// "− N +" with the alert's own description beside it, the event editor's
/// interval stepper in the one shape this sheet needs.
class _OffsetStepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final String unitLabel;
  final String decrementTooltip;
  final String incrementTooltip;
  final ValueChanged<int> onChanged;

  const _OffsetStepper({
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
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton.filledTonal(
              tooltip: decrementTooltip,
              icon: const Icon(Icons.remove_rounded),
              onPressed: value > min ? () => onChanged(value - 1) : null,
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
              onPressed: value < max ? () => onChanged(value + 1) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(unitLabel, style: theme.textTheme.bodyLarge),
            ),
          ],
        ),
      ),
    );
  }
}
