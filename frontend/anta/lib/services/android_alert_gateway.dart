import 'dart:async';

import 'package:alarm/alarm.dart';
import 'package:alarm/utils/alarm_exception.dart';
import 'package:alarm/utils/alarm_set.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../constants/alert_constants.dart';
import '../constants/settings_keys.dart';
import '../database/database.dart';
import '../l10n/app_localizations.dart';
import '../models/alert_payload.dart';
import '../models/alert_sound.dart';
import '../utils/alert_os_id.dart';
import '../utils/alert_planner.dart';
import 'alert_gateway.dart';
import 'pending_navigation.dart';
import 'settings_service.dart';

/// **The A5 switch.** `false` rings the Alarm tier through the `alarm`
/// package; `true` rings it through an insistent, alarm-stream notification
/// from `flutter_local_notifications` instead.
///
/// One constant, in one file, because that is the whole mitigation the Phase 0
/// investigation left standing: the emulator spike proved `alarm` in every
/// state it could reach, but `alarm` schedules with
/// `setExactAndAllowWhileIdle`, which deep Doze rate-limits, while the
/// notification path uses `setAlarmClock`, which it does not. If the owner's
/// phone shows an overnight alarm deferring, this flips and nothing else
/// changes — the registry records [AlertGateway.backendName] per row, so the
/// next reconcile re-schedules every entry under the new backend.
///
/// The Reminder tier is never affected: it cannot be built on `alarm`, which
/// always plays on the alarm stream and would break the silent-mode contract.
const bool kAlarmTierUsesNotifications = false;

/// Notification channel ids. **Fixed forever**: Android freezes a channel's
/// importance, sound and DND behaviour at creation, so a new id is the only
/// way to change any of them — and a changed id orphans the user's own
/// per-channel settings.
const String kAlertReminderChannelId = 'alerts_reminder';
const String kAlertAlarmChannelId = 'alerts_alarm';
const String kAlarmPluginChannelId = 'alarm_plugin_channel';

/// The `res/drawable` name of the monochrome status-bar icon.
const String kAlertSmallIcon = 'ic_alert';

/// The bundled alarm sound. The `alarm` package plays Flutter assets rather
/// than `res/raw`, which is why it is declared under `flutter: assets:`.
const String kDefaultAlarmAsset = 'assets/alerts/default_alarm.wav';

/// The error code `MainActivity` answers `pickAlarmSound` with when the device
/// has no ringtone picker activity at all (`ActivityNotFoundException`).
///
/// A literal on both sides of a platform channel, like the two action ids.
const String kAlertSoundNoPickerCode = 'no_picker';

/// The `assetAudioPath` one already-resolved sound is armed under.
///
/// Pure, and the whole of the sound decision the platform ever sees — which is
/// why it is a function rather than three branches inside a `try`. Three
/// answers, and the third is the one that matters:
///
/// - [AlertSoundSystemDefault] arms with **null**, because that is how the
///   `alarm` package says "play the device's default alarm sound"; storing the
///   default's URI instead would freeze today's choice and stop following the
///   Clock app.
/// - [AlertSoundUri] arms with the local file the URI was copied into. A
///   `content://` URI cannot be handed to the plugin at all — it ends up in
///   `MediaPlayer.setDataSource(String)`, which wants a path — so the copy is
///   not an optimisation, it is the only way this value can ring.
/// - **Everything else, and every failed copy, arms the bundled asset.** That
///   is the cross-device degrade rule: a sound another phone picked is a media
///   id this phone's provider never heard of, and the answer to that is the one
///   sound every install has, never silence.
String? alarmAssetPathFor(AlertSound sound, {String? resolvedPath}) {
  return switch (sound) {
    AlertSoundSystemDefault() => null,
    AlertSoundUri() => resolvedPath ?? kDefaultAlarmAsset,
    _ => kDefaultAlarmAsset,
  };
}

/// Action ids carried on a reminder notification. Matched in the background
/// isolate, so they are plain literals on both sides of a process boundary.
const String kAlertSnoozeActionId = 'alert_snooze';
const String kAlertDoneActionId = 'alert_done';

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
/// is why the payload carries that number at all.
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
    await plugin.cancel(id: payload.osId);
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      // Whatever `timezone` defaulted to is still a location; a snooze in the
      // wrong zone is better than no snooze.
    }
    final at = tz.TZDateTime.now(
      tz.local,
    ).add(Duration(minutes: payload.snoozeMinutes));
    final osId = resolveAlertOsId(
      seed: alertOsIdSeed(
        database: payload.database,
        alertId: payload.alertId,
        dayUtc: payload.dayUtc,
        kind: AlertKind.snooze,
      ),
      isTaken: (_) => false,
    );
    // No `AppLocalizations` from the app's own stored language here: reading
    // it would mean a database. The device locale is the honest fallback.
    final l10n = alertGatewayStrings();
    final snoozed = payload.copyWith(osId: osId, snooze: true);
    await plugin.zonedSchedule(
      id: osId,
      title: payload.title,
      body: l10n.alertsSnoozedBody(payload.snoozeMinutes),
      scheduledDate: at,
      payload: snoozed.encode(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      notificationDetails: NotificationDetails(
        android: _reminderDetails(l10n),
      ),
    );
  } catch (e) {
    debugPrint('[AndroidAlertGateway] background snooze failed: $e');
  }
}

