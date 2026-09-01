import 'package:flutter/material.dart';

import '../../core/settings/settings_repository.dart';
import 'wmn_system_module.dart';

class WmnSystemModuleRegistry extends ChangeNotifier {
  WmnSystemModuleRegistry(this.settings);

  final SettingsRepository settings;

  /// Platform-only dependency graph. Business applications never appear here.
  static const Map<String, List<String>> dependencyGraph = <String, List<String>>{
    'modules': <String>['kernel'],
    'data': <String>['kernel'],
    'settings': <String>['kernel', 'data'],
    'localization': <String>['settings'],
    'metadata': <String>['modules', 'data'],
    'audit': <String>['data'],
    'diagnostics': <String>['kernel', 'data', 'settings'],
    'documents': <String>['metadata', 'data'],
    'methods': <String>['kernel', 'documents'],
    'scripts': <String>['methods', 'documents'],
    'ui': <String>['metadata', 'documents', 'localization', 'settings'],
    'workspaces': <String>['ui', 'metadata', 'modules'],
    'reports': <String>['metadata', 'data'],
    'files': <String>['kernel', 'data'],
    'printing': <String>['kernel', 'data'],
    'import_export': <String>['metadata', 'documents'],
    'security': <String>['documents', 'settings'],
    'workflow': <String>['documents', 'security'],
    'scheduler': <String>['kernel', 'data'],
    'notifications': <String>['kernel', 'data'],
    'sync': <String>['documents', 'data'],
    'server': <String>['security', 'scheduler'],
    'mobile': <String>['kernel'],
    'windows': <String>['kernel'],
    'web': <String>['kernel'],
    'developer': <String>['metadata', 'methods', 'reports', 'diagnostics'],
  };

