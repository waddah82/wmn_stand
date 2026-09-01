import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/database/wmn_database.dart';
import 'package:wmn_standalone/core/settings/settings_repository.dart';
import 'package:wmn_standalone/platform/adapters/wmn_platform_adapter.dart';
import 'package:wmn_standalone/platform/adapters/wmn_platform_adapter_registry.dart';
import 'package:wmn_standalone/platform/apps/wmn_app_manifest.dart';
import 'package:wmn_standalone/platform/apps/wmn_application_registry.dart';
import 'package:wmn_standalone/platform/capabilities/wmn_capability.dart';
import 'package:wmn_standalone/platform/capabilities/wmn_capability_registry.dart';
import 'package:wmn_standalone/platform/system/wmn_system_module_registry.dart';

class _FakeWindowsAdapter implements WmnPlatformAdapter {
  @override
  String get id => 'windows-test';
  @override
  String get moduleId => 'windows';
  @override
  String get displayName => 'Windows Test';
  @override
  WmnPlatformAdapterStatus get status => WmnPlatformAdapterStatus.foundation;
  @override
  List<WmnRuntimePlatform> get supportedPlatforms => const <WmnRuntimePlatform>[WmnRuntimePlatform.windows];
  @override
  List<WmnPlatformCapability> get capabilities => const <WmnPlatformCapability>[
        WmnPlatformCapability(
          id: 'filesystem',
          status: WmnPlatformCapabilityStatus.foundation,
          serviceId: 'wmn.platform.windows.test',
        ),
        WmnPlatformCapability(
          id: 'usb',
          status: WmnPlatformCapabilityStatus.planned,
        ),
      ];
  @override
  Map<String, Object> get services => <String, Object>{'wmn.platform.windows.test': this};
  @override
  Future<void> initialize() async {}
  @override
  Future<void> refresh() async {}
  @override
  Map<String, Object?> diagnostics() => const <String, Object?>{'test': true};
}

void main() {
  test('platform adapter registry exposes only runtime-matching capabilities and services', () async {
    final registry = WmnPlatformAdapterRegistry(
      adapters: <WmnPlatformAdapter>[_FakeWindowsAdapter()],
      runtimePlatform: WmnRuntimePlatform.windows,
    );
    addTearDown(registry.dispose);

    await registry.initialize();

    expect(registry.runtimeModuleId, 'windows');
    expect(registry.isAvailable('filesystem'), isTrue);
    expect(registry.isAvailable('usb'), isFalse);
    expect(registry.serviceIds, contains('wmn.platform.windows.test'));
    expect(registry.resolveService<_FakeWindowsAdapter>('wmn.platform.windows.test'), isA<_FakeWindowsAdapter>());
  });

  test('capability registry gates platform module capabilities by active host adapter', () async {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final settings = SettingsRepository(database);
    final modules = WmnSystemModuleRegistry(settings);
    final adapters = WmnPlatformAdapterRegistry(
      adapters: <WmnPlatformAdapter>[_FakeWindowsAdapter()],
      runtimePlatform: WmnRuntimePlatform.web,
    );
    addTearDown(adapters.dispose);
    await adapters.initialize();
    final capabilities = WmnCapabilityRegistry(modules, platformAdapters: adapters);
    addTearDown(capabilities.dispose);

    expect(modules.isEnabled('windows'), isTrue);
    expect(capabilities.isAvailable('filesystem'), isFalse);
    expect(capabilities.descriptor('filesystem')?.status, WmnCapabilityStatus.unavailable);
  });

  test('application registry validates manifest platform targets against the active adapter', () async {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final settings = SettingsRepository(database);
    final modules = WmnSystemModuleRegistry(settings);
    final adapters = WmnPlatformAdapterRegistry(
      adapters: <WmnPlatformAdapter>[_FakeWindowsAdapter()],
      runtimePlatform: WmnRuntimePlatform.windows,
    );
    addTearDown(adapters.dispose);
    await adapters.initialize();
    final capabilities = WmnCapabilityRegistry(modules, platformAdapters: adapters);
    addTearDown(capabilities.dispose);
    final applications = WmnApplicationRegistry(
      database,
      modules,
      capabilities,
      platformAdapters: adapters,
    );
    addTearDown(applications.dispose);

    const mobileOnly = WmnAppManifest(
      name: 'mobile_only',
      title: 'Mobile Only',
      version: '0.1.0',
      platformTargets: <String>['mobile'],
    );
    final diagnostic = applications.diagnose(mobileOnly);
    expect(diagnostic.compatible, isFalse);
    expect(diagnostic.errors.join(' '), contains('windows'));
  });

}
