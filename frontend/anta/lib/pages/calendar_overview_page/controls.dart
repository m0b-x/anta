part of '../calendar_overview_page.dart';

/// What narrows the page and where each choice is kept: the search, the
/// period and its steps, the list options, the categories and the saved
/// views.
mixin _OverviewControls on _OverviewNavigation {
  /// Typing waits out the debounce; clearing applies at once, as the clear
  /// button promises.
  void _onQueryChanged(String raw) {
    _searchDebounce?.cancel();
    _unappliedQuery = raw;
    if (raw.isEmpty) {
      _applyQuery(raw);
      return;
    }
    _searchDebounce = Timer(
      OverviewListMetrics.searchDebounce,
      () => _applyQuery(raw),
    );
  }

  /// A query that parses to the one applied changes nothing — a trailing
  /// space, a letter's case.
  void _applyQuery(String raw) {
    if (!mounted) return;
    final previous = _query;
    _setQuery(raw);
    if (_query == previous) return;
    _rebuild();
    _land();
  }

  void _setQuery(String raw) {
    _unappliedQuery = null;
    _query = EventSearchQuery.parse(raw, localeName: _l10n?.localeName ?? '');
  }

  /// The Period menu's pick, live in every mode (D13 · A). A preset applies at
  /// once; Custom range… asks the Dates sheet for a span, seeded with the one
  /// shown, and changes nothing — the mode included — when it is cancelled.
  /// A period is the list's unit, so a pick outside the list opens the list
  /// on it; This year in year mode only pages to this year, which the tiles
  /// already show as a period.
  Future<void> _selectPeriod(OverviewPeriodChoice choice) async {
    final OverviewPeriod period;
    if (choice != OverviewPeriodChoice.custom) {
      period = OverviewPeriod.fromChoice(
        choice,
        today: _today,
        weekStart: _appearance.weekStart,
      );
    } else {
      final picked = await _pickRange();
      if (picked == null) return;
      period = picked;
    }
    final keepsMode =
        _mode == AgendaDayListMode.list ||
        (_mode == AgendaDayListMode.year &&
            choice == OverviewPeriodChoice.thisYear);
    if (keepsMode) {
      _setPeriod(period);
    } else {
      _listPeriod(period);
    }
  }

  /// The Dates sheet's range mode, seeded with the span shown; null when it
  /// is cancelled, already open, or the page has gone.
  Future<OverviewCustomPeriod?> _pickRange() async {
    if (_pickerOpen) return null;
    _pickerOpen = true;
    try {
      _blur();
      final picked = await CalendarDatePickerSheet.pickRange(
        context,
        initialRange: _shownPeriod.resolve(today: _today, yearBounds: _years),
        firstDate: DateTime.utc(_years.first, 1, 1),
        lastDate: DateTime.utc(_years.last, 12, 31),
        appearance: _appearance,
      );
      if (picked == null || !mounted) return null;
      return OverviewCustomPeriod(picked.start, picked.end);
    } finally {
      _pickerOpen = false;
    }
  }

  /// The nav's title in every mode (D19 · A): the Period menu, anchored to
  /// the title, its pick taken as [_selectPeriod] takes any.
  Future<void> _openPeriodMenu(BuildContext anchor) async {
    final l10n = AppLocalizations.of(context)!;
    _blur();
    final choice = await showFormMenu<OverviewPeriodChoice>(
      anchor,
      items: [
        for (final choice in OverviewPeriodChoice.values)
          FormMenuItem(
            value: choice,
            label: _periodLabel(l10n, choice),
            icon: _periodIcon(choice),
            identifier: _periodId(choice),
          ),
      ],
      selected: _shownPeriod.menuChoice(today: _today),
      menuWidth: FormMetrics.menuWidth,
      alignment: FormMenuAlignment.center,
    );
    if (choice == null || !mounted) return;
    await _selectPeriod(choice);
  }

  /// The list nav's neighbour of [_period] one step [direction] away, or
  /// null where its chevron is disabled.
  OverviewPeriod? _steppedPeriod(int direction) =>
      _period.stepped(direction: direction, today: _today, yearBounds: _years);

  /// A chevron of the list nav (D15a): a look at the neighbouring span,
  /// never persisted and never the home (D15c), landing as a pick does. A
  /// step back onto the home's own span is the home again (review 5), so the
  /// Period menu checks the preset, Today disables and a saved view matches.
  void _step(int direction) {
    final stepped = _steppedPeriod(direction);
    if (stepped == null) return;
    final home = _home.resolve(today: _today, yearBounds: _years);
    final span = stepped.resolve(today: _today, yearBounds: _years);
    final period = span == home ? _home : stepped;
    _click();
    setState(() {
      _period = period;
      _year = _firstYearOf(period);
      _recompute();
    });
    _land();
  }

  /// The list nav's Today slot (D15b): back to the period as picked.
  void _goHome() {
    _click();
    setState(() {
      _period = _home;
      _year = _firstYearOf(_home);
      _recompute();
    });
    _land();
  }

  /// Turns the page to the list on [period] in one rebuild and one landing —
  /// [_selectMode] then [_setPeriod] would resolve and land twice — and keeps
  /// both the mode and the period for the next visit.
  void _listPeriod(OverviewPeriod period) {
    setState(() {
      _mode = AgendaDayListMode.list;
      _cameFromYear = false;
      _period = _home = period;
      _year = _firstYearOf(period);
      _selectedDay = null;
      _recompute();
    });
    _land();
    unawaited(_persistMode(AgendaDayListMode.list));
    unawaited(_persistPeriod(period));
  }

  /// Lists [period], landing per D7, and persists it — a preset is kept for
  /// the next visit, a custom span clears what was kept. Year mode jumps to the
  /// period's first year, resolved before the frame; the jump lands on the
  /// year already set, so the scroll's report of it leaves the period alone.
  /// A pick of the period already shown is still persisted: scrolling the
  /// years changes the period without writing it, so "This year" picked
  /// after scrolling back to this year is a choice the next visit must see
  /// (review 1).
  void _setPeriod(OverviewPeriod period) {
    _home = period;
    if (period == _period) {
      // The Today slot reads the home, which may just have moved.
      setState(() {});
      // The years' scroll sets the period from the year at its top, so it can
      // sit well inside the section the pick names: the pick still has to
      // bring that year's header back up, or nothing on the page does.
      if (_mode == AgendaDayListMode.year) {
        _yearScroll.jumpToYear(_firstYearOf(period));
      }
      unawaited(_persistPeriod(period));
      return;
    }
    final inYear = _mode == AgendaDayListMode.year;
    setState(() {
      _period = period;
      _year = _firstYearOf(period);
      if (inYear) _resolveYear(_year);
      _recompute();
    });
    if (inYear) _yearScroll.jumpToYear(_year);
    _land();
    unawaited(_persistPeriod(period));
  }

  Future<void> _persistPeriod(OverviewPeriod period) async {
    final settings = await SettingsService.getInstance();
    await settings.setCalendarOverviewPeriod(period, today: _today);
  }

  /// What the title's Period menu checks: the year of the page in Year and
  /// Month mode — a span stepped to in the list is no period of a month's
  /// nav — and the list's period in List mode.
  OverviewPeriod get _shownPeriod => switch (_mode) {
    AgendaDayListMode.year => OverviewYearPeriod(_year),
    AgendaDayListMode.month => OverviewYearPeriod(_month.year),
    AgendaDayListMode.list => _period,
  };

  void _openOptions() {
    _blur();
    unawaited(
      OverviewOptionsSheet.show(
        context,
        initial: _options,
        mode: _mode,
        onChanged: _setOptions,
        categoryIds: _categoryIds,
        onCategoriesChanged: _onCategoriesChanged,
        partnerLook: _partnerLook,
      ),
    );
  }

  /// The options sheet's live writes. Order and Rows re-present the list and
  /// land it anew (D7); Missed only narrows the rows shown and keeps the list
  /// on its row. Order and Rows are kept for the next visit; Missed only is
  /// not.
  void _setOptions(OverviewListOptions next) {
    if (!mounted) return;
    final previous = _options;
    final represented =
        next.order != previous.order || next.rows != previous.rows;
    final anchor = represented ? null : _anchorOfList();
    setState(() {
      _options = next;
      _recompute();
    });
    if (represented) {
      _land();
      unawaited(_persistOptions(next));
    } else if (anchor != null) {
      _aimList(anchor);
    }
  }

  Future<void> _persistOptions(OverviewListOptions options) async {
    final settings = await SettingsService.getInstance();
    await settings.setCalendarOverviewListOptions(options);
  }

  /// The options sheet's Categories row (D22 · A): a new allowlist, already
  /// collapsed to empty when it covers every offered category.
  void _onCategoriesChanged(Set<String> next) {
    if (!mounted) return;
    _categoryIds = next;
    _categoryRevision = null;
    _refreshCategoryLabels();
    _storeStale = true;
    _rebuild();
    unawaited(_persistCategories(next));
  }

  /// The saved views sheet over the list as shown — year mode's year is the
  /// period there, as the Period menu reads it. Rebuilt on return so the bar
  /// button follows a save, a rename or a delete made inside.
  Future<void> _openViews() async {
    _blur();
    // A page left open across midnight would save and update through
    // yesterday's clock — This year stored as last year's number, since the
    // period the sheet writes is the one this page is holding. The resume
    // path's refresh, taken again at the press.
    if (_refreshToday()) {
      _storeStale = true;
      _rebuild();
    }
    await OverviewViewSheet.show(
      context,
      current: OverviewView(
        id: '',
        name: '',
        period: _shownPeriod,
        options: _options,
        categoryIds: _categoryIds,
      ),
      today: _today,
      weekStart: _appearance.weekStart,
      onApply: _applyView,
    );
    // A save, a rename or a delete inside changes what the list matches.
    if (mounted) setState(_foldNav);
  }

  /// Applies [view] as the picks it holds would (D17c · A): the list on its
  /// period — which becomes the nav's home — with its options and its
  /// allowlist, each persisted as its own pick persists, a custom span
  /// clearing the period key per D4. The query stays as typed.
  void _applyView(OverviewView view) {
    if (!mounted) return;
    _listLook(
      period: view.periodOn(today: _today, weekStart: _appearance.weekStart),
      categoryIds: view.categoryIds,
      options: view.options,
    );
  }

  /// Serves — and clears — the look a digest's tap published through
  /// `AppNavigator.toCalendarOverviewLook` (D13): the list on its span with
  /// its allowlist. The allowlist and the mode persist as picks; the span is
  /// a look and writes nothing, so a period the user kept survives the tap.
  ///
  /// Held until the settings are in — their period and allowlist would
  /// otherwise land over the look — and served by the one overview the
  /// navigator collapsed onto or pushed.
  void _serveOverviewLook() {
    if (!mounted || !_settingsLoaded) return;
    final look = AppNavigator.pendingOverviewLook.value;
    if (look == null) return;
    final route = ModalRoute.of(context);
    if (route != null && !AppNavigator.servesOverviewLook(route)) return;
    // Cleared before it is acted on, so a page mounting later cannot replay
    // a trip already made.
    AppNavigator.pendingOverviewLook.value = null;
    _listLook(
      period: OverviewCustomPeriod(look.start, look.end),
      categoryIds: look.categoryIds,
    );
  }

  /// Turns the page to the list on [period] over [categoryIds] in one
  /// rebuild and one landing — the shared body of a saved view and a digest's
  /// look.
  ///
  /// With [options] it is a view, applied as its picks would be: the options
  /// taken, and the period persisted too, a custom span clearing its key per
  /// D4. Without, it is a look: it lands on exactly what the digest counted,
  /// so a typed query and Missed only — both session-only — are dropped, while
  /// Order and Rows stay the user's and the period key is left alone.
  void _listLook({
    required OverviewPeriod period,
    required Set<String> categoryIds,
    OverviewListOptions? options,
  }) {
    final isView = options != null;
    final next = options ?? _options.copyWith(missedOnly: false);
    final queryDropped =
        !isView && (_query.isNotEmpty || _searchController.text.isNotEmpty);
    if (queryDropped) {
      _searchDebounce?.cancel();
      _searchController.clear();
      _setQuery('');
    }
    final categoriesChanged = !setEquals(categoryIds, _categoryIds);
    setState(() {
      _mode = AgendaDayListMode.list;
      _cameFromYear = false;
      _period = _home = period;
      _year = _firstYearOf(period);
      _selectedDay = null;
      _options = next;
      if (categoriesChanged) {
        _categoryIds = categoryIds;
        _categoryRevision = null;
        _refreshCategoryLabels();
        _storeStale = true;
      } else {
        _recompute();
      }
    });
    // The allowlist is an input of the scan, so a new one rebuilds the store
    // as a category pick does, and a dropped query refilters as a cleared
    // field does; the landing below then wins over its anchor.
    if (categoriesChanged || queryDropped) _rebuild();
    _land();
    unawaited(_persistMode(AgendaDayListMode.list));
    if (options != null) {
      unawaited(_persistPeriod(period));
      unawaited(_persistOptions(options));
    }
    if (categoriesChanged) unawaited(_persistCategories(categoryIds));
  }

  Future<void> _persistCategories(Set<String> categoryIds) async {
    final settings = await SettingsService.getInstance();
    await settings.setCalendarOverviewCategories(categoryIds);
  }

  static String _periodLabel(
    AppLocalizations l10n,
    OverviewPeriodChoice choice,
  ) {
    return switch (choice) {
      OverviewPeriodChoice.thisWeek => l10n.overviewPeriodThisWeek,
      OverviewPeriodChoice.thisMonth => l10n.overviewPeriodThisMonth,
      OverviewPeriodChoice.thisYear => l10n.upcomingPeriodWholeYear,
      OverviewPeriodChoice.last12Months => l10n.overviewPeriodLast12Months,
      OverviewPeriodChoice.last90Days => l10n.overviewPeriodLast90Days,
      OverviewPeriodChoice.allTime => l10n.overviewPeriodAllTime,
      OverviewPeriodChoice.custom => l10n.upcomingPeriodCustom,
    };
  }

  static IconData _periodIcon(OverviewPeriodChoice choice) {
    return switch (choice) {
      OverviewPeriodChoice.thisWeek => Icons.view_week_rounded,
      OverviewPeriodChoice.thisMonth => Icons.calendar_view_month_rounded,
      OverviewPeriodChoice.thisYear => Icons.today_rounded,
      OverviewPeriodChoice.last12Months => Icons.history_rounded,
      OverviewPeriodChoice.last90Days => Icons.history_rounded,
      OverviewPeriodChoice.allTime => Icons.all_inclusive_rounded,
      OverviewPeriodChoice.custom => Icons.date_range_rounded,
    };
  }

  static String _periodId(OverviewPeriodChoice choice) {
    return switch (choice) {
      OverviewPeriodChoice.thisWeek => SemanticsIds.overviewPeriodThisWeek,
      OverviewPeriodChoice.thisMonth => SemanticsIds.overviewPeriodThisMonth,
      OverviewPeriodChoice.thisYear => SemanticsIds.overviewPeriodThisYear,
      OverviewPeriodChoice.last12Months =>
        SemanticsIds.overviewPeriodLast12Months,
      OverviewPeriodChoice.last90Days => SemanticsIds.overviewPeriodLast90Days,
      OverviewPeriodChoice.allTime => SemanticsIds.overviewPeriodAllTime,
      OverviewPeriodChoice.custom => SemanticsIds.overviewPeriodCustom,
    };
  }
}
