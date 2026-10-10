import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:alarm/alarm.dart';
// The plugin's platform half, for the one question its public face cannot
// ask quietly — see `AndroidAlertGateway._silenceWindowRuns`. The fork is the
// app's own (`packages/alarm/`), so its implementation file is no moving
// target.
// ignore: implementation_imports
import 'package:alarm/src/android_alarm.dart';
import 'package:alarm/utils/alarm_exception.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../constants/alert_constants.dart';
import '../constants/calendar_categories.dart';
import '../constants/calendar_icons.dart';
import '../constants/settings_keys.dart';
import '../database/database.dart';
import '../l10n/app_localizations.dart';
import '../models/alert_payload.dart';
import '../models/alert_sound.dart';
import '../utils/alert_labels.dart';
import '../utils/alert_notification_content.dart';
import '../utils/alert_os_id.dart';
import '../utils/alert_planner.dart';
import '../widgets/event_avatar.dart';
import 'alert_gateway.dart';
import 'lock_screen_state.dart';
import 'pending_navigation.dart';
import 'settings_service.dart';

/// **The A5 switch.** `false` rings the Alarm tier through the `alarm`
/// package; `true` rings it through an insistent, alarm-stream notification
/// from `flutter_local_notifications` instead.
///
/// One constant, in one file, because that was the whole mitigation the
/// Phase 0 investigation left standing: the emulator spike proved `alarm` in
/// every state it could reach, but `alarm` then scheduled with
/// `setExactAndAllowWhileIdle`, which deep Doze rate-limits, while the
/// notification path uses `setAlarmClock`, which it does not. **That
/// difference is gone.** The plugin is the fork in `packages/alarm/`, whose
/// Patch 1 arms with `setAlarmClock` as well, so either backend is the
/// phone's own alarm clock and neither is the stronger scheduler. What the
/// switch is still for is a phone on which the plugin's ring path itself —
/// its foreground service, its own player — does not hold: this flips and
/// nothing else changes, because the registry records
/// [AlertGateway.backendName] per row and the next reconcile re-schedules
/// every entry under the new backend.
///
/// The Reminder tier is never affected: it cannot be built on `alarm`, which
/// always plays on the alarm stream and would break the silent-mode contract.
const bool kAlarmTierUsesNotifications = false;

/// Notification channel ids. **Fixed forever**: Android freezes a channel's
/// importance, sound and DND behaviour at creation, so a new id is the only
/// way to change any of them — and a changed id orphans the user's own
/// per-channel settings.
///
/// The fallback tier's channel is on its second id for exactly that reason
/// (OS-1, 2026-09-22): `alerts_alarm` was created without a sound, so a flipped
/// [kAlarmTierUsesNotifications] would have rung the phone's default
/// *notification* sound. [kAlertAlarmChannelId] names the replacement, created
/// with the phone's default alarm sound on the alarm stream, and the old id is
/// deleted at initialize so the two never coexist in the phone's settings.
///
/// [kAlertQuietChannelId] is the newest (2026-10), of **low** importance, and
/// holds the three kinds that must never interrupt: the upcoming notice, the
/// Missed notice and the session chip. They used to be posted on the reminder
/// channel under the notification's own `silent` flag, which Android 16 does
/// not honour in company. It bundles an app's loose notifications once two
/// stand in one section of the shade, under a summary of its own on the
/// channel that made the bundle — so two quiet ones together sounded, a
/// reminder that fired beside one was silenced, and taking that reminder
/// down made the summary sound again. A channel's importance is what picks
/// the section, and in the silent one nothing sounds, alone or bundled, and
/// nothing shares a bundle with a reminder
/// (`docs/alert-surfaces-redesign-roadmap.md` §3.7).
const String kAlertReminderChannelId = 'alerts_reminder';
const String kAlertQuietChannelId = 'alerts_quiet';
const String kAlertAlarmChannelId = 'alerts_alarm_v2';
const String kAlertLegacyAlarmChannelId = 'alerts_alarm';
const String kAlarmPluginChannelId = 'alarm_plugin_channel';

/// The sound [kAlertAlarmChannelId] was created with: the phone's **current**
/// default alarm, by the settings URI that keeps following the Clock app
/// rather than the sound it resolved to on the day the channel was made.
const String kAlertAlarmChannelSoundUri =
    'content://settings/system/alarm_alert';

/// The `res/drawable` name of the monochrome status-bar icon.
const String kAlertSmallIcon = 'ic_alert';

/// The error code `MainActivity` answers `pickAlarmSound` with when the device
/// has no ringtone picker activity at all (`ActivityNotFoundException`).
///
/// A literal on both sides of a platform channel, like the two action ids.
const String kAlertSoundNoPickerCode = 'no_picker';

/// The method `MainActivity` answers, on the alerts channel, with the phone's
/// Android API level (`Build.VERSION.SDK_INT`).
///
/// Spelled once and held to the Kotlin side by
/// `test/android/alerts_channel_test.dart`, because this call fails soft: an
/// unanswered one arms a reminder loose and says so only in the log, so a
/// method renamed on one side alone would read as a phone below Android 16
/// for good.
const String kAlertSdkLevelMethod = 'sdkInt';

/// The `assetAudioPath` one already-resolved sound is armed under.
///
/// Pure, and the whole of the sound decision the platform ever sees. **Null is
/// the phone's own default alarm sound** — the `alarm` package resolves it
/// through `RingtoneManager` at ring time, so it keeps following the Clock app.
/// A picked sound is armed with its `content://` URI **verbatim**: the fork's
/// `AudioService` (Patch 2 of `packages/alarm/`) hands a URI to
/// `MediaPlayer.setDataSource(Context, Uri)`, so nothing is copied into the
/// app's files first, and a URI this device cannot open — a sound picked on
/// another phone, a provider that is gone — falls back to the phone's default
/// *inside the plugin, at ring time*, rather than to nothing. The app ships no
/// sound of its own.
String? alarmAssetPathFor(AlertSound sound) =>
    sound is AlertSoundUri ? sound.uri : null;

/// The payload a ring is announced under: what the entry was armed with
/// ([stored]), under the id the platform holds it by, corrected for the
/// instant the platform says it rang at ([alarmDateTime]).
///
/// The two differ after a Snooze taken on the plugin's own notification, and
/// after a ring the platform deferred: the plugin moves its alarm and re-arms
/// the stored settings as they were, payload included, so the entry still
/// reads the first ring's time. A payload that names its due instant is
/// brought up to date here — the instant, the clock label written for it by
/// [labels], and the event's own time where the old label was all that said
/// it ([AlertLabels.moved]). One that names none was armed before the field
/// existed and is passed on as it is: there is nothing to compare the
/// plugin's instant with, and its page goes on drawing what it always drew.
///
/// [nativelySnoozed] is whether this process saw the plugin move this alarm
/// by a snooze since it was armed, and is the only thing that marks the ring
/// as one ([AlertPayload.reRing]). A moved instant alone never does — the
/// platform moves rings for reasons of its own.
///
/// Pure, and the whole of what the binding decides about a ring report: the
/// two sites that announce a ring only call it.
AlertPayload ringReportPayload({
  required AlertPayload stored,
  required DateTime alarmDateTime,
  required int osId,
  required AlertLabels labels,
  required bool nativelySnoozed,
}) {
  final reported = stored.copyWith(osId: osId);
  final armedFor = stored.fireAtMs;
  if (armedFor == null || armedFor == alarmDateTime.millisecondsSinceEpoch) {
    return reported;
  }
  return labels
      .moved(reported, alarmDateTime)
      .copyWith(reRing: nativelySnoozed);
}

/// Whether an unanswered ring's Silence-after window counts down, from what
/// the `alarm` host says it is sounding: this ring ([sounding]), or any ring
/// at all ([anySounding]).
///
/// The window is for the time a ring is heard. The host sounds one alarm at a
/// time and holds one that comes due during another, silent, until that one
/// ends — while the plugin's fallback timer tells the app of the held alarm
/// at its own instant anyway (the fork's Patch 7 keeps that, with the app in
/// front), so the binding tracks it from then. A window counted from then ran
/// out while the alarm waited: two alarms due a minute apart, nobody
/// answering, and the second was silenced a minute after it began to sound,
/// then reported Missed.
///
/// So the window waits only while the host says it sounds another alarm and
/// not this one. Anything else counts, as it did before the host was asked:
/// this ring sounding, and a host sounding nothing — an announced alarm that
/// nothing will promote still has its page closed after one window, and a
/// host that cannot answer reads as sounding nothing (the plugin answers
/// `false` to a query that failed). That is what bounds the wait: it lasts
/// only while the host names a ring in front, which it sounds, so that ring's
/// own window runs here and ends it, and the host then promotes the held one
/// or drops it.
///
/// Pure: what the two answers mean. When the binding asks — a ring tracked,
/// the ringing set changing while a ring is held, a window running out — and
/// in which order it reads the two, which a race between the reads turns on,
/// are the binding's own (`AndroidAlertGateway._silenceWindowRuns`).
bool alertSilenceWindowRuns({
  required bool sounding,
  required bool anySounding,
}) => sounding || !anySounding;

/// The line one record of the `alarm` plugin's log is printed as, or null for
/// a record below a warning.
///
/// The plugin reports through `package:logging`, which prints nothing until
/// somebody listens — and what it has to say is exactly what no diagnostic of
/// the app's can see: a ring whose settings it could not find is dropped with
/// one `severe` and no callback, which reads from outside as an alarm that
/// sounded with no page. Its `info` lines narrate every arm and stop and stay
/// unprinted.
String? alarmPluginLogLine(LogRecord record) {
  if (record.level < Level.WARNING) return null;
  return '[alarm] ${record.level.name} ${record.loggerName}: ${record.message}';
}

/// Action ids carried on a reminder notification. Matched in the background
/// isolate, so they are plain literals on both sides of a process boundary.
const String kAlertSnoozeActionId = 'alert_snooze';
const String kAlertDoneActionId = 'alert_done';

/// Action ids on an upcoming-alarm notice (OS-3). Both are foreground
/// actions — the background isolate never writes the database — so they
/// arrive in [AndroidAlertGateway._handleResponse] with the app up.
const String kAlertSkipActionId = 'alert_skip';
const String kAlertOpenActionId = 'alert_open';

/// `Notification.FLAG_INSISTENT` — what makes the fallback alarm loop its
/// sound until it is dismissed.
///
/// Hoisted and non-`const` because `Int32List.fromList` is not a constant
/// expression, which is also why the details object carrying it cannot be
/// `const` (§10.5).
final Int32List _insistentFlags = Int32List.fromList(<int>[4]);

/// Handles a reminder's Snooze and Done in a **background isolate**.
///
/// It shares nothing with the app: no database, no facades, no settings
/// service, no `EventSkips` (a process-global static that would read empty
/// here), and therefore **it never plans**. Done cancels; Snooze cancels and
/// re-posts the same notification [AlertPayload.snoozeMinutes] from now, which
/// is why the payload carries that number at all — and, beside it, the
/// language its words were written in, its tint and the file its avatar is
/// kept in, which is what lets the re-post come back as the reminder it was
/// ([snoozedRepost]).
///
/// The re-posted entry is marked `snooze: true`, and `AlertScheduler` never
/// cancels a platform entry that says so — the registry cannot learn about a
/// row written from here, and without that rule the next reconcile would
/// silently disarm the ten minutes the user just asked for.
@pragma('vm:entry-point')
void alertBackgroundActionHandler(NotificationResponse response) {
  final payload = AlertPayload.decode(response.payload);
  if (payload == null) return;
  final plugin = FlutterLocalNotificationsPlugin();
  switch (response.actionId) {
    case kAlertDoneActionId:
      unawaited(plugin.cancel(id: payload.osId));
    case kAlertSnoozeActionId:
      unawaited(_snoozeFromBackground(plugin, payload));
  }
}

