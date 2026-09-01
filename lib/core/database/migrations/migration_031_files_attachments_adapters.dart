import 'database_migration.dart';

/// R3.17 Files & Attachments adapters.
///
/// File remains a runtime-owned System DocType. Binary content may be copied
/// into WmnStorageService or kept as an external reference. User-selected file
/// dialogs and external-reference access remain platform adapter concerns.
class Migration031FilesAttachmentsAdapters extends SqlDatabaseMigration {
  const Migration031FilesAttachmentsAdapters();

  @override
  int get version => 31;

  @override
  String get name => 'files_attachments_adapters';

  @override
  String get sql => r'''
ALTER TABLE wmn_files ADD COLUMN mime_type TEXT;
ALTER TABLE wmn_files ADD COLUMN source_adapter TEXT;
ALTER TABLE wmn_files ADD COLUMN storage_adapter TEXT;
ALTER TABLE wmn_files ADD COLUMN content_mode TEXT NOT NULL DEFAULT 'MANAGED_STORAGE'
  CHECK(content_mode IN ('MANAGED_STORAGE','EXTERNAL_REFERENCE'));
ALTER TABLE wmn_files ADD COLUMN source_reference TEXT;
ALTER TABLE wmn_files ADD COLUMN state TEXT NOT NULL DEFAULT 'AVAILABLE'
  CHECK(state IN ('AVAILABLE','MISSING','CORRUPT'));

CREATE INDEX IF NOT EXISTS idx_wmn_files_hash
ON wmn_files(content_hash,file_size);
CREATE INDEX IF NOT EXISTS idx_wmn_files_state
ON wmn_files(state,creation DESC);
CREATE INDEX IF NOT EXISTS idx_wmn_files_attachment_field
ON wmn_files(attached_to_doctype,attached_to_name,attached_to_field,creation DESC);

CREATE TABLE IF NOT EXISTS file_settings (
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

INSERT INTO file_settings(
  id,name,default_content_mode,allow_external_reference,metadata_json,created_at,updated_at
) VALUES(
  'default','Default','MANAGED_STORAGE',1,
  '{"storage_optional":true,"external_reference_platform_gated":true}',
  datetime('now'),datetime('now')
)
ON CONFLICT(id) DO NOTHING;

INSERT INTO wmn_doctypes(
  name,module,storage_mode,table_name,id_field,title_field,autoname,
  is_single,is_child,is_submittable,track_changes,allow_create,allow_edit,
  allow_delete,allow_import,allow_export,generic_write,is_system,enabled,
  metadata_json,created_at,updated_at
) VALUES(
  'File Settings','WMN System','TABLE','file_settings','id','name',NULL,
  0,0,0,1,0,1,0,0,1,1,1,1,
  '{"file_runtime":true,"storage_optional":true,"single_managed_record":true}',
  datetime('now'),datetime('now')
)
ON CONFLICT(name) DO UPDATE SET
  module=excluded.module,storage_mode=excluded.storage_mode,table_name=excluded.table_name,
  id_field=excluded.id_field,title_field=excluded.title_field,allow_create=0,allow_edit=1,
  allow_delete=0,allow_import=0,allow_export=1,generic_write=1,is_system=1,enabled=1,
  metadata_json=excluded.metadata_json,updated_at=excluded.updated_at;

UPDATE wmn_doctypes
SET allow_create=0,allow_edit=0,allow_delete=0,generic_write=0,allow_export=1,
    metadata_json='{"runtime_owned":true,"attachment_runtime":true,"storage_optional":true,"external_reference":true,"storage_adapter":true,"file_dialog_adapter":true,"integrity_state":true}',
    updated_at=datetime('now')
WHERE name='File';

INSERT INTO wmn_doctype_fields(
  id,doctype,fieldname,label,fieldtype,options,idx,reqd,read_only,hidden,
  in_list_view,in_standard_filter,searchable,allow_on_submit,default_json,
  depends_on,mandatory_depends_on,read_only_depends_on,fetch_from,precision,
  length,metadata_json,created_at,updated_at
)
VALUES
('file-id','File','id','File ID','Data',NULL,10,0,1,0,1,0,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('file-name','File','file_name','File Name','Data',NULL,20,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,260,'{}',datetime('now'),datetime('now')),
('file-mime','File','mime_type','MIME Type','Data',NULL,30,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,160,'{}',datetime('now'),datetime('now')),
('file-size','File','file_size','Size (Bytes)','Int',NULL,40,0,1,0,1,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('file-private','File','is_private','Private','Check',NULL,50,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('file-state','File','state','State','Select','AVAILABLE\nMISSING\nCORRUPT',60,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{"runtime_managed":true}',datetime('now'),datetime('now')),
('file-doctype','File','attached_to_doctype','Attached To DocType','Link','DocType',70,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('file-docname','File','attached_to_name','Attached To Name','Data',NULL,80,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('file-field','File','attached_to_field','Attached To Field','Data',NULL,90,0,1,0,0,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('file-source-adapter','File','source_adapter','Source Adapter','Data',NULL,100,0,1,0,0,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,120,'{}',datetime('now'),datetime('now')),
('file-content-mode','File','content_mode','Content Mode','Select','MANAGED_STORAGE\nEXTERNAL_REFERENCE',110,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{"runtime_managed":true}',datetime('now'),datetime('now')),
('file-source-reference','File','source_reference','External Reference','Data',NULL,120,0,1,0,0,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,500,'{"external_reference":true}',datetime('now'),datetime('now')),
('file-storage-adapter','File','storage_adapter','Storage Adapter','Data',NULL,130,0,1,0,0,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,120,'{}',datetime('now'),datetime('now')),
('file-storage-path','File','storage_path','Storage Key','Data',NULL,140,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,320,'{}',datetime('now'),datetime('now')),
('file-url','File','file_url','File URL','Data',NULL,150,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,320,'{}',datetime('now'),datetime('now')),
('file-hash','File','content_hash','SHA-256','Data',NULL,160,0,1,1,0,0,1,0,NULL,NULL,NULL,NULL,NULL,NULL,64,'{}',datetime('now'),datetime('now')),
('file-owner','File','owner','Owner','Data',NULL,170,0,1,0,0,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('file-created','File','creation','Created At','Datetime',NULL,180,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('file-modified','File','modified','Modified At','Datetime',NULL,190,0,1,0,0,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('file-metadata','File','metadata_json','Metadata JSON','Code',NULL,200,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now'))
ON CONFLICT(doctype,fieldname) DO UPDATE SET
  label=excluded.label,fieldtype=excluded.fieldtype,options=excluded.options,idx=excluded.idx,
  reqd=excluded.reqd,read_only=1,hidden=excluded.hidden,
  in_list_view=excluded.in_list_view,in_standard_filter=excluded.in_standard_filter,
  searchable=excluded.searchable,metadata_json=excluded.metadata_json,updated_at=excluded.updated_at;


INSERT INTO wmn_doctype_fields(
  id,doctype,fieldname,label,fieldtype,options,idx,reqd,read_only,hidden,
  in_list_view,in_standard_filter,searchable,allow_on_submit,default_json,
  depends_on,mandatory_depends_on,read_only_depends_on,fetch_from,precision,
  length,metadata_json,created_at,updated_at
) VALUES
('fs-id','File Settings','id','ID','Data',NULL,10,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,80,'{}',datetime('now'),datetime('now')),
('fs-name','File Settings','name','Settings Name','Data',NULL,20,1,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,120,'{}',datetime('now'),datetime('now')),
('fs-mode','File Settings','default_content_mode','Default Content Mode','Select','MANAGED_STORAGE\nEXTERNAL_REFERENCE',30,1,0,0,1,1,1,0,'"MANAGED_STORAGE"',NULL,NULL,NULL,NULL,NULL,NULL,'{"storage_optional":true}',datetime('now'),datetime('now')),
('fs-external','File Settings','allow_external_reference','Allow External Reference','Check',NULL,40,0,0,0,1,1,0,0,'true',NULL,NULL,NULL,NULL,NULL,NULL,'{"platform_gated":true}',datetime('now'),datetime('now')),
('fs-metadata','File Settings','metadata_json','Metadata JSON','Code',NULL,50,0,0,1,0,0,0,0,'"{}"',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('fs-created','File Settings','created_at','Created At','Datetime',NULL,60,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('fs-updated','File Settings','updated_at','Updated At','Datetime',NULL,70,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now'))
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
) VALUES(
  'docperm-file-settings-system-manager','File Settings','System Manager',0,
  1,1,0,0,0,0,0,1,0,1,0,0,0,0,
  '{"platform_default":true,"files_attachments":true}'
)
ON CONFLICT(doctype,role,permlevel) DO UPDATE SET
  can_read=1,can_write=1,can_create=0,can_delete=0,
  can_report=1,can_export=1,metadata_json=excluded.metadata_json;

''';
}
