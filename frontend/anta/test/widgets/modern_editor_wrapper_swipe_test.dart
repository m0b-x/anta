import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/constants/app_spacing.dart';
import 'package:anta/utils/line_swipe_policy.dart';
import 'package:anta/utils/re_editor_search_controller.dart';
import 'package:anta/widgets/modern_editor_wrapper.dart';

/// D2 of the list-nesting record: a horizontal swipe on the focused
/// editor's caret line, when that line is a list item, nests it one level
/// per swipe with Tab's own edit. The predicate is a pure table; the
/// wrapper cases drive the touch path (`kIsAndroid` is true in widget
/// tests) and compare the swipe's edit with the hardware Tab's.
void main() {
  group('LineSwipePolicy.accepts', () {
    const caret = CodeLineSelection.collapsed(index: 1, offset: 3);

    bool accepts({
      bool hasFocus = true,
      CodeLineSelection selection = caret,
      int lineIndex = 1,
      String? lineText = '- squat',
      bool Function(int lineIndex)? isFenceLine,
    }) => LineSwipePolicy.accepts(
      hasFocus: hasFocus,
      selection: selection,
      lineIndex: lineIndex,
      lineText: lineText,
      isFenceLine: isFenceLine,
    );

    test('a focused caret list line accepts', () {
      expect(accepts(), isTrue);
      expect(accepts(lineText: '  - [ ] squat'), isTrue);
      expect(accepts(lineText: '1. squat'), isTrue);
    });

    test('a quoted list item accepts', () {
      expect(accepts(lineText: '> - squat'), isTrue);
      expect(accepts(lineText: '> > 1. squat'), isTrue);
    });

    test('a selection within the caret line accepts', () {
      expect(
        accepts(
          selection: const CodeLineSelection(
            baseIndex: 1,
            baseOffset: 2,
            extentIndex: 1,
            extentOffset: 6,
          ),
        ),
        isTrue,
      );
    });

    test('an unfocused editor refuses', () {
      expect(accepts(hasFocus: false), isFalse);
    });

    test('a line that is not a list item refuses', () {
      expect(accepts(lineText: 'squat'), isFalse);
      expect(accepts(lineText: '> squat'), isFalse);
      expect(accepts(lineText: '-squat'), isFalse);
    });

    test('a fenced line refuses', () {
      expect(accepts(isFenceLine: (index) => index == 1), isFalse);
      expect(accepts(isFenceLine: (index) => index == 0), isTrue);
    });

    test('a line other than the caret line refuses', () {
      expect(accepts(lineIndex: 0), isFalse);
      expect(accepts(lineIndex: 2), isFalse);
    });

    test('a multi-line selection refuses', () {
      expect(
        accepts(
          selection: const CodeLineSelection(
            baseIndex: 0,
            baseOffset: 0,
            extentIndex: 1,
            extentOffset: 3,
          ),
        ),
        isFalse,
      );
    });

    test('a line outside the document refuses', () {
      expect(accepts(lineText: null), isFalse);
    });
  });

  group('the wrapper', () {
    const fontSize = 16.0;
    // An item above line 1, so the cap lets it go one level deeper.
    const document = '- intro\n- warm-up\n  - squat';

    Offset lineAt(WidgetTester tester, int line) {
      final origin = tester.getTopLeft(find.byType(CodeEditor));
      final lineBox = CodeFieldRenderForTesting.of(
        tester.renderObject(find.byType(CodeEditor)),
      ).lineHeight;
      return origin +
          Offset(
            AppSpacing.xl + 40,
            AppSpacing.lg + line * lineBox + lineBox / 2,
          );
    }

    List<Object?> recordHaptics(WidgetTester tester) {
      final calls = <Object?>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      const channel = SystemChannels.platform;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add(call.arguments);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      return calls;
    }

    Future<({CodeLineEditingController controller, FocusNode focusNode})>
    pumpEditor(
      WidgetTester tester, {
      String text = document,
      bool hapticsEnabled = true,
      bool Function(int lineIndex)? isFenceLine,
    }) async {
      final controller = CodeLineEditingController.fromText(text);
      final searchController = ReEditorSearchController();
      final scrollController = CodeScrollController();
      final focusNode = FocusNode();
      addTearDown(() {
        focusNode.dispose();
        searchController.dispose();
        scrollController.dispose();
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
              showScrollIndicator: false,
              hapticsEnabled: hapticsEnabled,
              isFenceLine: isFenceLine,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return (controller: controller, focusNode: focusNode);
    }

    /// Focuses the editor with a tap, then parks the caret at [line]:
    /// [offset], past the double-tap window so nothing pairs with it.
    Future<void> focusAt(
      WidgetTester tester,
      CodeLineEditingController controller,
      int line,
      int offset,
    ) async {
      await tester.tapAt(lineAt(tester, line));
      await tester.pump(const Duration(milliseconds: 400));
      controller.selection = CodeLineSelection.collapsed(
        index: line,
        offset: offset,
      );
      await tester.pump();
    }

    Future<void> teardownEditor(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }

    testWidgets('a right swipe makes the Tab edit and clicks once', (
      tester,
    ) async {
      final haptics = recordHaptics(tester);
      final e = await pumpEditor(tester);
      await focusAt(tester, e.controller, 1, 4);
      expect(e.focusNode.hasFocus, isTrue);
      haptics.clear();

      await tester.dragFrom(lineAt(tester, 1), const Offset(80, 0));
      await tester.pump(const Duration(milliseconds: 400));
      final swiped = e.controller.text;
      final swipedSelection = e.controller.selection;

      expect(swiped, '- intro\n  - warm-up\n  - squat');
      expect(haptics, ['HapticFeedbackType.selectionClick']);
      expect(e.focusNode.hasFocus, isTrue);

      e.controller.loadText(document);
      e.controller.selection = const CodeLineSelection.collapsed(
        index: 1,
        offset: 4,
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(e.controller.text, swiped);
      _expectSameSelection(e.controller.selection, swipedSelection);

      await teardownEditor(tester);
    });

    testWidgets('a left swipe makes the Shift-Tab edit', (tester) async {
      final e = await pumpEditor(tester);
      await focusAt(tester, e.controller, 2, 6);

      await tester.dragFrom(lineAt(tester, 2), const Offset(-80, 0));
      await tester.pump(const Duration(milliseconds: 400));
      final swiped = e.controller.text;
      final swipedSelection = e.controller.selection;

      expect(swiped, '- intro\n- warm-up\n- squat');

      e.controller.loadText(document);
      e.controller.selection = const CodeLineSelection.collapsed(
        index: 2,
        offset: 6,
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();

      expect(e.controller.text, swiped);
      _expectSameSelection(e.controller.selection, swipedSelection);

      await teardownEditor(tester);
    });

    testWidgets('a left swipe at column 0 changes nothing and stays silent', (
      tester,
    ) async {
      final haptics = recordHaptics(tester);
      final e = await pumpEditor(tester);
      await focusAt(tester, e.controller, 1, 4);
      haptics.clear();

      await tester.dragFrom(lineAt(tester, 1), const Offset(-80, 0));
      await tester.pump(const Duration(milliseconds: 400));

      expect(e.controller.text, document);
      expect(haptics, isEmpty);

      await teardownEditor(tester);
    });

    testWidgets('an unfocused editor ignores the swipe', (tester) async {
      final e = await pumpEditor(tester);
      e.controller.selection = const CodeLineSelection.collapsed(
        index: 1,
        offset: 4,
      );
      await tester.pump();

      await tester.dragFrom(lineAt(tester, 1), const Offset(80, 0));
      await tester.pump(const Duration(milliseconds: 400));

      expect(e.controller.text, document);
      expect(e.focusNode.hasFocus, isFalse);

      await teardownEditor(tester);
    });

    testWidgets('a swipe on a line other than the caret line edits nothing', (
      tester,
    ) async {
      final e = await pumpEditor(tester);
      await focusAt(tester, e.controller, 1, 4);

      await tester.dragFrom(lineAt(tester, 2), const Offset(80, 0));
      await tester.pump(const Duration(milliseconds: 400));

      expect(e.controller.text, document);

      await teardownEditor(tester);
    });

    testWidgets('a swipe past the cap changes nothing and stays silent', (
      tester,
    ) async {
      // Under a column-0 paragraph the item opens its list: cap 0.
      const capped = 'intro\n- warm-up';
      final haptics = recordHaptics(tester);
      final e = await pumpEditor(tester, text: capped);
      await focusAt(tester, e.controller, 1, 4);
      haptics.clear();

      await tester.dragFrom(lineAt(tester, 1), const Offset(80, 0));
      await tester.pump(const Duration(milliseconds: 400));

      expect(e.controller.text, capped);
      expect(haptics, isEmpty);
      expect(e.controller.canUndo, isFalse);

      await teardownEditor(tester);
    });

    testWidgets('a quoted item nests after its quote run, never padded at '
        'the caret', (tester) async {
      // The caret before `r`: the fork's plain indent would split the word.
      const quoted = '> - intro\n> - warm-up';
      final e = await pumpEditor(tester, text: quoted);
      await focusAt(tester, e.controller, 1, 6);

      await tester.dragFrom(lineAt(tester, 1), const Offset(80, 0));
      await tester.pump(const Duration(milliseconds: 400));

      expect(e.controller.text, '> - intro\n>   - warm-up');
      _expectSameSelection(
        e.controller.selection,
        const CodeLineSelection.collapsed(index: 1, offset: 8),
      );

      await teardownEditor(tester);
    });

    testWidgets('a first quoted item stays as it is', (tester) async {
      const quoted = 'intro\n> - warm-up';
      final haptics = recordHaptics(tester);
      final e = await pumpEditor(tester, text: quoted);
      await focusAt(tester, e.controller, 1, 6);
      haptics.clear();

      await tester.dragFrom(lineAt(tester, 1), const Offset(80, 0));
      await tester.pump(const Duration(milliseconds: 400));

      expect(e.controller.text, quoted);
      expect(haptics, isEmpty);

      await teardownEditor(tester);
    });

    testWidgets('with haptics off the swipe edits and stays silent', (
      tester,
    ) async {
      final haptics = recordHaptics(tester);
      final e = await pumpEditor(tester, hapticsEnabled: false);
      await focusAt(tester, e.controller, 1, 4);
      haptics.clear();

      await tester.dragFrom(lineAt(tester, 1), const Offset(80, 0));
      await tester.pump(const Duration(milliseconds: 400));

      expect(e.controller.text, '- intro\n  - warm-up\n  - squat');
      expect(haptics, isEmpty);

      await teardownEditor(tester);
    });

    testWidgets('a line the host reports fenced refuses the swipe', (
      tester,
    ) async {
      final haptics = recordHaptics(tester);
      final e = await pumpEditor(
        tester,
        isFenceLine: (lineIndex) => lineIndex == 1,
      );
      await focusAt(tester, e.controller, 1, 4);
      haptics.clear();

      await tester.dragFrom(lineAt(tester, 1), const Offset(80, 0));
      await tester.pump(const Duration(milliseconds: 400));

      expect(e.controller.text, document);
      expect(haptics, isEmpty);

      await teardownEditor(tester);
    });

    testWidgets('one swipe is one undo step', (tester) async {
      final e = await pumpEditor(tester);
      await focusAt(tester, e.controller, 1, 4);
      expect(e.controller.canUndo, isFalse);

      await tester.dragFrom(lineAt(tester, 1), const Offset(80, 0));
      await tester.pump(const Duration(milliseconds: 400));
      expect(e.controller.text, '- intro\n  - warm-up\n  - squat');

      e.controller.undo();
      await tester.pump();

      expect(e.controller.text, document);
      expect(e.controller.canUndo, isFalse);

      await teardownEditor(tester);
    });
  });
}

void _expectSameSelection(CodeLineSelection a, CodeLineSelection b) {
  expect(a.baseIndex, b.baseIndex);
  expect(a.baseOffset, b.baseOffset);
  expect(a.extentIndex, b.extentIndex);
  expect(a.extentOffset, b.extentOffset);
}
