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
  Future<List<Note>> loadByKeys(AppDatabase db, Iterable<String> rowKeys) {
    final keys = rowKeys.toList(growable: false);
    if (keys.isEmpty) return Future.value(const []);
    return (db.select(db.notes)..where((n) => n.id.isIn(keys))).get();
  }

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
    final data = dataOf(envelope);
    return Note(
      id: envelope.rowKey,
      folderId: data[JsonKeys.folderId] as String? ?? '',
      title: data[JsonKeys.title] as String? ?? '',
      preview: data[JsonKeys.preview] as String? ?? '',
      contentLength: 0,
      chunkCount: 0,
      isCompressed: false,
      position: data['position'] as int? ?? 0,
      label: ItemLabel.fromName(data[JsonKeys.label] as String?).storageValue,
      createdAt: fromMs(data['createdAtMs']),
      updatedAt: fromMs(data['updatedAtMs']),
      hlcTimestamp: envelope.hlc,
      deviceId: envelope.deviceId,
      version: envelope.version,
      isDeleted: isTombstone(envelope),
      deletedAt: deletedAtOf(envelope),
      ownerId: envelope.ownerId,
    );
  }

  /// The body an envelope carries, `''` for a live note without one.
  String? contentOf(SyncEnvelope envelope) {
    if (isTombstone(envelope)) return null;
    return dataOf(envelope)[JsonKeys.content] as String? ?? '';
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
