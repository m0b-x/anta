import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:get_it/get_it.dart';

import '../../l10n/app_localizations.dart';
import '../../models/item_label.dart';
import '../../repositories/folder_repository.dart';
import '../../repositories/note_repository.dart';
import '../alert_scheduler.dart';
import '../calendar_event_service.dart';
import '../category_service.dart';
import '../counter_service.dart';
import '../event_alert_service.dart';
import '../event_digest_service.dart';
import '../event_occurrence_service.dart';
import '../event_presence_service.dart';
import '../event_skip_service.dart';
import '../event_template_service.dart';
import '../filter_preset_service.dart';
import '../note_storage_service.dart';
import '../overview_view_service.dart';
import '../settings_service.dart';
import '../vocabulary_service.dart';
import 'sync_apply_hooks.dart';
import 'sync_table_binding.dart';

/// The production [SyncApplyHooks]: what a pulled page does to the caches,
/// the change streams, the calendar, the alert planner and the counters
/// (record §3.5).
///
/// Every target is resolved per call, never held: the database-bound
/// singletons are rebuilt after a database switch, and an instance kept here
/// would answer for the closed one. Each cache effect runs on its own guard,
/// so one failing service — the alert scheduler on a build without a
/// gateway — is logged and the others still run; the conflict copy does not.
class AppSyncApplyHooks implements SyncApplyHooks {
  final NoteRepository Function() _notes;
  final FolderRepository Function() _folders;
  final NoteStorageService Function() _noteStorage;
  final Future<CounterService> Function() _counters;
  final Future<void> Function() _reloadCalendar;
  final Future<void> Function() _reloadAlerts;
  final Future<void> Function() _reconcileAlerts;
  final Future<void> Function() _reloadVocabularies;
  final Future<AppLocalizations> Function() _strings;
  final DateTime Function() _now;

  /// The defaults are the app's own targets; a test passes its in-memory
  /// repositories and recorders in their place.
  AppSyncApplyHooks({
    NoteRepository Function()? notes,
    FolderRepository Function()? folders,
    NoteStorageService Function()? noteStorage,
    Future<CounterService> Function()? counters,
    Future<void> Function()? reloadCalendar,
    Future<void> Function()? reloadAlerts,
    Future<void> Function()? reconcileAlerts,
    Future<void> Function()? reloadVocabularies,
    Future<AppLocalizations> Function()? strings,
    DateTime Function()? now,
  }) : _notes = notes ?? GetIt.I.get<NoteRepository>,
       _folders = folders ?? GetIt.I.get<FolderRepository>,
       _noteStorage = noteStorage ?? GetIt.I.get<NoteStorageService>,
       _counters = counters ?? CounterService.getInstance,
       _reloadCalendar = reloadCalendar ?? _appReloadCalendar,
       _reloadAlerts = reloadAlerts ?? _appReloadAlerts,
       _reconcileAlerts = reconcileAlerts ?? _appReconcileAlerts,
       _reloadVocabularies = reloadVocabularies ?? _appReloadVocabularies,
       _strings = strings ?? _appStrings,
       _now = now ?? DateTime.now;

  @override
  Future<void> beforePage(String table) async {
    if (table == 'counters' || table == 'counter_values') {
      await _guard('counter flush', () async => (await _counters()).flush());
    }
  }

  @override
  Future<void> afterPage(String table, List<SyncAppliedRow> rows) async {
    final changed = [
      for (final row in rows)
        if (row.result == MergeResult.inserted ||
            row.result == MergeResult.applied)
          row,
    ];
    if (changed.isEmpty) return;
    final ids = [for (final row in changed) row.rowKey];
    final inserted = {
      for (final row in changed)
        if (row.result == MergeResult.inserted) row.rowKey,
    };
    switch (table) {
      case 'notes':
        await _guard(
          'note changes',
          () => _notes().announceMerged(ids, inserted: inserted),
        );
      case 'folders':
        await _guard(
          'folder changes',
          () => _folders().announceMerged(ids, inserted: inserted),
        );
    }
  }

  @override
  Future<void> afterRun(Set<SyncInvalidation> touched) async {
    if (touched.contains(SyncInvalidation.notes)) {
      await _guard('note cache', () async => _notes().invalidateAll());
    }
    if (touched.contains(SyncInvalidation.folders)) {
      await _guard('folder cache', () async => _folders().invalidateAll());
    }
    if (touched.contains(SyncInvalidation.calendar)) {
      await _guard('calendar reload', _reloadCalendar);
    } else if (touched.contains(SyncInvalidation.alerts)) {
      // The calendar reload already re-read the alert services.
      await _guard('alert reload', _reloadAlerts);
    }
    if (touched.contains(SyncInvalidation.calendar) ||
        touched.contains(SyncInvalidation.alerts)) {
      await _guard('alert reconcile', _reconcileAlerts);
    }
    if (touched.contains(SyncInvalidation.counters)) {
      // reload() fires CounterService.changes, which the counter blocs follow.
      await _guard('counter reload', () async => (await _counters()).reload());
    }
    if (touched.contains(SyncInvalidation.vocabularies)) {
      await _guard('vocabulary reload', _reloadVocabularies);
    }
  }

