import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../tool/qa/qa.dart'
    show
        DragCommand,
        MarkerReport,
        QaContext,
        TargetLookup,
        bootPidPath,
        describeFound,
        describePerf,
        emulatorWrapperName,
        expectMisses,
        presentMatch,
        runLogSkipNote;
import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/agent_client.dart';
import '../../tool/qa/src/agent_protocol.dart';
import '../../tool/qa/src/device.dart';
import '../../tool/qa/src/poll.dart';
import '../../tool/qa/src/runner.dart';
import '../../tool/qa/src/target.dart';
import '../../tool/qa/src/doctor.dart';
import '../../tool/qa/src/fleet.dart';
import '../../tool/qa/src/log_parse.dart';
import '../../tool/qa/src/paths.dart';
import '../../tool/qa/src/self_build.dart';
import '../../tool/qa/src/shots.dart';
import '../../tool/qa/src/ui_tree.dart';

UiNode _node(
  int index, {
  String desc = '',
  String text = '',
  String id = '',
  String className = 'android.view.View',
  bool clickable = false,
  bool scrollable = false,
  bool hidden = false,
  bool offscreen = false,
  int? semanticsId,
  int parent = 0,
  UiRect bounds = const UiRect(0, 0, 100, 100),
}) =>
    UiNode(
      index: index,
      parentIndex: parent,
      depth: parent == -1 ? 0 : 1,
      className: className,
      text: text,
      contentDesc: desc,
      resourceId: id,
      packageName: 'com.alexzamfir.anta',
      bounds: bounds,
      clickable: clickable,
      longClickable: false,
      enabled: true,
      focused: false,
      focusable: clickable,
      checked: false,
      checkable: false,
      selected: false,
      scrollable: scrollable,
      hidden: hidden,
      offscreen: offscreen,
      semanticsId: semanticsId,
    );

/// A "Walk" row as the review's probes drew them: clickable, 100 px tall at
/// [top], its semantics id [sid].
UiNode _walk(int index, {bool hidden = false, int top = 0, int? sid}) => _node(
      index,
      desc: 'Walk',
      clickable: true,
      hidden: hidden,
      semanticsId: sid,
      bounds: UiRect(0, top, 1000, top + 100),
    );

UiTree _agentTree(List<UiNode> rows) => UiTree(
      [_node(0, parent: -1, bounds: const UiRect(0, 0, 1000, 2000)), ...rows],
      source: UiTreeSource.agent,
    );

