import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../constants/app_version.dart';
import '../../database/crdt/synced_tables.dart';
import '../../database/database.dart';
import '../../database/migrations/database_schema.dart';
import '../database_manager.dart';
import 'account_closer.dart';
import 'sync_binding_service.dart';
import 'sync_gateway.dart';
import 'sync_space_registry.dart';
import 'sync_suspension.dart';

/// Why a bind, a download or a stop failed, in the terms the Sharing page
/// words.
enum SyncBindFailure {
  /// No connection reached the cloud.
  offline,

  /// The account's daily quota ran out.
  quotaExhausted,

  /// The cloud refused the call: the rules are not deployed, or the space is
  /// another account's.
  permissionDenied,

  /// The chosen space is no longer in the cloud — deleted since the picker
  /// listed it — so the way on is another space or a new upload, not the
  /// account check [permissionDenied] asks for (review X-13).
  spaceGone,

  /// The space's [SyncSpaceInfo.schema] is above this build's
  /// [DatabaseSchema.syncSchemaVersion], so a deletion is refused before
  /// anything changes: a newer build may have written a table this one does
  /// not list, and removing the space document over it would strand those
  /// rows for good (cloud-multi-user-roadmap §5.3). The way on is an update.
  appOutdated,

  /// A restore or import is rewriting this database right now.
  suspended,

  /// This database syncs already: stop syncing first.
  alreadyBound,

  /// Another database of this install syncs with the chosen space —
  /// [SyncSpaceException.holderDatabase] names it.
  spaceHeldByAnotherDatabase,

  /// A space name empty after trimming, or over
  /// [SyncSpaceService.maxSpaceNameLength] code points.
  invalidSpaceName,

  /// The new database a download needs could not be created or opened; the
  /// user is still on the database they started from.
  newDatabaseFailed,

  /// The account chosen to confirm an account's deletion is not the one
  /// signed in: nothing was confirmed and nothing changed
  /// (cloud-multi-user-roadmap §6.1 c).
  otherAccount,

  /// The account's own deletion is under way or waiting, so nothing new of
  /// it may reach the cloud: a bind is refused until the deletion is
  /// finished or given up.
  accountDeleting,

  unknown,
}

class SyncSpaceException implements Exception {
  final SyncBindFailure failure;

  /// For [SyncBindFailure.spaceHeldByAnotherDatabase]: the database that
  /// holds the space, as the Databases page lists it.
  final String? holderDatabase;

  const SyncSpaceException(this.failure, {this.holderDatabase});

  @override
  String toString() =>
      'SyncSpaceException(${failure.name}'
      '${holderDatabase == null ? '' : ': $holderDatabase'})';
}

/// Where one account's cloud-copy deletions stand on this install
/// (cloud-multi-user-roadmap §5): what a "Finish deleting" row and a deleting
/// line are drawn from. Read it with [SyncSpaceService.deletionStatus],
/// follow it with [SyncSpaceService.deletionStatusOf].
///
/// A run is the background job [SyncSpaceService] owns, one per process at a
/// time, that empties and removes the account's marked spaces one after
/// another; it lives as long as the process, whether a page is open or not.
class SyncDeletionStatus extends Equatable {
  final String accountUid;

  /// The account's deletions this install knows of and has not finished, in
  /// the order they were recorded — the ones it began, and the marked spaces
  /// a "Sync this database" met — the one a run is emptying included, until
  /// its space is removed. Never another account's: only the owner may
  /// finish one.
  final List<SyncPendingDeletion> pending;

  /// Whether a run for this account is requested and not yet ended — under
  /// way, or waiting behind another account's — or about to be: from the
  /// moment "Delete cloud copy" or a "Sync this database" records a deletion
  /// to the run's request.
  final bool running;

  /// The documents the account's current run has removed so far, across its
  /// spaces; after the run ends, what it removed in all. A new run starts
  /// again from 0.
  final int removed;

  /// Why the account's last run stopped short, its record and every later
  /// one left in [pending]: null while a run is in flight, after one that
  /// finished, and before the first in this process.
  final SyncBindFailure? failure;

  /// Whether the account itself is being deleted, its cloud copies first
  /// (cloud-multi-user-roadmap §6.1): asked for on this install and not
  /// finished. While it is, [running] covers the account's last steps too —
  /// its pairs, its invites, the sign-in account — and with nothing running
  /// the deletion waits for the user to sign in again and finish it
  /// ([SyncSpaceService.deleteAccount]), whether or not [failure] says why
  /// it stopped.
  final bool account;

  const SyncDeletionStatus({
    required this.accountUid,
    this.pending = const [],
    this.running = false,
    this.removed = 0,
    this.failure,
    this.account = false,
  });

  /// Whether anything of the account's is still to delete: a cloud copy, or
  /// the account itself.
  bool get isLive => running || pending.isNotEmpty || account;

  @override
  List<Object?> get props => [
    accountUid,
    pending,
    running,
    removed,
    failure,
    account,
  ];
}

/// One [SyncSpaceService.deleteAccount] call's word that a run may end the
/// account itself, dated by the moment the call was made — right after its
/// caller had the account sign in again. Compared by identity: an attempt
/// that began under one licence never takes back a later call's.
final class _Licence {
  final DateTime at;

  _Licence(this.at);
}

/// One account's run as the service tracks it.
class _DeletionRun {
  int removed = 0;
  SyncBindFailure? failure;

  /// What licenses this run to end the account itself once its spaces are
  /// gone (cloud-multi-user-roadmap §6.1 c); null for a run that may not.
  /// Set only by [SyncSpaceService.deleteAccount] on the run that call
  /// started or joined — and taken back the moment an attempt under it
  /// finds it cannot, or the deletion is given up. A run resumed at a
  /// start-up, asked by "Finish deleting" or started by a later cloud
  /// copy's deletion finishes the copies and leaves the account waiting, so
  /// an account is never deleted by a run nobody asked that of.
  _Licence? licence;
}

/// What the install records for one account: the half of a
/// [SyncDeletionStatus] that is stored, where the run's half is in memory.
typedef _DeletionRecords = ({List<SyncPendingDeletion> pending, bool account});

/// What a "Sync this database" tap led to (record §2 D1, D2).
sealed class SyncBindStart extends Equatable {
  const SyncBindStart();
}

/// Bound in the tap: the account's first space created, or the one space
/// bound by a database that holds nothing.
final class SyncBindStartBound extends SyncBindStart {
  final SyncSpaceRef space;

  const SyncBindStartBound(this.space);

  @override
  List<Object?> get props => [space];
}

/// The picker's data: the account's spaces, most recently written first —
/// never one marked for deletion.
final class SyncBindStartPick extends SyncBindStart {
  final List<SyncSpaceInfo> spaces;

  /// Whether this database holds anything a person made — the picker leads
  /// with "Merge this database into the space" then.
  final bool holdsData;

  /// The spaces another database of this install holds, with its name:
  /// binding one is refused, so the picker can say so before the tap.
  final Map<SyncSpaceRef, String> heldBy;

