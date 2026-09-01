import 'dart:convert';

enum WmnCustomFieldType {
  data('DATA'),
  text('TEXT'),
  integer('INT'),
  floating('FLOAT'),
  currency('CURRENCY'),
  check('CHECK'),
  select('SELECT'),
  date('DATE'),
  dateTime('DATETIME'),
  link('LINK'),
  json('JSON');

  const WmnCustomFieldType(this.code);
  final String code;

  static WmnCustomFieldType fromCode(String value) => values.firstWhere(
        (entry) => entry.code == value,
        orElse: () => WmnCustomFieldType.data,
      );
}

class WmnCustomField {
  const WmnCustomField({
    required this.id,
    required this.documentType,
    required this.fieldName,
    required this.label,
    required this.fieldType,
    this.insertAfter,
    this.options = const [],
    this.defaultValue,
    this.required = false,
    this.readOnly = false,
    this.hidden = false,
    this.inListView = false,
    this.searchable = false,
    this.sortOrder = 0,
    this.enabled = true,
  });

  final String id;
  final String documentType;
  final String fieldName;
  final String label;
  final WmnCustomFieldType fieldType;
  final String? insertAfter;
  final List<String> options;
  final Object? defaultValue;
  final bool required;
  final bool readOnly;
  final bool hidden;
  final bool inListView;
  final bool searchable;
  final int sortOrder;
  final bool enabled;

  WmnCustomField copyWith({
    String? label,
    List<String>? options,
    Object? defaultValue,
    bool? required,
    bool? readOnly,
    bool? hidden,
    bool? inListView,
    bool? searchable,
    bool? enabled,
  }) =>
      WmnCustomField(
        id: id,
        documentType: documentType,
        fieldName: fieldName,
        label: label ?? this.label,
        fieldType: fieldType,
        insertAfter: insertAfter,
        options: options ?? this.options,
        defaultValue: defaultValue ?? this.defaultValue,
        required: required ?? this.required,
        readOnly: readOnly ?? this.readOnly,
        hidden: hidden ?? this.hidden,
        inListView: inListView ?? this.inListView,
        searchable: searchable ?? this.searchable,
        sortOrder: sortOrder,
        enabled: enabled ?? this.enabled,
      );
}

class WmnPropertyOverride {
  const WmnPropertyOverride({
    required this.id,
    required this.documentType,
    required this.fieldName,
    required this.propertyName,
    required this.value,
    this.enabled = true,
  });

  final String id;
  final String documentType;
  final String fieldName;
  final String propertyName;
  final Object? value;
  final bool enabled;
}

class WmnClientScript {
  const WmnClientScript({
    required this.id,
    required this.name,
    required this.documentType,
    required this.script,
    this.priority = 0,
    this.enabled = true,
  });

  final String id;
  final String name;
  final String documentType;
  final String script;
  final int priority;
  final bool enabled;
}

class WmnServerScript {
  const WmnServerScript({
    required this.id,
    required this.name,
    required this.scriptType,
    required this.script,
    this.documentType,
    this.eventName,
    this.apiMethod,
    this.priority = 0,
    this.enabled = true,
  });

  final String id;
  final String name;
  final String scriptType;
  final String? documentType;
  final String? eventName;
  final String? apiMethod;
  final String script;
  final int priority;
  final bool enabled;
}

class WmnScriptEffects {
  const WmnScriptEffects({
    this.messages = const [],
    this.fieldProperties = const {},
    this.queries = const [],
  });

  final List<String> messages;
  final Map<String, Map<String, Object?>> fieldProperties;
  final List<Map<String, Object?>> queries;

  WmnScriptEffects merge(WmnScriptEffects other) {
    final mergedProperties = <String, Map<String, Object?>>{
      for (final entry in fieldProperties.entries) entry.key: Map<String, Object?>.from(entry.value),
    };
    for (final entry in other.fieldProperties.entries) {
      mergedProperties.putIfAbsent(entry.key, () => <String, Object?>{}).addAll(entry.value);
    }
    return WmnScriptEffects(
      messages: [...messages, ...other.messages],
      fieldProperties: mergedProperties,
      queries: [...queries, ...other.queries],
    );
  }
}

class WmnScriptResult {
  const WmnScriptResult({
    required this.document,
    this.effects = const WmnScriptEffects(),
  });

  final Map<String, Object?> document;
  final WmnScriptEffects effects;
}

Object? decodeJsonValue(Object? value) {
  if (value == null) return null;
  if (value is! String || value.isEmpty) return value;
  try {
    return jsonDecode(value);
  } catch (_) {
    return value;
  }
}

String? encodeJsonValue(Object? value) => value == null ? null : jsonEncode(value);
