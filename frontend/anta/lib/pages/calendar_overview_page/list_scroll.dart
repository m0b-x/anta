part of '../calendar_overview_page.dart';

/// Where the list is: its layout over the measured extents, the landing and
/// the anchor that keep it on a row across rebuilds, and the pinned section
/// label.
mixin _OverviewListScroll on _OverviewRowActions {
  /// The list's position, or null while no list is laid out. The newest one:
  /// a mode cross-fade can hold an outgoing list for a moment.
  ScrollPosition? get _listPosition =>
      _listScroll.hasClients ? _listScroll.positions.last : null;

  /// [_rows]' offsets under [_extents]; null until the extents are measured.
  _ListLayout? get _currentLayout {
    final extents = _extents;
    if (extents == null) return null;
    final layout = _layout;
    final tail = _listTail;
    final newestFirst = _options.order == OverviewOrder.newestFirst;
    if (layout != null &&
        identical(layout.extents, extents) &&
        layout.newestFirst == newestFirst) {
      if (identical(layout.rows, _rows) && layout.tail == tail) return layout;
      // A run appended rows, or only the tail moved: the slots summed so
      // far stand.
      if (identical(layout.rows, _rows) || identical(layout.rows, _rowsBase)) {
        return _layout = layout.extendedTo(_rowBuilder(_rows), tail: tail);
      }
    }
    return _layout = _ListLayout.of(
      _rowBuilder(_rows),
      extents,
      newestFirst: _options.order == OverviewOrder.newestFirst,
      tail: tail,
    );
  }

  /// Sends the list to [target] once the frame that lays the new rows out is
  /// done; a later call before then replaces it. A target that answers null
  /// has no row in the list yet.
  void _aimList(double? Function(_ListLayout layout) target) {
    _listTarget = target;
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpList());
  }

  /// Applies [_listTarget], clamped to the list's extent. Waits — keeping the
  /// target — while the rows' extents are still being measured, and while
  /// the row it wants is in months still to be resolved; the probe's report
  /// and each run call it again. A row that never comes is the end.
  void _jumpList() {
    final target = _listTarget;
    if (target == null || !mounted) return;
    if (_mode != AgendaDayListMode.list) {
      _listTarget = null;
      return;
    }
    final position = _listPosition;
    final layout = _currentLayout;
    if (position == null || layout == null || _extentsStale) return;
    final aimed = target(layout);
    if (aimed == null && _listResolving) return;
    _listTarget = null;
    final offset = (aimed ?? double.infinity).clamp(
      0.0,
      position.maxScrollExtent,
    );
    if (offset != position.pixels) position.jumpTo(offset);
    _updatePinned();
  }

  /// Where the list lands on a period, query, order or rows change, and when
  /// it first shows (D7 · A): on today's day — the first day on or after it,
  /// or the end — when today is inside the period and the oldest come first;
  /// else at the top.
  void _land() {
    final span = _period.resolve(today: _today, yearBounds: _years);
    final today = _today;
    final onToday =
        _options.order == OverviewOrder.oldestFirst &&
        _options.rows == OverviewRows.everyOccurrence &&
        !today.isBefore(span.start) &&
        !today.isAfter(span.end);
    _aimList((layout) => onToday ? layout.offsetOfDay(today) : 0);
  }

  /// What keeps the list on the row it shows across a rebuild that keeps the
  /// period: the first visible row's day — or its month, its category, its
  /// event — found again in the new rows, at the same depth into it when the
  /// same row is there; the nearest later day when it is gone, the end when
  /// nothing follows. Null at the top, which a rebuild keeps by itself.
  double? Function(_ListLayout layout)? _anchorOfList() {
    if (_mode != AgendaDayListMode.list) return null;
    final position = _listPosition;
    final layout = _currentLayout;
    if (position == null || layout == null || layout.rows.isEmpty) return null;
    final pixels = position.pixels;
    if (pixels <= 0) return null;
    final index = layout.rowAtOffset(pixels);
    final depth = pixels - layout.offsetOfRow(index);
    double? nearDay(_ListLayout next, DateTime day) => next.offsetOfDay(day);
    switch (layout.rows[index]) {
      case AgendaDayListMonthRow(:final month):
        return (next) {
          final row = next.monthRowOf(month);
          return row == null
              ? nearDay(next, month)
              : next.offsetOfRow(row) + depth;
        };
      case AgendaDayListDayRow(:final day):
        return (next) {
          final row = next.dayRowOf(day);
          return row == null
              ? nearDay(next, day)
              : next.offsetOfRow(row) + depth;
        };
      case AgendaDayListEntryRow(:final entry):
        // Held by its day's read row, whose depth into the day it keeps.
        final dayRow = layout.dayRowOf(entry.day);
        final dayDepth = dayRow == null
            ? 0.0
            : pixels - layout.offsetOfRow(dayRow);
        return (next) {
          final row = next.dayRowOf(entry.day);
          return row == null
              ? nearDay(next, entry.day)
              : next.offsetOfRow(row) + dayDepth;
        };
      case AgendaDayListCategoryRow(:final categoryId):
        return (next) {
          final row = next.categoryRowOf(categoryId);
          return row == null ? pixels : next.offsetOfRow(row) + depth;
        };
      case AgendaDayListEventRow(:final entry):
        return (next) {
          final row = next.eventRowOf(entry.eventId);
          return row == null ? pixels : next.offsetOfRow(row) + depth;
        };
    }
  }

  /// Pins the label of the section under the list's top edge once that
  /// section's own label has wholly scrolled past it — the one before it
  /// until then — so no label is ever drawn twice (C, the fix pass).
  void _updatePinned() {
    if (!mounted) return;
    final position = _listPosition;
    final layout = _mode == AgendaDayListMode.list ? _currentLayout : null;
    AgendaDayListRow? pinned;
    if (position != null && layout != null && layout.rows.isNotEmpty) {
      if (layout.pinnedAt(position.pixels) case final section?) {
        pinned = layout.rows[section];
      }
    }
    _pinned.value = pinned;
  }

  /// The scrubber's semantics actions: the list's next or previous section —
  /// a month, or a category group — at its top (review 15).
  void _stepList(_ListLayout layout, int direction) {
    final position = _listPosition;
    if (position == null) return;
    final target = layout.sectionStep(position.pixels, direction);
    if (target == null) return;
    _listTarget = null;
    _staleAnchor = null;
    position.jumpTo(target.clamp(0.0, position.maxScrollExtent));
    _updatePinned();
    _click();
  }

  /// A drag the user starts is where they want the list: a landing or an
  /// anchor still waiting for its run or its extents is dropped, so a late
  /// one never yanks the list from under the finger.
  bool _onListScrollStart(ScrollStartNotification notification) {
    if (notification.dragDetails != null) {
      _listTarget = null;
      _staleAnchor = null;
    }
    return false;
  }

  /// Marks the extents stale when an input of theirs moved since they were
  /// measured, noting where the list is while its layout still says so.
  /// Runs while the list body builds, where the width is known.
  void _checkExtentsInputs(BuildContext context, double width) {
    final inputs = (
      MediaQuery.textScalerOf(context),
      AppLocalizations.of(context)!.localeName,
      width,
    );
    if (inputs == _extentsInputs) return;
    _extentsInputs = inputs;
    if (_extentsStale) return;
    _extentsStale = true;
    _staleAnchor = _anchorOfList();
  }

  /// The probe's report: the list can be built — or re-laid on the new
  /// extents — and a target waiting for it applied once it is.
  void _onExtentsMeasured(_RowExtents extents) {
    if (!mounted) return;
    final anchor = _staleAnchor;
    _staleAnchor = null;
    setState(() {
      _extents = extents;
      _extentsStale = false;
    });
    _listTarget ??= anchor;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpList();
      _updatePinned();
    });
  }
}
