import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/day_bar.dart';
import 'package:anta/models/share_settings.dart';
import 'package:anta/pages/calendar_page.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/calendar_day_bars.dart';
import 'package:anta/widgets/day_summary_panel.dart';
import 'package:anta/widgets/event_avatar.dart';
import 'package:anta/widgets/event_detail_sheet.dart';
import 'package:anta/widgets/event_editor_sheet.dart';
import 'package:anta/widgets/shared_event_sheet.dart';

import '../database/support/db_test_support.dart';

/// The real calendar page draws a partner's event by the look in the
/// settings, and a look picked on the settings page repaints the open
/// calendar on the way back — no restart (`docs/cloud-share-surfaces-
/// roadmap.md`, the definition of done, item 8); its day panel card opens it
/// read (§6.9). The settings arrangement is
/// `calendar_rail_label_wiring_test.dart`'s.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CalendarBloc bloc;
  late ImportExportBloc importExportBloc;
  late AppDatabase testDb;
  late DateTime today;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_partner_look');
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

    // The event service outlives a test, and a delete-all rightly leaves a
    // partner's rows where they are: the one the previous test stored goes
    // the way a share ends, or its id would still be the partner's here and
    // the next create under it would be refused.
    await (await AppDatabase.getInstance()).sharedRowDao.removeAll();
    final service = await CalendarEventService.getInstance();
    await service.tombstoneAll();
    bloc = CalendarBloc(service: service);
    await dispatch(const LoadCalendarEvents());
    final now = DateTime.now();
    today = DateTime.utc(now.year, now.month, now.day);

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

  /// Stores a one-time event today as the partner's — the row a pull would
  /// have written — and reloads the calendar over it.
  Future<void> seedPartnerEvent(WidgetTester tester) async {
    await tester.runAsync(() async {
      await dispatch(
        CreateCalendarEvent(
          event: CalendarEvent(
            id: 'theirs',
            title: 'Night shift',
            categoryId: 'health',
            startDate: today,
          ),
        ),
      );
      final db = await AppDatabase.getInstance();
      await db.customStatement(
        "UPDATE calendar_events SET owner_id = 'partner' WHERE id = 'theirs'",
      );
      await db.syncDao.setValue(SyncDao.keySharedOwner, 'partner');
      await CalendarEventService.applyMerged({'theirs'});
      await dispatch(const LoadCalendarEvents());
    });
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
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
          navigatorObservers: [AppNavigator.routeObserver],
          home: const CalendarPage(),
        ),
      ),
    );
    await settle(tester);
  }

  DayBar partnerBar(WidgetTester tester) => tester
      .widgetList<CalendarDayBars>(find.byType(CalendarDayBars))
      .expand((strip) => strip.bars)
      .firstWhere((bar) => bar.semanticLabel.startsWith('Night shift'));

  EventAvatar partnerAvatar(WidgetTester tester) => tester.widget<EventAvatar>(
    find.byWidgetPredicate(
      (widget) => widget is EventAvatar && widget.semanticsLabel != null,
    ),
  );

  testWidgets('a partner\'s event is outlined by default: a hollow bar that '
      'says whose it is, and an outlined avatar in the day panel', (
    tester,
  ) async {
    await seedPartnerEvent(tester);
    await pumpCalendar(tester);

    final bar = partnerBar(tester);
    expect(bar.hollow, isTrue);
    // No pairing is configured here, so the name is the stand-in.
    expect(bar.semanticLabel, 'Night shift, From your partner');
    final avatar = partnerAvatar(tester);
    expect(avatar.outlined, isTrue);
    expect(avatar.semanticsLabel, 'From your partner');
  });

  testWidgets('a partner read that failed is asked again once per change of '
      'events, never in a loop', (tester) async {
    // No pairing is configured here, so every read fails.
    var failures = 0;
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message?.startsWith('[CalendarPage] partner not read') ?? false) {
        failures++;
      }
    };
    try {
      await seedPartnerEvent(tester);
      await pumpCalendar(tester);
      final before = failures;
      expect(before, greaterThan(0));

      await tester.runAsync(
        () => dispatch(
          CreateCalendarEvent(
            event: CalendarEvent(
              id: 'mine',
              title: 'Dentist',
              categoryId: 'health',
              startDate: today,
            ),
          ),
        ),
      );
      await settle(tester);
      await settle(tester);

      expect(failures, before + 1);
    } finally {
      debugPrint = original;
    }
  });

  testWidgets('a look picked on a page above repaints the open calendar on '
      'the way back', (tester) async {
    await seedPartnerEvent(tester);
    await pumpCalendar(tester);
    expect(partnerBar(tester).hollow, isTrue);

    // The settings page's write, then its pop.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
    await settle(tester);
    await tester.runAsync(() async {
      final settings = await SettingsService.getInstance();
      await settings.setShareEventLook(ShareEventLook.avatar);
    });
    navigator.pop();
    await settle(tester);

    expect(partnerBar(tester).hollow, isFalse);
    expect(partnerBar(tester).semanticLabel, 'Night shift, From your partner');
    final avatar = partnerAvatar(tester);
    expect(avatar.outlined, isFalse);
    expect(avatar.badge, const EventAvatarBadge.partner(null));
  });

  // Share surfaces §6.9: the day panel's card of a partner's event opens it
  // read; my own card opens what it always did.
  group('a tap on a day panel card', () {
    Finder cardTitled(String title) => find.descendant(
      of: find.byType(DaySummaryPanel),
      matching: find.text(title),
    );

    /// Tall enough that the day panel sits on screen under the grid.
    void tallView(WidgetTester tester) {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 1400);
    }

    /// Closes whatever the tap opened, so no route outlives the test.
    Future<void> closeSheet(WidgetTester tester, Type sheet) async {
      Navigator.of(tester.element(find.byType(sheet))).pop();
      await settle(tester);
      expect(find.byType(sheet), findsNothing);
    }

    testWidgets("of a partner's event opens the read sheet, never the detail "
        'sheet or the editor', (tester) async {
      tallView(tester);
      await seedPartnerEvent(tester);
      await pumpCalendar(tester);

      await tester.tap(cardTitled('Night shift'));
      await settle(tester);

      expect(find.byType(SharedEventSheet), findsOneWidget);
      expect(find.byType(EventDetailSheet), findsNothing);
      expect(find.byType(EventEditorSheet), findsNothing);
      await closeSheet(tester, SharedEventSheet);
    });

    testWidgets('of my own event still opens the detail sheet', (
      tester,
    ) async {
      tallView(tester);
      await seedPartnerEvent(tester);
      await tester.runAsync(
        () => dispatch(
          CreateCalendarEvent(
            event: CalendarEvent(
              id: 'mine',
              title: 'Leg day',
              categoryId: 'gym',
              startDate: today,
            ),
          ),
        ),
      );
      await pumpCalendar(tester);

      await tester.tap(cardTitled('Leg day'));
      await settle(tester);

      expect(find.byType(EventDetailSheet), findsOneWidget);
      expect(find.byType(SharedEventSheet), findsNothing);
      await closeSheet(tester, EventDetailSheet);
    });
  });
}
