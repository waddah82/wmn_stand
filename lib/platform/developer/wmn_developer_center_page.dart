import 'package:flutter/material.dart';

import '../../core/localization/wmn_localization.dart';
import '../apps/wmn_application_registry.dart';
import '../capabilities/wmn_capability.dart';
import '../capabilities/wmn_capability_registry.dart';
import '../kernel/wmn_kernel.dart';
import '../system/wmn_system_doctype_runtime_catalog.dart';
import '../system/wmn_system_module_registry.dart';

class WmnDeveloperCenterPage extends StatelessWidget {
  const WmnDeveloperCenterPage({
    super.key,
    required this.kernel,
    required this.modules,
    required this.capabilities,
    required this.applications,
  });

  final WmnKernel kernel;
  final WmnSystemModuleRegistry modules;
  final WmnCapabilityRegistry capabilities;
  final WmnApplicationRegistry applications;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[kernel, modules, capabilities, applications]),
        builder: (context, _) {
          final health = kernel.snapshot();
          final apps = applications.applications();
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
            children: [
              _header(context, health),
              const SizedBox(height: 16),
              _metrics(context, health),
              const SizedBox(height: 22),
              _sectionTitle(context, 'capability_registry'),
              const SizedBox(height: 10),
              _capabilities(context),
              const SizedBox(height: 22),
              _sectionTitle(context, 'system_module_dependencies'),
              const SizedBox(height: 10),
              _moduleDependencies(context),
              const SizedBox(height: 22),
              _sectionTitle(context, 'system_doctype_runtime_ownership'),
              const SizedBox(height: 10),
              _systemDocTypeOwnership(context),
              const SizedBox(height: 22),
              _sectionTitle(context, 'application_manifests'),
              const SizedBox(height: 10),
              if (apps.isEmpty)
                _empty(context, context.wmnT('no_applications_installed'))
              else
                ...apps.map((app) => _applicationCard(context, app)),
              const SizedBox(height: 22),
              _sectionTitle(context, 'extension_points'),
              const SizedBox(height: 10),
              _extensionPoints(context),
            ],
          );
        },
      );

  Widget _header(BuildContext context, WmnKernelHealth health) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.developer_mode_outlined, color: Theme.of(context).colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.wmnT('developer_center'),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 5),
                    Text(context.wmnT('developer_center_help')),
                    const SizedBox(height: 10),
                    _statusChip(context, health),
                    if (health.issues.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      for (final issue in health.issues) Text('• $issue'),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: context.wmnT('refresh'),
                onPressed: kernel.refreshHealth,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
      );

  Widget _metrics(BuildContext context, WmnKernelHealth health) => Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _metric(context, Icons.memory_outlined, context.wmnT('registered_services'), '${health.registeredServices}'),
          _metric(context, Icons.toggle_on_outlined, context.wmnT('enabled_modules'), '${health.enabledModules}'),
          _metric(context, Icons.hub_outlined, context.wmnT('available_capabilities'), '${health.availableCapabilities}'),
          _metric(context, Icons.apps_outlined, context.wmnT('applications'), '${health.installedApplications}'),
        ],
      );

  Widget _metric(BuildContext context, IconData icon, String label, String value) => SizedBox(
        width: 230,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(label)),
                Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ),
      );

  Widget _capabilities(BuildContext context) => Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.layers_outlined),
              title: Text(context.wmnT('capability_profiles')),
              subtitle: Text(WmnCapabilityRegistry.profiles.map((profile) => profile.id).join(' • ')),
            ),
            const Divider(height: 1),
            for (final capability in capabilities.capabilities)
              ListTile(
                leading: Icon(_capabilityIcon(capability.status)),
                title: Text(capability.id),
                subtitle: Text('${context.wmnT('provided_by')}: ${capability.providerModuleIds.join(', ')}'),
                trailing: _capabilityStatus(context, capability.status),
              ),
          ],
        ),
      );

  Widget _moduleDependencies(BuildContext context) => Card(
        child: Column(
          children: [
            for (final module in WmnSystemModuleRegistry.definitions)
              ListTile(
                leading: Icon(module.icon),
                title: Text(context.wmnT(module.labelKey)),
                subtitle: Text(
                  modules.dependenciesOf(module.id).isEmpty
                      ? context.wmnT('no_dependencies')
                      : '${context.wmnT('system_depends_on')}: ${modules.dependenciesOf(module.id).join(', ')}',
                ),
                trailing: modules.isEnabled(module.id)
                    ? const Icon(Icons.check_circle_outline)
                    : const Icon(Icons.pause_circle_outline),
              ),
          ],
        ),
      );

  Widget _systemDocTypeOwnership(BuildContext context) => Card(
        child: Column(
          children: [
            for (final binding in WmnSystemDocTypeRuntimeCatalog.bindings)
              ListTile(
                leading: const Icon(Icons.account_tree_outlined),
                title: Text(binding.doctype),
                subtitle: Text(
                  '${context.wmnT('runtime_owner')}: ${binding.ownerServiceId} • '
                  '${context.wmnT('runtime_kind')}: ${binding.kind.name}',
                ),
                trailing: binding.genericEditingAllowed
                    ? Tooltip(
                        message: context.wmnT('generic_editing_allowed'),
                        child: const Icon(Icons.edit_outlined),
                      )
                    : const Icon(Icons.lock_outline),
              ),
          ],
        ),
      );

  Widget _applicationCard(BuildContext context, WmnInstalledApplication app) {
    final diagnostic = applications.diagnose(app.manifest);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.apps_outlined),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(app.manifest.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  Icon(diagnostic.compatible ? Icons.check_circle_outline : Icons.error_outline),
                ],
              ),
              const SizedBox(height: 6),
              Text('${app.manifest.name} • ${app.manifest.version}'),
              if (app.manifest.requiredSystemModules.isNotEmpty)
                Text('${context.wmnT('required_system_modules')}: ${app.manifest.requiredSystemModules.join(', ')}'),
              if (app.manifest.requiredCapabilities.isNotEmpty)
                Text('${context.wmnT('required_capabilities')}: ${app.manifest.requiredCapabilities.join(', ')}'),
              for (final warning in diagnostic.warnings) Text('• ${context.wmnT('warning')}: $warning'),
              for (final error in diagnostic.errors) Text('• ${context.wmnT('error')}: $error'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _extensionPoints(BuildContext context) => Card(
        child: Column(
          children: [
            for (final point in kernel.extensions.points)
              ListTile(
                leading: const Icon(Icons.extension_outlined),
                title: Text(point.id),
                subtitle: Text(point.description),
                trailing: Text('${kernel.extensions.handlersFor(point.id).length}'),
              ),
          ],
        ),
      );

  Widget _empty(BuildContext context, String message) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              const Icon(Icons.info_outline),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );

  Widget _sectionTitle(BuildContext context, String key) => Text(
        context.wmnT(key),
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      );

  Widget _statusChip(BuildContext context, WmnKernelHealth health) {
    final healthy = health.healthy;
    return Chip(
      avatar: Icon(healthy ? Icons.check_circle_outline : Icons.warning_amber_outlined, size: 18),
      label: Text(context.wmnT(healthy ? 'kernel_healthy' : 'kernel_degraded')),
    );
  }

  Widget _capabilityStatus(BuildContext context, WmnCapabilityStatus status) => Chip(
        visualDensity: VisualDensity.compact,
        label: Text(
          context.wmnT(switch (status) {
            WmnCapabilityStatus.available => 'capability_available',
            WmnCapabilityStatus.disabled => 'capability_disabled',
            WmnCapabilityStatus.planned => 'status_planned',
            WmnCapabilityStatus.deferred => 'status_deferred',
            WmnCapabilityStatus.unavailable => 'capability_unavailable',
          }),
        ),
      );

  IconData _capabilityIcon(WmnCapabilityStatus status) => switch (status) {
        WmnCapabilityStatus.available => Icons.check_circle_outline,
        WmnCapabilityStatus.disabled => Icons.pause_circle_outline,
        WmnCapabilityStatus.planned => Icons.schedule_outlined,
        WmnCapabilityStatus.deferred => Icons.snooze_outlined,
        WmnCapabilityStatus.unavailable => Icons.block_outlined,
      };
}
