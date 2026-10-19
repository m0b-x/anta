import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/constants/app_spacing.dart';
import 'package:anta/utils/re_editor_search_controller.dart';
import 'package:anta/widgets/modern_editor_wrapper.dart';

/// The selection toolbar offers Paste only while the clipboard holds text.
///
/// The fork builds the toolbar synchronously, so the wrapper cannot wait
/// for the platform's answer: each show asks `Clipboard.hasStrings`, the
/// toolbar keeps the last answer until the new one lands, and an open
/// toolbar rebuilds when it does. Runs on the default test platform
/// (Android), where a long-press on a word selects it and shows the
/// toolbar.
void main() {
  const fontSize = 16.0;

  /// Answers `Clipboard.hasStrings` with whatever [answer] returns, and
  /// counts the asks.
  List<String> mockClipboard(
    WidgetTester tester,
    FutureOr<bool> Function() answer,
  ) {
    final asks = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    const channel = SystemChannels.platform;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'Clipboard.hasStrings') return null;
      asks.add(call.method);
      return <String, Object?>{'value': await answer()};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    return asks;
  }

  Future<CodeLineEditingController> pumpEditor(WidgetTester tester) async {
    final controller = CodeLineEditingController.fromText('squat bench');
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
            showScrollIndicator: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  /// Long-presses inside the first word, which selects it and shows the
  /// toolbar when the press ends.
  Future<void> longPressFirstWord(WidgetTester tester) async {
    final origin = tester.getTopLeft(find.byType(CodeEditor));
    await tester.longPressAt(
      origin + const Offset(AppSpacing.xl + 2 * fontSize, AppSpacing.lg + 8),
    );
    await tester.pump();
  }

  /// The fork's cursor-blink controller arms an unguarded 100 ms delayed
  /// value-set on every focus change, so the tree is flushed while it is
  /// still alive.
  Future<void> teardownEditor(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('an empty clipboard leaves Paste out', (tester) async {
    final asks = mockClipboard(tester, () => false);
    final controller = await pumpEditor(tester);

    await longPressFirstWord(tester);
    await tester.pump();

    expect(controller.selectedText, 'squat');
    expect(asks, isNotEmpty);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Paste'), findsNothing);
    await teardownEditor(tester);
  });

  testWidgets('a clipboard holding text offers Paste', (tester) async {
    mockClipboard(tester, () => true);
    await pumpEditor(tester);

    await longPressFirstWord(tester);
    await tester.pump();

    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
    await teardownEditor(tester);
  });

  testWidgets('an open toolbar drops Paste when the answer lands', (
    tester,
  ) async {
    final answer = Completer<bool>();
    mockClipboard(tester, () => answer.future);
    await pumpEditor(tester);

    await longPressFirstWord(tester);
    // Not answered yet: Paste shows, as it did before the clipboard was
    // asked at all.
    expect(find.text('Paste'), findsOneWidget);

    answer.complete(false);
    await tester.pump();
    await tester.pump();

    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Paste'), findsNothing);
    await teardownEditor(tester);
  });
}
