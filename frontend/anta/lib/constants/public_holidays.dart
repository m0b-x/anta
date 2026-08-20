import '../l10n/app_localizations.dart';
import '../utils/liturgical_computus.dart';

/// Available built-in holiday profiles.
///
/// Each profile is a curated list of holidays for a region or tradition,
/// **computed on demand** by [HolidaySeeds] rather than stored — switching
/// profiles (via `setProfile`) is just a settings write plus dropping the
/// previous profile's stored deltas; user-added custom rows always survive.
///
/// Declared in the order they appear in the settings dropdown (the display
/// names are alphabetical, with `none` pinned last as the "off" option).
///
/// To add a new profile:
///   1. Add a value here.
///   2. Add a builder plus its [HolidaySeeds._seedsFor] branch (and a branch
///      in the substitute-day switch in [HolidaySeeds.forYear]).
///   3. Localize its display name in `PublicHolidays.profileNameOf`
///      and add the matching ARB key (`holidayProfile<EnumName>`).
enum HolidayProfile {
  /// Western (Catholic-leaning) Christian set with Gregorian Easter.
  /// Historical default — matches what the app shipped before profiles
  /// existed, so it must stay the fallback in [PublicHolidays.profileFromName].
  generic,

  /// Pan-European combined set: the most widely shared Christian and civil
  /// holidays across Europe, plus Europe Day.
  europe,

  /// German nationwide federal public holidays.
  germany,

  /// Romanian national + Orthodox Christian set (Orthodox Easter dates).
  romania,

  /// United Kingdom (England & Wales) bank holidays.
  unitedKingdom,

  /// United States federal holidays (movable Mondays/Thursdays included).
  unitedStates,

  /// Empty set: no built-in holidays. Users can still add customs.
  none,
}

/// Sentinel `profile` value used in the `public_holidays` table for
/// user-added rows. Distinct from any [HolidayProfile.name] so profile
/// switches can purge built-ins without touching customs.
const String kCustomHolidayProfileKey = 'custom';

/// Known public holidays recognized by the app.
///
/// Built-in holidays are **computed per year** by [HolidaySeeds], never
/// stored. The `public_holidays` table holds only user deltas: a custom
/// holiday (sentinel `custom` in `name_key` plus a `custom_label`) or a
/// suppression marking a built-in removed from one date.
///
/// To add a new built-in holiday:
///   1. Add a value to [PublicHoliday].
///   2. Localize its label in [PublicHolidays.nameOf] and in the ARB files
///      (key pattern: `publicHoliday<EnumName>`).
///   3. Yield it from the appropriate per-profile builder in [HolidaySeeds],
///      with an `if (year >= NNNN)` guard when it has a start year.
enum PublicHoliday {
  // ── Christian / shared ─────────────────────────────────────────────
  newYear,
  epiphany,
  goodFriday,
  easterSunday,
  easterMonday,
  labourDay,
  ascension,
  pentecost,
  whitMonday,
  assumption,
  allSaints,
  christmasEve,
  christmasDay,
  secondChristmasDay,
  newYearsEve,

  // ── Romania-specific ───────────────────────────────────────────────
  /// 24 January — Unification of the Romanian Principalities.
  unificationDay,

  /// 1 June — Children's Day.
  childrensDay,

  /// 30 November — Saint Andrew's Day.
  stAndrewDay,

  /// 1 December — Romanian National Day.
  nationalDayRomania,

  // ── United States ──────────────────────────────────────────────────
  /// 3rd Monday of January — Martin Luther King Jr. Day.
  martinLutherKingDay,

  /// 3rd Monday of February — Presidents' Day (Washington's Birthday).
  presidentsDay,

  /// Last Monday of May — Memorial Day.
  memorialDay,

  /// 19 June — Juneteenth National Independence Day.
  juneteenth,

  /// 4 July — Independence Day.
  independenceDay,

  /// 1st Monday of September — Labor Day (US).
  laborDayUnitedStates,

  /// 2nd Monday of October — Columbus Day.
  columbusDay,

  /// 11 November — Veterans Day.
  veteransDay,

