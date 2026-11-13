import 'dart:async';

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../constants/calendar_categories.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/share_notice.dart';
import '../services/app_navigator.dart';
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
/// another — and said on the next resume. It opens no service until a
/// notice arrives, so an account that never paired pays one idle
/// subscription and nothing else.
class ShareNoticeListener extends StatefulWidget {
  final Widget child;

  /// Resolves the share service, for the partner's name; a seam for tests.
  final Future<ShareService> Function() shareService;

  const ShareNoticeListener({
    super.key,
    required this.child,
    this.shareService = ShareService.getInstance,
  });

  @override
  State<ShareNoticeListener> createState() => _ShareNoticeListenerState();
}

class _ShareNoticeListenerState extends State<ShareNoticeListener>
    with WidgetsBindingObserver {
  StreamSubscription<ShareNotice>? _notices;

  /// What waits to be said, in arrival order: a set, because a read that
  /// repeats what the last one found must not say a title twice.
  final Set<String> _arrivedCategories = {};
  final Set<String> _arrivedEvents = {};
  final Set<String> _left = {};

  /// Runs while a bar of this listener's is up: the helper takes the bar on
  /// screen down for the next one, so the next waits for this to end.
  Timer? _barUp;

  /// Set across the read of the partner's name, so a notice that lands in
  /// that gap merges into what waits rather than starting a second bar.
  bool _wording = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notices = ShareService.notices.listen(_hold);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_notices?.cancel());
    _barUp?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_sayNext());
  }

  void _hold(ShareNotice notice) {
    switch (notice) {
      case ShareArrived(:final categoryIds, :final eventTitles):
        _arrivedCategories.addAll(categoryIds);
        _arrivedEvents.addAll(eventTitles);
      case ShareLeftWithAlert(:final eventTitles):
        _left.addAll(eventTitles);
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

  /// Says what waits, the leave before the arrival: losing an alert is the
  /// one a person must not miss.
  Future<void> _sayNext() async {
    if (_barUp != null || _wording || !_inFront || _nothingWaits) return;
    if (_pageInFront() == null) return;
    _wording = true;
    try {
      final audience = (await widget.shareService()).availability.audience;
      if (mounted) _say(audience?.displayName);
    } catch (e) {
      debugPrint('[ShareNoticeListener] notice not said: $e');
    } finally {
      _wording = false;
    }
  }

  void _say(String? partner) {
    final page = _pageInFront();
    if (page == null || !_inFront) return;
    final l10n = AppLocalizations.of(page)!;
    final name = ShareCopy.partnerName(l10n, partner);
    if (_left.isNotEmpty) {
      _sayLeft(page, l10n, name);
    } else {
      _sayArrived(page, l10n, name);
    }
  }

  void _sayLeft(BuildContext context, AppLocalizations l10n, String name) {
    final titles = _left.toList();
    _left.clear();
    final message = titles.length == 1
        ? l10n.shareGoneWithAlert(name, titles.single)
        : l10n.shareGoneWithAlerts(titles.length, name);
    CustomSnackbar.show(
      context,
      ShareCopy.sentence(message),
      duration: AppConstants.shareNoticeDuration,
    );
    _holdBarTime();
  }

  void _sayArrived(BuildContext context, AppLocalizations l10n, String name) {
    final ids = _arrivedCategories.toList();
    final titles = _arrivedEvents.toList();
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
    );
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

  /// Sync & sharing, which opens its Sharing page on top, so back lands on
  /// the page the Pairing row is on; nothing more when it is already in
  /// front, where that row is.
  void _view() {
    final context = AppNavigator.navigatorKey.currentContext;
    if (context == null) return;
    unawaited(AppNavigator.toSyncSettings(context, openSharing: true));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