  static const List<WmnSystemModuleDefinition> definitions = [
    WmnSystemModuleDefinition(
      id: 'kernel',
      labelKey: 'system_module_kernel',
      descriptionKey: 'system_module_kernel_help',
      icon: Icons.memory_outlined,
      group: WmnSystemModuleGroup.foundation,
      status: WmnSystemModuleStatus.ready,
      required: true,
      capabilities: ['lifecycle', 'errors', 'service-registry', 'capabilities'],
    ),
    WmnSystemModuleDefinition(
      id: 'modules',
      labelKey: 'system_module_modules',
      descriptionKey: 'system_module_modules_help',
      icon: Icons.grid_view_outlined,
      group: WmnSystemModuleGroup.foundation,
      status: WmnSystemModuleStatus.foundation,
      required: true,
      capabilities: ['module-registry', 'app-manifest', 'dependency-graph', 'application-generator', 'application-packaging', 'application-package-install', 'enable-disable', 'feature-registry', 'entitlements', 'feature-activation'],
    ),
    WmnSystemModuleDefinition(
      id: 'metadata',
      labelKey: 'system_module_metadata',
      descriptionKey: 'system_module_metadata_help',
      icon: Icons.schema_outlined,
      group: WmnSystemModuleGroup.foundation,
      status: WmnSystemModuleStatus.ready,
      required: true,
      capabilities: ['doctype', 'fields', 'metadata', 'customization'],
    ),
    WmnSystemModuleDefinition(
      id: 'documents',
      labelKey: 'system_module_documents',
      descriptionKey: 'system_module_documents_help',
      icon: Icons.description_outlined,
      group: WmnSystemModuleGroup.foundation,
      status: WmnSystemModuleStatus.ready,
      required: true,
      capabilities: [
        'create',
        'save',
        'update',
        'delete',
        'submit',
        'cancel',
        'links',
        'child-tables',
        'document-events',
        'document-lifecycle',
      ],
    ),
    WmnSystemModuleDefinition(
      id: 'data',
      labelKey: 'system_module_data',
      descriptionKey: 'system_module_data_help',
      icon: Icons.storage_outlined,
      group: WmnSystemModuleGroup.foundation,
      status: WmnSystemModuleStatus.ready,
      required: true,
      capabilities: ['sqlite', 'transactions', 'query-contracts', 'migrations'],
    ),
    WmnSystemModuleDefinition(
      id: 'methods',
      labelKey: 'system_module_methods',
      descriptionKey: 'system_module_methods_help',
      icon: Icons.data_object_outlined,
      group: WmnSystemModuleGroup.foundation,
      status: WmnSystemModuleStatus.foundation,
      required: true,
      capabilities: ['system-method-modules', 'custom-method-modules', 'validation', 'revisions'],
    ),
    WmnSystemModuleDefinition(
      id: 'scripts',
      labelKey: 'system_module_scripts',
      descriptionKey: 'system_module_scripts_help',
      icon: Icons.code_outlined,
      group: WmnSystemModuleGroup.foundation,
      status: WmnSystemModuleStatus.foundation,
      capabilities: ['client-code', 'server-hooks', 'events', 'safe-runtime'],
    ),
    WmnSystemModuleDefinition(
      id: 'ui',
      labelKey: 'system_module_ui',
      descriptionKey: 'system_module_ui_help',
      icon: Icons.space_dashboard_outlined,
      group: WmnSystemModuleGroup.experience,
      status: WmnSystemModuleStatus.ready,
      required: true,
      capabilities: [
        'shell',
        'forms',
        'lists',
        'dialogs',
        'responsive-layout',
        'page-registry',
        'page-runtime',
        'declarative-pages',
        'page-controllers',
      ],
    ),
    WmnSystemModuleDefinition(
      id: 'workspaces',
      labelKey: 'system_module_workspaces',
      descriptionKey: 'system_module_workspaces_help',
      icon: Icons.dashboard_customize_outlined,
      group: WmnSystemModuleGroup.experience,
      status: WmnSystemModuleStatus.ready,
      capabilities: ['workspace-registry', 'shortcuts', 'quick-lists', 'navigation'],
    ),
    WmnSystemModuleDefinition(
      id: 'reports',
      labelKey: 'system_module_reports',
      descriptionKey: 'system_module_reports_help',
      icon: Icons.analytics_outlined,
      group: WmnSystemModuleGroup.services,
      status: WmnSystemModuleStatus.foundation,
      capabilities: ['report-builder', 'query-reports', 'native-reports', 'export'],
    ),
    WmnSystemModuleDefinition(
      id: 'files',
      labelKey: 'system_module_files',
      descriptionKey: 'system_module_files_help',
      icon: Icons.folder_open_outlined,
      group: WmnSystemModuleGroup.services,
      status: WmnSystemModuleStatus.ready,
      capabilities: ['files', 'attachments', 'storage-contract', 'file-integrity', 'file-dialog-contract', 'external-file-reference'],
    ),
    WmnSystemModuleDefinition(
      id: 'printing',
      labelKey: 'system_module_printing',
      descriptionKey: 'system_module_printing_help',
      icon: Icons.print_outlined,
      group: WmnSystemModuleGroup.services,
      status: WmnSystemModuleStatus.ready,
      capabilities: ['print-contract', 'print-jobs', 'print-formats', 'html-renderer', 'pdf-renderer', 'escpos', 'barcode', 'qr', 'pdf-contract', 'platform-print-adapters'],
    ),
    WmnSystemModuleDefinition(
      id: 'import_export',
      labelKey: 'system_module_import_export',
      descriptionKey: 'system_module_import_export_help',
      icon: Icons.swap_vert_circle_outlined,
      group: WmnSystemModuleGroup.services,
      status: WmnSystemModuleStatus.ready,
      capabilities: ['csv', 'xlsx', 'templates', 'validation'],
    ),
    WmnSystemModuleDefinition(
      id: 'localization',
      labelKey: 'system_module_localization',
      descriptionKey: 'system_module_localization_help',
      icon: Icons.translate_outlined,
      group: WmnSystemModuleGroup.services,
      status: WmnSystemModuleStatus.ready,
      required: true,
      capabilities: ['i18n', 'rtl', 'locale', 'formatting'],
    ),
    WmnSystemModuleDefinition(
      id: 'settings',
      labelKey: 'system_module_settings',
      descriptionKey: 'system_module_settings_help',
      icon: Icons.tune_outlined,
      group: WmnSystemModuleGroup.services,
      status: WmnSystemModuleStatus.ready,
      required: true,
      capabilities: ['system-settings', 'app-settings', 'platform-settings', 'configuration-profiles', 'preferences'],
    ),
    WmnSystemModuleDefinition(
      id: 'security',
      labelKey: 'system_module_security',
      descriptionKey: 'system_module_security_help',
      icon: Icons.shield_outlined,
      group: WmnSystemModuleGroup.services,
      status: WmnSystemModuleStatus.ready,
      required: true,
      capabilities: <String>[
        'users','roles','permissions','identity-context',
        'permission-snapshot','user-permissions','document-sharing',
      ],
    ),
    WmnSystemModuleDefinition(
      id: 'workflow',
      labelKey: 'system_module_workflow',
      descriptionKey: 'system_module_workflow_help',
      icon: Icons.account_tree_outlined,
      group: WmnSystemModuleGroup.services,
      status: WmnSystemModuleStatus.ready,
      capabilities: <String>[
        'workflow-runtime',
        'workflow-approvals',
        'workflow-conditions',
        'workflow-history',
      ],
    ),
    WmnSystemModuleDefinition(
      id: 'scheduler',
      labelKey: 'system_module_scheduler',
      descriptionKey: 'system_module_scheduler_help',
      icon: Icons.schedule_outlined,
      group: WmnSystemModuleGroup.services,
      status: WmnSystemModuleStatus.foundation,
      defaultEnabled: false,
      capabilities: ['scheduler', 'background-jobs', 'queues', 'schedule-registry'],
    ),
    WmnSystemModuleDefinition(
      id: 'audit',
      labelKey: 'system_module_audit',
      descriptionKey: 'system_module_audit_help',
      icon: Icons.fact_check_outlined,
      group: WmnSystemModuleGroup.services,
      status: WmnSystemModuleStatus.ready,
      capabilities: ['audit-log', 'versions', 'change-history'],
    ),
    WmnSystemModuleDefinition(
      id: 'diagnostics',
      labelKey: 'system_module_diagnostics',
      descriptionKey: 'system_module_diagnostics_help',
      icon: Icons.monitor_heart_outlined,
      group: WmnSystemModuleGroup.services,
      status: WmnSystemModuleStatus.ready,
      capabilities: ['system-logs', 'diagnostics', 'health-snapshot'],
    ),
    WmnSystemModuleDefinition(
      id: 'notifications',
      labelKey: 'system_module_notifications',
      descriptionKey: 'system_module_notifications_help',
      icon: Icons.notifications_outlined,
      group: WmnSystemModuleGroup.services,
      status: WmnSystemModuleStatus.foundation,
      defaultEnabled: false,
      capabilities: ['in-app-notifications', 'notification-outbox', 'email-contract', 'sms-contract', 'push-contract'],
    ),
    WmnSystemModuleDefinition(
      id: 'sync',
      labelKey: 'system_module_sync',
      descriptionKey: 'system_module_sync_help',
      icon: Icons.sync_outlined,
      group: WmnSystemModuleGroup.services,
      status: WmnSystemModuleStatus.planned,
      defaultEnabled: false,
      capabilities: ['offline', 'sync', 'conflict-resolution'],
    ),
    WmnSystemModuleDefinition(
      id: 'server',
      labelKey: 'system_module_server',
      descriptionKey: 'system_module_server_help',
      icon: Icons.dns_outlined,
      group: WmnSystemModuleGroup.platform,
      status: WmnSystemModuleStatus.planned,
      defaultEnabled: false,
      capabilities: ['platform.server', 'api', 'tokens', 'postgresql', 'server-mode', 'jobs', 'server.api', 'server.tokens', 'server.authentication', 'server.postgresql', 'server.sync', 'server.jobs', 'server.files', 'server.health'],
    ),
    WmnSystemModuleDefinition(
      id: 'mobile',
      labelKey: 'system_module_mobile',
      descriptionKey: 'system_module_mobile_help',
      icon: Icons.smartphone_outlined,
      group: WmnSystemModuleGroup.platform,
      status: WmnSystemModuleStatus.foundation,
      defaultEnabled: false,
      capabilities: ['platform.mobile', 'mobile.device-info', 'mobile.filesystem', 'files.pick', 'files.pick-multiple', 'files.save', 'files.external-reference', 'external-open', 'browser', 'clipboard', 'connectivity', 'device-info', 'permissions', 'contacts', 'sms', 'share', 'camera', 'scanner', 'mobile.permissions', 'mobile.contacts', 'mobile.sms.read', 'mobile.sms.send', 'mobile.share', 'mobile.whatsapp.share', 'mobile.camera', 'mobile.scanner', 'mobile.secure-storage', 'mobile.bluetooth-gatt', 'mobile.connectivity'],
    ),
    WmnSystemModuleDefinition(
      id: 'windows',
      labelKey: 'system_module_windows',
      descriptionKey: 'system_module_windows_help',
      icon: Icons.desktop_windows_outlined,
      group: WmnSystemModuleGroup.platform,
      status: WmnSystemModuleStatus.foundation,
      capabilities: ['platform.windows', 'filesystem', 'windows.filesystem', 'files.pick', 'files.pick-multiple', 'files.save', 'files.external-reference', 'system-info', 'windows.system-info', 'shell', 'windows.shell', 'external-open', 'share', 'windows.share', 'clipboard', 'windows.clipboard', 'connectivity', 'windows.connectivity', 'device-info', 'devices', 'windows.device-discovery', 'windows.printer-discovery', 'windows.serial-discovery', 'printing', 'usb', 'serial', 'windows.usb', 'windows.serial', 'windows.bluetooth', 'windows.network-devices', 'windows.camera', 'windows.scanner'],
    ),
    WmnSystemModuleDefinition(
      id: 'web',
      labelKey: 'system_module_web',
      descriptionKey: 'system_module_web_help',
      icon: Icons.language_outlined,
      group: WmnSystemModuleGroup.platform,
      status: WmnSystemModuleStatus.foundation,
      defaultEnabled: false,
      capabilities: ['platform.web', 'browser', 'download', 'external-open', 'share', 'clipboard', 'connectivity', 'device-info', 'web-storage', 'files.pick', 'files.pick-multiple', 'files.save', 'files.external-reference', 'web-print', 'web.browser', 'web.download', 'web.upload', 'web.storage', 'web.print', 'web.clipboard', 'web.camera', 'web.share', 'web.connectivity'],
    ),
    WmnSystemModuleDefinition(
      id: 'developer',
      labelKey: 'system_module_developer',
      descriptionKey: 'system_module_developer_help',
      icon: Icons.developer_mode_outlined,
      group: WmnSystemModuleGroup.developer,
      status: WmnSystemModuleStatus.foundation,
      capabilities: ['doctype-studio', 'source-parity', 'app-converter'],
    ),
  ];