void main() {
  _hardeningTests();
  _reviewProbeTests();
  _harnessSourceScan();
  group('expectMisses', () {
    final tree = UiTree([
      _node(0, parent: -1, bounds: const UiRect(0, 0, 1000, 2000)),
      _node(1, desc: 'Search all notes', id: 'search-open', clickable: true),
      _node(2, desc: 'All notes\n3', id: 'drawer-all-notes', clickable: true),
      _node(3, desc: 'Loading', hidden: true),
    ]);

    test('present targets that resolve pass, missing ones are listed', () {
      expect(
        expectMisses(tree, present: ['id:search-open', 'Recent'], absent: []),
        ['missing "Recent"'],
      );
    });

    test('an ambiguous label still counts as present', () {
      expect(expectMisses(tree, present: ['All notes'], absent: []), isEmpty);
    });

    test('absent targets that are on screen are unexpected', () {
      expect(
        expectMisses(tree, present: [], absent: ['id:search-open', 'Nope']),
        ['unexpected "id:search-open" is on screen'],
      );
    });

    group('--ordered', () {
      // Three rows in traversal order, their rects deliberately not: the
      // order is the tree's, as the browser's selection mode needs.
      final rows = UiTree([
        _node(0, parent: -1, bounds: const UiRect(0, 0, 1000, 2000)),
        _node(1, desc: 'Inbox\n2 notes', bounds: const UiRect(0, 900, 1000, 1000)),
        _node(2, desc: 'Money', bounds: const UiRect(0, 100, 1000, 200)),
        _node(3, desc: 'Training', hidden: true),
      ]);

      test('passes when the targets come in traversal order', () {
        expect(
          expectMisses(rows,
              present: ['Inbox', 'Money', 'Training'], absent: [], ordered: true),
          isEmpty,
        );
      });

      test('names the pair that is out of order', () {
        expect(
          expectMisses(rows,
              present: ['Training', 'Inbox', 'Money'], absent: [], ordered: true),
          ['out of order: "Inbox" (node 1) comes before "Training" (node 3), '
              'not after it'],
        );
      });

      test('a missing target is reported once, not as an order miss', () {
        expect(
          expectMisses(rows, present: ['Inbox', 'Gym', 'Money'], absent: [], ordered: true),
          ['missing "Gym"'],
        );
      });

      test('without --ordered the order is not checked', () {
        expect(
          expectMisses(rows, present: ['Money', 'Inbox'], absent: []),
          isEmpty,
        );
      });
    });
  });

  group('describePerf', () {
    test('reads like one sample per phase', () {
      final text = describePerf({
        'frames': 120,
        'elapsedMs': 2000,
        'jank': 2,
        'recording': false,
        'build': {'p50': 1.2, 'p90': 3.4, 'max': 18.0},
        'raster': {'p50': 2.0, 'p90': 4.0, 'max': 9.0},
        'total': {'p50': 4.0, 'p90': 8.0, 'max': 24.0},
      });
      expect(text, startsWith('frames=120 over 2000 ms  jank=2 (build or raster over 16.7 ms)'));
      expect(text, contains('build p50 1.2 ms  p90 3.4 ms  max 18.0 ms'));
      expect(text, isNot(contains('still recording')));
      expect(describePerf({'recording': true}), contains('[still recording]'));
    });
  });

  group('hotReloadOutcome', () {
    test('recognises a finished reload and a restart', () {
      expect(
        hotReloadOutcome('Performing hot reload...\nReloaded 1 of 812 libraries in 412ms.\n'),
        (true, 'Reloaded 1 of 812 libraries in 412ms.'),
      );
      expect(
        hotReloadOutcome('Performing hot restart...\nRestarted application in 1,203ms.\n'),
        (true, 'Restarted application in 1,203ms.'),
      );
    });

    test('recognises a rejected reload and stays null while pending', () {
      final rejected = hotReloadOutcome(
        'Performing hot reload...\n'
        "lib/main.dart:12:3: Error: Expected ';' after this.\n"
        'Try again after fixing the above error(s).\n',
      );
      expect(rejected?.$1, isFalse);
      expect(rejected?.$2, contains('Error:'));
      expect(hotReloadOutcome('Performing hot reload...\n'), isNull);
    });
  });

  group('vmServiceUriFromLog', () {
    test('takes the last announced URI and strips trailing punctuation', () {
      const log = '09-16 21:00:01.000 I/flutter (123): The Dart VM service is listening on http://127.0.0.1:41234/abc=/.\n'
          '09-16 21:05:01.000 I/flutter (456): The Dart VM service is listening on http://127.0.0.1:45678/xyz=/\n';
      expect(vmServiceUriFromLog(log), 'http://127.0.0.1:45678/xyz=/');
    });

    test('is null when nothing was announced', () {
      expect(vmServiceUriFromLog('nothing here'), isNull);
    });
  });

  group('checkPendingMarkers', () {
    test('nothing pending is ok, a stale seed warns', () {
      expect(checkPendingMarkers(const []).status, CheckStatus.ok);
      final result = checkPendingMarkers(const ['qa_seed.json']);
      expect(result.status, CheckStatus.warn);
      expect(result.detail, contains('qa_seed.json'));
      expect(result.fix, contains('qa relaunch'));
    });
  });

  group('rebuild lock', () {
    late Directory temp;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('qa_lock');
    });

    tearDown(() => temp.deleteSync(recursive: true));

    test('the first taker wins and a fresh lock blocks the second', () {
      final lock = File('${temp.path}/rebuild.lock');
      expect(acquireRebuildLock(lock), isTrue);
      expect(acquireRebuildLock(lock), isFalse);
      releaseRebuildLock(lock);
      expect(lock.existsSync(), isFalse);
      expect(acquireRebuildLock(lock), isTrue);
    });

    test('a lock older than the ttl is reclaimed', () {
      final lock = File('${temp.path}/rebuild.lock')..createSync();
      final later = DateTime.now().add(rebuildLockTtl + const Duration(seconds: 1));
      expect(acquireRebuildLock(lock, now: later), isTrue);
    });

    test('QaPaths names the lock inside build/qa', () {
      expect(QaPaths(temp.path).rebuildLock, endsWith('rebuild.lock'));
    });
  });

  group('annotated screenshots', () {
    final tree = UiTree([
      _node(0, parent: -1, bounds: const UiRect(0, 0, 1000, 2000)),
      _node(1, desc: 'Search', className: 'android.widget.Button', clickable: true,
          bounds: const UiRect(800, 100, 900, 200)),
      _node(2, text: 'squat', className: 'android.widget.EditText',
          bounds: const UiRect(100, 100, 700, 180)),
      _node(3, scrollable: true, bounds: const UiRect(0, 300, 1000, 2000)),
      _node(4, desc: 'Off screen', clickable: true, hidden: true,
          bounds: const UiRect(0, 2500, 1000, 2600)),
      _node(5, bounds: const UiRect(0, 0, 1, 1)),
    ]);

    test('badgesFor scales, skips hidden and tiny nodes, and types the rest', () {
      final badges = badgesFor(tree, scale: 0.5, imageWidth: 500, imageHeight: 1000);
      expect(badges.map((b) => b.index), [1, 2, 3]);
      final search = badges.first;
      expect((search.left, search.top, search.right, search.bottom), (400, 50, 450, 100));
      expect(search.kind, 'click');
      expect(badges[1].kind, 'text');
      expect(badges[2].kind, 'scroll');
    });

    test('drawBadges paints the box outline and the tag', () {
      final image = img.Image(width: 500, height: 1000);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      drawBadges(image, badgesFor(tree, scale: 0.5, imageWidth: 500, imageHeight: 1000));
      final onOutline = image.getPixel(400, 75);
      expect(onOutline.r, 255);
      expect(onOutline.g, 92);
      final inside = image.getPixel(425, 90);
      expect(inside.r, 255);
      expect(inside.g, 255);
    });

    test('captureAnnotatedShot writes a PNG at the requested scale', () async {
      final temp = Directory.systemTemp.createTempSync('qa_look');
      addTearDown(() => temp.deleteSync(recursive: true));
      File('${temp.path}/pubspec.yaml').writeAsStringSync('name: anta');
      final paths = QaPaths(temp.path);
      final source = img.Image(width: 1000, height: 2000);
      img.fill(source, color: img.ColorRgb8(20, 20, 20));
      final png = img.encodePng(source);
      final path = await captureAnnotatedShot(
        () async => png,
        tree,
        paths,
        name: 'root',
        scale: 0.5,
        now: DateTime(2026, 9, 16, 21, 0, 0),
      );
      expect(path, endsWith('20260916_210000_000_root.png'));
      final decoded = img.decodePng(Uint8List.fromList(File(path).readAsBytesSync()))!;
      expect(decoded.width, 500);
      expect(decoded.height, 1000);
      expect(decoded.getPixel(400, 75).g, 92);
    });
  });

  group('fleet verbs are never destructive', () {
    const forbidden = [
      'delete',
      'wipe-data',
      'pm clear',
      'uninstall',
      'remove-item',
      'stop-process',
      'taskkill',
    ];
    void expectHarmless(Iterable<String> words, String what) {
      final text = words.join(' ').toLowerCase();
      for (final word in forbidden) {
        expect(text, isNot(contains(word)), reason: '$what carries "$word"');
      }
    }

    test('no vector a fleet verb emits deletes, wipes, clears or uninstalls', () {
      for (var index = 1; index <= fleetMaxIndex; index++) {
        expectHarmless(fleetEmulatorArgs(index), 'the emulator vector');
        expectHarmless(
          avdCreateArgs(
            fleetName(index),
            'system-images;android-36;google_apis_playstore;x86_64',
          ),
          'the avdmanager vector',
        );
        expectHarmless(
          fleetPassChildArgs(
            serial: fleetSerial(index),
            suite: 'calendar',
            shard: (1, index),
            jsonPath: 'shard.json',
            label: 'label',
            stopOnFail: true,
            via: 'agent',
            verbose: true,
          ),
          'a pass child',
        );
        expectHarmless(fleetInstallChildArgs(fleetSerial(index)), 'an install child');
        expectHarmless([pinScript(1000 + index, 0xFFFF)], 'the pin script');
        expectHarmless([minimizeWindowScript(1000 + index)], 'the minimize script');
      }
      expectHarmless([qemuWindowScript], 'the window script');
      for (final grant in passGrants) {
        expectHarmless(grant.command, 'the ${grant.what} grant');
      }
      expectHarmless(fleetBuildChildArgs(verbose: true), 'the build child');
      expectHarmless(fleetBootChildArgs(fleetName(1), verbose: true), 'the boot child');
      expectHarmless([gpuMemoryScript([1, 2]), cpuSecondsScript(1)], 'the health scripts');
      expectHarmless(emuAvdNameArgs, 'emu avd name');
      expectHarmless(emuKillArgs, 'emu kill');
      expectHarmless(
        [qemuListScript, cpuTopologyScript, avdCreateStdin],
        'the PowerShell scripts',
      );
      expect(avdCreateArgs('anta_qa_1', 'image'), isNot(contains('--force')));
    });

    test('fleet.dart spells a destructive command only in its two guarded '
        'stops', () {
      const path = 'tool/qa/src/fleet.dart';
      expect(scanHarnessSources({path: File(path).readAsStringSync()}), {
        path: {
          'emuKillArgs': {'emu kill'},
          'FleetHost.stop': {'emu kill'},
          'forceStopScript': {'Stop-Process'},
          'FleetHost.forceStop': {'Process.killPid'},
        },
      });
    });
  });
}

