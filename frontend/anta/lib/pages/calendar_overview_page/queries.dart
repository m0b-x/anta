part of '../calendar_overview_page.dart';

/// What the page reads off what it holds: a month's bucket, what matches the
/// search, the per-category tallies, what a day lists and which rows a mode
/// shows.
mixin _OverviewQueries on _OverviewState {
  /// Localized category labels for the search, re-resolved when the catalog
  /// or the locale moves. A partner's shown categories join, a hidden one
  /// never: hiding bumps no revision, so the shown list's identity is
  /// compared too.
  bool _refreshCategoryLabels() {
    final l10n = _l10n;
    if (l10n == null) return false;
    final revision = CalendarCategories.revision;
    final partner = CalendarCategories.partnerShown;
    if (_categoryRevision == revision &&
        identical(_categoryPartnerShown, partner)) {
      return false;
    }
    _categoryRevision = revision;
    _categoryPartnerShown = partner;
    _categoryLabels = {
      for (final category in CalendarCategories.visiblePlus(_categoryIds))
        category.id: CalendarCategories.labelOf(category, l10n),
      for (final category in partner)
        category.id: CalendarCategories.labelOf(category, l10n),
    };
    return true;
  }

  /// Whether months of the list are still to come: neither all listed nor
  /// stopped by the cap.
  bool get _listResolving =>
      !_listCapped && _listedMonthCount < _listMonths.length;

  /// What closes the list after its last row, if anything does.
  _ListTail? get _listTail => _listCapped
      ? _ListTail.capped
      : _listResolving
      ? _ListTail.loading
      : null;

  /// [month]'s bucket as the page lists it: the store's own, or — while a
  /// query is live — the entries of it the query matches, folded into a
  /// bucket of its own once per matcher. Resolves the month if the store
  /// has not, so it runs on navigation only.
  AgendaDayListMonth _bucketOf(DateTime month) {
    final bucket = _store!.monthFor(month);
    final matcher = _matcher;
    if (matcher == null) return bucket;
    return _filteredMonths[AgendaMonthStore.keyOf(
      month,
    )] ??= AgendaDayListMonth.build(bucket.month, [
      for (final entry in bucket.entries)
        if (_matches(matcher, entry)) entry,
    ]);
  }

  /// One grammar with the scan's own candidate test and per-day match, so a
  /// post-filtered entry is exactly one the scan would have kept.
  bool _matches(EventQueryMatcher matcher, AgendaDayListEntry entry) {
    final event = _eventsById[entry.eventId];
    if (event == null) return false;
    return matcher.mayMatch(event) && matcher.matches(event, entry.day);
  }

  /// The category an entry's event wears, an unknown one read as the
  /// fallback, as every surface resolves it.
  String _categoryOf(AgendaDayListEntry entry) {
    final event = _eventsById[entry.eventId];
    return CalendarCategories.resolve(event?.categoryId ?? '').id;
  }

  /// Adds [entries] to [totals] per category: the kept ones, or the missed
  /// ones while Missed only narrows this mode — year mode's tiles ignore it,
  /// as its count does (D16a). Each mode's caption counts what that mode
  /// shows: List and Month show a partner's entries and count them; Year is
  /// the heat-map of my days, whose tiles count none of theirs.
  void _tally(Map<String, int> totals, Iterable<AgendaDayListEntry> entries) {
    final inYear = _mode == AgendaDayListMode.year;
    final missed = _options.missedOnly && !inYear;
    for (final entry in entries) {
      if (entry.missed != missed) continue;
      if (inYear && entry.fromPartner) continue;
      final category = _categoryOf(entry);
      totals[category] = (totals[category] ?? 0) + 1;
    }
  }

  /// The totals caption (D16): the categories with a count in catalog order,
  /// [OverviewListMetrics.namedTotals] of them named and the rest summed up
  /// as "+N more"; empty
  /// when nothing is listed.
  String _totalsLabel(AppLocalizations l10n) {
    final parts = <String>[];
    var rest = 0;
    for (final category in CalendarCategories.all) {
      final count = _totals[category.id];
      if (count == null || count == 0) continue;
      if (parts.length < OverviewListMetrics.namedTotals) {
        final label = CalendarCategories.labelOf(category, l10n);
        parts.add(l10n.overviewCategoryTotal(label, count));
      } else {
        rest++;
      }
    }
    if (rest > 0) parts.add(l10n.categoriesMore(rest));
    return parts.join(' · ');
  }

  /// Whether [day] has anything listed: the store's mask, or the narrowed
  /// month's while a query is live. Cache-only, for the grid's builder.
  bool _hasEntry(DateTime day) {
    if (_matcher == null) return _store?.hasEntry(day) ?? false;
    final mask = _filteredMonths[AgendaMonthStore.keyOf(day)]?.markedMask ?? 0;
    return mask & (1 << (day.day - 1)) != 0;
  }

  /// Whether [day] is one to pick in month mode (D32): one with an entry,
  /// or under the hidden display one whose occurrences were all dropped as
  /// missed — the picked day lists them ([_pickedDayEntries]). A live query
  /// keeps every other day to [_hasEntry]: a dropped occurrence was never
  /// matched against it. Cache-only, for the grid's builder.
  bool _hasOccurrence(DateTime day) {
    if (_hasEntry(day)) return true;
    // The picked cell agrees with its rows, which a query matches faded.
    if (day == _selectedDay && _pickedEntries.isNotEmpty) return true;
    if (_matcher != null || !_missedHidden) return false;
    final mask = _occurrenceMask[AgendaMonthStore.keyOf(day)] ?? 0;
    return mask & (1 << (day.day - 1)) != 0;
  }

  /// The day's bars as [_hasEntry] reads its marks. Cache-only.
  List<DayBar>? _barsFor(DateTime day) {
    final bars = _matcher == null
        ? _store?.barsFor(day)
        : _filteredBars[AgendaMonthStore.keyOf(day)];
    return bars?[day.day];
  }

  /// A day's entries as the rows list them: only the missed ones under
  /// Missed only.
  List<AgendaDayListEntry> _listed(List<AgendaDayListEntry> entries) {
    if (!_options.missedOnly) return entries;
    return [
      for (final entry in entries)
        if (entry.missed) entry,
    ];
  }

  /// Whether the appearance hides missed entries. A mark on a row the month
  /// or the list draws from its bucket would then take the row away with
  /// nothing there left to undo it (review 2); the picked day is exempt, as
  /// the day panel is (D32).
  bool get _missedHidden =>
      _appearance.missedDisplay == CalendarMissedDisplay.hidden;

  /// Whether the mode shows a row per occurrence — month mode's, and the
  /// list's under Every occurrence — the rows that are a day to mark.
  bool get _dayRowsShown =>
      _mode == AgendaDayListMode.month ||
      (_mode == AgendaDayListMode.list &&
          _options.rows == OverviewRows.everyOccurrence);

  /// Whether month mode shows one picked day, whose rows list its missed
  /// occurrences under every display ([_pickedDayEntries]).
  bool get _pickedDayShown =>
      _mode == AgendaDayListMode.month && _selectedDay != null;

  /// Where the day panel's presence button is offered on the rows: where a
  /// row is a day and a mark keeps its row — missed entries show, or the
  /// rows are the picked day's.
  bool get _presenceOffered =>
      _dayRowsShown && (!_missedHidden || _pickedDayShown);
}
