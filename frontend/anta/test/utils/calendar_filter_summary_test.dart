import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_grid_filters.dart';
import 'package:anta/utils/calendar_filter_summary.dart';

/// The one grammar naming an active filter axis has two registers since
/// 2026-09-29: a chip counts a set ("Priority (2)") because it must stay one
/// word wide, while a preset's caption and the suggested name read the set
/// back ("Highest, High") like every set row of the Filters sheet. These pin
/// that the two never drift apart in anything but that.
void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  CalendarCategory category(String id, String name, {bool hidden = false}) =>
      CalendarCategory(
        id: id,
        name: name,
        colorValue: 0xFF000000,
        iconKey: 'event',
        sortOrder: 0,
        isBuiltIn: false,
        isHidden: hidden,
      );

  setUp(() {
    CalendarCategories.updateCache([
      category('gym', 'Gym'),
      category('run', 'Running'),
      category('swim', 'Swimming'),
      category('yoga', 'Yoga'),
    ]);
  });

  tearDown(() => CalendarCategories.updateCache(const []));

  group('priorities', () {
    const two = CalendarGridFilters(priorities: {2, 1});

    test('a chip counts several, a caption names them highest first', () {
      expect(
        CalendarFilterSummary.facetsOf(two, l10n).single.label,
        'Priority (2)',
      );
      expect(
        CalendarFilterSummary.facetsOf(two, l10n, named: true).single.label,
        'Highest, High',
      );
      expect(CalendarFilterSummary.describe(two, l10n), 'Highest, High');
      expect(CalendarFilterSummary.suggestName(two, l10n), 'Highest, High');
    });

    test('one priority names itself in both registers', () {
      const one = CalendarGridFilters(priorities: {3});
      expect(CalendarFilterSummary.facetsOf(one, l10n).single.label, 'Normal');
      expect(CalendarFilterSummary.describe(one, l10n), 'Normal');
    });

    test('past the named limit the rest fold into "+N more"', () {
      const four = CalendarGridFilters(priorities: {1, 2, 3, 4});
      expect(
        CalendarFilterSummary.describe(four, l10n),
        'Highest, High +2 more',
      );
    });
  });

  group('categories', () {
    test('a chip counts the shown categories, a caption names them', () {
      const oneHidden = CalendarGridFilters(hiddenCategoryIds: {'yoga'});
      expect(
        CalendarFilterSummary.facetsOf(oneHidden, l10n).single.label,
        'Categories (3)',
      );
      expect(
        CalendarFilterSummary.describe(oneHidden, l10n),
        'Gym, Running +1 more',
      );
    });

    test('two shown read the same in both registers', () {
      const twoHidden = CalendarGridFilters(hiddenCategoryIds: {'swim', 'yoga'});
      expect(
        CalendarFilterSummary.facetsOf(twoHidden, l10n).single.label,
        'Gym, Running',
      );
      expect(CalendarFilterSummary.describe(twoHidden, l10n), 'Gym, Running');
    });

    test('nothing shown reads "No categories" in both registers', () {
      const allHidden = CalendarGridFilters(
        hiddenCategoryIds: {'gym', 'run', 'swim', 'yoga'},
      );
      expect(
        CalendarFilterSummary.facetsOf(allHidden, l10n).single.label,
        'No categories',
      );
      expect(CalendarFilterSummary.describe(allHidden, l10n), 'No categories');
    });
  });

  test('the caption joins every axis in sheet order', () {
    const mixed = CalendarGridFilters(
      priorities: {1, 2},
      trackedOnly: true,
      showHolidays: false,
    );
    expect(
      CalendarFilterSummary.describe(mixed, l10n),
      'Highest, High · Tracked · Without Holidays',
    );
  });
}
