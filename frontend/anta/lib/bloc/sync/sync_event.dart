import 'package:equatable/equatable.dart';

import '../../models/app_user.dart';
import '../../services/sync/sync_cadence.dart';
import 'sync_state.dart';

sealed class SyncEvent extends Equatable {
  const SyncEvent();

  @override
  List<Object?> get props => [];
}

final class LoadSyncStatus extends SyncEvent {
  const LoadSyncStatus();
}

final class SignInRequested extends SyncEvent {
  const SignInRequested();
}

final class SignOutRequested extends SyncEvent {
  const SignOutRequested();
}

/// Re-reads the sync status while the account stays as it is — after the
/// outbox or the binding changed.
final class RefreshSyncStatus extends SyncEvent {
  const RefreshSyncStatus();
}

/// "Sync now": one full run of the engine — pull every table, then drain.
final class SyncNowRequested extends SyncEvent {
  const SyncNowRequested();
}

/// "Sync this database" (D1 A): signed in, either bound in the tap — the
/// account's first space created, or its one space bound by a database that
/// holds nothing — or the picker's data in [SyncBindPicking].
final class SyncThisDatabaseRequested extends SyncEvent {
  const SyncThisDatabaseRequested();
}

/// The picker's "Merge this database into the space" (D2 A).
final class MergeIntoSpaceRequested extends SyncEvent {
  final SyncSpaceInfo space;

  const MergeIntoSpaceRequested(this.space);

  @override
  List<Object?> get props => [space];
}

/// The picker's "Download the space into a new database" (D2 A): the app
/// switches to the new database, which [SyncBindIdle.switchedToDatabase]
/// names once it is bound.
final class DownloadSpaceRequested extends SyncEvent {
  final SyncSpaceInfo space;

  const DownloadSpaceRequested(this.space);

  @override
  List<Object?> get props => [space];
}

/// The picker's "Upload as a new space" (D2 A), named [name] — this
/// database's name when null.
final class UploadAsNewSpaceRequested extends SyncEvent {
  final String? name;

  const UploadAsNewSpaceRequested({this.name});

  @override
  List<Object?> get props => [name];
}

/// The picker closed without a choice, a failure or a download's switch
/// acknowledged: the flow goes back to a plain idle.
final class BindFlowDismissed extends SyncEvent {
  const BindFlowDismissed();
}

/// "Stop syncing this database" (D6 A): signed in, paused on another
/// account (D5 A's way out) or signed out alike.
final class StopSyncingRequested extends SyncEvent {
  const StopSyncingRequested();
}

/// "Delete cloud copy" (cloud-multi-user-roadmap §5): the space this
/// database syncs with removed from the account for good, nothing on this
/// device touched. Signed in only — the space's owner deletes it.
final class DeleteCloudCopyRequested extends SyncEvent {
  const DeleteCloudCopyRequested();
}

/// "Finish deleting": every deletion the signed-in account began on this
/// install and did not finish, taken to its end — confirmed when it began.
/// It only asks the service's background run; the binding and the engine
/// stay as they are.
final class FinishDeletingRequested extends SyncEvent {
  const FinishDeletingRequested();
}

/// "Delete account", and "Finish deleting account" while one waits
/// (cloud-multi-user-roadmap §6.1): the sign-in asked again, then every
/// cloud copy of the signed-in account marked for deletion, this database
/// unbound when it syncs with one, and the account recorded as going once
/// they are gone. Nothing on this device is touched; the emptying and the
/// account's end are the service's background run.
final class DeleteAccountRequested extends SyncEvent {
  const DeleteAccountRequested();
}

/// Fed from the service as it deletes the account [uid], so the signed-out
/// state its session ends in can say what happened.
final class SyncAccountDeleted extends SyncEvent {
  final String uid;

  const SyncAccountDeleted(this.uid);

  @override
  List<Object?> get props => [uid];
}

/// Fed from the service's deletion status of the account signed in, so a
/// background run's progress and end reach the page.
final class SyncDeletionStatusChanged extends SyncEvent {
  final SyncDeletionStatus status;

  const SyncDeletionStatusChanged(this.status);

  @override
  List<Object?> get props => [status];
}

/// The Sync section's "Sync automatically" switch (record §13): stored
/// through the engine, which applies it to the session at once.
final class SyncCadenceChanged extends SyncEvent {
  final SyncCadence cadence;

  const SyncCadenceChanged(this.cadence);

  @override
  List<Object?> get props => [cadence];
}

/// Fed from the engine's status stream, so a run's progress, pause or
/// failure reaches the page while the account stays as it is.
final class SyncEngineStatusChanged extends SyncEvent {
  final SyncStatus status;

  const SyncEngineStatusChanged(this.status);

  @override
  List<Object?> get props => [status];
}

/// Fed from the [AuthService] subscription rather than the UI, so a sign-in
/// that happens elsewhere (token expiry, sign-out on another screen) still
/// moves this bloc.
final class AuthStateChanged extends SyncEvent {
  final AppUser? user;

  const AuthStateChanged(this.user);

  @override
  List<Object?> get props => [user];
}
