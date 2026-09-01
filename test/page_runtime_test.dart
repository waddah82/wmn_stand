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
import 'package:wmn_standalone/platform/navigation/wmn_app_route.dart';
import 'package:wmn_standalone/platform/navigation/wmn_navigation_registry.dart';
import 'package:wmn_standalone/platform/pages/wmn_page.dart';
import 'package:wmn_standalone/platform/pages/wmn_page_service.dart';
import 'package:wmn_standalone/platform/system/wmn_system_module_registry.dart';

void main() {
  test('Page definitions load lazily and reuse the bounded page cache', () {
    final fixture = _PageFixture.create();
    addTearDown(fixture.dispose);

    fixture.pages.save(
      const WmnPageDefinition(
        name: 'Light Page',
        title: 'Light Page',
        route: '/light-page',
        pageType: WmnPageType.standard,
        metadata: <String, Object?>{'show_in_navigation': true},
      ),
    );

    expect(fixture.pages.debugDatabaseReads, 0);
    expect(fixture.pages.page('Light Page')?.route, '/light-page');
    expect(fixture.pages.debugDatabaseReads, 1);
    expect(fixture.pages.page('Light Page')?.title, 'Light Page');
    expect(fixture.pages.debugDatabaseReads, 1);

    expect(
      fixture.pages.navigationPages().singleWhere(
        (page) => page.name == 'Light Page',
      ).name,
      'Light Page',
    );
    expect(fixture.pages.debugDatabaseReads, 2);
    expect(
      fixture.pages.navigationPages().singleWhere(
        (page) => page.name == 'Light Page',
      ).name,
      'Light Page',
    );
    expect(fixture.pages.debugDatabaseReads, 2);
  });

  test('Page routes resolve through navigation and enforce Page roles', () {
    final fixture = _PageFixture.create();
    addTearDown(fixture.dispose);

    fixture.apps.register(
      const WmnAppManifest(
        name: 'page_app',
        title: 'Page App',
        version: '1.0.0',
        routeDefinitions: <WmnAppRouteDefinition>[
          WmnAppRouteDefinition(
            path: '/apps/page-app/home',
            title: 'Page Home',
            targetType: WmnAppRouteTargetType.page,
            target: 'Page Home',
          ),
        ],
      ),
    );
    fixture.pages.save(
      const WmnPageDefinition(
        name: 'Page Home',
        title: 'Page Home',
        route: '/apps/page-app/home',
        appName: 'page_app',
        pageType: WmnPageType.standard,
        roles: <String>['System Manager'],
      ),
    );

    expect(
      fixture.navigation.resolve('/apps/page-app/home')?.route.targetType,
      WmnAppRouteTargetType.page,
    );

    fixture.frappe.session.setUser('Guest');
    expect(
      fixture.navigation.canAccessPath('/apps/page-app/home').allowed,
      isFalse,
    );
    expect(fixture.navigation.resolve('/apps/page-app/home'), isNull);
  });

  test('optional Page feature activation gates runtime without deleting Page metadata', () {
    final fixture = _PageFixture.create();
    addTearDown(fixture.dispose);

    fixture.pages.save(
      const WmnPageDefinition(
        name: 'Script Report Page',
        title: 'Script Report Page',
        route: '/script-report-page',
        pageType: WmnPageType.standard,
        metadata: <String, Object?>{'feature_code': 'reports.script'},
      ),
    );
    expect(fixture.navigation.canAccessPage('Script Report Page').allowed, isTrue);

    final feature = fixture.features.byCode('reports.script');
    expect(feature, isNotNull);
    expect(fixture.features.setUserEnabled(feature!.id, false), isTrue);
    expect(fixture.navigation.canAccessPage('Script Report Page').allowed, isFalse);
    expect(
      fixture.pages.page('Script Report Page', includeDisabled: true),
      isNotNull,
    );
  });

  test('Frappe Page metadata imports as a WMN Page without executing JavaScript', () {
    final fixture = _PageFixture.create();
    addTearDown(fixture.dispose);

    fixture.apps.register(
      const WmnAppManifest(
        name: 'frappe_port',
        title: 'Frappe Port',
        version: '1.0.0',
      ),
    );
    final page = fixture.pages.importFrappePage(
      <String, Object?>{
        'name': 'stock-balance',
        'title': 'Stock Balance',
        'module': 'Stock',
        'roles': <Map<String, Object?>>[
          <String, Object?>{'role': 'System Manager'},
        ],
      },
      sourceApp: 'frappe_port',
      sourcePath: 'frappe_port/stock/page/stock_balance/stock_balance.json',
    );

    expect(page.pageType, WmnPageType.custom);
    expect(page.controllerKey, 'frappe.page.stock-balance');
    expect(page.metadata['requires_controller_port'], isTrue);
    expect(page.metadata['source_framework'], 'FRAPPE');
    expect(page.route, '/apps/frappe-port/pages/stock-balance');

    final collidingSlug = fixture.pages.importFrappePage(
      <String, Object?>{'name': 'stock balance', 'title': 'Stock Balance Two'},
      sourceApp: 'frappe_port',
      sourcePath: 'frappe_port/stock/page/stock_balance_two/stock_balance_two.json',
    );
    expect(collidingSlug.route, startsWith('/apps/frappe-port/pages/stock-balance-'));
    expect(collidingSlug.route, isNot(page.route));
  });

  test('application registration rejects a route already owned by a WMN Page', () {
    final fixture = _PageFixture.create();
    addTearDown(fixture.dispose);

    fixture.pages.save(
      const WmnPageDefinition(
        name: 'System Utility',
        title: 'System Utility',
        route: '/system-utility',
        pageType: WmnPageType.standard,
      ),
    );

    expect(
      () => fixture.apps.register(
        const WmnAppManifest(
          name: 'colliding_app',
          title: 'Colliding App',
          version: '1.0.0',
          routeDefinitions: <WmnAppRouteDefinition>[
            WmnAppRouteDefinition(
              path: '/system-utility',
              title: 'Collision',
              targetType: WmnAppRouteTargetType.workspace,
              target: 'Collision',
            ),
          ],
        ),
      ),
      throwsStateError,
    );
  });
}

class _PageFixture {
  _PageFixture({
    required this.database,
    required this.capabilities,
    required this.apps,
    required this.features,
    required this.pages,
    required this.frappe,
    required this.navigation,
  });

  final WmnDatabase database;
  final WmnCapabilityRegistry capabilities;
  final WmnApplicationRegistry apps;
  final WmnFeatureRegistry features;
  final WmnPageService pages;
  final WmnFrappeRuntime frappe;
  final WmnNavigationRegistry navigation;

  static _PageFixture create() {
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
    return _PageFixture(
      database: database,
      capabilities: capabilities,
      apps: apps,
      features: features,
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
