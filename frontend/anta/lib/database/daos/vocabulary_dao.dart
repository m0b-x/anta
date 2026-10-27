import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../crdt/crdt_merge.dart';
import '../crdt/crdt_write.dart';
import '../crdt/merge_outcome.dart';
import '../database.dart';
import '../tables/vocabularies_table.dart';
import '../tables/vocabulary_items_table.dart';

part 'vocabulary_dao.g.dart';

/// All CRDT stamping for `vocabularies` and `vocabulary_items` lives here,
/// never in the service: a `CrdtWrite` stamp and read-then-write
/// `version + 1`, the [NoteDao] idiom.
@DriftAccessor(tables: [Vocabularies, VocabularyItems])
class VocabularyDao extends DatabaseAccessor<AppDatabase>
    with _$VocabularyDaoMixin {
  VocabularyDao(super.db);

  static const _uuid = Uuid();

  /// Live vocabularies in display order. Tombstones stay below the service's
  /// waterline — they exist for a future merge, not for anything the app
  /// renders. Ordered by `id` after `sort_order` so two rows created in the
  /// same millisecond still list deterministically.
  Future<List<VocabularyRow>> getAllVocabularies() {
    return (select(vocabularies)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([
            (t) => OrderingTerm(expression: t.sortOrder),
            (t) => OrderingTerm(expression: t.id),
          ]))
        .get();
  }

  /// Every live term across every vocabulary, in the order the suggestion bar
  /// should rank ties. Read once into `Vocabularies`' static facade, so the
  /// per-keystroke editor path never awaits.
  Future<List<VocabularyItemRow>> getAllItems() {
    return (select(vocabularyItems)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([
            (t) => OrderingTerm(expression: t.sortOrder),
            (t) => OrderingTerm(expression: t.id),
          ]))
        .get();
  }

  /// Inserts a new vocabulary or updates an existing one in place.
  ///
  /// An update bumps `version` from the stored row and leaves `created_at`
  /// alone. A tombstoned row is resurrected rather than duplicated — ids are
  /// caller-supplied, and a re-imported id must not collide.
  Future<void> upsertVocabulary(VocabulariesCompanion entry) {
    return transaction(() async {
      final id = entry.id.value;
      final existing = await _vocabularyById(id);
      // A live row the entry would not change is left alone, so a save of an
      // unchanged list does not read as a change once devices merge.
      if (existing != null && !existing.isDeleted) {
        final merged = existing.copyWithCompanion(entry);
        final unchanged = merged.copyWith(
          createdAt: existing.createdAt,
          updatedAt: existing.updatedAt,
        );
        if (unchanged == existing) return;
      }
      final now = DateTime.now();
      final stamp = await db.stampLocal(vocabularies, id);

      if (existing == null) {
        await into(vocabularies).insert(
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

      await (update(vocabularies)..where((t) => t.id.equals(id))).write(
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

  /// Replaces a vocabulary's term list with [terms], preserving identity.
  ///
  /// The management UI edits the whole list as one block of lines, so the write
  /// is a diff rather than a wipe: a term that is still present keeps its row,
  /// its `id` and its `created_at`; a new term inserts; a term that disappeared
  /// is tombstoned; a term that comes back resurrects the row it had before.
  /// Only rows that actually changed are written, so re-saving an untouched
  /// list issues no `UPDATE`s and bumps no versions.
  ///
  /// [terms] is expected to be trimmed, blank-free and duplicate-free — the
  /// service owns that normalization. A repeat is skipped rather than mapped
  /// onto the same row twice.
  ///
  /// [snapshot] is the term list the caller started from. A live row whose
  /// term is in neither list arrived *after* that snapshot — a pull merged
  /// the term another device added while the editor was open — so it is kept
  /// instead of tombstoned: the user never saw the term, so its absence from
  /// [terms] is not a deletion, and tombstoning it would push the term's
  /// removal to every device (A1b review R23). A caller that passes nothing
  /// replaces the list outright, which is what a fresh vocabulary does.
  ///
  /// A *duplicate* of a term that is still listed — the merge-created pair the
  /// phase record §8 accepts — is tombstoned as before: the term stays, only
  /// its second row goes.
  Future<void> saveItems({
    required String vocabularyId,
    required List<String> terms,
    List<String>? snapshot,
  }) {
    return transaction(() async {
      final existing = await (select(
        vocabularyItems,
      )..where((t) => t.vocabularyId.equals(vocabularyId))).get();

      final byTerm = <String, VocabularyItemRow>{};
      for (final row in existing) {
        final previous = byTerm[row.term];
        if (previous == null || (previous.isDeleted && !row.isDeleted)) {
          byTerm[row.term] = row;
        }
      }

      final now = DateTime.now();
      final stamp = db.newStamp();
      final kept = <String>{};
      final seen = <String>{};
      final written = <String>[];
      final tombstoned = <String>[];
      var position = 0;

      for (final term in terms) {
        if (!seen.add(term)) continue;
        final row = byTerm[term];
        final sortOrder = position++;

        if (row == null) {
          final id = _uuid.v4();
          await into(vocabularyItems).insert(
            VocabularyItemsCompanion.insert(
              id: id,
              vocabularyId: vocabularyId,
              term: term,
              sortOrder: Value(sortOrder),
              createdAt: now,
              updatedAt: now,
              hlcTimestamp: stamp.hlc,
              deviceId: stamp.deviceId,
            ),
          );
          written.add(id);
          continue;
        }

        kept.add(row.id);
        if (!row.isDeleted && row.sortOrder == sortOrder) continue;

        await (update(
          vocabularyItems,
        )..where((t) => t.id.equals(row.id))).write(
          VocabularyItemsCompanion(
            sortOrder: Value(sortOrder),
            updatedAt: Value(now),
            hlcTimestamp: Value(stamp.hlc),
            deviceId: Value(stamp.deviceId),
            version: Value(row.version + 1),
            isDeleted: const Value(false),
            deletedAt: const Value(null),
          ),
        );
        written.add(row.id);
      }

      final known = snapshot?.toSet();
      for (final row in existing) {
        if (row.isDeleted || kept.contains(row.id)) continue;
        if (known != null &&
            !known.contains(row.term) &&
            !seen.contains(row.term)) {
          continue;
        }
        await _tombstoneItem(row, now, stamp);
        tombstoned.add(row.id);
      }

      await db.enqueueMany(vocabularyItems, written, stamp.hlc);
      await db.enqueueMany(
        vocabularyItems,
        tombstoned,
        stamp.hlc,
        op: OutboxOp.tombstone,
      );
    });
  }

  /// Soft-deletes a vocabulary and every term inside it, the
  /// [NoteDao.softDeleteNote] shape: the rows survive as tombstones so the
  /// delete carries an order once devices merge. A missing or already-
  /// tombstoned vocabulary is a no-op.
  Future<void> softDeleteVocabularyById(String id) {
    return transaction(() async {
      final existing = await _vocabularyById(id);
      if (existing == null || existing.isDeleted) return;

      final now = DateTime.now();
      final stamp = await db.stampLocal(
        vocabularies,
        id,
        op: OutboxOp.tombstone,
      );
      await (update(vocabularies)..where((t) => t.id.equals(id))).write(
        VocabulariesCompanion(
          isDeleted: const Value(true),
          deletedAt: Value(now),
          updatedAt: Value(now),
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: Value(existing.version + 1),
        ),
      );

      final items =
          await (select(vocabularyItems)..where(
                (t) => t.vocabularyId.equals(id) & t.isDeleted.equals(false),
              ))
              .get();
      for (final item in items) {
        await _tombstoneItem(item, now, stamp);
      }
      await db.enqueueMany(
        vocabularyItems,
        [for (final item in items) item.id],
        stamp.hlc,
        op: OutboxOp.tombstone,
      );
    });
  }

  /// Rewrites display order to match [orderedIds], in one transaction.
  ///
  /// Vocabulary order is not cosmetic: it is the tie-break the suggestion bar
  /// ranks by, so the list the user drags to the top wins ties everywhere.
  /// Rows whose position did not change are left alone.
  Future<void> reorderVocabularies(List<String> orderedIds) {
    return transaction(() async {
      final now = DateTime.now();
      final stamp = db.newStamp();
      final moved = <String>[];
      for (var i = 0; i < orderedIds.length; i++) {
        final existing = await _vocabularyById(orderedIds[i]);
        if (existing == null || existing.isDeleted) continue;
        if (existing.sortOrder == i) continue;

        await (update(
          vocabularies,
        )..where((t) => t.id.equals(existing.id))).write(
          VocabulariesCompanion(
            sortOrder: Value(i),
            updatedAt: Value(now),
            hlcTimestamp: Value(stamp.hlc),
            deviceId: Value(stamp.deviceId),
            version: Value(existing.version + 1),
          ),
        );
        moved.add(existing.id);
      }
      await db.enqueueMany(vocabularies, moved, stamp.hlc);
    });
  }

  /// Next free display position. Tombstones count: reusing a dead
  /// vocabulary's slot would reorder the list if that row is ever resurrected.
  Future<int> nextSortOrder() async {
    final row = await customSelect(
      'SELECT COALESCE(MAX(sort_order), -1) AS max_order FROM vocabularies',
      readsFrom: {vocabularies},
    ).getSingle();
    return row.read<int>('max_order') + 1;
  }

  /// Inserts a vocabulary while preserving externally-provided audit fields,
  /// the [NoteDao.importNote] convention: `createdAt`/`updatedAt` come from the
  /// caller, identity is stamped **fresh**. A backup is not a sync channel, so
  /// a restored row is this device's own live row, never a replayed one, and
  /// it is queued like one.
  Future<void> importVocabulary(VocabulariesCompanion entry) {
    return transaction(() async {
      final stamp = await db.stampLocal(vocabularies, entry.id.value);
      await into(vocabularies).insert(
        entry.copyWith(
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: const Value(1),
          isDeleted: const Value(false),
          deletedAt: const Value(null),
        ),
      );
    });
  }

  Future<void> importItem(VocabularyItemsCompanion entry) {
    return transaction(() async {
      final stamp = await db.stampLocal(vocabularyItems, entry.id.value);
      await into(vocabularyItems).insert(
        entry.copyWith(
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: const Value(1),
          isDeleted: const Value(false),
          deletedAt: const Value(null),
        ),
      );
    });
  }

  /// The vocabularies under [ids], tombstones included: the sync push sends
  /// the tombstone a delete queued, so it reads past the live-row filter.
  Future<List<VocabularyRow>> getVocabulariesByIdsIncludingDeleted(
    List<String> ids,
  ) {
    return CrdtMerge.loadInChunks(
      ids,
      (chunk) => (select(vocabularies)..where((t) => t.id.isIn(chunk))).get(),
    );
  }

  /// The terms under [ids], tombstones included, for the same reason.
  Future<List<VocabularyItemRow>> getItemsByIdsIncludingDeleted(
    List<String> ids,
  ) {
    return CrdtMerge.loadInChunks(
      ids,
      (chunk) =>
          (select(vocabularyItems)..where((t) => t.id.isIn(chunk))).get(),
    );
  }

  /// Merges one remote vocabulary on the contract of
  /// [CrdtMerge.mergeRemoteRow]. A tombstone carries no data, so over a local
  /// row it writes the stamps, the deletion and the owner and keeps the rest;
  /// its items arrive as their own rows, never by cascade.
  Future<MergeOutcome> mergeRemoteVocabulary(
    VocabularyRow remote, {
    String? floor,
  }) {
    return transaction(() async {
      final local = await _vocabularyById(remote.id);
      return CrdtMerge.mergeRemoteRow(
        db,
        table: vocabularies,
        rowKey: remote.id,
        remoteHlc: remote.hlcTimestamp,
        localHlc: local?.hlcTimestamp,
        floor: floor,
        insert: () => into(vocabularies).insert(remote),
        overwrite: (applied) async {
          if (remote.isDeleted) {
            await (update(
              vocabularies,
            )..where((t) => t.id.equals(remote.id))).write(
              VocabulariesCompanion(
                hlcTimestamp: Value(remote.hlcTimestamp),
                deviceId: Value(remote.deviceId),
                version: Value(remote.version),
                isDeleted: const Value(true),
                deletedAt: Value(remote.deletedAt),
                ownerId: Value(remote.ownerId),
              ),
            );
          } else {
            await update(vocabularies).replace(remote);
          }
          return applied;
        },
      );
    });
  }

  /// Merges one remote term on the contract of [CrdtMerge.mergeRemoteRow],
  /// stored as received even under a vocabulary tombstoned here: the parent's
  /// tombstone is its own row, and `VocabularyService` lists terms only
  /// under the live vocabularies it reads.
  Future<MergeOutcome> mergeRemoteVocabularyItem(
    VocabularyItemRow remote, {
    String? floor,
  }) {
    return transaction(() async {
      final local = await (select(
        vocabularyItems,
      )..where((t) => t.id.equals(remote.id))).getSingleOrNull();
      return CrdtMerge.mergeRemoteRow(
        db,
        table: vocabularyItems,
        rowKey: remote.id,
        remoteHlc: remote.hlcTimestamp,
        localHlc: local?.hlcTimestamp,
        floor: floor,
        insert: () => into(vocabularyItems).insert(remote),
        overwrite: (applied) async {
          if (remote.isDeleted) {
            await (update(
              vocabularyItems,
            )..where((t) => t.id.equals(remote.id))).write(
              VocabularyItemsCompanion(
                hlcTimestamp: Value(remote.hlcTimestamp),
                deviceId: Value(remote.deviceId),
                version: Value(remote.version),
                isDeleted: const Value(true),
                deletedAt: Value(remote.deletedAt),
                ownerId: Value(remote.ownerId),
              ),
            );
          } else {
            await update(vocabularyItems).replace(remote);
          }
          return applied;
        },
      );
    });
  }

  /// The **hard** wipe, tombstones included. Used by the import path, where no
  /// parent survives to merge against and a tombstone would strand a row no
  /// surface can reach.
  Future<void> deleteAll() {
    return transaction(() async {
      await delete(vocabularyItems).go();
      await delete(vocabularies).go();
    });
  }

  /// Writes the tombstone only; the caller queues every row it tombstoned in
  /// one [CrdtWrite.enqueueMany].
  Future<void> _tombstoneItem(
    VocabularyItemRow row,
    DateTime now,
    CrdtStamp stamp,
  ) {
    return (update(vocabularyItems)..where((t) => t.id.equals(row.id))).write(
      VocabularyItemsCompanion(
        isDeleted: const Value(true),
        deletedAt: Value(now),
        updatedAt: Value(now),
        hlcTimestamp: Value(stamp.hlc),
        deviceId: Value(stamp.deviceId),
        version: Value(row.version + 1),
      ),
    );
  }

  Future<VocabularyRow?> _vocabularyById(String id) {
    return (select(
      vocabularies,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }
}
