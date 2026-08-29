import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/models/calendar_category.dart';

/// Pins the one rule that makes hiding *archiving* rather than deleting:
/// `all` keeps everything, `visible` is a second list, and `visiblePlus` is
/// the single way a selection-holding surface gets a hidden id back.
///
/// Dropping a hidden category from `all` would make `resolve()` fall through
/// to `fallback` and repaint every one of its events grey — the exact opposite
/// of what the user asked for when they hid it. That is what the first two
/// tests exist to catch.
void main() {
  CalendarCategory category(
    String id, {
    int sortOrder = 0,
    bool isHidden = false,
  }) {
    return CalendarCategory(
      id: id,
      name: id,
      colorValue: 0xFF112233,
      iconKey: 'event',
      sortOrder: sortOrder,
      isBuiltIn: false,
      isHidden: isHidden,
    );
  }

  setUp(() {
    CalendarCategories.updateCache([
      category('gym', sortOrder: 0),
      category('retired', sortOrder: 1, isHidden: true),
      category('other', sortOrder: 2),
    ]);
  });

  tearDown(() => CalendarCategories.updateCache(const []));

  test('a hidden category stays in all and leaves visible', () {
    expect(CalendarCategories.all.map((c) => c.id), [
      'gym',
      'retired',
      'other',
    ]);
    expect(CalendarCategories.visible.map((c) => c.id), ['gym', 'other']);
  });

  test('a hidden category still resolves for an event using it', () {
    final resolved = CalendarCategories.resolve('retired');
    expect(resolved.id, 'retired');
    expect(
      resolved.colorValue,
      isNot(CalendarCategories.fallback.colorValue),
      reason:
          'falling through to the grey fallback is what hiding must never do '
          'to an event that already carries the category',
    );
    expect(CalendarCategories.byId('retired'), isNotNull);
  });

  test('both lists keep display order', () {
    CalendarCategories.updateCache([
      category('c', sortOrder: 2),
      category('a', sortOrder: 0),
      category('b', sortOrder: 1, isHidden: true),
    ]);
    expect(CalendarCategories.all.map((c) => c.id), ['a', 'b', 'c']);
    expect(CalendarCategories.visible.map((c) => c.id), ['a', 'c']);
  });

  test('updateCache bumps the revision', () {
    final before = CalendarCategories.revision;
    CalendarCategories.updateCache([category('gym')]);
    expect(CalendarCategories.revision, before + 1);
  });

  group('visiblePlus', () {
    test('adds back a kept hidden id, in display order', () {
      expect(CalendarCategories.visiblePlus({'retired'}).map((c) => c.id), [
        'gym',
        'retired',
        'other',
      ]);
    });

    test('ignores ids that are not hidden, and unknown ids', () {
      expect(CalendarCategories.visiblePlus({'gym'}).map((c) => c.id), [
        'gym',
        'other',
      ]);
      expect(CalendarCategories.visiblePlus({'ghost'}).map((c) => c.id), [
        'gym',
        'other',
      ]);
    });

    test('returns visible itself when nothing hidden is kept', () {
      // Identity, not equality: the common case must allocate nothing, so a
      // widget memo keyed on the list does not see a new object per build.
      expect(
        identical(
          CalendarCategories.visiblePlus(const {}),
          CalendarCategories.visible,
        ),
        isTrue,
      );
      expect(
        identical(
          CalendarCategories.visiblePlus(const {'gym'}),
          CalendarCategories.visible,
        ),
        isTrue,
      );
    });

    test('short-circuits when nothing is hidden at all', () {
      CalendarCategories.updateCache([category('gym'), category('other')]);
      expect(
        identical(
          CalendarCategories.visiblePlus(const {'anything'}),
          CalendarCategories.visible,
        ),
        isTrue,
      );
    });

    test('an empty cache yields an empty list rather than throwing', () {
      CalendarCategories.updateCache(const []);
      expect(CalendarCategories.visible, isEmpty);
      expect(CalendarCategories.visiblePlus(const {'gym'}), isEmpty);
    });
  });
}
