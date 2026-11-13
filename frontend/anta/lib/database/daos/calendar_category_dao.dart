import 'package:drift/drift.dart';

import '../../models/calendar_event.dart'
    show CalendarEventCategory, kFallbackCategoryId;
import '../../models/category_delete_impact.dart';
import '../crdt/crdt_merge.dart';
import '../crdt/crdt_write.dart';
import '../crdt/merge_outcome.dart';
import '../database.dart';
import '../tables/calendar_categories_table.dart';
import 'sync_dao.dart';

part 'calendar_category_dao.g.dart';

/// All CRDT stamping for `calendar_categories` lives here (**v43**), the
/// [CalendarEventDao] rule: nothing above this class — `CategoryService`, the
/// `CalendarCategories` facade, backup — sees a CRDT field or a tombstone.
@DriftAccessor(tables: [CalendarCategories])
class CalendarCategoryDao extends DatabaseAccessor<AppDatabase>
    with _$CalendarCategoryDaoMixin {
  CalendarCategoryDao(super.db);

  /// The live-row predicate every read restates, spelled exactly as
  /// `idx_calendar_categories_active`'s `WHERE`. A literal rather than
  /// `isDeleted.equals(false)`, whose bound parameter the SQLite shipping to
  /// Android does not prove implies the index's predicate.
  static const _live = CustomExpression<bool>('is_deleted = 0');

  /// Whether a row is another account's, the one this database reads shared
  /// rows from: read beside the row, never as a statement apart.
  static const _partners = CustomExpression<bool>(
    "owner_id = (SELECT value FROM sync_metadata "
    "WHERE key = '${SyncDao.keySharedOwner}')",
  );

  /// The built-in ids: every `CalendarEventCategory` name, the seeds'
  /// `id => kind.name`, `kFallbackCategoryId` among them.
  static final builtInIds = {
    for (final kind in CalendarEventCategory.values) kind.name,
  };

  Future<List<CalendarCategoryRow>> getAll() {
    return (select(calendarCategories)
          ..where((c) => _live)
          ..orderBy([
            (c) => OrderingTerm.asc(c.sortOrder),
            (c) => OrderingTerm.asc(c.id),
          ]))
        .get();
  }

  /// Seeds the built-in catalog: insert-if-not-exists for every entry, so a
  /// user's edits to a built-in's colour, icon, order or archive flag are
  /// never clobbered on a later launch.
  ///
  /// One read of the seeded ids, then at most one `batch` — rather than one
  /// awaited insert per seed. This runs on the first
  /// `CategoryService.getInstance()` of a session and again after every backup
  /// import, and `injection.dart` already records the nine-statement version
  /// as part of why the calendar services left the pre-`runApp` path.
  ///
  /// A missing built-in is inserted under [CrdtWrite.seedStamp], the stamp
  /// every device seeds alike, never under one minted now: a fresh device's
  /// seed stamped now would beat another device's older rename or hidden
  /// flag by last-writer-wins on both devices once the bind floor stops
  /// covering it (review F-2). Because every seeded row carries that one
  /// stamp, the rows this call writes are learned by the read rather than by
  /// their stamp — matching on it would queue every untouched built-in again
  /// on every launch. A launch with nothing to seed writes and queues
  /// nothing.
  ///
  /// The one existing row that is written is a **tombstoned** built-in,
  /// resurrected — keeping the user's last edits, flagged built-in again —
  /// rather than ignored, under a minted stamp: it is this device's decision
  /// against the tombstone, so it must outrank what it revives. Built-ins are
  /// undeletable, but a tombstone can still arrive (a merge, or a row an
  /// older archive restored as custom), and ignoring it would hide that
  /// built-in for good, `other` — the fallback every orphaned event resolves
  /// to — included. It comes back private: a delete ends the grant for good,
  /// so the mark the tombstone kept is cleared under the revival's stamp,
  /// which every device's merge of the mark then takes (as
  /// [mergeRemoteCategory] does for a tombstone a merge revives).
  ///
  /// A row another account shares under a built-in's id is the partner's,
  /// stored by an older build before that id was a built-in here, and is
  /// taken out first (`SharedRowDao.evict`): the person's own built-in
  /// comes first, as every other row of theirs does. Told in the one read
  /// of the seeded ids, so a launch with nothing to evict asks nothing more.
  Future<void> seedMissing(List<CalendarCategoriesCompanion> entries) {
    if (entries.isEmpty) return Future.value();
    return transaction(() async {
      final table = calendarCategories;
      final rows =
          await (selectOnly(table)
                ..addColumns([table.id, table.isDeleted, _partners])
                ..where(
                  table.id.isIn([for (final entry in entries) entry.id.value]),
                ))
              .get();
      final stored = <String, bool>{
        for (final row in rows) row.read(table.id)!: row.read(table.isDeleted)!,
      };
      final theirs = [
        for (final row in rows)
          if (row.read(_partners) ?? false) row.read(table.id)!,
      ];
      if (theirs.isNotEmpty) {
        final evicted = await db.sharedRowDao.evict(
          table.actualTableName,
          theirs,
        );
        evicted.keysOf(table.actualTableName).forEach(stored.remove);
      }
      final missing = [
        for (final entry in entries)
          if (!stored.containsKey(entry.id.value)) entry,
      ];
      final tombstoned = [
        for (final entry in entries)
          if (stored[entry.id.value] ?? false) entry.id.value,
      ];
      if (missing.isEmpty && tombstoned.isEmpty) return;
      final seed = db.seedStamp();
      final revived = tombstoned.isEmpty ? null : db.newStamp();
      await batch((b) {
        for (final entry in missing) {
          b.insert(
            table,
            entry.copyWith(
              hlcTimestamp: Value(seed.hlc),
              deviceId: Value(seed.deviceId),
              version: const Value(1),
            ),
            onConflict: DoNothing(),
          );
          db.enqueueIn(b, table, entry.id.value, seed.hlc);
        }
        for (final id in tombstoned) {
          b.update(
            table,
            CalendarCategoriesCompanion.custom(
              isBuiltIn: const Constant(true),
              isDeleted: const Constant(false),
              deletedAt: const Constant<DateTime>(null),
              hlcTimestamp: Variable<String>(revived!.hlc),
              deviceId: Variable<String>(revived.deviceId),
              version: table.version + const Constant(1),
              sharedPair: const Constant<String>(null),
              sharedStamp: Variable<String>(revived.hlc),
            ),
            where: (c) => c.id.equals(id) & c.isDeleted,
          );
          db.enqueueIn(b, table, id, revived.hlc);
        }
      });
    });
  }

  /// Restores a backup's rows in one `batch` — the shape
  /// `EventTemplateDao.importAll` established: parsed first, written once, so
  /// a restore costs one commit rather than one per archived category, and a
  /// row that fails to parse cannot leave the table half-written.
  ///
  /// `insertOrReplace` because `CategoryService.importData` wipes the table
  /// first: an archive carrying the same id twice must cost the duplicate,
  /// never the whole restore.
  ///
  /// Rows arrive as live `version 1` originals of this device, the
  /// [CalendarEventDao.importAll] convention: a restore is never a merge. Each
  /// is queued in the same batch, as any new local row is.
  ///
  /// A defence, not the path production takes: a restore unbinds the
  /// database first (`BackupService`), and the unbind removes every shared
  /// row (`SharedRowDao.removeAll`), so no partner's category is here when
  /// this runs. Were one left, the archive's row under its id — two accounts
  /// that restored one backup hold the same ids — is the person's own and
  /// comes first, so the partner's copy is taken out before the insert
  /// (`SharedRowDao.evict`), the shape of [CalendarEventDao.importAll]: a
  /// replace fires no delete trigger and would remove it past the fences.
  /// One read of the shared account, and nothing more, for a database that
  /// holds none.
  Future<void> importAll(List<CalendarCategoriesCompanion> entries) {
    if (entries.isEmpty) return Future.value();
    return transaction(() async {
      await db.sharedRowDao.evict('calendar_categories', [
        for (final entry in entries) entry.id.value,
      ]);
      final stamps = [for (final _ in entries) db.newStamp()];
      await batch((b) {
        for (var i = 0; i < entries.length; i++) {
          final entry = entries[i];
          final stamp = stamps[i];
          b.insert(
            calendarCategories,
            entry.copyWith(
              hlcTimestamp: Value(stamp.hlc),
              deviceId: Value(stamp.deviceId),
              version: const Value(1),
              isDeleted: const Value(false),
              deletedAt: const Value(null),
            ),
            mode: InsertMode.insertOrReplace,
          );
          db.enqueueIn(b, calendarCategories, entry.id.value, stamp.hlc);
        }
      });
    });
  }

  Future<void> insertCategory(CalendarCategoriesCompanion entry) {
    return transaction(() async {
      final stamp = await db.stampLocal(calendarCategories, entry.id.value);
      await into(calendarCategories).insert(
        entry.copyWith(
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: const Value(1),
        ),
      );
    });
  }

  /// Update that preserves `created_at` by masking it out, mirroring
  /// `CalendarEventDao.upsert`.
  ///
  /// Read-then-write so the version can be bumped. A tombstoned category is
  /// left alone rather than resurrected: an edit that lands after the delete
  /// would otherwise bring back a category whose events already moved to the
  /// fallback — the no-op the hard delete this replaced gave.
  ///
  /// An edit that changes nothing but `updated_at` writes nothing, the way
  /// `CategoryService.setHidden` already refuses a repeated tap, so a save of
  /// an unchanged category does not read as a change once devices merge.
  ///
  /// Returns whether the row was **there to write**, not whether a statement
  /// ran: a save that stores exactly what is already stored is a success the
  /// caller has nothing to say about, while a missing or tombstoned row means
  /// the edit is lost — the one case the editor sheet must not report as
  /// saved, since it would hand a dead category back to its caller. Another
  /// account's category is such a case: the fences keep it as its owner
  /// wrote it, so the edit is lost and nothing is stamped or queued.
  Future<bool> updateCategory(CalendarCategoriesCompanion entry) {
    return transaction(() async {
      final id = entry.id.value;
      final existing = await _liveById(id);
      if (existing == null || await _isPartners(existing)) return false;
      final merged = existing.copyWithCompanion(
        entry.copyWith(createdAt: const Value.absent()),
      );
      if (merged.copyWith(updatedAt: existing.updatedAt) == existing) {
        return true;
      }
      final stamp = await db.stampLocal(calendarCategories, id);
      await (update(calendarCategories)..where((c) => c.id.equals(id))).write(
        entry.copyWith(
          createdAt: const Value.absent(),
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: Value(existing.version + 1),
        ),
      );
      return true;
    });
  }

  /// Tombstones a category, the [CalendarEventDao.softDeleteById] shape: the
  /// row survives with `is_deleted = 1` and a bumped version, so the delete
  /// carries an order once devices merge, and [getAll]'s filter is what makes
  /// it vanish. A missing or already-tombstoned row is a no-op.
  ///
  /// **Refuses every built-in** — by id as well as by flag, since an older
  /// archive could restore a built-in as custom — and returns false, so no
  /// path can tombstone one: `other` is where every orphaned event resolves.
  /// Returns true only when a row was tombstoned.
  Future<bool> softDeleteById(String id) {
    return transaction(() async {
      final existing = await _deletable(id);
      if (existing == null) return false;
      await _tombstone(existing, db.newStamp());
      return true;
    });
  }

  /// Deletes a custom category as the one act it is to the user: its live
  /// events and templates move to [reassignTo], its live alerts and profile
  /// tombstone, and the category tombstones, all under **one** HLC and each
  /// row queued — so another device merges the delete whole rather than five
  /// changes it could interleave.
  ///
  /// The templates move for the same reason the events do: `CategoryService`'s
  /// contract is that no event is ever orphaned, and a template left on the
  /// dead id goes on stamping it onto every event built from it.
  ///
  /// [softDeleteById]'s refusals are checked before anything is written: a
  /// built-in, missing or already-tombstoned category moves no event and
  /// tombstones no alert. Returns whether the category was deleted.
  ///
  /// A shared category's live events leave it through
  /// [CalendarEventDao.reassignCategory], which says their new grant; its
  /// tombstoned events stay, and are said again by [_tombstone].
  ///
  /// [reassignTo] is resolved here, inside the transaction, against the live
  /// table: a target that is [id] itself or no longer live — a sync pull can
  /// tombstone it while the caller's catalogue still lists it — becomes
  /// [kFallbackCategoryId], so no event or template lands on a dead id. So
  /// does another account's category, which the fences keep every event
  /// and template of the person's own from taking: they would stay on the
  /// tombstoned id.
  Future<bool> tombstoneCascade(String id, {required String reassignTo}) {
    return transaction(() async {
      final existing = await _deletable(id);
      if (existing == null) return false;
      final target =
          reassignTo == kFallbackCategoryId ||
              (reassignTo != id && await _ownLive(reassignTo))
          ? reassignTo
          : kFallbackCategoryId;
      final stamp = db.newStamp();
      await db.calendarEventDao.reassignCategory(id, target, stamp: stamp);
      await db.eventTemplateDao.reassignCategory(id, target, stamp: stamp);
      await db.categoryAlertDao.tombstoneForCategory(id, stamp: stamp);
      await db.categoryProfileDao.tombstoneForCategory(id, stamp: stamp);
      await _tombstone(existing, stamp);
      // A shared category's end can ring: its events leave the partner.
      await db.syncDao.oweSharePokes([existing.sharedPair], urgent: true);
      return true;
    });
  }

  /// What [tombstoneCascade] would touch for [id], counted here beside it so
  /// the numbers the delete sheet shows are the cascade's own rows — live
  /// events and templates in [id], and its live alerts — rather than three
  /// caches that may each lag the table.
  ///
  /// Plain reads, not a transaction: the sheet shows a picture of the
  /// moment and the cascade recounts nothing, so a write landing between two
  /// of them costs a stale number on screen and never a wrong delete.
  Future<CategoryDeleteImpact> deleteImpact(String id) async {
    final events = await db.calendarEventDao.countByCategory();
    final templates = await db.eventTemplateDao.countByCategory();
    final alerts = await db.categoryAlertDao.getAllActive();
    final eventCount = events[id] ?? 0;
    return CategoryDeleteImpact(
      events: eventCount,
      alerts: alerts.where((alert) => alert.categoryId == id).length,
      templates: templates[id] ?? 0,
      // Only a category with events can hold a marked one.
      markedEvents: eventCount == 0
          ? 0
          : await db.calendarEventDao.countOwnMarkedIn(id),
    );
  }

  /// Shares the live category [id] into [pairId] — and with it every event
  /// of the person's own in it that carries no mark of its own, now and
  /// whenever one is added later — or makes it private again when null: the
  /// one writer of `shared_pair` on this table
  /// (`docs/cloud-share-surfaces-roadmap.md` §7.1), the shape of
  /// [CalendarEventDao.setSharedPair]. A stamped write of the mark and its
  /// stamp, so the owner's other devices merge the mark like any edit;
  /// `updated_at` is left alone, as a label's write leaves it. A built-in
  /// is marked like any other, under its fixed id.
  ///
  /// A database shares into one pair: setting a mark clears every mark of
  /// another pair, here, on `calendar_events` and on `folders`, under the
  /// same stamp.
  ///
  /// The events the mark decides, and their day rows, are queued again at
  /// the stamps they carry ([CalendarEventDao.requeueForCategories]): their
  /// documents say who may read them, and only a push writes that.
  ///
  /// A missing or tombstoned category writes nothing, and neither does a
  /// mark it already carries — though the marks of other pairs are cleared
  /// even then. Returns whether the category's mark was written.
  Future<bool> setSharedPair(String id, String? pairId) {
    return transaction(() async {
      final existing = await _liveById(id);
      if (existing == null) return false;
      // Another account's category is theirs to share.
      if (await db.sharedRowDao.isShared('calendar_categories', id)) {
        return false;
      }
      // One stamp for the whole act: the mark and whatever it clears.
      final stamp = db.newStamp();
      if (pairId != null) {
        await clearOtherPairs(pairId, stamp);
        await db.calendarEventDao.clearOtherPairs(pairId, stamp);
        await db.folderDao.clearOtherPairs(pairId, stamp);
      }
      if (existing.sharedPair == pairId) return false;
      await db.enqueue(calendarCategories, id, stamp.hlc);
      await (update(calendarCategories)..where((c) => c.id.equals(id))).write(
        CalendarCategoriesCompanion(
          sharedPair: Value(pairId),
          sharedStamp: Value(stamp.hlc),
          hlcTimestamp: Value(stamp.hlc),
          deviceId: Value(stamp.deviceId),
          version: Value(existing.version + 1),
        ),
      );
      await db.calendarEventDao.requeueForCategories([id]);
      await db.syncDao.oweSharePokes([
        pairId,
        existing.sharedPair,
      ], urgent: true);
      return true;
    });
  }

  /// Clears, under [stamp], the mark of every category shared into another
  /// pair than [pairId] — every mark there is when null — each row queued,
  /// and the events a live one granted queued again: its half of "a
  /// database shares into one pair", called inside the transaction of the
  /// write that sets a mark ([setSharedPair],
  /// [CalendarEventDao.setSharedPair], [FolderDao.setSharedPair]) and when
  /// the account's pair is found changed or ended
  /// ([FolderDao.clearSharesExcept]). Tombstones too: their documents would
  /// go on naming a pair this database no longer shares into. Returns how
  /// many it cleared.
  Future<int> clearOtherPairs(String? pairId, CrdtStamp stamp) async {
    // The pairs the marks named, read before they go: each is owed a poke.
    final pairs = await customSelect(
      'SELECT DISTINCT shared_pair AS pair FROM calendar_categories '
      'WHERE shared_pair IS NOT NULL AND shared_pair IS NOT ?1',
      variables: [Variable<String>(pairId)],
      readsFrom: {calendarCategories},
    ).map((row) => row.read<String>('pair')).get();
    if (pairs.isEmpty) return 0;
    final cleared = await customWriteReturning(
      'UPDATE calendar_categories SET shared_pair = NULL, shared_stamp = ?1, '
      'hlc_timestamp = ?1, device_id = ?2, version = version + 1 '
      'WHERE shared_pair IS NOT NULL AND shared_pair IS NOT ?3 '
      'RETURNING id, is_deleted',
      variables: [
        Variable<String>(stamp.hlc),
        Variable<String>(stamp.deviceId),
        Variable<String>(pairId),
      ],
      updates: {calendarCategories},
      updateKind: UpdateKind.update,
    );
    if (cleared.isEmpty) return 0;
    await db.syncDao.oweSharePokes(pairs, urgent: true);
    for (final deleted in const [false, true]) {
      await db.enqueueMany(
        calendarCategories,
        [
          for (final row in cleared)
            if (row.read<bool>('is_deleted') == deleted) row.read<String>('id'),
        ],
        stamp.hlc,
        op: OutboxOp.forRow(isDeleted: deleted),
      );
    }
    final granting = [
      for (final row in cleared)
        if (!row.read<bool>('is_deleted')) row.read<String>('id'),
    ];
    if (granting.isNotEmpty) {
      await db.calendarEventDao.requeueForCategories(granting);
    }
    return cleared.length;
  }

  /// The live custom row [id], or null when it is missing, already a
  /// tombstone, or built in — by flag or by id.
  ///
  /// Another account's category is not deletable either: the fences would
  /// keep it while the cascade tombstoned the person's own alerts and
  /// profile on it and moved nothing.
  Future<CalendarCategoryRow?> _deletable(String id) async {
    final existing = await _liveById(id);
    if (existing == null || existing.isBuiltIn || builtInIds.contains(id)) {
      return null;
    }
    if (await _isPartners(existing)) return null;
    return existing;
  }

  /// Whether [id] is a live category of the person's own.
  Future<bool> _ownLive(String id) async {
    final live = await _liveById(id);
    return live != null && !await _isPartners(live);
  }

  /// Whether [row] is a category another account shares with this one. No
  /// statement for a row that names no owner, which is every row written
  /// since the bind.
  Future<bool> _isPartners(CalendarCategoryRow row) async {
    final owner = row.ownerId;
    return owner != null && owner == await db.sharedRowDao.owner();
  }

  /// A tombstone grants nothing to the events in it, so a shared category's
  /// remaining events — and their day rows — are queued again
  /// ([CalendarEventDao.requeueForCategories]). The category's own document
  /// keeps its mark: the partner has to hear of the delete. Only a revival
  /// clears it ([mergeRemoteCategory], [seedMissing]).
  Future<void> _tombstone(CalendarCategoryRow existing, CrdtStamp stamp) async {
    final now = DateTime.now();
    await db.enqueue(
      calendarCategories,
      existing.id,
      stamp.hlc,
      op: OutboxOp.tombstone,
    );
    await (update(
      calendarCategories,
    )..where((c) => c.id.equals(existing.id))).write(
      CalendarCategoriesCompanion(
        isDeleted: const Value(true),
        deletedAt: Value(now),
        updatedAt: Value(now),
        hlcTimestamp: Value(stamp.hlc),
        deviceId: Value(stamp.deviceId),
        version: Value(existing.version + 1),
      ),
    );
    if (existing.sharedPair != null) {
      await db.calendarEventDao.requeueForCategories([existing.id]);
    }
  }

  /// The rows under [ids], tombstones included: the sync push sends the
  /// tombstone a delete queued, so it reads past the live-row filter.
  Future<List<CalendarCategoryRow>> getByIdsIncludingDeleted(List<String> ids) {
    if (ids.isEmpty) return Future.value(const []);
    return (select(calendarCategories)..where((c) => c.id.isIn(ids))).get();
  }

  /// Merges one remote category on the contract of [CrdtMerge.mergeRemoteRow].
  /// A built-in's fixed id merges like any other, `is_built_in` included as
  /// received; a tombstone writes the stamps, the deletion and the owner and
  /// keeps the rest, and reassigns no event — the events moved by the delete
  /// elsewhere arrive as their own rows.
  ///
  /// The share mark is settled apart from the row ([CrdtMerge.mergeMark]),
  /// as an event's is: the mark stamped later stands whichever side's row
  /// won. A tombstone carries no mark, and the one here stands.
  ///
  /// A delete ends the grant for good: a live row that wins over a tombstone
  /// here brings the category back private, whatever mark either side
  /// carries: a stamped write of the cleared mark, as [setSharedPair]'s is,
  /// so every device's merge and the space's document take the end over the
  /// mark the tombstone kept — or one a device that never heard of the
  /// delete still carries. Otherwise the revived category would share every
  /// event added to it on a device that never saw it shared. A row no mark
  /// ever touched has no stamp on either side and writes nothing more.
  ///
  /// A merge that changes what the category grants its events — its mark,
  /// or whether it is live at all — queues this device's copies of those
  /// events and their day rows again
  /// ([CalendarEventDao.requeueForCategories]): a device that pushed one
  /// before it had merged the change wrote a document that says the old
  /// grant. Events can arrive ahead of their category, so a new category
  /// that carries a mark queues them too.
  ///
  /// [shared] merges a category another account shares with this one
  /// (`docs/cloud-share-surfaces-roadmap.md` §7.5): the owner's copy wins
  /// whatever the stamps say, it carries no mark here — its caller took the
  /// owner's off — and nothing is queued.
  Future<MergeOutcome> mergeRemoteCategory(
    CalendarCategoryRow remote, {
    String? floor,
    bool shared = false,
  }) {
    return transaction(() async {
      final local = await (select(
        calendarCategories,
      )..where((c) => c.id.equals(remote.id))).getSingleOrNull();
      if (shared) {
        return _mergeCategory(remote, local, CrdtMerge.everyStamp);
      }
      final outcome = await _mergeCategory(remote, local, floor);
      final wrote =
          outcome.result == MergeResult.inserted ||
          outcome.result == MergeResult.applied;
      final before = _grantOf(local);
      String? after;
      if (remote.isDeleted) {
        after = wrote ? null : before;
      } else if (wrote &&
          local != null &&
          local.isDeleted &&
          (local.sharedStamp != null || remote.sharedStamp != null)) {
        final stamp = db.newStamp();
        await db.enqueue(calendarCategories, remote.id, stamp.hlc);
        await (update(
          calendarCategories,
        )..where((c) => c.id.equals(remote.id))).write(
          CalendarCategoriesCompanion(
            sharedPair: const Value(null),
            sharedStamp: Value(stamp.hlc),
            hlcTimestamp: Value(stamp.hlc),
            deviceId: Value(stamp.deviceId),
            version: Value(remote.version + 1),
          ),
        );
        after = null;
      } else {
        final kept = await CrdtMerge.mergeMark(
          db,
          table: calendarCategories,
          rowKey: remote.id,
          local: local == null
              ? null
              : (pair: local.sharedPair, stamp: local.sharedStamp),
          remote: (pair: remote.sharedPair, stamp: remote.sharedStamp),
          result: outcome.result,
          write: (mark) =>
              (update(
                calendarCategories,
              )..where((c) => c.id.equals(remote.id))).write(
                CalendarCategoriesCompanion(
                  sharedPair: Value(mark.pair),
                  sharedStamp: Value(mark.stamp),
                ),
              ),
        );
        after = wrote || !local!.isDeleted ? kept.pair : null;
      }
      if (before != after) {
        await db.calendarEventDao.requeueForCategories([remote.id]);
        await db.syncDao.oweSharePokes([before, after], urgent: true);
      }
      return outcome;
    });
  }

  /// What the category [row] grants the events in it: its mark while it is
  /// live, nothing once it is a tombstone or when there is no row.
  static String? _grantOf(CalendarCategoryRow? row) =>
      row == null || row.isDeleted ? null : row.sharedPair;

  /// [mergeRemoteCategory]'s merge of the row itself, inside its
  /// transaction.
  Future<MergeOutcome> _mergeCategory(
    CalendarCategoryRow remote,
    CalendarCategoryRow? local,
    String? floor,
  ) {
    return CrdtMerge.mergeRemoteRow(
      db,
      table: calendarCategories,
      rowKey: remote.id,
      remoteHlc: remote.hlcTimestamp,
      localHlc: local?.hlcTimestamp,
      floor: floor,
      insert: () => into(calendarCategories).insert(remote),
      overwrite: (applied) async {
        if (remote.isDeleted) {
          await (update(
            calendarCategories,
          )..where((c) => c.id.equals(remote.id))).write(
            CalendarCategoriesCompanion(
              hlcTimestamp: Value(remote.hlcTimestamp),
              deviceId: Value(remote.deviceId),
              version: Value(remote.version),
              isDeleted: const Value(true),
              deletedAt: Value(remote.deletedAt),
              updatedAt: CrdtMerge.tombstoneUpdatedAt(remote.deletedAt),
              ownerId: Value(remote.ownerId),
            ),
          );
        } else {
          await update(calendarCategories).replace(remote);
        }
        return applied;
      },
    );
  }

  /// Hard wipe, tombstones included — the backup import's replace-everything
  /// step, which must stay hard: a restore is never a merge.
  ///
  /// A shared category's events go on standing under its id — a restore
  /// re-imports no mark — so they, and their day rows, are queued again
  /// first ([CalendarEventDao.requeueForCategories]): their documents would
  /// otherwise go on saying "shared". One read for a database that shares
  /// no category.
  ///
  /// Another account's categories are not the person's to wipe: the fences
  /// skip them, as the events' wipe leaves a partner's events
  /// ([CalendarEventDao.deleteAll]). That is a defence, not the path: the
  /// restore that calls this unbinds the database first (`BackupService`),
  /// and the unbind has removed every shared row (`SharedRowDao.removeAll`).
  /// They carry no mark here, so the read above never names one.
  Future<void> deleteAll() {
    return transaction(() async {
      final marked = await customSelect(
        'SELECT id FROM calendar_categories '
        'WHERE shared_pair IS NOT NULL AND is_deleted = 0',
        readsFrom: {calendarCategories},
      ).get();
      if (marked.isNotEmpty) {
        await db.calendarEventDao.requeueForCategories([
          for (final row in marked) row.read<String>('id'),
        ]);
      }
      await delete(calendarCategories).go();
    });
  }

  /// Rewrites `sort_order` to a dense `0..N-1` matching [idsInOrder].
  ///
  /// One `batch` — which drift runs as a single transaction and a single
  /// commit — never an update per row awaited in a loop, and never a read
  /// first: `version + 1` is SQL arithmetic, and the drag shares one HLC.
  /// `query_count_test` guards the shape. A row already at its index is not
  /// written, so a drag re-stamps only the rows it moved.
  ///
  /// **Dense values matter.** `CalendarCategories._byOrder` tie-breaks on
  /// `id`, so leaving gaps or duplicates lets rows shuffle among themselves
  /// on the next load, which reads as the drag not having stuck.
  ///
  /// Ids not present in the table update nothing; a repeated id is written
  /// twice and the last wins. Neither can corrupt the ordering of the rest.
  Future<void> reorder(List<String> idsInOrder) async {
    if (idsInOrder.isEmpty) return;
    final now = DateTime.now();
    await transaction(() async {
      final stamp = db.newStamp();
      await batch((b) {
        for (var i = 0; i < idsInOrder.length; i++) {
          b.update(
            calendarCategories,
            CalendarCategoriesCompanion.custom(
              sortOrder: Variable<int>(i),
              updatedAt: Variable<DateTime>(now),
              hlcTimestamp: Variable<String>(stamp.hlc),
              deviceId: Variable<String>(stamp.deviceId),
              version: calendarCategories.version + const Constant(1),
            ),
            where: (c) =>
                c.id.equals(idsInOrder[i]) &
                _live &
                c.sortOrder.equals(i).not(),
          );
        }
        db.enqueueWrittenIn(b, calendarCategories, idsInOrder, stamp.hlc);
      });
    });
  }

  /// Next free sort order (max + 1, or 0 when the table is empty). Used to
  /// append newly created categories after every existing one.
  ///
  /// Counts tombstones on purpose, the `VocabularyDao` rule: a merge can
  /// resurrect a deleted category, and it must not land on a slot a newer one
  /// took. It returns a number, never a row, so no tombstone leaks upward.
  ///
  /// Never counts another account's: their order is theirs, not a slot in
  /// this person's list.
  Future<int> nextSortOrder() async {
    final maxExpr = calendarCategories.sortOrder.max();
    final row =
        await (selectOnly(calendarCategories)
              ..addColumns([maxExpr])
              ..where(const CustomExpression<bool>(SyncDao.mineSql)))
            .getSingleOrNull();
    final current = row?.read(maxExpr);
    return (current ?? -1) + 1;
  }

  Future<CalendarCategoryRow?> _liveById(String id) {
    return (select(
      calendarCategories,
    )..where((c) => c.id.equals(id) & _live)).getSingleOrNull();
  }
}
