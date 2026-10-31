import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/app_settings/app_settings_bloc.dart';
import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/counter/counter_bloc.dart';
import 'package:anta/bloc/import_export/import_export_bloc.dart';
import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/bloc/pairing/pairing_bloc.dart';
import 'package:anta/bloc/permissions/permissions_bloc.dart';
import 'package:anta/bloc/sync/sync_bloc.dart';
import 'package:anta/constants/app_version.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/counter.dart';
import 'package:anta/models/dev_options.dart';
import 'package:anta/models/nav_destination.dart';
import 'package:anta/pages/alerts_page.dart';
import 'package:anta/pages/calendar_appearance_page.dart';
import 'package:anta/pages/calendar_categories_page.dart';
import 'package:anta/pages/calendar_guide_page.dart';
import 'package:anta/pages/calendar_overview_page.dart';
import 'package:anta/pages/calendar_page.dart';
import 'package:anta/pages/calendar_report_page.dart';
import 'package:anta/pages/calendar_settings_page.dart';
import 'package:anta/pages/counter_management_page.dart';
import 'package:anta/pages/counter_per_note_page.dart';
import 'package:anta/pages/database_settings_page.dart';
import 'package:anta/pages/developer_options_page.dart';
import 'package:anta/pages/event_templates_page.dart';
import 'package:anta/pages/markdown_colors_page.dart';
import 'package:anta/pages/markdown_settings_page.dart';
import 'package:anta/pages/note_bar_assignment_page.dart';
import 'package:anta/pages/note_money_currency_page.dart';
import 'package:anta/pages/permissions_page.dart';
import 'package:anta/pages/settings_hub_page.dart';
import 'package:anta/pages/settings_page.dart';
import 'package:anta/pages/sync_settings_page.dart';
import 'package:anta/pages/vocabularies_page.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/dev_options_service.dart';
import 'package:anta/services/drawer_host_registry.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/import_export_service.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/navigation_history_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/permission_gateway.dart';
import 'package:anta/services/permission_service.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/app_drawer.dart';

import '../services/pairing_support.dart';
import '../services/permission_support.dart';

