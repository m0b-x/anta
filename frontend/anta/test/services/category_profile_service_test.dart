import 'dart:async';

// `isNull` / `isNotNull` are SQL builders in drift and matchers in
// flutter_test; this file wants the matchers.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/category_kinds.dart';
import 'package:anta/constants/category_profiles.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/category_profile.dart';
import 'package:anta/services/category_profile_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/event_alert_service.dart';

import '../database/support/db_test_support.dart';

/// Runs the real DAO and the real [CategoryProfiles] facade against
/// `NativeDatabase.memory()`, the alert service suite's setup: what a save,
/// a clear, a merge's second row, a database switch, a category delete and
/// a restore leave the synchronous readers holding.
void main() {
  late AppDatabase db;
  late CategoryProfileService service;

  setUp(() async {
    CategoryProfileService.reset();
    db = await openTestDatabase();
    service = await CategoryProfileService.forTesting(db);
  });

  tearDown(() async {
    CategoryProfileService.reset();
    CategoryService.reset();
    EventAlertService.reset();
    await db.close();
  });

  Future<List<CategoryProfileRow>> rows() =>
      db.select(db.calendarCategoryProfiles).get();

  const workout = CategoryProfile(
    id: 'p1',
    categoryId: 'gym',
    kind: CategoryKind.workout,
  );

  group('save', () {
    test('inserts, publishes and bumps the revision', () async {
      final before = CategoryProfiles.revision;

      final stored = await service.save(workout);

      expect(stored.id, isNot(workout.id), reason: 'the service mints ids');
      expect(stored.createdAt, isNotNull);
      expect(CategoryProfiles.revision, greaterThan(before));
      expect(CategoryProfiles.profileFor('gym'), stored);
      expect(
        CategoryProfiles.effectiveFor('gym'),
        CategoryProfile.effectiveOf(workout),
      );
      expect(CategoryProfiles.effectiveFor('gym').kind, CategoryKind.workout);
      expect((await rows()).single.id, stored.id);
    });

    test('a second save updates in place under the first id', () async {
      final first = await service.save(workout);

      final stored = await service.save(
        workout.copyWith(id: 'p2', kind: CategoryKind.study),
      );

      expect(stored.id, first.id);
      expect(stored.kind, CategoryKind.study);
      final all = await rows();
      expect(all.single.id, first.id);
      expect(all.single.version, 2);
      expect(CategoryProfiles.profileFor('gym')?.kind, CategoryKind.study);
    });

    test('a cleared override is written as cleared', () async {
      await service.save(
        workout.copyWith(
          countsHours: false,
          target: const ReportTarget(kind: TargetKind.maxGap, value: 4),
        ),
      );

      final stored = await service.save(
        CategoryProfiles.profileFor(
          'gym',
        )!.copyWith(clearCountsHours: true, clearTarget: true),
      );

      expect(stored.countsHours, isNull);
      expect(stored.target, isNull);
      final row = (await rows()).single;
      expect(row.countsHours, isNull);
      expect(row.targetKind, isNull);
      expect(row.targetValue, isNull);
    });
  });

  test('clear tombstones the row and the category is unprofiled', () async {
    await service.save(workout);
    final before = CategoryProfiles.revision;

    await service.clear('gym');

    expect(CategoryProfiles.revision, greaterThan(before));
    expect(CategoryProfiles.profileFor('gym'), isNull);
    expect(CategoryProfiles.effectiveFor('gym'), EffectiveProfile.unprofiled);
    expect((await rows()).single.isDeleted, isTrue);
  });

  test('a category never saved is unprofiled and has no row', () async {
    expect(CategoryProfiles.profileFor('climb'), isNull);
    expect(CategoryProfiles.effectiveFor('climb').isUnprofiled, isTrue);
    expect(await rows(), isEmpty);
  });

  test('two live rows of one category resolve to the newer stamp', () async {
    final now = DateTime.now();
    CalendarCategoryProfilesCompanion live(String id, String kind) =>
        CalendarCategoryProfilesCompanion(
          id: Value(id),
          categoryId: const Value('gym'),
          kind: Value(kind),
          createdAt: Value(now),
          updatedAt: Value(now),
        );
    // `importAll` stamps in order, so the second is the newer; its id sorts
    // first, so an order by id would pick the other.
    await db.categoryProfileDao.importAll([
      live('z-older', 'study'),
      live('a-newer', 'workout'),
    ]);

    await service.reload();

    expect(CategoryProfiles.profileFor('gym')?.id, 'a-newer');
    expect(CategoryProfiles.effectiveFor('gym').kind, CategoryKind.workout);
    final exported = await service.exportCategoryProfiles();
    expect(exported.single[CategoryProfileKeys.id], 'a-newer');
  });

  test('a database switch drops the instance and clears the facade', () async {
    await service.save(workout);
    final before = CategoryProfiles.revision;

    DatabaseLifecycle.notifyDatabaseSwitching();

    expect(CategoryProfiles.all, isEmpty);
    expect(CategoryProfiles.effectiveFor('gym').isUnprofiled, isTrue);
    expect(CategoryProfiles.revision, greaterThan(before));
    final next = await CategoryProfileService.forTesting(db);
    expect(identical(next, service), isFalse);
    expect(CategoryProfiles.profileFor('gym')?.kind, CategoryKind.workout);
  });

  test('a category delete drops its profile from the facade', () async {
    final categories = await CategoryService.forTesting(db);
    final custom = await categories.create(
      name: 'Climbing',
      colorValue: 0xFF00AAFF,
      iconKey: 'event',
    );
    await service.save(
      CategoryProfile(
        id: 'p-climb',
        categoryId: custom.id,
        kind: CategoryKind.workout,
      ),
    );
    await service.save(workout);

    expect(await categories.deleteCategory(custom.id), isTrue);

    expect(CategoryProfiles.profileFor(custom.id), isNull);
    expect(CategoryProfiles.profileFor('gym'), isNotNull);
    final tombstone = (await rows()).singleWhere(
      (r) => r.categoryId == custom.id,
    );
    expect(tombstone.isDeleted, isTrue);
  });

  group('export and import', () {
    final created = DateTime.utc(2026, 2, 3, 4, 5, 6);
    final updated = DateTime.utc(2026, 5, 6, 7, 8, 9);

    test(
      'every field round-trips, an off verb and a target among them',
      () async {
        const full = CategoryProfile(
          id: 'p-full',
          categoryId: 'gym',
          kind: CategoryKind.workout,
          area: LifeArea.people,
          measure: ReportMeasure.hours,
          nominalMinutes: 75,
          markVerb: '',
          marksNew: false,
          assumeAbsentNew: true,
          countsHours: false,
          target: ReportTarget(
            kind: TargetKind.atLeast,
            value: 3,
            period: TargetPeriod.week,
          ),
        );
        await service.save(full);
        final exported = await service.exportCategoryProfiles();
        final stored = CategoryProfiles.profileFor('gym')!;
        expect(
          CategoryProfile.fromJson(exported.single),
          stored,
          reason: 'a decoded export carries the row\'s local dates',
        );

        final dropped = await service.importCategoryProfiles(
          exported,
          knownCategoryIds: const {'gym'},
        );

        expect(dropped, 0);
        final back = CategoryProfiles.profileFor('gym')!;
        expect(back, stored);
        expect(back.markVerb, '');
        expect(
          back.effective.assumeAbsentNew,
          isFalse,
          reason: 'an off verb holds through the round trip',
        );
        expect(
          back,
          full.copyWith(
            id: stored.id,
            createdAt: stored.createdAt,
            updatedAt: stored.updatedAt,
          ),
        );
      },
    );

    test('an orphan is dropped and counted, dates and owner kept', () async {
      final archive = [
        {
          ...const CategoryProfile(
            id: 'p-gym',
            categoryId: 'gym',
            kind: CategoryKind.workout,
          ).copyWith(createdAt: created, updatedAt: updated).toJson(),
          'ownerId': 'uid-1',
        },
        const CategoryProfile(
          id: 'p-orphan',
          categoryId: 'gone',
          kind: CategoryKind.bill,
        ).toJson(),
      ];

      final dropped = await service.importCategoryProfiles(
        archive,
        knownCategoryIds: const {'gym'},
      );

      expect(dropped, 1);
      expect(CategoryProfiles.all.keys, ['gym']);
      final row = (await rows()).single;
      expect(row.id, 'p-gym');
      expect(row.createdAt.isAtSameMomentAs(created), isTrue);
      expect(row.updatedAt.isAtSameMomentAs(updated), isTrue);
      expect(row.ownerId, 'uid-1');
    });

    test('a malformed row is dropped and counted', () async {
      final dropped = await service.importCategoryProfiles(
        [
          'not a map',
          {'id': '', 'categoryId': 'gym'},
          {'id': 'p1', 'categoryId': 'gym', 'kind': 'workout'},
        ],
        knownCategoryIds: const {'gym'},
      );

      expect(dropped, 2);
      expect(CategoryProfiles.profileFor('gym')?.kind, CategoryKind.workout);
    });

    test('an import replaces what was there, tombstones included', () async {
      await service.save(workout);
      await service.clear('gym');
      await service.save(workout.copyWith(id: 'p-run', categoryId: 'run'));

      await service.importCategoryProfiles(
        const [],
        knownCategoryIds: const {'gym', 'run'},
      );

      expect(await rows(), isEmpty);
      expect(CategoryProfiles.all, isEmpty);
    });

    test('clearing for an import empties the table and the facade', () async {
      await service.save(workout);

      await service.clearCategoryProfilesForImport();

      expect(await rows(), isEmpty);
      expect(CategoryProfiles.all, isEmpty);
    });

    /// A row a newer build wrote and a sync brought here: read through the
    /// model, the export would turn it into a `custom` profile with no goal,
    /// and a restore of that backup would downgrade the category for good.
    test('values this build cannot read leave and return raw', () async {
      final now = DateTime.now();
      await db.categoryProfileDao.importAll([
        CalendarCategoryProfilesCompanion(
          id: const Value('p-future'),
          categoryId: const Value('gym'),
          kind: const Value('futureKind'),
          area: const Value('futureArea'),
          measure: const Value('futureMeasure'),
          nominalMinutes: const Value(0),
          targetKind: const Value('futureTarget'),
          targetValue: const Value(4),
          targetPeriod: const Value('fortnight'),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      ]);
      await service.reload();
      expect(CategoryProfiles.effectiveFor('gym').kind, CategoryKind.custom);

      final exported = (await service.exportCategoryProfiles()).single;
      expect(exported[CategoryProfileKeys.kind], 'futureKind');
      expect(exported[CategoryProfileKeys.area], 'futureArea');
      expect(exported[CategoryProfileKeys.measure], 'futureMeasure');
      expect(exported[CategoryProfileKeys.nominalMinutes], 0);
      expect(exported[CategoryProfileKeys.targetKind], 'futureTarget');
      expect(exported[CategoryProfileKeys.targetPeriod], 'fortnight');

      final dropped = await service.importCategoryProfiles(
        [exported],
        knownCategoryIds: const {'gym'},
      );

      expect(dropped, 0);
      final row = (await rows()).single;
      expect(row.kind, 'futureKind');
      expect(row.area, 'futureArea');
      expect(row.measure, 'futureMeasure');
      expect(row.nominalMinutes, 0);
      expect(row.targetKind, 'futureTarget');
      expect(row.targetValue, 4);
      expect(row.targetPeriod, 'fortnight');
      expect(await service.exportCategoryProfiles(), [exported]);
    });

    test('a mistyped row is dropped, the valid one kept', () async {
      await service.save(workout.copyWith(categoryId: 'run'));

      final dropped = await service.importCategoryProfiles(
        [
          {'id': 'p-bad', 'categoryId': 'gym', 'kind': 7},
          {'id': 'p-good', 'categoryId': 'gym', 'kind': 'study'},
        ],
        knownCategoryIds: const {'gym', 'run'},
      );

      expect(dropped, 1);
      expect((await rows()).single.id, 'p-good');
      expect(CategoryProfiles.all.keys, ['gym']);
      expect(CategoryProfiles.profileFor('gym')?.kind, CategoryKind.study);
    });

    /// The category alerts' rule: the archive is the authority over a
    /// category id space the restore just replaced, so a profile kept from
    /// here would attach to whatever category now holds its id.
    test('an archive whose every row is dropped still replaces', () async {
      await service.save(workout);

      final dropped = await service.importCategoryProfiles(
        [
          {'id': 'p-bad', 'categoryId': 'gym', 'marksNew': 'yes'},
          {'id': 'p-orphan', 'categoryId': 'gone'},
        ],
        knownCategoryIds: const {'gym'},
      );

      expect(dropped, 2);
      expect(await rows(), isEmpty);
      expect(CategoryProfiles.all, isEmpty);
    });
  });

  group('ids', () {
    test('a draft id another category holds gets a fresh one', () async {
      final run = await service.save(workout.copyWith(categoryId: 'run'));

      final gym = await service.save(workout.copyWith(id: run.id));

      expect(gym.id, isNot(run.id));
      expect(gym.categoryId, 'gym');
      final live = {
        for (final row in await rows())
          if (!row.isDeleted) row.categoryId: row.id,
      };
      expect(live, {'run': run.id, 'gym': gym.id});
      expect(CategoryProfiles.profileFor('run')?.id, run.id);
      expect(CategoryProfiles.profileFor('gym')?.id, gym.id);
    });
  });

  group('a construction in flight', () {
    /// A restore resetting the service while the calendar's first touch is
    /// still reading: the construction it overtook must not install itself,
    /// nor publish the profiles it read.
    test('a reset while it is in flight discards it', () async {
      await service.save(workout);
      final other = await openTestDatabase();
      addTearDown(other.close);
      CategoryProfileService.reset();

      final leaving = CategoryProfileService.forTesting(db);
      CategoryProfileService.reset();
      final arrived = await CategoryProfileService.forTesting(other);
      final discarded = await leaving;

      expect(
        identical(discarded, arrived),
        isTrue,
        reason: 'the construction the reset overtook must not be handed out',
      );
      expect(
        CategoryProfiles.all,
        isEmpty,
        reason: "the closing database's profiles must never be published",
      );
    });

    test('a database switch while it is in flight restarts it', () async {
      await service.save(workout);
      DatabaseLifecycle.notifyDatabaseSwitching();
      expect(DatabaseLifecycle.registeredHandlerCount, 0);

      final leaving = CategoryProfileService.forTesting(db);
      DatabaseLifecycle.notifyDatabaseSwitching();
      final arrived = await leaving;

      expect(DatabaseLifecycle.registeredHandlerCount, 1);
      expect(
        identical(await CategoryProfileService.forTesting(db), arrived),
        isTrue,
      );

      // The handler it registered is the live instance's: the next switch
      // drops it.
      DatabaseLifecycle.notifyDatabaseSwitching();
      expect(CategoryProfiles.all, isEmpty);
      expect(
        identical(await CategoryProfileService.forTesting(db), arrived),
        isFalse,
      );
    });

    test('forTesting refuses a second database', () async {
      final other = await openTestDatabase();
      addTearDown(other.close);

      expect(
        () => CategoryProfileService.forTesting(other),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('the write chain', () {
    /// `AppSyncApplyHooks` reloads the profiles once per pulled page. The
    /// reload used to empty the working copy before its read, so a save in
    /// that window published its own category alone under a bumped
    /// revision.
    test('saves overlapping a reload publish every category', () async {
      final gate = _HeldProfileRead();
      final gated = await openTestDatabase(interceptor: gate);
      addTearDown(() async {
        gate.release();
        await gated.close();
      });
      CategoryProfileService.reset();
      final profiles = await CategoryProfileService.forTesting(gated);
      await profiles.save(workout.copyWith(categoryId: 'run'));

      gate.holdNextProfileRead();
      final reload = profiles.reload();
      await pumpEventQueue();
      expect(gate.held, isTrue);
      final first = profiles.save(workout);
      final second = profiles.save(workout.copyWith(kind: CategoryKind.study));
      await pumpEventQueue();
      expect(CategoryProfiles.all.keys, contains('run'));

      gate.release();
      await Future.wait([reload, first, second]);

      final live = [
        for (final row
            in await gated.select(gated.calendarCategoryProfiles).get())
          if (!row.isDeleted && row.categoryId == 'gym') row,
      ];
      expect(live, hasLength(1));
      expect(CategoryProfiles.all.keys, unorderedEquals(['gym', 'run']));
      expect(CategoryProfiles.profileFor('gym')?.kind, CategoryKind.study);
    });
  });

  group('refreshAfterSync', () {
    CategoryProfileRow pulled() => CategoryProfileRow(
      id: 'p-pulled',
      categoryId: 'climb',
      kind: 'workout',
      createdAt: DateTime(2026, 3, 1),
      updatedAt: DateTime(2026, 3, 2),
      hlcTimestamp: '0193a0b0c0d0:0002:dev-b',
      deviceId: 'dev-b',
      version: 1,
      isDeleted: false,
    );

    /// Decision AG: the sync path never creates the service; the next
    /// `getInstance` reads the merged table anyway.
    test('with no instance it creates none', () async {
      DatabaseLifecycle.notifyDatabaseSwitching();
      await db.categoryProfileDao.mergeRemoteCategoryProfile(pulled());

      await CategoryProfileService.refreshAfterSync();

      expect(DatabaseLifecycle.registeredHandlerCount, 0);
      expect(CategoryProfiles.all, isEmpty);
    });

    test('a live instance shows a merged row after it', () async {
      await db.categoryProfileDao.mergeRemoteCategoryProfile(pulled());
      expect(CategoryProfiles.profileFor('climb'), isNull);

      await CategoryProfileService.refreshAfterSync();

      expect(CategoryProfiles.profileFor('climb')?.id, 'p-pulled');
    });

    test('an instance still loading is waited for and reloaded', () async {
      final gate = _HeldProfileRead();
      final gated = await openTestDatabase(interceptor: gate);
      addTearDown(() async {
        gate.release();
        await gated.close();
      });
      CategoryProfileService.reset();

      gate.holdNextProfileRead();
      final loading = CategoryProfileService.forTesting(gated);
      await pumpEventQueue();
      expect(gate.held, isTrue);
      // Merged after the construction's read: only a reload can show it.
      await gated.categoryProfileDao.mergeRemoteCategoryProfile(pulled());
      final refresh = CategoryProfileService.refreshAfterSync();

      gate.release();
      await refresh;

      expect(CategoryProfiles.profileFor('climb')?.id, 'p-pulled');
      expect(
        identical(
          await loading,
          await CategoryProfileService.forTesting(gated),
        ),
        isTrue,
      );
    });
  });
}

/// Holds the next read of `calendar_category_profiles` after it ran: its rows
/// are what the table held when it was asked, handed back only on
/// [release] — the window a sync pull's reload is open for.
class _HeldProfileRead extends QueryInterceptor {
  Completer<void>? _hold;
  bool _armed = false;
  bool held = false;

  void holdNextProfileRead() {
    _armed = true;
    _hold = Completer<void>();
  }

  void release() {
    final hold = _hold;
    _hold = null;
    _armed = false;
    if (hold != null && !hold.isCompleted) hold.complete();
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await super.runSelect(executor, statement, args);
    final hold = _hold;
    if (_armed &&
        hold != null &&
        statement.contains('calendar_category_profiles')) {
      _armed = false;
      held = true;
      await hold.future;
    }
    return rows;
  }
}
