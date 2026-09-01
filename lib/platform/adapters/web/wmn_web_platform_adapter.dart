import '../../files/adapters/wmn_native_file_dialog_adapter.dart';
import '../native/wmn_flutter_native_services.dart';
import '../wmn_platform_adapter.dart';

/// Web contract adapter.
///
/// R3.3 establishes the capability boundary without bundling browser-specific
/// packages into the WMN core. Concrete browser services can be registered in
/// later releases without changing applications.
class WmnWebPlatformAdapter implements WmnPlatformAdapter {
  final WmnNativeFileDialogAdapter _fileDialogs = WmnNativeFileDialogAdapter(
    runtimePlatform: WmnRuntimePlatform.web,
  );
  final WmnNativeShareService _share = const WmnNativeShareService();
  final WmnNativeBrowserService _browser = const WmnNativeBrowserService();
  final WmnNativeClipboardService _clipboard = const WmnNativeClipboardService();
  final WmnNativeConnectivityService _connectivity = WmnNativeConnectivityService();
  final WmnNativeDeviceInfoService _deviceInfo = WmnNativeDeviceInfoService();
  final WmnNativeDownloadService _download = const WmnNativeDownloadService();
  final WmnNativeCameraService _camera = WmnNativeCameraService();
  @override
  String get id => 'web';
  @override
  String get moduleId => 'web';
  @override
  String get displayName => 'Web';
  @override
  WmnPlatformAdapterStatus get status => WmnPlatformAdapterStatus.foundation;
  @override
  List<WmnRuntimePlatform> get supportedPlatforms => const <WmnRuntimePlatform>[WmnRuntimePlatform.web];
  @override
  List<WmnPlatformCapability> get capabilities => const <WmnPlatformCapability>[
        WmnPlatformCapability(id: 'platform.web', status: WmnPlatformCapabilityStatus.foundation),
        WmnPlatformCapability(id: 'browser', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.browser'),
        WmnPlatformCapability(id: 'download', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.web.download'),
        WmnPlatformCapability(id: 'web-storage', status: WmnPlatformCapabilityStatus.planned),
        WmnPlatformCapability(id: 'web-print', status: WmnPlatformCapabilityStatus.available, description: 'System PDF printing is provided by the Printing package adapter.'),
        WmnPlatformCapability(id: 'web.browser', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.browser'),
        WmnPlatformCapability(id: 'web.download', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.web.download'),
        WmnPlatformCapability(id: 'web.upload', status: WmnPlatformCapabilityStatus.foundation, serviceId: 'wmn.files.dialog'),
        WmnPlatformCapability(id: 'files.pick', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.files.dialog'),
        WmnPlatformCapability(id: 'files.pick-multiple', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.files.dialog'),
        WmnPlatformCapability(id: 'files.save', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.files.dialog', description: 'Browser save/export uses the WMN native file adapter and browser download flow.'),
        WmnPlatformCapability(id: 'files.external-reference', status: WmnPlatformCapabilityStatus.unavailable, serviceId: 'wmn.files.dialog', description: 'Browsers do not expose a persistent local path reference; use Managed Storage.'),
        WmnPlatformCapability(id: 'external-open', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.browser'),
        WmnPlatformCapability(id: 'share', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.share'),
        WmnPlatformCapability(id: 'clipboard', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.clipboard'),
        WmnPlatformCapability(id: 'connectivity', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.connectivity'),
        WmnPlatformCapability(id: 'device-info', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.device-info'),
        WmnPlatformCapability(id: 'web.storage', status: WmnPlatformCapabilityStatus.planned),
        WmnPlatformCapability(id: 'web.print', status: WmnPlatformCapabilityStatus.available),
        WmnPlatformCapability(id: 'web.clipboard', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.clipboard'),
        WmnPlatformCapability(id: 'web.camera', status: WmnPlatformCapabilityStatus.foundation, serviceId: 'wmn.native.camera', description: 'Browser camera capture uses the HTML media-capture hint where the browser supports it.'),
        WmnPlatformCapability(id: 'web.share', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.share'),
        WmnPlatformCapability(id: 'web.connectivity', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.connectivity'),
      ];
  @override
  Map<String, Object> get services => <String, Object>{
        'wmn.files.dialog': _fileDialogs,
        'wmn.native.share': _share,
        'wmn.native.browser': _browser,
        'wmn.native.clipboard': _clipboard,
        'wmn.native.connectivity': _connectivity,
        'wmn.native.device-info': _deviceInfo,
        'wmn.web.download': _download,
        'wmn.native.camera': _camera,
      };
  @override
  Future<void> initialize() async {}
  @override
  Future<void> refresh() async {}
  @override
  Map<String, Object?> diagnostics() => const <String, Object?>{
        'note': 'Web file selection, save/download, share, browser open, clipboard and connectivity are exposed through native WMN adapters.',
      };
}
