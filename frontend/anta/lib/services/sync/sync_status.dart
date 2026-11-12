import 'package:equatable/equatable.dart';

import '../../models/app_user.dart';
import '../../models/sync_binding.dart';
import '../../utils/sync_quota_reset.dart';
import 'sync_cadence.dart';
import 'sync_gateway.dart';

/// When the space's daily quota comes back, for the engine's retry and the
/// pause's words alike.
abstract final class SyncQuota {
  /// The quota's first reset after [at] ([nextSyncQuotaReset]).
  static DateTime nextReset(DateTime at) => nextSyncQuotaReset(at);
}

/// Why sync is held back while the database is bound.
enum SyncPause {
  none,

  /// The space's daily quota ran out; Phase 02 sets it from the gateway's
  /// `quotaExhausted` failure and clears it on the next day's push (D19).
  quotaExhausted,

  /// The signed-in account is not the one that bound the database: sync is
  /// suspended with a visible reason, never re-owned (D3 ii).
  accountMismatch,

  /// The rules refused this account: nothing is pulled or pushed until the
  /// next sign-in or launch.
  noAccess,

  /// The space was marked for deletion or no longer exists — deleted from
  /// another device or the console. It holds as [noAccess] does and the
  /// engine never unbinds the database itself: "Stop syncing" is the way
  /// out (record D1, §5.2 d).
  spaceDeleted,

  /// The space was written by a newer app schema than this build knows; the
  /// rules refuse its writes by design until the app is updated.
  appOutdated,

  /// The database is bound and no one is signed in: there is no account to
  /// sync as, and signing back in as the bound one resumes.
  signedOut;

  /// The pause the stored binding alone decides for the account [uid]
  /// (null: signed out) — the reader's half of `SyncEngine.pauseOver`, and
  /// what `SyncBloc` recomputes when it carries a status to another account
  /// before that account's read lands (review U-2).
  static SyncPause forAccount(SyncBinding? binding, String? uid) =>
      binding == null
      ? none
      : uid == null
      ? signedOut
      : uid != binding.accountUid
      ? accountMismatch
      : none;
}

/// What the engine is doing right now.
enum SyncActivity {
  /// No run in flight: the page shows the last sync times.
  idle,

  /// Reading the space's rows and merging them, the initial download
  /// included — `downloadedRows` counts its progress.
  pulling,

  /// Sending the outbox to the space.
  pushing,
}

/// The last failed sync call, kept for the settings page to explain a stall.
class SyncFailureInfo extends Equatable {
  /// What kind of failure, which decides the reason the page shows and
  /// whether the engine retries, waits for the quota or stops.
  final SyncGatewayFailure failure;

  /// When the call failed, in UTC, so the page can say how long ago.
  final DateTime at;

  /// The gateway's own wording, for a diagnostic line; never shown as the
  /// reason itself, which comes from [failure].
  final String? message;

  const SyncFailureInfo(this.failure, {required this.at, this.message});

  @override
  List<Object?> get props => [failure, at, message];
}

/// Why a row is held back, strongest first: a row parked for several
/// reasons — its pull and its push, or a note and a chunk of its body — is
/// listed once, under the first of them that applies.
enum SyncHeldReason {
  /// A pulled note names chunks neither this device nor the space holds.
  awaitingText,

  /// A pulled document could not be decoded or merged here.
  unreadable,

  /// The cloud copy's rules refused the row's push.
  refused,

  /// The row could not be encoded for the push: too large, a chunk that no
  /// longer matches its hash, a chunk its manifest needs parked.
  unencodable,

  /// A pulled row of the person's own names a folder or an event that is
  /// held here as one another account shares: it waits for its own parent
  /// (`SharedParentHeld`). Last, so a park an earlier build stored still
  /// reads by name, and one this build stores reads there as unreadable.
  sharedParent,
}

/// What a held-back row is, by its table: the page names notes and folders
/// and labels the rest by kind. Ordered as the page lists them after notes
/// and folders.
enum SyncHeldKind {
  /// Named by its title.
  note,

  /// Named by its name.
  folder,

  /// An event, or one of its occurrences, absences, skips or alerts: the
  /// user knows them all as the event.
  event,

  /// A calendar category, its alerts or its profile.
  category,

  /// A counter or one of its values.
  counter,

  /// An event template.
  template,

  /// A saved overview view.
  view,

  /// A saved calendar filter.
  filter,

  /// An alert digest.
  digest,

  /// A vocabulary list or one of its items.
  vocabulary,

  /// A table the page has no word for: a binding added after this list.
  other;

