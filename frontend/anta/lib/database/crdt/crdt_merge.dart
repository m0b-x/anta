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
  /// [localHlc] is null when the row is absent here, tombstones included.
  /// Stamps compare as strings: the encoding is zero-padded hex, so string
  /// order is time order, and an empty stamp sorts below every floor.
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
  /// Every branch advances the clock past the remote stamp, so the next local
  /// write orders after it. Nothing here mints a stamp or queues a remote
  /// row.
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
    db.hlc.update(HlcTimestamp.parse(remoteHlc));
    return outcome;
  }
}
