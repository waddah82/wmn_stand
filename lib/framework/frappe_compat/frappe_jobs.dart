import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/database/wmn_database.dart';
import 'frappe_methods.dart';

class WmnFrappeJobQueue {
  WmnFrappeJobQueue({required this.database, required this.methods});

  final WmnDatabase database;
  final WmnFrappeMethodRegistry methods;
  static const Uuid _uuid = Uuid();

  String enqueue(
    String method, {
    Map<String, Object?> args = const {},
    String queue = 'default',
    DateTime? runAfter,
    int maxAttempts = 3,
  }) {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO wmn_background_jobs(
        id,method_name,args_json,queue_name,status,run_after,max_attempts,created_at,updated_at
      ) VALUES (?,?,?,?,'QUEUED',?,?,?,?);
    ''', [id, method, jsonEncode(args), queue, runAfter?.toUtc().toIso8601String(), maxAttempts, now, now]);
    return id;
  }

  Map<String, Object?>? runNext({String queue = 'default'}) {
    final now = DateTime.now().toUtc();
    final rows = database.db.select('''
      SELECT * FROM wmn_background_jobs
      WHERE status='QUEUED' AND queue_name=? AND (run_after IS NULL OR run_after <= ?)
      ORDER BY created_at
      LIMIT 1;
    ''', [queue, now.toIso8601String()]);
    if (rows.isEmpty) return null;
    final row = Map<String, Object?>.from(rows.first);
    final id = row['id'] as String;
    final attempts = (row['attempts'] as int? ?? 0) + 1;
    database.db.execute(
      "UPDATE wmn_background_jobs SET status='RUNNING',attempts=?,started_at=?,updated_at=? WHERE id=?;",
      [attempts, now.toIso8601String(), now.toIso8601String(), id],
    );
    try {
      final args = Map<String, Object?>.from(jsonDecode(row['args_json'] as String) as Map);
      final result = methods.call(row['method_name'] as String, args);
      final finished = DateTime.now().toUtc().toIso8601String();
      database.db.execute(
        "UPDATE wmn_background_jobs SET status='SUCCESS',result_json=?,finished_at=?,updated_at=? WHERE id=?;",
        [jsonEncode(result), finished, finished, id],
      );
      return <String, Object?>{'id': id, 'status': 'SUCCESS', 'result': result};
    } catch (error) {
      final maxAttempts = row['max_attempts'] as int? ?? 3;
      final retry = attempts < maxAttempts;
      final finished = DateTime.now().toUtc().toIso8601String();
      database.db.execute(
        'UPDATE wmn_background_jobs SET status=?,error_text=?,finished_at=?,updated_at=? WHERE id=?;',
        [retry ? 'QUEUED' : 'FAILED', error.toString(), retry ? null : finished, finished, id],
      );
      return <String, Object?>{'id': id, 'status': retry ? 'QUEUED' : 'FAILED', 'error': error.toString()};
    }
  }

  List<Map<String, Object?>> jobs({String? status, int limit = 100}) {
    final rows = status == null
        ? database.db.select('SELECT * FROM wmn_background_jobs ORDER BY created_at DESC LIMIT ?;', [limit])
        : database.db.select('SELECT * FROM wmn_background_jobs WHERE status=? ORDER BY created_at DESC LIMIT ?;', [status, limit]);
    return rows.map((row) => Map<String, Object?>.from(row)).toList(growable: false);
  }
}
