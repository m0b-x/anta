part of '../calendar_overview_page.dart';

/// The three bodies: the list on its measured extents under its pinned
/// label, month mode's day rows, and the year and month navs.
mixin _OverviewBody on _OverviewChrome {
  /// The pinned band's height: the group gap, then one section slot.
  static double _pinnedBandHeight(AgendaHeaderSlots headers) =>
      RowMetrics.groupGap + (headers.sectionHeight ?? 0);

  /// The label of the section the list is scrolled into — its month, or its
  /// category group under One per event — on the ground above the list. A
  /// slot of one geometry, the list's section slot: drawn by the list's own
  /// builder, so it reads as the label it stands for, and shown only once
  /// that label has wholly scrolled out of the list — the section before it
  /// until then — so a label is never drawn twice (C, the fix pass).
  Widget _buildPinnedLabel(AgendaHeaderSlots headers) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RowMetrics.groupInset,
        RowMetrics.groupGap,
        RowMetrics.groupInset,
        0,
      ),
      child: ValueListenableBuilder<AgendaDayListRow?>(
        valueListenable: _pinned,
        builder: (context, row, _) {
          final pinned = switch (row) {
            AgendaDayListMonthRow(:final month, :final kept, :final missed) =>
              AgendaDayListMonthRow(
                month: month,
                showYear: true,
                kept: kept,
                missed: missed,
              ),
            AgendaDayListCategoryRow() => row,
            _ => null,
          };
          if (pinned == null) return SizedBox(height: headers.sectionHeight);
          return _rowBuilder([pinned], headers: headers).build(context, 0);
        },
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n, ColorScheme colorScheme) {
    final store = _store;
    if (store == null) {
      return const Center(child: CircularProgressIndicator());
    }
    switch (_mode) {
      case AgendaDayListMode.year:
        return NotificationListener<Notification>(
          onNotification: _onYearScrollNotification,
          child: AgendaYearScroll(
            controller: _yearScroll,
            firstYear: _scrollYears.first,
            lastYear: _scrollYears.last,
            // Cache-only: what the runs and the recomputes folded.
            tiles: _yearTiles,
            color: _tileColor(colorScheme),
            appearance: _appearance,
            today: _today,
            onOpenMonth: _openMonth,
            // The scaffold already resizes for the keyboard, so the scroll
            // carries no inset of its own, and the sections hang on the
            // width and their own year's tiles alone — no inset frame
            // rebuilds a year of tiles.
            padding: OverviewListMetrics.yearScrollPadding,
            // The page's groups' role, as Month's and List's cards.
            tileBackground: colorScheme.rowGroup,
            // One lane per page: the list's lane never shows with this one.
            scrubber: AgendaYearScrubber(
              semanticsLabel: l10n.overviewYearScrubberLabel,
              identifier: SemanticsIds.overviewScrubber,
              onLabelChanged: _click,
              onStep: _goToYear,
            ),
          ),
        );
      case AgendaDayListMode.list:
        return _buildListBody(l10n);
      case AgendaDayListMode.month:
        return _buildMonthBody(l10n);
    }
  }

  /// The period band of year and list mode (D15, D16): the nav, then the
  /// totals — one geometry in both, and month mode draws the same two at the
  /// top of its scroll view. Null in month mode and until the store exists.
  Widget? _buildBand(AppLocalizations l10n) {
    if (_store == null) return null;
    final nav = switch (_mode) {
      AgendaDayListMode.year => _buildYearNav(l10n),
      AgendaDayListMode.list => _buildListNav(l10n),
      AgendaDayListMode.month => null,
    };
    if (nav == null) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [nav, _buildTotals(l10n)],
    );
  }

  /// The list: the extents probe, then the list once the probe has
  /// measured.
  Widget _buildListBody(AppLocalizations l10n) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _checkExtentsInputs(context, constraints.maxWidth);
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: RowMetrics.groupInset,
              top: 0,
              right: RowMetrics.groupInset,
              child: _RowExtentProbe(
                builderOf: _rowBuilder,
                today: _today,
                measure: _extentsStale,
                onMeasured: _onExtentsMeasured,
              ),
            ),
            if (_currentLayout case final layout?)
              _buildList(l10n, layout)
            else
              const Center(child: CircularProgressIndicator()),
          ],
        );
      },
    );
  }

  /// The list on its exact extents (T4): every row's slot is its kind's
  /// measured height, so a jump lands where it was aimed, the scrollbar is
  /// true and a far jump lays out only what it lands on.
  Widget _buildList(AppLocalizations l10n, _ListLayout layout) {
    // Captured, not read from the fields: the outgoing list of a mode
    // cross-fade keeps building rows while it fades, and the fields by then
    // hold the next mode's.
    final rows = _rowBuilder(layout.rows, headers: layout.extents.headers);
    final rowCount = layout.rows.length;
    final tail = layout.tail;
    final extents = layout.slots;
    // Until the probe reports, the rows are drawn at the new scale or in the
    // new locale on the old extents: clipped to them for that frame rather
    // than overflowing them.
    final stale = _extentsStale;
    Widget slotted(Widget row) => stale
        ? ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              maxHeight: double.infinity,
              child: row,
            ),
          )
        : row;
    return Builder(
      builder: (context) {
        final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
        final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
        final padding = EdgeInsets.fromLTRB(
          RowMetrics.groupInset,
          0,
          RowMetrics.groupInset,
          FormMetrics.bodyBottom +
              (viewInsets > viewPadding ? viewInsets : viewPadding),
        );
        final list = Semantics(
          container: true,
          identifier: SemanticsIds.overviewList,
          child: NotificationListener<ScrollStartNotification>(
            onNotification: _onListScrollStart,
            child: extents.isEmpty
                ? ListView(
                    controller: _listScroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: padding,
                    children: [
                      FormCaption(
                        text: l10n.overviewEmptyPeriod,
                        padding: FormMetrics.groupCaptionPadding,
                      ),
                    ],
                  )
                : CustomScrollView(
                    controller: _listScroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    semanticChildCount: extents.length,
                    slivers: [
                      SliverPadding(
                        padding: padding,
                        sliver: _ExactExtentSliver(
                          layout: layout,
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => slotted(
                              index < rowCount
                                  ? rows.build(context, index)
                                  : _tailCaption(l10n, tail!),
                            ),
                            childCount: extents.length,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        );
        // Outside the list's node, so the lane joins none of its indexes;
        // it overlays the rows' trailing 48 dp, which carry no control.
        final body = rowCount == 0
            ? list
            : ListScrubber(
                controller: _listScroll,
                labelAt: (offset) => _groupLabelAt(l10n, layout, offset),
                semanticsLabel: l10n.overviewScrubberLabel,
                identifier: SemanticsIds.overviewScrubber,
                onLabelChanged: _click,
                onStep: (direction) => _stepList(layout, direction),
                child: list,
              );
        // The band takes its height from the list's share of the page, not
        // from the column above it, so nothing overflows; and it yields
        // when it would take most of that share — with the keyboard up at a
        // large scale on a small phone — so the list keeps a height to drag.
        return LayoutBuilder(
          builder: (context, constraints) {
            final band = _pinnedBandHeight(layout.extents.headers);
            final showBand =
                band <=
                constraints.maxHeight * OverviewListMetrics.pinnedBandMaxShare;
            // One shape either way, so the list keeps its state when the
            // band yields or returns.
            return Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: showBand ? band : 0),
                  child: body,
                ),
                if (showBand)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _buildPinnedLabel(layout.extents.headers),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  /// The scrubber's bubble: the month at [offset], with its year, or the
  /// category group under One per event.
  static String? _groupLabelAt(
    AppLocalizations l10n,
    _ListLayout layout,
    double offset,
  ) {
    final group = layout.groupAt(offset);
    if (group == null) return null;
    return switch (layout.rows[group]) {
      AgendaDayListMonthRow(:final month) => AgendaListView.monthLabel(
        l10n.localeName,
        month,
        withYear: true,
      ),
      AgendaDayListCategoryRow(:final label) => label,
      _ => null,
    };
  }

  /// The list's last row while it is not the period's end: "Loading more…"
  /// while runs are pending, the cap's line once it is reached. The probe
  /// measures it through this same builder, so its slot is exact.
  static Widget _tailCaption(AppLocalizations l10n, _ListTail tail) {
    return FormCaption(
      text: switch (tail) {
        _ListTail.loading => l10n.overviewLoading,
        _ListTail.capped => l10n.overviewCapReached(
          OverviewListMetrics.maxEntries,
        ),
      },
      padding: FormMetrics.groupCaptionPadding,
    );
  }

  /// Month mode below its nav and grid: the day list's rows (§3.2 item 7) —
  /// read rows over their entries for the whole month, or, with a day
  /// picked, that day's read row carrying "Whole month" over its entries,
  /// which list its missed occurrences under every display (D32).
  Widget _buildMonthBody(AppLocalizations l10n) {
    final bucket = _monthBucket!;
    final rows = _rowBuilder(_rows);
    // Captured beside its builder, [_buildList]'s reasoning: the outgoing
    // body of a mode cross-fade keeps building rows while it fades, and
    // `_rows` by then holds the next mode's — a count read from the field
    // would index past the rows this builder has.
    final rowCount = _rows.length;
    final selected = _selectedDay;
    // With a day picked the rows are its entries alone (`_recompute` groups
    // by day only for the whole month), so its read row is built in front
    // of them here, from the same entries' counts.
    final leadingRows = selected == null ? 0 : 1;
    final empty = rowCount == 0 && selected == null;
    return Builder(
      builder: (context) {
        final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
        final viewPadding = MediaQuery.viewPaddingOf(context).bottom;
        return CustomScrollView(
          controller: _monthScroll,
          slivers: [
            SliverToBoxAdapter(child: _buildMonthNav(l10n, bucket)),
            SliverToBoxAdapter(child: _buildTotals(l10n)),
            SliverToBoxAdapter(
              child: AgendaMonthGrid(
                month: _month,
                firstDay: _firstMonth,
                lastDay: DateTime.utc(_lastMonth.year, _lastMonth.month + 1, 0),
                today: _today,
                selectedDay: selected,
                appearance: _appearance,
                hasEntry: _hasOccurrence,
                barsFor: _barsFor,
                onDaySelected: _toggleSelectedDay,
                onPageChanged: _goToMonth,
              ),
            ),
            SliverPadding(
              // The group gap above the first group: the grid's last row of
              // cells ends flush, and a rounded group straight under it
              // read as part of the grid.
              padding: const EdgeInsets.fromLTRB(
                RowMetrics.groupInset,
                RowMetrics.groupGap,
                RowMetrics.groupInset,
                0,
              ),
              sliver: empty
                  ? SliverToBoxAdapter(
                      child: FormCaption(
                        text: l10n.dayListEmptyMonth,
                        padding: FormMetrics.groupCaptionPadding,
                      ),
                    )
                  : SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => selected != null && index == 0
                            ? _buildPickedDayRow(
                                context,
                                l10n,
                                rows,
                                rowCount,
                                selected,
                              )
                            : rows.build(context, index - leadingRows),
                        childCount: rowCount + leadingRows,
                      ),
                    ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height:
                    FormMetrics.bodyBottom +
                    (viewInsets > viewPadding ? viewInsets : viewPadding),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The picked day's head in month mode: its read row with "Whole month" as
  /// the second target, above its entries — the day list's own (D3).
  Widget _buildPickedDayRow(
    BuildContext context,
    AppLocalizations l10n,
    AgendaDayListRowBuilder rows,
    int rowCount,
    DateTime day,
  ) {
    return FormRowShell(
      first: true,
      last: rowCount == 0,
      child: rows.readRow(
        context,
        day: day,
        kept: _pickedKept,
        missed: _pickedMissed,
        trailingButton: FormTrailingButton(
          icon: Icons.close_rounded,
          tooltip: l10n.dayListWholeMonth,
          identifier: SemanticsIds.overviewWholeMonth,
          onPressed: () => _toggleSelectedDay(day),
        ),
      ),
    );
  }

  Widget _buildYearNav(AppLocalizations l10n) {
    return AgendaPeriodNav(
      title: '$_year',
      // Blank, in the same box, while the top year is still resolving.
      subtitle: _yearTallied
          ? agendaDayListCountLabel(l10n, _yearKept, _yearMissed)
          : '',
      previousTooltip: l10n.datePickerPreviousYear,
      nextTooltip: l10n.datePickerNextYear,
      todayTooltip: l10n.dayListScopeThisYear,
      titleTooltip: l10n.overviewPeriod,
      previousIdentifier: SemanticsIds.overviewNavPrevious,
      nextIdentifier: SemanticsIds.overviewNavNext,
      todayIdentifier: SemanticsIds.overviewNavToday,
      titleIdentifier: SemanticsIds.overviewNavTitle,
      onTitleTap: _openPeriodMenu,
      onPrevious: _year > _scrollYears.first
          ? () => _goToYear(_year - 1)
          : null,
      onNext: _year < _scrollYears.last ? () => _goToYear(_year + 1) : null,
      onToday: _year == _today.year ? null : () => _goToYear(_today.year),
    );
  }

  Widget _buildMonthNav(AppLocalizations l10n, AgendaDayListMonth bucket) {
    final order = AgendaMonthStore.monthOrder(_month);
    final todayMonth = AgendaMonthStore.monthOf(_today);
    return AgendaPeriodNav(
      title: AgendaListView.monthLabel(l10n.localeName, _month, withYear: true),
      month: _month,
      subtitle: agendaDayListCountLabel(
        l10n,
        bucket.keptCount,
        bucket.count - bucket.keptCount,
      ),
      previousTooltip: l10n.dayListPreviousMonth,
      nextTooltip: l10n.dayListNextMonth,
      todayTooltip: l10n.dayListJumpToToday,
      titleTooltip: l10n.overviewPeriod,
      previousIdentifier: SemanticsIds.overviewNavPrevious,
      nextIdentifier: SemanticsIds.overviewNavNext,
      todayIdentifier: SemanticsIds.overviewNavToday,
      titleIdentifier: SemanticsIds.overviewNavTitle,
      onTitleTap: _openPeriodMenu,
      onPrevious: order > AgendaMonthStore.monthOrder(_firstMonth)
          ? () => _goToMonth(DateTime.utc(_month.year, _month.month - 1, 1))
          : null,
      onNext: order < AgendaMonthStore.monthOrder(_lastMonth)
          ? () => _goToMonth(DateTime.utc(_month.year, _month.month + 1, 1))
          : null,
      onToday: order == AgendaMonthStore.monthOrder(todayMonth)
          ? null
          : () => _goToMonth(todayMonth),
    );
  }
}
