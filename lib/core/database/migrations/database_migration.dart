import 'package:sqlite3/common.dart';

abstract interface class DatabaseMigration {
  int get version;
  String get name;
  void apply(CommonDatabase database);
}

abstract class SqlDatabaseMigration implements DatabaseMigration {
  const SqlDatabaseMigration();

  String get sql;

  @override
  void apply(CommonDatabase database) {
    for (final statement in _splitSqlStatements(sql)) {
      database.execute(statement);
    }
  }
}

List<String> _splitSqlStatements(String script) {
  final statements = <String>[];
  final buffer = StringBuffer();
  var inSingleQuote = false;

  for (var index = 0; index < script.length; index++) {
    final char = script[index];
    if (char == "'") {
      final escapedQuote = inSingleQuote && index + 1 < script.length && script[index + 1] == "'";
      if (escapedQuote) {
        buffer.write("''");
        index++;
        continue;
      }
      inSingleQuote = !inSingleQuote;
      buffer.write(char);
      continue;
    }

    if (char == ';' && !inSingleQuote) {
      final statement = buffer.toString().trim();
      if (statement.isNotEmpty) statements.add(statement);
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }

  final tail = buffer.toString().trim();
  if (tail.isNotEmpty) statements.add(tail);
  return statements;
}
