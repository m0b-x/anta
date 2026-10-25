import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;

import 'sync_engine.dart';

/// Feeds the app's lifecycle to the [SyncEngine]: leaving the foreground
/// drains the outbox at once — the process may not live long enough for the
/// debounce (readiness D19) — and coming back resumes the signal and runs.
///
/// Android passes through `inactive`, `hidden` and `paused` on one way out
/// and back through some of them on the way in, so the drain fires once per
/// leave and the resume once per return, not on every intermediate state.
/// A stopped engine hears them too: it runs nothing, but a later start must
/// know whether the app is in the foreground (S3d review M4). A leave is
/// `hidden` or `paused`: a lone `inactive` is a notification shade, a
/// permission dialog or a desktop focus change, and treating it as one cost
/// a drain plus a full pull on every return (S3c review F4).
class SyncLifecycleBridge {
  final SyncEngine _engine;
  late final StreamSubscription<AppLifecycleState> _subscription;
  bool _away;

  /// [lifecycle] is `PermissionService.appLifecycle()` in the app — one
  /// `AppLifecycleListener` while subscribed — and a controller in a test.
  /// [initial] is the state the app is in now: the listener reports changes
  /// only, and a bridge built while away must still hear the return as one
  /// (S5 review M7).
  SyncLifecycleBridge(
    this._engine,
    Stream<AppLifecycleState> lifecycle, {
    AppLifecycleState? initial,
  }) : _away = isLeave(initial) {
    _subscription = lifecycle.listen(_onState);
  }

  /// Whether [state] means the app left the foreground — the bridge's rule
  /// and the one the engine's [SyncEngine.start] reads the current state by.
  static bool isLeave(AppLifecycleState? state) =>
      state == AppLifecycleState.hidden || state == AppLifecycleState.paused;

  void _onState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_away) return;
        _away = false;
        _engine.onAppResumed();
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (_away) return;
        _away = true;
        unawaited(_engine.onAppBackgrounded());
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> dispose() => _subscription.cancel();
}
