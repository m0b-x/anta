import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/app_settings/app_settings_bloc.dart';
import 'package:anta/bloc/markdown_bar/markdown_bar_bloc.dart';
import 'package:anta/bloc/pairing/pairing_bloc.dart';
import 'package:anta/bloc/sync/sync_bloc.dart';
import 'package:anta/config/default_markdown_shortcuts.dart';
import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/label_appearance.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/app_permission.dart';
import 'package:anta/models/app_user.dart';
import 'package:anta/models/dev_options.dart';
import 'package:anta/models/fasting_appearance.dart';
import 'package:anta/models/label_style.dart';
import 'package:anta/models/pair_record.dart';
import 'package:anta/pages/alert_settings_page.dart';
import 'package:anta/pages/calendar_settings_page.dart';
import 'package:anta/pages/database_settings_page.dart';
import 'package:anta/pages/fasting_settings_page.dart';
import 'package:anta/pages/markdown_settings_page.dart';
import 'package:anta/pages/note_bar_assignment_page.dart';
import 'package:anta/pages/note_money_currency_page.dart';
import 'package:anta/pages/permissions_page.dart';
import 'package:anta/pages/settings_hub_page.dart';
import 'package:anta/pages/settings_page.dart';
import 'package:anta/pages/sync_settings_page.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/label_appearance_service.dart';
import 'package:anta/services/markdown_bar_service.dart';
import 'package:anta/services/pairing_service.dart';
import 'package:anta/services/permission_service.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/auth_error.dart';
import 'package:anta/utils/settings_search.dart';
import 'package:anta/widgets/leading_nav_pair.dart';
import 'package:anta/widgets/permission_tile.dart';
import 'package:anta/widgets/settings_search_field.dart';
import 'package:anta/widgets/settings_section_list.dart';
import 'package:anta/widgets/value_change_highlight.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import '../goldens/support/golden_matrix.dart';
import '../services/pairing_support.dart';
import '../services/permission_support.dart';

