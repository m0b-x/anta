import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/fasting_appearance.dart';
import '../models/fasting_schedule.dart';
import '../utils/liturgical_computus.dart';
import 'calendar_colors.dart';
import 'calendar_icons.dart';

/// What a fasting day permits — the per-day rule printed church calendars
/// carry. [daylight] and [full] describe the fast's *shape* instead
/// (dawn-to-sunset vs a complete fast), which is how the Islamic and Jewish
/// traditions express theirs.
enum FastingRegime { strict, oil, fish, dairy, penitential, daylight, full }

/// Grid decoration resolved for a single day across every enabled
/// tradition. Both slots can be filled at once (one tradition tinting the
/// cell while another bolds the number); when several ask for the same
/// slot, the one with the strongest placement wins.
class FastingCellStyle {
  final Color? tint;
  final Color? numberColor;

  const FastingCellStyle({this.tint, this.numberColor});

  static const FastingCellStyle empty = FastingCellStyle();

  bool get isEmpty => tint == null && numberColor == null;
}

/// Named fast (or fasting rule) a day belongs to.
enum FastingPeriod {
  // ── Orthodox ──
  greatLent,
  apostlesFast,
  dormitionFast,
  nativityFast,
  weekdayFast,
  cheesefareWeek,
  eveOfTheophany,
  beheadingOfStJohn,
  exaltationOfCross,
  // ── Catholic ──
  lent,
  ashWednesday,
  goodFriday,
  fridayAbstinence,
  advent,
  // ── Muslim ──
  ramadan,
  dayOfArafah,
  ashura,
  // ── Jewish ──
  yomKippur,
  tishaBAv,
  fastOfGedaliah,
  tenthOfTevet,
  seventeenthOfTammuz,
  fastOfEsther,
  // ── Personal ──
  /// A day the user forced on through their own schedule, where no tradition
  /// computes a fast.
  personalFast,
}

/// One tradition's verdict for one day.
class FastingInfo {
  final FastingTradition tradition;
  final FastingPeriod period;
  final FastingRegime regime;
  const FastingInfo(this.tradition, this.period, this.regime);
}

/// Synchronous facade computing fasting days for the enabled traditions.
///
/// Mirrors [PublicHolidays]: configured once from settings (by the calendar
/// page), then queried from build methods. Everything is derived — nothing
/// is persisted beyond the enabled-traditions setting — so lookups build a
/// whole year lazily (O(365) once per year per tradition, from
/// [LiturgicalComputus]'s O(1) date math) and are O(1) map hits afterwards,
/// which keeps day-cell builds and the day panel cheap.
///
/// The Orthodox rules follow the common printed Romanian church calendar
/// (weekday pattern per fast + the customary fish/wine-oil dispensations on
/// major feasts); the Catholic ones follow current canon (fast + abstinence
/// on Ash Wednesday and Good Friday, Friday abstinence, Lent/Advent as
/// penitential seasons); Islamic dates use the arithmetic calendar (±1 day,
/// the standard software caveat); Jewish fasts carry their Shabbat
/// postponements.
abstract final class FastingCalendar {
  static Set<FastingTradition> _traditions = const {};
  static FastingAppearance _appearance = const FastingAppearance();
  static bool _orthodoxGreatFasts = true;
  static FastingSchedule _schedule = const FastingSchedule();

  /// Lazily built per-year day maps. Bounded so a century-spanning scroll
  /// through the grid cannot accumulate maps forever.
  static final Map<int, Map<DateTime, List<FastingInfo>>> _years = {};
  static const int _yearCacheCap = 12;

  /// Memoized grid decoration per day, so `defaultBuilder` does not re-derive
  /// colours for ~42 cells every frame. Dropped whenever the computation
  /// *or* the appearance changes, and bounded like the bloc's day cache.
  static final Map<DateTime, FastingCellStyle> _cellStyles = {};
  static const int _cellCacheCap = 512;

  static int _revision = 0;

