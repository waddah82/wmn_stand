CREATE TABLE IF NOT EXISTS "tabApplication Build Profile"(
  id TEXT PRIMARY KEY NOT NULL,
  app_name TEXT NOT NULL,
  profile_name TEXT NOT NULL,
  build_mode TEXT NOT NULL DEFAULT 'DEVELOPMENT'
    CHECK(build_mode IN ('DEVELOPMENT','TEST','RELEASE')),
  targets_json TEXT NOT NULL DEFAULT '["all"]',
  include_assets INTEGER NOT NULL DEFAULT 1 CHECK(include_assets IN (0,1)),
  strict_validation INTEGER NOT NULL DEFAULT 1 CHECK(strict_validation IN (0,1)),
  enabled INTEGER NOT NULL DEFAULT 1 CHECK(enabled IN (0,1)),
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(app_name,profile_name),
  FOREIGN KEY(app_name) REFERENCES wmn_app_packages(app_name) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_application_build_profile_app
ON "tabApplication Build Profile"(app_name,enabled,build_mode,profile_name);

CREATE TABLE IF NOT EXISTS "tabApplication Build"(
  id TEXT PRIMARY KEY NOT NULL,
  app_name TEXT NOT NULL,
  app_version TEXT NOT NULL,
  profile_name TEXT NOT NULL,
  build_mode TEXT NOT NULL CHECK(build_mode IN ('DEVELOPMENT','TEST','RELEASE')),
  targets_json TEXT NOT NULL DEFAULT '["all"]',
  package_format TEXT NOT NULL DEFAULT 'WMNAPP',
  package_format_version INTEGER NOT NULL DEFAULT 1,
  status TEXT NOT NULL CHECK(status IN ('VALIDATING','GENERATING','READY','FAILED','IMPORTED')),
  package_hash TEXT,
  package_size INTEGER NOT NULL DEFAULT 0 CHECK(package_size >= 0),
  artifact_file_id TEXT,
  manifest_json TEXT NOT NULL DEFAULT '{}',
  summary_json TEXT NOT NULL DEFAULT '{}',
  error_text TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  completed_at TEXT,
  FOREIGN KEY(app_name) REFERENCES wmn_app_packages(app_name) ON DELETE CASCADE,
  FOREIGN KEY(artifact_file_id) REFERENCES wmn_files(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_application_build_app_created
ON "tabApplication Build"(app_name,created_at DESC,status);

INSERT INTO wmn_doctypes(
  name,module,storage_mode,table_name,id_field,title_field,autoname,
  is_single,is_child,is_submittable,track_changes,
  allow_create,allow_edit,allow_delete,allow_import,allow_export,generic_write,
  is_system,enabled,metadata_json,created_at,updated_at
)
VALUES
(
  'Application Build Profile','WMN System','TABLE','tabApplication Build Profile','id','profile_name','field:id',
  0,0,0,1,1,1,1,1,1,1,1,1,
  '{"protected":true,"application_generator":true,"runtime_owned":true}',datetime('now'),datetime('now')
),
(
  'Application Build','WMN System','TABLE','tabApplication Build','id','id','field:id',
  0,0,0,1,0,0,0,0,1,0,1,1,
  '{"protected":true,"application_generator":true,"runtime_owned":true,"read_only_log":true}',datetime('now'),datetime('now')
)
ON CONFLICT(name) DO UPDATE SET
  module=excluded.module,storage_mode='TABLE',table_name=excluded.table_name,
  id_field=excluded.id_field,title_field=excluded.title_field,autoname=excluded.autoname,
  allow_create=excluded.allow_create,allow_edit=excluded.allow_edit,
  allow_delete=excluded.allow_delete,allow_import=excluded.allow_import,
  allow_export=excluded.allow_export,generic_write=excluded.generic_write,
  is_system=1,enabled=1,metadata_json=excluded.metadata_json,updated_at=datetime('now');

INSERT INTO wmn_doctype_fields(
  id,doctype,fieldname,label,fieldtype,options,idx,reqd,read_only,hidden,
  in_list_view,in_standard_filter,searchable,allow_on_submit,default_json,
  depends_on,mandatory_depends_on,read_only_depends_on,fetch_from,precision,
  length,metadata_json,created_at,updated_at
)
VALUES
('abp-id','Application Build Profile','id','ID','Data',NULL,10,1,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,220,'{}',datetime('now'),datetime('now')),
('abp-app','Application Build Profile','app_name','Application','Link','Application',20,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('abp-name','Application Build Profile','profile_name','Profile Name','Data',NULL,30,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,120,'{}',datetime('now'),datetime('now')),
('abp-mode','Application Build Profile','build_mode','Build Mode','Select','DEVELOPMENT\nTEST\nRELEASE',40,1,0,0,1,1,0,0,'"DEVELOPMENT"',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('abp-targets','Application Build Profile','targets_json','Targets','Code','JSON',50,1,0,0,0,0,0,0,'"[\\"all\\"]"',NULL,NULL,NULL,NULL,NULL,NULL,'{"language":"JSON"}',datetime('now'),datetime('now')),
('abp-assets','Application Build Profile','include_assets','Include Assets','Check',NULL,60,0,0,0,1,0,0,0,'true',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('abp-strict','Application Build Profile','strict_validation','Strict Validation','Check',NULL,70,0,0,0,1,0,0,0,'true',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('abp-enabled','Application Build Profile','enabled','Enabled','Check',NULL,80,0,0,0,1,1,0,0,'true',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('abp-meta','Application Build Profile','metadata_json','Metadata JSON','Code','JSON',90,0,0,1,0,0,0,0,'"{}"',NULL,NULL,NULL,NULL,NULL,NULL,'{"language":"JSON"}',datetime('now'),datetime('now')),
('ab-id','Application Build','id','Build ID','Data',NULL,10,1,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,220,'{}',datetime('now'),datetime('now')),
('ab-app','Application Build','app_name','Application','Link','Application',20,1,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('ab-version','Application Build','app_version','Application Version','Data',NULL,30,1,1,0,1,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,80,'{}',datetime('now'),datetime('now')),
('ab-profile','Application Build','profile_name','Build Profile','Data',NULL,40,1,1,0,1,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,120,'{}',datetime('now'),datetime('now')),
('ab-mode','Application Build','build_mode','Build Mode','Data',NULL,50,1,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,40,'{}',datetime('now'),datetime('now')),
('ab-status','Application Build','status','Status','Data',NULL,60,1,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,40,'{}',datetime('now'),datetime('now')),
('ab-hash','Application Build','package_hash','SHA-256','Data',NULL,70,0,1,0,0,0,1,0,NULL,NULL,NULL,NULL,NULL,NULL,64,'{}',datetime('now'),datetime('now')),
('ab-size','Application Build','package_size','Package Size','Int',NULL,80,0,1,0,1,0,0,0,'0',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('ab-created','Application Build','created_at','Created At','Datetime',NULL,90,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('ab-completed','Application Build','completed_at','Completed At','Datetime',NULL,100,0,1,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('ab-summary','Application Build','summary_json','Summary','Code','JSON',110,0,1,1,0,0,0,0,'"{}"',NULL,NULL,NULL,NULL,NULL,NULL,'{"language":"JSON"}',datetime('now'),datetime('now')),
('ab-error','Application Build','error_text','Error','Small Text',NULL,120,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now'))
ON CONFLICT(doctype,fieldname) DO UPDATE SET
  label=excluded.label,fieldtype=excluded.fieldtype,options=excluded.options,
  idx=excluded.idx,reqd=excluded.reqd,read_only=excluded.read_only,
  hidden=excluded.hidden,in_list_view=excluded.in_list_view,
  in_standard_filter=excluded.in_standard_filter,searchable=excluded.searchable,
  default_json=excluded.default_json,metadata_json=excluded.metadata_json,
  updated_at=datetime('now');

INSERT OR IGNORE INTO "tabApplication Build Profile"(
  id,app_name,profile_name,build_mode,targets_json,include_assets,strict_validation,enabled,metadata_json
)
SELECT app_name || ':development',app_name,'Development','DEVELOPMENT','["all"]',1,0,1,'{"system_default":true}'
FROM wmn_app_packages WHERE source_framework='WMN';

INSERT OR IGNORE INTO "tabApplication Build Profile"(
  id,app_name,profile_name,build_mode,targets_json,include_assets,strict_validation,enabled,metadata_json
)
SELECT app_name || ':test',app_name,'Test','TEST','["all"]',1,1,1,'{"system_default":true}'
FROM wmn_app_packages WHERE source_framework='WMN';

INSERT OR IGNORE INTO "tabApplication Build Profile"(
  id,app_name,profile_name,build_mode,targets_json,include_assets,strict_validation,enabled,metadata_json
)
SELECT app_name || ':release',app_name,'Release','RELEASE','["all"]',1,1,1,'{"system_default":true}'
FROM wmn_app_packages WHERE source_framework='WMN';
