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
      expectHarmless(emuAvdNameArgs, 'emu avd name');
      expectHarmless(emuKillArgs, 'emu kill');
      expectHarmless(
        [qemuListScript, cpuTopologyScript, avdCreateStdin],
        'the PowerShell scripts',
      );
      expect(avdCreateArgs('anta_qa_1', 'image'), isNot(contains('--force')));
    });

    test('fleet.dart spells no destructive command outside its comments', () {
      final code = File('tool/qa/src/fleet.dart')
          .readAsLinesSync()
          .where((line) => !line.trimLeft().startsWith('//'));
      expectHarmless(code, 'tool/qa/src/fleet.dart');
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
    final forbidden = <String, RegExp>{
      'pm clear': RegExp('pm clear', caseSensitive: false),
      'uninstall': RegExp('uninstall', caseSensitive: false),
      '-wipe-data': RegExp('-wipe-data', caseSensitive: false),
      'delete avd': RegExp(r'delete\s+avd|avdmanager\b.*\bdelete', caseSensitive: false),
      'Remove-Item': RegExp('remove-item', caseSensitive: false),
      'taskkill': RegExp('taskkill', caseSensitive: false),
      'emu kill': RegExp(r"emu kill|'emu',\s*'kill'", caseSensitive: false),
    };
    // Where a stop is the job, each guarded: `kill-run` ends the tool's own
    // recorded `flutter run` (runner.dart's killRecordedRun), and `fleet
    // stop` asks a fleet console only after it names its AVD (fleet.dart;
    // its vector, its failure message, and the verb's help line in qa.dart).
    const sanctioned = <String, Map<String, int>>{
      'tool/qa/src/runner.dart': {'taskkill': 1},
      'tool/qa/src/fleet.dart': {'emu kill': 2},
      'tool/qa/qa.dart': {'emu kill': 1},
    };

    bool isComment(String line) {
      final trimmed = line.trimLeft();
      return trimmed.startsWith('//') ||
          trimmed.startsWith('#') ||
          trimmed.toUpperCase().startsWith('REM ') ||
          trimmed.startsWith('::');
    }

    test('every hit under tool/qa and test_driver is a sanctioned one', () {
      final files = [
        for (final root in ['tool/qa', 'test_driver'])
          ...Directory(root).listSync(recursive: true).whereType<File>(),
      ];
      expect(files.length, greaterThan(40));
      final found = <String, Map<String, int>>{};
      for (final file in files) {
        final relative = file.path.replaceAll(r'\', '/');
        for (final line in file.readAsLinesSync()) {
          if (isComment(line)) continue;
          forbidden.forEach((name, pattern) {
            if (!pattern.hasMatch(line)) return;
            final counts = found.putIfAbsent(relative, () => {});
            counts[name] = (counts[name] ?? 0) + 1;
          });
        }
      }
      expect(found, sanctioned);
    });
  });
}
