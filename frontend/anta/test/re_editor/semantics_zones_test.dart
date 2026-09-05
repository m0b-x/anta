import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'support/editor_test_support.dart';

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
  const double viewportWidth = 300.0;
  const double viewportHeight = 200.0;
  const String label = 'zone';
  const int zoneStart = 2;
  const int zoneEnd = 5;
  const TextRange zoneRange = TextRange(start: zoneStart, end: zoneEnd);
  const Set<int> zoneLines = {0, 2};
  const String marker = 'zone';

  String buildDocument(int lineCount) {
    return List<String>.generate(lineCount, (i) => 'line $i').join('\n');
  }

  String buildMarkedDocument(int lineCount) {
    return List<String>.generate(
      lineCount,
      (i) => zoneLines.contains(i) ? '$marker $i xxxx' : 'line $i',
    ).join('\n');
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
    bool zonesFollowText = false,
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
              final bool carries = zonesFollowText
                  ? controller.codeLines[lineIndex].text.startsWith(marker)
                  : zoneLines.contains(lineIndex);
              if (!carries) {
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
                style: const CodeEditorStyle(fontSize: kTestFontSize),
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

  /// The zone's rect as the render should have expressed it: the
  /// paragraph's own range rects, unioned, shifted by the paragraph's
  /// scroll-adjusted offset. The notifier hands out exactly those
  /// offsets (`paragraph.offset - paintOffset`), so this is the
  /// render-local space the field's child nodes live in.
  Rect expectedZoneRect(CodeIndicatorValueNotifier notifier, int lineIndex) {
    final paragraph = displayedParagraphs(
      notifier,
    ).firstWhere((p) => p.index == lineIndex);
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

  testWidgets('one node per enumerated zone, covering the range it names', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester, text: buildDocument(6));
    await settle(tester);

    final nodes = find.semantics.byLabel(label).evaluate().toList();
    expect(nodes, hasLength(2));

    for (var i = 0; i < nodes.length; i++) {
      final lineIndex = zoneLines.elementAt(i);
      expect(nodes[i].parent, textFieldNode());
      expect(rectInParent(nodes[i]), expectedZoneRect(e.notifier, lineIndex));
      expect(
        nodes[i].getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
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
    expect(e.tapped, [const CodeLinePosition(index: 0, offset: zoneStart)]);
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

  testWidgets('a zone scrolled out of the window loses its node', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester, text: buildDocument(200));
    await settle(tester);
    expect(find.semantics.byLabel(label), findsExactly(2));

    e.controller.makePositionVisible(
      const CodeLinePosition(index: 120, offset: 0),
    );
    await settle(tester);

    final visible = displayedIndices(e.notifier).toSet();
    expect(visible.contains(0), isFalse);
    expect(visible.contains(2), isFalse);
    expect(find.semantics.byLabel(label), findsNothing);

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('without an interceptor the text field has no children', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpEditor(tester, text: buildDocument(6), withInterceptor: false);
    await settle(tester);

    expect(find.semantics.byLabel(label), findsNothing);
    expect(textFieldNode().childrenCount, 0);

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('an interceptor without zonesOf contributes no children', (
    tester,
  ) async {
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

  /// What the framework does to the render tree when the platform
  /// disposes the semantics owner (`RendererBinding` calls it from
  /// `onSemanticsOwnerDisposed`). An accessibility dump on Android
  /// enables semantics in a burst, so this runs between two builds of
  /// the same tree — and any node held across it belongs to a disposed
  /// owner.
  void tearDownSemantics(WidgetTester tester) {
    tester.renderObject(find.byType(CodeEditor)).clearSemantics();
  }

  /// Dirties the field's semantics without touching the text, so the
  /// next flush rebuilds the child nodes.
  Future<void> rebuildSemantics(
    WidgetTester tester,
    CodeLineEditingController controller,
    int caretLine,
  ) async {
    controller.selection = CodeLineSelection.collapsed(
      index: caretLine,
      offset: 0,
    );
    await settle(tester);
  }

  List<int> zoneIds() =>
      find.semantics.byLabel(label).evaluate().map((n) => n.id).toList();

  testWidgets('a plain semantics rebuild keeps the same zone nodes', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester, text: buildDocument(6));
    await settle(tester);
    final before = zoneIds();
    expect(before, hasLength(2));

    tester.renderObject(find.byType(CodeEditor)).markNeedsSemanticsUpdate();
    await settle(tester);
    expect(zoneIds(), before);

    await rebuildSemantics(tester, e.controller, 4);
    expect(
      zoneIds(),
      before,
      reason:
          'the keyed cache exists so an unrelated rebuild does not hand '
          'the platform a new node for an unchanged zone',
    );

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('a line inserted above the zones renumbers their nodes', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(
      tester,
      text: buildMarkedDocument(6),
      zonesFollowText: true,
    );
    await settle(tester);
    final before = zoneIds();
    expect(before, hasLength(2));

    e.controller.selection = const CodeLineSelection.collapsed(
      index: 0,
      offset: 0,
    );
    e.controller.replaceSelection('\n');
    await settle(tester);

    final after = zoneIds();
    expect(after, hasLength(2));
    expect(
      after.toSet().intersection(before.toSet()),
      isEmpty,
      reason:
          'the cache key carries the line index, so a zone that shifts '
          'down is a new node: the accepted cost of keying by line',
    );

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('a semantics teardown drops the zone node cache', (tester) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester, text: buildDocument(6));
    await settle(tester);
    final before = zoneIds();
    expect(before, hasLength(2));

    tearDownSemantics(tester);
    await rebuildSemantics(tester, e.controller, 4);

    expect(tester.takeException(), isNull);
    final after = zoneIds();
    expect(after, hasLength(2));
    expect(after.toSet().intersection(before.toSet()), isEmpty);

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('a window that moved across a teardown rebuilds cleanly', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester, text: buildDocument(200));
    await settle(tester);
    final before = zoneIds();
    expect(before, hasLength(2));

    tearDownSemantics(tester);
    e.controller.makePositionVisible(
      const CodeLinePosition(index: 120, offset: 0),
    );
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.semantics.byLabel(label), findsNothing);

    e.controller.makePositionVisible(
      const CodeLinePosition(index: 0, offset: 0),
    );
    await settle(tester);

    expect(tester.takeException(), isNull);
    final after = zoneIds();
    expect(after, hasLength(2));
    expect(after.toSet().intersection(before.toSet()), isEmpty);

    handle.dispose();
    await teardownEditor(tester);
  });

  testWidgets('repeated teardowns never reuse a node from an earlier tree', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final e = await pumpEditor(tester, text: buildDocument(6));
    await settle(tester);

    final seen = <int>{...zoneIds()};
    expect(seen, hasLength(2));

    for (var i = 0; i < 3; i++) {
      tearDownSemantics(tester);
      await rebuildSemantics(tester, e.controller, i + 3);

      expect(tester.takeException(), isNull, reason: 'pass $i');
      final ids = zoneIds();
      expect(ids, hasLength(2), reason: 'pass $i');
      expect(seen.intersection(ids.toSet()), isEmpty, reason: 'pass $i');
      seen.addAll(ids);
    }

    handle.dispose();
    await teardownEditor(tester);
  });
}
