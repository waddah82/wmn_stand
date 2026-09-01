import '../wmn_platform_adapter.dart';

/// Server-mode contract adapter.
///
/// The Flutter desktop/mobile runtime does not automatically become a server.
/// R3.3 defines the stable contracts/capabilities only. A dedicated WMN server
/// host will activate these capabilities later.
class WmnServerPlatformAdapter implements WmnPlatformAdapter {
  @override
  String get id => 'server';
  @override
  String get moduleId => 'server';
  @override
  String get displayName => 'Server';
  @override
  WmnPlatformAdapterStatus get status => WmnPlatformAdapterStatus.planned;
  @override
  List<WmnRuntimePlatform> get supportedPlatforms => const <WmnRuntimePlatform>[WmnRuntimePlatform.server];
  @override
  List<WmnPlatformCapability> get capabilities => const <WmnPlatformCapability>[
        WmnPlatformCapability(id: 'platform.server', status: WmnPlatformCapabilityStatus.planned),
        WmnPlatformCapability(id: 'api', status: WmnPlatformCapabilityStatus.planned),
        WmnPlatformCapability(id: 'tokens', status: WmnPlatformCapabilityStatus.planned),
        WmnPlatformCapability(id: 'postgresql', status: WmnPlatformCapabilityStatus.planned),
        WmnPlatformCapability(id: 'server-mode', status: WmnPlatformCapabilityStatus.planned),
        WmnPlatformCapability(id: 'server.api', status: WmnPlatformCapabilityStatus.planned),
        WmnPlatformCapability(id: 'server.tokens', status: WmnPlatformCapabilityStatus.planned),
        WmnPlatformCapability(id: 'server.authentication', status: WmnPlatformCapabilityStatus.planned),
        WmnPlatformCapability(id: 'server.postgresql', status: WmnPlatformCapabilityStatus.planned),
        WmnPlatformCapability(id: 'server.sync', status: WmnPlatformCapabilityStatus.planned),
        WmnPlatformCapability(id: 'server.jobs', status: WmnPlatformCapabilityStatus.planned),
        WmnPlatformCapability(id: 'server.files', status: WmnPlatformCapabilityStatus.planned),
        WmnPlatformCapability(id: 'server.health', status: WmnPlatformCapabilityStatus.planned),
      ];
  @override
  Map<String, Object> get services => const <String, Object>{};
  @override
  Future<void> initialize() async {}
  @override
  Future<void> refresh() async {}
  @override
  Map<String, Object?> diagnostics() => const <String, Object?>{
        'note': 'Dedicated WMN server host is deferred; contracts are stable in R3.3.',
      };
}
