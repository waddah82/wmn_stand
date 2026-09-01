import 'database_migration.dart';

/// R3.9 metadata-driven Page runtime foundation.
///
/// The Page table already exists from schema v22. This migration only adds
/// runtime metadata/indexes and permission defaults; no duplicate Page storage
/// is introduced.
class Migration024PageRuntime extends SqlDatabaseMigration {
  const Migration024PageRuntime();

  @override
  int get version => 24;

  @override
  String get name => 'page_runtime';

  @override
  String get sql => r'''
CREATE INDEX IF NOT EXISTS idx_tab_page_app_enabled
ON [tabPage](app_name,enabled,module,title);

UPDATE wmn_doctypes
SET metadata_json='{"page_types":["STANDARD","DASHBOARD","CUSTOM","LIST","FORM","REPORT","WORKSPACE"],"runtime":"WMN_PAGE_RUNTIME","metadata_layout":true}',
    updated_at=datetime('now')
WHERE name='Page';

INSERT INTO wmn_doctype_permissions(
  id,doctype,role,permlevel,can_read,can_write,can_create,can_delete,
  can_submit,can_cancel,can_amend,can_report,can_import,can_export,
  can_share,can_print,can_email,if_owner,metadata_json
)
VALUES(
  'docperm-page-system-manager','Page','System Manager',0,
  1,1,1,1,0,0,0,1,1,1,0,0,0,0,
  '{"platform_default":true,"runtime":"WMN_PAGE_RUNTIME"}'
)
ON CONFLICT(doctype,role,permlevel) DO UPDATE SET
  can_read=excluded.can_read,can_write=excluded.can_write,
  can_create=excluded.can_create,can_delete=excluded.can_delete,
  can_report=excluded.can_report,can_import=excluded.can_import,
  can_export=excluded.can_export,metadata_json=excluded.metadata_json;

INSERT INTO wmn_doctype_fields(
  id,doctype,fieldname,label,fieldtype,options,idx,reqd,read_only,hidden,
  in_list_view,in_standard_filter,searchable,allow_on_submit,default_json,
  depends_on,mandatory_depends_on,read_only_depends_on,fetch_from,precision,
  length,metadata_json,created_at,updated_at
)
VALUES
('page-field-name','Page','name','Page Name','Data',NULL,10,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,140,'{}',datetime('now'),datetime('now')),
('page-field-title','Page','title','Title','Data',NULL,20,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,200,'{}',datetime('now'),datetime('now')),
('page-field-route','Page','route','Route','Data',NULL,30,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,240,'{}',datetime('now'),datetime('now')),
('page-field-app','Page','app_name','Application','Link','Application',40,0,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('page-field-module','Page','module','Module','Link','Module',50,1,0,0,1,1,1,0,'"WMN System"',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('page-field-type','Page','page_type','Page Type','Select','STANDARD
DASHBOARD
CUSTOM
LIST
FORM
REPORT
WORKSPACE',60,1,0,0,1,1,1,0,'"STANDARD"',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('page-field-controller','Page','controller_key','Controller Key','Data',NULL,70,0,0,0,0,0,1,0,NULL,NULL,NULL,NULL,NULL,NULL,240,'{}',datetime('now'),datetime('now')),
('page-field-roles','Page','roles_json','Roles','JSON',NULL,80,0,0,0,0,0,0,0,'[]',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('page-field-permissions','Page','permissions_json','Permissions','JSON',NULL,90,0,0,0,0,0,0,0,'[]',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('page-field-enabled','Page','enabled','Enabled','Check',NULL,100,0,0,0,1,1,0,0,'true',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('page-field-metadata','Page','metadata_json','Page Metadata','JSON',NULL,110,0,0,0,0,0,0,0,'{}',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now'))
ON CONFLICT(doctype,fieldname) DO UPDATE SET
  label=excluded.label,fieldtype=excluded.fieldtype,options=excluded.options,
  idx=excluded.idx,reqd=excluded.reqd,read_only=excluded.read_only,
  hidden=excluded.hidden,in_list_view=excluded.in_list_view,
  in_standard_filter=excluded.in_standard_filter,searchable=excluded.searchable,
  default_json=excluded.default_json,metadata_json=excluded.metadata_json,
  updated_at=excluded.updated_at;

UPDATE wmn_features
SET capability_ids_json='["lifecycle","doctype","metadata","create","save","sqlite","transactions","shell","i18n","system-settings","feature-registry","entitlements","feature-activation","users","roles","permissions","identity-context","permission-snapshot","user-permissions","document-sharing","page-registry","page-runtime","declarative-pages","page-controllers"]',
    updated_at=datetime('now')
WHERE code='core.platform';
''';
}
