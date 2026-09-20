import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/app_permission.dart';

abstract final class PermissionPresentation {
  static IconData iconOf(AppPermission permission) => switch (permission) {
    AppPermission.notifications => Icons.notifications_active_outlined,
    AppPermission.exactAlarms => Icons.alarm_on_rounded,
    AppPermission.fullScreenIntent => Icons.fullscreen_rounded,
    AppPermission.batteryOptimization => Icons.battery_saver_rounded,
  };

  static String titleOf(AppLocalizations l10n, AppPermission permission) =>
      switch (permission) {
        AppPermission.notifications => l10n.alertsNotifications,
        AppPermission.exactAlarms => l10n.permissionExactAlarms,
        AppPermission.fullScreenIntent => l10n.alertsFullScreenAlarms,
        AppPermission.batteryOptimization => l10n.alertsBattery,
      };

  static String descriptionOf(
    AppLocalizations l10n,
    AppPermission permission,
  ) => switch (permission) {
    AppPermission.notifications => l10n.alertsNotificationsDesc,
    AppPermission.exactAlarms => l10n.permissionExactAlarmsDesc,
    AppPermission.fullScreenIntent => l10n.alertsFullScreenAlarmsDesc,
    AppPermission.batteryOptimization => l10n.alertsBatteryDesc,
  };

  static String actionOf(AppLocalizations l10n, PermissionEntry entry) =>
      entry.canPrompt ? l10n.alertsTurnOn : l10n.alertsOpenSettings;
}

class PermissionTile extends StatelessWidget {
  const PermissionTile({
    super.key,
    required this.entry,
    required this.title,
    required this.description,
    required this.onRequest,
    this.busy = false,
  });

  final PermissionEntry entry;
  final Widget title;
  final Widget? description;
  final VoidCallback? onRequest;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final blocking = entry.isMissing && entry.permission.isEssential;

    final Widget trailing;
    switch (entry.status) {
      case PermissionStatus.granted:
        trailing = Chip(
          label: Text(l10n.alertsPermissionOn),
          visualDensity: VisualDensity.compact,
        );
      case PermissionStatus.denied:
        final label = Text(PermissionPresentation.actionOf(l10n, entry));
        final onPressed = busy ? null : onRequest;
        trailing = blocking
            ? FilledButton.tonal(onPressed: onPressed, child: label)
            : TextButton(onPressed: onPressed, child: label);
      case PermissionStatus.unknown:
        trailing = TextButton(
          onPressed: busy ? null : onRequest,
          child: Text(l10n.alertsOpenSettings),
        );
      case PermissionStatus.notApplicable:
        trailing = Text(
          l10n.notSupportedOnPlatform,
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        );
    }

    return ListTile(
      leading: Icon(
        PermissionPresentation.iconOf(entry.permission),
        color: blocking ? colorScheme.error : colorScheme.primary,
      ),
      title: title,
      subtitle: description,
      trailing: trailing,
    );
  }
}
