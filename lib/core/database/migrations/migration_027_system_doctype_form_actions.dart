import 'database_migration.dart';

/// R3.15.5 System DocType completeness fixes.
///
/// Makes DocType itself addressable through the generic metadata runtime so
/// Link fields with Options = DocType use the normal Link lookup path. It also
/// gives Role explicit editable field metadata instead of relying on partial
/// physical-table inference.
class Migration027SystemDocTypeFormActions extends SqlDatabaseMigration {
  const Migration027SystemDocTypeFormActions();

  @override
  int get version => 27;

  @override
  String get name => 'system_doctype_form_actions';

  @override
  String get sql => r'''
INSERT INTO wmn_doctypes(
  name,module,storage_mode,table_name,id_field,title_field,autoname,
  is_single,is_child,is_submittable,track_changes,allow_create,allow_edit,
  allow_delete,allow_import,allow_export,generic_write,is_system,enabled,
  metadata_json,created_at,updated_at
)
VALUES(
  'DocType','WMN System','TABLE','wmn_doctypes','name','name',NULL,
  0,0,0,1,0,0,0,0,1,0,1,1,
  '{"runtime_owned":true,"metadata_registry":true,"link_target":true}',
  datetime('now'),datetime('now')
)
ON CONFLICT(name) DO UPDATE SET
  module=excluded.module,storage_mode=excluded.storage_mode,
  table_name=excluded.table_name,id_field=excluded.id_field,
  title_field=excluded.title_field,allow_create=0,allow_edit=0,
  allow_delete=0,generic_write=0,is_system=1,enabled=1,
  metadata_json=excluded.metadata_json,updated_at=excluded.updated_at;

INSERT INTO wmn_doctype_permissions(
  id,doctype,role,permlevel,can_read,can_write,can_create,can_delete,
  can_submit,can_cancel,can_amend,can_report,can_import,can_export,
  can_share,can_print,can_email,if_owner,metadata_json
)
VALUES(
  'docperm-doctype-system-manager','DocType','System Manager',0,
  1,0,0,0,0,0,0,1,0,1,0,0,0,0,
  '{"platform_default":true,"metadata_registry":true}'
)
ON CONFLICT(doctype,role,permlevel) DO UPDATE SET
  can_read=1,can_write=0,can_create=0,can_delete=0,
  can_report=1,can_export=1,metadata_json=excluded.metadata_json;

INSERT INTO wmn_doctype_fields(
  id,doctype,fieldname,label,fieldtype,options,idx,reqd,read_only,hidden,
  in_list_view,in_standard_filter,searchable,allow_on_submit,default_json,
  depends_on,mandatory_depends_on,read_only_depends_on,fetch_from,precision,
  length,metadata_json,created_at,updated_at
)
VALUES
('doctype-field-name','DocType','name','DocType','Data',NULL,10,1,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('doctype-field-module','DocType','module','Module','Data',NULL,20,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('doctype-field-storage','DocType','storage_mode','Storage Mode','Data',NULL,30,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,80,'{}',datetime('now'),datetime('now')),
('doctype-field-table','DocType','table_name','Table Name','Data',NULL,40,0,1,0,1,0,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('doctype-field-system','DocType','is_system','System DocType','Check',NULL,50,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('doctype-field-child','DocType','is_child','Child DocType','Check',NULL,60,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('doctype-field-enabled','DocType','enabled','Enabled','Check',NULL,70,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now'))
ON CONFLICT(doctype,fieldname) DO UPDATE SET
  label=excluded.label,fieldtype=excluded.fieldtype,options=excluded.options,
  idx=excluded.idx,reqd=excluded.reqd,read_only=excluded.read_only,
  hidden=excluded.hidden,in_list_view=excluded.in_list_view,
  in_standard_filter=excluded.in_standard_filter,searchable=excluded.searchable,
  updated_at=excluded.updated_at;

INSERT INTO wmn_doctype_fields(
  id,doctype,fieldname,label,fieldtype,options,idx,reqd,read_only,hidden,
  in_list_view,in_standard_filter,searchable,allow_on_submit,default_json,
  depends_on,mandatory_depends_on,read_only_depends_on,fetch_from,precision,
  length,metadata_json,created_at,updated_at
)
VALUES
('role-field-id','Role','id','ID','Data',NULL,10,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('role-field-code','Role','code','Code','Data',NULL,20,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,120,'{}',datetime('now'),datetime('now')),
('role-field-name','Role','name','Role Name','Data',NULL,30,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('role-field-system','Role','is_system','System Role','Check',NULL,40,0,1,0,1,1,0,0,'false',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('role-field-enabled','Role','enabled','Enabled','Check',NULL,50,0,0,0,1,1,0,0,'true',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('role-field-created','Role','created_at','Created At','Datetime',NULL,60,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('role-field-updated','Role','updated_at','Updated At','Datetime',NULL,70,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now'))
ON CONFLICT(doctype,fieldname) DO UPDATE SET
  label=excluded.label,fieldtype=excluded.fieldtype,options=excluded.options,
  idx=excluded.idx,reqd=excluded.reqd,read_only=excluded.read_only,
  hidden=excluded.hidden,in_list_view=excluded.in_list_view,
  in_standard_filter=excluded.in_standard_filter,searchable=excluded.searchable,
  default_json=excluded.default_json,updated_at=excluded.updated_at;
''';
}
