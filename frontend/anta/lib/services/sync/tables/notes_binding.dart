import '../../../constants/json_keys.dart';
import '../../../database/database.dart';
import '../../../models/item_label.dart';
import '../sync_gateway.dart';
import '../sync_table_binding.dart';

/// `notes` on the wire: the note map of `BackupService.exportAllData`, the
/// body under `content` — a note and its chunks are one document (D14) —
/// plus the folder map's `position`, which the backup leaves to the restore
/// but two devices must agree on. Dates cross as epoch milliseconds under
/// `createdAtMs` / `updatedAtMs`, as for folders.
///
/// Preview, length, chunk count and compression are derived from the body
/// on arrival, so only `preview` crosses, as the backup writes it.
final class NotesBinding extends SyncTableBinding<Note> {
  const NotesBinding();

  @override
  String get table => 'notes';

  @override
  SyncInvalidation get invalidation => SyncInvalidation.notes;

  @override
  Future<List<Note>> loadByKeys(AppDatabase db, Iterable<String> rowKeys) =>
      db.noteDao.getByIdsIncludingDeleted(rowKeys.toList());

  @override
  String rowKeyOf(Note row) => row.id;

  @override
  Future<SyncEnvelope> encode(
    AppDatabase db,
    Note row, {
    required String boundUid,
  }) async {
    final content = row.isDeleted
        ? null
        : await db.contentChunkDao.loadContent(row.id);
    return envelopeOf(
      table: table,
      rowKey: row.id,
      hlc: row.hlcTimestamp,
      deviceId: row.deviceId,
      version: row.version,
      isDeleted: row.isDeleted,
      ownerId: row.ownerId ?? boundUid,
      data: () => {
        JsonKeys.id: row.id,
        JsonKeys.folderId: row.folderId,
        JsonKeys.title: row.title,
        JsonKeys.content: content,
        JsonKeys.preview: row.preview,
        'createdAtMs': row.createdAt.millisecondsSinceEpoch,
        'updatedAtMs': row.updatedAt.millisecondsSinceEpoch,
        JsonKeys.label: ItemLabel.fromStorage(row.label).storageName,
        if (row.ownerId != null) JsonKeys.ownerId: row.ownerId,
        'position': row.position,
      },
    );
  }

  @override
  Note decode(SyncEnvelope envelope) {
    final f = WireFields(envelope)..expectSame(JsonKeys.id, envelope.rowKey);
    return Note(
      id: envelope.rowKey,
      folderId: f.field<String>(JsonKeys.folderId, ''),
      title: f.field<String>(JsonKeys.title, ''),
      // Read leniently where every other v43 column is strict: `_withBody`
      // recomputes the preview from the body, so holding a live document to
      // it would park a row for a value the merge discards (R70). It stays
      // in `encode` for backup-format parity.
      preview: f.nullable<String>(JsonKeys.preview) ?? '',
      contentLength: 0,
      chunkCount: 0,
      isCompressed: false,
      position: f.field<int>('position', 0),
      label: ItemLabel.fromName(
        f.field<String>(JsonKeys.label, ItemLabel.none.storageName),
      ).storageValue,
      createdAt: f.fieldMs('createdAtMs'),
      updatedAt: f.fieldMs('updatedAtMs'),
      hlcTimestamp: envelope.hlc,
      deviceId: envelope.deviceId,
      version: envelope.version,
      isDeleted: isTombstone(envelope),
      deletedAt: deletedAtOf(envelope),
      ownerId: envelope.ownerId,
    );
  }

  /// The body an envelope carries, null for a tombstone. A live note without
  /// one is refused like any missing field: an empty body would replace the
  /// real text here.
  String? contentOf(SyncEnvelope envelope) {
    if (isTombstone(envelope)) return null;
    return WireFields(envelope).field<String>(JsonKeys.content, '');
  }

  @override
  Future<MergeOutcome> mergeRemote(
    AppDatabase db,
    SyncEnvelope envelope, {
    String? floor,
  }) {
    return db.noteDao.mergeNoteDocument(
      decode(envelope),
      contentOf(envelope),
      floor: floor,
    );
  }
}
