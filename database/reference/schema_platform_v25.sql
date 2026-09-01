-- WMN Platform schema v25 delta: Native Workflow & Approval Runtime

INSERT INTO wmn_features(
  id,code,label,description,capability_ids_json,price_amount,currency,
  billing_period,plan_code,is_core,user_toggleable,enabled,metadata_json,
  created_at,updated_at
)
VALUES(
  'feature-workflow-approvals','workflow.approvals','Workflow & Approvals',
  'Role-based states, transitions, approval chains and workflow history.',
  '["workflow-runtime","workflow-approvals","workflow-conditions","workflow-history"]',
  0,'USD','ONE_TIME',NULL,0,1,1,'{"platform_runtime":true}',datetime('now'),datetime('now')
)
ON CONFLICT(id) DO UPDATE SET
  code=excluded.code,label=excluded.label,description=excluded.description,
  capability_ids_json=excluded.capability_ids_json,enabled=1,
  metadata_json=excluded.metadata_json,updated_at=excluded.updated_at;

INSERT OR IGNORE INTO wmn_feature_entitlements(
  id,feature_id,status,source,updated_at
)
VALUES(
  'entitlement-feature-workflow-approvals','feature-workflow-approvals',
  'GRANTED','LOCAL',datetime('now')
);

INSERT OR IGNORE INTO wmn_feature_activations(
  feature_id,scope_type,scope_key,enabled,updated_at
)
VALUES(
  'feature-workflow-approvals','INSTALLATION','local',1,datetime('now')
);

INSERT OR IGNORE INTO wmn_modules(
  name,label,app_name,icon,color,sequence_id,enabled,metadata_json,created_at,updated_at
)
VALUES(
  'Workflow','Workflow & Approvals',NULL,'account_tree',NULL,30,1,
  '{"source_framework":"WMN","system_capability":true,"required_feature":"workflow.approvals"}',
  datetime('now'),datetime('now')
);

INSERT INTO permissions(id,code,module,resource,action,description,created_at)
VALUES(
  'wmn-permission-workflow-manage','wmn.workflow.manage','Workflow',
  'workflow','manage','Manage WMN workflows and approval metadata',datetime('now')
)
ON CONFLICT(code) DO NOTHING;

INSERT INTO wmn_doctypes(
  name,module,storage_mode,table_name,id_field,title_field,autoname,
  is_single,is_child,is_submittable,track_changes,allow_create,allow_edit,
  allow_delete,allow_import,allow_export,generic_write,is_system,enabled,
  metadata_json,created_at,updated_at
)
VALUES
('Workflow','Workflow','TABLE','wmn_workflows','id','name','field:name',0,0,0,1,1,1,1,1,1,1,1,1,'{"runtime":"WMN_WORKFLOW_RUNTIME","required_feature":"workflow.approvals"}',datetime('now'),datetime('now')),
('Workflow State','Workflow','TABLE','wmn_workflow_states','id','state_name','format:WFS-.#####',0,0,0,1,1,1,1,1,1,1,1,1,'{"runtime":"WMN_WORKFLOW_RUNTIME","required_feature":"workflow.approvals"}',datetime('now'),datetime('now')),
('Workflow Transition','Workflow','TABLE','wmn_workflow_transitions','id','action','format:WFT-.#####',0,0,0,1,1,1,1,1,1,1,1,1,'{"runtime":"WMN_WORKFLOW_RUNTIME","required_feature":"workflow.approvals"}',datetime('now'),datetime('now')),
('Workflow Action','Workflow','TABLE','wmn_workflow_actions','id','action',NULL,0,0,0,0,0,0,0,0,1,0,1,1,'{"runtime":"WMN_WORKFLOW_RUNTIME","required_feature":"workflow.approvals","read_only":true}',datetime('now'),datetime('now'))
ON CONFLICT(name) DO UPDATE SET
  module=excluded.module,storage_mode=excluded.storage_mode,
  table_name=excluded.table_name,id_field=excluded.id_field,
  title_field=excluded.title_field,generic_write=excluded.generic_write,
  is_system=1,enabled=1,metadata_json=excluded.metadata_json,
  updated_at=excluded.updated_at;

