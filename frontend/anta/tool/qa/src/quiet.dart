import 'dart:math' as math;

import 'adb.dart';
import 'app_ids.dart';
import 'errors.dart';
import 'fleet.dart';
import 'guest_state.dart';
import 'paths.dart';

/// How long quieting one guest may take — the relaunch and the count after
/// it — before whatever it precedes goes ahead without it.
const Duration quietLimit = Duration(seconds: 20);

/// How long `fleet boot` gives the alarm plugin's boot receiver to re-arm
/// what it stored before the count after a boot stands.
const Duration bootReceiverWait = Duration(seconds: 8);

/// The child `qa` that quiets a guest: a seedless fresh relaunch. The app
/// starts on an empty QA database (a pending seed removed first), and its
/// launch reconcile cancels every alarm the last seed armed — which the
/// plugin would otherwise re-arm at every later launch and at boot. It
/// waits for the app's own `[qa] quiet:` line ([awaitQuietFlag]).
List<String> quietRelaunchArgs(String serial) => [
  ...qaChildGlobals(serial: serial),
  'relaunch',
  '--fresh',
  awaitQuietFlag,
];

/// The hidden `relaunch` flag that makes it wait for the app's `[qa]
/// quiet:` line as it waits for the reset's, and fail without it.
const String awaitQuietFlag = '--await-quiet';

/// What the app said its reset launch ended (`quietQaAlerts`): [rings]
/// stopped and [cancelled] alarms taken off the plugin's stores.
typedef AppQuiet = ({int rings, int cancelled});

final RegExp _appQuietLine = RegExp(
  r'\[qa\] quiet: stopped (\d+) ring\(s\), cancelled (\d+) alarm\(s\)',
);

/// The app's `[qa] quiet:` report among [lines], or null when it is not
/// there — which is the only evidence that the stores were emptied: the
/// relaunch's force-stop alone empties the alarm manager's list and ends a
/// ring, so a count after it reads quiet while every alarm is still stored
/// for the boot receiver to re-arm.
AppQuiet? parseAppQuiet(Iterable<String> lines) {
  for (final line in lines) {
    final match = _appQuietLine.firstMatch(line);
    if (match == null) continue;
    return (
      rings: int.parse(match.group(1)!),
      cancelled: int.parse(match.group(2)!),
    );
  }
  return null;
}

/// The app's own failure of its quiet (`[qa] quiet threw …`), or null.
String? appQuietFailure(Iterable<String> lines) {
  for (final line in lines) {
    final at = line.indexOf('[qa] quiet threw');
    if (at >= 0) return line.substring(at + '[qa] '.length).trim();
  }
  return null;
}

/// What quieting one fleet guest came to.
class GuestQuiet {
  const GuestQuiet({
    this.before,
    this.after,
    this.ringing = false,
    this.relaunched = false,
    this.app,
    this.skipped,
    this.failure,
  });

  /// The app's alarms armed before the relaunch; null when not counted.
  final int? before;

  /// What the app said its quiet ended; null when it said nothing.
  final AppQuiet? app;

  /// Armed after the relaunch; null when it did not run.
  final int? after;

  /// Whether an alarm was ringing before the relaunch — one the armed count
  /// cannot see, since a ring has left the alarm manager's list.
  final bool ringing;
  final bool relaunched;

  /// Why nothing was tried: the QA app is not on the guest.
  final String? skipped;

  /// Why the guest may still hold alarms; null when it is quiet.
  final String? failure;

  bool get ok => failure == null;

  /// Whether the guest held anything the quiet ended: an alarm armed or a
  /// ring by the harness's count, or one the app said it took off its
  /// stores — which a stop's quiet finds on a guest whose app was
  /// force-stopped, with the count at 0.
  bool get endedAnything =>
      (before ?? 0) > 0 ||
      ringing ||
      (app?.cancelled ?? 0) > 0 ||
      (app?.rings ?? 0) > 0;

  /// The line a verb prints, [when] being `before the stop`, `after the
  /// boot` or `after its pass died`. A failure's line is a warning.
  String line(String name, String when) {
    if (failure != null) {
      return 'warning: quiet: $name was not quieted $when — $failure';
    }
    if (skipped != null) return 'quiet: $name left as it is $when — $skipped';
    if (!relaunched || !endedAnything) {
      return 'quiet: no app alarm armed on $name $when';
    }
    final ring = ringing || (app?.rings ?? 0) > 0
        ? ' and a ring in progress'
        : '';
    // The app's count includes what was stored and not armed; the harness's
    // what was armed — the larger is the honest one.
    final count = math.max(app?.cancelled ?? 0, before ?? 0);
    return 'quiet: $count alarm(s)$ring on $name cancelled $when';
  }
}