void _hardeningTests() {
  group('pollUntil', () {
    test('returns the first non-null probe result', () async {
      var calls = 0;
      final result = await pollUntil<int>(
        timeout: const Duration(seconds: 1),
        interval: const Duration(milliseconds: 1),
        probe: () => ++calls >= 3 ? calls : null,
      );
      expect(result, 3);
    });

    test('gives up with null at the deadline after a last try', () async {
      var calls = 0;
      final result = await pollUntil<int>(
        timeout: const Duration(milliseconds: 20),
        interval: const Duration(milliseconds: 5),
        probe: () {
          calls++;
          return null;
        },
      );
      expect(result, isNull);
      expect(calls, greaterThan(1));
    });
  });

  group('readAppended', () {
    test('returns only the bytes past the offset', () {
      final temp = Directory.systemTemp.createTempSync('qa_tail');
      addTearDown(() => temp.deleteSync(recursive: true));
      final file = File('${temp.path}/run.log')..writeAsStringSync('first\n');
      final offset = file.lengthSync();
      file.writeAsStringSync('second\n', mode: FileMode.append);
      expect(readAppended(file.path, offset), 'second\n');
      expect(readAppended(file.path, file.lengthSync()), '');
      expect(readAppended('${temp.path}/missing', 0), '');
    });
  });

  group('MarkerReport', () {
    AgentInfo info(List<QaOutcome> outcomes) => AgentInfo(
          platform: 'iOS',
          dpr: 3,
          width: 1,
          height: 1,
          lifecycle: 'resumed',
          semanticsEnabled: true,
          textClient: false,
          documentsPath: null,
          qaMode: true,
          database: 'qa',
          qaLog: outcomes.map((o) => o.message).toList(),
          qaOutcomes: outcomes,
          uptimeMs: 0,
          protocolVersion: 1,
        );

    test('typed outcomes decide success, not wording', () {
      final report = MarkerReport.fromOutcomes(info(const [
        QaOutcome(kind: 'reset', ok: true, message: 'reset: whatever'),
        QaOutcome(kind: 'seed', ok: false, message: 'seed: rejected'),
      ]));
      expect(report.hasReset, isTrue);
      expect(report.hasSeed, isTrue);
      expect(report.seedFailed, isTrue);
      expect(report.resetFailed, isFalse);
      expect(report.satisfies(reset: true, seed: true), isTrue);
      expect(report.source, 'agent');
    });

    test('a refused reset is a failure even though a reset line exists', () {
      final report = MarkerReport.fromOutcomes(info(const [
        QaOutcome(kind: 'reset', ok: false, message: 'reset refused: owner db'),
      ]));
      expect(report.hasReset, isTrue);
      expect(report.resetFailed, isTrue);
      final text = MarkerReport.fromText(
        '[qa] reset refused: ANTA_QA_DB is "gym_notes", which is the owner database\n',
        'logcat',
      );
      expect(text.resetFailed, isTrue);
      expect(text.satisfies(reset: true, seed: false), isTrue);
    });

    test('log text still works when the agent is not there', () {
      final report = MarkerReport.fromText(
        'I/flutter: [qa] reset: cleared preferences and qa.db\n'
        'I/flutter: [qa] seed: imported 4 folders, 3 notes\n',
        'logcat',
      );
      expect(report.lines, hasLength(2));
      expect(report.satisfies(reset: true, seed: true), isTrue);
      expect(report.seedFailed, isFalse);
    });
  });

  group('probesFor', () {
    test('a hint decides which platform tools are asked', () {
      expect(QaContext.probesFor(null), (true, true));
      expect(QaContext.probesFor('macos'), (false, false));
      expect(QaContext.probesFor('ios'), (false, true));
      expect(QaContext.probesFor('B57A8680-5A8F-4010-96BE-7524481996B1'), (false, true));
      expect(QaContext.probesFor('android'), (true, false));
      expect(QaContext.probesFor('emulator-5554'), (true, false));
      expect(QaContext.probesFor('192.168.1.5:5555'), (true, false));
      expect(QaContext.probesFor('iPhone 17 Pro'), (true, true));
    });
  });

  group('hidden nodes and targets', () {
    final tree = UiTree([
      _node(0, parent: -1, bounds: const UiRect(0, 0, 1000, 2000)),
      _node(1, desc: 'Row', clickable: true, bounds: const UiRect(0, 100, 1000, 200)),
      _node(2, desc: 'Row', clickable: true, hidden: true,
          bounds: const UiRect(0, 2500, 1000, 2600)),
      _node(3, desc: 'Cached only', clickable: true, hidden: true,
          bounds: const UiRect(0, 2600, 1000, 2700)),
    ]);

    test('a visible match wins over a hidden duplicate', () {
      final resolved = TargetResolver(tree).resolve('Row');
      expect(resolved.node!.index, 1);
    });

    test('an only-hidden match still resolves, so tap can explain', () {
      expect(TargetResolver(tree).resolve('Cached only').node!.hidden, isTrue);
    });

    test('expect counts a node scrolled out of view as present', () {
      expect(expectMisses(tree, present: ['Cached only'], absent: []), isEmpty);
      expect(
        expectMisses(tree, present: [], absent: ['Cached only']),
        ['unexpected "Cached only" is present (scrolled out of view)'],
      );
    });

    test('--absent passes only when no node resolves at all', () {
      expect(expectMisses(tree, present: [], absent: ['Never drawn']), isEmpty);
      expect(
        expectMisses(tree, present: ['Never drawn'], absent: ['Row']),
        ['missing "Never drawn"', 'unexpected "Row" is on screen'],
      );
    });

    test('wait finds a scrolled-out node and says where it is', () {
      final found = presentMatch(tree, 'Cached only', gone: false)!;
      expect(found.node!.index, 3);
      expect(describeFound(found), endsWith('  (scrolled out of view)'));
      expect(describeFound(presentMatch(tree, 'Row', gone: false)!),
          isNot(contains('scrolled out')));
    });

    test('wait --gone is satisfied only when nothing resolves', () {
      expect(presentMatch(tree, 'Cached only', gone: true), isNotNull);
      expect(presentMatch(tree, 'Never drawn', gone: true), isNull);
      expect(presentMatch(tree, 'Never drawn', gone: false), isNull);
    });

    test('wait refuses an ambiguous label it could never settle on', () {
      final twice = UiTree([
        _node(0, parent: -1, bounds: const UiRect(0, 0, 1000, 2000)),
        _node(1, desc: 'Same', bounds: const UiRect(0, 0, 100, 100)),
        _node(2, desc: 'Same', bounds: const UiRect(0, 100, 100, 200)),
      ]);
      expect(() => presentMatch(twice, 'Same', gone: false),
          throwsA(isA<TargetFailure>()));
      expect(presentMatch(twice, 'Same', gone: false, nth: 1)!.node!.index, 2);
    });
  });

  group('resolveRevealing', () {
    UiNode row({required bool hidden, int top = 2600}) => UiNode(
          index: 3,
          parentIndex: 0,
          depth: 1,
          className: 'View',
          text: '',
          contentDesc: '',
          resourceId: 'fasting-extra-days',
          packageName: 'com.alexzamfir.anta',
          bounds: UiRect(0, top, 1000, top + 100),
          clickable: true,
          longClickable: false,
          enabled: true,
          focused: false,
          focusable: true,
          checked: false,
          checkable: false,
          selected: false,
          scrollable: false,
          hidden: hidden,
          semanticsId: 88,
        );
    UiTree screen(UiNode node) => UiTree([
          _node(0, parent: -1, bounds: const UiRect(0, 0, 1000, 2000)),
          node,
        ], source: UiTreeSource.agent);

    test('a hidden match is revealed by its id, then read from the new dump', () async {
      final revealed = <int?>[];
      var dumps = 0;
      final outcome = await resolveRevealing(
        'id:fasting-extra-days',
        screen(row(hidden: true)),
        reveal: (node) async => revealed.add(node.semanticsId),
        redump: () async {
          dumps++;
          return screen(row(hidden: false, top: 1500));
        },
      );
      expect(revealed, [88]);
      expect(dumps, 1);
      expect(outcome.revealed, isTrue);
      expect(outcome.onScreen, isTrue);
      expect(outcome.resolved.y, 1550);
    });

    test('a visible match is acted on without asking the app', () async {
      final outcome = await resolveRevealing(
        'id:fasting-extra-days',
        screen(row(hidden: false, top: 300)),
        reveal: (_) async => fail('nothing to reveal'),
        redump: () async => fail('no second dump'),
      );
      expect(outcome.revealed, isFalse);
      expect(outcome.resolved.y, 350);
    });

    test('a node still hidden after the reveal is reported, not tapped', () async {
      final outcome = await resolveRevealing(
        'id:fasting-extra-days',
        screen(row(hidden: true)),
        reveal: (_) async {},
        redump: () async => screen(row(hidden: true)),
      );
      expect(outcome.revealed, isTrue);
      expect(outcome.onScreen, isFalse);
      expect(offScreenAfterReveal('id:fasting-extra-days'),
          startsWith('"id:fasting-extra-days" is off screen even after asking '
              'the app to scroll it into view; scroll-to it first'));
    });

    test('the adb path has no reveal and keeps the hidden match', () async {
      final outcome = await resolveRevealing(
        'id:fasting-extra-days',
        screen(row(hidden: true)),
        reveal: null,
        redump: () async => fail('no second dump'),
      );
      expect(outcome.revealed, isFalse);
      expect(outcome.onScreen, isFalse);
    });

    test('a target gone from the new dump fails as a missing target', () async {
      expect(
        () => resolveRevealing(
          'id:fasting-extra-days',
          screen(row(hidden: true)),
          reveal: (_) async {},
          redump: () async => UiTree([_node(0, parent: -1)]),
        ),
        throwsA(isA<TargetFailure>()),
      );
    });
  });

  group('chooseDriver', () {
    test('auto picks the agent only when it can be reached', () {
      expect(chooseDriver(hasNative: true, vmRecorded: true, agentAnswers: true),
          ViaMode.agent);
      expect(chooseDriver(hasNative: true, vmRecorded: true, agentAnswers: false),
          ViaMode.native);
      expect(chooseDriver(hasNative: true, vmRecorded: false, agentAnswers: false),
          ViaMode.native);
      expect(chooseDriver(hasNative: true, vmRecorded: false, agentAnswers: true),
          ViaMode.native);
    });

    test('without a native layer the agent is the only choice', () {
      for (final vm in [true, false]) {
        for (final answers in [true, false]) {
          expect(chooseDriver(hasNative: false, vmRecorded: vm, agentAnswers: answers),
              ViaMode.agent);
        }
      }
    });
  });

  group('runLogSkipNote', () {
    test('run.log is evidence only for the device its flutter run serves', () {
      expect(runLogSkipNote(runDevice: 'emulator-5556', deviceId: 'emulator-5556'), isNull);
      expect(runLogSkipNote(runDevice: 'emulator-5554', deviceId: 'emulator-5556'),
          'run.log: belongs to emulator-5554, skipped');
      expect(runLogSkipNote(runDevice: null, deviceId: 'emulator-5556'),
          'run.log: belongs to no recorded run, skipped');
      expect(runLogSkipNote(runDevice: '', deviceId: 'emulator-5556'),
          'run.log: belongs to no recorded run, skipped');
    });
  });

  test('checkScreenOverride tolerates an unknown screen', () {
    expect(checkScreenOverride(const DeviceProbe()).status, CheckStatus.warn);
  });
}

