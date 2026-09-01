
ALTER TABLE print_formats ADD COLUMN target_type TEXT NOT NULL DEFAULT 'DOCUMENT'
  CHECK(target_type IN ('DOCUMENT','REPORT','GENERAL_REPORT','PLATFORM'));
ALTER TABLE print_formats ADD COLUMN document_type TEXT;
ALTER TABLE print_formats ADD COLUMN report_name TEXT;
ALTER TABLE print_formats ADD COLUMN renderer_id TEXT NOT NULL DEFAULT 'pdf';
ALTER TABLE print_formats ADD COLUMN template_text TEXT NOT NULL DEFAULT '';
ALTER TABLE print_formats ADD COLUMN css_text TEXT NOT NULL DEFAULT '';
ALTER TABLE print_formats ADD COLUMN is_default INTEGER NOT NULL DEFAULT 0 CHECK(is_default IN (0,1));
ALTER TABLE print_formats ADD COLUMN paper_width_mm REAL NOT NULL DEFAULT 210 CHECK(paper_width_mm > 0);
ALTER TABLE print_formats ADD COLUMN paper_height_mm REAL NOT NULL DEFAULT 297 CHECK(paper_height_mm > 0);
ALTER TABLE print_formats ADD COLUMN margin_mm REAL NOT NULL DEFAULT 10 CHECK(margin_mm >= 0);
ALTER TABLE print_formats ADD COLUMN metadata_json TEXT NOT NULL DEFAULT '{}';

ALTER TABLE print_settings ADD COLUMN default_document_format_id TEXT;
ALTER TABLE print_settings ADD COLUMN general_report_format_id TEXT;
ALTER TABLE print_settings ADD COLUMN default_printer_id TEXT;
ALTER TABLE print_settings ADD COLUMN preview_renderer_id TEXT NOT NULL DEFAULT 'html';
ALTER TABLE print_settings ADD COLUMN pdf_renderer_id TEXT NOT NULL DEFAULT 'pdf';
ALTER TABLE print_settings ADD COLUMN metadata_json TEXT NOT NULL DEFAULT '{}';

ALTER TABLE print_jobs ADD COLUMN source_type TEXT NOT NULL DEFAULT 'DOCUMENT'
  CHECK(source_type IN ('DOCUMENT','REPORT'));
ALTER TABLE print_jobs ADD COLUMN print_format_id TEXT;
ALTER TABLE print_jobs ADD COLUMN printer_id TEXT;
ALTER TABLE print_jobs ADD COLUMN renderer_id TEXT;
ALTER TABLE print_jobs ADD COLUMN output_file_id TEXT;
ALTER TABLE print_jobs ADD COLUMN mime_type TEXT;
ALTER TABLE print_jobs ADD COLUMN byte_count INTEGER NOT NULL DEFAULT 0 CHECK(byte_count >= 0);
ALTER TABLE print_jobs ADD COLUMN request_json TEXT NOT NULL DEFAULT '{}';

CREATE INDEX IF NOT EXISTS idx_print_formats_target
ON print_formats(enabled,target_type,document_type,report_name,is_default);
CREATE INDEX IF NOT EXISTS idx_print_jobs_format
ON print_jobs(print_format_id,created_at DESC);
CREATE INDEX IF NOT EXISTS idx_print_jobs_output
ON print_jobs(output_file_id);

INSERT INTO wmn_features(
  id,code,label,description,capability_ids_json,price_amount,currency,billing_period,
  plan_code,is_core,user_toggleable,enabled,metadata_json,created_at,updated_at
)
VALUES(
  'feature-advanced-printing','printing.advanced','Advanced Printing',
  'ESC/POS, raw printer transports, barcode/QR and native printer adapters.',
  '["escpos","raw-printing","barcode","qr","network-printing","usb-printing","bluetooth-printing"]',
  0,'USD','ONE_TIME','ADVANCED_PRINTING',0,1,1,
  '{"price_configurable":true,"native_adapter_feature":true}',datetime('now'),datetime('now')
)
ON CONFLICT(code) DO UPDATE SET
  label=excluded.label,description=excluded.description,
  capability_ids_json=excluded.capability_ids_json,plan_code=excluded.plan_code,
  user_toggleable=1,enabled=1,metadata_json=excluded.metadata_json,updated_at=datetime('now');