  /// 4th Thursday of November — Thanksgiving.
  thanksgiving,

  // ── United Kingdom ─────────────────────────────────────────────────
  /// 1st Monday of May — Early May Bank Holiday.
  earlyMayBankHoliday,

  /// Last Monday of May — Spring Bank Holiday.
  springBankHoliday,

  /// Last Monday of August — Summer Bank Holiday.
  summerBankHoliday,

  // ── Germany ────────────────────────────────────────────────────────
  /// 3 October — German Unity Day.
  germanUnityDay,

  // ── Europe ─────────────────────────────────────────────────────────
  /// 9 May — Europe Day (Schuman Day).
  europeDay,
}

/// Sentinel `name_key` used in the `public_holidays` table for user-added
/// rows whose display string lives in the row's `custom_label` column.
const String kCustomPublicHolidayKey = 'custom';

/// Resolved holiday entry as returned by [PublicHolidays.holidayOn].
/// Either [builtIn] is non-null (use [PublicHolidays.nameOf]) or
/// [customLabel] holds the display string verbatim.
class PublicHolidayInfo {
  final PublicHoliday? builtIn;
  final String? customLabel;

  /// True when this date is a **substitute** day for a holiday that fell on
  /// a weekend (UK bank holidays, US federal observance) rather than the
  /// holiday's own date. Display-only: [PublicHolidays.labelOf] marks it, so
  /// two "Christmas Day" rows in one week explain themselves.
  final bool observed;

  const PublicHolidayInfo._({
    this.builtIn,
    this.customLabel,
    this.observed = false,
  });
  const PublicHolidayInfo.builtIn(
    PublicHoliday holiday, {
    bool observed = false,
  }) : this._(builtIn: holiday, observed: observed);
  const PublicHolidayInfo.custom(String label) : this._(customLabel: label);
}

/// Synchronous facade resolving which holiday (if any) falls on a day.
///
/// Built-in holidays are **computed, never stored**: they are a pure function
/// of (profile, year) — see [HolidaySeeds] — so every year in the calendar's
/// navigable range resolves correctly, including Easter-derived feasts,
/// without seeding a single database row. Years are memoized on first touch
/// exactly like `FastingCalendar`'s per-year maps, which is what makes an
/// unbounded range free: a month view touches at most two years, and one
/// year costs one Easter computus plus ~15 date constructions.
///
/// The database holds only what cannot be recomputed — the user's deltas:
/// custom holidays and per-date suppressions — which
/// [PublicHolidayService] pushes in through [configure].
abstract final class PublicHolidays {
  /// User-added custom holidays (and any legacy stored built-in rows),
  /// keyed by `DateTime.utc(year, month, day)`. Wins over the computed set.
  static Map<DateTime, PublicHolidayInfo> _overrides = const {};

  /// Built-ins the user removed, as date → suppressed `PublicHoliday.name`s.
  /// Keyed per name rather than per date so restoring one holiday on a day
  /// that carries two does not resurrect the other.
  static Map<DateTime, Set<String>> _suppressed = const {};

  /// Active profile, or null while `PublicHolidayService` has not
  /// initialized — in which case [holidayOn] answers from [_fixedFallback]
  /// so the calendar still renders something sensible (and tests that never
  /// build a database keep working).
  static HolidayProfile? _profile;

  /// Memoized computed holidays per year. Bounded like the fasting engine's
  /// year cache: paging a century of months can never grow it without limit.
  static final Map<int, Map<DateTime, HolidayOccurrence>> _years = {};
  static const int _yearCacheCap = 12;

  static int _revision = 0;

  /// Bumped whenever the resolved holiday set changes. Same shape and same
  /// purpose as `EventSkips.revision`: `WorkdaysRecurrence` and
  /// `PublicHolidaysOnlyRecurrence` read [isHoliday] from inside `occursOn`,
  /// so a profile switch or a suppression changes **membership** — which days
  /// those events occur on — with no event row touched. `CalendarBloc` folds
  /// this into its day cache as a generation, so a stale month cannot survive
  /// a holiday change.
  static int get revision => _revision;

