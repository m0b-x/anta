import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:get_it/get_it.dart';

import '../../l10n/app_localizations.dart';
import '../../models/item_label.dart';
import '../../repositories/folder_repository.dart';
import '../../repositories/note_repository.dart';
import '../alert_scheduler.dart';
import '../calendar_event_service.dart';
import '../category_profile_service.dart';
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
import 'conflict_copy_title.dart';
import 'open_note_registry.dart';
import 'sync_apply_hooks.dart';
import 'sync_table_binding.dart';

/// What one run merged into the calendar's tables, as [AppSyncApplyHooks]
/// heard it page by page: the tables whose rows changed — null when no page
/// was heard, and the reload then runs whole, as it did before it knew — and
/// the ids of the `calendar_events` rows among them.
typedef CalendarPullScope = ({Set<String>? tables, Set<String> eventIds});

/// The production [SyncApplyHooks]: what a pulled page does to the caches,
/// the change streams, the calendar, the alert planner and the counters
/// (record §3.5).
///
/// Every target is resolved per call, never held: the database-bound
/// singletons are rebuilt after a database switch, and an instance kept here
/// would answer for the closed one. Each cache effect runs on its own guard,
/// so one failing service — the alert scheduler on a build without a
/// gateway — is logged and the others still run; the conflict copy and the
/// language it is titled in do not.
class AppSyncApplyHooks implements SyncApplyHooks {
  final NoteRepository Function() _notes;
  final FolderRepository Function() _folders;
  final NoteStorageService Function() _noteStorage;
  final Future<CounterService> Function() _counters;
  final Future<void> Function(CalendarPullScope scope) _reloadCalendar;
  final Future<void> Function() _reloadAlerts;
  final Future<void> Function() _reconcileAlerts;
  final Future<bool> Function() _reportDigestEnabled;
  final Future<void> Function() _reloadVocabularies;
  final Future<void> Function() _refreshShareMarks;
  final Future<AppLocalizations> Function() _strings;
  final bool Function(String noteId) _editorClaimsFiling;
  final DateTime Function() _now;

  /// The strings a copy filed by this page would take, resolved in
  /// [beforePage] — outside the page's transaction, which is the only place
  /// a database-bound singleton may be reached from (R104) — and cleared in
  /// [afterPage], and again at every page's [beforePage]: a notes page that
  /// halted or threw never reaches [afterPage] (review X-14). Null only
  /// outside a notes page: a resolve that fails there fails the page.
  AppLocalizations? _pageStrings;

  /// The tables this run's pages changed rows in, and the event ids among
  /// them, gathered by [afterPage] and spent and cleared by [afterRun]: the
  /// calendar reloads what the run touched, never the whole calendar for one
  /// row (scalability record §5.6, S14).
  final Set<String> _runTables = {};
  final Set<String> _runEventIds = {};

  /// The table whose [beforePage] has not had its [afterPage] yet. Only a page
  /// announced in such a pair is gathered: the puller's re-filed notes come
  /// with no [beforePage] of their own — after the run was told, or after a
  /// run that changed nothing and so was never told at all — and belong to
  /// no run, so they never widen the next one.
  String? _openPage;

  /// The defaults are the app's own targets; a test passes its in-memory
  /// repositories and recorders in their place.
  AppSyncApplyHooks({
    NoteRepository Function()? notes,
    FolderRepository Function()? folders,
    NoteStorageService Function()? noteStorage,
    Future<CounterService> Function()? counters,
    Future<void> Function(CalendarPullScope scope)? reloadCalendar,
    Future<void> Function()? reloadAlerts,
    Future<void> Function()? reconcileAlerts,
    Future<bool> Function()? reportDigestEnabled,
    Future<void> Function()? reloadVocabularies,
    Future<void> Function()? refreshShareMarks,
    Future<AppLocalizations> Function()? strings,
    bool Function(String noteId)? editorClaimsFiling,
    DateTime Function()? now,
  }) : _notes = notes ?? GetIt.I.get<NoteRepository>,
       _folders = folders ?? GetIt.I.get<FolderRepository>,
       _noteStorage = noteStorage ?? GetIt.I.get<NoteStorageService>,
       _counters = counters ?? CounterService.getInstance,
       _reloadCalendar = reloadCalendar ?? _appReloadCalendar,
       _reloadAlerts = reloadAlerts ?? _appReloadAlerts,
       _reconcileAlerts = reconcileAlerts ?? _appReconcileAlerts,
       _reportDigestEnabled = reportDigestEnabled ?? _appReportDigestEnabled,
       _reloadVocabularies = reloadVocabularies ?? _appReloadVocabularies,
       _refreshShareMarks = refreshShareMarks ?? _appRefreshShareMarks,
       _strings = strings ?? _appStrings,
       _editorClaimsFiling =
           editorClaimsFiling ?? OpenNoteRegistry.claimsConflictFiling,
       _now = now ?? DateTime.now;

