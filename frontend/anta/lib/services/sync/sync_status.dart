import 'package:equatable/equatable.dart';

import '../../models/app_user.dart';
import '../../models/sync_binding.dart';

/// Why sync is held back while the database is bound.
enum SyncPause {
  none,

  /// The space's daily quota ran out; Phase 02 sets it from the gateway's
  /// `quotaExhausted` failure and clears it on the next day's push (D19).
  quotaExhausted,

  /// The signed-in account is not the one that bound the database: sync is
  /// suspended with a visible reason, never re-owned (D3 ii).
  accountMismatch,
}

/// What the sync settings can say about this database's sync, read at once.
class SyncStatus extends Equatable {
  /// Rows changed locally and not yet pushed: the outbox's entry count.
  final int pendingCount;

  /// When a push was last acknowledged; null until Phase 02 pushes.
  final DateTime? lastPushAt;

  final SyncPause pause;

  /// How far the clock seeded at open ran ahead of the wall clock, zero
  /// unless that is past the drift a remote may run ahead: a store written
  /// under a clock set far forward, which every later stamp inherits.
  final Duration clockAhead;

  /// How many remote stamps this run's clock held back for running too far
  /// ahead — a device with a clock set forward, seen through its rows.
  final int clampedRemotes;

  /// The space this database is bound to; null while unbound.
  final SyncBinding? binding;

  const SyncStatus({
    this.pendingCount = 0,
    this.lastPushAt,
    this.pause = SyncPause.none,
    this.clockAhead = Duration.zero,
    this.clampedRemotes = 0,
    this.binding,
  });

  static const SyncStatus empty = SyncStatus();

  @override
  List<Object?> get props => [
    pendingCount,
    lastPushAt,
    pause,
    clockAhead,
    clampedRemotes,
    binding,
  ];
}

/// Reads [SyncStatus] for the signed-in [user] — the seam `SyncBloc` reads
/// through, so its tests need no database.
abstract interface class SyncStatusReader {
  Future<SyncStatus> read({AppUser? user});
}
