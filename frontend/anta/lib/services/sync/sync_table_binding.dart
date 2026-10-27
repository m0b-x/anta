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
  /// `FolderRepository.invalidateAll`: its per-row and per-parent caches.
  folders,

  /// `NoteRepository.invalidateAll`: its per-row and per-folder caches.
  notes,

  /// `CounterService`, whose cache holds counters and values together.
  counters,

  /// `VocabularyService`, whose cache holds vocabularies and terms together.
  vocabularies,

  /// The calendar services: events, categories, day rows, templates, filter
  /// presets and overview views.
  calendar,

  /// The alert services — event alerts, category alerts, digests — after
  /// which the device-local `alert_registrations` are reconciled.
  alerts,
}

/// How one synced table crosses the wire: the codec between its row and a
/// [SyncEnvelope], and the way into its DAO's remote merge.
///
/// The envelope's `data` is the table's backup map — the backup format is the
/// wire format — so a field the backup writes crosses under the backup's key
/// and in the backup's shape, dates excepted: they always cross as epoch
/// milliseconds (`*Ms`), the shape every calendar table's backup already
/// uses. The CRDT fields ride the envelope itself.
abstract class SyncTableBinding<R> {
  const SyncTableBinding();

  /// The SQL table name, one of `syncedTables`.
  String get table;

  /// The cache the engine refreshes once a pulled page merged rows of this
  /// table — a merge writes below every cache and tells none of them.
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

/// An envelope's data read field by field, strictly for a live row and
/// leniently for a tombstone.
///
/// A live envelope missing a required field, or carrying one of the wrong
/// type, throws a [FormatException] naming the table and the key, so the
/// engine can park that envelope instead of writing an empty row over real
/// data. A tombstone carries no data at all, so every field takes the
/// column's default and the row is stored only to be out-stamped.
final class WireFields {
  /// The SQL table, named in every refusal so a parked envelope can be traced
  /// to its table from the message alone.
  final String table;

  /// The envelope's data, empty for a tombstone that carries none.
  final Map<String, Object?> data;

  /// Whether the envelope is an upsert: only a live row is held to its
  /// fields; a tombstone takes the column defaults.
  final bool live;

  /// Refuses an empty row key, a tombstone's included: the key is all a
  /// tombstone carries, and an empty one names no row the outbox could have
  /// queued.
  WireFields(SyncEnvelope envelope)
    : table = envelope.table,
      data = dataOf(envelope),
      live = !isTombstone(envelope) {
    if (envelope.rowKey.isEmpty) {
      throw FormatException('$table: the row key is empty');
    }
  }

  /// A non-nullable column: required on a live row, [tombstoneDefault] on a
  /// tombstone.
  T field<T extends Object>(String key, T tombstoneDefault) {
    final value = data[key];
    if (value is T) return value;
    if (live) throw _bad(key, T);
    return tombstoneDefault;
  }

  /// A nullable column: absent or null is null; a value of another type is
  /// refused on a live row.
  T? nullable<T extends Object>(String key) {
    final value = data[key];
    if (value == null || value is T) return value as T?;
    if (live) throw _bad(key, T);
    return null;
  }

  /// A non-nullable date, written as epoch milliseconds.
  DateTime fieldMs(String key) =>
      DateTime.fromMillisecondsSinceEpoch(field<int>(key, 0));

  /// A nullable date, written as epoch milliseconds.
  DateTime? nullableMs(String key) {
    final ms = nullable<int>(key);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Refuses a live row whose data names another row than its key — the
  /// merge would store it under the key, apart from what it describes.
  void expectSame(String key, Object? expected) {
    if (live && data[key] != expected) {
      throw FormatException('$table: "$key" does not match the row key');
    }
  }

  FormatException _bad(String key, Type type) =>
      FormatException('$table: "$key" is missing or not a $type');
}

/// The `{eventId, day}` a day table's key names — `dayRowKey` read back. The
/// key is all a data-less tombstone carries, so identity comes from it. The
/// day follows the last `|`: it is digits only, whatever the event id holds.
///
/// An envelope key [dayEnvelopeKey] could not have written — no `|`, an
/// empty event id, a day that is not a UTC midnight in its canonical digits
/// — is a [FormatException], a tombstone's included: the merge stores the
/// row under the key it recomputes from these parts, so only a key that
/// reads back byte for byte can never be stored apart from its envelope's.
/// For a key read off this device's own outbox, [localDayKeyOf].
///
/// The midnight is the merge's share of the rule every other writer keeps
/// (`_dateOnlyUtc`): the three day facades are keyed by the normalised day,
/// so a second row for the same calendar day would make a presence mark or a
/// day description depend on the order its rows were read (R79).
({String eventId, DateTime day}) dayKeyOf(String rowKey) {
  final key = localDayKeyOf(rowKey);
  if (key.day.millisecondsSinceEpoch % Duration.millisecondsPerDay != 0) {
    throw FormatException('the day is not a UTC midnight', rowKey);
  }
  return key;
}

/// [dayKeyOf] without the midnight, for a key this device's own outbox
/// wrote.
///
/// A row whose `day` predates the rule — a legacy or imported one at a
/// *local* midnight — is keyed by the instant it holds, and the push has to
/// find it under that key to send it at all; refusing here retired its entry
/// under the bind floor and the mark, skip or day description never left
/// this device (A7 review R133). What goes on the wire is normalised by
/// [dayEnvelopeKey] instead, so no envelope carries a key [dayKeyOf]
/// refuses.
({String eventId, DateTime day}) localDayKeyOf(String rowKey) {
  final split = rowKey.lastIndexOf('|');
  final ms = split < 1 ? null : int.tryParse(rowKey.substring(split + 1));
  if (ms == null || ms.abs() > _maxEpochMs) {
    throw FormatException('not an eventId|dayMs row key', rowKey);
  }
  final key = (
    eventId: rowKey.substring(0, split),
    day: DateTime.fromMillisecondsSinceEpoch(ms),
  );
  if (dayRowKey(key.eventId, key.day) != rowKey) {
    throw FormatException('the day is not a whole second', rowKey);
  }
  return key;
}

/// The UTC midnight a day row's `day` stands for, as the epoch milliseconds
/// its envelope carries — in `dayMs` and in the key built from it.
///
/// The nearest midnight, not the floor: a row written at a *local* midnight
/// sits a few hours either side of UTC's, and the nearest one is the
/// calendar day it was written for in every zone. A row already at a UTC
/// midnight is untouched, which is every row this build writes.
int dayEnvelopeMs(DateTime day) {
  const span = Duration.millisecondsPerDay;
  final shifted = dayMs(day) + span ~/ 2;
  return shifted - shifted % span;
}

/// [dayEnvelopeMs] as the row key an envelope carries, which [dayKeyOf]
/// reads back. The row and the outbox entry naming it keep their own key.
String dayEnvelopeKey(String eventId, DateTime day) =>
    '$eventId|${dayEnvelopeMs(day)}';

/// The largest epoch-milliseconds magnitude a [DateTime] holds.
const int _maxEpochMs = 8640000000000000;
