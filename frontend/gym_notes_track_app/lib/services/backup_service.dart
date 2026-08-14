import 'dart:convert';
import 'dart:io';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../constants/json_keys.dart';
import '../constants/settings_keys.dart';
import 'calendar_event_service.dart';
import 'event_occurrence_service.dart';
import 'category_service.dart';
import 'counter_service.dart';
import 'markdown_bar_service.dart';
import 'public_holiday_service.dart';

class BackupService {
  static BackupService? _instance;
  late AppDatabase _db;

  BackupService._();

  static Future<BackupService> getInstance() async {
    if (_instance == null) {
      _instance = BackupService._();
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

  Future<Map<String, dynamic>> exportAllData() async {
    final folders = await _db.folderDao.getAllFolders(includeDeleted: false);
    final notes = await _db.noteDao.getAllNotes(includeDeleted: false);

    final notesWithContent = <Map<String, dynamic>>[];
    for (final note in notes) {
      final content = await _db.contentChunkDao.loadContent(note.id);
      notesWithContent.add({
        JsonKeys.id: note.id,
        JsonKeys.folderId: note.folderId,
        JsonKeys.title: note.title,
        JsonKeys.content: content,
        JsonKeys.preview: note.preview,
        JsonKeys.createdAt: note.createdAt.toIso8601String(),
        JsonKeys.updatedAt: note.updatedAt.toIso8601String(),
      });
    }

    final foldersData = folders
        .map(
          (f) => {
            JsonKeys.id: f.id,
            JsonKeys.name: f.name,
            JsonKeys.parentId: f.parentId,
            'position': f.position,
            JsonKeys.createdAt: f.createdAt.toIso8601String(),
            JsonKeys.updatedAt: f.updatedAt.toIso8601String(),
            JsonKeys.noteSortOrder: f.noteSortOrder,
            JsonKeys.subfolderSortOrder: f.subfolderSortOrder,
          },
        )
        .toList();

    final shortcuts = await _db.userSettingsDao.getValue('markdown_shortcuts');
    final settings = await _exportSettings();

    // Bar profiles & per-note assignments (v2+ data)
    final barProfiles = await _db.userSettingsDao.getValue(
      'markdown_bar_profiles',
    );
    final activeBar = await _db.userSettingsDao.getValue('active_markdown_bar');
    final noteBarAssignments = await _exportNoteBarAssignments();
    final noteMoneyCurrencies = await _exportNoteMoneyCurrencies();

    final counterData = await GetIt.I<CounterService>().exportData();
    final calendarCategories = await GetIt.I<CategoryService>().exportData();
    final calendarEvents = await GetIt.I<CalendarEventService>().exportData();
    final publicHolidays = await GetIt.I<PublicHolidayService>().exportData();
    final eventOccurrences = await GetIt.I<EventOccurrenceService>()
        .exportData();

    return {
      // v7: event priorities are stored inverted (1 = highest). Older
      // backups carry the old 5-is-highest values and are flipped on import.
      'version': 7,
      'exportedAt': DateTime.now().toIso8601String(),
      'folders': foldersData,
      'notes': notesWithContent,
      'markdownShortcuts': shortcuts,
      'settings': settings,
      'barProfiles': barProfiles,
      'activeBar': activeBar,
      'noteBarAssignments': noteBarAssignments,
      'noteMoneyCurrencies': noteMoneyCurrencies,
      'counterData': counterData,
      'calendarCategories': calendarCategories,
      'calendarEvents': calendarEvents,
      'publicHolidays': publicHolidays,
      // Purely additive (v24): an absent key on an older backup is simply a
      // database with no per-occurrence overrides, which is what those
      // installs had. No version bump — 7 was needed only because an existing
      // field changed meaning.
      'eventOccurrences': eventOccurrences,
    };
  }

  /// Returns a map of noteId → profileId for every per-note bar override.
  Future<Map<String, String>> _exportNoteBarAssignments() async {
    final all = await _db.userSettingsDao.getAllSettings();
    final result = <String, String>{};
    for (final entry in all.entries) {
      if (entry.key.startsWith('note_bar_')) {
        final noteId = entry.key.substring('note_bar_'.length);
        result[noteId] = entry.value;
      }
    }
    return result;
  }

  /// Returns a map of noteId → raw currency override (`symbol|suffix`)
  /// for every per-note money currency override.
  Future<Map<String, String>> _exportNoteMoneyCurrencies() async {
    final all = await _db.userSettingsDao.getAllSettings();
    final result = <String, String>{};
    for (final entry in all.entries) {
      if (entry.key.startsWith(SettingsKeys.moneyNoteCurrencyPrefix)) {
        final noteId = entry.key.substring(
          SettingsKeys.moneyNoteCurrencyPrefix.length,
        );
        result[noteId] = entry.value;
      }
    }
    return result;
  }

  Future<Map<String, dynamic>> _exportSettings() async {
    final settingsKeys = [
      'preview_font_size',
      'editor_font_size',
      'locale',
      'theme_mode',
      'date_format',
      'folder_swipe_enabled',
      'note_swipe_enabled',
      'confirm_delete',
      'auto_save_enabled',
      'auto_save_interval',
      'show_note_preview',
      'show_stats_bar',
      'haptic_feedback',
      'show_line_numbers',
      'word_wrap',
      'show_cursor_line',
      'auto_break_long_lines',
      'preview_when_keyboard_hidden',
      'scroll_cursor_on_keyboard',
      'show_preview_scrollbar',
      'toolbar_shortcut_ratio',
      'toolbar_split_enabled',
      'toolbar_utility_config',
      'preview_lines_per_chunk',
      'money_ledger_enabled',
      'money_start_cents',
      'money_currency_symbol',
      'money_currency_suffix',
      'markdown_custom_colors',
    ];

    final settings = <String, dynamic>{};
    for (final key in settingsKeys) {
      final value = await _db.userSettingsDao.getValue(key);
      if (value != null) {
        settings[key] = value;
      }
    }
    return settings;
  }

  Future<String> exportToFile() async {
    final data = await exportAllData();
    final jsonString = const JsonEncoder.withIndent('  ').convert(data);

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final fileName = 'anta_backup_$timestamp.json';
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsString(jsonString);

    return file.path;
  }

  Future<void> shareBackup() async {
    final filePath = await exportToFile();
    await SharePlus.instance.share(ShareParams(files: [XFile(filePath)]));
  }

  Future<BackupValidationResult> validateBackup(String jsonString) async {
    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      if (!data.containsKey('folders') || !data.containsKey('notes')) {
        return BackupValidationResult(
          isValid: false,
          error: 'Invalid backup format: missing folders or notes',
        );
      }

      final folders = data['folders'] as List;
      final notes = data['notes'] as List;

      return BackupValidationResult(
        isValid: true,
        folderCount: folders.length,
        noteCount: notes.length,
        exportedAt: data['exportedAt'] as String?,
        version: data['version'] as int? ?? 1,
      );
    } catch (e) {
      return BackupValidationResult(
        isValid: false,
        error: 'Failed to parse backup: $e',
      );
    }
  }

  Future<ImportResult> importFromJson(String jsonString) async {
    try {
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      final folders = data['folders'] as List? ?? [];
      final notes = data['notes'] as List? ?? [];
      final settings = data['settings'] as Map<String, dynamic>? ?? {};
      final markdownShortcuts = data['markdownShortcuts'] as String?;

      int foldersImported = 0;
      int notesImported = 0;

      for (final folderData in folders) {
        final map = folderData as Map<String, dynamic>;
        await _db.folderDao.createFolder(
          name: map[JsonKeys.name] as String,
          parentId: map[JsonKeys.parentId] as String?,
        );
        foldersImported++;
      }

      for (final noteData in notes) {
        final map = noteData as Map<String, dynamic>;
        final content = map[JsonKeys.content] as String? ?? '';
        final preview = content.length > 200
            ? content.substring(0, 200)
            : content;

        final note = await _db.noteDao.createNote(
          folderId: map[JsonKeys.folderId] as String,
          title: map[JsonKeys.title] as String,
          preview: preview,
          contentLength: content.length,
          chunkCount: 1,
        );

        await _db.contentChunkDao.saveContent(
          noteId: note.id,
          content: content,
        );
        notesImported++;
      }

      for (final entry in settings.entries) {
        await _db.userSettingsDao.setValue(entry.key, entry.value.toString());
      }

      if (markdownShortcuts != null) {
        await _db.userSettingsDao.setValue(
          'markdown_shortcuts',
          markdownShortcuts,
        );
      }

      // Restore bar profiles & per-note assignments (v2+ backups)
      final barProfiles = data['barProfiles'] as String?;
      final activeBar = data['activeBar'] as String?;
      final noteBarAssignments =
          data['noteBarAssignments'] as Map<String, dynamic>?;

      if (barProfiles != null) {
        await _db.userSettingsDao.setValue(
          'markdown_bar_profiles',
          barProfiles,
        );
      }
      if (activeBar != null) {
        await _db.userSettingsDao.setValue('active_markdown_bar', activeBar);
      }
      if (noteBarAssignments != null) {
        for (final entry in noteBarAssignments.entries) {
          await _db.userSettingsDao.setValue(
            'note_bar_${entry.key}',
            entry.value.toString(),
          );
        }
      }

      // Per-note money currency overrides (v6+ backups; missing key
      // leaves existing overrides in place).
      final noteMoneyCurrencies =
          data['noteMoneyCurrencies'] as Map<String, dynamic>?;
      if (noteMoneyCurrencies != null) {
        for (final entry in noteMoneyCurrencies.entries) {
          await _db.userSettingsDao.setValue(
            '${SettingsKeys.moneyNoteCurrencyPrefix}${entry.key}',
            entry.value.toString(),
          );
        }
      }

      // Reset MarkdownBarService so it picks up restored data
      MarkdownBarService.reset();

      final counterData = data['counterData'] as Map<String, dynamic>?;
      if (counterData != null) {
        await GetIt.I<CounterService>().importData(counterData);
      }

      // Calendar categories, events & public holidays (v3/v4+ backups).
      // Missing keys simply leave existing data in place — older backups
      // stay valid. Categories import first so events (which reference a
      // category id) and rendering resolve against the restored set.
      final calendarCategories = data['calendarCategories'] as List?;
      if (calendarCategories != null) {
        await GetIt.I<CategoryService>().importData(calendarCategories);
      }
      final calendarEvents = data['calendarEvents'] as List?;
      if (calendarEvents != null) {
        // Backups older than v7 store priorities on the retired
        // 5-is-highest scale; flip them so the user's ranking survives.
        final backupVersion = data['version'] as int? ?? 1;
        final events = backupVersion >= 7
            ? calendarEvents
            : [
                for (final event in calendarEvents)
                  if (event is Map<String, dynamic>)
                    {
                      ...event,
                      if (event['priority'] is int &&
                          (event['priority'] as int) >= 1 &&
                          (event['priority'] as int) <= 5)
                        'priority': 6 - (event['priority'] as int),
                    }
                  else
                    event,
              ];
        await GetIt.I<CalendarEventService>().importData(events);
      }
      // Per-occurrence description overrides (v24+ backups). Unlike the keys
      // above, an absent key here is NOT a no-op when the backup carried
      // events: the event import wipes and reinserts, so keeping the previous
      // database's overrides would strand them against unrelated event ids.
      final eventOccurrences = data['eventOccurrences'] as List?;
      if (eventOccurrences != null) {
        await GetIt.I<EventOccurrenceService>().importData(eventOccurrences);
      } else if (calendarEvents != null) {
        await GetIt.I<EventOccurrenceService>().clearAllForImport();
      }
      final publicHolidays = data['publicHolidays'] as List?;
      if (publicHolidays != null) {
        await GetIt.I<PublicHolidayService>().importData(publicHolidays);
      }

      return ImportResult(
        success: true,
        foldersImported: foldersImported,
        notesImported: notesImported,
      );
    } catch (e) {
      return ImportResult(success: false, error: e.toString());
    }
  }

  Future<bool> hasExistingData() async {
    final folderCount = await _db.folderDao.getFolderCount(null);
    final noteCount = await _db.noteDao.getNoteCount(null);
    return folderCount > 0 || noteCount > 0;
  }
}

class BackupValidationResult {
  final bool isValid;
  final String? error;
  final int folderCount;
  final int noteCount;
  final String? exportedAt;
  final int version;

  const BackupValidationResult({
    required this.isValid,
    this.error,
    this.folderCount = 0,
    this.noteCount = 0,
    this.exportedAt,
    this.version = 1,
  });
}

class ImportResult {
  final bool success;
  final String? error;
  final int foldersImported;
  final int notesImported;

  const ImportResult({
    required this.success,
    this.error,
    this.foldersImported = 0,
    this.notesImported = 0,
  });
}
