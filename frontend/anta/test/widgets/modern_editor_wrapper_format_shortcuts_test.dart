import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/config/default_markdown_shortcuts.dart';
import 'package:anta/utils/re_editor_search_controller.dart';
import 'package:anta/widgets/modern_editor_wrapper.dart';

/// Ctrl+B / Ctrl+I (Cmd on macOS) toggle bold and italic on the selection
/// on desktop, writing the same markers as the bar's `default_bold` and
/// `default_italic` shortcuts.
///
/// The fork's key layer is chosen by `kIsAndroid` / `kIsIOS`, top-level
/// `final`s resolved once per test process, so `setUpAll` resolves them
/// under a desktop override exactly as
/// `modern_editor_wrapper_desktop_indent_test.dart` does. The wrapper's
/// own binding reads `defaultTargetPlatform` when it mounts, which each
/// case sets through its [TargetPlatformVariant].
void main() {
  const fontSize = 16.0;

  setUpAll(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(kIsAndroid, isFalse);
    expect(kIsIOS, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  String markerOf(String id) => DefaultMarkdownShortcuts.shortcuts
      .firstWhere((shortcut) => shortcut.id == id)
      .beforeText;

  Future<({CodeLineEditingController controller, FocusNode focusNode})>
  pumpEditor(
    WidgetTester tester, {
    required String text,
    ValueChanged<String>? onFormatShortcut,
  }) async {
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
            onFormatShortcut: onFormatShortcut,
            wordWrap: false,
            showScrollIndicator: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (controller: controller, focusNode: focusNode);
  }

  /// The fork's cursor-blink controller arms an unguarded 100 ms delayed
  /// value-set on every focus change, so the tree is flushed while it is
  /// still alive.
  Future<void> teardownEditor(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  Future<void> select(
    WidgetTester tester,
    ({CodeLineEditingController controller, FocusNode focusNode}) e,
    int start,
    int end,
  ) async {
    e.focusNode.requestFocus();
    await tester.pump();
    e.controller.selection = CodeLineSelection(
      baseIndex: 0,
      baseOffset: start,
      extentIndex: 0,
      extentOffset: end,
    );
    await tester.pump();
  }

  Future<void> chord(
    WidgetTester tester,
    LogicalKeyboardKey modifier,
    LogicalKeyboardKey key,
  ) async {
    await tester.sendKeyDownEvent(modifier);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(modifier);
    await tester.pump();
  }

  final windows = TargetPlatformVariant.only(TargetPlatform.windows);

  testWidgets(
    'Ctrl+B bolds the selection, keeps it selected, and a second press '
    'reverses it',
    (tester) async {
      final e = await pumpEditor(tester, text: 'do squat now');
      await select(tester, e, 3, 8);
      final bold = markerOf('default_bold');

      await chord(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyB,
      );
      expect(e.controller.text, 'do ${bold}squat$bold now');
      expect(e.controller.selectedText, 'squat');

      await chord(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyB,
      );
      expect(e.controller.text, 'do squat now');
      expect(e.controller.selectedText, 'squat');
      expect(e.focusNode.hasFocus, isTrue);
      await teardownEditor(tester);
    },
    variant: windows,
  );

  testWidgets("Ctrl+I writes the default italic shortcut's marker", (
    tester,
  ) async {
    final e = await pumpEditor(tester, text: 'do squat now');
    await select(tester, e, 3, 8);
    final italic = markerOf('default_italic');

    await chord(
      tester,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.keyI,
    );

    expect(e.controller.text, 'do ${italic}squat$italic now');
    expect(e.controller.selectedText, 'squat');
    await teardownEditor(tester);
  }, variant: windows);

  testWidgets('one undo reverts the toggle', (tester) async {
    final e = await pumpEditor(tester, text: 'do squat now');
    await select(tester, e, 3, 8);

    await chord(
      tester,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.keyB,
    );
    e.controller.undo();
    await tester.pump();

    expect(e.controller.text, 'do squat now');
    await teardownEditor(tester);
  }, variant: windows);

  testWidgets(
    'macOS binds Cmd, not Ctrl',
    (tester) async {
      final e = await pumpEditor(tester, text: 'do squat now');
      await select(tester, e, 3, 8);
      final bold = markerOf('default_bold');

      await chord(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyB,
      );
      expect(e.controller.text, 'do squat now');

      await chord(tester, LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.keyB);
      expect(e.controller.text, 'do ${bold}squat$bold now');
      await teardownEditor(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  // Y13: the note editor routes the chord through its own guarded path.
  testWidgets('a host callback takes the chord instead of the direct edit', (
    tester,
  ) async {
    final markers = <String>[];
    final e = await pumpEditor(
      tester,
      text: 'do squat now',
      onFormatShortcut: markers.add,
    );
    await select(tester, e, 3, 8);

    await chord(
      tester,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.keyB,
    );
    await chord(
      tester,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.keyI,
    );

    expect(markers, [markerOf('default_bold'), markerOf('default_italic')]);
    expect(e.controller.text, 'do squat now', reason: 'the host edits');
    await teardownEditor(tester);
  }, variant: windows);

  testWidgets('an unfocused editor ignores the chord', (tester) async {
    final e = await pumpEditor(tester, text: 'do squat now');
    await select(tester, e, 3, 8);
    e.focusNode.unfocus();
    await tester.pump();

    await chord(
      tester,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.keyB,
    );

    expect(e.controller.text, 'do squat now');
    await teardownEditor(tester);
  }, variant: windows);

  testWidgets(
    'a phone binds neither chord',
    (tester) async {
      final e = await pumpEditor(tester, text: 'do squat now');
      await select(tester, e, 3, 8);

      await chord(
        tester,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.keyB,
      );

      expect(e.controller.text, 'do squat now');
      await teardownEditor(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
