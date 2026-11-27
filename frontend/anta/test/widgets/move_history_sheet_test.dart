import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:anta/constants/app_theme.dart';
import 'package:anta/constants/semantics_ids.dart';
import 'package:anta/database/database.dart';
import 'package:anta/l10n/app_localizations.dart';
import 'package:anta/l10n/app_localizations_en.dart';
import 'package:anta/repositories/folder_repository.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/folder_storage_service.dart';
import 'package:anta/services/move_history_service.dart';
import 'package:anta/services/move_history_store.dart';
import 'package:anta/services/note_storage_service.dart';
import 'package:anta/widgets/move_history_sheet.dart';

import '../database/support/db_test_support.dart';

/// Move history's sheet as the browser's ⋮ opens it: the entries newest
/// first, an entry's undo over a real database, Clear through its confirm,
/// the empty state, and the ids the browser flows target.
///
/// The undo writes through `MoveCoordinator` in real time, so a case that
/// taps one turns the real event loop until the entry reads undone.
void main() {
  late AppDatabase db;
  late MoveHistoryService history;
  final l10n = AppLocalizationsEn();

  setUp(() async {
    db = await openTestDatabase();
    history = MoveHistoryService(store: InMemoryMoveHistoryStore());
    GetIt.I
      ..registerSingleton<FolderStorageService>(
        FolderStorageService(repository: FolderRepository(database: db)),
      )
      ..registerSingleton<NoteStorageService>(
        NoteStorageService(repository: NoteRepository(database: db)),
      )
      ..registerSingleton<MoveHistoryService>(history);
  });

  tearDown(() async {
    await GetIt.I.reset();
    await db.close();
  });

  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showMoveHistorySheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// A note's move from [from] to [to] as the history records it; the
  /// database is not touched.
  String recordMove(
    String name, {
    String itemId = 'note',
    String? from,
    String? fromName,
    String? to,
    String? toName,
  }) {
    return history.addMove(
      itemType: MoveItemType.note,
      itemId: itemId,
      itemName: name,
      sourceParentId: from,
      sourceParentName: fromName,
      targetParentId: to,
      targetParentName: toName,
    );
  }

  testWidgets('lists the entries newest first, each with its own undo', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    recordMove('Session 1', itemId: 'n1', toName: 'Week 1');
    recordMove('Session 2', itemId: 'n2', toName: 'Inbox');

    await openSheet(tester);

    expect(find.text(l10n.moveHistory), findsOneWidget);
    expect(find.text(l10n.movedToTarget('Week 1')), findsOneWidget);
    expect(find.text(l10n.movedToTarget('Inbox')), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Session 2')).dy,
      lessThan(tester.getTopLeft(find.text('Session 1')).dy),
      reason: 'the newest move first',
    );

    final newest = find.bySemanticsIdentifier(SemanticsIds.moveHistoryUndo(0));
    expect(newest, findsOneWidget);
    expect(
      tester.getSemantics(newest),
      isSemantics(isButton: true, hasTapAction: true, tooltip: l10n.undo),
      reason: 'the id lands on the button itself',
    );
    expect(
      tester.getCenter(newest).dy,
      closeTo(tester.getCenter(find.text('Session 2')).dy, 24),
      reason: 'undo 0 is the newest entry\'s',
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.moveHistoryUndo(1)),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.moveHistoryUndo(2)),
      findsNothing,
    );
    semantics.dispose();
  });

  testWidgets('an entry\'s undo puts the note back and strikes its row', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    late Folder week;
    late Note note;
    late String entryId;
    await tester.runAsync(() async {
      week = await db.folderDao.createFolder(name: 'Week 1');
      final inbox = await db.folderDao.createFolder(name: 'Inbox');
      note = await db.noteDao.createNote(
        folderId: inbox.id,
        title: 'Session 1',
      );
      entryId = recordMove(
        'Session 1',
        itemId: note.id,
        from: week.id,
        fromName: week.name,
        to: inbox.id,
        toName: inbox.name,
      );
    });

    await openSheet(tester);
    await tester.tap(
      find.bySemanticsIdentifier(SemanticsIds.moveHistoryUndo(0)),
    );
    for (var turn = 0; turn < 200; turn++) {
      if (history.isEntryUndone(entryId)) break;
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    await tester.pump();

    expect(history.isEntryUndone(entryId), isTrue);
    final row = await tester.runAsync(
      () =>
          (db.select(db.notes)..where((n) => n.id.equals(note.id))).getSingle(),
    );
    expect(row!.folderId, week.id, reason: 'back where it came from');
    expect(find.text(l10n.undone), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Session 1')).style?.decoration,
      TextDecoration.lineThrough,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.moveHistoryUndo(0)),
      findsNothing,
      reason: 'an undone entry offers no second undo',
    );
    expect(find.text(l10n.moveUndone), findsOneWidget);

    // Lets the snackbar run out before the tree goes.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('Clear asks first: Cancel keeps the history, the confirm '
      'empties it to the empty line', (tester) async {
    final semantics = tester.ensureSemantics();
    recordMove('Session 1', toName: 'Week 1');

    await openSheet(tester);
    final clear = find.bySemanticsIdentifier(SemanticsIds.moveHistoryClear);
    expect(clear, findsOneWidget);
    expect(
      tester.getSemantics(clear),
      isSemantics(isButton: true, hasTapAction: true, label: l10n.clearHistory),
      reason: 'the id lands on the button itself',
    );

    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(find.text(l10n.clearMoveHistoryConfirm), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sheetCancel));
    await tester.pumpAndSettle();
    expect(history.history, hasLength(1));
    expect(find.text('Session 1'), findsOneWidget);

    await tester.tap(clear);
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsIdentifier(SemanticsIds.sheetConfirm));
    await tester.pumpAndSettle();

    expect(history.history, isEmpty);
    expect(find.text('Session 1'), findsNothing);
    expect(find.text(l10n.noMoveHistory), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.moveHistoryClear),
      findsNothing,
      reason: 'nothing left to clear',
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.moveHistorySheet),
      findsOneWidget,
      reason: 'the sheet stays open on its empty state',
    );
    semantics.dispose();
  });

  testWidgets('with no moves the sheet says so and offers no Clear', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await openSheet(tester);

    expect(
      find.bySemanticsIdentifier(SemanticsIds.moveHistorySheet),
      findsOneWidget,
    );
    expect(find.text(l10n.moveHistory), findsOneWidget);
    expect(find.text(l10n.noMoveHistory), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticsIds.moveHistoryClear),
      findsNothing,
    );
    expect(
      find.bySemanticsIdentifier(SemanticsIds.moveHistoryUndo(0)),
      findsNothing,
    );
    semantics.dispose();
  });

  testWidgets('the sheet\'s id does not swallow its title or the empty line', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await openSheet(tester);

    final title = tester.getSemantics(find.text(l10n.moveHistory));
    final empty = tester.getSemantics(find.text(l10n.noMoveHistory));
    expect(title.label, l10n.moveHistory, reason: 'the title is its own stop');
    expect(empty.label, l10n.noMoveHistory);
    expect(title.id, isNot(empty.id));

    recordMove('Session 1', toName: 'Week 1');
    await tester.pumpAndSettle();
    final sheet = tester.getSemantics(
      find.bySemanticsIdentifier(SemanticsIds.moveHistorySheet),
    );
    final titled = tester.getSemantics(find.text(l10n.moveHistory));
    expect(titled.label, l10n.moveHistory);
    expect(
      titled.id,
      isNot(sheet.id),
      reason: 'the title is not the sheet-wide node\'s label',
    );
    semantics.dispose();
  });

  testWidgets('an undo\'s id counts undone entries too, so an entry keeps '
      'its index when the one above it is undone', (tester) async {
    final semantics = tester.ensureSemantics();
    recordMove('Session 1', itemId: 'n1', toName: 'Week 1');
    final newest = recordMove('Session 2', itemId: 'n2', toName: 'Inbox');

    await openSheet(tester);
    history.markUndone(newest);
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsIdentifier(SemanticsIds.moveHistoryUndo(0)),
      findsNothing,
      reason: 'the undone entry offers no undo',
    );
    final lower = find.bySemanticsIdentifier(SemanticsIds.moveHistoryUndo(1));
    expect(lower, findsOneWidget);
    expect(
      tester.getCenter(lower).dy,
      closeTo(tester.getCenter(find.text('Session 1')).dy, 24),
      reason: 'undo 1 stays the older entry\'s',
    );
    semantics.dispose();
  });
}
