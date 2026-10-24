import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;

import 'sync_engine.dart';

/// Feeds the app's lifecycle to the [SyncEngine]: leaving the foreground
/// drains the outbox at once — the process may not live long enough for the
/// debounce (readiness D19) — and coming back resumes the signal and runs.
///
/// Android passes through `inactive`, `hidden` and `paused` on one way out
/// and back through some of them on the way in, so the drain fires once per
/// leave and the resume once per return, not on every intermediate state —
/// and only while the engine is started. A leave is `hidden` or `paused`: a
/// lone `inactive` is a notification shade, a permission dialog or a desktop
/// focus change, and treating it as one cost a drain plus a full pull on
/// every return (S3c review F4).
class SyncLifecycleBridge {
  final SyncEngine _engine;
  late final StreamSubscription<AppLifecycleState> _subscription;
  bool _away = false;

  /// [lifecycle] is `PermissionService.appLifecycle()` in the app — one
  /// `AppLifecycleListener` while subscribed — and a controller in a test.
  SyncLifecycleBridge(this._engine, Stream<AppLifecycleState> lifecycle) {
    _subscription = lifecycle.listen(_onState);
  }

  void _onState(AppLifecycleState state) {
    // Built before DI starts the engine; until then there is nothing to
    // drain or resume, and a leave seen then is not owed a resume.
    if (!_engine.isStarted) return;
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
