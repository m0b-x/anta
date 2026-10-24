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

  test('a brief inactive, as a system dialog makes, is a leave and a '
      'return', () async {
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

  test('before the engine starts, and after it stops, nothing reaches it', () async {
    engine.isStarted = false;
    await send([AppLifecycleState.paused]);
    engine.isStarted = true;
    // The leave seen before the start is owed no resume.
    await send([AppLifecycleState.resumed]);
    expect(engine.calls, isEmpty);

    await engine.stop();
    await send([AppLifecycleState.paused, AppLifecycleState.resumed]);
    expect(engine.calls, ['stop']);
  });

  test('after dispose nothing reaches the engine', () async {
    await bridge.dispose();

    await send([AppLifecycleState.paused, AppLifecycleState.resumed]);

    expect(engine.calls, isEmpty);
  });
}
