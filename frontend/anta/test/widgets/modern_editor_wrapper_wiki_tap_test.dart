import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/constants/app_spacing.dart';
import 'package:anta/constants/markdown_constants.dart';
import 'package:anta/utils/re_editor_search_controller.dart';
import 'package:anta/widgets/modern_editor_wrapper.dart';

/// The editor's `[[note]]` tap zone — the fifth one, added with wiki
/// links. It carries the link zone's pass-through rules verbatim (reveal
/// line, fence line, over-long line, ghosts win) and its own boundary
/// rule: the zone is `[start + 1, end)`, so the construct's *first* `[`
/// still places the caret and its second one opens the note.
///
/// The wrapper hands the editor no span builder, so the mounted text is
/// raw and every column maps 1:1 onto a source offset — which is what
/// makes these zones testable by geometry (same trick as
/// `modern_editor_wrapper_tag_tap_test.dart`, whose `positionOf` this
/// copies).
///
/// The caret is parked through the controller rather than with a tap:
/// an unfocused editor is exactly the state the interception rules are
/// about (a claimed tap must not raise the keyboard), and a programmatic
/// park never leaves an Android selection handle hanging one line box
/// below it for the next tap to land on. Every document below therefore
/// keeps its construct on line 2, one line clear of any handle a
/// pass-through tap on line 0 could produce.
void main() {
  const fontSize = 16.0;
  const lineBox = fontSize * MarkdownConstants.lineHeight;

  /// The global position of column [column] on line [line]. The `+ 2`
  /// biases the tap into the glyph so the nearest caret boundary is
  /// [column] and never [column] - 1.
  Offset positionOf(WidgetTester tester, int line, int column) {
    final origin = tester.getTopLeft(find.byType(CodeEditor));
    return origin +
        Offset(
          AppSpacing.lg + column * fontSize + 2,
          AppSpacing.lg + line * lineBox + lineBox / 2,
        );
  }

  /// Mounts the wrapper over [text] and records every wiki / tag / link
  /// tap. [wikiLinks] and [otherZones] pick which callbacks are wired,
  /// which is what the enabled-zone disjunction is read through.
  Future<
    ({
      List<String> wikis,
      List<String> tags,
      List<String> links,
      CodeLineEditingController controller,
      FocusNode focusNode,
    })
  >
  pumpEditor(
    WidgetTester tester, {
    required String text,
    Set<int> fenceLines = const {},
    bool wikiLinks = true,
    bool otherZones = true,
  }) async {
    final wikis = <String>[];
    final tags = <String>[];
    final links = <String>[];
    final controller = CodeLineEditingController.fromText(text);
    final searchController = ReEditorSearchController();
    final scrollController = CodeScrollController();
    final focusNode = FocusNode();
    addTearDown(() {
      focusNode.dispose();
      searchController.dispose();
      controller.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ModernEditorWrapper(
            controller: controller,
            focusNode: focusNode,
            scrollController: scrollController,
            searchController: searchController,
            editorFontSize: fontSize,
            onTextChanged: () {},
            wordWrap: false,
            checkboxTapToggle: otherZones,
            onOpenLink: otherZones ? links.add : null,
            onOpenTag: otherZones ? tags.add : null,
            onOpenWikiLink: wikiLinks ? wikis.add : null,
            isFenceLine: fenceLines.contains,
            showScrollIndicator: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (
      wikis: wikis,
      tags: tags,
      links: links,
      controller: controller,
      focusNode: focusNode,
    );
  }

  /// The focused editor keeps a cursor-blink timer running, so the tree
  /// has to come down before the test body ends or the binding's
  /// pending-timer invariant fires. Every focus change also arms an
  /// unguarded 100 ms delayed value-set inside the fork's blink
  /// controller, so those are flushed while the tree is still alive —
  /// settling after the teardown would fire them against a disposed
  /// notifier.
  Future<void> teardownEditor(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  /// Parks the collapsed caret on [lineIndex] without a tap, so the line
  /// under test is never the reveal line and the editor keeps its
  /// unfocused state.
  Future<void> park(
    WidgetTester tester,
    CodeLineEditingController controller,
    int lineIndex, {
    int offset = 0,
  }) async {
    controller.selection = CodeLineSelection.collapsed(
      index: lineIndex,
      offset: offset,
    );
    await tester.pump();
    await tester.pump();
  }

  /// `see [[Squat]] now`: `[` 4, `[` 5, `Squat` 6-10, `]` 11, `]` 12.
  /// The token runs [4, 13), so the zone is (4, 13) — 5 through 12.
  const wikiDocument =
      'caret line\n'
      'spacer line\n'
      'see [[Squat]] now';

  testWidgets('tapping a concealed title off the caret line opens the note', (
    tester,
  ) async {
    final e = await pumpEditor(tester, text: wikiDocument);
    await park(tester, e.controller, 0);

    // Inside `Squat`.
    await tester.tapAt(positionOf(tester, 2, 8));
    await tester.pump();

    expect(e.wikis, ['Squat']);
    expect(e.tags, isEmpty);
    expect(e.links, isEmpty);
    // An intercepted tap never moves the caret and never raises focus.
    expect(e.controller.selection.baseIndex, 0);
    expect(e.controller.selection.baseOffset, 0);
    expect(e.focusNode.hasFocus, isFalse);
    await teardownEditor(tester);
  });

  testWidgets('the first bracket places the caret and the second one opens', (
    tester,
  ) async {
    final e = await pumpEditor(tester, text: wikiDocument);
    await park(tester, e.controller, 0);

    // The interior tap runs first: it is intercepted, so the caret stays
    // on line 0 and line 2 is still not the reveal line for the boundary
    // tap that follows.
    await tester.tapAt(positionOf(tester, 2, 5));
    await tester.pump();
    expect(e.wikis, ['Squat']);
    expect(e.controller.selection.baseIndex, 0);

    // Exactly on the construct's outermost `[`, which `containsStrict`
    // leaves to caret placement.
    await tester.tapAt(positionOf(tester, 2, 4));
    await tester.pump();

    expect(e.wikis, ['Squat'], reason: 'the boundary tap opened nothing');
    expect(e.controller.selection.baseIndex, 2);
    expect(e.controller.selection.baseOffset, 4);
    await teardownEditor(tester);
  });

  testWidgets('the title reaches the callback raw, spaces and all', (
    tester,
  ) async {
    // `see [[ a ]] now`: `[` 4, `[` 5, ` a ` 6-8, `]` 9, `]` 10. The
    // title is the lookup key and trimming it is the page's job, so the
    // action carries it exactly as typed.
    final e = await pumpEditor(
      tester,
      text: 'caret line\nspacer line\nsee [[ a ]] now',
    );
    await park(tester, e.controller, 0);

    // On the `a`.
    await tester.tapAt(positionOf(tester, 2, 7));
    await tester.pump();

    expect(e.wikis, [' a ']);
    await teardownEditor(tester);
  });

  testWidgets('a claimed tap resolves the grammars exactly once', (
    tester,
  ) async {
    // B11: the interceptor asks twice — once to claim at tap-down, once
    // to act at tap-up. The claim memoizes its action, so the second ask
    // costs nothing while position, line text, selection and fence role
    // are unchanged.
    final e = await pumpEditor(tester, text: wikiDocument);
    await park(tester, e.controller, 0);

    ModernEditorWrapper.debugTapResolveCount = 0;
    await tester.tapAt(positionOf(tester, 2, 8));
    await tester.pump();

    expect(e.wikis, ['Squat']);
    expect(ModernEditorWrapper.debugTapResolveCount, 1);
    await teardownEditor(tester);
  });

  testWidgets('the caret (reveal) line passes through — its markdown is raw', (
    tester,
  ) async {
    final e = await pumpEditor(tester, text: wikiDocument);
    await park(tester, e.controller, 2);

    await tester.tapAt(positionOf(tester, 2, 8));
    await tester.pump();

    expect(e.wikis, isEmpty);
    expect(e.controller.selection.baseIndex, 2);
    expect(e.controller.selection.baseOffset, 8);
    await teardownEditor(tester);
  });

  testWidgets('fence lines pass through — fence text renders raw', (
    tester,
  ) async {
    final e = await pumpEditor(
      tester,
      text: 'caret line\n```\nsee [[Squat]] now\n```',
      fenceLines: {1, 2, 3},
    );
    await park(tester, e.controller, 0);

    await tester.tapAt(positionOf(tester, 2, 8));
    await tester.pump();

    expect(e.wikis, isEmpty);
    expect(e.controller.selection.baseIndex, 2);
    expect(e.controller.selection.baseOffset, 8);
    await teardownEditor(tester);
  });

  testWidgets('with no wiki handler the tap only places the caret', (
    tester,
  ) async {
    final e = await pumpEditor(tester, text: wikiDocument, wikiLinks: false);
    await park(tester, e.controller, 0);

    await tester.tapAt(positionOf(tester, 2, 8));
    await tester.pump();

    expect(e.wikis, isEmpty);
    expect(e.tags, isEmpty);
    expect(e.links, isEmpty);
    expect(e.controller.selection.baseIndex, 2);
    expect(e.controller.selection.baseOffset, 8);
    await teardownEditor(tester);
  });

  testWidgets('the wiki zone alone is enough to arm the interceptor', (
    tester,
  ) async {
    // The editor only builds a tap interceptor when at least one zone is
    // wired, and the disjunction has to include the newest one — with the
    // checkbox off and link / tag / money unwired there is nothing else
    // to enable it.
    final e = await pumpEditor(tester, text: wikiDocument, otherZones: false);
    await park(tester, e.controller, 0);

    await tester.tapAt(positionOf(tester, 2, 8));
    await tester.pump();

    expect(e.wikis, ['Squat']);
    expect(e.controller.selection.baseIndex, 0);
    await teardownEditor(tester);
  });

  testWidgets('a piped [[a|b]] is not a wiki link and passes through', (
    tester,
  ) async {
    // `see [[a|b]] now`: `[` 4, `[` 5, `a` 6, `|` 7. The grammar rejects
    // the pipe outright, so the whole construct is literal text.
    final e = await pumpEditor(
      tester,
      text: 'caret line\nspacer line\nsee [[a|b]] now',
    );
    await park(tester, e.controller, 0);

    await tester.tapAt(positionOf(tester, 2, 6));
    await tester.pump();

    expect(e.wikis, isEmpty);
    expect(e.controller.selection.baseIndex, 2);
    expect(e.controller.selection.baseOffset, 6);
    await teardownEditor(tester);
  });

  testWidgets('a ghost inside the brackets wins the tap and opens nothing', (
    tester,
  ) async {
    // `see [[a {{g}} b]] now`: the ghost atom [8, 13) starts before the
    // closing `]]`, so the tokenizer never forms a wiki link here at all
    // — and the tap rides the ghost's own selection change.
    final e = await pumpEditor(
      tester,
      text: 'caret line\nspacer line\nsee [[a {{g}} b]] now',
    );
    await park(tester, e.controller, 0);

    // On the `g`.
    await tester.tapAt(positionOf(tester, 2, 10));
    await tester.pump();
    await tester.pump();

    expect(e.wikis, isEmpty);
    final selection = e.controller.selection;
    expect(selection.baseIndex, 2);
    expect(selection.baseOffset, 8);
    expect(selection.extentIndex, 2);
    expect(selection.extentOffset, 13);
    await teardownEditor(tester);
  });

  testWidgets('a wiki link, a tag and a link on one line each fire their own', (
    tester,
  ) async {
    // `[[a]] #t [l](u)`: the wiki token runs [0, 5) so its zone is 1-4,
    // the tag [6, 8) so its zone is 7, and the link [9, 15) so its zone
    // is 10-14. Every tap below is intercepted, so the caret never
    // reaches line 2 and no tap turns it into the reveal line.
    final e = await pumpEditor(
      tester,
      text: 'caret line\nspacer line\n[[a]] #t [l](u)',
    );
    await park(tester, e.controller, 0);

    // On the `a` of the wiki title.
    await tester.tapAt(positionOf(tester, 2, 2));
    await tester.pump();
    expect(e.wikis, ['a']);
    expect(e.tags, isEmpty);
    expect(e.links, isEmpty);

    // On the `t` of the tag.
    await tester.tapAt(positionOf(tester, 2, 7));
    await tester.pump();
    expect(e.tags, ['#t']);
    expect(e.wikis, ['a']);
    expect(e.links, isEmpty);

    // On the `l` of the link text.
    await tester.tapAt(positionOf(tester, 2, 10));
    await tester.pump();
    expect(e.links, ['u']);
    expect(e.wikis, ['a']);
    expect(e.tags, ['#t']);

    expect(e.controller.selection.baseIndex, 0);
    await teardownEditor(tester);
  });

  testWidgets('binding onOpenWikiLink on a rebuild makes the zone live', (
    tester,
  ) async {
    // The enabled-zone set and the zone memo are both resolved once per
    // widget configuration, so a host that flips the callback on without
    // remounting has to invalidate both — otherwise the zone stays dead
    // for the life of the page.
    final wikis = <String>[];
    final controller = CodeLineEditingController.fromText(wikiDocument);
    final searchController = ReEditorSearchController();
    final scrollController = CodeScrollController();
    final focusNode = FocusNode();
    addTearDown(() {
      focusNode.dispose();
      searchController.dispose();
      controller.dispose();
    });

    Widget wrap({required bool wikiLinks}) => MaterialApp(
      home: Scaffold(
        body: ModernEditorWrapper(
          controller: controller,
          focusNode: focusNode,
          scrollController: scrollController,
          searchController: searchController,
          editorFontSize: fontSize,
          onTextChanged: () {},
          wordWrap: false,
          checkboxTapToggle: true,
          onOpenWikiLink: wikiLinks ? wikis.add : null,
          showScrollIndicator: false,
        ),
      ),
    );

    await tester.pumpWidget(wrap(wikiLinks: false));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(ModernEditorWrapper));
    await park(tester, controller, 0);

    await tester.tapAt(positionOf(tester, 2, 8));
    await tester.pump();
    expect(wikis, isEmpty);
    expect(controller.selection.baseIndex, 2);

    await tester.pumpWidget(wrap(wikiLinks: true));
    await tester.pumpAndSettle();
    // The flip must be an update, not a remount — otherwise this pins
    // nothing about `didUpdateWidget`.
    expect(tester.state(find.byType(ModernEditorWrapper)), same(state));
    await park(tester, controller, 0);

    await tester.tapAt(positionOf(tester, 2, 8));
    await tester.pump();

    expect(wikis, ['Squat']);
    expect(controller.selection.baseIndex, 0);
    await teardownEditor(tester);
  });
}
