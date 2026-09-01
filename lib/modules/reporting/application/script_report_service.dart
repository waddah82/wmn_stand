import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/database/wmn_database.dart';
import '../../../platform/scripts/wmn_script_runtime.dart';
import '../../../platform/storage/wmn_storage_service.dart';
import '../domain/report_models.dart';

typedef WmnNativeScriptReportHandler = WmnScriptReportResult Function(
  Map<String, Object?> filters,
);

/// Script Report executor backed exclusively by the Report DocType.
///
/// Report metadata lives in tabReport. Executable behavior is either a
/// compiled native handler or a managed source file resolved by WmnScriptRuntime.
class WmnScriptReportService {
  factory WmnScriptReportService({
    required WmnDatabase database,
    WmnStorageService? storage,
    WmnScriptRuntime? scriptRuntime,
  }) {
    final resolvedStorage = storage ?? WmnStorageService.forDatabase(database);
    return WmnScriptReportService._(
      database: database,
      storage: resolvedStorage,
      scriptRuntime: scriptRuntime ?? WmnScriptRuntime(storage: resolvedStorage),
    );
  }

  WmnScriptReportService._({
    required this.database,
    required this.storage,
    required this.scriptRuntime,
  });

  final WmnDatabase database;
  final WmnStorageService storage;
  final WmnScriptRuntime scriptRuntime;
  static const Uuid _uuid = Uuid();

  void registerNativeHandler(String reportName, WmnNativeScriptReportHandler handler) {
    final key = reportName.trim();
    if (key.isEmpty) throw StateError('Report handler key is required.');
    scriptRuntime.registerNativeHandler(key, (context) => handler(context));
  }

  bool hasNativeHandler(String reportName) => scriptRuntime.hasNativeHandler(reportName.trim());

  void registerManagedExecutor(String language, WmnManagedScriptExecutor executor) {
    scriptRuntime.registerManagedExecutor(language, executor);
  }

