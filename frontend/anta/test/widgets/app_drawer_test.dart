import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/bloc/app_settings/app_settings_bloc.dart';
import 'package:anta/bloc/sync/sync_bloc.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/app_version.dart';
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/app_permission.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/models/dev_options.dart';
import 'package:anta/models/sync_binding.dart';
import 'package:anta/pages/settings_hub_page.dart';
import 'package:anta/pages/settings_page.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/permission_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/services/sync/sync_status.dart';
import 'package:anta/widgets/app_drawer.dart';
import 'package:anta/widgets/leading_nav_pair.dart';
import 'package:anta/widgets/user_avatar.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import '../services/pairing_support.dart';
import '../services/permission_support.dart';
import '../support/fake_sync_engine.dart';

/// The drawer of the settings rework (D1, D10 of
/// `docs/settings-rework-roadmap.md`): it lists places — nine rows by id,
/// the settings rows that moved to the hub absent — drawn plain on the
/// metrics, with the permissions attention line on the Settings row and an
/// About dialog that reads `kAppVersion`.
///
/// A plain host stands in for the folder page: a `Scaffold` with the drawer,
/// as the browser, the note lists and the editor carry it. Every row's page
/// and back are the navigation contract's
/// (`settings_navigation_contract_test.dart`), which also taps the header
/// icon's developer unlock over the file-backed database it needs.
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
    GetIt.I.registerSingleton<AuthService>(NoOpAuthService());
  });

  tearDown(() async {
    DevOptions.instance.lockDeveloperMode();
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

  /// The drawer list's scrolling node, the one that carries the child count
  /// and the first visible index a screen reader announces.
  SemanticsData scrollNodeOf(WidgetTester tester) {
    SemanticsNode? found;
    bool visit(SemanticsNode node) {
      if (node.getSemanticsData().scrollChildCount != null) found = node;
      if (found == null) node.visitChildren(visit);
      return found == null;
    }

    visit(
      tester.getSemantics(find.bySemanticsIdentifier(SemanticsIds.drawerList)),
    );
    return found!.getSemanticsData();
  }

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

  // §12 of `docs/cloud-sync-phase-02-own-space.md`: the header's badge became
  // the list's first row while signed in. Where it lands is the navigation
  // contract's (`settings_navigation_contract_test.dart`).
  testWidgets('signed out there is no account row and no avatar, and the '
      'Calendar row sits where it always has', (tester) async {
    await pumpHost(tester);
    await openDrawer(tester);

    expect(
      find.bySemanticsIdentifier(SemanticsIds.drawerAccount),
      findsNothing,
    );
    expect(find.byType(UserAvatar), findsNothing);
    expect(
      tester.getRect(find.bySemanticsIdentifier(SemanticsIds.drawerCalendar)),
      const Rect.fromLTWH(0, 149, 304, 62),
    );
    // The list's children are the three labels and the nine places alone,
    // so a screen reader's "x of n" is what it always was.
    final list = scrollNodeOf(tester);
    expect(list.scrollChildCount, 12);
    expect(list.scrollIndex, 0);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('the account row, signed in (§12)', () {
    late FakeAuthService auth;
    late FakeSyncEngine engine;
    late _StatusReader reader;

    const binding = SyncBinding(
      spaceId: 'space-1',
      ownerUid: 'uid-a',
      accountUid: 'uid-a',
    );
    final pulled = DateTime.now().toUtc();

    const notSyncing = SyncStatus();
    final lastSynced = SyncStatus(binding: binding, lastPullAt: pulled);
    final pending = lastSynced.copyWith(pendingCount: 3);
    final mismatch = lastSynced.copyWith(pause: SyncPause.accountMismatch);

    /// How many blocs the drawer asked DI for.
    var blocsCreated = 0;

    setUp(() {
      auth = FakeAuthService(user: userA);
      engine = FakeSyncEngine();
      reader = _StatusReader()..status = lastSynced;
      blocsCreated = 0;
      GetIt.I.unregister<AuthService>();
      GetIt.I.registerSingleton<AuthService>(auth);
      GetIt.I.registerFactory<SyncBloc>(() {
        blocsCreated++;
        return SyncBloc(
          authService: auth,
          statusReader: () => reader,
          engine: () async => engine,
        );
      });
    });

    tearDown(() async {
      await engine.statuses.close();
      await auth.dispose();
    });

    Finder account() => find.bySemanticsIdentifier(SemanticsIds.drawerAccount);
    Finder calendar() =>
        find.bySemanticsIdentifier(SemanticsIds.drawerCalendar);

    for (final scale in const [1.0, 1.3, 2.0]) {
      testWidgets('at $scale the row is the Calendar row\'s height before '
          'its first status and in every state, and a status landing with '
          'the drawer open moves nothing', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final readGate = reader.gate = Completer<void>();
        await pumpHost(tester);

        // The first frame is built before the bloc has said anything.
        hostState(tester).openDrawer();
        await tester.pump();
        final firstFrame = tester.getSize(account()).height;
        await settle(tester);
        final bloc = BlocProvider.of<SyncBloc>(
          tester.element(
            inRow(SemanticsIds.drawerAccount, find.text(userA.displayName!)),
          ),
        );
        Finder lastSyncedLine() => inRow(
          SemanticsIds.drawerAccount,
          find.textContaining(l10n.syncLastSynced('')),
        );

        // A bound status not yet read is never said: the account's
        // placeholder would read "Not syncing" for a database that syncs.
        // ignore: invalid_use_of_visible_for_testing_member
        bloc.emit(SyncSignedIn(userA, status: lastSynced));
        await settle(tester, rounds: 2);
        expect(lastSyncedLine(), findsNothing);
        expect(
          inRow(
            SemanticsIds.drawerAccount,
            find.text(l10n.drawerAccountNotSyncing),
          ),
          findsNothing,
        );
        final blank = tester.getRect(account());

        // ignore: invalid_use_of_visible_for_testing_member
        bloc.emit(SyncSignedIn(userA, status: lastSynced, statusRead: true));
        await settle(tester, rounds: 2);
        expect(lastSyncedLine(), findsOneWidget);

        final rect = tester.getRect(account());
        expect(rect, blank);
        expect(rect.height, tester.getSize(calendar()).height);
        expect(firstFrame, rect.height);
        expect(rect.bottom, lessThan(tester.getTopLeft(calendar()).dy));
        expect(
          tester.getSize(
            inRow(SemanticsIds.drawerAccount, find.byType(UserAvatar)),
          ),
          const Size.square(RowMetrics.drawerGlyphSize),
        );
        final scheme = Theme.of(
          tester.element(find.byType(AppDrawer)),
        ).colorScheme;

        final states = [
          (lastSynced, l10n.syncLastSynced(''), false),
          (notSyncing, l10n.drawerAccountNotSyncing, false),
          (pending, l10n.syncPendingCount(3), false),
          (mismatch, l10n.drawerSyncPausedOtherAccount, true),
        ];
        for (final (status, words, isError) in states) {
          if (status != lastSynced) {
            engine.emit(status);
            await settle(tester, rounds: 2);
          }
          final line = inRow(
            SemanticsIds.drawerAccount,
            find.textContaining(words),
          );
          expect(line, findsOneWidget, reason: words);
          expect(
            styleOf(tester, line).color,
            isError ? scheme.error : scheme.onSurfaceVariant,
            reason: words,
          );
          expect(tester.getRect(account()), rect, reason: words);
        }

        // The row's bloc only read: it never started, ran or stopped sync.
        expect(engine.calls, isEmpty);

        readGate.complete();
        await settle(tester, rounds: 2);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('the account is the drawer\'s one avatar, the row reads the '
        'name then the status as a button, and every tappable is a labelled '
        '48 dp target', (tester) async {
      await pumpHost(tester);
      await openDrawer(tester);

      expect(find.byType(UserAvatar), findsOneWidget);
      expect(
        inRow(SemanticsIds.drawerAccount, find.byType(UserAvatar)),
        findsOneWidget,
      );
      final node = tester.getSemantics(account()).getSemanticsData();
      expect(node.label, startsWith(userA.displayName!));
      expect(node.label, contains(l10n.syncLastSynced('')));
      expect(node.flagsCollection.isButton, isTrue);
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the title falls back from the name to the email to the '
        'section\'s name, and the row leaves with the account', (tester) async {
      await pumpHost(tester);
      await openDrawer(tester);
      final height = tester.getSize(account()).height;

      expect(
        inRow(SemanticsIds.drawerAccount, find.text(userA.displayName!)),
        findsOneWidget,
      );

      auth.emitAuth(const AppUser(uid: 'uid-a', email: 'a@b.c'));
      await settle(tester, rounds: 2);
      expect(
        inRow(SemanticsIds.drawerAccount, find.text('a@b.c')),
        findsOneWidget,
      );
      expect(tester.getSize(account()).height, height);

      auth.emitAuth(const AppUser(uid: 'uid-a'));
      await settle(tester, rounds: 2);
      expect(
        inRow(SemanticsIds.drawerAccount, find.text(l10n.accountSection)),
        findsOneWidget,
      );

      auth.emitAuth(null);
      await settle(tester, rounds: 2);
      expect(account(), findsNothing);
      expect(find.byType(UserAvatar), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('with no sync bloc to read, the line stays blank in its '
        'reserved slot', (tester) async {
      GetIt.I.unregister<SyncBloc>();
      await pumpHost(tester);
      await openDrawer(tester);

      expect(
        tester.getSize(account()).height,
        tester.getSize(calendar()).height,
      );
      expect(
        inRow(SemanticsIds.drawerAccount, find.byType(Text)),
        findsNWidgets(2),
        reason: 'the title and the slot\'s unseen template only',
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('at 2.0 on a 360 × 780 phone a drag to About and back keeps '
        'the row\'s one bloc, and its line stays drawn', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpHost(tester);
      tester.view.physicalSize = const Size(360, 780);
      await tester.pump();
      await openDrawer(tester);
      Finder line() => inRow(
        SemanticsIds.drawerAccount,
        find.textContaining(l10n.syncLastSynced('')),
      );
      expect(line(), findsOneWidget);
      expect(blocsCreated, 1);

      final list = find.descendant(
        of: find.byType(AppDrawer),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.bySemanticsIdentifier(SemanticsIds.drawerAbout),
        300,
        scrollable: list,
      );
      await settle(tester, rounds: 2);
      expect(account(), findsNothing, reason: 'the row left the cache');

      await tester.drag(list, const Offset(0, 4000));
      await settle(tester, rounds: 4);
      expect(account(), findsOneWidget);
      expect(line(), findsOneWidget);
      expect(blocsCreated, 1);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    // The boundary pass of the design review: both themes, the two longest
    // locales, the scales either side of each threshold and Android's own
    // steps, every state. A cut the owner accepted is listed; any other is
    // a finding.
    final now = DateTime.now();
    SyncFailureInfo failed(SyncGatewayFailure failure) =>
        SyncFailureInfo(failure, at: pulled);
    final everyState = <String, SyncStatus>{
      'notSyncing': notSyncing,
      'pausedQuota': lastSynced.copyWith(pause: SyncPause.quotaExhausted),
      'pausedSignedOut': lastSynced.copyWith(pause: SyncPause.signedOut),
      'pausedOtherAccount': mismatch,
      'pausedAppOutdated': lastSynced.copyWith(pause: SyncPause.appOutdated),
      'pausedNoAccess': lastSynced.copyWith(pause: SyncPause.noAccess),
      'pausedSpaceDeleted': lastSynced.copyWith(pause: SyncPause.spaceDeleted),
      'sending': lastSynced.copyWith(
        activity: SyncActivity.pushing,
        pendingCount: 1234,
      ),
      'receiving': lastSynced.copyWith(activity: SyncActivity.pulling),
      'offline': lastSynced.copyWith(
        lastFailure: failed(SyncGatewayFailure.offline),
      ),
      'retrying': lastSynced.copyWith(
        lastFailure: failed(SyncGatewayFailure.permissionDenied),
      ),
      'pending': lastSynced.copyWith(pendingCount: 1234),
      'neverSynced': const SyncStatus(binding: binding),
      'lastSyncedToday': lastSynced,
      'lastSyncedPreviousYear': SyncStatus(
        binding: binding,
        lastPullAt: DateTime(now.year - 1, 11, 5, 15, 9).toUtc(),
      ),
    };
    // The date is `formatSyncMoment`'s, shared with the page and the picker.
    final acceptedCuts = {
      ('de', 1.0): {'lastSyncedPreviousYear'},
    };

    for (final (themeName, theme) in [
      ('light', AppTheme.light()),
      ('dark', AppTheme.dark()),
    ]) {
      for (final code in const ['de', 'ro']) {
        for (final scale in const [1.0, 1.15, 1.3, 1.5, 1.77, 2.0]) {
          testWidgets('$themeName $code at $scale: every state keeps the '
              'row\'s rect, and only an accepted line is cut', (tester) async {
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            tester.view.physicalSize = const Size(1000, 2400);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(
              BlocProvider<AppSettingsBloc>.value(
                value: appSettingsBloc,
                child: MaterialApp(
                  theme: theme,
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  locale: Locale(code),
                  home: const _DrawerHost(),
                ),
              ),
            );
            await settle(tester);
            await openDrawer(tester);
            final local = AppLocalizations.of(
              tester.element(find.byType(AppDrawer)),
            )!;
            final status = find.descendant(
              of: account(),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Text &&
                    widget.data != userA.displayName &&
                    (widget.data?.trim().isNotEmpty ?? false),
              ),
            );

            Rect? rect;
            final cuts = <String>{};
            for (final MapEntry(key: name, value: state)
                in everyState.entries) {
              engine.emit(state);
              await settle(tester, rounds: 2);
              expect(status, findsOneWidget, reason: name);
              if (tester
                  .renderObject<RenderParagraph>(status)
                  .didExceedMaxLines) {
                cuts.add('$name "${tester.widget<Text>(status).data}"');
              }
              rect ??= tester.getRect(account());
              expect(tester.getRect(account()), rect, reason: name);
            }
            final accepted = acceptedCuts[(code, scale)] ?? const <String>{};
            expect(
              cuts.where(
                (cut) => !accepted.contains(cut.substring(0, cut.indexOf(' '))),
              ),
              isEmpty,
            );

            // The header's subtitle is the one it always was.
            expect(
              find.descendant(
                of: find.byType(AppDrawer),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Text &&
                      widget.data == local.settings &&
                      widget.maxLines == 1 &&
                      widget.style?.fontSize == 14,
                ),
              ),
              findsOneWidget,
            );

            await tester.pumpWidget(const SizedBox.shrink());
          });
        }
      }
    }

    // The page's words for the update were cut in the drawer's one line;
    // the drawer has its own short ones, for the pull and the drain alike.
    final updatingStates = <String, SyncStatus>{
      'receiving': lastSynced.copyWith(
        activity: SyncActivity.pulling,
        updating: true,
        updatingTotal: 120,
        downloadedRows: 120,
      ),
      'sending': lastSynced.copyWith(
        activity: SyncActivity.pushing,
        updating: true,
        updatingSending: true,
        updatingTotal: 120,
        updatingSent: 120,
      ),
      'noTotal': lastSynced.copyWith(
        activity: SyncActivity.pulling,
        updating: true,
      ),
    };
    for (final code in const ['en', 'de', 'ro']) {
      testWidgets('$code at 1.0 on a 360 × 780 phone: the update\'s line, at '
          '120 of 120, fits the row', (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          BlocProvider<AppSettingsBloc>.value(
            value: appSettingsBloc,
            child: MaterialApp(
              theme: AppTheme.light(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: Locale(code),
              home: const _DrawerHost(),
            ),
          ),
        );
        await settle(tester);
        await openDrawer(tester);
        final local = AppLocalizations.of(
          tester.element(find.byType(AppDrawer)),
        )!;
        final status = find.descendant(
          of: account(),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.data != userA.displayName &&
                (widget.data?.trim().isNotEmpty ?? false),
          ),
        );

        for (final MapEntry(key: name, value: state)
            in updatingStates.entries) {
          engine.emit(state);
          await settle(tester, rounds: 2);
          expect(status, findsOneWidget, reason: name);
          expect(
            tester.renderObject<RenderParagraph>(status).didExceedMaxLines,
            isFalse,
            reason: '$name "${tester.widget<Text>(status).data}"',
          );
          expect(
            tester.widget<Text>(status).data,
            name == 'noTotal'
                ? local.drawerSyncUpdatingNoTotal
                : local.drawerSyncUpdating(120, 120),
            reason: name,
          );
        }

        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  });
}

/// Answers every read with [status].
class _StatusReader implements SyncStatusReader {
  SyncStatus status = SyncStatus.empty;

  /// When set, the next read waits for it, then clears it.
  Completer<void>? gate;

  @override
  Future<SyncStatus> read({AppUser? user}) async {
    final waiting = gate;
    gate = null;
    if (waiting != null) await waiting.future;
    return status;
  }
}

/// Stands in for the folder page: a scaffold that hosts the drawer.
class _DrawerHost extends StatelessWidget {
  const _DrawerHost();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      drawer: AppDrawer(),
      body: Center(child: Text('host')),
    );
  }
}
