import 'dart:ui' show Locale;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:anta/constants/app_constants.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/models/item_label.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/calendar_event_service.dart';
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
  /// The notes an open editor is holding unsaved, for the copy D3 leaves to
  /// the editor (R99), and how often the copy's language was resolved (R104).
  late Set<String> editorNotes;
  late int stringsResolved;
  Object? stringsFailure;
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
    editorNotes = {};
    stringsResolved = 0;
    stringsFailure = null;
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
      strings: () async {
        stringsResolved++;
        if (stringsFailure != null) throw stringsFailure!;
        return lookupAppLocalizations(const Locale('en'));
      },
      editorClaimsFiling: editorNotes.contains,
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
    bool moved = false,
    String? previousParent,
    String? content,
  }) => SyncAppliedRow(
    rowKey: key,
    result: result,
    tombstone: tombstone,
    moved: moved,
    previousParent: previousParent,
    content: content,
  );

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
      expect(changes.every((c) => c.remote), isTrue);
    });

    test('a local write is not remote; only a merged change is', () async {
      final changes = <NoteChange>[];
      final subscription = notes.noteChanges.listen(changes.add);
      addTearDown(subscription.cancel);

      final note = await storage.createNote(
        folderId: 'f1',
        title: 'Log',
        content: 'mine',
      );
      await hooks.afterPage('notes', [row(note.id, MergeResult.applied)]);
      await pumpEventQueue();

      expect([for (final c in changes) (c.type, c.remote)], [
        (NoteChangeType.created, false),
        (NoteChangeType.updated, true),
      ]);
    });

    test('a note merged into another folder is announced as moved from the '
        'old one beside the update', () async {
      final note = await db.noteDao.createNote(folderId: 'f1', title: 'Log');
      final outcome = await db.noteDao.mergeNoteDocument(
        note.copyWith(
          folderId: 'f2',
          hlcTimestamp: 'ffffffffffff:0000:remote',
        ),
        'body',
      );
      expect((outcome.moved, outcome.previousParent), (true, 'f1'));
      final changes = <NoteChange>[];
      final subscription = notes.noteChanges.listen(changes.add);
      addTearDown(subscription.cancel);

      await hooks.afterPage('notes', [
        row(
          note.id,
          outcome.result,
          moved: outcome.moved,
          previousParent: outcome.previousParent,
        ),
      ]);
      await pumpEventQueue();

      expect(
        [
          for (final c in changes)
            (c.type, c.folderId, c.sourceFolderId, c.remote),
        ],
        [
          (NoteChangeType.updated, 'f2', null, true),
          (NoteChangeType.moved, 'f2', 'f1', true),
        ],
      );
    });

    test('a folder merged out of the root is announced as moved from it', () async {
      final parent = await db.folderDao.createFolder(name: 'Parent');
      final folder = await db.folderDao.createFolder(name: 'Child');
      final outcome = await db.folderDao.mergeFolder(
        folder.copyWith(
          parentId: Value(parent.id),
          hlcTimestamp: 'ffffffffffff:0000:remote',
        ),
      );
      expect((outcome.moved, outcome.previousParent), (true, null));
      final changes = <FolderChange>[];
      final subscription = folders.folderChanges.listen(changes.add);
      addTearDown(subscription.cancel);

      await hooks.afterPage('folders', [
        row(
          folder.id,
          outcome.result,
          moved: outcome.moved,
          previousParent: outcome.previousParent,
        ),
      ]);
      await pumpEventQueue();

      expect(
        [
          for (final c in changes)
            (c.type, c.parentId, c.sourceParentId, c.remote),
        ],
        [
          (FolderChangeType.updated, parent.id, null, true),
          (FolderChangeType.moved, parent.id, null, true),
        ],
      );
    });

    test('a note merged live over its tombstone is announced as updated', () async {
      final note = await db.noteDao.createNote(folderId: 'f1', title: 'Log');
      await db.noteDao.softDeleteNote(note.id);
      final remote = (await db.noteDao.getNoteById(note.id))!.copyWith(
        isDeleted: false,
        hlcTimestamp: 'ffffffffffff:0000:remote',
      );
      final outcome = await db.noteDao.mergeNoteDocument(remote, 'back');
      final changes = <NoteChange>[];
      final subscription = notes.noteChanges.listen(changes.add);
      addTearDown(subscription.cancel);

      await hooks.afterPage('notes', [row(note.id, outcome.result)]);
      await pumpEventQueue();

      expect(outcome.result, MergeResult.applied);
      expect([for (final c in changes) c.type], [NoteChangeType.updated]);
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

    test('the body a merged row carries is what the announcement hands the '
        'editor, and it is not cached (R4, R6)', () async {
      final note = await storage.createNote(
        folderId: 'f1',
        title: 'Log',
        content: 'mine',
      );
      final changes = <NoteChange>[];
      final subscription = notes.noteChanges.listen(changes.add);
      addTearDown(subscription.cancel);

      // The row still holds the local text — a save that committed after the
      // page did — and the page's own body is the one the editor must see.
      await hooks.afterPage('notes', [
        row(note.id, MergeResult.applied, content: 'theirs'),
      ]);
      await pumpEventQueue();

      expect(changes.single.remoteContent, 'theirs');
      expect(notes.isContentCached(note.id), isFalse);
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

    test('a counter page reloads the counters right after it, keeping a '
        'pending tap, and fires the changes signal', () async {
      final id = await counters.addCounter(name: 'Sets', startValue: 3);
      await counters.incrementGlobal(id);
      await db.counterDao.upsertValue(id, '', 8);
      var fired = 0;
      final subscription = counters.changes.listen((_) => fired++);
      addTearDown(subscription.cancel);

      await hooks.afterPage('counter_values', [
        row('$id|', MergeResult.applied),
      ]);
      await pumpEventQueue();

      expect(counters.getGlobalValue(id), 9);
      expect(fired, 1);
    });

    test('a counter page that changed nothing reloads nothing', () async {
      var fired = 0;
      final subscription = counters.changes.listen((_) => fired++);
      addTearDown(subscription.cancel);

      await hooks.afterPage('counters', [row('c1', MergeResult.keptLocal)]);
      await pumpEventQueue();

      expect(fired, 0);
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

    test('the calendar alone still reconciles the alerts', () async {
      await hooks.afterRun({SyncInvalidation.calendar});

      expect(calls, ['calendar', 'reconcile']);
    });

    test('counters are left to their pages', () async {
      final id = await counters.addCounter(name: 'Sets', startValue: 3);
      await db.counterDao.upsertValue(id, '', 8);

      await hooks.afterRun({SyncInvalidation.counters});

      expect(counters.getGlobalValue(id), 3);
      expect(calls, isEmpty);
    });

    test('an alerts-only pull tells the open calendar too, through the real '
        'reload (R78, R85)', () async {
      // The app's own static, not the recorder: what it does after the two
      // alert services is what an open calendar page and the Alerts hub
      // hear, and only the dispatch order was pinned until now.
      final live = AppSyncApplyHooks(
        notes: () => notes,
        folders: () => folders,
        noteStorage: () => storage,
        counters: () async => counters,
        reconcileAlerts: () async => calls.add('reconcile'),
        strings: () async => lookupAppLocalizations(const Locale('en')),
        now: () => now,
      );
      var signalled = 0;
      final subscription = CalendarEventService.externalChanges.listen(
        (_) => signalled++,
      );
      addTearDown(subscription.cancel);

      await live.afterRun({SyncInvalidation.alerts});
      await pumpEventQueue();

      expect(signalled, 1);
      expect(calls, ['reconcile']);
    });

    test('one failing effect does not stop the others', () async {
      calendarFailure = StateError('no gateway');

      await hooks.afterRun({
        SyncInvalidation.calendar,
        SyncInvalidation.alerts,
        SyncInvalidation.vocabularies,
      });

      expect(calls, ['calendar', 'reconcile', 'vocabularies']);
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

    const stamp = 'Oct 24, 2026 09:05';

    test('files the losing text beside the note, stamped and queued, and '
        'returns its id', () async {
      final note = await loser();
      await db.syncOutboxDao.clear();

      final id = await hooks.fileConflictCopy(
        SyncNoteConflict(loser: note, loserContent: 'my unpushed set'),
      );

      final copy = (await copies()).single;
      expect(id, copy.id);
      expect(copy.title, 'Squat log (conflict copy, $stamp)');
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

    test('files nothing for a note an open editor holds unsaved: that page '
        'files the arriving body itself (R99)', () async {
      final note = await loser();
      editorNotes.add(note.id);

      final id = await hooks.fileConflictCopy(
        SyncNoteConflict(loser: note, loserContent: 'my unpushed set'),
      );

      expect(id, isNull);
      expect(await copies(), isEmpty);
    });

    test('a copy is still filed for a note no editor holds', () async {
      final note = await loser();
      editorNotes.add('another-note');

      final id = await hooks.fileConflictCopy(
        SyncNoteConflict(loser: note, loserContent: 'my unpushed set'),
      );

      expect(id, isNotNull);
      expect(await copies(), hasLength(1));
    });

    test("resolves the copy's language before the page, never from inside "
        'its transaction (R104)', () async {
      final note = await loser();

      await hooks.beforePage('notes');
      expect(stringsResolved, 1, reason: 'outside the page transaction');

      await db.transaction(
        () => hooks.fileConflictCopy(
          SyncNoteConflict(loser: note, loserContent: 'my unpushed set'),
        ),
      );

      expect(stringsResolved, 1);
      expect((await copies()).single.title, 'Squat log (conflict copy, $stamp)');
    });

    test('a language that cannot be read fails the page before its '
        'transaction, never from inside it (R139)', () async {
      stringsFailure = StateError('no locale');

      await expectLater(hooks.beforePage('notes'), throwsStateError);
      expect(stringsResolved, 1);
    });

    test('the page\'s language does not outlive the page (R147)', () async {
      await hooks.beforePage('notes');
      await hooks.afterPage('notes', const []);
      final note = await loser();

      await hooks.fileConflictCopy(
        SyncNoteConflict(loser: note, loserContent: 'my unpushed set'),
      );

      expect(stringsResolved, 2, reason: 'the next page resolves afresh');
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

    test('caches and announces nothing: the engine announces the id after '
        'the page committed', () async {
      final note = await loser();
      final changes = <NoteChange>[];
      final subscription = notes.noteChanges.listen(changes.add);
      addTearDown(subscription.cancel);

      final id = await hooks.fileConflictCopy(
        SyncNoteConflict(loser: note, loserContent: 'mine'),
      );
      await pumpEventQueue();

      expect(changes, isEmpty);
      expect(notes.isContentCached(id!), isFalse);

      await hooks.afterPage('notes', [row(id, MergeResult.inserted)]);
      await pumpEventQueue();

      expect([for (final c in changes) (c.type, c.noteId)], [
        (NoteChangeType.created, id),
      ]);
    });

    Future<Note> noteIn(String folderId) => db.noteDao.createNote(
      folderId: folderId,
      title: 'Squat log',
      content: 'theirs',
    );

    Future<void> tombstone(String folderId) => db.customStatement(
      'UPDATE folders SET is_deleted = 1 WHERE id = ?',
      [folderId],
    );

    Future<Note> copyOf(Note note) async {
      final id = await hooks.fileConflictCopy(
        SyncNoteConflict(loser: note, loserContent: 'mine'),
      );
      return (await db.noteDao.getNoteById(id!))!;
    }

    test("files the copy in the nearest live ancestor when the loser's "
        'folder was deleted, even while the folder is cached as live', () async {
      final kept = await db.folderDao.createFolder(name: 'Training');
      final gone = await db.folderDao.createFolder(
        name: 'Old',
        parentId: kept.id,
      );
      final deeper = await db.folderDao.createFolder(
        name: 'Older',
        parentId: gone.id,
      );
      expect((await folders.getFolderById(deeper.id))!.isDeleted, isFalse);
      final note = await noteIn(deeper.id);
      await tombstone(gone.id);
      await tombstone(deeper.id);

      final copy = await copyOf(note);

      expect(copy.folderId, kept.id);
      expect(await db.contentChunkDao.loadContent(copy.id), 'mine');
    });

    test('a page that rolls back leaves no folder it read cached as '
        'deleted (S4a review L11)', () async {
      final folder = await db.folderDao.createFolder(name: 'Training');
      final note = await noteIn(folder.id);

      await expectLater(
        db.transaction(() async {
          // The page merged the folder as deleted, then filed the copy.
          await tombstone(folder.id);
          expect((await copyOf(note)).folderId, '');
          throw StateError('the page failed');
        }),
        throwsStateError,
      );

      expect((await folders.getFolderById(folder.id))!.isDeleted, isFalse);
    });

    test('files the copy at the root when no ancestor is live', () async {
      final top = await db.folderDao.createFolder(name: 'Old');
      final folder = await db.folderDao.createFolder(
        name: 'Older',
        parentId: top.id,
      );
      final note = await noteIn(folder.id);
      await tombstone(top.id);
      await tombstone(folder.id);

      expect((await copyOf(note)).folderId, '');
    });

    test('a second copy the same minute takes a numbered title', () async {
      final note = await loser();
      final conflict = SyncNoteConflict(loser: note, loserContent: 'one');

      await hooks.fileConflictCopy(conflict);
      await hooks.fileConflictCopy(conflict);

      expect((await copies()).map((n) => n.title), {
        'Squat log (conflict copy, $stamp)',
        'Squat log (conflict copy, $stamp) (2)',
      });
    });

    test('a long title is cut so the copy fits the title column', () async {
      final note = await db.noteDao.createNote(
        folderId: 'f1',
        title: 'x' * 480,
        content: 'theirs',
      );
      final conflict = SyncNoteConflict(loser: note, loserContent: 'one');

      final first = await copyOf(note);
      final second = (await db.noteDao.getNoteById(
        (await hooks.fileConflictCopy(conflict))!,
      ))!;

      expect(first.title.length, AppConstants.maxNoteTitleLength);
      expect(first.title, endsWith(' (conflict copy, $stamp)'));
      expect(second.title.length, AppConstants.maxNoteTitleLength);
      expect(second.title, endsWith(' (conflict copy, $stamp) (2)'));
    });

    test('an untitled note is named as the browser names it', () async {
      final note = await db.noteDao.createNote(
        folderId: 'f1',
        title: '',
        content: 'theirs',
      );

      expect(
        (await copyOf(note)).title,
        'Untitled Note (conflict copy, $stamp)',
      );
    });

    test('the date carries no slash in any language', () {
      for (final locale in AppLocalizations.supportedLocales) {
        final title = lookupAppLocalizations(
          locale,
        ).syncConflictCopyTitle('Log', now);
        expect(title, isNot(contains('/')), reason: locale.languageCode);
      }
    });
  });
}