/// The cases Review 1 reproduced with its probe scripts, and the presence
/// rule that separates a scrolled-out row from a route still sliding in.
void _reviewProbeTests() {
  group('a reveal is followed by the semantics id', () {
    final threeHidden = _agentTree([
      _walk(1, hidden: true, top: 2500, sid: 11),
      _walk(2, hidden: true, top: 2700, sid: 12),
      _walk(3, hidden: true, top: 2900, sid: 13),
    ]);
    // After revealing, row 11 scrolled above the fold and 12 and 13 are on
    // screen: by position among the visible rows, --nth 1 would be 13.
    final afterReveal = _agentTree([
      _walk(1, hidden: true, top: -300, sid: 11),
      _walk(2, top: 1500, sid: 12),
      _walk(3, top: 1700, sid: 13),
    ]);

    for (final (nth, sid) in [(0, 11), (1, 12), (2, 13)]) {
      test('--nth $nth acts on the row it revealed (sid $sid)', () async {
        final revealed = <int?>[];
        final outcome = await resolveRevealing(
          'Walk',
          threeHidden,
          nth: nth,
          reveal: (node) async => revealed.add(node.semanticsId),
          redump: () async => afterReveal,
        );
        expect(revealed, [sid]);
        expect(outcome.resolved.node!.semanticsId, sid);
        expect(outcome.note, isNull);
      });
    }

    test('a hidden duplicate of a visible label is reachable by --nth', () async {
      final duplicate = _agentTree([
        _walk(1, top: 300, sid: 21),
        _walk(2, hidden: true, top: 2700, sid: 22),
      ]);
      expect(TargetResolver(duplicate).resolve('Walk').node!.semanticsId, 21,
          reason: 'without --nth the row on screen still wins');
      final outcome = await resolveRevealing(
        'Walk',
        duplicate,
        nth: 1,
        reveal: (_) async {},
        redump: () async => _agentTree([
          _walk(1, hidden: true, top: -500, sid: 21),
          _walk(2, top: 1400, sid: 22),
        ]),
      );
      expect(outcome.resolved.node!.semanticsId, 22);
      expect(outcome.resolved.y, 1450);
    });

    test('--nth counts in traversal order, and the ambiguity listing agrees', () {
      final mixed = _agentTree([
        _walk(1, hidden: true, top: 2500, sid: 31),
        _walk(2, top: 300, sid: 32),
        _walk(3, top: 500, sid: 33),
      ]);
      expect(TargetResolver(mixed).resolve('Walk', nth: 0).node!.semanticsId, 31);
      expect(
        () => TargetResolver(mixed).resolve('Walk'),
        throwsA(isA<TargetFailure>().having((e) => e.message, 'message',
            allOf(contains('2 matches'), contains('--nth 1  #2'), contains('--nth 2  #3')))),
      );
    });

    test('an id gone after the reveal falls back to the label once, and says so', () async {
      final outcome = await resolveRevealing(
        'Walk',
        threeHidden,
        nth: 2,
        reveal: (_) async {},
        redump: () async => _agentTree([
          _walk(1, top: 300, sid: 41),
          _walk(2, top: 500, sid: 42),
          _walk(3, top: 700, sid: 43),
        ]),
      );
      expect(outcome.resolved.node!.semanticsId, 43);
      expect(outcome.note, contains('(semantics id 13) is not in the new dump'));
    });

    test('a hidden #N is revealed by its id; from a uiautomator dump it is not', () async {
      final revealed = <int?>[];
      final outcome = await resolveRevealing(
        '#2',
        threeHidden,
        reveal: (node) async => revealed.add(node.semanticsId),
        redump: () async => afterReveal,
      );
      expect(revealed, [12]);
      expect(outcome.onScreen, isTrue);
      expect(outcome.resolved.y, 1550);

      final uiautomator = UiTree([
        _node(0, parent: -1, bounds: const UiRect(0, 0, 1000, 2000)),
        _node(1, desc: 'Walk', hidden: true),
      ]);
      final kept = await resolveRevealing(
        '#1',
        uiautomator,
        reveal: (_) async => fail('no id to reveal by'),
        redump: () async => fail('no second dump'),
      );
      expect(kept.revealed, isFalse);
      expect(kept.onScreen, isFalse);

      await expectLater(
        resolveRevealing('#2', threeHidden, reveal: (_) async {}, redump: () async => _agentTree([])),
        throwsA(isA<TargetFailure>()),
      );
    });

    test('drag reads the dragged row again by its id after the drop target scrolled', () {
      final before = TargetLookup(
        resolved: TargetResolver(afterReveal).resolve('Walk', nth: 1),
        tree: afterReveal,
      );
      final scrolled = _agentTree([
        _walk(1, top: 200, sid: 11),
        _walk(2, top: 400, sid: 12),
        _walk(3, hidden: true, top: 2600, sid: 13),
      ]);
      final notes = <String>[];
      final again = DragCommand.afterDropReveal('Walk', before, scrolled, 1, note: notes.add);
      expect(again.resolved.node!.semanticsId, 12);
      expect(again.resolved.y, 450);
      expect(notes, isEmpty);

      final renumbered = _agentTree([_walk(1, top: 200, sid: 51), _walk(2, top: 400, sid: 52)]);
      final fallback =
          DragCommand.afterDropReveal('Walk', before, renumbered, 1, note: notes.add);
      expect(fallback.resolved.node!.semanticsId, 52);
      expect(notes.single, contains('semantics id 12'));
    });
  });

  group('an ambiguous match is never gone (the --gone probe)', () {
    final twoHidden = _agentTree([
      _walk(1, hidden: true, top: 2500),
      _walk(2, hidden: true, top: 2700),
    ]);

    test('wait --gone keeps waiting while two hidden rows match', () {
      expect(presentMatch(twoHidden, 'Walk', gone: true), isNotNull);
      expect(presentMatch(twoHidden, 'Run', gone: true), isNull);
    });

    test('--absent reports an all-hidden ambiguous label as scrolled out of view', () {
      expect(expectMisses(twoHidden, present: [], absent: ['Walk']),
          ['unexpected "Walk" is present (scrolled out of view)']);
      final oneShown = _agentTree([_walk(1, top: 300), _walk(2, hidden: true, top: 2700)]);
      expect(expectMisses(oneShown, present: [], absent: ['Walk']),
          ['unexpected "Walk" is on screen']);
    });
  });

  group('presence: hidden by the framework vs outside the screen', () {
    UiTree screenWith(UiNode node) => _agentTree([node]);
    final sliding = _node(1, desc: 'Event', clickable: true, offscreen: true, semanticsId: 7,
        bounds: const UiRect(1100, 300, 2000, 400));
    final scrolledOut = _node(1, desc: 'Event', clickable: true, hidden: true, semanticsId: 7,
        bounds: const UiRect(0, 2500, 1000, 2600));
    final both = _node(1, desc: 'Event', clickable: true, hidden: true, offscreen: true,
        semanticsId: 7, bounds: const UiRect(0, 2500, 1000, 2600));

    test('a node only outside the screen does not count yet, so wait polls on', () {
      expect(presentMatch(screenWith(sliding), 'Event', gone: false), isNull);
      expect(expectMisses(screenWith(sliding), present: ['Event'], absent: []),
          ['missing "Event"']);
    });

    test('a node the framework hides counts, with or without an off-screen rect', () {
      for (final node in [scrolledOut, both]) {
        expect(presentMatch(screenWith(node), 'Event', gone: false), isNotNull);
        expect(expectMisses(screenWith(node), present: ['Event'], absent: []), isEmpty);
      }
    });

    test('absence still means no match at all', () {
      expect(presentMatch(screenWith(sliding), 'Event', gone: true), isNotNull);
      expect(expectMisses(screenWith(sliding), present: [], absent: ['Event']), hasLength(1));
    });

    test('both kinds are out of view: listed apart, revealed before acting', () async {
      expect(sliding.outOfView, isTrue);
      expect(sliding.interesting, isFalse);
      expect(sliding.flags, contains('offscreen'));
      expect(sliding.flags, isNot(contains('hidden')));
      expect(sliding.toJson()['offscreen'], isTrue);
      final revealed = <int?>[];
      await resolveRevealing('Event', screenWith(sliding),
          reveal: (node) async => revealed.add(node.semanticsId),
          redump: () async => screenWith(_node(1, desc: 'Event', semanticsId: 7)));
      expect(revealed, [7]);
    });

    test('the agent dump carries the two flags apart; an older dump reads as before', () {
      UiNode parse(List<String> flags) => UiTree.fromAgentMap({
            AgentKeys.nodes: [
              {
                AgentNodeKeys.index: 0,
                AgentNodeKeys.rect: [0, 0, 10, 10],
                AgentNodeKeys.label: 'x',
                AgentNodeKeys.flags: flags,
              },
            ],
          }, appPackage: 'com.alexzamfir.anta').nodes.single;
      final split = parse([AgentFlags.offscreen]);
      expect((split.hidden, split.offscreen, split.countsAsPresent), (false, true, false));
      final old = parse([AgentFlags.hidden]);
      expect((old.hidden, old.offscreen, old.countsAsPresent), (true, false, true));
    });
  });

  group('the auto driver', () {
    test('says why it fell back to adb', () {
      expect(
        autoFallbackNote(vmRecorded: true, deviceId: 'emulator-5556'),
        'note: driver auto → adb (the agent did not answer within 2 s; '
        '`qa relaunch` brings it back)',
      );
      expect(autoFallbackNote(vmRecorded: false, deviceId: 'emulator-5556'),
          contains('no VM URI is recorded for emulator-5556'));
    });
  });

  group('boot files', () {
    final paths = QaPaths('/repo');

    test("a plain boot waits only on emulator.pid, never a fleet AVD's", () {
      expect(bootPidPath(paths, null), paths.emulatorPid);
      expect(bootPidPath(paths, ''), paths.emulatorPid);
      expect(bootPidPath(paths, 'anta_qa_1'), paths.emulatorPidFor('anta_qa_1'));
      expect(bootPidPath(paths, 'anta_qa_1'), isNot(paths.emulatorPid));
    });

    test('every AVD boots through its own wrapper script', () {
      expect(emulatorWrapperName('Pixel_9_Pro'), 'emulator_cmd_Pixel_9_Pro');
      expect(emulatorWrapperName('anta_qa_1'), isNot(emulatorWrapperName('anta_qa_2')));
    });
  });
}

