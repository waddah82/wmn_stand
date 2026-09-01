import 'dart:convert';

import '../../core/database/wmn_database.dart';
import '../meta/doctype_meta.dart';
import '../meta/meta_service.dart';

class WmnFrappeConversionResult {
  const WmnFrappeConversionResult({
    required this.doctype,
    required this.convertedFields,
    required this.warnings,
    required this.unsupportedFieldTypes,
  });

  final WmnDocTypeMeta doctype;
  final int convertedFields;
  final List<String> warnings;
  final Set<String> unsupportedFieldTypes;
}

class WmnFrappeAppConverter {
  WmnFrappeAppConverter({required this.database, required this.meta});

  final WmnDatabase database;
  final WmnMetaService meta;

  static const Map<String, String> _fieldTypeMap = {
    'Data': 'Data',
    'Autocomplete': 'Data',
    'Icon': 'Data',
    'Text': 'Text',
    'Small Text': 'Small Text',
    'Long Text': 'Long Text',
    'Text Editor': 'Text Editor',
    'Markdown Editor': 'Text Editor',
    'Code': 'Code',
    'HTML Editor': 'Text Editor',
    'Int': 'Int',
    'Float': 'Float',
    'Currency': 'Currency',
    'Percent': 'Percent',
    'Check': 'Check',
    'Select': 'Select',
    'Link': 'Link',
    'Dynamic Link': 'Dynamic Link',
    'Date': 'Date',
    'Datetime': 'Datetime',
    'Time': 'Time',
    'Duration': 'Duration',
    'Attach': 'Attach',
    'Attach Image': 'Attach Image',
    'Image': 'Image',
    'Signature': 'Attach Image',
    'Barcode': 'Barcode',
    'Rating': 'Rating',
    'Color': 'Color',
    'Geolocation': 'Geolocation',
    'JSON': 'JSON',
    'Password': 'Password',
    'Table': 'Table',
    'Table MultiSelect': 'Table MultiSelect',
    'Section Break': 'Section Break',
    'Column Break': 'Column Break',
    'Tab Break': 'Tab Break',
    'Heading': 'Heading',
    'HTML': 'HTML',
    'Button': 'Button',
    'Read Only': 'Read Only',
  };

  WmnFrappeConversionResult importDocTypeJson(
    String jsonText, {
    String? moduleOverride,
    String sourceApp = 'frappe_app',
  }) {
    final raw = Map<String, Object?>.from(jsonDecode(jsonText) as Map);
    final name = '${raw['name'] ?? ''}'.trim();
    if (name.isEmpty) throw StateError('Frappe DocType JSON has no name.');
    final module = moduleOverride?.trim().isNotEmpty == true ? moduleOverride!.trim() : '${raw['module'] ?? 'Custom'}';
    final titleField = _string(raw['title_field']);
    final autoname = _string(raw['autoname']);
    final isSingle = _truthy(raw['issingle']);
    final isChild = _truthy(raw['istable']);
    final isSubmittable = _truthy(raw['is_submittable']);
    final trackChanges = !_hasExplicitFalse(raw['track_changes']);
    meta.saveDocType(
      name: name,
      module: module,
      titleField: titleField,
      autoname: autoname,
      isSingle: isSingle,
      isChild: isChild,
      isSubmittable: isSubmittable,
      trackChanges: trackChanges,
      allowImport: !_hasExplicitFalse(raw['allow_import']),
      allowExport: true,
      metadata: {
        'source_framework': 'FRAPPE',
        'source_app': sourceApp,
        'original': raw,
      },
    );

    database.db.execute('DELETE FROM wmn_doctype_fields WHERE doctype = ?;', [name]);
    final warnings = <String>[];
    final unsupported = <String>{};
    final fields = raw['fields'] as List? ?? const [];
    final usedFieldNames = <String>{};
    var converted = 0;
    for (var index = 0; index < fields.length; index++) {
      final item = fields[index];
      if (item is! Map) continue;
      final field = Map<String, Object?>.from(item);
      final originalFieldName = '${field['fieldname'] ?? ''}'.trim();
      if (originalFieldName.isEmpty) continue;
      final fieldName = _safeFieldName(originalFieldName, index: index + 1, used: usedFieldNames);
      if (fieldName != originalFieldName) {
        warnings.add('$name.$originalFieldName: normalized to $fieldName for WMN identifier safety.');
      }
      usedFieldNames.add(fieldName);
      final frappeType = '${field['fieldtype'] ?? 'Data'}';
      final mappedType = _fieldTypeMap[frappeType];
      if (mappedType == null) {
        unsupported.add(frappeType);
        warnings.add('$fieldName: unsupported Frappe field type $frappeType; mapped to Data.');
      }
      meta.saveField(
        doctype: name,
        fieldName: fieldName,
        label: '${field['label'] ?? _humanize(fieldName)}',
        fieldType: mappedType ?? 'Data',
        options: _string(field['options']),
        index: (field['idx'] as num?)?.toInt() ?? index + 1,
        required: _truthy(field['reqd']),
        readOnly: _truthy(field['read_only']),
        hidden: _truthy(field['hidden']),
        inListView: _truthy(field['in_list_view']),
        inStandardFilter: _truthy(field['in_standard_filter']),
        searchable: _truthy(field['search_index']) || _truthy(field['in_global_search']),
        allowOnSubmit: _truthy(field['allow_on_submit']),
        defaultValue: field['default'],
        dependsOn: _string(field['depends_on']),
        mandatoryDependsOn: _string(field['mandatory_depends_on']),
        readOnlyDependsOn: _string(field['read_only_depends_on']),
        fetchFrom: _string(field['fetch_from']),
        precision: (field['precision'] as num?)?.toInt(),
        length: (field['length'] as num?)?.toInt(),
        validateReferences: false,
        metadata: {'frappe_field': field, if (fieldName != originalFieldName) 'frappe_fieldname': originalFieldName},
      );
      converted++;
    }

    _importPermissions(
      doctype: name,
      module: module,
      rawPermissions: raw['permissions'],
      warnings: warnings,
    );

    if (fields.isEmpty) warnings.add('DocType has no fields.');
    if (isChild) warnings.add('Child table metadata imported; parent Table field must also be imported for full behavior.');
    if (isSubmittable) warnings.add('Submit/Cancel UI metadata imported, but business submit hooks must be ported to WMN document lifecycle.');
    return WmnFrappeConversionResult(
      doctype: meta.doctype(name)!,
      convertedFields: converted,
      warnings: List.unmodifiable(warnings),
      unsupportedFieldTypes: Set.unmodifiable(unsupported),
    );
  }