  /// Built-in fixed-date fallback used before the service has initialized.
  static const Map<(int, int), PublicHoliday> _fixedFallback = {
    (1, 1): PublicHoliday.newYear,
    (1, 6): PublicHoliday.epiphany,
    (5, 1): PublicHoliday.labourDay,
    (8, 15): PublicHoliday.assumption,
    (11, 1): PublicHoliday.allSaints,
    (12, 24): PublicHoliday.christmasEve,
    (12, 25): PublicHoliday.christmasDay,
    (12, 26): PublicHoliday.secondChristmasDay,
    (12, 31): PublicHoliday.newYearsEve,
  };

  /// Publishes the active profile and the user's stored deltas. Called by
  /// `PublicHolidayService` after every load or mutation; drops the memoized
  /// years because a profile switch changes what every year resolves to.
  static void configure({
    required HolidayProfile profile,
    required Map<DateTime, PublicHolidayInfo> overrides,
    required Map<DateTime, Set<String>> suppressed,
  }) {
    _profile = profile;
    _overrides = Map.unmodifiable(overrides);
    _suppressed = Map.unmodifiable(suppressed);
    _years.clear();
    _revision++;
  }

  /// Returns to the uninitialized state (see [_profile]). Invoked by
  /// `PublicHolidayService.reset` when the active database changes, so
  /// deltas from a closed database can never leak into the next one.
  static void resetCache() {
    _profile = null;
    _overrides = const {};
    _suppressed = const {};
    _years.clear();
    _revision++;
  }

  /// Computed built-ins for [year], memoized. Clears wholesale at the cap
  /// rather than evicting one entry: the map is tiny and rebuilding a year
  /// costs microseconds, so an LRU would be more bookkeeping than it saves.
  static Map<DateTime, HolidayOccurrence> _computedFor(
    HolidayProfile profile,
    int year,
  ) {
    final cached = _years[year];
    if (cached != null) return cached;
    if (_years.length >= _yearCacheCap) _years.clear();
    return _years[year] = HolidaySeeds.forYear(profile, year);
  }

  static PublicHolidayInfo? holidayOn(DateTime day) {
    final key = DateTime.utc(day.year, day.month, day.day);
    // A user's own entry outranks the computed set, so a custom holiday can
    // sit on a date the profile already claims.
    final override = _overrides[key];
    if (override != null) return override;
    final profile = _profile;
    if (profile == null) {
      final fixed = _fixedFallback[(day.month, day.day)];
      return fixed == null ? null : PublicHolidayInfo.builtIn(fixed);
    }
    final computed = _computedFor(profile, key.year)[key];
    if (computed == null) return null;
    if (_suppressed[key]?.contains(computed.holiday.name) ?? false) return null;
    return PublicHolidayInfo.builtIn(
      computed.holiday,
      observed: computed.observed,
    );
  }

  static bool isHoliday(DateTime day) => holidayOn(day) != null;

