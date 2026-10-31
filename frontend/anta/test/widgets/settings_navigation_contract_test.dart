import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/app_settings/app_settings_bloc.dart';
import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/bloc/counter/counter_bloc.dart';
import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/bloc/pairing/pairing_bloc.dart';
import 'package:anta/bloc/permissions/permissions_bloc.dart';
import 'package:anta/bloc/sync/sync_bloc.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/dev_options.dart';
import 'package:anta/models/nav_destination.dart';
import 'package:anta/pages/alerts_page.dart';
import 'package:anta/pages/calendar_appearance_page.dart';
import 'package:anta/pages/calendar_categories_page.dart';
import 'package:anta/pages/calendar_guide_page.dart';
import 'package:anta/pages/calendar_settings_page.dart';
import 'package:anta/pages/counter_management_page.dart';
import 'package:anta/pages/database_settings_page.dart';
import 'package:anta/pages/developer_options_page.dart';
import 'package:anta/pages/event_templates_page.dart';
import 'package:anta/pages/markdown_settings_page.dart';
import 'package:anta/pages/permissions_page.dart';
import 'package:anta/pages/settings_page.dart';
import 'package:anta/pages/sync_settings_page.dart';
import 'package:anta/pages/vocabularies_page.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/dev_options_service.dart';
import 'package:anta/services/drawer_host_registry.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/navigation_history_service.dart';
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/permission_gateway.dart';
import 'package:anta/services/permission_service.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/app_drawer.dart';

import '../services/pairing_support.dart';
import '../services/permission_support.dart';