  WmnScriptReportDefinition saveNativeDefinition({
    String? id,
    required String name,
    required String module,
    String? referenceDocType,
    List<WmnScriptReportFilter> filters = const [],
    List<WmnScriptReportColumn> columns = const [],
    bool isSystem = true,
    bool enabled = true,
    String? handlerKey,
  }) {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) throw StateError('Report name is required.');
    final existing = definition(normalizedName);
    final entityId = id ?? existing?.id ?? _uuid.v4();
    final key = (handlerKey?.trim().isNotEmpty ?? false) ? handlerKey!.trim() : normalizedName;
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO [tabReport](
        name,report_name,ref_doctype,report_type,module,is_standard,disabled,
        query_definition_json,script_key,filters_json,columns_json,metadata_json,
        created_at,updated_at,script_source_type,script_source_path,script_language
      ) VALUES (?,?,?,'Script Report',?,?,?,'{}',?,?,?,'{}',?,?,'NATIVE_HANDLER',NULL,NULL)
      ON CONFLICT(name) DO UPDATE SET
        report_name=excluded.report_name,ref_doctype=excluded.ref_doctype,
        report_type='Script Report',module=excluded.module,is_standard=excluded.is_standard,
        disabled=excluded.disabled,script_key=excluded.script_key,
        filters_json=excluded.filters_json,columns_json=excluded.columns_json,
        script_source_type='NATIVE_HANDLER',script_source_path=NULL,script_language=NULL,
        updated_at=excluded.updated_at;
    ''', [
      entityId,
      normalizedName,
      _nullable(referenceDocType),
      module.trim().isEmpty ? 'Custom' : module.trim(),
      isSystem ? 1 : 0,
      enabled ? 0 : 1,
      key,
      jsonEncode(filters.map((entry) => entry.toJson()).toList(growable: false)),
      jsonEncode(columns.map((entry) => entry.toJson()).toList(growable: false)),
      now,
      now,
    ]);
    _replaceChildren(entityId, filters: filters, columns: columns);
    return definition(entityId)!;
  }

  WmnScriptReportDefinition saveManagedDefinition({
    String? id,
    required String name,
    required String module,
    required String sourcePath,
    required String language,
    required String source,
    String? referenceDocType,
    List<WmnScriptReportFilter> filters = const [],
    List<WmnScriptReportColumn> columns = const [],
    bool isSystem = false,
    bool enabled = true,
  }) {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) throw StateError('Report name is required.');
    final normalizedPath = storage.normalizeKey(sourcePath);
    scriptRuntime.saveSource(path: normalizedPath, source: source);
    final existing = definition(normalizedName);
    final entityId = id ?? existing?.id ?? _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO [tabReport](
        name,report_name,ref_doctype,report_type,module,is_standard,disabled,
        query_definition_json,script_key,filters_json,columns_json,metadata_json,
        created_at,updated_at,script_source_type,script_source_path,script_language
      ) VALUES (?,?,?,'Script Report',?,?,?,'{}',NULL,?,?,'{}',?,?,'STORAGE_FILE',?,?)
      ON CONFLICT(name) DO UPDATE SET
        report_name=excluded.report_name,ref_doctype=excluded.ref_doctype,
        report_type='Script Report',module=excluded.module,is_standard=excluded.is_standard,
        disabled=excluded.disabled,script_key=NULL,
        filters_json=excluded.filters_json,columns_json=excluded.columns_json,
        script_source_type='STORAGE_FILE',script_source_path=excluded.script_source_path,
        script_language=excluded.script_language,updated_at=excluded.updated_at;
    ''', [
      entityId,
      normalizedName,
      _nullable(referenceDocType),
      module.trim().isEmpty ? 'Custom' : module.trim(),
      isSystem ? 1 : 0,
      enabled ? 0 : 1,
      jsonEncode(filters.map((entry) => entry.toJson()).toList(growable: false)),
      jsonEncode(columns.map((entry) => entry.toJson()).toList(growable: false)),
      now,
      now,
      normalizedPath,
      language.trim().toLowerCase(),
    ]);
    _replaceChildren(entityId, filters: filters, columns: columns);
    return definition(entityId)!;
  }

  List<WmnScriptReportDefinition> definitions({bool enabledOnly = false}) {
    final rows = database.db.select('''
      SELECT * FROM [tabReport]
      WHERE report_type='Script Report'
      ${enabledOnly ? 'AND disabled=0' : ''}
      ORDER BY module COLLATE NOCASE, report_name COLLATE NOCASE;
    ''');
    return rows.map(_definition).toList(growable: false);
  }

  WmnScriptReportDefinition? definition(String reportName) {
    final rows = database.db.select(
      "SELECT * FROM [tabReport] WHERE report_type='Script Report' AND (name=? OR report_name=?) LIMIT 1;",
      [reportName.trim(), reportName.trim()],
    );
    return rows.isEmpty ? null : _definition(rows.first);
  }

  WmnScriptReportResult execute(String reportName, {Map<String, Object?> filters = const {}}) {
    final report = definition(reportName);
    if (report == null) throw StateError('Unknown Script Report: $reportName.');
    if (!report.enabled) throw StateError('Script Report is disabled: ${report.name}.');

    final effectiveFilters = <String, Object?>{...filters};
    for (final filter in report.filters) {
      if (!effectiveFilters.containsKey(filter.fieldName) && filter.defaultValue != null) {
        effectiveFilters[filter.fieldName] = filter.defaultValue;
      }
      final value = effectiveFilters[filter.fieldName];
      if (filter.required && (value == null || (value is String && value.trim().isEmpty))) {
        throw StateError('${filter.label} is required.');
      }
    }

    final started = DateTime.now();
    final Object? raw;
    if (report.scriptSourceType == 'STORAGE_FILE') {
      if (report.scriptSourcePath == null || report.scriptSourcePath!.trim().isEmpty) {
        throw StateError('Script Report ${report.name} has no storage source path.');
      }
      if (report.scriptLanguage == null || report.scriptLanguage!.trim().isEmpty) {
        throw StateError('Script Report ${report.name} has no managed script language.');
      }
      raw = scriptRuntime.executeStored(
        path: report.scriptSourcePath!,
        language: report.scriptLanguage!,
        context: effectiveFilters,
      );
    } else {
      raw = scriptRuntime.executeNative(report.scriptKey ?? report.name, effectiveFilters);
    }
    if (raw is! WmnScriptReportResult) {
      throw StateError('Script Report ${report.name} executor returned an unsupported result.');
    }
    final durationMs = DateTime.now().difference(started).inMilliseconds;
    return WmnScriptReportResult(
      columns: raw.columns.isEmpty ? report.columns : raw.columns,
      rows: raw.rows,
      durationMs: durationMs,
      message: raw.message,
      summary: raw.summary,
    );
  }

  bool requiresPort(String reportName) {
    final report = definition(reportName);
    if (report == null) return false;
    if (report.scriptSourceType == 'STORAGE_FILE') {
      return report.scriptLanguage == null || !scriptRuntime.hasManagedExecutor(report.scriptLanguage!);
    }
    return !scriptRuntime.hasNativeHandler(report.scriptKey ?? report.name);
  }

  WmnScriptReportDefinition _definition(dynamic row) {
    final sourceType = '${row['script_source_type'] ?? 'NATIVE_HANDLER'}';
    final scriptKey = row['script_key'] as String?;
    final sourcePath = row['script_source_path'] as String?;
    return WmnScriptReportDefinition(
      id: row['name'] as String,
      name: row['report_name'] as String,
      module: row['module'] as String,
      referenceDocType: row['ref_doctype'] as String?,
      script: sourceType == 'STORAGE_FILE' ? 'storage:${sourcePath ?? ''}' : 'native:${scriptKey ?? row['report_name']}',
      scriptKey: scriptKey,
      scriptSourceType: sourceType,
      scriptSourcePath: sourcePath,
      scriptLanguage: row['script_language'] as String?,
      filters: _definitionFilters('${row['name']}', row['filters_json'] as String?),
      columns: _definitionColumns('${row['name']}', row['columns_json'] as String?),
      isSystem: (row['is_standard'] as int? ?? 0) == 1,
      enabled: (row['disabled'] as int? ?? 0) == 0,
    );
  }

  List<WmnScriptReportFilter> _definitionFilters(String reportName, String? legacyJson) {
    if (_tableExists('tabReport Filter')) {
      final rows = database.db.select(
        '''SELECT fieldname,label,fieldtype,options,required,"default",depends_on
           FROM [tabReport Filter]
           WHERE parent=? AND parenttype='Report' AND parentfield='filters'
           ORDER BY idx,name;''',
        [reportName],
      );
      if (rows.isNotEmpty) {
        return rows.map((row) => WmnScriptReportFilter(
          fieldName: '${row['fieldname']}',
          label: '${row['label'] ?? row['fieldname']}',
          fieldType: '${row['fieldtype'] ?? 'Data'}',
          options: row['options']?.toString(),
          defaultValue: row['default'],
          required: (row['required'] as int? ?? 0) == 1,
          dependsOn: row['depends_on']?.toString(),
        )).toList(growable: false);
      }
    }
    return _decodeList(legacyJson).map(WmnScriptReportFilter.fromJson).toList(growable: false);
  }

  List<WmnScriptReportColumn> _definitionColumns(String reportName, String? legacyJson) {
    if (_tableExists('tabReport Column')) {
      final rows = database.db.select(
        '''SELECT fieldname,label,fieldtype,options,width
           FROM [tabReport Column]
           WHERE parent=? AND parenttype='Report' AND parentfield='columns' AND hidden=0
           ORDER BY idx,name;''',
        [reportName],
      );
      if (rows.isNotEmpty) {
        return rows.map((row) => WmnScriptReportColumn(
          fieldName: '${row['fieldname']}',
          label: '${row['label'] ?? row['fieldname']}',
          fieldType: '${row['fieldtype'] ?? 'Data'}',
          options: row['options']?.toString(),
          width: (row['width'] as num?)?.toDouble(),
        )).toList(growable: false);
      }
    }
    return _decodeList(legacyJson).map(WmnScriptReportColumn.fromJson).toList(growable: false);
  }

  void _replaceChildren(
    String reportName, {
    required List<WmnScriptReportFilter> filters,
    required List<WmnScriptReportColumn> columns,
  }) {
    if (!_tableExists('tabReport Filter') || !_tableExists('tabReport Column')) return;
    final now = DateTime.now().toUtc().toIso8601String();
    database.transaction(() {
      database.db.execute("DELETE FROM [tabReport Filter] WHERE parent=? AND parenttype='Report' AND parentfield='filters';", [reportName]);
      database.db.execute("DELETE FROM [tabReport Column] WHERE parent=? AND parenttype='Report' AND parentfield='columns';", [reportName]);
      for (var index = 0; index < filters.length; index++) {
        final filter = filters[index];
        database.db.execute(
          '''INSERT INTO [tabReport Filter](
               name,parent,parentfield,parenttype,idx,fieldname,label,fieldtype,options,
               required,"default",depends_on,user_editable,source_field,operator,created_at,updated_at
             ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);''',
          [
            '$reportName-filter-${index + 1}', reportName, 'filters', 'Report', index + 1,
            filter.fieldName, filter.label, filter.fieldType, filter.options,
            filter.required ? 1 : 0, filter.defaultValue, filter.dependsOn, 1,
            filter.fieldName, 'EQ', now, now,
          ],
        );
      }
      for (var index = 0; index < columns.length; index++) {
        final column = columns[index];
        database.db.execute(
          '''INSERT INTO [tabReport Column](
               name,parent,parentfield,parenttype,idx,fieldname,label,fieldtype,options,width,
               aggregate,hidden,created_at,updated_at
             ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?);''',
          [
            '$reportName-column-${index + 1}', reportName, 'columns', 'Report', index + 1,
            column.fieldName, column.label, column.fieldType, column.options, column.width,
            'NONE', 0, now, now,
          ],
        );
      }
    });
  }

  bool _tableExists(String name) => database.db.select(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;",
        [name],
      ).isNotEmpty;

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

  String? _nullable(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
