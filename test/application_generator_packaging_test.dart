import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/database/wmn_database.dart';
import 'package:wmn_standalone/core/documents/document_registry.dart';
import 'package:wmn_standalone/core/settings/settings_repository.dart';
import 'package:wmn_standalone/modules/customization/data/customization_repository.dart';
import 'package:wmn_standalone/framework/meta/meta_service.dart';
import 'package:wmn_standalone/platform/apps/wmn_app_manifest.dart';
import 'package:wmn_standalone/platform/apps/wmn_application_generator_service.dart';
import 'package:wmn_standalone/platform/apps/wmn_application_registry.dart';
import 'package:wmn_standalone/platform/capabilities/wmn_capability_registry.dart';
import 'package:wmn_standalone/platform/storage/wmn_storage_adapter.dart';
import 'package:wmn_standalone/platform/storage/wmn_storage_service.dart';
import 'package:wmn_standalone/platform/system/wmn_system_module_registry.dart';

void main() {
  test('schema v36 registers application build profile and build runtime', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);

    final names = database.db
        .select("SELECT name FROM sqlite_master WHERE type='table';")
        .map((row) => '${row['name']}')
        .toSet();
    expect(names, contains('tabApplication Build Profile'));
    expect(names, contains('tabApplication Build'));

    final doctypes = database.db
        .select("SELECT name FROM wmn_doctypes WHERE name LIKE 'Application Build%';")
        .map((row) => '${row['name']}')
        .toSet();
    expect(doctypes, containsAll(<String>['Application Build Profile', 'Application Build']));
  });

  test('application generator creates a portable package and installs metadata on a clean runtime', () {
    final source = _fixture();
    addTearDown(source.dispose);

    const manifest = WmnAppManifest(
      name: 'sample_app',
      title: 'Sample Application',
      version: '1.0.0',
      publisher: 'WMN Test',
      license: 'MIT',
      entryRoute: '/sample',
      modules: <String>['Sample'],
      routes: <String>['/sample'],
      optionalCapabilities: <String>['mobile.camera'],
      platformTargets: <String>['android'],
      assets: <String>['apps/sample_app/assets/logo.txt'],
    );
    source.apps.register(manifest);
    source.meta.saveDocType(name: 'Sample Document', module: 'Sample');
    source.meta.saveField(
      doctype: 'Sample Document',
      fieldName: 'title',
      label: 'Title',
      fieldType: 'Data',
      required: true,
      inListView: true,
    );
    source.storage.writeText('apps/sample_app/assets/logo.txt', 'sample-logo');
    source.database.db.execute('''
      INSERT INTO [tabPage](name,title,route,app_name,module,page_type,enabled,metadata_json,created_at,updated_at)
      VALUES ('sample-page','Sample','/sample','sample_app','Sample','LIST',1,'{}',datetime('now'),datetime('now'));
    ''');
    source.database.db.execute('''
      INSERT INTO [tabWorkspace](name,label,module,app_name,sequence_id,is_public,is_hidden,content_json,metadata_json,created_at,updated_at)
      VALUES ('Sample Workspace','Sample Workspace','Sample','sample_app',10,1,0,'[]','{}',datetime('now'),datetime('now'));
    ''');
    source.database.db.execute('''
      INSERT INTO [tabWorkspaceItem](name,creation,modified,docstatus,idx,parent,parentfield,parenttype,region,item_type,label,link_type,link_to,parent_label,column_span,hidden,item_json)
      VALUES ('sample-workspace-document',datetime('now'),datetime('now'),0,1,'Sample Workspace','items','Workspace','SHORTCUTS','shortcut','Sample Document','DocType','Sample Document','Masters',4,0,'{}');
    ''');

    final diagnostic = source.generator.validateBuild('sample_app');
    expect(diagnostic.errors, isEmpty);
    expect(diagnostic.componentCounts['doctypes'], 1);
    expect(diagnostic.componentCounts['workspaces'], 1);
    expect(diagnostic.componentCounts['workspace_items'], 1);

    final build = source.generator.generatePackage('sample_app');
    expect(build.fileName, 'sample_app-1.0.0.zip');
    expect(build.bytes, isNotEmpty);
    expect(build.sha256, hasLength(64));
    expect(source.generator.builds('sample_app').first['status'], 'READY');

    final inspection = source.generator.inspectPackage(build.bytes);
    expect(inspection.manifest.name, 'sample_app');
    expect(inspection.manifest.publisher, 'WMN Test');
    expect(inspection.manifest.assets, contains('apps/sample_app/assets/logo.txt'));
    expect(inspection.componentCounts['doctypes'], 1);
    expect(inspection.componentCounts['pages'], 1);
    expect(inspection.componentCounts['workspaces'], 1);
    expect(inspection.componentCounts['workspace_items'], 1);
    expect(inspection.targets, hasLength(1));
    expect(inspection.targets.single['target'], 'android');
    final hostRequirements = Map<String, Object?>.from(
      inspection.targets.single['host_requirements']! as Map,
    );
    expect(
      hostRequirements['android_permissions'],
      contains('android.permission.CAMERA'),
    );

    final target = _fixture();
    addTearDown(target.dispose);
    final installed = target.generator.installPackage(build.bytes);
    expect(installed.manifest.name, 'sample_app');
    expect(installed.updatedExistingApplication, isFalse);
    expect(target.apps.application('sample_app')?.manifest.version, '1.0.0');
    expect(target.meta.doctype('Sample Document'), isNotNull);
    expect(
      target.database.db
          .select('PRAGMA table_info("tabSample Document");')
          .map((row) => '${row['name']}'),
      contains('title'),
    );
    expect(
      target.database.db.select("SELECT app_name FROM wmn_modules WHERE name='Sample';").first['app_name'],
      'sample_app',
    );
    expect(
      target.database.db.select("SELECT app_name FROM [tabPage] WHERE name='sample-page';").first['app_name'],
      'sample_app',
    );
    expect(
      target.database.db.select("SELECT app_name FROM [tabWorkspace] WHERE name='Sample Workspace';").first['app_name'],
      'sample_app',
    );
    final installedWorkspaceItems = target.database.db.select(
      "SELECT label,link_type,link_to,parent_label FROM [tabWorkspaceItem] WHERE parent='Sample Workspace' AND parenttype='Workspace' AND parentfield='items' ORDER BY idx;",
    );
    expect(installedWorkspaceItems, hasLength(1));
    expect(installedWorkspaceItems.single['label'], 'Sample Document');
    expect(installedWorkspaceItems.single['link_type'], 'DocType');
    expect(installedWorkspaceItems.single['link_to'], 'Sample Document');
    expect(installedWorkspaceItems.single['parent_label'], 'Masters');
    expect(target.storage.readText('apps/sample_app/assets/logo.txt'), 'sample-logo');
    expect(target.generator.builds('sample_app').first['status'], 'IMPORTED');
  });

  test('application package never includes system DocTypes or business records', () {
    final fixture = _fixture();
    addTearDown(fixture.dispose);
    const manifest = WmnAppManifest(
      name: 'clean_app',
      title: 'Clean App',
      version: '1.0.0',
      modules: <String>['Clean'],
    );
    fixture.apps.register(manifest);
    fixture.meta.saveDocType(name: 'Clean Document', module: 'Clean');
    fixture.database.db.execute(
      'INSERT INTO "tabClean Document"(name,owner,creation,modified,docstatus) VALUES (?,?,?,?,0);',
      <Object?>['DOC-1', 'test', '2026-01-01', '2026-01-01'],
    );

    final build = fixture.generator.generatePackage('clean_app');
    final target = _fixture();
    addTearDown(target.dispose);
    target.generator.installPackage(build.bytes);
    expect(
      target.database.db.select('SELECT COUNT(*) AS value FROM "tabClean Document";').first['value'],
      0,
    );
  });

  test('generator never emits a package when validation has hard errors', () {
    final fixture = _fixture();
    addTearDown(fixture.dispose);
    const manifest = WmnAppManifest(
      name: 'invalid_app',
      title: 'Invalid App',
      version: '1.0.0',
      modules: <String>['Missing Module'],
    );
    fixture.apps.register(manifest);
    fixture.database.db.execute(
      "DELETE FROM wmn_modules WHERE name='Missing Module';",
    );

    final diagnostic = fixture.generator.validateBuild('invalid_app');
    expect(diagnostic.errors, isNotEmpty);
    expect(
      () => fixture.generator.generatePackage(
        'invalid_app',
        profileName: 'Development',
      ),
      throwsStateError,
    );
  });
}