INSERT OR IGNORE INTO wmn_feature_entitlements(id,feature_id,status,source,updated_at)
VALUES('entitlement-feature-advanced-printing','feature-advanced-printing','GRANTED','LOCAL',datetime('now'));
INSERT OR IGNORE INTO wmn_feature_activations(feature_id,scope_type,scope_key,enabled,updated_at)
VALUES('feature-advanced-printing','INSTALLATION','local',1,datetime('now'));

CREATE TRIGGER IF NOT EXISTS trg_print_formats_validate_insert
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

CREATE TRIGGER IF NOT EXISTS trg_print_formats_validate_update
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

INSERT INTO wmn_doctypes(
  name,module,storage_mode,table_name,id_field,title_field,autoname,
  is_single,is_child,is_submittable,track_changes,allow_create,allow_edit,
  allow_delete,allow_import,allow_export,generic_write,is_system,enabled,
  metadata_json,created_at,updated_at
)
VALUES(
  'Print Job','WMN System','TABLE','print_jobs','id','document_name',NULL,
  0,0,0,0,0,0,0,0,1,0,1,1,
  '{"runtime_owned":true,"read_only":true,"printing_engine":true}',
  datetime('now'),datetime('now')
)
ON CONFLICT(name) DO UPDATE SET
  module=excluded.module,storage_mode=excluded.storage_mode,table_name=excluded.table_name,
  id_field=excluded.id_field,title_field=excluded.title_field,allow_create=0,allow_edit=0,
  allow_delete=0,generic_write=0,is_system=1,enabled=1,
  metadata_json=excluded.metadata_json,updated_at=excluded.updated_at;

UPDATE wmn_doctypes
SET metadata_json='{"printing_engine":true,"template_tokens":true,"renderer_registry":true}',updated_at=datetime('now')
WHERE name='Print Format';
UPDATE wmn_doctypes
SET metadata_json='{"printing_engine":true,"runtime_defaults":true}',updated_at=datetime('now')
WHERE name='Print Settings';
UPDATE wmn_doctypes
SET metadata_json='{"printing_engine":true,"native_adapter_target":true}',updated_at=datetime('now')
WHERE name='Printer';
UPDATE wmn_doctypes
SET metadata_json='{"printing_output":true,"attachment_runtime":true}',updated_at=datetime('now')
WHERE name='File';