/// The service the `alarm` plugin sounds a ring in. It runs only while an
/// alarm rings, so it is the one read-only sign of a ring in progress: a
/// ring has already left `dumpsys alarm`'s pending list.
const String alarmServiceClass = 'com.gdelataillade.alarm.alarm.AlarmService';

/// Whether `dumpsys activity services` lists the plugin's ring service of
/// [package] as running.
bool ringServiceRunning(String dumpsys, String package) => dumpsys
    .split('\n')
    .any(
      (line) =>
          line.contains('ServiceRecord{') &&
          line.contains('$package/$alarmServiceClass'),
    );

/// Whether one of the app's alarms is ringing on [adb]'s device (`dumpsys
/// activity services`, read-only); throws when adb could not answer, so a
/// guest that could not be asked never reads as silent.
Future<bool> ringInProgressOn(Adb adb) async {
  final dump = await adb.shell([
    'dumpsys',
    'activity',
    'services',
    antaPackage,
  ]);
  // An answer without the dump's own header is no answer: read as silent,
  // it would let a ringing guest pass for a quiet one.
  if (!dump.contains(servicesDumpHeader)) {
    throw DeviceFailure(
      'dumpsys activity services did not answer: ${dump.trim()}',
    );
  }
  return ringServiceRunning(dump, antaPackage);
}

/// The first line `dumpsys activity services` prints, whatever it lists.
const String servicesDumpHeader = 'ACTIVITY MANAGER SERVICES';

/// What a guest holds of the app's alarms: [armed] in the alarm manager and
/// whether one is [ringing]. Quiet means neither.
typedef GuestAlarms = ({int armed, bool ringing});

/// [armedAlarmsOn] and [ringInProgressOn] together.
Future<GuestAlarms> guestAlarmsOn(Adb adb) async =>
    (armed: await armedAlarmsOn(adb), ringing: await ringInProgressOn(adb));

/// How a guest's [GuestAlarms] reads in a listing: `7`, `7, ringing`.
String guestAlarmsLabel(GuestAlarms alarms) =>
    alarms.ringing ? '${alarms.armed}, ringing' : '${alarms.armed}';

/// [quiet] for fleet guest [index] while adb lists it and its console names
/// that AVD; null, with nothing done, for a guest off adb (a hung one
/// cannot be quieted — the boot after it is) or a port another emulator
/// answers on, whose app is never someone's to relaunch.
Future<GuestQuiet?> quietFleetGuestIfUp(
  FleetHost host,
  int index,
  Future<GuestQuiet> Function(String serial) quiet,
) async {
  final serial = fleetSerial(index);
  try {
    final devices = await host.adb.devices();
    if (!devices.any((d) => d.serial == serial && d.usable)) return null;
    if (await host.avdNameOn(serial) != fleetName(index)) return null;
  } on QaException {
    return null;
  }
  return quiet(serial);
}

/// Whether a stop's quiet has something to say: alarms were cancelled, or
/// the attempt failed. A guest that held none stops with its usual lines.
bool quietWorthSaying(GuestQuiet? quiet) =>
    quiet != null && (!quiet.ok || (quiet.relaunched && quiet.endedAnything));

/// The app's alarms armed on [adb]'s device (`dumpsys alarm`, read-only).
Future<int> armedAlarmsOn(Adb adb) async =>
    countArmedAlarms(await adb.shell(['dumpsys', 'alarm']), antaPackage);

/// Whether the app is installed on [adb]'s device; throws when adb could
/// not answer, so an unreachable guest never reads as one without the app.
Future<bool> appInstalledOn(Adb adb) async {
  final result = await adb.raw(['shell', 'pm', 'path', antaPackage]);
  if (result.combined.contains('package:')) return true;
  if (result.combined.contains('error')) {
    throw DeviceFailure('adb could not ask for the app: ${result.combined}');
  }
  return false;
}

/// The app's alarms on a guest that just booted, once its alarm plugin's
/// boot receiver had [wait] to re-arm what it stored — read every two
/// seconds and returned as soon as any is armed or ringing (the receiver
/// rings a stored alarm that is already due at once); null when the app is
/// not installed. Throws when adb cannot answer.
Future<GuestAlarms?> alarmsAfterBoot(
  Adb adb, {
  Duration wait = bootReceiverWait,
  Future<void> Function(Duration)? sleep,
  DateTime Function()? clock,
}) async {
  final now = clock ?? DateTime.now;
  final pause = sleep ?? (d) => Future<void>.delayed(d);
  if (!await appInstalledOn(adb)) return null;
  final deadline = now().add(wait);
  var alarms = await guestAlarmsOn(adb);
  while (alarms.armed == 0 && !alarms.ringing && now().isBefore(deadline)) {
    await pause(const Duration(seconds: 2));
    alarms = await guestAlarmsOn(adb);
  }
  return alarms;
}

