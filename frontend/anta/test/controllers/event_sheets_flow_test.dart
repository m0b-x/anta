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
import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/controllers/event_sheets_flow.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/calendar_grid_filters.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/sync_binding_service.dart';
import 'package:anta/utils/markdown_color_syntax.dart';
import 'package:anta/utils/sheet_guard.dart';
import 'package:anta/widgets/calendar_day_cell.dart';
import 'package:anta/widgets/event_detail_sheet.dart';
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
    // It holds the closed settings database, which the next setUp's
    // `tombstoneAll` would read through.
    SyncBindingService.reset();
    await settingsDb.close();
  });

  Finder busyBars() => find.byWidgetPredicate(
    (widget) =>
        widget is Semantics && widget.properties.label == 'Already has events',
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

  // S1b: a set trimmed to one date becomes a one-off, whose skip is its
  // cancel, so the rows the set left behind are cleared with the save.
  testWidgets('trimming a pinned set with a skip to one date clears its '
      'skips', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(412, 915);
    final first = DateTime.utc(2026, 9, 14);
    final second = DateTime.utc(2026, 9, 15);
    final pinned = CalendarEvent(
      id: 'pinned',
      title: 'Physio',
      categoryId: 'gym',
      startDate: first,
      rule: SpecificDatesRecurrence(dates: {first, second}),
    );
    // A bloc reads the observer when it is built, so this test builds its own.
    final previous = Bloc.observer;
    final recorder = _EventRecorder();
    Bloc.observer = recorder;
    addTearDown(() => Bloc.observer = previous);
    await tester.runAsync(() async {
      await bloc.close();
      bloc = CalendarBloc(service: await CalendarEventService.getInstance());
      await dispatch(const LoadCalendarEvents());
      await dispatch(CreateCalendarEvent(event: pinned));
      await dispatch(SetOccurrenceSkipped(eventId: 'pinned', day: second));
    });
    expect(EventSkips.daysFor('pinned'), {second});
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
                onPressed: () => flow.openDetail(context, pinned, first),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final dates = find.bySemanticsIdentifier(SemanticsIds.eventDetailDates);
    await tester.ensureVisible(dates);
    await tester.pumpAndSettle();
    await tester.tap(dates);
    await tester.pumpAndSettle();
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.datePickerView('month')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is CalendarDayCell && w.day == second && !w.isOutside,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.datePickerSave));
    await tester.pumpAndSettle();
    // The writes run on drift's isolate; let them land before teardown.
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && EventSkips.daysFor('pinned').isNotEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });

    expect(EventSkips.daysFor('pinned'), isEmpty);
    expect(
      recorder.events.whereType<SetOccurrenceSkips>().map(
        (e) => (e.eventId, e.days),
      ),
      [('pinned', const <DateTime>{})],
    );
  });

  // S1 fix pass: a cancel clears the day's mark, so a restore writes back
  // the mark it took — through the Restore row and through the Undo of a
  // sheet already closed.
  group('a one-off\'s restore', () {
    final day = DateTime.utc(2026, 9, 21);
    final dentist = CalendarEvent(
      id: 'dentist',
      title: 'Dentist',
      categoryId: 'gym',
      startDate: day,
      tracksPresence: true,
      assumeAbsent: true,
    );

    late _EventRecorder recorder;

    /// Waits on drift's isolate until [done] holds.
    Future<void> settle(WidgetTester tester, bool Function() done) async {
      await tester.runAsync(() async {
        for (var i = 0; i < 100 && !done(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
    }

    Future<void> open(WidgetTester tester, {PresenceStatus? mark}) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 915);
      final previous = Bloc.observer;
      recorder = _EventRecorder();
      Bloc.observer = recorder;
      addTearDown(() => Bloc.observer = previous);
      await tester.runAsync(() async {
        await bloc.close();
        bloc = CalendarBloc(service: await CalendarEventService.getInstance());
        await dispatch(const LoadCalendarEvents());
        await dispatch(CreateCalendarEvent(event: dentist));
        if (mark != null) {
          await dispatch(
            SetOccurrencePresence(eventId: 'dentist', day: day, status: mark),
          );
        }
      });
      expect(EventPresence.marksFor('dentist')[day], mark);
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
                  onPressed: () => flow.openDetail(context, dentist, day),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> cancel(WidgetTester tester) async {
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.eventDetailCancel),
      );
      await settle(
        tester,
        () =>
            EventSkips.daysFor('dentist').isNotEmpty &&
            EventPresence.marksFor('dentist').isEmpty,
      );
      expect(EventPresence.marksFor('dentist'), isEmpty);
    }

    Iterable<SetOccurrencePresence> restores() => recorder.events
        .whereType<SetOccurrencePresence>()
        .where((e) => e.eventId == 'dentist');

    testWidgets('a Done one-off cancelled and restored is Done again', (
      tester,
    ) async {
      await open(tester, mark: PresenceStatus.present);
      await cancel(tester);

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.eventDetailRestore),
      );
      await settle(
        tester,
        () =>
            EventSkips.daysFor('dentist').isEmpty &&
            EventPresence.marksFor('dentist').isNotEmpty,
      );

      expect(EventSkips.daysFor('dentist'), isEmpty);
      expect(EventPresence.marksFor('dentist')[day], PresenceStatus.present);
      expect(EventPresence.isMissed(dentist, day), isFalse);
    });

    testWidgets('the Undo after the sheet closed gives the mark back too', (
      tester,
    ) async {
      await open(tester, mark: PresenceStatus.present);
      await cancel(tester);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.eventDetailClose),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EventDetailSheet), findsNothing);

      await tester.tap(find.text('Undo'));
      await settle(
        tester,
        () =>
            EventSkips.daysFor('dentist').isEmpty &&
            EventPresence.marksFor('dentist').isNotEmpty,
      );

      expect(EventSkips.daysFor('dentist'), isEmpty);
      expect(EventPresence.marksFor('dentist')[day], PresenceStatus.present);
    });

    testWidgets('an unmarked one-off restores unmarked', (tester) async {
      await open(tester);
      await cancel(tester);

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.eventDetailRestore),
      );
      await settle(tester, () => EventSkips.daysFor('dentist').isEmpty);

      expect(EventSkips.daysFor('dentist'), isEmpty);
      expect(EventPresence.marksFor('dentist'), isEmpty);
      expect(restores(), isEmpty, reason: 'no mark is invented');
    });
  });
}

class _EventRecorder extends BlocObserver {
  final events = <Object?>[];

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    events.add(event);
  }
}
