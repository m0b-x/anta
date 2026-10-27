import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/database/crdt/crdt_write.dart';
import 'package:anta/database/crdt/hlc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/note_metadata.dart';
import 'package:anta/services/calendar_event_service.dart';
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
import 'package:anta/services/sync/tables/calendar_categories_binding.dart';
import 'package:anta/services/sync/tables/calendar_category_alerts_binding.dart';
import 'package:anta/services/sync/tables/calendar_event_absences_binding.dart';
import 'package:anta/services/sync/tables/calendar_event_alerts_binding.dart';
import 'package:anta/services/sync/tables/calendar_event_occurrences_binding.dart';
import 'package:anta/services/sync/tables/calendar_event_skips_binding.dart';
import 'package:anta/services/sync/tables/calendar_event_templates_binding.dart';
import 'package:anta/services/sync/tables/calendar_events_binding.dart';
import 'package:anta/services/sync/tables/calendar_filter_presets_binding.dart';
import 'package:anta/services/sync/tables/counter_values_binding.dart';
import 'package:anta/services/sync/tables/counters_binding.dart';
import 'package:anta/services/sync/tables/event_digests_binding.dart';
import 'package:anta/services/sync/tables/folders_binding.dart';
import 'package:anta/services/sync/tables/notes_binding.dart';
import 'package:anta/services/sync/tables/overview_views_binding.dart';
import 'package:anta/services/sync/tables/vocabularies_binding.dart';
import 'package:anta/services/sync/tables/vocabulary_items_binding.dart';
import 'package:anta/services/vocabulary_service.dart';

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
    expect(envelope.data, isNull);
  }

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
      // `BackupService.exportAllData`'s folder keys, dates as epoch-ms.
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
      // `BackupService.exportAllData`'s note keys, dates as epoch-ms, plus
      // `position`.
      expect(envelope.data!.keys.toSet(), {
        'id',
        'folderId',
        'title',
        'content',
        'preview',
        'createdAtMs',
        'updatedAtMs',
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

    test('a live envelope without a body is refused, never emptied', () async {
      final note = await db.noteDao.createNote(
        folderId: 'f1',
        title: 'Log',
        content: 'real text',
      );

      await expectStrict(
        binding,
        note.id,
        requiredKey: 'content',
        idKey: 'id',
        decode: binding.contentOf,
      );
      final envelope = await encodeStored(binding, note.id);
      final bodyless = SyncEnvelope(
        table: envelope.table,
        rowKey: envelope.rowKey,
        hlc: 'ffffffffffff:0000:remote',
        deviceId: 'remote',
        version: 9,
        op: OutboxOp.upsert,
        ownerId: envelope.ownerId,
        data: {...envelope.data!}..remove('content'),
      );
      expect(() => binding.mergeRemote(db, bodyless), throwsFormatException);
      expect(await db.contentChunkDao.loadContent(note.id), 'real text');
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
