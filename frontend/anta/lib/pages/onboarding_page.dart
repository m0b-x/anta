import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../l10n/app_localizations.dart';
import '../widgets/app_dialogs.dart';
import '../services/backup_service.dart';
import '../services/settings_service.dart';
import '../utils/custom_snackbar.dart';

class OnboardingPage extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingPage({super.key, required this.onComplete});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  bool _isImporting = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Icon(Icons.auto_stories, size: 80, color: colorScheme.primary),
              const SizedBox(height: 24),
              Text(
                l10n.welcomeToApp,
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.onboardingDescription,
                style: textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              if (_isImporting)
                const CircularProgressIndicator()
              else ...[
                FilledButton.icon(
                  onPressed: _startFresh,
                  icon: const Icon(Icons.add),
                  label: Text(l10n.startFresh),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _importBackup,
                  icon: const Icon(Icons.restore),
                  label: Text(l10n.restoreFromBackup),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                  ),
                ),
              ],
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startFresh() async {
    final settings = await SettingsService.getInstance();
    await settings.setOnboardingCompleted(true);
    widget.onComplete();
  }

  Future<void> _importBackup() async {
    final l10n = AppLocalizations.of(context)!;

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.isEmpty) return;

      setState(() => _isImporting = true);

      final file = File(result.files.first.path!);
      final jsonString = await file.readAsString();

      final backupService = await BackupService.getInstance();
      final validation = await backupService.validateBackup(jsonString);

      if (!validation.isValid) {
        if (mounted) {
          CustomSnackbar.showError(
            context,
            validation.error ?? l10n.invalidBackupFile,
          );
        }
        setState(() => _isImporting = false);
        return;
      }

      if (mounted) {
        final shouldImport = await _showImportConfirmation(validation);
        if (shouldImport != true) {
          setState(() => _isImporting = false);
          return;
        }
      }

      final importResult = await backupService.importFromJson(jsonString);

      if (mounted) {
        if (importResult.success) {
          CustomSnackbar.showSuccess(
            context,
            l10n.importSuccess(
              importResult.foldersImported,
              importResult.notesImported,
            ),
          );

          final settings = await SettingsService.getInstance();
          await settings.setOnboardingCompleted(true);
          widget.onComplete();
        } else {
          CustomSnackbar.showError(
            context,
            importResult.error ?? l10n.importFailed,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(context, '${l10n.importFailed}: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<bool> _showImportConfirmation(BackupValidationResult validation) {
    final l10n = AppLocalizations.of(context)!;

    return AppDialogs.confirm(
      context,
      title: l10n.confirmImport,
      confirmText: l10n.import,
      contentWidget: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.backupContains),
          const SizedBox(height: 8),
          Text('• ${validation.folderCount} ${l10n.folders}'),
          Text('• ${validation.noteCount} ${l10n.notes}'),
          if (validation.exportedAt != null) ...[
            const SizedBox(height: 8),
            Text(
              l10n.exportedOn(validation.exportedAt!),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
