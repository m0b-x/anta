part of '../settings_service.dart';

const List<String> _calendarOverviewKeys = [
  ..._calendarAppearanceKeys,
  SettingsKeys.calendarOverviewCategories,
  SettingsKeys.calendarOverviewMode,
  SettingsKeys.calendarOverviewPeriod,
  SettingsKeys.calendarOverviewOrder,
  SettingsKeys.calendarOverviewRows,
  SettingsKeys.hapticFeedback,
  SettingsKeys.markdownCustomColors,
  SettingsKeys.shareEventLook,
  SettingsKeys.shareMarkMine,
];

const List<String> _calendarReportKeys = [
  ..._calendarAppearanceKeys,
  SettingsKeys.reportPeriod,
  SettingsKeys.reportCategoryIds,
  SettingsKeys.reportCards,
  SettingsKeys.hapticFeedback,
  SettingsKeys.markdownCustomColors,
  SettingsKeys.moneyCurrencySymbol,
  SettingsKeys.moneyCurrencySuffix,
];

/// [OverviewPeriod.decode] with the report's own default, This month: that
/// decoder falls back to this year for an absent or unknown value, and the
/// report has no All time (D18), so either reads as this month here.
OverviewPeriod _decodeReportPeriod(
  String? raw, {
  required DateTime today,
  required CalendarWeekStart weekStart,
}) {
  final fallback = OverviewPeriod.thisMonth(today: today);
  if (raw == null) return fallback;
  final period = OverviewPeriod.decode(raw, today: today, weekStart: weekStart);
  return switch (period) {
    OverviewRollingPeriod(preset: OverviewRollingPreset.allTime) => fallback,
    OverviewYearPeriod() when period.encode(today: today) != raw => fallback,
    _ => period,
  };
}

// Calendar settings page - which sections are folded shut.
Set<String> _decodeCollapsedSections(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  final ids = <String>{};
  for (final part in raw.split(',')) {
    final id = part.trim();
    if (id.isNotEmpty) ids.add(id);
  }
  return ids;
}

