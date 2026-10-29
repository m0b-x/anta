import 'package:drift/drift.dart';

import '../database.dart';
import 'hlc.dart';
import 'merge_outcome.dart';

/// The one decision every synced table's remote merge makes, so the DAO
/// merges cannot drift apart on it (record §3.4).
abstract final class CrdtMerge {
  /// Decides one remote row against the local one and runs the matching side
  /// effects, while the caller supplies the writes, inside its own
  /// `transaction`.
  ///
  /// [localHlc] is null only when no row with this key exists here; a
  /// tombstone is a present row and passes its own stamp. Stamps compare as
  /// strings: the encoding is zero-padded hex, so string order is time order,
  /// and an empty stamp sorts below every floor.
  ///
  /// - Absent: [insert], stamps verbatim → [MergeResult.inserted].
  /// - Same stamp: the same write seen again → [MergeResult.unchanged].
  /// - Remote newer, or the local stamp at or below [floor] (the bind's
  ///   initial merge, where the space is authoritative): the overwritten
  ///   local change's outbox entry is retired — pushing it would echo the
  ///   loser back — and [overwrite] runs → [MergeResult.applied].
  /// - Local newer: the row stays and is re-queued at its own stamp, which
  ///   repairs a push that landed over it elsewhere → [MergeResult.keptLocal].
  ///
  /// The clock is **not** advanced here: a raise is in-memory and no
  /// rollback undoes it, so a page that rolls back would leave this device
  /// able to out-stamp a remote row it never merged. The puller raises the
  /// clock to the page's highest stamp once the page committed (R65).
  /// Nothing here mints a stamp or queues a remote row.
  ///
  /// `ContentChunkDao.mergeChunk` still advances the clock in its own
  /// transaction and is the one exception: it predates the engine, no pull
  /// reaches it — `content_chunks` is never queued and has no binding
  /// (record §3.4) — and nothing in `lib/` calls it (A7 review R145).
  static Future<MergeOutcome> mergeRemoteRow(
    AppDatabase db, {
    required TableInfo table,
    required String rowKey,
    required String remoteHlc,
    required String? localHlc,
    String? floor,
    required Future<void> Function() insert,
    required Future<MergeOutcome> Function(MergeOutcome applied) overwrite,
  }) async {
    final name = table.actualTableName;
    // Before the write, not after it: the rules validate the stamp by size
    // alone, so a document whose `hlc` is not `wall:counter:node` hex would
    // otherwise pay for an insert or an overwrite and then roll it back, and
    // park under a message naming neither table nor row (R69).
    try {
      HlcTimestamp.parse(remoteHlc);
    } on FormatException catch (error) {
      throw FormatException(
        '$name: "$rowKey" carries ${error.message}',
        remoteHlc,
      );
    }
    final MergeOutcome outcome;
    if (localHlc == null) {
      await insert();
      outcome = const MergeOutcome(MergeResult.inserted);
    } else if (remoteHlc == localHlc) {
      outcome = const MergeOutcome(MergeResult.unchanged);
    } else if (remoteHlc.compareTo(localHlc) > 0 ||
        (floor != null && localHlc.compareTo(floor) <= 0)) {
      final pending = await db.syncOutboxDao.ackThrough(name, rowKey, localHlc);
      outcome = await overwrite(
        MergeOutcome(MergeResult.applied, localHadPendingPush: pending),
      );
    } else {
      await db.syncOutboxDao.requeueRow(name, rowKey);
      outcome = const MergeOutcome(MergeResult.keptLocal);
    }
    return outcome;
  }

  /// Raises the clock past [remoteHlc], the highest stamp a pulled page
  /// merged, so the next local write orders after everything that page
  /// stored.
  ///
  /// Called by the puller once the page committed, never by a merge: the
  /// clock lives in memory and no rollback lowers it again (R65).
  ///
  /// `adopt`, not `update`: the page wrote its stamps verbatim onto rows of
  /// this database, and the drift guard would leave the clock below them, so
  /// the first local edit of such a row mints under it and is lost on every
  /// device (A5 review R98). Nothing is saved by holding — the page stored
  /// its highest stamp inside its own transaction and the next open seeds
  /// from it unguarded, so the clock ends above the row either way.
  static void advanceClock(AppDatabase db, String remoteHlc) {
    db.hlc.adopt(HlcTimestamp.parse(remoteHlc));
  }

  /// Raises the clock past [remoteHlc] from inside the transaction that
  /// merges it, for a merge that has to stamp above the row it rewrites —
  /// the folder repair's re-parenting (A7 review R131).
  ///
  /// `update`, not the [advanceClock] `adopt`: the raise happens while the
  /// page can still roll back, leaving nothing committed and no stamp
  /// stored behind it, so following a far-future stamp here would leave the
  /// clock arbitrarily ahead of everything this device holds and the next
  /// local edit would mint there, out-stamping remote rows it never merged
  /// (R65). The residual is R131's as recorded: a move stamped more than
  /// [HybridLogicalClock.maxDrift] ahead still sorts above the repair that
  /// rewrites it, so that push is denied and the move re-applies.
  static void advanceClockInTransaction(AppDatabase db, String remoteHlc) {
    db.hlc.update(HlcTimestamp.parse(remoteHlc));
  }

  /// What a merged tombstone writes to `updated_at`: the instant of the
  /// delete, so the deleting device and every merging one agree on the
  /// column instead of one holding the delete time and the others the last
  /// edit's (R67, R81).
  ///
  /// [deletedAt] is the tombstone's, never the row's own `updated_at` — a
  /// data-less tombstone decodes that to epoch 0, which would drag the
  /// column backwards. A tombstone reaching here without one leaves the
  /// column where it is.
  static Value<DateTime> tombstoneUpdatedAt(DateTime? deletedAt) =>
      deletedAt == null ? const Value.absent() : Value(deletedAt);

  /// How many keys one `IN (…)` of a sync load binds: a push or a pulled page
  /// can name more rows than an older SQLite accepts variables for.
  static const int keysPerStatement = 500;

  /// Runs [load] over [keys] [keysPerStatement] at a time and joins the
  /// results, for the DAOs' `…IncludingDeleted` loads.
  static Future<List<R>> loadInChunks<K, R>(
    List<K> keys,
    Future<List<R>> Function(List<K> chunk) load,
  ) async {
    if (keys.isEmpty) return const [];
    if (keys.length <= keysPerStatement) return load(keys);
    final rows = <R>[];
    for (var start = 0; start < keys.length; start += keysPerStatement) {
      final end = start + keysPerStatement < keys.length
          ? start + keysPerStatement
          : keys.length;
      rows.addAll(await load(keys.sublist(start, end)));
    }
    return rows;
  }
}