/// The settings navigation contract **as the app keeps it today**, written
/// in S0 of the settings rework (`docs/settings-rework-roadmap.md` §4.3) so
/// that S2, which replaces the drawer's rows with a hub and retires the
/// reopen-the-drawer mechanism (D1–D3), rewrites this file and the diff
/// between the two is the proof of what changed. A case S2 changes says so
/// in its name: `(today; S2 …)`.
///
/// The drawer flow drives the real rows over the real pages, so every page
/// the drawer reaches is built: the suite runs over the file-backed
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
  late CounterBloc counterBloc;
  late CalendarBloc calendarBloc;

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
    counterBloc = CounterBloc(counterService: await CounterService.getInstance())
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
    /// without the menu button — one per screen either way.
    Future<void> tapArrow(WidgetTester tester) async {
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.navBack));
      await settle(tester);
    }

    Future<void> systemBack(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await settle(tester);
    }

    Future<void> openFromDrawer(WidgetTester tester, _Row row) async {
      if (row.needsDeveloperMode) {
        DevOptions.instance.developerModeUnlocked = true;
      }
      await pumpHost(tester);
      await openDrawer(tester);
      observer.clear();
      await tapRow(tester, row.rowId);
    }

    group('each settings row opens its page, stamped and anchored', () {
      for (final row in _rows) {
        testWidgets('${row.name}: ${row.pageType} with ${row.barId}, '
            'stamped ${row.stamp?.kind.name ?? 'nothing'}', (tester) async {
          await openFromDrawer(tester, row);

          expect(host().isDrawerOpen, isFalse);
          expect(find.byType(row.pageType), findsOneWidget);
          final pushed = observer.pageRoutes.single;
          expect(pushed.settings.arguments, row.stamp);
          expect(find.bySemanticsIdentifier(row.barId), findsOneWidget);
          // The id's node carries the title as the heading that names the
          // route: a driver finds the bar, a screen reader still reads the
          // page's name as a heading and announces it on arrival.
          final title = tester
              .getSemantics(find.bySemanticsIdentifier(row.barId))
              .getSemanticsData();
          expect(title.identifier, row.barId);
          expect(title.label, row.title(l10n));
          expect(title.flagsCollection.isHeader, isTrue);
          expect(title.flagsCollection.namesRoute, isTrue);
          // And it is the page's only heading: `AppBar`'s own wrapper would
          // otherwise stay beside it as a heading with no label.
          expect(
            find.semantics
                .byFlag(SemanticsFlag.isHeader)
                .evaluate()
                .map((node) => node.label),
            [row.title(l10n)],
          );
          expect(tester.takeException(), isNull);

          await teardownApp(tester);
        });
      }
    });

    group('back by the arrow', () {
      for (final row in _rows) {
        final lands = row.arrowRaisesDrawer
            ? 'raises the drawer again'
            : 'lands on the host with the drawer closed';
        final today = row.arrowRaisesDrawer ? ' (today; S2 lands beneath)' : '';
        testWidgets('${row.name} $lands$today', (tester) async {
          await openFromDrawer(tester, row);

          await tapArrow(tester);

          expect(find.byType(row.pageType), findsNothing);
          expect(find.text('host'), findsOneWidget);
          expect(host().isDrawerOpen, row.arrowRaisesDrawer);

          await teardownApp(tester);
        });
      }
    });

    group('back by system back never raises the drawer (S6)', () {
      for (final row in _rows) {
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

    group('the dialog rows open their dialog and cancel cleanly', () {
      testWidgets('Language closes the drawer, offers the languages, and '
          'Close changes nothing', (tester) async {
        await pumpHost(tester);
        await openDrawer(tester);

        await tapRow(tester, SemanticsIds.drawerLanguage);

        expect(host().isDrawerOpen, isFalse);
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
        expect(host().isDrawerOpen, isFalse);

        await teardownApp(tester);
      });

      testWidgets('Theme closes the drawer, offers the themes, and Close '
          'changes nothing', (tester) async {
        await pumpHost(tester);
        await openDrawer(tester);

        await tapRow(tester, SemanticsIds.settingsAppearance);

        expect(host().isDrawerOpen, isFalse);
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
        expect(host().isDrawerOpen, isFalse);

        await teardownApp(tester);
      });

      testWidgets('About closes the drawer, shows the about dialog, and '
          'Close leaves the host as it was', (tester) async {
        await pumpHost(tester);
        await openDrawer(tester);

        await tapRow(tester, SemanticsIds.drawerAbout);

        expect(host().isDrawerOpen, isFalse);
        expect(find.byType(AboutDialog), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: find.byType(AboutDialog),
            matching: find.text(
              const DefaultMaterialLocalizations().closeButtonLabel,
            ),
          ),
        );
        await settle(tester);

        expect(find.byType(AboutDialog), findsNothing);
        expect(find.text('host'), findsOneWidget);
        expect(host().isDrawerOpen, isFalse);

        await teardownApp(tester);
      });
    });

    group('dedupe', () {
      testWidgets('toPermissions over Permissions pushes nothing', (
        tester,
      ) async {
        await openFromDrawer(tester, _row(SemanticsIds.drawerPermissions));
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

      testWidgets('toSettings over App settings pushes a second page '
          '(today, S15; S2 dedupes)', (tester) async {
        await openFromDrawer(tester, _row(SemanticsIds.drawerSettings));
        observer.clear();

        // Not awaited: the push future completes when the page is popped.
        AppNavigator.toSettings(tester.element(find.byType(SettingsPage)));
        await settle(tester);

        expect(observer.pageRoutes, hasLength(1));
        expect(
          find.byType(SettingsPage, skipOffstage: false),
          findsNWidgets(2),
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

      testWidgets('the editor\'s Counters: the arrow lands on the opener, no '
          'drawer raised, though it still reports openDrawer (today; S2 '
          'retires it)', (tester) async {
        final opener = await pushOpener(tester);
        SettingsResult? result;
        var returned = false;
        unawaited(
          AppNavigator.toCounterManagement(opener, noteId: 'note-1').then((
            value,
          ) {
            result = value;
            returned = true;
          }),
        );
        await settle(tester);
        expect(
          observer.pageRoutes.single.settings.arguments,
          NavDestination.counterManagement(noteId: 'note-1'),
        );

        await tapArrow(tester);

        expect(find.byType(CounterManagementPage), findsNothing);
        expect(find.text('opener'), findsOneWidget);
        expect(returned, isTrue);
        expect(result, SettingsResult.openDrawer);
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

    testWidgets('every restorable settings-family kind replays, in order, to '
        'a route stamped with it and the page it names', (tester) async {
      await saveStack(tester, [
        for (final kind in _restorable.keys) NavDestination(kind),
      ]);
      await pumpApp(tester);
      observer.clear();

      await restore(tester);

      expect(restoredDestinations(), [
        for (final kind in _restorable.keys) NavDestination(kind),
      ]);
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
      final reopens = _reopenKinds.contains(kind);
      final name = reopens
          ? 'a restored ${kind.name} popped with openDrawer raises the top '
                'drawer (today; S2 retires it)'
          : 'a restored ${kind.name} popped with openDrawer raises nothing';
      testWidgets(name, (tester) async {
        expect(kind.reopensDrawerOnPop, reopens);
        await saveStack(tester, [NavDestination(kind)]);
        await pumpApp(tester);
        observer.clear();
        await restore(tester);

        await popUnbuilt(
          tester,
          observer.pageRoutes.single,
          SettingsResult.openDrawer,
        );
        await settleHost(tester);

        expect(hostKey.currentState!.isDrawerOpen, reopens);

        await teardownApp(tester);
      });
    }

    testWidgets('a restored Permissions page does not ask for the drawer, '
        'though the drawer row\'s does (today, S6)', (tester) async {
      await saveStack(tester, const [
        NavDestination(NavDestinationKind.permissions),
      ]);
      await pumpApp(tester);
      observer.clear();

      await restore(tester);

      final page = pageOf(observer.pageRoutes.single) as PermissionsPage;
      expect(page.popsToDrawer, isFalse);

      await teardownApp(tester);
    });

    testWidgets('only the bottom-most reopen kind carries the continuation '
        '(today; S2 retires it)', (tester) async {
      await saveStack(tester, const [
        NavDestination(NavDestinationKind.settings),
        NavDestination(NavDestinationKind.databaseSettings),
      ]);
      await pumpApp(tester);
      observer.clear();
      await restore(tester);
      final [appSettings, databases] = observer.pageRoutes;

      // Both leave before a frame, so neither page is ever built; the upper
      // one asks for the drawer, the lower one does not. App settings alone
      // raises it (the case above), so the lower route is the only one
      // listened to.
      await popUnbuilt(tester, databases, SettingsResult.openDrawer);
      await popUnbuilt(tester, appSettings, null);
      await settleHost(tester);

      expect(hostKey.currentState!.isDrawerOpen, isFalse);

      await teardownApp(tester);
    });

    testWidgets('an unknown kind in the stored stack truncates it there, '
        'never throws (today; §4.3 asks S2 to drop the entry and keep the '
        'rest)', (tester) async {
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
      ]);
      expect(history.isRecording, isTrue);

      await teardownApp(tester);
    });
  });
}

/// A drawer row that opens a settings page, with what today's app does
/// with it.
class _Row {
  const _Row({
    required this.name,
    required this.rowId,
    required this.pageType,
    required this.barId,
    required this.title,
    required this.stamp,
    required this.arrowRaisesDrawer,
    this.needsDeveloperMode = false,
  });

  final String name;
  final String rowId;
  final Type pageType;
  final String barId;
  final String Function(AppLocalizations l10n) title;

  /// The `NavDestination` the pushed route carries; null for a page restore
  /// cannot rebuild.
  final NavDestination? stamp;

  /// Whether the bar's arrow reports `SettingsResult.openDrawer` — the
  /// pages that set `popsToDrawer`, which the row's awaiter honours.
  final bool arrowRaisesDrawer;

  /// Developer options is drawn only once taps on the drawer header's icon
  /// have unlocked it.
  final bool needsDeveloperMode;
}

final _rows = <_Row>[
  _Row(
    name: 'Calendar settings',
    rowId: SemanticsIds.drawerCalendarSettings,
    pageType: CalendarSettingsPage,
    barId: SemanticsIds.settingsBarCalendar,
    title: (l10n) => l10n.calendarSettings,
    stamp: const NavDestination(NavDestinationKind.calendarSettings),
    arrowRaisesDrawer: false,
  ),
  _Row(
    name: 'Alerts',
    rowId: SemanticsIds.drawerAlerts,
    pageType: AlertsPage,
    barId: SemanticsIds.settingsBarAlerts,
    title: (l10n) => l10n.alertsTitle,
    stamp: const NavDestination(NavDestinationKind.alerts),
    arrowRaisesDrawer: false,
  ),
  _Row(
    name: 'Markdown shortcuts',
    rowId: SemanticsIds.drawerMarkdownShortcuts,
    pageType: MarkdownSettingsPage,
    barId: SemanticsIds.settingsBarMarkdown,
    title: (l10n) => l10n.markdownShortcuts,
    // Unstamped, so nothing above it is recorded either: Vocabularies,
    // opened from here, is never restored (S26).
    stamp: null,
    arrowRaisesDrawer: true,
  ),
  _Row(
    name: 'Counters',
    rowId: SemanticsIds.drawerCounters,
    pageType: CounterManagementPage,
    barId: SemanticsIds.settingsBarCounters,
    title: (l10n) => l10n.counterSettings,
    stamp: NavDestination.counterManagement(),
    arrowRaisesDrawer: true,
  ),
  _Row(
    name: 'Sharing',
    rowId: SemanticsIds.drawerSharing,
    pageType: SyncSettingsPage,
    barId: SemanticsIds.settingsBarSharing,
    title: (l10n) => l10n.sharingSettings,
    stamp: const NavDestination(NavDestinationKind.syncSettings),
    arrowRaisesDrawer: true,
  ),
  _Row(
    name: 'App settings',
    rowId: SemanticsIds.drawerSettings,
    pageType: SettingsPage,
    barId: SemanticsIds.settingsBarApp,
    title: (l10n) => l10n.appSettings,
    stamp: const NavDestination(NavDestinationKind.settings),
    arrowRaisesDrawer: true,
  ),
  _Row(
    name: 'Databases',
    rowId: SemanticsIds.settingsDatabases,
    pageType: DatabaseSettingsPage,
    barId: SemanticsIds.settingsBarDatabases,
    title: (l10n) => l10n.databaseSettings,
    stamp: const NavDestination(NavDestinationKind.databaseSettings),
    arrowRaisesDrawer: true,
  ),
  _Row(
    name: 'Permissions',
    rowId: SemanticsIds.drawerPermissions,
    pageType: PermissionsPage,
    barId: SemanticsIds.settingsBarPermissions,
    title: (l10n) => l10n.permissionsTitle,
    stamp: const NavDestination(NavDestinationKind.permissions),
    arrowRaisesDrawer: true,
  ),
  _Row(
    name: 'Developer options',
    rowId: SemanticsIds.drawerDeveloperOptions,
    pageType: DeveloperOptionsPage,
    barId: SemanticsIds.settingsBarDeveloper,
    title: (l10n) => l10n.developerOptions,
    stamp: null,
    arrowRaisesDrawer: true,
    needsDeveloperMode: true,
  ),
];

_Row _row(String rowId) => _rows.singleWhere((row) => row.rowId == rowId);

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
};

/// The kinds whose restored page raises the drawer when its arrow pops it.
const _reopenKinds = {
  NavDestinationKind.databaseSettings,
  NavDestinationKind.settings,
  NavDestinationKind.syncSettings,
  NavDestinationKind.counterManagement,
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
