import 'dart:convert';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../models/dev_options.dart';

/// Service for persisting developer options settings
class DevOptionsService {
  static const String _settingsKey = 'dev_options';

  static DevOptionsService? _instance;

  /// The open in flight, shared by every caller that arrives before it
  /// finishes.
  static Future<DevOptionsService>? _opening;

  /// Published only once its options are loaded, the `SettingsService`
  /// shape: stored before the await, a second caller in that window got a
  /// service whose `_db` was not yet initialized and options not yet read.
  static Future<DevOptionsService> getInstance() {
    final existing = _instance;
    if (existing != null) return Future.value(existing);
    final inFlight = _opening;
    if (inFlight != null) return inFlight;
    final opening = _open();
    _opening = opening;
    // Only this open's own entry is cleared: a reset during it may already
    // have let a newer open take the slot.
    void settle() {
      if (identical(_opening, opening)) _opening = null;
    }

    opening.then<void>((_) => settle(), onError: (Object _) => settle());
    return opening;
  }

  /// How many times [_open] starts over before it gives up on a database
  /// that keeps switching under it.
  static const int _openAttempts = 3;

  /// A switch landing during the open starts it over, so a service over the
  /// closing database is never published. The options are read again from
  /// the one switched to when it stores any; one that stores none leaves
  /// the global as the last load set it, as before this shape.
  static Future<DevOptionsService> _open() async {
    for (var attempt = 0; attempt < _openAttempts; attempt++) {
      final generation = DatabaseLifecycle.generation;
      final db = await AppDatabase.getInstance();
      if (_instance case final raced?) return raced;
      if (DatabaseLifecycle.generation != generation) continue;
      final service = DevOptionsService._().._db = db;
      await service._loadOptions();
      if (_instance case final raced?) return raced;
      if (DatabaseLifecycle.generation != generation) continue;
      _instance = service;
      DatabaseLifecycle.registerResetHandler(reset);
      return service;
    }
    throw StateError('the database switched while dev options were opened');
  }

  /// Drops the cached singleton so the next [getInstance] rebinds to the
  /// currently-active [AppDatabase]. Invoked by [DatabaseLifecycle] when the
  /// active database changes.
  static void reset() {
    _instance = null;
    _opening = null;
  }

  DevOptionsService._();

  late final AppDatabase _db;

  Future<void> _loadOptions() async {
    final json = await _db.userSettingsDao.getValue(_settingsKey);
    if (json != null) {
      try {
        final map = Map<String, bool>.from(jsonDecode(json));
        DevOptions.instance.loadFromMap(map);
      } catch (_) {
        // Invalid data, use defaults
      }
    }
  }

  Future<void> saveOptions() async {
    final json = jsonEncode(DevOptions.instance.toMap());
    await _db.userSettingsDao.setValue(_settingsKey, json);
  }

  Future<void> resetOptions() async {
    DevOptions.instance.resetAll();
    await _db.userSettingsDao.deleteValue(_settingsKey);
  }
}
