import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/constants/app_spacing.dart';
import 'package:anta/controllers/editor_render_controller.dart';
import 'package:anta/utils/markdown_editor_paint_spans.dart';
import 'package:anta/utils/re_editor_search_controller.dart';
import 'package:anta/widgets/modern_editor_wrapper.dart';

/// E5: the caret line reveals its raw markers only while the editor holds
/// focus. A note opens with the caret at 0:0 and no focus, and its first
/// line used to render raw with a box that did nothing — a tap on it
/// placed the caret and raised the keyboard instead of ticking it.
///
/// Unlike the other wrapper suites this one renders live markdown, the
/// way the page does: the controller's span builder routes through an
/// [EditorRenderController] bound to the same focus node the wrapper's
/// taps read, so the spans the editor actually laid out can be inspected
/// and the render and the tap policy are proven to agree. Every tap aims
/// at column 0 of the task line, which is inside the toggle zone however
/// the box changes the glyph widths.
///
/// Harness notes are the same as `modern_editor_wrapper_tag_tap_test.dart`.
void main() {
  const fontSize = 16.0;
  const taskLine = '- [ ] squat 5x5';
  const document = '$taskLine\nplain line\nanother line';

  double lineBoxOf(WidgetTester tester) => CodeFieldRenderForTesting.of(
    tester.renderObject(find.byType(CodeEditor)),
  ).lineHeight;

  /// The global position of column 0 on line [line], biased into the
  /// line's first glyph.
  Offset lineStartOf(WidgetTester tester, int line) {
    final origin = tester.getTopLeft(find.byType(CodeEditor));
    final lineBox = lineBoxOf(tester);
    return origin +
        Offset(AppSpacing.xl + 2, AppSpacing.lg + line * lineBox + lineBox / 2);
  }

  /// Mounts the wrapper over [document] with live rendering, recording
  /// the last span the editor built for each line.
  Future<
    ({
      CodeLineEditingController controller,
      FocusNode focusNode,
      Map<int, TextSpan> built,
    })
  >
  pumpEditor(WidgetTester tester) async {
    final built = <int, TextSpan>{};
    final render = EditorRenderController();
    final controller = CodeLineEditingController(
      spanBuilder:
          ({
            required BuildContext context,
            required int index,
            required CodeLine codeLine,
            required TextSpan textSpan,
            required TextStyle style,
          }) => built[index] = render.buildSpan(
            context: context,
            index: index,
            codeLine: codeLine,
            textSpan: textSpan,
            style: style,
            liveRendering: true,
          ),
    )..loadText(document);
    final searchController = ReEditorSearchController();
    final scrollController = CodeScrollController();
    final focusNode = FocusNode();
    render
      ..bind(controller)
      ..bindFocus(focusNode);
    addTearDown(() {
      render.bindFocus(null);
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
            showScrollIndicator: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (controller: controller, focusNode: focusNode, built: built);
  }

  bool paintsBox(TextSpan? span) {
    var found = false;
    span?.visitChildren((child) {
      if (child is EditorCheckboxSpan) found = true;
      return !found;
    });
    return found;
  }

  Future<void> teardownEditor(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('an unfocused editor paints the box under the caret and a tap '
      'toggles it', (tester) async {
    final e = await pumpEditor(tester);
    expect(e.focusNode.hasFocus, isFalse);
    expect(
      e.controller.selection,
      const CodeLineSelection.collapsed(index: 0, offset: 0),
      reason: 'a note opens with the caret on its first line',
    );
    expect(paintsBox(e.built[0]), isTrue, reason: 'nothing reveals line 0');

    await tester.tapAt(lineStartOf(tester, 0));
    await tester.pump();

    expect(e.controller.codeLines[0].text, '- [x] squat 5x5');
    expect(
      e.controller.selection,
      const CodeLineSelection.collapsed(index: 0, offset: 0),
    );
    expect(e.focusNode.hasFocus, isFalse, reason: 'a toggle never focuses');
    await teardownEditor(tester);
  });

  testWidgets('a focused editor with the caret in the marker shows it raw '
      'and a tap edits', (tester) async {
    final e = await pumpEditor(tester);
    e.focusNode.requestFocus();
    await tester.pump();
    e.controller.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 3,
    );
    await tester.pump();
    expect(paintsBox(e.built[0]), isFalse, reason: 'the marker reveals raw');

    await tester.tapAt(lineStartOf(tester, 0));
    await tester.pump();

    expect(e.controller.codeLines[0].text, taskLine);
    expect(e.controller.selection.baseIndex, 0);
    expect(e.controller.selection.baseOffset, 0);
    await teardownEditor(tester);
  });

  testWidgets('a focus change re-renders the caret line', (tester) async {
    final e = await pumpEditor(tester);
    expect(paintsBox(e.built[0]), isTrue);

    // A focus change applies in a microtask after the first pump's frame,
    // so the rebuild it triggers lands one frame later.
    e.focusNode.requestFocus();
    await tester.pump();
    await tester.pump();
    expect(e.focusNode.hasFocus, isTrue);
    expect(
      paintsBox(e.built[0]),
      isFalse,
      reason: 'gaining focus relays the caret line out revealed',
    );

    e.focusNode.unfocus();
    await tester.pump();
    await tester.pump();
    expect(e.focusNode.hasFocus, isFalse);
    expect(
      paintsBox(e.built[0]),
      isTrue,
      reason: 'losing focus relays it out concealed',
    );
    await teardownEditor(tester);
  });
}
