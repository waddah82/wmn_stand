import 'package:flutter/material.dart';

import '../../core/localization/wmn_localization.dart';
import '../../framework/workspaces/workspace_models.dart';
import '../../framework/workspaces/workspace_service.dart';
import '../system/wmn_system_module.dart';
import '../system/wmn_system_module_registry.dart';

class WmnPlatformHomePage extends StatelessWidget {
  const WmnPlatformHomePage({
    super.key,
    required this.modules,
    required this.workspaces,
    this.visibleWorkspaces,
    required this.onOpenWorkspace,
    required this.onOpenSystemModules,
    required this.onOpenApplications,
    required this.onOpenDocTypes,
    required this.onOpenMethods,
  });

  final WmnSystemModuleRegistry modules;
  final WmnWorkspaceService workspaces;
  final List<WmnWorkspace>? visibleWorkspaces;
  final ValueChanged<String> onOpenWorkspace;
  final VoidCallback onOpenSystemModules;
  final VoidCallback onOpenApplications;
  final VoidCallback onOpenDocTypes;
  final VoidCallback onOpenMethods;

  @override
  Widget build(BuildContext context) {
    final workspaceRows = visibleWorkspaces ?? workspaces.workspaces();
    final ready = WmnSystemModuleRegistry.definitions
        .where((entry) => entry.status == WmnSystemModuleStatus.ready)
        .length;
    final enabled = WmnSystemModuleRegistry.definitions.where((entry) => modules.isEnabled(entry.id)).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
      children: [
        _hero(
          context,
          enabled: enabled,
          ready: ready,
          workspaceCount: workspaceRows.length,
        ),
        const SizedBox(height: 22),
        Text(
          context.wmnT('quick_start'),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _actionCard(
              context,
              icon: Icons.schema_outlined,
              title: context.wmnT('doctype_manager'),
              subtitle: context.wmnT('platform_home_doctypes_help'),
              onTap: onOpenDocTypes,
            ),
            _actionCard(
              context,
              icon: Icons.data_object_outlined,
              title: context.wmnT('system_scripts_methods'),
              subtitle: context.wmnT('platform_home_methods_help'),
              onTap: onOpenMethods,
            ),
            _actionCard(
              context,
              icon: Icons.grid_view_outlined,
              title: context.wmnT('system_modules'),
              subtitle: context.wmnT('platform_home_modules_help'),
              onTap: onOpenSystemModules,
            ),
            _actionCard(
              context,
              icon: Icons.apps_outlined,
              title: context.wmnT('applications'),
              subtitle: context.wmnT('applications_help'),
              onTap: onOpenApplications,
            ),
          ],
        ),
        const SizedBox(height: 26),
        Row(
          children: [
            Expanded(
              child: Text(
                context.wmnT('workspaces'),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '${workspaceRows.length}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (workspaceRows.isEmpty)
          _emptyWorkspaces(context)
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = constraints.maxWidth >= 1300
                  ? (constraints.maxWidth - 36) / 4
                  : constraints.maxWidth >= 900
                      ? (constraints.maxWidth - 24) / 3
                      : constraints.maxWidth >= 560
                          ? (constraints.maxWidth - 12) / 2
                          : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final workspace in workspaceRows)
                    SizedBox(
                      width: cardWidth,
                      child: _workspaceCard(context, workspace),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _hero(
    BuildContext context, {
    required int enabled,
    required int ready,
    required int workspaceCount,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primaryContainer,
            scheme.surfaceContainerHighest,
          ],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            final copy = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(
                        'W',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: scheme.onPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'WMN',
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          Text(context.wmnT('application_platform')),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  context.wmnT('platform_home_headline'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  context.wmnT('platform_home_description'),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            );
            final stats = Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _stat(context, '$enabled', context.wmnT('enabled_modules')),
                _stat(context, '$ready', context.wmnT('ready_modules')),
                _stat(context, '$workspaceCount', context.wmnT('workspaces')),
              ],
            );
            if (compact) {
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [copy, const SizedBox(height: 18), stats]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: copy),
                const SizedBox(width: 24),
                ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: stats),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String value, String label) => Container(
        width: 124,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 2),
            Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      );

  Widget _actionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => SizedBox(
        width: 300,
        child: Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(icon, color: Theme.of(context).colorScheme.onSecondaryContainer),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(subtitle, maxLines: 3, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _workspaceCard(BuildContext context, WmnWorkspace workspace) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => onOpenWorkspace(workspace.name),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.dashboard_customize_outlined, color: Theme.of(context).colorScheme.primary),
                    const Spacer(),
                    const Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ),
                const SizedBox(height: 16),
                Text(workspace.label, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 5),
                Text(
                  workspace.appName == null ? workspace.module : '${workspace.module} • ${workspace.appName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      );

  Widget _emptyWorkspaces(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            const Icon(Icons.dashboard_customize_outlined),
            const SizedBox(width: 12),
            Expanded(child: Text(context.wmnT('platform_no_workspaces_help'))),
          ],
        ),
      );
}
