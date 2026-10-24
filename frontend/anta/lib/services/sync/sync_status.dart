import 'package:equatable/equatable.dart';

import '../../models/app_user.dart';
import '../../models/sync_binding.dart';
import 'sync_gateway.dart';

/// Why sync is held back while the database is bound.
enum SyncPause {
  none,

  /// The space's daily quota ran out; Phase 02 sets it from the gateway's
  /// `quotaExhausted` failure and clears it on the next day's push (D19).
  quotaExhausted,

  /// The signed-in account is not the one that bound the database: sync is
  /// suspended with a visible reason, never re-owned (D3 ii).
  accountMismatch,

  /// The space is gone, or the rules refused this account: nothing is
  /// pulled or pushed until the next sign-in or launch.
  noAccess,

  /// The space was written by a newer app schema than this build knows; the
  /// rules refuse its writes by design until the app is updated.
  appOutdated,

  /// The database is bound and no one is signed in: there is no account to
  /// sync as, and signing back in as the bound one resumes.
  signedOut,
}

/// What the engine is doing right now.
enum SyncActivity { idle, pulling, pushing }

/// The last failed sync call, kept for the settings page to explain a stall.
class SyncFailureInfo extends Equatable {
  final SyncGatewayFailure failure;
  final DateTime at;

  /// The gateway's own wording, for a diagnostic line; never shown as the
  /// reason itself, which comes from [failure].
  final String? message;

  const SyncFailureInfo(this.failure, {required this.at, this.message});

  @override
  List<Object?> get props => [failure, at, message];
}

/// What the sync settings can say about this database's sync, read at once.
class SyncStatus extends Equatable {
  /// Rows changed locally and not yet pushed: the outbox's entry count.
  final int pendingCount;

  /// When a push was last acknowledged; null until Phase 02 pushes.
  final DateTime? lastPushAt;

  /// When a pulled page was last applied; null before the first pull.
  final DateTime? lastPullAt;

  final SyncPause pause;

  /// Whether the engine is pulling or pushing, so the page can show progress
  /// instead of a stale "last synced".
  final SyncActivity activity;

  /// The most recent failed call, cleared by the engine on the next success.
  final SyncFailureInfo? lastFailure;

  /// Envelopes set aside this session — refused by the space or undecodable
  /// here — so one bad row cannot stop the others; retried next launch.
  final int parkedCount;

  /// Rows applied so far by the initial pull after a bind, its progress.
  final int downloadedRows;

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
    this.lastPullAt,
    this.pause = SyncPause.none,
    this.activity = SyncActivity.idle,
    this.lastFailure,
    this.parkedCount = 0,
    this.downloadedRows = 0,
    this.clockAhead = Duration.zero,
    this.clampedRemotes = 0,
    this.binding,
  });

  static const SyncStatus empty = SyncStatus();

  /// A copy with the given fields replaced; [clearLastFailure] and
  /// [clearBinding] set those to null, which a null argument cannot say.
  SyncStatus copyWith({
    int? pendingCount,
    DateTime? lastPushAt,
    DateTime? lastPullAt,
    SyncPause? pause,
    SyncActivity? activity,
    SyncFailureInfo? lastFailure,
    bool clearLastFailure = false,
    int? parkedCount,
    int? downloadedRows,
    Duration? clockAhead,
    int? clampedRemotes,
    SyncBinding? binding,
    bool clearBinding = false,
  }) {
    return SyncStatus(
      pendingCount: pendingCount ?? this.pendingCount,
      lastPushAt: lastPushAt ?? this.lastPushAt,
      lastPullAt: lastPullAt ?? this.lastPullAt,
      pause: pause ?? this.pause,
      activity: activity ?? this.activity,
      lastFailure: clearLastFailure ? null : lastFailure ?? this.lastFailure,
      parkedCount: parkedCount ?? this.parkedCount,
      downloadedRows: downloadedRows ?? this.downloadedRows,
      clockAhead: clockAhead ?? this.clockAhead,
      clampedRemotes: clampedRemotes ?? this.clampedRemotes,
      binding: clearBinding ? null : binding ?? this.binding,
    );
  }

  @override
  List<Object?> get props => [
    pendingCount,
    lastPushAt,
    lastPullAt,
    pause,
    activity,
    lastFailure,
    parkedCount,
    downloadedRows,
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
