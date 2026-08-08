/// Pure calendrical arithmetic for the religious calendars the app computes
/// fasting periods and movable feasts from. Deliberately dependency-free
/// (no Flutter imports) so the math can be exercised by a plain `dart run`
/// script and reused by both `PublicHolidayService` (Easter-derived
/// holidays) and `FastingCalendar` (fasting periods).
///
/// All returned dates are date-only UTC `DateTime`s, matching the calendar
/// subsystem's normalization convention.
abstract final class LiturgicalComputus {
  // ── Gregorian Easter ───────────────────────────────────────────────

  /// Easter Sunday in the Gregorian calendar (Anonymous/Meeus computus).
  static DateTime easterSundayGregorian(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime.utc(year, month, day);
  }

  // ── Orthodox (Julian) Easter ───────────────────────────────────────

  /// Eastern Orthodox Easter Sunday for [year], expressed in the Gregorian
  /// calendar. Meeus' Julian algorithm plus the Julian → Gregorian offset.
  static DateTime easterSundayOrthodox(int year) {
    final a = year % 4;
    final b = year % 7;
    final c = year % 19;
    final d = (19 * c + 15) % 30;
    final e = (2 * a + 4 * b - d + 34) % 7;
    final julianMonth = (d + e + 114) ~/ 31;
    final julianDay = ((d + e + 114) % 31) + 1;
    final julianDate = DateTime.utc(year, julianMonth, julianDay);
    return julianDate.add(Duration(days: julianToGregorianOffset(year)));
  }

  /// Days by which the Julian calendar lags the Gregorian calendar in the
  /// given Gregorian [year]. Constant 13 across 1900–2099 (2000 is a
  /// Gregorian leap year, so no jump at that boundary); +1 at every
  /// non-leap century boundary after.
  static int julianToGregorianOffset(int year) {
    if (year < 1900) return 13;
    var offset = 13;
    for (var c = 21; c <= year ~/ 100; c++) {
      if (c % 4 != 0) offset += 1;
    }
    return offset;
  }

  // ── Julian day number ↔ Gregorian date ─────────────────────────────
  // Fliegel–Van Flandern integer algorithms; valid for the whole AD era.

  static int gregorianToJdn(int year, int month, int day) {
    final a = (month - 14) ~/ 12;
    return (1461 * (year + 4800 + a)) ~/ 4 +
        (367 * (month - 2 - 12 * a)) ~/ 12 -
        (3 * ((year + 4900 + a) ~/ 100)) ~/ 4 +
        day -
        32075;
  }

  static DateTime jdnToGregorian(int jdn) {
    var l = jdn + 68569;
    final n = (4 * l) ~/ 146097;
    l -= (146097 * n + 3) ~/ 4;
    final i = (4000 * (l + 1)) ~/ 1461001;
    l -= (1461 * i) ~/ 4 - 31;
    final j = (80 * l) ~/ 2447;
    final day = l - (2447 * j) ~/ 80;
    l = j ~/ 11;
    final month = j + 2 - 12 * l;
    final year = 100 * (n - 49) + i + l;
    return DateTime.utc(year, month, day);
  }

  // ── Tabular Islamic calendar (civil epoch) ─────────────────────────
  // The arithmetic ("Kuwaiti") calendar used by software the world over:
  // 30-year cycle with 11 leap years, months alternating 30/29 days.
  // Accuracy is ±1 day against actual moon sightings — the same caveat
  // every digital calendar carries for Islamic dates.

  /// JDN of 1 Muharram AH 1 in the civil reckoning (16 July 622).
  static const int hijriEpochJdn = 1948440;

  /// Leap years of the 30-year cycle: 2, 5, 7, 10, 13, 16, 18, 21, 24,
  /// 26, 29.
  static bool isHijriLeapYear(int hy) => (11 * hy + 14) % 30 < 11;

  /// JDN of the given tabular Islamic date. Odd months have 30 days, even
  /// months 29 (month 12 gains one in leap years, which only affects the
  /// *following* year's start and is covered by the leap-count term).
  static int hijriToJdn(int hy, int hm, int hd) {
    final daysBeforeYear = 354 * (hy - 1) + (11 * (hy - 1) + 14) ~/ 30;
    final daysBeforeMonth = 30 * (hm ~/ 2) + 29 * ((hm - 1) ~/ 2);
    return hijriEpochJdn - 1 + daysBeforeYear + daysBeforeMonth + hd;
  }

  /// Approximate Hijri year in effect at [jdn] (a 30-year cycle spans
  /// exactly 10631 days). Callers probe ±1 around it.
  static int hijriYearAtJdn(int jdn) =>
      ((jdn - hijriEpochJdn) * 30) ~/ 10631 + 1;

  // ── Hebrew calendar (fixed arithmetic) ─────────────────────────────
  // The molad-based calculation with all four dechiyot (postponements),
  // as standardized since Hillel II. Only Rosh Hashanah needs computing:
  // every public fast is a fixed offset from it (or from Pesach, itself
  // exactly 163 days before the following Rosh Hashanah — the months
  // Nisan..Elul never vary in length).

  /// JDN immediately before 1 Tishrei AM 1, calibrated so that
  /// `roshHashanahJdn(1)` lands on Monday, 7 September −3760 (Julian),
  /// JDN 347998.
  static const int hebrewEpochJdn = 347997;

  /// 19-year Metonic cycle: years 3, 6, 8, 11, 14, 17, 19 are leap.
  static bool isHebrewLeapYear(int hy) => (7 * hy + 1) % 19 < 7;

  /// Days from the epoch to 1 Tishrei of [year], dechiyot included.
  static int _hebrewElapsedDays(int year) {
    final monthsElapsed = (235 * year - 234) ~/ 19;
    final partsElapsed = 204 + 793 * (monthsElapsed % 1080);
    final hoursElapsed =
        5 +
        12 * monthsElapsed +
        793 * (monthsElapsed ~/ 1080) +
        partsElapsed ~/ 1080;
    final parts = (partsElapsed % 1080) + 1080 * (hoursElapsed % 24);
    var day = 1 + 29 * monthsElapsed + hoursElapsed ~/ 24;
    if (parts >= 19440 ||
        (day % 7 == 2 && parts >= 9924 && !isHebrewLeapYear(year)) ||
        (day % 7 == 1 && parts >= 16789 && isHebrewLeapYear(year - 1))) {
      day += 1;
    }
    if (day % 7 == 0 || day % 7 == 3 || day % 7 == 5) {
      day += 1;
    }
    return day;
  }

  /// JDN of 1 Tishrei (Rosh Hashanah) of Hebrew year [hy].
  static int roshHashanahJdn(int hy) => hebrewEpochJdn + _hebrewElapsedDays(hy);

  /// JDN of 15 Nisan (first day of Pesach) of Hebrew year [hy]. The months
  /// from Nisan to Elul are fixed-length, so Pesach is always exactly 163
  /// days before the next year's Rosh Hashanah.
  static int pesachJdn(int hy) => roshHashanahJdn(hy + 1) - 163;

  /// Length in days of Hebrew year [hy] (353/354/355 or 383/384/385).
  /// Determines Cheshvan (30 when length ends in 5) and Kislev (29 when it
  /// ends in 3), the only two variable months.
  static int hebrewYearLength(int hy) =>
      roshHashanahJdn(hy + 1) - roshHashanahJdn(hy);
}
