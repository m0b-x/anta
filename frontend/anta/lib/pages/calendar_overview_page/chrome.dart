part of '../calendar_overview_page.dart';

/// The chip row's height at the default text scale — its gap under the bar
/// and one run of chips, each on its 48 dp target — which is the
/// keyboard's travel the row folds over.
const double _chipRowHeight = FormMetrics.bodyTop + FormMetrics.chipTapTarget;

/// The bar and what sits under it: the options and views buttons, the mode
/// chips, the Search row and Back's ladder, the totals and the list's
/// period band.
mixin _OverviewChrome on _OverviewData {
  /// Badged by the restrictions alone — Missed only and the categories
  /// allowlist — as the calendar's filter button is: Order and Rows
  /// re-present the same entries, and a badge means something is hidden.
  Widget _buildOptionsButton(AppLocalizations l10n) {
    // Missed only narrows the list and month mode's rows; year mode's tiles
    // ignore it, so there it hides nothing (review 10). The allowlist
    // narrows every mode, the tiles included.
    final restrictions =
        (_options.missedOnly && _mode != AgendaDayListMode.year ? 1 : 0) +
        (CategoryAllowlist.filtersNothing(_categoryIds) ? 0 : 1);
    return AutomationId(
      identifier: SemanticsIds.overviewOptionsOpen,
      child: IconButton(
        tooltip: l10n.overviewListOptions,
        isSelected: restrictions > 0,
        iconSize: AppBarMetrics.glyphSize,
        // The badge rides the glyph, inside the button's 48 dp box: around
        // the button Material puts a labelled badge 4 dp above its child,
        // which a 48 dp bar's toolbar clip cuts off. Its count stays out of
        // the button's merged node: a label there would replace the tooltip
        // as what Android 9+ announces, and the button would be read as a
        // bare number (a spoken count needs words of its own).
        icon: ExcludeSemantics(
          child: Badge.count(
            count: restrictions,
            isLabelVisible: restrictions > 0,
            child: const Icon(Icons.tune_rounded),
          ),
        ),
        onPressed: _openOptions,
      ),
    );
  }

  /// The saved views (D17a · A), the calendar bar's saved-filters button in
  /// the overview's bar: selected while the list shown is a saved view, so a
  /// glance says whether what is on screen can be had back in one tap.
  Widget _buildViewsButton(AppLocalizations l10n) {
    final service = _viewService;
    final active = _activeView;
    return AutomationId(
      identifier: SemanticsIds.overviewViewsOpen,
      child: IconButton(
        tooltip: l10n.overviewViewsTitle,
        isSelected: active != null,
        iconSize: AppBarMetrics.glyphSize,
        icon: const Icon(Icons.bookmarks_outlined),
        onPressed: service == null ? null : _openViews,
      ),
    );
  }

  /// The page's primary control, on the page (D12 · A): the owner switches
  /// presentation on every visit, and the mode persists, so a switch kept in
  /// the title's menu left a page in List or Month with no visible way back.
  /// The search button ends the row (D21 · A): search is a List-mode tool
  /// most days, and the thumb is already on the chips.
  Widget _buildModeChips(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(top: FormMetrics.bodyTop),
      child: OverviewModeChips(
        mode: _mode,
        onSelected: _selectMode,
        modeIdentifier: _modeId,
        onSearch: _toggleSearch,
        searchActive: _query.isNotEmpty,
        searchIdentifier: SemanticsIds.overviewSearchOpen,
      ),
    );
  }

  /// The Search row in a group box of its own, only while the chip row's
  /// button has summoned it.
  Widget _buildSearchGroup(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(
        left: RowMetrics.groupInset,
        top: FormMetrics.bodyTop,
        right: RowMetrics.groupInset,
      ),
      child: FormRowGroup(
        trailingGap: false,
        children: [
          FormSearchRow(
            controller: _searchController,
            focusNode: _searchFocus,
            hint: l10n.upcomingSearchHint,
            clearTooltip: l10n.upcomingClearSearch,
            onChanged: _onQueryChanged,
            identifier: SemanticsIds.overviewSearch,
          ),
        ],
      ),
    );
  }

  /// Opens the Search row focused, or closes it and drops its query: the
  /// query is session-only, so a closed row never hides a live one.
  void _toggleSearch() {
    if (!_searchOpen) {
      setState(() => _searchOpen = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _searchOpen) _searchFocus.requestFocus();
      });
      return;
    }
    _closeSearch();
  }

  void _closeSearch() {
    _blur();
    if (_searchController.text.isNotEmpty || _query.isNotEmpty) {
      _searchController.clear();
      _onQueryChanged('');
    }
    setState(() => _searchOpen = false);
  }

  /// Whether Back means something on this page before it means leaving it
  /// (the overview record's D34). One [PopScope] serves the page, never one
  /// per mode — the browser's rule: swapping them would rebuild the
  /// [Scaffold] and lose the scroll.
  bool get _backIsHandled =>
      _searchOpen || (_mode == AgendaDayListMode.month && _cameFromYear);

  /// The ladder of the overview record's D34: the open Search row closes
  /// first, then a month opened from a year tile returns to the tiles; mode
  /// switches never stack steps. A back that arrives between a state change
  /// and its rebuild finds `canPop` still false and neither rung up, so it
  /// pops here rather than being lost, as the browser's does.
  void _onBackIntercepted() {
    if (_searchOpen) {
      _closeSearch();
      return;
    }
    // Back takes the chip's path on purpose: the Year it writes is the mode
    // this page entered Month from, so the stored mode reads as it did
    // before the drill.
    if (_mode == AgendaDayListMode.month && _cameFromYear) {
      _selectMode(AgendaDayListMode.year);
      return;
    }
    AppNavigator.pop(context);
  }

  static String _modeId(AgendaDayListMode mode) {
    return switch (mode) {
      AgendaDayListMode.year => SemanticsIds.overviewViewYear,
      AgendaDayListMode.month => SemanticsIds.overviewViewMonth,
      AgendaDayListMode.list => SemanticsIds.overviewViewList,
    };
  }

  /// The per-category totals under every mode's nav (D16), in a slot one
  /// line tall whatever it reads (D23 · A) — none, one category or a dozen —
  /// so the body below never moves. Empty, it is no semantics node at all
  /// rather than an unlabeled stop (review 12).
  Widget _buildTotals(AppLocalizations l10n) {
    final template = FormCaption(
      text: ' ',
      maxLines: OverviewListMetrics.totalsMaxLines,
      padding: FormMetrics.groupCaptionPadding,
    );
    final totals = _totalsCaption;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RowMetrics.groupInset),
      child: FormCaptionSlot(
        candidates: [template],
        child: Semantics(
          container: totals.isNotEmpty,
          excludeSemantics: totals.isEmpty,
          child: FormCaption(
            text: totals,
            maxLines: OverviewListMetrics.totalsMaxLines,
            padding: FormMetrics.groupCaptionPadding,
          ),
        ),
      ),
    );
  }

  /// The list's period band (D15): the year and month navs' row over the
  /// period, stepping by its own length, its title the Period menu.
  Widget _buildListNav(AppLocalizations l10n) {
    return AgendaPeriodNav(
      title: _period.menuValue(l10n),
      titleTemplates: _titleTemplates(l10n),
      subtitle: agendaDayListCountLabel(l10n, _listedKept, _listedMissed),
      previousTooltip: l10n.overviewPeriodPrevious,
      nextTooltip: l10n.overviewPeriodNext,
      todayTooltip: l10n.overviewPeriodHome(_home.menuValue(l10n)),
      titleTooltip: l10n.overviewPeriod,
      previousIdentifier: SemanticsIds.overviewNavPrevious,
      nextIdentifier: SemanticsIds.overviewNavNext,
      todayIdentifier: SemanticsIds.overviewNavToday,
      titleIdentifier: SemanticsIds.overviewNavTitle,
      onTitleTap: _openPeriodMenu,
      onPrevious: _canStepBack ? () => _step(-1) : null,
      onNext: _canStepForward ? () => _step(1) : null,
      onToday: _period == _home ? null : _goHome,
    );
  }

  /// Every shape the list nav's title takes, so a step never moves the list
  /// (D15): the presets, a year, every month's name — a month period's
  /// title, This month and the months it steps to — and for every month a
  /// same-year and a cross-year span on it with two-digit days, which a week
  /// is titled with too — every month, because the widest abbreviation is a
  /// matter of pixels, not characters (review 6).
  /// The list's alone: Year's and Month's boxes are their own titles' (D20 ·
  /// A), one line at 1.0, so the span's second line costs the tiles nothing.
  /// Built once per locale and year.
  List<String> _titleTemplates(AppLocalizations l10n) {
    final year = _today.year;
    final key = '${l10n.localeName} $year';
    if (key == _titleTemplatesKey) return _titleTemplatesCache;
    _titleTemplatesKey = key;
    return _titleTemplatesCache = List.unmodifiable([
      l10n.overviewPeriodLast12Months,
      l10n.overviewPeriodLast90Days,
      l10n.overviewPeriodAllTime,
      '$year',
      for (var m = DateTime.january; m <= DateTime.december; m++) ...[
        OverviewMonthPeriod(year, m).menuValue(l10n),
        dateSpanLabel(
          l10n,
          DateTime.utc(year, m, 10),
          DateTime.utc(year, m, 28),
        ),
        dateSpanLabel(
          l10n,
          DateTime.utc(year - 1, m, 28),
          DateTime.utc(year, m, 28),
        ),
      ],
    ]);
  }
}