  /// Bumped whenever anything a resolver-output memo could depend on
  /// changes: an appearance-only [configure] call (cell style only) and the
  /// fuller membership-changing branch (traditions/scope/schedule) each bump
  /// once, and so does [resetConfiguration] — same shape and purpose as
  /// `EventSkips.revision` / `PublicHolidays.revision`. **Never** bumped on
  /// the `unchanged` early return below: every settings-return calls
  /// [configure] again with (almost always) identical values, and bumping on
  /// a no-op would invalidate a downstream memo on every such return.
  static int get revision => _revision;

  /// Replaces the whole configuration.
  ///
  /// The expensive part (year maps) is invalidated only when something that
  /// changes *which* days are fasting days moved — traditions, the Orthodox
  /// scope option or the personal [schedule] — so calling this on every
  /// settings reload keeps warm caches warm. [appearance] is display-only: it
  /// drops the cheap per-day style memo and nothing else.
  static void configure({
    required Set<FastingTradition> traditions,
    FastingAppearance appearance = const FastingAppearance(),
    bool orthodoxGreatFasts = true,
    FastingSchedule schedule = const FastingSchedule(),
  }) {
    if (appearance != _appearance) {
      _appearance = appearance;
      _cellStyles.clear();
      _revision++;
    }
    final unchanged =
        traditions.length == _traditions.length &&
        traditions.every(_traditions.contains) &&
        orthodoxGreatFasts == _orthodoxGreatFasts &&
        schedule == _schedule;
    if (unchanged) return;
    _traditions = Set.unmodifiable(Set.of(traditions));
    _orthodoxGreatFasts = orthodoxGreatFasts;
    _schedule = schedule;
    _years.clear();
    _cellStyles.clear();
    _revision++;
  }

  /// Drops every configured input and both caches.
  ///
  /// Part of the `DatabaseLifecycle` reset contract: the whole configuration
  /// is derived from settings rows, so switching databases would otherwise
  /// leave the previous one's practice painting the grid until the calendar
  /// page happens to remount. Invoked from `SettingsService.reset` — the
  /// settings singleton owns these rows, exactly as `PublicHolidayService`
  /// owns the `PublicHolidays` facade.
  static void resetConfiguration() {
    _traditions = const {};
    _appearance = const FastingAppearance();
    _orthodoxGreatFasts = true;
    _schedule = const FastingSchedule();
    _years.clear();
    _cellStyles.clear();
    _revision++;
  }

  static Set<FastingTradition> get traditions => _traditions;
  static bool get isEnabled => _traditions.isNotEmpty;
  static FastingAppearance get appearance => _appearance;
  static FastingSchedule get schedule => _schedule;

  static FastingTraditionStyle styleOf(FastingTradition tradition) =>
      _appearance.styleFor(tradition);

  /// Effective colour for [tradition] — its override, else the shared
  /// fasting violet.
  static Color colorOf(FastingTradition tradition) =>
      _appearance.styleFor(tradition).colorOr(CalendarColors.fasting);

  /// Effective icon for [tradition] — its override, else the built-in.
  /// Mirrors `CalendarCategories.iconFor`: an unknown key falls back rather
  /// than throwing.
  static IconData iconFor(FastingTradition tradition) =>
      CalendarIcons.forKey(_appearance.styleFor(tradition).iconKey) ??
      defaultIconOf(tradition);

  /// Grid decoration for [day], resolved across every tradition that marks
  /// it. Memoized; safe to call once per cell per build.
  ///
  /// Normalizes and delegates to [cellStyleForUtcDay], the
  /// `occursOn`/`occursOnUtcDay` split this codebase already uses: a caller
  /// that is already holding a date-only UTC day should call that directly
  /// rather than paying for a `DateTime` allocation it has the answer to.
  static FastingCellStyle cellStyleFor(DateTime day) =>
      cellStyleForUtcDay(DateTime.utc(day.year, day.month, day.day));

