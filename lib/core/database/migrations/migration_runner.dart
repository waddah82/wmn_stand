import 'package:sqlite3/common.dart';

import 'database_migration.dart';
import 'migration_001_platform_baseline.dart';
import 'migration_020_platform_system_reset.dart';
import 'migration_021_system_services.dart';
import 'migration_022_system_doctypes_and_features.dart';
import 'migration_023_identity_permissions_runtime.dart';
import 'migration_024_page_runtime.dart';
import 'migration_025_workflow_runtime.dart';
import 'migration_026_report_storage_runtime.dart';
import 'migration_027_system_doctype_form_actions.dart';
import 'migration_028_report_examples_runtime.dart';
import 'migration_029_report_source_editor_examples.dart';
import 'migration_030_printing_pdf_engine.dart';
import 'migration_031_files_attachments_adapters.dart';
import 'migration_032_metadata_runtime_completion.dart';
import 'migration_033_printing_text_unicode_repair.dart';
import 'migration_034_structured_report_printing.dart';
import 'migration_035_frappe_print_runtime.dart';
import 'migration_036_application_generator_packaging.dart';

/// R3 uses a consolidated clean platform baseline.
///
/// Fresh databases are created directly from the platform schema. The single
/// v20 bridge exists only to upgrade the last supported pre-platform baseline
/// (R2.12.x / schema v19) without requiring the historical ERP/POS migrations
/// to remain in WMN System Core.
class DatabaseMigrationRunner {
  const DatabaseMigrationRunner();

  static const List<DatabaseMigration> migrations = [
    Migration001PlatformBaseline(),
    Migration020PlatformSystemReset(),
    Migration021SystemServices(),
    Migration022SystemDocTypesAndFeatures(),
    Migration023IdentityPermissionsRuntime(),
    Migration024PageRuntime(),
    Migration025WorkflowRuntime(),
    Migration026ReportStorageRuntime(),
    Migration027SystemDocTypeFormActions(),
    Migration028ReportExamplesRuntime(),
    Migration029ReportSourceEditorExamples(),
    Migration030PrintingPdfEngine(),
    Migration031FilesAttachmentsAdapters(),
    Migration032MetadataRuntimeCompletion(),
    Migration033PrintingTextUnicodeRepair(),
    Migration034StructuredReportPrinting(),
    Migration035FrappePrintRuntime(),
    Migration036ApplicationGeneratorPackaging(),
  ];

  int get latestVersion => migrations.last.version;

  void migrate(CommonDatabase database) {
    final currentVersion = _currentVersion(database);
    if (currentVersion > latestVersion) {
      throw StateError(
        'Database schema version $currentVersion is newer than supported version $latestVersion.',
      );
    }
    if (currentVersion > 1 && currentVersion < 19) {
      throw StateError(
        'WMN R3 supports direct legacy upgrade from schema v19. '
        'Upgrade the old project to the R2.12.x v19 baseline first, then open it with R3.',
      );
    }

    for (final migration in migrations) {
      if (migration.version <= currentVersion) continue;
      _applyMigration(database, migration);
    }
  }

  int _currentVersion(CommonDatabase database) {
    final metaTable = database.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'system_meta' LIMIT 1;",
    );
    if (metaTable.isEmpty) return 0;

    final rows = database.select(
      "SELECT value FROM system_meta WHERE key = 'schema_version' LIMIT 1;",
    );
    if (rows.isEmpty) return 0;
    return int.tryParse('${rows.first['value']}') ?? 0;
  }

  void _applyMigration(CommonDatabase database, DatabaseMigration migration) {
    database.execute('BEGIN IMMEDIATE;');
    try {
      migration.apply(database);
      _setVersion(database, migration.version);
      database.execute('COMMIT;');
    } catch (_) {
      database.execute('ROLLBACK;');
      rethrow;
    }
  }

  void _setVersion(CommonDatabase database, int version) {
    final now = DateTime.now().toUtc().toIso8601String();
    database.execute('''
      INSERT INTO system_meta(key, value, updated_at)
      VALUES ('schema_version', ?, ?)
      ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at;
    ''', [version.toString(), now]);
  }
}
