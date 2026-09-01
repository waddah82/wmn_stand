import '../wmn_platform_adapter.dart';

WmnPlatformAdapter createMobilePlatformAdapter() => const _UnavailableMobileAdapter();

class _UnavailableMobileAdapter implements WmnPlatformAdapter {
  const _UnavailableMobileAdapter();

  @override
  String get id => 'mobile';
  @override
  String get moduleId => 'mobile';
  @override
  String get displayName => 'Mobile';
  @override
  WmnPlatformAdapterStatus get status => WmnPlatformAdapterStatus.unavailable;
  @override
  List<WmnRuntimePlatform> get supportedPlatforms => const <WmnRuntimePlatform>[
        WmnRuntimePlatform.android,
        WmnRuntimePlatform.ios,
      ];
  @override
  List<WmnPlatformCapability> get capabilities => const <WmnPlatformCapability>[
        WmnPlatformCapability(id: 'platform.mobile', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'mobile.device-info', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'mobile.filesystem', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'files.pick', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'files.pick-multiple', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'files.save', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'files.external-reference', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'external-open', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'browser', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'clipboard', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'connectivity', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'device-info', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'permissions', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'contacts', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'sms', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'share', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'camera', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'scanner', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'mobile.permissions', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'mobile.contacts', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'mobile.sms.read', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'mobile.sms.send', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'mobile.share', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'mobile.whatsapp.share', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'mobile.camera', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'mobile.scanner', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'mobile.secure-storage', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'mobile.bluetooth-gatt', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'mobile.connectivity', status: WmnPlatformCapabilityStatus.unavailable),
      ];
  @override
  Map<String, Object> get services => const <String, Object>{};
  @override
  Future<void> initialize() async {}
  @override
  Future<void> refresh() async {}
  @override
  Map<String, Object?> diagnostics() => const <String, Object?>{'runtime': 'unavailable'};
}
