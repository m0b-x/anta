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

  factory NotePositionData.fromJson(Map<String, dynamic> json) {
    return NotePositionData(
      isPreviewMode: json['isPreviewMode'] as bool? ?? false,
      previewScrollProgress:
          (json['previewScrollOffset'] as num?)?.toDouble() ?? 0.0,
      editorLineIndex: json['editorLineIndex'] as int? ?? 0,
      editorColumnOffset: json['editorColumnOffset'] as int? ?? 0,
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

  NotePositionService._();

  static Future<NotePositionService> getInstance() async {
    if (_instance == null) {
      _instance = NotePositionService._();
      _instance!._db = await AppDatabase.getInstance();
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
