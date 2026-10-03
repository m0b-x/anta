import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_colors.dart';
import '../constants/app_constants.dart';
import '../constants/event_alerts.dart';
import '../constants/row_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/alert_sound.dart';
import '../models/app_permission.dart';
import '../models/calendar_event.dart';
import '../models/event_alert.dart';
import '../services/alert_gateway.dart';
import '../services/event_time_formatter.dart';
import '../services/permission_service.dart';
import 'alert_offset_sheet.dart';
import 'alert_sound_sheet.dart';
import 'alert_type_row.dart';
import 'form_rows.dart';
import 'overlay_snackbar.dart';
import 'time_pad_sheet.dart';
import 'value_change_highlight.dart';

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

/// Draft-and-Done editor for exactly one [EventAlert] (§5.2).
///
/// Nothing here writes: the sheet pops with an [AlertEditorResult] and the
/// surface that owns the event — the event editor, or the Calendar settings
/// row holding a default — decides what that means. That is what lets the same
/// sheet edit an alert on an event and the template a new event is seeded
/// from, without either path growing a second copy of the timing controls.
///
/// [event] is what decides whether the When row asks for minutes before a
/// start or for a day and a time: the derived [CalendarEvent.allDay], never a
/// flag of its own. Both offset sets survive the edit either way, exactly as
/// [EventAlert] promises.
///
/// A sub-sheet of the UI language, and one that never changes height: every
/// row the caller offers is there on both tiers, switched off rather than
/// taken away on the one that cannot use it.
class AlertEditorSheet extends StatefulWidget {
  /// The alert being edited. A brand-new one arrives seeded, so there is no
  /// "create" mode to tell apart.
  final EventAlert alert;

  /// The event the alert belongs to — or a stand-in with the right
  /// [CalendarEvent.allDay] shape when a settings default is being edited.
  final CalendarEvent event;

  /// Whether the sheet offers to remove this alert. False for a brand-new
  /// one, where closing the sheet already means "no", and true everywhere an
  /// alert exists — the settings defaults included, where removal means "no
  /// default".
  final bool canRemove;

  /// Whether the Sound row is offered at all.
  ///
  /// False for the Calendar-settings defaults: `alert_default_timed` encodes a
  /// tier and an offset and nothing else, so a sound chosen there would be
  /// discarded on save — and the Alarm sound row two lines below it on the same
  /// page is the control that actually means something.
  final bool showSound;

  /// Whether the **event-level** remove-after-it-rings switch is offered
  /// here: for a one-time event only, the rule the event editor's own copy of
  /// the switch follows. Offered, it stays in place on the Reminder tier,
  /// switched off and dimmed.
  final bool showRemoveAfter;

  final bool removeAfterAlert;

  const AlertEditorSheet({
    super.key,
    required this.alert,
    required this.event,
    this.canRemove = true,
    this.showSound = true,
    this.showRemoveAfter = false,
    this.removeAfterAlert = false,
  });

