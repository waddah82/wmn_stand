import 'dart:convert';

import 'field_options.dart';

enum WmnStorageMode { table, dynamic }

class WmnFieldMeta {
  const WmnFieldMeta({
    required this.fieldName,
    required this.label,
    required this.fieldType,
    this.options,
    this.index = 0,
    this.required = false,
    this.readOnly = false,
    this.hidden = false,
    this.inListView = false,
    this.inStandardFilter = false,
    this.searchable = false,
    this.allowOnSubmit = false,
    this.defaultValue,
    this.dependsOn,
    this.mandatoryDependsOn,
    this.readOnlyDependsOn,
    this.fetchFrom,
    this.precision,
    this.length,
    this.isCustom = false,
    this.metadata = const {},
  });

  final String fieldName;
  final String label;
  final String fieldType;
  final String? options;
  final int index;
  final bool required;
  final bool readOnly;
  final bool hidden;
  final bool inListView;
  final bool inStandardFilter;
  final bool searchable;
  final bool allowOnSubmit;
  final Object? defaultValue;
  final String? dependsOn;
  final String? mandatoryDependsOn;
  final String? readOnlyDependsOn;
  final String? fetchFrom;
  final int? precision;
  final int? length;
  final bool isCustom;
  final Map<String, Object?> metadata;

  bool get isLayout => const {'Section Break', 'Column Break', 'Tab Break'}.contains(fieldType);
  bool get isNumeric => const {'Int', 'Float', 'Currency', 'Percent', 'Duration'}.contains(fieldType);
  bool get isBoolean => fieldType == 'Check';
  bool get isDate => const {'Date', 'Datetime', 'Time'}.contains(fieldType);
  bool get isLink => const {'Link', 'Dynamic Link'}.contains(fieldType);

  List<String> get selectOptions => WmnFieldOptions.normalize(options);

  WmnFieldMeta copyWith({
    String? label,
    bool? required,
    bool? readOnly,
    bool? hidden,
    bool? inListView,
    bool? inStandardFilter,
    bool? searchable,
    Object? defaultValue,
    String? options,
  }) =>
      WmnFieldMeta(
        fieldName: fieldName,
        label: label ?? this.label,
        fieldType: fieldType,
        options: options ?? this.options,
        index: index,
        required: required ?? this.required,
        readOnly: readOnly ?? this.readOnly,
        hidden: hidden ?? this.hidden,
        inListView: inListView ?? this.inListView,
        inStandardFilter: inStandardFilter ?? this.inStandardFilter,
        searchable: searchable ?? this.searchable,
        allowOnSubmit: allowOnSubmit,
        defaultValue: defaultValue ?? this.defaultValue,
        dependsOn: dependsOn,
        mandatoryDependsOn: mandatoryDependsOn,
        readOnlyDependsOn: readOnlyDependsOn,
        fetchFrom: fetchFrom,
        precision: precision,
        length: length,
        isCustom: isCustom,
        metadata: metadata,
      );
}

class WmnDocTypeMeta {
  const WmnDocTypeMeta({
    required this.name,
    required this.module,
    required this.storageMode,
    required this.idField,
    this.tableName,
    this.titleField,
    this.autoname,
    this.isSingle = false,
    this.isChild = false,
    this.isSubmittable = false,
    this.trackChanges = true,
    this.allowCreate = true,
    this.allowEdit = true,
    this.allowDelete = true,
    this.allowImport = true,
    this.allowExport = true,
    this.genericWrite = true,
    this.isSystem = false,
    this.enabled = true,
    this.fields = const [],
    this.metadata = const {},
  });

  final String name;
  final String module;
  final WmnStorageMode storageMode;
  final String? tableName;
  final String idField;
  final String? titleField;
  final String? autoname;
  final bool isSingle;
  final bool isChild;
  final bool isSubmittable;
  final bool trackChanges;
  final bool allowCreate;
  final bool allowEdit;
  final bool allowDelete;
  final bool allowImport;
  final bool allowExport;
  final bool genericWrite;
  final bool isSystem;
  final bool enabled;
  final List<WmnFieldMeta> fields;
  final Map<String, Object?> metadata;

  WmnFieldMeta? field(String name) {
    for (final field in fields) {
      if (field.fieldName == name) return field;
    }
    return null;
  }

  List<WmnFieldMeta> get visibleFields => fields.where((field) => !field.hidden && !field.isLayout).toList(growable: false);
  List<WmnFieldMeta> get listFields {
    final selected = fields.where((field) => field.inListView && !field.hidden && !field.isLayout).toList(growable: false);
    if (selected.isNotEmpty) return selected;
    return visibleFields.take(5).toList(growable: false);
  }

  List<WmnFieldMeta> get standardFilterFields {
    final selected = fields.where((field) => field.inStandardFilter && !field.hidden && !field.isLayout).toList(growable: false);
    if (selected.isNotEmpty) return selected;
    return visibleFields.where((field) => field.searchable).take(8).toList(growable: false);
  }
}

class WmnListViewSettings {
  const WmnListViewSettings({
    this.fields = const [],
    this.searchFields = const [],
    this.defaultFilters = const [],
    this.sortField,
    this.sortDescending = true,
    this.pageSize = 20,
    this.hideNameColumn = false,
    this.layout = 'TABLE',
  });

  final List<String> fields;
  final List<String> searchFields;
  final List<List<Object?>> defaultFilters;
  final String? sortField;
  final bool sortDescending;
  final int pageSize;
  final bool hideNameColumn;
  final String layout;

  Map<String, Object?> toJson() => {
        'fields': fields,
        'search_fields': searchFields,
        'default_filters': defaultFilters,
        'sort_field': sortField,
        'sort_descending': sortDescending,
        'page_size': pageSize,
        'hide_name_column': hideNameColumn,
        'layout': layout,
      };

  String encode() => jsonEncode(toJson());

  factory WmnListViewSettings.fromJson(Map<String, Object?> json) => WmnListViewSettings(
        fields: (json['fields'] as List? ?? const []).map((entry) => '$entry').toList(growable: false),
        searchFields: (json['search_fields'] as List? ?? const []).map((entry) => '$entry').toList(growable: false),
        defaultFilters: (json['default_filters'] as List? ?? const [])
            .whereType<List>()
            .map((entry) => List<Object?>.from(entry))
            .toList(growable: false),
        sortField: json['sort_field']?.toString(),
        sortDescending: json['sort_descending'] != false,
        pageSize: (json['page_size'] as num?)?.toInt() ?? 20,
        hideNameColumn: json['hide_name_column'] == true,
        layout: '${json['layout'] ?? 'TABLE'}',
      );
}
