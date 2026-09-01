import 'dart:convert';

import '../../core/database/wmn_database.dart';

class WmnFrappeCache {
  WmnFrappeCache(this.database);

  final WmnDatabase database;
  final Map<String, Object?> _memory = <String, Object?>{};

  Object? get(String key, {String namespace = 'default'}) {
    final compound = '$namespace::$key';
    if (_memory.containsKey(compound)) return _memory[compound];
    final rows = database.db.select(
      'SELECT value_json, expires_at FROM wmn_runtime_cache WHERE namespace=? AND cache_key=? LIMIT 1;',
      [namespace, key],
    );
    if (rows.isEmpty) return null;
    final expires = rows.first['expires_at'] as String?;
    if (expires != null && DateTime.tryParse(expires)?.isBefore(DateTime.now().toUtc()) == true) {
      delete(key, namespace: namespace);
      return null;
    }
    final raw = rows.first['value_json'] as String?;
    final value = raw == null ? null : jsonDecode(raw);
    _memory[compound] = value;
    return value;
  }

  void set(String key, Object? value, {String namespace = 'default', Duration? ttl}) {
    final now = DateTime.now().toUtc();
    final expires = ttl == null ? null : now.add(ttl).toIso8601String();
    database.db.execute('''
      INSERT INTO wmn_runtime_cache(namespace,cache_key,value_json,expires_at,updated_at)
      VALUES (?,?,?,?,?)
      ON CONFLICT(namespace,cache_key) DO UPDATE SET
        value_json=excluded.value_json,expires_at=excluded.expires_at,updated_at=excluded.updated_at;
    ''', [namespace, key, value == null ? null : jsonEncode(value), expires, now.toIso8601String()]);
    _memory['$namespace::$key'] = value;
  }

  void delete(String key, {String namespace = 'default'}) {
    database.db.execute('DELETE FROM wmn_runtime_cache WHERE namespace=? AND cache_key=?;', [namespace, key]);
    _memory.remove('$namespace::$key');
  }

  void clear({String? namespace}) {
    if (namespace == null) {
      database.db.execute('DELETE FROM wmn_runtime_cache;');
      _memory.clear();
      return;
    }
    database.db.execute('DELETE FROM wmn_runtime_cache WHERE namespace=?;', [namespace]);
    _memory.removeWhere((key, _) => key.startsWith('$namespace::'));
  }

  Object? hget(String hash, String field) => get(field, namespace: 'hash:$hash');
  void hset(String hash, String field, Object? value, {Duration? ttl}) => set(field, value, namespace: 'hash:$hash', ttl: ttl);
  void hdel(String hash, String field) => delete(field, namespace: 'hash:$hash');
}
