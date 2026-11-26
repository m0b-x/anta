part of '../settings_service.dart';

// Calendar - Max number of bars shown per day cell (overflow shows "+N").
// Clamped on both sides of the boundary, the rail cap's shape: the
// appearance page hands the stored value straight to a `Slider`.
int _decodeCalendarMaxDayBars(String? raw) {
  return _decodeInt(raw, SettingsKeys.defaultCalendarMaxDayBars).clamp(
    SettingsKeys.minCalendarMaxDayBars,
    SettingsKeys.maxCalendarMaxDayBars,
  );
}

// Calendar appearance - today highlight style.
CalendarTodayStyle _decodeCalendarTodayStyle(String? raw) =>
    CalendarTodayStyle.fromName(raw ?? SettingsKeys.defaultCalendarTodayStyle);

// Calendar appearance - event marker style (bars / dots).
CalendarMarkerStyle _decodeCalendarMarkerStyle(String? raw) =>
    CalendarMarkerStyle.fromName(
      raw ?? SettingsKeys.defaultCalendarMarkerStyle,
    );

// Calendar appearance - first day of the week.
CalendarWeekStart _decodeCalendarWeekStart(String? raw) =>
    CalendarWeekStart.fromName(raw ?? SettingsKeys.defaultCalendarWeekStart);

// Calendar appearance - custom highlight accent (null = theme primary).
int? _decodeCalendarAccentColor(String? raw) =>
    (raw == null || raw.isEmpty) ? null : int.tryParse(raw);

// Calendar appearance - how missed occurrences render (faded / hidden).
CalendarMissedDisplay _decodeCalendarMissedDisplay(String? raw) =>
    CalendarMissedDisplay.fromName(
      raw ?? SettingsKeys.defaultCalendarMissedDisplay,
    );

// Calendar appearance - which tint source wins a contested day.
CalendarTintConflict _decodeCalendarTintConflict(String? raw) =>
    CalendarTintConflict.fromName(
      raw ?? SettingsKeys.defaultCalendarTintConflict,
    );

// Calendar appearance - how the resolved wash is painted, per theme. One
// decoder over the raw string for both keys (their defaults are the only
// thing that differs, and both are constants), shared by the single-row
// getters and the bulk path so the two can never drift.
CalendarCellStyle _decodeCalendarCellStyle(String? raw, String fallback) =>
    CalendarCellStyle.fromName(raw ?? fallback);

// Calendar appearance - the left-edge day rail.
DayRailStyle _decodeCalendarDayRailStyle(String? raw) =>
    DayRailStyle.fromName(raw ?? SettingsKeys.defaultCalendarDayRailStyle);

// Calendar appearance - rail capacity. Clamped on read so a hand-edited or
// future-written value can never ask the rail for a count it cannot draw.
int _decodeCalendarMaxDayRailMarks(String? raw) {
  return _decodeInt(raw, SettingsKeys.defaultCalendarMaxDayRailMarks).clamp(
    SettingsKeys.minCalendarMaxDayRailMarks,
    SettingsKeys.maxCalendarMaxDayRailMarks,
  );
}

// Calendar appearance - which end of the `line` rail the tint runner-up's
// band takes.
DayRailBasePosition _decodeCalendarDayRailBasePosition(String? raw) =>
    DayRailBasePosition.fromName(
      raw ?? SettingsKeys.defaultCalendarDayRailBasePosition,
    );

