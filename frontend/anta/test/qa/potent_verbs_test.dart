import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../tool/qa/qa.dart' show MarkerReport, QaContext, describePerf, expectMisses;
import '../../tool/qa/src/agent_client.dart';
import '../../tool/qa/src/device.dart';
import '../../tool/qa/src/poll.dart';
import '../../tool/qa/src/runner.dart';
import '../../tool/qa/src/target.dart';
import '../../tool/qa/src/doctor.dart';
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
    );

void main() {
  _hardeningTests();
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
      expect(path, endsWith('20260916_210000_root.png'));
      final decoded = img.decodePng(Uint8List.fromList(File(path).readAsBytesSync()))!;
      expect(decoded.width, 500);
      expect(decoded.height, 1000);
      expect(decoded.getPixel(400, 75).g, 92);
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

    test('expect treats a hidden node as absent', () {
      expect(expectMisses(tree, present: ['Cached only'], absent: []), ['missing "Cached only"']);
      expect(expectMisses(tree, present: [], absent: ['Cached only']), isEmpty);
    });
  });

  test('checkScreenOverride tolerates an unknown screen', () {
    expect(checkScreenOverride(const DeviceProbe()).status, CheckStatus.warn);
  });
}