  /// Resolves the localized label for a built-in holiday enum value.
  static String nameOf(PublicHoliday holiday, AppLocalizations l10n) {
    return switch (holiday) {
      PublicHoliday.newYear => l10n.publicHolidayNewYear,
      PublicHoliday.epiphany => l10n.publicHolidayEpiphany,
      PublicHoliday.goodFriday => l10n.publicHolidayGoodFriday,
      PublicHoliday.easterSunday => l10n.publicHolidayEasterSunday,
      PublicHoliday.easterMonday => l10n.publicHolidayEasterMonday,
      PublicHoliday.labourDay => l10n.publicHolidayLabourDay,
      PublicHoliday.ascension => l10n.publicHolidayAscension,
      PublicHoliday.pentecost => l10n.publicHolidayPentecost,
      PublicHoliday.whitMonday => l10n.publicHolidayWhitMonday,
      PublicHoliday.assumption => l10n.publicHolidayAssumption,
      PublicHoliday.allSaints => l10n.publicHolidayAllSaints,
      PublicHoliday.christmasEve => l10n.publicHolidayChristmasEve,
      PublicHoliday.christmasDay => l10n.publicHolidayChristmasDay,
      PublicHoliday.secondChristmasDay => l10n.publicHolidaySecondChristmasDay,
      PublicHoliday.newYearsEve => l10n.publicHolidayNewYearsEve,
      PublicHoliday.unificationDay => l10n.publicHolidayUnificationDay,
      PublicHoliday.childrensDay => l10n.publicHolidayChildrensDay,
      PublicHoliday.stAndrewDay => l10n.publicHolidayStAndrewDay,
      PublicHoliday.nationalDayRomania => l10n.publicHolidayNationalDayRomania,
      PublicHoliday.martinLutherKingDay =>
        l10n.publicHolidayMartinLutherKingDay,
      PublicHoliday.presidentsDay => l10n.publicHolidayPresidentsDay,
      PublicHoliday.memorialDay => l10n.publicHolidayMemorialDay,
      PublicHoliday.juneteenth => l10n.publicHolidayJuneteenth,
      PublicHoliday.independenceDay => l10n.publicHolidayIndependenceDay,
      PublicHoliday.laborDayUnitedStates =>
        l10n.publicHolidayLaborDayUnitedStates,
      PublicHoliday.columbusDay => l10n.publicHolidayColumbusDay,
      PublicHoliday.veteransDay => l10n.publicHolidayVeteransDay,
      PublicHoliday.thanksgiving => l10n.publicHolidayThanksgiving,
      PublicHoliday.earlyMayBankHoliday =>
        l10n.publicHolidayEarlyMayBankHoliday,
      PublicHoliday.springBankHoliday => l10n.publicHolidaySpringBankHoliday,
      PublicHoliday.summerBankHoliday => l10n.publicHolidaySummerBankHoliday,
      PublicHoliday.germanUnityDay => l10n.publicHolidayGermanUnityDay,
      PublicHoliday.europeDay => l10n.publicHolidayEuropeDay,
    };
  }

  /// Resolves the localized display name for a [HolidayProfile].
  static String profileNameOf(HolidayProfile profile, AppLocalizations l10n) {
    return switch (profile) {
      HolidayProfile.generic => l10n.holidayProfileGeneric,
      HolidayProfile.europe => l10n.holidayProfileEurope,
      HolidayProfile.germany => l10n.holidayProfileGermany,
      HolidayProfile.romania => l10n.holidayProfileRomania,
      HolidayProfile.unitedKingdom => l10n.holidayProfileUnitedKingdom,
      HolidayProfile.unitedStates => l10n.holidayProfileUnitedStates,
      HolidayProfile.none => l10n.holidayProfileNone,
    };
  }

  /// Parses a stored [HolidayProfile.name] back into the enum, falling
  /// back to [HolidayProfile.generic] for unrecognized values (forward
  /// compatibility with backups taken from a future version that adds
  /// new profiles).
  static HolidayProfile profileFromName(String? name) {
    if (name == null) return HolidayProfile.generic;
    for (final value in HolidayProfile.values) {
      if (value.name == name) return value;
    }
    return HolidayProfile.generic;
  }

  /// Convenience: resolves the localized display label for any
  /// [PublicHolidayInfo], including user-added custom entries.
  static String labelOf(PublicHolidayInfo info, AppLocalizations l10n) {
    final builtIn = info.builtIn;
    if (builtIn == null) return info.customLabel ?? '';
    final name = nameOf(builtIn, l10n);
    return info.observed ? l10n.publicHolidayObserved(name) : name;
  }
}

/// One generated holiday occurrence: the holiday itself plus whether this
/// date is a **substitute** (a weekend holiday's statutory day off) rather
/// than the holiday's own date. Both are emitted — you want to see Christmas
/// on Christmas *and* see which weekday is actually off.
typedef HolidayOccurrence = ({PublicHoliday holiday, bool observed});

