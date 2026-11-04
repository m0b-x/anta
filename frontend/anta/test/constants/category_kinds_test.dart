import 'package:anta/constants/category_kinds.dart';
import 'package:flutter_test/flutter_test.dart';

// Short names so the catalogue pin below reads as the record's table.
typedef A = LifeArea;
typedef M = ReportMeasure;
typedef V = MarkVerb;
typedef T = TargetPreset;
typedef K = TargetKind;
typedef P = TargetPeriod;

typedef _Row = (
  LifeArea,
  ReportMeasure?,
  ReportMeasure?,
  List<ReportMeasure>,
  MarkVerb?,
  bool,
  bool,
  bool,
  int?,
  List<TargetPreset>,
);

void main() {
  group('CategoryKinds.all', () {
    test('holds one row per kind, in the enum order, Custom last', () {
      expect(CategoryKinds.all, hasLength(21));
      expect(CategoryKinds.all.map((r) => r.kind), CategoryKind.values);
      expect(CategoryKinds.all.last.kind, CategoryKind.custom);
    });

    test('of() returns every kind its own row', () {
      for (final kind in CategoryKind.values) {
        expect(CategoryKinds.of(kind).kind, kind);
      }
    });

    test('inArea partitions the catalogue', () {
      expect(CategoryKinds.areas, LifeArea.values);
      final seen = <CategoryKind>[];
      for (final area in CategoryKinds.areas) {
        final rows = CategoryKinds.inArea(area);
        expect(rows.every((r) => r.area == area), isTrue, reason: '$area');
        seen.addAll(rows.map((r) => r.kind));
      }
      expect(seen, unorderedEquals(CategoryKind.values));
      expect(seen, hasLength(CategoryKind.values.length));
    });

    test('a marking kind pre-fills presence; only Social and Expiry do not '
        'assume absent', () {
      for (final row in CategoryKinds.all.where((r) => r.verb != null)) {
        expect(row.marksNew, isTrue, reason: '${row.kind}');
        final noAssume =
            row.kind == CategoryKind.social || row.kind == CategoryKind.expiry;
        expect(row.assumeAbsentNew, !noAssume, reason: '${row.kind}');
      }
    });

    test('a kind without a verb pre-fills neither switch', () {
      for (final row in CategoryKinds.all.where((r) => r.verb == null)) {
        expect(row.marksNew, isFalse, reason: '${row.kind}');
        expect(row.assumeAbsentNew, isFalse, reason: '${row.kind}');
      }
    });

    test('countsHours is false exactly for the kinds off the Hours tile', () {
      const off = {
        CategoryKind.medication,
        CategoryKind.sleep,
        CategoryKind.episode,
        CategoryKind.deadline,
        CategoryKind.bill,
        CategoryKind.income,
        CategoryKind.anniversary,
        CategoryKind.maintenance,
        CategoryKind.expiry,
        CategoryKind.trip,
        CategoryKind.leave,
      };
      for (final row in CategoryKinds.all) {
        expect(row.countsHours, !off.contains(row.kind), reason: '${row.kind}');
      }
    });

    test('a suggested counts-as is absent or positive', () {
      for (final row in CategoryKinds.all) {
        final minutes = row.suggestedMinutes;
        expect(minutes == null || minutes > 0, isTrue, reason: '${row.kind}');
      }
    });

    test('a gap preset has no period and every other preset has one', () {
      for (final row in CategoryKinds.all) {
        for (final preset in row.targets) {
          expect(
            preset.period == null,
            preset.kind == TargetKind.maxGap,
            reason: '${row.kind} ${preset.kind}',
          );
        }
      }
    });

    test('a budget is offered only on a Money primary or on Custom', () {
      for (final row in CategoryKinds.all) {
        final offersBudget = row.targets.any(
          (p) => p.kind == TargetKind.budget,
        );
        if (!offersBudget) continue;
        expect(
          row.primary == ReportMeasure.money || row.kind == CategoryKind.custom,
          isTrue,
          reason: '${row.kind}',
        );
      }
    });

    test('every row says what the record\'s §6.2 table says', () {
      // area, primary, primaryFallback, secondary, verb, marksNew,
      // assumeAbsentNew, countsHours, suggestedMinutes, targets.
      const expected = <CategoryKind, _Row>{
        CategoryKind.routine: (
          A.health,
          M.attendance,
          null,
          [M.count],
          V.done,
          true,
          true,
          true,
          null,
          [T(K.atLeast, P.week), T(K.maxGap)],
        ),
        CategoryKind.workout: (
          A.health,
          M.attendance,
          null,
          [M.hours],
          V.attended,
          true,
          true,
          true,
          60,
          [T(K.atLeast, P.week), T(K.maxGap)],
        ),
        CategoryKind.medication: (
          A.health,
          M.attendance,
          null,
          [],
          V.taken,
          true,
          true,
          false,
          null,
          [T(K.atLeast, P.week)],
        ),
        CategoryKind.sleep: (
          A.health,
          M.hours,
          null,
          [M.timing],
          null,
          false,
          false,
          false,
          null,
          [T(K.atLeast, P.day)],
        ),
        CategoryKind.episode: (
          A.health,
          M.count,
          null,
          [M.events, M.lastSeen],
          null,
          false,
          false,
          false,
          null,
          [],
        ),
        CategoryKind.appointment: (
          A.health,
          M.events,
          null,
          [M.lastSeen, M.hours],
          V.attended,
          true,
          true,
          true,
          60,
          [T(K.maxGap)],
        ),
        CategoryKind.work: (
          A.work,
          M.hours,
          null,
          [M.count],
          null,
          false,
          false,
          true,
          480,
          [T(K.atMost, P.week)],
        ),
        CategoryKind.meeting: (
          A.work,
          M.hours,
          null,
          [M.count],
          null,
          false,
          false,
          true,
          30,
          [T(K.atMost, P.week)],
        ),
        CategoryKind.task: (
          A.work,
          M.tasks,
          M.count,
          [],
          V.done,
          true,
          true,
          true,
          30,
          [T(K.atLeast, P.week)],
        ),
        CategoryKind.deadline: (
          A.work,
          M.events,
          null,
          [M.leadTime],
          V.done,
          true,
          true,
          false,
          null,
          [],
        ),
        CategoryKind.study: (
          A.work,
          M.hours,
          null,
          [M.attendance],
          V.attended,
          true,
          true,
          true,
          45,
          [T(K.atLeast, P.week)],
        ),
        CategoryKind.bill: (
          A.money,
          M.money,
          M.count,
          [],
          V.paid,
          true,
          true,
          false,
          null,
          [T(K.budget, P.month)],
        ),
        CategoryKind.income: (
          A.money,
          M.money,
          null,
          [],
          V.received,
          true,
          true,
          false,
          null,
          [],
        ),
        CategoryKind.social: (
          A.people,
          M.events,
          null,
          [M.lastSeen, M.hours],
          V.met,
          true,
          false,
          true,
          120,
          [T(K.atLeast, P.month), T(K.maxGap)],
        ),
        CategoryKind.anniversary: (
          A.people,
          M.count,
          null,
          [],
          null,
          false,
          false,
          false,
          null,
          [],
        ),
        CategoryKind.chore: (
          A.home,
          M.count,
          null,
          [M.lastSeen],
          V.done,
          true,
          true,
          true,
          30,
          [T(K.atLeast, P.week), T(K.maxGap)],
        ),
        CategoryKind.maintenance: (
          A.home,
          M.lastSeen,
          null,
          [M.money],
          V.done,
          true,
          true,
          false,
          null,
          [T(K.maxGap)],
        ),
        CategoryKind.expiry: (
          A.home,
          M.daysUntil,
          null,
          [],
          V.renewed,
          true,
          false,
          false,
          null,
          [],
        ),
        CategoryKind.trip: (
          A.leisure,
          M.count,
          null,
          [M.events, M.money],
          null,
          false,
          false,
          false,
          null,
          [T(K.atLeast, P.year)],
        ),
        CategoryKind.leave: (
          A.work,
          M.count,
          null,
          [],
          null,
          false,
          false,
          false,
          null,
          [T(K.atMost, P.year)],
        ),
        CategoryKind.custom: (
          A.other,
          null,
          null,
          [],
          null,
          false,
          false,
          true,
          null,
          [
            T(K.atLeast, P.week),
            T(K.atMost, P.week),
            T(K.maxGap),
            T(K.budget, P.month),
          ],
        ),
      };
      expect(expected.keys, CategoryKind.values);

      for (final MapEntry(key: kind, value: row) in expected.entries) {
        final actual = CategoryKinds.of(kind);
        final (
          area,
          primary,
          primaryFallback,
          secondary,
          verb,
          marksNew,
          assumeAbsentNew,
          countsHours,
          suggestedMinutes,
          targets,
        ) = row;
        expect(actual.area, area, reason: '$kind area');
        expect(actual.primary, primary, reason: '$kind primary');
        expect(actual.primaryFallback, primaryFallback, reason: '$kind');
        expect(actual.secondary, secondary, reason: '$kind secondary');
        expect(actual.verb, verb, reason: '$kind verb');
        expect(actual.marksNew, marksNew, reason: '$kind marksNew');
        expect(actual.assumeAbsentNew, assumeAbsentNew, reason: '$kind');
        expect(actual.countsHours, countsHours, reason: '$kind countsHours');
        expect(actual.suggestedMinutes, suggestedMinutes, reason: '$kind');
        expect(actual.targets, targets, reason: '$kind targets');
      }
    });

    test('a preset equals another of the same shape, const or not', () {
      final kind = TargetKind.atLeast;
      final a = TargetPreset(kind, TargetPeriod.week);
      final b = TargetPreset(kind, TargetPeriod.week);
      expect(identical(a, b), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, const TargetPreset(TargetKind.atLeast, TargetPeriod.week));
      expect(a, isNot(TargetPreset(kind, TargetPeriod.month)));
    });

    test('Custom is today\'s calendar: Auto, no verb, hours counted', () {
      final custom = CategoryKinds.of(CategoryKind.custom);
      expect(custom.primary, isNull);
      expect(custom.verb, isNull);
      expect(custom.marksNew, isFalse);
      expect(custom.assumeAbsentNew, isFalse);
      expect(custom.countsHours, isTrue);
      expect(custom.area, LifeArea.other);
    });
  });

  group('parse', () {
    test('round-trips every value and rejects garbage', () {
      for (final kind in CategoryKind.values) {
        expect(CategoryKind.parse(kind.name), kind);
      }
      for (final area in LifeArea.values) {
        expect(LifeArea.parse(area.name), area);
      }
      for (final verb in MarkVerb.values) {
        expect(MarkVerb.parse(verb.name), verb);
      }
      for (final raw in [null, '', 'Workout', 'gym', ' custom']) {
        expect(CategoryKind.parse(raw), isNull, reason: '$raw');
        expect(LifeArea.parse(raw), isNull, reason: '$raw');
        expect(MarkVerb.parse(raw), isNull, reason: '$raw');
      }
    });
  });
}
