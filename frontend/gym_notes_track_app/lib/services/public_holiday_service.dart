import 'package:flutter/foundation.dart';

import '../constants/public_holidays.dart';
import '../constants/settings_keys.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../database/daos/public_holiday_dao.dart';

/// Loads and seeds the `public_holidays` table, exposes a synchronous
/// in-memory cache used by [PublicHolidays.isHoliday]/[PublicHolidays.holidayOn].
///
/// On [getInstance] it:
///   1. Reads the user's selected [HolidayProfile] from `user_settings`
///      (defaulting to [HolidayProfile.generic] for backward compat with
///      pre-profile installs).
///   2. Seeds that profile's holidays for the current year and the five
///      following years using insert-if-not-exists semantics, so the
///      window naturally rolls forward and never overwrites user edits.
///   3. Loads every row into memory and publishes the cache via
///      [PublicHolidays.updateCache].
///
/// Switching profiles is a single call to [setProfile]: rows tagged with
/// the previous profile are dropped, the new profile is seeded, and the
/// cache is republished. User-added customs (rows whose `profile` column
/// equals [kCustomHolidayProfileKey]) survive every switch.
class PublicHolidayService {
  static PublicHolidayService? _instance;

  late AppDatabase _db;
  late PublicHolidayDao _dao;
  HolidayProfile _profile = HolidayProfile.generic;
  Map<DateTime, PublicHolidayInfo> _cache = const {};

  PublicHolidayService._();

  static Future<PublicHolidayService> getInstance() async {
    if (_instance != null) return _instance!;
    final service = PublicHolidayService._();
    service._db = await AppDatabase.getInstance();
    service._dao = service._db.publicHolidayDao;
    service._profile = await service._readProfile();
    await service._load();
    _instance = service;
    DatabaseLifecycle.registerResetHandler(reset);
    return service;
  }

  /// Drops the cached singleton and clears the static [PublicHolidays] cache so
  /// stale holiday data from a closed database cannot leak into
  /// [PublicHolidays.holidayOn] before the next [getInstance] republishes it.
  /// Invoked by [DatabaseLifecycle] when the active database changes.
  static void reset() {
    _instance = null;
    PublicHolidays.resetCache();
  }

  /// The currently active holiday profile.
  HolidayProfile get profile => _profile;

  /// Unmodifiable view over the in-memory cache. Callers must never mutate
  /// the returned map — use [addCustom] / [removeOn] to change persisted
  /// holiday data and let the service republish the cache.
  Map<DateTime, PublicHolidayInfo> get cache => Map.unmodifiable(_cache);

  // ── Profile management ───────────────────────────────────────────────

  /// Switches the active holiday profile.
  ///
  /// Nothing is seeded or re-seeded: the new profile's holidays are computed
  /// on demand, so the switch is just a settings write plus dropping the
  /// previous profile's stored rows (its suppressions no longer apply — a
  /// day removed from the German set says nothing about the Romanian one).
  /// Custom rows (`profile = 'custom'`) are never touched.
  ///
  /// No-op when [next] equals the current [profile].
  Future<void> setProfile(HolidayProfile next) async {
    if (next == _profile) return;
    final previous = _profile;
    await _db.transaction(() async {
      await _dao.deleteProfile(previous.name);
      await _writeProfile(next);
      _profile = next;
    });
    await _load();
  }

  Future<HolidayProfile> _readProfile() async {
    final raw = await _db.userSettingsDao.getValue(SettingsKeys.holidayProfile);
    return PublicHolidays.profileFromName(raw);
  }

