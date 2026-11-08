import '../../../constants/json_keys.dart';
import '../../../database/chunking/chunk_hasher.dart';
import '../../../database/crdt/crdt_write.dart';
import '../../../database/database.dart';
import '../../../models/item_label.dart';
import '../sync_gateway.dart';
import '../sync_table_binding.dart';

/// `notes` on the wire: the JSON backup's note map, as
/// `BackupService.importFromJson` reads it, with the body replaced by its
/// manifest (scalability record S6, D1 A) — `chunks`, the chunk hashes in
/// body order, each a `content_chunks` document pushed before the note, and
/// `bodyHash`, the [ChunkHasher] hash of the whole body — plus the folder
/// map's `position`, which the backup leaves to the restore but two devices
/// must agree on. Dates cross as epoch milliseconds under `createdAtMs` /
/// `updatedAtMs`, as for folders. A document an older build wrote carries
/// the body under `content` instead, and still decodes.
///
/// Preview, length, chunk count and compression are derived from the body
/// on arrival, so only `preview` crosses, as the backup writes it.
final class NotesBinding extends SyncTableBinding<Note> {
  const NotesBinding();

  /// The notes a pull page asks for: a page of bodies near the 900 KB
  /// document cap is about 45 MB at fifty, where 499 of them would outlast
  /// any call deadline on a phone's link and hold the database isolate for
  /// the whole page's transaction (scalability record S10).
  ///
  /// Manifests shrank the page's own documents to a few KB, but did not lift
  /// it (S6b): a note new to this device has its whole body read as chunks
  /// before the page, held in memory with it and stored in its one
  /// transaction. Those reads are bounded on their own: a page whose missing
  /// chunks outgrow `SyncEngine.chunkFetchBudget` is halved and pulled again,
  /// down to one note, while an edit's page reads a chunk or two at any
  /// size.
  static const int pageLimit = 50;

  @override
  String get table => 'notes';

  @override
  SyncInvalidation get invalidation => SyncInvalidation.notes;

  @override
  int? get pullPageLimit => pageLimit;

  @override
  Future<List<Note>> loadByKeys(AppDatabase db, Iterable<String> rowKeys) =>
      db.noteDao.getByIdsIncludingDeleted(rowKeys.toList());

  @override
  String rowKeyOf(Note row) => row.id;

  /// The manifest key: the chunk hashes in body order.
  static const String chunksKey = 'chunks';

  /// The manifest key: the hash of the whole body.
  static const String bodyHashKey = 'bodyHash';

