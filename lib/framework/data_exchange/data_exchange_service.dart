import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xls;
import 'package:uuid/uuid.dart';

import '../../core/database/wmn_database.dart';
import '../meta/doctype_meta.dart';
import '../meta/meta_service.dart';
import '../model/document_service.dart';
import 'data_exchange_models.dart';

class WmnDataExchangeService {
  WmnDataExchangeService({
    required this.database,
    required this.meta,
    required this.documents,
  });

  final WmnDatabase database;
  final WmnMetaService meta;
  final WmnDocumentService documents;
  static const Uuid _uuid = Uuid();

  List<WmnFieldMeta> importableFields(String doctype) {
    final dt = meta.doctype(doctype);
    if (dt == null || !dt.allowImport) return const [];
    return dt.fields.where(_importableField).toList(growable: false);
  }

  List<WmnFieldMeta> exportableFields(String doctype) {
    final dt = meta.doctype(doctype);
    if (dt == null || !dt.allowExport) return const [];
    return dt.fields.where((field) => !field.hidden && !field.isLayout && !_sensitive(field.fieldName)).toList(growable: false);
  }

  String csvTemplate(
    String doctype, {
    List<String> fields = const [],
    bool includeLabels = true,
    int sampleRows = 0,
  }) {
    final dt = _requireDocType(doctype);
    if (!dt.allowImport) throw StateError('$doctype does not allow Data Import.');
    final selected = _selectFields(importableFields(doctype), fields);
    final rows = <List<Object?>>[];
    rows.add(selected.map((field) => field.fieldName).toList(growable: false));
    if (includeLabels) rows.add(selected.map((field) => field.label).toList(growable: false));
    if (sampleRows > 0) {
      final page = documents.list(doctype, fields: selected.map((field) => field.fieldName).toList(), limit: sampleRows.clamp(1, 5).toInt(), descending: true);
      for (final row in page.rows) {
        rows.add(selected.map((field) => row[field.fieldName]).toList(growable: false));
      }
    }
    return csv.encode(rows);
  }

  Uint8List xlsxTemplate(
    String doctype, {
    List<String> fields = const [],
    int sampleRows = 0,
  }) {
    final selected = _selectFields(importableFields(doctype), fields);
    if (selected.isEmpty) throw StateError('No importable fields for $doctype.');
    final workbook = xls.Excel.createExcel();
    final sheet = workbook['Data Import'];
    sheet.appendRow(selected.map((field) => xls.TextCellValue(field.fieldName)).toList(growable: false));
    sheet.appendRow(selected.map((field) => xls.TextCellValue(field.label)).toList(growable: false));
    if (sampleRows > 0) {
      final page = documents.list(doctype, fields: selected.map((field) => field.fieldName).toList(), limit: sampleRows.clamp(1, 5).toInt());
      for (final row in page.rows) {
        sheet.appendRow(selected.map((field) => _cellValue(row[field.fieldName])).toList(growable: false));
      }
    }
    final bytes = workbook.encode();
    if (bytes == null) throw StateError('Could not encode XLSX template.');
    return Uint8List.fromList(bytes);
  }

  WmnImportPreview previewCsv(String doctype, String content, {List<WmnImportMapping>? mappings}) {
    final decoded = csv.decode(content);
    return _previewRows(doctype, decoded, mappings: mappings);
  }

