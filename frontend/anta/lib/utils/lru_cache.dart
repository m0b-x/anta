import 'dart:collection';

/// Fixed-capacity least-recently-used map over a [LinkedHashMap], whose
/// insertion order is the recency order: a hit re-inserts its entry at
/// the end, and an insertion past [maxSize] evicts the first key.
///
/// With [maxWeight] and a `weigh` function the cache is also bounded by
/// the summed weight of its values: an insertion evicts from the old end
/// until the sum fits again, but never the entry just put — one value
/// heavier than the whole bound is still cached, alone.
///
/// [V] must be non-nullable — absence is signalled by a `null` result
/// from the underlying map, so a stored `null` would read as a miss and
/// as room for one more entry. Callers that need "cached nothing"
/// semantics store a sentinel value (see `MarkdownEditorSpanBuilder`).
class LruCache<K, V extends Object> {
  final int maxSize;

  /// The bound on [weight], or `null` for a cache bounded by count alone.
  final int? maxWeight;
  final int Function(V value)? _weigh;
  final LinkedHashMap<K, V> _cache = LinkedHashMap<K, V>();
  int _weight = 0;

  LruCache({
    required this.maxSize,
    this.maxWeight,
    int Function(V value)? weigh,
  }) : assert(maxSize > 0),
       assert((maxWeight == null) == (weigh == null)),
       _weigh = weigh;

  /// The summed weight of the cached values; `0` without a `weigh`.
  int get weight => _weight;

  int _weightOf(V value) => _weigh?.call(value) ?? 0;

  V? get(K key) {
    final value = _cache.remove(key);
    if (value == null) return null;
    _cache[key] = value;
    return value;
  }

  void put(K key, V value) {
    final previous = _cache.remove(key);
    if (previous != null) {
      _weight -= _weightOf(previous);
    } else if (_cache.length >= maxSize) {
      _evictOldest();
    }
    _cache[key] = value;
    _weight += _weightOf(value);
    final bound = maxWeight;
    if (bound == null) return;
    while (_weight > bound && _cache.length > 1) {
      _evictOldest();
    }
  }

  void _evictOldest() {
    final value = _cache.remove(_cache.keys.first);
    if (value != null) _weight -= _weightOf(value);
  }

  bool containsKey(K key) => _cache.containsKey(key);

  V? remove(K key) {
    final value = _cache.remove(key);
    if (value != null) _weight -= _weightOf(value);
    return value;
  }

  void clear() {
    _cache.clear();
    _weight = 0;
  }

  int get length => _cache.length;

  Iterable<K> get keys => _cache.keys;

  Iterable<V> get values => _cache.values;

  void removeWhere(bool Function(K key, V value) test) {
    _cache.removeWhere((key, value) {
      if (!test(key, value)) return false;
      _weight -= _weightOf(value);
      return true;
    });
  }
}
