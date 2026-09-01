class WmnServiceRegistry {
  final Map<String, Object> _services = <String, Object>{};

  List<String> get serviceIds => _services.keys.toList(growable: false)..sort();

  void register<T extends Object>(String id, T service, {bool replace = false}) {
    final normalized = id.trim();
    if (normalized.isEmpty) {
      throw StateError('WMN service id is required.');
    }
    if (_services.containsKey(normalized) && !replace) {
      throw StateError('WMN service is already registered: $normalized');
    }
    _services[normalized] = service;
  }

  bool contains(String id) => _services.containsKey(id);

  T resolve<T extends Object>(String id) {
    final service = _services[id];
    if (service == null) {
      throw StateError('WMN service is not registered: $id');
    }
    if (service is! T) {
      throw StateError('WMN service $id is ${service.runtimeType}, not the requested $T.');
    }
    return service;
  }

  Object? tryResolve(String id) => _services[id];
}
