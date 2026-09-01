import '../../framework/frappe_compat/frappe_runtime.dart';
import '../../framework/meta/meta_service.dart';
import '../../framework/workspaces/workspace_models.dart';
import '../../framework/workspaces/workspace_service.dart';
import '../apps/wmn_application_registry.dart';
import '../pages/wmn_page.dart';
import '../pages/wmn_page_service.dart';
import 'wmn_app_route.dart';

class WmnNavigationEntry {
  const WmnNavigationEntry({
    required this.appName,
    required this.appTitle,
    required this.route,
  });

  final String appName;
  final String appTitle;
  final WmnAppRouteDefinition route;
}

class WmnRouteAccessResult {
  const WmnRouteAccessResult({
    required this.allowed,
    this.reason,
  });

  final bool allowed;
  final String? reason;
}

/// Runtime resolver for application-owned navigation and metadata Pages.
///
/// Manifest routes stay declarative. Page routes are resolved lazily from
/// `tabPage`, so a Page is not loaded or rendered until it is actually needed.
/// Access is checked both when navigation is built and when a route is opened.
class WmnNavigationRegistry {
  WmnNavigationRegistry({
    required this.applications,
    required this.workspaces,
    required this.pages,
    required this.meta,
    required this.frappe,
  });

  final WmnApplicationRegistry applications;
  final WmnWorkspaceService workspaces;
  final WmnPageService pages;
  final WmnMetaService meta;
  final WmnFrappeRuntime frappe;

  List<WmnNavigationEntry> entries({bool includeHidden = false}) {
    final result = <WmnNavigationEntry>[];
    final claimedPaths = <String>{};
    for (final app in applications.applications()) {
      if (!_applicationReady(app)) continue;
      for (final route in app.manifest.routeDefinitions) {
        claimedPaths.add(route.path.trim());
        if (!includeHidden && !route.showInNavigation) continue;
        if (!canAccessRoute(app.manifest.name, route).allowed) continue;
        result.add(
          WmnNavigationEntry(
            appName: app.manifest.name,
            appTitle: app.manifest.title,
            route: route,
          ),
        );
      }
    }

    for (final page in pages.navigationPages()) {
      if (claimedPaths.contains(page.route)) continue;
      final access = canAccessPage(page.name);
      if (!access.allowed) continue;
      final app = page.appName == null
          ? null
          : applications.application(page.appName!);
      result.add(
        WmnNavigationEntry(
          appName: page.appName ?? 'wmn_system',
          appTitle: app?.manifest.title ?? 'WMN System',
          route: _pageRoute(page),
        ),
      );
    }

    result.sort((left, right) {
      final appCompare = left.appTitle.toLowerCase().compareTo(
            right.appTitle.toLowerCase(),
          );
      if (appCompare != 0) return appCompare;
      final orderCompare = left.route.order.compareTo(right.route.order);
      if (orderCompare != 0) return orderCompare;
      return left.route.title.toLowerCase().compareTo(
            right.route.title.toLowerCase(),
          );
    });
    return List<WmnNavigationEntry>.unmodifiable(result);
  }

  WmnNavigationEntry? resolve(String path, {bool requireAccess = true}) {
    final normalized = path.trim();
    for (final app in applications.applications()) {
      if (!_applicationReady(app)) continue;
      for (final route in app.manifest.routeDefinitions) {
        if (route.path.trim() != normalized) continue;
        if (requireAccess &&
            !canAccessRoute(app.manifest.name, route).allowed) {
          return null;
        }
        return WmnNavigationEntry(
          appName: app.manifest.name,
          appTitle: app.manifest.title,
          route: route,
        );
      }
    }

    final page = pages.pageByRoute(normalized, includeDisabled: true);
    if (page == null) return null;
    if (requireAccess && !canAccessPage(page.name).allowed) return null;
    final app = page.appName == null
        ? null
        : applications.application(page.appName!);
    return WmnNavigationEntry(
      appName: page.appName ?? 'wmn_system',
      appTitle: app?.manifest.title ?? 'WMN System',
      route: _pageRoute(page),
    );
  }

  WmnRouteAccessResult canAccessReport(String reportName) =>
      _reportTargetAccess(reportName.trim());

