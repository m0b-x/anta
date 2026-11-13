import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../constants/calendar_categories.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/share_notice.dart';
import '../services/app_navigator.dart';
import '../services/category_service.dart';
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

  /// What is in front on the app's navigator, in `main.dart`'s
  /// `navigatorObservers`.
  static final ShareNoticeRoutes routes = ShareNoticeRoutes();

  const ShareNoticeListener({
    super.key,
    required this.child,
    this.shareService = ShareService.getInstance,
    this.loadCategories = CategoryService.getInstance,
    this.alertInFront = _noAlert,
  });

  static bool _noAlert() => false;

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
  final Map<String, String> _left = {};

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (ShareNoticeListener.routes._onChanged == _onRoutesChanged) {
      ShareNoticeListener.routes._onChanged = null;
    }
    unawaited(_notices?.cancel());
    _barUp?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_sayNext());
  }

  /// What is in front changed: a notice that waited for a dialog, a sheet
  /// or an alert to go may be said, once the change is laid out.
  void _onRoutesChanged() {
    if (_nothingWaits) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_sayNext());
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
  }

  void _hold(ShareNotice notice) {
    _keepToDatabase();
    switch (notice) {
      case ShareArrived(:final categoryIds, :final events):
        _arrivedCategories.addAll(categoryIds);
        _arrivedEvents.addAll({for (final e in events) e.id: e.title});
      case ShareLeftWithAlert(:final events):
        _left.addAll({for (final e in events) e.id: e.title});
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
  Future<void> _sayNext() async {
    _keepToDatabase();
    if (_barUp != null || _wording || !_inFront || _nothingWaits) return;
    if (_pageInFront() == null || _road() == null) return;
    if (_waitOutActionBar()) return;
    _wording = true;
    try {
      final audience = (await widget.shareService()).availability.audience;
      if (_arrivedCategories.isNotEmpty) await widget.loadCategories();
      if (mounted) _say(audience?.displayName);
    } catch (e, st) {
      debugPrint('[ShareNoticeListener] notice not said: $e\n$st');
    } finally {
      _wording = false;
    }
  }

  void _say(String? partner) {
    _keepToDatabase();
    final page = _pageInFront();
    final road = _road();
    if (page == null || road == null || !_inFront || _nothingWaits) return;
    final l10n = AppLocalizations.of(page)!;
    final name = ShareCopy.partnerName(l10n, partner);
    final overSheet = road == _Road.overSheet;
    if (_left.isNotEmpty) {
      _sayLeft(page, l10n, name, overSheet: overSheet);
    } else {
      _sayArrived(page, l10n, name, overSheet: overSheet);
    }
  }

  void _sayLeft(
    BuildContext context,
    AppLocalizations l10n,
    String name, {
    required bool overSheet,
  }) {
    final titles = _left.values.toList();
    _left.clear();
    final message = titles.length == 1
        ? l10n.shareGoneWithAlert(name, titles.single)
        : l10n.shareGoneWithAlerts(titles.length, name);
    CustomSnackbar.show(
      context,
      ShareCopy.sentence(message),
      duration: AppConstants.shareNoticeDuration,
      overSheet: overSheet,
    );
    _holdBarTime();
  }

  void _sayArrived(
    BuildContext context,
    AppLocalizations l10n,
    String name, {
    required bool overSheet,
  }) {
    final ids = _arrivedCategories.toList();
    final titles = _arrivedEvents.values.toList();
    _arrivedCategories.clear();
    _arrivedEvents.clear();
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
    _holdBarTime();
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
