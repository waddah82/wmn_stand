import 'database_migration.dart';

/// R3.19 metadata/runtime completion.
///
/// - Workspace becomes a real Parent + Child Table editor.
/// - Data Import history is exposed as a read-only engine-backed DocType while
///   the import/export operation itself remains a Tool/Page runtime.
/// - A system Runtime Laboratory seeds every currently supported Page type so
///   the platform can be exercised without a business application.
class Migration032MetadataRuntimeCompletion extends SqlDatabaseMigration {
  const Migration032MetadataRuntimeCompletion();

  @override
  int get version => 32;

  @override
  String get name => 'metadata_runtime_completion';

  @override
  String get sql => r'''
CREATE TABLE IF NOT EXISTS [tabWorkspaceItem] (
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

CREATE INDEX IF NOT EXISTS idx_tab_workspace_item_parent
ON [tabWorkspaceItem](parenttype,parent,parentfield,idx,name);

INSERT OR IGNORE INTO [tabWorkspaceItem](
  name,creation,modified,docstatus,idx,parent,parentfield,parenttype,region,item_type,
  label,link_type,link_to,icon,parent_label,column_span,hidden,required_feature,description,item_json
)
SELECT
  id,datetime('now'),datetime('now'),0,idx+1,workspace_name,'items','Workspace',region,item_type,
  label,link_type,link_to,icon,parent_label,column_span,hidden,
  json_extract(item_json,'$.required_feature'),json_extract(item_json,'$.description'),item_json
FROM wmn_workspace_items;

INSERT INTO wmn_doctypes(
  name,module,storage_mode,table_name,id_field,title_field,autoname,is_single,is_child,
  is_submittable,track_changes,allow_create,allow_edit,allow_delete,allow_import,
  allow_export,generic_write,is_system,enabled,metadata_json,created_at,updated_at
)
VALUES
('Workspace Item','WMN System','TABLE','tabWorkspaceItem','name','label',NULL,0,1,0,1,1,1,1,0,1,1,1,1,
 '{"runtime":"WORKSPACE_BUILDER","child_of":"Workspace","table_editor":true}',datetime('now'),datetime('now')),
('Data Import Job','WMN System','TABLE','data_import_jobs','id','file_name',NULL,0,0,0,0,0,0,0,0,1,0,1,1,
 '{"runtime_owned":true,"tool":"DATA_IMPORT","read_only":true}',datetime('now'),datetime('now')),
('Data Export Job','WMN System','TABLE','data_export_jobs','id','doctype',NULL,0,0,0,0,0,0,0,0,1,0,1,1,
 '{"runtime_owned":true,"tool":"DATA_EXPORT","read_only":true}',datetime('now'),datetime('now'))
ON CONFLICT(name) DO UPDATE SET
  module=excluded.module,storage_mode=excluded.storage_mode,table_name=excluded.table_name,
  id_field=excluded.id_field,title_field=excluded.title_field,is_child=excluded.is_child,
  generic_write=excluded.generic_write,is_system=1,enabled=1,metadata_json=excluded.metadata_json,
  updated_at=excluded.updated_at;

UPDATE wmn_doctypes
SET metadata_json='{"runtime":"WORKSPACE_BUILDER","layout":"PARENT_CHILD_TABLES","legacy_content_json":"import_compat_only"}',
    updated_at=datetime('now')
WHERE name='Workspace';

INSERT INTO wmn_doctype_fields(
  id,doctype,fieldname,label,fieldtype,options,idx,reqd,read_only,hidden,
  in_list_view,in_standard_filter,searchable,allow_on_submit,default_json,
  depends_on,mandatory_depends_on,read_only_depends_on,fetch_from,precision,length,
  metadata_json,created_at,updated_at
)
VALUES
('workspace-name','Workspace','name','Workspace Name','Data',NULL,10,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('workspace-label','Workspace','label','Label','Data',NULL,20,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,220,'{}',datetime('now'),datetime('now')),
('workspace-module','Workspace','module','Module','Link','Module',30,1,0,0,1,1,1,0,'"Custom"',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('workspace-app','Workspace','app_name','Application','Link','Application',40,0,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('workspace-icon','Workspace','icon','Icon','Data',NULL,50,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,120,'{}',datetime('now'),datetime('now')),
('workspace-parent-page','Workspace','parent_page','Parent Page','Link','Workspace',60,0,0,0,0,0,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('workspace-sequence','Workspace','sequence_id','Sequence','Float',NULL,70,0,0,0,1,0,0,0,'0',NULL,NULL,NULL,NULL,2,NULL,'{}',datetime('now'),datetime('now')),
('workspace-public','Workspace','is_public','Public','Check',NULL,80,0,0,0,1,1,0,0,'true',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('workspace-hidden','Workspace','is_hidden','Hidden','Check',NULL,90,0,0,0,1,1,0,0,'false',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('workspace-items','Workspace','items','Items','Table','Workspace Item',100,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
 '{"workspace_builder":true,"description":"Workspace layout rows. No JSON/code editing is required."}',datetime('now'),datetime('now')),

('workspace-item-region','Workspace Item','region','Region','Select','CONTENT\nLINKS\nSHORTCUTS\nSIDEBAR\nCHARTS\nNUMBER_CARDS\nQUICK_LISTS',10,1,0,0,1,1,1,0,'"CONTENT"',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('workspace-item-type','Workspace Item','item_type','Item Type','Select','shortcut\nheader\nspacer\ncard\nnumber_card\nchart\nquick_list\nlink',20,1,0,0,1,1,1,0,'"shortcut"',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('workspace-item-label','Workspace Item','label','Label','Data',NULL,30,0,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,220,'{}',datetime('now'),datetime('now')),
('workspace-item-link-type','Workspace Item','link_type','Link Type','Select','DocType\nPage\nReport\nWorkspace\nQuery Report',40,0,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('workspace-item-link-to','Workspace Item','link_to','Target','Data',NULL,50,0,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,240,'{}',datetime('now'),datetime('now')),
('workspace-item-icon','Workspace Item','icon','Icon','Data',NULL,60,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,120,'{}',datetime('now'),datetime('now')),
('workspace-item-parent-label','Workspace Item','parent_label','Parent Label','Data',NULL,70,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('workspace-item-span','Workspace Item','column_span','Column Span','Int',NULL,80,0,0,0,0,0,0,0,'4',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('workspace-item-feature','Workspace Item','required_feature','Required Feature','Data',NULL,90,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('workspace-item-description','Workspace Item','description','Description','Small Text',NULL,100,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('workspace-item-hidden','Workspace Item','hidden','Hidden','Check',NULL,110,0,0,0,0,0,0,0,'false',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),

('data-import-job-id','Data Import Job','id','Job ID','Data',NULL,10,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('data-import-job-doctype','Data Import Job','doctype','DocType','Data',NULL,20,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{"render_as":"LINK","link_target":"DocType"}',datetime('now'),datetime('now')),
('data-import-job-mode','Data Import Job','import_mode','Import Mode','Select','INSERT\nUPDATE\nUPSERT',30,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('data-import-job-file','Data Import Job','file_name','File','Data',NULL,40,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,240,'{}',datetime('now'),datetime('now')),
('data-import-job-status','Data Import Job','status','Status','Select','DRAFT\nVALIDATED\nCOMPLETED\nPARTIAL\nFAILED',50,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('data-import-job-total','Data Import Job','total_rows','Total Rows','Int',NULL,60,0,1,0,1,0,0,0,'0',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('data-import-job-success','Data Import Job','success_rows','Success Rows','Int',NULL,70,0,1,0,1,0,0,0,'0',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('data-import-job-failed','Data Import Job','failed_rows','Failed Rows','Int',NULL,80,0,1,0,1,0,0,0,'0',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('data-import-job-created','Data Import Job','created_at','Created At','Datetime',NULL,90,0,1,0,1,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('data-import-job-completed','Data Import Job','completed_at','Completed At','Datetime',NULL,100,0,1,0,1,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),

('data-export-job-id','Data Export Job','id','Job ID','Data',NULL,10,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('data-export-job-doctype','Data Export Job','doctype','DocType','Data',NULL,20,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{"render_as":"LINK","link_target":"DocType"}',datetime('now'),datetime('now')),
('data-export-job-format','Data Export Job','format','Format','Select','CSV\nJSON',30,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('data-export-job-row-count','Data Export Job','row_count','Rows','Int',NULL,40,0,1,0,1,0,0,0,'0',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('data-export-job-created','Data Export Job','created_at','Created At','Datetime',NULL,50,0,1,0,1,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now'))
ON CONFLICT(doctype,fieldname) DO UPDATE SET
  label=excluded.label,fieldtype=excluded.fieldtype,options=excluded.options,idx=excluded.idx,
  reqd=excluded.reqd,read_only=excluded.read_only,hidden=excluded.hidden,
  in_list_view=excluded.in_list_view,in_standard_filter=excluded.in_standard_filter,
  searchable=excluded.searchable,default_json=excluded.default_json,length=excluded.length,
  metadata_json=excluded.metadata_json,updated_at=excluded.updated_at;

INSERT INTO [tabWorkspace](
  name,label,module,app_name,icon,parent_page,sequence_id,is_public,is_hidden,
  content_json,metadata_json,created_at,updated_at
)
VALUES(
  'Runtime Laboratory','Runtime Laboratory','WMN System',NULL,'science',NULL,-50,1,0,'[]',
  '{"system_workspace":true,"runtime_lab":true,"required_roles":["System Manager"]}',
  datetime('now'),datetime('now')
)
ON CONFLICT(name) DO UPDATE SET
  label=excluded.label,module=excluded.module,icon=excluded.icon,sequence_id=excluded.sequence_id,
  is_hidden=0,metadata_json=excluded.metadata_json,updated_at=excluded.updated_at;

DELETE FROM [tabWorkspaceItem]
WHERE parent='Runtime Laboratory' AND parenttype='Workspace' AND parentfield='items';

INSERT INTO [tabPage](
  name,title,route,app_name,module,page_type,controller_key,roles_json,
  permissions_json,enabled,metadata_json,created_at,updated_at
)
VALUES
('Runtime Lab - Standard','Runtime Lab - Standard','/system/runtime-lab/standard',NULL,'WMN System','STANDARD',NULL,'["System Manager"]','[]',1,
 '{"show_in_navigation":false,"runtime_lab":true,"layout":[{"type":"heading","label":"Standard / Declarative Page"},{"type":"text","text":"Metadata-driven content without compiled business code."},{"type":"page","label":"Open Runtime Lab List","target":"Runtime Lab - List"}]}',datetime('now'),datetime('now')),
('Runtime Lab - Dashboard','Runtime Lab - Dashboard','/system/runtime-lab/dashboard',NULL,'WMN System','DASHBOARD',NULL,'["System Manager"]','[]',1,
 '{"show_in_navigation":false,"runtime_lab":true,"workspace":"Runtime Laboratory"}',datetime('now'),datetime('now')),
('Runtime Lab - Custom','Runtime Lab - Custom','/system/runtime-lab/custom',NULL,'WMN System','CUSTOM',NULL,'["System Manager"]','[]',1,
 '{"show_in_navigation":false,"runtime_lab":true,"layout":[{"type":"heading","label":"Custom Metadata Page"},{"type":"text","text":"CUSTOM pages can be metadata-only or use a registered native controller."}]}',datetime('now'),datetime('now')),
('Runtime Lab - List','Runtime Lab - List','/system/runtime-lab/list',NULL,'WMN System','LIST',NULL,'["System Manager"]','[]',1,
 '{"show_in_navigation":false,"runtime_lab":true,"doctype":"Page"}',datetime('now'),datetime('now')),
('Runtime Lab - Form','Runtime Lab - Form','/system/runtime-lab/form',NULL,'WMN System','FORM',NULL,'["System Manager"]','[]',1,
 '{"show_in_navigation":false,"runtime_lab":true,"doctype":"File Settings","document_name":"default"}',datetime('now'),datetime('now')),
('Runtime Lab - Report','Runtime Lab - Report','/system/runtime-lab/report',NULL,'WMN System','REPORT',NULL,'["System Manager"]','[]',1,
 '{"show_in_navigation":false,"runtime_lab":true,"report":"Example - Query Report - DocType Search"}',datetime('now'),datetime('now')),
('Runtime Lab - Workspace','Runtime Lab - Workspace','/system/runtime-lab/workspace',NULL,'WMN System','WORKSPACE',NULL,'["System Manager"]','[]',1,
 '{"show_in_navigation":false,"runtime_lab":true,"workspace":"Runtime Laboratory"}',datetime('now'),datetime('now')),
('Data Import / Export Tool','Data Import / Export','/system/tools/data-import-export',NULL,'WMN System','CUSTOM','wmn.tool.data_exchange','["System Manager"]','[]',1,
 '{"show_in_navigation":true,"section":"Tools","order":10,"runtime_category":"TOOL","runtime_lab":true}',datetime('now'),datetime('now')),
('Workspace Builder','Workspace Builder','/system/developer/workspaces',NULL,'WMN System','LIST',NULL,'["System Manager"]','[]',1,
 '{"show_in_navigation":true,"section":"Developer","order":20,"doctype":"Workspace","runtime_category":"BUILDER","workspace_builder":true}',datetime('now'),datetime('now'))
ON CONFLICT(name) DO UPDATE SET
  title=excluded.title,route=excluded.route,module=excluded.module,page_type=excluded.page_type,
  controller_key=excluded.controller_key,roles_json=excluded.roles_json,permissions_json=excluded.permissions_json,
  enabled=excluded.enabled,metadata_json=excluded.metadata_json,updated_at=excluded.updated_at;

INSERT INTO [tabWorkspaceItem](
  name,creation,modified,docstatus,idx,parent,parentfield,parenttype,region,item_type,label,
  link_type,link_to,column_span,hidden,item_json
)
VALUES
('runtime-lab-page-standard',datetime('now'),datetime('now'),0,1,'Runtime Laboratory','items','Workspace','CONTENT','shortcut','Standard Page','Page','Runtime Lab - Standard',4,0,'{}'),
('runtime-lab-page-dashboard',datetime('now'),datetime('now'),0,2,'Runtime Laboratory','items','Workspace','CONTENT','shortcut','Dashboard Page','Page','Runtime Lab - Dashboard',4,0,'{}'),
('runtime-lab-page-custom',datetime('now'),datetime('now'),0,3,'Runtime Laboratory','items','Workspace','CONTENT','shortcut','Custom Page','Page','Runtime Lab - Custom',4,0,'{}'),
('runtime-lab-page-list',datetime('now'),datetime('now'),0,4,'Runtime Laboratory','items','Workspace','CONTENT','shortcut','List Page','Page','Runtime Lab - List',4,0,'{}'),
('runtime-lab-page-form',datetime('now'),datetime('now'),0,5,'Runtime Laboratory','items','Workspace','CONTENT','shortcut','Form Page','Page','Runtime Lab - Form',4,0,'{}'),
('runtime-lab-page-report',datetime('now'),datetime('now'),0,6,'Runtime Laboratory','items','Workspace','CONTENT','shortcut','Report Page','Page','Runtime Lab - Report',4,0,'{}'),
('runtime-lab-page-workspace',datetime('now'),datetime('now'),0,7,'Runtime Laboratory','items','Workspace','CONTENT','shortcut','Workspace Page','Page','Runtime Lab - Workspace',4,0,'{}'),
('runtime-lab-data-import',datetime('now'),datetime('now'),0,8,'Runtime Laboratory','items','Workspace','CONTENT','shortcut','Data Import / Export Tool','Page','Data Import / Export Tool',4,0,'{}'),
('runtime-lab-workspace-builder',datetime('now'),datetime('now'),0,9,'Runtime Laboratory','items','Workspace','CONTENT','shortcut','Workspace Builder','Page','Workspace Builder',4,0,'{}');

-- R3.19 also repairs the protected General Report template created by the
-- historical raw SQL migration. Only the built-in protected format is touched;
-- custom report formats remain unchanged.
UPDATE print_formats
SET template_text=replace(template_text, '\n', char(10)),
    updated_at=datetime('now')
WHERE code='WMN-GENERAL-REPORT'
  AND target_type='GENERAL_REPORT'
  AND json_extract(metadata_json,'$.protected')=1
  AND instr(template_text, '\n') > 0;

UPDATE wmn_features
SET capability_ids_json='["lifecycle","doctype","metadata","create","save","sqlite","transactions","shell","i18n","system-settings","feature-registry","entitlements","feature-activation","users","roles","permissions","identity-context","permission-snapshot","user-permissions","document-sharing","page-registry","page-runtime","declarative-pages","page-controllers","field-control-resolver","workspace-builder","data-import-tool"]',
    updated_at=datetime('now')
WHERE code='core.platform';
''';
}