  WmnRouteAccessResult canAccessPage(String pageName) =>
      _pageTargetAccess(pageName.trim());

  WmnRouteAccessResult canAccessPath(String path) {
    final entry = resolve(path, requireAccess: false);
    if (entry == null) {
      return const WmnRouteAccessResult(
        allowed: false,
        reason:
            'Application route or Page is not registered or its application is not ready.',
      );
    }
    if (entry.route.targetType == WmnAppRouteTargetType.page) {
      return _pageTargetAccess(entry.route.target);
    }
    return canAccessRoute(entry.appName, entry.route);
  }

  WmnRouteAccessResult canAccessRoute(
    String appName,
    WmnAppRouteDefinition route,
  ) {
    if (route.targetType == WmnAppRouteTargetType.page) {
      final page = pages.page(route.target, includeDisabled: true);
      if (page == null) {
        return WmnRouteAccessResult(
          allowed: false,
          reason: 'Page target does not exist: ${route.target}',
        );
      }
      final pageApp = page.appName?.trim() ?? '';
      if (pageApp.isNotEmpty && pageApp != appName) {
        return const WmnRouteAccessResult(
          allowed: false,
          reason: 'Page target belongs to a different application.',
        );
      }
      if (pageApp.isNotEmpty) {
        final app = applications.application(pageApp);
        if (app == null || !_applicationReady(app)) {
          return const WmnRouteAccessResult(
            allowed: false,
            reason: 'Application is not installed and ready.',
          );
        }
        final appAccess = _applicationRoleAccess(app);
        if (!appAccess.allowed) return appAccess;
      }
      final routeAccess = _routeGateAccess(route);
      if (!routeAccess.allowed) return routeAccess;
      return _pageTargetAccess(route.target);
    }

    final app = applications.application(appName);
    if (app == null || !_applicationReady(app)) {
      return const WmnRouteAccessResult(
        allowed: false,
        reason: 'Application is not installed and ready.',
      );
    }
    final appAccess = _applicationRoleAccess(app);
    if (!appAccess.allowed) return appAccess;
    final routeAccess = _routeGateAccess(route);
    if (!routeAccess.allowed) return routeAccess;

    return switch (route.targetType) {
      WmnAppRouteTargetType.workspace => _workspaceTargetAccess(route.target),
      WmnAppRouteTargetType.doctype => _doctypeTargetAccess(route.target),
      WmnAppRouteTargetType.report => _reportTargetAccess(route.target),
      WmnAppRouteTargetType.page => _pageTargetAccess(route.target),
      WmnAppRouteTargetType.unsupported => const WmnRouteAccessResult(
          allowed: false,
          reason: 'Unsupported application route target.',
        ),
    };
  }

  List<WmnWorkspace> visibleWorkspaces() {
    final result = <WmnWorkspace>[];
    for (final workspace in workspaces.workspaces()) {
      if (canAccessWorkspace(workspace)) result.add(workspace);
    }
    return List<WmnWorkspace>.unmodifiable(result);
  }

  bool canAccessWorkspace(WmnWorkspace workspace) {
    final appName = workspace.appName?.trim();
    if (appName != null && appName.isNotEmpty) {
      final app = applications.application(appName);
      if (app == null || !_applicationReady(app)) return false;

      final matchingRoutes = app.manifest.routeDefinitions.where(
        (route) =>
            route.targetType == WmnAppRouteTargetType.workspace &&
            route.target == workspace.name,
      );
      if (matchingRoutes.isNotEmpty) {
        return matchingRoutes.any(
          (route) => canAccessRoute(appName, route).allowed,
        );
      }

      final appRoles = app.manifest.requiredRoles.toSet();
      final userRoles = frappe.permissions.rolesFor().toSet();
      if (!_isSystemUser(userRoles) &&
          appRoles.isNotEmpty &&
          userRoles.intersection(appRoles).isEmpty) {
        return false;
      }
    }

    return _workspaceIntrinsicAccess(workspace);
  }

  bool _applicationReady(WmnInstalledApplication app) {
    if (app.status != 'READY') return false;
    return applications.diagnose(app.manifest).compatible;
  }

