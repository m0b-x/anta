part of '../calendar_overview_page.dart';

/// Changing what is in view: the presentation, the year, the month, the
/// picked day — and the day itself, when the clock moves it.
mixin _OverviewNavigation on _OverviewListScroll {
  /// Whether the wall clock has moved [_today] to another day. Across New
  /// Year, This year moves on with it — the period and the year it opens
  /// year mode on — except in year mode, whose scroll holds the year shown.
  bool _refreshToday() {
    final today = EventAgenda.dateOnly(DateTime.now());
    if (today == _today) return false;
    final before = _today;
    _today = today;
    _home = _home.followingToday(before: before, today: today);
    if (_mode != AgendaDayListMode.year) {
      final period = _period.followingToday(before: before, today: today);
      if (period != _period) {
        _period = period;
        _year = _firstYearOf(period);
      }
    }
    return true;
  }

  void _selectMode(AgendaDayListMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _cameFromYear = false;
      _selectedDay = null;
      if (mode == AgendaDayListMode.year && _period is! OverviewYearPeriod) {
        _year = _firstYearOf(_period);
      }
      if (mode == AgendaDayListMode.year) _clampYearToScroll();
      if (mode == AgendaDayListMode.month) {
        _month = _month.year == _year
            ? _month
            : DateTime.utc(_year, _today.year == _year ? _today.month : 1, 1);
      }
      // A switch into Year lands on the year, resolved before its frame.
      if (mode == AgendaDayListMode.year) _resolveYear(_year);
      _recompute();
    });
    // A switch into the list opens it, so it lands as an open does.
    if (mode == AgendaDayListMode.list) _land();
    if (mode == AgendaDayListMode.year) _yearScroll.jumpToYear(_year);
    unawaited(_persistMode(mode));
  }

  Future<void> _persistMode(AgendaDayListMode mode) async {
    final settings = await SettingsService.getInstance();
    await settings.setCalendarOverviewMode(mode);
  }

  /// The year a period opens year mode on: its first, inside the bounds.
  int _firstYearOf(OverviewPeriod period) {
    final span = period.resolve(today: _today, yearBounds: _years);
    return span.start.year.clamp(_years.first, _years.last);
  }

  /// Puts [_year] inside the scroll's span as year mode opens: a year paged
  /// to in month mode, or the first year of a span kept from the list, may
  /// lie past D28's ceiling, which only the scroll has. A year period
  /// follows the year, as the scroll would have set it; a span stays the
  /// list's.
  void _clampYearToScroll() {
    final year = _year.clamp(_scrollYears.first, _scrollYears.last);
    if (year == _year) return;
    _year = year;
    if (_period is OverviewYearPeriod) _period = OverviewYearPeriod(year);
  }

  /// A new year at the top of the year scroll — a drag, a fling, the years
  /// an animated landing passes, or the landing itself. The title follows
  /// each; the recompute queues runs for none passed by a landing.
  @override
  void _onYearScrolled(int year) {
    // A scroll still fading out under another mode reports nothing to it.
    if (!mounted || _mode != AgendaDayListMode.year || year == _year) return;
    setState(() {
      _year = year;
      _period = OverviewYearPeriod(year);
      _recompute();
    });
  }

  /// Scrolls [year]'s header to the top while the scroll is laid out, its
  /// tiles resolved before the first frame of the way and its neighbours
  /// once it lands; otherwise the year simply changes and the scroll opens
  /// there when it next appears. The chevrons, the Today slot and the
  /// scrubber lane's steps all land here.
  void _goToYear(int year) {
    final target = year.clamp(_scrollYears.first, _scrollYears.last);
    // Mid-landing the scroll is already bound somewhere: where it goes, not
    // the year passing the top, is what a repeat would duplicate.
    if (target == (_yearScroll.landingYear ?? _year)) return;
    _click();
    if (_mode == AgendaDayListMode.year && _yearScroll.isAttached) {
      setState(() => _resolveYear(target));
      unawaited(_yearScroll.animateToYear(target));
    } else {
      _onYearScrolled(target);
    }
  }

  void _openMonth(DateTime month) {
    setState(() {
      _mode = AgendaDayListMode.month;
      _cameFromYear = true;
      _month = month;
      _year = month.year;
      _period = OverviewYearPeriod(month.year);
      _selectedDay = null;
      _recompute();
    });
  }

  void _goToMonth(DateTime month) {
    final order = AgendaMonthStore.monthOrder(month);
    if (order < AgendaMonthStore.monthOrder(_firstMonth) ||
        order > AgendaMonthStore.monthOrder(_lastMonth) ||
        order == AgendaMonthStore.monthOrder(_month)) {
      return;
    }
    setState(() {
      _month = month;
      _year = month.year.clamp(_years.first, _years.last);
      _period = OverviewYearPeriod(_year);
      _selectedDay = null;
      _recompute();
    });
    _scrollMonthToTop();
  }

  void _toggleSelectedDay(DateTime day) {
    // The picked day always lets go: a query may have emptied it since.
    if (day != _selectedDay && !_hasOccurrence(day)) return;
    setState(() {
      _selectedDay = _selectedDay == day ? null : day;
      _recompute();
    });
    _scrollMonthToTop();
  }

  void _scrollMonthToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _monthScroll.hasClients) _monthScroll.jumpTo(0);
    });
  }
}