  static Future<AlertEditorResult?> show(
    BuildContext context, {
    required EventAlert alert,
    required CalendarEvent event,
    bool canRemove = true,
    bool showSound = true,
    bool showRemoveAfter = false,
    bool removeAfterAlert = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<AlertEditorResult>(
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
        child: AlertEditorSheet(
          alert: alert,
          event: event,
          canRemove: canRemove,
          showSound: showSound,
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
    // Both offset sets are seeded, not just the one this event's shape reads:
    // the alert survives a flip to all-day, and it should arrive there with
    // the time the settings name rather than with nothing.
    return EventAlert(
      id: const Uuid().v4(),
      eventId: eventId,
      mode: timedDefault?.mode ?? AlertMode.notify,
      offsetMinutes: timedDefault?.offsetMinutes ?? kDraftAlertOffsetMinutes,
      daysBefore: allDayDefault?.daysBefore ?? 0,
      dayMinute: allDayDefault?.dayMinute,
    );
  }

  @override
  State<AlertEditorSheet> createState() => _AlertEditorSheetState();
}

class _AlertEditorSheetState extends State<AlertEditorSheet> {
  /// Offsets the When menu offers a timed event, in minutes. "At start" is
  /// the leading zero; everything else is what a calendar app is expected to
  /// have without a trip through Custom.
  static const List<int> _timedPresets = [
    0,
    5,
    10,
    15,
    30,
    Duration.minutesPerHour,
    EventAlert.minutesPerDay,
  ];

  /// Whole days the When menu offers an all-day event.
  static const List<int> _allDayPresets = [0, 1, DateTime.daysPerWeek];

  /// The menu's last item, which names no offset: it opens the Custom
  /// sub-sheet. A popup route answers a dismissal with `null`, so the item
  /// needs a value of its own, and one no preset can be.
  static const int _customItem = -1;

  late AlertMode _mode;
  late int _offsetMinutes;
  late int _daysBefore;
  late int? _dayMinute;

  /// What the remove switch shows on the Alarm tier. A tier change leaves it
  /// alone: on the Reminder tier the switch is drawn off and dimmed, and
  /// going back to Alarm shows what it showed before.
  late bool _removeAfter;

  /// Whether this sheet has turned the alert into a reminder. A reminder
  /// cannot be what deletes an event, so an alarm made a reminder here takes
  /// the removal with it — while an alert that arrived a reminder and stays
  /// one hands the event's flag back as it came, because that flag belongs to
  /// whichever of the event's alerts rings.
  bool _demoted = false;

  /// The alert's own sound, `null` for "follow the app setting". Kept across a
  /// flip to the reminder tier exactly as both offset sets are: the row dims,
  /// the value survives, and switching back restores the reading it had.
  late String? _sound;

  /// The phone's name for [_sound] when it is a picked one, and whether the
  /// phone has answered. Fetched off the first frame, never during it.
  String? _soundTitle;
  bool _soundTitleResolved = false;

  /// Whether the platform will let an alarm take over the screen. Null until
  /// the gateway has answered; the warning only appears on a definite "no",
  /// so a slow round trip never accuses a phone that is fine.
  bool? _fullScreenAllowed;

  final FormHeaderHairline _hairline = FormHeaderHairline();

  bool get _allDay => widget.event.allDay;

  /// The number the When row edits: minutes before the start for a timed
  /// event, whole days before for an all-day one.
  int get _whenValue => _allDay ? _daysBefore : _offsetMinutes;

  @override
  void initState() {
    super.initState();
    final alert = widget.alert;
    _mode = alert.mode;
    _offsetMinutes = alert.offsetMinutes;
    _daysBefore = alert.daysBefore;
    _dayMinute = alert.dayMinute;
    _sound = alert.sound;
    _removeAfter = widget.removeAfterAlert;
    _resolvePermissions();
    _resolveSoundTitle();
  }

  @override
  void dispose() {
    _hairline.dispose();
    super.dispose();
  }

  /// Asks the phone what it calls the picked sound this alert holds, once.
  ///
  /// Best-effort and deliberately not awaited by anything: the row renders its
  /// neutral name on the first frame and swaps in the phone's own when it
  /// arrives, so a slow platform costs a word, never a layout.
  Future<void> _resolveSoundTitle() async {
    final value = _sound;
    if (value == null || AlertSound.decode(value) is! AlertSoundUri) return;
    if (!GetIt.I.isRegistered<AlertGateway>()) return;
    final title = await GetIt.I<AlertGateway>().soundTitle(value);
    if (!mounted) return;
    setState(() {
      _soundTitle = title;
      _soundTitleResolved = true;
    });
  }

  /// Opens the shared chooser. The picker-missing case is reported by the
  /// sound sheet rather than shown inside it, and raised here in the
  /// overlay: this sheet is itself a route above the page, so a `SnackBar`
  /// on the page's `Scaffold` would be drawn under it.
  Future<void> _pickSound() async {
    final result = await AlertSoundSheet.show(
      context,
      value: _sound,
      allowInherit: true,
    );
    if (result == null || !mounted) return;
    switch (result) {
      case AlertSoundPickerMissing():
        OverlaySnackbar.show(
          context,
          _l10nOf.alertSoundPickerUnavailable,
          duration: AppConstants.snackbarErrorDuration,
        );
      case AlertSoundPicked(:final value, :final title):
        setState(() {
          _sound = value;
          _soundTitle = title;
          // A freshly picked sound the picker did not name is still a sound
          // this device has; only a stored one it cannot resolve is
          // "unavailable", so the answered flag follows the title.
          _soundTitleResolved = title != null;
        });
    }
  }

  AppLocalizations get _l10nOf => AppLocalizations.of(context)!;

  /// Asks once whether full-screen alarms are allowed, so the alarm hint can
  /// say what will actually happen. Best-effort: a build with no permission
  /// service, or a platform that cannot answer, simply says nothing.
  Future<void> _resolvePermissions() async {
    if (!GetIt.I.isRegistered<PermissionService>()) return;
    final permissions = await GetIt.I<PermissionService>().refresh();
    if (!mounted) return;
    setState(() {
      _fullScreenAllowed = !permissions.isMissing(
        AppPermission.fullScreenIntent,
      );
    });
  }

  void _setMode(AlertMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      if (mode == AlertMode.notify) _demoted = true;
    });
  }

  void _setWhenValue(int value) {
    setState(() {
      if (_allDay) {
        _daysBefore = value;
      } else {
        _offsetMinutes = value;
      }
    });
  }

  /// A preset is written at once. Custom writes nothing until its own sheet
  /// is confirmed: opening it on "At start" and backing out leaves the alert
  /// at start, and a value the stepper cannot count is kept until Done hands
  /// back the one it clamped to.
  Future<void> _onWhenSelected(int item) async {
    if (item != _customItem) {
      _setWhenValue(item);
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final picked = await AlertOffsetSheet.show(
      context,
      initial: _whenValue,
      allDay: _allDay,
      // The When row's own wording, so the sub-sheet shows before Done what
      // this row says after it.
      readBack: (stored) => _whenLabel(l10n, stored),
    );
    if (picked == null || !mounted) return;
    _setWhenValue(picked);
  }

  Future<void> _pickDayMinute() async {
    final current = _dayMinute ?? EventAlerts.defaultDayMinute;
    final picked = await TimePadSheet.pick(
      context,
      initialMinute: current,
      title: AppLocalizations.of(context)!.eventAlertTimeOfDay,
    );
    if (picked == null || !mounted) return;
    setState(() => _dayMinute = picked);
  }

  /// The alert as the sheet currently describes it. Both offset sets ride
  /// along untouched — the When row edits the one this event's shape asks
  /// for, and the other keeps whatever it said, which is exactly what makes
  /// flipping an event to all-day and back non-destructive.
  EventAlert get _draft => widget.alert.copyWith(
    mode: _mode,
    offsetMinutes: _offsetMinutes,
    daysBefore: _daysBefore,
    dayMinute: _dayMinute,
    clearDayMinute: _dayMinute == null,
    sound: _sound,
    clearSound: _sound == null,
  );

  /// The event-level removal the result carries: the switch on the Alarm
  /// tier, and on the Reminder tier whatever [_demoted] leaves of it.
  bool get _removeAfterResult =>
      _mode == AlertMode.ring ? _removeAfter : _removeAfter && !_demoted;

  void _save() {
    Navigator.of(
      context,
    ).pop(AlertEditorSaved(_draft, removeAfterAlert: _removeAfterResult));
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
    // A group exists only while it holds a row: the settings defaults are
    // offered neither a sound nor the removal, and a brand-new alert has
    // nothing to remove.
    final groups = <List<Widget>>[
      [_buildTypeRow(l10n)],
      [_buildWhenRow(l10n), if (_allDay) _buildTimeOfDayRow(l10n)],
      [
        if (widget.showSound) _buildSoundRow(l10n),
        if (widget.showRemoveAfter) _buildRemoveAfterRow(l10n),
      ],
      [if (widget.canRemove) _buildRemoveRow(l10n)],
    ].where((rows) => rows.isNotEmpty).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FormSheetHandle(),
        FormSheetHeader(
          leadingIcon: Icons.close_rounded,
          leadingTooltip: l10n.cancel,
          leadingIdentifier: SemanticsIds.alertSheetClose,
          onLeading: () => Navigator.of(context).pop(),
          title: l10n.eventAlert,
          scrolled: _hairline.scrolled,
          trailingInset: FormMetrics.headerActionInset,
          trailing: FormHeaderTextButton(
            label: l10n.eventDescriptionDone,
            identifier: SemanticsIds.alertSheetSave,
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
                  for (final (index, rows) in groups.indexed)
                    FormRowGroup(
                      trailingGap: index < groups.length - 1,
                      children: rows,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTypeRow(AppLocalizations l10n) {
    return AlertTypeRow(
      mode: _mode,
      onChanged: _setMode,
      reminderIdentifier: SemanticsIds.alertTypeReminder,
      alarmIdentifier: SemanticsIds.alertTypeAlarm,
      alarmWarning: l10n.eventAlertFullScreenOff,
      showAlarmWarning: _fullScreenAllowed == false,
    );
  }

  Widget _buildWhenRow(AppLocalizations l10n) {
    final presets = _allDay ? _allDayPresets : _timedPresets;
    final value = _whenValue;
    return FormMenuRow<int>(
      glyph: Icons.timer_outlined,
      label: l10n.eventAlertWhenSection,
      value: _whenLabel(l10n, value),
      selected: presets.contains(value) ? value : _customItem,
      identifier: SemanticsIds.alertWhen,
      menuWidth: FormMetrics.menuWidth,
      items: [
        for (final preset in presets)
          FormMenuItem(
            value: preset,
            label: _whenLabel(l10n, preset),
            identifier: _allDay
                ? SemanticsIds.alertWhenDayItem(preset)
                : SemanticsIds.alertWhenItem(preset),
          ),
        FormMenuItem(
          value: _customItem,
          label: l10n.eventAlertCustomItem,
          identifier: _allDay
              ? SemanticsIds.alertWhenDayCustom
              : SemanticsIds.alertWhenCustom,
        ),
      ],
      onSelected: _onWhenSelected,
    );
  }

  /// How an offset reads on the When row, in its menu and under the Custom
  /// sub-sheet's stepper — one wording for the three. A timed one goes
  /// through [EventAlert.describe], the one formatter every other surface
  /// reads. An all-day one is named without its time of day, which has the
  /// row under this one to itself.
  String _whenLabel(AppLocalizations l10n, int value) {
    if (!_allDay) {
      return widget.alert
          .copyWith(offsetMinutes: value)
          .describe(l10n, widget.event);
    }
    return switch (value) {
      <= 0 => l10n.eventAlertOnTheDay,
      1 => l10n.eventAlertTheDayBefore,
      DateTime.daysPerWeek => l10n.eventAlertAWeekBefore,
      _ => l10n.eventAlertDaysBefore(value),
    };
  }

  Widget _buildTimeOfDayRow(AppLocalizations l10n) {
    final minute = _dayMinute ?? EventAlerts.defaultDayMinute;
    // The highlight stands between the group and the row, so the group
    // cannot read the row's hairline indent through it.
    return FormIndentedRow(
      dividerIndent: FormMetrics.dividerIndentGlyph,
      child: ValueChangeHighlight(
        value: minute,
        // The group's own radius: this is the group's last row, and a flash
        // on a tighter corner than the group's clip lost its bottom corners.
        borderRadius: const BorderRadius.all(
          Radius.circular(RowMetrics.groupRadius),
        ),
        child: FormPickerRow(
          glyph: Icons.schedule_outlined,
          label: l10n.eventAlertTimeOfDay,
          value: EventTimeFormatter.formatMinute(minute, context),
          identifier: SemanticsIds.alertTimeOfDay,
          onTap: _pickDayMinute,
        ),
      ),
    );
  }

  Widget _buildSoundRow(AppLocalizations l10n) {
    return FormPickerRow(
      glyph: Icons.music_note_outlined,
      label: l10n.alertsSound,
      value: AlertSoundSheet.labelFor(
        l10n,
        _sound,
        title: _soundTitle,
        titleResolved: _soundTitleResolved,
      ),
      identifier: SemanticsIds.alertSound,
      // Alarm tier only: the reminder tier plays through a notification
      // channel whose sound Android froze at creation, so a choice there
      // would be a control that does nothing.
      enabled: _mode == AlertMode.ring,
      onTap: _pickSound,
    );
  }

  Widget _buildRemoveAfterRow(AppLocalizations l10n) {
    final isAlarm = _mode == AlertMode.ring;
    return FormSwitchRow(
      glyph: Icons.auto_delete_outlined,
      label: l10n.eventAlertRemoveAfter,
      subtitle: l10n.eventAlertRemoveAfterHint,
      identifier: SemanticsIds.alertRemoveAfter,
      value: isAlarm && _removeAfter,
      onChanged: isAlarm
          ? (value) => setState(() => _removeAfter = value)
          : null,
    );
  }

  Widget _buildRemoveRow(AppLocalizations l10n) {
    return FormActionRow(
      glyph: Icons.delete_outline_rounded,
      label: l10n.eventAlertRemove,
      destructive: true,
      identifier: SemanticsIds.alertRemove,
      onTap: () => Navigator.of(context).pop(const AlertEditorRemoved()),
    );
  }
}