/// Generates a profile's built-in holidays for a single year.
///
/// **Pure and dependency-free** — no database, no I/O, no state. That is the
/// whole point: because a year's holidays are a function of (profile, year),
/// they never need to be persisted, and [PublicHolidays] can answer any year
/// in the calendar's range by calling this and memoizing the result. The
/// `public_holidays` table therefore stores only user deltas.
///
/// Each profile's date math lives in its own builder for testability and so
/// adding a region is a localized change. Movable feasts derive from Easter
/// Sunday — Gregorian for the Western profiles, Orthodox (Julian computus
/// converted to Gregorian) for [HolidayProfile.romania] — via
/// [LiturgicalComputus], which is exact from 1900 (the floor `CalendarBounds`
/// enforces).
///
/// Holidays created (or moved) by legislation carry a `if (year >= NNNN)`
/// guard so browsing a past year does not show an anachronism — Juneteenth
/// did not exist in 1991, and the UK's Monday bank holidays were fixed in
/// 1971. The guard sits inline with the date it governs, which keeps each
/// region's history readable in one place. [HolidayProfile.generic] and
/// [HolidayProfile.europe] are deliberately unguarded: they are curated
/// convenience sets rather than a jurisdiction, so dating them by statute
/// would be false precision.
///
/// To add a region: add a [HolidayProfile] value, a builder here, branches in
/// [_seedsFor] and [forYear]'s substitution switch, and the
/// `holidayProfile<Name>` ARB trio. New holidays also need a [PublicHoliday]
/// value plus a [PublicHolidays.nameOf] branch.
abstract final class HolidaySeeds {
  /// Built-in holidays for [profile] in [year], keyed by date-only UTC.
  ///
  /// Later entries win when two holidays share a date, matching the
  /// last-write-wins behaviour the row-backed cache had. Substitute days are
  /// applied after the base set, so they can see (and avoid) every date the
  /// profile already claims.
  static Map<DateTime, HolidayOccurrence> forYear(
    HolidayProfile profile,
    int year,
  ) {
    final map = <DateTime, HolidayOccurrence>{};
    for (final (date, holiday) in _seedsFor(profile, year)) {
      map[date] = (holiday: holiday, observed: false);
    }
    switch (profile) {
      case HolidayProfile.unitedKingdom:
        _applyUkSubstitutes(map, year);
      case HolidayProfile.unitedStates:
        _applyUsObservance(map, year);
      case HolidayProfile.generic:
      case HolidayProfile.europe:
      case HolidayProfile.germany:
      case HolidayProfile.romania:
      case HolidayProfile.none:
        // No statutory weekend substitution in these sets: Germany and
        // Romania simply lose the day when a fixed holiday falls on a
        // weekend, and generic/europe are curated sets rather than a
        // jurisdiction, so inventing a rule for them would be false
        // precision.
        break;
    }
    return Map.unmodifiable(map);
  }

  /// UK rule: a bank holiday landing on a weekend moves to the next weekday
  /// that is not already a bank holiday. Order matters — Christmas takes the
  /// first free weekday and Boxing Day the one after, which is what produces
  /// the familiar Mon/Tue pair when Christmas falls on a Saturday.
  ///
  /// Only the fixed-date days can ever need this; Good Friday, Easter Monday
  /// and the three Monday bank holidays are weekday-anchored by construction.
  static void _applyUkSubstitutes(
    Map<DateTime, HolidayOccurrence> map,
    int year,
  ) {
    final taken = <DateTime>{...map.keys};
    for (final date in [
      DateTime.utc(year, 1, 1),
      DateTime.utc(year, 12, 25),
      DateTime.utc(year, 12, 26),
    ]) {
      final entry = map[date];
      if (entry == null || date.weekday < DateTime.saturday) continue;
      var substitute = date;
      do {
        substitute = substitute.add(const Duration(days: 1));
      } while (substitute.weekday >= DateTime.saturday ||
          taken.contains(substitute));
      map[substitute] = (holiday: entry.holiday, observed: true);
      taken.add(substitute);
    }
  }