/// No file of the harness spells a command that destroys a device, an AVD,
/// app data or a host process — outside the places where stopping
/// something is the verb's whole job and a guard sits in front of it.
void _harnessSourceScan() {
  group('the harness spells no destructive command', () {
    // Where a stop is the job, each guarded, keyed by file and declaration:
    // `kill-run` ends the tool's own recorded `flutter run`
    // (killRecordedRun); `doctor --fix` reaps only orphaned DDS processes
    // (_orphanedDdsScript, run by reapOrphanedServices); `fleet stop` asks
    // a fleet console only after it names its AVD (emuKillArgs,
    // FleetHost.stop, the verb's help line);
    // `fleet stop --force` kills a qemu only while its command line names
    // that fleet AVD on its port (forceStopScript, FleetHost.forceStop); hot
    // reload signals the recorded `flutter run` (HotCodeCommand.run).
    const sanctioned = <String, Map<String, Set<String>>>{
      'tool/qa/qa.dart': {
        'FleetStopCommand.description': {'emu kill'},
        'HotCodeCommand.run': {'Process.killPid'},
      },
      'tool/qa/src/fleet.dart': {
        'emuKillArgs': {'emu kill'},
        'FleetHost.stop': {'emu kill'},
        'forceStopScript': {'Stop-Process'},
        'FleetHost.forceStop': {'Process.killPid'},
      },
      'tool/qa/src/runner.dart': {
        'killRecordedRun': {'taskkill', 'Process.killPid'},
        '_orphanedDdsScript': {'Stop-Process'},
        'reapOrphanedServices': {'Stop-Process'},
      },
    };

    test('every hit under tool/qa and test_driver is a sanctioned one', () {
      final files = [
        for (final root in ['tool/qa', 'test_driver'])
          ...Directory(root).listSync(recursive: true).whereType<File>(),
      ];
      expect(files.length, greaterThan(40));
      final sources = {
        for (final file in files)
          file.path.replaceAll(r'\', '/'): file.readAsStringSync(),
      };
      expect(scanHarnessSources(sources), sanctioned);
    });

    group('the scanner', () {
      Map<String, Map<String, Set<String>>> scan(String source) =>
          scanHarnessSources({'tool/qa/src/x.dart': source});

      test('flags the one-string and the argv-list spelling alike', () {
        expect(scan('''
Future<void> wipe(Adb adb) async {
  await adb.shell(['pm', 'clear', antaPackage]);
  await adb.raw(['emu', 'kill']);
  await run('adb shell pm clear com.x');
  await run('rm', ['-rf', '/data/x']);
  await run('powershell', ['Stop-Process -Id 1']);
  await run('avdmanager', ['delete', 'avd', '-n', 'x']);
  await run('emulator', ['-avd', 'x', '-wipe-data']);
  await run('adb', ['uninstall', 'com.x']);
  await run('taskkill', ['/PID', '1']);
}
'''), {
          'tool/qa/src/x.dart': {
            'wipe': {
              'pm clear',
              'emu kill',
              'rm -rf',
              'Stop-Process',
              'delete avd',
              '-wipe-data',
              'uninstall',
              'taskkill',
            },
          },
        });
      });

      test('follows a constant that holds a vector to where it is used', () {
        expect(scan('''
const List<String> killArgs = ['emu', 'kill'];

class Host {
  Future<void> stop() => adb.raw(killArgs);

  Future<void> list() => adb.raw(['devices']);
}
'''), {
          'tool/qa/src/x.dart': {
            'killArgs': {'emu kill'},
            'Host.stop': {'emu kill'},
          },
        });
      });

      test('flags Process.killPid in code, never in a comment or a string', () {
        expect(scan('''
// Process.killPid(1) is how not to do it.
void reap(int pid) {
  final note = 'Process.killPid is refused';
  Process.killPid(pid, ProcessSignal.sigkill);
}
'''), {
          'tool/qa/src/x.dart': {
            'reap': {'Process.killPid'},
          },
        });
      });

      test('ignores comments, unrelated words and interpolated code', () {
        expect(scan('''
/// Never `pm clear` and never `emu kill` by hand.
String clearLine(String pm) => '\${pm} cleared, killed nothing';
const List<String> grant = ['pm', 'grant', 'x'];
'''), isEmpty);
      });
    });
  });
}

/// The destructive commands the harness must never spell outside a
/// guarded stop, matched against each string literal and against each run
/// of literals only commas separate (an argument list: `['pm', 'clear']`).
final Map<String, RegExp> _destructive = {
  'pm clear': RegExp(r'\bpm\s+clear\b', caseSensitive: false),
  'uninstall': RegExp('uninstall', caseSensitive: false),
  '-wipe-data': RegExp('-wipe-data', caseSensitive: false),
  'delete avd': RegExp(r'\bdelete\s+avd\b|\bavdmanager\b.*\bdelete\b',
      caseSensitive: false),
  'rm -rf': RegExp(r'\brm\s+(?:-\w*r\w*f|-\w*f\w*r|-r\s+-f|-f\s+-r)',
      caseSensitive: false),
  'emu kill': RegExp(r'\bemu\s+kill\b', caseSensitive: false),
  'Stop-Process': RegExp('stop-process', caseSensitive: false),
  'taskkill': RegExp('taskkill', caseSensitive: false),
  'Remove-Item': RegExp('remove-item', caseSensitive: false),
};

/// A process killed by pid, in code.
final RegExp _killPid = RegExp(r'\bProcess\s*\.\s*killPid\b');

/// Every destructive spelling in [sources] (path → text), by file, then by
/// the declaration it sits in (`Class.member` or a top-level name), then
/// by rule. A Dart file is lexed — comments dropped, string literals and
/// argument lists read — and a top-level or static constant found holding
/// a vector is followed to every declaration that names it; any other file
/// (the wrappers, the flows) is read line by line.
Map<String, Map<String, Set<String>>> scanHarnessSources(
  Map<String, String> sources,
) {
  final found = <String, Map<String, Set<String>>>{};
  void add(String file, String owner, String rule) => found
      .putIfAbsent(file, () => {})
      .putIfAbsent(owner, () => {})
      .add(rule);

  final lexed = <String, _Lexed>{};
  final constants = <String, Set<String>>{};
  sources.forEach((path, text) {
    if (!path.endsWith('.dart')) {
      for (final line in text.split('\n')) {
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('#') ||
            trimmed.startsWith('::') ||
            trimmed.toUpperCase().startsWith('REM ')) {
          continue;
        }
        _destructive.forEach((rule, pattern) {
          if (pattern.hasMatch(line)) add(path, '(file)', rule);
        });
      }
      return;
    }
    final lex = lexed[path] = _Lexed(text);
    for (final hit in lex.hits()) {
      add(path, hit.owner, hit.rule);
      if (lex.isConstant(hit.owner)) {
        constants.putIfAbsent(hit.owner, () => {}).add(hit.rule);
      }
    }
  });
  constants.forEach((name, rules) {
    final use = RegExp('\\b${RegExp.escape(name)}\\b');
    lexed.forEach((path, lex) {
      for (final match in use.allMatches(lex.code)) {
        final owner = lex.ownerAt(match.start);
        if (owner == null || owner == name) continue;
        for (final rule in rules) {
          add(path, owner, rule);
        }
      }
    });
  });
  return found;
}

