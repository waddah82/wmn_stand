import 'dart:typed_data';

/// Physical storage contract used by WMN for content that should not live in
/// relational tables (attachments, application assets, generated files,
/// report/query sources and managed scripts).
///
/// The synchronous API is intentionally retained for small runtime sources
/// such as report SQL and managed scripts. Large file/attachment operations
/// should use the asynchronous API to avoid blocking the Flutter UI isolate.
abstract interface class WmnStorageAdapter {
  String get id;
  bool get isExternal;

  void write(String key, Uint8List bytes);
  Uint8List read(String key);
  bool exists(String key);
  void delete(String key);

  Future<void> writeAsync(String key, Uint8List bytes);
  Future<Uint8List> readAsync(String key);
  Future<bool> existsAsync(String key);
  Future<void> deleteAsync(String key);
}

class WmnMemoryStorageAdapter implements WmnStorageAdapter {
  final Map<String, Uint8List> _objects = <String, Uint8List>{};

  @override
  String get id => 'memory';

  @override
  bool get isExternal => true;

  @override
  void write(String key, Uint8List bytes) {
    _objects[key] = Uint8List.fromList(bytes);
  }

  @override
  Uint8List read(String key) {
    final value = _objects[key];
    if (value == null) throw StateError('Storage object not found: $key');
    return Uint8List.fromList(value);
  }

  @override
  bool exists(String key) => _objects.containsKey(key);

  @override
  void delete(String key) => _objects.remove(key);

  @override
  Future<void> writeAsync(String key, Uint8List bytes) async => write(key, bytes);

  @override
  Future<Uint8List> readAsync(String key) async => read(key);

  @override
  Future<bool> existsAsync(String key) async => exists(key);

  @override
  Future<void> deleteAsync(String key) async => delete(key);
}
