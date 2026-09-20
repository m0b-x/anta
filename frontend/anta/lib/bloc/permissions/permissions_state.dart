import 'package:equatable/equatable.dart';

import '../../models/app_permission.dart';

enum PermissionNoticeKind { request, batch, appSettings }

class PermissionNotice extends Equatable {
  const PermissionNotice({
    required this.serial,
    required this.kind,
    required this.outcome,
    this.permission,
  });

  final int serial;
  final PermissionNoticeKind kind;
  final PermissionRequestOutcome outcome;
  final AppPermission? permission;

  @override
  List<Object?> get props => [serial, kind, outcome, permission];
}

sealed class PermissionsState extends Equatable {
  const PermissionsState();

  PermissionSnapshot? get snapshotOrNull => null;

  @override
  List<Object?> get props => [];
}

final class PermissionsInitial extends PermissionsState {
  const PermissionsInitial();
}

final class PermissionsReady extends PermissionsState {
  const PermissionsReady({
    required this.snapshot,
    required this.launchPromptEnabled,
    required this.hasAppSettings,
    this.requesting,
    this.requestingAll = false,
    this.notice,
  });

  final PermissionSnapshot snapshot;
  final bool launchPromptEnabled;
  final bool hasAppSettings;
  final AppPermission? requesting;
  final bool requestingAll;
  final PermissionNotice? notice;

  bool get isBusy => requesting != null || requestingAll;

  @override
  PermissionSnapshot? get snapshotOrNull => snapshot;

  PermissionsReady copyWith({
    PermissionSnapshot? snapshot,
    bool? launchPromptEnabled,
    AppPermission? requesting,
    bool clearRequesting = false,
    bool? requestingAll,
    PermissionNotice? notice,
  }) {
    return PermissionsReady(
      snapshot: snapshot ?? this.snapshot,
      launchPromptEnabled: launchPromptEnabled ?? this.launchPromptEnabled,
      hasAppSettings: hasAppSettings,
      requesting: clearRequesting ? null : requesting ?? this.requesting,
      requestingAll: requestingAll ?? this.requestingAll,
      notice: notice ?? this.notice,
    );
  }

  @override
  List<Object?> get props => [
    snapshot,
    launchPromptEnabled,
    hasAppSettings,
    requesting,
    requestingAll,
    notice,
  ];
}