  bool isEnabled(String id) {
    final definition = this.definition(id);
    if (definition.required) {
      return true;
    }
    return settings.getBool(
      'system_module.$id.enabled',
      fallback: definition.defaultEnabled,
    );
  }

  /// Updates module state while preserving the platform dependency graph.
  ///
  /// Enabling a module also enables its optional dependencies. Disabling is
  /// rejected when another enabled module still depends on it.
  bool updateEnabled(String id, bool enabled) {
    final module = definition(id);
    if (module.required) {
      return enabled;
    }
    if (!enabled && enabledDependentsOf(id).isNotEmpty) return false;

    if (enabled) {
      _enableWithDependencies(id, <String>{});
    } else {
      settings.setBool('system_module.$id.enabled', false);
    }
    notifyListeners();
    return true;
  }

  void setEnabled(String id, bool enabled) {
    updateEnabled(id, enabled);
  }

  List<String> dependenciesOf(String id) => List<String>.unmodifiable(dependencyGraph[id] ?? const <String>[]);

  List<String> dependentsOf(String id) {
    final result = <String>[];
    for (final entry in dependencyGraph.entries) {
      if (entry.value.contains(id)) result.add(entry.key);
    }
    result.sort();
    return result;
  }

  List<String> enabledDependentsOf(String id) =>
      dependentsOf(id).where(isEnabled).toList(growable: false);