/// The settings navigation contract (`docs/settings-rework-roadmap.md`
/// §4.3), written in S0 against the old drawer and rewritten in S2, so the
/// diff between the two is the proof of what changed: the drawer lists
/// places (D1), every settings page is chosen on the hub (D2), and back, by
/// the arrow or the system gesture, returns to the route beneath — the host
/// from a drawer row, the hub from a hub row (D3) — with the dedupe, the new
/// kinds and the decoder each named for its rule (S15, S26, §4.3).
///
/// The drawer flow drives the real rows over the real pages, so every page
/// the drawer and the hub reach is built: the suite runs over the file-backed
/// database in a temporary documents directory, opened in real async, with
/// each page's collaborators bound the way its own suite binds them. The
/// restore half asserts routes and stamps only, and tears the app down
/// before a frame builds a restored page (the `app_navigator_restore_test`
/// shape).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final l10n = AppLocalizationsEn();

  late Directory tempDir;
  late FakeAuthService auth;
  late FakePairingGateway gateway;
  late MarkdownBarBloc markdownBloc;
  late ImportExportBloc importExportBloc;
  late CounterBloc counterBloc;
  late CalendarBloc calendarBloc;

  /// A live per-note counter, so a per-note counter page has something to
  /// restore.
  late String counterId;

  /// A live global counter, which has no per-note page to restore.
  late String globalCounterId;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_settings_nav');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
    // Opened here, in real async: inside `testWidgets` the database answers
    // on a background isolate that `FakeAsync` never lets run.
    final db = await AppDatabase.getInstance();
    await db.customSelect('SELECT 1').get();
    final settings = await SettingsService.getInstance();
    await PublicHolidayService.getInstance();
    await CalendarEventService.getInstance();
    await CalendarPaletteService.getInstance();
    await DevOptionsService.getInstance();

    markdownBloc = MarkdownBarBloc(
      barService: await MarkdownBarService.getInstance(),
    );
    // The calendar's three pages listen for an export's outcome.
    final notes = NoteRepository(database: db);
    importExportBloc = ImportExportBloc(
      service: ImportExportService(
        noteStorage: NoteStorageService(repository: notes),
        folderStorage: FolderStorageService(
          repository: FolderRepository(database: db),
        ),
        noteRepository: notes,
      ),
    );
    final counters = await CounterService.getInstance();
    counterId = await counters.addCounter(
      name: 'Sets',
      scope: CounterScope.perNote,
    );
    globalCounterId = await counters.addCounter(name: 'Total');
    counterBloc = CounterBloc(counterService: counters)
      ..add(const LoadCounters());
    // The Alerts hub builds its body under a loaded calendar; a service that
    // never arrives keeps the bloc from reading anything.
    calendarBloc = CalendarBloc(
      service: Completer<CalendarEventService>().future,
      alertReconciler: (_, _) async {},
      alertWriter: (_, _, {knownIds}) async {},
      allAlertsReconciler: (_) async {},
    );
    // ignore: invalid_use_of_visible_for_testing_member
    calendarBloc.emit(
      CalendarPageLoaded(
        allEvents: const [],
        focusedDay: DateTime.utc(2026, 10, 31),
        selectedDay: DateTime.utc(2026, 10, 31),
      ),
    );

    auth = FakeAuthService();
    gateway = FakePairingGateway();
    await PairingService.forTesting(
      auth: auth,
      gateway: gateway,
      settings: settings,
    );
    GetIt.I.registerSingleton<AuthService>(auth);
    GetIt.I.registerFactory<SyncBloc>(() => SyncBloc(authService: auth));
    GetIt.I.registerFactory<PairingBloc>(
      () => PairingBloc(authService: auth, gateway: gateway),
    );
    GetIt.I.registerFactory<PermissionsBloc>(
      () => PermissionsBloc(
        service: PermissionService(
          gateway: const NoOpPermissionGateway(),
          store: MemoryPermissionPromptStore(),
          deviceId: () async => 'device-a',
        ),
      ),
    );
  });

  tearDownAll(() async {
    await markdownBloc.close();
    await importExportBloc.close();
    await counterBloc.close();
    await calendarBloc.close();
    await GetIt.I.reset();
    PairingService.reset();
    await gateway.dispose();
    await auth.dispose();
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(DrawerHostRegistry.clear);

  tearDown(() {
    DrawerHostRegistry.clear();
    DevOptions.instance.lockDeveloperMode();
  });

  /// Drift answers on futures `FakeAsync` alone never completes, so real time
  /// and pumped frames are interleaved rather than `pumpAndSettle` used.
  Future<void> settle(WidgetTester tester, {int rounds = 14}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  group('the drawer flow', () {
    late GlobalKey<ScaffoldState> hostKey;
    late _RecordingObserver observer;
    late _RecordingSettingsBloc appSettingsBloc;

    setUp(() {
      hostKey = GlobalKey<ScaffoldState>();
      observer = _RecordingObserver();
      appSettingsBloc = _RecordingSettingsBloc();
    });

    tearDown(() => appSettingsBloc.close());

    ScaffoldState host() => hostKey.currentState!;

    Future<void> pumpHost(WidgetTester tester) async {
      // Tall enough for the whole drawer list, so every row is built.
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AppSettingsBloc>.value(value: appSettingsBloc),
            BlocProvider<MarkdownBarBloc>.value(value: markdownBloc),
            BlocProvider<ImportExportBloc>.value(value: importExportBloc),
            BlocProvider<CounterBloc>.value(value: counterBloc),
            BlocProvider<CalendarBloc>.value(value: calendarBloc),
          ],
          child: MaterialApp(
            navigatorKey: AppNavigator.navigatorKey,
            navigatorObservers: [AppNavigator.routeObserver, observer],
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: _DrawerHost(scaffoldKey: hostKey),
          ),
        ),
      );
      await settle(tester);
    }

    Future<void> teardownApp(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester, rounds: 4);
    }

    Future<void> openDrawer(WidgetTester tester) async {
      host().openDrawer();
      await settle(tester);
      expect(host().isDrawerOpen, isTrue);
    }

    Future<void> tapRow(WidgetTester tester, String id) async {
      await tester.tap(find.bySemanticsIdentifier(id));
      await settle(tester);
    }

    /// The arrow the page draws, by the id a device flow taps: the pair's
    /// half on a page with a drawer, the bar's lone arrow on one drawn
    /// without the menu button — one per screen either way. The calendar's
    /// three pages draw `AppBar`'s implied arrow, which carries no id.
    Future<void> tapArrow(WidgetTester tester) async {
      final byId = find.bySemanticsIdentifier(SemanticsIds.navBack);
      await tester.tap(
        byId.evaluate().isNotEmpty ? byId : find.byType(BackButton),
      );
      await settle(tester);
    }

    Future<void> systemBack(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await settle(tester);
    }

    Future<void> openFromDrawer(WidgetTester tester, _Row row) async {
      await pumpHost(tester);
      await openDrawer(tester);
      observer.clear();
      await tapRow(tester, row.rowId);
    }

    /// The drawer's Settings row, then [row] on the hub: the way every
    /// settings page is reached from the drawer since D1.
    Future<void> openFromHub(WidgetTester tester, _Row row) async {
      if (row.needsDeveloperMode) {
        DevOptions.instance.developerModeUnlocked = true;
      }
      await pumpHost(tester);
      await openDrawer(tester);
      await tapRow(tester, SemanticsIds.drawerSettings);
      expect(find.byType(SettingsHubPage), findsOneWidget);
      observer.clear();
      await tapRow(tester, row.rowId);
    }

    /// The page [row] opened is on top, carrying its stamp, and — where its
    /// bar has an anchor — the anchor is the page's one labelled level-1
    /// heading over level-2 section headers.
    void expectLanded(WidgetTester tester, _Row row) {
      expect(host().isDrawerOpen, isFalse);
      expect(find.byType(row.pageType), findsOneWidget);
      final pushed = observer.pageRoutes.single;
      expect(pushed.settings.arguments, row.stamp);
      final barId = row.barId;
      if (barId != null) {
        expect(find.bySemanticsIdentifier(barId), findsOneWidget);
        // The id's node carries the title as the heading that names the
        // route: a driver finds the bar, a screen reader still reads the
        // page's name as a heading and announces it on arrival.
        final title = tester
            .getSemantics(find.bySemanticsIdentifier(barId))
            .getSemanticsData();
        expect(title.identifier, barId);
        expect(title.label, row.title!(l10n));
        expect(title.flagsCollection.isHeader, isTrue);
        expect(title.headingLevel, 1);
        expect(title.flagsCollection.namesRoute, isTrue);
        // Android reads a heading from its level, VoiceOver from its flag,
        // so a heading is either. None is unlabelled (`AppBar`'s own
        // wrapper would be), the title is the page's one level-1 heading,
        // and every other one, a section header, is level 2 under it.
        final headings = find.semantics
            .byPredicate((node) {
              final data = node.getSemanticsData();
              return data.flagsCollection.isHeader || data.headingLevel > 0;
            })
            .evaluate()
            .map((node) => node.getSemanticsData())
            .toList();
        expect(headings.where((h) => h.label.isEmpty), isEmpty);
        expect(
          headings.where((h) => h.headingLevel == 1).map((h) => h.identifier),
          [barId],
        );
        expect(
          headings
              .where((h) => h.identifier != barId)
              .map((h) => h.headingLevel),
          everyElement(2),
        );
      }
      expect(tester.takeException(), isNull);
    }

    group('each drawer row opens its place, stamped (D1)', () {
      for (final row in _drawerRows) {
        testWidgets('${row.name}: ${row.pageType}, stamped '
            '${row.stamp?.kind.name ?? 'nothing'}', (tester) async {
          await openFromDrawer(tester, row);

          expectLanded(tester, row);

          await teardownApp(tester);
        });
      }
    });

    group('back from a drawer row by the arrow lands beneath, as system '
        'back does (D3)', () {
      for (final row in _drawerRows) {
        testWidgets('${row.name} lands on the host with the drawer closed', (
          tester,
        ) async {
          await openFromDrawer(tester, row);
          // The page carries no drawer: the arrow is the only leading
          // control, and there is no edge drag to open one.
          expect(Scaffold.of(tester.element(find.byType(AppBar))).hasDrawer,
              isFalse);
          expect(find.byIcon(Icons.menu_rounded), findsNothing);

          await tapArrow(tester);

          expect(find.byType(row.pageType), findsNothing);
          expect(find.text('host'), findsOneWidget);
          expect(host().isDrawerOpen, isFalse);

          await teardownApp(tester);
        });
      }
    });

    group('back from a drawer row by system back never raises the drawer '
        '(S6)', () {
      for (final row in _drawerRows) {
        testWidgets('${row.name} lands on the host with the drawer closed', (
          tester,
        ) async {
          await openFromDrawer(tester, row);

          await systemBack(tester);

          expect(find.byType(row.pageType), findsNothing);
          expect(find.text('host'), findsOneWidget);
          expect(host().isDrawerOpen, isFalse);

          await teardownApp(tester);
        });
      }
    });

    group('each hub row opens its page, stamped and anchored (D2)', () {
      for (final row in _hubRows) {
        testWidgets('${row.name}: ${row.pageType} with '
            '${row.barId ?? 'no bar anchor'}, stamped '
            '${row.stamp?.kind.name ?? 'nothing'}', (tester) async {
          await openFromHub(tester, row);

          expectLanded(tester, row);

          await teardownApp(tester);
        });
      }
    });

    group('back from a hub row lands on the hub, then on the host (D3)', () {
      for (final row in _hubRows) {
        testWidgets('${row.name} by the arrow', (tester) async {
          await openFromHub(tester, row);

          await tapArrow(tester);

          expect(find.byType(row.pageType), findsNothing);
          expect(find.byType(SettingsHubPage), findsOneWidget);
          expect(host().isDrawerOpen, isFalse);

          await tapArrow(tester);

          expect(find.byType(SettingsHubPage), findsNothing);
          expect(find.text('host'), findsOneWidget);
          expect(host().isDrawerOpen, isFalse);

          await teardownApp(tester);
        });

        testWidgets('${row.name} by system back', (tester) async {
          await openFromHub(tester, row);

          await systemBack(tester);

          expect(find.byType(row.pageType), findsNothing);
          expect(find.byType(SettingsHubPage), findsOneWidget);
          expect(host().isDrawerOpen, isFalse);

          await systemBack(tester);

          expect(find.byType(SettingsHubPage), findsNothing);
          expect(find.text('host'), findsOneWidget);
          expect(host().isDrawerOpen, isFalse);

          await teardownApp(tester);
        });
      }
    });

    group('the dialogs open and cancel cleanly', () {
      Future<void> openHub(WidgetTester tester) async {
        await pumpHost(tester);
        await openDrawer(tester);
        await tapRow(tester, SemanticsIds.drawerSettings);
        expect(find.byType(SettingsHubPage), findsOneWidget);
      }

      testWidgets('the hub\'s Language offers the languages, and Close '
          'changes nothing', (tester) async {
        await openHub(tester);

        await tapRow(tester, SemanticsIds.settingsHubRow('language'));

        expect(find.text(l10n.selectLanguage), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text(l10n.close),
          ),
        );
        await settle(tester);

        expect(find.text(l10n.selectLanguage), findsNothing);
        expect(appSettingsBloc.events, isEmpty);
        expect(find.byType(SettingsHubPage), findsOneWidget);

        await teardownApp(tester);
      });

      testWidgets('the hub\'s Theme, by the id it carried in the drawer '
          '(D11), offers the themes, and Close changes nothing', (
        tester,
      ) async {
        await openHub(tester);

        await tapRow(tester, SemanticsIds.settingsAppearance);

        expect(find.text(l10n.selectTheme), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text(l10n.close),
          ),
        );
        await settle(tester);

        expect(find.text(l10n.selectTheme), findsNothing);
        expect(appSettingsBloc.events, isEmpty);
        expect(find.byType(SettingsHubPage), findsOneWidget);

        await teardownApp(tester);
      });

      testWidgets('About closes the drawer, shows the version, and system '
          'back leaves the host as it was', (tester) async {
        await pumpHost(tester);
        await openDrawer(tester);

        await tapRow(tester, SemanticsIds.drawerAbout);

        expect(host().isDrawerOpen, isFalse);
        expect(
          find.bySemanticsIdentifier(SemanticsIds.aboutDialog),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(kAppVersion),
          ),
          findsOneWidget,
        );
        await systemBack(tester);

        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('host'), findsOneWidget);
        expect(host().isDrawerOpen, isFalse);

        await teardownApp(tester);
      });
    });

    testWidgets('five taps on the header icon unlock developer mode, close '
        'the drawer, and the hub then lists Developer options', (
      tester,
    ) async {
      await pumpHost(tester);
      await openDrawer(tester);
      expect(DevOptions.instance.developerModeUnlocked, isFalse);

      final icon = find.descendant(
        of: find.byType(AppDrawer),
        matching: find.byIcon(Icons.fitness_center_rounded),
      );
      for (var i = 0; i < 5; i++) {
        await tester.tap(icon);
        await tester.pump();
      }
      await settle(tester);

      expect(DevOptions.instance.developerModeUnlocked, isTrue);
      expect(host().isDrawerOpen, isFalse);
      expect(find.text(l10n.developerModeUnlocked), findsOneWidget);

      await openDrawer(tester);
      await tapRow(tester, SemanticsIds.drawerSettings);
      expect(
        find.bySemanticsIdentifier(
          SemanticsIds.settingsHubRow('developerOptions'),
        ),
        findsOneWidget,
      );

      // The unlock was stored; put the stored flag back for the suites
      // after this one.
      DevOptions.instance.lockDeveloperMode();
      await tester.runAsync(
        () async => (await DevOptionsService.getInstance()).saveOptions(),
      );
      await teardownApp(tester);
    });

    group('dedupe', () {
      testWidgets('toPermissions over Permissions pushes nothing', (
        tester,
      ) async {
        await openFromHub(
          tester,
          _row(SemanticsIds.settingsHubRow('permissions')),
        );
        observer.clear();

        await AppNavigator.toPermissions(
          tester.element(find.byType(PermissionsPage)),
        );
        await settle(tester);

        expect(observer.pageRoutes, isEmpty);
        expect(
          find.byType(PermissionsPage, skipOffstage: false),
          findsOneWidget,
        );

        await teardownApp(tester);
      });

      testWidgets('toSettings over App settings pushes nothing (S15, D3)', (
        tester,
      ) async {
        await openFromHub(tester, _row(SemanticsIds.settingsHubRow('settings')));
        observer.clear();

        await AppNavigator.toSettings(
          tester.element(find.byType(SettingsPage)),
        );
        await settle(tester);

        expect(observer.pageRoutes, isEmpty);
        expect(
          find.byType(SettingsPage, skipOffstage: false),
          findsOneWidget,
        );

        await teardownApp(tester);
      });
    });

    // §4.3's two deep links, at the navigator level: a stand-in opener with
    // no drawer takes the place of the calendar and the editor, so neither is
    // built; each pushes through the same `AppNavigator` call its page makes
    // (`CalendarPage._openSettings`, the editor's counter picker).
    group('deep links land back on their opener', () {
      /// Pushes the stand-in opener over the host and returns a context on
      /// its route.
      Future<BuildContext> pushOpener(WidgetTester tester) async {
        await pumpHost(tester);
        unawaited(
          AppNavigator.push<void>(
            tester.element(find.text('host')),
            const _Opener(),
          ),
        );
        await settle(tester);
        observer.clear();
        return tester.element(find.text('opener'));
      }

      testWidgets('the calendar\'s Calendar settings: the arrow pops null to '
          'the opener, no drawer raised', (tester) async {
        final opener = await pushOpener(tester);
        unawaited(AppNavigator.toCalendarSettings(opener));
        await settle(tester);
        final pushed = observer.pageRoutes.single;
        expect(
          pushed.settings.arguments,
          const NavDestination(NavDestinationKind.calendarSettings),
        );
        Object? result = #unset;
        unawaited(pushed.popped.then((Object? value) => result = value));

        await tapArrow(tester);

        expect(find.byType(CalendarSettingsPage), findsNothing);
        expect(find.text('opener'), findsOneWidget);
        expect(result, isNull);
        expect(host().isDrawerOpen, isFalse);

        await teardownApp(tester);
      });

      testWidgets('the editor\'s Counters: the arrow pops null to the '
          'opener, no drawer raised (D3)', (tester) async {
        final opener = await pushOpener(tester);
        var returned = false;
        unawaited(
          AppNavigator.toCounterManagement(
            opener,
            noteId: 'note-1',
          ).then((_) => returned = true),
        );
        await settle(tester);
        final pushed = observer.pageRoutes.single;
        expect(
          pushed.settings.arguments,
          NavDestination.counterManagement(noteId: 'note-1'),
        );
        Object? result = #unset;
        unawaited(pushed.popped.then((Object? value) => result = value));

        await tapArrow(tester);

        expect(find.byType(CounterManagementPage), findsNothing);
        expect(find.text('opener'), findsOneWidget);
        expect(returned, isTrue);
        expect(result, isNull);
        expect(host().isDrawerOpen, isFalse);

        await teardownApp(tester);
      });
    });
  });

  group('restore', () {
    late NavigationHistoryService history;
    late _RecordingObserver observer;
    late GlobalKey<ScaffoldState> hostKey;

    setUp(() {
      history = NavigationHistoryService(
        writeDebounce: const Duration(milliseconds: 10),
      );
      GetIt.I.registerSingleton<NavigationHistoryService>(history);
      observer = _RecordingObserver();
      hostKey = GlobalKey<ScaffoldState>();
    });

    tearDown(() async {
      await GetIt.I.unregister<NavigationHistoryService>();
      history.dispose();
    });

    /// Written in real async: the file-backed database answers on a
    /// background isolate `FakeAsync` never lets run.
    Future<void> saveStack(
      WidgetTester tester,
      List<NavDestination> stack,
    ) async {
      await tester.runAsync(() async {
        final settings = await SettingsService.getInstance();
        await settings.saveLastLocationStack(stack);
      });
    }

    /// The host is registered with [DrawerHostRegistry] the way the browser
    /// beneath a restored chain registers itself; its drawer is a stand-in,
    /// since what is asserted is only whether it opens.
    Future<void> pumpApp(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: AppNavigator.navigatorKey,
          navigatorObservers: [
            AppNavigator.routeObserver,
            NavigationHistoryObserver(history),
            observer,
          ],
          home: _RestoreHost(scaffoldKey: hostKey),
        ),
      );
    }

    /// Runs the replay for real: drift answers on futures `FakeAsync` would
    /// never complete, and no frame is pumped, so the pushed routes stay
    /// unbuilt.
    Future<void> restore(WidgetTester tester) async {
      await tester.runAsync(AppNavigator.restoreLastLocation);
    }

    /// Takes [route] off the stack with [result], as its page's back would,
    /// without a frame ever building the page.
    Future<void> popUnbuilt(
      WidgetTester tester,
      Route<dynamic> route,
      Object? result,
    ) async {
      await tester.runAsync(() async {
        AppNavigator.navigatorKey.currentState!.removeRoute(route, result);
        await Future<void>.delayed(Duration.zero);
      });
    }

    /// Lets an opened drawer finish its slide.
    Future<void> settleHost(WidgetTester tester) async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    Future<void> teardownApp(WidgetTester tester) =>
        tester.pumpWidget(const SizedBox.shrink());

    List<NavDestination> restoredDestinations() => [
      for (final route in observer.pageRoutes)
        if (route.settings.arguments is NavDestination)
          route.settings.arguments as NavDestination,
    ];

    Widget pageOf(Route<dynamic> route) {
      return (route as PageRouteBuilder<Object?>).pageBuilder(
        AppNavigator.navigatorKey.currentContext!,
        const AlwaysStoppedAnimation<double>(1),
        const AlwaysStoppedAnimation<double>(0),
      );
    }

    /// The destination a route of [kind] is stamped with; the per-note
    /// counter page names the live counter.
    NavDestination destinationOf(NavDestinationKind kind) =>
        kind == NavDestinationKind.counterPerNote
        ? NavDestination.counterPerNote(counterId: counterId)
        : NavDestination(kind);

    testWidgets('every restorable settings-family kind replays, in order, to '
        'a route stamped with it and the page it names', (tester) async {
      DevOptions.instance.developerModeUnlocked = true;
      final stack = [for (final kind in _restorable.keys) destinationOf(kind)];
      await saveStack(tester, stack);
      await pumpApp(tester);
      observer.clear();

      await restore(tester);

      expect(restoredDestinations(), stack);
      for (final route in observer.pageRoutes) {
        final kind = (route.settings.arguments! as NavDestination).kind;
        expect(
          pageOf(route).runtimeType,
          _restorable[kind],
          reason: '${kind.name} restored the wrong page',
        );
      }

      await teardownApp(tester);
    });

    for (final kind in _restorable.keys) {
      testWidgets('a restored ${kind.name} popped lands beneath with no '
          'drawer raised (D3)', (tester) async {
        expect(kind.reopensDrawerOnPop, isFalse);
        DevOptions.instance.developerModeUnlocked = true;
        await saveStack(tester, [destinationOf(kind)]);
        await pumpApp(tester);
        observer.clear();
        await restore(tester);

        await popUnbuilt(tester, observer.pageRoutes.single, null);
        await settleHost(tester);

        expect(find.text('root'), findsOneWidget);
        expect(hostKey.currentState!.isDrawerOpen, isFalse);

        await teardownApp(tester);
      });
    }

    testWidgets('a page opened from the hub records [settingsHub, page], '
        'Vocabularies records under Markdown shortcuts (S26), and the '
        'recorded chain restores whole', (tester) async {
      await pumpApp(tester);
      // Pushed through the calls the pages make, from the navigator's own
      // context and without a frame, so no page is built; a stand-in carries
      // the hub's stamp.
      final navigator = AppNavigator.navigatorKey.currentContext!;
      unawaited(
        AppNavigator.push<void>(
          navigator,
          const _Opener(),
          destination: const NavDestination(NavDestinationKind.settingsHub),
        ),
      );
      unawaited(AppNavigator.toMarkdownSettings(navigator, allShortcuts: []));
      unawaited(AppNavigator.toVocabularies(navigator));

      final recorded = history.stack;
      expect(recorded, const [
        NavDestination(NavDestinationKind.settingsHub),
        NavDestination(NavDestinationKind.markdownSettings),
        NavDestination(NavDestinationKind.vocabularies),
      ]);
      await teardownApp(tester);

      await saveStack(tester, recorded);
      await pumpApp(tester);
      observer.clear();
      await restore(tester);

      expect(restoredDestinations(), recorded);

      await teardownApp(tester);
    });

    testWidgets('a per-note counter page whose counter is gone stops the '
        'chain beneath it', (tester) async {
      await saveStack(tester, [
        NavDestination.counterManagement(),
        NavDestination.counterPerNote(counterId: 'deleted-counter'),
      ]);
      await pumpApp(tester);
      observer.clear();

      await restore(tester);

      expect(restoredDestinations(), [NavDestination.counterManagement()]);

      await teardownApp(tester);
    });

    testWidgets('a per-note counter page whose counter is now global '
        'restores the Counters page alone', (tester) async {
      await saveStack(tester, [
        NavDestination.counterManagement(),
        NavDestination.counterPerNote(counterId: globalCounterId),
      ]);
      await pumpApp(tester);
      observer.clear();

      await restore(tester);

      expect(restoredDestinations(), [NavDestination.counterManagement()]);

      await teardownApp(tester);
    });

    testWidgets('Developer options is not reopened once developer mode is '
        'locked', (tester) async {
      DevOptions.instance.lockDeveloperMode();
      await saveStack(tester, const [
        NavDestination(NavDestinationKind.settingsHub),
        NavDestination(NavDestinationKind.developerOptions),
      ]);
      await pumpApp(tester);
      observer.clear();

      await restore(tester);

      expect(restoredDestinations(), const [
        NavDestination(NavDestinationKind.settingsHub),
      ]);

      await teardownApp(tester);
    });

    testWidgets('an unknown kind in the stored stack is dropped and the rest '
        'restored, never throws (§4.3)', (tester) async {
      final db = await tester.runAsync(AppDatabase.getInstance);
      await tester.runAsync(
        () => db!.userSettingsDao.setValue(
          SettingsKeys.lastLocationStack,
          jsonEncode({
            'v': NavDestination.stackVersion,
            'stack': [
              {'k': 'settings'},
              {'k': 'neverAKind'},
              {'k': 'permissions'},
            ],
          }),
        ),
      );
      await pumpApp(tester);
      observer.clear();

      await restore(tester);

      expect(restoredDestinations(), const [
        NavDestination(NavDestinationKind.settings),
        NavDestination(NavDestinationKind.permissions),
      ]);
      expect(history.isRecording, isTrue);

      await teardownApp(tester);
    });
  });
}

