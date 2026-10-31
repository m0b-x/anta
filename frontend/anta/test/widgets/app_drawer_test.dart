import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/bloc/app_settings/app_settings_bloc.dart';
import 'package:anta/constants/app_version.dart';
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/app_permission.dart';
import 'package:anta/models/dev_options.dart';
import 'package:anta/pages/settings_hub_page.dart';
import 'package:anta/pages/settings_page.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/drawer_host_registry.dart';
import 'package:anta/services/permission_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/app_drawer.dart';
import 'package:anta/widgets/leading_nav_pair.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import '../services/permission_support.dart';

/// The drawer of the settings rework (D1, D10 of
/// `docs/settings-rework-roadmap.md`): it lists places — nine rows by id,
/// the settings rows that moved to the hub absent — drawn plain on the
/// metrics, with the permissions attention line on the Settings row and an
/// About dialog that reads `kAppVersion`.
///
/// A plain host stands in for the folder page: a `Scaffold` with the drawer,
/// registered with [DrawerHostRegistry] the way the browser, the note lists
/// and the editor register. Every row's page and back are the navigation
/// contract's (`settings_navigation_contract_test.dart`), which also taps the
/// header icon's developer unlock over the file-backed database it needs.
void main() {
  late AppDatabase db;
  late SettingsService settings;
  late AppSettingsBloc appSettingsBloc;

  final l10n = AppLocalizationsEn();

  /// The nine rows of D1, top to bottom.
  const rowIds = [
    SemanticsIds.drawerCalendar,
    SemanticsIds.drawerCalendarOverview,
    SemanticsIds.drawerCalendarReport,
    SemanticsIds.drawerCalendarCategories,
    SemanticsIds.drawerAlerts,
    SemanticsIds.drawerCounters,
    SemanticsIds.drawerSettings,
    SemanticsIds.drawerHowTo,
    SemanticsIds.drawerAbout,
  ];

  /// The ids of the rows that left the drawer for the hub; their constants
  /// are retired, so a device flow spelling one finds nothing.
  const retiredIds = [
    'drawer-calendar-settings',
    'drawer-markdown-shortcuts',
    'drawer-sharing',
    'drawer-language',
    'drawer-developer-options',
    'drawer-permissions',
    'settings-databases',
    'settings-appearance',
  ];

  // Real Roboto, so a row's height is the one a phone lays out: under the
  // test font every subtitle wraps.
  setUpAll(loadGoldenFonts);

  setUp(() async {
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);
    appSettingsBloc = AppSettingsBloc();
    DrawerHostRegistry.clear();
    GetIt.I.registerSingleton<AuthService>(NoOpAuthService());
  });

  tearDown(() async {
    DevOptions.instance.lockDeveloperMode();
    DrawerHostRegistry.clear();
    await appSettingsBloc.close();
    await GetIt.I.reset();
    SettingsService.reset();
    DatabaseLifecycle.notifyDatabaseSwitching();
    await db.close();
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

  Future<void> pumpHost(WidgetTester tester) async {
    // Tall enough for the whole drawer list, so the row under test is built
    // rather than waiting below the fold.
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      BlocProvider<AppSettingsBloc>.value(
        value: appSettingsBloc,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const _DrawerHost(),
        ),
      ),
    );
    await settle(tester);
  }

  ScaffoldState hostState(WidgetTester tester) =>
      tester.state<ScaffoldState>(find.byType(Scaffold).first);

  Future<void> openDrawer(WidgetTester tester) async {
    hostState(tester).openDrawer();
    await settle(tester);
    expect(hostState(tester).isDrawerOpen, isTrue);
  }

  Finder inRow(String id, Finder matching) =>
      find.descendant(of: find.bySemanticsIdentifier(id), matching: matching);

  /// The style a [Text] paints with: the ambient default merged under its
  /// own, as the paragraph resolves it.
  TextStyle styleOf(WidgetTester tester, Finder text) {
    return DefaultTextStyle.of(
      tester.element(text),
    ).style.merge(tester.widget<Text>(text).style);
  }

  testWidgets('the Settings row opens the hub: back lands beneath with the '
      'drawer closed (D3)', (tester) async {
    await pumpHost(tester);
    await openDrawer(tester);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.drawerSettings));
    await settle(tester);

    expect(find.byType(SettingsHubPage), findsOneWidget);
    expect(hostState(tester).isDrawerOpen, isFalse);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.navBack));
    await settle(tester);

    expect(find.byType(SettingsHubPage), findsNothing);
    expect(find.text('host'), findsOneWidget);
    expect(hostState(tester).isDrawerOpen, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  // S25 is moot: the drag no longer reads the browser's swipe setting,
  // because there is no drawer to drag open, whatever the setting says.
  testWidgets('a settings page carries no drawer to drag open', (tester) async {
    await settings.setFolderSwipeEnabled(true);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const SettingsPage(),
      ),
    );
    await settle(tester);

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.drawer, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('automation identifiers', () {
    testWidgets('the nine places carry their ids, in order, and the rows '
        'that moved to the hub are gone (D1)', (tester) async {
      // Unlocked, so the Developer options row that used to appear with
      // the unlock is shown absent for the right reason.
      DevOptions.instance.developerModeUnlocked = true;
      await pumpHost(tester);
      await openDrawer(tester);

      var previousTop = double.negativeInfinity;
      for (final id in rowIds) {
        final row = find.bySemanticsIdentifier(id);
        expect(row, findsOneWidget, reason: '$id is missing from the drawer');
        final top = tester.getTopLeft(row).dy;
        expect(top, greaterThan(previousTop), reason: '$id is out of order');
        previousTop = top;
      }
      for (final id in retiredIds) {
        expect(
          find.bySemanticsIdentifier(id),
          findsNothing,
          reason: '$id left the drawer for the hub',
        );
      }
      // The list keeps its own id for a flow's scroll-to.
      expect(
        find.bySemanticsIdentifier(SemanticsIds.drawerList),
        findsOneWidget,
      );

      // The id rides next to the row's own text rather than replacing it:
      // a driver finds the control, a screen reader still reads the row.
      expect(
        inRow(SemanticsIds.drawerSettings, find.text(l10n.settingsHubTitle)),
        findsOneWidget,
      );
      expect(
        inRow(SemanticsIds.drawerHowTo, find.text(l10n.howToUseAnta)),
        findsOneWidget,
      );
      expect(
        inRow(SemanticsIds.drawerAbout, find.text(kAppVersion)),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the hub draws the arrow alone, by its id (D3)', (
      tester,
    ) async {
      await pumpHost(tester);
      await openDrawer(tester);
      await tester.tap(find.bySemanticsIdentifier(SemanticsIds.drawerSettings));
      await settle(tester);

      expect(find.bySemanticsIdentifier(SemanticsIds.navBack), findsOneWidget);
      expect(find.bySemanticsIdentifier(SemanticsIds.navMenu), findsNothing);
      expect(find.byType(LeadingNavPair), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('the plain rows (D10)', () {
    for (final brightness in Brightness.values) {
      testWidgets('glyph, title, subtitle and group label on the metrics '
          '(${brightness.name})', (tester) async {
        await tester.pumpWidget(const SizedBox.shrink());
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          BlocProvider<AppSettingsBloc>.value(
            value: appSettingsBloc,
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('en'),
              home: const _DrawerHost(),
            ),
          ),
        );
        await settle(tester);
        await openDrawer(tester);
        final scheme = Theme.of(
          tester.element(find.byType(AppDrawer)),
        ).colorScheme;

        for (final id in rowIds) {
          final glyph = tester.widget<Icon>(inRow(id, find.byType(Icon)).first);
          expect(glyph.size, RowMetrics.drawerGlyphSize, reason: id);
          expect(glyph.color, scheme.onSurfaceVariant, reason: id);
        }
        // No tinted chip behind a glyph.
        expect(
          find.descendant(
            of: find.byType(AppDrawer),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration! as BoxDecoration).color ==
                      scheme.primaryContainer.withValues(alpha: 0.5),
            ),
          ),
          findsNothing,
        );

        final title = styleOf(
          tester,
          inRow(SemanticsIds.drawerCounters, find.text(l10n.counterSettings)),
        );
        expect(title.fontSize, RowMetrics.titleFontSize);
        expect(title.fontWeight, FontWeight.w400);
        expect(title.color, scheme.onSurface);

        final subtitle = styleOf(
          tester,
          inRow(
            SemanticsIds.drawerCounters,
            find.text(l10n.settingsRowCountersDesc),
          ),
        );
        expect(subtitle.fontSize, RowMetrics.secondLineFontSize);
        expect(subtitle.fontWeight, FontWeight.w400);
        expect(subtitle.color, scheme.onSurfaceVariant);

        for (final label in [l10n.calendar, l10n.notes, l10n.appGroupLabel]) {
          final style = styleOf(tester, find.text(label.toUpperCase()));
          expect(style.fontSize, RowMetrics.sectionLabelFontSize);
          expect(style.fontWeight, RowMetrics.sectionLabelFontWeight);
          expect(style.letterSpacing, RowMetrics.sectionLabelLetterSpacing);
          expect(style.color, scheme.onSurfaceVariant);
        }

        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  });

  group('semantics', () {
    testWidgets('the three group labels are level-2 headings that read the '
        'label as written, not its capitals', (tester) async {
      await pumpHost(tester);
      await openDrawer(tester);

      for (final label in [l10n.calendar, l10n.notes, l10n.appGroupLabel]) {
        final heading = find.bySemanticsLabel(label);
        expect(heading, findsOneWidget, reason: label);
        final data = tester.getSemantics(heading).getSemanticsData();
        expect(data.flagsCollection.isHeader, isTrue, reason: label);
        expect(data.headingLevel, 2, reason: label);
        expect(
          find.bySemanticsLabel(label.toUpperCase()),
          findsNothing,
          reason: label,
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the header icon is a labelled button by its id, and every '
        'tappable in the drawer is labelled', (tester) async {
      await pumpHost(tester);
      await openDrawer(tester);

      final icon = find.bySemanticsIdentifier(SemanticsIds.drawerHeaderIcon);
      expect(icon, findsOneWidget);
      expect(
        tester.getSemantics(icon),
        isSemantics(label: l10n.appTitle, isButton: true, hasTapAction: true),
      );
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  // The Counters subtitle once wrapped to an 80 dp row; on one line every
  // two-line row is the same height. About still ends 7 dp past a 360 × 780
  // screen with no status bar (725–787 dp under a 109 dp header), so the
  // pin is the row that no longer wraps, not About above the fold.
  testWidgets('the Counters subtitle fits one line on a 360 × 780 screen at '
      '1.0 in English', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      BlocProvider<AppSettingsBloc>.value(
        value: appSettingsBloc,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const _DrawerHost(),
        ),
      ),
    );
    await settle(tester);
    await openDrawer(tester);

    double heightOf(String id) =>
        tester.getSize(find.bySemanticsIdentifier(id)).height;
    expect(
      heightOf(SemanticsIds.drawerCounters),
      heightOf(SemanticsIds.drawerCalendar),
    );
    expect(
      heightOf(SemanticsIds.drawerCounters),
      heightOf(SemanticsIds.drawerSettings),
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the Settings row reads the permissions attention line in the '
      'error colour while an essential permission is off, and its own '
      'subtitle once it is on', (tester) async {
    final gateway = FakePermissionGateway(
      statuses: {
        AppPermission.notifications: PermissionStatus.denied,
        AppPermission.fullScreenIntent: PermissionStatus.granted,
        AppPermission.batteryOptimization: PermissionStatus.denied,
      },
    );
    final permissions = permissionServiceOver(gateway);
    addTearDown(permissions.dispose);
    GetIt.I.registerSingleton<PermissionService>(permissions);
    await tester.runAsync(permissions.refresh);

    await pumpHost(tester);
    await openDrawer(tester);
    final scheme = Theme.of(tester.element(find.byType(AppDrawer))).colorScheme;

    final attention = inRow(
      SemanticsIds.drawerSettings,
      find.text(l10n.permissionsRowAttention(1)),
    );
    expect(attention, findsOneWidget);
    expect(styleOf(tester, attention).color, scheme.error);
    expect(
      inRow(SemanticsIds.drawerSettings, find.text(l10n.settingsHubRowDesc)),
      findsNothing,
    );

    gateway.current[AppPermission.notifications] = PermissionStatus.granted;
    await tester.runAsync(permissions.refresh);
    await settle(tester, rounds: 2);

    final description = inRow(
      SemanticsIds.drawerSettings,
      find.text(l10n.settingsHubRowDesc),
    );
    expect(description, findsOneWidget);
    expect(styleOf(tester, description).color, scheme.onSurfaceVariant);
    expect(attention, findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('About closes the drawer, shows the app with kAppVersion, and '
      'Close leaves the host as it was (S16)', (tester) async {
    await pumpHost(tester);
    await openDrawer(tester);

    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.drawerAbout));
    await settle(tester);

    expect(hostState(tester).isDrawerOpen, isFalse);
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    final title = find.bySemanticsIdentifier(SemanticsIds.aboutDialog);
    expect(title, findsOneWidget);
    expect(tester.getSemantics(title), isSemantics(isHeader: true));
    // Named About, never Flutter's generic "Alert".
    expect(
      tester.getSemantics(find.bySemanticsLabel(l10n.about)),
      isSemantics(label: l10n.about, scopesRoute: true, namesRoute: true),
    );
    expect(
      find.bySemanticsLabel(
        const DefaultMaterialLocalizations().alertDialogLabel,
      ),
      findsNothing,
    );
    for (final text in [
      l10n.appTitle,
      kAppVersion,
      l10n.aboutDescription,
      const DefaultMaterialLocalizations().viewLicensesButtonLabel,
    ]) {
      expect(
        find.descendant(of: dialog, matching: find.text(text)),
        findsOneWidget,
        reason: text,
      );
    }
    // The app's own mark (D10), 48 dp and silent to a screen reader.
    final mark = find.descendant(
      of: dialog,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == kAppIconAsset,
      ),
    );
    expect(mark, findsOneWidget);
    expect(tester.getSize(mark), const Size.square(48));
    expect(
      find.ancestor(of: mark, matching: find.byType(ExcludeSemantics)),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: dialog,
        matching: find.byIcon(Icons.fitness_center_rounded),
      ),
      findsNothing,
    );

    await tester.tap(
      find.descendant(of: dialog, matching: find.text(l10n.close)),
    );
    await settle(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('host'), findsOneWidget);
    expect(hostState(tester).isDrawerOpen, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

/// Stands in for the folder page: a scaffold that hosts the drawer and
/// registers itself the way every full-page screen does.
class _DrawerHost extends StatefulWidget {
  const _DrawerHost();

  @override
  State<_DrawerHost> createState() => _DrawerHostState();
}

class _DrawerHostState extends State<_DrawerHost> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    DrawerHostRegistry.register(_scaffoldKey);
  }

  @override
  void dispose() {
    DrawerHostRegistry.unregister(_scaffoldKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: const AppDrawer(),
      body: const Center(child: Text('host')),
    );
  }
}
