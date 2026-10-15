import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';

import '../l10n/app_localizations.dart';
import '../models/app_permission.dart';
import '../services/app_navigator.dart';
import '../services/permission_service.dart';
import '../services/settings_service.dart';
import '../utils/custom_snackbar.dart';

/// What every surface that saves an alert does next about the permissions it
/// needs to fire — the event editor's flow and the category editor alike, so
/// the prompt's latch and the message are one behaviour wherever an alert is
/// set.
abstract final class AlertPermissionCheck {
  /// Raises the system notification prompt the **first** time an alert is
  /// saved (§6.1), and says so every time an alert is saved that cannot ring —
  /// which is what it answers: whether it had to.
  ///
  /// The prompt is contextual and latched: it follows a user action, the alert
  /// is already persisted so a refusal costs nothing but the ring, and a
  /// denial is never asked about again from here — the launch dialog and the
  /// Permissions page are where it can still be granted. The snackbar is not
  /// latched, because an alert saved without an essential permission is an
  /// alert that silently never fires. Everything here is best-effort; a build
  /// with no permission service simply never asks.
  ///
  /// [context] must outlive the surface that saved: the message and its
  /// Review action are raised on it after that surface has closed.
  static Future<bool> afterSave(BuildContext context) async {
    try {
      if (!GetIt.I.isRegistered<PermissionService>()) return false;
      final permissions = GetIt.I<PermissionService>();
      final settings = await SettingsService.getInstance();
      var snapshot = await permissions.refresh();
      if (!await settings.getAlertNotificationsAsked()) {
        if (snapshot.isMissing(AppPermission.notifications)) {
          snapshot = await permissions.promptFor(const [
            AppPermission.notifications,
          ]);
        }
        await settings.setAlertNotificationsAsked(true);
      }
      if (!snapshot.needsAttention) return false;
      if (!context.mounted) return true;
      final l10n = AppLocalizations.of(context)!;
      CustomSnackbar.showWithAction(
        context,
        message: l10n.permissionsAlertBlocked,
        actionLabel: l10n.permissionsReview,
        onAction: () {
          if (context.mounted) AppNavigator.toPermissions(context);
        },
      );
      return true;
    } catch (e) {
      debugPrint('[AlertPermissionCheck] alert permission check skipped: $e');
      return false;
    }
  }
}