  Set<String> get enabledCapabilities => {
        for (final module in definitions)
          if (isEnabled(module.id) && _isExecutable(module)) ...module.capabilities,
      };

  bool hasCapability(String capability) => enabledCapabilities.contains(capability);

  List<String> missingCapabilities(Iterable<String> capabilities) {
    final enabled = enabledCapabilities;
    return capabilities.where((capability) => !enabled.contains(capability)).toSet().toList()..sort();
  }

  List<String> validateDependencyGraph() {
    final issues = <String>[];
    final ids = <String>{};
    for (final definition in definitions) {
      if (!ids.add(definition.id)) {
        issues.add('Duplicate WMN system module definition: ${definition.id}');
      }
      if (!_isSemanticVersion(definition.version)) {
        issues.add('Invalid WMN system module version for ${definition.id}: ${definition.version}');
      }
    }

    for (final entry in dependencyGraph.entries) {
      if (!ids.contains(entry.key)) {
        issues.add('Unknown dependency owner: ${entry.key}');
      }
      final uniqueDependencies = <String>{};
      for (final dependency in entry.value) {
        if (!uniqueDependencies.add(dependency)) {
          issues.add('${entry.key} declares duplicate dependency $dependency');
        }
        if (!ids.contains(dependency)) {
          issues.add('${entry.key} depends on unknown module $dependency');
        }
      }
    }

    for (final module in definitions.where((entry) => isEnabled(entry.id))) {
      for (final dependency in dependenciesOf(module.id)) {
        if (!isEnabled(dependency)) {
          issues.add('Enabled module ${module.id} requires disabled module $dependency');
        }
      }
    }

    final cycle = _findDependencyCycle(ids);
    if (cycle != null) {
      issues.add('Circular WMN system module dependency: ${cycle.join(' -> ')}');
    }
    return issues;
  }

