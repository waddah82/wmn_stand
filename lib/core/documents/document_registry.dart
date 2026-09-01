import 'dart:convert';

import '../database/sql_identifier.dart';
import '../database/wmn_database.dart';

class WmnDocumentDescriptor {
  const WmnDocumentDescriptor({
    required this.documentType,
    required this.tableName,
    required this.idField,
    required this.isSingle,
  });

  final String documentType;
  final String tableName;
  final String idField;
  final bool isSingle;
}

/// Low-level read registry for metadata-driven documents.
///
/// `wmn_doctypes` is the source of truth. Every active DocType uses one
/// physical SQLite table named `tab<DocType>`, matching Frappe's table naming
/// convention. Business services may still own write semantics for system
/// DocTypes, but reads resolve through the same metadata contract.
class WmnDocumentRegistry {
  const WmnDocumentRegistry(this.database);

  final WmnDatabase database;

  List<String> get documentTypes {
    if (!_tableExists('wmn_doctypes')) return const [];
    return database.db
        .select("SELECT name FROM wmn_doctypes WHERE enabled = 1 AND storage_mode = 'TABLE' ORDER BY name;")
        .map((row) => row['name'] as String)
        .toList(growable: false);
  }

  WmnDocumentDescriptor? descriptor(String documentType) {
    if (!_tableExists('wmn_doctypes')) return null;
    final rows = database.db.select(
      "SELECT name, table_name, id_field, is_single FROM wmn_doctypes WHERE name = ? AND enabled = 1 AND storage_mode = 'TABLE' LIMIT 1;",
      [documentType],
    );
    if (rows.isEmpty) return null;
    final table = rows.first['table_name'] as String?;
    if (table == null || table.trim().isEmpty || !_tableExists(table)) return null;
    return WmnDocumentDescriptor(
      documentType: rows.first['name'] as String,
      tableName: table,
      idField: rows.first['id_field'] as String? ?? 'name',
      isSingle: (rows.first['is_single'] as int? ?? 0) == 1,
    );
  }

  Set<String> standardFields(String documentType) {
    final entry = descriptor(documentType);
    if (entry == null) return const {};
    if (entry.isSingle) {
      return {'name', 'doctype', ..._singleFieldNames(documentType)};
    }
    final rows = database.db.select('PRAGMA table_info(${quoteSqlIdentifier(entry.tableName)});');
    return rows.map((row) => row['name'] as String).toSet();
  }

  Map<String, Object?>? readDocument(String documentType, String id) {
    final entry = descriptor(documentType);
    if (entry == null) return null;
    if (entry.isSingle) {
      if (id != documentType) return null;
      final result = <String, Object?>{'doctype': documentType, 'name': documentType, 'docstatus': 0};
      final rows = database.db.select(
        'SELECT field,value FROM [tabSingles] WHERE doctype = ? ORDER BY field;',
        [documentType],
      );
      for (final row in rows) {
        result[row['field'] as String] = _decodeJson(row['value']);
      }
      return result;
    }
    final table = quoteSqlIdentifier(entry.tableName);
    final idField = quoteSqlIdentifier(entry.idField);
    final rows = database.db.select(
      'SELECT * FROM $table WHERE $idField = ? LIMIT 1;',
      [id],
    );
    if (rows.isEmpty) return null;
    final result = Map<String, Object?>.from(rows.first);
    if (_hasCustomizationTables()) {
      final customRows = database.db.select('''
        SELECT field_name, value_json
        FROM custom_field_values
        WHERE document_type = ? AND document_id = ?;
      ''', [documentType, id]);
      for (final row in customRows) {
        result[row['field_name'] as String] = _decodeJson(row['value_json']);
      }
    }
    return result;
  }

  List<Map<String, Object?>> readList(
    String documentType, {
    List<String> fields = const [],
    List<Object?> filters = const [],
    int limit = 20,
    int offset = 0,
    String? orderBy,
    bool descending = false,
  }) {
    final entry = descriptor(documentType);
    if (entry == null) return const [];
    final standard = standardFields(documentType);
    final safeLimit = limit.clamp(1, 200).toInt();
    final safeOffset = offset < 0 ? 0 : offset;
    if (entry.isSingle) {
      if (safeOffset > 0) return const [];
      final document = readDocument(documentType, documentType);
      if (document == null || !_matchesDocument(document, filters)) return const [];
      final requestedFields = fields.where(isSafeFieldIdentifier).toSet();
      if (requestedFields.isEmpty) return [document];
      return [<String, Object?>{
        'name': documentType,
        for (final field in requestedFields)
          if (document.containsKey(field)) field: document[field],
      }];
    }
    final where = _whereClause(filters, standard);
    final requestedOrder = orderBy?.trim();
    final safeOrder = requestedOrder != null && standard.contains(requestedOrder)
        ? requestedOrder
        : entry.idField;
    final table = quoteSqlIdentifier(entry.tableName);
    final idField = quoteSqlIdentifier(entry.idField);
    final order = quoteSqlIdentifier(safeOrder);
    final rows = database.db.select(
      'SELECT $idField FROM $table${where.sql} '
      'ORDER BY $order ${descending ? 'DESC' : 'ASC'} LIMIT ? OFFSET ?;',
      [...where.args, safeLimit, safeOffset],
    );

    final requestedFields = fields.where(isSafeFieldIdentifier).toSet();
    return rows.map((row) {
      final id = '${row[entry.idField]}';
      final document = readDocument(documentType, id) ?? <String, Object?>{entry.idField: id};
      if (requestedFields.isEmpty) return document;
      return <String, Object?>{
        for (final field in requestedFields)
          if (document.containsKey(field)) field: document[field],
      };
    }).toList(growable: false);
  }

