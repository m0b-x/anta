@Timeout(Duration(seconds: 250))
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/app_colors.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/controllers/guide_setup_reader.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/utils/settings_search.dart';
import 'package:anta/widgets/guide_setup_card.dart';
import 'package:anta/widgets/settings_section_list.dart';

import '../goldens/support/golden_fonts.dart';

const _signedIn = GuideSetupFacts(
  signedIn: true,
  accountName: 'Alex',
  sync: GuideSetupSync.off,
  paired: false,
  shared: 0,
);
const _syncing = GuideSetupFacts(
  signedIn: true,
  accountName: 'Alex',
  sync: GuideSetupSync.on,
  paired: false,
  shared: 0,
);
const _paired = GuideSetupFacts(
  signedIn: true,
  accountName: 'Alex',
  sync: GuideSetupSync.on,
  paired: true,
  partnerName: 'Maria',
  shared: 0,
);
const _sharing = GuideSetupFacts(
  signedIn: true,
  accountName: 'Alex',
  sync: GuideSetupSync.on,
  paired: true,
  partnerName: 'Maria',
  shared: 3,
);

Finder _section() => find.bySemanticsIdentifier(SemanticsIds.guideSyncSetup);

Finder _row(GuideSetupStep step) =>
    find.bySemanticsIdentifier(SemanticsIds.guideSyncSetupRow(step.name));

/// Whether [element] is laid out unseen — a slot's sizing template.
bool _unseen(Element element) {
  var unseen = false;
  element.visitAncestorElements((ancestor) {
    if (ancestor.widget case Opacity(opacity: 0)) {
      unseen = true;
      return false;
    }
    return true;
  });
  return unseen;
}

/// The words [row] shows, its sizing templates left out.
List<String> _shown(Finder row) => [
  for (final element
      in find.descendant(of: row, matching: find.byType(Text)).evaluate())
    if (!_unseen(element)) (element.widget as Text).data!,
];

/// No laid-out text of the card is cut: every seen paragraph is as tall as
/// its lines need and none ran out of lines.
void _expectNoClippedText(WidgetTester tester) {
  for (final element
      in find
          .descendant(of: _section(), matching: find.byType(RichText))
          .evaluate()) {
    if (_unseen(element)) continue;
    final paragraph = element.renderObject! as RenderParagraph;
    final reason = paragraph.text.toPlainText();
    expect(paragraph.didExceedMaxLines, isFalse, reason: reason);
    expect(
      paragraph.size.height,
      moreOrLessEquals(
        paragraph.getMaxIntrinsicHeight(paragraph.size.width),
        epsilon: 0.01,
      ),
      reason: reason,
    );
  }
}

