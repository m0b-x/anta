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
import 'package:anta/models/day_bar.dart';
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

import '../database/support/db_test_support.dart';

/// Guards 3.3's per-day resolver-output memo (`_CalendarViewState`'s
/// `_barsOutputCache`/`_tintOutputCache`, gated by `_outputGeneration`).
///
/// `test/bloc/calendar_grid_rebuild_test.dart` pins `sameGridInputs` at the
/// bloc-state level (does a presence/skip tick even reach a fresh
/// `CalendarPageLoaded`); this file pins the layer above it — once that fresh
/// state lands, does the *rendered grid* actually reflect it, and does an
/// unrelated write (a description) leave the memo alone. `ImportExportBloc`
/// is provided because `CalendarPage`'s `MultiBlocListener` reads it, even
/// though this test never exercises export.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CalendarBloc bloc;
  late ImportExportBloc importExportBloc;
  late DateTime today;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_calendar_grid_memo');
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
    // Settings back onto a same-isolate in-memory database, separate from
    // `AppDatabase.getInstance()` (which round-trips through a background
    // isolate in real code — a round trip `testWidgets`' fake-async zone
    // cannot resolve unless it happens inside `runAsync`, and
    // `CalendarBottomPanel._load()` reads settings from its own `initState`,
    // outside any `runAsync` this test controls). Mirrors
    // `calendar_bottom_panel_anchor_test.dart`'s setup.
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
          // `_onCreateEvent` re-focuses the grid on the new event's start
          // date, so this must be `today` itself — an earlier anchor (even
          // one `retroactive` covers) would move the rendered page away from
          // `today` and this test would never see its own mutations.
          startDate: today,
          rule: const DailyRecurrence(),
          tracksPresence: true,
        ),
      ),
    );

    // A second, throwaway in-memory database purely so `ImportExportBloc`
    // exists in the tree — `CalendarPage` reads it but this test never
    // triggers export, so what it is wired to does not matter.
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

  /// Dispatches [event] and waits for the bloc's next emission before
  /// pumping. The wait runs through [WidgetTester.runAsync], which escapes
  /// `testWidgets`' fake-async zone: the handlers behind these events do
  /// real Drift I/O, and awaiting that under the fake clock (which only
  /// advances via an explicit `pump(duration)`) would hang rather than fail.
  Future<void> dispatchAndPump(
    WidgetTester tester,
    CalendarPageEvent event,
  ) async {
    await tester.runAsync(() async {
      final next = bloc.stream.first.timeout(const Duration(seconds: 10));
      bloc.add(event);
      await next;
    });
    await tester.pump();
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
    // `_loadSettings` and the bottom panel's own settings read
    // (`CalendarBottomPanel._load`) are real async gaps before the first
    // paint. Pump a bounded number of frames rather than settling, so a
    // stalled read fails with a missing-widget error instead of hanging.
    for (var i = 0; i < 20; i++) {
      if (find.byType(CalendarDayBars).evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Every `CalendarDayBars.bars` currently rendered, one entry per
  /// non-empty day cell, in tree order.
  List<List<DayBar>> barsSnapshot(WidgetTester tester) => [
    for (final widget in tester.widgetList<CalendarDayBars>(
      find.byType(CalendarDayBars),
    ))
      widget.bars,
  ];

  List<DayBar> eventBars(List<List<DayBar>> snapshot) => [
    for (final bars in snapshot) ...bars,
  ].where((bar) => bar.key.startsWith('event:')).toList(growable: false);

  /// True only when every entry is the exact same `List<DayBar>` instance as
  /// its counterpart — proof the memo served a cache hit rather than a fresh
  /// (even if value-identical) recompute.
  bool identicalSnapshots(List<List<DayBar>> a, List<List<DayBar>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  testWidgets(
    'presence, skip and description ticks repaint the grid correctly',
    (tester) async {
      await pumpCalendar(tester);

      final before = eventBars(barsSnapshot(tester));
      expect(before, isNotEmpty);
      expect(
        before.every((bar) => bar.color.a > 0.99),
        isTrue,
        reason: 'nothing is missed yet',
      );

      await dispatchAndPump(
        tester,
        SetOccurrenceMissed(eventId: 'e1', day: today),
      );
      final afterPresence = eventBars(barsSnapshot(tester));
      expect(
        afterPresence.length,
        before.length,
        reason: 'presence never changes which days an event occurs on',
      );
      expect(
        afterPresence.where((bar) => bar.color.a < 0.99).length,
        1,
        reason:
            'the grid must repaint with the fresh presence mark — a stale '
            'memo would keep every bar at full alpha',
      );

      await dispatchAndPump(
        tester,
        SetOccurrenceSkipped(eventId: 'e1', day: today),
      );
      final afterSkipSnapshot = barsSnapshot(tester);
      final afterSkip = eventBars(afterSkipSnapshot);
      expect(
        afterSkip.length,
        before.length - 1,
        reason:
            'the skipped day must lose its bar entirely — a stale memo '
            'would keep serving its (now nonexistent) occurrence',
      );
      expect(afterSkip.every((bar) => bar.color.a > 0.99), isTrue);

      // A day description write on a day that still occurs. No grid
      // resolver reads `OccurrenceDescriptions`, so this must leave every
      // rendered bar list untouched — not just value-equal, but the exact
      // same cached instances as the snapshot taken right before it.
      final stillOccurring = today.add(const Duration(days: 1));
      await dispatchAndPump(
        tester,
        SetOccurrenceDescription(
          eventId: 'e1',
          day: stillOccurring,
          description: 'note',
        ),
      );
      final afterDescriptionSnapshot = barsSnapshot(tester);
      expect(
        identicalSnapshots(afterSkipSnapshot, afterDescriptionSnapshot),
        isTrue,
        reason:
            'a description write must not disturb the grid output memo — '
            'no grid resolver reads OccurrenceDescriptions',
      );
    },
  );
}
