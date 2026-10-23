import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/constants/form_metrics.dart';
import 'package:anta/constants/label_appearance.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/label_style.dart';
import 'package:anta/models/restore_location_mode.dart';
import 'package:anta/pages/settings_page.dart';
import 'package:anta/services/auth_service.dart';
import 'package:anta/services/drawer_host_registry.dart';
import 'package:anta/services/label_appearance_service.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/settings_search_field.dart';
import 'package:anta/widgets/settings_section_list.dart';

import '../database/support/db_test_support.dart';

/// The label-style row on the settings page, against a real in-memory
/// database.
///
/// Two things are worth pinning. The row writes through
/// `LabelAppearanceService` rather than `SettingsService`, because the
/// browser sitting under this page repaints off the published facade and a
/// write that skipped it would only show up on the next launch. And the row
/// is findable by its hidden keywords, which is the only way someone who
/// thinks of it as "stripe" ever reaches it.
void main() {
  late AppDatabase db;
  late SettingsService settings;

  final l10n = AppLocalizationsEn();

  setUp(() async {
    LabelAppearanceService.reset();
    SettingsService.reset();
    LabelAppearance.style.value = LabelStyle.dot;
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);
    DrawerHostRegistry.clear();
    GetIt.I.registerSingleton<AuthService>(NoOpAuthService());
  });

  tearDown(() async {
    DrawerHostRegistry.clear();
    await GetIt.I.reset();
    LabelAppearanceService.reset();
    SettingsService.reset();
    LabelAppearance.style.value = LabelStyle.dot;
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

  Future<void> pumpPage(
    WidgetTester tester, {
    Size size = const Size(1000, 2400),
    Locale locale = const Locale('en'),
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const SettingsPage(),
      ),
    );
    await settle(tester);
  }

  /// Filters the page down to the row under test — the section list builds
  /// every open section, and the browsing rows sit well below the fold.
  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(
      find.descendant(
        of: find.byType(SettingsSearchField),
        matching: find.byType(TextField),
      ),
      query,
    );
    await settle(tester);
  }

  testWidgets('the browsing section offers the label style, findable by its '
      'keywords', (tester) async {
    await pumpPage(tester);

    await search(tester, 'stripe');

    expect(find.text(l10n.labelStyle), findsOneWidget);
    expect(find.text(l10n.labelStyleDot), findsOneWidget);
    expect(find.text(l10n.labelStyleStripe), findsOneWidget);
    expect(find.text(l10n.showStatsBar), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('choosing the edge stripe persists it and publishes it to the '
      'rows underneath', (tester) async {
    await pumpPage(tester);
    await search(tester, 'stripe');

    await tester.tap(find.text(l10n.labelStyleStripe));
    await settle(tester);

    expect(LabelAppearance.style.value, LabelStyle.stripe);
    expect(await settings.getLabelStyle(), LabelStyle.stripe);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Reset to defaults puts the style back to the dot and leaves '
      'the row in the store', (tester) async {
    await settings.setLabelStyle(LabelStyle.stripe);
    final service = await LabelAppearanceService.getInstance();
    expect(LabelAppearance.style.value, LabelStyle.stripe);
    expect(service.style, LabelStyle.stripe);

    await pumpPage(tester);
    // The reset button is the section list's footer, and the footer is only
    // built while the search box is empty — so it has to be scrolled to
    // rather than filtered to.
    await tester.scrollUntilVisible(
      find.text(l10n.resetToDefaults),
      600,
      scrollable: find
          .descendant(
            of: find.byType(SettingsSectionList),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await settle(tester);

    await tester.tap(find.text(l10n.resetToDefaults));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.reset));
    await settle(tester);

    expect(
      LabelAppearance.style.value,
      LabelStyle.dot,
      reason:
          'the reset writes through the service, so the browser underneath '
          'repaints rather than waiting for the next launch',
    );
    expect(await settings.getLabelStyle(), LabelStyle.dot);
    expect(
      await db.userSettingsDao.getValue(SettingsKeys.labelStyle),
      LabelStyle.dot.name,
      reason: 'the default is carried explicitly, not by the row\'s absence',
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the page opens on the persisted style', (tester) async {
    await settings.setLabelStyle(LabelStyle.stripe);

    await pumpPage(tester);
    await search(tester, 'stripe');

    final segmented = tester.widget<SegmentedButton<LabelStyle>>(
      find.byType(SegmentedButton<LabelStyle>),
    );
    expect(segmented.selected, {LabelStyle.stripe});

    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('the Start choices', () {
    final start = find.byType(SegmentedButton<RestoreLocationMode>);

    testWidgets('sit side by side while their words fit', (tester) async {
      await pumpPage(tester);

      final button = tester.widget<SegmentedButton<RestoreLocationMode>>(start);
      expect(button.direction, Axis.horizontal);
      // The theme's stadium, untouched.
      expect(button.style?.shape, isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('stack at 2.0 in German on a phone and break no word', (
      tester,
    ) async {
      await pumpPage(
        tester,
        size: const Size(360, 780),
        locale: const Locale('de'),
        textScale: 2.0,
      );

      final button = tester.widget<SegmentedButton<RestoreLocationMode>>(start);
      expect(button.direction, Axis.vertical);
      // Stacked, the group has the menu's corners, not a tall pill.
      expect(
        button.style?.shape?.resolve(const {}),
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(FormMetrics.menuRadius),
          ),
        ),
      );
      final labels = find.descendant(
        of: start,
        matching: find.byType(RichText),
      );
      expect(labels, findsNWidgets(RestoreLocationMode.values.length));
      for (final segment
          in find
              .descendant(of: start, matching: find.byType(TextButton))
              .evaluate()) {
        expect(
          (segment.renderObject! as RenderBox).size.height,
          greaterThanOrEqualTo(kMinInteractiveDimension),
        );
      }
      for (final element in labels.evaluate()) {
        final paragraph = element.renderObject! as RenderParagraph;
        final text = paragraph.text.toPlainText();
        // The label laid out again as the paragraph laid it out, for its
        // line boundaries; every line must end at a space or the label's end.
        final painter = TextPainter(
          text: paragraph.text,
          textAlign: paragraph.textAlign,
          textDirection: paragraph.textDirection,
          textScaler: paragraph.textScaler,
        )..layout(maxWidth: paragraph.constraints.maxWidth);
        addTearDown(painter.dispose);
        var offset = 0;
        while (offset < text.length) {
          final line = painter.getLineBoundary(TextPosition(offset: offset));
          final end = line.end;
          final atSpace =
              end >= text.length ||
              text[end - 1].trim().isEmpty ||
              text[end].trim().isEmpty;
          expect(atSpace, isTrue, reason: '"$text" broke at $end');
          offset = end > offset ? end : offset + 1;
        }
      }
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
