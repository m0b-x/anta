import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:stream_transform/stream_transform.dart';

import '../constants/calendar_categories.dart';
import '../database/crdt/synced_tables.dart';
import '../database/daos/sync_dao.dart';
import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../models/app_user.dart';
import '../models/calendar_category.dart';
import '../models/calendar_event.dart';
import '../models/share_notice.dart';
import '../models/share_overview.dart';
import '../models/share_settings.dart';
import '../models/sync_binding.dart';
import 'alert_scheduler.dart';
import 'calendar_event_service.dart';
import 'category_service.dart';
import 'pairing_service.dart';
import 'settings_service.dart';
import 'sync/sync_status.dart';

/// Who a share goes to: today the one partner of this database's pair
/// (`docs/cloud-share-surfaces-roadmap.md` §14). A surface names it and
/// draws its members, and never holds the pair behind it: the writes take
/// the pair from the pairing themselves.
class ShareAudience extends Equatable {
  /// Opaque to every surface; the pair's id today.
  final String id;

  /// The name the audience goes by, or null when nobody published one —
  /// the surface then says "your partner".
  final String? displayName;

  /// The people in it, for their avatars.
  final List<AppUser> members;

  const ShareAudience({
    required this.id,
    required this.displayName,
    required this.members,
  });

  @override
  List<Object?> get props => [id, displayName, members];
}

/// Whether this database can share now, and with whom (§6.1).
sealed class ShareAvailability extends Equatable {
  const ShareAvailability();

  /// The audience a share would go to; null while not paired.
  ShareAudience? get audience => null;
}

/// No pair: nothing to share with, and nothing was asked of the network or
/// the sync settings to say so.
final class ShareNotPaired extends ShareAvailability {
  const ShareNotPaired();

  @override
  List<Object?> get props => const [];
}

/// Paired, but this database does not sync with the signed-in account's
/// space, so a share would never leave the phone.
final class ShareNotSyncing extends ShareAvailability {
  @override
  final ShareAudience audience;

  const ShareNotSyncing(this.audience);

  @override
  List<Object?> get props => [audience];
}

/// Paired and syncing: a share leaves with the next push.
final class ShareReady extends ShareAvailability {
  @override
  final ShareAudience audience;

  const ShareReady(this.audience);

  @override
  List<Object?> get props => [audience];
}

/// A share write asked for while [availability] was not [ShareReady]: a
/// surface offers the switch only when it is, so this is a race the caller
/// words, never a write that silently did nothing.
class ShareRefused implements Exception {
  final ShareAvailability availability;

  const ShareRefused(this.availability);

  @override
  String toString() => 'ShareRefused(${availability.runtimeType})';
}

/// Whether the open database syncs with the signed-in account's space — a
/// seam, so the service's suite decides the answer and the engine stays out
/// of it.
abstract interface class ShareSyncSource {
  /// Local only: the stored binding against the signed-in account.
  Future<bool> syncing();

  /// Fires whenever [syncing] may have changed: a sign-in or out, a bind or
  /// an unbind.
  Stream<void> get changes;

  /// Whether the engine's last call found no network — a share then waits
  /// to send. Local: the engine's own record, never a probe.
  Future<bool> offline();

  /// Fires as each sync run of the open database ends — after its drain
  /// has sent a share, or its read has brought the partner's rows — so an
  /// open Sharing page reads its overview again.
  Stream<void> get runsEnded;
}

/// [ShareSyncSource] over the stored binding and the identity: bound to the
/// account signed in now, which is what the engine itself checks before a
/// run ([SyncPause.forAccount]).
class BindingShareSyncSource implements ShareSyncSource {
  final AppUser? Function() _currentUser;
  final Stream<AppUser?> _authChanges;
  final Future<SyncBinding?> Function() _binding;

  /// A fresh stream per listen: each database's service follows the engine
  /// of its own database.
  final Stream<Object?> Function() _bindingChanges;
  final Future<bool> Function() _offline;

  /// The engine's activity as it publishes it, a fresh stream per listen
  /// like [_bindingChanges].
  final Stream<SyncActivity> Function() _activity;

  BindingShareSyncSource({
    required AppUser? Function() currentUser,
    required Stream<AppUser?> authChanges,
    required Future<SyncBinding?> Function() binding,
    required Stream<Object?> Function() bindingChanges,
    required Future<bool> Function() offline,
    required Stream<SyncActivity> Function() activity,
  }) : _currentUser = currentUser,
       _authChanges = authChanges,
       _binding = binding,
       _bindingChanges = bindingChanges,
       _offline = offline,
       _activity = activity;

  @override
  Future<bool> offline() => _offline();

  /// A run ends where the activity goes back to idle: the engine publishes
  /// idle at the end of every run, and an idle status emitted between runs
  /// — an outbox count, a pause — ends none.
  @override
  Stream<void> get runsEnded {
    var running = false;
    return _activity().where((activity) {
      final ended = running && activity == SyncActivity.idle;
      running = activity != SyncActivity.idle;
      return ended;
    });
  }

  @override
  Future<bool> syncing() async {
    final uid = _currentUser()?.uid;
    if (uid == null) return false;
    final binding = await _binding();
    return binding != null &&
        SyncPause.forAccount(binding, uid) == SyncPause.none;
  }

  @override
  Stream<void> get changes =>
      _authChanges.map<Object?>((user) => user?.uid).merge(_bindingChanges());
}

