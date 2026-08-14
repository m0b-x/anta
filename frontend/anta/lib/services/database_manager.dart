import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing multiple SQLite databases
class DatabaseManager {
  static DatabaseManager? _instance;
  late SharedPreferences _prefs;

  static const String _keyActiveDatabase = 'active_database';
  static const String _defaultDatabaseName = 'gym_notes';

  DatabaseManager._();

  static Future<DatabaseManager> getInstance() async {
    if (_instance == null) {
      _instance = DatabaseManager._();
      _instance!._prefs = await SharedPreferences.getInstance();
    }
    return _instance!;
  }

  /// Get the name of the currently active database
  String getActiveDatabaseName() {
    return _prefs.getString(_keyActiveDatabase) ?? _defaultDatabaseName;
  }

  /// Set the active database name
  Future<void> setActiveDatabaseName(String name) async {
    await _prefs.setString(_keyActiveDatabase, name);
  }

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

  /// Rename a database file
  Future<void> renameDatabase(String oldName, String newName) async {
    if (!await databaseExists(oldName)) {
      throw Exception('Database "$oldName" does not exist');
    }

    if (await databaseExists(newName)) {
      throw Exception('Database "$newName" already exists');
    }

    final oldPath = await getDatabasePath(oldName);
    final newPath = await getDatabasePath(newName);

    final oldFile = File(oldPath);
    await oldFile.rename(newPath);

    // Also rename related files if they exist (WAL, SHM files)
    final oldWal = File('$oldPath-wal');
    if (await oldWal.exists()) {
      await oldWal.rename('$newPath-wal');
    }

    final oldShm = File('$oldPath-shm');
    if (await oldShm.exists()) {
      await oldShm.rename('$newPath-shm');
    }

    // If the renamed database was the active one, update the active database name
    if (getActiveDatabaseName() == oldName) {
      await setActiveDatabaseName(newName);
    }
  }

  /// Delete a database file
  Future<void> deleteDatabase(String name) async {
    if (!await databaseExists(name)) {
      throw Exception('Database "$name" does not exist');
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

    // If the deleted database was the active one, switch to default
    if (getActiveDatabaseName() == name) {
      await setActiveDatabaseName(_defaultDatabaseName);
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
