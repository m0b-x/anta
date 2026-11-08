import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import '../../../database/chunking/chunk_hasher.dart';
import '../../../database/daos/content_chunk_dao.dart';
import '../../../database/database.dart';
import '../../../utils/compression_utils.dart';
import '../sync_gateway.dart';
import '../sync_table_binding.dart';

/// `content_chunks` on the wire (scalability record S6, D1 A): one immutable
/// document per distinct chunk text, keyed by its `ChunkHasher` hash, with
/// data `{hash, gz, length}` — the text gzip'd as UTF-8 under `gz`, a bytes
/// field, and its length in code units. A note's document names its chunks
/// by hash, in order.
///
/// Pushed only by this build: a run never pulls the table, and a chunk row
/// deleted here never becomes a tombstone — the space keeps every chunk a
/// manifest, anywhere, may still name.
final class ContentChunksBinding extends SyncTableBinding<ContentChunk> {
  const ContentChunksBinding();

  /// The most `gz` may hold, as `firestore.rules` bounds it: the largest
  /// chunk the cutter makes, 16,384 code units, is at most 49,152 bytes of
  /// UTF-8 before gzip, which adds a few bytes to text it cannot shrink.
  static const int maxGzBytes = 65536;

  /// The data keys of a chunk document, which `firestore.rules` names too:
  /// the hash, the same as the document id; the text gzip'd as UTF-8, a
  /// bytes field; the text's length in code units.
  static const String hashKey = 'hash';
  static const String gzKey = 'gz';
  static const String lengthKey = 'length';

  @override
  String get table => 'content_chunks';

  @override
  SyncInvalidation get invalidation => SyncInvalidation.notes;

  @override
  bool get pulls => false;

  @override
  Future<List<ContentChunk>> loadByKeys(
    AppDatabase db,
    Iterable<String> rowKeys,
  ) => db.contentChunkDao.newestByHashes(rowKeys.toList());

  @override
  String rowKeyOf(ContentChunk row) => row.contentHash!;

  /// Refuses a row whose text no longer hashes to its key: the document id
  /// is the hash, so a wrong text pushed under it would stand for that
  /// chunk on every device, in every note that names it, for good.
  @override
  Future<SyncEnvelope> encode(
    AppDatabase db,
    ContentChunk row, {
    required String boundUid,
  }) async {
    final hash = row.contentHash!;
    final text = ContentChunkDao.textOf(row);
    if (ChunkHasher.hash(text) != hash) {
      throw FormatException('content_chunks: the text does not match', hash);
    }
    // A stored gzip is already gzip(UTF-8), the wire's form.
    final gz = row.isCompressed
        ? base64Decode(row.content)
        : CompressionUtils.compress(text);
    if (gz.length > maxGzBytes) {
      throw FormatException('content_chunks: over $maxGzBytes bytes', hash);
    }
    return envelopeOf(
      table: table,
      rowKey: hash,
      hlc: row.hlcTimestamp,
      deviceId: row.deviceId,
      version: row.version,
      isDeleted: false,
      ownerId: row.ownerId ?? boundUid,
      data: () => {hashKey: hash, gzKey: gz, lengthKey: text.length},
    );
  }

  /// The text a chunk document carries, held to its key: a `gz` that is not
  /// bytes, does not inflate, or inflates to another length or hash is a
  /// [FormatException] — no body is ever assembled from it.
  static String textOf(SyncEnvelope envelope) {
    final f = WireFields(envelope)..expectSame(hashKey, envelope.rowKey);
    final gz = f.field<Uint8List>(gzKey, Uint8List(0));
    final length = f.field<int>(lengthKey, 0);
    final String text;
    try {
      text = utf8.decode(gzip.decode(gz));
    } on Object catch (error) {
      throw FormatException(
        'content_chunks: "$gzKey" does not inflate: $error',
      );
    }
    if (text.length != length || ChunkHasher.hash(text) != envelope.rowKey) {
      throw FormatException(
        'content_chunks: the text does not match',
        envelope.rowKey,
      );
    }
    return text;
  }

  /// Not pulled by this build ([pulls]).
  @override
  ContentChunk decode(SyncEnvelope envelope) =>
      throw UnsupportedError('content_chunks is not pulled by this build');

  /// Not pulled by this build ([pulls]).
  @override
  Future<MergeOutcome> mergeRemote(
    AppDatabase db,
    SyncEnvelope envelope, {
    String? floor,
  }) => throw UnsupportedError('content_chunks is not pulled by this build');
}
