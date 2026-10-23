import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/common.dart';
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
import 'tables/event_absences_table.dart';
import 'tables/event_skips_table.dart';
import 'tables/event_alerts_table.dart';
import 'tables/alert_registrations_table.dart';
import 'tables/calendar_filter_presets_table.dart';
import 'tables/overview_views_table.dart';
import 'tables/calendar_category_alerts_table.dart';
import 'tables/event_digests_table.dart';
import 'tables/event_templates_table.dart';
import 'tables/vocabularies_table.dart';
import 'tables/vocabulary_items_table.dart';
import 'tables/sync_outbox_table.dart';
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
import 'daos/event_absence_dao.dart';
import 'daos/event_template_dao.dart';
import 'daos/filter_preset_dao.dart';
import 'daos/overview_view_dao.dart';
import 'daos/event_skip_dao.dart';
import 'daos/event_alert_dao.dart';
import 'daos/alert_registration_dao.dart';
import 'daos/category_alert_dao.dart';
import 'daos/event_digest_dao.dart';
import 'daos/vocabulary_dao.dart';
import 'daos/sync_outbox_dao.dart';
import 'crdt/crdt_write.dart';
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
    EventAbsences,
    EventTemplates,
    CalendarFilterPresets,
    OverviewViews,
    EventSkips,
    EventAlerts,
    AlertRegistrations,
    Vocabularies,
    VocabularyItems,
    CalendarCategoryAlerts,
    EventDigests,
    SyncOutbox,
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
    EventAbsenceDao,
    EventTemplateDao,
    FilterPresetDao,
    OverviewViewDao,
    EventSkipDao,
    EventAlertDao,
    AlertRegistrationDao,
    VocabularyDao,
    CategoryAlertDao,
    EventDigestDao,
    SyncOutboxDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  static String? _currentDatabaseName;

  final String _deviceId;
  late final HybridLogicalClock hlc;

  AppDatabase._internal(
    super.e,
    this._deviceId, {
    DateTime Function()? wallClock,
  }) {
    hlc = HybridLogicalClock(nodeId: _deviceId, wallClock: wallClock);
  }

  /// Builds a database over an arbitrary executor, bypassing [getInstance]'s
  /// singleton, `path_provider` lookup and device-id file.
  ///
  /// Exists so tests can run the real schema, the real migrations and the real
  /// DAOs against `NativeDatabase.memory()`. Never use it in app code — the
  /// singleton is what the `DatabaseLifecycle` reset contract is built on.
  /// [wallClock] lets a test put the wall clock behind a stored stamp.
  @visibleForTesting
  factory AppDatabase.forTesting(
    QueryExecutor executor, {
    String deviceId = 'test-device',
    DateTime Function()? wallClock,
  }) {
    return AppDatabase._internal(executor, deviceId, wallClock: wallClock);
  }

  /// The open in flight or done, shared by every caller of [getInstance] for
  /// [_currentDatabaseName], so two first callers never build two instances
  /// and none is handed an instance before its clock is seeded.
  static Future<AppDatabase>? _opening;

  static Future<AppDatabase> getInstance({String? databaseName}) async {
    final dbManager = await DatabaseManager.getInstance();
    final activeName = databaseName ?? dbManager.getActiveDatabaseName();

    final current = _opening;
    if (current != null && _currentDatabaseName == activeName) return current;

    // Set before the first await, so a concurrent caller joins this open.
    final opening = _open(activeName, previous: current);
    _opening = opening;
    _currentDatabaseName = activeName;
    try {
      return await opening;
    } catch (_) {
      if (identical(_opening, opening)) {
        _opening = null;
        _currentDatabaseName = null;
      }
      rethrow;
    }
  }

  /// Opens [name] once the [previous] database, if any, is closed.
  ///
  /// When switching, lifecycle listeners are notified FIRST so any singleton
  /// holding a `late AppDatabase` reference (CounterService,
  /// CalendarEventService, etc.) drops it before the underlying connection
  /// closes; without this, the next access from a stale singleton would hit
  /// a closed database. The previous open is awaited before the notice, so a
  /// singleton already waiting on it has received and cached its instance
  /// by the time the notice tells it to drop that instance.
  static Future<AppDatabase> _open(
    String name, {
    Future<AppDatabase>? previous,
  }) async {
    if (previous != null) {
      try {
        await previous;
      } catch (_) {
        // A failed open left nothing to drop; _closeOpened skips it too.
      }
      DatabaseLifecycle.notifyDatabaseSwitching();
      await _closeOpened(previous);
    }
    final deviceId = await _getOrCreateDeviceId();
    final db = AppDatabase._internal(_openConnection(name), deviceId);
    try {
      await db.seedClockFromStore();
    } catch (_) {
      await db.close();
      rethrow;
    }
    return db;
  }

  /// Closes what [opening] produced; an open that failed left nothing open.
  static Future<void> _closeOpened(Future<AppDatabase> opening) async {
    final AppDatabase db;
    try {
      db = await opening;
    } catch (_) {
      return;
    }
    await db.close();
  }

  /// Closes the database and deletes all data files.
  /// After calling this, the app should be restarted.
  static Future<void> deleteAllData() async {
    // Close the current instance if it exists. The memo outlives the close: a
    // reset singleton asking for the database
    // meanwhile joins the closing instance instead of opening a fresh one
    // that would write into the directory being deleted.
    final opening = _opening;
    if (opening != null) {
      try {
        await opening;
      } catch (_) {
        // Nothing was opened; there is nothing to drop.
      }
      DatabaseLifecycle.notifyDatabaseSwitching();
      await _closeOpened(opening);
      if (identical(_opening, opening)) {
        _opening = null;
        _currentDatabaseName = null;
      }
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
        // Before any step, so the stamps a step backfills sort above every
        // stamp the previous run wrote, as a local write's would. Only the
        // stored clock: the tables a row scan reads may not exist yet.
        await _seedFromLastHlc();
        Object? migrationError;
        try {
          await DatabaseMigrations(this).runMigrations(m, from, to);
          // Every table exists now. An install from before the clock was
          // stored has no `last_hlc`, so the persist below would store a
          // wall-based clock and the open's row scan would never run.
          await _seedFromRows();
        } catch (e) {
          migrationError = e;
          rethrow;
        } finally {
          // Each step commits on its own, so a later step that fails must
          // still leave the stamps the earlier ones backfilled covered. A
          // failed persist never hides the migration's own error.
          try {
            await persistClock();
          } catch (e) {
            if (migrationError == null) rethrow;
            debugPrint(
              '[AppDatabase] clock not stored after failed upgrade: $e',
            );
          }
        }
      },
    );
  }

  /// Raises the clock to the last stamp a previous run stored, so the first
  /// stamp of this run sorts above it even when the wall clock is behind.
  /// For a schema already current: a database whose rows predate the stored
  /// clock (a v43 install from before it was kept) is seeded once from its
  /// highest row stamp, which is then stored so the scan never runs again.
  Future<void> seedClockFromStore() async {
    if (await _seedFromLastHlc()) return;
    await _seedFromRows();
    await persistClock();
  }

  /// Raises the clock to the highest stamp any synced row carries; every
  /// synced table must exist.
  Future<void> _seedFromRows() async {
    final highest = await syncOutboxDao.maxHlc();
    if (highest == null) return;
    try {
      hlc.seed(HlcTimestamp.parse(highest));
    } on FormatException catch (e) {
      debugPrint('[AppDatabase] ignoring unreadable row stamp: $e');
    }
  }

  /// Seeds from `last_hlc` and says whether one was stored. An unreadable
  /// value is deleted: one that sorts above every stamp would otherwise fail
  /// the forward-only write for good, and the clock would never be stored.
  Future<bool> _seedFromLastHlc() async {
    final stored = await syncDao.getValue(SyncDao.keyLastHlc);
    if (stored == null) return false;
    try {
      hlc.seed(HlcTimestamp.parse(stored));
      return true;
    } on FormatException catch (e) {
      debugPrint('[AppDatabase] dropping unreadable last_hlc: $e');
      await syncDao.deleteValue(SyncDao.keyLastHlc);
      return false;
    }
  }

  /// How far the clock seeded at open was ahead of the wall clock.
  Duration get clockSeedAhead => hlc.seedAhead;

  /// How many remote stamps the clock held back for running too far ahead.
  int get clockClampedRemotes => hlc.clampedRemotes;

  /// How far ahead of the wall clock a remote stamp may run before the clock
  /// holds it back — the line past which a seed is worth reporting.
  static const Duration clockMaxDrift = HybridLogicalClock.maxDrift;

  Future<void> rebuildFtsIndex() async {
    await customStatement("INSERT INTO notes_fts(notes_fts) VALUES('rebuild')");
  }

  Future<void> vacuum() async {
    await customStatement('VACUUM');
  }

  /// The HLC a migration step backfills onto rows that predate their CRDT
  /// columns — for `DatabaseMigrations` alone. Such rows are not local edits
  /// and queue nothing; every write on a synced table takes its stamp from
  /// `CrdtWrite` instead, which is what queues it for the push.
  String migrationBackfillHlc() {
    return hlc.now().toString();
  }

  String generateId() {
    return const Uuid().v4();
  }
}