  /// A note still stored as legacy fixed slices is re-cut first, under its
  /// own stamp ([ContentChunkDao.hashLegacy]), so its manifest names chunks
  /// that exist and its new chunks are queued for the same push; one that
  /// cannot be re-cut is refused, and the pusher parks it.
  @override
  Future<SyncEnvelope> encode(
    AppDatabase db,
    Note row, {
    required String boundUid,
  }) async {
    final manifest = row.isDeleted ? null : await _manifestOf(db, row);
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
        chunksKey: manifest!.chunks,
        bodyHashKey: manifest.bodyHash,
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

  /// The hashes and the body hash of [row]'s stored body, read in one
  /// transaction so a save landing between them cannot pair one body's
  /// chunks with another's hash.
  static Future<({List<String> chunks, String bodyHash})> _manifestOf(
    AppDatabase db,
    Note row,
  ) async {
    final dao = db.contentChunkDao;
    if ((await dao.hashesOf(row.id)).contains(null)) {
      await dao.hashLegacy(
        row.id,
        hlc: row.hlcTimestamp,
        deviceId: row.deviceId,
      );
    }
    return db.transaction(() async {
      final hashes = await dao.hashesOf(row.id);
      if (hashes.contains(null)) {
        throw FormatException('notes: legacy chunks are not re-cut', row.id);
      }
      return (
        chunks: hashes.cast<String>(),
        bodyHash: ChunkHasher.hash(await dao.loadContent(row.id)),
      );
    });
  }

  /// The chunk hashes the live manifests among [envelopes] name that no
  /// live row on this device holds, each once, in the order first named:
  /// what a pull reads from the space before the page merges (scalability
  /// record S6b). A manifest whose merge reads no body ([_readsNoBody],
  /// under the page's [floor]) asks for none, nor does a `chunks` the merge
  /// refuses anyway.
  static Future<List<String>> missingChunks(
    AppDatabase db,
    List<SyncEnvelope> envelopes, {
    String? floor,
  }) async {
    final manifests = [
      for (final envelope in envelopes)
        if (!isTombstone(envelope) &&
            !dataOf(envelope).containsKey(JsonKeys.content))
          envelope,
    ];
    if (manifests.isEmpty) return const [];
    final locals = {
      for (final note in await db.noteDao.getByIdsIncludingDeleted([
        for (final envelope in manifests) envelope.rowKey,
      ]))
        note.id: note,
    };
    final named = <String>{};
    for (final envelope in manifests) {
      if (_readsNoBody(db, envelope, locals[envelope.rowKey], floor)) {
        continue;
      }
      final hashes = dataOf(envelope)[chunksKey];
      if (hashes is List) named.addAll(hashes.whereType<String>());
    }
    if (named.isEmpty) return const [];
    final held = await db.contentChunkDao.heldHashes(named.toList());
    return [
      for (final hash in named)
        if (!held.contains(hash)) hash,
    ];
  }

  /// The body an envelope carries or names, null for a tombstone. A live
  /// note naming neither a body nor a manifest is refused like any missing
  /// field: an empty body would replace the real text here.
  ///
  /// A manifest's body is assembled from the chunk rows this device already
  /// holds, any note's, and the texts its pull [fetched] from the space, and
  /// held to its `bodyHash`. A chunk found in neither — the space does not
  /// hold it, or its document failed [ContentChunksBinding.textOf] — is a
  /// [FormatException], so the envelope parks with its key held back from
  /// the push and is retried at every start and build change (scalability
  /// record S6b).
  ///
  /// [asked] are the hashes the pull asked the space for, null when no
  /// fetch ran. A chunk missing that was not among them was on this device
  /// when the fetch was planned and a save replaced its row since: that is
  /// [ChunkRowsMoved], which fails the page for the next run to fetch again,
  /// never a park.
  Future<String?> bodyOf(
    AppDatabase db,
    SyncEnvelope envelope, {
    Map<String, String> fetched = const {},
    Set<String>? asked,
  }) async {
    if (isTombstone(envelope)) return null;
    final f = WireFields(envelope);
    if (dataOf(envelope).containsKey(JsonKeys.content)) {
      return f.field<String>(JsonKeys.content, '');
    }
    final hashes = _hashesOf(f);
    final bodyHash = f.field<String>(bodyHashKey, '');
    final texts = {
      ...await db.contentChunkDao.textsByHash(
        hashes.where((hash) => !fetched.containsKey(hash)),
      ),
      for (final hash in hashes) hash: ?fetched[hash],
    };
    final missing = hashes.toSet().difference(texts.keys.toSet());
    if (asked != null && !missing.every(asked.contains)) {
      throw ChunkRowsMoved(envelope.rowKey);
    }
    if (missing.isNotEmpty) {
      throw ChunksMissing(
        'notes: ${missing.length} of ${hashes.toSet().length} chunks are '
        'neither on this device nor readable in the space',
        envelope.rowKey,
      );
    }
    final body = hashes.map((hash) => texts[hash]).join();
    if (ChunkHasher.hash(body) != bodyHash) {
      throw FormatException(
        'notes: the chunks do not make the body "$bodyHashKey" names',
        envelope.rowKey,
      );
    }
    return body;
  }

  /// The manifest's hashes in body order; a non-hash refuses the document.
  static List<String> _hashesOf(WireFields f) => [
    for (final hash in f.field<List<Object?>>(chunksKey, const []))
      if (hash is String)
        hash
      else
        throw FormatException('notes: "$chunksKey" holds a non-hash'),
  ];

  /// A manifest at the stamp the local note already holds is the same write
  /// seen again — the echo of this device's own push, most often — which the
  /// merge leaves unchanged without reading a body, so none is assembled.
  ///
  /// So is one this device wrote under a newer local stamp: the merge keeps
  /// the local row and never files our own version as a copy — and the
  /// chunks it names may be gone, replaced by the save since, so assembling
  /// it would park the note and hold that save back from the push. Unless
  /// the local stamp is at or under the bind [floor]: there the older
  /// remote wins (`CrdtMerge.mergeRemoteRow`), and a merge handed no body
  /// would store an empty one, which the next edit pushes everywhere.
  static bool _readsNoBody(
    AppDatabase db,
    SyncEnvelope envelope,
    Note? local,
    String? floor,
  ) {
    if (local == null || isTombstone(envelope)) return false;
    if (dataOf(envelope).containsKey(JsonKeys.content)) return false;
    final stamp = envelope.hlc;
    final kept = local.hlcTimestamp;
    return kept == stamp ||
        (envelope.deviceId == db.deviceId &&
            kept.compareTo(stamp) > 0 &&
            (floor == null || kept.compareTo(floor) > 0));
  }

  /// [fetched] holds the chunk texts the pull read from the space for this
  /// envelope's page ([missingChunks]), [asked] the hashes it asked for
  /// ([bodyOf]); the chunks a manifest names are stored without being
  /// queued, since the space holds them.
  ///
  /// A manifest that merged at or above the local stamp retires this
  /// device's queued entries for the chunks it names: a manifest lands only
  /// after its chunks, so the space holds them, and a second device cutting
  /// over to the chunked wire would otherwise upload every chunk the first
  /// already had (scalability record S6).
  @override
  Future<MergeOutcome> mergeRemote(
    AppDatabase db,
    SyncEnvelope envelope, {
    String? floor,
    Map<String, String> fetched = const {},
    Set<String>? asked,
  }) async {
    final remote = decode(envelope);
    final local = await db.noteDao.getNoteById(remote.id);
    final manifest =
        !remote.isDeleted && !dataOf(envelope).containsKey(JsonKeys.content);
    final MergeOutcome outcome;
    if (_readsNoBody(db, envelope, local, floor)) {
      outcome = await db.noteDao.mergeNoteDocument(remote, null, floor: floor);
    } else {
      final body = await bodyOf(db, envelope, fetched: fetched, asked: asked);
      outcome = await db.noteDao.mergeNoteDocument(
        remote,
        body,
        floor: floor,
        inSpace: manifest ? _hashesOf(WireFields(envelope)).toSet() : const {},
      );
    }
    if (manifest && outcome.result != MergeResult.keptLocal) {
      final named = dataOf(envelope)[chunksKey];
      if (named is List) {
        await db.batch((b) => db.retireChunksIn(b, named.whereType<String>()));
      }
    } else if (!manifest &&
        !remote.isDeleted &&
        outcome.result == MergeResult.unchanged) {
      // This row's own write in an older build's shape, its whole body in
      // the document: the equal-stamp ack just retired the entry the wire
      // cutover queued to replace it with a manifest, so it is queued again.
      await db.syncOutboxDao.requeueRow(table, remote.id);
    }
    return outcome;
  }
}

/// A manifest names chunks neither this device nor the space holds: the
/// note parks as waiting for its text, which the Sync page says apart from
/// a document that cannot be read (scalability record S7). A
/// [FormatException], so every path that parks a malformed document parks
/// it.
final class ChunksMissing extends FormatException {
  const ChunksMissing(super.message, [super.source]);
}

/// A chunk a page's merge needed was on this device when the page's fetch
/// was planned, so it was not read from the space, and a save replaced its
/// row since. Transient: the puller fails the page, and the next run reads
/// the chunk from the space (scalability record S6b).
final class ChunkRowsMoved implements Exception {
  /// The note whose body could not be assembled.
  final String noteId;

  const ChunkRowsMoved(this.noteId);

  @override
  String toString() =>
      'ChunkRowsMoved: a chunk of $noteId was replaced during the pull';
}