AndroidNotificationDetails _reminderDetails(AppLocalizations l10n) {
  return AndroidNotificationDetails(
    kAlertReminderChannelId,
    l10n.alertsReminderChannel,
    channelDescription: l10n.alertsReminderChannelDesc,
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
    icon: kAlertSmallIcon,
    actions: <AndroidNotificationAction>[
      // `showsUserInterface: false` is what routes both to the background
      // isolate, even while the app is in front (§10.5).
      AndroidNotificationAction(
        kAlertSnoozeActionId,
        l10n.alertsSnoozeAction,
        showsUserInterface: false,
        cancelNotification: true,
      ),
      AndroidNotificationAction(
        kAlertDoneActionId,
        l10n.alertsDoneAction,
        showsUserInterface: false,
        cancelNotification: true,
      ),
    ],
  );
}

/// Localizations for a surface with no `BuildContext`, off the **device**
/// locale — the `_errorLocalizations` shape in `main.dart`.
///
/// The background isolate has nothing else to go on, and the main isolate
/// overrides it with the app's own stored language where it can.
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
/// Nothing here is reachable from a test: `AlertAvailability` gates the GetIt
/// registration to Android, so every suite keeps the `NoOpAlertGateway` and
/// no plugin channel is ever stubbed.
class AndroidAlertGateway extends AlertGateway {
  AndroidAlertGateway();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  final StreamController<AlertPayload> _ringing =
      StreamController<AlertPayload>.broadcast();

  final StreamController<AlertRingEnd> _ringEnded =
      StreamController<AlertRingEnd>.broadcast();

  /// Rings in progress, by os id, with the payload each rang under.
  ///
  /// Doubles as the emit-once guard: `Alarm.ringing` is a `ValueStream` that
  /// replays, and the fallback path can deliver the same full-screen entry
  /// through both the response callback and the launch details — the queue
  /// dedupes too, but a stream that emits twice makes the `fired` marking run
  /// twice as well. The payload is kept because [ringEnded] has to hand it
  /// back: by the time a ring is over the `alarm` package has unsaved it.
  final Map<int, AlertPayload> _rings = <int, AlertPayload>{};

  /// The subset of [_rings] the `alarm` package reported, which is the only
  /// subset whose disappearance from `Alarm.ringing` means anything. A
  /// fallback ring never appears in that set, so its absence says nothing.
  final Set<int> _pluginRings = <int>{};

  StreamSubscription<AlarmSet>? _ringingSub;

  /// Stops a ring that nobody acknowledged, after the Silence-after setting.
  ///
  /// The `alarm` package has no timeout of its own — the fallback path gets
  /// `timeoutAfter` from the platform — so the app holds the timer whenever
  /// Dart is up for the ring. That is not always: with the phone in use and
  /// the app not running, the ring is a native heads-up and nothing here runs,
  /// so that ring has no timeout — but it also has someone looking at it.
  final Map<int, Timer> _silenceTimers = <int, Timer>{};

  AlertIntent? _launchIntent;
  bool _launchIntentRead = false;

  Future<void>? _initialization;

  /// The app's own stored language, cached for the life of the binding.
  ///
  /// Read once: the channel names it composes are **immutable after channel
  /// creation** anyway, and re-reading a settings row per scheduled entry
  /// would put a query on the reconcile's inner loop for a value that changes
  /// once in a phone's life.
  String? _languageCode;

  /// How loud the next ring this binding arms will be, re-read once per pass by
  /// [refreshArmContext].
  ///
  /// A field rather than a read per fire: the alarm stream is one number for
  /// the whole phone, and asking the platform 48 times per reconcile for it
  /// would put a channel round trip on the diff's inner loop. It starts at
  /// [AlertRingVolume.follow] so a `schedule` that somehow arrives before a
  /// pass leaves the user's volume alone — the safe half of the choice.
  AlertRingVolume _ringVolume = AlertRingVolume.follow;

  static const MethodChannel _platform = MethodChannel(
    'com.alexzamfir.anta/alerts',
  );

  @override
  String get backendName =>
      kAlarmTierUsesNotifications ? 'notification' : 'alarm';

