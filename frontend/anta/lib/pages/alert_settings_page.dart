import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';

import '../constants/alert_constants.dart';
import '../constants/app_colors.dart';
import '../constants/event_alerts.dart';
import '../constants/form_metrics.dart';
import '../constants/semantics_ids.dart';
import '../constants/settings_keys.dart';
import '../l10n/app_localizations.dart';
import '../models/alert_sound.dart';
import '../models/calendar_event.dart';
import '../models/calendar_guide_content.dart';
import '../models/event_alert.dart';
import '../models/recurrence_rule.dart';
import '../services/alert_gateway.dart';
import '../services/alert_scheduler.dart';
import '../services/app_navigator.dart';
import '../services/event_time_formatter.dart';
import '../services/permission_service.dart';
import '../services/settings_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/settings_search.dart';
import '../widgets/alert_editor_sheet.dart';
import '../widgets/alert_sound_sheet.dart';
import '../widgets/automation_id.dart';
import '../widgets/settings_section_list.dart';
import '../widgets/slider_setting_row.dart';
import '../widgets/unified_app_bars.dart';

/// Every app-wide alert option on one page (D5 of
/// `docs/settings-rework-roadmap.md`).
///
/// The rows lived as the last section of Calendar settings, three levels deep
/// (N150), with nothing beside them for the alerts a category carries or for
/// how alerts behave. They moved here whole — their state, their writes, the
/// reconcile after each one and the test alarm's permission check — and the
/// page adds a row to the categories page and one to the guide's alerts
/// topic. Calendar settings keeps a single row that opens it.
class AlertSettingsPage extends StatefulWidget {
  const AlertSettingsPage({super.key})
    : _reconcile = AlertScheduler.reconcileAllQuietly,
      _scheduleTestAlarm = _scheduleOnScheduler;

  /// The page over a stand-in for the scheduler: a widget suite cannot run a
  /// reconcile pass, which resolves every calendar service over the
  /// file-backed database.
  @visibleForTesting
  const AlertSettingsPage.forTesting({
    super.key,
    required Future<void> Function(AlertReconcileReason reason) reconcile,
    required Future<int?> Function(String title, Duration delay)
    scheduleTestAlarm,
  }) : _reconcile = reconcile,
       _scheduleTestAlarm = scheduleTestAlarm;

  final Future<void> Function(AlertReconcileReason reason) _reconcile;
  final Future<int?> Function(String title, Duration delay) _scheduleTestAlarm;

  static Future<int?> _scheduleOnScheduler(String title, Duration delay) async {
    final scheduler = await AlertScheduler.getInstance();
    return scheduler.scheduleTestAlarm(title: title, delay: delay);
  }

  /// Both defaults read back, the timed one over the all-day one, each named
  /// by its row's title here — the value line of Calendar settings' row to
  /// this page, where two bare readings could not say which shape each
  /// serves — or "No alert" once when neither seeds anything.
  static String defaultsSummary(
    BuildContext context, {
    required TimedAlertDefault? timed,
    required AllDayAlertDefault? allDay,
  }) {
    final l10n = AppLocalizations.of(context)!;
    if (timed == null && allDay == null) return l10n.alertsDefaultNone;
    final timedLine = _describe(context, _timedAlert(timed), allDay: false);
    final allDayLine = _describe(context, _allDayAlert(allDay), allDay: true);
    return '${l10n.alertsDefaultTimed} · $timedLine\n'
        '${l10n.alertsDefaultAllDay} · $allDayLine';
  }

  /// The upcoming notice's lead as a sentence: in hours from an hour up when
  /// it is a whole number of them (N121 / N153), in minutes otherwise.
  @visibleForTesting
  static String noticeLeadCaption(AppLocalizations l10n, int minutes) {
    if (minutes == 0) return l10n.alertsNoticeLeadOff;
    if (minutes >= 60 && minutes % 60 == 0) {
      return l10n.alertsNoticeLeadHours(minutes ~/ 60);
    }
    return l10n.alertsNoticeLeadDesc(minutes);
  }

