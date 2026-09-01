-- WMN R3.0 clean platform schema. No business application tables are created here.

CREATE TABLE system_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      ) STRICT;

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

CREATE TABLE roles (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  is_system INTEGER NOT NULL DEFAULT 0 CHECK (is_system IN (0, 1)),
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
  created_at TEXT NOT NULL,
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

CREATE TABLE role_permissions (
  role_id TEXT NOT NULL,
  permission_id TEXT NOT NULL,
  granted INTEGER NOT NULL DEFAULT 1 CHECK (granted IN (0, 1)),
  PRIMARY KEY (role_id, permission_id),
  FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE,
  FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE
) STRICT;

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

CREATE TABLE custom_field_values (
  document_type TEXT NOT NULL,
  document_id TEXT NOT NULL,
  field_name TEXT NOT NULL,
  value_json TEXT,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(document_type, document_id, field_name)
) STRICT;

CREATE TABLE client_scripts (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  document_type TEXT NOT NULL,
  script TEXT NOT NULL,
  priority INTEGER NOT NULL DEFAULT 0,
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(document_type, name)
) STRICT;

CREATE TABLE server_scripts (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  script_type TEXT NOT NULL DEFAULT 'DOCUMENT_EVENT' CHECK (script_type IN ('DOCUMENT_EVENT','API','SCHEDULED')),
  document_type TEXT,
  event_name TEXT,
  api_method TEXT,
  script TEXT NOT NULL,
  priority INTEGER NOT NULL DEFAULT 0,
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  CHECK (
    (script_type = 'DOCUMENT_EVENT' AND document_type IS NOT NULL AND event_name IS NOT NULL)
    OR (script_type = 'API' AND api_method IS NOT NULL)
    OR (script_type = 'SCHEDULED')
  ),
  UNIQUE(script_type, name)
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

CREATE TABLE custom_reports (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  source_key TEXT NOT NULL,
  definition_json TEXT NOT NULL,
  is_system INTEGER NOT NULL DEFAULT 0 CHECK (is_system IN (0, 1)),
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
  created_by TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(name)
) STRICT;

CREATE TABLE report_run_log (
  id TEXT PRIMARY KEY,
  report_id TEXT,
  report_name TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('SUCCESS','ERROR')),
  row_count INTEGER NOT NULL DEFAULT 0,
  duration_ms INTEGER NOT NULL DEFAULT 0,
  error_text TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (report_id) REFERENCES custom_reports(id) ON DELETE SET NULL
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

CREATE TABLE data_export_jobs (
  id TEXT PRIMARY KEY,
  doctype TEXT NOT NULL,
  format TEXT NOT NULL CHECK (format IN ('CSV','XLSX','JSON')),
  fields_json TEXT NOT NULL DEFAULT '[]',
  filters_json TEXT NOT NULL DEFAULT '[]',
  row_count INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
) STRICT;

CREATE TABLE print_formats (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  format_type TEXT NOT NULL DEFAULT 'DOCUMENT',
  template_json TEXT NOT NULL DEFAULT '{}',
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
) STRICT;

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
  updated_at TEXT NOT NULL,
  FOREIGN KEY (print_format_id) REFERENCES print_formats(id)
) STRICT;

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
) STRICT;

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

CREATE TABLE wmn_list_view_settings (
  doctype TEXT PRIMARY KEY,
  settings_json TEXT NOT NULL DEFAULT '{}',
  updated_at TEXT NOT NULL,
  FOREIGN KEY (doctype) REFERENCES wmn_doctypes(name) ON DELETE CASCADE
) STRICT;

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

CREATE TABLE wmn_naming_counters (
  series_key TEXT PRIMARY KEY,
  current_value INTEGER NOT NULL DEFAULT 0 CHECK (current_value >= 0),
  updated_at TEXT NOT NULL
) STRICT;

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

