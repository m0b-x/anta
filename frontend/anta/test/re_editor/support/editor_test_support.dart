/// Harness shared by the `test/re_editor/` suites: pumping a bare
/// [CodeEditor], settling it, reading its display window back, and the
/// semantics finders every accessibility suite needs.
///
/// The editor is settled frame by frame rather than with `pumpAndSettle`
/// (the cursor blink never settles), and the tree is taken down through
/// [teardownEditor] so the fork's pending 100 ms `Future.delayed` loops
/// elapse before the element goes away.
///
/// Nothing here reads `kIsAndroid` / `kIsIOS`: those are top-level
/// `final`s in the fork, resolved when the first editor is built and
/// then fixed for the whole test process, so a suite that needs the
/// desktop path must resolve them itself before calling any of this.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// The widget-test font advances every glyph by the font size, so a
/// column index times this is an exact x offset — see [zoneCellOf].
const double kTestFontSize = 14.0;

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

Future<void> flushDeferredWork(WidgetTester tester) async {
  await tester.pump(Duration.zero);
  await tester.idle();
  await tester.pump(Duration.zero);
}

List<String> watchTextInput(WidgetTester tester) {
  final methods = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.textInput,
    (MethodCall call) async {
      methods.add(call.method);
      return null;
    },
  );
  addTearDown(tester.testTextInput.register);
  return methods;
}

SemanticsFinder textField() => find.semantics.byFlag(SemanticsFlag.isTextField);

SemanticsNode textFieldNode() {
  final finder = textField();
  expect(finder, findsOne);
  return finder.evaluate().single;
}

List<CodeLineRenderParagraph> displayedParagraphs(
  CodeIndicatorValueNotifier notifier,
) {
  return notifier.value?.paragraphs ?? const <CodeLineRenderParagraph>[];
}

List<int> displayedIndices(CodeIndicatorValueNotifier notifier) {
  return displayedParagraphs(notifier).map((p) => p.index).toList();
}

String expectedWindow(
  CodeIndicatorValueNotifier notifier,
  CodeLineEditingController controller,
) {
  return displayedIndices(
    notifier,
  ).map((index) => controller.codeLines[index].text).join('\n');
}

typedef ZoneEditor = ({
  CodeLineEditingController controller,
  FocusNode focusNode,
  CodeIndicatorValueNotifier notifier,
  List<CodeLinePosition> taps,
});

/// A bare [CodeEditor] whose interceptor claims line 0, offsets 0-2 —
/// the fixture both `tap_interceptor_test.dart` (mobile gesture path)
/// and `tap_interceptor_desktop_test.dart` (pointer path) drive.
Future<ZoneEditor> pumpZoneEditor(
  WidgetTester tester, {
  required String text,
}) async {
  final controller = CodeLineEditingController.fromText(text);
  final focusNode = FocusNode();
  final taps = <CodeLinePosition>[];
  late CodeIndicatorValueNotifier notifier;
  addTearDown(() {
    focusNode.dispose();
    controller.dispose();
  });

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CodeEditor(
          controller: controller,
          focusNode: focusNode,
          autofocus: false,
          padding: EdgeInsets.zero,
          style: const CodeEditorStyle(fontSize: kTestFontSize),
          tapInterceptor: CodeEditorTapInterceptor(
            shouldIntercept: (pos) => pos.index == 0 && pos.offset < 3,
            onTap: taps.add,
          ),
          indicatorBuilder: (context, editing, chunk, valueNotifier) {
            notifier = valueNotifier;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return (
    controller: controller,
    focusNode: focusNode,
    notifier: notifier,
    taps: taps,
  );
}

/// The centre of one text cell in global coordinates. The column is
/// exact from the font's advance, but the vertical position of a line is
/// read back from the editor's own [CodeIndicatorValueNotifier] rather
/// than assumed, since these suites set no explicit `fontHeight`.
Offset zoneCellOf(
  WidgetTester tester,
  CodeIndicatorValueNotifier notifier,
  int line,
  int column,
) {
  final origin = tester.getTopLeft(find.byType(CodeEditor));
  final paragraph = displayedParagraphs(
    notifier,
  ).firstWhere((p) => p.index == line);
  return origin +
      Offset(column * kTestFontSize + 2, paragraph.top + paragraph.height / 2);
}

typedef ScrollEditor = ({
  CodeLineEditingController controller,
  CodeScrollController scroll,
  CodeIndicatorValueNotifier notifier,
});

/// A [CodeEditor] in a fixed [width] x [height] box with a scroll
/// controller the caller can read pixels off — the fixture for the
/// scroll-helper and line-height suites.
///
/// Lines listed in [scaledLines] get a root span at twice the base font
/// size, which is how the app's markdown headers become taller than the
/// base line height (the root keeps `fontFamily`/`height` untouched, or
/// the fork's strut assert fires).
Future<ScrollEditor> pumpScrollEditor(
  WidgetTester tester, {
  required String text,
  required double width,
  required double height,
  bool wordWrap = true,
  Set<int> scaledLines = const <int>{},
}) async {
  TextSpan buildSpan({
    required BuildContext context,
    required int index,
    required CodeLine codeLine,
    required TextSpan textSpan,
    required TextStyle style,
  }) {
    if (!scaledLines.contains(index)) {
      return textSpan;
    }
    final TextStyle scaled = style.copyWith(fontSize: style.fontSize! * 2);
    return TextSpan(
      style: scaled,
      children: [TextSpan(text: codeLine.text, style: scaled)],
    );
  }

  final controller = CodeLineEditingController(
    spanBuilder: scaledLines.isEmpty ? null : buildSpan,
  )..loadText(text);
  final scroll = CodeScrollController();
  final focusNode = FocusNode();
  late CodeIndicatorValueNotifier notifier;
  addTearDown(() {
    focusNode.dispose();
    scroll.dispose();
    controller.dispose();
  });

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: CodeEditor(
              controller: controller,
              scrollController: scroll,
              focusNode: focusNode,
              autofocus: false,
              wordWrap: wordWrap,
              padding: EdgeInsets.zero,
              style: const CodeEditorStyle(fontSize: kTestFontSize),
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
  return (controller: controller, scroll: scroll, notifier: notifier);
}

/// Vertical scroll offset of a [pumpScrollEditor] fixture.
double pixelsOf(CodeScrollController scroll) =>
    scroll.verticalScroller.position.pixels;

/// The displayed paragraph for [index], or null when that line is
/// outside the render's current window.
CodeLineRenderParagraph? displayedParagraphAt(
  CodeIndicatorValueNotifier notifier,
  int index,
) {
  for (final CodeLineRenderParagraph paragraph in displayedParagraphs(
    notifier,
  )) {
    if (paragraph.index == index) {
      return paragraph;
    }
  }
  return null;
}

void expectSameSelection(CodeLineSelection a, CodeLineSelection b) {
  expect(a.baseIndex, b.baseIndex);
  expect(a.baseOffset, b.baseOffset);
  expect(a.extentIndex, b.extentIndex);
  expect(a.extentOffset, b.extentOffset);
}
