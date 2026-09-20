import 'package:equatable/equatable.dart';

import '../../models/app_permission.dart';

sealed class PermissionsEvent extends Equatable {
  const PermissionsEvent();

  @override
  List<Object?> get props => [];
}

final class PermissionsStarted extends PermissionsEvent {
  const PermissionsStarted();
}

final class PermissionsRefreshRequested extends PermissionsEvent {
  const PermissionsRefreshRequested();
}

final class PermissionRequested extends PermissionsEvent {
  final AppPermission permission;

  const PermissionRequested(this.permission);

  @override
  List<Object?> get props => [permission];
}

final class PromptablePermissionsRequested extends PermissionsEvent {
  const PromptablePermissionsRequested();
}

final class AppSettingsRequested extends PermissionsEvent {
  const AppSettingsRequested();
}

final class LaunchPromptToggled extends PermissionsEvent {
  final bool enabled;

  const LaunchPromptToggled(this.enabled);

  @override
  List<Object?> get props => [enabled];
}

final class PermissionSnapshotChanged extends PermissionsEvent {
  final PermissionSnapshot snapshot;

  const PermissionSnapshotChanged(this.snapshot);

  @override
  List<Object?> get props => [snapshot];
}
