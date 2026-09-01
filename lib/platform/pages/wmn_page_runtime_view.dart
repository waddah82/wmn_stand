import 'package:flutter/material.dart';

import '../../core/localization/wmn_localization.dart';
import '../../framework/meta/meta_service.dart';
import '../../framework/model/document_service.dart';
import '../../framework/ui/form/wmn_form_view.dart';
import '../../framework/ui/list/wmn_list_view.dart';
import '../../framework/workspaces/workspace_page.dart';
import '../../framework/workspaces/workspace_service.dart';
import '../../modules/customization/application/customization_service.dart';
import '../../modules/reporting/application/frappe_report_service.dart';
import '../files/wmn_file_interaction_service.dart';
import '../navigation/wmn_application_report_page.dart';
import '../navigation/wmn_navigation_registry.dart';
import 'wmn_page.dart';
import 'wmn_page_controller_registry.dart';
import 'wmn_page_service.dart';

/// Native renderer for metadata-defined WMN Page records.
///
/// Only the selected Page is loaded and rendered. No application Page widget is
/// pre-built during startup, which keeps the shell light on constrained mobile
/// devices.
class WmnPageRuntimeView extends StatelessWidget {
  const WmnPageRuntimeView({
    super.key,
    required this.pageName,
    required this.pages,
    required this.controllers,
    required this.navigation,
    required this.meta,
    required this.documents,
    required this.customization,
    required this.workspaces,
    required this.reports,
    required this.onOpenDoctype,
    required this.onManageLinkRecords,
    required this.onOpenWorkspace,
    required this.onOpenReport,
    required this.onOpenPage,
    required this.canReadDoctype,
    required this.canOpenWorkspace,
    required this.canOpenReport,
    this.fileInteractions,
  });

  final String pageName;
  final WmnPageService pages;
  final WmnPageControllerRegistry controllers;
  final WmnNavigationRegistry navigation;
  final WmnMetaService meta;
  final WmnDocumentService documents;
  final CustomizationService customization;
  final WmnWorkspaceService workspaces;
  final WmnFrappeReportService reports;
  final ValueChanged<String> onOpenDoctype;
  final Future<void> Function(String doctype) onManageLinkRecords;
  final ValueChanged<String> onOpenWorkspace;
  final ValueChanged<String> onOpenReport;
  final ValueChanged<String> onOpenPage;
  final bool Function(String doctype) canReadDoctype;
  final bool Function(String workspace) canOpenWorkspace;
  final bool Function(String report) canOpenReport;
  final WmnFileInteractionService? fileInteractions;

