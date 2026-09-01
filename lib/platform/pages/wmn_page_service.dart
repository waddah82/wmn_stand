import 'dart:convert';

import '../../core/database/wmn_database.dart';
import '../apps/wmn_application_registry.dart';
import '../features/wmn_feature_registry.dart';
import 'wmn_page.dart';

/// Lightweight metadata owner for WMN Page records.
///
/// Page definitions are loaded on demand. A small bounded cache avoids repeated
/// SQLite reads during navigation while keeping memory usage predictable on
/// older mobile devices. Page content/widgets are never pre-built or retained.
class WmnPageService {
  WmnPageService({
    required this.database,
    required this.applications,
    required this.features,
  });

  final WmnDatabase database;
  final WmnApplicationRegistry applications;
  final WmnFeatureRegistry features;

  static const int cacheLimit = 12;
  final Map<String, WmnPageDefinition> _byName =
      <String, WmnPageDefinition>{};
  final Map<String, String> _routeToName = <String, String>{};
  List<WmnPageDefinition>? _navigationCache;

  int _databaseReads = 0;
  int get debugDatabaseReads => _databaseReads;

  WmnPageDefinition? page(String name, {bool includeDisabled = false}) {
    final normalized = name.trim();
    if (normalized.isEmpty) return null;
    final cached = _byName.remove(normalized);
    if (cached != null) {
      _byName[normalized] = cached;
      return includeDisabled || cached.enabled ? cached : null;
    }
    final rows = database.db.select(
      'SELECT * FROM [tabPage] WHERE name=? LIMIT 1;',
      <Object?>[normalized],
    );
    _databaseReads += 1;
    if (rows.isEmpty) return null;
    final loaded = WmnPageDefinition.fromDatabaseRow(
      <String, Object?>{for (final entry in rows.first.entries) entry.key: entry.value},
    );
    _cache(loaded);
    return includeDisabled || loaded.enabled ? loaded : null;
  }

  WmnPageDefinition? pageByRoute(
    String route, {
    bool includeDisabled = false,
  }) {
    final normalized = _normalizeRoute(route);
    if (normalized == null) return null;
    final cachedName = _routeToName.remove(normalized);
    if (cachedName != null) {
      _routeToName[normalized] = cachedName;
      final cached = page(cachedName, includeDisabled: includeDisabled);
      if (cached != null) return cached;
    }
    final rows = database.db.select(
      'SELECT * FROM [tabPage] WHERE route=? LIMIT 1;',
      <Object?>[normalized],
    );
    _databaseReads += 1;
    if (rows.isEmpty) return null;
    final loaded = WmnPageDefinition.fromDatabaseRow(
      <String, Object?>{for (final entry in rows.first.entries) entry.key: entry.value},
    );
    _cache(loaded);
    return includeDisabled || loaded.enabled ? loaded : null;
  }

  /// Reads only the columns required to build navigation. Full page metadata is
  /// still lazy and fetched only when a page is opened or access is checked.
  List<WmnPageDefinition> navigationPages() {
    final cached = _navigationCache;
    if (cached != null) return cached;
    final rows = database.db.select('''
      SELECT name,title,route,app_name,module,page_type,controller_key,
             roles_json,permissions_json,enabled,metadata_json
      FROM [tabPage]
      WHERE enabled=1
      ORDER BY app_name COLLATE NOCASE, title COLLATE NOCASE;
    ''');
    _databaseReads += 1;
    final result = <WmnPageDefinition>[];
    for (final row in rows) {
      final page = WmnPageDefinition.fromDatabaseRow(
        <String, Object?>{for (final entry in row.entries) entry.key: entry.value},
      );
      if (!page.showInNavigation) continue;
      result.add(page);
      _cache(page);
    }
    _navigationCache = List<WmnPageDefinition>.unmodifiable(result);
    return _navigationCache!;
  }

