import 'package:anta/utils/lru_cache.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the recency contract every memo in the app leans on: a hit
/// promotes its key to most-recent, a miss is a plain `null`, and an
/// insertion past [LruCache.maxSize] evicts the least-recently-used key
/// and only that one. `get`/`put` reach the underlying map twice per
/// call, so the tests read state through [LruCache.keys] (insertion
/// order == recency order) rather than through more `get` calls, which
/// would themselves reorder.
void main() {
  group('get', () {
    test('returns null for a key that was never stored', () {
      final cache = LruCache<String, int>(maxSize: 4);
      expect(cache.get('missing'), isNull);
      expect(cache.length, 0);
    });

    test('returns the stored value and leaves the entry in place', () {
      final cache = LruCache<String, int>(maxSize: 4);
      cache.put('a', 1);
      expect(cache.get('a'), 1);
      expect(cache.get('a'), 1);
      expect(cache.length, 1);
      expect(cache.keys, <String>['a']);
    });

    test('a hit moves the key to most-recent', () {
      final cache = LruCache<String, int>(maxSize: 4);
      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);
      expect(cache.keys, <String>['a', 'b', 'c']);

      expect(cache.get('a'), 1);
      expect(cache.keys, <String>[
        'b',
        'c',
        'a',
      ], reason: 'a hit must promote its key past the untouched ones');
    });

    test('a miss does not reorder anything', () {
      final cache = LruCache<String, int>(maxSize: 4);
      cache.put('a', 1);
      cache.put('b', 2);
      expect(cache.get('zzz'), isNull);
      expect(cache.keys, <String>['a', 'b']);
      expect(cache.length, 2);
    });
  });

  group('construction', () {
    test('a non-positive maxSize fails the assertion', () {
      expect(() => LruCache<String, int>(maxSize: 0), throwsAssertionError);
      expect(() => LruCache<String, int>(maxSize: -1), throwsAssertionError);
    });
  });

  group('put', () {
    test('re-putting an existing key overwrites and promotes it', () {
      final cache = LruCache<String, int>(maxSize: 3);
      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);

      cache.put('a', 99);
      expect(
        cache.length,
        3,
        reason: 'overwriting an existing key must not grow the cache',
      );
      expect(cache.keys, <String>['b', 'c', 'a']);
      expect(cache.get('a'), 99);
    });

    test('a new key past maxSize evicts the least-recently-used one', () {
      final cache = LruCache<String, int>(maxSize: 3);
      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);

      cache.put('d', 4);
      expect(cache.length, 3);
      expect(cache.keys, <String>['b', 'c', 'd']);
      expect(cache.get('a'), isNull, reason: 'a was the oldest entry');
      expect(cache.get('b'), 2);
    });

    test('a hit before an overflowing put changes who is evicted', () {
      final cache = LruCache<String, int>(maxSize: 3);
      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);

      cache.get('a');
      cache.put('d', 4);
      expect(cache.keys, <String>[
        'c',
        'a',
        'd',
      ], reason: 'the promoted key survives; b is now the oldest');
      expect(cache.get('b'), isNull);
      expect(cache.get('a'), 1);
    });

    test('maxSize is never exceeded across many inserts', () {
      final cache = LruCache<int, String>(maxSize: 5);
      for (var i = 0; i < 50; i++) {
        cache.put(i, 'v$i');
        expect(cache.length, lessThanOrEqualTo(5));
      }
      expect(cache.length, 5);
      expect(cache.keys, <int>[45, 46, 47, 48, 49]);
      expect(cache.get(44), isNull);
      expect(cache.get(49), 'v49');
    });

    test('repeated puts of the same key never evict anything', () {
      final cache = LruCache<String, int>(maxSize: 2);
      cache.put('a', 1);
      cache.put('b', 2);
      for (var i = 0; i < 10; i++) {
        cache.put('b', i);
      }
      expect(cache.length, 2);
      expect(cache.keys, <String>['a', 'b']);
      expect(cache.get('a'), 1);
      expect(cache.get('b'), 9);
    });
  });

  group('remove, clear and views', () {
    test('remove returns the value and frees a slot', () {
      final cache = LruCache<String, int>(maxSize: 2);
      cache.put('a', 1);
      cache.put('b', 2);

      expect(cache.remove('a'), 1);
      expect(cache.remove('a'), isNull);
      expect(cache.length, 1);

      cache.put('c', 3);
      expect(cache.keys, <String>['b', 'c']);
    });

    test('clear empties the cache and keeps it usable', () {
      final cache = LruCache<String, int>(maxSize: 2);
      cache.put('a', 1);
      cache.put('b', 2);

      cache.clear();
      expect(cache.length, 0);
      expect(cache.keys, isEmpty);
      expect(cache.values, isEmpty);
      expect(cache.get('a'), isNull);

      cache.put('c', 3);
      expect(cache.get('c'), 3);
      expect(cache.length, 1);
    });

    test('containsKey reports membership without reordering', () {
      final cache = LruCache<String, int>(maxSize: 3);
      cache.put('a', 1);
      cache.put('b', 2);

      expect(cache.containsKey('a'), isTrue);
      expect(cache.containsKey('zzz'), isFalse);
      expect(cache.keys, <String>['a', 'b']);
    });

    test('keys and values stay in recency order', () {
      final cache = LruCache<String, int>(maxSize: 3);
      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);
      cache.get('a');

      expect(cache.keys, <String>['b', 'c', 'a']);
      expect(cache.values, <int>[2, 3, 1]);
    });

    test('removeWhere drops only the matching entries', () {
      final cache = LruCache<String, int>(maxSize: 5);
      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);
      cache.put('d', 4);

      cache.removeWhere((key, value) => value.isEven);
      expect(cache.keys, <String>['a', 'c']);
      expect(cache.get('b'), isNull);
      expect(cache.get('c'), 3);
    });
  });
}
