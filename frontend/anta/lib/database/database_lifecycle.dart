import 'package:flutter/foundation.dart';

/// Coordinates cleanup of database-scoped singleton state when the active
/// [AppDatabase] is closed or replaced (e.g. user switches between multiple
/// local databases on the settings page).
///
/// ## Problem this solves
///
/// Several services (`CounterService`, `CalendarEventService`,
/// `PublicHolidayService`, `SettingsService`, etc.) cache a `late AppDatabase`
/// reference and an in-memory mirror of selected tables. When the active
/// database is swapped out, those references point at a closed instance and
/// the caches reflect the wrong database. Without explicit reset the app
/// either crashes on the next DAO call or — worse — silently shows the
/// previous database's data.
///
/// Historically this was masked by forcing an app restart after every switch.
/// This registry makes singleton invalidation correct-by-construction so the
/// restart prompt becomes a UX convenience rather than a correctness crutch.
///
/// ## Usage
///
/// Each DB-backed singleton calls [registerResetHandler] inside its
/// `getInstance()` first-time-init block, passing its own static `reset`:
///
/// ```dart
/// static Future<MyService> getInstance() async {
///   if (_instance != null) return _instance!;
///   final service = MyService._();
///   service._db = await AppDatabase.getInstance();
///   await service._load();
///   _instance = service;
///   DatabaseLifecycle.registerResetHandler(reset);
///   return _instance!;
/// }
///
/// static void reset() => _instance = null;
/// ```
///
/// `AppDatabase.getInstance` calls [notifyDatabaseSwitching] before closing
/// the old instance; every registered handler fires, the registry is cleared,
/// and the next call to any service's `getInstance()` produces a fresh
/// instance bound to the new database (and re-registers itself).
class DatabaseLifecycle {
  DatabaseLifecycle._();

  static final List<VoidCallback> _resetHandlers = [];

  /// Registers a reset callback. Callbacks are invoked once per
  /// [notifyDatabaseSwitching] call in registration order, then cleared.
  ///
  /// Services should call this from their `getInstance()` first-time path so
  /// the handler is re-registered alongside each fresh singleton.
  static void registerResetHandler(VoidCallback handler) {
    _resetHandlers.add(handler);
  }

  /// Invokes all registered handlers and clears the registry. Called by
  /// [AppDatabase] when the active database is about to be closed.
  ///
  /// Individual handler failures are logged in debug builds but do not
  /// interrupt the rest of the cleanup — one misbehaving service must not
  /// leave others bound to a closed database.
  static void notifyDatabaseSwitching() {
    final handlers = List<VoidCallback>.from(_resetHandlers);
    _resetHandlers.clear();
    for (final handler in handlers) {
      try {
        handler();
      } catch (e, stack) {
        debugPrint('[DatabaseLifecycle] reset handler threw: $e\n$stack');
      }
    }
  }

  /// Test-only: number of currently registered handlers.
  @visibleForTesting
  static int get registeredHandlerCount => _resetHandlers.length;
}
