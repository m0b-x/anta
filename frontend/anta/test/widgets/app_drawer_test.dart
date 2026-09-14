import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/pages/settings_page.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/drawer_host_registry.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/app_drawer.dart';
import 'package:anta/widgets/leading_nav_pair.dart';

import '../database/support/db_test_support.dart';

/// The drawer's rows and the settings pages they open.
///
/// Two things are pinned here. The first is the **reopen path**: a row awaits
/// its push and asks for the drawer back on `SettingsResult.openDrawer` — but
/// the awaiter's context is the *drawer's* own, and `DrawerController`
/// unmounts that the moment the drawer closes, so the reopen has to be
/// addressed to the host page rather than to a context. The second is that
/// the settings family honours the swipe setting the browser honours; those
/// pages simply never set the flag.
///
/// A plain host stands in for the folder page: what the reopen needs from it
/// is a `Scaffold` with a drawer registered with [DrawerHostRegistry], which
/// is exactly what the browser, the note lists and the editor register.
void main() {
  late AppDatabase db;
  late SettingsService settings;

  final l10n = AppLocalizationsEn();

  setUp(() async {
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);
    DrawerHostRegistry.clear();
    GetIt.I.registerSingleton<AuthService>(NoOpAuthService());
  });

  tearDown(() async {
    DrawerHostRegistry.clear();
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
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const _DrawerHost(),
      ),
    );
    await settle(tester);
  }

  ScaffoldState hostState(WidgetTester tester) =>
      tester.state<ScaffoldState>(find.byType(Scaffold).first);

  testWidgets('a settings page popped with openDrawer raises the host drawer '
      'again', (tester) async {
    await pumpHost(tester);

    hostState(tester).openDrawer();
    await settle(tester);
    expect(hostState(tester).isDrawerOpen, isTrue);

    // Addressed by its description, not its title: the row's title and the
    // drawer header's subtitle are the same string.
    await tester.tap(find.text(l10n.appSettingsDesc));
    await settle(tester);

    // The row closed the drawer and pushed the page; the drawer's own context
    // is gone by now, which is what used to make the reopen a dead branch.
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(hostState(tester).isDrawerOpen, isFalse);

    await tester.tap(
      find.descendant(
        of: find.byType(LeadingNavPair),
        matching: find.byType(BackButtonIcon),
      ),
    );
    await settle(tester);

    expect(find.byType(SettingsPage), findsNothing);
    expect(hostState(tester).isDrawerOpen, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('the edge drag follows the swipe setting', () {
    Future<bool> dragEnabledOnSettingsPage(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SettingsPage(),
        ),
      );
      await settle(tester);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      await tester.pumpWidget(const SizedBox.shrink());
      return scaffold.drawerEnableOpenDragGesture;
    }

    testWidgets('the drag is on when the setting is on', (tester) async {
      await settings.setFolderSwipeEnabled(true);

      expect(await dragEnabledOnSettingsPage(tester), isTrue);
    });

    testWidgets('the drag is off when the setting is off', (tester) async {
      await settings.setFolderSwipeEnabled(false);

      expect(await dragEnabledOnSettingsPage(tester), isFalse);
    });
  });

  group('automation identifiers', () {
    testWidgets('every tagged drawer destination carries its id', (
      tester,
    ) async {
      await pumpHost(tester);
      hostState(tester).openDrawer();
      await settle(tester);

      for (final id in [
        SemanticsIds.drawerCalendar,
        SemanticsIds.drawerSettings,
        SemanticsIds.settingsAppearance,
        SemanticsIds.settingsDatabases,
      ]) {
        expect(
          find.bySemanticsIdentifier(id),
          findsOneWidget,
          reason: '$id is missing from the drawer',
        );
      }

      // The id rides next to the row's own text rather than replacing it:
      // a driver finds the control, a screen reader still reads the row.
      expect(
        find.descendant(
          of: find.bySemanticsIdentifier(SemanticsIds.drawerSettings),
          matching: find.text(l10n.appSettings),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('the leading nav pair carries both halves', (tester) async {
      await pumpHost(tester);
      hostState(tester).openDrawer();
      await settle(tester);
      await tester.tap(find.text(l10n.appSettingsDesc));
      await settle(tester);

      expect(find.bySemanticsIdentifier(SemanticsIds.navBack), findsOneWidget);
      expect(find.bySemanticsIdentifier(SemanticsIds.navMenu), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });
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