Future<void> _snoozeFromBackground(
  FlutterLocalNotificationsPlugin plugin,
  AlertPayload payload,
) async {
  try {
    // **Before the cancel**, and before anything else is touched. The
    // platform took the reminder off the shade the moment its button was
    // pressed, so from here on every throw is a snooze that brings nothing
    // back: the words are put together first, where a failure still has a
    // fallback ([snoozedRepostFor]) and nothing has been cancelled for it yet.
    final repost = snoozedRepostFor(payload, DateTime.now());
    await plugin.cancel(id: payload.osId);
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // Whatever `timezone` defaulted to is still a location; a snooze in the
      // wrong zone is better than no snooze.
    }
    await plugin.zonedSchedule(
      id: repost.osId,
      title: repost.title,
      body: repost.body,
      scheduledDate: tz.TZDateTime.from(repost.at, tz.local),
      payload: repost.payload.encode(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      notificationDetails: NotificationDetails(android: repost.details),
    );
  } catch (e) {
    debugPrint('[AndroidAlertGateway] background snooze failed: $e');
  }
}

/// [snoozedRepost] in the language the entry's own lines were written in —
/// or, should putting its words together throw, [snoozedRepostTitleOnly].
///
/// An entry armed before payloads named their language is answered in the
/// device's, as the isolate always did: reading the app's stored one would
/// mean a database.
///
/// Public, with [stringsFor] a parameter, for its suite alone. Which
/// language is asked for and what a failure falls back to are the two things
/// the isolate decides for itself, and neither can be seen from outside it:
/// a re-post in the phone's language, or none at all, looks like any other
/// until somebody snoozes a reminder with the app closed.
SnoozedRepost snoozedRepostFor(
  AlertPayload payload,
  DateTime now, {
  AppLocalizations Function(String? languageCode) stringsFor =
      alertGatewayStrings,
}) {
  try {
    return snoozedRepost(payload, now, stringsFor(payload.languageCode));
  } catch (e) {
    debugPrint('[AndroidAlertGateway] snoozed text failed, title only: $e');
    return snoozedRepostTitleOnly(payload, now);
  }
}

/// A reminder as its Snooze posts it again: the id it is armed under, the
/// instant, its words, and the payload and details it carries.
typedef SnoozedRepost = ({
  int osId,
  DateTime at,
  String title,
  String? body,
  AlertPayload payload,
  AndroidNotificationDetails details,
});

/// What the reminder [payload] comes back as, [AlertPayload.snoozeMinutes]
/// after [now], in [strings]' language.
///
/// **From the payload alone, and it formats nothing.** It runs in the
/// background isolate, where no database is open, the category facade is
/// empty and no date symbols are loaded: the words are placed, never
/// written, and the colour and the avatar are the ones stamped into the
/// entry when it was armed ([alertDecorOf]). A payload from before those
/// were stamped comes back without them, as every re-post used to.
///
/// The group is the entry's own too ([AlertPayload.grouped]): the isolate
/// cannot ask which Android it runs on, and a reminder armed in the group
/// that came back loose would be bundled at post, and so silenced, beside
/// any other reminder still standing.
///
/// The lines the entry carries are left as they are — nothing here could
/// write a new one, and what a snoozed reminder names is the event's time,
/// not its own.
SnoozedRepost snoozedRepost(
  AlertPayload payload,
  DateTime now,
  AppLocalizations strings,
) {
  final entry = _snoozedEntry(payload, now);
  final content = alertNotificationContent(
    AlertNotificationKind.snoozed,
    entry.payload,
    strings,
  );
  return (
    osId: entry.payload.osId,
    at: entry.at,
    title: content.title,
    body: content.text,
    payload: entry.payload,
    details: alertReminderDetails(
      strings,
      content,
      decor: alertDecorOf(entry.payload),
      grouped: entry.payload.grouped,
    ),
  );
}

/// [snoozedRepost] when its words could not be put together: the title the
/// entry carries, its decor and its group, and nothing that takes a string —
/// no text line and no buttons.
///
/// A reminder that comes back bare can still be opened and swiped away; one
/// that does not come back at all is ten minutes the user asked for and
/// lost.
SnoozedRepost snoozedRepostTitleOnly(AlertPayload payload, DateTime now) {
  final entry = _snoozedEntry(payload, now);
  final decor = alertDecorOf(entry.payload);
  final group = _reminderGroup(entry.payload.grouped);
  return (
    osId: entry.payload.osId,
    at: entry.at,
    title: payload.title,
    body: null,
    payload: entry.payload,
    details: AndroidNotificationDetails(
      kAlertReminderChannelId,
      // The channel is there — the reminder being snoozed was posted on it —
      // and the plugin names a channel only when it has to create one.
      kAlertReminderChannelId,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      icon: kAlertSmallIcon,
      color: decor.color,
      largeIcon: _largeIconOf(decor),
      groupKey: group.key,
      groupAlertBehavior: group.alertBehavior,
    ),
  );
}

/// The entry a snoozed reminder is re-armed as: a snooze under the snooze
/// id, due at its own instant.
///
/// The id is the bare seed — there is no registry here to probe against, so
/// re-snoozing the same alert on the same day lands on the same entry.
({DateTime at, AlertPayload payload}) _snoozedEntry(
  AlertPayload payload,
  DateTime now,
) {
  final at = now.add(Duration(minutes: payload.snoozeMinutes));
  final osId = resolveAlertOsId(
    seed: alertOsIdSeed(
      database: payload.database,
      alertId: payload.alertId,
      dayUtc: payload.dayUtc,
      kind: AlertKind.snooze,
    ),
    isTaken: (_) => false,
  );
  return (
    at: at,
    payload: payload.copyWith(
      osId: osId,
      snooze: true,
      fireAtMs: at.millisecondsSinceEpoch,
    ),
  );
}

/// What a notification wears beyond its words: the colour of the event's
/// avatar, and the file that avatar is kept in once it has been drawn
/// ([alertLargeIconFileName]).
///
/// Either may be missing — an entry armed before payloads carried a tint, an
/// avatar that could not be drawn in time — and the notification is posted
/// without it. Never the other way round: decor is not worth an alert.
typedef AlertDecor = ({Color? color, String? iconFile});

/// The decor a payload vouches for by itself: the tint and the icon file
/// stamped into it when it was armed.
///
/// All there is in the background isolate, where the category facade is
/// empty and nothing can be drawn. The binding does better where it can —
/// it has the facade to fall back on and can draw an avatar that is missing.
AlertDecor alertDecorOf(AlertPayload payload) {
  final tint = payload.tintValue;
  return (color: tint == null ? null : Color(tint), iconFile: payload.iconFile);
}

/// The id a notification action is delivered under. Stop on the fallback
/// alarm has always travelled as Done: the isolate answers both by
/// cancelling.
String _actionIdOf(AlertNotificationAction action) => switch (action) {
  AlertNotificationAction.snooze => kAlertSnoozeActionId,
  AlertNotificationAction.done => kAlertDoneActionId,
  AlertNotificationAction.stop => kAlertDoneActionId,
  AlertNotificationAction.skip => kAlertSkipActionId,
  AlertNotificationAction.open => kAlertOpenActionId,
};

/// [content]'s buttons, in its order. [showsUserInterface] is the route:
/// false delivers an action to [alertBackgroundActionHandler] even while the
/// app is in front (§10.5), true brings the app up to answer it.
List<AndroidNotificationAction> _actionsOf(
  AlertNotificationContent content, {
  required bool showsUserInterface,
}) => <AndroidNotificationAction>[
  for (final action in content.actions)
    AndroidNotificationAction(
      _actionIdOf(action.action),
      action.label,
      showsUserInterface: showsUserInterface,
      cancelNotification: true,
    ),
];

/// A file rather than bytes: a scheduled notification is kept by the plugin
/// as JSON until it is due, and the background isolate can hand a path on
/// where it could never draw.
FilePathAndroidBitmap? _largeIconOf(AlertDecor decor) {
  final file = decor.iconFile;
  return file == null ? null : FilePathAndroidBitmap(file);
}

/// The big-text style holds the text line as well as what is added under
/// it: the platform draws it **in place of** the collapsed text, so a style
/// carrying the excerpt alone would hide the line that says what this is.
BigTextStyleInformation? _expandedOf(AlertNotificationContent content) {
  final expanded = content.expandedText;
  return expanded == null ? null : BigTextStyleInformation(expanded);
}

/// What a reminder's details say of grouping: [kAlertGroupKey] with every
/// member alerting for itself, or nothing at all — the loose reminder of a
/// phone below Android 16, and of an entry armed before the group existed.
///
/// **Never a summary**, in either answer: the key is there so the platform
/// leaves the reminder alone until it has sounded, not to draw a group, and
/// a summary is exactly what [kAlertGroupKey] was chosen to do without.
({String? key, GroupAlertBehavior alertBehavior}) _reminderGroup(
  bool grouped,
) => grouped
    ? (key: kAlertGroupKey, alertBehavior: GroupAlertBehavior.children)
    : (key: null, alertBehavior: GroupAlertBehavior.all);

/// How a reminder is posted — and its snoozed re-post, which differs from it
/// in [content] alone.
///
/// Both buttons are background actions: Done and Snooze are answered by
/// [alertBackgroundActionHandler] with no app, no database and no plan.
///
/// [grouped] is whether it is posted in the app's group, which the binding
/// decides from the phone's Android release ([alertRemindersGroupedOn]) and
/// the re-post reads off the entry it is re-posting.
AndroidNotificationDetails alertReminderDetails(
  AppLocalizations strings,
  AlertNotificationContent content, {
  AlertDecor decor = (color: null, iconFile: null),
  bool grouped = false,
}) {
  final group = _reminderGroup(grouped);
  return AndroidNotificationDetails(
    kAlertReminderChannelId,
    strings.alertsReminderChannel,
    channelDescription: strings.alertsReminderChannelDesc,
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
    icon: kAlertSmallIcon,
    color: decor.color,
    largeIcon: _largeIconOf(decor),
    styleInformation: _expandedOf(content),
    actions: _actionsOf(content, showsUserInterface: false),
    groupKey: group.key,
    groupAlertBehavior: group.alertBehavior,
  );
}

/// How the upcoming notice is posted.
///
/// Quiet by its channel ([kAlertQuietChannelId]), whatever else of the app
/// stands on the shade. The `silent` flag it carried while it shared the
/// reminder channel is kept under that: where the channel is low it changes
/// nothing, and it is what still holds one notice quiet on a phone whose
/// owner has turned the channel up.
///
/// It also dies at the alarm's instant ([timeoutAfterMillis], from
/// [noticeTimeoutMillis]): a ring stopped or snoozed natively with no Dart
/// running cancels nothing on this side, and a notice that outlived its
/// alarm would offer to skip an occurrence that already happened. Skip and
/// Open are foreground actions — Skip changes the plan, and the background
/// isolate never does.
AndroidNotificationDetails alertNoticeDetails(
  AppLocalizations strings,
  AlertNotificationContent content, {
  required int timeoutAfterMillis,
  AlertDecor decor = (color: null, iconFile: null),
}) {
  return AndroidNotificationDetails(
    kAlertQuietChannelId,
    strings.alertsQuietChannel,
    channelDescription: strings.alertsQuietChannelDesc,
    importance: Importance.low,
    priority: Priority.low,
    silent: true,
    timeoutAfter: timeoutAfterMillis,
    category: AndroidNotificationCategory.reminder,
    icon: kAlertSmallIcon,
    color: decor.color,
    largeIcon: _largeIconOf(decor),
    styleInformation: _expandedOf(content),
    actions: _actionsOf(content, showsUserInterface: true),
  );
}

