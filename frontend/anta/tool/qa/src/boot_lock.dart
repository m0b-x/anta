import 'dart:convert';
import 'dart:io';

import 'runner.dart';

/// Who holds the host's boot lock: the `fleet boot` process [pid] booting
/// [avd] since [at], started from the checkout at [checkout].
class BootLockOwner {
  const BootLockOwner({
    required this.pid,
    required this.avd,
    required this.at,
    required this.checkout,
  });

  final int pid;
  final String avd;
  final DateTime at;
  final String checkout;

  Map<String, Object?> toJson() => {
    'pid': pid,
    'avd': avd,
    'at': at.toIso8601String(),
    'checkout': checkout,
  };

  /// The owner [text] names, or null for a file that does not read — one
  /// being written this instant, or torn.
  static BootLockOwner? parse(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map) return null;
      final pid = json['pid'];
      final at = DateTime.tryParse('${json['at']}');
      if (pid is! int || at == null) return null;
      return BootLockOwner(
        pid: pid,
        avd: '${json['avd'] ?? '?'}',
        at: at,
        checkout: '${json['checkout'] ?? '?'}',
      );
    } on FormatException {
      return null;
    }
  }

  /// The lock at [path]: null when there is none or it does not read.
  static BootLockOwner? read(String path) {
    try {
      return parse(File(path).readAsStringSync());
    } on FileSystemException {
      return null;
    }
  }

  bool sameAs(BootLockOwner other) => pid == other.pid && at == other.at;
}

/// How long a boot waits behind an owner that could not be checked before
/// it boots anyway, with a warning: a check that cannot answer never
/// blocks the fleet for good.
const Duration bootLockPatience = Duration(minutes: 3);

/// The age past which a lock is not believed even with its pid alive: a
/// boot gives up within six minutes, so an older lock names a pid the host
/// has handed to something else since.
const Duration bootLockStale = Duration(minutes: 10);

/// Takes the host's boot lock at [path] for [me], waiting while another
/// boot holds it — several cold boots at once is what hung the fleet (§6,
/// §8 of the record). An owner [liveness] shows gone is taken over; one
/// that cannot be checked, or one past [bootLockStale], is waited on for
/// [patience] and then overridden with a warning. Same-process re-entry
/// (`fleet boot --all` boots one guest after another) never waits on
/// itself. [say] gets each line; a warning's starts `warning: `.
Future<void> takeBootLock({
  required String path,
  required BootLockOwner me,
  required Future<Liveness> Function(int pid) liveness,
  required void Function(String line) say,
  Duration patience = bootLockPatience,
  Duration poll = const Duration(seconds: 2),
  Future<void> Function(Duration)? sleep,
  DateTime Function()? clock,
}) async {
  final now = clock ?? DateTime.now;
  final pause = sleep ?? (d) => Future<void>.delayed(d);
  String? waitedOn;
  DateTime? doubtSince;
  while (true) {
    if (_createExclusive(path, me)) return;
    final owner = BootLockOwner.read(path);
    if (owner != null && owner.pid == me.pid) {
      _write(path, me);
      return;
    }
    final state = owner == null
        ? Liveness.unknown
        : now().difference(owner.at) > bootLockStale
        ? Liveness.unknown
        : await liveness(owner.pid);
    if (owner != null && state == Liveness.gone) {
      say(
        'boot: the boot lock of pid ${owner.pid} (${owner.avd}) is left by a '
        'process that is gone — taking it over',
      );
      _removeIfStill(path, owner);
      continue;
    }
    final key = owner == null ? '' : '${owner.pid}@${owner.at}';
    if (key != waitedOn) {
      waitedOn = key;
      doubtSince = null;
      if (owner != null) {
        say(
          'boot: waiting for ${owner.avd} (pid ${owner.pid} from '
          '${owner.checkout})',
        );
      }
    }
    if (state == Liveness.unknown) {
      doubtSince ??= now();
      if (now().difference(doubtSince) >= patience) {
        say(
          'warning: boot: the boot lock '
          '${owner == null ? 'does not read' : 'of pid ${owner.pid} (${owner.avd}) could not be checked'} '
          'for ${patience.inMinutes} min — booting anyway',
        );
        _write(path, me);
        return;
      }
    } else {
      doubtSince = null;
    }
    await pause(poll);
  }
}

/// Lets the lock go when it still names [me]; a lock taken over meanwhile
/// is its new owner's.
void releaseBootLock(String path, BootLockOwner me) {
  final owner = BootLockOwner.read(path);
  if (owner == null || !owner.sameAs(me)) return;
  try {
    File(path).deleteSync();
  } on FileSystemException {
    // Gone already, or held open for a read this instant: the next boot
    // reads a pid that is gone and takes it over.
  }
}

bool _createExclusive(String path, BootLockOwner me) {
  final file = File(path);
  try {
    file.parent.createSync(recursive: true);
    // CREATE_NEW / O_EXCL: of two boots that find no lock, one creates it.
    file.createSync(exclusive: true);
  } on FileSystemException {
    return false;
  }
  _write(path, me);
  return true;
}

void _write(String path, BootLockOwner me) {
  try {
    File(path).writeAsStringSync(jsonEncode(me.toJson()), flush: true);
  } on FileSystemException {
    // Read by another boot this instant; it reads it as not yet written
    // and waits a poll.
  }
}

/// Deletes the lock only while it still names [owner]: another waiter may
/// have taken it over a moment ago.
void _removeIfStill(String path, BootLockOwner owner) {
  final now = BootLockOwner.read(path);
  if (now == null || !now.sameAs(owner)) return;
  try {
    File(path).deleteSync();
  } on FileSystemException {
    // Taken or removed by someone else in between.
  }
}