  /// Files the losing text as a new note through the storage service, which
  /// stamps and queues it like any local note, so the other devices receive
  /// it too. It keeps the loser's folder and label and takes the folder's
  /// next free position — the storage path's own placement — under a title
  /// that names it a conflict copy, suffixed ` (n)` should a copy filed the
  /// same minute already hold it.
  ///
  /// Safe inside the page's transaction, so a copy that fails can roll the
  /// page back: it only reads and writes this database (the language from
  /// the settings table, the title check, the insert — drift nests the
  /// insert as a savepoint) and touches no UI; the repository caches it
  /// fills are dropped by [afterRun]'s invalidation either way. Unguarded,
  /// unlike the cache effects: a failure must reach the engine, or the
  /// losing text would be gone without a trace.
  @override
  Future<void> fileConflictCopy(SyncNoteConflict conflict) async {
    final loser = conflict.loser;
    final storage = _noteStorage();
    final base = (await _strings()).syncConflictCopyTitle(loser.title, _now());
    var title = base;
    for (var n = 2;
        await storage.noteTitleExistsInFolder(
          folderId: loser.folderId,
          title: title,
        );
        n++) {
      title = '$base ($n)';
    }
    await storage.createNote(
      folderId: loser.folderId,
      title: title,
      content: conflict.loserContent,
      label: ItemLabel.fromStorage(loser.label),
    );
  }

  Future<void> _guard(String what, Future<void> Function() effect) async {
    try {
      await effect();
    } catch (error, stack) {
      debugPrint('[AppSyncApplyHooks] $what failed: $error\n$stack');
    }
  }

  /// The calendar services in the record's order — categories and templates
  /// before the events that name them, the day rows after — each on its own
  /// guard, then the signal a bloc already showing the calendar reloads on.
  static Future<void> _appReloadCalendar() async {
    final reloads = <String, Future<void> Function()>{
      'categories': () async => (await CategoryService.getInstance()).reload(),
      'templates': () async =>
          (await EventTemplateService.getInstance()).reload(),
      'events': () async => (await CalendarEventService.getInstance()).reload(),
      'occurrences': () async =>
          (await EventOccurrenceService.getInstance()).reload(),
      'presence': () async =>
          (await EventPresenceService.getInstance()).reload(),
      'skips': () async => (await EventSkipService.getInstance()).reload(),
      'alerts': () async => (await EventAlertService.getInstance()).reload(),
      'digests': () async => (await EventDigestService.getInstance()).reload(),
      'filter presets': () async =>
          (await FilterPresetService.getInstance()).reload(),
      'overview views': () async =>
          (await OverviewViewService.getInstance()).reload(),
    };
    await _reloadEach(reloads);
    CalendarEventService.notifyExternalChange();
  }

  static Future<void> _appReloadAlerts() => _reloadEach({
    'alerts': () async => (await EventAlertService.getInstance()).reload(),
    'digests': () async => (await EventDigestService.getInstance()).reload(),
  });

  static Future<void> _reloadEach(
    Map<String, Future<void> Function()> reloads,
  ) async {
    for (final MapEntry(key: what, value: reload) in reloads.entries) {
      try {
        await reload();
      } catch (error) {
        debugPrint('[AppSyncApplyHooks] $what reload failed: $error');
      }
    }
  }

  static Future<void> _appReconcileAlerts() async {
    final scheduler = await AlertScheduler.getInstance();
    await scheduler.reconcileAll(AlertReconcileReason.sync);
  }

  static Future<void> _appReloadVocabularies() async =>
      (await VocabularyService.getInstance()).reload();

  /// The app's stored language, else the device's when it is one of ours,
  /// else English — the `alertGatewayStrings` shape, for a surface with no
  /// `BuildContext`.
  static Future<AppLocalizations> _appStrings() async {
    String? stored;
    try {
      stored = await (await SettingsService.getInstance()).getLocaleCode();
    } catch (error) {
      debugPrint('[AppSyncApplyHooks] stored language not read: $error');
    }
    for (final code in [
      stored,
      PlatformDispatcher.instance.locale.languageCode,
    ]) {
      if (code == null) continue;
      final supported = AppLocalizations.supportedLocales.any(
        (locale) => locale.languageCode == code,
      );
      if (supported) return lookupAppLocalizations(Locale(code));
    }
    return lookupAppLocalizations(const Locale('en'));
  }
}
