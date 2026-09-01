import 'database_migration.dart';

class Migration033PrintingTextUnicodeRepair extends SqlDatabaseMigration {
  const Migration033PrintingTextUnicodeRepair();

  @override
  int get version => 33;

  @override
  String get name => 'printing_text_unicode_repair';

  @override
  String get sql => r'''
-- Existing installations may already be on schema v32, so the protected
-- General Report format repair must have its own migration version.
UPDATE print_formats
SET template_text=replace(replace(template_text, '\r\n', char(10)), '\n', char(10)),
    updated_at=datetime('now')
WHERE code='WMN-GENERAL-REPORT'
  AND target_type='GENERAL_REPORT'
  AND json_extract(metadata_json,'$.protected')=1
  AND (instr(template_text, '\n') > 0 OR instr(template_text, '\r\n') > 0);
''';
}
