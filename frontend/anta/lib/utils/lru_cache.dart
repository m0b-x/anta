import 'dart:collection';

/// Fixed-capacity least-recently-used map over a [LinkedHashMap], whose
/// insertion order is the recency order: a hit re-inserts its entry at
/// the end, and an insertion past [maxSize] evicts the first key.
///
/// [V] must be non-nullable — absence is signalled by a `null` result
/// from the underlying map, so a stored `null` would read as a miss and
/// as room for one more entry. Callers that need "cached nothing"
/// semantics store a sentinel value (see `MarkdownEditorSpanBuilder`).
class LruCache<K, V extends Object> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap<K, V>();

  LruCache({required this.maxSize}) : assert(maxSize > 0);

  V? get(K key) {
    final value = _cache.remove(key);
    if (value == null) return null;
    _cache[key] = value;
    return value;
  }

  void put(K key, V value) {
    if (_cache.remove(key) == null && _cache.length >= maxSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = value;
  }

  bool containsKey(K key) => _cache.containsKey(key);

  V? remove(K key) => _cache.remove(key);

  void clear() => _cache.clear();

  int get length => _cache.length;

  Iterable<K> get keys => _cache.keys;

  Iterable<V> get values => _cache.values;

  void removeWhere(bool Function(K key, V value) test) {
    _cache.removeWhere(test);
  }
}
