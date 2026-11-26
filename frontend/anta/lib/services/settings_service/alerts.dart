part of '../settings_service.dart';

/// The five event-alert options (**v40**), read as one statement.
///
/// Permission state is deliberately **not** among them: it is per device,
/// the user can revoke it in Android's own settings between two frames, and
/// a cached copy would be a lie the moment it mattered. The gateway is asked
/// live instead.
const List<String> _alertKeys = [
  SettingsKeys.alertDefaultTimed,
  SettingsKeys.alertDefaultAllDay,
  SettingsKeys.alertSound,
  SettingsKeys.alertSnoozeMinutes,
  SettingsKeys.alertSilenceAfterMinutes,
  SettingsKeys.alertNoticeLeadMinutes,
];

/// Decodes the alert bundle out of an already-read key/value map.
///
/// Pure and static, so [getAlertSettings] and [getCalendarPageSettings]
/// share one implementation and cannot disagree about what `notify:10`
/// means — the failure mode that would otherwise show up as an editor
/// seeding one default and the settings page displaying another.
AlertSettings _decodeAlertSettings(Map<String, String> values) {
  return (
    timedDefault: _decodeTimedAlertDefault(
      values[SettingsKeys.alertDefaultTimed],
    ),
    allDayDefault: _decodeAllDayAlertDefault(
      values[SettingsKeys.alertDefaultAllDay],
    ),
    sound: values[SettingsKeys.alertSound] ?? SettingsKeys.defaultAlertSound,
    snoozeMinutes:
        _decodeInt(
          values[SettingsKeys.alertSnoozeMinutes],
          SettingsKeys.defaultAlertSnoozeMinutes,
        ).clamp(
          SettingsKeys.minAlertSnoozeMinutes,
          SettingsKeys.maxAlertSnoozeMinutes,
        ),
    silenceAfterMinutes:
        _decodeInt(
          values[SettingsKeys.alertSilenceAfterMinutes],
          SettingsKeys.defaultAlertSilenceAfterMinutes,
        ).clamp(
          SettingsKeys.minAlertSilenceAfterMinutes,
          SettingsKeys.maxAlertSilenceAfterMinutes,
        ),
    noticeLeadMinutes:
        _decodeInt(
          values[SettingsKeys.alertNoticeLeadMinutes],
          SettingsKeys.defaultAlertNoticeLeadMinutes,
        ).clamp(
          SettingsKeys.minAlertNoticeLeadMinutes,
          SettingsKeys.maxAlertNoticeLeadMinutes,
        ),
  );
}

/// `mode:offsetMinutes`, or `none` for "seed a new timed event with no
/// alert". Anything unparseable falls back to the shipped default, which is
/// `none` too: a row this build cannot read must not start attaching alerts
/// nobody asked for. Only the *seed* is at stake — an event's own alerts
/// live in their table and are untouched by this setting.
TimedAlertDefault? _decodeTimedAlertDefault(String? raw) {
  final value = raw ?? SettingsKeys.defaultAlertDefaultTimed;
  if (value == _alertDefaultNone) return null;
  final parts = value.split(':');
  if (parts.length != 2) return _decodeTimedAlertDefault(null);
  final offset = int.tryParse(parts[1]);
  if (offset == null || offset < 0) return _decodeTimedAlertDefault(null);
  return (mode: AlertMode.fromName(parts[0]), offsetMinutes: offset);
}

/// `mode:daysBefore:minuteOfDay`, or `none`.
AllDayAlertDefault? _decodeAllDayAlertDefault(String? raw) {
  final value = raw ?? SettingsKeys.defaultAlertDefaultAllDay;
  if (value == _alertDefaultNone) return null;
  final parts = value.split(':');
  if (parts.length != 3) return _decodeAllDayAlertDefault(null);
  final days = int.tryParse(parts[1]);
  final minute = int.tryParse(parts[2]);
  if (days == null || days < 0 || minute == null) {
    return _decodeAllDayAlertDefault(null);
  }
  return (
    mode: AlertMode.fromName(parts[0]),
    daysBefore: days,
    dayMinute: minute.clamp(0, EventAlert.minutesPerDay - 1),
  );
}

/// The stored value that means "a new event gets no alert".
const String _alertDefaultNone = 'none';

/// Hands the all-day default's minute to [EventAlerts], which is where every
/// synchronous describer of an alert reads it. Done on the read paths rather
/// than in the decoder because the decoder is pure — it also produces
/// [shippedAlertSettings], which must not move what is published.
AlertSettings _publishAlertDefaults(AlertSettings settings) {
  EventAlerts.configureDefaultDayMinute(settings.allDayDefault?.dayMinute);
  return settings;
}