/// How a Missed notice is posted: on the quiet channel, and dated by the
/// alarm it reports on rather than by the moment it was noticed.
///
/// The channel ([kAlertQuietChannelId]) is what makes it the quiet notice it
/// was always called, and it took two tries to get there. It asked for low
/// importance alone at first, on the reminder channel, whose importance was
/// frozen at high — so it arrived as loudly as a reminder. Then it was
/// flagged `silent`, which held only for as long as it stood alone: beside an
/// upcoming notice or the session chip Android 16 bundled the two under a
/// summary of its own, and that summary sounded. The flag stays, for the
/// reason [alertNoticeDetails] gives.
///
/// [dueAtMs] is the instant the alarm was due, which is what the header's
/// clock then reads; an entry from before payloads carried one is dated by
/// its posting, as before.
AndroidNotificationDetails alertMissedDetails(
  AppLocalizations strings,
  AlertNotificationContent content, {
  required int? dueAtMs,
  AlertDecor decor = (color: null, iconFile: null),
}) {
  return AndroidNotificationDetails(
    kAlertQuietChannelId,
    strings.alertsQuietChannel,
    channelDescription: strings.alertsQuietChannelDesc,
    importance: Importance.low,
    priority: Priority.low,
    silent: true,
    when: dueAtMs,
    icon: kAlertSmallIcon,
    color: decor.color,
    largeIcon: _largeIconOf(decor),
    styleInformation: _expandedOf(content),
  );
}

/// How the alarm tier is posted on the notification backend
/// ([kAlarmTierUsesNotifications]): insistent, on the alarm stream, with a
/// full-screen intent, and gone after [timeoutAfterMillis] — the
/// Silence-after setting, which the platform keeps for this backend.
AndroidNotificationDetails alertFallbackAlarmDetails(
  AppLocalizations strings,
  AlertNotificationContent content, {
  required int timeoutAfterMillis,
  AlertDecor decor = (color: null, iconFile: null),
}) {
  return AndroidNotificationDetails(
    kAlertAlarmChannelId,
    strings.alertsAlarmChannel,
    channelDescription: strings.alertsAlarmChannelDesc,
    importance: Importance.max,
    priority: Priority.max,
    color: decor.color,
    largeIcon: _largeIconOf(decor),
    styleInformation: _expandedOf(content),
    category: AndroidNotificationCategory.alarm,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    fullScreenIntent: true,
    ongoing: true,
    autoCancel: false,
    enableVibration: true,
    visibility: NotificationVisibility.public,
    icon: kAlertSmallIcon,
    additionalFlags: _insistentFlags,
    timeoutAfter: timeoutAfterMillis,
    actions: _actionsOf(content, showsUserInterface: false),
  );
}

/// What the `alarm` plugin draws a ring's own notification from.
///
/// Title, text, the two button labels, the small icon and one colour are
/// all the plugin takes: it builds the notification natively, colorized, in
/// its own fixed order — Stop, then Snooze — so the avatar and the expanded
/// text the other kinds carry have nowhere to go.
NotificationSettings alertRingSettings(
  AlertNotificationContent content,
  Color color,
) {
  return NotificationSettings(
    title: content.title,
    body: content.text,
    stopButton: content.labelOf(AlertNotificationAction.stop),
    androidSnoozeButton: content.labelOf(AlertNotificationAction.snooze),
    icon: kAlertSmallIcon,
    iconColor: color,
  );
}

/// What `SessionChip.kt` draws the session chip from — every key it reads.
///
/// The platform only draws: each string arrives localized, the colour
/// resolved and the avatar as the path of a file. The two buttons travel by
/// name and are added natively in the order [content] gives them, Done
/// first (`test/android/session_chip_channel_test.dart` holds the two sides
/// to each other).
Map<String, Object?> sessionChipArguments({
  required AlertPayload payload,
  required AlertNotificationContent content,
  required DateTime startedAt,
  DateTime? endsAt,
  int? progress,
  bool refresh = false,
  AlertDecor decor = (color: null, iconFile: null),
}) {
  return <String, Object?>{
    'payload': payload.encode(),
    'refresh': refresh,
    'channelId': kAlertQuietChannelId,
    'title': content.title,
    'text': content.text,
    'doneLabel': content.labelOf(AlertNotificationAction.done),
    'openLabel': content.labelOf(AlertNotificationAction.open),
    'startedAtMs': startedAt.millisecondsSinceEpoch,
    'endsAtMs': endsAt?.millisecondsSinceEpoch,
    'progress': progress,
    'color': decor.color?.toARGB32(),
    'largeIcon': decor.iconFile,
  };
}

/// Everything an entry is armed **under** that is the phone's or the app's
/// rather than the plan's, as the token the registry keeps per row — spelled
/// `<backend>[@floor]~g4.<language>.<H|h>`.
///
/// The backend and the volume bucket are what a ring will sound like. A
/// volume that follows the phone stays unspelled, as it always was: it is
/// the everyday answer.
///
/// The rest is what an entry **says**. A notification's title, text and
/// buttons are frozen into the platform when it is armed, and a time is
/// written into its payload once, on the UI isolate — so an app switched to
/// another language, or a phone moved between the 12- and the 24-hour clock,
/// left every standing entry reading the old way until something unrelated
/// re-armed it. Named here, either change re-arms the planned entries on the
/// next pass, and [kAlertArmGrammarToken] does the same once, on the first
/// pass of a build that changed what they say.
///
/// Pure, and all of what [AlertGateway.refreshArmContext] answers on
/// Android.
String alertArmContext({
  required String backend,
  required AlertRingVolume volume,
  required String language,
  required bool use24Hour,
}) {
  final loudness = volume == AlertRingVolume.follow ? '' : '@${volume.name}';
  final clock = use24Hour ? 'H' : 'h';
  return '$backend$loudness$kAlertArmGrammarToken.$language.$clock';
}

/// The side of a notification's large icon, in logical pixels: what the
/// platform's own templates draw one at.
const double kAlertLargeIconDp = 48;

/// The directory, under the app's support directory, the drawn avatars are
/// kept in.
const String kAlertIconDirectory = 'alert_icons';

/// The densest screen an avatar is drawn for, the sparsest, and the one
/// assumed when the engine has no view to ask.
const double _iconMaxPixelRatio = 4;
const double _iconMinPixelRatio = 1;
const double _iconDefaultPixelRatio = 3;

/// The side, in device pixels, an avatar is drawn at for a screen of
/// [devicePixelRatio] — [kAlertLargeIconDp] at the screen's own density, so
/// the platform neither blows it up nor throws pixels away.
///
/// Bounded at both ends: the ratio comes from the engine's view, and a
/// reading taken with no view attached must not ask for a bitmap of nothing,
/// nor one large enough to matter.
int alertLargeIconPixels(double? devicePixelRatio) {
  final ratio =
      devicePixelRatio == null ||
          !devicePixelRatio.isFinite ||
          devicePixelRatio <= 0
      ? _iconDefaultPixelRatio
      : devicePixelRatio.clamp(_iconMinPixelRatio, _iconMaxPixelRatio);
  return (kAlertLargeIconDp * ratio).round();
}

/// The font size the glyph is drawn at inside a disc [pixels] across:
/// `EventAvatar`'s own glyph-to-disc ratio, so the notification wears the
/// avatar the app draws for the same event.
double alertLargeIconGlyphSize(int pixels) =>
    pixels * EventAvatar.iconSize / (EventAvatar.radius * 2);

/// The file one drawn avatar is kept under: one per glyph, colour, size and
/// way of drawing it.
///
/// Named from everything that decides the picture, and nothing else. Two
/// events that share an icon and a colour share a file — and a file found
/// under a name is never drawn again, so the name has to say how the avatar
/// was drawn as well as what it shows. The disc's alpha (out of 255) and the
/// glyph's size (in pixels) are the in-app avatar's own constants: left out,
/// the build that changes either would go on posting the old picture for
/// every avatar a phone had already drawn, beside the new one for the rest.
/// In the name, a change of `EventAvatar` names new files by itself, and the
/// old ones are simply never asked for again. **A change to how
/// [paintAlertLargeIcon] itself draws has to add to the name too.** The size
/// of the bitmap is there because a phone's display density can be changed
/// under a standing install.
///
/// [discAlpha] and [glyphSize] default to what the painter draws with. They
/// are parameters for the suite alone, which holds the name to each.
String alertLargeIconFileName(
  IconData icon,
  Color color,
  int pixels, {
  double discAlpha = EventAvatar.backgroundAlpha,
  double? glyphSize,
}) {
  final font = '${icon.fontPackage ?? ''}${icon.fontFamily ?? ''}'
      .replaceAll(RegExp('[^A-Za-z0-9]'), '')
      .toLowerCase();
  final glyph = icon.codePoint.toRadixString(16);
  final tint = color.toARGB32().toRadixString(16).padLeft(8, '0');
  final alpha = (discAlpha * 255).round();
  final glyphPixels = (glyphSize ?? alertLargeIconGlyphSize(pixels)).round();
  return '${font.isEmpty ? 'text' : font}_${glyph}_${tint}_$pixels'
      '_a${alpha}_g$glyphPixels.png';
}

/// Paints the avatar [alertLargeIconFileName] names onto [canvas], a square
/// [pixels] across: the glyph in [color] on a disc of the same colour at
/// `EventAvatar`'s own alpha.
void paintAlertLargeIcon(
  Canvas canvas,
  IconData icon,
  Color color,
  int pixels,
) {
  final side = pixels.toDouble();
  canvas.drawCircle(
    Offset(side / 2, side / 2),
    side / 2,
    Paint()..color = color.withValues(alpha: EventAvatar.backgroundAlpha),
  );
  final painter = TextPainter(textDirection: TextDirection.ltr)
    ..text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: alertLargeIconGlyphSize(pixels),
        // What `Icon` sets: an icon font's glyph fills its em box, and any
        // other line height would move it off the disc's centre.
        height: 1,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: color,
      ),
    )
    ..layout();
  painter.paint(
    canvas,
    Offset((side - painter.width) / 2, (side - painter.height) / 2),
  );
  painter.dispose();
}

/// Localizations for a surface with no `BuildContext`: [languageCode]'s, or
/// off the **device** locale when it names none or one the app does not
/// ship — the `_errorLocalizations` shape in `main.dart`.
///
/// The main isolate passes the app's own stored language. The background
/// isolate cannot read it, and passes the one its entry's payload was
/// written in.
AppLocalizations alertGatewayStrings([String? languageCode]) {
  try {
    if (languageCode != null) {
      return lookupAppLocalizations(Locale(languageCode));
    }
  } catch (_) {
    // An unsupported stored code falls through to the device locale.
  }
  try {
    final device = WidgetsBinding.instance.platformDispatcher.locale;
    final supported = AppLocalizations.supportedLocales.any(
      (locale) => locale.languageCode == device.languageCode,
    );
    return lookupAppLocalizations(
      supported ? Locale(device.languageCode) : const Locale('en'),
    );
  } catch (_) {
    return lookupAppLocalizations(const Locale('en'));
  }
}

/// The Android binding: the one place in the app that talks to an alarm
/// plugin.
///
/// Two backends behind one seam. The **Alarm** tier rings through `alarm`,
/// which owns its own foreground service, its own looping audio and its own
/// full-screen intent, and the **Reminder** tier posts through
/// `flutter_local_notifications`, which is the only one of the two that can
/// respect silent mode. [kAlarmTierUsesNotifications] moves the Alarm tier
/// onto the second backend without touching anything above this file.
///
/// Nothing in the class is reachable from a test: `AlertAvailability` gates
/// the GetIt registration to Android, so every suite keeps the
/// `NoOpAlertGateway` and no plugin channel is ever stubbed. That is why
/// everything it *decides* about what an alert looks like lives above it, in
/// pure top-level functions it only calls — the words in
/// `alertNotificationContent`, how each kind is posted in the details
/// functions, the arm context, the avatar's name and size.
class AndroidAlertGateway extends AlertGateway {
  /// The activity's own pushes are answered from construction on: nothing
  /// here reaches the platform, and a warm show intent arriving before
  /// [initialize] has finished must not land on a channel with no handler.
  AndroidAlertGateway() {
    _platform.setMethodCallHandler(_handlePlatformCall);
  }

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  final StreamController<AlertPayload> _ringing =
      StreamController<AlertPayload>.broadcast();

