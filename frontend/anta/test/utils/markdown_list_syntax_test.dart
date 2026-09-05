import 'package:anta/utils/markdown_list_syntax.dart';
import 'package:flutter_test/flutter_test.dart';

/// [MarkdownListSyntax.scanListShape] is the allocation-free companion of
/// [MarkdownListSyntax.parse]: the same markers, the same whitespace
/// rules, the same detection order, answered as a packed int instead of a
/// [MarkdownListItem]. Two surfaces rely on that being exact — the
/// editor's positional line index reads shapes for the whole document,
/// and the span builder gates [MarkdownListSyntax.parse] behind the scan
/// so a non-list line never pays the three regexes. A scan that rejected
/// a line `parse` accepts would silently stop rendering that list item.
///
/// So the contract this file pins is a single equivalence, over a corpus
/// that walks both sides of every rule the two implementations share:
/// `scanListShape(line) >= 0` exactly when `parse(line) != null`. The
/// packed fields are checked against the parsed item on the same corpus,
/// because a shape that agrees on "is a list" while disagreeing on
/// kind, checked or level is just as wrong.
void main() {
  group('scanListShape stays in lockstep with parse', () {
    for (final line in _corpus) {
      test('"${_visible(line)}"', () {
        final shape = MarkdownListSyntax.scanListShape(line);
        final item = MarkdownListSyntax.parse(line);

        expect(
          shape >= 0,
          item != null,
          reason: shape >= 0
              ? 'the scan accepts a line parse rejects'
              : 'the scan rejects a line parse accepts',
        );
        if (item == null) return;

        expect(
          MarkdownListSyntax.shapeKind(shape),
          switch (item.kind) {
            MarkdownListKind.bullet => MarkdownListSyntax.shapeKindBullet,
            MarkdownListKind.ordered => MarkdownListSyntax.shapeKindOrdered,
            MarkdownListKind.task => MarkdownListSyntax.shapeKindTask,
          },
          reason: 'packed kind must match the parsed kind',
        );
        expect(
          MarkdownListSyntax.shapeChecked(shape),
          item.checked,
          reason: 'packed checked flag must match the parsed box',
        );
        expect(
          MarkdownListSyntax.shapeLevel(shape),
          item.level,
          reason: 'packed level must match the parsed indent level',
        );
      });
    }
  });
}

String _visible(String s) => s
    .replaceAll('\t', '\\t')
    .replaceAll(' ', '\\u00a0')
    .replaceAll('　', '\\u3000');

/// Both sides of every rule the scan and the regexes share: the marker
/// sets, the mandatory whitespace after a marker, the task-box shape,
/// multi-digit ordered markers, exotic `\s` indent (which the regexes
/// accept but [MarkdownListSyntax.indentLevel] stops counting at), and
/// the near-misses that must stay plain text.
const List<String> _corpus = <String>[
  // Bullets, every marker.
  '- item',
  '* item',
  '+ item',
  '• item',
  '-\titem',
  '-  wide gap',
  '- ',
  '-',
  '-item',
  '--- rule shaped',
  '***',
  '*bold* text',
  '+',

  // Indentation and levels.
  '  - two spaces',
  '    - four spaces',
  '      - six spaces',
  ' - one space',
  '\t- one tab',
  '\t\t- two tabs',
  ' - nbsp indent',
  '　- ideographic space indent',

  // Ordered.
  '1. first',
  '1) first',
  '12. twelfth',
  '007) bond',
  '1.no space',
  '1.',
  '1 . spaced delimiter',
  '1-. wrong delimiter',
  '1',
  '2026-09-05 is a date',

  // Tasks.
  '- [ ] open',
  '- [x] done',
  '- [X] done upper',
  '* [ ] star task',
  '+ [x] plus task',
  '  - [ ] nested task',
  '- [] no room',
  '- [y] not a box',
  '- [ ]',
  '- [ ] ',
  '-  [x] wide gap task',
  '• [ ] bullets never take a box',
  '1. [ ] ordered never takes a box',
  '- [ x] wrong width',

  // Not lists at all.
  '',
  ' ',
  '\t',
  'plain prose',
  '# heading',
  '> quote',
  r'$= 500',
  '| a | b |',
  '```dart',
  '~~~',
  '_ underscore is not a bullet',
  '. leading dot',
  ') leading paren',
];
