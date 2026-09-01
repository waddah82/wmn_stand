import 'package:flutter/material.dart';

enum WmnSystemModuleGroup {
  foundation,
  experience,
  services,
  platform,
  developer,
}

enum WmnSystemModuleStatus {
  ready,
  foundation,
  planned,
  deferred,
}

/// Immutable definition of a WMN System Core module.
///
/// Module definitions are platform contracts, not application modules. The
/// registry owns enable/disable state and dependency resolution while this
/// definition owns identity, contract version and lifecycle status.
class WmnSystemModuleDefinition {
  const WmnSystemModuleDefinition({
    required this.id,
    required this.labelKey,
    required this.descriptionKey,
    required this.icon,
    required this.group,
    required this.status,
    required this.capabilities,
    this.version = '1.0.0',
    this.required = false,
    this.defaultEnabled = true,
  });

  final String id;
  final String labelKey;
  final String descriptionKey;
  final IconData icon;
  final WmnSystemModuleGroup group;
  final WmnSystemModuleStatus status;
  final List<String> capabilities;
  final String version;
  final bool required;
  final bool defaultEnabled;

  bool get executable =>
      status == WmnSystemModuleStatus.ready ||
      status == WmnSystemModuleStatus.foundation;
}
