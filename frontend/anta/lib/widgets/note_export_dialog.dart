import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../constants/json_keys.dart';
import '../l10n/app_localizations.dart';
import '../services/app_navigator.dart';
import '../utils/custom_snackbar.dart';
import 'app_dialogs.dart';

/// Single export-and-share entry point for the note editor.
///
/// Shows the format chooser dialog, builds the file payload, writes
/// it to a temp file, and hands it to the share sheet. Errors are
/// surfaced via [CustomSnackbar] using the existing localized keys.
class NoteExportDialog {
  NoteExportDialog._();

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String content,
    required String? noteId,
    required DateTime? createdAt,
    required DateTime? updatedAt,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final format = await AppDialogs.choose<String>(
      context,
      title: l10n.chooseExportFormat,
      options: [
        (
          value: 'md',
          label: l10n.exportAsMarkdown,
          icon: Icons.description_rounded,
        ),
        (
          value: 'json',
          label: l10n.exportAsJson,
          icon: Icons.data_object_rounded,
        ),
        (
          value: 'txt',
          label: l10n.exportAsText,
          icon: Icons.text_snippet_rounded,
        ),
      ],
    );
    if (format == null || !context.mounted) return;

    await _share(
      context,
      format: format,
      title: title,
      content: content,
      noteId: noteId,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static Future<void> _share(
    BuildContext context, {
    required String format,
    required String title,
    required String content,
    required String? noteId,
    required DateTime? createdAt,
    required DateTime? updatedAt,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    AppDialogs.showLoading(context, message: l10n.exportingNote);

    try {
      final trimmedTitle = title.trim();
      final now = DateTime.now();
      late final String fileContent;
      late final String extension;

      switch (format) {
        case 'md':
          extension = 'md';
          final noteTitle = trimmedTitle.isEmpty ? 'Untitled' : trimmedTitle;
          fileContent = '# $noteTitle\n\n$content';
          break;
        case 'json':
          extension = 'json';
          final noteJson = {
            JsonKeys.title: trimmedTitle,
            JsonKeys.content: content,
            JsonKeys.createdAt: (createdAt ?? now).toIso8601String(),
            JsonKeys.updatedAt: (updatedAt ?? now).toIso8601String(),
            JsonKeys.exportedAt: now.toIso8601String(),
          };
          fileContent = const JsonEncoder.withIndent('  ').convert(noteJson);
          break;
        case 'txt':
        default:
          extension = 'txt';
          fileContent = content;
          break;
      }

      final tempDir = await getTemporaryDirectory();
      final sanitizedTitle = trimmedTitle.isEmpty
          ? 'note_${noteId?.substring(0, 8) ?? 'new'}'
          : trimmedTitle.replaceAll(RegExp(r'[^\w\s-]'), '_');
      final fileName = '$sanitizedTitle.$extension';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(fileContent);

      if (!context.mounted) return;
      AppNavigator.pop(context);

      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (e) {
      if (!context.mounted) return;
      AppNavigator.pop(context);
      CustomSnackbar.showError(
        context,
        '${AppLocalizations.of(context)!.noteExportError}: $e',
      );
    }
  }
}
