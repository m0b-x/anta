import 'dart:convert';

import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../constants/settings_keys.dart';

class NotePositionData {
  final bool isPreviewMode;

  /// Preview scroll position as a 0.0–1.0 progress ratio.
  final double previewScrollProgress;
  final int editorLineIndex;
  final int editorColumnOffset;

  const NotePositionData({
    required this.isPreviewMode,
    required this.previewScrollProgress,
    required this.editorLineIndex,
    required this.editorColumnOffset,
  });

  Map<String, dynamic> toJson() => {
    'isPreviewMode': isPreviewMode,
    // JSON key kept for backwards-compatible deserialization.
    'previewScrollOffset': previewScrollProgress,
    'editorLineIndex': editorLineIndex,
    'editorColumnOffset': editorColumnOffset,
  };

  /// Reads a stored position, falling back **per field**: a value of the
  /// wrong type is replaced by that field's default and the rest of the
  /// record survives. A malformed `isPreviewMode` must never cost the
  /// user their caret line.
  factory NotePositionData.fromJson(Map<String, dynamic> json) {
    final isPreviewMode = json['isPreviewMode'];
    final progress = json['previewScrollOffset'];
    final lineIndex = json['editorLineIndex'];
    final columnOffset = json['editorColumnOffset'];
    return NotePositionData(
      isPreviewMode: isPreviewMode is bool ? isPreviewMode : false,
      previewScrollProgress: progress is num ? progress.toDouble() : 0.0,
      editorLineIndex: lineIndex is num ? lineIndex.toInt() : 0,
      editorColumnOffset: columnOffset is num ? columnOffset.toInt() : 0,
    );
  }

  static const NotePositionData defaultPosition = NotePositionData(
    isPreviewMode: false,
    previewScrollProgress: 0.0,
    editorLineIndex: 0,
    editorColumnOffset: 0,
  );
}

class NotePositionService {
  static NotePositionService? _instance;
  late AppDatabase _db;

  /// The open in flight, shared by every caller that arrives before it
  /// finishes.
  static Future<NotePositionService>? _opening;

  NotePositionService._();

  /// Published only once its database is set, the `SettingsService` shape:
  /// stored before the await, a second caller in that window — the editor's
  /// restore and its save on the way out — got a service whose `_db` was not
  /// yet initialized.
  static Future<NotePositionService> getInstance() {
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
  /// closing database is never published.
  static Future<NotePositionService> _open() async {
    for (var attempt = 0; attempt < _openAttempts; attempt++) {
      final generation = DatabaseLifecycle.generation;
      final db = await AppDatabase.getInstance();
      final raced = _instance;
      if (raced != null) return raced;
      if (DatabaseLifecycle.generation != generation) continue;
      final service = NotePositionService._().._db = db;
      _instance = service;
      DatabaseLifecycle.registerResetHandler(reset);
      return service;
    }
    throw StateError('the database switched while note positions were opened');
  }

  /// Drops the cached singleton so the next [getInstance] rebinds to the
  /// currently-active [AppDatabase]. Invoked by [DatabaseLifecycle] when the
  /// active database changes.
  static void reset() {
    _instance = null;
    _opening = null;
  }

  String _getPositionKey(String noteId) =>
      '${SettingsKeys.notePositionPrefix}$noteId';

  Future<NotePositionData> getPosition(String noteId) async {
    final value = await _db.userSettingsDao.getValue(_getPositionKey(noteId));
    if (value == null) return NotePositionData.defaultPosition;

    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      return NotePositionData.fromJson(json);
    } catch (_) {
      return NotePositionData.defaultPosition;
    }
  }

  Future<void> savePosition(String noteId, NotePositionData position) async {
    final jsonString = jsonEncode(position.toJson());
    await _db.userSettingsDao.setValue(_getPositionKey(noteId), jsonString);
  }

  Future<void> deletePosition(String noteId) async {
    await _db.userSettingsDao.deleteValue(_getPositionKey(noteId));
  }

  Future<void> cleanupOrphanedPositions(Set<String> validNoteIds) async {
    final allSettings = await _db.userSettingsDao.getAllSettings();
    final prefix = SettingsKeys.notePositionPrefix;

    for (final key in allSettings.keys) {
      if (key.startsWith(prefix)) {
        final noteId = key.substring(prefix.length);
        if (!validNoteIds.contains(noteId)) {
          await _db.userSettingsDao.deleteValue(key);
        }
      }
    }
  }
}
