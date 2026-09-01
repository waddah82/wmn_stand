import '../../../core/database/wmn_database.dart';

class WmnQueryReportSafetyPolicy {
  const WmnQueryReportSafetyPolicy._();

  static const bool allowsMultipleStatements = false;
  static const bool allowsDataModification = false;
  static const bool allowsSchemaModification = false;
  static const bool allowsPragmaOrAttach = false;
  static const bool requiresBoundParameters = true;
  static const Set<String> allowedStatementPrefixes = <String>{'SELECT', 'WITH'};
  static const Set<String> forbiddenKeywords = <String>{
    'INSERT',
    'UPDATE',
    'DELETE',
    'REPLACE',
    'CREATE',
    'ALTER',
    'DROP',
    'TRUNCATE',
    'PRAGMA',
    'ATTACH',
    'DETACH',
    'VACUUM',
    'REINDEX',
    'ANALYZE',
    'BEGIN',
    'COMMIT',
    'ROLLBACK',
    'SAVEPOINT',
    'RELEASE',
  };
}

class WmnQueryReportResult {
  const WmnQueryReportResult({
    required this.columns,
    required this.rows,
    required this.durationMs,
    required this.truncated,
  });

  final List<Map<String, Object?>> columns;
  final List<Map<String, Object?>> rows;
  final int durationMs;
  final bool truncated;
}

/// Executes metadata-defined Query Reports using SQLite read-only statements.
///
/// Query Report SQL is deliberately constrained to a single SELECT/WITH query.
/// Filters use Frappe-compatible `%(filter_name)s` placeholders that are
/// converted to bound SQLite parameters. DDL/DML, PRAGMA, ATTACH and multiple
/// statements are rejected before execution.
class WmnQueryReportService {
  WmnQueryReportService({required this.database});

  final WmnDatabase database;

  static const int defaultMaxRows = 1000;
  static const int hardMaxRows = 5000;

  WmnQueryReportResult execute({
    required String sql,
    Map<String, Object?> filters = const {},
    List<Map<String, Object?>> declaredFilters = const [],
    List<Map<String, Object?>> declaredColumns = const [],
    int maxRows = defaultMaxRows,
  }) {
    final normalized = _validateAndNormalize(sql);
    final effectiveFilters = _effectiveFilters(filters, declaredFilters);
    final compiled = _compileBoundParameters(normalized, effectiveFilters);
    final parameters = compiled.parameters;
    final compiledSql = compiled.sql;

    final safeMax = maxRows < 1 ? 1 : (maxRows > hardMaxRows ? hardMaxRows : maxRows);
    final started = DateTime.now();
    final resultSet = database.db.select(
      'SELECT * FROM (\n$compiledSql\n) AS wmn_query_report LIMIT ?;',
      <Object?>[...parameters, safeMax + 1],
    );
    final durationMs = DateTime.now().difference(started).inMilliseconds;
    final truncated = resultSet.length > safeMax;
    final columnNames = resultSet.columnNames;
    final rows = resultSet
        .take(safeMax)
        .map((row) => <String, Object?>{
              for (final key in columnNames) key: row[key],
            })
        .toList(growable: false);

    final columns = declaredColumns.isNotEmpty
        ? declaredColumns
        : resultSet.columnNames
            .map((name) => <String, Object?>{
                  'fieldname': name,
                  'label': name,
                  'fieldtype': 'Data',
                })
            .toList(growable: false);
    return WmnQueryReportResult(
      columns: columns,
      rows: rows,
      durationMs: durationMs,
      truncated: truncated,
    );
  }

  Map<String, Object?> _effectiveFilters(
    Map<String, Object?> runtimeFilters,
    List<Map<String, Object?>> definitions,
  ) {
    final values = <String, Object?>{...runtimeFilters};
    for (final definition in definitions) {
      final name = '${definition['fieldname'] ?? definition['field_name'] ?? definition['name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      if (!values.containsKey(name)) {
        final defaultValue = definition['default'] ?? definition['value'];
        if (defaultValue != null) values[name] = defaultValue;
      }
      final required = definition['required'] == true || definition['reqd'] == true || definition['reqd'] == 1;
      final value = values[name];
      if (required && (value == null || (value is String && value.trim().isEmpty))) {
        throw StateError('Query Report filter $name is required.');
      }
    }
    return values;
  }

