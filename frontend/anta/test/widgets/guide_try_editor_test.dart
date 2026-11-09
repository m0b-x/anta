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

  /// The four pages that hold a card.
  const cardPages = [
    NotesGuideTopic.markdown,
    NotesGuideTopic.lists,
    NotesGuideTopic.own,
    NotesGuideTopic.money,
  ];

  String seedOf(AppLocalizations l10n, NotesGuideTopic topic) =>
      switch (topic) {
        NotesGuideTopic.markdown => l10n.notesGuideSeedMarkdown,
        NotesGuideTopic.lists => l10n.notesGuideSeedLists,
        NotesGuideTopic.own => l10n.notesGuideSeedOwn,
        NotesGuideTopic.money => l10n.notesGuideSeedMoney,
        _ => throw ArgumentError(topic),
      };

  String firstLineOf(AppLocalizations l10n, NotesGuideTopic topic) =>
      switch (topic) {
        NotesGuideTopic.markdown => l10n.notesGuideCoachMarkdownHeading,
        NotesGuideTopic.lists => l10n.notesGuideCoachListsEnter,
        NotesGuideTopic.own => l10n.notesGuideCoachOwnTag,
        NotesGuideTopic.money => l10n.notesGuideCoachMoneySpend,
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
    expect(robot.line, en.notesGuideCoachMarkdownBold);
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
    expect(robot.line, en.notesGuideCoachMarkdownList);

    await type(
      tester,
      '- ',
      const CodeLineSelection.collapsed(index: 1, offset: 0),
    );
    expect(robot.line, en.notesGuideCoachMarkdownTask);

    // An open box is not the step: the box has to be ticked.
    await type(
      tester,
      '- [ ] Stretch\n',
      const CodeLineSelection.collapsed(index: 1, offset: 0),
    );
    expect(robot.line, en.notesGuideCoachMarkdownTask);
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
    expect(robot.line, en.notesGuideCoachListsNest);

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
    expect(robot.line, en.notesGuideCoachListsOutdent);

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
    expect(robot.line, en.notesGuideCoachOwnGhost('{', '}'));

    await type(tester, ' {{weight}}', endOf(tester, 1));
    expect(robot.line, en.notesGuideCoachOwnColour('{', '}'));

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
    expect(robot.line, en.notesGuideCoachMoneyAdd);

    await enterAt(tester, 2);
    await type(
      tester,
      r'$+ 25 refund',
      const CodeLineSelection.collapsed(index: 3, offset: 0),
    );
    expect(robot.line, en.notesGuideCoachMoneyTotal);

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
    expect(robot.line, en.notesGuideCoachMarkdownList);
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
    expect(robot.line, en.notesGuideCoachMarkdownHeading);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('a real tap on a #tag she typed is reported, never '
      'followed', (tester) async {
    final handle = tester.ensureSemantics();
    final robot = await open(tester, topic: NotesGuideTopic.own);
    await type(tester, ' #pr', endOf(tester, 0));
    expect(robot.line, en.notesGuideCoachOwnGhost('{', '}'));

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
    expect(robot.line, en.notesGuideCoachMarkdownHeading);

    // No step's mark: the line still goes back to what is next.
    await type(tester, 'x', endOf(tester, 2));
    expect(robot.reading, isFalse);
    expect(robot.line, en.notesGuideCoachMarkdownBold);
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
    expect(robot.line, en.notesGuideCoachMarkdownHeading);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('a flat list after a skipped nest is no outdent', (tester) async {
    final robot = await open(tester, topic: NotesGuideTopic.lists);
    await robot.skip();
    await robot.skip();
    expect(robot.line, en.notesGuideCoachListsOutdent);

    await type(tester, 'x', endOf(tester, 0));
    expect(robot.line, en.notesGuideCoachListsOutdent);
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
        l10nRo.notesGuideCoachMoneySpend,
      ]),
    );
    expect(robot.lineCandidates, isNot(contains(l10nDe.notesGuideReportMoney)));
    expect(robot.line, l10nRo.notesGuideCoachMoneySpend);
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
