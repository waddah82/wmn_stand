import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/database/wmn_database.dart';
import '../../../platform/storage/wmn_storage_service.dart';
import '../domain/report_models.dart';
import 'query_report_service.dart';
import 'report_builder_service.dart';
import 'script_report_service.dart';

class WmnFrappeReportDefinition {
  const WmnFrappeReportDefinition({
    required this.name,
    required this.reportName,
    required this.reportType,
    required this.module,
    this.referenceDocType,
    this.scriptKey,
    this.queryDefinition = const {},
    this.filters = const [],
    this.columns = const [],
    this.disabled = false,
    this.isStandard = false,
    this.querySourceType = 'INLINE',
    this.querySourcePath,
    this.scriptSourceType = 'NATIVE_HANDLER',
    this.scriptSourcePath,
    this.scriptLanguage,
    this.metadata = const <String, Object?>{},
  });

  final String name;
  final String reportName;
  final String reportType;
  final String module;
  final String? referenceDocType;
  final String? scriptKey;
  final Map<String, Object?> queryDefinition;
  final List<Map<String, Object?>> filters;
  final List<Map<String, Object?>> columns;
  final bool disabled;
  final bool isStandard;
  final String querySourceType;
  final String? querySourcePath;
  final String scriptSourceType;
  final String? scriptSourcePath;
  final String? scriptLanguage;
  final Map<String, Object?> metadata;
}

class WmnFrappeReportExecution {
  const WmnFrappeReportExecution({
    required this.columns,
    required this.rows,
    required this.durationMs,
    this.message,
    this.summary = const [],
  });

  final List<Map<String, Object?>> columns;
  final List<Map<String, Object?>> rows;
  final int durationMs;
  final String? message;
  final List<Map<String, Object?>> summary;
}

/// Single Report DocType dispatcher.
///
/// Report metadata is always read from tabReport. Query/script source content
/// can be externalized into WMN Storage while tabReport retains only the
/// source reference, filters, columns, permissions-related metadata and type.
class WmnFrappeReportService {
  WmnFrappeReportService({
    required this.database,
    required this.reportBuilder,
    required this.queryReports,
    required this.scriptReports,
    WmnStorageService? storage,
    this.isFeatureEnabled,
    this.canReportOnDocType,
  }) : storage = storage ?? scriptReports.storage;

  final WmnDatabase database;
  final ReportBuilderService reportBuilder;
  final WmnQueryReportService queryReports;
  final WmnScriptReportService scriptReports;
  final WmnStorageService storage;
  final bool Function(String featureCode)? isFeatureEnabled;
  final bool Function(String doctype)? canReportOnDocType;
  static const Uuid _uuid = Uuid();

  WmnFrappeReportDefinition? definition(String name) {
    final rows = database.db.select(
      'SELECT * FROM [tabReport] WHERE name = ? OR report_name = ? LIMIT 1;',
      [name, name],
    );
    if (rows.isEmpty) return null;
    return _definition(rows.first);
  }

  List<WmnFrappeReportDefinition> definitions({String? module, bool includeDisabled = false}) {
    final clauses = <String>[];
    final args = <Object?>[];
    if (module != null && module.trim().isNotEmpty) {
      clauses.add('module = ?');
      args.add(module.trim());
    }
    if (!includeDisabled) clauses.add('disabled = 0');
    final rows = database.db.select('''
      SELECT * FROM [tabReport]
      ${clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}'}
      ORDER BY module COLLATE NOCASE, report_name COLLATE NOCASE;
    ''', args);
    return rows.map(_definition).toList(growable: false);
  }

