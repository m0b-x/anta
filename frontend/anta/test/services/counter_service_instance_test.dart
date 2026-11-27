import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/database/database.dart';
import 'package:anta/services/counter_service.dart';

/// Which `CounterService` answers: the singleton is published only once it
/// is whole, never over a database a switch overtook, and the app root asks
/// for the live one rather than the one GetIt kept from launch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('getInstance', () {
    late Directory tempDir;
    late String sets;

    // One file for the group: `AppDatabase` keeps its instance per name, so
    // a case that closed it would hand the next one a closed handle.
    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('anta_counter_instance');
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => tempDir.path,
          );
    });

    tearDownAll(() async {
      try {
        await (await AppDatabase.getInstance()).close();
      } catch (_) {}
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    setUp(() async {
      final first = await CounterService.getInstance();
      sets = await first.addCounter(name: 'Sets', startValue: 3);
      await first.flush();
      // The next caller builds a fresh instance over the same file, as the
      // first caller after a switch does.
      CounterService.reset();
    });

    tearDown(CounterService.reset);

    test('a caller that arrives during the open gets the loaded instance', () {
      final opening = CounterService.getInstance();
      final second = CounterService.getInstance();

      return second.then((service) {
        expect(service.getCounterById(sets), isNotNull);
        expect(service.getGlobalValue(sets), 3);
        return opening.then((first) => expect(first, same(service)));
      });
    });

    test('an open a reset overtook publishes the instance built after it, '
        'never its own', () async {
      final opening = CounterService.getInstance();
      CounterService.reset();

      final service = await opening;

      expect(CounterService.instanceOrNull, same(service));
      expect(service.getGlobalValue(sets), 3);
      expect(await CounterService.getInstance(), same(service));
    });

    // Last in the group: it closes the database the others share, which the
    // group's tear-down closes a second time.
    test(
      'an open that failed is not kept: the next caller opens again',
      () async {
        // A closed handle makes the load throw, as a database that cannot be
        // read would.
        await (await AppDatabase.getInstance()).close();

        final failed = CounterService.getInstance();
        await expectLater(failed, throwsA(anything));
        final again = CounterService.getInstance();

        expect(again, isNot(same(failed)));
        await expectLater(again, throwsA(anything));
        expect(CounterService.instanceOrNull, isNull);
      },
    );
  });

  test('the app root flushes the live service on pause, not the one GetIt '
      'kept', () {
    final source = File('lib/main.dart').readAsStringSync();
    final lifecycle = RegExp(
      r'void didChangeAppLifecycleState\(AppLifecycleState state\) \{'
      r'[\s\S]*?^  \}',
      multiLine: true,
    ).stringMatch(source);
    expect(lifecycle, isNotNull);

    expect(lifecycle, contains('CounterService.instanceOrNull?.flush()'));
    expect(lifecycle, isNot(contains('getIt<CounterService>()')));
  });
}
