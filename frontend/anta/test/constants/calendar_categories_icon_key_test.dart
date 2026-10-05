import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/constants/calendar_icons.dart';
import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/recurrence_rule.dart';

/// `iconKeyFor` is `iconFor` as a key: what an alert payload carries so that
/// a surface with no category facade — the background isolate, another
/// database's alarm — draws the glyph the calendar draws. The two are one
/// rule, and these cases are every branch of it.
void main() {
  CalendarCategory category(String id, String iconKey) => CalendarCategory(
    id: id,
    name: id,
    colorValue: 0xFF112233,
    iconKey: iconKey,
    sortOrder: 0,
    isBuiltIn: false,
  );

  CalendarEvent event({String categoryId = 'gym', String? iconKey}) =>
      CalendarEvent(
        id: 'e1',
        title: 'Leg day',
        categoryId: categoryId,
        startDate: DateTime.utc(2026, 9, 20),
        rule: const OneTimeRecurrence(),
        iconKey: iconKey,
      );

  setUp(() {
    CalendarCategories.updateCache([
      category('gym', 'fitness_center'),
      category('broken', 'no_such_icon'),
    ]);
  });

  tearDown(() => CalendarCategories.updateCache(const []));

  test("an event's own key wins while it names an icon", () {
    expect(CalendarCategories.iconKeyFor(event(iconKey: 'alarm')), 'alarm');
  });

  test("otherwise it is the category's", () {
    expect(CalendarCategories.iconKeyFor(event()), 'fitness_center');
    // A key that names nothing — an icon retired from the catalog — is no
    // override at all.
    expect(
      CalendarCategories.iconKeyFor(event(iconKey: 'no_such_icon')),
      'fitness_center',
    );
  });

  test('an unknown category resolves through the fallback', () {
    expect(
      CalendarCategories.iconKeyFor(event(categoryId: 'deleted')),
      CalendarCategories.fallback.iconKey,
    );
  });

  test('and nothing at all is null, where the glyph takes its default', () {
    final lost = event(categoryId: 'broken', iconKey: 'no_such_icon');

    expect(CalendarCategories.iconKeyFor(lost), isNull);
    expect(CalendarCategories.iconFor(lost), Icons.event_rounded);
  });

  test('the key always names the glyph iconFor draws', () {
    final events = [
      event(iconKey: 'alarm'),
      event(),
      event(iconKey: 'no_such_icon'),
      event(categoryId: 'deleted'),
    ];

    for (final candidate in events) {
      expect(
        CalendarIcons.forKey(CalendarCategories.iconKeyFor(candidate)),
        CalendarCategories.iconFor(candidate),
        reason: '${candidate.categoryId} / ${candidate.iconKey}',
      );
    }
  });
}