  const SyncBindStartPick({
    required this.spaces,
    required this.holdsData,
    this.heldBy = const {},
  });

  @override
  List<Object?> get props => [spaces, holdsData, heldBy];
}

/// The bind flow below the Sharing page (record §3.6): the account's spaces,
/// creating one, binding this database or a new one to one, and stopping.
///
/// Holds nothing per database: the database, its binding service and the
/// database manager are resolved on every call, so a download's switch — or
/// any other — never leaves it speaking to a closed database. Only the
/// gateway is kept, global like the identity, and the deletion runs, which
/// touch nothing local and so belong to the process, not to a database.
class SyncSpaceService {
  /// The rules' cap on a space name, in code points (record §3.3).
  static const int maxSpaceNameLength = 100;

  final SyncGateway _gateway;
  final Future<AppDatabase> Function() _database;
  final Future<SyncBindingService> Function() _binding;
  final Future<DatabaseManager> Function() _databases;

  /// What ends an account once its spaces are gone; null where an account
  /// cannot be deleted from here, and [deleteAccount] then refuses.
  final AccountCloser? _closer;

  /// The clock a run's licence is aged by; a test's own.
  final DateTime Function() _now;

  /// How long after the sign-in a run may still start the account's own
  /// end. The server deletes an account only within minutes of a sign-in —
  /// about five as observed; Firebase's documentation names no figure — and
  /// the pairs and invites go first: a run that began them past the window
  /// would remove those and then be refused the account — sharing ended,
  /// the account kept. Under the window with a margin, the two go together
  /// or not at all; past it the account waits for a sign-in, untouched. A
  /// server stricter than observed is still only a wait
  /// ([AccountCloseFailure.recentSignInRequired]).
  static const Duration accountCloseWindow = Duration(minutes: 4);

  /// The accounts a [deleteAccount] call is still marking the spaces of,
  /// counted per call: their run must not close the account yet — the
  /// listing it would judge by is about to change.
  final Map<String, int> _marking = {};

  final StreamController<String> _accountsDeleted =
      StreamController<String>.broadcast();

  /// The accounts whose run is requested and not yet under way, in the
  /// order asked; [_runningFor] is the one under way.
  final List<String> _waiting = [];
  String? _runningFor;

  /// Whether [_runAll] is looping, and the future that ends with it.
  bool _draining = false;
  Future<void> _drained = Future<void>.value();

  final Map<String, _DeletionRun> _runs = {};

  /// The accounts a run was requested for in this process, less those whose
  /// last run ended on the moment ([_momentary]): [followAccounts] resumes an
  /// account only when it is not here, so a failure never loops.
  final Set<String> _attempted = {};

  /// The accounts [followAccounts] was told of while their run was in
  /// flight: a run that then ends on the moment is requested once more if
  /// the account is still [_followed] (review K4). Spent at the run's end
  /// whatever it ended on, so each emission owes one run at most.
  final Set<String> _owed = {};

  /// The accounts whose deletion is being recorded ([_recordAndRequest]) and
  /// not yet requested, counted per call: their status reads running (review
  /// G4).
  final Map<String, int> _recording = {};

  StreamSubscription<String?>? _accounts;

  /// The account [followAccounts] last heard, null signed out.
  String? _followed;

  /// Set by [dispose]: a run ends at its next gateway call and nothing is
  /// requested or published any more.
  bool _disposed = false;

  /// The status last published per account. The controller is sync, so
  /// each [deletionStatusOf] stream's own controller has every change in
  /// the order published, before [_publish] returns; that controller, as
  /// every `Stream.multi` one's `add`, delivers it in a later microtask.
  final Map<String, SyncDeletionStatus> _published = {};
  final StreamController<SyncDeletionStatus> _statusChanges =
      StreamController<SyncDeletionStatus>.broadcast(sync: true);

  SyncSpaceService({
    required SyncGateway gateway,
    Future<AppDatabase> Function() database = AppDatabase.getInstance,
    Future<SyncBindingService> Function() binding =
        SyncBindingService.getInstance,
    Future<DatabaseManager> Function() databases = DatabaseManager.getInstance,
    AccountCloser? closer,
    DateTime Function() now = DateTime.now,
  }) : _gateway = gateway,
       _database = database,
       _binding = binding,
       _databases = databases,
       _closer = closer,
       _now = now;

  /// The "Sync this database" tap (D1, D2): no space yet → the account's
  /// first space, named after this database (the default one after the
  /// app), created and bound; this
  /// database holding nothing and exactly one space that no other database
  /// here holds → that space bound; otherwise the picker's data.
  ///
  /// The account's spaces marked for deletion are left to any device to
  /// finish (cloud-multi-user-roadmap §5.2 g): each is recorded as a pending
  /// deletion if it is not already and the account's run requested, as
  /// [finishPendingDeletions] does, without waiting for it. The decision
  /// counts the unmarked spaces only, so a dying space is never offered,
  /// and with none left the first space is created. A record that cannot be
  /// written is logged and the bind goes on: the space carries the mark, so
  /// a later "Sync this database" meets it again.
  Future<SyncBindStart> start({required String accountUid}) =>
      _mapped(() async {
        await _ensureAccountStays(accountUid);
        await _ensureBindable();
        final listed = await listSpaces(accountUid);
        try {
          await _recordMarked(accountUid, listed);
        } catch (e, st) {
          debugPrint('[SyncSpaceService] marked spaces not recorded: $e\n$st');
        }
        final spaces = [
          for (final space in listed)
            if (!space.markedForDeletion) space,
        ];
        if (spaces.isEmpty) {
          final created = await _createAndBind(
            accountUid: accountUid,
            name: await _defaultSpaceName(),
          );
          return SyncBindStartBound(created.ref);
        }
        final holdsData = await databaseHoldsData();
        final heldBy = await _heldBy(spaces);
        if (!holdsData && spaces.length == 1 && heldBy.isEmpty) {
          await _bind(spaces.single.ref, accountUid: accountUid);
          return SyncBindStartBound(spaces.single.ref);
        }
        return SyncBindStartPick(
          spaces: spaces,
          holdsData: holdsData,
          heldBy: heldBy,
        );
      });

  /// The account's spaces, the most recently written first; a space never
  /// written to sorts after every written one, the newest created first.
  Future<List<SyncSpaceInfo>> listSpaces(String accountUid) => _mapped(
    () async {
      final spaces = [...await _gateway.listSpaces(accountUid)];
      int newestFirst(DateTime? a, DateTime? b) {
        if (a == null || b == null) return a == null ? (b == null ? 0 : 1) : -1;
        return b.compareTo(a);
      }

      spaces.sort((a, b) {
        final written = newestFirst(a.lastWriteAt, b.lastWriteAt);
        if (written != 0) return written;
        return newestFirst(a.createdAt, b.createdAt);
      });
      return spaces;
    },
  );

