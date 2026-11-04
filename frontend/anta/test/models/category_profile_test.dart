import 'package:anta/constants/category_kinds.dart';
import 'package:anta/models/category_profile.dart';
import 'package:flutter_test/flutter_test.dart';

CategoryProfile _profile({CategoryKind kind = CategoryKind.custom}) =>
    CategoryProfile(id: 'p1', categoryId: 'c1', kind: kind);

void main() {
  final created = DateTime(2026, 11, 1, 9, 30, 0, 125);
  final updated = DateTime(2026, 11, 3, 18);

  final full = CategoryProfile(
    id: 'p1',
    categoryId: 'c1',
    kind: CategoryKind.workout,
    area: LifeArea.leisure,
    measure: ReportMeasure.hours,
    nominalMinutes: 45,
    markVerb: 'Lifted',
    marksNew: false,
    assumeAbsentNew: false,
    countsHours: false,
    target: const ReportTarget(
      kind: TargetKind.atLeast,
      value: 3,
      period: TargetPeriod.week,
    ),
    createdAt: created,
    updatedAt: updated,
  );

  group('JSON', () {
    test('round-trips every field set', () {
      final json = full.toJson();
      expect(json[CategoryProfileKeys.targetKind], 'atLeast');
      expect(json[CategoryProfileKeys.targetValue], 3);
      expect(json[CategoryProfileKeys.targetPeriod], 'week');
      expect(CategoryProfile.fromJson(json), full);
      expect(CategoryProfile.fromJson(json)!.createdAt!.isUtc, isFalse);
    });

    test('round-trips a profile with nothing set', () {
      final bare = _profile();
      final json = bare.toJson();
      expect(
        json.keys,
        containsAll(<String>[
          CategoryProfileKeys.targetKind,
          CategoryProfileKeys.targetValue,
          CategoryProfileKeys.targetPeriod,
        ]),
      );
      expect(json[CategoryProfileKeys.kind], 'custom');
      final back = CategoryProfile.fromJson(json);
      expect(back, bare);
      expect(back!.hasOverrides, isFalse);
    });

    test('round-trips a mark verb turned off', () {
      final off = _profile(kind: CategoryKind.bill).copyWith(markVerb: '');
      final back = CategoryProfile.fromJson(off.toJson());
      expect(back, off);
      expect(back!.markVerb, '');
    });

    test('round-trips a gap target with no period', () {
      final gap = _profile().copyWith(
        target: const ReportTarget(kind: TargetKind.maxGap, value: 180),
      );
      expect(CategoryProfile.fromJson(gap.toJson()), gap);
    });

    test('an unknown kind decodes as Custom', () {
      final json = full.toJson()..[CategoryProfileKeys.kind] = 'astrology';
      expect(CategoryProfile.fromJson(json)!.kind, CategoryKind.custom);
      json.remove(CategoryProfileKeys.kind);
      expect(CategoryProfile.fromJson(json)!.kind, CategoryKind.custom);
    });

    test('an unknown area, measure or period reads as absent', () {
      final json = full.toJson()
        ..[CategoryProfileKeys.area] = 'space'
        ..[CategoryProfileKeys.measure] = 'vibes';
      final back = CategoryProfile.fromJson(json)!;
      expect(back.area, isNull);
      expect(back.measure, isNull);
      expect(back.target, full.target);

      json[CategoryProfileKeys.targetPeriod] = 'fortnight';
      expect(CategoryProfile.fromJson(json)!.target, isNull);
    });

    test('a target with an unknown kind, no value or no period is dropped', () {
      Map<String, dynamic> withTarget(Object? kind, Object? value, Object? p) =>
          full.toJson()
            ..[CategoryProfileKeys.targetKind] = kind
            ..[CategoryProfileKeys.targetValue] = value
            ..[CategoryProfileKeys.targetPeriod] = p;

      expect(
        CategoryProfile.fromJson(withTarget('atLeastish', 3, 'week'))!.target,
        isNull,
      );
      expect(
        CategoryProfile.fromJson(withTarget('atLeast', null, 'week'))!.target,
        isNull,
      );
      expect(
        CategoryProfile.fromJson(withTarget('atLeast', '3', 'week'))!.target,
        isNull,
      );
      expect(
        CategoryProfile.fromJson(withTarget('budget', 300, null))!.target,
        isNull,
      );
    });

    test('a target value below one is read as one; a gap ignores a period', () {
      final low = full.toJson()..[CategoryProfileKeys.targetValue] = -4;
      expect(CategoryProfile.fromJson(low)!.target!.value, 1);

      final gap = full.toJson()
        ..[CategoryProfileKeys.targetKind] = 'maxGap'
        ..[CategoryProfileKeys.targetValue] = 0
        ..[CategoryProfileKeys.targetPeriod] = 'month';
      expect(
        CategoryProfile.fromJson(gap)!.target,
        const ReportTarget(kind: TargetKind.maxGap, value: 1),
      );
    });

    test('a counts-as of zero or less is none', () {
      for (final raw in [0, -30, '45', 4.5]) {
        final json = full.toJson()..[CategoryProfileKeys.nominalMinutes] = raw;
        expect(
          CategoryProfile.fromJson(json)!.nominalMinutes,
          isNull,
          reason: '$raw',
        );
      }
    });

    test('mistyped switches and dates fall back to absent', () {
      final json = full.toJson()
        ..[CategoryProfileKeys.marksNew] = 'yes'
        ..[CategoryProfileKeys.countsHours] = 1
        ..[CategoryProfileKeys.markVerb] = 7
        ..[CategoryProfileKeys.createdAt] = 'yesterday';
      final back = CategoryProfile.fromJson(json)!;
      expect(back.marksNew, isNull);
      expect(back.countsHours, isNull);
      expect(back.markVerb, isNull);
      expect(back.createdAt, isNull);
      expect(back.assumeAbsentNew, isFalse);
    });

    test('no identity, no profile', () {
      for (final key in [
        CategoryProfileKeys.id,
        CategoryProfileKeys.categoryId,
      ]) {
        expect(
          CategoryProfile.fromJson(full.toJson()..remove(key)),
          isNull,
          reason: key,
        );
        expect(
          CategoryProfile.fromJson(full.toJson()..[key] = ''),
          isNull,
          reason: key,
        );
        expect(
          CategoryProfile.fromJson(full.toJson()..[key] = 3),
          isNull,
          reason: key,
        );
      }
    });
  });

  group('copyWith', () {
    test('replaces what it is given and keeps the rest', () {
      final changed = full.copyWith(
        kind: CategoryKind.study,
        nominalMinutes: 50,
      );
      expect(changed.kind, CategoryKind.study);
      expect(changed.nominalMinutes, 50);
      expect(
        changed.copyWith(kind: CategoryKind.workout, nominalMinutes: 45),
        full,
      );
      expect(full.copyWith(), full);
    });

    test('each clear flag empties its override alone', () {
      final cleared = <String, CategoryProfile>{
        'area': full.copyWith(clearArea: true),
        'measure': full.copyWith(clearMeasure: true),
        'nominalMinutes': full.copyWith(clearNominalMinutes: true),
        'markVerb': full.copyWith(clearMarkVerb: true),
        'marksNew': full.copyWith(clearMarksNew: true),
        'assumeAbsentNew': full.copyWith(clearAssumeAbsentNew: true),
        'countsHours': full.copyWith(clearCountsHours: true),
        'target': full.copyWith(clearTarget: true),
      };
      Object? read(CategoryProfile p, String field) => switch (field) {
        'area' => p.area,
        'measure' => p.measure,
        'nominalMinutes' => p.nominalMinutes,
        'markVerb' => p.markVerb,
        'marksNew' => p.marksNew,
        'assumeAbsentNew' => p.assumeAbsentNew,
        'countsHours' => p.countsHours,
        'target' => p.target,
        _ => throw ArgumentError(field),
      };
      for (final MapEntry(key: field, value: profile) in cleared.entries) {
        expect(read(profile, field), isNull, reason: field);
        for (final other in cleared.keys.where((k) => k != field)) {
          expect(
            read(profile, other),
            read(full, other),
            reason: '$field/$other',
          );
        }
        expect(profile.kind, full.kind);
        expect(profile.createdAt, full.createdAt);
      }
    });

    test('hasOverrides follows the overrides, never the kind', () {
      expect(_profile(kind: CategoryKind.bill).hasOverrides, isFalse);
      expect(_profile().copyWith(markVerb: '').hasOverrides, isTrue);
      expect(_profile().copyWith(countsHours: true).hasOverrides, isTrue);
      expect(full.hasOverrides, isTrue);
    });
  });

  group('effective', () {
    test('no profile is unprofiled, Custom\'s row with nothing overridden', () {
      final none = CategoryProfile.effectiveOf(null);
      expect(none, same(EffectiveProfile.unprofiled));
      expect(none.isUnprofiled, isTrue);
      expect(_profile().effective, EffectiveProfile.unprofiled);
      expect(_profile().effective.isUnprofiled, isTrue);

      final custom = CategoryKinds.of(CategoryKind.custom);
      expect(none.kind, custom.kind);
      expect(none.area, custom.area);
      expect(none.primary, custom.primary);
      expect(none.primaryFallback, custom.primaryFallback);
      expect(none.secondary, custom.secondary);
      expect(none.verb, custom.verb);
      expect(none.marks, isFalse);
      expect(none.marksNew, custom.marksNew);
      expect(none.assumeAbsentNew, custom.assumeAbsentNew);
      expect(none.countsHours, custom.countsHours);
      expect(none.suggestedMinutes, custom.suggestedMinutes);
      expect(none.targetPresets, custom.targets);
      expect(none.nominalMinutes, isNull);
      expect(none.target, isNull);
    });

    test('every kind with nothing overridden is its own row', () {
      for (final row in CategoryKinds.all) {
        final e = _profile(kind: row.kind).effective;
        expect(e.kind, row.kind);
        expect(e.area, row.area);
        expect(e.primary, row.primary);
        expect(e.primaryFallback, row.primaryFallback);
        expect(e.secondary, row.secondary);
        expect(e.marks, row.verb != null, reason: '${row.kind}');
        expect(e.verb, row.verb);
        expect(e.customVerb, isNull);
        expect(e.marksNew, row.marksNew);
        expect(e.assumeAbsentNew, row.assumeAbsentNew);
        expect(e.countsHours, row.countsHours);
        expect(e.nominalMinutes, isNull, reason: '${row.kind}');
        expect(e.suggestedMinutes, row.suggestedMinutes);
        expect(e.target, isNull);
        expect(e.targetPresets, row.targets);
        expect(e.isUnprofiled, row.kind == CategoryKind.custom);
      }
    });

    test('each override wins alone', () {
      final base = _profile(kind: CategoryKind.workout);
      final row = CategoryKinds.of(CategoryKind.workout);
      const target = ReportTarget(kind: TargetKind.maxGap, value: 9);

      final area = base.copyWith(area: LifeArea.people).effective;
      expect(area.area, LifeArea.people);
      expect(area.primary, row.primary);

      final measure = base.copyWith(measure: ReportMeasure.count).effective;
      expect(measure.primary, ReportMeasure.count);
      expect(measure.area, row.area);

      final nominal = base.copyWith(nominalMinutes: 75).effective;
      expect(nominal.nominalMinutes, 75);
      expect(nominal.suggestedMinutes, row.suggestedMinutes);

      final hours = base.copyWith(countsHours: false).effective;
      expect(hours.countsHours, isFalse);
      expect(hours.marksNew, row.marksNew);

      final marksNew = base.copyWith(marksNew: false).effective;
      expect(marksNew.marksNew, isFalse);
      expect(marksNew.marks, isTrue);
      expect(marksNew.assumeAbsentNew, row.assumeAbsentNew);

      final assume = base.copyWith(assumeAbsentNew: false).effective;
      expect(assume.assumeAbsentNew, isFalse);
      expect(assume.marksNew, row.marksNew);

      final goal = base.copyWith(target: target).effective;
      expect(goal.target, target);
      expect(goal.targetPresets, row.targets);
    });

    test('the fallback measure stays only under the kind\'s own primary', () {
      final task = _profile(kind: CategoryKind.task);
      expect(task.effective.primaryFallback, ReportMeasure.count);
      expect(
        task.copyWith(measure: ReportMeasure.tasks).effective.primaryFallback,
        ReportMeasure.count,
      );
      expect(
        task.copyWith(measure: ReportMeasure.hours).effective.primaryFallback,
        isNull,
      );
    });

    test('an empty verb turns marking off, marksNew with it', () {
      final off = _profile(
        kind: CategoryKind.workout,
      ).copyWith(markVerb: '', marksNew: true).effective;
      expect(off.marks, isFalse);
      expect(off.verb, isNull);
      expect(off.customVerb, isNull);
      expect(off.marksNew, isFalse);
    });

    test('an empty verb turns assume-absent off, the kind\'s or own', () {
      final workout = _profile(kind: CategoryKind.workout);
      expect(CategoryKinds.of(CategoryKind.workout).assumeAbsentNew, isTrue);

      final kinds = workout.copyWith(markVerb: '').effective;
      expect(kinds.marksNew, isFalse);
      expect(kinds.assumeAbsentNew, isFalse);

      final own = workout
          .copyWith(markVerb: '', assumeAbsentNew: true)
          .effective;
      expect(own.assumeAbsentNew, isFalse);
    });

    test('an own verb keeps the kind\'s verb beside it', () {
      final own = _profile(
        kind: CategoryKind.chore,
      ).copyWith(markVerb: 'Watered').effective;
      expect(own.marks, isTrue);
      expect(own.verb, MarkVerb.done);
      expect(own.customVerb, 'Watered');
      expect(own.marksNew, isTrue);
    });

    test('an own verb on a kind without one turns marking on', () {
      final sleep = _profile(kind: CategoryKind.sleep);
      expect(sleep.effective.marks, isFalse);
      final own = sleep.copyWith(markVerb: 'Slept').effective;
      expect(own.marks, isTrue);
      expect(own.verb, isNull);
      expect(own.customVerb, 'Slept');
      expect(own.marksNew, isFalse);
      expect(
        sleep.copyWith(markVerb: 'Slept', marksNew: true).effective.marksNew,
        isTrue,
      );
    });
  });
}
