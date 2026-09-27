import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/import_export/import_export_bloc.dart';
import '../bloc/import_export/import_export_event.dart';
import '../bloc/import_export/import_export_state.dart';
import '../l10n/app_localizations.dart';
import '../models/calendar_event.dart';
import '../utils/custom_snackbar.dart';

/// The calendar's `.ics` export, started from the ⋮ menu of the calendar or
/// of the overview and reported back by snackbar.
///
/// One per page, and a page answers only for the export it started: both
/// pages can be mounted at once — the overview pushed over the calendar — and
/// [ImportExportBloc] is app-wide, so a listener that answered every calendar
/// export would show each one's snackbar twice. The share sheet and the
/// temp-file cleanup behind it stay the service's job; pages never touch
/// `SharePlus`.
class CalendarExportController {
  bool _pending = false;

  /// Whether an export this page started has not reported back yet.
  bool get isPending => _pending;

  void start(BuildContext context, List<CalendarEvent> events) {
    _pending = true;
    context.read<ImportExportBloc>().add(
      ExportCalendarRequested(events: events, share: true),
    );
  }

  /// The page's `BlocListener<ImportExportBloc, ImportExportState>` callback.
  void onState(BuildContext context, ImportExportState state) {
    if (!_pending) return;
    final l10n = AppLocalizations.of(context)!;
    if (state is ImportExportFailure) {
      if (state.operation != ImportExportOperation.exportCalendar) return;
      CustomSnackbar.showError(
        context,
        '${l10n.eventsExportError}: ${state.message}',
      );
    } else if (state is ImportExportExportSuccess) {
      if (state.operation != ImportExportOperation.exportCalendar) return;
      CustomSnackbar.showSuccess(
        context,
        l10n.eventsExported(state.result.eventsExported),
      );
    } else {
      return;
    }
    _pending = false;
    context.read<ImportExportBloc>().add(const ImportExportReset());
  }
}