  final StreamController<AlertRingEnd> _ringEnded =
      StreamController<AlertRingEnd>.broadcast();

  /// The warm half of the alarm-clock show intent — see [showAlarms].
  final StreamController<void> _showAlarms = StreamController<void>.broadcast();

  /// Rings in progress, by os id, with the payload each rang under.
  ///
  /// Doubles as the emit-once guard: `Alarm.ringing` is a `ValueStream` that
  /// replays, and the fallback path can deliver the same full-screen entry
  /// through both the response callback and the launch details — the queue
  /// dedupes too, but a stream that emits twice makes the `fired` marking run
  /// twice as well. The payload is kept because [ringEnded] has to hand it
  /// back: by the time a ring is over the `alarm` package has unsaved it.
  final Map<int, AlertPayload> _rings = <int, AlertPayload>{};

  /// Avatars looked for on disk, or being drawn, by file name — a reconcile
  /// arms up to 48 entries and most share a category, so each file is asked
  /// after once per process rather than once per fire, and two posts that
  /// want the same avatar at once share the one drawing. A lookup that ended
  /// with no file is forgotten, so the next post tries again.
  final Map<String, Future<String?>> _iconFiles = <String, Future<String?>>{};

  /// Where the avatars are kept, once it has been resolved.
  Directory? _iconDirectory;

  /// The subset of [_rings] the `alarm` package reported, which is the only
  /// subset whose disappearance from `Alarm.ringing` means anything. A
  /// fallback ring never appears in that set, so its absence says nothing.
  final Set<int> _pluginRings = <int>{};

  /// The ids this binding is itself asking the plugin to stop, for as long as
  /// that call is out: [stopRinging] and [cancel] put an id in before
  /// `Alarm.stop` and take it out when the call comes back.
  ///
  /// The plugin takes a stopped alarm out of its ringing set only once the
  /// platform has answered, and when the stop lets a queued alarm through,
  /// the platform tells of that new ring first. The set that carries the new
  /// ring then still holds the stopped one — by now in neither map here, so
  /// [_handleRinging] took it for a ring nobody had been told of, tracked
  /// and announced it again, and ended it on the next emission as a Stop on
  /// the notification. That is an acknowledgement: it cancelled the snooze a
  /// Snooze on the alarm page had just armed, posted the session chip and
  /// removed an event set to go after its alarm (seen on the emulator with
  /// two alarms due in one minute, 2026-10-05).
  final Set<int> _stopping = <int>{};

  StreamSubscription<AlarmSet>? _ringingSub;

  /// The plugin's own changes to its alarms, subscribed **before**
  /// `Alarm.init()` so the drain of markers recorded while no Dart was
  /// running is delivered here too.
  StreamSubscription<AlarmEvent>? _eventsSub;

  /// Snooze moves not yet handed to the scheduler, keyed by
  /// `(id, recordedAt)` because the stream is at-least-once. Nothing is
  /// applied from here: [takeMoves] hands them to the reconcile, which writes
  /// the row and then acknowledges.
  final Map<(int, int), AlertMove> _moves = <(int, int), AlertMove>{};

  /// The alarms the plugin has moved by a Snooze on its own notification
  /// since they were last armed here: what [ringReportPayload] is told so the
  /// ring that follows can say it is one.
  ///
  /// Apart from [_moves], which the reconcile empties as it writes each move
  /// down — this has to outlive that, until the moved alarm rings and that
  /// ring is over. An id leaves when its ring ends in anything but another
  /// snooze, when its entry is cancelled, and when an entry is armed under
  /// it afresh: a new arming is a new alarm, whatever the id's past.
  final Set<int> _snoozeMoved = <int>{};

  /// The plugin's log, printed — see [alarmPluginLogLine].
  StreamSubscription<LogRecord>? _pluginLogSub;

  /// Stops a ring that nobody acknowledged, after the Silence-after setting.
  ///
  /// The `alarm` package has no timeout of its own — the fallback path gets
  /// `timeoutAfter` from the platform — so the app holds the timer whenever
  /// Dart is up for the ring. That is not always: with the phone in use and
  /// the app not running, the ring is a native heads-up and nothing here runs,
  /// so that ring has no timeout — but it also has someone looking at it.
  ///
  /// Counted from when the host sounds the ring, not from when it is tracked
  /// ([_heldRings]).
  final Map<int, Timer> _silenceTimers = <int, Timer>{};

  /// The rings tracked here that the host holds behind another one: told of
  /// by the plugin's fallback timer at their own instant, silent until the
  /// ring in front of them ends, so their Silence-after window has not begun
  /// ([alertSilenceWindowRuns]). [_handleRinging] asks after them again at
  /// every change to the ringing set, and the first answer that finds one
  /// sounding starts its window.
  final Set<int> _heldRings = <int>{};

  /// How many times the plugin's ringing set has been emitted, so an asking
  /// in [_armSilenceTimer] can tell that the set changed while it waited on
  /// the host.
  int _ringingEmissions = 0;

  AlertIntent? _launchIntent;
  bool _launchIntentRead = false;

  Future<void>? _initialization;

  /// The app's own stored language, or null for "follow the device".
  ///
  /// Read as the binding first comes up ([_readLanguageCode]) and again once
  /// per pass by [refreshArmContext] ([_rereadLanguageCode]), never per
  /// scheduled entry: a query on the reconcile's inner loop for a value that
  /// changes once in a phone's life. Once per pass is what lets a change of
  /// language reach the entries already standing — it moves the arm context,
  /// and the pass that sees it writes them again.
  String? _languageCode;

  /// Whether [_initialize] has made its direct read of [_languageCode].
  ///
  /// Set by the first start and never taken back. [initialize] keeps no
  /// failure and every scheduling pass asks for it, so on a binding whose
  /// start keeps failing every pass is another start — and
  /// [_readLanguageCode] is the one read here that also decides which
  /// database is active. A start that is retried keeps the language the
  /// binding has; the per-pass re-read corrects it.
  bool _languageReadAtStart = false;

  /// How loud the next ring this binding arms will be, re-read once per pass by
  /// [refreshArmContext].
  ///
  /// A field rather than a read per fire: the alarm stream is one number for
  /// the whole phone, and asking the platform 48 times per reconcile for it
  /// would put a channel round trip on the diff's inner loop. It starts at
  /// [AlertRingVolume.follow] so a `schedule` that somehow arrives before a
  /// pass leaves the user's volume alone — the safe half of the choice.
  AlertRingVolume _ringVolume = AlertRingVolume.follow;

  /// What this pass writes its payloads with, rebuilt by [refreshArmContext]
  /// for the reason [_ringVolume] is: the phone's clock style can change
  /// between two passes and must not change inside one.
  AlertLabels? _labels;

  /// Whether this phone's reminders are armed in [kAlertGroupKey], once the
  /// activity has said which Android it is running — see [_groupsReminders].
  bool? _remindersGrouped;

  static const MethodChannel _platform = MethodChannel(
    'com.alexzamfir.anta/alerts',
  );

  @override
  String get backendName =>
      kAlarmTierUsesNotifications ? 'notification' : 'alarm';

  @override
  bool get tracksPending => true;

  @override
  bool get supportsSoundPicker => true;

  AppLocalizations get _l10n => alertGatewayStrings(_languageCode);

  @override
  AlertLabels get labels => _labels ??= _labelsFor(_languageCode);

  /// Labels in one language, on the clock the phone is on right now.
  static AlertLabels _labelsFor(String? languageCode) => AlertLabels(
    strings: alertGatewayStrings(languageCode),
    use24Hour: WidgetsBinding.instance.platformDispatcher.alwaysUse24HourFormat,
  );

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// Brings both plugins up, exactly once.
  ///
  /// Called from `configureDependencies()` on Android and nowhere else. It is
  /// deliberately **not** in the constructor: a binding that initialized
  /// plugins the moment it was built could not be registered before the
  /// database is open, and `Alarm.init()` drains the host's recorded events,
  /// which must not happen twice.
  ///
  /// A failure is **not** memoized. Every entry point awaits this, so a cached
  /// rejection would turn one transient platform error at launch into a
  /// binding that refuses to schedule for the life of the process.
  Future<void> initialize() {
    return _initialization ??= _initialize().onError<Object>((error, stack) {
      _initialization = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<void> _initialize() async {
    await _reportRingsInProgress();
    if (!_languageReadAtStart) {
      _languageReadAtStart = true;
      _languageCode = await _readLanguageCode();
    }
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      debugPrint('[AndroidAlertGateway] timezone lookup failed: $e');
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(kAlertSmallIcon),
      ),
      onDidReceiveNotificationResponse: _handleResponse,
      onDidReceiveBackgroundNotificationResponse: alertBackgroundActionHandler,
    );

    final l10n = _l10n;
    await _android?.createNotificationChannel(
      AndroidNotificationChannel(
        kAlertReminderChannelId,
        l10n.alertsReminderChannel,
        description: l10n.alertsReminderChannelDesc,
        importance: Importance.high,
      ),
    );
    await _android?.createNotificationChannel(
      AndroidNotificationChannel(
        kAlertQuietChannelId,
        l10n.alertsQuietChannel,
        description: l10n.alertsQuietChannelDesc,
        importance: Importance.low,
        // Both default to on, and Android freezes them with the importance.
        // At low importance neither does anything; they are off for the
        // phone whose owner turns this channel up — the only way to have its
        // three kinds on a lock screen that hides silent notifications —
        // where the channel that calls itself always silent would otherwise
        // start to sound.
        playSound: false,
        enableVibration: false,
      ),
    );
    await _android?.deleteNotificationChannel(
      channelId: kAlertLegacyAlarmChannelId,
    );
    await _android?.createNotificationChannel(
      AndroidNotificationChannel(
        kAlertAlarmChannelId,
        l10n.alertsAlarmChannel,
        description: l10n.alertsAlarmChannelDesc,
        importance: Importance.max,
        sound: const UriAndroidNotificationSound(kAlertAlarmChannelSoundUri),
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );

    // Before `init`, which is where the plugin has the most to say: it re-arms
    // every stored alarm there and reports what it could not. After the ring
    // lookup above on purpose — asking whether an alarm is ringing before the
    // plugin's own streams are filled logs a `severe` that means nothing.
    // Cancelled first, so a retried initialize prints each record once.
    await _pluginLogSub?.cancel();
    _pluginLogSub = Logger.root.onRecord.listen((record) {
      final line = alarmPluginLogLine(record);
      if (line != null) debugPrint(line);
    });

    // Before `init`, which drains the host's markers onto this stream; a
    // retried initialize re-subscribes and is replayed the buffer, which the
    // `(id, recordedAt)` key absorbs. The manual acknowledgement boundary
    // means a marker outlives a process death until the registry row exists.
    await _eventsSub?.cancel();
    _eventsSub = Alarm.events.listen(_handleAlarmEvent);
    await Alarm.init(acknowledgeEventsAutomatically: false);

    await _ringingSub?.cancel();
    _ringingSub = Alarm.ringing.listen(_handleRinging);
  }

  /// Announces the rings that started before this isolate existed.
  ///
  /// A cold start **caused** by an alarm has no engine for the plugin to tell,
  /// so the ring can only be found by asking — and `Alarm.init()` asks last,
  /// once it has stopped and re-armed every other stored alarm, a handful of
  /// platform round trips each. The app is on the lock screen for that whole
  /// stretch with no alarm page to show; asking first costs two round trips.
  ///
  /// Recorded as a plugin ring, so the first `Alarm.ringing` emission that
  /// lacks it ends it like any other. Best-effort: a failure here leaves the
  /// ring to `Alarm.init()`, as before.
  Future<void> _reportRingsInProgress() async {
    try {
      final now = DateTime.now();
      for (final alarm in await Alarm.getAlarms()) {
        if (alarm.dateTime.isAfter(now)) continue;
        if (!await Alarm.isRinging(alarm.id)) continue;
        final payload = AlertPayload.decode(alarm.payload);
        if (payload == null) continue;
        _pluginRings.add(alarm.id);
        _emitRing(_ringReport(payload, alarm));
      }
    } catch (e) {
      debugPrint('[AndroidAlertGateway] ring lookup at launch failed: $e');
    }
  }

  /// [ringReportPayload] for one of the plugin's alarms.
  ///
  /// The labels are the entry's own language rather than this pass's: a moved
  /// ring has its clock label rewritten, and that line sits beside others
  /// written when the entry was armed — possibly before the app's language
  /// was changed, and for an entry nothing re-arms.
  AlertPayload _ringReport(AlertPayload stored, AlarmSettings alarm) {
    return ringReportPayload(
      stored: stored,
      alarmDateTime: alarm.dateTime,
      osId: alarm.id,
      labels: _labelsFor(stored.languageCode ?? _languageCode),
      nativelySnoozed: _snoozeMoved.contains(alarm.id),
    );
  }

  /// Keeps a snooze move for the scheduler and acknowledges everything else
  /// at once — a drop of any cause, a move the platform forced — because an
  /// event never acknowledged is redelivered on every launch until its
  /// marker expires, and the registry's own late-fire path already covers
  /// what a drop means.
  void _handleAlarmEvent(AlarmEvent event) {
    if (event is AlarmMoved && event.cause == AlarmEventCause.snooze) {
      _snoozeMoved.add(event.id);
      _moves.putIfAbsent(
        (event.id, event.recordedAt.millisecondsSinceEpoch),
        () => (
          osId: event.id,
          nextRingAt: event.nextRingAt,
          recordedAt: event.recordedAt,
        ),
      );
      return;
    }
    unawaited(_acknowledge(event));
  }

  Future<void> _acknowledge(AlarmEvent event) async {
    try {
      await Alarm.acknowledgeEvent(event);
    } catch (e) {
      debugPrint('[AndroidAlertGateway] acknowledgeEvent(${event.id}) failed: $e');
    }
  }

  @override
  Future<List<AlertMove>> takeMoves() async {
    await initialize();
    final taken = List<AlertMove>.unmodifiable(_moves.values);
    _moves.clear();
    return taken;
  }

  @override
  Future<void> acknowledgeMove(AlertMove move) => _acknowledge(
    AlarmMoved(
      id: move.osId,
      cause: AlarmEventCause.snooze,
      recordedAt: move.recordedAt,
      nextRingAt: move.nextRingAt,
    ),
  );

  /// The activity's pushes, on the same channel the binding calls out on.
  ///
  /// `showAlarms` is the warm half of the alarm-clock show intent: the
  /// activity was already up when the lock-screen line was tapped, received
  /// the intent through `onNewIntent`, and says so here; the cold half is
  /// asked for by [launchIntent]. Anything else is not this binding's.
  Future<Object?> _handlePlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'showAlarms':
        if (!_showAlarms.isClosed) _showAlarms.add(null);
        return null;
      case 'openSession':
        final intent = OpenSessionIntent.fromPlatform(call.arguments);
        if (intent != null) PendingNavigationQueue.instance.enqueue(intent);
        return null;
      case 'quickAlarm':
        PendingNavigationQueue.instance.enqueue(const QuickAlarmIntent());
        return null;
      case 'keyguardChanged':
        LockScreenState.instance.setLocked(call.arguments == true);
        return null;
      default:
        throw MissingPluginException('${call.method} is not handled here');
    }
  }

