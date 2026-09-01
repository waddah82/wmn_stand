import '../../core/database/wmn_database.dart';
import '../kernel/wmn_kernel.dart';
import 'wmn_log_service.dart';

class WmnDiagnosticsSnapshot {
  const WmnDiagnosticsSnapshot({
    required this.capturedAt,
    required this.kernel,
    required this.database,
    required this.counts,
  });

  final DateTime capturedAt;
  final Map<String, Object?> kernel;
  final Map<String, Object?> database;
  final Map<String, int> counts;
}

class WmnDiagnosticsService {
  WmnDiagnosticsService({
    required this.database,
    required this.kernel,
    required this.logs,
  });

  final WmnDatabase database;
  final WmnKernel kernel;
  final WmnLogService logs;

  WmnDiagnosticsSnapshot snapshot() {
    final health = kernel.snapshot();
    return WmnDiagnosticsSnapshot(
      capturedAt: DateTime.now().toUtc(),
      kernel: <String, Object?>{
        'state': health.state.name,
        'healthy': health.healthy,
        'issues': health.issues,
        'registered_services': health.registeredServices,
        'available_capabilities': health.availableCapabilities,
        'enabled_modules': health.enabledModules,
        'installed_applications': health.installedApplications,
        'started_at': health.startedAt?.toIso8601String(),
      },
      database: <String, Object?>{
        'storage_kind': database.info.storageKind,
        'storage_location': database.info.storageLocation,
        'is_web': database.info.isWeb,
        'schema_version': database.info.schemaVersion,
      },
      counts: <String, int>{
        'files': _count('wmn_files'),
        'queued_jobs': _countWhere('wmn_background_jobs', "status='QUEUED'"),
        'failed_jobs': _countWhere('wmn_background_jobs', "status='FAILED'"),
        'unread_notifications': _countWhere('wmn_notifications', "channel='IN_APP' AND read_at IS NULL"),
        'error_logs': _countWhere('wmn_system_logs', "level IN ('ERROR','CRITICAL')"),
      },
    );
  }

  String recordSnapshot() {
    final value = snapshot();
    return logs.info(
      'wmn.diagnostics',
      'WMN diagnostics snapshot captured.',
      eventName: 'snapshot',
      details: <String, Object?>{
        'kernel': value.kernel,
        'database': value.database,
        'counts': value.counts,
      },
    );
  }

  int _count(String table) => database.db.select('SELECT COUNT(*) AS c FROM "$table";').first['c'] as int? ?? 0;

  int _countWhere(String table, String where) =>
      database.db.select('SELECT COUNT(*) AS c FROM "$table" WHERE $where;').first['c'] as int? ?? 0;
}
