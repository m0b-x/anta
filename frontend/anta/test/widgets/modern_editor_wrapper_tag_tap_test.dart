import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/constants/app_spacing.dart';
import 'package:anta/constants/markdown_constants.dart';
import 'package:anta/utils/re_editor_search_controller.dart';
import 'package:anta/widgets/modern_editor_wrapper.dart';

/// The editor's `#tag` tap zone. Tags conceal and substitute nothing, so
/// the tapped offset maps 1:1 onto source code units — which is exactly
/// what makes the zone testable by geometry: the widget-test font
/// advances every glyph by the font size, so column `n` of line `l` sits
/// at a position we can compute.
///
/// What matters here is not that a tap on a tag fires, but that all the
/// link zone's pass-through rules still win over it: the caret (reveal)
/// line, fence lines, and plain text keep placing the caret, and the
/// link zone — resolved first — still wins on a line that carries both.
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

  /// Mounts the wrapper over [text] and records every tag / link tap.
  Future<({List<String> tags, List<String> links, CodeLineEditingController
      controller})>
  pumpEditor(
    WidgetTester tester, {
    required String text,
    Set<int> fenceLines = const {},
  }) async {
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
            checkboxTapToggle: true,
            onOpenLink: links.add,
            onOpenTag: tags.add,
            isFenceLine: fenceLines.contains,
            showScrollIndicator: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (tags: tags, links: links, controller: controller);
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

  testWidgets('a tap resolves to the column it lands on', (tester) async {
    // Calibration: every assertion below reads a column, so the mapping
    // from position to source offset has to be pinned first. Line 1 has
    // no zones, so the tap falls through to plain caret placement.
    final e = await pumpEditor(tester, text: 'first line\nplain second line');

    await tester.tapAt(positionOf(tester, 1, 6));
    await tester.pump();

    expect(e.controller.selection.baseIndex, 1);
    expect(e.controller.selection.baseOffset, 6);
    await teardownEditor(tester);
  });

  testWidgets('tapping a #tag off the caret line fires onOpenTag with the '
      'leading #', (tester) async {
    final e = await pumpEditor(tester, text: 'caret line\nsee #project now');

    // Park the caret on line 0 so line 1 is not the reveal line.
    await tester.tapAt(positionOf(tester, 0, 3));
    await tester.pump();
    expect(e.controller.selection.baseIndex, 0);

    await tester.tapAt(positionOf(tester, 1, 6));
    await tester.pump();

    expect(e.tags, ['#project']);
    // An intercepted tap never moves the caret and never raises focus.
    expect(e.controller.selection.baseIndex, 0);
    expect(e.controller.selection.baseOffset, 3);
    await teardownEditor(tester);
  });

  testWidgets('the caret (reveal) line passes through — its markdown is raw',
      (tester) async {
    final e = await pumpEditor(tester, text: 'see #project now\nsecond');

    await tester.tapAt(positionOf(tester, 0, 6));
    await tester.pump();

    expect(e.tags, isEmpty);
    expect(e.controller.selection.baseIndex, 0);
    expect(e.controller.selection.baseOffset, 6);
    await teardownEditor(tester);
  });

  testWidgets('fence lines pass through — fence text renders raw',
      (tester) async {
    final e = await pumpEditor(
      tester,
      text: 'caret line\n```\nsee #project now\n```',
      fenceLines: {1, 2, 3},
    );

    await tester.tapAt(positionOf(tester, 0, 3));
    await tester.pump();
    await tester.tapAt(positionOf(tester, 2, 6));
    await tester.pump();

    expect(e.tags, isEmpty);
    expect(e.controller.selection.baseIndex, 2);
    expect(e.controller.selection.baseOffset, 6);
    await teardownEditor(tester);
  });

  testWidgets('plain text and a bare # do not fire', (tester) async {
    final e = await pumpEditor(
      tester,
      text: 'caret line\nplain words and set #1 here',
    );

    await tester.tapAt(positionOf(tester, 0, 3));
    await tester.pump();
    // Inside "words".
    await tester.tapAt(positionOf(tester, 1, 8));
    await tester.pump();
    // Inside the digit-led `#1`, which the grammar never treats as a tag.
    await tester.tapAt(positionOf(tester, 1, 21));
    await tester.pump();

    expect(e.tags, isEmpty);
    await teardownEditor(tester);
  });

  testWidgets('a link on the same line still opens, and the tag beside it '
      'still searches', (tester) async {
    final e = await pumpEditor(
      tester,
      text: 'caret line\n#note [docs](https://x.dev) end',
    );

    await tester.tapAt(positionOf(tester, 0, 3));
    await tester.pump();

    // Inside `note` — the tag.
    await tester.tapAt(positionOf(tester, 1, 2));
    await tester.pump();
    // Inside `docs` — the link text.
    await tester.tapAt(positionOf(tester, 1, 9));
    await tester.pump();

    expect(e.tags, ['#note']);
    expect(e.links, ['https://x.dev']);
    await teardownEditor(tester);
  });

  testWidgets('a tag inside an inline-code run passes through', (tester) async {
    final e = await pumpEditor(
      tester,
      text: 'caret line\nrun `git tag #v1x` now',
    );

    await tester.tapAt(positionOf(tester, 0, 3));
    await tester.pump();
    await tester.tapAt(positionOf(tester, 1, 15));
    await tester.pump();

    expect(e.tags, isEmpty);
    await teardownEditor(tester);
  });

  testWidgets('a tag inside a ghost run passes through — ghosts win',
      (tester) async {
    final e = await pumpEditor(
      tester,
      text: 'caret line\nfill {{ #topic }} in',
    );

    await tester.tapAt(positionOf(tester, 0, 3));
    await tester.pump();
    await tester.tapAt(positionOf(tester, 1, 11));
    await tester.pump();

    expect(e.tags, isEmpty);
    await teardownEditor(tester);
  });

  testWidgets('a heading line taps its own #tag, never its hashes',
      (tester) async {
    final e = await pumpEditor(tester, text: 'caret line\n## Title #done');

    await tester.tapAt(positionOf(tester, 0, 3));
    await tester.pump();
    // On the heading hashes — never a tag, so this falls through and
    // takes the caret with it, which is why the caret has to be parked
    // back on line 0 before the tag half of the case.
    await tester.tapAt(positionOf(tester, 1, 1));
    await tester.pump();
    expect(e.tags, isEmpty);
    expect(e.controller.selection.baseIndex, 1);

    await tester.tapAt(positionOf(tester, 0, 3));
    await tester.pump();
    // Inside `done`.
    await tester.tapAt(positionOf(tester, 1, 12));
    await tester.pump();
    expect(e.tags, ['#done']);
    await teardownEditor(tester);
  });

  testWidgets('a claimed tap resolves the grammars exactly once', (tester) async {
    // B11: the interceptor asks twice — once to claim at tap-down, once
    // to act at tap-up. The claim memoizes its action, so the second ask
    // costs nothing while position, line text, selection and fence role
    // are unchanged.
    final e = await pumpEditor(tester, text: 'caret line\nsee #project now');

    await tester.tapAt(positionOf(tester, 0, 3));
    await tester.pump();

    ModernEditorWrapper.debugTapResolveCount = 0;
    await tester.tapAt(positionOf(tester, 1, 6));
    await tester.pump();

    expect(e.tags, ['#project']);
    expect(ModernEditorWrapper.debugTapResolveCount, 1);
    await teardownEditor(tester);
  });

  testWidgets('a pass-through tap resolves once and leaves no stale claim',
      (tester) async {
    // A failed claim must not memoize anything: the next claimed tap has
    // to resolve for itself rather than reuse the previous position's
    // answer.
    final e = await pumpEditor(tester, text: 'caret line\nsee #project now');

    ModernEditorWrapper.debugTapResolveCount = 0;
    // Plain text on line 0 — no zone, so only the tap-down ask happens.
    await tester.tapAt(positionOf(tester, 0, 3));
    await tester.pump();
    expect(ModernEditorWrapper.debugTapResolveCount, 1);

    ModernEditorWrapper.debugTapResolveCount = 0;
    await tester.tapAt(positionOf(tester, 1, 6));
    await tester.pump();

    expect(e.tags, ['#project']);
    expect(ModernEditorWrapper.debugTapResolveCount, 1);
    await teardownEditor(tester);
  });
}
