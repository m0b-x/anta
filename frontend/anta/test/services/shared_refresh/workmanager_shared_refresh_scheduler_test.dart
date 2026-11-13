import 'package:flutter_test/flutter_test.dart';
import 'package:workmanager/workmanager.dart';

import 'package:anta/constants/shared_refresh_constants.dart';
import 'package:anta/services/shared_refresh/shared_refresh_entry.dart';
import 'package:anta/services/shared_refresh/shared_refresh_scheduler.dart';
import 'package:anta/services/shared_refresh/shared_refresh_trigger.dart';
import 'package:anta/services/shared_refresh/workmanager_shared_refresh_scheduler.dart';

/// The plugin's platform side, recording what reaches it.
class _RecordingPlatform extends WorkmanagerPlatform {
  final List<String> calls = [];
  Function? dispatcher;
  bool failInitialize = false;

  String? uniqueName;
  String? taskName;
  Duration? initialDelay;
  Constraints? constraints;
  ExistingWorkPolicy? policy;
  Map<String, dynamic>? inputData;
  bool expedited = false;

  @override
  Future<void> initialize(
    Function callbackDispatcher, {
    bool isInDebugMode = false,
  }) async {
    calls.add('initialize');
    if (failInitialize) throw StateError('no platform');
    dispatcher = callbackDispatcher;
  }

  @override
  Future<void> registerOneOffTask(
    String uniqueName,
    String taskName, {
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    OutOfQuotaPolicy? outOfQuotaPolicy,
    ForegroundServiceConfig? foregroundServiceConfig,
    bool expedited = false,
  }) async {
    calls.add('oneOff');
    this.inputData = inputData;
    this.uniqueName = uniqueName;
    this.taskName = taskName;
    this.initialDelay = initialDelay;
    this.constraints = constraints;
    policy = existingWorkPolicy;
    this.expedited = expedited;
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) async {
    calls.add('cancel:$uniqueName');
  }
}

/// `WorkmanagerSharedRefreshScheduler` — the check as WorkManager is asked
/// for it (`docs/cloud-shared-freshness.md` §4).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingPlatform platform;

  setUp(() {
    // Built first: its first construction binds the host's own platform
    // side, and the recording one must be what stands after it.
    Workmanager();
    platform = _RecordingPlatform();
    WorkmanagerPlatform.instance = platform;
  });

  test(
    'the check is one unique one-off work named shared-refresh, replacing '
    'the one that stands, run only with a network, after the delay',
    () async {
      await WorkmanagerSharedRefreshScheduler().schedule(
        const Duration(hours: 3),
      );

      expect(kSharedRefreshWorkName, 'shared-refresh');
      expect(platform.uniqueName, 'shared-refresh');
      expect(platform.taskName, 'shared-refresh');
      expect(platform.initialDelay, const Duration(hours: 3));
      expect(platform.policy, ExistingWorkPolicy.replace);
      expect(platform.constraints?.networkType, NetworkType.connected);
      expect(platform.expedited, isFalse);
    },
  );

  test('the work carries its cause — the schedule\'s own check — under the '
      'key the entry reads it by', () async {
    await WorkmanagerSharedRefreshScheduler().schedule(
      const Duration(hours: 3),
    );

    expect(platform.inputData, {'cause': 'check'});
    expect(
      SharedRefreshCause.fromInput(platform.inputData),
      SharedRefreshCause.check,
    );
  });

  group('two slots — replacing a unique work cancels it, a running one '
      'included, so a work never writes the slot it runs in', () {
    test('the slots are two unique names, and a task\'s own name says which '
        'it runs in; a name this build does not know is the first', () {
      expect(SharedRefreshSlot.first.workName, 'shared-refresh');
      expect(SharedRefreshSlot.second.workName, 'shared-refresh-2');
      expect(SharedRefreshSlot.first.other, SharedRefreshSlot.second);
      expect(SharedRefreshSlot.second.other, SharedRefreshSlot.first);

      expect(
        SharedRefreshSlot.ofTask('shared-refresh'),
        SharedRefreshSlot.first,
      );
      expect(
        SharedRefreshSlot.ofTask('shared-refresh-2'),
        SharedRefreshSlot.second,
      );
      expect(SharedRefreshSlot.ofTask(null), SharedRefreshSlot.first);
      expect(SharedRefreshSlot.ofTask('other'), SharedRefreshSlot.first);
    });

    for (final running in SharedRefreshSlot.values) {
      test('the work running in ${running.workName} schedules its successor '
          'into ${running.other.workName}, and cancels nothing: its own '
          'name is never asked for', () async {
        await WorkmanagerSharedRefreshScheduler().schedule(
          const Duration(hours: 3),
          runningIn: running,
        );

        expect(platform.uniqueName, running.other.workName);
        expect(platform.taskName, running.other.workName);
        expect(platform.policy, ExistingWorkPolicy.replace);
        expect(platform.initialDelay, const Duration(hours: 3));
        expect(platform.constraints?.networkType, NetworkType.connected);
        expect(platform.inputData, {'cause': 'check'});
        expect(platform.calls, ['initialize', 'oneOff']);
      });

      test('with the work in ${running.workName} running, cancel takes only '
          '${running.other.workName} off', () async {
        await WorkmanagerSharedRefreshScheduler().cancel(runningIn: running);

        expect(platform.calls, ['cancel:${running.other.workName}']);
      });
    }

    test('the app, running in no work, writes the first slot and takes the '
        'second off: one check stands, never two', () async {
      await WorkmanagerSharedRefreshScheduler().schedule(
        const Duration(hours: 3),
      );

      expect(platform.uniqueName, 'shared-refresh');
      expect(platform.calls, [
        'initialize',
        'oneOff',
        'cancel:shared-refresh-2',
      ]);
    });
  });

  test('the plugin is told its Dart entry before the first schedule, once '
      'per process', () async {
    final scheduler = WorkmanagerSharedRefreshScheduler();

    await scheduler.schedule(const Duration(hours: 3));
    await scheduler.schedule(const Duration(hours: 1));

    expect(platform.calls.where((call) => call == 'initialize'), hasLength(1));
    expect(platform.calls.first, 'initialize');
    expect(platform.calls.where((call) => call == 'oneOff'), hasLength(2));
    expect(platform.dispatcher, sharedRefreshEntry);
  });

  test('building it asks the platform nothing', () {
    WorkmanagerSharedRefreshScheduler();

    expect(platform.calls, isEmpty);
  });

  test('cancel takes the work off both slots and needs no entry', () async {
    await WorkmanagerSharedRefreshScheduler().cancel();

    expect(platform.calls, ['cancel:shared-refresh', 'cancel:shared-refresh-2']);
  });

  test('an entry the platform refused is offered again by the next '
      'schedule', () async {
    final scheduler = WorkmanagerSharedRefreshScheduler();
    platform.failInitialize = true;

    await expectLater(
      scheduler.schedule(const Duration(hours: 3)),
      throwsStateError,
    );
    platform.failInitialize = false;
    await scheduler.schedule(const Duration(hours: 3));

    expect(platform.calls, [
      'initialize',
      'initialize',
      'oneOff',
      'cancel:shared-refresh-2',
    ]);
  });
}
