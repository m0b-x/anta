import 'dart:convert';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../models/dev_options.dart';

/// Service for persisting developer options settings
class DevOptionsService {
  static const String _settingsKey = 'dev_options';

  static DevOptionsService? _instance;
  static Future<DevOptionsService> getInstance() async {
    if (_instance == null) {
      _instance = DevOptionsService._();
      await _instance!._init();
      DatabaseLifecycle.registerResetHandler(reset);
    }
    return _instance!;
  }

  /// Drops the cached singleton so the next [getInstance] rebinds to the
  /// currently-active [AppDatabase]. Invoked by [DatabaseLifecycle] when the
  /// active database changes.
  static void reset() {
    _instance = null;
  }

  DevOptionsService._();

  late final AppDatabase _db;

  Future<void> _init() async {
    _db = await AppDatabase.getInstance();
    await _loadOptions();
  }

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
