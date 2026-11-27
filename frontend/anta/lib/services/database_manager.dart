import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart'
    show ChangeNotifier, debugPrint, visibleForTesting;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart'
    show Database, OpenMode, SqliteException, sqlite3;

import '../constants/settings_keys.dart';
import '../constants/temp_file_names.dart';
import '../core/qa/qa_mode.dart';
import '../database/crdt/synced_tables.dart' show sharedTables;
import '../database/daos/note_search_dao.dart';
import '../database/daos/sync_dao.dart';
import '../database/database.dart';
import '../database/migrations/database_schema.dart';
import '../models/alert_payload.dart';
import '../models/nav_destination.dart';
import 'database_replacing.dart';
import 'fresh_preferences.dart';
import 'kept_share_notices.dart';
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

  /// Whether a manager runs the launch's recovery as it is built. The check
  /// that runs with the app closed turns it off for its own isolate before
  /// it opens anything (`docs/cloud-shared-freshness.md` §6): the recovery
  /// writes the active name back and clears the download's marker, and a
  /// background isolate beside a live app must do neither — the manager it
  /// builds only reads.
  static bool recoversAtStart = true;

  static Future<DatabaseManager> _create() async {
    final manager = DatabaseManager._();
    manager._prefs = await SharedPreferences.getInstance();
    if (recoversAtStart) await manager._recoverInterruptedDownload();
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

  /// What [activateAtNextLaunch] left behind: the name this process stays
  /// on, and the stored name that waits for the next launch. Null while the
  /// stored name is this process's own.
  ({String kept, String next})? _waitingForRestart;

  /// The name of the active database: the one this process has open, or
  /// opens first.
  ///
  /// Every reader in a running app pairs it with the open [AppDatabase] —
  /// [AppDatabase.getInstance] itself, the alert scheduler's entries, the
  /// sync claims, the kept notices — so it never moves ahead of that
  /// database: after [activateAtNextLaunch] it stays what it was until the
  /// process ends, and only the stored name has moved, which the next launch
  /// and [peekActiveDatabaseName] read.
  ///
  /// The wait holds only while the stored name is still the one left for
  /// the next launch: any other write of it is a switch to make now.
  String getActiveDatabaseName() {
    final stored = _storedActiveName;
    final waiting = _waitingForRestart;
    if (waiting != null && waiting.next == stored) return waiting.kept;
    return stored;
  }

  String get _storedActiveName =>
      _prefs.getString(_keyActiveDatabase) ??
      defaultDatabaseName(qaEnabled: QaMode.enabled);

  /// The active database's name as the preferences hold it, read and
  /// nothing else — for the check that runs with the app closed
  /// (`docs/cloud-shared-freshness.md` §6). [getInstance] is the launch's:
  /// its recovery writes the active name back and clears the download's
  /// marker, and neither is a background isolate's to do.
  ///
  /// Read off the store itself ([FreshPreferences]): the preferences are a
  /// copy per isolate, and the app's isolate may have switched databases
  /// since this one loaded its own — the name of a database the person
  /// left is the wrong file to measure and to keep notices under.
  static Future<String> peekActiveDatabaseName() async {
    final fresh = await FreshPreferences.read();
    return fresh.getString(_keyActiveDatabase) ??
        defaultDatabaseName(qaEnabled: QaMode.enabled);
  }

  /// [getDatabasePath] for a caller that holds no manager.
  static Future<String> databasePathOf(String name) async {
    final dbFolder = await getApplicationDocumentsDirectory();
    return p.join(dbFolder.path, 'gym_notes', '$name.db');
  }

  /// Makes [name] the active database now: the next
  /// [AppDatabase.getInstance] closes the open database and opens [name]
  /// under this process — the sync download's switch — and before anything
  /// is open, the launch's recovery. A flow that asks for a restart instead
  /// takes [activateAtNextLaunch].
  Future<void> setActiveDatabaseName(String name) async {
    _waitingForRestart = null;
    await _prefs.setString(_keyActiveDatabase, name);
  }

  /// Stores [name] as the database the next launch opens and keeps this
  /// process on the one it has open: for the flows that then ask for a
  /// restart — the Databases page's switch, an alarm of another database.
  ///
  /// [setActiveDatabaseName] switched under them. [AppDatabase.getInstance]
  /// reads the active name on every call, so the first caller after the
  /// write — an alert firing, a resume's reconcile — closed the open
  /// database and opened [name] behind the restart dialog, while the pages
  /// beneath still held the other database's rows and an editor's pending
  /// save had only the new one to land in (settings rework review,
  /// 2026-11-01).
  ///
  /// Throws a [StateError] when [name] has no file: stored, the next launch
  /// would open that name and create it empty — an alarm armed before its
  /// database was renamed or deleted still asks for the old name.
  Future<void> activateAtNextLaunch(String name) async {
    if (!await databaseExists(name)) {
      throw StateError('Database "$name" does not exist');
    }
    // Read before the write: a second call keeps the name the first kept.
    _waitingForRestart = (kept: getActiveDatabaseName(), next: name);
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
  Future<String> getDatabasePath(String name) => databasePathOf(name);

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

  /// Awaited at each [RenameStep] of [renameDatabase], inside the section
  /// [AppDatabase.whileClosed] holds, so a test can ask for the database at
  /// that point — a real rename passes them all in a few milliseconds.
  @visibleForTesting
  static Future<void> Function(RenameStep step)? debugRenameStep;

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
  ///
  /// Marked for the check's isolate while it runs ([DatabaseReplacing]).
  Future<void> importDatabase(
    String sourcePath,
    String targetName, {
    DatabaseImportProgress? progress,
  }) => DatabaseReplacing.run(
    () => _importDatabase(sourcePath, targetName, progress: progress),
  );

  Future<void> _importDatabase(
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
  /// have been tried, whether or not one of them failed: left on the old name,
  /// the next launch would open that name and create it empty, its claim
  /// would hold again, and the heal would unbind the renamed database (final
  /// review X-3, RA2-1). Nothing runs between the `.db` and its sidecars — a
  /// registry write that failed there could split a database from
  /// un-checkpointed pages in its `-wal` — and a registry write that fails is
  /// logged, never thrown; the claim it leaves on the old name, whose file is
  /// gone, reads as free, and the binding service's heal claims the space
  /// again for the bound database that has none.
  ///
  /// The open database is closed before its file moves, and the call says so
  /// by answering true ([AppDatabase.whileClosed] has the reasons): the
  /// caller asks for a restart. The close, the moves and every name write
  /// are one section no [AppDatabase.getInstance] enters.
  ///
  /// A sidecar already under [newName] — a `-wal` a delete could not remove
  /// once its `.db` was gone — is removed before anything moves: SQLite
  /// replays a `-wal` it finds beside a file into it, so it would write the
  /// deleted database's last commits over the renamed one's. One that cannot
  /// be removed fails the rename while every name is still the old one.
  ///
  /// Until the `.db` has moved a failure throws, and the database, when it
  /// was open, is opened again under its old name once the section ends, so
  /// the app is not left on a closed handle. From the move on nothing
  /// throws: a sidecar, the claim or a name that does not follow is logged,
  /// and the call still answers whether the database was closed — the
  /// stored name has moved by then, and only a restart puts every page on
  /// it.
  Future<bool> renameDatabase(String oldName, String newName) async {
    if (!await databaseExists(oldName)) {
      throw Exception('Database "$oldName" does not exist');
    }

    if (await databaseExists(newName)) {
      throw Exception('Database "$newName" already exists');
    }

    await checkpoint(oldName);

    final oldPath = await getDatabasePath(oldName);
    final newPath = await getDatabasePath(newName);

    var closed = false;
    try {
      return await AppDatabase.whileClosed(oldName, (wasOpen) async {
        closed = wasOpen;
        await debugRenameStep?.call(RenameStep.closed);
        for (final suffix in _sidecarSuffixes) {
          final orphan = File('$newPath$suffix');
          if (await orphan.exists()) await orphan.delete();
        }
        await File(oldPath).rename(newPath);
        await _afterRenameMove(oldName, newName, oldPath, newPath);
        return wasOpen;
      });
    } catch (_) {
      // Only a failure before the move reaches here: no name has changed.
      if (closed) {
        try {
          await AppDatabase.getInstance();
        } catch (e, st) {
          debugPrint(
            '[DatabaseManager] not reopened after a failed rename: '
            '$e\n$st',
          );
        }
      }
      rethrow;
    }
  }

  /// [renameDatabase]'s half once the `.db` has moved, which never throws.
  Future<void> _afterRenameMove(
    String oldName,
    String newName,
    String oldPath,
    String newPath,
  ) async {
    for (final suffix in const ['-wal', '-shm']) {
      try {
        final sidecar = File('$oldPath$suffix');
        if (await sidecar.exists()) await sidecar.rename('$newPath$suffix');
      } catch (e, st) {
        debugPrint('[DatabaseManager] $suffix not renamed: $e\n$st');
      }
    }
    await debugRenameStep?.call(RenameStep.moved);

    try {
      await spaceRegistry.rename(oldName, newName);
    } catch (e, st) {
      debugPrint('[DatabaseManager] sync claim not renamed: $e\n$st');
    }

    // The names that meant the renamed database follow it: the stored one
    // — this process's own, or the one a switch left for the next launch,
    // which would otherwise open the old name and create it empty — and
    // the one this process keeps meanwhile.
    final waiting = _waitingForRestart;
    if (waiting != null) {
      _waitingForRestart = (
        kept: waiting.kept == oldName ? newName : waiting.kept,
        next: waiting.next == oldName ? newName : waiting.next,
      );
    }
    try {
      if (_storedActiveName == oldName) {
        await _prefs.setString(_keyActiveDatabase, newName);
      }
    } catch (e, st) {
      debugPrint('[DatabaseManager] active name not renamed: $e\n$st');
    }

    // So do the notices a background check kept in it: they are looked
    // for by name, and the old name would be pruned as a database gone.
    try {
      await KeptShareNotices.databaseRenamed(_prefs, oldName, newName);
    } catch (e, st) {
      debugPrint('[DatabaseManager] kept notices not renamed: $e\n$st');
    }
    await debugRenameStep?.call(RenameStep.named);
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
    // onto the owner's database. Judged by the stored name, the one a launch
    // opens: a database a switch left for the next launch would otherwise
    // stay stored and be created empty — it goes back to the one this
    // process kept. And a kept name whose database is the one deleted keeps
    // nothing: the stored name is all there is.
    if (_waitingForRestart?.kept == name) _waitingForRestart = null;
    if (_storedActiveName == name) {
      final waiting = _waitingForRestart;
      await setActiveDatabaseName(
        waiting != null && waiting.next == name
            ? waiting.kept
            : defaultDatabaseName(qaEnabled: QaMode.enabled),
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

  /// [snapshotForShare]'s strip, over a copy a test made of a database no
  /// manager holds — one of the sync harness's, opened again as the phone a
  /// restore puts it on.
  @visibleForTesting
  static void debugStripCopy(String snapshot) => _stripShared(snapshot);

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
  /// them. Every search row that belongs to no live note goes too, shared
  /// owner or not (share surfaces P1): one a removal left behind before the
  /// removals took theirs along, or one the drain had not dropped yet, still
  /// matches the words of a note that is gone — mine as well: a copy made
  /// before the drain caught up with a note I deleted is written to, its
  /// search rows dropped and its index rebuilt, and that is right, for the
  /// words of a note I deleted do not travel in it either (review B6). Then
  /// the copy is compacted, so no freed page keeps their text.
  ///
  /// The compaction is what clears the body index itself: it is
  /// contentless, so a deleted note's rowid is only marked gone and its
  /// trigrams stay in the segment blobs until they merge — and `VACUUM
  /// INTO` copies those as they are. So a copy of a database that may ever
  /// have held a partner's row is always rebuilt, whatever else it holds
  /// ([_mayHaveHeldTheirs], reviews A3 and B1).
  ///
  /// Kept on purpose (review A5): the pair id in the marks on my own rows
  /// (`shared_pair`, `shared_stamp`) — a mark is my row's state, and what a
  /// restore of my own copy goes on sharing with, while the pairing rows are
  /// a cache the server answers again — and the ids of the partner's
  /// categories inside my own filter lists, saved filters, views, digests
  /// and category alerts: a random id of a category the copy does not hold
  /// says no word, no time and no person, and each list drops it at its
  /// next store.
  ///
  /// A copy of a database that never held a partner's row, with its index
  /// in step and no trace of the partner's, is left exactly as `VACUUM
  /// INTO` wrote it: four reads at most and no write — [_mayHaveHeldTheirs]
  /// one, the orphaned search rows two, the keyed traces one. Its own
  /// orphans are not looked for (review C2).
  static void _stripShared(String snapshot) {
    final connection = sqlite3.open(snapshot, mode: OpenMode.readWrite);
    try {
      final (:owner, :theirs) = _mayHaveHeldTheirs(connection);
      if (!theirs &&
          !_holdsOrphanedSearchRows(connection) &&
          !_holdsPartnerTraces(connection)) {
        return;
      }
      connection.execute('BEGIN');
      try {
        // The fences' licence (`SharedRowDao.writing`): they stand down while
        // this key is present, and it is gone again before the commit.
        if (owner != null) {
          connection.execute(
            'INSERT OR REPLACE INTO sync_metadata (key, value, updated_at) '
            'VALUES (?, ?, 0)',
            [SyncDao.keySharedWriting, '1'],
          );
          _stripOwner(connection, owner);
          connection.execute('DELETE FROM sync_metadata WHERE key = ?', [
            SyncDao.keySharedWriting,
          ]);
        }
        _stripPartnerTraces(connection, theirs: theirs);
        _stripOrphanedSearchRows(connection);
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

  /// The shared owner [connection] names, and whether it may ever have held
  /// a partner's row — so whether its index segments may still hold the
  /// words of one removed — read in one statement. Three arms:
  ///
  /// - the shared owner: it holds them now;
  /// - [SyncDao.keySharedEverHeld]: this database has had a partner to read
  ///   from — set when the reader begins for one, before any row is held,
  ///   on a phone that only gives too — or held theirs under a build before
  ///   the mark (`SharedRowDao.removeAll` sets it as it removes them);
  ///   nothing takes it away;
  /// - any `pairing_` settings row — the legacy arm, for a database that
  ///   paired before the mark existed. It rests on one row: the only writer
  ///   of the pairing rows (`SettingsService.setPairingSettings`) deletes a
  ///   row whose value is null or empty, but always writes
  ///   `pairing_ended_notice_pending` as `true` or `false` — through an
  ///   unpair, the partner's end and another account signing in alike.
  static ({String? owner, bool theirs}) _mayHaveHeldTheirs(
    Database connection,
  ) {
    try {
      final row = connection.select(
        'SELECT (SELECT value FROM sync_metadata WHERE key = ?1) AS owner, '
        'EXISTS(SELECT 1 FROM sync_metadata WHERE key = ?2) '
        'OR EXISTS(SELECT 1 FROM user_settings '
        'WHERE substr(key, 1, ?3) = ?4) AS theirs',
        [
          SyncDao.keySharedOwner,
          SyncDao.keySharedEverHeld,
          SettingsKeys.pairingPrefix.length,
          SettingsKeys.pairingPrefix,
        ],
      ).single;
      final owner = row['owner'] as String?;
      return (owner: owner, theirs: owner != null || row['theirs'] != 0);
    } on SqliteException catch (_) {
      // A database from before sync: it never held a shared row.
      return (owner: null, theirs: false);
    }
  }

  /// Whether [connection] holds a ledger row of a note that is gone,
  /// tombstoned or renumbered, or an index row without a ledger row.
  static bool _holdsOrphanedSearchRows(Database connection) {
    try {
      if (connection
          .select('SELECT 1 FROM (${NoteSearchDao.orphanRowids}) LIMIT 1')
          .isNotEmpty) {
        return true;
      }
    } on SqliteException catch (_) {
      // A database from before the body index: it holds none.
      return false;
    }
    try {
      return connection
          .select(
            'SELECT 1 FROM note_body_fts WHERE rowid NOT IN '
            '(SELECT note_rowid FROM note_search_ledger) LIMIT 1',
          )
          .isNotEmpty;
    } on SqliteException catch (_) {
      // No body index this SQLite can open.
      return false;
    }
  }

  /// Drops the search rows [_holdsOrphanedSearchRows] looks for: run after
  /// the partner's notes went, it takes theirs along with any left before.
  static void _stripOrphanedSearchRows(Database connection) {
    try {
      connection.execute(
        'DELETE FROM note_search_ledger WHERE note_rowid IN '
        '(${NoteSearchDao.orphanRowids})',
      );
    } on SqliteException catch (e) {
      debugPrint('[DatabaseManager] no search ledger to strip: $e');
      return;
    }
    try {
      connection.execute(
        'DELETE FROM note_body_fts WHERE rowid NOT IN '
        '(SELECT note_rowid FROM note_search_ledger)',
      );
    } on SqliteException catch (e) {
      // A build without the body index has none to clear.
      debugPrint('[DatabaseManager] no body index to strip: $e');
    }
  }

  /// What `SharedRowDao.removeAll` removes, on the copy's own connection,
  /// inside [_stripShared]'s transaction and licence.
  static void _stripOwner(Database connection, String owner) {
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
    ]) {
      connection.execute(
        "DELETE FROM sync_metadata WHERE substr(key, 1, ?) = ?",
        [prefix.length, prefix],
      );
    }
  }

  /// What names the partner or their rows outside the shareable tables,
  /// held whether or not a shared row is (share surfaces P6) — a pair can
  /// share nothing my way, or have ended:
  ///
  /// - every `pairing_` row: the pair, the partner's uid and name, an
  ///   invite code. The pairing is a cache the server answers again at the
  ///   next sign-in, and the JSON backup always left it out
  ///   (`BackupService._exportSettings`). The `sync_space_` binding is mine
  ///   and stays: a restore of my own copy claims or unbinds by it
  ///   (`SyncBindingService._healClaim`).
  /// - my choices about their rows, keyed by their ids: the hidden
  ///   categories and my sorts of their folders. The looks I chose for
  ///   their rows name nothing of theirs and stay, as a restore reads them.
  /// - the notices a background check kept (their event titles and name),
  ///   and the pokes owed to their phone, which name the pair.
  static const List<String> _partnerSettings = [
    SettingsKeys.shareHiddenCategories,
    SettingsKeys.shareFolderSorts,
  ];

  /// The `sync_metadata` rows [_stripPartnerTraces] takes by key: the kept
  /// notices, "Sending…" about shares (whether or not a partner's row is
  /// held, review A5), the mark that this database ever held one, and the
  /// record that its old tombstones were emptied.
  static const List<String> _partnerMetadata = [
    SyncDao.keyShareNoticesKept,
    SyncDao.keyShareSending,
    SyncDao.keySharedEverHeld,
    SyncDao.keySharedTombstonesEmptied,
  ];

  /// Whether [connection] holds any row [_stripPartnerTraces] takes.
  static bool _holdsPartnerTraces(Database connection) {
    try {
      final found = connection.select(
        'SELECT EXISTS(SELECT 1 FROM user_settings '
        'WHERE substr(key, 1, ?1) = ?2 OR key IN (?3, ?4)) '
        'OR EXISTS(SELECT 1 FROM sync_metadata '
        'WHERE key IN (?5, ?6, ?7, ?8) OR substr(key, 1, ?9) = ?10) AS found',
        [
          SettingsKeys.pairingPrefix.length,
          SettingsKeys.pairingPrefix,
          ..._partnerSettings,
          ..._partnerMetadata,
          SyncDao.sharePokeOwedPrefix.length,
          SyncDao.sharePokeOwedPrefix,
        ],
      );
      return found.single['found'] != 0;
    } on SqliteException catch (_) {
      // A database from before pairing: it never knew a partner.
      return false;
    }
  }

  /// The rows of mine that hang on an event or a note the copy does not
  /// hold — after [_stripOwner], every one of the partner's, and one a
  /// reader removed before (review A5), as `(table, condition, synced)`:
  /// my alerts, presence marks and the scheduler's registrations on their
  /// events, which give the days and times of those events; any day row of
  /// mine on one; my counter values on their notes; and the editor's
  /// remembered place and the money ledger's currency of their notes (the
  /// editor saves a place for a read-only note too). The JSON export leaves
  /// them out already. My own events and notes are always held — a delete
  /// leaves a tombstone — so nothing of mine on my rows goes. A global
  /// counter value (`note_id ''`), a digest's registration and a test
  /// alarm's (`AlertPayload.testEventId`) name no event or note of anyone's.
  ///
  /// Looked for only where the database may have held a partner's row
  /// ([_mayHaveHeldTheirs], review C2): elsewhere such a row is an orphan of
  /// my own — an alert pulled before its event, a key an import could not
  /// map — and travels as it always did.
  ///
  /// The live database keeps them, so a share given again finds them; and a
  /// restore of the copy finds them again in my space: for each synced
  /// table a row went from ([synced]), the copy forgets where that table's
  /// pull stood ([_forgetPull], review C1). `alert_registrations` and the
  /// settings rows are device-local — never pulled, a cache the scheduler
  /// and the editor rebuild — and need nothing.
  static final List<(String, String, bool)> _hangingRows = [
    ('calendar_event_alerts', _noEvent, true),
    ('calendar_event_absences', _noEvent, true),
    ('calendar_event_occurrences', _noEvent, true),
    ('calendar_event_skips', _noEvent, true),
    (
      'alert_registrations',
      "source != 'digest' AND event_id != '${AlertPayload.testEventId}' "
          'AND $_noEvent',
      false,
    ),
    (
      'counter_values',
      "note_id != '' AND note_id NOT IN (SELECT id FROM notes)",
      true,
    ),
    (
      'user_settings',
      '${_perNote(SettingsKeys.notePositionPrefix)} '
          'OR ${_perNote(SettingsKeys.moneyNoteCurrencyPrefix)}',
      false,
    ),
  ];

  /// Makes the next pull read [table] from its start: its cursor, the mark
  /// that the cursor was settled, and what the space's signal last said of
  /// it, without which the table reads as stale and is pulled
  /// (`SyncEngine._staleTables`) — the three a bind deletes for every table.
  static void _forgetPull(Database connection, String table) {
    connection.execute('DELETE FROM sync_metadata WHERE key IN (?, ?, ?)', [
      SyncDao.keyPullCursor(table),
      SyncDao.keyPullSettled(table),
      SyncDao.keyPullSeen(table),
    ]);
  }

  static const String _noEvent =
      'event_id NOT IN (SELECT id FROM calendar_events)';

  /// A `user_settings` key of [prefix] followed by the id of a note the copy
  /// does not hold. [prefix] is a constant of `SettingsKeys`, never input.
  static String _perNote(String prefix) =>
      "(substr(key, 1, ${prefix.length}) = '$prefix' AND "
      'substr(key, ${prefix.length + 1}) NOT IN (SELECT id FROM notes))';

  /// Takes out what [_partnerSettings] and [_partnerMetadata] say, and,
  /// where [theirs], what [_hangingRows] says and the remembered location
  /// when [_stackNamesAbsentRows]; run after [_stripOwner].
  static void _stripPartnerTraces(Database connection, {required bool theirs}) {
    for (final (table, condition, synced) in [if (theirs) ..._hangingRows]) {
      try {
        connection.execute('DELETE FROM $table WHERE $condition');
        if (synced && connection.updatedRows > 0) {
          _forgetPull(connection, table);
        }
      } on SqliteException catch (e) {
        debugPrint('[DatabaseManager] not stripped, $table: $e');
      }
    }
    connection.execute(
      'DELETE FROM user_settings WHERE substr(key, 1, ?) = ? OR key IN (?, ?)',
      [
        SettingsKeys.pairingPrefix.length,
        SettingsKeys.pairingPrefix,
        ..._partnerSettings,
      ],
    );
    connection.execute(
      'DELETE FROM sync_metadata WHERE key IN (?, ?, ?, ?) '
      'OR substr(key, 1, ?) = ?',
      [
        ..._partnerMetadata,
        SyncDao.sharePokeOwedPrefix.length,
        SyncDao.sharePokeOwedPrefix,
      ],
    );
    if (theirs && _stackNamesAbsentRows(connection)) {
      connection.execute('UPDATE user_settings SET value = ? WHERE key = ?', [
        NavDestination.encodeStack(const []),
        SettingsKeys.lastLocationStack,
      ]);
    }
  }

  /// Whether the remembered location (`NavDestination`'s stack) names a
  /// folder or a note the copy does not hold — after [_stripOwner], every
  /// one of the partner's, and one a reader removed before. Its entries
  /// carry a folder's title beside its id, so a stack standing in their
  /// folder names it.
  ///
  /// The whole stack is emptied rather than the entries pruned: the stack is
  /// a chain, and one with a hole is one the replay never recorded; it is
  /// worth nothing where the copy is opened, an empty stack reads as "at the
  /// root" (a deleted row would read as never migrated); and every param of
  /// every kind is read — a newer build's kind included — so no entry has to
  /// be understood to be judged. A row that cannot be read is emptied too,
  /// as a launch would read it.
  static bool _stackNamesAbsentRows(Database connection) {
    final rows = connection.select(
      'SELECT value FROM user_settings WHERE key = ?',
      [SettingsKeys.lastLocationStack],
    );
    if (rows.isEmpty) return false;
    final folders = <String>{};
    final notes = <String>{};
    try {
      final stack = jsonDecode(rows.single['value'] as String);
      if (stack is! Map || stack['stack'] is! List) return true;
      for (final entry in stack['stack'] as List) {
        final params = entry is Map ? entry['p'] : null;
        if (params is! Map) continue;
        if (params['folderId'] case final String id) folders.add(id);
        if (params['noteId'] case final String id) notes.add(id);
      }
    } on FormatException catch (_) {
      return true;
    }
    for (final (table, ids) in [('folders', folders), ('notes', notes)]) {
      if (ids.isEmpty) continue;
      final held = connection.select(
        'SELECT count(*) AS n FROM $table WHERE id IN '
        '(${List.filled(ids.length, '?').join(', ')})',
        ids.toList(),
      );
      if (held.single['n'] != ids.length) return true;
    }
    return false;
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

/// Where [DatabaseManager.debugRenameStep] stops a rename: the open
/// database closed and nothing moved yet; the `.db` and its sidecars moved
/// and no name changed yet; every name changed, the section not yet left.
enum RenameStep { closed, moved, named }

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