  /// The stand-in event the two default rows describe themselves through.
  ///
  /// [EventAlert.describe] answers for an *event*, and a default belongs to no
  /// event — so the row hands it the one property that decides the reading,
  /// the derived `allDay`. Anything else on this object is unread.
  static CalendarEvent _sampleEvent({required bool allDay}) => CalendarEvent(
    id: '',
    title: '',
    categoryId: kDefaultCategoryId,
    startDate: DateTime.utc(2026),
    rule: const OneTimeRecurrence(),
    time: allDay ? null : const EventTime(startMinute: 9 * 60),
  );

  /// The alert a default stands for, as one alert-shaped object, or null when
  /// the setting says "none".
  static EventAlert? _timedAlert(TimedAlertDefault? value) {
    if (value == null) return null;
    return EventAlert(
      id: 'default',
      eventId: '',
      mode: value.mode,
      offsetMinutes: value.offsetMinutes,
    );
  }

  static EventAlert? _allDayAlert(AllDayAlertDefault? value) {
    if (value == null) return null;
    return EventAlert(
      id: 'default',
      eventId: '',
      mode: value.mode,
      daysBefore: value.daysBefore,
      dayMinute: value.dayMinute,
    );
  }

  static String _describe(
    BuildContext context,
    EventAlert? alert, {
    required bool allDay,
  }) {
    final l10n = AppLocalizations.of(context)!;
    if (alert == null) return l10n.alertsDefaultNone;
    final tier = alert.isAlarm
        ? l10n.eventAlertModeRing
        : l10n.eventAlertModeNotify;
    final timing = alert.describe(
      l10n,
      _sampleEvent(allDay: allDay),
      formatMinute: (minute) =>
          EventTimeFormatter.formatMinute(minute, context),
    );
    return '$tier · $timing';
  }

  @override
  State<AlertSettingsPage> createState() => _AlertSettingsPageState();
}

class _AlertSettingsPageState extends State<AlertSettingsPage> {
  // Persisted fold state is keyed on these, so they are frozen strings, not
  // titles and not positions. They share the calendar settings page's stored
  // set, as the appearance page's do; the `alerts_` prefix keeps them apart
  // from that page's own `alerts` section.
  static const String _sectionDefaults = 'alerts_defaults';
  static const String _sectionTiming = 'alerts_timing';
  static const String _sectionPermissions = 'alerts_permissions';
  static const String _sectionCategories = 'alerts_categories';
  static const String _sectionHowItWorks = 'alerts_how_it_works';

  SettingsService? _settings;
  bool _isLoading = true;
  Set<String> _collapsedSections = const {};
  bool _hapticFeedback = true;

  int _snoozeMinutes = SettingsKeys.defaultAlertSnoozeMinutes;
  int _silenceAfterMinutes = SettingsKeys.defaultAlertSilenceAfterMinutes;
  int _noticeLeadMinutes = SettingsKeys.defaultAlertNoticeLeadMinutes;

  /// What a new event's first alert is seeded with, per shape. `null` is a
  /// value of its own — "no default" — and is what the rows render as
  /// `alertsDefaultNone`.
  TimedAlertDefault? _timedAlertDefault;
  AllDayAlertDefault? _allDayAlertDefault;

  /// Which sound an alarm plays when its own alert names none. `''` reads as
  /// the phone's default alarm — the setting has no "unset", unlike an alert.
  String _alertSound = SettingsKeys.defaultAlertSound;

  /// The phone's name for [_alertSound] when it is a picked one, resolved off
  /// the first frame so the row never waits on a platform round trip.
  String? _alertSoundTitle;
  bool _alertSoundTitleResolved = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsService.getInstance();
    final haptic = await settings.getHapticFeedback();
    final alerts = await settings.getAlertSettings();
    final collapsedSections = await settings
        .getCalendarSettingsCollapsedSections();