  @override
  Future<void> beforePage(String table) async {
    _pageStrings = null;
    _openPage = table;
    if (table == 'counters' || table == 'counter_values') {
      await _guard('counter flush', () async => (await _counters()).flush());
    }
    if (table == 'notes') {
      // Unguarded, unlike the cache effects: a language that cannot be read
      // must fail the page here, before its transaction opens, or
      // [fileConflictCopy] would reach a database-bound singleton from
      // inside it — the read R104 exists to move out (A7 review R139). The
      // page is merged again on the next run, so nothing is lost.
      _pageStrings = await _strings();
    }
  }

  @override
  Future<void> afterPage(String table, List<SyncAppliedRow> rows) async {
    // The page is over, and so is what its language was resolved for: a
    // locale changed since would otherwise be served from here until the
    // next notes page (A7 review R147).
    if (table == 'notes') _pageStrings = null;
    final paired = _openPage == table;
    _openPage = null;
    final changed = [
      for (final row in rows)
        if (row.result == MergeResult.inserted ||
            row.result == MergeResult.applied)
          row,
    ];
    if (changed.isEmpty) return;
    if (paired) {
      _runTables.add(table);
      if (table == _eventsTable) {
        _runEventIds.addAll([for (final row in changed) row.rowKey]);
      }
    }
    // Rows that are gone outright cannot be re-read for where they stood,
    // which is how the announcements below place a change: they are told
    // apart, with the parent their removal recorded.
    final gone = {
      for (final row in changed)
        if (row.gone) row.rowKey: row.previousParent,
    };
    if (gone.isNotEmpty) {
      switch (table) {
        case 'notes':
          await _guard(
            'note removals',
            () async => _notes().announceRemoved({
              for (final MapEntry(key: id, value: folder) in gone.entries)
                id: ?folder,
            }),
          );
        case 'folders':
          await _guard(
            'folder removals',
            () async => _folders().announceRemoved(gone),
          );
      }
      changed.removeWhere((row) => row.gone);
      if (changed.isEmpty) return;
    }
    final ids = [for (final row in changed) row.rowKey];
    final inserted = {
      for (final row in changed)
        if (row.result == MergeResult.inserted) row.rowKey,
    };
    final previousParents = {
      for (final row in changed)
        if (row.moved) row.rowKey: row.previousParent,
    };
    switch (table) {
      case 'notes':
        await _guard(
          'note changes',
          () => _notes().announceMerged(
            ids,
            inserted: inserted,
            previousParents: {
              for (final MapEntry(key: id, value: folder)
                  in previousParents.entries)
                id: ?folder,
            },
            bodies: {for (final row in changed) row.rowKey: ?row.content},
          ),
        );
      case 'folders':
        await _guard(
          'folder changes',
          () => _folders().announceMerged(
            ids,
            inserted: inserted,
            previousParents: previousParents,
          ),
        );
      case 'counters' || 'counter_values':
        // Right after the page, not at the end of the run: a tap between the
        // two was flushed over the merged count (S3c review H1). reload()
        // keeps the taps still pending and fires CounterService.changes,
        // which the counter blocs follow.
        await _guard(
          'counter reload',
          () async => (await _counters()).reload(),
        );
    }
  }

  @override
  Future<void> afterRun(Set<SyncInvalidation> touched) async {
    // Spent here, so the next run gathers from its own pages; a page
    // announced after this one without its own `beforePage` (the re-filed
    // notes) is gathered by none.
    final CalendarPullScope scope = (
      tables: _runTables.isEmpty ? null : Set.unmodifiable(_runTables),
      eventIds: Set.unmodifiable(_runEventIds),
    );
    _runTables.clear();
    _runEventIds.clear();
    _openPage = null;
    if (touched.contains(SyncInvalidation.notes)) {
      await _guard('note cache', () async => _notes().invalidateAll());
    }
    if (touched.contains(SyncInvalidation.folders)) {
      await _guard('folder cache', () async => _folders().invalidateAll());
    }
    // Before the calendar reload, whose signal tells the bloc the event
    // cache is current: the reload patches only the rows the pages named.
    if (touched.contains(SyncInvalidation.shareMarks)) {
      await _guard('share marks', _refreshShareMarks);
    }
    if (touched.contains(SyncInvalidation.calendar)) {
      await _guard('calendar reload', () => _reloadCalendar(scope));
    } else if (touched.contains(SyncInvalidation.alerts)) {
      // The calendar reload already re-read the alert services.
      await _guard('alert reload', _reloadAlerts);
    }
    if ((touched.contains(SyncInvalidation.calendar) ||
            touched.contains(SyncInvalidation.alerts)) &&
        await _replans(scope.tables)) {
      await _guard('alert reconcile', _reconcileAlerts);
    }
    // The counters reloaded after their own pages; the values of notes a pull
    // deleted are swept by the puller after a complete pull, not here.
    if (touched.contains(SyncInvalidation.vocabularies)) {
      await _guard('vocabulary reload', _reloadVocabularies);
    }
  }

