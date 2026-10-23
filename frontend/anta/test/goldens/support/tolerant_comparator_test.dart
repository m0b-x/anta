import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'tolerant_comparator.dart';

/// The comparator's rule on images small enough to reason about pixel by
/// pixel: 100 × 100, so one pixel is 0.01 % and the 0.5 % limit is 50.
void main() {
  const side = 100;

  /// A light ground with a dark 20 × 10 block at ([left], [top]).
  img.Image block({int left = 10, int top = 10}) {
    final image = img.Image(width: side, height: side, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(240, 240, 240, 255));
    img.fillRect(
      image,
      x1: left,
      y1: top,
      x2: left + 19,
      y2: top + 9,
      color: img.ColorRgba8(30, 30, 90, 255),
    );
    return image;
  }

  Uint8List png(img.Image image) => img.encodePng(image);

  test('an identical image passes with nothing changed', () {
    final result = TolerantGoldenComparator.diff(png(block()), png(block()));

    expect(result.passes, isTrue);
    expect(result.changedPixels, 0);
    expect(result.diffPng, isNull);
  });

  test('a shade under the channel tolerance is not a change', () {
    final shaded = block();
    for (final pixel in shaded) {
      pixel.r = pixel.r - TolerantGoldenComparator.channelTolerance;
    }

    final result = TolerantGoldenComparator.diff(png(block()), png(shaded));

    expect(result.changedPixels, 0);
  });

  test('anti-aliasing noise on 0.2 % of the pixels passes', () {
    final noisy = block();
    // 20 edge pixels of the block, each well past the tolerance.
    for (var x = 10; x < 30; x++) {
      noisy.setPixelRgba(x, 9, 120, 120, 170, 255);
    }

    final result = TolerantGoldenComparator.diff(png(block()), png(noisy));

    expect(result.changedPixels, 20);
    expect(result.changedFraction, closeTo(0.002, 1e-9));
    expect(result.passes, isTrue);
  });

  test('a block moved by 15 px fails, and the diff marks it in red', () {
    final result = TolerantGoldenComparator.diff(
      png(block()),
      png(block(left: 25)),
    );

    // The 15 columns the block left and the 15 it moved into, 10 rows each.
    expect(result.changedPixels, 300);
    expect(result.passes, isFalse);
    final diff = img.decodePng(result.diffPng!)!;
    final moved = diff.getPixel(12, 12);
    expect([moved.r, moved.g, moved.b], [255, 0, 0]);
    final kept = diff.getPixel(90, 90);
    expect(kept.r, kept.g);
  });

  test('a different size fails before any pixel is compared', () {
    final wider = img.Image(width: side + 1, height: side, numChannels: 4);

    final result = TolerantGoldenComparator.diff(png(block()), png(wider));

    expect(result.sizeMatches, isFalse);
    expect(result.passes, isFalse);
  });

  group('compare', () {
    late Directory dir;
    late TolerantGoldenComparator comparator;
    final golden = Uri.parse('images/block.png');

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('anta_tolerant_comparator');
      comparator = TolerantGoldenComparator(
        Uri.file('${dir.path}/block_test.dart'),
      );
      await comparator.update(golden, png(block()));
    });

    tearDown(() => dir.delete(recursive: true));

    test('passes within the tolerance and writes nothing', () async {
      expect(await comparator.compare(png(block()), golden), isTrue);
      expect(Directory('${dir.path}/failures').existsSync(), isFalse);
    });

    test('fails with the percentage and leaves master, test and diff '
        'next to the goldens', () async {
      await expectLater(
        comparator.compare(png(block(left: 25)), golden),
        throwsA(
          isA<FlutterError>().having(
            (error) => error.message,
            'message',
            contains('3.00 % of pixels changed'),
          ),
        ),
      );
      for (final suffix in ['master', 'test', 'diff']) {
        expect(
          File('${dir.path}/failures/block_$suffix.png').existsSync(),
          isTrue,
          reason: suffix,
        );
      }
    });
  });
}