  /// [cellStyleFor] for callers that already hold a date-only UTC [day] — the
  /// grid's `_buildDayCell` does, since it computes the same key for the tint
  /// output memo on the next line (**5.4**, the safe half).
  ///
  /// The wider half of that item — threading one resolved style into
  /// `FastingCellTintProvider` so the second lookup disappears entirely — was
  /// **not** done: it would mean widening the shared
  /// `CellTintProvider.tintFor(day, events)` contract to promise a normalized
  /// day, which reaches every other provider and its tests, to save a lookup
  /// that Phase 3's tint output memo already made rare. See roadmap
  /// correction 17.
  ///
  /// [day] **must** be date-only UTC; [cellStyleFor] is the normalizing entry
  /// point for everyone else.
  static FastingCellStyle cellStyleForUtcDay(DateTime key) {
    assert(
      key == DateTime.utc(key.year, key.month, key.day),
      'cellStyleForUtcDay requires a date-only UTC day; '
      'call cellStyleFor to normalize',
    );
    if (_traditions.isEmpty) return FastingCellStyle.empty;
    final cached = _cellStyles[key];
    if (cached != null) return cached;
    final infos = on(key);
    var resolved = FastingCellStyle.empty;
    if (infos.isNotEmpty) {
      Color? tint;
      Color? numberColor;
      var tintPriority = 1 << 30;
      var numberPriority = 1 << 30;
      for (final info in infos) {
        final style = _appearance.styleFor(info.tradition);
        final priority = style.priority;
        switch (style.style) {
          case FastingDisplayStyle.tint:
            if (priority < tintPriority) {
              tintPriority = priority;
              tint = style.colorOr(CalendarColors.fasting);
            }
          case FastingDisplayStyle.strong:
            if (priority < numberPriority) {
              numberPriority = priority;
              numberColor = style.colorOr(CalendarColors.fasting);
            }
          case FastingDisplayStyle.bar:
          case FastingDisplayStyle.none:
            break;
        }
      }
      resolved = FastingCellStyle(tint: tint, numberColor: numberColor);
    }
    // A bounded FIFO, never a wholesale clear from inside the lookup: this
    // method runs twice per cell per build (`calendar_page.dart` and
    // `CellTintResolver`), so a clear here could fire between the two calls
    // for the very day being painted — the exact bug 3.4 fixed for
    // `CalendarBloc._dayCache`. Unlike that cache, this static facade has no
    // focus-change event to hang a windowed eviction on, so a single-entry
    // FIFO (`_cellStyles` is a `LinkedHashMap`; its first key is the oldest
    // insert) is the mechanism here instead — it only ever drops the one
    // entry that made the map exceed its cap.
    if (_cellStyles.length >= _cellCacheCap) {
      _cellStyles.remove(_cellStyles.keys.first);
    }
    _cellStyles[key] = resolved;
    return resolved;
  }

  /// Fasting entries for [day] — at most one per enabled tradition, in
  /// [FastingTradition] declaration order. Empty list when none apply.
  ///
  /// Left as a wholesale clear-on-overflow, unlike [cellStyleFor]'s FIFO:
  /// this cache is keyed per **year**, not per day, and a single grid frame
  /// (one month) spans at most two distinct years, well under
  /// [_yearCacheCap] (12). A clear can only fire on a miss, and the same
  /// frame's own two-year need is satisfied by the two inserts that follow
  /// immediately after — it cannot evict a year *this frame* still needs the
  /// way [cellStyleFor]'s per-day clear could evict the very day being
  /// painted. Reaching the cap at all needs 12+ distinct years touched in one
  /// session, a coarser, rarer pattern than the day-cache's.
  static List<FastingInfo> on(DateTime day) {
    if (_traditions.isEmpty) return const [];
    final key = DateTime.utc(day.year, day.month, day.day);
    var year = _years[key.year];
    if (year == null) {
      if (_years.length >= _yearCacheCap) _years.clear();
      year = _buildYear(key.year);
      _years[key.year] = year;
    }
    return year[key] ?? const [];
  }

  static bool isFastingDay(DateTime day) => on(day).isNotEmpty;

  // ── Localized display ──────────────────────────────────────────────

  static String traditionNameOf(
    FastingTradition tradition,
    AppLocalizations l10n,
  ) {
    return switch (tradition) {
      FastingTradition.orthodox => l10n.fastingTraditionOrthodox,
      FastingTradition.catholic => l10n.fastingTraditionCatholic,
      FastingTradition.muslim => l10n.fastingTraditionMuslim,
      FastingTradition.jewish => l10n.fastingTraditionJewish,
    };
  }

