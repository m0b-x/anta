import 'dart:async';

import 'package:anta/services/sync/sync_engine.dart';
import 'package:anta/services/sync/sync_status.dart';

/// A [SyncEngine] stand-in for the code that drives one — `SyncBloc`, the
/// lifecycle bridge: a status controller the test pushes into, and a record
/// of every call made on it.
class FakeSyncEngine implements SyncEngine {
  final StreamController<SyncStatus> statuses =
      StreamController<SyncStatus>.broadcast();

  /// Every call by name, in order: `start`, `stop`, `dispose`, `syncNow`,
  /// `resumed`, `backgrounded`.
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
  void onAppResumed() => calls.add('resumed');

  @override
  Future<SyncRunReport> onAppBackgrounded() async {
    calls.add('backgrounded');
    return const SyncRunReport();
  }
}
