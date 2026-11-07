import 'package:equatable/equatable.dart';

import '../../models/app_user.dart';
import '../../services/sync/sync_gateway.dart';
import '../../services/sync/sync_space_service.dart';
import '../../services/sync/sync_status.dart';
import '../../utils/auth_error.dart';

export '../../services/sync/sync_gateway.dart'
    show SyncGatewayFailure, SyncSpaceInfo;
export '../../services/sync/sync_space_service.dart' show SyncBindFailure;
export '../../services/sync/sync_status.dart'
    show SyncActivity, SyncPause, SyncStatus;

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

/// The last step failed; stays until it is dismissed or the flow starts
/// again.
final class SyncBindFailed extends SyncBindFlow {
  final SyncBindFailure failure;

  /// For [SyncBindFailure.spaceHeldByAnotherDatabase]: the database holding
  /// the space.
  final String? holderDatabase;

  const SyncBindFailed(this.failure, {this.holderDatabase});

  @override
  List<Object?> get props => [failure, holderDatabase];
}

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

  const SyncSignedOut({
    this.status = SyncStatus.empty,
    this.flow = const SyncBindIdle(),
    this.stepInFlight = false,
  });

  @override
  SyncSignedOut withStepInFlight(bool value) =>
      SyncSignedOut(status: status, flow: flow, stepInFlight: value);

  @override
  List<Object?> get props => [status, flow, stepInFlight];
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

  const SyncSignedIn(
    this.user, {
    this.status = SyncStatus.empty,
    this.flow = const SyncBindIdle(),
    this.stepInFlight = false,
    this.statusRead = false,
  });

  @override
  SyncSignedIn withStepInFlight(bool value) => SyncSignedIn(
    user,
    status: status,
    flow: flow,
    stepInFlight: value,
    statusRead: statusRead,
  );

  /// This state with [statusRead] set to [value].
  SyncSignedIn withStatusRead(bool value) => SyncSignedIn(
    user,
    status: status,
    flow: flow,
    stepInFlight: stepInFlight,
    statusRead: value,
  );

  @override
  List<Object?> get props => [user, status, flow, stepInFlight, statusRead];
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

  const SyncFailure(
    this.error, {
    this.action = SyncAccountAction.signIn,
    this.user,
  });

  @override
  List<Object?> get props => [error, action, user];
}
