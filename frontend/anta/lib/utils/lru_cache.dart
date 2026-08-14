import 'dart:collection';

class LruCache<K, V> {
  final int maxSize;
  final LinkedHashMap<K, V> _cache = LinkedHashMap<K, V>();

  LruCache({required this.maxSize});

  V? get(K key) {
    if (!_cache.containsKey(key)) return null;

    final value = _cache.remove(key);
    _cache[key] = value as V;
    return value;
  }

  void put(K key, V value) {
    if (_cache.containsKey(key)) {
      _cache.remove(key);
    } else if (_cache.length >= maxSize) {
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
