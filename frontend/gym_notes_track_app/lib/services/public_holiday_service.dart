import 'package:flutter/foundation.dart';

import '../constants/public_holidays.dart';
import '../constants/settings_keys.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../database/daos/public_holiday_dao.dart';
import '../utils/liturgical_computus.dart';

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

  /// Number of upcoming years (inclusive of the current year) that
  /// built-in seeds cover. Six years balances DB size with the user not
  /// having to re-launch every year.
  static const int _seedYearWindow = 6;

  PublicHolidayService._();

  static Future<PublicHolidayService> getInstance() async {
    if (_instance != null) return _instance!;
    final service = PublicHolidayService._();
    service._db = await AppDatabase.getInstance();
    service._dao = service._db.publicHolidayDao;
    service._profile = await service._readProfile();
    await service._seedDefaults();
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
    PublicHolidays.updateCache(const {});
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
  /// Atomically: deletes every built-in row owned by the *previous*
  /// profile, persists the new selection, seeds the new profile's
  /// holidays for the covered year window, and republishes the cache.
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
      await _seedDefaults();
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

  Future<void> _load() async {
    final rows = await _dao.getAll();
    final next = <DateTime, PublicHolidayInfo>{};
    for (final row in rows) {
      // Suppressed rows are kept in storage (so the seeder's
      // insert-if-missing pass never resurrects them) but must not
      // resolve as a holiday, so skip them when building the cache.
      if (row.suppressed) continue;
      final key = _dateOnlyUtc(row.date);
      if (row.nameKey == kCustomPublicHolidayKey) {
        next[key] = PublicHolidayInfo.custom(row.customLabel ?? '');
      } else {
        final builtIn = _nameToHoliday[row.nameKey];
        if (builtIn != null) {
          // Last write wins when multiple built-ins land on the same
          // date (rare, e.g. profile-specific overlap). The composite
          // PK guarantees they're distinct rows in storage.
          next[key] = PublicHolidayInfo.builtIn(builtIn);
        }
      }
    }
    _cache = next;
    PublicHolidays.updateCache(next, coveredYears: _seedYearRange);
  }

  /// Range of years (inclusive) that this seeder guarantees coverage for.
  /// `PublicHolidays` uses this to decide when to fall back to the
  /// static fixed-date map for out-of-window queries.
  (int min, int max) get _seedYearRange {
    final start = DateTime.now().year;
    return (start, start + _seedYearWindow - 1);
  }

  Future<void> _seedDefaults() async {
    final (startYear, endYearInclusive) = _seedYearRange;
    try {
      await _db.transaction(() async {
        for (var year = startYear; year <= endYearInclusive; year++) {
          for (final seed in _buildSeeds(_profile, year)) {
            await _dao.insertIfMissing(
              date: seed.date,
              nameKey: seed.holiday.name,
              profile: _profile.name,
            );
          }
        }
      });
    } catch (e) {
      debugPrint('[PublicHolidayService] Seed error: $e');
    }
  }

  /// Returns the holidays to seed for [profile] in [year].
  ///
  /// Each profile's date math lives in its own helper for testability
  /// and so adding a new region is a localized change. Movable feasts
  /// derive from Easter Sunday (Gregorian for [HolidayProfile.generic],
  /// Orthodox for [HolidayProfile.romania]).
  static Iterable<_HolidaySeed> _buildSeeds(HolidayProfile profile, int year) {
    return switch (profile) {
      HolidayProfile.generic => _genericSeeds(year),
      HolidayProfile.europe => _europeSeeds(year),
      HolidayProfile.germany => _germanySeeds(year),
      HolidayProfile.romania => _romaniaSeeds(year),
      HolidayProfile.unitedKingdom => _unitedKingdomSeeds(year),
      HolidayProfile.unitedStates => _unitedStatesSeeds(year),
      HolidayProfile.none => const [],
    };
  }

  /// Catholic-leaning Christian set — historical default. Matches the
  /// holidays the app shipped before profiles existed, so an installed
  /// user's Calendar looks identical after upgrading until they actively
  /// switch profiles.
  static Iterable<_HolidaySeed> _genericSeeds(int year) sync* {
    final easter = _easterSundayGregorian(year);
    yield _HolidaySeed(DateTime.utc(year, 1, 1), PublicHoliday.newYear);
    yield _HolidaySeed(DateTime.utc(year, 1, 6), PublicHoliday.epiphany);
    yield _HolidaySeed(
      easter.subtract(const Duration(days: 2)),
      PublicHoliday.goodFriday,
    );
    yield _HolidaySeed(easter, PublicHoliday.easterSunday);
    yield _HolidaySeed(
      easter.add(const Duration(days: 1)),
      PublicHoliday.easterMonday,
    );
    yield _HolidaySeed(DateTime.utc(year, 5, 1), PublicHoliday.labourDay);
    yield _HolidaySeed(
      easter.add(const Duration(days: 39)),
      PublicHoliday.ascension,
    );
    yield _HolidaySeed(
      easter.add(const Duration(days: 49)),
      PublicHoliday.pentecost,
    );
    yield _HolidaySeed(
      easter.add(const Duration(days: 50)),
      PublicHoliday.whitMonday,
    );
    yield _HolidaySeed(DateTime.utc(year, 8, 15), PublicHoliday.assumption);
    yield _HolidaySeed(DateTime.utc(year, 11, 1), PublicHoliday.allSaints);
    yield _HolidaySeed(DateTime.utc(year, 12, 24), PublicHoliday.christmasEve);
    yield _HolidaySeed(DateTime.utc(year, 12, 25), PublicHoliday.christmasDay);
    yield _HolidaySeed(
      DateTime.utc(year, 12, 26),
      PublicHoliday.secondChristmasDay,
    );
    yield _HolidaySeed(DateTime.utc(year, 12, 31), PublicHoliday.newYearsEve);
  }

  /// Romanian official non-working days — civil holidays + Orthodox
  /// Christian feasts. Easter dates are computed via the Julian-calendar
  /// Meeus algorithm and converted to Gregorian.
  static Iterable<_HolidaySeed> _romaniaSeeds(int year) sync* {
    final easter = _easterSundayOrthodox(year);
    yield _HolidaySeed(DateTime.utc(year, 1, 1), PublicHoliday.newYear);
    yield _HolidaySeed(DateTime.utc(year, 1, 24), PublicHoliday.unificationDay);
    yield _HolidaySeed(
      easter.subtract(const Duration(days: 2)),
      PublicHoliday.goodFriday,
    );
    yield _HolidaySeed(easter, PublicHoliday.easterSunday);
    yield _HolidaySeed(
      easter.add(const Duration(days: 1)),
      PublicHoliday.easterMonday,
    );
    yield _HolidaySeed(DateTime.utc(year, 5, 1), PublicHoliday.labourDay);
    yield _HolidaySeed(DateTime.utc(year, 6, 1), PublicHoliday.childrensDay);
    yield _HolidaySeed(
      easter.add(const Duration(days: 49)),
      PublicHoliday.pentecost,
    );
    yield _HolidaySeed(
      easter.add(const Duration(days: 50)),
      PublicHoliday.whitMonday,
    );
    yield _HolidaySeed(DateTime.utc(year, 8, 15), PublicHoliday.assumption);
    yield _HolidaySeed(DateTime.utc(year, 11, 30), PublicHoliday.stAndrewDay);
    yield _HolidaySeed(
      DateTime.utc(year, 12, 1),
      PublicHoliday.nationalDayRomania,
    );
    yield _HolidaySeed(DateTime.utc(year, 12, 25), PublicHoliday.christmasDay);
    yield _HolidaySeed(
      DateTime.utc(year, 12, 26),
      PublicHoliday.secondChristmasDay,
    );
  }

  /// United States federal holidays. Movable days are computed Mondays /
  /// Thursdays; fixed civil days fall on their calendar date (observance
  /// shifting to the nearest weekday is intentionally not modelled).
  static Iterable<_HolidaySeed> _unitedStatesSeeds(int year) sync* {
    yield _HolidaySeed(DateTime.utc(year, 1, 1), PublicHoliday.newYear);
    yield _HolidaySeed(
      _nthWeekdayOfMonth(year, 1, DateTime.monday, 3),
      PublicHoliday.martinLutherKingDay,
    );
    yield _HolidaySeed(
      _nthWeekdayOfMonth(year, 2, DateTime.monday, 3),
      PublicHoliday.presidentsDay,
    );
    yield _HolidaySeed(
      _lastWeekdayOfMonth(year, 5, DateTime.monday),
      PublicHoliday.memorialDay,
    );
    yield _HolidaySeed(DateTime.utc(year, 6, 19), PublicHoliday.juneteenth);
    yield _HolidaySeed(DateTime.utc(year, 7, 4), PublicHoliday.independenceDay);
    yield _HolidaySeed(
      _nthWeekdayOfMonth(year, 9, DateTime.monday, 1),
      PublicHoliday.laborDayUnitedStates,
    );
    yield _HolidaySeed(
      _nthWeekdayOfMonth(year, 10, DateTime.monday, 2),
      PublicHoliday.columbusDay,
    );
    yield _HolidaySeed(DateTime.utc(year, 11, 11), PublicHoliday.veteransDay);
    yield _HolidaySeed(
      _nthWeekdayOfMonth(year, 11, DateTime.thursday, 4),
      PublicHoliday.thanksgiving,
    );
    yield _HolidaySeed(DateTime.utc(year, 12, 25), PublicHoliday.christmasDay);
  }

  /// United Kingdom (England & Wales) bank holidays. Easter-derived days
  /// use the Gregorian computus; the three named bank holidays fall on
  /// fixed Mondays.
  static Iterable<_HolidaySeed> _unitedKingdomSeeds(int year) sync* {
    final easter = _easterSundayGregorian(year);
    yield _HolidaySeed(DateTime.utc(year, 1, 1), PublicHoliday.newYear);
    yield _HolidaySeed(
      easter.subtract(const Duration(days: 2)),
      PublicHoliday.goodFriday,
    );
    yield _HolidaySeed(
      easter.add(const Duration(days: 1)),
      PublicHoliday.easterMonday,
    );
    yield _HolidaySeed(
      _nthWeekdayOfMonth(year, 5, DateTime.monday, 1),
      PublicHoliday.earlyMayBankHoliday,
    );
    yield _HolidaySeed(
      _lastWeekdayOfMonth(year, 5, DateTime.monday),
      PublicHoliday.springBankHoliday,
    );
    yield _HolidaySeed(
      _lastWeekdayOfMonth(year, 8, DateTime.monday),
      PublicHoliday.summerBankHoliday,
    );
    yield _HolidaySeed(DateTime.utc(year, 12, 25), PublicHoliday.christmasDay);
    yield _HolidaySeed(
      DateTime.utc(year, 12, 26),
      PublicHoliday.secondChristmasDay,
    );
  }

  /// German nationwide federal public holidays (those observed in every
  /// federal state). State-specific feasts (e.g. Epiphany, Corpus Christi,
  /// Reformation Day, All Saints) are intentionally excluded.
  static Iterable<_HolidaySeed> _germanySeeds(int year) sync* {
    final easter = _easterSundayGregorian(year);
    yield _HolidaySeed(DateTime.utc(year, 1, 1), PublicHoliday.newYear);
    yield _HolidaySeed(
      easter.subtract(const Duration(days: 2)),
      PublicHoliday.goodFriday,
    );
    yield _HolidaySeed(
      easter.add(const Duration(days: 1)),
      PublicHoliday.easterMonday,
    );
    yield _HolidaySeed(DateTime.utc(year, 5, 1), PublicHoliday.labourDay);
    yield _HolidaySeed(
      easter.add(const Duration(days: 39)),
      PublicHoliday.ascension,
    );
    yield _HolidaySeed(
      easter.add(const Duration(days: 50)),
      PublicHoliday.whitMonday,
    );
    yield _HolidaySeed(DateTime.utc(year, 10, 3), PublicHoliday.germanUnityDay);
    yield _HolidaySeed(DateTime.utc(year, 12, 25), PublicHoliday.christmasDay);
    yield _HolidaySeed(
      DateTime.utc(year, 12, 26),
      PublicHoliday.secondChristmasDay,
    );
  }

  /// Pan-European combined set: the most widely shared Christian feasts and
  /// civil holidays observed across European countries, plus Europe Day
  /// (9 May). Easter-derived days use the Gregorian computus.
  static Iterable<_HolidaySeed> _europeSeeds(int year) sync* {
    final easter = _easterSundayGregorian(year);
    yield _HolidaySeed(DateTime.utc(year, 1, 1), PublicHoliday.newYear);
    yield _HolidaySeed(DateTime.utc(year, 1, 6), PublicHoliday.epiphany);
    yield _HolidaySeed(
      easter.subtract(const Duration(days: 2)),
      PublicHoliday.goodFriday,
    );
    yield _HolidaySeed(easter, PublicHoliday.easterSunday);
    yield _HolidaySeed(
      easter.add(const Duration(days: 1)),
      PublicHoliday.easterMonday,
    );
    yield _HolidaySeed(DateTime.utc(year, 5, 1), PublicHoliday.labourDay);
    yield _HolidaySeed(DateTime.utc(year, 5, 9), PublicHoliday.europeDay);
    yield _HolidaySeed(
      easter.add(const Duration(days: 39)),
      PublicHoliday.ascension,
    );
    yield _HolidaySeed(
      easter.add(const Duration(days: 49)),
      PublicHoliday.pentecost,
    );
    yield _HolidaySeed(
      easter.add(const Duration(days: 50)),
      PublicHoliday.whitMonday,
    );
    yield _HolidaySeed(DateTime.utc(year, 8, 15), PublicHoliday.assumption);
    yield _HolidaySeed(DateTime.utc(year, 11, 1), PublicHoliday.allSaints);
    yield _HolidaySeed(DateTime.utc(year, 12, 24), PublicHoliday.christmasEve);
    yield _HolidaySeed(DateTime.utc(year, 12, 25), PublicHoliday.christmasDay);
    yield _HolidaySeed(
      DateTime.utc(year, 12, 26),
      PublicHoliday.secondChristmasDay,
    );
    yield _HolidaySeed(DateTime.utc(year, 12, 31), PublicHoliday.newYearsEve);
  }

  /// Date of the [n]-th [weekday] (1 = Mon … 7 = Sun, per [DateTime]) in
  /// [month] of [year]. `n` is 1-based (e.g. 3 = third Monday).
  static DateTime _nthWeekdayOfMonth(int year, int month, int weekday, int n) {
    final first = DateTime.utc(year, month, 1);
    final offset = (weekday - first.weekday + 7) % 7;
    return DateTime.utc(year, month, 1 + offset + (n - 1) * 7);
  }

  /// Date of the last [weekday] (per [DateTime]) in [month] of [year].
  static DateTime _lastWeekdayOfMonth(int year, int month, int weekday) {
    final last = DateTime.utc(year, month + 1, 0); // day 0 = last of `month`
    final offset = (last.weekday - weekday + 7) % 7;
    return last.subtract(Duration(days: offset));
  }

  /// Easter computus lives in [LiturgicalComputus] (shared with the
  /// fasting engine); these wrappers keep the seed builders' call sites.
  static DateTime _easterSundayGregorian(int year) =>
      LiturgicalComputus.easterSundayGregorian(year);

  static DateTime _easterSundayOrthodox(int year) =>
      LiturgicalComputus.easterSundayOrthodox(year);

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

  /// Removes the holiday(s) on [date] for this specific occurrence only —
  /// a built-in row is kept but flagged `suppressed` (so it survives an
  /// app restart or a backup restore instead of being silently
  /// re-inserted by the seeder), while a custom row is hard-deleted. Use
  /// [suppressedHolidays] / [restoreSuppressed] to undo a built-in removal.
  Future<void> removeOn(DateTime date) async {
    final key = DateTime.utc(date.year, date.month, date.day);
    await _dao.suppressOn(key);
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

  /// Restores a single suppressed built-in holiday.
  Future<void> restoreSuppressed(DateTime date, PublicHoliday holiday) async {
    final key = DateTime.utc(date.year, date.month, date.day);
    await _dao.unsuppress(key, holiday.name);
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

  /// Replaces every persisted holiday with the contents of [data]. The
  /// next startup will re-seed any built-in rows that are still missing
  /// for the active profile (idempotent), so a backup taken before a
  /// new built-in was added will not block the seeder from filling it
  /// in. Backups missing a `profile` field are treated as `generic`
  /// (matches the v12 → v13 migration's back-fill behaviour); backups
  /// missing `suppressed` (taken before this field existed) import as
  /// `false`, matching the historical "never suppressed" behaviour.
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
          suppressed: (map['suppressed'] as bool?) ?? false,
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

class _HolidaySeed {
  final DateTime date;
  final PublicHoliday holiday;
  const _HolidaySeed(this.date, this.holiday);
}
