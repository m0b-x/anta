part of '../settings_service.dart';

// Calendar - Enabled religious-fasting traditions (empty set = off).
Set<FastingTradition> _decodeFastingTraditions(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  final traditions = <FastingTradition>{};
  for (final part in raw.split(',')) {
    final tradition = FastingTradition.fromName(part.trim());
    if (tradition != null) traditions.add(tradition);
  }
  return traditions;
}

/// Per-tradition fasting look & feel. When the appearance key is absent,
/// the retired global style key seeds every tradition, so upgrading never
/// silently resets someone's chosen look.
FastingAppearance _decodeFastingAppearance(String? raw, String? legacyStyle) {
  if (raw != null && raw.isNotEmpty) {
    return FastingAppearance.decode(raw);
  }
  return FastingAppearance.decode(
    null,
    fallbackStyle: legacyStyle == null
        ? null
        : FastingDisplayStyle.fromName(legacyStyle),
  );
}

/// The personal practice schedule. When the JSON key is absent the retired
/// weekday CSV seeds it, so upgrading never silently resets someone's
/// practice — including the deliberate "no weekly fast" empty string. That
/// is why the absent-vs-empty distinction is resolved here rather than
/// inside the decoder: a null row means the weekdays were never chosen.
/// [legacyWeekdayCsv] must stay nullable all the way down: `null` means the
/// weekdays were never chosen, `''` means a deliberate "no weekly fast".
FastingSchedule _decodeFastingSchedule(String? raw, String? legacyWeekdayCsv) {
  if (raw != null && raw.isNotEmpty) return FastingSchedule.decode(raw);
  return FastingSchedule.decode(null, legacyWeekdayCsv: legacyWeekdayCsv);
}

/// Fasting: the enabled traditions, how they are drawn, and the schedule.
mixin _FastingSettings on _OverviewAndReportSettings {
  Future<Set<FastingTradition>> getFastingTraditions() async {
    return _decodeFastingTraditions(
      await _db.userSettingsDao.getValue(
        SettingsKeys.calendarFastingTraditions,
      ),
    );
  }

  Future<void> setFastingTraditions(Set<FastingTradition> traditions) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarFastingTraditions,
      traditions.map((t) => t.name).join(','),
    );
  }

  Future<FastingAppearance> getFastingAppearance() async {
    final raw = await _db.userSettingsDao.getValue(
      SettingsKeys.calendarFastingAppearance,
    );
    return _decodeFastingAppearance(
      raw,
      // Only reached when the primary key is absent, so the retired key is
      // not read on the common path.
      (raw != null && raw.isNotEmpty)
          ? null
          : await _db.userSettingsDao.getValue(
              SettingsKeys.calendarFastingStyle,
            ),
    );
  }

  Future<void> setFastingAppearance(FastingAppearance appearance) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarFastingAppearance,
      appearance.encode(),
    );
  }

  Future<bool> getFastingOrthodoxGreatFasts() async {
    return _getBool(SettingsKeys.calendarFastingOrthodoxGreatFasts, true);
  }

  Future<void> setFastingOrthodoxGreatFasts(bool value) async {
    await _setBool(SettingsKeys.calendarFastingOrthodoxGreatFasts, value);
  }

  Future<FastingSchedule> getFastingSchedule() async {
    final raw = await _db.userSettingsDao.getValue(
      SettingsKeys.calendarFastingSchedule,
    );
    return _decodeFastingSchedule(
      raw,
      (raw != null && raw.isNotEmpty)
          ? null
          : await _db.userSettingsDao.getValue(
              SettingsKeys.calendarFastingWeekdays,
            ),
    );
  }

  Future<void> setFastingSchedule(FastingSchedule schedule) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarFastingSchedule,
      schedule.encode(),
    );
  }
}
