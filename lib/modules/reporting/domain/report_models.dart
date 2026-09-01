import 'dart:convert';

enum WmnReportAggregate {
  none('NONE'),
  count('COUNT'),
  sum('SUM'),
  average('AVG'),
  minimum('MIN'),
  maximum('MAX');

  const WmnReportAggregate(this.code);
  final String code;

  static WmnReportAggregate fromCode(String? value) => values.firstWhere(
        (entry) => entry.code == value,
        orElse: () => WmnReportAggregate.none,
      );
}

enum WmnReportOperator {
  equals('EQ'),
  notEquals('NE'),
  greaterThan('GT'),
  greaterOrEqual('GTE'),
  lessThan('LT'),
  lessOrEqual('LTE'),
  contains('CONTAINS'),
  startsWith('STARTS_WITH'),
  isEmpty('IS_EMPTY'),
  isNotEmpty('IS_NOT_EMPTY');

  const WmnReportOperator(this.code);
  final String code;

  static WmnReportOperator fromCode(String? value) => values.firstWhere(
        (entry) => entry.code == value,
        orElse: () => WmnReportOperator.equals,
      );
}

class WmnReportColumn {
  const WmnReportColumn({
    required this.field,
    this.label,
    this.aggregate = WmnReportAggregate.none,
  });

  final String field;
  final String? label;
  final WmnReportAggregate aggregate;

  Map<String, Object?> toJson() => {
        'field': field,
        'label': label,
        'aggregate': aggregate.code,
      };

  factory WmnReportColumn.fromJson(Map<String, Object?> json) => WmnReportColumn(
        field: '${json['field'] ?? ''}',
        label: json['label'] as String?,
        aggregate: WmnReportAggregate.fromCode(json['aggregate'] as String?),
      );
}

class WmnReportFilter {
  const WmnReportFilter({
    required this.field,
    required this.operator,
    this.value,
    this.parameterName,
    this.label,
    this.fieldType = 'Data',
    this.options,
    this.required = false,
    this.userEditable = true,
  });

  final String field;
  final WmnReportOperator operator;
  final Object? value;
  final String? parameterName;
  final String? label;
  final String fieldType;
  final String? options;
  final bool required;
  final bool userEditable;

  String get key => (parameterName?.trim().isNotEmpty ?? false) ? parameterName!.trim() : field;

  Map<String, Object?> toJson() => {
        'field': field,
        'operator': operator.code,
        'value': value,
        'parameter_name': parameterName,
        'label': label,
        'field_type': fieldType,
        'options': options,
        'required': required,
        'user_editable': userEditable,
      };

  factory WmnReportFilter.fromJson(Map<String, Object?> json) => WmnReportFilter(
        field: '${json['field'] ?? ''}',
        operator: WmnReportOperator.fromCode(json['operator'] as String?),
        value: json['value'],
        parameterName: json['parameter_name'] as String?,
        label: json['label'] as String?,
        fieldType: '${json['field_type'] ?? 'Data'}',
        options: json['options'] as String?,
        required: json['required'] == true,
        userEditable: json['user_editable'] != false,
      );

  WmnReportFilter withValue(Object? next) => WmnReportFilter(
        field: field,
        operator: operator,
        value: next,
        parameterName: parameterName,
        label: label,
        fieldType: fieldType,
        options: options,
        required: required,
        userEditable: userEditable,
      );
}

class WmnReportSort {
  const WmnReportSort({required this.field, this.descending = false});

  final String field;
  final bool descending;

  Map<String, Object?> toJson() => {'field': field, 'descending': descending};

  factory WmnReportSort.fromJson(Map<String, Object?> json) => WmnReportSort(
        field: '${json['field'] ?? ''}',
        descending: json['descending'] == true,
      );
}

class WmnReportDefinition {
  const WmnReportDefinition({
    required this.id,
    required this.name,
    required this.sourceKey,
    required this.columns,
    this.filters = const [],
    this.sorts = const [],
    this.limit = 500,
    this.enabled = true,
    this.isSystem = false,
  });

  final String id;
  final String name;
  final String sourceKey;
  final List<WmnReportColumn> columns;
  final List<WmnReportFilter> filters;
  final List<WmnReportSort> sorts;
  final int limit;
  final bool enabled;
  final bool isSystem;

  Map<String, Object?> definitionJson() => {
        'columns': columns.map((entry) => entry.toJson()).toList(growable: false),
        'filters': filters.map((entry) => entry.toJson()).toList(growable: false),
        'sorts': sorts.map((entry) => entry.toJson()).toList(growable: false),
        'limit': limit,
      };

  String encodeDefinition() => jsonEncode(definitionJson());

