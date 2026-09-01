import 'package:flutter/material.dart';

import '../../core/localization/wmn_localization.dart';
import 'workspace_models.dart';
import 'workspace_service.dart';

class WmnWorkspacePage extends StatelessWidget {
  const WmnWorkspacePage({
    super.key,
    required this.workspaceName,
    required this.service,
    required this.onOpenDoctype,
    required this.onOpenWorkspace,
    this.onOpenReport,
    this.onOpenPage,
    this.canReadDoctype,
    this.canOpenWorkspace,
    this.canOpenReport,
    this.canOpenPage,
    this.canUseFeature,
  });

  final String workspaceName;
  final WmnWorkspaceService service;
  final ValueChanged<String> onOpenDoctype;
  final ValueChanged<String> onOpenWorkspace;
  final ValueChanged<String>? onOpenReport;
  final ValueChanged<String>? onOpenPage;
  final bool Function(String doctype)? canReadDoctype;
  final bool Function(String workspace)? canOpenWorkspace;
  final bool Function(String report)? canOpenReport;
  final bool Function(String page)? canOpenPage;
  final bool Function(String featureCode)? canUseFeature;

  @override
  Widget build(BuildContext context) {
    final bundle = service.bundle(workspaceName);
    if (bundle == null) return Center(child: Text(context.wmnT('workspace_not_found')));
    final workspace = bundle.workspace;
    final content = bundle.region('CONTENT').where(_visibleItem).toList(growable: false);
    final links = bundle.region('LINKS').where(_visibleItem).toList(growable: false);
    final shortcuts = bundle.region('SHORTCUTS').where(_visibleItem).toList(growable: false);
    final cards = bundle.region('NUMBER_CARDS').where(_visibleItem).toList(growable: false);
    final charts = bundle.region('CHARTS').where(_visibleItem).toList(growable: false);
    final quickLists = bundle.region('QUICK_LISTS').where(_visibleItem).toList(growable: false);
    final sidebar = bundle.region('SIDEBAR').where(_visibleItem).toList(growable: false);
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 920;
      final body = ListView(
        padding: EdgeInsets.all(constraints.maxWidth < 600 ? 12 : 18),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _workspaceLabel(context, workspace),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              _metaPill(context, workspace.module),
              if (workspace.appName != null)
                _metaPill(context, workspace.appName!),
            ],
          ),
          const SizedBox(height: 8),
          if (shortcuts.isNotEmpty) _workspaceLinkSection(context, context.wmnT('workspace_shortcuts'), shortcuts),
          if (cards.isNotEmpty) _numberCards(context, cards),
          if (WmnWorkspaceService.dashboardChartsEnabled && charts.isNotEmpty) _dashboardCharts(context, charts),
          if (quickLists.isNotEmpty) _quickLists(context, quickLists),
          if (content.isNotEmpty) _contentGrid(context, content),
          if (links.isNotEmpty) _workspaceLinkSection(context, context.wmnT('workspace_links'), links),
          const SizedBox(height: 36),
        ],
      );
      if (!wide || sidebar.isEmpty) return body;
      return Row(children: [
        SizedBox(width: 224, child: _sidebar(context, sidebar)),
        const VerticalDivider(width: 1),
        Expanded(child: body),
      ]);
    });
  }

  String _workspaceLabel(BuildContext context, WmnWorkspace workspace) {
    return switch (workspace.name) {
      'System' => context.wmnT('workspace_system'),
      'Administration' => context.wmnT('workspace_administration'),
      'Developer' => context.wmnT('workspace_developer'),
      _ => workspace.label,
    };
  }

  Widget _sidebar(BuildContext context, List<WmnWorkspaceItem> items) => ListView(
        padding: const EdgeInsets.symmetric(vertical: 6),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            child: Text(context.wmnT('workspace_navigation'), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
          ),
          for (final item in items)
            ListTile(
              dense: true,
              leading: Icon(_iconFor(item), size: 19),
              title: Text(
                item.label ?? item.linkTo ?? item.itemType,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              visualDensity: VisualDensity.compact,
              onTap: _action(item),
            ),
        ],
      );

  Widget _numberCards(BuildContext context, List<WmnWorkspaceItem> items) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in items)
              SizedBox(
                width: _responsiveCardWidth(context, 200),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item.label ?? item.linkTo ?? context.wmnT('number_card')),
                      const SizedBox(height: 12),
                      Text(
                        '${item.linkTo == null ? '—' : service.numberCardValue(item.linkTo!) ?? '—'}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _dashboardCharts(BuildContext context, List<WmnWorkspaceItem> items) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.wmnT('workspace_charts'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final item in items) _dashboardChartCard(context, item),
            ],
          ),
        ]),
      );

  Widget _dashboardChartCard(BuildContext context, WmnWorkspaceItem item) {
    final name = item.linkTo ?? item.label ?? '';
    final series = name.isEmpty ? const <Map<String, Object?>>[] : service.dashboardChartSeries(name);
    final meta = name.isEmpty ? null : service.dashboardChartMeta(name);
    final maxValue = series.fold<num>(0, (max, row) {
      final value = row['value'] as num? ?? 0;
      return value > max ? value : max;
    });
    return SizedBox(
      width: _responsiveCardWidth(context, 340),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.label ?? '${meta?['label'] ?? name}', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            if (meta?['document_type'] != null) Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('${meta!['document_type']}', style: Theme.of(context).textTheme.bodySmall),
            ),
            const SizedBox(height: 10),
            if (series.isEmpty)
              Text(context.wmnT('workspace_chart_requires_port'))
            else
              for (final row in series) Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  SizedBox(width: 110, child: Text('${row['label']}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        minHeight: 8,
                        value: maxValue <= 0 ? 0 : ((row['value'] as num? ?? 0) / maxValue).clamp(0, 1).toDouble(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${row['value']}'),
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _quickLists(BuildContext context, List<WmnWorkspaceItem> items) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(context.wmnT('workspace_quick_lists'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final item in items) _quickListCard(context, item),
            ],
          ),
        ]),
      );

  Widget _quickListCard(BuildContext context, WmnWorkspaceItem item) {
    final doctype = item.linkTo ?? item.data['document_type']?.toString() ?? item.data['doctype']?.toString();
    final rows = doctype == null || doctype.trim().isEmpty ? const <Map<String, Object?>>[] : service.quickListRows(doctype);
    return SizedBox(
      width: _responsiveCardWidth(context, 320),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(item.label ?? doctype ?? context.wmnT('workspace_quick_list'), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800))),
              if (doctype != null) IconButton(onPressed: () => onOpenDoctype(doctype), icon: const Icon(Icons.open_in_new), tooltip: context.wmnT('open')),
            ]),
            if (rows.isEmpty)
              Padding(padding: const EdgeInsets.all(8), child: Text(context.wmnT('no_records')))
            else
              for (final row in rows)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(_quickRowTitle(row)),
                  subtitle: Text(_quickRowSubtitle(row), maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: doctype == null ? null : () => onOpenDoctype(doctype),
                ),
          ]),
        ),
      ),
    );
  }

  String _quickRowTitle(Map<String, Object?> row) {
    for (final key in const ['title', 'label', 'name', 'id']) {
      final value = row[key];
      if (value != null && '$value'.trim().isNotEmpty) return '$value';
    }
    return row.values.isEmpty ? '—' : '${row.values.first}';
  }

  String _quickRowSubtitle(Map<String, Object?> row) {
    final values = row.entries
        .where((entry) => !const {'title', 'name', 'id'}.contains(entry.key))
        .where((entry) => entry.value != null && '${entry.value}'.trim().isNotEmpty)
        .take(3)
        .map((entry) => '${entry.key}: ${entry.value}')
        .toList(growable: false);
    return values.isEmpty ? ' ' : values.join(' • ');
  }

  Widget _contentGrid(BuildContext context, List<WmnWorkspaceItem> items) {
    final widgets = <Widget>[];
    for (final item in items) {
      final type = item.itemType.toLowerCase();
      if (type == 'header') {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(item.label ?? '', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        ));
      } else if (type == 'spacer') {
        widgets.add(const SizedBox(height: 12));
      } else if (type == 'number_card') {
        widgets.add(_numberCards(context, [item]));
      } else {
        widgets.add(SizedBox(
          width: _responsiveCardWidth(context, 236),
          child: Card(
            child: ListTile(
              leading: Icon(_iconFor(item), size: 19),
              title: Text(item.label ?? item.linkTo ?? item.itemType),
              subtitle: '${item.data['description'] ?? ''}'.trim().isEmpty
                  ? null
                  : Text('${item.data['description']}'),
              trailing: _action(item) == null ? null : const Icon(Icons.chevron_right, size: 18),
              onTap: _action(item),
            ),
          ),
        ));
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Wrap(spacing: 12, runSpacing: 12, children: widgets),
    );
  }

  Widget _workspaceLinkSection(
    BuildContext context,
    String title,
    List<WmnWorkspaceItem> items,
  ) {
    final actionable = items.where((item) => !_isCardBreak(item)).toList(growable: false);
    final hasCards = actionable.any((item) => (item.parentLabel ?? '').trim().isNotEmpty);
    if (!hasCards) return _linkSection(context, title, actionable);

    final groups = <String, List<WmnWorkspaceItem>>{};
    final ungrouped = <WmnWorkspaceItem>[];
    for (final item in actionable) {
      final card = (item.parentLabel ?? '').trim();
      if (card.isEmpty) {
        ungrouped.add(item);
      } else {
        groups.putIfAbsent(card, () => <WmnWorkspaceItem>[]).add(item);
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              for (final entry in groups.entries) _workspaceLinkCard(context, entry.key, entry.value),
            ],
          ),
          if (ungrouped.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            _linkChips(context, ungrouped),
          ],
        ],
      ),
    );
  }

  Widget _workspaceLinkCard(
    BuildContext context,
    String title,
    List<WmnWorkspaceItem> items,
  ) {
    return SizedBox(
      width: _responsiveCardWidth(context, 320),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const Divider(height: 1),
              for (final item in items)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                  leading: Icon(_iconFor(item), size: 18),
                  title: Text(item.label ?? item.linkTo ?? item.itemType),
                  trailing: _action(item) == null ? null : const Icon(Icons.chevron_right, size: 18),
                  onTap: _action(item),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _linkSection(BuildContext context, String title, List<WmnWorkspaceItem> items) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          _linkChips(context, items),
        ]),
      );

  Widget _linkChips(BuildContext context, List<WmnWorkspaceItem> items) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final item in items)
            ActionChip(
              visualDensity: VisualDensity.compact,
              avatar: Icon(_iconFor(item), size: 17),
              label: Text(item.label ?? item.linkTo ?? item.itemType),
              onPressed: _action(item),
            ),
        ],
      );

  bool _isCardBreak(WmnWorkspaceItem item) {
    final type = item.itemType.trim().toLowerCase();
    return (type == 'card' || type == 'card break') && (item.linkTo ?? '').trim().isEmpty;
  }

  Widget _metaPill(BuildContext context, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        value,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  double _responsiveCardWidth(BuildContext context, double preferred) {
    final viewport = MediaQuery.sizeOf(context).width;
    if (viewport >= 600) return preferred;
    final available = viewport - 24;
    return available < 160 ? 160 : available;
  }

  bool _visibleItem(WmnWorkspaceItem item) {
    final requiredFeature = '${item.data['required_feature'] ?? ''}'.trim();
    if (requiredFeature.isNotEmpty &&
        !(canUseFeature?.call(requiredFeature) ?? true)) {
      return false;
    }
    final target = item.linkTo?.trim();
    final type = (item.linkType ?? item.itemType).trim().toLowerCase();
    if (target != null && target.isNotEmpty) {
      if (type == 'doctype') return canReadDoctype?.call(target) ?? true;
      if (type == 'workspace' || item.itemType.toLowerCase() == 'card') {
        return canOpenWorkspace?.call(target) ?? true;
      }
      if (type == 'report' || type == 'query report') {
        return canOpenReport?.call(target) ?? true;
      }
      if (type == 'page') return canOpenPage?.call(target) ?? true;
    }

    if (type.contains('quick')) {
      final doctype = target ??
          item.data['document_type']?.toString() ??
          item.data['doctype']?.toString();
      if (doctype != null && doctype.trim().isNotEmpty) {
        return canReadDoctype?.call(doctype.trim()) ?? true;
      }
    }
    if (type.contains('chart')) {
      final name = target ?? item.label ?? '';
      final doctype = name.isEmpty
          ? null
          : service.dashboardChartMeta(name)?['document_type']?.toString();
      if (doctype != null && doctype.trim().isNotEmpty) {
        return canReadDoctype?.call(doctype.trim()) ?? true;
      }
    }
    if (type.contains('number')) {
      final name = target ?? item.label ?? '';
      final doctype = name.isEmpty
          ? null
          : service.numberCardMeta(name)?['document_type']?.toString();
      if (doctype != null && doctype.trim().isNotEmpty) {
        return canReadDoctype?.call(doctype.trim()) ?? true;
      }
    }
    return true;
  }

  VoidCallback? _action(WmnWorkspaceItem item) {
    final target = item.linkTo?.trim();
    if (target == null || target.isEmpty) return null;
    final type = (item.linkType ?? '').toLowerCase();
    if (type == 'doctype') return () => onOpenDoctype(target);
    if (type == 'workspace') return () => onOpenWorkspace(target);
    if (type == 'report' || type == 'query report') return onOpenReport == null ? null : () => onOpenReport!(target);
    if (type == 'page') return onOpenPage == null ? null : () => onOpenPage!(target);
    if (item.itemType.toLowerCase() == 'card') return () => onOpenWorkspace(target);
    return null;
  }

  IconData _iconFor(WmnWorkspaceItem item) {
    final type = (item.linkType ?? item.itemType).toLowerCase();
    if (type.contains('report') || type.contains('chart')) return Icons.analytics_outlined;
    if (type.contains('workspace') || type.contains('card')) return Icons.dashboard_customize_outlined;
    if (type.contains('doctype')) return Icons.description_outlined;
    if (type.contains('page')) return Icons.web_asset_outlined;
    if (type.contains('number')) return Icons.numbers_outlined;
    return Icons.chevron_right;
  }
}