/// The "Your setup" card on the sync book's hub (`docs/guide-hub-roadmap.md`
/// D48, §11.8 I): the rows in every combination that can occur, their
/// glyphs and captions, where each opens, the line of a build without sync,
/// the first frame before a fact is known, and its geometry across
/// languages, text scales, phones and themes.
void main() {
  setUpAll(loadGoldenFonts);

  late ValueNotifier<GuideSetupFacts> facts;

  /// Every opening asked, by whether it asked for the Sharing page.
  late List<bool> opened;

  setUp(() {
    facts = ValueNotifier(GuideSetupFacts.signedOut);
    opened = [];
  });

  tearDown(() => facts.dispose());

  Future<AppLocalizations> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    double scale = 1.0,
    Size size = const Size(412, 915),
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
          body: Builder(
            builder: (context) => SettingsSectionList(
              query: SettingsQuery.empty,
              sections: [
                guideSetupSection(
                  AppLocalizations.of(context)!,
                  facts,
                  open: (context, {required sharing}) => opened.add(sharing),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return lookupAppLocalizations(locale);
  }

  Finder glyph(GuideSetupStep step, IconData icon) =>
      find.descendant(of: _row(step), matching: find.byIcon(icon));

  void expectRow(
    GuideSetupStep step, {
    required bool done,
    required String title,
    String? caption,
  }) {
    expect(_shown(_row(step)), [title, ?caption], reason: step.name);
    expect(
      glyph(step, Icons.check_circle_rounded),
      done ? findsOneWidget : findsNothing,
      reason: step.name,
    );
    expect(
      glyph(step, Icons.radio_button_unchecked_rounded),
      done ? findsNothing : findsOneWidget,
      reason: step.name,
    );
  }

  testWidgets('nothing done: every step after the account says to sign in '
      'first', (tester) async {
    final en = await pump(tester);
    expect(find.text(en.syncGuideSetupTitle.toUpperCase()), findsOneWidget);
    expectRow(
      GuideSetupStep.account,
      done: false,
      title: en.syncGuideSetupAccountTodo,
    );
    expectRow(
      GuideSetupStep.sync,
      done: false,
      title: en.syncGuideSetupSyncTodo(en.syncThisDatabase),
      caption: en.syncGuideSetupAccountFirst,
    );
    expectRow(
      GuideSetupStep.pair,
      done: false,
      title: en.syncGuideSetupPairTodo,
      caption: en.syncGuideSetupAccountFirst,
    );
    expectRow(
      GuideSetupStep.share,
      done: false,
      title: en.syncGuideSetupShareTodo,
      caption: en.syncGuideSetupAccountFirst,
    );
  });

  testWidgets('signed in only: sharing waits on sync first, pairing on '
      'nothing', (tester) async {
    facts.value = _signedIn;
    final en = await pump(tester);
    expectRow(
      GuideSetupStep.account,
      done: true,
      title: en.syncGuideSetupAccountDone('Alex'),
    );
    expectRow(
      GuideSetupStep.sync,
      done: false,
      title: en.syncGuideSetupSyncTodo(en.syncThisDatabase),
    );
    expectRow(
      GuideSetupStep.pair,
      done: false,
      title: en.syncGuideSetupPairTodo,
    );
    expectRow(
      GuideSetupStep.share,
      done: false,
      title: en.syncGuideSetupShareTodo,
      caption: en.syncGuideSetupSyncFirst,
    );
  });

  testWidgets('syncing: sharing waits on the pair', (tester) async {
    facts.value = _syncing;
    final en = await pump(tester);
    expectRow(
      GuideSetupStep.sync,
      done: true,
      title: en.syncGuideSetupSyncDone,
    );
    expectRow(
      GuideSetupStep.pair,
      done: false,
      title: en.syncGuideSetupPairTodo,
    );
    expectRow(
      GuideSetupStep.share,
      done: false,
      title: en.syncGuideSetupShareTodo,
      caption: en.syncGuideSetupPairFirst,
    );
  });

  testWidgets('paired and syncing, nothing shared: no step comes first', (
    tester,
  ) async {
    facts.value = _paired;
    final en = await pump(tester);
    expectRow(
      GuideSetupStep.pair,
      done: true,
      title: en.syncGuideSetupPairDone('Maria'),
    );
    expectRow(
      GuideSetupStep.share,
      done: false,
      title: en.syncGuideSetupShareTodo,
    );
  });

  testWidgets('a partner with no published name, and an account with '
      'neither name nor address', (tester) async {
    facts.value = const GuideSetupFacts(
      signedIn: true,
      sync: GuideSetupSync.on,
      paired: true,
      shared: 0,
    );
    final en = await pump(tester);
    expectRow(
      GuideSetupStep.account,
      done: true,
      title: en.syncGuideSetupAccountDoneUnnamed,
    );
    expectRow(GuideSetupStep.pair, done: true, title: en.pairingPartnerUnknown);
  });

  testWidgets('sharing three things: every step done, no caption anywhere', (
    tester,
  ) async {
    facts.value = _sharing;
    final en = await pump(tester);
    expectRow(
      GuideSetupStep.account,
      done: true,
      title: en.syncGuideSetupAccountDone('Alex'),
    );
    expectRow(
      GuideSetupStep.sync,
      done: true,
      title: en.syncGuideSetupSyncDone,
    );
    expectRow(
      GuideSetupStep.pair,
      done: true,
      title: en.syncGuideSetupPairDone('Maria'),
    );
    expectRow(
      GuideSetupStep.share,
      done: true,
      title: en.syncGuideSetupShareDone(3),
    );
  });

  testWidgets('each row is one button whose words are its state and its '
      'caption — never colour alone — and where it leads', (tester) async {
    final handle = tester.ensureSemantics();
    final en = await pump(tester);
    expect(
      tester.getSemantics(
        find.descendant(
          of: _row(GuideSetupStep.share),
          matching: find.byType(ListTile),
        ),
      ),
      matchesSemantics(
        label:
            '${en.syncGuideSetupShareTodo}\n${en.syncGuideSetupAccountFirst}',
        hint: en.shareOpensSyncHint,
        isButton: true,
        hasTapAction: true,
        hasFocusAction: true,
        hasSelectedState: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('never dimmed: a step not yet done still opens its screen — '
      'Sync & sharing, and the Sharing page only once paired', (tester) async {
    await pump(tester);
    // Tapped in order, one opening each: Sync & sharing every time.
    for (final step in GuideSetupStep.values) {
      await tester.tap(_row(step));
    }
    expect(opened, [false, false, false, false]);
    for (final tile in tester.widgetList<ListTile>(
      find.descendant(of: _section(), matching: find.byType(ListTile)),
    )) {
      expect(tile.enabled, isTrue);
    }

    opened.clear();
    facts.value = _sharing;
    await tester.pump();
    for (final step in GuideSetupStep.values) {
      await tester.tap(_row(step));
    }
    expect(opened, [false, false, false, true]);
  });

  testWidgets('a build without sync: the one line, no glyph, no tap', (
    tester,
  ) async {
    facts.value = const GuideSetupFacts.unavailable();
    final en = await pump(tester);
    final line = find.bySemanticsIdentifier(
      SemanticsIds.guideSyncSetupRow('unavailable'),
    );
    expect(line, findsOneWidget);
    expect(_shown(line), [en.syncThisDatabaseUnavailable]);
    expect(find.byType(Icon), findsNothing);
    expect(tester.widget<ListTile>(find.byType(ListTile)).onTap, isNull);
    for (final step in GuideSetupStep.values) {
      expect(_row(step), findsNothing);
    }
  });

  testWidgets('before a fact is read its row claims nothing — no glyph, no '
      'words, no tap — and nothing moves when it lands', (tester) async {
    final handle = tester.ensureSemantics();
    facts.value = const GuideSetupFacts(
      signedIn: true,
      accountName: 'Alex',
      paired: true,
      partnerName: 'Maria',
    );
    final en = await pump(tester);
    for (final step in [GuideSetupStep.sync, GuideSetupStep.share]) {
      expect(_shown(_row(step)), isEmpty, reason: step.name);
      expect(
        find.descendant(of: _row(step), matching: find.byType(Icon)),
        findsOneWidget,
        reason: 'the chevron alone',
      );
      final tile = find.descendant(
        of: _row(step),
        matching: find.byType(ListTile),
      );
      expect(tester.widget<ListTile>(tile).onTap, isNull);
      expect(tester.getSemantics(tile).label, isEmpty);
    }
    final rects = {
      for (final step in GuideSetupStep.values)
        step: tester.getRect(_row(step)),
    };
    final card = tester.getRect(_section());

    facts.value = _sharing;
    await tester.pump();
    expectRow(
      GuideSetupStep.share,
      done: true,
      title: en.syncGuideSetupShareDone(3),
    );
    for (final step in GuideSetupStep.values) {
      expect(tester.getRect(_row(step)), rects[step], reason: step.name);
    }
    expect(tester.getRect(_section()), card);
    handle.dispose();
  });

  testWidgets('bound to another account: the sync row says what Sync & '
      'sharing says, never names a "Sync this database" the page does not '
      'draw, and still opens it', (tester) async {
    facts.value = const GuideSetupFacts(
      signedIn: true,
      accountName: 'Alex',
      sync: GuideSetupSync.otherAccount,
      paired: false,
      shared: 0,
    );
    final en = await pump(tester);
    expectRow(
      GuideSetupStep.sync,
      done: false,
      title: en.syncPausedOtherAccount,
    );
    expect(
      _shown(_row(GuideSetupStep.sync)),
      isNot(contains(en.syncGuideSetupSyncTodo(en.syncThisDatabase))),
    );
    // Sync is not off: the share row names the pause, not a switch to turn.
    expectRow(
      GuideSetupStep.share,
      done: false,
      title: en.syncGuideSetupShareTodo,
      caption: en.syncGuideSetupSyncPausedFirst,
    );
    await tester.tap(_row(GuideSetupStep.sync));
    expect(opened, [false]);
  });

  // A name arrives with its fact — a sign-in or a pair made on another
  // screen — and may be any length: the slot holds two title lines from the
  // first frame, and a longer name ends in "…".
  testWidgets('no row changes height, and none drops its chevron, when a '
      'fact lands — a long name and an unbreakable address included', (
    tester,
  ) async {
    const longName = 'Alexandra Popescu';
    const address = 'alexandra.popescu.constantinescu@example.com';
    GuideSetupFacts named(String name, {bool shares = false}) =>
        GuideSetupFacts(
          signedIn: true,
          accountName: name,
          sync: GuideSetupSync.on,
          paired: true,
          partnerName: name,
          shared: shares ? 3 : 0,
        );
    Finder chevrons() => find.descendant(
      of: _section(),
      matching: find.byIcon(Icons.chevron_right_rounded),
    );
    for (final (locale, scale) in [
      (const Locale('en'), 1.0),
      (const Locale('de'), 2.0),
    ]) {
      facts.value = const GuideSetupFacts();
      await pump(
        tester,
        locale: locale,
        scale: scale,
        size: const Size(360, 780),
      );
      final before = {
        for (final step in GuideSetupStep.values)
          step: tester.getRect(_row(step)),
      };
      final chevronCount = chevrons().evaluate().length;
      for (final next in [
        GuideSetupFacts.signedOut,
        _signedIn,
        const GuideSetupFacts(
          signedIn: true,
          accountName: 'Alex',
          sync: GuideSetupSync.otherAccount,
          paired: true,
        ),
        const GuideSetupFacts(
          signedIn: true,
          accountName: 'Alex',
          sync: GuideSetupSync.otherAccount,
          paired: true,
          shared: 0,
        ),
        _syncing,
        _paired,
        named(longName),
        named(address),
        named(address, shares: true),
        _sharing,
      ]) {
        facts.value = next;
        await tester.pump();
        for (final step in GuideSetupStep.values) {
          expect(
            tester.getRect(_row(step)),
            before[step],
            reason: '$locale $scale ${step.name} ${next.accountName}',
          );
        }
        expect(
          chevrons().evaluate().length,
          chevronCount,
          reason: '$locale $scale ${next.accountName}',
        );
        expect(tester.takeException(), isNull);
      }
    }
  });

  group('no overflow and no cut text', () {
    for (final locale in AppLocalizations.supportedLocales) {
      for (final size in const [Size(360, 780), Size(412, 915)]) {
        for (final scale in const [1.0, 1.3, 2.0]) {
          testWidgets('${locale.languageCode} ${size.width.toInt()} $scale', (
            tester,
          ) async {
            for (final state in [GuideSetupFacts.signedOut, _sharing]) {
              facts.value = state;
              await pump(tester, locale: locale, scale: scale, size: size);
              expect(tester.takeException(), isNull);
              _expectNoClippedText(tester);
            }
          });
        }
      }
    }
  });

  // The sampler reads pixels at the logical size, where the anti-aliased
  // edge of a short word ("Sign in") outnumbers its solid strokes and is
  // taken for its colour: the guideline runs where every word is long
  // enough to read, and every state is judged by its tokens.
  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name}: tap targets and text contrast', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      for (final state in [GuideSetupFacts.signedOut, _sharing]) {
        facts.value = state;
        await pump(tester, brightness: brightness);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        if (state == _sharing) {
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        }
        final ground = Theme.of(
          tester.element(_section()),
        ).colorScheme.rowGroup;
        for (final element
            in find
                .descendant(of: _section(), matching: find.byType(Text))
                .evaluate()) {
          if (_unseen(element)) continue;
          final text = element.widget as Text;
          final color = DefaultTextStyle.of(
            element,
          ).style.merge(text.style).color!;
          final (light, dark) = switch ((
            color.computeLuminance(),
            ground.computeLuminance(),
          )) {
            (final a, final b) when a > b => (a, b),
            (final a, final b) => (b, a),
          };
          expect(
            (light + 0.05) / (dark + 0.05),
            greaterThanOrEqualTo(4.5),
            reason: text.data,
          );
        }
      }
      handle.dispose();
    });
  }
}
