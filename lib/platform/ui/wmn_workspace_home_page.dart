import 'package:flutter/material.dart';

import '../../core/localization/wmn_localization.dart';
import '../../framework/workspaces/workspace_models.dart';

/// Lightweight workspace-first landing page.
///
/// Only the already-resolved workspace list is rendered here. Workspace
/// content remains lazy and is loaded after the user opens a workspace.
class WmnWorkspaceHomePage extends StatelessWidget {
  const WmnWorkspaceHomePage({
    super.key,
    required this.workspaces,
    required this.onOpenWorkspace,
  });

  final List<WmnWorkspace> workspaces;
  final ValueChanged<String> onOpenWorkspace;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final horizontal = compact ? 14.0 : 24.0;
        return ListView(
          padding: EdgeInsets.fromLTRB(horizontal, compact ? 16 : 22, horizontal, 32),
          children: [
            _header(context, compact: compact),
            SizedBox(height: compact ? 16 : 20),
            if (workspaces.isEmpty)
              _empty(context)
            else
              _workspaceGrid(context, constraints.maxWidth - (horizontal * 2)),
          ],
        );
      },
    );
  }

  Widget _header(BuildContext context, {required bool compact}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.wmnT('workspace_home_title'),
          style: (compact ? theme.textTheme.titleLarge : theme.textTheme.headlineSmall)
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Text(
            context.wmnT('workspace_home_description'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _workspaceGrid(BuildContext context, double maxWidth) {
    final columns = maxWidth >= 1180
        ? 4
        : maxWidth >= 820
            ? 3
            : maxWidth >= 560
                ? 2
                : 1;
    final gap = maxWidth < 600 ? 10.0 : 12.0;
    final cardWidth = (maxWidth - (gap * (columns - 1))) / columns;

    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        for (final workspace in workspaces)
          SizedBox(
            width: cardWidth,
            child: _workspaceCard(context, workspace),
          ),
      ],
    );
  }

  Widget _workspaceCard(BuildContext context, WmnWorkspace workspace) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onOpenWorkspace(workspace.name),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _iconFor(workspace),
                  size: 20,
                  color: scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _label(context, workspace),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      workspace.appName ?? workspace.module,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.dashboard_customize_outlined, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(context.wmnT('platform_no_workspaces_help'))),
            ],
          ),
        ),
      );

  String _label(BuildContext context, WmnWorkspace workspace) {
    return switch (workspace.name) {
      'System' => context.wmnT('workspace_system'),
      'Administration' => context.wmnT('workspace_administration'),
      'Developer' => context.wmnT('workspace_developer'),
      _ => workspace.label,
    };
  }

  IconData _iconFor(WmnWorkspace workspace) {
    final name = workspace.name.toLowerCase();
    if (name == 'administration') return Icons.admin_panel_settings_outlined;
    if (name == 'developer') return Icons.developer_mode_outlined;
    if (name == 'system') return Icons.settings_suggest_outlined;
    return Icons.dashboard_customize_outlined;
  }
}