/// The overview's and the report's own choices — categories, mode, period,
/// cards, list options — with the recent icons and the settings pages'
/// folded sections.
mixin _OverviewAndReportSettings on _CalendarPageSettings {
  /// Everything the calendar overview page needs before it can paint, in one
  /// statement — the appearance through the same decoder the calendar page
  /// uses, the page's own settings, the haptic switch its jumps obey, the
  /// palette its detail sheets render descriptions in, and how a partner's
  /// events are drawn. [today] (date-only, defaulting to the wall clock's)
  /// is what a stored `thisYear` means.
  Future<
    ({
      CalendarAppearance appearance,
      MarkdownColorPalette palette,
      Set<String> categoryIds,
      AgendaDayListMode mode,
      OverviewPeriod period,
      OverviewListOptions listOptions,
      bool hapticFeedback,
      ShareLook share,
    })
  >
  getCalendarOverviewSettings({DateTime? today}) async {
    final values = await _db.userSettingsDao.getValuesFor(
      _calendarOverviewKeys,
    );
    return (
      appearance: _decodeCalendarAppearance(values),
      palette: _decodeColorPalette(values[SettingsKeys.markdownCustomColors]),
      categoryIds: UpcomingAgendaFilters.decodeCategories(
        values[SettingsKeys.calendarOverviewCategories] ?? '',
      ),
      mode: AgendaDayListMode.fromName(
        values[SettingsKeys.calendarOverviewMode] ??
            SettingsKeys.defaultCalendarOverviewMode,
      ),
      period: OverviewPeriod.decode(
        values[SettingsKeys.calendarOverviewPeriod],
        today: today ?? DateTime.now(),
        weekStart: _decodeCalendarWeekStart(
          values[SettingsKeys.calendarWeekStart],
        ),
      ),
      // Missed only is session-only by decision, so it always opens off.
      listOptions: OverviewListOptions(
        order: OverviewOrder.fromName(
          values[SettingsKeys.calendarOverviewOrder] ??
              SettingsKeys.defaultCalendarOverviewOrder,
        ),
        rows: OverviewRows.fromName(
          values[SettingsKeys.calendarOverviewRows] ??
              SettingsKeys.defaultCalendarOverviewRows,
        ),
      ),
      hapticFeedback: _decodeBool(
        values[SettingsKeys.hapticFeedback],
        SettingsKeys.defaultHapticFeedback,
      ),
      share: _decodeShareLook(values),
    );
  }

  Future<void> setCalendarOverviewCategories(Set<String> ids) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarOverviewCategories,
      UpcomingAgendaFilters.encodeCategories(ids),
    );
  }

  Future<void> setCalendarOverviewMode(AgendaDayListMode mode) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarOverviewMode,
      mode.name,
    );
  }

  /// Stores [period] as [OverviewPeriod.encode] spells it, or clears the key
  /// for a period that is not kept (a custom span, a past year), so the next
  /// launch opens on this year rather than on a look that has gone stale.
  Future<void> setCalendarOverviewPeriod(
    OverviewPeriod period, {
    DateTime? today,
  }) async {
    final encoded = period.encode(today: today ?? DateTime.now());
    if (encoded == null) {
      await _db.userSettingsDao.deleteValue(
        SettingsKeys.calendarOverviewPeriod,
      );
    } else {
      await _db.userSettingsDao.setValue(
        SettingsKeys.calendarOverviewPeriod,
        encoded,
      );
    }
  }

  /// What the calendar report remembers (D35), in one statement: its period,
  /// its allowlist, its cards (W) and the calendar's appearance — whose week
  /// start This week and the trend's columns follow, and which the range
  /// picker draws its grid in — with the palette a row's detail sheet
  /// renders the description in, the haptic switch a presence mark obeys and
  /// the ledger's global currency, which the report's amounts are written in
  /// (a note's own currency is not the report's: its sums cross notes).
  /// [today] (date-only) is what a stored `thisWeek` or `thisMonth` means.
  Future<
    ({
      OverviewPeriod period,
      Set<String> categoryIds,
      ReportCards cards,
      CalendarAppearance appearance,
      MarkdownColorPalette palette,
      bool hapticFeedback,
      String currencySymbol,
      bool currencySuffix,
    })
  >
  getCalendarReportSettings({required DateTime today}) async {
    final values = await _db.userSettingsDao.getValuesFor(_calendarReportKeys);
    final appearance = _decodeCalendarAppearance(values);
    return (
      period: _decodeReportPeriod(
        values[SettingsKeys.reportPeriod],
        today: today,
        weekStart: appearance.weekStart,
      ),
      categoryIds: UpcomingAgendaFilters.decodeCategories(
        values[SettingsKeys.reportCategoryIds] ?? '',
      ),
      cards: ReportCards.decode(values[SettingsKeys.reportCards]),
      appearance: appearance,
      palette: _decodeColorPalette(values[SettingsKeys.markdownCustomColors]),
      hapticFeedback: _decodeBool(
        values[SettingsKeys.hapticFeedback],
        SettingsKeys.defaultHapticFeedback,
      ),
      currencySymbol:
          values[SettingsKeys.moneyCurrencySymbol] ??
          SettingsKeys.defaultMoneyCurrencySymbol,
      currencySuffix: _decodeBool(
        values[SettingsKeys.moneyCurrencySuffix],
        SettingsKeys.defaultMoneyCurrencySuffix,
      ),
    );
  }

  /// Stores [period] as [OverviewPeriod.encode] spells it, or clears the key
  /// for a span that is not kept, so the report reopens on This month rather
  /// than on a look that has gone stale.
  Future<void> setCalendarReportPeriod(
    OverviewPeriod period, {
    required DateTime today,
  }) async {
    final encoded = period.encode(today: today);
    if (encoded == null) {
      await _db.userSettingsDao.deleteValue(SettingsKeys.reportPeriod);
    } else {
      await _db.userSettingsDao.setValue(SettingsKeys.reportPeriod, encoded);
    }
  }

  Future<void> setCalendarReportCategories(Set<String> ids) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.reportCategoryIds,
      UpcomingAgendaFilters.encodeCategories(ids),
    );
  }

  /// Stores [cards] in [ReportCards.encode]'s grammar, or clears the key
  /// when they are the defaults, so a card a later version adds lands in
  /// its own place for an owner who never reordered.
  Future<void> setReportCards(ReportCards cards) async {
    if (cards == ReportCards.defaults) {
      await _db.userSettingsDao.deleteValue(SettingsKeys.reportCards);
    } else {
      await _db.userSettingsDao.setValue(
        SettingsKeys.reportCards,
        cards.encode(),
      );
    }
  }

  /// Stores the order and the rows in one batch; Missed only is never
  /// persisted.
  Future<void> setCalendarOverviewListOptions(
    OverviewListOptions options,
  ) async {
    await _db.userSettingsDao.setValues({
      SettingsKeys.calendarOverviewOrder: options.order.name,
      SettingsKeys.calendarOverviewRows: options.rows.name,
    });
  }

  /// The icon keys picked most recently, newest first.
  ///
  /// **Unknown keys are dropped on read**, the forward-compatible parsing
  /// every calendar setting uses: icon keys are additive-only but an icon may
  /// be *retired* from the catalog, and a retired key must leave this list
  /// rather than render an empty tile. Duplicates are collapsed for the same
  /// reason the writer de-duplicates — a list written by an older build is
  /// still input.
  Future<List<String>> getRecentIconKeys() async {
    final raw = await _db.userSettingsDao.getValue(SettingsKeys.recentIconKeys);
    if (raw == null || raw.isEmpty) return const [];
    final keys = <String>[];
    final seen = <String>{};
    for (final part in raw.split(',')) {
      final key = part.trim();
      if (key.isEmpty || !seen.add(key)) continue;
      if (CalendarIcons.forKey(key) == null) continue;
      keys.add(key);
      if (keys.length == SettingsService.recentIconLimit) break;
    }
    return keys;
  }

  /// Moves [key] to the front of the recent list, capped at
  /// [SettingsService.recentIconLimit]. Re-picking an icon promotes it rather than adding a
  /// second copy.
  Future<void> recordRecentIconKey(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return;
    final current = await getRecentIconKeys();
    final next = <String>[
      trimmed,
      for (final existing in current)
        if (existing != trimmed) existing,
    ];
    if (next.length > SettingsService.recentIconLimit) {
      next.removeRange(SettingsService.recentIconLimit, next.length);
    }
    await _db.userSettingsDao.setValue(
      SettingsKeys.recentIconKeys,
      next.join(','),
    );
  }

  Future<Set<String>> getCalendarSettingsCollapsedSections() async {
    return _decodeCollapsedSections(
      await _db.userSettingsDao.getValue(
        SettingsKeys.calendarSettingsCollapsedSections,
      ),
    );
  }

  Future<void> setCalendarSettingsCollapsedSections(Set<String> ids) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.calendarSettingsCollapsedSections,
      ids.join(','),
    );
  }

  /// The tail of the fold edits, so each one reads the set the previous one
  /// wrote.
  Future<void> _collapsedSectionEdits = Future<void>.value();

  /// Folds or unfolds [id] in the stored set and returns the set written.
  ///
  /// Four pages share the one row, each holding its own copy of it; a page
  /// that wrote its copy back would drop the folds a child page stored since
  /// that copy was read (a toggle landing before `didPopNext`'s reload). The
  /// edit reads the row instead, and the edits run one after another so two
  /// pages cannot interleave a read and a write.
  Future<Set<String>> setCalendarSettingsSectionCollapsed(
    String id, {
    required bool collapsed,
  }) {
    final edit = _collapsedSectionEdits.then((_) async {
      final ids = {...await getCalendarSettingsCollapsedSections()};
      if (collapsed) {
        ids.add(id);
      } else {
        ids.remove(id);
      }
      await setCalendarSettingsCollapsedSections(ids);
      return ids;
    });
    _collapsedSectionEdits = edit.then<void>((_) {}, onError: (_) {});
    return edit;
  }

  Future<Set<String>> getAppSettingsCollapsedSections() async {
    return _decodeCollapsedSections(
      await _db.userSettingsDao.getValue(
        SettingsKeys.appSettingsCollapsedSections,
      ),
    );
  }

  Future<void> setAppSettingsCollapsedSections(Set<String> ids) async {
    await _db.userSettingsDao.setValue(
      SettingsKeys.appSettingsCollapsedSections,
      ids.join(','),
    );
  }
}
