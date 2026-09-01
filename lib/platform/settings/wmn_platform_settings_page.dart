import 'package:flutter/material.dart';

import '../../core/database/wmn_database.dart';
import '../../core/localization/wmn_localization.dart';
import '../../core/settings/theme_controller.dart';
import '../system/wmn_shell_preferences.dart';
import '../features/wmn_feature_registry.dart';
import '../system/wmn_system_module_registry.dart';

class WmnPlatformSettingsPage extends StatelessWidget {
  const WmnPlatformSettingsPage({
    super.key,
    required this.database,
    required this.locale,
    required this.theme,
    required this.shell,
    required this.modules,
    required this.features,
  });

  final WmnDatabase database;
  final WmnLocaleController locale;
  final WmnThemeController theme;
  final WmnShellPreferences shell;
  final WmnSystemModuleRegistry modules;
  final WmnFeatureRegistry features;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([locale, theme, shell, modules, features]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
          children: [
            Text(
              context.wmnT('platform_settings'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 18),
            _section(
              context,
              icon: Icons.translate_outlined,
              title: context.wmnT('language'),
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'ar', label: Text('العربية')),
                    ButtonSegment(value: 'en', label: Text('English')),
                  ],
                  selected: {locale.languageCode},
                  onSelectionChanged: (value) => locale.setLanguage(value.first),
                ),
              ],
            ),
            _section(
              context,
              icon: Icons.palette_outlined,
              title: context.wmnT('appearance'),
              children: [
                SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment(value: ThemeMode.light, icon: const Icon(Icons.light_mode_outlined), label: Text(context.wmnT('light'))),
                    ButtonSegment(value: ThemeMode.dark, icon: const Icon(Icons.dark_mode_outlined), label: Text(context.wmnT('dark'))),
                    ButtonSegment(value: ThemeMode.system, icon: const Icon(Icons.settings_suggest_outlined), label: Text(context.wmnT('system'))),
                  ],
                  selected: {theme.mode},
                  onSelectionChanged: (value) => theme.setMode(value.first),
                ),
                const SizedBox(height: 16),
                Text(context.wmnT('accent_color'), style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in WmnThemeController.accentColors.entries)
                      ChoiceChip(
                        selected: theme.accent == entry.key,
                        onSelected: (_) => theme.setAccent(entry.key),
                        avatar: CircleAvatar(backgroundColor: entry.value),
                        label: Text(context.wmnT('accent_${entry.key}')),
                      ),
                  ],
                ),
              ],
            ),
            _section(
              context,
              icon: Icons.view_sidebar_outlined,
              title: context.wmnT('shell_layout'),
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.wmnT('compact_navigation')),
                  subtitle: Text(context.wmnT('compact_navigation_help')),
                  value: shell.compact,
                  onChanged: shell.setCompact,
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.wmnT('show_workspace_labels')),
                  value: shell.showWorkspaceLabels,
                  onChanged: shell.setShowWorkspaceLabels,
                ),
              ],
            ),
            _section(
              context,
              icon: Icons.extension_outlined,
              title: context.wmnT('feature_management'),
              children: [
                Text(
                  context.wmnT('feature_management_help'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                for (final feature in features.definitions())
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(feature.label),
                    subtitle: Text(
                      feature.isCore
                          ? context.wmnT('feature_core_included')
                          : '${feature.entitlementStatus} • ${feature.priceAmount.toStringAsFixed(2)} ${feature.currency} • ${feature.billingPeriod}',
                    ),
                    value: feature.effectiveEnabled,
                    onChanged: feature.isCore || !feature.userToggleable || !feature.entitled
                        ? null
                        : (value) => features.setUserEnabled(feature.id, value),
                  ),
              ],
            ),
            _section(
              context,
              icon: Icons.storage_outlined,
              title: context.wmnT('database'),
              children: [
                SelectableText('${context.wmnT('storage')}: ${database.info.storageKind}'),
                const SizedBox(height: 4),
                SelectableText('${context.wmnT('location')}: ${database.info.storageLocation}'),
                const SizedBox(height: 4),
                SelectableText('${context.wmnT('schema_version')}: ${database.info.schemaVersion}'),
              ],
            ),
          ],
        ),
      );

  Widget _section(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 10),
                    Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 16),
                ...children,
              ],
            ),
          ),
        ),
      );
}
