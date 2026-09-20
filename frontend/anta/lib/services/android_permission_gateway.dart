import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/app_permission.dart';
import 'permission_gateway.dart';

class AndroidPermissionGateway extends PermissionGateway {
  AndroidPermissionGateway({
    required List<String> notificationChannelIds,
    AndroidFlutterLocalNotificationsPlugin? notifications,
    MethodChannel channel = const MethodChannel(channelName),
  }) : _notificationChannelIds = List.unmodifiable(notificationChannelIds),
       _notificationsOverride = notifications,
       _channel = channel;

  static const String channelName = 'com.alexzamfir.anta/permissions';

  static const Map<AppPermission, String> _wireNames = {
    AppPermission.notifications: 'notifications',
    AppPermission.exactAlarms: 'exactAlarms',
    AppPermission.fullScreenIntent: 'fullScreenIntent',
    AppPermission.batteryOptimization: 'batteryOptimization',
  };

  static const Map<AppPermission, String> _settingsMethods = {
    AppPermission.notifications: 'openNotificationSettings',
    AppPermission.exactAlarms: 'openExactAlarmSettings',
    AppPermission.fullScreenIntent: 'openFullScreenIntentSettings',
    AppPermission.batteryOptimization: 'openAppSettings',
  };

  final List<String> _notificationChannelIds;
  final AndroidFlutterLocalNotificationsPlugin? _notificationsOverride;
  final MethodChannel _channel;

  AndroidFlutterLocalNotificationsPlugin? get _notifications =>
      _notificationsOverride ??
      FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

  @override
  List<AppPermission> get supported => AppPermission.values;

  @override
  bool get hasAppSettings => true;

  @override
  Future<Map<AppPermission, PermissionStatus>> statuses() async {
    final Map<String, bool?>? raw;
    try {
      raw = await _channel.invokeMapMethod<String, bool?>('status', {
        'channels': _notificationChannelIds,
      });
    } catch (e) {
      debugPrint('[AndroidPermissionGateway] status failed: $e');
      return _allUnknown;
    }
    if (raw == null) return _allUnknown;
    return {
      for (final entry in _wireNames.entries)
        if (raw.containsKey(entry.value))
          entry.key: switch (raw[entry.value]) {
            true => PermissionStatus.granted,
            false => PermissionStatus.denied,
            null => PermissionStatus.unknown,
          },
    };
  }

  Map<AppPermission, PermissionStatus> get _allUnknown => {
    for (final permission in supported) permission: PermissionStatus.unknown,
  };

  @override
  bool canPrompt(AppPermission permission) =>
      permission == AppPermission.notifications;

  @override
  Future<PermissionPromptResult> prompt(AppPermission permission) async {
    if (!canPrompt(permission)) return PermissionPromptResult.blocked;
    final explainedBefore = await _shouldExplainNotifications();
    bool granted;
    try {
      granted = await _notifications?.requestNotificationsPermission() ?? false;
    } catch (e) {
      debugPrint('[AndroidPermissionGateway] prompt failed: $e');
      return PermissionPromptResult.blocked;
    }
    if (granted) return PermissionPromptResult.granted;
    final answered = explainedBefore || await _shouldExplainNotifications();
    return answered
        ? PermissionPromptResult.denied
        : PermissionPromptResult.blocked;
  }

  Future<bool> _shouldExplainNotifications() async {
    try {
      return await _channel.invokeMethod<bool>('shouldExplainNotifications') ??
          false;
    } catch (e) {
      debugPrint('[AndroidPermissionGateway] rationale query failed: $e');
      return false;
    }
  }

  @override
  Future<bool> openSettings(AppPermission permission) =>
      _open(_settingsMethods[permission]!);

  @override
  Future<bool> openAppSettings() => _open('openAppSettings');

  Future<bool> _open(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } catch (e) {
      debugPrint('[AndroidPermissionGateway] $method failed: $e');
      return false;
    }
  }
}
