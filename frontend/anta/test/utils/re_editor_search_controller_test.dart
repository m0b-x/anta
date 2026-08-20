import 'package:anta/utils/re_editor_search_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Builds a find controller holding a ready-made result, so the tests exercise
/// navigation without waiting on the background search isolate.
({CodeFindController find, CodeLineEditingController edit}) _editorWith(
  String text,
  String pattern,
) {
  final edit = CodeLineEditingController.fromText(text);
  final find = CodeFindController(edit);
  final lines = text.split('\n');
  final matches = <CodeLineSelection>[];
  for (var i = 0; i < lines.length; i++) {
    var from = 0;
    while (true) {
      final at = lines[i].indexOf(pattern, from);
      if (at == -1) break;
      matches.add(
        CodeLineSelection(
          baseIndex: i,
          baseOffset: at,
          extentIndex: i,
          extentOffset: at + pattern.length,
        ),
      );
      from = at + pattern.length;
    }
  }
  find.value = CodeFindValue(
    option: CodeFindOption(
      pattern: pattern,
      caseSensitive: false,
      regex: false,
    ),
    replaceMode: false,
    result: CodeFindResult(
      index: 0,
      matches: matches,
      option: CodeFindOption(
        pattern: pattern,
        caseSensitive: false,
        regex: false,
      ),
      codeLines: edit.codeLines,
      dirty: false,
    ),
  );
  return (find: find, edit: edit);
}

ReEditorSearchController _previewController(String content, String query) {
  final controller = ReEditorSearchController();
  controller.openSearch();
  controller.updateContent(content);
  controller.searchImmediate(query);
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('goToMatch', () {
    test('jumps straight to the target index in editor mode', () {
      final text = List.generate(60, (i) => 'line $i squat').join('\n');
      final editor = _editorWith(text, 'squat');
      final controller = ReEditorSearchController()
        ..initialize(editor.edit)
        ..setFindController(editor.find);

      expect(controller.matchCount, 60);

      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.goToMatch(25);

      expect(controller.currentMatchIndex, 25);
      // The old implementation stepped nextMatch() 25 times, and each step
      // pushed a new value through the find controller.
      expect(notifications, 1);
    });

    test('clamps out-of-range indices instead of moving', () {
      final editor = _editorWith('a squat\nanother squat', 'squat');
      final controller = ReEditorSearchController()
        ..initialize(editor.edit)
        ..setFindController(editor.find);

      controller.goToMatch(99);
      expect(controller.currentMatchIndex, 1);

      controller.goToMatch(-5);
      expect(controller.currentMatchIndex, 0);
    });

    test('moves the index in preview mode', () {
      final controller = _previewController('one\ntwo hit\nthree hit', 'hit');
      expect(controller.matchCount, 2);

      controller.goToMatch(1);
      expect(controller.currentMatchIndex, 1);
    });
  });

  group('previewAt', () {
    test('reports the line and highlight range in editor mode', () {
      final editor = _editorWith('alpha\nbeta squat set\ngamma', 'squat');
      final controller = ReEditorSearchController()
        ..initialize(editor.edit)
        ..setFindController(editor.find);

      final preview = controller.previewAt(0)!;
      expect(preview.lineNumber, 1);
      expect(preview.snippet, 'beta squat set');
      expect(
        preview.snippet.substring(preview.highlightStart, preview.highlightEnd),
        'squat',
      );
      expect(preview.trimmedStart, isFalse);
      expect(preview.trimmedEnd, isFalse);
    });

    test('reports each match on a shared line separately', () {
      final controller = _previewController('hit and hit again', 'hit');

      final first = controller.previewAt(0)!;
      final second = controller.previewAt(1)!;
      expect(first.lineNumber, 0);
      expect(second.lineNumber, 0);
      expect(first.highlightStart, 0);
      expect(second.highlightStart, 8);
      expect(first.snippet, second.snippet);
    });

    test('windows long lines around the match', () {
      final filler = 'x' * 300;
      final controller = _previewController('$filler needle $filler', 'needle');

      final preview = controller.previewAt(0)!;
      expect(preview.snippet.length, lessThanOrEqualTo(140));
      expect(preview.trimmedStart, isTrue);
      expect(preview.trimmedEnd, isTrue);
      expect(
        preview.snippet.substring(preview.highlightStart, preview.highlightEnd),
        'needle',
      );
    });

    test('keeps the window in range for a match at the line start', () {
      final controller = _previewController('needle${'y' * 300}', 'needle');

      final preview = controller.previewAt(0)!;
      expect(preview.trimmedStart, isFalse);
      expect(preview.trimmedEnd, isTrue);
      expect(preview.highlightStart, 0);
      expect(preview.highlightEnd, 6);
    });

    test('keeps the window in range for a match at the line end', () {
      final controller = _previewController('${'y' * 300}needle', 'needle');

      final preview = controller.previewAt(0)!;
      expect(preview.trimmedStart, isTrue);
      expect(preview.trimmedEnd, isFalse);
      expect(
        preview.snippet.substring(preview.highlightStart, preview.highlightEnd),
        'needle',
      );
    });

    test('returns null outside the match range', () {
      final controller = _previewController('one hit', 'hit');
      expect(controller.previewAt(1), isNull);
      expect(controller.previewAt(-1), isNull);
    });
  });

  test('matches are converted once per find result', () {
    final text = List.generate(200, (i) => 'row $i squat').join('\n');
    final editor = _editorWith(text, 'squat');
    final controller = ReEditorSearchController()
      ..initialize(editor.edit)
      ..setFindController(editor.find);

    final first = controller.matches;
    expect(identical(controller.matches, first), isTrue);

    // Offsets stay correct across the document, not just on the first line.
    expect(first.first.start, text.indexOf('squat'));
    expect(first.last.start, text.lastIndexOf('squat'));
  });
}
