import 'package:flutter/material.dart';

import '../constants/form_metrics.dart';
import '../l10n/app_localizations.dart';
import '../models/app_permission.dart';
import 'settings_section_list.dart';

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

    // The status, or the step that fixes it, is the row's value and the
    // request the row's tap: a button beside the title was laid out first
    // and squeezed it at a large text scale (S5). A missing essential keeps
    // its weight through the error colour, on the glyph and the value.
    final String value;
    final VoidCallback? onTap;
    final Color valueColor;
    switch (entry.status) {
      case PermissionStatus.granted:
        value = l10n.alertsPermissionOn;
        onTap = null;
        valueColor = colorScheme.onSurfaceVariant;
      case PermissionStatus.denied:
        value = PermissionPresentation.actionOf(l10n, entry);
        onTap = onRequest;
        valueColor = blocking ? colorScheme.error : colorScheme.primary;
      case PermissionStatus.unknown:
        value = l10n.alertsOpenSettings;
        onTap = onRequest;
        valueColor = colorScheme.primary;
      case PermissionStatus.notApplicable:
        value = l10n.notSupportedOnPlatform;
        onTap = null;
        valueColor = colorScheme.onSurfaceVariant;
    }
    // Only a row with something to do waits on a request in flight.
    final enabled = onTap == null || !busy;

    return SettingsYieldingTile(
      leading: Icon(
        PermissionPresentation.iconOf(entry.permission),
        color: blocking ? colorScheme.error : colorScheme.primary,
      ),
      title: title,
      subtitle: description,
      value: value,
      trailing: (maxWidth) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Text(
          value,
          style: TextStyle(
            color: enabled
                ? valueColor
                : colorScheme.onSurface.withValues(
                    alpha: FormMetrics.disabledOpacity,
                  ),
          ),
        ),
      ),
      onTap: onTap,
      enabled: enabled,
    );
  }
}
