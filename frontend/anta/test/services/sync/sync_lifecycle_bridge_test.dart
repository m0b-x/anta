import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';

import 'package:anta/services/sync/sync_lifecycle_bridge.dart';

import '../../support/fake_sync_engine.dart';

void main() {
  late StreamController<AppLifecycleState> lifecycle;
  late FakeSyncEngine engine;
  late SyncLifecycleBridge bridge;

  setUp(() {
    lifecycle = StreamController<AppLifecycleState>();
    engine = FakeSyncEngine()..isStarted = true;
    bridge = SyncLifecycleBridge(engine, lifecycle.stream);
  });

  tearDown(() async {
    await bridge.dispose();
    await lifecycle.close();
  });

  Future<void> send(List<AppLifecycleState> states) async {
    states.forEach(lifecycle.add);
    await pumpEventQueue();
  }

  test('one way out drains once, one way back resumes once', () async {
    await send([
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);
    expect(engine.calls, ['backgrounded']);

    await send([
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    expect(engine.calls, ['backgrounded', 'resumed']);
  });

  test('a lone inactive, as a notification shade or a system dialog makes, '
      'is neither a leave nor a return', () async {
    await send([AppLifecycleState.inactive, AppLifecycleState.resumed]);
    await send([AppLifecycleState.inactive, AppLifecycleState.resumed]);

    expect(engine.calls, isEmpty);
  });

  test('a leave after a lone inactive still drains once and resumes once', () async {
    await send([AppLifecycleState.inactive, AppLifecycleState.resumed]);
    await send([
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
    ]);
    await send([AppLifecycleState.inactive, AppLifecycleState.resumed]);

    expect(engine.calls, ['backgrounded', 'resumed']);
  });

  test('a resume without a leave, as the launch reports, does nothing', () async {
    await send([AppLifecycleState.resumed]);

    expect(engine.calls, isEmpty);
  });

  test('detached is neither', () async {
    await send([AppLifecycleState.detached]);

    expect(engine.calls, isEmpty);
  });

  test('a stopped engine hears the leave and the return, so a later start '
      'knows the foreground', () async {
    engine.isStarted = false;
    await send([AppLifecycleState.paused]);
    await send([AppLifecycleState.resumed]);
    expect(engine.calls, ['backgrounded', 'resumed']);

    await engine.stop();
    await send([AppLifecycleState.paused, AppLifecycleState.resumed]);
    expect(engine.calls, [
      'backgrounded',
      'resumed',
      'stop',
      'backgrounded',
      'resumed',
    ]);
  });

  test('a bridge built while the app is away hears the return as one', () async {
    for (final initial in [AppLifecycleState.hidden, AppLifecycleState.paused]) {
      final away = StreamController<AppLifecycleState>();
      final seeded = FakeSyncEngine()..isStarted = true;
      final built = SyncLifecycleBridge(seeded, away.stream, initial: initial);

      away
        ..add(AppLifecycleState.inactive)
        ..add(AppLifecycleState.resumed);
      await pumpEventQueue();

      expect(seeded.calls, ['resumed'], reason: '$initial');
      await built.dispose();
      await away.close();
    }
  });

  test('after dispose nothing reaches the engine', () async {
    await bridge.dispose();

    await send([AppLifecycleState.paused, AppLifecycleState.resumed]);

    expect(engine.calls, isEmpty);
  });
}
