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
