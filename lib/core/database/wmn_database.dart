import 'package:sqlite3/common.dart';

import 'migrations/migration_runner.dart';
import 'platform/database_opener.dart';
import 'platform/pre_migration_storage.dart';

class WmnDatabaseInfo {
  const WmnDatabaseInfo({
    required this.storageKind,
    required this.storageLocation,
    required this.isWeb,
    required this.schemaVersion,
  });

  final String storageKind;
  final String storageLocation;
  final bool isWeb;
  final int schemaVersion;
}

class WmnDatabase {
  WmnDatabase._(this.db, this.info);

  static const DatabaseMigrationRunner _migrationRunner = DatabaseMigrationRunner();
  static final int schemaVersion = _migrationRunner.latestVersion;

  final CommonDatabase db;
  final WmnDatabaseInfo info;

  int _transactionDepth = 0;
  int _savepointSerial = 0;

  static WmnDatabase forTesting(CommonDatabase database) {
    _configureDatabase(database, isWeb: false);
    _migrationRunner.migrate(database);
    return WmnDatabase._(
      database,
      WmnDatabaseInfo(
        storageKind: 'SQLite in-memory test database',
        storageLocation: ':memory:',
        isWeb: false,
        schemaVersion: schemaVersion,
      ),
    );
  }

  static Future<WmnDatabase> open() async {
    final opened = await openWmnDatabase();
    _configureDatabase(opened.database, isWeb: opened.isWeb);
    final previousVersion = _readSchemaVersion(opened.database);
    final rollbackBackup = await prepareWmnDatabaseForMigration(
      opened.database,
      storageLocation: opened.storageLocation,
      currentVersion: previousVersion,
    );
    _migrationRunner.migrate(opened.database);
    if (rollbackBackup != null) {
      opened.database.execute('''
        INSERT INTO system_meta(key,value,updated_at)
        VALUES ('r315_rollback_backup',?,?)
        ON CONFLICT(key) DO UPDATE SET value=excluded.value,updated_at=excluded.updated_at;
      ''', [rollbackBackup, DateTime.now().toUtc().toIso8601String()]);
    }
    return WmnDatabase._(
      opened.database,
      WmnDatabaseInfo(
        storageKind: opened.storageKind,
        storageLocation: opened.storageLocation,
        isWeb: opened.isWeb,
        schemaVersion: schemaVersion,
      ),
    );
  }

  static int _readSchemaVersion(CommonDatabase database) {
    final table = database.select(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='system_meta' LIMIT 1;",
    );
    if (table.isEmpty) return 0;
    final rows = database.select(
      "SELECT value FROM system_meta WHERE key='schema_version' LIMIT 1;",
    );
    if (rows.isEmpty) return 0;
    return int.tryParse('${rows.first['value']}') ?? 0;
  }

  static void _configureDatabase(CommonDatabase database, {required bool isWeb}) {
    database.execute('PRAGMA foreign_keys = ON;');
    database.execute('PRAGMA busy_timeout = 5000;');
    if (!isWeb) {
      database.execute('PRAGMA journal_mode = WAL;');
      database.execute('PRAGMA synchronous = NORMAL;');
    }
  }

  T transaction<T>(T Function() action) {
    if (_transactionDepth == 0) {
      db.execute('BEGIN IMMEDIATE;');
      _transactionDepth = 1;
      try {
        final result = action();
        db.execute('COMMIT;');
        return result;
      } catch (_) {
        db.execute('ROLLBACK;');
        rethrow;
      } finally {
        _transactionDepth = 0;
      }
    }

    final savepoint = 'wmn_nested_tx_${++_savepointSerial}';
    db.execute('SAVEPOINT $savepoint;');
    _transactionDepth += 1;
    try {
      final result = action();
      db.execute('RELEASE SAVEPOINT $savepoint;');
      return result;
    } catch (_) {
      db.execute('ROLLBACK TO SAVEPOINT $savepoint;');
      db.execute('RELEASE SAVEPOINT $savepoint;');
      rethrow;
    } finally {
      _transactionDepth -= 1;
    }
  }

  void close() => db.close();
}