CREATE TABLE wmn_defaults (
  user_id TEXT NOT NULL,
  default_key TEXT NOT NULL,
  value_json TEXT,
  updated_at TEXT NOT NULL,
  PRIMARY KEY(user_id, default_key)
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

CREATE TABLE wmn_script_reports (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  module TEXT NOT NULL DEFAULT 'Custom',
  reference_doctype TEXT,
  script TEXT NOT NULL,
  filters_json TEXT NOT NULL DEFAULT '[]',
  columns_json TEXT NOT NULL DEFAULT '[]',
  is_system INTEGER NOT NULL DEFAULT 0 CHECK (is_system IN (0,1)),
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0,1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
) STRICT;

CREATE TABLE "wmn_frappe_api_coverage" (
  source_api TEXT PRIMARY KEY,
  family TEXT NOT NULL,
  target_api TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('NATIVE','COMPAT','STRUCTURED','SAFE_SUBSET','EXPLICIT_PORT','PARTIAL','PENDING','DEFERRED','NOT_APPLICABLE')),
  source_hits INTEGER NOT NULL DEFAULT 0,
  notes TEXT,
  updated_at TEXT NOT NULL
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

CREATE TABLE wmn_app_source_units (
  id TEXT PRIMARY KEY,
  app_name TEXT NOT NULL,
  artifact_id TEXT,
  source_path TEXT NOT NULL,
  language TEXT NOT NULL CHECK (language IN ('PYTHON','JAVASCRIPT','TYPESCRIPT','JSON','SQL','HTML','CSS','TEXT')),
  source_code TEXT NOT NULL,
  converted_code TEXT,
  conversion_strategy TEXT NOT NULL DEFAULT 'PRESERVE',
  conversion_status TEXT NOT NULL DEFAULT 'NEEDS_PORT' CHECK (conversion_status IN ('AUTO_CONVERTED','REVIEW','NEEDS_PORT','IGNORED','FAILED')),
  confidence REAL NOT NULL DEFAULT 0 CHECK (confidence >= 0 AND confidence <= 1),
  review_status TEXT NOT NULL DEFAULT 'UNREVIEWED' CHECK (review_status IN ('UNREVIEWED','APPROVED','REJECTED','EDITED')),
  diagnostics_json TEXT NOT NULL DEFAULT '[]',
  dependencies_json TEXT NOT NULL DEFAULT '[]',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (app_name) REFERENCES wmn_app_packages(app_name) ON DELETE CASCADE,
  FOREIGN KEY (artifact_id) REFERENCES wmn_app_artifacts(id) ON DELETE SET NULL,
  UNIQUE(app_name, source_path, language)
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

CREATE INDEX idx_client_scripts_document
ON client_scripts(document_type, enabled, priority DESC, name);

CREATE INDEX idx_custom_field_values_lookup
ON custom_field_values(document_type, field_name, document_id);

CREATE INDEX idx_custom_fields_document
ON custom_fields(document_type, enabled, sort_order, field_name);

CREATE INDEX idx_custom_reports_source
ON custom_reports(source_key, enabled, name);

CREATE INDEX idx_data_import_jobs_created
ON data_import_jobs(created_at DESC, status);

CREATE INDEX idx_data_import_rows_job
ON data_import_rows(job_id, row_number);

CREATE INDEX idx_property_overrides_document
ON property_overrides(document_type, enabled, field_name);

CREATE INDEX idx_report_run_log_created
ON report_run_log(created_at DESC, status);

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

CREATE INDEX IF NOT EXISTS idx_user_roles_user ON user_roles(user_id, role_id);

CREATE INDEX IF NOT EXISTS idx_numbering_series_scope ON numbering_series(document_type, scope_type, scope_value, enabled);

CREATE INDEX IF NOT EXISTS idx_print_jobs_document ON print_jobs(document_type, document_name, created_at);

INSERT OR IGNORE INTO wmn_modules(name,label,app_name,icon,color,sequence_id,enabled,metadata_json,created_at,updated_at) VALUES ('WMN System','WMN System',NULL,'hub',NULL,10,1,'{"source_framework":"WMN","system_platform":true}',datetime('now'),datetime('now'));

INSERT OR IGNORE INTO wmn_modules(name,label,app_name,icon,color,sequence_id,enabled,metadata_json,created_at,updated_at) VALUES ('Security','Security',NULL,'shield',NULL,20,1,'{"source_framework":"WMN","system_capability":true,"optional":true}',datetime('now'),datetime('now'));

INSERT OR IGNORE INTO wmn_doctypes(name,module,storage_mode,table_name,id_field,title_field,autoname,is_single,is_child,is_submittable,track_changes,allow_create,allow_edit,allow_delete,allow_import,allow_export,generic_write,is_system,enabled,metadata_json,created_at,updated_at) VALUES ('User','Security','TABLE','tabUser','id','display_name',NULL,0,0,0,1,1,1,0,0,1,0,1,1,'{}',datetime('now'),datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.ValidationError','Exceptions','WmnFrappeValidationException','NATIVE',401,'Native validation exception contract.',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe._dict','Core Types','Map<String,Object?> / script object','COMPAT',1860,'Frappe dict semantics map to native Dart/JavaScript objects',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.as_json','Utilities','WmnFrappeUtils.asJson','NATIVE',101,'Native JSON serialization helper',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.bold','Formatting','WmnFrappeUtils.bold','NATIVE',881,'Native formatting helper',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.cache.get_value','Cache','wmn.frappe.cache.get','NATIVE',59,'Namespaced cache with optional TTL',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.cache.set_value','Cache','wmn.frappe.cache.set','NATIVE',39,'Namespaced cache with optional TTL',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.call','RPC','wmn.frappe.methods.call','NATIVE',668,'Native method registry with built-in frappe.client mappings',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.clear_cache','Cache','WmnFrappeUtils.clearCache','NATIVE',172,'WMN runtime cache invalidation',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.copy_doc','Document','WmnFrappeDocumentApi.copyDoc','NATIVE',219,'Creates a local unsaved document copy',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.db.bulk_update','Database','WmnFrappeDbApi.bulkUpdate','NATIVE',23,'Transactional document-layer updates; engine ownership remains enforced.',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.db.count','Database','wmn.frappe.db.count','NATIVE',139,'Filtered document count',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.db.exists','Database','wmn.frappe.db.exists','NATIVE',1110,'Name or filter existence checks',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.db.get_default','Defaults','WmnFrappeDefaults.getDefault','NATIVE',78,'User default with global fallback.',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.db.get_single_value','Database','wmn.frappe.db.getSingleValue','NATIVE',314,'Single DocType value store',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.db.get_value','Database','wmn.frappe.db.getValue','NATIVE',2290,'Document selector or filters',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.db.get_values','Database','WmnFrappeDbApi.getValues','NATIVE',63,'Structured multi-row value lookup.',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.db.set_default','Defaults','WmnFrappeDefaults.setDefault','NATIVE',52,'Native user/global default persistence.',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.db.set_single_value','Database','wmn.frappe.db.setSingleValue','NATIVE',440,'Single DocType value store',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.db.set_value','Database','wmn.frappe.db.setValue','NATIVE',834,'Writes through WmnDocumentService and cannot bypass engine-owned docs',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.db.sql','Database','WmnFrappeQueryEngine / native module service','PARTIAL',1106,'Arbitrary SQL is intentionally not exposed; common operations map to structured queries/native services',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.defaults.get_global_default','Defaults','WmnFrappeDefaults.getGlobalDefault','NATIVE',32,'Native global defaults store.',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.delete_doc','Document','WmnFrappeDocumentApi.deleteDoc','NATIVE',456,'Delete through permissions and engine ownership checks',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.delete_doc_if_exists','Document','WmnFrappeUtils.deleteDocIfExists','NATIVE',158,'Conditional document deletion with normal permission rules',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.enqueue','Jobs','wmn.frappe.jobs.enqueue','NATIVE',105,'Persistent local-first queue; server authoritative in multi-device mode',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.format','Formatting','wmn.format','PARTIAL',50,'Basic value formatting contract; DocField-aware formatters remain incremental',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.generate_hash','Utilities','WmnFrappeUtils.generateHash','NATIVE',207,'Cryptographically seeded runtime token helper',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.get_all','Database','wmn.frappe.db.getAll','NATIVE',1649,'Trusted runtime query API',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.get_cached_doc','Cache','WmnFrappeUtils.getCachedDoc','NATIVE',173,'Cached document read',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.get_cached_value','Cache','WmnFrappeUtils.getCachedValue','NATIVE',767,'Cached read over WMN document/database API',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.get_doc','Document','wmn.frappe.documents.getDoc','NATIVE',4046,'Generic DocType read with engine ownership preserved',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.get_hooks','Hooks','WmnFrappeHookRegistry.bindings','NATIVE',212,'Reads native persistent hook bindings',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.get_last_doc','Database','WmnFrappeDbApi.getLastDoc','NATIVE',64,'Permission-aware last-document lookup with explicit ordering.',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.get_lazy_doc','Documents','WmnFrappeDocumentApi.getLazyDoc','NATIVE',27,'Local-first WMN returns the document directly; no remote lazy proxy is required.',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.get_list','Database','wmn.frappe.db.getList','NATIVE',190,'Permission-aware list facade',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.get_meta','Meta','wmn.frappe.meta.getMeta','NATIVE',427,'WMN DocType metadata facade',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.get_precision','Meta','WmnFrappeMetaApi.getPrecision','NATIVE',54,'Reads DocField precision with deterministic fallback.',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.get_roles','Permissions','wmn.frappe.permissions.rolesFor','NATIVE',97,'WMN roles mapped to Frappe-compatible role names',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.get_route','Routing','wmn.getRoute','PENDING',67,'Deferred until the safe WMN script/runtime capability is enabled.',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.get_single','Database','WmnFrappeDbApi.getSingle','NATIVE',79,'Native singleton value document.',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.get_single_value','Database','WmnFrappeDbApi.getSingleValue','NATIVE',206,'Top-level compatibility alias for singleton values',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.get_system_settings','Settings','WmnFrappeUtils.getSystemSetting','NATIVE',112,'Reads WMN settings repository',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.get_value','Database','WmnFrappeDbApi.getValue','NATIVE',213,'Top-level compatibility alias to DB value API',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.has_permission','Permissions','wmn.frappe.permissions.hasPermission','NATIVE',208,'DocPerm + roles + shares + owner checks',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.log_error','Audit','WmnFrappeUtils.logError','NATIVE',132,'Records runtime errors in WMN audit trail',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.model.document','Documents','WmnDocumentService + WmnFrappeDocumentApi','STRUCTURED',279,'WMN document lifecycle is native Dart; Python Document subclasses are explicitly ported.',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.model.mapper.get_mapped_doc','Document Mapping','WmnFrappeDocumentMapper.mapDocument','STRUCTURED',43,'Metadata-aware parent/child mapping; business conditions/post-processing remain module-owned.',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.model.set_value','Client Model','wmn.model.setValue','PENDING',311,'Deferred until the safe WMN script/runtime capability is enabled.',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.model.workflow','Workflow','WmnFrappeWorkflowEngine','NATIVE',120,'Native workflow states, transitions, role checks and action history',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.msgprint','Messages','WmnFrappeMessageBus.msgprint','NATIVE',428,'Native message queue for controller warnings and information; UI decides presentation.',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.new_doc','Document','wmn.frappe.documents.newDoc','NATIVE',851,'Metadata defaults and local document state',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.parse_json','Utilities','WmnFrappeUtils.parseJson','NATIVE',29,'Native JSON parse helper.',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.provide','Namespace','wmn.provide','PENDING',265,'Deferred until the safe WMN script/runtime capability is enabled.',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.publish_realtime','Realtime','wmn.frappe.realtime.publish','NATIVE',48,'Local event bus plus persisted event log',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.qb.DocType','Query','WmnFrappeQueryEngine','PARTIAL',1259,'Structured DocType query target; arbitrary Python query-builder expressions are ported explicitly',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.qb.from_','Query','WmnFrappeQueryEngine','PARTIAL',869,'Structured select/update/delete facade',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.qb.get_query','Query','WmnFrappeQueryEngine','PARTIAL',190,'Structured query specifications instead of application SQL text',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.realtime.on','Realtime','wmn.realtime.on','PENDING',43,'Deferred until the safe WMN script/runtime capability is enabled.',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.render_template','Template','wmn.renderTemplate','PARTIAL',64,'Safe simple template compatibility; full Jinja parity remains pending',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.scrub','Utilities','WmnFrappeUtils.scrub','NATIVE',266,'Native identifier normalization helper',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.sendmail','Mail','WmnMailEngine','PENDING',55,'Reserved for server/runtime implementation',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.session.user','Session','WmnFrappeSession.user','NATIVE',47,'Native current-user session value.',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.set_route','Routing','wmn.router.setRoute','PENDING',412,'Deferred until the safe WMN script/runtime capability is enabled.',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.set_user','Session','WmnFrappeSession.setUser','NATIVE',433,'Switches runtime user only to known/enabled WMN users',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.throw','Errors','WmnFrappeValidationException','NATIVE',2615,'Native structured runtime exception',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.ui.form.on','Client Form','wmn.ui.form.on','PENDING',636,'Deferred until the safe WMN script/runtime capability is enabled.',datetime('now'));

INSERT OR IGNORE INTO wmn_frappe_api_coverage(source_api,family,target_api,status,source_hits,notes,updated_at) VALUES ('frappe.whitelist','External API','Deferred external API layer','DEFERRED',457,'Decorator exposure over HTTP/RPC is deferred; native module calls do not require a whitelist decorator.',datetime('now'));
