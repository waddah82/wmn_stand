/// Defines the platform contracts used by WMN System Platform adapters.
///
/// These contracts isolate platform-specific implementations from the
/// platform core and provide stable interfaces for capabilities that require
/// operating-system or runtime integration.
library;

import 'dart:typed_data';

abstract interface class WmnPermissionAdapter {
  Future<bool> isGranted(String permission);
  Future<bool> request(String permission);
}

class WmnContactRecord {
  const WmnContactRecord({
    required this.id,
    required this.displayName,
    this.phones = const <String>[],
    this.emails = const <String>[],
  });

  final String id;
  final String displayName;
  final List<String> phones;
  final List<String> emails;
}

abstract interface class WmnContactsAdapter {
  Future<List<WmnContactRecord>> list({String? query, int limit = 200});
}

class WmnSmsMessage {
  const WmnSmsMessage({
    required this.id,
    required this.address,
    required this.body,
    required this.receivedAt,
  });

  final String id;
  final String address;
  final String body;
  final DateTime receivedAt;
}

abstract interface class WmnSmsAdapter {
  Future<List<WmnSmsMessage>> read({DateTime? since, int limit = 200});
  Future<void> send({required String to, required String message});
}

abstract interface class WmnShareAdapter {
  Future<void> shareText(String text, {String? subject});
  Future<void> shareFile(String path, {String? text, String? mimeType});
  Future<void> shareBytes({
    required String fileName,
    required Uint8List bytes,
    String? text,
    String? mimeType,
  });
}

abstract interface class WmnClipboardAdapter {
  Future<void> writeText(String text);
  Future<String?> readText();
}

class WmnConnectivitySnapshot {
  const WmnConnectivitySnapshot({
    required this.interfaces,
    required this.hasNetworkInterface,
  });

  final List<String> interfaces;
  final bool hasNetworkInterface;

  Map<String, Object?> toMap() => <String, Object?>{
        'interfaces': interfaces,
        'has_network_interface': hasNetworkInterface,
      };
}

abstract interface class WmnConnectivityAdapter {
  Future<WmnConnectivitySnapshot> snapshot();
}

abstract interface class WmnDeviceInfoAdapter {
  Future<Map<String, Object?>> snapshot();
}

abstract interface class WmnCameraAdapter {
  Future<String?> captureImage();
}

abstract interface class WmnScannerAdapter {
  Future<String?> scanBarcode();
}

abstract interface class WmnExternalOpenAdapter {
  Future<void> open(String target);
}

/// Backward-compatible Web browser contract. New platform-neutral consumers
/// should resolve [WmnExternalOpenAdapter].
abstract interface class WmnWebBrowserAdapter implements WmnExternalOpenAdapter {}

abstract interface class WmnWebDownloadAdapter {
  Future<void> download({
    required String fileName,
    required List<int> bytes,
    String? mimeType,
  });
}

abstract interface class WmnTokenHost {
  Future<String> issueToken({required String subject, Duration? ttl});
  Future<bool> validateToken(String token);
  Future<void> revokeToken(String token);
}

abstract interface class WmnApiHost {
  Future<void> start();
  Future<void> stop();
  bool get running;
}

abstract interface class WmnServerDataBackend {
  String get backendId;
  Future<void> open();
  Future<void> close();
}
