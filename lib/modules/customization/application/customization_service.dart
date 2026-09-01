import '../../../core/audit/audit_service.dart';
import '../../../core/documents/document_registry.dart';
import '../data/customization_repository.dart';
import '../domain/customization_models.dart';
import 'script_engine.dart';

class WmnFormCustomizationSnapshot {
  const WmnFormCustomizationSnapshot({
    required this.documentType,
    required this.documentId,
    required this.fields,
    required this.values,
    required this.fieldProperties,
  });

  final String documentType;
  final String? documentId;
  final List<WmnCustomField> fields;
  final Map<String, Object?> values;
  final Map<String, Map<String, Object?>> fieldProperties;
}

class CustomizationService {
  CustomizationService({
    required this.repository,
    required this.registry,
    required this.scriptEngine,
    required this.audit,
  });

  final CustomizationRepository repository;
  final WmnDocumentRegistry registry;
  final WmnScriptEngine scriptEngine;
  final AuditService audit;

  static const List<String> customizableDocumentTypes = <String>[];

  List<String> get documentTypes {
    final result = customizableDocumentTypes.toSet();
    final table = repository.database.db.select(
      "SELECT 1 FROM sqlite_master WHERE type='table' AND name='wmn_doctypes' LIMIT 1;",
    );
    if (table.isNotEmpty) {
      result.addAll(
        repository.database.db
            .select("SELECT name FROM wmn_doctypes WHERE enabled = 1 ORDER BY name;")
            .map((row) => row['name'] as String),
      );
    }
    return result.toList(growable: false)..sort();
  }

  List<WmnCustomField> customFields({String? documentType, bool enabledOnly = false}) =>
      repository.customFields(documentType: documentType, enabledOnly: enabledOnly);

  List<WmnPropertyOverride> propertyOverrides({String? documentType, bool enabledOnly = false}) =>
      repository.propertyOverrides(documentType: documentType, enabledOnly: enabledOnly);

  List<WmnClientScript> clientScripts({String? documentType, bool enabledOnly = false}) =>
      repository.clientScripts(documentType: documentType, enabledOnly: enabledOnly);

  List<WmnServerScript> serverScripts({String? documentType, String? eventName, bool enabledOnly = false}) =>
      repository.serverScripts(documentType: documentType, eventName: eventName, enabledOnly: enabledOnly);

  List<Map<String, Object?>> executionLogs({int limit = 200}) => repository.executionLogs(limit: limit);

  WmnCustomField saveCustomField({
    String? id,
    required String documentType,
    required String fieldName,
    required String label,
    required WmnCustomFieldType fieldType,
    String? insertAfter,
    List<String> options = const [],
    Object? defaultValue,
    bool required = false,
    bool readOnly = false,
    bool hidden = false,
    bool inListView = false,
    bool searchable = false,
    int sortOrder = 0,
    bool enabled = true,
  }) {
    _validateDocumentType(documentType);
    _validateCustomFieldName(documentType, fieldName, existingId: id);
    if (label.trim().isEmpty) throw StateError('Custom field label is required.');
    if (fieldType == WmnCustomFieldType.select && options.isEmpty) {
      throw StateError('Select custom fields require at least one option.');
    }
    final saved = repository.saveCustomField(
      id: id,
      documentType: documentType,
      fieldName: fieldName,
      label: label,
      fieldType: fieldType,
      insertAfter: insertAfter,
      options: options,
      defaultValue: defaultValue,
      required: required,
      readOnly: readOnly,
      hidden: hidden,
      inListView: inListView,
      searchable: searchable,
      sortOrder: sortOrder,
      enabled: enabled,
    );
    audit.record(
      entityType: 'Custom Field',
      entityId: saved.id,
      action: id == null ? 'CREATE' : 'UPDATE',
      payload: {'document_type': documentType, 'field_name': fieldName, 'field_type': fieldType.code},
    );
    return saved;
  }

  void deleteCustomField(String id) {
    repository.deleteCustomField(id);
    audit.record(entityType: 'Custom Field', entityId: id, action: 'DELETE');
  }

