import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/counter_per_note/counter_per_note_bloc.dart';
import 'package:anta/bloc/counter_per_note/counter_per_note_event.dart';
import 'package:anta/bloc/counter_per_note/counter_per_note_state.dart';
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

  test('a reload before the page opened leaves the bloc as it was', () async {
    await service.reload();
    await pumpEventQueue();

    expect(bloc.state, const CounterPerNoteInitial());
  });
}
