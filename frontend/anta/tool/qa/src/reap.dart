import 'dart:io';

import 'adb.dart';
import 'boot_lock.dart';
import 'errors.dart';
import 'fleet.dart';
import 'guard.dart';
import 'guest_state.dart';
import 'paths.dart';
import 'process_runner.dart';
import 'quiet.dart';
import 'runner.dart';
import 'self_build.dart';

/// How many pass directories per suite `reap --prune` keeps, newest first:
/// as many as `qa pass --history` reads by default.
const int keptPassDirs = 20;

/// One emulator crash handler whose parent is gone.
class CrashHandler {
  const CrashHandler({
    required this.pid,
    required this.parentPid,
    required this.path,
  });

  final int pid;
  final int parentPid;
  final String path;
}

/// The PowerShell test a process `$p` passes when it is an orphaned
/// emulator crash handler: `crashpad_handler.exe` run from [emulatorDir]
/// (TeamViewer and Chrome ship one of their own), whose parent is gone, or
/// was started after it (the parent's pid was reused). An unreadable
/// executable path — a process of another user — never passes.
String _orphanedCrashHandlerTest(String emulatorDir) {
  final root = _withSeparator(emulatorDir).replaceAll("'", "''");
  return "\$p.Name -eq 'crashpad_handler.exe' -and \$p.ExecutablePath -and "
      "\$p.ExecutablePath.StartsWith('$root', [StringComparison]::OrdinalIgnoreCase) -and "
      "(\$null -eq (\$q = Get-CimInstance Win32_Process -Filter ('ProcessId=' + \$p.ParentProcessId)) -or "
      '\$q.CreationDate -gt \$p.CreationDate)';
}

