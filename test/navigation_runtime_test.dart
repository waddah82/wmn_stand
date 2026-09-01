import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/audit/audit_service.dart';
import 'package:wmn_standalone/core/database/wmn_database.dart';
import 'package:wmn_standalone/core/documents/document_registry.dart';
import 'package:wmn_standalone/core/settings/settings_repository.dart';
import 'package:wmn_standalone/framework/frappe_compat/frappe_runtime.dart';
import 'package:wmn_standalone/framework/meta/meta_service.dart';
import 'package:wmn_standalone/framework/model/document_service.dart';
import 'package:wmn_standalone/framework/workspaces/workspace_service.dart';
import 'package:wmn_standalone/modules/customization/data/customization_repository.dart';
import 'package:wmn_standalone/platform/apps/wmn_app_manifest.dart';
import 'package:wmn_standalone/platform/apps/wmn_application_registry.dart';
import 'package:wmn_standalone/platform/capabilities/wmn_capability_registry.dart';
import 'package:wmn_standalone/platform/features/wmn_feature_registry.dart';
import 'package:wmn_standalone/platform/pages/wmn_page_service.dart';
import 'package:wmn_standalone/platform/navigation/wmn_app_route.dart';
import 'package:wmn_standalone/platform/navigation/wmn_navigation_registry.dart';
import 'package:wmn_standalone/platform/system/wmn_system_module_registry.dart';

void main() {
  test('application routes validate explicit targets and permission tokens', () {
    final manifest = WmnAppManifest.fromJson(<String, Object?>{
      'name': 'route_app',
      'title': 'Route App',
      'version': '1.0.0',
      'route_definitions': <Map<String, Object?>>[
        <String, Object?>{
          'path': '/route-app/home',
          'title': 'Home',
          'target_type': 'workspace',
          'target': 'Route Home',
          'required_permissions': <String>[
            'doctype:Route Doc:read',
            'permission:wmn.security.manage',
          ],
        },
      ],
    });

    expect(manifest.validateStructure(), isEmpty);
    expect(manifest.routeDefinitions.single.targetType,
        WmnAppRouteTargetType.workspace);
    expect(
      manifest.routeDefinitions.single.requiredPermissions,
      containsAll(<String>[
        'doctype:Route Doc:read',
        'permission:wmn.security.manage',
      ]),
    );

    final invalid = WmnAppManifest.fromJson(<String, Object?>{
      'name': 'invalid_route_app',
      'title': 'Invalid Route App',
      'version': '1.0.0',
      'route_definitions': <Map<String, Object?>>[
        <String, Object?>{
          'path': '/invalid',
          'title': 'Invalid',
          'target_type': 'custom_flutter_page',
          'target': 'Anything',
          'required_permissions': <String>['unknown.permission'],
        },
      ],
    });
    expect(invalid.validateStructure(), isNotEmpty);
  });

  test('navigation renders only ready routes allowed for the current user', () {
    final fixture = _NavigationFixture.create();
    addTearDown(fixture.dispose);

    fixture.apps.register(
      const WmnAppManifest(
        name: 'sample_nav',
        title: 'Sample Navigation',
        version: '1.0.0',
        requiredSystemModules: <String>['workspaces'],
        routeDefinitions: <WmnAppRouteDefinition>[
          WmnAppRouteDefinition(
            path: '/apps/sample-nav/home',
            title: 'Sample Home',
            targetType: WmnAppRouteTargetType.workspace,
            target: 'Sample Home',
            requiredRoles: <String>['Sales User'],
          ),
        ],
      ),
    );
    fixture.workspaces.saveWorkspace(
      name: 'Sample Home',
      label: 'Sample Home',
      appName: 'sample_nav',
    );

    final sampleEntries = fixture.navigation.entries().where(
      (entry) => entry.appName == 'sample_nav',
    ).toList(growable: false);
    expect(sampleEntries, hasLength(1));
    expect(sampleEntries.single.route.path, '/apps/sample-nav/home');
    expect(
      fixture.navigation.resolve('/apps/sample-nav/home')?.route.target,
      'Sample Home',
    );

    fixture.frappe.session.setUser('Guest');
    expect(fixture.navigation.entries(), isEmpty);
    expect(
      fixture.navigation.canAccessPath('/apps/sample-nav/home').allowed,
      isFalse,
    );
    expect(
      fixture.navigation.visibleWorkspaces().map((entry) => entry.name),
      isNot(contains('Sample Home')),
    );
  });

  test('application registry rejects global route collisions', () {
    final fixture = _NavigationFixture.create();
    addTearDown(fixture.dispose);

    fixture.apps.register(
      const WmnAppManifest(
        name: 'first_app',
        title: 'First App',
        version: '1.0.0',
        routeDefinitions: <WmnAppRouteDefinition>[
          WmnAppRouteDefinition(
            path: '/shared/home',
            title: 'First Home',
            targetType: WmnAppRouteTargetType.workspace,
            target: 'First Workspace',
          ),
        ],
      ),
    );

    expect(
      () => fixture.apps.register(
        const WmnAppManifest(
          name: 'second_app',
          title: 'Second App',
          version: '1.0.0',
          routeDefinitions: <WmnAppRouteDefinition>[
            WmnAppRouteDefinition(
              path: '/shared/home',
              title: 'Second Home',
              targetType: WmnAppRouteTargetType.workspace,
              target: 'Second Workspace',
            ),
          ],
        ),
      ),
      throwsStateError,
    );
  });
}

class _NavigationFixture {
  _NavigationFixture({
    required this.database,
    required this.capabilities,
    required this.apps,
    required this.workspaces,
    required this.pages,
    required this.frappe,
    required this.navigation,
  });

  final WmnDatabase database;
  final WmnCapabilityRegistry capabilities;
  final WmnApplicationRegistry apps;
  final WmnWorkspaceService workspaces;
  final WmnPageService pages;
  final WmnFrappeRuntime frappe;
  final WmnNavigationRegistry navigation;

  static _NavigationFixture create() {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    final settings = SettingsRepository(database);
    final modules = WmnSystemModuleRegistry(settings);
    final capabilities = WmnCapabilityRegistry(modules);
    final apps = WmnApplicationRegistry(database, modules, capabilities);
    final registry = WmnDocumentRegistry(database);
    final customization = CustomizationRepository(database);
    final meta = WmnMetaService(
      database: database,
      registry: registry,
      customization: customization,
    );
    final audit = AuditService(database);
    final documents = WmnDocumentService(
      database: database,
      meta: meta,
      customization: customization,
      audit: audit,
    );
    final frappe = WmnFrappeRuntime.create(
      database: database,
      settings: settings,
      metaService: meta,
      documentService: documents,
      audit: audit,
    );
    final workspaces = WmnWorkspaceService(database: database, meta: meta);
    final features = WmnFeatureRegistry(database);
    final pages = WmnPageService(
      database: database,
      applications: apps,
      features: features,
    );
    final navigation = WmnNavigationRegistry(
      applications: apps,
      workspaces: workspaces,
      pages: pages,
      meta: meta,
      frappe: frappe,
    );
    return _NavigationFixture(
      database: database,
      capabilities: capabilities,
      apps: apps,
      workspaces: workspaces,
      pages: pages,
      frappe: frappe,
      navigation: navigation,
    );
  }

  void dispose() {
    apps.dispose();
    capabilities.dispose();
    database.close();
  }
}
