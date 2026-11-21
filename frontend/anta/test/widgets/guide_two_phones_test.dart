@Timeout(Duration(seconds: 250))
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_bar_metrics.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/guide_metrics.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_guide_content.dart';
import 'package:anta/models/guide_share_world.dart';
import 'package:anta/models/sync_guide_tries.dart';
import 'package:anta/widgets/calendar_guide_try_card.dart';
import 'package:anta/widgets/form_rows.dart';
import 'package:anta/widgets/guide_sync_try_alerts.dart';
import 'package:anta/widgets/guide_sync_try_category.dart';
import 'package:anta/widgets/guide_sync_try_conflict.dart';
import 'package:anta/widgets/guide_sync_try_event.dart';
import 'package:anta/widgets/guide_sync_try_folder.dart';
import 'package:anta/widgets/guide_sync_try_look.dart';
import 'package:anta/widgets/guide_sync_try_offline.dart';
import 'package:anta/widgets/guide_sync_try_pair.dart';
import 'package:anta/widgets/guide_sync_try_stop.dart';
import 'package:anta/widgets/guide_sync_try_sync.dart';
import 'package:anta/widgets/guide_two_phones.dart';

import '../goldens/support/golden_fonts.dart';
import 'support/guide_guidelines.dart';
import 'support/guide_share_card_harness.dart';

