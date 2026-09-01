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
import 'package:wmn_standalone/platform/apps/wmn_application_registry.dart';
import 'package:wmn_standalone/platform/capabilities/wmn_capability_registry.dart';
import 'package:wmn_standalone/platform/features/wmn_feature_registry.dart';
import 'package:wmn_standalone/platform/navigation/wmn_navigation_registry.dart';
import 'package:wmn_standalone/platform/pages/wmn_page_service.dart';
import 'package:wmn_standalone/platform/system/wmn_system_module_registry.dart';

void main() {
  test('platform seeds workspace-first system navigation without legacy workspace names', () {
    final fixture = _WorkspaceShellFixture.create();
    addTearDown(fixture.dispose);

    fixture.workspaces.ensurePlatformWorkspaces();
    final names = fixture.workspaces
        .workspaces(includeHidden: true)
        .map((entry) => entry.name)
        .toSet();

    expect(names, containsAll(<String>{'System', 'Administration', 'Developer'}));
    expect(names, isNot(contains('WMN Platform')));
    expect(names, isNot(contains('Developer Studio')));
  });

  test('system and administration workspaces navigate through System DocTypes', () {
    final fixture = _WorkspaceShellFixture.create();
    addTearDown(fixture.dispose);

    fixture.workspaces.ensurePlatformWorkspaces();
    final system = fixture.workspaces.bundle('System')!;
    final administration = fixture.workspaces.bundle('Administration')!;

    final links = <String>{
      ...system.items.where((entry) => entry.linkType == 'DocType').map((entry) => entry.linkTo!),
      ...administration.items.where((entry) => entry.linkType == 'DocType').map((entry) => entry.linkTo!),
    };
    final registered = fixture.database.db
        .select('SELECT name FROM wmn_doctypes WHERE is_system=1 AND enabled=1;')
        .map((row) => '${row['name']}')
        .toSet();

    expect(links, isNotEmpty);
    expect(registered.containsAll(links), isTrue);
    expect(
      system.items.any(
        (entry) =>
            entry.linkTo == 'Printer' &&
            entry.data['required_feature'] == 'printing',
      ),
      isTrue,
    );
  });

  test('platform workspace seeding is idempotent after the current seed version', () {
    final fixture = _WorkspaceShellFixture.create();
    addTearDown(fixture.dispose);

    fixture.workspaces.ensurePlatformWorkspaces();
    final before = fixture.database.db
        .select("SELECT name FROM [tabWorkspaceItem] WHERE parent='System' AND parenttype='Workspace' AND parentfield='items' ORDER BY idx;")
        .map((row) => '${row['name']}')
        .toList(growable: false);

    fixture.workspaces.ensurePlatformWorkspaces();
    final after = fixture.database.db
        .select("SELECT name FROM [tabWorkspaceItem] WHERE parent='System' AND parenttype='Workspace' AND parentfield='items' ORDER BY idx;")
        .map((row) => '${row['name']}')
        .toList(growable: false);

    expect(after, before);
  });

  test('developer workspace follows user-controlled developer feature activation', () {
    final fixture = _WorkspaceShellFixture.create();
    addTearDown(fixture.dispose);

    fixture.workspaces.ensurePlatformWorkspaces();
    expect(
      fixture.navigation.visibleWorkspaces().map((entry) => entry.name),
      contains('Developer'),
    );

    expect(
      fixture.features.setUserEnabled('feature-developer-tools', false),
      isTrue,
    );
    expect(
      fixture.navigation.visibleWorkspaces().map((entry) => entry.name),
      isNot(contains('Developer')),
    );
  });
}

class _WorkspaceShellFixture {
  _WorkspaceShellFixture({
    required this.database,
    required this.workspaces,
    required this.features,
    required this.navigation,
  });

  final WmnDatabase database;
  final WmnWorkspaceService workspaces;
  final WmnFeatureRegistry features;
  final WmnNavigationRegistry navigation;

  static _WorkspaceShellFixture create() {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    final settings = SettingsRepository(database);
    final modules = WmnSystemModuleRegistry(settings);
    final capabilities = WmnCapabilityRegistry(modules);
    final applications = WmnApplicationRegistry(database, modules, capabilities);
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
      applications: applications,
      features: features,
    );
    final navigation = WmnNavigationRegistry(
      applications: applications,
      workspaces: workspaces,
      pages: pages,
      meta: meta,
      frappe: frappe,
    );
    return _WorkspaceShellFixture(
      database: database,
      workspaces: workspaces,
      features: features,
      navigation: navigation,
    );
  }

  void dispose() => database.close();
}