INSERT INTO wmn_doctype_fields(
  id,doctype,fieldname,label,fieldtype,options,idx,reqd,read_only,hidden,
  in_list_view,in_standard_filter,searchable,allow_on_submit,default_json,
  depends_on,mandatory_depends_on,read_only_depends_on,fetch_from,precision,
  length,metadata_json,created_at,updated_at
)
VALUES
('workflow-id','Workflow','id','ID','Data',NULL,10,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,140,'{}',datetime('now'),datetime('now')),
('workflow-name','Workflow','name','Workflow Name','Data',NULL,20,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,200,'{}',datetime('now'),datetime('now')),
('workflow-doctype','Workflow','doctype','Document Type','Data',NULL,30,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('workflow-state-field','Workflow','state_field','State Field','Data',NULL,40,1,0,0,1,0,1,0,'"workflow_state"',NULL,NULL,NULL,NULL,NULL,140,'{}',datetime('now'),datetime('now')),
('workflow-enabled','Workflow','enabled','Enabled','Check',NULL,50,0,0,0,1,1,0,0,'true',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('workflow-send-email','Workflow','send_email','Send Email','Check',NULL,60,0,0,0,0,0,0,0,'false',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('workflow-metadata','Workflow','metadata_json','Metadata','JSON',NULL,70,0,0,0,0,0,0,0,'{}',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),

('workflow-state-id','Workflow State','id','ID','Data',NULL,10,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,140,'{}',datetime('now'),datetime('now')),
('workflow-state-workflow','Workflow State','workflow_id','Workflow','Link','Workflow',20,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('workflow-state-name','Workflow State','state_name','State Name','Data',NULL,30,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,140,'{}',datetime('now'),datetime('now')),
('workflow-state-docstatus','Workflow State','doc_status','Document Status','Select','0\n1\n2',40,1,0,0,1,1,0,0,'0',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('workflow-state-edit-role','Workflow State','allow_edit_role','Allow Edit Role','Link','Role',50,0,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('workflow-state-index','Workflow State','idx','Index','Int',NULL,60,0,0,0,1,0,0,0,'0',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('workflow-state-metadata','Workflow State','metadata_json','Metadata','JSON',NULL,70,0,0,0,0,0,0,0,'{}',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),

('workflow-transition-id','Workflow Transition','id','ID','Data',NULL,10,0,1,1,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,140,'{}',datetime('now'),datetime('now')),
('workflow-transition-workflow','Workflow Transition','workflow_id','Workflow','Link','Workflow',20,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('workflow-transition-state','Workflow Transition','state_name','From State','Data',NULL,30,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,140,'{}',datetime('now'),datetime('now')),
('workflow-transition-action','Workflow Transition','action','Action','Data',NULL,40,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,140,'{}',datetime('now'),datetime('now')),
('workflow-transition-next','Workflow Transition','next_state','Next State','Data',NULL,50,1,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,140,'{}',datetime('now'),datetime('now')),
('workflow-transition-role','Workflow Transition','allowed_role','Allowed Role','Link','Role',60,0,0,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('workflow-transition-condition','Workflow Transition','condition_expression','Condition','Code',NULL,70,0,0,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{"safe_json_condition":true}',datetime('now'),datetime('now')),
('workflow-transition-index','Workflow Transition','idx','Index','Int',NULL,80,0,0,0,1,0,0,0,'0',NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('workflow-transition-metadata','Workflow Transition','metadata_json','Metadata','JSON',NULL,90,0,0,0,0,0,0,0,'{}',NULL,NULL,NULL,NULL,NULL,NULL,'{"condition_handler_key":"condition_handler"}',datetime('now'),datetime('now')),

('workflow-action-id','Workflow Action','id','ID','Data',NULL,10,1,1,0,0,0,1,0,NULL,NULL,NULL,NULL,NULL,NULL,140,'{}',datetime('now'),datetime('now')),
('workflow-action-doctype','Workflow Action','doctype','Document Type','Data',NULL,20,1,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('workflow-action-docname','Workflow Action','docname','Document','Data',NULL,30,1,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('workflow-action-action','Workflow Action','action','Action','Data',NULL,40,1,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,140,'{}',datetime('now'),datetime('now')),
('workflow-action-from','Workflow Action','from_state','From State','Data',NULL,50,0,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,140,'{}',datetime('now'),datetime('now')),
('workflow-action-to','Workflow Action','to_state','To State','Data',NULL,60,1,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,140,'{}',datetime('now'),datetime('now')),
('workflow-action-user','Workflow Action','user_id','User','Data',NULL,70,0,1,0,1,1,1,0,NULL,NULL,NULL,NULL,NULL,NULL,180,'{}',datetime('now'),datetime('now')),
('workflow-action-status','Workflow Action','status','Status','Data',NULL,80,1,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,100,'{}',datetime('now'),datetime('now')),
('workflow-action-comment','Workflow Action','comment','Comment','Text',NULL,90,0,1,0,0,0,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now')),
('workflow-action-created','Workflow Action','created_at','Created At','Datetime',NULL,100,1,1,0,1,1,0,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',datetime('now'),datetime('now'))
ON CONFLICT(doctype,fieldname) DO UPDATE SET
  label=excluded.label,fieldtype=excluded.fieldtype,options=excluded.options,
  idx=excluded.idx,reqd=excluded.reqd,read_only=excluded.read_only,
  hidden=excluded.hidden,in_list_view=excluded.in_list_view,
  in_standard_filter=excluded.in_standard_filter,searchable=excluded.searchable,
  allow_on_submit=excluded.allow_on_submit,default_json=excluded.default_json,
  metadata_json=excluded.metadata_json,updated_at=excluded.updated_at;

INSERT INTO wmn_doctype_permissions(
  id,doctype,role,permlevel,can_read,can_write,can_create,can_delete,
  can_submit,can_cancel,can_amend,can_report,can_import,can_export,
  can_share,can_print,can_email,if_owner,metadata_json
)
VALUES
('docperm-workflow-system-manager','Workflow','System Manager',0,1,1,1,1,0,0,0,1,1,1,0,0,0,0,'{"platform_default":true}'),
('docperm-workflow-state-system-manager','Workflow State','System Manager',0,1,1,1,1,0,0,0,1,1,1,0,0,0,0,'{"platform_default":true}'),
('docperm-workflow-transition-system-manager','Workflow Transition','System Manager',0,1,1,1,1,0,0,0,1,1,1,0,0,0,0,'{"platform_default":true}'),
('docperm-workflow-action-system-manager','Workflow Action','System Manager',0,1,0,0,0,0,0,0,1,0,1,0,0,0,0,'{"platform_default":true,"read_only":true}')
ON CONFLICT(doctype,role,permlevel) DO UPDATE SET
  can_read=excluded.can_read,can_write=excluded.can_write,
  can_create=excluded.can_create,can_delete=excluded.can_delete,
  can_report=excluded.can_report,can_import=excluded.can_import,
  can_export=excluded.can_export,metadata_json=excluded.metadata_json;

UPDATE wmn_features
SET capability_ids_json='["lifecycle","doctype","metadata","create","save","sqlite","transactions","shell","i18n","system-settings","feature-registry","entitlements","feature-activation","users","roles","permissions","identity-context","permission-snapshot","user-permissions","document-sharing","page-registry","page-runtime","declarative-pages","page-controllers","document-events","document-lifecycle"]',
    updated_at=datetime('now')
WHERE code='core.platform';
