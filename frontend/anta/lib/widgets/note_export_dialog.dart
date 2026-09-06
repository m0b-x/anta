import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/export_format.dart';
import 'app_dialogs.dart';

/// The single export-format chooser for a note.
///
/// It only asks. Encoding the file, writing it and handing it to the share
/// sheet is [ImportExportBloc]'s work — the editor and the browser card
/// dispatch the same `ExportNoteRequested` with whatever this returns, so
/// there is one export path and one place that talks to the share sheet.
class NoteExportDialog {
  NoteExportDialog._();

  static Future<ExportFormat?> chooseFormat(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppDialogs.choose<ExportFormat>(
      context,
      title: l10n.chooseExportFormat,
      options: [
        (
          value: ExportFormat.markdown,
          label: l10n.exportAsMarkdown,
          icon: Icons.description_rounded,
        ),
        (
          value: ExportFormat.json,
          label: l10n.exportAsJson,
          icon: Icons.data_object_rounded,
        ),
        (
          value: ExportFormat.text,
          label: l10n.exportAsText,
          icon: Icons.text_snippet_rounded,
        ),
      ],
    );
  }
}
