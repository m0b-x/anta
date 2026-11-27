import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import '../database/daos/folder_dao.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../constants/calendar_categories.dart';
import '../constants/category_kinds.dart';
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
import 'database_replacing.dart';
import 'markdown_bar_service.dart';
import 'public_holiday_service.dart';
import 'sync/sync_binding_service.dart';
import 'sync/sync_suspension.dart';

class BackupService {
  static BackupService? _instance;
  late AppDatabase _db;

  /// The open in flight, shared by every caller that arrives before it
  /// finishes.
  static Future<BackupService>? _opening;

  BackupService._();

  /// Published only once its database is set, the `SettingsService` shape:
  /// stored before the await, a second caller in that window got a service
  /// whose `_db` was not yet initialized.
  static Future<BackupService> getInstance() {
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
  static Future<BackupService> _open() async {
    for (var attempt = 0; attempt < _openAttempts; attempt++) {
      final generation = DatabaseLifecycle.generation;
      final db = await AppDatabase.getInstance();
      final raced = _instance;
      if (raced != null) return raced;
      if (DatabaseLifecycle.generation != generation) continue;
      final service = BackupService._().._db = db;
      _instance = service;
      DatabaseLifecycle.registerResetHandler(reset);
      return service;
    }
    throw StateError('the database switched while the backup was opened');
  }

  /// Drops the cached singleton so the next [getInstance] rebinds to the
  /// currently-active [AppDatabase]. Invoked by [DatabaseLifecycle] when the
  /// active database changes.
  static void reset() {
    _instance = null;
    _opening = null;
  }

  /// Reads and decodes the backup file at [path] in a worker isolate, for
  /// [validateBackupData] and [importFromData]: a large database's backup is
  /// megabytes of JSON, which would hold the UI isolate twice if each step
  /// decoded the text itself. Null when the file is not UTF-8 text (a `.zip`
  /// picked by mistake) or the text is not JSON — both are "not a backup";
  /// a file that cannot be read throws.
  static Future<Object?> readBackupFile(String path) => Isolate.run(() {
    final bytes = File(path).readAsBytesSync();
    try {
      return jsonDecode(utf8.decode(bytes));
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
      final decoded = decode();
      final refusal = _shapeRefusal(decoded);
      if (refusal != null) {
        return BackupValidationResult(
          isValid: false,
          error: 'Invalid backup format: $refusal',
        );
      }
      final data = decoded as Map<String, dynamic>;

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
        exportedAt: switch (data['exportedAt']) {
          final String at => at,
          _ => null,
        },
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
  /// A file whose folders or notes the restore cannot apply is refused
  /// before the unbind and changes nothing. Past that, a damaged optional
  /// section or row is skipped and counted ([ImportResult.skipped]), and
  /// every row write runs in one transaction: a database error halfway rolls
  /// all of them back, leaving the database as it was apart from the unbind,
  /// and a retry restores once.
  ///
  /// **Only where nothing else writes** — the welcome page, which is the one
  /// caller. A write a service had already queued from outside the
  /// transaction waits on its lock, and the restore, joining that service's
  /// queue, waits on the write: neither ends. Only the counters' pending
  /// flush is drained first. Offered anywhere the app is in use (settings),
  /// the write chains of `CategoryService`, `CategoryProfileService`,
  /// `FilterPresetService`, `OverviewViewService` and `EventDigestService`
  /// would have to be drained before the transaction opens too.
  ///
  /// Once the unbind has run, the queue is cleared, the floor written and the
  /// calendar told whether the restore succeeded or not. After a rollback
  /// that is still right: the database stays unbound, and the rows it held
  /// before must neither sit queued nor stand above the floor, or they would
  /// win over the space's twins at the next bind; the calendar reloads a
  /// store the rollback put back beneath it.
  Future<ImportResult> importFromJson(String jsonString) =>
      _restore(() => jsonDecode(jsonString));

  /// [importFromJson] for a backup already decoded ([readBackupFile]).
  Future<ImportResult> importFromData(Map<String, dynamic> data) =>
      _restore(() => data);

  /// The suspension holds this isolate's engine. The shared check runs in an
  /// isolate of its own, which reads no static of this one: the marker is
  /// what holds it.
  Future<ImportResult> _restore(Object? Function() decode) =>
      DatabaseReplacing.run(() => _restoreSuspended(decode));

  Future<ImportResult> _restoreSuspended(Object? Function() decode) {
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
        // reload a store still being restored and never reload again.
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
      final decoded = decode();
      // Before the unbind and before any write: a file the restore would
      // throw on halfway changes nothing at all.
      final refusal = _shapeRefusal(decoded);
      if (refusal != null) return ImportResult(success: false, error: refusal);
      final data = decoded as Map<String, dynamic>;

      // Past the folders and notes, what cannot be read is skipped and
      // counted, never thrown: those two are what nobody can make again, and
      // a damaged optional section must not cost them.
      var skipped = 0;
      T? optional<T>(String key) {
        final value = data[key];
        if (value == null || value is T) return value as T?;
        debugPrint('[BackupService] Skipped $key: not a $T');
        skipped++;
        return null;
      }

      // A row that is not an object is one each service skips unseen.
      List<dynamic>? rows(String key) {
        final list = optional<List<dynamic>>(key);
        if (list != null) skipped += list.where((row) => row is! Map).length;
        return list;
      }

      final folders = data['folders'] as List? ?? [];
      final notes = data['notes'] as List? ?? [];
      final settings = optional<Map<String, dynamic>>('settings') ?? {};
      final markdownShortcuts = optional<String>('markdownShortcuts');
      final barProfiles = optional<String>('barProfiles');
      final activeBar = optional<String>('activeBar');
      final noteBarAssignments = optional<Map<String, dynamic>>(
        'noteBarAssignments',
      );
      final noteMoneyCurrencies = optional<Map<String, dynamic>>(
        'noteMoneyCurrencies',
      );
      final counterData = optional<Map<String, dynamic>>('counterData');
      final calendarCategories = rows('calendarCategories');
      final categoryAlerts = rows('categoryAlerts');
      final categoryProfiles = rows('categoryProfiles');
      final eventTemplates = rows('eventTemplates');
      final filterPresets = rows('calendarFilterPresets');
      final overviewViews = rows('overviewViews');
      final eventDigests = rows('eventDigests');
      final vocabularies = rows('vocabularies');
      final calendarEvents = rows('calendarEvents');
      final eventOccurrences = rows('eventOccurrences');
      final eventAbsences = rows('eventAbsences');
      final eventSkips = rows('eventSkips');
      final eventAlerts = rows('eventAlerts');
      final publicHolidays = optional<List<dynamic>>('publicHolidays');

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

      // The counters' rule (`CounterService.importData`): the map names
      // every note the restore creates, so a per-note row whose note it lacks
      // belongs to a note the archive did not carry and is dropped — under
      // its archived id it would be an orphan, or overwrite the original's on
      // the database the archive came from. An archive without notes is no
      // exception: every note it names was deleted at its source.
      String? restoredNoteId(String archived) => noteIdMap[archived];

      final binding = await SyncBindingService.getInstance();
      await binding.unbind();
      onUnbound(binding);

      // Every service the writes go through is opened before the
      // transaction, and only those the archive reaches: an open still in
      // flight from outside it would wait on the transaction's lock while the
      // transaction waited on the open, and one first opened inside would
      // cache rows a rollback takes back.
      final touchesCategories = calendarCategories != null;
      final touchesEvents = calendarEvents != null;
      final counters = counterData != null
          ? await CounterService.getInstance()
          : null;
      final categories = touchesCategories || categoryProfiles != null
          ? await CategoryService.getInstance()
          : null;
      final alerts =
          touchesCategories ||
              categoryAlerts != null ||
              touchesEvents ||
              eventAlerts != null
          ? await EventAlertService.getInstance()
          : null;
      final profiles = touchesCategories || categoryProfiles != null
          ? await CategoryProfileService.getInstance()
          : null;
      final templates = touchesCategories || eventTemplates != null
          ? await EventTemplateService.getInstance()
          : null;
      final presets = filterPresets != null
          ? await FilterPresetService.getInstance()
          : null;
      final views = overviewViews != null
          ? await OverviewViewService.getInstance()
          : null;
      final digests = eventDigests != null
          ? await EventDigestService.getInstance()
          : null;
      final vocabularyLists = vocabularies != null
          ? await VocabularyService.getInstance()
          : null;
      final events = touchesEvents
          ? await CalendarEventService.getInstance()
          : null;
      final occurrences = touchesEvents || eventOccurrences != null
          ? await EventOccurrenceService.getInstance()
          : null;
      final presence = touchesEvents || eventAbsences != null
          ? await EventPresenceService.getInstance()
          : null;
      final skips = touchesEvents || eventSkips != null
          ? await EventSkipService.getInstance()
          : null;
      final holidays = publicHolidays != null
          ? await PublicHolidayService.getInstance()
          : null;
      // A tap's flush queued from outside would hold the counter import
      // behind it, inside the transaction it waits on.
      await counters?.flush();

      // Every row write in one transaction: a throw anywhere rolls back the
      // folders, notes, settings, counters and calendar alike, so a retry of
      // the corrected file restores once. The services' imports join it
      // through Drift's zone.
      try {
        await _db.transaction(() async {
          final folderEntries = <FolderImportEntry>[
            for (final map in _foldersParentsFirst(folders))
              (
                archivedId: map[JsonKeys.id] is String
                    ? map[JsonKeys.id] as String
                    : null,
                parentId: map[JsonKeys.parentId] as String?,
                name: map[JsonKeys.name] as String,
                createdAt:
                    _archivedDate(map[JsonKeys.createdAt]) ?? DateTime.now(),
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

          // A note whose folder the archive did not carry keeps it only while
          // it is a live folder here; otherwise it restores at the root, never
          // under an id that exists nowhere, where nobody could see it.
          // Resolved once per archived folder.
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

          // A per-entry value the store cannot hold as text is skipped and
          // counted, never written as its `toString()`.
          Future<void> setSetting(String key, Object? value) async {
            final text = _settingText(value);
            if (text == null) {
              debugPrint('[BackupService] Skipped setting $key');
              skipped++;
              return;
            }
            await _db.userSettingsDao.setValue(key, text);
          }

          for (final entry in settings.entries) {
            if (entry.key.startsWith(SettingsKeys.pairingPrefix) ||
                entry.key.startsWith(SettingsKeys.syncSpacePrefix)) {
              continue;
            }
            await setSetting(entry.key, entry.value);
          }

          if (markdownShortcuts != null) {
            await _db.userSettingsDao.setValue(
              'markdown_shortcuts',
              markdownShortcuts,
            );
          }

          // Restore bar profiles & per-note assignments (v2+ backups)
          if (barProfiles != null) {
            await _db.userSettingsDao.setValue(
              'markdown_bar_profiles',
              barProfiles,
            );
          }
          if (activeBar != null) {
            await _db.userSettingsDao.setValue(
              'active_markdown_bar',
              activeBar,
            );
          }
          if (noteBarAssignments != null) {
            for (final entry in noteBarAssignments.entries) {
              final noteId = restoredNoteId(entry.key);
              if (noteId == null) continue;
              await setSetting('note_bar_$noteId', entry.value);
            }
          }

          // Per-note money currency overrides (v6+ backups; missing key
          // leaves existing overrides in place).
          if (noteMoneyCurrencies != null) {
            for (final entry in noteMoneyCurrencies.entries) {
              final noteId = restoredNoteId(entry.key);
              if (noteId == null) continue;
              await setSetting(
                '${SettingsKeys.moneyNoteCurrencyPrefix}$noteId',
                entry.value,
              );
            }
          }

          // Through `getInstance`, never GetIt: after an in-process database
          // switch GetIt still holds the instance on the closed database.
          if (counters != null) {
            skipped += await counters.importData(
              counterData!,
              noteIdMap: noteIdMap,
            );
          }

          // Calendar categories, events & public holidays (v3/v4+ backups).
          // Missing keys simply leave existing data in place — older backups
          // stay valid. Categories import first so events (which reference a
          // category id) and rendering resolve against the restored set.
          //
          // Each import returns the object rows it could not read; a row of
          // a parent the restore skipped (an alert of a damaged event) is
          // counted once, with that parent.
          if (calendarCategories != null) {
            skipped += await categories!.importData(calendarCategories);
          }
          // Category alerts (v42+ backups), right after the categories they
          // hang off and before the events' own alerts. The templates' strand
          // rule, keyed to categories for their reason: the import above wiped
          // and replaced the category id space, so alerts kept from this
          // device would orphan on its old custom ids — and its built-in
          // categories' alerts would quietly start ringing for the restored
          // events.
          if (categoryAlerts != null || calendarCategories != null) {
            if (categoryAlerts != null) {
              skipped += await alerts!.importCategoryAlerts(categoryAlerts);
            } else {
              await alerts!.clearCategoryAlertsForImport();
            }
          }
          // Category profiles (v8 backups), the category alerts' strand rule. A
          // profile whose category the restored set does not hold is dropped:
          // left out here, so the service counts only the rows it cannot
          // read, and it costs nothing more than its category already did —
          // the one dependant the restore drops rather than keeps unseen. A
          // row that is not an object [rows] has counted, so it is left out
          // too. The category facade it checks against was published when
          // [categories] opened, or by the import above.
          if (categoryProfiles != null || calendarCategories != null) {
            if (categoryProfiles != null) {
              final knownCategoryIds = {
                for (final category in CalendarCategories.all) category.id,
              };
              final readable = [
                for (final row in categoryProfiles)
                  if (row is Map &&
                      switch (row[CategoryProfileKeys.categoryId]) {
                        final String id => knownCategoryIds.contains(id),
                        _ => true,
                      })
                    row,
              ];
              final orphans =
                  categoryProfiles.whereType<Map>().length - readable.length;
              if (orphans > 0) {
                debugPrint(
                  '[BackupService] Dropped $orphans category profiles',
                );
              }
              skipped += await profiles!.importCategoryProfiles(
                readable,
                knownCategoryIds: knownCategoryIds,
              );
            } else {
              await profiles!.clearCategoryProfilesForImport();
            }
          }
          // Event templates (v29+ backups). The strand rule applies, but keyed
          // to **categories** rather than events — a template's only foreign
          // reference is its category id, and the category import above just
          // wiped and replaced that id space.
          if (eventTemplates != null || calendarCategories != null) {
            if (eventTemplates != null) {
              skipped += await templates!.importData(eventTemplates);
            } else {
              await templates!.clearAllForImport();
            }
          }
          // Saved calendar filters (v35+ backups). Self-contained for the same
          // reason vocabularies are: a preset's only foreign reference is the
          // category ids inside its filter blob, and an id no category answers
          // to simply hides nothing — so an absent key leaves existing presets
          // in place rather than stranding anything.
          if (filterPresets != null) {
            skipped += await presets!.importData(filterPresets);
          }
          // Saved overview lists (v41+ backups), self-contained like the saved
          // filters above: an absent key leaves existing views in place.
          if (overviewViews != null) {
            skipped += await views!.importData(overviewViews);
          }
          // Digests (v42+ backups), the same rule as the saved lists above.
          if (eventDigests != null) {
            skipped += await digests!.importData(eventDigests);
          }
          // Vocabularies (v32+ backups). Self-contained — no foreign reference
          // to strand — so an absent key simply leaves existing lists in place.
          if (vocabularies != null) {
            skipped += await vocabularyLists!.importData(vocabularies);
          }
          if (calendarEvents != null) {
            // Backups older than v7 store priorities on the retired
            // 5-is-highest scale; flip them so the user's ranking survives.
            // The linked note, meanwhile, was copied under a new id in every
            // version, so the link is re-pointed at the copy — or cleared when
            // the archive did not carry the note: no restored note answers to
            // its old id.
            final backupVersion = data['version'] as int? ?? 1;
            final restoredEvents = [
              for (final event in calendarEvents)
                if (event is Map<String, dynamic>)
                  {
                    ...event,
                    'noteId': switch (event['noteId']) {
                      final String id => restoredNoteId(id),
                      _ => null,
                    },
                    if (backupVersion < 7 &&
                        event['priority'] is int &&
                        (event['priority'] as int) >= 1 &&
                        (event['priority'] as int) <= 5)
                      'priority': 6 - (event['priority'] as int),
                  }
                else
                  event,
            ];
            skipped += await events!.importData(restoredEvents);
          }
          // Per-occurrence description overrides (v24+ backups). Unlike the
          // keys above, an absent key here is NOT a no-op when the backup
          // carried events: the event import wipes and reinserts, so keeping
          // the previous database's overrides would strand them against
          // unrelated event ids.
          if (eventOccurrences != null || calendarEvents != null) {
            if (eventOccurrences != null) {
              skipped += await occurrences!.importData(eventOccurrences);
            } else {
              await occurrences!.clearAllForImport();
            }
          }
          // Presence marks (v26+ backups). Same strand rule as the overrides
          // above, for the same reason. A pre-v37 archive's rows carry no
          // `status`, and absent decodes to `missed` — the only thing a live
          // row could have meant before statuses existed. The events' own
          // `assumeAbsent` / `assumeAbsentFromMs` ride `calendarEvents`, so
          // the version stays 7.
          if (eventAbsences != null || calendarEvents != null) {
            if (eventAbsences != null) {
              skipped += await presence!.importData(eventAbsences);
            } else {
              await presence!.clearAllForImport();
            }
          }
          // Cancelled occurrences (v30+ backups). Same strand rule, and the
          // one where getting it wrong is worst: a stale skip does not render
          // a wrong colour, it hides occurrences of whatever event later takes
          // that id.
          if (eventSkips != null || calendarEvents != null) {
            if (eventSkips != null) {
              // Before v8 no surface could cancel a one-off, so its skip is a
              // converted series' leftover hiding it: v45 swept the on-disk
              // rows.
              final oneOffIds = (data['version'] as int? ?? 1) < 8
                  ? {
                      for (final event in calendarEvents ?? const <Object?>[])
                        if (event is Map && event['ruleKind'] == 'oneTime')
                          event['id'],
                    }
                  : const <Object?>{};
              final kept = [
                for (final skip in eventSkips)
                  if (skip is! Map || !oneOffIds.contains(skip['eventId']))
                    skip,
              ];
              final dropped = eventSkips.length - kept.length;
              if (dropped > 0) {
                debugPrint('[BackupService] Dropped $dropped one-off skips');
              }
              skipped += await skips!.importData(kept);
            } else {
              await skips!.clearAllForImport();
            }
          }
          // Event alerts (v40+ backups). The same strand rule, keyed to
          // `calendarEvents` for the same reason — and this is the one where
          // the consequence is loudest: an alert left behind against an id the
          // event import has just handed to a different event does not draw a
          // wrong badge, it rings.
          if (eventAlerts != null || calendarEvents != null) {
            if (eventAlerts != null) {
              skipped += await alerts!.importData(eventAlerts);
            } else {
              await alerts!.clearAllForImport();
            }
          }
          if (publicHolidays != null) {
            skipped += await holidays!.importData(publicHolidays);
          }
        });
      } catch (_) {
        // Rolled back: every cache an import refilled from inside the
        // transaction holds rows that are gone, so each is read again.
        await _rereadAfterRollback({
          'counters': ?counters?.reload,
          'categories': ?categories?.reload,
          'category profiles': ?profiles?.reload,
          'templates': ?templates?.reload,
          'filter presets': ?presets?.reload,
          'overview views': ?views?.reload,
          'digests': ?digests?.reload,
          'vocabularies': ?vocabularyLists?.reload,
          if (events != null) 'events': CalendarEventService.refreshAfterSync,
          'occurrences': ?occurrences?.reload,
          'presence': ?presence?.reload,
          'skips': ?skips?.reload,
          'alerts': ?alerts?.reload,
          'holidays': ?holidays?.reload,
        });
        rethrow;
      }

      // Everything below runs after the commit, so each step is best-effort:
      // the rows are in, and a restore reported as failed would be retried
      // into duplicates.
      //
      // Settings-derived caches first. The bar re-reads on its next open;
      // the palette and the label style republish now, so a picker or a
      // labelled row left open repaints once and correctly instead of
      // falling back to the built-ins until the next launch.
      //
      // Then the alerts: a restore replaces the event store wholesale, so
      // every registration the platform holds now names an event id that may
      // belong to something else entirely — and a stranded alert does not
      // draw wrong, it rings.
      await _afterCommit({
        'markdown bar': () async => MarkdownBarService.reset(),
        'palette': () {
          CalendarPaletteService.reset();
          return CalendarPaletteService.getInstance();
        },
        'label style': () {
          LabelAppearanceService.reset();
          return LabelAppearanceService.getInstance();
        },
        'alert reconcile': () async => (await AlertScheduler.getInstance())
            .reconcileAll(AlertReconcileReason.backupRestored),
      });

      return ImportResult(
        success: true,
        foldersImported: foldersImported,
        notesImported: notesImported,
        skipped: skipped,
      );
    } catch (e) {
      return ImportResult(success: false, error: e.toString());
    }
  }

  /// Why the restore would refuse [data], or null when it can restore every
  /// folder and note: the top level a map with an int `version` or none,
  /// `folders` and `notes` lists of maps, each folder's `name` and each
  /// note's `title` and `folderId` strings, and every other field the two
  /// read a string or absent. Absent and JSON null are one, as they always
  /// were. Nothing else refuses a file: a damaged optional section is
  /// skipped and counted by the restore, never worth the notes.
  ///
  /// [validateBackupData] runs the same check, so the confirmation never
  /// opens on a file the restore would refuse.
  static String? _shapeRefusal(Object? data) {
    if (data is! Map<String, dynamic>) return 'the backup is not an object';
    String? optional(Map<String, dynamic> map, String key, String where) {
      final value = map[key];
      return value == null || value is String ? null : '$where: $key';
    }

    // The version decides how the calendar rows are read (priorities before
    // v7, one-off skips before v8): a guess could rewrite them.
    final version = data['version'];
    if (version != null && version is! int) return 'not an int: version';
    for (final key in const ['folders', 'notes']) {
      final value = data[key];
      if (value != null && value is! List) return 'not a list: $key';
    }
    for (final (i, folder) in (data['folders'] as List? ?? const []).indexed) {
      if (folder is! Map<String, dynamic>) return 'folder $i is not an object';
      if (folder[JsonKeys.name] is! String) return 'folder $i has no name';
      for (final key in const [
        JsonKeys.parentId,
        JsonKeys.noteSortOrder,
        JsonKeys.subfolderSortOrder,
        JsonKeys.label,
      ]) {
        if (optional(folder, key, 'folder $i') case final error?) return error;
      }
    }
    for (final (i, note) in (data['notes'] as List? ?? const []).indexed) {
      if (note is! Map<String, dynamic>) return 'note $i is not an object';
      if (note[JsonKeys.title] is! String) return 'note $i has no title';
      if (note[JsonKeys.folderId] is! String) return 'note $i has no folder';
      for (final key in const [JsonKeys.content, JsonKeys.label]) {
        if (optional(note, key, 'note $i') case final error?) return error;
      }
    }
    return null;
  }

  /// Re-reads each service a rolled-back restore reached, one failure never
  /// stopping the rest — the sync hooks' `_reloadEach`.
  static Future<void> _rereadAfterRollback(
    Map<String, Future<Object?> Function()> rereads,
  ) => _eachLogged(rereads, 're-read after rollback');

  /// The steps after a committed restore, each logged rather than reported:
  /// the rows are in, and none of these may turn the restore into a failure.
  ///
  /// [afterCommitStepForTesting] runs first among them, so a test can make
  /// one throw and see every later step still run.
  static Future<void> _afterCommit(
    Map<String, Future<Object?> Function()> steps,
  ) => _eachLogged({
    'test step': ?afterCommitStepForTesting,
    ...steps,
  }, 'after the commit');

  /// A step [_afterCommit] runs with the others; null outside tests.
  @visibleForTesting
  static Future<Object?> Function()? afterCommitStepForTesting;

  static Future<void> _eachLogged(
    Map<String, Future<Object?> Function()> steps,
    String when,
  ) async {
    for (final MapEntry(key: what, value: step) in steps.entries) {
      try {
        await step();
      } catch (e) {
        debugPrint('[BackupService] $what $when failed: $e');
      }
    }
  }

  /// An archived setting's value as the text the store holds, or null when
  /// it has none: the exporter wrote text, and a number or a flag an older
  /// or hand-edited file carries reads as the text it stands for — an object,
  /// a list or a null stands for no setting.
  static String? _settingText(Object? value) => switch (value) {
    final String text => text,
    num() || bool() => '$value',
    _ => null,
  };

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
  ///
  /// Siblings come out in their archived `position` order, because
  /// `importFolders` appends each parent's children in entry order: the
  /// manual order is what the person arranged, and the list order is only
  /// what the query returned. A group in which any sibling lacks an int
  /// position keeps the list order.
  static List<Map<String, dynamic>> _foldersParentsFirst(List<dynamic> rows) {
    final maps = <Map<String, dynamic>>[
      for (final raw in rows)
        if (raw is Map<String, dynamic>) raw,
    ];
    final byId = <String, Map<String, dynamic>>{
      for (final map in maps)
        if (map[JsonKeys.id] is String) map[JsonKeys.id] as String: map,
    };
    final siblings = <String?, List<Map<String, dynamic>>>{};
    for (final map in maps) {
      final parentId = map[JsonKeys.parentId];
      siblings
          .putIfAbsent(parentId is String ? parentId : null, () => [])
          .add(map);
    }
    for (final group in siblings.values) {
      if (!group.every((map) => map['position'] is int)) continue;
      final listOrder = {for (final (i, map) in group.indexed) map: i};
      group.sort((a, b) {
        final byPosition = (a['position'] as int).compareTo(
          b['position'] as int,
        );
        return byPosition != 0 ? byPosition : listOrder[a]! - listOrder[b]!;
      });
    }

    final indexInGroup = <Map<String, dynamic>, int>{
      for (final group in siblings.values)
        for (final (i, map) in group.indexed) map: i,
    };
    // Per group, how far its siblings have been walked: a 16,384-folder
    // parent must not rescan its earlier siblings for every child.
    final walked = <String?, int>{};

    final ordered = <Map<String, dynamic>>[];
    final placed = <Map<String, dynamic>>{};
    final emitted = <String>{};

    void place(Map<String, dynamic> map, Set<String> chain) {
      if (!placed.add(map)) return;
      final parentId = map[JsonKeys.parentId];
      final key = parentId is String ? parentId : null;
      if (key != null && !chain.contains(key)) {
        final parent = byId[key];
        if (parent != null) place(parent, {...chain, key});
      }
      // The siblings that sort first go first — unless the parent is still
      // being walked, which only a cycle does, and then the list order holds.
      if (key == null || !byId.containsKey(key) || emitted.contains(key)) {
        final group = siblings[key]!;
        final at = indexInGroup[map]!;
        for (var i = walked[key] ?? 0; i < at; i = walked[key]!) {
          walked[key] = i + 1;
          place(group[i], chain);
        }
      }
      ordered.add(map);
      final id = map[JsonKeys.id];
      if (id is String) emitted.add(id);
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

  /// Rows and sections of the optional parts that could not be read and
  /// were left out of a restore that otherwise landed — said to the person,
  /// never only logged.
  final int skipped;

  const ImportResult({
    required this.success,
    this.error,
    this.foldersImported = 0,
    this.notesImported = 0,
    this.skipped = 0,
  });
}