/// What `fleet boot` does once fleet guest [index] is up after a boot it
/// started: when no one holds the guest, [alarmsAfterBoot] reads, and any
/// alarm the boot receiver re-armed or rang is ended through [quiet]. [say]
/// gets one line; a failure's starts `warning: `.
Future<void> quietAfterBoot({
  required FleetHost host,
  required QaPaths paths,
  required int index,
  required Future<GuestQuiet> Function(String serial) quiet,
  required void Function(String line) say,
  Duration wait = bootReceiverWait,
  Future<void> Function(Duration)? sleep,
  DateTime Function()? clock,
}) async {
  final name = fleetName(index);
  final serial = fleetSerial(index);
  // A holder reseeds the guest itself; one that could not be checked
  // still holds it.
  if (await host.holdOf(GuestState.read(paths.guestStateFor(name))) != null) {
    return;
  }
  try {
    final alarms = await alarmsAfterBoot(
      host.adb.withSerial(serial),
      wait: wait,
      sleep: sleep,
      clock: clock,
    );
    if (alarms == null) return;
    if (alarms.armed == 0 && !alarms.ringing) {
      say('quiet: no app alarm armed on $name after the boot');
      return;
    }
  } on QaException catch (e) {
    say(
      'warning: quiet: the alarms on $name could not be counted after the '
      'boot — ${e.message}',
    );
    return;
  }
  say((await quiet(serial)).line(name, 'after the boot'));
}

/// Leaves the guest [adb] is bound to with none of the app's alarms armed,
/// stored or ringing: reads the first and the last, and when there is
/// either — or with [always], which every quiet before a stop passes, since
/// a force-stopped app shows nothing armed with every alarm still stored —
/// runs [relaunch] with [quietRelaunchArgs] under [limit] (a QA reset
/// launch stops a ring in progress), handing it the line sink its output
/// goes to. A relaunch whose output lacks the app's `[qa] quiet:` line is
/// a failed quiet, never a quiet guest. Then it reads again until both are
/// gone or [limit] has passed. Never throws: what went wrong is the
/// result's [GuestQuiet.failure], and the caller goes on.
Future<GuestQuiet> quietGuest({
  required Adb adb,
  required Future<ChildOutcome> Function(
    List<String> arguments,
    Duration limit,
    void Function(String line) onLine,
  )
  relaunch,
  bool always = false,
  Duration limit = quietLimit,
  Future<void> Function(Duration)? sleep,
  DateTime Function()? clock,
}) async {
  final now = clock ?? DateTime.now;
  final wait = sleep ?? (d) => Future<void>.delayed(d);
  int? before;
  var ringing = false;
  try {
    if (!await appInstalledOn(adb)) {
      return const GuestQuiet(skipped: 'the QA app is not installed');
    }
    final found = await guestAlarmsOn(adb);
    before = found.armed;
    ringing = found.ringing;
    if (before == 0 && !ringing && !always) return const GuestQuiet(before: 0);
    final started = now();
    final printed = <String>[];
    final outcome = await relaunch(
      quietRelaunchArgs(adb.serial!),
      limit,
      printed.add,
    );
    final app = parseAppQuiet(printed);
    if (outcome.exitCode != 0) {
      return GuestQuiet(
        before: before,
        ringing: ringing,
        app: app,
        failure: outcome.timedOut
            ? 'the relaunch ran past ${limit.inSeconds} s'
                  '${app == null ? ' before the app said it was quiet' : ''}'
            : 'the relaunch exited ${outcome.exitCode}',
      );
    }
    final threw = appQuietFailure(printed);
    if (app == null) {
      return GuestQuiet(
        before: before,
        ringing: ringing,
        relaunched: true,
        failure:
            threw ??
            'the app never said it had quieted itself (no `[qa] quiet:` '
                'line from the relaunch) — its stored alarms may outlive the '
                'stop',
      );
    }
    // The launch reconcile cancels a moment after the first frame.
    var after = await guestAlarmsOn(adb);
    while ((after.armed > 0 || after.ringing) &&
        now().difference(started) < limit) {
      await wait(const Duration(seconds: 1));
      after = await guestAlarmsOn(adb);
    }
    return GuestQuiet(
      before: before,
      after: after.armed,
      ringing: ringing,
      relaunched: true,
      app: app,
      failure: after.ringing
          ? 'an alarm still ringing after it'
          : after.armed > 0
          ? '${after.armed} alarm(s) still armed after it'
          : null,
    );
  } on QaException catch (e) {
    return GuestQuiet(before: before, ringing: ringing, failure: e.message);
  }
}
