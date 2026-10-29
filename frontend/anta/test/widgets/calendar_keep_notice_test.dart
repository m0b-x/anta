import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/pages/calendar_page.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/alert_keep_notice.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/calendar_day_bars.dart';
import 'package:anta/widgets/event_detail_sheet.dart';
import 'package:anta/widgets/event_editor_sheet.dart';

import '../database/support/db_test_support.dart';

/// Where the alarm page's Keep lands on the calendar.
///
/// Keep clears an event's "remove after it rings" through the event service,
/// and a service write tells nobody: the app-wide bloc went on holding the
/// event as it was and the day panel kept saying "removed after it rings"
/// under an event the user had just kept, until the next launch (seen on the
/// emulator, 2026-10-04). The controller now publishes an `AlertKeepNotice`
/// once the write is in, and the page answers it with a reload — whether the
/// notice arrives while the page is up or was waiting when it mounted.
///
/// The reload reaches what the bloc draws. A detail sheet that was open
/// under the ring holds a copy of the event of its own, and the last group
/// holds what is saved from that copy to the Keep.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final removedAfter = AppLocalizationsEn().eventRemovedAfterAlert;

  late Directory tempDir;
  late AppDatabase testDb;
  late CalendarEventService service;
  late CalendarBloc bloc;
  late ImportExportBloc importExportBloc;
  late CalendarEvent teaTimer;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_calendar_keep');
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
    AlertKeepNotice.instance.clearForTesting();
    testDb = await openTestDatabase();
    SettingsService.forTesting(testDb);

    service = await CalendarEventService.getInstance();
    await service.tombstoneAll();
    // Today's, so the day panel the page opens on lists it.
    final now = DateTime.now();
    teaTimer = CalendarEvent(
      id: 'tea-timer',
      title: 'Tea timer',
      categoryId: 'other',
      startDate: DateTime.utc(now.year, now.month, now.day),
      time: const EventTime(startMinute: 7 * 60),
      removeAfterAlert: true,
    );
    await service.upsert(teaTimer);

    bloc = CalendarBloc(
      service: service,
      alertReconciler: (eventId, reason) async {},
      alertWriter: (eventId, alerts, {knownIds}) async {},
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
    AlertKeepNotice.instance.clearForTesting();
    SettingsService.reset();
    await testDb.close();
  });

  /// [markdownBar] is for the cases that go on into the event editor, which
  /// reads that bloc as it mounts; the calendar itself does not.
  Future<void> pumpCalendar(
    WidgetTester tester, {
    Widget page = const CalendarPage(),
    MarkdownBarBloc? markdownBar,
  }) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1400);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<CalendarBloc>.value(value: bloc),
          BlocProvider<ImportExportBloc>.value(value: importExportBloc),
          if (markdownBar != null)
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

  /// The event as the bloc holds it — what every calendar surface draws.
  CalendarEvent held() => (bloc.state as CalendarPageLoaded).allEvents
      .singleWhere((event) => event.id == teaTimer.id);

  /// What the alarm page's Keep does to the database: the flag cleared
  /// through the service, behind the bloc's back.
  Future<void> keepBehindTheBloc(WidgetTester tester) async {
    await tester.runAsync(
      () => service.upsert(teaTimer.copyWith(removeAfterAlert: false)),
    );
    await tester.pump();
  }

  /// Lets the reload's database read land under real time, pumping the
  /// handler's continuation each turn, until the bloc holds the kept event.
  Future<void> awaitReload(WidgetTester tester) async {
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (held().removeAfterAlert) {
        if (DateTime.now().isAfter(deadline)) {
          fail('the calendar never reloaded the kept event');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pump();
  }

  /// The same for a write the page dispatched: until the bloc holds the
  /// event as [landed] describes it.
  Future<void> awaitWrite(
    WidgetTester tester,
    bool Function(CalendarEvent event) landed,
  ) async {
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (!landed(held())) {
        if (DateTime.now().isAfter(deadline)) {
          fail('the write never reached the bloc');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pump();
  }

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

  testWidgets('a Keep taken while the calendar is up reloads it, and the row '
      'stops saying the event goes', (tester) async {
    await pumpCalendar(tester);
    expect(find.textContaining(removedAfter), findsOneWidget);

    await keepBehindTheBloc(tester);
    // The service told nobody: the page is still drawing the event as it
    // was.
    expect(held().removeAfterAlert, isTrue);
    expect(find.textContaining(removedAfter), findsOneWidget);

    AlertKeepNotice.instance.publish();
    await awaitReload(tester);

    expect(held().removeAfterAlert, isFalse);
    expect(find.text('Tea timer'), findsWidgets);
    expect(find.textContaining(removedAfter), findsNothing);
    expect(AlertKeepNotice.instance.hasPending, isFalse);
  });

  testWidgets('a Keep taken before the calendar was opened is waiting for '
      'it', (tester) async {
    // The ring came up over a note: no calendar was mounted to hear the
    // notice, and the bloc — which is app-wide and was loaded at launch —
    // still holds the event as it was.
    await keepBehindTheBloc(tester);
    AlertKeepNotice.instance.publish();
    expect(held().removeAfterAlert, isTrue);

    await pumpCalendar(tester);
    await awaitReload(tester);

    expect(held().removeAfterAlert, isFalse);
    expect(find.textContaining(removedAfter), findsNothing);
    expect(AlertKeepNotice.instance.hasPending, isFalse);
  });

  testWidgets("a Keep still waiting when the alarm page's Open event pushes "
      'the calendar is in the event its detail sheet opens on', (tester) async {
    // Keep, then Open event, with no calendar on the stack: the page is
    // pushed with the kept event as its target while the bloc — loaded at
    // launch — still holds that event as it was. The sheet used to open on
    // that copy: "Remove after it rings" about an event just kept, and an
    // edit saved from it wrote the flag back.
    await keepBehindTheBloc(tester);
    AlertKeepNotice.instance.publish();
    expect(held().removeAfterAlert, isTrue);

    await pumpCalendar(
      tester,
      page: CalendarPage(
        initialDay: teaTimer.startDate,
        initialEventId: teaTimer.id,
      ),
    );
    await awaitReload(tester);
    // The sheet loads data of its own, which a widget test's fake async
    // never completes, so its entry animation is run by hand.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // One sheet, and on the event as it now is.
    final sheet = tester.widget<EventDetailSheet>(
      find.byType(EventDetailSheet),
    );
    expect(sheet.event.removeAfterAlert, isFalse);
    expect(AlertKeepNotice.instance.hasPending, isFalse);
  });

  testWidgets('with no Keep published the calendar reloads nothing', (
    tester,
  ) async {
    // The other half of the first case: without the notice the stale row
    // stays, which is what the notice is for.
    await pumpCalendar(tester);
    await keepBehindTheBloc(tester);
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    expect(held().removeAfterAlert, isTrue);
    expect(find.textContaining(removedAfter), findsOneWidget);
  });

  group("a Keep taken over the event's own detail sheet", () {
    // The sheet was open when the alarm rang — opened from the day panel to
    // look at the alarm, or left open before the phone was locked — and the
    // alarm page came up over it. Keep reloads the bloc and redraws nothing
    // of the sheet, which goes on holding the event as it opened on, "remove
    // after it rings" and all; and whatever is saved from there is the whole
    // event. A task ticked in its description, a description edit, a date
    // added or the editor's Save wrote the flag back, and the event's next
    // alarm then removed the event the user had kept.

    /// The calendar with the event's detail sheet open on it.
    Future<void> pumpOpenSheet(
      WidgetTester tester, {
      MarkdownBarBloc? markdownBar,
    }) async {
      await pumpCalendar(
        tester,
        page: CalendarPage(
          initialDay: teaTimer.startDate,
          initialEventId: teaTimer.id,
        ),
        markdownBar: markdownBar,
      );
      await settleSheet(tester);
    }

    /// The Keep, as the alarm page makes it over a calendar that is up: the
    /// write, the notice, and the reload the calendar answers with.
    Future<void> keepOverTheSheet(WidgetTester tester) async {
      await keepBehindTheBloc(tester);
      AlertKeepNotice.instance.publish();
      await awaitReload(tester);
    }

    EventDetailSheet openSheet(WidgetTester tester) =>
        tester.widget<EventDetailSheet>(find.byType(EventDetailSheet));

    /// What the sheet sends when a task in its description is ticked: the
    /// event it holds, with the description rewritten.
    void tick(EventDetailSheet sheet, String description) =>
        sheet.onEventChanged!(sheet.event.copyWith(description: description));

    testWidgets('is not written back by a task ticked in that sheet', (
      tester,
    ) async {
      await pumpOpenSheet(tester);
      final sheet = openSheet(tester);
      expect(sheet.event.removeAfterAlert, isTrue);

      await keepOverTheSheet(tester);
      // The sheet is not redrawn by the Keep: it is the same sheet, on the
      // event as it was.
      expect(openSheet(tester), same(sheet));

      tick(sheet, '- [x] steep');
      await awaitWrite(tester, (event) => event.description == '- [x] steep');

      expect(held().removeAfterAlert, isFalse);

      // Nor by the next one: every tick is the sheet's own old copy again.
      tick(sheet, '- [ ] steep');
      await awaitWrite(tester, (event) => event.description == '- [ ] steep');

      expect(held().removeAfterAlert, isFalse);
    });

    testWidgets('is not written back from the calendar in front when one '
        'beneath it took the notice', (tester) async {
      // The calendar, a note opened from it, and the drawer's Calendar row
      // from that note: a plain push, so two calendars are mounted and both
      // hear the notice. It is one flag and one of them takes it — the older,
      // whose listener was added first — while the sheet is on the other.
      await pumpCalendar(tester);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const Scaffold()),
        ),
      );
      await settleSheet(tester);
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const CalendarPage()),
        ),
      );
      await settleSheet(tester);
      expect(find.byType(CalendarPage, skipOffstage: false), findsNWidgets(2));

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.eventRow(teaTimer.id)),
      );
      await settleSheet(tester);
      final sheet = openSheet(tester);
      expect(sheet.event.removeAfterAlert, isTrue);

      await keepOverTheSheet(tester);

      tick(sheet, '- [x] steep');
      await awaitWrite(tester, (event) => event.description == '- [x] steep');

      expect(held().removeAfterAlert, isFalse);
    });

    testWidgets('is in the event the editor opens on from that sheet', (
      tester,
    ) async {
      await pumpOpenSheet(tester, markdownBar: await loadedMarkdownBar(tester));
      expect(openSheet(tester).event.removeAfterAlert, isTrue);

      await keepOverTheSheet(tester);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.eventDetailEdit),
      );
      await settleSheet(tester);

      // The editor's switch starts where the event is, not where the sheet
      // left it: a Save with nothing touched keeps the event kept.
      final editor = tester.widget<EventEditorSheet>(
        find.byType(EventEditorSheet),
      );
      expect(editor.initialEvent!.id, teaTimer.id);
      expect(editor.initialEvent!.removeAfterAlert, isFalse);
    });

    testWidgets("gives way to the editor's own switch, turned on again after "
        'it', (tester) async {
      await pumpOpenSheet(tester, markdownBar: await loadedMarkdownBar(tester));
      await keepOverTheSheet(tester);
      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.eventDetailEdit),
      );
      await settleSheet(tester);
      final editor = tester.element(find.byType(EventEditorSheet));
      final kept = (editor.widget as EventEditorSheet).initialEvent!;
      expect(kept.removeAfterAlert, isFalse);

      // The user turns "remove after it rings" back on in the editor and
      // saves: the later word. The page reopens the detail sheet on what was
      // saved, while that save is still on its way to the bloc.
      Navigator.of(
        editor,
      ).pop(EventEditorSaved(kept.copyWith(removeAfterAlert: true)));
      await settleSheet(tester);
      final reopened = openSheet(tester);
      expect(reopened.event.removeAfterAlert, isTrue);
      expect(held().removeAfterAlert, isFalse);

      tick(reopened, '- [x] steep');
      await awaitWrite(tester, (event) => event.description == '- [x] steep');

      expect(held().removeAfterAlert, isTrue);
    });
  });
}
