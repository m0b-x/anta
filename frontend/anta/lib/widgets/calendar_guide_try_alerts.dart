import 'package:flutter/material.dart';

import '../constants/calendar_categories.dart';
import '../constants/guide_metrics.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/alert_payload.dart';
import '../models/calendar_event.dart';
import '../models/calendar_guide_demo.dart';
import '../models/event_alert.dart';
import '../pages/alarm_page.dart';
import '../services/app_navigator.dart';
import '../services/day_summary_resolver.dart';
import '../services/event_time_formatter.dart';
import '../utils/alert_labels.dart';
import '../utils/quick_alarm.dart';
import 'agenda_list_view.dart';
import 'alert_editor_sheet.dart';
import 'calendar_guide_try_card.dart';
import 'event_avatar.dart';
import 'form_rows.dart';
import 'quick_alarm_sheet.dart';

/// The alerts page's card: one demo event and its alerts as the editor lists
/// them, through the real alert sheet; then the real ring screen in its
/// preview, the real quick alarm sheet, and — on purpose — the real
/// Permissions page, the one thing here that is not a demo, because she has
/// to grant those on her own phone. Nothing is armed and nothing is saved.
class GuideAlertsDemo extends GuideCardDemo {
  GuideAlertsDemo({DateTime Function() now = DateTime.now})
    : _now = now,
      _today = _todayUtc(now());

  /// Handed on to the quick alarm sheet, so its times read the same day.
  final DateTime Function() _now;

  static const String slug = 'alerts';

  static DateTime _todayUtc(DateTime now) =>
      DateTime.utc(now.year, now.month, now.day);

  /// Date-only UTC, read once.
  final DateTime _today;

  DateTime get _tomorrow =>
      DateTime.utc(_today.year, _today.month, _today.day + 1);

  /// Null until the first build, which names it in her language.
  CalendarEvent? _event;
  List<EventAlert> _alerts = const [];
  int _nextId = 0;

  /// The empty slot is the resting state (D30): until she adds an alert
  /// there is nothing to report.
  @override
  String? idle(AppLocalizations l10n) => null;

  /// What an alert of the timed seed can say, each at its widest digits.
  static List<String> _describes(AppLocalizations l10n) => [
    l10n.eventAlertAtStart,
    for (final n in const [1, 2, 22, 999]) ...[
      l10n.eventAlertMinutesBefore(n),
      l10n.eventAlertHoursBefore(n),
      l10n.eventAlertDaysBefore(n),
    ],
  ];

  /// The stand-in alert row's words — the longest description and the
  /// longer tier — made once per language.
  (String, String) _standIn(AppLocalizations l10n) {
    if (_standInLocale != l10n.localeName) {
      _standInLocale = l10n.localeName;
      String longest(Iterable<String> texts) =>
          texts.reduce((a, b) => b.length > a.length ? b : a);
      _standInWords = (
        longest(_describes(l10n)),
        longest([l10n.eventAlertModeRing, l10n.eventAlertModeNotify]),
      );
    }
    return _standInWords;
  }

  (String, String) _standInWords = ('', '');
  String? _standInLocale;

  @override
  List<String> candidates(AppLocalizations l10n) {
    final quote = calendarGuideLongestQuote;
    final describes = _describes(l10n);
    final times = [
      for (final use24Hour in const [false, true])
        EventTimeFormatter.formatMinuteFor(
          12 * 60 + 59,
          localeName: l10n.localeName,
          use24Hour: use24Hour,
        ),
    ];
    final days = [
      l10n.upcomingTomorrow,
      AgendaListView.anchorLabel(l10n.localeName, DateTime.utc(2027, 9, 30)),
    ];
    return [
      for (final alert in describes)
        l10n.calendarGuideDemoAlertSet(quote, alert),
      l10n.calendarGuideDemoChanged(quote),
      for (final time in times) ...[
        l10n.calendarGuideDemoHereOnly(l10n.quickAlarmSet(quote, time)),
        for (final day in days)
          l10n.calendarGuideDemoHereOnly(
            l10n.quickAlarmSetOn(quote, time, day),
          ),
      ],
    ];
  }

