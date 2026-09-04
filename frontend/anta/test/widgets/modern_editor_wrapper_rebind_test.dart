import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/utils/re_editor_search_controller.dart';
import 'package:anta/widgets/modern_editor_wrapper.dart';

/// The wrapper binds its change listener in `initState`, so a page that
/// swaps in a different `CodeLineEditingController` without remounting
/// used to keep reporting the *old* document's edits — and never hear the
/// new one's. `didUpdateWidget` moves the binding; these cases pin both
/// halves of the move, plus the search controller's unbind.
///
/// Harness note (same as the other wrapper suites): the fork's cursor
/// blink controller arms an unguarded 100 ms delayed value-set on every
/// focus change, so the tree is flushed while it is still alive before it
/// comes down.
void main() {
  const fontSize = 16.0;

  Future<void> teardownEditor(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('a swapped controller moves the change listener with it', (
    tester,
  ) async {
    final first = CodeLineEditingController.fromText('first document');
    final second = CodeLineEditingController.fromText('second document');
    final searchController = ReEditorSearchController();
    final scrollController = CodeScrollController();
    final focusNode = FocusNode();
    var changes = 0;
    addTearDown(() {
      focusNode.dispose();
      searchController.dispose();
      second.dispose();
      first.dispose();
    });

    Widget wrap(CodeLineEditingController controller) => MaterialApp(
      home: Scaffold(
        body: ModernEditorWrapper(
          controller: controller,
          focusNode: focusNode,
          scrollController: scrollController,
          searchController: searchController,
          editorFontSize: fontSize,
          onTextChanged: () => changes++,
          wordWrap: false,
          showScrollIndicator: false,
        ),
      ),
    );

    await tester.pumpWidget(wrap(first));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(ModernEditorWrapper));

    first.replaceSelection('!');
    await tester.pump();
    expect(changes, greaterThan(0), reason: 'the first controller is bound');

    await tester.pumpWidget(wrap(second));
    await tester.pumpAndSettle();
    // The swap must be an update, not a remount — otherwise this pins
    // nothing about `didUpdateWidget`.
    expect(tester.state(find.byType(ModernEditorWrapper)), same(state));

    changes = 0;
    second.replaceSelection('?');
    await tester.pump();
    expect(changes, greaterThan(0), reason: 'the new controller is bound');
    expect(second.codeLines[0].text, startsWith('?'));

    changes = 0;
    first.replaceSelection('#');
    await tester.pump();
    expect(changes, 0, reason: 'the old controller is unbound');

    await teardownEditor(tester);
  });

  testWidgets('a swapped search controller is unbound from the editor', (
    tester,
  ) async {
    final controller = CodeLineEditingController.fromText('a document');
    final first = ReEditorSearchController();
    final second = ReEditorSearchController();
    final scrollController = CodeScrollController();
    final focusNode = FocusNode();
    addTearDown(() {
      focusNode.dispose();
      second.dispose();
      first.dispose();
      controller.dispose();
    });

    Widget wrap(ReEditorSearchController searchController) => MaterialApp(
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
    );

    await tester.pumpWidget(wrap(first));
    await tester.pumpAndSettle();
    expect(first.findController, isNotNull);

    await tester.pumpWidget(wrap(second));
    await tester.pumpAndSettle();
    expect(first.findController, isNull);
    expect(second.findController, isNotNull);

    await teardownEditor(tester);
  });
}
