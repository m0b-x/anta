import 'package:flutter_test/flutter_test.dart';

import 'package:anta/bloc/counter/counter_bloc.dart';
import 'package:anta/database/database.dart';
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

  test('a reload before the first load leaves the bloc unloaded', () async {
    await service.reload();
    await pumpEventQueue();

    expect(bloc.state, const CounterInitial());
  });

  test('a closed bloc no longer follows the service', () async {
    await bloc.close();

    // Adding to a closed bloc throws: the listener must be gone.
    await service.reload();
    await pumpEventQueue();

    expect(bloc.isClosed, isTrue);
  });
}
