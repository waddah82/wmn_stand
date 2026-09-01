import 'dart:convert';

import '../../core/audit/audit_service.dart';
import '../../core/database/wmn_database.dart';

enum WmnConfigurationScope {
  system,
  application,
  platform,
  profile,
}

class WmnConfigurationEntry {
  const WmnConfigurationEntry({
    required this.scope,
    required this.scopeKey,
    required this.key,
    required this.value,
    required this.isSecret,
    required this.updatedAt,
  });

  final WmnConfigurationScope scope;
  final String scopeKey;
  final String key;
  final Object? value;
  final bool isSecret;
  final DateTime updatedAt;
}

/// Hierarchical configuration service for WMN System and installed apps.
///
/// Secret entries are redacted from audit payloads. R3.2 does not claim
/// encryption-at-rest; a secure-storage adapter will own that responsibility
/// on supported platforms later.
class WmnConfigurationService {
  WmnConfigurationService({required this.database, required this.audit});

  final WmnDatabase database;
  final AuditService audit;

  Object? getValue(
    WmnConfigurationScope scope,
    String key, {
    String scopeKey = '',
    Object? fallback,
  }) {
    final rows = database.db.select('''
      SELECT value_json FROM wmn_scoped_settings
      WHERE scope_type=? AND scope_key=? AND setting_key=?
      LIMIT 1;
    ''', [_scopeName(scope), scopeKey, key]);
    if (rows.isEmpty) return fallback;
    final raw = rows.first['value_json'];
    if (raw == null) return null;
    return jsonDecode('$raw');
  }

  String getString(
    WmnConfigurationScope scope,
    String key, {
    String scopeKey = '',
    required String fallback,
  }) {
    final value = getValue(scope, key, scopeKey: scopeKey, fallback: fallback);
    return value is String ? value : '$value';
  }

  bool getBool(
    WmnConfigurationScope scope,
    String key, {
    String scopeKey = '',
    required bool fallback,
  }) {
    final value = getValue(scope, key, scopeKey: scopeKey, fallback: fallback);
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      return const <String>{'1', 'true', 'yes', 'on'}.contains(value.toLowerCase());
    }
    return fallback;
  }

  void setValue(
    WmnConfigurationScope scope,
    String key,
    Object? value, {
    String scopeKey = '',
    bool isSecret = false,
    String? actor,
  }) {
    if (key.trim().isEmpty) throw StateError('Configuration key is required.');
    final now = DateTime.now().toUtc().toIso8601String();
    database.transaction(() {
      database.db.execute('''
        INSERT INTO wmn_scoped_settings(
          scope_type,scope_key,setting_key,value_json,is_secret,updated_at
        ) VALUES (?,?,?,?,?,?)
        ON CONFLICT(scope_type,scope_key,setting_key) DO UPDATE SET
          value_json=excluded.value_json,
          is_secret=excluded.is_secret,
          updated_at=excluded.updated_at;
      ''', [_scopeName(scope), scopeKey, key, jsonEncode(value), isSecret ? 1 : 0, now]);
      audit.record(
        entityType: 'WMN Configuration',
        entityId: '${_scopeName(scope)}:$scopeKey:$key',
        action: 'SET',
        userId: actor,
        payload: <String, Object?>{
          'scope': _scopeName(scope),
          'scope_key': scopeKey,
          'key': key,
          'secret': isSecret,
          if (!isSecret) 'value': value,
        },
      );
    });
  }

  void remove(
    WmnConfigurationScope scope,
    String key, {
    String scopeKey = '',
    String? actor,
  }) {
    database.transaction(() {
      database.db.execute(
        'DELETE FROM wmn_scoped_settings WHERE scope_type=? AND scope_key=? AND setting_key=?;',
        [_scopeName(scope), scopeKey, key],
      );
      audit.record(
        entityType: 'WMN Configuration',
        entityId: '${_scopeName(scope)}:$scopeKey:$key',
        action: 'DELETE',
        userId: actor,
        payload: <String, Object?>{'scope': _scopeName(scope), 'scope_key': scopeKey, 'key': key},
      );
    });
  }

  List<WmnConfigurationEntry> entries({WmnConfigurationScope? scope, String? scopeKey}) {
    final where = <String>[];
    final args = <Object?>[];
    if (scope != null) {
      where.add('scope_type=?');
      args.add(_scopeName(scope));
    }
    if (scopeKey != null) {
      where.add('scope_key=?');
      args.add(scopeKey);
    }
    final clause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    final rows = database.db.select('''
      SELECT scope_type,scope_key,setting_key,value_json,is_secret,updated_at
      FROM wmn_scoped_settings $clause
      ORDER BY scope_type,scope_key,setting_key;
    ''', args);
    return rows.map((row) {
      final raw = row['value_json'];
      return WmnConfigurationEntry(
        scope: _scopeFromName('${row['scope_type']}'),
        scopeKey: '${row['scope_key']}',
        key: '${row['setting_key']}',
        value: raw == null ? null : jsonDecode('$raw'),
        isSecret: row['is_secret'] == 1,
        updatedAt: DateTime.parse('${row['updated_at']}'),
      );
    }).toList(growable: false);
  }

  String _scopeName(WmnConfigurationScope scope) => switch (scope) {
        WmnConfigurationScope.system => 'SYSTEM',
        WmnConfigurationScope.application => 'APPLICATION',
        WmnConfigurationScope.platform => 'PLATFORM',
        WmnConfigurationScope.profile => 'PROFILE',
      };

  WmnConfigurationScope _scopeFromName(String value) => switch (value) {
        'APPLICATION' => WmnConfigurationScope.application,
        'PLATFORM' => WmnConfigurationScope.platform,
        'PROFILE' => WmnConfigurationScope.profile,
        _ => WmnConfigurationScope.system,
      };
}
