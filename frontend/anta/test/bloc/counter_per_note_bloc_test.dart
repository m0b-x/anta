import 'dart:async';

import 'package:drift/drift.dart' show QueryExecutor, QueryInterceptor;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/counter_per_note/counter_per_note_bloc.dart';
import 'package:anta/bloc/counter_per_note/counter_per_note_event.dart';
import 'package:anta/bloc/counter_per_note/counter_per_note_state.dart';
import 'package:anta/database/daos/sync_dao.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/counter.dart';
import 'package:anta/repositories/note_repository.dart';
import 'package:anta/services/counter_service.dart';

import '../database/support/db_test_support.dart';

/// Pins that the per-note page's bloc follows `CounterService.changes`: a
/// value a sync pull merged shows in place, without the loading state.
void main() {
  late AppDatabase db;
  late CounterService service;
  late CounterPerNoteBloc bloc;

  setUp(() async {
    db = await openTestDatabase();
    service = await CounterService.forTesting(db);
    bloc = CounterPerNoteBloc(
      counterService: service,
      noteRepository: NoteRepository(database: db),
    );
  });

  tearDown(() async {
    await bloc.close();
    await service.flush();
    await db.close();
  });

  test("a row opens the editor with flagged metadata: the partner's note "
      'reads as theirs (§6.13)', () async {
    final note = await db.noteDao.createNote(
      folderId: 'f1',
      title: 'Their log',
    );
    final laps = await service.addCounter(
      name: 'Laps',
      scope: CounterScope.perNote,
    );
    await service.setValueForNote(laps, 3, noteId: note.id);
    await db.customStatement(
      "UPDATE notes SET owner_id = 'partner' WHERE id = ?",
      [note.id],
    );
    await db.syncDao.setValue(SyncDao.keySharedOwner, 'partner');
    ShareCensus.of(db).forget();

    bloc.add(CounterPerNoteOpened(counterId: laps));
    await pumpEventQueue();

    final entry = (bloc.state as CounterPerNoteLoaded).entries.single;
    expect(entry.note.fromPartner, isTrue);
  });

  test('a reload beneath the service re-reads the entries in place', () async {
    final note = await db.noteDao.createNote(folderId: 'f1', title: 'Log');
    final laps = await service.addCounter(
      name: 'Laps',
      scope: CounterScope.perNote,
    );
    await service.setValueForNote(laps, 2, noteId: note.id);
    bloc.add(CounterPerNoteOpened(counterId: laps));
    await pumpEventQueue();
    expect((bloc.state as CounterPerNoteLoaded).entries.single.value, 2);
    final states = <CounterPerNoteState>[];
    final subscription = bloc.stream.listen(states.add);
    addTearDown(subscription.cancel);

    await db.counterDao.upsertValue(laps, note.id, 9);
    await service.reload();
    await pumpEventQueue();

    expect(states, hasLength(1), reason: 'no loading state in between');
    expect((states.single as CounterPerNoteLoaded).entries.single.value, 9);
  });

  test(
    'a tap still pending at a reload shows on top of the merged value',
    () async {
      final note = await db.noteDao.createNote(folderId: 'f1', title: 'Log');
      final laps = await service.addCounter(
        name: 'Laps',
        scope: CounterScope.perNote,
      );
      await service.setValueForNote(laps, 2, noteId: note.id);
      bloc.add(CounterPerNoteOpened(counterId: laps));
      await pumpEventQueue();

      await service.increment(laps, noteId: note.id);
      await db.counterDao.upsertValue(laps, note.id, 9);
      await service.reload();
      await pumpEventQueue();

      expect((bloc.state as CounterPerNoteLoaded).entries.single.value, 10);
      expect(await db.counterDao.getValue(laps, note.id), 10);
    },
  );

  test('a counter that is gone is a typed error the page words', () async {
    final laps = await service.addCounter(
      name: 'Laps',
      scope: CounterScope.perNote,
    );
    await service.deleteCounter(laps);

    bloc.add(CounterPerNoteOpened(counterId: laps));
    await pumpEventQueue();

    expect(
      bloc.state,
      const CounterPerNoteError(CounterPerNoteFailure.counterNotFound),
    );
  });

  test('pinning one of 40 notes moves only that one, on the page and in the '
      'stored positions', () async {
    final laps = await service.addCounter(
      name: 'Laps',
      scope: CounterScope.perNote,
    );
    for (var i = 0; i < 40; i++) {
      final note = await db.noteDao.createNote(folderId: 'f1', title: 'N$i');
      await service.setValueForNote(laps, i, noteId: note.id);
    }
    await service.flush();
    // Every value starts at position 0: a reorder gives them their own.
    bloc.add(CounterPerNoteOpened(counterId: laps));
    await pumpEventQueue();
    bloc.add(const CounterPerNoteReorder(oldIndex: 0, newIndex: 1));
    await pumpEventQueue();
    List<String> order() => [
      for (final e in (bloc.state as CounterPerNoteLoaded).entries) e.note.id,
    ];
    final before = order();

    bloc.add(CounterPerNoteTogglePin(noteId: before[20]));
    await pumpEventQueue();

    final expected = [before[20], ...before.take(20), ...before.skip(21)];
    expect(order(), expected);
    final stored = await service.getOrderedNoteValuesForCounter(laps);
    expect(stored.map((r) => r.noteId), expected);
  });

  test('a tap made while a pin is written stays on the page', () async {
    final note = await db.noteDao.createNote(folderId: 'f1', title: 'Log');
    final laps = await service.addCounter(
      name: 'Laps',
      scope: CounterScope.perNote,
    );
    await service.setValueForNote(laps, 2, noteId: note.id);
    bloc.add(CounterPerNoteOpened(counterId: laps));
    await pumpEventQueue();

    bloc
      ..add(CounterPerNoteTogglePin(noteId: note.id))
      ..add(CounterPerNoteIncrement(noteId: note.id));
    await pumpEventQueue();

    final entry = (bloc.state as CounterPerNoteLoaded).entries.single;
    expect(entry.isPinned, isTrue);
    expect(entry.value, 3);
    expect(await service.getValueForNote(laps, note.id), 3);
  });

  test('a write that failed is carried in the state', () async {
    final note = await db.noteDao.createNote(folderId: 'f1', title: 'Log');
    final laps = await service.addCounter(
      name: 'Laps',
      scope: CounterScope.perNote,
    );
    await service.setValueForNote(laps, 2, noteId: note.id);
    bloc.add(CounterPerNoteOpened(counterId: laps));
    await pumpEventQueue();
    // Gone beneath the open page, as a sync pull can do.
    await service.deleteCounter(laps);

    final done = Completer<bool>();
    bloc.add(CounterPerNoteReset(noteId: note.id, done: done));

    await expectLater(done.future, throwsStateError);
    expect((bloc.state as CounterPerNoteLoaded).lastError, isNotNull);

    final all = Completer<bool>();
    bloc.add(CounterPerNoteResetAll(done: all));
    await expectLater(all.future, throwsStateError);
  });

  test('a Reset sent before the values are loaded answers that nothing was '
      'attempted, not that it failed', () async {
    final done = Completer<bool>();
    bloc.add(CounterPerNoteReset(noteId: 'n1', done: done));
    final all = Completer<bool>();
    bloc.add(CounterPerNoteResetAll(done: all));

    expect(await done.future, isFalse);
    expect(await all.future, isFalse);
  });

  test('a tap made during a refresh stays on the page', () async {
    final note = await db.noteDao.createNote(folderId: 'f1', title: 'Log');
    final laps = await service.addCounter(
      name: 'Laps',
      scope: CounterScope.perNote,
    );
    await service.setValueForNote(laps, 2, noteId: note.id);
    bloc.add(CounterPerNoteOpened(counterId: laps));
    await pumpEventQueue();

    // The tap lands while the refresh flushes and reads the table.
    bloc
      ..add(const CounterPerNoteRefreshed())
      ..add(CounterPerNoteIncrement(noteId: note.id));
    await pumpEventQueue();

    expect((bloc.state as CounterPerNoteLoaded).entries.single.value, 3);
    expect(await service.getValueForNote(laps, note.id), 3);
  });

  test(
    'a tap made while a refresh reads the notes stays on the page',
    () async {
      final statements = StatementCounter();
      final heldDb = await openTestDatabase(interceptor: statements);
      addTearDown(heldDb.close);
      final counters = await CounterService.forTesting(heldDb);
      final perNote = CounterPerNoteBloc(
        counterService: counters,
        noteRepository: NoteRepository(database: heldDb),
      );
      addTearDown(perNote.close);
      final note = await heldDb.noteDao.createNote(
        folderId: 'f1',
        title: 'Log',
      );
      final laps = await counters.addCounter(
        name: 'Laps',
        scope: CounterScope.perNote,
      );
      await counters.setValueForNote(laps, 2, noteId: note.id);
      perNote.add(CounterPerNoteOpened(counterId: laps));
      await pumpEventQueue();

      // The value rows are read; the notes they name are not yet.
      final reached = Completer<void>();
      final release = Completer<void>();
      statements.onStatement = (sql, _) {
        if (!sql.contains('FROM "notes"') || reached.isCompleted) return null;
        reached.complete();
        return release.future;
      };
      perNote.add(const CounterPerNoteRefreshed());
      await reached.future;
      perNote.add(CounterPerNoteIncrement(noteId: note.id));
      await pumpEventQueue();
      release.complete();
      await pumpEventQueue();

      expect((perNote.state as CounterPerNoteLoaded).entries.single.value, 3);
      expect(await counters.getValueForNote(laps, note.id), 3);
    },
  );

  test('a reorder that could not be written is carried in the state', () async {
    final writes = _RefuseCounterValueUpdates();
    final failing = await openTestDatabase(interceptor: writes);
    addTearDown(failing.close);
    final counters = await CounterService.forTesting(failing);
    final perNote = CounterPerNoteBloc(
      counterService: counters,
      noteRepository: NoteRepository(database: failing),
    );
    addTearDown(perNote.close);
    final laps = await counters.addCounter(
      name: 'Laps',
      scope: CounterScope.perNote,
    );
    for (final title in ['A', 'B']) {
      final note = await failing.noteDao.createNote(
        folderId: 'f1',
        title: title,
      );
      await counters.setValueForNote(laps, 1, noteId: note.id);
    }
    perNote.add(CounterPerNoteOpened(counterId: laps));
    await pumpEventQueue();

    writes.armed = true;
    perNote.add(const CounterPerNoteReorder(oldIndex: 0, newIndex: 1));
    await pumpEventQueue();

    expect(writes.refused, isPositive);
    expect((perNote.state as CounterPerNoteLoaded).lastError, isNotNull);
  });

  test('a reload before the page opened leaves the bloc as it was', () async {
    await service.reload();
    await pumpEventQueue();

    expect(bloc.state, const CounterPerNoteInitial());
  });
}

/// Refuses every update to `counter_values` while [armed], as a failing disk
/// would.
class _RefuseCounterValueUpdates extends QueryInterceptor {
  bool armed = false;
  int refused = 0;

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    if (armed && statement.contains('counter_values')) {
      refused++;
      throw StateError('counter_values refused');
    }
    return super.runUpdate(executor, statement, args);
  }
}
