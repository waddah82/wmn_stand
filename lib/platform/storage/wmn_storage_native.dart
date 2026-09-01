import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'wmn_storage_adapter.dart';

WmnStorageAdapter createNativeStorageAdapter(String databaseLocation) {
  if (databaseLocation == ':memory:' || databaseLocation.startsWith('browser://')) {
    return WmnMemoryStorageAdapter();
  }
  final root = p.join(p.dirname(databaseLocation), 'wmn_storage');
  return WmnDirectoryStorageAdapter(root);
}

class WmnDirectoryStorageAdapter implements WmnStorageAdapter {
  WmnDirectoryStorageAdapter(this.rootPath) {
    Directory(rootPath).createSync(recursive: true);
  }

  final String rootPath;

  @override
  String get id => 'directory';

  @override
  bool get isExternal => true;

  @override
  void write(String key, Uint8List bytes) {
    final file = File(_resolve(key));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes, flush: true);
  }

  @override
  Uint8List read(String key) {
    final file = File(_resolve(key));
    if (!file.existsSync()) throw StateError('Storage object not found: $key');
    return file.readAsBytesSync();
  }

  @override
  bool exists(String key) => File(_resolve(key)).existsSync();

  @override
  void delete(String key) {
    final file = File(_resolve(key));
    if (file.existsSync()) file.deleteSync();
  }

  @override
  Future<void> writeAsync(String key, Uint8List bytes) async {
    final file = File(_resolve(key));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<Uint8List> readAsync(String key) async {
    final file = File(_resolve(key));
    if (!await file.exists()) throw StateError('Storage object not found: $key');
    return file.readAsBytes();
  }

  @override
  Future<bool> existsAsync(String key) => File(_resolve(key)).exists();

  @override
  Future<void> deleteAsync(String key) async {
    final file = File(_resolve(key));
    if (await file.exists()) await file.delete();
  }

  String _resolve(String key) {
    final normalized = p.posix.normalize(key.replaceAll('\\', '/'));
    if (normalized == '.' ||
        normalized.startsWith('../') ||
        normalized.contains('/../') ||
        p.posix.isAbsolute(normalized)) {
      throw StateError('Unsafe storage key: $key');
    }
    final segments = normalized
        .split('/')
        .where((part) => part.isNotEmpty && part != '.')
        .toList(growable: false);
    if (segments.isEmpty) throw StateError('Storage key is required.');
    return p.joinAll(<String>[rootPath, ...segments]);
  }
}