  /// The app's language setting as the binding comes up, or null for "follow
  /// the device".
  ///
  /// Read straight off `user_settings` rather than through `SettingsService`:
  /// this runs inside `configureDependencies()`, where the database is open
  /// but the settings singleton may not be, and one row is all it wants.
  ///
  /// **For the binding's first start alone** ([_languageReadAtStart]).
  /// `AppDatabase.getInstance()` also decides which database is active, and
  /// at that start — the database opened a moment ago under the stored name —
  /// that decides nothing. Anywhere later it can, a start retried after a
  /// failed one included: [initialize] keeps no failure and every scheduling
  /// pass asks for it, so a binding whose start kept failing made this read
  /// on every pass. See [_rereadLanguageCode].
  Future<String?> _readLanguageCode() async {
    try {
      final db = await AppDatabase.getInstance();
      return await db.userSettingsDao.getValue(SettingsKeys.locale);
    } catch (e) {
      debugPrint('[AndroidAlertGateway] locale read failed: $e');
      return null;
    }
  }

  /// The same setting, read again for one scheduling pass — through the
  /// settings singleton, and **never** through `AppDatabase.getInstance()`.
  ///
  /// That call is this app's database switch. When the stored active name is
  /// no longer the open database's — the open one renamed in Settings, or a
  /// switch waiting behind its "close ANTA and open it again" dialog, the
  /// alarm page's among them — it closes the open connection and opens the
  /// other file, and every repository and service GetIt holds is left bound
  /// to the closed one: folders stop loading and the note being edited can
  /// no longer be saved. A pass runs two seconds after every resume and after
  /// every calendar save, so a read that went that way carried the switch out
  /// under the running app. The singleton is bound to the database that is
  /// open and asks nothing: it is made at launch, and dropped only by a
  /// switch that has already been carried out.
  ///
  /// A read that failed keeps the language the binding had. It is not a user
  /// who went back to the device's language: answered with null, one bad
  /// query would move the arm context and write every standing entry again
  /// in a language nobody chose, and the next pass would write them all back.
  Future<String?> _rereadLanguageCode() async {
    try {
      return await (await SettingsService.getInstance()).getLocaleCode();
    } catch (e) {
      debugPrint('[AndroidAlertGateway] locale re-read failed: $e');
      return _languageCode;
    }
  }

  // ── Ring handling ────────────────────────────────────────────────────

  /// `Alarm.ringing` emits an **empty set on subscribe** (it is an rxdart
  /// `ValueStream`), so an unguarded listener would push an alarm page on
  /// every single launch — an empty set simply has nothing to emit.
  ///
  /// The set **shrinking** is the other half. A ring this binding is tracking
  /// that has left the set, and that neither [stopRinging] nor [cancel] took
  /// out of [_rings] first, ended from the package's own notification — the
  /// only controls there are when the phone is in use, since Android turns a
  /// full-screen intent into a heads-up then. Which control tells itself: a
  /// Snooze leaves the alarm in `Alarm.scheduled` at its new instant and a
  /// Stop removes it from both. The plugin's `_applyMove` publishes the
  /// ringing set first in source order, but both subjects deliver
  /// asynchronously and a `BehaviorSubject` sets its `value` at `add`, so by
  /// the time this listener runs `Alarm.scheduled.value` already holds the
  /// moved alarm — the fork's `alarm_snooze_test.dart` pins that, because a
  /// sync subject or a reordered `_applyMove` would turn every native Snooze
  /// into a dismissal here.
  void _handleRinging(AlarmSet set) {
    _ringingEmissions++;
    final live = <int>{for (final alarm in set.alarms) alarm.id};
    for (final osId in _pluginRings.toList()) {
      if (live.contains(osId)) continue;
      _endRing(
        osId,
        Alarm.scheduled.value.containsId(osId)
            ? AlertRingEndCause.snoozed
            : AlertRingEndCause.dismissed,
      );
    }
    for (final alarm in set.alarms) {
      // In the plugin's set only because the stop this binding sent for it
      // has not come back yet ([_stopping]): not a ring to announce.
      if (_stopping.contains(alarm.id)) continue;
      final payload = AlertPayload.decode(alarm.payload);
      if (payload == null) continue;
      _pluginRings.add(alarm.id);
      _emitRing(_ringReport(payload, alarm));
    }
    // A held ring starts to sound when the one in front of it ends, and the
    // set is emitted for both — that ending, and the host's own report of
    // the ring it promotes — so every emission asks after each held ring
    // once more.
    for (final osId in _heldRings.toList()) {
      unawaited(_armSilenceTimer(osId));
    }
  }

  void _emitRing(AlertPayload payload) {
    final tracked = _rings[payload.osId];
    if (!_trackRing(payload)) {
      // The same ring told twice is this guard at work, and by design it
      // happens all the time: at a cold start the launch lookup finds the
      // ring and the plugin's replay then tells it again, and every alarm
      // that joins the ringing set repeats the ones already in it. Only a
      // ring due at **another instant** is worth a line — the id is still
      // tracked from a ring whose end never reached this binding, and the
      // one sounding now gets no page. An entry armed before payloads named
      // their instant cannot be told apart that way, a repeat and a new ring
      // both reading null on both sides, so for it this line never prints.
      if (tracked?.fireAtMs != payload.fireAtMs) {
        debugPrint(
          '[AndroidAlertGateway] ring ${payload.osId} already tracked for '
          'another instant (${tracked?.fireAtMs} -> ${payload.fireAtMs}): '
          'not announced',
        );
      }
      return;
    }
    if (!_ringing.isClosed) _ringing.add(payload);
  }

  /// Starts tracking one ring. False when it is already tracked.
  bool _trackRing(AlertPayload payload) {
    if (_rings.containsKey(payload.osId)) return false;
    _rings[payload.osId] = payload;
    unawaited(_armSilenceTimer(payload.osId));
    unawaited(_showOverKeyguard(true));
    return true;
  }

  /// Settles a ring that ended outside the app and reports it.
  void _endRing(int osId, AlertRingEndCause cause) {
    _silenceTimers.remove(osId)?.cancel();
    _heldRings.remove(osId);
    _pluginRings.remove(osId);
    // A ring that ends in a snooze is the one that makes the record, and the
    // plugin's move and its shrunken ringing set arrive on two streams in no
    // promised order — so that ending must not take the record with it.
    if (cause != AlertRingEndCause.snoozed) _snoozeMoved.remove(osId);
    final payload = _rings.remove(osId);
    if (_rings.isEmpty) unawaited(_showOverKeyguard(false));
    if (payload == null || _ringEnded.isClosed) return;
    _ringEnded.add((payload: payload, cause: cause));
  }

  /// Lifts the activity over the keyguard while a **fallback** ring is up.
  ///
  /// The `alarm` package does this for its own rings, natively, and drops the
  /// flags when the ring ends. The notification fallback has nobody to do it:
  /// its full-screen intent launches the activity, and without the flag the
  /// alarm page sits behind the PIN. It is a runtime flag precisely so it can
  /// be dropped again — as a manifest attribute it would hold forever and put
  /// the whole app on the lock screen.
  Future<void> _showOverKeyguard(bool show) async {
    if (!kAlarmTierUsesNotifications) return;
    try {
      await _platform.invokeMethod<void>('setShowWhenLocked', show);
    } catch (e) {
      debugPrint('[AndroidAlertGateway] setShowWhenLocked($show) failed: $e');
    }
  }