  /// Whether this run's rows can change what the alert planner arms: every
  /// calendar row can, except a presence mark and a category's profile, which
  /// only a report digest's words read — those re-plan under
  /// `AlertScheduler.reportDigestEnabled`, the rule the scheduler and a local
  /// mark apply. A run whose tables are unknown re-plans, as every run did.
  /// An answer that cannot be read re-plans too: a pass too many costs time,
  /// a pass too few a stale digest.
  Future<bool> _replans(Set<String>? tables) async {
    if (tables == null || !tables.every(_reportOnlyTables.contains)) {
      return true;
    }
    try {
      return await _reportDigestEnabled();
    } catch (error, stack) {
      debugPrint('[AppSyncApplyHooks] digest check failed: $error\n$stack');
      return true;
    }
  }

  /// Files the losing text as a new note through
  /// `NoteRepository.createMergedCopy`, which stamps and queues it like any
  /// local note, so the other devices receive it too, but caches and
  /// announces nothing: the engine announces the returned id after the page
  /// committed. It keeps the loser's folder and label and takes the folder's
  /// next free position under D3's title ([conflictCopyTitle]). A folder
  /// deleted meanwhile — the same pull may have tombstoned it — would hide
  /// the copy with it, so the copy goes to the nearest live ancestor, else
  /// the root (`folderId` empty, the wire's own default).
  ///
  /// Files nothing when an open editor claims the copy ([OpenNoteRegistry]):
  /// that page files the *arriving* body as the copy and its next save puts
  /// the live text back on the row, so one conflict leaves the one copy D3
  /// promises rather than two — this one would hold an intermediate autosave
  /// the live text supersedes (record §3.9, R99). A claim, not a question
  /// about the page's state: this runs inside the merge's transaction and
  /// the editor acts only once it committed, so an answer re-derived there
  /// could differ from the one acted on here (A7 review R129).
  ///
  /// An [SyncNoteConflict.incoming] copy is never asked about: the merge kept
  /// the local row, so an open page hears of no change to its note and its
  /// text stays; the text that lost is one it never showed, and the copy
  /// reaches it as any other inserted note. Asking would latch a claim the
  /// page then files on with nothing to file (scalability record S8).
  ///
  /// Safe inside the page's transaction, so a copy that fails can roll the
  /// page back: it only reads and writes this database (the folders, the
  /// title check, the insert — drift nests the insert as a savepoint) and
  /// touches no UI; the language was resolved in [beforePage], outside it.
  /// Unguarded, unlike the cache effects: a failure must reach the engine,
  /// or the losing text would be gone without a trace.
  @override
  Future<String?> fileConflictCopy(SyncNoteConflict conflict) async {
    final loser = conflict.loser;
    if (!conflict.incoming && _editorClaimsFiling(loser.id)) return null;
    final storage = _noteStorage();
    // Past the cache: a folder merged as deleted earlier in this run is still
    // cached as live until [afterRun], and this read runs inside the page's
    // transaction, so it must not cache what it reads either.
    final folderId = await _folders().nearestLiveFolderId(loser.folderId);
    // [beforePage] resolved them; the fallback is the call that came without
    // a page at all, never one inside this transaction (R139).
    final strings = _pageStrings ?? await _strings();
    final now = _now();
    var title = conflictCopyTitle(strings, loser.title, now);
    for (
      var n = 2;
      await storage.noteTitleExistsInFolder(folderId: folderId, title: title);
      n++
    ) {
      title = conflictCopyTitle(strings, loser.title, now, copy: n);
    }
    final copy = await _notes().createMergedCopy(
      folderId: folderId,
      title: title,
      content: conflict.loserContent,
      label: ItemLabel.fromStorage(loser.label),
    );
    return copy.id;
  }

  Future<void> _guard(String what, Future<void> Function() effect) async {
    try {
      await effect();
    } catch (error, stack) {
      debugPrint('[AppSyncApplyHooks] $what failed: $error\n$stack');
    }
  }

  static const _eventsTable = 'calendar_events';

  /// The two tables whose rows arm nothing (see [_replans]).
  static const _reportOnlyTables = {
    'calendar_event_absences',
    'calendar_category_profiles',
  };

