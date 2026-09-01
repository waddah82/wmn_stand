import 'dart:convert';

import '../../../platform/storage/wmn_storage_service.dart';
import 'frappe_report_service.dart';

/// Imports/exports a complete Report definition from/to an application report
/// folder in WMN Storage.
///
/// Folder contract:
///   `apps/{app}/reports/{report}/report.json`
///   `apps/{app}/reports/{report}/query.sql` (Query Report)
///   `apps/{app}/reports/{report}/script.{language}` (managed Script Report)
///
/// Runtime execution still reads tabReport + Report Filter/Report Column child
/// metadata. The folder is the application/package source and is synchronized
/// explicitly during install/upgrade/export rather than on every report run.
class WmnReportFolderLoader {
  const WmnReportFolderLoader({
    required this.reports,
    required this.storage,
  });

  final WmnFrappeReportService reports;
  final WmnStorageService storage;

  WmnFrappeReportDefinition importFolder(String folderPath) {
    final base = _folder(folderPath);
    final definitionPath = '$base/report.json';
    if (!storage.exists(definitionPath)) {
      throw StateError('Report folder is missing report.json: $base');
    }
    final raw = jsonDecode(storage.readText(definitionPath));
    if (raw is! Map) throw StateError('report.json must contain one JSON object.');
    final json = <String, Object?>{for (final entry in raw.entries) '${entry.key}': entry.value};

    final reportName = '${json['report_name'] ?? json['title'] ?? ''}'.trim();
    final name = '${json['name'] ?? reportName}'.trim();
    final reportType = '${json['report_type'] ?? ''}'.trim();
    final module = '${json['module'] ?? ''}'.trim();
    if (name.isEmpty || reportName.isEmpty) throw StateError('report.json requires name and report_name.');
    if (module.isEmpty) throw StateError('report.json requires module.');
    if (!const <String>{'Report Builder', 'Query Report', 'Script Report', 'Custom Report'}.contains(reportType)) {
      throw StateError('Unsupported report_type in report.json: $reportType');
    }

    final queryDefinition = _map(json['query_definition']);
    var querySourceType = '${json['query_source_type'] ?? (reportType == 'Query Report' ? 'STORAGE_FILE' : 'STRUCTURED')}'.trim();
    String? querySourcePath;
    if (reportType == 'Query Report') {
      final queryFile = '${json['query_file'] ?? 'query.sql'}'.trim();
      querySourcePath = _child(base, queryFile);
      if (!storage.exists(querySourcePath)) {
        throw StateError('Query Report folder is missing $queryFile.');
      }
      queryDefinition['sql'] = storage.readText(querySourcePath);
      querySourceType = 'STORAGE_FILE';
    }

    var scriptSourceType = '${json['script_source_type'] ?? 'NATIVE_HANDLER'}'.trim();
    String? scriptSourcePath;
    final scriptLanguage = _text(json['script_language']);
    final scriptKey = _text(json['script_key']);
    if (reportType == 'Script Report' && scriptSourceType == 'STORAGE_FILE') {
      final language = scriptLanguage ?? 'wmn';
      final scriptFile = '${json['script_file'] ?? 'script.$language'}'.trim();
      scriptSourcePath = _child(base, scriptFile);
      if (!storage.exists(scriptSourcePath)) {
        throw StateError('Managed Script Report folder is missing $scriptFile.');
      }
      scriptSourceType = 'STORAGE_FILE';
    }

    final metadata = <String, Object?>{
      ..._map(json['metadata']),
      'source_mode': 'REPORT_FOLDER',
      'report_folder': base,
      'definition_path': definitionPath,
    };

    final definition = WmnFrappeReportDefinition(
      name: name,
      reportName: reportName,
      reportType: reportType,
      module: module,
      referenceDocType: _text(json['ref_doctype'] ?? json['reference_doctype']),
      scriptKey: scriptKey,
      queryDefinition: queryDefinition,
      filters: _list(json['filters']),
      columns: _list(json['columns']),
      disabled: _bool(json['disabled']),
      isStandard: json.containsKey('is_standard') ? _bool(json['is_standard']) : true,
      querySourceType: querySourceType,
      querySourcePath: querySourcePath,
      scriptSourceType: scriptSourceType,
      scriptSourcePath: scriptSourcePath,
      scriptLanguage: scriptLanguage,
      metadata: metadata,
    );
    reports.saveDefinition(definition);
    return reports.definition(name)!;
  }

  String exportFolder(String reportName, String folderPath) {
    final report = reports.definition(reportName);
    if (report == null) throw StateError('Unknown report: $reportName');
    final base = _folder(folderPath);
    final json = <String, Object?>{
      'name': report.name,
      'report_name': report.reportName,
      'report_type': report.reportType,
      'module': report.module,
      'ref_doctype': report.referenceDocType,
      'disabled': report.disabled,
      'is_standard': report.isStandard,
      'filters': report.filters,
      'columns': report.columns,
      'query_definition': report.queryDefinition,
      'query_source_type': report.querySourceType,
      'script_source_type': report.scriptSourceType,
      'script_key': report.scriptKey,
      'script_language': report.scriptLanguage,
      'metadata': <String, Object?>{
        ...report.metadata,
        'source_mode': 'REPORT_FOLDER',
        'report_folder': base,
      },
    };

    if (report.reportType == 'Query Report') {
      final sourcePath = report.querySourcePath?.trim() ?? '';
      if (sourcePath.isEmpty || !storage.exists(sourcePath)) {
        throw StateError('Query Report ${report.reportName} has no readable SQL source.');
      }
      storage.writeText('$base/query.sql', storage.readText(sourcePath));
      json['query_file'] = 'query.sql';
      json['query_source_type'] = 'STORAGE_FILE';
    } else if (report.reportType == 'Script Report' && report.scriptSourceType == 'STORAGE_FILE') {
      final sourcePath = report.scriptSourcePath?.trim() ?? '';
      if (sourcePath.isEmpty || !storage.exists(sourcePath)) {
        throw StateError('Script Report ${report.reportName} has no readable managed source.');
      }
      final language = report.scriptLanguage?.trim().isNotEmpty == true ? report.scriptLanguage!.trim() : 'wmn';
      final file = 'script.$language';
      storage.writeText('$base/$file', storage.readText(sourcePath));
      json['script_file'] = file;
    }

    final definitionPath = '$base/report.json';
    storage.writeText(definitionPath, const JsonEncoder.withIndent('  ').convert(json));
    return definitionPath;
  }

  String _folder(String value) {
    final normalized = storage.normalizeKey(value);
    return normalized.endsWith('/') ? normalized.substring(0, normalized.length - 1) : normalized;
  }

  String _child(String base, String relative) {
    final clean = relative.trim().replaceAll('\\', '/');
    if (clean.isEmpty || clean.startsWith('/') || clean.split('/').contains('..')) {
      throw StateError('Unsafe report folder file: $relative');
    }
    return storage.normalizeKey('$base/$clean');
  }

  Map<String, Object?> _map(Object? value) {
    if (value is! Map) return <String, Object?>{};
    return <String, Object?>{for (final entry in value.entries) '${entry.key}': entry.value};
  }

  List<Map<String, Object?>> _list(Object? value) {
    if (value is! List) return <Map<String, Object?>>[];
    return value.whereType<Map>().map((entry) => <String, Object?>{
          for (final item in entry.entries) '${item.key}': item.value,
        }).toList(growable: false);
  }

  String? _text(Object? value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? null : text;
  }

  bool _bool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return const <String>{'1', 'true', 'yes', 'y', 'on'}.contains('${value ?? ''}'.trim().toLowerCase());
  }
}
