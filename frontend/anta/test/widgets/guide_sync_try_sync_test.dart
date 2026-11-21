@Timeout(Duration(seconds: 250))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/guide_metrics.dart';
import 'package:anta/constants/row_metrics.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/sync_guide_content.dart';
import 'package:anta/models/sync_guide_tries.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/guide_sync_phones.dart' show GuideSyncNoteTask;
import 'package:anta/widgets/guide_sync_try_sync.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import 'support/guide_share_card_harness.dart';

/// The sync book's `sync` card (`docs/guide-hub-roadmap.md` §11.4): the Sync
/// section's own rows on this phone — "Sync this database", then the status
/// row and Sync now — over its notes, and the other phone with nothing until
/// sync is on. Each step is done by doing it and by nothing else; the status
/// row reads the app's own lines; one stage height whichever phone shows; the
/// languages, themes and guidelines; a page that goes mid-beat.
void main() {
  final en = AppLocalizationsEn();
  const card = GuideShareCardHarness('sync');
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

  String onLine() => en.syncGuideCoachSyncOn(en.syncThisDatabase);
  String writeLine() =>
      en.syncGuideCoachSyncWriteStatus(en.syncUpToDate, en.newNote);
  String lookLine() => en.syncGuideCoachSyncLook;
  String editLine() => en.syncGuideCoachSyncEdit;

  Finder bind() => card.byId('bind');
  Finder status() => card.byId('status');
  Finder syncNow() => card.byId('now');
  Finder newNote() => card.byId('new-note');
  Finder note(String phone) => card.byId('$phone-new-1');
  Finder task(String phone) => card.byId('$phone-new-1-task');

  /// [text] in [row]: the row's own line, beside the unseen copy its slot
  /// is sized by.
  Finder says(Finder row, String text) =>
      find.descendant(of: row, matching: find.text(text));

  bool checked(WidgetTester tester, String phone) =>
      tester
          .widget<Checkbox>(
            find.descendant(of: task(phone), matching: find.byType(Checkbox)),
          )
          .value ??
      false;

  bool nowEnabled(WidgetTester tester) => tester
      .widget<ListTile>(
        find.descendant(of: syncNow(), matching: find.byType(ListTile)),
      )
      .enabled;

  testWidgets('each step is done by doing it, and by nothing else', (
    tester,
  ) async {
    final robot = await card.openPage(tester, SyncGuideTopic.sync);
    expect(robot.card, findsOneWidget);
    expect(robot.line, onLine());
    expect(says(bind(), en.syncThisDatabaseDesc), findsWidgets);
    expect(status(), findsNothing);
    expect(syncNow(), findsNothing);

    // Nothing syncs while it is off: the note stays here, nothing travels.
    await card.tap(tester, newNote());
    expect(note('here'), findsOneWidget);
    expect(robot.line, onLine());
    await card.beat(tester);
    await card.tap(tester, card.there());
    expect(find.text(en.syncGuideEmptyNotes), findsOneWidget);
    expect(note('there'), findsNothing);
    expect(robot.line, onLine(), reason: 'nothing to look at yet');
    await card.tap(tester, card.here());

    // On: the bind sends everything, the note made before it too.
    await card.tap(tester, bind());
    expect(robot.line, lookLine());
    expect(says(status(), en.syncSending(3)), findsWidgets);
    expect(nowEnabled(tester), isFalse, reason: 'a run is under way');
    await card.beat(tester);
    expect(says(status(), en.syncUpToDate), findsWidgets);
    expect(nowEnabled(tester), isTrue);

    await card.tap(tester, card.there());
    expect(note('there'), findsOneWidget);
    expect(robot.line, editLine());

    // Judged here: the tick made there is not yet the step.
    await card.tap(tester, task('there'));
    expect(checked(tester, 'there'), isTrue);
    expect(robot.line, editLine());
    await card.beat(tester);
    expect(robot.line, en.calendarGuideCoachDone);
    await card.tap(tester, card.here());
    expect(checked(tester, 'here'), isTrue);
    await card.finish(tester);
  });

  testWidgets('a note made after sync is on is the write step', (tester) async {
    final robot = await card.openPage(tester, SyncGuideTopic.sync);
    await card.tap(tester, bind());
    expect(robot.line, writeLine());
    await card.beat(tester);
    await card.tap(tester, newNote());
    expect(robot.line, lookLine());
    expect(says(status(), en.syncSending(1)), findsWidgets);
    // Looking before it landed counts once it lands in front of her.
    await card.tap(tester, card.there());
    expect(note('there'), findsNothing);
    expect(robot.line, lookLine());
    await card.beat(tester);
    expect(note('there'), findsOneWidget);
    expect(robot.line, editLine());
    await card.finish(tester);
  });

  testWidgets('the line after the bind names the status row\'s lesson: it '
      'waits for "Up to date" there', (tester) async {
    final robot = await card.openPage(tester, SyncGuideTopic.sync);
    await card.tap(tester, bind());
    expect(robot.line, writeLine());
    expect(robot.line, contains('“${en.syncUpToDate}”'));
    expect(says(status(), en.syncSending(2)), findsWidgets);
    await card.beat(tester);
    expect(says(status(), en.syncUpToDate), findsWidgets);
    expect(robot.line, writeLine());
    await card.finish(tester);
  });

  testWidgets('the task line reads as a line of its note: under it, in the '
      'note\'s second-line type behind its checkbox, one 48 dp target', (
    tester,
  ) async {
    await card.openPage(tester, SyncGuideTopic.sync);
    await card.tap(tester, newNote());
    final row = task('here');
    expect(row, findsOneWidget);
    expect(
      find.ancestor(of: row, matching: find.byType(GuideSyncNoteTask)),
      findsOneWidget,
    );
    expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
    expect(
      tester.getRect(row).top,
      greaterThanOrEqualTo(tester.getRect(note('here')).bottom),
    );
    final words = find.descendant(
      of: row,
      matching: find.text(en.syncGuideDemoTaskMilk),
    );
    expect(
      tester.widget<Text>(words).style?.fontSize,
      RowMetrics.secondLineFontSize,
    );
    // The box leads, as a note's task line does: the words come after it.
    expect(
      tester.getRect(words).left,
      greaterThan(
        tester
            .getRect(
              find.descendant(of: row, matching: find.byType(Checkbox)),
            )
            .right,
      ),
    );
    await card.tap(tester, row);
    expect(checked(tester, 'here'), isTrue);
    await card.finish(tester);
  });

  testWidgets('a tick made here is no road to the last step', (tester) async {
    final robot = await card.openPage(tester, SyncGuideTopic.sync);
    await card.tap(tester, bind());
    await card.tap(tester, newNote());
    await card.beat(tester);
    await card.tap(tester, card.there());
    await card.tap(tester, card.here());
    await card.tap(tester, task('here'));
    expect(says(status(), en.syncSending(1)), findsWidgets);
    await card.beat(tester);
    expect(robot.line, editLine());
    await card.tap(tester, card.there());
    expect(checked(tester, 'there'), isTrue);
    expect(robot.line, editLine());
    await card.finish(tester);
  });

  testWidgets('Sync now while nothing waits says both phones match', (
    tester,
  ) async {
    final robot = await card.openPage(tester, SyncGuideTopic.sync);
    await card.tap(tester, bind());
    await card.beat(tester);
    await card.tap(tester, syncNow());
    expect(robot.line, en.syncGuideReportSyncNow);
    expect(robot.lineCandidates, contains(en.syncGuideReportSyncNow));
    await card.finish(tester);
  });

  testWidgets('the other phone rings while the note travels, then fills', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await card.openPage(tester, SyncGuideTopic.sync);
    final other = en.syncGuidePhoneOther;
    await card.tap(tester, bind());
    expect(
      find.bySemanticsLabel(en.syncGuidePhoneSyncing(other)),
      findsOneWidget,
    );
    await card.beat(tester);
    expect(
      find.bySemanticsLabel(en.syncGuidePhoneChanged(other)),
      findsOneWidget,
    );
    handle.dispose();
    await card.finish(tester);
  });

  testWidgets('the page goes mid-beat and nothing throws', (tester) async {
    await card.openPage(tester, SyncGuideTopic.sync);
    await card.tap(tester, bind());
    await tester.pump(GuideMetrics.syncBeat ~/ 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(GuideMetrics.syncBeat * 2);
    expect(tester.takeException(), isNull);
  });

  group('the card alone', () {
    late GuideSyncSyncDemo demo;

    setUp(() {
      demo = GuideSyncSyncDemo(
        SyncGuideTries.sync,
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
              final first = card.stageInCard(tester);
              void same(String state) =>
                  expect(card.stageInCard(tester), first, reason: state);

              await card.tap(tester, card.there());
              same('the other, empty');
              await card.tap(tester, card.here());
              await card.tap(tester, bind());
              same('this, sending');
              await card.tap(tester, newNote());
              await card.beat(tester);
              same('this, up to date');
              await card.tap(tester, card.there());
              same('the other, the notes');
              await card.tap(tester, task('there'));
              await card.beat(tester);
              same('the other, ticked');
              await card.tap(tester, card.here());
              same('this, ticked');
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
            card.expectClean(tester, 'this, off');
            await card.tap(tester, card.there());
            card.expectClean(tester, 'the other, empty');
            await card.tap(tester, card.here());
            await card.tap(tester, bind());
            await card.tap(tester, newNote());
            card.expectClean(tester, 'this, sending');
            await card.beat(tester);
            card.expectClean(tester, 'this, up to date');
            await card.tap(tester, card.there());
            card.expectClean(tester, 'the other, the notes');
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
          await card.meetsGuidelines(tester, 'this, off');
          await card.tap(tester, bind());
          await card.tap(tester, newNote());
          await card.beat(tester);
          await tester.pumpAndSettle();
          await card.meetsGuidelines(tester, 'this, up to date');
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
