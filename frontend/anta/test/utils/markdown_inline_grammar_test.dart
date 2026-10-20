import 'package:anta/constants/markdown_constants.dart';
import 'package:anta/utils/ghost_text.dart';
import 'package:anta/utils/markdown_color_syntax.dart';
import 'package:anta/utils/markdown_inline_grammar.dart';
import 'package:anta/utils/markdown_tag_syntax.dart';
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
  if (t is InlineEntity) return 'entity[$s,$e) ${t.decoded}';
  if (t is InlineGhost) return 'ghost[$s,$e)';
  if (t is InlineCode) {
    return 'code[$s,$e) inner[${t.innerStart + shift},${t.innerEnd + shift})';
  }
  if (t is InlineLink) {
    final String kind = t.isImage ? 'image' : 'link';
    // The destination is named only where it is narrower than the url
    // range, so every link without a title or angle form reads as before.
    final String dest = t.destStart == t.urlStart && t.destEnd == t.urlEnd
        ? ''
        : ' dest[${t.destStart + shift},${t.destEnd + shift})';
    return '$kind[$s,$e) text[${t.textStart + shift},${t.textEnd + shift}) '
        'url[${t.urlStart + shift},${t.urlEnd + shift})$dest';
  }
  if (t is InlineWikiLink) {
    final int? alias = t.aliasStart;
    return '${t.isEmbed ? 'embed' : 'wiki'}[$s,$e) '
        'title[${t.titleStart + shift},${t.titleEnd + shift})'
        '${alias == null ? '' : ' alias${alias + shift}'}';
  }
  if (t is InlineAutolink) {
    return '${t.isEmail ? 'email' : 'autolink'}[$s,$e)';
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

    test('a range bound keeps the letter rule on a clamped body', () {
      expect(show('#5x5', end: 2), '');
      expect(show('#5x5', end: 3), 'tag[0,3)');
      expect(show('#a5x', end: 2), 'tag[0,2)');
    });

    test('a range bound keeps the slash rule on a clamped body', () {
      // MarkdownTagSyntax keeps a `/` only with a tag char after it.
      expect(show('#a/b', end: 3), 'tag[0,2)');
      expect(MarkdownTagSyntax.tryParseTagAt('#a/', 0), 2);
      expect(show('#5/a', end: 3), '');
      expect(show('#a/b', end: 4), 'tag[0,4)');
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

    test('balanced parentheses stay in a bare url', () {
      const String line = 'https://en.wikipedia.org/wiki/Squat_(exercise)';
      expect(show(line), 'url[0,${line.length})');
      expect(show('$line.'), 'url[0,${line.length})');
    });

    test('an unbalanced close paren ends a bare url', () {
      expect(show('(https://x.y).'), 'url[1,12)');
      expect(show('(see https://x.y/a_(b))'), 'url[5,22)');
      expect(show('https://x.y/a)b'), 'url[0,13)');
    });

    test('an unclosed open paren ends a bare url before it', () {
      expect(show('https://x.y/a(b c'), 'url[0,13)');
      expect(show('https://x.y/a(b)c(d'), 'url[0,17)');
    });

    test('tagOf and urlOf return the source text', () {
      const String line = '[t](https://x.io) #done';
      final List<InlineToken> tokens = tok(line);
      expect((tokens[0] as InlineLink).urlOf(line), 'https://x.io');
      expect((tokens[1] as InlineTag).tagOf(line), '#done');
    });
  });

  group('wiki links', () {
    test('[[a]] is a wiki link', () {
      expect(show('[[a]]'), 'wiki[0,5) title[2,3)');
    });

    test('a multi-word title keeps its spaces', () {
      expect(show('[[Squat Progression]]'), 'wiki[0,21) title[2,19)');
    });

    test('a mid-sentence wiki link is found', () {
      expect(show('see [[a]] now'), 'wiki[4,9) title[6,7)');
    });

    test('inner padding stays inside the title range', () {
      expect(show('[[ a ]]'), 'wiki[0,7) title[2,5)');
    });

    test('an empty or blank title is literal', () {
      expect(show('[[]]'), '');
      expect(show('[[ ]]'), '');
      expect(show('[[\t]]'), '');
    });

    test('a single closing bracket never closes a wiki link', () {
      expect(show('[[a]'), '');
    });

    test('an unclosed wiki link is literal', () {
      expect(show('[[a'), '');
      expect(show('[['), '');
    });

    test('an alias ends the title at the pipe', () {
      const String line = '[[Squat Day|leg day]]';
      expect(show(line), 'wiki[0,21) title[2,11) alias12');
      final InlineWikiLink w = tok(line).single as InlineWikiLink;
      expect(w.titleOf(line), 'Squat Day');
      expect(w.displayOf(line), 'leg day');
      expect(w.closeStart, 19);
    });

    test('an empty or blank alias shows the title', () {
      for (final String line in <String>['[[a|]]', '[[a| ]]']) {
        final InlineWikiLink w = tok(line).single as InlineWikiLink;
        expect(w.aliasStart, isNull, reason: line);
        expect(w.titleOf(line), 'a', reason: line);
        expect(w.displayOf(line), 'a', reason: line);
      }
    });

    test('a blank title before an alias is literal', () {
      expect(show('[[|b]]'), '');
      expect(show('[[ |b]]'), '');
    });

    test('a second pipe leaves the run literal', () {
      expect(show('[[a|b|c]]'), '');
    });

    test('an alias is literal and keeps a heading suffix in the title', () {
      expect(show('[[a#h|**b**]]'), 'wiki[0,13) title[2,5) alias6');
    });

    test('a ghost inside the alias rejects the wiki link', () {
      expect(show('[[a|{{g}}]]'), 'ghost[4,9)');
    });

    test('a bracket inside the title is literal', () {
      expect(show('[[a[b]]'), '');
    });

    test('a newline inside the title is literal', () {
      expect(show('[[a\nb]]'), '');
    });

    test('bare bracket runs are literal', () {
      expect(show(']]'), '');
      expect(show('[]'), '');
    });

    test('[[a]]] is a wiki link then a literal bracket', () {
      expect(show('[[a]]]'), 'wiki[0,5) title[2,3)');
    });

    test('[[[a]]] starts the wiki link at the second bracket', () {
      expect(show('[[[a]]]'), 'wiki[1,6) title[3,4)');
    });

    test('adjacent wiki links are two tokens', () {
      expect(show('[[a]][[b]]'), 'wiki[0,5) title[2,3) wiki[5,10) title[7,8)');
    });

    test('separated wiki links are two tokens', () {
      expect(show('[[a]] [[b]]'), 'wiki[0,5) title[2,3) wiki[6,11) title[8,9)');
    });

    test('a wiki link followed by parens is not an inline link', () {
      expect(show('[[a]](b)'), 'wiki[0,5) title[2,3)');
    });

    test('[[a](b)]] stays the inline link it was before wiki links', () {
      expect(show('[[a](b)]]'), 'link[0,7) text[1,3) url[5,6)');
    });

    test('an escaped opening bracket kills the wiki link', () {
      expect(show(r'\[[a]]'), 'escape[0,2)');
    });

    test('an escaped backslash leaves the wiki link intact', () {
      expect(show(r'\\[[a]]'), 'escape[0,2) wiki[2,7) title[4,5)');
    });

    test('a wiki link inside a code span is literal', () {
      expect(show('`[[a]]`'), 'code[0,7) inner[1,6)');
    });

    test('a code span inside the title rejects the wiki link', () {
      expect(show('[[a `b` c]]'), 'code[4,7) inner[5,6)');
    });

    test('a ghost inside the title rejects the wiki link', () {
      expect(show('[[a {{g}} b]]'), 'ghost[4,9)');
    });

    test('a wiki link inside a ghost is swallowed by the ghost', () {
      expect(show('{{[[a]]}}'), 'ghost[0,9)');
    });

    test('a wiki link before a ghost still tokenizes', () {
      expect(show('[[a]] {{g}}'), 'wiki[0,5) title[2,3) ghost[6,11)');
    });

    // The placement rule is `wiki.end <= nextAtom`, and every case above
    // reaches it with `nextAtom == hi`. These two are the equality: an
    // atom opening on the very code unit the construct ends at must not
    // reject it.
    test('a ghost tight against the closing brackets still tokenizes', () {
      expect(show('[[a]]{{g}}'), 'wiki[0,5) title[2,3) ghost[5,10)');
    });

    test('a code span tight against the closing brackets still tokenizes', () {
      expect(show('[[a]]`x`'), 'wiki[0,5) title[2,3) code[5,8) inner[6,7)');
    });

    test('an escaped bracket is not a closer and not a title unit', () {
      expect(show(r'[[a \] b]]'), 'escape[4,6)');
    });

    test('bold wraps a wiki link and the inner range rediscovers it', () {
      expect(show('**[[a]]**'), 'bold[0,9) inner[2,7)');
      expect(show('**[[a]]**', start: 2, end: 7), 'wiki[2,7) title[4,5)');
    });

    test('italic wraps a wiki link', () {
      expect(show('*x [[a]] y*'), 'italic[0,11) inner[1,10)');
      expect(show('*x [[a]] y*', start: 1, end: 10), 'wiki[3,8) title[5,6)');
    });

    test('a colour run wraps a wiki link', () {
      expect(show('{red:[[a]]}'), 'color[0,11) inner[5,10)');
      expect(show('{red:[[a]]}', start: 5, end: 10), 'wiki[5,10) title[7,8)');
    });

    test('a highlight wraps a wiki link', () {
      expect(show('==[[a]]=='), 'highlight[0,9) inner[2,7)');
      expect(show('==[[a]]==', start: 2, end: 7), 'wiki[2,7) title[4,5)');
    });

    test('strikethrough wraps a wiki link', () {
      expect(show('~~[[a]]~~'), 'strikethrough[0,9) inner[2,7)');
      expect(show('~~[[a]]~~', start: 2, end: 7), 'wiki[2,7) title[4,5)');
    });

    test('emphasis markers in a title stay literal', () {
      expect(show('[[**a**]]'), 'wiki[0,9) title[2,7)');
    });

    test('a hash in a title is not a tag', () {
      expect(show('[[#tag]]'), 'wiki[0,8) title[2,6)');
    });

    test('a url in a title is not a url', () {
      expect(show('[[https://a.com]]'), 'wiki[0,17) title[2,15)');
    });

    test('a star in a title never pairs with one outside', () {
      expect(show('[[a*]] b*'), 'wiki[0,6) title[2,4)');
    });

    test('underscores in a title stay literal', () {
      expect(show('[[snake_case]]'), 'wiki[0,14) title[2,12)');
    });

    test('a leading bang makes an embed reported from the bang', () {
      expect(show('![[a]]'), 'embed[0,6) title[3,4)');
      expect(show('![[a]](u)'), 'embed[0,6) title[3,4)');
      expect(show('x ![[a|b]] y'), 'embed[2,10) title[5,6) alias7');
      final InlineWikiLink w = tok('![[a]]').single as InlineWikiLink;
      expect(w.bracketStart, 1);
      expect(w.containsStrict(1), isFalse);
      expect(w.containsStrict(2), isTrue);
    });

    test('an escaped bang leaves a plain wiki link', () {
      expect(show(r'\![[a]]'), 'escape[0,2) wiki[2,7) title[4,5)');
    });

    test('an image whose alt opens with a bracket stays an image', () {
      expect(show('![[a](b)'), 'image[0,8) text[2,4) url[6,7)');
    });

    test('a tag, a wiki link and a url on one line keep their order', () {
      expect(
        show('#t [[a]] https://x.y'),
        'tag[0,2) wiki[3,8) title[5,6) url[9,20)',
      );
    });

    test('titleOf returns the raw source title', () {
      const String line = '[[Squat Day]]';
      final InlineWikiLink w = tok(line).single as InlineWikiLink;
      expect(w.titleOf(line), 'Squat Day');
      expect(w.end, 13);
    });

    test('a wiki link is a candidate line', () {
      expect(MarkdownInlineGrammar.hasCandidates('[[a]]'), isTrue);
      expect(MarkdownInlineGrammar.hasCandidates('see [[a]] now'), isTrue);
      expect(MarkdownInlineGrammar.hasCandidates('see a now'), isFalse);
    });

    test('sub-ranges of a wiki line match substring tokenization', () {
      expectRangeEdge('x [[a]] y');
      expectRangeEdge('[[a]][[b]]');
      expectRangeEdge('**[[a]]**');
      expectRangeEdge('[[a {{g}} b]]');
      expectRangeEdge('[[a|b]]');
      expectRangeEdge('x ![[a|b]] y');
    });
  });

  group('angle autolinks', () {
    test('an http url in angle brackets is an autolink', () {
      const String line = 'see <https://x.y/a> now';
      expect(show(line), 'autolink[4,19)');
      final InlineAutolink a = tok(line).single as InlineAutolink;
      expect(a.hrefOf(line), 'https://x.y/a');
    });

    test('mailto, tel and an upper-case scheme are autolinks', () {
      expect(show('<mailto:a@b.c>'), 'autolink[0,14)');
      expect(show('<tel:+40700>'), 'autolink[0,12)');
      expect(show('<HTTPS://X.Y>'), 'autolink[0,13)');
    });

    test('a bare address opens as mailto', () {
      const String line = '<me@example.com>';
      expect(show(line), 'email[0,16)');
      expect(
        (tok(line).single as InlineAutolink).hrefOf(line),
        'mailto:me@example.com',
      );
    });

    test('anything else in angle brackets stays literal', () {
      expect(show('a <b> c'), '');
      expect(show('x < y > z'), '');
      expect(show('<javascript:alert(1)>'), '');
      expect(show('<https:>'), '');
      expect(show('<>'), '');
      expect(show('<me@localhost>'), '');
      expect(show('<a@-b.c>'), '');
      expect(show('<https://x y>'), 'url[1,10)');
      expect(show('<https://x.y'), 'url[1,12)');
    });

    test('an atom inside refuses the autolink', () {
      expect(show(r'<https://x.y/\_a>'), r'url[1,13) escape[13,15)');
      expect(show('<https://x{{g}}>'), 'url[1,10) ghost[10,15)');
    });

    test('the inside is literal: no url, tag or emphasis inside', () {
      expect(show('<https://x.y/#tag_*a*>'), 'autolink[0,22)');
    });

    test('emphasis around an autolink rediscovers it inside', () {
      expect(show('*<https://x.y>*'), 'italic[0,15) inner[1,14)');
      expect(show('*<https://x.y>*', start: 1, end: 14), 'autolink[1,14)');
    });

    test('a less-than sign makes a candidate line', () {
      expect(MarkdownInlineGrammar.hasCandidates('<me@example.com>'), isTrue);
    });

    test('linksAndTags reports autolinks without descending', () {
      final List<InlineToken> found = MarkdownInlineGrammar.linksAndTags(
        '<https://x.y/#a> #t',
        palette: palette,
      );
      expect(render(found), 'autolink[0,16) tag[17,19)');
    });

    test('sub-ranges of an autolink line match substring tokenization', () {
      expectRangeEdge('a <https://x.y> b');
      expectRangeEdge('<me@example.com>');
    });
  });

  group('link destinations', () {
    test('a quoted title is not part of the destination', () {
      const String line = '[t](https://x.com/s "Guide")';
      expect(show(line), 'link[0,28) text[1,2) url[4,27) dest[4,19)');
      expect((tok(line).single as InlineLink).urlOf(line), 'https://x.com/s');
    });

    test('single-quoted and parenthesised titles', () {
      expect((tok("[t](u 'T')").single as InlineLink).urlOf("[t](u 'T')"), 'u');
      expect((tok('[t](u (T))').single as InlineLink).urlOf('[t](u (T))'), 'u');
    });

    test('balanced parentheses stay in the destination', () {
      const String line = '[w](https://en.wikipedia.org/wiki/Foo_(bar)) x';
      final InlineLink l = tok(line).first as InlineLink;
      expect(l.end, 44);
      expect(l.urlOf(line), 'https://en.wikipedia.org/wiki/Foo_(bar)');
      expect(show(line), 'link[0,44) text[1,2) url[4,43)');
    });

    test('an angle destination opens without its brackets', () {
      const String line = '[t](<a b>)';
      expect(show(line), 'link[0,10) text[1,2) url[4,9) dest[5,8)');
      expect((tok(line).single as InlineLink).urlOf(line), 'a b');
    });

    test('an unbalanced paren ends the link at the first close', () {
      const String line = '[a](b(c) d';
      expect(show(line), 'link[0,8) text[1,2) url[4,7)');
      expect((tok(line).single as InlineLink).urlOf(line), 'b(c');
    });

    test('blanks around the destination stay chrome', () {
      const String line = '[a]( b )';
      expect(show(line), 'link[0,8) text[1,2) url[4,7) dest[5,6)');
    });

    test('a destination with a blank and no title opens its first run', () {
      const String line = '[a](b c)';
      expect(show(line), 'link[0,8) text[1,2) url[4,7) dest[4,5)');
      expect((tok(line).single as InlineLink).urlOf(line), 'b');
    });

    test('a title the reading cannot close never reaches the url', () {
      const String line = "[G](https://x.y 'Bob's guide') x";
      expect(show(line), 'link[0,30) text[1,2) url[4,29) dest[4,15)');
      expect((tok(line).single as InlineLink).urlOf(line), 'https://x.y');
    });

    test('an escaped quote stays inside its title', () {
      const String line = r'[t](u "a \" b")';
      expect(show(line), 'link[0,15) text[1,2) url[4,14) dest[4,5)');
    });

    test('an image reads its destination the same way', () {
      const String line = '![a](u "t")';
      expect(show(line), 'image[0,11) text[2,3) url[5,10) dest[5,6)');
    });

    test('an image may leave its alt empty, a link may not', () {
      expect(show('![](u)'), 'image[0,6) text[2,2) url[4,5)');
      expect(show('a [](u) b'), '');
      expect(show('![]()'), '');
    });

    test('a range edge never lets the destination read past it', () {
      expectRangeEdge('[w](x_(b)) y');
      expectRangeEdge('[t](u "T") y');
      expectRangeEdge('x [t](<a b>)');
      expect(
        show('**[w](x_(b))**', start: 2, end: 12),
        'link[2,12) text[3,4) url[6,11)',
      );
    });
  });

  group('wikiLinkAt', () {
    InlineWikiLink? wikiAt(String text, int offset) =>
        MarkdownInlineGrammar.wikiLinkAt(text, offset, palette: palette);

    test('the opening boundary is not inside the wiki link', () {
      expect(wikiAt('x [[a]] y', 2), isNull);
    });

    test('the second opening bracket is already inside', () {
      final InlineWikiLink? w = wikiAt('x [[a]] y', 3);
      expect(w, isNotNull);
      expect(w!.start, 2);
      expect(w.end, 7);
    });

    test('every strictly-inner offset resolves', () {
      for (int i = 3; i <= 6; i++) {
        final InlineWikiLink? w = wikiAt('x [[a]] y', i);
        expect(w, isNotNull, reason: 'offset $i');
        expect(w!.start, 2);
        expect(w.end, 7);
      }
    });

    test('the closing boundary is not inside the wiki link', () {
      expect(wikiAt('x [[a]] y', 7), isNull);
    });

    test('offsets outside the string are null', () {
      expect(wikiAt('[[a]]', 0), isNull);
      expect(wikiAt('[[a]]', 5), isNull);
      expect(wikiAt('[[a]]', -1), isNull);
    });

    test('a title offset resolves and exposes the raw title', () {
      const String line = 'see [[Squat Day]] now';
      final InlineWikiLink? w = wikiAt(line, 8);
      expect(w, isNotNull);
      expect(w!.titleOf(line), 'Squat Day');
    });

    test('a wiki link nested in bold is found', () {
      final InlineWikiLink? w = wikiAt('**[[a]]**', 4);
      expect(w, isNotNull);
      expect(w!.start, 2);
      expect(w.end, 7);
    });

    test('a wiki link inside a code span is not a wiki link', () {
      expect(wikiAt('`[[a]]`', 3), isNull);
    });

    test('a wiki link inside a ghost is not a wiki link', () {
      expect(wikiAt('{{ [[a]] }}', 5), isNull);
    });

    test('an aliased link resolves to its title on the alias', () {
      const String line = '[[a|b]] x';
      final InlineWikiLink? w = wikiAt(line, 4);
      expect(w, isNotNull);
      expect(w!.titleOf(line), 'a');
      expect(w.displayOf(line), 'b');
      expect(wikiAt('[[a|b|c]] x', 3), isNull);
    });

    test("an embed's bang and first bracket are not inside it", () {
      expect(wikiAt('![[a]]', 1), isNull);
      expect(wikiAt('![[a]]', 2), isNotNull);
    });

    test('an inline link is not a wiki link', () {
      expect(wikiAt('[a](b) x', 2), isNull);
    });

    test('plain text has no wiki link', () {
      expect(wikiAt('nothing here at all', 5), isNull);
    });
  });

  group('linksAndTags with wiki links', () {
    List<InlineToken> walk(String text) =>
        MarkdownInlineGrammar.linksAndTags(text, palette: palette);

    test('a wiki link nested in bold is reported', () {
      expect(render(walk('**[[a]]**')), 'wiki[2,7) title[4,5)');
    });

    test('a tag, a wiki link and a link keep source order', () {
      expect(
        render(walk('#t [[a]] [b](c)')),
        'tag[0,2) wiki[3,8) title[5,6) link[9,15) text[10,11) url[13,14)',
      );
    });

    test('outermost first: a nested wiki link precedes a later tag', () {
      expect(
        render(walk('{red:[[a]]} #t')),
        'wiki[5,10) title[7,8) tag[12,14)',
      );
    });

    test('a wiki link title is never descended into', () {
      expect(render(walk('[[#tag]]')), 'wiki[0,8) title[2,6)');
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
      '„_foarte greu_“ and 😀_x_',
      'Squat 3*10, Bench 3*8',
      'a &amp; b &#169; &nope; `&lt;`',
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

    test('above 0x7F only letters, digits and marks are word characters', () {
      expect(MarkdownInlineGrammar.isWordChar('ü'.codeUnitAt(0)), isTrue);
      expect(MarkdownInlineGrammar.isWordChar('٣'.codeUnitAt(0)), isTrue);
      expect(MarkdownInlineGrammar.isWordChar(0x0301), isTrue);
      expect(MarkdownInlineGrammar.isWordChar('𝐀'.runes.single), isTrue);
      expect(MarkdownInlineGrammar.isWordChar('„'.codeUnitAt(0)), isFalse);
      expect(MarkdownInlineGrammar.isWordChar('—'.codeUnitAt(0)), isFalse);
      expect(MarkdownInlineGrammar.isWordChar('«'.codeUnitAt(0)), isFalse);
      expect(MarkdownInlineGrammar.isWordChar(0xA0), isFalse);
    });
  });

  group('underscore flanking past ASCII', () {
    test('Romanian quotes around underscores italicise', () {
      expect(show('„_foarte greu_“'), 'italic[1,14) inner[2,13)');
    });

    test('an em dash before underscores italicises', () {
      expect(show('—_x_'), 'italic[1,4) inner[2,3)');
    });

    test('guillemets around underscores italicise', () {
      expect(show('«_x_»'), 'italic[1,4) inner[2,3)');
    });

    test('a letter before underscores stays literal', () {
      expect(show('über_x_'), '');
      expect(show('aș_x_'), '');
    });

    test('a surrogate-pair letter before underscores stays literal', () {
      expect(show('𝐀_x_'), '');
    });

    test('an emoji before underscores is punctuation', () {
      expect(show('😀_x_'), 'italic[2,5) inner[3,4)');
    });

    test('a range edge splits no surrogate pair', () {
      // The low half alone is no word character, exactly as the range
      // starting there reads it.
      expect(show('𝐀_x_', start: 1), 'italic[2,5) inner[3,4)');
    });

    test('a letter after the closer keeps it literal', () {
      expect(show('_x_ü'), '');
      expect(show('_x_𝐀'), '');
    });

    test('an emoji after the closer is punctuation', () {
      expect(show('_x_😀'), 'italic[0,3) inner[1,2)');
    });

    test('a range end splits no surrogate pair after the closer', () {
      // The high half alone is no word character either.
      expect(show('_x_𝐀', end: 4), 'italic[0,3) inner[1,2)');
    });

    test('code points read whole only inside the range', () {
      const String line = 'a𝐀b';
      expect(MarkdownInlineGrammar.codePointBefore(line, 3, 0), 0x1D400);
      expect(MarkdownInlineGrammar.codePointBefore(line, 3, 2), 0xDC00);
      expect(MarkdownInlineGrammar.codePointAt(line, 1, 4), 0x1D400);
      expect(MarkdownInlineGrammar.codePointAt(line, 1, 2), 0xD835);
      expect(MarkdownInlineGrammar.codePointAt(line, 0, 4), 0x61);
    });
  });

  group('a star between digits', () {
    test('2*3*4 is literal', () {
      expect(show('2*3*4'), '');
    });

    test('a gym log line stays literal', () {
      expect(show('Squat 3*10, Bench 3*8'), '');
    });

    test('one digit side is not enough to block', () {
      expect(show('2*x*'), 'italic[1,4) inner[2,3)');
      expect(show('*3*'), 'italic[0,3) inner[1,2)');
    });

    test('a double star between digits is still bold', () {
      expect(show('2**3**4'), 'bold[1,6) inner[3,4)');
      // Only a single star is blocked, so a double run pairs across
      // words, as CommonMark and Obsidian pair it.
      expect(show('3**10 and 5**2'), 'bold[1,13) inner[3,11)');
    });

    test('underscores between digits keep their own rule', () {
      expect(show('2_3_4'), '');
      expect(show('_3_'), 'italic[0,3) inner[1,2)');
    });
  });

  group('html entities', () {
    test('a named entity is one token decoding to one unit', () {
      final InlineEntity e = tok('&amp;').single as InlineEntity;
      expect(e.end, 5);
      expect(e.decoded, '&');
      expect(show('a &copy; b'), 'entity[2,8) ©');
    });

    test('decimal and hex references decode', () {
      expect(show('&#169;'), 'entity[0,6) ©');
      expect(show('&#xA9;'), 'entity[0,6) ©');
      expect(show('&#X2014;'), 'entity[0,8) —');
    });

    test('every table name decodes to a single unit', () {
      expect(MarkdownConstants.htmlEntities, hasLength(32));
      MarkdownConstants.htmlEntities.forEach((String name, int char) {
        final List<InlineToken> tokens = tok('&$name;');
        expect(tokens.single, isA<InlineEntity>(), reason: name);
        expect((tokens.single as InlineEntity).char, char, reason: name);
        expect((tokens.single as InlineEntity).decoded.length, 1);
      });
    });

    test('table names decode to the glyphs HTML gives them', () {
      // Spelled out here rather than read back from the table, so a
      // wrong code point in it fails.
      const Map<String, String> glyphs = <String, String>{
        'frac34': '¾',
        'trade': '™',
        'bull': '•',
        'hellip': '…',
        'ndash': '–',
        'micro': 'µ',
        'nbsp': ' ',
        'times': '×',
      };
      glyphs.forEach((String name, String glyph) {
        expect(
          (tok('&$name;').single as InlineEntity).decoded,
          glyph,
          reason: name,
        );
      });
    });

    // A `#` after the `&` could read as a tag (`&` is a word boundary);
    // these pin only that no entity is decoded.
    void expectNoEntity(String line) =>
        expect(tok(line).whereType<InlineEntity>(), isEmpty, reason: line);

    test('unknown or malformed entities stay literal', () {
      for (final String line in const <String>[
        '&nope;',
        '&AMP;',
        '&amp',
        '& amp;',
        '&;',
        '&#;',
        '&#x;',
        '&#12a;',
        'AT&T',
        '&verylongname;',
      ]) {
        expectNoEntity(line);
      }
      expect(show('&nope;'), '');
    });

    test('references outside one printable BMP unit stay literal', () {
      for (final String line in const <String>[
        '&#0;',
        '&#31;',
        '&#xD800;',
        '&#xDFFF;',
        '&#x1F600;',
        '&#65536;',
        // Controls, separators, format and bidi controls, combining
        // marks and noncharacters would break, reorder or fuse the line
        // in the `&`'s slot.
        '&#127;',
        '&#133;',
        '&#150;',
        '&#x9F;',
        '&#x2028;',
        '&#x2029;',
        '&#x200B;',
        '&#x202E;',
        '&#x2066;',
        '&#xFEFF;',
        '&#x301;',
        '&#xFDD0;',
        '&#xFFFE;',
        '&#xFFFF;',
      ]) {
        expectNoEntity(line);
      }
      expect(show('&#32;'), 'entity[0,5)  ');
      expect(show('&#126;'), 'entity[0,6) ~');
      expect(show('&#xA0;'), 'entity[0,6)  ');
    });

    test('a numeric reference holds at most seven decimal digits', () {
      expect(show('&#0000169;'), 'entity[0,10) ©');
      expectNoEntity('&#00000169;');
    });

    test('a reference that does not decode forms no tag either', () {
      expect(show('&#x1F600;'), '');
      expect(show('&#xD800; and &#x1F;'), '');
      // A `#` that is not a whole reference still tags.
      expect(show('&#xyz'), 'tag[1,5)');
    });

    test('an entity inside a code span or a url stays literal', () {
      expect(show('`&amp;`'), 'code[0,7) inner[1,6)');
      expect(show('https://a.com/?a=1&amp;b=2'), 'url[0,26)');
    });

    test('an entity in a destination, autolink, wiki link or ghost is not '
        'decoded', () {
      for (final String line in const <String>[
        '[x](u?a&amp;b)',
        '<https://a.com?a&amp;b>',
        '[[A &amp; B]]',
        '{{&amp;}}',
      ]) {
        final List<InlineToken> tokens = tok(line);
        expect(tokens, hasLength(1), reason: line);
        expect(tokens.single, isNot(isA<InlineEntity>()), reason: line);
        expect(tokens.single.end, line.length, reason: line);
      }
    });

    test('an entity nests in emphasis and link text', () {
      expect(show('*a &amp; b*', start: 1, end: 10), 'entity[3,8) &');
      expect(show('[&lt;x](u)', start: 1, end: 6), 'entity[1,5) <');
    });

    test('an escaped ampersand is not an entity', () {
      expect(show(r'\&amp;'), 'escape[0,2)');
    });
  });

  group('hard breaks', () {
    bool breaks(String line) => MarkdownInlineGrammar.endsWithHardBreak(
      line,
      0,
      line.length,
      tok(line),
    );

    test('a trailing backslash after content is a hard break', () {
      expect(breaks(r'next line\'), isTrue);
      expect(breaks(r'a \'), isTrue);
      expect(breaks(r'**a**\'), isTrue);
    });

    test('an escaped trailing backslash is not', () {
      expect(breaks(r'a\\'), isFalse);
      expect(breaks(r'a\\\'), isTrue);
    });

    test('a line that is only a backslash is not', () {
      expect(breaks(r'\'), isFalse);
      expect(breaks(r'   \'), isFalse);
    });

    test('a backslash a token covers is not', () {
      // A bare URL takes the `\` into itself, the one token besides an
      // escape that can end on one.
      expect(tok(r'see https://a.com/x\').single.end, 20);
      expect(breaks(r'see https://a.com/x\'), isFalse);
      expect(breaks('a'), isFalse);
    });
  });

  group('inline comments', () {
    List<(Type, int, int)> shape(String line) => [
      for (final t in tok(line)) (t.runtimeType, t.start, t.end),
    ];

    test('a %%…%% run is one opaque atom, tags and links inert inside', () {
      expect(shape('a %%x #t [l](u)%% b'), [(InlineComment, 2, 17)]);
    });

    test('an unclosed %% is literal and opens nothing', () {
      expect(shape('a %%unclosed #t'), [(InlineTag, 13, 15)]);
    });

    test('adjacent comments are two atoms', () {
      expect(shape('%%a%%%%b%%'), [
        (InlineComment, 0, 5),
        (InlineComment, 5, 10),
      ]);
    });

    test('a comment never swallows a ghost', () {
      final tokens = tok('a %%x {{ g }} y%% b');
      expect(tokens.whereType<InlineComment>(), isEmpty);
      expect(tokens.whereType<InlineGhost>(), hasLength(1));
    });

    test('a lone % is no candidate, %% is', () {
      expect(MarkdownInlineGrammar.hasCandidates('50% off'), isFalse);
      expect(MarkdownInlineGrammar.hasCandidates('%%'), isTrue);
    });
  });
}