  /// Every table the calendar reload has a service for.
  static const _calendarTables = {
    'calendar_categories',
    'calendar_category_profiles',
    'calendar_event_templates',
    _eventsTable,
    'calendar_event_occurrences',
    'calendar_event_absences',
    'calendar_event_skips',
    'calendar_event_alerts',
    'calendar_category_alerts',
    'event_digests',
    'calendar_filter_presets',
    'overview_views',
  };

  /// The tables of the other cache classes, which the calendar reload has no
  /// service for. A table in neither set is one added since, and the reload
  /// runs whole rather than miss it.
  static const _otherTables = {
    'notes',
    'folders',
    'counters',
    'counter_values',
    'vocabularies',
    'vocabulary_items',
  };

  /// The calendar services whose tables the run touched, in the record's
  /// order — categories and templates before the events that name them, the
  /// day rows after — each on its own guard, then the signal a bloc already
  /// showing the calendar reloads on, announced `cacheCurrent` when the
  /// events step left the event cache current, so the bloc does not read the
  /// store a second time.
  ///
  /// Categories reload on every calendar run: the reload seeds the built-in
  /// categories, the only path that seeds them after a bind. The events step
  /// patches the merged ids into a loaded cache
  /// ([CalendarEventService.applyMerged]). The profiles, templates, filter
  /// presets and overview views reload only a live instance: nothing has
  /// read them otherwise, and the next `getInstance` reads the merged table.
  /// A run whose tables are unknown, or that holds a table neither set
  /// names, reloads every service and the whole event cache, as every run
  /// did before the hooks knew.
  static Future<void> _appReloadCalendar(CalendarPullScope scope) async {
    final heard = scope.tables;
    final tables =
        heard != null &&
            heard.every(
              (t) => _calendarTables.contains(t) || _otherTables.contains(t),
            )
        ? heard
        : null;
    bool touched(String table) => tables == null || tables.contains(table);
    var eventsCurrent = true;
    await _reloadEach({
      'categories': () async => (await CategoryService.getInstance()).reload(),
      if (touched('calendar_category_profiles'))
        'profiles': CategoryProfileService.refreshAfterSync,
      if (touched('calendar_event_templates'))
        'templates': EventTemplateService.refreshAfterSync,
      if (touched(_eventsTable))
        'events': () async {
          eventsCurrent = false;
          eventsCurrent = tables == null
              ? await CalendarEventService.refreshAfterSync()
              : await CalendarEventService.applyMerged(scope.eventIds);
        },
      if (touched('calendar_event_occurrences'))
        'occurrences': () async =>
            (await EventOccurrenceService.getInstance()).reload(),
      if (touched('calendar_event_absences'))
        'presence': () async =>
            (await EventPresenceService.getInstance()).reload(),
      if (touched('calendar_event_skips'))
        'skips': () async => (await EventSkipService.getInstance()).reload(),
      if (touched('calendar_event_alerts') ||
          touched('calendar_category_alerts'))
        'alerts': () async => (await EventAlertService.getInstance()).reload(),
      if (touched('event_digests'))
        'digests': () async =>
            (await EventDigestService.getInstance()).reload(),
      if (touched('calendar_filter_presets'))
        'filter presets': FilterPresetService.refreshAfterSync,
      if (touched('overview_views'))
        'overview views': OverviewViewService.refreshAfterSync,
    });
    CalendarEventService.notifyExternalChange(
      cacheCurrent: eventsCurrent,
      eventsMerged: touched(_eventsTable),
    );
  }

  /// The two alert services, then the same signal the calendar reload ends
  /// on: an alerts-only pull arms new alerts, and an open calendar page or
  /// Alerts hub would otherwise keep the badges it was built with until an
  /// unrelated change forced an emit — the phone ringing for something the
  /// screen does not show (R78). The event cache is untouched by an alert
  /// row, so the signal vouches for it.
  static Future<void> _appReloadAlerts() async {
    await _reloadEach({
      'alerts': () async => (await EventAlertService.getInstance()).reload(),
      'digests': () async => (await EventDigestService.getInstance()).reload(),
    });
    CalendarEventService.notifyExternalChange(cacheCurrent: true);
  }

  /// [AlertScheduler.reportDigestEnabled] over a loaded digest facade: the
  /// digests are read once and stay published, so this is a facade read on
  /// every run after the first.
  static Future<bool> _appReportDigestEnabled() async {
    await EventDigestService.getInstance();
    return AlertScheduler.reportDigestEnabled;
  }

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

  /// The two caches that hold a share mark of the person's own rows; each
  /// refreshes only a live instance, so a calendar nobody opened stays
  /// unread.
  static Future<void> _appRefreshShareMarks() => _reloadEach({
    'category marks': CategoryService.refreshShareMarks,
    'event marks': CalendarEventService.refreshShareMarks,
  });

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
