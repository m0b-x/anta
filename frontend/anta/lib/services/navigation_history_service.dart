import 'dart:async';

import 'package:flutter/widgets.dart';

import '../database/database_lifecycle.dart';
import '../models/nav_destination.dart';
import 'settings_service.dart';

/// Keeps the persisted "where the user was" stack in step with the live
/// navigator.
///
/// The previous design recorded from inside the `AppNavigator.to*` helpers,
/// which see pushes but not pops — the system back gesture, app-bar back
/// buttons and stray `Navigator.pop` calls all went unnoticed, and a single
/// `RouteAware.didPopNext` hook on the folder page papered over the gap. A
/// [NavigatorObserver] sees push, pop, replace and remove symmetrically from
/// one place, which is why recording lives here now.
///
/// Writes are debounced and coalesced: navigation is bursty and this lands in
/// SQLite. The debounce is what makes [flush] on `AppLifecycleState.paused`
/// load-bearing rather than polish — Android kills paused processes, and that
/// moment is the entire point of the feature.
class NavigationHistoryService {
  NavigationHistoryService({
    Duration writeDebounce = const Duration(milliseconds: 400),
  }) : _writeDebounce = writeDebounce {
    DatabaseLifecycle.registerResetHandler(_handleDatabaseSwitch);
  }

  final Duration _writeDebounce;

  List<NavDestination> _current = const [];
  String? _lastQueued;
  Timer? _timer;
  bool _recording = false;
  Future<void> _writeChain = Future<void>.value();

  /// The stack as it currently stands, bottom-to-top. Not necessarily what is
  /// on disk yet — see [flush].
  List<NavDestination> get stack => List.unmodifiable(_current);

  /// Whether writes are enabled yet. See [beginRecording].
  bool get isRecording => _recording;

  /// Opens the write path, and schedules the first write.
  ///
  /// Nothing may be persisted before this: mounting the root page publishes an
  /// *empty* stack, and if that write won the race against restore reading the
  /// stored value, the app would erase the location it was about to reopen.
  /// So `AppNavigator.restoreLastLocation` calls this only once it has read
  /// the stack and queued the replay — and `main.dart` calls it on the paths
  /// where restore does not run at all.
  ///
  /// The first write is debounced rather than immediate so the replay's pushes
  /// are certain to have been observed: what it then persists is what actually
  /// landed, which is how a chain truncated by a deleted folder heals itself
  /// without restore having to write anything back.
  void beginRecording() {
    if (_recording) return;
    _recording = true;
    _schedule();
  }

  /// Called by [NavigationHistoryObserver] whenever the navigator's set of
  /// restorable routes changes. Cheap and synchronous; the write is deferred.
  void onStackChanged(List<NavDestination> stack) {
    _current = List.unmodifiable(stack);
    _schedule();
  }

  void _schedule() {
    if (!_recording) return;
    _timer?.cancel();
    _timer = Timer(_writeDebounce, flush);
  }

  /// Persists the pending stack now. Safe to call at any time; returns the
  /// in-flight write so tests and the lifecycle hook can await it.
  ///
  /// Identical consecutive states are dropped, and writes are chained rather
  /// than fired in parallel — fast navigation used to leave the last write to
  /// chance.
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    if (!_recording) return _writeChain;

    final stack = _current;
    final encoded = NavDestination.encodeStack(stack);
    if (encoded == _lastQueued) return _writeChain;
    _lastQueued = encoded;

    _writeChain = _writeChain
        .then((_) async {
          final settings = await SettingsService.getInstance();
          await settings.saveLastLocationStack(stack);
        })
        .catchError((Object error, StackTrace stack) {
          debugPrint('[NavigationHistoryService] write failed: $error');
        });
    return _writeChain;
  }

  /// Drops everything on a database switch: the recorded ids belong to the
  /// database being closed, and writing them into the new one would restore a
  /// folder that exists only in the other database. Re-registers itself
  /// because [DatabaseLifecycle] clears its registry after each notification.
  void _handleDatabaseSwitch() {
    _timer?.cancel();
    _timer = null;
    _current = const [];
    _lastQueued = null;
    DatabaseLifecycle.registerResetHandler(_handleDatabaseSwitch);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Translates navigator events into the restorable stack.
///
/// It never inspects page types. Every restorable route is stamped by
/// `AppNavigator` with a [NavDestination] in its `RouteSettings.arguments`, so
/// the whole decision is "is this route stamped?". Modal sheets and dialogs
/// are `PopupRoute`s and are invisible here by construction.
class NavigationHistoryObserver extends NavigatorObserver {
  NavigationHistoryObserver(this._history);

  final NavigationHistoryService _history;

  /// Page routes above (and including) the root, in push order. Kept as
  /// routes rather than destinations so an unstamped page route still holds
  /// its place — that is what enforces the coherent-chain rule below.
  final List<Route<dynamic>> _pageRoutes = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PageRoute) return;
    _pageRoutes.add(route);
    _publish();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_pageRoutes.remove(route)) _publish();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_pageRoutes.remove(route)) _publish();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _pageRoutes.indexOf(oldRoute);
    if (index < 0) return;
    if (newRoute is PageRoute) {
      _pageRoutes[index] = newRoute;
    } else {
      _pageRoutes.removeAt(index);
    }
    _publish();
  }

  /// The stack is the longest **prefix** of stamped routes above the root
  /// page, not every stamped route on the navigator.
  ///
  /// Taking a prefix is what handles the pages restore cannot rebuild — a
  /// shortcut editor carrying an `onSave` closure, a counter page carrying a
  /// live `Counter`. They are unstamped, so anything pushed above them stops
  /// being recorded, and restore lands the user on the deepest ancestor it
  /// can honestly rebuild instead of a chain with a hole in it.
  void _publish() {
    final stack = <NavDestination>[];
    for (var i = 1; i < _pageRoutes.length; i++) {
      final destination = _pageRoutes[i].settings.arguments;
      if (destination is! NavDestination) break;
      stack.add(destination);
    }
    _history.onStackChanged(stack);
  }
}
