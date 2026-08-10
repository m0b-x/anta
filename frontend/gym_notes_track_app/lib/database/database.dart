import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../services/database_manager.dart';

import 'tables/folders_table.dart';
import 'tables/notes_table.dart';
import 'tables/content_chunks_table.dart';
import 'tables/sync_metadata_table.dart';
import 'tables/user_settings_table.dart';
import 'tables/counters_table.dart';
import 'tables/counter_values_table.dart';
import 'tables/calendar_events_table.dart';
import 'tables/public_holidays_table.dart';
import 'tables/calendar_categories_table.dart';
import 'tables/event_occurrences_table.dart';
import 'daos/folder_dao.dart';
import 'daos/note_dao.dart';
import 'daos/content_chunk_dao.dart';
import 'daos/sync_dao.dart';
import 'daos/user_settings_dao.dart';
import 'daos/counter_dao.dart';
import 'daos/calendar_event_dao.dart';
import 'daos/public_holiday_dao.dart';
import 'daos/calendar_category_dao.dart';
import 'daos/event_occurrence_dao.dart';
import 'crdt/hlc.dart';
import 'database_lifecycle.dart';
import 'loading_interceptor.dart';
import 'migrations/migrations.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Folders,
    Notes,
    ContentChunks,
    SyncMetadata,
    UserSettings,
    Counters,
    CounterValues,
    CalendarEvents,
    PublicHolidaysTable,
    CalendarCategories,
    EventOccurrenceDescriptions,
  ],
  daos: [
    FolderDao,
    NoteDao,
    ContentChunkDao,
    SyncDao,
    UserSettingsDao,
    CounterDao,
    CalendarEventDao,
    PublicHolidayDao,
    CalendarCategoryDao,
    EventOccurrenceDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  static AppDatabase? _instance;
  static String? _currentDatabaseName;

  final String _deviceId;
  late final HybridLogicalClock hlc;

  AppDatabase._internal(super.e, this._deviceId) {
    hlc = HybridLogicalClock(nodeId: _deviceId);
  }

  /// Builds a database over an arbitrary executor, bypassing [getInstance]'s
  /// singleton, `path_provider` lookup and device-id file.
  ///
  /// Exists so tests can run the real schema, the real migrations and the real
  /// DAOs against `NativeDatabase.memory()`. Never use it in app code — the
  /// singleton is what the `DatabaseLifecycle` reset contract is built on.
  @visibleForTesting
  factory AppDatabase.forTesting(
    QueryExecutor executor, {
    String deviceId = 'test-device',
  }) {
    return AppDatabase._internal(executor, deviceId);
  }

  static Future<AppDatabase> getInstance({String? databaseName}) async {
    final dbManager = await DatabaseManager.getInstance();
    final activeName = databaseName ?? dbManager.getActiveDatabaseName();

    // If instance exists and we're requesting a different database, close current one.
    // Notify lifecycle listeners FIRST so any singleton holding a `late AppDatabase`
    // reference (CounterService, CalendarEventService, etc.) drops it before we
    // close the underlying connection. Without this, the next access from a stale
    // singleton would hit a closed database.
    if (_instance != null && _currentDatabaseName != activeName) {
      DatabaseLifecycle.notifyDatabaseSwitching();
      await _instance!.close();
      _instance = null;
      _currentDatabaseName = null;
    }

    if (_instance != null) return _instance!;

    final deviceId = await _getOrCreateDeviceId();
    _instance = AppDatabase._internal(_openConnection(activeName), deviceId);
    _currentDatabaseName = activeName;
    return _instance!;
  }

  /// Closes the database and deletes all data files.
  /// After calling this, the app should be restarted.
  static Future<void> deleteAllData() async {
    // Close the current instance if it exists
    if (_instance != null) {
      DatabaseLifecycle.notifyDatabaseSwitching();
      await _instance!.close();
      _instance = null;
      _currentDatabaseName = null;
    }

    // Get the database folder path
    final dbFolder = await getApplicationDocumentsDirectory();
    final gymNotesDir = Directory(p.join(dbFolder.path, 'gym_notes'));

    // Delete the entire gym_notes directory (includes db, device_id, etc.)
    if (await gymNotesDir.exists()) {
      await gymNotesDir.delete(recursive: true);
    }
  }

  static Future<String> _getOrCreateDeviceId() async {
    final directory = await getApplicationDocumentsDirectory();
    final deviceFile = File(p.join(directory.path, 'gym_notes', 'device_id'));

    if (await deviceFile.exists()) {
      return await deviceFile.readAsString();
    }

    final deviceId = const Uuid().v4();
    await deviceFile.parent.create(recursive: true);
    await deviceFile.writeAsString(deviceId);
    return deviceId;
  }

  String get deviceId => _deviceId;

  @override
  int get schemaVersion => DatabaseSchema.currentVersion;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        await DatabaseIndexes(this).createAllIndexes();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        await DatabaseMigrations(this).runMigrations(m, from, to);
      },
    );
  }

  Future<void> rebuildFtsIndex() async {
    await customStatement("INSERT INTO notes_fts(notes_fts) VALUES('rebuild')");
  }

  Future<void> vacuum() async {
    await customStatement('VACUUM');
  }

  String generateHlc() {
    return hlc.now().toString();
  }

  String generateId() {
    return const Uuid().v4();
  }
}

LazyDatabase _openConnection(String databaseName) {
  return LazyDatabase(() async {
    final dbManager = await DatabaseManager.getInstance();
    final dbPath = await dbManager.getDatabasePath(databaseName);
    final file = File(dbPath);
    await file.parent.create(recursive: true);
    return NativeDatabase.createInBackground(
      file,
    ).interceptWith(LoadingQueryInterceptor());
  });
}