  WmnPropertyOverride savePropertyOverride({
    String? id,
    required String documentType,
    required String fieldName,
    required String propertyName,
    required Object? value,
    bool enabled = true,
  }) {
    _validateDocumentType(documentType);
    final knownCustomField = repository
        .customFields(documentType: documentType)
        .any((entry) => entry.fieldName == fieldName);
    if (!knownCustomField) {
      throw StateError(
        'Unknown custom field for property override: $fieldName',
      );
    }
    const allowed = {'label', 'required', 'read_only', 'hidden', 'default', 'options', 'in_list_view', 'searchable'};
    if (!allowed.contains(propertyName)) throw StateError('Unsupported property override: $propertyName');
    final saved = repository.savePropertyOverride(
      id: id,
      documentType: documentType,
      fieldName: fieldName,
      propertyName: propertyName,
      value: value,
      enabled: enabled,
    );
    audit.record(
      entityType: 'Property Override',
      entityId: saved.id,
      action: id == null ? 'CREATE' : 'UPDATE',
      payload: {'document_type': documentType, 'field_name': fieldName, 'property': propertyName},
    );
    return saved;
  }

  void deletePropertyOverride(String id) {
    repository.deletePropertyOverride(id);
    audit.record(entityType: 'Property Override', entityId: id, action: 'DELETE');
  }

  WmnClientScript saveClientScript({
    String? id,
    required String name,
    required String documentType,
    required String script,
    int priority = 0,
    bool enabled = true,
  }) {
    _validateDocumentType(documentType);
    scriptEngine.policy.validate(script);
    final saved = repository.saveClientScript(
      id: id,
      name: name,
      documentType: documentType,
      script: script,
      priority: priority,
      enabled: false,
    );
    audit.record(
      entityType: 'Client Script',
      entityId: saved.id,
      action: id == null ? 'CREATE' : 'UPDATE',
      payload: {'document_type': documentType, 'name': name, 'enabled': false, 'runtime': 'DEFERRED'},
    );
    return saved;
  }

  void deleteClientScript(String id) {
    repository.deleteClientScript(id);
    audit.record(entityType: 'Client Script', entityId: id, action: 'DELETE');
  }

  WmnServerScript saveServerScript({
    String? id,
    required String name,
    String scriptType = 'DOCUMENT_EVENT',
    String? documentType,
    String? eventName,
    String? apiMethod,
    required String script,
    int priority = 0,
    bool enabled = true,
  }) {
    if (scriptType == 'DOCUMENT_EVENT') {
      if (documentType == null || eventName == null) {
        throw StateError('Document Event server scripts require document type and event.');
      }
      _validateDocumentType(documentType);
    }
    scriptEngine.policy.validate(script);
    final saved = repository.saveServerScript(
      id: id,
      name: name,
      scriptType: scriptType,
      documentType: documentType,
      eventName: eventName,
      apiMethod: apiMethod,
      script: script,
      priority: priority,
      enabled: false,
    );
    audit.record(
      entityType: 'Server Script',
      entityId: saved.id,
      action: id == null ? 'CREATE' : 'UPDATE',
      payload: {
        'script_type': scriptType,
        'document_type': documentType,
        'event': eventName,
        'name': name,
        'enabled': false,
        'runtime': 'DEFERRED',
      },
    );
    return saved;
  }

  void deleteServerScript(String id) {
    repository.deleteServerScript(id);
    audit.record(entityType: 'Server Script', entityId: id, action: 'DELETE');
  }

  WmnFormCustomizationSnapshot formSnapshot({
    required String documentType,
    String? documentId,
  }) {
    final fields = _effectiveCustomFields(documentType);
    final persisted = documentId == null ? <String, Object?>{} : repository.customValues(documentType, documentId);
    final values = <String, Object?>{};
    for (final field in fields) {
      values[field.fieldName] = persisted.containsKey(field.fieldName) ? persisted[field.fieldName] : field.defaultValue;
    }
    return WmnFormCustomizationSnapshot(
      documentType: documentType,
      documentId: documentId,
      fields: fields,
      values: values,
      fieldProperties: _fieldProperties(documentType),
    );
  }

  void validateCustomValues(WmnFormCustomizationSnapshot snapshot, Map<String, Object?> values) {
    for (final field in snapshot.fields) {
      if (!field.enabled || field.hidden) continue;
      final properties = snapshot.fieldProperties[field.fieldName] ?? const <String, Object?>{};
      final required = _bool(properties['required'], field.required);
      if (!required) continue;
      final value = values[field.fieldName];
      if (value == null || (value is String && value.trim().isEmpty)) {
        throw StateError('${field.label} is required.');
      }
    }
  }