  /// Whether this database holds anything a person made (D2: one that holds
  /// nothing skips the picker): a live row in any table that syncs. Not
  /// counted: `content_chunks`, which only exist inside a note, and the
  /// built-in calendar categories, which every database seeds on open —
  /// edited or not, since a bind settles them against the space's under the
  /// floor either way. Tombstones are not counted: they hold nothing to keep.
  Future<bool> databaseHoldsData() async {
    final db = await _database();
    final probes = [
      for (final synced in syncedTables)
        if (!synced.contentAddressed)
          'EXISTS (SELECT 1 FROM ${synced.name} WHERE is_deleted = 0'
              '${synced.name == 'calendar_categories' ? ' AND is_built_in = 0' : ''})',
    ];
    final row = await db
        .customSelect('SELECT (${probes.join(' OR ')}) AS held')
        .getSingle();
    return row.read<bool>('held');
  }

  /// "Upload as a new space": created under [name], trimmed — this
  /// database's name when null, the app's for the default database — then
  /// this database bound to it. A name outside 1..[maxSpaceNameLength] code
  /// points is refused before the gateway.
  Future<SyncSpaceInfo> createAndBind({
    required String accountUid,
    String? name,
  }) => _mapped(() async {
    await _ensureAccountStays(accountUid);
    await _ensureBindable();
    return _createAndBind(
      accountUid: accountUid,
      name: name ?? await _defaultSpaceName(),
    );
  });

  /// The name a space this database creates takes unless one is given: the
  /// database's, as the Databases page lists it — but the app's for the
  /// owner's default database, whose `gym_notes` is a file name kept from the
  /// app's first life, and spaces cannot be renamed yet (review BA-L2,
  /// record §8). A QA build's own default keeps its name.
  Future<String> _defaultSpaceName() async {
    final name = (await _databases()).getActiveDatabaseName();
    return name == DatabaseManager.defaultDatabaseName(qaEnabled: false)
        ? kAppName
        : name;
  }

  /// "Merge this database into the space": this database bound to [space],
  /// its rows settled against the space's under the floor (D15).
  ///
  /// The space is read first: one gone from the cloud or marked for deletion
  /// since the picker listed it is [SyncBindFailure.spaceGone], nothing
  /// bound.
  Future<void> bindExisting(SyncSpaceRef space, {required String accountUid}) =>
      _mapped(() async {
        await _ensureAccountStays(accountUid);
        await _ensureBindable();
        await _ensureNotHeld(space);
        await _ensureLive(space);
        await _bind(space, accountUid: accountUid);
      });

  /// "Download the space into a new database": a new database named after
  /// [space], made active — the open database switches in place — and bound
  /// with nothing local to merge, so the pull fills it. Returns its name.
  ///
  /// The name is the space's through [DatabaseManager.suggestDatabaseName],
  /// the rule a database import already follows: every character outside
  /// `[a-zA-Z0-9_-]` becomes `_`, at most 50 characters, `_1`, `_2`, … until
  /// no file has it. A failure after the create switches back to the
  /// database the user started from and deletes the new file, which holds
  /// nothing but the schema.
  ///
  /// The space is read first, so offline or a space gone from the cloud —
  /// or marked for deletion — is refused before anything here changes
  /// (review BA-M3). From the switch to
  /// the bind, [DatabaseManager.markDownloadInFlight] lets a launch after a
  /// kill switch back (BA-M2). The database the user started from keeps its
  /// own binding and claim.
  Future<String> downloadIntoNewDatabase(
    SyncSpaceInfo space, {
    required String accountUid,
  }) => _mapped(() async {
    await _ensureAccountStays(accountUid);
    if (SyncSuspension.isSuspended) {
      throw const SyncSpaceException(SyncBindFailure.suspended);
    }
    await _ensureNotHeld(space.ref);
    await _ensureLive(space.ref);
    final databases = await _databases();
    final previous = databases.getActiveDatabaseName();
    // Past the holder check, a claim on the space by the database left is
    // stale — it does not sync the space — and would stop the new database's
    // own bind: dropped, as a Merge's claim would replace it.
    final registry = databases.spaceRegistry;
    final stale = SyncSpaceClaim(space: space.ref, databaseName: previous);
    if (registry.claims().contains(stale)) await registry.release(previous);
    final String name;
    try {
      name = await databases.suggestDatabaseName(space.name);
      await databases.createDatabase(name);
    } catch (e, st) {
      debugPrint('[SyncSpaceService] new database not created: $e\n$st');
      throw const SyncSpaceException(SyncBindFailure.newDatabaseFailed);
    }
    try {
      await databases.markDownloadInFlight(from: previous, to: name);
      await databases.setActiveDatabaseName(name);
      await _database();
    } catch (e, st) {
      debugPrint('[SyncSpaceService] new database not opened: $e\n$st');
      await _returnTo(previous, leaving: name);
      throw const SyncSpaceException(SyncBindFailure.newDatabaseFailed);
    }
    try {
      await (await _binding()).bind(space: space.ref, accountUid: accountUid);
    } catch (_) {
      await _returnTo(previous, leaving: name);
      rethrow;
    }
    try {
      await databases.clearDownloadInFlight();
    } catch (e, st) {
      // Bound already: a marker left behind only lands the next launch on
      // the database the user started from.
      debugPrint('[SyncSpaceService] download marker not cleared: $e\n$st');
    }
    return name;
  });

  /// "Stop syncing this database" (D6 A): unbound, the claim released by the
  /// unbind; the space stays. Allowed whatever the account — signed out or
  /// another account's is D5's way out. Unbound already, it writes nothing:
  /// an unbind would raise the floor a restore or the last unbind wrote, and
  /// the space would win edits made since (D15).
  Future<void> stopSyncing() => _mapped(() async {
    final binding = await _binding();
    if (await binding.read() == null) return;
    await binding.unbind();
  });

