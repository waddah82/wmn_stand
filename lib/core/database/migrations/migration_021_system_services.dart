import 'database_migration.dart';

/// WMN R3.2 system-service foundation.
///
/// Adds application-neutral persistence for files, scoped configuration,
/// diagnostics, schedules and notifications. No business-application tables
/// are introduced here.
class Migration021SystemServices extends SqlDatabaseMigration {
  const Migration021SystemServices();

  @override
  int get version => 21;

  @override
  String get name => 'system_services';

  @override
  String get sql => r'''
CREATE TABLE IF NOT EXISTS wmn_scoped_settings (
  scope_type TEXT NOT NULL CHECK (scope_type IN ('SYSTEM','APPLICATION','PLATFORM','PROFILE')),
  scope_key TEXT NOT NULL DEFAULT '',
  setting_key TEXT NOT NULL,
  value_json TEXT,
  is_secret INTEGER NOT NULL DEFAULT 0 CHECK (is_secret IN (0,1)),
  updated_at TEXT NOT NULL,
  PRIMARY KEY (scope_type, scope_key, setting_key)
) STRICT;

CREATE TABLE IF NOT EXISTS wmn_system_logs (
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

CREATE TABLE IF NOT EXISTS wmn_schedules (
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

CREATE TABLE IF NOT EXISTS wmn_notifications (
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

CREATE INDEX IF NOT EXISTS idx_wmn_scoped_settings_lookup
ON wmn_scoped_settings(scope_type, scope_key, setting_key);

CREATE INDEX IF NOT EXISTS idx_wmn_system_logs_created
ON wmn_system_logs(created_at DESC, level, source);

CREATE INDEX IF NOT EXISTS idx_wmn_system_logs_correlation
ON wmn_system_logs(correlation_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_wmn_schedules_due
ON wmn_schedules(enabled, next_run_at, name);

CREATE INDEX IF NOT EXISTS idx_wmn_notifications_recipient
ON wmn_notifications(recipient, read_at, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_wmn_notifications_status
ON wmn_notifications(channel, status, created_at);
''';
}
