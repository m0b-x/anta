import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/category_kinds.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/category_profile.dart';
import 'package:anta/utils/category_profile_labels.dart';

/// The goal read-back is the one sentence the category editor's Goal row
/// and the goal sheet both say, so its numbers are pinned here: grouped as
/// every other amount is, and exact for a stored value the sheet could not
/// have written.
void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final de = lookupAppLocalizations(const Locale('de'));

  ReportTarget atMost(int value) => ReportTarget(
    kind: TargetKind.atMost,
    value: value,
    period: TargetPeriod.week,
  );

  test('hours are grouped like counts and money', () {
    expect(
      categoryGoalReadBack(en, atMost(1200 * 60), ReportMeasure.hours),
      'At most 1,200 h a week',
    );
    expect(
      categoryGoalReadBack(de, atMost(1200 * 60), ReportMeasure.hours),
      'Höchstens 1.200 h pro Woche',
    );
    expect(
      categoryGoalReadBack(en, atMost(1200), ReportMeasure.count),
      'At most 1,200 a week',
    );
  });

  test('a stored part of an hour or of a money unit reads exactly, never '
      'floored', () {
    expect(
      categoryGoalReadBack(en, atMost(450), ReportMeasure.hours),
      'At most 7.5 h a week',
    );
    expect(
      categoryGoalReadBack(en, atMost(30), ReportMeasure.hours),
      'At most 0.5 h a week',
    );
    expect(
      categoryGoalReadBack(de, atMost(450), ReportMeasure.hours),
      'Höchstens 7,5 h pro Woche',
    );
    expect(
      categoryGoalReadBack(
        en,
        const ReportTarget(
          kind: TargetKind.budget,
          value: 123450,
          period: TargetPeriod.month,
        ),
        ReportMeasure.money,
      ),
      'Budget 1,234.50 a month',
    );
    // Whole values keep no decimals.
    expect(
      categoryGoalReadBack(en, atMost(40 * 60), ReportMeasure.hours),
      'At most 40 h a week',
    );
  });

  test('the three measures that never lead a category have their own '
      'names', () {
    expect(reportMeasureName(en, ReportMeasure.cancelled), 'Cancelled');
    expect(reportMeasureName(en, ReportMeasure.leadTime), 'Lead time');
    expect(reportMeasureName(en, ReportMeasure.timing), 'Timing');
  });
}
