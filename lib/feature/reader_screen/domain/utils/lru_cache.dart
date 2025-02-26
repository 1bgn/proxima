// lru_cache.dart
import 'dart:collection';

class LruCache<K, V> {
  final int capacity;
  final _map = LinkedHashMap<K, V>();

  LruCache(this.capacity);

  V? get(K key) {
    final value = _map.remove(key);
    if (value != null) {
      _map[key] = value;
    }
    return value;
  }

  void put(K key, V value) {
    if (_map.containsKey(key)) {
      _map.remove(key);
      _map[key] = value;
      return;
    }
    if (_map.length >= capacity) {
      final oldestKey = _map.keys.first;
      _map.remove(oldestKey);
    }
    _map[key] = value;
  }

  bool containsKey(K key) => _map.containsKey(key);
  void clear() => _map.clear();
  void remove(K key) => _map.remove(key);
}
