import 'frappe_db_api.dart';

class WmnFrappeQuerySpec {
  const WmnFrappeQuerySpec({
    required this.doctype,
    this.fields = const [],
    this.filters = const [],
    this.orderBy,
    this.limit = 20,
    this.offset = 0,
  });

  final String doctype;
  final List<String> fields;
  final Object filters;
  final String? orderBy;
  final int limit;
  final int offset;
}

/// Structured replacement for the common `frappe.qb` / `frappe.db.sql` use
/// cases. It deliberately does not expose arbitrary SQL. More advanced joins
/// and expressions are added as native WMN query operators rather than by
/// executing application-provided SQL text.
class WmnFrappeQueryEngine {
  const WmnFrappeQueryEngine(this.db);

  final WmnFrappeDbApi db;

  List<Map<String, Object?>> select(WmnFrappeQuerySpec query, {bool ignorePermissions = false}) => db.getList(
        query.doctype,
        fields: query.fields,
        filters: query.filters,
        orderBy: query.orderBy,
        limit: query.limit,
        offset: query.offset,
        ignorePermissions: ignorePermissions,
      );

  int count(String doctype, {Object filters = const []}) => db.count(doctype, filters: filters);

  num sum(String doctype, String field, {Object filters = const []}) {
    final rows = db.getList(doctype, fields: ['name', field], filters: filters, limit: 500);
    num result = 0;
    for (final row in rows) {
      final value = row[field];
      if (value is num) {
        result += value;
      } else if (value != null) {
        result += num.tryParse('$value') ?? 0;
      }
    }
    return result;
  }

  int update(String doctype, Map<String, Object?> values, {Object filters = const []}) {
    final rows = db.getList(doctype, fields: const ['name'], filters: filters, limit: 500);
    var changed = 0;
    for (final row in rows) {
      final name = '${row['name'] ?? ''}';
      if (name.isEmpty) continue;
      db.setValue(doctype, name, values);
      changed++;
    }
    return changed;
  }

  int delete(String doctype, {Object filters = const []}) {
    final countBefore = db.count(doctype, filters: filters);
    db.delete(doctype, filters);
    return countBefore;
  }
}
