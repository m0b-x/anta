import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `tool/qa/fixtures/markdown_corpus.json` is hand-edited JSON whose note
/// body escapes every newline, tab and backslash, so a slip in an edit
/// would otherwise surface only at `qa seed` on the device.
void main() {
  test('the markdown corpus fixture decodes and holds its note', () {
    final json =
        jsonDecode(
              File('tool/qa/fixtures/markdown_corpus.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final notes = (json['notes'] as List).cast<Map<String, dynamic>>();
    final corpus = notes.singleWhere(
      (note) => note['id'] == 'qa-note-markdown-corpus',
    );
    final content = corpus['content'] as String;
    expect(content, startsWith('# Markdown corpus\n'));
    expect(content, contains('\n## Foo # ##\n'));
    expect(content, contains('\n - - -\n'));
  });
}
