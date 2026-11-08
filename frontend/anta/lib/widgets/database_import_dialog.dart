import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/app_navigator.dart';
import '../services/database_manager.dart';
import '../utils/custom_snackbar.dart';
import 'app_dialogs.dart';

/// The one way a database file is imported, from the Databases page and
/// from onboarding alike: [AppDialogs.progress] over the copy (its share,
/// Cancel live) and the check (indeterminate, Cancel disabled), then a
/// refusal named by its kind.
abstract final class DatabaseImportDialog {
  /// Runs [import] under the dialog, which closes when it settles. True when
  /// the database is in; false when the user cancelled or the import
  /// failed, the failure's message already shown.
  static Future<bool> run(
    BuildContext context,
    Future<void> Function(DatabaseImportProgress progress) import,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final progress = DatabaseImportProgress();
    final closed = AppDialogs.progress(
      context,
      steps: [l10n.importingDatabase, l10n.checkingDatabaseFile],
      listenable: progress,
      read: () => switch (progress.phase) {
        DatabaseImportPhase.copying => (
          step: 0,
          fraction: progress.fraction,
          canCancel: progress.canCancel,
        ),
        DatabaseImportPhase.verifying => (
          step: 1,
          fraction: null,
          canCancel: false,
        ),
      },
      onCancel: progress.cancel,
    );
    unawaited(closed.whenComplete(progress.dispose));
    try {
      await import(progress);
      if (context.mounted) AppNavigator.pop(context);
      return true;
    } catch (e, st) {
      if (context.mounted) AppNavigator.pop(context);
      if (e is DatabaseImportCancelled) return false;
      debugPrint('[DatabaseImport] import failed: $e\n$st');
      if (context.mounted) {
        CustomSnackbar.showError(context, _messageFor(e, l10n));
      }
      return false;
    }
  }

  static String _messageFor(Object error, AppLocalizations l10n) =>
      switch (error) {
        DatabaseImportCorrupt() => l10n.databaseImportCorrupt,
        DatabaseImportNotAnta() => l10n.databaseImportNotAnta,
        DatabaseImportTooNew() => l10n.databaseImportTooNew,
        _ => l10n.importFailed,
      };
}
