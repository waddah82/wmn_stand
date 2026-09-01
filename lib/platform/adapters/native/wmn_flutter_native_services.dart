import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../contracts/wmn_platform_contracts.dart';

/// Cross-platform native services used only behind WMN adapter contracts.
///
/// Applications and platform-neutral engines must not import plugin packages
/// directly. They resolve these contracts from [WmnPlatformAdapterRegistry].
class WmnNativeShareService implements WmnShareAdapter {
  const WmnNativeShareService();

  @override
  Future<void> shareText(String text, {String? subject}) async {
    final value = text.trim();
    if (value.isEmpty) throw StateError('Share text cannot be empty.');
    await SharePlus.instance.share(
      ShareParams(text: value, subject: _nullable(subject)),
    );
  }

  @override
  Future<void> shareFile(
    String path, {
    String? text,
    String? mimeType,
  }) async {
    final value = path.trim();
    if (value.isEmpty) throw StateError('A file path is required for sharing.');
    await SharePlus.instance.share(
      ShareParams(
        text: _nullable(text),
        files: <XFile>[XFile(value, mimeType: _nullable(mimeType))],
      ),
    );
  }

  @override
  Future<void> shareBytes({
    required String fileName,
    required Uint8List bytes,
    String? text,
    String? mimeType,
  }) async {
    final name = fileName.trim();
    if (name.isEmpty) throw StateError('A file name is required for sharing.');
    if (bytes.isEmpty) throw StateError('Cannot share an empty file payload.');
    await SharePlus.instance.share(
      ShareParams(
        text: _nullable(text),
        files: <XFile>[
          XFile.fromData(bytes, mimeType: _nullable(mimeType)),
        ],
        fileNameOverrides: <String>[name],
      ),
    );
  }
}

class WmnNativeBrowserService implements WmnExternalOpenAdapter, WmnWebBrowserAdapter {
  const WmnNativeBrowserService();

  static const Set<String> _allowedSchemes = <String>{
    'http',
    'https',
    'mailto',
    'tel',
    'sms',
  };

  @override
  Future<void> open(String url) async {
    final value = url.trim();
    if (value.isEmpty) throw StateError('A URL is required.');
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) {
      throw StateError('A fully qualified URL is required.');
    }
    if (!_allowedSchemes.contains(uri.scheme.toLowerCase())) {
      throw UnsupportedError('Unsupported external URI scheme: ${uri.scheme}');
    }
    final opened = await launchUrl(uri);
    if (!opened) throw StateError('The platform could not open $value.');
  }
}

class WmnNativeClipboardService implements WmnClipboardAdapter {
  const WmnNativeClipboardService();

  @override
  Future<void> writeText(String text) => Clipboard.setData(ClipboardData(text: text));

  @override
  Future<String?> readText() async {
    final value = await Clipboard.getData(Clipboard.kTextPlain);
    return value?.text;
  }
}

class WmnNativeConnectivityService implements WmnConnectivityAdapter {
  WmnNativeConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<WmnConnectivitySnapshot> snapshot() async {
    final result = await _connectivity.checkConnectivity();
    final interfaces = result.map((item) => item.name).toSet().toList()..sort();
    final hasInterface = result.any((item) => item != ConnectivityResult.none);
    return WmnConnectivitySnapshot(
      interfaces: List<String>.unmodifiable(interfaces),
      hasNetworkInterface: hasInterface,
    );
  }
}

class WmnNativeDeviceInfoService implements WmnDeviceInfoAdapter {
  WmnNativeDeviceInfoService({DeviceInfoPlugin? plugin})
      : _plugin = plugin ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _plugin;

  @override
  Future<Map<String, Object?>> snapshot() async {
    final info = await _plugin.deviceInfo;
    return Map<String, Object?>.unmodifiable(
      info.data.map((key, value) => MapEntry<String, Object?>(key, _safe(value))),
    );
  }

  Object? _safe(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Iterable) return value.map(_safe).toList(growable: false);
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries) '${entry.key}': _safe(entry.value),
      };
    }
    return value.toString();
  }
}

class WmnNativeCameraService implements WmnCameraAdapter {
  WmnNativeCameraService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<String?> captureImage() async {
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 92,
    );
    if (image == null) return null;
    final path = image.path.trim();
    return path.isEmpty ? null : path;
  }
}

class WmnNativeDownloadService implements WmnWebDownloadAdapter {
  const WmnNativeDownloadService();

  @override
  Future<void> download({
    required String fileName,
    required List<int> bytes,
    String? mimeType,
  }) async {
    final payload = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    if (payload.isEmpty) throw StateError('Cannot export an empty file payload.');
    final parts = _splitName(fileName);
    final result = await FileSaver.instance.saveAs(
      name: parts.$1,
      bytes: payload,
      fileExtension: parts.$2,
      includeExtension: parts.$2.isNotEmpty,
      mimeType: _nullable(mimeType) == null ? MimeType.other : MimeType.custom,
      customMimeType: _nullable(mimeType),
    );
    if (result == null) throw StateError('The file export was canceled.');
  }
}

(String, String) _splitName(String fileName) {
  final value = fileName.trim();
  if (value.isEmpty) throw StateError('A file name is required.');
  final dot = value.lastIndexOf('.');
  if (dot <= 0 || dot == value.length - 1) return (value, '');
  return (value.substring(0, dot), value.substring(dot + 1));
}

String? _nullable(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
