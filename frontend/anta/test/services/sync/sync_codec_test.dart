import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/chunking/body_cut.dart';
import 'package:anta/database/chunking/chunk_hasher.dart';
import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/crdt/hlc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/database/migrations/database_schema.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/category_profile_service.dart';
import 'package:anta/services/category_service.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/event_alert_service.dart';
import 'package:anta/services/event_digest_service.dart';
import 'package:anta/services/event_occurrence_service.dart';
import 'package:anta/services/event_presence_service.dart';
import 'package:anta/services/event_skip_service.dart';
import 'package:anta/services/event_template_service.dart';
import 'package:anta/services/filter_preset_service.dart';
import 'package:anta/services/overview_view_service.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_table_binding.dart';
import 'package:anta/services/sync/sync_tables.dart';
import 'package:anta/services/sync/tables/calendar_categories_binding.dart';
import 'package:anta/services/sync/tables/calendar_category_alerts_binding.dart';
import 'package:anta/services/sync/tables/calendar_category_profiles_binding.dart';
import 'package:anta/services/sync/tables/calendar_event_absences_binding.dart';
import 'package:anta/services/sync/tables/calendar_event_alerts_binding.dart';
import 'package:anta/services/sync/tables/calendar_event_occurrences_binding.dart';
import 'package:anta/services/sync/tables/calendar_event_skips_binding.dart';
import 'package:anta/services/sync/tables/calendar_event_templates_binding.dart';
import 'package:anta/services/sync/tables/calendar_events_binding.dart';
import 'package:anta/services/sync/tables/calendar_filter_presets_binding.dart';
import 'package:anta/services/sync/tables/content_chunks_binding.dart';
import 'package:anta/services/sync/tables/counter_values_binding.dart';
import 'package:anta/services/sync/tables/counters_binding.dart';
import 'package:anta/services/sync/tables/event_digests_binding.dart';
import 'package:anta/services/sync/tables/folders_binding.dart';
import 'package:anta/services/sync/tables/notes_binding.dart';
import 'package:anta/services/sync/tables/overview_views_binding.dart';
import 'package:anta/services/sync/tables/vocabularies_binding.dart';
import 'package:anta/services/sync/tables/vocabulary_items_binding.dart';
import 'package:anta/services/vocabulary_service.dart';
import 'package:anta/utils/compression_utils.dart';

import '../../database/support/db_test_support.dart';

