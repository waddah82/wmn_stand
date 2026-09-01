import 'package:flutter/foundation.dart';

import '../adapters/wmn_platform_adapter.dart';
import '../adapters/wmn_platform_adapter_registry.dart';
import '../system/wmn_system_module.dart';
import '../system/wmn_system_module_registry.dart';
import '../features/wmn_feature_registry.dart';
import 'wmn_capability.dart';

/// Resolves stable runtime capability contracts independently from business
/// applications.
///
/// Module state decides which providers may execute. Capability state can then
/// disable optional contracts without scattering platform checks through UI or
/// application code. Required System Core capabilities remain protected.
class WmnCapabilityRegistry extends ChangeNotifier {
  WmnCapabilityRegistry(this.modules, {this.platformAdapters, this.features}) {
    modules.addListener(_moduleStateChanged);
    platformAdapters?.addListener(_platformStateChanged);
    features?.addListener(_featureStateChanged);
  }

  final WmnSystemModuleRegistry modules;
  final WmnPlatformAdapterRegistry? platformAdapters;
  final WmnFeatureRegistry? features;

  static const String contractVersion = '1.0.0';

  /// Capability-to-capability dependencies only. Module dependencies remain in
  /// [WmnSystemModuleRegistry] so the two graphs have one clear owner each.
  static const Map<String, List<String>> dependencyGraph = <String, List<String>>{
    'module-registry': <String>['lifecycle'],
    'app-manifest': <String>['module-registry'],
    'application-generator': <String>['app-manifest', 'dependency-graph'],
    'application-packaging': <String>['application-generator'],
    'application-package-install': <String>['application-packaging', 'metadata'],
    'dependency-graph': <String>['module-registry'],
    'enable-disable': <String>['dependency-graph'],
    'feature-registry': <String>['module-registry'],
    'entitlements': <String>['feature-registry'],
    'feature-activation': <String>['entitlements'],
    'roles': <String>['users'],
    'permissions': <String>['roles'],
    'identity-context': <String>['users', 'roles'],
    'permission-snapshot': <String>['identity-context', 'permissions'],
    'user-permissions': <String>['permission-snapshot'],
    'document-sharing': <String>['permission-snapshot'],
    'fields': <String>['doctype'],
    'metadata': <String>['doctype'],
    'customization': <String>['metadata'],
    'create': <String>['doctype', 'transactions'],
    'document-events': <String>['transactions'],
    'document-lifecycle': <String>['document-events', 'create'],
    'workflow-runtime': <String>['document-lifecycle', 'permission-snapshot'],
    'workflow-approvals': <String>['workflow-runtime'],
    'workflow-conditions': <String>['workflow-runtime'],
    'workflow-history': <String>['workflow-runtime'],
    'save': <String>['document-lifecycle'],
    'update': <String>['save'],
    'delete': <String>['save'],
    'submit': <String>['save'],
    'cancel': <String>['submit'],
    'links': <String>['doctype'],
    'child-tables': <String>['doctype'],
    'forms': <String>['doctype', 'save'],
    'lists': <String>['doctype'],
    'dialogs': <String>['forms'],
    'page-registry': <String>['metadata'],
    'page-runtime': <String>['page-registry', 'forms', 'lists'],
    'declarative-pages': <String>['page-runtime'],
    'page-controllers': <String>['page-runtime'],
    'workspace-registry': <String>['forms', 'lists'],
    'shortcuts': <String>['workspace-registry'],
    'quick-lists': <String>['workspace-registry'],
    'navigation': <String>['workspace-registry'],
    'attachments': <String>['files'],
    'storage-contract': <String>['files'],
    'file-integrity': <String>['files'],
    'file-dialog-contract': <String>['files'],
    'external-file-reference': <String>['files'],
    'files.pick': <String>['file-dialog-contract'],
    'files.pick-multiple': <String>['files.pick'],
    'files.save': <String>['file-dialog-contract'],
    'files.external-reference': <String>['external-file-reference', 'files.pick'],
    'print-jobs': <String>['print-contract'],
    'print-formats': <String>['print-contract'],
    'pdf-contract': <String>['print-contract'],
    'platform-print-adapters': <String>['print-contract'],
    'health-snapshot': <String>['diagnostics'],
    'background-jobs': <String>['scheduler'],
    'queues': <String>['scheduler'],
    'schedule-registry': <String>['scheduler'],
    'in-app-notifications': <String>['notification-outbox'],
    'mobile.scanner': <String>['mobile.camera'],
    'windows.scanner': <String>['windows.camera'],
  };

