import 'dart:convert';

import '../../core/database/wmn_database.dart';
import 'frappe_session.dart';

class WmnFrappeDefaults {
  WmnFrappeDefaults({required this.database, required this.session});

  final WmnDatabase database;
  final WmnFrappeSession session;

  Object? getDefault(String key, {String? user}) {
    final userId = user ?? session.user;
    final personal = _get(userId, key);
    return personal ?? _get('__global__', key);
  }

  Object? getGlobalDefault(String key) => _get('__global__', key);

  void setDefault(String key, Object? value, {String? user}) {
    _set(user ?? session.user, key, value);
  }

  void setGlobalDefault(String key, Object? value) => _set('__global__', key, value);

  Map<String, Object?> getDefaults({String? user}) {
    final global = _all('__global__');
    final personal = _all(user ?? session.user);
    return <String, Object?>{...global, ...personal};
  }

  Object? _get(String userId, String key) {
    final rows = database.db.select(
      'SELECT value_json FROM wmn_defaults WHERE user_id = ? AND default_key = ? LIMIT 1;',
      [userId, key],
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['value_json'] as String?;
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
  }

  Map<String, Object?> _all(String userId) {
    final rows = database.db.select(
      'SELECT default_key,value_json FROM wmn_defaults WHERE user_id = ? ORDER BY default_key;',
      [userId],
    );
    final result = <String, Object?>{};
    for (final row in rows) {
      final key = row['default_key'] as String;
      final raw = row['value_json'] as String?;
      if (raw == null) {
        result[key] = null;
        continue;
      }
      try {
        result[key] = jsonDecode(raw);
      } catch (_) {
        result[key] = raw;
      }
    }
    return result;
  }

  void _set(String userId, String key, Object? value) {
    final normalized = key.trim();
    if (normalized.isEmpty) throw StateError('Default key is required.');
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO wmn_defaults(user_id,default_key,value_json,updated_at)
      VALUES (?,?,?,?)
      ON CONFLICT(user_id,default_key) DO UPDATE SET
        value_json=excluded.value_json,updated_at=excluded.updated_at;
    ''', [userId, normalized, jsonEncode(value), now]);
  }
}
