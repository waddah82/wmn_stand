import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/database/wmn_database.dart';
import '../../../core/database/sql_identifier.dart';
import '../../../framework/meta/doctype_meta.dart';
import '../../../framework/meta/meta_service.dart';
import '../../customization/data/customization_repository.dart';
import '../domain/report_models.dart';

class ReportBuilderService {
  ReportBuilderService({
    required this.database,
    required this.customization,
    required this.meta,
  });

  final WmnDatabase database;
  final CustomizationRepository customization;
  final WmnMetaService meta;
  static const Uuid _uuid = Uuid();

  static const List<WmnReportSource> _sources = <WmnReportSource>[];

  List<WmnReportSource> get sources {
    final result = <WmnReportSource>[..._sources];
    final existing = result.map((entry) => entry.documentType).whereType<String>().toSet();
    for (final dt in meta.doctypes()) {
      if (dt.isChild || existing.contains(dt.name)) continue;
      if (dt.storageMode == WmnStorageMode.table && dt.tableName != null && dt.tableName!.isNotEmpty) {
        result.add(WmnReportSource(
          key: 'doctype:${dt.name}',
          label: dt.name,
          tableName: dt.tableName!,
          idField: dt.idField,
          documentType: dt.name,
        ));
      }
      existing.add(dt.name);
    }
    result.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return List.unmodifiable(result);
  }

  WmnReportSource source(String key) => sources.firstWhere(
        (entry) => entry.key == key,
        orElse: () => throw StateError('Unknown report source: $key'),
      );

  List<WmnReportField> fieldsFor(String sourceKey) {
    final reportSource = source(sourceKey);
    final documentType = reportSource.documentType;
    final rows = database.db.select('PRAGMA table_info(${quoteSqlIdentifier(reportSource.tableName)});');
    final overrideLabels = <String, String>{};
    if (documentType != null && _tableExists('property_overrides')) {
      for (final override in customization.propertyOverrides(documentType: documentType, enabledOnly: true)) {
        if (override.propertyName == 'label' && override.value != null) {
          overrideLabels[override.fieldName] = '${override.value}';
        }
      }
    }
    final fields = <WmnReportField>[
      for (final row in rows)
        if (_isReportableField(row['name'] as String))
          WmnReportField(
          name: row['name'] as String,
          label: overrideLabels[row['name'] as String] ?? _humanize(row['name'] as String),
          storageType: '${row['type'] ?? 'TEXT'}',
          isNumeric: _isNumericField(row['name'] as String, '${row['type'] ?? 'TEXT'}'),
          isCustom: false,
        ),
    ];
    if (documentType != null && _tableExists('custom_fields')) {
      for (final field in customization.customFields(documentType: documentType, enabledOnly: true)) {
        if (field.hidden || !_isReportableField(field.fieldName)) continue;
        fields.add(
          WmnReportField(
            name: field.fieldName,
            label: field.label,
            storageType: field.fieldType.code,
            isNumeric: const {'INT', 'FLOAT', 'CURRENCY'}.contains(field.fieldType.code),
            isCustom: true,
          ),
        );
      }
    }
    return fields;
  }

  List<WmnReportDefinition> reports({bool enabledOnly = false}) {
    final rows = database.db.select('''
      SELECT * FROM [tabReport]
      WHERE report_type = 'Report Builder'
      ${enabledOnly ? 'AND disabled = 0' : ''}
      ORDER BY report_name COLLATE NOCASE;
    ''');
    return rows.map(_mapReport).toList(growable: false);
  }

  WmnReportDefinition? report(String id) {
    final rows = database.db.select(
      "SELECT * FROM [tabReport] WHERE report_type='Report Builder' AND (name=? OR report_name=?) LIMIT 1;",
      [id, id],
    );
    if (rows.isEmpty) return null;
    return _mapReport(rows.first);
  }

