import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database.dart';
import '../tables/vocabularies_table.dart';
import '../tables/vocabulary_items_table.dart';

part 'vocabulary_dao.g.dart';

/// All CRDT stamping for `vocabularies` and `vocabulary_items` lives here,
/// never in the service: `db.generateHlc()`, `db.deviceId` and read-then-write
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
      final now = DateTime.now();
      final hlc = db.generateHlc();

      if (existing == null) {
        await into(vocabularies).insert(
          entry.copyWith(
            createdAt: entry.createdAt.present ? entry.createdAt : Value(now),
            updatedAt: Value(now),
            hlcTimestamp: Value(hlc),
            deviceId: Value(db.deviceId),
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
          hlcTimestamp: Value(hlc),
          deviceId: Value(db.deviceId),
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
  Future<void> saveItems({
    required String vocabularyId,
    required List<String> terms,
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
      final kept = <String>{};
      final seen = <String>{};
      var position = 0;

      for (final term in terms) {
        if (!seen.add(term)) continue;
        final row = byTerm[term];
        final sortOrder = position++;

        if (row == null) {
          await into(vocabularyItems).insert(
            VocabularyItemsCompanion.insert(
              id: _uuid.v4(),
              vocabularyId: vocabularyId,
              term: term,
              sortOrder: Value(sortOrder),
              createdAt: now,
              updatedAt: now,
              hlcTimestamp: db.generateHlc(),
              deviceId: db.deviceId,
            ),
          );
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
            hlcTimestamp: Value(db.generateHlc()),
            deviceId: Value(db.deviceId),
            version: Value(row.version + 1),
            isDeleted: const Value(false),
            deletedAt: const Value(null),
          ),
        );
      }

      for (final row in existing) {
        if (row.isDeleted || kept.contains(row.id)) continue;
        await _tombstoneItem(row, now);
      }
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
      await (update(vocabularies)..where((t) => t.id.equals(id))).write(
        VocabulariesCompanion(
          isDeleted: const Value(true),
          deletedAt: Value(now),
          updatedAt: Value(now),
          hlcTimestamp: Value(db.generateHlc()),
          deviceId: Value(db.deviceId),
          version: Value(existing.version + 1),
        ),
      );

      final items =
          await (select(vocabularyItems)..where(
                (t) => t.vocabularyId.equals(id) & t.isDeleted.equals(false),
              ))
              .get();
      for (final item in items) {
        await _tombstoneItem(item, now);
      }
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
            hlcTimestamp: Value(db.generateHlc()),
            deviceId: Value(db.deviceId),
            version: Value(existing.version + 1),
          ),
        );
      }
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
  /// a restored row is this device's own live row, never a replayed one.
  Future<void> importVocabulary(VocabulariesCompanion entry) {
    return into(vocabularies).insert(
      entry.copyWith(
        hlcTimestamp: Value(db.generateHlc()),
        deviceId: Value(db.deviceId),
        version: const Value(1),
        isDeleted: const Value(false),
        deletedAt: const Value(null),
      ),
    );
  }

  Future<void> importItem(VocabularyItemsCompanion entry) {
    return into(vocabularyItems).insert(
      entry.copyWith(
        hlcTimestamp: Value(db.generateHlc()),
        deviceId: Value(db.deviceId),
        version: const Value(1),
        isDeleted: const Value(false),
        deletedAt: const Value(null),
      ),
    );
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

  Future<void> _tombstoneItem(VocabularyItemRow row, DateTime now) {
    return (update(vocabularyItems)..where((t) => t.id.equals(row.id))).write(
      VocabularyItemsCompanion(
        isDeleted: const Value(true),
        deletedAt: Value(now),
        updatedAt: Value(now),
        hlcTimestamp: Value(db.generateHlc()),
        deviceId: Value(db.deviceId),
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
