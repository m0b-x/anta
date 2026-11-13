import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/models/movable_item.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/move_coordinator.dart';
import 'package:anta/services/move_history_service.dart';
import 'package:anta/services/move_history_store.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/services/recent_destinations_service.dart';

import '../database/support/db_test_support.dart';

/// The selection move and its Undo, end to end over a real database: a
/// batch is one set-based write per kind, its outcomes are still reported
/// per item, and its Undo restores the whole unit or says what stayed.
///
/// The coordinator answers through snackbars, so each case runs it from a
/// mounted context; the database answers in real time, hence `runAsync`.
void main() {
  late AppDatabase db;
  late StatementCounter counter;
  late MoveHistoryService history;
  final l10n = AppLocalizationsEn();

  setUp(() async {
    counter = StatementCounter();
    db = await openTestDatabase(interceptor: counter);
    history = MoveHistoryService(store: InMemoryMoveHistoryStore());
    GetIt.I
      ..registerSingleton<FolderStorageService>(
        FolderStorageService(repository: FolderRepository(database: db)),
      )
      ..registerSingleton<NoteStorageService>(
        NoteStorageService(repository: NoteRepository(database: db)),
      )
      ..registerSingleton<MoveHistoryService>(history)
      ..registerSingleton<RecentDestinationsService>(
        RecentDestinationsService(),
      );
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (c) {
              context = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return context;
  }

  MovableItemRef noteRef(Note note) => MovableItemRef(
    kind: MovableItemKind.note,
    id: note.id,
    name: note.title,
    currentParentId: note.folderId,
  );

  Future<Note> noteRow(String id) {
    return (db.select(db.notes)..where((n) => n.id.equals(id))).getSingle();
  }

  Future<List<Note>> seedNotes(String folderId, int count, String prefix) {
    return Future.wait([
      for (var i = 0; i < count; i++)
        db.noteDao.createNote(folderId: folderId, title: '$prefix $i'),
    ]);
  }

  testWidgets('two hundred selected notes move in one batched write and one '
      'undo unit', (tester) async {
    final context = await pumpHost(tester);
    late Folder target;
    late List<Note> notes;
    await tester.runAsync(() async {
      final source = await db.folderDao.createFolder(name: 'Source');
      target = await db.folderDao.createFolder(name: 'Target');
      notes = await seedNotes(source.id, 200, 'Set');
      counter.reset();
      await MoveCoordinator.moveItemsTo(
        context,
        items: [for (final note in notes) noteRef(note)],
        targetParentId: target.id,
      );
    });
    await tester.pump();

    expect(counter.matching('UPDATE "notes"'), hasLength(1));
    expect(counter.executions('UPDATE "notes"'), 200);
    final rows = await tester.runAsync(
      () => Future.wait([for (final note in notes) noteRow(note.id)]),
    );
    expect(rows!.map((r) => r.folderId).toSet(), {target.id});
    expect(rows.map((r) => r.hlcTimestamp).toSet(), hasLength(1));
    expect(history.history, hasLength(200));
    expect(history.history.map((e) => e.batchId).toSet(), hasLength(1));
    expect(find.text(l10n.itemsMoved(200)), findsOneWidget);
  });

  // Share surfaces §6.11: the bar says what the move did to sharing when it
  // did one thing to all it moved, and nothing when it did none or several.
  testWidgets('a move into a shared folder ends its bar "· now shared", one '
      'out of it "· no longer shared"; a mixed one says neither', (
    tester,
  ) async {
    final context = await pumpHost(tester);
    late Folder shared;
    late Folder plain;
    late List<Note> notes;
    await tester.runAsync(() async {
      shared = await db.folderDao.createFolder(name: 'Trips');
      plain = await db.folderDao.createFolder(name: 'Plain');
      await db.folderDao.setSharedPair(shared.id, 'pair-1');
      notes = await seedNotes(plain.id, 2, 'Note');
      await MoveCoordinator.moveItemsTo(
        context,
        items: [noteRef(notes.first)],
        targetParentId: shared.id,
      );
    });
    await tester.pump();
    final into = l10n.shareMovedIn(l10n.noteMoved, l10n.sharePartnerFallback);
    expect(find.text(into), findsOneWidget);

    await tester.runAsync(
      () async => MoveCoordinator.moveItemsTo(
        context,
        items: [noteRef(await noteRow(notes.first.id))],
        targetParentId: plain.id,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(l10n.shareMovedOut(l10n.noteMoved)), findsOneWidget);

    // One already in the shared folder, one coming in: a mixed move.
    await tester.runAsync(() async {
      final inside = (await seedNotes(shared.id, 1, 'Inside')).single;
      final other = await db.folderDao.createFolder(name: 'Other');
      await MoveCoordinator.moveItemsTo(
        context,
        items: [noteRef(inside), noteRef(await noteRow(notes.last.id))],
        targetParentId: other.id,
      );
    });
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(l10n.itemsMoved(2)), findsOneWidget);
  });

  testWidgets('a name clash is skipped and reported, the rest still move', (
    tester,
  ) async {
    final context = await pumpHost(tester);
    late List<Note> picked;
    late Folder target;
    await tester.runAsync(() async {
      final source = await db.folderDao.createFolder(name: 'Source');
      target = await db.folderDao.createFolder(name: 'Target');
      await db.noteDao.createNote(folderId: target.id, title: 'Clash');
      picked = [
        await db.noteDao.createNote(folderId: source.id, title: 'clash'),
        await db.noteDao.createNote(folderId: source.id, title: 'Free'),
        await db.noteDao.createNote(folderId: source.id, title: 'Also free'),
      ];
      await MoveCoordinator.moveItemsTo(
        context,
        items: [for (final note in picked) noteRef(note)],
        targetParentId: target.id,
      );
    });
    await tester.pump();

    final rows = await tester.runAsync(
      () => Future.wait([for (final note in picked) noteRow(note.id)]),
    );
    expect(
      [for (final row in rows!) row.folderId == target.id],
      [false, true, true],
    );
    expect(history.history, hasLength(2));
    expect(find.text(l10n.moveSkippedDueToDuplicates(1)), findsOneWidget);
  });

  testWidgets('Undo of a 25-item batch restores all 25 and says so', (
    tester,
  ) async {
    final context = await pumpHost(tester);
    late Folder source;
    late List<Note> notes;
    await tester.runAsync(() async {
      source = await db.folderDao.createFolder(name: 'Source');
      final target = await db.folderDao.createFolder(name: 'Target');
      notes = await seedNotes(source.id, 25, 'Lift');
      await MoveCoordinator.moveItemsTo(
        context,
        items: [for (final note in notes) noteRef(note)],
        targetParentId: target.id,
      );
      final batchId = history.history.first.batchId!;
      await MoveCoordinator.undoBatch(context, batchId);
    });
    await tester.pump();

    final rows = await tester.runAsync(
      () => Future.wait([for (final note in notes) noteRow(note.id)]),
    );
    expect(rows!.map((r) => r.folderId).toSet(), {source.id});
    expect(history.undoableCount, 0);
    expect(find.text(l10n.moveUndone), findsOneWidget);
  });

  testWidgets('Undo sends a note whose folder is gone to the first folder, '
      'and counts a clash at the source instead of claiming success', (
    tester,
  ) async {
    final context = await pumpHost(tester);
    late Folder fallback;
    late Note orphan;
    late Note clashing;
    late Note plain;
    await tester.runAsync(() async {
      fallback = await db.folderDao.createFolder(name: 'Aaa first');
      final doomed = await db.folderDao.createFolder(name: 'Doomed');
      final home = await db.folderDao.createFolder(name: 'Home');
      final target = await db.folderDao.createFolder(name: 'Target');
      orphan = await db.noteDao.createNote(
        folderId: doomed.id,
        title: 'Orphan',
      );
      clashing = await db.noteDao.createNote(folderId: home.id, title: 'Same');
      plain = await db.noteDao.createNote(folderId: home.id, title: 'Plain');
      await MoveCoordinator.moveItemsTo(
        context,
        items: [noteRef(orphan), noteRef(clashing), noteRef(plain)],
        targetParentId: target.id,
      );
      await GetIt.I<FolderStorageService>().deleteFolder(doomed.id);
      // Someone files a note of the same name at home meanwhile.
      await db.noteDao.createNote(folderId: home.id, title: 'same');
      await MoveCoordinator.undoBatch(context, history.history.first.batchId!);
    });
    await tester.pump();

    final rows = await tester.runAsync(
      () => Future.wait([
        noteRow(orphan.id),
        noteRow(clashing.id),
        noteRow(plain.id),
      ]),
    );
    expect(rows![0].folderId, fallback.id);
    expect(rows[1].folderId, isNot(clashing.folderId));
    expect(rows[2].folderId, plain.folderId);
    expect(history.undoableCount, 1, reason: 'the clash stays undoable');
    expect(find.text(l10n.moveUndone), findsNothing);
    expect(find.text(l10n.moveSkippedDueToDuplicates(1)), findsOneWidget);
  });

  testWidgets('a database failure in the move or its Undo shows the failure '
      'snackbar instead of escaping', (tester) async {
    final context = await pumpHost(tester);
    late List<Note> notes;
    late Folder third;
    await tester.runAsync(() async {
      final source = await db.folderDao.createFolder(name: 'Source');
      final target = await db.folderDao.createFolder(name: 'Target');
      third = await db.folderDao.createFolder(name: 'Third');
      notes = await seedNotes(source.id, 2, 'Row');
      await MoveCoordinator.moveItemsTo(
        context,
        items: [for (final note in notes) noteRef(note)],
        targetParentId: target.id,
      );
      GetIt.I.unregister<NoteStorageService>();
      GetIt.I.registerSingleton<NoteStorageService>(
        _ThrowingNoteStorage(NoteRepository(database: db)),
      );
      await MoveCoordinator.undoBatch(context, history.history.first.batchId!);
    });
    await tester.pump();

    expect(find.text(l10n.noteMoveFailed), findsOneWidget);
    expect(history.undoableCount, 2, reason: 'nothing went back');

    await tester.runAsync(
      () => MoveCoordinator.moveItemsTo(
        context,
        items: [for (final note in notes) noteRef(note)],
        targetParentId: third.id,
      ),
    );
    await tester.pump();
    expect(find.text(l10n.noteMoveFailed), findsOneWidget);
  });
}

/// A note store whose bulk move fails the way a locked or full database
/// would.
class _ThrowingNoteStorage extends NoteStorageService {
  _ThrowingNoteStorage(NoteRepository repository)
    : super(repository: repository);

  @override
  Future<BulkMoveResult> moveNotes({
    required List<String> noteIds,
    required String targetFolderId,
  }) => throw StateError('database is locked');
}
