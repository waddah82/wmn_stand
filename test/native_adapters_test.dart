import 'package:flutter_test/flutter_test.dart';
import 'package:wmn_standalone/platform/adapters/contracts/wmn_platform_contracts.dart';
import 'package:wmn_standalone/platform/adapters/mobile/wmn_mobile_platform_adapter.dart';
import 'package:wmn_standalone/platform/adapters/web/wmn_web_platform_adapter.dart';
import 'package:wmn_standalone/platform/adapters/windows/wmn_windows_platform_adapter.dart';
import 'package:wmn_standalone/platform/adapters/wmn_platform_adapter.dart';
import 'package:wmn_standalone/platform/adapters/wmn_platform_adapter_registry.dart';
import 'package:wmn_standalone/platform/files/adapters/wmn_native_file_dialog_adapter.dart';
import 'package:wmn_standalone/platform/files/wmn_file_adapter.dart';

void main() {
  test('Windows native adapter exposes only executable registered services', () {
    final adapter = createWindowsPlatformAdapter();
    final capabilities = _capabilities(adapter);

    expect(capabilities['external-open']?.status, WmnPlatformCapabilityStatus.available);
    expect(capabilities['share']?.status, WmnPlatformCapabilityStatus.available);
    expect(capabilities['clipboard']?.status, WmnPlatformCapabilityStatus.available);
    expect(capabilities['connectivity']?.status, WmnPlatformCapabilityStatus.available);
    expect(capabilities['device-info']?.status, WmnPlatformCapabilityStatus.available);
    expect(capabilities['windows.camera']?.status, WmnPlatformCapabilityStatus.planned);
    expect(capabilities['windows.scanner']?.status, WmnPlatformCapabilityStatus.planned);

    expect(adapter.services['wmn.native.share'], isA<WmnShareAdapter>());
    expect(adapter.services['wmn.native.browser'], isA<WmnExternalOpenAdapter>());
    expect(adapter.services['wmn.native.clipboard'], isA<WmnClipboardAdapter>());
    expect(adapter.services['wmn.native.connectivity'], isA<WmnConnectivityAdapter>());
    expect(adapter.services['wmn.native.device-info'], isA<WmnDeviceInfoAdapter>());
  });

  test('Mobile native adapter exposes save, share, camera and scanning without claiming external references', () {
    final adapter = createMobilePlatformAdapter();
    final capabilities = _capabilities(adapter);

    expect(capabilities['files.save']?.status, WmnPlatformCapabilityStatus.available);
    expect(capabilities['files.external-reference']?.status, WmnPlatformCapabilityStatus.unavailable);
    expect(capabilities['share']?.status, WmnPlatformCapabilityStatus.available);
    expect(capabilities['camera']?.status, WmnPlatformCapabilityStatus.available);
    expect(capabilities['scanner']?.status, WmnPlatformCapabilityStatus.available);
    expect(capabilities['connectivity']?.status, WmnPlatformCapabilityStatus.available);
    expect(capabilities['mobile.bluetooth-gatt']?.status, WmnPlatformCapabilityStatus.planned);

    final fileDialogs = adapter.services['wmn.files.dialog'];
    expect(fileDialogs, isA<WmnFileDialogAdapter>());
    expect(fileDialogs, isA<WmnFileReferenceAdapter>());
    expect((fileDialogs! as WmnFileReferenceAdapter).supportsExternalReferences, isFalse);
    expect(adapter.services['wmn.native.share'], isA<WmnShareAdapter>());
    expect(adapter.services['wmn.native.camera'], isA<WmnCameraAdapter>());
    expect(adapter.services['wmn.native.scanner'], isA<WmnScannerAdapter>());
  });

  test('Web adapter exposes browser download/share services and keeps persistent references unavailable', () {
    final adapter = WmnWebPlatformAdapter();
    final capabilities = _capabilities(adapter);

    expect(capabilities['browser']?.status, WmnPlatformCapabilityStatus.available);
    expect(capabilities['download']?.status, WmnPlatformCapabilityStatus.available);
    expect(capabilities['files.save']?.status, WmnPlatformCapabilityStatus.available);
    expect(capabilities['files.external-reference']?.status, WmnPlatformCapabilityStatus.unavailable);
    expect(capabilities['web.share']?.status, WmnPlatformCapabilityStatus.available);
    expect(capabilities['web.clipboard']?.status, WmnPlatformCapabilityStatus.available);
    expect(capabilities['web.connectivity']?.status, WmnPlatformCapabilityStatus.available);
    expect(capabilities['web.camera']?.status, WmnPlatformCapabilityStatus.foundation);

    expect(adapter.services['wmn.web.download'], isA<WmnWebDownloadAdapter>());
    expect(adapter.services['wmn.native.browser'], isA<WmnExternalOpenAdapter>());
    expect(adapter.services['wmn.native.share'], isA<WmnShareAdapter>());
    expect(adapter.services['wmn.native.clipboard'], isA<WmnClipboardAdapter>());
    expect(adapter.services['wmn.native.connectivity'], isA<WmnConnectivityAdapter>());
  });

  test('Native file dialog adds save/export without silently adding external-reference semantics', () {
    final mobile = WmnNativeFileDialogAdapter(runtimePlatform: WmnRuntimePlatform.android);
    final web = WmnNativeFileDialogAdapter(runtimePlatform: WmnRuntimePlatform.web);

    expect(mobile.supportsSaveLocation, isTrue);
    expect(mobile.supportsExternalReferences, isFalse);
    expect(web.supportsSaveLocation, isTrue);
    expect(web.supportsExternalReferences, isFalse);
  });

  test('Platform registry resolves native contracts through capability and service boundaries', () {
    final web = WmnWebPlatformAdapter();
    final registry = WmnPlatformAdapterRegistry(
      runtimePlatform: WmnRuntimePlatform.web,
      adapters: <WmnPlatformAdapter>[web],
    );
    addTearDown(registry.dispose);

    expect(registry.isAvailable('share'), isTrue);
    expect(registry.isAvailable('files.save'), isTrue);
    expect(registry.isAvailable('files.external-reference'), isFalse);
    expect(registry.resolveService<WmnShareAdapter>('wmn.native.share'), same(web.services['wmn.native.share']));
    expect(registry.resolveService<WmnWebDownloadAdapter>('wmn.web.download'), same(web.services['wmn.web.download']));
  });
}

Map<String, WmnPlatformCapability> _capabilities(WmnPlatformAdapter adapter) => <String, WmnPlatformCapability>{
      for (final capability in adapter.capabilities) capability.id: capability,
    };
