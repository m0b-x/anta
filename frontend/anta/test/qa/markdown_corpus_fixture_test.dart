import 'dart:convert';
import 'dart:io';

import 'package:anta/utils/line_based_markdown_builder.dart';
import 'package:anta/utils/markdown_chunker.dart';
import 'package:anta/utils/markdown_color_syntax.dart';
import 'package:anta/utils/markdown_plain_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _corpusNote(String id) {
  final json =
      jsonDecode(
            File('tool/qa/fixtures/markdown_corpus.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final notes = (json['notes'] as List).cast<Map<String, dynamic>>();
  return notes.singleWhere((note) => note['id'] == id)['content'] as String;
}

/// The text a preview line paints, list rows included: a bullet row is a
/// `WidgetSpan` whose content sits in a `Text.rich` under its layout.
String _painted(Object? node) {
  final out = StringBuffer();
  void visit(Object? node) {
    switch (node) {
      case TextSpan():
        out.write(node.text ?? '');
        node.children?.forEach(visit);
      case WidgetSpan():
        visit(node.child);
      case Text():
        node.textSpan == null
            ? out.write(node.data ?? '')
            : visit(node.textSpan);
      case ProxyWidget():
        visit(node.child);
      case SingleChildRenderObjectWidget():
        visit(node.child);
      case MultiChildRenderObjectWidget():
        node.children.forEach(visit);
    }
  }

  visit(node);
  return out.toString();
}

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
    expect(
      content,
      contains('\n> a quote line keeps its backslash\\\n> > above a deeper'),
    );
    expect(
      content,
      contains('keeps its backslash\\\nSetext after a break\n---------\n'),
    );
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
    // Sweep S2: a list item is no paragraph continuation, so both paths
    // keep their trailing backslash.
    expect(content, contains('\n- D:\\Notes\\\n- D:\\Notes\\old\\\n\n'));
    expect(content, contains('\n## 9 Block comments\n%%\n'));
    final unclosed = content.indexOf('\n## 10 Unclosed fence');
    expect(unclosed, greaterThan(0));
    expect(content.indexOf('\n## ', unclosed + 1), -1);
  });

  // S2.7 — the "Front matter" note is a properties block, then the H1:
  // the last property no longer reads as a setext H2 over the closer.
  test('the front matter note is one block followed by its H1', () {
    final content = _corpusNote('qa-note-front-matter');
    final lines = content.split('\n');
    final layout = MarkdownChunker.computeLayout(
      lineCount: lines.length,
      chunkSize: 50,
      lineAt: (i) => lines[i],
    );
    final block = layout.blocks.first;
    expect(block.kind, MarkdownBlockKind.frontMatter);
    expect((block.startLine, block.endLine), (0, 4));
    expect(lines[4], '# Body after front matter');
    expect(MarkdownPlainText.strip(content), startsWith('Body after front'));
  });

  // S2 T3 — section 8 rendered, not only found: a reverted
  // `continuesParagraph` drops the paths' backslashes or keeps the
  // paragraph's, and either fails here.
  test('section 8 keeps the path backslashes and drops the hard breaks', () {
    final content = _corpusNote('qa-note-markdown-corpus');
    final start = content.indexOf('## 8 Breaks and misc\n');
    final end = content.indexOf('\n## 9 ');
    expect(start, greaterThan(0));
    final section = content.substring(start, end);
    final lines = section.split('\n');

    final plain = MarkdownPlainText.strip(section, maxLength: 1 << 20);
    expect(plain, contains(r'D:\Notes\ D:\Notes\old\'));
    expect(plain, contains('line with backslash next line'));

    final builder = LineBasedMarkdownBuilder(
      style: LineMarkdownStyle.fromTheme(
        ThemeData(useMaterial3: true, brightness: Brightness.light),
        16.0,
      ),
      colorPalette: MarkdownColorPalette.presets,
    );
    addTearDown(builder.dispose);
    builder.prepare(section);
    String preview(String line) {
      final i = lines.indexOf(line);
      expect(i, greaterThanOrEqualTo(0), reason: line);
      return _painted(builder.buildLine(line, i));
    }

    expect(preview(r'- D:\Notes\'), endsWith(r'D:\Notes\'));
    expect(preview(r'- D:\Notes\old\'), endsWith(r'D:\Notes\old\'));
    expect(preview(r'line with backslash\'), 'line with backslash');
  });
}
