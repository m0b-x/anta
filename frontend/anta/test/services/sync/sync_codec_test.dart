import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/crdt/hlc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/sync/sync_gateway.dart';
import 'package:anta/services/sync/sync_table_binding.dart';
import 'package:anta/services/sync/tables/counter_values_binding.dart';
import 'package:anta/services/sync/tables/counters_binding.dart';
import 'package:anta/services/sync/tables/folders_binding.dart';
import 'package:anta/services/sync/tables/notes_binding.dart';
import 'package:anta/services/sync/tables/vocabularies_binding.dart';
import 'package:anta/services/sync/tables/vocabulary_items_binding.dart';
import 'package:anta/services/vocabulary_service.dart';

import '../../database/support/db_test_support.dart';

/// Guards the wire codec of S2a's six tables: a row encodes to the envelope
/// the outbox and the rules expect, its `data` under the backup's keys, and
/// decodes back to the same row — so a row that crosses the wire and merges
/// lands as the row that left.
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
    expect(envelope.data, isNull);
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
      // `BackupService.exportAllData`'s folder keys.
      expect(envelope.data!.keys.toSet(), {
        'id',
        'name',
        'parentId',
        'position',
        'createdAt',
        'updatedAt',
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
    });
  });

  group('notes', () {
    const binding = NotesBinding();
    final body = List.generate(1400, (i) => 'set $i rep').join('\n');

    test('a 14 KB body crosses whole and lands as it left', () async {
      expect(body.length, greaterThan(14 * 1000));
      final note = await db.noteDao.createNote(
        folderId: 'f1',
        title: 'Squat log',
        preview: NoteMetadata.generatePreview(body),
        contentLength: body.length,
        chunkCount: 2,
        isCompressed: true,
        content: body,
        ownerId: uid,
      );

      final envelope = await encodeStored(binding, note.id);

      expect(envelope.rowKey, note.id);
      expect(envelope.hlc, note.hlcTimestamp);
      expect(envelope.op, OutboxOp.upsert);
      // `BackupService.exportAllData`'s note keys, plus `position`.
      expect(envelope.data!.keys.toSet(), {
        'id',
        'folderId',
        'title',
        'content',
        'preview',
        'createdAt',
        'updatedAt',
        'label',
        'ownerId',
        'position',
      });
      expect(envelope.data!['content'], body);
      expect(binding.contentOf(envelope), body);

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

      final other = await openTestDatabase();
      addTearDown(other.close);
      await binding.mergeRemote(other, envelope);
      expect(await other.noteDao.getNoteById(note.id), note);
      expect(await other.contentChunkDao.loadContent(note.id), body);
    });

    test('a tombstone carries no body', () async {
      final note = await db.noteDao.createNote(folderId: 'f1', title: 'Gone');
      await db.noteDao.softDeleteNote(note.id);

      final envelope = await encodeStored(binding, note.id);

      expectTombstone(envelope);
      expect(binding.contentOf(envelope), isNull);
      final decoded = binding.decode(envelope);
      expect(decoded.isDeleted, isTrue);
      expect(
        decoded.deletedAt,
        DateTime.fromMillisecondsSinceEpoch(
          HlcTimestamp.parse(envelope.hlc).wallTime,
        ),
      );
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
      expect(envelope.data!.keys.toSet(), {...exported.keys, 'position'});
      expect(binding.decode(envelope), row());
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
        );

    test('the global value keys as counterId| and round-trips', () async {
      await db.into(db.counterValues).insert(row(''));

      final envelope = await encodeStored(binding, 'c1|');

      expectStamps(envelope, 'counter_values', 'c1|');
      expect(envelope.data!.keys.toSet(), {
        'counterId',
        'noteId',
        'value',
        'isPinned',
        'position',
        'ownerId',
      });
      expect(envelope.data!['noteId'], '');
      expect(binding.decode(envelope), row(''));
    });

    test('a per-note tombstone keeps its composite identity', () async {
      await db.into(db.counterValues).insert(row('note-1', deleted: true));

      final envelope = await encodeStored(binding, 'c1|note-1');

      expectTombstone(envelope);
      final decoded = binding.decode(envelope);
      expect((decoded.counterId, decoded.noteId), ('c1', 'note-1'));
      expect(decoded.isDeleted, isTrue);
      expect(decoded.deletedAt, deletedAt);
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
      expect(envelope.data!.keys.toSet(), {...exported.keys, 'vocabularyId'});
      expect(binding.decode(envelope), row());
    });

    test('a tombstone decodes to a deleted row', () async {
      await db.into(db.vocabularyItems).insert(row(deleted: true));

      final envelope = await encodeStored(binding, 'i1');

      expectTombstone(envelope);
      expect(binding.decode(envelope).isDeleted, isTrue);
      expect(binding.decode(envelope).deletedAt, deletedAt);
    });
  });
}