  WmnRouteAccessResult _applicationRoleAccess(WmnInstalledApplication app) {
    final roles = frappe.permissions.rolesFor().toSet();
    if (_isSystemUser(roles)) {
      return const WmnRouteAccessResult(allowed: true);
    }
    final appRoles = app.manifest.requiredRoles
        .map((role) => role.trim())
        .where((role) => role.isNotEmpty)
        .toSet();
    if (appRoles.isNotEmpty && roles.intersection(appRoles).isEmpty) {
      return const WmnRouteAccessResult(
        allowed: false,
        reason: 'Current user does not have an application role.',
      );
    }
    return const WmnRouteAccessResult(allowed: true);
  }

  WmnRouteAccessResult _routeGateAccess(WmnAppRouteDefinition route) {
    final roles = frappe.permissions.rolesFor().toSet();
    final systemUser = _isSystemUser(roles);
    final routeRoles = route.requiredRoles
        .map((role) => role.trim())
        .where((role) => role.isNotEmpty)
        .toSet();
    if (!systemUser &&
        routeRoles.isNotEmpty &&
        roles.intersection(routeRoles).isEmpty) {
      return const WmnRouteAccessResult(
        allowed: false,
        reason: 'Current user does not have a route role.',
      );
    }
    for (final token in route.requiredPermissions) {
      if (!_hasPermissionToken(token)) {
        return WmnRouteAccessResult(
          allowed: false,
          reason: 'Permission denied: $token',
        );
      }
    }
    return const WmnRouteAccessResult(allowed: true);
  }

  bool _hasPermissionToken(String token) {
    if (!WmnAppRouteDefinition.isSupportedPermissionToken(token)) return false;
    final parts = token.trim().split(':');
    if (parts.first.toLowerCase() == 'permission') {
      return frappe.permissions.hasSystemPermission(parts[1].trim());
    }
    return frappe.permissions.hasPermission(
      parts[1].trim(),
      parts[2].trim().toLowerCase(),
    );
  }

  WmnRouteAccessResult _pageTargetAccess(String name) {
    final page = pages.page(name, includeDisabled: true);
    if (page == null) {
      return WmnRouteAccessResult(
        allowed: false,
        reason: 'Page target does not exist: $name',
      );
    }
    if (!pages.isRuntimeEnabled(page)) {
      return const WmnRouteAccessResult(
        allowed: false,
        reason: 'Page or its required feature is disabled.',
      );
    }

    final appName = page.appName?.trim() ?? '';
    if (appName.isNotEmpty) {
      final app = applications.application(appName);
      if (app == null || !_applicationReady(app)) {
        return const WmnRouteAccessResult(
          allowed: false,
          reason: 'Page application is not installed and ready.',
        );
      }
      final appAccess = _applicationRoleAccess(app);
      if (!appAccess.allowed) return appAccess;
    }

    final roles = frappe.permissions.rolesFor().toSet();
    if (!_isSystemUser(roles) && page.roles.isNotEmpty) {
      if (roles.intersection(page.roles.toSet()).isEmpty) {
        return const WmnRouteAccessResult(
          allowed: false,
          reason: 'Current user does not have a Page role.',
        );
      }
    }
    for (final token in page.permissions) {
      if (!_hasPermissionToken(token)) {
        return WmnRouteAccessResult(
          allowed: false,
          reason: 'Page permission denied: $token',
        );
      }
    }

    final target = page.target;
    return switch (page.pageType) {
      WmnPageType.list || WmnPageType.form => target == null
          ? const WmnRouteAccessResult(
              allowed: false,
              reason: 'Page DocType target is missing.',
            )
          : _doctypeTargetAccess(target),
      WmnPageType.report => target == null
          ? const WmnRouteAccessResult(
              allowed: false,
              reason: 'Page Report target is missing.',
            )
          : _reportTargetAccess(target),
      WmnPageType.workspace => target == null
          ? const WmnRouteAccessResult(
              allowed: false,
              reason: 'Page Workspace target is missing.',
            )
          : _workspaceTargetAccess(target),
      WmnPageType.dashboard => target == null
          ? const WmnRouteAccessResult(allowed: true)
          : _workspaceTargetAccess(target),
      WmnPageType.standard || WmnPageType.custom =>
        const WmnRouteAccessResult(allowed: true),
    };
  }

