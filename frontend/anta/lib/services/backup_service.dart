import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:get_it/get_it.dart';
import '../database/daos/folder_dao.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../constants/calendar_categories.dart';
import '../constants/json_keys.dart';
import '../constants/settings_keys.dart';
import '../models/item_label.dart';
import '../models/note_metadata.dart';
import 'alert_scheduler.dart';
import 'calendar_event_service.dart';
import 'category_profile_service.dart';
import 'event_occurrence_service.dart';
import 'event_presence_service.dart';
import 'event_alert_service.dart';
import 'event_digest_service.dart';
import 'event_skip_service.dart';
import 'event_template_service.dart';
import 'calendar_palette_service.dart';
import 'filter_preset_service.dart';
import 'label_appearance_service.dart';
import 'overview_view_service.dart';
import 'vocabulary_service.dart';
import 'category_service.dart';
import 'counter_service.dart';
import 'markdown_bar_service.dart';
import 'public_holiday_service.dart';
import 'sync/sync_binding_service.dart';
import 'sync/sync_suspension.dart';

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

  /// Reads and decodes the backup file at [path] in a worker isolate, for
  /// [validateBackupData] and [importFromData]: a large database's backup is
  /// megabytes of JSON, which would hold the UI isolate twice if each step
  /// decoded the text itself. Null when the text is not JSON; a file that
  /// cannot be read throws.
  static Future<Object?> readBackupFile(String path) => Isolate.run(() {
    final text = File(path).readAsStringSync();
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  });

  Future<BackupValidationResult> validateBackup(String jsonString) =>
      _validateBackup(() => jsonDecode(jsonString));

  /// [validateBackup] for a backup already decoded ([readBackupFile]).
  Future<BackupValidationResult> validateBackupData(Object? data) =>
      _validateBackup(() => data);

  Future<BackupValidationResult> _validateBackup(
    Object? Function() decode,
  ) async {
    try {
      final data = decode() as Map<String, dynamic>;

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

  /// Restores a backup suspended and unbound (D9): a restore re-creates rows
  /// under fresh stamps, so a database that kept its binding would push them
  /// as new and duplicate the other device's copies. The floor written at
  /// the end covers every stamp the import minted, so a later bind lets the
  /// space win every restored row (D15).
  ///
  /// Once the unbind has run, the queue is cleared, the floor written and the
  /// calendar told whether the restore succeeded or not: a row-level throw
  /// halfway leaves a half-restored database, and its partial rows must
  /// neither sit queued nor stand above the floor, or they would win over
  /// the space's twins at the next bind.
  Future<ImportResult> importFromJson(String jsonString) =>
      _restore(() => jsonDecode(jsonString));

  /// [importFromJson] for a backup already decoded ([readBackupFile]).
  Future<ImportResult> importFromData(Map<String, dynamic> data) =>
      _restore(() => data);

  Future<ImportResult> _restore(Object? Function() decode) {
    return SyncSuspension.run(() async {
      SyncBindingService? unbound;
      final result = await _importFromJson(
        decode,
        onUnbound: (binding) => unbound = binding,
      );
      final binding = unbound;
      if (binding == null) return result;
      try {
        // Every insert queued itself; an unbound database pushes nothing.
        await _db.syncOutboxDao.clear();
        await binding.writeBindFloor();
      } catch (e) {
        if (result.success) {
          return ImportResult(success: false, error: e.toString());
        }
      } finally {
        // Once, after the last calendar import: a bloc told earlier would
        // reload a half-restored store and never reload again.
        CalendarEventService.notifyExternalChange();
      }
      return result;
    });
  }

  Future<ImportResult> _importFromJson(
    Object? Function() decode, {
    required void Function(SyncBindingService binding) onUnbound,
  }) async {
    try {
      final data = decode() as Map<String, dynamic>;

      final folders = data['folders'] as List? ?? [];
      final notes = data['notes'] as List? ?? [];
      final settings = data['settings'] as Map<String, dynamic>? ?? {};
      final markdownShortcuts = data['markdownShortcuts'] as String?;

      int foldersImported = 0;
      int notesImported = 0;

      // An import appends copies, so every row gets a fresh id — which means
      // every reference to an archived id has to be translated to the id the
      // copy actually got. Without this a restore onto a database that does
      // not already contain the archive's rows (a fresh install, the
      // onboarding path) inserts subfolders and notes under ids that exist
      // nowhere, and they are invisible in the browser.
      final folderIdMap = <String, String>{};
      final noteIdMap = <String, String>{};

      final binding = await SyncBindingService.getInstance();
      await binding.unbind();
      onUnbound(binding);

      final folderEntries = <FolderImportEntry>[
        for (final map in _foldersParentsFirst(folders))
          (
            archivedId: map[JsonKeys.id] is String
                ? map[JsonKeys.id] as String
                : null,
            parentId: map[JsonKeys.parentId] as String?,
            name: map[JsonKeys.name] as String,
            createdAt: _archivedDate(map[JsonKeys.createdAt]) ?? DateTime.now(),
            updatedAt: _archivedDate(map[JsonKeys.updatedAt]),
            noteSortOrder: map[JsonKeys.noteSortOrder] as String?,
            subfolderSortOrder: map[JsonKeys.subfolderSortOrder] as String?,
            label: ItemLabel.fromName(map[JsonKeys.label] as String?),
            ownerId: JsonKeys.ownerIdOf(map),
          ),
      ];
      final folderIds = await _db.folderDao.importFolders(folderEntries);
      for (var i = 0; i < folderEntries.length; i++) {
        final archivedId = folderEntries[i].archivedId;
        if (archivedId != null) folderIdMap[archivedId] = folderIds[i];
      }
      foldersImported = folderIds.length;

      // A note whose folder the archive did not carry keeps it only while it
      // is a live folder here; otherwise it restores at the root, never under
      // an id that exists nowhere, where nobody could see it. Resolved once
      // per archived folder.
      final unarchivedFolders = <String, String>{};
      Future<String> restoredFolderId(String archived) async {
        final mapped = folderIdMap[archived];
        if (mapped != null) return mapped;
        if (archived.isEmpty) return archived;
        final known = unarchivedFolders[archived];
        if (known != null) return known;
        final live = await _db.folderDao.getFoldersByIds([archived]);
        return unarchivedFolders[archived] = live.isEmpty ? '' : archived;
      }

      for (final noteData in notes) {
        final map = noteData as Map<String, dynamic>;
        final content = map[JsonKeys.content] as String? ?? '';
        final preview = NoteMetadata.generatePreview(content);
        final archivedFolderId = map[JsonKeys.folderId] as String;

        final now = DateTime.now();
        final note = await _db.noteDao.importNote(
          folderId: await restoredFolderId(archivedFolderId),
          title: map[JsonKeys.title] as String,
          preview: preview,
          contentLength: content.length,
          chunkCount: 1,
          label: ItemLabel.fromName(map[JsonKeys.label] as String?),
          createdAt: _archivedDate(map[JsonKeys.createdAt]) ?? now,
          updatedAt: _archivedDate(map[JsonKeys.updatedAt]) ?? now,
          content: content,
          ownerId: JsonKeys.ownerIdOf(map),
        );
        final archivedNoteId = map[JsonKeys.id];
        if (archivedNoteId is String) noteIdMap[archivedNoteId] = note.id;
        notesImported++;
      }

      for (final entry in settings.entries) {
        if (entry.key.startsWith(SettingsKeys.pairingPrefix) ||
            entry.key.startsWith(SettingsKeys.syncSpacePrefix)) {
          continue;
        }
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
            'note_bar_${noteIdMap[entry.key] ?? entry.key}',
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
            '${SettingsKeys.moneyNoteCurrencyPrefix}'
            '${noteIdMap[entry.key] ?? entry.key}',
            entry.value.toString(),
          );
        }
      }

      // Reset MarkdownBarService so it picks up restored data
      MarkdownBarService.reset();

      // The colour palette is a settings-derived cache like the bar above.
      // Reset drops the pre-restore swatches; re-initialising right away
      // republishes the restored ones, so a picker left open repaints once
      // and correctly instead of falling back to the built-ins.
      CalendarPaletteService.reset();
      await CalendarPaletteService.getInstance();

      // Same reason for the label style: every labelled row on screen reads
      // the published value, so a restored `label_style` has to reach the
      // facade now rather than on the next launch.
      LabelAppearanceService.reset();
      await LabelAppearanceService.getInstance();

      final counterData = data['counterData'] as Map<String, dynamic>?;
      if (counterData != null) {
        await GetIt.I<CounterService>().importData(
          counterData,
          noteIdMap: noteIdMap,
        );
      }

      // Calendar categories, events & public holidays (v3/v4+ backups).
      // Missing keys simply leave existing data in place — older backups
      // stay valid. Categories import first so events (which reference a
      // category id) and rendering resolve against the restored set.
      final calendarCategories = data['calendarCategories'] as List?;
      if (calendarCategories != null) {
        await (await CategoryService.getInstance()).importData(
          calendarCategories,
        );
      }
      // Category alerts (v42+ backups), right after the categories they hang
      // off and before the events' own alerts. The templates' strand rule,
      // keyed to categories for their reason: the import above wiped and
      // replaced the category id space, so alerts kept from this device would
      // orphan on its old custom ids — and its built-in categories' alerts
      // would quietly start ringing for the restored events.
      final categoryAlerts = data['categoryAlerts'] as List?;
      if (categoryAlerts != null || calendarCategories != null) {
        final alerts = await EventAlertService.getInstance();
        if (categoryAlerts != null) {
          await alerts.importCategoryAlerts(categoryAlerts);
        } else {
          await alerts.clearCategoryAlertsForImport();
        }
      }
      // Category profiles (v8 backups), the category alerts' strand rule. A
      // profile whose category the restored set does not hold is dropped,
      // counted in the log only.
      final categoryProfiles = data['categoryProfiles'] as List?;
      if (categoryProfiles != null || calendarCategories != null) {
        final profiles = await CategoryProfileService.getInstance();
        if (categoryProfiles != null) {
          await CategoryService.getInstance();
          final dropped = await profiles.importCategoryProfiles(
            categoryProfiles,
            knownCategoryIds: {
              for (final category in CalendarCategories.all) category.id,
            },
          );
          if (dropped > 0) {
            debugPrint('[BackupService] Dropped $dropped category profiles');
          }
        } else {
          await profiles.clearCategoryProfilesForImport();
        }
      }
      // Event templates (v29+ backups). The strand rule applies, but keyed to
      // **categories** rather than events — a template's only foreign
      // reference is its category id, and the category import above just
      // wiped and replaced that id space.
      final eventTemplates = data['eventTemplates'] as List?;
      if (eventTemplates != null || calendarCategories != null) {
        final templates = await EventTemplateService.getInstance();
        if (eventTemplates != null) {
          await templates.importData(eventTemplates);
        } else {
          await templates.clearAllForImport();
        }
      }
      // Saved calendar filters (v35+ backups). Self-contained for the same
      // reason vocabularies are: a preset's only foreign reference is the
      // category ids inside its filter blob, and an id no category answers to
      // simply hides nothing — so an absent key leaves existing presets in
      // place rather than stranding anything.
      final filterPresets = data['calendarFilterPresets'] as List?;
      if (filterPresets != null) {
        await (await FilterPresetService.getInstance()).importData(
          filterPresets,
        );
      }
      // Saved overview lists (v41+ backups), self-contained like the saved
      // filters above: an absent key leaves existing views in place.
      final overviewViews = data['overviewViews'] as List?;
      if (overviewViews != null) {
        await (await OverviewViewService.getInstance()).importData(
          overviewViews,
        );
      }
      // Digests (v42+ backups), the same rule as the saved lists above.
      final eventDigests = data['eventDigests'] as List?;
      if (eventDigests != null) {
        await (await EventDigestService.getInstance()).importData(eventDigests);
      }
      // Vocabularies (v32+ backups). Self-contained — no foreign reference to
      // strand — so an absent key simply leaves existing lists in place.
      final vocabularies = data['vocabularies'] as List?;
      if (vocabularies != null) {
        await (await VocabularyService.getInstance()).importData(vocabularies);
      }
      final calendarEvents = data['calendarEvents'] as List?;
      if (calendarEvents != null) {
        // Backups older than v7 store priorities on the retired
        // 5-is-highest scale; flip them so the user's ranking survives. The
        // linked note, meanwhile, was copied under a new id in every version,
        // so the link is re-pointed at the copy.
        final backupVersion = data['version'] as int? ?? 1;
        final events = [
          for (final event in calendarEvents)
            if (event is Map<String, dynamic>)
              {
                ...event,
                'noteId': ?noteIdMap[event['noteId']],
                if (backupVersion < 7 &&
                    event['priority'] is int &&
                    (event['priority'] as int) >= 1 &&
                    (event['priority'] as int) <= 5)
                  'priority': 6 - (event['priority'] as int),
              }
            else
              event,
        ];
        await (await CalendarEventService.getInstance()).importData(events);
      }
      // Per-occurrence description overrides (v24+ backups). Unlike the keys
      // above, an absent key here is NOT a no-op when the backup carried
      // events: the event import wipes and reinserts, so keeping the previous
      // database's overrides would strand them against unrelated event ids.
      final eventOccurrences = data['eventOccurrences'] as List?;
      if (eventOccurrences != null || calendarEvents != null) {
        final occurrences = await EventOccurrenceService.getInstance();
        if (eventOccurrences != null) {
          await occurrences.importData(eventOccurrences);
        } else {
          await occurrences.clearAllForImport();
        }
      }
      // Presence marks (v26+ backups). Same strand rule as the overrides
      // above, for the same reason. A pre-v37 archive's rows carry no
      // `status`, and absent decodes to `missed` — the only thing a live row
      // could have meant before statuses existed. The events' own
      // `assumeAbsent` / `assumeAbsentFromMs` ride `calendarEvents`, so the
      // version stays 7.
      final eventAbsences = data['eventAbsences'] as List?;
      if (eventAbsences != null || calendarEvents != null) {
        final presence = await EventPresenceService.getInstance();
        if (eventAbsences != null) {
          await presence.importData(eventAbsences);
        } else {
          await presence.clearAllForImport();
        }
      }
      // Cancelled occurrences (v30+ backups). Same strand rule, and the one
      // where getting it wrong is worst: a stale skip does not render a wrong
      // colour, it hides occurrences of whatever event later takes that id.
      final eventSkips = data['eventSkips'] as List?;
      if (eventSkips != null || calendarEvents != null) {
        final skips = await EventSkipService.getInstance();
        if (eventSkips != null) {
          // Before v8 no surface could cancel a one-off, so its skip is a
          // converted series' leftover hiding it: v45 swept the on-disk rows.
          final oneOffIds = (data['version'] as int? ?? 1) < 8
              ? {
                  for (final event in calendarEvents ?? const <Object?>[])
                    if (event is Map && event['ruleKind'] == 'oneTime')
                      event['id'],
                }
              : const <Object?>{};
          final kept = [
            for (final skip in eventSkips)
              if (skip is! Map || !oneOffIds.contains(skip['eventId'])) skip,
          ];
          final dropped = eventSkips.length - kept.length;
          if (dropped > 0) {
            debugPrint('[BackupService] Dropped $dropped one-off skips');
          }
          await skips.importData(kept);
        } else {
          await skips.clearAllForImport();
        }
      }
      // Event alerts (v40+ backups). The same strand rule, keyed to
      // `calendarEvents` for the same reason — and this is the one where the
      // consequence is loudest: an alert left behind against an id the event
      // import has just handed to a different event does not draw a wrong
      // badge, it rings.
      final eventAlerts = data['eventAlerts'] as List?;
      if (eventAlerts != null || calendarEvents != null) {
        final alerts = await EventAlertService.getInstance();
        if (eventAlerts != null) {
          await alerts.importData(eventAlerts);
        } else {
          await alerts.clearAllForImport();
        }
      }
      final publicHolidays = data['publicHolidays'] as List?;
      if (publicHolidays != null) {
        await (await PublicHolidayService.getInstance()).importData(
          publicHolidays,
        );
      }

      // A restore replaces the event store wholesale, so every registration
      // the platform holds now names an event id that may belong to something
      // else entirely — and a stranded alert does not draw wrong, it rings.
      // Best-effort: a restore that worked must not report failure because the
      // scheduler could not reach the platform.
      try {
        await (await AlertScheduler.getInstance()).reconcileAll(
          AlertReconcileReason.backupRestored,
        );
      } catch (e) {
        debugPrint('[BackupService] Alert reconcile after import failed: $e');
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

  /// An archived `createdAt` / `updatedAt`, or null when the archive does not
  /// carry it or carries something no `DateTime` can read — a backup written
  /// before the field existed, or hand-edited. The caller then stamps the
  /// restore's own time, as `createFolder` / `createNote` always did.
  static DateTime? _archivedDate(Object? raw) =>
      raw is String ? DateTime.tryParse(raw) : null;

  /// The archive's folder rows, ordered so a parent always precedes its
  /// children.
  ///
  /// The exporter wrote them in whatever order `getAllFolders` returned,
  /// and a child created before its parent cannot be re-pointed at the copy
  /// the parent will become. A parent the archive does not carry, and a cycle
  /// no export could produce but a hand-edited file could, both simply stop
  /// the walk — that row still imports, under its parent id as written only
  /// while that is a live folder here, else at the root
  /// (`FolderDao.importFolders`).
  static List<Map<String, dynamic>> _foldersParentsFirst(List<dynamic> rows) {
    final maps = <Map<String, dynamic>>[
      for (final raw in rows)
        if (raw is Map<String, dynamic>) raw,
    ];
    final byId = <String, Map<String, dynamic>>{
      for (final map in maps)
        if (map[JsonKeys.id] is String) map[JsonKeys.id] as String: map,
    };

    final ordered = <Map<String, dynamic>>[];
    final placed = <Map<String, dynamic>>{};

    void place(Map<String, dynamic> map, Set<String> chain) {
      if (!placed.add(map)) return;
      final parentId = map[JsonKeys.parentId];
      if (parentId is String && !chain.contains(parentId)) {
        final parent = byId[parentId];
        if (parent != null) place(parent, {...chain, parentId});
      }
      ordered.add(map);
    }

    for (final map in maps) {
      place(map, const {});
    }
    return ordered;
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
