import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:anta/models/app_permission.dart';
import 'package:anta/services/permission_gateway.dart';
import 'package:anta/services/permission_service.dart';

class FakePermissionGateway extends PermissionGateway {
  FakePermissionGateway({
    Map<AppPermission, PermissionStatus>? statuses,
    this.promptable = const {AppPermission.notifications},
    this.appSettings = true,
  }) : current = {...?statuses};

  final Map<AppPermission, PermissionStatus> current;
  final Set<AppPermission> promptable;
  final bool appSettings;

  final Map<AppPermission, PermissionPromptResult> promptResults = {};
  final List<AppPermission> prompts = [];
  final List<AppPermission> settingsOpens = [];
  int appSettingsOpens = 0;
  int statusReads = 0;
  bool settingsAvailable = true;
  Object? statusError;
  Completer<void>? promptGate;
  Completer<void>? statusGate;

  @override
  List<AppPermission> get supported => AppPermission.values;

  @override
  bool get hasAppSettings => appSettings;

  @override
  Future<Map<AppPermission, PermissionStatus>> statuses() async {
    statusReads++;
    final answer = {...current};
    final gate = statusGate;
    if (gate != null) await gate.future;
    final error = statusError;
    if (error != null) throw error;
    return answer;
  }

  @override
  bool canPrompt(AppPermission permission) => promptable.contains(permission);

  @override
  Future<PermissionPromptResult> prompt(AppPermission permission) async {
    prompts.add(permission);
    final gate = promptGate;
    if (gate != null) await gate.future;
    final result = promptResults[permission] ?? PermissionPromptResult.granted;
    if (result == PermissionPromptResult.granted) {
      current[permission] = PermissionStatus.granted;
    }
    return result;
  }

  @override
  Future<bool> openSettings(AppPermission permission) async {
    settingsOpens.add(permission);
    return settingsAvailable;
  }

  @override
  Future<bool> openAppSettings() async {
    appSettingsOpens++;
    return settingsAvailable;
  }
}

class MemoryPermissionPromptStore implements PermissionPromptStore {
  String? acknowledgement;
  bool launchPromptEnabled = true;
  Completer<void>? optionGate;

  @override
  Future<String?> readAcknowledgement() async => acknowledgement;

  @override
  Future<void> writeAcknowledgement(String value) async =>
      acknowledgement = value;

  @override
  Future<bool> readLaunchPromptEnabled() async {
    final gate = optionGate;
    if (gate != null) await gate.future;
    return launchPromptEnabled;
  }

  @override
  Future<void> writeLaunchPromptEnabled(bool value) async =>
      launchPromptEnabled = value;
}

const Map<AppPermission, PermissionStatus> allGranted = {
  AppPermission.notifications: PermissionStatus.granted,
  AppPermission.fullScreenIntent: PermissionStatus.granted,
  AppPermission.batteryOptimization: PermissionStatus.granted,
};

PermissionService permissionServiceOver(
  FakePermissionGateway gateway, {
  MemoryPermissionPromptStore? store,
  String deviceId = 'device-a',
  Stream<AppLifecycleState>? lifecycle,
}) {
  return PermissionService(
    gateway: gateway,
    store: store ?? MemoryPermissionPromptStore(),
    deviceId: () async => deviceId,
    lifecycle: lifecycle,
  );
}