_AppFixture _fixture() {
  final database = WmnDatabase.forTesting(sqlite3.openInMemory());
  final settings = SettingsRepository(database);
  final modules = WmnSystemModuleRegistry(settings);
  final capabilities = WmnCapabilityRegistry(modules);
  final apps = WmnApplicationRegistry(database, modules, capabilities);
  final meta = WmnMetaService(
    database: database,
    registry: WmnDocumentRegistry(database),
    customization: CustomizationRepository(database),
  );
  final storage = WmnStorageService(WmnMemoryStorageAdapter());
  final generator = WmnApplicationGeneratorService(
    database: database,
    applications: apps,
    meta: meta,
    storage: storage,
  );
  return _AppFixture(
    database: database,
    capabilities: capabilities,
    apps: apps,
    meta: meta,
    storage: storage,
    generator: generator,
  );
}

class _AppFixture {
  const _AppFixture({
    required this.database,
    required this.capabilities,
    required this.apps,
    required this.meta,
    required this.storage,
    required this.generator,
  });

  final WmnDatabase database;
  final WmnCapabilityRegistry capabilities;
  final WmnApplicationRegistry apps;
  final WmnMetaService meta;
  final WmnStorageService storage;
  final WmnApplicationGeneratorService generator;

  void dispose() {
    apps.dispose();
    capabilities.dispose();
    database.close();
  }
}