  int count(String documentType, {List<Object?> filters = const []}) {
    final entry = descriptor(documentType);
    if (entry == null) return 0;
    if (entry.isSingle) {
      final document = readDocument(documentType, documentType);
      return document != null && _matchesDocument(document, filters) ? 1 : 0;
    }
    final where = _whereClause(filters, standardFields(documentType));
    final rows = database.db.select(
      'SELECT COUNT(*) AS value FROM ${quoteSqlIdentifier(entry.tableName)}${where.sql};',
      where.args,
    );
    return rows.isEmpty ? 0 : (rows.first['value'] as int? ?? 0);
  }

  Object? readValue(String documentType, String id, String fieldName) {
    if (!isSafeFieldIdentifier(fieldName)) return null;
    final entry = descriptor(documentType);
    if (entry == null) return null;
    if (entry.isSingle) {
      if (id != documentType) return null;
      return readDocument(documentType, documentType)?[fieldName];
    }
    if (standardFields(documentType).contains(fieldName)) {
      final rows = database.db.select(
        'SELECT ${quoteSqlIdentifier(fieldName)} AS value FROM ${quoteSqlIdentifier(entry.tableName)} '
        'WHERE ${quoteSqlIdentifier(entry.idField)} = ? LIMIT 1;',
        [id],
      );
      if (rows.isEmpty) return null;
      return rows.first['value'];
    }
    if (!_hasCustomizationTables()) return null;
    final rows = database.db.select('''
      SELECT value_json
      FROM custom_field_values
      WHERE document_type = ? AND document_id = ? AND field_name = ?
      LIMIT 1;
    ''', [documentType, id, fieldName]);
    if (rows.isEmpty) return null;
    return _decodeJson(rows.first['value_json']);
  }

  bool exists(String documentType, String id) => readDocument(documentType, id) != null;

  _WhereClause _whereClause(List<Object?> filters, Set<String> standardFields) {
    final clauses = <String>[];
    final args = <Object?>[];
    for (final rawFilter in filters) {
      if (rawFilter is! List || rawFilter.length < 3) continue;
      final field = '${rawFilter[0]}';
      final operator = '${rawFilter[1]}'.trim().toUpperCase();
      final value = rawFilter[2];
      if (!isSafeFieldIdentifier(field) || !standardFields.contains(field)) continue;
      final identifier = quoteSqlIdentifier(field);
      switch (operator) {
        case '=':
        case '!=':
        case '>':
        case '>=':
        case '<':
        case '<=':
        case 'LIKE':
          clauses.add('$identifier $operator ?');
          args.add(value);
          break;
        case 'IN':
          if (value is List && value.isNotEmpty) {
            clauses.add('$identifier IN (${List.filled(value.length, '?').join(',')})');
            args.addAll(value);
          }
          break;
      }
    }
    return _WhereClause(
      sql: clauses.isEmpty ? '' : ' WHERE ${clauses.join(' AND ')}',
      args: args,
    );
  }


  Set<String> _singleFieldNames(String documentType) {
    if (!_tableExists('wmn_doctype_fields')) return const {};
    return database.db
        .select('SELECT fieldname FROM wmn_doctype_fields WHERE doctype = ? ORDER BY idx, fieldname;', [documentType])
        .map((row) => row['fieldname'] as String)
        .toSet();
  }

  bool _matchesDocument(Map<String, Object?> document, List<Object?> filters) {
    for (final rawFilter in filters) {
      if (rawFilter is! List || rawFilter.length < 3) continue;
      final field = '${rawFilter[0]}';
      final operator = '${rawFilter[1]}'.trim().toUpperCase();
      final expected = rawFilter[2];
      final actual = document[field];
      if (!_matchesValue(actual, operator, expected)) return false;
    }
    return true;
  }

  bool _matchesValue(Object? actual, String operator, Object? expected) {
    bool same(Object? a, Object? b) {
      if (a == b) return true;
      if (a is num && b is num) return a.toDouble() == b.toDouble();
      return '${a ?? ''}' == '${b ?? ''}';
    }

    switch (operator) {
      case '=':
      case '==':
        return same(actual, expected);
      case '!=':
        return !same(actual, expected);
      case 'LIKE':
        final pattern = '${expected ?? ''}'.replaceAll('%', '').toLowerCase();
        return '${actual ?? ''}'.toLowerCase().contains(pattern);
      case 'IN':
        return expected is List && expected.any((value) => same(actual, value));
      case '>':
      case '>=':
      case '<':
      case '<=':
        final left = actual is num ? actual.toDouble() : double.tryParse('${actual ?? ''}');
        final right = expected is num ? expected.toDouble() : double.tryParse('${expected ?? ''}');
        if (left == null || right == null) return false;
        return switch (operator) {
          '>' => left > right,
          '>=' => left >= right,
          '<' => left < right,
          '<=' => left <= right,
          _ => false,
        };
      default:
        return false;
    }
  }

  bool _hasCustomizationTables() => _tableExists('custom_field_values');

  bool _tableExists(String name) => database.db.select(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;",
        [name],
      ).isNotEmpty;

  Object? _decodeJson(Object? value) {
    if (value == null || value is! String || value.isEmpty) return value;
    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }
}

class _WhereClause {
  const _WhereClause({required this.sql, required this.args});

  final String sql;
  final List<Object?> args;
}