  /// Starts [osId]'s Silence-after window — unless the host is holding the
  /// ring behind another one, when it is marked held and nothing starts
  /// ([alertSilenceWindowRuns]).
  Future<void> _armSilenceTimer(int osId) async {
    _silenceTimers.remove(osId)?.cancel();
    int minutes = SettingsKeys.defaultAlertSilenceAfterMinutes;
    try {
      minutes = (await (await SettingsService.getInstance())
              .getAlertSettings())
          .silenceAfterMinutes;
    } catch (_) {
      // The shipped default is a better answer than ringing forever.
    }
    final emissionsBefore = _ringingEmissions;
    final runs = await _silenceWindowRuns(osId);
    // Stopped while the setting was read or the host asked: arming now would
    // leave a timer that fires `Alarm.stop` on whatever holds this id by
    // then — and a snooze of a snooze is re-armed under the same one.
    if (!_rings.containsKey(osId)) {
      _heldRings.remove(osId);
      return;
    }
    if (!runs) {
      _heldRings.add(osId);
      // An emission handled while the host was being asked found no mark, so
      // it asked nothing — and what it told of can be what the answer
      // missed: the ring in front ending between the two reads, with nothing
      // promoted. Asked again, now that the mark is there for every emission
      // after.
      if (_ringingEmissions != emissionsBefore) {
        unawaited(_armSilenceTimer(osId));
      }
      return;
    }
    _heldRings.remove(osId);
    // Two askings can be out for one held ring — the set is emitted for the
    // ending in front of it and again for the host's report of it. Cancelled
    // here, two that both find it sounding leave one timer between them.
    // Two that finish out of order can still leave a held mark beside a
    // running timer, which costs nothing: the next emission asks again and
    // starts the window afresh, and a window that runs out asks the host
    // before it stops anything.
    _silenceTimers.remove(osId)?.cancel();
    _silenceTimers[osId] = Timer(Duration(minutes: minutes), () {
      unawaited(_silence(osId));
    });
  }

  /// Ends an unanswered ring. Reported as `timedOut` rather than folded into
  /// [stopRinging], because nobody acknowledged anything.
  ///
  /// The host is asked first. A window can have started for a ring it was
  /// holding — begun while the host could not say — and stopping that ring
  /// would end it before anyone heard it: its window is started again
  /// instead, and waits for the host to sound it.
  Future<void> _silence(int osId) async {
    final payload = _rings[osId];
    final runs = await _silenceWindowRuns(osId);
    // Over, or ringing again under the same id, by the time the host
    // answered: this timer was for neither.
    if (!identical(_rings[osId], payload)) return;
    if (!runs) {
      unawaited(_armSilenceTimer(osId));
      return;
    }
    await stopRinging(osId);
    if (payload == null || _ringEnded.isClosed) return;
    _ringEnded.add((payload: payload, cause: AlertRingEndCause.timedOut));
  }

  /// [alertSilenceWindowRuns] for [osId], as the `alarm` host answers it.
  ///
  /// Only a ring the plugin reported is the host's to answer for: the
  /// notification fallback's ring is not, and the host would call it silent.
  /// Asked of the plugin's platform half, not of `Alarm.isRinging`, which
  /// checks the answer against the plugin's own ringing set and logs a severe
  /// line when the two differ — for a held ring, every time, the fallback
  /// timer having put it in that set. Nor of that set itself, for the same
  /// reason: it holds the held ring as if it rang.
  Future<bool> _silenceWindowRuns(int osId) async {
    if (!_pluginRings.contains(osId)) return true;
    try {
      final host = AndroidAlarm();
      // Anything first, this ring second. A promotion that lands between the
      // two reads — the ring in front stopped, this one sounding — then reads
      // as sounding, and one that lands after both is told by emissions that
      // come once the held mark is in place. The other way round, such a
      // promotion read as held and its emissions were handled before the
      // mark existed: nothing asked again, and the ring sounded with no
      // window until somebody stopped it.
      final anySounding = await host.isRinging();
      final sounding = anySounding && await host.isRinging(osId);
      return alertSilenceWindowRuns(
        sounding: sounding,
        anySounding: anySounding,
      );
    } catch (e) {
      debugPrint('[AndroidAlertGateway] isRinging($osId) failed: $e');
      return true;
    }
  }

  /// `AlarmDropped(cause: staleAtBoot)` on `Alarm.events` is deliberately not
  /// subscribed to: it carries an id and nothing else, and the plugin has
  /// already unsaved the alarm when it delivers the event, so there is no
  /// payload to post a "Missed" from. `androidStaleAfter` equals
  /// `kLateFireGrace`, which puts the registry row past the grace window at
  /// the same launch, and `AlertScheduler` reports it from there (**A10**).

  void _handleResponse(NotificationResponse response) {
    final payload = AlertPayload.decode(response.payload);
    if (payload == null) return;
    // An upcoming notice carries its alarm's payload; the id says which of the
    // two was tapped, and the action says what for. Skip is the one intent
    // that changes the plan, so it goes to the calendar page rather than to a
    // detail sheet; Open and a tap on the body open the event.
    if (isNoticeNotification(response.id, payload)) {
      PendingNavigationQueue.instance.enqueue(
        response.actionId == kAlertSkipActionId
            ? SkipNextFireIntent(payload: payload)
            : OpenEventIntent(payload: payload),
      );
      return;
    }
    // A "Missed" notice carries the payload of the alarm it reports on, so
    // without this a tap on it would open the ring page for a session that
    // ended hours ago and mark a cancelled row `fired`. It opens the event.
    if (isMissedNotification(response.id, payload)) {
      PendingNavigationQueue.instance.enqueue(OpenEventIntent(payload: payload));
      return;
    }
    // A handled full-screen-intent notification keeps the right to relaunch
    // the activity the next time the screen turns off (§10.5), so it is
    // cancelled the moment it has been dealt with.
    if (payload.isAlarm) {
      unawaited(_plugin.cancel(id: payload.osId));
      _emitRing(payload);
      return;
    }
    // Both actions are declared `showsUserInterface: false`, which routes them
    // to [alertBackgroundActionHandler] whether or not the app is in front —
    // so neither case is expected here. They are kept as the same two lines
    // the background handler runs, in case a plugin release ever delivers one.
    switch (response.actionId) {
      case kAlertDoneActionId:
        unawaited(_plugin.cancel(id: payload.osId));
      case kAlertSnoozeActionId:
        unawaited(_snoozeFromBackground(_plugin, payload));
      default:
        PendingNavigationQueue.instance.enqueue(
          OpenEventIntent(payload: payload),
        );
    }
  }

  // ── Decor ────────────────────────────────────────────────────────────

  /// The colour the event's avatar wears: the one resolved when the entry
  /// was armed, where its payload carries it, and the same icon rule over
  /// the category facade for an entry from before payloads did.
  static Color _tintOf(AlertPayload payload) => Color(
    payload.tintValue ??
        payload.iconColorValue(
          CalendarCategories.resolve(payload.categoryId).colorValue,
        ),
  );

  /// The glyph of that avatar, found the same way.
  static IconData _iconOf(AlertPayload payload) =>
      CalendarIcons.forKey(payload.glyphKey) ??
      CalendarIcons.forKey(payload.iconKey) ??
      CalendarIcons.forKey(
        CalendarCategories.resolve(payload.categoryId).iconKey,
      ) ??
      Icons.alarm_rounded;

  /// What a notification for [payload] wears: its colour, and its avatar
  /// once that is on disk.
  Future<AlertDecor> _decorFor(AlertPayload payload) async =>
      (color: _tintOf(payload), iconFile: await _iconFileFor(payload));

  /// How long a drawing, a write or a directory lookup is waited for. They
  /// run inside the scheduler's serialized chain, where one that never came
  /// back would park every later turn behind it.
  static const Duration _rasterPatience = Duration(seconds: 2);

  /// The path of [payload]'s avatar on disk, drawn first when it is not
  /// there yet — or null when it could not be had in time, which posts a
  /// notification without a large icon and never holds one back.
  ///
  /// **A file, kept for good.** A reminder is scheduled with the path days
  /// ahead and its Snooze hands the same path on from a background isolate,
  /// so nothing here ever clears the directory: a file is a few kilobytes,
  /// there is one per glyph, colour and size (and per way of drawing them,
  /// should the avatar ever change — [alertLargeIconFileName]), and deleting
  /// one a standing notification still names would take its avatar away.
  Future<String?> _iconFileFor(AlertPayload payload) async {
    try {
      final icon = _iconOf(payload);
      final color = _tintOf(payload);
      final pixels = alertLargeIconPixels(_devicePixelRatio());
      final name = alertLargeIconFileName(icon, color, pixels);
      return await (_iconFiles[name] ??= _findOrDrawIcon(
        name,
        icon,
        color,
        pixels,
      ));
    } catch (e) {
      debugPrint('[AndroidAlertGateway] avatar lookup failed: $e');
      return null;
    }
  }

  /// Answers within a few [_rasterPatience]s whatever happens, and never
  /// throws: every wait in it is bounded, and it is shared by whoever asks
  /// for the same file while it runs.
  Future<String?> _findOrDrawIcon(
    String name,
    IconData icon,
    Color color,
    int pixels,
  ) async {
    try {
      final directory = await _resolveIconDirectory();
      final file = File(p.join(directory.path, name));
      if (!await file.exists().timeout(_rasterPatience)) {
        final recorder = ui.PictureRecorder();
        paintAlertLargeIcon(Canvas(recorder), icon, color, pixels);
        final bytes = await _rasterize(
          recorder.endRecording(),
          pixels,
        ).timeout(_rasterPatience);
        await _writeWhole(file, bytes);
      }
      return file.path;
    } catch (e) {
      debugPrint('[AndroidAlertGateway] avatar $name not ready: $e');
      // Forgotten rather than remembered as missing: the next post asks
      // again, and a drawing that only ran out of patience may be there.
      unawaited(_iconFiles.remove(name));
      return null;
    }
  }

  Future<Directory> _resolveIconDirectory() async {
    final known = _iconDirectory;
    if (known != null) return known;
    final support = await getApplicationSupportDirectory().timeout(
      _rasterPatience,
    );
    final directory = Directory(p.join(support.path, kAlertIconDirectory));
    await directory.create(recursive: true).timeout(_rasterPatience);
    return _iconDirectory = directory;
  }

  /// The screen's density, or null while the engine has no view to ask.
  static double? _devicePixelRatio() {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final view = dispatcher.implicitView ?? dispatcher.views.firstOrNull;
    return view?.devicePixelRatio;
  }

  /// Not bounded in itself — the caller is — so that a drawing which comes
  /// back after its caller stopped waiting still disposes what it made.
  static Future<Uint8List> _rasterize(ui.Picture picture, int pixels) async {
    try {
      final image = await picture.toImage(pixels, pixels);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw StateError('the engine encoded no image');
        return data.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  }

  /// Puts [bytes] under [file]'s name in one step: written beside it first,
  /// then renamed. A file caught half-written would be found under its name
  /// by every later lookup, handed to the platform as it is and never drawn
  /// again.
  static Future<void> _writeWhole(File file, Uint8List bytes) async {
    final draft = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await draft.writeAsBytes(bytes, flush: true).timeout(_rasterPatience);
      await draft.rename(file.path).timeout(_rasterPatience);
    } catch (_) {
      unawaited(draft.delete().then<void>((_) {}, onError: (_) {}));
      rethrow;
    }
  }

  // ── Sounds ───────────────────────────────────────────────────────────

  @override
  Future<PickedAlertSound?> pickSystemSound(String? current) async {
    try {
      final picked = await _platform.invokeMapMethod<String, Object?>(
        'pickAlarmSound',
        current,
      );
      // Null is a cancelled picker, which is a decision the user made and not
      // a failure — the sheet simply stays where it was.
      if (picked == null) return null;
      final value = picked['value'];
      if (value is! String || value.isEmpty) return null;
      final title = picked['title'];
      return (value: value, title: title is String ? title : null);
    } on PlatformException catch (e) {
      if (e.code == kAlertSoundNoPickerCode) {
        throw const AlertSoundPickerUnavailable();
      }
      debugPrint('[AndroidAlertGateway] pickAlarmSound refused: ${e.code}');
      return null;
    } catch (e) {
      debugPrint('[AndroidAlertGateway] pickAlarmSound failed: $e');
      return null;
    }
  }

