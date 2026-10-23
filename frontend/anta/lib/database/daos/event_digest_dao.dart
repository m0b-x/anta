import 'package:drift/drift.dart';

import '../crdt/crdt_write.dart';
import '../database.dart';
import '../tables/event_digests_table.dart';

part 'event_digest_dao.g.dart';

/// All CRDT stamping for `event_digests` lives here, never in the service —
/// [OverviewViewDao] cloned, so the saved-list tables behave alike under a
/// future merge, the outbox included (**v43**).
@DriftAccessor(tables: [EventDigests])
class EventDigestDao extends DatabaseAccessor<AppDatabase>
    with _$EventDigestDaoMixin {
  EventDigestDao(super.db);

  /// Live digests in display order, tie-broken on `id` so two digests saved in
  /// the same millisecond still list deterministically.
  Future<List<EventDigestRow>> getAll() {
    return (select(eventDigests)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([
            (t) => OrderingTerm(expression: t.sortOrder),
            (t) => OrderingTerm(expression: t.id),
          ]))
        .get();
  }

  /// Inserts a new digest or updates an existing one in place — a version
  /// bump from the stored row, `created_at` left alone, a tombstone
  /// resurrected rather than duplicated ([OverviewViewDao.upsertView]), an
  /// unchanged save of a live digest not written at all.
  Future<void> upsertDigest(EventDigestsCompanion entry) {
    return transaction(() async {
      final id = entry.id.value;
      final existing = await _byId(id);
      final now = DateTime.now();

      if (existing == null) {
        final stamp = await db.stampLocal(eventDigests, id);
        await into(eventDigests).insert(
          entry.copyWith(
            createdAt: entry.createdAt.present ? entry.createdAt : Value(now),
            updatedAt: Value(now),
            hlcTimestamp: Value(stamp.hlc),
            deviceId: Value(stamp.deviceId),
            version: const Value(1),
            isDeleted: const Value(false),
            deletedAt: const Value(null),
          ),
        );
        return;
      }

      if (!existing.isDeleted && db.changesNothing(existing, entry)) return;
      final stamp = await db.stampLocal(eventDigests, id);
      await (update(eventDigests)..where((t) => t.id.equals(id))).write(
        entry.copyWith(
          createdAt: const Value.absent(),
          updatedAt: Value(now),
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: Value(existing.version + 1),
          isDeleted: const Value(false),
          deletedAt: const Value(null),
        ),
      );
    });
  }

  /// Writes the `enabled` column alone, with the CRDT stamps — never the
  /// payload, so the hub's switch cannot re-encode a digest this build reads
  /// only in part (a newer build's fields would be lost). A missing row, a
  /// tombstone, or the value already stored is a no-op: an unchanged write
  /// must not bump `version` and win a merge over a real edit elsewhere.
  Future<void> setEnabled(String id, bool enabled) {
    return transaction(() async {
      final existing = await _byId(id);
      if (existing == null ||
          existing.isDeleted ||
          existing.enabled == enabled) {
        return;
      }
      final stamp = await db.stampLocal(eventDigests, id);
      await (update(eventDigests)..where((t) => t.id.equals(id))).write(
        EventDigestsCompanion(
          enabled: Value(enabled),
          updatedAt: Value(DateTime.now()),
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: Value(existing.version + 1),
        ),
      );
    });
  }

  /// Soft-deletes a digest so the delete carries an order once devices merge.
  /// A missing or already-tombstoned row is a no-op.
  Future<void> softDeleteById(String id) {
    return transaction(() async {
      final existing = await _byId(id);
      if (existing == null || existing.isDeleted) return;

      final now = DateTime.now();
      final stamp = await db.stampLocal(
        eventDigests,
        id,
        op: OutboxOp.tombstone,
      );
      await (update(eventDigests)..where((t) => t.id.equals(id))).write(
        EventDigestsCompanion(
          isDeleted: const Value(true),
          deletedAt: Value(now),
          updatedAt: Value(now),
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: Value(existing.version + 1),
        ),
      );
    });
  }

  /// Next free display position. Tombstones count: reusing a dead digest's
  /// slot would reorder the list if that digest is ever resurrected.
  Future<int> nextSortOrder() async {
    final row = await customSelect(
      'SELECT COALESCE(MAX(sort_order), -1) AS max_order FROM event_digests',
      readsFrom: {eventDigests},
    ).getSingle();
    return row.read<int>('max_order') + 1;
  }

  /// Rewrites `sort_order` to a dense `0..N-1` matching [idsInOrder] in one
  /// transaction of `UPDATE`s and no reads — [OverviewViewDao.reorder]'s
  /// contract: `version + 1` in SQL, a row already in place left alone, a
  /// tombstone or an unknown id untouched, and only the rows it moved queued.
  Future<void> reorder(List<String> idsInOrder) async {
    if (idsInOrder.isEmpty) return;
    final now = DateTime.now();

    await transaction(() async {
      final stamp = db.newStamp();
      final moved = <String>[];
      for (var i = 0; i < idsInOrder.length; i++) {
        final changed = await customUpdate(
          'UPDATE event_digests SET sort_order = ?, updated_at = ?, '
          'hlc_timestamp = ?, device_id = ?, version = version + 1 '
          'WHERE id = ? AND is_deleted = 0 AND sort_order != ?',
          variables: [
            Variable<int>(i),
            Variable<DateTime>(now),
            Variable<String>(stamp.hlc),
            Variable<String>(stamp.deviceId),
            Variable<String>(idsInOrder[i]),
            Variable<int>(i),
          ],
          updates: {eventDigests},
        );
        if (changed > 0) moved.add(idsInOrder[i]);
      }
      await db.enqueueMany(eventDigests, moved, stamp.hlc);
    });
  }

  /// Inserts digests while preserving the caller's audit fields; identity is
  /// stamped **fresh** — a backup is not a sync channel. One batch for the
  /// whole archive, each row queued in it as any new local row is.
  Future<void> importAll(List<EventDigestsCompanion> entries) {
    if (entries.isEmpty) return Future.value();
    return transaction(() async {
      final stamps = [for (final _ in entries) db.newStamp()];
      await batch((b) {
        for (var i = 0; i < entries.length; i++) {
          final entry = entries[i];
          final stamp = stamps[i];
          b.insert(
            eventDigests,
            entry.copyWith(
              hlcTimestamp: Value(stamp.hlc),
              deviceId: Value(stamp.deviceId),
              version: const Value(1),
              isDeleted: const Value(false),
              deletedAt: const Value(null),
            ),
            mode: InsertMode.insertOrReplace,
          );
          db.enqueueIn(b, eventDigests, entry.id.value, stamp.hlc);
        }
      });
    });
  }

  /// The **hard** wipe, tombstones included, for the import path.
  Future<void> deleteAll() {
    return delete(eventDigests).go();
  }

  Future<EventDigestRow?> _byId(String id) {
    return (select(
      eventDigests,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }
}
