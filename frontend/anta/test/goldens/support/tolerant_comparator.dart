import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// What [TolerantGoldenComparator.diff] found between a master and a test
/// image.
class GoldenDiff {
  const GoldenDiff._({
    required this.sizeMatches,
    required this.changedPixels,
    required this.totalPixels,
    this.diffPng,
  });

  /// False when the two images are not the same size; nothing else is
  /// compared then.
  final bool sizeMatches;

  final int changedPixels;
  final int totalPixels;

  /// The master in grey with every changed pixel in red, or null when
  /// nothing changed or the sizes differ.
  final Uint8List? diffPng;

  double get changedFraction =>
      totalPixels == 0 ? 0 : changedPixels / totalPixels;

  bool get passes =>
      sizeMatches &&
      changedFraction <= TolerantGoldenComparator.maxChangedFraction;
}

/// A [LocalFileComparator] that forgives anti-aliasing noise.
///
/// The goldens are drawn on Windows and on the Mac with the same Flutter
/// version and the same fonts, but the rasterizer still lands an edge pixel
/// a shade differently from one host to the other; a byte-exact compare
/// would fail every golden on the machine that did not write it. A layout
/// regression moves whole glyphs and rows, so it changes far more pixels,
/// by far more than a shade, than that noise ever does. If the Mac's noise
/// ever exceeds [maxChangedFraction], the fallback is per-OS master images,
/// not a looser limit.
class TolerantGoldenComparator extends LocalFileComparator {
  TolerantGoldenComparator(super.testFile);

  /// A pixel counts as changed only when one of its channels moved by more
  /// than this, out of 255.
  static const int channelTolerance = 16;

  /// A golden fails only when more than this share of its pixels changed:
  /// 0.1 % is 281 px of a 360 × 780 cell; the 0.5 % first chosen (1,404 px)
  /// could let an ellipsized word through.
  static const double maxChangedFraction = 0.001;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final master = Uint8List.fromList(await getGoldenBytes(golden));
    final result = diff(master, imageBytes);
    if (result.passes) return true;

    final name = golden.pathSegments.last.replaceAll('.png', '');
    final failures = Directory.fromUri(basedir.resolve('failures/'));
    await failures.create(recursive: true);
    await File('${failures.path}/${name}_master.png').writeAsBytes(master);
    await File('${failures.path}/${name}_test.png').writeAsBytes(imageBytes);
    final diffPng = result.diffPng;
    if (diffPng != null) {
      await File('${failures.path}/${name}_diff.png').writeAsBytes(diffPng);
    }
    final what = result.sizeMatches
        ? '${(result.changedFraction * 100).toStringAsFixed(2)} % of pixels '
              'changed (${result.changedPixels} of ${result.totalPixels}; '
              'the limit is ${(maxChangedFraction * 100).toStringAsFixed(2)} %)'
        : 'the image size changed';
    throw FlutterError(
      'Golden "$golden": $what. The master, the test image and the diff '
      '(changed pixels in red) are in ${failures.path}.',
    );
  }

  /// Compares two PNGs pixel by pixel under [channelTolerance].
  static GoldenDiff diff(Uint8List masterPng, Uint8List testPng) {
    final master = _decode(masterPng);
    final test = _decode(testPng);
    if (master.width != test.width || master.height != test.height) {
      return const GoldenDiff._(
        sizeMatches: false,
        changedPixels: 0,
        totalPixels: 0,
      );
    }
    final a = _rgba(master);
    final b = _rgba(test);
    final out = Uint8List(a.length);
    var changed = 0;
    for (var i = 0; i < a.length; i += 4) {
      final moved =
          (a[i] - b[i]).abs() > channelTolerance ||
          (a[i + 1] - b[i + 1]).abs() > channelTolerance ||
          (a[i + 2] - b[i + 2]).abs() > channelTolerance ||
          (a[i + 3] - b[i + 3]).abs() > channelTolerance;
      if (moved) {
        changed++;
        out[i] = 255;
        out[i + 1] = 0;
        out[i + 2] = 0;
      } else {
        // The master faded to a light grey, so the red reads against it
        // while the layout around a change stays recognisable.
        final grey = 160 + (a[i] + a[i + 1] + a[i + 2]) ~/ 12;
        out[i] = grey;
        out[i + 1] = grey;
        out[i + 2] = grey;
      }
      out[i + 3] = 255;
    }
    return GoldenDiff._(
      sizeMatches: true,
      changedPixels: changed,
      totalPixels: master.width * master.height,
      diffPng: changed == 0
          ? null
          : img.encodePng(
              img.Image.fromBytes(
                width: master.width,
                height: master.height,
                bytes: out.buffer,
                numChannels: 4,
              ),
            ),
    );
  }

  static img.Image _decode(Uint8List png) {
    final image = img.decodePng(png);
    if (image == null) {
      throw FlutterError('Not a PNG a golden can be read from');
    }
    return image;
  }

  static Uint8List _rgba(img.Image image) => image
      .convert(format: img.Format.uint8, numChannels: 4, alpha: 255)
      .getBytes(order: img.ChannelOrder.rgba);
}
