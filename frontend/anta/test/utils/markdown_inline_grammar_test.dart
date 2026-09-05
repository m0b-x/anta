import 'package:anta/utils/ghost_text.dart';
import 'package:anta/utils/markdown_color_syntax.dart';
import 'package:anta/utils/markdown_inline_grammar.dart';
import 'package:flutter_test/flutter_test.dart';

const MarkdownColorPalette palette = MarkdownColorPalette.presets;

List<InlineToken> tok(String text, {int start = 0, int? end, int depth = 0}) =>
    MarkdownInlineGrammar.tokenize(
      text,
      start: start,
      end: end,
      palette: palette,
      depth: depth,
    );

String describe(InlineToken t, [int shift = 0]) {
  final int s = t.start + shift;
  final int e = t.end + shift;
  if (t is InlineEscape) return 'escape[$s,$e)';
  if (t is InlineGhost) return 'ghost[$s,$e)';
  if (t is InlineCode) {
    return 'code[$s,$e) inner[${t.innerStart + shift},${t.innerEnd + shift})';
  }
  if (t is InlineLink) {
    final String kind = t.isImage ? 'image' : 'link';
    return '$kind[$s,$e) text[${t.textStart + shift},${t.textEnd + shift}) '
        'url[${t.urlStart + shift},${t.urlEnd + shift})';
  }
  if (t is InlineColor) {
    return 'color[$s,$e) inner[${t.innerStart + shift},${t.innerEnd + shift})';
  }
  if (t is InlineTag) return 'tag[$s,$e)';
  if (t is InlineUrl) return 'url[$s,$e)';
  if (t is InlineEmphasis) {
    final StringBuffer b = StringBuffer()
      ..write(t.kind.name)
      ..write('[$s,$e) inner[${t.innerStart + shift},${t.innerEnd + shift})');
    if (t.contentStart != t.innerStart) {
      b.write(' content${t.contentStart + shift}');
    }
    if (t.tintSpec != null) b.write(' tint');
    return b.toString();
  }
  return 'unknown[$s,$e)';
}

String render(List<InlineToken> tokens, [int shift = 0]) =>
    tokens.map((t) => describe(t, shift)).join(' ');

String show(String text, {int start = 0, int? end, int depth = 0}) =>
    render(tok(text, start: start, end: end, depth: depth));

void expectRangeEdge(String line) {
  final int n = line.length;
  for (final int s in <int>[0, 1, 2, 3]) {
    for (final int e in <int>[n, n - 1, n - 2, n - 3]) {
      if (s > n || e < 0 || s >= e) continue;
      final String ranged = render(
        MarkdownInlineGrammar.tokenize(
          line,
          start: s,
          end: e,
          palette: palette,
        ),
      );
      final String sub = render(
        MarkdownInlineGrammar.tokenize(line.substring(s, e), palette: palette),
        s,
      );
      expect(ranged, sub, reason: 'line "$line" range [$s,$e)');
    }
  }
}

