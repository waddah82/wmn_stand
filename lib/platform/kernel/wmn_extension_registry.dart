class WmnExtensionPoint {
  const WmnExtensionPoint({
    required this.id,
    required this.description,
    this.allowMultiple = true,
  });

  final String id;
  final String description;
  final bool allowMultiple;
}

class WmnExtensionRegistration {
  const WmnExtensionRegistration({
    required this.pointId,
    required this.ownerId,
    required this.handler,
    this.priority = 100,
  });

  final String pointId;
  final String ownerId;
  final Object handler;
  final int priority;
}

/// Native extension-point registry used by WMN applications and adapters.
///
/// This registry contains only already-compiled Dart handlers. Editable custom
/// scripts remain activation-gated and cannot bypass the safe script runtime.
class WmnExtensionRegistry {
  final Map<String, WmnExtensionPoint> _points = <String, WmnExtensionPoint>{};
  final Map<String, List<WmnExtensionRegistration>> _handlers = <String, List<WmnExtensionRegistration>>{};

  List<WmnExtensionPoint> get points => _points.values.toList(growable: false)..sort((a, b) => a.id.compareTo(b.id));

  void define(WmnExtensionPoint point) {
    if (point.id.trim().isEmpty) throw StateError('Extension point id is required.');
    _points[point.id] = point;
  }

  void register(WmnExtensionRegistration registration) {
    final point = _points[registration.pointId];
    if (point == null) {
      throw StateError('Unknown WMN extension point: ${registration.pointId}');
    }
    final handlers = _handlers.putIfAbsent(registration.pointId, () => <WmnExtensionRegistration>[]);
    if (!point.allowMultiple && handlers.isNotEmpty) {
      throw StateError('WMN extension point ${point.id} accepts only one handler.');
    }
    if (handlers.any((entry) => entry.ownerId == registration.ownerId)) {
      throw StateError('${registration.ownerId} is already registered for ${registration.pointId}.');
    }
    handlers.add(registration);
    handlers.sort((a, b) => a.priority.compareTo(b.priority));
  }

  List<WmnExtensionRegistration> handlersFor(String pointId) =>
      List<WmnExtensionRegistration>.unmodifiable(_handlers[pointId] ?? const <WmnExtensionRegistration>[]);

  void unregisterOwner(String ownerId) {
    for (final handlers in _handlers.values) {
      handlers.removeWhere((entry) => entry.ownerId == ownerId);
    }
  }
}
