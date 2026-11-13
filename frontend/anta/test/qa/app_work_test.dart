import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/agent_protocol.dart';
import '../../tool/qa/src/app_work.dart';

/// What `qa work` and `qa armed` read off the platform, and how they judge
/// it — the evidence of a check that ran with no app to ask.
void main() {
  const package = 'com.alexzamfir.anta';

  group('parseAppJobs', () {
    const dumpsys = '''
Registered 87 jobs:
  JOB #u0a217/14: 2f1c0b3 com.alexzamfir.anta/androidx.work.impl.background.systemjob.SystemJobService
    u0a217 tag=*job*/com.alexzamfir.anta/androidx.work.impl.background.systemjob.SystemJobService#14
    Source: uid=u0a217 user=0 pkg=com.alexzamfir.anta
    JobInfo:
      Service: com.alexzamfir.anta/androidx.work.impl.background.systemjob.SystemJobService
      Network type: NetworkRequest [ NONE id=0, [ Capabilities: INTERNET&TRUSTED&VALIDATED Uid: 10217] ]
      Minimum latency: +2h59m59s960ms
      Backoff: policy=1 initial=+30s0ms
      Has early constraint
    Required constraints: TIMING_DELAY CONNECTIVITY [0x90000000]
    Satisfied constraints: CONNECTIVITY DEVICE_NOT_DOZING BACKGROUND_NOT_RESTRICTED [0x12400000]
    Enqueue time: -3s2ms
    Run time: earliest=+2h59m56s958ms, latest=none, original latest=none
    Ready: false (job=false user=true !restricted=true !pending=true !active=true !backingup=true comp=true)
  JOB #u0a180/3: 9a1 com.google.android.gms/.tasks.JobService
    Required constraints: IDLE [0x4]
    Run time: earliest=+1h, latest=none, original latest=none
  JOB #u0a217/9: 77aa com.alexzamfir.anta.other/androidx.work.impl.background.systemjob.SystemJobService
    Run time: earliest=+5m, latest=none, original latest=none

Active jobs:
  Slot #0: inactive
''';

    test('the app\'s own job, with its earliest run time and constraints — '
        'never another package\'s, nor one whose name only begins alike', () {
      final jobs = parseAppJobs(dumpsys, package);

      expect(jobs, hasLength(1));
      expect(jobs.single.id, 14);
      expect(jobs.single.earliest, '+2h59m56s958ms');
      expect(jobs.single.constraints, 'TIMING_DELAY CONNECTIVITY');
      expect(
        describeAppJobs(jobs),
        'work: 1 scheduled  #14 earliest=+2h59m56s958ms '
        'constraints=TIMING_DELAY CONNECTIVITY',
      );
    });

    // What `dumpsys jobscheduler com.alexzamfir.anta` printed on the fleet's
    // API 36 guest for WorkManager's job on 2026-11-13 (`qa work --raw`),
    // its constraint history shortened: the job has a namespace, printed
    // before the uid with no `#`, and again between two `@` before the
    // component.
    const api36 = '''
    <0>com.alexzamfir.anta::timeout-reg:
    <0>com.alexzamfir.anta::.schedulePersisted():
    <0>com.alexzamfir.anta::anr:
    <0>com.alexzamfir.anta::timeout-total:
  JOB androidx.work.systemjobscheduler:u0a217/7: bff8282 @androidx.work.systemjobscheduler@com.alexzamfir.anta/androidx.work.impl.background.systemjob.SystemJobService
    u0a217 tag=*job*r/@androidx.work.systemjobscheduler@com.alexzamfir.anta/androidx.work.impl.background.systemjob.SystemJobService
    Source: uid=u0a217 user=0 pkg=com.alexzamfir.anta
    JobInfo:
      Service: com.alexzamfir.anta/androidx.work.impl.background.systemjob.SystemJobService
      Priority: 300 [DEFAULT]
      Requires: charging=false batteryNotLow=false deviceIdle=false
      Extras: mParcelledData.dataSize=248
      Network type: NetworkRequest [ NONE id=0, [ Capabilities: INTERNET&TRUSTED&VALIDATED&NOT_VCN_MANAGED&NOT_BANDWIDTH_CONSTRAINED Uid: 10217 UnderlyingNetworks: Null] ]
      Minimum latency: +11h59m59s990ms
      Backoff: policy=1 initial=+30s0ms
      Has early constraint
    Required constraints: TIMING_DELAY CONNECTIVITY FLEXIBILITY [0x90200000]
    Dynamic constraints:
    Satisfied constraints: CONNECTIVITY FLEXIBILITY DEVICE_NOT_DOZING BACKGROUND_NOT_RESTRICTED WITHIN_QUOTA [0x13600000]
    Unsatisfied constraints: TIMING_DELAY [0x80000000]
    Num Required Flexible constraints: 0
    Num Dropped Flexible constraints: 0
    Constraint history:
      -10s439ms = FLEXIBILITY [0x200000]
      -10s439ms = CONNECTIVITY FLEXIBILITY [0x10200000]
    Uid: active
    Tracking: CONNECTIVITY TIME QUOTA
    Implicit constraints:
      readyNotDozing: true
      readyNotRestrictedInBg: true
      readyComponentEnabled: true
    Started with foreground flag: false
    Network: 100
    Standby bucket: ACTIVE
    Enqueue time: -10s439ms
    Run time: earliest=+11h59m49s551ms, latest=none, original latest=none
    Restricted due to: none.
    Ready: false (job=false user=true !restricted=true !pending=true !active=true !backingup=true comp=true)
    JobStatus{bff8282 androidx.work.systemjobscheduler:u0a217/7 @androidx.work.systemjobscheduler@com.alexzamfir.anta/androidx.work.impl.background.systemjob.SystemJobService u=0 s=10217 TIME=+11h59m49s550ms:none NET satisfied:0x13600000 unsatisfied:0x80000000
    10217:com.alexzamfir.anta=false
    #androidx.work.systemjobscheduler:u0a217/7 from u0a217 active: com.alexzamfir.anta [RUN_ANY_IN_BACKGROUND allowed] RUNNABLE
    #androidx.work.systemjobscheduler:u0a217/7 from u0a217: com.alexzamfir.anta RUNNABLE
    TopAppTimer{<0>com.alexzamfir.anta} started at 30904 (278315ms ago)
      com.alexzamfir.anta.MainActivity
      <0>com.alexzamfir.anta
  0-ComponentInfo{com.alexzamfir.anta/androidx.work.impl.background.systemjob.SystemJobService}: com.alexzamfir.anta
  10217: {com.alexzamfir.anta}
''';

    test('API 36\'s own text: the namespaced job is the app\'s, once, with '
        'the namespace a run needs — the shape that read as "work: none" '
        'in the first device passes', () {
      final job = parseAppJobs(api36, package).single;

      expect(job.id, 7);
      expect(job.namespace, 'androidx.work.systemjobscheduler');
      expect(job.earliest, '+11h59m49s551ms');
      expect(job.constraints, 'TIMING_DELAY CONNECTIVITY FLEXIBILITY');
      expect(
        describeAppJobs([job]),
        'work: 1 scheduled  #7 earliest=+11h59m49s551ms '
        'constraints=TIMING_DELAY CONNECTIVITY FLEXIBILITY',
      );
      expect(parseAppJobs(dumpsys, package).single.namespace, isNull);
    });

    test('--raw keeps the job\'s block whole and every other line that '
        'names the package, and nothing of another\'s', () {
      final raw = rawAppJobLines('$api36$dumpsys', package);

      expect(raw.first, contains('timeout-reg'));
      expect(
        raw.where((line) => line.trimLeft().startsWith('JOB ')),
        hasLength(3),
        reason: 'the namespaced job, the plain one, and the look-alike '
            'package\'s header, which names the package as a prefix',
      );
      expect(raw, contains('    Unsatisfied constraints: TIMING_DELAY [0x80000000]'));
      expect(raw.any((line) => line.contains('com.google.android.gms')), isFalse);
    });

    test('no job of the app is "none"', () {
      expect(parseAppJobs('Registered 0 jobs:\n', package), isEmpty);
      expect(describeAppJobs(const []), 'work: none');
    });

    test('a job listed again while it runs is one job', () {
      final twice =
          '$dumpsys\n${dumpsys.split('\n').skip(1).take(14).join('\n')}';

      expect(parseAppJobs(twice, package), hasLength(1));
    });
  });

  group('parseArmedAlarms', () {
    const dumpsys = '''
  5 pending alarms:
    RTC_WAKEUP #4: Alarm{edf8eb6 type 0 origWhen 1763315400000 whenElapsed 107671144 com.alexzamfir.anta}
      tag=*walarm*:com.alexzamfir.anta/com.gdelataillade.alarm.alarm.AlarmReceiver
      type=RTC_WAKEUP origWhen=2026-11-16 17:30:00.000 window=0 flags=0x3
      Alarm clock:
        triggerTime=2026-11-16 17:30:00.000
    RTC_WAKEUP #3: Alarm{6bfb68d type 0 origWhen 1763316600000 whenElapsed 110671144 com.alexzamfir.anta}
      tag=*walarm*:com.alexzamfir.anta/com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver
      type=RTC_WAKEUP origWhen=2026-11-16 17:50:00.000 window=0 flags=0x9
    RTC_WAKEUP #2: Alarm{aa11 type 0 origWhen 1763575800000 whenElapsed 1 com.alexzamfir.anta}
      tag=*walarm*:com.alexzamfir.anta/com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver
    ELAPSED_WAKEUP #1: Alarm{a4384a2 type 2 origWhen 8487259 whenElapsed 8487259 com.google.android.gms}
      tag=*walarm*:com.google.android.gms/.checkin.EventLogService
    RTC #0: Alarm{1a2b3c4 type 1 origWhen 1 whenElapsed 1 com.alexzamfir.anta.other}
  Removal history:
    u0a217:
      #1: Reason=alarm_cancelled elapsed=-38m27s665ms rtc=2026-10-23 19:08:52.916
          type=RTC_WAKEUP tag=*walarm*:com.alexzamfir.anta/com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver
''';

    test('the pending rows of the app, soonest first, each told by tier', () {
      final alarms = parseArmedAlarms(dumpsys, package);

      expect(armedInstants(alarms, ArmedTier.alarm), [1763315400000]);
      expect(armedInstants(alarms, ArmedTier.reminder), [
        1763316600000,
        1763575800000,
      ]);
      expect(armedInstants(alarms, null), hasLength(3));
      expect(
        describeArmed(alarms),
        'armed: reminder=2025-11-16T18:10 2025-11-19T18:10  '
        'alarm=2025-11-16T17:50',
      );
    });

    test('nothing of the app pending is none of either tier', () {
      expect(parseArmedAlarms('  0 pending alarms:\n', package), isEmpty);
      expect(describeArmed(const []), 'armed: reminder=none  alarm=none');
    });
  });

  group('armedExpectationFailure', () {
    const hour = 3600000;
    final captures = {
      'before': encodeInstants([1000 * hour, 1100 * hour]),
      'empty': '',
    };

    String? judge(String expectation, List<int> now) =>
        armedExpectationFailure(expectation, now, captures);

    test('none and some speak of what is armed now', () {
      expect(judge('none', const []), isNull);
      expect(judge('none', [1]), isNotNull);
      expect(judge('some', [1]), isNull);
      expect(judge('some', const []), isNotNull);
    });

    test('shifted: every instant moved by exactly the seconds named', () {
      expect(judge('shifted:before:3600', [1001 * hour, 1101 * hour]), isNull);
      expect(
        judge('shifted:before:3600', [1000 * hour, 1100 * hour]),
        contains('moved by 0 s'),
      );
      expect(
        judge('shifted:before:3600', [1001 * hour, 1100 * hour]),
        contains('instant 2'),
      );
    });

    test('the horizon may hold one more or one fewer at its far end', () {
      expect(judge('shifted:before:3600', [1001 * hour]), isNull);
      expect(
        judge('shifted:before:3600', [1001 * hour, 1101 * hour, 1201 * hour]),
        isNull,
      );
    });

    test('same: nothing moved', () {
      expect(judge('same:before', [1000 * hour, 1100 * hour]), isNull);
      expect(judge('same:before', [1001 * hour, 1101 * hour]), isNotNull);
    });

    test('never satisfied over nothing: a capture or a read that holds no '
        'instant, a name nobody captured, a malformed ask', () {
      expect(judge('shifted:before:3600', const []), 'nothing armed now');
      expect(judge('same:empty', [1]), contains('captured nothing'));
      expect(judge('same:other', [1]), contains('nothing was captured'));
      expect(judge('shifted:before', [1]), contains('shifted:<name>'));
      expect(judge('shifted:before:soon', [1]), contains('not a number'));
      expect(judge('later', [1]), contains('unknown --expect'));
    });
  });

  group('lastSharedRefreshEnding', () {
    test('the last ending the check logged, whatever started it', () {
      const log = '''
11-13 10:01:02.000 I/flutter ( 4242): [SharedRefresh] trigger(check) ended: forwarded
11-13 10:03:09.120 I/flutter ( 5151): [AlertScheduler] reconcile(launch) backend=android planned=2
11-13 10:03:11.480 I/flutter ( 5151): [SharedRefresh] trigger(check) ended: read
''';

      expect(lastSharedRefreshEnding(log), 'read');
      expect(lastSharedRefreshEnding('nothing of it'), isNull);
    });
  });

  test('the move-event op and its key are part of the protocol', () {
    expect(AgentOps.moveEvent, 'move-event');
    expect(AgentKeys.minutes, 'minutes');
  });
}