void main() {
  group('emphasis pairing', () {
    test('___bold___ is one bold-italic token', () {
      expect(show('___bold___'), 'boldItalic[0,10) inner[3,7)');
    });

    test('***x*** is one bold-italic token', () {
      expect(show('***x***'), 'boldItalic[0,7) inner[3,4)');
    });

    test('**a *b* c** keeps only the outer bold', () {
      expect(show('**a *b* c**'), 'bold[0,11) inner[2,9)');
    });

    test('**a *b* c** inner range rediscovers the italic', () {
      expect(show('**a *b* c**', start: 2, end: 9), 'italic[4,7) inner[5,6)');
    });

    test('*a **b** c* keeps only the outer italic', () {
      expect(show('*a **b** c*'), 'italic[0,11) inner[1,10)');
    });

    test('*a **b** c* inner range rediscovers the bold', () {
      expect(show('*a **b** c*', start: 1, end: 10), 'bold[3,8) inner[5,6)');
    });

    test('***a** is a literal star then bold', () {
      expect(show('***a**'), 'bold[1,6) inner[3,4)');
    });

    test('**a*** is bold then a literal star', () {
      expect(show('**a***'), 'bold[0,5) inner[2,3)');
    });

    test('a*b*c is intra-word italic', () {
      expect(show('a*b*c'), 'italic[1,4) inner[2,3)');
    });

    test('2 * 3 * 4 has no emphasis', () {
      expect(show('2 * 3 * 4'), '');
    });

    test('_a_b_ is one italic spanning the middle underscore', () {
      expect(show('_a_b_'), 'italic[0,5) inner[1,4)');
    });

    test('snake_case_word has no emphasis', () {
      expect(show('snake_case_word'), '');
    });

    test('__init__ is bold', () {
      expect(show('__init__'), 'bold[0,8) inner[2,6)');
    });

    test('non-ASCII letters block underscore flanking', () {
      expect(show('ș_a_'), '');
    });

    test('interleaved runs keep only the first matched pair', () {
      expect(show('*a _b* c_'), 'italic[0,6) inner[1,5)');
    });

    test('~~~x~~~ leaves one literal tilde on each side', () {
      expect(show('~~~x~~~'), 'strikethrough[1,6) inner[3,4)');
    });

    test('single tildes are literal', () {
      expect(show('~x~'), '');
    });

    test('~~x~~ is strikethrough', () {
      expect(show('~~x~~'), 'strikethrough[0,5) inner[2,3)');
    });

    test('==x== is a default highlight', () {
      expect(show('==x=='), 'highlight[0,5) inner[2,3)');
    });

    test('==teal:x== resolves a tint and moves contentStart', () {
      expect(show('==teal:x=='), 'highlight[0,10) inner[2,8) content7 tint');
    });

    test('==note: x== keeps its text, unresolved name is not consumed', () {
      expect(show('==note: x=='), 'highlight[0,11) inner[2,9)');
    });

    test('bare markers produce nothing', () {
      expect(show('**'), '');
      expect(show('*'), '');
      expect(show('a*'), '');
      expect(show('*a'), '');
      expect(show('_'), '');
      expect(show('=='), '');
      expect(show('~~'), '');
    });

    test('plain **a** and *a*', () {
      expect(show('**a**'), 'bold[0,5) inner[2,3)');
      expect(show('*a*'), 'italic[0,3) inner[1,2)');
    });

    test('runs of four never pair with themselves', () {
      expect(show('===='), '');
      expect(show('____'), '');
      expect(show('~~~~'), '');
    });

    test('repeated bold across a line pairs greedily left to right', () {
      expect(
        show('a**b**c**d**e'),
        'bold[1,6) inner[3,4) bold[7,12) inner[9,10)',
      );
    });

    test('rule of three skips a same-run opener', () {
      expect(show('*a*b*'), 'italic[0,3) inner[1,2)');
    });

    test('emphasis whose content is only spaces never opens', () {
      expect(show('* a *'), '');
    });

    test('boldItalic marker length is three on both sides', () {
      final List<InlineToken> tokens = tok('***x***');
      final InlineEmphasis e = tokens.single as InlineEmphasis;
      expect(e.markerLength, 3);
      expect(e.kind, InlineEmphasisKind.boldItalic);
    });

    test('highlight tint spec resolves to the teal preset', () {
      final InlineEmphasis e = tok('==teal:x==').single as InlineEmphasis;
      expect(e.tintSpec, same(palette.lookup('teal')));
      expect(e.contentStart, 7);
    });
  });

  group('code spans', () {
    test('double backtick fence matches by length', () {
      expect(show('``a`b``'), 'code[0,7) inner[2,5)');
    });

    test('single backtick code span', () {
      expect(show('`a`'), 'code[0,3) inner[1,2)');
    });

    test('spaces inside a code span are allowed', () {
      expect(show('` a `'), 'code[0,5) inner[1,4)');
    });

    test('an unclosed backtick run is literal', () {
      expect(show('`a'), '');
    });

    test('backslashes do not escape inside a code span', () {
      expect(show(r'`a\`b`'), 'code[0,4) inner[1,3)');
    });

    test('an emphasis opener whose closer sits in a code span is literal', () {
      expect(show(r'*a `b* c`'), 'code[3,9) inner[4,8)');
    });

    test('a fence of the wrong length is skipped over', () {
      expect(show('``a`b``c'), 'code[0,7) inner[2,5)');
    });

    test('code spans expose their fence length', () {
      final InlineCode c = tok('``a``').single as InlineCode;
      expect(c.fenceLength, 2);
    });
  });

  group('escapes', () {
    test(r'\*a\* is two escapes and no emphasis', () {
      expect(show(r'\*a\*'), 'escape[0,2) escape[3,5)');
    });

    test(r'\\*a* is an escape followed by italic', () {
      expect(show(r'\\*a*'), 'escape[0,2) italic[2,5) inner[3,4)');
    });

    test(r'\{{x}} lets the ghost win over the escape', () {
      expect(show(r'\{{x}}'), 'ghost[1,6)');
    });

    test(r'\[a](b) is an escape and no link', () {
      expect(show(r'\[a](b)'), 'escape[0,2)');
    });

    test(r'\![a](b) is an escape and a non-image link', () {
      expect(show(r'\![a](b)'), 'escape[0,2) link[2,8) text[3,4) url[6,7)');
    });

    test('a backslash before a non-punctuation character is literal', () {
      expect(show(r'\a'), '');
    });

    test('a trailing backslash is literal', () {
      expect(show(r'a\'), '');
    });

    test('escape exposes the escaped character offset', () {
      final InlineEscape e = tok(r'\*').single as InlineEscape;
      expect(e.charStart, 1);
      expect(e.end, 2);
    });
  });

  group('links, tags and urls', () {
    test('![a](b) is an image link starting at the bang', () {
      expect(show('![a](b)'), 'image[0,7) text[2,3) url[5,6)');
    });

    test('[a](b) is a link', () {
      expect(show('[a](b)'), 'link[0,6) text[1,2) url[4,5)');
    });

    test('a link whose bracket sits in a code span is not a link', () {
      expect(show('[a `]` x](b)'), 'code[3,6) inner[4,5)');
    });

    test('an empty link text is not a link', () {
      expect(show('[](b)'), '');
    });

    test('an empty url is not a link', () {
      expect(show('[a]()'), '');
    });

    test('a bang not followed by a bracket is literal', () {
      expect(show('!x [a](b)'), 'link[3,9) text[4,5) url[7,8)');
    });

    test('[#tag](url) nests a tag in its text', () {
      expect(show('[#tag](url)'), 'link[0,11) text[1,5) url[7,10)');
      expect(show('[#tag](url)', start: 1, end: 5), 'tag[1,5)');
    });

    test('**[a](b)** nests a link in the bold', () {
      expect(show('**[a](b)**'), 'bold[0,10) inner[2,8)');
      expect(
        show('**[a](b)**', start: 2, end: 8),
        'link[2,8) text[3,4) url[6,7)',
      );
    });

    test('*#tag* nests a tag in the italic', () {
      expect(show('*#tag*'), 'italic[0,6) inner[1,5)');
      expect(show('*#tag*', start: 1, end: 5), 'tag[1,5)');
    });

    test('a mid-sentence tag is found at its word boundary', () {
      expect(show('see #project now'), 'tag[4,12)');
    });

    test('digit-led and glued hashes are not tags', () {
      expect(show('set #1'), '');
      expect(show('no#42'), '');
    });

    test('a heading hash is not a tag but a later one is', () {
      expect(show('## Title #done'), 'tag[9,14)');
    });

    test('a tag inside a code span stays literal', () {
      expect(show('run `git tag #v1x` now'), 'code[4,18) inner[5,17)');
    });

    test('bare https url', () {
      expect(show('https://example.com'), 'url[0,19)');
    });

    test('bare url drops trailing punctuation', () {
      expect(show('see https://example.com.'), 'url[4,23)');
    });

    test('www url gains a scheme in hrefOf', () {
      const String line = 'www.a.com';
      final InlineUrl u = tok(line).single as InlineUrl;
      expect(describe(u), 'url[0,9)');
      expect(u.hrefOf(line), 'https://www.a.com');
    });

    test('a bare scheme is not a url', () {
      expect(show('https://'), '');
      expect(show('www.'), '');
    });

    test('a url glued to a word is not a url', () {
      expect(show('awww.a.com'), '');
    });

    test('italic around a bare url keeps its closing star', () {
      expect(show('*https://a.com*'), 'italic[0,15) inner[1,14)');
      expect(show('*https://a.com*', start: 1, end: 14), 'url[1,14)');
    });

    test('bold around a bare url keeps both closing stars', () {
      expect(show('**see https://a.com**'), 'bold[0,21) inner[2,19)');
      expect(show('**see https://a.com**', start: 2, end: 19), 'url[6,19)');
    });

    test('strikethrough around a bare url keeps its tildes', () {
      expect(show('~~https://a.com~~'), 'strikethrough[0,17) inner[2,15)');
      expect(show('~~https://a.com~~', start: 2, end: 15), 'url[2,15)');
    });

    test('underscore italic around a bare www url', () {
      expect(show('_www.a.com_'), 'italic[0,11) inner[1,10)');
      expect(show('_www.a.com_', start: 1, end: 10), 'url[1,10)');
    });

    test('an interior underscore stays inside the url', () {
      expect(show('https://a.com/a_b'), 'url[0,17)');
    });

    test('trailing stars are trimmed from a bare url', () {
      expect(show('https://a.com/**'), 'url[0,14)');
    });

    test('base64 padding survives the trailing trim', () {
      expect(show('https://a.com/x?q=YWI=='), 'url[0,23)');
    });

    test('tagOf and urlOf return the source text', () {
      const String line = '[t](https://x.io) #done';
      final List<InlineToken> tokens = tok(line);
      expect((tokens[0] as InlineLink).urlOf(line), 'https://x.io');
      expect((tokens[1] as InlineTag).tagOf(line), '#done');
    });
  });

  group('colours', () {
    test('{teal:x} is a colour run', () {
      expect(show('{teal:x}'), 'color[0,8) inner[6,7)');
    });

    test('an unresolved colour name is never consumed', () {
      expect(show('{note:x}'), '');
    });

    test('nested braces close correctly', () {
      expect(show('{red:a {green:b} c}'), 'color[0,19) inner[5,18)');
    });

    test('{red:a {{b}} c} keeps the ghost for the inner pass', () {
      expect(show('{red:a {{b}} c}'), 'color[0,15) inner[5,14)');
      expect(show('{red:a {{b}} c}', start: 5, end: 14), 'ghost[7,12)');
    });

    test('colour spec resolves against the palette', () {
      final InlineColor c = tok('{red:x}').single as InlineColor;
      expect(c.spec, same(palette.lookup('red')));
    });
  });

  group('ghosts are opaque', () {
    test('emphasis cannot close inside a ghost', () {
      expect(show('**a {{b** c}}'), 'ghost[4,13)');
    });

    test('a code fence inside a ghost never closes a span', () {
      expect(show('`a {{b` c}}'), 'ghost[3,11)');
    });

    test('a link bracket inside a ghost invalidates the link', () {
      expect(show('[a {{b](c) d}}'), 'ghost[3,14)');
    });

    test('a tag before a ghost still tokenizes', () {
      expect(show('#tag {{x}}'), 'tag[0,4) ghost[5,10)');
    });

    test('a hash inside a ghost is not a tag', () {
      expect(show('{{ #topic }}'), 'ghost[0,12)');
    });

    test('a bare url stops at the next atom', () {
      expect(show('www.a.com{{x}}'), 'url[0,9) ghost[9,14)');
    });

    test('a ghost inside a code span is swallowed by the code', () {
      expect(show('`a{{b}}c`'), 'code[0,9) inner[1,8)');
    });

    test('ghost token carries its match', () {
      const String line = 'x {{ y }} z';
      final InlineGhost g = tok(line).single as InlineGhost;
      expect(g.match.innerOf(line), ' y ');
    });
  });

  group('nesting depth', () {
    test('depth at the limit yields only the range ghosts', () {
      expect(
        tok('*a* `b` [c](d)', depth: MarkdownInlineGrammar.maxNestingDepth),
        isEmpty,
      );
      expect(
        show('*a* {{g}} [c](d)', depth: MarkdownInlineGrammar.maxNestingDepth),
        'ghost[4,9)',
      );
    });

    test('depth one below the limit still tokenizes', () {
      expect(
        show('*a*', depth: MarkdownInlineGrammar.maxNestingDepth - 1),
        'italic[0,3) inner[1,2)',
      );
    });

    test('depth above the limit yields only the range ghosts', () {
      expect(
        tok('*a*', depth: MarkdownInlineGrammar.maxNestingDepth + 4),
        isEmpty,
      );
      expect(
        show(
          '{{g}} *a* {{h}}',
          depth: MarkdownInlineGrammar.maxNestingDepth + 4,
        ),
        'ghost[0,5) ghost[10,15)',
      );
    });

    test('a ghost eight colour wrappers deep is still a ghost', () {
      const String line =
          '{red:{red:{red:{red:{red:{red:{red:{red:{{g}}}}}}}}}}';
      expect(line.substring(40, 45), '{{g}}');
      final List<InlineToken> tokens = MarkdownInlineGrammar.tokenize(
        line,
        start: 40,
        end: 45,
        palette: palette,
        depth: MarkdownInlineGrammar.maxNestingDepth,
      );
      expect(tokens.single, isA<InlineGhost>());
      expect(render(tokens), 'ghost[40,45)');
    });

    test('deep nesting rediscovers level by level', () {
      const String line = '***a***';
      final InlineEmphasis outer = tok(line).single as InlineEmphasis;
      expect(outer.kind, InlineEmphasisKind.boldItalic);
      expect(
        show(line, start: outer.contentStart, end: outer.innerEnd, depth: 1),
        '',
      );
    });

    test('a colour inside bold inside a link text is found by recursion', () {
      const String line = '[**{red:x}**](u)';
      expect(show(line), 'link[0,16) text[1,12) url[14,15)');
      expect(show(line, start: 1, end: 12, depth: 1), 'bold[1,12) inner[3,10)');
      expect(show(line, start: 3, end: 10, depth: 2), 'color[3,10) inner[8,9)');
      expect(show(line, start: 8, end: 9, depth: 3), '');
    });
  });

  // Pinned from the pairing loop before it grew CommonMark's
  // `openers_bottom` bound, so the bound is proven to be a pure speed-up:
  // every line here is one whose closers repeatedly fail to find an
  // opener, which is exactly what the bound short-circuits.
  group('delimiter pairing', () {
    const Map<String, String> pinned = <String, String>{
      '*a **b** c*': 'italic[0,11) inner[1,10)',
      '**a *b* c**': 'bold[0,11) inner[2,9)',
      '*a*b*c*': 'italic[0,3) inner[1,2) italic[4,7) inner[5,6)',
      '**a*b**': 'bold[0,7) inner[2,5)',
      '*a **b* c**': 'italic[0,11) inner[1,10)',
      '_a __b_ c__': 'italic[0,11) inner[1,10)',
      '***a** b*': 'italic[0,9) inner[1,8)',
      '*a* *b* *c*':
          'italic[0,3) inner[1,2) italic[4,7) inner[5,6) '
          'italic[8,11) inner[9,10)',
      '~~a ~~b~~ c~~': 'strikethrough[0,13) inner[2,11)',
      '==a ==b== c==': 'highlight[0,13) inner[2,11)',
      '*a _b* c_': 'italic[0,6) inner[1,5)',
      'a* b* c* *d*': 'italic[9,12) inner[10,11)',
      '*a *b *c* d* e*': 'italic[0,15) inner[1,14)',
      '**a** *b* ***c***':
          'bold[0,5) inner[2,3) italic[6,9) inner[7,8) '
          'boldItalic[10,17) inner[13,14)',
      '*a**b*': 'italic[0,6) inner[1,5)',
      '**a*b*c**': 'bold[0,9) inner[2,7)',
      '*a**': 'italic[0,3) inner[1,2)',
      '**a*': 'italic[1,4) inner[2,3)',
      'a* b *c*': 'italic[5,8) inner[6,7)',
      '*a b* c*': 'italic[0,5) inner[1,4)',
      '***a***': 'boldItalic[0,7) inner[3,4)',
      '****a****': 'italic[0,9) inner[1,8)',
      '*****a*****': 'bold[0,11) inner[2,9)',
      '__a__b__': 'bold[0,8) inner[2,6)',
      '_a_b_c_': 'italic[0,7) inner[1,6)',
      '==a== ==b==': 'highlight[0,5) inner[2,3) highlight[6,11) inner[8,9)',
      '~~~a~~~ b~~': 'strikethrough[1,6) inner[3,4)',
      '*a ~~b* c~~': 'italic[0,7) inner[1,6)',
      '==a *b== c*': 'highlight[0,8) inner[2,6)',
      '* a * b *c*': 'italic[8,11) inner[9,10)',
      'a*b**c***d': 'italic[1,9) inner[2,8)',
      '**a *b **c** d* e**': 'bold[0,19) inner[2,17)',
      '*a**b**c*': 'italic[0,9) inner[1,8)',
      '**a*b**c*d**': 'bold[0,7) inner[2,5)',
      '_ a _ _b_': 'italic[6,9) inner[7,8)',
      '~~a~~~~b~~':
          'strikethrough[0,5) inner[2,3) strikethrough[5,10) inner[7,8)',
      '====a====': 'highlight[0,9) inner[2,7)',
      r'*a\*b*': 'italic[0,6) inner[1,5)',
      '`a*b` *c*': 'code[0,5) inner[1,4) italic[6,9) inner[7,8)',
      '*a `b*c` d*': 'italic[0,11) inner[1,10)',
      '{red:*a*} *b*': 'color[0,9) inner[5,8) italic[10,13) inner[11,12)',
      '==teal:a== *b*':
          'highlight[0,10) inner[2,8) content7 tint '
          'italic[11,14) inner[12,13)',
      'a_b_c *d* e': 'italic[6,9) inner[7,8)',
      '*a* b_c_d': 'italic[0,3) inner[1,2)',
    };

    pinned.forEach((String line, String expected) {
      test('pairs "$line" exactly as before', () {
        expect(show(line), expected);
      });
    });

    test('a storm of unpairable closers still resolves the one real pair', () {
      final String line = '${'a* ' * 400}*b*';
      expect(show(line), 'italic[1200,1203) inner[1201,1202)');
    });
  });

  group('empty and degenerate ranges', () {
    test('an empty string yields no tokens', () {
      expect(tok(''), isEmpty);
    });

    test('an empty range yields no tokens', () {
      expect(tok('*a*', start: 1, end: 1), isEmpty);
    });

    test('an inverted range yields no tokens', () {
      expect(tok('*a*', start: 2, end: 1), isEmpty);
    });

    test('the no-token path returns a const empty list', () {
      expect(identical(tok('plain'), tok('other plain')), isTrue);
    });

    test('tokens are sorted and non-overlapping', () {
      const String line = r'\*a `b` [c](d) #e {red:f} **g**';
      final List<InlineToken> tokens = tok(line);
      expect(tokens, isNotEmpty);
      int cover = 0;
      for (final InlineToken t in tokens) {
        expect(t.start, greaterThanOrEqualTo(cover));
        expect(t.end, greaterThan(t.start));
        expect(t.end, lessThanOrEqualTo(line.length));
        cover = t.end;
      }
    });
  });

  group('range edges match substring tokenization', () {
    const List<String> corpus = <String>[
      'plain text with no markup',
      '*a*',
      '**bold** and *italic*',
      'a*b*c and _d_e_',
      '***x*** ~~y~~ ==z==',
      'snake_case_word __init__',
      r'\*escaped\* and \\*real*',
      '`code` and ``a`b``',
      '[link](url) and ![img](u2)',
      'see #tag and #other-tag',
      'visit www.a.com and https://b.org/x',
      '{red:tinted} text',
      '==teal:tint== and ==note: plain==',
      '2 * 3 * 4 = 12',
      '*a _b* c_',
      '**a *b* c**',
      '*a **b** c*',
      '***a**',
      '**a***',
      '~~~x~~~',
      'a `b* c` *d',
      '[#tag](url) **[a](b)**',
      'no#42 set #1',
      'ș_a_ and cafe#x',
      'mixed **[a](b)** `c` #t www.d.e',
      '====',
      '____',
      '~~~~',
      r'\{a} {b:c} {gray:d}',
      'trailing marker *',
      '* leading marker',
      'a**b**c**d**e',
      '==red:x== ==x==',
      r'a\`b`c`',
      '#tag#tag',
      '![a](b) ![c](d)',
      'a `b` c `d` e',
      '> quoted **line** with #tag',
    ];

    for (final String line in corpus) {
      test('sub-ranges of "$line"', () => expectRangeEdge(line));
    }

    test('ghost-bearing lines agree on ghost-safe ranges', () {
      const String line = 'a {{g}} *b* c';
      for (final List<int> range in <List<int>>[
        <int>[0, 13],
        <int>[1, 13],
        <int>[7, 13],
        <int>[8, 13],
        <int>[0, 7],
        <int>[7, 12],
      ]) {
        final String ranged = render(
          MarkdownInlineGrammar.tokenize(
            line,
            start: range[0],
            end: range[1],
            palette: palette,
          ),
        );
        final String sub = render(
          MarkdownInlineGrammar.tokenize(
            line.substring(range[0], range[1]),
            palette: palette,
          ),
          range[0],
        );
        expect(ranged, sub, reason: 'range $range');
      }
    });

    test('an explicit ghost list is honoured over rescanning', () {
      const String line = 'a {{g}} b';
      final List<InlineToken> withList = MarkdownInlineGrammar.tokenize(
        line,
        ghosts: const <GhostMatch>[],
        palette: palette,
      );
      expect(withList, isEmpty);
      expect(show(line), 'ghost[2,7)');
    });
  });

  group('linkAt', () {
    InlineLink? linkAt(String text, int offset) =>
        MarkdownInlineGrammar.linkAt(text, offset, palette: palette);

    test('the opening boundary is not inside the link', () {
      expect(linkAt('a [b](c) d', 2), isNull);
    });

    test('every strictly-inner offset resolves', () {
      for (int i = 3; i <= 7; i++) {
        final InlineLink? l = linkAt('a [b](c) d', i);
        expect(l, isNotNull, reason: 'offset $i');
        expect(l!.start, 2);
        expect(l.end, 8);
      }
    });

    test('the closing boundary is not inside the link', () {
      expect(linkAt('a [b](c) d', 8), isNull);
    });

    test('offsets outside the string are null', () {
      expect(linkAt('a [b](c) d', 0), isNull);
      expect(linkAt('a [b](c) d', 10), isNull);
      expect(linkAt('a [b](c) d', -1), isNull);
    });

    test('a link nested in emphasis is found', () {
      expect(linkAt('*[a](b)*', 1), isNull);
      final InlineLink? l = linkAt('*[a](b)*', 2);
      expect(l, isNotNull);
      expect(l!.start, 1);
      expect(l.end, 7);
    });

    test('an image link is never returned', () {
      expect(linkAt('![a](b)', 2), isNull);
      expect(linkAt('![a](b)', 4), isNull);
    });

    test('a link inside a code span is not a link', () {
      expect(linkAt('`[a](b)`', 3), isNull);
    });

    test('an escaped bracket kills the link', () {
      expect(linkAt(r'\[a](b)', 3), isNull);
    });

    test('an escaped backslash leaves the link intact', () {
      final InlineLink? l = linkAt(r'\\[a](b)', 4);
      expect(l, isNotNull);
      expect(l!.start, 2);
    });

    test('a link inside a ghost is not a link', () {
      expect(linkAt('{{ [a](b) }}', 5), isNull);
    });

    test('a link inside a colour run is found', () {
      const String line = '{red:[a](b)}';
      final InlineLink? l = linkAt(line, 7);
      expect(l, isNotNull);
      expect(l!.start, 5);
      expect(l.urlOf(line), 'b');
    });

    test('a link nested in bold is found', () {
      final InlineLink? l = linkAt('**[a](b)**', 4);
      expect(l, isNotNull);
      expect(l!.start, 2);
      expect(l.isImage, isFalse);
    });

    test('an image link text is descended into but never returned', () {
      // The link matcher closes on the first `]`, so `![x [a](b) y](u)` is
      // the image `![x [a](b)` — its text holds no complete nested link.
      expect(show('![x [a](b) y](u)'), 'image[0,10) text[2,6) url[8,9)');
      expect(linkAt('![x [a](b) y](u)', 5), isNull);
    });

    test('an offset in the url part still resolves to the link', () {
      final InlineLink? l = linkAt('[a](https://x.io)', 10);
      expect(l, isNotNull);
      expect(l!.start, 0);
    });

    test('plain text has no link', () {
      expect(linkAt('nothing here at all', 5), isNull);
    });

    test('a bare url is not an inline link', () {
      expect(linkAt('see www.a.com now', 8), isNull);
    });

    test('an explicit ghost list is honoured over rescanning', () {
      const String line = 'a [b](c) d';
      expect(linkAt(line, 4), isNotNull);
      expect(
        MarkdownInlineGrammar.linkAt(
          line,
          4,
          palette: palette,
          ghosts: const <GhostMatch>[
            GhostMatch(start: 2, end: 8, innerStart: 4, innerEnd: 6),
          ],
        ),
        isNull,
      );
    });
  });

  group('tagAt', () {
    InlineTag? tagAt(String text, int offset) =>
        MarkdownInlineGrammar.tagAt(text, offset, palette: palette);

    test('the leading hash is a boundary, not inside', () {
      expect(tagAt('see #x now', 4), isNull);
    });

    test('an offset inside the tag body resolves', () {
      final InlineTag? t = tagAt('see #x now', 5);
      expect(t, isNotNull);
      expect(t!.start, 4);
      expect(t.end, 6);
    });

    test('the closing boundary is not inside the tag', () {
      expect(tagAt('see #x now', 6), isNull);
    });

    test('a tag in a code span is not a tag', () {
      expect(tagAt('`#tag`', 3), isNull);
    });

    test('a tag in a ghost is not a tag', () {
      expect(tagAt('{{ #tag }}', 5), isNull);
    });

    test('a heading trailing tag resolves', () {
      final InlineTag? t = tagAt('## Title #done', 11);
      expect(t, isNotNull);
      expect(t!.start, 9);
      expect(t.end, 14);
    });

    test('a tag nested in a link text resolves', () {
      const String line = '[#tag](url)';
      final InlineTag? t = tagAt(line, 3);
      expect(t, isNotNull);
      expect(t!.tagOf(line), '#tag');
    });

    test('a tag nested in emphasis resolves', () {
      final InlineTag? t = tagAt('**#tag**', 4);
      expect(t, isNotNull);
      expect(t!.start, 2);
    });

    test('a tag nested in a colour run resolves', () {
      final InlineTag? t = tagAt('{red:#tag}', 7);
      expect(t, isNotNull);
      expect(t!.start, 5);
    });

    test('a digit-led hash is not a tag', () {
      expect(tagAt('set #1 now', 5), isNull);
    });

    test('a tag nested in an image link text resolves', () {
      final InlineTag? t = tagAt('![#tag](u)', 4);
      expect(t, isNotNull);
      expect(t!.start, 2);
      expect(t.end, 6);
    });

    test('offsets outside the string are null', () {
      expect(tagAt('#tag', 0), isNull);
      expect(tagAt('#tag', 4), isNull);
      expect(tagAt('', 0), isNull);
    });

    test('linkAt wins over tagAt on the same offset by wrapper order', () {
      const String line = '[#tag](url)';
      expect(
        MarkdownInlineGrammar.linkAt(line, 3, palette: palette),
        isNotNull,
      );
      expect(MarkdownInlineGrammar.tagAt(line, 3, palette: palette), isNotNull);
    });
  });

  group('character classes', () {
    test('isSpace covers the four whitespace units', () {
      expect(MarkdownInlineGrammar.isSpace(0x20), isTrue);
      expect(MarkdownInlineGrammar.isSpace(0x09), isTrue);
      expect(MarkdownInlineGrammar.isSpace(0x0A), isTrue);
      expect(MarkdownInlineGrammar.isSpace(0x0D), isTrue);
      expect(MarkdownInlineGrammar.isSpace(0x61), isFalse);
    });

    test('isWordChar covers ASCII alphanumerics, underscore and non-ASCII', () {
      expect(MarkdownInlineGrammar.isWordChar('a'.codeUnitAt(0)), isTrue);
      expect(MarkdownInlineGrammar.isWordChar('Z'.codeUnitAt(0)), isTrue);
      expect(MarkdownInlineGrammar.isWordChar('7'.codeUnitAt(0)), isTrue);
      expect(MarkdownInlineGrammar.isWordChar('_'.codeUnitAt(0)), isTrue);
      expect(MarkdownInlineGrammar.isWordChar('ș'.codeUnitAt(0)), isTrue);
      expect(MarkdownInlineGrammar.isWordChar(' '.codeUnitAt(0)), isFalse);
      expect(MarkdownInlineGrammar.isWordChar('-'.codeUnitAt(0)), isFalse);
    });
  });
}
