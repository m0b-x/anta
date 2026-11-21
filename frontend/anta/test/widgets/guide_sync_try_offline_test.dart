@Timeout(Duration(seconds: 250))
library;

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/guide_metrics.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/sync_guide_content.dart';
import 'package:anta/models/sync_guide_tries.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/guide_sync_try_offline.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import 'support/guide_share_card_harness.dart';

/// The sync book's `offline` card (`docs/guide-hub-roadmap.md` §11.4): this
/// phone's airplane mode in its bar, the status row reading the app's own
/// "Offline — will retry" and counting the note that waits, the other
/// phone's dot a ring until airplane mode is off; each step done by doing
/// it; one stage height; the languages, themes and guidelines; a page that
/// goes mid-beat.
void main() {
  final en = AppLocalizationsEn();
  final airplane = en.syncGuideAirplaneMode;
  final other = en.syncGuidePhoneOther;
  const card = GuideShareCardHarness('offline');
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

  String offLine() => en.syncGuideCoachOfflineOff;
  String writeLine() => en.syncGuideCoachSyncWrite(en.newNote);
  String lookLine() => en.syncGuideCoachSyncLook;
  String onLine() => en.syncGuideCoachOfflineOn;

  Finder toggle() => card.byId('airplane');
  Finder status() => card.byId('status');
  Finder newNote() => card.byId('new-note');
  Finder note(String phone, int n) => card.byId('$phone-new-$n');

  /// [text] in [row]: the row's own line, beside the unseen copy its slot
  /// is sized by.
  Finder says(Finder row, String text) =>
      find.descendant(of: row, matching: find.textContaining(text));

  IconButton button(WidgetTester tester) => tester.widget<IconButton>(
    find.descendant(of: toggle(), matching: find.byType(IconButton)),
  );

  testWidgets('each step is done by doing it, and by nothing else', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final robot = await card.openPage(tester, SyncGuideTopic.offline);
    expect(robot.card, findsOneWidget);
    expect(robot.line, offLine());
    expect(says(status(), en.syncUpToDate), findsWidgets);
    expect(button(tester).isSelected, isFalse);

    // A note made online goes at once and is no waiting note.
    await card.tap(tester, newNote());
    expect(says(status(), en.syncSending(1)), findsWidgets);
    await card.beat(tester);
    expect(robot.line, offLine());
    expect(says(status(), en.syncUpToDate), findsWidgets);

    await card.tap(tester, toggle());
    expect(button(tester).isSelected, isTrue);
    expect(robot.line, writeLine());
    expect(says(status(), en.syncOffline), findsWidgets);

    await card.tap(tester, newNote());
    expect(robot.line, lookLine());
    expect(says(status(), en.syncOffline), findsWidgets);
    expect(says(status(), en.syncDetailsWaiting(1)), findsOneWidget);
    // No beat sets out: the ring stays for as long as it waits.
    expect(
      find.bySemanticsLabel(en.syncGuidePhoneSyncing(other)),
      findsOneWidget,
    );
    await card.beat(tester);
    await card.beat(tester);
    expect(
      find.bySemanticsLabel(en.syncGuidePhoneSyncing(other)),
      findsOneWidget,
    );

    await card.tap(tester, card.there());
    expect(note('there', 1), findsOneWidget);
    expect(note('there', 2), findsNothing);
    expect(robot.line, onLine());
    await card.tap(tester, card.here());

    await card.tap(tester, toggle());
    expect(button(tester).isSelected, isFalse);
    expect(says(status(), en.syncSending(1)), findsWidgets);
    expect(robot.line, onLine(), reason: 'judged on the other phone');
    await card.beat(tester);
    expect(says(status(), en.syncUpToDate), findsWidgets);
    expect(
      find.bySemanticsLabel(en.syncGuidePhoneChanged(other)),
      findsOneWidget,
    );
    expect(robot.line, en.calendarGuideCoachDone);
    await card.tap(tester, card.there());
    expect(note('there', 2), findsOneWidget);
    handle.dispose();
    await card.finish(tester);
  });

  testWidgets('the airplane toggle stands in the bar, 48 × 48, with its '
      'tooltip', (tester) async {
    await card.openPage(tester, SyncGuideTopic.offline);
    final box = find.descendant(
      of: toggle(),
      matching: find.byType(IconButton),
    );
    expect(tester.getSize(box), const Size(48, 48));
    expect(
      find.descendant(of: toggle(), matching: find.byTooltip(airplane)),
      findsOneWidget,
    );
    // In the bar: level with the phone's title, at the stage's top.
    final stage = tester.getRect(card.stage());
    expect(tester.getRect(box).top, stage.top);
    // The other phone carries none.
    await card.tap(tester, card.there());
    expect(toggle(), findsNothing);
    await card.finish(tester);
  });

  testWidgets('the airplane toggle is one node — its id, its label, a '
      'button toggled off then on — and its tap toggles it', (tester) async {
    final handle = tester.ensureSemantics();
    await card.openPage(tester, SyncGuideTopic.offline);
    SemanticsNode node() => tester.getSemantics(toggle());
    void expectToggle(Tristate toggled) {
      final data = node().getSemanticsData();
      expect(data.identifier, 'guide-sync-try-offline-airplane');
      expect(data.label, airplane);
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isToggled, toggled);
      expect(data.flagsCollection.isSelected, Tristate.none);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(node().childrenCount, 0, reason: 'no second node says it');
    }

    expectToggle(Tristate.isFalse);
    // The coach line says where the control is, not a label off screen.
    expect(offLine(), isNot(contains('“$airplane”')));

    tester.semantics.performAction(
      find.semantics.byPredicate(
        (node) => node.identifier == 'guide-sync-try-offline-airplane',
      ),
      SemanticsAction.tap,
    );
    await tester.pump();
    expect(button(tester).isSelected, isTrue);
    expectToggle(Tristate.isTrue);

    await card.tap(tester, toggle());
    expectToggle(Tristate.isFalse);
    handle.dispose();
    await card.finish(tester);
  });

  testWidgets('the page goes mid-beat and nothing throws', (tester) async {
    await card.openPage(tester, SyncGuideTopic.offline);
    await card.tap(tester, newNote());
    await tester.pump(GuideMetrics.syncBeat ~/ 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(GuideMetrics.syncBeat * 2);
    expect(tester.takeException(), isNull);
  });

  group('the card alone', () {
    late GuideSyncOfflineDemo demo;

    setUp(() {
      demo = GuideSyncOfflineDemo(
        SyncGuideTries.offline,
        now: () => DateTime(2026, 11, 26, 9),
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
              final first = card.stageInCard(tester);
              void same(String state) =>
                  expect(card.stageInCard(tester), first, reason: state);

              await card.tap(tester, card.there());
              same('the other');
              await card.tap(tester, card.here());
              await card.tap(tester, toggle());
              await card.tap(tester, newNote());
              same('this, offline, waiting');
              await card.tap(tester, card.there());
              same('the other, nothing new');
              await card.tap(tester, card.here());
              await card.tap(tester, toggle());
              same('this, sending');
              await card.beat(tester);
              same('this, up to date');
              await card.tap(tester, card.there());
              same('the other, arrived');
              await card.finish(tester);
            },
          );
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
            card.expectClean(tester, 'this');
            await card.tap(tester, toggle());
            await card.tap(tester, newNote());
            card.expectClean(tester, 'this, offline, waiting');
            await card.tap(tester, card.there());
            card.expectClean(tester, 'the other');
            await card.tap(tester, card.here());
            await card.tap(tester, toggle());
            card.expectClean(tester, 'this, sending');
            await card.beat(tester);
            card.expectClean(tester, 'this, up to date');
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
          await card.meetsGuidelines(tester, 'this');
          await card.tap(tester, toggle());
          await card.tap(tester, newNote());
          await tester.pumpAndSettle();
          await card.meetsGuidelines(tester, 'this, offline');
          await card.tap(tester, card.there());
          await tester.pumpAndSettle();
          await card.meetsGuidelines(tester, 'the other');
          handle.dispose();
          await card.finish(tester);
        });
      }
    });
  });
}
