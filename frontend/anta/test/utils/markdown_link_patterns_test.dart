import 'package:anta/utils/markdown_link_patterns.dart';
import 'package:flutter_test/flutter_test.dart';

/// The link module's matchers on their own, below the inline grammar
/// that places them: destinations and titles, balanced parentheses in
/// bare URLs, angle autolinks, wiki aliases, the paste-protection shapes
/// and the Obsidian suffixes a tapped wiki title is read through.
void main() {
  group('matchInlineLinkAt destinations', () {
    String? dest(String line, [int? limit]) =>
        MarkdownLinkPatterns.matchInlineLinkAt(line, 0, limit)?.urlOf(line);

    test('a plain destination is the whole inside', () {
      final link = MarkdownLinkPatterns.matchInlineLinkAt('[a](b)', 0)!;
      expect(link.urlStart, 4);
      expect(link.urlEnd, 5);
      expect(link.destStart, 4);
      expect(link.destEnd, 5);
      expect(link.end, 6);
    });

    test('a title in any of the three quotings is dropped', () {
      expect(dest('[t](https://x.com/s "Guide")'), 'https://x.com/s');
      expect(dest("[t](u 'T')"), 'u');
      expect(dest('[t](u (T))'), 'u');
      expect(dest('[t](u "a)b")'), 'u');
    });

    test('balanced parentheses close the link at the outer paren', () {
      const line = '[w](https://en.wikipedia.org/wiki/Foo_(bar)) x';
      final link = MarkdownLinkPatterns.matchInlineLinkAt(line, 0)!;
      expect(link.end, 44);
      expect(link.urlOf(line), 'https://en.wikipedia.org/wiki/Foo_(bar)');
    });

    test('an angle destination may hold blanks and a paren', () {
      expect(dest('[t](<a b>)'), 'a b');
      expect(dest('[t](<a)b> "T")'), 'a)b');
    });

    test('the first-paren reading keeps the inside first blank-free run', () {
      expect(dest('[a](b(c) d'), 'b(c');
      expect(dest('[a](b c)'), 'b');
      expect(dest('[a]( )'), '');
      expect(dest('[t](u "T" x)'), 'u');
      expect(dest('[t](<a b)'), '<a');
      // A title the reading cannot close is never opened.
      expect(dest("[Guide](https://x.y 'Bob's guide')"), 'https://x.y');
      expect(dest('[a](u "say "hi"")'), 'u');
    });

    test('the fallback keeps the concealed range of the first paren', () {
      const line = "[g](https://x.y 'Bob's guide') tail";
      final link = MarkdownLinkPatterns.matchInlineLinkAt(line, 0)!;
      expect(link.urlStart, 4);
      expect(link.urlEnd, line.indexOf(')'));
      expect(link.destStart, 4);
      expect(link.destEnd, 15);
    });

    test('a backslash escapes the next unit in the title and the run', () {
      expect(dest(r'[t](https://x.com "say \"hi\"")'), 'https://x.com');
      expect(dest(r'[t](u "a \" b")'), 'u');
      expect(dest(r"[t](u 'Bob\'s')"), 'u');
      expect(dest(r'[t](a\)b)'), r'a\)b');
      expect(dest(r'[t](a\(b)'), r'a\(b');
    });

    test('empty parts are still no link', () {
      expect(dest('[a]()'), isNull);
      expect(dest('[](b)'), isNull);
      expect(dest('[a](<>)'), '<>');
    });

    test('an image bracket may leave its alt empty', () {
      final image = MarkdownLinkPatterns.matchImageAt(
        '![](https://x.y/a.png)',
        1,
      )!;
      expect(image.textStart, image.textEnd);
      expect(image.urlOf('![](https://x.y/a.png)'), 'https://x.y/a.png');
      expect(image.end, 22);
      expect(MarkdownLinkPatterns.matchImageAt('![a](u "T")', 1)?.end, 11);
      expect(MarkdownLinkPatterns.matchImageAt('![]()', 1), isNull);
      expect(MarkdownLinkPatterns.matchImageAt('![](u)', 1, 5), isNull);
    });

    test('the limit is never read past', () {
      const line = '[w](x_(b)) tail)';
      expect(dest(line, 10), 'x_(b)');
      // Cut before the outer paren, the range reads exactly what the
      // substring `[w](x_(b)` reads: the first-paren fallback.
      expect(dest(line, 9), 'x_(b');
      expect(dest(line.substring(0, 9)), 'x_(b');
      expect(dest('[t](u "T") y', 9), isNull);
    });
  });

  group('matchBareUrlEnd parentheses', () {
    int end(String line, [int start = 0, int? limit]) =>
        MarkdownLinkPatterns.matchBareUrlEnd(line, start, limit);

    test('a balanced pair stays in the url', () {
      const url = 'https://en.wikipedia.org/wiki/Squat_(exercise)';
      expect(end(url), url.length);
      expect(end('$url.'), url.length);
      expect(end('$url),'), url.length);
    });

    test('a close paren that closes nothing ends the url', () {
      expect(end('(https://x.y).', 1), 12);
      expect(end('https://x.y/a)b'), 13);
    });

    test('an open paren the url never closes ends it before that paren', () {
      expect(end('https://x.y/a(b'), 13);
      expect(end('https://x.y/a(b)c(d'), 17);
      expect(end('www.x.y/(a'), 8);
    });

    test('the trailing trim still applies after a balanced pair', () {
      expect(end('https://x.y/(a)*'), 15);
      expect(end('https://x.y/(a)._'), 15);
    });

    test('the limit clamps before parentheses are weighed', () {
      expect(end('https://x.y/(a)', 0, 14), 12);
    });

    test('the paste protection class keeps the whole url', () {
      const line = 'see https://en.wikipedia.org/wiki/Squat_(exercise) now';
      final match = MarkdownLinkPatterns.bareUrl.firstMatch(line)!;
      expect(match.group(0), 'https://en.wikipedia.org/wiki/Squat_(exercise)');
    });
  });

  group('matchAutolinkAt', () {
    MarkdownAutolink? at(String line, [int open = 0, int? limit]) =>
        MarkdownLinkPatterns.matchAutolinkAt(line, open, limit);

    test('the four schemes the editor opens, in any case', () {
      for (final line in <String>[
        '<http://x.y>',
        '<https://x.y/a?b=c>',
        '<mailto:a@b.c>',
        '<tel:+40700>',
        '<HTTPS://X.Y>',
      ]) {
        final auto = at(line);
        expect(auto, isNotNull, reason: line);
        expect(auto!.isEmail, isFalse, reason: line);
        expect(auto.end, line.length, reason: line);
      }
    });

    test('an address with a dotted host is an email autolink', () {
      final auto = at('<first.last+tag@mail.example.com>')!;
      expect(auto.isEmail, isTrue);
      expect(auto.innerStart, 1);
    });

    test('everything else stays literal', () {
      for (final line in <String>[
        '<b>',
        '<>',
        '<https:>',
        '<ftp://x.y>',
        '<javascript:alert(1)>',
        '<https://x y>',
        '<https://x.y',
        '<<https://x.y>',
        '<me@localhost>',
        '<me@x..y>',
        '<me@-x.y>',
        '<me@x-.y>',
        '<@x.y>',
        '<me@x.y@z.w>',
      ]) {
        expect(at(line), isNull, reason: line);
      }
    });

    test('an address past the closing bracket is never read', () {
      expect(at('<b> me@x.y'), isNull);
      expect(at('<b@x.y> me@x.y')?.end, 7);
      expect(at('<Tel:1>')?.isEmail, isFalse);
      expect(at('<telx:1>'), isNull);
    });

    test('the limit is never read past', () {
      expect(at('<https://x.y>', 0, 12), isNull);
      expect(at('a <https://x.y> b', 2, 15)?.end, 15);
    });
  });

  group('matchWikiLinkAt aliases', () {
    MarkdownWikiLink? at(String line) =>
        MarkdownLinkPatterns.matchWikiLinkAt(line, 0);

    test('the pipe ends the title and opens the alias', () {
      final wiki = at('[[Leg Day|legs]]')!;
      expect(wiki.titleOf('[[Leg Day|legs]]'), 'Leg Day');
      expect(wiki.aliasStart, 10);
      expect(wiki.closeStart, 14);
      expect(wiki.end, 16);
    });

    test('a plain title has no alias and closes where its title ends', () {
      final wiki = at('[[a]]')!;
      expect(wiki.aliasStart, isNull);
      expect(wiki.titleEnd, wiki.closeStart);
    });

    test('a blank alias is no alias', () {
      expect(at('[[a|]]')!.aliasStart, isNull);
      expect(at('[[a|  ]]')!.aliasStart, isNull);
    });

    test('a blank title, a second pipe or a bracket in the alias refuse', () {
      expect(at('[[|a]]'), isNull);
      expect(at('[[a|b|c]]'), isNull);
      expect(at('[[a|b[c]]'), isNull);
    });

    test('the paste protection shape covers the alias form', () {
      expect(MarkdownLinkPatterns.wikiLink.hasMatch('[[a b|c d]]'), isTrue);
      expect(MarkdownLinkPatterns.wikiLink.hasMatch('[[a]]'), isTrue);
      expect(MarkdownLinkPatterns.wikiLink.hasMatch('[[a|b|c]]'), isFalse);
    });
  });

  group('MarkdownWikiTarget.parse', () {
    test('a plain title is its own note with no heading', () {
      final target = MarkdownWikiTarget.parse('  Leg Day ');
      expect(target.title, 'Leg Day');
      expect(target.note, 'Leg Day');
      expect(target.heading, isNull);
      expect(target.hasSuffix, isFalse);
    });

    test('a heading suffix splits at the first hash', () {
      final target = MarkdownWikiTarget.parse('Leg Day # Warm-up ');
      expect(target.note, 'Leg Day');
      expect(target.heading, 'Warm-up');
      expect(target.hasSuffix, isTrue);
    });

    test('a heading path lands on its last segment', () {
      expect(MarkdownWikiTarget.parse('N#Week 1#Day 2').heading, 'Day 2');
    });

    test('the whole fragment is kept for a heading that holds a hash', () {
      final target = MarkdownWikiTarget.parse('Log#Week #3');
      expect(target.heading, '3');
      expect(target.wholeHeading, 'Week #3');
      expect(
        MarkdownWikiTarget.parse('N#C# basics^b').wholeHeading,
        'C# basics',
      );
      expect(MarkdownWikiTarget.parse('N#^b').wholeHeading, isNull);
      expect(MarkdownWikiTarget.parse('N').wholeHeading, isNull);
    });

    test('heading readings try the whole fragment before its last segment', () {
      expect(MarkdownWikiTarget.headingReadingsOf('Week #3'), ['Week #3', '3']);
      expect(MarkdownWikiTarget.headingReadingsOf(' Week 1#Day 2 '), [
        'Week 1#Day 2',
        'Day 2',
      ]);
      expect(MarkdownWikiTarget.headingReadingsOf('Squat'), ['Squat']);
      expect(MarkdownWikiTarget.headingReadingsOf('a#'), ['a#']);
      expect(MarkdownWikiTarget.headingReadingsOf('  '), isEmpty);
    });

    test('block references open the note and name no heading', () {
      for (final raw in <String>['Leg Day^abc', 'Leg Day#^abc']) {
        final target = MarkdownWikiTarget.parse(raw);
        expect(target.note, 'Leg Day', reason: raw);
        expect(target.heading, isNull, reason: raw);
      }
    });

    test('a trailing .md is dropped in any case', () {
      expect(MarkdownWikiTarget.parse('Leg Day.md').note, 'Leg Day');
      expect(MarkdownWikiTarget.parse('Leg Day.MD#h').note, 'Leg Day');
      expect(MarkdownWikiTarget.parse('Leg Day.md#h').heading, 'h');
      expect(MarkdownWikiTarget.parse('.md').note, '.md');
    });

    test('a bare heading names the current note', () {
      final target = MarkdownWikiTarget.parse('#Warm-up');
      expect(target.note, isEmpty);
      expect(target.heading, 'Warm-up');
    });

    test('an empty heading part is no heading', () {
      expect(MarkdownWikiTarget.parse('Leg Day#').heading, isNull);
      expect(MarkdownWikiTarget.parse('Leg Day#  ').heading, isNull);
    });
  });

  group('MarkdownWikiTarget.resolve', () {
    /// `found byNote asked|asked`, the lookup order made visible.
    Future<String> resolve(String raw, Set<String> notes) async {
      final asked = <String>[];
      final (found, byNote) = await MarkdownWikiTarget.parse(raw).resolve((
        title,
      ) async {
        asked.add(title);
        return notes.contains(title) ? title : null;
      });
      return '$found $byNote ${asked.join('|')}';
    }

    test('the title as typed wins over its note part', () async {
      expect(
        await resolve('C# basics', {'C# basics', 'C'}),
        'C# basics false C# basics',
      );
    });

    test('a suffixed title falls back to its note part', () async {
      for (final raw in <String>['Squat#Warm-up', 'Squat.md', 'Squat^b']) {
        expect(
          await resolve(raw, {'Squat'}),
          'Squat true $raw|Squat',
          reason: raw,
        );
      }
    });

    test('the note part is asked only after a suffix and a miss', () async {
      expect(await resolve('Squat', {}), 'null false Squat');
      expect(await resolve('#Warm-up', {'Squat'}), 'null false #Warm-up');
      expect(await resolve('Gone#h', {}), 'null false Gone#h|Gone');
    });
  });
}