  Future<void> _writeProfile(HolidayProfile profile) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.holidayProfile,
      profile.name,
    );
  }

  // ── Cache load / DB seed ─────────────────────────────────────────────

  /// Republishes the user's stored deltas to [PublicHolidays], which layers
  /// them over the computed built-in set. Only deltas live in the table:
  /// custom holidays and suppressions. Built-ins are never stored — they are
  /// recomputed per year from (profile, year), so every year in the
  /// calendar's range resolves without a seeding pass.
  Future<void> _load() async {
    final rows = await _dao.getAll();
    final overrides = <DateTime, PublicHolidayInfo>{};
    final suppressed = <DateTime, Set<String>>{};
    for (final row in rows) {
      final key = _dateOnlyUtc(row.date);
      if (row.suppressed) {
        (suppressed[key] ??= <String>{}).add(row.nameKey);
        continue;
      }
      if (row.nameKey == kCustomPublicHolidayKey) {
        overrides[key] = PublicHolidayInfo.custom(row.customLabel ?? '');
      } else {
        // Built-in rows only survive here from a pre-v22 database or an old
        // backup; they resolve to the same value the computed set produces.
        final builtIn = _nameToHoliday[row.nameKey];
        if (builtIn != null) {
          overrides[key] = PublicHolidayInfo.builtIn(builtIn);
        }
      }
    }
    _cache = overrides;
    PublicHolidays.configure(
      profile: _profile,
      overrides: overrides,
      suppressed: suppressed,
    );
  }

  static final Map<String, PublicHoliday> _nameToHoliday = {
    for (final v in PublicHoliday.values) v.name: v,
  };

  static DateTime _dateOnlyUtc(DateTime value) {
    final asUtc = DateTime.fromMillisecondsSinceEpoch(
      value.millisecondsSinceEpoch,
      isUtc: true,
    );
    return DateTime.utc(asUtc.year, asUtc.month, asUtc.day);
  }

  /// Adds a user-defined custom holiday. No-op if a row already exists
  /// for the same `(date, nameKey='custom')` pair.
  Future<void> addCustom(DateTime date, String label) async {
    final key = DateTime.utc(date.year, date.month, date.day);
    final inserted = await _dao.insertIfMissing(
      date: key,
      nameKey: kCustomPublicHolidayKey,
      profile: kCustomHolidayProfileKey,
      customLabel: label,
    );
    if (inserted) await _load();
  }

  /// Removes the holiday(s) on [date] for this specific occurrence only.
  ///
  /// A custom row is hard-deleted; a built-in is recorded as a **suppression
  /// row**, which is the only thing that can persist "not on this date" now
  /// that built-ins are computed rather than stored — without it the next
  /// resolve would hand the holiday straight back. Legacy stored built-ins
  /// are flagged in place by the same call. Undo via [restoreSuppressed].
  Future<void> removeOn(DateTime date) async {
    final key = DateTime.utc(date.year, date.month, date.day);
    await _dao.suppressOn(key);
    final computed = HolidaySeeds.forYear(_profile, key.year)[key];
    if (computed != null) {
      await _dao.insertIfMissing(
        date: key,
        nameKey: computed.holiday.name,
        profile: _profile.name,
        suppressed: true,
      );
    }
    await _load();
  }

  /// Every built-in holiday the user has suppressed for a specific date,
  /// across whichever profile(s) still have rows in the table. Feeds the
  /// "restore a removed holiday" list in Calendar Settings.
  Future<List<SuppressedHoliday>> suppressedHolidays() async {
    final rows = await _dao.getSuppressed();
    return [
      for (final row in rows)
        if (_nameToHoliday[row.nameKey] case final holiday?)
          SuppressedHoliday(date: _dateOnlyUtc(row.date), holiday: holiday),
    ];
  }

  /// Restores a single suppressed built-in holiday by **deleting** its
  /// suppression row: the holiday itself is computed, so removing the "not
  /// here" marker is what brings it back — clearing the flag instead would
  /// leave a stored duplicate of derived data behind.
  Future<void> restoreSuppressed(DateTime date, PublicHoliday holiday) async {
    final key = DateTime.utc(date.year, date.month, date.day);
    await _dao.deleteOn(key, holiday.name);
    await _load();
  }

  // ── Backup export / import ────────────────────────────────────────────

  /// Snapshot of every holiday row (built-in and user-custom) for
  /// inclusion in a full-app backup. User edits to the built-in set
  /// (suppressions for a given date, custom additions) round-trip exactly
  /// because we mirror the row shape verbatim, including the `profile`
  /// and `suppressed` columns for forward/backward compatibility.
  Future<List<Map<String, dynamic>>> exportData() async {
    final rows = await _dao.getAll();
    return [
      for (final row in rows)
        {
          'dateMs': row.date.millisecondsSinceEpoch,
          'nameKey': row.nameKey,
          'profile': row.profile,
          'customLabel': row.customLabel,
          'suppressed': row.suppressed,
        },
    ];
  }

  /// Replaces every persisted holiday with the contents of [data].
  ///
  /// **Only user deltas are imported.** Plain built-in rows in an older
  /// backup are derived data — recomputed from (profile, year) — so they are
  /// skipped rather than restored: importing them would pin a stale copy of
  /// another profile's holidays over the computed set. Custom holidays and
  /// suppressions round-trip exactly, which is the whole of what a user can
  /// actually author. Backups missing a `profile` field are treated as
  /// `generic`; backups missing `suppressed` import as `false`.
  Future<void> importData(List<dynamic> data) async {
    await _dao.deleteAll();
    for (final raw in data) {
      if (raw is! Map) continue;
      final map = raw.cast<String, dynamic>();
      final dateMs = map['dateMs'];
      final nameKey = map['nameKey'] as String?;
      if (dateMs is! int || nameKey == null) continue;
      final date = _dateOnlyUtc(
        DateTime.fromMillisecondsSinceEpoch(dateMs, isUtc: true),
      );
      final isSuppression = (map['suppressed'] as bool?) ?? false;
      if (!isSuppression && nameKey != kCustomPublicHolidayKey) continue;
      final profile =
          (map['profile'] as String?) ??
          (nameKey == kCustomPublicHolidayKey
              ? kCustomHolidayProfileKey
              : HolidayProfile.generic.name);
      try {
        await _dao.insertIfMissing(
          date: date,
          nameKey: nameKey,
          profile: profile,
          customLabel: map['customLabel'] as String?,
          suppressed: isSuppression,
        );
      } catch (e) {
        debugPrint('[PublicHolidayService] Import row error: $e');
      }
    }
    await _load();
  }
}

/// A single built-in holiday the user has suppressed for one specific
/// dated occurrence. Exposed for the "restore a removed holiday" list in
/// Calendar Settings — see [PublicHolidayService.suppressedHolidays].
class SuppressedHoliday {
  final DateTime date;
  final PublicHoliday holiday;
  const SuppressedHoliday({required this.date, required this.holiday});
}