  /// "Delete cloud copy" (cloud-multi-user-roadmap §5): the space this
  /// database syncs with removed from the account for good; every row on
  /// this device stays. The caller stops the engine first, as it does for
  /// [stopSyncing]; this call never touches it.
  ///
  /// The order is the design. Unbound, nothing happens. The space is read:
  /// gone already, this database is unbound as [stopSyncing] does and the
  /// call returns. Then the space is marked — from here there is no way
  /// back — and read again, since only from the mark on is its schema
  /// final: a newer build may have pushed a table this build does not list
  /// in between (review F3). Then the deletion is recorded install-wide
  /// ([pendingDeletions]) and only then this database unbound as
  /// [stopSyncing] does, so an app that dies in between never leaves a
  /// marked space that no device shows (review F6). A space marked already
  /// — a second call on a database still bound to it — goes the same way.
  ///
  /// The call returns there, unbound, with the space owner's run requested
  /// as [finishPendingDeletions] does: emptying every table, removing the
  /// space document and clearing the record outlast any page, so they run
  /// in the background and [deletionStatusOf] reports them — a failure
  /// there is the status's [SyncDeletionStatus.failure], never this call's.
  ///
  /// Throws [SyncSpaceException]. With nothing changed — still bound, still
  /// syncing: [SyncBindFailure.suspended] while a restore runs,
  /// [SyncBindFailure.appOutdated] for a space a newer build wrote to, and
  /// any failure of the read or the mark (`offline`, `quotaExhausted`,
  /// `permissionDenied` when another account is signed in).
  ///
  /// In one race the mark stands with nothing else done: a newer build that
  /// wrote between the first read and the mark, which the second read finds
  /// — [SyncBindFailure.appOutdated], nothing recorded, still bound — or a
  /// failure of that second read. The database stays bound and its engine
  /// pauses as `spaceDeleted`; an updated app, or a second call, finishes
  /// it. A failure of the unbind leaves the deletion recorded and no run
  /// requested: "Finish deleting" ([finishPendingDeletions]) takes it on,
  /// and so does the next [start] of any device of the account;
  /// [followAccounts] takes it on only at the account's next emission — a
  /// sign-in, a change of account, the next launch — and only when its
  /// resume rule allows.
  ///
  /// From the record to the unbind, the owner's status reads running with
  /// no failure — the last run's cleared — so no moment reads as a deletion
  /// stopped short; a failed unbind settles it as pending, not running, and
  /// a record that cannot be written leaves the last run's state as it was
  /// ([_recordAndRequest]).
  Future<void> deleteCloudCopy() => _mapped(() async {
    final binding = await _binding();
    final bound = await binding.read();
    if (bound == null) return;
    if (SyncSuspension.isSuspended) {
      throw const SyncSpaceException(SyncBindFailure.suspended);
    }
    final space = SyncSpaceRef(
      ownerUid: bound.ownerUid,
      spaceId: bound.spaceId,
    );
    final registry = (await _databases()).spaceRegistry;
    final info = await _gateway.readSpace(space);
    if (info == null) {
      await binding.unbind();
      await registry.clearPendingDeletion(space);
      _publish(space.ownerUid, registry);
      return;
    }
    // Refuses the common case before anything changes.
    _ensureKnownSchema(info);
    await _gateway.markSpaceDeleted(space);
    final marked = await _gateway.readSpace(space);
    if (marked == null) {
      await binding.unbind();
      await registry.clearPendingDeletion(space);
      _publish(space.ownerUid, registry);
      return;
    }
    _ensureKnownSchema(marked);
    await _recordAndRequest(space.ownerUid, registry, [
      SyncPendingDeletion(space: space, spaceName: marked.name),
    ], then: binding.unbind);
  });

  /// "Delete account" (cloud-multi-user-roadmap §6.1): every cloud copy of
  /// [accountUid] marked for deletion, this database unbound when it syncs
  /// with one of them, and the account itself recorded as going once they
  /// are gone. Every row on this device stays. The caller has just had the
  /// account sign in again and stops the engine first, as for
  /// [deleteCloudCopy]; this call touches neither. Asked again while the
  /// deletion waits — "Finish deleting account" — it goes on from where the
  /// last attempt stopped.
  ///
  /// The order is the design. The account's spaces are listed, and nothing
  /// has changed if that fails, if a restore is running
  /// ([SyncBindFailure.suspended]) or if one of them was written by a newer
  /// build ([SyncBindFailure.appOutdated]: this build could never finish
  /// it). Then the account's deletion is recorded, and each space is marked
  /// and recorded one by one — this database's own first, unbound as soon
  /// as it is — so a failure midway leaves marks and records in step: what
  /// was marked is finished like any cloud copy, and the account waits.
  ///
  /// Unlike [deleteCloudCopy] it does not read a space again after its
  /// mark: a newer build's write that landed in between is met by the run,
  /// which passes that space over as it does any other ([_run]), with this
  /// database unbound already — there is no account left to keep it bound
  /// for.
  ///
  /// The call returns there, with the account's run requested. The run
  /// empties and removes the spaces as [finishPendingDeletions] describes,
  /// then — this run alone, the one this call started or joined, never one
  /// resumed or asked for otherwise, and only within [accountCloseWindow]
  /// of this call — reads the account's spaces once more and, when none is
  /// left, has the [AccountCloser] end its pairs, its invites and the
  /// account itself; [accountsDeleted] then names it. A space met there is
  /// recorded when it is marked, and left alone when it is not — made
  /// since, and only a person marks one — in which case the account waits
  /// for the next call, as it does when the window has passed by then: with
  /// no failure, since nothing failed.
  ///
  /// From the record on, no bind of this account is accepted
  /// ([SyncBindFailure.accountDeleting]) until the deletion finishes or is
  /// given up ([abandonAccountDeletion]).
  ///
  /// Throws [SyncSpaceException]; [SyncBindFailure.unknown] where no
  /// [AccountCloser] is bound.
  Future<void> deleteAccount({required String accountUid}) => _mapped(() async {
    if (_closer == null) {
      throw const SyncSpaceException(SyncBindFailure.unknown);
    }
    if (SyncSuspension.isSuspended) {
      throw const SyncSpaceException(SyncBindFailure.suspended);
    }
    // The sign-in is as old as this call at least: the window is counted
    // from here, never from the end of the marking below, which a slow link
    // stretches.
    final licence = _Licence(_now());
    final binding = await _binding();
    final registry = (await _databases()).spaceRegistry;
    final listed = await _gateway.listSpaces(accountUid);
    listed.forEach(_ensureKnownSchema);

    _recording[accountUid] = (_recording[accountUid] ?? 0) + 1;
    _marking[accountUid] = (_marking[accountUid] ?? 0) + 1;
    try {
      await registry.setPendingAccountDeletion(accountUid);
      // From the record on the last run's failure is that attempt's, as
      // [_recordAndRequest] has it.
      if (!_requested(accountUid)) _runs[accountUid] = _DeletionRun();
      _publish(accountUid, registry);

      final bound = await binding.read();
      final own = bound != null && bound.ownerUid == accountUid
          ? SyncSpaceRef(ownerUid: bound.ownerUid, spaceId: bound.spaceId)
          : null;
      final ordered = [
        for (final space in listed)
          if (space.ref == own) space,
        for (final space in listed)
          if (space.ref != own) space,
      ];
      for (final space in ordered) {
        if (!space.markedForDeletion) {
          await _gateway.markSpaceDeleted(space.ref);
        }
        await registry.addPendingDeletion(
          SyncPendingDeletion(space: space.ref, spaceName: space.name),
        );
        _publish(accountUid, registry);
        if (space.ref == own) await binding.unbind();
      }
      // Bound to a space of the account that is no longer listed: gone
      // already, and nothing is left to sync with.
      if (own != null && ordered.every((space) => space.ref != own)) {
        await binding.unbind();
      }
    } catch (_) {
      _endMarking(accountUid);
      _endRecording(accountUid);
      _publish(accountUid, registry);
      rethrow;
    }
    _endMarking(accountUid);
    _endRecording(accountUid);
    _request(accountUid, registry);
    // The run just requested, or the one already emptying this account's
    // copies, which then ends the account too — and looks again when this
    // reaches it at its very end ([_run]).
    _runs[accountUid]?.licence = licence;
  });

  void _endMarking(String accountUid) {
    final left = (_marking[accountUid] ?? 1) - 1;
    if (left > 0) {
      _marking[accountUid] = left;
    } else {
      _marking.remove(accountUid);
    }
  }