/// What the app's [ShareService] is built over, handed in once by
/// `configureDependencies`: the global pieces a database switch leaves
/// standing.
class ShareServiceWiring {
  final Future<PairingService> Function() pairing;
  final ShareSyncSource sync;

  /// `FolderStorageService.invalidateCache`: the folder writer is the DAO's,
  /// which holds no cache, and a mark set on a category or an event clears
  /// another pair's on folders — both behind the folder cache.
  final void Function() foldersChanged;

  /// Asks the engine for the run that sends a share now; nothing where
  /// sync does not run.
  final Future<void> Function() requestRun;

  /// Asks the engine for the read of what the partner shares alone — no
  /// pull, no push; nothing where sync does not run. Completes when that
  /// run has ended, which is when the Sharing page reads again.
  final Future<void> Function() requestSharedRead;

  const ShareServiceWiring({
    required this.pairing,
    required this.sync,
    required this.foldersChanged,
    required this.requestRun,
    required this.requestSharedRead,
  });
}

/// The one facade over sharing (`docs/cloud-share-surfaces-roadmap.md`
/// §6.1): whether this database can share and with whom, the only writer of
/// a share's mark outside tests and the QA seam, whether a row is the
/// partner's, and the receiver's settings.
///
/// Pairing and the sync binding are per database, so this is on the
/// [DatabaseLifecycle] reset contract. Built only when a surface asks, and
/// an account that never paired costs nothing more once built: the pairing
/// it reads is the cached one, and the binding is read only while paired.
class ShareService {
  static ShareService? _instance;
  static Future<ShareService>? _opening;
  static ShareServiceWiring? _wiring;

  /// Which opening of the database is the current one
  /// ([DatabaseLifecycle.generation]). A surface that offers an Undo keeps
  /// the value it was offered under and drops an Undo tapped under another:
  /// built-in category ids are the same in every database, so the write
  /// would land in one that never saw the act. Read here so that no page
  /// reaches for the database layer to learn it.
  static int get databaseGeneration => DatabaseLifecycle.generation;

  /// How old the last completed shared read must be before the Sharing
  /// page's open asks for another: each read costs a dozen server reads,
  /// and a page opened, left and opened again learns nothing new sooner.
  static const Duration sharedReadMinAge = Duration(minutes: 1);

  static final StreamController<ShareNotice> _notices =
      StreamController<ShareNotice>.broadcast();

  /// What a read of the partner's shares changed that a person is told
  /// about (§6.14) — heard by the app's one listener, which says it in the
  /// app. Static, like `CalendarEventService.externalChanges`: the listener
  /// subscribes at start without building this service, so an account that
  /// never paired pays one idle subscription and nothing else.
  static Stream<ShareNotice> get notices => _notices.stream;

  /// Hands [notice] to whoever listens; with nobody listening it is
  /// dropped — a notice is said once or not at all, never kept for later.
  static void notify(ShareNotice notice) => _notices.add(notice);

  final PairingService _pairing;
  final ShareSyncSource _sync;
  final AppDatabase _db;
  final SettingsService _settings;
  final Future<bool> Function(String eventId, String? pairId) _markEvent;
  final Future<bool> Function(String categoryId, String? pairId) _markCategory;
  final Future<bool> Function(String folderId, String? pairId) _markFolder;
  final void Function() _foldersChanged;
  final Future<void> Function() _requestRun;
  final Future<void> Function() _requestSharedRead;
  final Future<void> Function() _reconcileAlerts;

  final StreamController<ShareAvailability> _controller =
      StreamController<ShareAvailability>.broadcast();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  ShareAvailability _availability = const ShareNotPaired();

  /// Evaluations started, so one that lands after a newer one is dropped.
  int _evaluations = 0;

  /// The evaluation [_availability] was taken from.
  int _landed = 0;

  /// The hidden-set writes in order, each reading what the one before it
  /// wrote: two switches flipped in a row must both hold.
  Future<void> _hiddenWrites = Future.value();

  ShareService._({
    required PairingService pairing,
    required ShareSyncSource sync,
    required AppDatabase db,
    required SettingsService settings,
    required Future<bool> Function(String eventId, String? pairId) markEvent,
    required Future<bool> Function(String categoryId, String? pairId)
    markCategory,
    required Future<bool> Function(String folderId, String? pairId) markFolder,
    required void Function() foldersChanged,
    required Future<void> Function() requestRun,
    required Future<void> Function() requestSharedRead,
    required Future<void> Function() reconcileAlerts,
  }) : _pairing = pairing,
       _sync = sync,
       _db = db,
       _settings = settings,
       _markEvent = markEvent,
       _markCategory = markCategory,
       _markFolder = markFolder,
       _foldersChanged = foldersChanged,
       _requestRun = requestRun,
       _requestSharedRead = requestSharedRead,
       _reconcileAlerts = reconcileAlerts;

  /// The category writer in the app: the DAO's, so the marks of one act
  /// share its transaction ([_act]). The catalogue's own chain could not
  /// hold that transaction — a link queued ahead of it waiting on the
  /// database would wait on the transaction itself — so the catalogue reads
  /// the marks again on its chain once the act has ended ([_afterMarks]).
  static Future<bool> Function(String, String?) _markCategoryIn(
    AppDatabase db,
  ) => db.calendarCategoryDao.setSharedPair;

  /// Hands the service what it is built over; `configureDependencies` calls
  /// it once, `resetDependencies` with null.
  static void configure(ShareServiceWiring? wiring) => _wiring = wiring;

