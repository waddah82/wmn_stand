import 'database_migration.dart';

/// R3.19.2 structured report printing.
///
/// The protected general report format now places a real structured table
/// marker instead of flattening every row into key/value text. Report-specific
/// formats can opt into the same engine by using {{ report.table }} and
/// {{ report.filters_block }} in their template.
class Migration034StructuredReportPrinting extends SqlDatabaseMigration {
  const Migration034StructuredReportPrinting();

  @override
  int get version => 34;

  @override
  String get name => 'structured_report_printing';

  @override
  String get sql => r'''
UPDATE print_formats
SET template_text='<h1>{{ report.title }}</h1>
{{ report.filters_block }}
{{ report.table }}',
    metadata_json=json_set(
      COALESCE(NULLIF(metadata_json,''),'{}'),
      '$.protected',1,
      '$.general_report',1,
      '$.structured_report',1,
      '$.auto_landscape',1,
      '$.repeat_table_header',1
    ),
    updated_at=datetime('now')
WHERE code='WMN-GENERAL-REPORT'
  AND target_type='GENERAL_REPORT'
  AND json_extract(metadata_json,'$.protected')=1;
''';
}
