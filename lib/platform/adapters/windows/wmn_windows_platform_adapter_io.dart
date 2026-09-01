import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../files/adapters/wmn_file_selector_adapter.dart';
import '../native/wmn_flutter_native_services.dart';
import '../wmn_platform_adapter.dart';

class WmnWindowsPaths {
  const WmnWindowsPaths({
    required this.applicationSupport,
    required this.documents,
    required this.temporary,
    this.downloads,
  });

  final String applicationSupport;
  final String documents;
  final String temporary;
  final String? downloads;

  Map<String, Object?> toMap() => <String, Object?>{
        'application_support': applicationSupport,
        'documents': documents,
        'temporary': temporary,
        'downloads': downloads,
      };
}

class WmnWindowsSystemInfo {
  const WmnWindowsSystemInfo({
    required this.operatingSystem,
    required this.operatingSystemVersion,
    required this.localeName,
    required this.hostName,
    required this.processorCount,
  });

  final String operatingSystem;
  final String operatingSystemVersion;
  final String localeName;
  final String hostName;
  final int processorCount;

  Map<String, Object?> toMap() => <String, Object?>{
        'os': operatingSystem,
        'os_version': operatingSystemVersion,
        'locale': localeName,
        'host': hostName,
        'processors': processorCount,
      };
}

class WmnWindowsDiscoverySnapshot {
  const WmnWindowsDiscoverySnapshot({
    required this.printers,
    required this.serialPorts,
    required this.capturedAt,
  });

  final List<String> printers;
  final List<String> serialPorts;
  final DateTime capturedAt;

  Map<String, Object?> toMap() => <String, Object?>{
        'printers': printers,
        'serial_ports': serialPorts,
        'captured_at': capturedAt.toUtc().toIso8601String(),
      };
}

/// Safe Windows integration surface.
///
/// It deliberately does not expose arbitrary command execution. Applications
/// can ask WMN to reveal a path, open an external file/URL, inspect system
/// information and discover common device endpoints.
class WmnWindowsPlatformService {
  WmnWindowsPaths? _paths;
  WmnWindowsSystemInfo? _systemInfo;
  WmnWindowsDiscoverySnapshot? _discovery;

  WmnWindowsPaths? get cachedPaths => _paths;
  WmnWindowsSystemInfo? get cachedSystemInfo => _systemInfo;
  WmnWindowsDiscoverySnapshot? get cachedDiscovery => _discovery;

  Future<void> initialize() async {
    if (!Platform.isWindows) return;
    final support = await getApplicationSupportDirectory();
    final documents = await getApplicationDocumentsDirectory();
    final temporary = await getTemporaryDirectory();
    final downloads = await getDownloadsDirectory();
    _paths = WmnWindowsPaths(
      applicationSupport: support.path,
      documents: documents.path,
      temporary: temporary.path,
      downloads: downloads?.path,
    );
    _systemInfo = WmnWindowsSystemInfo(
      operatingSystem: Platform.operatingSystem,
      operatingSystemVersion: Platform.operatingSystemVersion,
      localeName: Platform.localeName,
      hostName: Platform.localHostname,
      processorCount: Platform.numberOfProcessors,
    );
  }

  Future<WmnWindowsDiscoverySnapshot> discoverDevices() async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows device discovery is available on Windows only.');
    }
    final printers = await _runPowerShellLines(
      'Get-CimInstance Win32_Printer | Select-Object -ExpandProperty Name',
    );
    final serialPorts = await _runPowerShellLines(
      r'Get-CimInstance Win32_SerialPort | ForEach-Object { "$($_.DeviceID)|$($_.Name)" }',
    );
    final snapshot = WmnWindowsDiscoverySnapshot(
      printers: printers,
      serialPorts: serialPorts,
      capturedAt: DateTime.now().toUtc(),
    );
    _discovery = snapshot;
    return snapshot;
  }

  Future<void> revealInExplorer(String path) async {
    if (!Platform.isWindows) throw UnsupportedError('Explorer integration is Windows-only.');
    final value = path.trim();
    if (value.isEmpty) throw StateError('A path is required.');
    await Process.start('explorer.exe', <String>['/select,', value], mode: ProcessStartMode.detached);
  }

  Future<void> openExternal(String target) async {
    if (!Platform.isWindows) throw UnsupportedError('External open is Windows-only.');
    final value = target.trim();
    if (value.isEmpty) throw StateError('A target is required.');
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) {
      const allowed = <String>{'http', 'https', 'mailto', 'tel'};
      if (!allowed.contains(uri.scheme.toLowerCase())) {
        throw StateError('Unsupported external URI scheme: ${uri.scheme}');
      }
      await Process.start(
        'rundll32.exe',
        <String>['url.dll,FileProtocolHandler', value],
        mode: ProcessStartMode.detached,
      );
      return;
    }
    final entity = FileSystemEntity.typeSync(value);
    if (entity == FileSystemEntityType.notFound) {
      throw StateError('External path does not exist: $value');
    }
    await Process.start('explorer.exe', <String>[value], mode: ProcessStartMode.detached);
  }

  Future<List<String>> _runPowerShellLines(String command) async {
    try {
      final result = await Process.run(
        'powershell.exe',
        <String>['-NoProfile', '-NonInteractive', '-Command', command],
        stdoutEncoding: systemEncoding,
        stderrEncoding: systemEncoding,
      );
      if (result.exitCode != 0) return const <String>[];
      return '${result.stdout}'
          .split(RegExp(r'[\r\n]+'))
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false)
        ..sort();
    } catch (_) {
      return const <String>[];
    }
  }
}

WmnPlatformAdapter createWindowsPlatformAdapter() => _WindowsPlatformAdapter();