  @override
  Future<String?> soundTitle(String value) async {
    try {
      return await _platform.invokeMethod<String>('alarmSoundTitle', value);
    } catch (e) {
      debugPrint('[AndroidAlertGateway] alarmSoundTitle failed: $e');
      return null;
    }
  }

  /// The phone's alarm-stream level as a 0..1 fraction, or null when it could
  /// not be read.
  Future<double?> _alarmStreamVolume() async {
    try {
      return await _platform.invokeMethod<double>('alarmStreamVolume');
    } catch (e) {
      debugPrint('[AndroidAlertGateway] alarmStreamVolume failed: $e');
      return null;
    }
  }

  @override
  Future<String> refreshArmContext() async {
    _ringVolume = alertRingVolumeFor(await _alarmStreamVolume());
    _languageCode = await _rereadLanguageCode();
    final labels = _labels = _labelsFor(_languageCode);
    return alertArmContext(
      backend: backendName,
      volume: _ringVolume,
      // What the pass will really write in, not what the setting says: a
      // setting that follows the device resolves to a language, and it is
      // the language that is frozen into an entry.
      language: labels.languageCode,
      use24Hour: labels.use24Hour,
    );
  }

  // ── Scheduling ───────────────────────────────────────────────────────

  @override
  Future<bool> schedule(
    PlannedFire fire,
    AlertPayload payload, {
    DateTime? noticeAt,
  }) async {
    await initialize();
    _snoozeMoved.remove(payload.osId);
    final armed = payload.isAlarm && !kAlarmTierUsesNotifications
        ? await _scheduleAlarm(fire, payload)
        : await _scheduleNotification(fire, payload);
    if (!armed) return false;
    await _armNotice(payload, noticeAt, fire.fireAt);
    // Drawn now, behind the entry and waited for by nobody: an alarm's own
    // notification has no avatar, but what may follow it has — the session
    // chip after Stop, a Missed — and those are posted at moments that are
    // worse for drawing one than this pass is.
    unawaited(_iconFileFor(payload));
    return true;
  }