  WmnReportDefinition copyWith({
    String? id,
    String? name,
    String? sourceKey,
    List<WmnReportColumn>? columns,
    List<WmnReportFilter>? filters,
    List<WmnReportSort>? sorts,
    int? limit,
    bool? enabled,
    bool? isSystem,
  }) =>
      WmnReportDefinition(
        id: id ?? this.id,
        name: name ?? this.name,
        sourceKey: sourceKey ?? this.sourceKey,
        columns: columns ?? this.columns,
        filters: filters ?? this.filters,
        sorts: sorts ?? this.sorts,
        limit: limit ?? this.limit,
        enabled: enabled ?? this.enabled,
        isSystem: isSystem ?? this.isSystem,
      );
}

class WmnReportSource {
  const WmnReportSource({
    required this.key,
    required this.label,
    required this.tableName,
    required this.idField,
    this.documentType,
    this.dynamic = false,
  });

  final String key;
  final String label;
  final String tableName;
  final String idField;
  final String? documentType;
  final bool dynamic;
}

class WmnReportField {
  const WmnReportField({
    required this.name,
    required this.label,
    required this.storageType,
    required this.isNumeric,
    required this.isCustom,
  });

  final String name;
  final String label;
  final String storageType;
  final bool isNumeric;
  final bool isCustom;
}

class WmnReportResult {
  const WmnReportResult({
    required this.columns,
    required this.rows,
    required this.durationMs,
  });

  final List<String> columns;
  final List<Map<String, Object?>> rows;
  final int durationMs;
}

class WmnScriptReportFilter {
  const WmnScriptReportFilter({
    required this.fieldName,
    required this.label,
    this.fieldType = 'Data',
    this.options,
    this.defaultValue,
    this.required = false,
    this.dependsOn,
  });

  final String fieldName;
  final String label;
  final String fieldType;
  final String? options;
  final Object? defaultValue;
  final bool required;
  final String? dependsOn;

  Map<String, Object?> toJson() => {
        'fieldname': fieldName,
        'label': label,
        'fieldtype': fieldType,
        'options': options,
        'default': defaultValue,
        'reqd': required,
        'depends_on': dependsOn,
      };

  factory WmnScriptReportFilter.fromJson(Map<String, Object?> json) => WmnScriptReportFilter(
        fieldName: '${json['fieldname'] ?? json['field_name'] ?? ''}',
        label: '${json['label'] ?? json['fieldname'] ?? ''}',
        fieldType: '${json['fieldtype'] ?? json['field_type'] ?? 'Data'}',
        options: json['options']?.toString(),
        defaultValue: json['default'],
        required: json['reqd'] == true || json['reqd'] == 1 || json['required'] == true,
        dependsOn: json['depends_on']?.toString(),
      );
}

class WmnScriptReportColumn {
  const WmnScriptReportColumn({
    required this.fieldName,
    required this.label,
    this.fieldType = 'Data',
    this.options,
    this.width,
  });

  final String fieldName;
  final String label;
  final String fieldType;
  final String? options;
  final double? width;

  Map<String, Object?> toJson() => {
        'fieldname': fieldName,
        'label': label,
        'fieldtype': fieldType,
        'options': options,
        'width': width,
      };

  factory WmnScriptReportColumn.fromJson(Map<String, Object?> json) => WmnScriptReportColumn(
        fieldName: '${json['fieldname'] ?? json['field_name'] ?? ''}',
        label: '${json['label'] ?? json['fieldname'] ?? ''}',
        fieldType: '${json['fieldtype'] ?? json['field_type'] ?? 'Data'}',
        options: json['options']?.toString(),
        width: (json['width'] as num?)?.toDouble(),
      );
}

class WmnScriptReportDefinition {
  const WmnScriptReportDefinition({
    required this.id,
    required this.name,
    required this.module,
    required this.script,
    this.scriptKey,
    this.scriptSourceType = 'NATIVE_HANDLER',
    this.scriptSourcePath,
    this.scriptLanguage,
    this.referenceDocType,
    this.filters = const [],
    this.columns = const [],
    this.isSystem = false,
    this.enabled = true,
  });

  final String id;
  final String name;
  final String module;
  final String? referenceDocType;
  final String script;
  final String? scriptKey;
  final String scriptSourceType;
  final String? scriptSourcePath;
  final String? scriptLanguage;
  final List<WmnScriptReportFilter> filters;
  final List<WmnScriptReportColumn> columns;
  final bool isSystem;
  final bool enabled;
}

class WmnScriptReportResult {
  const WmnScriptReportResult({
    required this.columns,
    required this.rows,
    required this.durationMs,
    this.message,
    this.summary = const [],
  });

  final List<WmnScriptReportColumn> columns;
  final List<Map<String, Object?>> rows;
  final int durationMs;
  final String? message;
  final List<Map<String, Object?>> summary;
}
