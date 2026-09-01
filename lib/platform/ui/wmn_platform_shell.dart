import 'package:flutter/material.dart';

import '../../app/wmn_runtime.dart';
import '../../core/localization/wmn_localization.dart';
import '../../framework/apps/frappe_app_import_page.dart';
import '../../framework/data_exchange/data_exchange_page.dart';
import '../../framework/frappe_compat/frappe_runtime_status_page.dart';
import '../../framework/frappe_compat/system_methods_page.dart';
import '../../framework/ui/doctype/wmn_doctype_manager_page.dart';
import '../../framework/ui/form/wmn_form_view.dart';
import '../../framework/ui/list/wmn_list_view.dart';
import '../../framework/workspaces/workspace_models.dart';
import '../../framework/workspaces/workspace_page.dart';
import '../adapters/wmn_platform_adapters_page.dart';
import '../apps/wmn_applications_page.dart';
import '../developer/wmn_developer_center_page.dart';
import '../navigation/wmn_app_route.dart';
import '../navigation/wmn_application_report_page.dart';
import '../navigation/wmn_navigation_registry.dart';
import '../pages/wmn_page_runtime_view.dart';
import '../reports/wmn_platform_reports_page.dart';
import '../services/wmn_system_services_page.dart';
import '../settings/wmn_platform_settings_page.dart';
import '../system/wmn_system_modules_page.dart';
import '../system/wmn_system_module_registry.dart';
import 'wmn_platform_home_page.dart';
import 'wmn_responsive.dart';
import 'wmn_workspace_home_page.dart';

class WmnPlatformShell extends StatefulWidget {
  const WmnPlatformShell({super.key, required this.runtime});

  final WmnRuntime runtime;

  @override
  State<WmnPlatformShell> createState() => _WmnPlatformShellState();
}

class _WmnPlatformShellState extends State<WmnPlatformShell> {
  String _route = 'home';
  String? _workspace;
  String? _appRoutePath;
  bool _legacyUi = false;
  final _searchController = TextEditingController();
  final _compactScaffoldKey = GlobalKey<ScaffoldState>();

  WmnRuntime get r => widget.runtime;

