import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/overview_list_options.dart';
import 'package:anta/models/overview_period.dart';
import 'package:anta/services/overview_view_service.dart';

import '../database/support/db_test_support.dart';

/// Runs the real DAO and the real codec against `NativeDatabase.memory()`,
/// the preset service's suite cloned: the list survives the payload round
/// trip, `matching` answers on value and ignores Mark presence, the cap
/// refuses, a delete is a tombstone, and a backup keeps what a newer build
/// wrote.
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

  test('Mark presence is never stored', () async {
    await save('Marking', options: perEvent.copyWith(markPresence: true));

    await service.reload();
    expect(service.views.single.options.markPresence, isFalse);
  });

  group('matching', () {
    test('answers on the list, not the id', () async {
      await save('Q1 gym');

      final sameSpan = OverviewCustomPeriod(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 3, 31),
      );
      expect(service.matching(sameSpan, perEvent, {'gym'})?.name, 'Q1 gym');
    });

    test('ignores Mark presence', () async {
      await save('Q1 gym');

      expect(
        service.matching(q1, perEvent.copyWith(markPresence: true), {'gym'}),
        isNotNull,
      );
    });

    test('each part decides', () async {
      await save('Q1 gym');

      expect(
        service.matching(const OverviewYearPeriod(2026), perEvent, {'gym'}),
        isNull,
      );
      expect(
        service.matching(q1, perEvent.copyWith(missedOnly: false), {'gym'}),
        isNull,
      );
      expect(
        service.matching(
          q1,
          perEvent.copyWith(rows: OverviewRows.everyOccurrence),
          {'gym'},
        ),
        isNull,
      );
      expect(service.matching(q1, perEvent, const {}), isNull);
      expect(service.matching(q1, perEvent, {'gym', 'work'}), isNull);
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
    expect(service.matching(q1, perEvent, {'gym'}), isNull);
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
