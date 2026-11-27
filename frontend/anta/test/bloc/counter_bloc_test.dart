import 'dart:async';

import 'package:drift/drift.dart' show QueryExecutor, QueryInterceptor;
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import 'package:anta/bloc/counter/counter_bloc.dart';
import 'package:anta/controllers/shortcut_applier.dart';
import 'package:anta/database/database.dart';
import 'package:anta/models/counter.dart';
import 'package:anta/models/custom_markdown_shortcut.dart';
import 'package:anta/services/counter_service.dart';

import '../database/support/db_test_support.dart';

/// Pins that the bloc follows `CounterService.changes`: counters a sync pull
/// re-read beneath the service reach a loaded state without a new load.
void main() {
  late AppDatabase db;
  late CounterService service;
  late CounterBloc bloc;

  setUp(() async {
    db = await openTestDatabase();
    service = await CounterService.forTesting(db);
    bloc = CounterBloc(counterService: service);
  });

  tearDown(() async {
    await bloc.close();
    await service.flush();
    await db.close();
  });

  test('a reload beneath the service refreshes the loaded counters', () async {
    final sets = await service.addCounter(name: 'Sets', startValue: 3);
    bloc.add(const LoadCounters());
    await pumpEventQueue();
    expect((bloc.state as CounterLoaded).counterValues, {sets: 3});

    // A pull merged a new value under the service's cache.
    await db.counterDao.upsertValue(sets, '', 8);
    await service.reload();
    await pumpEventQueue();

    expect((bloc.state as CounterLoaded).counterValues, {sets: 8});
  });

  test('a reload re-reads the values picked on a card', () async {
    final laps = await service.addCounter(
      name: 'Laps',
      scope: CounterScope.perNote,
    );
    await service.setValueForNote(laps, 2, noteId: 'n1');
    await service.flush();
    bloc.add(const LoadCounters());
    await pumpEventQueue();
    bloc.add(LoadCounterForNote(counterId: laps, noteId: 'n1'));
    await pumpEventQueue();
    expect((bloc.state as CounterLoaded).pickedNoteValues, {
      (counterId: laps, noteId: 'n1'): 2,
    });

    await db.counterDao.upsertValue(laps, 'n1', 7);
    await service.reload();
    await pumpEventQueue();

    expect((bloc.state as CounterLoaded).pickedNoteValues, {
      (counterId: laps, noteId: 'n1'): 7,
    });
  });

  test('a reload before the first load leaves the bloc unloaded', () async {
    await service.reload();
    await pumpEventQueue();

    expect(bloc.state, const CounterInitial());
  });

  test('a tap made while an edit is written stays on the page', () async {
    final sets = await service.addCounter(name: 'Sets', startValue: 3);
    bloc.add(const LoadCounters());
    await pumpEventQueue();
    final counter = service.getCounterById(sets)!;

    bloc
      ..add(UpdateCounter(counter: counter.copyWith(name: 'Rounds')))
      ..add(IncrementCounter(counterId: sets));
    await pumpEventQueue();

    final loaded = bloc.state as CounterLoaded;
    expect(loaded.counters.single.name, 'Rounds');
    expect(loaded.counterValues, {sets: 4});
  });

  test('a tap right after a Reset shows on top of the start value', () async {
    final sets = await service.addCounter(name: 'Sets', startValue: 0);
    await service.incrementGlobal(sets);
    await service.flush();
    bloc.add(const LoadCounters());
    await pumpEventQueue();
    await service.incrementGlobal(sets);
    final flushing = service.flush();

    bloc
      ..add(ResetCounter(counterId: sets))
      ..add(IncrementCounter(counterId: sets));
    await flushing;
    await pumpEventQueue();

    expect((bloc.state as CounterLoaded).counterValues, {sets: 1});
    expect(service.getGlobalValue(sets), 1);
  });

  test('a write that failed is carried in the state', () async {
    final sets = await service.addCounter(name: 'Sets', startValue: 3);
    bloc.add(const LoadCounters());
    await pumpEventQueue();
    // Gone beneath the loaded page, as a sync pull can do.
    await service.deleteCounter(sets);

    final done = Completer<bool>();
    bloc.add(ResetCounter(counterId: sets, done: done));

    await expectLater(done.future, throwsStateError);
    expect((bloc.state as CounterLoaded).lastError, isNotNull);
  });

  test('a delete answers that it was made', () async {
    final sets = await service.addCounter(name: 'Sets', startValue: 3);
    bloc.add(const LoadCounters());
    await pumpEventQueue();

    final done = Completer<bool>();
    bloc.add(DeleteCounter(counterId: sets, done: done));

    expect(await done.future, isTrue);
    expect((bloc.state as CounterLoaded).counters, isEmpty);
  });

  test('a Reset sent before the counters are loaded answers that nothing '
      'was attempted, not that it failed', () async {
    final sets = await service.addCounter(name: 'Sets', startValue: 3);

    final done = Completer<bool>();
    bloc.add(ResetCounter(counterId: sets, done: done));

    expect(await done.future, isFalse);
  });

  test('a tap made during a refresh stays on the page', () async {
    final sets = await service.addCounter(name: 'Sets', startValue: 0);
    bloc.add(const LoadCounters());
    await pumpEventQueue();

    bloc
      ..add(const RefreshCounters())
      ..add(IncrementCounter(counterId: sets));
    await pumpEventQueue();

    expect((bloc.state as CounterLoaded).counterValues, {sets: 1});
    expect(service.getGlobalValue(sets), 1);
  });

  group('with a value picked on a card and the note cache cold', () {
    late String laps;

    setUp(() async {
      laps = await service.addCounter(
        name: 'Laps',
        scope: CounterScope.perNote,
        startValue: 0,
      );
      await service.setValueForNote(laps, 4, noteId: 'n1');
      await service.setValueForNote(laps, 7, noteId: 'n2');
      await service.flush();
      bloc.add(const LoadCounters(noteId: 'n1'));
      await pumpEventQueue();
      bloc.add(LoadCounterForNote(counterId: laps, noteId: 'n2'));
      await pumpEventQueue();
      // A sync pull: the reload empties the note cache and its refresh has
      // run; the next pull's reload empties it again.
      await service.reload();
      await pumpEventQueue();
      await service.reload();
    });

    Future<void> expectShown(int loaded) async {
      await pumpEventQueue();
      final state = bloc.state as CounterLoaded;
      expect(state.counterValues[laps], loaded);
      expect(await service.getValueForNote(laps, 'n1'), loaded);
      expect(state.pickedNoteValues[(counterId: laps, noteId: 'n2')], 7);
    }

    test('a tap made during a refresh stays on the page', () async {
      bloc
        ..add(const RefreshCounters())
        ..add(IncrementCounter(counterId: laps, noteId: 'n1'));

      await expectShown(5);
    });

    test('a tap made during two refreshes stays on the page', () async {
      bloc
        ..add(const RefreshCounters())
        ..add(const RefreshCounters())
        ..add(IncrementCounter(counterId: laps, noteId: 'n1'));

      await expectShown(5);
    });

    test('a tap made while a counter is added stays on the page', () async {
      bloc
        ..add(const AddCounter(name: 'Sets'))
        ..add(IncrementCounter(counterId: laps, noteId: 'n1'));

      await expectShown(5);
    });

    test('a Reset made during a refresh stays on the page', () async {
      final done = Completer<bool>();
      bloc
        ..add(const RefreshCounters())
        ..add(ResetCounter(counterId: laps, noteId: 'n1', done: done));

      expect(await done.future, isTrue);
      await expectShown(0);
    });
  });

  group('a note context set while another handler awaits', () {
    late String laps;

    setUp(() async {
      laps = await service.addCounter(
        name: 'Laps',
        scope: CounterScope.perNote,
      );
      await service.setValueForNote(laps, 5, noteId: 'n1');
      await service.setValueForNote(laps, 9, noteId: 'n2');
      await service.flush();
      bloc.add(const LoadCounters(noteId: 'n1'));
      await pumpEventQueue();
    });

    test('is the one an added counter is shown for', () async {
      bloc
        ..add(const AddCounter(name: 'Sets'))
        ..add(const SetNoteContext(noteId: 'n2'));
      await pumpEventQueue();

      final loaded = bloc.state as CounterLoaded;
      expect(loaded.loadedNoteId, 'n2');
      expect(loaded.counterValues[laps], 9);
      expect(loaded.counters, hasLength(2));
    });

    test('is not reverted by a refresh that started before it', () async {
      bloc.add(LoadCounterForNote(counterId: laps, noteId: 'n3'));
      await pumpEventQueue();
      // A sync pull: the reload empties the note cache and sends the bloc a
      // refresh, whose reads of the table the context lands between.
      await service.reload();
      bloc.add(const SetNoteContext(noteId: 'n2'));
      await pumpEventQueue();

      final loaded = bloc.state as CounterLoaded;
      expect(loaded.loadedNoteId, 'n2');
      expect(loaded.counterValues[laps], 9);
    });
  });

  // The note editor's `{cN}` path: `toolbar.dart` hands
  // `ShortcutApplier.resolve` exactly this mutator.
  for (final scope in CounterScope.values) {
    group('a shortcut that counts one $scope counter more than once', () {
      final noteId = scope == CounterScope.perNote ? 'n1' : null;
      late String sets;

      setUp(() async {
        sets = await service.addCounter(
          name: 'Sets',
          startValue: 0,
          scope: scope,
        );
        bloc.add(LoadCounters(noteId: noteId));
        await pumpEventQueue();
      });

      Future<String?> press(
        String beforeText, {
        int bindings = 1,
        RepeatConfig? repeat,
      }) => ShortcutApplier.resolve(
        controller: CodeLineEditingController.fromText(''),
        shortcut: CustomMarkdownShortcut(
          id: 'sets',
          label: 'Sets',
          iconCodePoint: 0xe000,
          iconFontFamily: 'MaterialIcons',
          beforeText: beforeText,
          afterText: '',
          insertType: 'wrap',
          repeatConfig: repeat,
          counters: [
            for (var i = 0; i < bindings; i++) CounterBinding(counterId: sets),
          ],
        ),
        mutateCounter: (id, op) => bloc.shortcutValue(id, op, noteId: noteId),
      );

      Future<int> stored() async => noteId == null
          ? service.getGlobalValue(sets)
          : await service.getValueForNote(sets, noteId);

      int shown() => (bloc.state as CounterLoaded).counterValues[sets]!;

      test('writes each token its own count, in order', () async {
        final text = await press('Set {c1} / {c1} ');

        expect(text, 'Set 1 / 2 ');
        expect(shown(), 2, reason: 'the page is not behind the note');
        expect(await stored(), 2);
      });

      test('writes each of two bindings its own count', () async {
        final text = await press('{c1} then {c2}', bindings: 2);

        expect(text, '1 then 2');
        expect(shown(), 2);
        expect(await stored(), 2);
      });

      test('writes each repeat its own count', () async {
        final text = await press(
          'Set {c1}',
          repeat: const RepeatConfig(count: 3, separator: ' | '),
        );

        expect(text, 'Set 1 | Set 2 | Set 3');
        expect(shown(), 3);
        expect(await stored(), 3);
      });

      test('counts from the table when a reload emptied the cache', () async {
        await service.reload();
        await pumpEventQueue();

        final text = await press('Set {c1} / {c1} ');

        expect(text, 'Set 1 / 2 ');
        expect(shown(), 2);
        expect(await stored(), 2);
      });
    });
  }

  test('a refresh overtaken by a reload during its reads shows the tap made '
      'after the reload', () async {
    final hold = _HoldNoteRead();
    final heldDb = await openTestDatabase(interceptor: hold);
    addTearDown(heldDb.close);
    final counters = await CounterService.forTesting(heldDb);
    final held = CounterBloc(counterService: counters);
    addTearDown(held.close);
    final laps = await counters.addCounter(
      name: 'Laps',
      scope: CounterScope.perNote,
      startValue: 0,
    );
    await counters.setValueForNote(laps, 4, noteId: 'n1');
    await counters.setValueForNote(laps, 7, noteId: 'n2');
    await counters.flush();
    held.add(const LoadCounters(noteId: 'n1'));
    await pumpEventQueue();
    held.add(LoadCounterForNote(counterId: laps, noteId: 'n2'));
    await pumpEventQueue();

    // A pull's refresh has read n1 and waits on n2 when the next pull's
    // reload drops the cache, and a tap lands on n1 after it.
    hold.noteId = 'n2';
    await counters.reload();
    await hold.reached.future;
    await counters.reload();
    held.add(IncrementCounter(counterId: laps, noteId: 'n1'));
    await pumpEventQueue();
    hold.release.complete();
    await pumpEventQueue();

    expect((held.state as CounterLoaded).counterValues[laps], 5);
    expect(await counters.getValueForNote(laps, 'n1'), 5);
  });

  group('a shortcut in a note that has no id yet', () {
    late String laps;
    late String sets;

    setUp(() async {
      laps = await service.addCounter(
        name: 'Laps',
        scope: CounterScope.perNote,
        startValue: 1,
        step: 2,
      );
      sets = await service.addCounter(name: 'Sets', startValue: 0);
      bloc.add(const LoadCounters());
      await pumpEventQueue();
    });

    test('writes start plus a step per kept press, counts nothing, and '
        'counts the presses once filed on the note', () async {
      final unfiled = <String, int>{};
      Future<int?> token(CounterOp op) =>
          bloc.shortcutValue(laps, op, unfiled: unfiled);

      expect(await token(CounterOp.increment), 3);
      expect(await token(CounterOp.increment), 5);
      expect(await token(CounterOp.decrement), 3);
      expect(await token(CounterOp.keep), 3);
      expect(unfiled, {laps: 1});
      await pumpEventQueue();
      expect(await db.counterDao.getValuesForCounter(laps), isEmpty);

      bloc.fileShortcutPresses('n9', unfiled);
      await pumpEventQueue();

      expect(unfiled, isEmpty);
      expect(await service.getValueForNote(laps, 'n9'), 3);
      expect(
        await bloc.shortcutValue(
          laps,
          CounterOp.increment,
          noteId: 'n9',
          unfiled: unfiled,
        ),
        5,
      );
    });

    test('files presses that went below the start as decrements', () async {
      final unfiled = <String, int>{};
      await bloc.shortcutValue(laps, CounterOp.decrement, unfiled: unfiled);
      await bloc.shortcutValue(laps, CounterOp.decrement, unfiled: unfiled);

      bloc.fileShortcutPresses('n9', unfiled);
      await pumpEventQueue();

      expect(await service.getValueForNote(laps, 'n9'), -3);
    });

    test('counts a global counter at once, as before', () async {
      final unfiled = <String, int>{};

      expect(
        await bloc.shortcutValue(sets, CounterOp.increment, unfiled: unfiled),
        1,
      );
      expect(unfiled, isEmpty);
      expect(service.getGlobalValue(sets), 1);
    });
  });

  group('a note read that fails', () {
    late _FailNoteRead reads;
    late CounterService counters;
    late CounterBloc failing;
    late String laps;

    setUp(() async {
      reads = _FailNoteRead();
      final failingDb = await openTestDatabase(interceptor: reads);
      addTearDown(failingDb.close);
      counters = await CounterService.forTesting(failingDb);
      failing = CounterBloc(counterService: counters);
      addTearDown(failing.close);
      laps = await counters.addCounter(
        name: 'Laps',
        scope: CounterScope.perNote,
        startValue: 0,
      );
      await counters.setValueForNote(laps, 4, noteId: 'n1');
      await counters.setValueForNote(laps, 9, noteId: 'n2');
      await counters.flush();
      failing.add(const LoadCounters(noteId: 'n1'));
      await pumpEventQueue();
    });

    test('in the refresh a sync pull sends is carried in the state', () async {
      reads.noteId = 'n1';
      await counters.reload();
      await pumpEventQueue();

      expect((failing.state as CounterLoaded).lastError, isNotNull);
    });

    test("in a note context switch leaves no other note's values as this "
        "note's", () async {
      await counters.reload();
      await pumpEventQueue();
      reads.noteId = 'n2';
      failing.add(const SetNoteContext(noteId: 'n2'));
      await pumpEventQueue();

      final state = failing.state as CounterLoaded;
      expect(state.loadedNoteId, 'n2');
      expect(state.counterValues.containsKey(laps), isFalse);
      expect(state.lastError, isNotNull);

      // Readable again: the next refresh shows the note's own value.
      reads.noteId = null;
      failing.add(const RefreshCounters());
      await pumpEventQueue();
      expect((failing.state as CounterLoaded).counterValues[laps], 9);
    });
  });

  test('a note context set keeps an error not read yet', () async {
    final sets = await service.addCounter(name: 'Sets', startValue: 3);
    bloc.add(const LoadCounters());
    await pumpEventQueue();
    await service.deleteCounter(sets);
    bloc.add(ResetCounter(counterId: sets));
    await pumpEventQueue();
    expect((bloc.state as CounterLoaded).lastError, isNotNull);

    bloc.add(const SetNoteContext(noteId: 'n1'));
    await pumpEventQueue();

    expect((bloc.state as CounterLoaded).lastError, isNotNull);
  });

  test('a closed bloc no longer follows the service', () async {
    await bloc.close();

    // Adding to a closed bloc throws: the listener must be gone.
    await service.reload();
    await pumpEventQueue();

    expect(bloc.isClosed, isTrue);
  });
}

/// Holds the first read of [noteId]'s counter values after the table answered
/// and before the answer reaches the service, so a test can land a reload
/// inside it.
class _HoldNoteRead extends QueryInterceptor {
  String? noteId;
  final reached = Completer<void>();
  final release = Completer<void>();

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await super.runSelect(executor, statement, args);
    final holding = noteId;
    if (holding != null &&
        statement.contains('counter_values') &&
        args.contains(holding)) {
      noteId = null;
      reached.complete();
      await release.future;
    }
    return rows;
  }
}

/// Fails every read of [noteId]'s counter values while it is set, as a
/// database that went away beneath the bloc would.
class _FailNoteRead extends QueryInterceptor {
  String? noteId;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    final failing = noteId;
    if (failing != null &&
        statement.contains('counter_values') &&
        args.contains(failing)) {
      throw StateError('counter_values unreadable');
    }
    return super.runSelect(executor, statement, args);
  }
}
