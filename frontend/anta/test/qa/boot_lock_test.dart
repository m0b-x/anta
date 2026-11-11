import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/qa/src/boot_lock.dart';
import '../../tool/qa/src/runner.dart' show Liveness;
import 'fake_sleep.dart';

void main() {
  late Directory root;
  late String path;
  late DateTime clock;
  late List<String> said;
  late Map<int, Liveness> processes;

  BootLockOwner owner(int pid, String avd, {DateTime? at}) => BootLockOwner(
    pid: pid,
    avd: avd,
    at: at ?? clock,
    checkout: r'D:\checkout',
  );

  void held(BootLockOwner by) =>
      File(path).writeAsStringSync(jsonEncode(by.toJson()));

  /// Takes the lock for pid 200 booting anta_qa_2; [onPoll] runs at each
  /// wait, after the clock moved on.
  Future<void> take({void Function()? onPoll}) => takeBootLock(
    path: path,
    me: owner(200, 'anta_qa_2'),
    liveness: (pid) async => processes[pid] ?? Liveness.gone,
    say: said.add,
    sleep: boundedSleep('the boot-lock wait', (d) {
      clock = clock.add(d);
      onPoll?.call();
    }, polls: 200),
    clock: () => clock,
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('anta_qa_boot_lock_');
    path = '${root.path}${Platform.pathSeparator}boot.lock';
    clock = DateTime(2026, 11, 11, 13);
    said = [];
    processes = {};
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('a free lock is taken at once and let go after', () async {
    await take();
    expect(BootLockOwner.read(path)?.pid, 200);
    expect(said, isEmpty);
    releaseBootLock(path, owner(200, 'anta_qa_2'));
    expect(File(path).existsSync(), isFalse);
  });

  test('a live boot is waited on, said once, and followed', () async {
    // Two boots starting together is what hung the fleet: the second one
    // starts only once the first has let go.
    processes[100] = Liveness.alive;
    held(owner(100, 'anta_qa_1'));
    var polls = 0;
    await take(
      onPoll: () {
        if (++polls == 5) File(path).deleteSync();
      },
    );
    expect(polls, 5);
    expect(said, [r'boot: waiting for anta_qa_1 (pid 100 from D:\checkout)']);
    expect(BootLockOwner.read(path)?.pid, 200);
  });

  test('a lock whose owner is gone is taken over', () async {
    held(owner(100, 'anta_qa_1'));
    await take();
    expect(said.single, contains('is gone — taking it over'));
    expect(BootLockOwner.read(path)?.pid, 200);
  });

  test(
    'an owner that cannot be checked is waited on, then overridden',
    () async {
      processes[100] = Liveness.unknown;
      held(owner(100, 'anta_qa_1'));
      final start = clock;
      await take();
      expect(clock.difference(start), greaterThanOrEqualTo(bootLockPatience));
      expect(said.last, startsWith('warning: boot: the boot lock of pid 100'));
      expect(BootLockOwner.read(path)?.pid, 200);
    },
  );

  test('a lock past its age is not believed for its live pid', () async {
    processes[100] = Liveness.alive;
    held(
      owner(
        100,
        'anta_qa_1',
        at: clock.subtract(bootLockStale + const Duration(minutes: 1)),
      ),
    );
    await take();
    expect(said.last, startsWith('warning: '));
    expect(BootLockOwner.read(path)?.pid, 200);
  });

  test('the same process re-enters its own lock', () async {
    // `fleet boot --all` boots its guests one after another in one process.
    held(owner(200, 'anta_qa_1'));
    await take();
    expect(said, isEmpty);
    expect(BootLockOwner.read(path)?.avd, 'anta_qa_2');
  });

  test('a lock taken over meanwhile is its new owner\'s to let go', () {
    held(owner(300, 'anta_qa_3'));
    releaseBootLock(path, owner(200, 'anta_qa_2'));
    expect(BootLockOwner.read(path)?.pid, 300);
  });
}