/// Guards the wire codec of every synced table: a row encodes to the
/// envelope the outbox and the rules expect, its `data` under the backup's
/// keys, and decodes back to the same row — so a row that crosses the wire
/// and merges lands as the row that left. The calendar tables also pin the
/// strict decode: a live envelope missing a required field is refused.
void main() {
  late AppDatabase db;

  setUp(() async => db = await openTestDatabase());
  tearDown(() async => db.close());

  const hlc = '0193a0b0c0d0:0002:dev-a';
  const uid = 'uid-1';
  final created = DateTime.utc(2026, 6, 1, 8, 30).toLocal();
  final updated = DateTime.utc(2026, 6, 2, 9, 45).toLocal();
  final deletedAt = DateTime.fromMillisecondsSinceEpoch(
    HlcTimestamp.parse(hlc).wallTime,
  );

  /// Encodes [row] as the push would read it back from the table.
  Future<SyncEnvelope> encodeStored<R extends Object>(
    SyncTableBinding<R> binding,
    String key,
  ) async {
    final rows = await binding.loadByKeys(db, [key]);
    expect(rows, hasLength(1));
    return binding.encode(db, rows.single, boundUid: uid);
  }

  void expectStamps(SyncEnvelope envelope, String table, String key) {
    expect(envelope.table, table);
    expect(envelope.rowKey, key);
    expect(envelope.hlc, hlc);
    expect(envelope.deviceId, 'dev-a');
    expect(envelope.version, 5);
    expect(envelope.ownerId, uid);
  }

  void expectTombstone(SyncEnvelope envelope) {
    expect(envelope.op, OutboxOp.tombstone);
    expect(envelope.data, isNull, reason: _wireChanged);
  }

  /// [envelope]'s `data` keys against the frozen [_wireKeys] — independent
  /// of the backup and export maps the tests below also compare against, so
  /// a change there that reaches the wire cannot pass unnoticed.
  void expectWire(SyncEnvelope envelope) {
    expect(
      envelope.data!.keys.toSet(),
      _wireKeys[envelope.table],
      reason: _wireChanged,
    );
  }

  test('the space carries the wire version, never above the local one', () {
    expect(
      DatabaseSchema.syncSchemaVersion,
      48,
      reason:
          'raised only with a wire change and this file\'s snapshot; a '
          'local-only migration leaves it, or every older device pauses as '
          'appOutdated',
    );
    expect(
      DatabaseSchema.syncSchemaVersion,
      lessThanOrEqualTo(DatabaseSchema.currentVersion),
      reason: 'a wire version names a schema some build has shipped',
    );
  });

  test('the wire snapshot names every synced table', () {
    expect(_wireKeys.keys.toSet(), {
      for (final binding in syncTableBindings) binding.table,
    }, reason: _wireChanged);
  });

  /// [envelope] as a live upsert carrying [data] in place of its own.
  SyncEnvelope carrying(SyncEnvelope envelope, Map<String, Object?> data) =>
      SyncEnvelope(
        table: envelope.table,
        rowKey: envelope.rowKey,
        hlc: envelope.hlc,
        deviceId: envelope.deviceId,
        version: envelope.version,
        op: OutboxOp.upsert,
        ownerId: envelope.ownerId,
        data: data,
      );

  /// The strict decode of a stored live row under [key]: without
  /// [requiredKey], with it mistyped, or naming another row in [idKey], the
  /// envelope is refused with the table and the key named — never decoded
  /// to defaults over real data. A key this build does not know is ignored
  /// instead, the forward compatibility of §3.4 (8). [decode] stands in for
  /// the binding's own when the key is read elsewhere (a note's body).
  Future<void> expectStrict<R extends Object>(
    SyncTableBinding<R> binding,
    String key, {
    required String requiredKey,
    required String idKey,
    Object? Function(SyncEnvelope envelope)? decode,
  }) async {
    final run = decode ?? binding.decode;
    final envelope = await encodeStored(binding, key);
    final live = envelope.data!;
    final refused = throwsA(
      isA<FormatException>().having(
        (e) => e.message,
        'message',
        allOf(contains(binding.table), contains(requiredKey)),
      ),
    );

    expect(
      () => run(carrying(envelope, {...live}..remove(requiredKey))),
      refused,
    );
    expect(
      () => run(carrying(envelope, {...live, requiredKey: const []})),
      refused,
    );
    expect(
      () => binding.decode(carrying(envelope, {...live, idKey: 'another-row'})),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          allOf(contains(binding.table), contains(idKey)),
        ),
      ),
    );
    expect(() => run(carrying(envelope, const {})), throwsFormatException);
    // A column a later build added is ignored, not refused: a strict decode
    // here would brick every install already out there (R73).
    expect(
      run(carrying(envelope, {...live, 'futureColumn': 1})),
      run(carrying(envelope, live)),
    );
  }

  group('folders', () {
    const binding = FoldersBinding();
    Folder row({bool deleted = false, String? ownerId}) => Folder(
      id: 'f1',
      name: 'Training',
      parentId: 'root',
      position: 4,
      label: 3,
      createdAt: created,
      updatedAt: updated,
      noteSortOrder: 'titleAsc',
      subfolderSortOrder: 'nameDesc',
      hlcTimestamp: hlc,
      deviceId: 'dev-a',
      version: 5,
      isDeleted: deleted,
      deletedAt: deleted ? deletedAt : null,
      ownerId: ownerId,
    );

    test('a live row carries the backup folder map', () async {
      await db.into(db.folders).insert(row(ownerId: uid));

      final envelope = await encodeStored(binding, 'f1');

      expectStamps(envelope, 'folders', 'f1');
      expect(envelope.op, OutboxOp.upsert);
      expectWire(envelope);
      // The JSON backup's folder keys, dates as epoch-ms.
      expect(envelope.data!.keys.toSet(), {
        'id',
        'name',
        'parentId',
        'position',
        'createdAtMs',
        'updatedAtMs',
        'noteSortOrder',
        'subfolderSortOrder',
        'label',
        'ownerId',
      });
      expect(binding.decode(envelope), row(ownerId: uid));
    });

    test('an unowned row is pushed under the bound account', () async {
      await db.into(db.folders).insert(row());

      final envelope = await encodeStored(binding, 'f1');

      expect(envelope.ownerId, uid);
      expect(envelope.data!.containsKey('ownerId'), isFalse);
    });

    test('a tombstone carries identity and stamp only', () async {
      await db.into(db.folders).insert(row(deleted: true, ownerId: uid));

      final envelope = await encodeStored(binding, 'f1');

      expectStamps(envelope, 'folders', 'f1');
      expectTombstone(envelope);
      final decoded = binding.decode(envelope);
      expect(decoded.isDeleted, isTrue);
      expect(decoded.deletedAt, deletedAt);
      expect(decoded.hlcTimestamp, hlc);
      expect(decoded.name, isNotEmpty, reason: 'the column refuses empty');
      expect(decoded.position, 0);
      expect(decoded.label, 0);
      expect(decoded.parentId, isNull);
    });

    test('a live envelope without a valid name is refused', () async {
      await db.into(db.folders).insert(row(ownerId: uid));

      await expectStrict(binding, 'f1', requiredKey: 'name', idKey: 'id');
    });

    test('a marked row adds its mark and the mark\'s stamp and nothing '
        'else, and decodes with them (wire 47)', () async {
      await db
          .into(db.folders)
          .insert(
            row(ownerId: uid).copyWith(
              sharedPair: const Value('p1'),
              sharedStamp: const Value('0000000001:0000:a'),
            ),
          );

      final envelope = await encodeStored(binding, 'f1');

      expect(envelope.data!.keys.toSet(), {
        ..._wireKeys['folders']!,
        'sharedPair',
        'sharedStamp',
      }, reason: _wireChanged);
      expect(envelope.data!['sharedPair'], 'p1');
      expect(envelope.data!['sharedStamp'], '0000000001:0000:a');
      expect(binding.decode(envelope).sharedPair, 'p1');
      expect(binding.decode(envelope).sharedStamp, '0000000001:0000:a');
      expect(
        () => binding.decode(
          carrying(envelope, {...envelope.data!, 'sharedPair': 7}),
        ),
        throwsFormatException,
      );
    });

    test('a tombstone names no mark: a merge keeps the one the row '
        'had', () async {
      await db
          .into(db.folders)
          .insert(
            row(
              deleted: true,
              ownerId: uid,
            ).copyWith(sharedPair: const Value('p1')),
          );

      final envelope = await encodeStored(binding, 'f1');

      expectTombstone(envelope);
      expect(binding.decode(envelope).sharedPair, isNull);
    });
  });

  group('notes', () {
    const binding = NotesBinding();
    final body = List.generate(1400, (i) => 'set $i rep').join('\n');

    Future<Note> stored() => db.noteDao.createNote(
      folderId: 'f1',
      title: 'Squat log',
      preview: NoteMetadata.generatePreview(body),
      contentLength: body.length,
      chunkCount: 2,
      isCompressed: true,
      content: body,
      ownerId: uid,
    );

    /// [manifest] as a 45-build wrote it: the body under `content`.
    SyncEnvelope legacy(SyncEnvelope manifest, String text) => carrying(
      manifest,
      {...manifest.data!}
        ..remove(NotesBinding.chunksKey)
        ..remove(NotesBinding.bodyHashKey)
        ..['content'] = text,
    );

    test('a 14 KB body crosses as its manifest and is assembled again from '
        'the chunks it names', () async {
      expect(body.length, greaterThan(14 * 1000));
      final note = await stored();

      final envelope = await encodeStored(binding, note.id);

      expect(envelope.rowKey, note.id);
      expect(envelope.hlc, note.hlcTimestamp);
      expect(envelope.op, OutboxOp.upsert);
      expectWire(envelope);
      // The JSON backup's note keys, dates as epoch-ms, the body replaced
      // by its manifest, plus `position`.
      expect(envelope.data!.keys.toSet(), {
        'id',
        'folderId',
        'title',
        'chunks',
        'bodyHash',
        'preview',
        'createdAtMs',
        'updatedAtMs',
        'label',
        'ownerId',
        'position',
      });
      final hashes = await db.contentChunkDao.hashesOf(note.id);
      expect(hashes.length, greaterThan(1));
      expect(envelope.data!['chunks'], hashes);
      expect(envelope.data!['bodyHash'], ChunkHasher.hash(body));
      expect(await binding.bodyOf(db, envelope), body);

      final decoded = binding.decode(envelope);
      expect(
        decoded.copyWith(
          contentLength: note.contentLength,
          chunkCount: note.chunkCount,
          isCompressed: note.isCompressed,
        ),
        note,
        reason: 'the body columns are derived on arrival',
      );

      // Another note holding the same chunks: the body is assembled from
      // any note's rows on the receiving device.
      final other = await openTestDatabase();
      addTearDown(other.close);
      await other.noteDao.createNote(
        folderId: 'f9',
        title: 'Copy',
        content: body,
      );
      await binding.mergeRemote(other, envelope);
      expect(await other.noteDao.getNoteById(note.id), note);
      expect(await other.contentChunkDao.loadContent(note.id), body);
    });

    test('a document an older build wrote, its body under content, still '
        'lands as it left', () async {
      final note = await stored();
      final envelope = legacy(await encodeStored(binding, note.id), body);

      expect(await binding.bodyOf(db, envelope), body);
      final other = await openTestDatabase();
      addTearDown(other.close);
      await binding.mergeRemote(other, envelope);
      expect(await other.noteDao.getNoteById(note.id), note);
      expect(await other.contentChunkDao.loadContent(note.id), body);
    });

    test('a manifest naming a chunk neither this device nor the fetch holds '
        'is refused before anything is written', () async {
      final note = await stored();
      final envelope = await encodeStored(binding, note.id);
      final other = await openTestDatabase();
      addTearDown(other.close);

      await expectLater(
        binding.mergeRemote(other, envelope),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('chunks are neither on this device nor readable'),
          ),
        ),
      );
      expect(await other.noteDao.getNoteById(note.id), isNull);
    });

    test(
      'a manifest whose chunks do not make its body hash is refused',
      () async {
        final note = await stored();
        final envelope = await encodeStored(binding, note.id);

        await expectLater(
          binding.bodyOf(
            db,
            carrying(envelope, {
              ...envelope.data!,
              'bodyHash': ChunkHasher.hash('another body'),
            }),
          ),
          throwsFormatException,
        );
      },
    );

    test('the echo of a pushed manifest merges unchanged without assembling '
        'its body', () async {
      final note = await stored();
      final envelope = await encodeStored(binding, note.id);
      // Gone from this device: assembling would fail, the stamp says it
      // needs no body.
      await db.customStatement('DELETE FROM content_chunks');

      final outcome = await binding.mergeRemote(db, envelope);

      expect(outcome.result, MergeResult.unchanged);
    });

    test('a tombstone carries no body', () async {
      final note = await db.noteDao.createNote(folderId: 'f1', title: 'Gone');
      await db.noteDao.softDeleteNote(note.id);

      final envelope = await encodeStored(binding, note.id);

      expectTombstone(envelope);
      expect(await binding.bodyOf(db, envelope), isNull);
      final decoded = binding.decode(envelope);
      expect(decoded.isDeleted, isTrue);
      expect(
        decoded.deletedAt,
        DateTime.fromMillisecondsSinceEpoch(
          HlcTimestamp.parse(envelope.hlc).wallTime,
        ),
      );
      expect(decoded.title, '');
      expect(decoded.folderId, '');
    });

    test('a live envelope without a valid title is refused', () async {
      final note = await db.noteDao.createNote(folderId: 'f1', title: 'Log');

      await expectStrict(binding, note.id, requiredKey: 'title', idKey: 'id');
    });

    test('a live envelope without a preview still decodes', () async {
      final note = await db.noteDao.createNote(folderId: 'f1', title: 'Log');
      final envelope = await encodeStored(binding, note.id);

      // The merge recomputes the preview from the body, so parking a row
      // for it would cost a note a column nothing reads (R70).
      final decoded = binding.decode(
        carrying(envelope, {...envelope.data!}..remove('preview')),
      );

      expect(decoded.preview, '');
      expect(decoded.title, 'Log');
    });

    test('a live envelope without a body or a manifest is refused, never '
        'emptied', () async {
      final note = await db.noteDao.createNote(
        folderId: 'f1',
        title: 'Log',
        content: 'real text',
      );
      final envelope = await encodeStored(binding, note.id);
      final live = envelope.data!;

      for (final data in [
        {...live}..remove('chunks'),
        {...live, 'chunks': 'not a list'},
        {
          ...live,
          'chunks': [7],
        },
        {...live}..remove('bodyHash'),
        legacy(envelope, '').data!..['content'] = 7,
      ]) {
        await expectLater(
          binding.bodyOf(db, carrying(envelope, data)),
          throwsFormatException,
          reason: '$data',
        );
      }
      final bodyless = SyncEnvelope(
        table: envelope.table,
        rowKey: envelope.rowKey,
        hlc: 'ffffffffffff:0000:remote',
        deviceId: 'remote',
        version: 9,
        op: OutboxOp.upsert,
        ownerId: envelope.ownerId,
        data: {...live}..remove('chunks'),
      );
      await expectLater(
        binding.mergeRemote(db, bodyless),
        throwsFormatException,
      );
      expect(await db.contentChunkDao.loadContent(note.id), 'real text');
    });
  });

  group('content_chunks', () {
    const binding = ContentChunksBinding();
    // One chunk stored plain, one gzip'd: the cutter's chunks run 4,096 to
    // 16,384 code units and the store compresses above 5,000.
    final short = List.generate(400, (i) => 'rep $i').join(' ');
    final long = List.generate(1600, (i) => 'set $i rep').join('\n');

    /// The first chunk of a note saved with [body], and its text.
    Future<(ContentChunk, String)> chunkOf(String body) async {
      final note = await db.noteDao.createNote(
        folderId: 'f1',
        title: 'Log',
        content: body,
        ownerId: uid,
      );
      final hash = (await db.contentChunkDao.hashesOf(note.id)).first!;
      final row = (await binding.loadByKeys(db, [hash])).single;
      return (row, BodyCut.inline(body).chunkText(0));
    }

    for (final (name, body, compressed) in [
      ('a plain', short, false),
      ('a gzip\'d', long, true),
    ]) {
      test('$name chunk crosses as its gzip\'d UTF-8 under its hash and '
          'inflates back to its text', () async {
        final (row, text) = await chunkOf(body);
        expect(row.isCompressed, compressed);

        final envelope = await binding.encode(db, row, boundUid: uid);

        expect(envelope.rowKey, ChunkHasher.hash(text));
        expect(envelope.hlc, row.hlcTimestamp);
        expect(envelope.op, OutboxOp.upsert);
        expect(envelope.ownerId, uid);
        expectWire(envelope);
        expect(envelope.data!['hash'], envelope.rowKey);
        expect(envelope.data!['length'], text.length);
        final gz = envelope.data!['gz']! as Uint8List;
        expect(utf8.decode(gzip.decode(gz)), text);
        expect(gz.length, lessThan(utf8.encode(text).length));
        expect(ContentChunksBinding.textOf(envelope), text);
      });
    }

    test('a row whose text no longer matches its hash is never pushed under '
        'it', () async {
      final (row, _) = await chunkOf(short);

      await expectLater(
        binding.encode(db, row.copyWith(content: '$short!'), boundUid: uid),
        throwsFormatException,
      );
    });

    test('a document that does not inflate to its key is refused', () async {
      final (row, _) = await chunkOf(short);
      final envelope = await binding.encode(db, row, boundUid: uid);
      final live = envelope.data!;

      for (final data in [
        {...live, 'length': short.length + 1},
        {...live, 'gz': CompressionUtils.compress('$short!')},
        {...live, 'gz': Uint8List.fromList(utf8.encode(short))},
        {...live, 'gz': 'not bytes'},
        {...live, 'hash': 'another'},
      ]) {
        expect(
          () => ContentChunksBinding.textOf(carrying(envelope, data)),
          throwsFormatException,
          reason: '$data',
        );
      }
    });
  });

  group('counters', () {
    const binding = CountersBinding();
    CounterRow row({bool deleted = false}) => CounterRow(
      id: 'c1',
      name: 'Sets',
      startValue: 5,
      step: 2,
      scope: 'perNote',
      position: 3,
      isPinned: true,
      createdAt: created,
      hlcTimestamp: hlc,
      deviceId: 'dev-a',
      version: 5,
      isDeleted: deleted,
      deletedAt: deleted ? deletedAt : null,
      ownerId: uid,
    );

    test('a live row carries the backup counter map', () async {
      await db.into(db.counters).insert(row());
      final service = await CounterService.forTesting(db);
      final exported =
          (jsonDecode((await service.exportData())['counters'] as String)
                      as List)
                  .single
              as Map<String, dynamic>;

      final envelope = await encodeStored(binding, 'c1');

      expectStamps(envelope, 'counters', 'c1');
      expectWire(envelope);
      // The backup's counter map, its ISO `createdAt` as epoch-ms (F7).
      expect(envelope.data!.keys.toSet(), {
        ...exported.keys.where((k) => k != 'createdAt'),
        'createdAtMs',
        'position',
      });
      expect(envelope.data!['createdAtMs'], created.millisecondsSinceEpoch);
      expect(binding.decode(envelope), row());
    });

    test('a live envelope without a valid name is refused', () async {
      await db.into(db.counters).insert(row());

      await expectStrict(binding, 'c1', requiredKey: 'name', idKey: 'id');
    });

    test('a scope this build does not know crosses verbatim', () async {
      await db.into(db.counters).insert(row().copyWith(scope: 'session'));

      final envelope = await encodeStored(binding, 'c1');

      // Rewriting it to `global` here would hand the other device a value
      // the one that wrote it never stored (R66); the read stays lenient,
      // so this build still stores a scope it can hold.
      expect(envelope.data!['counterScope'], 'session');
      expect(binding.decode(envelope).scope, 'global');
    });

    test('a live envelope without a valid createdAtMs is refused', () async {
      await db.into(db.counters).insert(row());

      await expectStrict(
        binding,
        'c1',
        requiredKey: 'createdAtMs',
        idKey: 'id',
      );
    });

    test('a tombstone decodes to a deleted row', () async {
      await db.into(db.counters).insert(row(deleted: true));

      final envelope = await encodeStored(binding, 'c1');

      expectTombstone(envelope);
      final decoded = binding.decode(envelope);
      expect(decoded.id, 'c1');
      expect(decoded.isDeleted, isTrue);
      expect(decoded.deletedAt, deletedAt);
      expect(decoded.hlcTimestamp, hlc);
      expect(decoded.version, 5);
      expect(decoded.name, '');
      expect(decoded.startValue, 1);
      expect(decoded.scope, 'global');
    });
  });

  group('counter_values', () {
    const binding = CounterValuesBinding();
    CounterValueRow row(String noteId, {bool deleted = false}) =>
        CounterValueRow(
          counterId: 'c1',
          noteId: noteId,
          value: 12,
          position: 2,
          isPinned: true,
          hlcTimestamp: hlc,
          deviceId: 'dev-a',
          version: 5,
          isDeleted: deleted,
          deletedAt: deleted ? deletedAt : null,
          ownerId: uid,
          epochHlc: hlc,
          epochValue: 10,
          shards: '{"r1":[3,1]}',
        );

    test('the global value keys as counterId| and round-trips', () async {
      await db.into(db.counterValues).insert(row(''));

      final envelope = await encodeStored(binding, 'c1|');

      expectStamps(envelope, 'counter_values', 'c1|');
      expectWire(envelope);
      expect(envelope.data!['noteId'], '');
      expect(envelope.data!['shards'], {
        'r1': [3, 1],
      });
      expect(binding.decode(envelope), row(''));
    });

    test('an envelope without the PN-counter keys is a legacy absolute '
        'state', () async {
      await db.into(db.counterValues).insert(row(''));
      final envelope = await encodeStored(binding, 'c1|');
      final legacy = {...envelope.data!}
        ..remove('epochHlc')
        ..remove('epochValue')
        ..remove('shards');

      final decoded = binding.decode(carrying(envelope, legacy));

      expect(decoded.value, 12);
      expect(
        (decoded.epochHlc, decoded.epochValue, decoded.shards),
        (envelope.hlc, 12, ''),
      );
    });

    test('a PN-counter that is partial, malformed or does not add up to its '
        'value is refused', () async {
      await db.into(db.counterValues).insert(row(''));
      final envelope = await encodeStored(binding, 'c1|');
      final live = envelope.data!;

      for (final bad in <Map<String, Object?>>[
        {...live}..remove('shards'),
        {...live, 'value': 13},
        {
          ...live,
          'shards': {
            'r1': [3, -1],
          },
        },
        {...live, 'shards': 'r1'},
        {...live, 'epochHlc': 'not a stamp'},
      ]) {
        expect(
          () => binding.decode(carrying(envelope, bad)),
          throwsFormatException,
          reason: '$bad',
        );
      }
    });

    test('a per-note tombstone keeps its composite identity', () async {
      await db.into(db.counterValues).insert(row('note-1', deleted: true));

      final envelope = await encodeStored(binding, 'c1|note-1');

      expectTombstone(envelope);
      final decoded = binding.decode(envelope);
      expect((decoded.counterId, decoded.noteId), ('c1', 'note-1'));
      expect(decoded.isDeleted, isTrue);
      expect(decoded.deletedAt, deletedAt);
      expect(decoded.value, 0);
    });

    test('a live envelope without a valid value is refused', () async {
      await db.into(db.counterValues).insert(row(''));

      await expectStrict(binding, 'c1|', requiredKey: 'value', idKey: 'noteId');
      await expectStrict(
        binding,
        'c1|',
        requiredKey: 'isPinned',
        idKey: 'counterId',
      );
    });

    test('the key is the one a local write queues', () async {
      await db.counterDao.insertCounterWithValue(
        CountersCompanion(
          id: const Value('c2'),
          name: const Value('Reps'),
          createdAt: Value(created),
        ),
        1,
      );
      final queued = await (db.select(
        db.syncOutbox,
      )..where((o) => o.syncedTable.equals('counter_values'))).getSingle();
      final stored = await db.select(db.counterValues).getSingle();

      expect(binding.rowKeyOf(stored), queued.rowKey);
    });
  });

  group('vocabularies', () {
    const binding = VocabulariesBinding();
    VocabularyRow row({bool deleted = false}) => VocabularyRow(
      id: 'v1',
      name: 'Exercises',
      isEnabled: false,
      sortOrder: 4,
      createdAt: created,
      updatedAt: updated,
      hlcTimestamp: hlc,
      deviceId: 'dev-a',
      version: 5,
      isDeleted: deleted,
      deletedAt: deleted ? deletedAt : null,
      ownerId: uid,
    );

    tearDown(VocabularyService.reset);

    test('a live row carries the backup vocabulary map', () async {
      await db.into(db.vocabularies).insert(row());
      final service = await VocabularyService.forTesting(db);
      final exported = (await service.exportData()).single;

      final envelope = await encodeStored(binding, 'v1');

      expectStamps(envelope, 'vocabularies', 'v1');
      expectWire(envelope);
      expect(
        envelope.data!.keys.toSet(),
        exported.keys.toSet()..remove('items'),
        reason: 'its terms travel as their own rows',
      );
      expect(binding.decode(envelope), row());
    });

    test('a tombstone decodes to a deleted row', () async {
      await db.into(db.vocabularies).insert(row(deleted: true));

      final envelope = await encodeStored(binding, 'v1');

      expectTombstone(envelope);
      expect(binding.decode(envelope).isDeleted, isTrue);
      expect(binding.decode(envelope).deletedAt, deletedAt);
      expect(binding.decode(envelope).isEnabled, isTrue);
    });

    test('a live envelope without a valid isEnabled is refused', () async {
      await db.into(db.vocabularies).insert(row());

      await expectStrict(binding, 'v1', requiredKey: 'isEnabled', idKey: 'id');
    });
  });

  group('vocabulary_items', () {
    const binding = VocabularyItemsBinding();
    VocabularyItemRow row({bool deleted = false}) => VocabularyItemRow(
      id: 'i1',
      vocabularyId: 'v1',
      term: 'Squat',
      sortOrder: 2,
      createdAt: created,
      updatedAt: updated,
      hlcTimestamp: hlc,
      deviceId: 'dev-a',
      version: 5,
      isDeleted: deleted,
      deletedAt: deleted ? deletedAt : null,
      ownerId: uid,
    );

    tearDown(VocabularyService.reset);

    test('a live row carries the backup item map and its parent', () async {
      await db
          .into(db.vocabularies)
          .insert(
            VocabularyRow(
              id: 'v1',
              name: 'Exercises',
              isEnabled: true,
              sortOrder: 0,
              createdAt: created,
              updatedAt: updated,
              hlcTimestamp: hlc,
              deviceId: 'dev-a',
              version: 1,
              isDeleted: false,
            ),
          );
      await db.into(db.vocabularyItems).insert(row());
      final service = await VocabularyService.forTesting(db);
      final exported =
          ((await service.exportData()).single['items'] as List).single
              as Map<String, dynamic>;

      final envelope = await encodeStored(binding, 'i1');

      expectStamps(envelope, 'vocabulary_items', 'i1');
      expectWire(envelope);
      expect(envelope.data!.keys.toSet(), {...exported.keys, 'vocabularyId'});
      expect(binding.decode(envelope), row());
    });

    test('a tombstone decodes to a deleted row', () async {
      await db.into(db.vocabularyItems).insert(row(deleted: true));

      final envelope = await encodeStored(binding, 'i1');

      expectTombstone(envelope);
      expect(binding.decode(envelope).isDeleted, isTrue);
      expect(binding.decode(envelope).deletedAt, deletedAt);
      expect(binding.decode(envelope).term, '');
    });

    test('a live envelope without a valid vocabularyId is refused', () async {
      await db.into(db.vocabularyItems).insert(row());

      await expectStrict(
        binding,
        'i1',
        requiredKey: 'vocabularyId',
        idKey: 'id',
      );
    });
  });

  /// One calendar table's codec: the live row's wire map is its service's
  /// real `exportData` entry, value for value, and decodes back to every
  /// column; a data-less tombstone still decodes; a live envelope missing
  /// [requiredKey], or carrying it under the wrong type, is refused with the
  /// table and the key named; so is one whose data names another row than
  /// its key — each key of [mismatched] against the wrong value it maps to
  /// (R84). A key this build does not know is ignored instead (R73).
  void calendarTable<R extends Object>(
    SyncTableBinding<R> binding, {
    required String key,
    required R Function({bool deleted}) row,
    required Future<void> Function(R row) insert,
    required Future<Map<String, dynamic>> Function() exported,
    required String requiredKey,
    required Map<String, Object> mismatched,
    required void Function() reset,
  }) {
    group(binding.table, () {
      tearDown(reset);

      test('a live row carries the export map and decodes whole', () async {
        await insert(row());

        final envelope = await encodeStored(binding, key);

        expectStamps(envelope, binding.table, key);
        expect(envelope.op, OutboxOp.upsert);
        expectWire(envelope);
        expect(envelope.data, await exported());
        expect(binding.decode(envelope), row());
      });

      test('a tombstone without data decodes to a deleted row', () async {
        await insert(row(deleted: true));

        final envelope = await encodeStored(binding, key);

        expectStamps(envelope, binding.table, key);
        expectTombstone(envelope);
        final tombstone = binding.decode(envelope);
        expect(binding.rowKeyOf(tombstone), key);
        // Every drift row carries the CRDT fields; R does not say so.
        final dynamic decoded = tombstone;
        expect(decoded.isDeleted, isTrue);
        expect(decoded.deletedAt, deletedAt);
        expect(decoded.hlcTimestamp, hlc);
      });

      test('a live envelope without a valid $requiredKey is refused', () async {
        await insert(row());
        final live = await encodeStored(binding, key);
        final refused = throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains(binding.table), contains(requiredKey)),
          ),
        );

        expect(
          () => binding.decode(
            carrying(live, {...live.data!}..remove(requiredKey)),
          ),
          refused,
        );
        expect(
          () => binding.decode(
            carrying(live, {...live.data!, requiredKey: const []}),
          ),
          refused,
        );
        expect(
          () => binding.decode(carrying(live, const {})),
          throwsFormatException,
        );
      });

      test('a live envelope naming another row is refused', () async {
        await insert(row());
        final live = await encodeStored(binding, key);

        for (final MapEntry(key: idKey, value: other) in mismatched.entries) {
          expect(
            () => binding.decode(carrying(live, {...live.data!, idKey: other})),
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'message',
                allOf(contains(binding.table), contains(idKey)),
              ),
            ),
            reason: idKey,
          );
        }
      });

      test('a key this build does not know is ignored', () async {
        await insert(row());
        final live = await encodeStored(binding, key);

        expect(
          binding.decode(carrying(live, {...live.data!, 'futureColumn': 1})),
          binding.decode(live),
        );
      });
    });
  }

  calendarTable(
    const CalendarCategoriesBinding(),
    key: 'c1',
    row: ({bool deleted = false}) => CalendarCategoryRow(
      id: 'c1',
      name: 'Climb',
      colorValue: 0xFF00FF00,
      iconKey: 'event',
      sortOrder: 9,
      isBuiltIn: false,
      isHidden: true,
      createdAt: created,
      updatedAt: updated,
      hlcTimestamp: hlc,
      deviceId: 'dev-a',
      version: 5,
      isDeleted: deleted,
      deletedAt: deleted ? deletedAt : null,
      ownerId: uid,
    ),
    insert: (row) => db.into(db.calendarCategories).insert(row),
    exported: () async => (await (await CategoryService.forTesting(
      db,
    )).exportData()).singleWhere((m) => m['id'] == 'c1'),
    requiredKey: 'name',
    mismatched: const {'id': 'another-row'},
    reset: CategoryService.reset,
  );

  calendarTable(
    const CalendarEventTemplatesBinding(),
    key: 't1',
    row: ({bool deleted = false}) => EventTemplateRow(
      id: 't1',
      name: 'Push day',
      category: 'gym',
      sortOrder: 2,
      ruleKind: 'weekly',
      rulePayload: '{"weekdays":[1,3]}',
      startMinute: 540,
      durationMinutes: 90,
      description: 'Warm up',
      iconKey: 'bolt',
      colorValue: 0xFF445566,
      tintIcon: false,
      priority: 1,
      retroactive: true,
      countOccurrences: true,
      countStyle: 'ordinal',
      tracksPresence: true,
      assumeAbsent: true,
      perOccurrenceDescriptions: true,
      createdAt: created,
      updatedAt: updated,
      hlcTimestamp: hlc,
      deviceId: 'dev-a',
      version: 5,
      isDeleted: deleted,
      deletedAt: deleted ? deletedAt : null,
      ownerId: uid,
    ),
    insert: (row) => db.into(db.eventTemplates).insert(row),
    exported: () async =>
        (await (await EventTemplateService.forTesting(db)).exportData()).single,
    requiredKey: 'category',
    mismatched: const {'id': 'another-row'},
    reset: EventTemplateService.reset,
  );

  calendarTable(
    const CalendarEventsBinding(),
    key: 'e1',
    row: ({bool deleted = false}) => CalendarEventRow(
      id: 'e1',
      title: 'Leg day',
      category: 'gym',
      startDate: DateTime.utc(2026, 4, 1).toLocal(),
      allDay: false,
      iconKey: 'bolt',
      ruleKind: 'weekly',
      rulePayload: '{"weekdays":[2]}',
      endDate: DateTime.utc(2026, 9, 1).toLocal(),
      startMinute: 600,
      durationMinutes: 45,
      description: 'Bring chalk',
      noteId: 'n1',
      colorValue: 0xFF778899,
      tintIcon: false,
      priority: 2,
      retroactive: true,
      countOccurrences: true,
      countStyle: 'ordinal',
      tracksPresence: true,
      perOccurrenceDescriptions: true,
      showInDayRail: false,
      assumeAbsent: true,
      assumeAbsentFrom: DateTime.utc(2026, 5, 1).toLocal(),
      removeAfterAlert: true,
      categoryAlerts: false,
      createdAt: created,
      updatedAt: updated,
      hlcTimestamp: hlc,
      deviceId: 'dev-a',
      version: 5,
      isDeleted: deleted,
      deletedAt: deleted ? deletedAt : null,
      ownerId: uid,
    ),
    insert: (row) => db.into(db.calendarEvents).insert(row),
    exported: () async =>
        (await (await CalendarEventService.forTesting(db)).exportData()).single,
    requiredKey: 'startDateMs',
    mismatched: const {'id': 'another-row'},
    reset: CalendarEventService.reset,
  );

  test('a marked event adds its mark and the mark\'s stamp and nothing else, '
      'decodes with them, keeps the stamp once the mark is taken away, and '
      'its backup map carries neither (wire 47)', () async {
    const binding = CalendarEventsBinding();
    addTearDown(CalendarEventService.reset);
    await db.calendarEventDao.upsert(
      CalendarEventsCompanion.insert(
        id: 'e1',
        title: 'Leg day',
        category: 'gym',
        startDate: created,
        ruleKind: 'weekly',
        createdAt: created,
        updatedAt: updated,
      ),
    );
    final plain = await encodeStored(binding, 'e1');
    await db.calendarEventDao.setSharedPair('e1', 'p1');

    final envelope = await encodeStored(binding, 'e1');

    expect(envelope.data!.keys.toSet(), {
      ...plain.data!.keys,
      'sharedPair',
      'sharedStamp',
    }, reason: _wireChanged);
    expect(envelope.data!['sharedPair'], 'p1');
    expect(envelope.data!['sharedStamp'], envelope.hlc);
    expect(binding.decode(envelope).sharedPair, 'p1');
    expect(binding.decode(envelope).sharedStamp, envelope.hlc);
    expect(binding.decode(plain).sharedPair, isNull);
    expect(binding.decode(plain).sharedStamp, isNull);

    // A mark taken away still says when: that is what another device tells
    // it from a mark it never heard of.
    await db.calendarEventDao.setSharedPair('e1', null);
    final cleared = await encodeStored(binding, 'e1');
    expect(cleared.data!.keys.toSet(), {
      ...plain.data!.keys,
      'sharedStamp',
    }, reason: _wireChanged);
    expect(cleared.data!['sharedStamp'], cleared.hlc);

    // The backup is a person's own copy: it says nothing of a share.
    final exported = (await (await CalendarEventService.forTesting(
      db,
    )).exportData()).single;
    expect(exported.containsKey('sharedPair'), isFalse);
    expect(exported.containsKey('sharedStamp'), isFalse);
  });

  test('a marked category adds its mark and the mark\'s stamp and nothing '
      'else, decodes with them, keeps the stamp once the mark is taken '
      'away, and its backup map carries neither (wire 48)', () async {
    const binding = CalendarCategoriesBinding();
    addTearDown(CategoryService.reset);
    await db.calendarCategoryDao.insertCategory(
      CalendarCategoriesCompanion.insert(
        id: 'c1',
        name: 'Climb',
        colorValue: 0xFF00FF00,
        iconKey: 'event',
        createdAt: created,
        updatedAt: updated,
      ),
    );
    final plain = await encodeStored(binding, 'c1');
    await db.calendarCategoryDao.setSharedPair('c1', 'p1');

    final envelope = await encodeStored(binding, 'c1');

    expect(envelope.data!.keys.toSet(), {
      ...plain.data!.keys,
      'sharedPair',
      'sharedStamp',
    }, reason: _wireChanged);
    expect(envelope.data!['sharedPair'], 'p1');
    expect(envelope.data!['sharedStamp'], envelope.hlc);
    expect(binding.decode(envelope).sharedPair, 'p1');
    expect(binding.decode(envelope).sharedStamp, envelope.hlc);
    expect(binding.decode(plain).sharedPair, isNull);
    expect(binding.decode(plain).sharedStamp, isNull);
    expect(
      () => binding.decode(
        carrying(envelope, {...envelope.data!, 'sharedPair': 7}),
      ),
      throwsFormatException,
    );

    await db.calendarCategoryDao.setSharedPair('c1', null);
    final cleared = await encodeStored(binding, 'c1');
    expect(cleared.data!.keys.toSet(), {
      ...plain.data!.keys,
      'sharedStamp',
    }, reason: _wireChanged);
    expect(cleared.data!['sharedStamp'], cleared.hlc);

    final exported = (await (await CategoryService.forTesting(
      db,
    )).exportData()).singleWhere((map) => map['id'] == 'c1');
    expect(exported.containsKey('sharedPair'), isFalse);
    expect(exported.containsKey('sharedStamp'), isFalse);
  });

  // The EU spring-forward day: the day keys must survive a DST switch.
  final day = DateTime.utc(2026, 3, 29);
  final dayKey = dayRowKey('e1', day);

  /// What a day row's data must not say when its key says `e1` and [day]:
  /// either half of the identity naming another row is refused.
  final otherDay = <String, Object>{
    'eventId': 'another-event',
    'dayMs': day.add(const Duration(days: 1)).millisecondsSinceEpoch,
  };

  calendarTable(
    const CalendarEventOccurrencesBinding(),
    key: dayKey,
    row: ({bool deleted = false}) => EventOccurrenceRow(
      eventId: 'e1',
      day: day.toLocal(),
      description: 'Felt strong',
      createdAt: created,
      updatedAt: updated,
      hlcTimestamp: hlc,
      deviceId: 'dev-a',
      version: 5,
      isDeleted: deleted,
      deletedAt: deleted ? deletedAt : null,
      ownerId: uid,
    ),
    insert: (row) => db.into(db.eventOccurrenceDescriptions).insert(row),
    exported: () async => (await (await EventOccurrenceService.forTesting(
      db,
    )).exportData()).single,
    requiredKey: 'dayMs',
    mismatched: otherDay,
    reset: EventOccurrenceService.reset,
  );

  calendarTable(
    const CalendarEventAbsencesBinding(),
    key: dayKey,
    row: ({bool deleted = false}) => EventAbsenceRow(
      eventId: 'e1',
      day: day.toLocal(),
      status: 'present',
      createdAt: created,
      updatedAt: updated,
      hlcTimestamp: hlc,
      deviceId: 'dev-a',
      version: 5,
      isDeleted: deleted,
      deletedAt: deleted ? deletedAt : null,
      ownerId: uid,
    ),
    insert: (row) => db.into(db.eventAbsences).insert(row),
    exported: () async =>
        (await (await EventPresenceService.forTesting(db)).exportData()).single,
    requiredKey: 'eventId',
    mismatched: otherDay,
    reset: EventPresenceService.reset,
  );

  calendarTable(
    const CalendarEventSkipsBinding(),
    key: dayKey,
    row: ({bool deleted = false}) => EventSkipRow(
      eventId: 'e1',
      day: day.toLocal(),
      createdAt: created,
      updatedAt: updated,
      hlcTimestamp: hlc,
      deviceId: 'dev-a',
      version: 5,
      isDeleted: deleted,
      deletedAt: deleted ? deletedAt : null,
      ownerId: uid,
    ),
    insert: (row) => db.into(db.eventSkips).insert(row),
    exported: () async =>
        (await (await EventSkipService.forTesting(db)).exportData()).single,
    requiredKey: 'createdAtMs',
    mismatched: otherDay,
    reset: EventSkipService.reset,
  );

  calendarTable(
    const CalendarEventAlertsBinding(),
    key: 'a1',
    row: ({bool deleted = false}) => EventAlertRow(
      id: 'a1',
      eventId: 'e1',
      mode: 'ring',
      offsetMinutes: 15,
      daysBefore: 1,
      dayMinute: 480,
      sound: 'chime',
      enabled: false,
      createdAt: created,
      updatedAt: updated,
      hlcTimestamp: hlc,
      deviceId: 'dev-a',
      version: 5,
      isDeleted: deleted,
      deletedAt: deleted ? deletedAt : null,
      ownerId: uid,
    ),
    insert: (row) => db.into(db.eventAlerts).insert(row),
    exported: () async =>
        (await (await EventAlertService.forTesting(db)).exportData()).single,
    requiredKey: 'offsetMinutes',
    mismatched: const {'id': 'another-row'},
    reset: EventAlertService.reset,
  );

  calendarTable(
    const CalendarCategoryAlertsBinding(),
    key: 'ca1',
    row: ({bool deleted = false}) => CategoryAlertRow(
      id: 'ca1',
      categoryId: 'climb',
      mode: 'ring',
      offsetMinutes: 30,
      daysBefore: 2,
      dayMinute: 1200,
      sound: 'bell',
      enabled: false,
      createdAt: created,
      updatedAt: updated,
      hlcTimestamp: hlc,
      deviceId: 'dev-a',
      version: 5,
      isDeleted: deleted,
      deletedAt: deleted ? deletedAt : null,
      ownerId: uid,
    ),
    insert: (row) => db.into(db.calendarCategoryAlerts).insert(row),
    exported: () async => (await (await EventAlertService.forTesting(
      db,
    )).exportCategoryAlerts()).single,
    requiredKey: 'categoryId',
    mismatched: const {'id': 'another-row'},
    reset: EventAlertService.reset,
  );

  calendarTable(
    const CalendarCategoryProfilesBinding(),
    key: 'cp1',
    row: ({bool deleted = false}) => CategoryProfileRow(
      id: 'cp1',
      categoryId: 'climb',
      kind: 'workout',
      area: 'health',
      measure: 'hours',
      nominalMinutes: 90,
      markVerb: '',
      marksNew: false,
      assumeAbsentNew: true,
      countsHours: false,
      targetKind: 'atLeast',
      targetValue: 3,
      targetPeriod: 'week',
      createdAt: created,
      updatedAt: updated,
      hlcTimestamp: hlc,
      deviceId: 'dev-a',
      version: 5,
      isDeleted: deleted,
      deletedAt: deleted ? deletedAt : null,
      ownerId: uid,
    ),
    insert: (row) => db.into(db.calendarCategoryProfiles).insert(row),
    exported: () async => (await (await CategoryProfileService.forTesting(
      db,
    )).exportCategoryProfiles()).single,
    requiredKey: 'categoryId',
    mismatched: const {'id': 'another-row'},
    reset: CategoryProfileService.reset,
  );

  /// Written as literals, not through `CategoryProfileKeys`: renaming a
  /// constant moves the wire and the backup together, which every
  /// round-trip above would pass.
  test('a calendar_category_profiles row carries exactly its keys', () async {
    await db
        .into(db.calendarCategoryProfiles)
        .insert(
          CategoryProfileRow(
            id: 'cp1',
            categoryId: 'climb',
            kind: 'workout',
            createdAt: created,
            updatedAt: updated,
            hlcTimestamp: hlc,
            deviceId: 'dev-a',
            version: 5,
            isDeleted: false,
            ownerId: uid,
          ),
        );

    final envelope = await encodeStored(
      const CalendarCategoryProfilesBinding(),
      'cp1',
    );

    expect(envelope.data!.keys.toSet(), {
      'id',
      'categoryId',
      'kind',
      'area',
      'measure',
      'nominalMinutes',
      'markVerb',
      'marksNew',
      'assumeAbsentNew',
      'countsHours',
      'targetKind',
      'targetValue',
      'targetPeriod',
      'createdAtMs',
      'updatedAtMs',
      'ownerId',
    });
  });

  calendarTable(
    const EventDigestsBinding(),
    key: 'd1',
    row: ({bool deleted = false}) => EventDigestRow(
      id: 'd1',
      name: 'Weekly',
      payload: '{"cadence":"weekly","fromTheFuture":true}',
      enabled: false,
      sortOrder: 3,
      createdAt: created,
      updatedAt: updated,
      hlcTimestamp: hlc,
      deviceId: 'dev-a',
      version: 5,
      isDeleted: deleted,
      deletedAt: deleted ? deletedAt : null,
      ownerId: uid,
    ),
    insert: (row) => db.into(db.eventDigests).insert(row),
    exported: () async =>
        (await (await EventDigestService.forTesting(db)).exportData()).single,
    requiredKey: 'payload',
    mismatched: const {'id': 'another-row'},
    reset: EventDigestService.reset,
  );

  calendarTable(
    const CalendarFilterPresetsBinding(),
    key: 'p1',
    row: ({bool deleted = false}) => CalendarFilterPresetRow(
      id: 'p1',
      name: 'Tracked',
      filters: '{"trackedOnly":true}',
      sortOrder: 5,
      createdAt: created,
      updatedAt: updated,
      hlcTimestamp: hlc,
      deviceId: 'dev-a',
      version: 5,
      isDeleted: deleted,
      deletedAt: deleted ? deletedAt : null,
      ownerId: uid,
    ),
    insert: (row) => db.into(db.calendarFilterPresets).insert(row),
    exported: () async =>
        (await (await FilterPresetService.forTesting(db)).exportData()).single,
    requiredKey: 'filters',
    mismatched: const {'id': 'another-row'},
    reset: FilterPresetService.reset,
  );

  calendarTable(
    const OverviewViewsBinding(),
    key: 'v1',
    row: ({bool deleted = false}) => OverviewViewRow(
      id: 'v1',
      name: 'This year',
      payload: '{"period":{"kind":"thisYear"}}',
      sortOrder: 6,
      createdAt: created,
      updatedAt: updated,
      hlcTimestamp: hlc,
      deviceId: 'dev-a',
      version: 5,
      isDeleted: deleted,
      deletedAt: deleted ? deletedAt : null,
      ownerId: uid,
    ),
    insert: (row) => db.into(db.overviewViews).insert(row),
    exported: () async =>
        (await (await OverviewViewService.forTesting(db)).exportData()).single,
    requiredKey: 'name',
    mismatched: const {'id': 'another-row'},
    reset: OverviewViewService.reset,
  );

  test('a live day row whose dayMs names another day is refused', () {
    const binding = CalendarEventSkipsBinding();

    expect(
      () => binding.decode(
        SyncEnvelope(
          table: binding.table,
          rowKey: dayKey,
          hlc: hlc,
          deviceId: 'dev-a',
          version: 5,
          op: OutboxOp.upsert,
          ownerId: uid,
          data: {
            'eventId': 'e1',
            'dayMs': day.millisecondsSinceEpoch + 86400000,
            'createdAtMs': 0,
            'updatedAtMs': 0,
          },
        ),
      ),
      throwsFormatException,
    );
  });

  group('row keys', () {
    SyncEnvelope tombstone(String table, String rowKey) => SyncEnvelope(
      table: table,
      rowKey: rowKey,
      hlc: hlc,
      deviceId: 'dev-a',
      version: 5,
      op: OutboxOp.tombstone,
      ownerId: uid,
    );

    test('dayKeyOf reads back exactly what dayRowKey writes', () {
      final key = dayKeyOf(dayKey);

      expect(key.eventId, 'e1');
      expect(dayRowKey(key.eventId, key.day), dayKey);
      expect(dayKeyOf('a|b|${day.millisecondsSinceEpoch}').eventId, 'a|b');
    });

    test('dayKeyOf refuses a key dayRowKey could not have written', () {
      final ms = day.millisecondsSinceEpoch;
      for (final bad in [
        'e1',
        '|$ms',
        'e1|',
        'e1|day',
        'e1|${ms + 1}',
        'e1|0$ms',
        'e1|+$ms',
        'e1|99999999999999999',
        // A whole second that is not a UTC midnight: every local writer
        // normalises the day, and a second row for one calendar day would
        // make a presence mark depend on the order its rows were read
        // (R79).
        'e1|${ms + 1000}',
        'e1|${ms + 43200000}',
      ]) {
        expect(() => dayKeyOf(bad), throwsFormatException, reason: bad);
      }
    });

    test('a row stored at a local midnight still pushes a key dayKeyOf '
        'accepts (A7 review R133)', () async {
      // Two hours under the UTC midnight: what a row written before the
      // rule — or imported from a backup of one — holds in a zone east of
      // UTC. No migration normalised the column, so the push meets it.
      final legacy = DateTime.fromMillisecondsSinceEpoch(
        day.millisecondsSinceEpoch - const Duration(hours: 2).inMilliseconds,
      );
      const binding = CalendarEventSkipsBinding();
      final row = EventSkipRow(
        eventId: 'e1',
        day: legacy,
        createdAt: created,
        updatedAt: updated,
        hlcTimestamp: hlc,
        deviceId: 'dev-a',
        version: 5,
        isDeleted: false,
        ownerId: uid,
      );

      final envelope = await binding.encode(db, row, boundUid: uid);

      // Without this the envelope carried a key every receiving device
      // refused, and the skip never left this one.
      expect(dayKeyOf(envelope.rowKey).day, day.toLocal());
      expect(envelope.data!['dayMs'], day.millisecondsSinceEpoch);
      // The row and the outbox entry naming it keep their own key, which is
      // how the push finds the row to send at all.
      expect(binding.rowKeyOf(row), dayRowKey('e1', legacy));
      expect(localDayKeyOf(binding.rowKeyOf(row)).day, legacy);
    });

    test('a day tombstone under a malformed key is refused', () {
      const bindings = <SyncTableBinding<Object>>[
        CalendarEventOccurrencesBinding(),
        CalendarEventAbsencesBinding(),
        CalendarEventSkipsBinding(),
      ];
      for (final binding in bindings) {
        for (final bad in ['e1', 'e1|${day.millisecondsSinceEpoch + 500}']) {
          expect(
            () => binding.decode(tombstone(binding.table, bad)),
            throwsFormatException,
            reason: '${binding.table} $bad',
          );
        }
      }
    });

    test('a counter value key without a | or a counter id is refused', () {
      const binding = CounterValuesBinding();

      for (final bad in ['c1', '|n1']) {
        expect(
          () => binding.decode(tombstone(binding.table, bad)),
          throwsFormatException,
          reason: bad,
        );
      }
      expect(
        binding.rowKeyOf(binding.decode(tombstone(binding.table, 'c1|'))),
        'c1|',
      );
    });

    test('a tombstone under an empty key is refused', () {
      const bindings = <SyncTableBinding<Object>>[
        FoldersBinding(),
        NotesBinding(),
        CalendarEventsBinding(),
        CounterValuesBinding(),
      ];
      for (final binding in bindings) {
        expect(
          () => binding.decode(tombstone(binding.table, '')),
          throwsFormatException,
          reason: binding.table,
        );
      }
    });
  });
}