/// Connection pragmas, applied to every database this app opens.
///
/// Must stay a **top-level** function: `createInBackground` runs the database
/// on its own isolate and sends this across, which a capturing closure cannot
/// survive.
///
/// Measured on a real file (200 individually-committed inserts — the auto-save
/// shape of many small writes):
///
/// | setup                     | 200 single commits | 500 in one txn |
/// | ------------------------- | ------------------ | -------------- |
/// | stock defaults            | 561 ms             | 42 ms          |
/// | `WAL`                     | 139 ms             | 28 ms          |
/// | `WAL` + `synchronous=NORMAL` | 28 ms           | 22 ms          |
/// | + cache + temp_store      | 26 ms              | 19 ms          |
///
/// **Durability trade-off, stated plainly:** `synchronous = NORMAL` is only
/// safe *because* of WAL, and it is the combination SQLite documents as such.
/// An app crash or kill loses nothing — the WAL is already handed to the OS.
/// A power cut or kernel panic may roll back the last transactions, but the
/// database cannot corrupt. For an offline-first log that auto-saves
/// constantly, losing a second of typing to a power cut beats an fsync on
/// every keystroke's save.
///
/// `DatabaseManager` already renames and deletes the `-wal` / `-shm` sidecars
/// alongside the main file, so the multi-database feature stays correct.
@visibleForTesting
void configureSqliteConnection(CommonDatabase database) {
  // Write-ahead logging: readers no longer block on the writer, and a commit
  // appends instead of rewriting a rollback journal.
  database.execute('PRAGMA journal_mode = WAL');
  // One fsync per checkpoint rather than per commit. See the doc above.
  database.execute('PRAGMA synchronous = NORMAL');
  // Keeps `ORDER BY` spills (the folder list sorted by title/date builds a
  // temp B-tree) off the filesystem.
  database.execute('PRAGMA temp_store = MEMORY');
  // Negative = kibibytes rather than pages, so this is ~4 MB regardless of
  // page size. Contributed the least of the four; sized conservatively
  // because it is per-connection resident memory on a phone.
  database.execute('PRAGMA cache_size = -4000');
}

LazyDatabase _openConnection(String databaseName) {
  return LazyDatabase(() async {
    final dbManager = await DatabaseManager.getInstance();
    final dbPath = await dbManager.getDatabasePath(databaseName);
    final file = File(dbPath);
    await file.parent.create(recursive: true);
    return NativeDatabase.createInBackground(
      file,
      setup: configureSqliteConnection,
    ).interceptWith(LoadingQueryInterceptor());
  });
}
