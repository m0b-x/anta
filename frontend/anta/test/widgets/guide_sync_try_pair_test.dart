@Timeout(Duration(seconds: 250))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/guide_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/sync_guide_content.dart';
import 'package:anta/models/sync_guide_tries.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/calendar_guide_try_card.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/guide_sync_try_pair.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import 'support/guide_share_card_harness.dart';

/// The sync book's `pair` card (`docs/guide-hub-roadmap.md` §11.4): a code
/// made on her phone, entered on Sam's — by "Fill in the code" or by hand —
/// and the pair both phones hold one beat later; each step done by doing it
/// and by nothing else; a wrong code refused in the app's words; the code's
/// life held still; one stage height in every step; the languages, themes
/// and guidelines; a page that goes mid-beat.
void main() {
  final en = AppLocalizationsEn();
  final partner = en.syncGuideDemoPartner;
  const card = GuideShareCardHarness('pair');
  late AppDatabase db;

  setUpAll(() async {
    await loadGoldenFonts();
    // The code and its field are drawn in monospace, which the test font
    // would measure twice as wide as a phone does.
    await loadMonospaceStandIn();
  });

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

  String inviteLine() => en.syncGuideCoachPairInvite(en.pairingGenerateCode);
  String lookLine() => en.syncGuideCoachEventLook(partner);
  String redeemLine() => en.syncGuideCoachPairRedeem(en.pairingConnect);
  String backLine() => en.syncGuideCoachPairBack;
  String copyReport() => en.syncGuideReportPairCopy(partner);
  String invalid() => en.pairingErrorCodeInvalid;
  const shown = 'K7M2-Q9XP';

  Finder create() => card.byId('create');
  Finder fill() => card.byId('fill');
  Finder connect() => card.byId('connect');
  Finder row() => card.byId('row');
  Finder field() => find.descendant(
    of: card.byId('field'),
    matching: find.byType(EditableText),
  );

  String fieldText(WidgetTester tester) =>
      tester.widget<EditableText>(field()).controller.text;

  bool enabled(WidgetTester tester, Finder target) => tester
      .widget<FilledButton>(
        find.descendant(of: target, matching: find.byType(FilledButton)),
      )
      .enabled;

  Finder within(Finder of, String text) =>
      find.descendant(of: of, matching: find.text(text));

  /// Sam types [text] by hand and taps Connect.
  Future<void> typeAndConnect(WidgetTester tester, String text) async {
    await tester.enterText(field(), text);
    await tester.pump();
    await card.tap(tester, connect());
  }

  testWidgets('each step is done by doing it, and by nothing else', (
    tester,
  ) async {
    final robot = await card.openPage(tester, SyncGuideTopic.pair);
    expect(robot.card, findsOneWidget);
    expect(robot.line, inviteLine());
    expect(within(row(), en.pairingNotPaired), findsOneWidget);

    // Sam's phone before a code: the field is there, "Fill in the code"
    // held, and looking is no step yet.
    await card.tap(tester, card.there());
    expect(field(), findsOneWidget);
    expect(fieldText(tester), isEmpty);
    expect(enabled(tester, connect()), isFalse);
    await card.tap(tester, fill());
    expect(fieldText(tester), isEmpty, reason: 'no code to fill in yet');
    expect(robot.line, inviteLine());
    await card.tap(tester, card.there());
    await card.tap(tester, card.here());

    await card.tap(tester, create());
    expect(robot.line, lookLine());
    expect(within(card.byId('code'), shown), findsOneWidget);
    expect(within(row(), en.pairingWaiting), findsOneWidget);
    expect(within(row(), shown), findsOneWidget);

    // Copy copies nothing on a stage: it says what it would do.
    await card.tap(tester, card.byId('copy'));
    expect(robot.line, copyReport());

    await card.tap(tester, card.there());
    expect(robot.line, redeemLine());
    expect(fieldText(tester), isEmpty, reason: 'the field, empty');

    await card.tap(tester, fill());
    expect(fieldText(tester), shown);
    expect(robot.line, redeemLine(), reason: 'filled is not entered');
    await card.tap(tester, connect());
    expect(robot.line, redeemLine(), reason: 'still on its way');
    expect(within(row(), en.pairingNotPaired), findsOneWidget);
    await card.beat(tester);
    expect(robot.line, backLine());
    expect(within(row(), en.pairingPairedWith(en.syncGuideDemoYou)), findsOne);
    expect(field(), findsNothing, reason: 'the sheet closed itself');

    await card.tap(tester, card.here());
    expect(robot.line, en.calendarGuideCoachDone);
    expect(within(row(), en.pairingPairedWith(partner)), findsOneWidget);
    // The summary's slot lays its templates out beside it.
    expect(within(row(), en.shareNothingYet), findsWidgets);
    await card.finish(tester);
  });

  // "Fill it in" stood inside Sam's phone at Connect's weight, and read as
  // one of the app's controls; the paired row's chevron led nowhere.
  testWidgets('"Fill it in" is the card\'s, not the phone\'s: always in its '
      'place, enabled only on Sam\'s phone while a code waits there; the '
      'paired row says where it leads', (tester) async {
    final robot = await card.openPage(tester, SyncGuideTopic.pair);
    final chip = find.ancestor(of: fill(), matching: find.byType(FormChip));
    bool fillEnabled() => tester.widget<FormChip>(chip).onTap != null;
    expect(
      find.descendant(of: card.stage(), matching: fill()),
      findsNothing,
      reason: 'not on the phone',
    );
    final place = card.stageInCard(tester);
    Rect fillInCard() => tester
        .getRect(chip)
        .shift(-tester.getTopLeft(find.byType(CalendarGuideTryCard)));
    final at = fillInCard();
    expect(at.height, greaterThanOrEqualTo(48));
    expect(at.bottom, lessThanOrEqualTo(place.top));
    expect(fillEnabled(), isFalse, reason: 'her phone, no code');

    await card.tap(tester, card.there());
    expect(fillEnabled(), isFalse, reason: 'no code to fill in yet');
    await card.tap(tester, card.here());
    await card.tap(tester, create());
    expect(fillEnabled(), isFalse, reason: 'the code is on her phone');
    expect(fillInCard(), rectMoreOrLessEquals(at));
    await card.tap(tester, card.there());
    expect(fillEnabled(), isTrue);
    expect(fillInCard(), rectMoreOrLessEquals(at));
    await card.tap(tester, fill());
    await card.tap(tester, connect());
    await card.beat(tester);
    expect(fillEnabled(), isFalse, reason: 'paired: nothing to fill in');
    expect(fillInCard(), rectMoreOrLessEquals(at));

    final sharing = en.syncGuideReportPairSharing(
      en.sharingWithTitle(en.syncGuideDemoYou),
    );
    await card.tap(tester, row());
    expect(robot.line, sharing, reason: "Sam's row");
    await card.tap(tester, card.here());
    await card.tap(tester, row());
    expect(
      robot.line,
      en.syncGuideReportPairSharing(en.sharingWithTitle(partner)),
      reason: 'her row',
    );
    await card.finish(tester);
  });

  testWidgets('a wrong code says the app\'s words and completes nothing', (
    tester,
  ) async {
    final robot = await card.openPage(tester, SyncGuideTopic.pair);
    // Before any code exists, every code is wrong.
    await card.tap(tester, card.there());
    await typeAndConnect(tester, 'ABCD-EFGH');
    expect(within(card.byId('field'), invalid()), findsOneWidget);
    await card.beat(tester);
    expect(robot.line, inviteLine());

    await card.tap(tester, card.here());
    await card.tap(tester, create());
    await card.tap(tester, card.there());
    expect(robot.line, redeemLine());
    await typeAndConnect(tester, 'K7M2-Q9XQ');
    expect(within(card.byId('field'), invalid()), findsOneWidget);
    await card.beat(tester);
    expect(robot.line, redeemLine());
    expect(within(row(), en.pairingNotPaired), findsOneWidget);
    await card.finish(tester);
  });

  testWidgets('the code typed by hand pairs as "Fill in the code" does', (
    tester,
  ) async {
    final robot = await card.openPage(tester, SyncGuideTopic.pair);
    await card.tap(tester, create());
    await card.tap(tester, card.there());
    // Lower case and no dash, as a person types it.
    await typeAndConnect(tester, 'k7m2q9xp');
    await card.beat(tester);
    expect(robot.line, backLine());
    await card.finish(tester);
  });

  testWidgets('back to her phone during the beat counts once it lands', (
    tester,
  ) async {
    final robot = await card.openPage(tester, SyncGuideTopic.pair);
    await card.tap(tester, create());
    await card.tap(tester, card.there());
    await card.tap(tester, fill());
    await card.tap(tester, connect());
    await card.tap(tester, card.here());
    expect(robot.line, redeemLine());
    await card.beat(tester);
    expect(robot.line, en.calendarGuideCoachDone);
    await card.finish(tester);
  });

  testWidgets('the code\'s life is the service\'s ten minutes, held still', (
    tester,
  ) async {
    await card.openPage(tester, SyncGuideTopic.pair);
    await card.tap(tester, create());
    final life = en.pairingCodeExpiresIn('10:00');
    expect(within(card.stage(), life), findsWidgets);
    await tester.pump(const Duration(seconds: 5));
    expect(within(card.stage(), life), findsWidgets);
    expect(within(card.stage(), en.pairingCodeExpiresIn('9:55')), findsNothing);
    await card.finish(tester);
  });

  testWidgets('no stage that draws a section of the real pages carries its '
      'help button: a guide page never links to itself', (tester) async {
    for (final topic in [
      SyncGuideTopic.sync,
      SyncGuideTopic.pair,
      SyncGuideTopic.stop,
    ]) {
      await card.openPage(tester, topic);
      expect(
        find.bySemanticsIdentifier(
          SemanticsIds.guideBookTry('sync', topic.slug),
        ),
        findsOneWidget,
        reason: topic.slug,
      );
      for (final id in [
        SemanticsIds.sharingSyncHow,
        SemanticsIds.sharingPageHow,
      ]) {
        expect(
          find.bySemanticsIdentifier(id, skipOffstage: false),
          findsNothing,
          reason: '${topic.slug}: $id',
        );
      }
      await card.finish(tester);
    }
  });

  testWidgets('the page goes mid-beat and nothing throws', (tester) async {
    await card.openPage(tester, SyncGuideTopic.pair);
    await card.tap(tester, create());
    await card.tap(tester, card.there());
    await card.tap(tester, fill());
    await card.tap(tester, connect());
    await tester.pump(GuideMetrics.syncBeat ~/ 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(GuideMetrics.syncBeat * 2);
    expect(tester.takeException(), isNull);
  });

  group('the card alone', () {
    late GuideSyncPairDemo demo;

    setUp(() {
      demo = GuideSyncPairDemo(
        SyncGuideTries.pair,
        now: () => DateTime(2026, 11, 26),
      );
    });

    tearDown(() => demo.dispose());

    group('both phones give the stage one rect', () {
      for (final size in const [Size(360, 780), Size(412, 915)]) {
        for (final scale in const [1.0, 1.3, 2.0]) {
          for (final locale in const [
            Locale('en'),
            Locale('de'),
            Locale('ro'),
          ]) {
            for (final brightness in Brightness.values) {
              testWidgets(
                '${size.width.toInt()}×${size.height.toInt()} at $scale, '
                '${locale.languageCode} ${brightness.name}',
                (tester) async {
                  await card.openCard(
                    tester,
                    demo,
                    size: size,
                    scale: scale,
                    locale: locale,
                    brightness: brightness,
                  );
                  final hers = card.stageInCard(tester);
                  void same(String state) =>
                      expect(card.stageInCard(tester), hers, reason: state);

                  await card.tap(tester, card.there());
                  same("Sam's, no code yet");
                  await card.tap(tester, card.here());
                  await card.tap(tester, create());
                  same('hers, the code');
                  await card.tap(tester, card.there());
                  same("Sam's, the field empty");
                  await typeAndConnect(tester, 'ABCD-EFGH');
                  same("Sam's, a wrong code");
                  await card.tap(tester, fill());
                  await card.tap(tester, connect());
                  same("Sam's, on its way");
                  await card.beat(tester);
                  same("Sam's, paired");
                  await card.tap(tester, card.here());
                  same('hers, paired');
                  await card.finish(tester);
                },
              );
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
            card.expectClean(tester, 'hers');
            await card.tap(tester, create());
            card.expectClean(tester, 'hers, the code');
            await card.tap(tester, card.there());
            card.expectClean(tester, "Sam's");
            await typeAndConnect(tester, 'ABCD-EFGH');
            card.expectClean(tester, "Sam's, a wrong code");
            await card.tap(tester, fill());
            await card.tap(tester, connect());
            await card.beat(tester);
            card.expectClean(tester, "Sam's, paired");
            await card.tap(tester, card.here());
            card.expectClean(tester, 'hers, paired');
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
          await card.meetsGuidelines(tester, 'hers');
          await card.tap(tester, create());
          await tester.pumpAndSettle();
          await card.meetsGuidelines(tester, 'hers, the code');
          await card.tap(tester, card.there());
          await typeAndConnect(tester, 'ABCD-EFGH');
          await tester.pumpAndSettle();
          await card.meetsGuidelines(tester, "Sam's, a wrong code");
          handle.dispose();
          await card.finish(tester);
        });
      }
    });
  });
}
