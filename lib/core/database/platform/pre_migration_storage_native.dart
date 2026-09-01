import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqlite3/common.dart';

/// Native-only preparation for the R3.15 transition.
///
/// A byte-for-byte v25 database backup is created before any schema mutation.
/// Legacy attachment BLOBs are then externalized directly to wmn_storage one
/// object at a time, avoiding a second full BLOB copy inside SQLite during the
/// v26 migration.
Future<String?> prepareWmnDatabaseForMigration(
  CommonDatabase database, {
  required String storageLocation,
  required int currentVersion,
}) async {
  if (currentVersion != 25 ||
      storageLocation == ':memory:' ||
      storageLocation.startsWith('browser://')) {
    return null;
  }

  final databaseFile = File(storageLocation);
  if (!await databaseFile.exists()) return null;

  // Ensure the main file contains all committed WAL frames before copying it.
  database.execute('PRAGMA wal_checkpoint(TRUNCATE);');

  final stamp = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(RegExp(r'[^0-9]'), '')
      .substring(0, 14);
  final backupPath = p.join(
    p.dirname(storageLocation),
    'wmn_platform_pre_r315_v25_$stamp.sqlite3',
  );
  await databaseFile.copy(backupPath);

  if (!_tableExists(database, 'wmn_file_contents') ||
      !_tableExists(database, 'wmn_files')) {
    return backupPath;
  }

  final root = Directory(p.join(p.dirname(storageLocation), 'wmn_storage'));
  await root.create(recursive: true);

  while (true) {
    final rows = database.select('''
      SELECT f.id,f.file_name,f.is_private,c.content
      FROM wmn_files f
      JOIN wmn_file_contents c ON c.file_id=f.id
      LIMIT 1;
    ''');
    if (rows.isEmpty) break;

    final row = rows.first;
    final id = '${row['id']}';
    final fileName = '${row['file_name']}';
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    final key = 'files/${row['is_private'] == 1 ? 'private' : 'public'}/$id/$safeName';
    final value = row['content'];
    final bytes = value is Uint8List
        ? value
        : value is List<int>
            ? Uint8List.fromList(value)
            : null;
    if (bytes == null) {
      throw StateError('Unsupported legacy attachment representation: $id');
    }

    final target = File(_resolveStoragePath(root.path, key));
    await target.parent.create(recursive: true);
    await target.writeAsBytes(bytes, flush: true);

    database.execute(
      'UPDATE wmn_files SET storage_path=?,file_url=? WHERE id=?;',
      [key, 'wmn://$key', id],
    );
    database.execute(
      'DELETE FROM wmn_file_contents WHERE file_id=?;',
      [id],
    );
  }

  return backupPath;
}

bool _tableExists(CommonDatabase database, String table) => database.select(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;",
      [table],
    ).isNotEmpty;

String _resolveStoragePath(String rootPath, String key) {
  final normalized = p.posix.normalize(key.replaceAll('\\', '/'));
  if (normalized == '.' ||
      normalized.startsWith('../') ||
      normalized.contains('/../') ||
      p.posix.isAbsolute(normalized)) {
    throw StateError('Unsafe storage key during migration: $key');
  }
  final segments = normalized
      .split('/')
      .where((part) => part.isNotEmpty && part != '.')
      .toList(growable: false);
  if (segments.isEmpty) throw StateError('Storage key is required.');
  return p.joinAll(<String>[rootPath, ...segments]);
}
