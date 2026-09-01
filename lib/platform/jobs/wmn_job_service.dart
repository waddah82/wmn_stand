import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/database/wmn_database.dart';
import '../diagnostics/wmn_log_service.dart';

typedef WmnJobHandler = Object? Function(Map<String, Object?> args);

class WmnJobResult {
  const WmnJobResult({required this.id, required this.status, this.result, this.error});

  final String id;
  final String status;
  final Object? result;
  final String? error;
}

/// Generic WMN background-job and schedule foundation.
///
/// This service owns platform jobs only. A platform adapter decides when/how
/// `runNext` or `enqueueDueSchedules` is invoked (desktop loop, mobile task,
/// server worker, etc.).
class WmnJobService {
  WmnJobService({required this.database, required this.logs});

  final WmnDatabase database;
  final WmnLogService logs;
  static const Uuid _uuid = Uuid();
  final Map<String, WmnJobHandler> _handlers = <String, WmnJobHandler>{};

  List<String> get handlerNames => _handlers.keys.toList(growable: false)..sort();

  void registerHandler(String name, WmnJobHandler handler, {bool replace = false}) {
    final normalized = name.trim();
    if (normalized.isEmpty) throw StateError('Job handler name is required.');
    if (!replace && _handlers.containsKey(normalized)) {
      throw StateError('WMN job handler already registered: $normalized');
    }
    _handlers[normalized] = handler;
  }

  bool unregisterHandler(String name) => _handlers.remove(name) != null;