/// Keys [_decodeCalendarAppearance] reads. Listed explicitly so the bulk
/// read stays O(keys): `user_settings` also holds a `note_position_<id>` row
/// per note, so a full-table read would scale with the note count on the
/// pre-first-paint path this is meant to speed up.
const List<String> _calendarAppearanceKeys = [
  SettingsKeys.calendarTodayStyle,
  SettingsKeys.calendarMarkerStyle,
  SettingsKeys.calendarWeekStart,
  SettingsKeys.calendarAccentColor,
  SettingsKeys.calendarHighlightWeekends,
  SettingsKeys.calendarShowWeekNumbers,
  SettingsKeys.calendarShowFilterChips,
  SettingsKeys.calendarMaxDayBars,
  SettingsKeys.calendarShowRecurrenceLabels,
  SettingsKeys.calendarMissedDisplay,
  SettingsKeys.calendarEventTint,
  SettingsKeys.calendarTintConflict,
  SettingsKeys.calendarCellStyleLight,
  SettingsKeys.calendarCellStyleDark,
  SettingsKeys.calendarDayRailStyle,
  SettingsKeys.calendarMaxDayRailMarks,
  SettingsKeys.calendarDayRailBasePosition,
];

CalendarAppearance _decodeCalendarAppearance(Map<String, String> values) {
  return CalendarAppearance(
    todayStyle: _decodeCalendarTodayStyle(
      values[SettingsKeys.calendarTodayStyle],
    ),
    markerStyle: _decodeCalendarMarkerStyle(
      values[SettingsKeys.calendarMarkerStyle],
    ),
    weekStart: _decodeCalendarWeekStart(values[SettingsKeys.calendarWeekStart]),
    accentColorValue: _decodeCalendarAccentColor(
      values[SettingsKeys.calendarAccentColor],
    ),
    highlightWeekends: _decodeBool(
      values[SettingsKeys.calendarHighlightWeekends],
      SettingsKeys.defaultCalendarHighlightWeekends,
    ),
    showWeekNumbers: _decodeBool(
      values[SettingsKeys.calendarShowWeekNumbers],
      SettingsKeys.defaultCalendarShowWeekNumbers,
    ),
    showFilterChips: _decodeBool(
      values[SettingsKeys.calendarShowFilterChips],
      SettingsKeys.defaultCalendarShowFilterChips,
    ),
    maxDayBars: _decodeCalendarMaxDayBars(
      values[SettingsKeys.calendarMaxDayBars],
    ),
    showRecurrenceLabels: _decodeBool(
      values[SettingsKeys.calendarShowRecurrenceLabels],
      SettingsKeys.defaultCalendarShowRecurrenceLabels,
    ),
    missedDisplay: _decodeCalendarMissedDisplay(
      values[SettingsKeys.calendarMissedDisplay],
    ),
    eventTint: _decodeBool(
      values[SettingsKeys.calendarEventTint],
      SettingsKeys.defaultCalendarEventTint,
    ),
    tintConflict: _decodeCalendarTintConflict(
      values[SettingsKeys.calendarTintConflict],
    ),
    cellStyleLight: _decodeCalendarCellStyle(
      values[SettingsKeys.calendarCellStyleLight],
      SettingsKeys.defaultCalendarCellStyleLight,
    ),
    cellStyleDark: _decodeCalendarCellStyle(
      values[SettingsKeys.calendarCellStyleDark],
      SettingsKeys.defaultCalendarCellStyleDark,
    ),
    dayRailStyle: _decodeCalendarDayRailStyle(
      values[SettingsKeys.calendarDayRailStyle],
    ),
    maxDayRailMarks: _decodeCalendarMaxDayRailMarks(
      values[SettingsKeys.calendarMaxDayRailMarks],
    ),
    dayRailBasePosition: _decodeCalendarDayRailBasePosition(
      values[SettingsKeys.calendarDayRailBasePosition],
    ),
  );
}

