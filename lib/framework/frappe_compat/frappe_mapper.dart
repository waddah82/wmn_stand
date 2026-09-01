import 'frappe_documents.dart';
import 'frappe_meta_api.dart';

typedef WmnFrappeMapCondition = bool Function(Map<String, Object?> source);
typedef WmnFrappeMapPostprocess = void Function(
  Map<String, Object?> source,
  Map<String, Object?> target,
);

class WmnFrappeMapValidation {
  const WmnFrappeMapValidation({
    required this.field,
    required this.expected,
    this.operator = '=',
  });

  final String field;
  final Object? expected;
  final String operator;
}

class WmnFrappeChildMap {
  const WmnFrappeChildMap({
    required this.sourceField,
    required this.targetField,
    this.targetDoctype,
    this.fieldMap = const {},
    this.fieldNoMap = const {},
    this.condition,
    this.filter,
    this.postprocess,
    this.addIfEmpty = false,
    this.resetValue = false,
  });

  final String sourceField;
  final String targetField;
  final String? targetDoctype;
  final Map<String, String> fieldMap;
  final Set<String> fieldNoMap;
  final WmnFrappeMapCondition? condition;
  final WmnFrappeMapCondition? filter;
  final WmnFrappeMapPostprocess? postprocess;
  final bool addIfEmpty;
  final bool resetValue;
}

class WmnFrappeDocumentMap {
  const WmnFrappeDocumentMap({
    required this.sourceDoctype,
    required this.targetDoctype,
    this.fieldMap = const {},
    this.fieldNoMap = const {},
    this.children = const [],
    this.validations = const [],
    this.postprocess,
  });

  final String sourceDoctype;
  final String targetDoctype;
  final Map<String, String> fieldMap;
  final Set<String> fieldNoMap;
  final List<WmnFrappeChildMap> children;
  final List<WmnFrappeMapValidation> validations;
  final WmnFrappeMapPostprocess? postprocess;
}

/// Structured Dart equivalent of Frappe `get_mapped_doc`.
///
/// It preserves the same important contract: permission-aware source read,
/// creation of a target draft, same-name field copying, explicit field maps,
/// validation, child mapping and post-processing. Python callbacks are never
/// executed; module ports provide Dart callbacks instead.
class WmnFrappeDocumentMapper {
  const WmnFrappeDocumentMapper({required this.documents, required this.meta});

  final WmnFrappeDocumentApi documents;
  final WmnFrappeMetaApi meta;

  Map<String, Object?> mapDocument(
    String sourceName,
    WmnFrappeDocumentMap mapping, {
    Map<String, Object?>? target,
  }) {
    final source = documents.getDoc(mapping.sourceDoctype, sourceName);
    if (source == null) {
      throw StateError('${mapping.sourceDoctype} $sourceName does not exist.');
    }
    _validateSource(source, mapping.validations);

    final result = target == null
        ? documents.newDoc(mapping.targetDoctype)
        : Map<String, Object?>.from(target);
    final targetFields = _targetFields(mapping.targetDoctype);

    _mapFields(
      source,
      result,
      targetFields: targetFields,
      fieldMap: mapping.fieldMap,
      fieldNoMap: mapping.fieldNoMap,
    );

    result['__mapped_from_doctype'] = mapping.sourceDoctype;
    result['__mapped_from_name'] = sourceName;

    for (final childMap in mapping.children) {
      final rawRows = source[childMap.sourceField];
      if (rawRows is! List) continue;
      final existing = result[childMap.targetField];
      if (childMap.addIfEmpty && existing is List && existing.isNotEmpty) continue;
      final rows = childMap.resetValue || existing is! List
          ? <Map<String, Object?>>[]
          : existing.whereType<Map>().map(_stringMap).toList(growable: true);
      final childTargetFields = childMap.targetDoctype == null
          ? null
          : _targetFields(childMap.targetDoctype!);
      for (final raw in rawRows.whereType<Map>()) {
        final sourceRow = _stringMap(raw);
        if (childMap.condition != null && !childMap.condition!(sourceRow)) continue;
        // Frappe's child `filter` callback returns true to skip the row.
        if (childMap.filter != null && childMap.filter!(sourceRow)) continue;
        final targetRow = <String, Object?>{};
        _mapFields(
          sourceRow,
          targetRow,
          targetFields: childTargetFields,
          fieldMap: childMap.fieldMap,
          fieldNoMap: childMap.fieldNoMap,
        );
        childMap.postprocess?.call(sourceRow, targetRow);
        rows.add(targetRow);
      }
      result[childMap.targetField] = rows;
    }

    mapping.postprocess?.call(source, result);
    return result;
  }

  void _validateSource(
    Map<String, Object?> source,
    List<WmnFrappeMapValidation> validations,
  ) {
    for (final validation in validations) {
      final actual = source[validation.field];
      final valid = switch (validation.operator) {
        '=' || '==' => actual == validation.expected,
        '!=' => actual != validation.expected,
        _ => throw StateError('Unsupported mapping validation operator: ${validation.operator}.'),
      };
      if (!valid) {
        throw StateError(
          'Cannot map because condition fails: ${validation.field} '
          '${validation.operator} ${validation.expected}.',
        );
      }
    }
  }

  void _mapFields(
    Map<String, Object?> source,
    Map<String, Object?> target, {
    required Set<String>? targetFields,
    required Map<String, String> fieldMap,
    required Set<String> fieldNoMap,
  }) {
    for (final entry in source.entries) {
      final sourceField = entry.key;
      if (_systemField(sourceField) || fieldNoMap.contains(sourceField)) continue;
      final targetField = fieldMap[sourceField] ?? sourceField;
      if (targetFields != null && !targetFields.contains(targetField)) continue;
      final value = entry.value;
      if (value == null || value == '') continue;
      target[targetField] = value;
    }
  }

  Set<String> _targetFields(String doctype) {
    final targetMeta = meta.getMeta(doctype);
    if (targetMeta == null) throw StateError('Unknown target DocType: $doctype');
    return <String>{
      'name',
      ...((targetMeta['fields'] as List?) ?? const [])
          .whereType<Map>()
          .map((field) => '${field['fieldname']}'),
    };
  }

  Map<String, Object?> _stringMap(Map raw) => <String, Object?>{
        for (final entry in raw.entries) '${entry.key}': entry.value,
      };

  bool _systemField(String field) => const {
        'name',
        'owner',
        'creation',
        'modified',
        'modified_by',
        'docstatus',
        'idx',
        'parent',
        'parentfield',
        'parenttype',
        '__islocal',
        '__dirty',
      }.contains(field);
}
