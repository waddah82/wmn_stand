import 'dart:convert';
import 'dart:typed_data';

import '../../core/database/wmn_database.dart';
import 'wmn_database_storage_adapter.dart';
import 'wmn_storage_adapter.dart';
import 'wmn_storage_factory.dart';

/// Central content storage runtime.
///
/// Relational/queryable metadata stays in SQLite/PostgreSQL. Whole-object
/// content is addressed by stable storage keys and placed in an adapter.
///
/// Small text sources are cached because report SQL and managed scripts may be
/// read repeatedly. Large binary payloads should use the asynchronous methods.
class WmnStorageService {
  WmnStorageService(this.adapter);

  static final Expando<WmnStorageService> _databaseServices =
      Expando<WmnStorageService>('wmn-storage-service');

  static const int _maxTextCacheEntries = 128;
  static const int _maxCachedTextBytes = 64 * 1024;

  factory WmnStorageService.forDatabase(WmnDatabase database) {
    final existing = _databaseServices[database];
    if (existing != null) return existing;
    final service = database.info.isWeb
        ? WmnStorageService(WmnDatabaseStorageAdapter(database))
        : WmnStorageService(
            createNativeStorageAdapter(database.info.storageLocation),
          );
    _databaseServices[database] = service;
    if (service.isExternal) service._externalizeDatabaseBlobs(database);
    return service;
  }

  final WmnStorageAdapter adapter;
  final Map<String, String> _textCache = <String, String>{};

  String get adapterId => adapter.id;
  bool get isExternal => adapter.isExternal;

  void writeBytes(String key, Uint8List bytes) {
    final normalized = normalizeKey(key);
    adapter.write(normalized, bytes);
    _textCache.remove(normalized);
  }

  Uint8List readBytes(String key) => adapter.read(normalizeKey(key));

  bool exists(String key) => adapter.exists(normalizeKey(key));

  void delete(String key) {
    final normalized = normalizeKey(key);
    adapter.delete(normalized);
    _textCache.remove(normalized);
  }

  Future<void> writeBytesAsync(String key, Uint8List bytes) async {
    final normalized = normalizeKey(key);
    await adapter.writeAsync(normalized, bytes);
    _textCache.remove(normalized);
  }

  Future<Uint8List> readBytesAsync(String key) =>
      adapter.readAsync(normalizeKey(key));

  Future<bool> existsAsync(String key) =>
      adapter.existsAsync(normalizeKey(key));

  Future<void> deleteAsync(String key) async {
    final normalized = normalizeKey(key);
    await adapter.deleteAsync(normalized);
    _textCache.remove(normalized);
  }

  void writeText(String key, String value) {
    final normalized = normalizeKey(key);
    adapter.write(normalized, Uint8List.fromList(utf8.encode(value)));
    _cacheText(normalized, value);
  }

  String readText(String key) {
    final normalized = normalizeKey(key);
    final cached = _textCache[normalized];
    if (cached != null) {
      // Refresh insertion order so frequently used report/script sources stay
      // hot without introducing a separate cache dependency.
      _textCache
        ..remove(normalized)
        ..[normalized] = cached;
      return cached;
    }
    final value = utf8.decode(adapter.read(normalized));
    _cacheText(normalized, value);
    return value;
  }

  Future<void> writeTextAsync(String key, String value) async {
    final normalized = normalizeKey(key);
    await adapter.writeAsync(normalized, Uint8List.fromList(utf8.encode(value)));
    _cacheText(normalized, value);
  }

  Future<String> readTextAsync(String key) async {
    final normalized = normalizeKey(key);
    final cached = _textCache[normalized];
    if (cached != null) {
      _textCache
        ..remove(normalized)
        ..[normalized] = cached;
      return cached;
    }
    final value = utf8.decode(await adapter.readAsync(normalized));
    _cacheText(normalized, value);
    return value;
  }

  void clearTextCache() => _textCache.clear();

  void _cacheText(String normalizedKey, String value) {
    final estimatedBytes = utf8.encode(value).length;
    if (estimatedBytes > _maxCachedTextBytes) {
      _textCache.remove(normalizedKey);
      return;
    }
    _textCache
      ..remove(normalizedKey)
      ..[normalizedKey] = value;
    while (_textCache.length > _maxTextCacheEntries) {
      _textCache.remove(_textCache.keys.first);
    }
  }

  void _externalizeDatabaseBlobs(WmnDatabase database) {
    final table = database.db.select(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='wmn_storage_blobs' LIMIT 1;",
    );
    if (table.isEmpty) return;

    // Process one object at a time so a large legacy database is not copied
    // into application memory as a single ResultSet.
    while (true) {
      final rows = database.db.select(
        'SELECT storage_key,content FROM wmn_storage_blobs LIMIT 1;',
      );
      if (rows.isEmpty) break;
      final row = rows.first;
      final key = '${row['storage_key']}';
      final value = row['content'];
      final bytes = value is Uint8List
          ? value
          : value is List<int>
              ? Uint8List.fromList(value)
              : null;
      if (bytes == null) {
        throw StateError('Unsupported stored blob representation for: $key');
      }
      writeBytes(key, bytes);
      database.db.execute(
        'DELETE FROM wmn_storage_blobs WHERE storage_key=?;',
        [key],
      );
    }
  }

  String normalizeKey(String key) {
    var value = key.trim().replaceAll('\\', '/');
    while (value.startsWith('/')) {
      value = value.substring(1);
    }
    final parts = <String>[];
    for (final raw in value.split('/')) {
      final part = raw.trim();
      if (part.isEmpty || part == '.') continue;
      if (part == '..') throw StateError('Unsafe storage key: $key');
      parts.add(part);
    }
    if (parts.isEmpty) throw StateError('Storage key is required.');
    return parts.join('/');
  }
}
