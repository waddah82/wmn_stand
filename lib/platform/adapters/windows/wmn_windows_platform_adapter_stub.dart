import '../wmn_platform_adapter.dart';

WmnPlatformAdapter createWindowsPlatformAdapter() => const _UnavailableWindowsAdapter();

class _UnavailableWindowsAdapter implements WmnPlatformAdapter {
  const _UnavailableWindowsAdapter();

  @override
  String get id => 'windows';
  @override
  String get moduleId => 'windows';
  @override
  String get displayName => 'Windows';
  @override
  WmnPlatformAdapterStatus get status => WmnPlatformAdapterStatus.unavailable;
  @override
  List<WmnRuntimePlatform> get supportedPlatforms => const <WmnRuntimePlatform>[WmnRuntimePlatform.windows];
  @override
  List<WmnPlatformCapability> get capabilities => const <WmnPlatformCapability>[
        WmnPlatformCapability(id: 'platform.windows', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'filesystem', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'windows.filesystem', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'system-info', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'windows.system-info', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'shell', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'windows.shell', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'devices', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'windows.device-discovery', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'windows.printer-discovery', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'windows.serial-discovery', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'printing', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'usb', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'serial', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'windows.usb', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'windows.serial', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'windows.bluetooth', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'windows.network-devices', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'windows.camera', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'windows.scanner', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'external-open', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'share', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'windows.share', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'clipboard', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'windows.clipboard', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'connectivity', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'windows.connectivity', status: WmnPlatformCapabilityStatus.unavailable),
        WmnPlatformCapability(id: 'device-info', status: WmnPlatformCapabilityStatus.unavailable),
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