  /// Gives up [accountUid]'s own deletion — the user asked to sign out,
  /// which is the way out the page names (cloud-multi-user-roadmap §6.1 d).
  /// The account stays: the record is cleared and a run in flight loses its
  /// licence at once, so it finishes the copies and stops there even when
  /// it is already past its listing ([_closeAccount] asks again before the
  /// account's own delete). The cloud copies already marked are still
  /// removed, by their owner's next run. Nothing changes when no deletion
  /// of that account is recorded.
  Future<void> abandonAccountDeletion(String accountUid) => _mapped(() async {
    _runs[accountUid]?.licence = null;
    final registry = (await _databases()).spaceRegistry;
    await registry.clearPendingAccountDeletion(accountUid);
    _publish(accountUid, registry);
  });

  /// The uid of each account this service deleted, as its session ends —
  /// what tells a sign-out that is the end of a deletion from any other.
  /// Broadcast, never replayed, never an error.
  Stream<String> get accountsDeleted => _accountsDeleted.stream;

  /// The deletions this install knows of for [accountUid]'s spaces and has
  /// not finished, in the order they were recorded — what the "Finish
  /// deleting" row offers. Another account's are never listed: only their
  /// owner may finish them.
  Future<List<SyncPendingDeletion>> pendingDeletions(String accountUid) =>
      _mapped(
        () async => [
          for (final pending
              in (await _databases()).spaceRegistry.pendingDeletions())
            if (pending.space.ownerUid == accountUid) pending,
        ],
      );

  /// "Finish deleting": [accountUid]'s run requested, and the call returns
  /// once it is — it never waits for the run, and never fails for it; the
  /// run's progress and outcome are [deletionStatusOf]'s. A run for the
  /// account already in flight or waiting is left as it is; one for another
  /// account goes first, and this one waits for it to end.
  ///
  /// The run takes every [pendingDeletions] of the account in turn,
  /// re-reading the records before each, so a deletion recorded meanwhile is
  /// taken too: the space read, then every table emptied in pages of
  /// [SyncGateway.rowDeleteBatch], the space document removed and the record
  /// cleared. Only the mark licenses a deletion, never the record (review
  /// F8): a record whose space is gone is cleared, and so is one whose space
  /// reads unmarked, which is never marked or emptied. A space a newer build
  /// wrote to is passed over, its record kept, and the run ends as
  /// [SyncBindFailure.appOutdated] once the later ones are done. Any other
  /// failure — the gateway's, mapped as every call here maps it — stops it
  /// at once, leaving that record and every later one for the next request.
  /// It reads and writes nothing local and never touches the engine, so it
  /// runs bound or not, the page open or not.
  Future<void> finishPendingDeletions({required String accountUid}) =>
      _mapped(() async {
        _request(accountUid, (await _databases()).spaceRegistry);
      });

  /// Follows the account signed in on this device for the life of the
  /// process — [accounts] replays the current one first, as
  /// `AuthService.authStateChanges` does — and resumes a deletion the
  /// process did not see end (the app killed mid-run, an unbind that
  /// failed, a record a [start] left) each time an account becomes known:
  /// at launch, at a sign-in, at a change of account. The app's start-up
  /// calls it, not a bloc: one exists only once a sync surface is built,
  /// and the run belongs to the process (review G3).
  ///
  /// The account's run is requested as [finishPendingDeletions] does when
  /// it has [pendingDeletions] and either no run was asked for it in this
  /// process or its last one ended on the moment rather than on the
  /// deletion — refused, as a sign-out or another account under it is, or
  /// offline (review G2). One that ended on the quota, an outdated app or
  /// an unknown failure waits for "Finish deleting" or the next process, so
  /// a failure never loops. An account that becomes known while its own run
  /// is in flight — back from a sign-out or another account that run may
  /// yet fail on — is owed one more request, made when that run ends on the
  /// moment and the account is still the one followed (review K4). With
  /// nothing pending it costs one read of the install-wide record and no
  /// network call.
  void followAccounts(Stream<String?> accounts) {
    unawaited(_accounts?.cancel());
    _followed = null;
    _accounts = accounts.listen(
      (uid) {
        if (uid == _followed) return;
        _followed = uid;
        if (uid != null) unawaited(_resume(uid));
      },
      onError: (Object e, StackTrace st) =>
          debugPrint('[SyncSpaceService] account not followed: $e\n$st'),
    );
  }

  /// Ends what [followAccounts] follows, when the app's dependencies are
  /// reset: the identity it listens to goes with them. A run in flight ends
  /// at its next gateway call, the runs waiting never start, and nothing is
  /// requested or published afterwards. The records stay, for the next
  /// service to resume.
  Future<void> dispose() async {
    _disposed = true;
    _waiting.clear();
    _owed.clear();
    _followed = null;
    final accounts = _accounts;
    _accounts = null;
    await accounts?.cancel();
  }

  /// [accountUid]'s deletions as they stand now: its [pendingDeletions] read
  /// afresh, with its run's state.
  Future<SyncDeletionStatus> deletionStatus(String accountUid) =>
      _mapped(() async {
        final registry = (await _databases()).spaceRegistry;
        _publish(accountUid, registry);
        return _statusOf(accountUid, _recordsOf(accountUid, registry));
      });

  /// [accountUid]'s [deletionStatus], followed: a new listener hears the
  /// current status first, then every change — a record added or cleared by
  /// this service, a run requested, each page it removes, its end — and
  /// never the same status twice in a row. Broadcast; it never closes and
  /// never fails: a first read that cannot be made is logged and heard as
  /// the account's status with nothing pending — or what was last published
  /// — which the next change corrects (review G7).
  Stream<SyncDeletionStatus> deletionStatusOf(String accountUid) =>
      Stream.multi((listener) {
        SyncDeletionStatus? last;
        void add(SyncDeletionStatus status) {
          if (status == last) return;
          last = status;
          listener.add(status);
        }

        final subscription = _statusChanges.stream.listen((status) {
          if (status.accountUid == accountUid) add(status);
        });
        listener.onCancel = subscription.cancel;
        deletionStatus(accountUid).then(
          // A change published since the read began is newer than it.
          (status) => last == null ? add(status) : null,
          onError: (Object e, StackTrace st) {
            debugPrint('[SyncSpaceService] deletion status not read: $e\n$st');
            if (last != null) return;
            add(_statusOf(accountUid, _lastRecords(accountUid)));
          },
        );
      }, isBroadcast: true);

  /// Completes once no run is in flight or waiting — at once when none is.
  /// Never fails: a run's failure is its status's. What a test awaits after
  /// a request, and what a caller awaits that must not race a run.
  Future<void> deletionRunsIdle() async {
    while (_draining) {
      await _drained;
    }
  }

  /// [start]'s pass over [listed]: each marked space recorded, and the
  /// account's run requested when any is.
  Future<void> _recordMarked(
    String accountUid,
    List<SyncSpaceInfo> listed,
  ) async {
    final marked = [
      for (final space in listed)
        if (space.markedForDeletion)
          SyncPendingDeletion(space: space.ref, spaceName: space.name),
    ];
    if (marked.isEmpty) return;
    await _recordAndRequest(
      accountUid,
      (await _databases()).spaceRegistry,
      marked,
    );
  }