/// One Dart source as the scan reads it: [code] with every comment and
/// string literal blanked (offsets and newlines kept), the literals
/// themselves, and the declaration each line belongs to, from the layout
/// `dart format` gives (top level at column 0, class members at 2).
class _Lexed {
  _Lexed(this.source) {
    _codeUnits = source.codeUnits.toList();
    _inside = List.filled(source.length, false);
    var i = 0;
    while (i < source.length) {
      if (source.startsWith('//', i)) {
        final end = source.indexOf('\n', i);
        i = _blank(i, end < 0 ? source.length : end);
      } else if (source.startsWith('/*', i)) {
        final end = source.indexOf('*/', i + 2);
        i = _blank(i, end < 0 ? source.length : end + 2);
      } else if (_stringStartsAt(i)) {
        i = _string(i);
      } else {
        i++;
      }
    }
    code = String.fromCharCodes(_codeUnits);
    _readOwners();
  }

  final String source;
  late final String code;
  late final List<int> _codeUnits;
  late final List<bool> _inside;
  /// Every literal; a [nested] one sits inside another's interpolation.
  final List<({int start, int end, String text, bool nested})> strings = [];
  var _nesting = 0;
  final List<int> _lineStarts = [];
  final List<String?> _owners = [];
  final Set<String> _constants = {};

