import 'package:sqlite3/common.dart';

import 'database_migration.dart';

/// R3.20.x Frappe-compatible print runtime.
///
/// Letter Head is a first-class System DocType. Print Format owns the visual
/// template/CSS contract while canonical HTML is the single representation
/// consumed by Preview/PDF/Print backends.
class Migration035FrappePrintRuntime extends SqlDatabaseMigration {
  const Migration035FrappePrintRuntime();

  @override
  int get version => 35;

  @override
  String get name => 'frappe_print_runtime';

  @override
  void apply(CommonDatabase database) {
    super.apply(database);
    for (final triggerSql in _defaultLetterHeadTriggers) {
      database.execute(triggerSql);
    }
  }

  static const List<String> _defaultLetterHeadTriggers = <String>[
    r'''CREATE TRIGGER IF NOT EXISTS trg_letter_head_default_insert
AFTER INSERT ON "tabLetter Head"
WHEN NEW.is_default=1 AND NEW.disabled=0
BEGIN
  UPDATE "tabLetter Head"
  SET is_default=0,
      updated_at=datetime('now')
  WHERE id<>NEW.id AND is_default=1;
END;''',
    r'''CREATE TRIGGER IF NOT EXISTS trg_letter_head_default_update
AFTER UPDATE OF is_default,disabled ON "tabLetter Head"
WHEN NEW.is_default=1 AND NEW.disabled=0
BEGIN
  UPDATE "tabLetter Head"
  SET is_default=0,
      updated_at=datetime('now')
  WHERE id<>NEW.id AND is_default=1;
END;''',
  ];

