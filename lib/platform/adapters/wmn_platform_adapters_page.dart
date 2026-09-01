import 'package:flutter/material.dart';

import '../../core/localization/wmn_localization.dart';
import 'wmn_platform_adapter.dart';
import 'wmn_platform_adapter_registry.dart';

class WmnPlatformAdaptersPage extends StatefulWidget {
  const WmnPlatformAdaptersPage({super.key, required this.registry});

  final WmnPlatformAdapterRegistry registry;

  @override
  State<WmnPlatformAdaptersPage> createState() => _WmnPlatformAdaptersPageState();
}

class _WmnPlatformAdaptersPageState extends State<WmnPlatformAdaptersPage> {
  bool _refreshing = false;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.registry,
        builder: (context, _) {
          final runtimeName = wmnRuntimePlatformName(widget.registry.runtimePlatform);
          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _summaryCard(
                    context,
                    icon: Icons.computer_outlined,
                    title: context.wmnT('current_platform'),
                    value: runtimeName,
                  ),
                  _summaryCard(
                    context,
                    icon: Icons.extension_outlined,
                    title: context.wmnT('active_adapters'),
                    value: '${widget.registry.activeAdapters.length}',
                  ),
                  _summaryCard(
                    context,
                    icon: Icons.bolt_outlined,
                    title: context.wmnT('available_capabilities'),
                    value: '${widget.registry.availableCapabilityIds.length}',
                  ),
                  FilledButton.icon(
                    onPressed: _refreshing ? null : _refresh,
                    icon: _refreshing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(context.wmnT('refresh')),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              for (final adapter in widget.registry.adapters) ...[
                _adapterCard(context, adapter),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      );

  Widget _summaryCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
  }) => SizedBox(
        width: 210,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(icon),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 3),
                      Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _adapterCard(BuildContext context, WmnPlatformAdapter adapter) {
    final active = adapter.supports(widget.registry.runtimePlatform);
    final diagnostics = active ? adapter.diagnostics() : const <String, Object?>{};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_adapterIcon(adapter.id), size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(adapter.displayName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      Text('${context.wmnT('system_module')}: ${adapter.moduleId}'),
                    ],
                  ),
                ),
                _statusChip(context, active ? adapter.status.name : WmnPlatformAdapterStatus.unavailable.name),
              ],
            ),
            const SizedBox(height: 14),
            Text(context.wmnT('platform_capabilities'), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final capability in adapter.capabilities)
                  Tooltip(
                    message: capability.description,
                    child: Chip(
                      avatar: Icon(_capabilityIcon(capability.status), size: 16),
                      label: Text('${capability.id} · ${capability.status.name}'),
                    ),
                  ),
              ],
            ),
            if (active && adapter.services.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(context.wmnT('platform_services'), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              SelectableText((adapter.services.keys.toList()..sort()).join('\n')),
            ],
            if (diagnostics.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(context.wmnT('diagnostics'), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              ...diagnostics.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: SelectableText('${entry.key}: ${entry.value}'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusChip(BuildContext context, String status) => Chip(
        label: Text(status.toUpperCase()),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      );

  IconData _adapterIcon(String id) => switch (id) {
        'windows' => Icons.desktop_windows_outlined,
        'mobile' => Icons.smartphone_outlined,
        'web' => Icons.language_outlined,
        'server' => Icons.dns_outlined,
        _ => Icons.extension_outlined,
      };

  IconData _capabilityIcon(WmnPlatformCapabilityStatus status) => switch (status) {
        WmnPlatformCapabilityStatus.available => Icons.check_circle_outline,
        WmnPlatformCapabilityStatus.foundation => Icons.construction_outlined,
        WmnPlatformCapabilityStatus.planned => Icons.schedule_outlined,
        WmnPlatformCapabilityStatus.unavailable => Icons.block_outlined,
      };

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      await widget.registry.refresh();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }
}
