import '../../database/crdt/crdt_write.dart';
import '../../database/crdt/hlc.dart';
import '../../database/crdt/merge_outcome.dart';
import '../../database/database.dart';
import 'sync_gateway.dart';

export '../../database/crdt/merge_outcome.dart';

/// Which in-memory caches the engine refreshes after a pulled page touched a
/// table: every table but notes and folders is cached in its service, and
/// nothing above the DAO hears of a merge on its own.
enum SyncInvalidation {
  folders,
  notes,
  counters,
  vocabularies,
  calendar,
  alerts,
}

/// How one synced table crosses the wire: the codec between its row and a
/// [SyncEnvelope], and the way into its DAO's remote merge.
///
/// The envelope's `data` is the table's backup map — the backup format is the
/// wire format — so a field the backup writes crosses under the backup's key
/// and in the backup's shape; the CRDT fields ride the envelope itself.
abstract class SyncTableBinding<R> {
  const SyncTableBinding();

  /// The SQL table name, one of `syncedTables`.
  String get table;

  SyncInvalidation get invalidation;

  /// The rows under [rowKeys], live and tombstoned alike — a push sends the
  /// tombstone a delete queued.
  Future<List<R>> loadByKeys(AppDatabase db, Iterable<String> rowKeys);

  /// The row's key, built by the same helper the outbox keys it with, so a
  /// queued key and a pushed document's id are byte for byte the same.
  String rowKeyOf(R row);

  /// The envelope for [row]: an upsert carrying the backup map, or a
  /// tombstone carrying nothing but identity and stamp. An unowned row is
  /// pushed under [boundUid], the account the rules require.
  Future<SyncEnvelope> encode(
    AppDatabase db,
    R row, {
    required String boundUid,
  });

  /// The row an envelope describes, its CRDT fields taken from the envelope.
  /// A tombstone without data decodes to a row of column defaults, so an
  /// unknown row's deletion can still be stored and later out-stamped.
  R decode(SyncEnvelope envelope);

  /// Merges [envelope] through the table's DAO; [floor] is the bind floor
  /// while the initial merge is pending, below which the space wins.
  Future<MergeOutcome> mergeRemote(
    AppDatabase db,
    SyncEnvelope envelope, {
    String? floor,
  });
}

/// The CRDT fields every binding stamps on its envelope.
SyncEnvelope envelopeOf({
  required String table,
  required String rowKey,
  required String hlc,
  required String deviceId,
  required int version,
  required bool isDeleted,
  required String ownerId,
  required Map<String, Object?> Function() data,
}) {
  return SyncEnvelope(
    table: table,
    rowKey: rowKey,
    hlc: hlc,
    deviceId: deviceId,
    version: version,
    op: isDeleted ? OutboxOp.tombstone : OutboxOp.upsert,
    ownerId: ownerId,
    data: isDeleted ? null : data(),
  );
}

/// Whether [envelope] deletes its row.
bool isTombstone(SyncEnvelope envelope) => envelope.op == OutboxOp.tombstone;

/// A tombstone's `deleted_at`: the wall time of the stamp that deleted it,
/// the only instant a data-less tombstone carries.
DateTime? deletedAtOf(SyncEnvelope envelope) {
  if (!isTombstone(envelope)) return null;
  return DateTime.fromMillisecondsSinceEpoch(
    HlcTimestamp.parse(envelope.hlc).wallTime,
  );
}

/// The envelope's data, or an empty map for a tombstone without any.
Map<String, Object?> dataOf(SyncEnvelope envelope) => envelope.data ?? const {};

/// An instant written as an ISO-8601 string, in UTC so two devices in
/// different zones read the same instant back — the backup's key, the
/// backup's `DateTime.parse`.
String isoOf(DateTime instant) => instant.toUtc().toIso8601String();

/// The instant [isoOf] wrote, as the local time the database reads back; the
/// epoch when absent, as a data-less tombstone's dates are.
DateTime fromIso(Object? value) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  return (parsed ?? DateTime.fromMillisecondsSinceEpoch(0)).toLocal();
}

/// An instant the backup writes as epoch milliseconds, read back; the epoch
/// when absent.
DateTime fromMs(Object? value) =>
    DateTime.fromMillisecondsSinceEpoch(value is int ? value : 0);
