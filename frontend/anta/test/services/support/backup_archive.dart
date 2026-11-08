import 'package:get_it/get_it.dart';

import 'package:anta/constants/json_keys.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/item_label.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/category_profile_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/event_digest_service.dart';
import 'package:anta/services/event_occurrence_service.dart';
import 'package:anta/services/event_presence_service.dart';
import 'package:anta/services/event_skip_service.dart';
import 'package:anta/services/event_template_service.dart';
import 'package:anta/services/filter_preset_service.dart';
import 'package:anta/services/overview_view_service.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/services/vocabulary_service.dart';

/// The JSON backup of the active database, exactly as the app wrote it until
/// S18 of `docs/scalability-roadmap.md` retired the uncalled exporter: the
/// version-8 format `BackupService.importFromJson` keeps restoring, so the
/// round-trip suites build their archives here.
Future<Map<String, dynamic>> exportBackupArchive() async {
  final db = await AppDatabase.getInstance();
  final folders = await db.folderDao.getAllFolders(includeDeleted: false);
  final notes = await db.noteDao.getAllNotes(includeDeleted: false);

  final notesWithContent = <Map<String, dynamic>>[];
  for (final note in notes) {
    final content = await db.contentChunkDao.loadContent(note.id);
    notesWithContent.add({
      JsonKeys.id: note.id,
      JsonKeys.folderId: note.folderId,
      JsonKeys.title: note.title,
      JsonKeys.content: content,
      JsonKeys.preview: note.preview,
      JsonKeys.createdAt: note.createdAt.toIso8601String(),
      JsonKeys.updatedAt: note.updatedAt.toIso8601String(),
      JsonKeys.label: ItemLabel.fromStorage(note.label).storageName,
      if (note.ownerId != null) JsonKeys.ownerId: note.ownerId,
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
          JsonKeys.label: ItemLabel.fromStorage(f.label).storageName,
          if (f.ownerId != null) JsonKeys.ownerId: f.ownerId,
        },
      )
      .toList();

  // Every settings read before any service is asked, in the exporter's
  // order, so what the archive holds never depends on a service's first
  // construction having written a setting.
  final shortcuts = await db.userSettingsDao.getValue('markdown_shortcuts');
  final settings = <String, dynamic>{};
  for (final key in _settingsKeys) {
    final value = await db.userSettingsDao.getValue(key);
    if (value != null) settings[key] = value;
  }
  // Bar profiles & per-note assignments (v2+ data).
  final barProfiles = await db.userSettingsDao.getValue(
    'markdown_bar_profiles',
  );
  final activeBar = await db.userSettingsDao.getValue('active_markdown_bar');
  final allSettings = await db.userSettingsDao.getAllSettings();
  Map<String, String> settingsUnder(String prefix) => {
    for (final entry in allSettings.entries)
      if (entry.key.startsWith(prefix))
        entry.key.substring(prefix.length): entry.value,
  };
  final noteBarAssignments = settingsUnder('note_bar_');
  final noteMoneyCurrencies = settingsUnder(
    SettingsKeys.moneyNoteCurrencyPrefix,
  );

  // The services in the order the exporter built them, which is the order
  // their singletons were first constructed in.
  final counterData = await GetIt.I<CounterService>().exportData();
  final calendarCategories = await (await CategoryService.getInstance())
      .exportData();
  final calendarEvents = await (await CalendarEventService.getInstance())
      .exportData();
  final publicHolidays = await (await PublicHolidayService.getInstance())
      .exportData();
  final eventOccurrences = await (await EventOccurrenceService.getInstance())
      .exportData();
  final eventAbsences = await (await EventPresenceService.getInstance())
      .exportData();
  final eventSkips = await (await EventSkipService.getInstance()).exportData();
  final alertService = await EventAlertService.getInstance();
  final eventAlerts = await alertService.exportData();
  final categoryAlerts = await alertService.exportCategoryAlerts();
  final categoryProfiles = await (await CategoryProfileService.getInstance())
      .exportCategoryProfiles();
  final eventTemplates = await (await EventTemplateService.getInstance())
      .exportData();
  final filterPresets = await (await FilterPresetService.getInstance())
      .exportData();
  final overviewViews = await (await OverviewViewService.getInstance())
      .exportData();
  final eventDigests = await (await EventDigestService.getInstance())
      .exportData();
  final vocabularies = await (await VocabularyService.getInstance())
      .exportData();

  return {
    // v8: category profiles ride `categoryProfiles`; an archive of 7 or older
    // imports with none, which is what those installs had, and no version is
    // refused. v7: event priorities are stored inverted (1 = highest). Older
    // backups carry the old 5-is-highest values and are flipped on import.
    'version': 8,
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
    // database with no per-occurrence overrides.
    'eventOccurrences': eventOccurrences,
    // Purely additive (v26): live marks only — tombstones and CRDT identity
    // stay out, as they do for notes and folders: a backup is not a sync
    // channel.
    'eventAbsences': eventAbsences,
    // Purely additive (v30), membership rather than rendering: an absent key
    // is a database where every occurrence still exists.
    'eventSkips': eventSkips,
    // Purely additive (v40): live rows only, and `alert_registrations` is
    // never here — it mirrors one device's OS scheduler.
    'eventAlerts': eventAlerts,
    // Purely additive (v42): keyed by category ids, so its strand rule
    // follows `calendarCategories`.
    'categoryAlerts': categoryAlerts,
    // v44, the `categoryAlerts` strand rule: one profile per category.
    'categoryProfiles': categoryProfiles,
    // Purely additive (v29).
    'eventTemplates': eventTemplates,
    // Purely additive (v35), self-contained.
    'calendarFilterPresets': filterPresets,
    // Purely additive (v41), self-contained.
    'overviewViews': overviewViews,
    // Purely additive (v42), self-contained.
    'eventDigests': eventDigests,
    // Purely additive (v32): each entry nests its own terms.
    'vocabularies': vocabularies,
  };
}

/// The settings a backup carried, each restored when present.
const _settingsKeys = [
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
  'restore_location_mode',
  'show_line_numbers',
  'word_wrap',
  'show_cursor_line',
  'auto_break_long_lines',
  'preview_when_keyboard_hidden',
  'scroll_cursor_on_keyboard',
  'show_preview_scrollbar',
  'toolbar_shortcut_ratio',
  'toolbar_split_enabled',
  'toolbar_undo_redo_pinned',
  'toolbar_utility_config',
  'preview_lines_per_chunk',
  'money_ledger_enabled',
  'money_start_cents',
  'money_currency_symbol',
  'money_currency_suffix',
  'markdown_custom_colors',
  SettingsKeys.calendarCustomColors,
  SettingsKeys.colorPickerMode,
  SettingsKeys.labelStyle,
  SettingsKeys.calendarFastingSchedule,
  SettingsKeys.calendarFastingTraditions,
  SettingsKeys.calendarFastingAppearance,
  SettingsKeys.calendarFastingOrthodoxGreatFasts,
  SettingsKeys.liveMarkdownRendering,
  SettingsKeys.previewModeEnabled,
  SettingsKeys.reportCards,
];
