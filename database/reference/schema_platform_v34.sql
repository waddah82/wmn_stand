BEGIN TRANSACTION;
CREATE TABLE app_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL
) STRICT;
CREATE TABLE audit_log (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        action TEXT NOT NULL,
        user_id TEXT,
        payload_json TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL
      ) STRICT;
CREATE TABLE client_scripts (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  document_type TEXT NOT NULL,
  priority INTEGER NOT NULL DEFAULT 0,
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL, source_storage_path TEXT,
  UNIQUE(document_type, name)
) STRICT;
CREATE TABLE custom_field_values (
  document_type TEXT NOT NULL,
  document_id TEXT NOT NULL,
  field_name TEXT NOT NULL,
  value_json TEXT,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(document_type, document_id, field_name)
) STRICT;
CREATE TABLE custom_fields (
  id TEXT PRIMARY KEY,
  document_type TEXT NOT NULL,
  field_name TEXT NOT NULL,
  label TEXT NOT NULL,
  field_type TEXT NOT NULL CHECK (field_type IN (
    'DATA','TEXT','INT','FLOAT','CURRENCY','CHECK','SELECT','DATE','DATETIME','LINK','JSON'
  )),
  insert_after TEXT,
  options_json TEXT NOT NULL DEFAULT '[]',
  default_value_json TEXT,
  required INTEGER NOT NULL DEFAULT 0 CHECK (required IN (0, 1)),
  read_only INTEGER NOT NULL DEFAULT 0 CHECK (read_only IN (0, 1)),
  hidden INTEGER NOT NULL DEFAULT 0 CHECK (hidden IN (0, 1)),
  in_list_view INTEGER NOT NULL DEFAULT 0 CHECK (in_list_view IN (0, 1)),
  searchable INTEGER NOT NULL DEFAULT 0 CHECK (searchable IN (0, 1)),
  sort_order INTEGER NOT NULL DEFAULT 0,
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(document_type, field_name)
) STRICT;
CREATE TABLE data_export_jobs (
  id TEXT PRIMARY KEY,
  doctype TEXT NOT NULL,
  format TEXT NOT NULL CHECK (format IN ('CSV','XLSX','JSON')),
  fields_json TEXT NOT NULL DEFAULT '[]',
  filters_json TEXT NOT NULL DEFAULT '[]',
  row_count INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
) STRICT;
CREATE TABLE data_import_jobs (
  id TEXT PRIMARY KEY,
  doctype TEXT NOT NULL,
  import_mode TEXT NOT NULL CHECK (import_mode IN ('INSERT','UPDATE','UPSERT')),
  file_name TEXT,
  status TEXT NOT NULL CHECK (status IN ('DRAFT','VALIDATED','COMPLETED','PARTIAL','FAILED')),
  total_rows INTEGER NOT NULL DEFAULT 0,
  success_rows INTEGER NOT NULL DEFAULT 0,
  failed_rows INTEGER NOT NULL DEFAULT 0,
  options_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  completed_at TEXT
) STRICT;
CREATE TABLE data_import_rows (
  id TEXT PRIMARY KEY,
  job_id TEXT NOT NULL,
  row_number INTEGER NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('PENDING','VALID','SUCCESS','ERROR')),
  document_name TEXT,
  row_json TEXT NOT NULL,
  error_text TEXT,
  FOREIGN KEY (job_id) REFERENCES data_import_jobs(id) ON DELETE CASCADE
) STRICT;
CREATE TABLE file_settings (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  default_content_mode TEXT NOT NULL DEFAULT 'MANAGED_STORAGE'
    CHECK(default_content_mode IN ('MANAGED_STORAGE','EXTERNAL_REFERENCE')),
  allow_external_reference INTEGER NOT NULL DEFAULT 1
    CHECK(allow_external_reference IN (0,1)),
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
) STRICT;
INSERT INTO "file_settings" VALUES('default','Default','MANAGED_STORAGE',1,'{"storage_optional":true,"external_reference_platform_gated":true}','2026-08-30 00:26:30','2026-08-30 00:26:30');
CREATE TABLE numbering_series (
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
CREATE TABLE permissions (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  module TEXT NOT NULL,
  resource TEXT NOT NULL,
  action TEXT NOT NULL,
  description TEXT,
  created_at TEXT NOT NULL
) STRICT;
INSERT INTO "permissions" VALUES('wmn-permission-security-manage','wmn.security.manage','Security','security','manage','Manage WMN identity and permission metadata','2026-08-28T17:45:00Z');
INSERT INTO "permissions" VALUES('wmn-permission-workflow-manage','wmn.workflow.manage','Workflow','workflow','manage','Manage WMN workflows and approval metadata','2026-08-28 21:47:40');
CREATE TABLE print_formats (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  format_type TEXT NOT NULL DEFAULT 'DOCUMENT',
  template_json TEXT NOT NULL DEFAULT '{}',
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
, target_type TEXT NOT NULL DEFAULT 'DOCUMENT'
  CHECK(target_type IN ('DOCUMENT','REPORT','GENERAL_REPORT','PLATFORM')), document_type TEXT, report_name TEXT, renderer_id TEXT NOT NULL DEFAULT 'pdf', template_text TEXT NOT NULL DEFAULT '', css_text TEXT NOT NULL DEFAULT '', is_default INTEGER NOT NULL DEFAULT 0 CHECK(is_default IN (0,1)), paper_width_mm REAL NOT NULL DEFAULT 210 CHECK(paper_width_mm > 0), paper_height_mm REAL NOT NULL DEFAULT 297 CHECK(paper_height_mm > 0), margin_mm REAL NOT NULL DEFAULT 10 CHECK(margin_mm >= 0), metadata_json TEXT NOT NULL DEFAULT '{}') STRICT;
INSERT INTO "print_formats" VALUES('print-format-platform-default','WMN-PLATFORM-DEFAULT','WMN Platform Default','PLATFORM','{}',1,'2026-08-29 23:29:37','2026-08-29 23:29:37','PLATFORM',NULL,NULL,'pdf','{{ document }}','',1,210.0,297.0,10.0,'{"protected":true,"fallback":true}');
INSERT INTO "print_formats" VALUES('print-format-general-report','WMN-GENERAL-REPORT','General Report Print Format','REPORT','{}',1,'2026-08-29 23:29:37','2026-08-30 15:04:44','GENERAL_REPORT',NULL,NULL,'pdf','<h1>{{ report.title }}</h1>
{{ report.filters_block }}
{{ report.table }}','',1,210.0,297.0,10.0,'{"protected":1,"general_report":1,"structured_report":1,"auto_landscape":1,"repeat_table_header":1}');
CREATE TABLE print_jobs (
  id TEXT PRIMARY KEY,
  document_type TEXT NOT NULL,
  document_name TEXT NOT NULL,
  connection_type TEXT NOT NULL,
  printer_target TEXT,
  status TEXT NOT NULL CHECK (status IN ('PENDING', 'SENT', 'FAILED')),
  error_message TEXT,
  created_at TEXT NOT NULL,
  completed_at TEXT
, source_type TEXT NOT NULL DEFAULT 'DOCUMENT'
  CHECK(source_type IN ('DOCUMENT','REPORT')), print_format_id TEXT, printer_id TEXT, renderer_id TEXT, output_file_id TEXT, mime_type TEXT, byte_count INTEGER NOT NULL DEFAULT 0 CHECK(byte_count >= 0), request_json TEXT NOT NULL DEFAULT '{}') STRICT;
CREATE TABLE print_settings (
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
  updated_at TEXT NOT NULL, default_document_format_id TEXT, general_report_format_id TEXT, default_printer_id TEXT, preview_renderer_id TEXT NOT NULL DEFAULT 'html', pdf_renderer_id TEXT NOT NULL DEFAULT 'pdf', metadata_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (print_format_id) REFERENCES print_formats(id)
) STRICT;
INSERT INTO "print_settings" VALUES('print-settings-default','Default',NULL,'PREVIEW',NULL,NULL,9100,NULL,9600,80,0,0,1,NULL,NULL,NULL,NULL,NULL,NULL,'DOCUMENT','2026-08-29 23:29:37','print-format-platform-default','print-format-general-report',NULL,'html','pdf','{"platform_default":true}');
CREATE TABLE property_overrides (
  id TEXT PRIMARY KEY,
  document_type TEXT NOT NULL,
  field_name TEXT NOT NULL,
  property_name TEXT NOT NULL CHECK (property_name IN (
    'label','required','read_only','hidden','default','options','in_list_view','searchable'
  )),
  value_json TEXT NOT NULL,
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(document_type, field_name, property_name)
) STRICT;
CREATE TABLE "report_run_log"(id TEXT PRIMARY KEY,report_id TEXT,report_name TEXT NOT NULL,status TEXT NOT NULL CHECK(status IN ('SUCCESS','ERROR')),row_count INTEGER NOT NULL DEFAULT 0,duration_ms INTEGER NOT NULL DEFAULT 0,error_text TEXT,created_at TEXT NOT NULL,FOREIGN KEY(report_id) REFERENCES tabReport(name) ON DELETE SET NULL) STRICT;
CREATE TABLE role_permissions (
  role_id TEXT NOT NULL,
  permission_id TEXT NOT NULL,
  granted INTEGER NOT NULL DEFAULT 1 CHECK (granted IN (0, 1)), id TEXT,
  PRIMARY KEY (role_id, permission_id),
  FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE,
  FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE
) STRICT;
CREATE TABLE roles (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  is_system INTEGER NOT NULL DEFAULT 0 CHECK (is_system IN (0, 1)),
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
) STRICT;
CREATE TABLE script_execution_log (
  id TEXT PRIMARY KEY,
  script_kind TEXT NOT NULL CHECK (script_kind IN ('CLIENT','SERVER')),
  script_id TEXT,
  script_name TEXT NOT NULL,
  document_type TEXT,
  document_id TEXT,
  event_name TEXT,
  status TEXT NOT NULL CHECK (status IN ('SUCCESS','ERROR','BLOCKED')),
  duration_ms INTEGER NOT NULL DEFAULT 0,
  messages_json TEXT NOT NULL DEFAULT '[]',
  error_text TEXT,
  created_at TEXT NOT NULL
) STRICT;
CREATE TABLE server_scripts (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  script_type TEXT NOT NULL DEFAULT 'DOCUMENT_EVENT' CHECK (script_type IN ('DOCUMENT_EVENT','API','SCHEDULED')),
  document_type TEXT,
  event_name TEXT,
  api_method TEXT,
  priority INTEGER NOT NULL DEFAULT 0,
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL, source_storage_path TEXT,
  CHECK (
    (script_type = 'DOCUMENT_EVENT' AND document_type IS NOT NULL AND event_name IS NOT NULL)
    OR (script_type = 'API' AND api_method IS NOT NULL)
    OR (script_type = 'SCHEDULED')
  ),
  UNIQUE(script_type, name)
) STRICT;
CREATE TABLE system_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      ) STRICT;
INSERT INTO "system_meta" VALUES('schema_version','34','2026-08-30 15:04:44');
CREATE TABLE "tabPage" (
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
INSERT INTO "tabPage" VALUES('Runtime Lab - Standard','Runtime Lab - Standard','/system/runtime-lab/standard',NULL,'WMN System','STANDARD',NULL,'["System Manager"]','[]',1,'{"show_in_navigation":false,"runtime_lab":true,"layout":[{"type":"heading","label":"Standard / Declarative Page"},{"type":"text","text":"Metadata-driven content without compiled business code."},{"type":"page","label":"Open Runtime Lab List","target":"Runtime Lab - List"}]}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "tabPage" VALUES('Runtime Lab - Dashboard','Runtime Lab - Dashboard','/system/runtime-lab/dashboard',NULL,'WMN System','DASHBOARD',NULL,'["System Manager"]','[]',1,'{"show_in_navigation":false,"runtime_lab":true,"workspace":"Runtime Laboratory"}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "tabPage" VALUES('Runtime Lab - Custom','Runtime Lab - Custom','/system/runtime-lab/custom',NULL,'WMN System','CUSTOM',NULL,'["System Manager"]','[]',1,'{"show_in_navigation":false,"runtime_lab":true,"layout":[{"type":"heading","label":"Custom Metadata Page"},{"type":"text","text":"CUSTOM pages can be metadata-only or use a registered native controller."}]}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "tabPage" VALUES('Runtime Lab - List','Runtime Lab - List','/system/runtime-lab/list',NULL,'WMN System','LIST',NULL,'["System Manager"]','[]',1,'{"show_in_navigation":false,"runtime_lab":true,"doctype":"Page"}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "tabPage" VALUES('Runtime Lab - Form','Runtime Lab - Form','/system/runtime-lab/form',NULL,'WMN System','FORM',NULL,'["System Manager"]','[]',1,'{"show_in_navigation":false,"runtime_lab":true,"doctype":"File Settings","document_name":"default"}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "tabPage" VALUES('Runtime Lab - Report','Runtime Lab - Report','/system/runtime-lab/report',NULL,'WMN System','REPORT',NULL,'["System Manager"]','[]',1,'{"show_in_navigation":false,"runtime_lab":true,"report":"Example - Query Report - DocType Search"}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "tabPage" VALUES('Runtime Lab - Workspace','Runtime Lab - Workspace','/system/runtime-lab/workspace',NULL,'WMN System','WORKSPACE',NULL,'["System Manager"]','[]',1,'{"show_in_navigation":false,"runtime_lab":true,"workspace":"Runtime Laboratory"}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "tabPage" VALUES('Data Import / Export Tool','Data Import / Export','/system/tools/data-import-export',NULL,'WMN System','CUSTOM','wmn.tool.data_exchange','["System Manager"]','[]',1,'{"show_in_navigation":true,"section":"Tools","order":10,"runtime_category":"TOOL","runtime_lab":true}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "tabPage" VALUES('Workspace Builder','Workspace Builder','/system/developer/workspaces',NULL,'WMN System','LIST',NULL,'["System Manager"]','[]',1,'{"show_in_navigation":true,"section":"Developer","order":20,"doctype":"Workspace","runtime_category":"BUILDER","workspace_builder":true}','2026-08-30 01:49:37','2026-08-30 01:49:37');
CREATE TABLE "tabReport" (
  name TEXT PRIMARY KEY,
  report_name TEXT NOT NULL UNIQUE,
  ref_doctype TEXT,
  report_type TEXT NOT NULL CHECK(report_type IN ('Report Builder','Query Report','Script Report','Custom Report')),
  module TEXT NOT NULL DEFAULT 'Custom',
  is_standard INTEGER NOT NULL DEFAULT 0 CHECK(is_standard IN (0,1)),
  disabled INTEGER NOT NULL DEFAULT 0 CHECK(disabled IN (0,1)),
  query_definition_json TEXT NOT NULL DEFAULT '{}',
  script_key TEXT,
  filters_json TEXT NOT NULL DEFAULT '[]',
  columns_json TEXT NOT NULL DEFAULT '[]',
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
, query_source_type TEXT NOT NULL DEFAULT 'INLINE' CHECK(query_source_type IN ('INLINE','STORAGE_FILE','STRUCTURED')), query_source_path TEXT, script_source_type TEXT NOT NULL DEFAULT 'NATIVE_HANDLER' CHECK(script_source_type IN ('NATIVE_HANDLER','STORAGE_FILE')), script_source_path TEXT, script_language TEXT, source_hash TEXT) STRICT;
INSERT INTO "tabReport" VALUES('wmn-example-report-builder','Example - Report Builder - DocType Catalog','DocType','Report Builder','WMN System',1,0,'{"source_key": "doctype:DocType", "columns": [{"field": "name", "label": "DocType", "aggregate": "NONE"}, {"field": "module", "label": "Module", "aggregate": "NONE"}, {"field": "storage_mode", "label": "Storage Mode", "aggregate": "NONE"}, {"field": "enabled", "label": "Enabled", "aggregate": "NONE"}], "filters": [{"field": "module", "operator": "CONTAINS", "value": "WMN System", "parameter_name": "module_contains", "label": "Module", "label_ar": "الوحدة", "field_type": "Link", "options": "Module", "required": false, "user_editable": true}, {"field": "enabled", "operator": "EQ", "value": 1, "parameter_name": "enabled_only", "label": "Enabled", "label_ar": "مفعّل", "field_type": "Check", "required": false, "user_editable": true}], "sorts": [{"field": "name", "descending": false}], "limit": 200}',NULL,'[{"fieldname": "module_contains", "label": "Module", "label_ar": "الوحدة", "fieldtype": "Link", "options": "Module", "required": false, "default": "WMN System", "user_editable": true}, {"fieldname": "enabled_only", "label": "Enabled", "label_ar": "مفعّل", "fieldtype": "Check", "required": false, "default": 1, "user_editable": true}]','[{"fieldname": "name", "label": "DocType", "aggregate": "NONE"}, {"fieldname": "module", "label": "Module", "aggregate": "NONE"}, {"fieldname": "storage_mode", "label": "Storage Mode", "aggregate": "NONE"}, {"fieldname": "enabled", "label": "Enabled", "aggregate": "NONE"}]','{"tutorial_example": true, "description": "x", "creation_steps": ["a"], "notes": ["b"], "description_ar": "\u0633", "creation_steps_ar": ["\u0627"], "notes_ar": ["\u0628"]}','2026-08-29T22:30:00Z','2026-08-29T00:00:00Z','STRUCTURED',NULL,'NATIVE_HANDLER',NULL,NULL,NULL);
INSERT INTO "tabReport" VALUES('wmn-example-query-report','Example - Query Report - DocType Search','DocType','Query Report','WMN System',1,0,'{"sql": "SELECT name AS doctype, module, storage_mode, enabled, created_at\nFROM wmn_doctypes\nWHERE (%(module)s = '''' OR module LIKE ''%'' || %(module)s || ''%'')\n  AND (%(doctype)s = '''' OR name LIKE ''%'' || %(doctype)s || ''%'')\n  AND (%(created_from)s = '''' OR date(created_at) >= date(%(created_from)s))\n  AND (\n    %(enabled_state)s = ''All''\n    OR (%(enabled_state)s = ''Enabled'' AND enabled = 1)\n    OR (%(enabled_state)s = ''Disabled'' AND enabled = 0)\n  )\nORDER BY module COLLATE NOCASE, name COLLATE NOCASE\nLIMIT 200", "max_rows": 200}',NULL,'[{"fieldname": "module", "label": "Module", "label_ar": "الوحدة", "fieldtype": "Link", "options": "Module", "required": false, "default": "WMN System"}, {"fieldname": "doctype", "label": "DocType Contains", "label_ar": "اسم DocType يحتوي", "fieldtype": "Data", "required": false, "default": ""}, {"fieldname": "created_from", "label": "Created From", "label_ar": "تاريخ الإنشاء من", "fieldtype": "Date", "required": false, "default": ""}, {"fieldname": "enabled_state", "label": "Status", "label_ar": "الحالة", "fieldtype": "Select", "options": "All\nEnabled\nDisabled", "required": true, "default": "All"}]','[{"fieldname": "doctype", "label": "DocType", "fieldtype": "Data"}, {"fieldname": "module", "label": "Module", "fieldtype": "Data"}, {"fieldname": "storage_mode", "label": "Storage Mode", "fieldtype": "Data"}, {"fieldname": "enabled", "label": "Enabled", "fieldtype": "Check"}, {"fieldname": "created_at", "label": "Created At", "fieldtype": "Datetime"}]','{"tutorial_example": true, "description": "x", "creation_steps": ["a"], "notes": ["b"], "description_ar": "\u0633", "creation_steps_ar": ["\u0627"], "notes_ar": ["\u0628"]}','2026-08-29T22:30:00Z','2026-08-29T00:00:00Z','INLINE',NULL,'NATIVE_HANDLER',NULL,NULL,NULL);
INSERT INTO "tabReport" VALUES('wmn-example-script-report','Example - Script Report - Module Summary','DocType','Script Report','WMN System',1,0,'{}','wmn.examples.reports.module_summary','[{"fieldname": "module", "label": "Module", "label_ar": "الوحدة", "fieldtype": "Link", "options": "Module", "required": false, "default": ""}]','[{"fieldname":"module","label":"Module","fieldtype":"Data"},{"fieldname":"doctype_count","label":"DocTypes","fieldtype":"Int"},{"fieldname":"field_count","label":"Fields","fieldtype":"Int"},{"fieldname":"required_field_count","label":"Required Fields","fieldtype":"Int"}]','{"tutorial_example":true,"description":"A compiled native Script Report that joins DocType metadata with field metadata and returns a module summary.","description_ar":"تقرير Script مترجم يستخدم JOIN حقيقي بين جدول DocTypes وجدول الحقول ثم يعرض ملخص الوحدات.","creation_steps":["Create a Report and choose Script Report.","Choose a Reference DocType for permission checks.","Define filters and output columns in the child tables.","Use a registered NATIVE_HANDLER key for compiled Dart logic.","The built-in example joins wmn_doctypes and wmn_doctype_fields."],"source_preview":"final module = ''${filters[''module''] ?? ''''}''.trim();\nfinal rows = database.db.select(''''''\n  SELECT d.module,\n         COUNT(DISTINCT d.name) AS doctype_count,\n         COUNT(f.id) AS field_count,\n         SUM(CASE WHEN f.reqd=1 THEN 1 ELSE 0 END) AS required_field_count\n  FROM wmn_doctypes d\n  LEFT JOIN wmn_doctype_fields f ON f.doctype = d.name\n  WHERE (? = '''' OR d.module LIKE ''%'' || ? || ''%'')\n  GROUP BY d.module\n  ORDER BY doctype_count DESC, d.module COLLATE NOCASE\n  LIMIT 200;\n'''''', <Object?>[module, module]);"}','2026-08-29T22:30:00Z','2026-08-29T20:54:55.861133+00:00','INLINE',NULL,'NATIVE_HANDLER',NULL,NULL,NULL);
CREATE TABLE [tabReport Column] (
  name TEXT PRIMARY KEY,
  parent TEXT NOT NULL,
  parentfield TEXT NOT NULL DEFAULT 'columns',
  parenttype TEXT NOT NULL DEFAULT 'Report',
  idx INTEGER NOT NULL DEFAULT 0,
  fieldname TEXT NOT NULL,
  label TEXT NOT NULL,
  label_ar TEXT,
  fieldtype TEXT NOT NULL DEFAULT 'Data',
  options TEXT,
  width REAL,
  precision INTEGER,
  alignment TEXT,
  aggregate TEXT,
  hidden INTEGER NOT NULL DEFAULT 0 CHECK (hidden IN (0,1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(parent) REFERENCES [tabReport](name) ON DELETE CASCADE
);
INSERT INTO "tabReport Column" VALUES('wmn-example-query-report-column-1','wmn-example-query-report','columns','Report',1,'doctype','DocType',NULL,'Data',NULL,NULL,NULL,NULL,'NONE',0,'2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "tabReport Column" VALUES('wmn-example-query-report-column-2','wmn-example-query-report','columns','Report',2,'module','Module',NULL,'Data',NULL,NULL,NULL,NULL,'NONE',0,'2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "tabReport Column" VALUES('wmn-example-query-report-column-3','wmn-example-query-report','columns','Report',3,'storage_mode','Storage Mode',NULL,'Data',NULL,NULL,NULL,NULL,'NONE',0,'2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "tabReport Column" VALUES('wmn-example-query-report-column-4','wmn-example-query-report','columns','Report',4,'enabled','Enabled',NULL,'Check',NULL,NULL,NULL,NULL,'NONE',0,'2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "tabReport Column" VALUES('wmn-example-query-report-column-5','wmn-example-query-report','columns','Report',5,'created_at','Created At',NULL,'Datetime',NULL,NULL,NULL,NULL,'NONE',0,'2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "tabReport Column" VALUES('wmn-example-report-builder-column-1','wmn-example-report-builder','columns','Report',1,'name','DocType',NULL,'Data',NULL,NULL,NULL,NULL,'NONE',0,'2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "tabReport Column" VALUES('wmn-example-report-builder-column-2','wmn-example-report-builder','columns','Report',2,'module','Module',NULL,'Data',NULL,NULL,NULL,NULL,'NONE',0,'2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "tabReport Column" VALUES('wmn-example-report-builder-column-3','wmn-example-report-builder','columns','Report',3,'storage_mode','Storage Mode',NULL,'Data',NULL,NULL,NULL,NULL,'NONE',0,'2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "tabReport Column" VALUES('wmn-example-report-builder-column-4','wmn-example-report-builder','columns','Report',4,'enabled','Enabled',NULL,'Data',NULL,NULL,NULL,NULL,'NONE',0,'2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "tabReport Column" VALUES('wmn-example-script-report-column-1','wmn-example-script-report','columns','Report',1,'module','Module',NULL,'Data',NULL,NULL,NULL,NULL,'NONE',0,'2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "tabReport Column" VALUES('wmn-example-script-report-column-2','wmn-example-script-report','columns','Report',2,'doctype_count','DocTypes',NULL,'Int',NULL,NULL,NULL,NULL,'NONE',0,'2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "tabReport Column" VALUES('wmn-example-script-report-column-3','wmn-example-script-report','columns','Report',3,'field_count','Fields',NULL,'Int',NULL,NULL,NULL,NULL,'NONE',0,'2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "tabReport Column" VALUES('wmn-example-script-report-column-4','wmn-example-script-report','columns','Report',4,'required_field_count','Required Fields',NULL,'Int',NULL,NULL,NULL,NULL,'NONE',0,'2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
CREATE TABLE [tabReport Filter] (
  name TEXT PRIMARY KEY,
  parent TEXT NOT NULL,
  parentfield TEXT NOT NULL DEFAULT 'filters',
  parenttype TEXT NOT NULL DEFAULT 'Report',
  idx INTEGER NOT NULL DEFAULT 0,
  fieldname TEXT NOT NULL,
  label TEXT NOT NULL,
  label_ar TEXT,
  fieldtype TEXT NOT NULL DEFAULT 'Data',
  options TEXT,
  required INTEGER NOT NULL DEFAULT 0 CHECK (required IN (0,1)),
  "default" TEXT,
  depends_on TEXT,
  user_editable INTEGER NOT NULL DEFAULT 1 CHECK (user_editable IN (0,1)),
  source_field TEXT,
  operator TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(parent) REFERENCES [tabReport](name) ON DELETE CASCADE
);
INSERT INTO "tabReport Filter" VALUES('wmn-example-query-report-filter-1','wmn-example-query-report','filters','Report',1,'module','Module','الوحدة','Link','Module',0,'WMN System',NULL,1,'module','EQ','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "tabReport Filter" VALUES('wmn-example-query-report-filter-2','wmn-example-query-report','filters','Report',2,'doctype','DocType Contains','اسم DocType يحتوي','Data',NULL,0,'',NULL,1,'doctype','EQ','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "tabReport Filter" VALUES('wmn-example-query-report-filter-3','wmn-example-query-report','filters','Report',3,'created_from','Created From','تاريخ الإنشاء من','Date',NULL,0,'',NULL,1,'created_from','EQ','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "tabReport Filter" VALUES('wmn-example-query-report-filter-4','wmn-example-query-report','filters','Report',4,'enabled_state','Status','الحالة','Select','All
Enabled
Disabled',1,'All',NULL,1,'enabled_state','EQ','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "tabReport Filter" VALUES('wmn-example-report-builder-filter-1','wmn-example-report-builder','filters','Report',1,'module_contains','Module','الوحدة','Link','Module',0,'WMN System',NULL,1,'module','CONTAINS','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "tabReport Filter" VALUES('wmn-example-report-builder-filter-2','wmn-example-report-builder','filters','Report',2,'enabled_only','Enabled','مفعّل','Check',NULL,0,'1',NULL,1,'enabled','EQ','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "tabReport Filter" VALUES('wmn-example-script-report-filter-1','wmn-example-script-report','filters','Report',1,'module','Module','الوحدة','Link','Module',0,'',NULL,1,'module','EQ','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
CREATE TABLE "tabSingles" (
  doctype TEXT NOT NULL,
  field TEXT NOT NULL,
  value TEXT,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (doctype, field)
) STRICT;
CREATE TABLE "tabUser" (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  pin_hash TEXT,
  role TEXT NOT NULL DEFAULT 'USER',
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
) STRICT;
CREATE TABLE "tabWorkspace" (
  name TEXT PRIMARY KEY,
  label TEXT NOT NULL,
  module TEXT NOT NULL DEFAULT 'Custom',
  app_name TEXT,
  icon TEXT,
  parent_page TEXT,
  sequence_id REAL NOT NULL DEFAULT 0,
  is_public INTEGER NOT NULL DEFAULT 1 CHECK (is_public IN (0,1)),
  is_hidden INTEGER NOT NULL DEFAULT 0 CHECK (is_hidden IN (0,1)),
  content_json TEXT NOT NULL DEFAULT '[]',
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (app_name) REFERENCES wmn_app_packages(app_name) ON DELETE SET NULL
) STRICT;
INSERT INTO "tabWorkspace" VALUES('Runtime Laboratory','Runtime Laboratory','WMN System',NULL,'science',NULL,-50.0,1,0,'[]','{"system_workspace":true,"runtime_lab":true,"required_roles":["System Manager"]}','2026-08-30 01:49:37','2026-08-30 01:49:37');
CREATE TABLE [tabWorkspaceItem] (
  name TEXT PRIMARY KEY,
  owner TEXT,
  creation TEXT NOT NULL,
  modified TEXT NOT NULL,
  modified_by TEXT,
  docstatus INTEGER NOT NULL DEFAULT 0 CHECK (docstatus IN (0,1,2)),
  idx INTEGER NOT NULL DEFAULT 0,
  parent TEXT NOT NULL,
  parentfield TEXT NOT NULL DEFAULT 'items',
  parenttype TEXT NOT NULL DEFAULT 'Workspace',
  region TEXT NOT NULL DEFAULT 'CONTENT' CHECK (region IN ('CONTENT','LINKS','SHORTCUTS','SIDEBAR','CHARTS','NUMBER_CARDS','QUICK_LISTS')),
  item_type TEXT NOT NULL DEFAULT 'shortcut',
  label TEXT,
  link_type TEXT,
  link_to TEXT,
  icon TEXT,
  parent_label TEXT,
  column_span INTEGER NOT NULL DEFAULT 4 CHECK (column_span BETWEEN 1 AND 12),
  hidden INTEGER NOT NULL DEFAULT 0 CHECK (hidden IN (0,1)),
  required_feature TEXT,
  description TEXT,
  item_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (parent) REFERENCES [tabWorkspace](name) ON DELETE CASCADE
) STRICT;
INSERT INTO "tabWorkspaceItem" VALUES('runtime-lab-page-standard',NULL,'2026-08-30 01:49:37','2026-08-30 01:49:37',NULL,0,1,'Runtime Laboratory','items','Workspace','CONTENT','shortcut','Standard Page','Page','Runtime Lab - Standard',NULL,NULL,4,0,NULL,NULL,'{}');
INSERT INTO "tabWorkspaceItem" VALUES('runtime-lab-page-dashboard',NULL,'2026-08-30 01:49:37','2026-08-30 01:49:37',NULL,0,2,'Runtime Laboratory','items','Workspace','CONTENT','shortcut','Dashboard Page','Page','Runtime Lab - Dashboard',NULL,NULL,4,0,NULL,NULL,'{}');
INSERT INTO "tabWorkspaceItem" VALUES('runtime-lab-page-custom',NULL,'2026-08-30 01:49:37','2026-08-30 01:49:37',NULL,0,3,'Runtime Laboratory','items','Workspace','CONTENT','shortcut','Custom Page','Page','Runtime Lab - Custom',NULL,NULL,4,0,NULL,NULL,'{}');
INSERT INTO "tabWorkspaceItem" VALUES('runtime-lab-page-list',NULL,'2026-08-30 01:49:37','2026-08-30 01:49:37',NULL,0,4,'Runtime Laboratory','items','Workspace','CONTENT','shortcut','List Page','Page','Runtime Lab - List',NULL,NULL,4,0,NULL,NULL,'{}');
INSERT INTO "tabWorkspaceItem" VALUES('runtime-lab-page-form',NULL,'2026-08-30 01:49:37','2026-08-30 01:49:37',NULL,0,5,'Runtime Laboratory','items','Workspace','CONTENT','shortcut','Form Page','Page','Runtime Lab - Form',NULL,NULL,4,0,NULL,NULL,'{}');
INSERT INTO "tabWorkspaceItem" VALUES('runtime-lab-page-report',NULL,'2026-08-30 01:49:37','2026-08-30 01:49:37',NULL,0,6,'Runtime Laboratory','items','Workspace','CONTENT','shortcut','Report Page','Page','Runtime Lab - Report',NULL,NULL,4,0,NULL,NULL,'{}');
INSERT INTO "tabWorkspaceItem" VALUES('runtime-lab-page-workspace',NULL,'2026-08-30 01:49:37','2026-08-30 01:49:37',NULL,0,7,'Runtime Laboratory','items','Workspace','CONTENT','shortcut','Workspace Page','Page','Runtime Lab - Workspace',NULL,NULL,4,0,NULL,NULL,'{}');
INSERT INTO "tabWorkspaceItem" VALUES('runtime-lab-data-import',NULL,'2026-08-30 01:49:37','2026-08-30 01:49:37',NULL,0,8,'Runtime Laboratory','items','Workspace','CONTENT','shortcut','Data Import / Export Tool','Page','Data Import / Export Tool',NULL,NULL,4,0,NULL,NULL,'{}');
INSERT INTO "tabWorkspaceItem" VALUES('runtime-lab-workspace-builder',NULL,'2026-08-30 01:49:37','2026-08-30 01:49:37',NULL,0,9,'Runtime Laboratory','items','Workspace','CONTENT','shortcut','Workspace Builder','Page','Workspace Builder',NULL,NULL,4,0,NULL,NULL,'{}');
CREATE TABLE user_roles (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  role_id TEXT NOT NULL,
  scope_type TEXT,
  scope_value TEXT,
  assigned_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES "tabUser"(id) ON DELETE CASCADE,
  FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE
) STRICT;
CREATE TABLE wmn_app_artifacts (
  id TEXT PRIMARY KEY,
  app_name TEXT NOT NULL,
  run_id TEXT,
  artifact_type TEXT NOT NULL,
  source_path TEXT NOT NULL,
  source_hash TEXT,
  target_type TEXT,
  target_name TEXT,
  conversion_status TEXT NOT NULL CHECK (conversion_status IN ('CONVERTED','NEEDS_PORT','IGNORED','FAILED')),
  notes TEXT,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  FOREIGN KEY (app_name) REFERENCES wmn_app_packages(app_name) ON DELETE CASCADE,
  FOREIGN KEY (run_id) REFERENCES wmn_app_conversion_runs(id) ON DELETE CASCADE,
  UNIQUE(app_name, source_path, artifact_type)
) STRICT;
CREATE TABLE wmn_app_conversion_runs (
  id TEXT PRIMARY KEY,
  app_name TEXT NOT NULL,
  source_name TEXT,
  source_kind TEXT NOT NULL CHECK (source_kind IN ('ZIP','GITHUB','JSON','FOLDER')),
  source_ref TEXT,
  status TEXT NOT NULL CHECK (status IN ('RUNNING','COMPLETED','PARTIAL','FAILED')),
  total_artifacts INTEGER NOT NULL DEFAULT 0,
  converted_artifacts INTEGER NOT NULL DEFAULT 0,
  porting_artifacts INTEGER NOT NULL DEFAULT 0,
  failed_artifacts INTEGER NOT NULL DEFAULT 0,
  summary_json TEXT NOT NULL DEFAULT '{}',
  started_at TEXT NOT NULL,
  completed_at TEXT,
  FOREIGN KEY (app_name) REFERENCES wmn_app_packages(app_name) ON DELETE CASCADE
) STRICT;
CREATE TABLE wmn_app_dependencies (
  app_name TEXT NOT NULL,
  dependency_name TEXT NOT NULL,
  dependency_kind TEXT NOT NULL DEFAULT 'APP' CHECK (dependency_kind IN ('APP','DOCTYPE','PYTHON_PACKAGE','JAVASCRIPT_PACKAGE','EXTERNAL_SERVICE')),
  source_path TEXT,
  required INTEGER NOT NULL DEFAULT 1 CHECK (required IN (0,1)),
  resolved INTEGER NOT NULL DEFAULT 0 CHECK (resolved IN (0,1)),
  metadata_json TEXT NOT NULL DEFAULT '{}',
  updated_at TEXT NOT NULL,
  PRIMARY KEY (app_name, dependency_name, dependency_kind),
  FOREIGN KEY (app_name) REFERENCES wmn_app_packages(app_name) ON DELETE CASCADE
) STRICT;
CREATE TABLE wmn_app_packages (
  app_name TEXT PRIMARY KEY,
  app_title TEXT,
  app_version TEXT,
  source_framework TEXT NOT NULL DEFAULT 'WMN',
  source_repository TEXT,
  source_ref TEXT,
  source_license TEXT,
  module_json TEXT NOT NULL DEFAULT '{}',
  manifest_json TEXT NOT NULL DEFAULT '{}',
  conversion_status TEXT NOT NULL DEFAULT 'IMPORTED' CHECK (conversion_status IN ('IMPORTED','PARTIAL','READY','FAILED')),
  installed_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
) STRICT;
CREATE TABLE wmn_app_source_units (
  id TEXT PRIMARY KEY,
  app_name TEXT NOT NULL,
  artifact_id TEXT,
  source_path TEXT NOT NULL,
  language TEXT NOT NULL CHECK (language IN ('PYTHON','JAVASCRIPT','TYPESCRIPT','JSON','SQL','HTML','CSS','TEXT')),
  conversion_strategy TEXT NOT NULL DEFAULT 'PRESERVE',
  conversion_status TEXT NOT NULL DEFAULT 'NEEDS_PORT' CHECK (conversion_status IN ('AUTO_CONVERTED','REVIEW','NEEDS_PORT','IGNORED','FAILED')),
  confidence REAL NOT NULL DEFAULT 0 CHECK (confidence >= 0 AND confidence <= 1),
  review_status TEXT NOT NULL DEFAULT 'UNREVIEWED' CHECK (review_status IN ('UNREVIEWED','APPROVED','REJECTED','EDITED')),
  diagnostics_json TEXT NOT NULL DEFAULT '[]',
  dependencies_json TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL, source_storage_path TEXT, converted_storage_path TEXT,
  FOREIGN KEY (app_name) REFERENCES wmn_app_packages(app_name) ON DELETE CASCADE,
  FOREIGN KEY (artifact_id) REFERENCES wmn_app_artifacts(id) ON DELETE SET NULL,
  UNIQUE(app_name, source_path, language)
) STRICT;
CREATE TABLE wmn_assignments (
  id TEXT PRIMARY KEY,
  doctype TEXT NOT NULL,
  docname TEXT NOT NULL,
  allocated_to TEXT NOT NULL,
  description TEXT,
  priority TEXT NOT NULL DEFAULT 'Medium',
  status TEXT NOT NULL DEFAULT 'Open' CHECK (status IN ('Open','Closed','Cancelled')),
  due_date TEXT,
  assigned_by TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
) STRICT;
CREATE TABLE wmn_background_jobs (
  id TEXT PRIMARY KEY,
  method_name TEXT NOT NULL,
  args_json TEXT NOT NULL DEFAULT '{}',
  queue_name TEXT NOT NULL DEFAULT 'default',
  status TEXT NOT NULL DEFAULT 'QUEUED' CHECK (status IN ('QUEUED','RUNNING','SUCCESS','FAILED','CANCELLED')),
  run_after TEXT,
  attempts INTEGER NOT NULL DEFAULT 0,
  max_attempts INTEGER NOT NULL DEFAULT 3,
  result_json TEXT,
  error_text TEXT,
  created_at TEXT NOT NULL,
  started_at TEXT,
  finished_at TEXT,
  updated_at TEXT NOT NULL
) STRICT;
CREATE TABLE wmn_comments (
  id TEXT PRIMARY KEY,
  doctype TEXT NOT NULL,
  docname TEXT NOT NULL,
  comment_type TEXT NOT NULL DEFAULT 'Comment',
  content TEXT NOT NULL,
  owner TEXT,
  creation TEXT NOT NULL,
  modified TEXT NOT NULL
) STRICT;
CREATE TABLE wmn_dashboard_charts (
  name TEXT PRIMARY KEY,
  label TEXT NOT NULL,
  module TEXT NOT NULL DEFAULT 'Custom',
  app_name TEXT,
  chart_type TEXT,
  document_type TEXT,
  report_name TEXT,
  based_on TEXT,
  value_field TEXT,
  filters_json TEXT NOT NULL DEFAULT '[]',
  metadata_json TEXT NOT NULL DEFAULT '{}',
  updated_at TEXT NOT NULL,
  FOREIGN KEY (app_name) REFERENCES wmn_app_packages(app_name) ON DELETE SET NULL
) STRICT;
CREATE TABLE wmn_defaults (
  user_id TEXT NOT NULL,
  default_key TEXT NOT NULL,
  value_json TEXT,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(user_id, default_key)
) STRICT;
CREATE TABLE wmn_doc_shares (
  id TEXT PRIMARY KEY,
  doctype TEXT NOT NULL,
  docname TEXT NOT NULL,
  user_id TEXT NOT NULL,
  can_read INTEGER NOT NULL DEFAULT 1 CHECK (can_read IN (0,1)),
  can_write INTEGER NOT NULL DEFAULT 0 CHECK (can_write IN (0,1)),
  can_share INTEGER NOT NULL DEFAULT 0 CHECK (can_share IN (0,1)),
  can_submit INTEGER NOT NULL DEFAULT 0 CHECK (can_submit IN (0,1)),
  created_by TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(doctype, docname, user_id)
) STRICT;
CREATE TABLE wmn_doctype_fields (
  id TEXT PRIMARY KEY,
  doctype TEXT NOT NULL,
  fieldname TEXT NOT NULL,
  label TEXT NOT NULL,
  fieldtype TEXT NOT NULL DEFAULT 'Data',
  options TEXT,
  idx INTEGER NOT NULL DEFAULT 0,
  reqd INTEGER NOT NULL DEFAULT 0 CHECK (reqd IN (0,1)),
  read_only INTEGER NOT NULL DEFAULT 0 CHECK (read_only IN (0,1)),
  hidden INTEGER NOT NULL DEFAULT 0 CHECK (hidden IN (0,1)),
  in_list_view INTEGER NOT NULL DEFAULT 0 CHECK (in_list_view IN (0,1)),
  in_standard_filter INTEGER NOT NULL DEFAULT 0 CHECK (in_standard_filter IN (0,1)),
  searchable INTEGER NOT NULL DEFAULT 0 CHECK (searchable IN (0,1)),
  allow_on_submit INTEGER NOT NULL DEFAULT 0 CHECK (allow_on_submit IN (0,1)),
  default_json TEXT,
  depends_on TEXT,
  mandatory_depends_on TEXT,
  read_only_depends_on TEXT,
  fetch_from TEXT,
  precision INTEGER,
  length INTEGER,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(doctype, fieldname),
  FOREIGN KEY (doctype) REFERENCES wmn_doctypes(name) ON DELETE CASCADE
) STRICT;
INSERT INTO "wmn_doctype_fields" VALUES('page-field-name','Page','name','Page Name','Data',NULL,10,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,140,'{}','2026-08-28 18:21:19','2026-08-28 18:21:19');
INSERT INTO "wmn_doctype_fields" VALUES('page-field-title','Page','title','Title','Data',NULL,20,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,200,'{}','2026-08-28 18:21:19','2026-08-28 18:21:19');
INSERT INTO "wmn_doctype_fields" VALUES('page-field-route','Page','route','Route','Data',NULL,30,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,240,'{}','2026-08-28 18:21:19','2026-08-28 18:21:19');
INSERT INTO "wmn_doctype_fields" VALUES('page-field-app','Page','app_name','Application','Link','Application',40,0,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-28 18:21:19','2026-08-28 18:21:19');
INSERT INTO "wmn_doctype_fields" VALUES('page-field-module','Page','module','Module','Link','Module',50,1,0,0,1,1,1,0,'"WMN System"',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-28 18:21:19','2026-08-28 18:21:19');
INSERT INTO "wmn_doctype_fields" VALUES('page-field-type','Page','page_type','Page Type','Select','STANDARD
DASHBOARD
CUSTOM
LIST
FORM
REPORT
WORKSPACE',60,1,0,0,1,1,1,0,'"STANDARD"',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-28 18:21:19','2026-08-28 18:21:19');
INSERT INTO "wmn_doctype_fields" VALUES('page-field-controller','Page','controller_key','Controller Key','Data',NULL,70,0,0,0,0,0,1,0,NULL,NULL,NULL,NULL,NULL,NULL,240,'{}','2026-08-28 18:21:19','2026-08-28 18:21:19');
INSERT INTO "wmn_doctype_fields" VALUES('page-field-roles','Page','roles_json','Roles','JSON',NULL,80,0,0,0,0,0,0,0,'[]',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-28 18:21:19','2026-08-28 18:21:19');
INSERT INTO "wmn_doctype_fields" VALUES('page-field-permissions','Page','permissions_json','Permissions','JSON',NULL,90,0,0,0,0,0,0,0,'[]',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-28 18:21:19','2026-08-28 18:21:19');
INSERT INTO "wmn_doctype_fields" VALUES('page-field-enabled','Page','enabled','Enabled','Check',NULL,100,0,0,0,1,1,0,0,'true',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-28 18:21:19','2026-08-28 18:21:19');
INSERT INTO "wmn_doctype_fields" VALUES('page-field-metadata','Page','metadata_json','Page Metadata','JSON',NULL,110,0,0,0,0,0,0,0,'{}',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-28 18:21:19','2026-08-28 18:21:19');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-id','Workflow','id','ID','Data',NULL,10,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,140,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-name','Workflow','name','Workflow Name','Data',NULL,20,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,200,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-doctype','Workflow','doctype','Document Type','Data',NULL,30,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-state-field','Workflow','state_field','State Field','Data',NULL,40,1,0,0,1,0,1,0,'"workflow_state"',NULL,NULL,NULL,NULL,NULL,140,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-enabled','Workflow','enabled','Enabled','Check',NULL,50,0,0,0,1,1,0,0,'true',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-send-email','Workflow','send_email','Send Email','Check',NULL,60,0,0,0,0,0,0,0,'false',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-metadata','Workflow','metadata_json','Metadata','JSON',NULL,70,0,0,0,0,0,0,0,'{}',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-state-id','Workflow State','id','ID','Data',NULL,10,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,140,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-state-workflow','Workflow State','workflow_id','Workflow','Link','Workflow',20,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-state-name','Workflow State','state_name','State Name','Data',NULL,30,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,140,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-state-docstatus','Workflow State','doc_status','Document Status','Select','0\n1\n2',40,1,0,0,1,1,0,0,'0',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-state-edit-role','Workflow State','allow_edit_role','Allow Edit Role','Link','Role',50,0,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-state-index','Workflow State','idx','Index','Int',NULL,60,0,0,0,1,0,0,0,'0',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-state-metadata','Workflow State','metadata_json','Metadata','JSON',NULL,70,0,0,0,0,0,0,0,'{}',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-transition-id','Workflow Transition','id','ID','Data',NULL,10,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,140,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-transition-workflow','Workflow Transition','workflow_id','Workflow','Link','Workflow',20,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-transition-state','Workflow Transition','state_name','From State','Data',NULL,30,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,140,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-transition-action','Workflow Transition','action','Action','Data',NULL,40,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,140,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-transition-next','Workflow Transition','next_state','Next State','Data',NULL,50,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,140,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-transition-role','Workflow Transition','allowed_role','Allowed Role','Link','Role',60,0,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-transition-condition','Workflow Transition','condition_expression','Condition','Code',NULL,70,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{"safe_json_condition":true}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-transition-index','Workflow Transition','idx','Index','Int',NULL,80,0,0,0,1,0,0,0,'0',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-transition-metadata','Workflow Transition','metadata_json','Metadata','JSON',NULL,90,0,0,0,0,0,0,0,'{}',NULL,NULL,NULL,NULL,NULL,NULL,'{"condition_handler_key":"condition_handler"}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-action-id','Workflow Action','id','ID','Data',NULL,10,1,1,0,0,0,1,0,NULL,NULL,NULL,NULL,NULL,NULL,140,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-action-doctype','Workflow Action','doctype','Document Type','Data',NULL,20,1,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-action-docname','Workflow Action','docname','Document','Data',NULL,30,1,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-action-action','Workflow Action','action','Action','Data',NULL,40,1,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,140,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-action-from','Workflow Action','from_state','From State','Data',NULL,50,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,140,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-action-to','Workflow Action','to_state','To State','Data',NULL,60,1,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,140,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-action-user','Workflow Action','user_id','User','Data',NULL,70,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-action-status','Workflow Action','status','Status','Data',NULL,80,1,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,100,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-action-comment','Workflow Action','comment','Comment','Text',NULL,90,0,1,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('workflow-action-created','Workflow Action','created_at','Created At','Datetime',NULL,100,1,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctype_fields" VALUES('sys-report-report_name','Report','report_name','Report Name','Data',NULL,10,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T00:00:00.000Z','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('sys-report-report_type','Report','report_type','Report Type','Select','Report Builder
Query Report
Script Report
Custom Report',20,1,0,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{"description":"Choose Report Builder for no-SQL reports, Query Report for safe read-only SQL, or Script Report for registered native/managed logic."}','2026-08-29T00:00:00.000Z','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('sys-report-ref_doctype','Report','ref_doctype','Reference DocType','Link','DocType',30,0,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{"description":"DocType used as the report subject and permission boundary."}','2026-08-29T00:00:00.000Z','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('sys-report-module','Report','module','Module','Link','Module',40,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T00:00:00.000Z','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('sys-report-disabled','Report','disabled','Disabled','Check',NULL,50,0,0,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T00:00:00.000Z','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('sys-report-is_standard','Report','is_standard','System Report','Check',NULL,60,0,1,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T00:00:00.000Z','2026-08-29T00:00:00.000Z');
INSERT INTO "wmn_doctype_fields" VALUES('sys-report-query_source_type','Report','query_source_type','Query Source Type','Select','INLINE
STORAGE_FILE
STRUCTURED',70,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T00:00:00.000Z','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('sys-report-query_source_path','Report','query_source_path','Query Source Path','Data',NULL,80,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{"description":"Internal Storage path. The Report form edits Query SQL through the source editor instead.","external_source":true}','2026-08-29T00:00:00.000Z','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('sys-report-script_source_type','Report','script_source_type','Script Source Type','Select','NATIVE_HANDLER
STORAGE_FILE',90,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T00:00:00.000Z','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('sys-report-script_key','Report','script_key','Native Handler Key','Data',NULL,100,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{"description":"Registered native handler key for Script Reports using NATIVE_HANDLER."}','2026-08-29T00:00:00.000Z','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('sys-report-script_source_path','Report','script_source_path','Script Source Path','Data',NULL,110,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T00:00:00.000Z','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('sys-report-script_language','Report','script_language','Script Language','Data',NULL,120,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T00:00:00.000Z','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('sys-report-filters_json','Report','filters_json','Filters','JSON',NULL,130,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{"description": "Frappe-style runtime filters. Each filter may define fieldname, label, fieldtype, options, required/reqd, default and depends_on. Link, Dynamic Link, Date, Select, Check and numeric filters render natively."}','2026-08-29T00:00:00.000Z','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('sys-report-columns_json','Report','columns_json','Columns','JSON',NULL,140,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{"description":"Output column definitions using fieldname, label and fieldtype."}','2026-08-29T00:00:00.000Z','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('sys-report-query_definition_json','Report','query_definition_json','Structured Definition','JSON',NULL,150,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{"description":"Structured Report Builder definition or Query Report options such as max_rows. Query SQL is externalized to Storage."}','2026-08-29T00:00:00.000Z','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('sys-report-metadata_json','Report','metadata_json','Metadata','JSON',NULL,160,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T00:00:00.000Z','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('sys-report-created_at','Report','created_at','Created At','Datetime',NULL,170,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T00:00:00.000Z','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('sys-report-updated_at','Report','updated_at','Updated At','Datetime',NULL,180,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T00:00:00.000Z','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('doctype-field-name','DocType','name','DocType','Data',NULL,10,1,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-29 19:01:03','2026-08-29 19:01:03');
INSERT INTO "wmn_doctype_fields" VALUES('doctype-field-module','DocType','module','Module','Data',NULL,20,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-29 19:01:03','2026-08-29 19:01:03');
INSERT INTO "wmn_doctype_fields" VALUES('doctype-field-storage','DocType','storage_mode','Storage Mode','Data',NULL,30,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,80,'{}','2026-08-29 19:01:03','2026-08-29 19:01:03');
INSERT INTO "wmn_doctype_fields" VALUES('doctype-field-table','DocType','table_name','Table Name','Data',NULL,40,0,1,0,1,0,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-29 19:01:03','2026-08-29 19:01:03');
INSERT INTO "wmn_doctype_fields" VALUES('doctype-field-system','DocType','is_system','System DocType','Check',NULL,50,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29 19:01:03','2026-08-29 19:01:03');
INSERT INTO "wmn_doctype_fields" VALUES('doctype-field-child','DocType','is_child','Child DocType','Check',NULL,60,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29 19:01:03','2026-08-29 19:01:03');
INSERT INTO "wmn_doctype_fields" VALUES('doctype-field-enabled','DocType','enabled','Enabled','Check',NULL,70,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29 19:01:03','2026-08-29 19:01:03');
INSERT INTO "wmn_doctype_fields" VALUES('role-field-id','Role','id','ID','Data',NULL,10,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-29 19:01:03','2026-08-29 19:01:03');
INSERT INTO "wmn_doctype_fields" VALUES('role-field-code','Role','code','Code','Data',NULL,20,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,120,'{}','2026-08-29 19:01:03','2026-08-29 19:01:03');
INSERT INTO "wmn_doctype_fields" VALUES('role-field-name','Role','name','Role Name','Data',NULL,30,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-29 19:01:03','2026-08-29 19:01:03');
INSERT INTO "wmn_doctype_fields" VALUES('role-field-system','Role','is_system','System Role','Check',NULL,40,0,1,0,1,1,0,0,'false',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29 19:01:03','2026-08-29 19:01:03');
INSERT INTO "wmn_doctype_fields" VALUES('role-field-enabled','Role','enabled','Enabled','Check',NULL,50,0,0,0,1,1,0,0,'true',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29 19:01:03','2026-08-29 19:01:03');
INSERT INTO "wmn_doctype_fields" VALUES('role-field-created','Role','created_at','Created At','Datetime',NULL,60,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29 19:01:03','2026-08-29 19:01:03');
INSERT INTO "wmn_doctype_fields" VALUES('role-field-updated','Role','updated_at','Updated At','Datetime',NULL,70,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29 19:01:03','2026-08-29 19:01:03');
INSERT INTO "wmn_doctype_fields" VALUES('r31512-report-filter-fieldname','Report Filter','fieldname','Field Name','Data',NULL,10,1,0,0,1,0,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('r31512-report-filter-label','Report Filter','label','Label','Data',NULL,20,1,0,0,1,0,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('r31512-report-filter-label_ar','Report Filter','label_ar','Arabic Label','Data',NULL,30,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('r31512-report-filter-fieldtype','Report Filter','fieldtype','Field Type','Select','Data
Link
Dynamic Link
Date
Datetime
Select
Check
Int
Float
Currency
Percent',40,1,0,0,1,0,0,0,'"Data"',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('r31512-report-filter-options','Report Filter','options','Options','Small Text',NULL,50,0,0,0,1,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('r31512-report-filter-required','Report Filter','required','Required','Check',NULL,60,0,0,0,1,0,0,0,'false',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('r31512-report-filter-default','Report Filter','default','Default','Data',NULL,70,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('r31512-report-filter-depends_on','Report Filter','depends_on','Depends On','Data',NULL,80,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('r31512-report-filter-user_editable','Report Filter','user_editable','User Editable','Check',NULL,90,0,0,0,0,0,0,0,'true',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('r31512-report-filter-source_field','Report Filter','source_field','Source Field','Data',NULL,100,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('r31512-report-filter-operator','Report Filter','operator','Operator','Select','EQ
NE
GT
GTE
LT
LTE
CONTAINS
STARTS_WITH
IS_EMPTY
IS_NOT_EMPTY',110,0,0,0,0,0,0,0,'"EQ"',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('r31512-report-column-fieldname','Report Column','fieldname','Field Name','Data',NULL,10,1,0,0,1,0,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('r31512-report-column-label','Report Column','label','Label','Data',NULL,20,1,0,0,1,0,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('r31512-report-column-label_ar','Report Column','label_ar','Arabic Label','Data',NULL,30,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('r31512-report-column-fieldtype','Report Column','fieldtype','Field Type','Select','Data
Link
Dynamic Link
Date
Datetime
Select
Check
Int
Float
Currency
Percent',40,1,0,0,1,0,0,0,'"Data"',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('r31512-report-column-options','Report Column','options','Options','Small Text',NULL,50,0,0,0,1,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('r31512-report-column-width','Report Column','width','Width','Float',NULL,60,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('r31512-report-column-precision','Report Column','precision','Precision','Int',NULL,70,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('r31512-report-column-alignment','Report Column','alignment','Alignment','Select','Left
Center
Right',80,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('r31512-report-column-aggregate','Report Column','aggregate','Aggregate','Select','NONE
COUNT
SUM
AVG
MIN
MAX',90,0,0,0,0,0,0,0,'"NONE"',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('r31512-report-column-hidden','Report Column','hidden','Hidden','Check',NULL,100,0,0,0,0,0,0,0,'false',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('r31512-report-filters','Report','filters','Filters','Table','Report Filter',130,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{"description":"Frappe-style filter rows. Add/edit/reorder filters as child records; JSON editing is no longer required."}','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('r31512-report-columns','Report','columns','Columns','Table','Report Column',140,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{"description":"Output column rows. Add/edit/reorder columns as child records."}','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctype_fields" VALUES('pf-id','Print Format','id','ID','Data',NULL,10,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pf-code','Print Format','code','Code','Data',NULL,20,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,120,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pf-name','Print Format','name','Print Format Name','Data',NULL,30,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pf-target','Print Format','target_type','Target Type','Select','DOCUMENT\nREPORT\nGENERAL_REPORT\nPLATFORM',40,1,0,0,1,1,1,0,'"DOCUMENT"',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pf-doctype','Print Format','document_type','DocType','Link','DocType',50,0,0,0,1,1,1,0,NULL,'eval:doc.target_type==''DOCUMENT''',NULL,NULL,NULL,NULL,180,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pf-report','Print Format','report_name','Report','Link','Report',60,0,0,0,1,1,1,0,NULL,'eval:doc.target_type==''REPORT''',NULL,NULL,NULL,NULL,180,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pf-renderer','Print Format','renderer_id','Renderer','Select','pdf\nhtml\nescpos',70,1,0,0,1,1,1,0,'"pdf"',NULL,NULL,NULL,NULL,NULL,NULL,'{"registry_backed":true}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pf-template','Print Format','template_text','Template','Code',NULL,80,1,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{"language":"WMN Print Template","token_help":true}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pf-css','Print Format','css_text','CSS','Code',NULL,90,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{"optional":true,"renderer":"html"}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pf-default','Print Format','is_default','Default','Check',NULL,100,0,0,0,1,1,0,0,'false',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pf-paper-width','Print Format','paper_width_mm','Paper Width (mm)','Float',NULL,110,1,0,0,0,0,0,0,'210',NULL,NULL,NULL,NULL,2,NULL,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pf-paper-height','Print Format','paper_height_mm','Paper Height (mm)','Float',NULL,120,1,0,0,0,0,0,0,'297',NULL,NULL,NULL,NULL,2,NULL,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pf-margin','Print Format','margin_mm','Margin (mm)','Float',NULL,130,1,0,0,0,0,0,0,'10',NULL,NULL,NULL,NULL,2,NULL,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pf-enabled','Print Format','enabled','Enabled','Check',NULL,140,0,0,0,1,1,0,0,'true',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pf-metadata','Print Format','metadata_json','Metadata JSON','Code',NULL,150,0,0,1,0,0,0,0,'"{}"',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('ps-id','Print Settings','id','ID','Data',NULL,10,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('ps-name','Print Settings','name','Settings Name','Data',NULL,20,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('ps-default-format','Print Settings','default_document_format_id','Default Document Format','Link','Print Format',30,0,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('ps-general-report','Print Settings','general_report_format_id','General Report Format','Link','Print Format',40,0,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('ps-printer','Print Settings','default_printer_id','Default Printer','Link','Printer',50,0,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('ps-preview','Print Settings','preview_renderer_id','Preview Renderer','Select','html\npdf',60,1,0,0,0,1,0,0,'"html"',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('ps-pdf','Print Settings','pdf_renderer_id','PDF Renderer','Select','pdf',70,1,0,0,0,1,0,0,'"pdf"',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('ps-paper','Print Settings','paper_width_mm','ESC/POS Paper Width (mm)','Int',NULL,80,1,0,0,0,0,0,0,'80',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('ps-autoprint','Print Settings','auto_print','Auto Print','Check',NULL,90,0,0,0,0,0,0,0,'false',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('ps-cut','Print Settings','cut_paper','Cut Paper','Check',NULL,100,0,0,0,0,0,0,0,'false',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('ps-enabled','Print Settings','enabled','Enabled','Check',NULL,110,0,0,0,1,1,0,0,'true',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('ps-metadata','Print Settings','metadata_json','Metadata JSON','Code',NULL,120,0,0,1,0,0,0,0,'"{}"',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pr-id','Printer','id','ID','Data',NULL,10,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pr-name','Printer','name','Printer Name','Data',NULL,20,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pr-connection','Printer','connection_type','Adapter','Select','SYSTEM\nWINDOWS_RAW\nNETWORK\nSERIAL\nUSB\nBLUETOOTH\nWEB',30,1,0,0,1,1,1,0,'"SYSTEM"',NULL,NULL,NULL,NULL,NULL,NULL,'{"native_adapter":true}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pr-target','Printer','target','Target','Data',NULL,40,0,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,260,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pr-platform','Printer','platform','Platform','Select','ANY\nWINDOWS\nANDROID\nIOS\nWEB\nSERVER',50,1,0,0,1,1,1,0,'"ANY"',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pr-capabilities','Printer','capabilities_json','Capabilities JSON','Code',NULL,60,0,0,1,0,0,0,0,'"[]"',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pr-enabled','Printer','enabled','Enabled','Check',NULL,70,0,0,0,1,1,0,0,'true',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pr-metadata','Printer','metadata_json','Adapter Metadata JSON','Code',NULL,80,0,0,0,0,0,0,0,'"{}"',NULL,NULL,NULL,NULL,NULL,NULL,'{"adapter_config":true}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pj-id','Print Job','id','Job ID','Data',NULL,10,0,1,0,1,0,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pj-source','Print Job','source_type','Source','Data',NULL,20,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,40,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pj-doctype','Print Job','document_type','DocType / Report','Data',NULL,30,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pj-docname','Print Job','document_name','Document / Execution','Data',NULL,40,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pj-format','Print Job','print_format_id','Print Format','Link','Print Format',50,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pj-printer','Print Job','printer_id','Printer','Link','Printer',60,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pj-renderer','Print Job','renderer_id','Renderer','Data',NULL,70,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,80,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pj-status','Print Job','status','Status','Data',NULL,80,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,40,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pj-output','Print Job','output_file_id','Output File','Link','File',90,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pj-mime','Print Job','mime_type','MIME Type','Data',NULL,100,0,1,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,120,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pj-bytes','Print Job','byte_count','Bytes','Int',NULL,110,0,1,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pj-error','Print Job','error_message','Error','Small Text',NULL,120,0,1,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pj-created','Print Job','created_at','Created At','Datetime',NULL,130,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('pj-completed','Print Job','completed_at','Completed At','Datetime',NULL,140,0,1,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctype_fields" VALUES('file-id','File','id','File ID','Data',NULL,10,0,1,0,1,0,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('file-name','File','file_name','File Name','Data',NULL,20,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,260,'{}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('file-mime','File','mime_type','MIME Type','Data',NULL,30,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,160,'{}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('file-size','File','file_size','Size (Bytes)','Int',NULL,40,0,1,0,1,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('file-private','File','is_private','Private','Check',NULL,50,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('file-state','File','state','State','Select','AVAILABLE\nMISSING\nCORRUPT',60,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{"runtime_managed":true}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('file-doctype','File','attached_to_doctype','Attached To DocType','Link','DocType',70,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('file-docname','File','attached_to_name','Attached To Name','Data',NULL,80,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('file-field','File','attached_to_field','Attached To Field','Data',NULL,90,0,1,0,0,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('file-source-adapter','File','source_adapter','Source Adapter','Data',NULL,100,0,1,0,0,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,120,'{}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('file-content-mode','File','content_mode','Content Mode','Select','MANAGED_STORAGE\nEXTERNAL_REFERENCE',110,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{"runtime_managed":true}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('file-source-reference','File','source_reference','External Reference','Data',NULL,120,0,1,0,0,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,500,'{"external_reference":true}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('file-storage-adapter','File','storage_adapter','Storage Adapter','Data',NULL,130,0,1,0,0,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,120,'{}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('file-storage-path','File','storage_path','Storage Key','Data',NULL,140,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,320,'{}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('file-url','File','file_url','File URL','Data',NULL,150,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,320,'{}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('file-hash','File','content_hash','SHA-256','Data',NULL,160,0,1,1,0,0,1,0,NULL,NULL,NULL,NULL,NULL,NULL,64,'{}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('file-owner','File','owner','Owner','Data',NULL,170,0,1,0,0,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('file-created','File','creation','Created At','Datetime',NULL,180,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('file-modified','File','modified','Modified At','Datetime',NULL,190,0,1,0,0,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('file-metadata','File','metadata_json','Metadata JSON','Code',NULL,200,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('fs-id','File Settings','id','ID','Data',NULL,10,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,80,'{}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('fs-name','File Settings','name','Settings Name','Data',NULL,20,1,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,120,'{}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('fs-mode','File Settings','default_content_mode','Default Content Mode','Select','MANAGED_STORAGE\nEXTERNAL_REFERENCE',30,1,0,0,1,1,1,0,'"MANAGED_STORAGE"',NULL,NULL,NULL,NULL,NULL,NULL,'{"storage_optional":true}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('fs-external','File Settings','allow_external_reference','Allow External Reference','Check',NULL,40,0,0,0,1,1,0,0,'true',NULL,NULL,NULL,NULL,NULL,NULL,'{"platform_gated":true}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('fs-metadata','File Settings','metadata_json','Metadata JSON','Code',NULL,50,0,0,1,0,0,0,0,'"{}"',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('fs-created','File Settings','created_at','Created At','Datetime',NULL,60,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('fs-updated','File Settings','updated_at','Updated At','Datetime',NULL,70,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctype_fields" VALUES('workspace-name','Workspace','name','Workspace Name','Data',NULL,10,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('workspace-label','Workspace','label','Label','Data',NULL,20,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,220,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('workspace-module','Workspace','module','Module','Link','Module',30,1,0,0,1,1,1,0,'"Custom"',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('workspace-app','Workspace','app_name','Application','Link','Application',40,0,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('workspace-icon','Workspace','icon','Icon','Data',NULL,50,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,120,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('workspace-parent-page','Workspace','parent_page','Parent Page','Link','Workspace',60,0,0,0,0,0,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('workspace-sequence','Workspace','sequence_id','Sequence','Float',NULL,70,0,0,0,1,0,0,0,'0',NULL,NULL,NULL,NULL,2,NULL,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('workspace-public','Workspace','is_public','Public','Check',NULL,80,0,0,0,1,1,0,0,'true',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('workspace-hidden','Workspace','is_hidden','Hidden','Check',NULL,90,0,0,0,1,1,0,0,'false',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('workspace-items','Workspace','items','Items','Table','Workspace Item',100,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{"workspace_builder":true,"description":"Workspace layout rows. No JSON/code editing is required."}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('workspace-item-region','Workspace Item','region','Region','Select','CONTENT\nLINKS\nSHORTCUTS\nSIDEBAR\nCHARTS\nNUMBER_CARDS\nQUICK_LISTS',10,1,0,0,1,1,1,0,'"CONTENT"',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('workspace-item-type','Workspace Item','item_type','Item Type','Select','shortcut\nheader\nspacer\ncard\nnumber_card\nchart\nquick_list\nlink',20,1,0,0,1,1,1,0,'"shortcut"',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('workspace-item-label','Workspace Item','label','Label','Data',NULL,30,0,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,220,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('workspace-item-link-type','Workspace Item','link_type','Link Type','Select','DocType\nPage\nReport\nWorkspace\nQuery Report',40,0,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('workspace-item-link-to','Workspace Item','link_to','Target','Data',NULL,50,0,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,240,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('workspace-item-icon','Workspace Item','icon','Icon','Data',NULL,60,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,120,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('workspace-item-parent-label','Workspace Item','parent_label','Parent Label','Data',NULL,70,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('workspace-item-span','Workspace Item','column_span','Column Span','Int',NULL,80,0,0,0,0,0,0,0,'4',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('workspace-item-feature','Workspace Item','required_feature','Required Feature','Data',NULL,90,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('workspace-item-description','Workspace Item','description','Description','Small Text',NULL,100,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('workspace-item-hidden','Workspace Item','hidden','Hidden','Check',NULL,110,0,0,0,0,0,0,0,'false',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('data-import-job-id','Data Import Job','id','Job ID','Data',NULL,10,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('data-import-job-doctype','Data Import Job','doctype','DocType','Data',NULL,20,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{"render_as":"LINK","link_target":"DocType"}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('data-import-job-mode','Data Import Job','import_mode','Import Mode','Select','INSERT\nUPDATE\nUPSERT',30,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('data-import-job-file','Data Import Job','file_name','File','Data',NULL,40,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,240,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('data-import-job-status','Data Import Job','status','Status','Select','DRAFT\nVALIDATED\nCOMPLETED\nPARTIAL\nFAILED',50,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('data-import-job-total','Data Import Job','total_rows','Total Rows','Int',NULL,60,0,1,0,1,0,0,0,'0',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('data-import-job-success','Data Import Job','success_rows','Success Rows','Int',NULL,70,0,1,0,1,0,0,0,'0',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('data-import-job-failed','Data Import Job','failed_rows','Failed Rows','Int',NULL,80,0,1,0,1,0,0,0,'0',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('data-import-job-created','Data Import Job','created_at','Created At','Datetime',NULL,90,0,1,0,1,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('data-import-job-completed','Data Import Job','completed_at','Completed At','Datetime',NULL,100,0,1,0,1,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('data-export-job-id','Data Export Job','id','Job ID','Data',NULL,10,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('data-export-job-doctype','Data Export Job','doctype','DocType','Data',NULL,20,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{"render_as":"LINK","link_target":"DocType"}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('data-export-job-format','Data Export Job','format','Format','Select','CSV\nJSON',30,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('data-export-job-row-count','Data Export Job','row_count','Rows','Int',NULL,40,0,1,0,1,0,0,0,'0',NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctype_fields" VALUES('data-export-job-created','Data Export Job','created_at','Created At','Datetime',NULL,50,0,1,0,1,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}','2026-08-30 01:49:37','2026-08-30 01:49:37');
CREATE TABLE wmn_doctype_permissions (
  id TEXT PRIMARY KEY,
  doctype TEXT NOT NULL,
  role TEXT NOT NULL,
  permlevel INTEGER NOT NULL DEFAULT 0,
  can_read INTEGER NOT NULL DEFAULT 0 CHECK (can_read IN (0,1)),
  can_write INTEGER NOT NULL DEFAULT 0 CHECK (can_write IN (0,1)),
  can_create INTEGER NOT NULL DEFAULT 0 CHECK (can_create IN (0,1)),
  can_delete INTEGER NOT NULL DEFAULT 0 CHECK (can_delete IN (0,1)),
  can_submit INTEGER NOT NULL DEFAULT 0 CHECK (can_submit IN (0,1)),
  can_cancel INTEGER NOT NULL DEFAULT 0 CHECK (can_cancel IN (0,1)),
  can_amend INTEGER NOT NULL DEFAULT 0 CHECK (can_amend IN (0,1)),
  can_report INTEGER NOT NULL DEFAULT 0 CHECK (can_report IN (0,1)),
  can_import INTEGER NOT NULL DEFAULT 0 CHECK (can_import IN (0,1)),
  can_export INTEGER NOT NULL DEFAULT 0 CHECK (can_export IN (0,1)),
  can_share INTEGER NOT NULL DEFAULT 0 CHECK (can_share IN (0,1)),
  can_print INTEGER NOT NULL DEFAULT 0 CHECK (can_print IN (0,1)),
  can_email INTEGER NOT NULL DEFAULT 0 CHECK (can_email IN (0,1)),
  if_owner INTEGER NOT NULL DEFAULT 0 CHECK (if_owner IN (0,1)),
  metadata_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (doctype) REFERENCES wmn_doctypes(name) ON DELETE CASCADE,
  UNIQUE(doctype, role, permlevel)
) STRICT;
INSERT INTO "wmn_doctype_permissions" VALUES('docperm-page-system-manager','Page','System Manager',0,1,1,1,1,0,0,0,1,1,1,0,0,0,0,'{"platform_default":true,"runtime":"WMN_PAGE_RUNTIME"}');
INSERT INTO "wmn_doctype_permissions" VALUES('docperm-workflow-system-manager','Workflow','System Manager',0,1,1,1,1,0,0,0,1,1,1,0,0,0,0,'{"platform_default":true}');
INSERT INTO "wmn_doctype_permissions" VALUES('docperm-workflow-state-system-manager','Workflow State','System Manager',0,1,1,1,1,0,0,0,1,1,1,0,0,0,0,'{"platform_default":true}');
INSERT INTO "wmn_doctype_permissions" VALUES('docperm-workflow-transition-system-manager','Workflow Transition','System Manager',0,1,1,1,1,0,0,0,1,1,1,0,0,0,0,'{"platform_default":true}');
INSERT INTO "wmn_doctype_permissions" VALUES('docperm-workflow-action-system-manager','Workflow Action','System Manager',0,1,0,0,0,0,0,0,1,0,1,0,0,0,0,'{"platform_default":true,"read_only":true}');
INSERT INTO "wmn_doctype_permissions" VALUES('docperm-doctype-system-manager','DocType','System Manager',0,1,0,0,0,0,0,0,1,0,1,0,0,0,0,'{"platform_default":true,"metadata_registry":true}');
INSERT INTO "wmn_doctype_permissions" VALUES('docperm-print-format-system-manager','Print Format','System Manager',0,1,1,1,1,0,0,0,1,0,1,0,0,0,0,'{"platform_default":true,"printing_engine":true}');
INSERT INTO "wmn_doctype_permissions" VALUES('docperm-print-settings-system-manager','Print Settings','System Manager',0,1,1,1,1,0,0,0,1,0,1,0,0,0,0,'{"platform_default":true,"printing_engine":true}');
INSERT INTO "wmn_doctype_permissions" VALUES('docperm-printer-system-manager','Printer','System Manager',0,1,1,1,1,0,0,0,1,0,1,0,0,0,0,'{"platform_default":true,"printing_engine":true}');
INSERT INTO "wmn_doctype_permissions" VALUES('docperm-print-job-system-manager','Print Job','System Manager',0,1,0,0,0,0,0,0,1,0,1,0,0,0,0,'{"platform_default":true,"printing_engine":true}');
INSERT INTO "wmn_doctype_permissions" VALUES('docperm-file-settings-system-manager','File Settings','System Manager',0,1,1,0,0,0,0,0,1,0,1,0,0,0,0,'{"platform_default":true,"files_attachments":true}');
CREATE TABLE wmn_doctypes (
  name TEXT PRIMARY KEY,
  module TEXT NOT NULL DEFAULT 'Custom',
  storage_mode TEXT NOT NULL DEFAULT 'DYNAMIC' CHECK (storage_mode IN ('TABLE','DYNAMIC')),
  table_name TEXT,
  id_field TEXT NOT NULL DEFAULT 'id',
  title_field TEXT,
  autoname TEXT,
  is_single INTEGER NOT NULL DEFAULT 0 CHECK (is_single IN (0,1)),
  is_child INTEGER NOT NULL DEFAULT 0 CHECK (is_child IN (0,1)),
  is_submittable INTEGER NOT NULL DEFAULT 0 CHECK (is_submittable IN (0,1)),
  track_changes INTEGER NOT NULL DEFAULT 1 CHECK (track_changes IN (0,1)),
  allow_create INTEGER NOT NULL DEFAULT 1 CHECK (allow_create IN (0,1)),
  allow_edit INTEGER NOT NULL DEFAULT 1 CHECK (allow_edit IN (0,1)),
  allow_delete INTEGER NOT NULL DEFAULT 1 CHECK (allow_delete IN (0,1)),
  allow_import INTEGER NOT NULL DEFAULT 1 CHECK (allow_import IN (0,1)),
  allow_export INTEGER NOT NULL DEFAULT 1 CHECK (allow_export IN (0,1)),
  generic_write INTEGER NOT NULL DEFAULT 1 CHECK (generic_write IN (0,1)),
  is_system INTEGER NOT NULL DEFAULT 0 CHECK (is_system IN (0,1)),
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
) STRICT;
INSERT INTO "wmn_doctypes" VALUES('User','Security','TABLE','tabUser','id','display_name',NULL,0,0,0,1,1,1,0,0,1,1,1,1,'{"security_owned":true}','2026-08-28 00:11:21','2026-08-28T17:45:00Z');
INSERT INTO "wmn_doctypes" VALUES('Role','Security','TABLE','roles','id','name',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{"security_owned":true}','2026-08-28 17:26:44','2026-08-28T17:45:00Z');
INSERT INTO "wmn_doctypes" VALUES('Permission','Security','TABLE','permissions','id','code',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{"security_owned":true}','2026-08-28 17:26:44','2026-08-28T17:45:00Z');
INSERT INTO "wmn_doctypes" VALUES('User Role','Security','TABLE','user_roles','id','user_id',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{"security_owned":true}','2026-08-28 17:26:44','2026-08-28T17:45:00Z');
INSERT INTO "wmn_doctypes" VALUES('Application','WMN System','TABLE','wmn_app_packages','app_name','app_name',NULL,0,0,0,1,0,0,0,0,1,0,1,1,'{"runtime_owned":true}','2026-08-28 17:26:44','2026-08-28 17:26:44');
INSERT INTO "wmn_doctypes" VALUES('Module','WMN System','TABLE','wmn_modules','name','label',NULL,0,0,0,1,0,1,0,0,1,0,1,1,'{"runtime_owned":true}','2026-08-28 17:26:44','2026-08-28 17:26:44');
INSERT INTO "wmn_doctypes" VALUES('Page','WMN System','TABLE','tabPage','name','title',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{"page_types":["STANDARD","DASHBOARD","CUSTOM","LIST","FORM","REPORT","WORKSPACE"],"runtime":"WMN_PAGE_RUNTIME","metadata_layout":true}','2026-08-28 17:26:44','2026-08-28 18:21:19');
INSERT INTO "wmn_doctypes" VALUES('Workspace','WMN System','TABLE','tabWorkspace','name','label',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{"runtime":"WORKSPACE_BUILDER","layout":"PARENT_CHILD_TABLES","legacy_content_json":"import_compat_only"}','2026-08-28 17:26:44','2026-08-30 01:49:37');
INSERT INTO "wmn_doctypes" VALUES('Report','WMN System','TABLE','tabReport','name','report_name',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{"report_types":["Report Builder","Query Report","Script Report","Custom Report"],"single_source_of_truth":true,"external_source_storage":true}','2026-08-28 17:26:44','2026-08-29T00:00:00.000Z');
INSERT INTO "wmn_doctypes" VALUES('Print Format','WMN System','TABLE','print_formats','id','name',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{"printing_engine":true,"template_tokens":true,"renderer_registry":true}','2026-08-28 17:26:44','2026-08-29 23:29:37');
INSERT INTO "wmn_doctypes" VALUES('Print Settings','WMN System','TABLE','print_settings','id','name',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{"printing_engine":true,"runtime_defaults":true}','2026-08-28 17:26:44','2026-08-29 23:29:37');
INSERT INTO "wmn_doctypes" VALUES('Printer','WMN System','TABLE','wmn_printers','id','name',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{"printing_engine":true,"native_adapter_target":true}','2026-08-28 17:26:44','2026-08-29 23:29:37');
INSERT INTO "wmn_doctypes" VALUES('Notification','WMN System','TABLE','wmn_notifications','id','title',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{}','2026-08-28 17:26:44','2026-08-28 17:26:44');
INSERT INTO "wmn_doctypes" VALUES('Scheduled Job','WMN System','TABLE','wmn_schedules','id','name',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{}','2026-08-28 17:26:44','2026-08-28 17:26:44');
INSERT INTO "wmn_doctypes" VALUES('File','WMN System','TABLE','wmn_files','id','file_name',NULL,0,0,0,1,0,0,0,1,1,0,1,1,'{"runtime_owned":true,"attachment_runtime":true,"storage_optional":true,"external_reference":true,"storage_adapter":true,"file_dialog_adapter":true,"integrity_state":true}','2026-08-28 17:26:44','2026-08-30 00:26:30');
INSERT INTO "wmn_doctypes" VALUES('System Setting','WMN System','TABLE','wmn_scoped_settings','setting_key','setting_key',NULL,0,0,0,1,0,0,0,0,1,0,1,1,'{"runtime_owned":true}','2026-08-28 17:26:44','2026-08-28 17:26:44');
INSERT INTO "wmn_doctypes" VALUES('System Log','WMN System','TABLE','wmn_system_logs','id','message',NULL,0,0,0,0,0,0,0,0,1,0,1,1,'{"read_only":true}','2026-08-28 17:26:44','2026-08-28 17:26:44');
INSERT INTO "wmn_doctypes" VALUES('Audit Log','WMN System','TABLE','audit_log','id','action',NULL,0,0,0,0,0,0,0,0,1,0,1,1,'{"read_only":true}','2026-08-28 17:26:44','2026-08-28 17:26:44');
INSERT INTO "wmn_doctypes" VALUES('Background Job','WMN System','TABLE','wmn_background_jobs','id','handler_name',NULL,0,0,0,0,0,0,0,0,1,0,1,1,'{"runtime_owned":true}','2026-08-28 17:26:44','2026-08-28 17:26:44');
INSERT INTO "wmn_doctypes" VALUES('Feature','WMN System','TABLE','wmn_features','id','label',NULL,0,0,0,1,0,1,0,0,1,0,1,1,'{"commercial":true}','2026-08-28 17:26:44','2026-08-28 17:26:44');
INSERT INTO "wmn_doctypes" VALUES('Feature Entitlement','WMN System','TABLE','wmn_feature_entitlements','id','feature_id',NULL,0,0,0,1,0,1,0,0,1,0,1,1,'{"commercial":true}','2026-08-28 17:26:44','2026-08-28 17:26:44');
INSERT INTO "wmn_doctypes" VALUES('Feature Activation','WMN System','TABLE','wmn_feature_activations','feature_id','feature_id',NULL,0,0,0,1,0,1,0,0,1,0,1,1,'{"local_activation":true}','2026-08-28 17:26:44','2026-08-28 17:26:44');
INSERT INTO "wmn_doctypes" VALUES('Role Permission','Security','TABLE','role_permissions','id','permission_id',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{"security_owned":true}','2026-08-28T17:45:00Z','2026-08-28T17:45:00Z');
INSERT INTO "wmn_doctypes" VALUES('DocType Permission','Security','TABLE','wmn_doctype_permissions','id','doctype',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{"security_owned":true}','2026-08-28T17:45:00Z','2026-08-28T17:45:00Z');
INSERT INTO "wmn_doctypes" VALUES('User Permission','Security','TABLE','wmn_user_permissions','id','for_value',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{"security_owned":true}','2026-08-28T17:45:00Z','2026-08-28T17:45:00Z');
INSERT INTO "wmn_doctypes" VALUES('Document Share','Security','TABLE','wmn_doc_shares','id','docname',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{"security_owned":true}','2026-08-28T17:45:00Z','2026-08-28T17:45:00Z');
INSERT INTO "wmn_doctypes" VALUES('Workflow','Workflow','TABLE','wmn_workflows','id','name','field:name',0,0,0,1,1,1,1,1,1,1,1,1,'{"runtime":"WMN_WORKFLOW_RUNTIME","required_feature":"workflow.approvals"}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctypes" VALUES('Workflow State','Workflow','TABLE','wmn_workflow_states','id','state_name','format:WFS-.#####',0,0,0,1,1,1,1,1,1,1,1,1,'{"runtime":"WMN_WORKFLOW_RUNTIME","required_feature":"workflow.approvals"}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctypes" VALUES('Workflow Transition','Workflow','TABLE','wmn_workflow_transitions','id','action','format:WFT-.#####',0,0,0,1,1,1,1,1,1,1,1,1,'{"runtime":"WMN_WORKFLOW_RUNTIME","required_feature":"workflow.approvals"}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctypes" VALUES('Workflow Action','Workflow','TABLE','wmn_workflow_actions','id','action',NULL,0,0,0,0,0,0,0,0,1,0,1,1,'{"runtime":"WMN_WORKFLOW_RUNTIME","required_feature":"workflow.approvals","read_only":true}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_doctypes" VALUES('DocType','WMN System','TABLE','wmn_doctypes','name','name',NULL,0,0,0,1,0,0,0,0,1,0,1,1,'{"runtime_owned":true,"metadata_registry":true,"link_target":true}','2026-08-29 19:01:03','2026-08-29 19:01:03');
INSERT INTO "wmn_doctypes" VALUES('Report Filter','WMN System','TABLE','tabReport Filter','name','label',NULL,0,1,0,0,1,1,1,0,1,1,1,1,'{"runtime_owned":true,"report_child_table":true}','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctypes" VALUES('Report Column','WMN System','TABLE','tabReport Column','name','label',NULL,0,1,0,0,1,1,1,0,1,1,1,1,'{"runtime_owned":true,"report_child_table":true}','2026-08-29T20:54:55.861133+00:00','2026-08-29T20:54:55.861133+00:00');
INSERT INTO "wmn_doctypes" VALUES('Print Job','WMN System','TABLE','print_jobs','id','document_name',NULL,0,0,0,0,0,0,0,0,1,0,1,1,'{"runtime_owned":true,"read_only":true,"printing_engine":true}','2026-08-29 23:29:37','2026-08-29 23:29:37');
INSERT INTO "wmn_doctypes" VALUES('File Settings','WMN System','TABLE','file_settings','id','name',NULL,0,0,0,1,0,1,0,0,1,1,1,1,'{"file_runtime":true,"storage_optional":true,"single_managed_record":true}','2026-08-30 00:26:30','2026-08-30 00:26:30');
INSERT INTO "wmn_doctypes" VALUES('Workspace Item','WMN System','TABLE','tabWorkspaceItem','name','label',NULL,0,1,0,1,1,1,1,0,1,1,1,1,'{"runtime":"WORKSPACE_BUILDER","child_of":"Workspace","table_editor":true}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctypes" VALUES('Data Import Job','WMN System','TABLE','data_import_jobs','id','file_name',NULL,0,0,0,0,0,0,0,0,1,0,1,1,'{"runtime_owned":true,"tool":"DATA_IMPORT","read_only":true}','2026-08-30 01:49:37','2026-08-30 01:49:37');
INSERT INTO "wmn_doctypes" VALUES('Data Export Job','WMN System','TABLE','data_export_jobs','id','doctype',NULL,0,0,0,0,0,0,0,0,1,0,1,1,'{"runtime_owned":true,"tool":"DATA_EXPORT","read_only":true}','2026-08-30 01:49:37','2026-08-30 01:49:37');
CREATE TABLE wmn_document_versions (
  id TEXT PRIMARY KEY,
  doctype TEXT NOT NULL,
  docname TEXT NOT NULL,
  version_no INTEGER NOT NULL,
  data_json TEXT NOT NULL,
  changed_by TEXT,
  created_at TEXT NOT NULL,
  UNIQUE(doctype, docname, version_no)
) STRICT;
CREATE TABLE wmn_feature_activations (
  feature_id TEXT NOT NULL,
  scope_type TEXT NOT NULL DEFAULT 'INSTALLATION' CHECK (scope_type IN ('INSTALLATION','USER')),
  scope_key TEXT NOT NULL DEFAULT 'local',
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
  updated_at TEXT NOT NULL,
  PRIMARY KEY(feature_id,scope_type,scope_key),
  FOREIGN KEY (feature_id) REFERENCES wmn_features(id) ON DELETE CASCADE
) STRICT;
INSERT INTO "wmn_feature_activations" VALUES('feature-core-platform','INSTALLATION','local',1,'2026-08-28 17:26:44');
INSERT INTO "wmn_feature_activations" VALUES('feature-dashboard-charts','INSTALLATION','local',1,'2026-08-28 17:26:44');
INSERT INTO "wmn_feature_activations" VALUES('feature-developer-tools','INSTALLATION','local',1,'2026-08-28 17:26:44');
INSERT INTO "wmn_feature_activations" VALUES('feature-diagnostics','INSTALLATION','local',1,'2026-08-28 17:26:44');
INSERT INTO "wmn_feature_activations" VALUES('feature-notifications','INSTALLATION','local',1,'2026-08-28 17:26:44');
INSERT INTO "wmn_feature_activations" VALUES('feature-printing','INSTALLATION','local',1,'2026-08-28 17:26:44');
INSERT INTO "wmn_feature_activations" VALUES('feature-query-reports','INSTALLATION','local',1,'2026-08-28 17:26:44');
INSERT INTO "wmn_feature_activations" VALUES('feature-scheduler','INSTALLATION','local',1,'2026-08-28 17:26:44');
INSERT INTO "wmn_feature_activations" VALUES('feature-script-reports','INSTALLATION','local',1,'2026-08-28 17:26:44');
INSERT INTO "wmn_feature_activations" VALUES('feature-workflow-approvals','INSTALLATION','local',1,'2026-08-28 21:47:40');
INSERT INTO "wmn_feature_activations" VALUES('feature-advanced-printing','INSTALLATION','local',1,'2026-08-29 23:29:37');
CREATE TABLE wmn_feature_entitlements (
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
INSERT INTO "wmn_feature_entitlements" VALUES('entitlement-feature-core-platform','feature-core-platform','GRANTED','LOCAL',NULL,NULL,'{}','2026-08-28 17:26:44');
INSERT INTO "wmn_feature_entitlements" VALUES('entitlement-feature-dashboard-charts','feature-dashboard-charts','GRANTED','LOCAL',NULL,NULL,'{}','2026-08-28 17:26:44');
INSERT INTO "wmn_feature_entitlements" VALUES('entitlement-feature-developer-tools','feature-developer-tools','GRANTED','LOCAL',NULL,NULL,'{}','2026-08-28 17:26:44');
INSERT INTO "wmn_feature_entitlements" VALUES('entitlement-feature-diagnostics','feature-diagnostics','GRANTED','LOCAL',NULL,NULL,'{}','2026-08-28 17:26:44');
INSERT INTO "wmn_feature_entitlements" VALUES('entitlement-feature-notifications','feature-notifications','GRANTED','LOCAL',NULL,NULL,'{}','2026-08-28 17:26:44');
INSERT INTO "wmn_feature_entitlements" VALUES('entitlement-feature-printing','feature-printing','GRANTED','LOCAL',NULL,NULL,'{}','2026-08-28 17:26:44');
INSERT INTO "wmn_feature_entitlements" VALUES('entitlement-feature-query-reports','feature-query-reports','GRANTED','LOCAL',NULL,NULL,'{}','2026-08-28 17:26:44');
INSERT INTO "wmn_feature_entitlements" VALUES('entitlement-feature-scheduler','feature-scheduler','GRANTED','LOCAL',NULL,NULL,'{}','2026-08-28 17:26:44');
INSERT INTO "wmn_feature_entitlements" VALUES('entitlement-feature-script-reports','feature-script-reports','GRANTED','LOCAL',NULL,NULL,'{}','2026-08-28 17:26:44');
INSERT INTO "wmn_feature_entitlements" VALUES('entitlement-feature-workflow-approvals','feature-workflow-approvals','GRANTED','LOCAL',NULL,NULL,'{}','2026-08-28 21:47:40');
INSERT INTO "wmn_feature_entitlements" VALUES('entitlement-feature-advanced-printing','feature-advanced-printing','GRANTED','LOCAL',NULL,NULL,'{}','2026-08-29 23:29:37');
CREATE TABLE wmn_features (
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
INSERT INTO "wmn_features" VALUES('feature-core-platform','core.platform','Core Platform','Required WMN platform runtime.','["lifecycle","doctype","metadata","create","save","sqlite","transactions","shell","i18n","system-settings","feature-registry","entitlements","feature-activation","users","roles","permissions","identity-context","permission-snapshot","user-permissions","document-sharing","page-registry","page-runtime","declarative-pages","page-controllers","field-control-resolver","workspace-builder","data-import-tool"]',0.0,'USD','ONE_TIME','CORE',1,0,1,'{}','2026-08-28 17:26:44','2026-08-30 01:49:37');
INSERT INTO "wmn_features" VALUES('feature-query-reports','reports.query','Query Reports','Metadata-defined query reports.','["query-reports"]',0.0,'USD','ONE_TIME',NULL,0,1,1,'{}','2026-08-28 17:26:44','2026-08-28 17:26:44');
INSERT INTO "wmn_features" VALUES('feature-script-reports','reports.script','Script Reports','Scripted reports for calculated and multi-step reporting.','["native-reports"]',0.0,'USD','ONE_TIME',NULL,0,1,1,'{}','2026-08-28 17:26:44','2026-08-28 17:26:44');
INSERT INTO "wmn_features" VALUES('feature-dashboard-charts','workspace.charts','Dashboard Charts','Workspace dashboard chart aggregation and rendering.','["workspace-registry"]',0.0,'USD','ONE_TIME',NULL,0,1,1,'{}','2026-08-28 17:26:44','2026-08-28 17:26:44');
INSERT INTO "wmn_features" VALUES('feature-printing','printing','Printing','Print formats, jobs and platform print adapters.','["print-contract","print-jobs","print-formats","pdf-contract","platform-print-adapters"]',0.0,'USD','ONE_TIME',NULL,0,1,1,'{}','2026-08-28 17:26:44','2026-08-28 17:26:44');
INSERT INTO "wmn_features" VALUES('feature-developer-tools','developer.tools','Developer Tools','DocType studio and application conversion tooling.','["doctype-studio","source-parity","app-converter"]',0.0,'USD','ONE_TIME',NULL,0,1,1,'{}','2026-08-28 17:26:44','2026-08-28 17:26:44');
INSERT INTO "wmn_features" VALUES('feature-diagnostics','system.diagnostics','Diagnostics','System diagnostics and health snapshots.','["diagnostics","health-snapshot"]',0.0,'USD','ONE_TIME',NULL,0,1,1,'{}','2026-08-28 17:26:44','2026-08-28 17:26:44');
INSERT INTO "wmn_features" VALUES('feature-scheduler','system.scheduler','Scheduler','Background jobs and schedules.','["scheduler","background-jobs","queues","schedule-registry"]',0.0,'USD','ONE_TIME',NULL,0,1,1,'{}','2026-08-28 17:26:44','2026-08-28 17:26:44');
INSERT INTO "wmn_features" VALUES('feature-notifications','system.notifications','Notifications','In-app and delivery notification contracts.','["in-app-notifications","notification-outbox","email-contract","sms-contract","push-contract"]',0.0,'USD','ONE_TIME',NULL,0,1,1,'{}','2026-08-28 17:26:44','2026-08-28 17:26:44');
INSERT INTO "wmn_features" VALUES('feature-workflow-approvals','workflow.approvals','Workflow & Approvals','Role-based states, transitions, approval chains and workflow history.','["workflow-runtime","workflow-approvals","workflow-conditions","workflow-history"]',0.0,'USD','ONE_TIME',NULL,0,1,1,'{"platform_runtime":true}','2026-08-28 21:47:40','2026-08-28 21:47:40');
INSERT INTO "wmn_features" VALUES('feature-advanced-printing','printing.advanced','Advanced Printing','ESC/POS, raw printer transports, barcode/QR and native printer adapters.','["escpos","raw-printing","barcode","qr","network-printing","usb-printing","bluetooth-printing"]',0.0,'USD','ONE_TIME','ADVANCED_PRINTING',0,1,1,'{"price_configurable":true,"native_adapter_feature":true}','2026-08-29 23:29:37','2026-08-29 23:29:37');
CREATE TABLE wmn_files (
  id TEXT PRIMARY KEY,
  file_name TEXT NOT NULL,
  file_url TEXT,
  storage_path TEXT,
  is_private INTEGER NOT NULL DEFAULT 1 CHECK (is_private IN (0,1)),
  attached_to_doctype TEXT,
  attached_to_name TEXT,
  attached_to_field TEXT,
  content_hash TEXT,
  file_size INTEGER,
  owner TEXT,
  creation TEXT NOT NULL,
  modified TEXT NOT NULL,
  metadata_json TEXT NOT NULL DEFAULT '{}'
, mime_type TEXT, source_adapter TEXT, storage_adapter TEXT, content_mode TEXT NOT NULL DEFAULT 'MANAGED_STORAGE'
  CHECK(content_mode IN ('MANAGED_STORAGE','EXTERNAL_REFERENCE')), source_reference TEXT, state TEXT NOT NULL DEFAULT 'AVAILABLE'
  CHECK(state IN ('AVAILABLE','MISSING','CORRUPT'))) STRICT;
CREATE TABLE "wmn_frappe_api_coverage" (
  source_api TEXT PRIMARY KEY,
  family TEXT NOT NULL,
  target_api TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('NATIVE','COMPAT','STRUCTURED','SAFE_SUBSET','EXPLICIT_PORT','PARTIAL','PENDING','DEFERRED','NOT_APPLICABLE')),
  source_hits INTEGER NOT NULL DEFAULT 0,
  notes TEXT,
  updated_at TEXT NOT NULL
) STRICT;
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.ValidationError','Exceptions','WmnFrappeValidationException','NATIVE',401,'Native validation exception contract.','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe._dict','Core Types','Map<String,Object?> / script object','COMPAT',1860,'Frappe dict semantics map to native Dart/JavaScript objects','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.as_json','Utilities','WmnFrappeUtils.asJson','NATIVE',101,'Native JSON serialization helper','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.bold','Formatting','WmnFrappeUtils.bold','NATIVE',881,'Native formatting helper','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.cache.get_value','Cache','wmn.frappe.cache.get','NATIVE',59,'Namespaced cache with optional TTL','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.cache.set_value','Cache','wmn.frappe.cache.set','NATIVE',39,'Namespaced cache with optional TTL','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.call','RPC','wmn.frappe.methods.call','NATIVE',668,'Native method registry with built-in frappe.client mappings','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.clear_cache','Cache','WmnFrappeUtils.clearCache','NATIVE',172,'WMN runtime cache invalidation','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.copy_doc','Document','WmnFrappeDocumentApi.copyDoc','NATIVE',219,'Creates a local unsaved document copy','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.db.bulk_update','Database','WmnFrappeDbApi.bulkUpdate','NATIVE',23,'Transactional document-layer updates; engine ownership remains enforced.','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.db.count','Database','wmn.frappe.db.count','NATIVE',139,'Filtered document count','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.db.exists','Database','wmn.frappe.db.exists','NATIVE',1110,'Name or filter existence checks','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.db.get_default','Defaults','WmnFrappeDefaults.getDefault','NATIVE',78,'User default with global fallback.','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.db.get_single_value','Database','wmn.frappe.db.getSingleValue','NATIVE',314,'Single DocType value store','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.db.get_value','Database','wmn.frappe.db.getValue','NATIVE',2290,'Document selector or filters','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.db.get_values','Database','WmnFrappeDbApi.getValues','NATIVE',63,'Structured multi-row value lookup.','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.db.set_default','Defaults','WmnFrappeDefaults.setDefault','NATIVE',52,'Native user/global default persistence.','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.db.set_single_value','Database','wmn.frappe.db.setSingleValue','NATIVE',440,'Single DocType value store','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.db.set_value','Database','wmn.frappe.db.setValue','NATIVE',834,'Writes through WmnDocumentService and cannot bypass engine-owned docs','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.db.sql','Database','WmnFrappeQueryEngine / native module service','PARTIAL',1106,'Arbitrary SQL is intentionally not exposed; common operations map to structured queries/native services','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.defaults.get_global_default','Defaults','WmnFrappeDefaults.getGlobalDefault','NATIVE',32,'Native global defaults store.','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.delete_doc','Document','WmnFrappeDocumentApi.deleteDoc','NATIVE',456,'Delete through permissions and engine ownership checks','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.delete_doc_if_exists','Document','WmnFrappeUtils.deleteDocIfExists','NATIVE',158,'Conditional document deletion with normal permission rules','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.enqueue','Jobs','wmn.frappe.jobs.enqueue','NATIVE',105,'Persistent local-first queue; server authoritative in multi-device mode','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.format','Formatting','wmn.format','PARTIAL',50,'Basic value formatting contract; DocField-aware formatters remain incremental','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.generate_hash','Utilities','WmnFrappeUtils.generateHash','NATIVE',207,'Cryptographically seeded runtime token helper','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.get_all','Database','wmn.frappe.db.getAll','NATIVE',1649,'Trusted runtime query API','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.get_cached_doc','Cache','WmnFrappeUtils.getCachedDoc','NATIVE',173,'Cached document read','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.get_cached_value','Cache','WmnFrappeUtils.getCachedValue','NATIVE',767,'Cached read over WMN document/database API','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.get_doc','Document','wmn.frappe.documents.getDoc','NATIVE',4046,'Generic DocType read with engine ownership preserved','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.get_hooks','Hooks','WmnFrappeHookRegistry.bindings','NATIVE',212,'Reads native persistent hook bindings','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.get_last_doc','Database','WmnFrappeDbApi.getLastDoc','NATIVE',64,'Permission-aware last-document lookup with explicit ordering.','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.get_lazy_doc','Documents','WmnFrappeDocumentApi.getLazyDoc','NATIVE',27,'Local-first WMN returns the document directly; no remote lazy proxy is required.','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.get_list','Database','wmn.frappe.db.getList','NATIVE',190,'Permission-aware list facade','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.get_meta','Meta','wmn.frappe.meta.getMeta','NATIVE',427,'WMN DocType metadata facade','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.get_precision','Meta','WmnFrappeMetaApi.getPrecision','NATIVE',54,'Reads DocField precision with deterministic fallback.','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.get_roles','Permissions','wmn.frappe.permissions.rolesFor','NATIVE',97,'WMN roles mapped to Frappe-compatible role names','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.get_route','Routing','wmn.getRoute','PENDING',67,'Deferred until the safe WMN script/runtime capability is enabled.','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.get_single','Database','WmnFrappeDbApi.getSingle','NATIVE',79,'Native singleton value document.','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.get_single_value','Database','WmnFrappeDbApi.getSingleValue','NATIVE',206,'Top-level compatibility alias for singleton values','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.get_system_settings','Settings','WmnFrappeUtils.getSystemSetting','NATIVE',112,'Reads WMN settings repository','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.get_value','Database','WmnFrappeDbApi.getValue','NATIVE',213,'Top-level compatibility alias to DB value API','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.has_permission','Permissions','wmn.frappe.permissions.hasPermission','NATIVE',208,'DocPerm + roles + shares + owner checks','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.log_error','Audit','WmnFrappeUtils.logError','NATIVE',132,'Records runtime errors in WMN audit trail','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.model.document','Documents','WmnDocumentService + WmnFrappeDocumentApi','STRUCTURED',279,'WMN document lifecycle is native Dart; Python Document subclasses are explicitly ported.','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.model.mapper.get_mapped_doc','Document Mapping','WmnFrappeDocumentMapper.mapDocument','STRUCTURED',43,'Metadata-aware parent/child mapping; business conditions/post-processing remain module-owned.','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.model.set_value','Client Model','wmn.model.setValue','PENDING',311,'Deferred until the safe WMN script/runtime capability is enabled.','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.model.workflow','Workflow','WmnFrappeWorkflowEngine','NATIVE',120,'Native workflow states, transitions, role checks and action history','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.msgprint','Messages','WmnFrappeMessageBus.msgprint','NATIVE',428,'Native message queue for controller warnings and information; UI decides presentation.','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.new_doc','Document','wmn.frappe.documents.newDoc','NATIVE',851,'Metadata defaults and local document state','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.parse_json','Utilities','WmnFrappeUtils.parseJson','NATIVE',29,'Native JSON parse helper.','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.provide','Namespace','wmn.provide','PENDING',265,'Deferred until the safe WMN script/runtime capability is enabled.','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.publish_realtime','Realtime','wmn.frappe.realtime.publish','NATIVE',48,'Local event bus plus persisted event log','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.qb.DocType','Query','WmnFrappeQueryEngine','PARTIAL',1259,'Structured DocType query target; arbitrary Python query-builder expressions are ported explicitly','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.qb.from_','Query','WmnFrappeQueryEngine','PARTIAL',869,'Structured select/update/delete facade','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.qb.get_query','Query','WmnFrappeQueryEngine','PARTIAL',190,'Structured query specifications instead of application SQL text','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.realtime.on','Realtime','wmn.realtime.on','PENDING',43,'Deferred until the safe WMN script/runtime capability is enabled.','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.render_template','Template','wmn.renderTemplate','PARTIAL',64,'Safe simple template compatibility; full Jinja parity remains pending','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.scrub','Utilities','WmnFrappeUtils.scrub','NATIVE',266,'Native identifier normalization helper','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.sendmail','Mail','WmnMailEngine','PENDING',55,'Reserved for server/runtime implementation','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.session.user','Session','WmnFrappeSession.user','NATIVE',47,'Native current-user session value.','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.set_route','Routing','wmn.router.setRoute','PENDING',412,'Deferred until the safe WMN script/runtime capability is enabled.','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.set_user','Session','WmnFrappeSession.setUser','NATIVE',433,'Switches runtime user only to known/enabled WMN users','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.throw','Errors','WmnFrappeValidationException','NATIVE',2615,'Native structured runtime exception','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.ui.form.on','Client Form','wmn.ui.form.on','PENDING',636,'Deferred until the safe WMN script/runtime capability is enabled.','2026-08-28 00:11:21');
INSERT INTO "wmn_frappe_api_coverage" VALUES('frappe.whitelist','External API','Deferred external API layer','DEFERRED',457,'Decorator exposure over HTTP/RPC is deferred; native module calls do not require a whitelist decorator.','2026-08-28 00:11:21');
CREATE TABLE wmn_hook_bindings (
  id TEXT PRIMARY KEY,
  hook_type TEXT NOT NULL,
  reference_doctype TEXT,
  event_name TEXT,
  source_app TEXT,
  source_path TEXT,
  target_kind TEXT NOT NULL DEFAULT 'NATIVE' CHECK (target_kind IN ('NATIVE','SERVER_SCRIPT','METHOD','PORT_REQUIRED')),
  target TEXT,
  priority INTEGER NOT NULL DEFAULT 0,
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
) STRICT;
CREATE TABLE wmn_list_view_settings (
  doctype TEXT PRIMARY KEY,
  settings_json TEXT NOT NULL DEFAULT '{}',
  updated_at TEXT NOT NULL,
  FOREIGN KEY (doctype) REFERENCES wmn_doctypes(name) ON DELETE CASCADE
) STRICT;
INSERT INTO "wmn_list_view_settings" VALUES('Report','{"fields":["report_name","report_type","ref_doctype","module","disabled"],"search_fields":["report_name","ref_doctype","module"],"sort_field":"report_name","sort_descending":false,"page_size":50,"layout":"TABLE"}','2026-08-29T00:00:00.000Z');
CREATE TABLE wmn_method_bindings (
  method_name TEXT PRIMARY KEY,
  handler_kind TEXT NOT NULL CHECK (handler_kind IN ('NATIVE','SERVER_SCRIPT','ALIAS','PORT_REQUIRED')),
  target TEXT,
  allow_guest INTEGER NOT NULL DEFAULT 0 CHECK (allow_guest IN (0,1)),
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
  source_app TEXT,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  updated_at TEXT NOT NULL
) STRICT;
CREATE TABLE wmn_modules (
  name TEXT PRIMARY KEY,
  label TEXT NOT NULL,
  app_name TEXT,
  icon TEXT,
  color TEXT,
  sequence_id REAL NOT NULL DEFAULT 0,
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (app_name) REFERENCES wmn_app_packages(app_name) ON DELETE SET NULL
) STRICT;
INSERT INTO "wmn_modules" VALUES('WMN System','WMN System',NULL,'hub',NULL,10.0,1,'{"source_framework":"WMN","system_platform":true}','2026-08-28 00:11:21','2026-08-28 00:11:21');
INSERT INTO "wmn_modules" VALUES('Security','Security',NULL,'shield',NULL,20.0,1,'{"source_framework":"WMN","system_capability":true,"optional":true}','2026-08-28 00:11:21','2026-08-28 00:11:21');
INSERT INTO "wmn_modules" VALUES('Workflow','Workflow & Approvals',NULL,'account_tree',NULL,30.0,1,'{"source_framework":"WMN","system_capability":true,"required_feature":"workflow.approvals"}','2026-08-28 21:47:40','2026-08-28 21:47:40');
CREATE TABLE wmn_naming_counters (
  series_key TEXT PRIMARY KEY,
  current_value INTEGER NOT NULL DEFAULT 0 CHECK (current_value >= 0),
  updated_at TEXT NOT NULL
) STRICT;
CREATE TABLE wmn_notifications (
  id TEXT PRIMARY KEY,
  channel TEXT NOT NULL CHECK (channel IN ('IN_APP','EMAIL','SMS','PUSH')),
  recipient TEXT,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  payload_json TEXT NOT NULL DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'QUEUED' CHECK (status IN ('QUEUED','SENT','FAILED','CANCELLED')),
  error_text TEXT,
  read_at TEXT,
  created_at TEXT NOT NULL,
  sent_at TEXT
) STRICT;
CREATE TABLE wmn_number_cards (
  name TEXT PRIMARY KEY,
  label TEXT NOT NULL,
  module TEXT NOT NULL DEFAULT 'Custom',
  app_name TEXT,
  document_type TEXT,
  function TEXT,
  aggregate_field TEXT,
  report_name TEXT,
  filters_json TEXT NOT NULL DEFAULT '[]',
  metadata_json TEXT NOT NULL DEFAULT '{}',
  updated_at TEXT NOT NULL,
  FOREIGN KEY (app_name) REFERENCES wmn_app_packages(app_name) ON DELETE SET NULL
) STRICT;
CREATE TABLE wmn_porting_symbols (
  id TEXT PRIMARY KEY,
  source_unit_id TEXT NOT NULL,
  symbol_type TEXT NOT NULL,
  symbol_name TEXT NOT NULL,
  line_start INTEGER,
  line_end INTEGER,
  lifecycle_event TEXT,
  target_kind TEXT,
  target_name TEXT,
  conversion_status TEXT NOT NULL DEFAULT 'NEEDS_PORT' CHECK (conversion_status IN ('AUTO_CONVERTED','REVIEW','NEEDS_PORT','IGNORED','FAILED')),
  confidence REAL NOT NULL DEFAULT 0 CHECK (confidence >= 0 AND confidence <= 1),
  details_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (source_unit_id) REFERENCES wmn_app_source_units(id) ON DELETE CASCADE
) STRICT;
CREATE TABLE wmn_porting_tasks (
  id TEXT PRIMARY KEY,
  app_name TEXT NOT NULL,
  artifact_id TEXT,
  task_type TEXT NOT NULL,
  title TEXT NOT NULL,
  source_path TEXT,
  priority TEXT NOT NULL DEFAULT 'MEDIUM' CHECK (priority IN ('LOW','MEDIUM','HIGH','CRITICAL')),
  status TEXT NOT NULL DEFAULT 'TODO' CHECK (status IN ('TODO','IN_PROGRESS','DONE','IGNORED')),
  details_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (app_name) REFERENCES wmn_app_packages(app_name) ON DELETE CASCADE,
  FOREIGN KEY (artifact_id) REFERENCES wmn_app_artifacts(id) ON DELETE SET NULL
) STRICT;
CREATE TABLE wmn_printers (
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
CREATE TABLE wmn_realtime_events (
  id TEXT PRIMARY KEY,
  event_name TEXT NOT NULL,
  payload_json TEXT NOT NULL DEFAULT '{}',
  room TEXT,
  user_id TEXT,
  doctype TEXT,
  docname TEXT,
  created_at TEXT NOT NULL
) STRICT;
CREATE TABLE wmn_runtime_cache (
  namespace TEXT NOT NULL,
  cache_key TEXT NOT NULL,
  value_json TEXT,
  expires_at TEXT,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(namespace, cache_key)
) STRICT;
CREATE TABLE wmn_schedules (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  handler_name TEXT NOT NULL,
  args_json TEXT NOT NULL DEFAULT '{}',
  schedule_kind TEXT NOT NULL CHECK (schedule_kind IN ('ONCE','INTERVAL')),
  interval_seconds INTEGER,
  run_at TEXT,
  next_run_at TEXT,
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
  last_job_id TEXT,
  last_run_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (last_job_id) REFERENCES wmn_background_jobs(id) ON DELETE SET NULL,
  CHECK (
    (schedule_kind='ONCE' AND run_at IS NOT NULL)
    OR (schedule_kind='INTERVAL' AND interval_seconds IS NOT NULL AND interval_seconds > 0)
  )
) STRICT;
CREATE TABLE wmn_scoped_settings (
  scope_type TEXT NOT NULL CHECK (scope_type IN ('SYSTEM','APPLICATION','PLATFORM','PROFILE')),
  scope_key TEXT NOT NULL DEFAULT '',
  setting_key TEXT NOT NULL,
  value_json TEXT,
  is_secret INTEGER NOT NULL DEFAULT 0 CHECK (is_secret IN (0,1)),
  updated_at TEXT NOT NULL,
  PRIMARY KEY (scope_type, scope_key, setting_key)
) STRICT;
CREATE TABLE wmn_storage_blobs(storage_key TEXT PRIMARY KEY,content BLOB NOT NULL,updated_at TEXT NOT NULL) STRICT;
CREATE TABLE wmn_system_logs (
  id TEXT PRIMARY KEY,
  level TEXT NOT NULL CHECK (level IN ('DEBUG','INFO','WARNING','ERROR','CRITICAL')),
  source TEXT NOT NULL,
  event_name TEXT,
  message TEXT NOT NULL,
  details_json TEXT NOT NULL DEFAULT '{}',
  correlation_id TEXT,
  stack_trace TEXT,
  created_at TEXT NOT NULL
) STRICT;
CREATE TABLE wmn_user_permissions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  allow_doctype TEXT NOT NULL,
  for_value TEXT NOT NULL,
  applicable_for TEXT,
  is_default INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0,1)),
  hide_descendants INTEGER NOT NULL DEFAULT 0 CHECK (hide_descendants IN (0,1)),
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(user_id, allow_doctype, for_value, applicable_for)
) STRICT;
CREATE TABLE wmn_workflow_actions (
  id TEXT PRIMARY KEY,
  workflow_id TEXT NOT NULL,
  doctype TEXT NOT NULL,
  docname TEXT NOT NULL,
  action TEXT NOT NULL,
  from_state TEXT,
  to_state TEXT NOT NULL,
  user_id TEXT,
  status TEXT NOT NULL DEFAULT 'COMPLETED' CHECK (status IN ('COMPLETED','REJECTED','FAILED')),
  comment TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (workflow_id) REFERENCES wmn_workflows(id) ON DELETE CASCADE
) STRICT;
CREATE TABLE wmn_workflow_states (
  id TEXT PRIMARY KEY,
  workflow_id TEXT NOT NULL,
  state_name TEXT NOT NULL,
  doc_status INTEGER NOT NULL DEFAULT 0 CHECK (doc_status IN (0,1,2)),
  allow_edit_role TEXT,
  idx INTEGER NOT NULL DEFAULT 0,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (workflow_id) REFERENCES wmn_workflows(id) ON DELETE CASCADE,
  UNIQUE(workflow_id, state_name)
) STRICT;
CREATE TABLE wmn_workflow_transitions (
  id TEXT PRIMARY KEY,
  workflow_id TEXT NOT NULL,
  state_name TEXT NOT NULL,
  action TEXT NOT NULL,
  next_state TEXT NOT NULL,
  allowed_role TEXT,
  condition_expression TEXT,
  idx INTEGER NOT NULL DEFAULT 0,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (workflow_id) REFERENCES wmn_workflows(id) ON DELETE CASCADE,
  UNIQUE(workflow_id, state_name, action, next_state, allowed_role)
) STRICT;
CREATE TABLE wmn_workflows (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  doctype TEXT NOT NULL,
  state_field TEXT NOT NULL DEFAULT 'workflow_state',
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
  send_email INTEGER NOT NULL DEFAULT 0 CHECK (send_email IN (0,1)),
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
) STRICT;
CREATE TABLE wmn_workspace_items (
  id TEXT PRIMARY KEY,
  workspace_name TEXT NOT NULL,
  region TEXT NOT NULL DEFAULT 'CONTENT' CHECK (region IN ('CONTENT','LINKS','SHORTCUTS','SIDEBAR','CHARTS','NUMBER_CARDS','QUICK_LISTS')),
  item_type TEXT NOT NULL,
  label TEXT,
  link_type TEXT,
  link_to TEXT,
  icon TEXT,
  parent_label TEXT,
  idx INTEGER NOT NULL DEFAULT 0,
  column_span INTEGER NOT NULL DEFAULT 4,
  hidden INTEGER NOT NULL DEFAULT 0 CHECK (hidden IN (0,1)),
  item_json TEXT NOT NULL DEFAULT '{}',
  FOREIGN KEY (workspace_name) REFERENCES "tabWorkspace"(name) ON DELETE CASCADE
) STRICT;
CREATE INDEX idx_client_scripts_document
ON client_scripts(document_type, enabled, priority DESC, name);
CREATE INDEX idx_custom_field_values_lookup
ON custom_field_values(document_type, field_name, document_id);
CREATE INDEX idx_custom_fields_document
ON custom_fields(document_type, enabled, sort_order, field_name);
CREATE INDEX idx_data_import_jobs_created
ON data_import_jobs(created_at DESC, status);
CREATE INDEX idx_data_import_rows_job
ON data_import_rows(job_id, row_number);
CREATE INDEX idx_property_overrides_document
ON property_overrides(document_type, enabled, field_name);
CREATE INDEX idx_script_log_created
ON script_execution_log(created_at DESC, script_kind, status);
CREATE INDEX idx_server_scripts_event
ON server_scripts(script_type, document_type, event_name, enabled, priority DESC);
CREATE INDEX idx_tab_report_module_type
ON "tabReport"(module, report_type, disabled, report_name);
CREATE INDEX idx_wmn_app_artifacts_status
ON wmn_app_artifacts(app_name, conversion_status, artifact_type);
CREATE INDEX idx_wmn_app_conversion_runs_app
ON wmn_app_conversion_runs(app_name, started_at DESC);
CREATE INDEX idx_wmn_app_dependencies_resolved
ON wmn_app_dependencies(app_name, resolved, dependency_kind);
CREATE INDEX idx_wmn_assignments_doc
ON wmn_assignments(doctype, docname, status);
CREATE INDEX idx_wmn_assignments_user
ON wmn_assignments(allocated_to, status, due_date);
CREATE INDEX idx_wmn_background_jobs_queue
ON wmn_background_jobs(status, queue_name, run_after, created_at);
CREATE INDEX idx_wmn_comments_doc
ON wmn_comments(doctype, docname, creation DESC);
CREATE INDEX idx_wmn_doc_shares_user
ON wmn_doc_shares(user_id, doctype, docname);
CREATE INDEX idx_wmn_doctype_fields_order
ON wmn_doctype_fields(doctype, idx, fieldname);
CREATE INDEX idx_wmn_doctype_permissions_role
ON wmn_doctype_permissions(role, doctype, permlevel);
CREATE INDEX idx_wmn_doctypes_module
ON wmn_doctypes(module, enabled, name);
CREATE INDEX idx_wmn_document_versions_doc
ON wmn_document_versions(doctype, docname, version_no DESC);
CREATE INDEX idx_wmn_files_attachment
ON wmn_files(attached_to_doctype, attached_to_name, creation DESC);
CREATE INDEX idx_wmn_hook_bindings_lookup
ON wmn_hook_bindings(hook_type, reference_doctype, event_name, enabled, priority);
CREATE INDEX idx_wmn_modules_app
ON wmn_modules(app_name, sequence_id, label);
CREATE INDEX idx_wmn_porting_symbols_unit
ON wmn_porting_symbols(source_unit_id, line_start, symbol_name);
CREATE INDEX idx_wmn_porting_tasks_app
ON wmn_porting_tasks(app_name, status, priority);
CREATE INDEX idx_wmn_realtime_events_name
ON wmn_realtime_events(event_name, created_at DESC);
CREATE INDEX idx_wmn_runtime_cache_expiry
ON wmn_runtime_cache(expires_at);
CREATE INDEX idx_wmn_source_units_status
ON wmn_app_source_units(app_name, conversion_status, language, source_path);
CREATE INDEX idx_wmn_user_permissions_lookup
ON wmn_user_permissions(user_id, applicable_for, allow_doctype, enabled);
CREATE INDEX idx_wmn_workflow_actions_doc
ON wmn_workflow_actions(doctype, docname, created_at DESC);
CREATE INDEX idx_wmn_workflow_transitions_lookup
ON wmn_workflow_transitions(workflow_id, state_name, idx);
CREATE INDEX idx_wmn_workflows_doctype
ON wmn_workflows(doctype, enabled);
CREATE INDEX idx_wmn_workspace_items_order
ON wmn_workspace_items(workspace_name, region, idx);
CREATE INDEX idx_wmn_workspaces_order
ON "tabWorkspace"(is_hidden, sequence_id, label);
CREATE INDEX idx_user_roles_user ON user_roles(user_id, role_id);
CREATE INDEX idx_numbering_series_scope ON numbering_series(document_type, scope_type, scope_value, enabled);
CREATE INDEX idx_print_jobs_document ON print_jobs(document_type, document_name, created_at);
CREATE INDEX idx_wmn_scoped_settings_lookup
ON wmn_scoped_settings(scope_type, scope_key, setting_key);
CREATE INDEX idx_wmn_system_logs_created
ON wmn_system_logs(created_at DESC, level, source);
CREATE INDEX idx_wmn_system_logs_correlation
ON wmn_system_logs(correlation_id, created_at DESC);
CREATE INDEX idx_wmn_schedules_due
ON wmn_schedules(enabled, next_run_at, name);
CREATE INDEX idx_wmn_notifications_recipient
ON wmn_notifications(recipient, read_at, created_at DESC);
CREATE INDEX idx_wmn_notifications_status
ON wmn_notifications(channel, status, created_at);
CREATE INDEX idx_tab_page_enabled_route ON "tabPage"(enabled, route);
CREATE INDEX idx_wmn_printers_enabled ON wmn_printers(enabled, platform, name);
CREATE INDEX idx_wmn_features_enabled ON wmn_features(enabled, code);
CREATE INDEX idx_wmn_feature_entitlements_status ON wmn_feature_entitlements(status, feature_id);
CREATE INDEX idx_wmn_feature_activations_scope ON wmn_feature_activations(scope_type,scope_key,enabled);
CREATE UNIQUE INDEX idx_role_permissions_id ON role_permissions(id);
CREATE INDEX idx_roles_enabled_code ON roles(enabled, code, name);
CREATE INDEX idx_permissions_code ON permissions(code);
CREATE INDEX idx_role_permissions_role_granted ON role_permissions(role_id, granted, permission_id);
CREATE INDEX idx_wmn_doctype_permissions_doctype_role ON wmn_doctype_permissions(doctype, role, permlevel);
CREATE INDEX idx_wmn_user_permissions_user_enabled ON wmn_user_permissions(user_id, enabled, allow_doctype, applicable_for);
CREATE INDEX idx_tab_page_app_enabled
ON [tabPage](app_name,enabled,module,title);
CREATE INDEX idx_report_run_log_created on report_run_log(created_at desc,status);
CREATE INDEX idx_tab_report_runtime on tabReport(report_type,disabled,module,report_name);
CREATE INDEX idx_wmn_files_storage_path on wmn_files(storage_path);
CREATE INDEX idx_report_filter_parent ON [tabReport Filter](parenttype,parent,parentfield,idx);
CREATE INDEX idx_report_column_parent ON [tabReport Column](parenttype,parent,parentfield,idx);
CREATE INDEX idx_print_formats_target
ON print_formats(enabled,target_type,document_type,report_name,is_default);
CREATE INDEX idx_print_jobs_format
ON print_jobs(print_format_id,created_at DESC);
CREATE INDEX idx_print_jobs_output
ON print_jobs(output_file_id);
CREATE TRIGGER trg_print_formats_validate_insert
BEFORE INSERT ON print_formats
BEGIN
  SELECT CASE
    WHEN trim(NEW.code)='' THEN RAISE(ABORT,'Print Format code is required')
    WHEN trim(NEW.name)='' THEN RAISE(ABORT,'Print Format name is required')
    WHEN trim(NEW.renderer_id)='' THEN RAISE(ABORT,'Print Format renderer_id is required')
    WHEN trim(NEW.template_text)='' THEN RAISE(ABORT,'Print Format template cannot be empty')
    WHEN NEW.target_type='DOCUMENT' AND (NEW.document_type IS NULL OR trim(NEW.document_type)='')
      THEN RAISE(ABORT,'Document Print Format requires document_type')
    WHEN NEW.target_type='REPORT' AND (NEW.report_name IS NULL OR trim(NEW.report_name)='')
      THEN RAISE(ABORT,'Report Print Format requires report_name')
  END;
END;
CREATE TRIGGER trg_print_formats_validate_update
BEFORE UPDATE ON print_formats
BEGIN
  SELECT CASE
    WHEN trim(NEW.code)='' THEN RAISE(ABORT,'Print Format code is required')
    WHEN trim(NEW.name)='' THEN RAISE(ABORT,'Print Format name is required')
    WHEN trim(NEW.renderer_id)='' THEN RAISE(ABORT,'Print Format renderer_id is required')
    WHEN trim(NEW.template_text)='' THEN RAISE(ABORT,'Print Format template cannot be empty')
    WHEN NEW.target_type='DOCUMENT' AND (NEW.document_type IS NULL OR trim(NEW.document_type)='')
      THEN RAISE(ABORT,'Document Print Format requires document_type')
    WHEN NEW.target_type='REPORT' AND (NEW.report_name IS NULL OR trim(NEW.report_name)='')
      THEN RAISE(ABORT,'Report Print Format requires report_name')
  END;
END;
CREATE INDEX idx_wmn_files_hash
ON wmn_files(content_hash,file_size);
CREATE INDEX idx_wmn_files_state
ON wmn_files(state,creation DESC);
CREATE INDEX idx_wmn_files_attachment_field
ON wmn_files(attached_to_doctype,attached_to_name,attached_to_field,creation DESC);
CREATE INDEX idx_tab_workspace_item_parent
ON [tabWorkspaceItem](parenttype,parent,parentfield,idx,name);
COMMIT;
