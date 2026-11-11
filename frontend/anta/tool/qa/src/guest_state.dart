import 'dart:convert';
import 'dart:io';

import 'fleet.dart';
import 'paths.dart';

/// The pass or install running on a fleet guest. Only the process that set
/// it clears it; one whose [pid] is gone was killed before its `finally`
/// ran, and reads as no hold at all.
class GuestHold {
  const GuestHold({
    required this.pid,
    required this.verb,
    required this.since,
    this.beatAt,
    this.checkout,
    this.unconfirmed = false,
    this.unreadable = false,
  });

  /// What a state file that exists but cannot be read holds: it may hide a
  /// live hold, so it keeps every stop off its guest until it reads again
  /// or a person runs `reap --force`.
  factory GuestHold.unreadableFile() => GuestHold(
    pid: 0,
    verb: 'an unreadable state file',
    since: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    unreadable: true,
  );

  final int pid;

  /// `pass` or `fleet install`: what `fleet status` and `reap` name.
  final String verb;
  final DateTime since;

  /// The holder's last sign of life ([GuestState.beat]): a pass may run
  /// longer than any fixed age a hold could be trusted for, so the guard
  /// judges a hold by its heartbeat, not by its start.
  final DateTime? beatAt;

  /// The project root of the checkout that took the hold: the fleet is
  /// shared by every checkout on the host, worktrees included.
  final String? checkout;

  /// Never on file: [FleetHost.withHolds] sets it when the holder's process
  /// could not be checked. Such a hold protects like a live one.
  final bool unconfirmed;

  /// Never on file: see [GuestHold.unreadableFile].
  final bool unreadable;

  /// When the holder last showed it was working.
  DateTime get lastBeat => beatAt ?? since;

  static GuestHold? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final pid = json['pid'];
    final verb = json['verb'];
    final since = DateTime.tryParse(json['since'] as String? ?? '');
    if (pid is! int || verb is! String || since == null) return null;
    final checkout = json['checkout'];
    return GuestHold(
      pid: pid,
      verb: verb,
      since: since,
      beatAt: DateTime.tryParse(json['beatAt'] as String? ?? ''),
      checkout: checkout is String ? checkout : null,
    );
  }

  Map<String, Object?> toJson() => {
    'pid': pid,
    'verb': verb,
    'since': since.toUtc().toIso8601String(),
    if (beatAt != null) 'beatAt': beatAt!.toUtc().toIso8601String(),
    if (checkout != null) 'checkout': checkout,
  };

  GuestHold withBeat(DateTime at) => GuestHold(
    pid: pid,
    verb: verb,
    since: since,
    beatAt: at,
    checkout: checkout,
  );

  /// This hold as one whose holder could not be checked.
  GuestHold asUnconfirmed() => GuestHold(
    pid: pid,
    verb: verb,
    since: since,
    beatAt: beatAt,
    checkout: checkout,
    unconfirmed: true,
  );

  /// `pass pid 1234 since 14:05 from D:\…\anta`, as `fleet status` and
  /// `reap` print it.
  String get label {
    if (unreadable) return '$verb (left alone until it reads)';
    final local = since.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '$verb pid $pid since ${two(local.hour)}:${two(local.minute)}'
        '${unconfirmed ? ' (its process could not be checked)' : ''}'
        '${checkout == null ? '' : ' from $checkout'}';
  }
}

/// What the harness knows about one fleet guest's life, kept in
/// `guest_<avd>.json` in the host-wide fleet directory
/// ([QaPaths.fleetState]) because no single process lives as long as the
/// guest does: when it booted, when a verb last used it, and what holds it
/// now. `reap` and the idle guard read it to tell a guest someone is using
/// from one an agent forgot. Every write is best-effort: a verb never fails
/// because this file could not be written.
class GuestState {
  const GuestState({
    this.bootedAt,
    this.lastUsedAt,
    this.hold,
    this.keep = false,
    this.unreadable = false,
  });

  final DateTime? bootedAt;
  final DateTime? lastUsedAt;

  /// As written; [liveHold] says whether its holder still runs.
  final GuestHold? hold;

  /// `fleet boot --keep-up`: the idle guard never stops this guest for
  /// being unused (a hung one it still force-stops); `reap` still does.
  final bool keep;

  /// The file exists but could not be read or parsed: it may hold a live
  /// hold nobody can see, so it protects its guest ([read]).
  final bool unreadable;