/// A drawer or hub row that opens a page, with the page it lands on.
class _Row {
  const _Row({
    required this.name,
    required this.rowId,
    required this.pageType,
    required this.stamp,
    this.barId,
    this.title,
    this.needsDeveloperMode = false,
  });

  final String name;
  final String rowId;
  final Type pageType;

  /// The settings bar's anchor and the title it reads; null on a page whose
  /// bar has none (the calendar's pages, the categories, appearance and
  /// guide pages, which a flow anchors on a control of their own).
  final String? barId;
  final String Function(AppLocalizations l10n)? title;

  /// The `NavDestination` the pushed route carries; null for a page restore
  /// cannot rebuild.
  final NavDestination? stamp;

  /// Developer options is drawn only once taps on the drawer header's icon
  /// have unlocked it.
  final bool needsDeveloperMode;
}

/// The drawer's rows that open a page (D1), top to bottom; About opens a
/// dialog and has its own case.
final _drawerRows = <_Row>[
  _Row(
    name: 'Calendar',
    rowId: SemanticsIds.drawerCalendar,
    pageType: CalendarPage,
    stamp: const NavDestination(NavDestinationKind.calendar),
  ),
  _Row(
    name: 'Overview',
    rowId: SemanticsIds.drawerCalendarOverview,
    pageType: CalendarOverviewPage,
    stamp: const NavDestination(NavDestinationKind.calendarOverview),
  ),
  _Row(
    name: 'Report',
    rowId: SemanticsIds.drawerCalendarReport,
    pageType: CalendarReportPage,
    stamp: const NavDestination(NavDestinationKind.calendarReport),
  ),
  _Row(
    name: 'Categories',
    rowId: SemanticsIds.drawerCalendarCategories,
    pageType: CalendarCategoriesPage,
    stamp: const NavDestination(NavDestinationKind.calendarCategories),
  ),
  _Row(
    name: 'Alerts',
    rowId: SemanticsIds.drawerAlerts,
    pageType: AlertsPage,
    barId: SemanticsIds.settingsBarAlerts,
    title: (l10n) => l10n.alertsTitle,
    stamp: const NavDestination(NavDestinationKind.alerts),
  ),
  _Row(
    name: 'Counters',
    rowId: SemanticsIds.drawerCounters,
    pageType: CounterManagementPage,
    barId: SemanticsIds.settingsBarCounters,
    title: (l10n) => l10n.counterSettings,
    stamp: NavDestination.counterManagement(),
  ),
  _Row(
    name: 'Settings',
    rowId: SemanticsIds.drawerSettings,
    pageType: SettingsHubPage,
    barId: SemanticsIds.settingsBarHub,
    title: (l10n) => l10n.settingsHubTitle,
    stamp: const NavDestination(NavDestinationKind.settingsHub),
  ),
  _Row(
    name: 'How to use ANTA',
    rowId: SemanticsIds.drawerHowTo,
    pageType: CalendarGuidePage,
    stamp: const NavDestination(NavDestinationKind.calendarGuide),
  ),
];