  String _validateAndNormalize(String sql) {
    var value = sql.trim();
    if (value.isEmpty) throw StateError('Query Report SQL is required.');

    var surface = _sqlCodeSurface(value);
    final terminators = <int>[
      for (var index = 0; index < surface.length; index++)
        if (surface.codeUnitAt(index) == 59) index,
    ];
    if (terminators.length > 1) {
      throw StateError('Query Report must contain exactly one read-only statement.');
    }
    if (terminators.length == 1) {
      final index = terminators.single;
      if (surface.substring(index + 1).trim().isNotEmpty) {
        throw StateError('Query Report must contain exactly one read-only statement.');
      }
      value = '${value.substring(0, index)}${value.substring(index + 1)}'.trimRight();
      surface = _sqlCodeSurface(value);
    }

    final scrubbed = surface.trimLeft();
    final prefixMatch = RegExp(r'^([A-Za-z]+)\b').firstMatch(scrubbed);
    final prefix = prefixMatch?.group(1)?.toUpperCase();
    if (prefix == null || !WmnQueryReportSafetyPolicy.allowedStatementPrefixes.contains(prefix)) {
      throw StateError('Query Report must start with SELECT or WITH.');
    }
    for (final keyword in WmnQueryReportSafetyPolicy.forbiddenKeywords) {
      if (RegExp('\\b$keyword\\b', caseSensitive: false).hasMatch(scrubbed)) {
        throw StateError('Query Report cannot execute $keyword statements.');
      }
    }
    return value;
  }

  _CompiledQuery _compileBoundParameters(
    String sql,
    Map<String, Object?> effectiveFilters,
  ) {
    final surface = _sqlCodeSurface(sql);
    final validPattern = RegExp(r'%\(([A-Za-z_][A-Za-z0-9_]*)\)s');
    final suspiciousPattern = RegExp(r'%\([^)]+\)s');
    final matches = validPattern.allMatches(surface).toList(growable: false);
    final validRanges = <String>{for (final match in matches) '${match.start}:${match.end}'};
    for (final match in suspiciousPattern.allMatches(surface)) {
      if (!validRanges.contains('${match.start}:${match.end}')) {
        throw StateError('Query Report contains an invalid filter placeholder.');
      }
    }

    final parameters = <Object?>[];
    final buffer = StringBuffer();
    var offset = 0;
    for (final match in matches) {
      final name = match.group(1)!;
      if (!effectiveFilters.containsKey(name)) {
        throw StateError('Missing Query Report filter: $name.');
      }
      buffer
        ..write(sql.substring(offset, match.start))
        ..write('?');
      parameters.add(effectiveFilters[name]);
      offset = match.end;
    }
    buffer.write(sql.substring(offset));
    return _CompiledQuery(
      sql: buffer.toString(),
      parameters: List<Object?>.unmodifiable(parameters),
    );
  }

  /// Returns a same-length SQL surface where comments and quoted content are
  /// replaced by spaces. Safety checks and placeholder detection can therefore
  /// inspect executable SQL without false positives from literals/comments.
  String _sqlCodeSurface(String sql) {
    final output = StringBuffer();
    var index = 0;
    while (index < sql.length) {
      final char = sql[index];
      final next = index + 1 < sql.length ? sql[index + 1] : '';

      if (char == '-' && next == '-') {
        output.write('  ');
        index += 2;
        while (index < sql.length && sql[index] != '\n' && sql[index] != '\r') {
          output.write(' ');
          index++;
        }
        continue;
      }
      if (char == '/' && next == '*') {
        output.write('  ');
        index += 2;
        while (index < sql.length) {
          if (index + 1 < sql.length && sql[index] == '*' && sql[index + 1] == '/') {
            output.write('  ');
            index += 2;
            break;
          }
          output.write(sql[index] == '\n' || sql[index] == '\r' ? sql[index] : ' ');
          index++;
        }
        continue;
      }
      if (char == "'" || char == '"' || char == '`' || char == '[') {
        final close = char == '[' ? ']' : char;
        output.write(' ');
        index++;
        while (index < sql.length) {
          final current = sql[index];
          output.write(current == '\n' || current == '\r' ? current : ' ');
          index++;
          if (current != close) continue;
          if (close != ']' && index < sql.length && sql[index] == close) {
            output.write(' ');
            index++;
            continue;
          }
          break;
        }
        continue;
      }

      output.write(char);
      index++;
    }
    return output.toString();
  }
}

class _CompiledQuery {
  const _CompiledQuery({required this.sql, required this.parameters});

  final String sql;
  final List<Object?> parameters;
}