  @override
  Widget build(BuildContext context) {
    final page = pages.page(pageName, includeDisabled: true);
    if (page == null) {
      return Center(child: Text(context.wmnT('page_not_found')));
    }
    final access = navigation.canAccessPage(page.name);
    if (!access.allowed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(access.reason ?? context.wmnT('access_denied')),
        ),
      );
    }

    if (page.pageType == WmnPageType.custom && page.controllerKey != null) {
      final custom = controllers.build(context, page.controllerKey!, page);
      if (custom != null) return custom;
    }

    final target = page.target;
    return switch (page.pageType) {
      WmnPageType.list => _listPage(context, page, target),
      WmnPageType.form => _formPage(context, page, target),
      WmnPageType.report => _reportPage(context, target),
      WmnPageType.workspace => _workspacePage(context, target),
      WmnPageType.dashboard => target != null && canOpenWorkspace(target)
          ? _workspacePage(context, target)
          : _metadataPage(context, page),
      WmnPageType.standard || WmnPageType.custom =>
        _metadataPage(context, page),
    };
  }

  Widget _listPage(
    BuildContext context,
    WmnPageDefinition page,
    String? target,
  ) {
    if (target == null ||
        meta.doctype(target, includeFields: false) == null ||
        !canReadDoctype(target)) {
      return _invalidTarget(context);
    }
    return WmnListView(
      doctype: target,
      meta: meta,
      documents: documents,
      customization: customization,
      onOpenReport: (name) async => onOpenReport(name),
      fileInteractions: fileInteractions,
    );
  }

  Widget _formPage(
    BuildContext context,
    WmnPageDefinition page,
    String? target,
  ) {
    if (target == null || !canReadDoctype(target)) {
      return _invalidTarget(context);
    }
    final dt = meta.doctype(target, includeFields: false);
    if (dt == null) return _invalidTarget(context);
    final documentName = page.documentName ?? (dt.isSingle ? target : null);
    if (!dt.isSingle && documentName == null) {
      return _metadataPage(context, page);
    }
    return WmnFormView(
      doctype: target,
      documentName: documentName,
      meta: meta,
      documents: documents,
      customization: customization,
      onManageLinkRecords: onManageLinkRecords,
      onOpenReport: (name) async => onOpenReport(name),
      fileInteractions: fileInteractions,
    );
  }

  Widget _reportPage(BuildContext context, String? target) {
    if (target == null || !canOpenReport(target)) {
      return _invalidTarget(context);
    }
    return WmnApplicationReportPage(reportName: target, service: reports);
  }

  Widget _workspacePage(BuildContext context, String? target) {
    if (target == null || !canOpenWorkspace(target)) {
      return _invalidTarget(context);
    }
    return WmnWorkspacePage(
      workspaceName: target,
      service: workspaces,
      onOpenDoctype: onOpenDoctype,
      onOpenWorkspace: onOpenWorkspace,
      onOpenReport: onOpenReport,
      onOpenPage: onOpenPage,
      canReadDoctype: canReadDoctype,
      canOpenWorkspace: canOpenWorkspace,
      canOpenReport: canOpenReport,
      canOpenPage: (name) => navigation.canAccessPage(name).allowed,
      canUseFeature: pages.features.isFeatureEnabled,
    );
  }

  Widget _metadataPage(BuildContext context, WmnPageDefinition page) {
    final blocks = page.layoutBlocks;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text(
          page.title,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (page.module.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            page.module,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 18),
        if (blocks.isEmpty)
          Text(
            page.controllerKey == null
                ? context.wmnT('page_metadata_ready')
                : context.wmnT('page_controller_missing'),
          )
        else
          for (final block in blocks) _block(context, block),
      ],
    );
  }

  Widget _block(BuildContext context, Map<String, Object?> block) {
    final type = '${block['type'] ?? 'text'}'.trim().toLowerCase();
    final label = '${block['label'] ?? block['text'] ?? block['title'] ?? ''}'
        .trim();
    final target = '${block['target'] ?? block['link_to'] ?? ''}'.trim();
    return switch (type) {
      'heading' => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Text(
            label,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      'spacer' => SizedBox(
          height: (block['height'] as num?)?.toDouble() ?? 16,
        ),
      'doctype' => _actionTile(
          context,
          label: label.isEmpty ? target : label,
          icon: Icons.description_outlined,
          enabled: target.isNotEmpty && canReadDoctype(target),
          onTap: () => onOpenDoctype(target),
        ),
      'workspace' => _actionTile(
          context,
          label: label.isEmpty ? target : label,
          icon: Icons.dashboard_customize_outlined,
          enabled: target.isNotEmpty && canOpenWorkspace(target),
          onTap: () => onOpenWorkspace(target),
        ),
      'report' => _actionTile(
          context,
          label: label.isEmpty ? target : label,
          icon: Icons.analytics_outlined,
          enabled: target.isNotEmpty && canOpenReport(target),
          onTap: () => onOpenReport(target),
        ),
      'page' => _actionTile(
          context,
          label: label.isEmpty ? target : label,
          icon: Icons.web_asset_outlined,
          enabled: target.isNotEmpty && navigation.canAccessPage(target).allowed,
          onTap: () => onOpenPage(target),
        ),
      _ => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(label),
        ),
    };
  }

  Widget _actionTile(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          enabled: enabled,
          leading: Icon(icon),
          title: Text(label),
          trailing: const Icon(Icons.chevron_right),
          onTap: enabled ? onTap : null,
        ),
      ),
    );
  }

  Widget _invalidTarget(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(context.wmnT('page_target_unavailable')),
      ),
    );
  }
}
