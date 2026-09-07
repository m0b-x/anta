import 'package:anta/models/note_metadata.dart';
import 'package:anta/utils/markdown_plain_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MarkdownPlainText.strip line shapes', () {
    test('drops list, quote and callout markers from a nested note', () {
      const content =
          '31\n- level zero\n  - level one\n    - level two\n> [!note] x';

      final preview = MarkdownPlainText.strip(content);

      expect(preview, '31 level zero level one level two Note x');
      expect(preview, isNot(contains('-')));
      expect(preview, isNot(contains('>')));
      expect(preview, isNot(contains('[!')));
    });

    test('strips heading markers at every level', () {
      expect(MarkdownPlainText.strip('# One'), 'One');
      expect(MarkdownPlainText.strip('###### Six'), 'Six');
      expect(MarkdownPlainText.strip('#tag stays'), '#tag stays');
    });

    test('keeps a checked task marked and an unchecked one bare', () {
      expect(MarkdownPlainText.strip('- [x] done'), '✓ done');
      expect(MarkdownPlainText.strip('- [ ] todo'), 'todo');
    });

    test('skips blank lines, horizontal rules and table separators', () {
      expect(MarkdownPlainText.strip('a\n\n---\n\nb'), 'a b');
      expect(MarkdownPlainText.strip('| a | b |\n|---|---|\n| 1 | 2 |'),
          'a · b 1 · 2');
    });

    test('skips fence delimiters and everything inside a fence', () {
      const content = 'before\n```dart\nvar x = 1;\n```\nafter';

      expect(MarkdownPlainText.strip(content), 'before after');
    });

    test('unwraps a quoted block shape', () {
      expect(MarkdownPlainText.strip('> ## Quoted heading'), 'Quoted heading');
      expect(MarkdownPlainText.strip('>> deep'), 'deep');
    });

    test('names the callout type and keeps its title', () {
      expect(MarkdownPlainText.strip('> [!tip] Careful now'), 'Tip Careful now');
      expect(MarkdownPlainText.strip('> [!warning]'), 'Warning');
    });
  });

  group('MarkdownPlainText.strip inline grammar', () {
    test('emits the inner text of emphasis, code and highlight', () {
      expect(
        MarkdownPlainText.strip('**b** *i* ~~s~~ ==h== `c`'),
        'b i s h c',
      );
      expect(MarkdownPlainText.strip('==red: tinted=='), 'tinted');
    });

    test('emits link text, drops images, keeps wiki titles and urls', () {
      expect(MarkdownPlainText.strip('[text](https://a.com)'), 'text');
      expect(MarkdownPlainText.strip('a ![alt](https://a.com/x.png) b'), 'a b');
      expect(MarkdownPlainText.strip('see [[Leg Day]]'), 'see Leg Day');
      expect(MarkdownPlainText.strip('go https://b.com now'),
          'go https://b.com now');
      expect(MarkdownPlainText.strip('a #tag b'), 'a #tag b');
    });

    test('emits the escaped character and the colour contents', () {
      expect(MarkdownPlainText.strip(r'\*lit\*'), '*lit*');
      expect(MarkdownPlainText.strip('{red:tinted}'), 'tinted');
    });

    test('drops ghost placeholders entirely', () {
      expect(MarkdownPlainText.strip('reps {{count}} today'), 'reps today');
    });
  });

  group('MarkdownPlainText.strip money rows', () {
    test('emits the amount as typed and the label, never a balance', () {
      expect(MarkdownPlainText.strip('\$= 500 start'), '500 start');
      expect(MarkdownPlainText.strip('\$+ 45.00 chalk'), '45.00 chalk');
      expect(MarkdownPlainText.strip('\$- blue: 30 taxi'), '30 taxi');
    });

    test('a display row shows only its label', () {
      expect(MarkdownPlainText.strip('\$\$ Total'), 'Total');
      expect(MarkdownPlainText.strip('\$^ 3 Recent'), 'Recent');
    });

    test('a label-first row keeps its label, amount and trailing text', () {
      expect(
        MarkdownPlainText.strip('\$= Net worth: 5000 lei as of today'),
        'Net worth: 5000 lei as of today',
      );
    });

    test('a bulleted money row loses only its bullet', () {
      expect(MarkdownPlainText.strip('- \$+ 12.50 coffee'), '12.50 coffee');
    });

    test('a non-money dollar line stays plain', () {
      expect(MarkdownPlainText.strip('- \$100 coffee'), '\$100 coffee');
    });
  });

  group('MarkdownPlainText.strip output shape', () {
    test('falls back to the raw collapse when every line strips empty', () {
      const content = '---\n***\n```\nonly fence\n```';

      final preview = MarkdownPlainText.strip(content);

      expect(preview, '--- *** ``` only fence ```');
    });

    test('empty content previews empty', () {
      expect(MarkdownPlainText.strip(''), '');
      expect(MarkdownPlainText.strip('   \n\n  '), '');
    });

    test('caps at maxLength with an ellipsis', () {
      final content = '# ${'a' * 260}';

      final preview = MarkdownPlainText.strip(content);

      expect(preview.length, 203);
      expect(preview.endsWith('...'), isTrue);
      expect(preview.substring(0, 200), 'a' * 200);
      expect(MarkdownPlainText.strip('# ${'a' * 20}', maxLength: 5), 'aaaaa...');
    });

    test('joins every line so quick search keeps its reach', () {
      const content = '# Title\nbody line\n- last item';

      expect(MarkdownPlainText.strip(content), 'Title body line last item');
    });
  });

  group('NoteMetadata.generatePreview', () {
    test('delegates to the stripper', () {
      const content = '# Wednesday heavy\n- 5 x 3 @ 140kg';

      expect(
        NoteMetadata.generatePreview(content),
        MarkdownPlainText.strip(content),
      );
      expect(NoteMetadata.generatePreview(content), 'Wednesday heavy 5 x 3 @ 140kg');
    });

    test('empty content stays empty', () {
      expect(NoteMetadata.generatePreview(''), '');
    });
  });
}