  /// The kind of a row of the synced [table].
  static SyncHeldKind ofTable(String table) => switch (table) {
    'notes' => note,
    'folders' => folder,
    'calendar_events' ||
    'calendar_event_occurrences' ||
    'calendar_event_absences' ||
    'calendar_event_skips' ||
    'calendar_event_alerts' => event,
    'calendar_categories' ||
    'calendar_category_alerts' ||
    'calendar_category_profiles' => category,
    'counters' || 'counter_values' => counter,
    'calendar_event_templates' => template,
    'overview_views' => view,
    'calendar_filter_presets' => filter,
    'event_digests' => digest,
    'vocabularies' || 'vocabulary_items' => vocabulary,
    _ => other,
  };
}

/// One park as the engine holds it, pull or push, this session's or a
/// stored one — what the status service turns into [SyncHeldItem]s.
class SyncParkedRow extends Equatable {
  /// The synced table's name, as the outbox and the space name it.
  final String table;

  /// The row's key in [table] as its outbox entry carries it — a day-keyed
  /// row's composite key, a chunk's hash.
  final String rowKey;

  /// The stamp the park holds, empty when the document carried none.
  final String stamp;
  final SyncHeldReason reason;

  const SyncParkedRow(this.table, this.rowKey, this.stamp, this.reason);

  @override
  List<Object?> get props => [table, rowKey, stamp, reason];
}

/// One row the Sync page lists as held back (scalability record S7, the
/// D14 promise): every park of the row folded into one, a chunk's into the
/// notes holding it.
class SyncHeldItem extends Equatable {
  /// The synced table of the row listed: `notes` for a chunk's park, which
  /// is listed as each note holding it.
  final String table;

  /// The row's key in [table], which the page keeps a row's place by.
  final String rowKey;

  /// What the row is, for its glyph and, unless it is named, its title.
  final SyncHeldKind kind;

  /// A note's title or a folder's name, empty when the row has none; null
  /// for the other kinds, and for a note or folder this device holds no
  /// copy of — a pulled row it never merged.
  final String? name;

  /// Whether this device's row is a tombstone.
  final bool deleted;
  final SyncHeldReason reason;

  const SyncHeldItem({
    required this.table,
    required this.rowKey,
    required this.kind,
    this.name,
    this.deleted = false,
    required this.reason,
  });

  @override
  List<Object?> get props => [table, rowKey, kind, name, deleted, reason];
}

/// What the sync settings can say about this database's sync, read at once.
class SyncStatus extends Equatable {
  /// Rows changed locally and not yet pushed: the outbox's entry count.
  final int pendingCount;

  /// When a push was last acknowledged; null until Phase 02 pushes.
  final DateTime? lastPushAt;

  /// When a pulled page was last applied, or a live snapshot last found every
  /// table current (record §13); null before the first pull.
  final DateTime? lastPullAt;

  final SyncPause pause;

  /// When the engine runs on its own; the page's switch and the lines that
  /// promise a retry read it (record §13).
  final SyncCadence cadence;

  /// Whether the engine is pulling or pushing, so the page can show progress
  /// instead of a stale "last synced".
  final SyncActivity activity;

  /// The most recent failed call, cleared by the engine on the next success.
  final SyncFailureInfo? lastFailure;

  /// The rows held back — refused by the space or undecodable here — so one
  /// bad row cannot stop the others: [heldBack]'s length, so the status
  /// line and the list under it count the same rows.
  final int parkedCount;

  /// The rows held back, as the Sync page lists them.
  final List<SyncHeldItem> heldBack;

  /// Rows applied so far by the initial pull after a bind, its progress —
  /// or, while [updating], the notes the wire cutover has read again.
  final int downloadedRows;

  /// Whether the run in flight is the first under a new wire version
  /// (the scalability record's S6 cutover), reading every note again and
  /// then sending them: what keeps the browser and the calendar slow for a
  /// while after an update, which the drawer and the Sync page then say
  /// rather than a bare "Receiving…" or "Sending…".
  final bool updating;

  /// Whether the cutover's drain has begun, its second phase. Carried
  /// apart from [activity], which still says pulling between the re-read's
  /// end and the drain's first batch: an emit there must word the re-read
  /// and count it against its own total, not the drain's.
  final bool updatingSending;

  /// What the cutover's current phase counts towards: until
  /// [updatingSending], the live notes as the re-read began
  /// ([downloadedRows]); after it, the notes queued as the drain began
  /// ([updatingSent]), chunks apart. Null while unknown.
  final int? updatingTotal;

  /// The notes the cutover's drain has pushed so far, towards
  /// [updatingTotal] once [updatingSending].
  final int updatingSent;

  /// How far the clock seeded at open ran ahead of the wall clock, zero
  /// unless that is past the drift a remote may run ahead: a store written
  /// under a clock set far forward, which every later stamp inherits.
  final Duration clockAhead;

  /// How many remote stamps this run's clock held back for running too far
  /// ahead — a device with a clock set forward, seen through its rows.
  final int clampedRemotes;

  /// The space this database is bound to; null while unbound.
  final SyncBinding? binding;

