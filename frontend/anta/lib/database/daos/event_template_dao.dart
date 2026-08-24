import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/event_templates_table.dart';

part 'event_template_dao.g.dart';

/// All CRDT stamping for `calendar_event_templates` lives here, never in the
/// service: `db.generateHlc()`, `db.deviceId` and read-then-write
/// `version + 1`, the [NoteDao] idiom.
@DriftAccessor(tables: [EventTemplates])
class EventTemplateDao extends DatabaseAccessor<AppDatabase>
    with _$EventTemplateDaoMixin {
  EventTemplateDao(super.db);

  /// Live templates in display order. Tombstones stay below the service's
  /// waterline — they exist for a future merge, not for anything the app
  /// renders. Ordered by `id` after `sort_order` so two templates that were
  /// created in the same millisecond still list deterministically.
  Future<List<EventTemplateRow>> getAll() {
    return (select(eventTemplates)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([
            (t) => OrderingTerm(expression: t.sortOrder),
            (t) => OrderingTerm(expression: t.id),
          ]))
        .get();
  }

  /// Inserts a new template or updates an existing one in place.
  ///
  /// [entry] must carry every non-default column the caller means to set;
  /// identity is always stamped here. An update bumps `version` from the
  /// stored row and leaves `created_at` alone, so editing a template keeps the
  /// date it was made. A tombstoned row is resurrected rather than duplicated —
  /// ids are caller-supplied, and a re-imported id must not collide.
  Future<void> upsertTemplate(EventTemplatesCompanion entry) {
    return transaction(() async {
      final id = entry.id.value;
      final existing = await _byId(id);
      final now = DateTime.now();
      final hlc = db.generateHlc();

      if (existing == null) {
        await into(eventTemplates).insert(
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

      await (update(eventTemplates)..where((t) => t.id.equals(id))).write(
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

  /// Soft-deletes a template, the [NoteDao.softDeleteNote] shape: the row
  /// survives as a tombstone so the delete carries an order once devices
  /// merge. A missing or already-tombstoned row is a no-op.
  Future<void> softDeleteById(String id) {
    return transaction(() async {
      final existing = await _byId(id);
      if (existing == null || existing.isDeleted) return;

      final now = DateTime.now();
      await (update(eventTemplates)..where((t) => t.id.equals(id))).write(
        EventTemplatesCompanion(
          isDeleted: const Value(true),
          deletedAt: Value(now),
          updatedAt: Value(now),
          hlcTimestamp: Value(db.generateHlc()),
          deviceId: Value(db.deviceId),
          version: Value(existing.version + 1),
        ),
      );
    });
  }

  /// Next free display position. Tombstones count: reusing a dead template's
  /// slot would reorder the list if that template is ever resurrected.
  Future<int> nextSortOrder() async {
    final row = await customSelect(
      'SELECT COALESCE(MAX(sort_order), -1) AS max_order '
      'FROM calendar_event_templates',
      readsFrom: {eventTemplates},
    ).getSingle();
    return row.read<int>('max_order') + 1;
  }

  /// Inserts a template while preserving externally-provided audit fields, the
  /// [NoteDao.importNote] convention: `createdAt`/`updatedAt` come from the
  /// caller, identity is stamped **fresh**. A backup is not a sync channel, so
  /// a restored template is this device's own live row, never a replayed one.
  /// Takes the whole archive at once (**5.1**): one batched transaction and one
  /// commit, where this was a separate awaited insert — and so a separate WAL
  /// commit — per restored template. See [CalendarEventDao.importAll] for why
  /// `insertOrReplace` is the safe mode here.
  Future<void> importAll(List<EventTemplatesCompanion> entries) {
    if (entries.isEmpty) return Future.value();
    return batch((b) {
      for (final entry in entries) {
        b.insert(
          eventTemplates,
          entry.copyWith(
            hlcTimestamp: Value(db.generateHlc()),
            deviceId: Value(db.deviceId),
            version: const Value(1),
            isDeleted: const Value(false),
            deletedAt: const Value(null),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  /// The **hard** wipe, tombstones included. Used by the import path, where no
  /// parent survives to merge against and a tombstone would strand a row no
  /// surface can reach.
  Future<void> deleteAll() {
    return delete(eventTemplates).go();
  }

  Future<EventTemplateRow?> _byId(String id) {
    return (select(
      eventTemplates,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }
}