  /// The record's Dentist, tomorrow at nine, so an alert before it is still
  /// ahead whatever the hour she opens the page.
  CalendarEvent _seed(AppLocalizations l10n) => CalendarEvent(
    id: '${GuideDemoCalendar.idPrefix}alerts-dentist',
    title: l10n.calendarGuideDemoEventDentist,
    categoryId: CalendarCategories.fallback.id,
    iconKey: 'medical_services',
    startDate: _tomorrow,
    time: const EventTime(startMinute: 9 * 60, durationMinutes: 45),
  );

  /// A fresh demo id for an alert the sheet drafted with a bare uuid.
  String _alertId() => '${GuideDemoCalendar.idPrefix}alert-${_nextId++}';

  Future<void> _addAlert(BuildContext context, CalendarEvent event) async {
    final result = await AlertEditorSheet.show(
      context,
      alert: AlertEditorSheet.draft(
        eventId: event.id,
        allDay: event.allDay,
      ).copyWith(id: _alertId()),
      event: event,
      canRemove: false,
      showRemoveAfter: true,
      removeAfterAlert: event.removeAfterAlert,
    );
    if (result is! AlertEditorSaved) return;
    final alert = result.alert;
    _alerts = [..._alerts, alert];
    _event = event.copyWith(removeAfterAlert: result.removeAfterAlert);
    _saidAlert(event, alert);
  }

  Future<void> _editAlert(
    BuildContext context,
    CalendarEvent event,
    EventAlert alert,
  ) async {
    final result = await AlertEditorSheet.show(
      context,
      alert: alert,
      event: event,
      canRemove: true,
      showRemoveAfter: true,
      removeAfterAlert: event.removeAfterAlert,
    );
    final title = calendarGuideQuote(event.title);
    switch (result) {
      case null:
        return;
      case AlertEditorSaved(alert: final saved, :final removeAfterAlert):
        _alerts = [for (final a in _alerts) a.id == saved.id ? saved : a];
        _event = event.copyWith(removeAfterAlert: removeAfterAlert);
        _saidAlert(event, saved);
      case AlertEditorRemoved():
        _alerts = [
          for (final a in _alerts)
            if (a.id != alert.id) a,
        ];
        say((l10n) => l10n.calendarGuideDemoChanged(title));
    }
  }

  void _saidAlert(CalendarEvent event, EventAlert alert) {
    final title = calendarGuideQuote(event.title);
    // The event is timed, so its alerts' words carry no clock to format.
    say(
      (l10n) =>
          l10n.calendarGuideDemoAlertSet(title, alert.describe(l10n, event)),
    );
  }