  List<WmnPageDefinition> search(String query, {int limit = 12}) {
    final normalized = query.trim();
    if (normalized.isEmpty) return const <WmnPageDefinition>[];
    final safeLimit = limit.clamp(1, 50);
    final pattern = '%$normalized%';
    final rows = database.db.select(
      r'''SELECT * FROM [tabPage]
          WHERE enabled=1
            AND (title LIKE ? COLLATE NOCASE
                 OR name LIKE ? COLLATE NOCASE
                 OR route LIKE ? COLLATE NOCASE)
          ORDER BY title COLLATE NOCASE LIMIT ?;''',
      <Object?>[pattern, pattern, pattern, safeLimit],
    );
    _databaseReads += 1;
    return List<WmnPageDefinition>.unmodifiable(
      rows.map((row) {
        final page = WmnPageDefinition.fromDatabaseRow(
          <String, Object?>{
            for (final entry in row.entries) entry.key: entry.value,
          },
        );
        _cache(page);
        return page;
      }),
    );
  }

  List<WmnPageDefinition> applicationPages(
    String appName, {
    bool includeDisabled = true,
  }) {
    final normalized = appName.trim();
    if (normalized.isEmpty) return const <WmnPageDefinition>[];
    final rows = database.db.select(
      'SELECT * FROM [tabPage] WHERE app_name=? '
      '${includeDisabled ? '' : 'AND enabled=1 '}ORDER BY title COLLATE NOCASE;',
      <Object?>[normalized],
    );
    _databaseReads += 1;
    final result = rows.map((row) {
      final page = WmnPageDefinition.fromDatabaseRow(
        <String, Object?>{
          for (final entry in row.entries) entry.key: entry.value,
        },
      );
      _cache(page);
      return page;
    }).toList(growable: false);
    return List<WmnPageDefinition>.unmodifiable(result);
  }

  bool isRuntimeEnabled(WmnPageDefinition page) =>
      page.enabled && _featureEnabled(page);