/// The settings kit against Android's tap-target, labelled-tap and text
/// contrast guidelines (`docs/settings-rework-roadmap.md` §4.4), on the
/// pages that use the most of it — App settings, Calendar settings, Alert
/// settings and Fasting settings — on the settings hub every page is opened
/// from, on Sharing's action rows, and on the Databases page, Markdown
/// settings and its two per-note pages, still off the kit, at 1.0 in light
/// English and at 2.0 in dark German on the small phone, with Roboto loaded
/// so text is measured as a phone draws it.
/// The search field's own contract — 48 dp, growing with the text, a
/// labelled clear button with an id — is pinned beside it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The app's own database, which the holiday service is bound to, beside
  // the in-memory one the settings live in.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late Directory tempDir;

  setUpAll(() async {
    await loadGoldenFonts();
    tempDir = await Directory.systemTemp.createTemp('anta_settings_kit');
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
    LabelAppearanceService.reset();
    SettingsService.reset();
    CalendarPaletteService.reset();
    CalendarEventService.reset();
    LabelAppearance.style.value = LabelStyle.dot;
    db = await openTestDatabase();
    SettingsService.forTesting(db);
    await CalendarEventService.forTesting(db);
    // Warmed in the real async zone: the service opens the file-backed
    // database, which never completes under a test body's `FakeAsync`.
    await PublicHolidayService.getInstance();
    GetIt.I.registerSingleton<AuthService>(NoOpAuthService());
  });

  tearDown(() async {
    await GetIt.I.reset();
    CalendarEventService.reset();
    PublicHolidayService.reset();
    LabelAppearanceService.reset();
    SettingsService.reset();
    CalendarPaletteService.reset();
    LabelAppearance.style.value = LabelStyle.dot;
    DatabaseLifecycle.notifyDatabaseSwitching();
    await db.close();
  });

  /// Drift answers on futures `FakeAsync` alone never completes, so real time
  /// and pumped frames are interleaved; both pages spin a progress indicator
  /// until their reads land.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (i > 14 && find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
    // Past every fold and fade the late reads started.
    await tester.pump(const Duration(seconds: 1));
  }

  /// The three guidelines at every scroll position of the page's list, top
  /// to bottom, in half-viewport steps: the tap-target guideline skips a node
  /// cut by the viewport's edge and the contrast guideline reads only text a
  /// finger could hit, so the first screen alone judged nothing below it, and
  /// a node cut by one edge in whole-viewport steps would be cut by the other
  /// at the next.
  ///
  /// [list] is the page's own scroll on a page off the kit (Databases).
  ///
  /// [offenders] are the nodes a page off the kit fails today on what §9 of
  /// the record will restyle, not on what its slice touched: each is left out
  /// of its own guideline only, so every other node is still judged, and is
  /// pinned failing somewhere in the walk, so the slice that fixes one sees
  /// that one pin flip.
  Future<void> meetsAll(
    WidgetTester tester, {
    Finder? list,
    List<_Offender> offenders = const [],
  }) async {
    // The settings bars' 42 dp pair left in S7; one coming back is a tap
    // target to judge, not an exception to excuse.
    expect(find.byType(LeadingNavPair), findsNothing);
    // With [only], the guideline judges that offender's nodes and no other.
    AccessibilityGuideline guideline(_Guideline which, {_Offender? only}) {
      final named = only != null
          ? [only]
          : [
              for (final offender in offenders)
                if (offender.guideline == which) offender,
            ];
      final areas = [
        for (final offender in named)
          for (final element in offender.finder.evaluate()) ?_box(element),
      ];
      final texts = {
        for (final offender in named)
          for (final element in offender.finder.evaluate())
            if (element.widget case Text(:final data?)) data,
      };
      final ratio = tester.view.devicePixelRatio;
      bool skip(bool isNamed) => only == null ? isNamed : !isNamed;
      bool skipNode(SemanticsNode node) =>
          skip(_within(areas, _logicalRect(node, ratio)));
      return switch (which) {
        _Guideline.tapTargets => _KitTapTargetGuideline(skipNode),
        _Guideline.labels => _KitLabelGuideline(skipNode),
        _Guideline.contrast => _KitContrastGuideline(
          (data) => skip(
            texts.contains(data.label.isEmpty ? data.value : data.label),
          ),
        ),
      };
    }

    final seenFailing = <_Offender>{};
    list ??= find
        .descendant(
          of: find.byType(SettingsSectionList),
          matching: find.byType(Scrollable),
        )
        .first;
    final position = tester.state<ScrollableState>(list).position;
    while (true) {
      final at =
          'at ${position.pixels.round()} of '
          '${position.maxScrollExtent.round()}';
      for (final which in _Guideline.values) {
        await expectLater(tester, meetsGuideline(guideline(which)), reason: at);
      }
      for (final offender in offenders) {
        if (seenFailing.contains(offender)) continue;
        final evaluation = await guideline(
          offender.guideline,
          only: offender,
        ).evaluate(tester);
        if (!evaluation.passed) seenFailing.add(offender);
      }
      if (position.pixels >= position.maxScrollExtent) break;
      position.jumpTo(
        math.min(
          position.pixels + position.viewportDimension / 2,
          position.maxScrollExtent,
        ),
      );
      await tester.pump();
    }
    for (final offender in offenders) {
      expect(
        seenFailing,
        contains(offender),
        reason:
            '${offender.name} passes ${offender.guideline} now — off the list',
      );
    }
  }

  /// A page off the kit's own vertical scroll — the first one down from it,
  /// never the bar preview's horizontal strip inside it.
  Finder pageScroll(Type page) => find
      .descendant(
        of: find.byType(page),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      )
      .first;

  /// The bar bloc the Markdown pages read, over the app's own database
  /// file, loaded in real async and closed when the test ends.
  Future<MarkdownBarBloc> loadedBarBloc(WidgetTester tester) async {
    final bloc = (await tester.runAsync(() async {
      final bloc = MarkdownBarBloc(
        barService: await MarkdownBarService.getInstance(),
      )..add(const LoadMarkdownBar());
      await bloc.stream.firstWhere((s) => s is MarkdownBarLoaded);
      return bloc;
    }))!;
    addTearDown(bloc.close);
    return bloc;
  }

  /// Two notes for the per-note pages to list, written once into the app's
  /// own database file, which outlives each test's singletons.
  var notesSeeded = false;
  Future<void> seedNotes(WidgetTester tester) async {
    if (notesSeeded) return;
    await tester.runAsync(() async {
      final app = await AppDatabase.getInstance();
      final folder = await app.folderDao.createFolder(name: 'Training');
      await app.noteDao.createNote(folderId: folder.id, title: 'Leg day');
      await app.noteDao.createNote(folderId: folder.id, title: 'Arm day');
    });
    notesSeeded = true;
  }

  const cells = [
    GoldenCell(
      dark: false,
      locale: Locale('en'),
      textScale: 1.0,
      size: Size(360, 780),
    ),
    GoldenCell(
      dark: true,
      locale: Locale('de'),
      textScale: 2.0,
      size: Size(360, 780),
    ),
  ];

  for (final cell in cells) {
    testWidgets('App settings meets the guidelines, ${cell.label}', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      setGoldenSurface(tester, cell);
      await tester.pumpWidget(goldenApp(cell, home: const SettingsPage()));
      await settle(tester);

      expect(tester.takeException(), isNull);
      await meetsAll(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      handle.dispose();
    });

    testWidgets('the settings hub meets the guidelines, ${cell.label}', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final appSettings = AppSettingsBloc();
      addTearDown(appSettings.close);
      setGoldenSurface(tester, cell);
      await tester.pumpWidget(
        goldenApp(
          cell,
          home: BlocProvider<AppSettingsBloc>.value(
            value: appSettings,
            child: const SettingsHubPage(),
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      await meetsAll(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      handle.dispose();
    });

    // The hub at its fullest: the Permissions row's error-coloured attention
    // line in place of its subtitle, and the Developer options row drawn.
    testWidgets('the settings hub with the attention line and Developer '
        'options meets the guidelines, ${cell.label}', (tester) async {
      final handle = tester.ensureSemantics();
      final appSettings = AppSettingsBloc();
      addTearDown(appSettings.close);
      DevOptions.instance.developerModeUnlocked = true;
      addTearDown(DevOptions.instance.lockDeveloperMode);
      final permissions = permissionServiceOver(
        FakePermissionGateway(
          statuses: {
            ...allGranted,
            AppPermission.notifications: PermissionStatus.denied,
          },
        ),
      );
      GetIt.I.registerSingleton<PermissionService>(permissions);
      await tester.runAsync(permissions.refresh);
      setGoldenSurface(tester, cell);
      await tester.pumpWidget(
        goldenApp(
          cell,
          home: BlocProvider<AppSettingsBloc>.value(
            value: appSettings,
            child: const SettingsHubPage(),
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      await meetsAll(tester);
      // Read at the list's end, where [meetsAll] stopped: at 2.0 both rows
      // sit below the first screen.
      final l10n = lookupAppLocalizations(cell.locale);
      expect(find.text(l10n.permissionsRowAttention(1)), findsOneWidget);
      expect(
        find.bySemanticsIdentifier(
          SemanticsIds.settingsHubRow('developerOptions'),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      handle.dispose();
    });

    testWidgets('Calendar settings meets the guidelines, ${cell.label}', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      setGoldenSurface(tester, cell);
      await tester.pumpWidget(
        goldenApp(cell, home: const CalendarSettingsPage()),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      await meetsAll(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      handle.dispose();
    });

    testWidgets('Alert settings meets the guidelines, ${cell.label}', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      setGoldenSurface(tester, cell);
      await tester.pumpWidget(goldenApp(cell, home: const AlertSettingsPage()));
      await settle(tester);

      expect(tester.takeException(), isNull);
      await meetsAll(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      handle.dispose();
    });

    // Orthodox on, so the page holds enabled rows beside the disabled look
    // rows of the three traditions left off.
    testWidgets('Fasting settings meets the guidelines, ${cell.label}', (
      tester,
    ) async {
      await tester.runAsync(
        () async => (await SettingsService.getInstance()).setFastingTraditions(
          const {FastingTradition.orthodox},
        ),
      );
      final handle = tester.ensureSemantics();
      setGoldenSurface(tester, cell);
      await tester.pumpWidget(
        goldenApp(cell, home: const FastingSettingsPage()),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      await meetsAll(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      handle.dispose();
    });

    // Sharing's two action rows at once — Sign out and Unpair, values that
    // are the rows' taps — and the failed sign-in, whose Retry once left the
    // title zero wide (S5).
    for (final failed in [false, true]) {
      testWidgets(
        'Sharing ${failed ? 'after a failed sign-in' : 'signed in '
                  'and paired'} meets the guidelines, ${cell.label}',
        (tester) async {
          final auth = failed
              ? _OfflineAuthService()
              : FakeAuthService(user: userA);
          final gateway = FakePairingGateway();
          addTearDown(gateway.dispose);
          addTearDown(PairingService.reset);
          if (!failed) {
            gateway.seedPair(
              [userA.uid, userB.uid],
              {userB.uid: PairProfile.fromUser(userB)},
            );
          }
          await tester.runAsync(
            () async => PairingService.forTesting(
              auth: auth,
              gateway: gateway,
              settings: await SettingsService.getInstance(),
            ),
          );
          GetIt.I.registerFactory<SyncBloc>(() => SyncBloc(authService: auth));
          GetIt.I.registerFactory<PairingBloc>(
            () => PairingBloc(authService: auth, gateway: gateway),
          );
          final handle = tester.ensureSemantics();
          setGoldenSurface(tester, cell);
          await tester.pumpWidget(
            goldenApp(cell, home: const SyncSettingsPage()),
          );
          await settle(tester);
          if (failed) {
            await tester.tap(
              find.bySemanticsIdentifier(SemanticsIds.sharingSignIn),
            );
            await settle(tester);
            expect(
              find.bySemanticsIdentifier(SemanticsIds.sharingRetry),
              findsOneWidget,
            );
          } else {
            expect(
              find.bySemanticsIdentifier(SemanticsIds.sharingUnpair),
              findsOneWidget,
            );
          }

          expect(tester.takeException(), isNull);
          await meetsAll(tester);
          await tester.pumpWidget(const SizedBox.shrink());
          handle.dispose();
        },
      );
    }

    // Not on the kit (its cards move in the record's §9), so the page's own
    // list is walked; the database list inside it is the app's own database
    // file, which the holiday service opened in setUp.
    testWidgets('Databases meets the guidelines, ${cell.label}', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      setGoldenSurface(tester, cell);
      await tester.pumpWidget(
        goldenApp(cell, home: const DatabaseSettingsPage()),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      await meetsAll(
        tester,
        list: find
            .descendant(
              of: find.byType(DatabaseSettingsPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      handle.dispose();
    });

    // Off the kit too (its cards and menus are §9), walked through its own
    // scroll view; the bars come from the app's own database file.
    testWidgets('Markdown settings meets the guidelines, ${cell.label}', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final barBloc = await loadedBarBloc(tester);
      setGoldenSurface(tester, cell);
      await tester.pumpWidget(
        BlocProvider<MarkdownBarBloc>.value(
          value: barBloc,
          child: goldenPushedApp(
            cell,
            page: MarkdownSettingsPage(
              allShortcuts: DefaultMarkdownShortcuts.shortcuts,
            ),
          ),
        ),
      );
      await settle(tester);

      expect(tester.takeException(), isNull);
      await meetsAll(
        tester,
        list: pageScroll(MarkdownSettingsPage),
        offenders: _markdownOffenders(cell),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      handle.dispose();
    });

    testWidgets('the per-note bars page meets the guidelines, ${cell.label}', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await seedNotes(tester);
      final barBloc = await loadedBarBloc(tester);
      GetIt.I.registerSingleton<MarkdownBarService>(
        (await tester.runAsync(MarkdownBarService.getInstance))!,
      );
      setGoldenSurface(tester, cell);
      await tester.pumpWidget(
        BlocProvider<MarkdownBarBloc>.value(
          value: barBloc,
          child: goldenPushedApp(cell, page: const NoteBarAssignmentPage()),
        ),
      );
      await settle(tester);

      expect(find.text('Leg day'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await meetsAll(
        tester,
        list: pageScroll(NoteBarAssignmentPage),
        offenders: _noteBarsOffenders(cell),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      handle.dispose();
    });

    testWidgets('the per-note currency page meets the guidelines, '
        '${cell.label}', (tester) async {
      final handle = tester.ensureSemantics();
      await seedNotes(tester);
      setGoldenSurface(tester, cell);
      await tester.pumpWidget(
        goldenPushedApp(cell, page: const NoteMoneyCurrencyPage()),
      );
      await settle(tester);

      expect(find.text('Leg day'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await meetsAll(tester, list: pageScroll(NoteMoneyCurrencyPage));
      await tester.pumpWidget(const SizedBox.shrink());
      handle.dispose();
    });
  }

  // The field has 260 dp beside the glyph on the small phone: "Einstellungen
  // suchen" needed about 293 and was cut, so the German hint says "Suchen".
  for (final (page, home, hintOf)
      in <(String, Widget, String Function(AppLocalizations))>[
        ('App settings', const SettingsPage(), (l10n) => l10n.searchSettings),
        (
          'Calendar settings',
          const CalendarSettingsPage(),
          (l10n) => l10n.searchSettings,
        ),
        (
          'the settings hub',
          const SettingsHubPage(),
          (l10n) => l10n.settingsHubSearchHint,
        ),
      ]) {
    for (final size in const [Size(412, 915), Size(360, 780)]) {
      testWidgets('$page: the search hint in German at 2.0 on '
          '${size.width.round()} dp is whole', (tester) async {
        final cell = GoldenCell(
          dark: true,
          locale: const Locale('de'),
          textScale: 2.0,
          size: size,
        );
        final appSettings = AppSettingsBloc();
        addTearDown(appSettings.close);
        setGoldenSurface(tester, cell);
        await tester.pumpWidget(
          goldenApp(
            cell,
            home: BlocProvider<AppSettingsBloc>.value(
              value: appSettings,
              child: home,
            ),
          ),
        );
        await settle(tester);

        final hint = hintOf(lookupAppLocalizations(cell.locale));
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(hint))
              .didExceedMaxLines,
          isFalse,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('Permissions in German at 2.0 keeps every row shorter than '
      'the phone', (tester) async {
    final cell = cells.last;
    setGoldenSurface(tester, cell);
    await tester.pumpWidget(
      goldenApp(
        cell,
        home: PermissionsPage.forTesting(
          service: permissionServiceOver(
            FakePermissionGateway(
              statuses: {
                for (final permission in AppPermission.values)
                  permission: PermissionStatus.denied,
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Pinned at S0 as one letter a line: `PermissionTile`'s raw `trailing:`
    // — the action button, laid out first — left the title no width and the
    // exact-alarms row taller than the phone. Since S6 the action is the
    // row's value on `SettingsYieldingTile`, which yields to the title.
    final title = find.text(
      PermissionPresentation.titleOf(
        lookupAppLocalizations(cell.locale),
        AppPermission.exactAlarms,
      ),
    );
    final tile = find.ancestor(of: title, matching: find.byType(ListTile));
    expect(tester.getSize(tile).height, lessThan(cell.size.height / 2));
    expect(tester.getSize(title).width, greaterThan(cell.size.width / 3));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('the search field', () {
    final l10n = AppLocalizationsEn();

    Future<List<String>> pumpField(
      WidgetTester tester, {
      double textScale = 1.0,
      String? identifier,
    }) async {
      final changes = <String>[];
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: identifier == null
                  ? SettingsSearchField(
                      controller: controller,
                      hint: 'Search settings',
                      onChanged: changes.add,
                    )
                  : SettingsSearchField(
                      controller: controller,
                      hint: 'Search settings',
                      onChanged: changes.add,
                      identifier: identifier,
                    ),
            ),
          ),
        ),
      );
      return changes;
    }

    testWidgets('is 48 dp at 1.0 and grows with the text at 2.0, never '
        'clipping it', (tester) async {
      await pumpField(tester);
      expect(
        tester.getSize(find.byType(SettingsSearchField)).height,
        FormMetrics.rowMinHeight,
      );

      await pumpField(tester, textScale: 2.0);
      final field = tester.getRect(find.byType(SettingsSearchField));
      final hint = tester.getRect(find.text('Search settings'));
      expect(field.height, greaterThan(FormMetrics.rowMinHeight));
      expect(hint.top, greaterThanOrEqualTo(field.top));
      expect(hint.bottom, lessThanOrEqualTo(field.bottom));
      // What a fixed-extent host reserves for it is what it lays out at.
      expect(
        SettingsSearchField.heightFor(
          tester.element(find.byType(SettingsSearchField)),
        ),
        moreOrLessEquals(field.height),
      );
    });

    testWidgets('the hint and the glyph are onSurfaceVariant', (tester) async {
      await pumpField(tester);
      final colorScheme = Theme.of(
        tester.element(find.byType(SettingsSearchField)),
      ).colorScheme;

      final hint = tester.widget<Text>(find.text('Search settings'));
      expect(hint.style?.color, colorScheme.onSurfaceVariant);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.search_rounded)).color,
        colorScheme.onSurfaceVariant,
      );
    });

    testWidgets('the clear button is a labelled 48 dp button with its own '
        'id, drawn once there is text, and empties the query', (tester) async {
      final changes = await pumpField(tester);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.settingsSearch),
        findsOneWidget,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.settingsSearchClear),
        findsNothing,
      );

      await tester.enterText(find.byType(TextField), 'alarm');
      await tester.pump();
      final clear = find.bySemanticsIdentifier(
        SemanticsIds.settingsSearchClear,
      );
      expect(clear, findsOneWidget);
      final button = find.byTooltip(l10n.clearSearch);
      expect(button, findsOneWidget);
      expect(
        tester.getSize(button),
        const Size.square(FormMetrics.trailingButtonSize),
      );

      await tester.tap(button);
      await tester.pump();
      expect(changes.last, '');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(
        find.bySemanticsIdentifier(SemanticsIds.settingsSearchClear),
        findsNothing,
      );
    });

    testWidgets('a page may pass its own field id', (tester) async {
      await pumpField(tester, identifier: 'a-page-search');
      expect(find.bySemanticsIdentifier('a-page-search'), findsOneWidget);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.settingsSearch),
        findsNothing,
      );
    });
  });

  group('the yielding tile', () {
    /// One yielding tile on a kit page, as Alert settings draws its
    /// defaults: [value] in a box no wider than the room it is given, inside
    /// a [ValueChangeHighlight] with [flash], as the holiday set's row is.
    Future<void> pumpTile(
      WidgetTester tester,
      GoldenCell cell, {
      required String title,
      required String description,
      required String value,
      bool flash = false,
      bool enabled = true,
      VoidCallback? onTap,
    }) async {
      Widget box(double maxWidth) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Text(value),
      );
      setGoldenSurface(tester, cell);
      await tester.pumpWidget(
        goldenApp(
          cell,
          home: Scaffold(
            body: SettingsSectionList(
              sections: [
                SettingsSectionData(
                  icon: Icons.schedule_rounded,
                  title: 'Defaults',
                  entries: [
                    SettingsEntry(
                      title: title,
                      description: description,
                      builder: (context, title, description) =>
                          SettingsYieldingTile(
                            leading: const Icon(Icons.today_rounded),
                            title: title,
                            subtitle: description,
                            value: value,
                            trailing: (maxWidth) => flash
                                ? ValueChangeHighlight(
                                    value: value,
                                    child: box(maxWidth),
                                  )
                                : box(maxWidth),
                            onTap: onTap,
                            enabled: enabled,
                          ),
                    ),
                  ],
                ),
              ],
              query: SettingsQuery.empty,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    }

    ListTile tile(WidgetTester tester) =>
        tester.widget<ListTile>(find.byType(ListTile));

    RenderParagraph paragraphOf(WidgetTester tester, String text) =>
        tester.renderObject<RenderParagraph>(find.text(text));

    /// [text] laid out on one line: as tall as one line of its own style.
    void expectOneLine(WidgetTester tester, String text) {
      final paragraph = paragraphOf(tester, text);
      final line = TextPainter(
        text: paragraph.text,
        textScaler: paragraph.textScaler,
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      addTearDown(line.dispose);
      expect(
        paragraph.size.height,
        moreOrLessEquals(line.height),
        reason: text,
      );
    }

    /// [text] is never narrower than its longest word: no word is broken.
    void expectWholeWords(WidgetTester tester, String text) {
      final paragraph = paragraphOf(tester, text);
      expect(
        paragraph.size.width,
        greaterThanOrEqualTo(
          paragraph.getMinIntrinsicWidth(double.infinity) - 0.01,
        ),
        reason: '"$text" breaks inside a word',
      );
    }

    const phoneEn = GoldenCell(
      dark: false,
      locale: Locale('en'),
      textScale: 1.0,
      size: Size(360, 780),
    );

    // Sharing's Unpair while a request runs: the row stays where it is.
    for (final (label, value) in const [
      ('beside the title', 'Off'),
      ('under the description', 'Reminder · The day before, 9:00 AM'),
    ]) {
      testWidgets('disabled with its value $label, it reads disabled and '
          'its tap does nothing', (tester) async {
        final handle = tester.ensureSemantics();
        var taps = 0;
        await pumpTile(
          tester,
          phoneEn,
          title: 'All-day events',
          description: 'The alert a new all-day event starts with',
          value: value,
          enabled: false,
          onTap: () => taps++,
        );

        expect(tile(tester).enabled, isFalse);
        expect(
          tester.getSemantics(find.byType(ListTile)),
          isSemantics(hasEnabledState: true, isEnabled: false),
        );
        await tester.tap(find.byType(ListTile));
        await tester.pump();
        expect(taps, 0);
        handle.dispose();
      });
    }

    testWidgets('at 1.0 on a 360 phone a value that would leave the title '
        'less than half its column goes under the description: the title '
        'on one line, the caption whole', (tester) async {
      const title = 'All-day events';
      const caption = 'The alert a new all-day event starts with';
      const value = 'Reminder · The day before, 9:00 AM';
      await pumpTile(
        tester,
        phoneEn,
        title: title,
        description: caption,
        value: value,
      );

      expect(tile(tester).trailing, isNull);
      expectOneLine(tester, title);
      expectWholeWords(tester, caption);
      expect(
        tester.getRect(find.text(value)).top,
        greaterThanOrEqualTo(tester.getRect(find.text(caption)).bottom),
      );
      expectWholeWords(tester, value);
    });

    testWidgets('at 1.0 on a 360 phone a short value stays beside the title', (
      tester,
    ) async {
      await pumpTile(
        tester,
        phoneEn,
        title: 'All-day events',
        description: 'The alert a new all-day event starts with',
        value: 'No alert',
      );

      expect(tile(tester).trailing, isNotNull);
      expectOneLine(tester, 'All-day events');
      expectOneLine(tester, 'No alert');
    });

    testWidgets('German at 2.0 on a 360 phone a value goes under the '
        'description, as before', (tester) async {
      const title = 'Ganztägige Termine';
      const caption =
          'Die Erinnerung, mit der ein neuer ganztägiger Termin startet';
      const value = 'Mitteilung · Am Vortag, 09:00';
      await pumpTile(
        tester,
        const GoldenCell(
          dark: true,
          locale: Locale('de'),
          textScale: 2.0,
          size: Size(360, 780),
        ),
        title: title,
        description: caption,
        value: value,
      );

      expect(tile(tester).trailing, isNull);
      expectWholeWords(tester, title);
      expectWholeWords(tester, caption);
      expectWholeWords(tester, value);
      expect(
        tester.getRect(find.text(value)).top,
        greaterThanOrEqualTo(tester.getRect(find.text(caption)).bottom),
      );
    });

    testWidgets('a pick whose new value moves it from beside the title to '
        'under the description still flashes', (tester) async {
      const title = 'All-day events';
      const caption = 'The alert a new all-day event starts with';
      const short = 'No alert';
      const long = 'Reminder · The day before, 9:00 AM';

      /// The flash's wash, or null while the highlight paints none.
      Color? wash() {
        final box = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byType(ValueChangeHighlight),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        return (box.decoration as BoxDecoration).color;
      }

      await pumpTile(
        tester,
        phoneEn,
        title: title,
        description: caption,
        value: short,
        flash: true,
      );
      expect(tile(tester).trailing, isNotNull);
      expect(wash(), isNull);

      await pumpTile(
        tester,
        phoneEn,
        title: title,
        description: caption,
        value: long,
        flash: true,
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(tile(tester).trailing, isNull, reason: 'the value moved under');
      expect(wash(), isNotNull);
      await tester.pumpAndSettle();
      expect(wash(), isNull);
    });
  });

  group('the choice row', () {
    testWidgets('disabled, its selected segment keeps a dimmed wash the '
        'others lack, and every segment reads disabled', (tester) async {
      final handle = tester.ensureSemantics();
      const cell = GoldenCell(
        dark: false,
        locale: Locale('en'),
        textScale: 1.0,
        size: Size(360, 780),
      );
      setGoldenSurface(tester, cell);
      await tester.pumpWidget(
        goldenApp(
          cell,
          home: Scaffold(
            body: settingsChoiceRow<_Choice>(
              title: const Text('On fasting days'),
              description: null,
              value: _Choice.second,
              labels: const {
                _Choice.first: 'Event',
                _Choice.second: 'Fasting',
                _Choice.third: 'Both',
              },
              onChanged: (_) {},
              enabled: false,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);

      Color? background(String label) => tester
          .widget<Material>(
            find.descendant(
              of: find.widgetWithText(TextButton, label),
              matching: find.byType(Material),
            ),
          )
          .color;
      final colors = cell.theme.colorScheme;
      expect(
        background('Fasting'),
        colors.secondaryContainer.withValues(
          alpha: FormMetrics.disabledOpacity,
        ),
      );
      // The label keeps its role over the wash, dimmed the same way: the
      // stock disabled grey on it read as a fourth state.
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('Fasting'))
            .text
            .style
            ?.color,
        colors.onSecondaryContainer.withValues(
          alpha: FormMetrics.disabledOpacity,
        ),
      );
      for (final label in ['Event', 'Both']) {
        expect(background(label), isNot(background('Fasting')), reason: label);
        expect(
          tester.getSemantics(find.widgetWithText(TextButton, label)),
          isSemantics(label: label, hasEnabledState: true, isEnabled: false),
        );
      }
      expect(
        tester.getSemantics(find.widgetWithText(TextButton, 'Fasting')),
        isSemantics(
          label: 'Fasting',
          isSelected: true,
          hasEnabledState: true,
          isEnabled: false,
        ),
      );

      handle.dispose();
    });
  });
}

enum _Choice { first, second, third }

/// The three guidelines `meetsAll` walks, in the order it judges them.
enum _Guideline { tapTargets, labels, contrast }

/// An account whose sign-in fails offline: the way to Sharing's Retry row.
class _OfflineAuthService extends FakeAuthService {
  @override
  Future<AppUser?> signInWithGoogle() async =>
      throw const AuthException(AuthError.offline);
}

/// A pre-existing failure of one guideline on a page off the kit, named by
/// the widgets that draw it — a widget type, a key or its text — and left
/// out of that guideline only. §9 of `docs/settings-rework-roadmap.md`
/// restyles every one; until then each is pinned failing, so the restyle
/// that fixes one flips its pin and takes it off the list.
class _Offender {
  const _Offender(this.guideline, this.name, this.finder);

  final _Guideline guideline;

  /// What the pin's failure reason calls it.
  final String name;

  /// The widgets whose semantics nodes are excused: a node inside one of
  /// their boxes for the tap-target and label guidelines, a node reading one
  /// of their [Text]s for the contrast guideline.
  final Finder finder;
}

/// Markdown settings' pre-existing failures, all restyled by §9 of
/// `docs/settings-rework-roadmap.md` (its cards, menus and FAB): the section
/// headers' 26 dp strips, the bar profile selector's 32 dp row and the
/// compact add-bar button under 48 dp; the switches shrunk to 0.8, too short and
/// unlabelled beside their own text; the add-shortcut FAB, unlabelled, and in
/// German at 2.0 drawn over the heading at the screen's foot; the vocabulary
/// trigger's one-glyph segments, whose anti-aliasing reads under 4.5:1; and,
/// in the light theme, the 60 % descriptions (4.28:1) and the toolbar ratio's
/// caption (2.10:1).
List<_Offender> _markdownOffenders(GoldenCell cell) {
  final l10n = lookupAppLocalizations(cell.locale);
  // The five shrunk today, each named by the label of the row it sits in, so
  // a sixth is judged rather than excused.
  final switchLabels = {
    l10n.splitToolbar,
    l10n.pinUndoRedo,
    l10n.vocabularySuggestionsLabel,
    l10n.moneyLedgerEnabledLabel,
    l10n.moneyCurrencySuffixLabel,
  };
  bool inNamedRow(Element element) {
    Element? row;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is! Row) return true;
      row = ancestor;
      return false;
    });
    var named = false;
    void visit(Element child) {
      if (child.widget case Text(
        :final data?,
      ) when switchLabels.contains(data)) {
        named = true;
      }
      if (!named) child.visitChildren(visit);
    }

    row?.visitChildren(visit);
    return named;
  }

  final shrunkSwitches = find.byElementPredicate(
    (element) => switch (element.widget) {
      final Transform transform =>
        transform.child is Switch &&
            transform.transform.entry(0, 0) < 1 &&
            inNamedRow(element),
      _ => false,
    },
  );
  final fab = find.byType(FloatingActionButton);
  return [
    // At 2.0 their text makes them tall enough.
    if (!cell.dark) ...[
      _Offender(
        _Guideline.tapTargets,
        'the section headers',
        find.ancestor(
          of: find.byType(AnimatedRotation),
          matching: find.byType(InkWell),
        ),
      ),
      _Offender(
        _Guideline.tapTargets,
        'the bar profile selector',
        find.ancestor(
          of: find.byIcon(Icons.unfold_more),
          matching: find.byType(InkWell),
        ),
      ),
    ],
    _Offender(
      _Guideline.tapTargets,
      'the compact add-bar button',
      find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.visualDensity == VisualDensity.compact &&
            widget.tooltip == l10n.addBar,
      ),
    ),
    _Offender(_Guideline.tapTargets, 'the 0.8 switches', shrunkSwitches),
    _Offender(_Guideline.labels, 'the 0.8 switches', shrunkSwitches),
    _Offender(_Guideline.labels, 'the add-shortcut FAB', fab),
    _Offender(
      _Guideline.contrast,
      'the vocabulary trigger segments',
      find.descendant(
        of: find.byType(SegmentedButton<String>),
        matching: find.byType(Text),
      ),
    ),
    if (cell.dark)
      _Offender(
        _Guideline.contrast,
        'the heading under the FAB',
        find.byElementPredicate((element) {
          if (element.widget is! Text) return false;
          final text = _box(element);
          if (text == null) return false;
          // The guideline reads 4 dp around the text's box.
          return fab
              .evaluate()
              .map(_box)
              .nonNulls
              .any((cover) => cover.overlaps(text.inflate(4)));
        }),
      )
    else ...[
      for (final description in [
        l10n.moneyLedgerEnabledDesc,
        l10n.vocabularySuggestionsDesc,
        l10n.utilityButtonsHint,
      ])
        _Offender(
          _Guideline.contrast,
          '"$description"',
          find.text(description),
        ),
      _Offender(
        _Guideline.contrast,
        "the toolbar ratio's caption",
        find.textContaining('  ·  ${l10n.utilities} '),
      ),
    ],
  ];
}

/// The per-note bars page's pre-existing failure, restyled by §9 of
/// `docs/settings-rework-roadmap.md`: in the light theme the hint above the
/// search, at 60 % of the text colour, reads 4.28:1.
List<_Offender> _noteBarsOffenders(GoldenCell cell) => [
  if (!cell.dark)
    _Offender(
      _Guideline.contrast,
      'the hint above the search',
      find.text(lookupAppLocalizations(cell.locale).perNoteBarHint),
    ),
];

/// An element's box in logical global pixels, null while it is not laid out.
Rect? _box(Element element) => switch (element.renderObject) {
  final RenderBox box when box.attached && box.hasSize =>
    MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size),
  _ => null,
};

/// A semantics node's rect in logical global pixels, as the widgets measure.
Rect _logicalRect(SemanticsNode node, double ratio) {
  var physical = node.rect;
  for (SemanticsNode? n = node; n != null; n = n.parent) {
    if (n.transform case final transform?) {
      physical = MatrixUtils.transformRect(transform, physical);
    }
  }
  return Rect.fromLTRB(
    physical.left / ratio,
    physical.top / ratio,
    physical.right / ratio,
    physical.bottom / ratio,
  );
}

bool _within(List<Rect> areas, Rect rect) => areas.any((area) {
  final room = area.inflate(0.5);
  return room.contains(rect.topLeft) && room.contains(rect.bottomRight);
});

/// Android's 48 dp tap-target guideline, judged node for node as the stock
/// one judges it but for the nodes [_skip] names (the walk's offenders).
class _KitTapTargetGuideline extends MinimumTapTargetGuideline {
  _KitTapTargetGuideline(this._skip)
    : super(size: _android.size, link: _android.link);

  static final MinimumTapTargetGuideline _android =
      androidTapTargetGuideline as MinimumTapTargetGuideline;

  final bool Function(SemanticsNode node) _skip;

  @override
  bool shouldSkipNode(SemanticsNode node) =>
      super.shouldSkipNode(node) || _skip(node);
}

/// Flutter's labelled-tap-target guideline, judged node for node as the
/// stock one judges it — which cannot be extended, its constructor being
/// private — but for the nodes [_skip] names.
class _KitLabelGuideline extends AccessibilityGuideline {
  const _KitLabelGuideline(this._skip);

  final bool Function(SemanticsNode node) _skip;

  @override
  String get description => labeledTapTargetGuideline.description;

  @override
  Evaluation evaluate(WidgetTester tester) {
    var result = const Evaluation.pass();
    for (final view in tester.binding.renderViews) {
      result += _traverse(view.owner!.semanticsOwner!.rootSemanticsNode!);
    }
    return result;
  }

  Evaluation _traverse(SemanticsNode node) {
    var result = const Evaluation.pass();
    node.visitChildren((child) {
      result += _traverse(child);
      return true;
    });
    if (node.isMergedIntoParent || node.isInvisible) return result;
    // The merged data's flags: under `AutomationId`'s `MergeSemantics` a
    // field's text-field flag is its child's, never the node's own.
    final data = node.getSemanticsData();
    if (node.flagsCollection.isHidden ||
        data.flagsCollection.isTextField ||
        _skip(node)) {
      return result;
    }
    if (!data.hasAction(SemanticsAction.longPress) &&
        !data.hasAction(SemanticsAction.tap)) {
      return result;
    }
    if (data.label.isEmpty && data.tooltip.isEmpty) {
      result += Evaluation.fail(
        '$node: expected tappable node to have semantic label, '
        'but none was found.',
      );
    }
    return result;
  }
}

/// Flutter's 4.5:1 text-contrast guideline but for the nodes [_skip] names.
class _KitContrastGuideline extends MinimumTextContrastGuideline {
  const _KitContrastGuideline(this._skip);

  final bool Function(SemanticsData data) _skip;

  @override
  bool shouldSkipNode(SemanticsData data) =>
      super.shouldSkipNode(data) || _skip(data);
}
