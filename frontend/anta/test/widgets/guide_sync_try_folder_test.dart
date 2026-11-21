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
import 'package:anta/widgets/form_menu_item.dart';
import 'package:anta/widgets/guide_sync_try_folder.dart';
import 'package:anta/widgets/guide_two_phones.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import 'support/guide_share_card_harness.dart';

/// The sync book's `folder` card (`docs/guide-hub-roadmap.md` §11.4): the
/// folder menu's own share item, the folder arriving on Sam's phone one
/// beat later, opened under the app's read-only line, and a note copied
/// into Sam's own folder through the partner note's real sheet — each step
/// done by doing it and by nothing else; one stage height whichever phone
/// shows and whatever Sam has open; the languages, themes and guidelines; a
/// page that goes mid-beat.
void main() {
  final en = AppLocalizationsEn();
  final partner = en.syncGuideDemoPartner;
  final shareWith = en.shareWithPartner(partner);
  final trips = en.syncGuideDemoFolderTrips;
  const card = GuideShareCardHarness('folder');
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

  String shareLine() => en.syncGuideCoachFolderShare(trips, shareWith);
  String lookLine() => en.syncGuideCoachEventLook(partner);
  String openLine() => en.syncGuideCoachFolderOpen(trips);
  String copyLine() => en.syncGuideCoachFolderCopy(en.sharedNoteCopy);
  String report() =>
      en.syncGuideReportFolderCopy(partner, en.syncGuideDemoFolderIdeas);

  Finder more([String folder = 'trips']) => card.byId('more-$folder');
  Finder shareItem() => card.byId('share');
  Finder theirsRow(String name) => card.byId('there-$name');
  Finder back() => card.byId('back');
  Finder copy() => find.bySemanticsIdentifier(SemanticsIds.rowActionCopyToMine);

  Future<void> pickShare(WidgetTester tester, [String folder = 'trips']) async {
    await card.tap(tester, more(folder));
    await card.settleRoute(tester);
    await tester.tap(shareItem());
    await card.settleRoute(tester);
  }

  testWidgets('each step is done by doing it, and by nothing else', (
    tester,
  ) async {
    final robot = await card.openPage(tester, SyncGuideTopic.folder);
    expect(robot.card, findsOneWidget);
    expect(robot.line, shareLine());

    // Sam's own folder alone is nothing to look at.
    await card.tap(tester, card.there());
    expect(theirsRow('ideas'), findsOneWidget);
    expect(theirsRow('trips'), findsNothing);
    expect(robot.line, shareLine());
    await card.tap(tester, card.here());

    // Opening the menu and leaving it shares nothing.
    await card.tap(tester, more());
    await card.settleRoute(tester);
    await tester.tapAt(const Offset(5, 5));
    await card.settleRoute(tester);
    expect(robot.line, shareLine());

    await pickShare(tester);
    expect(robot.line, lookLine());

    await card.tap(tester, card.there());
    expect(theirsRow('trips'), findsNothing, reason: 'on its way');
    expect(robot.line, lookLine());
    await card.beat(tester);
    expect(theirsRow('trips'), findsOneWidget);
    expect(theirsRow('recipes'), findsNothing);
    expect(robot.line, openLine());

    await card.tap(tester, theirsRow('trips'));
    expect(
      find.descendant(
        of: card.byId('read-only'),
        matching: find.text(en.sharedNoteLine(en.syncGuideDemoYou)),
      ),
      findsOneWidget,
    );
    expect(theirsRow('lisbon'), findsOneWidget);
    expect(theirsRow('packing'), findsOneWidget);
    expect(robot.line, copyLine());

    // Opening a note's sheet and leaving it copies nothing.
    await card.tap(tester, theirsRow('lisbon'));
    await card.settleRoute(tester);
    expect(copy(), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await card.settleRoute(tester);
    expect(robot.line, copyLine());

    await card.tap(tester, theirsRow('lisbon'));
    await card.settleRoute(tester);
    await tester.tap(copy());
    await card.settleRoute(tester);
    // Done, and the report says where the copy went; Sam's own folder now
    // counts it.
    expect(robot.line, report());
    expect(robot.lineCandidates, contains(report()));
    expect(
      find.descendant(of: theirsRow('ideas'), matching: find.text('1')),
      findsOneWidget,
    );
    // Hers is as it was.
    await card.tap(tester, card.here());
    expect(card.byId('here-trips'), findsOneWidget);
    await card.finish(tester);
  });

  testWidgets('steps done out of order are not asked for again', (
    tester,
  ) async {
    final robot = await card.openPage(tester, SyncGuideTopic.folder);
    // Looking while it arrives counts as the look.
    await pickShare(tester);
    await card.tap(tester, card.there());
    await card.beat(tester);
    expect(robot.line, openLine());
    await card.tap(tester, theirsRow('trips'));
    expect(robot.line, copyLine());
    // Back out and in again: open stays done.
    await card.tap(tester, back());
    expect(theirsRow('trips'), findsOneWidget);
    expect(robot.line, copyLine());
    await card.finish(tester);
  });

  testWidgets('the menu is the folder menu\'s own item, and un-sharing closes '
      'the folder on Sam\'s phone after the beat', (tester) async {
    await card.openPage(tester, SyncGuideTopic.folder);
    await card.tap(tester, more());
    await card.settleRoute(tester);
    expect(
      find.descendant(of: shareItem(), matching: find.text(shareWith)),
      findsOneWidget,
    );
    await tester.tap(shareItem());
    await card.settleRoute(tester);
    await card.beat(tester);

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
    await tester.tapAt(const Offset(5, 5));
    await card.settleRoute(tester);

    await card.tap(tester, card.there());
    await card.tap(tester, theirsRow('trips'));
    expect(back(), findsOneWidget);
    await card.tap(tester, card.here());
    await pickShare(tester);
    await card.tap(tester, card.there());
    expect(theirsRow('lisbon'), findsOneWidget, reason: 'on its way');
    await card.beat(tester);
    expect(theirsRow('lisbon'), findsNothing);
    expect(theirsRow('trips'), findsNothing);
    expect(theirsRow('ideas'), findsOneWidget);
    expect(back(), findsNothing);
    await card.finish(tester);
  });

  testWidgets('Sam\'s own folder opens: empty, then holding the copy', (
    tester,
  ) async {
    final robot = await card.openPage(tester, SyncGuideTopic.folder);
    // What the phone draws, not the template laid out unseen beneath it.
    Finder inStage(String text) => find
        .descendant(of: card.stage(), matching: find.text(text))
        .hitTestable();
    await card.tap(tester, card.there());
    await card.tap(tester, theirsRow('ideas'));
    expect(inStage(en.syncGuideEmptyNotes), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        en.syncGuidePhoneBar(
          en.syncGuidePhoneTheirs(partner),
          en.syncGuideDemoFolderIdeas,
        ),
      ),
      findsOneWidget,
    );
    // Free to look: no step is done by it.
    expect(robot.line, shareLine());
    await card.tap(tester, back());
    expect(theirsRow('ideas'), findsOneWidget);

    await card.tap(tester, card.here());
    await pickShare(tester);
    await card.tap(tester, card.there());
    await card.beat(tester);
    await card.tap(tester, theirsRow('trips'));
    await card.tap(tester, theirsRow('lisbon'));
    await card.settleRoute(tester);
    // The sheet speaks from Sam's side: Sam can't change it, only she can.
    expect(find.text(en.syncGuideSharedNoteCaption(partner)), findsOneWidget);
    await tester.tap(copy());
    await card.settleRoute(tester);
    expect(robot.line, report());

    await card.tap(tester, theirsRow('ideas'));
    expect(inStage(en.syncGuideEmptyNotes), findsNothing);
    expect(inStage(en.syncGuideDemoNoteLisbon), findsOneWidget);
    expect(robot.line, report(), reason: 'the report still stands');
    await card.finish(tester);
  });

  testWidgets('the page goes mid-beat and nothing throws', (tester) async {
    await card.openPage(tester, SyncGuideTopic.folder);
    await pickShare(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(GuideMetrics.syncBeat * 2);
    expect(tester.takeException(), isNull);
  });

  group('the card alone', () {
    late GuideSyncFolderDemo demo;

    setUp(() {
      demo = GuideSyncFolderDemo(
        SyncGuideTries.folder,
        now: () => DateTime(2026, 11, 26, 10),
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
              same("Sam's top, Sam's own folder only");
              await card.tap(tester, card.here());
              await pickShare(tester);
              await pickShare(tester, 'recipes');
              await card.beat(tester);
              same('hers, both shared');
              await card.tap(tester, card.there());
              same("Sam's top, both arrived");
              await card.tap(tester, theirsRow('trips'));
              same("Sam's, Trips open");
              await card.tap(tester, back());
              await card.tap(tester, theirsRow('recipes'));
              same("Sam's, Recipes open");
              await card.tap(tester, back());
              await card.tap(tester, theirsRow('ideas'));
              same("Sam's, Ideas open");
              await card.finish(tester);
            },
          );
        }
      }
    });

    testWidgets("Sam's bar wears his initial, Trips the from-you face", (
      tester,
    ) async {
      await card.openCard(tester, demo);
      await pickShare(tester);
      await card.beat(tester);
      await card.tap(tester, card.there());
      // The bar in view: the template's bars stand unseen before it.
      final bar = find.byType(GuidePhoneBar).last;
      expect(
        find.descendant(of: bar, matching: find.text(partner.characters.first)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: bar, matching: find.byIcon(Icons.person_rounded)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: theirsRow('trips'),
          matching: find.byIcon(Icons.person_rounded),
        ),
        findsOneWidget,
      );
      await card.finish(tester);
    });

    testWidgets('the list starts at one height on both phones', (tester) async {
      await card.openCard(tester, demo);
      // From the stage's top: Sam's bar keeps a back button's room, hers
      // none of her own.
      double topOf(Finder row) =>
          tester.getTopLeft(row).dy - tester.getTopLeft(card.stage()).dy;
      final hers = topOf(card.byId('here-trips'));
      await card.tap(tester, card.there());
      expect(topOf(theirsRow('ideas')), hers);
      await card.finish(tester);
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
            await card.beat(tester);
            card.expectClean(tester, 'hers, shared');
            await card.tap(tester, card.there());
            card.expectClean(tester, "Sam's top");
            await card.tap(tester, theirsRow('trips'));
            card.expectClean(tester, "Sam's, Trips open");
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
          await card.beat(tester);
          await tester.pumpAndSettle();
          await card.meetsGuidelines(tester, 'hers, shared, the dot filled');
          await card.tap(tester, card.there());
          await tester.pumpAndSettle();
          await card.meetsGuidelines(tester, "Sam's top");
          await card.tap(tester, theirsRow('trips'));
          await tester.pumpAndSettle();
          await card.meetsGuidelines(tester, "Sam's, Trips open");
          handle.dispose();
          await card.finish(tester);
        });
      }
    });
  });
}
