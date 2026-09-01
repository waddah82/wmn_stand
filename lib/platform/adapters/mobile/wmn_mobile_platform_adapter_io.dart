import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../files/adapters/wmn_native_file_dialog_adapter.dart';
import '../native/wmn_flutter_native_services.dart';
import '../native/wmn_mobile_barcode_scanner.dart';
import '../wmn_platform_adapter.dart';

class WmnMobileFoundationService {
  Map<String, Object?> _diagnostics = const <String, Object?>{};

  Map<String, Object?> get diagnostics => Map<String, Object?>.unmodifiable(_diagnostics);

  Future<void> initialize() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final support = await getApplicationSupportDirectory();
    final documents = await getApplicationDocumentsDirectory();
    final temporary = await getTemporaryDirectory();
    _diagnostics = <String, Object?>{
      'os': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      'locale': Platform.localeName,
      'processors': Platform.numberOfProcessors,
      'application_support': support.path,
      'documents': documents.path,
      'temporary': temporary.path,
    };
  }
}

WmnPlatformAdapter createMobilePlatformAdapter() => _MobilePlatformAdapter();

class _MobilePlatformAdapter implements WmnPlatformAdapter {
  final WmnMobileFoundationService _service = WmnMobileFoundationService();
  late final WmnNativeFileDialogAdapter _fileDialogs = WmnNativeFileDialogAdapter(
    runtimePlatform: Platform.isIOS ? WmnRuntimePlatform.ios : WmnRuntimePlatform.android,
  );
  final WmnNativeShareService _share = const WmnNativeShareService();
  final WmnNativeBrowserService _browser = const WmnNativeBrowserService();
  final WmnNativeClipboardService _clipboard = const WmnNativeClipboardService();
  final WmnNativeConnectivityService _connectivity = WmnNativeConnectivityService();
  final WmnNativeDeviceInfoService _deviceInfo = WmnNativeDeviceInfoService();
  final WmnNativeCameraService _camera = WmnNativeCameraService();
  final WmnMobileBarcodeScanner _scanner = const WmnMobileBarcodeScanner();

  @override
  String get id => 'mobile';
  @override
  String get moduleId => 'mobile';
  @override
  String get displayName => 'Mobile';
  @override
  WmnPlatformAdapterStatus get status => WmnPlatformAdapterStatus.foundation;
  @override
  List<WmnRuntimePlatform> get supportedPlatforms => const <WmnRuntimePlatform>[
        WmnRuntimePlatform.android,
        WmnRuntimePlatform.ios,
      ];

  @override
  List<WmnPlatformCapability> get capabilities => const <WmnPlatformCapability>[
        WmnPlatformCapability(id: 'platform.mobile', status: WmnPlatformCapabilityStatus.foundation, serviceId: 'wmn.platform.mobile'),
        WmnPlatformCapability(id: 'mobile.device-info', status: WmnPlatformCapabilityStatus.foundation, serviceId: 'wmn.platform.mobile'),
        WmnPlatformCapability(id: 'mobile.filesystem', status: WmnPlatformCapabilityStatus.foundation, serviceId: 'wmn.platform.mobile'),
        WmnPlatformCapability(id: 'files.pick', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.files.dialog'),
        WmnPlatformCapability(id: 'files.pick-multiple', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.files.dialog'),
        WmnPlatformCapability(id: 'files.save', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.files.dialog', description: 'Android/iOS native save/export is provided through the WMN native file adapter.'),
        WmnPlatformCapability(id: 'files.external-reference', status: WmnPlatformCapabilityStatus.unavailable, serviceId: 'wmn.files.dialog', description: 'Persistent external references require the later Mobile scoped-storage adapter; selected files use Managed Storage for now.'),
        WmnPlatformCapability(id: 'external-open', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.browser'),
        WmnPlatformCapability(id: 'browser', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.browser'),
        WmnPlatformCapability(id: 'clipboard', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.clipboard'),
        WmnPlatformCapability(id: 'connectivity', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.connectivity'),
        WmnPlatformCapability(id: 'device-info', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.device-info'),
        WmnPlatformCapability(id: 'permissions', status: WmnPlatformCapabilityStatus.planned),
        WmnPlatformCapability(id: 'contacts', status: WmnPlatformCapabilityStatus.planned),
        WmnPlatformCapability(id: 'sms', status: WmnPlatformCapabilityStatus.planned),
        WmnPlatformCapability(id: 'share', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.share'),
        WmnPlatformCapability(id: 'camera', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.camera'),
        WmnPlatformCapability(id: 'scanner', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.scanner'),
        WmnPlatformCapability(id: 'mobile.permissions', status: WmnPlatformCapabilityStatus.planned),
        WmnPlatformCapability(id: 'mobile.contacts', status: WmnPlatformCapabilityStatus.planned),
        WmnPlatformCapability(id: 'mobile.sms.read', status: WmnPlatformCapabilityStatus.planned),
        WmnPlatformCapability(id: 'mobile.sms.send', status: WmnPlatformCapabilityStatus.planned),
        WmnPlatformCapability(id: 'mobile.share', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.share'),
        WmnPlatformCapability(id: 'mobile.whatsapp.share', status: WmnPlatformCapabilityStatus.planned),
        WmnPlatformCapability(id: 'mobile.camera', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.camera'),
        WmnPlatformCapability(id: 'mobile.scanner', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.scanner'),
        WmnPlatformCapability(id: 'mobile.secure-storage', status: WmnPlatformCapabilityStatus.planned),
        WmnPlatformCapability(id: 'mobile.bluetooth-gatt', status: WmnPlatformCapabilityStatus.planned, description: 'Direct BLE GATT remains isolated until a protocol-neutral transport adapter and host permission manifest are generated.'),
        WmnPlatformCapability(id: 'mobile.connectivity', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.connectivity'),
      ];

  @override
  Map<String, Object> get services => <String, Object>{
        'wmn.platform.mobile': _service,
        'wmn.files.dialog': _fileDialogs,
        'wmn.native.share': _share,
        'wmn.native.browser': _browser,
        'wmn.native.clipboard': _clipboard,
        'wmn.native.connectivity': _connectivity,
        'wmn.native.device-info': _deviceInfo,
        'wmn.native.camera': _camera,
        'wmn.native.scanner': _scanner,
      };

  @override
  Future<void> initialize() => _service.initialize();
  @override
  Future<void> refresh() => _service.initialize();
  @override
  Map<String, Object?> diagnostics() => _service.diagnostics;
}
