import 'package:equatable/equatable.dart';

import '../../models/app_user.dart';

sealed class SyncState extends Equatable {
  const SyncState();

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
  const SyncSignedOut();
}

final class SyncSigningIn extends SyncState {
  const SyncSigningIn();
}

final class SyncSignedIn extends SyncState {
  final AppUser user;

  const SyncSignedIn(this.user);

  @override
  List<Object?> get props => [user];
}

final class SyncFailure extends SyncState {
  final String message;

  const SyncFailure(this.message);

  @override
  List<Object?> get props => [message];
}
