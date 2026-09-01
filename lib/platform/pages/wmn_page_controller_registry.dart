import 'package:flutter/widgets.dart';

import 'wmn_page.dart';

typedef WmnPageControllerBuilder = Widget Function(
  BuildContext context,
  WmnPageDefinition page,
);

/// Registry for compiled WMN page extensions.
///
/// Dynamic applications should prefer metadata-driven pages. A compiled app may
/// register a controller key for a highly specialized Flutter page without
/// making System Core depend on that application.
class WmnPageControllerRegistry {
  final Map<String, WmnPageControllerBuilder> _builders =
      <String, WmnPageControllerBuilder>{};

  Set<String> get controllerKeys => Set<String>.unmodifiable(_builders.keys);

  void register(String key, WmnPageControllerBuilder builder) {
    final normalized = key.trim();
    if (normalized.isEmpty) throw StateError('Page controller key is required.');
    if (_builders.containsKey(normalized)) {
      throw StateError('Page controller is already registered: $normalized');
    }
    _builders[normalized] = builder;
  }

  bool contains(String key) => _builders.containsKey(key.trim());

  Widget? build(
    BuildContext context,
    String key,
    WmnPageDefinition page,
  ) => _builders[key.trim()]?.call(context, page);
}