  /// The ring screen as a ring of this event would draw it, its payload
  /// built as the scheduler builds one — the words written through
  /// [AlertLabels] in her language and on her phone's clock — with demo ids
  /// and no database, so nothing it closes can touch a real alert.
  void _showAlarm(BuildContext context, CalendarEvent event) {
    final l10n = AppLocalizations.of(context)!;
    final labels = AlertLabels(
      strings: l10n,
      use24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final day = event.startDateUtc;
    final fireAt = DateTime(
      day.year,
      day.month,
      day.day,
      0,
      event.time?.startMinute ?? 0,
    );
    final category = CalendarCategories.resolve(event.categoryId);
    final payload = AlertPayload(
      database: '',
      eventId: event.id,
      alertId: '${GuideDemoCalendar.idPrefix}alarm-preview',
      dayUtcMs: day.millisecondsSinceEpoch,
      osId: 0,
      mode: AlertMode.ring,
      title: event.title,
      timeLabel: labels.timeLabel(fireAt),
      colorValue: event.colorValue,
      tintIcon: event.tintIcon,
      iconKey: event.iconKey,
      categoryId: event.categoryId,
      fireAtMs: fireAt.millisecondsSinceEpoch,
      whenLabel: labels.whenLabel(time: event.time, day: day, fireAt: fireAt),
      glyphKey: CalendarCategories.iconKeyFor(event),
      languageCode: labels.languageCode,
      // As the scheduler stamps it: the Remove / Keep row shows when she
      // turned removal on. The preview's Keep only closes the page.
      removeAfterAlert: event.removeAfterAlert,
    );
    AppNavigator.push<void>(
      context,
      AlarmPage.preview(
        payload: payload.copyWith(
          tintValue: payload.iconColorValue(category.colorValue),
        ),
      ),
    );
  }

  /// The real quick alarm sheet; its draft is reported in the words the
  /// calendar's own message uses, and kept nowhere.
  Future<void> _quickAlarm(BuildContext context) async {
    final draft = await QuickAlarmSheet.show(context, day: _today, now: _now);
    if (draft == null || !context.mounted) return;
    final title = calendarGuideQuote(
      buildQuickAlarmEvent(draft, id: _alertId()).title,
    );
    final time = EventTimeFormatter.formatMinute(draft.startMinute, context);
    final day = draft.day;
    say(
      (l10n) => l10n.calendarGuideDemoHereOnly(
        day == _today
            ? l10n.quickAlarmSet(title, time)
            : l10n.quickAlarmSetOn(
                title,
                time,
                AgendaListView.shortDayLabel(l10n, day, _today),
              ),
      ),
    );
  }

  @override
  Widget buildStage(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final event = _event ??= _seed(l10n);
    final time = event.time;
    String formatMinute(int minute) =>
        EventTimeFormatter.formatMinute(minute, context);
    String control(String name) =>
        SemanticsIds.calendarGuideTryControl(slug, name);
    final titleRow = FormReadTitleRow(
      leading: EventAvatar(
        icon: CalendarCategories.iconFor(event),
        color: EventSummaryProvider.colorFor(
          event,
          CalendarCategories.resolve(event.categoryId),
        ),
      ),
      title: event.title,
      caption: [
        l10n.upcomingTomorrow,
        if (time != null)
          EventTimeFormatter.formatRangeOfContext(time, context),
      ].join(' · '),
    );
    final (standInLabel, standInValue) = _standIn(l10n);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          children: [
            // The group's height: the demo's limit of alerts, each as wide
            // as an alert's words get, laid out unseen, so adding or
            // removing one never moves the card or the page under her
            // finger. The rows scroll inside it.
            ExcludeSemantics(
              child: ExcludeFocus(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0,
                    child: FormRowGroup(
                      children: [
                        titleRow,
                        for (var i = 0; i < GuideMetrics.demoAlertCap; i++)
                          FormPickerRow(
                            glyph: Icons.notifications_outlined,
                            label: standInLabel,
                            value: standInValue,
                            onTap: () {},
                          ),
                        FormActionRow(
                          glyph: Icons.add_rounded,
                          label: l10n.eventAlertAdd,
                          onTap: null,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: SingleChildScrollView(
                child: FormRowGroup(
                  children: [
                    titleRow,
                    // The editor's own alert rows: the glyph names the
                    // tier, the value says it.
                    for (final (index, alert) in _alerts.indexed)
                      FormPickerRow(
                        glyph: alert.isAlarm
                            ? Icons.alarm_outlined
                            : Icons.notifications_outlined,
                        label: alert.describe(
                          l10n,
                          event,
                          formatMinute: formatMinute,
                        ),
                        value: alert.isAlarm
                            ? l10n.eventAlertModeRing
                            : l10n.eventAlertModeNotify,
                        identifier: control('alert-$index'),
                        onTap: () => _editAlert(context, event, alert),
                      ),
                    FormActionRow(
                      glyph: Icons.add_rounded,
                      label: l10n.eventAlertAdd,
                      identifier: control('add'),
                      // Disabled, never hidden, at the demo's limit.
                      onTap: _alerts.length < GuideMetrics.demoAlertCap
                          ? () => _addAlert(context, event)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        FormRowGroup(
          trailingGap: false,
          children: [
            FormActionRow(
              glyph: Icons.alarm_rounded,
              label: l10n.calendarGuideShowAlarm,
              identifier: control('show-alarm'),
              onTap: () => _showAlarm(context, event),
            ),
            FormActionRow(
              glyph: Icons.alarm_add_rounded,
              label: l10n.quickAlarmTitle,
              identifier: control('quick'),
              onTap: () => _quickAlarm(context),
            ),
            FormActionRow(
              glyph: Icons.open_in_new_rounded,
              label: l10n.calendarGuideOpenPermissions(l10n.permissionsTitle),
              identifier: control('permissions'),
              onTap: () => AppNavigator.toPermissions(context),
            ),
          ],
        ),
      ],
    );
  }
}