  /// US federal rule: a fixed-date holiday on a Saturday is observed the
  /// Friday before, on a Sunday the Monday after. The Monday- and
  /// Thursday-anchored holidays can never fall on a weekend.
  static void _applyUsObservance(
    Map<DateTime, HolidayOccurrence> map,
    int year,
  ) {
    for (final date in [
      DateTime.utc(year, 1, 1),
      DateTime.utc(year, 6, 19),
      DateTime.utc(year, 7, 4),
      DateTime.utc(year, 11, 11),
      DateTime.utc(year, 12, 25),
    ]) {
      final entry = map[date];
      if (entry == null) continue;
      final DateTime? observed = switch (date.weekday) {
        DateTime.saturday => date.subtract(const Duration(days: 1)),
        DateTime.sunday => date.add(const Duration(days: 1)),
        _ => null,
      };
      if (observed == null || map.containsKey(observed)) continue;
      map[observed] = (holiday: entry.holiday, observed: true);
    }
    // A New Year's Day that falls on a Saturday is observed on 31 December
    // of the *previous* year, so it belongs to this year's map even though
    // the holiday itself does not.
    if (DateTime.utc(year + 1, 1, 1).weekday == DateTime.saturday) {
      final newYearsEve = DateTime.utc(year, 12, 31);
      if (!map.containsKey(newYearsEve)) {
        map[newYearsEve] = (holiday: PublicHoliday.newYear, observed: true);
      }
    }
  }

  static Iterable<(DateTime, PublicHoliday)> _seedsFor(
    HolidayProfile profile,
    int year,
  ) {
    return switch (profile) {
      HolidayProfile.generic => _generic(year),
      HolidayProfile.europe => _europe(year),
      HolidayProfile.germany => _germany(year),
      HolidayProfile.romania => _romania(year),
      HolidayProfile.unitedKingdom => _unitedKingdom(year),
      HolidayProfile.unitedStates => _unitedStates(year),
      HolidayProfile.none => const [],
    };
  }

  /// Catholic-leaning Christian set — historical default. Matches the
  /// holidays the app shipped before profiles existed.
  static Iterable<(DateTime, PublicHoliday)> _generic(int year) sync* {
    final easter = LiturgicalComputus.easterSundayGregorian(year);
    yield (DateTime.utc(year, 1, 1), PublicHoliday.newYear);
    yield (DateTime.utc(year, 1, 6), PublicHoliday.epiphany);
    yield (easter.subtract(const Duration(days: 2)), PublicHoliday.goodFriday);
    yield (easter, PublicHoliday.easterSunday);
    yield (easter.add(const Duration(days: 1)), PublicHoliday.easterMonday);
    yield (DateTime.utc(year, 5, 1), PublicHoliday.labourDay);
    yield (easter.add(const Duration(days: 39)), PublicHoliday.ascension);
    yield (easter.add(const Duration(days: 49)), PublicHoliday.pentecost);
    yield (easter.add(const Duration(days: 50)), PublicHoliday.whitMonday);
    yield (DateTime.utc(year, 8, 15), PublicHoliday.assumption);
    yield (DateTime.utc(year, 11, 1), PublicHoliday.allSaints);
    yield (DateTime.utc(year, 12, 24), PublicHoliday.christmasEve);
    yield (DateTime.utc(year, 12, 25), PublicHoliday.christmasDay);
    yield (DateTime.utc(year, 12, 26), PublicHoliday.secondChristmasDay);
    yield (DateTime.utc(year, 12, 31), PublicHoliday.newYearsEve);
  }

  /// Romanian official non-working days — civil holidays + Orthodox
  /// Christian feasts (Julian-computus Easter converted to Gregorian).
  static Iterable<(DateTime, PublicHoliday)> _romania(int year) sync* {
    final easter = LiturgicalComputus.easterSundayOrthodox(year);
    yield (DateTime.utc(year, 1, 1), PublicHoliday.newYear);
    // Non-working day since 2016.
    if (year >= 2016) {
      yield (DateTime.utc(year, 1, 24), PublicHoliday.unificationDay);
    }
    // Added to the legal set in 2018.
    if (year >= 2018) {
      yield (
        easter.subtract(const Duration(days: 2)),
        PublicHoliday.goodFriday,
      );
    }
    yield (easter, PublicHoliday.easterSunday);
    yield (easter.add(const Duration(days: 1)), PublicHoliday.easterMonday);
    yield (DateTime.utc(year, 5, 1), PublicHoliday.labourDay);
    // Non-working day since 2017.
    if (year >= 2017) {
      yield (DateTime.utc(year, 6, 1), PublicHoliday.childrensDay);
    }
    // Pentecost and the Assumption entered the legal set in 2008.
    if (year >= 2008) {
      yield (easter.add(const Duration(days: 49)), PublicHoliday.pentecost);
      yield (easter.add(const Duration(days: 50)), PublicHoliday.whitMonday);
      yield (DateTime.utc(year, 8, 15), PublicHoliday.assumption);
    }
    // Non-working day since 2012.
    if (year >= 2012) {
      yield (DateTime.utc(year, 11, 30), PublicHoliday.stAndrewDay);
    }
    // The National Day moved to 1 December with the post-1989 constitution.
    if (year >= 1990) {
      yield (DateTime.utc(year, 12, 1), PublicHoliday.nationalDayRomania);
    }
    yield (DateTime.utc(year, 12, 25), PublicHoliday.christmasDay);
    yield (DateTime.utc(year, 12, 26), PublicHoliday.secondChristmasDay);
  }

