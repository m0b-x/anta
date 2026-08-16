import 'package:equatable/equatable.dart';

import '../../models/app_user.dart';

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

/// Fed from the [AuthService] subscription rather than the UI, so a sign-in
/// that happens elsewhere (token expiry, sign-out on another screen) still
/// moves this bloc.
final class AuthStateChanged extends SyncEvent {
  final AppUser? user;

  const AuthStateChanged(this.user);

  @override
  List<Object?> get props => [user];
}