  static String periodNameOf(FastingPeriod period, AppLocalizations l10n) {
    return switch (period) {
      FastingPeriod.greatLent => l10n.fastingGreatLent,
      FastingPeriod.apostlesFast => l10n.fastingApostlesFast,
      FastingPeriod.dormitionFast => l10n.fastingDormitionFast,
      FastingPeriod.nativityFast => l10n.fastingNativityFast,
      FastingPeriod.weekdayFast => l10n.fastingWeekdayFast,
      FastingPeriod.cheesefareWeek => l10n.fastingCheesefareWeek,
      FastingPeriod.eveOfTheophany => l10n.fastingEveOfTheophany,
      FastingPeriod.beheadingOfStJohn => l10n.fastingBeheadingOfStJohn,
      FastingPeriod.exaltationOfCross => l10n.fastingExaltationOfCross,
      FastingPeriod.lent => l10n.fastingLent,
      FastingPeriod.ashWednesday => l10n.fastingAshWednesday,
      FastingPeriod.goodFriday => l10n.fastingGoodFriday,
      FastingPeriod.fridayAbstinence => l10n.fastingFridayAbstinence,
      FastingPeriod.advent => l10n.fastingAdvent,
      FastingPeriod.ramadan => l10n.fastingRamadan,
      FastingPeriod.dayOfArafah => l10n.fastingDayOfArafah,
      FastingPeriod.ashura => l10n.fastingAshura,
      FastingPeriod.yomKippur => l10n.fastingYomKippur,
      FastingPeriod.tishaBAv => l10n.fastingTishaBAv,
      FastingPeriod.fastOfGedaliah => l10n.fastingGedaliah,
      FastingPeriod.tenthOfTevet => l10n.fastingTenthOfTevet,
      FastingPeriod.seventeenthOfTammuz => l10n.fastingSeventeenthOfTammuz,
      FastingPeriod.fastOfEsther => l10n.fastingEstherFast,
      FastingPeriod.personalFast => l10n.fastingPersonalFast,
    };
  }

  static String regimeNameOf(FastingRegime regime, AppLocalizations l10n) {
    return switch (regime) {
      FastingRegime.strict => l10n.fastingRegimeStrict,
      FastingRegime.oil => l10n.fastingRegimeOil,
      FastingRegime.fish => l10n.fastingRegimeFish,
      FastingRegime.dairy => l10n.fastingRegimeDairy,
      FastingRegime.penitential => l10n.fastingRegimePenitential,
      FastingRegime.daylight => l10n.fastingRegimeDaylight,
      FastingRegime.full => l10n.fastingRegimeFull,
    };
  }

  /// Built-in icon for [tradition], before any user override.
  static IconData defaultIconOf(FastingTradition tradition) {
    return switch (tradition) {
      FastingTradition.orthodox || FastingTradition.catholic => Icons.church,
      FastingTradition.muslim => Icons.mosque,
      FastingTradition.jewish => Icons.synagogue,
    };
  }

  static String styleNameOf(FastingDisplayStyle style, AppLocalizations l10n) {
    return switch (style) {
      FastingDisplayStyle.tint => l10n.fastingStyleTint,
      FastingDisplayStyle.bar => l10n.fastingStyleBar,
      FastingDisplayStyle.strong => l10n.fastingStyleStrong,
      FastingDisplayStyle.none => l10n.fastingStyleNone,
    };
  }

  static String placementNameOf(
    FastingRowPlacement placement,
    AppLocalizations l10n,
  ) {
    return switch (placement) {
      FastingRowPlacement.first => l10n.fastingPlacementFirst,
      FastingRowPlacement.beforeHolidays => l10n.fastingPlacementBeforeHolidays,
      FastingRowPlacement.afterHolidays => l10n.fastingPlacementAfterHolidays,
      FastingRowPlacement.last => l10n.fastingPlacementLast,
    };
  }

  // ── Year builders ──────────────────────────────────────────────────

