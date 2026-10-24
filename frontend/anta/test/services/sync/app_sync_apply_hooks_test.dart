import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/item_label.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/sync/app_sync_apply_hooks.dart';
import 'package:anta/services/sync/sync_apply_hooks.dart';
import 'package:anta/services/sync/sync_table_binding.dart';

import '../../database/support/db_test_support.dart';

/// The production hooks against an in-memory database: the real
/// repositories, storage service and counter service, recorders for the
/// calendar, the alerts and the vocabularies.
void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late FolderRepository folders;
  late NoteStorageService storage;
  late CounterService counters;
  late List<String> calls;
  late AppSyncApplyHooks hooks;
  Object? calendarFailure;
  final now = DateTime(2026, 10, 24, 9, 5);

  setUpAll(() => initializeDateFormatting('en'));

  setUp(() async {
    db = await openTestDatabase();
    notes = NoteRepository(database: db);
    folders = FolderRepository(database: db);
    storage = NoteStorageService(repository: notes);
    counters = await CounterService.forTesting(db);
    calls = [];
    calendarFailure = null;
    Future<void> Function() record(String name) => () async => calls.add(name);
    hooks = AppSyncApplyHooks(
      notes: () => notes,
      folders: () => folders,
      noteStorage: () => storage,
      counters: () async => counters,
      reloadCalendar: () async {
        calls.add('calendar');
        if (calendarFailure != null) throw calendarFailure!;
      },
      reloadAlerts: record('alerts'),
      reconcileAlerts: record('reconcile'),
      reloadVocabularies: record('vocabularies'),
      strings: () async => lookupAppLocalizations(const Locale('en')),
      now: () => now,
    );
  });

  tearDown(() async {
    await counters.flush();
    await db.close();
  });

  SyncAppliedRow row(
    String key,
    MergeResult result, {
    bool tombstone = false,
  }) => SyncAppliedRow(rowKey: key, result: result, tombstone: tombstone);

  group('afterPage', () {
    test('announces each changed note as created, updated or deleted, and '
        'passes over the rest', () async {
      final inserted = await db.noteDao.createNote(folderId: 'f1', title: 'A');
      final applied = await db.noteDao.createNote(folderId: 'f1', title: 'B');
      final gone = await db.noteDao.createNote(folderId: 'f2', title: 'C');
      final kept = await db.noteDao.createNote(folderId: 'f1', title: 'D');
      await db.customStatement(
        'UPDATE notes SET is_deleted = 1 WHERE id = ?',
        [gone.id],
      );
      final changes = <NoteChange>[];
      final subscription = notes.noteChanges.listen(changes.add);
      addTearDown(subscription.cancel);

      await hooks.afterPage('notes', [
        row(inserted.id, MergeResult.inserted),
        row(applied.id, MergeResult.applied),
        row(gone.id, MergeResult.applied, tombstone: true),
        row(kept.id, MergeResult.keptLocal),
        row('unseen', MergeResult.unchanged),
      ]);
      await pumpEventQueue();

      expect(
        {for (final c in changes) c.noteId: (c.type, c.folderId)},
        {
          inserted.id: (NoteChangeType.created, 'f1'),
          applied.id: (NoteChangeType.updated, 'f1'),
          gone.id: (NoteChangeType.deleted, 'f2'),
        },
      );
      expect(changes.firstWhere((c) => c.noteId == applied.id).note!.title, 'B');
    });

    test('drops a merged note\'s cached row and body before announcing', () async {
      final note = await storage.createNote(
        folderId: 'f1',
        title: 'Log',
        content: 'mine',
      );
      expect(await notes.loadContent(note.id), 'mine');
      // A pull replaced the row and its chunks beneath the repository.
      final merged = (await db.noteDao.getNoteById(note.id))!.copyWith(
        title: 'Merged',
        hlcTimestamp: 'ffffffffffff:0000:remote',
      );
      await db.noteDao.mergeNoteDocument(merged, 'theirs');
      String? seenContent;
      final subscription = notes.noteChanges.listen((_) async {
        seenContent = await notes.loadContent(note.id);
      });
      addTearDown(subscription.cancel);

      await hooks.afterPage('notes', [row(note.id, MergeResult.applied)]);
      await pumpEventQueue();

      expect(seenContent, 'theirs');
      expect((await notes.getNoteById(note.id))!.title, 'Merged');
    });

    test('announces each changed folder', () async {
      final inserted = await db.folderDao.createFolder(name: 'New');
      final gone = await db.folderDao.createFolder(name: 'Gone');
      await db.customStatement(
        'UPDATE folders SET is_deleted = 1 WHERE id = ?',
        [gone.id],
      );
      final changes = <FolderChange>[];
      final subscription = folders.folderChanges.listen(changes.add);
      addTearDown(subscription.cancel);

      await hooks.afterPage('folders', [
        row(inserted.id, MergeResult.inserted),
        row(gone.id, MergeResult.applied, tombstone: true),
      ]);
      await pumpEventQueue();

      expect({for (final c in changes) c.folderId: c.type}, {
        inserted.id: FolderChangeType.created,
        gone.id: FolderChangeType.deleted,
      });
    });

    test('announces nothing for the other tables', () async {
      final changes = <NoteChange>[];
      final subscription = notes.noteChanges.listen(changes.add);
      addTearDown(subscription.cancel);

      await hooks.afterPage('calendar_events', [row('e1', MergeResult.applied)]);
      await pumpEventQueue();

      expect(changes, isEmpty);
      expect(calls, isEmpty);
    });
  });

  group('beforePage', () {
    test('flushes a pending counter tap before a counter page', () async {
      final id = await counters.addCounter(name: 'Sets', startValue: 3);
      await counters.incrementGlobal(id);
      expect((await db.counterDao.getValuesForNote(''))[id], 3);

      await hooks.beforePage('counter_values');

      expect((await db.counterDao.getValuesForNote(''))[id], 4);
    });

    test('leaves a pending tap alone before another table', () async {
      final id = await counters.addCounter(name: 'Sets', startValue: 3);
      await counters.incrementGlobal(id);

      await hooks.beforePage('notes');

      expect((await db.counterDao.getValuesForNote(''))[id], 3);
    });
  });

  group('afterRun', () {
    test('the calendar reloads once, then the alerts are reconciled once', () async {
      await hooks.afterRun({
        SyncInvalidation.calendar,
        SyncInvalidation.alerts,
      });

      expect(calls, ['calendar', 'reconcile']);
    });

    test('alerts alone reload the alert services, then reconcile', () async {
      await hooks.afterRun({SyncInvalidation.alerts});

      expect(calls, ['alerts', 'reconcile']);
    });

    test('vocabularies reload; notes and folders reach no recorder', () async {
      await hooks.afterRun({
        SyncInvalidation.notes,
        SyncInvalidation.folders,
        SyncInvalidation.vocabularies,
      });

      expect(calls, ['vocabularies']);
    });

    test('counters reload and fire the changes signal', () async {
      final id = await counters.addCounter(name: 'Sets', startValue: 3);
      await db.counterDao.upsertValue(id, '', 8);
      var fired = 0;
      final subscription = counters.changes.listen((_) => fired++);
      addTearDown(subscription.cancel);

      await hooks.afterRun({SyncInvalidation.counters});
      await pumpEventQueue();

      expect(counters.getGlobalValue(id), 8);
      expect(fired, 1);
    });

    test('one failing effect does not stop the others', () async {
      calendarFailure = StateError('no gateway');
      final id = await counters.addCounter(name: 'Sets', startValue: 3);
      await db.counterDao.upsertValue(id, '', 8);

      await hooks.afterRun({
        SyncInvalidation.calendar,
        SyncInvalidation.alerts,
        SyncInvalidation.counters,
        SyncInvalidation.vocabularies,
      });

      expect(calls, ['calendar', 'reconcile', 'vocabularies']);
      expect(counters.getGlobalValue(id), 8);
    });
  });

  group('fileConflictCopy', () {
    Future<Note> loser() async {
      final note = await db.noteDao.createNote(
        folderId: 'f1',
        title: 'Squat log',
        label: ItemLabel.teal,
        content: 'theirs',
      );
      await db.noteDao.createNote(folderId: 'f1', title: 'Other');
      return note;
    }

    Future<List<Note>> copies() async =>
        (await db.noteDao.getNotesByFolder('f1'))
            .where((n) => n.title.startsWith('Squat log ('))
            .toList();

    test('files the losing text beside the note, stamped and queued', () async {
      final note = await loser();
      await db.syncOutboxDao.clear();

      await hooks.fileConflictCopy(
        SyncNoteConflict(loser: note, loserContent: 'my unpushed set'),
      );

      final copy = (await copies()).single;
      expect(copy.title, 'Squat log (conflict copy, 10/24/2026 09:05)');
      expect(await db.contentChunkDao.loadContent(copy.id), 'my unpushed set');
      expect(ItemLabel.fromStorage(copy.label), ItemLabel.teal);
      expect(copy.folderId, 'f1');
      expect(copy.position, 2, reason: "the folder's next free position");
      final queued = [
        for (final e in await db.syncOutboxDao.pending())
          '${e.syncedTable}/${e.rowKey}',
      ];
      expect(queued, ['notes/${copy.id}']);
    });

    test('files inside the page transaction and rolls back with it', () async {
      final note = await loser();
      final conflict = SyncNoteConflict(loser: note, loserContent: 'one');

      await db.transaction(() => hooks.fileConflictCopy(conflict));
      expect(await copies(), hasLength(1));

      await expectLater(
        db.transaction(() async {
          await hooks.fileConflictCopy(conflict);
          throw StateError('the page failed');
        }),
        throwsStateError,
      );
      expect(await copies(), hasLength(1));
    });

    test('a failure reaches the caller', () async {
      final note = await loser();
      await db.close();

      await expectLater(
        hooks.fileConflictCopy(
          SyncNoteConflict(loser: note, loserContent: 'one'),
        ),
        throwsA(anything),
      );
      db = await openTestDatabase();
    });

    test("files the copy at the root when the loser's folder was deleted, "
        'even while the folder is cached as live', () async {
      final folder = await db.folderDao.createFolder(name: 'Old');
      expect((await folders.getFolderById(folder.id))!.isDeleted, isFalse);
      final note = await db.noteDao.createNote(
        folderId: folder.id,
        title: 'Squat log',
        content: 'theirs',
      );
      await db.customStatement(
        'UPDATE folders SET is_deleted = 1 WHERE id = ?',
        [folder.id],
      );

      await hooks.fileConflictCopy(
        SyncNoteConflict(loser: note, loserContent: 'mine'),
      );

      final copy = (await db.noteDao.getAllNotes()).singleWhere(
        (n) => n.title.startsWith('Squat log ('),
      );
      expect(copy.folderId, '');
      expect(await db.contentChunkDao.loadContent(copy.id), 'mine');
    });

    test('a second copy the same minute takes a numbered title', () async {
      final note = await loser();
      final conflict = SyncNoteConflict(loser: note, loserContent: 'one');

      await hooks.fileConflictCopy(conflict);
      await hooks.fileConflictCopy(conflict);

      expect((await copies()).map((n) => n.title), {
        'Squat log (conflict copy, 10/24/2026 09:05)',
        'Squat log (conflict copy, 10/24/2026 09:05) (2)',
      });
    });
  });
}
