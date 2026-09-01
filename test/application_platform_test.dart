import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/database/wmn_database.dart';
import 'package:wmn_standalone/core/settings/settings_repository.dart';
import 'package:wmn_standalone/platform/apps/wmn_app_manifest.dart';
import 'package:wmn_standalone/platform/apps/wmn_application_registry.dart';
import 'package:wmn_standalone/platform/capabilities/wmn_capability_registry.dart';
import 'package:wmn_standalone/platform/navigation/wmn_app_route.dart';
import 'package:wmn_standalone/platform/system/wmn_system_module_registry.dart';

void main() {
  test('application manifest round-trips without business-domain assumptions', () {
    const manifest = WmnAppManifest(
      name: 'sample_app',
      title: 'Sample App',
      version: '1.2.3',
      description: 'A domain-neutral WMN application.',
      publisher: 'WMN Test',
      license: 'MIT',
      entryRoute: '/home',
      minimumPlatformVersion: '3.4.0',
      requiredApplications: ['foundation_app'],
      requiredSystemModules: ['metadata', 'documents'],
      requiredCapabilities: ['doctype', 'create', 'save'],
      optionalCapabilities: ['printing'],
      capabilityProfile: 'minimal',
      modules: ['Core'],
      workspaces: ['Home'],
      routes: ['/home'],
      routeDefinitions: <WmnAppRouteDefinition>[
        WmnAppRouteDefinition(
          path: '/home',
          title: 'Home',
          targetType: WmnAppRouteTargetType.workspace,
          target: 'Home',
          requiredRoles: <String>['Sample User'],
        ),
      ],
      requiredRoles: ['Sample User'],
      permissions: ['sample.read'],
      metadataContributions: ['Sample DocType'],
      platformTargets: ['windows', 'mobile'],
      assets: ['apps/sample_app/assets/logo.svg'],
      metadata: {'owner': 'test'},
    );

    final decoded = WmnAppManifest.fromJson(
      Map<String, Object?>.from(jsonDecode(manifest.encode()) as Map),
    );

    expect(decoded.name, 'sample_app');
    expect(decoded.publisher, 'WMN Test');
    expect(decoded.license, 'MIT');
    expect(decoded.entryRoute, '/home');
    expect(decoded.minimumPlatformVersion, '3.4.0');
    expect(decoded.requiredApplications, contains('foundation_app'));
    expect(decoded.requiredSystemModules, containsAll(['metadata', 'documents']));
    expect(decoded.requiredCapabilities, containsAll(['doctype', 'create', 'save']));
    expect(decoded.optionalCapabilities, contains('printing'));
    expect(decoded.capabilityProfile, 'minimal');
    expect(decoded.routes, contains('/home'));
    expect(decoded.routeDefinitions.single.target, 'Home');
    expect(decoded.routeDefinitions.single.requiredRoles, contains('Sample User'));
    expect(decoded.requiredRoles, contains('Sample User'));
    expect(decoded.permissions, contains('sample.read'));
    expect(decoded.metadataContributions, contains('Sample DocType'));
    expect(decoded.platformTargets, containsAll(['windows', 'mobile']));
    expect(decoded.assets, contains('apps/sample_app/assets/logo.svg'));
  });

  test('application registry enforces executable WMN modules and capabilities', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final settings = SettingsRepository(database);
    final modules = WmnSystemModuleRegistry(settings);
    final capabilities = WmnCapabilityRegistry(modules);
    addTearDown(capabilities.dispose);
    final apps = WmnApplicationRegistry(database, modules, capabilities);
    addTearDown(apps.dispose);

    const basic = WmnAppManifest(
      name: 'basic_app',
      title: 'Basic App',
      version: '0.1.0',
      requiredSystemModules: ['metadata', 'documents'],
      requiredCapabilities: ['doctype', 'create'],
      optionalCapabilities: ['camera'],
      capabilityProfile: 'minimal',
    );
    final diagnostic = apps.diagnose(basic);
    expect(diagnostic.compatible, isTrue);
    expect(diagnostic.warnings, isNotEmpty);

    apps.register(basic);
    expect(apps.application('basic_app')?.manifest.title, 'Basic App');

    const serverApp = WmnAppManifest(
      name: 'server_app',
      title: 'Server App',
      version: '0.1.0',
      requiredSystemModules: ['server'],
      requiredCapabilities: ['server-mode'],
    );
    expect(() => apps.register(serverApp), throwsStateError);

    modules.setEnabled('server', true);
    expect(modules.isEnabled('security'), isTrue);
    expect(modules.isEnabled('scheduler'), isTrue);
    expect(capabilities.isAvailable('server-mode'), isFalse);
    expect(() => apps.register(serverApp), throwsStateError);
  });

  test('application registry enforces platform version and application dependencies', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final settings = SettingsRepository(database);
    final modules = WmnSystemModuleRegistry(settings);
    final capabilities = WmnCapabilityRegistry(modules);
    addTearDown(capabilities.dispose);
    final apps = WmnApplicationRegistry(database, modules, capabilities);
    addTearDown(apps.dispose);

    const futureApp = WmnAppManifest(
      name: 'future_app',
      title: 'Future App',
      version: '1.0.0',
      minimumPlatformVersion: '99.0.0',
    );
    expect(apps.diagnose(futureApp).compatible, isFalse);

    const extension = WmnAppManifest(
      name: 'extension_app',
      title: 'Extension App',
      version: '1.0.0',
      requiredApplications: <String>['foundation_app'],
    );
    expect(apps.diagnose(extension).compatible, isFalse);

    const foundation = WmnAppManifest(
      name: 'foundation_app',
      title: 'Foundation App',
      version: '1.0.0',
      minimumPlatformVersion: '3.4.0',
    );
    apps.register(foundation);
    expect(apps.diagnose(extension).compatible, isTrue);
    apps.register(extension);
    expect(() => apps.remove('foundation_app'), throwsStateError);
  });

}
