import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../constants/event_title.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/event_alert.dart';
import '../services/event_time_formatter.dart';
import '../utils/quick_alarm.dart';
import 'agenda_list_view.dart';
import 'alert_type_row.dart';
import 'event_avatar.dart';
import 'form_rows.dart';
import 'time_pad_sheet.dart';
import 'value_change_highlight.dart';

enum _QuickAlarmPreset { in20Minutes, in1Hour, tonight }

/// The quick-alarm sheet (parent roadmap §5.8, Session 6): the time first
/// and large, three presets under it, a name, the tier and the remove-after
/// switch — the fewest taps between "I need an alarm" and one that is armed.
///
/// Reports a [QuickAlarmDraft] on Save and `null` on dismiss; the page mints
/// the event and its alert from the draft. The sheet never touches a service.
///
/// A sub-sheet of the UI language, and one the tier never resizes: both
/// tiers show the same rows, the remove switch dimmed rather than taken away
/// on the one that cannot use it.
class QuickAlarmSheet extends StatefulWidget {
  /// The day the sheet was opened for, date-only UTC. Where the alarm lands
  /// while its time is still ahead on that day; [quickAlarmDayFor] rolls a
  /// time already gone forward.
  final DateTime day;

  /// The clock, a seam so the defaults and the presets can be tested.
  final DateTime Function() now;

  const QuickAlarmSheet({
    super.key,
    required this.day,
    this.now = DateTime.now,
  });

  static Future<QuickAlarmDraft?> show(
    BuildContext context, {
    required DateTime day,
    DateTime Function() now = DateTime.now,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<QuickAlarmDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
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

  /// What the remove switch shows on the Alarm tier. A tier change leaves it
  /// alone: on the Reminder tier the switch is drawn off and dimmed, and
  /// going back to Alarm shows what it showed before. Clearing it with the
  /// tier would lose the default on a round trip through Reminder.
  bool _removeAfter = true;
  _QuickAlarmPreset? _preset;
  final TextEditingController _name = TextEditingController();
  bool _nameSeeded = false;
  final FormHeaderHairline _hairline = FormHeaderHairline();

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
    _hairline.dispose();
    _name.dispose();
    super.dispose();
  }

  void _blur() => FocusManager.instance.primaryFocus?.unfocus();

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
    // Before the pad opens: a name field left focused takes the focus back
    // when the pad closes, and the keyboard comes up over a sheet the user
    // had finished typing in.
    _blur();
    final l10n = AppLocalizations.of(context)!;
    final now = widget.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final picked = await TimePadSheet.pick(
      context,
      initialMinute: _minute,
      title: l10n.quickAlarmTime,
      periodAfter: now.hour * 60 + now.minute,
      caption: (minute, _) => AgendaListView.shortDayLabel(
        l10n,
        quickAlarmDayFor(day: widget.day, minute: minute, now: now),
        today,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _preset = null;
      // On the opened day again: a preset may have moved the day to
      // tomorrow, and 23:58 picked at 23:50 must mean tonight.
      _day = widget.day;
      _minute = picked;
    });
  }

