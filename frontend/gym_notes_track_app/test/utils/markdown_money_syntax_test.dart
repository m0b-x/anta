import 'package:flutter_test/flutter_test.dart';
import 'package:gym_notes_track_app/utils/markdown_line_shape.dart';
import 'package:gym_notes_track_app/utils/markdown_money_syntax.dart';

MoneyLineMatch? p(String s) => MarkdownMoneySyntax.parse(s);

MoneyLedgerCollection fold(List<String> lines, {int start = 0}) =>
    MarkdownMoneySyntax.collectEntries(
      lineCount: lines.length,
      lineAt: (i) => lines[i],
      isInert: (_) => false,
      startCents: start,
    );

int valueAt(MoneyLedgerCollection c, int lineIndex) =>
    c.entries.firstWhere((e) => e.lineIndex == lineIndex).valueAfter;

BigInt bigRoundedDiv(BigInt a, BigInt b) {
  final r = (a.abs() + (b >> 1)) ~/ b;
  return a.isNegative ? -r : r;
}

int bigClamp(BigInt v) {
  final l = BigInt.from(MarkdownMoneySyntax.balanceLimitCents);
  if (v < -l) return -l.toInt();
  if (v > l) return l.toInt();
  return v.toInt();
}

void main() {
  group('amount limits', () {
    test('11-digit set parses clean and exact', () {
      final m = p(r'$= 99999999999.99')!;
      expect(m.error, isNull);
      expect(m.amountFixed ~/ 100, 9999999999999);
    });

    test('12-digit set is an amountTooLarge error row', () {
      final m = p(r'$= 999999999999')!;
      expect(m.error, MoneyLineError.amountTooLarge);
    });

    test('over-limit amount keeps label offsets', () {
      const line = r'$+ 999999999999 groceries';
      final m = p(line)!;
      expect(m.error, MoneyLineError.amountTooLarge);
      expect(line.substring(m.labelStart), 'groceries');
    });

    test('3 decimals on an amount is tooManyDecimals', () {
      expect(p(r'$+ 1.234')!.error, MoneyLineError.tooManyDecimals);
    });

    test('factor limits: 5 int digits / 5 decimals error', () {
      expect(p(r'$* 12345')!.error, MoneyLineError.amountTooLarge);
      expect(p(r'$* 1.12345')!.error, MoneyLineError.tooManyDecimals);
    });

    test(r'$/ 0 is a divideByZero error row', () {
      expect(p(r'$/ 0')!.error, MoneyLineError.divideByZero);
    });

    test('label-first over-limit amount is an error row', () {
      expect(
        p(r'$= Net worth: 999999999999')!.error,
        MoneyLineError.amountTooLarge,
      );
    });

    test('non-amount shapes still render plain (null)', () {
      expect(p(r'$+ 123abc'), isNull);
      expect(p(r'$+ lunch'), isNull);
    });

    test('label-first missing amount still errors', () {
      expect(p(r'$= Label:')!.error, MoneyLineError.labelFirstMissingAmount);
    });
  });

  group('overflow-safe arithmetic', () {
    const balances = [
      0, 1, -1, 99, 12345, 999999, 123456789012, 9999999999999,
      50000000000000, 99999999999999, -99999999999999, -12345678901234,
    ];
    const factors = [1, 3, 5000, 9999, 10000, 11900, 19900, 33333, 99999999];

    test('multiply matches a BigInt reference over the grid', () {
      for (final b in balances) {
        for (final f in factors) {
          final m = p(
            '\$* ${f ~/ 10000}.${(f % 10000).toString().padLeft(4, '0')}',
          )!;
          expect(m.amountFixed, f);
          expect(
            MarkdownMoneySyntax.apply(b, m),
            bigClamp(
              bigRoundedDiv(BigInt.from(b) * BigInt.from(f), BigInt.from(10000)),
            ),
            reason: 'mul b=$b f=$f',
          );
        }
      }
    });

    test('divide matches a BigInt reference over the grid', () {
      for (final b in balances) {
        for (final f in factors) {
          final m = p(
            '\$/ ${f ~/ 10000}.${(f % 10000).toString().padLeft(4, '0')}',
          )!;
          expect(
            MarkdownMoneySyntax.apply(b, m),
            bigClamp(
              bigRoundedDiv(BigInt.from(b) * BigInt.from(10000), BigInt.from(f)),
            ),
            reason: 'div b=$b f=$f',
          );
        }
      }
    });

    test('giant multiply/divide pin at the limit, never wrap', () {
      final pinned = MarkdownMoneySyntax.apply(
        99999999999999,
        p(r'$* 9999.9999')!,
      );
      expect(pinned, MarkdownMoneySyntax.balanceLimitCents);
      expect(MarkdownMoneySyntax.valuePinned(pinned), isTrue);
      expect(
        MarkdownMoneySyntax.apply(-99999999999999, p(r'$/ 0.0001')!),
        -MarkdownMoneySyntax.balanceLimitCents,
      );
    });

    test('everyday arithmetic is exact to the cent', () {
      expect(MarkdownMoneySyntax.apply(10000, p(r'$* 1.19')!), 11900);
      expect(MarkdownMoneySyntax.apply(3333, p(r'$/ 3')!), 1111);
      expect(MarkdownMoneySyntax.apply(1000, p(r'$/ 3')!), 333);
      expect(MarkdownMoneySyntax.apply(-1000, p(r'$/ 3')!), -333);
      expect(MarkdownMoneySyntax.apply(5, p(r'$* 0.5')!), 3);
    });

    test('format of the limit', () {
      expect(
        MarkdownMoneySyntax.formatCents(MarkdownMoneySyntax.balanceLimitCents),
        '999999999999.99',
      );
    });
  });

  group('window counts', () {
    test('any-length counts parse', () {
      const line = r'$~ 1000 label';
      final m = p(line)!;
      expect(m.windowCount, 1000);
      expect(line.substring(m.labelStart), 'label');
      expect(p(r'$^ 2024 spending')!.windowCount, 2024);
    });

    test('absurd digit runs saturate without overflow', () {
      expect(
        p(r'$~ 99999999999999999999 x')!.windowCount,
        greaterThanOrEqualTo(1000000000),
      );
    });

    test('zero and non-count shapes stay label text', () {
      expect(p(r'$~ 0 x')!.windowCount, 1);
      expect(p(r'$~ 3x things')!.windowCount, 1);
    });

    test('ALL sentinel', () {
      expect(p(r'$~ ALL label')!.windowCount, -1);
      expect(p(r'$^ ALL')!.windowCount, -1);
    });

    test('a label is always preceded by a space', () {
      // The editor conceals the whole chrome run up to `labelStart - 1`
      // and leaves that one space visible to separate the painted chip
      // from the label; if the parser could ever land `labelStart`
      // directly on a non-space, the row would render glued together.
      const lines = [
        r'$~ 2 label',
        r'$^ ALL label',
        r'$~ teal: 2 label',
        r'$~ 2 teal: label',
        r'$^ 12 teal: Change: $ dollars',
      ];
      for (final line in lines) {
        final m = p(line)!;
        expect(m.labelStart, lessThan(line.length), reason: line);
        expect(line[m.labelStart - 1], ' ', reason: line);
      }
      // A display row always has a space after its marker, so the
      // concealed chrome run is never empty either.
      expect(p(r'$~2 label'), isNull);
    });

    test('accent token composes on either side of the count', () {
      const after = r'$~ 2 teal: Change of Balance: $ dollars';
      final a = p(after)!;
      expect(a.windowCount, 2);
      expect(after.substring(a.accentStart, a.accentEnd), 'teal');
      expect(a.valueSlot, greaterThanOrEqualTo(0));
      const before = r'$~ teal: 2 label';
      final b = p(before)!;
      expect(b.windowCount, 2);
      expect(before.substring(b.accentStart, b.accentEnd), 'teal');
    });
  });

  group('heading prefix', () {
    test('space after the hashes is optional', () {
      final m = p(r'##$$ Net worth')!;
      expect(m.headerLevel, 2);
      expect(m.kind, MoneyLineKind.total);
      expect(p(r'## $$ x')!.headerLevel, 2);
    });

    test('full no-space compose: hashes + accent + slot + trailing text', () {
      const line = r'#####$$ teal: Money current: $ and after';
      final m = p(line)!;
      expect(m.headerLevel, 5);
      expect(line.substring(m.accentStart, m.accentEnd), 'teal');
      expect(m.valueSlot, greaterThanOrEqualTo(0));
    });

    test('rejections', () {
      expect(p(r'#######$$ x'), isNull);
      expect(p(r'##$5 coffee'), isNull);
    });

    test('probe agrees with parse', () {
      expect(MarkdownMoneySyntax.leadsWithMoney(r'##$$ x'), isTrue);
      expect(MarkdownMoneySyntax.leadsWithMoney(r'#######$$ x'), isFalse);
      expect(MarkdownMoneySyntax.leadsWithMoney('## heading'), isFalse);
    });
  });

  group('folds and display values', () {
    test(r'$~ floors at the FIRST $= checkpoint', () {
      final one = fold([r'$= 100', r'$+ 50', r'$~ 5']);
      expect(valueAt(one, 2), 5000);
      final two = fold([r'$= 100', r'$+ 10', r'$= 200', r'$+ 5', r'$~ 999']);
      expect(valueAt(two, 4), 10500);
    });

    test(r'a note with no $= falls back to the start balance', () {
      expect(valueAt(fold([r'$+ 50', r'$~ 3']), 1), 5000);
    });

    test(r'error $= lines are fold-inert, incl. window shifts', () {
      final c = fold([r'$= 100', r'$= 999999999999', r'$+ 10', r'$?']);
      expect(valueAt(c, 3), 1000);
      expect(c.entries[1].match.error, MoneyLineError.amountTooLarge);
      expect(c.entryLines, [0, 2]);
      expect(c.anchorLines, [0]);
    });

    test('MoneyFold.step agrees with collectEntries line by line', () {
      final lines = [
        r'$= 100',
        r'$+ 25.50 groceries',
        r'$- 8 coffee',
        r'$* 1.19',
        r'$$',
        r'$?',
        r'$= 200',
        r'$/ 2',
        r'$^ 2',
        r'$~ 2',
        r'$~ ALL',
        r'$/ 0',
        r'$! 500 budget',
        r'$- 40 lunch',
        r'$!',
      ];
      final collected = fold(lines, start: 700);
      final f = MoneyFold(700);
      for (final e in collected.entries) {
        expect(f.step(e.match), e.valueAfter, reason: 'line ${e.lineIndex}');
      }
    });

    test('isCountedEntry is the entry predicate', () {
      expect(MarkdownMoneySyntax.isCountedEntry(p(r'$+ 5')!), isTrue);
      expect(MarkdownMoneySyntax.isCountedEntry(p(r'$$')!), isFalse);
      expect(MarkdownMoneySyntax.isCountedEntry(p(r'$/ 0')!), isFalse);
    });
  });

  group('window entry resolvers', () {
    final lines = [
      r'$= 100', // 0
      r'$+ 10', // 1
      r'$+ 20', // 2
      r'$= 200', // 3
      r'$+ 5', // 4
      r'$~ 2', // 5
      r'$^ 2', // 6
      r'$~ ALL', // 7
      r'$^ ALL', // 8
    ];

    test(r'$~ N lists from the Nth-most-recent $=', () {
      final c = fold(lines);
      final tapped = c.entries.firstWhere((e) => e.lineIndex == 5).match;
      final w = MarkdownMoneySyntax.spanWindowEntries(c, tapped, 5);
      expect(w.first.lineIndex, 0);
      expect(w.last.lineIndex, 5);
    });

    test(r'$^ N clamps to the current period', () {
      final c = fold(lines);
      final tapped = c.entries.firstWhere((e) => e.lineIndex == 6).match;
      final w = MarkdownMoneySyntax.diffWindowEntries(c, tapped, 6);
      expect(w.first.lineIndex, 3);
      expect(w.last.lineIndex, 6);
    });

    test('ALL sentinel never throws and spans the whole history', () {
      final c = fold(lines);
      final span = c.entries.firstWhere((e) => e.lineIndex == 7).match;
      final diff = c.entries.firstWhere((e) => e.lineIndex == 8).match;
      expect(
        MarkdownMoneySyntax.spanWindowEntries(c, span, 7).first.lineIndex,
        0,
      );
      expect(
        MarkdownMoneySyntax.diffWindowEntries(c, diff, 8).first.lineIndex,
        3,
      );
    });

    test('no entries at all: diff window lists only the tapped row', () {
      final c = fold([r'$^ 2 nothing yet']);
      final tapped = c.entries.single.match;
      final w = MarkdownMoneySyntax.diffWindowEntries(c, tapped, 0);
      expect(w.single.lineIndex, 0);
    });
  });

  group(r'$= amount is the row value', () {
    // The preview renders a `$=` row's amount as
    // `formatCentsWithSymbol(value)` rather than echoing the typed
    // digits, which is how the currency finally shows on the one row
    // that has no computed annotation to carry it. That substitution is
    // only sound while a `set` row's fold value is exactly the amount
    // the user typed — pinned here so nobody can quietly break it.
    test('fold value equals the typed amount, every spelling', () {
      const cases = {
        r'$= 5000': 500000,
        r'$= 1234.5': 123450,
        r'$= 0': 0,
        r'$= Net worth: 5000': 500000,
        r'$= 99999999999.99': 9999999999999,
      };
      cases.forEach((line, cents) {
        // A non-zero start balance must not leak into a `$=` row.
        expect(valueAt(fold([line], start: 777), 0), cents, reason: line);
      });
    });

    test('a clean set row can never be pinned', () {
      // 11 integer digits is the parse cap, an order of magnitude under
      // the balance clamp, so the amount can never render in the warning
      // colour — anything larger is an error row on a different path.
      final maxSet = valueAt(fold([r'$= 99999999999.99']), 0);
      expect(MarkdownMoneySyntax.valuePinned(maxSet), isFalse);
      expect(p(r'$= 999999999999')!.error, MoneyLineError.amountTooLarge);
    });

    test('currency lands in its configured position', () {
      const v = 500000;
      expect(
        MarkdownMoneySyntax.formatCentsWithSymbol(v, symbol: 'lei', suffix: true),
        '5000.00 lei',
      );
      expect(
        MarkdownMoneySyntax.formatCentsWithSymbol(v, symbol: r'$', suffix: false),
        r'$5000.00',
      );
      expect(
        MarkdownMoneySyntax.formatCentsWithSymbol(-v, symbol: r'$', suffix: false),
        r'-$5000.00',
      );
      expect(
        MarkdownMoneySyntax.formatCentsWithSymbol(v, symbol: '', suffix: false),
        '5000.00',
      );
    });
  });

  group('inline currency word', () {
    int curEnd(String line, String symbol) =>
        MarkdownMoneySyntax.inlineCurrencyEnd(line, p(line)!, symbol);

    String labelOf(String line, String symbol) {
      final m = p(line)!;
      final from = MarkdownMoneySyntax.labelStartAfterCurrency(
        line,
        m,
        symbol,
      );
      final to = m.labelStart < m.amountStart ? m.labelEnd - 1 : m.labelEnd;
      return from < to ? line.substring(from, to) : '';
    }

    test('the configured currency is consumed, the rest stays label', () {
      expect(labelOf(r'$= 500 lei', 'lei'), '');
      expect(labelOf(r'$+ 50 lei coffee', 'lei'), 'coffee');
      expect(labelOf(r'$= 500 groceries', 'lei'), 'groceries');
      expect(labelOf(r'$= 500 lei groceries', 'lei'), 'groceries');
    });

    test('matching is ASCII-case-insensitive and whole-word', () {
      expect(curEnd(r'$= 500 Lei', 'lei'), 10);
      expect(curEnd(r'$= 500 LEI', 'lei'), 10);
      expect(curEnd(r'$= 500 leisure', 'lei'), -1);
      expect(labelOf(r'$= 500 leisure boat', 'lei'), 'leisure boat');
    });

    test('non-ASCII prefix symbols match unchanged', () {
      expect(labelOf(r'$= 500 € trip', '€'), 'trip');
      expect(labelOf(r'$= 500 $ trip', r'$'), 'trip');
    });

    test('only the configured symbol wins — no guessing', () {
      // Same source, three currency settings: the word is chrome only
      // when it is this note's currency, and goes back to being a label
      // the moment the setting changes.
      expect(labelOf(r'$= 500 lei', 'lei'), '');
      expect(labelOf(r'$= 500 lei', '€'), 'lei');
      expect(labelOf(r'$= 500 lei', ''), 'lei');
      expect(labelOf(r'$= 500 EUR', 'lei'), 'EUR');
    });

    test('label-first rows carry it after the amount', () {
      const line = r'$= Net worth: 500 lei';
      final m = p(line)!;
      expect(m.error, isNull);
      expect(line.substring(m.amountStart, m.amountEnd), '500');
      expect(m.amountFixed, p(r'$= Net worth: 500')!.amountFixed);
      // The word trails the amount, outside the label, so the label
      // start is untouched while the word itself is recognised.
      expect(MarkdownMoneySyntax.inlineCurrencyEnd(line, m, 'lei'), line.length);
      expect(labelOf(line, 'lei'), 'Net worth');
      expect(curEnd(r'$= Net worth: 500', 'lei'), -1);
    });

    test('the exact reported line renders', () {
      // `# $= teal: Initia Balance(lei):70897 lei` — heading, accent
      // token, parenthesised text inside the label, no space after the
      // colon, and the currency typed at the end.
      const line = r'# $= teal: Initia Balance(lei):70897 lei';
      final m = p(line)!;
      expect(m.error, isNull);
      expect(m.headerLevel, 1);
      expect(line.substring(m.accentStart, m.accentEnd), 'teal');
      expect(line.substring(m.amountStart, m.amountEnd), '70897');
      expect(labelOf(line, 'lei'), 'Initia Balance(lei)');
      expect(MarkdownMoneySyntax.inlineCurrencyEnd(line, m, 'lei'), line.length);
      // Same ledger value as the spelling that already worked.
      expect(
        valueAt(fold([line]), 0),
        valueAt(fold([r'# $= teal: Initia Balance(lei):70897']), 0),
      );
    });

    test('a non-currency trailing word stays visible, never eaten', () {
      const line = r'$= Net worth: 500 RON';
      final m = p(line)!;
      expect(MarkdownMoneySyntax.inlineCurrencyEnd(line, m, 'lei'), -1);
      // The renderer emits `[amountEnd, length)` when it is not the
      // currency, so the typed word survives at its true offsets.
      expect(line.substring(m.amountEnd), ' RON');
    });

    test(r'a trailing `$` is the currency when the symbol is `$`', () {
      // The trailing region scans for a slot now, so the raw match finds
      // one — but with `$` as the configured symbol the word reads as
      // the typed currency, and [effectiveValueSlot] voids it so the
      // row never renders its value twice. Any other symbol keeps the
      // slot: text before the value with the value at the end.
      const line = r'$= Net worth: 500 $';
      final m = p(line)!;
      expect(m.valueSlot, line.length - 1);
      expect(MarkdownMoneySyntax.inlineCurrencyEnd(line, m, r'$'), line.length);
      expect(MarkdownMoneySyntax.effectiveValueSlot(line, m, r'$'), -1);
      expect(
        MarkdownMoneySyntax.effectiveValueSlot(line, m, 'lei'),
        line.length - 1,
      );
      expect(MarkdownMoneySyntax.inlineCurrencyEnd(line, m, 'lei'), -1);
    });

    test('display rows without an amount take none', () {
      expect(curEnd(r'$$ lei', 'lei'), -1);
      expect(curEnd(r'$? lei', 'lei'), -1);
      // ...but a `$^ N` count is an amount, so the word after it is the
      // start of the label and can be the currency.
      expect(labelOf(r'$^ 2 lei spent', 'lei'), 'spent');
    });

    test('composes with headings, accents and value slots', () {
      const line = r'### $= teal: 500 lei Net worth: $ today';
      final m = p(line)!;
      expect(m.headerLevel, 3);
      expect(line.substring(m.accentStart, m.accentEnd), 'teal');
      expect(m.valueSlot, greaterThan(0));
      expect(labelOf(line, 'lei'), r'Net worth: $ today');
      // The slot still sits inside the label the renderer will emit.
      final from = MarkdownMoneySyntax.labelStartAfterCurrency(line, m, 'lei');
      expect(m.valueSlot, greaterThan(from));
    });

    test('the ledger cannot tell the two spellings apart', () {
      // Parse stays currency-agnostic: the word is display-only chrome,
      // so folds, windows and balances are byte-identical either way.
      final plain = fold([r'$= 500', r'$+ 50 coffee', r'$?']);
      final typed = fold([r'$= 500 lei', r'$+ 50 lei coffee', r'$?']);
      for (var i = 0; i < plain.entries.length; i++) {
        expect(typed.entries[i].valueAfter, plain.entries[i].valueAfter);
      }
      expect(typed.entryLines, plain.entryLines);
      expect(typed.anchorLines, plain.anchorLines);
      expect(p(r'$= 500 lei')!.amountFixed, p(r'$= 500')!.amountFixed);
    });
  });

  group('label-first trailing text', () {
    test('free text may follow the amount', () {
      const line = r'$= Net worth: 5000 as of today';
      final m = p(line)!;
      expect(m.error, isNull);
      expect(m.amountFixed, 50000000);
      expect(line.substring(m.labelStart, m.labelEnd - 1), 'Net worth');
      expect(line.substring(m.amountStart, m.amountEnd), '5000');
      expect(line.substring(m.amountEnd), ' as of today');
    });

    test(r'the LAST `: amount` pair wins, deterministically', () {
      const line = r'$= A: 100 B: 200 end';
      final m = p(line)!;
      expect(line.substring(m.amountStart, m.amountEnd), '200');
      expect(line.substring(m.labelStart, m.labelEnd - 1), 'A: 100 B');
      // Precedence pin: a lowercase one-word lead is the accent-token
      // shape and wins first, making the FIRST number the amount — the
      // same reading `$= a: 100` always had.
      final n = p(r'$= a: 100 b: 200 end')!;
      expect(n.amountFixed, 1000000);
    });

    test('digit:digit with a tight colon is a time, never an amount', () {
      final m = p(r'$= Note: 500 at 9:30')!;
      expect(m.amountFixed, 5000000);
      // A line whose only colon-adjacent number is time-shaped stays
      // plain text — this also fixes the old line-end quirk where
      // `$= Standup 9:30` set the balance to 30.
      expect(p(r'$= Standup 9:30 daily'), isNull);
      expect(p(r'$= Standup 9:30'), isNull);
      expect(p(r'$= 2024:500'), isNull);
      // A space after the colon reads as `label: amount` again.
      expect(p(r'$= Total 2024: 500')!.amountFixed, 5000000);
    });

    test('currency word and trailing text compose', () {
      const line = r'$= Net worth: 500 lei as of today';
      final m = p(line)!;
      expect(line.substring(m.amountStart, m.amountEnd), '500');
      expect(
        MarkdownMoneySyntax.inlineCurrencyEnd(line, m, 'lei'),
        line.indexOf('lei') + 3,
      );
      expect(MarkdownMoneySyntax.inlineCurrencyEnd(line, m, '€'), -1);
      expect(valueAt(fold([line]), 0), valueAt(fold([r'$= Net worth: 500']), 0));
    });

    test('the reported heading line extends with trailing text', () {
      const line = r'# $= teal: Initia Balance(lei):70897 lei as of today';
      final m = p(line)!;
      expect(m.error, isNull);
      expect(m.headerLevel, 1);
      expect(line.substring(m.amountStart, m.amountEnd), '70897');
    });

    test(r'$! targets take the label-first shape too', () {
      const line = r'$! Vacation fund: 500 by December';
      final m = p(line)!;
      expect(m.kind, MoneyLineKind.target);
      expect(m.error, isNull);
      expect(m.amountFixed, 5000000);
      expect(line.substring(m.labelStart, m.labelEnd - 1), 'Vacation fund');
    });

    test('a value slot works in the trailing region', () {
      const line = r'$+ Fees so far: 50 leaving $ total';
      final m = p(line)!;
      expect(m.valueSlot, line.indexOf(r'$ total'));
      // ...and in the label region, document order winning.
      const both = r'$= My $ worth: 500 then $ again';
      expect(p(both)!.valueSlot, both.indexOf(r'$ worth'));
    });

    test('label-first error rows still surface', () {
      expect(
        p(r'$= Net worth: 999999999999 lei so far')!.error,
        MoneyLineError.amountTooLarge,
      );
      expect(p(r'$= Label:')!.error, MoneyLineError.labelFirstMissingAmount);
    });
  });

  group('list-prefixed money rows', () {
    test('bullets compose with every op', () {
      final m = p(r'- $= 500')!;
      expect(m.listMarkerStart, 0);
      expect(m.listMarkerEnd, 1);
      expect(m.markerStart, 2);
      expect(m.kind, MoneyLineKind.set);
      expect(m.amountFixed, 5000000);
      expect(p(r'* $* 1.19')!.kind, MoneyLineKind.multiply);
      expect(p(r'+ $+ 5 coffee')!.kind, MoneyLineKind.add);
      expect(p(r'• $$')!.kind, MoneyLineKind.total);
    });

    test('ordered markers compose, delimiter included', () {
      final m = p(r'1. $+ 50 coffee')!;
      expect(m.listMarkerStart, 0);
      expect(m.listMarkerEnd, 2);
      expect(p(r'12) $$ running: $')!.kind, MoneyLineKind.total);
    });

    test('nesting indents survive', () {
      final m = p(r'  - $- 5 snack')!;
      expect(m.listMarkerStart, 2);
      expect(m.markerStart, 4);
    });

    test('probe agrees with parse on every shape', () {
      const yes = [r'- $= 5', r'* $$', r'1. $+ 5', r'12) $?', r'  • $~ 2'];
      for (final line in yes) {
        expect(MarkdownMoneySyntax.leadsWithMoney(line), isTrue, reason: line);
        expect(p(line), isNotNull, reason: line);
      }
      const no = [r'- coffee', r'1. things', r'-$= 5', r'- [ ] $= 5'];
      for (final line in no) {
        expect(
          MarkdownMoneySyntax.leadsWithMoney(line) && p(line) != null,
          isFalse,
          reason: line,
        );
      }
    });

    test('near-money list prose falls back to a plain list item', () {
      // The probe fires but the parse rejects, so the list branch
      // renders it — identical to the unprefixed `$100 coffee` rule.
      expect(MarkdownMoneySyntax.leadsWithMoney(r'- $100 coffee'), isTrue);
      expect(p(r'- $100 coffee'), isNull);
      // Near-heading list prose too: probe false, plain list item.
      expect(MarkdownMoneySyntax.leadsWithMoney(r'- ## groceries'), isFalse);
      expect(p(r'- ## groceries'), isNull);
      expect(p(r'- #tag stuff'), isNull);
    });

    test('bullet + header + colour compose for EVERY marker', () {
      // The full chrome stack on one line, per marker kind: list
      // marker, heading prefix, accent token — plus an amount where the
      // op takes one — must all resolve on a single row.
      const rows = {
        r'- ## $= teal: 500': MoneyLineKind.set,
        r'- ## $+ teal: 50 groceries': MoneyLineKind.add,
        r'- ## $- teal: 8 coffee': MoneyLineKind.subtract,
        r'- ## $* teal: 1.19': MoneyLineKind.multiply,
        r'- ## $/ teal: 2': MoneyLineKind.divide,
        r'- ## $$ teal: Total: $': MoneyLineKind.total,
        r'- ## $? teal: change': MoneyLineKind.delta,
        r'- ## $! teal: 500 budget': MoneyLineKind.target,
        r'- ## $^ 2 teal: last two': MoneyLineKind.diff,
        r'- ## $~ 2 teal: since then': MoneyLineKind.span,
      };
      rows.forEach((line, kind) {
        expect(MarkdownMoneySyntax.leadsWithMoney(line), isTrue, reason: line);
        final m = p(line)!;
        expect(m.kind, kind, reason: line);
        expect(m.error, isNull, reason: line);
        expect(m.listMarkerStart, 0, reason: line);
        expect(m.headerStart, 2, reason: line);
        expect(m.headerLevel, 2, reason: line);
        expect(line.substring(m.accentStart, m.accentEnd), 'teal',
            reason: line);
      });
      // Ordered + nested + no-space hash variants of the same stack.
      final o = p(r'1. ###$$ blue: Sum: $ so far')!;
      expect(o.listMarkerEnd, 2);
      expect(o.headerLevel, 3);
      final nested = p(r'  - # $? red:')!;
      expect(nested.listMarkerStart, 2);
      expect(nested.headerLevel, 1);
    });

    test('composed rows fold identically to their bare spellings', () {
      final bare = fold([r'$= 100', r'$+ 50', r'$?']);
      final composed = fold([
        r'- ## $= teal: 100',
        r'  1. # $+ blue: 50',
        r'- ### $? red:',
      ]);
      for (var i = 0; i < bare.entries.length; i++) {
        expect(
          composed.entries[i].valueAfter,
          bare.entries[i].valueAfter,
          reason: 'line $i',
        );
      }
      expect(composed.entryLines, bare.entryLines);
      expect(composed.anchorLines, bare.anchorLines);
    });

    test('bulleted rows count in the fold like any other', () {
      final c = fold([r'- $= 100', r'  - $+ 50 snack', r'1. $?']);
      expect(valueAt(c, 2), 5000);
      expect(c.entryLines, [0, 1]);
      expect(c.anchorLines, [0]);
    });

    test('bulleted error rows keep their prefix offsets', () {
      final m = p(r'- $= 999999999999')!;
      expect(m.error, MoneyLineError.amountTooLarge);
      expect(m.listMarkerStart, 0);
    });

    test('line-led protection covers list-prefixed rows', () {
      expect(MarkdownLineShape.isLineLedConstruct(r'- $+ 12.50 rent'), isTrue);
      expect(MarkdownLineShape.isLineLedConstruct(r'1. $$'), isTrue);
      expect(
        MarkdownLineShape.isLineLedConstruct(r'- plain list prose'),
        isFalse,
      );
    });
  });

  group('emphasis wrapper', () {
    test("the reported note's exact lines parse", () {
      final first = p(r'* $= teal: End of day Balance: 5900')!;
      expect(first.error, isNull);
      expect(first.listMarkerStart, 0);
      expect(first.amountFixed, 59000000);
      expect(first.emphasisLen, 0);

      const line = r'* *$~ 2 Change from prev. day: $ *';
      final m = p(line)!;
      expect(m.kind, MoneyLineKind.span);
      expect(m.listMarkerStart, 0);
      expect(m.emphasisStart, 2);
      expect(m.emphasisLen, 1);
      expect(m.emphasisItalic, isTrue);
      expect(m.emphasisBold, isFalse);
      expect(m.emphasisCloseStart, line.length - 1);
      expect(m.windowCount, 2);
      expect(m.valueSlot, line.indexOf(r'$ *'));
      expect(line.substring(m.labelStart, m.valueSlot).trim(),
          'Change from prev. day:');
    });

    test('marker runs map to italic / bold / both, `_` family too', () {
      expect(p(r'*$= 5*')!.emphasisItalic, isTrue);
      expect(p(r'*$= 5*')!.emphasisBold, isFalse);
      final bold = p(r'**$$ Total: $**')!;
      expect(bold.emphasisBold, isTrue);
      expect(bold.emphasisItalic, isFalse);
      final both = p(r'***$? change***')!;
      expect(both.emphasisItalic, isTrue);
      expect(both.emphasisBold, isTrue);
      expect(p(r'_$~ 2 x_')!.emphasisItalic, isTrue);
      expect(p(r'__$+ 5 y__')!.emphasisBold, isTrue);
    });

    test('rejections: unclosed, mismatched, oversized, tail junk', () {
      expect(p(r'*$= 5'), isNull);
      expect(p(r'*$= 5**'), isNull);
      expect(p(r'**$= 5*'), isNull);
      expect(p(r'_$= 5*'), isNull);
      expect(p(r'****$$ x****'), isNull);
      expect(p(r'*$= 5* x'), isNull);
      expect(p(r'*$*'), isNull);
      // Not tight to the `$`: a bullet, never emphasis.
      expect(p(r'* $= 5')!.listMarkerStart, 0);
    });

    test('content offsets all respect the reduced end', () {
      const line = r'*$= Net worth: 500 lei as of today*';
      final m = p(line)!;
      expect(m.error, isNull);
      expect(line.substring(m.amountStart, m.amountEnd), '500');
      expect(
        MarkdownMoneySyntax.inlineCurrencyEnd(line, m, 'lei'),
        line.indexOf('lei') + 3,
      );
      expect(
        MarkdownMoneySyntax.displayLabel(line, m, 'lei'),
        'Net worth as of today',
      );
      final layout = MoneyRowLayout.of(line, m, 'lei');
      expect(layout.contentEnd, m.emphasisCloseStart);
      // Currency word tight against the closer still resolves.
      const tight = r'*$= Worth: 500 lei*';
      final t = p(tight)!;
      expect(
        MarkdownMoneySyntax.inlineCurrencyEnd(tight, t, 'lei'),
        tight.length - 1,
      );
    });

    test('full chrome stack: bullet + heading + emphasis + accent', () {
      const line = r'- ## **$= teal: 500 lei**';
      final m = p(line)!;
      expect(m.error, isNull);
      expect(m.listMarkerStart, 0);
      expect(m.headerLevel, 2);
      expect(m.emphasisBold, isTrue);
      expect(line.substring(m.accentStart, m.accentEnd), 'teal');
      expect(m.amountFixed, 5000000);
    });

    test('wrapped rows fold identically to bare ones', () {
      final bare = fold([r'$= 100', r'$+ 50', r'$?']);
      final wrapped = fold([
        r'*$= 100*',
        r'* **$+ 50**',
        r'- _$?_',
      ]);
      for (var i = 0; i < bare.entries.length; i++) {
        expect(wrapped.entries[i].valueAfter, bare.entries[i].valueAfter);
      }
      expect(wrapped.entryLines, bare.entryLines);
      expect(wrapped.anchorLines, bare.anchorLines);
    });

    test('probe accepts every wrapped shape (parse ⊆ probe holds)', () {
      const lines = [
        r'*$= 5*', r'**$$**', r'_$~ 2 x_', r'* *$~ 2 y: $ *',
        r'- ## **$= teal: 500**', r'## *$$ Total: $*', r'1. _$?_',
        r'*$= 5', r'****$$****', // over-accepts are fine, silent misses are not
      ];
      for (final line in lines) {
        if (MarkdownMoneySyntax.parse(line) != null) {
          expect(MarkdownMoneySyntax.leadsWithMoney(line), isTrue,
              reason: line);
        }
      }
    });

    test('emphasised heading text without money stays plain', () {
      expect(p(r'## *text*'), isNull);
      expect(p(r'- *italic thing*'), isNull);
      expect(p(r'- _foo_'), isNull);
    });
  });

  group('reported document integrity', () {
    // Alex's exact note (2026-07-25): money rows, coloured headings,
    // tags, and an INDENTED heading after money/list lines. Pins that
    // every line classifies the way the note reads — most importantly
    // that headings and tags are never claimed by the money probe.
    final doc = [
      r'# $= teal: Initial Balance:70897.00 lei', // 0 money H1 set
      r'', // 1
      r'## {blue:Monday 20 June 2026}', // 2 heading
      r'', // 3
      r'* *$= teal: End of day Balance:5900 lei*', // 4 bullet+emph set
      r'* *$~ 2 Change from prev. day: $*', // 5 bullet+emph span
      r'#usus', // 6 tag
      r' ', // 7
      r' ## ahsususi', // 8 INDENTED heading
      r'', // 9
      r'* *$= teal: End of day Balance:5900 lei*', // 10
      r'* *$~ 3 Change from prev. day: $*', // 11
    ];

    test('non-money lines are never probed as money', () {
      for (final i in [1, 2, 3, 6, 7, 8, 9]) {
        expect(
          MarkdownMoneySyntax.leadsWithMoney(doc[i]),
          isFalse,
          reason: 'line $i: "${doc[i]}"',
        );
        expect(p(doc[i]), isNull, reason: 'line $i');
      }
    });

    test('every money line parses with its full chrome', () {
      final l0 = p(doc[0])!;
      expect(l0.error, isNull);
      expect(l0.headerLevel, 1);
      expect(l0.amountFixed, 708970000);
      expect(
        MarkdownMoneySyntax.inlineCurrencyEnd(doc[0], l0, 'lei'),
        doc[0].length,
      );

      final l4 = p(doc[4])!;
      expect(l4.error, isNull);
      expect(l4.kind, MoneyLineKind.set);
      expect(l4.listMarkerStart, 0);
      expect(l4.emphasisItalic, isTrue);
      expect(l4.amountFixed, 59000000);
      expect(MarkdownMoneySyntax.displayLabel(doc[4], l4, 'lei'),
          'End of day Balance');

      final l5 = p(doc[5])!;
      expect(l5.kind, MoneyLineKind.span);
      expect(l5.windowCount, 2);
      // The slot sits tight against the emphasis closer (`$*`).
      expect(l5.valueSlot, doc[5].indexOf(r'$*'));
      expect(p(doc[11])!.windowCount, 3);
    });

    test('the whole document folds to the numbers the note shows', () {
      final c = fold(doc);
      expect(c.entryLines, [0, 4, 10]);
      expect(c.anchorLines, [0, 4, 10]);
      // Day change: 5900 − 70897 (2 checkpoints back from line 4's).
      expect(valueAt(c, 5), 590000 - 7089700);
      // `$~ 3` reaches past the oldest checkpoint and floors at the
      // FIRST `$=`, still a change between checkpoints.
      expect(valueAt(c, 11), 590000 - 7089700);
    });
  });

  group('adversarial edges', () {
    test('parse NEVER accepts a line the probe rejects', () {
      // Every fold probes before parsing — a line that parses but fails
      // the probe would silently vanish from the ledger. Battery over
      // every shape in this file plus hostile near-misses.
      const battery = [
        r'$= 500', r'$+ 50 lei coffee', r'$$', r'$~ 2 teal: x',
        r'## $$', r'##$$ x', r'###### $~ 2 teal: Change: $ dollars',
        r'- $= 500', r'* $* 1.19', r'+ $+ 5', r'• $$', r'  - $- 5',
        r'1. $+ 50', r'12) $$', r'- ## $= teal: 500', r'1. ###$$ blue: $',
        r'  - # $? red:', r'- ##$$ x', r'- $100 coffee', r'1. $5 x',
        r'- ####### $$', r'#######$$', r'-$= 5', r'1.$= 5', r'- [ ] $= 5',
        r'$= Net worth: 5000 as of today', r'# $= teal: Initia Balance(lei):70897 lei',
        r'2024 was great', r'- plain', r'$5 coffee', r'$', r'- ', r'1. ',
      ];
      for (final line in battery) {
        if (MarkdownMoneySyntax.parse(line) != null) {
          expect(
            MarkdownMoneySyntax.leadsWithMoney(line),
            isTrue,
            reason: 'parse accepted but probe rejected: $line',
          );
        }
      }
    });

    test('no-space hashes compose after a bullet', () {
      final m = p(r'- ##$$ x')!;
      expect(m.listMarkerStart, 0);
      expect(m.headerLevel, 2);
      expect(m.kind, MoneyLineKind.total);
    });

    test('near-money ordered prose stays a plain list item', () {
      expect(MarkdownMoneySyntax.leadsWithMoney(r'1. $5 coffee'), isTrue);
      expect(p(r'1. $5 coffee'), isNull);
      expect(p(r'- ####### $$'), isNull);
    });

    test('error rows keep every prefix offset in the full stack', () {
      final m = p(r'- ## $= teal: 999999999999')!;
      expect(m.error, MoneyLineError.amountTooLarge);
      expect(m.listMarkerStart, 0);
      expect(m.headerStart, 2);
      expect(m.headerLevel, 2);
    });

    test('full-stack rows are line-led for the paste policies', () {
      expect(MarkdownLineShape.isLineLedConstruct(r'- ## $$ x'), isTrue);
      expect(MarkdownLineShape.isLineLedConstruct(r'1. ###$= teal: 5'), isTrue);
      expect(MarkdownLineShape.isLineLedConstruct(r'- ## groceries'), isFalse);
    });
  });

  group('shared render helpers', () {
    test('glyph covers every kind, non-empty and distinct where painted', () {
      final seen = <String>{};
      for (final kind in MoneyLineKind.values) {
        final g = MarkdownMoneySyntax.glyph(kind);
        expect(g, isNotEmpty, reason: '$kind');
        seen.add(g);
      }
      // One deliberate collision: `$! N` declarations and bare `$!`
      // status rows are one family and share the target glyph `◎`.
      expect(seen.length, MoneyLineKind.values.length - 1);
      expect(
        MarkdownMoneySyntax.glyph(MoneyLineKind.target),
        MarkdownMoneySyntax.glyph(MoneyLineKind.remaining),
      );
    });

    test('isSignedKind: every sign-coloured value shows its sign', () {
      // The direction rows and the budget status print `+`/`-`/`±`...
      for (final kind in [
        MoneyLineKind.delta,
        MoneyLineKind.diff,
        MoneyLineKind.span,
        MoneyLineKind.remaining,
      ]) {
        expect(MarkdownMoneySyntax.isSignedKind(kind), isTrue, reason: '$kind');
      }
      // ...while balances (and every operand-is-the-value row) do not.
      for (final kind in [
        MoneyLineKind.total,
        MoneyLineKind.set,
        MoneyLineKind.target,
        MoneyLineKind.add,
        MoneyLineKind.subtract,
        MoneyLineKind.multiply,
        MoneyLineKind.divide,
      ]) {
        expect(MarkdownMoneySyntax.isSignedKind(kind), isFalse, reason: '$kind');
      }
      expect(MarkdownMoneySyntax.formatCentsSigned(5000), '+50.00');
      expect(MarkdownMoneySyntax.formatCentsSigned(-3000), '-30.00');
      expect(MarkdownMoneySyntax.formatCentsSigned(0), '±0.00');
    });

    test('needsBalance: display rows and slots only', () {
      expect(MarkdownMoneySyntax.needsBalance(p(r'$$')!), isTrue);
      expect(MarkdownMoneySyntax.needsBalance(p(r'$~ 2 x')!), isTrue);
      expect(MarkdownMoneySyntax.needsBalance(p(r'$+ 5 coffee')!), isFalse);
      expect(MarkdownMoneySyntax.needsBalance(p(r'$+ 5 now $')!), isTrue);
      expect(
        MarkdownMoneySyntax.needsBalance(p(r'$= Worth: 500 then $')!),
        isTrue,
      );
    });

    test('displayLabel composes what the preview renders', () {
      String label(String line, [String symbol = 'lei']) =>
          MarkdownMoneySyntax.displayLabel(line, p(line)!, symbol);
      expect(label(r'$+ 50 lei coffee'), 'coffee');
      expect(label(r'$= Net worth: 500 lei as of today'), 'Net worth as of today');
      expect(label(r'$= Net worth: 500'), 'Net worth');
      expect(label(r'$= 500 lei'), '');
      expect(label(r'$= 500 EUR'), 'EUR');
      expect(label(r'$! Vacation: 500 by December'), 'Vacation by December');
    });

    test('MoneyRowLayout mirrors the hand-derived shape', () {
      const line = r'$= Net worth: 500 lei as of $ today';
      final m = p(line)!;
      final l = MoneyRowLayout.of(line, m, 'lei');
      expect(l.isDisplay, isFalse);
      expect(l.labelFirst, isTrue);
      expect(l.labelTo, m.labelEnd - 1);
      expect(l.currencyEnd, line.indexOf('lei') + 3);
      // Trailing text starts past the currency word's spaces? No — at
      // the currency end itself; the renderer's region emit keeps the
      // separating space visible.
      expect(l.trailingFrom, l.currencyEnd);
      expect(l.slot, line.indexOf(r'$ today'));
      // Currency-voided slot ride-along.
      const dollar = r'$= Net worth: 500 $';
      final dm = p(dollar)!;
      expect(MoneyRowLayout.of(dollar, dm, r'$').slot, -1);
      expect(MoneyRowLayout.of(dollar, dm, 'lei').slot, dollar.length - 1);
      // Display shape flags.
      const disp = r'$~ 2 teal: Change: $ dollars';
      final dl = MoneyRowLayout.of(disp, p(disp)!, '');
      expect(dl.isDisplay, isTrue);
      expect(dl.accentAfterCount, isTrue);
      expect(dl.labelFirst, isFalse);
    });
  });

  group(r'target status (bare $!)', () {
    test('bare and labelled spellings parse as remaining', () {
      for (final line in [r'$!', r'$! ', r'$! how am I doing']) {
        final m = p(line)!;
        expect(m.kind, MoneyLineKind.remaining, reason: line);
        expect(m.error, isNull, reason: line);
        expect(m.amountStart, m.amountEnd, reason: line);
      }
      const labelled = r'$! how am I doing';
      final m = p(labelled)!;
      expect(
        labelled.substring(m.labelStart, m.labelEnd),
        'how am I doing',
      );
    });

    test('a colon tail is label text, not a missing amount', () {
      const line = r'$! Remaining:';
      final m = p(line)!;
      expect(m.kind, MoneyLineKind.remaining);
      expect(m.error, isNull);
      expect(line.substring(m.labelStart, m.labelEnd), 'Remaining:');
    });

    test('a value slot works on a status row', () {
      const line = r'$! Budget left: $ this week';
      final m = p(line)!;
      expect(m.kind, MoneyLineKind.remaining);
      expect(m.valueSlot, line.indexOf(r'$ this'));
    });

    test('the status shape needs a space after the marker', () {
      expect(p(r'$!x'), isNull);
      expect(p(r'$!important note'), isNull);
      // No space + colon tail keeps the old error row.
      expect(
        p(r'$!Remaining:')!.error,
        MoneyLineError.labelFirstMissingAmount,
      );
    });

    test('declarations are untouched, and a leading number is an amount', () {
      expect(p(r'$! 100')!.kind, MoneyLineKind.target);
      expect(p(r'$! Vacation fund: 500 by December')!.kind,
          MoneyLineKind.target);
      // Unlike `$^`/`$~`, `$!` takes no window count — any leading
      // number declares that target.
      final m = p(r'$! 2024 savings')!;
      expect(m.kind, MoneyLineKind.target);
      expect(m.amountFixed ~/ 100, 202400);
    });

    test('an accent token composes with both spellings', () {
      final decl = p(r'$! blue: 250')!;
      expect(decl.kind, MoneyLineKind.target);
      expect(decl.amountFixed, 2500000);
      const status = r'$! blue: status';
      final m = p(status)!;
      expect(m.kind, MoneyLineKind.remaining);
      expect(status.substring(m.accentStart, m.accentEnd), 'blue');
      expect(status.substring(m.labelStart, m.labelEnd), 'status');
    });

    test('status rows compose with the chrome layers', () {
      for (final line in [
        r'## $!',
        r'- $! status',
        r'  - $! nested',
        r'- ## $! stacked',
        r'*$! Budget left: $ *',
      ]) {
        expect(MarkdownMoneySyntax.leadsWithMoney(line), isTrue, reason: line);
        final m = p(line)!;
        expect(m.kind, MoneyLineKind.remaining, reason: line);
        expect(m.error, isNull, reason: line);
        expect(MarkdownLineShape.isLineLedConstruct(line), isTrue,
            reason: line);
      }
      expect(p(r'## $!')!.headerLevel, 2);
      expect(p(r'- $! status')!.listMarkerStart, 0);
      expect(p(r'*$! Budget left: $ *')!.emphasisItalic, isTrue);
    });

    test('remaining is a display kind and needs the balance', () {
      expect(MarkdownMoneySyntax.isDisplayKind(MoneyLineKind.remaining),
          isTrue);
      expect(MarkdownMoneySyntax.isEntryKind(MoneyLineKind.remaining),
          isFalse);
      expect(MarkdownMoneySyntax.needsBalance(p(r'$!')!), isTrue);
      // A declaration stays amount-led with no pill, like `$=`.
      expect(MarkdownMoneySyntax.isDisplayKind(MoneyLineKind.target),
          isFalse);
      expect(MarkdownMoneySyntax.needsBalance(p(r'$! 100')!), isFalse);
      final l = MoneyRowLayout.of(r'$!', p(r'$!')!, 'lei');
      expect(l.isDisplay, isTrue);
      expect(l.labelFirst, isFalse);
    });

    test('a declaration displays the target itself', () {
      final c = fold([r'$= 500', r'$- 30 coffee', r'$! 100 lunch budget']);
      expect(valueAt(c, 2), 10000);
    });

    test(r'the $=-updated scenario: remaining measures from the declaration',
        () {
      // The motivating ledger: balances recorded with `$=` set-rows, a
      // target declared under the day heading, and a bare `$!` reading
      // the remaining budget — 100 − (500 − 450) = 50, green.
      final c = fold([
        r'$= 500',
        r'$! 100',
        r'$= 450',
        r'$~ 2',
        r'$!',
      ]);
      expect(valueAt(c, 3), -5000);
      expect(valueAt(c, 4), 5000);
    });

    test('op spending, overspend goes negative', () {
      final c = fold([
        r'$= 500',
        r'$! 100',
        r'$- 30 coffee',
        r'$!',
        r'$- 80 dinner',
        r'$!',
      ]);
      expect(valueAt(c, 3), 7000);
      expect(valueAt(c, 5), -1000);
    });

    test('gains widen the remaining budget', () {
      final c = fold([r'$= 500', r'$! 100', r'$+ 50 refund', r'$!']);
      expect(valueAt(c, 3), 15000);
    });

    test('a later declaration replaces the target and re-anchors', () {
      final c = fold([
        r'$= 500',
        r'$! 100',
        r'$- 50',
        r'$! 200',
        r'$- 20',
        r'$!',
      ]);
      expect(valueAt(c, 5), 18000);
    });

    test('no declaration above yields the sentinel', () {
      final c = fold([r'$= 500', r'$!']);
      expect(MarkdownMoneySyntax.isNoTarget(valueAt(c, 1)), isTrue);
      // The sentinel is not a pinned value — the two warnings must stay
      // distinguishable predicates.
      expect(
        MarkdownMoneySyntax.valuePinned(MarkdownMoneySyntax.noTargetSentinel),
        isFalse,
      );
    });

    test('an error declaration never becomes the active target', () {
      final c = fold([r'$= 500', r'$! 999999999999', r'$!']);
      expect(c.entries[1].match.error, MoneyLineError.amountTooLarge);
      expect(MarkdownMoneySyntax.isNoTarget(valueAt(c, 2)), isTrue);
      expect(c.targetLines, isEmpty);
    });

    test('targetWindowEntries lists declaration through tapped row', () {
      final lines = [
        r'$= 500',
        r'$! 100',
        r'$- 30 coffee',
        r'$= 450',
        r'$!',
      ];
      final c = fold(lines);
      final window = MarkdownMoneySyntax.targetWindowEntries(c, 4);
      expect(window.map((e) => e.lineIndex).toList(), [1, 2, 3, 4]);
      // A later declaration moves the baseline.
      final c2 = fold([...lines, r'$! 200', r'$!']);
      final window2 = MarkdownMoneySyntax.targetWindowEntries(c2, 6);
      expect(window2.map((e) => e.lineIndex).toList(), [5, 6]);
      // No declaration: just the tapped row.
      final c3 = fold([r'$= 500', r'$!']);
      final window3 = MarkdownMoneySyntax.targetWindowEntries(c3, 1);
      expect(window3.map((e) => e.lineIndex).toList(), [1]);
    });

    test('displayLabel reads the status label as typed', () {
      expect(
        MarkdownMoneySyntax.displayLabel(r'$! blue: status', p(r'$! blue: status')!, 'lei'),
        'status',
      );
      expect(
        MarkdownMoneySyntax.displayLabel(r'$! Remaining:', p(r'$! Remaining:')!, 'lei'),
        'Remaining:',
      );
    });
  });

  group('legacy shapes unchanged', () {
    test('classic rows', () {
      expect(p(r'$+ 12.50 rent')!.amountFixed, 125000);
      expect(p(r'$= Net worth: 5000')!.amountFixed, 50000000);
    });

    test('errorMessage covers every enum value', () {
      for (final e in MoneyLineError.values) {
        expect(MarkdownMoneySyntax.errorMessage(e), isNotEmpty);
      }
    });
  });
}