/// The hub's rows that open a page (D2); Language and Theme open dialogs
/// and have their own cases.
final _hubRows = <_Row>[
  _Row(
    name: 'Calendar settings',
    rowId: SemanticsIds.settingsHubRow('calendarSettings'),
    pageType: CalendarSettingsPage,
    barId: SemanticsIds.settingsBarCalendar,
    title: (l10n) => l10n.calendarSettings,
    stamp: const NavDestination(NavDestinationKind.calendarSettings),
  ),
  _Row(
    name: 'Appearance',
    rowId: SemanticsIds.settingsHubRow('calendarAppearance'),
    pageType: CalendarAppearancePage,
    stamp: const NavDestination(NavDestinationKind.calendarAppearance),
  ),
  _Row(
    name: 'Categories',
    rowId: SemanticsIds.settingsHubRow('calendarCategories'),
    pageType: CalendarCategoriesPage,
    stamp: const NavDestination(NavDestinationKind.calendarCategories),
  ),
  _Row(
    name: 'Editor and markdown',
    rowId: SemanticsIds.settingsHubRow('markdownSettings'),
    pageType: MarkdownSettingsPage,
    barId: SemanticsIds.settingsBarMarkdown,
    title: (l10n) => l10n.markdownShortcuts,
    stamp: const NavDestination(NavDestinationKind.markdownSettings),
  ),
  _Row(
    name: 'Counters',
    rowId: SemanticsIds.settingsHubRow('counterManagement'),
    pageType: CounterManagementPage,
    barId: SemanticsIds.settingsBarCounters,
    title: (l10n) => l10n.counterSettings,
    stamp: NavDestination.counterManagement(),
  ),
  _Row(
    name: 'General',
    rowId: SemanticsIds.settingsHubRow('settings'),
    pageType: SettingsPage,
    barId: SemanticsIds.settingsBarApp,
    title: (l10n) => l10n.appSettings,
    stamp: const NavDestination(NavDestinationKind.settings),
  ),
  _Row(
    name: 'Databases',
    rowId: SemanticsIds.settingsHubRow('databaseSettings'),
    pageType: DatabaseSettingsPage,
    barId: SemanticsIds.settingsBarDatabases,
    title: (l10n) => l10n.databaseSettings,
    stamp: const NavDestination(NavDestinationKind.databaseSettings),
  ),
  _Row(
    name: 'Sharing',
    rowId: SemanticsIds.settingsHubRow('syncSettings'),
    pageType: SyncSettingsPage,
    barId: SemanticsIds.settingsBarSharing,
    title: (l10n) => l10n.sharingSettings,
    stamp: const NavDestination(NavDestinationKind.syncSettings),
  ),
  _Row(
    name: 'Permissions',
    rowId: SemanticsIds.settingsHubRow('permissions'),
    pageType: PermissionsPage,
    barId: SemanticsIds.settingsBarPermissions,
    title: (l10n) => l10n.permissionsTitle,
    stamp: const NavDestination(NavDestinationKind.permissions),
  ),
  _Row(
    name: 'Developer options',
    rowId: SemanticsIds.settingsHubRow('developerOptions'),
    pageType: DeveloperOptionsPage,
    barId: SemanticsIds.settingsBarDeveloper,
    title: (l10n) => l10n.developerOptions,
    stamp: const NavDestination(NavDestinationKind.developerOptions),
    needsDeveloperMode: true,
  ),
  _Row(
    name: 'How the calendar works',
    rowId: SemanticsIds.settingsHubRow('calendarGuide'),
    pageType: CalendarGuidePage,
    stamp: const NavDestination(NavDestinationKind.calendarGuide),
  ),
];

