import 'package:flutter/foundation.dart';

import 'mobile/wmn_mobile_platform_adapter.dart';
import 'server/wmn_server_platform_adapter.dart';
import 'web/wmn_web_platform_adapter.dart';
import 'windows/wmn_windows_platform_adapter.dart';
import 'wmn_platform_adapter.dart';

/// Central registry for host/platform adapters.
///
/// Applications consume capabilities and services through this registry. The
/// registry is the only layer that needs to know which operating system is
/// currently running WMN.
class WmnPlatformAdapterRegistry extends ChangeNotifier {
  WmnPlatformAdapterRegistry({
    List<WmnPlatformAdapter>? adapters,
    WmnRuntimePlatform? runtimePlatform,
  })  : runtimePlatform = runtimePlatform ?? detectWmnRuntimePlatform(),
        _adapters = adapters ??
            <WmnPlatformAdapter>[
              createWindowsPlatformAdapter(),
              createMobilePlatformAdapter(),
              WmnWebPlatformAdapter(),
              WmnServerPlatformAdapter(),
            ];

  final WmnRuntimePlatform runtimePlatform;
  final List<WmnPlatformAdapter> _adapters;
  bool _initialized = false;

  bool get initialized => _initialized;
  List<WmnPlatformAdapter> get adapters => List<WmnPlatformAdapter>.unmodifiable(_adapters);
  List<WmnPlatformAdapter> get activeAdapters =>
      _adapters.where((adapter) => adapter.supports(runtimePlatform)).toList(growable: false);

  String? get runtimeModuleId {
    for (final adapter in activeAdapters) {
      if (adapter.moduleId.isNotEmpty) return adapter.moduleId;
    }
    return null;
  }

  Set<String> get knownCapabilityIds => <String>{
        for (final adapter in _adapters)
          for (final capability in adapter.capabilities) capability.id,
      };

  Set<String> get availableCapabilityIds => <String>{
        for (final adapter in activeAdapters)
          for (final capability in adapter.capabilities)
            if (capability.isAvailable) capability.id,
      };

  Set<WmnRuntimePlatform> supportedPlatformsForCapability(String id) => <WmnRuntimePlatform>{
        for (final adapter in _adapters)
          if (adapter.capabilities.any((capability) => capability.id == id))
            ...adapter.supportedPlatforms,
      };

  List<String> get serviceIds {
    final ids = <String>{};
    for (final adapter in activeAdapters) {
      ids.addAll(adapter.services.keys);
    }
    final result = ids.toList()..sort();
    return result;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    for (final adapter in activeAdapters) {
      await adapter.initialize();
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> refresh() async {
    for (final adapter in activeAdapters) {
      await adapter.refresh();
    }
    notifyListeners();
  }

  WmnPlatformCapabilityStatus? capabilityStatus(String id) {
    final providers = <({WmnPlatformAdapter adapter, WmnPlatformCapability capability})>[];
    for (final adapter in _adapters) {
      for (final capability in adapter.capabilities) {
        if (capability.id == id) providers.add((adapter: adapter, capability: capability));
      }
    }
    if (providers.isEmpty) return null;

    final active = providers.where((entry) => entry.adapter.supports(runtimePlatform)).toList(growable: false);
    if (active.isEmpty) return WmnPlatformCapabilityStatus.unavailable;
    if (active.any((entry) => entry.capability.status == WmnPlatformCapabilityStatus.available)) {
      return WmnPlatformCapabilityStatus.available;
    }
    if (active.any((entry) => entry.capability.status == WmnPlatformCapabilityStatus.foundation)) {
      return WmnPlatformCapabilityStatus.foundation;
    }
    if (active.any((entry) => entry.capability.status == WmnPlatformCapabilityStatus.planned)) {
      return WmnPlatformCapabilityStatus.planned;
    }
    return WmnPlatformCapabilityStatus.unavailable;
  }

  bool isAvailable(String id) {
    final status = capabilityStatus(id);
    return status == WmnPlatformCapabilityStatus.available ||
        status == WmnPlatformCapabilityStatus.foundation;
  }

  T resolveService<T extends Object>(String id) {
    for (final adapter in activeAdapters) {
      final service = adapter.services[id];
      if (service == null) continue;
      if (service is! T) {
        throw StateError('WMN platform service $id is ${service.runtimeType}, not $T.');
      }
      return service;
    }
    throw StateError('WMN platform service is not available on ${wmnRuntimePlatformName(runtimePlatform)}: $id');
  }

  Object? tryResolveService(String id) {
    for (final adapter in activeAdapters) {
      final service = adapter.services[id];
      if (service != null) return service;
    }
    return null;
  }
}
