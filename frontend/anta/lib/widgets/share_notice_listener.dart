import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../constants/calendar_categories.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/share_notice.dart';
import '../services/app_navigator.dart';
import '../services/calendar_event_service.dart';
import '../services/category_service.dart';
import '../services/kept_share_notices.dart';
import '../services/share_service.dart';
import '../utils/custom_snackbar.dart';
import '../utils/share_copy.dart';

/// The one place the app says a [ShareNotice] (`docs/cloud-share-surfaces-
/// roadmap.md` §6.14, D23): a bar inside the app, never a system
/// notification.
///
/// Mounted once above the navigator, it draws nothing of its own. A notice
/// that arrives while the app is not in front, or before a page is up to
/// carry the bar, is held — the arrivals merged into one, the leaves into
/// another — and said on the next resume. Under a dialog, an alert or a
/// sheet that may hold a draft it waits for what is in front to change,
/// and someone's bar with an action — an Undo — it waits out. It holds
/// what arrived under one database only while that database is open. It
/// opens no service until a notice arrives, so an account that never
/// paired pays one idle subscription and nothing else.
class ShareNoticeListener extends StatefulWidget {
  final Widget child;

  /// Resolves the share service, for the partner's name; a seam for tests.
  final Future<ShareService> Function() shareService;

  /// Loads the category catalogue before a category is worded: a built-in
  /// read from an empty cache is "Other". A seam for tests.
  final Future<Object?> Function() loadCategories;

  /// Whether an alert is in front — ringing, or still to be routed to its
  /// page — over which nothing is said and nothing is pushed: `main.dart`'s
  /// rule for its permission prompt.
  final bool Function() alertInFront;

  /// Reads what a check kept while no app ran to say it
  /// (`KeptShareNotices`): asked at the start and on each return, and what
  /// it hands over is held and said like any notice. Reading clears
  /// nothing — [forgetKept] does. A seam for tests.
  final Future<List<ShareNotice>> Function() keptNotices;

  /// Tells the store what of its notices was dealt with — said, or dropped
  /// as undone at the moment of saying — so it forgets that and nothing
  /// else. Never called for a notice that did not come from the store. A
  /// seam for tests.
  final Future<void> Function(KeptNoticesSaid said) forgetKept;

  /// Which of the given ids the calendar still holds as the partner's
  /// events, asked as an arrival is said. A seam for tests.
  final Future<Set<String>> Function(Iterable<String> eventIds)
  partnerEventsHeld;

  /// What is in front on the app's navigator, in `main.dart`'s
  /// `navigatorObservers`.
  static final ShareNoticeRoutes routes = ShareNoticeRoutes();

  const ShareNoticeListener({
    super.key,
    required this.child,
    this.shareService = ShareService.getInstance,
    this.loadCategories = CategoryService.getInstance,
    this.alertInFront = _noAlert,
    this.keptNotices = KeptShareNotices.forActiveDatabase,
    this.forgetKept = KeptShareNotices.forgetForActiveDatabase,
    this.partnerEventsHeld = heldPartnerEvents,
  });

  static bool _noAlert() => false;

  /// Which of [eventIds] the calendar shows as the partner's: read from the
  /// event cache, which leaves out their events in a category hidden on
  /// this phone. So an arrival in a hidden category is "not here", dropped
  /// unsaid and forgotten in the store — decided: a person is not told of
  /// an event they chose not to see.
  static Future<Set<String>> heldPartnerEvents(
    Iterable<String> eventIds,
  ) async {
    final wanted = eventIds.toSet();
    final events = (await CalendarEventService.getInstance()).events;
    return {
      for (final event in events)
        if (event.fromPartner && wanted.contains(event.id)) event.id,
    };
  }

  @override
  State<ShareNoticeListener> createState() => _ShareNoticeListenerState();
}

