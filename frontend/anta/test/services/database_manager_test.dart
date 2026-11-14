import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/alert_payload.dart';
import 'package:anta/models/nav_destination.dart';
import 'package:anta/services/body_search_indexer.dart';
import 'package:anta/services/database_manager.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/sync_gateway.dart';

import '../support/scripted_prefs_store.dart';
import 'support/body_index_support.dart';

/// `DatabaseManager.checkpoint` is what makes a shared `.db` whole: the app
/// runs in WAL, so committed writes sit in the `-wal` sidecar until a
/// checkpoint folds them back, and a share hands over the main file alone
/// (S2 of the settings rework, `docs/settings-rework-roadmap.md`, D8).
///
/// Everything is file-backed in a temporary documents directory — an
/// in-memory database never journals. "The main file holds the rows" is read
/// from a copy of the `.db` taken without its sidecars, which is exactly what
/// a share sees.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DatabaseManager manager;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_db_manager');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    manager = await DatabaseManager.getInstance();
  });

  tearDown(() async {
    // Closes the open database and empties the directory.
    await AppDatabase.deleteAllData();
  });

  tearDownAll(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  /// Opens a copy of [dbPath] taken without its sidecars and runs [read].
  T readMainFileAlone<T>(String dbPath, T Function(Database db) read) {
    final copyPath = p.join(tempDir.path, 'copy.db');
    File(dbPath).copySync(copyPath);
    final copy = sqlite3.open(copyPath);
    try {
      return read(copy);
    } finally {
      copy.close();
      for (final suffix in ['', '-wal', '-shm']) {
        final file = File('$copyPath$suffix');
        if (file.existsSync()) file.deleteSync();
      }
    }
  }

  int count(Database db, String sql) =>
      db.select(sql).single.values.first as int;

  /// Leaves [name] as an app quit before folding leaves it: a `.db` and a
  /// `-wal` holding 300 items the main file does not, copied in from a
  /// writer elsewhere while it still held them open.
  Future<String> leaveInSidecar(String name) async {
    final sourcePath = p.join(tempDir.path, 'writer', '$name.db');
    await Directory(p.dirname(sourcePath)).create(recursive: true);
    final targetPath = await manager.getDatabasePath(name);
    await Directory(p.dirname(targetPath)).create(recursive: true);
    final writer = sqlite3.open(sourcePath);
    try {
      writer.execute('PRAGMA journal_mode = WAL');
      writer.execute('PRAGMA wal_autocheckpoint = 0');
      writer.execute('CREATE TABLE items (v TEXT)');
      writer.execute(
        'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n '
        'WHERE x < 300) INSERT INTO items SELECT hex(randomblob(100)) FROM n',
      );
      File(sourcePath).copySync(targetPath);
      File('$sourcePath-wal').copySync('$targetPath-wal');
    } finally {
      writer.close();
      for (final suffix in ['', '-wal', '-shm']) {
        final file = File('$sourcePath$suffix');
        if (file.existsSync()) file.deleteSync();
      }
    }
    expect(File('$targetPath-wal').lengthSync(), greaterThan(0));
    return targetPath;
  }

  /// Whether [path]'s `-wal` still holds frames.
  bool walHasContent(String path) {
    final wal = File('$path-wal');
    return wal.existsSync() && wal.lengthSync() > 0;
  }

  test('the open database folds its WAL into the main file on its own '
      'connection', () async {
    final db = await AppDatabase.getInstance();
    final path = await manager.getDatabasePath(manager.getActiveDatabaseName());
    // Past the WAL's 1,000-page auto-checkpoint, so the sidecar is large and
    // already partly folded; the folder written last sits in the WAL alone.
    await db.customStatement('CREATE TABLE ballast (v TEXT)');
    await db.customStatement(
      'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n '
      'WHERE x < 2500) INSERT INTO ballast SELECT hex(randomblob(1000)) FROM n',
    );
    await db.folderDao.createFolder(name: 'Latest');

    const latestSql = "SELECT count(*) FROM folders WHERE name = 'Latest'";
    expect(File('$path-wal').lengthSync(), greaterThan(0));
    expect(
      readMainFileAlone(path, (copy) => count(copy, latestSql)),
      0,
      reason: 'before the checkpoint a copy of the .db lacks the last write',
    );

    await manager.checkpoint(manager.getActiveDatabaseName());

    expect(File('$path-wal').lengthSync(), 0);
    expect(readMainFileAlone(path, (copy) => count(copy, latestSql)), 1);
    expect(
      readMainFileAlone(
        path,
        (copy) => count(copy, 'SELECT count(*) FROM ballast'),
      ),
      2500,
    );
    // The live connection is the same one, still usable.
    expect(identical(await AppDatabase.getInstance(), db), isTrue);
  });

  test('another database with a sidecar left behind is folded on a '
      'short-lived connection', () async {
    // A WAL database written elsewhere, its files copied in while the writer
    // still holds them open — the shape an app quit before folding leaves.
    final sourcePath = p.join(tempDir.path, 'source', 'work.db');
    await Directory(p.dirname(sourcePath)).create(recursive: true);
    final writer = sqlite3.open(sourcePath);
    final targetPath = await manager.getDatabasePath('work');
    await Directory(p.dirname(targetPath)).create(recursive: true);
    try {
      writer.execute('PRAGMA journal_mode = WAL');
      writer.execute('PRAGMA wal_autocheckpoint = 0');
      writer.execute('CREATE TABLE items (v TEXT)');
      writer.execute(
        'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n '
        'WHERE x < 300) INSERT INTO items SELECT hex(randomblob(100)) FROM n',
      );
      File(sourcePath).copySync(targetPath);
      File('$sourcePath-wal').copySync('$targetPath-wal');
    } finally {
      writer.close();
    }
    expect(File('$targetPath-wal').lengthSync(), greaterThan(0));
    expect(
      readMainFileAlone(
        targetPath,
        (copy) => count(
          copy,
          "SELECT count(*) FROM sqlite_master WHERE name = 'items'",
        ),
      ),
      0,
      reason: 'the table exists only in the sidecar',
    );

    await manager.checkpoint('work');

    final wal = File('$targetPath-wal');
    expect(!wal.existsSync() || wal.lengthSync() == 0, isTrue);
    expect(
      readMainFileAlone(
        targetPath,
        (copy) => count(copy, 'SELECT count(*) FROM items'),
      ),
      300,
    );
    expect(AppDatabase.openInstanceOf('work'), isNull);
  });

  test(
    'a database with no sidecar is left alone and nothing is opened',
    () async {
      await manager.createDatabase('quiet');
      final path = await manager.getDatabasePath('quiet');

      await manager.checkpoint('quiet');
      await manager.checkpoint(manager.getActiveDatabaseName());

      expect(File(path).lengthSync(), 0);
      expect(File('$path-wal').existsSync(), isFalse);
      expect(AppDatabase.openInstanceOf('quiet'), isNull);
      expect(
        AppDatabase.openInstanceOf(manager.getActiveDatabaseName()),
        isNull,
        reason: 'a checkpoint never opens the database it was asked about',
      );
    },
  );

  test('a sidecar with no database beside it creates nothing', () async {
    final path = await manager.getDatabasePath('orphan');
    await Directory(p.dirname(path)).create(recursive: true);
    File('$path-wal').writeAsBytesSync([1, 2, 3]);

    await manager.checkpoint('orphan');

    expect(File(path).existsSync(), isFalse);
    expect(File('$path-wal').readAsBytesSync(), [1, 2, 3]);
    expect(
      (await manager.listDatabases()).map((db) => db.name),
      isNot(contains('orphan')),
    );
  });

  test('renaming a database with writes left in its sidecar folds them into '
      'the renamed file first', () async {
    await leaveInSidecar('work');
    final oldPath = await manager.getDatabasePath('work');

    await manager.renameDatabase('work', 'office');

    final newPath = await manager.getDatabasePath('office');
    expect(File(oldPath).existsSync(), isFalse);
    expect(walHasContent(oldPath), isFalse);
    expect(
      walHasContent(newPath),
      isFalse,
      reason: 'nothing a kill between the renames could strand',
    );
    expect(
      readMainFileAlone(
        newPath,
        (copy) => count(copy, 'SELECT count(*) FROM items'),
      ),
      300,
    );
    expect(AppDatabase.openInstanceOf('office'), isNull);
  });

  test(
    'a sidecar rename that fails still reports the failure, yet the sync '
    'claim and the active name follow the `.db` (review BA-M6, RA2-1)',
    () async {
      const space = SyncSpaceRef(ownerUid: 'uid-1', spaceId: 'space-1');
      await manager.createDatabase('work');
      await manager.spaceRegistry.claim(space, 'work');
      await manager.setActiveDatabaseName('work');
      addTearDown(() async {
        await (await SharedPreferences.getInstance()).remove(
          SettingsKeys.syncBoundSpaces,
        );
        await manager.setActiveDatabaseName('gym_notes');
      });
      // A stray `-shm` beside a closed database, and a directory where its
      // renamed twin must go: the `.db` moves, then the sidecar's rename fails.
      // Closed, because Windows cannot rename an open file.
      final oldPath = await manager.getDatabasePath('work');
      File('$oldPath-shm').writeAsStringSync('stray');
      final newPath = await manager.getDatabasePath('office');
      Directory('$newPath-shm/blocked').createSync(recursive: true);

      await expectLater(
        manager.renameDatabase('work', 'office'),
        throwsA(isA<FileSystemException>()),
      );

      expect(File(newPath).existsSync(), isTrue);
      expect(manager.spaceRegistry.claims().single.databaseName, 'office');
      expect(await manager.spaceRegistry.holderOf(space), 'office');
      expect(manager.getActiveDatabaseName(), 'office');
    },
  );

  test('a registry write that fails during a rename is logged: every file '
      'still moves and the rename completes (final review X-3)', () async {
    const space = SyncSpaceRef(ownerUid: 'uid-1', spaceId: 'space-1');
    await manager.createDatabase('work');
    await manager.spaceRegistry.claim(space, 'work');
    await manager.setActiveDatabaseName('work');
    final previous = SharedPreferencesStorePlatform.instance;
    SharedPreferencesStorePlatform.instance = ScriptedPrefsStore()
      ..failWrite = (key) => key == SettingsKeys.syncBoundSpaces;
    addTearDown(() async {
      SharedPreferencesStorePlatform.instance = previous;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(SettingsKeys.syncBoundSpaces);
      await manager.setActiveDatabaseName('gym_notes');
    });
    // A closed file's `-wal` is folded and removed by the checkpoint before
    // any file moves, so the sidecar left to carry here is the `-shm`.
    final oldPath = await manager.getDatabasePath('work');
    File('$oldPath-shm').writeAsStringSync('stray');

    await manager.renameDatabase('work', 'office');

    final newPath = await manager.getDatabasePath('office');
    expect(File(newPath).existsSync(), isTrue);
    expect(File('$newPath-shm').readAsStringSync(), 'stray');
    // The two `-wal` checks document the checkpoint-first contract; on a
    // closed file they cannot fail, so they do not pin it.
    for (final suffix in ['', '-wal', '-shm']) {
      expect(File('$oldPath$suffix').existsSync(), isFalse, reason: suffix);
    }
    expect(File('$newPath-wal').existsSync(), isFalse);
    expect(manager.getActiveDatabaseName(), 'office');
  });

  group('a blocked checkpoint throws', () {
    test('on the live connection, which stays writable and folds once the '
        'reader is gone', () async {
      final db = await AppDatabase.getInstance();
      final name = manager.getActiveDatabaseName();
      final path = await manager.getDatabasePath(name);
      await db.folderDao.createFolder(name: 'In the WAL');
      expect(File('$path-wal').lengthSync(), greaterThan(0));

      // A foreign reader holding a snapshot of the WAL.
      final reader = sqlite3.open(path, mode: OpenMode.readWrite);
      Object? error;
      try {
        reader.execute('BEGIN');
        reader.select('SELECT count(*) FROM folders');
        try {
          await manager.checkpoint(name);
        } catch (e) {
          error = e;
        }
        reader.execute('COMMIT');
      } finally {
        reader.close();
      }
      expect(error, isA<StateError>());

      await db.folderDao.createFolder(name: 'Still writable');
      await manager.checkpoint(name);
      expect(File('$path-wal').lengthSync(), 0);
      expect(
        readMainFileAlone(
          path,
          (copy) => count(copy, 'SELECT count(*) FROM folders'),
        ),
        2,
      );
    });

    test('on the short-lived connection, which it still closes', () async {
      final path = await manager.getDatabasePath('work');
      await Directory(p.dirname(path)).create(recursive: true);
      final writer = sqlite3.open(path);
      Object? error;
      try {
        writer.execute('PRAGMA journal_mode = WAL');
        writer.execute('PRAGMA wal_autocheckpoint = 0');
        writer.execute('CREATE TABLE t (v)');
        writer.execute('INSERT INTO t VALUES (1)');
        writer.execute('BEGIN');
        writer.select('SELECT * FROM t');
        try {
          await manager.checkpoint('work');
        } catch (e) {
          error = e;
        }
        writer.execute('COMMIT');
      } finally {
        writer.close();
      }
      expect(error, isA<StateError>());
      expect(AppDatabase.openInstanceOf('work'), isNull);
      // SQLite folds and removes the sidecar only as the last connection
      // closes: had the checkpoint's own connection stayed open, the
      // writer's close would not have been the last.
      expect(File('$path-wal').existsSync(), isFalse);
      expect(File(path).existsSync(), isTrue);
    });
  });

  test('a name stored as active but not yet open takes the file branch and '
      'opens nothing', () async {
    final path = await leaveInSidecar('later');
    await manager.setActiveDatabaseName('later');
    addTearDown(() => manager.setActiveDatabaseName('gym_notes'));
    expect(AppDatabase.openInstanceOf('later'), isNull);

    await manager.checkpoint('later');

    expect(walHasContent(path), isFalse);
    expect(
      readMainFileAlone(
        path,
        (copy) => count(copy, 'SELECT count(*) FROM items'),
      ),
      300,
    );
    expect(AppDatabase.openInstanceOf('later'), isNull);
  });

  // S18 (D11): the share hands over a `VACUUM INTO` copy, so no checkpoint —
  // which a reader can block — stands between a write and the shared file.
  group('the share snapshot', () {
    final snapshotFolder = RegExp(
      '^${DatabaseManager.shareSnapshotPrefix}\\d+\$',
    );

    /// The snapshot folders in the temp directory, by name.
    Set<String> snapshotFolders() => {
      for (final entity in tempDir.listSync())
        if (entity is Directory &&
            p.basename(entity.path).startsWith('anta_db_share_'))
          p.basename(entity.path),
    };

    tearDown(() {
      for (final name in snapshotFolders()) {
        Directory(p.join(tempDir.path, name)).deleteSync(recursive: true);
      }
    });

    /// Catches [db]'s body index up, as a launch or a search would.
    Future<void> indexAll(AppDatabase db) => BodySearchIndexer(
      database: db,
      scheduler: inlineBodyIndexScheduler,
    ).drain();

    const matching =
        'SELECT count(*) FROM note_body_fts WHERE note_body_fts MATCH ?';

    Future<int> liveHits(AppDatabase db, String word) async =>
        (await db
                    .customSelect(
                      matching,
                      variables: [Variable<String>('"$word"')],
                    )
                    .getSingle())
                .data
                .values
                .single
            as int;

    /// The projections in [copy]'s body index that hold [word].
    int hitsIn(Database copy, String word) =>
        copy.select(matching, ['"$word"']).single.values.first as int;

    int ledgerOf(Database copy, String noteId) =>
        copy
                .select(
                  'SELECT count(*) FROM note_search_ledger WHERE note_id = ?',
                  [noteId],
                )
                .single
                .values
                .first
            as int;

    test('the open database is copied beside the app\'s connection, the '
        'write still in its WAL included', () async {
      final db = await AppDatabase.getInstance();
      final name = manager.getActiveDatabaseName();
      final path = await manager.getDatabasePath(name);
      await db.folderDao.createFolder(name: 'Latest');
      expect(walHasContent(path), isTrue);

      final snapshot = await manager.snapshotForShare(name);

      expect(p.basename(snapshot), '$name.db');
      expect(p.dirname(p.dirname(snapshot)), tempDir.path);
      expect(p.basename(p.dirname(snapshot)), matches(snapshotFolder));
      final copy = sqlite3.open(snapshot, mode: OpenMode.readOnly);
      try {
        expect(
          count(copy, "SELECT count(*) FROM folders WHERE name = 'Latest'"),
          1,
        );
      } finally {
        copy.close();
      }
      // Nothing was folded to take it, and the app's connection is the same
      // one, still writing.
      expect(walHasContent(path), isTrue);
      expect(identical(await AppDatabase.getInstance(), db), isTrue);
      await db.folderDao.createFolder(name: 'After');
    });

    test('a copy that leaves the phone holds only my rows: the partner\'s, '
        'their text and the shared reader\'s records are stripped, mine kept '
        '(share surfaces D19)', () async {
      const partner = 'partner-uid';
      final db = await AppDatabase.getInstance();
      final name = manager.getActiveDatabaseName();
      final mine = await db.folderDao.createFolder(name: 'Mine to send');
      final mineNote = await db.noteDao.createNote(
        folderId: mine.id,
        title: 'My note',
        content: 'my text',
      );
      final theirs = await db.folderDao.createFolder(name: 'Theirs');
      final theirNote = await db.noteDao.createNote(
        folderId: theirs.id,
        title: 'Their note',
        content: 'their secret text',
      );
      await db.calendarEventDao.upsert(
        CalendarEventsCompanion.insert(
          id: 'their-event',
          title: 'Their event',
          category: 'general',
          startDate: DateTime.utc(2026, 6, 1),
          ruleKind: 'weekly',
          createdAt: DateTime.utc(2026, 6, 1),
          updatedAt: DateTime.utc(2026, 6, 1),
        ),
      );
      for (final (table, id) in [
        ('folders', theirs.id),
        ('notes', theirNote.id),
        ('calendar_events', 'their-event'),
      ]) {
        await db.customStatement(
          "UPDATE $table SET owner_id = '$partner' WHERE id = ?",
          [id],
        );
      }
      await db.syncDao.setValue(SyncDao.keySharedOwner, partner);
      await db.syncDao.setValue(SyncDao.keySharedCursor('notes'), 'cursor');
      await db.customStatement(
        'INSERT INTO user_settings (key, value, updated_at) VALUES (?, ?, 0)',
        [SettingsKeys.shareHiddenCategories, '["theirs"]'],
      );
      await db.customStatement(
        'INSERT INTO user_settings (key, value, updated_at) VALUES (?, ?, 0)',
        [SettingsKeys.shareFolderSorts, '{"their-folder":"name"}'],
      );
      await db.syncDao.oweSharePoke(pairId: 'pair-1', urgent: true);
      addTearDown(() async {
        await db.sharedRowDao.removeAll();
      });
      await indexAll(db);
      expect(await liveHits(db, 'secret'), 1);

      final snapshot = await manager.snapshotForShare(name);

      final copy = sqlite3.open(snapshot, mode: OpenMode.readOnly);
      try {
        for (final table in ['folders', 'notes', 'calendar_events']) {
          expect(
            count(
              copy,
              "SELECT count(*) FROM $table WHERE owner_id = '$partner'",
            ),
            0,
            reason: '$table of the partner\'s',
          );
        }
        expect(
          count(
            copy,
            "SELECT count(*) FROM content_chunks WHERE note_id = '${theirNote.id}'",
          ),
          0,
          reason: 'their text goes with their note',
        );
        expect(
          count(
            copy,
            "SELECT count(*) FROM sync_metadata WHERE key LIKE 'shared%'",
          ),
          0,
        );
        expect(
          count(
            copy,
            'SELECT count(*) FROM user_settings WHERE key IN '
            "('${SettingsKeys.shareHiddenCategories}', "
            "'${SettingsKeys.shareFolderSorts}')",
          ),
          0,
        );
        expect(
          count(
            copy,
            'SELECT count(*) FROM sync_metadata WHERE key LIKE '
            "'${SyncDao.sharePokeOwedPrefix}%'",
          ),
          0,
          reason: 'what this phone owes its partner stays on it',
        );
        expect(
          count(copy, "SELECT count(*) FROM folders WHERE id = '${mine.id}'"),
          1,
        );
        expect(
          count(
            copy,
            'SELECT count(*) FROM content_chunks c JOIN notes n '
            "ON n.id = c.note_id WHERE n.folder_id = '${mine.id}'",
          ),
          greaterThan(0),
          reason: 'my text stays',
        );
        expect(hitsIn(copy, 'secret'), 0, reason: 'their words are not found');
        expect(ledgerOf(copy, theirNote.id), 0);
        expect(hitsIn(copy, 'my text'), 1, reason: 'my search rows stay');
        expect(ledgerOf(copy, mineNote.id), 1);
      } finally {
        copy.close();
      }
      expect(
        await db.sharedRowDao.isShared('notes', theirNote.id),
        isTrue,
        reason: 'the live database is untouched',
      );
    });

    /// A partner's note held here, indexed, under [partner] as the reader
    /// stores it, with the database reading [partner]'s shared rows.
    Future<Note> indexedPartnerNote(AppDatabase db, String partner) async {
      final folder = await db.folderDao.createFolder(name: 'Clinic');
      final note = await db.noteDao.createNote(
        folderId: folder.id,
        title: 'Their visit',
        content: 'the diagnosis',
      );
      for (final (table, id) in [('folders', folder.id), ('notes', note.id)]) {
        await db.customStatement(
          'UPDATE $table SET owner_id = ? WHERE id = ?',
          [partner, id],
        );
      }
      await db.syncDao.setValue(SyncDao.keySharedOwner, partner);
      // As `SharedRowDao.begin` leaves it, the first time this database
      // reads a partner's rows.
      await db.syncDao.setValue(SyncDao.keySharedEverHeld, '1');
      await indexAll(db);
      expect(await liveHits(db, 'diagnosis'), 1);
      return note;
    }

    /// Whether any segment of [copy]'s body index still holds a trigram of
    /// [word] in its raw bytes — what a `MATCH` cannot see once the rowid
    /// is deleted, and a `VACUUM INTO` copies as it is (review A3).
    bool segmentsHold(Database copy, String word) {
      final trigrams = {
        for (var at = 0; at + 3 <= word.length; at++)
          word.substring(at, at + 3),
      };
      for (final row in copy.select('SELECT block FROM note_body_fts_data')) {
        final block = row['block'];
        if (block is! List<int>) continue;
        final text = String.fromCharCodes(block);
        if (trigrams.any(text.contains)) return true;
      }
      return false;
    }

    test('a partner\'s note the reader removed while the pair goes on leaves '
        'no search row behind, here or in a copy that leaves (P1)', () async {
      const partner = 'partner-uid';
      final db = await AppDatabase.getInstance();
      final name = manager.getActiveDatabaseName();
      final note = await indexedPartnerNote(db, partner);
      addTearDown(() async {
        await db.sharedRowDao.removeAll();
      });

      await db.sharedRowDao.removeAbsent('notes', partner, const {});

      expect(await liveHits(db, 'diagnosis'), 0);
      final snapshot = await manager.snapshotForShare(name);
      final copy = sqlite3.open(snapshot, mode: OpenMode.readOnly);
      try {
        expect(hitsIn(copy, 'diagnosis'), 0);
        expect(ledgerOf(copy, note.id), 0);
      } finally {
        copy.close();
      }
    });

    test('after the pair ended, a partner\'s removed note leaves no search '
        'row behind, here or in a copy that leaves (P1)', () async {
      const partner = 'partner-uid';
      final db = await AppDatabase.getInstance();
      final name = manager.getActiveDatabaseName();
      final note = await indexedPartnerNote(db, partner);

      await db.sharedRowDao.removeAll();

      expect(await liveHits(db, 'diagnosis'), 0);
      final snapshot = await manager.snapshotForShare(name);
      final copy = sqlite3.open(snapshot, mode: OpenMode.readOnly);
      try {
        expect(hitsIn(copy, 'diagnosis'), 0);
        expect(ledgerOf(copy, note.id), 0);
        expect(
          segmentsHold(copy, 'diagnosis'),
          isFalse,
          reason:
              'the index is rebuilt compactly in a copy of a database '
              'that ever held a partner\'s row (A3)',
        );
        expect(
          count(
            copy,
            "SELECT count(*) FROM sync_metadata WHERE key = "
            "'${SyncDao.keySharedEverHeld}'",
          ),
          0,
          reason: 'the copy does not say it ever held one',
        );
      } finally {
        copy.close();
      }
    });

    test('a copy drops every search row that belongs to no note, whether or '
        'not a shared owner is set — what an earlier build left behind '
        '(P1)', () async {
      final db = await AppDatabase.getInstance();
      final name = manager.getActiveDatabaseName();
      final folder = await db.folderDao.createFolder(name: 'Kept');
      final kept = await db.noteDao.createNote(
        folderId: folder.id,
        title: 'Kept',
        content: 'still here',
      );
      final gone = await db.noteDao.createNote(
        folderId: folder.id,
        title: 'Gone',
        content: 'the diagnosis',
      );
      await indexAll(db);
      // Removed the way a build before this fix removed a partner's note:
      // the row and its text, never its search rows.
      await db.customStatement('DELETE FROM content_chunks WHERE note_id = ?', [
        gone.id,
      ]);
      await db.customStatement('DELETE FROM notes WHERE id = ?', [gone.id]);
      expect(await liveHits(db, 'diagnosis'), 1);

      final snapshot = await manager.snapshotForShare(name);

      final copy = sqlite3.open(snapshot, mode: OpenMode.readOnly);
      try {
        expect(hitsIn(copy, 'diagnosis'), 0);
        expect(ledgerOf(copy, gone.id), 0);
        expect(hitsIn(copy, 'still here'), 1, reason: 'my search rows stay');
        expect(ledgerOf(copy, kept.id), 1);
      } finally {
        copy.close();
      }
    });

    Future<void> setting(AppDatabase db, String key, String value) =>
        db.customStatement(
          'INSERT OR REPLACE INTO user_settings (key, value, updated_at) '
          'VALUES (?, ?, 0)',
          [key, value],
        );

    String? settingIn(Database copy, String key) =>
        copy.select('SELECT value FROM user_settings WHERE key = ?', [
              key,
            ]).firstOrNull?['value']
            as String?;

    test('a copy made while I stand in the partner\'s folder carries no '
        'location that names it: the stack is emptied there, here it stays '
        '(P6)', () async {
      const partner = 'partner-uid';
      final db = await AppDatabase.getInstance();
      final name = manager.getActiveDatabaseName();
      final mine = await db.folderDao.createFolder(name: 'Home');
      final theirs = await db.folderDao.createFolder(name: 'Their clinic');
      final theirNote = await db.noteDao.createNote(
        folderId: theirs.id,
        title: 'Visit',
        content: 'text',
      );
      for (final (table, id) in [
        ('folders', theirs.id),
        ('notes', theirNote.id),
      ]) {
        await db.customStatement(
          'UPDATE $table SET owner_id = ? WHERE id = ?',
          [partner, id],
        );
      }
      await db.syncDao.setValue(SyncDao.keySharedOwner, partner);
      addTearDown(() async {
        await db.sharedRowDao.removeAll();
      });
      final standing = NavDestination.encodeStack([
        NavDestination.folder(folderId: mine.id, title: 'Home'),
        NavDestination.folder(folderId: theirs.id, title: 'Their clinic'),
        NavDestination.note(noteId: theirNote.id, folderId: theirs.id),
      ]);
      await setting(db, SettingsKeys.lastLocationStack, standing);

      final snapshot = await manager.snapshotForShare(name);

      final copy = sqlite3.open(snapshot, mode: OpenMode.readOnly);
      try {
        expect(
          settingIn(copy, SettingsKeys.lastLocationStack),
          NavDestination.encodeStack(const []),
          reason: 'an empty stack, which a launch reads as "at the root"',
        );
      } finally {
        copy.close();
      }
      expect(
        await db.userSettingsDao.getValue(SettingsKeys.lastLocationStack),
        standing,
      );
    });

    test('a stack that names only my rows leaves in the copy as it was '
        '(P6)', () async {
      const partner = 'partner-uid';
      final db = await AppDatabase.getInstance();
      final name = manager.getActiveDatabaseName();
      final mine = await db.folderDao.createFolder(name: 'Home');
      final myNote = await db.noteDao.createNote(
        folderId: mine.id,
        title: 'Mine',
        content: 'text',
      );
      final theirs = await db.folderDao.createFolder(name: 'Their clinic');
      await db.customStatement('UPDATE folders SET owner_id = ? WHERE id = ?', [
        partner,
        theirs.id,
      ]);
      await db.syncDao.setValue(SyncDao.keySharedOwner, partner);
      addTearDown(() async {
        await db.sharedRowDao.removeAll();
      });
      final standing = NavDestination.encodeStack([
        NavDestination.folder(folderId: mine.id, title: 'Home'),
        NavDestination.note(noteId: myNote.id, folderId: mine.id),
        NavDestination(NavDestinationKind.calendar),
      ]);
      await setting(db, SettingsKeys.lastLocationStack, standing);

      final snapshot = await manager.snapshotForShare(name);

      final copy = sqlite3.open(snapshot, mode: OpenMode.readOnly);
      try {
        expect(settingIn(copy, SettingsKeys.lastLocationStack), standing);
      } finally {
        copy.close();
      }
    });

    test('a copy leaves no name or trace of the partner\'s with no shared row '
        'held — the pairing, the kept notices, the owed pokes, the choices '
        'about their rows, a stack naming a folder of theirs already '
        'removed — and keeps what a restore of my own copy needs: the '
        'binding and my look preferences (P6)', () async {
      final db = await AppDatabase.getInstance();
      final name = manager.getActiveDatabaseName();
      final pairing = {
        SettingsKeys.pairingPairId: 'pair-1',
        SettingsKeys.pairingAccountUid: 'my-uid',
        SettingsKeys.pairingPartnerUid: 'partner-uid',
        SettingsKeys.pairingPartnerName: 'Ana Partner',
        SettingsKeys.pairingPendingCode: 'ABC123',
        SettingsKeys.pairingEndedPair: 'pair-0',
        SettingsKeys.pairingLastPair: 'pair-1',
      };
      for (final MapEntry(:key, :value) in pairing.entries) {
        await setting(db, key, value);
      }
      final binding = {
        SettingsKeys.syncSpaceId: 'space-1',
        SettingsKeys.syncSpaceOwnerUid: 'my-uid',
        SettingsKeys.syncSpaceAccountUid: 'my-uid',
        SettingsKeys.syncSpaceBoundAt: '1',
        SettingsKeys.shareEventLook: 'outlined',
        SettingsKeys.shareNoteLook: 'avatar',
      };
      for (final MapEntry(:key, :value) in binding.entries) {
        await setting(db, key, value);
      }
      await setting(db, SettingsKeys.shareHiddenCategories, '["theirs"]');
      await setting(db, SettingsKeys.shareFolderSorts, '{"gone":"name"}');
      await setting(
        db,
        SettingsKeys.lastLocationStack,
        NavDestination.encodeStack([
          NavDestination.folder(folderId: 'gone', title: 'Their clinic'),
        ]),
      );
      await db.syncDao.setValue(
        SyncDao.keyShareNoticesKept,
        '{"from":"Ana Partner","titles":["Their event"]}',
      );
      await db.syncDao.oweSharePoke(pairId: 'pair-1', urgent: false);

      final snapshot = await manager.snapshotForShare(name);

      final copy = sqlite3.open(snapshot, mode: OpenMode.readOnly);
      try {
        for (final key in [
          ...pairing.keys,
          SettingsKeys.shareHiddenCategories,
          SettingsKeys.shareFolderSorts,
        ]) {
          expect(settingIn(copy, key), isNull, reason: key);
        }
        expect(
          count(
            copy,
            'SELECT count(*) FROM sync_metadata WHERE key = '
            "'${SyncDao.keyShareNoticesKept}' OR key LIKE "
            "'${SyncDao.sharePokeOwedPrefix}%'",
          ),
          0,
        );
        expect(
          settingIn(copy, SettingsKeys.lastLocationStack),
          NavDestination.encodeStack(const []),
        );
        for (final MapEntry(:key, :value) in binding.entries) {
          expect(settingIn(copy, key), value, reason: key);
        }
        for (final table in ['user_settings', 'sync_metadata']) {
          expect(
            count(
              copy,
              "SELECT count(*) FROM $table WHERE value LIKE '%Ana Partner%' "
              "OR value LIKE '%Their%'",
            ),
            0,
            reason: table,
          );
        }
      } finally {
        copy.close();
      }
      expect(
        await db.userSettingsDao.getValue(SettingsKeys.pairingPartnerName),
        'Ana Partner',
        reason: 'the live database is untouched',
      );
    });

    // A database that paired before the mark of a partner's rows existed:
    // its pairing rows are what tells the copy it may hold their words.
    group('a database that paired before this build (B1)', () {
      tearDown(SettingsService.reset);

      test('keeps a pairing row through every pairing write: an unpair, the '
          'partner\'s end, another account signing in', () async {
        final db = await AppDatabase.getInstance();
        final settings = SettingsService.forTesting(db);
        Future<int> pairingRows() async =>
            (await db
                    .customSelect(
                      'SELECT count(*) AS n FROM user_settings '
                      "WHERE key LIKE 'pairing\\_%' ESCAPE '\\'",
                    )
                    .getSingle())
                .read<int>('n');

        await settings.setPairingSettings(
          const PairingSettings(
            pairId: 'pair-1',
            accountUid: 'me',
            partnerUid: 'partner-uid',
            partnerName: 'Ana',
          ),
        );
        for (final (step, next) in [
          ('unpaired', PairingSettings.empty),
          (
            'ended by the partner',
            const PairingSettings(
              endedNoticePending: true,
              endedPairId: 'pair-1',
            ),
          ),
          ('another account', const PairingSettings(accountUid: 'other')),
        ]) {
          await settings.setPairingSettings(next);
          expect(await pairingRows(), greaterThan(0), reason: step);
        }
      });

      test('a copy of it is rebuilt clean: no trigram of a partner\'s removed '
          'note in its index segments', () async {
        const partner = 'partner-uid';
        final db = await AppDatabase.getInstance();
        final name = manager.getActiveDatabaseName();
        await indexedPartnerNote(db, partner);
        // No mark: the build that held the note wrote none.
        await db.syncDao.deleteValue(SyncDao.keySharedEverHeld);
        await db.sharedRowDao.removeAll();
        await db.syncDao.deleteValue(SyncDao.keySharedEverHeld);
        await setting(db, SettingsKeys.pairingEndedNotice, 'false');

        final snapshot = await manager.snapshotForShare(name);

        final copy = sqlite3.open(snapshot, mode: OpenMode.readOnly);
        try {
          expect(segmentsHold(copy, 'diagnosis'), isFalse);
        } finally {
          copy.close();
        }
      });

      test('with no pairing row either, the end of the pair marks it: a copy '
          'made after is still rebuilt clean (C3)', () async {
        const partner = 'partner-uid';
        final db = await AppDatabase.getInstance();
        final name = manager.getActiveDatabaseName();
        await indexedPartnerNote(db, partner);
        // The owner as the build before the mark left it: no mark at all.
        await db.syncDao.deleteValue(SyncDao.keySharedEverHeld);

        await db.sharedRowDao.removeAll();

        expect(await db.syncDao.getValue(SyncDao.keySharedEverHeld), '1');
        final snapshot = await manager.snapshotForShare(name);
        final copy = sqlite3.open(snapshot, mode: OpenMode.readOnly);
        try {
          expect(segmentsHold(copy, 'diagnosis'), isFalse);
        } finally {
          copy.close();
        }
      });
    });

    group('what of mine hangs on a partner\'s row (A5)', () {
      const partner = 'partner-uid';
      final at = DateTime.utc(2026, 6, 1);
      final stamp = at.millisecondsSinceEpoch ~/ 1000;

      /// An alert, a presence mark and a registration of mine on [eventId],
      /// as the alerts and presence services store them.
      Future<void> hangOn(AppDatabase db, String eventId) async {
        await db.customStatement(
          'INSERT INTO calendar_event_alerts (id, event_id, created_at, '
          'updated_at, hlc_timestamp, device_id) VALUES (?, ?, ?, ?, ?, ?)',
          ['alert-$eventId', eventId, stamp, stamp, '1', 'me'],
        );
        await db.customStatement(
          'INSERT INTO calendar_event_absences (event_id, day, created_at, '
          'updated_at, hlc_timestamp, device_id) VALUES (?, ?, ?, ?, ?, ?)',
          [eventId, stamp, stamp, stamp, '1', 'me'],
        );
        await db.customStatement(
          'INSERT INTO alert_registrations (os_id, alert_id, event_id, day, '
          'fire_at, backend, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [
            eventId.hashCode & 0x7fffffff,
            'alert-$eventId',
            eventId,
            at.millisecondsSinceEpoch,
            at.millisecondsSinceEpoch,
            'alarm',
            stamp,
            stamp,
          ],
        );
      }

      Future<void> event(AppDatabase db, String id) =>
          db.calendarEventDao.upsert(
            CalendarEventsCompanion.insert(
              id: id,
              title: 'Event $id',
              category: 'general',
              startDate: at,
              ruleKind: 'weekly',
              createdAt: at,
              updatedAt: at,
            ),
          );

      for (final ended in [false, true]) {
        test(
          ended
              ? 'after the pair ended, nothing of mine on their former rows '
                    'leaves in a copy; mine on my own rows does'
              : 'goes from the copy with the partner\'s rows, and stays here; '
                    'mine on my own rows stays in both',
          () async {
            final db = await AppDatabase.getInstance();
            final name = manager.getActiveDatabaseName();
            await event(db, 'their-event');
            await event(db, 'my-event');
            final folder = await db.folderDao.createFolder(name: 'Folder');
            final theirNote = await db.noteDao.createNote(
              folderId: folder.id,
              title: 'Theirs',
              content: 'x',
            );
            final myNote = await db.noteDao.createNote(
              folderId: folder.id,
              title: 'Mine',
              content: 'y',
            );
            for (final eventId in ['their-event', 'my-event']) {
              await hangOn(db, eventId);
            }
            for (final note in [theirNote, myNote]) {
              await db.customStatement(
                'INSERT INTO counter_values (counter_id, note_id, value) '
                'VALUES (?, ?, 3)',
                ['c1', note.id],
              );
              await setting(
                db,
                '${SettingsKeys.notePositionPrefix}${note.id}',
                '{}',
              );
              await setting(
                db,
                '${SettingsKeys.moneyNoteCurrencyPrefix}${note.id}',
                'EUR',
              );
            }
            await db.syncDao.setValue(SyncDao.keyShareSending, '1');
            for (final (table, id) in [
              ('calendar_events', 'their-event'),
              ('notes', theirNote.id),
            ]) {
              await db.customStatement(
                'UPDATE $table SET owner_id = ? WHERE id = ?',
                [partner, id],
              );
            }
            await db.syncDao.setValue(SyncDao.keySharedOwner, partner);
            await db.syncDao.setValue(SyncDao.keySharedEverHeld, '1');
            if (ended) await db.sharedRowDao.removeAll();
            addTearDown(() async {
              await db.sharedRowDao.removeAll();
            });

            final snapshot = await manager.snapshotForShare(name);

            final copy = sqlite3.open(snapshot, mode: OpenMode.readOnly);
            try {
              for (final table in [
                'calendar_event_alerts',
                'calendar_event_absences',
                'alert_registrations',
              ]) {
                expect(
                  count(
                    copy,
                    "SELECT count(*) FROM $table WHERE event_id = 'their-event'",
                  ),
                  0,
                  reason: table,
                );
                expect(
                  count(
                    copy,
                    "SELECT count(*) FROM $table WHERE event_id = 'my-event'",
                  ),
                  1,
                  reason: '$table of mine',
                );
              }
              for (final (note, kept) in [(theirNote, 0), (myNote, 1)]) {
                expect(
                  count(
                    copy,
                    'SELECT count(*) FROM counter_values '
                    "WHERE note_id = '${note.id}'",
                  ),
                  kept,
                );
                for (final prefix in [
                  SettingsKeys.notePositionPrefix,
                  SettingsKeys.moneyNoteCurrencyPrefix,
                ]) {
                  expect(
                    settingIn(copy, '$prefix${note.id}'),
                    kept == 0 ? isNull : isNotNull,
                    reason: prefix,
                  );
                }
              }
              expect(
                count(
                  copy,
                  'SELECT count(*) FROM sync_metadata WHERE key = '
                  "'${SyncDao.keyShareSending}'",
                ),
                0,
              );
            } finally {
              copy.close();
            }
            expect(
              (await db
                      .customSelect(
                        'SELECT count(*) AS n FROM calendar_event_alerts '
                        "WHERE event_id = 'their-event'",
                      )
                      .getSingle())
                  .read<int>('n'),
              1,
              reason: 'the live database keeps them, for a re-share',
            );
          },
        );
      }
    });

    test('a never-paired database whose index is in step with a note of '
        'mine I deleted leaves it in no search row of the copy, nor in a '
        'segment: the copy is rebuilt (B6)', () async {
      final db = await AppDatabase.getInstance();
      final name = manager.getActiveDatabaseName();
      final folder = await db.folderDao.createFolder(name: 'Plain');
      final kept = await db.noteDao.createNote(
        folderId: folder.id,
        title: 'Kept',
        content: 'still here',
      );
      final gone = await db.noteDao.createNote(
        folderId: folder.id,
        title: 'Gone',
        content: 'the diagnosis',
      );
      await indexAll(db);
      // Deleted after the drain, shared before the next one.
      await db.noteDao.softDeleteNoteWithChunks(gone.id);

      final snapshot = await manager.snapshotForShare(name);

      final copy = sqlite3.open(snapshot, mode: OpenMode.readOnly);
      try {
        expect(ledgerOf(copy, gone.id), 0);
        expect(hitsIn(copy, 'diagnosis'), 0);
        expect(segmentsHold(copy, 'diagnosis'), isFalse);
        expect(ledgerOf(copy, kept.id), 1);
      } finally {
        copy.close();
      }
    });

    test('a database with no shared owner, its index in step, is copied '
        'exactly as before: no write reaches the copy', () async {
      final db = await AppDatabase.getInstance();
      final name = manager.getActiveDatabaseName();
      final folder = await db.folderDao.createFolder(name: 'Plain');
      await db.noteDao.createNote(
        folderId: folder.id,
        title: 'Indexed',
        content: 'in step',
      );
      await indexAll(db);
      final source = await manager.getDatabasePath(name);

      final snapshot = await manager.snapshotForShare(name);

      final plain = p.join(p.dirname(snapshot), 'plain.db');
      final connection = sqlite3.open(source, mode: OpenMode.readWrite);
      try {
        connection.execute('VACUUM INTO ?', [plain]);
      } finally {
        connection.close();
      }
      expect(File(snapshot).readAsBytesSync(), File(plain).readAsBytesSync());
    });

    /// Whether the share snapshot of [name] is byte for byte what a plain
    /// `VACUUM INTO` of it gives: no write reached the copy.
    Future<bool> copiedAsIs(String name) async {
      final source = await manager.getDatabasePath(name);
      final snapshot = await manager.snapshotForShare(name);
      final plain = p.join(p.dirname(snapshot), 'plain.db');
      final connection = sqlite3.open(source, mode: OpenMode.readWrite);
      try {
        connection.execute('VACUUM INTO ?', [plain]);
      } finally {
        connection.close();
      }
      final a = File(snapshot).readAsBytesSync();
      final b = File(plain).readAsBytesSync();
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }

    final at = DateTime.utc(2026, 6, 1);
    final stamp = at.millisecondsSinceEpoch ~/ 1000;

    Future<void> registration(
      AppDatabase db,
      int osId,
      String eventId, {
      String source = 'event',
    }) => db.customStatement(
      'INSERT INTO alert_registrations (os_id, alert_id, event_id, day, '
      'fire_at, backend, created_at, updated_at, source) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        osId,
        'alert-$osId',
        eventId,
        at.millisecondsSinceEpoch,
        at.millisecondsSinceEpoch,
        'alarm',
        stamp,
        stamp,
        source,
      ],
    );

    Future<void> alertOn(AppDatabase db, String id, String eventId) =>
        db.customStatement(
          'INSERT INTO calendar_event_alerts (id, event_id, created_at, '
          'updated_at, hlc_timestamp, device_id) VALUES (?, ?, ?, ?, ?, ?)',
          [id, eventId, stamp, stamp, '1', 'me'],
        );

    /// A database of mine that never paired, its index in step.
    Future<AppDatabase> neverPaired() async {
      final db = await AppDatabase.getInstance();
      final folder = await db.folderDao.createFolder(name: 'Plain');
      await db.noteDao.createNote(
        folderId: folder.id,
        title: 'Indexed',
        content: 'in step',
      );
      await indexAll(db);
      return db;
    }

    group('a never-paired database\'s own orphans travel as they are, '
        'byte for byte (C2)', () {
      test('a test alarm\'s registration', () async {
        final db = await neverPaired();
        await registration(db, 1, AlertPayload.testEventId);

        expect(await copiedAsIs(manager.getActiveDatabaseName()), isTrue);
      });

      test('an alert whose event is not held', () async {
        final db = await neverPaired();
        await alertOn(db, 'early', 'not-yet-pulled');

        expect(await copiedAsIs(manager.getActiveDatabaseName()), isTrue);
      });

      test('a currency of a note id an import could not map', () async {
        final db = await neverPaired();
        await setting(
          db,
          '${SettingsKeys.moneyNoteCurrencyPrefix}unknown-id',
          'EUR',
        );

        expect(await copiedAsIs(manager.getActiveDatabaseName()), isTrue);
      });

      test('a location stack naming a folder not held', () async {
        final db = await neverPaired();
        await setting(
          db,
          SettingsKeys.lastLocationStack,
          NavDestination.encodeStack([
            NavDestination.folder(folderId: 'gone', title: 'Gone'),
          ]),
        );

        expect(await copiedAsIs(manager.getActiveDatabaseName()), isTrue);
      });
    });

    test('where a partner was held, a test alarm\'s registration survives the '
        'strip (C2)', () async {
      final db = await AppDatabase.getInstance();
      final name = manager.getActiveDatabaseName();
      await registration(db, 1, AlertPayload.testEventId);
      await db.syncDao.setValue(SyncDao.keySharedEverHeld, '1');

      final snapshot = await manager.snapshotForShare(name);

      final copy = sqlite3.open(snapshot, mode: OpenMode.readOnly);
      try {
        expect(
          count(
            copy,
            'SELECT count(*) FROM alert_registrations WHERE event_id = '
            "'${AlertPayload.testEventId}'",
          ),
          1,
        );
      } finally {
        copy.close();
      }
    });

    // Everything of mine on my own rows, live or deleted, stays in the copy
    // whichever way it is made (review C7).
    group('every row of mine on my own rows stays in the copy (C7)', () {
      const tables = [
        'calendar_event_alerts',
        'calendar_event_absences',
        'calendar_event_occurrences',
        'calendar_event_skips',
        'alert_registrations',
        'counter_values',
      ];
      const perNote =
          'SELECT count(*) AS n FROM user_settings WHERE key LIKE '
          "'note\\_position\\_%' ESCAPE '\\' OR key LIKE "
          "'money\\_note\\_currency\\_%' ESCAPE '\\'";

      Future<Map<String, int>> live(AppDatabase db) async => {
        for (final table in tables)
          table:
              (await db
                      .customSelect('SELECT count(*) AS n FROM $table')
                      .getSingle())
                  .read<int>('n'),
        'per-note settings': (await db.customSelect(perNote).getSingle())
            .read<int>('n'),
      };

      Map<String, int> inCopy(Database copy) => {
        for (final table in tables)
          table: count(copy, 'SELECT count(*) FROM $table'),
        'per-note settings': count(copy, perNote),
      };

      /// A live event and a cascade-deleted one of mine, each with an alert,
      /// a presence mark, a day text, a skipped day and a registration; a
      /// digest's and a category's registration; a global counter value;
      /// counter values and per-note settings on a live and a deleted note.
      Future<void> mine(AppDatabase db) async {
        var os = 10;
        for (final id in ['live-event', 'gone-event']) {
          await db.calendarEventDao.upsert(
            CalendarEventsCompanion.insert(
              id: id,
              title: 'Event $id',
              category: 'general',
              startDate: at,
              ruleKind: 'weekly',
              createdAt: at,
              updatedAt: at,
            ),
          );
          await alertOn(db, 'alert-$id', id);
          await db.eventAbsenceDao.setStatus(id, at, PresenceStatus.present);
          await db.eventOccurrenceDao.upsert(
            EventOccurrenceDescriptionsCompanion.insert(
              eventId: id,
              day: at,
              description: 'Day text',
              createdAt: at,
              updatedAt: at,
            ),
          );
          await db.eventSkipDao.markSkipped(
            id,
            at.add(const Duration(days: 7)),
          );
          await registration(db, os++, id);
        }
        await db.calendarEventDao.tombstoneEventCascade('gone-event');
        await registration(db, os++, 'digest-1', source: 'digest');
        await registration(db, os++, 'live-event', source: 'category');
        await db.counterDao.insertCounter(
          CountersCompanion.insert(id: 'c1', name: 'Sets', createdAt: at),
        );
        await db.counterDao.upsertValue('c1', '', 5);
        final folder = await db.folderDao.createFolder(name: 'Mine');
        for (final title in ['Live', 'Deleted']) {
          final note = await db.noteDao.createNote(
            folderId: folder.id,
            title: title,
            content: title,
          );
          await db.counterDao.upsertValue('c1', note.id, 3);
          await setting(
            db,
            '${SettingsKeys.notePositionPrefix}${note.id}',
            '{}',
          );
          await setting(
            db,
            '${SettingsKeys.moneyNoteCurrencyPrefix}${note.id}',
            'EUR',
          );
          if (title == 'Deleted') {
            await db.noteDao.softDeleteNoteWithChunks(note.id);
          }
        }
        await indexAll(db);
      }

      test('never paired: the copy is byte for byte', () async {
        final db = await AppDatabase.getInstance();
        await mine(db);

        expect(await copiedAsIs(manager.getActiveDatabaseName()), isTrue);
      });

      test('paired, through the strip: the same counts', () async {
        final db = await AppDatabase.getInstance();
        final name = manager.getActiveDatabaseName();
        await mine(db);
        await db.syncDao.setValue(SyncDao.keySharedEverHeld, '1');
        final before = await live(db);

        final snapshot = await manager.snapshotForShare(name);

        final copy = sqlite3.open(snapshot, mode: OpenMode.readOnly);
        try {
          expect(inCopy(copy), before);
          expect(
            count(
              copy,
              'SELECT count(*) FROM sync_metadata WHERE key = '
              "'${SyncDao.keySharedEverHeld}'",
            ),
            0,
            reason: 'the strip ran',
          );
        } finally {
          copy.close();
        }
      });
    });

    test('a copy of the open database that fails takes its folder with it and '
        'leaves the live database as it was', () async {
      final db = await AppDatabase.getInstance();
      final name = manager.getActiveDatabaseName();
      await db.folderDao.createFolder(name: 'Kept');
      // A full disk: part of the copy written, then SQLITE_FULL.
      DatabaseManager.debugSnapshotCopy = (source, snapshot) {
        File(snapshot).writeAsBytesSync([1, 2, 3]);
        throw SqliteException(
          extendedResultCode: 13,
          message: 'database or disk is full',
        );
      };
      addTearDown(() => DatabaseManager.debugSnapshotCopy = null);

      await expectLater(
        manager.snapshotForShare(name),
        throwsA(isA<SqliteException>()),
      );

      expect(snapshotFolders(), isEmpty);
      expect(identical(await AppDatabase.getInstance(), db), isTrue);
      final kept = await db.folderDao.getAllFolders(includeDeleted: false);
      expect([for (final folder in kept) folder.name], contains('Kept'));
      await db.folderDao.createFolder(name: 'After');
    });

    test('a missing database fails the copy and is never created', () async {
      final path = await manager.getDatabasePath('ghost');

      await expectLater(manager.snapshotForShare('ghost'), throwsA(anything));

      expect(File(path).existsSync(), isFalse);
      expect(snapshotFolders(), isEmpty);
    });

    test('a reader holding the WAL does not stop the copy', () async {
      final db = await AppDatabase.getInstance();
      final name = manager.getActiveDatabaseName();
      final path = await manager.getDatabasePath(name);
      await db.folderDao.createFolder(name: 'In the WAL');
      final reader = sqlite3.open(path, mode: OpenMode.readWrite);
      addTearDown(reader.close);
      reader.execute('BEGIN');
      reader.select('SELECT count(*) FROM folders');

      final snapshot = await manager.snapshotForShare(name);
      reader.execute('COMMIT');

      final copy = sqlite3.open(snapshot, mode: OpenMode.readOnly);
      try {
        expect(
          count(copy, "SELECT count(*) FROM folders WHERE name = 'In the WAL'"),
          1,
        );
      } finally {
        copy.close();
      }
    });

    test('a database that is not open is copied, sidecar included, and '
        'stays closed', () async {
      await leaveInSidecar('work');

      final snapshot = await manager.snapshotForShare('work');

      expect(p.basename(snapshot), 'work.db');
      final copy = sqlite3.open(snapshot, mode: OpenMode.readOnly);
      try {
        expect(count(copy, 'SELECT count(*) FROM items'), 300);
      } finally {
        copy.close();
      }
      expect(AppDatabase.openInstanceOf('work'), isNull);
    });

    test('the next snapshot deletes the earlier ones and nothing else in the '
        'temp directory', () async {
      await leaveInSidecar('work');
      final earlier = Directory(
        p.join(tempDir.path, '${DatabaseManager.shareSnapshotPrefix}1'),
      )..createSync();
      File(p.join(earlier.path, 'work.db')).writeAsStringSync('old');
      final foreign = Directory(p.join(tempDir.path, 'another_app'))
        ..createSync();
      addTearDown(() => foreign.deleteSync(recursive: true));

      final snapshot = await manager.snapshotForShare('work');

      expect(earlier.existsSync(), isFalse);
      expect(foreign.existsSync(), isTrue);
      expect(snapshotFolders(), {p.basename(p.dirname(snapshot))});
    });

    // `SQLITE_FULL` cannot be staged here; a file SQLite refuses to read
    // fails the same statement on the same path.
    test('a copy that fails takes its folder with it', () async {
      final path = await manager.getDatabasePath('broken');
      await Directory(p.dirname(path)).create(recursive: true);
      await File(path).writeAsBytes([
        ...'SQLite format 3\u0000'.codeUnits,
        ...List.filled(84, 0),
      ]);

      await expectLater(manager.snapshotForShare('broken'), throwsA(anything));

      expect(snapshotFolders(), isEmpty);
    });
  });

  group('the memoized open', () {
    late SharedPreferencesStorePlatform previous;

    setUp(() {
      previous = SharedPreferencesStorePlatform.instance;
      DatabaseManager.resetForTesting();
    });

    tearDown(() {
      SharedPreferencesStorePlatform.instance = previous;
      SharedPreferences.resetStatic();
      DatabaseManager.resetForTesting();
    });

    test('two first callers share one manager, built before either reads '
        'it (final review X-11)', () async {
      final arrived = Completer<void>();
      final release = Completer<void>();
      ScriptedPrefsStore.install({'active_database': 'phone'}).onRead = (_) {
        if (!arrived.isCompleted) arrived.complete();
        return release.future;
      };
      final managers = <DatabaseManager>[];
      Future<String> readActiveName() async {
        final manager = await DatabaseManager.getInstance();
        managers.add(manager);
        return manager.getActiveDatabaseName();
      }

      final names = [readActiveName(), readActiveName()];
      await arrived.future;
      release.complete();

      expect(await Future.wait(names), ['phone', 'phone']);
      expect(identical(managers[0], managers[1]), isTrue);
    });

    test('an open that fails is not kept: the next call opens anew '
        '(final review X-7)', () async {
      final store = ScriptedPrefsStore.install()
        ..onRead = (read) {
          if (read == 1) throw StateError('the store is not ready');
        };

      await expectLater(DatabaseManager.getInstance(), throwsStateError);
      final retried = await DatabaseManager.getInstance();

      expect(retried.getActiveDatabaseName(), 'gym_notes');
      expect(identical(await DatabaseManager.getInstance(), retried), isTrue);
      expect(store.reads, 2);
    });
  });
}
