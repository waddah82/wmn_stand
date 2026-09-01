import 'package:sqlite3/common.dart';

import 'database_migration.dart';

/// Upgrade bridge from the last ERP/POS-oriented WMN schema (v19) to the
/// application-platform baseline.
///
/// Fresh R3 databases are created by [Migration001PlatformBaseline] and this
/// migration is effectively an idempotent cleanup. Existing v19 databases keep
/// their application data tables for recovery/export, but WMN no longer
/// registers or executes those business applications as part of System Core.
class Migration020PlatformSystemReset implements DatabaseMigration {
  const Migration020PlatformSystemReset();

  @override
  int get version => 20;

  @override
  String get name => 'platform_system_reset';

  @override
  void apply(CommonDatabase database) {
    _removeBuiltInBusinessMetadata(database);
    _normalizeGenericSystemTables(database);
    _removeBuiltInBusinessSeeds(database);
    _ensurePlatformModules(database);
  }

  void _removeBuiltInBusinessMetadata(CommonDatabase database) {
    if (_tableExists(database, 'wmn_doctypes')) {
      database.execute(r'''
        DELETE FROM wmn_doctypes
        WHERE name IN (
          'Account','Branch','Company','Coupon','Customer','Item','Item Group',
          'Payment Entry','POS Profile','Pricing Rule','Promotion',
          'Purchase Document','Sales Invoice','Supplier','UOM','Warehouse'
        );
      ''');
      database.execute("UPDATE wmn_doctypes SET module='Security', updated_at=datetime('now') WHERE name='User';");
    }

    if (_tableExists(database, 'wmn_modules')) {
      database.execute(r'''
        DELETE FROM wmn_modules
        WHERE app_name IS NULL
          AND name IN ('Accounts','Buying','Selling','Stock','Setup','Users');
      ''');
    }

    if (_tableExists(database, 'app_settings')) {
      database.execute(r'''
        DELETE FROM app_settings
        WHERE key LIKE 'pos_%'
           OR key IN ('pos_profile_id','default_pos_profile','cash_session_id');
      ''');
    }

    if (_tableExists(database, 'tabWorkspace')) {
      database.execute(r'''
        DELETE FROM [tabWorkspace]
        WHERE app_name IS NULL
          AND (
            module IN ('Accounts','Buying','Selling','Stock','Setup')
            OR name IN ('Accounts','Buying','Selling','Stock','Setup')
          );
      ''');
    }

    if (_tableExists(database, 'custom_reports')) {
      database.execute(r'''
        DELETE FROM custom_reports
        WHERE source_key IN (
          'customers','suppliers','items','sales_invoices','sales_invoice_items',
          'payments','purchase_documents','purchase_document_items','payment_entries',
          'accounts','gl_entries','stock_ledger_entries','stock_balances',
          'cash_movements','cash_sessions','companies','branches','warehouses'
        );
      ''');
    }

    // This table represented the old ERP application porting milestone rather
    // than a WMN system capability. Generic Frappe/source-porting coverage is
    // retained in wmn_frappe_api_coverage and the app-converter tables.
    database.execute('DROP TABLE IF EXISTS wmn_erp_source_parity;');
  }

  void _normalizeGenericSystemTables(CommonDatabase database) {
    _normalizeNumberingSeries(database);
    _normalizeUserRoles(database);
    _normalizePrintSettings(database);
    _normalizePrintJobs(database);
  }

