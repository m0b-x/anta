import 'package:flutter/foundation.dart';

/// What the app knows about the phone's lock screen, and whether the one
/// surface allowed on top of it is showing.
///
/// A ringing alarm lifts the whole activity above the keyguard — there is one
/// activity, so there is nothing smaller to lift. The alarm page is meant to be
/// what the lock screen then shows, but it is a route like any other: for a
/// moment before it is pushed, after it is popped, or whenever something else
/// lands above it, the page underneath is on a locked phone and takes touches
/// without a PIN. [mustCover] is the rule that closes those moments — **locked,
/// and no alarm page on top** — and `LockScreenCurtain` is what enforces it.
///
/// Outside GetIt, like `PendingNavigationQueue`: the platform's pushes arrive
/// through a static-shaped channel handler, it holds no database reference, and
/// a widget above the navigator has to be able to read it before anything is
/// registered.
class LockScreenState {
  LockScreenState();

  /// The app-wide instance.
  static final LockScreenState instance = LockScreenState();

  final ValueNotifier<bool> _locked = ValueNotifier<bool>(false);

  final ValueNotifier<bool> _alarmOnTop = ValueNotifier<bool>(false);

  /// The alarm pages that are the topmost page route right now. A set of
  /// owners rather than a count, so a page reporting twice cannot leave the
  /// curtain open after it is gone.
  final Set<Object> _alarmSurfaces = <Object>{};

  /// Asks the platform again. Wired by `main.dart`; null wherever nothing can
  /// answer, which leaves [locked] where it is.
  Future<bool> Function()? query;

  /// Whether the lock screen is up, as last reported. False until the platform
  /// says otherwise — and always false where there is no lock screen to ask.
  bool get locked => _locked.value;

  /// Whether an alarm page is the topmost page route.
  bool get alarmOnTop => _alarmOnTop.value;

  /// Whether the app's content has to stay hidden right now.
  bool get mustCover => locked && !alarmOnTop;

  /// Notifies when either input of [mustCover] moves.
  late final Listenable changes = Listenable.merge(<Listenable>[
    _locked,
    _alarmOnTop,
  ]);

  /// Records what the platform reported.
  void setLocked(bool locked) => _locked.value = locked;

  /// Re-reads the lock screen from the platform. A failed read leaves the last
  /// answer standing: a curtain that stays is a nuisance, one that lifts on an
  /// error shows the app to whoever is holding a locked phone.
  Future<void> refresh() async {
    final ask = query;
    if (ask == null) return;
    try {
      _locked.value = await ask();
    } catch (e) {
      debugPrint('[LockScreenState] lock screen query failed: $e');
    }
  }

  /// [owner]'s alarm page became the topmost page route.
  void alarmSurfaceShown(Object owner) {
    _alarmSurfaces.add(owner);
    _alarmOnTop.value = true;
  }

  /// [owner]'s alarm page was covered by another page, or is gone.
  void alarmSurfaceHidden(Object owner) {
    _alarmSurfaces.remove(owner);
    _alarmOnTop.value = _alarmSurfaces.isNotEmpty;
  }

  /// Returns to the launch state. Test-only: the instance is process-global.
  @visibleForTesting
  void resetForTesting() {
    _alarmSurfaces.clear();
    _alarmOnTop.value = false;
    _locked.value = false;
    query = null;
  }
}
