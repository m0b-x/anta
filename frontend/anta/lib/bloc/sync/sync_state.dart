import 'package:equatable/equatable.dart';

import '../../models/app_user.dart';
import '../../services/sync/sync_gateway.dart';
import '../../services/sync/sync_space_service.dart';
import '../../services/sync/sync_status.dart';
import '../../utils/auth_error.dart';

export '../../services/sync/sync_gateway.dart'
    show SyncGatewayFailure, SyncSpaceInfo;
export '../../services/sync/sync_space_registry.dart' show SyncPendingDeletion;
export '../../services/sync/sync_space_service.dart'
    show SyncBindFailure, SyncDeletionStatus;
export '../../services/sync/sync_status.dart'
    show
        SyncActivity,
        SyncHeldItem,
        SyncHeldKind,
        SyncHeldReason,
        SyncPause,
        SyncStatus;

/// Where "Sync this database" — or "Stop syncing" — stands, carried by the
/// account states so a status emit never drops the picker from under it.
sealed class SyncBindFlow extends Equatable {
  const SyncBindFlow();

  /// A step in flight, during which another bind or stop is ignored.
  bool get isBusy => false;

  @override
  List<Object?> get props => [];
}

final class SyncBindIdle extends SyncBindFlow {
  /// The database a download created and switched to, once it is bound — so
  /// the page can say the app now shows it; null otherwise.
  final String? switchedToDatabase;

  const SyncBindIdle({this.switchedToDatabase});

  @override
  List<Object?> get props => [switchedToDatabase];
}

/// Reading the account's spaces — and, on D1's paths, creating or binding
/// in the same tap.
final class SyncBindChecking extends SyncBindFlow {
  const SyncBindChecking();

  @override
  bool get isBusy => true;
}

/// The picker (D2): merge into one of [spaces], download one into a new
/// database, or upload as a new space.
final class SyncBindPicking extends SyncBindFlow {
  /// The account's spaces, most recently written first.
  final List<SyncSpaceInfo> spaces;

  /// Whether this database holds anything a person made.
  final bool holdsData;

  /// The spaces another database of this install holds, with its name;
  /// merging into or downloading one of them is refused.
  final Map<SyncSpaceRef, String> heldBy;

  const SyncBindPicking({
    required this.spaces,
    required this.holdsData,
    this.heldBy = const {},
  });

  @override
  List<Object?> get props => [spaces, holdsData, heldBy];
}

/// The picker's choice being carried out.
final class SyncBindBinding extends SyncBindFlow {
  const SyncBindBinding();

  @override
  bool get isBusy => true;
}

/// "Stop syncing this database" being carried out.
final class SyncBindStopping extends SyncBindFlow {
  const SyncBindStopping();

  @override
  bool get isBusy => true;
}

/// "Delete cloud copy" being carried out (cloud-multi-user-roadmap §5): the
/// mark and the unbind only — the emptying that follows is the service's
/// background run, which [SyncSignedIn.deletion] follows.
final class SyncBindDeleting extends SyncBindFlow {
  const SyncBindDeleting();

  @override
  bool get isBusy => true;
}

/// "Delete account" being started (cloud-multi-user-roadmap §6.1): the
/// sign-in asked again, then every cloud copy marked and this database
/// unbound — the emptying and the account's own end are the service's
/// background run, which [SyncSignedIn.deletion] follows.
final class SyncAccountDeleting extends SyncBindFlow {
  const SyncAccountDeleting();

  @override
  bool get isBusy => true;
}

/// The last step failed; stays until it is dismissed or the flow starts
/// again.
final class SyncBindFailed extends SyncBindFlow {
  final SyncBindFailure failure;

  /// For [SyncBindFailure.spaceHeldByAnotherDatabase]: the database holding
  /// the space.
  final String? holderDatabase;

  /// Whether the step that failed was "Delete cloud copy" — nothing changed,
  /// still bound: the page says so on the Delete row, not as the stop's
  /// failure a bound section would otherwise take it for. A background
  /// run's failure is never a flow's; [SyncDeletionStatus.failure] carries
  /// it.
  final bool deleting;

  /// Whether what failed was "Delete account" — the sign-in asked again, or
  /// the step after it: the page says so on that row, and never as a
  /// stop's or a cloud copy's failure.
  final bool account;

  const SyncBindFailed(
    this.failure, {
    this.holderDatabase,
    this.deleting = false,
    this.account = false,
  });

  @override
  List<Object?> get props => [failure, holderDatabase, deleting, account];
}

/// The one rule "Delete cloud copy" follows, read by the page to hold its
/// row and by the bloc to refuse the request (cloud-multi-user-roadmap §5,
/// review S3, S6), so the two cannot drift.
extension SyncCloudCopyDeletion on SyncStatus {
  /// Whether deleting this database's cloud copy can work for the account
  /// signed in: only a bound database has one, and three pauses forbid it —
  /// another account's space is not this one's to delete, the service
  /// always refuses an outdated app, and a copy marked or gone is left by
  /// "Stop syncing". Under `noAccess` and the quota pause it stays a way
  /// out: a copy that will not sync may still be deleted.
  bool get canDeleteCloudCopy =>
      binding != null && !_cloudCopyDeletionPauses.contains(pause);
}