_Row _row(String rowId) => _hubRows.singleWhere((row) => row.rowId == rowId);

/// Every settings-family kind `_pageFor` rebuilds, in the order a stack of
/// all of them is saved, with the page each one names.
const _restorable = <NavDestinationKind, Type>{
  NavDestinationKind.calendarSettings: CalendarSettingsPage,
  NavDestinationKind.calendarCategories: CalendarCategoriesPage,
  NavDestinationKind.calendarAppearance: CalendarAppearancePage,
  NavDestinationKind.eventTemplates: EventTemplatesPage,
  NavDestinationKind.vocabularies: VocabulariesPage,
  NavDestinationKind.databaseSettings: DatabaseSettingsPage,
  NavDestinationKind.settings: SettingsPage,
  NavDestinationKind.syncSettings: SyncSettingsPage,
  NavDestinationKind.counterManagement: CounterManagementPage,
  NavDestinationKind.alerts: AlertsPage,
  NavDestinationKind.permissions: PermissionsPage,
  NavDestinationKind.calendarGuide: CalendarGuidePage,
  NavDestinationKind.settingsHub: SettingsHubPage,
  NavDestinationKind.markdownSettings: MarkdownSettingsPage,
  NavDestinationKind.markdownColors: MarkdownColorsPage,
  NavDestinationKind.noteBarAssignment: NoteBarAssignmentPage,
  NavDestinationKind.noteMoneyCurrency: NoteMoneyCurrencyPage,
  NavDestinationKind.counterPerNote: CounterPerNotePage,
  NavDestinationKind.developerOptions: DeveloperOptionsPage,
};

