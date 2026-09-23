import 'package:flutter/material.dart';

import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/event_alert.dart';
import '../services/event_time_formatter.dart';
import '../utils/quick_alarm.dart';
import 'agenda_list_view.dart';
import 'automation_id.dart';

enum _QuickAlarmPreset { in20Minutes, in1Hour, tonight }

/// The quick-alarm sheet (parent roadmap §5.8, Session 6): a big time, three
/// presets, a name, the tier and the remove-after switch — the fewest taps
/// between "I need an alarm" and one that is armed.
///
/// Reports a [QuickAlarmDraft] on Save and `null` on dismiss; the page mints
/// the event and its alert from the draft. The sheet never touches a service.
class QuickAlarmSheet extends StatefulWidget {
  /// The day the sheet was opened for, date-only UTC. Where the alarm lands
  /// while its time is still ahead on that day; [quickAlarmDayFor] rolls a
  /// time already gone forward.
  final DateTime day;

  /// The clock, a seam so the defaults and the presets can be tested.
  final DateTime Function() now;

  const QuickAlarmSheet({super.key, required this.day, this.now = DateTime.now});

  static Future<QuickAlarmDraft?> show(
    BuildContext context, {
    required DateTime day,
    DateTime Function() now = DateTime.now,
  }) {
    return showModalBottomSheet<QuickAlarmDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.7,
        child: QuickAlarmSheet(day: day, now: now),
      ),
    );
  }

  @override
  State<QuickAlarmSheet> createState() => _QuickAlarmSheetState();
}

class _QuickAlarmSheetState extends State<QuickAlarmSheet> {
  late DateTime _day;
  late int _minute;
  AlertMode _mode = AlertMode.ring;
  bool _removeAfter = true;
  _QuickAlarmPreset? _preset;
  final TextEditingController _name = TextEditingController();
  bool _nameSeeded = false;

  @override
  void initState() {
    super.initState();
    _minute = quickAlarmDefaultFor(widget.now()).minute;
    // The opened day, whatever the time: `quickAlarmDayFor` rolls a moment
    // already gone forward in the caption and at Save, so 23:50 opens on
    // 00:00 tomorrow without the day itself moving.
    _day = widget.day;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_nameSeeded) return;
    _nameSeeded = true;
    _name.text = AppLocalizations.of(context)!.quickAlarmName;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  QuickAlarmMoment? _momentFor(_QuickAlarmPreset preset) {
    final now = widget.now();
    return switch (preset) {
      _QuickAlarmPreset.in20Minutes => quickAlarmAfter(
        now,
        const Duration(minutes: 20),
      ),
      _QuickAlarmPreset.in1Hour => quickAlarmAfter(
        now,
        const Duration(hours: 1),
      ),
      _QuickAlarmPreset.tonight => quickAlarmTonightFor(now),
    };
  }

  void _applyPreset(_QuickAlarmPreset preset) {
    final moment = _momentFor(preset);
    if (moment == null) return;
    setState(() {
      _preset = preset;
      _day = moment.day;
      _minute = moment.minute;
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _minute ~/ 60, minute: _minute % 60),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _preset = null;
      // On the opened day again: a preset may have moved the day to
      // tomorrow, and 23:58 picked at 23:50 must mean tonight.
      _day = widget.day;
      _minute = picked.hour * 60 + picked.minute;
    });
  }

  DateTime get _resolvedDay =>
      quickAlarmDayFor(day: _day, minute: _minute, now: widget.now());

  void _save() {
    final l10n = AppLocalizations.of(context)!;
    final name = _name.text.trim();
    Navigator.of(context).pop(
      QuickAlarmDraft(
        day: _resolvedDay,
        startMinute: _minute,
        name: name.isEmpty ? l10n.quickAlarmName : name,
        mode: _mode,
        removeAfterAlert: _mode == AlertMode.ring && _removeAfter,
      ),
    );
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
    final now = widget.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final captionStyle = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );

    // The clearance rides the scroll view rather than the whole body, the
    // rule every calendar sheet follows — see `sheet_bottom_clearance_test`.
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
                  l10n.quickAlarmTitle,
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: AutomationId(
                  identifier: SemanticsIds.quickAlarmSave,
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
                Center(
                  child: AutomationId(
                    identifier: SemanticsIds.quickAlarmTime,
                    child: Tooltip(
                      message: l10n.quickAlarmPickTime,
                      child: TextButton(
                        onPressed: _pickTime,
                        child: Text(
                          EventTimeFormatter.formatMinute(_minute, context),
                          style: theme.textTheme.displayLarge?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Text(
                  AgendaListView.shortDayLabel(l10n, _resolvedDay, today),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(l10n.quickAlarmIn20Min),
                      selected: _preset == _QuickAlarmPreset.in20Minutes,
                      onSelected: (_) =>
                          _applyPreset(_QuickAlarmPreset.in20Minutes),
                    ),
                    ChoiceChip(
                      label: Text(l10n.quickAlarmIn1Hour),
                      selected: _preset == _QuickAlarmPreset.in1Hour,
                      onSelected: (_) =>
                          _applyPreset(_QuickAlarmPreset.in1Hour),
                    ),
                    ChoiceChip(
                      label: Text(
                        l10n.quickAlarmTonight(
                          EventTimeFormatter.formatMinute(
                            kQuickAlarmTonightMinute,
                            context,
                          ),
                        ),
                      ),
                      selected: _preset == _QuickAlarmPreset.tonight,
                      // Disabled once 21:00 has passed: the chip must not
                      // quietly mean tomorrow night.
                      onSelected: quickAlarmTonightFor(now) == null
                          ? null
                          : (_) => _applyPreset(_QuickAlarmPreset.tonight),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                AutomationId(
                  identifier: SemanticsIds.quickAlarmName,
                  child: TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: l10n.eventTitle,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.eventAlertTypeSection,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<AlertMode>(
                  segments: [
                    ButtonSegment(
                      value: AlertMode.ring,
                      icon: const Icon(Icons.alarm_rounded),
                      label: Text(l10n.eventAlertModeRing),
                    ),
                    ButtonSegment(
                      value: AlertMode.notify,
                      icon: const Icon(Icons.notifications_active_rounded),
                      label: Text(l10n.eventAlertModeNotify),
                    ),
                  ],
                  selected: {_mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) => setState(() {
                    _mode = selection.first;
                    // The editor's rule: the switch belongs to the alarm tier.
                    if (_mode != AlertMode.ring) _removeAfter = false;
                  }),
                ),
                const SizedBox(height: 8),
                Text(
                  isAlarm ? l10n.eventAlertRingHint : l10n.eventAlertNotifyHint,
                  style: captionStyle,
                ),
                if (isAlarm) ...[
                  const SizedBox(height: 16),
                  Card(
                    margin: EdgeInsets.zero,
                    child: AutomationId(
                      identifier: SemanticsIds.quickAlarmRemoveAfter,
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
