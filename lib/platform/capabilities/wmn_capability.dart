enum WmnCapabilityStatus {
  available,
  disabled,
  planned,
  deferred,
  unavailable,
}

/// Runtime view of one stable WMN capability contract.
class WmnCapabilityDescriptor {
  const WmnCapabilityDescriptor({
    required this.id,
    required this.contractVersion,
    required this.providerModuleIds,
    required this.providerVersions,
    required this.status,
    required this.enabledProviderModuleIds,
    required this.requiredCapabilities,
    required this.supportedPlatforms,
    required this.requiredByPlatform,
  });

  final String id;
  final String contractVersion;
  final List<String> providerModuleIds;
  final Map<String, String> providerVersions;
  final WmnCapabilityStatus status;
  final List<String> enabledProviderModuleIds;
  final List<String> requiredCapabilities;
  final List<String> supportedPlatforms;
  final bool requiredByPlatform;

  bool get isAvailable => status == WmnCapabilityStatus.available;
  bool get canDisable => !requiredByPlatform;
}

class WmnCapabilityProfile {
  const WmnCapabilityProfile({
    required this.id,
    required this.requiredCapabilities,
    this.optionalCapabilities = const <String>[],
  });

  final String id;
  final List<String> requiredCapabilities;
  final List<String> optionalCapabilities;
}
