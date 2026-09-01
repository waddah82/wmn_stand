import 'dart:convert';

import '../../core/database/wmn_database.dart';
import '../meta/meta_service.dart';
import '../model/document_service.dart';
import 'frappe_permissions.dart';
import 'frappe_session.dart';

class WmnFrappeDbApi {
  WmnFrappeDbApi({
    required this.database,
    required this.meta,
    required this.documents,
    required this.permissions,
    required this.session,
  });

  final WmnDatabase database;
  final WmnMetaService meta;
  final WmnDocumentService documents;
  final WmnFrappePermissionEngine permissions;
  final WmnFrappeSession session;

  Map<String, Object?>? getValue(
    String doctype,
    Object selector,
    Object fields, {
    bool ignorePermissions = false,
  }) {
    if (!ignorePermissions && !permissions.hasPermission(doctype, 'read')) return null;
    final fieldNames = _fields(fields);
    if (fieldNames.isEmpty) return null;
    Map<String, Object?>? doc;
    if (selector is Map) {
      final page = getList(
        doctype,
        fields: <String>{'name', ...fieldNames}.toList(growable: false),
        filters: _filters(selector),
        limit: 1,
        ignorePermissions: ignorePermissions,
      );
      doc = page.isEmpty ? null : page.first;
    } else {
      doc = documents.get(doctype, '$selector');
    }
    if (doc == null) return null;
    return <String, Object?>{for (final field in fieldNames) field: doc[field]};
  }

  Object? getSingleValue(String doctype, String fieldname) {
    if (!permissions.hasPermission(doctype, 'read') && meta.doctype(doctype) != null) return null;
    final rows = database.db.select(
      'SELECT value FROM [tabSingles] WHERE doctype=? AND field=? LIMIT 1;',
      [doctype, fieldname],
    );
    if (rows.isEmpty) return null;
    final value = rows.first['value'] as String?;
    if (value == null) return null;
    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }

  void setSingleValue(String doctype, String fieldname, Object? value) {
    final dt = meta.doctype(doctype);
    if (dt != null && !dt.isSingle) throw StateError('$doctype is not a Single DocType.');
    if (dt != null && !permissions.hasPermission(doctype, 'write')) {
      throw StateError('Not permitted to write $doctype.');
    }
    if (dt != null && fieldname != 'modified' && fieldname != 'modified_by' && dt.field(fieldname) == null) {
      throw StateError('Unknown field $doctype.$fieldname.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    database.transaction(() {
      _upsertSingleValue(doctype, fieldname, value, now);
      _upsertSingleValue(doctype, 'modified', now, now);
      _upsertSingleValue(doctype, 'modified_by', session.user, now);
    });
  }

  Map<String, Object?> getSingle(String doctype) {
    final dt = meta.doctype(doctype);
    if (dt != null && !dt.isSingle) throw StateError('$doctype is not a Single DocType.');
    final stored = documents.get(doctype, doctype);
    if (stored != null) return <String, Object?>{'doctype': doctype, ...stored};
    return <String, Object?>{'doctype': doctype, 'name': doctype};
  }

  void _upsertSingleValue(String doctype, String fieldname, Object? value, String now) {
    database.db.execute('''
      INSERT INTO [tabSingles](doctype,field,value,updated_at)
      VALUES (?,?,?,?)
      ON CONFLICT(doctype,field) DO UPDATE SET value=excluded.value,updated_at=excluded.updated_at;
    ''', [doctype, fieldname, value == null ? null : jsonEncode(value), now]);
  }

  List<Map<String, Object?>> getValues(
    String doctype,
    Object? filters,
    Object fields, {
    int limit = 500,
    bool ignorePermissions = false,
  }) {
    return getList(
      doctype,
      fields: _fields(fields),
      filters: filters,
      limit: limit,
      ignorePermissions: ignorePermissions,
    );
  }

  int bulkUpdate(
    String doctype,
    Map<String, Map<String, Object?>> valuesByName, {
    bool ignorePermissions = false,
  }) {
    var updated = 0;
    database.transaction(() {
      for (final entry in valuesByName.entries) {
        if (!ignorePermissions && !permissions.hasPermission(doctype, 'write', docname: entry.key)) {
          throw StateError('Not permitted to write $doctype ${entry.key}.');
        }
        if (ignorePermissions) {
          final existing = documents.get(doctype, entry.key);
          if (existing == null) throw StateError('$doctype ${entry.key} does not exist.');
          final next = Map<String, Object?>.from(existing)..addAll(entry.value);
          documents.save(doctype, next, existingName: entry.key);
        } else {
          setValue(doctype, entry.key, entry.value);
        }
        updated += 1;
      }
    });
    return updated;
  }

