import 'package:flutter_test/flutter_test.dart';

import 'package:anta/models/calendar_category.dart';
import 'package:anta/models/calendar_event.dart';
import 'package:anta/models/share_overview.dart';

/// `ShareOverview.withPartnerShown` is a copy by hand: this suite keeps it
/// from dropping a field. The overview below sets every field off its
/// default, so a field the copy forgot comes back as its default and the
/// round trip no longer equals the original.
void main() {
  const work = CalendarCategory(
    id: 'work',
    name: 'Work',
    colorValue: 0xFF336699,
    iconKey: 'event',
    sortOrder: 0,
    isBuiltIn: false,
    sharedByMe: true,
  );
  const shifts = CalendarCategory(
    id: 'p-shifts',
    name: 'Night shift',
    colorValue: 0xFF3949AB,
    iconKey: 'event',
    sortOrder: 0,
    isBuiltIn: false,
    fromPartner: true,
  );
  const gym = CalendarCategory(
    id: 'gym',
    name: 'Gym',
    colorValue: 0xFF43A047,
    iconKey: 'fitness_center',
    sortOrder: 1,
    isBuiltIn: true,
  );

  CalendarEvent event(String id) => CalendarEvent(
    id: id,
    title: id,
    categoryId: 'work',
    startDate: DateTime(2026, 11, 12),
  );

  final overview = ShareOverview(
    categories: const [work],
    events: [MySharedEvent(event: event('mine'), categoryShared: true)],
    partnerCategories: const [
      PartnerSharedCategory(
        category: shifts,
        joinsMine: false,
        shown: true,
        eventCount: 18,
      ),
      PartnerSharedCategory(
        category: gym,
        joinsMine: true,
        shown: true,
        eventCount: 9,
      ),
    ],
    partnerEvents: [event('theirs')],
    readAt: DateTime(2026, 11, 12, 9),
    readFailed: true,
    sending: true,
    offline: true,
    partnerNewerWire: true,
    refusedCount: 3,
    anyMark: true,
    eventCounts: const {'work': 4},
  );

  test('the overview used here sets every field off its default — a field '
      'added to the class is added here, and the round trip then guards '
      'it', () {
    final defaults = ShareOverview.empty.props;
    expect(overview.props.length, defaults.length);
    for (var i = 0; i < defaults.length; i++) {
      expect(overview.props[i], isNot(defaults[i]), reason: 'prop $i');
    }
  });

  test('hiding one of the partner\'s categories changes that row alone', () {
    final hidden = overview.withPartnerShown('p-shifts', false);

    expect(hidden.partnerCategories.first.shown, isFalse);
    expect(hidden.partnerCategories.first.eventCount, 18);
    expect(hidden.partnerCategories.first.category, shifts);
    expect(hidden.partnerCategories.last, overview.partnerCategories.last);
    expect(hidden, isNot(overview));
  });

  test('showing it again gives back the overview whole — no field is lost '
      'on the way', () {
    final back = overview
        .withPartnerShown('p-shifts', false)
        .withPartnerShown('p-shifts', true);

    expect(back, overview);
    expect(back.props.length, overview.props.length);
  });

  test('a built-in the partner shares is switched by its id too', () {
    final hidden = overview.withPartnerShown('gym', false);

    expect(hidden.partnerCategories.last.shown, isFalse);
    expect(hidden.partnerCategories.last.joinsMine, isTrue);
    expect(hidden.partnerCategories.first, overview.partnerCategories.first);
  });

  test('an id the overview does not list changes nothing', () {
    expect(overview.withPartnerShown('gone', false), overview);
  });

  group('PartnerSharedCategory.copyWith — the copy withPartnerShown makes',
      () {
    const row = PartnerSharedCategory(
      category: shifts,
      joinsMine: true,
      shown: true,
      eventCount: 18,
    );

    test('the row here sets every field, and has as many as copyWith '
        'carries — a field added to the row is added here', () {
      expect(row.props, hasLength(4));
      expect(row.props, everyElement(isNotNull));
    });

    test('with nothing given it is the row whole', () {
      expect(row.copyWith(), row);
    });

    test('shown changes that field alone, and back gives the row whole', () {
      final hidden = row.copyWith(shown: false);

      expect(hidden.shown, isFalse);
      expect(hidden.category, row.category);
      expect(hidden.joinsMine, row.joinsMine);
      expect(hidden.eventCount, row.eventCount);
      expect(hidden.copyWith(shown: true), row);
    });
  });

  group('isStale (D22)', () {
    final readAt = DateTime(2026, 11, 1, 9);
    final read = ShareOverview(readAt: readAt);

    test('six days and 23 hours after the last read is not stale yet', () {
      expect(
        read.isStale(readAt.add(const Duration(days: 6, hours: 23))),
        isFalse,
      );
    });

    test('seven days after it is', () {
      expect(read.isStale(readAt.add(ShareOverview.staleAfter)), isTrue);
      expect(read.isStale(readAt.add(const Duration(days: 30))), isTrue);
    });

    test('an overview never read is never stale', () {
      expect(ShareOverview.empty.isStale(DateTime(2099)), isFalse);
    });
  });
}
