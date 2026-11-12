import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:stream_transform/stream_transform.dart';

import '../database/database.dart';
import '../database/database_lifecycle.dart';
import '../models/app_user.dart';
import '../models/share_settings.dart';
import '../models/sync_binding.dart';
import 'alert_scheduler.dart';
import 'calendar_event_service.dart';
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

  BindingShareSyncSource({
    required AppUser? Function() currentUser,
    required Stream<AppUser?> authChanges,
    required Future<SyncBinding?> Function() binding,
    required Stream<Object?> Function() bindingChanges,
  }) : _currentUser = currentUser,
       _authChanges = authChanges,
       _binding = binding,
       _bindingChanges = bindingChanges;

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

  /// `FolderStorageService.setFolderShared`, which lives in GetIt.
  final Future<bool> Function(String folderId, String? pairId) markFolder;

  /// Asks the engine for the run that sends a share now; nothing where
  /// sync does not run.
  final Future<void> Function() requestRun;

  const ShareServiceWiring({
    required this.pairing,
    required this.sync,
    required this.markFolder,
    required this.requestRun,
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

  final PairingService _pairing;
  final ShareSyncSource _sync;
  final AppDatabase _db;
  final SettingsService _settings;
  final Future<bool> Function(String eventId, String? pairId) _markEvent;
  final Future<bool> Function(String folderId, String? pairId) _markFolder;
  final Future<void> Function() _requestRun;
  final Future<void> Function() _reconcileAlerts;

  final StreamController<ShareAvailability> _controller =
      StreamController<ShareAvailability>.broadcast();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  ShareAvailability _availability = const ShareNotPaired();

  /// Evaluations started, so one that lands after a newer one is dropped.
  int _evaluations = 0;

  /// The evaluation [_availability] was taken from.
  int _landed = 0;

  ShareService._({
    required PairingService pairing,
    required ShareSyncSource sync,
    required AppDatabase db,
    required SettingsService settings,
    required Future<bool> Function(String eventId, String? pairId) markEvent,
    required Future<bool> Function(String folderId, String? pairId) markFolder,
    required Future<void> Function() requestRun,
    required Future<void> Function() reconcileAlerts,
  }) : _pairing = pairing,
       _sync = sync,
       _db = db,
       _settings = settings,
       _markEvent = markEvent,
       _markFolder = markFolder,
       _requestRun = requestRun,
       _reconcileAlerts = reconcileAlerts;

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
        markEvent: (id, pairId) async =>
            (await CalendarEventService.getInstance()).setShared(id, pairId),
        markFolder: wiring.markFolder,
        requestRun: wiring.requestRun,
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
  /// so the code under test reaches it through [getInstance].
  @visibleForTesting
  static Future<ShareService> forTesting({
    required AppDatabase db,
    required SettingsService settings,
    required PairingService pairing,
    required ShareSyncSource sync,
    required Future<bool> Function(String eventId, String? pairId) markEvent,
    required Future<bool> Function(String folderId, String? pairId) markFolder,
    Future<void> Function()? requestRun,
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
      markFolder: markFolder,
      requestRun: requestRun ?? () async {},
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

  /// Shares the event [id] with the audience, or stops sharing it.
  /// Returns whether its mark changed.
  ///
  /// Throws [ShareRefused] unless this database is [ShareReady] now —
  /// evaluated afresh, since the pairing's own writes publish no change.
  Future<bool> setEventShared(String id, bool on) =>
      _setShared(id, on, _markEvent);

  /// [setEventShared] for the folder [id] and everything under it.
  Future<bool> setFolderShared(String id, bool on) =>
      _setShared(id, on, _markFolder);

  Future<bool> _setShared(
    String id,
    bool on,
    Future<bool> Function(String id, String? pairId) mark,
  ) async {
    final availability = await _reevaluate();
    final pairId = _pairing.status.pairId;
    if (availability is! ShareReady || pairId == null) {
      throw ShareRefused(availability);
    }
    final changed = await mark(id, on ? pairId : null);
    if (changed) _askForRun();
    return changed;
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

  /// Whether the row of [table] under [id] is one the partner shares.
  Future<bool> isFromPartner(String table, String id) =>
      _db.sharedRowDao.isShared(table, id);

  Future<ShareEventLook> eventLook() async =>
      (await _settings.getShareLook()).eventLook;

  Future<void> setEventLook(ShareEventLook look) =>
      _settings.setShareEventLook(look);

  Future<bool> markMine() async => (await _settings.getShareLook()).markMine;

  Future<void> setMarkMine(bool value) => _settings.setShareMarkMine(value);

  Future<ShareAlerts> alerts() => _settings.getShareAlerts();

  /// Stores [value] and runs the pass that arms or cancels by it.
  Future<void> setAlerts(ShareAlerts value) async {
    await _settings.setShareAlerts(value);
    await _reconcileAlerts();
  }

  Future<Set<String>> hiddenCategories() =>
      _settings.getShareHiddenCategories();

  Future<void> setHiddenCategories(Set<String> ids) =>
      _settings.setShareHiddenCategories(ids);
}
