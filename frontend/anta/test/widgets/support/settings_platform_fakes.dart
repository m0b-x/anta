import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart' show XFile;
import 'package:sqlite3/sqlite3.dart' show Database, sqlite3;

import 'package:anta/database/migrations/database_schema.dart';

/// The system file picker as the destructive settings paths meet it: it
/// hands back the path a test chose, or nothing — the user backing out.
///
/// Installed over [FilePickerPlatform.instance], the seam the plugin's own
/// static `FilePicker.pickFile` reads, so the pages run unchanged.
class FakeFilePicker extends FilePickerPlatform {
  /// What the next pick returns; `null` is a cancelled picker.
  String? nextPath;

  int picks = 0;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    picks++;
    final path = nextPath;
    return path == null ? null : _PickedFile(path);
  }

  /// Puts this picker in place for the current test and the plugin's own
  /// back afterwards.
  void install() {
    final previous = FilePickerPlatform.instance;
    FilePickerPlatform.instance = this;
    addTearDown(() => FilePickerPlatform.instance = previous);
  }
}

final class _PickedFile extends PlatformFile {
  _PickedFile(this._path);

  final String _path;

  @override
  String get name => p.basename(_path);

  @override
  Uri get uri => Uri.file(_path);

  @override
  XFile get xFile => XFile(_path);

  @override
  Future<int> length() => File(_path).length();

  @override
  Future<Uint8List> readAsBytes() => File(_path).readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() =>
      File(_path).openRead().map(Uint8List.fromList);
}

/// Answers every call on [channel] with [answer] for the current test and
/// returns the list the calls are written into.
///
/// `SystemNavigator.pop` and the share sheet are the two ends of the
/// destructive paths that leave the app; a test proves they were reached by
/// reading the call, since neither has an effect a widget test could see.
List<MethodCall> recordMethodCalls(MethodChannel channel, {Object? answer}) {
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    calls.add(call);
    return answer;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return calls;
}

/// Writes a file that passes `DatabaseManager.isSqliteFile` — the 16-byte
/// SQLite magic header and some padding — at [path]. Enough for the share
/// and for an import under a fake verifier, which never open it; the real
/// verifier refuses it (its page size is 0).
Future<File> writeSqliteHeaderFile(String path) async {
  final bytes = BytesBuilder()
    ..add('SQLite format 3\u0000'.codeUnits)
    ..add(Uint8List(84));
  final file = File(path);
  await file.parent.create(recursive: true);
  return file.writeAsBytes(bytes.takeBytes());
}

/// What [writeSqliteFile] puts in the database.
enum SqliteFileShape {
  /// ANTA's three core tables with their columns as the current schema has
  /// them.
  anta,

  /// Tables named `notes`, `folders` and `content_chunks` whose columns are
  /// another app's.
  antaNamesOnly,

  /// One table of another app's.
  foreign,
}

/// Writes a real SQLite database at [path] that the import's real verifier
/// opens: tables of [shape], [notes] rows in `notes`, and [userVersion]. A
/// rollback-journal file, as a share is since S18; with [inSidecar] it is
/// WAL-flagged and every table and row sits in a `-wal` beside it, as a copy
/// of a live database leaves them.
Future<File> writeSqliteFile(
  String path, {
  SqliteFileShape shape = SqliteFileShape.anta,
  int notes = 0,
  int userVersion = DatabaseSchema.currentVersion,
  bool inSidecar = false,
}) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  final writerPath = inSidecar ? '$path.writer' : path;
  final db = sqlite3.open(writerPath);
  try {
    if (inSidecar) {
      // A main file of its own first: SQLite discards a `-wal` beside an
      // empty one, and a live database's main file is never empty.
      db.execute('CREATE TABLE meta (key TEXT)');
      db.execute('PRAGMA journal_mode = WAL');
      db.execute('PRAGMA wal_autocheckpoint = 0');
    }
    _writeTables(db, shape: shape, notes: notes, userVersion: userVersion);
    if (inSidecar) {
      File(writerPath).copySync(path);
      File('$writerPath-wal').copySync('$path-wal');
    }
  } finally {
    db.close();
    if (inSidecar) {
      for (final suffix in ['', '-wal', '-shm']) {
        final leftover = File('$writerPath$suffix');
        if (leftover.existsSync()) leftover.deleteSync();
      }
    }
  }
  return file;
}

/// The columns every synced core table carries (`lib/database/tables/`).
const _crdtColumns =
    "hlc_timestamp TEXT NOT NULL DEFAULT '', device_id TEXT NOT NULL "
    "DEFAULT '', version INTEGER NOT NULL DEFAULT 1, is_deleted INTEGER NOT "
    'NULL DEFAULT 0, deleted_at INTEGER, owner_id TEXT';

void _writeTables(
  Database db, {
  required SqliteFileShape shape,
  required int notes,
  required int userVersion,
}) {
  switch (shape) {
    case SqliteFileShape.anta:
      db.execute(
        'CREATE TABLE folders (id TEXT PRIMARY KEY, name TEXT NOT NULL, '
        'parent_id TEXT, position INTEGER NOT NULL DEFAULT 0, label INTEGER '
        'NOT NULL DEFAULT 0, created_at INTEGER NOT NULL DEFAULT 0, '
        'updated_at INTEGER NOT NULL DEFAULT 0, note_sort_order TEXT, '
        'subfolder_sort_order TEXT, $_crdtColumns)',
      );
      db.execute(
        'CREATE TABLE notes (id TEXT PRIMARY KEY, folder_id TEXT NOT NULL, '
        "title TEXT NOT NULL, preview TEXT NOT NULL DEFAULT '', "
        'content_length INTEGER NOT NULL DEFAULT 0, chunk_count INTEGER NOT '
        'NULL DEFAULT 0, is_compressed INTEGER NOT NULL DEFAULT 0, position '
        'INTEGER NOT NULL DEFAULT 0, label INTEGER NOT NULL DEFAULT 0, '
        'created_at INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL '
        'DEFAULT 0, $_crdtColumns)',
      );
      db.execute(
        'CREATE TABLE content_chunks (id TEXT PRIMARY KEY, note_id TEXT NOT '
        'NULL, chunk_index INTEGER NOT NULL, content TEXT NOT NULL, '
        'is_compressed INTEGER NOT NULL DEFAULT 0, content_hash TEXT, '
        '$_crdtColumns)',
      );
      if (notes > 0) {
        db.execute(
          'WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM n '
          'WHERE x < $notes) '
          "INSERT INTO notes (id, folder_id, title) SELECT 'note-' || x, "
          "'root', hex(randomblob(100)) FROM n",
        );
      }
    case SqliteFileShape.antaNamesOnly:
      db.execute('CREATE TABLE folders (key INTEGER PRIMARY KEY, label TEXT)');
      db.execute('CREATE TABLE notes (key INTEGER PRIMARY KEY, body TEXT)');
      db.execute(
        'CREATE TABLE content_chunks (key INTEGER PRIMARY KEY, blob BLOB)',
      );
    case SqliteFileShape.foreign:
      db.execute('CREATE TABLE recipes (id INTEGER PRIMARY KEY, name TEXT)');
  }
  db.execute('PRAGMA user_version = $userVersion');
}
