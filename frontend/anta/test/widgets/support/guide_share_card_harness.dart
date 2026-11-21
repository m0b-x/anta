import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/guide_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/guide_book.dart';
import 'package:anta/models/sync_guide_content.dart';
import 'package:anta/pages/guide_topic_page.dart';
import 'package:anta/widgets/calendar_guide_try_card.dart';

import 'guide_guidelines.dart';
import 'guide_try_card_robot.dart';

/// The sharing cards' suites (`docs/guide-hub-roadmap.md` §11.4), one card
/// a file: the card on its page for its steps, and the card alone — as
/// `guide_two_phones_test.dart` draws the event card — for the matrix of
/// sizes, scales, languages and themes, which needs no database.
///
/// The beat is a timer: every tap moves the clock one frame and the beat is
/// pumped by its own length, never settled past.
class GuideShareCardHarness {
  const GuideShareCardHarness(this.slug);

  final String slug;

  Finder byId(String suffix) =>
      find.bySemanticsIdentifier('guide-sync-try-$slug-$suffix');
  Finder here() => byId('phone-here');
  Finder there() => byId('phone-there');
  Finder stage() =>
      find.bySemanticsIdentifier(SemanticsIds.guideBookTryStage('sync', slug));

  /// The stage's rect from its card's top-left: a stage taller than the
  /// screen scrolls the list when the flip is brought into view, which moves
  /// the card, never the stage inside it.
  Rect stageInCard(WidgetTester tester) => tester
      .getRect(stage())
      .shift(-tester.getTopLeft(find.byType(CalendarGuideTryCard)));

  /// The card on its page, through `GuideTopicPage`. The caller opens the
  /// settings the page reads.
  Future<GuideTryCardRobot> openPage(
    WidgetTester tester,
    SyncGuideTopic topic, {
    Size size = const Size(412, 915),
  }) async {
    _surface(tester, size);
    await tester.pumpWidget(
      _app(
        home: GuideTopicPage(book: GuideBook.sync, topic: topic),
      ),
    );
    // Nothing is in flight yet, so the page may settle.
    await tester.pumpAndSettle();
    return GuideTryCardRobot.book(tester, 'sync', slug);
  }

  /// [demo] in a card of its own.
  Future<AppLocalizations> openCard(
    WidgetTester tester,
    GuideCardDemo demo, {
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    Size size = const Size(412, 915),
    double scale = 1.0,
  }) async {
    _surface(tester, size);
    final l10n = lookupAppLocalizations(locale);
    await tester.pumpWidget(
      _app(
        locale: locale,
        brightness: brightness,
        scale: scale,
        home: Scaffold(
          body: ListView(
            children: [
              CalendarGuideTryCard(
                slug: slug,
                demo: demo,
                candidates: demo.candidates(l10n),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    return l10n;
  }

  void _surface(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Widget _app({
    required Widget home,
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    double scale = 1.0,
  }) => MaterialApp(
    theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: home,
  );

  /// A tap as a finger makes it, the clock moved one frame.
  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await tester.pump();
  }

  /// A menu or a sheet opened by [tap] has finished sliding in, the beat's
  /// timer left where it is.
  Future<void> settleRoute(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> beat(WidgetTester tester) => tester.pump(GuideMetrics.syncBeat);

  /// The page goes, and a beat still under way has nothing left to land on.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(GuideMetrics.syncBeat);
  }

  /// No overflow and no clipped or cut text anywhere in the card.
  void expectClean(WidgetTester tester, String state) {
    expect(tester.takeException(), isNull, reason: state);
    final paragraphs = tester.renderObjectList<RenderParagraph>(
      find.descendant(
        of: find.byType(CalendarGuideTryCard),
        matching: find.byType(RichText),
      ),
    );
    for (final paragraph in paragraphs) {
      if (!paragraph.attached || paragraph.size.isEmpty) continue;
      if (_unseen(paragraph)) continue;
      final text = '$state: ${paragraph.text.toPlainText()}';
      expect(paragraph.didExceedMaxLines, isFalse, reason: text);
      expect(
        paragraph.size.height,
        moreOrLessEquals(
          paragraph.getMaxIntrinsicHeight(paragraph.size.width),
          epsilon: 0.01,
        ),
        reason: text,
      );
    }
  }

  /// [paragraph] is laid out unseen — a template or a slot's sizing line
  /// under `Opacity(0)` — so no reader sees it cut: the Sync section's
  /// status row sizes its details by one line of "Never synced" held to one
  /// line on purpose.
  static bool _unseen(RenderObject paragraph) {
    for (var node = paragraph.parent; node != null; node = node.parent) {
      if (node is RenderOpacity && node.opacity == 0) return true;
    }
    return false;
  }

  /// The guides' tap-target and contrast guidelines over the card.
  Future<void> meetsGuidelines(WidgetTester tester, String state) async {
    final viewport = tester.getRect(find.byType(ListView).first);
    await expectLater(
      tester,
      meetsGuideline(GuideTapTargetGuideline.of(tester)),
      reason: state,
    );
    await expectLater(
      tester,
      meetsGuideline(GuideLabeledTapTargetGuideline.of(tester)),
      reason: state,
    );
    await expectLater(
      tester,
      meetsGuideline(GuideTextContrastGuideline(viewport: viewport)),
      reason: state,
    );
  }
}