  void registerApp({
    required String appName,
    String? title,
    String? version,
    String sourceFramework = 'FRAPPE',
    String? repository,
    String? sourceRef,
    String? license,
    List<String> modules = const [],
    Map<String, Object?> manifest = const {},
    String status = 'IMPORTED',
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO wmn_app_packages(
        app_name,app_title,app_version,source_framework,source_repository,source_ref,source_license,
        module_json,manifest_json,conversion_status,installed_at,updated_at
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(app_name) DO UPDATE SET
        app_title=excluded.app_title,app_version=excluded.app_version,source_framework=excluded.source_framework,
        source_repository=excluded.source_repository,source_ref=excluded.source_ref,source_license=excluded.source_license,
        module_json=excluded.module_json,manifest_json=excluded.manifest_json,conversion_status=excluded.conversion_status,
        updated_at=excluded.updated_at;
    ''', [
      appName,
      title,
      version,
      sourceFramework,
      repository,
      sourceRef,
      license,
      jsonEncode(modules),
      jsonEncode(manifest),
      status,
      now,
      now,
    ]);
    var sequence = 10.0;
    for (final module in modules.toSet()) {
      final normalized = module.trim();
      if (normalized.isEmpty) continue;
      database.db.execute('''
        INSERT INTO wmn_modules(name,label,app_name,sequence_id,enabled,metadata_json,created_at,updated_at)
        VALUES (?,?,?, ?,1,?,?,?)
        ON CONFLICT(name) DO UPDATE SET
          app_name=excluded.app_name,label=excluded.label,sequence_id=excluded.sequence_id,
          metadata_json=excluded.metadata_json,updated_at=excluded.updated_at;
      ''', [normalized, normalized, appName, sequence, jsonEncode({'source_framework': sourceFramework}), now, now]);
      sequence += 10;
    }
  }

  Map<String, Object?> compatibilitySummary() => {
        'frappe_concepts': {
          'DocType': 'wmn_doctypes + wmn_doctype_fields',
          'Document': 'WmnDocumentService',
          'Form': 'WmnFormView',
          'List': 'WmnListView',
          'Client Script': 'Preserved as disabled metadata; runtime deferred',
          'Server Script': 'Preserved as disabled metadata; runtime deferred',
          'Report Builder': 'WMN Report Builder',
          'Script Report': 'WmnScriptReportService; imported Python behavior requires an explicit native port',
          'Data Import': 'WmnDataExchangeService',
          'Data Export': 'WmnDataExchangeService',
          'Workspace': 'WmnWorkspaceService + WmnWorkspacePage',
          'Page': 'WmnPageService + WmnPageRuntimeView',
          'App Package': 'WmnFrappeAppPackageConverter',
          'Python / JS Source': 'WmnFrappeSourcePorter + Source Porting Workbench',
        },
        'not_automatic': [
          'critical Python controller behavior requiring WMN native engine mapping',
          'arbitrary SQL Query Reports',
          'hooks.py Python behavior (tracked as porting tasks)',
          'external Frappe/API integrations that require explicit WMN adapters',
        ],
      };

  void _importPermissions({
    required String doctype,
    required String module,
    required Object? rawPermissions,
    required List<String> warnings,
  }) {
    database.db.execute('DELETE FROM wmn_doctype_permissions WHERE doctype = ?;', [doctype]);
    if (rawPermissions is! List) return;
    for (final raw in rawPermissions.whereType<Map>()) {
      final permission = Map<String, Object?>.from(raw);
      final role = '${permission['role'] ?? ''}'.trim();
      if (role.isEmpty) continue;
      final permlevel = (permission['permlevel'] as num?)?.toInt() ?? int.tryParse('${permission['permlevel'] ?? 0}') ?? 0;
      final id = 'docperm-${_slug(doctype)}-${_slug(role)}-$permlevel';
      database.db.execute('''
        INSERT INTO wmn_doctype_permissions(
          id,doctype,role,permlevel,can_read,can_write,can_create,can_delete,can_submit,can_cancel,
          can_amend,can_report,can_import,can_export,can_share,can_print,can_email,if_owner,metadata_json
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(doctype,role,permlevel) DO UPDATE SET
          can_read=excluded.can_read,can_write=excluded.can_write,can_create=excluded.can_create,
          can_delete=excluded.can_delete,can_submit=excluded.can_submit,can_cancel=excluded.can_cancel,
          can_amend=excluded.can_amend,can_report=excluded.can_report,can_import=excluded.can_import,
          can_export=excluded.can_export,can_share=excluded.can_share,can_print=excluded.can_print,
          can_email=excluded.can_email,if_owner=excluded.if_owner,metadata_json=excluded.metadata_json;
      ''', [
        id, doctype, role, permlevel,
        _truthy(permission['read']) ? 1 : 0,
        _truthy(permission['write']) ? 1 : 0,
        _truthy(permission['create']) ? 1 : 0,
        _truthy(permission['delete']) ? 1 : 0,
        _truthy(permission['submit']) ? 1 : 0,
        _truthy(permission['cancel']) ? 1 : 0,
        _truthy(permission['amend']) ? 1 : 0,
        _truthy(permission['report']) ? 1 : 0,
        _truthy(permission['import']) ? 1 : 0,
        _truthy(permission['export']) ? 1 : 0,
        _truthy(permission['share']) ? 1 : 0,
        _truthy(permission['print']) ? 1 : 0,
        _truthy(permission['email']) ? 1 : 0,
        _truthy(permission['if_owner']) ? 1 : 0,
        jsonEncode(permission),
      ]);
      if (permlevel != 0 || _truthy(permission['if_owner'])) {
        warnings.add('$doctype permission for $role uses Frappe permlevel/if_owner semantics; metadata was preserved for WMN permission enforcement.');
      }
    }
  }

  String _safeFieldName(String value, {required int index, required Set<String> used}) {
    if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value) && !used.contains(value)) return value;
    var safe = value.replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_').replaceAll(RegExp(r'_+'), '_');
    safe = safe.replaceAll(RegExp(r'^_+|_+$'), '');
    if (safe.isEmpty) safe = 'field_$index';
    if (RegExp(r'^[0-9]').hasMatch(safe)) safe = 'field_$safe';
    var candidate = safe;
    var suffix = 2;
    while (used.contains(candidate)) {
      candidate = '${safe}_$suffix';
      suffix++;
    }
    return candidate;
  }

  String _slug(String value) {
    final slug = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'entry' : slug;
  }

  bool _truthy(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = '${value ?? ''}'.toLowerCase();
    return text == '1' || text == 'true' || text == 'yes';
  }

  bool _hasExplicitFalse(Object? value) => value == false || value == 0 || '${value ?? ''}'.toLowerCase() == 'false';
  String? _string(Object? value) => value == null || '$value'.trim().isEmpty ? null : '$value';
  String _humanize(String value) => value.split('_').map((entry) => entry.isEmpty ? entry : '${entry[0].toUpperCase()}${entry.substring(1)}').join(' ');
}
