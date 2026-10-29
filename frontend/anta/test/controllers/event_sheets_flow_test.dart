import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/controllers/event_sheets_flow.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_grid_filters.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/markdown_color_syntax.dart';
import 'package:anta/utils/sheet_guard.dart';
import 'package:anta/widgets/form_rows.dart';

import '../database/support/db_test_support.dart';

/// The picker a scheduling surface opens must never inherit the grid's lens.
///
/// A filter is render-time only — a hidden event still occurs and still
/// counts — so the "already has events" bar the date picker draws comes from
/// the bloc's **unfiltered** day, or the user schedules onto a day they were
/// told was free.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase settingsDb;
  late CalendarBloc bloc;
  late MarkdownBarBloc barBloc;

  final visibleDay = DateTime.utc(2026, 9, 25);
  final hiddenDay = DateTime.utc(2026, 9, 10);

  final edited = CalendarEvent(
    id: 'visible',
    title: 'Leg day',
    categoryId: 'gym',
    startDate: visibleDay,
  );

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_event_sheets_flow');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    await initializeDateFormatting('en');
    GetIt.I.registerSingleton<NoteRepository>(
      NoteRepository(database: await AppDatabase.getInstance()),
    );
  });

  tearDownAll(() async {
    GetIt.I.unregister<NoteRepository>();
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<CalendarPageLoaded> dispatch(CalendarPageEvent event) async {
    final next = bloc.stream.first.timeout(const Duration(seconds: 30));
    bloc.add(event);
    return await next as CalendarPageLoaded;
  }

  setUp(() async {
    SettingsService.reset();
    settingsDb = await openTestDatabase();
    SettingsService.forTesting(settingsDb);
    barBloc = MarkdownBarBloc(
      barService: await MarkdownBarService.getInstance(),
    );
    final service = await CalendarEventService.getInstance();
    await service.tombstoneAll();
    bloc = CalendarBloc(service: service);
    await dispatch(const LoadCalendarEvents());
    await dispatch(CreateCalendarEvent(event: edited));
    await dispatch(
      CreateCalendarEvent(
        event: CalendarEvent(
          id: 'hidden',
          title: 'Physio',
          categoryId: 'mobility',
          startDate: hiddenDay,
        ),
      ),
    );
    // The lens the picker must not inherit.
    await dispatch(
      const ChangeCalendarFilters(
        filters: CalendarGridFilters(hiddenCategoryIds: {'mobility'}),
      ),
    );
  });

  tearDown(() async {
    await bloc.close();
    await barBloc.close();
    SettingsService.reset();
    await settingsDb.close();
  });

  Finder busyBars() => find.byWidgetPredicate(
    (widget) =>
        widget is Semantics &&
        widget.properties.label == 'Already has events',
  );

  testWidgets('the editor\'s date picker marks a day whose only event is '
      'filtered out', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(412, 915);
    final flow = EventSheetsFlow(
      guard: SheetGuard(),
      appearance: () => const CalendarAppearance(),
      palette: () => MarkdownColorPalette.presets,
      keepsHeard: () => 0,
    );
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<CalendarBloc>.value(value: bloc),
          BlocProvider<MarkdownBarBloc>.value(value: barBloc),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => flow.openEditor(context, initialEvent: edited),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final dateRow = find.widgetWithText(FormPickerRow, 'Date');
    await tester.ensureVisible(dateRow);
    await tester.pumpAndSettle();
    await tester.tap(dateRow);
    await tester.pumpAndSettle();

    // September 2026 holds one visible occurrence and one the grid hides;
    // both are days the user would be scheduling onto.
    expect(busyBars(), findsNWidgets(2));
  });
}
