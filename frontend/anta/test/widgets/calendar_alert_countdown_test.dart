import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/constants/event_alerts.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/event_alert.dart';
import 'package:anta/pages/calendar_page.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/calendar_add_fab.dart';
import 'package:anta/widgets/calendar_day_bars.dart';
import 'package:anta/widgets/event_detail_sheet.dart';
import 'package:anta/widgets/event_editor_sheet.dart';

import '../database/support/db_test_support.dart';

/// What the calendar says after the editor's Save changed an event's alerts:
/// how long until the next one.
///
/// Which fire that is, whether a save earns a word and how the wait reads are
/// `AlertCountdown`'s, pinned in `test/utils/alert_countdown_test.dart`. This
/// holds the page's half: that the line is raised at all, that it is raised
/// where it can be seen — in the page's own bar while the page is on screen,
/// in the overlay when a save made from the detail sheet has reopened that
/// sheet over anything the page's `Scaffold` shows — and that a save which
/// changed nothing about the alerts stays quiet.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase testDb;
  late CalendarEventService service;
  late CalendarBloc bloc;
  late ImportExportBloc importExportBloc;
  late CalendarEvent legDay;

  // Tomorrow's 07:00 is ahead whenever the suite runs, so the line always has
  // something to count down to; how far is the clock's business.
  final countdown = find.textContaining(RegExp(r'^Reminder in \d'));

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_alert_countdown');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() async {
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    testDb = await openTestDatabase();
    SettingsService.forTesting(testDb);

    service = await CalendarEventService.getInstance();
    await service.deleteAll();
    await (await EventAlertService.getInstance()).deleteAll();
    final now = DateTime.now();
    legDay = CalendarEvent(
      id: 'leg-day',
      title: 'Leg day',
      categoryId: 'other',
      startDate: DateTime.utc(now.year, now.month, now.day + 1),
      time: const EventTime(startMinute: 7 * 60),
    );
    await service.upsert(legDay);

    bloc = CalendarBloc(
      service: service,
      alertReconciler: (eventId, reason) async {},
      alertWriter: (eventId, alerts) async {},
    );
    final loaded = bloc.stream.first.timeout(const Duration(seconds: 30));
    bloc.add(const LoadCalendarEvents());
    await loaded;

    final noteRepository = NoteRepository(database: testDb);
    final folderRepository = FolderRepository(database: testDb);
    importExportBloc = ImportExportBloc(
      service: ImportExportService(
        noteStorage: NoteStorageService(repository: noteRepository),
        folderStorage: FolderStorageService(repository: folderRepository),
        noteRepository: noteRepository,
      ),
    );
  });

  tearDown(() async {
    await bloc.close();
    await importExportBloc.close();
    SettingsService.reset();
    await testDb.close();
  });

  /// Runs a sheet in, or out and the next one in. A sheet loads data of its
  /// own, which a widget test's fake async never completes, so its animation
  /// is run by hand.
  Future<void> settleSheet(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// The markdown bar the event editor reads as it mounts, loaded already:
  /// the editor asks one that is not loaded to load, and that read would
  /// never come back under a widget test's clock.
  Future<MarkdownBarBloc> loadedMarkdownBar(WidgetTester tester) async {
    final bar = await tester.runAsync(() async {
      final bar = MarkdownBarBloc(
        barService: await MarkdownBarService.getInstance(),
      );
      final loaded = bar.stream
          .firstWhere((state) => state is MarkdownBarLoaded)
          .timeout(const Duration(seconds: 30));
      bar.add(const LoadMarkdownBar());
      await loaded;
      return bar;
    });
    addTearDown(bar!.close);
    return bar;
  }

  Future<void> pumpCalendar(
    WidgetTester tester, {
    Widget page = const CalendarPage(),
  }) async {
    final markdownBar = await loadedMarkdownBar(tester);
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1400);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<CalendarBloc>.value(value: bloc),
          BlocProvider<ImportExportBloc>.value(value: importExportBloc),
          BlocProvider<MarkdownBarBloc>.value(value: markdownBar),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: page,
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      if (find.byType(CalendarDayBars).evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump();
  }

  /// The calendar with the event's detail sheet open on it, and the editor
  /// opened from that sheet.
  Future<Element> pumpEditorFromDetailSheet(WidgetTester tester) async {
    await pumpCalendar(
      tester,
      page: CalendarPage(
        initialDay: legDay.startDate,
        initialEventId: legDay.id,
      ),
    );
    await settleSheet(tester);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.eventDetailEdit));
    await settleSheet(tester);
    return tester.element(find.byType(EventEditorSheet));
  }

  /// Lets what follows a save run under real time — the alert settings are a
  /// database read — pumping each turn, for as long as [until] is false.
  Future<void> letTheSaveLand(
    WidgetTester tester, {
    required bool Function() until,
    required Duration within,
  }) async {
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(within);
      while (!until() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pump();
  }

  testWidgets('a new event saved with an alert says when it is next due, in '
      "the page's own bar", (tester) async {
    await pumpCalendar(tester);
    await tester.tap(find.byType(CalendarAddFab));
    await settleSheet(tester);
    final editor = tester.element(find.byType(EventEditorSheet));

    Navigator.of(editor).pop(
      EventEditorSaved(
        legDay.copyWith(id: 'pull-day', title: 'Pull day'),
        alerts: const [EventAlert(id: 'a1', eventId: 'pull-day')],
      ),
    );
    await settleSheet(tester);
    await letTheSaveLand(
      tester,
      until: () => countdown.evaluate().isNotEmpty,
      within: const Duration(seconds: 30),
    );

    // No sheet is up, so it takes its turn with the page's other notices —
    // and wears their close button.
    final bar = find.ancestor(of: countdown, matching: find.byType(SnackBar));
    expect(bar, findsOneWidget);
    expect(tester.widget<SnackBar>(bar).showCloseIcon, isTrue);
  });

  testWidgets('an alert saved from the detail sheet says when it is next due, '
      'over the sheet that reopens, until its close button', (tester) async {
    final editor = await pumpEditorFromDetailSheet(tester);

    Navigator.of(editor).pop(
      EventEditorSaved(
        legDay,
        alerts: [EventAlert(id: 'a1', eventId: legDay.id)],
      ),
    );
    await settleSheet(tester);
    await letTheSaveLand(
      tester,
      until: () => countdown.evaluate().isNotEmpty,
      within: const Duration(seconds: 30),
    );

    // The detail sheet is back, and the line is above it — in the overlay,
    // not in the bar the sheet covers: a tap at its centre lands on it.
    expect(find.byType(EventDetailSheet), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(countdown.hitTestable(), findsOneWidget);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
    await tester.pump();
    expect(countdown, findsNothing);
  });

  testWidgets('a save that left the alerts as they were says nothing', (
    tester,
  ) async {
    final alert = EventAlert(id: 'a1', eventId: legDay.id);
    await tester.runAsync(
      () async => (await EventAlertService.getInstance()).replaceForEvent(
        legDay.id,
        [alert],
      ),
    );
    final editor = await pumpEditorFromDetailSheet(tester);
    // The premise: the event is known to carry this alert already.
    expect(EventAlerts.alertsFor(legDay.id), [alert]);

    Navigator.of(editor).pop(
      EventEditorSaved(
        legDay.copyWith(title: 'Leg day, heavy'),
        alerts: [alert],
      ),
    );
    await settleSheet(tester);
    await letTheSaveLand(
      tester,
      until: () => countdown.evaluate().isNotEmpty,
      within: const Duration(milliseconds: 600),
    );

    expect(find.byType(EventDetailSheet), findsOneWidget);
    expect(countdown, findsNothing);
  });
}
