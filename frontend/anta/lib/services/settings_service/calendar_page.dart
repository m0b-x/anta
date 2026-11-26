part of '../settings_service.dart';

const List<String> _calendarPageKeys = [
  ..._calendarAppearanceKeys,
  ..._alertKeys,
  SettingsKeys.calendarGridFilters,
  SettingsKeys.markdownCustomColors,
  SettingsKeys.calendarFastingTraditions,
  SettingsKeys.calendarFastingAppearance,
  SettingsKeys.calendarFastingStyle,
  SettingsKeys.calendarFastingOrthodoxGreatFasts,
  SettingsKeys.calendarFastingSchedule,
  SettingsKeys.calendarFastingWeekdays,
  SettingsKeys.shareEventLook,
  SettingsKeys.shareMarkMine,
  SettingsKeys.shareAlerts,
];

/// What the calendar page was left showing — the agenda's filters, the panel
/// and day-list modes, the grid's filters — the bundle the page opens with,
/// and the colours the pickers remember.
mixin _CalendarPageSettings on _CalendarAppearanceSettings {
  /// Loads every upcoming-agenda filter in one call.
  Future<UpcomingAgendaFilters> getUpcomingAgendaFilters() async {
    final rangeDays = await _getInt(
      SettingsKeys.calendarUpcomingRangeDays,
      SettingsKeys.defaultCalendarUpcomingRangeDays,
    );
    final (customStart, customEnd) = UpcomingAgendaFilters.decodeRange(
      await _db.userSettingsDao.getValue(
            SettingsKeys.calendarUpcomingCustomRange,
          ) ??
          '',
    );
    return UpcomingAgendaFilters(
      periodMode: AgendaPeriodMode.fromName(
        await _db.userSettingsDao.getValue(
          SettingsKeys.calendarUpcomingPeriodMode,
        ),
      ),
      rangeDays: rangeDays,
      priorities: await _readUpcomingPriorities(),
      customStart: customStart,
      customEnd: customEnd,
      query:
          await _db.userSettingsDao.getValue(
            SettingsKeys.calendarUpcomingQuery,
          ) ??
          '',
      showHolidays: await _getBool(
        SettingsKeys.calendarUpcomingShowHolidays,
        SettingsKeys.defaultCalendarUpcomingShowHolidays,
      ),
      showFasting: await _getBool(
        SettingsKeys.calendarUpcomingShowFasting,
        SettingsKeys.defaultCalendarUpcomingShowFasting,
      ),
      eventDisplay: await _readUpcomingEventDisplay(),
      fastingDisplay: await _readUpcomingFastingDisplay(),
      holidayDisplay: AgendaHolidayDisplay.fromName(
        await _db.userSettingsDao.getValue(
              SettingsKeys.calendarUpcomingHolidayDisplay,
            ) ??
            SettingsKeys.defaultCalendarUpcomingHolidayDisplay,
      ),
      followSelectedDay: await _getBool(
        SettingsKeys.calendarUpcomingFollowSelectedDay,
        SettingsKeys.defaultCalendarUpcomingFollowSelectedDay,
      ),
      eventType: AgendaEventType.fromName(
        await _db.userSettingsDao.getValue(
          SettingsKeys.calendarUpcomingEventType,
        ),
      ),
      categoryIds: await _readUpcomingCategoryIds(),
    );
  }

  /// Reads the priority set. The superseded single-threshold key is folded
  /// into this one (values flipped to the 1-is-highest scale) by the v18
  /// database migration, so no legacy fallback is needed here.
  Future<Set<int>> _readUpcomingPriorities() async {
    final raw = await _db.userSettingsDao.getValue(
      SettingsKeys.calendarUpcomingPriorities,
    );
    if (raw == null) return const {};
    return UpcomingAgendaFilters.decodePriorities(raw);
  }

  /// Reads the event presentation, falling back to the superseded
  /// `collapse_recurring` boolean when the new key has never been written
  /// (`true` was one row per event, `false` one row per occurrence). A
  /// read-time fallback rather than a migration pass, exactly like
  /// [_readUpcomingFastingDisplay].
  Future<AgendaEventDisplay> _readUpcomingEventDisplay() async {
    final raw = await _db.userSettingsDao.getValue(
      SettingsKeys.calendarUpcomingEventDisplay,
    );
    if (raw != null) return AgendaEventDisplay.fromName(raw);
    final legacy = await _db.userSettingsDao.getValue(
      SettingsKeys.calendarUpcomingCollapseRecurring,
    );
    if (legacy == null) {
      return AgendaEventDisplay.fromName(
        SettingsKeys.defaultCalendarUpcomingEventDisplay,
      );
    }
    return legacy == 'true'
        ? AgendaEventDisplay.perEvent
        : AgendaEventDisplay.everyOccurrence;
  }

  /// Reads the fasting presentation, falling back to the superseded
  /// `collapse_fasting` boolean when the new key has never been written
  /// (`true` was one row per period, `false` one row per day). A read-time
  /// fallback rather than a migration pass, exactly like the schedule's
  /// legacy weekday CSV — so nobody's configuration resets on update.
  Future<AgendaFastingDisplay> _readUpcomingFastingDisplay() async {
    final raw = await _db.userSettingsDao.getValue(
      SettingsKeys.calendarUpcomingFastingDisplay,
    );
    if (raw != null) return AgendaFastingDisplay.fromName(raw);
    final legacy = await _db.userSettingsDao.getValue(
      SettingsKeys.calendarUpcomingCollapseFasting,
    );
    if (legacy == null) {
      return AgendaFastingDisplay.fromName(
        SettingsKeys.defaultCalendarUpcomingFastingDisplay,
      );
    }
    return legacy == 'true'
        ? AgendaFastingDisplay.periods
        : AgendaFastingDisplay.everyDay;
  }

  Future<Set<String>> _readUpcomingCategoryIds() async {
    final raw = await _db.userSettingsDao.getValue(
      SettingsKeys.calendarUpcomingCategories,
    );
    if (raw == null) return const {};
    return UpcomingAgendaFilters.decodeCategories(raw);
  }

  /// Persists every upcoming-agenda filter in **one transaction**. Callers
  /// debounce the text query themselves and fire this without awaiting, so
  /// two saves in flight must not interleave key by key: thirteen sequential
  /// writes could leave a restart with half of each.
  Future<void> saveUpcomingAgendaFilters(UpcomingAgendaFilters filters) async {
    await _db.userSettingsDao.setValues({
      SettingsKeys.calendarUpcomingPeriodMode: filters.periodMode.name,
      SettingsKeys.calendarUpcomingRangeDays: filters.rangeDays.toString(),
      SettingsKeys.calendarUpcomingPriorities:
          UpcomingAgendaFilters.encodePriorities(filters.priorities),
      SettingsKeys.calendarUpcomingCustomRange:
          UpcomingAgendaFilters.encodeRange(
            filters.customStart,
            filters.customEnd,
          ),
      SettingsKeys.calendarUpcomingQuery: filters.query,
      SettingsKeys.calendarUpcomingShowHolidays: filters.showHolidays
          .toString(),
      SettingsKeys.calendarUpcomingShowFasting: filters.showFasting.toString(),
      SettingsKeys.calendarUpcomingEventDisplay: filters.eventDisplay.name,
      SettingsKeys.calendarUpcomingFastingDisplay: filters.fastingDisplay.name,
      SettingsKeys.calendarUpcomingHolidayDisplay: filters.holidayDisplay.name,
      SettingsKeys.calendarUpcomingFollowSelectedDay: filters.followSelectedDay
          .toString(),
      SettingsKeys.calendarUpcomingEventType: filters.eventType.name,
      SettingsKeys.calendarUpcomingCategories:
          UpcomingAgendaFilters.encodeCategories(filters.categoryIds),
    });
  }

  // Calendar - Which mode the bottom panel was left in.
  Future<CalendarPanelMode> getCalendarPanelMode() async {
    final raw = await _db.userSettingsDao.getValue(
      SettingsKeys.calendarPanelMode,
    );
    return CalendarPanelMode.fromName(
      raw ?? SettingsKeys.defaultCalendarPanelMode,
    );
  }

  Future<void> setCalendarPanelMode(CalendarPanelMode mode) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarPanelMode,
      mode.name,
    );
  }

  // Calendar - Which presentation the agenda drill-down sheet was left in.
  Future<AgendaDayListMode> getAgendaDayListMode() async {
    final raw = await _db.userSettingsDao.getValue(
      SettingsKeys.calendarDayListMode,
    );
    return AgendaDayListMode.fromName(
      raw ?? SettingsKeys.defaultCalendarDayListMode,
    );
  }

  Future<void> setAgendaDayListMode(AgendaDayListMode mode) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarDayListMode,
      mode.name,
    );
  }

  /// Every setting `CalendarPage` needs before it can paint, in one statement.
  ///
  /// `initState` previously issued 16-18 sequential single-row SELECTs here.
  /// The decoders are the same ones the individual getters use, so the bulk
  /// path cannot drift from them.
  Future<
    ({
      CalendarAppearance appearance,
      CalendarGridFilters filters,
      MarkdownColorPalette palette,
      Set<FastingTradition> fastingTraditions,
      FastingAppearance fastingAppearance,
      bool fastingGreatFasts,
      FastingSchedule fastingSchedule,
      AlertSettings alerts,
      ShareLook share,
    })
  >
  getCalendarPageSettings() async {
    final values = await _db.userSettingsDao.getValuesFor(_calendarPageKeys);
    // The badges the page draws answer by it, as by the alert defaults.
    EventAlerts.configureShareAlerts(
      _decodeShareAlerts(values[SettingsKeys.shareAlerts]),
    );
    return (
      appearance: _decodeCalendarAppearance(values),
      filters: CalendarGridFilters.decode(
        values[SettingsKeys.calendarGridFilters],
      ),
      palette: _decodeColorPalette(values[SettingsKeys.markdownCustomColors]),
      fastingTraditions: _decodeFastingTraditions(
        values[SettingsKeys.calendarFastingTraditions],
      ),
      fastingAppearance: _decodeFastingAppearance(
        values[SettingsKeys.calendarFastingAppearance],
        values[SettingsKeys.calendarFastingStyle],
      ),
      fastingGreatFasts: _decodeBool(
        values[SettingsKeys.calendarFastingOrthodoxGreatFasts],
        true,
      ),
      fastingSchedule: _decodeFastingSchedule(
        values[SettingsKeys.calendarFastingSchedule],
        values[SettingsKeys.calendarFastingWeekdays],
      ),
      alerts: _publishAlertDefaults(_decodeAlertSettings(values)),
      share: _decodeShareLook(values),
    );
  }

  /// Persists the calendar grid's filter set.
  ///
  /// Deletes the row outright when nothing is set rather than storing `{}`, so
  /// "never filtered" and "filtered then cleared" leave the same absence
  /// behind and the decoder has one less shape to understand.
  Future<void> setCalendarGridFilters(CalendarGridFilters filters) async {
    final encoded = filters.encode();
    if (encoded.isEmpty) {
      await _db.userSettingsDao.deleteValue(SettingsKeys.calendarGridFilters);
      return;
    }
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarGridFilters,
      encoded,
    );
  }

  /// The stored filter set on its own, for callers outside the page's bulk
  /// read. Shares [CalendarGridFilters.decode] with the bulk path, so the two
  /// cannot drift.
  Future<CalendarGridFilters> getCalendarGridFilters() async {
    return CalendarGridFilters.decode(
      await _db.userSettingsDao.getValue(SettingsKeys.calendarGridFilters),
    );
  }

  // Calendar - Recently used custom event colors (most-recent-first, capped).
  Future<List<int>> getRecentEventColors() async {
    final raw = await _db.userSettingsDao.getValue(
      SettingsKeys.recentEventColors,
    );
    if (raw == null || raw.isEmpty) return const [];
    return raw.split(',').map(int.tryParse).whereType<int>().toList();
  }

  /// Drops the retired recent-colors row once `CalendarPaletteService` has
  /// folded it into the permanent palette, so the fold runs exactly once.
  Future<void> clearRecentEventColors() async {
    await _db.userSettingsDao.setValue(SettingsKeys.recentEventColors, '');
  }

  // Colour picker - which geometry the custom-colour sheet opens with.
  Future<ColorPickerMode> getColorPickerMode() async {
    final raw = await _db.userSettingsDao.getValue(
      SettingsKeys.colorPickerMode,
    );
    return ColorPickerMode.fromName(raw ?? SettingsKeys.defaultColorPickerMode);
  }

  Future<void> setColorPickerMode(ColorPickerMode mode) async {
    await _db.userSettingsDao.setValue(SettingsKeys.colorPickerMode, mode.name);
  }

  // Calendar - The user's own swatches, appended to the built-in palette.
  Future<List<int>> getCustomCalendarColors() async {
    final raw = await _db.userSettingsDao.getValue(
      SettingsKeys.calendarCustomColors,
    );
    if (raw == null || raw.isEmpty) return const [];
    return raw.split(',').map(int.tryParse).whereType<int>().toList();
  }

  /// Replaces the whole custom set. The service owns ordering, dedup and the
  /// cap; this is the raw write it commits through.
  Future<void> setCustomCalendarColors(List<int> colors) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarCustomColors,
      colors.join(','),
    );
  }
}
