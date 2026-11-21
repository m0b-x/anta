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
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/guide_sync_try_stop.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import 'support/guide_share_card_harness.dart';

/// The sync book's `stop` card (`docs/guide-hub-roadmap.md` §11.4): the
/// shared list's ✕ on one event, then the Sharing page's Stop sharing
/// everything and Unpair with their own confirmations, each step judged on
/// Sam's phone one beat later; done by doing it and by nothing else — an
/// unpair first included; the category's ✕, which the app does not have,
/// says where the real control is; one confirmation per double tap; one stage
/// height whichever phone shows; the languages, themes and guidelines; a
/// page that goes mid-beat.
void main() {
  final en = AppLocalizationsEn();
  final partner = en.syncGuideDemoPartner;
  const card = GuideShareCardHarness('stop');
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

  String oneLine() =>
      en.syncGuideCoachStopOne(en.calendarGuideDemoEventDentist);
  String lookLine() =>
      '${en.syncGuideCoachEventLook(partner)} ${en.syncGuideTryStopFromYou}';
  String allLine() => en.syncGuideCoachStopAll(en.shareStopAll);
  String unpairLine() => en.syncGuideCoachStopUnpair(en.unpair);
  String report() => en.syncGuideReportStopUnpair(partner);
  String pickerReport() =>
      en.syncGuideTryStopCategoryPicker(en.shareRowCategories);

  Finder unshare(String name) => card.byId('unshare-$name');
  Finder stopAll() => card.byId('stop-all');
  Finder unpair() => card.byId('unpair');
  Finder hersRow(String name) => card.byId('here-$name');
  Finder theirsRow(String name) => card.byId('there-$name');

  /// Her row for [name] stands, taken back: its caption says so.
  void expectTakenBack(String name) => expect(
    find.descendant(
      of: hersRow(name),
      matching: find.text(en.syncGuideTryStopNotShared),
    ),
    findsOneWidget,
    reason: name,
  );

  /// The bar of the phone in view reads "{phone} · {area}".
  void expectBar(String phone, String area) => expect(
    find.text(en.syncGuidePhoneBar(phone, area)),
    findsWidgets,
    reason: area,
  );

  bool tileEnabled(WidgetTester tester, Finder row) => tester
      .widget<ListTile>(
        find.descendant(of: row, matching: find.byType(ListTile)),
      )
      .enabled;

  /// A Sharing page row, then its dialog's confirm button.
  Future<void> confirm(WidgetTester tester, Finder row, String button) async {
    await card.tap(tester, row);
    await card.settleRoute(tester);
    await tester.tap(card.byId(button));
    await card.settleRoute(tester);
  }

  testWidgets('each step is done by doing it, and by nothing else', (
    tester,
  ) async {
    final robot = await card.openPage(tester, SyncGuideTopic.stop);
    expect(robot.card, findsOneWidget);
    expect(robot.line, oneLine());
    for (final name in ['gym', 'dentist', 'trips']) {
      expect(hersRow(name), findsOneWidget, reason: name);
      expect(unshare(name), findsOneWidget, reason: name);
    }

    // Everything she shares is on Sam's phone already; looking is no step.
    await card.tap(tester, card.there());
    expect(theirsRow('dentist'), findsOneWidget);
    expect(theirsRow('pilates'), findsOneWidget);
    expect(theirsRow('trips'), findsOneWidget);
    expect(robot.line, oneLine());
    await card.tap(tester, card.here());

    // The page's confirmation, cancelled, stops nothing.
    await card.tap(tester, stopAll());
    await card.settleRoute(tester);
    expect(find.text(en.shareStopAllConfirm(partner)), findsOneWidget);
    await tester.tap(find.text(en.cancel));
    await card.settleRoute(tester);
    await card.beat(tester);
    expect(robot.line, oneLine());

    // Judged on Sam's phone: the ✕ alone is not yet the step. Her row
    // stays where it stood, taken back at once.
    await card.tap(tester, unshare('dentist'));
    expectTakenBack('dentist');
    expect(robot.line, oneLine());
    await card.beat(tester);
    expect(robot.line, lookLine());

    await card.tap(tester, card.there());
    expect(theirsRow('dentist'), findsNothing);
    expect(theirsRow('pilates'), findsOneWidget);
    expect(theirsRow('trips'), findsOneWidget);
    // The category that remains is named over its event.
    expect(
      find.text(FormSectionLabel.capitals(en.eventCategoryGym)),
      findsWidgets,
    );
    expect(robot.line, allLine());

    await card.tap(tester, card.here());
    await confirm(tester, stopAll(), 'stop-all-confirm');
    expect(robot.line, allLine(), reason: 'still on its way');
    await card.beat(tester);
    expect(robot.line, unpairLine());
    expect(tileEnabled(tester, stopAll()), isFalse);
    expect(tileEnabled(tester, unpair()), isTrue);
    // Every row stays, each taken back; she is still paired.
    for (final name in ['gym', 'dentist', 'trips']) {
      expectTakenBack(name);
    }
    expect(find.text(en.shareNothingYet), findsNothing);
    expectBar(en.syncGuidePhoneYours, en.sharingWithTitle(partner));
    await card.tap(tester, card.there());
    expect(find.text(en.syncGuideEmptyFromYou), findsOneWidget);
    await card.tap(tester, card.here());

    await confirm(tester, unpair(), 'unpair-confirm');
    // The report stands at once; her rows go off, as the page's do once
    // the pair is gone, and her phone says it is not paired.
    expect(robot.line, report());
    expect(tileEnabled(tester, unpair()), isFalse);
    expect(find.text(en.pairingNotPaired), findsOneWidget);
    expectBar(en.syncGuidePhoneYours, en.shareSectionLabel);
    // The landing marks the step and leaves the report standing.
    await card.beat(tester);
    expect(robot.line, report());
    expect(robot.lineCandidates, contains(report()));
    await card.tap(tester, card.there());
    expect(find.text(en.pairingNotPaired), findsOneWidget);
    expectBar(en.syncGuidePhoneTheirs(partner), en.shareSectionLabel);
    expect(
      find.text(
        en.syncGuidePhoneBar(
          en.syncGuidePhoneTheirs(partner),
          en.sharingWithTitle(en.syncGuideDemoYou),
        ),
      ),
      findsNothing,
    );
    expect(robot.line, en.calendarGuideCoachDone);
    await card.finish(tester);
  });

  testWidgets('an unpair done first leaves no dead end', (tester) async {
    final robot = await card.openPage(tester, SyncGuideTopic.stop);
    await confirm(tester, unpair(), 'unpair-confirm');
    await card.beat(tester);
    // Nothing of hers is left on Sam's phone: the event and "all" count.
    expect(robot.line, report());
    await card.tap(tester, card.there());
    expect(robot.line, en.calendarGuideCoachDone);
    await card.finish(tester);
  });

  testWidgets('a ✕ on the category or the folder completes nothing by '
      'itself', (tester) async {
    final robot = await card.openPage(tester, SyncGuideTopic.stop);
    await card.tap(tester, unshare('gym'));
    await card.tap(tester, unshare('trips'));
    await card.beat(tester);
    expect(robot.line, oneLine());
    await card.tap(tester, card.there());
    expect(theirsRow('pilates'), findsNothing);
    expect(theirsRow('trips'), findsNothing);
    expect(theirsRow('dentist'), findsOneWidget);
    expect(robot.line, oneLine());
    await card.finish(tester);
  });

  // The app has no ✕ on a category: the stage's says where the real
  // control is when it is used, and takes the category back all the same.
  testWidgets('the category\'s ✕ says the app unticks it in a picker; the '
      'other ✕s say nothing', (tester) async {
    final robot = await card.openPage(tester, SyncGuideTopic.stop);
    expect(robot.lineCandidates, contains(pickerReport()));

    await card.tap(tester, unshare('gym'));
    expectTakenBack('gym');
    expect(robot.line, pickerReport());
    // The landing is no act of hers and leaves the report standing.
    await card.beat(tester);
    expect(robot.line, pickerReport());
    await card.tap(tester, card.there());
    expect(theirsRow('pilates'), findsNothing);
    expect(robot.line, oneLine());

    await card.tap(tester, card.here());
    await card.tap(tester, unshare('trips'));
    expectTakenBack('trips');
    expect(robot.line, oneLine());
    await card.tap(tester, unshare('dentist'));
    expect(robot.line, oneLine());
    await card.finish(tester);
  });

  testWidgets('a ✕ taken back stays where it stood: no other ✕ moves under '
      'the finger', (tester) async {
    final robot = await card.openPage(tester, SyncGuideTopic.stop);
    await tester.ensureVisible(unshare('gym'));
    await tester.pump();
    final before = {
      for (final name in ['gym', 'dentist', 'trips'])
        name: tester.getRect(unshare(name)),
    };
    final finger = before['gym']!.center;

    await tester.tapAt(finger);
    await tester.pump();
    for (final name in ['dentist', 'trips']) {
      expect(tester.getRect(unshare(name)), before[name], reason: name);
    }
    // The row stays, its ✕ off and its caption saying why.
    expect(tester.getRect(unshare('gym')), before['gym']);
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: unshare('gym'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(
      find.descendant(
        of: hersRow('gym'),
        matching: find.text(en.syncGuideTryStopNotShared),
      ),
      findsOneWidget,
    );

    // The finger's second tap, where the first one was, takes nothing else.
    await tester.tapAt(finger);
    await tester.pump();
    await card.beat(tester);
    await card.tap(tester, card.there());
    expect(theirsRow('pilates'), findsNothing);
    expect(theirsRow('dentist'), findsOneWidget);
    expect(theirsRow('trips'), findsOneWidget);
    expect(robot.line, oneLine());
    await card.finish(tester);
  });

  testWidgets('a double tap opens one confirmation', (tester) async {
    await card.openPage(tester, SyncGuideTopic.stop);
    // Two taps before a frame: a finger's second lands on the dialog's
    // barrier once it is laid out, so the row's handler is called twice.
    final row = tester.widget<ListTile>(
      find.descendant(of: stopAll(), matching: find.byType(ListTile)),
    );
    row.onTap!();
    row.onTap!();
    await card.settleRoute(tester);
    expect(find.text(en.shareStopAllConfirm(partner)), findsOneWidget);
    await tester.tap(find.text(en.cancel));
    await card.settleRoute(tester);
    expect(find.text(en.shareStopAllConfirm(partner)), findsNothing);
    await card.finish(tester);
  });

  testWidgets('steps done out of order are not asked for again', (
    tester,
  ) async {
    final robot = await card.openPage(tester, SyncGuideTopic.stop);
    // Everything at once takes the one event back too.
    await confirm(tester, stopAll(), 'stop-all-confirm');
    await card.beat(tester);
    expect(robot.line, lookLine());
    await card.tap(tester, card.there());
    expect(find.text(en.syncGuideEmptyFromYou), findsOneWidget);
    expect(robot.line, unpairLine());
    await card.finish(tester);
  });

  testWidgets('the page goes mid-beat and nothing throws', (tester) async {
    await card.openPage(tester, SyncGuideTopic.stop);
    await card.tap(tester, unshare('dentist'));
    await tester.pump(GuideMetrics.syncBeat ~/ 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(GuideMetrics.syncBeat * 2);
    expect(tester.takeException(), isNull);
  });

  group('the card alone', () {
    late GuideSyncStopDemo demo;

    setUp(() {
      demo = GuideSyncStopDemo(
        SyncGuideTries.stop,
        now: () => DateTime(2026, 11, 26),
      );
    });

    tearDown(() => demo.dispose());

    group('both phones give the stage one rect', () {
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
                final hers = card.stageInCard(tester);
                // A card taller than the screen scrolls on a tap, and
                // the card's offset carries a float's rounding.
                void same(String state) {
                  final now = card.stageInCard(tester);
                  for (final (edge, was, is_) in [
                    ('top', hers.top, now.top),
                    ('height', hers.height, now.height),
                    ('width', hers.width, now.width),
                  ]) {
                    expect(
                      is_,
                      moreOrLessEquals(was, epsilon: 0.01),
                      reason: '$state: $edge',
                    );
                  }
                }

                await card.tap(tester, card.there());
                same("Sam's, everything");
                await card.tap(tester, card.here());
                await card.tap(tester, unshare('dentist'));
                await card.beat(tester);
                same('hers, the event off');
                await card.tap(tester, card.there());
                same("Sam's, two left");
                await card.tap(tester, card.here());
                await card.tap(tester, unshare('gym'));
                same('hers, the category off, its report standing');
                await confirm(tester, stopAll(), 'stop-all-confirm');
                await card.beat(tester);
                same('hers, all taken back');
                await card.tap(tester, card.there());
                same("Sam's, empty");
                await card.tap(tester, card.here());
                await confirm(tester, unpair(), 'unpair-confirm');
                await card.beat(tester);
                same('hers, unpaired');
                await card.tap(tester, card.there());
                same("Sam's, not paired");
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
            card.expectClean(tester, 'hers');
            await card.tap(tester, card.there());
            card.expectClean(tester, "Sam's");
            await card.tap(tester, card.here());
            await confirm(tester, unpair(), 'unpair-confirm');
            await card.beat(tester);
            card.expectClean(tester, 'hers, unpaired');
            await card.tap(tester, card.there());
            card.expectClean(tester, "Sam's, not paired");
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
          await card.tap(tester, unshare('dentist'));
          await card.beat(tester);
          await tester.pumpAndSettle();
          await card.meetsGuidelines(tester, 'hers, the event off');
          await card.tap(tester, card.there());
          await tester.pumpAndSettle();
          await card.meetsGuidelines(tester, "Sam's");
          handle.dispose();
          await card.finish(tester);
        });
      }
    });
  });
}
