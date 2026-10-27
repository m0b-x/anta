import 'package:flutter/foundation.dart';

import 'database.dart';

/// Runs when a switched-to database has opened, with that database.
typedef DatabaseSwitchedHandler = void Function(AppDatabase database);

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

  static int _generation = 0;

  /// Bumped by every [notifyDatabaseSwitching]. A `getInstance()` that awaits
  /// several things compares it before and after: a reset that landed
  /// between them means what it awaited first may belong to a database that
  /// is closing, and registering a singleton over it would outlive the reset
  /// meant to drop it.
  static int get generation => _generation;

  /// Registers a reset callback. Callbacks are invoked once per
  /// [notifyDatabaseSwitching] call in registration order, then cleared.
  ///
  /// Services should call this from their `getInstance()` first-time path so
  /// the handler is re-registered alongside each fresh singleton.
  ///
  /// Registering the same handler twice is a no-op. A service that resets and
  /// re-initializes *within* one database lifetime — a backup restore does
  /// exactly that, so the restored rows reach its cache — would otherwise
  /// leave a duplicate behind on every pass.
  static void registerResetHandler(VoidCallback handler) {
    if (_resetHandlers.contains(handler)) return;
    _resetHandlers.add(handler);
  }

  /// Invokes all registered handlers and clears the registry. Called by
  /// [AppDatabase] when the active database is about to be closed.
  ///
  /// Individual handler failures are logged in debug builds but do not
  /// interrupt the rest of the cleanup — one misbehaving service must not
  /// leave others bound to a closed database.
  static void notifyDatabaseSwitching() {
    _generation++;
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

  static final List<DatabaseSwitchedHandler> _switchedHandlers = [];

  /// Registers [handler] to run each time a switched-to database has opened.
  /// Unlike a reset handler it is kept across switches: it is how something
  /// that must run without anyone asking for it — the sync engine — comes
  /// back on the new database (S4a review M5). Registering twice is a no-op.
  static void registerSwitchedHandler(DatabaseSwitchedHandler handler) {
    if (_switchedHandlers.contains(handler)) return;
    _switchedHandlers.add(handler);
  }

  /// Invokes every switched handler with [database], after
  /// [notifyDatabaseSwitching] and that database's open. Called by
  /// [AppDatabase]; failures are logged and do not stop the others.
  ///
  /// The handle is passed rather than looked up: a handler that asked
  /// [AppDatabase.getInstance] for it would join the open it is announced
  /// from and only rebind a turn later, racing every other handler's first
  /// await (A6 review R113).
  static void notifyDatabaseSwitched(AppDatabase database) {
    for (final handler in List<DatabaseSwitchedHandler>.from(
      _switchedHandlers,
    )) {
      try {
        handler(database);
      } catch (e, stack) {
        debugPrint('[DatabaseLifecycle] switched handler threw: $e\n$stack');
      }
    }
  }

  /// Test-only: drops a switched handler a test registered.
  @visibleForTesting
  static void unregisterSwitchedHandler(DatabaseSwitchedHandler handler) =>
      _switchedHandlers.remove(handler);

  /// Test-only: number of currently registered handlers.
  @visibleForTesting
  static int get registeredHandlerCount => _resetHandlers.length;
}