  WmnReportDefinition saveReport({
    String? id,
    required String name,
    required String sourceKey,
    required List<WmnReportColumn> columns,
    List<WmnReportFilter> filters = const [],
    List<WmnReportSort> sorts = const [],
    int limit = 500,
    bool enabled = true,
  }) {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) throw StateError('Report name is required.');
    final availableFields = {for (final field in fieldsFor(sourceKey)) field.name: field};
    if (columns.isEmpty) throw StateError('Select at least one report column.');
    for (final column in columns) {
      final field = availableFields[column.field];
      if (field == null) throw StateError('Unknown report field: ${column.field}');
      if (!field.isNumeric && const {WmnReportAggregate.sum, WmnReportAggregate.average}.contains(column.aggregate)) {
        throw StateError('${field.label} is not numeric.');
      }
    }
    for (final filter in filters) {
      if (!availableFields.containsKey(filter.field)) {
        throw StateError('Unknown filter field: ${filter.field}');
      }
    }
    for (final sort in sorts) {
      if (!columns.any((column) => column.field == sort.field)) {
        throw StateError('Sort field must be one of the selected columns.');
      }
    }

    final existing = id == null ? report(trimmedName) : report(id);
    final entityId = existing?.id ?? id ?? _uuid.v4();
    final safeLimit = limit.clamp(1, 5000).toInt();
    final definition = WmnReportDefinition(
      id: entityId,
      name: trimmedName,
      sourceKey: sourceKey,
      columns: List<WmnReportColumn>.unmodifiable(columns),
      filters: List<WmnReportFilter>.unmodifiable(filters),
      sorts: List<WmnReportSort>.unmodifiable(sorts),
      limit: safeLimit,
      enabled: enabled,
    );
    final payload = <String, Object?>{
      'source_key': sourceKey,
      ...definition.definitionJson(),
    };
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO [tabReport](
        name,report_name,ref_doctype,report_type,module,is_standard,disabled,
        query_definition_json,script_key,filters_json,columns_json,metadata_json,
        created_at,updated_at,query_source_type
      ) VALUES (?,?,?,'Report Builder','Custom',0,?,?,NULL,?,?,'{}',?,?,'STRUCTURED')
      ON CONFLICT(name) DO UPDATE SET
        report_name=excluded.report_name,ref_doctype=excluded.ref_doctype,
        disabled=excluded.disabled,query_definition_json=excluded.query_definition_json,
        filters_json=excluded.filters_json,columns_json=excluded.columns_json,
        query_source_type='STRUCTURED',updated_at=excluded.updated_at;
    ''', [
      entityId,
      trimmedName,
      source(sourceKey).documentType,
      enabled ? 0 : 1,
      jsonEncode(payload),
      jsonEncode(<Map<String, Object?>>[
        for (final filter in filters)
          <String, Object?>{
            'fieldname': filter.key,
            'label': _effectiveChildLabel(filter.label, filter.field, availableFields),
            'fieldtype': filter.fieldType,
            'options': filter.options,
            'required': filter.required,
            'default': filter.value,
            'user_editable': filter.userEditable,
          },
      ]),
      jsonEncode(<Map<String, Object?>>[
        for (final column in columns)
          <String, Object?>{
            'fieldname': column.field,
            'label': _effectiveChildLabel(column.label, column.field, availableFields),
            'aggregate': column.aggregate.code,
          },
      ]),
      now,
      now,
    ]);
    _replaceReportChildren(
      entityId,
      filters: filters,
      columns: columns,
      availableFields: availableFields,
    );
    return report(entityId)!;
  }

  void deleteReport(String id) {
    final existing = report(id);
    if (existing?.isSystem == true) throw StateError('System reports cannot be deleted.');
    if (_tableExists('tabReport Filter')) {
      database.db.execute("DELETE FROM [tabReport Filter] WHERE parent=? AND parenttype='Report';", [id]);
    }
    if (_tableExists('tabReport Column')) {
      database.db.execute("DELETE FROM [tabReport Column] WHERE parent=? AND parenttype='Report';", [id]);
    }
    database.db.execute("DELETE FROM [tabReport] WHERE report_type='Report Builder' AND name=?;", [id]);
  }

  WmnReportResult run(
    WmnReportDefinition definition, {
    Map<String, Object?> runtimeFilters = const {},
  }) {
    final started = DateTime.now();
    try {
      final built = _buildQuery(definition, runtimeFilters: runtimeFilters);
      final rawRows = database.db.select(built.sql, built.args);
      final rows = rawRows
          .map((row) => <String, Object?>{
                for (var index = 0; index < definition.columns.length; index++)
                  built.labels[index]: row['c$index'],
              })
          .toList(growable: false);
      final duration = DateTime.now().difference(started).inMilliseconds;
      _logRun(definition, status: 'SUCCESS', rowCount: rows.length, durationMs: duration);
      return WmnReportResult(
        columns: List<String>.unmodifiable(built.labels),
        rows: rows,
        durationMs: duration,
      );
    } catch (error) {
      final duration = DateTime.now().difference(started).inMilliseconds;
      _logRun(
        definition,
        status: 'ERROR',
        durationMs: duration,
        errorText: error.toString(),
      );
      rethrow;
    }
  }

  String exportCsv(WmnReportResult result) {
    final buffer = StringBuffer();
    buffer.writeln(result.columns.map(_csv).join(','));
    for (final row in result.rows) {
      buffer.writeln(result.columns.map((column) => _csv(row[column])).join(','));
    }
    return buffer.toString();
  }

  List<Map<String, Object?>> runLog({int limit = 100}) => database.db
      .select('''
        SELECT report_id, report_name, status, row_count, duration_ms, error_text, created_at
        FROM report_run_log
        ORDER BY created_at DESC
        LIMIT ?;
      ''', [limit.clamp(1, 1000).toInt()])
      .map((row) => Map<String, Object?>.from(row))
      .toList(growable: false);

  _BuiltReportQuery _buildQuery(
    WmnReportDefinition definition, {
    Map<String, Object?> runtimeFilters = const {},
  }) {
    final reportSource = source(definition.sourceKey);
    final availableFields = {for (final field in fieldsFor(definition.sourceKey)) field.name: field};
    final anyAggregate = definition.columns.any((column) => column.aggregate != WmnReportAggregate.none);
    final selectParts = <String>[];
    final selectArgs = <Object?>[];
    final labels = <String>[];
    final groupParts = <String>[];
    final groupArgs = <Object?>[];

    for (var index = 0; index < definition.columns.length; index++) {
      final column = definition.columns[index];
      final field = availableFields[column.field];
      if (field == null) throw StateError('Unknown report field: ${column.field}');
      final expression = _fieldExpression(reportSource, field);
      final args = _fieldExpressionArgs(reportSource, field);
      final aggregateExpression = _aggregateExpression(expression, field, column.aggregate);
      selectParts.add('$aggregateExpression AS c$index');
      selectArgs.addAll(args);
      labels.add((column.label?.trim().isNotEmpty ?? false) ? column.label!.trim() : field.label);
      if (anyAggregate && column.aggregate == WmnReportAggregate.none) {
        groupParts.add(expression);
        groupArgs.addAll(args);
      }
    }

    final whereParts = <String>[];
    final whereArgs = <Object?>[];
    for (final filter in definition.filters) {
      final field = availableFields[filter.field];
      if (field == null) throw StateError('Unknown report filter field: ${filter.field}');
      final effectiveValue = filter.userEditable && runtimeFilters.containsKey(filter.key)
          ? runtimeFilters[filter.key]
          : filter.value;
      if (filter.required && (effectiveValue == null || (effectiveValue is String && effectiveValue.trim().isEmpty))) {
        throw StateError('${filter.label ?? field.label} is required.');
      }
      final expression = _fieldExpression(reportSource, field);
      whereArgs.addAll(_fieldExpressionArgs(reportSource, field));
      final builtFilter = _filterExpression(expression, field, filter.withValue(effectiveValue));
      whereParts.add(builtFilter.sql);
      whereArgs.addAll(builtFilter.args);
    }

    final orderParts = <String>[];
    for (final sort in definition.sorts) {
      final index = definition.columns.indexWhere((column) => column.field == sort.field);
      if (index < 0) continue;
      orderParts.add('c$index ${sort.descending ? 'DESC' : 'ASC'}');
    }

    final sql = StringBuffer('SELECT ${selectParts.join(', ')} FROM ${quoteSqlIdentifier(reportSource.tableName)} t');
    if (whereParts.isNotEmpty) sql.write(' WHERE ${whereParts.join(' AND ')}');
    if (groupParts.isNotEmpty) sql.write(' GROUP BY ${groupParts.join(', ')}');
    if (orderParts.isNotEmpty) sql.write(' ORDER BY ${orderParts.join(', ')}');
    sql.write(' LIMIT ?;');

    return _BuiltReportQuery(
      sql: sql.toString(),
      args: <Object?>[
        ...selectArgs,
        ...whereArgs,
        ...groupArgs,
        definition.limit.clamp(1, 5000).toInt(),
      ],
      labels: labels,
    );
  }

  String _fieldExpression(WmnReportSource source, WmnReportField field) {
    if (!field.isCustom) return 't."${field.name}"';
    return '''(
      SELECT json_extract(cfv.value_json, '\$')
      FROM custom_field_values cfv
      WHERE cfv.document_type = ?
        AND cfv.document_id = t."${source.idField}"
        AND cfv.field_name = ?
      LIMIT 1
    )''';
  }

  List<Object?> _fieldExpressionArgs(WmnReportSource source, WmnReportField field) {
    if (!field.isCustom) return const [];
    final documentType = source.documentType;
    if (documentType == null) throw StateError('Custom field source has no document type.');
    return <Object?>[documentType, field.name];
  }

  String _aggregateExpression(String expression, WmnReportField field, WmnReportAggregate aggregate) {
    final numeric = field.isNumeric ? 'CAST($expression AS REAL)' : expression;
    return switch (aggregate) {
      WmnReportAggregate.none => expression,
      WmnReportAggregate.count => 'COUNT($expression)',
      WmnReportAggregate.sum => 'SUM($numeric)',
      WmnReportAggregate.average => 'AVG($numeric)',
      WmnReportAggregate.minimum => 'MIN($numeric)',
      WmnReportAggregate.maximum => 'MAX($numeric)',
    };
  }

  _SqlFragment _filterExpression(String expression, WmnReportField field, WmnReportFilter filter) {
    final comparable = field.isNumeric ? 'CAST($expression AS REAL)' : expression;
    final value = field.isNumeric ? num.tryParse('${filter.value ?? ''}') ?? filter.value : filter.value;
    return switch (filter.operator) {
      WmnReportOperator.equals => _SqlFragment('$comparable = ?', [value]),
      WmnReportOperator.notEquals => _SqlFragment('$comparable != ?', [value]),
      WmnReportOperator.greaterThan => _SqlFragment('$comparable > ?', [value]),
      WmnReportOperator.greaterOrEqual => _SqlFragment('$comparable >= ?', [value]),
      WmnReportOperator.lessThan => _SqlFragment('$comparable < ?', [value]),
      WmnReportOperator.lessOrEqual => _SqlFragment('$comparable <= ?', [value]),
      WmnReportOperator.contains => _SqlFragment('$expression LIKE ?', ['%${filter.value ?? ''}%']),
      WmnReportOperator.startsWith => _SqlFragment('$expression LIKE ?', ['${filter.value ?? ''}%']),
      WmnReportOperator.isEmpty => _SqlFragment("($expression IS NULL OR CAST($expression AS TEXT) = '')", const []),
      WmnReportOperator.isNotEmpty => _SqlFragment("($expression IS NOT NULL AND CAST($expression AS TEXT) != '')", const []),
    };
  }

  WmnReportDefinition _mapReport(dynamic row) {
    final raw = jsonDecode(row['query_definition_json'] as String) as Map<String, dynamic>;
    final reportName = '${row['name']}';
    final childColumns = _builderChildColumns(reportName);
    final childFilters = _builderChildFilters(reportName);
    return WmnReportDefinition(
      id: row['name'] as String,
      name: row['report_name'] as String,
      sourceKey: '${raw['source_key'] ?? ''}',
      columns: childColumns.isNotEmpty
          ? childColumns
          : (raw['columns'] as List? ?? const [])
              .map((entry) => WmnReportColumn.fromJson(Map<String, Object?>.from(entry as Map)))
              .toList(growable: false),
      filters: childFilters.isNotEmpty
          ? childFilters
          : (raw['filters'] as List? ?? const [])
              .map((entry) => WmnReportFilter.fromJson(Map<String, Object?>.from(entry as Map)))
              .toList(growable: false),
      sorts: (raw['sorts'] as List? ?? const [])
          .map((entry) => WmnReportSort.fromJson(Map<String, Object?>.from(entry as Map)))
          .toList(growable: false),
      limit: (raw['limit'] as num?)?.toInt() ?? 500,
      isSystem: (row['is_standard'] as int? ?? 0) == 1,
      enabled: (row['disabled'] as int? ?? 0) == 0,
    );
  }

  List<WmnReportFilter> _builderChildFilters(String reportName) {
    if (!_tableExists('tabReport Filter')) return const <WmnReportFilter>[];
    final rows = database.db.select(
      '''SELECT fieldname,label,fieldtype,options,required,"default",user_editable,
                source_field,operator
         FROM [tabReport Filter]
         WHERE parent=? AND parenttype='Report' AND parentfield='filters'
         ORDER BY idx,name;''',
      [reportName],
    );
    return rows.map((row) => WmnReportFilter(
      field: '${row['source_field'] ?? row['fieldname']}',
      operator: WmnReportOperator.fromCode('${row['operator'] ?? 'EQ'}'),
      value: row['default'],
      parameterName: '${row['fieldname']}',
      label: '${row['label'] ?? row['fieldname']}',
      fieldType: '${row['fieldtype'] ?? 'Data'}',
      options: row['options']?.toString(),
      required: (row['required'] as int? ?? 0) == 1,
      userEditable: (row['user_editable'] as int? ?? 1) == 1,
    )).toList(growable: false);
  }

  List<WmnReportColumn> _builderChildColumns(String reportName) {
    if (!_tableExists('tabReport Column')) return const <WmnReportColumn>[];
    final rows = database.db.select(
      '''SELECT fieldname,label,aggregate
         FROM [tabReport Column]
         WHERE parent=? AND parenttype='Report' AND parentfield='columns' AND hidden=0
         ORDER BY idx,name;''',
      [reportName],
    );
    return rows.map((row) => WmnReportColumn(
      field: '${row['fieldname']}',
      label: '${row['label'] ?? row['fieldname']}',
      aggregate: WmnReportAggregate.fromCode('${row['aggregate'] ?? 'NONE'}'),
    )).toList(growable: false);
  }

  void _replaceReportChildren(
    String reportName, {
    required List<WmnReportFilter> filters,
    required List<WmnReportColumn> columns,
    required Map<String, WmnReportField> availableFields,
  }) {
    if (!_tableExists('tabReport Filter') || !_tableExists('tabReport Column')) return;
    final now = DateTime.now().toUtc().toIso8601String();
    database.transaction(() {
      database.db.execute(
        "DELETE FROM [tabReport Filter] WHERE parent=? AND parenttype='Report' AND parentfield='filters';",
        [reportName],
      );
      database.db.execute(
        "DELETE FROM [tabReport Column] WHERE parent=? AND parenttype='Report' AND parentfield='columns';",
        [reportName],
      );
      for (var index = 0; index < filters.length; index++) {
        final filter = filters[index];
        database.db.execute(
          '''INSERT INTO [tabReport Filter](
               name,parent,parentfield,parenttype,idx,fieldname,label,fieldtype,options,
               required,"default",user_editable,source_field,operator,created_at,updated_at
             ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);''',
          [
            '$reportName-filter-${index + 1}', reportName, 'filters', 'Report', index + 1,
            filter.key,
            _effectiveChildLabel(filter.label, filter.field, availableFields),
            filter.fieldType,
            filter.options,
            filter.required ? 1 : 0, filter.value, filter.userEditable ? 1 : 0,
            filter.field, filter.operator.code, now, now,
          ],
        );
      }
      for (var index = 0; index < columns.length; index++) {
        final column = columns[index];
        database.db.execute(
          '''INSERT INTO [tabReport Column](
               name,parent,parentfield,parenttype,idx,fieldname,label,fieldtype,aggregate,
               hidden,created_at,updated_at
             ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?);''',
          [
            '$reportName-column-${index + 1}', reportName, 'columns', 'Report', index + 1,
            column.field,
            _effectiveChildLabel(column.label, column.field, availableFields),
            'Data',
            column.aggregate.code,
            0, now, now,
          ],
        );
      }
    });
  }
  String _effectiveChildLabel(
    String? explicitLabel,
    String fieldName,
    Map<String, WmnReportField> availableFields,
  ) {
    final normalized = explicitLabel?.trim();
    if (normalized != null && normalized.isNotEmpty) return normalized;
    final metadataLabel = availableFields[fieldName]?.label.trim();
    if (metadataLabel != null && metadataLabel.isNotEmpty) return metadataLabel;
    return _humanize(fieldName);
  }

  void _logRun(
    WmnReportDefinition definition, {
    required String status,
    int rowCount = 0,
    int durationMs = 0,
    String? errorText,
  }) {
    database.db.execute('''
      INSERT INTO report_run_log(
        id, report_id, report_name, status, row_count, duration_ms, error_text, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
    ''', [
      _uuid.v4(),
      definition.id,
      definition.name,
      status,
      rowCount,
      durationMs,
      errorText,
      DateTime.now().toUtc().toIso8601String(),
    ]);
  }

  bool _tableExists(String name) => database.db.select(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;",
        [name],
      ).isNotEmpty;

  bool _isReportableField(String name) {
    final lower = name.toLowerCase();
    const blocked = <String>{
      'password',
      'password_hash',
      'pin',
      'pin_hash',
      'secret',
      'api_secret',
      'api_key',
      'access_token',
      'refresh_token',
    };
    if (blocked.contains(lower)) return false;
    return !lower.endsWith('_secret') && !lower.endsWith('_token') && !lower.endsWith('_hash');
  }

  bool _isNumericField(String name, String storageType) {
    final upper = storageType.toUpperCase();
    if (upper.contains('INT') || upper.contains('REAL') || upper.contains('NUM')) return true;
    final lower = name.toLowerCase();
    return lower == 'debit' ||
        lower == 'credit' ||
        lower == 'rate' ||
        lower == 'qty' ||
        lower.endsWith('_qty') ||
        lower.endsWith('_rate') ||
        lower.endsWith('_amount') ||
        lower.endsWith('_total') ||
        lower.endsWith('_percent') ||
        lower.endsWith('_balance') ||
        lower.endsWith('_stock');
  }

  String _humanize(String value) {
    final words = value.split('_').where((entry) => entry.isNotEmpty).map((entry) {
      if (entry.length <= 2) return entry.toUpperCase();
      return '${entry[0].toUpperCase()}${entry.substring(1)}';
    });
    return words.join(' ');
  }

  String _csv(Object? value) {
    final text = '${value ?? ''}'.replaceAll('"', '""');
    return '"$text"';
  }
}

class _BuiltReportQuery {
  const _BuiltReportQuery({required this.sql, required this.args, required this.labels});

  final String sql;
  final List<Object?> args;
  final List<String> labels;
}

class _SqlFragment {
  const _SqlFragment(this.sql, this.args);

  final String sql;
  final List<Object?> args;
}