  Map<String, Object?>? getLastDoc(
    String doctype, {
    Object? filters,
    String orderBy = 'modified desc',
    bool ignorePermissions = false,
  }) {
    final rows = getList(
      doctype,
      filters: filters,
      orderBy: orderBy,
      limit: 1,
      ignorePermissions: ignorePermissions,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Map<String, Object?> setValue(String doctype, String name, Object fields, [Object? value]) {
    if (!permissions.hasPermission(doctype, 'write', docname: name)) {
      throw StateError('Not permitted to write $doctype $name.');
    }
    final existing = documents.get(doctype, name);
    if (existing == null) throw StateError('$doctype $name does not exist.');
    final updates = fields is Map
        ? <String, Object?>{for (final entry in fields.entries) '${entry.key}': entry.value}
        : <String, Object?>{'$fields': value};
    final next = Map<String, Object?>.from(existing)..addAll(updates);
    return documents.save(doctype, next, existingName: name);
  }

  List<Map<String, Object?>> getList(
    String doctype, {
    List<String> fields = const [],
    Object? filters,
    String? search,
    String? orderBy,
    int limit = 20,
    int offset = 0,
    bool ignorePermissions = false,
  }) {
    if (!ignorePermissions && !permissions.hasPermission(doctype, 'read')) return const [];
    final parsedOrder = _order(orderBy);
    final page = documents.list(
      doctype,
      filters: _filters(filters),
      search: search,
      fields: fields,
      sortField: parsedOrder.$1,
      descending: parsedOrder.$2,
      limit: limit.clamp(1, 500).toInt(),
      offset: offset < 0 ? 0 : offset,
    );
    return page.rows;
  }

  List<Map<String, Object?>> getAll(
    String doctype, {
    List<String> fields = const [],
    Object? filters,
    String? orderBy,
    int limit = 500,
    int offset = 0,
  }) =>
      getList(
        doctype,
        fields: fields,
        filters: filters,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
        ignorePermissions: true,
      );

  int count(String doctype, {Object? filters, bool ignorePermissions = false}) {
    if (!ignorePermissions && !permissions.hasPermission(doctype, 'read')) return 0;
    return documents.list(doctype, filters: _filters(filters), limit: 1, offset: 0).total;
  }

  bool exists(String doctype, Object selector, {bool ignorePermissions = false}) {
    if (!ignorePermissions && !permissions.hasPermission(doctype, 'read')) return false;
    if (selector is Map) {
      return documents.list(doctype, filters: _filters(selector), limit: 1).rows.isNotEmpty;
    }
    return documents.exists(doctype, '$selector');
  }

  void delete(String doctype, Object? filters, {bool ignorePermissions = false}) {
    if (!ignorePermissions && !permissions.hasPermission(doctype, 'delete')) {
      throw StateError('Not permitted to delete $doctype.');
    }
    final rows = getList(
      doctype,
      fields: const ['name'],
      filters: filters,
      limit: 500,
      ignorePermissions: true,
    );
    final dt = meta.doctype(doctype);
    if (dt == null) throw StateError('Unknown DocType: $doctype');
    for (final row in rows) {
      final name = '${row['name'] ?? row[dt.idField] ?? ''}';
      if (name.isNotEmpty) documents.delete(doctype, name);
    }
  }

  List<String> _fields(Object value) {
    if (value is List) return value.map((entry) => '$entry').where((entry) => entry.isNotEmpty).toList(growable: false);
    final text = '$value'.trim();
    return text.isEmpty ? const [] : <String>[text];
  }

  List<List<Object?>> _filters(Object? raw) {
    if (raw == null) return const [];
    if (raw is Map) {
      return raw.entries.map((entry) => <Object?>['${entry.key}', '=', entry.value]).toList(growable: false);
    }
    if (raw is List) {
      final result = <List<Object?>>[];
      for (final entry in raw) {
        if (entry is List && entry.length >= 3) result.add(List<Object?>.from(entry));
      }
      return result;
    }
    return const [];
  }

  (String?, bool) _order(String? orderBy) {
    final text = orderBy?.trim();
    if (text == null || text.isEmpty) return (null, true);
    final parts = text.split(RegExp(r'\s+'));
    return (parts.first, parts.length > 1 && parts[1].toLowerCase() == 'desc');
  }
}