  void saveCustomValues(String documentType, String documentId, Map<String, Object?> values) {
    final allowed = repository
        .customFields(documentType: documentType, enabledOnly: true)
        .map((entry) => entry.fieldName)
        .toSet();
    final filtered = <String, Object?>{
      for (final entry in values.entries)
        if (allowed.contains(entry.key)) entry.key: entry.value,
    };
    repository.saveCustomValues(documentType, documentId, filtered);
  }

  Map<String, Object?> loadMergedDocument(String documentType, String documentId) {
    final standard = registry.readDocument(documentType, documentId) ?? <String, Object?>{'id': documentId};
    return {...standard, ...repository.customValues(documentType, documentId)};
  }

  /// Script definitions are preserved as metadata in the clean platform baseline,
  /// but arbitrary Client/Server Script execution is intentionally disabled.
  WmnScriptResult runClientScripts({
    required String documentType,
    required String eventName,
    String? fieldName,
    required Map<String, Object?> document,
    String? documentId,
  }) => WmnScriptResult(document: Map<String, Object?>.from(document));

  WmnScriptResult runServerScripts({
    required String documentType,
    required String eventName,
    required Map<String, Object?> document,
    String? documentId,
  }) => WmnScriptResult(document: Map<String, Object?>.from(document));

  WmnScriptResult runSavePipeline({
    required String documentType,
    required Map<String, Object?> document,
    String? documentId,
    bool includeClient = true,
  }) => WmnScriptResult(document: Map<String, Object?>.from(document));

  WmnScriptResult runAfterSave({
    required String documentType,
    required Map<String, Object?> document,
    required String documentId,
    bool includeClient = true,
  }) => WmnScriptResult(document: Map<String, Object?>.from(document));

  String clientScriptTemplate(String documentType) =>
      '// Client Script runtime is deferred in WMN R2.1 CLEAN PLATFORM.';

  String serverScriptTemplate() =>
      '// Server Script runtime is deferred in WMN R2.1 CLEAN PLATFORM.';

  List<WmnCustomField> _effectiveCustomFields(String documentType) {
    final fields = repository.customFields(documentType: documentType, enabledOnly: true);
    final overrides = _fieldProperties(documentType);
    return fields
        .map((field) {
          final props = overrides[field.fieldName] ?? const <String, Object?>{};
          return field.copyWith(
            label: props['label']?.toString(),
            options: props['options'] is List
                ? (props['options'] as List).map((entry) => '$entry').toList(growable: false)
                : null,
            defaultValue: props.containsKey('default') ? props['default'] : field.defaultValue,
            required: _bool(props['required'], field.required),
            readOnly: _bool(props['read_only'], field.readOnly),
            hidden: _bool(props['hidden'], field.hidden),
            inListView: _bool(props['in_list_view'], field.inListView),
            searchable: _bool(props['searchable'], field.searchable),
          );
        })
        .toList(growable: false);
  }

  Map<String, Map<String, Object?>> _fieldProperties(String documentType) {
    final result = <String, Map<String, Object?>>{};
    for (final override in repository.propertyOverrides(documentType: documentType, enabledOnly: true)) {
      result.putIfAbsent(override.fieldName, () => <String, Object?>{})[override.propertyName] = override.value;
    }
    return result;
  }

  bool _bool(Object? value, bool fallback) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      if (value.toLowerCase() == 'true' || value == '1') return true;
      if (value.toLowerCase() == 'false' || value == '0') return false;
    }
    return fallback;
  }

  void _validateDocumentType(String documentType) {
    if (documentTypes.contains(documentType)) return;
    throw StateError('Unknown or disabled document type: $documentType');
  }

  void _validateCustomFieldName(String documentType, String fieldName, {String? existingId}) {
    final normalized = fieldName.trim();
    if (!RegExp(r'^custom_[a-z][a-z0-9_]*$').hasMatch(normalized)) {
      throw StateError('Custom field names must use custom_ prefix and lowercase snake_case.');
    }
    if (registry.standardFields(documentType).contains(normalized)) {
      throw StateError('Custom field conflicts with a standard field: $normalized');
    }
    final duplicate = repository
        .customFields(documentType: documentType)
        .any((entry) => entry.fieldName == normalized && entry.id != existingId);
    if (duplicate) throw StateError('Custom field already exists: $normalized');
  }
}