  void _normalizeNumberingSeries(CommonDatabase database) {
    if (!_tableExists(database, 'numbering_series')) return;
    final columns = _columns(database, 'numbering_series');
    if (!columns.contains('company_id') && columns.contains('scope_type')) return;

    database.execute(r'''
      CREATE TABLE numbering_series_v20 (
        id TEXT PRIMARY KEY,
        series_key TEXT NOT NULL UNIQUE,
        document_type TEXT NOT NULL,
        scope_type TEXT,
        scope_value TEXT,
        prefix TEXT NOT NULL,
        next_value INTEGER NOT NULL DEFAULT 1 CHECK (next_value > 0),
        padding INTEGER NOT NULL DEFAULT 6 CHECK (padding >= 1),
        fiscal_year_mode TEXT NOT NULL DEFAULT 'NONE',
        enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
        updated_at TEXT NOT NULL
      ) STRICT;
    ''');
    database.execute(r'''
      INSERT INTO numbering_series_v20(
        id,series_key,document_type,scope_type,scope_value,prefix,next_value,
        padding,fiscal_year_mode,enabled,updated_at
      )
      SELECT
        id,series_key,document_type,
        CASE
          WHEN branch_id IS NOT NULL AND trim(branch_id) <> '' THEN 'LEGACY_BRANCH'
          WHEN company_id IS NOT NULL AND trim(company_id) <> '' THEN 'LEGACY_COMPANY'
          ELSE NULL
        END,
        COALESCE(NULLIF(branch_id,''), NULLIF(company_id,'')),
        prefix,next_value,padding,fiscal_year_mode,enabled,updated_at
      FROM numbering_series;
    ''');
    database.execute('DROP TABLE numbering_series;');
    database.execute('ALTER TABLE numbering_series_v20 RENAME TO numbering_series;');
    database.execute(
      'CREATE INDEX IF NOT EXISTS idx_numbering_series_scope '
      'ON numbering_series(document_type, scope_type, scope_value, enabled);',
    );
  }

  void _normalizeUserRoles(CommonDatabase database) {
    if (!_tableExists(database, 'user_roles')) return;
    final columns = _columns(database, 'user_roles');
    if (!columns.contains('company_id') && columns.contains('scope_type')) return;

    database.execute(r'''
      CREATE TABLE user_roles_v20 (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        role_id TEXT NOT NULL,
        scope_type TEXT,
        scope_value TEXT,
        assigned_at TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES "tabUser"(id) ON DELETE CASCADE,
        FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE
      ) STRICT;
    ''');
    database.execute(r'''
      INSERT INTO user_roles_v20(id,user_id,role_id,scope_type,scope_value,assigned_at)
      SELECT
        id,user_id,role_id,
        CASE
          WHEN branch_id IS NOT NULL AND trim(branch_id) <> '' THEN 'LEGACY_BRANCH'
          WHEN company_id IS NOT NULL AND trim(company_id) <> '' THEN 'LEGACY_COMPANY'
          ELSE NULL
        END,
        COALESCE(NULLIF(branch_id,''), NULLIF(company_id,'')),
        assigned_at
      FROM user_roles;
    ''');
    database.execute('DROP TABLE user_roles;');
    database.execute('ALTER TABLE user_roles_v20 RENAME TO user_roles;');
    database.execute('CREATE INDEX IF NOT EXISTS idx_user_roles_user ON user_roles(user_id, role_id);');
  }

  void _normalizePrintSettings(CommonDatabase database) {
    if (!_tableExists(database, 'print_settings')) return;
    final columns = _columns(database, 'print_settings');
    if (!columns.contains('open_cash_drawer')) return;

    database.execute(r'''
      CREATE TABLE print_settings_v20 (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        print_format_id TEXT,
        connection_type TEXT NOT NULL DEFAULT 'PREVIEW',
        printer_name TEXT,
        network_host TEXT,
        network_port INTEGER NOT NULL DEFAULT 9100,
        serial_port TEXT,
        serial_baud INTEGER NOT NULL DEFAULT 9600,
        paper_width_mm INTEGER NOT NULL DEFAULT 80,
        auto_print INTEGER NOT NULL DEFAULT 0 CHECK (auto_print IN (0, 1)),
        cut_paper INTEGER NOT NULL DEFAULT 0 CHECK (cut_paper IN (0, 1)),
        enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
        qz_printer_name TEXT,
        usb_device_name TEXT,
        usb_vendor_id INTEGER,
        usb_product_id INTEGER,
        bluetooth_name TEXT,
        bluetooth_address TEXT,
        system_print_mode TEXT NOT NULL DEFAULT 'DOCUMENT',
        updated_at TEXT NOT NULL,
        FOREIGN KEY (print_format_id) REFERENCES print_formats(id)
      ) STRICT;
    ''');
    database.execute(r'''
      INSERT INTO print_settings_v20(
        id,name,print_format_id,connection_type,printer_name,network_host,network_port,
        serial_port,serial_baud,paper_width_mm,auto_print,cut_paper,enabled,
        qz_printer_name,usb_device_name,usb_vendor_id,usb_product_id,
        bluetooth_name,bluetooth_address,system_print_mode,updated_at
      )
      SELECT
        id,name,print_format_id,connection_type,printer_name,network_host,network_port,
        serial_port,serial_baud,paper_width_mm,auto_print,cut_paper,enabled,
        qz_printer_name,usb_device_name,usb_vendor_id,usb_product_id,
        bluetooth_name,bluetooth_address,
        CASE WHEN system_print_mode='RECEIPT' THEN 'DOCUMENT' ELSE system_print_mode END,
        updated_at
      FROM print_settings
      WHERE id <> 'default-print-settings';
    ''');
    database.execute('DROP TABLE print_settings;');
    database.execute('ALTER TABLE print_settings_v20 RENAME TO print_settings;');
  }

