import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/bloc/import_export/import_export_event.dart';
import 'package:anta/bloc/import_export/import_export_state.dart';
import 'package:anta/controllers/calendar_export_controller.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/note_storage_service.dart';

import '../database/support/db_test_support.dart';

/// D11 of `docs/calendar-header-roadmap.md`: the calendar and the overview
/// can both be mounted, and the import/export bloc is app-wide, so each page
/// answers only for the export it started. Two controllers share one bloc
/// here, the way the two pages do; the bloc records what it is asked instead
/// of exporting, and the test emits the outcome itself.
void main() {
  late AppDatabase db;
  late _RecordingImportExportBloc bloc;

  final event = CalendarEvent(
    id: 'e1',
    title: 'Leg day',
    categoryId: 'gym',
    startDate: DateTime.utc(2026, 9, 26),
    rule: const DailyRecurrence(),
  );

  setUp(() async {
    db = await openTestDatabase();
    final notes = NoteRepository(database: db);
    final folders = FolderRepository(database: db);
    bloc = _RecordingImportExportBloc(
      ImportExportService(
        noteStorage: NoteStorageService(repository: notes),
        folderStorage: FolderStorageService(repository: folders),
        noteRepository: notes,
      ),
    );
  });

  tearDown(() async {
    await bloc.close();
    await db.close();
  });

  final contexts = <String, BuildContext>{};

  Future<void> pumpPages(
    WidgetTester tester, {
    required CalendarExportController calendar,
    required CalendarExportController overview,
  }) async {
    Widget page(String name, CalendarExportController controller) {
      return BlocListener<ImportExportBloc, ImportExportState>(
        listener: controller.onState,
        child: Builder(
          builder: (context) {
            contexts[name] = context;
            return Text(name);
          },
        ),
      );
    }

    await tester.pumpWidget(
      BlocProvider<ImportExportBloc>.value(
        value: bloc,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Column(
              children: [
                page('calendar', calendar),
                page('overview', overview),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void emit(ImportExportState state) {
    // ignore: invalid_use_of_visible_for_testing_member
    bloc.emit(state);
  }

  int resets() => bloc.recorded.whereType<ImportExportReset>().length;

  testWidgets('only the page that started the export answers for it', (
    tester,
  ) async {
    final calendar = CalendarExportController();
    final overview = CalendarExportController();
    await pumpPages(tester, calendar: calendar, overview: overview);

    overview.start(contexts['overview']!, [event]);
    expect(overview.isPending, isTrue);
    expect(calendar.isPending, isFalse);
    final request = bloc.recorded.single as ExportCalendarRequested;
    expect(request.events, [event]);
    expect(request.share, isTrue);

    emit(
      const ImportExportExportSuccess(
        operation: ImportExportOperation.exportCalendar,
        result: ExportResult(filePath: 'events.ics', eventsExported: 3),
      ),
    );
    await tester.pump();

    expect(resets(), 1, reason: 'one page answered, not both');
    expect(overview.isPending, isFalse);
    expect(find.text('3 events exported'), findsOneWidget);
  });

  testWidgets('a failure is reported with the service message', (
    tester,
  ) async {
    final calendar = CalendarExportController();
    final overview = CalendarExportController();
    await pumpPages(tester, calendar: calendar, overview: overview);

    calendar.start(contexts['calendar']!, [event]);
    emit(
      const ImportExportFailure(
        operation: ImportExportOperation.exportCalendar,
        message: 'disk full',
      ),
    );
    await tester.pump();

    expect(find.text('Could not export events: disk full'), findsOneWidget);
    expect(resets(), 1);
    expect(calendar.isPending, isFalse);
  });

  testWidgets('another operation leaves a pending export pending', (
    tester,
  ) async {
    final calendar = CalendarExportController();
    await pumpPages(
      tester,
      calendar: calendar,
      overview: CalendarExportController(),
    );

    calendar.start(contexts['calendar']!, [event]);
    emit(const ImportExportInProgress(ImportExportOperation.exportCalendar));
    emit(
      const ImportExportExportSuccess(
        operation: ImportExportOperation.exportNote,
        result: ExportResult(filePath: 'note.md'),
      ),
    );
    await tester.pump();

    expect(calendar.isPending, isTrue);
    expect(resets(), 0);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('an export nobody here started is not answered', (tester) async {
    await pumpPages(
      tester,
      calendar: CalendarExportController(),
      overview: CalendarExportController(),
    );

    emit(
      const ImportExportExportSuccess(
        operation: ImportExportOperation.exportCalendar,
        result: ExportResult(filePath: 'events.ics', eventsExported: 2),
      ),
    );
    await tester.pump();

    expect(resets(), 0);
    expect(find.byType(SnackBar), findsNothing);
  });
}

/// Records every event instead of running it: the export itself would reach
/// the share sheet.
class _RecordingImportExportBloc extends ImportExportBloc {
  _RecordingImportExportBloc(ImportExportService service)
    : super(service: service);

  final List<ImportExportEvent> recorded = [];

  @override
  void add(ImportExportEvent event) => recorded.add(event);
}