  /// Returns enabled modules in dependency-first startup order.
  ///
  /// This provides one deterministic order for bootstrap, diagnostics and
  /// future module lifecycle hooks instead of scattering dependency checks.
  List<WmnSystemModuleDefinition> enabledInDependencyOrder() {
    final ordered = <WmnSystemModuleDefinition>[];
    final visited = <String>{};
    final visiting = <String>{};

    void visit(String id) {
      if (visited.contains(id) || !isEnabled(id)) return;
      if (!visiting.add(id)) {
        throw StateError('Circular WMN system module dependency involving $id');
      }
      for (final dependency in dependenciesOf(id)) {
        visit(dependency);
      }
      visiting.remove(id);
      visited.add(id);
      ordered.add(definition(id));
    }

    for (final module in definitions) {
      visit(module.id);
    }
    return List<WmnSystemModuleDefinition>.unmodifiable(ordered);
  }

  List<String>? _findDependencyCycle(Set<String> ids) {
    final visited = <String>{};
    final visiting = <String>{};
    final path = <String>[];

    List<String>? visit(String id) {
      if (visited.contains(id)) return null;
      if (visiting.contains(id)) {
        final start = path.indexOf(id);
        return <String>[...path.sublist(start), id];
      }
      visiting.add(id);
      path.add(id);
      for (final dependency in dependencyGraph[id] ?? const <String>[]) {
        if (!ids.contains(dependency)) continue;
        final cycle = visit(dependency);
        if (cycle != null) return cycle;
      }
      path.removeLast();
      visiting.remove(id);
      visited.add(id);
      return null;
    }

    for (final id in ids) {
      final cycle = visit(id);
      if (cycle != null) return cycle;
    }
    return null;
  }

  bool _isSemanticVersion(String value) =>
      RegExp(r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$').hasMatch(value.trim());

  void _enableWithDependencies(String id, Set<String> visiting) {
    if (!visiting.add(id)) {
      throw StateError('Circular WMN system module dependency involving $id');
    }
    for (final dependency in dependenciesOf(id)) {
      final definition = this.definition(dependency);
      if (!definition.required) {
        settings.setBool('system_module.$dependency.enabled', true);
      }
      _enableWithDependencies(dependency, visiting);
    }
    final definition = this.definition(id);
    if (!definition.required) {
      settings.setBool('system_module.$id.enabled', true);
    }
    visiting.remove(id);
  }

  bool _isExecutable(WmnSystemModuleDefinition module) => module.executable;

  WmnSystemModuleDefinition definition(String id) => definitions.firstWhere(
        (entry) => entry.id == id,
        orElse: () => throw StateError('Unknown WMN system module: $id'),
      );

  List<WmnSystemModuleDefinition> group(WmnSystemModuleGroup group) =>
      definitions.where((entry) => entry.group == group).toList(growable: false);
}
