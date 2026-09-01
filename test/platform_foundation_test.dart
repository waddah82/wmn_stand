import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/database/wmn_database.dart';
import 'package:wmn_standalone/core/documents/document_registry.dart';
import 'package:wmn_standalone/core/settings/settings_repository.dart';
import 'package:wmn_standalone/framework/meta/meta_service.dart';
import 'package:wmn_standalone/framework/workspaces/workspace_service.dart';
import 'package:wmn_standalone/modules/customization/data/customization_repository.dart';
import 'package:wmn_standalone/platform/apps/wmn_app_manifest.dart';
import 'package:wmn_standalone/platform/apps/wmn_application_registry.dart';
import 'package:wmn_standalone/platform/capabilities/wmn_capability_registry.dart';
import 'package:wmn_standalone/platform/kernel/wmn_extension_registry.dart';
import 'package:wmn_standalone/platform/kernel/wmn_kernel.dart';
import 'package:wmn_standalone/platform/system/wmn_shell_preferences.dart';
import 'package:wmn_standalone/platform/system/wmn_system_module_registry.dart';

void main() {
  test('system module registry separates foundation, dependencies and planned capabilities', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final settings = SettingsRepository(database);
    final modules = WmnSystemModuleRegistry(settings);

    expect(modules.isEnabled('kernel'), isTrue);
    expect(modules.isEnabled('documents'), isTrue);
    expect(modules.isEnabled('security'), isTrue);
    expect(modules.validateDependencyGraph(), isEmpty);
    expect(modules.dependenciesOf('documents'), containsAll(['metadata', 'data']));

    modules.setEnabled('security', false);
    expect(modules.isEnabled('security'), isTrue);

    modules.setEnabled('kernel', false);
    expect(modules.isEnabled('kernel'), isTrue);

    expect(modules.hasCapability('doctype'), isTrue);
    expect(modules.hasCapability('server-mode'), isFalse);
    modules.setEnabled('server', true);
    expect(modules.isEnabled('security'), isTrue);
    expect(modules.isEnabled('scheduler'), isTrue);
    expect(modules.hasCapability('server-mode'), isFalse);
  });

  test('capability registry resolves providers without advertising planned adapters', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final settings = SettingsRepository(database);
    final modules = WmnSystemModuleRegistry(settings);
    final capabilities = WmnCapabilityRegistry(modules);
    addTearDown(capabilities.dispose);

    expect(capabilities.isAvailable('forms'), isTrue);
    expect(capabilities.isAvailable('filesystem'), isTrue);
    expect(capabilities.isAvailable('contacts'), isFalse);
    expect(capabilities.isAvailable('authentication'), isFalse);
    expect(capabilities.descriptor('contacts')?.providerModuleIds, contains('mobile'));
    expect(capabilities.profile('minimal').requiredCapabilities, contains('doctype'));
  });

  test('kernel owns service and native extension registries without business concepts', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final settings = SettingsRepository(database);
    final modules = WmnSystemModuleRegistry(settings);
    final capabilities = WmnCapabilityRegistry(modules);
    addTearDown(capabilities.dispose);
    final apps = WmnApplicationRegistry(database, modules, capabilities);
    addTearDown(apps.dispose);
    final kernel = WmnKernel(modules: modules, capabilities: capabilities, applications: apps);
    addTearDown(kernel.dispose);

    kernel.services.register('wmn.database', database);
    kernel.extensions.define(const WmnExtensionPoint(id: 'test.point', description: 'Test point'));
    kernel.extensions.register(
      WmnExtensionRegistration(pointId: 'test.point', ownerId: 'test_app', handler: const Object()),
    );
    kernel.start();

    expect(kernel.state, WmnKernelState.ready);
    expect(kernel.services.resolve<WmnDatabase>('wmn.database'), same(database));
    expect(kernel.extensions.handlersFor('test.point'), hasLength(1));
    expect(kernel.snapshot().registeredServices, 1);
  });

  test('shell preferences are persisted independently from application modules', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final settings = SettingsRepository(database);
    final shell = WmnShellPreferences(settings);

    expect(shell.sidebarCollapsed, isFalse);
    shell.setSidebarCollapsed(true);
    shell.setCompact(true);

    final reloaded = WmnShellPreferences(settings);
    expect(reloaded.sidebarCollapsed, isTrue);
    expect(reloaded.compact, isTrue);
  });

  test('platform workspaces are seeded without ERP/POS navigation', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final registry = WmnDocumentRegistry(database);
    final customization = CustomizationRepository(database);
    final meta = WmnMetaService(database: database, registry: registry, customization: customization);
    final workspaces = WmnWorkspaceService(database: database, meta: meta);

    workspaces.ensurePlatformWorkspaces();
    final names = workspaces.workspaces().map((entry) => entry.name).toSet();
    expect(names, containsAll(<String>{'System', 'Administration', 'Developer'}));
    expect(names, isNot(contains('Accounts')));
    expect(names, isNot(contains('Selling')));
    expect(names, isNot(contains('Stock')));
  });

  test('system modules expose contract versions and deterministic dependency order', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final settings = SettingsRepository(database);
    final modules = WmnSystemModuleRegistry(settings);

    expect(modules.definition('kernel').version, '1.0.0');
    final order = modules.enabledInDependencyOrder().map((entry) => entry.id).toList();
    expect(order.indexOf('kernel'), lessThan(order.indexOf('data')));
    expect(order.indexOf('metadata'), lessThan(order.indexOf('documents')));
    expect(modules.validateDependencyGraph(), isEmpty);
  });

  test('capability state protects core contracts and preserves dependency safety', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final settings = SettingsRepository(database);
    final modules = WmnSystemModuleRegistry(settings);
    final capabilities = WmnCapabilityRegistry(modules);
    addTearDown(capabilities.dispose);

    final forms = capabilities.descriptor('forms');
    expect(forms, isNotNull);
    expect(forms!.providerVersions['ui'], '1.0.0');
    expect(forms.requiredCapabilities, containsAll(<String>['doctype', 'save']));
    expect(forms.supportedPlatforms, <String>['all']);

    expect(capabilities.updateEnabled('doctype', false), isFalse);
    expect(capabilities.isAvailable('doctype'), isTrue);

    expect(capabilities.updateEnabled('printing', false), isTrue);
    expect(capabilities.isAvailable('printing'), isFalse);
    expect(capabilities.updateEnabled('printing', true), isTrue);
    expect(capabilities.isAvailable('printing'), isTrue);

    expect(capabilities.updateEnabled('print-contract', false), isFalse);
    expect(capabilities.validateDependencyGraph(), isEmpty);
  });


  test('dashboard charts aggregate local DocType values natively', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final registry = WmnDocumentRegistry(database);
    final customization = CustomizationRepository(database);
    final meta = WmnMetaService(
      database: database,
      registry: registry,
      customization: customization,
    );
    final workspaces = WmnWorkspaceService(database: database, meta: meta);

    meta.saveDocType(name: 'Chart Sample', module: 'Platform Test');
    meta.saveField(
      doctype: 'Chart Sample',
      fieldName: 'category',
      label: 'Category',
      fieldType: 'Data',
    );
    meta.saveField(
      doctype: 'Chart Sample',
      fieldName: 'amount',
      label: 'Amount',
      fieldType: 'Currency',
    );
    database.db.execute('''
      INSERT INTO [tabChart Sample](name,creation,modified,category,amount)
      VALUES
        ('ROW-1','2026-08-28','2026-08-28','A',10),
        ('ROW-2','2026-08-28','2026-08-28','A',5),
        ('ROW-3','2026-08-28','2026-08-28','B',7);
    ''');

    workspaces.saveDashboardChart(<String, Object?>{
      'name': 'Amount by Category',
      'label': 'Amount by Category',
      'type': 'Bar',
      'document_type': 'Chart Sample',
      'based_on': 'category',
      'value_based_on': 'amount',
    });

    expect(WmnWorkspaceService.dashboardChartsEnabled, isTrue);
    final series = workspaces.dashboardChartSeries('Amount by Category');
    expect(series, hasLength(2));
    expect(series.first['label'], 'A');
    expect(series.first['value'], 15);
    expect(series.last['label'], 'B');
    expect(series.last['value'], 7);
  });

  test('dashboard charts fail closed for unsupported metadata fields', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final registry = WmnDocumentRegistry(database);
    final customization = CustomizationRepository(database);
    final meta = WmnMetaService(
      database: database,
      registry: registry,
      customization: customization,
    );
    final workspaces = WmnWorkspaceService(database: database, meta: meta);

    meta.saveDocType(name: 'Chart Guard', module: 'Platform Test');
    meta.saveField(
      doctype: 'Chart Guard',
      fieldName: 'category',
      label: 'Category',
      fieldType: 'Data',
    );
    workspaces.saveDashboardChart(<String, Object?>{
      'name': 'Invalid Chart',
      'document_type': 'Chart Guard',
      'based_on': 'missing_field',
    });

    expect(workspaces.dashboardChartSeries('Invalid Chart'), isEmpty);
  });

  test('kernel health reacts when an installed app loses an optional capability', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final settings = SettingsRepository(database);
    final modules = WmnSystemModuleRegistry(settings);
    final capabilities = WmnCapabilityRegistry(modules);
    addTearDown(capabilities.dispose);
    final apps = WmnApplicationRegistry(database, modules, capabilities);
    addTearDown(apps.dispose);
    final kernel = WmnKernel(
      modules: modules,
      capabilities: capabilities,
      applications: apps,
    );
    addTearDown(kernel.dispose);

    apps.register(
      const WmnAppManifest(
        name: 'printing_app',
        title: 'Printing App',
        version: '1.0.0',
        requiredCapabilities: <String>['printing'],
      ),
    );
    kernel.start();
    expect(kernel.state, WmnKernelState.ready);

    expect(capabilities.updateEnabled('printing', false), isTrue);
    expect(kernel.state, WmnKernelState.degraded);
    expect(kernel.issues.join(' '), contains('printing_app'));
  });

}
