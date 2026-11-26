part of '../calendar_overview_page.dart';

/// What the page reads when it opens and after a trip to Settings: the
/// settings, the saved views, the partner's look, the week start — and the
/// ⋮ menu's two ways out.
mixin _OverviewLoading on _OverviewControls {
  /// Reloads the bloc after a Keep on the alarm page cleared an event's
  /// "remove after it rings" behind its back, and counts it, so a detail
  /// sheet open here learns that a Keep happened.
  ///
  /// Never takes the notice. A calendar beneath this page registered first
  /// and has taken it already — its reload is on its way — when the flag is
  /// down here. With no calendar beneath, the alarm page's Open event may
  /// push one over this page next, and that calendar must still find the
  /// flag standing: it is how it knows its initial target may predate the
  /// Keep and defers the sheet to the reload.
  void _serveKeepNotice() {
    if (!mounted) return;
    _keepsHeard++;
    if (!AlertKeepNotice.instance.hasPending) return;
    context.read<CalendarBloc>().add(const RefreshCalendarView());
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsService.getInstance();
    final loaded = await settings.getCalendarOverviewSettings(today: _today);
    if (!mounted) return;
    _takeShareLook(loaded.share);
    _appearance = loaded.appearance;
    _palette = loaded.palette;
    _categoryIds = loaded.categoryIds;
    _mode = loaded.mode;
    _period = _home = loaded.period;
    if (loaded.period case OverviewYearPeriod(:final year)) {
      _year = year;
    } else {
      _yearFromPeriod = true;
    }
    _options = loaded.listOptions;
    _hapticFeedback = loaded.hapticFeedback;
    _settingsLoaded = true;
    _storeStale = true;
    _rebuild();
    // A look that arrived while the settings loaded wins over what they kept.
    _serveOverviewLook();
  }

  Future<void> _loadViews() async {
    try {
      final service = await OverviewViewService.getInstance();
      if (!mounted) return;
      setState(() {
        _viewService = service;
        _foldNav();
      });
    } catch (e) {
      debugPrint('[CalendarOverviewPage] Saved views load failed: $e');
    }
  }

  /// Takes the share look of a settings trip, and asks afresh who the
  /// partner is — the pairing may have changed on the page the trip
  /// returned from. Returns whether the look changed.
  bool _takeShareLook(ShareLook share) {
    final lookChanged = share.eventLook != _partnerLook.look;
    final changed = lookChanged || share.markMine != _partnerLook.markMine;
    _partnerLook = PartnerLook(
      look: share.eventLook,
      partner: _partnerLook.partner,
      name: _partnerLook.name,
      markMine: share.markMine,
      unpaired: _partnerLook.unpaired,
    );
    // The bars draw a partner's events only; my share sign is the rows'.
    if (lookChanged) _refoldBars();
    _partnerAsked = false;
    unawaited(_readPartner());
    return changed;
  }

  /// The month grid's bars say whose an entry is by the calendar page's own
  /// rule, under this page's partner look.
  EventDayBarProvider _barRuleOf(AppLocalizations l10n) => EventDayBarProvider(
    partnerLabel: _partnerLook.label(l10n),
    hollowPartners: _partnerLook.outlined,
  );

  /// Refolds the month grid's bars under a new partner look — the store's
  /// and a search's alike — with no month resolved again.
  void _refoldBars() {
    final store = _store;
    final l10n = _l10n;
    if (store == null || l10n == null) return;
    final rule = store.barRule = _barRuleOf(l10n);
    for (final key in _filteredBars.keys.toList()) {
      final bucket = _filteredMonths[key];
      if (bucket == null) {
        _filteredBars.remove(key);
        continue;
      }
      _filteredBars[key] = AgendaMonthStore.buildBars(
        bucket,
        maxBars: store.maxBars,
        rule: rule,
      );
    }
  }

  /// Reads who the partner is, once per settings trip and only while the
  /// list holds an event of theirs or one I share with them: an account
  /// that never paired opens no sharing for the overview.
  Future<void> _readPartner() async {
    if (_partnerAsked || !_eventsHoldShares) return;
    _partnerAsked = true;
    final ShareAudience? audience;
    try {
      audience = (await ShareService.getInstance()).availability.audience;
    } catch (e, st) {
      // The rows keep the localized stand-in for the name and the person
      // glyph for the face until the next state taken asks again.
      debugPrint('[CalendarOverviewPage] partner not read: $e\n$st');
      _partnerAsked = false;
      return;
    }
    if (!mounted) return;
    final next = PartnerLook(
      look: _partnerLook.look,
      partner: audience?.members.firstOrNull,
      name: audience?.displayName,
      markMine: _partnerLook.markMine,
      unpaired: audience == null,
    );
    if (next == _partnerLook) return;
    // The bars say the name and nothing of the photo, which only the rows'
    // avatars draw.
    final renamed = next.name != _partnerLook.name;
    setState(() {
      _partnerLook = next;
      if (renamed) _refoldBars();
    });
  }

  /// This week — as the home and as the period shown — re-read on the week
  /// start just set, so the This week row lists the grid's week. Nothing is
  /// persisted: both read back as the same `thisWeek`. A week paged away
  /// from today is a look at those seven days and stays as it is.
  void _followWeekStart() {
    OverviewPeriod follow(OverviewPeriod period) =>
        period is OverviewWeekPeriod &&
            period.menuChoice(today: _today) == OverviewPeriodChoice.thisWeek
        ? OverviewPeriod.thisWeek(
            today: _today,
            weekStart: _appearance.weekStart,
          )
        : period;
    _home = follow(_home);
    final period = follow(_period);
    if (period != _period) {
      _period = period;
      _year = _firstYearOf(period);
    }
  }

  /// The ⋮ menu's Calendar settings. Settings → Categories can delete a
  /// category, which reassigns its events in SQL; the delete refreshes the
  /// service's cache before its route pops, so the trip ends in a re-emit of
  /// that cache — as the calendar's own does.
  Future<void> _openSettings() async {
    final bloc = context.read<CalendarBloc>();
    await AppNavigator.toCalendarSettings(context);
    if (!mounted) return;
    bloc.add(const RefreshCalendarView(refreshLedger: true));
  }

  void _exportEvents() {
    final state = context.read<CalendarBloc>().state;
    if (state is! CalendarPageLoaded) return;
    _export.start(context, state.allEvents);
  }
}
