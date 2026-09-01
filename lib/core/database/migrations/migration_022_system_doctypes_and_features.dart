import 'database_migration.dart';

/// R3.7 System DocType + commercial feature-control foundation.
///
/// Reuses existing platform tables wherever possible. New storage is created
/// only for metadata that had no neutral owner yet (Page, Printer, Feature and
/// Feature Entitlement). This keeps startup/storage overhead small.
class Migration022SystemDocTypesAndFeatures extends SqlDatabaseMigration {
  const Migration022SystemDocTypesAndFeatures();

  @override
  int get version => 22;

  @override
  String get name => 'system_doctypes_and_features';

  @override
  String get sql => r'''
CREATE TABLE IF NOT EXISTS "tabPage" (
  name TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  route TEXT NOT NULL UNIQUE,
  app_name TEXT,
  module TEXT NOT NULL DEFAULT 'WMN System',
  page_type TEXT NOT NULL DEFAULT 'STANDARD' CHECK (page_type IN ('STANDARD','DASHBOARD','CUSTOM','LIST','FORM','REPORT','WORKSPACE')),
  controller_key TEXT,
  roles_json TEXT NOT NULL DEFAULT '[]',
  permissions_json TEXT NOT NULL DEFAULT '[]',
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (app_name) REFERENCES wmn_app_packages(app_name) ON DELETE SET NULL
) STRICT;

CREATE TABLE IF NOT EXISTS wmn_printers (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  connection_type TEXT NOT NULL DEFAULT 'SYSTEM',
  target TEXT,
  platform TEXT NOT NULL DEFAULT 'ANY',
  capabilities_json TEXT NOT NULL DEFAULT '[]',
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
) STRICT;

CREATE TABLE IF NOT EXISTS wmn_features (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  label TEXT NOT NULL,
  description TEXT,
  capability_ids_json TEXT NOT NULL DEFAULT '[]',
  price_amount REAL NOT NULL DEFAULT 0 CHECK (price_amount >= 0),
  currency TEXT NOT NULL DEFAULT 'USD',
  billing_period TEXT NOT NULL DEFAULT 'ONE_TIME' CHECK (billing_period IN ('ONE_TIME','MONTHLY','YEARLY','CUSTOM')),
  plan_code TEXT,
  is_core INTEGER NOT NULL DEFAULT 0 CHECK (is_core IN (0,1)),
  user_toggleable INTEGER NOT NULL DEFAULT 1 CHECK (user_toggleable IN (0,1)),
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
) STRICT;

CREATE TABLE IF NOT EXISTS wmn_feature_entitlements (
  id TEXT PRIMARY KEY,
  feature_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'GRANTED' CHECK (status IN ('GRANTED','TRIAL','EXPIRED','REVOKED')),
  source TEXT NOT NULL DEFAULT 'LOCAL' CHECK (source IN ('LOCAL','PLAN','LICENSE','TRIAL','ADMIN')),
  starts_at TEXT,
  expires_at TEXT,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  updated_at TEXT NOT NULL,
  UNIQUE(feature_id),
  FOREIGN KEY (feature_id) REFERENCES wmn_features(id) ON DELETE CASCADE
) STRICT;

CREATE INDEX IF NOT EXISTS idx_tab_page_enabled_route ON "tabPage"(enabled, route);
CREATE INDEX IF NOT EXISTS idx_wmn_printers_enabled ON wmn_printers(enabled, platform, name);
CREATE INDEX IF NOT EXISTS idx_wmn_features_enabled ON wmn_features(enabled, code);
CREATE INDEX IF NOT EXISTS idx_wmn_feature_entitlements_status ON wmn_feature_entitlements(status, feature_id);

CREATE TABLE IF NOT EXISTS wmn_feature_activations (
  feature_id TEXT NOT NULL,
  scope_type TEXT NOT NULL DEFAULT 'INSTALLATION' CHECK (scope_type IN ('INSTALLATION','USER')),
  scope_key TEXT NOT NULL DEFAULT 'local',
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
  updated_at TEXT NOT NULL,
  PRIMARY KEY(feature_id,scope_type,scope_key),
  FOREIGN KEY (feature_id) REFERENCES wmn_features(id) ON DELETE CASCADE
) STRICT;

CREATE INDEX IF NOT EXISTS idx_wmn_feature_activations_scope ON wmn_feature_activations(scope_type,scope_key,enabled);

INSERT INTO wmn_features(id,code,label,description,capability_ids_json,price_amount,currency,billing_period,plan_code,is_core,user_toggleable,enabled,metadata_json,created_at,updated_at)
VALUES
('feature-core-platform','core.platform','Core Platform','Required WMN platform runtime.','["lifecycle","doctype","metadata","create","save","sqlite","transactions","shell","i18n","system-settings","feature-registry","entitlements","feature-activation"]',0,'USD','ONE_TIME','CORE',1,0,1,'{}',datetime('now'),datetime('now')),
('feature-query-reports','reports.query','Query Reports','Metadata-defined query reports.','["query-reports"]',0,'USD','ONE_TIME',NULL,0,1,1,'{}',datetime('now'),datetime('now')),
('feature-script-reports','reports.script','Script Reports','Scripted reports for calculated and multi-step reporting.','["native-reports"]',0,'USD','ONE_TIME',NULL,0,1,1,'{}',datetime('now'),datetime('now')),
('feature-dashboard-charts','workspace.charts','Dashboard Charts','Workspace dashboard chart aggregation and rendering.','["workspace-registry"]',0,'USD','ONE_TIME',NULL,0,1,1,'{}',datetime('now'),datetime('now')),
('feature-printing','printing','Printing','Print formats, jobs and platform print adapters.','["print-contract","print-jobs","print-formats","pdf-contract","platform-print-adapters"]',0,'USD','ONE_TIME',NULL,0,1,1,'{}',datetime('now'),datetime('now')),
('feature-developer-tools','developer.tools','Developer Tools','DocType studio and application conversion tooling.','["doctype-studio","source-parity","app-converter"]',0,'USD','ONE_TIME',NULL,0,1,1,'{}',datetime('now'),datetime('now')),
('feature-diagnostics','system.diagnostics','Diagnostics','System diagnostics and health snapshots.','["diagnostics","health-snapshot"]',0,'USD','ONE_TIME',NULL,0,1,1,'{}',datetime('now'),datetime('now')),
('feature-scheduler','system.scheduler','Scheduler','Background jobs and schedules.','["scheduler","background-jobs","queues","schedule-registry"]',0,'USD','ONE_TIME',NULL,0,1,1,'{}',datetime('now'),datetime('now')),
('feature-notifications','system.notifications','Notifications','In-app and delivery notification contracts.','["in-app-notifications","notification-outbox","email-contract","sms-contract","push-contract"]',0,'USD','ONE_TIME',NULL,0,1,1,'{}',datetime('now'),datetime('now'))
ON CONFLICT(id) DO NOTHING;

INSERT OR IGNORE INTO wmn_feature_entitlements(id,feature_id,status,source,updated_at)
SELECT 'entitlement-' || id,id,'GRANTED','LOCAL',datetime('now') FROM wmn_features;

INSERT OR IGNORE INTO wmn_feature_activations(feature_id,scope_type,scope_key,enabled,updated_at)
SELECT id,'INSTALLATION','local',1,datetime('now') FROM wmn_features;

INSERT INTO wmn_doctypes(name,module,storage_mode,table_name,id_field,title_field,autoname,is_single,is_child,is_submittable,track_changes,allow_create,allow_edit,allow_delete,allow_import,allow_export,generic_write,is_system,enabled,metadata_json,created_at,updated_at)
VALUES
('User','Security','TABLE','tabUser','id','display_name',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{}',datetime('now'),datetime('now')),
('Role','Security','TABLE','roles','id','name',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{}',datetime('now'),datetime('now')),
('Permission','Security','TABLE','permissions','id','code',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{}',datetime('now'),datetime('now')),
('User Role','Security','TABLE','user_roles','id','user_id',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{}',datetime('now'),datetime('now')),
('Application','WMN System','TABLE','wmn_app_packages','app_name','app_name',NULL,0,0,0,1,0,0,0,0,1,0,1,1,'{"runtime_owned":true}',datetime('now'),datetime('now')),
('Module','WMN System','TABLE','wmn_modules','name','label',NULL,0,0,0,1,0,1,0,0,1,0,1,1,'{"runtime_owned":true}',datetime('now'),datetime('now')),
('Page','WMN System','TABLE','tabPage','name','title',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{}',datetime('now'),datetime('now')),
('Workspace','WMN System','TABLE','tabWorkspace','name','label',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{}',datetime('now'),datetime('now')),
('Report','WMN System','TABLE','tabReport','name','report_name',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{"report_types":["Query Report","Script Report"]}',datetime('now'),datetime('now')),
('Print Format','WMN System','TABLE','print_formats','id','name',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{}',datetime('now'),datetime('now')),
('Print Settings','WMN System','TABLE','print_settings','id','name',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{}',datetime('now'),datetime('now')),
('Printer','WMN System','TABLE','wmn_printers','id','name',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{}',datetime('now'),datetime('now')),
('Notification','WMN System','TABLE','wmn_notifications','id','title',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{}',datetime('now'),datetime('now')),
('Scheduled Job','WMN System','TABLE','wmn_schedules','id','name',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{}',datetime('now'),datetime('now')),
('File','WMN System','TABLE','wmn_files','id','file_name',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{}',datetime('now'),datetime('now')),
('System Setting','WMN System','TABLE','wmn_scoped_settings','setting_key','setting_key',NULL,0,0,0,1,0,0,0,0,1,0,1,1,'{"runtime_owned":true}',datetime('now'),datetime('now')),
('System Log','WMN System','TABLE','wmn_system_logs','id','message',NULL,0,0,0,0,0,0,0,0,1,0,1,1,'{"read_only":true}',datetime('now'),datetime('now')),
('Audit Log','WMN System','TABLE','audit_log','id','action',NULL,0,0,0,0,0,0,0,0,1,0,1,1,'{"read_only":true}',datetime('now'),datetime('now')),
('Background Job','WMN System','TABLE','wmn_background_jobs','id','handler_name',NULL,0,0,0,0,0,0,0,0,1,0,1,1,'{"runtime_owned":true}',datetime('now'),datetime('now')),
('Feature','WMN System','TABLE','wmn_features','id','label',NULL,0,0,0,1,0,1,0,0,1,0,1,1,'{"commercial":true}',datetime('now'),datetime('now')),
('Feature Entitlement','WMN System','TABLE','wmn_feature_entitlements','id','feature_id',NULL,0,0,0,1,0,1,0,0,1,0,1,1,'{"commercial":true}',datetime('now'),datetime('now')),
('Feature Activation','WMN System','TABLE','wmn_feature_activations','feature_id','feature_id',NULL,0,0,0,1,0,1,0,0,1,0,1,1,'{"local_activation":true}',datetime('now'),datetime('now'))
ON CONFLICT(name) DO UPDATE SET
  module=excluded.module,storage_mode=excluded.storage_mode,table_name=excluded.table_name,id_field=excluded.id_field,
  title_field=excluded.title_field,generic_write=excluded.generic_write,is_system=1,enabled=1,
  metadata_json=excluded.metadata_json,updated_at=excluded.updated_at;
''';
}