/// The two-phone stage (`docs/guide-hub-roadmap.md` §11.3, §11.8 A–G, L):
/// the flip and its dot, the phone's one height whichever phone is shown,
/// the long locales at 2.0, and the guides' guidelines — on the event card,
/// the first stage built on it, drawn in a card of its own.
void main() {
  late GuideSyncEventDemo demo;

  setUpAll(loadGoldenFonts);

  setUp(() {
    demo = GuideSyncEventDemo(
      SyncGuideTries.event,
      now: () => DateTime(2026, 11, 26),
    );
  });

  tearDown(() => demo.dispose());

  // Finders are made per use: a semantics finder reads the binding, which a
  // suite's main has not yet.
  Finder byId(String suffix) =>
      find.bySemanticsIdentifier('guide-sync-try-event-$suffix');
  Finder here() => byId('phone-here');
  Finder there() => byId('phone-there');
  Finder stage() => find.bySemanticsIdentifier(
    SemanticsIds.guideBookTryStage('sync', 'event'),
  );
  Finder share() => byId('share');

  Future<AppLocalizations> open(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    Size size = const Size(412, 915),
    double scale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final l10n = lookupAppLocalizations(locale);
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.light
            ? AppTheme.light()
            : AppTheme.dark(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(
            children: [
              CalendarGuideTryCard(
                slug: 'event',
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

  /// A tap as a finger makes it, the clock moved one frame: the beat is a
  /// timer, so nothing here settles past it.
  Future<void> tap(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pump();
    await tester.tap(target);
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(GuideMetrics.syncBeat);
  }

  testWidgets('the flip shows the phone it selects', (tester) async {
    final l10n = await open(tester);
    final button = find.byType(SegmentedButton<GuidePhone>);
    expect(demo.phone, GuidePhone.here);
    expect(tester.widget<SegmentedButton<GuidePhone>>(button).selected, {
      GuidePhone.here,
    });
    expect(share(), findsOneWidget);

    await tap(tester, there());
    expect(demo.phone, GuidePhone.there);
    expect(tester.widget<SegmentedButton<GuidePhone>>(button).selected, {
      GuidePhone.there,
    });
    // Sam's empty day, and no share switch: it is her phone's.
    expect(find.text(l10n.syncGuideEmptyFromYou), findsOneWidget);
    expect(share(), findsNothing);

    await tap(tester, here());
    expect(demo.phone, GuidePhone.here);
    expect(share(), findsOneWidget);
    await finish(tester);
  });

  testWidgets('the dot rings, fills and clears without moving the label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final l10n = await open(tester);
    final label = l10n.syncGuidePhoneTheirs(l10n.syncGuideDemoPartner);
    final labelText = find.text(label);
    final rest = tester.getRect(labelText);

    await tap(tester, share());
    expect(demo.dotOf(GuidePhone.there), GuideFlipDot.ring);
    expect(demo.dotOf(GuidePhone.here), GuideFlipDot.none);
    expect(
      find.bySemanticsLabel(l10n.syncGuidePhoneSyncing(label)),
      findsOneWidget,
    );
    expect(tester.getRect(labelText), rest);

    await tester.pump(GuideMetrics.syncBeat);
    expect(demo.dotOf(GuidePhone.there), GuideFlipDot.filled);
    expect(
      find.bySemanticsLabel(l10n.syncGuidePhoneChanged(label)),
      findsOneWidget,
    );
    expect(tester.getRect(labelText), rest);

    // Looking clears it; the phone in view never wears one.
    await tap(tester, there());
    expect(demo.dotOf(GuidePhone.there), GuideFlipDot.none);
    expect(demo.dotOf(GuidePhone.here), GuideFlipDot.none);
    expect(find.bySemanticsLabel(label), findsOneWidget);
    expect(tester.getRect(labelText), rest);
    handle.dispose();
    await finish(tester);
  });

  testWidgets('a share taken back within the beat leaves no dot', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, share());
    expect(demo.dotOf(GuidePhone.there), GuideFlipDot.ring);
    await tap(tester, share());
    // Nothing travels any more: no ring, and nothing lands to fill it.
    expect(demo.dotOf(GuidePhone.there), GuideFlipDot.none);
    await tester.pump(GuideMetrics.syncBeat);
    expect(demo.dotOf(GuidePhone.there), GuideFlipDot.none);
    await finish(tester);
  });

  testWidgets('each bar says whose phone it is, seen and spoken', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final l10n = await open(tester);
    final yours = l10n.syncGuidePhoneBar(
      l10n.syncGuidePhoneYours,
      l10n.calendar,
    );
    final sams = l10n.syncGuidePhoneBar(
      l10n.syncGuidePhoneTheirs(l10n.syncGuideDemoPartner),
      l10n.calendar,
    );
    expect(yours, 'Your phone · Calendar');
    expect(find.bySemanticsLabel(yours), findsOneWidget);
    await tap(tester, there());
    expect(find.bySemanticsLabel(sams), findsOneWidget);
    expect(find.bySemanticsLabel(yours), findsNothing);
    handle.dispose();
    await finish(tester);
  });

  testWidgets("Sam's mark is his initial, never the from-you face", (
    tester,
  ) async {
    final l10n = await open(tester);
    // The bar in view: the template's bars stand unseen before it.
    Finder inBar(Finder matching) => find.descendant(
      of: find.byType(GuidePhoneBar).last,
      matching: matching,
    );
    final initial = l10n.syncGuideDemoPartner.characters.first;
    expect(inBar(find.byIcon(Icons.smartphone_rounded)), findsOneWidget);
    expect(inBar(find.text(initial)), findsNothing);

    await tap(tester, share());
    await tester.pump(GuideMetrics.syncBeat);
    await tap(tester, there());
    expect(inBar(find.text(initial)), findsOneWidget);
    // The person glyph is the from-you mark's alone (the folder card's suite
    // sees both on one phone).
    expect(inBar(find.byIcon(Icons.person_rounded)), findsNothing);
    await finish(tester);
  });

  testWidgets('a wrapped flip label keeps its dot beside the word', (
    tester,
  ) async {
    // On the small phone: at 412 the Romanian label still fits one line.
    final l10n = await open(
      tester,
      locale: const Locale('ro'),
      size: const Size(360, 780),
      scale: 1.3,
    );
    await tap(tester, share());
    final label = l10n.syncGuidePhoneTheirs(l10n.syncGuideDemoPartner);
    final text = find.text(label);
    // Taller than her own label's one line: it wraps.
    expect(
      tester.getSize(text).height,
      greaterThan(tester.getSize(find.text(l10n.syncGuidePhoneYours)).height),
      reason: 'the label wraps',
    );
    final textRect = tester.getRect(text);
    final dot = tester.getRect(
      find.descendant(
        of: find.ancestor(of: text, matching: find.byType(Row)).first,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is SizedBox &&
              widget.width == GuideMetrics.flipDotSize &&
              widget.height == GuideMetrics.flipDotSize,
        ),
      ),
    );
    expect(
      dot.left - textRect.right,
      moreOrLessEquals(GuideMetrics.flipDotGap, epsilon: 0.5),
    );
    await finish(tester);
  });

  group('every event shared, the tallest state, gives the stage one rect', () {
    for (final size in const [Size(360, 780), Size(412, 915)]) {
      for (final scale in const [1.0, 2.0]) {
        testWidgets('${size.width.toInt()}×${size.height.toInt()} at $scale', (
          tester,
        ) async {
          await open(tester, size: size, scale: scale);
          // From the card's top-left: bringing a row into view scrolls the
          // list, which moves the card, never the stage inside it.
          Rect inCard() => tester
              .getRect(stage())
              .shift(-tester.getTopLeft(find.byType(CalendarGuideTryCard)));
          final rest = inCard();
          await tap(tester, share());
          await tap(tester, byId('here-yoga'));
          await tap(tester, share());
          await tester.pump(GuideMetrics.syncBeat);
          expect(inCard(), rest, reason: 'hers, all shared');
          await tap(tester, there());
          expect(demo.world.theirs, hasLength(demo.world.events.length));
          expect(inCard(), rest, reason: "Sam's, all shared");
          await finish(tester);
        });
      }
    }
  });

  testWidgets('a change that lands in view earns no dot', (tester) async {
    await open(tester);
    await tap(tester, share());
    await tap(tester, there());
    expect(demo.dotOf(GuidePhone.there), GuideFlipDot.none);
    await tester.pump(GuideMetrics.syncBeat);
    expect(demo.dotOf(GuidePhone.there), GuideFlipDot.none);
    expect(demo.world.theirs, hasLength(1));
    await finish(tester);
  });

  group('both phones give the stage one rect', () {
    for (final size in const [Size(360, 780), Size(412, 915)]) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('${size.width.toInt()}×${size.height.toInt()} at $scale', (
          tester,
        ) async {
          await open(tester, size: size, scale: scale);
          final hers = tester.getRect(stage());

          await tap(tester, there());
          expect(tester.getRect(stage()), hers, reason: "Sam's, empty");

          await tap(tester, here());
          await tap(tester, share());
          await tester.pump(GuideMetrics.syncBeat);
          expect(tester.getRect(stage()), hers, reason: 'hers, shared');

          await tap(tester, there());
          expect(demo.world.theirs, hasLength(1));
          expect(tester.getRect(stage()), hers, reason: "Sam's, one event");
          await finish(tester);
        });
      }
    }
  });

  group('no overflow and no clipped text at 2.0', () {
    for (final locale in const [Locale('en'), Locale('de'), Locale('ro')]) {
      for (final brightness in Brightness.values) {
        testWidgets('${locale.languageCode} ${brightness.name}', (
          tester,
        ) async {
          await open(
            tester,
            locale: locale,
            brightness: brightness,
            size: const Size(360, 780),
            scale: 2.0,
          );
          void expectClean(String state) {
            expect(tester.takeException(), isNull, reason: state);
            final paragraphs = tester.renderObjectList<RenderParagraph>(
              find.descendant(
                of: find.byType(CalendarGuideTryCard),
                matching: find.byType(RichText),
              ),
            );
            for (final paragraph in paragraphs) {
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

          expectClean('hers');
          await tap(tester, share());
          await tester.pump(GuideMetrics.syncBeat);
          expectClean('hers, shared, dot');
          await tap(tester, there());
          expectClean("Sam's");
          await finish(tester);
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
        await open(tester, brightness: brightness);
        final viewport = tester.getRect(find.byType(ListView));
        Future<void> meetsAll(String state) async {
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

        await meetsAll('hers');
        await tap(tester, share());
        await tester.pump(GuideMetrics.syncBeat);
        await tester.pumpAndSettle();
        await meetsAll('hers, shared, the dot filled');
        await tap(tester, there());
        await tester.pumpAndSettle();
        await meetsAll("Sam's");
        handle.dispose();
        await finish(tester);
      });
    }
  });

  group('the frame, on a throwaway card', () {
    const harness = GuideShareCardHarness('frame');

    testWidgets('two sends that cross each end as their phone saw them', (
      tester,
    ) async {
      final frame = _FrameDemo();
      addTearDown(frame.dispose);
      await harness.openCard(tester, frame);
      frame.sendTo(GuidePhone.there);
      frame.select(GuidePhone.there);
      frame.sendTo(GuidePhone.here);
      await tester.pump();
      expect(frame.dotOf(GuidePhone.here), GuideFlipDot.ring);
      frame.select(GuidePhone.here);
      await tester.pump();
      // Both are still on their way; the phone in view wears no dot.
      expect(frame.dotOf(GuidePhone.there), GuideFlipDot.ring);
      expect(frame.dotOf(GuidePhone.here), GuideFlipDot.none);
      await harness.beat(tester);
      // Both landed: no ring stands, and only the phone not in view fills.
      expect(frame.dotOf(GuidePhone.there), GuideFlipDot.filled);
      expect(frame.dotOf(GuidePhone.here), GuideFlipDot.none);
      await harness.finish(tester);
    });

    testWidgets('the bar keeps a trailing control in a 48 dp slot', (
      tester,
    ) async {
      final frame = _FrameDemo();
      addTearDown(frame.dispose);
      await harness.openCard(tester, frame);
      final stage = harness.stageInCard(tester);
      final toggle = find.byTooltip(_FrameDemo.toggleTooltip);
      expect(toggle, findsOneWidget);
      final bar = tester.getRect(find.byType(GuidePhoneBar).last);
      expect(tester.getSize(toggle), const Size.square(48));
      // Flush with the bar's end.
      expect(tester.getRect(toggle).right, bar.right);
      await harness.tap(tester, toggle);
      expect(frame.toggled, 1);
      // The other phone has no control there and the stage still holds.
      await harness.tap(tester, harness.there());
      expect(toggle, findsNothing);
      expect(harness.stageInCard(tester), stage);
      await harness.finish(tester);
    });

    testWidgets('a card with one phone draws no flip', (tester) async {
      final frame = _FrameDemo(onePhone: true);
      addTearDown(frame.dispose);
      final l10n = await harness.openCard(tester, frame);
      expect(find.byType(SegmentedButton<GuidePhone>), findsNothing);
      expect(harness.stage(), findsOneWidget);
      // Her bar, read once: the unseen template is no node.
      expect(
        find.bySemanticsLabel(
          l10n.syncGuidePhoneBar(l10n.syncGuidePhoneYours, l10n.calendar),
        ),
        findsOneWidget,
      );
      await harness.finish(tester);
    });

    testWidgets('a disposed card takes a late settle without a redraw', (
      tester,
    ) async {
      final frame = _FrameDemo();
      await harness.openCard(tester, frame);
      await tester.pumpWidget(const SizedBox());
      frame.dispose();
      // A sheet's answer after the page went: dropped, not thrown.
      frame.settleQuietly();
      frame.settleByHer();
      expect(tester.takeException(), isNull);
    });
  });

  group('the coach line and the stage share a screen', () {
    final cards = <String, GuideTwoPhonesDemo Function()>{
      'event': () => GuideSyncEventDemo(SyncGuideTries.event, now: _day),
      'category': () =>
          GuideSyncCategoryDemo(SyncGuideTries.category, now: _day),
      'folder': () => GuideSyncFolderDemo(SyncGuideTries.folder, now: _day),
      'stop': () => GuideSyncStopDemo(SyncGuideTries.stop, now: _day),
      'look': () => GuideSyncLookDemo(SyncGuideTries.look, now: _day),
      'alerts': () => GuideSyncAlertsDemo(SyncGuideTries.alerts, now: _day),
      'sync': () => GuideSyncSyncDemo(SyncGuideTries.sync, now: _day),
      'offline': () => GuideSyncOfflineDemo(SyncGuideTries.offline, now: _day),
      'conflict': () =>
          GuideSyncConflictDemo(SyncGuideTries.conflict, now: _day),
      'pair': () => GuideSyncPairDemo(SyncGuideTries.pair, now: _day),
    };
    for (final MapEntry(key: slug, value: make) in cards.entries) {
      testWidgets('$slug: en at 1.0 on 360 × 780; de at 2.0 printed', (
        tester,
      ) async {
        final harness = GuideShareCardHarness(slug);
        const size = Size(360, 780);
        final card = find.byType(CalendarGuideTryCard);
        Rect span() {
          final line = tester.getRect(
            find
                .descendant(of: card, matching: find.byType(FormCaptionSlot))
                .first,
          );
          return Rect.fromLTRB(
            line.left,
            line.top,
            line.right,
            tester.getRect(harness.stage()).bottom,
          );
        }

        final en = make();
        addTearDown(en.dispose);
        await harness.openCard(tester, en, size: size);
        final fit = span().height;
        expect(
          fit,
          lessThanOrEqualTo(size.height - AppBarMetrics.toolbarHeight),
          reason: 'the coach line to the stage, under the app bar',
        );

        // For the record, not a pin: the card's height and the span from
        // the coach line to the stage's bottom at 2.0, in English (the
        // earlier record's measure) and in German (the longest).
        String at2(String language) =>
            '$language 2.0 card '
            '${tester.getSize(card).height.toStringAsFixed(0)}, span '
            '${span().height.toStringAsFixed(0)}';
        final big = make();
        addTearDown(big.dispose);
        await harness.openCard(tester, big, size: size, scale: 2.0);
        final en2 = at2('en');
        final de = make();
        addTearDown(de.dispose);
        await harness.openCard(
          tester,
          de,
          locale: const Locale('de'),
          size: size,
          scale: 2.0,
        );
        debugPrint(
          '[measure] $slug: en 1.0 span ${fit.toStringAsFixed(0)}; '
          '$en2; ${at2('de')}',
        );
        await harness.finish(tester);
      });
    }
  });
}

DateTime _day() => DateTime(2026, 11, 26);

/// A two-phone card of no lesson, for what the frame does on its own: its
/// changes travel whichever way it is told, a trailing control on her
/// phone's bar, and the one-phone form.
class _FrameDemo extends GuideTwoPhonesDemo {
  _FrameDemo({this.onePhone = false}) : super(_spec, book: 'sync');

  static const GuideCardSpec _spec = GuideCardSpec('frame', [
    GuideShareStep('never', _line, _never),
  ], _line);

  static String _line(AppLocalizations l10n) => l10n.syncGuideDemoPartner;
  static bool _never(GuideShareWorld world) => false;

  static const String toggleTooltip = 'Toggle';

  @override
  final bool onePhone;

  final Set<GuidePhone> _travelling = {};
  int toggled = 0;

  @override
  bool inFlightTo(GuidePhone phone) => _travelling.contains(phone);

  @override
  void land() => _travelling.clear();

  void sendTo(GuidePhone phone) {
    _travelling.add(phone);
    send(phone);
    settle();
  }

  void settleQuietly() => settle(byHer: false);
  void settleByHer() => settle();

  @override
  GuideShareWorld seedWorld(AppLocalizations l10n) =>
      GuideShareWorld(day: DateTime.utc(2026, 11, 26), events: const []);

  @override
  String phoneLabel(AppLocalizations l10n, GuidePhone phone) => switch (phone) {
    GuidePhone.here => l10n.syncGuidePhoneYours,
    GuidePhone.there => l10n.syncGuidePhoneTheirs(l10n.syncGuideDemoPartner),
  };

  @override
  GuidePhoneView buildPhone(BuildContext context, GuidePhone phone) {
    final l10n = AppLocalizations.of(context)!;
    return GuidePhoneView(
      mark: const SizedBox.shrink(),
      area: l10n.calendar,
      list: null,
      template: const SizedBox(height: 120),
      empty: l10n.syncGuideEmptyFromYou,
      trailing: phone == GuidePhone.here
          ? IconButton(
              icon: const Icon(Icons.airplanemode_active_rounded),
              tooltip: toggleTooltip,
              onPressed: () => toggled++,
            )
          : null,
    );
  }
}
