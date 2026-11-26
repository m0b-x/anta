part of '../calendar_overview_page.dart';

/// From the bloc's events to what the page shows: taking a state, the scan
/// and its resolve runs, the list's rows in their runs, the picked day, and
/// the catch-up when the page is uncovered.
mixin _OverviewData on _OverviewLoading {
  /// Catches up with everything that moved while a page covered this one, in
  /// one rebuild: the bloc state parked meanwhile, the appearance — the
  /// calendar's settings are one ⋮ away, from here or from a calendar pushed
  /// over this page — the day, and a query typed just before the cover.
  ///
  /// The allowlist, the mode and the period are left alone. Only this page
  /// writes them, and a month drilled into from a year tile is not persisted,
  /// so reading the mode back would throw the user out of it. The one
  /// exception is This week under a new week start ([_followWeekStart]).
  Future<void> _resumeUncovered() async {
    final settings = await SettingsService.getInstance();
    final loaded = await settings.getCalendarOverviewSettings(today: _today);
    if (!mounted || _covered) return;
    if (_refreshToday()) _storeStale = true;
    final lookChanged = _takeShareLook(loaded.share);
    if (_settingsLoaded) {
      _hapticFeedback = loaded.hapticFeedback;
      _palette = loaded.palette;
      if (loaded.appearance != _appearance) {
        final weekStartChanged =
            loaded.appearance.weekStart != _appearance.weekStart;
        _appearance = loaded.appearance;
        _storeStale = true;
        if (weekStartChanged) _followWeekStart();
      }
    }
    // A page pushed from inside a row's trip returns to the trip: what was
    // parked waits for its end.
    final pending = _sheetGuard.isOpen ? null : _pendingState;
    var changed = _storeStale;
    if (pending != null) {
      _pendingState = null;
      _take(pending);
      changed = true;
    }
    final raw = _unappliedQuery;
    if (raw != null) _setQuery(raw);
    if (changed || raw != null) {
      _rebuild();
    } else {
      // A new look changes how rows draw, never which rows there are.
      if (lookChanged) setState(() {});
      _scheduleYearRun();
    }
    if (raw != null) _land();
  }

  /// The rows show no description and no alert, so `occurrenceRevision` —
  /// which counts those — is an input only while a query is live: a day's
  /// match reads its description; presence has its own revision.
  bool _listenWhen(CalendarPageState previous, CalendarPageState current) {
    if (current is! CalendarPageLoaded) return previous is CalendarPageLoaded;
    if (previous is! CalendarPageLoaded) return true;
    return !identical(previous.allEvents, current.allEvents) ||
        previous.membershipRevision != current.membershipRevision ||
        previous.presenceRevision != current.presenceRevision ||
        (_query.isNotEmpty &&
            previous.occurrenceRevision != current.occurrenceRevision);
  }

  /// Parked while covered, and while a row's detail sheet holds
  /// [_sheetGuard]: a sheet never fires the route observer, yet every tick
  /// in it gives the bloc's list a new identity, and the period under the
  /// sheet would be resolved anew for each. The trip's end adopts what was
  /// parked, once ([_openOn]).
  void _onStateChanged(CalendarPageState state) {
    if (_covered || _sheetGuard.isOpen) {
      _pendingState = state;
      // What is adopted later may carry presence writes of the sheet or the
      // page above, which no mark accounts for: that state takes a new store.
      _pendingMarks.clear();
      return;
    }
    // A return still reading the settings must not adopt the older state it
    // parked over this one.
    _pendingState = null;
    _adopt(state);
  }

  /// Takes the event list from a bloc state and repaints.
  @override
  void _adopt(CalendarPageState state) {
    _take(state);
    _rebuild();
  }

  /// A revision bump arrives as a fresh state with the same list, so the
  /// listener's test above decides when this runs; the store is resolved
  /// again only when the list or a revision its rows read moved.
  void _take(CalendarPageState state) {
    final loaded = state is CalendarPageLoaded ? state : null;
    _events = loaded?.allEvents;
    _eventsHoldShares =
        loaded != null && (loaded.holdsPartnerEvents || loaded.holdsSharedByMe);
    if (!_partnerAsked) unawaited(_readPartner());
    final inputs = (
      loaded?.allEvents,
      loaded?.membershipRevision ?? 0,
      loaded?.presenceRevision ?? 0,
    );
    final adopted = _adoptedInputs;
    if (inputs != adopted) {
      _adoptedInputs = inputs;
      if (!_forgetMarked(adopted, inputs)) _storeStale = true;
    }
    if (_refreshCategoryLabels()) _storeStale = true;
  }

  /// Whether [next] moved from [previous] by nothing but presence bumps the
  /// pending marks account for. Then the marks' months — and only they — are
  /// dropped from the store and resolved again at once, so the rows fold
  /// anew under the same keys and the list's anchor finds its row in the
  /// same frame (review 1). Any other bump — the detail sheet's pair, adopted
  /// as its trip ends — is left to a new store, as is a bump arriving with
  /// the list, the membership or the store itself moved. The bumps consume
  /// the oldest marks either way; a mark's month is forgotten with every
  /// bump until its own is consumed, since writes may land out of order.
  bool _forgetMarked(
    (List<CalendarEvent>?, int, int)? previous,
    (List<CalendarEvent>?, int, int) next,
  ) {
    if (previous == null || _pendingMarks.isEmpty) return false;
    final (events, membership, presence) = next;
    final bumps = presence - previous.$3;
    if (bumps <= 0) return false;
    final months = {
      for (final (_, day) in _pendingMarks) AgendaMonthStore.keyOf(day),
    };
    final accounted = bumps <= _pendingMarks.length;
    if (accounted) {
      _pendingMarks.removeRange(0, bumps);
    } else {
      _pendingMarks.clear();
    }
    final store = _store;
    if (!accounted ||
        store == null ||
        _storeStale ||
        !identical(events, previous.$1) ||
        membership != previous.$2) {
      return false;
    }
    for (final key in months) {
      final month = AgendaMonthStore.monthOfKey(key);
      final resolved = store.isResolved(month);
      store.forget(month);
      // The year tiles' kept marks of this month are folded anew with its
      // tally; the filtered months, the bars and the tiles go whole with
      // [_rebuild].
      _markedKept.remove(key);
      // A listed month must be back before [_listMore] runs: it extends the
      // synchronous part over resolved months only, and stopping at this one
      // would leave the rest to runs, which is the shrink this path avoids.
      if (resolved) store.ensure([month]);
    }
    return true;
  }

  /// Resolves what the current presentation shows through the query, then
  /// repaints — and, while the list shows, keeps it on the row it was on.
  /// Every input funnels through here: the events and their revisions, the
  /// categories, the query, the locale, the appearance. Those that feed the
  /// resolvers set [_storeStale] first, and only then is every resolved
  /// month dropped and the year bounds re-derived; a query alone keeps the
  /// store and refilters what it holds (T3).
  ///
  /// [duringBuild] is a call from [didChangeDependencies]: the rebuild is
  /// still immediate, but year mode's shown year is resolved after the frame
  /// — its section shows the placeholder for that one frame — so no scan
  /// runs inside the build phase.
  @override
  void _rebuild({bool duringBuild = false}) {
    final events = _events;
    final l10n = _l10n;
    _filteredMonths.clear();
    _filteredBars.clear();
    if (events == null || !_settingsLoaded || l10n == null) {
      _resolveGeneration++;
      _store = null;
      _markedKept.clear();
      _occurrenceMask.clear();
      _clearTiles();
      _storeStale = true;
      _rows = const [];
      _monthBucket = null;
      _foldNav();
      if (mounted) setState(() {});
      return;
    }
    final anchor = _anchorOfList();
    _matcher = _query.isEmpty
        ? null
        : EventQueryMatcher(
            query: _query,
            categoryLabels: _categoryLabels,
            labelTextOf: (event) =>
                AgendaSearchText.forEventCached(event, l10n),
          );
    if (_storeStale || _store == null) {
      _storeStale = false;
      _eventsById = {for (final event in events) event.id: event};
      // The year scroll lays every year out at once, so there an open-ended
      // series ends the span next year rather than at the calendar's
      // ceiling (D28); the list, the month pages and the range picker keep
      // every year an event can fire in.
      final spans = EventAgenda.yearSpansOf(
        events,
        categoryIds: _categoryIds,
        todayYear: _today.year,
        earliestYear: CalendarBounds.earliest.year,
        latestYear: CalendarBounds.latest.year,
        openEndedLastYear: _today.year + 1,
      );
      _years = spans.full;
      _scrollYears = spans.ceiled;
      if (_yearFromPeriod) {
        _yearFromPeriod = false;
        _year = _firstYearOf(_period);
      } else {
        _year = _year.clamp(_years.first, _years.last);
      }
      if (_mode == AgendaDayListMode.year) _clampYearToScroll();
      // A laid-out scroll keeps its own top year through a span change.
      if (!_yearScroll.isAttached) _yearScroll.jumpToYear(_year);
      _markedKept.clear();
      _occurrenceMask.clear();
      _clearTiles();
      final store = _store = AgendaMonthStore(
        resolve: _resolve,
        resolveMarks: _resolveMarks,
        maxBars: AgendaMonthGrid.maxBarsFor(_appearance),
        ownTallies: true,
        barRule: _barRuleOf(l10n),
      );
      widget._onStore?.call(store);
    } else {
      // The same store under a new query, or with a month forgotten. The
      // years in and next to the viewport keep their tiles on screen until
      // their refold replaces them — in [_recompute] when the store holds
      // them, otherwise by the runs, which take them first — so a keystroke
      // never blanks a section. Every other year is dropped: a far year
      // scrolled in later draws the placeholder until its run, never the
      // tiles of the query before as if they were current.
      final near = _nearYears();
      _yearTiles
        ..removeWhere((year) => !near.contains(year))
        ..notify();
      _staleTileYears
        ..clear()
        ..addAll(_yearTiles.years);
    }
    if (mounted) {
      final inYear = _mode == AgendaDayListMode.year;
      setState(() {
        // The year shown is resolved before its frame, so neither the first
        // frame nor a rebuild under it draws it blank — mid-landing the
        // year it is bound for, which the passing years only lead to.
        if (inYear && !duringBuild) _resolveYear(_shownYearTarget);
        _recompute();
      });
      if (inYear && duringBuild) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // Covered, nothing is resolved: the return queues the shown year
          // with the rest ([didPopNext]).
          if (!mounted || _covered || _mode != AgendaDayListMode.year) return;
          final target = _shownYearTarget;
          if (_tilesCurrent(target)) return;
          setState(() {
            _resolveYear(target);
            _tallyYear(_year);
            _foldNav();
          });
        });
      }
    }
    final landing = _landOnOpen;
    _landOnOpen = false;
    if (landing && _mode == AgendaDayListMode.list) {
      _land();
    } else if (anchor != null) {
      _aimList(anchor);
    }
  }

  /// The allowlist narrows the expansion itself and changes rarely, so it
  /// stays an input of the scan; the query is applied after it (T3).
  List<EventOccurrence> _scan(DateTime start, DateTime end) {
    return EventAgenda.occurrencesInRange(
      events: _events!,
      from: start,
      to: end,
      categoryIds: _categoryIds,
    );
  }

  List<AgendaDayListEntry> _resolve(DateTime start, DateTime end) {
    final occurrences = _scan(start, end);
    for (final month in _monthsOf((start: start, end: end))) {
      _occurrenceMask[AgendaMonthStore.keyOf(month)] = 0;
    }
    for (final occurrence in occurrences) {
      final key = AgendaMonthStore.keyOf(occurrence.day);
      // A day the scan returned outside the span has no mask seeded above:
      // folded into a fresh one, since a release build has no assert to stop
      // it and this runs inside `setState`.
      _occurrenceMask[key] =
          (_occurrenceMask[key] ?? 0) | (1 << (occurrence.day.day - 1));
    }
    return AgendaListView.eventDayEntries(
      occurrences,
      _l10n!,
      false,
      showRecurrenceLabels: _appearance.showRecurrenceLabels,
      missedDisplay: _appearance.missedDisplay,
    );
  }

  /// Marks feed the year tiles alone, which count my days and never a
  /// partner's (D15): their occurrences leave before anything is folded.
  List<AgendaDayMark> _resolveMarks(DateTime start, DateTime end) {
    var occurrences = _scan(start, end);
    if (occurrences.any((occurrence) => occurrence.event.fromPartner)) {
      occurrences = [
        for (final occurrence in occurrences)
          if (!occurrence.event.fromPartner) occurrence,
      ];
    }
    for (final month in _monthsOf((start: start, end: end))) {
      _markedKept[AgendaMonthStore.keyOf(month)] = {};
    }
    for (final occurrence in occurrences) {
      final event = occurrence.event;
      if (EventPresence.appliesTo(event) &&
          EventPresence.isMissed(event, occurrence.day)) {
        continue;
      }
      // [_resolve]'s reasoning: a day outside the span gets its own counts
      // rather than a null check the asserts alone guard.
      final counts = _markedKept.putIfAbsent(
        AgendaMonthStore.keyOf(occurrence.day),
        () => <String, int>{},
      );
      final category = CalendarCategories.resolve(event.categoryId).id;
      counts[category] = (counts[category] ?? 0) + 1;
    }
    return AgendaListView.eventDayMarks(
      occurrences,
      missedDisplay: _appearance.missedDisplay,
    );
  }

  /// Resolves what the presentation shows and rebuilds its rows or tiles, so a
  /// frame folds nothing. Called inside `setState` on navigation only. In
  /// year mode it folds the years in and next to the viewport from what the
  /// store holds and queues a run for the rest, so no recompute leaves a
  /// visible placeholder unqueued.
  @override
  void _recompute() {
    _resolveGeneration++;
    _rowsBase = null;
    final store = _store;
    if (store == null) {
      _foldNav();
      return;
    }
    switch (_mode) {
      case AgendaDayListMode.year:
        _rows = const [];
        _monthBucket = null;
        _takePicked(const []);
        for (final year in _nearYears()) {
          if (!_tilesCurrent(year) && _yearHeld(year)) _resolveYear(year);
        }
        _tallyYear(_year);
        _scheduleYearRun();
      case AgendaDayListMode.list:
        _monthBucket = null;
        _takePicked(const []);
        final span = _period.resolve(today: _today, yearBounds: _years);
        final months = _monthsOf(span);
        _listSpan = span;
        _spanCrossesYear = span.start.year != span.end.year;
        _listMonths = _options.order == OverviewOrder.newestFirst
            ? months.reversed.toList()
            : months;
        _listedMonthCount = 0;
        _listMore(OverviewListMetrics.syncMonths);
      case AgendaDayListMode.month:
        final bucket = _bucketOf(_month);
        if (_matcher != null) {
          _filteredBars[AgendaMonthStore.keyOf(_month)] ??=
              AgendaMonthStore.buildBars(
                bucket,
                maxBars: store.maxBars,
                rule: store.barRule,
              );
        }
        _monthBucket = bucket;
        _totals = {};
        _tally(_totals, bucket.entries);
        final selected = _selectedDay;
        if (selected == null) {
          _takePicked(const []);
          _rows = buildAgendaDayListRows(
            bucket.days,
            (day) => _listed(bucket.entriesOn(day)),
            groupByDay: true,
            withMonths: false,
            keptCountOf: _options.missedOnly
                ? (_) => 0
                : bucket.keptCountForDay,
          );
        } else {
          _takePicked(_pickedDayEntries(selected));
          final listed = _listed(_pickedEntries);
          final kept = _pickedKept;
          _rows = buildAgendaDayListRows(
            [selected],
            (_) => listed,
            groupByDay: false,
            withMonths: false,
            keptCountOf: (_) => kept,
          );
        }
    }
    _foldNav();
  }

  /// Folds what the chrome reads out of the state a navigation just set: the
  /// totals caption, the saved view the list shown matches and the reach of
  /// the list nav's two chevrons. [_titleTemplates]'s reasoning — a frame
  /// walks no category catalog, scans no saved list and resolves no period
  /// twice over just to enable a button.
  @override
  void _foldNav() {
    final l10n = _l10n;
    _totalsCaption = l10n == null ? '' : _totalsLabel(l10n);
    _activeView = _viewService?.matching(
      _shownPeriod,
      _options,
      _categoryIds,
      today: _today,
      weekStart: _appearance.weekStart,
    );
    _canStepBack = _steppedPeriod(-1) != null;
    _canStepForward = _steppedPeriod(1) != null;
  }

  /// Holds [entries] as the picked day's and folds its read row's counts.
  void _takePicked(List<AgendaDayListEntry> entries) {
    _pickedEntries = entries;
    var missed = 0;
    for (final entry in entries) {
      if (entry.missed) missed++;
    }
    _pickedMissed = missed;
    _pickedKept = _options.missedOnly ? 0 : entries.length - missed;
  }

  /// The picked day as the day panel lists it (D32): scanned on its own and
  /// converted under `faded`, so under the hidden display its missed and
  /// assumed-absent occurrences still show — dimmed, with the button that
  /// marks them — where the month's bucket has dropped them. Under `faded`
  /// this is exactly the bucket's day. The query narrows it as it narrows
  /// the bucket; Missed only is left to the rows, the read row counts all.
  List<AgendaDayListEntry> _pickedDayEntries(DateTime day) {
    final entries = AgendaListView.eventDayEntries(
      _scan(day, day),
      _l10n!,
      false,
      showRecurrenceLabels: _appearance.showRecurrenceLabels,
      missedDisplay: CalendarMissedDisplay.faded,
    );
    final matcher = _matcher;
    if (matcher == null) return entries;
    return [
      for (final entry in entries)
        if (_matches(matcher, entry)) entry,
    ];
  }

  /// Lists [count] more of [_listMonths] — and every month right after them
  /// the store already holds, which costs no scan, so a query or an option
  /// over a period resolved before relists it whole — and schedules the
  /// next run while months are left.
  void _listMore(int count) {
    final store = _store!;
    var end = _listedMonthCount + count;
    if (end > _listMonths.length) end = _listMonths.length;
    while (end < _listMonths.length && store.isResolved(_listMonths[end])) {
      end++;
    }
    final from = _listedMonthCount;
    store.ensure(_listMonths.sublist(from, end));
    _listedMonthCount = end;
    _buildListRows(from: from);
    if (_listResolving) _scheduleListRun();
  }

  /// The next run, one event-loop turn later — a `Future`, never a
  /// microtask, so the frame the last run asked for is drawn first. New
  /// rows only ever join at the list's reading end, so the offset is kept
  /// as it is; a landing or an anchor still waiting for its row is tried
  /// again. Nothing runs while a page covers this one: a run that comes due
  /// then leaves the list as it is, and [didPopNext] schedules the next.
  void _scheduleListRun() {
    if (_covered) return;
    final generation = _resolveGeneration;
    unawaited(
      Future(() {
        if (!mounted || generation != _resolveGeneration || _covered) return;
        setState(() {
          _listMore(OverviewListMetrics.batchMonths);
          // A run appends months, so it moves the totals the caption reads:
          // the chrome folds after a background run exactly as it folds
          // after a navigation.
          _foldNav();
        });
        if (_listTarget != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _jumpList());
        }
      }),
    );
  }

  /// The rows of the months listed from [from] on, appended to the rows of
  /// the months before them: months only ever join at the list's reading
  /// end, so a run visits its own months' entries and no others (review 16).
  /// One per event folds every entry listed so far again — a fold has no
  /// end to append at. The cap counts what the rows show — after the query
  /// and Missed only — in reading order, so Newest first keeps the newest
  /// entries; the day it falls in keeps the entries before it.
  void _buildListRows({required int from}) {
    final perEvent = _options.rows == OverviewRows.perEvent;
    if (from == 0) {
      _rows = const [];
      _rowsBase = null;
      _listedEntries = [];
      _listedKept = 0;
      _listedMissed = 0;
      _totals = {};
      _listCapped = false;
    }
    final span = _listSpan!;
    final newestFirst = _options.order == OverviewOrder.newestFirst;
    final newMonths = _listMonths.sublist(from, _listedMonthCount);
    final buckets = {
      for (final month in newestFirst ? newMonths.reversed : newMonths)
        AgendaMonthStore.keyOf(month): _bucketOf(month),
    };
    AgendaDayListMonth bucketOf(DateTime day) =>
        buckets[AgendaMonthStore.keyOf(day)]!;
    // The store resolves whole months; a span starting on the 15th lists
    // nothing before it.
    final days = <DateTime>[
      for (final bucket in buckets.values)
        for (final day in bucket.days)
          if (!day.isBefore(span.start) && !day.isAfter(span.end)) day,
    ];
    final shown = <DateTime>[];
    var total = _listedKept + _listedMissed;
    DateTime? cutDay;
    var cut = const <AgendaDayListEntry>[];
    for (final day in newestFirst ? days.reversed : days) {
      final entries = _listed(bucketOf(day).entriesOn(day));
      CalendarOverviewPage._debugListedEntryVisits += entries.length;
      if (entries.isEmpty) continue;
      shown.add(day);
      final room = OverviewListMetrics.maxEntries - total;
      if (entries.length < room) {
        total += entries.length;
        continue;
      }
      if (entries.length > room) {
        cutDay = day;
        cut = entries.sublist(0, room);
      }
      _listCapped = true;
      break;
    }
    List<AgendaDayListEntry> entriesOf(DateTime day) =>
        day == cutDay ? cut : _listed(bucketOf(day).entriesOn(day));
    int keptCountOf(DateTime day) {
      if (_options.missedOnly) return 0;
      if (day == cutDay) return cut.where((entry) => !entry.missed).length;
      return bucketOf(day).keptCountForDay(day);
    }

    final listed = <AgendaDayListEntry>[
      // [shown] is already in reading order — the loop above walked the days
      // under the order in force — so it is never reversed a second time.
      for (final day in shown) ...entriesOf(day),
    ];
    final missed = listed.where((entry) => entry.missed).length;
    _listedKept += listed.length - missed;
    _listedMissed += missed;
    _tally(_totals, listed);
    if (perEvent) {
      _listedEntries.addAll(listed);
      _rowsBase = null;
      _rows = foldAgendaDayListRowsByEvent(
        _listedEntries,
        categoryLabels: {
          for (final category in CalendarCategories.all)
            category.id: CalendarCategories.labelOf(category, _l10n!),
        },
        categoryOrder: [
          for (final category in CalendarCategories.all) category.id,
        ],
        newestFirst: newestFirst,
        categoryOf: _categoryOf,
      );
    } else {
      final added = buildAgendaDayListRows(
        shown,
        entriesOf,
        groupByDay: true,
        withMonths: true,
        alwaysMonths: true,
        showYear: _spanCrossesYear,
        keptCountOf: keptCountOf,
      );
      // A month is never split across runs, so the new months' rows follow
      // the old ones as they are; the layout extends from where it was.
      if (_rows.isEmpty) {
        _rows = added;
      } else if (added.isNotEmpty) {
        _rowsBase = _rows;
        _rows = [..._rows, ...added];
      }
    }
    // The rows moved under an offset that did not: the pinned label
    // follows once they are laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) => _updatePinned());
  }

  /// Every month [span] touches, in order.
  static List<DateTime> _monthsOf(DateRange span) {
    final last = AgendaMonthStore.keyOf(span.end);
    return [
      for (var key = AgendaMonthStore.keyOf(span.start); key <= last; key++)
        AgendaMonthStore.monthOfKey(key),
    ];
  }
}
