import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/pages/calendar_page.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/calendar_day_bars.dart';
import 'package:anta/widgets/calendar_filter_sheet.dart';
import 'package:anta/widgets/color_picker_sheet.dart';
import 'package:anta/widgets/event_detail_sheet.dart';
import 'package:anta/widgets/filter_preset_sheet.dart';

import '../database/support/db_test_support.dart';

/// The blank-sheet report: on the calendar page a sheet sometimes came up
/// empty and would not dismiss. One contributor is a second, pixel-identical
/// modal underneath the first — no opener held an in-flight slot, so two
/// gestures landing before a frame was drawn each pushed one.
///
/// **Two layers, tested at the level each one lives on.** An opener that
/// pushes synchronously is already shielded by the route's own modal barrier
/// and gesture arena, so the widget tests below pin the contract — one gesture
/// pair, one sheet, one pop — rather than the mechanism; the mechanism itself
/// is pinned directly on [SheetGuard], and on the one opener the barrier
/// genuinely cannot help: [ColorPickerSheet.show] reads a setting *before* it
/// pushes, so during that await there is no route to absorb a second tap.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Counts every route push and pop, so a second one shows up as a number
  /// rather than as a missing widget three frames later.
  final pushes = <Route<dynamic>>[];
  final pops = <Route<dynamic>>[];

  final observer = _RecordingObserver(pushes: pushes, pops: pops);

  setUp(() {
    pushes.clear();
    pops.clear();
  });

  /// Taps [first] and [second] with two pointers whose down-events both land
  /// before either handler has had a frame to react — the multi-touch fumble
  /// behind "I only tapped once".
  Future<void> tapTogether(
    WidgetTester tester,
    Finder first,
    Finder second,
  ) async {
    final a = tester.getCenter(first);
    final b = tester.getCenter(second);
    final g1 = await tester.startGesture(a, pointer: 11);
    final g2 = await tester.startGesture(b, pointer: 12);
    await g1.up();
    await g2.up();
  }

  group('SheetGuard', () {
    test('a second run while one is in flight does nothing', () async {
      final guard = SheetGuard();
      final gate = Completer<void>();
      var bodies = 0;

      final first = guard.run<int>(() async {
        bodies++;
        await gate.future;
        return 1;
      });
      final second = guard.run<int>(() async {
        bodies++;
        return 2;
      });

      expect(await second, isNull, reason: 'the slot was already taken');
      gate.complete();
      expect(await first, 1);
      expect(bodies, 1);
    });

    test('the slot is released for the next gesture', () async {
      final guard = SheetGuard();
      expect(await guard.run<int>(() async => 1), 1);
      expect(guard.isOpen, isFalse);
      expect(await guard.run<int>(() async => 2), 2);
    });

    test('a throwing body still releases the slot', () async {
      final guard = SheetGuard();
      await expectLater(
        guard.run<int>(() async => throw StateError('boom')),
        throwsStateError,
      );
      expect(guard.isOpen, isFalse);
      expect(await guard.run<int>(() async => 3), 3);
    });
  });

  group('colour picker', () {
    late AppDatabase pickerDb;

    setUp(() async {
      DatabaseLifecycle.notifyDatabaseSwitching();
      SettingsService.reset();
      pickerDb = await openTestDatabase();
      SettingsService.forTesting(pickerDb);
    });

    tearDown(() async {
      SettingsService.reset();
      await pickerDb.close();
    });

    /// The one opener that reads settings *before* it pushes. That await is a
    /// real window with no route and no barrier in it, so two gestures landing
    /// inside it both reach `showModalBottomSheet` — the static flag is what
    /// makes the second one a no-op.
    testWidgets('two overlapping opens push one picker', (tester) async {
      final results = <int?>[];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          navigatorObservers: [observer],
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  final both = await Future.wait([
                    ColorPickerSheet.show(context),
                    ColorPickerSheet.show(context),
                  ]);
                  results.addAll(both);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ColorPickerSheet), findsOneWidget);
      expect(
        pushes.length,
        1,
        reason: 'the second call must find the slot taken, not stack a picker',
      );
    });
  });

  group('page openers', () {
    late Directory tempDir;
    late CalendarBloc bloc;
    late ImportExportBloc importExportBloc;
    late AppDatabase testDb;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('anta_calendar_double');
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
      DatabaseLifecycle.notifyDatabaseSwitching();
      SettingsService.reset();
      testDb = await openTestDatabase();
      SettingsService.forTesting(testDb);

      final service = await CalendarEventService.getInstance();
      await service.deleteAll();
      bloc = CalendarBloc(service: service);
      await dispatch(const LoadCalendarEvents());
      final now = DateTime.now();
      final today = DateTime.utc(now.year, now.month, now.day);
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

    Future<void> pumpCalendar(WidgetTester tester) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1400);
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
            navigatorObservers: [observer],
            home: const CalendarPage(),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        if (find.byType(CalendarDayBars).evaluate().isNotEmpty) break;
        await tester.pump(const Duration(milliseconds: 20));
      }
      pushes.clear();
      pops.clear();
    }

    /// The sheets load their own data off the database, which a widget test's
    /// fake async never completes, so the entry animation is run by hand — a
    /// spinner would never let `pumpAndSettle` return.
    Future<void> settleSheet(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    final filterButton = find.widgetWithIcon(
      IconButton,
      Icons.filter_alt_outlined,
    );
    final presetButton = find.widgetWithIcon(
      IconButton,
      Icons.bookmarks_outlined,
    );

    testWidgets('two app-bar openers in one frame push one sheet', (
      tester,
    ) async {
      await pumpCalendar(tester);

      await tapTogether(tester, presetButton, filterButton);
      await settleSheet(tester);

      expect(
        pushes.length,
        1,
        reason: 'the second push is the sheet that looks blank underneath',
      );
      expect(
        find.byType(FilterPresetSheet).evaluate().length +
            find.byType(CalendarFilterSheet).evaluate().length,
        1,
        reason: 'exactly one sheet is mounted, whichever finger won',
      );
    });

    testWidgets('a double tap on the filter button opens one sheet', (
      tester,
    ) async {
      await pumpCalendar(tester);

      await tester.tap(filterButton, warnIfMissed: false);
      await tester.tap(filterButton, warnIfMissed: false);
      await settleSheet(tester);

      expect(find.byType(CalendarFilterSheet), findsOneWidget);
      expect(pushes.length, 1);
    });

    testWidgets('a double tap on the saved-filters button opens one sheet', (
      tester,
    ) async {
      await pumpCalendar(tester);

      await tester.tap(presetButton, warnIfMissed: false);
      await tester.tap(presetButton, warnIfMissed: false);
      await settleSheet(tester);

      expect(find.byType(FilterPresetSheet), findsOneWidget);
      expect(pushes.length, 1);
    });
  });

  group('detail sheet close', () {
    final day = DateTime.utc(2026, 8, 25);

    final event = CalendarEvent(
      id: 'e1',
      title: 'Leg day',
      categoryId: 'gym',
      startDate: day,
      rule: const OneTimeRecurrence(),
    );

    Future<List<EventDetailAction?>> openSheet(WidgetTester tester) async {
      final actions = <EventDetailAction?>[];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          navigatorObservers: [observer],
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  actions.add(
                    await EventDetailSheet.show(context, event: event, day: day),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      pops.clear();
      return actions;
    }

    testWidgets('close and Edit in one frame pop exactly once', (tester) async {
      final actions = await openSheet(tester);

      await tapTogether(
        tester,
        find.descendant(
          of: find.byType(EventDetailSheet),
          matching: find.byIcon(Icons.close_rounded),
        ),
        find.descendant(
          of: find.byType(EventDetailSheet),
          matching: find.widgetWithText(FilledButton, 'Edit'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        pops.length,
        1,
        reason:
            'a second pop takes the page underneath the sheet with it, which '
            'is the other half of "dismissal is unreliable"',
      );
      expect(
        find.text('open'),
        findsOneWidget,
        reason: 'the page that opened the sheet is still there',
      );
      expect(actions, hasLength(1));
    });

    testWidgets('two rapid taps on close pop exactly once', (tester) async {
      final actions = await openSheet(tester);

      final close = find.descendant(
        of: find.byType(EventDetailSheet),
        matching: find.byIcon(Icons.close_rounded),
      );
      await tester.tap(close);
      await tester.tap(close, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(pops.length, 1);
      expect(find.text('open'), findsOneWidget);
      expect(actions, [null]);
    });
  });
}

class _RecordingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushes;
  final List<Route<dynamic>> pops;

  _RecordingObserver({required this.pushes, required this.pops});

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) pushes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops.add(route);
  }
}