  void saveDefinition(WmnFrappeReportDefinition definition) {
    if (!const {'Report Builder', 'Query Report', 'Script Report', 'Custom Report'}.contains(definition.reportType)) {
      throw StateError('Unsupported Frappe report type: ${definition.reportType}.');
    }
    final existing = this.definition(definition.name);
    final queryDefinition = <String, Object?>{...definition.queryDefinition};
    var querySourceType = definition.querySourceType;
    var querySourcePath = definition.querySourcePath;
    var scriptSourceType = definition.scriptSourceType;
    var scriptSourcePath = definition.scriptSourcePath;
    var scriptLanguage = definition.scriptLanguage;
    var scriptKey = definition.scriptKey;

    if (definition.reportType == 'Query Report') {
      final inlineSql = '${queryDefinition['sql'] ?? queryDefinition['query'] ?? ''}'.trim();
      if (inlineSql.isNotEmpty) {
        querySourcePath ??= _queryPath(definition.module, definition.reportName);
        storage.writeText(querySourcePath, inlineSql);
        querySourceType = 'STORAGE_FILE';
        queryDefinition.remove('sql');
        queryDefinition.remove('query');
        queryDefinition.remove('raw_sql');
      } else if (existing != null && querySourcePath == null) {
        querySourceType = existing.querySourceType;
        querySourcePath = existing.querySourcePath;
      }
    }

    if (definition.reportType == 'Script Report' && existing != null) {
      if (definition.scriptSourceType == 'NATIVE_HANDLER' && definition.scriptSourcePath == null && definition.scriptLanguage == null) {
        scriptSourceType = existing.scriptSourceType;
        scriptSourcePath = existing.scriptSourcePath;
        scriptLanguage = existing.scriptLanguage;
      }
      scriptKey ??= existing.scriptKey;
    }

    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO [tabReport](
        name,report_name,ref_doctype,report_type,module,is_standard,disabled,
        query_definition_json,script_key,filters_json,columns_json,metadata_json,
        created_at,updated_at,query_source_type,query_source_path,
        script_source_type,script_source_path,script_language
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(name) DO UPDATE SET
        report_name=excluded.report_name,ref_doctype=excluded.ref_doctype,
        report_type=excluded.report_type,module=excluded.module,is_standard=excluded.is_standard,
        disabled=excluded.disabled,query_definition_json=excluded.query_definition_json,
        script_key=excluded.script_key,filters_json=excluded.filters_json,
        columns_json=excluded.columns_json,metadata_json=excluded.metadata_json,
        query_source_type=excluded.query_source_type,query_source_path=excluded.query_source_path,
        script_source_type=excluded.script_source_type,script_source_path=excluded.script_source_path,
        script_language=excluded.script_language,updated_at=excluded.updated_at;
    ''', [
      existing?.name ?? definition.name,
      definition.reportName,
      definition.referenceDocType,
      definition.reportType,
      definition.module,
      definition.isStandard ? 1 : 0,
      definition.disabled ? 1 : 0,
      jsonEncode(queryDefinition),
      scriptKey,
      jsonEncode(definition.filters),
      jsonEncode(definition.columns),
      jsonEncode(definition.metadata),
      now,
      now,
      querySourceType,
      querySourcePath,
      scriptSourceType,
      scriptSourcePath,
      scriptLanguage,
    ]);
    _replaceReportChildren(
      existing?.name ?? definition.name,
      filters: definition.filters,
      columns: definition.columns,
    );

  }

  int normalizeSources({String? reportName}) {
    final rows = reportName == null
        ? database.db.select("SELECT * FROM [tabReport] WHERE report_type='Query Report';")
        : database.db.select(
            "SELECT * FROM [tabReport] WHERE report_type='Query Report' AND (name=? OR report_name=?);",
            [reportName, reportName],
          );
    var changed = 0;
    for (final row in rows) {
      final definition = _decodeMap(row['query_definition_json'] as String?);
      final sql = '${definition['sql'] ?? definition['query'] ?? definition['raw_sql'] ?? ''}'.trim();
      if (sql.isEmpty) continue;
      final existingPath = row['query_source_path'] as String?;
      final path = (existingPath?.trim().isNotEmpty ?? false)
          ? existingPath!.trim()
          : _queryPath('${row['module'] ?? 'Custom'}', '${row['report_name']}');
      storage.writeText(path, sql);
      definition.remove('sql');
      definition.remove('query');
      definition.remove('raw_sql');
      database.db.execute('''
        UPDATE [tabReport]
        SET query_definition_json=?,query_source_type='STORAGE_FILE',query_source_path=?,updated_at=?
        WHERE name=?;
      ''', [
        jsonEncode(definition),
        path,
        DateTime.now().toUtc().toIso8601String(),
        row['name'],
      ]);
      changed++;
    }
    return changed;
  }

  WmnFrappeReportExecution execute(String name, {Map<String, Object?> filters = const {}}) {
    normalizeSources(reportName: name);
    final report = definition(name);
    if (report == null) throw StateError('Unknown report: $name.');
    if (report.disabled) throw StateError('Report is disabled: ${report.reportName}.');
    final ref = report.referenceDocType?.trim();
    if (ref != null && ref.isNotEmpty && canReportOnDocType?.call(ref) == false) {
      throw StateError('Not permitted to run reports on $ref.');
    }
    if (report.reportType == 'Report Builder') {
      // ReportBuilderService owns its detailed run log to avoid duplicate rows.
      return _applyCurrentColumnMetadata(report, _executeStructured(report, filters));
    }
    if (report.reportType == 'Custom Report') {
      final parent = '${report.queryDefinition['parent_report'] ?? ''}'.trim();
      if (parent.isEmpty) throw StateError('Custom Report ${report.reportName} has no parent report.');
      return execute(parent, filters: filters);
    }

    final started = DateTime.now();
    try {
      final WmnFrappeReportExecution result;
      if (report.reportType == 'Script Report') {
        _requireFeature('reports.script');
        final scriptResult = scriptReports.execute(report.name, filters: filters);
        result = WmnFrappeReportExecution(
          columns: scriptResult.columns.map((entry) => entry.toJson()).toList(growable: false),
          rows: scriptResult.rows,
          durationMs: scriptResult.durationMs,
          message: scriptResult.message,
          summary: scriptResult.summary,
        );
      } else if (report.reportType == 'Query Report') {
        _requireFeature('reports.query');
        result = _executeQuery(report, filters);
      } else {
        throw StateError('Unsupported report type: ${report.reportType}.');
      }
      final resolvedResult = _applyCurrentColumnMetadata(report, result);
      _logRun(
        report,
        status: 'SUCCESS',
        rowCount: resolvedResult.rows.length,
        durationMs: resolvedResult.durationMs,
      );
      return resolvedResult;
    } catch (error) {
      _logRun(
        report,
        status: 'ERROR',
        durationMs: DateTime.now().difference(started).inMilliseconds,
        errorText: error.toString(),
      );
      rethrow;
    }
  }

  WmnFrappeReportExecution _applyCurrentColumnMetadata(
    WmnFrappeReportDefinition report,
    WmnFrappeReportExecution execution,
  ) {
    if (report.columns.isEmpty) return execution;
    final declared = <String, Map<String, Object?>>{};
    for (final column in report.columns) {
      final key = '${column['fieldname'] ?? column['field'] ?? column['name'] ?? ''}'.trim();
      if (key.isNotEmpty) declared[key] = column;
    }
    if (declared.isEmpty) return execution;
    final sourceColumns = execution.columns.isEmpty ? report.columns : execution.columns;
    final resolvedColumns = sourceColumns.map((column) {
      final key = '${column['fieldname'] ?? column['field'] ?? column['name'] ?? ''}'.trim();
      final metadata = declared[key];
      if (metadata == null) return Map<String, Object?>.from(column);
      return <String, Object?>{...column, ...metadata, 'fieldname': key};
    }).toList(growable: false);
    return WmnFrappeReportExecution(
      columns: resolvedColumns,
      rows: execution.rows,
      durationMs: execution.durationMs,
      message: execution.message,
      summary: execution.summary,
    );
  }

  WmnFrappeReportExecution _executeQuery(
    WmnFrappeReportDefinition report,
    Map<String, Object?> runtimeFilters,
  ) {
    var sql = '';
    if (report.querySourceType == 'STORAGE_FILE') {
      final path = report.querySourcePath?.trim() ?? '';
      if (path.isEmpty) throw StateError('Query Report ${report.reportName} has no query source path.');
      sql = storage.readText(path).trim();
    } else {
      sql = '${report.queryDefinition['sql'] ?? report.queryDefinition['query'] ?? ''}'.trim();
    }
    if (sql.isEmpty) return _executeStructured(report, runtimeFilters);
    final rawMaxRows = report.queryDefinition['max_rows'];
    final maxRows = rawMaxRows is num ? rawMaxRows.toInt() : WmnQueryReportService.defaultMaxRows;
    final result = queryReports.execute(
      sql: sql,
      filters: runtimeFilters,
      declaredFilters: report.filters,
      declaredColumns: report.columns,
      maxRows: maxRows,
    );
    return WmnFrappeReportExecution(
      columns: result.columns,
      rows: result.rows,
      durationMs: result.durationMs,
      message: result.truncated ? 'Result limited to ${result.rows.length} rows.' : null,
    );
  }

  void _logRun(
    WmnFrappeReportDefinition report, {
    required String status,
    int rowCount = 0,
    int durationMs = 0,
    String? errorText,
  }) {
    database.db.execute('''
      INSERT INTO report_run_log(
        id,report_id,report_name,status,row_count,duration_ms,error_text,created_at
      ) VALUES (?,?,?,?,?,?,?,?);
    ''', [
      _uuid.v4(),
      report.name,
      report.reportName,
      status,
      rowCount,
      durationMs,
      errorText,
      DateTime.now().toUtc().toIso8601String(),
    ]);
  }

  void _requireFeature(String code) {
    if (isFeatureEnabled?.call(code) == false) {
      throw StateError('Feature is not enabled: $code.');
    }
  }

  WmnFrappeReportExecution _executeStructured(
    WmnFrappeReportDefinition report,
    Map<String, Object?> runtimeFilters,
  ) {
    if (_containsRawSql(report.queryDefinition)) {
      throw StateError('Raw SQL report ${report.reportName} requires Query Report storage execution.');
    }
    WmnReportDefinition? builder = reportBuilder.report(report.name);
    final builderId = '${report.queryDefinition['builder_report_id'] ?? ''}'.trim();
    if (builder == null && builderId.isNotEmpty) builder = reportBuilder.report(builderId);
    if (builder == null) {
      throw StateError('${report.reportType} ${report.reportName} requires a structured WMN report definition.');
    }
    final result = reportBuilder.run(builder, runtimeFilters: runtimeFilters);
    return WmnFrappeReportExecution(
      columns: result.columns
          .map((label) => <String, Object?>{'label': label, 'fieldname': label, 'fieldtype': 'Data'})
          .toList(growable: false),
      rows: result.rows,
      durationMs: result.durationMs,
    );
  }

  WmnFrappeReportDefinition _definition(dynamic row) {
    final queryDefinition = _decodeMap(row['query_definition_json'] as String?);
    var filters = _reportFilterRows('${row['name']}');
    var columns = _reportColumnRows('${row['name']}');
    if (filters.isEmpty) filters = _decodeList(row['filters_json'] as String?);
    if (columns.isEmpty) columns = _decodeList(row['columns_json'] as String?);
    if ('${row['report_type']}' == 'Report Builder') {
      if (filters.isEmpty) filters = _builderFilters(queryDefinition);
      if (columns.isEmpty) columns = _builderColumns(queryDefinition);
    }
    return WmnFrappeReportDefinition(
      name: row['name'] as String,
      reportName: row['report_name'] as String,
      referenceDocType: row['ref_doctype'] as String?,
      reportType: row['report_type'] as String,
      module: row['module'] as String,
      scriptKey: row['script_key'] as String?,
      queryDefinition: queryDefinition,
      filters: filters,
      columns: columns,
      disabled: (row['disabled'] as int? ?? 0) == 1,
      isStandard: (row['is_standard'] as int? ?? 0) == 1,
      querySourceType: '${row['query_source_type'] ?? 'INLINE'}',
      querySourcePath: row['query_source_path'] as String?,
      scriptSourceType: '${row['script_source_type'] ?? 'NATIVE_HANDLER'}',
      scriptSourcePath: row['script_source_path'] as String?,
      scriptLanguage: row['script_language'] as String?,
      metadata: _decodeMap(row['metadata_json'] as String?),
    );
  }

  List<Map<String, Object?>> _reportFilterRows(String reportName) {
    if (!_tableExists('tabReport Filter')) return const <Map<String, Object?>>[];
    final rows = database.db.select(
      '''SELECT fieldname,label,label_ar,fieldtype,options,required,"default",depends_on,
                user_editable,source_field,operator,idx
         FROM [tabReport Filter]
         WHERE parent=? AND parenttype='Report' AND parentfield='filters'
         ORDER BY idx,name;''',
      <Object?>[reportName],
    );
    return rows.map((row) => <String, Object?>{
      'fieldname': row['fieldname'],
      'label': row['label'],
      if (row['label_ar'] != null) 'label_ar': row['label_ar'],
      'fieldtype': row['fieldtype'] ?? 'Data',
      if (row['options'] != null) 'options': row['options'],
      'required': (row['required'] as int? ?? 0) == 1,
      if (row['default'] != null) 'default': row['default'],
      if (row['depends_on'] != null) 'depends_on': row['depends_on'],
      'user_editable': (row['user_editable'] as int? ?? 1) == 1,
      if (row['source_field'] != null) 'source_field': row['source_field'],
      if (row['operator'] != null) 'operator': row['operator'],
    }).toList(growable: false);
  }

  List<Map<String, Object?>> _reportColumnRows(String reportName) {
    if (!_tableExists('tabReport Column')) return const <Map<String, Object?>>[];
    final rows = database.db.select(
      '''SELECT fieldname,label,label_ar,fieldtype,options,width,precision,alignment,
                aggregate,hidden,idx
         FROM [tabReport Column]
         WHERE parent=? AND parenttype='Report' AND parentfield='columns'
         ORDER BY idx,name;''',
      <Object?>[reportName],
    );
    return rows.map((row) => <String, Object?>{
      'fieldname': row['fieldname'],
      'label': row['label'],
      if (row['label_ar'] != null) 'label_ar': row['label_ar'],
      'fieldtype': row['fieldtype'] ?? 'Data',
      if (row['options'] != null) 'options': row['options'],
      if (row['width'] != null) 'width': row['width'],
      if (row['precision'] != null) 'precision': row['precision'],
      if (row['alignment'] != null) 'alignment': row['alignment'],
      if (row['aggregate'] != null) 'aggregate': row['aggregate'],
      'hidden': (row['hidden'] as int? ?? 0) == 1,
    }).toList(growable: false);
  }

  void _replaceReportChildren(
    String reportName, {
    required List<Map<String, Object?>> filters,
    required List<Map<String, Object?>> columns,
  }) {
    if (!_tableExists('tabReport Filter') || !_tableExists('tabReport Column')) return;
    final now = DateTime.now().toUtc().toIso8601String();
    database.transaction(() {
      database.db.execute(
        "DELETE FROM [tabReport Filter] WHERE parent=? AND parenttype='Report' AND parentfield='filters';",
        <Object?>[reportName],
      );
      database.db.execute(
        "DELETE FROM [tabReport Column] WHERE parent=? AND parenttype='Report' AND parentfield='columns';",
        <Object?>[reportName],
      );
      for (var index = 0; index < filters.length; index++) {
        final row = filters[index];
        final fieldname = '${row['fieldname'] ?? row['field_name'] ?? row['name'] ?? ''}'.trim();
        if (fieldname.isEmpty) continue;
        database.db.execute(
          '''INSERT INTO [tabReport Filter](
               name,parent,parentfield,parenttype,idx,fieldname,label,label_ar,fieldtype,
               options,required,"default",depends_on,user_editable,source_field,operator,
               created_at,updated_at
             ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);''',
          <Object?>[
            '$reportName-filter-${index + 1}', reportName, 'filters', 'Report', index + 1,
            fieldname, row['label'] ?? fieldname, row['label_ar'],
            row['fieldtype'] ?? row['field_type'] ?? 'Data', row['options'],
            _truthy(row['required'] ?? row['reqd']) ? 1 : 0,
            row['default'] ?? row['value'], row['depends_on'],
            row['user_editable'] == false || row['user_editable'] == 0 ? 0 : 1,
            row['source_field'] ?? fieldname, row['operator'] ?? 'EQ', now, now,
          ],
        );
      }
      for (var index = 0; index < columns.length; index++) {
        final row = columns[index];
        final fieldname = '${row['fieldname'] ?? row['field_name'] ?? row['field'] ?? ''}'.trim();
        if (fieldname.isEmpty) continue;
        database.db.execute(
          '''INSERT INTO [tabReport Column](
               name,parent,parentfield,parenttype,idx,fieldname,label,label_ar,fieldtype,
               options,width,precision,alignment,aggregate,hidden,created_at,updated_at
             ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);''',
          <Object?>[
            '$reportName-column-${index + 1}', reportName, 'columns', 'Report', index + 1,
            fieldname, row['label'] ?? fieldname, row['label_ar'],
            row['fieldtype'] ?? row['field_type'] ?? 'Data', row['options'],
            row['width'], row['precision'], row['alignment'], row['aggregate'] ?? 'NONE',
            _truthy(row['hidden']) ? 1 : 0, now, now,
          ],
        );
      }
    });
  }

  bool _truthy(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return const <String>{'1', 'true', 'yes', 'y', 'on'}.contains('${value ?? ''}'.trim().toLowerCase());
  }

  bool _tableExists(String name) => database.db.select(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;",
        <Object?>[name],
      ).isNotEmpty;

  List<Map<String, Object?>> _builderFilters(Map<String, Object?> definition) {
    final raw = definition['filters'];
    if (raw is! List) return const <Map<String, Object?>>[];
    return raw.whereType<Map>().map((entry) {
      final map = <String, Object?>{for (final item in entry.entries) '${item.key}': item.value};
      final field = '${map['field'] ?? ''}'.trim();
      final parameter = '${map['parameter_name'] ?? ''}'.trim();
      return <String, Object?>{
        'fieldname': parameter.isEmpty ? field : parameter,
        'label': map['label'] ?? field,
        'fieldtype': map['field_type'] ?? 'Data',
        'options': map['options'],
        'required': map['required'] == true,
        'default': map['value'],
        'user_editable': map['user_editable'] != false,
      };
    }).where((entry) => '${entry['fieldname'] ?? ''}'.trim().isNotEmpty).toList(growable: false);
  }

  List<Map<String, Object?>> _builderColumns(Map<String, Object?> definition) {
    final raw = definition['columns'];
    if (raw is! List) return const <Map<String, Object?>>[];
    return raw.whereType<Map>().map((entry) {
      final map = <String, Object?>{for (final item in entry.entries) '${item.key}': item.value};
      final field = '${map['field'] ?? ''}'.trim();
      return <String, Object?>{
        'fieldname': field,
        'label': map['label'] ?? field,
        'aggregate': map['aggregate'],
      };
    }).where((entry) => '${entry['fieldname'] ?? ''}'.trim().isNotEmpty).toList(growable: false);
  }

  bool _containsRawSql(Map<String, Object?> definition) {
    for (final key in const ['sql', 'query', 'raw_sql']) {
      final value = definition[key];
      if (value is String && value.trim().isNotEmpty) return true;
    }
    return false;
  }

  String _queryPath(String module, String reportName) {
    String slug(String value) => value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final app = slug(module).isEmpty ? 'custom' : slug(module);
    final report = slug(reportName).isEmpty ? 'report' : slug(reportName);
    return 'apps/$app/reports/$report/query.sql';
  }

  Map<String, Object?> _decodeMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final value = jsonDecode(raw);
      if (value is! Map) return const {};
      return <String, Object?>{for (final entry in value.entries) '${entry.key}': entry.value};
    } catch (_) {
      return const {};
    }
  }

  List<Map<String, Object?>> _decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final value = jsonDecode(raw);
      if (value is! List) return const [];
      return value.whereType<Map>().map((entry) => <String, Object?>{
        for (final item in entry.entries) '${item.key}': item.value,
      }).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