INSERT INTO wmn_doctype_fields(
  id,doctype,fieldname,label,fieldtype,options,idx,reqd,read_only,hidden,
  in_list_view,in_standard_filter,searchable,allow_on_submit,default_json,
  depends_on,mandatory_depends_on,read_only_depends_on,fetch_from,precision,
  length,metadata_json,created_at,updated_at
)
VALUES
('pf-id','Print Format','id','ID','Data',NULL,10,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('pf-code','Print Format','code','Code','Data',NULL,20,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,120,'{}',datetime('now'),datetime('now')),
('pf-name','Print Format','name','Print Format Name','Data',NULL,30,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('pf-target','Print Format','target_type','Target Type','Select','DOCUMENT\nREPORT\nGENERAL_REPORT\nPLATFORM',40,1,0,0,1,1,1,0,'"DOCUMENT"',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('pf-doctype','Print Format','document_type','DocType','Link','DocType',50,0,0,0,1,1,1,0,NULL,"eval:doc.target_type=='DOCUMENT'",NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('pf-report','Print Format','report_name','Report','Link','Report',60,0,0,0,1,1,1,0,NULL,"eval:doc.target_type=='REPORT'",NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('pf-renderer','Print Format','renderer_id','Renderer','Select','pdf\nhtml\nescpos',70,1,0,0,1,1,1,0,'"pdf"',NULL,NULL,NULL,NULL,NULL,NULL,'{"registry_backed":true}',datetime('now'),datetime('now')),
('pf-template','Print Format','template_text','Template','Code',NULL,80,1,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{"language":"WMN Print Template","token_help":true}',datetime('now'),datetime('now')),
('pf-css','Print Format','css_text','CSS','Code',NULL,90,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{"optional":true,"renderer":"html"}',datetime('now'),datetime('now')),
('pf-default','Print Format','is_default','Default','Check',NULL,100,0,0,0,1,1,0,0,'false',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('pf-paper-width','Print Format','paper_width_mm','Paper Width (mm)','Float',NULL,110,1,0,0,0,0,0,0,'210',NULL,NULL,NULL,NULL,2,NULL,'{}',datetime('now'),datetime('now')),
('pf-paper-height','Print Format','paper_height_mm','Paper Height (mm)','Float',NULL,120,1,0,0,0,0,0,0,'297',NULL,NULL,NULL,NULL,2,NULL,'{}',datetime('now'),datetime('now')),
('pf-margin','Print Format','margin_mm','Margin (mm)','Float',NULL,130,1,0,0,0,0,0,0,'10',NULL,NULL,NULL,NULL,2,NULL,'{}',datetime('now'),datetime('now')),
('pf-enabled','Print Format','enabled','Enabled','Check',NULL,140,0,0,0,1,1,0,0,'true',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('pf-metadata','Print Format','metadata_json','Metadata JSON','Code',NULL,150,0,0,1,0,0,0,0,'"{}"',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now'))
ON CONFLICT(doctype,fieldname) DO UPDATE SET
  label=excluded.label,fieldtype=excluded.fieldtype,options=excluded.options,idx=excluded.idx,
  reqd=excluded.reqd,read_only=excluded.read_only,hidden=excluded.hidden,
  in_list_view=excluded.in_list_view,in_standard_filter=excluded.in_standard_filter,
  searchable=excluded.searchable,default_json=excluded.default_json,
  depends_on=excluded.depends_on,metadata_json=excluded.metadata_json,updated_at=excluded.updated_at;

INSERT INTO wmn_doctype_fields(
  id,doctype,fieldname,label,fieldtype,options,idx,reqd,read_only,hidden,
  in_list_view,in_standard_filter,searchable,allow_on_submit,default_json,
  depends_on,mandatory_depends_on,read_only_depends_on,fetch_from,precision,
  length,metadata_json,created_at,updated_at
)
VALUES
('ps-id','Print Settings','id','ID','Data',NULL,10,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('ps-name','Print Settings','name','Settings Name','Data',NULL,20,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('ps-default-format','Print Settings','default_document_format_id','Default Document Format','Link','Print Format',30,0,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('ps-general-report','Print Settings','general_report_format_id','General Report Format','Link','Print Format',40,0,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('ps-printer','Print Settings','default_printer_id','Default Printer','Link','Printer',50,0,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('ps-preview','Print Settings','preview_renderer_id','Preview Renderer','Select','html\npdf',60,1,0,0,0,1,0,0,'"html"',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('ps-pdf','Print Settings','pdf_renderer_id','PDF Renderer','Select','pdf',70,1,0,0,0,1,0,0,'"pdf"',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('ps-paper','Print Settings','paper_width_mm','ESC/POS Paper Width (mm)','Int',NULL,80,1,0,0,0,0,0,0,'80',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('ps-autoprint','Print Settings','auto_print','Auto Print','Check',NULL,90,0,0,0,0,0,0,0,'false',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('ps-cut','Print Settings','cut_paper','Cut Paper','Check',NULL,100,0,0,0,0,0,0,0,'false',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('ps-enabled','Print Settings','enabled','Enabled','Check',NULL,110,0,0,0,1,1,0,0,'true',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('ps-metadata','Print Settings','metadata_json','Metadata JSON','Code',NULL,120,0,0,1,0,0,0,0,'"{}"',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now'))
ON CONFLICT(doctype,fieldname) DO UPDATE SET
  label=excluded.label,fieldtype=excluded.fieldtype,options=excluded.options,idx=excluded.idx,
  reqd=excluded.reqd,read_only=excluded.read_only,hidden=excluded.hidden,
  in_list_view=excluded.in_list_view,in_standard_filter=excluded.in_standard_filter,
  searchable=excluded.searchable,default_json=excluded.default_json,metadata_json=excluded.metadata_json,
  updated_at=excluded.updated_at;

INSERT INTO wmn_doctype_fields(
  id,doctype,fieldname,label,fieldtype,options,idx,reqd,read_only,hidden,
  in_list_view,in_standard_filter,searchable,allow_on_submit,default_json,
  depends_on,mandatory_depends_on,read_only_depends_on,fetch_from,precision,
  length,metadata_json,created_at,updated_at
)
VALUES
('pr-id','Printer','id','ID','Data',NULL,10,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('pr-name','Printer','name','Printer Name','Data',NULL,20,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('pr-connection','Printer','connection_type','Adapter','Select','SYSTEM\nWINDOWS_RAW\nNETWORK\nSERIAL\nUSB\nBLUETOOTH\nWEB',30,1,0,0,1,1,1,0,'"SYSTEM"',NULL,NULL,NULL,NULL,NULL,NULL,'{"native_adapter":true}',datetime('now'),datetime('now')),
('pr-target','Printer','target','Target','Data',NULL,40,0,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,260,'{}',datetime('now'),datetime('now')),
('pr-platform','Printer','platform','Platform','Select','ANY\nWINDOWS\nANDROID\nIOS\nWEB\nSERVER',50,1,0,0,1,1,1,0,'"ANY"',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('pr-capabilities','Printer','capabilities_json','Capabilities JSON','Code',NULL,60,0,0,1,0,0,0,0,'"[]"',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('pr-enabled','Printer','enabled','Enabled','Check',NULL,70,0,0,0,1,1,0,0,'true',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('pr-metadata','Printer','metadata_json','Adapter Metadata JSON','Code',NULL,80,0,0,0,0,0,0,0,'"{}"',NULL,NULL,NULL,NULL,NULL,NULL,'{"adapter_config":true}',datetime('now'),datetime('now'))
ON CONFLICT(doctype,fieldname) DO UPDATE SET
  label=excluded.label,fieldtype=excluded.fieldtype,options=excluded.options,idx=excluded.idx,
  reqd=excluded.reqd,read_only=excluded.read_only,hidden=excluded.hidden,
  in_list_view=excluded.in_list_view,in_standard_filter=excluded.in_standard_filter,
  searchable=excluded.searchable,default_json=excluded.default_json,metadata_json=excluded.metadata_json,
  updated_at=excluded.updated_at;

INSERT INTO wmn_doctype_fields(
  id,doctype,fieldname,label,fieldtype,options,idx,reqd,read_only,hidden,
  in_list_view,in_standard_filter,searchable,allow_on_submit,default_json,
  depends_on,mandatory_depends_on,read_only_depends_on,fetch_from,precision,
  length,metadata_json,created_at,updated_at
)
VALUES
('pj-id','Print Job','id','Job ID','Data',NULL,10,0,1,0,1,0,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('pj-source','Print Job','source_type','Source','Data',NULL,20,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,40,'{}',datetime('now'),datetime('now')),
('pj-doctype','Print Job','document_type','DocType / Report','Data',NULL,30,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('pj-docname','Print Job','document_name','Document / Execution','Data',NULL,40,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('pj-format','Print Job','print_format_id','Print Format','Link','Print Format',50,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('pj-printer','Print Job','printer_id','Printer','Link','Printer',60,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('pj-renderer','Print Job','renderer_id','Renderer','Data',NULL,70,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,80,'{}',datetime('now'),datetime('now')),
('pj-status','Print Job','status','Status','Data',NULL,80,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,40,'{}',datetime('now'),datetime('now')),
('pj-output','Print Job','output_file_id','Output File','Link','File',90,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('pj-mime','Print Job','mime_type','MIME Type','Data',NULL,100,0,1,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,120,'{}',datetime('now'),datetime('now')),
('pj-bytes','Print Job','byte_count','Bytes','Int',NULL,110,0,1,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('pj-error','Print Job','error_message','Error','Small Text',NULL,120,0,1,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('pj-created','Print Job','created_at','Created At','Datetime',NULL,130,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('pj-completed','Print Job','completed_at','Completed At','Datetime',NULL,140,0,1,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now'))
ON CONFLICT(doctype,fieldname) DO UPDATE SET
  label=excluded.label,fieldtype=excluded.fieldtype,options=excluded.options,idx=excluded.idx,
  reqd=excluded.reqd,read_only=1,hidden=excluded.hidden,
  in_list_view=excluded.in_list_view,in_standard_filter=excluded.in_standard_filter,
  searchable=excluded.searchable,updated_at=excluded.updated_at;

INSERT INTO wmn_doctype_permissions(
  id,doctype,role,permlevel,can_read,can_write,can_create,can_delete,
  can_submit,can_cancel,can_amend,can_report,can_import,can_export,
  can_share,can_print,can_email,if_owner,metadata_json
)
SELECT 'docperm-' || lower(replace(doctype,' ','-')) || '-system-manager',doctype,'System Manager',0,
       1,CASE WHEN doctype='Print Job' THEN 0 ELSE 1 END,
       CASE WHEN doctype='Print Job' THEN 0 ELSE 1 END,
       CASE WHEN doctype='Print Job' THEN 0 ELSE 1 END,
       0,0,0,1,0,1,0,0,0,0,'{"platform_default":true,"printing_engine":true}'
FROM (SELECT 'Print Format' AS doctype UNION ALL SELECT 'Print Settings' UNION ALL SELECT 'Printer' UNION ALL SELECT 'Print Job')
WHERE 1=1
ON CONFLICT(doctype,role,permlevel) DO UPDATE SET
  can_read=1,can_write=excluded.can_write,can_create=excluded.can_create,can_delete=excluded.can_delete,
  can_report=1,can_export=1,metadata_json=excluded.metadata_json;

INSERT INTO print_formats(
  id,code,name,format_type,template_json,enabled,created_at,updated_at,
  target_type,document_type,report_name,renderer_id,template_text,css_text,
  is_default,paper_width_mm,paper_height_mm,margin_mm,metadata_json
)
VALUES
('print-format-platform-default','WMN-PLATFORM-DEFAULT','WMN Platform Default','PLATFORM','{}',1,datetime('now'),datetime('now'),
 'PLATFORM',NULL,NULL,'pdf','{{ document }}','',1,210,297,10,'{"protected":true,"fallback":true}'),
('print-format-general-report','WMN-GENERAL-REPORT','General Report Print Format','REPORT','{}',1,datetime('now'),datetime('now'),
 'GENERAL_REPORT',NULL,NULL,'pdf','{{ report.title }}\n\n{{#each report.rows}}{{#each this}}{{ key }}: {{ value }}   {{/each}}\n{{/each}}','',1,210,297,10,'{"protected":true,"general_report":true}')
ON CONFLICT(code) DO UPDATE SET
  name=excluded.name,target_type=excluded.target_type,renderer_id=excluded.renderer_id,
  template_text=CASE WHEN trim(print_formats.template_text)='' THEN excluded.template_text ELSE print_formats.template_text END,
  is_default=1,enabled=1,metadata_json=excluded.metadata_json,updated_at=datetime('now');

INSERT INTO print_settings(
  id,name,print_format_id,connection_type,network_port,serial_baud,paper_width_mm,
  auto_print,cut_paper,enabled,system_print_mode,updated_at,
  default_document_format_id,general_report_format_id,preview_renderer_id,pdf_renderer_id,metadata_json
)
VALUES(
  'print-settings-default','Default',NULL,'PREVIEW',9100,9600,80,
  0,0,1,'DOCUMENT',datetime('now'),
  'print-format-platform-default','print-format-general-report','html','pdf','{"platform_default":true}'
)
ON CONFLICT(name) DO UPDATE SET
  default_document_format_id=COALESCE(print_settings.default_document_format_id,excluded.default_document_format_id),
  general_report_format_id=COALESCE(print_settings.general_report_format_id,excluded.general_report_format_id),
  preview_renderer_id=excluded.preview_renderer_id,pdf_renderer_id=excluded.pdf_renderer_id,
  enabled=1,updated_at=datetime('now');