  /// Arms the upcoming notice beside its alarm, or takes a standing one down
  /// when the pass no longer wants one — the lead turned off, the instant
  /// already behind now. A failure costs the notice alone: the alarm is
  /// armed by then, and a notice is not a registration, so nothing records it
  /// and nothing retries it before the next pass.
  Future<void> _armNotice(
    AlertPayload payload,
    DateTime? noticeAt,
    DateTime fireAt,
  ) async {
    final id = noticeNotificationId(payload.osId);
    try {
      if (noticeAt == null) {
        await _plugin.cancel(id: id);
        return;
      }
      final l10n = _l10n;
      final content = alertNotificationContent(
        AlertNotificationKind.notice,
        payload,
        l10n,
        // The notice can be posted up to a day ahead: a bare "07:00" on one
        // posted the evening before would read as a time already gone.
        dayLabel: labels.dayLabel(fireAt: fireAt, noticeAt: noticeAt),
      );
      final decor = await _decorFor(payload);
      await _plugin.zonedSchedule(
        id: id,
        title: content.title,
        body: content.text,
        scheduledDate: tz.TZDateTime.from(noticeAt, tz.local),
        payload: payload.copyWith(notice: true).encode(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        notificationDetails: NotificationDetails(
          android: alertNoticeDetails(
            l10n,
            content,
            decor: decor,
            timeoutAfterMillis: noticeTimeoutMillis(
              noticeAt: noticeAt,
              fireAt: fireAt,
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint('[AndroidAlertGateway] notice for ${payload.osId} failed: $e');
    }
  }

  Future<bool> _scheduleAlarm(PlannedFire fire, AlertPayload payload) async {
    final assetAudioPath = alarmAssetPathFor(fire.sound);
    try {
      final content = alertNotificationContent(
        AlertNotificationKind.ring,
        payload,
        _l10n,
      );
      return await Alarm.set(
        alarmSettings: AlarmSettings(
          id: payload.osId,
          dateTime: fire.fireAt,
          assetAudioPath: assetAudioPath,
          loopAudio: true,
          vibrate: true,
          androidFullScreenIntent: true,
          // Defaults false, and false means `Alarm.set` **stops every other
          // alarm due in the same second** before arming this one. Alerts are
          // minute-granular wall-clock instants, so two events at 07:00 — or
          // two all-day events on the 09:00 default, or an alarm belonging to
          // another database — collide exactly, and each reconcile would
          // silently disarm whichever of them it did not schedule last.
          allowSameSecondScheduling: true,
          // Defaults true and posts a second, permanent notification warning
          // that killing the app stops alarms — noise the app says once, in
          // its own settings copy, instead.
          warningNotificationOnKill: false,
          // Swiping the app away must not disarm a ring already in progress.
          androidStopAlarmOnTermination: false,
          // A10: a phone that was off should not ring a 07:00 alarm at 09:30.
          // The same number the registry's in-flight band uses, so the app's
          // idea of "still worth ringing" and the plugin's cannot drift.
          androidStaleAfter: kLateFireGrace,
          payload: payload.encode(),
          // **Null volume follows the phone.** `AlarmService` only calls its
          // `VolumeService.setVolume` when a volume is named, so a null one
          // never touches `AudioManager` and the ring plays at whatever the
          // alarm stream is set to — the user's own slider, which an alarm app
          // has no business overriding. The floor is the one exception
          // ([AlertRingVolume]), for a slider left near zero. The fade is
          // applied to the plugin's own `MediaPlayer`, not to the stream, so it
          // survives either answer.
          volumeSettings: VolumeSettings.fade(
            fadeDuration: kAlertRingFade,
            volume: _ringVolume == AlertRingVolume.floor
                ? kAlertRingFloorVolume
                : null,
            // Defaults true, and true has the plugin raise the phone's own
            // volume panel whenever it sets the stream: at the start of a
            // ring in the floor bucket and again at its end, over the alarm
            // page both times.
            showSystemUI: false,
          ),
          // The snooze length the pass already read (`payload.snoozeMinutes`
          // is the scheduler's once-per-pass settings value), so the plugin
          // can defer the ring from its own notification with no Dart up.
          androidSnoozeDuration: Duration(minutes: payload.snoozeMinutes),
          notificationSettings: alertRingSettings(content, _tintOf(payload)),
        ),
      );
    } on AlarmException catch (e) {
      // Typed `Future<bool>` and still throws since 5.9.0 (§10.5). A refusal
      // records nothing, so the next reconcile simply tries again.
      debugPrint('[AndroidAlertGateway] Alarm.set refused: ${e.code} ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[AndroidAlertGateway] Alarm.set failed: $e');
      return false;
    }
  }

  /// Whether a reminder armed now goes into [kAlertGroupKey]: what
  /// [alertRemindersGroupedOn] makes of the phone's Android release.
  ///
  /// Asked of the activity once per process — a phone does not change its
  /// release under one — and kept only when it was an answer. A read that
  /// failed arms this one reminder loose, the shape every phone had before
  /// the group existed, and the next arming asks again: remembered, one bad
  /// round trip at launch would leave every reminder of the process loose.
  Future<bool> _groupsReminders() async {
    final known = _remindersGrouped;
    if (known != null) return known;
    try {
      final sdkInt = await _platform.invokeMethod<int>(kAlertSdkLevelMethod);
      if (sdkInt == null) return false;
      return _remindersGrouped = alertRemindersGroupedOn(sdkInt);
    } catch (e) {
      debugPrint('[AndroidAlertGateway] $kAlertSdkLevelMethod failed: $e');
      return false;
    }
  }

  Future<bool> _scheduleNotification(
    PlannedFire fire,
    AlertPayload payload,
  ) async {
    final l10n = _l10n;
    final alarmTier = payload.isAlarm;
    try {
      final silenceAfter = alarmTier
          ? await _silenceAfterMillis()
          : null;
      final decor = await _decorFor(payload);
      final content = alertNotificationContent(
        alarmTier
            ? AlertNotificationKind.fallbackAlarm
            : AlertNotificationKind.reminder,
        payload,
        l10n,
      );
      // The fallback alarm stays out of the group: whether its insistent
      // sound outlasts the platform gathering the group's members, three
      // seconds after the post, was never seen.
      final grouped = !alarmTier && await _groupsReminders();
      // A reminder carries the path of its own avatar and the shape it was
      // armed in: its Snooze posts it again from the payload alone, in an
      // isolate that can neither draw nor ask which Android this is.
      final carried = alarmTier
          ? payload
          : payload.copyWith(iconFile: decor.iconFile, grouped: grouped);
      await _plugin.zonedSchedule(
        id: payload.osId,
        title: content.title,
        body: content.text,
        scheduledDate: tz.TZDateTime.from(fire.fireAt, tz.local),
        payload: carried.encode(),
        // The fallback alarm uses `setAlarmClock`, which becomes the system's
        // next wake-from-idle and is not Doze rate-limited; a reminder takes
        // the quieter exact tier.
        androidScheduleMode: alarmTier
            ? AndroidScheduleMode.alarmClock
            : AndroidScheduleMode.exactAllowWhileIdle,
        notificationDetails: NotificationDetails(
          android: alarmTier
              ? alertFallbackAlarmDetails(
                  l10n,
                  content,
                  decor: decor,
                  timeoutAfterMillis: silenceAfter!,
                )
              : alertReminderDetails(
                  l10n,
                  content,
                  decor: decor,
                  grouped: grouped,
                ),
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[AndroidAlertGateway] zonedSchedule failed: $e');
      return false;
    }
  }

  Future<int> _silenceAfterMillis() async {
    var minutes = SettingsKeys.defaultAlertSilenceAfterMinutes;
    try {
      minutes = (await (await SettingsService.getInstance())
              .getAlertSettings())
          .silenceAfterMinutes;
    } catch (_) {
      // The shipped default rather than a ring with no end.
    }
    return Duration(minutes: minutes).inMilliseconds;
  }

  @override
  Future<void> cancel(int osId) async {
    await initialize();
    // Off its silence timer and out of both ring maps **before**
    // `Alarm.stop`, as [stopRinging] takes it. Cancelling an id that is
    // ringing is the plan saying the entry should not exist, not somebody
    // answering it: left tracked, the ring's disappearance would be read by
    // [_handleRinging] as a Stop on the notification and settled as one —
    // the session chip, and the removal of an event set to go after its
    // alarm. And a stop that threw would leave the id in [ringingIds] for
    // the life of the process, with every destination but an alarm page
    // held back behind it.
    //
    // No caller cancels a ringing id outside a race: the scheduler cancels
    // rows still ahead of now, ids it has just stopped or seen end, and
    // platform entries with [ringingIds] left out. A race is enough, though
    // — a row whose instant passes while its pass is running, a snooze
    // cancelled in the hub as it starts to ring — and that ring is over all
    // the same: it is reported below, under a cause of its own.
    _silenceTimers.remove(osId)?.cancel();
    _heldRings.remove(osId);
    _pluginRings.remove(osId);
    final ring = _rings.remove(osId);
    if (ring != null && _rings.isEmpty) {
      unawaited(_showOverKeyguard(false));
    }
    // Asked of **both** backends. A registration records which one armed it,
    // but the tier's backend can be switched under a standing entry, and
    // cancelling an id a platform does not hold is a no-op by contract.
    _stopping.add(osId);
    try {
      await Alarm.stop(osId);
    } catch (e) {
      debugPrint('[AndroidAlertGateway] Alarm.stop($osId) failed: $e');
    } finally {
      _stopping.remove(osId);
    }
    try {
      await _plugin.cancel(id: osId);
    } catch (e) {
      debugPrint('[AndroidAlertGateway] cancel($osId) failed: $e');
    }
    await _cancelNotice(osId);
    _snoozeMoved.remove(osId);
    // Only for a ring this call took out, and last: by now both backends
    // have been asked, so the ring is over when it is said to be — as for
    // every other ending [ringEnded] carries. Cancelled, not dismissed: the
    // alarm page closes and what the ring held back is routed, and nothing
    // is settled, because whoever cancelled writes down its own reason.
    if (ring != null && !_ringEnded.isClosed) {
      _ringEnded.add((payload: ring, cause: AlertRingEndCause.cancelled));
    }
  }

  /// Every path that takes an alarm off the platform takes its notice too.
  Future<void> _cancelNotice(int osId) async {
    try {
      await _plugin.cancel(id: noticeNotificationId(osId));
    } catch (e) {
      debugPrint('[AndroidAlertGateway] notice cancel($osId) failed: $e');
    }
  }

  @override
  Future<List<PendingAlertEntry>> pendingEntries() async {
    await initialize();
    final entries = <int, AlertPayload>{};
    try {
      for (final alarm in await Alarm.getAlarms()) {
        final payload = AlertPayload.decode(alarm.payload);
        if (payload == null) continue;
        entries[alarm.id] = payload.copyWith(osId: alarm.id);
      }
    } catch (e) {
      debugPrint('[AndroidAlertGateway] Alarm.getAlarms failed: $e');
    }
    try {
      for (final request in await _plugin.pendingNotificationRequests()) {
        final payload = AlertPayload.decode(request.payload);
        if (payload == null) continue;
        // A notice is the alarm's shadow, not an entry the plan made: listed
        // here it would be cancelled as a stray by the OS-truth pass.
        if (payload.notice) continue;
        entries[request.id] = payload.copyWith(osId: request.id);
      }
    } catch (e) {
      debugPrint('[AndroidAlertGateway] pendingNotificationRequests failed: $e');
    }
    return [
      for (final entry in entries.entries)
        (osId: entry.key, payload: entry.value),
    ];
  }

  @override
  Future<void> showMissed(AlertPayload payload) async {
    await initialize();
    final l10n = _l10n;
    try {
      final decor = await _decorFor(payload);
      final content = alertNotificationContent(
        AlertNotificationKind.missed,
        payload,
        l10n,
      );
      await _plugin.show(
        // Its own id space, so a Missed notice never replaces or is replaced
        // by a live registration that happens to share an os id.
        id: missedNotificationId(payload.osId),
        title: content.title,
        body: content.text,
        payload: payload.encode(),
        notificationDetails: NotificationDetails(
          android: alertMissedDetails(
            l10n,
            content,
            decor: decor,
            dueAtMs: payload.fireAtMs,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[AndroidAlertGateway] showMissed failed: $e');
    }
  }

  // ── Ringing ──────────────────────────────────────────────────────────

  @override
  Future<void> stopRinging(int osId) async {
    await initialize();
    _silenceTimers.remove(osId)?.cancel();
    _heldRings.remove(osId);
    // Out of both maps **before** `Alarm.stop`, which is what tells
    // [_handleRinging] this ending was the app's own and not a dismissal.
    _pluginRings.remove(osId);
    _rings.remove(osId);
    _snoozeMoved.remove(osId);
    if (_rings.isEmpty) unawaited(_showOverKeyguard(false));
    _stopping.add(osId);
    try {
      await Alarm.stop(osId);
    } catch (e) {
      debugPrint('[AndroidAlertGateway] stopRinging($osId) failed: $e');
    } finally {
      _stopping.remove(osId);
    }
    try {
      await _plugin.cancel(id: osId);
    } catch (e) {
      debugPrint('[AndroidAlertGateway] stopRinging cancel($osId) failed: $e');
    }
    await _cancelNotice(osId);
  }

  @override
  Stream<AlertPayload> get ringing => _ringing.stream;

  @override
  Stream<AlertRingEnd> get ringEnded => _ringEnded.stream;

  @override
  Future<DateTime?> processStartedAt() async {
    try {
      final ms = await _platform.invokeMethod<int>('processStartedAt');
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (e) {
      debugPrint('[AndroidAlertGateway] processStartedAt failed: $e');
      return null;
    }
  }

  @override
  Future<AlertIntent?> launchIntent() async {
    await initialize();
    if (_launchIntentRead) return _launchIntent;
    _launchIntentRead = true;
    try {
      _launchIntent = await _notificationLaunchIntent();
    } catch (e) {
      debugPrint('[AndroidAlertGateway] launchIntent failed: $e');
    }
    // Asked second, so a notification that launched the app always wins over
    // the session chip's Open note and the phone's "next alarm" line — and
    // asked at all only once, because the activity answers each a single
    // time.
    _launchIntent ??= await _consumeSessionOpenRequest();
    if (_launchIntent == null && await _consumeShowAlarmsRequest()) {
      _launchIntent = const OpenAlertsHubIntent();
    }
    if (_launchIntent == null && await _consumeQuickAlarmRequest()) {
      _launchIntent = const QuickAlarmIntent();
    }
    return _launchIntent;
  }

  /// The payload the session chip's *Open note* started the activity with,
  /// once, or null.
  Future<OpenSessionIntent?> _consumeSessionOpenRequest() async {
    try {
      return OpenSessionIntent.fromPlatform(
        await _platform.invokeMethod<String>('consumeSessionOpenRequest'),
      );
    } catch (e) {
      debugPrint('[AndroidAlertGateway] consumeSessionOpenRequest failed: $e');
      return null;
    }
  }

  /// The intent a notification launched the app with, or null when none did.
  Future<AlertIntent?> _notificationLaunchIntent() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    final response = details?.notificationResponse;
    final payload = AlertPayload.decode(response?.payload);
    if (payload == null) return null;
    if (isNoticeNotification(response?.id, payload)) {
      return response?.actionId == kAlertSkipActionId
          ? SkipNextFireIntent(payload: payload)
          : OpenEventIntent(payload: payload);
    }
    if (isMissedNotification(response?.id, payload)) {
      return OpenEventIntent(payload: payload);
    }
    if (payload.isAlarm) {
      await _plugin.cancel(id: payload.osId);
      // Tracked like a warm ring, so the silence timer and the keyguard flag
      // cover a fallback alarm that launched the app — but not emitted: the
      // caller queues the intent it is handed.
      _trackRing(payload);
      return OpenAlarmIntent(payload: payload);
    }
    return OpenEventIntent(payload: payload);
  }

  /// Whether the activity was started by an alarm-clock show intent it has
  /// not yet reported — true once, then false, on the activity's side.
  Future<bool> _consumeShowAlarmsRequest() async {
    try {
      return await _platform.invokeMethod<bool>('consumeShowAlarmsRequest') ??
          false;
    } catch (e) {
      debugPrint('[AndroidAlertGateway] consumeShowAlarmsRequest failed: $e');
      return false;
    }
  }

  /// Whether the activity was started by the Quick Settings tile or the
  /// launcher shortcut (`QUICK_ALARM`, OS-5) and has not reported it yet —
  /// the show intent's answer, for the other cold start.
  Future<bool> _consumeQuickAlarmRequest() async {
    try {
      return await _platform.invokeMethod<bool>('consumeQuickAlarmRequest') ??
          false;
    } catch (e) {
      debugPrint('[AndroidAlertGateway] consumeQuickAlarmRequest failed: $e');
      return false;
    }
  }

  @override
  Stream<void> get showAlarms => _showAlarms.stream;

  // ── Session chip (OS-5) ──────────────────────────────────────────────

  /// Drawn natively by `SessionChip.kt`: promoted with a progress bar where
  /// Android 16 allows it, a plain ongoing chronometer notification
  /// everywhere else, on the quiet channel and silent either way. Every
  /// string crosses here, localized, and the avatar as a file; the platform
  /// only draws them ([sessionChipArguments]).
  @override
  Future<bool> showSessionChip(
    AlertPayload payload, {
    required DateTime startedAt,
    DateTime? endsAt,
    int? progress,
    bool refresh = false,
    bool linkedNote = false,
  }) async {
    await initialize();
    try {
      final content = alertNotificationContent(
        AlertNotificationKind.sessionChip,
        payload,
        _l10n,
        untilLabel: endsAt == null ? null : labels.untilLabel(endsAt),
        linkedNote: linkedNote,
      );
      final decor = await _decorFor(payload);
      final standing = await _platform.invokeMethod<bool>(
        'showSessionChip',
        sessionChipArguments(
          payload: payload,
          content: content,
          decor: decor,
          startedAt: startedAt,
          endsAt: endsAt,
          progress: progress,
          refresh: refresh,
        ),
      );
      return standing ?? false;
    } catch (e) {
      debugPrint('[AndroidAlertGateway] session chip failed: $e');
      return false;
    }
  }

  @override
  Future<void> clearSessionChip() async {
    try {
      await _platform.invokeMethod<void>('clearSessionChip');
    } catch (e) {
      debugPrint('[AndroidAlertGateway] session chip clear failed: $e');
    }
  }

  @override
  Set<int> get ringingIds => Set<int>.unmodifiable(_rings.keys);

  @override
  List<AlertPayload> get ringingPayloads =>
      List<AlertPayload>.unmodifiable(_rings.values);

  @override
  Future<bool> isLockScreenUp() async {
    try {
      return await _platform.invokeMethod<bool>('keyguardLocked') ?? false;
    } catch (e) {
      debugPrint('[AndroidAlertGateway] keyguardLocked failed: $e');
      rethrow;
    }
  }

  @override
  Future<bool> dismissLockScreen() async {
    try {
      return await _platform.invokeMethod<bool>('dismissKeyguard') ?? false;
    } catch (e) {
      debugPrint('[AndroidAlertGateway] dismissKeyguard failed: $e');
      return false;
    }
  }

  @override
  Future<void> dispose() async {
    _platform.setMethodCallHandler(null);
    await _ringingSub?.cancel();
    await _eventsSub?.cancel();
    await _pluginLogSub?.cancel();
    for (final timer in _silenceTimers.values) {
      timer.cancel();
    }
    _silenceTimers.clear();
    _heldRings.clear();
    await _ringing.close();
    await _ringEnded.close();
    await _showAlarms.close();
  }
}

/// The id a "Missed" notice is posted under, derived from the registration it
/// reports on.
///
/// Derived rather than random so the same miss reported twice replaces itself
/// instead of stacking, and offset out of the registration id space so it can
/// never cancel a live entry.
int missedNotificationId(int osId) =>
    (osId ^ kAlertMissedIdSalt) & kAlertOsIdMask;

/// Whether a notification response came from the "Missed" notice posted for
/// [payload]'s registration rather than from the registration itself.
///
/// The notice re-uses the alarm's payload — that is what lets a tap open the
/// right day — so the payload alone cannot tell the two apart; the
/// notification id can, because a notice is always posted under
/// [missedNotificationId]. A response with no id (a pre-10 plugin entry)
/// reads as the registration, which is the only kind that could exist.
bool isMissedNotification(int? notificationId, AlertPayload payload) =>
    notificationId != null && notificationId == missedNotificationId(payload.osId);

/// The id an upcoming-alarm notice is posted under (OS-3), derived from the
/// alarm it announces: cancelled with it, never landing on it or on its
/// Missed notice.
int noticeNotificationId(int osId) => (osId ^ kAlertNoticeIdSalt) & kAlertOsIdMask;

/// How long an upcoming notice may stay in the shade once posted: until the
/// alarm it announces is due. Pure, so the rule is pinned rather than
/// trusted — a notice that outlives its alarm is one whose Skip cancels an
/// occurrence that already happened.
int noticeTimeoutMillis({required DateTime noticeAt, required DateTime fireAt}) =>
    fireAt.difference(noticeAt).inMilliseconds;

/// Whether a notification response came from the upcoming notice posted for
/// [payload]'s alarm rather than from the alarm itself. The id decides, like
/// [isMissedNotification]; the payload's own `notice` flag is the fallback a
/// response with no id would need, and both say the same thing.
bool isNoticeNotification(int? notificationId, AlertPayload payload) =>
    notificationId == null
        ? payload.notice
        : notificationId == noticeNotificationId(payload.osId);
