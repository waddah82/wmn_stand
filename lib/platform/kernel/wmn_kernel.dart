import 'package:flutter/foundation.dart';

import '../apps/wmn_application_registry.dart';
import '../capabilities/wmn_capability_registry.dart';
import '../system/wmn_system_module_registry.dart';
import 'wmn_extension_registry.dart';
import 'wmn_service_registry.dart';

enum WmnKernelState {
  created,
  starting,
  ready,
  degraded,
  stopped,
}

class WmnKernelHealth {
  const WmnKernelHealth({
    required this.state,
    required this.startedAt,
    required this.issues,
    required this.registeredServices,
    required this.availableCapabilities,
    required this.enabledModules,
    required this.installedApplications,
  });

  final WmnKernelState state;
  final DateTime? startedAt;
  final List<String> issues;
  final int registeredServices;
  final int availableCapabilities;
  final int enabledModules;
  final int installedApplications;

  bool get healthy => state == WmnKernelState.ready && issues.isEmpty;
}

/// WMN platform lifecycle and dependency boundary.
///
/// The kernel knows only platform registries and services. It intentionally has
/// no concepts such as Invoice, Account, Stock or any future application domain.
class WmnKernel extends ChangeNotifier {
  WmnKernel({
    required this.modules,
    required this.capabilities,
    required this.applications,
    WmnServiceRegistry? services,
    WmnExtensionRegistry? extensions,
  })  : services = services ?? WmnServiceRegistry(),
        extensions = extensions ?? WmnExtensionRegistry() {
    modules.addListener(refreshHealth);
    capabilities.addListener(refreshHealth);
    applications.addListener(refreshHealth);
  }

  final WmnSystemModuleRegistry modules;
  final WmnCapabilityRegistry capabilities;
  final WmnApplicationRegistry applications;
  final WmnServiceRegistry services;
  final WmnExtensionRegistry extensions;

  WmnKernelState _state = WmnKernelState.created;
  DateTime? _startedAt;
  List<String> _issues = const <String>[];

  WmnKernelState get state => _state;
  DateTime? get startedAt => _startedAt;
  List<String> get issues => List<String>.unmodifiable(_issues);

  void start() {
    if (_state == WmnKernelState.ready || _state == WmnKernelState.degraded) {
      return;
    }
    _state = WmnKernelState.starting;
    notifyListeners();

    final issues = <String>[
      ...modules.validateDependencyGraph(),
      ...capabilities.validateDependencyGraph(),
      ...applications.platformIssues(),
    ];
    _issues = issues;
    _startedAt ??= DateTime.now().toUtc();
    _state = issues.isEmpty ? WmnKernelState.ready : WmnKernelState.degraded;
    notifyListeners();
  }

  void refreshHealth() {
    if (_state == WmnKernelState.stopped) {
      return;
    }
    final issues = <String>[
      ...modules.validateDependencyGraph(),
      ...capabilities.validateDependencyGraph(),
      ...applications.platformIssues(),
    ];
    _issues = issues;
    _state = issues.isEmpty ? WmnKernelState.ready : WmnKernelState.degraded;
    notifyListeners();
  }

  void stop() {
    if (_state == WmnKernelState.stopped) {
      return;
    }
    _state = WmnKernelState.stopped;
    notifyListeners();
  }

  WmnKernelHealth snapshot() => WmnKernelHealth(
        state: _state,
        startedAt: _startedAt,
        issues: List<String>.unmodifiable(_issues),
        registeredServices: services.serviceIds.length,
        availableCapabilities: capabilities.availableCapabilityIds.length,
        enabledModules: WmnSystemModuleRegistry.definitions.where((entry) => modules.isEnabled(entry.id)).length,
        installedApplications: applications.applications().length,
      );
  @override
  void dispose() {
    modules.removeListener(refreshHealth);
    capabilities.removeListener(refreshHealth);
    applications.removeListener(refreshHealth);
    super.dispose();
  }

}
