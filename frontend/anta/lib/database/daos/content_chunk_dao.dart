import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/content_chunks_table.dart';
import '../crdt/hlc.dart';
import '../../utils/compression_utils.dart';

part 'content_chunk_dao.g.dart';

@DriftAccessor(tables: [ContentChunks])
class ContentChunkDao extends DatabaseAccessor<AppDatabase>
    with _$ContentChunkDaoMixin {
  static const int defaultChunkSize = 10000;
  static const int compressionThreshold = 5000;

  ContentChunkDao(super.db);

  Future<List<ContentChunk>> getChunksForNote(String noteId) {
    return (select(contentChunks)
          ..where((c) => c.noteId.equals(noteId) & c.isDeleted.equals(false))
          ..orderBy([(c) => OrderingTerm.asc(c.chunkIndex)]))
        .get();
  }

  Future<ContentChunk?> getChunk(String noteId, int chunkIndex) {
    return (select(contentChunks)..where(
          (c) =>
              c.noteId.equals(noteId) &
              c.chunkIndex.equals(chunkIndex) &
              c.isDeleted.equals(false),
        ))
        .getSingleOrNull();
  }

  Future<int> getChunkCount(String noteId) async {
    final countExp = contentChunks.id.count();
    final query = selectOnly(contentChunks)
      ..addColumns([countExp])
      ..where(
        contentChunks.noteId.equals(noteId) &
            contentChunks.isDeleted.equals(false),
      );

    final result = await query.getSingle();
    return result.read(countExp) ?? 0;
  }

  Future<String> loadContent(String noteId) async {
    final chunks = await getChunksForNote(noteId);

    if (chunks.isEmpty) return '';

    final buffer = StringBuffer();
    for (final chunk in chunks) {
      if (chunk.isCompressed) {
        buffer.write(CompressionUtils.decompressFromBase64(chunk.content));
      } else {
        buffer.write(chunk.content);
      }
    }

    return buffer.toString();
  }

  Future<void> saveContent({
    required String noteId,
    required String content,
  }) async {
    // Split new content into raw (unprocessed) slices.
    final rawSlices = _splitRaw(content);
    final newCount = rawSlices.length;

    // Fetch existing chunks ordered by chunkIndex.
    final existing = await getChunksForNote(noteId);

    // Fast path: nothing changed in chunk count, check content equality.
    // Build a map of old chunks by index for O(1) lookup.
    final oldByIndex = <int, ContentChunk>{};
    for (final chunk in existing) {
      oldByIndex[chunk.chunkIndex] = chunk;
    }

    // Collect DB operations.
    final toInsert = <ContentChunksCompanion>[];
    final toUpdate = <ContentChunksCompanion>[];
    final toDeleteIds = <String>[];

    for (int i = 0; i < newCount; i++) {
      final rawContent = rawSlices[i];
      final old = oldByIndex[i];

      if (old != null) {
        // Compare raw content against what's stored.
        // For uncompressed chunks the stored content IS the raw text.
        // For compressed chunks we must decompress to compare.
        final oldRaw = old.isCompressed
            ? CompressionUtils.decompressFromBase64(old.content)
            : old.content;

        if (oldRaw == rawContent) {
          continue; // Chunk unchanged — skip.
        }

        // Chunk changed — process and update.
        final shouldCompress = rawContent.length > compressionThreshold;
        final processedContent = shouldCompress
            ? CompressionUtils.compressToBase64(rawContent)
            : rawContent;
        final hlc = db.generateHlc();

        toUpdate.add(
          ContentChunksCompanion(
            id: Value(old.id),
            noteId: Value(old.noteId),
            chunkIndex: Value(old.chunkIndex),
            content: Value(processedContent),
            isCompressed: Value(shouldCompress),
            hlcTimestamp: Value(hlc),
            deviceId: Value(db.deviceId),
            version: const Value(1),
            isDeleted: const Value(false),
          ),
        );
      } else {
        // New chunk at this index — insert.
        final shouldCompress = rawContent.length > compressionThreshold;
        final processedContent = shouldCompress
            ? CompressionUtils.compressToBase64(rawContent)
            : rawContent;
        final hlc = db.generateHlc();

        toInsert.add(
          ContentChunksCompanion(
            id: Value('${noteId}_chunk_$i'),
            noteId: Value(noteId),
            chunkIndex: Value(i),
            content: Value(processedContent),
            isCompressed: Value(shouldCompress),
            hlcTimestamp: Value(hlc),
            deviceId: Value(db.deviceId),
            version: const Value(1),
            isDeleted: const Value(false),
          ),
        );
      }
    }

    // Chunks beyond the new count need to be removed.
    for (final old in existing) {
      if (old.chunkIndex >= newCount) {
        toDeleteIds.add(old.id);
      }
    }

    // Nothing changed at all — skip the DB round-trip entirely.
    if (toInsert.isEmpty && toUpdate.isEmpty && toDeleteIds.isEmpty) {
      return;
    }

    // Apply all changes in a single batch for atomicity and speed.
    await batch((b) {
      if (toInsert.isNotEmpty) {
        b.insertAll(contentChunks, toInsert);
      }

      for (final companion in toUpdate) {
        b.replace(contentChunks, companion);
      }

      for (final id in toDeleteIds) {
        b.deleteWhere(contentChunks, (c) => c.id.equals(id));
      }
    });
  }

  /// Splits [content] into raw string slices of [defaultChunkSize] characters.
  /// No compression or processing — just the plain text for each chunk position.
  List<String> _splitRaw(String content) {
    if (content.isEmpty) return const [];

    final slices = <String>[];
    int position = 0;
    while (position < content.length) {
      final end = (position + defaultChunkSize).clamp(0, content.length);
      slices.add(content.substring(position, end));
      position = end;
    }
    return slices;
  }

  /// Soft delete chunks for CRDT sync (marks as deleted but preserves for sync)
  Future<void> softDeleteChunksForNote(String noteId) async {
    final hlc = db.generateHlc();
    await (update(contentChunks)..where((c) => c.noteId.equals(noteId))).write(
      ContentChunksCompanion(
        isDeleted: const Value(true),
        hlcTimestamp: Value(hlc),
        deviceId: Value(db.deviceId),
      ),
    );
  }

  /// Hard delete chunks (used when replacing content locally)
  Future<void> hardDeleteChunksForNote(String noteId) async {
    await (delete(contentChunks)..where((c) => c.noteId.equals(noteId))).go();
  }

  @Deprecated('Use softDeleteChunksForNote or hardDeleteChunksForNote instead')
  Future<void> deleteChunksForNote(String noteId) async {
    await hardDeleteChunksForNote(noteId);
  }

  Future<List<ContentChunk>> getChunksSince(String hlcTimestamp) {
    return (select(
      contentChunks,
    )..where((c) => c.hlcTimestamp.isBiggerThanValue(hlcTimestamp))).get();
  }

  Future<void> mergeChunk(ContentChunk remote) async {
    final local = await (select(
      contentChunks,
    )..where((c) => c.id.equals(remote.id))).getSingleOrNull();

    if (local == null) {
      await into(contentChunks).insert(
        ContentChunksCompanion(
          id: Value(remote.id),
          noteId: Value(remote.noteId),
          chunkIndex: Value(remote.chunkIndex),
          content: Value(remote.content),
          isCompressed: Value(remote.isCompressed),
          hlcTimestamp: Value(remote.hlcTimestamp),
          deviceId: Value(remote.deviceId),
          version: Value(remote.version),
          isDeleted: Value(remote.isDeleted),
        ),
      );
      return;
    }

    final localHlc = HlcTimestamp.parse(local.hlcTimestamp);
    final remoteHlc = HlcTimestamp.parse(remote.hlcTimestamp);

    if (remoteHlc > localHlc) {
      await (update(contentChunks)..where((c) => c.id.equals(remote.id))).write(
        ContentChunksCompanion(
          content: Value(remote.content),
          isCompressed: Value(remote.isCompressed),
          hlcTimestamp: Value(remote.hlcTimestamp),
          deviceId: Value(remote.deviceId),
          version: Value(remote.version),
          isDeleted: Value(remote.isDeleted),
        ),
      );
      db.hlc.update(remoteHlc);
    }
  }

  Future<ContentStats> getContentStats(String noteId) async {
    final chunks = await getChunksForNote(noteId);

    int compressedSize = 0;
    int compressedChunks = 0;

    for (final chunk in chunks) {
      compressedSize += chunk.content.length;
      if (chunk.isCompressed) {
        compressedChunks++;
      }
    }

    final content = await loadContent(noteId);

    return ContentStats(
      noteId: noteId,
      totalSize: content.length,
      compressedSize: compressedSize,
      chunkCount: chunks.length,
      compressedChunkCount: compressedChunks,
    );
  }
}

class ContentStats {
  final String noteId;
  final int totalSize;
  final int compressedSize;
  final int chunkCount;
  final int compressedChunkCount;

  const ContentStats({
    required this.noteId,
    required this.totalSize,
    required this.compressedSize,
    required this.chunkCount,
    required this.compressedChunkCount,
  });

  double get compressionRatio =>
      totalSize > 0 ? compressedSize / totalSize : 1.0;
}
