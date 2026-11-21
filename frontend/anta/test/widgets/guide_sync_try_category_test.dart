@Timeout(Duration(seconds: 250))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/guide_metrics.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/sync_guide_content.dart';
import 'package:anta/models/sync_guide_tries.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/form_menu_item.dart';
import 'package:anta/widgets/guide_sync_try_category.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import 'support/guide_share_card_harness.dart';

/// The sync book's `category` card (`docs/guide-hub-roadmap.md` §11.4): the
/// Categories page's own ⋮ item shares a whole category, Sam's day fills
/// one beat later, and an event added to the category afterwards follows
/// with no switch of its own — each step done by doing it and by nothing
/// else, judged on the phone the record names; one stage height whichever
/// phone shows; the languages, themes and guidelines; a page that goes
/// mid-beat.
void main() {
  final en = AppLocalizationsEn();
  final partner = en.syncGuideDemoPartner;
  final shareWith = en.shareWithPartner(partner);
  final gym = SyncGuideTries.categoryName(en);
  const card = GuideShareCardHarness('category');
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

  String shareLine() => en.syncGuideCoachCategoryShare(gym, shareWith);
  String lookLine() => en.syncGuideCoachEventLook(partner);
  String addLine() => en.syncGuideCoachCategoryAdd(en.syncGuideAddEventTo(gym));
  String followLine() => en.syncGuideCoachCategoryFollow(partner);

  Finder more() => card.byId('more-gym');
  Finder shareItem() => card.byId('share');
  Finder add() => card.byId('add');
  Finder theirsRow(String name) => card.byId('there-$name');

  /// ⋮ on the shared category, then its one item.
  Future<void> pickShare(WidgetTester tester) async {
    await card.tap(tester, more());
    await card.settleRoute(tester);
    await tester.tap(shareItem());
    await card.settleRoute(tester);
  }

  testWidgets('each step is done by doing it, and by nothing else', (
    tester,
  ) async {
    final robot = await card.openPage(tester, SyncGuideTopic.category);
    expect(robot.card, findsOneWidget);
    expect(robot.line, shareLine());

    // Looking at Sam's phone before anything was shared is no look.
    await card.tap(tester, card.there());
    expect(find.text(en.syncGuideEmptyFromYou), findsOneWidget);
    expect(robot.line, shareLine());
    await card.tap(tester, card.here());

    // Opening the menu and leaving it shares nothing.
    await card.tap(tester, more());
    await card.settleRoute(tester);
    expect(shareItem(), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await card.settleRoute(tester);
    expect(robot.line, shareLine());

    await pickShare(tester);
    expect(robot.line, lookLine());

    // On its way: Sam's day is still empty until the beat lands.
    await card.tap(tester, card.there());
    expect(find.text(en.syncGuideEmptyFromYou), findsOneWidget);
    expect(robot.line, lookLine());
    await card.beat(tester);
    expect(theirsRow('pilates'), findsOneWidget);
    // Only the shared category's events.
    expect(theirsRow('book-club-event'), findsNothing);
    expect(robot.line, addLine());

    await card.tap(tester, card.here());
    await card.tap(tester, add());
    expect(robot.line, followLine());

    // Looking before it arrived is no follow; it counts as it lands.
    await card.tap(tester, card.there());
    expect(theirsRow('yoga'), findsNothing);
    expect(robot.line, followLine());
    await card.beat(tester);
    expect(theirsRow('yoga'), findsOneWidget);
    expect(robot.line, en.calendarGuideCoachDone);
    await card.finish(tester);
  });

  testWidgets('steps done out of order are not asked for again', (
    tester,
  ) async {
    final robot = await card.openPage(tester, SyncGuideTopic.category);
    // The event first: added, but nothing is shared, so Sam sees nothing.
    await card.tap(tester, add());
    expect(robot.line, shareLine());
    await card.beat(tester);
    await card.tap(tester, card.there());
    expect(find.text(en.syncGuideEmptyFromYou), findsOneWidget);
    await card.tap(tester, card.here());

    await pickShare(tester);
    expect(robot.line, lookLine());
    await card.beat(tester);
    // One look sees both, the added event among them: the card is done.
    await card.tap(tester, card.there());
    expect(theirsRow('pilates'), findsOneWidget);
    expect(theirsRow('yoga'), findsOneWidget);
    expect(robot.line, en.calendarGuideCoachDone);
    await card.finish(tester);
  });

  testWidgets('the menu is the page\'s own item: ticked once shared, and a '
      'second pick takes the category back', (tester) async {
    final robot = await card.openPage(tester, SyncGuideTopic.category);
    await card.tap(tester, more());
    await card.settleRoute(tester);
    expect(
      find.descendant(of: shareItem(), matching: find.text(shareWith)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FormMenuChoiceItem<bool>>(
            find.byType(FormMenuChoiceItem<bool>),
          )
          .checked,
      isFalse,
    );
    await tester.tap(shareItem());
    await card.settleRoute(tester);
    await card.beat(tester);
    // The row's caption says it, as the page's does — the caption drawn,
    // not the longest one whose room the row keeps unseen.
    expect(
      find
          .descendant(
            of: card.byId('here-gym'),
            matching: find.textContaining(en.categoryCaptionShared),
          )
          .hitTestable(),
      findsOneWidget,
    );
    expect(
      find
          .descendant(
            of: card.byId('here-cardio'),
            matching: find.textContaining(en.categoryCaptionShared),
          )
          .hitTestable(),
      findsNothing,
    );

    await card.tap(tester, more());
    await card.settleRoute(tester);
    expect(
      find.descendant(
        of: shareItem(),
        matching: find.text(en.sharedWithPartner(partner)),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FormMenuChoiceItem<bool>>(
            find.byType(FormMenuChoiceItem<bool>),
          )
          .checked,
      isTrue,
    );
    await tester.tap(shareItem());
    await card.settleRoute(tester);
    await card.tap(tester, card.there());
    expect(theirsRow('pilates'), findsOneWidget, reason: 'on its way');
    await card.beat(tester);
    expect(theirsRow('pilates'), findsNothing);
    expect(find.text(en.syncGuideEmptyFromYou), findsOneWidget);
    expect(robot.card, findsOneWidget);
    await card.finish(tester);
  });

  testWidgets('the page goes mid-beat and nothing throws', (tester) async {
    await card.openPage(tester, SyncGuideTopic.category);
    await card.tap(tester, add());
    await tester.pump(GuideMetrics.syncBeat ~/ 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(GuideMetrics.syncBeat * 2);
    expect(tester.takeException(), isNull);
  });

  group('the card alone', () {
    late GuideSyncCategoryDemo demo;

    setUp(() {
      demo = GuideSyncCategoryDemo(
        SyncGuideTries.category,
        now: () => DateTime(2026, 11, 26),
      );
    });

    tearDown(() => demo.dispose());

    group('both phones give the stage one rect', () {
      for (final size in const [Size(360, 780), Size(412, 915)]) {
        for (final scale in const [1.0, 1.3, 2.0]) {
          testWidgets(
            '${size.width.toInt()}×${size.height.toInt()} at $scale',
            (tester) async {
              await card.openCard(tester, demo, size: size, scale: scale);
              final hers = card.stageInCard(tester);
              void same(String state) =>
                  expect(card.stageInCard(tester), hers, reason: state);

              await card.tap(tester, card.there());
              same("Sam's, empty");
              await card.tap(tester, card.here());
              await pickShare(tester);
              await card.beat(tester);
              same('hers, shared');
              await card.tap(tester, card.there());
              expect(demo.world.theirs, hasLength(1));
              same("Sam's, one event");
              await card.tap(tester, card.here());
              await card.tap(tester, add());
              await card.beat(tester);
              same('hers, added');
              await card.tap(tester, card.there());
              expect(demo.world.theirs, hasLength(2));
              same("Sam's, two events");
              await card.finish(tester);
            },
          );
        }
      }
    });

    group('sharing and adding move no row under the shared one', () {
      for (final (locale, scale) in const [
        (Locale('en'), 1.0),
        (Locale('de'), 2.0),
      ]) {
        testWidgets('360×780 ${locale.languageCode} at $scale', (tester) async {
          await card.openCard(
            tester,
            demo,
            locale: locale,
            size: const Size(360, 780),
            scale: scale,
          );
          // From the stage's top: bringing the ⋮ into view may scroll the
          // page, which moves the stage, never a row inside it.
          Rect inStage(String row) => tester
              .getRect(card.byId('here-$row'))
              .shift(-tester.getTopLeft(card.stage()));
          final rest = [inStage('cardio'), inStage('book-club')];
          void same(String state) => expect(
            [inStage('cardio'), inStage('book-club')],
            rest,
            reason: state,
          );

          await pickShare(tester);
          same('Gym shared');
          await card.tap(tester, add());
          same('an event added to Gym');
          await card.finish(tester);
        });
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
            await pickShare(tester);
            await card.tap(tester, add());
            await card.beat(tester);
            card.expectClean(tester, 'hers, shared and added');
            await card.tap(tester, card.there());
            card.expectClean(tester, "Sam's");
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
          await pickShare(tester);
          await card.tap(tester, add());
          await card.beat(tester);
          await tester.pumpAndSettle();
          await card.meetsGuidelines(tester, 'hers, shared, the dot filled');
          await card.tap(tester, card.there());
          await tester.pumpAndSettle();
          expect(demo.phone, GuidePhone.there);
          await card.meetsGuidelines(tester, "Sam's");
          handle.dispose();
          await card.finish(tester);
        });
      }
    });
  });
}
