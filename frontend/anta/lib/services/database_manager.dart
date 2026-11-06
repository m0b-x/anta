import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' show OpenMode, sqlite3;

import '../constants/settings_keys.dart';
import '../core/qa/qa_mode.dart';
import '../database/database.dart';
import 'sync/sync_space_registry.dart';

/// Service for managing multiple SQLite databases
class DatabaseManager {
  /// Memoized, so every caller waits for the launch's recovery below and none
  /// reads the active name before it has been put back.
  static Future<DatabaseManager>? _instance;
  late SharedPreferences _prefs;

  static const String _keyActiveDatabase = 'active_database';
  static const String _defaultDatabaseName = 'gym_notes';

  static const String _downloadFrom = 'from';
  static const String _downloadTo = 'to';

  DatabaseManager._();

  /// The one manager of this process, published only once its preferences
  /// are read and the launch's recovery has run. An open that fails is not
  /// kept: the next call starts over rather than rethrowing it for the rest
  /// of the process (final review X-7).
  static Future<DatabaseManager> getInstance() {
    final existing = _instance;
    if (existing != null) return existing;
    final created = _create();
    _instance = created;
    created.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_instance, created)) _instance = null;
      },
    );
    return created;
  }

  /// Drops the memo, so the next [getInstance] reads the preferences and
  /// runs the recovery again as a new process would.
  @visibleForTesting
  static void resetForTesting() => _instance = null;

  static Future<DatabaseManager> _create() async {
    final manager = DatabaseManager._();
    manager._prefs = await SharedPreferences.getInstance();
    await manager._recoverInterruptedDownload();
    return manager;
  }

  /// The database an install opens when it has never switched.
  ///
  /// A QA build falls back to its own database instead of the owner's. Its
  /// preferences are namespaced, so the stored `active_database` of a normal
  /// build is invisible to it and this fallback is what it lands on — while
  /// switching databases from Settings keeps working in both builds.
  ///
  /// Takes [qaEnabled] rather than reading [QaMode.enabled] directly so the
  /// decision is testable: the constant is fixed at compile time.
  static String defaultDatabaseName({
    required bool qaEnabled,
    String qaDatabaseName = QaMode.databaseName,
  }) {
    return qaEnabled ? qaDatabaseName : _defaultDatabaseName;
  }

  /// Get the name of the currently active database
  String getActiveDatabaseName() {
    return _prefs.getString(_keyActiveDatabase) ??
        defaultDatabaseName(qaEnabled: QaMode.enabled);
  }

  /// Set the active database name
  Future<void> setActiveDatabaseName(String name) async {
    await _prefs.setString(_keyActiveDatabase, name);
  }

  /// Records that a "Download into a new database" is about to make [to]
  /// active, coming from [from]: until [clearDownloadInFlight], a kill leaves
  /// [to] active and empty, so the next launch switches back to [from]
  /// (review BA-M2).
  Future<void> markDownloadInFlight({
    required String from,
    required String to,
  }) async {
    await _prefs.setString(
      SettingsKeys.syncDownloadInFlight,
      jsonEncode({_downloadFrom: from, _downloadTo: to}),
    );
  }

  /// The download has bound its database, or has switched back.
  ///
  /// Tried twice: a marker left behind after a bind that committed would
  /// switch the next launch back to the old database, away from the one the
  /// user has been working in since (final review X-4). A `false` counts as
  /// a failure: the Android store answers a failed remove with it rather
  /// than a throw (RA2-2).
  Future<void> clearDownloadInFlight() async {
    try {
      if (await _prefs.remove(SettingsKeys.syncDownloadInFlight)) return;
      debugPrint('[DatabaseManager] download marker not cleared, retrying');
    } catch (e) {
      debugPrint('[DatabaseManager] download marker not cleared, retrying: $e');
    }
    if (!await _prefs.remove(SettingsKeys.syncDownloadInFlight)) {
      debugPrint('[DatabaseManager] download marker still not cleared');
    }
  }

  /// A download the process died in: the database it came from made active
  /// again. The new file stays for the Databases page — nothing is deleted
  /// at launch, before anything has been seen. An unreadable marker is only
  /// dropped. Never thrown: the launch must go on.
  ///
  /// The marker is trusted only while it still describes the install: the
  /// download's database is the active one, holds no sync claim, and the one
  /// it came from is still there. Otherwise the user has moved on — switched
  /// elsewhere, or deleted the old database, which switching to would create
  /// empty — or the bind committed, since it claims right after its commit,
  /// and only the clear failed; the marker is then only dropped (final
  /// review X-4, RA2-3).
  Future<void> _recoverInterruptedDownload() async {
    final raw = _prefs.getString(SettingsKeys.syncDownloadInFlight);
    if (raw == null) return;
    try {
      final marker = raw.isEmpty ? null : jsonDecode(raw);
      if (marker is Map) {
        final from = marker[_downloadFrom];
        final to = marker[_downloadTo];
        final active = getActiveDatabaseName();
        if (from is String && from.isNotEmpty) {
          if (active != to) {
            debugPrint(
              '[DatabaseManager] download marker into "$to" dropped: '
              '"$active" is active',
            );
          } else if (spaceRegistry.claims().any(
            (claim) => claim.databaseName == to,
          )) {
            debugPrint(
              '[DatabaseManager] download marker dropped: "$to" holds a '
              'sync claim, so its bind committed',
            );
          } else if (!await databaseExists(from)) {
            debugPrint(
              '[DatabaseManager] download marker dropped: "$from" is gone, '
              'staying on "$to"',
            );
          } else {
            await setActiveDatabaseName(from);
            debugPrint(
              '[DatabaseManager] interrupted download into "$to": back on '
              '"$from"',
            );
          }
        }
      }
    } catch (e, st) {
      debugPrint('[DatabaseManager] download marker not recovered: $e\n$st');
    }
    try {
      await clearDownloadInFlight();
    } catch (e, st) {
      debugPrint('[DatabaseManager] download marker not cleared: $e\n$st');
    }
  }

  /// Which database of this install holds which sync space: install-wide
  /// like the active name, so over the same preferences — and kept true here
  /// across a delete and a rename, the two ways a database's name leaves.
  SyncSpaceRegistry get spaceRegistry =>
      SyncSpaceRegistry(_prefs, databaseExists: databaseExists);

  /// Get the full path to a database file by name
  Future<String> getDatabasePath(String name) async {
    final dbFolder = await getApplicationDocumentsDirectory();
    return p.join(dbFolder.path, 'gym_notes', '$name.db');
  }

  /// Get the path to the gym_notes directory
  Future<String> getDatabaseDirectory() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    return p.join(dbFolder.path, 'gym_notes');
  }

  /// List all available database files
  Future<List<DatabaseInfo>> listDatabases() async {
    final gymNotesDir = Directory(await getDatabaseDirectory());

    if (!await gymNotesDir.exists()) {
      await gymNotesDir.create(recursive: true);
    }

    final databases = <DatabaseInfo>[];
    final files = gymNotesDir.listSync();

    for (final file in files) {
      if (file is File && file.path.endsWith('.db')) {
        final name = p.basenameWithoutExtension(file.path);
        final stats = await file.stat();
        databases.add(
          DatabaseInfo(
            name: name,
            path: file.path,
            size: stats.size,
            lastModified: stats.modified,
          ),
        );
      }
    }

    // Sort by last modified (newest first)
    databases.sort((a, b) => b.lastModified.compareTo(a.lastModified));

    return databases;
  }

  /// Check if a database with the given name exists
  Future<bool> databaseExists(String name) async {
    final path = await getDatabasePath(name);
    return await File(path).exists();
  }

  /// Create a new database file
  Future<void> createDatabase(String name) async {
    if (await databaseExists(name)) {
      throw Exception('Database "$name" already exists');
    }

    final path = await getDatabasePath(name);
    final file = File(path);
    await file.parent.create(recursive: true);

    // Create an empty file - the database will be initialized on first access
    await file.create();
  }

  /// Copies an external SQLite database file into the managed directory as
  /// [targetName]. The file is imported verbatim; ANTA's migrations upgrade it
  /// on first open.
  Future<void> importDatabase(String sourcePath, String targetName) async {
    if (await databaseExists(targetName)) {
      throw Exception('Database "$targetName" already exists');
    }

    final source = File(sourcePath);
    if (!await source.exists()) {
      throw Exception('Source database file not found');
    }

    final targetPath = await getDatabasePath(targetName);
    final targetFile = File(targetPath);
    await targetFile.parent.create(recursive: true);
    await source.copy(targetPath);
  }

  /// True when [path] begins with the SQLite file magic header. Guards against
  /// importing a non-database file that would crash the app once it becomes
  /// the active database.
  Future<bool> isSqliteFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return false;

    final handle = await file.open();
    try {
      final header = await handle.read(16);
      if (header.length < 16) return false;
      const magic = 'SQLite format 3\u0000';
      for (var i = 0; i < magic.length; i++) {
        if (header[i] != magic.codeUnitAt(i)) return false;
      }
      return true;
    } finally {
      await handle.close();
    }
  }

  /// A unique, valid database name derived from [base] by sanitizing invalid
  /// characters and appending a numeric suffix until it no longer collides.
  Future<String> suggestDatabaseName(String base) async {
    var sanitized = base.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (sanitized.length > 50) sanitized = sanitized.substring(0, 50);
    if (sanitized.isEmpty) sanitized = 'imported';

    var name = sanitized;
    var counter = 1;
    while (await databaseExists(name)) {
      final suffix = '_$counter';
      final maxBase = 50 - suffix.length;
      final trimmed = sanitized.length > maxBase
          ? sanitized.substring(0, maxBase)
          : sanitized;
      name = '$trimmed$suffix';
      counter++;
    }
    return name;
  }

  /// Rename a database file.
  ///
  /// Checkpointed first, so no `-wal` is left to move: a kill between the
  /// `.db`'s rename and the sidecar's would otherwise leave the renamed file
  /// without its last writes and an orphan `-wal` that nothing applies. A
  /// blocked checkpoint fails the rename before any file has moved.
  ///
  /// The sync claim and the active name follow the `.db` once its sidecars
  /// have been tried, whether or not one of them threw: left on the old name,
  /// the next launch would open that name and create it empty, its claim
  /// would hold again, and the heal would unbind the renamed database (final
  /// review X-3, RA2-1). Nothing runs between the `.db` and its sidecars — a
  /// registry write that failed there could split a database from
  /// un-checkpointed pages in its `-wal` — and a registry write that fails is
  /// logged, never thrown; the claim it leaves on the old name, whose file is
  /// gone, reads as free, and the binding service's heal claims the space
  /// again for the bound database that has none.
  Future<void> renameDatabase(String oldName, String newName) async {
    if (!await databaseExists(oldName)) {
      throw Exception('Database "$oldName" does not exist');
    }

    if (await databaseExists(newName)) {
      throw Exception('Database "$newName" already exists');
    }

    await checkpoint(oldName);

    final oldPath = await getDatabasePath(oldName);
    final newPath = await getDatabasePath(newName);

    final oldFile = File(oldPath);
    await oldFile.rename(newPath);

    try {
      // Also rename related files if they exist (WAL, SHM files)
      final oldWal = File('$oldPath-wal');
      if (await oldWal.exists()) {
        await oldWal.rename('$newPath-wal');
      }

      final oldShm = File('$oldPath-shm');
      if (await oldShm.exists()) {
        await oldShm.rename('$newPath-shm');
      }
    } finally {
      try {
        await spaceRegistry.rename(oldName, newName);
      } catch (e, st) {
        debugPrint('[DatabaseManager] sync claim not renamed: $e\n$st');
      }

      // If the renamed database was the active one, update the active database name
      if (getActiveDatabaseName() == oldName) {
        await setActiveDatabaseName(newName);
      }
    }
  }

  /// Delete a database file.
  ///
  /// Checkpointed first only to tidy — a kill mid-delete then leaves no
  /// orphan `-wal` beside the name — so a checkpoint that fails (a file that
  /// is not SQLite) is logged and the delete goes on: the files are going
  /// either way, and the database a user most wants gone must stay deletable.
  Future<void> deleteDatabase(String name) async {
    if (!await databaseExists(name)) {
      throw Exception('Database "$name" does not exist');
    }

    try {
      await checkpoint(name);
    } catch (e, st) {
      debugPrint('[DatabaseManager] checkpoint before delete failed: $e\n$st');
    }

    final path = await getDatabasePath(name);
    final file = File(path);
    await file.delete();

    // Also delete related files if they exist
    final wal = File('$path-wal');
    if (await wal.exists()) {
      await wal.delete();
    }

    final shm = File('$path-shm');
    if (await shm.exists()) {
      await shm.delete();
    }

    await spaceRegistry.release(name);

    // If the deleted database was the active one, switch to default — the QA
    // one in a QA build, so deleting from Settings can never drop that build
    // onto the owner's database.
    if (getActiveDatabaseName() == name) {
      await setActiveDatabaseName(
        defaultDatabaseName(qaEnabled: QaMode.enabled),
      );
    }
  }

  /// Folds [name]'s `-wal` sidecar back into its `.db`, so the main file alone
  /// — what a share hands over — holds every committed write.
  ///
  /// The open database is checkpointed on the app's own connection. Any other
  /// name is checkpointed only when a sidecar was left behind (the app quit
  /// before folding it), on a short-lived connection; SQLite checkpoints once
  /// more as that last connection closes. It opens read-write, never create:
  /// an orphan sidecar with no `.db` beside it must not conjure an empty
  /// database into the list. The FFI calls are synchronous on the UI isolate,
  /// accepted for this rare branch.
  Future<void> checkpoint(String name) async {
    final open = AppDatabase.openInstanceOf(name);
    if (open != null) {
      await (await open).checkpoint();
      return;
    }
    final path = await getDatabasePath(name);
    if (!await File(path).exists()) return;
    if (!await File('$path-wal').exists()) return;
    final connection = sqlite3.open(path, mode: OpenMode.readWrite);
    try {
      final row = connection.select('PRAGMA wal_checkpoint(TRUNCATE)').single;
      if (row['busy'] != 0) throw StateError('WAL checkpoint was blocked');
    } finally {
      connection.close();
    }
  }

  /// Validate database name (alphanumeric, underscores, hyphens only)
  bool isValidDatabaseName(String name) {
    if (name.isEmpty || name.length > 50) return false;
    final regex = RegExp(r'^[a-zA-Z0-9_-]+$');
    return regex.hasMatch(name);
  }
}

/// Information about a database file
class DatabaseInfo {
  final String name;
  final String path;
  final int size;
  final DateTime lastModified;

  DatabaseInfo({
    required this.name,
    required this.path,
    required this.size,
    required this.lastModified,
  });
}