  /// German nationwide federal public holidays (those observed in every
  /// federal state). State-specific feasts are intentionally excluded.
  static Iterable<(DateTime, PublicHoliday)> _germany(int year) sync* {
    final easter = LiturgicalComputus.easterSundayGregorian(year);
    yield (DateTime.utc(year, 1, 1), PublicHoliday.newYear);
    yield (easter.subtract(const Duration(days: 2)), PublicHoliday.goodFriday);
    yield (easter.add(const Duration(days: 1)), PublicHoliday.easterMonday);
    yield (DateTime.utc(year, 5, 1), PublicHoliday.labourDay);
    yield (easter.add(const Duration(days: 39)), PublicHoliday.ascension);
    yield (easter.add(const Duration(days: 50)), PublicHoliday.whitMonday);
    // The Day of German Unity dates from reunification in 1990.
    if (year >= 1990) {
      yield (DateTime.utc(year, 10, 3), PublicHoliday.germanUnityDay);
    }
    yield (DateTime.utc(year, 12, 25), PublicHoliday.christmasDay);
    yield (DateTime.utc(year, 12, 26), PublicHoliday.secondChristmasDay);
  }

  /// Pan-European combined set: the most widely shared Christian feasts and
  /// civil holidays across Europe, plus Europe Day (9 May).
  static Iterable<(DateTime, PublicHoliday)> _europe(int year) sync* {
    final easter = LiturgicalComputus.easterSundayGregorian(year);
    yield (DateTime.utc(year, 1, 1), PublicHoliday.newYear);
    yield (DateTime.utc(year, 1, 6), PublicHoliday.epiphany);
    yield (easter.subtract(const Duration(days: 2)), PublicHoliday.goodFriday);
    yield (easter, PublicHoliday.easterSunday);
    yield (easter.add(const Duration(days: 1)), PublicHoliday.easterMonday);
    yield (DateTime.utc(year, 5, 1), PublicHoliday.labourDay);
    yield (DateTime.utc(year, 5, 9), PublicHoliday.europeDay);
    yield (easter.add(const Duration(days: 39)), PublicHoliday.ascension);
    yield (easter.add(const Duration(days: 49)), PublicHoliday.pentecost);
    yield (easter.add(const Duration(days: 50)), PublicHoliday.whitMonday);
    yield (DateTime.utc(year, 8, 15), PublicHoliday.assumption);
    yield (DateTime.utc(year, 11, 1), PublicHoliday.allSaints);
    yield (DateTime.utc(year, 12, 24), PublicHoliday.christmasEve);
    yield (DateTime.utc(year, 12, 25), PublicHoliday.christmasDay);
    yield (DateTime.utc(year, 12, 26), PublicHoliday.secondChristmasDay);
    yield (DateTime.utc(year, 12, 31), PublicHoliday.newYearsEve);
  }