/// How the calendar grid is drawn: bars and markers, today, the week, the
/// accent, the tint and its cell style per theme, the day rail — and the
/// description's length limit.
mixin _CalendarAppearanceSettings on _EditorSettings {
  Future<int> getCalendarMaxDayBars() async {
    return _decodeCalendarMaxDayBars(
      await _db.userSettingsDao.getValue(SettingsKeys.calendarMaxDayBars),
    );
  }

  Future<void> setCalendarMaxDayBars(int value) async {
    await _setInt(
      SettingsKeys.calendarMaxDayBars,
      value.clamp(
        SettingsKeys.minCalendarMaxDayBars,
        SettingsKeys.maxCalendarMaxDayBars,
      ),
    );
  }

  // Calendar - character budget for an event description. Clamped on both
  // sides of the boundary so a hand-edited or future-written value can never
  // leave the editor unable to save anything.
  Future<int> getEventDescriptionLimit() async {
    final stored = await _getInt(
      SettingsKeys.eventDescriptionLimit,
      SettingsKeys.defaultEventDescriptionLimit,
    );
    return stored.clamp(
      SettingsKeys.minEventDescriptionLimit,
      SettingsKeys.maxEventDescriptionLimit,
    );
  }

  Future<void> setEventDescriptionLimit(int value) async {
    await _setInt(
      SettingsKeys.eventDescriptionLimit,
      value.clamp(
        SettingsKeys.minEventDescriptionLimit,
        SettingsKeys.maxEventDescriptionLimit,
      ),
    );
  }

  Future<CalendarTodayStyle> getCalendarTodayStyle() async {
    return _decodeCalendarTodayStyle(
      await _db.userSettingsDao.getValue(SettingsKeys.calendarTodayStyle),
    );
  }

  Future<void> setCalendarTodayStyle(CalendarTodayStyle style) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarTodayStyle,
      style.name,
    );
  }

  Future<CalendarMarkerStyle> getCalendarMarkerStyle() async {
    return _decodeCalendarMarkerStyle(
      await _db.userSettingsDao.getValue(SettingsKeys.calendarMarkerStyle),
    );
  }

  Future<void> setCalendarMarkerStyle(CalendarMarkerStyle style) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarMarkerStyle,
      style.name,
    );
  }

  Future<CalendarWeekStart> getCalendarWeekStart() async {
    return _decodeCalendarWeekStart(
      await _db.userSettingsDao.getValue(SettingsKeys.calendarWeekStart),
    );
  }

  Future<void> setCalendarWeekStart(CalendarWeekStart start) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarWeekStart,
      start.name,
    );
  }

  Future<int?> getCalendarAccentColor() async {
    return _decodeCalendarAccentColor(
      await _db.userSettingsDao.getValue(SettingsKeys.calendarAccentColor),
    );
  }

  Future<void> setCalendarAccentColor(int? color) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarAccentColor,
      color?.toString() ?? '',
    );
  }

  // Calendar appearance - tint weekend day numbers.
  Future<bool> getCalendarHighlightWeekends() async {
    return _getBool(
      SettingsKeys.calendarHighlightWeekends,
      SettingsKeys.defaultCalendarHighlightWeekends,
    );
  }

  Future<void> setCalendarHighlightWeekends(bool value) async {
    await _setBool(SettingsKeys.calendarHighlightWeekends, value);
  }

  // Calendar appearance - show ISO week numbers.
  Future<bool> getCalendarShowWeekNumbers() async {
    return _getBool(
      SettingsKeys.calendarShowWeekNumbers,
      SettingsKeys.defaultCalendarShowWeekNumbers,
    );
  }

  Future<void> setCalendarShowWeekNumbers(bool value) async {
    await _setBool(SettingsKeys.calendarShowWeekNumbers, value);
  }

  // Calendar appearance - show the active-filter chips row above the grid.
  Future<bool> getCalendarShowFilterChips() async {
    return _getBool(
      SettingsKeys.calendarShowFilterChips,
      SettingsKeys.defaultCalendarShowFilterChips,
    );
  }

  Future<void> setCalendarShowFilterChips(bool value) async {
    await _setBool(SettingsKeys.calendarShowFilterChips, value);
  }

  Future<bool> getCalendarShowRecurrenceLabels() async {
    return _getBool(
      SettingsKeys.calendarShowRecurrenceLabels,
      SettingsKeys.defaultCalendarShowRecurrenceLabels,
    );
  }

  Future<void> setCalendarShowRecurrenceLabels(bool value) async {
    await _setBool(SettingsKeys.calendarShowRecurrenceLabels, value);
  }

  Future<CalendarMissedDisplay> getCalendarMissedDisplay() async {
    return _decodeCalendarMissedDisplay(
      await _db.userSettingsDao.getValue(SettingsKeys.calendarMissedDisplay),
    );
  }

  Future<void> setCalendarMissedDisplay(CalendarMissedDisplay display) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarMissedDisplay,
      display.name,
    );
  }

  // Calendar appearance - wash day cells with their top event's color.
  Future<bool> getCalendarEventTint() async {
    return _getBool(
      SettingsKeys.calendarEventTint,
      SettingsKeys.defaultCalendarEventTint,
    );
  }

  Future<void> setCalendarEventTint(bool value) async {
    await _setBool(SettingsKeys.calendarEventTint, value);
  }

  Future<CalendarTintConflict> getCalendarTintConflict() async {
    return _decodeCalendarTintConflict(
      await _db.userSettingsDao.getValue(SettingsKeys.calendarTintConflict),
    );
  }

  Future<void> setCalendarTintConflict(CalendarTintConflict conflict) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarTintConflict,
      conflict.name,
    );
  }

  Future<CalendarCellStyle> getCalendarCellStyleLight() async {
    return _decodeCalendarCellStyle(
      await _db.userSettingsDao.getValue(SettingsKeys.calendarCellStyleLight),
      SettingsKeys.defaultCalendarCellStyleLight,
    );
  }

  Future<void> setCalendarCellStyleLight(CalendarCellStyle style) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarCellStyleLight,
      style.name,
    );
  }

  Future<CalendarCellStyle> getCalendarCellStyleDark() async {
    return _decodeCalendarCellStyle(
      await _db.userSettingsDao.getValue(SettingsKeys.calendarCellStyleDark),
      SettingsKeys.defaultCalendarCellStyleDark,
    );
  }

  Future<void> setCalendarCellStyleDark(CalendarCellStyle style) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarCellStyleDark,
      style.name,
    );
  }

  Future<DayRailStyle> getCalendarDayRailStyle() async {
    return _decodeCalendarDayRailStyle(
      await _db.userSettingsDao.getValue(SettingsKeys.calendarDayRailStyle),
    );
  }

  Future<void> setCalendarDayRailStyle(DayRailStyle style) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarDayRailStyle,
      style.name,
    );
  }

  Future<int> getCalendarMaxDayRailMarks() async {
    return _decodeCalendarMaxDayRailMarks(
      await _db.userSettingsDao.getValue(SettingsKeys.calendarMaxDayRailMarks),
    );
  }

  Future<void> setCalendarMaxDayRailMarks(int value) async {
    await _setInt(
      SettingsKeys.calendarMaxDayRailMarks,
      value.clamp(
        SettingsKeys.minCalendarMaxDayRailMarks,
        SettingsKeys.maxCalendarMaxDayRailMarks,
      ),
    );
  }

  Future<DayRailBasePosition> getCalendarDayRailBasePosition() async {
    return _decodeCalendarDayRailBasePosition(
      await _db.userSettingsDao.getValue(
        SettingsKeys.calendarDayRailBasePosition,
      ),
    );
  }

  Future<void> setCalendarDayRailBasePosition(
    DayRailBasePosition position,
  ) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarDayRailBasePosition,
      position.name,
    );
  }

  /// Loads every calendar look & feel option in one call.
  ///
  /// One statement rather than eleven: resolving this after the first frame
  /// visibly re-lays-out the grid, and eleven sequential single-row awaits are
  /// eleven round trips to the drift isolate whose latencies add rather than
  /// overlap.
  Future<CalendarAppearance> getCalendarAppearance() async {
    return _decodeCalendarAppearance(
      await _db.userSettingsDao.getValuesFor(_calendarAppearanceKeys),
    );
  }
}
