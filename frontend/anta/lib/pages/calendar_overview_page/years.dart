part of '../calendar_overview_page.dart';

/// Year mode's tiles: which years are resolved, the runs that resolve the
/// ones near the viewport, and each year's tally.
mixin _OverviewYears on _OverviewQueries {
  /// Drops every year's tiles: the store they were folded from is gone.
  void _clearTiles() {
    _yearTiles
      ..clear()
      ..notify();
    _staleTileYears.clear();
  }

  /// Whether [year]'s tiles are folded from the store and query as they are
  /// now — not stale, not missing.
  bool _tilesCurrent(int year) =>
      _yearTiles.holds(year) && !_staleTileYears.contains(year);

  /// The year the scroll shows next: the one a landing under way is bound
  /// for, else the top year — inside the scroll's span, which a bloc emit
  /// may just have narrowed under the landing.
  int get _shownYearTarget => (_yearScroll.landingYear ?? _year).clamp(
    _scrollYears.first,
    _scrollYears.last,
  );

  /// Whether the store holds every month of [year] in the shape its tiles
  /// fold from — a tally or its rows, only its rows while a query is live —
  /// so resolving the year scans nothing.
  bool _yearHeld(int year) {
    final store = _store!;
    for (final month in AgendaMonthStore.monthsOfYear(year)) {
      if (store.isResolved(month)) continue;
      if (_matcher == null && store.cachedTally(month) != null) continue;
      return false;
    }
    return true;
  }

  /// Resolves [year]'s twelve months — one marks call, or the rows while a
  /// query is live, nothing for what the store holds — and folds its tiles
  /// from marks, each day in its top entry's colour so several categories on
  /// one tile stay tellable apart; under a query from the narrowed months,
  /// which costs the year's rows once and then nothing per keystroke. On
  /// navigation only: the opening year and a landing's target before their
  /// frame, the years in and next to the viewport in [_recompute] when held,
  /// every other year in a run ([_scheduleYearRun]). The sections read
  /// [_yearTiles] and fold nothing; only [year]'s section rebuilds.
  void _resolveYear(int year) {
    if (_tilesCurrent(year)) return;
    final store = _store;
    if (store == null) return;
    // A held year costs no scan, so only a scan holds the next run back.
    if (!_yearHeld(year)) _oweYearFrame();
    final months = AgendaMonthStore.monthsOfYear(year);
    if (_matcher != null) {
      store.ensure(months);
      _yearTiles.put(year, [
        for (final month in months)
          AgendaYearTile.ofTally(
            AgendaMonthTally.ofOwnEntries(_bucketOf(month)),
            perDayColors: true,
          ),
      ]);
    } else {
      store.ensureTallies(months);
      _yearTiles.put(year, [
        for (final month in months)
          AgendaYearTile.ofTally(store.cachedTally(month)!, perDayColors: true),
      ]);
    }
    _staleTileYears.remove(year);
    _yearTiles.notify();
  }

  /// Holds year runs back until the frame that draws a scan's result is
  /// over. A run's scan comes at a frame's end and is drawn by the next
  /// one, whose end is where the flag drops and the next run fires: one
  /// year per frame. A scan anywhere else — a tap, a landing, a bloc emit —
  /// is drawn by the coming frame, and a run registered after it would fire
  /// at that same frame's end: the flag drops a frame later instead, so the
  /// frame that drew the scan's result runs no other scan.
  void _oweYearFrame() {
    if (_yearFrameOwed) return;
    _yearFrameOwed = true;
    final binding = WidgetsBinding.instance;
    void release(Duration _) => _yearFrameOwed = false;
    if (binding.schedulerPhase == SchedulerPhase.postFrameCallbacks) {
      binding.addPostFrameCallback(release);
    } else {
      binding.addPostFrameCallback(
        (_) => binding.addPostFrameCallback(release),
      );
    }
    binding.ensureVisualUpdate();
  }

  /// The band's count and totals for [year], read from its resolved tiles;
  /// blank while it is unresolved — the text changes, never the band's
  /// height — until the run that resolves it repaints.
  void _tallyYear(int year) {
    final tiles = _tilesCurrent(year) ? _yearTiles.tilesFor(year) : null;
    _yearTallied = tiles != null;
    if (tiles == null) {
      _yearKept = 0;
      _yearMissed = 0;
      _totals = {};
      return;
    }
    var kept = 0;
    var missed = 0;
    for (final tile in tiles) {
      kept += tile.count;
      missed += tile.missedCount;
    }
    _yearKept = kept;
    _yearMissed = missed;
    // The tiles above are folded from every month of the year: as rows while
    // a query is live, otherwise as marks (folded into [_markedKept]) or as
    // the rows a list or month look resolved before.
    final store = _store!;
    final totals = <String, int>{};
    for (final month in AgendaMonthStore.monthsOfYear(year)) {
      final marked = _matcher == null
          ? _markedKept[AgendaMonthStore.keyOf(month)]
          : null;
      if (marked != null) {
        marked.forEach((category, count) {
          totals[category] = (totals[category] ?? 0) + count;
        });
      } else if (_matcher != null) {
        _tally(totals, _bucketOf(month).entries);
      } else if (store.cached(month) case final bucket?) {
        _tally(totals, bucket.entries);
      }
    }
    _totals = totals;
  }

  /// The years in and next to the viewport, most wanted first: the top year,
  /// then those whose sections show in the viewport in reading order, then
  /// the top year's two neighbours — inside the span. Read from the scroll
  /// as it is when asked, so a year scrolled past is never among them.
  List<int> _nearYears() {
    if (_store == null || _mode != AgendaDayListMode.year) return const [];
    final visible = _yearScroll.visibleYears;
    final near = <int>[];
    void add(int year) {
      if (year < _scrollYears.first || year > _scrollYears.last) return;
      if (!near.contains(year)) near.add(year);
    }

    add(_year);
    if (visible != null) {
      for (var year = visible.first; year <= visible.last; year++) {
        add(year);
      }
    }
    add(_year - 1);
    add(_year + 1);
    return near;
  }

  /// What a year run should resolve: [_nearYears] whose tiles are not
  /// current.
  List<int> _wantedYears() => [
    for (final year in _nearYears())
      if (!_tilesCurrent(year)) year,
  ];

  /// The next year run when a year is wanted and no run is pending: at the
  /// end of the next frame, once it is drawn (a post-frame callback, a frame
  /// asked for if none is coming). A run resolves exactly one year, the most
  /// wanted when it fires, and one that finds a scan's frame still owed
  /// ([_yearFrameOwed]) waits for the frame after it: so at most one year
  /// resolves per frame, always after the frame the last one's repaint asked
  /// for, and a fling across a decade costs one marks call per frame at
  /// most. Never a timer — a turn-later run would land before the next frame
  /// as well as after it, and a chain cut short would leave it pending.
  /// Nothing is queued while an animated landing is under way — the years it
  /// passes are not stopped on — and [AgendaYearScrollController.onLanded]
  /// queues where it ends. Under [_resolveGeneration], like the list's runs;
  /// nothing runs while a page covers this one, and [didPopNext] schedules
  /// again.
  @override
  void _scheduleYearRun() {
    if (_covered || !mounted || _yearScroll.isLanding) return;
    final generation = _resolveGeneration;
    if (_yearRunGeneration == generation) return;
    if (_wantedYears().isEmpty) return;
    _yearRunGeneration = generation;
    WidgetsBinding.instance
      ..addPostFrameCallback((_) => _runYear(generation))
      ..ensureVisualUpdate();
  }

  /// One year run (see [_scheduleYearRun]).
  void _runYear(int generation) {
    if (_yearRunGeneration == generation) _yearRunGeneration = null;
    if (!mounted ||
        generation != _resolveGeneration ||
        _covered ||
        _yearScroll.isLanding) {
      return;
    }
    if (_yearFrameOwed) {
      _scheduleYearRun();
      return;
    }
    final wanted = _wantedYears();
    if (wanted.isEmpty) return;
    setState(() {
      _resolveYear(wanted.first);
      _tallyYear(_year);
      _foldNav();
    });
    _scheduleYearRun();
  }

  /// Every scroll notification asks for the years it brought into view, and
  /// so does a metrics change — a width or text-scale change can bring a
  /// section into view without a scroll.
  bool _onYearScrollNotification(Notification notification) {
    if (notification is ScrollNotification ||
        notification is ScrollMetricsNotification) {
      _scheduleYearRun();
    }
    return false;
  }
}
