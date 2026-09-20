import '../models/app_permission.dart';

abstract class PermissionGateway {
  const PermissionGateway();

  List<AppPermission> get supported;

  bool get hasAppSettings;

  Future<Map<AppPermission, PermissionStatus>> statuses();

  bool canPrompt(AppPermission permission);

  Future<PermissionPromptResult> prompt(AppPermission permission);

  Future<bool> openSettings(AppPermission permission);

  Future<bool> openAppSettings();
}

class NoOpPermissionGateway extends PermissionGateway {
  const NoOpPermissionGateway();

  @override
  List<AppPermission> get supported => const [];

  @override
  bool get hasAppSettings => false;

  @override
  Future<Map<AppPermission, PermissionStatus>> statuses() async => const {};

  @override
  bool canPrompt(AppPermission permission) => false;

  @override
  Future<PermissionPromptResult> prompt(AppPermission permission) async =>
      PermissionPromptResult.blocked;

  @override
  Future<bool> openSettings(AppPermission permission) async => false;

  @override
  Future<bool> openAppSettings() async => false;
}