/// Event alerts: the sound, the snooze and silence times, the defaults a
/// new event takes — and the latches beside them: whether notifications
/// were asked for, the permission prompts, and the app's own language for
/// the alert binding.
mixin _AlertSettings on _FastingSettings {
  /// Which sound an alarm plays when its alert names none of its own —
  /// `AlertSound.systemDefaultValue` for the phone's own default alarm, or a
  /// URI the phone's picker returned.
  ///
  /// Normalised through the codec on write as well as on read, so a value this
  /// build cannot make sense of is stored as the phone's default rather than
  /// kept around to decode to it on every read.
  Future<void> setAlertSound(String? value) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.alertSound,
      AlertSound.decode(value).stored ?? SettingsKeys.defaultAlertSound,
    );
  }

  /// How long Snooze postpones an alert, clamped on write as well as on read
  /// so a hand-edited row can never hand the platform a snooze of zero.
  Future<void> setAlertSnoozeMinutes(int value) async {
    await _setInt(
      SettingsKeys.alertSnoozeMinutes,
      value.clamp(
        SettingsKeys.minAlertSnoozeMinutes,
        SettingsKeys.maxAlertSnoozeMinutes,
      ),
    );
  }

  /// How long an unacknowledged alarm keeps ringing.
  Future<void> setAlertSilenceAfterMinutes(int value) async {
    await _setInt(
      SettingsKeys.alertSilenceAfterMinutes,
      value.clamp(
        SettingsKeys.minAlertSilenceAfterMinutes,
        SettingsKeys.maxAlertSilenceAfterMinutes,
      ),
    );
  }

  /// How far ahead of an alarm its upcoming notice is posted; `0` is off.
  /// Clamped on write as on read, like the two sliders beside it.
  Future<void> setAlertNoticeLeadMinutes(int value) async {
    await _setInt(
      SettingsKeys.alertNoticeLeadMinutes,
      value.clamp(
        SettingsKeys.minAlertNoticeLeadMinutes,
        SettingsKeys.maxAlertNoticeLeadMinutes,
      ),
    );
  }

  /// Whether the runtime notification prompt has already been raised once
  /// (§6.1). See [SettingsKeys.alertNotificationsAsked] for why this is a
  /// latch rather than a cached permission.
  Future<bool> getAlertNotificationsAsked() => _getBool(
    SettingsKeys.alertNotificationsAsked,
    SettingsKeys.defaultAlertNotificationsAsked,
  );

  Future<void> setAlertNotificationsAsked(bool value) =>
      _setBool(SettingsKeys.alertNotificationsAsked, value);

  /// The app's own language as `AppSettingsBloc` stores it, or null for
  /// "follow the device".
  ///
  /// Here for a reader that asks again and again while the app runs — the
  /// alert binding does, once per scheduling pass. Read straight off
  /// `AppDatabase.getInstance()`, each of those reads would also re-resolve
  /// which database is active, and that call carries out a stored switch on
  /// the spot: it closes the connection everything else is bound to. This
  /// answers from the database the singleton already holds.
  Future<String?> getLocaleCode() =>
      _db.userSettingsDao.getValue(SettingsKeys.locale);

  Future<String?> getPermissionPromptAcknowledged() =>
      _db.userSettingsDao.getValue(SettingsKeys.permissionPromptAcknowledged);

  Future<void> setPermissionPromptAcknowledged(String value) => _db
      .userSettingsDao
      .setValue(SettingsKeys.permissionPromptAcknowledged, value);

  Future<bool> getPermissionLaunchPrompt() => _getBool(
    SettingsKeys.permissionLaunchPrompt,
    SettingsKeys.defaultPermissionLaunchPrompt,
  );

  Future<void> setPermissionLaunchPrompt(bool value) =>
      _setBool(SettingsKeys.permissionLaunchPrompt, value);

  /// The alert a new **timed** event is seeded with, or `null` for "none".
  /// Encoded as `mode:offsetMinutes`, the spelling
  /// [_decodeTimedAlertDefault] reads back.
  Future<void> setAlertDefaultTimed(TimedAlertDefault? value) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.alertDefaultTimed,
      value == null
          ? _alertDefaultNone
          : '${value.mode.name}:${value.offsetMinutes}',
    );
  }

  /// The same for an **all-day** event, as `mode:daysBefore:minuteOfDay`.
  Future<void> setAlertDefaultAllDay(AllDayAlertDefault? value) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.alertDefaultAllDay,
      value == null
          ? _alertDefaultNone
          : '${value.mode.name}:${value.daysBefore}:${value.dayMinute}',
    );
    EventAlerts.configureDefaultDayMinute(value?.dayMinute);
  }

  /// Every event-alert option in one statement.
  ///
  /// The editor seeds a new event's first alert from it, and the scheduler
  /// reads the snooze and silence lengths — so it is read on a save path and
  /// on a ring path, never inside `build`.
  Future<AlertSettings> getAlertSettings() async {
    return _publishAlertDefaults(
      _decodeAlertSettings(await _db.userSettingsDao.getValuesFor(_alertKeys)),
    );
  }
}
