import 'package:drift/drift.dart' show QueryInterceptor, QueryExecutor;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_colors.dart';
import 'package:anta/constants/calendar_palette.dart';
import 'package:anta/constants/settings_keys.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/calendar_palette_service.dart';
import 'package:anta/services/settings_service.dart';

import '../database/support/db_test_support.dart';

/// Runs the real settings rows and the real facade against
/// `NativeDatabase.memory()`.
///
/// The assertions that earn their place are the ones where the palette is not
/// just a list: a built-in can never be stored (so re-seeding the shipped
/// swatches keeps reaching existing installs), the retired recent-colors row
/// folds in exactly once (so a colour the user then deleted cannot come back),
/// and a reset drops only the half the user owns.
void main() {
  late AppDatabase db;
  late SettingsService settings;
  late CalendarPaletteService service;

  const customA = 0xFF123456;
  const customB = 0xFF654321;
  final builtIn = CalendarColors.swatchPalette.first;

  setUp(() async {
    CalendarPaletteService.reset();
    SettingsService.reset();
    db = await openTestDatabase();
    settings = SettingsService.forTesting(db);
    service = await CalendarPaletteService.getInstance();
  });

  tearDown(() async {
    CalendarPaletteService.reset();
    SettingsService.reset();
    await db.close();
  });

  test('a fresh install offers the built-in swatches and nothing else', () {
    expect(CalendarPalette.custom, isEmpty);
    expect(CalendarPalette.all, CalendarColors.swatchPalette);
    expect(CalendarPalette.isDefault(builtIn), isTrue);
  });

  group('add', () {
    test('appends after the built-ins and publishes the facade', () async {
      expect(await service.add(customA), isTrue);

      expect(service.customColors, [customA]);
      expect(CalendarPalette.all.last, customA);
      expect(CalendarPalette.contains(customA), isTrue);
      expect(CalendarPalette.isDefault(customA), isFalse);
      expect(await settings.getCustomCalendarColors(), [customA]);
    });

    test('refuses a colour the palette already offers', () async {
      await service.add(customA);

      expect(await service.add(customA), isFalse);
      expect(await service.add(builtIn), isFalse);
      expect(service.customColors, [customA]);
    });

    test('refuses past the cap rather than evicting the oldest', () async {
      for (var i = 0; i < SettingsKeys.maxCustomCalendarColors; i++) {
        expect(await service.add(0xFF000001 + i), isTrue);
      }

      expect(await service.add(customA), isFalse);
      expect(service.customColors.length, SettingsKeys.maxCustomCalendarColors);
      expect(service.customColors.first, 0xFF000001);
    });

    test('concurrent adds all land', () async {
      await Future.wait([
        service.add(customA),
        service.add(customB),
        service.add(0xFFABCDEF),
      ]);

      expect(service.customColors, hasLength(3));
      expect(await settings.getCustomCalendarColors(), hasLength(3));
    });
  });

  group('update', () {
    test('recolours in place, keeping the swatch position', () async {
      await service.add(customA);
      await service.add(customB);

      expect(await service.update(customA, 0xFFAAAAAA), isTrue);
      expect(service.customColors, [0xFFAAAAAA, customB]);
    });

    test('refuses to recolour a built-in or onto an existing colour', () async {
      await service.add(customA);

      expect(await service.update(builtIn, customB), isFalse);
      expect(await service.update(customA, builtIn), isFalse);
      expect(service.customColors, [customA]);
    });
  });

  group('remove', () {
    test('drops the swatch and persists the shorter list', () async {
      await service.add(customA);
      await service.add(customB);

      expect(await service.remove(customA), isTrue);
      expect(service.customColors, [customB]);
      expect(await settings.getCustomCalendarColors(), [customB]);
    });

    test('a built-in cannot be removed', () async {
      expect(await service.remove(builtIn), isFalse);
      expect(CalendarPalette.all, contains(builtIn));
    });
  });

  group('move', () {
    test('reorders the stored list, which is the picker order', () async {
      await service.add(customA);
      await service.add(customB);
      await service.add(0xFFABCDEF);

      expect(await service.move(2, 0), isTrue);

      expect(service.customColors, [0xFFABCDEF, customA, customB]);
      expect(await settings.getCustomCalendarColors(), [
        0xFFABCDEF,
        customA,
        customB,
      ]);
      expect(
        CalendarPalette.all.sublist(CalendarPalette.defaults.length),
        [0xFFABCDEF, customA, customB],
        reason: 'the facade publishes the new order, built-ins still first',
      );
    });

    test('a drag that lands where it started changes nothing', () async {
      await service.add(customA);
      await service.add(customB);

      expect(await service.move(1, 1), isFalse);
      expect(service.customColors, [customA, customB]);
    });

    test('out-of-range indices are refused, not thrown', () async {
      await service.add(customA);

      expect(await service.move(0, 5), isFalse);
      expect(await service.move(-1, 0), isFalse);
      expect(await service.move(3, 0), isFalse);
      expect(service.customColors, [customA]);
    });

    test('reordering never changes the set', () async {
      for (var i = 0; i < 5; i++) {
        await service.add(0xFF000001 + i);
      }
      final before = {...service.customColors};

      await service.move(4, 1);
      await service.move(0, 3);

      expect(service.customColors.toSet(), before);
      expect(service.customColors, hasLength(5));
    });
  });

  test('resetToDefaults drops only the user half', () async {
    await service.add(customA);
    await service.add(customB);

    expect(await service.resetToDefaults(), isTrue);
    expect(service.customColors, isEmpty);
    expect(CalendarPalette.all, CalendarColors.swatchPalette);
    expect(await settings.getCustomCalendarColors(), isEmpty);
    expect(await service.resetToDefaults(), isFalse);
  });

  group('legacy recent colours', () {
    setUp(() async {
      CalendarPaletteService.reset();
    });

    test('fold into the palette once, built-ins excluded', () async {
      await db.userSettingsDao.setValue(
        SettingsKeys.recentEventColors,
        '$customA,$builtIn,$customB',
      );

      final migrated = await CalendarPaletteService.getInstance();

      expect(migrated.customColors, [customA, customB]);
      expect(await settings.getRecentEventColors(), isEmpty);
    });

    test('a colour deleted after the fold stays deleted', () async {
      await db.userSettingsDao.setValue(
        SettingsKeys.recentEventColors,
        '$customA',
      );
      final migrated = await CalendarPaletteService.getInstance();
      await migrated.remove(customA);

      CalendarPaletteService.reset();
      final reopened = await CalendarPaletteService.getInstance();

      expect(reopened.customColors, isEmpty);
    });
  });

  group('a failed read', () {
    // The read fails while the row itself is intact — a briefly unavailable
    // database, not a corrupt value. What must never happen is the service
    // reading "unknown" as "empty" and then writing that over the user's
    // swatches, so the failure here is transient and the row stays readable.
    late AppDatabase db;
    late _FailingReads failure;
    late CalendarPaletteService degraded;

    setUp(() async {
      CalendarPaletteService.reset();
      SettingsService.reset();
      failure = _FailingReads();
      db = await openTestDatabase(interceptor: failure);
      final settings = SettingsService.forTesting(db);
      await settings.setCustomCalendarColors(const [customA, customB]);
      failure.failMatching = 'user_settings';
      degraded = await CalendarPaletteService.getInstance();
      failure.failMatching = null;
    });

    tearDown(() async {
      CalendarPaletteService.reset();
      SettingsService.reset();
      await db.close();
    });

    test('publishes an empty palette rather than throwing', () {
      expect(CalendarPalette.custom, isEmpty);
    });

    test(
      'refuses every mutation rather than persisting the emptiness',
      () async {
        expect(await degraded.add(0xFFAAAAAA), isFalse);
        expect(await degraded.remove(customA), isFalse);
        expect(await degraded.update(customA, 0xFFAAAAAA), isFalse);
        expect(await degraded.move(0, 1), isFalse);
        expect(await degraded.resetToDefaults(), isFalse);
      },
    );

    test('the stored swatches are untouched and come back on reload', () async {
      await degraded.add(0xFFAAAAAA);
      await degraded.resetToDefaults();

      await degraded.reload();

      expect(
        degraded.customColors,
        [customA, customB],
        reason: 'writes while degraded must not have reached the row',
      );
      expect(CalendarPalette.custom, [customA, customB]);
    });
  });

  test('two racing first callers share one service', () async {
    CalendarPaletteService.reset();

    final both = await Future.wait([
      CalendarPaletteService.getInstance(),
      CalendarPaletteService.getInstance(),
    ]);

    expect(identical(both.first, both.last), isTrue);

    // The real hazard is two services each rewriting the whole row from their
    // own copy, so the proof is that both adds survive.
    await Future.wait([both.first.add(customA), both.last.add(customB)]);
    expect(both.first.customColors, hasLength(2));
  });

  test('a recolour is published with the pair that produced it', () async {
    await service.add(customA);

    await service.update(customA, 0xFFAAAAAA);
    expect(CalendarPalette.lastRecolor, (customA, 0xFFAAAAAA));

    // Any other update clears it, so it can never describe a stale revision.
    await service.add(customB);
    expect(CalendarPalette.lastRecolor, isNull);
  });

  test('reset() clears the published facade', () async {
    await service.add(customA);
    CalendarPaletteService.reset();

    expect(CalendarPalette.custom, isEmpty);
    expect(CalendarPalette.all, CalendarColors.swatchPalette);
  });
}

/// Fails selects touching a named table while [failMatching] is set, so a test
/// can make one read fail with the row itself still intact and readable.
class _FailingReads extends QueryInterceptor {
  String? failMatching;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    final needle = failMatching;
    if (needle != null && statement.contains(needle)) {
      return Future.error(StateError('read unavailable'));
    }
    return super.runSelect(executor, statement, args);
  }
}