  /// The service over the active database. Published only once whole, and
  /// started over when a database switch lands during the build, the
  /// `SettingsService.getInstance` shape.
  static Future<ShareService> getInstance() {
    final existing = _instance;
    if (existing != null) return Future.value(existing);
    final inFlight = _opening;
    if (inFlight != null) return inFlight;
    final opening = _open();
    _opening = opening;
    void settle() {
      if (identical(_opening, opening)) _opening = null;
    }

    opening.then<void>((_) => settle(), onError: (Object _) => settle());
    return opening;
  }

  static Future<ShareService> _open() async {
    final wiring = _wiring;
    if (wiring == null) throw StateError('ShareService is not configured');
    for (var attempt = 0; attempt < 2; attempt++) {
      final generation = DatabaseLifecycle.generation;
      final db = await AppDatabase.getInstance();
      final settings = await SettingsService.getInstance();
      final pairing = await wiring.pairing();
      final raced = _instance;
      if (raced != null) return raced;
      if (DatabaseLifecycle.generation != generation) continue;
      final service = ShareService._(
        pairing: pairing,
        sync: wiring.sync,
        db: db,
        settings: settings,
        // The DAO's, as the category's ([_markCategoryIn]); the cached
        // events and folders read the marks again after the act.
        markEvent: db.calendarEventDao.setSharedPair,
        markCategory: _markCategoryIn(db),
        markFolder: db.folderDao.setSharedPair,
        foldersChanged: wiring.foldersChanged,
        requestRun: wiring.requestRun,
        requestSharedRead: wiring.requestSharedRead,
        reconcileAlerts: () => AlertScheduler.reconcileAllQuietly(
          AlertReconcileReason.eventChanged,
        ),
      );
      await service._start();
      if (DatabaseLifecycle.generation != generation) {
        service._dispose();
        continue;
      }
      // A reset lets go of this open, so another one of this generation may
      // have published while this one evaluated: the first published stays,
      // and this one is disposed rather than left listening unowned.
      final published = _instance;
      if (published != null) {
        service._dispose();
        return published;
      }
      _instance = service;
      DatabaseLifecycle.registerResetHandler(reset);
      return service;
    }
    throw StateError('the database switched while sharing was opened');
  }

  /// A service over [db] and the given sources, registered as the singleton
  /// so the code under test reaches it through [getInstance]. The catalogue
  /// and the events are the services' own (`CategoryService.forTesting`,
  /// `CalendarEventService.forTesting` over the same [db]); [markCategory]
  /// and [markFolder] default to the app's writers.
  @visibleForTesting
  static Future<ShareService> forTesting({
    required AppDatabase db,
    required SettingsService settings,
    required PairingService pairing,
    required ShareSyncSource sync,
    required Future<bool> Function(String eventId, String? pairId) markEvent,
    Future<bool> Function(String folderId, String? pairId)? markFolder,
    Future<bool> Function(String categoryId, String? pairId)? markCategory,
    void Function()? foldersChanged,
    Future<void> Function()? requestRun,
    Future<void> Function()? requestSharedRead,
    Future<void> Function()? reconcileAlerts,
  }) async {
    final existing = _instance;
    if (existing != null) return existing;
    final service = ShareService._(
      pairing: pairing,
      sync: sync,
      db: db,
      settings: settings,
      markEvent: markEvent,
      markCategory: markCategory ?? _markCategoryIn(db),
      markFolder: markFolder ?? db.folderDao.setSharedPair,
      foldersChanged: foldersChanged ?? () {},
      requestRun: requestRun ?? () async {},
      requestSharedRead: requestSharedRead ?? () async {},
      reconcileAlerts: reconcileAlerts ?? () async {},
    );
    await service._start();
    _instance = service;
    DatabaseLifecycle.registerResetHandler(reset);
    return service;
  }

  /// Drops the singleton and its subscriptions: the pair and the binding it
  /// followed belong to the closed database.
  static void reset() {
    _publishedLook = null;
    _instance?._dispose();
    _instance = null;
    _opening = null;
  }

  Future<void> _start() async {
    // A source that fails says nothing new; the last value stands, and the
    // next write reads afresh anyway.
    void logged(Object e, StackTrace st) =>
        debugPrint('[ShareService] a source failed: $e\n$st');
    // Attached before the first evaluation, so a change heard while it runs
    // is not missed; that change's evaluation is newer, and the first one
    // never overwrites what a newer one already published.
    _subscriptions
      ..add(_pairing.changes.listen((_) => _reevaluate(), onError: logged))
      ..add(_pairing.written.listen((_) => _reevaluate(), onError: logged))
      ..add(_sync.changes.listen((_) => _reevaluate(), onError: logged));
    final evaluation = ++_evaluations;
    final ShareAvailability first;
    try {
      first = await _evaluate();
    } catch (_) {
      // Nobody will hold this service to dispose it.
      _dispose();
      rethrow;
    }
    if (evaluation > _landed) {
      _availability = first;
      _landed = evaluation;
    }
  }

