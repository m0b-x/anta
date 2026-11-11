import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/guide_metrics.dart';
import 'package:anta/constants/markdown_constants.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/editor_settings.dart';
import 'package:anta/models/guide_book.dart';
import 'package:anta/models/notes_guide_content.dart';
import 'package:anta/pages/guide_topic_page.dart';
import 'package:anta/services/settings_service.dart';
import 'package:anta/utils/markdown_editor_paint_spans.dart';
import 'package:anta/widgets/markdown_bar.dart';
import 'package:anta/widgets/modern_editor_wrapper.dart';
import 'package:anta/widgets/settings_section_list.dart';

import '../database/support/db_test_support.dart';
import '../goldens/support/golden_fonts.dart';
import 'support/guide_guidelines.dart';
import 'support/guide_try_card_robot.dart';

/// The notes book's "Try it" editors on the markdown, lists, own and money
/// pages (`docs/guide-hub-roadmap.md` D17–D22, §9.2): the real editor over
/// each seed, a coach read off the document, every card walked to its
/// closing line, the reports of the taps that would leave a note, the ids,
/// the guide's guidelines and the long locales at 2.0.
///
/// Edits go through the editor's own controller, as the fork's suites
/// drive it; the fork's caret blink arms a 100 ms timer on a focus change,
/// so every case flushes the tree before it ends.
void main() {
  final en = AppLocalizationsEn();
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

  /// The five pages that hold a card.
  const cardPages = [
    NotesGuideTopic.markdown,
    NotesGuideTopic.lists,
    NotesGuideTopic.own,
    NotesGuideTopic.money,
    NotesGuideTopic.shortcuts,
  ];

  String seedOf(AppLocalizations l10n, NotesGuideTopic topic) =>
      switch (topic) {
        NotesGuideTopic.markdown => l10n.notesGuideSeedMarkdown,
        NotesGuideTopic.lists => l10n.notesGuideSeedLists,
        NotesGuideTopic.own => l10n.notesGuideSeedOwn,
        NotesGuideTopic.money => l10n.notesGuideSeedMoney,
        NotesGuideTopic.shortcuts => l10n.notesGuideSeedShortcuts,
        _ => throw ArgumentError(topic),
      };

  String firstLineOf(AppLocalizations l10n, NotesGuideTopic topic) =>
      switch (topic) {
        NotesGuideTopic.markdown => l10n.notesGuideCoachMarkdownHeading(
          l10n.headers,
        ),
        NotesGuideTopic.lists => l10n.notesGuideCoachListsEnter,
        NotesGuideTopic.own => l10n.notesGuideCoachOwnTag,
        NotesGuideTopic.money => l10n.notesGuideCoachMoneySpend(
          l10n.shortcutMoneySubtract,
        ),
        NotesGuideTopic.shortcuts => l10n.notesGuideCoachShortcutsLine(
          l10n.notesGuideShortcutSetLabel,
        ),
        _ => throw ArgumentError(topic),
      };

  Widget app({
    required NotesGuideTopic topic,
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    TextScaler textScaler = TextScaler.noScaling,
  }) => MaterialApp(
    theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: GuideTopicPage(book: GuideBook.notes, topic: topic),
  );

  Future<GuideTryCardRobot> open(
    WidgetTester tester, {
    NotesGuideTopic topic = NotesGuideTopic.markdown,
    Locale locale = const Locale('en'),
    Brightness brightness = Brightness.light,
    Size size = const Size(412, 915),
    TextScaler textScaler = TextScaler.noScaling,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(
        topic: topic,
        locale: locale,
        brightness: brightness,
        textScaler: textScaler,
      ),
    );
    await tester.pumpAndSettle();
    final robot = GuideTryCardRobot.book(tester, 'notes', topic.slug);
    await robot.reveal();
    return robot;
  }

  Finder editorNode([String slug = 'markdown']) => find.bySemanticsIdentifier(
    SemanticsIds.guideBookTryEditor('notes', slug),
  );

  ModernEditorWrapper wrapper(WidgetTester tester) =>
      tester.widget<ModernEditorWrapper>(find.byType(ModernEditorWrapper));

  CodeLineEditingController controller(WidgetTester tester) =>
      wrapper(tester).controller;

  /// The stage is six of the fork's own lines (D20), and the fork's line is
  /// [fontSize] × the editor's line height rounded to a whole pixel by the
  /// text engine — the render says so, so a sixth line is never clipped.
  void expectSixLines(WidgetTester tester, String slug, double fontSize) {
    final line = (fontSize * MarkdownConstants.lineHeight).roundToDouble();
    final render = CodeFieldRenderForTesting.of(
      tester.renderObject(find.byType(CodeEditor)),
    );
    expect(render.lineHeight, line);
    expect(
      tester.getSize(editorNode(slug)).height,
      line * GuideMetrics.editorStageLines,
    );
  }

  Future<void> type(
    WidgetTester tester,
    String text,
    CodeLineSelection at,
  ) async {
    controller(tester).replaceSelection(text, at);
    await tester.pumpAndSettle();
  }

  /// The caret at the end of [line], whatever the seed's language.
  CodeLineSelection endOf(WidgetTester tester, int line) =>
      CodeLineSelection.collapsed(
        index: line,
        offset: controller(tester).codeLines[line].text.length,
      );

  /// Enter at the end of [line] as the keyboard sends it: a line break the
  /// edit tracker reads as an Enter, so a list item continues.
  Future<void> enterAt(WidgetTester tester, int line) =>
      type(tester, '\n', endOf(tester, line));

  /// A press on the bar's button named [label] — its tooltip, the app's own
  /// label for it (`docs/guide-hub-roadmap.md` D27).
  Future<void> press(WidgetTester tester, String label) async {
    final button = find.byTooltip(label);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  /// What she types at the caret, wherever a press left it.
  Future<void> typeAtCaret(WidgetTester tester, String text) async {
    controller(tester).replaceSelection(text);
    await tester.pumpAndSettle();
  }

  /// Parks the caret in [line], as her tap on it would.
  Future<void> caretIn(WidgetTester tester, int line, [int offset = 0]) async {
    controller(tester).selection = CodeLineSelection.collapsed(
      index: line,
      offset: offset,
    );
    await tester.pump();
  }

  List<String> lines(WidgetTester tester) => [
    for (final line in controller(tester).codeLines.toList()) line.text,
  ];

  /// The English edit that does [topic]'s first step, so the coach has
  /// moved on.
  Future<void> firstStep(WidgetTester tester, NotesGuideTopic topic) async {
    switch (topic) {
      case NotesGuideTopic.markdown:
        await type(
          tester,
          '# ',
          const CodeLineSelection.collapsed(index: 0, offset: 0),
        );
      case NotesGuideTopic.lists:
        await enterAt(tester, 3);
      case NotesGuideTopic.own:
        await type(tester, ' #pr', endOf(tester, 0));
      case NotesGuideTopic.money:
        await enterAt(tester, 1);
        await type(
          tester,
          r'$- 25 shoes',
          const CodeLineSelection.collapsed(index: 2, offset: 0),
        );
      case NotesGuideTopic.shortcuts:
        await press(tester, en.notesGuideShortcutSetLabel);
      default:
        throw ArgumentError(topic);
    }
  }

  /// Flushes the caret blink's timer before the tree comes down.
  Future<void> finish(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  for (final topic in cardPages) {
    testWidgets('the ${topic.slug} page opens its card on the seed, above how '
        'it works, under its ids', (tester) async {
      final robot = await open(tester, topic: topic);

      expect(robot.card, findsOneWidget);
      expect(
        find.bySemanticsIdentifier(
          SemanticsIds.guideBookTryCaption('notes', topic.slug),
        ),
        findsOneWidget,
      );
      expect(editorNode(topic.slug), findsOneWidget);
      expect(robot.skipButton, findsOneWidget);
      expect(robot.backButton, findsOneWidget);
      expect(find.text(en.calendarGuideTryIt.toUpperCase()), findsOneWidget);
      expect(
        tester.getTopLeft(robot.card).dy,
        lessThan(
          tester
              .getTopLeft(find.text(en.calendarGuideHowItWorks.toUpperCase()))
              .dy,
        ),
      );
      expect(controller(tester).text, seedOf(en, topic));
      expect(robot.line, firstLineOf(en, topic));
      expect(robot.canBack, isFalse);
      // Every report and the closing line size the slot.
      expect(
        robot.lineCandidates,
        containsAll([
          en.calendarGuideCoachDone,
          en.notesGuideReportTag,
          en.notesGuideReportWiki,
          en.notesGuideReportLink,
          en.notesGuideReportMoney,
        ]),
      );
      // The editor's default size, six lines of it, whatever she set.
      expect(
        wrapper(tester).editorFontSize,
        EditorSettings.defaults.editorFontSize,
      );
      expect(wrapper(tester).checkboxTapToggle, isTrue);
      // Six lines scroll by drag; no rail under the 48 dp target.
      expect(wrapper(tester).showScrollIndicator, isFalse);
      expectSixLines(
        tester,
        topic.slug,
        EditorSettings.defaults.editorFontSize,
      );
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  }

  testWidgets('six plain lines fill the stage, the sixth unclipped', (
    tester,
  ) async {
    await open(tester, topic: NotesGuideTopic.lists);
    final lines = [for (var i = 1; i <= 6; i++) 'Line $i'];
    controller(tester).text = lines.join('\n');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final editor = find.byType(CodeEditor);
    final render = CodeFieldRenderForTesting.of(tester.renderObject(editor));
    expect(render.displayedLineIndices, [0, 1, 2, 3, 4, 5]);
    var bottom = tester.getTopLeft(editor).dy;
    for (var i = 0; i < lines.length; i++) {
      bottom += render.lineHeightOfLine(i);
    }
    expect(
      bottom,
      lessThanOrEqualTo(tester.getRect(editorNode('lists')).bottom),
    );
    // Nothing left to scroll to: the sixth line is all there.
    expect(
      wrapper(
        tester,
      ).scrollController.verticalScroller.position.maxScrollExtent,
      0,
    );
    await finish(tester);
  });

  test('the app book\'s pages have no card', () {
    for (final topic in GuideBook.app.topics) {
      expect(topic.editorCards, isEmpty, reason: topic.slug);
    }
  });

  testWidgets('each mark she types moves the coach on; a box tick finishes '
      'the card on the closing line', (tester) async {
    final robot = await open(tester);
    final cardHeight = tester.getSize(robot.card).height;

    await type(
      tester,
      '# ',
      const CodeLineSelection.collapsed(index: 0, offset: 0),
    );
    expect(robot.line, en.notesGuideCoachMarkdownBold(en.bold));
    expect(robot.canBack, isTrue);

    // "Felt strong today": the word between offsets 5 and 11.
    await type(
      tester,
      '**strong**',
      const CodeLineSelection(
        baseIndex: 3,
        baseOffset: 5,
        extentIndex: 3,
        extentOffset: 11,
      ),
    );
    expect(robot.line, en.notesGuideCoachMarkdownList(en.bulletList));

    await type(
      tester,
      '- ',
      const CodeLineSelection.collapsed(index: 1, offset: 0),
    );
    expect(robot.line, en.notesGuideCoachMarkdownTask(en.checkbox));

    // An open box is not the step: the box has to be ticked.
    await type(
      tester,
      '- [ ] Stretch\n',
      const CodeLineSelection.collapsed(index: 1, offset: 0),
    );
    expect(robot.line, en.notesGuideCoachMarkdownTask(en.checkbox));
    expect(tester.getSize(robot.card).height, cardHeight);

    // Column 0 of the task line is inside the box's tap zone however the
    // box changes the glyph widths; the heading above is taller than a
    // plain line, so the line's top is read off the editor.
    final editor = find.byType(CodeEditor);
    final render = CodeFieldRenderForTesting.of(tester.renderObject(editor));
    await tester.tapAt(
      tester.getTopLeft(editor) +
          Offset(
            GuideMetrics.cardInset + 2,
            render.lineHeightOfLine(0) + render.lineHeightOfLine(1) / 2,
          ),
    );
    await tester.pumpAndSettle();

    expect(controller(tester).codeLines[1].text, '- [x] Stretch');
    expect(robot.line, en.calendarGuideCoachDone);
    expect(robot.canSkip, isFalse);
    expect(tester.getSize(robot.card).height, cardHeight);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('the lists card: Enter continues, the swipe nests the item and '
      'brings it back, Enter on an empty item ends the list', (tester) async {
    final robot = await open(tester, topic: NotesGuideTopic.lists);
    final cardHeight = tester.getSize(robot.card).height;

    await enterAt(tester, 3);
    expect(controller(tester).codeLines[4].text, '- ');
    expect(robot.line, en.notesGuideCoachListsNest(en.indentLine));

    // The swipe nests only the focused editor's caret line: a tap on
    // "Squat" takes focus and, past the double-tap window, the caret is
    // parked in the word as her tap leaves it.
    final editor = find.byType(CodeEditor);
    final render = CodeFieldRenderForTesting.of(tester.renderObject(editor));
    final squat =
        tester.getTopLeft(editor) +
        Offset(GuideMetrics.cardInset + 40, render.lineHeightOfLine(0) * 1.5);
    await tester.tapAt(squat);
    await tester.pump(const Duration(milliseconds: 400));
    controller(tester).selection = const CodeLineSelection.collapsed(
      index: 1,
      offset: 4,
    );
    await tester.pump();

    await tester.dragFrom(squat, const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(controller(tester).codeLines[1].text, '  - Squat');
    expect(robot.line, en.notesGuideCoachListsOutdent(en.outdentLine));

    await tester.dragFrom(squat, const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(controller(tester).codeLines[1].text, '- Squat');
    expect(robot.line, en.notesGuideCoachListsEnd);

    await enterAt(tester, 4);
    expect(controller(tester).text, '${en.notesGuideSeedLists}\n');
    expect(robot.line, en.calendarGuideCoachDone);
    expect(tester.getSize(robot.card).height, cardHeight);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('the own card: a tag, a ghost, a colour and a wiki link walk '
      'it to the closing line', (tester) async {
    final robot = await open(tester, topic: NotesGuideTopic.own);

    await type(tester, ' #pr', endOf(tester, 0));
    expect(robot.line, en.notesGuideCoachOwnGhost(en.shortcutGhostText));

    await type(tester, ' {{weight}}', endOf(tester, 1));
    expect(robot.line, en.notesGuideCoachOwnColour(en.shortcutColorText));

    await type(tester, ' {red:heavy}', endOf(tester, 2));
    expect(robot.line, en.notesGuideCoachOwnWiki);

    await enterAt(tester, 2);
    await type(
      tester,
      '[[Leg day]]',
      const CodeLineSelection.collapsed(index: 3, offset: 0),
    );
    expect(robot.line, en.calendarGuideCoachDone);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('the money card: a spend, money in and the total walk it to '
      'the closing line, on lines drawn as a ledger', (tester) async {
    final robot = await open(tester, topic: NotesGuideTopic.money);

    await enterAt(tester, 1);
    await type(
      tester,
      r'$- 25 shoes',
      const CodeLineSelection.collapsed(index: 2, offset: 0),
    );
    expect(robot.line, en.notesGuideCoachMoneyAdd(en.shortcutMoneyAdd));

    await enterAt(tester, 2);
    await type(
      tester,
      r'$+ 25 refund',
      const CodeLineSelection.collapsed(index: 3, offset: 0),
    );
    expect(robot.line, en.notesGuideCoachMoneyTotal(en.shortcutMoneyTotal));

    await enterAt(tester, 3);
    await type(
      tester,
      r'$$',
      const CodeLineSelection.collapsed(index: 4, offset: 0),
    );
    expect(robot.line, en.calendarGuideCoachDone);

    // The ledger is on in a card whatever her setting (§4): a spend's `-`
    // is drawn as the ledger's minus and `$$` as the balance chip.
    final editor = find.byType(CodeEditor);
    TextSpan spanOf(int index) => controller(tester).buildTextSpan(
      context: tester.element(editor),
      index: index,
      textSpan: TextSpan(text: controller(tester).codeLines[index].text),
      style: const TextStyle(fontSize: 16, color: Color(0xFF000000)),
    );
    expect(spanOf(1).toPlainText(), contains('−'));
    var chips = 0;
    spanOf(4).visitChildren((span) {
      if (span is EditorMoneyTotalSpan) chips++;
      return true;
    });
    expect(chips, 1);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('one edit that shows two marks marks both steps', (tester) async {
    final robot = await open(tester);
    await type(
      tester,
      '# **Leg** day',
      const CodeLineSelection(
        baseIndex: 0,
        baseOffset: 0,
        extentIndex: 0,
        extentOffset: 7,
      ),
    );
    expect(robot.line, en.notesGuideCoachMarkdownList(en.bulletList));
    await finish(tester);
  });

  testWidgets('a tap that would leave the note is reported, and her next '
      'edit takes the report down', (tester) async {
    final robot = await open(tester);
    final reports = <(String, void Function(ModernEditorWrapper)), String>{
      ('tag', (w) => w.onOpenTag!('#gym')): en.notesGuideReportTag,
      ('wiki', (w) => w.onOpenWikiLink!('Leg day')): en.notesGuideReportWiki,
      ('link', (w) => w.onOpenLink!('https://example.com')):
          en.notesGuideReportLink,
      ('money', (w) => w.onMoneyTap!(0)): en.notesGuideReportMoney,
    };
    for (final MapEntry(key: (name, tap), value: report) in reports.entries) {
      tap(wrapper(tester));
      await tester.pumpAndSettle();
      expect(robot.line, report, reason: name);
    }

    await type(
      tester,
      'x',
      const CodeLineSelection.collapsed(index: 2, offset: 0),
    );
    expect(robot.line, en.notesGuideCoachMarkdownHeading(en.headers));
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('a real tap on a #tag she typed is reported, never '
      'followed', (tester) async {
    final handle = tester.ensureSemantics();
    final robot = await open(tester, topic: NotesGuideTopic.own);
    await type(tester, ' #pr', endOf(tester, 0));
    expect(robot.line, en.notesGuideCoachOwnGhost(en.shortcutGhostText));

    // The tag's own zone, as the editor publishes it: the editor is not
    // focused, so no line is revealed and the zone is live.
    final zone = find.semantics
        .byLabel(en.editorZoneSearchTagNamed('#pr'))
        .evaluate()
        .single;
    var rect = zone.rect;
    for (SemanticsNode? n = zone; n != null; n = n.parent) {
      if (n.transform case final transform?) {
        rect = MatrixUtils.transformRect(transform, rect);
      }
    }
    final text = controller(tester).text;
    await tester.tapAt(rect.center);
    await tester.pumpAndSettle();

    expect(robot.line, en.notesGuideReportTag);
    expect(controller(tester).text, text);
    expect(tester.takeException(), isNull);
    handle.dispose();
    await finish(tester);
  });

  testWidgets('an edit snaps a read-back line to the live one', (tester) async {
    final robot = await open(tester);
    await type(
      tester,
      '# ',
      const CodeLineSelection.collapsed(index: 0, offset: 0),
    );
    await robot.back();
    expect(robot.reading, isTrue);
    expect(robot.line, en.notesGuideCoachMarkdownHeading(en.headers));

    // No step's mark: the line still goes back to what is next.
    await type(tester, 'x', endOf(tester, 2));
    expect(robot.reading, isFalse);
    expect(robot.line, en.notesGuideCoachMarkdownBold(en.bold));
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('a heading typed inside a fence is no heading', (tester) async {
    final robot = await open(tester);
    await type(
      tester,
      '```\n# x\n```\n',
      const CodeLineSelection.collapsed(index: 0, offset: 0),
    );
    expect(controller(tester).codeLines[1].text, '# x');
    expect(robot.line, en.notesGuideCoachMarkdownHeading(en.headers));
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('a flat list after a skipped nest is no outdent', (tester) async {
    final robot = await open(tester, topic: NotesGuideTopic.lists);
    await robot.skip();
    await robot.skip();
    expect(robot.line, en.notesGuideCoachListsOutdent(en.outdentLine));

    await type(tester, 'x', endOf(tester, 0));
    expect(robot.line, en.notesGuideCoachListsOutdent(en.outdentLine));
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('Enter at the start of an item opens a line, it ends no '
      'list', (tester) async {
    final robot = await open(tester, topic: NotesGuideTopic.lists);
    while (robot.line != en.notesGuideCoachListsEnd) {
      await robot.skip();
    }

    await type(
      tester,
      '\n',
      const CodeLineSelection.collapsed(index: 1, offset: 0),
    );
    expect(controller(tester).codeLines[0].text, '- Legs');
    expect(controller(tester).codeLines[1].text, '');
    expect(controller(tester).codeLines[2].text, '- Squat');
    expect(robot.line, en.notesGuideCoachListsEnd);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('a change of language keeps her text and the editor, and '
      'sizes the coach slot for the new language', (tester) async {
    const de = Locale('de');
    const ro = Locale('ro');
    final robot = await open(tester, topic: NotesGuideTopic.money, locale: de);
    final l10nDe = lookupAppLocalizations(de);
    final l10nRo = lookupAppLocalizations(ro);
    expect(robot.lineCandidates, contains(l10nDe.notesGuideReportMoney));

    await type(tester, ' x', endOf(tester, 0));
    final text = controller(tester).text;
    final editor = tester.state(find.byType(CodeEditor));

    await tester.pumpWidget(app(topic: NotesGuideTopic.money, locale: ro));
    await tester.pumpAndSettle();

    expect(controller(tester).text, text);
    // The ledger's messages changed with the language: a repaint, never a
    // remount of the editor.
    expect(tester.state(find.byType(CodeEditor)), same(editor));
    expect(
      robot.lineCandidates,
      containsAll([
        l10nRo.notesGuideReportMoney,
        l10nRo.calendarGuideCoachDone,
        l10nRo.notesGuideCoachMoneySpend(l10nRo.shortcutMoneySubtract),
      ]),
    );
    expect(robot.lineCandidates, isNot(contains(l10nDe.notesGuideReportMoney)));
    expect(
      robot.line,
      l10nRo.notesGuideCoachMoneySpend(l10nRo.shortcutMoneySubtract),
    );
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('the keyboard up brings the coach line and the editor above '
      'it', (tester) async {
    final robot = await open(tester);
    const inset = 320.0;
    final editor = find.byType(CodeEditor);
    final render = CodeFieldRenderForTesting.of(tester.renderObject(editor));
    // A plain line, so the tap places the caret and takes focus.
    await tester.tapAt(
      tester.getTopLeft(editor) +
          Offset(GuideMetrics.cardInset + 40, render.lineHeightOfLine(0) * 2.5),
    );
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: inset);
    await tester.pumpAndSettle();

    final list = find
        .descendant(
          of: find.byType(SettingsSectionList),
          matching: find.byType(Scrollable),
        )
        .first;
    expect(
      robot.slotRect.top,
      moreOrLessEquals(tester.getRect(list).top, epsilon: 1),
    );
    expect(tester.getRect(editorNode()).bottom, lessThanOrEqualTo(915 - inset));
    expect(tester.takeException(), isNull);

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('German at 2.0 on a small phone: the keyboard up keeps the '
      'coach line, the stage\'s top and her first line in view (D22)', (
    tester,
  ) async {
    const height = 780.0;
    const inset = 320.0;
    final robot = await open(
      tester,
      locale: const Locale('de'),
      size: const Size(360, height),
      textScaler: const TextScaler.linear(2.0),
    );
    // She reads the card from its top; the keyboard's reveal never scrolls
    // the page back down.
    await tester.ensureVisible(robot.card);
    await tester.pumpAndSettle();
    final editor = find.byType(CodeEditor);
    final render = CodeFieldRenderForTesting.of(tester.renderObject(editor));
    // A plain line, so the tap places the caret and takes focus.
    await tester.tapAt(
      tester.getTopLeft(editor) +
          Offset(GuideMetrics.cardInset + 40, render.lineHeightOfLine(0) * 0.5),
    );
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: inset);
    await tester.pumpAndSettle();

    final list = tester.getRect(
      find
          .descendant(
            of: find.byType(SettingsSectionList),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(robot.slotRect.top, greaterThanOrEqualTo(list.top - 0.5));
    final stage = tester.getRect(editorNode());
    // The stage's hairline sits its padding above the editor.
    expect(
      stage.top - GuideMetrics.stagePadding,
      greaterThanOrEqualTo(list.top),
    );
    final scrolled = wrapper(tester).scrollController.verticalScroller.offset;
    expect(
      stage.top - scrolled + render.lineHeightOfLine(0),
      lessThanOrEqualTo(height - inset),
    );
    expect(tester.takeException(), isNull);

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  group('the bar under the editor (D27–D31)', () {
    testWidgets('holds the card\'s buttons in the shipped bar\'s order, with '
        'undo, and none of the rest', (tester) async {
      await open(tester);
      final bar = find.bySemanticsIdentifier(
        SemanticsIds.guideBookTryBar('notes', 'markdown'),
      );
      expect(bar, findsOneWidget);
      // Over the editor, under the line that names its buttons (D29).
      expect(
        tester.getBottomLeft(bar).dy,
        lessThanOrEqualTo(tester.getTopLeft(editorNode()).dy),
      );
      final shipped = [
        en.checkbox,
        en.bulletList,
        en.numberedList,
        en.bold,
        en.italic,
        en.headers,
        en.strikethrough,
        en.shortcutHighlight,
        en.quote,
        en.link,
        en.undo,
        en.redo,
      ];
      double? before;
      for (final label in shipped) {
        final button = find.descendant(
          of: bar,
          matching: find.byTooltip(label),
        );
        expect(button, findsOneWidget, reason: label);
        final x = tester.getTopLeft(button).dx;
        if (before != null) expect(x, greaterThan(before), reason: label);
        before = x;
      }
      for (final absent in [
        en.shortcutCallout,
        en.shortcutGhostText,
        en.shortcutMoneyAdd,
        en.paste,
        en.settings,
      ]) {
        expect(find.byTooltip(absent), findsNothing, reason: absent);
      }
      // Nothing to undo in a note she has not touched.
      expect(
        tester.widget<MarkdownBar>(find.byType(MarkdownBar)).canUndo,
        isFalse,
      );
      await finish(tester);
    });

    testWidgets('the caret waits at the end of the seed, so a press before '
        'any tap adds a line, never writes into the first', (tester) async {
      await open(tester, topic: NotesGuideTopic.money);
      final seed = en.notesGuideSeedMoney.split('\n');
      expect(seed.last, isEmpty);
      expect(
        controller(tester).selection,
        CodeLineSelection.collapsed(index: seed.length - 1, offset: 0),
      );
      // The money buttons ship hidden; the card shows them (D27).
      await press(tester, en.shortcutMoneySubtract);
      expect(lines(tester), [...seed.take(seed.length - 1), r'$- ']);
      await finish(tester);
    });

    testWidgets('the markdown card walks to its closing line on the bar: '
        'the heading menu, bold around the caret, a bullet, a checkbox', (
      tester,
    ) async {
      final robot = await open(tester);
      final cardHeight = tester.getSize(robot.card).height;

      await caretIn(tester, 0, 3);
      await press(tester, en.headers);
      await tester.tap(find.text(en.header1));
      await tester.pumpAndSettle();
      expect(lines(tester).first, '# Leg day');
      expect(robot.line, en.notesGuideCoachMarkdownBold(en.bold));

      // Bold at a bare caret writes the pair and waits between the stars.
      await caretIn(tester, 3, 5);
      await press(tester, en.bold);
      expect(lines(tester)[3], 'Felt ****strong today');
      expect(robot.line, en.notesGuideCoachMarkdownBold(en.bold));
      await typeAtCaret(tester, 'very');
      expect(lines(tester)[3], 'Felt **very**strong today');
      expect(robot.line, en.notesGuideCoachMarkdownList(en.bulletList));

      await caretIn(tester, 1);
      await press(tester, en.bulletList);
      expect(lines(tester)[1], '- Squat 5×5');
      expect(robot.line, en.notesGuideCoachMarkdownTask(en.checkbox));

      await caretIn(tester, 2);
      await press(tester, en.checkbox);
      expect(lines(tester)[2], '- [ ] Bench 3×8');
      // An open box is not the step.
      expect(robot.line, en.notesGuideCoachMarkdownTask(en.checkbox));
      await type(
        tester,
        'x',
        const CodeLineSelection(
          baseIndex: 2,
          baseOffset: 3,
          extentIndex: 2,
          extentOffset: 4,
        ),
      );
      expect(robot.line, en.calendarGuideCoachDone);
      expect(tester.getSize(robot.card).height, cardHeight);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });

    testWidgets('a press is one undo: the bar\'s undo takes the whole line '
        'back and redo writes it again', (tester) async {
      await open(tester);
      await caretIn(tester, 1);
      await press(tester, en.bulletList);
      expect(lines(tester)[1], '- Squat 5×5');
      MarkdownBar bar() => tester.widget<MarkdownBar>(find.byType(MarkdownBar));
      expect(bar().canUndo, isTrue);
      expect(bar().canRedo, isFalse);

      await press(tester, en.undo);
      expect(controller(tester).text, en.notesGuideSeedMarkdown);
      expect(bar().canUndo, isFalse);
      expect(bar().canRedo, isTrue);

      await press(tester, en.redo);
      expect(lines(tester)[1], '- Squat 5×5');
      expect(tester.takeException(), isNull);
      await finish(tester);
    });

    testWidgets('the lists card: the bar\'s arrows nest the item and bring '
        'it back, as the swipe does', (tester) async {
      final robot = await open(tester, topic: NotesGuideTopic.lists);
      await enterAt(tester, 3);
      expect(robot.line, en.notesGuideCoachListsNest(en.indentLine));

      await caretIn(tester, 1, 4);
      await press(tester, en.indentLine);
      expect(lines(tester)[1], '  - Squat');
      expect(robot.line, en.notesGuideCoachListsOutdent(en.outdentLine));

      await press(tester, en.outdentLine);
      expect(lines(tester)[1], '- Squat');
      expect(robot.line, en.notesGuideCoachListsEnd);
      // The lesson's two arrows lead the utility buttons.
      expect(
        tester.getTopLeft(find.byTooltip(en.indentLine)).dx,
        lessThan(tester.getTopLeft(find.byTooltip(en.undo)).dx),
      );
      expect(tester.takeException(), isNull);
      await finish(tester);
    });

    testWidgets('the own card: the ghost button draws its blank at once; the '
        'colour button\'s slot is no colour until a word fills it', (
      tester,
    ) async {
      final robot = await open(tester, topic: NotesGuideTopic.own);
      await type(tester, ' #pr', endOf(tester, 0));
      expect(robot.line, en.notesGuideCoachOwnGhost(en.shortcutGhostText));

      await caretIn(tester, 1, lines(tester)[1].length);
      await press(tester, en.shortcutGhostText);
      expect(lines(tester)[1], 'Next week: squat{{  }}');
      expect(robot.line, en.notesGuideCoachOwnColour(en.shortcutColorText));

      await caretIn(tester, 2, lines(tester)[2].length);
      await press(tester, en.shortcutColorText);
      expect(lines(tester)[2], 'Same warm-up as last time{red:{{  }}}');
      // The slot is selected and dim: not red yet (D31).
      expect(robot.line, en.notesGuideCoachOwnColour(en.shortcutColorText));
      await typeAtCaret(tester, 'heavy');
      expect(lines(tester)[2], 'Same warm-up as last time{red:heavy}');
      expect(robot.line, en.notesGuideCoachOwnWiki);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });

    testWidgets('the money card walks to its closing line on the bar, the '
        'amounts typed', (tester) async {
      final robot = await open(tester, topic: NotesGuideTopic.money);

      await press(tester, en.shortcutMoneySubtract);
      // A marker with no amount is no ledger line yet.
      expect(
        robot.line,
        en.notesGuideCoachMoneySpend(en.shortcutMoneySubtract),
      );
      await typeAtCaret(tester, '25 shoes');
      expect(robot.line, en.notesGuideCoachMoneyAdd(en.shortcutMoneyAdd));

      await enterAt(tester, 2);
      await caretIn(tester, 3);
      await press(tester, en.shortcutMoneyAdd);
      await typeAtCaret(tester, '25 refund');
      expect(robot.line, en.notesGuideCoachMoneyTotal(en.shortcutMoneyTotal));

      await enterAt(tester, 3);
      await caretIn(tester, 4);
      await press(tester, en.shortcutMoneyTotal);
      expect(lines(tester), [
        r'$= 500 budget',
        r'$- 40 gym',
        r'$- 25 shoes',
        r'$+ 25 refund',
        r'$$',
      ]);
      expect(robot.line, en.calendarGuideCoachDone);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });

    testWidgets('a change of language renames the bar\'s buttons in '
        'place', (tester) async {
      await tester.pumpWidget(app(topic: NotesGuideTopic.shortcuts));
      await tester.pumpAndSettle();
      expect(find.byTooltip(en.notesGuideShortcutSetLabel), findsOneWidget);
      await tester.pumpWidget(
        app(topic: NotesGuideTopic.shortcuts, locale: const Locale('de')),
      );
      await tester.pumpAndSettle();
      final de = lookupAppLocalizations(const Locale('de'));
      expect(find.byTooltip(de.notesGuideShortcutSetLabel), findsOneWidget);
      expect(find.byTooltip(de.notesGuideShortcutMineLabel), findsOneWidget);
      expect(find.byTooltip(en.notesGuideShortcutMineLabel), findsNothing);
      await finish(tester);
    });
  });

  testWidgets('German at 1.3 on a small phone: the keyboard up keeps the '
      'coach line, the bar and her first line in view together (D29)', (
    tester,
  ) async {
    const height = 780.0;
    const inset = 320.0;
    for (final topic in [NotesGuideTopic.markdown, NotesGuideTopic.lists]) {
      final robot = await open(
        tester,
        topic: topic,
        locale: const Locale('de'),
        size: const Size(360, height),
        textScaler: const TextScaler.linear(1.3),
      );
      await tester.ensureVisible(robot.card);
      await tester.pumpAndSettle();
      final editor = find.byType(CodeEditor);
      final render = CodeFieldRenderForTesting.of(tester.renderObject(editor));
      await tester.tapAt(
        tester.getTopLeft(editor) +
            Offset(GuideMetrics.cardInset + 40, render.lineHeightOfLine(0) / 2),
      );
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: inset);
      await tester.pumpAndSettle();

      final list = tester.getRect(
        find
            .descendant(
              of: find.byType(SettingsSectionList),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final reason = topic.slug;
      expect(
        robot.slotRect.top,
        greaterThanOrEqualTo(list.top - 0.5),
        reason: reason,
      );
      final bar = tester.getRect(
        find.bySemanticsIdentifier(
          SemanticsIds.guideBookTryBar('notes', topic.slug),
        ),
      );
      expect(bar.top, greaterThanOrEqualTo(list.top), reason: reason);
      expect(bar.bottom, lessThanOrEqualTo(height - inset), reason: reason);
      expect(
        tester.getRect(editorNode(topic.slug)).top + render.lineHeightOfLine(0),
        lessThanOrEqualTo(height - inset),
        reason: reason,
      );
      expect(tester.takeException(), isNull, reason: reason);

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      await finish(tester);
    }
  });

  group('the shortcuts card (D32–D34)', () {
    Finder maker() => find.bySemanticsIdentifier(
      SemanticsIds.guideBookTryMaker('notes', 'shortcuts'),
    );

    Finder makerField(WidgetTester tester) =>
        find.descendant(of: maker(), matching: find.byType(TextField));

    testWidgets('her field stands between the bar and the editor under the '
        'New Shortcut page\'s own label, her star at the end of the bar', (
      tester,
    ) async {
      await open(tester, topic: NotesGuideTopic.shortcuts);
      expect(maker(), findsOneWidget);
      expect(
        tester.getBottomLeft(maker()).dy,
        lessThanOrEqualTo(tester.getTopLeft(editorNode('shortcuts')).dy),
      );
      expect(
        tester
            .getBottomLeft(
              find.bySemanticsIdentifier(
                SemanticsIds.guideBookTryBar('notes', 'shortcuts'),
              ),
            )
            .dy,
        lessThanOrEqualTo(tester.getTopLeft(maker()).dy),
      );
      // The star the coach names is the glyph drawn, never the bar's
      // fallback for an icon it cannot resolve.
      expect(
        find.descendant(
          of: find.byTooltip(en.notesGuideShortcutMineLabel),
          matching: find.byIcon(Icons.star),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(makerField(tester)).decoration!.labelText,
        en.markdownStart,
      );
      final labels = [
        en.notesGuideShortcutSetLabel,
        en.notesGuideShortcutTodayLabel,
        en.notesGuideShortcutMineLabel,
        en.undo,
      ];
      double? before;
      for (final label in labels) {
        final x = tester.getTopLeft(find.byTooltip(label)).dx;
        if (before != null) expect(x, greaterThan(before), reason: label);
        before = x;
      }
      // The other notes cards have no field.
      await finish(tester);
      await open(tester);
      expect(find.byType(TextField), findsNothing);
      await finish(tester);
    });

    testWidgets('Set writes a counted line, then the next number; Today a '
        'dated heading; her text and her button finish the card', (
      tester,
    ) async {
      final robot = await open(tester, topic: NotesGuideTopic.shortcuts);
      final cardHeight = tester.getSize(robot.card).height;
      final set = en.notesGuideShortcutSetLabel;
      String setLine(int n) => en.notesGuideShortcutSetText('$n', '{', '}');

      await press(tester, set);
      expect(lines(tester), ['Leg day', setLine(1), '']);
      expect(robot.line, en.notesGuideCoachShortcutsCount(set));

      await press(tester, set);
      expect(lines(tester), ['Leg day', setLine(1), setLine(2), '']);
      expect(
        robot.line,
        en.notesGuideCoachShortcutsDate(en.notesGuideShortcutTodayLabel),
      );

      await press(tester, en.notesGuideShortcutTodayLabel);
      final dated = lines(tester)[3];
      expect(dated, startsWith('## '));
      // The year alone: the day may turn while the suite runs.
      expect(dated, matches(RegExp(r'^## \d{1,2} \S+ \d{4}$')));
      expect(robot.line, en.notesGuideCoachShortcutsWrite(en.markdownStart));

      // Her button with nothing to write says so and writes nothing.
      final before = controller(tester).text;
      await press(tester, en.notesGuideShortcutMineLabel);
      expect(controller(tester).text, before);
      expect(robot.line, en.notesGuideReportEmptyButton(en.markdownStart));

      await tester.enterText(makerField(tester), 'Squat 5×5');
      await tester.pumpAndSettle();
      expect(
        robot.line,
        en.notesGuideCoachShortcutsPress(en.notesGuideShortcutMineLabel),
      );

      await press(tester, en.notesGuideShortcutMineLabel);
      expect(lines(tester), [
        'Leg day',
        setLine(1),
        setLine(2),
        dated,
        'Squat 5×5',
      ]);
      expect(robot.line, en.calendarGuideCoachDone);
      expect(robot.canSkip, isFalse);
      expect(tester.getSize(robot.card).height, cardHeight);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });

    testWidgets('a press with the caret inside a line of text writes there, '
        'as in a note, and is no line of its own', (tester) async {
      final robot = await open(tester, topic: NotesGuideTopic.shortcuts);
      await caretIn(tester, 0, 3);
      await press(tester, en.notesGuideShortcutSetLabel);
      expect(lines(tester).first, startsWith('Leg- [ ] '));
      // The line says to tap the empty line first; this was not it.
      expect(
        robot.line,
        en.notesGuideCoachShortcutsLine(en.notesGuideShortcutSetLabel),
      );
      expect(tester.takeException(), isNull);
      await finish(tester);
    });

    testWidgets('her text typed into the note by hand is not her button\'s '
        'press', (tester) async {
      final robot = await open(tester, topic: NotesGuideTopic.shortcuts);
      await tester.enterText(makerField(tester), 'Squat 5×5');
      await tester.pumpAndSettle();
      await typeAtCaret(tester, 'Squat 5×5');
      // `write` is done; `line` still leads, and `press` is not credited.
      expect(
        robot.line,
        en.notesGuideCoachShortcutsLine(en.notesGuideShortcutSetLabel),
      );
      while (robot.line !=
          en.notesGuideCoachShortcutsPress(en.notesGuideShortcutMineLabel)) {
        expect(robot.canSkip, isTrue);
        await robot.skip();
      }
      await press(tester, en.notesGuideShortcutMineLabel);
      expect(robot.line, en.calendarGuideCoachDone);
      await finish(tester);
    });

    testWidgets('the keyboard under her field keeps the coach line and the '
        'field in view together', (tester) async {
      const inset = 320.0;
      final robot = await open(
        tester,
        topic: NotesGuideTopic.shortcuts,
        size: const Size(360, 780),
      );
      await tester.tap(makerField(tester));
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: inset);
      await tester.pumpAndSettle();

      final list = tester.getRect(
        find
            .descendant(
              of: find.byType(SettingsSectionList),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(robot.slotRect.top, greaterThanOrEqualTo(list.top - 0.5));
      expect(tester.getRect(maker()).bottom, lessThanOrEqualTo(780 - inset));
      expect(tester.takeException(), isNull);

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  });

  group('the tap-target and text-contrast guidelines', () {
    for (final topic in cardPages) {
      for (final brightness in Brightness.values) {
        for (final size in const [Size(360, 780), Size(412, 915)]) {
          testWidgets('${topic.slug} ${brightness.name} '
              '${size.width.toInt()}', (tester) async {
            final handle = tester.ensureSemantics();
            final robot = await open(
              tester,
              topic: topic,
              brightness: brightness,
              size: size,
            );
            final list = find
                .descendant(
                  of: find.byType(SettingsSectionList),
                  matching: find.byType(Scrollable),
                )
                .first;
            Future<void> meetsAll(String state) async {
              await Scrollable.ensureVisible(
                tester.element(
                  find
                      .ancestor(
                        of: robot.card,
                        matching: find.byType(SettingsSectionCard),
                      )
                      .first,
                ),
              );
              await tester.pumpAndSettle();
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
                meetsGuideline(
                  GuideTextContrastGuideline(viewport: tester.getRect(list)),
                ),
                reason: state,
              );
            }

            await meetsAll('idle');
            await firstStep(tester, topic);
            expect(robot.line, isNot(firstLineOf(en, topic)));
            await meetsAll('changed');
            while (robot.canSkip) {
              await robot.skip();
            }
            await meetsAll('closing');
            handle.dispose();
            await finish(tester);
          });
        }
      }
    }

    // The scale's far end on the small phone, where the editor's inline
    // zones grow with its lines; `own` is the card whose first step types
    // one (a tag).
    testWidgets('own de light 360 at 2.0', (tester) async {
      final handle = tester.ensureSemantics();
      final robot = await open(
        tester,
        topic: NotesGuideTopic.own,
        locale: const Locale('de'),
        size: const Size(360, 780),
        textScaler: const TextScaler.linear(2.0),
      );
      final de = lookupAppLocalizations(const Locale('de'));
      Future<void> meetsBoth(String state) async {
        await tester.ensureVisible(editorNode('own'));
        await tester.pumpAndSettle();
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
      }

      await meetsBoth('idle');
      await firstStep(tester, NotesGuideTopic.own);
      expect(robot.line, isNot(firstLineOf(de, NotesGuideTopic.own)));
      await meetsBoth('changed');
      handle.dispose();
      await finish(tester);
    });
  });

  group('no overflow at text scale 2.0', () {
    for (final topic in cardPages) {
      for (final locale in const [Locale('de'), Locale('ro')]) {
        for (final size in const [Size(360, 780), Size(412, 915)]) {
          testWidgets('${topic.slug} ${locale.languageCode} '
              '${size.width.toInt()}×${size.height.toInt()}', (tester) async {
            final robot = await open(
              tester,
              topic: topic,
              locale: locale,
              size: size,
              textScaler: const TextScaler.linear(2.0),
            );
            final l10n = lookupAppLocalizations(locale);
            expect(tester.takeException(), isNull);
            expect(controller(tester).text, seedOf(l10n, topic));
            expect(robot.line, firstLineOf(l10n, topic));
            // Six lines at the scale the editor follows, to its clamp.
            expectSixLines(
              tester,
              topic.slug,
              EditorSettings.defaults.editorFontSize *
                  ModernEditorWrapper.maxTextScale,
            );
            await tester.ensureVisible(editorNode(topic.slug));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            while (robot.canSkip) {
              await robot.skip();
            }
            expect(robot.line, l10n.calendarGuideCoachDone);
            expect(tester.takeException(), isNull);
            await finish(tester);
          });
        }
      }
    }
  });
}
