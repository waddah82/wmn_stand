import 'dart:convert';

import '../navigation/wmn_app_route.dart';

/// Declarative contract used by every application built on WMN.
///
/// WMN System Core never needs to know the application's business domain. An
/// application declares only the system modules, capabilities and platform
/// surfaces it consumes. Business concepts stay inside the application package.
class WmnAppManifest {
  const WmnAppManifest({
    required this.name,
    required this.title,
    required this.version,
    this.description,
    this.publisher,
    this.license,
    this.entryRoute,
    this.minimumPlatformVersion,
    this.requiredApplications = const <String>[],
    this.requiredSystemModules = const <String>[],
    this.requiredCapabilities = const <String>[],
    this.optionalCapabilities = const <String>[],
    this.capabilityProfile,
    this.modules = const <String>[],
    this.workspaces = const <String>[],
    this.pages = const <String>[],
    this.routes = const <String>[],
    this.routeDefinitions = const <WmnAppRouteDefinition>[],
    this.requiredRoles = const <String>[],
    this.permissions = const <String>[],
    this.metadataContributions = const <String>[],
    this.platformTargets = const <String>[],
    this.assets = const <String>[],
    this.metadata = const <String, Object?>{},
  });

  final String name;
  final String title;
  final String version;
  final String? description;
  final String? publisher;
  final String? license;
  final String? entryRoute;
  final String? minimumPlatformVersion;
  final List<String> requiredApplications;
  final List<String> requiredSystemModules;
  final List<String> requiredCapabilities;
  final List<String> optionalCapabilities;
  final String? capabilityProfile;
  final List<String> modules;
  final List<String> workspaces;
  final List<String> pages;
  final List<String> routes;
  final List<WmnAppRouteDefinition> routeDefinitions;
  final List<String> requiredRoles;
  final List<String> permissions;
  final List<String> metadataContributions;
  final List<String> platformTargets;
  /// Managed storage keys bundled with the application. Generator validation
  /// requires app assets to live below `apps/<app-name>/` so packages cannot
  /// overwrite platform-owned storage.
  final List<String> assets;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'title': title,
        'version': version,
        if (description != null) 'description': description,
        if (publisher != null) 'publisher': publisher,
        if (license != null) 'license': license,
        if (entryRoute != null) 'entry_route': entryRoute,
        if (minimumPlatformVersion != null)
          'minimum_platform_version': minimumPlatformVersion,
        'required_applications': requiredApplications,
        'required_system_modules': requiredSystemModules,
        'required_capabilities': requiredCapabilities,
        'optional_capabilities': optionalCapabilities,
        if (capabilityProfile != null) 'capability_profile': capabilityProfile,
        'modules': modules,
        'workspaces': workspaces,
        'pages': pages,
        'routes': routes,
        'route_definitions': routeDefinitions
            .map((route) => route.toJson())
            .toList(growable: false),
        'required_roles': requiredRoles,
        'permissions': permissions,
        'metadata_contributions': metadataContributions,
        'platform_targets': platformTargets,
        'assets': assets,
        'metadata': metadata,
      };

  String encode() => jsonEncode(toJson());

  List<String> validateStructure() {
    final issues = <String>[];
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name.trim())) {
      issues.add('Invalid application name: $name');
    }
    if (title.trim().isEmpty) issues.add('Application title is required.');
    if (!_isSemanticVersion(version)) {
      issues.add('Application version must use semantic versioning: $version');
    }
    final route = entryRoute?.trim();
    if (route != null && route.isNotEmpty && !route.startsWith('/')) {
      issues.add('Application entry route must start with /: $route');
    }

    final unsafeAssets = assets.where((asset) {
      final value = asset.trim().replaceAll('\\', '/');
      return value.isEmpty || value.startsWith('/') || value.split('/').contains('..');
    }).toList(growable: false);
    if (unsafeAssets.isNotEmpty) {
      issues.add('Application assets contain unsafe storage keys: ${unsafeAssets.join(', ')}');
    }

    final minimumVersion = minimumPlatformVersion;
    if (minimumVersion != null &&
        minimumVersion.trim().isNotEmpty &&
        !_isSemanticVersion(minimumVersion)) {
      issues.add(
        'Minimum WMN platform version must use semantic versioning: $minimumVersion',
      );
    }

    final required = requiredCapabilities.toSet();
    final overlap = optionalCapabilities.where(required.contains).toSet().toList()
      ..sort();
    if (overlap.isNotEmpty) {
      issues.add(
        'Capabilities cannot be both required and optional: ${overlap.join(', ')}',
      );
    }

    if (requiredApplications.contains(name)) {
      issues.add('Application cannot depend on itself: $name');
    }

    const knownTargets = <String>{
      'all',
      'windows',
      'mobile',
      'android',
      'ios',
      'web',
      'server',
      'linux',
      'macos',
    };
    final invalidTargets = platformTargets
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty && !knownTargets.contains(value))
        .toSet()
        .toList()
      ..sort();
    if (invalidTargets.isNotEmpty) {
      issues.add('Unknown platform targets: ${invalidTargets.join(', ')}');
    }

    final invalidRoutes = routes
        .where((route) => route.trim().isEmpty || !route.trim().startsWith('/'))
        .toSet()
        .toList()
      ..sort();
    if (invalidRoutes.isNotEmpty) {
      issues.add('Application routes must start with /: ${invalidRoutes.join(', ')}');
    }

    final routePaths = <String>{};
    for (final route in routeDefinitions) {
      issues.addAll(route.validate());
      final normalizedPath = route.path.trim();
      if (!routePaths.add(normalizedPath)) {
        issues.add('Duplicate application route path: $normalizedPath');
      }
    }
    return issues;
  }

  factory WmnAppManifest.fromJson(Map<String, Object?> value) => WmnAppManifest(
        name: '${value['name'] ?? ''}',
        title: '${value['title'] ?? value['name'] ?? ''}',
        version: '${value['version'] ?? '0.0.0'}',
        description: value['description']?.toString(),
        publisher: value['publisher']?.toString(),
        license: value['license']?.toString(),
        entryRoute: value['entry_route']?.toString(),
        minimumPlatformVersion: value['minimum_platform_version']?.toString(),
        requiredApplications: _strings(value['required_applications']),
        requiredSystemModules: _strings(value['required_system_modules']),
        requiredCapabilities: _strings(value['required_capabilities']),
        optionalCapabilities: _strings(value['optional_capabilities']),
        capabilityProfile: value['capability_profile']?.toString(),
        modules: _strings(value['modules']),
        workspaces: _strings(value['workspaces']),
        pages: _strings(value['pages']),
        routes: _strings(value['routes']),
        routeDefinitions: _routeDefinitions(value['route_definitions']),
        requiredRoles: _strings(value['required_roles']),
        permissions: _strings(value['permissions']),
        metadataContributions: _strings(value['metadata_contributions']),
        platformTargets: _strings(value['platform_targets']),
        assets: _strings(value['assets']),
        metadata: value['metadata'] is Map
            ? Map<String, Object?>.from(value['metadata'] as Map)
            : const <String, Object?>{},
      );

  static List<String> _strings(Object? value) => value is List
      ? value
          .map((entry) => '$entry'.trim())
          .where((entry) => entry.isNotEmpty)
          .toSet()
          .toList(growable: false)
      : const <String>[];


  static List<WmnAppRouteDefinition> _routeDefinitions(Object? value) {
    if (value is! List) return const <WmnAppRouteDefinition>[];
    return List<WmnAppRouteDefinition>.unmodifiable(
      value.whereType<Map>().map(
            (entry) => WmnAppRouteDefinition.fromJson(
              Map<String, Object?>.from(entry),
            ),
          ),
    );
  }

  static bool _isSemanticVersion(String value) => RegExp(
        r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$',
      ).hasMatch(value.trim());
}
