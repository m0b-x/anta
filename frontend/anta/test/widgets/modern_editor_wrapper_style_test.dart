import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/constants/app_constants.dart';
import 'package:anta/constants/app_spacing.dart';
import 'package:anta/constants/app_theme.dart';
import 'package:anta/utils/re_editor_search_controller.dart';
import 'package:anta/widgets/modern_editor_wrapper.dart';

/// E9, E10, E12 — the editor body's own chrome, read straight off the
/// style the wrapper hands the fork.
///
/// The caret line used to be `primary@0.10`, a purple wash over the text;
/// the find hit fell through to the fork's `primary@0.4`, which is also
/// the selection colour, so a hit and a selection were the same paint.
void main() {
  const fontSize = 16.0;

  Future<CodeEditorStyle> pumpAndReadStyle(
    WidgetTester tester,
    Brightness brightness,
  ) async {
    final controller = CodeLineEditingController.fromText('one\ntwo\nthree');
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
        theme: brightness == Brightness.light
            ? AppTheme.light()
            : AppTheme.dark(),
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
            showCursorLine: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.widget<CodeEditor>(find.byType(CodeEditor)).style!;
  }

  Future<void> teardownEditor(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  for (final brightness in Brightness.values) {
    testWidgets('the caret line and the find hit are palette roles '
        '(${brightness.name})', (tester) async {
      final scheme = brightness == Brightness.light
          ? AppTheme.lightScheme
          : AppTheme.darkScheme;
      final style = await pumpAndReadStyle(tester, brightness);

      expect(style.cursorLineColor, scheme.surfaceContainerLow);
      expect(style.cursorLineColor!.a, 1.0);
      expect(style.highlightColor, scheme.primaryContainer);
      expect(style.highlightColor, isNot(style.selectionColor));

      await teardownEditor(tester);
    });
  }

  testWidgets('the editor body is inset 20 dp', (tester) async {
    await pumpAndReadStyle(tester, Brightness.light);

    final padding =
        tester.widget<CodeEditor>(find.byType(CodeEditor)).padding!
            as EdgeInsets;
    expect(padding.left, AppSpacing.xl);
    expect(padding.right, AppSpacing.xl + AppConstants.editorScrollbarPadding);

    await teardownEditor(tester);
  });
}
