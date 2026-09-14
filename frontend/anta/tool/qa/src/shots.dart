import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'device.dart';
import 'errors.dart';
import 'paths.dart';

/// Timestamp prefix used for screenshot file names.
String shotStamp(DateTime now) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${now.year}${two(now.month)}${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
}

String sanitiseName(String name) {
  final cleaned = name
      .replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_')
      .replaceAll(RegExp(r'^[_.]+|[_.]+$'), '');
  return cleaned.isEmpty ? 'shot' : cleaned;
}

/// Grabs a screenshot, optionally downscales it, and returns the file path.
///
/// The default 0.5 scale halves each side, which is what keeps a screenshot
/// cheap for an agent to read back.
Future<String> captureShot(
  Device device,
  QaPaths paths, {
  String name = 'shot',
  double scale = 0.5,
  String? outDir,
  DateTime? now,
}) async {
  if (scale <= 0 || scale > 1) {
    throw UsageFailure('--scale must be greater than 0 and at most 1');
  }
  final bytes = await device.screencapPng();
  if (bytes.isEmpty) {
    throw DeviceFailure('screencap returned no data');
  }
  List<int> payload = bytes;
  if (scale != 1.0) {
    final decoded = img.decodePng(Uint8List.fromList(bytes));
    if (decoded == null) {
      throw DeviceFailure('screencap did not return a readable PNG');
    }
    final resized = img.copyResize(
      decoded,
      width: (decoded.width * scale).round().clamp(1, decoded.width),
      interpolation: img.Interpolation.average,
    );
    payload = img.encodePng(resized);
  }
  final directory = outDir == null
      ? paths.ensureShots()
      : (Directory(paths.resolve(outDir))..createSync(recursive: true));
  final fileName =
      '${shotStamp(now ?? DateTime.now())}_${sanitiseName(name)}.png';
  final file = File(joinPath(directory.path, [fileName]));
  file.writeAsBytesSync(payload);
  return file.absolute.path;
}