  @override
  bool get tracksPending => true;

  @override
  bool get supportsSystemSounds => true;

  AppLocalizations get _l10n => alertGatewayStrings(_languageCode);

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
    _languageCode = await _readLanguageCode();
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
        kAlertAlarmChannelId,
        l10n.alertsAlarmChannel,
        description: l10n.alertsAlarmChannelDesc,
        importance: Importance.max,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );

    await Alarm.init();

    await _ringingSub?.cancel();
    _ringingSub = Alarm.ringing.listen(_handleRinging);
  }

  /// The app's language setting, or null for "follow the device".
  ///
  /// Read straight off `user_settings` rather than through `SettingsService`:
  /// this runs inside `configureDependencies()`, where the database is open
  /// but the settings singleton may not be, and one row is all it wants.
  Future<String?> _readLanguageCode() async {
    try {
      final db = await AppDatabase.getInstance();
      return await db.userSettingsDao.getValue(SettingsKeys.locale);
    } catch (e) {
      debugPrint('[AndroidAlertGateway] locale read failed: $e');
      return null;
    }
  }

  // ── Ring handling ────────────────────────────────────────────────────

  /// `Alarm.ringing` emits an **empty set on subscribe** (it is an rxdart
  /// `ValueStream`), so an unguarded listener would push an alarm page on
  /// every single launch — an empty set simply has nothing to emit.
  ///
  /// The set **shrinking** is the other half. A ring this binding is tracking
  /// that has left the set, and that [stopRinging] did not take out of
  /// [_rings] first, was stopped from the package's own notification — the
  /// only Stop there is when the phone is in use, since Android turns a
  /// full-screen intent into a heads-up then.
  void _handleRinging(AlarmSet set) {
    final live = <int>{for (final alarm in set.alarms) alarm.id};
    for (final osId in _pluginRings.toList()) {
      if (live.contains(osId)) continue;
      _endRing(osId, AlertRingEndCause.dismissed);
    }
    for (final alarm in set.alarms) {
      final payload = AlertPayload.decode(alarm.payload);
      if (payload == null) continue;
      _pluginRings.add(alarm.id);
      _emitRing(payload.copyWith(osId: alarm.id));
    }
  }

  void _emitRing(AlertPayload payload) {
    if (!_trackRing(payload)) return;
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
    _pluginRings.remove(osId);
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
    // Stopped while the setting was being read: arming now would leave a
    // timer that fires `Alarm.stop` on whatever holds this id by then — and a
    // snooze of a snooze is re-armed under the same one.
    if (!_rings.containsKey(osId)) return;
    _silenceTimers[osId] = Timer(Duration(minutes: minutes), () {
      unawaited(_silence(osId));
    });
  }

  /// Ends an unanswered ring. Reported as `timedOut` rather than folded into
  /// [stopRinging], because nobody acknowledged anything.
  Future<void> _silence(int osId) async {
    final payload = _rings[osId];
    await stopRinging(osId);
    if (payload == null || _ringEnded.isClosed) return;
    _ringEnded.add((payload: payload, cause: AlertRingEndCause.timedOut));
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

  /// The local file a picked sound has been copied into, or null when this
  /// device cannot open it — a URI from another phone, a revoked permission, a
  /// provider that is simply gone.
  ///
  /// The copy happens natively and off the main thread; asking twice for the
  /// same URI is cheap, because the second call finds the file already there.
  Future<String?> _resolvePickedSound(String uri) async {
    try {
      return await _platform.invokeMethod<String>('resolveAlarmSound', uri);
    } catch (e) {
      debugPrint('[AndroidAlertGateway] resolveAlarmSound failed: $e');
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
    // `follow` is spelled as the bare backend name on purpose: it is the
    // everyday answer, so the registry keeps the token it has always held and
    // an upgrade — or a phone whose volume never went near the floor — re-arms
    // nothing at all.
    return _ringVolume == AlertRingVolume.follow
        ? backendName
        : '$backendName@${_ringVolume.name}';
  }

  // ── Scheduling ───────────────────────────────────────────────────────

  @override
  Future<bool> schedule(PlannedFire fire, AlertPayload payload) async {
    await initialize();
    if (payload.isAlarm && !kAlarmTierUsesNotifications) {
      return _scheduleAlarm(fire, payload);
    }
    return _scheduleNotification(fire, payload);
  }

  Future<bool> _scheduleAlarm(PlannedFire fire, AlertPayload payload) async {
    final l10n = _l10n;
    // Resolved before `Alarm.set` and never allowed to stop it: a sound that
    // could not be copied is a ring with the bundled sound, not a missing ring.
    final sound = fire.sound;
    final assetAudioPath = alarmAssetPathFor(
      sound,
      resolvedPath: sound is AlertSoundUri
          ? await _resolvePickedSound(sound.uri)
          : null,
    );
    try {
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
          ),
          notificationSettings: NotificationSettings(
            title: payload.isTest ? l10n.alertsTestAlarm : payload.title,
            body: payload.timeLabel,
            stopButton: l10n.alarmStop,
            icon: kAlertSmallIcon,
          ),
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
      await _plugin.zonedSchedule(
        id: payload.osId,
        title: payload.isTest ? l10n.alertsTestAlarm : payload.title,
        body: payload.timeLabel,
        scheduledDate: tz.TZDateTime.from(fire.fireAt, tz.local),
        payload: payload.encode(),
        // The fallback alarm uses `setAlarmClock`, which becomes the system's
        // next wake-from-idle and is not Doze rate-limited; a reminder takes
        // the quieter exact tier.
        androidScheduleMode: alarmTier
            ? AndroidScheduleMode.alarmClock
            : AndroidScheduleMode.exactAllowWhileIdle,
        notificationDetails: NotificationDetails(
          android: alarmTier
              ? _alarmFallbackDetails(l10n, silenceAfter!)
              : _reminderDetails(l10n),
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[AndroidAlertGateway] zonedSchedule failed: $e');
      return false;
    }
  }

  AndroidNotificationDetails _alarmFallbackDetails(
    AppLocalizations l10n,
    int timeoutAfterMillis,
  ) {
    return AndroidNotificationDetails(
      kAlertAlarmChannelId,
      l10n.alertsAlarmChannel,
      channelDescription: l10n.alertsAlarmChannelDesc,
      importance: Importance.max,
      priority: Priority.max,
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
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          kAlertDoneActionId,
          l10n.alarmStop,
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );
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
    // Asked of **both** backends. A registration records which one armed it,
    // but the tier's backend can be switched under a standing entry, and
    // cancelling an id a platform does not hold is a no-op by contract.
    try {
      await Alarm.stop(osId);
    } catch (e) {
      debugPrint('[AndroidAlertGateway] Alarm.stop($osId) failed: $e');
    }
    try {
      await _plugin.cancel(id: osId);
    } catch (e) {
      debugPrint('[AndroidAlertGateway] cancel($osId) failed: $e');
    }
    _silenceTimers.remove(osId)?.cancel();
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
      await _plugin.show(
        // Its own id space, so a Missed notice never replaces or is replaced
        // by a live registration that happens to share an os id.
        id: missedNotificationId(payload.osId),
        title: l10n.alertsMissedTitle(payload.title),
        body: l10n.alertsMissedBody(payload.timeLabel),
        payload: payload.encode(),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            kAlertReminderChannelId,
            l10n.alertsReminderChannel,
            channelDescription: l10n.alertsReminderChannelDesc,
            importance: Importance.low,
            priority: Priority.low,
            icon: kAlertSmallIcon,
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
    // Out of both maps **before** `Alarm.stop`, which is what tells
    // [_handleRinging] this ending was the app's own and not a dismissal.
    _pluginRings.remove(osId);
    _rings.remove(osId);
    if (_rings.isEmpty) unawaited(_showOverKeyguard(false));
    try {
      await Alarm.stop(osId);
    } catch (e) {
      debugPrint('[AndroidAlertGateway] stopRinging($osId) failed: $e');
    }
    try {
      await _plugin.cancel(id: osId);
    } catch (e) {
      debugPrint('[AndroidAlertGateway] stopRinging cancel($osId) failed: $e');
    }
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
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return null;
      final payload = AlertPayload.decode(
        details?.notificationResponse?.payload,
      );
      if (payload == null) return null;
      if (isMissedNotification(details?.notificationResponse?.id, payload)) {
        _launchIntent = OpenEventIntent(payload: payload);
      } else if (payload.isAlarm) {
        await _plugin.cancel(id: payload.osId);
        // Tracked like a warm ring, so the silence timer and the keyguard flag
        // cover a fallback alarm that launched the app — but not emitted: the
        // caller queues the intent it is handed.
        _trackRing(payload);
        _launchIntent = OpenAlarmIntent(payload: payload);
      } else {
        _launchIntent = OpenEventIntent(payload: payload);
      }
      return _launchIntent;
    } catch (e) {
      debugPrint('[AndroidAlertGateway] launchIntent failed: $e');
      return null;
    }
  }

  @override
  Set<int> get ringingIds => Set<int>.unmodifiable(_rings.keys);

  @override
  Future<void> dispose() async {
    await _ringingSub?.cancel();
    for (final timer in _silenceTimers.values) {
      timer.cancel();
    }
    _silenceTimers.clear();
    await _ringing.close();
    await _ringEnded.close();
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
