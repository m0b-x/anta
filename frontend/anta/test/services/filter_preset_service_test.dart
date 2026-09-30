import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_grid_filters.dart';
import 'package:anta/models/upcoming_agenda_filters.dart';
import 'package:anta/services/filter_preset_service.dart';

import '../database/support/db_test_support.dart';

/// Runs the real DAO and the real codec against `NativeDatabase.memory()`.
///
/// The assertions that earn their place are the ones where a preset differs
/// from a plain row: that the filter survives the blob round trip exactly (it
/// is the whole point of the feature), that `matching` answers on **value**
/// rather than identity, and that a backup restores a preset a newer build
/// wrote without quietly dropping the axes this build does not know about.
void main() {
  late AppDatabase db;
  late FilterPresetService service;

  const tracked = CalendarGridFilters(
    trackedOnly: true,
    priorities: {1, 2},
    eventType: AgendaEventType.recurring,
    hiddenCategoryIds: {'gym'},
    showFasting: false,
    panelShowsAll: true,
  );

  setUp(() async {
    FilterPresetService.reset();
    db = await openTestDatabase();
    service = await FilterPresetService.forTesting(db);
  });

  tearDown(() async {
    FilterPresetService.reset();
    await db.close();
  });

  test('a fresh database has no presets', () {
    expect(service.presets, isEmpty);
    expect(service.isFull, isFalse);
  });

  test('a saved filter round-trips through the blob exactly', () async {
    final saved = await service.create(name: 'Training', filters: tracked);

    expect(saved, isNotNull);
    expect(saved!.name, 'Training');
    expect(saved.filters, tracked);

    // And again from storage, not from the value just handed back.
    await service.reload();
    expect(service.presets.single.filters, tracked);
  });

  test('names are trimmed on the way in', () async {
    await service.create(name: '  Padded  ', filters: tracked);

    expect(service.presets.single.name, 'Padded');
  });

  test('presets append in save order', () async {
    await service.create(name: 'First', filters: tracked);
    await service.create(
      name: 'Second',
      filters: const CalendarGridFilters(missedOnly: true),
    );

    expect(service.presets.map((p) => p.name), ['First', 'Second']);
  });

  group('matching', () {
    test('answers on the filters, not the id', () async {
      await service.create(name: 'Training', filters: tracked);

      // A different instance holding the same axes is the same filter.
      final equivalent = CalendarGridFilters.decode(tracked.encode());
      expect(identical(equivalent, tracked), isFalse);
      expect(service.matching(equivalent)?.name, 'Training');
    });

    test('a filter nobody saved matches nothing', () async {
      await service.create(name: 'Training', filters: tracked);

      expect(
        service.matching(const CalendarGridFilters(hideEnded: true)),
        isNull,
      );
      expect(service.matching(CalendarGridFilters.none), isNull);
    });

    /// The panel opt-out is part of what a preset saves, so two otherwise
    /// identical sets that disagree about it are different presets.
    test('the panel opt-out is part of the identity', () async {
      await service.create(name: 'Training', filters: tracked);

      expect(
        service.matching(tracked.copyWith(panelShowsAll: false)),
        isNull,
      );
    });
  });

  test('update rewrites in place, keeping the position', () async {
    final first = await service.create(name: 'First', filters: tracked);
    await service.create(
      name: 'Second',
      filters: const CalendarGridFilters(missedOnly: true),
    );

    await service.update(
      first!.copyWith(
        name: 'Renamed',
        filters: const CalendarGridFilters(countedOnly: true),
      ),
    );

    expect(service.presets.map((p) => p.name), ['Renamed', 'Second']);
    expect(
      service.presets.first.filters,
      const CalendarGridFilters(countedOnly: true),
    );
  });

  group('reorder', () {
    List<String> names() => [for (final p in service.presets) p.name];

    Future<void> seedThree() async {
      await service.create(name: 'A', filters: tracked);
      await service.create(
        name: 'B',
        filters: const CalendarGridFilters(missedOnly: true),
      );
      await service.create(
        name: 'C',
        filters: const CalendarGridFilters(hideEnded: true),
      );
    }

    test('the new order persists and survives a reload', () async {
      await seedThree();
      final ids = {for (final p in service.presets) p.name: p.id};

      await service.reorder([ids['C']!, ids['A']!, ids['B']!]);

      expect(names(), ['C', 'A', 'B']);
      await service.reload();
      expect(names(), ['C', 'A', 'B']);
      expect(service.presets.map((p) => p.sortOrder), [0, 1, 2]);
    });

    /// Issued back to back without awaiting the first — the shape two quick
    /// drags produce. The chain is what makes the *last* one the truth.
    test('racing reorders land in the order they were issued', () async {
      await seedThree();
      final ids = [for (final p in service.presets) p.id];
      final first = ids.reversed.toList();
      final second = [ids.last, ...ids.take(ids.length - 1)];

      final a = service.reorder(first);
      final b = service.reorder(second);
      await Future.wait([a, b]);

      expect([for (final p in service.presets) p.id], second);
    });

    /// A link that throws must surface to its caller and leave the cache
    /// as it was, and the chain must keep accepting work afterwards.
    test('a failed write surfaces, changes nothing, and does not poison '
        'later ones', () async {
      await seedThree();
      final ids = [for (final p in service.presets) p.id];
      // The database itself refuses the write, the way a full disk or a
      // locked file would — an id nothing matches would merely update no
      // rows, which is not a failure.
      await db.customStatement(
        'CREATE TRIGGER block_preset_updates BEFORE UPDATE '
        'ON calendar_filter_presets BEGIN SELECT RAISE(ABORT, \'blocked\'); END',
      );

      await expectLater(
        service.reorder(ids.reversed.toList()),
        throwsA(anything),
      );
      expect([for (final p in service.presets) p.id], ids);

      await db.customStatement('DROP TRIGGER block_preset_updates');
      await service.reorder(ids.reversed.toList());

      expect([for (final p in service.presets) p.id], ids.reversed);
    });

    test('an unknown id updates nothing and is not a failure', () async {
      await seedThree();
      final before = names();

      await service.reorder(const ['no-such-preset']);

      expect(names(), before);
    });

    test('reordering nothing leaves the order alone', () async {
      await seedThree();
      final before = names();

      await service.reorder(const []);

      expect(names(), before);
    });

    test('a later save still appends after a reorder', () async {
      await seedThree();
      final ids = [for (final p in service.presets) p.id];
      await service.reorder(ids.reversed.toList());

      await service.create(
        name: 'D',
        filters: const CalendarGridFilters(countedOnly: true),
      );

      expect(names(), ['C', 'B', 'A', 'D']);
    });
  });

  test('delete removes it from the list', () async {
    final saved = await service.create(name: 'Training', filters: tracked);

    await service.delete(saved!.id);

    expect(service.presets, isEmpty);
    expect(service.matching(tracked), isNull);
  });

  /// The cap is refused rather than thrown: the user reached it by tapping
  /// Save, and the caller reports it.
  test('create refuses past the limit', () async {
    for (var i = 0; i < FilterPresetService.maxPresets; i++) {
      await service.create(
        name: 'Preset $i',
        filters: CalendarGridFilters(priorities: {1 + (i % 5)}),
      );
    }

    expect(service.isFull, isTrue);
    expect(
      await service.create(name: 'One too many', filters: tracked),
      isNull,
    );
    expect(service.presets, hasLength(FilterPresetService.maxPresets));
  });

  group('backup', () {
    test('round-trips presets', () async {
      await service.create(name: 'Training', filters: tracked);
      await service.create(
        name: 'Missed',
        filters: const CalendarGridFilters(missedOnly: true),
      );

      final exported = await service.exportData();
      await service.importData(exported);

      expect(service.presets.map((p) => p.name), ['Training', 'Missed']);
      expect(service.presets.first.filters, tracked);
    });

    test('import replaces rather than merges', () async {
      await service.create(name: 'Stale', filters: tracked);

      await service.importData([
        {
          'id': 'imported',
          'name': 'Imported',
          'filters': '{"hideEnded":true}',
          'sortOrder': 0,
        },
      ]);

      expect(service.presets.map((p) => p.name), ['Imported']);
      expect(
        service.presets.single.filters,
        const CalendarGridFilters(hideEnded: true),
      );
    });

    /// The blob is exported verbatim and stored verbatim, so an axis this
    /// build has never heard of survives a restore instead of being erased by
    /// a decode/re-encode round trip.
    test('an unknown axis survives a restore', () async {
      await service.importData([
        {
          'id': 'future',
          'name': 'From a newer build',
          'filters': '{"trackedOnly":true,"someFutureAxis":"yes"}',
        },
      ]);

      final exported = await service.exportData();
      expect(exported.single['filters'], contains('someFutureAxis'));
      // And what this build *does* understand still applies.
      expect(service.presets.single.filters.trackedOnly, isTrue);
    });

    test('a malformed row is skipped, not fatal', () async {
      await service.importData([
        'not a map',
        {'name': 'No id'},
        {'id': 'ok', 'name': 'Fine', 'filters': '{"trackedOnly":true}'},
      ]);

      expect(service.presets.map((p) => p.name), ['Fine']);
    });

    /// A blob that no longer parses keeps its named row rather than being
    /// deleted on the user's behalf — it simply decodes to "nothing filtered".
    test('an unparseable blob keeps the row', () async {
      await service.importData([
        {'id': 'broken', 'name': 'Broken', 'filters': 'not json'},
      ]);

      expect(service.presets.single.name, 'Broken');
      expect(service.presets.single.filters, CalendarGridFilters.none);
    });
  });
}
