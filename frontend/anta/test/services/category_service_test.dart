import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/category_service.dart';

import '../database/support/db_test_support.dart';

/// Runs the real DAO and the real facade against `NativeDatabase.memory()`,
/// the way the `test/database` suite does.
///
/// The assertions that earn their place are the ones where hiding differs from
/// deleting — a hidden category is still resolvable, unhiding puts it back
/// where it was, a backup written before the flag existed restores everything
/// visible — and the one where reorder differs from a plain write: two drags
/// racing each other must not resurrect the first arrangement.
void main() {
  late AppDatabase db;
  late CategoryService service;

  setUp(() async {
    CategoryService.reset();
    db = await openTestDatabase();
    service = await CategoryService.forTesting(db);
  });

  tearDown(() async {
    CategoryService.reset();
    await db.close();
  });

  test('a freshly seeded catalog is entirely visible', () {
    expect(CalendarCategories.all, isNotEmpty);
    expect(
      CalendarCategories.visible.length,
      CalendarCategories.all.length,
      reason: 'built-ins seed unhidden; the column defaults to 0',
    );
    expect(CalendarCategories.all.every((c) => !c.isHidden), isTrue);
  });

  group('setHidden', () {
    test('drops the category from visible but keeps it resolvable', () async {
      await service.setHidden('gym', true);

      expect(
        CalendarCategories.visible.map((c) => c.id),
        isNot(contains('gym')),
      );
      expect(CalendarCategories.all.map((c) => c.id), contains('gym'));
      expect(CalendarCategories.resolve('gym').id, 'gym');
      expect(CalendarCategories.byId('gym')!.isHidden, isTrue);
    });

    test('a built-in can be hidden', () async {
      await service.setHidden('other', true);
      expect(CalendarCategories.byId('other')!.isHidden, isTrue);
      expect(CalendarCategories.byId('other')!.isBuiltIn, isTrue);
    });

    test('unhiding restores the category to its old position', () async {
      final before = CalendarCategories.all.map((c) => c.id).toList();
      final order = CalendarCategories.byId('cardio')!.sortOrder;

      await service.setHidden('cardio', true);
      await service.setHidden('cardio', false);

      expect(CalendarCategories.byId('cardio')!.sortOrder, order);
      expect(
        CalendarCategories.all.map((c) => c.id),
        before,
        reason:
            'hiding must leave sort_order untouched — that is the whole edge '
            'over deleting and re-creating',
      );
    });

    test('survives a reload from the database', () async {
      await service.setHidden('rest', true);
      CategoryService.reset();
      final reopened = await CategoryService.forTesting(db);

      expect(
        reopened.categories.firstWhere((c) => c.id == 'rest').isHidden,
        isTrue,
      );
      expect(
        CalendarCategories.visible.map((c) => c.id),
        isNot(contains('rest')),
      );
    });

    test('setting the state it already has writes nothing', () async {
      final revision = CalendarCategories.revision;
      await service.setHidden('gym', false);
      expect(
        CalendarCategories.revision,
        revision,
        reason: 'a repeated tap must not churn updated_at or the revision',
      );
    });

    test('an unknown id is a no-op', () async {
      final revision = CalendarCategories.revision;
      await service.setHidden('no-such-category', true);
      expect(CalendarCategories.revision, revision);
    });

    test('hiding bumps the revision the grid memo keys on', () async {
      final revision = CalendarCategories.revision;
      await service.setHidden('gym', true);
      expect(CalendarCategories.revision, greaterThan(revision));
    });
  });

  group('reorder', () {
    List<String> currentIds() => [for (final c in CalendarCategories.all) c.id];

    test('the new order persists and the facade reflects it', () async {
      final reversed = currentIds().reversed.toList();

      await service.reorder(reversed);

      expect(currentIds(), reversed);
      expect(service.categories.map((c) => c.id), reversed);
    });

    test('it survives a reload from the database', () async {
      final reversed = currentIds().reversed.toList();
      await service.reorder(reversed);

      CategoryService.reset();
      await CategoryService.forTesting(db);

      expect(currentIds(), reversed);
    });

    test('sort orders come back dense', () async {
      await service.reorder(currentIds().reversed.toList());
      expect(CalendarCategories.all.map((c) => c.sortOrder), [
        for (var i = 0; i < CalendarCategories.all.length; i++) i,
      ]);
    });

    test('it bumps the revision the grid memo keys on', () async {
      final revision = CalendarCategories.revision;
      await service.reorder(currentIds().reversed.toList());
      expect(CalendarCategories.revision, greaterThan(revision));
    });

    test('a custom category can be dragged ahead of the built-ins', () async {
      final custom = await service.create(
        name: 'Work',
        colorValue: 0xFF00AAFF,
        iconKey: 'event',
      );
      final promoted = [
        custom.id,
        ...currentIds().where((id) => id != custom.id),
      ];

      await service.reorder(promoted);

      expect(currentIds().first, custom.id);
    });

    test('racing writes land in the order they were issued', () async {
      final ids = currentIds();
      final first = ids.reversed.toList();
      final second = [ids.last, ...ids.take(ids.length - 1)];

      // Issued back to back without awaiting the first — the shape two quick
      // drags produce. Chaining is what makes the *last* one the truth; without
      // it the loser can land second and resurrect the earlier arrangement.
      final a = service.reorder(first);
      final b = service.reorder(second);
      await Future.wait([a, b]);

      expect(currentIds(), second);
    });

    test('a failed write does not poison later ones', () async {
      // An id nothing matches updates no rows — harmless — but the point is
      // that the chain keeps accepting work afterwards.
      await service.reorder(const ['no-such-category']);
      final reversed = currentIds().reversed.toList();

      await service.reorder(reversed);

      expect(currentIds(), reversed);
    });

    test('reordering nothing leaves the order alone', () async {
      final before = currentIds();
      await service.reorder(const []);
      expect(currentIds(), before);
    });
  });

  group('backup', () {
    test('round-trips the flag', () async {
      final custom = await service.create(
        name: 'Dentist',
        colorValue: 0xFF00AAFF,
        iconKey: 'event',
      );
      await service.setHidden(custom.id, true);
      await service.setHidden('gym', true);

      final exported = await service.exportData();
      expect(
        exported.firstWhere((r) => r['id'] == custom.id)['isHidden'],
        isTrue,
      );

      await service.importData(exported);

      expect(CalendarCategories.byId(custom.id)!.isHidden, isTrue);
      expect(CalendarCategories.byId('gym')!.isHidden, isTrue);
      expect(CalendarCategories.byId('other')!.isHidden, isFalse);
    });

    test('a pre-v33 backup imports everything visible', () async {
      await service.setHidden('gym', true);
      final exported = await service.exportData();
      // Exactly what an archive written before the column existed looks like:
      // the key is simply absent.
      final legacy = [
        for (final row in exported)
          {
            for (final entry in row.entries)
              if (entry.key != 'isHidden') entry.key: entry.value,
          },
      ];

      await service.importData(legacy);

      expect(
        CalendarCategories.all.every((c) => !c.isHidden),
        isTrue,
        reason:
            'an older archive cannot describe a hidden category because none '
            'existed — restoring everything visible is what it recorded',
      );
      expect(CalendarCategories.visible.length, CalendarCategories.all.length);
    });

    test('a malformed isHidden costs the flag, not the category', () async {
      final custom = await service.create(
        name: 'Dentist',
        colorValue: 0xFF00AAFF,
        iconKey: 'event',
      );
      final exported = await service.exportData();
      final corrupted = [
        for (final row in exported) {...row, 'isHidden': 'yes'},
      ];

      await service.importData(corrupted);

      expect(CalendarCategories.all.every((c) => !c.isHidden), isTrue);
      expect(
        CalendarCategories.byId(custom.id),
        isNotNull,
        reason:
            'the flag is read by type test rather than a cast — a junk value '
            'must not throw the whole row out of the restore, which for a '
            'custom category is unrecoverable data loss',
      );
    });
  });
}
