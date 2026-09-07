import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/utils/re_editor_search_controller.dart';

import 'support/editor_test_support.dart';

/// F1 — a settled search with no match used to leave the previous match
/// selected. Painted in `selectionColor` it is indistinguishable from a
/// hit: typing "bench" into a note holding "belt" left "be" highlighted
/// with the counter reading 0, and closing the bar did not clear it
/// either.
///
/// The isolate search cannot be pumped, so every case here seeds
/// `CodeFindController.value` by hand. A result whose `option` and
/// `codeLines` already match short-circuits `_updateResult`, so the
/// seeded value survives the controller's own listener.
const _text = 'first line here\nthe quick brown fox belt is heavy\nthird line';

const _matchStart = 20;
const _matchEnd = 22;

CodeFindOption _option(String pattern) =>
    CodeFindOption(pattern: pattern, caseSensitive: false, regex: false);

CodeFindValue _settled(
  CodeLineEditingController edit,
  String pattern,
  List<CodeLineSelection> matches,
) {
  return CodeFindValue(
    option: _option(pattern),
    replaceMode: false,
    searching: false,
    result: matches.isEmpty
        ? null
        : CodeFindResult(
            index: 0,
            matches: matches,
            option: _option(pattern),
            codeLines: edit.codeLines,
            dirty: false,
          ),
  );
}

void main() {
  Future<CodeFindController> pumpEditor(
    WidgetTester tester,
    CodeLineEditingController controller,
    CodeFindController find, {
    ReEditorSearchController? search,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 200,
            child: CodeEditor(
              controller: controller,
              findController: find,
              autofocus: false,
              padding: EdgeInsets.zero,
              style: const CodeEditorStyle(fontSize: kTestFontSize),
              findBuilder: (context, controller, readOnly) {
                search?.setFindController(controller);
                return const _NoFindPanel();
              },
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    return find;
  }

  testWidgets('a settled zero-match query gives back the selection the last '
      'match took', (tester) async {
    final edit = CodeLineEditingController.fromText(_text);
    final find = CodeFindController(edit);
    addTearDown(() {
      find.dispose();
      edit.dispose();
    });

    await pumpEditor(tester, edit, find);

    const match = CodeLineSelection(
      baseIndex: 1,
      baseOffset: _matchStart,
      extentIndex: 1,
      extentOffset: _matchEnd,
    );
    find.value = _settled(edit, 'be', const [match]);
    await settle(tester);
    expect(edit.selection, match);

    // "ben" — the search settles with nothing to show.
    find.value = _settled(edit, 'ben', const []);
    await settle(tester);

    expect(edit.selection.isCollapsed, isTrue);
    expect(edit.selection.baseIndex, 1);
    expect(edit.selection.baseOffset, _matchStart);

    await teardownEditor(tester);
  });

  testWidgets('an in-flight search keeps the current match selected', (
    tester,
  ) async {
    final edit = CodeLineEditingController.fromText(_text);
    final find = CodeFindController(edit);
    addTearDown(() {
      find.dispose();
      edit.dispose();
    });

    await pumpEditor(tester, edit, find);

    const match = CodeLineSelection(
      baseIndex: 1,
      baseOffset: _matchStart,
      extentIndex: 1,
      extentOffset: _matchEnd,
    );
    find.value = _settled(edit, 'be', const [match]);
    await settle(tester);

    find.value = CodeFindValue(
      option: _option('ben'),
      replaceMode: false,
      searching: true,
    );
    await settle(tester);

    expect(edit.selection, match);

    await teardownEditor(tester);
  });

  testWidgets('a selection the user made themselves is left alone', (
    tester,
  ) async {
    final edit = CodeLineEditingController.fromText(_text);
    final find = CodeFindController(edit);
    addTearDown(() {
      find.dispose();
      edit.dispose();
    });

    await pumpEditor(tester, edit, find);

    const match = CodeLineSelection(
      baseIndex: 1,
      baseOffset: _matchStart,
      extentIndex: 1,
      extentOffset: _matchEnd,
    );
    find.value = _settled(edit, 'be', const [match]);
    await settle(tester);

    const own = CodeLineSelection(
      baseIndex: 0,
      baseOffset: 0,
      extentIndex: 0,
      extentOffset: 5,
    );
    edit.selection = own;
    find.value = _settled(edit, 'ben', const []);
    await settle(tester);

    expect(edit.selection, own);

    await teardownEditor(tester);
  });

  testWidgets('closing the bar collapses the match the find left selected', (
    tester,
  ) async {
    final edit = CodeLineEditingController.fromText(_text);
    final find = CodeFindController(edit);
    final search = ReEditorSearchController()..initialize(edit);
    addTearDown(() {
      search.dispose();
      find.dispose();
      edit.dispose();
    });

    await pumpEditor(tester, edit, find, search: search);

    const match = CodeLineSelection(
      baseIndex: 1,
      baseOffset: _matchStart,
      extentIndex: 1,
      extentOffset: _matchEnd,
    );
    find.value = _settled(edit, 'be', const [match]);
    await settle(tester);
    expect(edit.selection, match);

    search.closeSearch();
    await settle(tester);

    expect(edit.selection.isCollapsed, isTrue);
    expect(edit.selection.baseIndex, 1);
    expect(edit.selection.baseOffset, _matchStart);

    await teardownEditor(tester);
  });
}

class _NoFindPanel extends StatelessWidget implements PreferredSizeWidget {
  const _NoFindPanel();

  @override
  Size get preferredSize => Size.zero;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
