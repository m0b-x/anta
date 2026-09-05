import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

/// Two-level cache contract of the fork's paragraph provider: an
/// identity-keyed L1 (`LinkedHashMap.identity()`) sits in front of an
/// equality-keyed L2 LRU, so a steady-state hit — the render asking for
/// the same `TextSpan` instance it asked for last frame — costs one
/// pointer hash and never walks the span tree's `==`/`hashCode`.
///
/// `LinkedHashMap.identity()` is `equals: identical, hashCode:
/// identityHashCode` (dart:collection), so an L1 lookup never calls the
/// key's own `==`/`hashCode` at all, regardless of whether the span
/// overrides them. Only a miss that falls through to the plain `Map`
/// backing L2 can touch those overrides. [_CountingSpan] counts exactly
/// that: it increments a counter inside `==`/`hashCode` and delegates to
/// `super` so the counts stay meaningful (equal spans still compare
/// equal, so the L2 map still finds them) — see `hash_and_equals`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _CountingSpan.resetCounters();
  });

  group('paragraph cache identity contract', () {
    test('a steady-state identity hit never touches hashCode or ==', () {
      final CodeParagraphProviderForTesting provider = _provider();
      final _CountingSpan span = _countingSpan('buy milk');
      final IParagraph first = provider.build(span, _maxWidth);

      _CountingSpan.resetCounters();
      final IParagraph second = provider.build(span, _maxWidth);

      expect(identical(second, first), isTrue);
      expect(_CountingSpan.hashCodeCalls, 0);
      expect(_CountingSpan.equalityCalls, 0);
    });

    test('a distinct but value-equal span falls through to the L2 map', () {
      final CodeParagraphProviderForTesting provider = _provider();
      final _CountingSpan first = _countingSpan('buy milk');
      final IParagraph firstParagraph = provider.build(first, _maxWidth);

      _CountingSpan.resetCounters();
      final _CountingSpan second = _countingSpan('buy milk');
      expect(identical(first, second), isFalse);
      expect(first, second, reason: 'must be value-equal for L2 to find it');

      final IParagraph secondParagraph = provider.build(second, _maxWidth);

      expect(
        identical(secondParagraph, firstParagraph),
        isTrue,
        reason: 'the L2 equality map should hand back the L1-cached impl',
      );
      expect(
        _CountingSpan.hashCodeCalls,
        greaterThan(0),
        reason:
            'the L1 identity miss must fall through to the L2 map, '
            'which hashes the span to find its bucket',
      );
    });

    test('clearCache empties both levels: a rebuild is a new instance', () {
      final CodeParagraphProviderForTesting provider = _provider();
      final _CountingSpan span = _countingSpan('buy milk');
      final IParagraph before = provider.build(span, _maxWidth);

      provider.clearCache();
      final IParagraph after = provider.build(span, _maxWidth);

      expect(identical(after, before), isFalse);
    });

    test('a maxWidth change invalidates the cache for the same span', () {
      final CodeParagraphProviderForTesting provider = _provider();
      final _CountingSpan span = _countingSpan('buy milk');
      final IParagraph atFirstWidth = provider.build(span, _maxWidth);

      final IParagraph atOtherWidth = provider.build(span, _maxWidth + 40);
      expect(identical(atOtherWidth, atFirstWidth), isFalse);

      final IParagraph backAtFirstWidth = provider.build(span, _maxWidth);
      expect(
        identical(backAtFirstWidth, atFirstWidth),
        isFalse,
        reason:
            'the width change must evict, not shadow: rebuilding at the '
            'original width may not hand back the pre-change instance',
      );
    });
  });
}

const TextStyle _base = TextStyle(fontSize: 14, height: 1.4);
const double _maxWidth = 200;

CodeParagraphProviderForTesting _provider() =>
    CodeParagraphProviderForTesting()..updateBaseStyle(_base);

_CountingSpan _countingSpan(String text) =>
    _CountingSpan(text: text, style: _base);

class _CountingSpan extends TextSpan {
  const _CountingSpan({required super.text, required super.style});

  static int hashCodeCalls = 0;
  static int equalityCalls = 0;

  static void resetCounters() {
    hashCodeCalls = 0;
    equalityCalls = 0;
  }

  @override
  bool operator ==(Object other) {
    equalityCalls++;
    return super == other;
  }

  @override
  int get hashCode {
    hashCodeCalls++;
    return super.hashCode;
  }
}
