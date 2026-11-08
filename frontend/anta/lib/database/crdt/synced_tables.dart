import 'package:drift/drift.dart';

/// One table whose rows travel between devices: every one carries
/// `is_deleted`, `hlc_timestamp` and `owner_id`.
final class SyncedTable {
  /// The SQL table name, which is also the table a queued row names.
  final String name;

  /// The SQL expression that builds a row's key from its columns.
  ///
  /// It must equal the key a local write queues byte for byte — `id`,
  /// `counterValueRowKey` or `dayRowKey` in `crdt_write.dart` — or a row
  /// queued both ways would sit in the queue twice and a remote document
  /// would be addressed under two ids. The day tables store unix seconds,
  /// hence `day * 1000`: the helper's epoch milliseconds.
  final String rowKeySql;

  /// Whether the key is a hash of the row's content rather than its id:
  /// several rows — one per note holding the same text — share one key and
  /// one document, which is immutable. Only a live row with a key travels:
  /// a row deleted here is no reason to delete the document another note
  /// still names, and no merge ever re-queues one (scalability record S6).
  final bool contentAddressed;

  const SyncedTable(
    this.name, {
    this.rowKeySql = 'id',
    this.contentAddressed = false,
  });

  /// The rows a re-seed of the queue reads for the bound account, its one
  /// `?`, as an SQL condition: those no account owns or that account does,
  /// never another's (D16). A chunk row carries no owner of its own — it is
  /// local storage of a note's body — so it goes by its note's: a chunk of
  /// a note another account owns is that account's text.
  String get queuedRowsSql => contentAddressed
      ? '$rowKeySql IS NOT NULL AND is_deleted = 0 AND note_id IN '
            '(SELECT id FROM notes WHERE owner_id IS NULL OR owner_id = ?)'
      : '(owner_id IS NULL OR owner_id = ?)';
}

const String _dayKey = "event_id || '|' || (day * 1000)";

/// The `WHERE` term for the rows a wipe may touch (D13, D17): those no
/// account owns yet and, when [ownerUid] is the bound account, its own —
/// never another account's, which this device holds but did not author.
({String sql, List<Variable<Object>> variables}) ownedRowsWhere(
  String? ownerUid,
) {
  return ownerUid == null
      ? (sql: 'owner_id IS NULL', variables: const [])
      : (
          sql: '(owner_id IS NULL OR owner_id = ?)',
          variables: [Variable<String>(ownerUid)],
        );
}

/// Every synced table, so a pass over all of them — re-queueing at bind,
/// the highest stamp in the database — cannot forget one.
/// `test/database/sync_outbox_requeue_test.dart` fails when a table with an
/// `hlc_timestamp` column is missing here.
const List<SyncedTable> syncedTables = [
  SyncedTable('folders'),
  SyncedTable('notes'),
  // A note body's chunks, one document per distinct text (D1 A): a NULL
  // hash is a legacy slice, re-cut before its note's manifest is pushed.
  SyncedTable(
    'content_chunks',
    rowKeySql: 'content_hash',
    contentAddressed: true,
  ),
  SyncedTable('counters'),
  SyncedTable('counter_values', rowKeySql: "counter_id || '|' || note_id"),
  SyncedTable('calendar_events'),
  SyncedTable('calendar_categories'),
  SyncedTable('calendar_category_alerts'),
  SyncedTable('calendar_category_profiles'),
  SyncedTable('calendar_event_occurrences', rowKeySql: _dayKey),
  SyncedTable('calendar_event_absences', rowKeySql: _dayKey),
  SyncedTable('calendar_event_skips', rowKeySql: _dayKey),
  SyncedTable('calendar_event_alerts'),
  SyncedTable('calendar_event_templates'),
  SyncedTable('calendar_filter_presets'),
  SyncedTable('overview_views'),
  SyncedTable('event_digests'),
  SyncedTable('vocabularies'),
  SyncedTable('vocabulary_items'),
];
