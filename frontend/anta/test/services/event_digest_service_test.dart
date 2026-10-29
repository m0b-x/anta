import 'package:flutter_test/flutter_test.dart';

import 'package:anta/constants/alert_constants.dart';
import 'package:anta/constants/event_digests.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/database_lifecycle.dart';
import 'package:anta/models/event_digest.dart';
import 'package:anta/services/event_digest_service.dart';

import '../database/support/db_test_support.dart';

/// Runs the real DAO, the real codec and the real facade against
/// `NativeDatabase.memory()` — the overview view service's suite cloned, plus
/// the facade it does not have: every write republishes [EventDigests], the
/// cap refuses at [DigestHorizon.maxDigests], a delete is a tombstone, and a
/// backup keeps what a newer build wrote.
void main() {
  late AppDatabase db;
  late EventDigestService service;

  const birthdays = EventDigest(
    id: 'draft',
    name: '  Birthdays ',
    cadence: DigestCadence.weekly,
    anchor: DateTime.sunday,
    minute: 20 * 60,
    leadDays: 1,
    categoryIds: {'birthday'},
    includeEmpty: true,
  );

  Future<String> save([EventDigest draft = birthdays]) async {
    final digest = await service.create(draft);
    return digest!.id;
  }

  setUp(() async {
    EventDigestService.reset();
    db = await openTestDatabase();
    service = await EventDigestService.forTesting(db);
  });

  tearDown(() async {
    EventDigestService.reset();
    await db.close();
  });

  test('a fresh database has no digests, and the facade agrees', () {
    expect(service.digests, isEmpty);
    expect(EventDigests.all, isEmpty);
  });

  test(
    'create assigns an id, trims the name and round-trips the rest',
    () async {
      final before = EventDigests.revision;

      final id = await save();

      expect(id, isNot('draft'));
      final digest = EventDigests.byId(id)!;
      expect(digest.name, 'Birthdays');
      expect(
        digest,
        birthdays.copyWith(id: id, name: 'Birthdays', sortOrder: 0),
      );
      expect(EventDigests.revision, greaterThan(before));
      expect(EventDigests.all, service.digests);
    },
  );

  test('digests append in save order', () async {
    await save(const EventDigest(id: 'x', name: 'First'));
    await save(const EventDigest(id: 'x', name: 'Second'));

    expect(EventDigests.all.map((d) => d.name), ['First', 'Second']);
    expect(EventDigests.all.map((d) => d.sortOrder), [0, 1]);
  });

  test('update rewrites in place, keeping the position', () async {
    await save(const EventDigest(id: 'x', name: 'First'));
    final id = await save(const EventDigest(id: 'x', name: 'Second'));

    await service.update(
      EventDigests.byId(id)!.copyWith(enabled: false, minute: 60),
    );

    final updated = EventDigests.byId(id)!;
    expect(updated.enabled, isFalse);
    expect(updated.minute, 60);
    expect(updated.sortOrder, 1);
    final row = await (db.select(
      db.eventDigests,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(row.version, 2);
    expect(row.enabled, isFalse);
  });

  test('delete leaves a tombstone, not a hole', () async {
    final id = await save();

    await service.delete(id);

    expect(service.digests, isEmpty);
    expect(EventDigests.byId(id), isNull);
    final row = await (db.select(
      db.eventDigests,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(row.isDeleted, isTrue);
    expect(row.version, 2);
    expect(await db.eventDigestDao.nextSortOrder(), 1);
  });

  group('reorder', () {
    test('the new order persists and survives a reload', () async {
      final a = await save(const EventDigest(id: 'x', name: 'A'));
      final b = await save(const EventDigest(id: 'x', name: 'B'));
      final c = await save(const EventDigest(id: 'x', name: 'C'));

      await service.reorder([c, a, b]);
      expect(EventDigests.all.map((d) => d.name), ['C', 'A', 'B']);

      await service.reload();
      expect(EventDigests.all.map((d) => d.name), ['C', 'A', 'B']);
      expect(EventDigests.all.map((d) => d.sortOrder), [0, 1, 2]);
    });

    test('racing reorders land in the order they were issued', () async {
      final a = await save(const EventDigest(id: 'x', name: 'A'));
      final b = await save(const EventDigest(id: 'x', name: 'B'));

      await Future.wait([
        service.reorder([b, a]),
        service.reorder([a, b]),
      ]);

      expect(EventDigests.all.map((d) => d.name), ['A', 'B']);
    });
  });

  test('create refuses at the cap', () async {
    for (var i = 0; i < kDigestHorizon.maxDigests; i++) {
      await save(EventDigest(id: 'x', name: 'Digest $i'));
    }

    expect(kDigestHorizon.maxDigests, 10);
    expect(service.isFull, isTrue);
    expect(await service.create(birthdays), isNull);
    expect(EventDigests.all, hasLength(kDigestHorizon.maxDigests));
  });

  test('a database switch drops the singleton and the facade', () async {
    await save();

    DatabaseLifecycle.notifyDatabaseSwitching();
    expect(EventDigests.all, isEmpty);

    final other = await openTestDatabase();
    addTearDown(other.close);
    final rebound = await EventDigestService.forTesting(other);
    expect(identical(rebound, service), isFalse);
    expect(rebound.digests, isEmpty);
  });

  test('racing first callers share one construction', () async {
    DatabaseLifecycle.notifyDatabaseSwitching();

    final first = EventDigestService.forTesting(db);
    final second = EventDigestService.forTesting(db);

    expect(identical(await first, await second), isTrue);
  });

  /// The `AlertScheduler` pass asking for the service while the user switches
  /// database. Without the in-flight guard the construction the switch
  /// overtook finishes against the closing database, publishes its digests
  /// and installs itself, so every later caller holds a dead handle: the hub
  /// lists nothing and every write throws until the next switch.
  test('a switch while the first construction is in flight discards it',
      () async {
    await save();
    final other = await openTestDatabase();
    addTearDown(other.close);
    DatabaseLifecycle.notifyDatabaseSwitching();

    final leaving = EventDigestService.forTesting(db);
    EventDigestService.reset();
    final arrived = await EventDigestService.forTesting(other);
    final discarded = await leaving;

    expect(
      identical(discarded, arrived),
      isTrue,
      reason: 'the construction the switch overtook must not be handed out',
    );
    expect(
      EventDigests.all,
      isEmpty,
      reason: "the closing database's digests must never be published",
    );
  });

  /// A sync pull landing during a switch, or a transient sqlite lock. An
  /// empty facade is not "no digests" to the reconcile that follows: it would
  /// cancel every armed digest on the platform and re-arm them under new os
  /// ids on the next healthy pass.
  test('a load that fails keeps the digests it had', () async {
    final id = await save();

    await db.close();
    await service.reload();

    expect(EventDigests.byId(id), isNotNull);
    expect(service.digests, hasLength(1));
  });

  /// C145: the restart published the replacement's cache unconditionally, so
  /// a replacement whose own load failed published the initial empty list —
  /// the facade the test above exists to prevent, one path over.
  test('a restart whose own load failed publishes nothing', () async {
    final id = await save();
    final standing = EventDigests.all;
    // Every read from here on fails, the replacement's included.
    await db.close();
    EventDigestService.reset();

    final leaving = EventDigestService.forTesting(db);
    // Overtaken past its `await open()`, so it discards itself and restarts;
    // and what its `_load` had published is still standing in the facade.
    EventDigestService.reset();
    EventDigests.updateCache(standing);
    await leaving;

    expect(EventDigests.byId(id), isNotNull);
    expect(EventDigests.all, standing);
  });

  /// The sheet is open on a digest the hub listed; a pull applies that
  /// digest's tombstone from another device. `upsertDigest` resurrects a
  /// tombstone by design, so without the refusal Save brings the digest back
  /// under a stamp that beats the remote tombstone for good — re-armed, and
  /// one over the planner's horizon, which then drops a digest from every
  /// pass.
  test('an edit of a tombstoned digest is refused', () async {
    final id = await save();
    await service.delete(id);
    final tombstone = await (db.select(
      db.eventDigests,
    )..where((t) => t.id.equals(id))).getSingle();

    await service.update(EventDigest(id: id, name: 'Back'));

    final row = await (db.select(
      db.eventDigests,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(row.isDeleted, isTrue);
    expect(row.version, tombstone.version);
    expect(EventDigests.byId(id), isNull);
  });

  group('backup', () {
    test('round-trips digests, the switch included', () async {
      final id = await save();
      await service.update(EventDigests.byId(id)!.copyWith(enabled: false));

      final exported = await service.exportData();
      expect(exported.single.keys, isNot(contains('hlcTimestamp')));
      await service.importData(exported);

      final restored = EventDigests.all.single;
      expect(restored.id, id);
      expect(restored.enabled, isFalse);
      expect(restored.cadence, DigestCadence.weekly);
      expect(restored.categoryIds, {'birthday'});
    });

    test('import replaces rather than merges', () async {
      await save();

      await service.importData([
        {
          'id': 'imported',
          'name': '',
          'payload': '{"cadence":"daily","minute":480}',
        },
      ]);

      final only = EventDigests.all.single;
      expect(only.id, 'imported');
      expect(only.cadence, DigestCadence.daily);
      expect(only.minute, 480);
      expect(only.enabled, isTrue, reason: 'an absent switch is on');
    });

    test('an unknown key survives a restore', () async {
      await service.importData([
        {
          'id': 'future',
          'name': 'From a newer build',
          'payload': '{"cadence":"weekly","anchor":3,"someFutureKey":"yes"}',
        },
      ]);

      final exported = await service.exportData();
      expect(exported.single['payload'], contains('someFutureKey'));
      expect(EventDigests.all.single.anchor, 3);
    });

    test(
      'a malformed row is skipped and an unparseable payload kept',
      () async {
        await service.importData([
          'not a map',
          {'name': 'No id'},
          {'id': 'broken', 'name': 'Broken', 'payload': 'not json'},
        ]);

        final only = EventDigests.all.single;
        expect(only.name, 'Broken');
        expect(only.cadence, DigestCadence.monthly);
        expect(only.anchor, 1);
        expect(only.enabled, isFalse, reason: 'nothing arms an unread row');
      },
    );

    test('a row with no payload imports disabled', () async {
      await service.importData([
        {'id': 'bare', 'name': 'Bare', 'enabled': true},
      ]);

      final only = EventDigests.all.single;
      expect(only.id, 'bare');
      expect(only.enabled, isFalse);
    });
  });
}
