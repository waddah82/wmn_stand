import 'dart:convert';

typedef WmnWorkflowConditionHandler = bool Function(
  Map<String, Object?> document,
  Map<String, Object?> metadata,
);

/// Safe declarative workflow condition engine.
///
/// Arbitrary Dart, JavaScript, Python and SQL are never executed. Conditions
/// are JSON expressions, or a compiled handler explicitly registered by an
/// application through [WmnWorkflowConditionRegistry].
class WmnWorkflowConditionRegistry {
  final Map<String, WmnWorkflowConditionHandler> _handlers =
      <String, WmnWorkflowConditionHandler>{};

  void register(String key, WmnWorkflowConditionHandler handler) {
    final normalized = key.trim();
    if (normalized.isEmpty) {
      throw StateError('Workflow condition handler key cannot be empty.');
    }
    if (_handlers.containsKey(normalized)) {
      throw StateError('Workflow condition handler already registered: $normalized');
    }
    _handlers[normalized] = handler;
  }

  bool unregister(String key) => _handlers.remove(key.trim()) != null;

  bool evaluate(
    String key,
    Map<String, Object?> document,
    Map<String, Object?> metadata,
  ) {
    final handler = _handlers[key.trim()];
    if (handler == null) return false;
    return handler(document, metadata);
  }

  bool contains(String key) => _handlers.containsKey(key.trim());

  int get length => _handlers.length;
}

class WmnWorkflowConditionEngine {
  WmnWorkflowConditionEngine({WmnWorkflowConditionRegistry? registry})
      : registry = registry ?? WmnWorkflowConditionRegistry();

  final WmnWorkflowConditionRegistry registry;

  bool evaluate(
    String? expression,
    Map<String, Object?> document, {
    String? handlerKey,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final handler = handlerKey?.trim() ?? '';
    if (handler.isNotEmpty) {
      return registry.evaluate(handler, document, metadata);
    }

    final source = expression?.trim() ?? '';
    if (source.isEmpty) return true;
    if (!source.startsWith('{')) return false;

    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return false;
      return _evaluateNode(Map<String, Object?>.from(decoded), document);
    } catch (_) {
      return false;
    }
  }

  bool isSupported(String? expression, {String? handlerKey}) {
    final handler = handlerKey?.trim() ?? '';
    if (handler.isNotEmpty) return registry.contains(handler);
    final source = expression?.trim() ?? '';
    if (source.isEmpty) return true;
    if (!source.startsWith('{')) return false;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return false;
      return _validateNode(Map<String, Object?>.from(decoded));
    } catch (_) {
      return false;
    }
  }

  bool _evaluateNode(
    Map<String, Object?> node,
    Map<String, Object?> document,
  ) {
    final all = node['all'];
    if (all is List) {
      return all.every(
        (entry) => entry is Map &&
            _evaluateNode(Map<String, Object?>.from(entry), document),
      );
    }

    final any = node['any'];
    if (any is List) {
      return any.any(
        (entry) => entry is Map &&
            _evaluateNode(Map<String, Object?>.from(entry), document),
      );
    }

    final not = node['not'];
    if (not is Map) {
      return !_evaluateNode(Map<String, Object?>.from(not), document);
    }

    final field = '${node['field'] ?? ''}'.trim();
    final op = '${node['op'] ?? 'eq'}'.trim().toLowerCase();
    if (field.isEmpty) return false;
    final actual = _fieldValue(document, field);
    final expected = node['value'];

    return switch (op) {
      'eq' || '==' => _equals(actual, expected),
      'ne' || '!=' => !_equals(actual, expected),
      'gt' || '>' => _compare(actual, expected) > 0,
      'gte' || '>=' => _compare(actual, expected) >= 0,
      'lt' || '<' => _compare(actual, expected) < 0,
      'lte' || '<=' => _compare(actual, expected) <= 0,
      'in' => expected is List && expected.any((entry) => _equals(actual, entry)),
      'not_in' => expected is List && !expected.any((entry) => _equals(actual, entry)),
      'is_set' => actual != null && '$actual'.trim().isNotEmpty,
      'is_not_set' => actual == null || '$actual'.trim().isEmpty,
      _ => false,
    };
  }

  bool _validateNode(Map<String, Object?> node) {
    for (final key in const <String>['all', 'any']) {
      final value = node[key];
      if (value != null) {
        return value is List &&
            value.isNotEmpty &&
            value.every(
              (entry) => entry is Map &&
                  _validateNode(Map<String, Object?>.from(entry)),
            );
      }
    }
    final not = node['not'];
    if (not != null) {
      return not is Map && _validateNode(Map<String, Object?>.from(not));
    }
    final field = '${node['field'] ?? ''}'.trim();
    final op = '${node['op'] ?? 'eq'}'.trim().toLowerCase();
    return field.isNotEmpty &&
        const <String>{
          'eq','==','ne','!=','gt','>','gte','>=','lt','<','lte','<=',
          'in','not_in','is_set','is_not_set',
        }.contains(op);
  }

  Object? _fieldValue(Map<String, Object?> document, String path) {
    Object? current = document;
    for (final segment in path.split('.')) {
      if (current is! Map) return null;
      current = current[segment];
    }
    return current;
  }

  bool _equals(Object? left, Object? right) {
    if (left is num && right is num) return left == right;
    if (left is bool && right is bool) return left == right;
    return '${left ?? ''}' == '${right ?? ''}';
  }

  int _compare(Object? left, Object? right) {
    if (left is num && right is num) return left.compareTo(right);
    final leftNumber = double.tryParse('${left ?? ''}');
    final rightNumber = double.tryParse('${right ?? ''}');
    if (leftNumber != null && rightNumber != null) {
      return leftNumber.compareTo(rightNumber);
    }
    return '${left ?? ''}'.compareTo('${right ?? ''}');
  }
}
