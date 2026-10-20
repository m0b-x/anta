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
    expect(content, contains('\nSetext H1\n=========\nSetext H2\n---------\n'));
    expect(
      content,
      contains('\n   ====  \n- a list line keeps its rule\n---\n'),
    );
    expect(content, contains('\n- [-] cancelled task\n- [/] in progress'));
    expect(content, contains('\n- [<] scheduled task\n'));
    expect(content, contains('\n- [y] any other unit draws itself\n'));
    // Pipeless tables are deferred, so a `---` right under their last row
    // would read as a setext underline instead of the first rule.
    expect(content, contains('\nno | pipes\n\n---\n'));
    expect(content, contains('\n> - [ ] quoted task gets a box\n'));
    expect(content, contains('\n> [!TIP]+ open fold marker hidden\n'));
    expect(content, contains('\n> [!hint]\n> [!NOTE] a body token'));
    // Each lead of the first callout run opens its own block: a lead
    // under an open block is body text, so the fold, the unknown word and
    // the titleless kind would never show as leads on the device.
    expect(content, contains('\n> body of tip\n\n> [!WARNING]\n'));
    expect(content, contains('\n\n> [!custom] unknown type\n\n'));
    expect(content, contains('\n\n> [!NOTE]- folded callout\n'));
    expect(content, contains('\n> [![badge](https://example.com/b.svg)]'));
    expect(content, contains('\n>\t- tab-separated quoted bullet\n'));
    expect(content, contains('\n\u00a0- - -\n'));
    expect(content, contains('\n\u00a0## No-break-space lead stays prose\n'));
    expect(content, contains('\n# not a heading\n## build ##\n```\n'));
    // The device-pass lines of phase two, slice D: a one-line fence, the
    // fences under a list item, the literal tail before a blank line, the
    // block comment, and the unclosed fence that must stay last.
    expect(content, contains('\n```npm i``` pasted'));
    expect(content, contains('\n    ```bash\n'));
    expect(content, contains('\n\t~~~\n\ta tab-indented fence'));
    expect(content, contains('\n- D:\\Backups\\\n\n'));
    expect(content, contains('\n## 9 Block comments\n%%\n'));
    final unclosed = content.indexOf('\n## 10 Unclosed fence');
    expect(unclosed, greaterThan(0));
    expect(content.indexOf('\n## ', unclosed + 1), -1);
  });
}