  @override
  String get sql => r'''
CREATE TABLE IF NOT EXISTS "tabLetter Head"(
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL UNIQUE,
  header_html TEXT NOT NULL DEFAULT '',
  footer_html TEXT NOT NULL DEFAULT '',
  css_text TEXT NOT NULL DEFAULT '',
  is_default INTEGER NOT NULL DEFAULT 0 CHECK(is_default IN (0,1)),
  disabled INTEGER NOT NULL DEFAULT 0 CHECK(disabled IN (0,1)),
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_letter_head_enabled_default
ON "tabLetter Head"(disabled,is_default,name);

ALTER TABLE print_formats ADD COLUMN letter_head_id TEXT;
ALTER TABLE print_formats ADD COLUMN default_print_language TEXT;
ALTER TABLE print_formats ADD COLUMN font_family TEXT;
ALTER TABLE print_formats ADD COLUMN pdf_generator TEXT NOT NULL DEFAULT 'AUTO'
  CHECK(pdf_generator IN ('AUTO','PLATFORM','CHROMIUM'));

ALTER TABLE print_settings ADD COLUMN default_letter_head_id TEXT;
ALTER TABLE print_settings ADD COLUMN default_print_language TEXT;

UPDATE print_formats
SET metadata_json=json_set(
      COALESCE(NULLIF(metadata_json,''),'{}'),
      '$.canonical_html',1,
      '$.frappe_print_contract',1
    ),
    updated_at=datetime('now');

UPDATE print_settings
SET default_print_language=COALESCE(NULLIF(default_print_language,''),'en'),
    metadata_json=json_set(
      COALESCE(NULLIF(metadata_json,''),'{}'),
      '$.canonical_html',1,
      '$.frappe_print_contract',1
    ),
    updated_at=datetime('now');

INSERT INTO wmn_doctypes(
  name,module,storage_mode,table_name,id_field,title_field,autoname,
  is_single,is_child,is_submittable,track_changes,
  allow_create,allow_edit,allow_delete,allow_import,allow_export,generic_write,
  is_system,enabled,metadata_json,created_at,updated_at
)
VALUES(
  'Letter Head','WMN System','TABLE','tabLetter Head','id','name','field:name',
  0,0,0,1,
  1,1,1,1,1,1,
  1,1,
  '{"protected":true,"printing_engine":true,"frappe_compatible":true}',
  datetime('now'),datetime('now')
)
ON CONFLICT(name) DO UPDATE SET
  module=excluded.module,storage_mode=excluded.storage_mode,table_name=excluded.table_name,
  id_field=excluded.id_field,title_field=excluded.title_field,autoname=excluded.autoname,
  allow_create=1,allow_edit=1,allow_delete=1,allow_import=1,allow_export=1,
  generic_write=1,is_system=1,enabled=1,metadata_json=excluded.metadata_json,
  updated_at=datetime('now');

INSERT INTO wmn_doctype_fields(
  id,doctype,fieldname,label,fieldtype,options,idx,reqd,read_only,hidden,
  in_list_view,in_standard_filter,searchable,allow_on_submit,default_json,
  depends_on,mandatory_depends_on,read_only_depends_on,fetch_from,precision,
  length,metadata_json,created_at,updated_at
)
VALUES
('lh-id','Letter Head','id','ID','Data',NULL,10,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('lh-name','Letter Head','name','Letter Head Name','Data',NULL,20,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('lh-header','Letter Head','header_html','Header HTML','Code','HTML',30,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{"language":"HTML","print_html":true}',datetime('now'),datetime('now')),
('lh-footer','Letter Head','footer_html','Footer HTML','Code','HTML',40,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{"language":"HTML","print_html":true}',datetime('now'),datetime('now')),
('lh-css','Letter Head','css_text','Custom CSS','Code','CSS',50,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{"language":"CSS","print_html":true}',datetime('now'),datetime('now')),
('lh-default','Letter Head','is_default','Default','Check',NULL,60,0,0,0,1,1,0,0,'false',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('lh-disabled','Letter Head','disabled','Disabled','Check',NULL,70,0,0,0,1,1,0,0,'false',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('lh-metadata','Letter Head','metadata_json','Metadata JSON','Code',NULL,80,0,0,1,0,0,0,0,'"{}"',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('lh-created','Letter Head','created_at','Created At','Datetime',NULL,90,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('lh-updated','Letter Head','updated_at','Updated At','Datetime',NULL,100,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now'))
ON CONFLICT(doctype,fieldname) DO UPDATE SET
  label=excluded.label,fieldtype=excluded.fieldtype,options=excluded.options,idx=excluded.idx,
  reqd=excluded.reqd,read_only=excluded.read_only,hidden=excluded.hidden,
  in_list_view=excluded.in_list_view,in_standard_filter=excluded.in_standard_filter,
  searchable=excluded.searchable,default_json=excluded.default_json,
  metadata_json=excluded.metadata_json,updated_at=excluded.updated_at;

INSERT INTO wmn_doctype_fields(
  id,doctype,fieldname,label,fieldtype,options,idx,reqd,read_only,hidden,
  in_list_view,in_standard_filter,searchable,allow_on_submit,default_json,
  depends_on,mandatory_depends_on,read_only_depends_on,fetch_from,precision,
  length,metadata_json,created_at,updated_at
)
VALUES
('pf-letter-head','Print Format','letter_head_id','Letter Head','Link','Letter Head',95,0,0,0,0,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{"frappe_print_contract":true}',datetime('now'),datetime('now')),
('pf-language','Print Format','default_print_language','Default Print Language','Data',NULL,96,0,0,0,0,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,24,'{"frappe_print_contract":true}',datetime('now'),datetime('now')),
('pf-font-family','Print Format','font_family','Font Family','Data',NULL,97,0,0,0,0,0,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{"css_font_family":true}',datetime('now'),datetime('now')),
('pf-pdf-generator','Print Format','pdf_generator','PDF Generator','Select','AUTO\nPLATFORM\nCHROMIUM',98,1,0,0,0,1,0,0,'"AUTO"',NULL,NULL,NULL,NULL,NULL,NULL,'{"backend_selector":true}',datetime('now'),datetime('now')),
('ps-letter-head','Print Settings','default_letter_head_id','Default Letter Head','Link','Letter Head',45,0,0,0,0,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{"frappe_print_contract":true}',datetime('now'),datetime('now')),
('ps-language','Print Settings','default_print_language','Default Print Language','Data',NULL,46,0,0,0,0,1,1,0,'"en"',NULL,NULL,NULL,NULL,NULL,24,'{"frappe_print_contract":true}',datetime('now'),datetime('now'))
ON CONFLICT(doctype,fieldname) DO UPDATE SET
  label=excluded.label,fieldtype=excluded.fieldtype,options=excluded.options,idx=excluded.idx,
  reqd=excluded.reqd,read_only=excluded.read_only,hidden=excluded.hidden,
  in_list_view=excluded.in_list_view,in_standard_filter=excluded.in_standard_filter,
  searchable=excluded.searchable,default_json=excluded.default_json,
  metadata_json=excluded.metadata_json,updated_at=excluded.updated_at;

INSERT INTO wmn_doctype_permissions(
  id,doctype,role,permlevel,can_read,can_write,can_create,can_delete,
  can_submit,can_cancel,can_amend,can_report,can_import,can_export,
  can_share,can_print,can_email,if_owner,metadata_json
)
VALUES(
  'docperm-letter-head-system-manager','Letter Head','System Manager',0,
  1,1,1,1,0,0,0,1,1,1,0,0,0,0,
  '{"platform_default":true,"printing_engine":true}'
)
ON CONFLICT(doctype,role,permlevel) DO UPDATE SET
  can_read=1,can_write=1,can_create=1,can_delete=1,can_report=1,
  can_import=1,can_export=1,metadata_json=excluded.metadata_json;
''';
}