    if (!mounted) return;
    setState(() {
      _settings = settings;
      _collapsedSections = collapsedSections;
      _hapticFeedback = haptic;
      _snoozeMinutes = alerts.snoozeMinutes;
      _silenceAfterMinutes = alerts.silenceAfterMinutes;
      _noticeLeadMinutes = alerts.noticeLeadMinutes;
      _timedAlertDefault = alerts.timedDefault;
      _allDayAlertDefault = alerts.allDayDefault;
      _alertSound = alerts.sound;
      _isLoading = false;
    });
    unawaited(_resolveAlertSoundTitle());
  }

  /// Asks the phone what it calls the stored sound, once per load. Best-effort
  /// and unawaited: a build with no gateway simply never answers and the row
  /// keeps its neutral name.
  Future<void> _resolveAlertSoundTitle() async {
    if (AlertSound.decode(_alertSound) is! AlertSoundUri) return;
    if (!GetIt.I.isRegistered<AlertGateway>()) return;
    final title = await GetIt.I<AlertGateway>().soundTitle(_alertSound);
    if (!mounted) return;
    setState(() {
      _alertSoundTitle = title;
      _alertSoundTitleResolved = true;
    });
  }

  /// Writes the app-wide alarm sound and makes the phone catch up.
  ///
  /// The reconcile is the point: nothing about any event changed, so no bloc
  /// dispatches and nothing else would ever re-arm the alarms already standing
  /// on the old sound. The pass re-arms exactly the registrations whose arm
  /// signature moved and leaves every other one on its fast path.
  Future<void> _editAlertSound() async {
    _onHapticFeedback();
    final l10n = AppLocalizations.of(context)!;
    final result = await AlertSoundSheet.show(context, value: _alertSound);
    if (result == null || !mounted) return;
    switch (result) {
      case AlertSoundPickerMissing():
        CustomSnackbar.showError(context, l10n.alertSoundPickerUnavailable);
      case AlertSoundPicked(:final value, :final title):
        setState(() {
          _alertSound = value ?? SettingsKeys.defaultAlertSound;
          _alertSoundTitle = title;
          _alertSoundTitleResolved = title != null;
        });
        await _settings?.setAlertSound(_alertSound);
        await widget._reconcile(AlertReconcileReason.eventChanged);
    }
  }

  PermissionService? get _permissionService =>
      GetIt.I.isRegistered<PermissionService>()
      ? GetIt.I<PermissionService>()
      : null;

  /// Optimistic like every other row on this page: the fold is a view
  /// preference, so a failed write costs nothing worth blocking the tap for.
  Future<void> _toggleSection(String id) async {
    _onHapticFeedback();
    final next = {..._collapsedSections};
    if (!next.remove(id)) next.add(id);
    setState(() => _collapsedSections = next);
    await _settings?.setCalendarSettingsCollapsedSections(next);
  }

  void _onHapticFeedback() {
    if (_hapticFeedback) {
      HapticFeedback.lightImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: colorScheme.pageGround,
      appBar: SettingsAppBar(
        title: l10n.alertSettingsTitle,
        identifier: SemanticsIds.settingsBarAlertSettings,
      ),
      body: SafeArea(
        top: false,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SettingsSectionList(
                query: SettingsQuery.empty,
                listIdentifier: SemanticsIds.alertSettingsList,
                sections: _buildSections(colorScheme, l10n),
                collapsedSections: _collapsedSections,
                onToggleSection: _toggleSection,
              ),
      ),
    );
  }

  List<SettingsSectionData> _buildSections(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    final captionStyle = TextStyle(
      fontSize: FormMetrics.captionSize,
      color: colorScheme.onSurfaceVariant,
    );
    return [
      _buildDefaultsSection(colorScheme, l10n),
      _buildTimingSection(colorScheme, l10n, captionStyle),
      _buildPermissionsSection(colorScheme, l10n, captionStyle),
      _buildCategoriesSection(colorScheme, l10n),
      _buildHowItWorksSection(colorScheme, l10n),
    ];
  }

  /// The kit no longer draws a section's icon (D4), but its frozen API still
  /// requires one, so this section and the four after it name one unseen.
  SettingsSectionData _buildDefaultsSection(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SettingsSectionData(
      id: _sectionDefaults,
      icon: Icons.schedule_rounded,
      title: l10n.alertSettingsSectionDefaults,
      entries: [
        SettingsEntry(
          title: l10n.alertsDefaultTimed,
          description: l10n.alertsDefaultTimedDesc,
          identifier: SemanticsIds.alertsDefaultTimed,
          builder: (context, title, description) {
            final value = AlertSettingsPage._describe(
              context,
              AlertSettingsPage._timedAlert(_timedAlertDefault),
              allDay: false,
            );
            return SettingsYieldingTile(
              leading: Icon(Icons.schedule_rounded, color: colorScheme.primary),
              title: title,
              subtitle: description,
              value: value,
              trailing: (maxWidth) =>
                  _buildValueText(value, colorScheme, maxWidth: maxWidth),
              onTap: () => _editAlertDefault(allDay: false),
            );
          },
        ),
        SettingsEntry(
          title: l10n.alertsDefaultAllDay,
          description: l10n.alertsDefaultAllDayDesc,
          identifier: SemanticsIds.alertsDefaultAllDay,
          builder: (context, title, description) {
            final value = AlertSettingsPage._describe(
              context,
              AlertSettingsPage._allDayAlert(_allDayAlertDefault),
              allDay: true,
            );
            return SettingsYieldingTile(
              leading: Icon(Icons.today_rounded, color: colorScheme.primary),
              title: title,
              subtitle: description,
              value: value,
              trailing: (maxWidth) =>
                  _buildValueText(value, colorScheme, maxWidth: maxWidth),
              onTap: () => _editAlertDefault(allDay: true),
            );
          },
        ),
      ],
    );
  }

  SettingsSectionData _buildTimingSection(
    ColorScheme colorScheme,
    AppLocalizations l10n,
    TextStyle captionStyle,
  ) {
    return SettingsSectionData(
      id: _sectionTiming,
      icon: Icons.music_note_rounded,
      title: l10n.alertSettingsSectionTiming,
      entries: [
        SettingsEntry(
          title: l10n.alertsSound,
          description: l10n.alertsSoundDesc,
          identifier: SemanticsIds.alertSettingsSound,
          builder: (context, title, description) {
            // The same sentence-wide value as the two default rows, which
            // took the whole tile at 200 % in German like the dropdown.
            final value = AlertSoundSheet.labelFor(
              l10n,
              _alertSound,
              title: _alertSoundTitle,
              titleResolved: _alertSoundTitleResolved,
            );
            return SettingsYieldingTile(
              leading: Icon(
                Icons.music_note_rounded,
                color: colorScheme.primary,
              ),
              title: title,
              subtitle: description,
              value: value,
              trailing: (maxWidth) =>
                  _buildValueText(value, colorScheme, maxWidth: maxWidth),
              onTap: _editAlertSound,
            );
          },
        ),
        SettingsEntry(
          title: l10n.alertsSnoozeLength,
          description: l10n.alertsSnoozeLengthDesc(_snoozeMinutes),
          identifier: SemanticsIds.alertSettingsSnooze,
          builder: (context, title, description) => SliderSettingRow(
            title: title,
            description: description,
            value: _snoozeMinutes,
            min: SettingsKeys.minAlertSnoozeMinutes,
            max: SettingsKeys.maxAlertSnoozeMinutes,
            divisions:
                (SettingsKeys.maxAlertSnoozeMinutes -
                    SettingsKeys.minAlertSnoozeMinutes) ~/
                SettingsKeys.alertSnoozeMinutesStep,
            captionStyle: captionStyle,
            draftCaption: (draft) => l10n.alertsSnoozeLengthDesc(draft),
            onCommit: (value) async {
              _onHapticFeedback();
              setState(() => _snoozeMinutes = value);
              await _settings?.setAlertSnoozeMinutes(value);
              // Armed into every alarm-tier entry as the plugin's own Snooze
              // (OS-2), so standing alarms owe the same catch-up a changed
              // sound gets.
              await widget._reconcile(AlertReconcileReason.eventChanged);
            },
          ),
        ),
        SettingsEntry(
          title: l10n.alertsNoticeLead,
          description: AlertSettingsPage.noticeLeadCaption(
            l10n,
            _noticeLeadMinutes,
          ),
          identifier: SemanticsIds.alertSettingsNotice,
          builder: (context, title, description) => SliderSettingRow(
            title: title,
            description: description,
            value: _noticeLeadMinutes,
            min: SettingsKeys.minAlertNoticeLeadMinutes,
            max: SettingsKeys.maxAlertNoticeLeadMinutes,
            divisions:
                (SettingsKeys.maxAlertNoticeLeadMinutes -
                    SettingsKeys.minAlertNoticeLeadMinutes) ~/
                SettingsKeys.alertNoticeLeadMinutesStep,
            captionStyle: captionStyle,
            draftCaption: (draft) =>
                AlertSettingsPage.noticeLeadCaption(l10n, draft),
            onCommit: (value) async {
              _onHapticFeedback();
              setState(() => _noticeLeadMinutes = value);
              await _settings?.setAlertNoticeLeadMinutes(value);
              // The lead rides the arm signature, so this is what moves — or
              // removes — the notice of every alarm already standing.
              await widget._reconcile(AlertReconcileReason.eventChanged);
            },
          ),
        ),
        SettingsEntry(
          title: l10n.alertsSilenceAfter,
          description: l10n.alertsSilenceAfterDesc(_silenceAfterMinutes),
          identifier: SemanticsIds.alertSettingsSilence,
          builder: (context, title, description) => SliderSettingRow(
            title: title,
            description: description,
            value: _silenceAfterMinutes,
            min: SettingsKeys.minAlertSilenceAfterMinutes,
            max: SettingsKeys.maxAlertSilenceAfterMinutes,
            divisions:
                SettingsKeys.maxAlertSilenceAfterMinutes -
                SettingsKeys.minAlertSilenceAfterMinutes,
            captionStyle: captionStyle,
            draftCaption: (draft) => l10n.alertsSilenceAfterDesc(draft),
            onCommit: (value) async {
              _onHapticFeedback();
              setState(() => _silenceAfterMinutes = value);
              await _settings?.setAlertSilenceAfterMinutes(value);
              // Frozen into every alarm-tier entry as `timeoutAfterMillis` at
              // arm time, so a standing alarm would ring for the old length
              // until something unrelated re-scheduled it — the snooze
              // slider's catch-up, for the same reason.
              await widget._reconcile(AlertReconcileReason.eventChanged);
            },
          ),
        ),
      ],
    );
  }

  /// What the operating system allows lives on the Permissions page; the row
  /// here only says whether anything essential is missing, read **live** off
  /// the `PermissionService` snapshot and never stored — and the test ring
  /// beside it is how the user proves the answer.
  SettingsSectionData _buildPermissionsSection(
    ColorScheme colorScheme,
    AppLocalizations l10n,
    TextStyle captionStyle,
  ) {
    return SettingsSectionData(
      id: _sectionPermissions,
      icon: Icons.verified_user_outlined,
      title: l10n.permissionsTitle,
      entries: [
        SettingsEntry(
          title: l10n.permissionsTitle,
          description: l10n.permissionsCalendarRowDesc,
          identifier: SemanticsIds.alertSettingsPermissions,
          builder: (context, title, description) =>
              _permissionsTile(colorScheme, title, description),
        ),
        SettingsEntry(
          title: l10n.alertsTestAlarm,
          // The force-stop note rides this row rather than a row of its own:
          // it is the one thing about alerts nothing in the app can fix, and
          // it belongs beside the button that proves they work.
          description: l10n.alertsForceStopNote,
          builder: (context, title, description) => Padding(
            padding: FormMetrics.settingsControlRowPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AutomationId(
                  identifier: SemanticsIds.alertsTestAlarm,
                  child: OutlinedButton.icon(
                    onPressed: _scheduleTestAlarm,
                    icon: const Icon(Icons.alarm_add_rounded),
                    label: title,
                    style: OutlinedButton.styleFrom(
                      padding: FormMetrics.settingsButtonPadding,
                      // One label line at the reader's scale plus its air,
                      // never under a row's target.
                      minimumSize: Size(
                        0,
                        math.max(
                          FormMetrics.rowMinHeight,
                          MediaQuery.textScalerOf(
                                context,
                              ).scale(FormMetrics.labelLineHeight) +
                              FormMetrics.settingsButtonPadding.vertical,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: FormMetrics.settingsControlGap),
                if (description != null)
                  DefaultTextStyle.merge(
                    style: captionStyle,
                    child: description,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// A category's alerts are set on the category itself (v42); this row is
  /// the way there from the page a user looks for alerts on.
  SettingsSectionData _buildCategoriesSection(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SettingsSectionData(
      id: _sectionCategories,
      icon: Icons.category_rounded,
      title: l10n.calendarCategories,
      entries: [
        SettingsEntry(
          title: l10n.alertSettingsCategoriesRow,
          description: l10n.alertSettingsCategoriesDesc,
          identifier: SemanticsIds.alertSettingsCategoriesOpen,
          builder: (context, title, description) => ListTile(
            leading: Icon(Icons.category_rounded, color: colorScheme.primary),
            title: title,
            subtitle: description,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              _onHapticFeedback();
              AppNavigator.toCalendarCategories(context);
            },
          ),
        ),
      ],
    );
  }

  /// The guide's alerts topic, opened straight from here (D12).
  SettingsSectionData _buildHowItWorksSection(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SettingsSectionData(
      id: _sectionHowItWorks,
      icon: Icons.school_rounded,
      title: l10n.calendarGuideHowItWorks,
      entries: [
        SettingsEntry(
          // Titled by the topic it opens, as the guide's hub lists it; the
          // section header already says what kind of row this is.
          title: l10n.calendarGuidePageAlerts,
          description: l10n.calendarGuidePageAlertsCaption,
          identifier: SemanticsIds.alertSettingsHowItWorksOpen,
          builder: (context, title, description) => ListTile(
            leading: Icon(Icons.school_rounded, color: colorScheme.primary),
            title: title,
            subtitle: description,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              _onHapticFeedback();
              AppNavigator.toCalendarGuideTopic(
                context,
                CalendarGuideTopic.alerts,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _permissionsTile(
    ColorScheme colorScheme,
    Widget title,
    Widget? description,
  ) {
    Widget tile(int missing) {
      final attention = missing > 0;
      return ListTile(
        leading: Icon(
          Icons.verified_user_outlined,
          color: attention ? colorScheme.error : colorScheme.primary,
        ),
        title: title,
        subtitle: description,
        trailing: Icon(
          attention ? Icons.error_outline_rounded : Icons.chevron_right_rounded,
          color: attention ? colorScheme.error : colorScheme.onSurfaceVariant,
          // The glyph's red is all the attention this row shows; a screen
          // reader hears the hub's sentence for it instead.
          semanticLabel: attention
              ? AppLocalizations.of(context)!.permissionsRowAttention(missing)
              : null,
        ),
        onTap: () {
          _onHapticFeedback();
          AppNavigator.toPermissions(context);
        },
      );
    }

    final service = _permissionService;
    if (service == null) return tile(0);
    return ValueListenableBuilder(
      valueListenable: service.snapshot,
      builder: (context, snapshot, _) =>
          tile(snapshot?.missingEssential.length ?? 0),
    );
  }

  /// A tile's value — a default read back, the alarm sound's name — wrapping
  /// inside [maxWidth]: each is a sentence, and as an unbounded trailing it
  /// took the title's room at a large text scale.
  Widget _buildValueText(
    String value,
    ColorScheme colorScheme, {
    required double maxWidth,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Text(value, style: TextStyle(color: colorScheme.onSurfaceVariant)),
    );
  }

  /// Edits one default through the same sheet an event's own alert uses, so
  /// the timing vocabulary cannot drift between the two. Remove there means
  /// "no default" — the `none` the decoder reads as "seed nothing" — and says
  /// so (N148).
  Future<void> _editAlertDefault({required bool allDay}) async {
    _onHapticFeedback();
    final l10n = AppLocalizations.of(context)!;
    final sample = AlertSettingsPage._sampleEvent(allDay: allDay);
    final current = allDay
        ? AlertSettingsPage._allDayAlert(_allDayAlertDefault)
        : AlertSettingsPage._timedAlert(_timedAlertDefault);
    final initial =
        current ?? AlertEditorSheet.draft(eventId: '', allDay: allDay);
    final result = await AlertEditorSheet.show(
      context,
      alert: initial,
      event: sample,
      // A default encodes a tier and an offset, nothing else — and the Alarm
      // sound row on this page is where the sound actually lives.
      showSound: false,
      removeLabel: l10n.alertsDefaultRemove,
    );
    if (result == null || !mounted) return;
    switch (result) {
      case AlertEditorRemoved():
        setState(() {
          if (allDay) {
            _allDayAlertDefault = null;
          } else {
            _timedAlertDefault = null;
          }
        });
        if (allDay) {
          await _settings?.setAlertDefaultAllDay(null);
        } else {
          await _settings?.setAlertDefaultTimed(null);
        }
      case AlertEditorSaved(:final alert, :final touched):
        // Alerts are opt-in: with no default set, the sheet opens on a draft,
        // and a Done that touched nothing on it was a look, not a choice.
        // Touch, not value: a draft chosen as it stands is still a choice.
        if (current == null && !touched) return;
        if (allDay) {
          final value = (
            mode: alert.mode,
            daysBefore: alert.daysBefore,
            dayMinute: alert.dayMinute ?? kDefaultAlertDayMinute,
          );
          setState(() => _allDayAlertDefault = value);
          await _settings?.setAlertDefaultAllDay(value);
        } else {
          final value = (mode: alert.mode, offsetMinutes: alert.offsetMinutes);
          setState(() => _timedAlertDefault = value);
          await _settings?.setAlertDefaultTimed(value);
        }
    }
  }

  Future<void> _scheduleTestAlarm() async {
    final l10n = AppLocalizations.of(context)!;
    _onHapticFeedback();
    final permissions = await _permissionService?.refresh();
    if (!mounted) return;
    if (permissions?.needsAttention ?? false) {
      CustomSnackbar.showWithAction(
        context,
        message: l10n.permissionsAlertBlocked,
        actionLabel: l10n.permissionsReview,
        onAction: () {
          if (context.mounted) AppNavigator.toPermissions(context);
        },
      );
      return;
    }
    int? osId;
    try {
      osId = await widget._scheduleTestAlarm(
        l10n.alertsTestAlarm,
        kAlertTestAlarmDelay,
      );
    } catch (e) {
      debugPrint('[AlertSettings] test alarm failed: $e');
    }
    if (!mounted) return;
    if (osId == null) {
      CustomSnackbar.showError(context, l10n.alertsTestAlarmFailed);
      return;
    }
    CustomSnackbar.showSuccess(context, l10n.alertsTestAlarmScheduled);
  }
}