  static Map<DateTime, List<FastingInfo>> _buildYear(int year) {
    final out = <DateTime, List<FastingInfo>>{};
    // A month the user turned off drops every tradition's mark only in the
    // "all fasts" scope. In the default scope the month filter lives inside
    // the weekly loops instead, so a great fast still shows in a month the
    // weekly fast is not kept in. Filtering here rather than in a pass over
    // the merged map keeps it O(1) per entry already being visited.
    final filterEveryFast = _schedule.monthScope == FastingMonthScope.allFasts;
    // The weekday twin of the month scope, and subtract-only in the same way:
    // a weekday the user turned off is never marked in the "all fasts" scope,
    // so a Wed/Fri practice keeps Great Lent on Wednesdays and Fridays only
    // instead of every one of its forty days. One probe per produced entry —
    // never a second pass over the merged map.
    final filterEveryWeekday =
        _schedule.weekdayScope == FastingWeekdayScope.allFasts;
    void merge(Map<DateTime, FastingInfo> tradition) {
      tradition.forEach((day, info) {
        if (filterEveryFast && !_schedule.months.contains(day.month)) return;
        if (filterEveryWeekday && !_schedule.weekdays.contains(day.weekday)) {
          return;
        }
        (out[day] ??= []).add(info);
      });
    }

    if (_traditions.contains(FastingTradition.orthodox)) {
      merge(_buildOrthodox(year));
    }
    if (_traditions.contains(FastingTradition.catholic)) {
      merge(_buildCatholic(year));
    }
    if (_traditions.contains(FastingTradition.muslim)) {
      merge(_buildMuslim(year));
    }
    if (_traditions.contains(FastingTradition.jewish)) {
      merge(_buildJewish(year));
    }
    _applyExceptions(year, out);
    return out;
  }

  /// Personal exception dates, applied last so they override every computed
  /// rule. Walks the (hand-picked, capped) date sets rather than the merged
  /// map, so the cost is proportional to the exceptions and not to the year.
  ///
  /// A forced day no tradition claimed is attributed to the first enabled
  /// tradition in declaration order — the same one whose colour and icon the
  /// grid already uses for a day only one tradition marks.
  static void _applyExceptions(int year, Map<DateTime, List<FastingInfo>> out) {
    for (final day in _schedule.skipDates) {
      if (day.year == year) out.remove(day);
    }
    if (_schedule.forceDates.isEmpty) return;
    FastingTradition? owner;
    for (final tradition in FastingTradition.values) {
      if (_traditions.contains(tradition)) {
        owner = tradition;
        break;
      }
    }
    if (owner == null) return;
    for (final day in _schedule.forceDates) {
      if (day.year != year || out.containsKey(day)) continue;
      out[day] = [
        FastingInfo(owner, FastingPeriod.personalFast, FastingRegime.oil),
      ];
    }
  }

  static const Duration _oneDay = Duration(days: 1);

  static bool _isWeekend(DateTime d) =>
      d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;

  /// Orthodox year: the four multi-day fasts (weekday pattern + customary
  /// feast dispensations), the three strict single days, Cheesefare week's
  /// dairy days, and the year-round Wednesday/Friday fast — suppressed in
  /// the fast-free (harți) weeks that follow the great feasts.
  static Map<DateTime, FastingInfo> _buildOrthodox(int year) {
    final map = <DateTime, FastingInfo>{};
    final pascha = LiturgicalComputus.easterSundayOrthodox(year);
    const t = FastingTradition.orthodox;
    DateTime at(int m, int d) => DateTime.utc(year, m, d);
    void set(DateTime d, FastingPeriod p, FastingRegime r) {
      if (d.year == year) map[d] = FastingInfo(t, p, r);
    }

    // Fast-free (harți) windows: Christmastide (Dec 25 – Jan 4, spanning
    // the year boundary), the week after Publican & Pharisee Sunday
    // (pascha−70), Bright Week, and Trinity week after Pentecost.
    final fastFree = <DateTime>{};
    void free(DateTime start, int days) {
      for (var i = 0; i < days; i++) {
        final d = start.add(Duration(days: i));
        if (d.year == year) fastFree.add(d);
      }
    }

    free(at(1, 1), 4);
    free(at(12, 25), 7);
    free(pascha.subtract(const Duration(days: 69)), 7);
    free(pascha.add(_oneDay), 6);
    free(pascha.add(const Duration(days: 50)), 6);

    // The multi-day fasts, strict single days and Cheesefare week are
    // optional (`orthodoxGreatFasts` setting): people who keep only the
    // weekly fast days skip straight to the weekday rule below, which
    // then applies year-round.
    if (_orthodoxGreatFasts) {
      _buildOrthodoxGreatFasts(pascha, at, set);
    }

    // Weekly fast on the configured days (traditionally Wed/Fri, but a
    // personal practice can be any set — or none) in the configured months,
    // wherever nothing above applies. The fast-free weeks still win: harți
    // suspend the weekly fast for every practice.
    for (var d = at(1, 1); d.year == year; d = d.add(_oneDay)) {
      if (!_schedule.weekdays.contains(d.weekday)) continue;
      if (!_schedule.months.contains(d.month)) continue;
      if (map.containsKey(d) || fastFree.contains(d)) continue;
      map[d] = const FastingInfo(
        t,
        FastingPeriod.weekdayFast,
        FastingRegime.oil,
      );
    }
    return map;
  }

