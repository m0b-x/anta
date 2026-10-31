import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/import_export/import_export_bloc.dart';
import '../bloc/import_export/import_export_event.dart';
import '../bloc/import_export/import_export_state.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../models/export_format.dart';
import '../utils/custom_snackbar.dart';

/// The calendar's exports — the `.ics` export started from the ⋮ menu of the
/// calendar, the overview or the report, and the report's Markdown share —
/// reported back by snackbar.
///
/// One per page, and a page answers only for the export it started: both
/// pages can be mounted at once — the overview pushed over the calendar — and
/// [ImportExportBloc] is app-wide, so a listener that answered every calendar
/// export would show each one's snackbar twice. The share sheet and the
/// temp-file cleanup behind it stay the service's job; pages never touch
/// `SharePlus`.
class CalendarExportController {
  /// The operation this page started and has not heard back from.
  ImportExportOperation? _pending;

  /// Whether an export this page started has not reported back yet.
  bool get isPending => _pending != null;

  void start(BuildContext context, List<CalendarEvent> events) {
    _pending = ImportExportOperation.exportCalendar;
    context.read<ImportExportBloc>().add(
      ExportCalendarRequested(events: events, share: true),
    );
  }

  /// Shares [text] as one file named [fileName] — the report's Markdown.
  void startText(
    BuildContext context, {
    required String fileName,
    required String text,
    required ExportFormat format,
  }) {
    _pending = ImportExportOperation.exportText;
    context.read<ImportExportBloc>().add(
      ExportTextRequested(fileName: fileName, text: text, format: format),
    );
  }

  /// The page's `BlocListener<ImportExportBloc, ImportExportState>` callback.
  void onState(BuildContext context, ImportExportState state) {
    final pending = _pending;
    if (pending == null) return;
    final l10n = AppLocalizations.of(context)!;
    final calendar = pending == ImportExportOperation.exportCalendar;
    if (state is ImportExportFailure) {
      if (state.operation != pending) return;
      final what = calendar ? l10n.eventsExportError : l10n.reportExportError;
      CustomSnackbar.showError(context, '$what: ${state.message}');
    } else if (state is ImportExportExportSuccess) {
      if (state.operation != pending) return;
      CustomSnackbar.showSuccess(
        context,
        calendar
            ? l10n.eventsExported(state.result.eventsExported)
            : l10n.reportExported,
      );
    } else {
      return;
    }
    _pending = null;
    context.read<ImportExportBloc>().add(const ImportExportReset());
  }
}