  void _setMode(AlertMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
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
    // The larger of the keyboard inset and the system's bottom inset pads the
    // scroll view, never the whole body — the rule every calendar sheet
    // follows (`sheet_bottom_clearance_test.dart`).
    final clearance = math.max(
      MediaQuery.viewInsetsOf(context).bottom,
      MediaQuery.viewPaddingOf(context).bottom,
    );
    final now = widget.now();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FormSheetHandle(),
        FormSheetHeader(
          leadingIcon: Icons.close_rounded,
          leadingTooltip: l10n.cancel,
          leadingIdentifier: SemanticsIds.quickAlarmClose,
          onLeading: () => Navigator.of(context).pop(),
          title: l10n.quickAlarmTitle,
          scrolled: _hairline.scrolled,
          trailingInset: FormMetrics.headerActionInset,
          trailing: FormHeaderTextButton(
            label: l10n.save,
            identifier: SemanticsIds.quickAlarmSave,
            onPressed: _save,
          ),
        ),
        Flexible(
          child: _hairline.watch(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                RowMetrics.groupInset,
                FormMetrics.bodyTop,
                RowMetrics.groupInset,
                FormMetrics.bodyBottom + clearance,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FormRowGroup(
                    children: [
                      _buildTimeRow(l10n, now),
                      _buildPresetRow(l10n, now),
                    ],
                  ),
                  FormRowGroup(children: [_buildTitleRow(l10n)]),
                  FormRowGroup(
                    trailingGap: false,
                    children: [_buildTypeRow(), _buildRemoveAfterRow(l10n)],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeRow(AppLocalizations l10n, DateTime now) {
    final today = DateTime.utc(now.year, now.month, now.day);
    // The highlight stands between the group and the row, so the group
    // cannot read the row's hairline indent through it.
    return FormIndentedRow(
      dividerIndent: FormMetrics.dividerIndentPlain,
      child: ValueChangeHighlight(
        value: _minute,
        // The group's own radius: this is the group's first row, and a flash
        // on a tighter corner than the group's clip lost its top corners.
        borderRadius: const BorderRadius.all(
          Radius.circular(RowMetrics.groupRadius),
        ),
        child: FormHeroRow(
          glyph: Icons.alarm_outlined,
          value: EventTimeFormatter.formatMinute(_minute, context),
          caption: AgendaListView.shortDayLabel(l10n, _resolvedDay, today),
          tooltip: l10n.quickAlarmPickTime,
          identifier: SemanticsIds.quickAlarmTime,
          onTap: _pickTime,
        ),
      ),
    );
  }

  Widget _buildPresetRow(AppLocalizations l10n, DateTime now) {
    return FormChipRow(
      indented: false,
      chips: [
        FormChip(
          label: l10n.quickAlarmIn20Min,
          selected: _preset == _QuickAlarmPreset.in20Minutes,
          identifier: SemanticsIds.quickAlarmPreset20,
          onTap: () => _applyPreset(_QuickAlarmPreset.in20Minutes),
        ),
        FormChip(
          label: l10n.quickAlarmIn1Hour,
          selected: _preset == _QuickAlarmPreset.in1Hour,
          identifier: SemanticsIds.quickAlarmPreset60,
          onTap: () => _applyPreset(_QuickAlarmPreset.in1Hour),
        ),
        FormChip(
          label: l10n.quickAlarmTonight(
            EventTimeFormatter.formatMinute(kQuickAlarmTonightMinute, context),
          ),
          selected: _preset == _QuickAlarmPreset.tonight,
          identifier: SemanticsIds.quickAlarmPresetTonight,
          // Disabled once 21:00 has passed: the chip must not quietly mean
          // tomorrow night.
          onTap: quickAlarmTonightFor(now) == null
              ? null
              : () => _applyPreset(_QuickAlarmPreset.tonight),
        ),
      ],
    );
  }

  Widget _buildTitleRow(AppLocalizations l10n) {
    final category = CalendarCategories.resolve(kFallbackCategoryId);
    return FormTitleRow(
      // What the event Save makes will wear (`buildQuickAlarmEvent`): the
      // alarm icon as its own override, in the fallback category's colour.
      leading: EventAvatar(
        icon:
            CalendarIcons.forKey(kQuickAlarmIconKey) ??
            CalendarIcons.forKey(category.iconKey) ??
            Icons.event_rounded,
        color: category.color,
      ),
      controller: _name,
      hint: l10n.eventTitle,
      maxLength: kEventTitleMaxLength,
      counterFrom: kEventTitleCounterFrom,
      counterLabel: l10n.eventTitleCount,
      textCapitalization: TextCapitalization.sentences,
      identifier: SemanticsIds.quickAlarmName,
    );
  }

  Widget _buildTypeRow() {
    return AlertTypeRow(
      mode: _mode,
      onChanged: _setMode,
      reminderIdentifier: SemanticsIds.quickAlarmTypeReminder,
      alarmIdentifier: SemanticsIds.quickAlarmTypeAlarm,
    );
  }

  Widget _buildRemoveAfterRow(AppLocalizations l10n) {
    final isAlarm = _mode == AlertMode.ring;
    return FormSwitchRow(
      glyph: Icons.auto_delete_outlined,
      label: l10n.eventAlertRemoveAfter,
      subtitle: l10n.eventAlertRemoveAfterHint,
      identifier: SemanticsIds.quickAlarmRemoveAfter,
      value: isAlarm && _removeAfter,
      onChanged: isAlarm
          ? (value) => setState(() => _removeAfter = value)
          : null,
    );
  }
}
