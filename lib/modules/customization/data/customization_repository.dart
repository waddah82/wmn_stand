import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/database/wmn_database.dart';
import '../../../platform/storage/wmn_storage_service.dart';
import '../domain/customization_models.dart';

class CustomizationRepository {
  CustomizationRepository(this.database, {WmnStorageService? storage})
      : storage = storage ?? WmnStorageService.forDatabase(database);

  final WmnDatabase database;
  final WmnStorageService storage;
  static const Uuid _uuid = Uuid();

  List<WmnCustomField> customFields({String? documentType, bool enabledOnly = false}) {
    final clauses = <String>[];
    final args = <Object?>[];
    if (documentType != null && documentType.trim().isNotEmpty) {
      clauses.add('document_type = ?');
      args.add(documentType.trim());
    }
    if (enabledOnly) clauses.add('enabled = 1');
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    final rows = database.db.select('''
      SELECT * FROM custom_fields
      $where
      ORDER BY document_type, sort_order, field_name;
    ''', args);
    return rows.map(_mapCustomField).toList(growable: false);
  }

  WmnCustomField saveCustomField({
    String? id,
    required String documentType,
    required String fieldName,
    required String label,
    required WmnCustomFieldType fieldType,
    String? insertAfter,
    List<String> options = const [],
    Object? defaultValue,
    bool required = false,
    bool readOnly = false,
    bool hidden = false,
    bool inListView = false,
    bool searchable = false,
    int sortOrder = 0,
    bool enabled = true,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    final entityId = id ?? _uuid.v4();
    database.db.execute('''
      INSERT INTO custom_fields(
        id, document_type, field_name, label, field_type, insert_after,
        options_json, default_value_json, required, read_only, hidden,
        in_list_view, searchable, sort_order, enabled, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        document_type = excluded.document_type,
        field_name = excluded.field_name,
        label = excluded.label,
        field_type = excluded.field_type,
        insert_after = excluded.insert_after,
        options_json = excluded.options_json,
        default_value_json = excluded.default_value_json,
        required = excluded.required,
        read_only = excluded.read_only,
        hidden = excluded.hidden,
        in_list_view = excluded.in_list_view,
        searchable = excluded.searchable,
        sort_order = excluded.sort_order,
        enabled = excluded.enabled,
        updated_at = excluded.updated_at;
    ''', [
      entityId,
      documentType.trim(),
      fieldName.trim(),
      label.trim(),
      fieldType.code,
      _nullable(insertAfter),
      jsonEncode(options),
      encodeJsonValue(defaultValue),
      required ? 1 : 0,
      readOnly ? 1 : 0,
      hidden ? 1 : 0,
      inListView ? 1 : 0,
      searchable ? 1 : 0,
      sortOrder,
      enabled ? 1 : 0,
      now,
      now,
    ]);
    return customFields().firstWhere((entry) => entry.id == entityId);
  }

  void deleteCustomField(String id) {
    final rows = database.db.select(
      'SELECT document_type, field_name FROM custom_fields WHERE id = ? LIMIT 1;',
      [id],
    );
    if (rows.isEmpty) return;
    final documentType = rows.first['document_type'] as String;
    final fieldName = rows.first['field_name'] as String;
    database.transaction(() {
      database.db.execute(
        'DELETE FROM custom_field_values WHERE document_type = ? AND field_name = ?;',
        [documentType, fieldName],
      );
      database.db.execute(
        'DELETE FROM property_overrides WHERE document_type = ? AND field_name = ?;',
        [documentType, fieldName],
      );
      database.db.execute('DELETE FROM custom_fields WHERE id = ?;', [id]);
    });
  }

  List<WmnPropertyOverride> propertyOverrides({String? documentType, bool enabledOnly = false}) {
    final clauses = <String>[];
    final args = <Object?>[];
    if (documentType != null && documentType.trim().isNotEmpty) {
      clauses.add('document_type = ?');
      args.add(documentType.trim());
    }
    if (enabledOnly) clauses.add('enabled = 1');
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    final rows = database.db.select('''
      SELECT * FROM property_overrides
      $where
      ORDER BY document_type, field_name, property_name;
    ''', args);
    return rows
        .map(
          (row) => WmnPropertyOverride(
            id: row['id'] as String,
            documentType: row['document_type'] as String,
            fieldName: row['field_name'] as String,
            propertyName: row['property_name'] as String,
            value: decodeJsonValue(row['value_json']),
            enabled: (row['enabled'] as int) == 1,
          ),
        )
        .toList(growable: false);
  }

  WmnPropertyOverride savePropertyOverride({
    String? id,
    required String documentType,
    required String fieldName,
    required String propertyName,
    required Object? value,
    bool enabled = true,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    final entityId = id ?? _uuid.v4();
    database.db.execute('''
      INSERT INTO property_overrides(
        id, document_type, field_name, property_name, value_json, enabled, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        document_type = excluded.document_type,
        field_name = excluded.field_name,
        property_name = excluded.property_name,
        value_json = excluded.value_json,
        enabled = excluded.enabled,
        updated_at = excluded.updated_at;
    ''', [
      entityId,
      documentType.trim(),
      fieldName.trim(),
      propertyName.trim(),
      jsonEncode(value),
      enabled ? 1 : 0,
      now,
      now,
    ]);
    return propertyOverrides().firstWhere((entry) => entry.id == entityId);
  }

  void deletePropertyOverride(String id) =>
      database.db.execute('DELETE FROM property_overrides WHERE id = ?;', [id]);

  Map<String, Object?> customValues(String documentType, String documentId) {
    final rows = database.db.select('''
      SELECT field_name, value_json
      FROM custom_field_values
      WHERE document_type = ? AND document_id = ?;
    ''', [documentType, documentId]);
    return {
      for (final row in rows) row['field_name'] as String: decodeJsonValue(row['value_json']),
    };
  }

  void saveCustomValues(String documentType, String documentId, Map<String, Object?> values) {
    final now = DateTime.now().toUtc().toIso8601String();
    database.transaction(() {
      for (final entry in values.entries) {
        database.db.execute('''
          INSERT INTO custom_field_values(document_type, document_id, field_name, value_json, updated_at)
          VALUES (?, ?, ?, ?, ?)
          ON CONFLICT(document_type, document_id, field_name) DO UPDATE SET
            value_json = excluded.value_json,
            updated_at = excluded.updated_at;
        ''', [documentType, documentId, entry.key, encodeJsonValue(entry.value), now]);
      }
    });
  }

  List<WmnClientScript> clientScripts({String? documentType, bool enabledOnly = false}) {
    final clauses = <String>[];
    final args = <Object?>[];
    if (documentType != null && documentType.trim().isNotEmpty) {
      clauses.add('document_type = ?');
      args.add(documentType.trim());
    }
    if (enabledOnly) clauses.add('enabled = 1');
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    final rows = database.db.select('''
      SELECT * FROM client_scripts
      $where
      ORDER BY document_type, priority DESC, name;
    ''', args);
    return rows
        .map(
          (row) => WmnClientScript(
            id: row['id'] as String,
            name: row['name'] as String,
            documentType: row['document_type'] as String,
            script: _readScript(row['source_storage_path']),
            priority: row['priority'] as int,
            enabled: (row['enabled'] as int) == 1,
          ),
        )
        .toList(growable: false);
  }

  WmnClientScript saveClientScript({
    String? id,
    required String name,
    required String documentType,
    required String script,
    int priority = 0,
    bool enabled = true,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    final entityId = id ?? _uuid.v4();
    final sourcePath = _scriptPath('client', documentType, entityId);
    storage.writeText(sourcePath, script);
    database.db.execute('''
      INSERT INTO client_scripts(id, name, document_type, source_storage_path, priority, enabled, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        document_type = excluded.document_type,
        source_storage_path = excluded.source_storage_path,
        priority = excluded.priority,
        enabled = excluded.enabled,
        updated_at = excluded.updated_at;
    ''', [entityId, name.trim(), documentType.trim(), sourcePath, priority, enabled ? 1 : 0, now, now]);
    return clientScripts().firstWhere((entry) => entry.id == entityId);
  }

  void deleteClientScript(String id) {
    final rows = database.db.select('SELECT source_storage_path FROM client_scripts WHERE id=? LIMIT 1;', [id]);
    if (rows.isNotEmpty) {
      final path = '${rows.first['source_storage_path'] ?? ''}'.trim();
      if (path.isNotEmpty && storage.exists(path)) storage.delete(path);
    }
    database.db.execute('DELETE FROM client_scripts WHERE id = ?;', [id]);
  }

  List<WmnServerScript> serverScripts({
    String? documentType,
    String? eventName,
    bool enabledOnly = false,
  }) {
    final clauses = <String>[];
    final args = <Object?>[];
    if (documentType != null && documentType.trim().isNotEmpty) {
      clauses.add('document_type = ?');
      args.add(documentType.trim());
    }
    if (eventName != null && eventName.trim().isNotEmpty) {
      clauses.add('event_name = ?');
      args.add(eventName.trim());
    }
    if (enabledOnly) clauses.add('enabled = 1');
    final where = clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}';
    final rows = database.db.select('''
      SELECT * FROM server_scripts
      $where
      ORDER BY script_type, priority DESC, name;
    ''', args);
    return rows
        .map(
          (row) => WmnServerScript(
            id: row['id'] as String,
            name: row['name'] as String,
            scriptType: row['script_type'] as String,
            documentType: row['document_type'] as String?,
            eventName: row['event_name'] as String?,
            apiMethod: row['api_method'] as String?,
            script: _readScript(row['source_storage_path']),
            priority: row['priority'] as int,
            enabled: (row['enabled'] as int) == 1,
          ),
        )
        .toList(growable: false);
  }

  WmnServerScript saveServerScript({
    String? id,
    required String name,
    String scriptType = 'DOCUMENT_EVENT',
    String? documentType,
    String? eventName,
    String? apiMethod,
    required String script,
    int priority = 0,
    bool enabled = true,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    final entityId = id ?? _uuid.v4();
    final sourcePath = _scriptPath('server', documentType ?? scriptType, entityId);
    storage.writeText(sourcePath, script);
    database.db.execute('''
      INSERT INTO server_scripts(
        id, name, script_type, document_type, event_name, api_method,
        source_storage_path, priority, enabled, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        script_type = excluded.script_type,
        document_type = excluded.document_type,
        event_name = excluded.event_name,
        api_method = excluded.api_method,
        source_storage_path = excluded.source_storage_path,
        priority = excluded.priority,
        enabled = excluded.enabled,
        updated_at = excluded.updated_at;
    ''', [
      entityId,
      name.trim(),
      scriptType,
      _nullable(documentType),
      _nullable(eventName),
      _nullable(apiMethod),
      sourcePath,
      priority,
      enabled ? 1 : 0,
      now,
      now,
    ]);
    return serverScripts().firstWhere((entry) => entry.id == entityId);
  }

  void deleteServerScript(String id) {
    final rows = database.db.select('SELECT source_storage_path FROM server_scripts WHERE id=? LIMIT 1;', [id]);
    if (rows.isNotEmpty) {
      final path = '${rows.first['source_storage_path'] ?? ''}'.trim();
      if (path.isNotEmpty && storage.exists(path)) storage.delete(path);
    }
    database.db.execute('DELETE FROM server_scripts WHERE id = ?;', [id]);
  }

  void logExecution({
    required String scriptKind,
    required String scriptName,
    String? scriptId,
    String? documentType,
    String? documentId,
    String? eventName,
    required String status,
    required int durationMs,
    List<String> messages = const [],
    String? errorText,
  }) {
    database.db.execute('''
      INSERT INTO script_execution_log(
        id, script_kind, script_id, script_name, document_type, document_id,
        event_name, status, duration_ms, messages_json, error_text, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    ''', [
      _uuid.v4(),
      scriptKind,
      scriptId,
      scriptName,
      documentType,
      documentId,
      eventName,
      status,
      durationMs,
      jsonEncode(messages),
      errorText,
      DateTime.now().toUtc().toIso8601String(),
    ]);
  }

  List<Map<String, Object?>> executionLogs({int limit = 200}) => database.db
      .select('''
        SELECT * FROM script_execution_log
        ORDER BY created_at DESC
        LIMIT ?;
      ''', [limit])
      .map((row) => Map<String, Object?>.from(row))
      .toList(growable: false);

  WmnCustomField _mapCustomField(dynamic row) => WmnCustomField(
        id: row['id'] as String,
        documentType: row['document_type'] as String,
        fieldName: row['field_name'] as String,
        label: row['label'] as String,
        fieldType: WmnCustomFieldType.fromCode(row['field_type'] as String),
        insertAfter: row['insert_after'] as String?,
        options: (jsonDecode(row['options_json'] as String) as List<dynamic>).map((entry) => '$entry').toList(growable: false),
        defaultValue: decodeJsonValue(row['default_value_json']),
        required: (row['required'] as int) == 1,
        readOnly: (row['read_only'] as int) == 1,
        hidden: (row['hidden'] as int) == 1,
        inListView: (row['in_list_view'] as int) == 1,
        searchable: (row['searchable'] as int) == 1,
        sortOrder: row['sort_order'] as int,
        enabled: (row['enabled'] as int) == 1,
      );

  String _readScript(Object? pathValue) {
    final path = '${pathValue ?? ''}'.trim();
    if (path.isEmpty || !storage.exists(path)) return '';
    return storage.readText(path);
  }

  String _scriptPath(String kind, String scope, String id) {
    final safeScope = scope.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9._-]+'), '_');
    return 'apps/custom/scripts/$kind/${safeScope.isEmpty ? 'global' : safeScope}/$id.wmn';
  }

  String? _nullable(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
