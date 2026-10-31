import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/bloc/app_settings/app_settings_bloc.dart';
import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/app_permission.dart';
import 'package:anta/models/custom_markdown_shortcut.dart';
import 'package:anta/models/dev_options.dart';
import 'package:anta/models/nav_destination.dart';
import 'package:anta/pages/markdown_settings_page.dart';
import 'package:anta/pages/settings_hub_page.dart';
import 'package:anta/services/app_navigator.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/navigation_history_service.dart';
import 'package:anta/services/permission_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/settings_section_list.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import '../goldens/support/golden_matrix.dart';
import '../services/permission_support.dart';
import 'support/layout_errors.dart';

/// The settings hub (`docs/settings-rework-roadmap.md` §4.2): a row per
/// settings page, in four sections, each opening its page — asserted
/// through the route it pushes and the stamp on it, never by building the
/// page — searchable by the pages' section titles, with the Language and
/// Theme dialogs, the Permissions attention line and the developer gate.
void main() {
  final l10n = AppLocalizationsEn();

  const shortcuts = [
    CustomMarkdownShortcut(
      id: 'bold',
      label: 'Bold',
      iconCodePoint: 0xe238,
      iconFontFamily: 'MaterialIcons',
      beforeText: '**',
      afterText: '**',
    ),
  ];

  late AppDatabase db;
  late SettingsService settings;
  late MarkdownBarBloc markdownBloc;
  late _RecordingSettingsBloc appSettingsBloc;
  late NavigationHistoryService history;
  late _RecordingObserver observer;

  setUpAll(loadGoldenFonts);

  setUp(() async {
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);
    markdownBloc = MarkdownBarBloc(
      barService: await MarkdownBarService.forTesting(db),
    );
    // The hub reads the shortcuts off a loaded bar at the tap.
    // ignore: invalid_use_of_visible_for_testing_member
    markdownBloc.emit(
      const MarkdownBarLoaded(
        profiles: [],
        activeProfileId: 'default',
        currentShortcuts: shortcuts,
      ),
    );
    appSettingsBloc = _RecordingSettingsBloc();
    history = NavigationHistoryService(
      writeDebounce: const Duration(milliseconds: 10),
    );
    GetIt.I.registerSingleton<NavigationHistoryService>(history);
    observer = _RecordingObserver();
  });

  tearDown(() async {
    DevOptions.instance.lockDeveloperMode();
    await markdownBloc.close();
    await appSettingsBloc.close();
    history.dispose();
    await GetIt.I.reset();
    SettingsService.reset();
    DatabaseLifecycle.notifyDatabaseSwitching();
    await db.close();
  });

  Widget app({Widget home = const SettingsHubPage(), GoldenCell? cell}) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AppSettingsBloc>.value(value: appSettingsBloc),
        BlocProvider<MarkdownBarBloc>.value(value: markdownBloc),
      ],
      child: MaterialApp(
        navigatorKey: AppNavigator.navigatorKey,
        navigatorObservers: [AppNavigator.routeObserver, observer],
        theme: cell?.theme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: cell?.locale ?? const Locale('en'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(cell?.textScale ?? 1.0)),
          child: child!,
        ),
        home: home,
      ),
    );
  }

  /// Tall enough that every row of every section is built.
  Future<void> pumpHub(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pump();
  }

  /// Tears the app down before a frame builds the page a row pushed: the
  /// suite asserts which route lands and how it is stamped, not what the
  /// page paints.
  Future<void> teardownApp(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  /// The Theme row carries the id it had in the drawer (D11); every other
  /// row its kind's.
  Finder row(String kind) => find.bySemanticsIdentifier(
    kind == 'theme'
        ? SemanticsIds.settingsAppearance
        : SemanticsIds.settingsHubRow(kind),
  );

  Finder section(String title) => find.ancestor(
    of: find.text(title.toUpperCase()),
    matching: find.byType(SettingsSectionCard),
  );

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.settingsHubSearch),
        matching: find.byType(TextField),
      ),
      query,
    );
    await tester.pump();
  }

  const calendarRows = [
    'calendarSettings',
    'calendarAppearance',
    'calendarCategories',
  ];
  const notesRows = ['markdownSettings', 'counterManagement'];
  const appRows = [
    'settings',
    'language',
    'theme',
    'databaseSettings',
    'syncSettings',
    'permissions',
    'developerOptions',
  ];
  const howToRows = ['calendarGuide'];
  const allRows = [...calendarRows, ...notesRows, ...appRows, ...howToRows];

  testWidgets('every row sits in its section, by id', (tester) async {
    DevOptions.instance.developerModeUnlocked = true;
    await pumpHub(tester);

    expect(
      find.bySemanticsIdentifier(SemanticsIds.settingsBarHub),
      findsOneWidget,
    );
    for (final (title, kinds) in [
      (l10n.settingsSectionCalendar, calendarRows),
      (l10n.settingsSectionNotes, notesRows),
      (l10n.settingsSectionApp, appRows),
      (l10n.settingsSectionHowTo, howToRows),
    ]) {
      for (final kind in kinds) {
        expect(
          find.descendant(of: section(title), matching: row(kind)),
          findsOneWidget,
          reason: '$kind under $title',
        );
      }
    }
    expect(
      find.bySemanticsIdentifier(SemanticsIds.settingsHubRow('theme')),
      findsNothing,
    );
    // The list a device flow swipes inside to reach a lower row.
    expect(
      find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.settingsHubList),
        matching: row('developerOptions'),
      ),
      findsOneWidget,
    );

    await teardownApp(tester);
  });

  group('each page row pushes its page', () {
    for (final (kind, stamp) in const [
      ('calendarSettings', NavDestinationKind.calendarSettings),
      ('calendarAppearance', NavDestinationKind.calendarAppearance),
      ('calendarCategories', NavDestinationKind.calendarCategories),
      ('counterManagement', NavDestinationKind.counterManagement),
      ('settings', NavDestinationKind.settings),
      ('databaseSettings', NavDestinationKind.databaseSettings),
      ('syncSettings', NavDestinationKind.syncSettings),
      ('permissions', NavDestinationKind.permissions),
      ('calendarGuide', NavDestinationKind.calendarGuide),
    ]) {
      testWidgets('$kind is stamped ${stamp.name}', (tester) async {
        await pumpHub(tester);
        observer.clear();

        await tester.tap(row(kind));

        final destination = observer.pushed.single.settings.arguments;
        expect(destination, isA<NavDestination>());
        expect((destination as NavDestination).kind, stamp);

        await teardownApp(tester);
      });
    }

    // The page is read off the route without building it, for the
    // shortcuts the row hands it.
    testWidgets('markdownSettings is stamped markdownSettings and opens the '
        'editor page with the bar\'s shortcuts', (tester) async {
      await pumpHub(tester);
      observer.clear();

      await tester.tap(row('markdownSettings'));

      final pushed = observer.pushed.single;
      expect(
        pushed.settings.arguments,
        const NavDestination(NavDestinationKind.markdownSettings),
      );
      final page = pageOf(tester, pushed);
      expect(page, isA<MarkdownSettingsPage>());
      expect((page as MarkdownSettingsPage).allShortcuts, same(shortcuts));

      await teardownApp(tester);
    });

    testWidgets('markdownSettings opens while the bar is still loading, and '
        'the page fills once the bar loads', (tester) async {
      const squat = CustomMarkdownShortcut(
        id: 'custom_squat',
        label: 'Squat',
        iconCodePoint: 0xe238,
        iconFontFamily: 'MaterialIcons',
        beforeText: 'Squat ',
        afterText: '',
      );
      // ignore: invalid_use_of_visible_for_testing_member
      markdownBloc.emit(const MarkdownBarLoading());
      // Tall, so the shortcut list beneath the page's other sections is built.
      tester.view.physicalSize = const Size(1000, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app());
      await tester.pump();
      observer.clear();

      await tester.tap(row('markdownSettings'));
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(
        observer.pushed.single.settings.arguments,
        const NavDestination(NavDestinationKind.markdownSettings),
      );
      expect(find.byType(MarkdownSettingsPage), findsOneWidget);
      Finder shortcutRow() =>
          find.descendant(of: find.byType(Card), matching: find.text('Squat'));
      expect(shortcutRow(), findsNothing);

      // ignore: invalid_use_of_visible_for_testing_member
      markdownBloc.emit(
        const MarkdownBarLoaded(
          profiles: [],
          activeProfileId: 'default',
          currentShortcuts: [squat],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      expect(shortcutRow(), findsOneWidget);

      await teardownApp(tester);
    });

    testWidgets('developerOptions is stamped developerOptions', (tester) async {
      DevOptions.instance.developerModeUnlocked = true;
      await pumpHub(tester);
      observer.clear();

      await tester.tap(row('developerOptions'));

      expect(
        observer.pushed.single.settings.arguments,
        const NavDestination(NavDestinationKind.developerOptions),
      );

      await teardownApp(tester);
    });
  });

  group('the search', () {
    testWidgets('"holiday" finds Calendar settings only', (tester) async {
      DevOptions.instance.developerModeUnlocked = true;
      await pumpHub(tester);

      await search(tester, 'holiday');

      for (final kind in allRows) {
        expect(
          row(kind),
          kind == 'calendarSettings' ? findsOneWidget : findsNothing,
          reason: kind,
        );
      }

      await teardownApp(tester);
    });

    testWidgets('"auto" finds General, by its subtitle', (tester) async {
      await pumpHub(tester);

      await search(tester, 'auto');

      expect(row('settings'), findsOneWidget);
      expect(row('calendarSettings'), findsNothing);
      expect(row('permissions'), findsNothing);

      await teardownApp(tester);
    });

    testWidgets('a page\'s section title finds the row that opens it', (
      tester,
    ) async {
      await pumpHub(tester);

      await search(tester, l10n.pairingSection);

      expect(row('syncSettings'), findsOneWidget);
      expect(row('settings'), findsNothing);

      await teardownApp(tester);
    });

    testWidgets('"theme" finds the Theme row, titled apart from the '
        'calendar\'s Appearance', (tester) async {
      await pumpHub(tester);

      expect(
        find.descendant(
          of: row('theme'),
          matching: find.text(l10n.settingsRowTheme),
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.calendarAppearanceSection), findsOneWidget);

      await search(tester, 'theme');

      expect(row('theme'), findsOneWidget);
      expect(row('calendarAppearance'), findsNothing);
      expect(row('settings'), findsNothing);

      await teardownApp(tester);
    });

    testWidgets('a query with no hit shows the caption and keeps the field', (
      tester,
    ) async {
      await pumpHub(tester);

      await search(tester, 'qqqzzz');

      expect(find.text(l10n.noMatchesFound), findsOneWidget);
      for (final kind in allRows) {
        expect(row(kind), findsNothing, reason: kind);
      }
      final field = find.descendant(
        of: find.bySemanticsIdentifier(SemanticsIds.settingsHubSearch),
        matching: find.byType(TextField),
      );
      expect(field, findsOneWidget);
      expect(tester.widget<TextField>(field).controller!.text, 'qqqzzz');

      await teardownApp(tester);
    });
  });

  group('the dialog rows', () {
    testWidgets('Language opens its dialog, and Close sends nothing', (
      tester,
    ) async {
      await pumpHub(tester);

      final dialog = find.bySemanticsIdentifier(SemanticsIds.languageDialog);
      await tester.tap(row('language'));
      await tester.pumpAndSettle();
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text(l10n.selectLanguage)),
        findsOneWidget,
      );

      await tester.tap(find.text(l10n.close));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(appSettingsBloc.events, isEmpty);

      await teardownApp(tester);
    });

    testWidgets('Theme opens its dialog, and Close sends nothing', (
      tester,
    ) async {
      await pumpHub(tester);

      final dialog = find.bySemanticsIdentifier(SemanticsIds.themeDialog);
      await tester.tap(row('theme'));
      await tester.pumpAndSettle();
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text(l10n.selectTheme)),
        findsOneWidget,
      );

      await tester.tap(find.text(l10n.close));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(appSettingsBloc.events, isEmpty);

      await teardownApp(tester);
    });

    testWidgets('the Theme row reads the current theme, and the one picked '
        'once the dialog closes', (tester) async {
      await pumpHub(tester);
      expect(
        find.descendant(
          of: row('theme'),
          matching: find.text(l10n.systemTheme),
        ),
        findsOneWidget,
      );

      await tester.tap(row('theme'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.darkTheme));
      await tester.pumpAndSettle();

      expect(appSettingsBloc.events, [const ChangeThemeMode(ThemeMode.dark)]);
      expect(
        find.descendant(of: row('theme'), matching: find.text(l10n.darkTheme)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row('theme'),
          matching: find.text(l10n.systemTheme),
        ),
        findsNothing,
      );

      await teardownApp(tester);
    });

    testWidgets('the Language row reads the current language, and the one '
        'picked once the dialog closes', (tester) async {
      await pumpHub(tester);
      expect(
        find.descendant(
          of: row('language'),
          matching: find.text(l10n.systemDefault),
        ),
        findsOneWidget,
      );

      await tester.tap(row('language'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.german));
      await tester.pumpAndSettle();

      expect(appSettingsBloc.events, [const ChangeLocale('de')]);
      expect(
        find.descendant(of: row('language'), matching: find.text(l10n.german)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row('language'),
          matching: find.text(l10n.systemDefault),
        ),
        findsNothing,
      );

      await teardownApp(tester);
    });
  });

  testWidgets('the Permissions subtitle turns into the attention line, in '
      'error, while an essential permission is off', (tester) async {
    final gateway = FakePermissionGateway(
      statuses: {
        ...allGranted,
        AppPermission.notifications: PermissionStatus.denied,
      },
    );
    final service = permissionServiceOver(gateway);
    GetIt.I.registerSingleton<PermissionService>(service);
    await tester.runAsync(service.refresh);
    await pumpHub(tester);

    final attention = l10n.permissionsRowAttention(1);
    final line = find.byWidgetPredicate(
      (widget) => widget is HighlightedText && widget.text == attention,
    );
    expect(find.descendant(of: row('permissions'), matching: line), findsOne);
    final colorScheme = Theme.of(tester.element(line)).colorScheme;
    expect(
      tester.widget<HighlightedText>(line).style?.color,
      colorScheme.error,
    );
    expect(find.text(l10n.permissionsRowDesc), findsNothing);

    // Granted while the hub is open: the plain subtitle comes back.
    gateway.current[AppPermission.notifications] = PermissionStatus.granted;
    await tester.runAsync(service.refresh);
    await tester.pump();

    expect(
      find.descendant(
        of: row('permissions'),
        matching: find.text(l10n.permissionsRowDesc),
      ),
      findsOneWidget,
    );
    expect(find.text(attention), findsNothing);

    await teardownApp(tester);
  });

  testWidgets('Developer options is drawn only while unlocked', (tester) async {
    await pumpHub(tester);
    expect(row('developerOptions'), findsNothing);

    DevOptions.instance.developerModeUnlocked = true;
    await tester.pump();
    expect(row('developerOptions'), findsOneWidget);

    DevOptions.instance.lockDeveloperMode();
    await tester.pump();
    expect(row('developerOptions'), findsNothing);

    await teardownApp(tester);
  });

  group('navigation', () {
    testWidgets('toSettingsHub stamps the hub, and over the hub pushes '
        'nothing', (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(home: const Scaffold(body: Text('root'))));
      observer.clear();

      AppNavigator.toSettingsHub(tester.element(find.text('root')));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsHubPage), findsOneWidget);
      expect(
        observer.pushed.single.settings.arguments,
        const NavDestination(NavDestinationKind.settingsHub),
      );

      observer.clear();
      await AppNavigator.toSettingsHub(
        tester.element(find.byType(SettingsHubPage)),
      );
      await tester.pumpAndSettle();

      expect(observer.pushed, isEmpty);
      expect(find.byType(SettingsHubPage), findsOneWidget);

      await teardownApp(tester);
    });

    testWidgets('a restored [settingsHub] rebuilds the hub', (tester) async {
      await settings.saveLastLocationStack(const [
        NavDestination(NavDestinationKind.settingsHub),
      ]);
      await tester.pumpWidget(app(home: const Scaffold(body: Text('root'))));
      observer.clear();

      await tester.runAsync(AppNavigator.restoreLastLocation);

      final route = observer.pushed.single;
      expect(
        route.settings.arguments,
        const NavDestination(NavDestinationKind.settingsHub),
      );
      expect(pageOf(tester, route), isA<SettingsHubPage>());

      await teardownApp(tester);
    });
  });

  group('large text', () {
    const cells = [
      GoldenCell(
        dark: true,
        locale: Locale('de'),
        textScale: 2.0,
        size: Size(360, 780),
      ),
      GoldenCell(
        dark: false,
        locale: Locale('ro'),
        textScale: 2.0,
        size: Size(360, 780),
      ),
    ];

    for (final cell in cells) {
      testWidgets('${cell.label}: no overflow and no clipped row text, top '
          'to bottom', (tester) async {
        DevOptions.instance.developerModeUnlocked = true;
        final gateway = FakePermissionGateway(
          statuses: {
            for (final permission in AppPermission.values)
              permission: PermissionStatus.denied,
          },
        );
        final service = permissionServiceOver(gateway);
        GetIt.I.registerSingleton<PermissionService>(service);
        await tester.runAsync(service.refresh);
        setGoldenSurface(tester, cell);

        final errors = await layoutErrorsDuring(() async {
          await tester.pumpWidget(app(cell: cell));
          await tester.pump();

          final list = find
              .descendant(
                of: find.byType(SettingsSectionList),
                matching: find.byType(Scrollable),
              )
              .first;
          final position = tester.state<ScrollableState>(list).position;
          while (true) {
            final paragraphs = find.descendant(
              of: find.byType(SettingsSectionList),
              matching: find.byType(RichText),
            );
            for (final element in paragraphs.evaluate()) {
              final paragraph = element.renderObject! as RenderParagraph;
              expect(
                paragraph.didExceedMaxLines,
                isFalse,
                reason: paragraph.text.toPlainText(),
              );
            }
            if (position.pixels >= position.maxScrollExtent) break;
            position.jumpTo(
              (position.pixels + position.viewportDimension / 2).clamp(
                0.0,
                position.maxScrollExtent,
              ),
            );
            await tester.pump();
          }
        });

        expect(errors, isEmpty);
        await teardownApp(tester);
      });
    }
  });
}

/// The page a pushed route would build, read off the route without a frame.
Widget pageOf(WidgetTester tester, Route<dynamic> route) {
  final context = AppNavigator.navigatorKey.currentContext!;
  if (route is PageRouteBuilder) {
    return route.pageBuilder(
      context,
      const AlwaysStoppedAnimation<double>(1),
      const AlwaysStoppedAnimation<double>(0),
    );
  }
  return (route as MaterialPageRoute<dynamic>).builder(context);
}

class _RecordingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  void clear() => pushed.clear();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

/// Keeps every event a dialog sends instead of writing it through the app's
/// database, and answers a theme change the way the real bloc does once its
/// write lands — so the row can be shown to follow it.
class _RecordingSettingsBloc extends AppSettingsBloc {
  final List<AppSettingsEvent> events = [];

  @override
  void add(AppSettingsEvent event) {
    events.add(event);
    if (event is ChangeThemeMode) {
      emit(state.copyWith(themeMode: event.themeMode, isLoading: false));
    }
    if (event is ChangeLocale) {
      emit(
        state.copyWith(
          localeCode: event.localeCode,
          clearLocale: event.localeCode == null,
          isLoading: false,
        ),
      );
    }
  }
}