const String _wireChanged =
    'the wire changed: bump DatabaseSchema.syncSchemaVersion and update this '
    'snapshot';

/// The `data` keys each binding writes for a live, owned row — frozen here
/// rather than derived from the backup or export maps, since those move for
/// reasons of their own. A tombstone writes no `data` at all. The space's
/// schema is `DatabaseSchema.syncSchemaVersion`, raised only when this set
/// changes (`docs/scalability-roadmap.md` §5.1 S1).
///
/// Wire 46 (§5.3 S6): a note's body left its document — `content` gave way
/// to the manifest's `chunks` and `bodyHash` — and `content_chunks` joined
/// the wire, one immutable document per chunk text.
///
/// Wire 47 (`docs/cloud-sharing-foundations.md` §4): an event and a folder
/// that carry a share mark write it under `sharedPair` — and since wire 48 a
/// category (`docs/cloud-share-surfaces-roadmap.md` §7.4) — a key absent from
/// every other row — so it is not in the sets below, which are an unmarked
/// row's; the folders group and the marked-event and marked-category cases
/// above pin it for a marked one, and `sync_share_push_test.dart` what the
/// documents say.
const Map<String, Set<String>> _wireKeys = {
  'content_chunks': {'hash', 'gz', 'length'},
  'calendar_categories': {
    'id',
    'name',
    'colorValue',
    'iconKey',
    'sortOrder',
    'isBuiltIn',
    'isHidden',
    'createdAtMs',
    'updatedAtMs',
    'ownerId',
  },
  'calendar_event_templates': {
    'id',
    'name',
    'category',
    'sortOrder',
    'ruleKind',
    'rulePayload',
    'startMinute',
    'durationMinutes',
    'description',
    'iconKey',
    'colorValue',
    'tintIcon',
    'priority',
    'retroactive',
    'countOccurrences',
    'countStyle',
    'tracksPresence',
    'assumeAbsent',
    'perOccurrenceDescriptions',
    'createdAtMs',
    'updatedAtMs',
    'ownerId',
  },
  'calendar_events': {
    'id',
    'title',
    'category',
    'startDateMs',
    'allDay',
    'iconKey',
    'ruleKind',
    'rulePayload',
    'endDateMs',
    'startMinute',
    'durationMinutes',
    'description',
    'noteId',
    'colorValue',
    'tintIcon',
    'priority',
    'retroactive',
    'countOccurrences',
    'countStyle',
    'tracksPresence',
    'assumeAbsent',
    'assumeAbsentFromMs',
    'perOccurrenceDescriptions',
    'showInDayRail',
    'removeAfterAlert',
    'categoryAlerts',
    'createdAtMs',
    'updatedAtMs',
    'ownerId',
  },
  'calendar_event_occurrences': {
    'eventId',
    'dayMs',
    'description',
    'createdAtMs',
    'updatedAtMs',
    'ownerId',
  },
  'calendar_event_absences': {
    'eventId',
    'dayMs',
    'status',
    'createdAtMs',
    'updatedAtMs',
    'ownerId',
  },
  'calendar_event_skips': {
    'eventId',
    'dayMs',
    'createdAtMs',
    'updatedAtMs',
    'ownerId',
  },
  'calendar_event_alerts': {
    'id',
    'eventId',
    'mode',
    'offsetMinutes',
    'daysBefore',
    'dayMinute',
    'sound',
    'enabled',
    'createdAtMs',
    'updatedAtMs',
    'ownerId',
  },
  'calendar_category_alerts': {
    'id',
    'categoryId',
    'mode',
    'offsetMinutes',
    'daysBefore',
    'dayMinute',
    'sound',
    'enabled',
    'createdAtMs',
    'updatedAtMs',
    'ownerId',
  },
  'calendar_category_profiles': {
    'id',
    'categoryId',
    'kind',
    'area',
    'measure',
    'nominalMinutes',
    'markVerb',
    'marksNew',
    'assumeAbsentNew',
    'countsHours',
    'targetKind',
    'targetValue',
    'targetPeriod',
    'createdAtMs',
    'updatedAtMs',
    'ownerId',
  },
  'event_digests': {
    'id',
    'name',
    'payload',
    'enabled',
    'sortOrder',
    'createdAtMs',
    'updatedAtMs',
    'ownerId',
  },
  'calendar_filter_presets': {
    'id',
    'name',
    'filters',
    'sortOrder',
    'createdAtMs',
    'updatedAtMs',
    'ownerId',
  },
  'overview_views': {
    'id',
    'name',
    'payload',
    'sortOrder',
    'createdAtMs',
    'updatedAtMs',
    'ownerId',
  },
  'folders': {
    'id',
    'name',
    'parentId',
    'position',
    'createdAtMs',
    'updatedAtMs',
    'noteSortOrder',
    'subfolderSortOrder',
    'label',
    'ownerId',
  },
  'notes': {
    'id',
    'folderId',
    'title',
    'chunks',
    'bodyHash',
    'preview',
    'createdAtMs',
    'updatedAtMs',
    'label',
    'ownerId',
    'position',
  },
  'counters': {
    'id',
    'name',
    'counterStartValue',
    'counterStep',
    'counterScope',
    'isPinned',
    'createdAtMs',
    'ownerId',
    'position',
  },
  // The PN-counter keys (S20, D8 A) joined without a version bump, the one
  // exception the record decided: an older build ignores them and reads
  // `value`, so no device pauses as appOutdated. They are additive, not free:
  // in the mixed-version window an older build's envelope, which lacks them,
  // never joins and merges by stamp order, so its strictly newer write still
  // overwrites the taps counted since (`CounterValuesBinding.mergeRemote`).
  'counter_values': {
    'counterId',
    'noteId',
    'value',
    'isPinned',
    'position',
    'ownerId',
    'epochHlc',
    'epochValue',
    'shards',
  },
  'vocabularies': {
    'id',
    'name',
    'isEnabled',
    'sortOrder',
    'createdAtMs',
    'updatedAtMs',
    'ownerId',
  },
  'vocabulary_items': {
    'id',
    'term',
    'sortOrder',
    'createdAtMs',
    'updatedAtMs',
    'ownerId',
    'vocabularyId',
  },
};
