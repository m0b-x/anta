import 'package:drift/drift.dart';

import '../database.dart';
import 'hlc.dart';
import 'merge_outcome.dart';

/// Where a `join` of [CrdtMerge.mergeRemoteRow] found the state both sides
/// converge on; the merge then runs the outbox side of it, so a joining DAO
/// never touches the queue but through `CrdtWrite`.
enum MergeJoin {
  /// The local row holds it and the remote too: nothing is written.
  echo,

  /// The local row holds it and the remote holds less: kept and re-queued,
  /// as an older remote is → [MergeResult.keptLocal].
  local,

  /// The remote holds it: written over the local row by `overwrite`, as a
  /// newer remote is → [MergeResult.applied].
  remote,

  /// Neither holds it: the join stored it under a fresh local stamp — raised
  /// toward the remote's, held to the drift limit; convergence does not
  /// depend on it — and queued it through `CrdtWrite` →
  /// [MergeResult.applied].
  stored,
}

/// The one decision every synced table's remote merge makes, so the DAO
/// merges cannot drift apart on it (record §3.4).
abstract final class CrdtMerge {
  static final String _seed = HlcTimestamp.seed.toString();

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
  /// - Same stamp: the same write seen again → [MergeResult.unchanged]. The
  ///   space already holds this row, so an outbox entry at or below the stamp
  ///   is retired: a rebind, a restore-then-bind or a Merge of a database the
  ///   space holds queues every row, and without the ack each one would be
  ///   pushed again (scalability record S9). Never for [HlcTimestamp.seed]:
  ///   every device stamps its own catalog defaults with it, so an equal
  ///   seed says nothing about what the space holds, and the entry is kept.
  /// - Remote newer, or the local stamp at or below [floor] (the bind's
  ///   initial merge, where the space is authoritative): the overwritten
  ///   local change's outbox entry is retired — pushing it would echo the
  ///   loser back — and [overwrite] runs → [MergeResult.applied]. Never for
  ///   a remote [HlcTimestamp.seed]: a seed is the catalog every device ships
  ///   and says nothing about the space, so yielding to it would replace a
  ///   real edit made before the floor — a rename whose upload never landed,
  ///   then a Stop syncing and a rebind — with defaults on both devices
  ///   (review RA1-1). The local row is kept and re-queued instead, so the
  ///   space gets the edit at the next drain.
  /// - Local newer: the row stays and is re-queued at its own stamp, which
  ///   repairs a push that landed over it elsewhere → [MergeResult.keptLocal].
  /// - [join] given, the stamps different and the floor not yielding: neither
  ///   side is simply newer — a counter value's taps add up whichever device
  ///   stamped last (D8 A) — so [join] decides which side holds what both
  ///   converge on, in place of the two rules above ([MergeJoin]).
  ///
  /// The clock is **not** advanced here: a raise is in-memory and no
  /// rollback undoes it, so a page that rolls back would leave this device
  /// able to out-stamp a remote row it never merged. The puller raises the
  /// clock to the page's highest stamp once the page committed (R65).
  /// Nothing here mints a stamp or queues a remote row.
  static Future<MergeOutcome> mergeRemoteRow(
    AppDatabase db, {
    required TableInfo table,
    required String rowKey,
    required String remoteHlc,
    required String? localHlc,
    String? floor,
    required Future<void> Function() insert,
    required Future<MergeOutcome> Function(MergeOutcome applied) overwrite,
    Future<MergeJoin> Function()? join,
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
      if (localHlc != _seed) {
        await db.syncOutboxDao.ackThrough(name, rowKey, localHlc);
      }
      outcome = const MergeOutcome(MergeResult.unchanged);
    } else {
      final yields = _yieldsToFloor(localHlc, remoteHlc, floor);
      final side = join != null && !yields
          ? await join()
          : remoteHlc.compareTo(localHlc) > 0 || yields
          ? MergeJoin.remote
          : MergeJoin.local;
      switch (side) {
        case MergeJoin.remote:
          final pending = await db.syncOutboxDao.ackThrough(
            name,
            rowKey,
            localHlc,
          );
          outcome = await overwrite(
            MergeOutcome(MergeResult.applied, localHadPendingPush: pending),
          );
        case MergeJoin.local:
          await db.syncOutboxDao.requeueRow(name, rowKey);
          outcome = const MergeOutcome(MergeResult.keptLocal);
        case MergeJoin.echo:
          outcome = const MergeOutcome(MergeResult.unchanged);
        case MergeJoin.stored:
          outcome = const MergeOutcome(MergeResult.applied);
      }
    }
    return outcome;
  }

  static bool _yieldsToFloor(
    String localHlc,
    String remoteHlc,
    String? floor,
  ) => floor != null && localHlc.compareTo(floor) <= 0 && remoteHlc != _seed;

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
