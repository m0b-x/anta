import 'package:equatable/equatable.dart';

import '../database.dart';

/// What a remote merge did to the local row.
enum MergeResult {
  /// The row was unknown here and is stored as received.
  inserted,

  /// The remote row replaced the local one.
  applied,

  /// The local row is newer and stays; it was re-queued so the space learns
  /// of it on the next push.
  keptLocal,

  /// The same write arrived again: nothing changed.
  unchanged,
}

/// The result of one remote merge, carrying what the engine needs to act on
/// beyond the row itself.
final class MergeOutcome extends Equatable {
  /// Which branch of the merge ran: the engine counts what a page changed
  /// and invalidates caches only when a row was written.
  final MergeResult result;

  /// Whether the remote won over a local row whose change had not been pushed
  /// yet — its outbox entry was retired so it does not echo back.
  final bool localHadPendingPush;

  /// Notes only: the live local row a strictly newer remote overwrote while
  /// its change was still unpushed and its text differed, so the engine can
  /// file it as a conflict copy (D3). Null otherwise.
  final Note? loser;

  /// The [loser]'s body, read before the remote replaced its chunks.
  final String? loserContent;

  const MergeOutcome(
    this.result, {
    this.localHadPendingPush = false,
    this.loser,
    this.loserContent,
  });

  @override
  List<Object?> get props => [result, localHadPendingPush, loser, loserContent];
}
