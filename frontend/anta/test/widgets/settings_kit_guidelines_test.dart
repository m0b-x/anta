import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/label_appearance.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/app_permission.dart';
import 'package:anta/models/label_style.dart';
import 'package:anta/pages/calendar_settings_page.dart';
import 'package:anta/pages/permissions_page.dart';
import 'package:anta/pages/settings_page.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/drawer_host_registry.dart';
import 'package:anta/services/label_appearance_service.dart';
import 'package:anta/services/public_holiday_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/leading_nav_pair.dart';
import 'package:anta/widgets/permission_tile.dart';
import 'package:anta/widgets/settings_search_field.dart';
import 'package:anta/widgets/settings_section_list.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import '../goldens/support/golden_matrix.dart';
import '../services/permission_support.dart';

/// The settings kit against Android's tap-target, labelled-tap and text
/// contrast guidelines (`docs/settings-rework-roadmap.md` §4.4), on the two
/// pages that use the most of it — App settings and Calendar settings — at
/// 1.0 in light English and at 2.0 in dark German on the small phone, with
/// Roboto loaded so text is measured as a phone draws it. The search field's
/// own contract — 48 dp, growing with the text, a labelled clear button with
/// an id — is pinned beside it.
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
    DrawerHostRegistry.clear();
    GetIt.I.registerSingleton<AuthService>(NoOpAuthService());
  });

  tearDown(() async {
    DrawerHostRegistry.clear();
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
  Future<void> meetsAll(WidgetTester tester) async {
    final list = find
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
      await expectLater(
        tester,
        meetsGuideline(_KitTapTargetGuideline.of(tester)),
        reason: at,
      );
      await expectLater(
        tester,
        meetsGuideline(labeledTapTargetGuideline),
        reason: at,
      );
      await expectLater(
        tester,
        meetsGuideline(textContrastGuideline),
        reason: at,
      );
      if (position.pixels >= position.maxScrollExtent) break;
      position.jumpTo(
        math.min(
          position.pixels + position.viewportDimension / 2,
          position.maxScrollExtent,
        ),
      );
      await tester.pump();
    }
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
  }

  // With no clear-button slot while empty the German hint is whole on the
  // large phone. On the small one it needs about 293 dp beside the glyph and
  // the field has 260 — known, cut until the field's insets or the copy
  // change.
  for (final (size, whole) in const [
    (Size(412, 915), true),
    (Size(360, 780), false),
  ]) {
    testWidgets('the search hint in German at 2.0 on '
        '${size.width.round()} dp is ${whole ? 'whole' : 'cut — known'}', (
      tester,
    ) async {
      final cell = GoldenCell(
        dark: true,
        locale: const Locale('de'),
        textScale: 2.0,
        size: size,
      );
      setGoldenSurface(tester, cell);
      await tester.pumpWidget(goldenApp(cell, home: const SettingsPage()));
      await settle(tester);

      final hint = lookupAppLocalizations(cell.locale).searchSettings;
      expect(
        tester.renderObject<RenderParagraph>(find.text(hint)).didExceedMaxLines,
        !whole,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('Permissions in German at 2.0 lays one letter per line — '
      'known, S5', (tester) async {
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

    // `PermissionTile`'s raw `trailing:` — the action button, laid out first
    // — leaves the title no width, so the exact-alarms row is taller than the
    // phone. S5 moves the page onto `SettingsYieldingTile`, which flips this.
    final title = find.text(
      PermissionPresentation.titleOf(
        lookupAppLocalizations(cell.locale),
        AppPermission.exactAlarms,
      ),
    );
    final tile = find.ancestor(of: title, matching: find.byType(ListTile));
    expect(tester.getSize(tile).height, greaterThan(cell.size.height));
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
}

/// Android's 48 dp tap-target guideline with one accepted exception taken out
/// by name rather than the check skipped: the bar's [LeadingNavPair], whose
/// two 42 dp halves are an app-wide decision of their own (the pair's
/// `halfSize`), drawn on App settings because it has a drawer. Every other
/// node is judged as the stock guideline judges it.
class _KitTapTargetGuideline extends MinimumTapTargetGuideline {
  _KitTapTargetGuideline._(this._ratio, this._pairs)
    : super(size: _android.size, link: _android.link);

  static final MinimumTapTargetGuideline _android =
      androidTapTargetGuideline as MinimumTapTargetGuideline;

  factory _KitTapTargetGuideline.of(WidgetTester tester) =>
      _KitTapTargetGuideline._(tester.view.devicePixelRatio, [
        for (final element in find.byType(LeadingNavPair).evaluate())
          if (element.renderObject case final RenderBox box when box.hasSize)
            box.localToGlobal(Offset.zero) & box.size,
      ]);

  final double _ratio;

  /// Logical pixels, as the widgets measure.
  final List<Rect> _pairs;

  @override
  bool shouldSkipNode(SemanticsNode node) {
    if (super.shouldSkipNode(node)) return true;
    var physical = node.rect;
    for (SemanticsNode? n = node; n != null; n = n.parent) {
      if (n.transform case final transform?) {
        physical = MatrixUtils.transformRect(transform, physical);
      }
    }
    final rect = Rect.fromLTRB(
      physical.left / _ratio,
      physical.top / _ratio,
      physical.right / _ratio,
      physical.bottom / _ratio,
    );
    return _pairs.any((area) {
      final room = area.inflate(0.5);
      return room.contains(rect.topLeft) && room.contains(rect.bottomRight);
    });
  }

  @override
  String get description =>
      '${super.description}, the bar\'s leading pair aside';
}