  /// The one path a deletion is recorded by, for [deleteCloudCopy] and
  /// [start] (review K7): [deletions] of [accountUid]'s spaces recorded
  /// install-wide, then [then] — [deleteCloudCopy]'s unbind — then the
  /// account's run requested. From the record on the status reads running
  /// with no failure, the last run's cleared, so no moment reads as a
  /// deletion stopped short (review G4).
  ///
  /// Throws what failed. A record that cannot be written puts the
  /// account's last run back as it was, its failure included, since nothing
  /// new was recorded to clear it; a failure of [then] leaves the deletions
  /// recorded, pending and not running, with no failure.
  Future<void> _recordAndRequest(
    String accountUid,
    SyncSpaceRegistry registry,
    List<SyncPendingDeletion> deletions, {
    Future<void> Function()? then,
  }) async {
    _recording[accountUid] = (_recording[accountUid] ?? 0) + 1;
    final previous = _runs[accountUid];
    final fresh = _requested(accountUid) ? null : _DeletionRun();
    if (fresh != null) _runs[accountUid] = fresh;
    try {
      try {
        for (final deletion in deletions) {
          await registry.addPendingDeletion(deletion);
        }
      } catch (_) {
        // Unless a request since replaced it with a run of its own.
        if (fresh != null && identical(_runs[accountUid], fresh)) {
          if (previous == null) {
            _runs.remove(accountUid);
          } else {
            _runs[accountUid] = previous;
          }
        }
        rethrow;
      }
      _publish(accountUid, registry);
      await then?.call();
    } catch (_) {
      _endRecording(accountUid);
      _publish(accountUid, registry);
      rethrow;
    }
    _endRecording(accountUid);
    _request(accountUid, registry);
  }

  /// [followAccounts]' resume of [accountUid]; logged, never thrown.
  ///
  /// Another account's own deletion still recorded is dropped first
  /// (cloud-multi-user-roadmap §6.1 d): one install deletes the account
  /// signed in, and that one no longer is. Its cloud copies stay recorded
  /// for it.
  Future<void> _resume(String accountUid) async {
    try {
      if (_disposed) return;
      // Judged before the first await, in the turn the emission arrived in:
      // that run may yet end on the moment this emission came back from.
      final attempted = _attempted.contains(accountUid);
      if (attempted && _runningFor == accountUid) _owed.add(accountUid);
      final registry = (await _databases()).spaceRegistry;
      final deleting = registry.pendingAccountDeletion();
      if (deleting != null && deleting != accountUid) {
        await registry.clearPendingAccountDeletion(deleting);
        _publish(deleting, registry);
      }
      if (attempted) return;
      if (_pendingOf(accountUid, registry).isEmpty) return;
      _request(accountUid, registry);
    } catch (e, st) {
      debugPrint('[SyncSpaceService] deletions not resumed: $e\n$st');
    }
  }

  /// Whether a run ended on [failure] for a reason of the moment — the
  /// account signed out or changed under it, or the link — rather than of
  /// the deletion, so the account's next appearance may resume it.
  static bool _momentary(SyncBindFailure? failure) =>
      failure == SyncBindFailure.permissionDenied ||
      failure == SyncBindFailure.offline;

  /// Whether [accountUid]'s run is in flight or waiting.
  bool _requested(String accountUid) =>
      _runningFor == accountUid || _waiting.contains(accountUid);

  void _endRecording(String accountUid) {
    final left = (_recording[accountUid] ?? 1) - 1;
    if (left > 0) {
      _recording[accountUid] = left;
    } else {
      _recording.remove(accountUid);
    }
  }

  /// [accountUid]'s run queued, unless it is in flight or waiting already,
  /// and the queue started if it is not running.
  void _request(String accountUid, SyncSpaceRegistry registry) {
    if (_disposed) return;
    _attempted.add(accountUid);
    if (_requested(accountUid)) return;
    _waiting.add(accountUid);
    _runs[accountUid] = _DeletionRun();
    _publish(accountUid, registry);
    if (_draining) return;
    _draining = true;
    _drained = _runAll();
  }

  /// Every waiting account's run, one at a time in the order asked. Clears
  /// [_draining] in the same turn it finds the queue empty, so a request
  /// after that starts a new loop rather than joining one that has ended.
  ///
  /// Never fails (review G6): [_run] catches its job's failures, and a throw
  /// past them — its tail's last status — ends that account's run with the
  /// failure, so the accounts behind it still run and none reads running
  /// with nothing in flight. A run that ended on the moment with a resume
  /// owed ([_owed]) is requested again, behind the accounts waiting.
  Future<void> _runAll() async {
    try {
      while (_waiting.isNotEmpty) {
        final accountUid = _runningFor = _waiting.removeAt(0);
        final run = _runs[accountUid]!;
        try {
          await _run(accountUid, run);
        } catch (e, st) {
          run.failure ??= _failureOf(e, st).failure;
          _runningFor = null;
          _publishWith(accountUid, _lastRecords(accountUid));
        }
        final owed = _owed.remove(accountUid);
        if (_momentary(run.failure)) {
          _attempted.remove(accountUid);
          if (owed && _followed == accountUid) await _resume(accountUid);
        }
      }
    } finally {
      _draining = false;
    }
  }

  /// One account's run; a failure of its job is [run]'s, and only its last
  /// status can throw, which [_runAll] takes. It ends by clearing
  /// [_runningFor], so the last status it publishes reads ended.
  ///
  /// A space a newer build wrote to cannot be finished by this one whatever
  /// the link does, so its record is passed over and the run goes on with
  /// the later ones, ending as [SyncBindFailure.appOutdated] with that
  /// record left; a failure of the link or the account stops it at once.
  ///
  /// With every record done and none passed over, an account that is itself
  /// being deleted is closed ([_closeAccount]); the marked spaces that
  /// finds are taken like any other record, so the loop goes round again.
  Future<void> _run(String accountUid, _DeletionRun run) async {
    SyncSpaceRegistry? registry;
    try {
      final known = registry = (await _databases()).spaceRegistry;
      final outdated = <SyncSpaceRef>{};
      while (true) {
        final pending = [
          for (final deletion in _pendingOf(accountUid, known))
            if (!outdated.contains(deletion.space)) deletion,
        ];
        if (pending.isEmpty) {
          if (outdated.isNotEmpty) break;
          final licence = run.licence;
          if (await _closeAccount(accountUid, run, known)) continue;
          // What arrived while the account's end was being judged found
          // this run in flight and asked for none of its own: a deletion
          // recorded meanwhile, or a [deleteAccount] call's licence. Each
          // call hands over one licence, so this never loops.
          final since = _pendingOf(accountUid, known);
          if (since.any((d) => !outdated.contains(d.space))) continue;
          if (run.licence != null && !identical(run.licence, licence)) continue;
          break;
        }
        final space = pending.first.space;
        _checkDisposed();
        final info = await _gateway.readSpace(space);
        if (info != null && info.markedForDeletion) {
          if (info.schema > DatabaseSchema.syncSchemaVersion) {
            outdated.add(space);
            continue;
          }
          await _emptyAndRemove(space, known, (page) {
            run.removed += page;
            _publish(accountUid, known);
          });
        } else {
          await known.clearPendingDeletion(space);
        }
        _publish(accountUid, known);
      }
      if (outdated.isNotEmpty) run.failure = SyncBindFailure.appOutdated;
    } on _Disposed {
      // Ended by [dispose], which nothing is published after.
    } catch (e, st) {
      run.failure = _failureOf(e, st).failure;
    }
    _runningFor = null;
    if (registry != null) {
      _publish(accountUid, registry);
    } else {
      _publishWith(accountUid, _lastRecords(accountUid));
    }
  }