  /// The database this one was found to be a copy of when the claim heal
  /// unbound it, until the next bind; null otherwise. The one reason an
  /// unbound database can give for no longer syncing without the user having
  /// stopped it (review X-2).
  final String? unboundAsCopyOf;

  /// When the quota pause began, as stored; null when no quota pause is
  /// stored. The pause's words say when it ends from this, never from the
  /// time they are drawn: drawn after the reset they would name the next one.
  final DateTime? quotaPausedAt;

  const SyncStatus({
    this.pendingCount = 0,
    this.lastPushAt,
    this.lastPullAt,
    this.pause = SyncPause.none,
    this.cadence = SyncCadence.automatic,
    this.activity = SyncActivity.idle,
    this.lastFailure,
    this.parkedCount = 0,
    this.heldBack = const [],
    this.downloadedRows = 0,
    this.updating = false,
    this.updatingSending = false,
    this.updatingTotal,
    this.updatingSent = 0,
    this.clockAhead = Duration.zero,
    this.clampedRemotes = 0,
    this.binding,
    this.unboundAsCopyOf,
    this.quotaPausedAt,
  });

  static const SyncStatus empty = SyncStatus();

  /// The quota reset the pause waits for, while it is still ahead of [now];
  /// null without a stored pause or once that reset has passed, when only
  /// the reason is left to say.
  DateTime? quotaResetAfter(DateTime now) {
    final paused = quotaPausedAt;
    if (paused == null) return null;
    final reset = SyncQuota.nextReset(paused);
    return reset.isAfter(now) ? reset : null;
  }

  /// The later of [lastPushAt] and [lastPullAt]: a sync either way is a
  /// sync, so the Sync section and the drawer say one time, never two.
  DateTime? get lastSyncAt {
    final push = lastPushAt;
    final pull = lastPullAt;
    if (push == null) return pull;
    if (pull == null) return push;
    return push.isAfter(pull) ? push : pull;
  }

  /// A copy with the given fields replaced; [clearLastFailure],
  /// [clearUpdatingTotal], [clearBinding] and [clearUnboundAsCopyOf] set
  /// those to null, which a null argument cannot say.
  SyncStatus copyWith({
    int? pendingCount,
    DateTime? lastPushAt,
    DateTime? lastPullAt,
    SyncPause? pause,
    SyncCadence? cadence,
    SyncActivity? activity,
    SyncFailureInfo? lastFailure,
    bool clearLastFailure = false,
    int? parkedCount,
    List<SyncHeldItem>? heldBack,
    int? downloadedRows,
    bool? updating,
    bool? updatingSending,
    int? updatingTotal,
    bool clearUpdatingTotal = false,
    int? updatingSent,
    Duration? clockAhead,
    int? clampedRemotes,
    SyncBinding? binding,
    bool clearBinding = false,
    String? unboundAsCopyOf,
    bool clearUnboundAsCopyOf = false,
    DateTime? quotaPausedAt,
  }) {
    return SyncStatus(
      pendingCount: pendingCount ?? this.pendingCount,
      lastPushAt: lastPushAt ?? this.lastPushAt,
      lastPullAt: lastPullAt ?? this.lastPullAt,
      pause: pause ?? this.pause,
      cadence: cadence ?? this.cadence,
      activity: activity ?? this.activity,
      lastFailure: clearLastFailure ? null : lastFailure ?? this.lastFailure,
      parkedCount: parkedCount ?? this.parkedCount,
      heldBack: heldBack ?? this.heldBack,
      downloadedRows: downloadedRows ?? this.downloadedRows,
      updating: updating ?? this.updating,
      updatingSending: updatingSending ?? this.updatingSending,
      updatingTotal: clearUpdatingTotal
          ? null
          : updatingTotal ?? this.updatingTotal,
      updatingSent: updatingSent ?? this.updatingSent,
      clockAhead: clockAhead ?? this.clockAhead,
      clampedRemotes: clampedRemotes ?? this.clampedRemotes,
      binding: clearBinding ? null : binding ?? this.binding,
      unboundAsCopyOf: clearUnboundAsCopyOf
          ? null
          : unboundAsCopyOf ?? this.unboundAsCopyOf,
      quotaPausedAt: quotaPausedAt ?? this.quotaPausedAt,
    );
  }

  @override
  List<Object?> get props => [
    pendingCount,
    lastPushAt,
    lastPullAt,
    pause,
    cadence,
    activity,
    lastFailure,
    parkedCount,
    heldBack,
    downloadedRows,
    updating,
    updatingSending,
    updatingTotal,
    updatingSent,
    clockAhead,
    clampedRemotes,
    binding,
    unboundAsCopyOf,
    quotaPausedAt,
  ];
}

/// Reads [SyncStatus] for the signed-in [user] — the seam `SyncBloc` reads
/// through, so its tests need no database.
abstract interface class SyncStatusReader {
  Future<SyncStatus> read({AppUser? user});
}
