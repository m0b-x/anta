import 'package:flutter_test/flutter_test.dart';
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
      expect(p(r'$= Net worth: 5000 as of today'), isNull);
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