  static void _buildOrthodoxGreatFasts(
    DateTime pascha,
    DateTime Function(int m, int d) at,
    void Function(DateTime d, FastingPeriod p, FastingRegime r) set,
  ) {
    // Great Lent: Clean Monday (pascha−48) through Holy Saturday. First
    // week and Holy Week strict throughout; otherwise Mon/Wed/Fri strict,
    // the rest wine & oil; Lazarus Saturday wine & oil, Palm Sunday fish.
    final cleanMonday = pascha.subtract(const Duration(days: 48));
    final palmSunday = pascha.subtract(const Duration(days: 7));
    for (var i = 0; i < 48; i++) {
      final d = cleanMonday.add(Duration(days: i));
      final FastingRegime r;
      if (i == 41) {
        r = FastingRegime.fish; // Palm Sunday
      } else if (i == 40) {
        r = FastingRegime.oil; // Lazarus Saturday
      } else if (i >= 42 || i < 5) {
        r = FastingRegime.strict; // Holy Week / first week
      } else if (_isWeekend(d) ||
          d.weekday == DateTime.tuesday ||
          d.weekday == DateTime.thursday) {
        r = FastingRegime.oil;
      } else {
        r = FastingRegime.strict;
      }
      set(d, FastingPeriod.greatLent, r);
    }
    // Annunciation: fish when it falls in Lent (wine & oil in Holy Week).
    final annunciation = at(3, 25);
    if (!annunciation.isBefore(cleanMonday) && annunciation.isBefore(pascha)) {
      set(
        annunciation,
        FastingPeriod.greatLent,
        annunciation.isBefore(palmSunday)
            ? FastingRegime.fish
            : FastingRegime.oil,
      );
    }

    // Apostles' fast: Monday after All Saints (pascha+57) through Jun 28.
    // Variable length; vanishes entirely when Pascha falls very late.
    final apostlesStart = pascha.add(const Duration(days: 57));
    for (var d = apostlesStart; !d.isAfter(at(6, 28)); d = d.add(_oneDay)) {
      var r = _isWeekend(d)
          ? FastingRegime.fish
          : (d.weekday == DateTime.tuesday || d.weekday == DateTime.thursday)
          ? FastingRegime.oil
          : FastingRegime.strict;
      if (d.month == 6 && d.day == 24) r = FastingRegime.fish; // St John
      set(d, FastingPeriod.apostlesFast, r);
    }

    // Dormition fast: Aug 1–14, strict weekdays, wine & oil weekends,
    // fish on the Transfiguration (Aug 6).
    for (var dd = 1; dd <= 14; dd++) {
      final d = at(8, dd);
      var r = _isWeekend(d) ? FastingRegime.oil : FastingRegime.strict;
      if (dd == 6) r = FastingRegime.fish;
      set(d, FastingPeriod.dormitionFast, r);
    }

    // Nativity fast: Nov 15 – Dec 24. Fish on weekends and on the Entry
    // into the Temple (Nov 21) until the final stretch (Dec 20–24), which
    // drops fish; Christmas Eve is strict.
    for (var d = at(11, 15); !d.isAfter(at(12, 24)); d = d.add(_oneDay)) {
      final lastStretch = d.month == 12 && d.day >= 20;
      final FastingRegime r;
      if (d.month == 12 && d.day == 24) {
        r = FastingRegime.strict;
      } else if (d.month == 11 && d.day == 21) {
        r = FastingRegime.fish;
      } else if (lastStretch) {
        r = _isWeekend(d) ? FastingRegime.oil : FastingRegime.strict;
      } else if (_isWeekend(d)) {
        r = FastingRegime.fish;
      } else if (d.weekday == DateTime.tuesday ||
          d.weekday == DateTime.thursday) {
        r = FastingRegime.oil;
      } else {
        r = FastingRegime.strict;
      }
      set(d, FastingPeriod.nativityFast, r);
    }

    // Cheesefare week (between Meatfare and Cheesefare Sundays): Wednesday
    // and Friday keep a dairy-allowed fast.
    final cheeseMonday = pascha.subtract(const Duration(days: 55));
    for (var i = 0; i < 7; i++) {
      final d = cheeseMonday.add(Duration(days: i));
      if (d.weekday == DateTime.wednesday || d.weekday == DateTime.friday) {
        set(d, FastingPeriod.cheesefareWeek, FastingRegime.dairy);
      }
    }

    // Strict single days (softened to wine & oil on weekends).
    void strictDay(DateTime d, FastingPeriod p) {
      set(d, p, _isWeekend(d) ? FastingRegime.oil : FastingRegime.strict);
    }

    strictDay(at(1, 5), FastingPeriod.eveOfTheophany);
    strictDay(at(8, 29), FastingPeriod.beheadingOfStJohn);
    strictDay(at(9, 14), FastingPeriod.exaltationOfCross);
  }