  /// United States federal holidays. Movable days are computed Mondays /
  /// Thursdays; observance shifting to the nearest weekday is intentionally
  /// not modelled.
  static Iterable<(DateTime, PublicHoliday)> _unitedStates(int year) sync* {
    yield (DateTime.utc(year, 1, 1), PublicHoliday.newYear);
    // First observed 1986, three years after the 1983 enactment.
    if (year >= 1986) {
      yield (
        _nthWeekdayOfMonth(year, 1, DateTime.monday, 3),
        PublicHoliday.martinLutherKingDay,
      );
    }
    // The Uniform Monday Holiday Act moved these to fixed Mondays in 1971;
    // before that they sat on their calendar dates.
    if (year >= 1971) {
      yield (
        _nthWeekdayOfMonth(year, 2, DateTime.monday, 3),
        PublicHoliday.presidentsDay,
      );
      yield (
        _lastWeekdayOfMonth(year, 5, DateTime.monday),
        PublicHoliday.memorialDay,
      );
      yield (
        _nthWeekdayOfMonth(year, 10, DateTime.monday, 2),
        PublicHoliday.columbusDay,
      );
    }
    // Federal holiday since June 2021.
    if (year >= 2021) {
      yield (DateTime.utc(year, 6, 19), PublicHoliday.juneteenth);
    }
    yield (DateTime.utc(year, 7, 4), PublicHoliday.independenceDay);
    yield (
      _nthWeekdayOfMonth(year, 9, DateTime.monday, 1),
      PublicHoliday.laborDayUnitedStates,
    );
    // Armistice Day became a federal holiday in 1938 and was renamed
    // Veterans Day in 1954; the 1971–1977 move to October is not modelled.
    if (year >= 1954) {
      yield (DateTime.utc(year, 11, 11), PublicHoliday.veteransDay);
    }
    // Fixed to the fourth Thursday by joint resolution, effective 1942.
    if (year >= 1942) {
      yield (
        _nthWeekdayOfMonth(year, 11, DateTime.thursday, 4),
        PublicHoliday.thanksgiving,
      );
    }
    yield (DateTime.utc(year, 12, 25), PublicHoliday.christmasDay);
  }

  /// United Kingdom (England & Wales) bank holidays.
  static Iterable<(DateTime, PublicHoliday)> _unitedKingdom(int year) sync* {
    final easter = LiturgicalComputus.easterSundayGregorian(year);
    // A bank holiday in England & Wales only since 1974.
    if (year >= 1974) {
      yield (DateTime.utc(year, 1, 1), PublicHoliday.newYear);
    }
    yield (easter.subtract(const Duration(days: 2)), PublicHoliday.goodFriday);
    yield (easter.add(const Duration(days: 1)), PublicHoliday.easterMonday);
    // Introduced in 1978.
    if (year >= 1978) {
      yield (
        _nthWeekdayOfMonth(year, 5, DateTime.monday, 1),
        PublicHoliday.earlyMayBankHoliday,
      );
    }
    // The 1971 Banking and Financial Dealings Act fixed both to Mondays
    // (spring replacing Whit Monday, summer moving off the first Monday).
    if (year >= 1971) {
      yield (
        _lastWeekdayOfMonth(year, 5, DateTime.monday),
        PublicHoliday.springBankHoliday,
      );
      yield (
        _lastWeekdayOfMonth(year, 8, DateTime.monday),
        PublicHoliday.summerBankHoliday,
      );
    }
    yield (DateTime.utc(year, 12, 25), PublicHoliday.christmasDay);
    yield (DateTime.utc(year, 12, 26), PublicHoliday.secondChristmasDay);
  }

  /// Date of the [n]-th [weekday] (1 = Mon … 7 = Sun) in [month] of [year].
  static DateTime _nthWeekdayOfMonth(int year, int month, int weekday, int n) {
    final first = DateTime.utc(year, month, 1);
    final offset = (weekday - first.weekday + 7) % 7;
    return DateTime.utc(year, month, 1 + offset + (n - 1) * 7);
  }

  /// Date of the last [weekday] in [month] of [year].
  static DateTime _lastWeekdayOfMonth(int year, int month, int weekday) {
    final last = DateTime.utc(year, month + 1, 0); // day 0 = last of `month`
    final offset = (last.weekday - weekday + 7) % 7;
    return last.subtract(Duration(days: offset));
  }
}
