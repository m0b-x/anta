import 'dart:async';
import 'dart:io';

/// What a verb a Ctrl+C ended exits with: 128 + SIGINT, as a shell reports
/// an interrupted command.
const int exitInterrupted = 130;

/// How long an interrupted pass gives its quiet end: the seeds' alarms
/// are worth fifteen seconds, a person waiting on Ctrl+C is not worth more.
const Duration interruptQuietLimit = Duration(seconds: 15);

/// How long an interrupted `fleet pass` waits for its shards, each of
/// which got the same Ctrl+C and is ending as [PassInterrupt] says.
const Duration interruptShardWait = Duration(seconds: 20);

/// The Ctrl+C events a verb ends early on; empty where the platform cannot
/// watch for them, so the verb then dies the default way.
Stream<ProcessSignal> interruptSignals() {
  try {
    return ProcessSignal.sigint.watch();
  } on SignalException {
    return const Stream.empty();
  } on UnsupportedError {
    return const Stream.empty();
  }
}

/// How long an interrupted pass waits for its cancelled flow loop to
/// return before it writes the report: the step in flight throws at its
/// next device call, so this is milliseconds unless something is stuck.
const Duration interruptWorkLimit = Duration(seconds: 5);

/// What `pass` does on Ctrl+C, in order: wait up to [workLimit] for the
/// cancelled flow loop ([stopWork]), so the quiet end never drives the
/// device beside a step still in flight and the report holds what was
/// finished; write the report as it stands
/// (partial), leave the device quiet within [quietLimit] — the quiet end
/// cancels the alarms a seed armed, which would otherwise ring on a guest
/// nobody is looking at — unless the pass would have skipped it anyway,
/// then release the guest's hold. A kill that cannot be caught leaves all
/// of this to the idle guard and `reap`.
class PassInterrupt {
  PassInterrupt({
    required this.writePartial,
    required this.leaveQuiet,
    required this.quietSkipped,
    required this.release,
    required this.say,
    this.stopWork,
    this.quietLimit = interruptQuietLimit,
    this.workLimit = interruptWorkLimit,
  });

  /// Completes once the cancelled flow loop has returned; its error counts
  /// as returned.
  final Future<void> Function()? stopWork;
  final Duration workLimit;

  /// Writes the report with the flows done so far, still partial.
  final void Function() writePartial;

  /// The pass's quiet end, which also writes what it found into the report.
  final Future<void> Function() leaveQuiet;

  /// Why the quiet end is skipped, asked at the moment of the interrupt;
  /// null runs it.
  final String? Function() quietSkipped;
  final void Function() release;
  final void Function(String line) say;
  final Duration quietLimit;

  /// Runs the steps above and returns [exitInterrupted]; none of them can
  /// keep the next from running.
  Future<int> handle() async {
    say('interrupted — writing the report as it stands');
    final work = stopWork;
    if (work != null) {
      try {
        await work().timeout(workLimit);
      } on TimeoutException {
        say(
          'the flow in flight did not stop within ${workLimit.inSeconds} s — '
          'its next device call fails, so the pass ends without it',
        );
      } on Object {
        // A loop that ended by throwing has ended all the same.
      }
    }
    try {
      writePartial();
    } on Object catch (e) {
      say('the report could not be written: $e');
    }
    final skipped = quietSkipped();
    if (skipped != null) {
      say('quiet relaunch skipped: $skipped');
    } else {
      try {
        await leaveQuiet().timeout(quietLimit);
      } on TimeoutException {
        say(
          'the quiet end did not finish within ${quietLimit.inSeconds} s — '
          'the device may still hold the seed\'s alarms',
        );
      } on Object catch (e) {
        say('the quiet end failed: $e');
      }
    }
    try {
      release();
    } on Object catch (e) {
      say('the guest\'s hold could not be released: $e');
    }
    return exitInterrupted;
  }
}

/// What an interrupted `fleet pass` does: waits up to [limit] for [shards]
/// — the children, each ending as [PassInterrupt] says — and returns
/// [exitInterrupted] either way.
Future<int> awaitShardsOnInterrupt(
  Future<void> shards, {
  required void Function(String line) say,
  Duration limit = interruptShardWait,
}) async {
  say(
    'interrupted — waiting up to ${limit.inSeconds} s for the shards to '
    'write their reports and leave their devices quiet',
  );
  var finished = false;
  await Future.any([
    shards.then((_) => finished = true, onError: (_) => finished = true),
    Future<void>.delayed(limit),
  ]);
  if (!finished) say('the shards did not end within ${limit.inSeconds} s');
  return exitInterrupted;
}