  String enqueue(
    String handlerName, {
    Map<String, Object?> args = const <String, Object?>{},
    String queue = 'system',
    DateTime? runAfter,
    int maxAttempts = 3,
  }) {
    if (!_handlers.containsKey(handlerName)) {
      throw StateError('Unknown WMN job handler: $handlerName');
    }
    if (maxAttempts < 1) throw StateError('maxAttempts must be at least 1.');
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO wmn_background_jobs(
        id,method_name,args_json,queue_name,status,run_after,attempts,max_attempts,
        created_at,updated_at
      ) VALUES (?,?,?,?,'QUEUED',?,0,?,?,?);
    ''', [
      id,
      handlerName,
      jsonEncode(args),
      queue,
      runAfter?.toUtc().toIso8601String(),
      maxAttempts,
      now,
      now,
    ]);
    return id;
  }

  WmnJobResult? runNext({String queue = 'system'}) {
    final now = DateTime.now().toUtc();
    final rows = database.db.select('''
      SELECT * FROM wmn_background_jobs
      WHERE status='QUEUED' AND queue_name=? AND (run_after IS NULL OR run_after <= ?)
      ORDER BY created_at
      LIMIT 1;
    ''', [queue, now.toIso8601String()]);
    if (rows.isEmpty) return null;

    final row = Map<String, Object?>.from(rows.first);
    final id = '${row['id']}';
    final handlerName = '${row['method_name']}';
    final handler = _handlers[handlerName];
    final attempts = (row['attempts'] as int? ?? 0) + 1;
    final started = now.toIso8601String();
    database.db.execute(
      "UPDATE wmn_background_jobs SET status='RUNNING',attempts=?,started_at=?,updated_at=? WHERE id=?;",
      [attempts, started, started, id],
    );

    if (handler == null) {
      final error = 'No active WMN handler is registered for $handlerName.';
      final status = _failOrRetry(row, id, attempts, error);
      return WmnJobResult(id: id, status: status, error: error);
    }

    try {
      final decoded = jsonDecode('${row['args_json']}');
      final args = decoded is Map ? Map<String, Object?>.from(decoded) : <String, Object?>{};
      final result = handler(args);
      final finished = DateTime.now().toUtc().toIso8601String();
      database.db.execute('''
        UPDATE wmn_background_jobs
        SET status='SUCCESS',result_json=?,error_text=NULL,finished_at=?,updated_at=?
        WHERE id=?;
      ''', [jsonEncode(result), finished, finished, id]);
      logs.info('wmn.jobs', 'Job completed.', eventName: handlerName, details: <String, Object?>{'job_id': id});
      return WmnJobResult(id: id, status: 'SUCCESS', result: result);
    } catch (error, stackTrace) {
      final text = error.toString();
      final status = _failOrRetry(row, id, attempts, text);
      logs.error(
        'wmn.jobs',
        'Job failed.',
        eventName: handlerName,
        details: <String, Object?>{'job_id': id, 'status': status, 'attempts': attempts},
        stackTrace: stackTrace.toString(),
      );
      return WmnJobResult(id: id, status: status, error: text);
    }
  }

  String scheduleOnce({
    required String name,
    required String handlerName,
    required DateTime runAt,
    Map<String, Object?> args = const <String, Object?>{},
  }) => _upsertSchedule(
        name: name,
        handlerName: handlerName,
        args: args,
        kind: 'ONCE',
        runAt: runAt.toUtc(),
      );

  String scheduleEvery({
    required String name,
    required String handlerName,
    required Duration interval,
    Map<String, Object?> args = const <String, Object?>{},
    DateTime? firstRunAt,
  }) {
    if (interval.inSeconds <= 0) throw StateError('Schedule interval must be greater than zero.');
    return _upsertSchedule(
      name: name,
      handlerName: handlerName,
      args: args,
      kind: 'INTERVAL',
      intervalSeconds: interval.inSeconds,
      nextRunAt: (firstRunAt ?? DateTime.now().toUtc().add(interval)).toUtc(),
    );
  }

  int enqueueDueSchedules({DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    final rows = database.db.select('''
      SELECT * FROM wmn_schedules
      WHERE enabled=1 AND next_run_at IS NOT NULL AND next_run_at <= ?
      ORDER BY next_run_at,name;
    ''', [current.toIso8601String()]);
    var count = 0;
    for (final raw in rows) {
      final row = Map<String, Object?>.from(raw);
      final handlerName = '${row['handler_name']}';
      if (!_handlers.containsKey(handlerName)) {
        logs.warning(
          'wmn.scheduler',
          'Due schedule skipped because its handler is not registered.',
          eventName: '${row['name']}',
          details: <String, Object?>{'handler': handlerName},
        );
        continue;
      }
      final decoded = jsonDecode('${row['args_json']}');
      final args = decoded is Map ? Map<String, Object?>.from(decoded) : <String, Object?>{};
      final jobId = enqueue(handlerName, args: args, queue: 'system');
      final next = _nextRun(row, current);
      database.db.execute('''
        UPDATE wmn_schedules
        SET last_job_id=?,last_run_at=?,next_run_at=?,enabled=?,updated_at=?
        WHERE id=?;
      ''', [
        jobId,
        current.toIso8601String(),
        next?.toIso8601String(),
        next == null ? 0 : 1,
        current.toIso8601String(),
        row['id'],
      ]);
      count += 1;
    }
    return count;
  }

  List<Map<String, Object?>> jobs({String? status, int limit = 100}) {
    final rows = status == null
        ? database.db.select('SELECT * FROM wmn_background_jobs ORDER BY created_at DESC LIMIT ?;', [limit])
        : database.db.select(
            'SELECT * FROM wmn_background_jobs WHERE status=? ORDER BY created_at DESC LIMIT ?;',
            [status, limit],
          );
    return rows.map((row) => Map<String, Object?>.from(row)).toList(growable: false);
  }

  List<Map<String, Object?>> schedules({bool? enabled}) {
    final rows = enabled == null
        ? database.db.select('SELECT * FROM wmn_schedules ORDER BY name;')
        : database.db.select('SELECT * FROM wmn_schedules WHERE enabled=? ORDER BY name;', [enabled ? 1 : 0]);
    return rows.map((row) => Map<String, Object?>.from(row)).toList(growable: false);
  }

  String _failOrRetry(Map<String, Object?> row, String id, int attempts, String error) {
    final maxAttempts = row['max_attempts'] as int? ?? 3;
    final retry = attempts < maxAttempts;
    final now = DateTime.now().toUtc();
    final runAfter = retry ? now.add(Duration(seconds: attempts * 5)).toIso8601String() : null;
    database.db.execute('''
      UPDATE wmn_background_jobs
      SET status=?,error_text=?,run_after=?,finished_at=?,updated_at=?
      WHERE id=?;
    ''', [
      retry ? 'QUEUED' : 'FAILED',
      error,
      runAfter,
      retry ? null : now.toIso8601String(),
      now.toIso8601String(),
      id,
    ]);
    return retry ? 'QUEUED' : 'FAILED';
  }

  String _upsertSchedule({
    required String name,
    required String handlerName,
    required Map<String, Object?> args,
    required String kind,
    int? intervalSeconds,
    DateTime? runAt,
    DateTime? nextRunAt,
  }) {
    if (!_handlers.containsKey(handlerName)) throw StateError('Unknown WMN job handler: $handlerName');
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) throw StateError('Schedule name is required.');
    final existing = database.db.select('SELECT id FROM wmn_schedules WHERE name=? LIMIT 1;', [normalizedName]);
    final id = existing.isEmpty ? _uuid.v4() : '${existing.first['id']}';
    final now = DateTime.now().toUtc().toIso8601String();
    final effectiveNext = kind == 'ONCE' ? runAt : nextRunAt;
    database.db.execute('''
      INSERT INTO wmn_schedules(
        id,name,handler_name,args_json,schedule_kind,interval_seconds,run_at,next_run_at,
        enabled,created_at,updated_at
      ) VALUES (?,?,?,?,?,?,?,?,1,?,?)
      ON CONFLICT(name) DO UPDATE SET
        handler_name=excluded.handler_name,
        args_json=excluded.args_json,
        schedule_kind=excluded.schedule_kind,
        interval_seconds=excluded.interval_seconds,
        run_at=excluded.run_at,
        next_run_at=excluded.next_run_at,
        enabled=1,
        updated_at=excluded.updated_at;
    ''', [
      id,
      normalizedName,
      handlerName,
      jsonEncode(args),
      kind,
      intervalSeconds,
      runAt?.toIso8601String(),
      effectiveNext?.toIso8601String(),
      now,
      now,
    ]);
    return id;
  }

  DateTime? _nextRun(Map<String, Object?> row, DateTime current) {
    if ('${row['schedule_kind']}' == 'ONCE') return null;
    final seconds = row['interval_seconds'] as int?;
    if (seconds == null || seconds <= 0) return null;
    return current.add(Duration(seconds: seconds));
  }
}
