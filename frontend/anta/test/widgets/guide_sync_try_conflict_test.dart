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
import 'package:anta/services/sync/conflict_copy_title.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/guide_sync_try_conflict.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import 'support/guide_share_card_harness.dart';

/// The sync book's `conflict` card (`docs/guide-hub-roadmap.md` §11.4), the
/// second on the offline page: "Packing list" edited on both phones in
/// airplane mode, then both online — the later edit in the note, the other
/// filed beside it under the app's conflict title, on both phones, no line
/// lost. Each step done by doing it; one stage height; the languages, themes
/// and guidelines; a page that goes mid-beat.
void main() {
  final en = AppLocalizationsEn();
  final airplane = en.syncGuideAirplaneMode;
  const card = GuideShareCardHarness('conflict');
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

  String hereLine() => en.syncGuideCoachConflictHere;
  String thereLine() => en.syncGuideCoachConflictThere;
  String onlineLine() => en.syncGuideCoachConflictOnline;
  String report() => en.syncGuideReportConflict;

  Finder addLine(GuidePhone phone) =>
      card.byId(phone == GuidePhone.here ? 'add-line' : 'there-add-line');
  Finder toggle(GuidePhone phone) =>
      card.byId(phone == GuidePhone.here ? 'airplane' : 'there-airplane');
  Finder copyRow(String phone) => card.byId('$phone-packing-copy-1');

  IconButton button(WidgetTester tester, GuidePhone phone) =>
      tester.widget<IconButton>(
        find.descendant(of: toggle(phone), matching: find.byType(IconButton)),
      );

  bool actionEnabled(WidgetTester tester, GuidePhone phone) =>
      tester
          .widget<FormActionRow>(
            find
                .ancestor(
                  of: addLine(phone),
                  matching: find.byType(FormActionRow),
                )
                .first,
          )
          .onTap !=
      null;

  testWidgets('each step is done by doing it, and by nothing else', (
    tester,
  ) async {
    final robot = await card.openPage(tester, SyncGuideTopic.offline);
    expect(robot.card, findsOneWidget);
    expect(robot.line, hereLine());
    expect(button(tester, GuidePhone.here).isSelected, isTrue);

    await card.tap(tester, addLine(GuidePhone.here));
    expect(robot.line, thereLine());
    expect(actionEnabled(tester, GuidePhone.here), isFalse, reason: 'held');
    await card.beat(tester);

    await card.tap(tester, card.there());
    expect(button(tester, GuidePhone.there).isSelected, isTrue);
    await card.tap(tester, addLine(GuidePhone.there));
    expect(robot.line, onlineLine());

    // One phone online meets no conflict yet: the other still holds its
    // edit, unsent.
    await card.tap(tester, toggle(GuidePhone.there));
    await card.beat(tester);
    expect(copyRow('there'), findsNothing);
    expect(robot.line, onlineLine());

    await card.tap(tester, card.here());
    await card.tap(tester, toggle(GuidePhone.here));
    expect(robot.line, onlineLine(), reason: 'only after the beat');
    await card.beat(tester);
    expect(robot.line, report());
    expect(robot.lineCandidates, contains(report()));
    expect(copyRow('here'), findsOneWidget);
    await card.tap(tester, card.there());
    expect(copyRow('there'), findsOneWidget);
    // Her flip is an act of hers, and takes the report down.
    expect(robot.line, en.calendarGuideCoachDone);
    await card.finish(tester);
  });

  testWidgets('the report names each version by its phone: the other phone '
      'edited last, so its line is in the note; this phone last, this '
      'one\'s', (tester) async {
    expect(report(), contains(en.syncGuidePhoneOther.toLowerCase()));
    expect(report(), contains('this phone'));
    expect(onlineLine(), isNot(contains('“$airplane”')));

    // This phone's line added last: the report turns round.
    final robot = await card.openPage(tester, SyncGuideTopic.offline);
    await card.tap(tester, card.there());
    await card.tap(tester, addLine(GuidePhone.there));
    await card.tap(tester, card.here());
    await card.tap(tester, addLine(GuidePhone.here));
    await card.tap(tester, toggle(GuidePhone.here));
    await card.tap(tester, card.there());
    await card.tap(tester, toggle(GuidePhone.there));
    await card.beat(tester);
    expect(robot.line, en.syncGuideReportConflictHere);
    expect(
      robot.lineCandidates,
      containsAll([report(), en.syncGuideReportConflictHere]),
    );
    await card.finish(tester);
  });

  testWidgets('each phone\'s airplane toggle is one node — its id, its '
      'label, a button toggled on then off — and its tap toggles it', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await card.openPage(tester, SyncGuideTopic.offline);
    for (final phone in GuidePhone.values) {
      if (phone == GuidePhone.there) await card.tap(tester, card.there());
      final id = phone == GuidePhone.here
          ? 'guide-sync-try-conflict-airplane'
          : 'guide-sync-try-conflict-there-airplane';
      void expectToggle(Tristate toggled) {
        final node = tester.getSemantics(toggle(phone));
        final data = node.getSemanticsData();
        expect(data.identifier, id);
        expect(data.label, airplane);
        expect(data.flagsCollection.isButton, isTrue);
        expect(data.flagsCollection.isToggled, toggled, reason: phone.name);
        expect(data.flagsCollection.isSelected, Tristate.none);
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        expect(node.childrenCount, 0, reason: 'no second node says it');
      }

      expectToggle(Tristate.isTrue);
      tester.semantics.performAction(
        find.semantics.byPredicate((node) => node.identifier == id),
        SemanticsAction.tap,
      );
      await tester.pump();
      expect(button(tester, phone).isSelected, isFalse);
      expectToggle(Tristate.isFalse);
    }
    handle.dispose();
    await card.finish(tester);
  });

  testWidgets('an edit on one phone alone files no copy', (tester) async {
    final robot = await card.openPage(tester, SyncGuideTopic.offline);
    await card.tap(tester, addLine(GuidePhone.here));
    await card.tap(tester, toggle(GuidePhone.here));
    await card.tap(tester, card.there());
    await card.tap(tester, toggle(GuidePhone.there));
    await card.beat(tester);
    expect(copyRow('there'), findsNothing);
    expect(robot.line, thereLine());
    await card.finish(tester);
  });

  testWidgets('the page goes mid-beat and nothing throws', (tester) async {
    await card.openPage(tester, SyncGuideTopic.offline);
    await card.tap(tester, addLine(GuidePhone.here));
    await card.tap(tester, toggle(GuidePhone.here));
    await tester.pump(GuideMetrics.syncBeat ~/ 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(GuideMetrics.syncBeat * 2);
    expect(tester.takeException(), isNull);
  });

  group('the card alone', () {
    final day = DateTime(2026, 11, 26, 9);
    late GuideSyncConflictDemo demo;

    setUp(() {
      demo = GuideSyncConflictDemo(SyncGuideTries.conflict, now: () => day);
    });

    tearDown(() => demo.dispose());

    /// Both lines added offline, here first, then both phones online.
    Future<void> conflict(WidgetTester tester) async {
      await card.tap(tester, addLine(GuidePhone.here));
      await card.tap(tester, card.there());
      await card.tap(tester, addLine(GuidePhone.there));
      await card.tap(tester, toggle(GuidePhone.there));
      await card.tap(tester, card.here());
      await card.tap(tester, toggle(GuidePhone.here));
      await card.beat(tester);
    }

    testWidgets('the later edit stays in the note, the other is a copy on '
        'both phones, and no line is lost', (tester) async {
      await card.openCard(tester, demo);
      await conflict(tester);
      final copyTitle = conflictCopyTitle(en, en.syncGuideDemoNotePacking, day);
      for (final phone in GuidePhone.values) {
        final notes = demo.sync.notesOn(phone);
        expect(notes, hasLength(2), reason: phone.name);
        expect(notes.first.lines, [
          en.syncGuideDemoLinePassport,
          en.syncGuideDemoLineUmbrella,
        ], reason: 'the later edit, ${phone.name}');
        expect(notes.last.title, copyTitle, reason: phone.name);
        expect(notes.last.lines, [
          en.syncGuideDemoLinePassport,
          en.syncGuideDemoLineSunscreen,
        ], reason: 'the other edit, ${phone.name}');
      }
      expect(
        find.descendant(of: copyRow('here'), matching: find.text(copyTitle)),
        findsOneWidget,
      );
      await card.finish(tester);
    });

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

              await card.tap(tester, addLine(GuidePhone.here));
              same('this, a line');
              await card.tap(tester, card.there());
              same('the other');
              await card.tap(tester, addLine(GuidePhone.there));
              await card.tap(tester, toggle(GuidePhone.there));
              same('the other, a line, online');
              await card.tap(tester, card.here());
              await card.tap(tester, toggle(GuidePhone.here));
              await card.beat(tester);
              same('this, the copy');
              await card.tap(tester, card.there());
              same('the other, the copy');
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
            card.expectClean(tester, 'this, offline');
            await conflict(tester);
            card.expectClean(tester, 'this, the copy');
            await card.tap(tester, card.there());
            card.expectClean(tester, 'the other, the copy');
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
          await card.meetsGuidelines(tester, 'this, offline');
          await conflict(tester);
          await tester.pumpAndSettle();
          await card.meetsGuidelines(tester, 'this, the copy');
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
