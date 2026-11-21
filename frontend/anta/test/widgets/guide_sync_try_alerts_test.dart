@Timeout(Duration(seconds: 250))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/sync_guide_content.dart';
import 'package:anta/models/sync_guide_tries.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/guide_sync_try_alerts.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import 'support/guide_share_card_harness.dart';

/// The sync book's `alerts` card (`docs/guide-hub-roadmap.md` §11.4): her
/// phone alone, no flip; Sam's flight over the Sharing page's own alerts
/// row and menu, and a line that says what would ring under each choice;
/// each step done by choosing it — the app's default included only once
/// chosen — and by nothing else; one menu per double tap; one stage height
/// in every state; the languages, themes and guidelines.
void main() {
  final en = AppLocalizationsEn();
  const card = GuideShareCardHarness('alerts');
  late AppDatabase db;

  setUpAll(loadGoldenFonts);

  // The page reads the money config and the palette once.
  setUp(() async {
    db = await openTestDatabase();
    SettingsService.reset();
    SettingsService.forTesting(db);
  });

  tearDown(() async {
    SettingsService.reset();
    await db.close();
  });

  String offLine() =>
      en.syncGuideCoachAlertsOff(en.shareAlerts, en.shareAlertsOff);
  String ownLine() => en.syncGuideCoachChooseNext(en.shareAlertsOwn);
  String categoryLine() => en.syncGuideCoachChooseNext(en.shareAlertsCategory);
  final both = en.syncGuideRingsBoth(en.syncGuideDemoCategoryTravel);

  Finder alertsRow() => card.byId('alerts');

  String rings(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(of: card.byId('rings'), matching: find.byType(Text)),
      )
      .data!;

  /// The row's value line says [value].
  void expectRowSays(String value) => expect(
    find.descendant(
      of: alertsRow(),
      matching: find.text(value, findRichText: true),
    ),
    findsOneWidget,
    reason: value,
  );

  /// The page's row, then its menu's [choice] — scrolled to first: at 2.0
  /// on a small phone the menu's last choice opens below the screen — and
  /// the menu has gone.
  Future<void> choose(WidgetTester tester, String choice) async {
    await card.tap(tester, alertsRow());
    await card.settleRoute(tester);
    final item = card.byId('alerts-$choice');
    await tester.ensureVisible(item);
    await tester.pump();
    await tester.tap(item);
    await card.settleRoute(tester);
    expect(item, findsNothing, reason: 'the menu closed on $choice');
  }

  testWidgets('her phone alone: no flip, Sam\'s flight, the page\'s row', (
    tester,
  ) async {
    final robot = await card.openPage(tester, SyncGuideTopic.alerts);
    expect(robot.card, findsOneWidget);
    expect(card.stage(), findsOneWidget);
    expect(card.here(), findsNothing);
    expect(card.there(), findsNothing);
    expect(card.byId('row-flight'), findsOneWidget);
    expect(alertsRow(), findsOneWidget);
    // A fresh install's choice: only what she added rings.
    expectRowSays(en.shareAlertsOwn);
    expect(rings(tester), en.syncGuideRingsOwn);
    // What the line speaks of stands on the stage, in the app's words:
    // whose the flight is, her alert and Travel's alarm.
    expect(
      find.text(
        en.syncGuideTryAlertsFlightCaption(
          en.shareFromPartner(en.syncGuideDemoPartner),
          en.eventAlertMinutesBefore(30),
          en.syncGuideDemoCategoryTravel,
          en.eventAlertHoursBefore(3),
        ),
      ),
      findsWidgets,
    );
    expect(robot.line, offLine());
    await card.finish(tester);
  });

  testWidgets('each step is done by choosing it, and by nothing else', (
    tester,
  ) async {
    final robot = await card.openPage(tester, SyncGuideTopic.alerts);

    // A menu dismissed, or the choice already standing, changes nothing.
    await card.tap(tester, alertsRow());
    await card.settleRoute(tester);
    expect(card.byId('alerts-off'), findsOneWidget);
    await tester.tapAt(const Offset(1, 1));
    await card.settleRoute(tester);
    expect(card.byId('alerts-off'), findsNothing);
    await choose(tester, 'own');
    expect(robot.line, offLine());
    expect(rings(tester), en.syncGuideRingsOwn);

    await choose(tester, 'off');
    expect(rings(tester), en.syncGuideRingsNothing);
    expectRowSays(en.shareAlertsOff);
    expect(robot.line, ownLine());

    await choose(tester, 'own');
    expect(rings(tester), en.syncGuideRingsOwn);
    expect(robot.line, categoryLine());

    await choose(tester, 'category');
    expect(rings(tester), both);
    expectRowSays(en.shareAlertsCategory);
    expect(robot.line, en.calendarGuideCoachDone);
    await card.finish(tester);
  });

  testWidgets('steps done out of order are not asked for again', (
    tester,
  ) async {
    final robot = await card.openPage(tester, SyncGuideTopic.alerts);
    await choose(tester, 'category');
    expect(robot.line, offLine());
    await choose(tester, 'own');
    expect(robot.line, offLine());
    await choose(tester, 'off');
    expect(robot.line, en.calendarGuideCoachDone);
    await card.finish(tester);
  });

  testWidgets('a double tap opens one menu', (tester) async {
    await card.openPage(tester, SyncGuideTopic.alerts);
    final row = tester.widget<ListTile>(
      find.descendant(of: alertsRow(), matching: find.byType(ListTile)),
    );
    row.onTap!();
    row.onTap!();
    await card.settleRoute(tester);
    expect(card.byId('alerts-off'), findsOneWidget);
    await tester.tapAt(const Offset(1, 1));
    await card.settleRoute(tester);
    expect(card.byId('alerts-off'), findsNothing);
    await card.finish(tester);
  });

  group('the card alone', () {
    late GuideSyncAlertsDemo demo;

    setUp(() {
      demo = GuideSyncAlertsDemo(
        SyncGuideTries.alerts,
        now: () => DateTime(2026, 11, 26),
      );
    });

    tearDown(() => demo.dispose());

    group('one stage rect in every state', () {
      // The menu's words differ in length by language: German's "own"
      // takes two lines at 2.0 where "Off" takes one.
      for (final locale in const [Locale('en'), Locale('de'), Locale('ro')]) {
        for (final brightness in Brightness.values) {
          for (final size in const [Size(360, 780), Size(412, 915)]) {
            for (final scale in const [1.0, 1.3, 2.0]) {
              testWidgets('${locale.languageCode} ${brightness.name} '
                  '${size.width.toInt()}×${size.height.toInt()} at $scale', (
                tester,
              ) async {
                await card.openCard(
                  tester,
                  demo,
                  locale: locale,
                  brightness: brightness,
                  size: size,
                  scale: scale,
                );
                final first = card.stageInCard(tester);
                // A page taller than the screen scrolls on a tap, and the
                // card's offset carries a float's rounding.
                void same(String state) {
                  final now = card.stageInCard(tester);
                  for (final (edge, was, is_) in [
                    ('top', first.top, now.top),
                    ('height', first.height, now.height),
                    ('width', first.width, now.width),
                  ]) {
                    expect(
                      is_,
                      moreOrLessEquals(was, epsilon: 0.01),
                      reason: '$state: $edge',
                    );
                  }
                }

                for (final choice in ['off', 'category', 'own']) {
                  await choose(tester, choice);
                  same(choice);
                }
                await card.finish(tester);
              });
            }
          }
        }
      }
    });

    group('no overflow and no clipped text at 2.0', () {
      for (final locale in const [Locale('en'), Locale('de'), Locale('ro')]) {
        for (final brightness in Brightness.values) {
          testWidgets('${locale.languageCode} ${brightness.name}', (
            tester,
          ) async {
            await card.openCard(
              tester,
              demo,
              locale: locale,
              brightness: brightness,
              size: const Size(360, 780),
              scale: 2.0,
            );
            card.expectClean(tester, 'own');
            for (final choice in ['off', 'category']) {
              await choose(tester, choice);
              card.expectClean(tester, choice);
            }
            await card.finish(tester);
          });
        }
      }
    });

    group('guidelines', () {
      for (final brightness in Brightness.values) {
        testWidgets('tap targets and contrast, ${brightness.name}', (
          tester,
        ) async {
          final handle = tester.ensureSemantics();
          await card.openCard(tester, demo, brightness: brightness);
          await card.meetsGuidelines(tester, 'own');
          await choose(tester, 'category');
          await tester.pumpAndSettle();
          await card.meetsGuidelines(tester, 'category');
          handle.dispose();
          await card.finish(tester);
        });
      }
    });
  });
}
