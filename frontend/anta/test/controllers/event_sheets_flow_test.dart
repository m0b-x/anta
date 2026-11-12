import 'dart:async';
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
import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/event_presence.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/controllers/event_sheets_flow.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/models/calendar_grid_filters.dart';
import 'package:anta/models/recurrence_rule.dart';
import 'package:anta/models/share_overview.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/share_service.dart';
import 'package:anta/services/sync/sync_binding_service.dart';
import 'package:anta/utils/markdown_color_syntax.dart';
import 'package:anta/utils/sheet_guard.dart';
import 'package:anta/widgets/calendar_day_cell.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/models/partner_look.dart';
import 'package:anta/widgets/event_detail_sheet.dart';
import 'package:anta/widgets/event_editor_sheet.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/shared_event_sheet.dart';

import '../database/support/db_test_support.dart';
import '../services/pairing_support.dart';
import '../support/fake_share_service.dart';

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

  // Share surfaces §6.9: both doors open a partner's event read, never the
  // detail sheet or the form, and the read sheet follows the event.
  group("a partner's event", () {
    final day = DateTime.utc(2026, 9, 24);
    final theirs = CalendarEvent(
      id: 'theirs',
      title: 'Night shift',
      categoryId: 'gym',
      startDate: day,
      time: const EventTime(startMinute: 21 * 60),
    );

    late AppDatabase db;
    late CalendarEventService service;

    /// Runs [statement] on the shared row and lets the bloc re-read it, as
    /// a pull would.
    Future<void> pull(WidgetTester tester, String statement) async {
      await tester.runAsync(() async {
        // The reader's way past the fences, as the shared pull takes it.
        await db.sharedRowDao.writing(() => db.customStatement(statement));
        await service.reload();
        await dispatch(const RefreshCalendarView());
      });
      await tester.pumpAndSettle();
    }

    CalendarEvent held() => (bloc.state as CalendarPageLoaded).allEvents
        .firstWhere((event) => event.id == 'theirs');

    Future<void> open(
      WidgetTester tester,
      Future<void> Function(EventSheetsFlow flow, BuildContext context) door,
    ) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 915);
      await tester.runAsync(() async {
        db = await AppDatabase.getInstance();
        service = await CalendarEventService.getInstance();
        await service.upsert(theirs);
        await db.customStatement(
          "UPDATE calendar_events SET owner_id = 'partner' WHERE id = 'theirs'",
        );
        await db.syncDao.setValue(SyncDao.keySharedOwner, 'partner');
        await service.reload();
        await bloc.close();
        bloc = CalendarBloc(service: service);
        await dispatch(const LoadCalendarEvents());
      });
      addTearDown(() async {
        await db.sharedRowDao.writing(
          () => db.customStatement(
            "UPDATE calendar_events SET owner_id = NULL, is_deleted = 1 "
            "WHERE id = 'theirs'",
          ),
        );
        await db.syncDao.deleteValue(SyncDao.keySharedOwner);
        await service.reload();
      });
      expect(held().fromPartner, isTrue);
      final flow = EventSheetsFlow(
        guard: SheetGuard(),
        appearance: () => const CalendarAppearance(),
        palette: () => MarkdownColorPalette.presets,
        keepsHeard: () => 0,
        partnerLook: () => const PartnerLook(name: 'Maria'),
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
                  onPressed: () => door(flow, context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    void expectReadSheetOnly() {
      expect(find.byType(SharedEventSheet), findsOneWidget);
      expect(find.byType(EventDetailSheet), findsNothing);
      expect(find.byType(EventEditorSheet), findsNothing);
    }

    /// Pops every sheet the door opened, so no route — and nothing it
    /// listens to — outlives the test.
    Future<void> closeSheets(WidgetTester tester) async {
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .popUntil((route) => route.isFirst);
      await tester.pumpAndSettle();
      expect(find.byType(SharedEventSheet), findsNothing);
      expect(find.byType(EventDetailSheet), findsNothing);
      expect(find.byType(EventEditorSheet), findsNothing);
    }

    testWidgets('the detail door opens the read sheet', (tester) async {
      await open(
        tester,
        (flow, context) => flow.openDetail(context, held(), day),
      );

      expectReadSheetOnly();
      expect(find.text('From Maria'), findsOneWidget);
      await closeSheets(tester);
    });

    testWidgets('the editor door — a pencil, an alert path — opens the read '
        'sheet too', (tester) async {
      await open(
        tester,
        (flow, context) =>
            flow.openEditor(context, initialEvent: held(), occurrenceDay: day),
      );

      expectReadSheetOnly();
      await closeSheets(tester);
    });

    testWidgets('my own event still opens the detail sheet', (tester) async {
      await open(
        tester,
        (flow, context) => flow.openDetail(context, edited, visibleDay),
      );

      expect(find.byType(EventDetailSheet), findsOneWidget);
      expect(find.byType(SharedEventSheet), findsNothing);
      await closeSheets(tester);
    });

    testWidgets('a change by the partner redraws the open sheet', (
      tester,
    ) async {
      await open(
        tester,
        (flow, context) => flow.openDetail(context, held(), day),
      );

      await pull(
        tester,
        "UPDATE calendar_events SET title = 'Late shift' WHERE id = 'theirs'",
      );

      expect(find.text('Late shift'), findsOneWidget);
      expectReadSheetOnly();
      await closeSheets(tester);
    });

    testWidgets('when the event leaves, the sheet closes and says so once', (
      tester,
    ) async {
      await open(
        tester,
        (flow, context) => flow.openDetail(context, held(), day),
      );

      await pull(
        tester,
        "UPDATE calendar_events SET is_deleted = 1 WHERE id = 'theirs'",
      );

      expect(find.byType(SharedEventSheet), findsNothing);
      expect(find.text('Maria no longer shares this event'), findsOneWidget);
    });

    testWidgets('Copy to my calendar opens my copy in the editor and says '
        'it is a copy', (tester) async {
      await open(
        tester,
        (flow, context) => flow.openDetail(context, held(), day),
      );

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.sharedEventCopy),
      );
      Iterable<CalendarEvent> copies() => service.events.where(
        (event) => event.title == 'Night shift' && event.id != 'theirs',
      );
      // The copy is written on drift's isolate, then adopted by the bloc.
      for (
        var i = 0;
        i < 100 && find.byType(EventEditorSheet).evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(copies(), hasLength(1));
      final copy = copies().single;
      expect(copy.fromPartner, isFalse);
      expect(find.byType(SharedEventSheet), findsNothing);
      expect(find.byType(EventEditorSheet), findsOneWidget);
      expect(
        find.text('Copied. Later changes by Maria do not reach your copy.'),
        findsOneWidget,
      );
      expect(held().title, 'Night shift', reason: "the partner's is untouched");
      await closeSheets(tester);
    });
  });

  // Share surfaces §9: someone who never paired awaits nothing new before
  // the editor opens. The answer comes from the pairing service's cache;
  // only a pair goes on to the share service.
  group('the share row\'s availability, read as the editor opens', () {
    var opens = 0;

    Future<PairingService> pairing({required bool paired}) async {
      final settings = await SettingsService.getInstance();
      if (paired) {
        await settings.setPairingSettings(
          const PairingSettings(
            pairId: 'pair-1',
            accountUid: 'me',
            partnerUid: 'maria-uid',
            partnerName: 'Maria',
          ),
        );
      }
      return PairingService.forTesting(
        auth: FakeAuthService(user: const AppUser(uid: 'me')),
        gateway: FakePairingGateway(),
        settings: settings,
      );
    }

    setUp(() {
      opens = 0;
      // What the app opens sharing through; counted, so a case can say
      // the share service was never asked for.
      ShareService.configure(
        ShareServiceWiring(
          pairing: () async {
            opens++;
            return pairing(paired: false);
          },
          sync: _SyncingSource(),
          markFolder: (_, _) async => false,
          foldersChanged: () {},
          requestRun: () async {},
          requestSharedRead: () async {},
        ),
      );
    });

    tearDown(() {
      ShareService.reset();
      ShareService.configure(null);
      PairingService.reset();
    });

    Future<void> pumpHost(WidgetTester tester, EventSheetsFlow flow) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 915);
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
    }

    EventSheetsFlow flowOf() => EventSheetsFlow(
      guard: SheetGuard(),
      appearance: () => const CalendarAppearance(),
      palette: () => MarkdownColorPalette.presets,
      keepsHeard: () => 0,
    );

    final shareRow = find.byWidgetPredicate(
      (w) => w is FormSwitchRow && w.identifier == SemanticsIds.eventShare,
    );

    Future<void> closeSheets(WidgetTester tester) async {
      tester
          .state<NavigatorState>(find.byType(Navigator).first)
          .popUntil((route) => route.isFirst);
      await tester.pumpAndSettle();
      expect(find.byType(EventEditorSheet), findsNothing);
    }

    testWidgets('never paired: the editor is up on the tap\'s own frame, the '
        'share service never opened, and no share row', (tester) async {
      await tester.runAsync(() => pairing(paired: false));
      await pumpHost(tester, flowOf());

      await tester.tap(find.text('open'));
      await tester.pump();

      expect(find.byType(EventEditorSheet), findsOneWidget);
      expect(opens, 0, reason: 'nothing opened for sharing');
      await tester.pumpAndSettle();
      expect(shareRow, findsNothing);
      await closeSheets(tester);
    });

    testWidgets('paired: the share service answers, and the row is there', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final paired = await pairing(paired: true);
        await ShareService.forTesting(
          db: settingsDb,
          settings: await SettingsService.getInstance(),
          pairing: paired,
          sync: _SyncingSource(),
          markEvent: (_, _) async => false,
          markFolder: (_, _) async => false,
        );
      });
      await pumpHost(tester, flowOf());

      await tester.tap(find.text('open'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(shareRow, findsOneWidget);
      expect(find.text('Share with Maria'), findsOneWidget);
      await closeSheets(tester);
    });
  });

  // Share surfaces §6.6: the editor's switch rides its result, and the flow
  // writes it through the bloc once the event is stored, then says so.
  group('the share switch', () {
    const audience = ShareAudience(
      id: 'pair-1',
      displayName: 'Maria',
      members: [],
    );

    late _OrderedShareService share;
    late List<CalendarCategory> catalogue;

    setUp(() => catalogue = CalendarCategories.all);
    tearDown(() => CalendarCategories.updateCache(catalogue));

    Future<void> open(
      WidgetTester tester,
      Future<void> Function(EventSheetsFlow flow, BuildContext context) door, {
      AlertWriter? alertWriter,
    }) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 915);
      await tester.runAsync(() async {
        await bloc.close();
        share = _OrderedShareService();
        bloc = CalendarBloc(
          service: await CalendarEventService.getInstance(),
          shareService: () async => share,
          alertWriter: alertWriter,
        );
        share.bloc = bloc;
        await dispatch(const LoadCalendarEvents());
      });
      final flow = EventSheetsFlow(
        guard: SheetGuard(),
        appearance: () => const CalendarAppearance(),
        palette: () => MarkdownColorPalette.presets,
        keepsHeard: () => 0,
        shareAvailability: () async => const ShareReady(audience),
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
                  onPressed: () => door(flow, context),
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

    Future<void> tapAndSettle(WidgetTester tester, Finder target) async {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    final shareRow = find.byWidgetPredicate(
      (w) => w is FormSwitchRow && w.identifier == SemanticsIds.eventShare,
    );

    /// Waits until [done] holds: the writes run on drift's isolate, and the
    /// flow's steps after them on the test's clock, so both get turns.
    Future<void> until(WidgetTester tester, bool Function() done) async {
      for (var i = 0; i < 100 && !done(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    Future<void> saveAnd(WidgetTester tester, bool Function() done) async {
      await tapAndSettle(tester, find.byType(FilledButton).first);
      await until(tester, done);
    }

    testWidgets('a new event created shared is marked after it is stored, '
        'and the snackbar\'s Undo takes the mark back', (tester) async {
      await open(
        tester,
        (flow, context) => flow.openEditor(context, day: visibleDay),
      );
      share.nextChange = ShareChange(sharedEvents: [edited]);
      await tester.enterText(find.byType(TextField).first, 'Dinner');
      await tester.pumpAndSettle();
      await tapAndSettle(tester, shareRow);

      await saveAnd(tester, () => share.eventShares.isNotEmpty);

      final id = share.eventShares.single.$1;
      expect(share.eventShares.single.$2, isTrue);
      expect(share.heldAtWrite, [true], reason: 'the write follows the store');
      expect(find.text('Sharing Dinner with Maria'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await until(tester, () => share.eventShares.length > 1);
      expect(share.eventShares.last, (id, false));
    });

    testWidgets('a create that lands past the old two-second bound still '
        'ends shared, its mark set after the row', (tester) async {
      final alertsHeld = Completer<void>();
      await open(
        tester,
        (flow, context) => flow.openEditor(context, day: visibleDay),
        alertWriter: (_, _, {knownIds}) => alertsHeld.future,
      );
      share.nextChange = ShareChange(sharedEvents: [edited]);
      await tester.enterText(find.byType(TextField).first, 'Dinner');
      await tester.pumpAndSettle();
      await tapAndSettle(tester, shareRow);
      await tapAndSettle(tester, find.byType(FilledButton).first);

      // The create is held on its alerts while the clock passes the wait
      // the flow used to give up after.
      await tester.pump(const Duration(seconds: 3));
      expect(share.eventShares, isEmpty, reason: 'nothing before the row');
      alertsHeld.complete();
      await until(tester, () => share.eventShares.isNotEmpty);

      expect(share.eventShares.single.$2, isTrue);
      expect(share.heldAtWrite, [true], reason: 'the write follows the store');
      expect(find.text('Sharing Dinner with Maria'), findsOneWidget);
    });

    testWidgets('an edit whose save is refused leaves the mark unwritten', (
      tester,
    ) async {
      await open(
        tester,
        (flow, context) => flow.openEditor(context, initialEvent: edited),
      );
      await tapAndSettle(tester, shareRow);
      // A pull tombstones the event under the open form: the bloc refuses
      // the update, which must take the share with it.
      await tester.runAsync(() async {
        final gone = bloc.stream.firstWhere(
          (state) =>
              state is CalendarPageLoaded &&
              !state.allEvents.any((event) => event.id == edited.id),
        );
        bloc.add(DeleteCalendarEvent(eventId: edited.id));
        await gone;
      });

      await saveAnd(tester, () => false);
      await tester.pump(const Duration(seconds: 3));
      await until(tester, () => false);

      expect(share.eventShares, isEmpty);
      expect(find.textContaining('Sharing'), findsNothing);
    });

    testWidgets('a mark that could not be set is said as such, never as the '
        'exception\'s text', (tester) async {
      await open(
        tester,
        (flow, context) => flow.openEditor(context, initialEvent: edited),
      );
      share.failWith = StateError('the store is locked');
      await tapAndSettle(tester, shareRow);

      await saveAnd(tester, () => share.attempts > 0);

      expect(find.text("Sharing couldn't be changed — try again"), findsOne);
      expect(find.textContaining('locked'), findsNothing);
    });

    testWidgets('an edit that leaves the switch where it was writes nothing', (
      tester,
    ) async {
      await open(
        tester,
        (flow, context) => flow.openEditor(context, initialEvent: edited),
      );
      expect(shareRow, findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Leg day, heavy');
      await tester.pumpAndSettle();

      await saveAnd(
        tester,
        () => (bloc.state as CalendarPageLoaded).allEvents.any(
          (event) => event.title == 'Leg day, heavy',
        ),
      );
      await until(tester, () => false);

      expect(share.eventShares, isEmpty);
      expect(find.textContaining('Sharing'), findsNothing);
    });

    testWidgets('the own mark taken off an event its category shares says it '
        'stays shared, never "No longer shared"', (tester) async {
      CalendarCategories.updateCache([
        for (final category in catalogue)
          category.id == 'mobility'
              ? CalendarCategory(
                  id: category.id,
                  name: category.name,
                  colorValue: category.colorValue,
                  iconKey: category.iconKey,
                  sortOrder: category.sortOrder,
                  isBuiltIn: category.isBuiltIn,
                  isHidden: category.isHidden,
                  sharedByMe: true,
                )
              : category,
      ]);
      await open(
        tester,
        (flow, context) => flow.openEditor(
          context,
          initialEvent: edited.copyWith(markedShared: true),
        ),
      );
      share.nextChange = ShareChange(unsharedEvents: [edited]);
      // The mark is the event's own while the category is not shared.
      await tapAndSettle(tester, shareRow);
      await tapAndSettle(
        tester,
        find.bySemanticsIdentifier(SemanticsIds.eventCategory),
      );
      await tapAndSettle(
        tester,
        find.bySemanticsIdentifier(SemanticsIds.categoryPickRow('mobility')),
      );

      await saveAnd(tester, () => share.eventShares.isNotEmpty);

      expect(share.eventShares.single, ('visible', false));
      expect(find.textContaining('No longer shared'), findsNothing);
      expect(
        find.textContaining('Leg day stays shared through'),
        findsOneWidget,
      );
    });
  });
}

/// A database that syncs, for the share service a paired case builds.
class _SyncingSource implements ShareSyncSource {
  @override
  Future<bool> syncing() async => true;

  @override
  Future<bool> offline() async => false;

  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Stream<void> get runsEnded => const Stream<void>.empty();
}

/// The fake share service, which also records whether the calendar held the
/// event when its mark was written — the store first, the mark after.
class _OrderedShareService extends FakeShareService {
  _OrderedShareService()
    : super(
        availability: const ShareReady(
          ShareAudience(id: 'pair-1', displayName: 'Maria', members: []),
        ),
      );

  CalendarBloc? bloc;
  final heldAtWrite = <bool>[];

  /// Thrown by every share write instead of writing, when set.
  Object? failWith;
  int attempts = 0;

  @override
  Future<ShareChange> setEventShared(String id, bool on) async {
    attempts++;
    final failure = failWith;
    if (failure != null) throw failure;
    final state = bloc?.state;
    heldAtWrite.add(
      state is CalendarPageLoaded &&
          state.allEvents.any((event) => event.id == id),
    );
    return super.setEventShared(id, on);
  }
}

class _EventRecorder extends BlocObserver {
  final events = <Object?>[];

  @override
  void onEvent(Bloc<dynamic, dynamic> bloc, Object? event) {
    super.onEvent(bloc, event);
    events.add(event);
  }
}
