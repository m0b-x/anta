import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_panel_mode.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/pages/calendar_page.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/day_summary_resolver.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/agenda_list_view.dart';
import 'package:anta/widgets/calendar_day_bars.dart';

import '../database/support/db_test_support.dart';

/// The soft keyboard collapses the month grid to a single week so the agenda
/// below it stays visible while the user types in its search field.
///
/// The override is ephemeral — it never reaches `CalendarBloc`, so the chosen
/// format comes back when the keyboard closes. It is driven here through
/// `tester.view.viewInsets`, not a `MediaQuery` wrapper, so the update travels
/// the real path (view metrics -> the ambient `MediaQuery` -> the one widget
/// that depends on it) instead of rebuilding the page from its root — which is
/// what makes the "the panel was never rebuilt" assertion mean anything.
///
/// The surface is deliberately taller than the 800x600 default: a month grid
/// is ~445px, so on the default surface raising a keyboard leaves the body
/// shorter than the grid and every pump reports a `RenderFlex` overflow that
/// has nothing to do with what is under test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CalendarBloc bloc;
  late ImportExportBloc importExportBloc;
  late DateTime today;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_calendar_keyboard');
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

  Future<void> dispatch(CalendarPageEvent event) async {
    final next = bloc.stream.first.timeout(const Duration(seconds: 30));
    bloc.add(event);
    await next;
  }

  setUp(() async {
    // Same arrangement as `calendar_grid_output_memo_test.dart`: settings on a
    // same-isolate in-memory database, because `CalendarBottomPanel._load()`
    // reads them from its own `initState`, outside any `runAsync` this test
    // controls.
    DatabaseLifecycle.notifyDatabaseSwitching();
    SettingsService.reset();
    SettingsService.forTesting(await openTestDatabase());

    final service = await CalendarEventService.getInstance();
    await service.deleteAll();
    bloc = CalendarBloc(service: service);
    await dispatch(const LoadCalendarEvents());
    final now = DateTime.now();
    today = DateTime.utc(now.year, now.month, now.day);
    await dispatch(
      CreateCalendarEvent(
        event: CalendarEvent(
          id: 'e1',
          title: 'Leg day',
          categoryId: 'gym',
          startDate: today,
          rule: const DailyRecurrence(),
        ),
      ),
    );

    final importDb = await openTestDatabase();
    final noteRepository = NoteRepository(database: importDb);
    final folderRepository = FolderRepository(database: importDb);
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
  });

  /// A phone-width surface tall enough to hold a month grid plus a keyboard.
  /// Device pixel ratio 1 so [FakeViewPadding] — which is in physical pixels —
  /// reads as logical pixels here.
  void sizeSurface(WidgetTester tester) {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1200);
  }

  Future<void> pumpCalendar(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<CalendarBloc>.value(value: bloc),
          BlocProvider<ImportExportBloc>.value(value: importExportBloc),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const CalendarPage(),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      if (find.byType(CalendarDayBars).evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> setPanelMode(CalendarPanelMode mode) async {
    final settings = await SettingsService.getInstance();
    await settings.setCalendarPanelMode(mode);
  }

  TableCalendar<CalendarEvent> grid(WidgetTester tester) =>
      tester.widget<TableCalendar<CalendarEvent>>(
        find.byType(TableCalendar<CalendarEvent>),
      );

  Future<void> showKeyboard(WidgetTester tester) async {
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    await tester.pump();
  }

  Future<void> hideKeyboard(WidgetTester tester) async {
    tester.view.resetViewInsets();
    await tester.pump();
  }

  /// Height of the page's own `AnimatedSize` (the outer one, an ancestor of
  /// `table_calendar`'s) and of the grid it wraps.
  (double outer, double inner) heights(WidgetTester tester) => (
    tester.getSize(find.byType(AnimatedSize).first).height,
    tester.getSize(find.byType(TableCalendar<CalendarEvent>)).height,
  );

  testWidgets('the keyboard collapses the grid to a week and back', (
    tester,
  ) async {
    sizeSurface(tester);
    await setPanelMode(CalendarPanelMode.upcoming);
    await pumpCalendar(tester);

    expect(grid(tester).calendarFormat, CalendarFormat.month);
    expect(
      grid(tester).onFormatChanged,
      isNotNull,
      reason: 'the vertical-swipe format gesture is live without a keyboard',
    );

    await showKeyboard(tester);
    expect(grid(tester).calendarFormat, CalendarFormat.week);
    expect(
      grid(tester).onFormatChanged,
      isNull,
      reason: 'a swipe must not rewrite the chosen format behind the override',
    );

    final duringKeyboard = bloc.state;
    expect(
      duringKeyboard is CalendarPageLoaded ? duringKeyboard.format : null,
      CalendarFormat.month,
      reason: 'the override never reaches the bloc',
    );

    await tester.pumpAndSettle();
    await hideKeyboard(tester);
    expect(grid(tester).calendarFormat, CalendarFormat.month);
    expect(grid(tester).onFormatChanged, isNotNull);
    await tester.pumpAndSettle();
  });

  testWidgets('the collapse is one animation, not two', (tester) async {
    sizeSurface(tester);
    await setPanelMode(CalendarPanelMode.upcoming);
    await pumpCalendar(tester);
    await tester.pumpAndSettle();

    final monthHeight = heights(tester).$1;
    await showKeyboard(tester);

    final samples = <(double, double)>[heights(tester)];
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      samples.add(heights(tester));
    }

    expect(
      samples.last.$1,
      lessThan(monthHeight),
      reason: 'the grid ends up shorter than the month it started as',
    );
    expect(
      samples.map((s) => s.$1).toSet().length,
      greaterThan(2),
      reason: 'the collapse animates rather than snapping in one frame',
    );
    for (var i = 1; i < samples.length; i++) {
      expect(
        samples[i].$1,
        lessThanOrEqualTo(samples[i - 1].$1),
        reason:
            'the page AnimatedSize must never grow back mid-collapse — that '
            'is what two competing size animations look like',
      );
    }
    // `table_calendar` owns the transition. The page's own AnimatedSize sees a
    // child that resizes on consecutive layouts, drops into `RenderAnimatedSize`'s
    // `unstable` state and tracks it from then on — so exactly one frame (the
    // first, where it has started its own tween but not yet noticed the child
    // moving again) may hold the old height. If it ever ran its 250ms tween
    // through, the two would diverge for its whole length.
    final divergent = [
      for (var i = 0; i < samples.length; i++)
        if (samples[i].$1 != samples[i].$2) i,
    ];
    expect(
      divergent.length,
      lessThanOrEqualTo(1),
      reason:
          'the page AnimatedSize must yield to the grid within a frame '
          'instead of running a competing tween: diverged on $divergent',
    );
    expect(samples.last.$1, samples.last.$2);
    await tester.pumpAndSettle();
  });

  testWidgets('an already-weekly grid is left alone', (tester) async {
    sizeSurface(tester);
    await setPanelMode(CalendarPanelMode.upcoming);
    await pumpCalendar(tester);

    await tester.runAsync(() async {
      final next = bloc.stream.first.timeout(const Duration(seconds: 10));
      bloc.add(const ChangeCalendarFormat(format: CalendarFormat.week));
      await next;
    });
    await tester.pumpAndSettle();
    expect(grid(tester).calendarFormat, CalendarFormat.week);
    final weekHeight = heights(tester).$1;

    await showKeyboard(tester);
    await tester.pumpAndSettle();
    expect(grid(tester).calendarFormat, CalendarFormat.week);
    expect(heights(tester).$1, weekHeight);

    await hideKeyboard(tester);
    await tester.pumpAndSettle();
    expect(grid(tester).calendarFormat, CalendarFormat.week);
    expect(heights(tester).$1, weekHeight);

    final state = bloc.state;
    expect(
      state is CalendarPageLoaded ? state.format : null,
      CalendarFormat.week,
    );
  });

  testWidgets('the collapsed panel keeps its hidden grid hidden', (
    tester,
  ) async {
    sizeSurface(tester);
    await setPanelMode(CalendarPanelMode.upcoming);
    await pumpCalendar(tester);

    await tester.tap(find.byTooltip('Expand panel'));
    await tester.pumpAndSettle();
    expect(find.byType(TableCalendar<CalendarEvent>), findsNothing);

    await showKeyboard(tester);
    await tester.pumpAndSettle();
    expect(
      find.byType(TableCalendar<CalendarEvent>),
      findsNothing,
      reason: 'the override must not resurrect a grid the user hid',
    );
  });

  testWidgets('the keyboard never rescans the agenda', (tester) async {
    sizeSurface(tester);
    await setPanelMode(CalendarPanelMode.upcoming);
    await pumpCalendar(tester);
    await tester.pumpAndSettle();

    final before = tester.widget<AgendaListView>(
      find.byType(AgendaListView),
    ).rows;
    CalendarEvent.debugOccursOnCalls = 0;

    await showKeyboard(tester);
    await tester.pumpAndSettle();
    await hideKeyboard(tester);
    await tester.pumpAndSettle();

    expect(
      CalendarEvent.debugOccursOnCalls,
      0,
      reason: 'the keyboard changes no agenda input',
    );
    final after = tester.widget<AgendaListView>(
      find.byType(AgendaListView),
    ).rows;
    expect(
      identical(after, before),
      isTrue,
      reason:
          'the panel rebuilds for the keyboard inset now that resize is '
          'off, but the rows memo must still hit rather than re-derive '
          'from a fresh scan',
    );
  });

  testWidgets('the keyboard never rebuilds the day-panel resolver', (
    tester,
  ) async {
    sizeSurface(tester);
    await setPanelMode(CalendarPanelMode.day);
    await pumpCalendar(tester);
    await tester.pumpAndSettle();
    DaySummaryResolver.debugDefaultsBuilds = 0;

    await showKeyboard(tester);
    expect(grid(tester).calendarFormat, CalendarFormat.week);
    await tester.pumpAndSettle();
    await hideKeyboard(tester);
    await tester.pumpAndSettle();

    expect(DaySummaryResolver.debugDefaultsBuilds, 0);
  });

  testWidgets(
    'a keyboard on a short screen never overflows during the collapse',
    (tester) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 700);
      await setPanelMode(CalendarPanelMode.upcoming);
      await pumpCalendar(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pump();
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      tester.view.resetViewInsets();
      await tester.pump();
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