  WmnImportPreview previewXlsx(String doctype, List<int> bytes, {List<WmnImportMapping>? mappings}) {
    final workbook = xls.Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) return const WmnImportPreview(headers: [], rows: [], mappings: [], errors: ['Workbook has no sheets.']);
    final sheet = workbook.tables.values.first;
    final rows = sheet.rows
        .map<List<dynamic>>((row) => row.map<dynamic>((cell) => cell?.value?.toString()).toList(growable: false))
        .toList(growable: false);
    return _previewRows(doctype, rows, mappings: mappings);
  }

  WmnImportResult importCsv({
    required String doctype,
    required String content,
    required WmnImportMode mode,
    List<WmnImportMapping>? mappings,
    bool skipLabelRow = true,
    String? fileName,
  }) {
    final rows = csv.decode(content);
    return _importRows(doctype: doctype, rows: rows, mode: mode, mappings: mappings, skipLabelRow: skipLabelRow, fileName: fileName);
  }

  WmnImportResult importXlsx({
    required String doctype,
    required List<int> bytes,
    required WmnImportMode mode,
    List<WmnImportMapping>? mappings,
    bool skipLabelRow = true,
    String? fileName,
  }) {
    final workbook = xls.Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) throw StateError('Workbook has no sheets.');
    final sheet = workbook.tables.values.first;
    final rows = sheet.rows
        .map<List<dynamic>>((row) => row.map<dynamic>((cell) => cell?.value?.toString()).toList(growable: false))
        .toList(growable: false);
    return _importRows(doctype: doctype, rows: rows, mode: mode, mappings: mappings, skipLabelRow: skipLabelRow, fileName: fileName);
  }

  WmnExportResult export({
    required String doctype,
    WmnDataFormat format = WmnDataFormat.csv,
    List<String> fields = const [],
    List<List<Object?>> filters = const [],
    String? search,
    int limit = 5000,
  }) {
    final dt = _requireDocType(doctype);
    if (!dt.allowExport) throw StateError('$doctype does not allow Data Export.');
    final selected = _selectFields(exportableFields(doctype), fields);
    if (selected.isEmpty) throw StateError('Select at least one field to export.');
    final selectedNames = selected.map((field) => field.fieldName).toList(growable: false);
    final page = documents.list(
      doctype,
      filters: filters,
      search: search,
      fields: selectedNames,
      limit: limit.clamp(1, 5000).toInt(),
      offset: 0,
    );
    final jobId = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO data_export_jobs(id,doctype,format,fields_json,filters_json,row_count,created_at)
      VALUES (?,?,?,?,?,?,?);
    ''', [jobId, doctype, format.name.toUpperCase(), jsonEncode(selectedNames), jsonEncode(filters), page.rows.length, now]);

    return switch (format) {
      WmnDataFormat.csv => _exportCsv(jobId, doctype, selected, page.rows),
      WmnDataFormat.xlsx => _exportXlsx(jobId, doctype, selected, page.rows),
      WmnDataFormat.json => _exportJson(jobId, doctype, selected, page.rows),
    };
  }

  String importErrorsCsv(String jobId) {
    final rows = database.db.select('''
      SELECT row_number, document_name, row_json, error_text
      FROM data_import_rows WHERE job_id = ? AND status = 'ERROR'
      ORDER BY row_number;
    ''', [jobId]);
    final output = <List<Object?>>[
      const ['row_number', 'document_name', 'error', 'row_json'],
      for (final row in rows) [row['row_number'], row['document_name'], row['error_text'], row['row_json']],
    ];
    return csv.encode(output);
  }

  List<Map<String, Object?>> importJobs({int limit = 100}) => database.db
      .select('SELECT * FROM data_import_jobs ORDER BY created_at DESC LIMIT ?;', [limit.clamp(1, 1000).toInt()])
      .map((row) => Map<String, Object?>.from(row))
      .toList(growable: false);

  WmnImportPreview _previewRows(String doctype, List<List<dynamic>> rows, {List<WmnImportMapping>? mappings}) {
    if (rows.isEmpty) return const WmnImportPreview(headers: [], rows: [], mappings: [], errors: ['File is empty.']);
    final headers = rows.first.map((entry) => '${entry ?? ''}'.trim()).toList(growable: false);
    final resolved = mappings ?? _autoMapping(doctype, headers);
    final errors = <String>[];
    if (headers.any((entry) => entry.isEmpty)) errors.add('One or more source columns have an empty header.');
    final targets = resolved.map((entry) => entry.targetField).where((entry) => entry.isNotEmpty).toList();
    if (targets.toSet().length != targets.length) errors.add('Multiple source columns map to the same target field.');
    final previewRows = rows.skip(1).take(20).map((row) => _mappedRow(headers, row, resolved)).toList(growable: false);
    return WmnImportPreview(headers: headers, rows: previewRows, mappings: resolved, errors: errors);
  }

  WmnImportResult _importRows({
    required String doctype,
    required List<List<dynamic>> rows,
    required WmnImportMode mode,
    required bool skipLabelRow,
    List<WmnImportMapping>? mappings,
    String? fileName,
  }) {
    final dt = _requireDocType(doctype);
    if (!dt.allowImport) throw StateError('$doctype does not allow Data Import.');
    if (rows.isEmpty) throw StateError('Import file is empty.');
    final headers = rows.first.map((entry) => '${entry ?? ''}'.trim()).toList(growable: false);
    final resolved = mappings ?? _autoMapping(doctype, headers);
    final jobId = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final firstDataIndex = skipLabelRow && rows.length > 1 && _looksLikeLabelRow(doctype, headers, rows[1]) ? 2 : 1;
    final totalRows = (rows.length - firstDataIndex).clamp(0, rows.length).toInt();
    database.db.execute('''
      INSERT INTO data_import_jobs(id,doctype,import_mode,file_name,status,total_rows,success_rows,failed_rows,options_json,created_at)
      VALUES (?,?,?,?, 'VALIDATED', ?,0,0,?,?);
    ''', [jobId, doctype, mode.name.toUpperCase(), fileName, totalRows, jsonEncode({'mappings': resolved.map((m) => {'source': m.sourceColumn, 'target': m.targetField}).toList()}), now]);

    final results = <WmnImportRowResult>[];
    for (var index = firstDataIndex; index < rows.length; index++) {
      final rowNo = index + 1;
      final mapped = _mappedRow(headers, rows[index], resolved);
      if (mapped.values.every((value) => value == null || '$value'.trim().isEmpty)) continue;
      try {
        final identity = _identity(dt, mapped);
        final exists = identity != null && documents.exists(doctype, identity);
        if (mode == WmnImportMode.insert && exists) throw StateError('Record already exists: $identity');
        if (mode == WmnImportMode.update && !exists) throw StateError('Record does not exist for update: ${identity ?? '(missing id)'}');
        final existingName = switch (mode) {
          WmnImportMode.insert => null,
          WmnImportMode.update => identity,
          WmnImportMode.upsert => exists ? identity : null,
        };
        final saved = documents.save(doctype, mapped, existingName: existingName, fromImport: true);
        final name = '${saved[dt.idField] ?? saved['name'] ?? ''}';
        results.add(WmnImportRowResult(rowNumber: rowNo, success: true, documentName: name));
        _logRow(jobId, rowNo, 'SUCCESS', mapped, documentName: name);
      } catch (error) {
        results.add(WmnImportRowResult(rowNumber: rowNo, success: false, error: error.toString()));
        _logRow(jobId, rowNo, 'ERROR', mapped, error: error.toString());
      }
    }
    final success = results.where((row) => row.success).length;
    final failed = results.length - success;
    final status = failed == 0 ? 'COMPLETED' : success == 0 ? 'FAILED' : 'PARTIAL';
    database.db.execute('''
      UPDATE data_import_jobs SET status=?,success_rows=?,failed_rows=?,completed_at=? WHERE id=?;
    ''', [status, success, failed, DateTime.now().toUtc().toIso8601String(), jobId]);
    return WmnImportResult(jobId: jobId, rows: results);
  }

  List<WmnImportMapping> _autoMapping(String doctype, List<String> headers) {
    final fields = importableFields(doctype);
    final byName = {for (final field in fields) field.fieldName.toLowerCase(): field.fieldName};
    final byLabel = {for (final field in fields) field.label.toLowerCase(): field.fieldName};
    return headers.map((header) {
      final key = header.trim().toLowerCase();
      return WmnImportMapping(sourceColumn: header, targetField: byName[key] ?? byLabel[key] ?? '');
    }).toList(growable: false);
  }

  Map<String, Object?> _mappedRow(List<String> headers, List<dynamic> row, List<WmnImportMapping> mappings) {
    final result = <String, Object?>{};
    for (var index = 0; index < headers.length; index++) {
      final source = headers[index];
      final mapping = mappings.where((entry) => entry.sourceColumn == source).firstOrNull;
      if (mapping == null || mapping.targetField.isEmpty) continue;
      result[mapping.targetField] = index < row.length ? row[index] : null;
    }
    return result;
  }

  bool _looksLikeLabelRow(String doctype, List<String> headers, List<dynamic> row) {
    final fields = {for (final field in importableFields(doctype)) field.fieldName: field.label.toLowerCase()};
    var matches = 0;
    for (var i = 0; i < headers.length && i < row.length; i++) {
      final target = _autoMapping(doctype, [headers[i]]).first.targetField;
      if (target.isNotEmpty && '${row[i] ?? ''}'.trim().toLowerCase() == fields[target]) matches++;
    }
    return matches > 0 && matches >= (headers.length / 2).floor();
  }

  String? _identity(WmnDocTypeMeta dt, Map<String, Object?> row) {
    final value = row[dt.idField] ?? row['name'];
    if (value != null && '$value'.trim().isNotEmpty) return '$value'.trim();
    if (dt.autoname?.startsWith('field:') == true) {
      final field = dt.autoname!.substring(6);
      final auto = row[field];
      if (auto != null && '$auto'.trim().isNotEmpty) return '$auto'.trim();
    }
    return null;
  }

  WmnExportResult _exportCsv(String jobId, String doctype, List<WmnFieldMeta> fields, List<Map<String, Object?>> rows) {
    final matrix = <List<Object?>>[
      fields.map((field) => field.fieldName).toList(growable: false),
      fields.map((field) => field.label).toList(growable: false),
      ...rows.map((row) => fields.map((field) => row[field.fieldName]).toList(growable: false)),
    ];
    final text = '\uFEFF${csv.encode(matrix)}';
    return WmnExportResult(jobId: jobId, fileName: '${_slug(doctype)}.csv', mimeType: 'text/csv', bytes: utf8.encode(text), rowCount: rows.length);
  }

  WmnExportResult _exportXlsx(String jobId, String doctype, List<WmnFieldMeta> fields, List<Map<String, Object?>> rows) {
    final workbook = xls.Excel.createExcel();
    final sheet = workbook['Data'];
    sheet.appendRow(fields.map((field) => xls.TextCellValue(field.fieldName)).toList(growable: false));
    sheet.appendRow(fields.map((field) => xls.TextCellValue(field.label)).toList(growable: false));
    for (final row in rows) {
      sheet.appendRow(fields.map((field) => _cellValue(row[field.fieldName])).toList(growable: false));
    }
    final bytes = workbook.encode();
    if (bytes == null) throw StateError('Could not encode XLSX export.');
    return WmnExportResult(jobId: jobId, fileName: '${_slug(doctype)}.xlsx', mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', bytes: bytes, rowCount: rows.length);
  }

  WmnExportResult _exportJson(String jobId, String doctype, List<WmnFieldMeta> fields, List<Map<String, Object?>> rows) {
    final names = fields.map((field) => field.fieldName).toSet();
    final payload = rows.map((row) => <String, Object?>{for (final entry in row.entries) if (names.contains(entry.key)) entry.key: entry.value}).toList();
    return WmnExportResult(jobId: jobId, fileName: '${_slug(doctype)}.json', mimeType: 'application/json', bytes: utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)), rowCount: rows.length);
  }

  xls.CellValue _cellValue(Object? value) {
    if (value == null) return xls.TextCellValue('');
    if (value is int) return xls.IntCellValue(value);
    if (value is double) return xls.DoubleCellValue(value);
    if (value is num) return xls.DoubleCellValue(value.toDouble());
    if (value is bool) return xls.BoolCellValue(value);
    return xls.TextCellValue('$value');
  }

  List<WmnFieldMeta> _selectFields(List<WmnFieldMeta> available, List<String> requested) {
    if (requested.isEmpty) return available;
    final wanted = requested.toSet();
    return available.where((field) => wanted.contains(field.fieldName)).toList(growable: false);
  }

  bool _importableField(WmnFieldMeta field) => !field.hidden && !field.isLayout && !field.readOnly && !_sensitive(field.fieldName);

  bool _sensitive(String name) {
    final lower = name.toLowerCase();
    const blocked = {'password', 'password_hash', 'pin', 'pin_hash', 'api_secret', 'api_key', 'access_token', 'refresh_token'};
    return blocked.contains(lower) || lower.endsWith('_secret') || lower.endsWith('_token') || lower.endsWith('_hash');
  }

  WmnDocTypeMeta _requireDocType(String name) => meta.doctype(name) ?? (throw StateError('Unknown DocType: $name'));

  void _logRow(String jobId, int rowNo, String status, Map<String, Object?> row, {String? documentName, String? error}) {
    database.db.execute('''
      INSERT INTO data_import_rows(id,job_id,row_number,status,document_name,row_json,error_text)
      VALUES (?,?,?,?,?,?,?);
    ''', [_uuid.v4(), jobId, rowNo, status, documentName, jsonEncode(row), error]);
  }

  String _slug(String value) => value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
