import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'errors.dart';
import 'paths.dart';
import 'ui_tree.dart';

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

/// Grabs a screenshot through [capture], optionally downscales it, and
/// returns the file path.
///
/// The default 0.5 scale halves each side, which is what keeps a screenshot
/// cheap for an agent to read back.
Future<String> captureShot(
  Future<List<int>> Function() capture,
  QaPaths paths, {
  String name = 'shot',
  double scale = 0.5,
  String? outDir,
  DateTime? now,
}) async {
  if (scale <= 0 || scale > 1) {
    throw UsageFailure('--scale must be greater than 0 and at most 1');
  }
  final bytes = await capture();
  if (bytes.isEmpty) {
    throw DeviceFailure('the screenshot came back empty');
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

/// One box the annotated screenshot draws: the node's bounds, already in
/// the image's pixel space, and the badge to put at its corner.
class ShotBadge {
  const ShotBadge({
    required this.index,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.kind,
  });

  final int index;
  final int left;
  final int top;
  final int right;
  final int bottom;

  /// `click`, `text`, `scroll` or `other` — picks the colour.
  final String kind;

  int get width => right - left;

  int get height => bottom - top;
}

/// Which nodes an annotated screenshot marks, scaled into image space and
/// clipped to it. Pure, so the geometry can be tested without pixels.
List<ShotBadge> badgesFor(
  UiTree tree, {
  required double scale,
  required int imageWidth,
  required int imageHeight,
  bool all = false,
}) {
  final badges = <ShotBadge>[];
  for (final node in tree.nodes) {
    if (node.hidden) continue;
    if (!all && !node.interesting) continue;
    if (node.parentIndex == -1) continue;
    final left = (node.bounds.left * scale).round().clamp(0, imageWidth);
    final top = (node.bounds.top * scale).round().clamp(0, imageHeight);
    final right = (node.bounds.right * scale).round().clamp(0, imageWidth);
    final bottom = (node.bounds.bottom * scale).round().clamp(0, imageHeight);
    if (right - left < 2 || bottom - top < 2) continue;
    final kind = node.shortClass == 'EditText'
        ? 'text'
        : node.clickable
            ? 'click'
            : node.scrollable
                ? 'scroll'
                : 'other';
    badges.add(ShotBadge(
      index: node.index,
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      kind: kind,
    ));
  }
  return badges;
}

img.Color _badgeColor(String kind) => switch (kind) {
      'click' => img.ColorRgb8(255, 92, 0),
      'text' => img.ColorRgb8(0, 122, 255),
      'scroll' => img.ColorRgb8(0, 160, 90),
      _ => img.ColorRgb8(130, 130, 130),
    };

/// Draws each badge's outline and its `#index` tag onto [image].
///
/// Boxes for scroll containers are drawn thin so they do not hide the rows
/// inside them; the tag sits just inside the top-left corner, on a filled
/// strip, so it stays readable over any background.
void drawBadges(img.Image image, List<ShotBadge> badges) {
  final font = image.width >= 900 ? img.arial24 : img.arial14;
  final tagHeight = image.width >= 900 ? 26 : 16;
  final white = img.ColorRgb8(255, 255, 255);
  for (final badge in badges) {
    final color = _badgeColor(badge.kind);
    img.drawRect(
      image,
      x1: badge.left,
      y1: badge.top,
      x2: badge.right - 1,
      y2: badge.bottom - 1,
      color: color,
      thickness: badge.kind == 'scroll' ? 1 : 2,
    );
  }
  for (final badge in badges) {
    final label = '#${badge.index}';
    final tagWidth = label.length * (tagHeight * 0.62).round() + 6;
    final x = badge.left;
    final y = badge.top;
    img.fillRect(
      image,
      x1: x,
      y1: y,
      x2: (x + tagWidth).clamp(0, image.width - 1),
      y2: (y + tagHeight).clamp(0, image.height - 1),
      color: _badgeColor(badge.kind),
    );
    img.drawString(
      image,
      label,
      font: font,
      x: x + 3,
      y: y + 1,
      color: white,
    );
  }
}

/// Grabs a screenshot, downscales it, marks the tree's nodes on it and
/// returns the file path — one picture that carries the `#N` the dump uses.
Future<String> captureAnnotatedShot(
  Future<List<int>> Function() capture,
  UiTree tree,
  QaPaths paths, {
  String name = 'look',
  double scale = 0.5,
  bool all = false,
  String? outDir,
  DateTime? now,
}) async {
  if (scale <= 0 || scale > 1) {
    throw UsageFailure('--scale must be greater than 0 and at most 1');
  }
  final bytes = await capture();
  if (bytes.isEmpty) throw DeviceFailure('the screenshot came back empty');
  final decoded = img.decodePng(Uint8List.fromList(bytes));
  if (decoded == null) {
    throw DeviceFailure('the screenshot is not a readable PNG');
  }
  final image = scale == 1.0
      ? decoded
      : img.copyResize(
          decoded,
          width: (decoded.width * scale).round().clamp(1, decoded.width),
          interpolation: img.Interpolation.average,
        );
  final effectiveScale = image.width / decoded.width;
  drawBadges(
    image,
    badgesFor(
      tree,
      scale: effectiveScale,
      imageWidth: image.width,
      imageHeight: image.height,
      all: all,
    ),
  );
  final directory = outDir == null
      ? paths.ensureShots()
      : (Directory(paths.resolve(outDir))..createSync(recursive: true));
  final fileName =
      '${shotStamp(now ?? DateTime.now())}_${sanitiseName(name)}.png';
  final file = File(joinPath(directory.path, [fileName]));
  file.writeAsBytesSync(img.encodePng(image));
  return file.absolute.path;
}
