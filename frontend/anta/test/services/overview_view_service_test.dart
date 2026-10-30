import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/calendar_appearance.dart';
import 'package:anta/models/overview_list_options.dart';
import 'package:anta/models/overview_period.dart';
import 'package:anta/models/overview_view.dart';
import 'package:anta/services/overview_view_service.dart';

import '../database/support/db_test_support.dart';

/// Runs the real DAO and the real codec against `NativeDatabase.memory()`,
/// the preset service's suite cloned: the list survives the payload round
/// trip, `matching` answers on value, the cap refuses, a delete is a
/// tombstone, and a backup keeps what a newer build wrote.
void main() {
  late AppDatabase db;
  late OverviewViewService service;

  final q1 = OverviewCustomPeriod(
    DateTime.utc(2026, 1, 1),
    DateTime.utc(2026, 3, 31),
  );
  const perEvent = OverviewListOptions(
    order: OverviewOrder.newestFirst,
    rows: OverviewRows.perEvent,
    missedOnly: true,
  );

  Future<String> save(
    String name, {
    OverviewPeriod? period,
    OverviewListOptions options = perEvent,
    Set<String> categoryIds = const {'gym'},
  }) async {
    final view = await service.create(
      name: name,
      period: period ?? q1,
      options: options,
      categoryIds: categoryIds,
    );
    return view!.id;
  }

  /// [OverviewViewService.matching] on a fixed day; none of the periods
  /// below rolls, so the day only has to be one.
  OverviewView? match(
    OverviewPeriod period,
    OverviewListOptions options,
    Set<String> categoryIds,
  ) => service.matching(
    period,
    options,
    categoryIds,
    today: DateTime(2026, 10, 14),
    weekStart: CalendarWeekStart.monday,
  );

  setUp(() async {
    OverviewViewService.reset();
    db = await openTestDatabase();
    service = await OverviewViewService.forTesting(db);
  });

  tearDown(() async {
    OverviewViewService.reset();
    await db.close();
  });

  test('a fresh database has no views', () {
    expect(service.views, isEmpty);
    expect(service.isFull, isFalse);
  });

  test('a saved list round-trips through the payload exactly', () async {
    await save('Q1 gym');

    await service.reload();
    final view = service.views.single;
    expect(view.name, 'Q1 gym');
    expect(view.period, q1);
    expect(view.options, perEvent);
    expect(view.categoryIds, {'gym'});
  });

  test('names are trimmed and views append in save order', () async {
    await save('  First  ');
    await save('Second', period: const OverviewYearPeriod(2025));

    expect(service.views.map((v) => v.name), ['First', 'Second']);
  });

  group('matching', () {
    test('answers on the list, not the id', () async {
      await save('Q1 gym');

      final sameSpan = OverviewCustomPeriod(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 3, 31),
      );
      expect(match(sameSpan, perEvent, {'gym'})?.name, 'Q1 gym');
    });

    test('each part decides', () async {
      await save('Q1 gym');

      expect(match(const OverviewYearPeriod(2026), perEvent, {'gym'}), isNull);
      expect(match(q1, perEvent.copyWith(missedOnly: false), {'gym'}), isNull);
      expect(
        match(q1, perEvent.copyWith(rows: OverviewRows.everyOccurrence), {
          'gym',
        }),
        isNull,
      );
      expect(match(q1, perEvent, const {}), isNull);
      expect(match(q1, perEvent, {'gym', 'work'}), isNull);
    });
  });

  test('update rewrites in place, keeping the position', () async {
    await save('First');
    await save('Second', period: const OverviewYearPeriod(2025));

    await service.update(
      service.views.first.copyWith(
        name: 'Renamed',
        period: const OverviewRollingPeriod(OverviewRollingPreset.last90Days),
      ),
    );

    expect(service.views.map((v) => v.name), ['Renamed', 'Second']);
    expect(
      service.views.first.period,
      const OverviewRollingPeriod(OverviewRollingPreset.last90Days),
    );
  });

  group('a write crossing the year boundary', () {
    /// The blob as stored, past the cache: what the next launch decodes.
    Future<Map<Object?, Object?>> periodBlobOf(String id) async {
      final rows = await db.overviewViewDao.getAll();
      final payload = rows.firstWhere((row) => row.id == id).payload;
      return (jsonDecode(payload) as Map)['period'] as Map<Object?, Object?>;
    }

    test('a rename in the new year keeps "this year" rolling', () async {
      service.clock = () => DateTime(2026, 12, 31);
      final id = await save(
        'This year',
        period: const OverviewYearPeriod(2026),
      );
      expect(await periodBlobOf(id), {'kind': 'thisYear'});

      // Resumed on 2 January with no view written in between: the cache
      // still holds the period decoded on 31 December.
      service.clock = () => DateTime(2027, 1, 2);
      await service.update(service.views.single.copyWith(name: 'Renamed'));

      expect(await periodBlobOf(id), {'kind': 'thisYear'});
      expect(service.views.single.period, const OverviewYearPeriod(2027));
    });

    test('re-pointing the view at a year pins it', () async {
      service.clock = () => DateTime(2026, 12, 31);
      final id = await save(
        'This year',
        period: const OverviewYearPeriod(2026),
      );

      service.clock = () => DateTime(2027, 1, 2);
      await service.update(
        service.views.single.copyWith(period: const OverviewYearPeriod(2026)),
      );

      expect(await periodBlobOf(id), {'kind': 'year', 'year': 2026});
    });
  });

  group('reorder', () {
    List<String> names() => [for (final v in service.views) v.name];

    Future<void> seedThree() async {
      await save('A');
      await save('B', period: const OverviewYearPeriod(2025));
      await save('C', period: const OverviewYearPeriod(2024));
    }

    test('the new order persists and survives a reload', () async {
      await seedThree();
      final ids = {for (final v in service.views) v.name: v.id};

      await service.reorder([ids['C']!, ids['A']!, ids['B']!]);

      expect(names(), ['C', 'A', 'B']);
      await service.reload();
      expect(names(), ['C', 'A', 'B']);
      expect(service.views.map((v) => v.sortOrder), [0, 1, 2]);
    });

    test('racing reorders land in the order they were issued', () async {
      await seedThree();
      final ids = [for (final v in service.views) v.id];
      final first = ids.reversed.toList();
      final second = [ids.last, ...ids.take(ids.length - 1)];

      await Future.wait([service.reorder(first), service.reorder(second)]);

      expect([for (final v in service.views) v.id], second);
    });

    test('a later save still appends after a reorder', () async {
      await seedThree();
      final ids = [for (final v in service.views) v.id];
      await service.reorder(ids.reversed.toList());

      await save('D', period: const OverviewYearPeriod(2023));

      expect(names(), ['C', 'B', 'A', 'D']);
    });
  });

  test('delete leaves a tombstone, not a hole', () async {
    final id = await save('Q1 gym');

    await service.delete(id);

    expect(service.views, isEmpty);
    expect(match(q1, perEvent, {'gym'}), isNull);
    final rows = await db
        .customSelect('SELECT is_deleted, version FROM overview_views')
        .get();
    expect(rows.single.read<bool>('is_deleted'), isTrue);
    expect(rows.single.read<int>('version'), 2);
    // The dead slot still counts, so a later view appends after it.
    expect(await db.overviewViewDao.nextSortOrder(), 1);
  });

  test('create refuses past the limit', () async {
    for (var i = 0; i < OverviewViewService.maxViews; i++) {
      await save('View $i', period: OverviewYearPeriod(2000 + i));
    }

    expect(service.isFull, isTrue);
    expect(
      await service.create(
        name: 'One too many',
        period: q1,
        options: perEvent,
        categoryIds: const {},
      ),
      isNull,
    );
    expect(service.views, hasLength(OverviewViewService.maxViews));
  });

  test('a database switch drops the singleton', () async {
    DatabaseLifecycle.notifyDatabaseSwitching();

    final other = await openTestDatabase();
    addTearDown(other.close);
    final rebound = await OverviewViewService.forTesting(other);
    expect(identical(rebound, service), isFalse);
  });

  // October 14, 2026 is a Wednesday: its week starts on Sunday the 11th or
  // on Monday the 12th.
  group('the week start', () {
    final wednesday = DateTime(2026, 10, 14);

    Future<void> saveThisWeek() async {
      service.clock = () => wednesday;
      await service.create(
        name: 'This week',
        period: OverviewPeriod.thisWeek(
          today: wednesday,
          weekStart: CalendarWeekStart.monday,
        ),
        options: OverviewListOptions.defaults,
        categoryIds: const {},
      );
    }

    Future<OverviewViewService> rebind({
      CalendarWeekStart weekStart = CalendarWeekStart.monday,
      Future<CalendarWeekStart> Function()? weekStartReader,
    }) async {
      OverviewViewService.reset();
      final rebound = await OverviewViewService.forTesting(
        db,
        weekStart: weekStart,
        weekStartReader: weekStartReader,
      );
      rebound.clock = () => wednesday;
      await rebound.reload();
      return rebound;
    }

    test(
      'a view saved on this week decodes onto the week start read',
      () async {
        await saveThisWeek();

        final sundays = await rebind(weekStart: CalendarWeekStart.sunday);
        expect(
          sundays.views.single.period,
          OverviewWeekPeriod(DateTime.utc(2026, 10, 11)),
        );
        expect(sundays.views.single.rollsWithToday, isTrue);

        final mondays = await rebind();
        expect(
          mondays.views.single.period,
          OverviewWeekPeriod(DateTime.utc(2026, 10, 12)),
        );
      },
    );

    test('a week start read that fails loads the views on Monday', () async {
      await saveThisWeek();

      final fallback = await rebind(
        weekStart: CalendarWeekStart.sunday,
        weekStartReader: () async => throw StateError('no settings'),
      );
      expect(fallback.views.single.name, 'This week');
      expect(
        fallback.views.single.period,
        OverviewWeekPeriod(DateTime.utc(2026, 10, 12)),
      );
    });
  });

  group('backup', () {
    test('round-trips views', () async {
      await save('Q1 gym');
      await save('Last year', period: const OverviewYearPeriod(2025));

      final exported = await service.exportData();
      await service.importData(exported);

      expect(service.views.map((v) => v.name), ['Q1 gym', 'Last year']);
      expect(service.views.first.period, q1);
      expect(service.views.first.categoryIds, {'gym'});
    });

    test('import replaces rather than merges', () async {
      await save('Stale');

      await service.importData([
        {
          'id': 'imported',
          'name': 'Imported',
          'payload': '{"period":{"kind":"preset","preset":"allTime"}}',
          'sortOrder': 0,
        },
      ]);

      expect(service.views.map((v) => v.name), ['Imported']);
      expect(
        service.views.single.period,
        const OverviewRollingPeriod(OverviewRollingPreset.allTime),
      );
    });

    test('an unknown key survives a restore', () async {
      await service.importData([
        {
          'id': 'future',
          'name': 'From a newer build',
          'payload': '{"rows":"perEvent","someFutureKey":"yes"}',
        },
      ]);

      final exported = await service.exportData();
      expect(exported.single['payload'], contains('someFutureKey'));
      expect(service.views.single.options.rows, OverviewRows.perEvent);
    });

    test(
      'a malformed row is skipped and an unparseable payload kept',
      () async {
        await service.importData([
          'not a map',
          {'name': 'No id'},
          {'id': 'broken', 'name': 'Broken', 'payload': 'not json'},
        ]);

        expect(service.views.single.name, 'Broken');
        expect(service.views.single.options, OverviewListOptions.defaults);
        expect(service.views.single.period, isA<OverviewYearPeriod>());
      },
    );
  });
}
