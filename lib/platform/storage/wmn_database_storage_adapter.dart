import 'dart:typed_data';

import '../../core/database/wmn_database.dart';
import 'wmn_storage_adapter.dart';

/// Web persistence fallback. Native Windows/Android/iOS builds use directory
/// storage instead. This adapter keeps the same contract until the web-native
/// OPFS adapter is completed in the Native Adapters phase.
class WmnDatabaseStorageAdapter implements WmnStorageAdapter {
  WmnDatabaseStorageAdapter(this.database);

  final WmnDatabase database;

  @override
  String get id => 'database-web-fallback';

  @override
  bool get isExternal => false;

  @override
  void write(String key, Uint8List bytes) {
    database.db.execute('''
      INSERT INTO wmn_storage_blobs(storage_key,content,updated_at)
      VALUES (?,?,?)
      ON CONFLICT(storage_key) DO UPDATE SET content=excluded.content,updated_at=excluded.updated_at;
    ''', [key, bytes, DateTime.now().toUtc().toIso8601String()]);
  }

  @override
  Uint8List read(String key) {
    final rows = database.db.select('SELECT content FROM wmn_storage_blobs WHERE storage_key=? LIMIT 1;', [key]);
    if (rows.isEmpty) throw StateError('Storage object not found: $key');
    final value = rows.first['content'];
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    throw StateError('Unsupported web storage representation for: $key');
  }

  @override
  bool exists(String key) => database.db.select(
        'SELECT 1 FROM wmn_storage_blobs WHERE storage_key=? LIMIT 1;',
        [key],
      ).isNotEmpty;

  @override
  void delete(String key) {
    database.db.execute('DELETE FROM wmn_storage_blobs WHERE storage_key=?;', [key]);
  }

  @override
  Future<void> writeAsync(String key, Uint8List bytes) async => write(key, bytes);

  @override
  Future<Uint8List> readAsync(String key) async => read(key);

  @override
  Future<bool> existsAsync(String key) async => exists(key);

  @override
  Future<void> deleteAsync(String key) async => delete(key);
}