  @override
  void initState() {
    super.initState();
    final workspaces = r.navigation.visibleWorkspaces();
    if (workspaces.isNotEmpty) _workspace = workspaces.first.name;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _select(String route, {String? workspace}) {
    setState(() {
      _route = route;
      _appRoutePath = null;
      if (workspace != null) _workspace = workspace;
    });
  }

  void _selectAppRoute(String path) {
    final access = r.navigation.canAccessPath(path);
    if (!access.allowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(access.reason ?? context.wmnT('access_denied'))),
      );
      return;
    }
    setState(() {
      _route = 'app_route';
      _appRoutePath = path;
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([
          r.shell,
          r.systemModules,
          r.capabilities,
          r.features,
          r.applications,
          r.locale,
          r.theme,
        ]),
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final desktop = !WmnResponsive.compactShell(constraints.maxWidth);
            if (desktop) {
              return Scaffold(
                body: Row(
                  children: [
                    _sidebar(context),
                    Expanded(child: _page(context)),
                  ],
                ),
              );
            }
            return Scaffold(
              key: _compactScaffoldKey,
              drawer: Drawer(
                width: constraints.maxWidth < 360 ? constraints.maxWidth * .88 : 292,
                child: SafeArea(
                  child: _activeSidebarContent(context, drawerMode: true),
                ),
              ),
              body: _page(context, compactShell: true),
            );
          },
        ),
      );

  Widget _sidebar(BuildContext context) {
    final collapsed = r.shell.sidebarCollapsed;
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      width: collapsed ? 64 : 232,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: BorderDirectional(
          end: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        child: _activeSidebarContent(context, collapsed: collapsed),
      ),
    );
  }

  Widget _activeSidebarContent(
    BuildContext context, {
    bool collapsed = false,
    bool drawerMode = false,
  }) =>
      _legacyUi
          ? _legacySidebarContent(
              context,
              collapsed: collapsed,
              drawerMode: drawerMode,
            )
          : _workspaceSidebarContent(
              context,
              collapsed: collapsed,
              drawerMode: drawerMode,
            );

  Widget _workspaceSidebarContent(
    BuildContext context, {
    bool collapsed = false,
    bool drawerMode = false,
  }) {
    final workspaces = r.navigation.visibleWorkspaces();
    final appEntries = r.navigation
        .entries()
        .where((entry) => entry.appName != 'wmn_system')
        .toList(growable: false);
    final content = ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
      children: [
        _brand(context, collapsed: collapsed),
        const SizedBox(height: 8),
        _navItem(
          context,
          route: 'home',
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          label: context.wmnT('home'),
          collapsed: collapsed,
          drawerMode: drawerMode,
        ),
        if (workspaces.isNotEmpty) ...[
          _sectionLabel(context, context.wmnT('workspaces'), collapsed),
          for (final workspace in workspaces)
            _workspaceItem(
              context,
              workspace.name,
              _workspaceLabel(context, workspace),
              collapsed: collapsed,
              drawerMode: drawerMode,
            ),
        ],
        if (appEntries.isNotEmpty) ...[
          _sectionLabel(
            context,
            context.wmnT('application_navigation'),
            collapsed,
          ),
          for (final entry in appEntries)
            _appNavItem(
              context,
              entry,
              collapsed: collapsed,
              drawerMode: drawerMode,
            ),
        ],
      ],
    );
    return Column(
      children: [
        Expanded(child: content),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
          child: collapsed && !drawerMode
              ? IconButton(
                  tooltip: context.wmnT('current_ui'),
                  onPressed: _toggleUiMode,
                  icon: const Icon(Icons.view_sidebar_outlined),
                )
              : SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      if (drawerMode) Navigator.maybePop(context);
                      _toggleUiMode();
                    },
                    icon: const Icon(Icons.view_sidebar_outlined, size: 18),
                    label: Text(context.wmnT('current_ui')),
                  ),
                ),
        ),
        if (!drawerMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
            child: IconButton(
              tooltip: collapsed
                  ? context.wmnT('expand_sidebar')
                  : context.wmnT('collapse_sidebar'),
              onPressed: r.shell.toggleSidebar,
              icon: Icon(
                collapsed
                    ? Icons.keyboard_double_arrow_right
                    : Icons.keyboard_double_arrow_left,
              ),
            ),
          ),
      ],
    );
  }

  Widget _legacySidebarContent(
    BuildContext context, {
    bool collapsed = false,
    bool drawerMode = false,
  }) {
    final workspaces = r.navigation.visibleWorkspaces();
    final appEntries = r.navigation.entries();
    final routedWorkspaceNames = appEntries
        .where((entry) =>
            entry.route.targetType == WmnAppRouteTargetType.workspace)
        .map((entry) => entry.route.target)
        .toSet();
    final workspaceEntries = workspaces
        .where((workspace) =>
            workspace.appName == null ||
            !routedWorkspaceNames.contains(workspace.name))
        .toList(growable: false);
    final content = ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
      children: [
        _brand(context, collapsed: collapsed),
        const SizedBox(height: 8),
        _navItem(
          context,
          route: 'home',
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          label: context.wmnT('home'),
          collapsed: collapsed,
          drawerMode: drawerMode,
        ),
        _navItem(
          context,
          route: 'system_modules',
          icon: Icons.grid_view_outlined,
          selectedIcon: Icons.grid_view,
          label: context.wmnT('system_modules'),
          collapsed: collapsed,
          drawerMode: drawerMode,
        ),
        _navItem(
          context,
          route: 'applications',
          icon: Icons.apps_outlined,
          selectedIcon: Icons.apps,
          label: context.wmnT('applications'),
          collapsed: collapsed,
          drawerMode: drawerMode,
        ),
        if (r.systemModules.isEnabled('workspaces') && workspaceEntries.isNotEmpty) ...[
          _sectionLabel(context, context.wmnT('workspaces'), collapsed),
          for (final workspace in workspaceEntries)
            _workspaceItem(
              context,
              workspace.name,
              _workspaceLabel(context, workspace),
              collapsed: collapsed,
              drawerMode: drawerMode,
            ),
        ],
        if (appEntries.isNotEmpty) ...[
          _sectionLabel(
            context,
            context.wmnT('application_navigation'),
            collapsed,
          ),
          for (final entry in appEntries)
            _appNavItem(
              context,
              entry,
              collapsed: collapsed,
              drawerMode: drawerMode,
            ),
        ],
        _sectionLabel(context, context.wmnT('build'), collapsed),
        _navItem(
          context,
          route: 'doctypes',
          icon: Icons.schema_outlined,
          selectedIcon: Icons.schema,
          label: context.wmnT('doctype_manager'),
          collapsed: collapsed,
          drawerMode: drawerMode,
        ),
        _navItem(
          context,
          route: 'methods',
          icon: Icons.data_object_outlined,
          selectedIcon: Icons.data_object,
          label: context.wmnT('system_scripts_methods'),
          collapsed: collapsed,
          drawerMode: drawerMode,
        ),
        if (r.systemModules.isEnabled('reports') &&
            (r.features.isFeatureEnabled('reports.query') ||
                r.features.isFeatureEnabled('reports.script')))
          _navItem(
          context,
          route: 'reports',
          icon: Icons.analytics_outlined,
          selectedIcon: Icons.analytics,
          label: context.wmnT('reports'),
          collapsed: collapsed,
          drawerMode: drawerMode,
        ),
        if (r.systemModules.isEnabled('import_export'))
          _navItem(
          context,
          route: 'data_exchange',
          icon: Icons.swap_vert_circle_outlined,
          selectedIcon: Icons.swap_vert_circle,
          label: context.wmnT('data_import_export'),
          collapsed: collapsed,
          drawerMode: drawerMode,
        ),
        if (r.systemModules.isEnabled('developer') &&
            r.features.isFeatureEnabled('developer.tools')) ...[
          _sectionLabel(context, context.wmnT('developer_tools'), collapsed),
          _navItem(
            context,
            route: 'developer_center',
            icon: Icons.developer_mode_outlined,
            selectedIcon: Icons.developer_mode,
            label: context.wmnT('developer_center'),
            collapsed: collapsed,
            drawerMode: drawerMode,
          ),
          _navItem(
            context,
            route: 'app_converter',
            icon: Icons.extension_outlined,
            selectedIcon: Icons.extension,
            label: context.wmnT('app_converter'),
            collapsed: collapsed,
            drawerMode: drawerMode,
          ),
          _navItem(
            context,
            route: 'compatibility',
            icon: Icons.hub_outlined,
            selectedIcon: Icons.hub,
            label: context.wmnT('compatibility_runtime'),
            collapsed: collapsed,
            drawerMode: drawerMode,
          ),
        ],
        _sectionLabel(context, context.wmnT('system'), collapsed),
        _navItem(
          context,
          route: 'platform_adapters',
          icon: Icons.devices_other_outlined,
          selectedIcon: Icons.devices_other,
          label: context.wmnT('platform_adapters'),
          collapsed: collapsed,
          drawerMode: drawerMode,
        ),
        _navItem(
          context,
          route: 'system_services',
          icon: Icons.miscellaneous_services_outlined,
          selectedIcon: Icons.miscellaneous_services,
          label: context.wmnT('system_services'),
          collapsed: collapsed,
          drawerMode: drawerMode,
        ),
        _navItem(
          context,
          route: 'settings',
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings,
          label: context.wmnT('platform_settings'),
          collapsed: collapsed,
          drawerMode: drawerMode,
        ),
      ],
    );
    return Column(
      children: [
        Expanded(child: content),
        if (!drawerMode)
          Padding(
            padding: const EdgeInsets.all(10),
            child: IconButton(
              tooltip: collapsed ? context.wmnT('expand_sidebar') : context.wmnT('collapse_sidebar'),
              onPressed: r.shell.toggleSidebar,
              icon: Icon(collapsed ? Icons.keyboard_double_arrow_right : Icons.keyboard_double_arrow_left),
            ),
          ),
      ],
    );
  }

  Widget _brand(BuildContext context, {required bool collapsed}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'W',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
            if (!collapsed) ...[
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('WMN', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    Text(
                      context.wmnT('application_platform'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );

  Widget _sectionLabel(BuildContext context, String value, bool collapsed) {
    if (collapsed) return const Padding(padding: EdgeInsets.symmetric(vertical: 7), child: Divider(height: 1));
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 5),
      child: Text(
        value.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: .55,
            ),
      ),
    );
  }

  Widget _navItem(
    BuildContext context, {
    required String route,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required bool collapsed,
    required bool drawerMode,
  }) {
    final selected = _route == route;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: collapsed ? label : '',
        child: Material(
          color: selected ? Theme.of(context).colorScheme.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              _select(route);
              if (drawerMode) Navigator.maybePop(context);
            },
            child: SizedBox(
              height: r.shell.compact ? 38 : 42,
              child: Row(
                mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                children: [
                  SizedBox(
                    width: collapsed ? 48 : 40,
                    child: Icon(
                      selected ? selectedIcon : icon,
                      size: 20,
                      color: selected ? Theme.of(context).colorScheme.onSecondaryContainer : null,
                    ),
                  ),
                  if (!collapsed)
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w600),
                      ),
                    ),
                  if (!collapsed) const SizedBox(width: 10),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _appNavItem(
    BuildContext context,
    WmnNavigationEntry entry, {
    required bool collapsed,
    required bool drawerMode,
  }) {
    final selected =
        _route == 'app_route' && _appRoutePath == entry.route.path;
    final label = entry.route.title;
    final icon = _appRouteIcon(entry.route);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: collapsed ? label : '',
        child: Material(
          color: selected
              ? Theme.of(context).colorScheme.secondaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              _selectAppRoute(entry.route.path);
              if (drawerMode) Navigator.maybePop(context);
            },
            child: SizedBox(
              height: r.shell.compact ? 38 : 42,
              child: Row(
                mainAxisAlignment: collapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  SizedBox(width: collapsed ? 48 : 40, child: Icon(icon, size: 20)),
                  if (!collapsed)
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ),
                  if (!collapsed) const SizedBox(width: 10),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _workspaceItem(
    BuildContext context,
    String name,
    String label, {
    required bool collapsed,
    required bool drawerMode,
  }) {
    final selected = _route == 'workspace' && _workspace == name;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: collapsed ? label : '',
        child: Material(
          color: selected ? Theme.of(context).colorScheme.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              _openWorkspace(name);
              if (drawerMode) Navigator.maybePop(context);
            },
            child: SizedBox(
              height: r.shell.compact ? 38 : 42,
              child: Row(
                mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                children: [
                  SizedBox(width: collapsed ? 48 : 40, child: const Icon(Icons.dashboard_customize_outlined, size: 20)),
                  if (!collapsed && r.shell.showWorkspaceLabels)
                    Expanded(
                      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  if (!collapsed) const SizedBox(width: 10),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _workspaceLabel(BuildContext context, WmnWorkspace workspace) {
    return switch (workspace.name) {
      'System' => context.wmnT('workspace_system'),
      'Administration' => context.wmnT('workspace_administration'),
      'Developer' => context.wmnT('workspace_developer'),
      _ => workspace.label,
    };
  }

  Widget _page(BuildContext context, {bool compactShell = false}) {
    return switch (_route) {
      'home' => _shellScaffold(
          context,
          title: 'WMN',
          compactShell: compactShell,
          body: _legacyUi
              ? WmnPlatformHomePage(
                  modules: r.systemModules,
                  workspaces: r.workspaces,
                  visibleWorkspaces: r.navigation.visibleWorkspaces(),
                  onOpenWorkspace: _openWorkspace,
                  onOpenSystemModules: () => _select('system_modules'),
                  onOpenApplications: () => _select('applications'),
                  onOpenDocTypes: () => _select('doctypes'),
                  onOpenMethods: () => _select('methods'),
                )
              : WmnWorkspaceHomePage(
                  workspaces: r.navigation.visibleWorkspaces(),
                  onOpenWorkspace: _openWorkspace,
                ),
        ),
      'workspace' => _workspacePage(context, compactShell: compactShell),
      'app_route' => _applicationRoutePage(context, compactShell: compactShell),
      'system_modules' => _shellScaffold(
          context,
          title: context.wmnT('system_modules'),
          compactShell: compactShell,
          body: WmnSystemModulesPage(registry: r.systemModules),
        ),
      'applications' => _shellScaffold(
          context,
          title: context.wmnT('applications'),
          compactShell: compactShell,
          body: WmnApplicationsPage(
            registry: r.applications,
            generator: r.applicationGenerator,
            fileInteractions: r.fileInteractions,
          ),
        ),
      'doctypes' => WmnDocTypeManagerPage(meta: r.meta),
      'methods' => WmnSystemMethodsPage(runtime: r.frappe),
      'reports' => _shellScaffold(
          context,
          title: context.wmnT('reports'),
          compactShell: compactShell,
          body: WmnPlatformReportsPage(reportBuilder: r.reportBuilder),
        ),
      'data_exchange' => WmnDataExchangePage(
          service: r.dataExchange,
          meta: r.meta,
          fileInteractions: r.fileInteractions,
        ),
      'developer_center' => _shellScaffold(
          context,
          title: context.wmnT('developer_center'),
          compactShell: compactShell,
          body: WmnDeveloperCenterPage(
            kernel: r.kernel,
            modules: r.systemModules,
            capabilities: r.capabilities,
            applications: r.applications,
          ),
        ),
      'app_converter' => WmnFrappeAppImportPage(
          converter: r.frappeConverter,
          packageConverter: r.frappePackageConverter,
          fileInteractions: r.fileInteractions,
        ),
      'compatibility' => WmnFrappeRuntimeStatusPage(runtime: r.frappe),
      'platform_adapters' => _shellScaffold(
          context,
          title: context.wmnT('platform_adapters'),
          compactShell: compactShell,
          body: WmnPlatformAdaptersPage(registry: r.platformAdapters),
        ),
      'system_services' => _shellScaffold(
          context,
          title: context.wmnT('system_services'),
          compactShell: compactShell,
          body: WmnSystemServicesPage(runtime: r),
        ),
      'settings' => _shellScaffold(
          context,
          title: context.wmnT('platform_settings'),
          compactShell: compactShell,
          body: WmnPlatformSettingsPage(
            database: r.database,
            locale: r.locale,
            theme: r.theme,
            shell: r.shell,
            modules: r.systemModules,
            features: r.features,
          ),
        ),
      _ => _shellScaffold(context, title: 'WMN', compactShell: compactShell, body: const SizedBox.shrink()),
    };
  }

  Widget _workspacePage(BuildContext context, {required bool compactShell}) {
    final name = _workspace;
    final bundle = name == null ? null : r.workspaces.bundle(name);
    if (bundle == null) {
      return _shellScaffold(
        context,
        title: context.wmnT('workspaces'),
        compactShell: compactShell,
        body: Center(child: Text(context.wmnT('workspace_not_found'))),
      );
    }
    if (!r.navigation.canAccessWorkspace(bundle.workspace)) {
      return _shellScaffold(
        context,
        title: context.wmnT('access_denied'),
        compactShell: compactShell,
        body: Center(child: Text(context.wmnT('access_denied'))),
      );
    }
    return _shellScaffold(
      context,
      title: _workspaceLabel(context, bundle.workspace),
      compactShell: compactShell,
      body: WmnWorkspacePage(
        workspaceName: bundle.workspace.name,
        service: r.workspaces,
        onOpenDoctype: _openDoctype,
        onOpenWorkspace: _openWorkspace,
        onOpenReport: _openReport,
        onOpenPage: _openPage,
        canReadDoctype: _canReadDoctype,
        canOpenWorkspace: _canOpenWorkspace,
        canOpenReport: _canOpenReport,
        canOpenPage: (name) => r.navigation.canAccessPage(name).allowed,
        canUseFeature: r.features.isFeatureEnabled,
      ),
    );
  }

  Widget _shellScaffold(
    BuildContext context, {
    required String title,
    required Widget body,
    required bool compactShell,
  }) => Scaffold(
        appBar: AppBar(
          toolbarHeight: 54,
          titleSpacing: compactShell ? 0 : 18,
          leadingWidth: compactShell ? 48 : null,
          leading: compactShell
              ? Builder(
                  builder: (context) => IconButton(
                    tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
                    onPressed: () => _compactScaffoldKey.currentState?.openDrawer(),
                    icon: const Icon(Icons.menu),
                  ),
                )
              : null,
          title: Text(title),
          actions: [
            if (MediaQuery.sizeOf(context).width >= WmnResponsive.inlineSearchMinWidth)
              SizedBox(
                width: 270,
                height: 38,
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: context.wmnT('global_search'),
                    prefixIcon: const Icon(Icons.search, size: 19),
                    suffixIcon: _searchController.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close, size: 18),
                          ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onSubmitted: _runGlobalSearch,
                  onChanged: (_) => setState(() {}),
                ),
              ),
            if (MediaQuery.sizeOf(context).width >= WmnResponsive.fullToolbarMinWidth)
              TextButton.icon(
                onPressed: _toggleUiMode,
                icon: Icon(
                  _legacyUi
                      ? Icons.dashboard_customize_outlined
                      : Icons.view_sidebar_outlined,
                ),
                label: Text(
                  context.wmnT(_legacyUi ? 'workspace_ui' : 'current_ui'),
                ),
              )
            else
              IconButton(
                tooltip: context.wmnT(
                  _legacyUi ? 'workspace_ui' : 'current_ui',
                ),
                onPressed: _toggleUiMode,
                icon: Icon(
                  _legacyUi
                      ? Icons.dashboard_customize_outlined
                      : Icons.view_sidebar_outlined,
                ),
              ),
            IconButton(
              tooltip: context.wmnT('language'),
              onPressed: () => r.locale.setLanguage(r.locale.languageCode == 'ar' ? 'en' : 'ar'),
              icon: const Icon(Icons.translate_outlined),
            ),
            IconButton(
              tooltip: context.wmnT('appearance'),
              onPressed: _cycleTheme,
              icon: Icon(switch (r.theme.mode) {
                ThemeMode.dark => Icons.dark_mode,
                ThemeMode.light => Icons.light_mode,
                ThemeMode.system => Icons.brightness_auto_outlined,
              }),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: body,
      );

  void _toggleUiMode() {
    setState(() {
      _legacyUi = !_legacyUi;
      _route = 'home';
      _workspace = null;
      _appRoutePath = null;
    });
  }

  void _cycleTheme() {
    final next = switch (r.theme.mode) {
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
      ThemeMode.system => ThemeMode.light,
    };
    r.theme.setMode(next);
  }

  void _runGlobalSearch(String raw) {
    final query = raw.trim().toLowerCase();
    if (query.isEmpty) return;

    final workspace = r.navigation.visibleWorkspaces().where(
          (entry) => entry.label.toLowerCase().contains(query) || entry.name.toLowerCase().contains(query),
        );
    if (workspace.isNotEmpty) {
      _openWorkspace(workspace.first.name);
      return;
    }

    final page = r.pages
        .search(query, limit: 8)
        .where((entry) => r.navigation.canAccessPage(entry.name).allowed);
    if (page.isNotEmpty) {
      _selectAppRoute(page.first.route);
      return;
    }

    final doctype = r.meta.doctypes().where(
          (entry) => entry.name.toLowerCase().contains(query) || entry.module.toLowerCase().contains(query),
        );
    if (doctype.isNotEmpty) {
      _openDoctype(doctype.first.name);
      return;
    }

    final module = WmnSystemModuleRegistry.definitions.where(
          (entry) => context.wmnT(entry.labelKey).toLowerCase().contains(query) || entry.id.contains(query),
        );
    if (module.isNotEmpty) {
      if (_legacyUi) {
        _select('system_modules');
      } else if (_canOpenWorkspace('System')) {
        _openWorkspace('System');
      }
      return;
    }

    final capability = r.capabilities.capabilities.where((entry) => entry.id.toLowerCase().contains(query));
    if (capability.isNotEmpty) {
      if (_legacyUi) {
        final id = capability.first.id;
        _select(id.startsWith('platform.') || id.startsWith('windows.') || id.startsWith('mobile.') || id.startsWith('web.') || id.startsWith('server.')
            ? 'platform_adapters'
            : 'developer_center');
      } else if (_canOpenWorkspace('Developer')) {
        _openWorkspace('Developer');
      } else if (_canOpenWorkspace('System')) {
        _openWorkspace('System');
      }
      return;
    }

    final appRoute = r.navigation.entries().where(
          (entry) =>
              entry.route.title.toLowerCase().contains(query) ||
              entry.appTitle.toLowerCase().contains(query) ||
              entry.route.path.toLowerCase().contains(query),
        );
    if (appRoute.isNotEmpty) {
      _selectAppRoute(appRoute.first.route.path);
      return;
    }

    final application = r.applications.applications().where(
          (entry) => entry.manifest.name.toLowerCase().contains(query) || entry.manifest.title.toLowerCase().contains(query),
        );
    if (application.isNotEmpty) {
      if (_legacyUi) {
        _select('applications');
      } else if (_canOpenWorkspace('Administration')) {
        _openWorkspace('Administration');
      }
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.wmnT('no_search_results'))),
    );
  }

  Widget _applicationRoutePage(
    BuildContext context, {
    required bool compactShell,
  }) {
    final path = _appRoutePath;
    if (path == null) {
      return _shellScaffold(
        context,
        title: context.wmnT('application_navigation'),
        compactShell: compactShell,
        body: Center(child: Text(context.wmnT('route_not_found'))),
      );
    }
    final entry = r.navigation.resolve(path, requireAccess: false);
    final access = r.navigation.canAccessPath(path);
    if (entry == null || !access.allowed) {
      return _shellScaffold(
        context,
        title: context.wmnT('access_denied'),
        compactShell: compactShell,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(access.reason ?? context.wmnT('access_denied')),
          ),
        ),
      );
    }

    final route = entry.route;
    return switch (route.targetType) {
      WmnAppRouteTargetType.workspace => _shellScaffold(
          context,
          title: route.title,
          compactShell: compactShell,
          body: WmnWorkspacePage(
            workspaceName: route.target,
            service: r.workspaces,
            onOpenDoctype: _openDoctype,
            onOpenWorkspace: _openWorkspace,
            onOpenReport: _openReport,
            onOpenPage: _openPage,
            canReadDoctype: _canReadDoctype,
            canOpenWorkspace: _canOpenWorkspace,
            canOpenReport: _canOpenReport,
            canOpenPage: (name) => r.navigation.canAccessPage(name).allowed,
            canUseFeature: r.features.isFeatureEnabled,
          ),
        ),
      WmnAppRouteTargetType.doctype => _applicationDoctypeRoute(
          context,
          route,
          compactShell: compactShell,
        ),
      WmnAppRouteTargetType.report => _shellScaffold(
          context,
          title: route.title,
          compactShell: compactShell,
          body: WmnApplicationReportPage(
            reportName: route.target,
            service: r.frappeReports,
          ),
        ),
      WmnAppRouteTargetType.page => _shellScaffold(
          context,
          title: route.title,
          compactShell: compactShell,
          body: WmnPageRuntimeView(
            pageName: route.target,
            pages: r.pages,
            controllers: r.pageControllers,
            navigation: r.navigation,
            meta: r.meta,
            documents: r.documents,
            customization: r.customization,
            workspaces: r.workspaces,
            reports: r.frappeReports,
            fileInteractions: r.fileInteractions,
            onOpenDoctype: _openDoctype,
            onManageLinkRecords: _manageLinkRecords,
            onOpenWorkspace: _openWorkspace,
            onOpenReport: _openReport,
            onOpenPage: _openPage,
            canReadDoctype: _canReadDoctype,
            canOpenWorkspace: _canOpenWorkspace,
            canOpenReport: _canOpenReport,
          ),
        ),
      WmnAppRouteTargetType.unsupported => _shellScaffold(
          context,
          title: context.wmnT('route_not_found'),
          compactShell: compactShell,
          body: Center(child: Text(context.wmnT('route_not_found'))),
        ),
    };
  }

  Widget _applicationDoctypeRoute(
    BuildContext context,
    WmnAppRouteDefinition route, {
    required bool compactShell,
  }) {
    final dt = r.meta.doctype(route.target, includeFields: false);
    if (dt == null || !r.frappe.hasPermission(route.target, 'read')) {
      return _shellScaffold(
        context,
        title: route.title,
        compactShell: compactShell,
        body: Center(child: Text(context.wmnT('access_denied'))),
      );
    }
    final body = dt.isSingle
        ? WmnFormView(
            doctype: route.target,
            documentName: route.target,
            meta: r.meta,
            documents: r.documents,
            customization: r.customization,
            fileInteractions: r.fileInteractions,
            onManageLinkRecords: _manageLinkRecords,
            onOpenReport: (name) async => _openReport(name),
          )
        : WmnListView(
            doctype: route.target,
            meta: r.meta,
            documents: r.documents,
            customization: r.customization,
            fileInteractions: r.fileInteractions,
            onDataImport: () => _select('data_exchange'),
            onDataExport: () => _select('data_exchange'),
            onOpenReport: (name) async => _openReport(name),
          );
    return _shellScaffold(
      context,
      title: route.title,
      compactShell: compactShell,
      body: body,
    );
  }

  bool _canReadDoctype(String doctype) =>
      r.frappe.hasPermission(doctype, 'read');

  bool _canOpenReport(String reportName) =>
      r.navigation.canAccessReport(reportName).allowed;

  bool _canOpenWorkspace(String name) {
    final bundle = r.workspaces.bundle(name);
    return bundle != null && r.navigation.canAccessWorkspace(bundle.workspace);
  }

  void _openWorkspace(String name) {
    final bundle = r.workspaces.bundle(name);
    if (bundle == null || !r.navigation.canAccessWorkspace(bundle.workspace)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.wmnT('access_denied'))),
      );
      return;
    }
    _select('workspace', workspace: name);
  }

  IconData _appRouteIcon(WmnAppRouteDefinition route) {
    final value = route.icon?.trim().toLowerCase();
    if (value != null) {
      if (value.contains('home')) return Icons.home_outlined;
      if (value.contains('report') || value.contains('chart')) {
        return Icons.analytics_outlined;
      }
      if (value.contains('user') || value.contains('person')) {
        return Icons.person_outline;
      }
      if (value.contains('setting')) return Icons.settings_outlined;
      if (value.contains('list')) return Icons.list_alt_outlined;
      if (value.contains('document') || value.contains('file')) {
        return Icons.description_outlined;
      }
    }
    return switch (route.targetType) {
      WmnAppRouteTargetType.workspace => Icons.dashboard_customize_outlined,
      WmnAppRouteTargetType.doctype => Icons.description_outlined,
      WmnAppRouteTargetType.report => Icons.analytics_outlined,
      WmnAppRouteTargetType.page => Icons.web_asset_outlined,
      WmnAppRouteTargetType.unsupported => Icons.link_off_outlined,
    };
  }

  void _openPage(String pageName) {
    final page = r.pages.page(pageName, includeDisabled: true);
    if (page == null || !r.navigation.canAccessPage(pageName).allowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.wmnT('access_denied'))),
      );
      return;
    }
    _selectAppRoute(page.route);
  }

  void _openReport(String reportName) {
    final access = r.navigation.canAccessReport(reportName);
    if (!access.allowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(access.reason ?? context.wmnT('access_denied'))),
      );
      return;
    }
    final definition = r.frappeReports.definition(reportName);
    if (definition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.wmnT('route_not_found'))),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(definition.reportName)),
          body: WmnApplicationReportPage(
            reportName: reportName,
            service: r.frappeReports,
          ),
        ),
      ),
    );
  }

  Future<void> _manageLinkRecords(String doctype) async {
    if (!r.frappe.hasPermission(doctype, 'read')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.wmnT('access_denied'))),
      );
      return;
    }
    if (r.meta.doctype(doctype, includeFields: false) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.wmnT('unknown_doctype')}: $doctype')),
      );
      return;
    }
    await WmnListView.showManageDialog(
      context,
      doctype: doctype,
      meta: r.meta,
      documents: r.documents,
      customization: r.customization,
      onDataImport: () => _select('data_exchange'),
      onDataExport: () => _select('data_exchange'),
      fileInteractions: r.fileInteractions,
    );
  }

  void _openDoctype(String doctype) {
    if (!r.frappe.hasPermission(doctype, 'read')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.wmnT('access_denied'))),
      );
      return;
    }
    final dt = r.meta.doctype(doctype, includeFields: false);
    if (dt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.wmnT('unknown_doctype')}: $doctype')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => dt.isSingle
            ? WmnFormView(
                doctype: doctype,
                documentName: doctype,
                meta: r.meta,
                documents: r.documents,
                customization: r.customization,
                fileInteractions: r.fileInteractions,
                onManageLinkRecords: _manageLinkRecords,
                onOpenReport: (name) async => _openReport(name),
              )
            : Scaffold(
                appBar: AppBar(title: Text(doctype)),
                body: WmnListView(
                  doctype: doctype,
                  meta: r.meta,
                  documents: r.documents,
                  customization: r.customization,
                  fileInteractions: r.fileInteractions,
                  onDataImport: () => _select('data_exchange'),
                  onDataExport: () => _select('data_exchange'),
                  onOpenReport: (name) async => _openReport(name),
                ),
              ),
      ),
    );
  }
}