  static GuestState? parse(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) return null;
      return GuestState(
        bootedAt: DateTime.tryParse(json['bootedAt'] as String? ?? ''),
        lastUsedAt: DateTime.tryParse(json['lastUsedAt'] as String? ?? ''),
        hold: GuestHold.fromJson(json['hold']),
        keep: json['keep'] == true,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// The file at [path]: null when there is none, an [unreadable] state
  /// when it exists but cannot be read or parsed — never "no hold", since a
  /// check that could not answer must not authorize a stop.
  static GuestState? read(String path) {
    final String text;
    try {
      text = File(path).readAsStringSync();
    } on PathNotFoundException {
      return null;
    } on FileSystemException {
      return const GuestState(unreadable: true);
    }
    return parse(text) ?? const GuestState(unreadable: true);
  }

  Map<String, Object?> toJson() => {
    'bootedAt': bootedAt?.toUtc().toIso8601String(),
    'lastUsedAt': lastUsedAt?.toUtc().toIso8601String(),
    if (hold != null) 'hold': hold!.toJson(),
    if (keep) 'keep': true,
  };

  /// How long the guest has gone unused: since the last verb on it, else
  /// since its boot; null when the file knows neither.
  Duration? idleAge(DateTime now) {
    final since = lastUsedAt ?? bootedAt;
    if (since == null) return null;
    final age = now.difference(since);
    return age.isNegative ? Duration.zero : age;
  }

  /// [hold] while [holderAlive] says its process still runs, else null.
  GuestHold? liveHold({required bool holderAlive}) =>
      hold != null && holderAlive ? hold : null;

  GuestState copyWith({
    DateTime? bootedAt,
    DateTime? lastUsedAt,
    GuestHold? hold,
    bool clearHold = false,
    bool? keep,
  }) => GuestState(
    bootedAt: bootedAt ?? this.bootedAt,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    hold: clearHold ? null : (hold ?? this.hold),
    keep: keep ?? this.keep,
  );

  /// Reads [path], applies [change] and writes the result back; a missing
  /// file starts from nothing. A file that exists but does not read is
  /// retried briefly and then left as it is: starting from nothing would
  /// drop a hold for good. The write goes to a temporary file renamed over
  /// [path], so a reader never sees a half-written one. Returns false when
  /// nothing was written, which no caller treats as an error.
  static bool update(String path, GuestState Function(GuestState) change) {
    for (var attempt = 0; ; attempt++) {
      final current = read(path);
      if (current != null && current.unreadable) {
        if (attempt >= _unreadableRetries) return false;
        sleep(_retryPause);
        continue;
      }
      return writeFileAtomically(
        path,
        jsonEncode(change(current ?? const GuestState()).toJson()),
      );
    }
  }

  static const int _unreadableRetries = 5;

  /// A guest `fleet boot` is bringing up, or just brought up. [keep] only
  /// ever sets the `--keep-up` mark: a recovery or a recycle boots the
  /// guest again through a plain child boot, and the owner's mark must
  /// survive that; `fleet stop`, `reap` and the guard's stops clear it by
  /// removing the file. A hold already on file is kept: a pass recycling
  /// its own guest boots it through a child while it still holds it.
  static bool booted(String path, DateTime at, {bool keep = false}) => update(
    path,
    (s) => s.copyWith(bootedAt: at, lastUsedAt: at, keep: keep || s.keep),
  );

  /// `fleet boot --keep-up` on a guest that was already up.
  static bool markKeep(String path, DateTime at) =>
      update(path, (s) => s.copyWith(lastUsedAt: at, keep: true));

  static bool touch(String path, DateTime at) =>
      update(path, (s) => s.copyWith(lastUsedAt: at));

  static bool take(String path, GuestHold hold) =>
      update(path, (s) => s.copyWith(hold: hold, lastUsedAt: hold.since));

  /// The holder [pid] is still working [at]: its hold's heartbeat and the
  /// guest's last use move; a hold someone else took is left as it is.
  static bool beat(String path, int pid, DateTime at) => update(
    path,
    (s) => s.hold?.pid == pid
        ? s.copyWith(hold: s.hold!.withBeat(at), lastUsedAt: at)
        : s.copyWith(lastUsedAt: at),
  );

  /// Clears the hold only when [pid] set it, so a holder that ends late
  /// never drops a newer one, and marks the guest used [at] then: a pass
  /// that ran for ten minutes leaves a guest used now, not ten minutes ago.
  static bool release(String path, int pid, DateTime at) => update(
    path,
    (s) => s.hold?.pid == pid
        ? s.copyWith(clearHold: true, lastUsedAt: at)
        : s.copyWith(lastUsedAt: at),
  );

  /// Removes the file; false when there was none or it would not go.
  static bool forget(String path) {
    final file = File(path);
    try {
      if (!file.existsSync()) return false;
      file.deleteSync();
      return true;
    } on FileSystemException {
      return false;
    }
  }
}

/// Someone stopped a held fleet guest on purpose — `fleet stop --force`,
/// `reap --force`, the guard on a hold gone silent — kept in
/// `stop_<avd>.json` beside the guest's state file until the guest's next
/// boot. A pass that loses its guest reads it to tell a stop someone asked
/// for from a crash: it recovers a crash, and ends on a request instead of
/// booting the guest again under the person who stopped it.
class StopRequest {
  const StopRequest({
    required this.by,
    required this.pid,
    required this.at,
    this.checkout,
  });

