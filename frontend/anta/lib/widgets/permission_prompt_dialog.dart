import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/permissions/permissions_bloc.dart';
import '../constants/app_spacing.dart';
import '../constants/semantics_ids.dart';
import '../l10n/app_localizations.dart';
import '../models/app_permission.dart';
import '../services/app_navigator.dart';
import '../services/permission_service.dart';
import '../utils/custom_snackbar.dart';
import 'automation_id.dart';
import 'permission_tile.dart';

enum PermissionPromptChoice { notNow, done, review }

abstract final class PermissionLaunchPrompt {
  static Future<PermissionPromptChoice?> maybeShow({
    required PermissionService service,
    required BuildContext? Function() context,
    required bool Function() isInterrupted,
  }) async {
    if (isInterrupted()) return null;
    final snapshot = await service.launchPromptSnapshot();
    if (snapshot == null || isInterrupted()) return null;
    final target = context();
    if (target == null || !target.mounted) return null;
    return show(target, service: service, snapshot: snapshot);
  }

  static Future<PermissionPromptChoice?> show(
    BuildContext context, {
    required PermissionService service,
    required PermissionSnapshot snapshot,
  }) async {
    final choice = await showDialog<PermissionPromptChoice>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BlocProvider<PermissionsBloc>(
        create: (_) =>
            PermissionsBloc(service: service)..add(const PermissionsStarted()),
        child: PermissionPromptDialog(initialSnapshot: snapshot),
      ),
    );
    if (choice == null) return null;
    await service.acknowledgeLaunchPrompt();
    if (!context.mounted) return choice;
    switch (choice) {
      case PermissionPromptChoice.notNow:
        break;
      case PermissionPromptChoice.done:
        CustomSnackbar.showSuccess(
          context,
          AppLocalizations.of(context)!.permissionsAllSet,
        );
      case PermissionPromptChoice.review:
        unawaited(AppNavigator.toPermissions(context));
    }
    return choice;
  }
}

class PermissionPromptDialog extends StatelessWidget {
  const PermissionPromptDialog({super.key, required this.initialSnapshot});

  final PermissionSnapshot initialSnapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return BlocConsumer<PermissionsBloc, PermissionsState>(
      listenWhen: (previous, current) =>
          current is PermissionsReady &&
          current.notice?.kind == PermissionNoticeKind.batch &&
          (previous is! PermissionsReady ||
              previous.notice?.serial != current.notice?.serial),
      listener: (context, state) {
        final missing = state.snapshotOrNull?.hasMissing ?? true;
        Navigator.of(context).pop(
          missing ? PermissionPromptChoice.review : PermissionPromptChoice.done,
        );
      },
      builder: (context, state) {
        final missing = (state.snapshotOrNull ?? initialSnapshot).missing;
        final busy = state is! PermissionsReady || state.isBusy;
        return AlertDialog(
          icon: Icon(
            Icons.verified_user_rounded,
            size: 48,
            color: theme.colorScheme.primary,
          ),
          title: Text(l10n.permissionsPromptTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.permissionsPromptBody),
                const SizedBox(height: AppSpacing.sm),
                for (final entry in missing) _PromptRow(entry: entry),
              ],
            ),
          ),
          actions: [
            AutomationId(
              identifier: SemanticsIds.permissionsPromptNotNow,
              child: TextButton(
                onPressed: busy
                    ? null
                    : () => Navigator.of(
                        context,
                      ).pop(PermissionPromptChoice.notNow),
                child: Text(l10n.permissionsPromptNotNow),
              ),
            ),
            AutomationId(
              identifier: SemanticsIds.permissionsPromptContinue,
              child: FilledButton(
                onPressed: busy
                    ? null
                    : () => context.read<PermissionsBloc>().add(
                        const PromptablePermissionsRequested(),
                      ),
                child: Text(l10n.permissionsPromptContinue),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PromptRow extends StatelessWidget {
  const _PromptRow({required this.entry});

  final PermissionEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final essential = entry.permission.isEssential;
    final description = PermissionPresentation.descriptionOf(
      l10n,
      entry.permission,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            PermissionPresentation.iconOf(entry.permission),
            color: essential
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  PermissionPresentation.titleOf(l10n, entry.permission),
                  style: theme.textTheme.bodyLarge,
                ),
                Text(
                  essential
                      ? description
                      : l10n.permissionsPromptRecommended(description),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
