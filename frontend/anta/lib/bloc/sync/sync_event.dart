import 'package:equatable/equatable.dart';

import '../../models/app_user.dart';
import '../../services/sync/sync_status.dart';

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
