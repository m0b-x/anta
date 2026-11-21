@Timeout(Duration(seconds: 250))
library;

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/guide_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/guide_book.dart';
import 'package:anta/models/sync_guide_content.dart';
import 'package:anta/pages/guide_topic_page.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/settings_section_list.dart';

import '../database/support/db_test_support.dart';
import 'support/guide_try_card_robot.dart';

/// The sync book's `event` card (`docs/guide-hub-roadmap.md` §11.4), on its
/// page: each step done by doing it and by nothing else, steps done out of
/// order never asked for again, the real read sheet on Sam's phone and its
/// copy's report, un-sharing emptying Sam's day, a landing that closes
/// Sam's open sheet, one sheet per double tap, a card that keeps what she
/// did when scrolled away, a page that goes mid-beat or is handed another
/// topic, and a change of language.
///
/// The beat is a timer: every tap moves the clock one frame and the beat is
/// pumped by its own length, never settled past.
void main() {
  final en = AppLocalizationsEn();
  final partner = en.syncGuideDemoPartner;
  final shareWith = en.shareWithPartner(partner);
  late AppDatabase db;

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

  String shareLine() => en.syncGuideCoachEventShare(shareWith);
  String lookLine() => en.syncGuideCoachEventLook(partner);
  String openLine() => en.syncGuideCoachEventOpen;
  String unshareLine() => en.syncGuideCoachEventUnshare(shareWith);
  String report() => en.syncGuideReportEventCopy(partner);

  Finder byId(String suffix) =>
      find.bySemanticsIdentifier('guide-sync-try-event-$suffix');
  Finder here() => byId('phone-here');
  Finder there() => byId('phone-there');
  Finder share() => byId('share');
  Finder hersRow(String name) => byId('here-$name');
  Finder theirsRow(String name) => byId('there-$name');

  Future<GuideTryCardRobot> open(
    WidgetTester tester, {
    Size size = const Size(412, 915),
    double scale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const GuideTopicPage(
          book: GuideBook.sync,
          topic: SyncGuideTopic.event,
        ),
      ),
    );
    // Nothing is in flight yet, so the page may settle.
    await tester.pumpAndSettle();
    return GuideTryCardRobot.book(tester, 'sync', 'event');
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await tester.pump();
  }

  Future<void> beat(WidgetTester tester) => tester.pump(GuideMetrics.syncBeat);

  bool switchOn(WidgetTester tester) => tester
      .widget<Switch>(
        find.descendant(of: share(), matching: find.byType(Switch)),
      )
      .value;

  testWidgets('each step is done by doing it, and by nothing else', (
    tester,
  ) async {
    final robot = await open(tester);
    expect(robot.card, findsOneWidget);
    expect(robot.line, shareLine());

    // Looking at Sam's phone before anything was shared is no look.
    await tap(tester, there());
    expect(find.text(en.syncGuideEmptyFromYou), findsOneWidget);
    expect(robot.line, shareLine());
    await tap(tester, here());

    // Two events, and picking the other is no share either. The pick is
    // said on the row's own node, and the pair under the list names it.
    expect(hersRow('lunch'), findsNothing);
    await tap(tester, hersRow('yoga'));
    expect(robot.line, shareLine());
    Tristate selected(String name) => tester
        .getSemantics(hersRow(name))
        .getSemanticsData()
        .flagsCollection
        .isSelected;
    expect(selected('yoga'), Tristate.isTrue);
    expect(selected('dentist'), isNot(Tristate.isTrue));
    // The title row says the pick; the others' titles under it are unseen.
    expect(
      find.bySemanticsLabel(en.calendarGuideDemoEventYoga),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(en.calendarGuideDemoEventDentist),
      findsNothing,
    );
    await tap(tester, hersRow('dentist'));

    await tap(tester, share());
    expect(switchOn(tester), isTrue);
    expect(robot.line, lookLine());

    // On its way: Sam's day is still empty until the beat lands.
    await tap(tester, there());
    expect(find.text(en.syncGuideEmptyFromYou), findsOneWidget);
    expect(robot.line, lookLine());
    await beat(tester);
    expect(find.text(en.syncGuideEmptyFromYou), findsNothing);
    expect(theirsRow('dentist'), findsOneWidget);
    expect(robot.line, openLine());

    await tap(tester, theirsRow('dentist'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.sharedEventSheet),
      findsOneWidget,
    );
    expect(robot.line, unshareLine());
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tap(tester, here());
    await tap(tester, share());
    expect(switchOn(tester), isFalse);
    // Judged on Sam's phone: done once the un-share has left it.
    expect(robot.line, unshareLine());
    await beat(tester);
    expect(robot.line, en.calendarGuideCoachDone);
    expect(robot.canSkip, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('steps done out of order are not asked for again', (
    tester,
  ) async {
    final robot = await open(tester);
    // Shared and taken back within one beat: the share is done, the
    // un-share is not — nothing ever reached Sam's phone to leave it — and
    // Sam's day stays empty.
    await tap(tester, share());
    await tap(tester, share());
    await beat(tester);
    expect(robot.line, lookLine());

    await tap(tester, there());
    expect(find.text(en.syncGuideEmptyFromYou), findsOneWidget);
    expect(robot.line, lookLine());

    // Looking at it while it arrives counts.
    await tap(tester, here());
    await tap(tester, hersRow('yoga'));
    await tap(tester, share());
    await tap(tester, there());
    await beat(tester);
    expect(theirsRow('yoga'), findsOneWidget);
    expect(robot.line, openLine());

    await tap(tester, theirsRow('yoga'));
    await tester.pumpAndSettle();
    // The card still asks for the un-share.
    expect(robot.line, unshareLine());
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Taken back from her phone: it counts once it has left Sam's.
    await tap(tester, here());
    await tap(tester, share());
    await beat(tester);
    expect(robot.line, en.calendarGuideCoachDone);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    "the read sheet opens from Sam's phone and its copy makes the report",
    (tester) async {
      final robot = await open(tester);
      await tap(tester, share());
      await beat(tester);
      await tap(tester, there());
      await tap(tester, theirsRow('dentist'));
      await tester.pumpAndSettle();

      final sheet = find.bySemanticsIdentifier(SemanticsIds.sharedEventSheet);
      expect(sheet, findsOneWidget);
      // From her, in words of the guide's own; no alerts, no note (D56).
      expect(
        find.text(en.shareFromPartner(en.syncGuideDemoYou)),
        findsOneWidget,
      );
      expect(
        find.text(en.syncGuideSharedEventCaption(partner)),
        findsOneWidget,
      );
      // One clock for the stage and the sheet.
      expect(find.text('9:00 AM – 9:45 AM'), findsWidgets);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.sharedEventAddAlert),
        findsNothing,
      );
      expect(find.text(en.sharedEventYours), findsNothing);
      expect(
        find.bySemanticsIdentifier(SemanticsIds.sharedEventNote),
        findsNothing,
      );

      await tester.tap(
        find.bySemanticsIdentifier(SemanticsIds.sharedEventCopy),
      );
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(robot.line, report());
      // The page is still the guide's, and Sam's day is as it was.
      expect(robot.card, findsOneWidget);
      expect(theirsRow('dentist'), findsOneWidget);
      expect(robot.lineCandidates, contains(report()));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets("un-sharing empties Sam's phone after the beat", (tester) async {
    await open(tester);
    await tap(tester, share());
    await beat(tester);
    await tap(tester, there());
    expect(theirsRow('dentist'), findsOneWidget);

    await tap(tester, here());
    await tap(tester, share());
    await tap(tester, there());
    // Still there while the change travels.
    expect(theirsRow('dentist'), findsOneWidget);
    await beat(tester);
    expect(theirsRow('dentist'), findsNothing);
    expect(find.text(en.syncGuideEmptyFromYou), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a card scrolled away and back keeps its state', (tester) async {
    final robot = await open(tester, size: const Size(360, 780), scale: 2.0);
    await tap(tester, hersRow('yoga'));
    await tap(tester, share());
    await beat(tester);
    expect(robot.line, lookLine());

    final list = find
        .descendant(
          of: find.byType(SettingsSectionList),
          matching: find.byType(Scrollable),
        )
        .first;
    final position = tester.state<ScrollableState>(list).position;
    position.jumpTo(position.maxScrollExtent);
    await tester.pump();
    expect(robot.card, findsNothing, reason: 'the card left the list');

    position.jumpTo(0);
    await tester.pump();
    expect(robot.line, lookLine());
    expect(switchOn(tester), isTrue);
    await tap(tester, there());
    expect(theirsRow('yoga'), findsOneWidget);
    expect(theirsRow('dentist'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a landing that takes the event away closes Sam's sheet", (
    tester,
  ) async {
    final robot = await open(tester);
    await tap(tester, share());
    await beat(tester);
    // Taken back, and Sam opens it while the change travels.
    await tap(tester, share());
    await tap(tester, there());
    await tap(tester, theirsRow('dentist'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final sheet = find.bySemanticsIdentifier(SemanticsIds.sharedEventSheet);
    expect(sheet, findsOneWidget);
    await beat(tester);
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(theirsRow('dentist'), findsNothing);
    expect(robot.line, en.calendarGuideCoachDone);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a double tap opens Sam's sheet once", (tester) async {
    await open(tester);
    await tap(tester, share());
    await beat(tester);
    await tap(tester, there());
    // Two taps before a frame: a finger's second lands on the sheet's
    // barrier once it is laid out, so the row's handler is called twice.
    final row = tester.widget<InkWell>(
      find
          .descendant(of: theirsRow('dentist'), matching: find.byType(InkWell))
          .first,
    );
    row.onTap!();
    row.onTap!();
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.sharedEventSheet),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsIdentifier(SemanticsIds.sharedEventSheet),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the page goes mid-beat and nothing throws', (tester) async {
    await open(tester);
    await tap(tester, share());
    await tester.pump(GuideMetrics.syncBeat ~/ 2);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(GuideMetrics.syncBeat * 2);
    expect(tester.takeException(), isNull);
  });

  /// The page in place, so a second pump hands the same page another topic
  /// or language rather than building a new one.
  Widget page({
    Locale locale = const Locale('en'),
    SyncGuideTopic topic = SyncGuideTopic.event,
  }) => MaterialApp(
    theme: AppTheme.light(),
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: GuideTopicPage(book: GuideBook.sync, topic: topic),
  );

  Future<GuideTryCardRobot> openInPlace(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    return GuideTryCardRobot.book(tester, 'sync', 'event');
  }

  testWidgets('the page handed another topic mid-beat drops the old card', (
    tester,
  ) async {
    await openInPlace(tester);
    await tap(tester, share());
    await tester.pump(GuideMetrics.syncBeat ~/ 2);
    await tester.pumpWidget(page(topic: SyncGuideTopic.category));
    await tester.pump();
    // The old demo goes after the frame; its beat has nothing to land on.
    await tester.pump(GuideMetrics.syncBeat * 2);
    expect(tester.takeException(), isNull);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.guideBookTry('sync', 'event')),
      findsNothing,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.guideBookTry('sync', 'category')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a change of language resizes the coach line for it', (
    tester,
  ) async {
    final robot = await openInPlace(tester);
    expect(robot.lineCandidates, contains(shareLine()));
    final de = lookupAppLocalizations(const Locale('de'));
    final deLine = de.syncGuideCoachEventShare(
      de.shareWithPartner(de.syncGuideDemoPartner),
    );
    expect(robot.lineCandidates, isNot(contains(deLine)));

    await tester.pumpWidget(page(locale: const Locale('de')));
    await tester.pumpAndSettle();
    expect(robot.lineCandidates, contains(deLine));
    expect(robot.lineCandidates, isNot(contains(shareLine())));
    expect(robot.line, deLine);
    await tester.pumpWidget(const SizedBox());
  });
}