  /// The verb that stopped it: `fleet stop --force`, `reap --force`, `the
  /// idle guard`.
  final String by;
  final int pid;
  final DateTime at;

  /// The project root of the checkout the stop came from.
  final String? checkout;

  static StopRequest? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final by = json['by'];
    final pid = json['pid'];
    final at = DateTime.tryParse(json['at'] as String? ?? '');
    if (by is! String || pid is! int || at == null) return null;
    final checkout = json['checkout'];
    return StopRequest(
      by: by,
      pid: pid,
      at: at,
      checkout: checkout is String ? checkout : null,
    );
  }

  Map<String, Object?> toJson() => {
    'by': by,
    'pid': pid,
    'at': at.toUtc().toIso8601String(),
    if (checkout != null) 'checkout': checkout,
  };

  /// `fleet stop --force (pid 1234) at 14:05 from D:\…\anta`.
  String get label {
    final local = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '$by (pid $pid) at ${two(local.hour)}:${two(local.minute)}'
        '${checkout == null ? '' : ' from $checkout'}';
  }

  /// The request on file at [path]; null when there is none or it does not
  /// read — a request nobody can read cannot name who asked, and the pass
  /// then recovers its guest as it always did.
  static StopRequest? read(String path) {
    try {
      return fromJson(jsonDecode(File(path).readAsStringSync()));
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// Records [request] for the guest whose request file is [path], before
  /// the stop, so a pass that sees its guest go never reads the stop
  /// before the request. False when nothing was written.
  static bool record(String path, StopRequest request) =>
      writeFileAtomically(path, jsonEncode(request.toJson()));

  /// The guest is booting again: whatever was asked of the guest before is
  /// done.
  static bool clear(String path) => GuestState.forget(path);
}

/// A stop request from this process, for a held guest about to be stopped
/// on purpose.
StopRequest stopRequestNow(String by, QaPaths paths) => StopRequest(
  by: by,
  pid: pid,
  at: DateTime.now(),
  checkout: paths.projectRoot,
);

const Duration _retryPause = Duration(milliseconds: 40);

/// Writes [text] to a temporary file beside [path] and renames it into
/// place, so a reader sees the old file or the new one, never a part of
/// either; a rename Windows refuses while a reader has the file open is
/// retried. False when nothing was written.
bool writeFileAtomically(String path, String text) {
  final temp = File('$path.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp');
  try {
    temp
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text, flush: true);
  } on FileSystemException {
    _deleteQuietly(temp);
    return false;
  }
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      temp.renameSync(path);
      return true;
    } on FileSystemException {
      sleep(_retryPause);
    }
  }
  _deleteQuietly(temp);
  return false;
}

void _deleteQuietly(File file) {
  try {
    file.deleteSync();
  } on FileSystemException {
    return;
  }
}

/// The state file of the fleet guest on [serial], or null for a serial
/// off the fleet's ports (the owner's `emulator-5554`, a phone).
String? guestStatePathFor(QaPaths paths, String serial) {
  final index = fleetIndexOfSerial(serial);
  return index == null ? null : paths.guestStateFor(fleetName(index));
}

/// `35s`, `12m`, `2h05m`: an idle age as one short word.
String idleLabel(Duration age) {
  if (age.inMinutes < 1) return '${age.inSeconds}s';
  if (age.inHours < 1) return '${age.inMinutes}m';
  return '${age.inHours}h${(age.inMinutes % 60).toString().padLeft(2, '0')}m';
}

/// Idle this long with no live hold, a fleet guest is a leftover: `doctor`
/// names it and the idle guard stops it.
const Duration guestIdleLimit = Duration(minutes: 30);