class _WindowsPlatformAdapter implements WmnPlatformAdapter {
  final WmnWindowsPlatformService _service = WmnWindowsPlatformService();
  final WmnFileSelectorAdapter _fileDialogs = const WmnFileSelectorAdapter(
    runtimePlatform: WmnRuntimePlatform.windows,
  );
  final WmnNativeShareService _share = const WmnNativeShareService();
  final WmnNativeBrowserService _browser = const WmnNativeBrowserService();
  final WmnNativeClipboardService _clipboard = const WmnNativeClipboardService();
  final WmnNativeConnectivityService _connectivity = WmnNativeConnectivityService();
  final WmnNativeDeviceInfoService _deviceInfo = WmnNativeDeviceInfoService();

  @override
  String get id => 'windows';
  @override
  String get moduleId => 'windows';
  @override
  String get displayName => 'Windows';
  @override
  WmnPlatformAdapterStatus get status => WmnPlatformAdapterStatus.foundation;
  @override
  List<WmnRuntimePlatform> get supportedPlatforms => const <WmnRuntimePlatform>[WmnRuntimePlatform.windows];

  @override
  List<WmnPlatformCapability> get capabilities => const <WmnPlatformCapability>[
        WmnPlatformCapability(id: 'platform.windows', status: WmnPlatformCapabilityStatus.available),
        WmnPlatformCapability(id: 'filesystem', status: WmnPlatformCapabilityStatus.foundation, serviceId: 'wmn.platform.windows'),
        WmnPlatformCapability(id: 'windows.filesystem', status: WmnPlatformCapabilityStatus.foundation, serviceId: 'wmn.platform.windows'),
        WmnPlatformCapability(id: 'files.pick', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.files.dialog'),
        WmnPlatformCapability(id: 'files.pick-multiple', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.files.dialog'),
        WmnPlatformCapability(id: 'files.save', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.files.dialog'),
        WmnPlatformCapability(id: 'files.external-reference', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.files.dialog', description: 'Desktop files may remain at their original path instead of being copied into WMN Storage.'),
        WmnPlatformCapability(id: 'system-info', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.platform.windows'),
        WmnPlatformCapability(id: 'windows.system-info', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.platform.windows'),
        WmnPlatformCapability(id: 'shell', status: WmnPlatformCapabilityStatus.foundation, serviceId: 'wmn.platform.windows'),
        WmnPlatformCapability(id: 'windows.shell', status: WmnPlatformCapabilityStatus.foundation, serviceId: 'wmn.platform.windows'),
        WmnPlatformCapability(id: 'devices', status: WmnPlatformCapabilityStatus.foundation, serviceId: 'wmn.platform.windows'),
        WmnPlatformCapability(id: 'windows.device-discovery', status: WmnPlatformCapabilityStatus.foundation, serviceId: 'wmn.platform.windows'),
        WmnPlatformCapability(id: 'windows.printer-discovery', status: WmnPlatformCapabilityStatus.foundation, serviceId: 'wmn.platform.windows'),
        WmnPlatformCapability(id: 'windows.serial-discovery', status: WmnPlatformCapabilityStatus.foundation, serviceId: 'wmn.platform.windows'),
        WmnPlatformCapability(id: 'printing', status: WmnPlatformCapabilityStatus.available),
        WmnPlatformCapability(id: 'usb', status: WmnPlatformCapabilityStatus.foundation),
        WmnPlatformCapability(id: 'serial', status: WmnPlatformCapabilityStatus.available),
        WmnPlatformCapability(id: 'windows.usb', status: WmnPlatformCapabilityStatus.foundation),
        WmnPlatformCapability(id: 'windows.serial', status: WmnPlatformCapabilityStatus.available),
        WmnPlatformCapability(id: 'windows.bluetooth', status: WmnPlatformCapabilityStatus.foundation, description: 'Bluetooth serial is supported when Windows exposes a COM port; direct mobile GATT is a later adapter.'),
        WmnPlatformCapability(id: 'windows.network-devices', status: WmnPlatformCapabilityStatus.available),
        WmnPlatformCapability(id: 'windows.camera', status: WmnPlatformCapabilityStatus.planned),
        WmnPlatformCapability(id: 'windows.scanner', status: WmnPlatformCapabilityStatus.planned),
        WmnPlatformCapability(id: 'external-open', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.browser'),
        WmnPlatformCapability(id: 'share', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.share'),
        WmnPlatformCapability(id: 'windows.share', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.share'),
        WmnPlatformCapability(id: 'clipboard', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.clipboard'),
        WmnPlatformCapability(id: 'windows.clipboard', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.clipboard'),
        WmnPlatformCapability(id: 'connectivity', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.connectivity'),
        WmnPlatformCapability(id: 'windows.connectivity', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.connectivity'),
        WmnPlatformCapability(id: 'device-info', status: WmnPlatformCapabilityStatus.available, serviceId: 'wmn.native.device-info'),
      ];

  @override
  Map<String, Object> get services => <String, Object>{
        'wmn.platform.windows': _service,
        'wmn.files.dialog': _fileDialogs,
        'wmn.native.share': _share,
        'wmn.native.browser': _browser,
        'wmn.native.clipboard': _clipboard,
        'wmn.native.connectivity': _connectivity,
        'wmn.native.device-info': _deviceInfo,
      };

  @override
  Future<void> initialize() => _service.initialize();

  @override
  Future<void> refresh() async {
    if (Platform.isWindows) await _service.discoverDevices();
  }

  @override
  Map<String, Object?> diagnostics() => <String, Object?>{
        'platform': Platform.operatingSystem,
        'paths': _service.cachedPaths?.toMap(),
        'system': _service.cachedSystemInfo?.toMap(),
        'discovery': _service.cachedDiscovery?.toMap(),
      };
}
