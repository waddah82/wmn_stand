import 'package:flutter/material.dart';

import '../../core/localization/wmn_localization.dart';
import 'wmn_system_module.dart';
import 'wmn_system_module_registry.dart';

class WmnSystemModulesPage extends StatelessWidget {
  const WmnSystemModulesPage({super.key, required this.registry});

  final WmnSystemModuleRegistry registry;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: registry,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
          children: [
            _header(context),
            const SizedBox(height: 20),
            for (final group in WmnSystemModuleGroup.values) ...[
              _groupHeader(context, group),
              const SizedBox(height: 10),
              _groupGrid(context, registry.group(group)),
              const SizedBox(height: 24),
            ],
          ],
        ),
      );

  Widget _header(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(Icons.grid_view_outlined, color: Theme.of(context).colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.wmnT('system_modules'),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 5),
                    Text(context.wmnT('system_modules_help')),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _groupHeader(BuildContext context, WmnSystemModuleGroup group) => Text(
        context.wmnT(_groupLabelKey(group)),
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      );

  Widget _groupGrid(BuildContext context, List<WmnSystemModuleDefinition> modules) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth >= 1200
              ? (constraints.maxWidth - 24) / 3
              : constraints.maxWidth >= 720
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final module in modules)
                SizedBox(
                  width: width,
                  child: _moduleCard(context, module),
                ),
            ],
          );
        },
      );

  Widget _moduleCard(BuildContext context, WmnSystemModuleDefinition module) {
    final enabled = registry.isEnabled(module.id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(module.icon, color: Theme.of(context).colorScheme.onSecondaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.wmnT(module.labelKey),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 3),
                      _statusChip(context, module.status),
                    ],
                  ),
                ),
                Switch(
                  value: enabled,
                  onChanged: module.required
                      ? null
                      : (value) {
                          final changed = registry.updateEnabled(module.id, value);
                          if (!changed) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(context.wmnT('module_has_enabled_dependents'))),
                            );
                          }
                        },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(context.wmnT(module.descriptionKey)),
            const SizedBox(height: 13),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final capability in module.capabilities)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(capability),
                  ),
              ],
            ),
            if (registry.dependenciesOf(module.id).isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '${context.wmnT('system_depends_on')}: ${registry.dependenciesOf(module.id).join(', ')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (module.required) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.lock_outline, size: 16, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(context.wmnT('required_system_module')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusChip(BuildContext context, WmnSystemModuleStatus status) {
    final key = switch (status) {
      WmnSystemModuleStatus.ready => 'status_ready',
      WmnSystemModuleStatus.foundation => 'status_foundation',
      WmnSystemModuleStatus.planned => 'status_planned',
      WmnSystemModuleStatus.deferred => 'status_deferred',
    };
    return Text(
      context.wmnT(key),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
    );
  }

  String _groupLabelKey(WmnSystemModuleGroup group) => switch (group) {
        WmnSystemModuleGroup.foundation => 'system_group_foundation',
        WmnSystemModuleGroup.experience => 'system_group_experience',
        WmnSystemModuleGroup.services => 'system_group_services',
        WmnSystemModuleGroup.platform => 'system_group_platform',
        WmnSystemModuleGroup.developer => 'system_group_developer',
      };
}
