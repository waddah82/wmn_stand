import '../storage/wmn_storage_service.dart';

typedef WmnNativeScriptHandler = Object? Function(Map<String, Object?> context);
typedef WmnManagedScriptExecutor = Object? Function(
  String source,
  Map<String, Object?> context,
);

/// Cross-platform script/code runtime.
///
/// Native Dart handlers are compiled with the application. Managed script
/// sources can live in WMN storage and are executed only by an explicitly
/// registered language executor. WMN never evals arbitrary Dart/JS/Python.
class WmnScriptRuntime {
  WmnScriptRuntime({required this.storage});

  final WmnStorageService storage;
  final Map<String, WmnNativeScriptHandler> _nativeHandlers = <String, WmnNativeScriptHandler>{};
  final Map<String, WmnManagedScriptExecutor> _managedExecutors = <String, WmnManagedScriptExecutor>{};

  void registerNativeHandler(String key, WmnNativeScriptHandler handler) {
    final normalized = key.trim();
    if (normalized.isEmpty) throw StateError('Native script handler key is required.');
    _nativeHandlers[normalized] = handler;
  }

  bool hasNativeHandler(String key) => _nativeHandlers.containsKey(key.trim());

  void registerManagedExecutor(String language, WmnManagedScriptExecutor executor) {
    final normalized = language.trim().toLowerCase();
    if (normalized.isEmpty) throw StateError('Managed script language is required.');
    _managedExecutors[normalized] = executor;
  }

  bool hasManagedExecutor(String language) => _managedExecutors.containsKey(language.trim().toLowerCase());

  Object? executeNative(String key, Map<String, Object?> context) {
    final handler = _nativeHandlers[key.trim()];
    if (handler == null) throw StateError('Native script handler is not registered: $key');
    return handler(Map<String, Object?>.unmodifiable(context));
  }

  Object? executeStored({
    required String path,
    required String language,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    final executor = _managedExecutors[language.trim().toLowerCase()];
    if (executor == null) {
      throw StateError('No managed script executor is registered for language: $language');
    }
    final source = storage.readText(path);
    return executor(source, Map<String, Object?>.unmodifiable(context));
  }

  void saveSource({required String path, required String source}) {
    if (source.trim().isEmpty) throw StateError('Script source cannot be empty.');
    storage.writeText(path, source);
  }

  String readSource(String path) => storage.readText(path);
  bool sourceExists(String path) => storage.exists(path);
  void deleteSource(String path) => storage.delete(path);
}
