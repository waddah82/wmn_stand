import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/database/wmn_database.dart';
import '../../framework/meta/meta_service.dart';
import '../../framework/model/document_service.dart';

/// Safe declarative runtime for application-owned business methods.
///
/// Sources are JSON documents. They do not execute Dart, JavaScript, Python,
/// shell commands, raw SQL, file-system calls, or platform APIs. The language
/// intentionally exposes only document values, deterministic expressions and
/// metadata-aware document CRUD. Portable application ZIPs can carry validations
/// and lifecycle posting rules without compiling the Flutter host again.
class WmnManagedProcedureRuntime {
  WmnManagedProcedureRuntime({
    required this.database,
    required this.meta,
    required this.documents,
  });

  static const String language = 'wmn-procedure-v1';
  static const Uuid _uuid = Uuid();

  final WmnDatabase database;
  final WmnMetaService meta;
  final WmnDocumentService documents;

  Object? execute(String source, Map<String, Object?> context) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } catch (error) {
      throw StateError('Invalid WMN managed procedure JSON: $error');
    }
    if (decoded is! Map) {
      throw StateError('WMN managed procedure source must be a JSON object.');
    }
    final procedure = Map<String, Object?>.from(decoded);
    if ('${procedure['language'] ?? language}' != language) {
      throw StateError('Unsupported managed procedure language: ${procedure['language']}');
    }
    final version = (procedure['version'] as num?)?.toInt() ?? 1;
    if (version != 1) throw StateError('Unsupported managed procedure version: $version');

    final scope = _Scope(
      context: Map<String, Object?>.from(context),
      variables: <String, Object?>{},
    );
    final steps = _steps(procedure['steps']);
    return database.transaction(() {
      final signal = _runSteps(steps, scope);
      return signal?.value;
    });
  }

  _ReturnSignal? _runSteps(List<Map<String, Object?>> steps, _Scope scope) {
    for (final step in steps) {
      final op = '${step['op'] ?? ''}'.trim();
      switch (op) {
        case 'let':
          final name = _requiredName(step['name'], 'let.name');
          scope.variables[name] = _eval(step['value'], scope);
          break;
        case 'set':
          final path = _requiredName(step['path'], 'set.path');
          _setPath(scope, path, _eval(step['value'], scope));
          break;
        case 'map_put':
          final path = _requiredName(step['path'], 'map_put.path');
          final target = _getPath(scope, path);
          if (target is! Map) {
            throw StateError('Managed procedure map_put target must be a map: $path');
          }
          final key = '${_eval(step['key'], scope) ?? ''}'.trim();
          if (key.isEmpty) throw StateError('map_put.key is required.');
          target[key] = _eval(step['value'], scope);
          break;
        case 'append':
          final path = _requiredName(step['path'], 'append.path');
          final target = _getPath(scope, path);
          if (target is! List) {
            throw StateError('Managed procedure append target must be a list: $path');
          }
          target.add(_eval(step['value'], scope));
          break;
        case 'assert':
          if (!_truthy(_eval(step['test'], scope))) {
            throw StateError(_render('${step['message'] ?? 'Managed procedure validation failed.'}', scope));
          }
          break;
        case 'throw':
          throw StateError(_render('${step['message'] ?? 'Managed procedure stopped.'}', scope));
        case 'if':
          final branch = _truthy(_eval(step['test'], scope)) ? step['then'] : step['else'];
          final signal = _runSteps(_steps(branch), scope);
          if (signal != null) return signal;
          break;
        case 'for_each':
          final list = _asList(_eval(step['items'], scope));
          final asName = '${step['as'] ?? 'row'}'.trim();
          final indexName = '${step['index_as'] ?? 'index'}'.trim();
          final body = _steps(step['steps']);
          for (var index = 0; index < list.length; index++) {
            final child = scope.child(<String, Object?>{
              asName: list[index],
              indexName: index,
            });
            final signal = _runSteps(body, child);
            if (signal != null) return signal;
          }
          break;
        case 'db_get':
          final name = _requiredName(step['as'], 'db_get.as');
          scope.variables[name] = _dbGet(step, scope);
          break;
        case 'db_list':
          final name = _requiredName(step['as'], 'db_list.as');
          scope.variables[name] = _dbList(step, scope);
          break;
        case 'db_insert':
          final value = _dbInsert(step, scope);
          final asName = '${step['as'] ?? ''}'.trim();
          if (asName.isNotEmpty) scope.variables[asName] = value;
          break;
        case 'db_update':
          final value = _dbUpdate(step, scope);
          final asName = '${step['as'] ?? ''}'.trim();
          if (asName.isNotEmpty) scope.variables[asName] = value;
          break;
        case 'db_upsert':
          final value = _dbUpsert(step, scope);
          final asName = '${step['as'] ?? ''}'.trim();
          if (asName.isNotEmpty) scope.variables[asName] = value;
          break;
        case 'db_delete':
          _dbDelete(step, scope);
          break;
        case 'return':
          return _ReturnSignal(_eval(step['value'], scope));
        case 'noop':
          break;
        default:
          throw StateError('Unsupported WMN managed procedure operation: $op');
      }
    }
    return null;
  }

  Object? _eval(Object? expression, _Scope scope) {
    if (expression == null || expression is num || expression is bool) return expression;
    if (expression is String) return expression;
    if (expression is List) return expression.map((entry) => _eval(entry, scope)).toList(growable: false);
    if (expression is! Map) return expression;

    final map = Map<String, Object?>.from(expression);
    if (map.containsKey('get')) return _getPath(scope, '${map['get']}');
    if (map.containsKey('literal')) return map['literal'];
    if (map.containsKey('coalesce')) {
      for (final entry in _asList(map['coalesce'])) {
        final value = _eval(entry, scope);
        if (value != null && (value is! String || value.trim().isNotEmpty)) return value;
      }
      return null;
    }
    if (map.containsKey('if')) {
      final spec = _asMap(map['if']);
      return _truthy(_eval(spec['test'], scope)) ? _eval(spec['then'], scope) : _eval(spec['else'], scope);
    }
    if (map.containsKey('eq')) return _binary(map['eq'], scope, (a, b) => _equivalent(a, b));
    if (map.containsKey('ne')) return _binary(map['ne'], scope, (a, b) => !_equivalent(a, b));
    if (map.containsKey('gt')) return _compare(map['gt'], scope, (v) => v > 0);
    if (map.containsKey('gte')) return _compare(map['gte'], scope, (v) => v >= 0);
    if (map.containsKey('lt')) return _compare(map['lt'], scope, (v) => v < 0);
    if (map.containsKey('lte')) return _compare(map['lte'], scope, (v) => v <= 0);
    if (map.containsKey('close')) {
      final values = _asList(map['close']);
      if (values.length < 2 || values.length > 3) throw StateError('close expects [left, right, optional tolerance].');
      final left = _number(_eval(values[0], scope));
      final right = _number(_eval(values[1], scope));
      final tolerance = values.length == 3 ? _number(_eval(values[2], scope)).abs() : 0.0000001;
      return (left - right).abs() <= tolerance;
    }
    if (map.containsKey('and')) return _asList(map['and']).every((entry) => _truthy(_eval(entry, scope)));
    if (map.containsKey('or')) return _asList(map['or']).any((entry) => _truthy(_eval(entry, scope)));
    if (map.containsKey('not')) return !_truthy(_eval(map['not'], scope));
    if (map.containsKey('empty')) return _isEmpty(_eval(map['empty'], scope));
    if (map.containsKey('not_empty')) return !_isEmpty(_eval(map['not_empty'], scope));
    if (map.containsKey('in')) {
      final values = _asList(map['in']);
      if (values.length != 2) throw StateError('in expects [value, collection].');
      final needle = _eval(values[0], scope);
      final haystack = _eval(values[1], scope);
      if (haystack is Iterable) return haystack.any((entry) => _equivalent(entry, needle));
      return false;
    }
    if (map.containsKey('add')) return _numbers(map['add'], scope).fold<double>(0, (a, b) => a + b);
    if (map.containsKey('mul')) return _numbers(map['mul'], scope).fold<double>(1, (a, b) => a * b);
    if (map.containsKey('sub')) {
      final values = _numbers(map['sub'], scope);
      if (values.isEmpty) return 0.0;
      return values.skip(1).fold<double>(values.first, (a, b) => a - b);
    }
    if (map.containsKey('div')) {
      final values = _numbers(map['div'], scope);
      if (values.length != 2 || values[1] == 0) throw StateError('div expects [numerator, non-zero denominator].');
      return values[0] / values[1];
    }
    if (map.containsKey('abs')) return _number(_eval(map['abs'], scope)).abs();
    if (map.containsKey('round')) {
      final spec = _asMap(map['round']);
      final value = _number(_eval(spec['value'], scope));
      final precision = (_number(_eval(spec['precision'] ?? 2, scope))).toInt().clamp(0, 12).toInt();
      final factor = _pow10(precision);
      return (value * factor).round() / factor;
    }
    if (map.containsKey('min')) {
      final values = _numbers(map['min'], scope);
      return values.isEmpty ? 0.0 : values.reduce((a, b) => a < b ? a : b);
    }
    if (map.containsKey('max')) {
      final values = _numbers(map['max'], scope);
      return values.isEmpty ? 0.0 : values.reduce((a, b) => a > b ? a : b);
    }
    if (map.containsKey('len')) {
      final value = _eval(map['len'], scope);
      if (value is String) return value.length;
      if (value is Map) return value.length;
      return _asList(value).length;
    }
    if (map.containsKey('sum')) {
      final spec = _asMap(map['sum']);
      final items = _asList(_eval(spec['items'], scope));
      final asName = '${spec['as'] ?? 'row'}';
      var total = 0.0;
      for (var i = 0; i < items.length; i++) {
        total += _number(_eval(spec['value'], scope.child(<String, Object?>{asName: items[i], 'index': i})));
      }
      return total;
    }
    if (map.containsKey('concat')) {
      return _asList(map['concat']).map((entry) => '${_eval(entry, scope) ?? ''}').join();
    }
    if (map.containsKey('slice')) {
      final spec = _asMap(map['slice']);
      final value = '${_eval(spec['value'], scope) ?? ''}';
      final start = _number(_eval(spec['start'] ?? 0, scope)).toInt();
      final requestedLength = spec.containsKey('length')
          ? _number(_eval(spec['length'], scope)).toInt()
          : value.length - start;
      if (start < 0 || requestedLength < 0 || start > value.length) {
        throw StateError('slice range is invalid.');
      }
      final end = (start + requestedLength).clamp(start, value.length).toInt();
      return value.substring(start, end);
    }
    if (map.containsKey('starts_with')) {
      final values = _asList(map['starts_with']);
      if (values.length != 2) throw StateError('starts_with expects [value, prefix].');
      return '${_eval(values[0], scope) ?? ''}'.startsWith('${_eval(values[1], scope) ?? ''}');
    }
    if (map.containsKey('ends_with')) {
      final values = _asList(map['ends_with']);
      if (values.length != 2) throw StateError('ends_with expects [value, suffix].');
      return '${_eval(values[0], scope) ?? ''}'.endsWith('${_eval(values[1], scope) ?? ''}');
    }
    if (map.containsKey('to_number')) return _number(_eval(map['to_number'], scope));
    if (map.containsKey('floor')) return _number(_eval(map['floor'], scope)).floorToDouble();
    if (map.containsKey('trim')) return '${_eval(map['trim'], scope) ?? ''}'.trim();
    if (map.containsKey('lower')) return '${_eval(map['lower'], scope) ?? ''}'.toLowerCase();
    if (map.containsKey('upper')) return '${_eval(map['upper'], scope) ?? ''}'.toUpperCase();
    if (map.containsKey('matches')) {
      final values = _asList(map['matches']);
      if (values.length != 2) throw StateError('matches expects [value, pattern].');
      final value = '${_eval(values[0], scope) ?? ''}';
      final pattern = '${_eval(values[1], scope) ?? ''}';
      if (pattern.length > 256) throw StateError('Managed procedure regular expression is too long.');
      return RegExp(pattern).hasMatch(value);
    }
    if (map.containsKey('uuid')) return _uuid.v4();
    if (map.containsKey('now')) return DateTime.now().toUtc().toIso8601String();
    if (map.containsKey('today')) return DateTime.now().toUtc().toIso8601String().substring(0, 10);
    if (map.containsKey('db_get')) return _dbGet(_asMap(map['db_get']), scope);
    if (map.containsKey('db_list')) return _dbList(_asMap(map['db_list']), scope);
    if (map.containsKey('db_exists')) {
      final spec = _asMap(map['db_exists']);
      final doctype = _requiredName(_eval(spec['doctype'], scope), 'db_exists.doctype');
      final name = '${_eval(spec['name'], scope) ?? ''}'.trim();
      if (name.isNotEmpty) return documents.get(doctype, name) != null;
      return _dbList(<String, Object?>{...spec, 'limit': 1}, scope).isNotEmpty;
    }
    if (map.containsKey('db_count')) {
      final spec = _asMap(map['db_count']);
      final doctype = _requiredName(_eval(spec['doctype'], scope), 'db_count.doctype');
      return documents.list(
        doctype,
        filters: _filters(spec['filters'], scope),
        fields: const <String>['name'],
        limit: 1,
      ).total;
    }
    if (map.containsKey('field')) {
      final spec = _asMap(map['field']);
      final value = _eval(spec['from'], scope);
      if (value is Map) return value['${spec['name']}'];
      return null;
    }

    return <String, Object?>{for (final entry in map.entries) entry.key: _eval(entry.value, scope)};
  }

  Map<String, Object?>? _dbGet(Map<String, Object?> spec, _Scope scope) {
    final doctype = _requiredName(_eval(spec['doctype'], scope), 'db_get.doctype');
    final name = '${_eval(spec['name'], scope) ?? ''}'.trim();
    if (name.isNotEmpty) return documents.get(doctype, name);
    final rows = _dbList(<String, Object?>{...spec, 'limit': 1}, scope);
    return rows.isEmpty ? null : rows.first;
  }

  List<Map<String, Object?>> _dbList(Map<String, Object?> spec, _Scope scope) {
    final doctype = _requiredName(_eval(spec['doctype'], scope), 'db_list.doctype');
    final fieldsRaw = _eval(spec['fields'] ?? const <Object?>[], scope);
    final fields = _asList(fieldsRaw).map((entry) => '$entry').where((entry) => entry.trim().isNotEmpty).toList(growable: false);
    final filters = _filters(spec['filters'], scope);
    final orderBy = '${_eval(spec['order_by'], scope) ?? ''}'.trim();
    final orderParts = orderBy.isEmpty ? const <String>[] : orderBy.split(RegExp(r'\s+'));
    final limit = (_number(_eval(spec['limit'] ?? 500, scope))).toInt().clamp(1, 500).toInt();
    final offset = (_number(_eval(spec['offset'] ?? 0, scope))).toInt();
    return documents.list(
      doctype,
      filters: filters,
      fields: fields,
      sortField: orderParts.isEmpty ? null : orderParts.first,
      descending: orderParts.length > 1 ? orderParts[1].toLowerCase() == 'desc' : true,
      limit: limit,
      offset: offset < 0 ? 0 : offset,
    ).rows;
  }

  List<List<Object?>> _filters(Object? raw, _Scope scope) {
    final filters = <List<Object?>>[];
    for (final filter in _asList(raw)) {
      final values = _asList(filter);
      if (values.length < 3) continue;
      filters.add(<Object?>[
        '${_eval(values[0], scope)}',
        '${_eval(values[1], scope)}',
        _eval(values[2], scope),
      ]);
    }
    return filters;
  }

  Map<String, Object?> _dbInsert(Map<String, Object?> spec, _Scope scope) {
    final doctype = _requiredName(_eval(spec['doctype'], scope), 'db_insert.doctype');
    _assertWriteAllowed(doctype, scope);
    final values = _evalMap(spec['values'], scope);
    return documents.saveEngineRecord(doctype, values);
  }

  Map<String, Object?> _dbUpdate(Map<String, Object?> spec, _Scope scope) {
    final doctype = _requiredName(_eval(spec['doctype'], scope), 'db_update.doctype');
    _assertWriteAllowed(doctype, scope);
    final name = _requiredName(_eval(spec['name'], scope), 'db_update.name');
    final existing = documents.get(doctype, name);
    if (existing == null) throw StateError('$doctype $name does not exist.');
    final values = Map<String, Object?>.from(existing)..addAll(_evalMap(spec['values'], scope));
    return documents.saveEngineRecord(doctype, values, existingName: name);
  }

  Map<String, Object?> _dbUpsert(Map<String, Object?> spec, _Scope scope) {
    final doctype = _requiredName(_eval(spec['doctype'], scope), 'db_upsert.doctype');
    _assertWriteAllowed(doctype, scope);
    final values = _evalMap(spec['values'], scope);
    final nameValue = _eval(spec['name'], scope);
    var name = '${nameValue ?? values['name'] ?? ''}'.trim();
    if (name.isEmpty) {
      final existing = _dbGet(<String, Object?>{
        'doctype': doctype,
        'filters': spec['filters'] ?? const <Object?>[],
        'limit': 1,
      }, scope);
      if (existing != null) name = '${existing['name'] ?? ''}'.trim();
    }
    if (name.isEmpty || documents.get(doctype, name) == null) {
      return documents.saveEngineRecord(doctype, values);
    }
    final existing = documents.get(doctype, name)!;
    return documents.saveEngineRecord(doctype, <String, Object?>{...existing, ...values}, existingName: name);
  }

  void _dbDelete(Map<String, Object?> spec, _Scope scope) {
    final doctype = _requiredName(_eval(spec['doctype'], scope), 'db_delete.doctype');
    _assertWriteAllowed(doctype, scope);
    final name = '${_eval(spec['name'], scope) ?? ''}'.trim();
    if (name.isNotEmpty) {
      documents.deleteEngineRecord(doctype, name);
      return;
    }
    final rows = _dbList(<String, Object?>{...spec, 'fields': const <String>['name'], 'limit': 500}, scope);
    for (final row in rows) {
      final value = '${row['name'] ?? ''}'.trim();
      if (value.isNotEmpty) documents.deleteEngineRecord(doctype, value);
    }
  }

  void _assertWriteAllowed(String doctype, _Scope scope) {
    final sourceApp = '${scope.context['source_app'] ?? ''}'.trim();
    if (sourceApp.isEmpty) {
      throw StateError('Managed application write requires source_app context.');
    }
    final rows = database.db.select(
      'SELECT d.module,m.app_name FROM wmn_doctypes d LEFT JOIN wmn_modules m ON m.name=d.module WHERE d.name=? LIMIT 1;',
      <Object?>[doctype],
    );
    if (rows.isEmpty) throw StateError('Unknown DocType: $doctype');
    final owner = '${rows.first['app_name'] ?? ''}'.trim();
    if (owner != sourceApp) {
      throw StateError(
        'Managed application $sourceApp cannot write $doctype; owner is ${owner.isEmpty ? 'WMN System' : owner}.',
      );
    }
  }

  Map<String, Object?> _evalMap(Object? value, _Scope scope) {
    final source = _asMap(value);
    return <String, Object?>{for (final entry in source.entries) entry.key: _eval(entry.value, scope)};
  }

  Object? _getPath(_Scope scope, String path) {
    final parts = path.split('.').where((entry) => entry.isNotEmpty).toList(growable: false);
    if (parts.isEmpty) return null;
    Object? current;
    final first = parts.first;
    if (first == 'doc' || first == 'document') {
      current = scope.context['document'];
    } else if (first == 'previous') {
      current = scope.context['previous'];
    } else if (first == 'context') {
      current = scope.context;
    } else if (first == 'vars') {
      current = scope.variables;
    } else {
      current = scope.lookup(first);
    }
    for (final part in parts.skip(1)) {
      if (current is Map) {
        current = current[part];
      } else if (current is List) {
        final index = int.tryParse(part);
        current = index == null || index < 0 || index >= current.length ? null : current[index];
      } else {
        return null;
      }
    }
    return current;
  }

  void _setPath(_Scope scope, String path, Object? value) {
    final parts = path.split('.').where((entry) => entry.isNotEmpty).toList(growable: false);
    if (parts.length < 2) {
      scope.variables[path] = value;
      return;
    }
    Object? current;
    final first = parts.first;
    if (first == 'doc' || first == 'document') {
      current = scope.context['document'];
    } else if (first == 'vars') {
      current = scope.variables;
    } else {
      current = scope.lookup(first);
    }
    if (current == null) throw StateError('Cannot set managed procedure path: $path');
    for (var index = 1; index < parts.length - 1; index++) {
      final part = parts[index];
      if (current is Map) {
        current = current[part];
      } else if (current is List) {
        final listIndex = int.tryParse(part);
        if (listIndex == null || listIndex < 0 || listIndex >= current.length) {
          throw StateError('Invalid managed procedure list path: $path');
        }
        current = current[listIndex];
      } else {
        throw StateError('Cannot set managed procedure path: $path');
      }
    }
    final last = parts.last;
    if (current is Map) {
      current[last] = value;
      return;
    }
    if (current is List) {
      final index = int.tryParse(last);
      if (index == null || index < 0 || index >= current.length) throw StateError('Invalid managed procedure list path: $path');
      current[index] = value;
      return;
    }
    throw StateError('Cannot set managed procedure path: $path');
  }

  String _render(String template, _Scope scope) {
    return template.replaceAllMapped(RegExp(r'\{\{\s*([^}]+)\s*\}\}'), (match) {
      final value = _getPath(scope, match.group(1)!.trim());
      return '${value ?? ''}';
    });
  }

  bool _binary(Object? raw, _Scope scope, bool Function(Object?, Object?) test) {
    final values = _asList(raw);
    if (values.length != 2) throw StateError('Binary expression expects exactly two values.');
    return test(_eval(values[0], scope), _eval(values[1], scope));
  }

  bool _compare(Object? raw, _Scope scope, bool Function(int) test) {
    final values = _asList(raw);
    if (values.length != 2) throw StateError('Comparison expects exactly two values.');
    final left = _eval(values[0], scope);
    final right = _eval(values[1], scope);
    final a = double.tryParse('${left ?? ''}');
    final b = double.tryParse('${right ?? ''}');
    if (a != null && b != null) return test(a.compareTo(b));
    return test('${left ?? ''}'.compareTo('${right ?? ''}'));
  }

  List<double> _numbers(Object? raw, _Scope scope) =>
      _asList(raw).map((entry) => _number(_eval(entry, scope))).toList(growable: false);

  double _number(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}'.trim()) ?? 0.0;
  }

  bool _equivalent(Object? left, Object? right) {
    if (left == right) return true;
    final a = double.tryParse('${left ?? ''}');
    final b = double.tryParse('${right ?? ''}');
    if (a != null && b != null) return (a - b).abs() < 0.0000001;
    return '${left ?? ''}' == '${right ?? ''}';
  }

  bool _truthy(Object? value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized.isNotEmpty && !const <String>{'0', 'false', 'no', 'off', 'null', 'none'}.contains(normalized);
    }
    if (value is Iterable) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  bool _isEmpty(Object? value) {
    if (value == null) return true;
    if (value is String) return value.trim().isEmpty;
    if (value is Iterable) return value.isEmpty;
    if (value is Map) return value.isEmpty;
    return false;
  }

  String _requiredName(Object? value, String label) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) throw StateError('$label is required.');
    return text;
  }

  List<Object?> _asList(Object? value) {
    if (value == null) return const <Object?>[];
    if (value is List<Object?>) return value;
    if (value is List) return List<Object?>.from(value);
    return <Object?>[value];
  }

  Map<String, Object?> _asMap(Object? value) {
    if (value is Map<String, Object?>) return Map<String, Object?>.from(value);
    if (value is Map) return Map<String, Object?>.from(value);
    return <String, Object?>{};
  }

  List<Map<String, Object?>> _steps(Object? value) => _asList(value)
      .whereType<Map>()
      .map((entry) => Map<String, Object?>.from(entry))
      .toList(growable: false);

  double _pow10(int precision) {
    var result = 1.0;
    for (var i = 0; i < precision; i++) result *= 10.0;
    return result;
  }
}

class _Scope {
  _Scope({
    required this.context,
    required this.variables,
    this.parent,
  });

  final Map<String, Object?> context;
  final Map<String, Object?> variables;
  final _Scope? parent;

  _Scope child(Map<String, Object?> locals) => _Scope(
        context: context,
        variables: <String, Object?>{...locals},
        parent: this,
      );

  Object? lookup(String name) {
    if (variables.containsKey(name)) return variables[name];
    if (context.containsKey(name)) return context[name];
    return parent?.lookup(name);
  }
}

class _ReturnSignal {
  const _ReturnSignal(this.value);
  final Object? value;
}
