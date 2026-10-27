import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/counter/counter_bloc.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/counter_service.dart';
import 'package:anta/services/database_manager.dart';

/// The counter twin of `test/pages/vocabularies_page_test.dart`'s database
/// switch case: `CounterService.changes` is shared by every instance, so a
/// bloc built before a switch hears that another instance answers now and
/// re-resolves it — rather than staying subscribed to the dead controller of
/// a closed database (A1b review R22).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_counter_switch');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDown(() async {
    // The singleton emits on the stream every instance shares, so one left
    // standing would reach the next test's bloc (A6 review R124).
    CounterService.reset();
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('after a database switch the bloc shows the new database and follows '
      'its service', () async {
    final first = await CounterService.getInstance();
    final sets = await first.addCounter(name: 'Sets', startValue: 3);
    final bloc = CounterBloc(counterService: first);
    addTearDown(bloc.close);

    bloc.add(const LoadCounters());
    await pumpEventQueue();
    expect((bloc.state as CounterLoaded).counterValues, {sets: 3});

    // The switch the database settings page performs: the active name moves,
    // the next open closes the old database and drops every singleton on the
    // lifecycle contract.
    final manager = await DatabaseManager.getInstance();
    await manager.setActiveDatabaseName('switched');
    await AppDatabase.getInstance();
    final second = await CounterService.getInstance();
    expect(second, isNot(same(first)));

    await pumpEventQueue();
    expect(
      (bloc.state as CounterLoaded).counters,
      isEmpty,
      reason: 'the switched-to database carries no counters',
    );

    // And it reads the new service from then on, not the one it was built
    // with: a pull merged a counter under the new database's cache.
    final laps = await second.addCounter(name: 'Laps', startValue: 7);
    await second.reload();
    await pumpEventQueue();
    expect((bloc.state as CounterLoaded).counterValues, {laps: 7});
  });
}
