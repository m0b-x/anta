import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:anta/bloc/calendar/calendar_bloc.dart';
import 'package:anta/constants/event_skips.dart';
import 'package:anta/database/database.dart';
import 'package:anta/services/backup_service.dart';
import 'package:anta/services/calendar_event_service.dart';
import 'package:anta/services/counter_service.dart';

/// Guards the seam a pull will reload the calendar through: a change made
/// behind the bloc's back reaches a loaded calendar at once, in place — no
/// spinner, the occurrence revision bumped once, nothing stale left behind.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CalendarBloc bloc;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('anta_external_change');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDownAll(() async {
    await (await AppDatabase.getInstance()).close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    final service = await CalendarEventService.getInstance();
    await service.tombstoneAll();
    bloc = CalendarBloc(service: service);
    final loaded = bloc.stream.first.timeout(const Duration(seconds: 30));
    bloc.add(const LoadCalendarEvents());
    await loaded;
  });

  tearDown(() async {
    if (!bloc.isClosed) await bloc.close();
  });

  Future<void> insertBehindTheService(String id) async {
    final now = DateTime.now();
    await (await AppDatabase.getInstance()).calendarEventDao.upsert(
      CalendarEventsCompanion.insert(
        id: id,
        title: 'Pulled',
        category: 'gym',
        startDate: DateTime.utc(2026, 1, 1),
        ruleKind: 'daily',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  test('a loaded calendar reloads in place on an external change', () async {
    final before = bloc.state as CalendarPageLoaded;
    final states = <CalendarPageState>[];
    final sub = bloc.stream.listen(states.add);
    addTearDown(sub.cancel);
    await insertBehindTheService('pulled');

    CalendarEventService.notifyExternalChange();
    await bloc.stream.first.timeout(const Duration(seconds: 30));
    await pumpEventQueue();

    expect(states, hasLength(1));
    final after = states.single as CalendarPageLoaded;
    expect(after.allEvents.map((e) => e.id), contains('pulled'));
    expect(after.occurrenceRevision, before.occurrenceRevision + 1);
    expect(after.membershipRevision, before.membershipRevision + 1);
    expect(after.selectedDay, before.selectedDay);
    expect(bloc.isStale, isFalse);
  });

  test('two changes in a row reload once, with the later read', () async {
    final before = bloc.state as CalendarPageLoaded;
    final states = <CalendarPageState>[];
    final sub = bloc.stream.listen(states.add);
    addTearDown(sub.cancel);
    await insertBehindTheService('first');

    CalendarEventService.notifyExternalChange();
    CalendarEventService.notifyExternalChange();
    await bloc.stream.first.timeout(const Duration(seconds: 30));
    await pumpEventQueue();

    expect(states, hasLength(1));
    final after = states.single as CalendarPageLoaded;
    expect(after.allEvents.map((e) => e.id), contains('first'));
    expect(after.membershipRevision, before.membershipRevision + 1);
  });

  test('a calendar not loaded yet ignores the change', () async {
    final fresh = CalendarBloc(
      service: await CalendarEventService.getInstance(),
    );
    addTearDown(fresh.close);
    final states = <CalendarPageState>[];
    final sub = fresh.stream.listen(states.add);
    addTearDown(sub.cancel);
    final initial = fresh.state;

    CalendarEventService.notifyExternalChange();
    await pumpEventQueue();

    expect(states, isEmpty);
    expect(fresh.state, same(initial));
  });

  test('a change during the first load reaches its first state', () async {
    // The service has read the table already; the gate holds the first load
    // while the store changes behind it.
    final gate = Completer<CalendarEventService>();
    final fresh = CalendarBloc(service: gate.future);
    addTearDown(fresh.close);
    final loaded = fresh.stream.first.timeout(const Duration(seconds: 30));
    fresh.add(const LoadCalendarEvents());
    await pumpEventQueue();

    await insertBehindTheService('mid-load');
    CalendarEventService.notifyExternalChange();
    await pumpEventQueue();
    gate.complete(await CalendarEventService.getInstance());

    final first = await loaded as CalendarPageLoaded;
    expect(first.allEvents.map((e) => e.id), contains('mid-load'));
  });

  test('a closed bloc emits nothing when the store changes', () async {
    final states = <CalendarPageState>[];
    var done = false;
    bloc.stream.listen(states.add, onDone: () => done = true);
    await bloc.close();

    // `add` after close would throw into the zone and fail this test.
    CalendarEventService.notifyExternalChange();
    await pumpEventQueue();

    expect(done, isTrue);
    expect(states, isEmpty);
  });

  test('a restore reloads once, after its last calendar import', () async {
    if (!GetIt.I.isRegistered<CounterService>()) {
      GetIt.I.registerSingleton<CounterService>(
        await CounterService.getInstance(),
      );
      addTearDown(() => GetIt.I.unregister<CounterService>());
    }
    final db = await AppDatabase.getInstance();
    final day = DateTime.utc(2026, 2, 3);
    await insertBehindTheService('restored');
    final now = DateTime.now();
    await db.eventSkipDao.importAll([
      EventSkipsCompanion.insert(
        eventId: 'restored',
        day: day,
        createdAt: now,
        updatedAt: now,
        hlcTimestamp: '',
        deviceId: '',
      ),
    ]);
    final backup = await BackupService.getInstance();
    final archive = jsonEncode(await backup.exportAllData());
    final skippedAtEmit = <bool>[];
    final sub = bloc.stream.listen((state) {
      skippedAtEmit.add(EventSkips.isSkipped('restored', day));
    });
    addTearDown(sub.cancel);

    final result = await backup.importFromJson(archive);
    await bloc.stream.first.timeout(const Duration(seconds: 30));
    await pumpEventQueue();

    expect(result.success, isTrue, reason: result.error);
    // One reload, and the skips — imported after the events — were in.
    expect(skippedAtEmit, [isTrue]);
    final after = bloc.state as CalendarPageLoaded;
    expect(after.allEvents.map((e) => e.id), contains('restored'));
    expect(bloc.isStale, isFalse);
  });
}