  /// Catholic year: Lent (Sundays exempt) with fast + abstinence on Ash
  /// Wednesday and Good Friday and abstinence on its Fridays, Advent as a
  /// penitential season, and year-round Friday abstinence.
  static Map<DateTime, FastingInfo> _buildCatholic(int year) {
    final map = <DateTime, FastingInfo>{};
    final easter = LiturgicalComputus.easterSundayGregorian(year);
    const t = FastingTradition.catholic;
    final ashWednesday = easter.subtract(const Duration(days: 46));
    final goodFriday = easter.subtract(const Duration(days: 2));

    for (var d = ashWednesday; d.isBefore(easter); d = d.add(_oneDay)) {
      if (d.weekday == DateTime.sunday) continue;
      if (d == ashWednesday) {
        map[d] = const FastingInfo(
          t,
          FastingPeriod.ashWednesday,
          FastingRegime.strict,
        );
      } else if (d == goodFriday) {
        map[d] = const FastingInfo(
          t,
          FastingPeriod.goodFriday,
          FastingRegime.strict,
        );
      } else if (d.weekday == DateTime.friday) {
        map[d] = const FastingInfo(t, FastingPeriod.lent, FastingRegime.fish);
      } else {
        map[d] = const FastingInfo(
          t,
          FastingPeriod.lent,
          FastingRegime.penitential,
        );
      }
    }

    // Advent: from the 4th Sunday before Christmas through Dec 24.
    final christmas = DateTime.utc(year, 12, 25);
    final advent1 = christmas.subtract(
      Duration(days: christmas.weekday == 7 ? 28 : 21 + christmas.weekday),
    );
    for (var d = advent1; d.isBefore(christmas); d = d.add(_oneDay)) {
      if (d.weekday == DateTime.sunday) continue;
      map[d] = FastingInfo(
        t,
        FastingPeriod.advent,
        d.weekday == DateTime.friday
            ? FastingRegime.fish
            : FastingRegime.penitential,
      );
    }

    // Friday abstinence outside Lent and Advent, in the configured months.
    // The personal schedule may *subtract* from a tradition's own weekly rule
    // but never invent days it does not have: dropping Friday silences this
    // loop, while adding Monday is an Orthodox-side choice that must not
    // fabricate a Catholic Monday abstinence. Lent and Advent Fridays are
    // seasonal rather than weekly and are already in the map above, so they
    // stay either way.
    if (_schedule.weekdays.contains(DateTime.friday)) {
      for (
        var d = DateTime.utc(year, 1, 1);
        d.year == year;
        d = d.add(_oneDay)
      ) {
        if (d.weekday != DateTime.friday || map.containsKey(d)) continue;
        if (!_schedule.months.contains(d.month)) continue;
        map[d] = const FastingInfo(
          t,
          FastingPeriod.fridayAbstinence,
          FastingRegime.fish,
        );
      }
    }
    return map;
  }