  WmnAppRouteDefinition _pageRoute(WmnPageDefinition page) {
    return WmnAppRouteDefinition(
      path: page.route,
      title: page.title,
      targetType: WmnAppRouteTargetType.page,
      target: page.name,
      icon: page.icon,
      section: page.section ?? page.module,
      order: page.order,
      showInNavigation: page.showInNavigation,
      requiredRoles: page.roles,
      requiredPermissions: page.permissions,
    );
  }

  WmnRouteAccessResult _workspaceTargetAccess(String name) {
    final bundle = workspaces.bundle(name);
    if (bundle == null) {
      return WmnRouteAccessResult(
        allowed: false,
        reason: 'Workspace target does not exist: $name',
      );
    }
    if (!_workspaceIntrinsicAccess(bundle.workspace)) {
      return const WmnRouteAccessResult(
        allowed: false,
        reason: 'Workspace access is denied.',
      );
    }
    return const WmnRouteAccessResult(allowed: true);
  }

  WmnRouteAccessResult _doctypeTargetAccess(String doctype) {
    if (meta.doctype(doctype, includeFields: false) == null) {
      return WmnRouteAccessResult(
        allowed: false,
        reason: 'DocType target does not exist: $doctype',
      );
    }
    if (!frappe.permissions.hasPermission(doctype, 'read')) {
      return const WmnRouteAccessResult(
        allowed: false,
        reason: 'DocType read access is denied.',
      );
    }
    return const WmnRouteAccessResult(allowed: true);
  }

  WmnRouteAccessResult _reportTargetAccess(String reportName) {
    final rows = workspaces.database.db.select(
      'SELECT ref_doctype,disabled FROM [tabReport] '
      'WHERE name = ? OR report_name = ? LIMIT 1;',
      <Object?>[reportName, reportName],
    );
    if (rows.isEmpty) {
      return WmnRouteAccessResult(
        allowed: false,
        reason: 'Report target does not exist: $reportName',
      );
    }
    if ((rows.first['disabled'] as int? ?? 0) == 1) {
      return const WmnRouteAccessResult(
        allowed: false,
        reason: 'Report target is disabled.',
      );
    }
    final doctype = '${rows.first['ref_doctype'] ?? ''}'.trim();
    if (doctype.isNotEmpty &&
        (!frappe.permissions.hasPermission(doctype, 'read') ||
            !frappe.permissions.hasPermission(doctype, 'report'))) {
      return const WmnRouteAccessResult(
        allowed: false,
        reason: 'Report access is denied.',
      );
    }
    return const WmnRouteAccessResult(allowed: true);
  }

  bool _workspaceIntrinsicAccess(WmnWorkspace workspace) {
    final requiredFeature =
        '${workspace.metadata['required_feature'] ?? ''}'.trim();
    if (requiredFeature.isNotEmpty &&
        !pages.features.isFeatureEnabled(requiredFeature)) {
      return false;
    }
    final requiredRoles = _workspaceRoles(workspace);
    final userRoles = frappe.permissions.rolesFor().toSet();
    if (_isSystemUser(userRoles)) return true;
    if (requiredRoles.isNotEmpty &&
        userRoles.intersection(requiredRoles).isEmpty) {
      return false;
    }
    if (!workspace.isPublic && requiredRoles.isEmpty) {
      return _isSystemUser(userRoles);
    }
    return true;
  }

  Set<String> _workspaceRoles(WmnWorkspace workspace) {
    final roles = <String>{};
    final direct = workspace.metadata['required_roles'];
    if (direct is List) {
      roles.addAll(
        direct
            .map((entry) => '$entry'.trim())
            .where((entry) => entry.isNotEmpty),
      );
    }
    final raw = workspace.metadata['raw'];
    if (raw is Map) {
      final rawRoles = raw['roles'];
      if (rawRoles is List) {
        for (final entry in rawRoles) {
          if (entry is Map) {
            final role = '${entry['role'] ?? entry['name'] ?? ''}'.trim();
            if (role.isNotEmpty) roles.add(role);
          } else {
            final role = '$entry'.trim();
            if (role.isNotEmpty) roles.add(role);
          }
        }
      }
    }
    return roles;
  }

  bool _isSystemUser(Set<String> roles) =>
      roles.contains('Administrator') ||
      roles.contains('System Manager') ||
      roles.contains('SYSTEM_ADMIN');
}