  void _normalizePrintJobs(CommonDatabase database) {
    if (!_tableExists(database, 'print_jobs')) return;
    final columns = _columns(database, 'print_jobs');
    if (!columns.contains('invoice_id')) return;

    database.execute(r'''
      CREATE TABLE print_jobs_v20 (
        id TEXT PRIMARY KEY,
        document_type TEXT NOT NULL,
        document_name TEXT NOT NULL,
        connection_type TEXT NOT NULL,
        printer_target TEXT,
        status TEXT NOT NULL CHECK (status IN ('PENDING','SENT','FAILED')),
        error_message TEXT,
        created_at TEXT NOT NULL,
        completed_at TEXT
      ) STRICT;
    ''');
    database.execute(r'''
      INSERT INTO print_jobs_v20(
        id,document_type,document_name,connection_type,printer_target,status,
        error_message,created_at,completed_at
      )
      SELECT
        id,'Sales Invoice',invoice_id,connection_type,printer_target,status,
        error_message,created_at,completed_at
      FROM print_jobs;
    ''');
    database.execute('DROP TABLE print_jobs;');
    database.execute('ALTER TABLE print_jobs_v20 RENAME TO print_jobs;');
    database.execute(
      'CREATE INDEX IF NOT EXISTS idx_print_jobs_document '
      'ON print_jobs(document_type, document_name, created_at);',
    );
  }

  void _removeBuiltInBusinessSeeds(CommonDatabase database) {
    if (_tableExists(database, 'print_formats')) {
      database.execute("DELETE FROM print_formats WHERE id='default-receipt-format' OR code='DEFAULT_RECEIPT';");
    }
    if (_tableExists(database, 'numbering_series')) {
      database.execute(r'''
        DELETE FROM numbering_series
        WHERE id IN (
          'series-sales-invoice-default','series-sales-return-default',
          'series-journal-default','series-payment-default',
          'series-material-request-default','series-rfq-default',
          'series-supplier-quotation-default','series-purchase-order-default',
          'series-purchase-receipt-default','series-purchase-invoice-default'
        );
      ''');
    }
    if (_tableExists(database, 'permissions')) {
      database.execute(r'''
        DELETE FROM permissions
        WHERE module IN ('sales','inventory','pos','accounting','purchase');
      ''');
    }
    if (_tableExists(database, 'roles')) {
      database.execute("DELETE FROM roles WHERE id IN ('role-manager','role-cashier');");
    }
    if (_tableExists(database, 'tabUser')) {
      database.execute("UPDATE [tabUser] SET role='USER' WHERE role IN ('CASHIER','MANAGER');");
    }
  }

  void _ensurePlatformModules(CommonDatabase database) {
    if (!_tableExists(database, 'wmn_modules')) return;
    database.execute(r'''
      INSERT OR IGNORE INTO wmn_modules(
        name,label,app_name,icon,color,sequence_id,enabled,metadata_json,created_at,updated_at
      ) VALUES (
        'WMN System','WMN System',NULL,'hub',NULL,10,1,
        '{"source_framework":"WMN","system_platform":true}',datetime('now'),datetime('now')
      );
    ''');
    database.execute(r'''
      INSERT OR IGNORE INTO wmn_modules(
        name,label,app_name,icon,color,sequence_id,enabled,metadata_json,created_at,updated_at
      ) VALUES (
        'Security','Security',NULL,'shield',NULL,20,1,
        '{"source_framework":"WMN","system_capability":true,"optional":true}',datetime('now'),datetime('now')
      );
    ''');
  }

  bool _tableExists(CommonDatabase database, String name) => database.select(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;",
        [name],
      ).isNotEmpty;

  Set<String> _columns(CommonDatabase database, String table) => database
      .select('PRAGMA table_info("${table.replaceAll('"', '""')}");')
      .map((row) => '${row['name']}')
      .toSet();
}
