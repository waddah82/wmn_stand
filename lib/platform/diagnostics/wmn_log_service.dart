import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/database/wmn_database.dart';

enum WmnLogLevel { debug, info, warning, error, critical }

class WmnLogEntry {
  const WmnLogEntry({
    required this.id,
    required this.level,
    required this.source,
    required this.message,
    required this.createdAt,
    this.eventName,
    this.details = const <String, Object?>{},
    this.correlationId,
    this.stackTrace,
  });

  final String id;
  final WmnLogLevel level;
  final String source;
  final String message;
  final DateTime createdAt;
  final String? eventName;
  final Map<String, Object?> details;
  final String? correlationId;
  final String? stackTrace;
}

class WmnLogService {
  WmnLogService(this.database);

  final WmnDatabase database;
  static const Uuid _uuid = Uuid();

  String write(
    WmnLogLevel level, {
    required String source,
    required String message,
    String? eventName,
    Map<String, Object?> details = const <String, Object?>{},
    String? correlationId,
    String? stackTrace,
  }) {
    final id = _uuid.v4();
    database.db.execute('''
      INSERT INTO wmn_system_logs(
        id,level,source,event_name,message,details_json,correlation_id,stack_trace,created_at
      ) VALUES (?,?,?,?,?,?,?,?,?);
    ''', [
      id,
      _levelName(level),
      source,
      eventName,
      message,
      jsonEncode(details),
      correlationId,
      stackTrace,
      DateTime.now().toUtc().toIso8601String(),
    ]);
    return id;
  }

  String info(String source, String message, {String? eventName, Map<String, Object?> details = const {}}) =>
      write(WmnLogLevel.info, source: source, message: message, eventName: eventName, details: details);

  String warning(String source, String message, {String? eventName, Map<String, Object?> details = const {}}) =>
      write(WmnLogLevel.warning, source: source, message: message, eventName: eventName, details: details);

  String error(
    String source,
    String message, {
    String? eventName,
    Map<String, Object?> details = const {},
    String? correlationId,
    String? stackTrace,
  }) =>
      write(
        WmnLogLevel.error,
        source: source,
        message: message,
        eventName: eventName,
        details: details,
        correlationId: correlationId,
        stackTrace: stackTrace,
      );

  List<WmnLogEntry> entries({WmnLogLevel? minimumLevel, String? source, int limit = 200}) {
    final where = <String>[];
    final args = <Object?>[];
    if (minimumLevel != null) {
      const ranks = <WmnLogLevel, int>{
        WmnLogLevel.debug: 0,
        WmnLogLevel.info: 1,
        WmnLogLevel.warning: 2,
        WmnLogLevel.error: 3,
        WmnLogLevel.critical: 4,
      };
      final accepted = WmnLogLevel.values.where((level) => ranks[level]! >= ranks[minimumLevel]!).map(_levelName).toList();
      where.add('level IN (${List.filled(accepted.length, '?').join(',')})');
      args.addAll(accepted);
    }
    if (source != null && source.trim().isNotEmpty) {
      where.add('source=?');
      args.add(source);
    }
    final clause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    args.add(limit);
    final rows = database.db.select('''
      SELECT * FROM wmn_system_logs
      $clause
      ORDER BY created_at DESC
      LIMIT ?;
    ''', args);
    return rows.map((row) => _fromRow(Map<String, Object?>.from(row))).toList(growable: false);
  }

  int count({WmnLogLevel? level}) {
    final rows = level == null
        ? database.db.select('SELECT COUNT(*) AS c FROM wmn_system_logs;')
        : database.db.select('SELECT COUNT(*) AS c FROM wmn_system_logs WHERE level=?;', [_levelName(level)]);
    return rows.first['c'] as int? ?? 0;
  }

  int prune({Duration keepFor = const Duration(days: 30)}) {
    final cutoff = DateTime.now().toUtc().subtract(keepFor).toIso8601String();
    final before = count();
    database.db.execute('DELETE FROM wmn_system_logs WHERE created_at < ?;', [cutoff]);
    return before - count();
  }

  WmnLogEntry _fromRow(Map<String, Object?> row) {
    Map<String, Object?> details = const <String, Object?>{};
    final raw = row['details_json'];
    if (raw is String && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map) details = Map<String, Object?>.from(decoded);
    }
    return WmnLogEntry(
      id: '${row['id']}',
      level: _levelFromName('${row['level']}'),
      source: '${row['source']}',
      eventName: row['event_name'] as String?,
      message: '${row['message']}',
      details: Map<String, Object?>.unmodifiable(details),
      correlationId: row['correlation_id'] as String?,
      stackTrace: row['stack_trace'] as String?,
      createdAt: DateTime.parse('${row['created_at']}'),
    );
  }

  String _levelName(WmnLogLevel level) => switch (level) {
        WmnLogLevel.debug => 'DEBUG',
        WmnLogLevel.info => 'INFO',
        WmnLogLevel.warning => 'WARNING',
        WmnLogLevel.error => 'ERROR',
        WmnLogLevel.critical => 'CRITICAL',
      };

  WmnLogLevel _levelFromName(String value) => switch (value) {
        'DEBUG' => WmnLogLevel.debug,
        'WARNING' => WmnLogLevel.warning,
        'ERROR' => WmnLogLevel.error,
        'CRITICAL' => WmnLogLevel.critical,
        _ => WmnLogLevel.info,
      };
}
