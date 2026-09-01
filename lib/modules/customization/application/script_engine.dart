import '../../../core/documents/document_registry.dart';
import '../../../framework/frappe_compat/frappe_runtime.dart';
import '../domain/customization_models.dart';

/// Lightweight policy kept only for validating stored script metadata.
///
/// R2.1 CLEAN PLATFORM deliberately does not execute arbitrary JavaScript.
/// Client/Server Script definitions may be imported and preserved, but the
/// runtime is disabled until a cross-platform sandbox is reintroduced later.
class WmnScriptPolicyViolation extends StateError {
  WmnScriptPolicyViolation({required this.capability})
      : super('Script uses a blocked capability: $capability');

  final String capability;
}

class WmnScriptPolicy {
  const WmnScriptPolicy();

  void validate(String script) {
    if (script.trim().isEmpty) {
      throw StateError('Script cannot be empty.');
    }
    if (script.length > 100000) {
      throw StateError('Script is larger than the 100 KB storage limit.');
    }
  }
}

/// Compatibility facade retained for form metadata and workflow conditions.
///
/// Script execution is intentionally disabled in R2.1. The class remains so
/// existing platform services do not need a second compatibility layer. Its
/// only active behavior is deterministic Dart-side condition evaluation.
class WmnScriptEngine {
  WmnScriptEngine({
    required this.registry,
    this.frappeRuntime,
    this.policy = const WmnScriptPolicy(),
  });

  final WmnDocumentRegistry registry;
  final WmnFrappeRuntime? frappeRuntime;
  final WmnScriptPolicy policy;

  bool get executionEnabled => false;

  WmnScriptResult executeClient({
    required String documentType,
    required String eventName,
    String? fieldName,
    required Map<String, Object?> document,
    required String script,
  }) {
    policy.validate(script);
    return WmnScriptResult(document: Map<String, Object?>.from(document));
  }

  WmnScriptResult executeServer({
    required String documentType,
    required String eventName,
    required Map<String, Object?> document,
    required String script,
  }) {
    policy.validate(script);
    return WmnScriptResult(document: Map<String, Object?>.from(document));
  }

  /// Evaluates the small expression subset used by Frappe metadata fields such
  /// as depends_on / mandatory_depends_on / read_only_depends_on.
  ///
  /// Supported intentionally:
  /// - bare field names
  /// - doc.field / doc['field'] / doc["field"]
  /// - !, &&, ||
  /// - ==, ===, !=, !==, >, >=, <, <=
  /// - string, number, true, false, null literals
  ///
  /// Function calls and arbitrary JavaScript are not executed.
  bool evaluateCondition({
    required String expression,
    required Map<String, Object?> document,
  }) {
    var source = expression.trim();
    if (source.isEmpty) return true;
    if (source.startsWith('eval:')) source = source.substring(5).trim();
    try {
      return _evaluateBoolean(_stripOuterParens(source), document);
    } catch (_) {
      return false;
    }
  }

  bool _evaluateBoolean(String source, Map<String, Object?> doc) {
    final orParts = _splitTopLevel(source, '||');
    if (orParts.length > 1) {
      return orParts.any((part) => _evaluateBoolean(part, doc));
    }

    final andParts = _splitTopLevel(source, '&&');
    if (andParts.length > 1) {
      return andParts.every((part) => _evaluateBoolean(part, doc));
    }

    var value = source.trim();
    if (value.startsWith('!') && !value.startsWith('!=')) {
      return !_evaluateBoolean(value.substring(1).trim(), doc);
    }

    for (final op in const ['===', '!==', '>=', '<=', '==', '!=', '>', '<']) {
      final index = _findTopLevelOperator(value, op);
      if (index < 0) continue;
      final left = _resolve(value.substring(0, index).trim(), doc);
      final right = _resolve(value.substring(index + op.length).trim(), doc);
      return _compare(left, right, op);
    }

    return _truthy(_resolve(value, doc));
  }