  void _dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    unawaited(_controller.close());
  }

  /// Whether this database can share now, as last evaluated.
  ShareAvailability get availability => _availability;

  /// [availability] of the service built for the open database, or null
  /// while none is: with [publishedLook], what a page draws its first frame
  /// by without awaiting the service — the browser's partner rows.
  static ShareAvailability? get knownAvailability => _instance?._availability;

  /// [availability] and every change of it. Replays the current value to
  /// each new listener, so a surface that subscribes late never waits for a
  /// change to learn where it stands.
  Stream<ShareAvailability> get changes {
    late final StreamController<ShareAvailability> replay;
    StreamSubscription<ShareAvailability>? live;
    replay = StreamController<ShareAvailability>(
      onListen: () {
        replay.add(_availability);
        live = _controller.stream.listen(
          replay.add,
          onDone: () => unawaited(replay.close()),
        );
      },
      onCancel: () => live?.cancel(),
    );
    return replay.stream;
  }

  Future<ShareAvailability> _evaluate() async {
    final status = _pairing.status;
    final pairId = status.pairId;
    if (pairId == null || !_pairing.pairedForSignedInAccount) {
      return const ShareNotPaired();
    }
    final partner = status.partner;
    final audience = ShareAudience(
      id: pairId,
      displayName: partner?.displayName,
      members: [if (partner != null) partner.toUser()],
    );
    return await _sync.syncing()
        ? ShareReady(audience)
        : ShareNotSyncing(audience);
  }

  Future<ShareAvailability> _reevaluate() async {
    final evaluation = ++_evaluations;
    final ShareAvailability next;
    try {
      next = await _evaluate();
    } catch (e, st) {
      debugPrint('[ShareService] availability not read: $e\n$st');
      return _availability;
    }
    if (evaluation != _evaluations) return _availability;
    _landed = evaluation;
    if (next != _availability) {
      _availability = next;
      if (!_controller.isClosed) _controller.add(next);
    }
    return next;
  }

  /// Shares the event [id] singly with the audience, or takes its own mark
  /// away — it stays shared through its category when that one is. Returns
  /// what changed: [ShareChange.none] when its mark already said so.
  ///
  /// Throws [ShareRefused] unless this database is [ShareReady] now —
  /// evaluated afresh, since the pairing's own writes publish no change.
  Future<ShareChange> setEventShared(String id, bool on) async =>
      _act(await _readyPair(), events: {id: on});

  /// Shares the category [id] — every event of this person's in it, new
  /// ones too — or stops sharing it; [setEventShared]'s terms. Un-sharing
  /// says how many of its events stay shared on their own (case C10).
  Future<ShareChange> setCategoryShared(String id, bool on) async =>
      _act(await _readyPair(), categories: {id: on});

  /// The tick sheet's Done (§6.3): exactly [ids] of this person's
  /// categories shared afterwards, an empty set included. Diffed against
  /// the marks, one write per category that changes; one change returned
  /// for the one snackbar.
  Future<ShareChange> setCategoriesShared(Set<String> ids) async {
    final pairId = await _readyPair();
    await CategoryService.getInstance();
    return _act(
      pairId,
      categories: {
        for (final category in CalendarCategories.all)
          if (!category.fromPartner &&
              category.sharedByMe != ids.contains(category.id))
            category.id: ids.contains(category.id),
      },
    );
  }

  /// Writes back every mark [change] wrote — its snackbar's Undo — and
  /// returns that change in turn. The events a category's un-share left
  /// shared on their own were never written, and stay as they are. A
  /// folder's share is undone outer mark first, then each inner mark it
  /// covered, so the inner ones are not cleared again by the outer.
  Future<ShareChange> undo(ShareChange change) async => _act(
    await _readyPair(),
    categories: {
      for (final category in change.sharedCategories) category.id: false,
      for (final category in change.unsharedCategories) category.id: true,
    },
    events: {
      for (final event in change.sharedEvents) event.id: false,
      for (final event in change.unsharedEvents) event.id: true,
    },
    folders: {
      for (final folder in change.sharedFolders) folder.id: false,
      for (final folder in change.unsharedFolders) folder.id: true,
      for (final folder in change.coveredFolders) folder.id: true,
    },
  );

  /// Shares the folder [id] — everything under it, notes and folders made
  /// later too — or stops sharing it; [setEventShared]'s terms. Sharing it
  /// clears the own marks of the folders inside it, which it now covers,
  /// and names them in [ShareChange.coveredFolders] so its Undo marks them
  /// again. A folder that is gone or the partner's writes nothing, and so
  /// does one already shared, by its own mark or through an outer folder's
  /// — the surface says it is shared already.
  Future<ShareChange> setFolderShared(String id, bool on) async =>
      _act(await _readyPair(), folders: {id: on});

  /// "Stop sharing everything" (§6.2): every mark of this database cleared
  /// — categories, events and folders, tombstones too — under one stamp and
  /// queued like any edit, as one act (`FolderDao.clearSharesExcept`), then
  /// the run that sends it. What the partner shares stays. Asks nothing of
  /// the pairing, so it also ends what an old pair left behind; a database
  /// without a mark pays one statement. Returns how many marks it cleared.
  Future<int> stopAll() async {
    if (!await _db.syncDao.anyShareMark()) return 0;
    final cleared = await _db.transaction(() async {
      final cleared = await _db.folderDao.clearSharesExcept(null);
      if (cleared > 0) await _markSending();
      return cleared;
    });
    if (cleared > 0) await _afterMarks(wrote: true);
    return cleared;
  }

  /// What the Sharing page lists and says, read now (§6.1, §6.2): local
  /// reads only. [ShareOverview.empty] at once, reading nothing, while not
  /// paired — an account that never paired pays nothing for the page's
  /// summary. [withCounts] reads what only the Sharing page shows: the tick
  /// sheet's [ShareOverview.eventCounts] — a grouped count over every event
  /// — and the two folder lists, each with its notes counted; the Pairing
  /// row's summary leaves them empty and reads [ShareOverview.folderCount]
  /// alone.
  ///
  /// The folders cost nothing where nothing is shared: one statement says
  /// whether any mark stands, whether a folder of mine carries one and
  /// whether the partner shares a folder, and a list is read — one
  /// statement each, two at most; one count in a summary — only when that
  /// statement says it has rows.
  Future<ShareOverview> overview({bool withCounts = false}) async {
    if (_pairing.status.pairId == null) return ShareOverview.empty;
    await CategoryService.getInstance();
    final events = (await CalendarEventService.getInstance()).events;
    final hidden = await _settings.getShareHiddenCategories();
    final builtIns = await _db.sharedRowDao.sharedBuiltIns();
    final theirs = CalendarCategories.partner;
    final counts = theirs.isEmpty && builtIns.isEmpty
        ? const <String, int>{}
        : await _db.calendarEventDao.countPartnerByCategory();
    PartnerSharedCategory partnerOf(CalendarCategory category) =>
        PartnerSharedCategory(
          category: category,
          joinsMine: !category.fromPartner,
          shown: !hidden.contains(category.id),
          eventCount: counts[category.id] ?? 0,
        );
    final partnerCategories = [
      for (final category in theirs) partnerOf(category),
      for (final category in CalendarCategories.all)
        if (!category.fromPartner && builtIns.contains(category.id))
          partnerOf(category),
    ];
    final partnerIds = {
      for (final shared in partnerCategories) shared.category.id,
    };
    final sync = _db.syncDao;
    final okMs = int.tryParse(
      await sync.getValue(SyncDao.keySharedReadOkAt) ?? '',
    );
    // Only a failure recorded as one says "Could not check": a read a leave
    // cut records nothing, and an install from before the stamp has none.
    final failedMs = int.tryParse(
      await sync.getValue(SyncDao.keySharedReadFailedAt) ?? '',
    );
    final marks = await sync.liveShareMarks();
    final folderDao = _db.folderDao;
    final folders = withCounts && marks.myFolders
        ? [
            for (final folder in await folderDao.mySharedFolders())
              MySharedFolder(
                id: folder.id,
                name: folder.name,
                parentName: folder.parentName,
                noteCount: folder.noteCount,
              ),
          ]
        : const <MySharedFolder>[];
    final folderCount = !marks.myFolders
        ? 0
        : withCounts
        ? folders.length
        : await folderDao.countMySharedFolders();
    final partnerFolders = withCounts && marks.partnerFolders
        ? [
            for (final folder in await folderDao.partnerTopFolders())
              PartnerSharedFolder(
                id: folder.id,
                name: folder.name,
                noteCount: folder.noteCount,
              ),
          ]
        : const <PartnerSharedFolder>[];
    final queue = await _shareSending();
    return ShareOverview(
      categories: [
        for (final category in CalendarCategories.all)
          if (category.sharedByMe && !category.fromPartner) category,
      ],
      events: [
        for (final event in events)
          if (event.markedShared && !event.fromPartner)
            MySharedEvent(
              event: event,
              categoryShared:
                  CalendarCategories.byId(event.categoryId)?.sharedByMe ??
                  false,
            ),
      ],
      partnerCategories: partnerCategories,
      partnerEvents: [
        for (final event in events)
          if (event.fromPartner && !partnerIds.contains(event.categoryId))
            event,
      ],
      folders: folders,
      folderCount: folderCount,
      partnerFolders: partnerFolders,
      partnerSharesFolders: marks.partnerFolders,
      readAt: okMs == null ? null : DateTime.fromMillisecondsSinceEpoch(okMs),
      readFailed: failedMs != null && (okMs == null || failedMs > okMs),
      sending: queue.sending,
      sendingParked: queue.parked,
      offline: await _sync.offline(),
      partnerNewerWire: await sync.getValue(SyncDao.keySharedNewerWire) != null,
      refusedCount: await _db.sharedRowDao.refusedCount(),
      anyMark: marks.anyMark,
      eventCounts: withCounts
          ? await _db.calendarEventDao.countByCategory()
          : const {},
    );
  }

  /// Asks for the run that reads what the partner shares now — the Sharing
  /// page's open (D22): that read alone, never a pull or a push — and
  /// completes when it has ended, so the page reads its overview again
  /// then. Nothing while this database is not [ShareReady], nor within
  /// [sharedReadMinAge] of the last read that completed; a failed one does
  /// not count, so "Could not check" is tried again at the next open.
  Future<void> refreshShared() async {
    if (await _reevaluate() is! ShareReady) return;
    final okMs = int.tryParse(
      await _db.syncDao.getValue(SyncDao.keySharedReadOkAt) ?? '',
    );
    if (okMs != null) {
      final age = DateTime.now().millisecondsSinceEpoch - okMs;
      // A clock set back since says nothing about the read's age.
      if (age >= 0 && age < sharedReadMinAge.inMilliseconds) return;
    }
    try {
      await _requestSharedRead();
    } catch (e, st) {
      // The engine shows its own failure; the page reads what there is.
      debugPrint('[ShareService] shared read not run: $e\n$st');
    }
  }

  /// Every end of a sync run of this database ([ShareSyncSource.runsEnded]).
  Stream<void> get runsEnded => _sync.runsEnded;

  /// The pair to write a mark under, read afresh: [ShareRefused] unless
  /// this database is [ShareReady].
  Future<String> _readyPair() async {
    final availability = await _reevaluate();
    final pairId = _pairing.status.pairId;
    if (availability is! ShareReady || pairId == null) {
      throw ShareRefused(availability);
    }
    return pairId;
  }

  /// Writes each mark of [categories], [events] and [folders] (id → shared)
  /// under [pairId], one write each, and says which were written, by the
  /// models as they stood before. An id the catalogue or the cache does not
  /// hold is still handed to its writer, which refuses what is gone or a
  /// partner's, and is left unnamed; a folder is named from its row, read
  /// in the act.
  ///
  /// One transaction: a write that throws takes the act's earlier ones with
  /// it, so a failure said is a failure true — nothing shared, nothing to
  /// undo. Whatever the end, the caches read their marks again.
  Future<ShareChange> _act(
    String pairId, {
    Map<String, bool> categories = const {},
    Map<String, bool> events = const {},
    Map<String, bool> folders = const {},
  }) async {
    if (categories.isNotEmpty) await CategoryService.getInstance();
    final cached = events.isEmpty
        ? const <String, CalendarEvent>{}
        : {
            for (final event
                in (await CalendarEventService.getInstance()).events)
              event.id: event,
          };
    final sharedCategories = <CalendarCategory>[];
    final unsharedCategories = <CalendarCategory>[];
    final sharedEvents = <CalendarEvent>[];
    final unsharedEvents = <CalendarEvent>[];
    final sharedFolders = <ShareFolderRef>[];
    final unsharedFolders = <ShareFolderRef>[];
    final coveredFolders = <ShareFolderRef>[];
    final clearedInnerFolders = <ShareFolderRef>[];
    var wrote = false;
    var stored = false;
    try {
      await _db.transaction(() async {
        for (final MapEntry(key: id, value: on) in categories.entries) {
          final category = CalendarCategories.byId(id);
          if (!await _markCategory(id, on ? pairId : null)) continue;
          wrote = true;
          if (category == null || category.fromPartner) continue;
          (on ? sharedCategories : unsharedCategories).add(category);
        }
        for (final MapEntry(key: id, value: on) in events.entries) {
          if (!await _markEvent(id, on ? pairId : null)) continue;
          wrote = true;
          final event = cached[id];
          if (event == null) continue;
          (on ? sharedEvents : unsharedEvents).add(event);
        }
        final folderDao = _db.folderDao;
        for (final MapEntry(key: id, value: on) in folders.entries) {
          final row = await folderDao.getFolderById(id);
          // Read before the write that clears them: on a share the marks of
          // this pair it now covers, on an un-share every mark under it.
          final inner = row == null
              ? const <({String id, String name})>[]
              : await folderDao.markedUnder(id, on ? pairId : null);
          if (!await _markFolder(id, on ? pairId : null)) continue;
          wrote = true;
          if (row == null) continue;
          (on ? sharedFolders : unsharedFolders).add(
            ShareFolderRef(id: id, name: row.name),
          );
          (on ? coveredFolders : clearedInnerFolders).addAll([
            for (final folder in inner)
              ShareFolderRef(id: folder.id, name: folder.name),
          ]);
        }
        if (wrote) await _markSending();
      });
      stored = wrote;
    } finally {
      await _afterMarks(wrote: stored);
    }
    var kept = 0;
    if (unsharedCategories.isNotEmpty) {
      final left = {for (final category in unsharedCategories) category.id};
      // The act is stored: a count that cannot be made must not report it
      // failed and take its Undo away — the snackbar says no "kept" then.
      try {
        kept = (await CalendarEventService.getInstance()).events
            .where(
              (event) =>
                  event.markedShared &&
                  !event.fromPartner &&
                  left.contains(event.categoryId),
            )
            .length;
      } catch (e, st) {
        debugPrint('[ShareService] kept events not counted: $e\n$st');
      }
    }
    return ShareChange(
      sharedCategories: sharedCategories,
      unsharedCategories: unsharedCategories,
      sharedEvents: sharedEvents,
      unsharedEvents: unsharedEvents,
      sharedFolders: sharedFolders,
      unsharedFolders: unsharedFolders,
      coveredFolders: coveredFolders,
      clearedInnerFolders: clearedInnerFolders,
      keptOnTheirOwn: kept,
    );
  }

  /// After a share act, whatever its end: the writers are the DAOs', which
  /// hold no cache, and a mark set clears every other pair's on all three
  /// tables even when the mark itself stood — so each cache reads its marks
  /// again, once, which also mends a flag a cache held stale. A stored
  /// write asks for the run that sends it. A calendar already showing the
  /// events is told whenever their marks changed in its cache — by the
  /// write, or by a mend alone, which writes nothing.
  ///
  /// The folders first, in a `try` of their own: dropping their caches and
  /// the share census cannot fail on a calendar refresh, and a census kept
  /// would go on saying "not shared" of a folder that is.
  Future<void> _afterMarks({required bool wrote}) async {
    var mended = false;
    try {
      _foldersChanged();
    } catch (e, st) {
      debugPrint('[ShareService] folder caches not dropped: $e\n$st');
    }
    try {
      await CategoryService.refreshShareMarks();
      mended = await CalendarEventService.refreshShareMarks();
    } catch (e, st) {
      // The marks are written; a cache that missed them reads them at its
      // next load.
      debugPrint('[ShareService] caches not refreshed: $e\n$st');
    }
    if (wrote && _availability is ShareReady) _askForRun();
    if (wrote || mended) {
      CalendarEventService.notifyExternalChange(cacheCurrent: true);
    }
  }

  /// Not awaited: the run reaches the network, and the switch that asked
  /// must not wait on it. A failure is the engine's to show.
  void _askForRun() {
    unawaited(
      _requestRun().catchError((Object e, StackTrace st) {
        debugPrint('[ShareService] run not requested: $e\n$st');
      }),
    );
  }

  /// "Sending…" from here until the outbox holds no entry of the shareable
  /// tables ([_shareSending]); inside the act's own transaction wherever it
  /// has one.
  Future<void> _markSending() =>
      _db.syncDao.setValue(SyncDao.keyShareSending, '1');

  /// Whether a share act still waits to be sent: the marker stands and the
  /// outbox holds an entry of the shareable tables. With no marker — every
  /// read but the ones after an act — this is one keyed read. The marker is
  /// cleared in the transaction that finds the outbox drained, so an act
  /// that commits beside this read keeps its own; the outbox is asked
  /// through its own DAO, the only door to its table.
  ///
  /// [parked]: every entry left is one the push set aside, which no run
  /// sends until a start or "Sync now" — "Waiting to send", not "Sending…",
  /// read in the same statement.
  Future<({bool sending, bool parked})> _shareSending() async {
    const idle = (sending: false, parked: false);
    final sync = _db.syncDao;
    if (await sync.getValue(SyncDao.keyShareSending) == null) return idle;
    return _db.transaction(() async {
      final queue = await _db.syncOutboxDao.shareQueueOf(sharedTables);
      if (queue.queued) return (sending: true, parked: queue.parked);
      await sync.deleteValue(SyncDao.keyShareSending);
      return idle;
    });
  }

  /// Whether the row of [table] under [id] is one the partner shares.
  Future<bool> isFromPartner(String table, String id) =>
      _db.sharedRowDao.isShared(table, id);

  /// Both looks and the mark switch in one statement — what the Sharing
  /// page draws its settings rows by. The notes look is read while paired:
  /// an account that never paired, which the Categories page reads this
  /// for, runs the statement it always ran and has no partner's note to
  /// draw.
  Future<ShareLook> looks() async {
    final generation = databaseGeneration;
    final withNotes = _pairing.status.pairId != null;
    final look = await _settings.getShareLook(withNotes: withNotes);
    if (withNotes) {
      _publish(generation, look);
    } else {
      _publishOver(
        generation,
        (known) =>
            known.copyWith(eventLook: look.eventLook, markMine: look.markMine),
      );
    }
    return look;
  }

  Future<ShareEventLook> eventLook() async {
    final generation = databaseGeneration;
    final look = await _settings.getShareLook();
    _publishOver(
      generation,
      (known) =>
          known.copyWith(eventLook: look.eventLook, markMine: look.markMine),
    );
    return look.eventLook;
  }

  Future<void> setEventLook(ShareEventLook look) async {
    final generation = databaseGeneration;
    await _settings.setShareEventLook(look);
    _publishOver(generation, (known) => known.copyWith(eventLook: look));
  }

  /// How a partner's folders and notes are drawn — what the browser builds
  /// its `PartnerLook` from, once per page state.
  Future<ShareNoteLook> noteLook() async {
    final generation = databaseGeneration;
    final look = await _settings.getShareNoteLook();
    _publishOver(generation, (known) => known.copyWith(noteLook: look));
    return look;
  }

  Future<void> setNoteLook(ShareNoteLook look) async {
    final generation = databaseGeneration;
    await _settings.setShareNoteLook(look);
    _publishOver(generation, (known) => known.copyWith(noteLook: look));
  }

  /// The mark, read with the rest of the looks — one statement either way —
  /// so what it publishes is whole.
  Future<bool> markMine() async {
    final generation = databaseGeneration;
    final look = await _settings.getShareLook(withNotes: true);
    _publish(generation, look);
    return look.markMine;
  }

  Future<void> setMarkMine(bool value) async {
    final generation = databaseGeneration;
    await _settings.setShareMarkMine(value);
    _publishOver(generation, (known) => known.copyWith(markMine: value));
  }

  /// The looks and the mark switch as last read or written for the open
  /// database, or null before the first: for a page that draws its first
  /// frame without awaiting — the note editor's share sign — and corrects
  /// from its own read. The `EventAlerts.shareAlerts` shape; cleared by
  /// [reset] on a database switch.
  static ShareLook? get publishedLook => _publishedLook;
  static ShareLook? _publishedLook;

  /// Sets [publishedLook] as a read of it would.
  @visibleForTesting
  static void publishLookForTesting(ShareLook? look) => _publishedLook = look;

  /// Publishes a whole [look] that was read — unless the database switched
  /// while it was read: the look is the old database's then.
  static void _publish(int generation, ShareLook look) {
    if (generation != databaseGeneration) return;
    _publishedLook = look;
  }

  /// A part read or written lands on a whole look read before it, and only
  /// there: published over nothing, its other fields would be the shipped
  /// values nobody read.
  static void _publishOver(
    int generation,
    ShareLook Function(ShareLook known) merge,
  ) {
    final known = _publishedLook;
    if (known == null || generation != databaseGeneration) return;
    _publishedLook = merge(known);
  }

  Future<ShareAlerts> alerts() => _settings.getShareAlerts();

  /// Stores [value] and runs the pass that arms or cancels by it.
  Future<void> setAlerts(ShareAlerts value) async {
    await _settings.setShareAlerts(value);
    await _reconcileAlerts();
  }

  Future<Set<String>> hiddenCategories() =>
      _settings.getShareHiddenCategories();

  /// [setCategoryShown] for a whole set: exactly [ids] hidden afterwards.
  Future<void> setHiddenCategories(Set<String> ids) => _writeHidden((_) => ids);

  /// Shows or hides on this phone the partner's category [id] — one of
  /// their own, or a built-in they share, whose own events here are
  /// untouched (§6.4, D11). Per device: a setting, never a synced row, so
  /// the partner never learns of it. Takes effect at once: the catalogue's
  /// [CalendarCategories.partnerShown], the events (one local reload, no
  /// network — the rows stay stored and current while hidden), a calendar
  /// already showing them, and the alert pass, so nothing stays armed on an
  /// event that no longer exists here (§6.8). Nothing when it already
  /// stood so.
  ///
  /// An id the partner stops sharing leaves the hidden set with that share
  /// (the shared reader's prune), so sharing it again starts shown.
  ///
  /// Returns how many of its events held an alert of mine armed when it was
  /// hidden; 0 when shown, and when it already stood hidden. When it was
  /// more, once the hide is written, [notify] says those alerts are off
  /// (D30, A13) — from here, so the bar needs no sheet and no bloc of the
  /// surface that asked to be alive by then.
  Future<int> setCategoryShown(String id, bool shown) async {
    var armed = 0;
    String? name;
    final written = await _writeHidden(
      (hidden) => shown ? (Set.of(hidden)..remove(id)) : {...hidden, id},
      // Counted in the write's turn, before the reload drops its events; a
      // count that fails costs the bar, never the hide.
      before: shown
          ? null
          : () async {
              name = CalendarCategories.byId(id)?.name;
              try {
                armed = await armedOnPartner(categoryId: id);
              } catch (e, st) {
                debugPrint('[ShareService] armed alerts not counted: $e\n$st');
              }
            },
    );
    // Only for a hide that landed where it was asked: a switch abandoned it,
    // and the notice would be said under a database that never hid it.
    if (!written) return 0;
    if (armed > 0) {
      notify(ShareHiddenWithAlerts(categoryId: id, name: name ?? id));
    }
    return armed;
  }

  /// How many of the partner's events on this phone — under [categoryId]
  /// alone when given, by the category they draw under — hold an alert of
  /// mine still armed on the platform: what a confirmation or a bar must say
  /// goes off with them (D30). No statement while the calendar holds none
  /// of theirs; one read of the pending registrations otherwise, of which
  /// only those still ahead count: a fire time passed is over, though the
  /// row stays pending until the next pass sweeps it.
  Future<int> armedOnPartner({String? categoryId}) async {
    final events = await CalendarEventService.getInstance();
    if (!events.mayHoldPartnerEvents) return 0;
    final theirs = {
      for (final event in events.events)
        if (event.fromPartner &&
            (categoryId == null ||
                CalendarCategories.drawnIdOf(event.categoryId) == categoryId))
          event.id,
    };
    if (theirs.isEmpty) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    return {
      for (final row in await _db.alertRegistrationDao.pending())
        if (row.fireAt > now && theirs.contains(row.eventId)) row.eventId,
    }.length;
  }

  /// The read and the write are one transaction, as the shared reader's
  /// prune is, so neither writes over the other. What follows the store is
  /// published into the app-wide caches only while [_db] is still the
  /// database those caches answer for. [before] runs first in the write's
  /// turn of the chain.
  ///
  /// Answers whether the hidden set changed on the database that was open
  /// when it was asked, and stayed the one open through its store: a write
  /// a switch abandoned — or that found the set as asked — answers false,
  /// and nothing may be said of it.
  Future<bool> _writeHidden(
    Set<String> Function(Set<String>) next, {
    Future<void> Function()? before,
  }) {
    final asked = DatabaseLifecycle.generation;
    final write = _hiddenWrites.then((_) async {
      await before?.call();
      final generation = DatabaseLifecycle.generation;
      if (generation != asked) return false;
      final wanted = await _db.transaction(() async {
        final hidden = await SettingsService.shareHiddenCategoriesOf(_db);
        final wanted = Set<String>.unmodifiable(next(hidden));
        if (wanted.length == hidden.length && wanted.containsAll(hidden)) {
          return null;
        }
        await SettingsService.setShareHiddenCategoriesOf(_db, wanted);
        return wanted;
      });
      if (wanted == null || DatabaseLifecycle.generation != generation) {
        return false;
      }
      CalendarCategories.updatePartnerHidden(wanted);
      bool current;
      try {
        current = await CalendarEventService.refreshHiddenCategories();
      } catch (e, st) {
        // Written all the same; the next load drops by it.
        debugPrint('[ShareService] events not reloaded: $e\n$st');
        current = false;
      }
      CalendarEventService.notifyExternalChange(cacheCurrent: current);
      await _reconcileAlerts();
      return true;
    });
    // The chain outlives a failed write; the caller still hears of it.
    _hiddenWrites = write.then<void>((_) {}, onError: (Object _) {});
    return write;
  }
}
