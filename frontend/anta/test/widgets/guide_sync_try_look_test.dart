@Timeout(Duration(seconds: 250))
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_bar_metrics.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/guide_book.dart';
import 'package:anta/models/sync_guide_content.dart';
import 'package:anta/pages/guide_topic_page.dart';
import 'package:anta/models/sync_guide_tries.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/widgets/event_avatar.dart';
import 'package:anta/widgets/guide_sync_try_look.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import 'support/guide_share_card_harness.dart';

/// The sync book's `look` card (`docs/guide-hub-roadmap.md` §11.4): her
/// phone alone, no flip; the Sharing page's own look rows redraw Sam's
/// events — outlined, with Sam's face, like hers — and "Mark what you
/// share" puts the sign on her shared event; each step done by doing it
/// and by nothing else; one stage height in every state; the languages,
/// themes and guidelines.
void main() {
  final en = AppLocalizationsEn();
  const card = GuideShareCardHarness('look');
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

  String avatarLine() =>
      en.syncGuideCoachLookAvatar(en.shareEventLook, en.shareLookAvatar);
  String plainLine() => en.syncGuideCoachChooseNext(en.shareLookPlain);
  String markLine() => en.syncGuideCoachLookMark(en.shareMarkMine);

  Finder eventLook(String look) => card.byId('events-$look');
  Finder noteLook(String look) => card.byId('notes-$look');
  Finder markMine() => card.byId('mark-mine');
  Finder row(String name) => card.byId('row-$name');

  EventAvatar avatarOf(WidgetTester tester, String name) =>
      tester.widget<EventAvatar>(
        find.descendant(of: row(name), matching: find.byType(EventAvatar)),
      );

  /// Sam's row as the real day list draws it under each look.
  void expectSams(
    WidgetTester tester, {
    required bool outlined,
    required bool face,
  }) {
    for (final name in ['lunch']) {
      final avatar = avatarOf(tester, name);
      expect(avatar.outlined, outlined, reason: name);
      expect(avatar.badge?.isMine ?? false, isFalse, reason: name);
      expect(avatar.badge != null, face, reason: name);
      if (face) {
        expect(avatar.badge!.partner?.displayName, en.syncGuideDemoPartner);
      }
      expect(
        avatar.semanticsLabel,
        en.shareMarkPartnerLabel(en.syncGuideDemoPartner),
        reason: 'said in every look, $name',
      );
    }
  }

  testWidgets('her phone alone: no flip, her bar, her day and the page\'s '
      'rows', (tester) async {
    final robot = await card.openPage(tester, SyncGuideTopic.look);
    expect(robot.card, findsOneWidget);
    expect(card.stage(), findsOneWidget);
    expect(card.here(), findsNothing);
    expect(card.there(), findsNothing);
    // Drawn twice: the bar in view and its unseen twin that sizes the stage.
    expect(
      find.text(en.syncGuidePhoneBar(en.syncGuidePhoneYours, en.calendar)),
      findsNWidgets(2),
    );
    for (final name in ['dentist', 'lunch']) {
      expect(row(name), findsOneWidget, reason: name);
    }
    // Two events show both effects: hers shared, and one of Sam's.
    for (final name in ['pilates', 'piano']) {
      expect(row(name), findsNothing, reason: name);
    }
    expect(find.text(en.shareLookSection), findsOneWidget);
    expect(eventLook('outlined'), findsOneWidget);
    expect(markMine(), findsOneWidget);
    // The stage holds no notes, so the notes' row is left off it.
    expect(noteLook('avatar'), findsNothing);
    expect(find.text(en.shareNoteLook), findsNothing);
    await card.finish(tester);
  });

  testWidgets('each step is done by doing it, and by nothing else', (
    tester,
  ) async {
    final robot = await card.openPage(tester, SyncGuideTopic.look);
    // A fresh install's looks, the sign off.
    expect(robot.line, avatarLine());
    expectSams(tester, outlined: true, face: false);
    expect(avatarOf(tester, 'dentist').badge, isNull);
    expect(
      avatarOf(tester, 'dentist').semanticsLabel,
      en.shareMarkMineLabel(en.syncGuideDemoPartner),
    );

    // The look already chosen teaches nothing here.
    await card.tap(tester, eventLook('outlined'));
    expect(robot.line, avatarLine());
    expectSams(tester, outlined: true, face: false);

    await card.tap(tester, eventLook('avatar'));
    expect(robot.line, plainLine());
    expectSams(tester, outlined: false, face: true);

    await card.tap(tester, eventLook('plain'));
    expect(robot.line, markLine());
    expectSams(tester, outlined: false, face: false);
    expect(avatarOf(tester, 'dentist').badge, isNull);

    await card.tap(tester, markMine());
    expect(avatarOf(tester, 'dentist').badge, EventAvatarBadge.mine);
    expect(
      avatarOf(tester, 'lunch').badge?.isMine ?? false,
      isFalse,
      reason: "Sam's is never marked hers",
    );
    expect(robot.line, en.calendarGuideCoachDone);

    // Back to the outline: the real rows follow, the card stays done.
    await card.tap(tester, eventLook('outlined'));
    expectSams(tester, outlined: true, face: false);
    expect(robot.line, en.calendarGuideCoachDone);
    await card.finish(tester);
  });

  testWidgets('steps done out of order are not asked for again', (
    tester,
  ) async {
    final robot = await card.openPage(tester, SyncGuideTopic.look);
    await card.tap(tester, markMine());
    expect(robot.line, avatarLine());
    await card.tap(tester, eventLook('plain'));
    expect(robot.line, avatarLine());
    await card.tap(tester, eventLook('avatar'));
    expect(robot.line, en.calendarGuideCoachDone);
    await card.finish(tester);
  });

  // Through the page, where the card is 328 wide, not alone: each step's
  // control and the row it changes share one screen under the bar.
  group('at 2.0 on a small phone, the act and its result share a screen', () {
    for (final locale in const [Locale('de'), Locale('ro')]) {
      testWidgets(locale.languageCode, (tester) async {
        const size = Size(360, 780);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2.0)),
              child: child!,
            ),
            home: GuideTopicPage(
              book: GuideBook.sync,
              topic: SyncGuideTopic.look,
            ),
          ),
        );
        await tester.pumpAndSettle();
        const screen = 780 - AppBarMetrics.toolbarHeight;
        for (final (control, changed) in [
          (card.byId('events'), row('lunch')),
          (markMine(), row('dentist')),
        ]) {
          final a = tester.getRect(control);
          final b = tester.getRect(changed);
          final span = math.max(a.bottom, b.bottom) - math.min(a.top, b.top);
          expect(span, lessThanOrEqualTo(screen), reason: '$control');
        }
        await card.finish(tester);
      });
    }
  });

  group('the card alone', () {
    late GuideSyncLookDemo demo;

    setUp(() {
      demo = GuideSyncLookDemo(
        SyncGuideTries.look,
        now: () => DateTime(2026, 11, 26),
      );
    });

    tearDown(() => demo.dispose());

    group('one stage rect in every state', () {
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
                // The stage outgrows the screen at 2.0, so a tap scrolls
                // the page and the card's offset carries a float's
                // rounding.
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

                await card.tap(tester, eventLook('avatar'));
                same('avatar');
                await card.tap(tester, eventLook('plain'));
                same('like mine');
                await card.tap(tester, markMine());
                same('marked');
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
            card.expectClean(tester, 'outlined');
            await card.tap(tester, eventLook('avatar'));
            card.expectClean(tester, 'avatar');
            await card.tap(tester, markMine());
            card.expectClean(tester, 'marked');
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
          await card.meetsGuidelines(tester, 'outlined');
          await card.tap(tester, eventLook('avatar'));
          await card.tap(tester, markMine());
          await tester.pumpAndSettle();
          await card.meetsGuidelines(tester, 'avatar, marked');
          handle.dispose();
          await card.finish(tester);
        });
      }
    });
  });
}