String _withSeparator(String dir) =>
    dir.endsWith(r'\') || dir.endsWith('/') ? dir : '$dir\\';

/// PowerShell that prints every orphaned emulator crash handler as its
/// pid, its parent's pid and its path, tab-separated. It holds no double
/// quote: `powershell -Command` misreads them on Windows.
String crashHandlerListScript(String emulatorDir) =>
    "Get-CimInstance Win32_Process -Filter 'Name=''crashpad_handler.exe''' | "
    'ForEach-Object { \$p = \$_; if (${_orphanedCrashHandlerTest(emulatorDir)}) '
    '{ (\$p.ProcessId, \$p.ParentProcessId, \$p.ExecutablePath) -join [char]9 } }';

/// PowerShell that kills [pid] only while it still passes the orphan test —
/// read again right before the kill, so a pid reused since the list was
/// taken is never hit — and prints `killed`, `gone` or `mismatch`.
String crashHandlerKillScript(int pid, String emulatorDir) =>
    "\$p = Get-CimInstance Win32_Process -Filter 'ProcessId=$pid'; "
    "if (\$null -eq \$p) { 'gone'; exit 0 }; "
    'if (${_orphanedCrashHandlerTest(emulatorDir)}) '
    "{ Stop-Process -Id $pid -Force -ErrorAction Stop; 'killed' } else { 'mismatch' }";

/// [crashHandlerListScript]'s output.
List<CrashHandler> parseCrashHandlers(String output) => [
  for (final line in output.split('\n'))
    if (line.replaceAll('\r', '').split('\t') case [
      final pid,
      final parent,
      final path,
    ])
      if ((int.tryParse(pid.trim()), int.tryParse(parent.trim())) case (
        final int p,
        final int q,
      ))
        CrashHandler(pid: p, parentPid: q, path: path.trim()),
];

/// The pass directories beyond the newest [keep] per suite, oldest first,
/// from directory names `<suite>_<yyyyMMdd_HHmmss_mmm>_<device>`; a name
/// of any other shape is never pruned.
List<String> prunablePassDirs(List<String> names, {int keep = keptPassDirs}) {
  final pattern = RegExp(r'^(.+?)_(\d{8}_\d{6}_\d{3})_.+$');
  final bySuite = <String, List<({String name, String stamp})>>{};
  for (final name in names) {
    final match = pattern.firstMatch(name);
    if (match == null) continue;
    bySuite.putIfAbsent(match.group(1)!, () => []).add((
      name: name,
      stamp: match.group(2)!,
    ));
  }
  final prune = <({String name, String stamp})>[];
  for (final dirs in bySuite.values) {
    dirs.sort((a, b) => b.stamp.compareTo(a.stamp));
    prune.addAll(dirs.skip(keep));
  }
  prune.sort((a, b) => a.stamp.compareTo(b.stamp));
  return [for (final dir in prune) dir.name];
}

/// The ids of the `vm_<id>.txt` and `dtd_<id>.txt` files in [names] that
/// name an emulator serial, by file name.
Map<String, String> emulatorUriFiles(List<String> names) => {
  for (final name in names)
    if (RegExp(r'^(?:vm|dtd)_(emulator-\d+)\.txt$').firstMatch(name)
        case final match?)
      name: match.group(1)!,
};

/// What `reap` found, before it acts: everything an earlier session left.
class ReapSurvey {
  ReapSurvey({
    required this.runPid,
    required this.runState,
    required this.guests,
    required this.crashHandlers,
    required this.staleFiles,
    required this.passDirs,
    required this.notes,
    this.fleetUp = const {},
    this.guard,
    this.contested = const [],
  });

  /// Fleet guests whose qemu runs while their port answers as something
  /// else — another AVD, or nothing at all when the guest's own console is
  /// dead. Neither stop can be proven safe from here, so they are reported
  /// and left to a person.
  final List<FleetMember> contested;

  /// Every fleet guest that is up or coming up, held ones included.
  final Set<String> fleetUp;

  /// The idle guard `guard.pid` names while it runs; null when none does.
  final GuardRecord? guard;

  /// The pid in `run.pid`, and whether it is `ours`, `other` or `gone`.
  final int? runPid;
  final String? runState;

  /// Every fleet guest that is up or coming up, its live hold filled in.
  final List<FleetMember> guests;
  final List<CrashHandler> crashHandlers;

  /// Files whose process or device is gone, each with why.
  final List<({String path, String why})> staleFiles;

  /// Pass directories `--prune` deletes; empty without it.
  final List<String> passDirs;

  /// What could not be read, said once.
  final List<String> notes;
}

/// Returns the host to clean: the recorded `flutter run`, the fleet guests,
/// orphaned emulator crash handlers and state files whose process is gone.
/// Every kill it does is one the
/// harness already sanctions — the run's tree, a fleet guest through
/// [FleetHost.stop] or the guarded [FleetHost.forceStop] — plus the crash
/// handler, guarded by its path and its missing parent.
class HostReaper {
  HostReaper({
    required this.paths,
    required this.runner,
    required this.host,
    required this.windows,
    required this.isAlive,
    required this.stopRun,
    this.now,
    this.quiet,
  });

  /// Cancels the app's alarms on a guest no one holds before it is stopped
  /// ([quietFleetGuestIfUp]): the alarm plugin re-arms what it stored at
  /// the next launch and at boot, so a guest stopped with them armed rings
  /// whenever it next comes up. Null quiets nothing.
  final Future<GuestQuiet?> Function(FleetMember member)? quiet;

  final QaPaths paths;
  final ProcessRunner runner;

  /// Null on a host without the Android SDK: only the run and the files.
  final FleetHost? host;

  /// The fleet parts run only here, like the other fleet verbs' host work.
  final bool windows;

  /// Only a [Liveness.gone] makes a pid file stale.
  final Future<Liveness> Function(int pid) isAlive;

  /// Ends the recorded run as `kill-run` does, returning its lines.
  final Future<List<String>> Function() stopRun;
  final DateTime Function()? now;

  DateTime get _now => now?.call() ?? DateTime.now();

  String? get _emulatorDir {
    final root = host?.sdkRoot;
    return root == null ? null : joinPath(root, ['emulator']);
  }

  List<String> _fileNames(String path) {
    final dir = Directory(path);
    try {
      if (!dir.existsSync()) return const [];
      return [
        for (final file in dir.listSync().whereType<File>())
          file.uri.pathSegments.last,
      ];
    } on FileSystemException {
      return const [];
    }
  }

  /// [path]'s text, '' when it is gone (a file can vanish between the
  /// listing and the read), null when it is there but will not read.
  static String? _read(String path) {
    try {
      return File(path).readAsStringSync().trim();
    } on PathNotFoundException {
      return '';
    } on FileSystemException {
      return null;
    }
  }

  Future<ReapSurvey> survey({required bool prune}) async {
    final notes = <String>[];
    final names = _fileNames(paths.buildQa);
    final fleetNames = _fileNames(paths.fleetState);
    final staleFiles = <({String path, String why})>[];

    final runText = _read(paths.runPid);
    final runPid = runText == null ? null : int.tryParse(runText);
    final runState = runPid == null
        ? null
        : await probeRecordedRun(runPid, paths, runner, windows: windows);
    if (runText == null) {
      notes.add('run.pid could not be read — left as it is');
    } else if (runText.isNotEmpty && runPid == null) {
      staleFiles.add((path: paths.runPid, why: 'names no pid'));
    }

    for (final name in names) {
      if (!RegExp(r'^emulator(?:_.+)?\.pid$').hasMatch(name)) continue;
      final path = joinPath(paths.buildQa, [name]);
      final text = _read(path);
      if (text == null || text.isEmpty) continue;
      final pid = int.tryParse(text);
      // A pid whose process could not be checked keeps its file.
      if (pid == null || await isAlive(pid) == Liveness.gone) {
        staleFiles.add((path: path, why: 'pid ${pid ?? '?'} is gone'));
      }
    }

    final lock = File(paths.rebuildLock);
    final lockStat = lock.statSync();
    if (lockStat.type != FileSystemEntityType.notFound &&
        _now.difference(lockStat.modified) >= rebuildLockTtl) {
      staleFiles.add((
        path: lock.path,
        why: 'older than ${rebuildLockTtl.inMinutes} min',
      ));
    }

    // Fleet state from before it moved to the host-wide directory: no
    // build reads it any more, and a stale copy would only mislead.
    for (final name in names) {
      if (RegExp(r'^guest_.+\.json$').hasMatch(name) ||
          name == 'guard.pid' ||
          name == 'guard.log' ||
          isGuardCopyName(name)) {
        staleFiles.add((
          path: joinPath(paths.buildQa, [name]),
          why: 'fleet state now lives in ${paths.fleetState}',
        ));
      }
    }

    // A writer that died between its temporary file and the rename.
    for (final name in fleetNames) {
      if (!name.endsWith('.tmp') || isGuardCopyName(name)) continue;
      final path = joinPath(paths.fleetState, [name]);
      final stat = File(path).statSync();
      if (stat.type != FileSystemEntityType.notFound &&
          _now.difference(stat.modified) >= const Duration(minutes: 1)) {
        staleFiles.add((path: path, why: 'an unfinished write'));
      }
    }

    // A boot that died holding the host's boot lock; one that could not be
    // checked, or that does not read, may be a live boot's and stays.
    final booting = BootLockOwner.read(paths.bootLock);
    if (booting != null && await isAlive(booting.pid) == Liveness.gone) {
      staleFiles.add((
        path: paths.bootLock,
        why: 'pid ${booting.pid} booting ${booting.avd} is gone',
      ));
    }

    GuardRecord? guard;
    if (windows) {
      final record = GuardRecord.read(paths.guardPid);
      if (record != null) {
        final said = await probeGuard(record.pid, runner);
        if (said == 'ours') {
          guard = record;
        } else if (said != null) {
          staleFiles.add((
            path: paths.guardPid,
            why:
                'pid ${record.pid} '
                '${said == 'gone' ? 'is gone' : 'is no longer a guard'}',
          ));
        }
      } else if (File(paths.guardPid).existsSync() &&
          _read(paths.guardPid) != null) {
        // Only a file that reads and names no pid (a guard writes it whole
        // through a rename); one that will not read may be a live guard's.
        staleFiles.add((path: paths.guardPid, why: 'names no pid'));
      }
      // A running guard holds its own copy, and a guard between two polls
      // may be about to hand over to a newer one: only with no guard at all
      // is every copy a leftover.
      if (guard == null) {
        for (final copy in guardCopies(paths)) {
          staleFiles.add((path: copy, why: 'no guard runs from it'));
        }
      }
    }

    final guests = <FleetMember>[];
    final contested = <FleetMember>[];
    final running = <String>{};
    final fleet = host;
    if (windows && fleet != null) {
      List<AdbDevice>? devices;
      try {
        devices = await fleet.adb.devices(timeout: const Duration(seconds: 20));
      } on QaException catch (e) {
        notes.add('adb did not answer, so URIs are left: ${e.message}');
      }
      final created = fleet.createdIndices();
      final members = await fleet.withHolds(
        await fleet.members(
          upTo: created.isEmpty ? 0 : created.last,
          paths: paths,
          devices: devices ?? const [],
        ),
      );
      for (final member in members) {
        if (member.qemu != null || (devices != null && member.up)) {
          running.add(member.name);
          if (member.heldBy == null) {
            guests.add(member);
          } else if (member.qemu != null) {
            contested.add(member);
          }
        }
      }
      for (final name in fleetNames) {
        final match = RegExp(r'^guest_(.+)\.json$').firstMatch(name);
        if (match == null || running.contains(match.group(1))) continue;
        // Without adb, a guest on adb but without a qemu line cannot be
        // told from a stopped one; its file stays.
        if (devices == null) continue;
        staleFiles.add((
          path: joinPath(paths.fleetState, [name]),
          why: '${match.group(1)} is not running',
        ));
      }
      if (devices != null) {
        final attached = {
          for (final d in devices)
            if (d.usable) d.serial,
        };
        // No forwards here: adb drops a serial's forwards itself the moment
        // that emulator leaves (seen live 2026-11-11), so a stopped guest
        // never leaves one behind.
        emulatorUriFiles(names).forEach((name, serial) {
          if (attached.contains(serial)) return;
          staleFiles.add((
            path: joinPath(paths.buildQa, [name]),
            why: '$serial is not attached',
          ));
        });
      }
    }

    final crashHandlers = <CrashHandler>[];
    final emulatorDir = _emulatorDir;
    if (windows && emulatorDir != null) {
      final result = await runner.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        crashHandlerListScript(emulatorDir),
      ], timeout: const Duration(seconds: 30));
      if (result.ok) {
        crashHandlers.addAll(parseCrashHandlers(result.stdout));
      } else {
        notes.add('the crash handlers could not be listed: ${result.combined}');
      }
    }

    final passDirs = <String>[];
    final passRoot = Directory(paths.passRoot);
    if (prune && passRoot.existsSync()) {
      passDirs.addAll(
        prunablePassDirs([
          for (final dir in passRoot.listSync().whereType<Directory>())
            dir.uri.pathSegments.where((s) => s.isNotEmpty).last,
        ]).map((name) => joinPath(paths.passRoot, [name])),
      );
    }

    return ReapSurvey(
      runPid: runPid,
      runState: runState,
      guests: guests,
      crashHandlers: crashHandlers,
      staleFiles: staleFiles,
      passDirs: passDirs,
      notes: notes,
      fleetUp: running,
      guard: guard,
      contested: contested,
    );
  }

  /// Acts on what [survey] found, or with [dryRun] only says what it
  /// would do. [say] gets one line per action taken or skipped; the result
  /// is what is left and why, empty when the host is clean, and whether
  /// anything that was tried failed.
  Future<({List<String> left, bool failed})> reap({
    required bool dryRun,
    required bool force,
    required bool prune,
    required void Function(String line) say,
  }) async {
    final found = await survey(prune: prune);
    final left = <String>[];
    var failed = false;
    String would(String action) => dryRun ? 'would $action' : action;

    found.notes.forEach(say);

    final runPid = found.runPid;
    // Whether the recorded run is over (or, dry, would be) by the time the
    // guests are read: its own hold on a fleet guest went with it.
    var runEnded = false;
    if (runPid != null) {
      switch (found.runState) {
        case 'ours':
          if (dryRun) {
            say(would('stop the recorded flutter run (pid $runPid)'));
            runEnded = true;
          } else {
            final lines = await stopRun();
            lines.forEach(say);
            switch (await isAlive(runPid)) {
              case Liveness.alive:
                failed = true;
                left.add('flutter run pid $runPid is still alive');
              case Liveness.unknown:
                failed = true;
                left.add('flutter run pid $runPid could not be checked');
              case Liveness.gone:
                runEnded = true;
            }
          }
        case 'gone' || 'other':
          say(
            '${would('remove')} run.pid: pid $runPid '
            '${found.runState == 'gone' ? 'is gone' : 'is no longer the harness\'s run (left running)'}',
          );
          if (!dryRun) {
            // Without run.pid, kill-run's ending kills nothing of that pid
            // and only forgets what the dead run recorded.
            try {
              File(paths.runPid).deleteSync();
            } on PathNotFoundException {
              // Gone already: what was to be done is done.
            }
            (await stopRun()).forEach(say);
          }
        default:
          left.add('run.pid $runPid could not be checked');
      }
    }

    final fleet = host;
    var stopped = false;
    for (final member in found.guests) {
      final read = member.hold;
      final hold =
          runEnded &&
              read != null &&
              read.verb == runHoldVerb &&
              read.pid == runPid &&
              read.checkout == paths.projectRoot
          ? null
          : read;
      if (hold != null && !force) {
        say(
          'skip: ${member.name} (${member.serial}) — held by ${hold.label}; '
          '--force stops it anyway',
        );
        left.add('${member.name} held by ${hold.label}');
        continue;
      }
      final how = member.state == FleetState.device ? 'stop' : 'force-stop';
      if (dryRun) {
        say(
          would(
            '$how ${member.name} (${member.serial}'
            '${member.qemu == null ? '' : ', qemu ${member.qemu!.pid}'})'
            '${hold == null ? '' : ' although ${hold.label} holds it'}',
          ),
        );
        continue;
      }
      if (hold != null) {
        // The pass holding it must read this as a stop someone asked for,
        // not a crash to recover from by booting the guest again.
        StopRequest.record(
          paths.stopRequestFor(member.name),
          stopRequestNow('reap --force', paths),
        );
      } else if (member.state == FleetState.device) {
        // A held guest is its holder's to quiet; a quiet that fails is said
        // and the stop goes ahead.
        final quieted = await quiet?.call(member);
        if (quietWorthSaying(quieted)) {
          say(quieted!.line(member.name, 'before the stop'));
        }
      }
      try {
        // forceStop goes the console way for a guest adb lists and kills
        // the qemu only for one it does not, after its command-line guard.
        say(await fleet!.forceStop(member.index));
        GuestState.forget(paths.guestStateFor(member.name));
        stopped = true;
      } on QaException catch (e) {
        failed = true;
        say('failed: ${member.name} — ${e.message}');
        left.add('${member.name} could not be stopped');
      }
    }

    for (final member in found.contested) {
      failed = true;
      say(
        'left: ${member.name} (${member.serial}, qemu ${member.qemu!.pid}) — '
        'its port answers as ${member.heldBy}, so neither stop can be proven '
        'safe; `qa fleet stop ${member.name} --force` once you are sure the '
        'qemu is hung',
      );
      left.add('${member.name} qemu ${member.qemu!.pid} on a contested port');
    }

    // A stopped guest leaves its pid file, its URIs and possibly a crash
    // handler behind; looking again now is what lets one reap leave the
    // host clean instead of the next one.
    final rest = stopped ? await survey(prune: prune) : found;
    // The guard is not killed: with no guest left it exits by itself after
    // two empty polls, and one that a held guest keeps alive is still
    // needed.
    final guard = rest.guard;
    if (stopped && guard != null && rest.fleetUp.isEmpty) {
      say(
        'guard pid ${guard.pid} exits by itself within '
        '${guard.poll.inSeconds * guardEmptyPolls} s (no fleet guest is left)',
      );
    }
    final emulatorDir = _emulatorDir;
    for (final handler in rest.crashHandlers) {
      final what =
          'orphaned emulator crash handler ${handler.pid} '
          '(parent ${handler.parentPid} gone)';
      if (dryRun || emulatorDir == null) {
        say(would('end $what'));
        continue;
      }
      final result = await runner.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        crashHandlerKillScript(handler.pid, emulatorDir),
      ], timeout: const Duration(seconds: 30));
      final said = result.stdout.trim();
      if (said == 'killed' || said == 'gone') {
        say('ended $what');
      } else if (said == 'mismatch') {
        say(
          'left ${handler.pid}: it no longer looks like an orphaned '
          'emulator crash handler',
        );
      } else {
        failed = true;
        say('failed: crash handler ${handler.pid} — ${result.combined}');
        left.add('crash handler ${handler.pid}');
      }
    }

    for (final file in rest.staleFiles) {
      final name = File(file.path).uri.pathSegments.last;
      if (dryRun) {
        say(would('remove $name (${file.why})'));
        continue;
      }
      try {
        File(file.path).deleteSync();
        say('removed $name (${file.why})');
      } on PathNotFoundException {
        say('removed $name (${file.why}; it had gone already)');
      } on FileSystemException catch (e) {
        if (isGuardCopyName(name) &&
            File(file.path).parent.path == paths.buildQa) {
          // A guard of the old layout runs from it; without its pid file
          // it exits at its next poll, and the next reap removes the copy.
          say('left $name: a guard of the old layout still runs from it');
          left.add('$name (in use until its guard exits)');
          continue;
        }
        failed = true;
        say('failed: $name — ${e.message}');
        left.add(name);
      }
    }

    for (final dir in rest.passDirs) {
      final name = Directory(
        dir,
      ).uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (dryRun) {
        say(would('prune pass/$name'));
        continue;
      }
      try {
        Directory(dir).deleteSync(recursive: true);
        say('pruned pass/$name');
      } on PathNotFoundException {
        say('pruned pass/$name (it had gone already)');
      } on FileSystemException catch (e) {
        failed = true;
        say('failed: pass/$name — ${e.message}');
        left.add('pass/$name');
      }
    }
    return (left: left, failed: failed);
  }
}