  /// Muslim year: the whole of Ramadan plus the recommended single fasts of
  /// Arafah (9 Dhu al-Hijjah) and Ashura (10 Muharram), all dawn-to-sunset.
  /// Hijri years shift ~11 days a year, so a Gregorian year can hold parts
  /// of two — the probe window covers both.
  static Map<DateTime, FastingInfo> _buildMuslim(int year) {
    final map = <DateTime, FastingInfo>{};
    const t = FastingTradition.muslim;
    void add(DateTime d, FastingPeriod p) {
      if (d.year == year) {
        map[d] = FastingInfo(t, p, FastingRegime.daylight);
      }
    }

    final guess = LiturgicalComputus.hijriYearAtJdn(
      LiturgicalComputus.gregorianToJdn(year, 1, 1),
    );
    for (var hy = guess - 1; hy <= guess + 2; hy++) {
      final ramadanStart = LiturgicalComputus.hijriToJdn(hy, 9, 1);
      for (var i = 0; i < 30; i++) {
        add(
          LiturgicalComputus.jdnToGregorian(ramadanStart + i),
          FastingPeriod.ramadan,
        );
      }
      add(
        LiturgicalComputus.jdnToGregorian(
          LiturgicalComputus.hijriToJdn(hy, 12, 9),
        ),
        FastingPeriod.dayOfArafah,
      );
      add(
        LiturgicalComputus.jdnToGregorian(
          LiturgicalComputus.hijriToJdn(hy, 1, 10),
        ),
        FastingPeriod.ashura,
      );
    }
    return map;
  }

  /// Jewish year: the six public fasts, each a fixed offset from Rosh
  /// Hashanah or Pesach, with the traditional Shabbat deferrals (17 Tammuz,
  /// Tisha B'Av and Tzom Gedaliah move to Sunday; Ta'anit Esther moves back
  /// to Thursday). Yom Kippur and Tisha B'Av are full fasts, the minor ones
  /// dawn-to-dusk.
  static Map<DateTime, FastingInfo> _buildJewish(int year) {
    final map = <DateTime, FastingInfo>{};
    const t = FastingTradition.jewish;
    void add(DateTime d, FastingPeriod p, FastingRegime r) {
      if (d.year == year) map[d] = FastingInfo(t, p, r);
    }

    DateTime g(int jdn) => LiturgicalComputus.jdnToGregorian(jdn);
    for (var hy = year + 3759; hy <= year + 3762; hy++) {
      final rh = LiturgicalComputus.roshHashanahJdn(hy);

      var gedaliah = g(rh + 2);
      if (gedaliah.weekday == DateTime.saturday) {
        gedaliah = gedaliah.add(_oneDay);
      }
      add(gedaliah, FastingPeriod.fastOfGedaliah, FastingRegime.daylight);

      add(g(rh + 9), FastingPeriod.yomKippur, FastingRegime.full);

      final length = LiturgicalComputus.hebrewYearLength(hy);
      final cheshvan = length % 10 == 5 ? 30 : 29;
      final kislev = length % 10 == 3 ? 29 : 30;
      add(
        g(rh + 30 + cheshvan + kislev + 9),
        FastingPeriod.tenthOfTevet,
        FastingRegime.daylight,
      );

      final pesach = LiturgicalComputus.pesachJdn(hy);
      var esther = g(pesach - 31);
      if (esther.weekday == DateTime.saturday) {
        esther = esther.subtract(const Duration(days: 2));
      }
      add(esther, FastingPeriod.fastOfEsther, FastingRegime.daylight);

      var tammuz = g(pesach + 91);
      if (tammuz.weekday == DateTime.saturday) tammuz = tammuz.add(_oneDay);
      add(tammuz, FastingPeriod.seventeenthOfTammuz, FastingRegime.daylight);

      var av = g(pesach + 112);
      if (av.weekday == DateTime.saturday) av = av.add(_oneDay);
      add(av, FastingPeriod.tishaBAv, FastingRegime.full);
    }
    return map;
  }
}
