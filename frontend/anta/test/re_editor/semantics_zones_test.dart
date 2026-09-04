import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// The editor's interactive text regions are pointer-only by nature: the
/// host claims a tap at a text position, and nothing about that is
/// reachable to a screen reader. `CodeEditorTapInterceptor.zonesOf` is
/// the answer — it enumerates the ranges, and the render turns each into
/// a child node of the text field with a label and a tap action.
///
/// What is pinned here is the fork's half of that contract: one node per
/// zone per *visible* line, each covering exactly the cells the range
/// paints on, a tap running the interceptor's own two-step
/// (`shouldIntercept` then `onTap`) without moving the caret, and the
/// text field's own value surviving underneath the children.
///
/// Harness notes are the same as `semantics_value_test.dart`: the
/// semantics handle is disposed before the tree comes down, and the
/// editor is settled frame by frame rather than with `pumpAndSettle`
/// (the cursor blink never settles).
void main() {
  const double fontSize = 14.0;
  const double viewportWidth = 300.0;
  const double viewportHeight = 200.0;
  const String label = 'zone';
  const int zoneStart = 2;
  const int zoneEnd = 5;
  const TextRange zoneRange = TextRange(start: zoneStart, end: zoneEnd);
  const Set<int> zoneLines = {0, 2};

  String buildDocument(int lineCount) {
    return List<String>.generate(lineCount, (i) => 'line $i').join('\n');
  }

  Future<
    ({
      CodeLineEditingController controller,
      CodeIndicatorValueNotifier notifier,
      List<CodeLinePosition> intercepted,
      List<CodeLinePosition> tapped,
      List<int> enumerated,
    })
  >
  pumpEditor(
    WidgetTester tester, {
    required String text,
    bool withInterceptor = true,
    bool withZones = true,
  }) async {
    final controller = CodeLineEditingController.fromText(text);
    final scroll = CodeScrollController();
    final focusNode = FocusNode();
    final intercepted = <CodeLinePosition>[];
    final tapped = <CodeLinePosition>[];
    final enumerated = <int>[];
    late CodeIndicatorValueNotifier notifier;
    addTearDown(() {
      focusNode.dispose();
      scroll.dispose();
      controller.dispose();
    });

    final interceptor = CodeEditorTapInterceptor(
      shouldIntercept: (position) {
        intercepted.add(position);
        return zoneLines.contains(position.index);
      },
      onTap: tapped.add,
      zonesOf: withZones
          ? (lineIndex) {
              enumerated.add(lineIndex);
              if (!zoneLines.contains(lineIndex)) {
                return const <CodeEditorSemanticsZone>[];
              }
              return const [
                CodeEditorSemanticsZone(
                  start: zoneStart,
                  end: zoneEnd,
                  label: label,
                ),
              ];
            }
          : null,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: viewportWidth,
              height: viewportHeight,
              child: CodeEditor(
                controller: controller,
                scrollController: scroll,
                focusNode: focusNode,
                autofocus: false,
                wordWrap: true,
                padding: EdgeInsets.zero,
                style: const CodeEditorStyle(fontSize: fontSize),
                tapInterceptor: withInterceptor ? interceptor : null,
                indicatorBuilder: (context, editing, chunk, valueNotifier) {
                  notifier = valueNotifier;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return (
      controller: controller,
      notifier: notifier,
      intercepted: intercepted,
      tapped: tapped,
      enumerated: enumerated,
    );
  }

  Future<void> teardownEditor(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester, [int frames = 14]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  SemanticsNode textFieldNode() {
    final finder = find.semantics.byFlag(SemanticsFlag.isTextField);
    expect(finder, findsOne);
    return finder.evaluate().single;
  }

  List<CodeLineRenderParagraph> paragraphs(
    CodeIndicatorValueNotifier notifier,
  ) {
    return notifier.value?.paragraphs ?? const <CodeLineRenderParagraph>[];
  }

  String expectedWindow(
    CodeIndicatorValueNotifier notifier,
    CodeLineEditingController controller,
  ) {
    return paragraphs(
      notifier,
    ).map((p) => controller.codeLines[p.index].text).join('\n');
  }

  /// The zone's rect as the render should have expressed it: the
  /// paragraph's own range rects, unioned, shifted by the paragraph's
  /// scroll-adjusted offset. The notifier hands out exactly those
  /// offsets (`paragraph.offset - paintOffset`), so this is the
  /// render-local space the field's child nodes live in.
  Rect expectedZoneRect(CodeIndicatorValueNotifier notifier, int lineIndex) {
    final paragraph = paragraphs(notifier).firstWhere(
      (p) => p.index == lineIndex,
    );
    final rects = paragraph.getRangeRects(zoneRange);
    expect(rects, isNotEmpty);
    var rect = rects.first;
    for (final part in rects.skip(1)) {
      rect = rect.expandToInclude(part);
    }
    return rect.shift(paragraph.offset);
  }

  /// A zone node's rect in its parent's (the text field's) coordinate
  /// space — the space the render builds them in.
  Rect rectInParent(SemanticsNode node) {
    final transform = node.transform;
    return transform == null
        ? node.rect
        : MatrixUtils.transformRect(transform, node.rect);
  }

  testWidgets('one node per enumerated zone, covering the range it names',
      (tester) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester, text: buildDocument(6));
    await settle(tester);

    final nodes = find.semantics.byLabel(label).evaluate().toList();
    expect(nodes, hasLength(2));

    for (var i = 0; i < nodes.length; i++) {
      final lineIndex = zoneLines.elementAt(i);
      expect(nodes[i].parent, textFieldNode());
      expect(rectInParent(nodes[i]), expectedZoneRect(e.notifier, lineIndex));
      expect(nodes[i].getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    }

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('tapping a zone node runs shouldIntercept then onTap and '
      'leaves the caret alone', (tester) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester, text: buildDocument(6));
    await settle(tester);

    final selection = e.controller.selection;
    e.intercepted.clear();
    e.tapped.clear();

    tester.semantics.tap(find.semantics.byLabel(label).first);
    await tester.pump();

    expect(e.intercepted, [
      const CodeLinePosition(index: 0, offset: zoneStart),
    ]);
    expect(e.tapped, [
      const CodeLinePosition(index: 0, offset: zoneStart),
    ]);
    expect(e.controller.selection, selection);

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('the text field keeps its visible-window value and reads '
      'before its zones', (tester) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester, text: buildDocument(6));
    await settle(tester);

    final window = expectedWindow(e.notifier, e.controller);
    expect(window, isNotEmpty);
    expect(textFieldNode().value, window);

    expect(
      tester.semantics.simulatedAccessibilityTraversal(),
      containsAllInOrder(<Matcher>[
        isSemantics(value: window, isTextField: true),
        isSemantics(label: label),
        isSemantics(label: label),
      ]),
    );

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('a zone scrolled out of the window loses its node',
      (tester) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester, text: buildDocument(200));
    await settle(tester);
    expect(find.semantics.byLabel(label), findsExactly(2));

    e.controller.makePositionVisible(
      const CodeLinePosition(index: 120, offset: 0),
    );
    await settle(tester);

    final visible = paragraphs(e.notifier).map((p) => p.index).toSet();
    expect(visible.contains(0), isFalse);
    expect(visible.contains(2), isFalse);
    expect(find.semantics.byLabel(label), findsNothing);

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('without an interceptor the text field has no children',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpEditor(
      tester,
      text: buildDocument(6),
      withInterceptor: false,
    );
    await settle(tester);

    expect(find.semantics.byLabel(label), findsNothing);
    expect(textFieldNode().childrenCount, 0);

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('an interceptor without zonesOf contributes no children',
      (tester) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(
      tester,
      text: buildDocument(6),
      withZones: false,
    );
    await settle(tester);

    expect(find.semantics.byLabel(label), findsNothing);
    expect(textFieldNode().childrenCount, 0);
    expect(e.enumerated, isEmpty);

    handle.dispose();
    await teardownEditor(tester);
  });
}
