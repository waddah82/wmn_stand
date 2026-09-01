import '../../../core/database/wmn_database.dart';
import '../domain/report_models.dart';
import 'script_report_service.dart';

/// Registers compiled WMN System report handlers.
///
/// Built-in examples use the same public Script Report contract that
/// applications use; there is no separate execution path for tutorial data.
class WmnBuiltinReportHandlers {
  const WmnBuiltinReportHandlers._();

  static const String moduleSummaryKey = 'wmn.examples.reports.module_summary';

  static void register({
    required WmnDatabase database,
    required WmnScriptReportService scriptReports,
  }) {
    scriptReports.registerNativeHandler(moduleSummaryKey, (filters) {
      final module = '${filters['module'] ?? ''}'.trim();
      final rows = database.db.select('''
        SELECT d.module,
               COUNT(DISTINCT d.name) AS doctype_count,
               COUNT(f.id) AS field_count,
               SUM(CASE WHEN f.reqd=1 THEN 1 ELSE 0 END) AS required_field_count
        FROM wmn_doctypes d
        LEFT JOIN wmn_doctype_fields f ON f.doctype = d.name
        WHERE (? = '' OR d.module LIKE '%' || ? || '%')
        GROUP BY d.module
        ORDER BY doctype_count DESC, d.module COLLATE NOCASE
        LIMIT 200;
      ''', <Object?>[module, module]);
      return WmnScriptReportResult(
        columns: const <WmnScriptReportColumn>[
          WmnScriptReportColumn(fieldName: 'module', label: 'Module'),
          WmnScriptReportColumn(fieldName: 'doctype_count', label: 'DocTypes', fieldType: 'Int'),
          WmnScriptReportColumn(fieldName: 'field_count', label: 'Fields', fieldType: 'Int'),
          WmnScriptReportColumn(fieldName: 'required_field_count', label: 'Required Fields', fieldType: 'Int'),
        ],
        rows: rows
            .map((row) => <String, Object?>{
                  'module': row['module'],
                  'doctype_count': row['doctype_count'],
                  'field_count': row['field_count'],
                  'required_field_count': row['required_field_count'],
                })
            .toList(growable: false),
        durationMs: 0,
        message: 'Built-in example native handler.',
      );
    });
  }
}
