import 'package:equatable/equatable.dart';

import '../../database/database.dart';
import 'sync_table_binding.dart';

/// What a pulled page does to the rest of the app. The engine decides WHEN;
/// the production hooks (S3c) decide HOW — caches, change events, the
/// calendar bloc, the alert planner — so the engine is testable with a
/// recorder and holds no reference to a service above it.
abstract interface class SyncApplyHooks {
  /// Before a page of [table] is merged, outside its transaction: a pending
  /// counter tap flushed after the merge would be stamped over the merged
  /// value, so the counters hook flushes here; the others may ignore it.
  Future<void> beforePage(String table);

  /// After a page of [table] committed, with every envelope it merged — the
  /// per-row effects (a merged note's change event) need the keys, not only
  /// the table.
  Future<void> afterPage(String table, List<SyncAppliedRow> rows);

  /// Once per run after the pull, with the cache classes whose rows changed
  /// here; `alerts` rides along whenever `calendar` did, because events and
  /// categories feed the alert planner as much as the alert rows do.
  Future<void> afterRun(Set<SyncInvalidation> touched);

  /// A strictly newer remote replaced a note whose local edit had not been
  /// pushed yet: the losing text is filed as a copy so nothing typed is lost
  /// (D3). Called once per losing merge, inside its page's transaction after
  /// the merges and before the cursor moves: a copy that throws rolls the
  /// page back, so the next run merges it again rather than the losing text
  /// being dropped. It must therefore write only through the database —
  /// drift nests its writes as a savepoint — and tell no listener: it returns
  /// the copy's id, and the engine passes it to [afterPage] as an inserted
  /// row of `notes` once the page committed (record §3.9). Null when no copy
  /// was written.
  Future<String?> fileConflictCopy(SyncNoteConflict conflict);
}

/// One envelope a pulled page merged.
class SyncAppliedRow extends Equatable {
  /// The row's key in its table, as the outbox keys it.
  final String rowKey;

  /// What the merge did; only `inserted` and `applied` changed a row here,
  /// so the hooks act on those and pass over the rest.
  final MergeResult result;

  /// Whether the envelope deleted its row, so a hook can tell a removal from
  /// an edit without reading the row back.
  final bool tombstone;

  /// Notes and folders: the merge moved the row to another parent, so the
  /// list it left hears of it too ([MergeOutcome.moved]).
  final bool moved;

  /// The parent the row left when [moved]; null for a folder at the root.
  final String? previousParent;

  const SyncAppliedRow({
    required this.rowKey,
    required this.result,
    required this.tombstone,
    this.moved = false,
    this.previousParent,
  });

  @override
  List<Object?> get props => [
    rowKey,
    result,
    tombstone,
    moved,
    previousParent,
  ];
}

/// A local note a newer remote overwrote before its edit was pushed.
class SyncNoteConflict extends Equatable {
  /// The local row as it stood before the merge: its folder and title place
  /// the copy beside the note it came from.
  final Note loser;

  /// The body that lost, read before the remote replaced the chunks.
  final String loserContent;

  const SyncNoteConflict({required this.loser, required this.loserContent});

  @override
  List<Object?> get props => [loser, loserContent];
}

/// Hooks that do nothing: for an engine whose pulls nothing above the DAO
/// needs to hear of, and for tests that do not look at the effects.
class NoOpSyncApplyHooks implements SyncApplyHooks {
  const NoOpSyncApplyHooks();

  @override
  Future<void> beforePage(String table) async {}

  @override
  Future<void> afterPage(String table, List<SyncAppliedRow> rows) async {}

  @override
  Future<void> afterRun(Set<SyncInvalidation> touched) async {}

  @override
  Future<String?> fileConflictCopy(SyncNoteConflict conflict) async => null;
}
