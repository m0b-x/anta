import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/calendar_categories.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/calendar_category.dart';
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

  /// Every mutation writes a whole row from a model the caller captured at
  /// some earlier moment, so the question is what a *stale* field in that
  /// model may overwrite. Order is the dangerous one: it is the only field
  /// another surface (the drag) owns, and clobbering it also breaks the dense
  /// `0..N-1` invariant, after which `_byOrder`'s id tie-break shuffles rows
  /// nobody touched.
  group('a write cannot clobber the order', () {
    List<String> currentIds() => [for (final c in CalendarCategories.all) c.id];

    test('updateCategory ignores a stale sortOrder on the model', () async {
      final reversed = currentIds().reversed.toList();
      await service.reorder(reversed);
      final moved = CalendarCategories.byId('gym')!;

      // The shape an editor sheet produces: opened before the drag, saved
      // after it, so `sortOrder` still holds the pre-drag value.
      await service.updateCategory(
        moved.copyWith(sortOrder: 0, colorValue: 0xFF123456),
      );

      expect(CalendarCategories.byId('gym')!.colorValue, 0xFF123456);
      expect(currentIds(), reversed);
      expect(
        CalendarCategories.all.map((c) => c.sortOrder),
        [for (var i = 0; i < CalendarCategories.all.length; i++) i],
        reason: 'the dense 0..N-1 order reorder writes must survive a save',
      );
    });

    test('hiding after a drag leaves the dragged position alone', () async {
      final reversed = currentIds().reversed.toList();
      await service.reorder(reversed);

      await service.setHidden('gym', true);

      expect(CalendarCategories.byId('gym')!.isHidden, isTrue);
      expect(currentIds(), reversed);
    });

    test('a hide issued during a drag persist still lands after it', () async {
      final reversed = currentIds().reversed.toList();

      // Not awaited: the drag's write is still in flight when the menu fires,
      // which is exactly when a re-read of the cache would be stale.
      final drag = service.reorder(reversed);
      final hide = service.setHidden('rest', true);
      await Future.wait([drag, hide]);

      expect(currentIds(), reversed);
      expect(CalendarCategories.byId('rest')!.isHidden, isTrue);
    });

    test('updateCategory ignores a stale isHidden on the model', () async {
      await service.setHidden('gym', true);
      // The shape the editor sheet produces: `widget.initial` was captured
      // before the hide landed, and the sheet has no control for the flag, so
      // all it can do is echo the value it read.
      final stale = CalendarCategory(
        id: 'gym',
        name: 'Gym',
        colorValue: 0xFF123456,
        iconKey: 'fitness_center',
        sortOrder: 0,
        isBuiltIn: true,
      );

      await service.updateCategory(stale);

      expect(CalendarCategories.byId('gym')!.colorValue, 0xFF123456);
      expect(
        CalendarCategories.byId('gym')!.isHidden,
        isTrue,
        reason:
            'the archive flag belongs to setHidden; a colour edit saved over '
            'a stale model must not silently un-archive the category',
      );
      expect(
        CalendarCategories.visible.map((c) => c.id),
        isNot(contains('gym')),
      );
    });

    test('updateCategory cannot flip isBuiltIn', () async {
      final builtIn = CalendarCategories.byId('gym')!;
      await service.updateCategory(
        CalendarCategory(
          id: builtIn.id,
          name: builtIn.name,
          colorValue: builtIn.colorValue,
          iconKey: builtIn.iconKey,
          sortOrder: builtIn.sortOrder,
          isBuiltIn: false,
        ),
      );

      expect(
        CalendarCategories.byId('gym')!.isBuiltIn,
        isTrue,
        reason: 'a built-in that could be un-flagged becomes deletable',
      );
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
