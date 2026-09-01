import 'package:flutter/foundation.dart';

/// Runtime host detected by the WMN platform layer.
///
/// This is intentionally separate from business applications. Applications
/// request capabilities; they do not branch on the operating system directly.
enum WmnRuntimePlatform {
  windows,
  android,
  ios,
  web,
  linux,
  macos,
  server,
  unknown,
}

enum WmnPlatformAdapterStatus {
  ready,
  foundation,
  planned,
  unavailable,
}

enum WmnPlatformCapabilityStatus {
  available,
  foundation,
  planned,
  unavailable,
}

class WmnPlatformCapability {
  const WmnPlatformCapability({
    required this.id,
    required this.status,
    this.description = '',
    this.serviceId,
  });

  final String id;
  final WmnPlatformCapabilityStatus status;
  final String description;
  final String? serviceId;

  bool get isAvailable =>
      status == WmnPlatformCapabilityStatus.available ||
      status == WmnPlatformCapabilityStatus.foundation;
}

abstract interface class WmnPlatformAdapter {
  String get id;
  String get moduleId;
  String get displayName;
  WmnPlatformAdapterStatus get status;
  List<WmnRuntimePlatform> get supportedPlatforms;
  List<WmnPlatformCapability> get capabilities;
  Map<String, Object> get services;

  Future<void> initialize();

  /// Refreshes runtime diagnostics. Expensive discovery belongs here rather
  /// than in application startup.
  Future<void> refresh();

  Map<String, Object?> diagnostics();
}

extension WmnPlatformAdapterRuntime on WmnPlatformAdapter {
  bool supports(WmnRuntimePlatform platform) => supportedPlatforms.contains(platform);
}

WmnRuntimePlatform detectWmnRuntimePlatform() {
  if (kIsWeb) return WmnRuntimePlatform.web;
  return switch (defaultTargetPlatform) {
    TargetPlatform.windows => WmnRuntimePlatform.windows,
    TargetPlatform.android => WmnRuntimePlatform.android,
    TargetPlatform.iOS => WmnRuntimePlatform.ios,
    TargetPlatform.linux => WmnRuntimePlatform.linux,
    TargetPlatform.macOS => WmnRuntimePlatform.macos,
    TargetPlatform.fuchsia => WmnRuntimePlatform.unknown,
  };
}

String wmnRuntimePlatformName(WmnRuntimePlatform platform) => switch (platform) {
      WmnRuntimePlatform.windows => 'Windows',
      WmnRuntimePlatform.android => 'Android',
      WmnRuntimePlatform.ios => 'iOS',
      WmnRuntimePlatform.web => 'Web',
      WmnRuntimePlatform.linux => 'Linux',
      WmnRuntimePlatform.macos => 'macOS',
      WmnRuntimePlatform.server => 'Server',
      WmnRuntimePlatform.unknown => 'Unknown',
    };
