import '../../../constants/json_keys.dart';
import '../../../database/chunking/chunk_hasher.dart';
import '../../../database/crdt/crdt_merge.dart';
import '../../../database/crdt/crdt_write.dart';
import '../../../database/crdt/hlc.dart';
import '../../../database/daos/content_chunk_dao.dart'
    show ContentChunkDao, EncodedBody;
import '../../../database/daos/sync_dao.dart';
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
  /// before the page, held in memory with it and stored by its transaction —
  /// in parts past `SyncEngine.pullBodyBudget`. Those reads are bounded on
  /// their own: a page whose missing chunks outgrow
  /// `SyncEngine.chunkFetchBudget` is halved and pulled again, down to one
  /// note, while an edit's page reads a chunk or two at any size.
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

  /// A note is shared as the folder it lies in is: by that folder's mark or
  /// the nearest one above it.
  @override
  Future<Map<String, String>> sharedPairs(
    AppDatabase db,
    List<Note> rows,
  ) async {
    final folders = await db.folderDao.sharedPairsOf({
      for (final row in rows) row.folderId,
    });
    return {for (final row in rows) row.id: ?folders[row.folderId]};
  }

  @override
  Future<Map<String, String>> shareStamps(
    AppDatabase db,
    List<Note> rows,
  ) async {
    final folders = await db.folderDao.shareStampsOf({
      for (final row in rows) row.folderId,
    });
    return {for (final row in rows) row.id: ?folders[row.folderId]};
  }

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

  /// The hashes and the body hash of [row]'s stored body, both from the
  /// chunk rows one statement read, so a save landing meanwhile cannot pair
  /// one body's chunks with another's hash. No transaction: the body is
  /// decompressed and hashed after the read ([ContentChunkDao.bodyHashOf]),
  /// and a cutover's drain does that for every note, which would hold the
  /// browser's queries behind each whole body.
  static Future<({List<String> chunks, String bodyHash})> _manifestOf(
    AppDatabase db,
    Note row,
  ) async {
    final dao = db.contentChunkDao;
    var rows = await dao.getChunksForNote(row.id);
    if (rows.any((chunk) => chunk.contentHash == null)) {
      await dao.hashLegacy(
        row.id,
        hlc: row.hlcTimestamp,
        deviceId: row.deviceId,
      );
      rows = await dao.getChunksForNote(row.id);
      if (rows.any((chunk) => chunk.contentHash == null)) {
        throw FormatException('notes: legacy chunks are not re-cut', row.id);
      }
    }
    return (
      chunks: [for (final chunk in rows) chunk.contentHash!],
      bodyHash: await ContentChunkDao.bodyHashOf(
        rows,
        units: row.contentLength,
      ),
    );
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

  /// The bodies of a pull page's [envelopes], assembled before its
  /// transaction — one entry per envelope, null where the merge reads no
  /// body: each body a merge reads ([_readsNoBody], against the local rows
  /// read here) assembled by [bodyOf], and marked when the merge will store
  /// it ([CrdtMerge.remoteWrites]), which is what the page's parts are cut by
  /// ([PreparedNoteBody.storedLength]). Nothing is cut or encoded here:
  /// [readyBodies] does that for one part at a time, so a page of big
  /// bodies never holds every cut and encoded chunk at once.
  ///
  /// A body that cannot be assembled is kept as its error, which
  /// [mergeRemote] raises where [bodyOf] would — inside the envelope's
  /// savepoint, so the envelope parks, or the part fails on a
  /// [ChunkRowsMoved]. [fetched] and [asked] are [bodyOf]'s.
  Future<List<PreparedNoteBody?>> prepareBodies(
    AppDatabase db,
    List<SyncEnvelope> envelopes, {
    String? floor,
    Map<String, String> fetched = const {},
    Set<String>? asked,
  }) async {
    final live = [
      for (final envelope in envelopes)
        if (!isTombstone(envelope)) envelope.rowKey,
    ];
    if (live.isEmpty) return List.filled(envelopes.length, null);
    final locals = {
      for (final note in await db.noteDao.getByIdsIncludingDeleted(live))
        note.id: note,
    };
    final prepared = List<PreparedNoteBody?>.filled(envelopes.length, null);
    for (final (i, envelope) in envelopes.indexed) {
      if (isTombstone(envelope)) continue;
      final local = locals[envelope.rowKey];
      if (_readsNoBody(db, envelope, local, floor)) continue;
      try {
        final body = await bodyOf(db, envelope, fetched: fetched, asked: asked);
        prepared[i] = PreparedNoteBody._(
          body!,
          local: local,
          stores: CrdtMerge.remoteWrites(
            remoteHlc: envelope.hlc,
            localHlc: local?.hlcTimestamp,
            floor: floor,
          ),
        );
      } catch (error, stack) {
        prepared[i] = PreparedNoteBody._failed(error, stack);
      }
    }
    return prepared;
  }

  /// One part of a page as [prepareBodies] left it, made ready for the
  /// part's transaction: each body the merge will store cut, with its
  /// chunks encoded, in one isolate hop for the part
  /// ([ContentChunkDao.encodeBodies]). Drift's executor is exclusive while
  /// the transaction runs, so the browser's and the calendar's queries wait
  /// behind it: it must hold SQL alone, never the hashing and gzip of big
  /// bodies.
  ///
  /// A body whose cut or encoding throws is kept as its error, which the
  /// merge raises inside the envelope's savepoint, so that envelope parks
  /// and the part's others merge: the part's hop failing is retried one
  /// body at a time to find it.
  ///
  /// A remote that overwrites a local edit still queued carries that local
  /// text too ([_unpushedTexts]), which the conflict check would otherwise
  /// decompress inside the transaction — for every note another device
  /// edited, on the run that cuts over to the chunked wire, which queues
  /// every note.
  Future<List<PreparedNoteBody?>> readyBodies(
    AppDatabase db,
    List<SyncEnvelope> envelopes,
    List<PreparedNoteBody?> prepared, {
    String? floor,
  }) async {
    final stored = [
      for (final (i, body) in prepared.indexed)
        if (body != null && body._stores && body._error == null) i,
    ];
    if (stored.isEmpty) return prepared;
    final encoded = await _encodeEach(db, [
      for (final i in stored)
        (noteId: envelopes[i].rowKey, text: prepared[i]!.body),
    ]);
    final unpushed = await _unpushedTexts(db, [
      for (final (j, i) in stored.indexed)
        if (prepared[i]!._local case final local?
            when encoded[j].body != null &&
                !local.isDeleted &&
                envelopes[i].hlc.compareTo(local.hlcTimestamp) > 0 &&
                (floor == null || local.hlcTimestamp.compareTo(floor) > 0))
          local,
    ]);
    final ready = [...prepared];
    for (final (j, i) in stored.indexed) {
      final (:body, :error, :stack) = encoded[j];
      ready[i] = body != null
          ? PreparedNoteBody._(
              prepared[i]!.body,
              stores: true,
              ready: body,
              localBody: unpushed[envelopes[i].rowKey],
            )
          : PreparedNoteBody._failed(error!, stack!);
    }
    return ready;
  }

  /// [ContentChunkDao.encodeBodies] for [bodies], each answered with its
  /// encoding or the error it raised: one hop for all of them, and only
  /// when that hop throws, one per body, so one bad body costs the others
  /// nothing but the retry.
  static Future<List<({EncodedBody? body, Object? error, StackTrace? stack})>>
  _encodeEach(
    AppDatabase db,
    List<({String noteId, String text})> bodies,
  ) async {
    try {
      return [
        for (final body in await db.contentChunkDao.encodeBodies(bodies))
          (body: body, error: null, stack: null),
      ];
    } catch (_) {
      return [for (final body in bodies) await _encodeOne(db, body)];
    }
  }

  static Future<({EncodedBody? body, Object? error, StackTrace? stack})>
  _encodeOne(AppDatabase db, ({String noteId, String text}) body) async {
    try {
      final [encoded] = await db.contentChunkDao.encodeBodies([body]);
      return (body: encoded, error: null, stack: null);
    } catch (error, stack) {
      return (body: null, error: error, stack: stack);
    }
  }

  /// The text of each of [locals] that has an entry queued at or below its
  /// stamp — an edit not pushed yet, the condition under which
  /// `NoteDao.mergeNoteDocument` compares it with a newer remote — keyed by
  /// note id, with the stamp the row carried when [locals] were read. The
  /// texts are read after the rows, so a save landing in between leaves a
  /// text newer than its stamp, and the merge, finding another stamp on
  /// the row, reads the text again. A note whose chunks do not decode is
  /// left out, for the merge to fail on as it does today.
  ///
  /// So is a note whose stamp is its `note_seen` value, and one whose entry
  /// only re-sends a version the space holds (`SyncOutbox.republish`): the
  /// merge files no copy of either, and on the run that cuts over to the
  /// chunked wire, which queues every note, each text read here would be
  /// read for nothing.
  Future<Map<String, ({String hlc, String text})>> _unpushedTexts(
    AppDatabase db,
    List<Note> locals,
  ) async {
    if (locals.isEmpty) return const {};
    final queued = await db.syncOutboxDao.pendingKeys(table, [
      for (final local in locals) local.id,
    ], unpushedOnly: true);
    final pending = [
      for (final local in locals)
        if (queued[local.id] case final entry?
            when entry.hlc.compareTo(local.hlcTimestamp) <= 0)
          local,
    ];
    if (pending.isEmpty) return const {};
    final seen = await db.syncDao.valuesOf([
      for (final local in pending) SyncDao.keyNoteSeen(local.id),
    ]);
    final unpushed = [
      for (final local in pending)
        if (seen[SyncDao.keyNoteSeen(local.id)] != local.hlcTimestamp) local,
    ];
    if (unpushed.isEmpty) return const {};
    final texts = await db.contentChunkDao.loadContentForNotes([
      for (final local in unpushed) local.id,
    ]);
    return {
      for (final local in unpushed)
        if (texts[local.id] case final text?)
          local.id: (hlc: local.hlcTimestamp, text: text),
    };
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
  ///
  /// [prepared] is the envelope's entry from [readyBodies]; without one
  /// the body is assembled here, as a merge outside a pull page does. The
  /// merge decides against the local row it reads now: one a save changed
  /// since the preparation may read no body after all, or one the
  /// preparation skipped — assembled here then, against the page's
  /// [fetched] and [asked], so a chunk that save replaced fails the part
  /// ([ChunkRowsMoved]) rather than parking the note.
  @override
  Future<MergeOutcome> mergeRemote(
    AppDatabase db,
    SyncEnvelope envelope, {
    String? floor,
    Map<String, String> fetched = const {},
    Set<String>? asked,
    PreparedNoteBody? prepared,
  }) async {
    final remote = decode(envelope);
    final local = await db.noteDao.getNoteById(remote.id);
    final manifest =
        !remote.isDeleted && !dataOf(envelope).containsKey(JsonKeys.content);
    final MergeOutcome outcome;
    if (_readsNoBody(db, envelope, local, floor)) {
      outcome = await db.noteDao.mergeNoteDocument(remote, null, floor: floor);
    } else {
      final failure = prepared?._error;
      if (failure != null) {
        Error.throwWithStackTrace(failure, prepared!._stack!);
      }
      final body = prepared != null
          ? prepared.body
          : await bodyOf(db, envelope, fetched: fetched, asked: asked);
      outcome = await db.noteDao.mergeNoteDocument(
        remote,
        body,
        floor: floor,
        inSpace: manifest ? _hashesOf(WireFields(envelope)).toSet() : const {},
        ready: prepared?.ready,
        localBody: prepared?.localBody,
      );
    }
    if (manifest && outcome.result != MergeResult.keptLocal) {
      final named = dataOf(envelope)[chunksKey];
      if (named is List) {
        await db.batch((b) => db.retireChunksIn(b, named.whereType<String>()));
      }
    } else if (!manifest &&
        !remote.isDeleted &&
        outcome.result == MergeResult.unchanged &&
        // At the seed the merge acks nothing — an equal seed does not prove
        // the space holds this version — so nothing was retired to queue
        // again, and a republish would claim a version the space may lack.
        remote.hlcTimestamp != HlcTimestamp.seed.toString()) {
      // This row's own write in an older build's shape, its whole body in
      // the document: the equal-stamp ack just retired the entry the wire
      // cutover queued to replace it with a manifest, so it is queued again
      // — as a republish: the space holds this version, and a newer remote
      // overwriting it before the push loses no text.
      await db.syncOutboxDao.requeueRow(table, remote.id, republish: true);
    }
    return outcome;
  }
}

/// One envelope's body as [NotesBinding.prepareBodies] left it before the
/// page's transaction, assembled, and as [NotesBinding.readyBodies] left it
/// before its part's: cut and encoded when the merge will store it — or the
/// error assembling, cutting or encoding it raised.
final class PreparedNoteBody {
  PreparedNoteBody._(
    this.body, {
    required bool stores,
    Note? local,
    this.ready,
    this.localBody,
  }) : _stores = stores,
       _local = local,
       _error = null,
       _stack = null;

  PreparedNoteBody._failed(Object error, StackTrace stack)
    : body = '',
      ready = null,
      localBody = null,
      _stores = false,
      _local = null,
      _error = error,
      _stack = stack;

  /// The assembled body; empty for a failed one.
  final String body;

  /// [body] cut with its chunks encoded, when the merge will store it.
  final EncodedBody? ready;

  /// The local note's unpushed text this body overwrites, with the stamp
  /// the row carried when it was read: what the conflict check compares
  /// [body] with, read before the transaction.
  final ({String hlc, String text})? localBody;

  /// Whether the merge will store [body] ([CrdtMerge.remoteWrites]).
  final bool _stores;

  /// The local note as [NotesBinding.prepareBodies] read it, null when none:
  /// whose unpushed text [NotesBinding.readyBodies] reads.
  final Note? _local;

  final Object? _error;
  final StackTrace? _stack;

  /// What storing this body writes, in code units: the measure a page's
  /// write budget is spent in (`SyncEngine.pullBodyBudget`), known before
  /// anything is cut. Zero for a body the merge only compares.
  int get storedLength => _stores ? body.length : 0;
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
/// row since. Transient: the puller fails the page's part, and the next run
/// reads the page again and the chunk from the space (scalability record
/// S6b).
final class ChunkRowsMoved implements Exception {
  /// The note whose body could not be assembled.
  final String noteId;

  const ChunkRowsMoved(this.noteId);

  @override
  String toString() =>
      'ChunkRowsMoved: a chunk of $noteId was replaced during the pull';
}