class _RecordingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  /// The page routes pushed — the drawer itself is no route, and a dialog is
  /// a popup route.
  List<Route<dynamic>> get pageRoutes => [
    for (final route in pushed)
      if (route is PageRoute) route,
  ];

  void clear() => pushed.clear();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

/// Keeps every event a dialog row sends, so a cancelled dialog can be shown
/// to have sent none.
class _RecordingSettingsBloc extends AppSettingsBloc {
  final List<AppSettingsEvent> events = [];

  @override
  void onEvent(AppSettingsEvent event) {
    events.add(event);
    super.onEvent(event);
  }
}

/// Stands in for the folder page: a scaffold that hosts the drawer and
/// registers itself the way every full-page screen does.
class _DrawerHost extends StatefulWidget {
  const _DrawerHost({required this.scaffoldKey});

  final GlobalKey<ScaffoldState> scaffoldKey;

  @override
  State<_DrawerHost> createState() => _DrawerHostState();
}

class _DrawerHostState extends State<_DrawerHost> {
  @override
  void initState() {
    super.initState();
    DrawerHostRegistry.register(widget.scaffoldKey);
  }

  @override
  void dispose() {
    DrawerHostRegistry.unregister(widget.scaffoldKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: widget.scaffoldKey,
      drawer: const AppDrawer(),
      body: const Center(child: Text('host')),
    );
  }
}

/// Stands in for a page that opens a settings page directly — the calendar,
/// the editor — and has no drawer of its own.
class _Opener extends StatelessWidget {
  const _Opener();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('opener')));
  }
}

/// The restore suite's host: registered like [_DrawerHost], with a drawer
/// that needs nothing bound.
class _RestoreHost extends StatefulWidget {
  const _RestoreHost({required this.scaffoldKey});

  final GlobalKey<ScaffoldState> scaffoldKey;

  @override
  State<_RestoreHost> createState() => _RestoreHostState();
}

class _RestoreHostState extends State<_RestoreHost> {
  @override
  void initState() {
    super.initState();
    DrawerHostRegistry.register(widget.scaffoldKey);
  }

  @override
  void dispose() {
    DrawerHostRegistry.unregister(widget.scaffoldKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: widget.scaffoldKey,
      drawer: const Drawer(child: Text('drawer')),
      body: const Text('root'),
    );
  }
}