  /// The account's own end, once [run] finds none of its records left
  /// (cloud-multi-user-roadmap §6.1 b, c): nothing unless [_mayClose] — the
  /// account is being deleted, [run] holds a licence still young enough,
  /// and no [deleteAccount] is still marking the account's spaces. Then the
  /// spaces are listed once more — data first, the account last — and only
  /// an empty listing lets the [AccountCloser] end the pairs, the invites
  /// and the account, after which the record is cleared and
  /// [accountsDeleted] names it.
  ///
  /// True when the listing held marked spaces, now recorded for the run to
  /// take. Everything else that keeps the account is a wait, never a
  /// failure: an unmarked space, made since the deletion was asked for —
  /// only a person marks one, so the licence ends there; the window passed,
  /// before the closer was called or by the server's own word; the deletion
  /// given up while this was under way, or a space of the account recorded
  /// meanwhile — both asked again after the listing and by the closer right
  /// before the account's delete. Anything else the closer throws is the
  /// run's failure.
  ///
  /// A wait takes back the licence this attempt began under and no other:
  /// one a [deleteAccount] call handed over meanwhile is that call's, and
  /// [_run] tries again under it.
  Future<bool> _closeAccount(
    String accountUid,
    _DeletionRun run,
    SyncSpaceRegistry registry,
  ) async {
    final closer = _closer;
    if (closer == null || !_mayClose(accountUid, run, registry)) return false;
    final licence = run.licence;
    void takeBack() {
      if (identical(run.licence, licence)) run.licence = null;
    }

    _checkDisposed();
    final left = await _gateway.listSpaces(accountUid);
    if (!_mayClose(accountUid, run, registry)) return false;
    if (left.isNotEmpty) {
      var marked = false;
      for (final space in left) {
        if (!space.markedForDeletion) {
          takeBack();
          continue;
        }
        marked = true;
        await registry.addPendingDeletion(
          SyncPendingDeletion(space: space.ref, spaceName: space.name),
        );
      }
      return marked;
    }
    _checkDisposed();
    try {
      await closer.close(
        accountUid,
        stillWanted: () =>
            _mayClose(accountUid, run, registry) &&
            _pendingOf(accountUid, registry).isEmpty,
      );
    } on AccountCloseException catch (e) {
      if (e.failure != AccountCloseFailure.recentSignInRequired &&
          e.failure != AccountCloseFailure.withdrawn) {
        rethrow;
      }
      takeBack();
      return false;
    }
    run.licence = null;
    await registry.clearPendingAccountDeletion(accountUid);
    if (!_disposed) _accountsDeleted.add(accountUid);
    return false;
  }

  /// Whether [run] may end [accountUid]'s account now: its deletion is
  /// still recorded, the run holds the licence of a [deleteAccount] call
  /// made no longer ago than [accountCloseWindow], and none is marking
  /// spaces.
  bool _mayClose(
    String accountUid,
    _DeletionRun run,
    SyncSpaceRegistry registry,
  ) {
    final licence = run.licence;
    return licence != null &&
        _now().difference(licence.at) <= accountCloseWindow &&
        registry.pendingAccountDeletion() == accountUid &&
        !_marking.containsKey(accountUid);
  }

  List<SyncPendingDeletion> _pendingOf(
    String accountUid,
    SyncSpaceRegistry registry,
  ) => [
    for (final pending in registry.pendingDeletions())
      if (pending.space.ownerUid == accountUid) pending,
  ];

  /// What the install records for [accountUid]: its unfinished cloud-copy
  /// deletions, and whether the account itself goes with them.
  _DeletionRecords _recordsOf(String accountUid, SyncSpaceRegistry registry) =>
      (
        pending: _pendingOf(accountUid, registry),
        account: registry.pendingAccountDeletion() == accountUid,
      );

  /// [accountUid]'s records as last published, for the status of a moment
  /// the registry cannot be read in.
  _DeletionRecords _lastRecords(String accountUid) {
    final last = _published[accountUid];
    return (
      pending: last?.pending ?? const [],
      account: last?.account ?? false,
    );
  }

  SyncDeletionStatus _statusOf(String accountUid, _DeletionRecords records) {
    final run = _runs[accountUid];
    return SyncDeletionStatus(
      accountUid: accountUid,
      pending: records.pending,
      running: _requested(accountUid) || _recording.containsKey(accountUid),
      removed: run?.removed ?? 0,
      failure: run?.failure,
      account: records.account,
    );
  }

  /// [accountUid]'s status sent to [deletionStatusOf]'s listeners when it
  /// changed since the last one sent.
  void _publish(String accountUid, SyncSpaceRegistry registry) =>
      _publishWith(accountUid, _recordsOf(accountUid, registry));

  void _publishWith(String accountUid, _DeletionRecords records) {
    if (_disposed) return;
    final status = _statusOf(accountUid, records);
    if (_published[accountUid] == status) return;
    _published[accountUid] = status;
    _statusChanges.add(status);
  }

  /// Every table of the registry emptied in pages of
  /// [SyncGateway.rowDeleteBatch], then the space document removed — last,
  /// since a row under a missing space can never be deleted — then the
  /// record cleared. A page that times out halves its table's page for the
  /// rest of the job; one that times out at a single document fails as
  /// offline. A page refused because another device removed the space
  /// meanwhile — two finishing one space — means the deletion is done
  /// (review F4).
  Future<void> _emptyAndRemove(
    SyncSpaceRef space,
    SyncSpaceRegistry registry,
    void Function(int page) removed,
  ) async {
    for (final synced in syncedTables) {
      var limit = SyncGateway.rowDeleteBatch;
      while (true) {
        final int count;
        _checkDisposed();
        try {
          count = await _gateway.deleteRows(space, synced.name, limit: limit);
        } on SyncGatewayException catch (e) {
          if (e.failure == SyncGatewayFailure.permissionDenied) {
            if (!await _spaceGone(space)) rethrow;
            await registry.clearPendingDeletion(space);
            return;
          }
          if (!e.timedOut || limit <= 1) rethrow;
          limit ~/= 2;
          continue;
        }
        if (count == 0) break;
        removed(count);
      }
    }
    _checkDisposed();
    await _gateway.deleteSpace(space);
    await registry.clearPendingDeletion(space);
  }