const Set<SyncPause> _cloudCopyDeletionPauses = {
  SyncPause.accountMismatch,
  SyncPause.appOutdated,
  SyncPause.spaceDeleted,
};

sealed class SyncState extends Equatable {
  const SyncState();

  /// Whether a bind or stop step is running, whichever account it started
  /// on: an account change mid-step shows the new account's idle flow, and
  /// the page must still read busy and hold until the step has settled
  /// (review U-1, U-5). Only the account states can be shown during one.
  bool get stepInFlight => false;

  /// This state with [stepInFlight] set to [value], where it carries one.
  SyncState withStepInFlight(bool value) => this;

  @override
  List<Object?> get props => [];
}

final class SyncInitial extends SyncState {
  const SyncInitial();
}

/// Terminal whenever the bound `AuthService` cannot sign in — an unsupported
/// platform, or Firebase init failed and DI degraded to the no-op binding.
final class SyncUnavailable extends SyncState {
  const SyncUnavailable();
}

final class SyncSignedOut extends SyncState {
  final SyncStatus status;

  /// Only "Stop syncing" runs signed out (D5 A), so only idle, stopping or
  /// its failure — and a download's switch when the account signed out
  /// while it ran, whose restart prompt must still come (final review U-1).
  final SyncBindFlow flow;

  @override
  final bool stepInFlight;

  /// Whether this is the signed-out state an account's deletion ended in
  /// (cloud-multi-user-roadmap §6.1): the page says "Account deleted" once,
  /// as it turns true. The states that follow carry false again.
  final bool accountDeleted;

  const SyncSignedOut({
    this.status = SyncStatus.empty,
    this.flow = const SyncBindIdle(),
    this.stepInFlight = false,
    this.accountDeleted = false,
  });

  @override
  SyncSignedOut withStepInFlight(bool value) => SyncSignedOut(
    status: status,
    flow: flow,
    stepInFlight: value,
    accountDeleted: accountDeleted,
  );

  @override
  List<Object?> get props => [status, flow, stepInFlight, accountDeleted];
}

final class SyncSigningIn extends SyncState {
  const SyncSigningIn();
}

final class SyncSignedIn extends SyncState {
  final AppUser user;
  final SyncStatus status;
  final SyncBindFlow flow;

  @override
  final bool stepInFlight;

  /// Whether [status] is one a read or the engine delivered, rather than the
  /// [SyncStatus.empty] the account is first shown with: an unbound
  /// database reads as that same empty status, so only this tells the
  /// drawer's line to wait instead of saying "Not syncing" for a bound one
  /// (§12 (k) of `docs/cloud-sync-phase-02-own-space.md`). A read that timed
  /// out leaves it false.
  final bool statusRead;

  /// Where this account's cloud-copy deletions stand on this install, as
  /// the service's background run reports them: the page ends with a
  /// deletion section while one is pending or running. Null until the first
  /// status arrives; signed out there is none — only their owner may finish
  /// them.
  final SyncDeletionStatus? deletion;

  const SyncSignedIn(
    this.user, {
    this.status = SyncStatus.empty,
    this.flow = const SyncBindIdle(),
    this.stepInFlight = false,
    this.statusRead = false,
    this.deletion,
  });

  @override
  SyncSignedIn withStepInFlight(bool value) => SyncSignedIn(
    user,
    status: status,
    flow: flow,
    stepInFlight: value,
    statusRead: statusRead,
    deletion: deletion,
  );

  /// This state with [statusRead] set to [value].
  SyncSignedIn withStatusRead(bool value) => SyncSignedIn(
    user,
    status: status,
    flow: flow,
    stepInFlight: stepInFlight,
    statusRead: value,
    deletion: deletion,
  );

  /// This state with [deletion] set to [value].
  SyncSignedIn withDeletion(SyncDeletionStatus? value) => SyncSignedIn(
    user,
    status: status,
    flow: flow,
    stepInFlight: stepInFlight,
    statusRead: statusRead,
    deletion: value,
  );

  @override
  List<Object?> get props => [
    user,
    status,
    flow,
    stepInFlight,
    statusRead,
    deletion,
  ];
}

/// The account change a [SyncFailure] came from.
enum SyncAccountAction { signIn, signOut }

final class SyncFailure extends SyncState {
  final AuthError error;

  /// A failed sign-out leaves the user signed in, so the page words it as
  /// the sign-out's and offers Sign out again rather than a sign-in.
  final SyncAccountAction action;

  /// The account a failed sign-out left signed in, which its row keeps
  /// naming so it stays the signed-in row's shape (review D3-2).
  final AppUser? user;

  /// [user]'s cloud-copy deletions, as [SyncSignedIn.deletion] carries them:
  /// the account is still signed in, and its deletion row must go on
  /// following the run (review K3). Null without a [user].
  final SyncDeletionStatus? deletion;

  const SyncFailure(
    this.error, {
    this.action = SyncAccountAction.signIn,
    this.user,
    this.deletion,
  });

  /// This state with [deletion] set to [value].
  SyncFailure withDeletion(SyncDeletionStatus? value) =>
      SyncFailure(error, action: action, user: user, deletion: value);

  @override
  List<Object?> get props => [error, action, user, deletion];
}
