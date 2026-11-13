import 'dart:async';

import 'package:anta/services/sync/sync_cadence.dart';
import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/services/sync/sync_status.dart';

/// A [SyncEngine] stand-in for the code that drives one — `SyncBloc`, the
/// lifecycle bridge: a status controller the test pushes into, and a record
/// of every call made on it.
class FakeSyncEngine implements SyncEngine {
  final StreamController<SyncStatus> statuses =
      StreamController<SyncStatus>.broadcast();

  /// Every call by name, in order: `start`, `stop`, `dispose`, `syncNow`,
  /// `pushNow`, `readSharedNow`, `resumed`, `backgrounded`.
  final List<String> calls = [];

  SyncRunReport report = const SyncRunReport();

  @override
  SyncStatus current = SyncStatus.empty;

  /// Pushes [status] as the engine would after a change.
  void emit(SyncStatus status) {
    current = status;
    statuses.add(status);
  }

  @override
  Stream<SyncStatus> get status => statuses.stream;

  @override
  Future<void> get whenIdle async {}

  @override
  int get schemaForTesting => 0;

  @override
  bool isStarted = false;

  @override
  Future<void> start() async {
    calls.add('start');
    isStarted = true;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    isStarted = false;
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await statuses.close();
  }

  @override
  Future<SyncRunReport> syncNow() async {
    calls.add('syncNow');
    return report;
  }

  @override
  Future<SyncRunReport> pushNow() async {
    calls.add('pushNow');
    return report;
  }

  @override
  Future<SyncRunReport> readSharedNow() async {
    calls.add('readSharedNow');
    return report;
  }

  @override
  Future<SyncRunReport> readSharedWhileAway() async {
    calls.add('readSharedWhileAway');
    return report;
  }

  @override
  SyncCadence cadence = SyncCadence.automatic;

  /// When set, [setCadence] throws it instead of storing — a closed
  /// database.
  Object? setCadenceError;

  /// Recorded as `cadence:<name>`; the status is not re-emitted, so a test
  /// sees the bloc's own flip apart from the engine's confirmation.
  @override
  Future<void> setCadence(SyncCadence next) async {
    calls.add('cadence:${next.name}');
    if (setCadenceError case final error?) throw error;
    cadence = next;
  }

  @override
  void onAppResumed() => calls.add('resumed');

  @override
  Future<SyncRunReport> onAppBackgrounded() async {
    calls.add('backgrounded');
    return const SyncRunReport();
  }
}