  /// Whether [space] reads as gone; a failed read is not proof of it.
  Future<bool> _spaceGone(SyncSpaceRef space) async {
    _checkDisposed();
    try {
      return await _gateway.readSpace(space) == null;
    } on SyncGatewayException {
      return false;
    }
  }

  /// Before each gateway call of a run: a disposed service's run ends there
  /// (review K8).
  void _checkDisposed() {
    if (_disposed) throw const _Disposed();
  }

  void _ensureKnownSchema(SyncSpaceInfo space) {
    if (space.schema > DatabaseSchema.syncSchemaVersion) {
      throw const SyncSpaceException(SyncBindFailure.appOutdated);
    }
  }

  /// A space gone from the cloud or marked for deletion is never bound.
  Future<void> _ensureLive(SyncSpaceRef space) async {
    final info = await _gateway.readSpace(space);
    if (info == null || info.markedForDeletion) {
      throw const SyncSpaceException(SyncBindFailure.spaceGone);
    }
  }

  Future<SyncSpaceInfo> _createAndBind({
    required String accountUid,
    required String name,
  }) async {
    final trimmed = name.trim();
    final size = trimmed.runes.length;
    if (size == 0 || size > maxSpaceNameLength) {
      throw const SyncSpaceException(SyncBindFailure.invalidSpaceName);
    }
    final db = await _database();
    final created = await _gateway.createSpace(
      ownerUid: accountUid,
      name: trimmed,
      deviceId: db.deviceId,
      schema: DatabaseSchema.syncSchemaVersion,
    );
    await _bind(created.ref, accountUid: accountUid);
    return created;
  }

  Future<void> _bind(SyncSpaceRef space, {required String accountUid}) async {
    await _ensureNotHeld(space);
    await (await _binding()).bind(space: space, accountUid: accountUid);
  }

  /// Refuses every bind for an account whose own deletion is recorded
  /// (cloud-multi-user-roadmap §6.1 b): a space made now could land between
  /// the run's last listing of the account's spaces and the account's
  /// delete, and nobody could reach it afterwards. The way on is the one
  /// the page names — finish the deletion, or sign out to give it up.
  Future<void> _ensureAccountStays(String accountUid) async {
    final registry = (await _databases()).spaceRegistry;
    if (registry.pendingAccountDeletion() == accountUid) {
      throw const SyncSpaceException(SyncBindFailure.accountDeleting);
    }
  }

  /// The refusals [SyncBindingService.bind] makes again inside its
  /// transaction, made first so a space is never created for a bind that
  /// cannot happen.
  Future<void> _ensureBindable() async {
    if (SyncSuspension.isSuspended) {
      throw const SyncSpaceException(SyncBindFailure.suspended);
    }
    if (await (await _binding()).read() != null) {
      throw const SyncSpaceException(SyncBindFailure.alreadyBound);
    }
  }

  Future<void> _ensureNotHeld(SyncSpaceRef space) async {
    final holder = await _holderOf(space);
    if (holder != null) {
      throw SyncSpaceException(
        SyncBindFailure.spaceHeldByAnotherDatabase,
        holderDatabase: holder,
      );
    }
  }

  Future<Map<SyncSpaceRef, String>> _heldBy(List<SyncSpaceInfo> spaces) async {
    final heldBy = <SyncSpaceRef, String>{};
    for (final space in spaces) {
      final holder = await _holderOf(space.ref);
      if (holder != null) heldBy[space.ref] = holder;
    }
    return heldBy;
  }

  /// The database of this install that holds [space], by one rule for the
  /// picker, Merge and Download (review BA-L1): another database's live
  /// claim, or the active database itself when its binding is to [space]. Its
  /// claim alone is never in the way — unbound, that claim is stale, a
  /// release that failed.
  Future<String?> _holderOf(SyncSpaceRef space) async {
    final databases = await _databases();
    final self = databases.getActiveDatabaseName();
    final other = await databases.spaceRegistry.holderOf(space, except: self);
    if (other != null) return other;
    final bound = await (await _binding()).read();
    final syncsIt =
        bound != null &&
        bound.spaceId == space.spaceId &&
        bound.ownerUid == space.ownerUid;
    return syncsIt ? self : null;
  }

  /// Back to [previous], then [leaving] deleted — only once the switch back
  /// has landed, so the open database is never the one deleted. Logged, not
  /// thrown: the caller reports the failure that brought it here.
  Future<void> _returnTo(String previous, {required String leaving}) async {
    try {
      final databases = await _databases();
      await databases.setActiveDatabaseName(previous);
      await databases.clearDownloadInFlight();
      await _database();
      await databases.deleteDatabase(leaving);
    } catch (e, st) {
      debugPrint('[SyncSpaceService] returning to "$previous" failed: $e\n$st');
    }
  }

  /// Every failure as a [SyncSpaceException]: the gateway's and the binding's
  /// typed ones mapped, anything else [SyncBindFailure.unknown].
  Future<T> _mapped<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on SyncSpaceException {
      rethrow;
    } catch (e, st) {
      throw _failureOf(e, st);
    }
  }

  /// [error] as the [SyncSpaceException] [_mapped] throws for it.
  static SyncSpaceException _failureOf(Object error, StackTrace stack) {
    switch (error) {
      case SyncSpaceException():
        return error;
      case SyncBindRefusal(:final reason, :final holderDatabase):
        return SyncSpaceException(switch (reason) {
          SyncBindRefusalReason.suspended => SyncBindFailure.suspended,
          SyncBindRefusalReason.alreadyBound => SyncBindFailure.alreadyBound,
          SyncBindRefusalReason.spaceHeldByAnotherDatabase =>
            SyncBindFailure.spaceHeldByAnotherDatabase,
        }, holderDatabase: holderDatabase);
      case SyncGatewayException(:final failure):
        return SyncSpaceException(switch (failure) {
          SyncGatewayFailure.offline => SyncBindFailure.offline,
          SyncGatewayFailure.quotaExhausted => SyncBindFailure.quotaExhausted,
          SyncGatewayFailure.permissionDenied =>
            SyncBindFailure.permissionDenied,
          SyncGatewayFailure.invalidData ||
          SyncGatewayFailure.unknown => SyncBindFailure.unknown,
        });
      // A stale sign-in and a withdrawn deletion never arrive here:
      // [_closeAccount] takes each as a wait, not a failure.
      case AccountCloseException(:final failure):
        return SyncSpaceException(switch (failure) {
          AccountCloseFailure.offline => SyncBindFailure.offline,
          AccountCloseFailure.permissionDenied =>
            SyncBindFailure.permissionDenied,
          AccountCloseFailure.recentSignInRequired ||
          AccountCloseFailure.withdrawn ||
          AccountCloseFailure.unknown => SyncBindFailure.unknown,
        });
      default:
        debugPrint('[SyncSpaceService] failed: $error\n$stack');
        return const SyncSpaceException(SyncBindFailure.unknown);
    }
  }
}

/// What ends a disposed service's run at its next gateway call.
class _Disposed implements Exception {
  const _Disposed();
}
