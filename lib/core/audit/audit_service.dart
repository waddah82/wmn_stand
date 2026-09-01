import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../database/wmn_database.dart';

class WmnAuditEntry {
  const WmnAuditEntry({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.action,
    required this.payload,
    required this.createdAt,
    this.userId,
  });

  final String id;
  final String entityType;
  final String entityId;
  final String action;
  final String? userId;
  final Map<String, Object?> payload;
  final DateTime createdAt;
}

class AuditService {
  AuditService(this.database);

  final WmnDatabase database;
  static const Uuid _uuid = Uuid();

  void record({
    required String entityType,
    required String entityId,
    required String action,
    String? userId,
    Map<String, Object?> payload = const {},
    DateTime? occurredAt,
  }) {
    final timestamp = (occurredAt ?? DateTime.now()).toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO audit_log(
        id, entity_type, entity_id, action, user_id, payload_json, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?);
    ''', [
      _uuid.v4(),
      entityType,
      entityId,
      action,
      userId,
      jsonEncode(payload),
      timestamp,
    ]);
  }

  List<WmnAuditEntry> entries({String? entityType, String? entityId, int limit = 200}) {
    final where = <String>[];
    final args = <Object?>[];
    if (entityType != null && entityType.trim().isNotEmpty) {
      where.add('entity_type=?');
      args.add(entityType);
    }
    if (entityId != null && entityId.trim().isNotEmpty) {
      where.add('entity_id=?');
      args.add(entityId);
    }
    final clause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    args.add(limit);
    final rows = database.db.select('''
      SELECT * FROM audit_log
      $clause
      ORDER BY created_at DESC
      LIMIT ?;
    ''', args);
    return rows.map((row) {
      final data = Map<String, Object?>.from(row);
      Map<String, Object?> payload = const <String, Object?>{};
      final raw = data['payload_json'];
      if (raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) payload = Map<String, Object?>.from(decoded);
      }
      return WmnAuditEntry(
        id: '${data['id']}',
        entityType: '${data['entity_type']}',
        entityId: '${data['entity_id']}',
        action: '${data['action']}',
        userId: data['user_id'] as String?,
        payload: Map<String, Object?>.unmodifiable(payload),
        createdAt: DateTime.parse('${data['created_at']}'),
      );
    }).toList(growable: false);
  }

  int get count => database.db.select('SELECT COUNT(*) AS c FROM audit_log;').first['c'] as int? ?? 0;
}