  static const List<WmnCapabilityProfile> profiles = <WmnCapabilityProfile>[
    WmnCapabilityProfile(
      id: 'minimal',
      requiredCapabilities: <String>['lifecycle', 'doctype', 'create', 'save'],
    ),
    WmnCapabilityProfile(
      id: 'windows_desktop',
      requiredCapabilities: <String>['lifecycle', 'doctype', 'forms', 'lists', 'platform.windows', 'filesystem'],
      optionalCapabilities: <String>['windows.printer-discovery', 'printing', 'usb', 'serial'],
    ),
    WmnCapabilityProfile(
      id: 'mobile_lite',
      requiredCapabilities: <String>['lifecycle', 'doctype', 'forms', 'lists', 'platform.mobile'],
      optionalCapabilities: <String>['mobile.permissions', 'mobile.contacts', 'mobile.sms.read', 'mobile.share', 'mobile.camera', 'mobile.scanner'],
    ),
    WmnCapabilityProfile(
      id: 'web_client',
      requiredCapabilities: <String>['lifecycle', 'doctype', 'forms', 'lists', 'platform.web'],
      optionalCapabilities: <String>['web.browser', 'web.download', 'web.storage', 'web.print'],
    ),
    WmnCapabilityProfile(
      id: 'server_multi_user',
      requiredCapabilities: <String>['lifecycle', 'doctype', 'transactions'],
      optionalCapabilities: <String>['platform.server', 'server.authentication', 'server.api', 'server.tokens', 'server.postgresql', 'background-jobs'],
    ),
    WmnCapabilityProfile(
      id: 'system_services',
      requiredCapabilities: <String>['lifecycle', 'files', 'system-settings', 'audit-log', 'diagnostics'],
      optionalCapabilities: <String>['scheduler', 'in-app-notifications', 'print-contract'],
    ),
  ];

  List<WmnCapabilityDescriptor> get capabilities {
    final providers = <String, List<WmnSystemModuleDefinition>>{};
    for (final module in WmnSystemModuleRegistry.definitions) {
      for (final capability in module.capabilities) {
        providers.putIfAbsent(capability, () => <WmnSystemModuleDefinition>[]).add(module);
      }
    }

    final result = <WmnCapabilityDescriptor>[];
    for (final entry in providers.entries) {
      final providerModules = entry.value;
      final enabledProviders = providerModules.where((module) => modules.isEnabled(module.id)).toList(growable: false);
      final executableProviders = enabledProviders.where((module) => module.executable).toList(growable: false);

      var status = executableProviders.isNotEmpty
          ? WmnCapabilityStatus.available
          : enabledProviders.any((module) => module.status == WmnSystemModuleStatus.deferred)
              ? WmnCapabilityStatus.deferred
              : enabledProviders.any((module) => module.status == WmnSystemModuleStatus.planned)
                  ? WmnCapabilityStatus.planned
                  : providerModules.any((module) => module.executable)
                      ? WmnCapabilityStatus.disabled
                      : providerModules.any((module) => module.status == WmnSystemModuleStatus.deferred)
                          ? WmnCapabilityStatus.deferred
                          : providerModules.any((module) => module.status == WmnSystemModuleStatus.planned)
                              ? WmnCapabilityStatus.planned
                              : WmnCapabilityStatus.unavailable;

      final adapters = platformAdapters;
      if (adapters != null && adapters.knownCapabilityIds.contains(entry.key)) {
        if (enabledProviders.isEmpty) {
          status = providerModules.any((module) => module.executable)
              ? WmnCapabilityStatus.disabled
              : WmnCapabilityStatus.unavailable;
        } else {
          final platformStatus = adapters.capabilityStatus(entry.key);
          if (platformStatus == WmnPlatformCapabilityStatus.available ||
              platformStatus == WmnPlatformCapabilityStatus.foundation) {
            status = WmnCapabilityStatus.available;
          } else if (platformStatus == WmnPlatformCapabilityStatus.planned) {
            status = WmnCapabilityStatus.planned;
          } else {
            status = WmnCapabilityStatus.unavailable;
          }
        }
      }

      if (!_isExplicitlyEnabled(entry.key) && status == WmnCapabilityStatus.available) {
        status = WmnCapabilityStatus.disabled;
      }

      final providerIds = providerModules.map((module) => module.id).toList(growable: false)..sort();
      final providerVersions = <String, String>{
        for (final provider in providerModules) provider.id: provider.version,
      };
      final List<String> supportedPlatforms;
      if (adapters != null && adapters.knownCapabilityIds.contains(entry.key)) {
        final resolvedPlatforms = adapters
            .supportedPlatformsForCapability(entry.key)
            .map((platform) => platform.name)
            .toList(growable: false);
        resolvedPlatforms.sort();
        supportedPlatforms = resolvedPlatforms;
      } else {
        supportedPlatforms = <String>['all'];
      }

      result.add(
        WmnCapabilityDescriptor(
          id: entry.key,
          contractVersion: contractVersion,
          providerModuleIds: providerIds,
          providerVersions: Map<String, String>.unmodifiable(providerVersions),
          status: status,
          enabledProviderModuleIds: enabledProviders.map((module) => module.id).toList(growable: false)..sort(),
          requiredCapabilities: List<String>.unmodifiable(dependencyGraph[entry.key] ?? const <String>[]),
          supportedPlatforms: List<String>.unmodifiable(supportedPlatforms),
          requiredByPlatform: providerModules.any((module) => module.required),
        ),
      );
    }
    result.sort((a, b) => a.id.compareTo(b.id));
    return result;
  }