  Object? _resolve(String token, Map<String, Object?> doc) {
    final value = _stripOuterParens(token.trim());
    if (value.isEmpty) return null;
    if (value == 'true') return true;
    if (value == 'false') return false;
    if (value == 'null' || value == 'undefined') return null;

    if ((value.startsWith("'") && value.endsWith("'")) ||
        (value.startsWith('"') && value.endsWith('"'))) {
      return value.substring(1, value.length - 1);
    }

    final number = num.tryParse(value);
    if (number != null) return number;

    final dot = RegExp(r'^doc\.([A-Za-z_][A-Za-z0-9_]*)$').firstMatch(value);
    if (dot != null) return doc[dot.group(1)!];

    final bracket = RegExp(r'''^doc\[['\"]([^'\"]+)['\"]\]$''').firstMatch(value);
    if (bracket != null) return doc[bracket.group(1)!];

    if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value)) {
      return doc[value];
    }

    return null;
  }

  bool _compare(Object? left, Object? right, String op) {
    if (op == '==' || op == '===') return _equivalent(left, right);
    if (op == '!=' || op == '!==') return !_equivalent(left, right);

    final leftNumber = _asNumber(left);
    final rightNumber = _asNumber(right);
    if (leftNumber != null && rightNumber != null) {
      return switch (op) {
        '>' => leftNumber > rightNumber,
        '>=' => leftNumber >= rightNumber,
        '<' => leftNumber < rightNumber,
        '<=' => leftNumber <= rightNumber,
        _ => false,
      };
    }

    final a = '${left ?? ''}';
    final b = '${right ?? ''}';
    final order = a.compareTo(b);
    return switch (op) {
      '>' => order > 0,
      '>=' => order >= 0,
      '<' => order < 0,
      '<=' => order <= 0,
      _ => false,
    };
  }

  bool _equivalent(Object? left, Object? right) {
    if (left == right) return true;
    final a = _asNumber(left);
    final b = _asNumber(right);
    if (a != null && b != null) return a == b;
    return '${left ?? ''}' == '${right ?? ''}';
  }

  num? _asNumber(Object? value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value.trim());
    return null;
  }

  bool _truthy(Object? value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final text = value.trim().toLowerCase();
      return text.isNotEmpty && !const {'0', 'false', 'no', 'off', 'null', 'none'}.contains(text);
    }
    if (value is Iterable) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  List<String> _splitTopLevel(String source, String operator) {
    final parts = <String>[];
    var start = 0;
    var depth = 0;
    String? quote;
    for (var i = 0; i <= source.length - operator.length; i++) {
      final ch = source[i];
      if (quote != null) {
        if (ch == quote && (i == 0 || source[i - 1] != '\\')) quote = null;
        continue;
      }
      if (ch == "'" || ch == '"') {
        quote = ch;
        continue;
      }
      if (ch == '(') {
        depth++;
        continue;
      }
      if (ch == ')') {
        depth--;
        continue;
      }
      if (depth == 0 && source.startsWith(operator, i)) {
        parts.add(source.substring(start, i).trim());
        start = i + operator.length;
        i += operator.length - 1;
      }
    }
    if (start == 0) return [source.trim()];
    parts.add(source.substring(start).trim());
    return parts;
  }

  int _findTopLevelOperator(String source, String operator) {
    var depth = 0;
    String? quote;
    for (var i = 0; i <= source.length - operator.length; i++) {
      final ch = source[i];
      if (quote != null) {
        if (ch == quote && (i == 0 || source[i - 1] != '\\')) quote = null;
        continue;
      }
      if (ch == "'" || ch == '"') {
        quote = ch;
        continue;
      }
      if (ch == '(') {
        depth++;
        continue;
      }
      if (ch == ')') {
        depth--;
        continue;
      }
      if (depth == 0 && source.startsWith(operator, i)) return i;
    }
    return -1;
  }

  String _stripOuterParens(String source) {
    var value = source.trim();
    while (value.length >= 2 && value.startsWith('(') && value.endsWith(')')) {
      var depth = 0;
      var enclosesAll = true;
      String? quote;
      for (var i = 0; i < value.length; i++) {
        final ch = value[i];
        if (quote != null) {
          if (ch == quote && (i == 0 || value[i - 1] != '\\')) quote = null;
          continue;
        }
        if (ch == "'" || ch == '"') {
          quote = ch;
          continue;
        }
        if (ch == '(') depth++;
        if (ch == ')') depth--;
        if (depth == 0 && i < value.length - 1) {
          enclosesAll = false;
          break;
        }
      }
      if (!enclosesAll) break;
      value = value.substring(1, value.length - 1).trim();
    }
    return value;
  }
}
