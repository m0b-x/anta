import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';

/// Pins the two answers the cache gives when the caller has no category of
/// its own: what an unknown id draws as (the user's Other, K4) and what a
/// brand-new event opens on (the first unarchived category, D1).
void main() {
  CalendarCategory category(
    String id, {
    int sortOrder = 0,
    bool isHidden = false,
    int colorValue = 0xFF112233,
    String iconKey = 'event',
  }) {
    return CalendarCategory(
      id: id,
      name: id,
      colorValue: colorValue,
      iconKey: iconKey,
      sortOrder: sortOrder,
      isBuiltIn: false,
      isHidden: isHidden,
    );
  }

  tearDown(() => CalendarCategories.updateCache(const []));

  group('resolve', () {
    test('an unknown id resolves to the stored, recoloured Other', () {
      CalendarCategories.updateCache([
        category('gym', sortOrder: 0),
        category(
          kFallbackCategoryId,
          sortOrder: 1,
          colorValue: 0xFFAB47BC,
          iconKey: 'star',
        ),
      ]);

      final orphan = CalendarCategories.resolve('deleted-elsewhere');

      expect(orphan.id, kFallbackCategoryId);
      expect(orphan.colorValue, 0xFFAB47BC);
      expect(orphan.iconKey, 'star');
      expect(
        orphan.colorValue,
        isNot(CalendarCategories.fallback.colorValue),
        reason: 'an orphan draws as the user\'s Other, never the const grey',
      );
    });

    test('an archived Other still catches an unknown id', () {
      CalendarCategories.updateCache([
        category('gym', sortOrder: 0),
        category(
          kFallbackCategoryId,
          sortOrder: 1,
          isHidden: true,
          colorValue: 0xFFAB47BC,
        ),
      ]);

      expect(CalendarCategories.resolve('nope').colorValue, 0xFFAB47BC);
    });

    test('the const fallback is the last resort when the cache holds no '
        'Other', () {
      CalendarCategories.updateCache([category('gym')]);

      expect(
        CalendarCategories.resolve('nope'),
        same(CalendarCategories.fallback),
      );
    });

    test('an empty cache still resolves', () {
      expect(
        CalendarCategories.resolve('nope'),
        same(CalendarCategories.fallback),
      );
    });
  });

  group('defaultForNewEvent', () {
    test('follows the user\'s order, not the seed\'s', () {
      CalendarCategories.updateCache([
        category('gym', sortOrder: 2),
        category('reading', sortOrder: 0),
        category(kFallbackCategoryId, sortOrder: 1),
      ]);

      expect(CalendarCategories.defaultForNewEvent, 'reading');
    });

    test('skips an archived first category', () {
      CalendarCategories.updateCache([
        category('gym', sortOrder: 0, isHidden: true),
        category('cardio', sortOrder: 1),
        category(kFallbackCategoryId, sortOrder: 2),
      ]);

      expect(CalendarCategories.defaultForNewEvent, 'cardio');
    });

    test('is Other when every category is archived', () {
      CalendarCategories.updateCache([
        category('gym', sortOrder: 0, isHidden: true),
        category(kFallbackCategoryId, sortOrder: 1, isHidden: true),
      ]);

      expect(CalendarCategories.defaultForNewEvent, kFallbackCategoryId);
    });

    test('is Other over an empty cache', () {
      expect(CalendarCategories.defaultForNewEvent, kFallbackCategoryId);
    });
  });
}
