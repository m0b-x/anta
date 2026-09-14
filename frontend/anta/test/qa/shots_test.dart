import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import '../../tool/qa/src/device.dart';
import '../../tool/qa/src/errors.dart';
import '../../tool/qa/src/gestures.dart';
import '../../tool/qa/src/paths.dart';
import '../../tool/qa/src/shots.dart';
import '../../tool/qa/src/ui_tree.dart';

class _FakeDevice implements Device {
  _FakeDevice(this.png);

  final List<int> png;

  @override
  String get id => 'fake';

  @override
  Future<List<int>> screencapPng() async => png;

  @override
  Future<ScreenSize> screenSize() async => const ScreenSize(
      physicalWidth: 1280, physicalHeight: 2856, density: 480);

  @override
  Future<int?> appPid(String packageId) async => null;

  @override
  Future<UiTree> dumpUi() async => UiTree(const []);

  @override
  Future<void> forceStop(String packageId) async {}

  @override
  Future<void> key(String keycode) async {}

  @override
  Future<void> launchActivity(String component) async {}

  @override
  Future<void> swipePath(SwipePath path) async {}

  @override
  Future<void> tap(int x, int y) async {}

  @override
  Future<void> typeText(String text) async {}
}

Uint8List _png(int width, int height) =>
    img.encodePng(img.Image(width: width, height: height));

void main() {
  late Directory temp;
  late QaPaths paths;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('anta_shots_');
    paths = QaPaths(temp.path);
  });

  tearDown(() => temp.deleteSync(recursive: true));

  group('shotStamp and sanitiseName', () {
    test('the stamp sorts chronologically as a file name', () {
      expect(shotStamp(DateTime(2026, 9, 13, 17, 4, 5)), '20260913_170405');
      expect(shotStamp(DateTime(2026, 1, 2, 3, 4, 5)), '20260102_030405');
    });

    test('a name is reduced to safe file characters', () {
      expect(sanitiseName('folder page'), 'folder_page');
      expect(sanitiseName('a/b:c*d'), 'a_b_c_d');
      expect(sanitiseName('keep-this.1'), 'keep-this.1');
      expect(sanitiseName('///'), 'shot');
    });
  });

  group('captureShot', () {
    test('downscales by half by default and prints an absolute path', () async {
      final path = await captureShot(
        _FakeDevice(_png(1280, 2856)),
        paths,
        name: 'home',
        now: DateTime(2026, 9, 13, 17, 37, 44),
      );
      expect(File(path).isAbsolute, isTrue);
      expect(path, endsWith('20260913_173744_home.png'));
      final decoded = img.decodePng(File(path).readAsBytesSync())!;
      expect(decoded.width, 640);
      expect(decoded.height, 1428);
    });

    test('--full keeps the device pixels', () async {
      final path = await captureShot(
        _FakeDevice(_png(200, 400)),
        paths,
        scale: 1.0,
      );
      final decoded = img.decodePng(File(path).readAsBytesSync())!;
      expect(decoded.width, 200);
      expect(decoded.height, 400);
    });

    test('--out writes elsewhere, creating the directory', () async {
      final path = await captureShot(
        _FakeDevice(_png(100, 100)),
        paths,
        outDir: 'nested/shots',
      );
      expect(path, contains('nested'));
      expect(File(path).existsSync(), isTrue);
    });

    test('rejects a scale outside (0, 1]', () async {
      final device = _FakeDevice(_png(100, 100));
      expect(() => captureShot(device, paths, scale: 0),
          throwsA(isA<UsageFailure>()));
      expect(() => captureShot(device, paths, scale: 1.5),
          throwsA(isA<UsageFailure>()));
    });

    test('an empty screencap is a device failure', () async {
      expect(
        () => captureShot(_FakeDevice(const []), paths),
        throwsA(isA<DeviceFailure>()),
      );
    });

    test('a screencap that is not a PNG is a device failure', () async {
      expect(
        () => captureShot(_FakeDevice(const [1, 2, 3, 4]), paths),
        throwsA(isA<DeviceFailure>()),
      );
    });
  });
}
