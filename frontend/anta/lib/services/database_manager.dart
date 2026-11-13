import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart'
    show ChangeNotifier, debugPrint, visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart'
    show Database, OpenMode, ResultSet, SqliteException, sqlite3;

import '../constants/settings_keys.dart';
import '../constants/temp_file_names.dart';
import '../core/qa/qa_mode.dart';
import '../database/crdt/synced_tables.dart' show sharedTables;
import '../database/daos/sync_dao.dart';
import '../database/database.dart';
import '../database/migrations/database_schema.dart';
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

  /// What a share's snapshot folder in the system temp directory is named
  /// with ([snapshotForShare]); it carries ANTA's temp prefix so the launch
  /// sweep (`ImportExportService.sweepStaleExports`) knows it as ANTA's own.
  static const String shareSnapshotPrefix = TempFileNames.shareSnapshotPrefix;

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

  /// The schema version the database file at [path] was last written at,
  /// read with SQLite alone and never through Drift, whose open would
  /// create a missing file and migrate an older one: null when there is no
  /// file, -1 when it cannot be read. For the one reader that must leave
  /// both to the app — the check that runs with the app closed
  /// (`docs/cloud-shared-freshness.md`, decision e). Through SQLite rather
  /// than the header's bytes: a version a migration just wrote may still be
  /// in the WAL.
  static int? schemaVersionOfFile(String path) {
    if (!File(path).existsSync()) return null;
    final Database db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readOnly);
    } on SqliteException catch (e) {
      debugPrint('[DatabaseManager] schema of $path not read: $e');
      return -1;
    }
    try {
      final version = db.select('PRAGMA user_version').single['user_version'];
      return version is int ? version : -1;
    } on SqliteException catch (e) {
      debugPrint('[DatabaseManager] schema of $path not read: $e');
      return -1;
    } finally {
      db.close();
    }
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

  /// What an import's temporary copy is named with, after the target's
  /// `.db` and before a timestamp (`travel.db.import-<epoch ms>`), so
  /// [listDatabases] never lists one and [sweepStaleImports] knows it.
  static const String _importTempSuffix = '.import-';

  /// A temporary copy or one of its sidecars, by [_importTempSuffix].
  static final RegExp _importTempName = RegExp(
    '\\.db${RegExp.escape(_importTempSuffix)}\\d+(-wal|-shm|-journal)?\$',
  );

  /// The 16 bytes every SQLite database file begins with.
  static const String _sqliteMagic = 'SQLite format 3\u0000';

  /// The sidecars SQLite keeps beside a database: the WAL, its index, and a
  /// rollback journal.
  static const List<String> _sidecarSuffixes = ['-wal', '-shm', '-journal'];

  /// The copy's read and write size, and so how long a Cancel can wait.
  static const int _importChunkBytes = 1 << 20;

  /// Checks a copied file before it may become a database of this install;
  /// throws a [DatabaseImportError] to refuse it. The real check opens the
  /// file in SQLite, so a widget test, which cannot run it under `FakeAsync`,
  /// puts a fake here.
  @visibleForTesting
  Future<void> Function(String tmpPath) verifyImport = verifyImportFile;

  /// Awaited after each chunk the copy writes, so a test can hold the copy
  /// half done — a real one finishes before a tap could land.
  @visibleForTesting
  static Future<void> Function()? debugImportChunkWritten;

  /// Brings an external SQLite database file in as [targetName]; ANTA's
  /// migrations upgrade it on first open.
  ///
  /// The copy goes to a temporary name beside the target, in chunks, so
  /// [progress] can show it and stop it; a `-wal` beside the source comes
  /// too, or a WAL-mode file would arrive without its latest writes, and so
  /// does a hot `-journal`, or a file copied mid-transaction would arrive
  /// torn instead of rolled back. Only a copy [verifyImport] accepts is
  /// renamed into place: a corrupt file, a newer schema or another app's
  /// database would otherwise become the active database and could take the
  /// app down at launch. Whatever fails — a cancel, a full disk, a refusal —
  /// the temporary files go before the error reaches the caller.
  Future<void> importDatabase(
    String sourcePath,
    String targetName, {
    DatabaseImportProgress? progress,
  }) async {
    if (await databaseExists(targetName)) {
      throw Exception('Database "$targetName" already exists');
    }

    final source = File(sourcePath);
    if (!await source.exists()) {
      throw Exception('Source database file not found');
    }

    final targetPath = await getDatabasePath(targetName);
    await File(targetPath).parent.create(recursive: true);
    final tempPath =
        '$targetPath$_importTempSuffix${DateTime.now().millisecondsSinceEpoch}';
    final copies = <(File, String)>[(source, tempPath)];
    for (final suffix in const ['-wal', '-journal']) {
      final sidecar = File('$sourcePath$suffix');
      if (await sidecar.exists()) copies.add((sidecar, '$tempPath$suffix'));
    }

    try {
      final lengths = [for (final (file, _) in copies) await file.length()];
      final total = lengths.fold(0, (sum, length) => sum + length);
      var copied = 0;
      for (final (index, (file, to)) in copies.indexed) {
        await _copyInChunks(file, to, lengths[index], progress, (bytes) {
          copied += bytes;
          progress?._copied(total == 0 ? 1 : copied / total);
        });
      }

      // A Cancel tapped after the last chunk's check still counts: the dialog
      // took it, so the import must not go on to succeed.
      if (progress?.cancelRequested ?? false) {
        throw const DatabaseImportCancelled();
      }
      progress?._verifying();
      await verifyImport(tempPath);

      // The real check folds a WAL-mode file's sidecar and rolls a hot
      // journal back, so a sidecar still here was never the file's own — a
      // stale one copied from beside the source, or an orphan a failed
      // delete left beside the target. SQLite replays a WAL it finds beside
      // a database, even a rollback-flagged one, so either would be written
      // over the imported file.
      for (final suffix in _sidecarSuffixes) {
        for (final sidecar in [
          File('$tempPath$suffix'),
          File('$targetPath$suffix'),
        ]) {
          if (await sidecar.exists()) await sidecar.delete();
        }
      }
      await File(tempPath).rename(targetPath);
    } catch (_) {
      await _deleteImportTemp(tempPath);
      rethrow;
    }
  }

  /// Copies the [length] bytes [from] held when the import began — what the
  /// bar's total counts; a live `-wal` growing meanwhile ends on a whole
  /// frame or a torn one SQLite ignores.
  Future<void> _copyInChunks(
    File from,
    String to,
    int length,
    DatabaseImportProgress? progress,
    void Function(int bytes) onChunk,
  ) async {
    final input = await from.open();
    try {
      final output = await File(to).open(mode: FileMode.writeOnly);
      try {
        var remaining = length;
        while (remaining > 0) {
          if (progress?.cancelRequested ?? false) {
            throw const DatabaseImportCancelled();
          }
          final chunk = await input.read(
            remaining < _importChunkBytes ? remaining : _importChunkBytes,
          );
          if (chunk.isEmpty) break;
          remaining -= chunk.length;
          await output.writeFrom(chunk);
          onChunk(chunk.length);
          await debugImportChunkWritten?.call();
        }
        await output.flush();
      } finally {
        await output.close();
      }
    } finally {
      await input.close();
    }
  }

  /// Deletes an import's temporary copy and every sidecar SQLite may have
  /// left beside it. Never thrown: what is left, the launch sweep takes.
  Future<void> _deleteImportTemp(String tempPath) async {
    for (final suffix in ['', ..._sidecarSuffixes]) {
      try {
        final file = File('$tempPath$suffix');
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint('[DatabaseManager] import temp kept: $e');
      }
    }
  }

  /// Deletes the temporary copies an import left when the app died during
  /// it. Run before the first frame, when no import can be running; nothing
  /// else in the directory is touched. Never thrown: the launch must go on.
  Future<void> sweepStaleImports() async {
    try {
      final directory = Directory(await getDatabaseDirectory());
      if (!await directory.exists()) return;
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        if (!_importTempName.hasMatch(p.basename(entity.path))) continue;
        try {
          await entity.delete();
        } catch (e) {
          debugPrint('[DatabaseManager] stale import kept: $e');
        }
      }
    } catch (e, st) {
      debugPrint('[DatabaseManager] import sweep failed: $e\n$st');
    }
  }

  /// [verifyImport]'s real check, off the UI isolate: a 500 MB file's
  /// `quick_check` takes seconds.
  static Future<void> verifyImportFile(String path) {
    final newestVersion = DatabaseSchema.currentVersion;
    return Isolate.run(() => _verifyImportSync(path, newestVersion));
  }

  /// ANTA's core tables and the columns each has had since the first schema
  /// (no migration renames or drops them): what an older file must carry for
  /// the migrations to have anything to upgrade.
  static const Map<String, List<String>> _antaBaseColumns = {
    'notes': ['id', 'folder_id', 'title'],
    'folders': ['id', 'name'],
    'content_chunks': ['id', 'note_id', 'chunk_index', 'content'],
  };

  /// What a file at [DatabaseSchema.currentVersion] carries besides: Drift
  /// runs no migration on it, so a table that only has the right name would
  /// fail every query once it is active.
  static const Map<String, List<String>> _antaCurrentColumns = {
    'notes': ['is_deleted', 'hlc_timestamp'],
    'folders': ['is_deleted', 'hlc_timestamp'],
    // `content_hash` arrived with v46 (the content-defined chunks); a file at
    // the current version without it would fail every planned save.
    'content_chunks': ['is_deleted', 'hlc_timestamp', 'content_hash'],
  };

  /// In order: the header, the length against the pages, the schema
  /// version, `quick_check`, ANTA's shape (a version of at least 1 and the
  /// core tables' columns, the current ones at the current version) — then,
  /// on a file it accepts, [_forgetReplicaId], the one write. Opens
  /// read-write, never create — a vanished file must fail, not become an
  /// empty database — and folds a `-wal` first, so the length is the whole
  /// database's.
  static void _verifyImportSync(String path, int newestVersion) {
    final file = File(path);
    final header = file.openSync();
    final List<int> bytes;
    try {
      bytes = header.readSync(100);
    } finally {
      header.closeSync();
    }
    _checkHeader(bytes);

    final Database db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readWrite);
    } on SqliteException catch (e) {
      throw DatabaseImportCorrupt('open: $e');
    }
    try {
      if (File('$path-wal').existsSync()) {
        final row = db.select('PRAGMA wal_checkpoint(TRUNCATE)').single;
        if (row['busy'] != 0) {
          throw const DatabaseImportCorrupt('WAL not folded');
        }
      }
      final pageCount = db.select('PRAGMA page_count').single['page_count'];
      final pageSize = db.select('PRAGMA page_size').single['page_size'];
      final length = file.lengthSync();
      if (pageCount is! int ||
          pageSize is! int ||
          pageCount * pageSize != length) {
        throw DatabaseImportCorrupt(
          '$pageCount pages of $pageSize bytes in $length',
        );
      }

      final version = db.select('PRAGMA user_version').single['user_version'];
      if (version is int && version > newestVersion) {
        throw DatabaseImportTooNew(version);
      }

      final check = db.select('PRAGMA quick_check');
      if (check.length != 1 || check.single.values.first != 'ok') {
        throw DatabaseImportCorrupt(
          'quick_check: ${check.map((r) => r.values.first).join('; ')}',
        );
      }

      // Version 0 is a file no ANTA has opened: Drift would create its
      // tables beside the foreign ones and stamp it current.
      if (version is! int || version < 1) {
        throw const DatabaseImportNotAnta();
      }
      for (final MapEntry(key: table, value: base)
          in _antaBaseColumns.entries) {
        final columns = {
          for (final row in db.select('PRAGMA table_info("$table")'))
            row['name'],
        };
        final required = [
          ...base,
          if (version == newestVersion) ..._antaCurrentColumns[table]!,
        ];
        if (!columns.containsAll(required)) {
          throw const DatabaseImportNotAnta();
        }
      }
      _forgetReplicaId(db);
    } on SqliteException catch (e) {
      throw DatabaseImportCorrupt('$e');
    } finally {
      db.close();
    }
  }

  /// Drops an accepted file's `replica_id`, so its first counter tap mints a
  /// fresh one (S20, D8 A): a bound database imported on another phone claims
  /// the space there, and tapping under the source's id would join the two
  /// phones' taps as one replica's — the larger count kept, not the sum.
  /// Writes nothing to a file that carries none.
  static void _forgetReplicaId(Database db) {
    final hasTable = db.select(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' "
      "AND name = 'sync_metadata'",
    );
    if (hasTable.isEmpty) return;
    final stored = db.select('SELECT 1 FROM sync_metadata WHERE key = ?', [
      SyncDao.keyReplicaId,
    ]);
    if (stored.isEmpty) return;
    db.execute('DELETE FROM sync_metadata WHERE key = ?', [
      SyncDao.keyReplicaId,
    ]);
  }

  /// The SQLite magic, a power-of-two page size, and read and write versions
  /// of 1 or 2: a share since S18 is a rollback-journal file (1, 1), an
  /// older share and a live copy are WAL-flagged (2, 2).
  static void _checkHeader(List<int> bytes) {
    if (bytes.length < 100) {
      throw const DatabaseImportCorrupt('header shorter than 100 bytes');
    }
    if (!_startsWithMagic(bytes)) {
      throw const DatabaseImportCorrupt('no SQLite magic');
    }
    final rawPageSize = bytes[16] << 8 | bytes[17];
    final pageSize = rawPageSize == 1 ? 65536 : rawPageSize;
    if (pageSize < 512 || pageSize & (pageSize - 1) != 0) {
      throw DatabaseImportCorrupt('page size $pageSize');
    }
    for (final version in [bytes[18], bytes[19]]) {
      if (version != 1 && version != 2) {
        throw DatabaseImportCorrupt('file format version $version');
      }
    }
  }

  /// True when [path] begins with the SQLite file magic header. Guards against
  /// importing a non-database file that would crash the app once it becomes
  /// the active database.
  Future<bool> isSqliteFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return false;

    final handle = await file.open();
    try {
      return _startsWithMagic(await handle.read(_sqliteMagic.length));
    } finally {
      await handle.close();
    }
  }

  static bool _startsWithMagic(List<int> bytes) {
    if (bytes.length < _sqliteMagic.length) return false;
    for (var i = 0; i < _sqliteMagic.length; i++) {
      if (bytes[i] != _sqliteMagic.codeUnitAt(i)) return false;
    }
    return true;
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
  /// holds every committed write before [renameDatabase] moves it or
  /// [deleteDatabase] removes it. (A share no longer needs it: it hands over
  /// [snapshotForShare]'s copy.)
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

  /// Writes a consistent copy of [name] for a share and returns its path,
  /// `<temp>/anta_db_share_<epoch ms>/<name>.db` — the file name the
  /// recipient sees, and so the name a restore suggests.
  ///
  /// `VACUUM INTO` copies one read transaction's view, so a write landing
  /// meanwhile (an auto-save, a sync pull) is wholly in the copy or wholly
  /// out of it, nothing waits on a checkpoint a reader could block, and free
  /// pages stay behind (D11, `docs/scalability-roadmap.md`).
  ///
  /// It runs on a short-lived connection of its own, in a worker isolate,
  /// whether or not the app has [name] open: in WAL mode that connection is
  /// one more reader with its own consistent view, so the app's single Drift
  /// connection is never held for the length of the copy and its writes go
  /// on meanwhile. No `temp_store` change is needed — `VACUUM INTO` writes
  /// the copy straight into the target file, not through temporary storage.
  ///
  /// Earlier snapshot folders go first: a desktop share leaves its own for
  /// later (`ImportExportService.shareExport`). A copy that fails — a full
  /// disk — takes its folder with it before the error reaches the caller.
  Future<String> snapshotForShare(String name) async {
    final tempDir = await getTemporaryDirectory();
    await for (final entity in tempDir.list(followLinks: false)) {
      if (entity is Directory &&
          p.basename(entity.path).startsWith(shareSnapshotPrefix)) {
        try {
          await entity.delete(recursive: true);
        } catch (e) {
          // Still open in a share sheet; the launch sweep retries it.
          debugPrint('[DatabaseManager] earlier snapshot kept: $e');
        }
      }
    }

    final folder = Directory(
      p.join(
        tempDir.path,
        '$shareSnapshotPrefix${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
    final snapshot = p.join(folder.path, '$name.db');
    try {
      await folder.create(recursive: true);
      final source = await getDatabasePath(name);
      final copy = debugSnapshotCopy;
      if (copy != null) {
        copy(source, snapshot);
      } else {
        await Isolate.run(() => _vacuumInto(source, snapshot));
      }
      return snapshot;
    } catch (_) {
      try {
        await folder.delete(recursive: true);
      } catch (_) {
        /* the launch sweep retries it */
      }
      rethrow;
    }
  }

  /// Stands in for [snapshotForShare]'s copy, on the calling isolate, so a
  /// test can fail it the way a full disk would — SQLite cannot be made to
  /// run out of room on a test machine.
  @visibleForTesting
  static void Function(String source, String snapshot)? debugSnapshotCopy;

  /// [snapshotForShare]'s copy. Opens read-write, never create: a missing
  /// file must fail the share, not conjure an empty database to snapshot.
  static void _vacuumInto(String source, String snapshot) {
    final connection = sqlite3.open(source, mode: OpenMode.readWrite);
    try {
      connection.execute('VACUUM INTO ?', [snapshot]);
    } finally {
      connection.close();
    }
    _stripShared(snapshot);
  }

  /// Takes out of [snapshot] — a copy about to leave the phone — every row
  /// the partner shares and what the shared reader keeps of them: a file is
  /// opened by whoever receives it, never as the person, and nothing would
  /// ever run the reader there to take the rows away (share surfaces D19,
  /// "a partner's rows never leave by file"). What `SharedRowDao.removeAll`
  /// removes, on the copy's own connection: the owner's rows of every
  /// shareable table, their notes' text and search index, and the reader's
  /// records (the owner, its cursors and counts, the hidden categories).
  /// The person's own rows, marks and alerts stay as a restore would read
  /// them. Then the copy is compacted, so no freed page keeps their text.
  ///
  /// A copy holding no shared owner is left exactly as `VACUUM INTO` wrote
  /// it: one read, no write.
  static void _stripShared(String snapshot) {
    final connection = sqlite3.open(snapshot, mode: OpenMode.readWrite);
    try {
      final ResultSet rows;
      try {
        rows = connection.select(
          'SELECT value FROM sync_metadata WHERE key = ?',
          [SyncDao.keySharedOwner],
        );
      } on SqliteException catch (_) {
        // A database from before sync: it never held a shared row.
        return;
      }
      if (rows.isEmpty) return;
      final owner = rows.single['value'] as String;
      connection.execute('BEGIN');
      try {
        // The fences' licence (`SharedRowDao.writing`): they stand down while
        // this key is present, and it is gone again before the commit.
        connection.execute(
          'INSERT OR REPLACE INTO sync_metadata (key, value, updated_at) '
          'VALUES (?, ?, 0)',
          [SyncDao.keySharedWriting, '1'],
        );
        const theirNotes = 'SELECT rowid FROM notes WHERE owner_id = ?';
        try {
          connection.execute(
            'DELETE FROM note_body_fts WHERE rowid IN ($theirNotes)',
            [owner],
          );
        } on SqliteException catch (e) {
          // A build without the body index has none to clear.
          debugPrint('[DatabaseManager] no body index to strip: $e');
        }
        connection.execute(
          'DELETE FROM note_search_ledger WHERE note_rowid IN ($theirNotes)',
          [owner],
        );
        connection.execute(
          'DELETE FROM content_chunks WHERE note_id IN '
          '(SELECT id FROM notes WHERE owner_id = ?)',
          [owner],
        );
        for (final table in sharedTables.reversed) {
          connection.execute('DELETE FROM $table WHERE owner_id = ?', [owner]);
        }
        connection.execute(
          'DELETE FROM sync_metadata WHERE key IN (?, ?, ?, ?, ?, ?, ?, ?)',
          [
            SyncDao.keySharedOwner,
            SyncDao.keySharedPair,
            SyncDao.keySharedReadAt,
            SyncDao.keySharedReadOkAt,
            SyncDao.keySharedReadFailedAt,
            SyncDao.keySharedFullAt,
            SyncDao.keySharedNewerWire,
            SyncDao.keyShareSending,
          ],
        );
        for (final prefix in const [
          SyncDao.sharedCursorPrefix,
          SyncDao.sharedWaitingPrefix,
          SyncDao.sharedRootPrefix,
          SyncDao.sharedRefusedPrefix,
          SyncDao.sharedBuiltInPrefix,
          SyncDao.sharePokeOwedPrefix,
        ]) {
          connection.execute(
            "DELETE FROM sync_metadata WHERE substr(key, 1, ?) = ?",
            [prefix.length, prefix],
          );
        }
        // The receiver's choices about a partner's rows, keyed by her ids.
        connection.execute('DELETE FROM user_settings WHERE key IN (?, ?)', [
          SettingsKeys.shareHiddenCategories,
          SettingsKeys.shareFolderSorts,
        ]);
        connection.execute('DELETE FROM sync_metadata WHERE key = ?', [
          SyncDao.keySharedWriting,
        ]);
        connection.execute('COMMIT');
      } catch (_) {
        connection.execute('ROLLBACK');
        rethrow;
      }
      try {
        connection.execute(
          "INSERT INTO note_body_fts(note_body_fts) VALUES ('optimize')",
        );
      } on SqliteException catch (_) {
        // No body index: nothing kept a deleted entry.
      }
      connection.execute('VACUUM');
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

/// Why an imported database file was refused. Each kind has its own message,
/// so the user knows whether to look for another file or update the app.
sealed class DatabaseImportError implements Exception {
  const DatabaseImportError();
}

/// Not a whole SQLite database: a bad header, a length its pages do not
/// account for, or a failed `quick_check`.
final class DatabaseImportCorrupt extends DatabaseImportError {
  const DatabaseImportCorrupt(this.reason);

  /// For the log only; the user sees one sentence for every reason.
  final String reason;

  @override
  String toString() => 'DatabaseImportCorrupt: $reason';
}

/// A sound SQLite file that is not ANTA's: version 0 (no ANTA ever opened
/// it), or core tables missing or without the columns its version carries.
final class DatabaseImportNotAnta extends DatabaseImportError {
  const DatabaseImportNotAnta();

  @override
  String toString() => 'DatabaseImportNotAnta';
}

/// Written by a newer ANTA: this build's migrations cannot read a schema past
/// [DatabaseSchema.currentVersion], so the file must never become active.
final class DatabaseImportTooNew extends DatabaseImportError {
  const DatabaseImportTooNew(this.version);

  /// The file's `user_version`, for the log; the message names no number,
  /// since the user needs only to update.
  final int version;

  @override
  String toString() => 'DatabaseImportTooNew: $version';
}

/// The user stopped the copy; its partial file is already gone.
final class DatabaseImportCancelled extends DatabaseImportError {
  const DatabaseImportCancelled();

  @override
  String toString() => 'DatabaseImportCancelled';
}

/// An import's two steps: the copy, which a Cancel stops between chunks, and
/// the check, which nothing can interrupt.
enum DatabaseImportPhase { copying, verifying }

/// One import as its dialog sees it — how far the copy is, whether it has
/// moved on to the check — and the dialog's one way to stop it.
class DatabaseImportProgress extends ChangeNotifier {
  DatabaseImportPhase _phase = DatabaseImportPhase.copying;
  double _fraction = 0;
  bool _cancelRequested = false;

  /// Which step the dialog shows; it moves forward once, never back.
  DatabaseImportPhase get phase => _phase;

  /// The share of the copy written, 0 to 1.
  double get fraction => _fraction;

  /// A Cancel was taken; the import throws [DatabaseImportCancelled] before
  /// it writes another chunk or starts the check.
  bool get cancelRequested => _cancelRequested;

  /// Whether [cancel] still means anything: the check is FFI work that
  /// cannot be interrupted, so only the copy can be stopped.
  bool get canCancel =>
      _phase == DatabaseImportPhase.copying && !_cancelRequested;

  /// Honoured before the copy's next chunk.
  void cancel() {
    if (!canCancel) return;
    _cancelRequested = true;
    notifyListeners();
  }

  void _copied(double fraction) {
    _fraction = fraction;
    notifyListeners();
  }

  void _verifying() {
    _phase = DatabaseImportPhase.verifying;
    _fraction = 1;
    notifyListeners();
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
