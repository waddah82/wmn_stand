import 'dart:convert';

class WmnWorkspace {
  const WmnWorkspace({
    required this.name,
    required this.label,
    required this.module,
    this.appName,
    this.icon,
    this.parentPage,
    this.sequenceId = 0,
    this.isPublic = true,
    this.isHidden = false,
    this.content = const [],
    this.metadata = const {},
  });

  final String name;
  final String label;
  final String module;
  final String? appName;
  final String? icon;
  final String? parentPage;
  final double sequenceId;
  final bool isPublic;
  final bool isHidden;
  final List<Map<String, Object?>> content;
  final Map<String, Object?> metadata;
}

class WmnWorkspaceItem {
  const WmnWorkspaceItem({
    required this.id,
    required this.workspaceName,
    required this.region,
    required this.itemType,
    this.label,
    this.linkType,
    this.linkTo,
    this.icon,
    this.parentLabel,
    this.index = 0,
    this.columnSpan = 4,
    this.hidden = false,
    this.data = const {},
  });

  final String id;
  final String workspaceName;
  final String region;
  final String itemType;
  final String? label;
  final String? linkType;
  final String? linkTo;
  final String? icon;
  final String? parentLabel;
  final int index;
  final int columnSpan;
  final bool hidden;
  final Map<String, Object?> data;
}

class WmnWorkspaceBundle {
  const WmnWorkspaceBundle({required this.workspace, required this.items});
  final WmnWorkspace workspace;
  final List<WmnWorkspaceItem> items;

  List<WmnWorkspaceItem> region(String region) =>
      items.where((entry) => entry.region == region && !entry.hidden).toList(growable: false);
}

Map<String, Object?> wmnMap(Object? value) {
  if (value is! Map) return <String, Object?>{};
  return <String, Object?>{
    for (final entry in value.entries) '${entry.key}': wmnNormalizeJson(entry.value),
  };
}

Object? wmnNormalizeJson(Object? value) {
  if (value is Map) return wmnMap(value);
  if (value is List) return value.map(wmnNormalizeJson).toList(growable: false);
  return value;
}

List<Map<String, Object?>> wmnDecodeList(String? value) {
  if (value == null || value.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(value);
    if (decoded is! List) return const [];
    return decoded.whereType<Map>().map(wmnMap).toList(growable: false);
  } catch (_) {
    return const [];
  }
}