  bool isConstant(String owner) => _constants.contains(owner);

  int _blank(int from, int to) {
    for (var k = from; k < to; k++) {
      _inside[k] = true;
      if (_codeUnits[k] != 0x0A && _codeUnits[k] != 0x0D) _codeUnits[k] = 0x20;
    }
    return to;
  }

  bool _isIdentifierChar(int unit) =>
      (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x41 && unit <= 0x5A) ||
      (unit >= 0x61 && unit <= 0x7A) ||
      unit == 0x5F ||
      unit == 0x24;

  bool _stringStartsAt(int i) {
    final c = source[i];
    if (c == "'" || c == '"') return true;
    return c == 'r' &&
        i + 1 < source.length &&
        (source[i + 1] == "'" || source[i + 1] == '"') &&
        (i == 0 || !_isIdentifierChar(source.codeUnitAt(i - 1)));
  }

  /// Reads the literal at [start] into [strings] and returns where it
  /// ends; an interpolation's code counts as one blank, so no command can
  /// be assembled from a variable's name.
  int _string(int start) {
    var j = start;
    final raw = source[j] == 'r';
    if (raw) j++;
    final quote = source[j];
    final triple = source.startsWith(quote * 3, j);
    final delimiter = triple ? quote * 3 : quote;
    j += delimiter.length;
    final text = StringBuffer();
    while (j < source.length) {
      if (source.startsWith(delimiter, j)) {
        j += delimiter.length;
        break;
      }
      final c = source[j];
      if (!triple && c == '\n') break;
      if (!raw && c == r'\' && j + 1 < source.length) {
        text.write(source[j + 1]);
        j += 2;
      } else if (!raw && c == r'$' && j + 1 < source.length && source[j + 1] == '{') {
        _nesting++;
        j = _interpolation(j + 2);
        _nesting--;
        text.write(' ');
      } else {
        text.write(c);
        j++;
      }
    }
    strings.add((start: start, end: j, text: text.toString(), nested: _nesting > 0));
    return _blank(start, j);
  }

