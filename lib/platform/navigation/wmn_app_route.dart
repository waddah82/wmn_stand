/// Declarative application route that WMN can resolve without application-
/// specific Flutter wiring.
enum WmnAppRouteTargetType {
  workspace,
  doctype,
  report,
  page,
  unsupported;

  static WmnAppRouteTargetType parse(String value) {
    final normalized = value.trim().toLowerCase().replaceAll('-', '_');
    return switch (normalized) {
      'workspace' => WmnAppRouteTargetType.workspace,
      'doctype' || 'doc_type' => WmnAppRouteTargetType.doctype,
      'report' || 'query_report' => WmnAppRouteTargetType.report,
      'page' => WmnAppRouteTargetType.page,
      _ => WmnAppRouteTargetType.unsupported,
    };
  }
}

class WmnAppRouteDefinition {
  const WmnAppRouteDefinition({
    required this.path,
    required this.title,
    required this.targetType,
    required this.target,
    this.icon,
    this.section,
    this.order = 0,
    this.showInNavigation = true,
    this.requiredRoles = const <String>[],
    this.requiredPermissions = const <String>[],
  });

  final String path;
  final String title;
  final WmnAppRouteTargetType targetType;
  final String target;
  final String? icon;
  final String? section;
  final double order;
  final bool showInNavigation;
  final List<String> requiredRoles;

  /// Permission tokens use either `doctype:<DocType>:<action>` or
  /// `permission:<code>`. Unknown token formats fail closed during manifest
  /// validation.
  final List<String> requiredPermissions;

  Map<String, Object?> toJson() => <String, Object?>{
        'path': path,
        'title': title,
        'target_type': targetType.name,
        'target': target,
        if (icon != null) 'icon': icon,
        if (section != null) 'section': section,
        'order': order,
        'show_in_navigation': showInNavigation,
        'required_roles': requiredRoles,
        'required_permissions': requiredPermissions,
      };

  List<String> validate() {
    final issues = <String>[];
    final normalizedPath = path.trim();
    if (!_validPath(normalizedPath)) {
      issues.add('Application route path is invalid: $path');
    }
    if (title.trim().isEmpty) {
      issues.add('Application route title is required for $path.');
    }
    if (targetType == WmnAppRouteTargetType.unsupported) {
      issues.add('Application route target type is unsupported for $path.');
    }
    if (target.trim().isEmpty) {
      issues.add('Application route target is required for $path.');
    }
    final invalidPermissions = requiredPermissions
        .where((token) => !isSupportedPermissionToken(token))
        .toSet()
        .toList()
      ..sort();
    if (invalidPermissions.isNotEmpty) {
      issues.add(
        'Unsupported route permission tokens for $path: '
        '${invalidPermissions.join(', ')}',
      );
    }
    return issues;
  }

  factory WmnAppRouteDefinition.fromJson(Map<String, Object?> value) {
    final parsedTarget = WmnAppRouteTargetType.parse(
      '${value['target_type'] ?? ''}',
    );
    return WmnAppRouteDefinition(
      path: '${value['path'] ?? ''}'.trim(),
      title: '${value['title'] ?? value['label'] ?? ''}'.trim(),
      targetType: parsedTarget,
      target: '${value['target'] ?? value['link_to'] ?? ''}'.trim(),
      icon: _nullable(value['icon']),
      section: _nullable(value['section']),
      order: (value['order'] as num?)?.toDouble() ??
          double.tryParse('${value['order'] ?? ''}') ??
          0,
      showInNavigation: _bool(value['show_in_navigation'], fallback: true),
      requiredRoles: _strings(value['required_roles']),
      requiredPermissions: _strings(value['required_permissions']),
    );
  }

  static bool isSupportedPermissionToken(String token) {
    final parts = token.trim().split(':');
    if (parts.length == 2 &&
        parts.first.toLowerCase() == 'permission' &&
        parts[1].trim().isNotEmpty) {
      return true;
    }
    if (parts.length != 3 || parts.first.toLowerCase() != 'doctype') {
      return false;
    }
    if (parts[1].trim().isEmpty) return false;
    return const <String>{
      'read','write','create','delete','submit','cancel','amend','report',
      'import','export','share','print','email',
    }.contains(parts[2].trim().toLowerCase());
  }

  static bool _validPath(String value) {
    if (!value.startsWith('/') || value.contains(' ') || value.contains('//')) {
      return false;
    }
    return RegExp(r"^/[A-Za-z0-9._~!$&'()*+,;=:@%/-]+$").hasMatch(value);
  }

  static String? _nullable(Object? value) {
    final normalized = '${value ?? ''}'.trim();
    return normalized.isEmpty ? null : normalized;
  }

  static List<String> _strings(Object? value) => value is List
      ? value
          .map((entry) => '$entry'.trim())
          .where((entry) => entry.isNotEmpty)
          .toSet()
          .toList(growable: false)
      : const <String>[];

  static bool _bool(Object? value, {required bool fallback}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    return !const <String>{'0', 'false', 'no', 'off'}
        .contains('$value'.trim().toLowerCase());
  }
}