  void save(WmnPageDefinition page) {
    final name = page.name.trim();
    final route = _normalizeRoute(page.route);
    if (name.isEmpty) throw StateError('Page name is required.');
    if (page.title.trim().isEmpty) throw StateError('Page title is required.');
    if (route == null) throw StateError('Page route must start with /.');
    _validateApp(page.appName);
    _validateRouteCollision(name, route);
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO [tabPage](
        name,title,route,app_name,module,page_type,controller_key,roles_json,
        permissions_json,enabled,metadata_json,created_at,updated_at
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(name) DO UPDATE SET
        title=excluded.title,route=excluded.route,app_name=excluded.app_name,
        module=excluded.module,page_type=excluded.page_type,
        controller_key=excluded.controller_key,roles_json=excluded.roles_json,
        permissions_json=excluded.permissions_json,enabled=excluded.enabled,
        metadata_json=excluded.metadata_json,updated_at=excluded.updated_at;
    ''', <Object?>[
      name,
      page.title.trim(),
      route,
      page.appName,
      page.module.trim().isEmpty ? 'WMN System' : page.module.trim(),
      page.pageType.storageValue,
      page.controllerKey,
      jsonEncode(page.roles),
      jsonEncode(page.permissions),
      page.enabled ? 1 : 0,
      jsonEncode(page.metadata),
      now,
      now,
    ]);
    invalidate(name: name, route: route);
  }

  WmnPageDefinition importFrappePage(
    Map<String, Object?> source, {
    required String sourceApp,
    required String sourcePath,
  }) {
    final rawName = '${source['name'] ?? source['page_name'] ?? ''}'.trim();
    if (rawName.isEmpty) throw StateError('Frappe Page has no name.');
    final title = '${source['title'] ?? rawName}'.trim();
    final explicitRoute = _normalizeRoute('${source['route'] ?? ''}');
    final route = explicitRoute ??
        _uniqueGeneratedImportRoute(sourceApp, rawName, sourcePath);
    final roles = <String>{};
    final rawRoles = source['roles'];
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
    final page = WmnPageDefinition(
      name: rawName,
      title: title.isEmpty ? rawName : title,
      route: route,
      appName: sourceApp,
      module: '${source['module'] ?? 'Custom'}'.trim(),
      pageType: WmnPageType.custom,
      controllerKey: 'frappe.page.${_slug(rawName)}',
      roles: roles.toList(growable: false)..sort(),
      permissions: const <String>[],
      enabled: source['disabled'] != 1,
      metadata: <String, Object?>{
        'source_framework': 'FRAPPE',
        'source_path': sourcePath,
        'show_in_navigation': false,
        'requires_controller_port': true,
        'raw': source,
      },
    );
    save(page);
    return page;
  }

  void invalidate({String? name, String? route}) {
    _navigationCache = null;
    if (name == null && route == null) {
      _byName.clear();
      _routeToName.clear();
      return;
    }
    if (name != null) {
      final removed = _byName.remove(name);
      if (removed != null) _routeToName.remove(removed.route);
    }
    if (route != null) _routeToName.remove(route);
  }

  bool _featureEnabled(WmnPageDefinition page) {
    final code = page.featureCode;
    return code == null || features.isFeatureEnabled(code);
  }

  void _cache(WmnPageDefinition page) {
    _byName.remove(page.name);
    _routeToName.remove(page.route);
    while (_byName.length >= cacheLimit) {
      final oldest = _byName.keys.first;
      final removed = _byName.remove(oldest);
      if (removed != null) _routeToName.remove(removed.route);
    }
    while (_routeToName.length >= cacheLimit) {
      _routeToName.remove(_routeToName.keys.first);
    }
    _byName[page.name] = page;
    _routeToName[page.route] = page.name;
  }

  void _validateApp(String? appName) {
    final normalized = appName?.trim() ?? '';
    if (normalized.isEmpty) return;
    final app = applications.application(normalized);
    if (app == null) throw StateError('Unknown application for Page: $normalized');
  }

  void _validateRouteCollision(String pageName, String route) {
    final pageRows = database.db.select(
      'SELECT name FROM [tabPage] WHERE route=? AND name<>? LIMIT 1;',
      <Object?>[route, pageName],
    );
    if (pageRows.isNotEmpty) {
      throw StateError('Page route is already registered: $route');
    }
    for (final app in applications.applications()) {
      for (final definition in app.manifest.routeDefinitions) {
        if (definition.path.trim() == route &&
            !(definition.targetType.name == 'page' &&
                definition.target.trim() == pageName)) {
          throw StateError(
            'Page route collides with application route $route (${app.manifest.name}).',
          );
        }
      }
    }
  }


  String _uniqueGeneratedImportRoute(
    String sourceApp,
    String pageName,
    String sourcePath,
  ) {
    final base = '/apps/${_slug(sourceApp)}/pages/${_slug(pageName)}';
    if (!_routeOwnedByAnotherPage(base, pageName) &&
        !_routeOwnedByApplication(base, pageName)) {
      return base;
    }
    return '$base-${_stableSuffix('$sourceApp|$pageName|$sourcePath')}';
  }

  bool _routeOwnedByAnotherPage(String route, String pageName) {
    return database.db.select(
      'SELECT 1 FROM [tabPage] WHERE route=? AND name<>? LIMIT 1;',
      <Object?>[route, pageName],
    ).isNotEmpty;
  }

  bool _routeOwnedByApplication(String route, String pageName) {
    for (final app in applications.applications()) {
      for (final definition in app.manifest.routeDefinitions) {
        if (definition.path.trim() == route &&
            !(definition.targetType.name == 'page' &&
                definition.target.trim() == pageName)) {
          return true;
        }
      }
    }
    return false;
  }

  String _stableSuffix(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0').substring(0, 8);
  }

  String? _normalizeRoute(String value) {
    final normalized = value.trim();
    if (!normalized.startsWith('/') ||
        normalized.contains(' ') ||
        normalized.contains('//')) {
      return null;
    }
    return normalized;
  }

  String _slug(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return normalized.isEmpty ? 'page' : normalized;
  }
}