  int _interpolation(int from) {
    var depth = 1;
    var j = from;
    while (j < source.length) {
      final c = source[j];
      if (_stringStartsAt(j)) {
        j = _string(j);
        continue;
      }
      if (c == '{') depth++;
      if (c == '}' && --depth == 0) return j + 1;
      j++;
    }
    return j;
  }

  void _readOwners() {
    String? currentClass;
    String? owner;
    var offset = 0;
    for (final line in source.split('\n')) {
      _lineStarts.add(offset);
      final inCode = offset >= source.length || !_inside[offset];
      offset += line.length + 1;
      final trimmed = line.trim();
      final indent = line.length - line.trimLeft().length;
      if (!inCode ||
          trimmed.isEmpty ||
          trimmed.startsWith('//') ||
          trimmed.startsWith('@') ||
          trimmed.startsWith(')') ||
          trimmed.startsWith(']')) {
        _owners.add(owner);
        continue;
      }
      if (trimmed.startsWith('}')) {
        if (indent == 0) currentClass = null;
        _owners.add(owner);
        continue;
      }
      if (indent == 0) {
        final type = RegExp(
          r'^(?:(?:abstract|sealed|final|base|interface)\s+)*'
          r'(?:class|mixin|extension|enum)\s+(\w+)',
        ).firstMatch(trimmed);
        if (type != null) {
          owner = currentClass = type.group(1);
        } else if (!RegExp(r'^(?:import|export|part|library)\b').hasMatch(trimmed)) {
          final name = _declarationName(trimmed);
          if (name != null) {
            currentClass = null;
            owner = name;
            if (RegExp(r'^(?:const|final)\b').hasMatch(trimmed)) _constants.add(name);
          }
        }
      } else if (indent == 2 && currentClass != null) {
        final name = _declarationName(trimmed);
        if (name != null) {
          owner = '$currentClass.$name';
          if (RegExp(r'^static\s+(?:const|final)\b').hasMatch(trimmed)) {
            _constants.add(owner);
          }
        }
      }
      _owners.add(owner);
    }
  }

  static const Set<String> _keywords = {
    'if', 'for', 'while', 'switch', 'return', 'catch', 'assert', 'await',
  };

  static String? _declarationName(String line) {
    final typedef = RegExp(r'^typedef\s+(\w+)').firstMatch(line);
    if (typedef != null) return typedef.group(1);
    final accessor = RegExp(r'\b(?:get|set)\s+(\w+)').firstMatch(line);
    if (accessor != null) return accessor.group(1);
    final variable = RegExp(
      r'^(?:static\s+)?(?:const|final|var|late)\b.*?(\w+)\s*=(?![=>])',
    ).firstMatch(line);
    if (variable != null) return variable.group(1);
    for (final match in RegExp(r'(\w+)\s*(?:<[^()]*>)?\s*\(').allMatches(line)) {
      final name = match.group(1)!;
      if (!_keywords.contains(name)) return name;
    }
    return null;
  }

  /// The declaration the line holding [offset] belongs to.
  String? ownerAt(int offset) {
    var low = 0;
    var high = _lineStarts.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (_lineStarts[mid] <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return _owners[low];
  }

  /// Every destructive spelling: in one literal, across a run of literals
  /// only commas, blanks and an opening bracket separate (`run('rm',
  /// ['-rf', …])`), and `Process.killPid` in code.
  Iterable<({String owner, String rule})> hits() sync* {
    for (final nested in strings.where((s) => s.nested)) {
      for (final entry in _destructive.entries) {
        if (entry.value.hasMatch(nested.text)) {
          yield (owner: ownerAt(nested.start) ?? '(top)', rule: entry.key);
        }
      }
    }
    final ordered = strings.where((s) => !s.nested).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    var runStart = 0;
    for (var k = 0; k <= ordered.length; k++) {
      final joins = k > 0 &&
          k < ordered.length &&
          RegExp(r'^[\s,\[(]*$').hasMatch(code.substring(ordered[k - 1].end, ordered[k].start));
      if (k > 0 && !joins) {
        final run = ordered.sublist(runStart, k);
        final owner = ownerAt(run.first.start) ?? '(top)';
        final joined = run.map((s) => s.text).join(' ');
        for (final entry in _destructive.entries) {
          if (entry.value.hasMatch(joined)) yield (owner: owner, rule: entry.key);
        }
        runStart = k;
      }
    }
    for (final match in _killPid.allMatches(code)) {
      yield (owner: ownerAt(match.start) ?? '(top)', rule: 'Process.killPid');
    }
  }
}