  Set<String> get availableCapabilityIds => capabilities
      .where((capability) => capability.isAvailable)
      .map((capability) => capability.id)
      .toSet();

  bool isAvailable(String id) => descriptor(id)?.isAvailable ?? false;

  WmnCapabilityDescriptor? descriptor(String id) {
    for (final capability in capabilities) {
      if (capability.id == id) return capability;
    }
    return null;
  }

  List<String> dependenciesOf(String id) =>
      List<String>.unmodifiable(dependencyGraph[id] ?? const <String>[]);

  List<String> dependentsOf(String id) {
    final result = <String>[];
    for (final entry in dependencyGraph.entries) {
      if (entry.value.contains(id)) result.add(entry.key);
    }
    result.sort();
    return result;
  }

  List<String> enabledDependentsOf(String id) =>
      dependentsOf(id).where(isAvailable).toList(growable: false);

  /// Enables or disables an optional capability contract.
  ///
  /// Required System Core capabilities cannot be disabled. A capability also
  /// cannot be disabled while another available capability depends on it.
  bool updateEnabled(String id, bool enabled) {
    final capability = descriptor(id);
    if (capability == null) {
      throw StateError('Unknown WMN capability: $id');
    }
    if (!enabled) {
      if (!capability.canDisable || enabledDependentsOf(id).isNotEmpty) {
        return false;
      }
      modules.settings.setBool('system_capability.$id.enabled', false);
    } else {
      _enableWithDependencies(id, <String>{});
    }
    notifyListeners();
    return true;
  }

  List<String> missing(Iterable<String> ids) {
    final available = availableCapabilityIds;
    return ids.where((id) => !available.contains(id)).toSet().toList()..sort();
  }

  List<String> unavailableOptional(Iterable<String> ids) => missing(ids);

  WmnCapabilityProfile profile(String id) => profiles.firstWhere(
        (profile) => profile.id == id,
        orElse: () => throw StateError('Unknown WMN capability profile: $id'),
      );

  List<String> validateDependencyGraph() {
    final issues = <String>[];
    final ids = capabilities.map((entry) => entry.id).toSet();
    for (final entry in dependencyGraph.entries) {
      if (!ids.contains(entry.key)) {
        issues.add('Unknown capability dependency owner: ${entry.key}');
      }
      for (final dependency in entry.value) {
        if (!ids.contains(dependency)) {
          issues.add('${entry.key} depends on unknown capability $dependency');
        }
      }
    }
    for (final capability in capabilities.where((entry) => entry.isAvailable)) {
      final unavailableDependencies = capability.requiredCapabilities
          .where((dependency) => !isAvailable(dependency))
          .toList()
        ..sort();
      if (unavailableDependencies.isNotEmpty) {
        issues.add(
          'Available capability ${capability.id} requires unavailable capabilities: '
          '${unavailableDependencies.join(', ')}',
        );
      }
    }
    return issues;
  }

  @override
  void dispose() {
    modules.removeListener(_moduleStateChanged);
    platformAdapters?.removeListener(_platformStateChanged);
    features?.removeListener(_featureStateChanged);
    super.dispose();
  }

  bool _isExplicitlyEnabled(String id) =>
      (features?.isCapabilityEnabled(id) ?? true) &&
      modules.settings.getBool(
        'system_capability.$id.enabled',
        fallback: true,
      );

  void _enableWithDependencies(String id, Set<String> visiting) {
    if (!visiting.add(id)) {
      throw StateError('Circular WMN capability dependency involving $id');
    }
    if (descriptor(id) == null) {
      throw StateError('Unknown WMN capability: $id');
    }
    for (final dependency in dependenciesOf(id)) {
      _enableWithDependencies(dependency, visiting);
    }
    modules.settings.setBool('system_capability.$id.enabled', true);
    visiting.remove(id);
  }

  void _moduleStateChanged() => notifyListeners();
  void _platformStateChanged() => notifyListeners();
  void _featureStateChanged() => notifyListeners();
}
