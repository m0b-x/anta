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
  ///
  /// After a read of what a partner shares, [shared] says what it brought
  /// and took away — what a person is told of, which no cache class names;
  /// [SharedReadChanges.none] after the account's own pull.
  Future<void> afterRun(
    Set<SyncInvalidation> touched, {
    SharedReadChanges shared = SharedReadChanges.none,
  });

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

  /// Notes only: the body the merge wrote, so an editor holding the note is
  /// told what the page stored instead of the hook re-reading a row a local
  /// save may have overwritten since (R4). Null for every other table, for a
  /// tombstone and for a row the merge left alone.
  final String? content;

  /// The row no longer exists here at all: one another account shared, which
  /// left with its grant and leaves no tombstone. A hook cannot read it
  /// back, so for a note and a folder [previousParent] is where it stood —
  /// the list that has to drop it.
  final bool gone;

  const SyncAppliedRow({
    required this.rowKey,
    required this.result,
    required this.tombstone,
    this.moved = false,
    this.previousParent,
    this.content,
    this.gone = false,
  });

  @override
  List<Object?> get props => [
    rowKey,
    result,
    tombstone,
    moved,
    previousParent,
    content,
    gone,
  ];
}

/// A local note a newer remote overwrote before its edit was pushed — or,
/// when [incoming], another device's edit a newer local one kept out.
class SyncNoteConflict extends Equatable {
  /// The local row as it stood before the merge: its folder and title place
  /// the copy beside the note it came from. When [incoming], it carries the
  /// remote's title and label.
  final Note loser;

  /// The body that lost, read before the remote replaced the chunks; the
  /// remote's body when [incoming].
  final String loserContent;

  /// Whether the text that lost arrived with the pull. An open editor never
  /// showed it and keeps its own text, so no editor claims this copy
  /// (scalability record S8).
  final bool incoming;

  const SyncNoteConflict({
    required this.loser,
    required this.loserContent,
    this.incoming = false,
  });

  @override
  List<Object?> get props => [loser, loserContent, incoming];
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
  Future<void> afterRun(
    Set<SyncInvalidation> touched, {
    SharedReadChanges shared = SharedReadChanges.none,
  }) async {}

  @override
  Future<String?> fileConflictCopy(SyncNoteConflict conflict) async => null;
}

/// A partner's event this phone came to hold: its stored category tells an
/// event shared one by one from one that came with a category.
typedef SharedEventArrival = ({String id, String title, String category});

/// A partner's event this phone no longer holds, with the title it had —
/// read before it went, since nothing is left to read it from.
typedef SharedEventLeave = ({String id, String title});

/// What one read of a partner's shares changed on this phone, by what this
/// phone held before it (`docs/cloud-share-surfaces-roadmap.md` §6.14): an
/// update of a row already held, or a read from the start that meets it
/// again, is no arrival; a tombstone is none either.
class SharedReadChanges extends Equatable {
  /// The partner's categories newly held: a row of their own stored under
  /// an id not held before, and a built-in newly recorded as shared.
  final List<String> categoryIds;

  /// The partner's live events stored under an id not held before.
  final List<SharedEventArrival> events;

  /// The partner's live events this read removed or saw deleted: no longer
  /// shared, deleted by the partner, their category no longer shared, or
  /// the whole share forgotten with its pair. One the same read stored
  /// again never left — a pair made anew shares it again, so it is among
  /// [events].
  final List<SharedEventLeave> left;

  /// The pair whose whole share this read forgot — it ended, or another
  /// was made — when it did; every one of [left] went with it then. Null
  /// when the read forgot nothing, and when the pair was never recorded.
  final String? endedPair;

  const SharedReadChanges({
    this.categoryIds = const [],
    this.events = const [],
    this.left = const [],
    this.endedPair,
  });

  static const SharedReadChanges none = SharedReadChanges();

  bool get isEmpty => categoryIds.isEmpty && events.isEmpty && left.isEmpty;

  @override
  List<Object?> get props => [categoryIds, events, left, endedPair];
}