class _ShareNoticeListenerState extends State<ShareNoticeListener>
    with WidgetsBindingObserver {
  StreamSubscription<ShareNotice>? _notices;

  /// What waits to be said, in arrival order, by id: a read that repeats
  /// what the last one found must not say an event twice, and two events of
  /// one title are two. An event's latest title is the one said.
  final Set<String> _arrivedCategories = {};
  final Map<String, String> _arrivedEvents = {};

  /// The leaves that wait, each run of them told with one name a bar of
  /// its own, the oldest first. Merged under the latest name, the leaves
  /// of a pair that ended were said as the next partner's.
  final List<_Leaves> _left = [];

  /// The opening of the database what waits arrived under
  /// ([ShareService.databaseGeneration]): it tells of that database's
  /// events, so under another it is dropped unsaid.
  int? _heldGeneration;

  /// Runs while a bar is up that the next must not take down — this
  /// listener's own, or someone's bar with an action — since the helper
  /// takes the bar on screen down for the next one.
  Timer? _barUp;

  /// The helper's last record of a bar with an action that [_barUp] has
  /// waited out or is waiting out — this listener's own bar with View, or
  /// someone's — so it is never waited for twice.
  DateTime? _actionBarWaited;

  /// Set across the read of the partner's name, so a notice that lands in
  /// that gap merges into what waits rather than starting a second bar.
  bool _wording = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ShareNoticeListener.routes._onChanged = _onRoutesChanged;
    _notices = ShareService.notices.listen(_hold);
    _prompts = KeptShareNotices.prompts.listen((_) => unawaited(_holdKept()));
    unawaited(_holdKept());
  }

  /// The store may hold something new with the app in front
  /// ([KeptShareNotices.prompt]): read again, as at a return.
  StreamSubscription<void>? _prompts;

  /// Of what waits, the ids that came from the store, by kind: when one is
  /// said or dropped the store is told, and forgets it.
  final _Ids _kept = _Ids();

  /// What the store must not have said again under this database: said, or
  /// dropped as undone, while the store may still hold it. Reading clears
  /// nothing, so a resume reads a notice again while its forgetting is on
  /// its way — or after it failed.
  ///
  /// An id stays exactly as long as that is open. Once the store has
  /// forgotten it, it goes: an arrival said in the morning, kept anew by a
  /// later run — it left and was shared again — is news, and held for the
  /// life of the process it was never said and never forgotten.
  final _Ids _dealt = _Ids();

  /// Of [_dealt], what was said or dropped as a live notice. The store was
  /// told nothing — saying it costs no statement — yet a run may have kept
  /// the same id, in a read still on its way: that copy is then forgotten
  /// unsaid. A read begun after the saying that brings none settles it the
  /// other way: there is no copy, and the id goes.
  final _Ids _live = _Ids();

  /// Holds what a check kept with the database while the app was closed
  /// (`docs/cloud-shared-freshness.md`, decision f). Costs a database that
  /// kept nothing no read at all. What still waits here from an earlier
  /// read is held by id, so reading it again adds nothing.
  Future<void> _holdKept() async {
    // Before the read: what it brings belongs to this opening of the
    // database, and to nobody once another is open — said under the next,
    // it was forgotten there and kept, to be said again, here.
    final generation = ShareService.databaseGeneration;
    final saidBefore = _live.copy();
    try {
      final notices = await widget.keptNotices();
      if (!mounted || ShareService.databaseGeneration != generation) return;
      // Before the marks below, which are this database's.
      _keepToDatabase();
      final read = _Ids();
      final copies = _Ids();
      for (final notice in notices) {
        final fresh = _notDealtWith(notice, read: read, copies: copies);
        if (fresh != null) _hold(fresh);
      }
      _live.removeAll(copies);
      _forget(copies.said());
      final noCopy = saidBefore.without(read);
      _live.removeAll(noCopy);
      _dealt.removeAll(noCopy);
    } catch (e, st) {
      debugPrint('[ShareNoticeListener] kept notices not read: $e\n$st');
    }
  }

  /// [notice] from the store without what was already dealt with, its ids
  /// marked as the store's; null when nothing of it is left. Every id it
  /// names goes into [read], and into [copies] the ones already said as a
  /// live notice.
  ShareNotice? _notDealtWith(
    ShareNotice notice, {
    required _Ids read,
    required _Ids copies,
  }) {
    bool fresh(String id, Set<String> Function(_Ids ids) of) {
      of(read).add(id);
      if (!of(_dealt).contains(id)) return true;
      if (of(_live).contains(id)) of(copies).add(id);
      return false;
    }

    switch (notice) {
      case ShareArrived(:final categoryIds, :final events):
        final categories = [
          for (final id in categoryIds)
            if (fresh(id, (ids) => ids.categories)) id,
        ];
        final arrived = [
          for (final event in events)
            if (fresh(event.id, (ids) => ids.events)) event,
        ];
        _kept.categories.addAll(categories);
        _kept.events.addAll(arrived.map((event) => event.id));
        final left = ShareArrived(categoryIds: categories, events: arrived);
        return left.isEmpty ? null : left;
      case ShareLeftWithAlert(:final events, :final partnerName):
        final left = [
          for (final event in events)
            if (fresh(event.id, (ids) => ids.left)) event,
        ];
        _kept.left.addAll(left.map((event) => event.id));
        return left.isEmpty
            ? null
            : ShareLeftWithAlert(left, partnerName: partnerName);
      case ShareHiddenWithAlerts():
        return notice;
    }
  }

  /// What was just said, or dropped as it would have been said, is dealt
  /// with: the store is told of the ids that were its own. A notice that
  /// only ever arrived live tells it nothing, and costs no statement.
  void _dealtWith({
    Iterable<String> left = const [],
    Iterable<String> categories = const [],
    Iterable<String> events = const [],
  }) {
    final all = _Ids()
      ..left.addAll(left)
      ..categories.addAll(categories)
      ..events.addAll(events);
    final stored = all.within(_kept);
    _kept.removeAll(stored);
    _dealt.addAll(all);
    _live.addAll(all.without(stored));
    _forget(stored.said());
  }

  /// Has the store forget [said], and what it forgot is dealt with no
  /// longer: kept again, it is said again.
  void _forget(KeptNoticesSaid said) {
    if (said.isEmpty) return;
    final generation = _heldGeneration;
    unawaited(
      widget
          .forgetKept(said)
          .then(
            (_) {
              if (_heldGeneration != generation) return;
              _dealt.removeAll(
                _Ids()
                  ..left.addAll(said.left)
                  ..categories.addAll(said.categories)
                  ..events.addAll(said.events),
              );
            },
            onError: (Object e, StackTrace st) {
              // Said again at the next launch rather than lost.
              debugPrint(
                '[ShareNoticeListener] kept notices not forgotten: $e\n$st',
              );
            },
          ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (ShareNoticeListener.routes._onChanged == _onRoutesChanged) {
      ShareNoticeListener.routes._onChanged = null;
    }
    unawaited(_notices?.cancel());
    unawaited(_prompts?.cancel());
    _barUp?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_sayNext());
      unawaited(_holdKept());
    }
  }

  /// What is in front changed: a notice that waited for a dialog, a sheet
  /// or an alert to go may be said, once the change is laid out.
  void _onRoutesChanged() {
    if (_nothingWaits && _hidden == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sayHidden();
      unawaited(_sayNext());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _keepToDatabase() {
    final generation = ShareService.databaseGeneration;
    if (_heldGeneration == generation) return;
    _heldGeneration = generation;
    _arrivedCategories.clear();
    _arrivedEvents.clear();
    _left.clear();
    _hidden = null;
    // Unsaid, they stay in the store of the database they arrived under.
    _kept.clear();
    _dealt.clear();
    _live.clear();
  }

  /// A hide of mine that took my alerts off, waiting only while an alert
  /// is in front or before a page is up (D30, A13): the latest, since each
  /// bar would take the one before it down.
  ShareHiddenWithAlerts? _hidden;

  /// Says [_hidden] at once, over whatever is in front — a sheet, a form
  /// sheet, a dialog — on the overlay road: it answers the person's own
  /// tap, so it is neither held for a resume nor queued behind another bar,
  /// and the next notice waits its time out. The surface whose switch asked
  /// for the hide may have closed since; nothing here needs it.
  void _sayHidden() {
    // A hide tells of the database it was made in, like every notice.
    _keepToDatabase();
    final hidden = _hidden;
    if (hidden == null) return;
    // Shown again while the bar waited: its alerts are armed again, and
    // "off until you show it again" would be said of nothing.
    if (!CalendarCategories.partnerHidden.contains(hidden.categoryId)) {
      _hidden = null;
      return;
    }
    if (widget.alertInFront()) return;
    final page = _pageInFront();
    if (page == null) return;
    _hidden = null;
    final l10n = AppLocalizations.of(page)!;
    final category = CalendarCategories.byId(hidden.categoryId);
    final label = category == null
        ? hidden.name
        : CalendarCategories.labelOf(category, l10n);
    CustomSnackbar.show(
      page,
      ShareCopy.sentence(l10n.shareHiddenAlertsOff(label)),
      duration: AppConstants.shareNoticeDuration,
      overSheet: true,
    );
    _barUp?.cancel();
    _holdBarTime();
  }

  void _hold(ShareNotice notice) {
    _keepToDatabase();
    switch (notice) {
      case ShareArrived(:final categoryIds, :final events):
        _arrivedCategories.addAll(categoryIds);
        _arrivedEvents.addAll({for (final e in events) e.id: e.title});
      case ShareLeftWithAlert(:final events, :final partnerName):
        // By id: told again, an event waits once, with what tells it last.
        for (final leaves in _left) {
          for (final event in events) {
            leaves.events.remove(event.id);
          }
        }
        _left.removeWhere((leaves) => leaves.events.isEmpty);
        // The name as it stood while the pair did (D35): once the partner
        // ends it the service names nobody, and such a leave joins the
        // ones before it. Only two names that differ part a bar.
        final last = _left.lastOrNull;
        final joins =
            last != null &&
            (partnerName == null ||
                last.name == null ||
                last.name == partnerName);
        final leaves = joins ? last : _Leaves();
        if (!joins && events.isNotEmpty) _left.add(leaves);
        leaves.name = partnerName ?? leaves.name;
        leaves.events.addAll({for (final e in events) e.id: e.title});
      case ShareHiddenWithAlerts(:final generation):
        // Made under another opening of the database — a switch came
        // during the alert pass that precedes the notice: said of nothing
        // that is open now.
        if (generation != null &&
            generation != ShareService.databaseGeneration) {
          return;
        }
        _hidden = notice;
        _sayHidden();
        return;
    }
    unawaited(_sayNext());
  }

  bool get _inFront {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  bool get _nothingWaits =>
      _left.isEmpty && _arrivedCategories.isEmpty && _arrivedEvents.isEmpty;

  /// A context inside the page in front, which is what picks the bar's road
  /// (`CustomSnackbar._showSnackBar`): the navigator's own sits above its
  /// overlay, where the road a non-resizing page takes finds no overlay.
  BuildContext? _pageInFront() {
    final navigator = AppNavigator.navigatorKey.currentState;
    if (navigator == null) return null;
    final routes = AppNavigator.routeObserver.pageRoutes;
    for (final route in routes.reversed) {
      if (route is ModalRoute &&
          route.isActive &&
          identical(route.navigator, navigator)) {
        return route.subtreeContext;
      }
    }
    return null;
  }

  /// The road a bar takes over what is in front, or null while it would go
  /// unseen or in the way. A page carries it on its Scaffold. Over sheets
  /// it takes the overlay, above them, and View closes them on its way —
  /// unless one is held by a `PopScope`: a form sheet may hold a draft,
  /// which a notice must never discard, so it waits, as it waits under a
  /// dialog or a menu and while an alert is in front.
  _Road? _road() {
    if (widget.alertInFront()) return null;
    final routes = ShareNoticeListener.routes.live;
    final page = routes.lastIndexWhere((route) => route is PageRoute);
    final above = routes.skip(page + 1);
    if (above.isEmpty) return _Road.page;
    final closable = above.every(
      (route) =>
          route is ModalBottomSheetRoute &&
          route.popDisposition != RoutePopDisposition.doNotPop,
    );
    return closable ? _Road.overSheet : null;
  }

  /// Arms [_barUp] for what is left of someone's bar with an action — an
  /// Undo — which a bar nobody asked for must not take down.
  bool _waitOutActionBar() {
    final until = CustomSnackbar.actionBarUntil;
    if (until == null || until == _actionBarWaited) return false;
    final left = until.difference(DateTime.now());
    if (left <= Duration.zero) return false;
    _actionBarWaited = until;
    _barUp = Timer(left, () {
      _barUp = null;
      unawaited(_sayNext());
    });
    return true;
  }

  /// Says what waits, the leave before the arrival: losing an alert is the
  /// one a person must not miss.
  ///
  /// No wait in a turn is without a bound
  /// ([AppConstants.shareNoticeCheckLimit]), and the turn is given up on
  /// every way out of it: one read that never answered — a service that
  /// never came up, a calendar that never loaded — held every later notice
  /// for good, the leaves included, and a return changed nothing.
  Future<void> _sayNext() async {
    _keepToDatabase();
    if (_barUp != null || _wording || !_inFront || _nothingWaits) return;
    if (_pageInFront() == null || _road() == null) return;
    if (_waitOutActionBar()) return;
    // Before the first wait: what the turn learns is this opening's.
    final generation = ShareService.databaseGeneration;
    // Whether the turn said nothing of what waits and looked at none of
    // it — held while it asked, or under a database opened meanwhile:
    // that gets a turn of its own, at once.
    var again = false;
    _wording = true;
    try {
      final service = await widget.shareService().timeout(
        AppConstants.shareNoticeCheckLimit,
      );
      if (!mounted) return;
      final partner = service.availability.audience?.displayName;
      if (ShareService.databaseGeneration != generation) {
        again = true;
        return;
      }
      // A leave asks nothing more: it tells of an alert of mine that went
      // off, and no check of an arrival stands between it and its bar.
      if (_left.isNotEmpty) {
        _say(partner);
        return;
      }
      final here = await _stillHere(service, generation);
      if (!mounted) return;
      again = !_say(partner, arrived: here);
    } on TimeoutException {
      // Tried again by the next notice, or the next return.
      debugPrint('[ShareNoticeListener] notice not said: no share service');
    } catch (e, st) {
      debugPrint('[ShareNoticeListener] notice not said: $e\n$st');
    } finally {
      _wording = false;
    }
    if (again && mounted) unawaited(_sayNext());
  }

  /// What arrived and is still here, of what waited when this was asked —
  /// the rest of that is dropped, at the moment it would be said (D23:
  /// arrival is news once): a category un-shared again while its bar
  /// waited — whose id the catalogue would read back as Other — and an
  /// event the calendar no longer holds as the partner's. A leave is never
  /// dropped: it tells of an alert of mine that went off.
  ///
  /// It answers for the ids it asked about and no others. A notice held
  /// while it waited is in neither answer: it stays for a turn of its own,
  /// which asks about it — said in this one's bar it was said unchecked,
  /// an arrival already gone again among them.
  ///
  /// Null when another database is open by the time the reads answer:
  /// what they say is of the one that was asked. And when they do not
  /// answer within the bound, everything asked about is "still here":
  /// nothing is dropped and nothing held back — an arrival that is gone
  /// may then be said, which costs less than a notice that never is.
  Future<_Ids?> _stillHere(ShareService service, int generation) async {
    final asked = _Ids()
      ..categories.addAll(_arrivedCategories)
      ..events.addAll(_arrivedEvents.keys);
    final _Ids here;
    try {
      here = await () async {
        // The catalogue first: a built-in read from an empty cache is
        // worded "Other".
        if (asked.categories.isNotEmpty) await widget.loadCategories();
        return _Ids()
          ..categories.addAll(
            asked.categories.isEmpty
                ? const <String>{}
                : await service.partnerSharesCategories(asked.categories),
          )
          ..events.addAll(
            asked.events.isEmpty
                ? const <String>{}
                : await widget.partnerEventsHeld(asked.events),
          );
      }().timeout(AppConstants.shareNoticeCheckLimit);
    } on TimeoutException {
      debugPrint('[ShareNoticeListener] arrivals said unchecked: no answer');
      return ShareService.databaseGeneration == generation ? asked : null;
    }
    if (ShareService.databaseGeneration != generation) return null;
    final undone = asked.without(here);
    _arrivedCategories.removeAll(undone.categories);
    undone.events.forEach(_arrivedEvents.remove);
    _dealtWith(categories: undone.categories);
    _dealtWith(events: undone.events);
    return asked.within(here);
  }

  /// Says the leaves that wait, else — of the arrivals — exactly [arrived]:
  /// the ones a turn has just asked about. False when nothing was said.
  bool _say(String? partner, {_Ids? arrived}) {
    _keepToDatabase();
    final page = _pageInFront();
    final road = _road();
    if (page == null || road == null || !_inFront || _nothingWaits) {
      return false;
    }
    final l10n = AppLocalizations.of(page)!;
    final name = ShareCopy.partnerName(l10n, partner);
    final overSheet = road == _Road.overSheet;
    if (_left.isNotEmpty) {
      final leaves = _left.removeAt(0);
      final leftName = ShareCopy.partnerName(l10n, leaves.name ?? partner);
      _sayLeft(page, l10n, leftName, leaves, overSheet: overSheet);
      return true;
    }
    if (arrived == null) return false;
    return _sayArrived(page, l10n, name, arrived, overSheet: overSheet);
  }

  void _sayLeft(
    BuildContext context,
    AppLocalizations l10n,
    String name,
    _Leaves leaves, {
    required bool overSheet,
  }) {
    final titles = leaves.events.values.toList();
    final ids = leaves.events.keys.toList();
    final message = titles.length == 1
        ? l10n.shareGoneWithAlert(name, titles.single)
        : l10n.shareGoneWithAlerts(titles.length, name);
    CustomSnackbar.show(
      context,
      ShareCopy.sentence(message),
      duration: AppConstants.shareNoticeDuration,
      overSheet: overSheet,
    );
    _dealtWith(left: ids);
    _holdBarTime();
  }

  bool _sayArrived(
    BuildContext context,
    AppLocalizations l10n,
    String name,
    _Ids checked, {
    required bool overSheet,
  }) {
    // Of what waits, what was asked about — in the order it arrived. The
    // rest stays where it is.
    final ids = [
      for (final id in _arrivedCategories)
        if (checked.categories.contains(id)) id,
    ];
    final eventIds = [
      for (final id in _arrivedEvents.keys)
        if (checked.events.contains(id)) id,
    ];
    if (ids.isEmpty && eventIds.isEmpty) return false;
    final titles = [for (final id in eventIds) _arrivedEvents[id]!];
    _arrivedCategories.removeAll(ids);
    eventIds.forEach(_arrivedEvents.remove);
    // A category carries more than any event beside it, so it is what the
    // bar names.
    final message = switch ((ids.length, titles.length)) {
      (1, _) => l10n.shareNewFromPartner(
        name,
        CalendarCategories.labelOf(
          CalendarCategories.resolve(ids.single),
          l10n,
        ),
      ),
      (> 1, _) => l10n.shareNewManyFromPartner(name, ids.length),
      (_, 1) => l10n.shareNewFromPartner(name, titles.single),
      _ => l10n.shareNewFromPartner(
        name,
        l10n.shareSummaryEvents(titles.length),
      ),
    };
    CustomSnackbar.showWithAction(
      context,
      message: ShareCopy.sentence(message),
      actionLabel: l10n.shareView,
      actionIdentifier: SemanticsIds.shareNoticeView,
      duration: AppConstants.shareNoticeDuration,
      onAction: _view,
      overSheet: overSheet,
    );
    _actionBarWaited = CustomSnackbar.actionBarUntil;
    _dealtWith(categories: ids, events: eventIds);
    _holdBarTime();
    return true;
  }

  void _holdBarTime() {
    final barTime =
        AppConstants.shareNoticeDuration + AppConstants.snackbarTransitions;
    _barUp = Timer(barTime, () {
      _barUp = null;
      unawaited(_sayNext());
    });
  }

  /// The Sharing page over the one Sync & sharing page, so back lands on the
  /// page the Pairing row is on. Asked again at the tap, since the bar on
  /// the overlay outlives what was in front when it was said: an alert come
  /// up since only takes the bar down, and so does a draft the way there
  /// would close ([_viewWouldCloseDraft]).
  void _view() {
    final context = AppNavigator.navigatorKey.currentContext;
    if (context == null || _road() == null) return;
    if (_viewWouldCloseDraft()) return;
    unawaited(AppNavigator.toSyncSettings(context, openSharing: true));
  }

  /// Whether a sheet held by a `PopScope` — a form that may hold a draft —
  /// lies above the Sync & sharing page View goes back to: going back
  /// closes everything above that page, draft and all. A held sheet under
  /// that page stays where it is, and with no such page in the stack only
  /// the sheets in front close, for which [_road] has answered.
  bool _viewWouldCloseDraft() {
    final routes = ShareNoticeListener.routes.live;
    final target = routes.lastIndexWhere(AppNavigator.isSyncSettingsRoute);
    if (target < 0) return false;
    return routes
        .skip(target + 1)
        .any(
          (route) =>
              route is! PageRoute &&
              route.popDisposition == RoutePopDisposition.doNotPop,
        );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Where a notice's bar is drawn: on the page's Scaffold, or on the
/// overlay above the sheets in front.
enum _Road { page, overSheet }

/// Leaves told with one name, by event id: one bar.
class _Leaves {
  String? name;
  final Map<String, String> events = {};
}

/// Ids of notices by their kind: an event that left, a category that
/// arrived, an event that arrived. One id may stand in two kinds at once —
/// an event told as left that arrived again — and each is its own notice.
class _Ids {
  final Set<String> left = {};
  final Set<String> categories = {};
  final Set<String> events = {};

  _Ids copy() => _Ids()..addAll(this);

  void addAll(_Ids other) {
    left.addAll(other.left);
    categories.addAll(other.categories);
    events.addAll(other.events);
  }

  void removeAll(_Ids other) {
    left.removeAll(other.left);
    categories.removeAll(other.categories);
    events.removeAll(other.events);
  }

  void clear() {
    left.clear();
    categories.clear();
    events.clear();
  }

  /// These ids that are also in [other], and that are not.
  _Ids within(_Ids other) => _Ids()
    ..left.addAll(left.intersection(other.left))
    ..categories.addAll(categories.intersection(other.categories))
    ..events.addAll(events.intersection(other.events));

  _Ids without(_Ids other) => _Ids()
    ..left.addAll(left.difference(other.left))
    ..categories.addAll(categories.difference(other.categories))
    ..events.addAll(events.difference(other.events));

  /// As the store is told of them.
  KeptNoticesSaid said() =>
      KeptNoticesSaid(left: left, categories: categories, events: events);
}

/// Every route on the app's navigator, popups included — the page routes
/// `AppRouteObserver` keeps leave out the sheet or dialog in front — and a
/// call back to [ShareNoticeListener] when they change, so a notice that
/// waits for a dialog or an alert is said once that has gone.
class ShareNoticeRoutes extends NavigatorObserver {
  final List<Route<dynamic>> _routes = [];
  VoidCallback? _onChanged;

  /// The routes on the navigator, bottom-first. A navigator torn down
  /// without popping leaves its routes behind, so they are shed here.
  List<Route<dynamic>> get live {
    _routes.removeWhere((route) => !route.isActive);
    return List.unmodifiable(_routes);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _onChanged?.call();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _onChanged?.call();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _onChanged?.call();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) _routes.removeAt(index);
    if (newRoute != null) {
      _routes.insert(index < 0 ? _routes.length : index, newRoute);
    }
    _onChanged?.call();
  }
}
