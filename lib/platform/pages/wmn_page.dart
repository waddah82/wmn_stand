import 'dart:convert';

enum WmnPageType {
  standard,
  dashboard,
  custom,
  list,
  form,
  report,
  workspace;

  static WmnPageType parse(String value) {
    final normalized = value.trim().toUpperCase();
    return switch (normalized) {
      'DASHBOARD' => WmnPageType.dashboard,
      'CUSTOM' => WmnPageType.custom,
      'LIST' => WmnPageType.list,
      'FORM' => WmnPageType.form,
      'REPORT' => WmnPageType.report,
      'WORKSPACE' => WmnPageType.workspace,
      _ => WmnPageType.standard,
    };
  }

  String get storageValue => name.toUpperCase();
}

class WmnPageDefinition {
  const WmnPageDefinition({
    required this.name,
    required this.title,
    required this.route,
    this.module = 'WMN System',
    this.pageType = WmnPageType.standard,
    this.roles = const <String>[],
    this.permissions = const <String>[],
    this.enabled = true,
    this.metadata = const <String, Object?>{},
    this.appName,
    this.controllerKey,
  });

  final String name;
  final String title;
  final String route;
  final String? appName;
  final String module;
  final WmnPageType pageType;
  final String? controllerKey;
  final List<String> roles;
  final List<String> permissions;
  final bool enabled;
  final Map<String, Object?> metadata;

  String? get featureCode => _nullable(metadata['feature_code']);

  String? get target => _nullable(
        metadata['target'] ??
            metadata['link_to'] ??
            metadata['doctype'] ??
            metadata['report'] ??
            metadata['workspace'],
      );

  String? get documentName => _nullable(metadata['document_name']);

  String? get icon => _nullable(metadata['icon']);

  String? get section => _nullable(metadata['section']);

  double get order =>
      (metadata['order'] as num?)?.toDouble() ??
      double.tryParse('${metadata['order'] ?? ''}') ??
      0;

  bool get showInNavigation =>
      _bool(metadata['show_in_navigation'], fallback: false);

  List<Map<String, Object?>> get layoutBlocks {
    final raw = metadata['layout'];
    if (raw is! List) return const <Map<String, Object?>>[];
    return raw
        .whereType<Map>()
        .map(
          (entry) => <String, Object?>{
            for (final item in entry.entries) '${item.key}': item.value,
          },
        )
        .toList(growable: false);
  }

  Map<String, Object?> toStorageJson() => <String, Object?>{
        'name': name,
        'title': title,
        'route': route,
        if (appName != null) 'app_name': appName,
        'module': module,
        'page_type': pageType.storageValue,
        if (controllerKey != null) 'controller_key': controllerKey,
        'roles': roles,
        'permissions': permissions,
        'enabled': enabled,
        'metadata': metadata,
      };

  factory WmnPageDefinition.fromDatabaseRow(Map<String, Object?> row) {
    return WmnPageDefinition(
      name: '${row['name'] ?? ''}'.trim(),
      title: '${row['title'] ?? row['name'] ?? ''}'.trim(),
      route: '${row['route'] ?? ''}'.trim(),
      appName: _nullable(row['app_name']),
      module: '${row['module'] ?? 'WMN System'}'.trim(),
      pageType: WmnPageType.parse('${row['page_type'] ?? 'STANDARD'}'),
      controllerKey: _nullable(row['controller_key']),
      roles: _stringList(row['roles_json']),
      permissions: _stringList(row['permissions_json']),
      enabled: _bool(row['enabled'], fallback: true),
      metadata: _jsonMap(row['metadata_json']),
    );
  }

  static String? _nullable(Object? value) {
    final normalized = '${value ?? ''}'.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static bool _bool(Object? value, {required bool fallback}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = '$value'.trim().toLowerCase();
    if (const <String>{'1', 'true', 'yes', 'on'}.contains(normalized)) {
      return true;
    }
    if (const <String>{'0', 'false', 'no', 'off'}.contains(normalized)) {
      return false;
    }
    return fallback;
  }

  static List<String> _stringList(Object? value) {
    Object? decoded = value;
    if (value is String) {
      try {
        decoded = jsonDecode(value);
      } catch (_) {
        return const <String>[];
      }
    }
    if (decoded is! List) return const <String>[];
    return <String>{
      for (final entry in decoded)
        if ('$entry'.trim().isNotEmpty) '$entry'.trim(),
    }.toList(growable: false);
  }

  static Map<String, Object?> _jsonMap(Object? value) {
    Object? decoded = value;
    if (value is String) {
      try {
        decoded = jsonDecode(value);
      } catch (_) {
        return const <String, Object?>{};
      }
    }
    if (decoded is! Map) return const <String, Object?>{};
    return <String, Object?>{
      for (final entry in decoded.entries) '${entry.key}': entry.value,
    };
  }
}
