import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/database/wmn_database.dart';
import '../../core/database/sql_identifier.dart';
import '../../core/documents/document_registry.dart';
import '../../modules/customization/data/customization_repository.dart';
import '../../modules/customization/domain/customization_models.dart';
import 'doctype_meta.dart';
import 'field_control_resolver.dart';
import 'field_options.dart';

class WmnMetaService {
  WmnMetaService({
    required this.database,
    required this.registry,
    required this.customization,
  });

  final WmnDatabase database;
  final WmnDocumentRegistry registry;
  final CustomizationRepository customization;
  static const Uuid _uuid = Uuid();

  List<WmnDocTypeMeta> doctypes({bool enabledOnly = true}) {
    final rows = database.db.select('''
      SELECT * FROM wmn_doctypes
      ${enabledOnly ? 'WHERE enabled = 1' : ''}
      ORDER BY module COLLATE NOCASE, name COLLATE NOCASE;
    ''');
    return rows.map((row) => _mapDocType(row, includeFields: false)).toList(growable: false);
  }

  WmnDocTypeMeta? doctype(String name, {bool includeFields = true}) {
    final rows = database.db.select('SELECT * FROM wmn_doctypes WHERE name = ? LIMIT 1;', [name]);
    if (rows.isEmpty) return null;
    return _mapDocType(rows.first, includeFields: includeFields);
  }

  List<WmnFieldMeta> fields(String doctype) {
    final metaRows = database.db.select('''
      SELECT * FROM wmn_doctype_fields
      WHERE doctype = ?
      ORDER BY idx, fieldname;
    ''', [doctype]);
    List<WmnFieldMeta> result;
    if (metaRows.isNotEmpty) {
      result = metaRows.map(_mapField).toList(growable: true);
    } else {
      final dt = doctypeMetaOnly(doctype);
      if (dt == null || dt.storageMode != WmnStorageMode.table || dt.tableName == null) return const [];
      result = _inferTableFields(dt).toList(growable: true);
    }

    if (_tableExists('custom_fields')) {
      final existing = result.map((entry) => entry.fieldName).toSet();
      for (final custom in customization.customFields(documentType: doctype, enabledOnly: true)) {
        if (existing.contains(custom.fieldName)) continue;
        result.add(_fromCustomField(custom, result.length + 1000));
      }
    }

    final overrides = _propertyOverrides(doctype);
    result = result.map((field) {
      final props = overrides[field.fieldName];
      if (props == null) return field;
      return field.copyWith(
        label: props['label']?.toString(),
        required: _bool(props['required'], field.required),
        readOnly: _bool(props['read_only'], field.readOnly),
        hidden: _bool(props['hidden'], field.hidden),
        inListView: _bool(props['in_list_view'], field.inListView),
        searchable: _bool(props['searchable'], field.searchable),
        defaultValue: props.containsKey('default') ? props['default'] : field.defaultValue,
        options: props['options'] is List ? (props['options'] as List).join('\n') : props['options']?.toString(),
      );
    }).toList(growable: true);

    // Field names are the identity used by forms, lists, filters and dropdowns.
    // Keep one effective field per name even when an upgraded/customized database
    // contains overlapping metadata from an older source.
    final uniqueByName = <String, WmnFieldMeta>{};
    for (final field in result) {
      uniqueByName.putIfAbsent(field.fieldName, () => field);
    }
    result = uniqueByName.values.toList(growable: true);

    result.sort((a, b) {
      final byIndex = a.index.compareTo(b.index);
      return byIndex != 0 ? byIndex : a.fieldName.compareTo(b.fieldName);
    });
    return result;
  }

  WmnDocTypeMeta? doctypeMetaOnly(String name) {
    final rows = database.db.select('SELECT * FROM wmn_doctypes WHERE name = ? LIMIT 1;', [name]);
    return rows.isEmpty ? null : _mapDocType(rows.first, includeFields: false);
  }

  WmnListViewSettings listViewSettings(String doctype) {
    final meta = this.doctype(doctype);
    if (meta == null) return const WmnListViewSettings();
    final sortableNames = meta.fields
        .where((field) => !field.hidden && !field.isLayout && !const {'Table', 'Table MultiSelect'}.contains(field.fieldType))
        .map((field) => field.fieldName)
        .toSet();

    final rows = database.db.select('SELECT settings_json FROM wmn_list_view_settings WHERE doctype = ? LIMIT 1;', [doctype]);
    if (rows.isNotEmpty) {
      try {
        final stored = WmnListViewSettings.fromJson(
          Map<String, Object?>.from(jsonDecode(rows.first['settings_json'] as String) as Map),
        );
        final effectiveSort = stored.sortField != null && sortableNames.contains(stored.sortField)
            ? stored.sortField
            : _defaultSortField(meta);
        return WmnListViewSettings(
          fields: stored.fields,
          searchFields: stored.searchFields,
          defaultFilters: stored.defaultFilters,
          sortField: effectiveSort,
          sortDescending: stored.sortDescending,
          pageSize: stored.pageSize,
          hideNameColumn: stored.hideNameColumn,
          layout: stored.layout,
        );
      } catch (_) {}
    }
    final fields = meta.listFields.map((entry) => entry.fieldName).toList(growable: false);
    final searchFields = meta.fields
        .where((entry) => entry.searchable || entry.inListView)
        .where((entry) => !entry.hidden && !entry.isLayout)
        .map((entry) => entry.fieldName)
        .take(8)
        .toList(growable: false);
    final defaultSort = _defaultSortField(meta);
    return WmnListViewSettings(
      fields: fields,
      searchFields: searchFields,
      sortField: defaultSort,
      sortDescending: defaultSort?.contains('modified') == true || defaultSort?.contains('updated') == true,
      pageSize: 20,
      layout: 'TABLE',
    );
  }

  void saveListViewSettings(String doctype, WmnListViewSettings settings) {
    if (this.doctype(doctype, includeFields: false) == null) throw StateError('Unknown DocType: $doctype');
    database.db.execute('''
      INSERT INTO wmn_list_view_settings(doctype, settings_json, updated_at)
      VALUES (?, ?, ?)
      ON CONFLICT(doctype) DO UPDATE SET
        settings_json = excluded.settings_json,
        updated_at = excluded.updated_at;
    ''', [doctype, settings.encode(), DateTime.now().toUtc().toIso8601String()]);
  }

  List<String> modules({bool enabledOnly = true}) {
    final result = <String>{'Custom'};
    if (_tableExists('wmn_modules')) {
      final rows = database.db.select('''
        SELECT name FROM wmn_modules
        ${enabledOnly ? 'WHERE enabled = 1' : ''}
        ORDER BY sequence_id, label COLLATE NOCASE, name COLLATE NOCASE;
      ''');
      result.addAll(rows.map((row) => '${row['name']}'.trim()).where((value) => value.isNotEmpty));
    }
    if (_tableExists('wmn_doctypes')) {
      result.addAll(
        database.db
            .select("SELECT DISTINCT module FROM wmn_doctypes WHERE module IS NOT NULL AND trim(module) <> '' ORDER BY module COLLATE NOCASE;")
            .map((row) => '${row['module']}'.trim())
            .where((value) => value.isNotEmpty),
      );
    }
    final rows = result.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return rows;
  }

  void saveModule({
    required String name,
    String? label,
    bool enabled = true,
  }) {
    final normalized = name.trim();
    if (normalized.isEmpty) throw StateError('Module name is required.');
    if (!_tableExists('wmn_modules')) {
      throw StateError('Module registry is not installed.');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final sequenceRows = database.db.select('SELECT COALESCE(MAX(sequence_id), 0) + 10 AS value FROM wmn_modules;');
    final sequence = (sequenceRows.first['value'] as num?)?.toDouble() ?? 10;
    database.db.execute('''
      INSERT INTO wmn_modules(name,label,app_name,sequence_id,enabled,metadata_json,created_at,updated_at)
      VALUES (?,?,NULL,?,?,'{"source_framework":"WMN","managed_by":"DocType Studio"}',?,?)
      ON CONFLICT(name) DO UPDATE SET
        label=excluded.label, enabled=excluded.enabled, updated_at=excluded.updated_at;
    ''', [normalized, (label?.trim().isNotEmpty == true ? label!.trim() : normalized), sequence, enabled ? 1 : 0, now, now]);
  }

  WmnDocTypeMeta saveDocType({
    required String name,
    String module = 'Custom',
    String? titleField,
    String? autoname,
    bool isSingle = false,
    bool isChild = false,
    bool isSubmittable = false,
    bool trackChanges = true,
    bool allowCreate = true,
    bool allowEdit = true,
    bool allowDelete = true,
    bool allowImport = true,
    bool allowExport = true,
    bool genericWrite = true,
    bool enabled = true,
    Map<String, Object?> metadata = const {},
  }) {
    final normalized = name.trim();
    if (normalized.isEmpty) throw StateError('DocType name is required.');
    final normalizedModule = module.trim().isEmpty ? 'Custom' : module.trim();
    if (_tableExists('wmn_modules') && !modules(enabledOnly: false).contains(normalizedModule)) {
      saveModule(name: normalizedModule);
    }
    final existing = doctype(normalized, includeFields: false);
    if (existing != null && existing.isSingle != isSingle) {
      throw StateError('Changing Single DocType storage mode requires an explicit schema/data migration.');
    }

    // Frappe rule: Single DocTypes have one logical record, are not child
    // tables, are not submittable, and are not importable. Their values live
    // in tabSingles rather than a dedicated tab<DocType> table.
    final effectiveIsSingle = isSingle;
    final effectiveIsChild = effectiveIsSingle ? false : isChild;
    final effectiveIsSubmittable = (effectiveIsSingle || effectiveIsChild) ? false : isSubmittable;
    final effectiveAllowImport = (effectiveIsSingle || effectiveIsChild) ? false : allowImport;
    _validateAutonameSyntax(normalized, autoname);
    final tableName = effectiveIsSingle ? 'tabSingles' : frappeTableName(normalized);
    if (effectiveIsSingle) {
      _ensureSinglesTable();
    } else {
      _ensureDocTypeTable(tableName);
    }
    final physicalIdField = effectiveIsSingle ? 'name' : _physicalIdField(tableName);
    final now = DateTime.now().toUtc().toIso8601String();
    final storedMetadata = <String, Object?>{
      ...metadata,
      'wmn_physical_storage': effectiveIsSingle ? 'FRAPPE_TAB_SINGLES' : 'FRAPPE_TAB_TABLE',
    };
    database.db.execute('''
      INSERT INTO wmn_doctypes(
        name,module,storage_mode,table_name,id_field,title_field,autoname,is_single,is_child,is_submittable,
        track_changes,allow_create,allow_edit,allow_delete,allow_import,allow_export,generic_write,
        is_system,enabled,metadata_json,created_at,updated_at
      ) VALUES (?,?,'TABLE',?,?,?,?,?,?,?,?,?,?,?,?,?,?,0,?,?,?,?)
      ON CONFLICT(name) DO UPDATE SET
        module=excluded.module,storage_mode='TABLE',table_name=excluded.table_name,id_field=excluded.id_field,
        title_field=excluded.title_field,autoname=excluded.autoname,is_single=excluded.is_single,
        is_child=excluded.is_child,is_submittable=excluded.is_submittable,track_changes=excluded.track_changes,
        allow_create=excluded.allow_create,allow_edit=excluded.allow_edit,allow_delete=excluded.allow_delete,
        allow_import=excluded.allow_import,allow_export=excluded.allow_export,generic_write=excluded.generic_write,
        enabled=excluded.enabled,metadata_json=excluded.metadata_json,updated_at=excluded.updated_at;
    ''', [
      normalized,
      normalizedModule,
      tableName,
      physicalIdField,
      titleField?.trim().isEmpty == true ? null : titleField?.trim(),
      autoname?.trim().isEmpty == true ? null : autoname?.trim(),
      effectiveIsSingle ? 1 : 0,
      effectiveIsChild ? 1 : 0,
      effectiveIsSubmittable ? 1 : 0,
      trackChanges ? 1 : 0,
      allowCreate ? 1 : 0,
      allowEdit ? 1 : 0,
      allowDelete ? 1 : 0,
      effectiveAllowImport ? 1 : 0,
      allowExport ? 1 : 0,
      genericWrite ? 1 : 0,
      enabled ? 1 : 0,
      jsonEncode(storedMetadata),
      now,
      now,
    ]);
    return doctype(normalized)!;
  }

  WmnFieldMeta saveField({
    String? id,
    required String doctype,
    required String fieldName,
    required String label,
    required String fieldType,
    String? options,
    int index = 0,
    bool required = false,
    bool readOnly = false,
    bool hidden = false,
    bool inListView = false,
    bool inStandardFilter = false,
    bool searchable = false,
    bool allowOnSubmit = false,
    Object? defaultValue,
    String? dependsOn,
    String? mandatoryDependsOn,
    String? readOnlyDependsOn,
    String? fetchFrom,
    int? precision,
    int? length,
    bool validateReferences = true,
    Map<String, Object?> metadata = const {},
  }) {
    final dt = this.doctype(doctype, includeFields: false);
    if (dt == null) throw StateError('Unknown DocType: $doctype');
    final normalized = fieldName.trim();
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(normalized)) {
      throw StateError('Invalid field name: $normalized');
    }
    _validateFieldDefinition(
      doctype: doctype,
      fieldName: normalized,
      fieldType: fieldType,
      options: options,
      required: required,
      hidden: hidden,
      inListView: inListView,
      defaultValue: defaultValue,
      precision: precision,
      metadata: metadata,
    );
    final existingRows = database.db.select(
      'SELECT fieldtype FROM wmn_doctype_fields WHERE doctype = ? AND fieldname = ? LIMIT 1;',
      [doctype, normalized],
    );
    if (existingRows.isNotEmpty) {
      final oldType = existingRows.first['fieldtype'] as String;
      if (_sqlType(oldType) != _sqlType(fieldType)) {
        throw StateError('Changing $doctype.$normalized from $oldType to $fieldType changes its physical SQL type. Create a migration instead of mutating stored data.');
      }
    }
    if (validateReferences) {
      final renderAs = '${metadata['render_as'] ?? ''}'.trim().replaceAll(' ', '_').toUpperCase();
      final metadataTarget = '${metadata['link_target'] ?? ''}'.trim();
      final target = metadataTarget.isNotEmpty ? metadataTarget : options?.trim();
      if (fieldType == 'Link' || renderAs == 'LINK') {
        if (target == null || target.isEmpty) throw StateError('Link field $doctype.$normalized requires a target DocType in Options.');
        if (this.doctype(target, includeFields: false) == null) {
          throw StateError('Link field $doctype.$normalized references unknown DocType: $target');
        }
      }
      if (const {'Table', 'Table MultiSelect'}.contains(fieldType)) {
        if (target == null || target.isEmpty) throw StateError('Table field $doctype.$normalized requires a Child DocType in Options.');
        final child = this.doctype(target, includeFields: false);
        if (child == null) throw StateError('Table field $doctype.$normalized references unknown DocType: $target');
        if (!child.isChild) throw StateError('Table field $doctype.$normalized must reference a Child DocType.');
      }
      if (fieldType == 'Dynamic Link' || renderAs == 'DYNAMIC_LINK') {
        if (target == null || target.isEmpty) throw StateError('Dynamic Link field $doctype.$normalized requires the target-DocType fieldname in Options.');
        if (target == normalized) throw StateError('Dynamic Link field $doctype.$normalized cannot target itself.');
        final targetField = _findField(doctype, target);
        if (targetField == null) throw StateError('Dynamic Link field $doctype.$normalized references missing field: $target');
        final pointerControl = WmnFieldControlResolver.resolve(
          targetField,
          doctypeExists: (name) => this.doctype(name, includeFields: false) != null,
        );
        final validPointer = pointerControl.type == WmnFieldControlType.select ||
            (pointerControl.type == WmnFieldControlType.link && pointerControl.targetDoctype == 'DocType');
        if (!validPointer) {
          throw StateError('Dynamic Link target $doctype.$target must resolve to Select or Link with target DocType.');
        }
      }
      _validateFetchFrom(doctype, normalized, fetchFrom);
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final fieldId = id ?? _uuid.v4();
    database.db.execute('''
      INSERT INTO wmn_doctype_fields(
        id,doctype,fieldname,label,fieldtype,options,idx,reqd,read_only,hidden,in_list_view,
        in_standard_filter,searchable,allow_on_submit,default_json,depends_on,mandatory_depends_on,
        read_only_depends_on,fetch_from,precision,length,metadata_json,created_at,updated_at
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(doctype,fieldname) DO UPDATE SET
        label=excluded.label,fieldtype=excluded.fieldtype,options=excluded.options,idx=excluded.idx,
        reqd=excluded.reqd,read_only=excluded.read_only,hidden=excluded.hidden,in_list_view=excluded.in_list_view,
        in_standard_filter=excluded.in_standard_filter,searchable=excluded.searchable,
        allow_on_submit=excluded.allow_on_submit,default_json=excluded.default_json,depends_on=excluded.depends_on,
        mandatory_depends_on=excluded.mandatory_depends_on,read_only_depends_on=excluded.read_only_depends_on,
        fetch_from=excluded.fetch_from,precision=excluded.precision,length=excluded.length,
        metadata_json=excluded.metadata_json,updated_at=excluded.updated_at;
    ''', [
      fieldId,
      doctype,
      normalized,
      label.trim().isEmpty ? _humanize(normalized) : label.trim(),
      fieldType,
      options,
      index,
      required ? 1 : 0,
      readOnly ? 1 : 0,
      hidden ? 1 : 0,
      inListView ? 1 : 0,
      inStandardFilter ? 1 : 0,
      searchable ? 1 : 0,
      allowOnSubmit ? 1 : 0,
      defaultValue == null ? null : jsonEncode(defaultValue),
      dependsOn,
      mandatoryDependsOn,
      readOnlyDependsOn,
      fetchFrom,
      precision,
      length,
      jsonEncode(metadata),
      now,
      now,
    ]);
    if (!dt.isSingle && dt.storageMode == WmnStorageMode.table && dt.tableName != null) {
      _ensureDocTypeField(dt.tableName!, normalized, fieldType);
    }
    return fields(doctype).firstWhere((entry) => entry.fieldName == normalized);
  }

  void deleteField(String doctype, String fieldName) {
    final dt = this.doctype(doctype, includeFields: false);
    if (dt == null) throw StateError('Unknown DocType: $doctype');
    if (dt.isSystem || !dt.genericWrite || (!dt.isSingle && dt.tableName != frappeTableName(dt.name))) {
      throw StateError('Only custom/imported DocType fields can be deleted from DocType Manager.');
    }
    final normalized = fieldName.trim();
    const protectedFields = {
      'name', 'owner', 'creation', 'modified', 'modified_by', 'docstatus', 'idx',
      'parent', 'parentfield', 'parenttype',
    };
    if (protectedFields.contains(normalized)) throw StateError('$normalized is a standard Frappe field and cannot be deleted.');
    if (dt.titleField == normalized) throw StateError('$normalized is the DocType title field. Select another title field first.');
    if (dt.autoname == 'field:$normalized') throw StateError('$normalized is used by autoname. Change autoname first.');
    final dependencies = fieldReferences(doctype, normalized);
    if (dependencies.isNotEmpty) {
      throw StateError('$doctype.$normalized is still referenced by: ${dependencies.join(', ')}');
    }

    final rows = database.db.select(
      'SELECT fieldtype FROM wmn_doctype_fields WHERE doctype = ? AND fieldname = ? LIMIT 1;',
      [doctype, normalized],
    );
    if (rows.isEmpty) throw StateError('Unknown field: $doctype.$normalized');
    final fieldType = rows.first['fieldtype'] as String;
    final table = quoteSqlIdentifier(dt.tableName!);
    final columns = dt.isSingle
        ? const <String>{}
        : database.db.select('PRAGMA table_info($table);').map((row) => row['name'] as String).toSet();

    database.transaction(() {
      if (dt.isSingle) {
        database.db.execute('DELETE FROM [tabSingles] WHERE doctype = ? AND field = ?;', [doctype, normalized]);
      } else if (!const {'Section Break', 'Column Break', 'Tab Break', 'Table', 'Table MultiSelect'}.contains(fieldType) && columns.contains(normalized)) {
        database.db.execute('ALTER TABLE $table DROP COLUMN ${quoteSqlIdentifier(normalized)};');
      }
      database.db.execute('DELETE FROM wmn_doctype_fields WHERE doctype = ? AND fieldname = ?;', [doctype, normalized]);
      if (_tableExists('custom_field_values')) {
        database.db.execute(
          'DELETE FROM custom_field_values WHERE document_type = ? AND field_name = ?;',
          [doctype, normalized],
        );
      }
    });
  }

  void reorderFields(String doctype, List<String> orderedFieldNames) {
    final dt = this.doctype(doctype, includeFields: false);
    if (dt == null) throw StateError('Unknown DocType: $doctype');
    if (dt.isSystem || !dt.genericWrite) {
      throw StateError('System DocType field order is managed by source metadata/customization.');
    }
    database.transaction(() {
      var index = 0;
      final now = DateTime.now().toUtc().toIso8601String();
      for (final fieldName in orderedFieldNames) {
        index++;
        database.db.execute(
          'UPDATE wmn_doctype_fields SET idx = ?, updated_at = ? WHERE doctype = ? AND fieldname = ?;',
          [index, now, doctype, fieldName],
        );
      }
    });
  }

  List<String> doctypeReferences(String name) {
    final result = <String>[];
    for (final sourceBase in doctypes(enabledOnly: false)) {
      if (sourceBase.name == name) continue;
      final source = doctype(sourceBase.name);
      if (source == null) continue;
      for (final field in source.fields) {
        if (const {'Table', 'Table MultiSelect'}.contains(field.fieldType) &&
            field.options?.trim() == name) {
          result.add('${source.name}.${field.fieldName} (${field.fieldType})');
          continue;
        }
        final control = _effectiveControl(field);
        if (control.type == WmnFieldControlType.link && control.targetDoctype == name) {
          result.add('${source.name}.${field.fieldName} (Link)');
        }
      }
    }
    return result.toSet().toList()..sort();
  }

  void deleteDocType(String name) {
    final dt = doctype(name, includeFields: false);
    if (dt == null) return;
    if (dt.isSystem || !dt.genericWrite || (!dt.isSingle && dt.tableName != frappeTableName(dt.name))) {
      throw StateError('Only custom/imported DocTypes can be deleted.');
    }
    final references = doctypeReferences(name);
    if (references.isNotEmpty) {
      throw StateError('DocType $name is still referenced by: ${references.join(', ')}');
    }
    database.transaction(() {
      if (dt.isSingle) {
        database.db.execute('DELETE FROM [tabSingles] WHERE doctype = ?;', [name]);
      } else {
        database.db.execute('DROP TABLE IF EXISTS ${quoteSqlIdentifier(dt.tableName!)};');
      }
      database.db.execute('DELETE FROM wmn_list_view_settings WHERE doctype = ?;', [name]);
      if (_tableExists('custom_field_values')) {
        database.db.execute('DELETE FROM custom_field_values WHERE document_type = ?;', [name]);
      }
      database.db.execute('DELETE FROM wmn_doctypes WHERE name = ?;', [name]);
    });
  }

  List<String> fieldReferences(String doctype, String fieldName) {
    final result = <String>[];
    final dt = this.doctype(doctype);
    if (dt == null) return result;
    for (final field in dt.fields) {
      if (field.fieldName == fieldName) continue;
      final control = _effectiveControl(field);
      if (control.type == WmnFieldControlType.dynamicLink && field.options?.trim() == fieldName) {
        result.add('${field.fieldName}.options');
      }
      if (field.fetchFrom?.trim().startsWith('$fieldName.') == true) {
        result.add('${field.fieldName}.fetch_from');
      }
      for (final entry in <String?>[field.dependsOn, field.mandatoryDependsOn, field.readOnlyDependsOn]) {
        if (_expressionReferencesField(entry, fieldName)) {
          result.add('${field.fieldName}.condition');
          break;
        }
      }
    }
    return result.toSet().toList()..sort();
  }

  bool _expressionReferencesField(String? expression, String fieldName) {
    final source = expression ?? '';
    if (source.isEmpty) return false;
    return source.contains('doc.$fieldName') ||
        source.contains("doc['$fieldName']") ||
        source.contains('doc["$fieldName"]') ||
        RegExp('(^|[^A-Za-z0-9_])${RegExp.escape(fieldName)}([^A-Za-z0-9_]|\$)').hasMatch(source);
  }

  void validateDocTypeDefinition(String doctype) {
    final dt = this.doctype(doctype);
    if (dt == null) throw StateError('Unknown DocType: $doctype');
    final names = dt.fields.map((field) => field.fieldName).toSet();
    final titleField = dt.titleField?.trim();
    if (titleField != null && titleField.isNotEmpty && !names.contains(titleField)) {
      throw StateError('Title Field $doctype.$titleField does not exist.');
    }
    final autoname = dt.autoname?.trim();
    if (autoname != null && autoname.startsWith('field:')) {
      final field = autoname.substring(6).trim();
      if (field.isEmpty || !names.contains(field)) throw StateError('Autoname field $doctype.$field does not exist.');
    }
    for (final field in dt.fields) {
      final options = field.options?.trim();
      final control = _effectiveControl(field);
      if (control.type == WmnFieldControlType.link) {
        final target = control.targetDoctype;
        if (target == null || target.isEmpty || this.doctype(target, includeFields: false) == null) {
          throw StateError(
            'Link field $doctype.${field.fieldName} has an invalid target DocType: ${target ?? options ?? ''}',
          );
        }
      }
      if (const {'Table', 'Table MultiSelect'}.contains(field.fieldType)) {
        final child = options == null || options.isEmpty ? null : this.doctype(options, includeFields: false);
        if (child == null || !child.isChild) {
          throw StateError('Table field $doctype.${field.fieldName} must reference a Child DocType.');
        }
      }
      if (control.type == WmnFieldControlType.dynamicLink) {
        if (options == null || options.isEmpty || !names.contains(options)) {
          throw StateError('Dynamic Link field $doctype.${field.fieldName} references missing target field: ${options ?? ''}');
        }
        final pointer = dt.field(options);
        final pointerControl = pointer == null ? null : _effectiveControl(pointer);
        final validPointer = pointerControl?.type == WmnFieldControlType.select ||
            (pointerControl?.type == WmnFieldControlType.link &&
                pointerControl?.targetDoctype == 'DocType');
        if (!validPointer) {
          throw StateError(
            'Dynamic Link field $doctype.${field.fieldName} must point to Select or Link with target DocType.',
          );
        }
      }
      _validateFetchFrom(doctype, field.fieldName, field.fetchFrom);
    }
  }

  void _validateAutonameSyntax(String doctype, String? autoname) {
    final rule = autoname?.trim();
    if (rule == null || rule.isEmpty) return;
    if (rule.startsWith('field:') && rule.substring('field:'.length).trim().isEmpty) {
      throw StateError('Autoname for $doctype requires a field after field:.');
    }
    if (rule.startsWith('format:') && rule.substring('format:'.length).trim().isEmpty) {
      throw StateError('Autoname format for $doctype cannot be empty.');
    }
    if (rule.startsWith('naming_series:') && rule.substring('naming_series:'.length).trim().isEmpty) {
      throw StateError('Naming Series for $doctype requires a fallback pattern.');
    }
  }

  void _validateFieldDefinition({
    required String doctype,
    required String fieldName,
    required String fieldType,
    required String? options,
    required bool required,
    required bool hidden,
    required bool inListView,
    required Object? defaultValue,
    required int? precision,
    required Map<String, Object?> metadata,
  }) {
    final renderAs = '${metadata['render_as'] ?? ''}'.trim().replaceAll(' ', '_').toUpperCase();
    const supportedRenderAs = <String>{
      '', 'AUTO', 'TEXT', 'SELECT', 'LINK', 'DYNAMIC_LINK', 'CHECKBOX', 'CHECK',
      'NUMBER', 'MULTILINE', 'TEXTAREA', 'DATE', 'DATETIME', 'TIME',
    };
    if (!supportedRenderAs.contains(renderAs)) {
      throw StateError('Unsupported Render As for $doctype.$fieldName: $renderAs');
    }
    const supported = <String>{
      'Data', 'Small Text', 'Long Text', 'Text', 'Text Editor', 'Code', 'HTML', 'JSON',
      'Int', 'Float', 'Currency', 'Percent', 'Duration', 'Check', 'Select', 'Link',
      'Dynamic Link', 'Date', 'Datetime', 'Time', 'Table', 'Table MultiSelect',
      'Section Break', 'Column Break', 'Tab Break', 'Read Only',
    };
    if (!supported.contains(fieldType)) throw StateError('Unsupported field type for $doctype.$fieldName: $fieldType');
    const layout = {'Section Break', 'Column Break', 'Tab Break'};
    if (layout.contains(fieldType) && required) {
      throw StateError('$doctype.$fieldName of type $fieldType cannot be mandatory.');
    }
    if (hidden && required && defaultValue == null) {
      throw StateError('$doctype.$fieldName cannot be hidden and mandatory without a default.');
    }
    if (inListView && const {'Section Break', 'Column Break', 'Tab Break', 'Table', 'Table MultiSelect', 'HTML'}.contains(fieldType)) {
      throw StateError('$doctype.$fieldName of type $fieldType cannot be shown directly in List View.');
    }
    if (fieldType == 'Check' && defaultValue != null) {
      final text = '$defaultValue'.trim().toLowerCase();
      if (!const {'0', '1', 'false', 'true'}.contains(text)) {
        throw StateError('The default value for Check field $doctype.$fieldName must be 0 or 1.');
      }
    }
    final normalizedOptions = WmnFieldOptions.normalize(options);
    final effectiveSelect = fieldType == 'Select' || renderAs == 'SELECT' ||
        (fieldType == 'Data' && (renderAs.isEmpty || renderAs == 'AUTO') && normalizedOptions.length > 1);
    if (effectiveSelect && defaultValue != null && '$defaultValue'.isNotEmpty) {
      final values = normalizedOptions.toSet();
      if (values.isEmpty || !values.contains('$defaultValue')) {
        throw StateError('Default value for Select field $doctype.$fieldName must be one of its Options.');
      }
    }
    if (precision != null && const {'Currency', 'Float', 'Percent'}.contains(fieldType) && (precision < 1 || precision > 6)) {
      throw StateError('Precision for $doctype.$fieldName must be between 1 and 6.');
    }
  }

  void _validateFetchFrom(String doctype, String fieldName, String? fetchFrom) {
    final source = fetchFrom?.trim();
    if (source == null || source.isEmpty) return;
    final dot = source.indexOf('.');
    if (dot <= 0 || dot >= source.length - 1) {
      throw StateError('Fetch From for $doctype.$fieldName must use link_field.target_field.');
    }
    final linkFieldName = source.substring(0, dot).trim();
    final targetFieldName = source.substring(dot + 1).trim();
    final linkField = _findField(doctype, linkFieldName);
    if (linkField == null) {
      throw StateError('Fetch From for $doctype.$fieldName references missing field: $linkFieldName');
    }
    final control = WmnFieldControlResolver.resolve(
      linkField,
      doctypeExists: (name) => this.doctype(name, includeFields: false) != null,
    );
    if (control.type != WmnFieldControlType.link && control.type != WmnFieldControlType.dynamicLink) {
      throw StateError('Fetch From for $doctype.$fieldName references non-Link field: $linkFieldName');
    }
    if (control.type == WmnFieldControlType.link) {
      final targetDoctype = control.targetDoctype;
      if (targetDoctype == null || targetDoctype.isEmpty) return;
      final targetMeta = this.doctype(targetDoctype);
      if (targetMeta != null && targetMeta.field(targetFieldName) == null && targetFieldName != 'name') {
        throw StateError('Fetch From for $doctype.$fieldName references missing $targetDoctype.$targetFieldName');
      }
    }
  }

  WmnFieldMeta? _findField(String doctype, String fieldName) {
    for (final field in fields(doctype)) {
      if (field.fieldName == fieldName) return field;
    }
    return null;
  }

  WmnFieldControlResolution _effectiveControl(WmnFieldMeta field) =>
      WmnFieldControlResolver.resolve(
        field,
        doctypeExists: (name) => doctype(name, includeFields: false) != null,
      );

  WmnDocTypeMeta _mapDocType(dynamic row, {required bool includeFields}) {
    final name = row['name'] as String;
    return WmnDocTypeMeta(
      name: name,
      module: row['module'] as String,
      storageMode: row['storage_mode'] == 'TABLE' ? WmnStorageMode.table : WmnStorageMode.dynamic,
      tableName: row['table_name'] as String?,
      idField: row['id_field'] as String? ?? 'id',
      titleField: row['title_field'] as String?,
      autoname: row['autoname'] as String?,
      isSingle: (row['is_single'] as int? ?? 0) == 1,
      isChild: (row['is_child'] as int? ?? 0) == 1,
      isSubmittable: (row['is_submittable'] as int? ?? 0) == 1,
      trackChanges: (row['track_changes'] as int? ?? 1) == 1,
      allowCreate: (row['allow_create'] as int? ?? 1) == 1,
      allowEdit: (row['allow_edit'] as int? ?? 1) == 1,
      allowDelete: (row['allow_delete'] as int? ?? 1) == 1,
      allowImport: (row['allow_import'] as int? ?? 1) == 1,
      allowExport: (row['allow_export'] as int? ?? 1) == 1,
      genericWrite: (row['generic_write'] as int? ?? 1) == 1,
      isSystem: (row['is_system'] as int? ?? 0) == 1,
      enabled: (row['enabled'] as int? ?? 1) == 1,
      fields: includeFields ? fields(name) : const [],
      metadata: _jsonMap(row['metadata_json']),
    );
  }

  WmnFieldMeta _mapField(dynamic row) => WmnFieldMeta(
        fieldName: row['fieldname'] as String,
        label: row['label'] as String,
        fieldType: row['fieldtype'] as String,
        options: row['options'] as String?,
        index: row['idx'] as int? ?? 0,
        required: (row['reqd'] as int? ?? 0) == 1,
        readOnly: (row['read_only'] as int? ?? 0) == 1,
        hidden: (row['hidden'] as int? ?? 0) == 1,
        inListView: (row['in_list_view'] as int? ?? 0) == 1,
        inStandardFilter: (row['in_standard_filter'] as int? ?? 0) == 1,
        searchable: (row['searchable'] as int? ?? 0) == 1,
        allowOnSubmit: (row['allow_on_submit'] as int? ?? 0) == 1,
        defaultValue: _decodeJson(row['default_json']),
        dependsOn: row['depends_on'] as String?,
        mandatoryDependsOn: row['mandatory_depends_on'] as String?,
        readOnlyDependsOn: row['read_only_depends_on'] as String?,
        fetchFrom: row['fetch_from'] as String?,
        precision: row['precision'] as int?,
        length: row['length'] as int?,
        metadata: _jsonMap(row['metadata_json']),
      );

  Iterable<WmnFieldMeta> _inferTableFields(WmnDocTypeMeta meta) sync* {
    final table = meta.tableName!;
    final rows = database.db.select('PRAGMA table_info(${quoteSqlIdentifier(table)});');
    var index = 0;
    for (final row in rows) {
      index++;
      final name = row['name'] as String;
      if (_sensitive(name)) continue;
      final type = '${row['type'] ?? 'TEXT'}'.toUpperCase();
      final pk = (row['pk'] as int? ?? 0) == 1;
      final notNull = (row['notnull'] as int? ?? 0) == 1;
      final fieldType = _inferFieldType(name, type);
      final isSystem = const {'created_at', 'updated_at', 'creation', 'modified', 'owner', 'modified_by'}.contains(name);
      final likelyList = index <= 6 && !isSystem;
      yield WmnFieldMeta(
        fieldName: name,
        label: _humanize(name),
        fieldType: fieldType,
        options: fieldType == 'Link' ? _inferLinkTarget(meta, name) : null,
        index: index,
        required: notNull && !pk && row['dflt_value'] == null && !isSystem,
        readOnly: pk || isSystem,
        hidden: false,
        inListView: likelyList,
        inStandardFilter: likelyList,
        searchable: fieldType == 'Data' || fieldType == 'Link',
        defaultValue: _sqlDefault(row['dflt_value']),
      );
    }
  }

  void _ensureSinglesTable() {
    database.db.execute('''
      CREATE TABLE IF NOT EXISTS [tabSingles] (
        doctype TEXT NOT NULL,
        field TEXT NOT NULL,
        value TEXT,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (doctype, field)
      ) STRICT;
    ''');
  }

  void _ensureDocTypeTable(String tableName) {
    final table = quoteSqlIdentifier(tableName);
    database.db.execute('''
      CREATE TABLE IF NOT EXISTS $table (
        name TEXT PRIMARY KEY,
        owner TEXT,
        creation TEXT NOT NULL,
        modified TEXT NOT NULL,
        modified_by TEXT,
        docstatus INTEGER NOT NULL DEFAULT 0 CHECK (docstatus IN (0,1,2)),
        idx INTEGER NOT NULL DEFAULT 0,
        parent TEXT,
        parentfield TEXT,
        parenttype TEXT
      ) STRICT;
    ''');
    final columns = database.db.select('PRAGMA table_info($table);').map((row) => row['name'] as String).toSet();
    if (columns.containsAll(const {'modified', 'name'})) {
      database.db.execute('CREATE INDEX IF NOT EXISTS ${quoteSqlIdentifier('idx_${_indexStem(tableName)}_modified')} ON $table(modified DESC, name);');
    }
    if (columns.containsAll(const {'parenttype', 'parent', 'parentfield', 'idx'})) {
      database.db.execute('CREATE INDEX IF NOT EXISTS ${quoteSqlIdentifier('idx_${_indexStem(tableName)}_parent')} ON $table(parenttype, parent, parentfield, idx);');
    }
  }

  String _physicalIdField(String tableName) {
    final info = database.db.select('PRAGMA table_info(${quoteSqlIdentifier(tableName)});');
    final columns = info.map((row) => row['name'] as String).toSet();
    if (columns.contains('name')) return 'name';
    if (columns.contains('id')) return 'id';
    final primary = info.where((row) => ((row['pk'] as num?)?.toInt() ?? 0) > 0).toList()
      ..sort((a, b) => ((a['pk'] as num?)?.toInt() ?? 0).compareTo((b['pk'] as num?)?.toInt() ?? 0));
    if (primary.isNotEmpty) return primary.first['name'] as String;
    throw StateError('Physical DocType table $tableName has no usable document identity column.');
  }

  void _ensureDocTypeField(String tableName, String fieldName, String fieldType) {
    if (const {'Section Break', 'Column Break', 'Tab Break', 'Table', 'Table MultiSelect'}.contains(fieldType)) return;
    if (!isSafeFieldIdentifier(fieldName)) throw StateError('Invalid field name: $fieldName');
    final table = quoteSqlIdentifier(tableName);
    final columns = database.db.select('PRAGMA table_info($table);').map((row) => row['name'] as String).toSet();
    if (columns.contains(fieldName)) return;
    database.db.execute('ALTER TABLE $table ADD COLUMN ${quoteSqlIdentifier(fieldName)} ${_sqlType(fieldType)};');
  }

  String _sqlType(String fieldType) => switch (fieldType) {
        'Check' || 'Int' => 'INTEGER',
        'Float' || 'Currency' || 'Percent' || 'Duration' => 'REAL',
        _ => 'TEXT',
      };

  String _indexStem(String tableName) => tableName
      .replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  WmnFieldMeta _fromCustomField(WmnCustomField field, int index) => WmnFieldMeta(
        fieldName: field.fieldName,
        label: field.label,
        fieldType: switch (field.fieldType) {
          WmnCustomFieldType.data => 'Data',
          WmnCustomFieldType.text => 'Small Text',
          WmnCustomFieldType.integer => 'Int',
          WmnCustomFieldType.floating => 'Float',
          WmnCustomFieldType.currency => 'Currency',
          WmnCustomFieldType.check => 'Check',
          WmnCustomFieldType.select => 'Select',
          WmnCustomFieldType.date => 'Date',
          WmnCustomFieldType.dateTime => 'Datetime',
          WmnCustomFieldType.link => 'Link',
          WmnCustomFieldType.json => 'JSON',
        },
        options: field.options.join('\n'),
        index: index,
        required: field.required,
        readOnly: field.readOnly,
        hidden: field.hidden,
        inListView: field.inListView,
        inStandardFilter: field.searchable,
        searchable: field.searchable,
        defaultValue: field.defaultValue,
        isCustom: true,
      );

  Map<String, Map<String, Object?>> _propertyOverrides(String doctype) {
    final result = <String, Map<String, Object?>>{};
    if (!_tableExists('property_overrides')) return result;
    for (final override in customization.propertyOverrides(documentType: doctype, enabledOnly: true)) {
      result.putIfAbsent(override.fieldName, () => <String, Object?>{})[override.propertyName] = override.value;
    }
    return result;
  }

  String? _defaultSortField(WmnDocTypeMeta meta) {
    final names = meta.fields
        .where((field) => !field.hidden && !field.isLayout && !const {'Table', 'Table MultiSelect'}.contains(field.fieldType))
        .map((field) => field.fieldName)
        .toList(growable: false);
    final available = names.toSet();
    if (available.contains('modified')) return 'modified';
    if (available.contains('updated_at')) return 'updated_at';
    if (available.contains('created_at')) return 'created_at';
    if (available.contains(meta.idField)) return meta.idField;
    return names.isEmpty ? null : names.first;
  }


  String? _inferLinkTarget(WmnDocTypeMeta meta, String fieldName) {
    final lower = fieldName.trim().toLowerCase();
    if (lower == 'parent_id') return meta.name;
    if (!lower.endsWith('_id')) return null;

    // WMN System Core must not know business concepts such as Customer,
    // Warehouse or Account. For legacy physical schemas we infer a Link only
    // when the field stem matches a DocType that is actually registered by the
    // currently installed application.
    final stem = lower.substring(0, lower.length - 3).replaceAll('_', ' ').trim();
    if (stem.isEmpty) return null;
    final normalizedStem = stem.replaceAll(' ', '');
    for (final candidate in doctypes(enabledOnly: false)) {
      final normalizedName = candidate.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
      if (normalizedName == normalizedStem) return candidate.name;
    }
    return null;
  }

  String _inferFieldType(String name, String sqlType) {
    final lower = name.toLowerCase();
    if (lower.endsWith('_date') || lower == 'date' || lower == 'posting_date' || lower == 'required_by') return 'Date';
    if (lower.endsWith('_at') || lower == 'creation' || lower == 'modified') return 'Datetime';
    if (lower == 'enabled' || lower == 'disabled' || lower.startsWith('is_') || lower.startsWith('has_') || lower.startsWith('allow_') || lower.startsWith('require_')) return 'Check';
    if (sqlType.contains('INT')) return 'Int';
    if (sqlType.contains('REAL') || sqlType.contains('NUM') || lower.endsWith('_amount') || lower.endsWith('_total') || lower.endsWith('_rate') || lower.endsWith('_percent') || lower == 'qty') return 'Float';
    if (lower.endsWith('_id') || lower == 'parent_id' || lower == 'variant_of') return 'Link';
    if (lower.contains('remarks') || lower.contains('description') || lower.endsWith('_json')) return 'Small Text';
    return 'Data';
  }

  Object? _sqlDefault(Object? raw) {
    if (raw == null) return null;
    var value = '$raw';
    if (value.startsWith("'") && value.endsWith("'") && value.length >= 2) value = value.substring(1, value.length - 1);
    final number = num.tryParse(value);
    return number ?? value;
  }

  bool _sensitive(String name) {
    final lower = name.toLowerCase();
    const blocked = {'password', 'password_hash', 'pin', 'pin_hash', 'api_secret', 'api_key', 'access_token', 'refresh_token'};
    return blocked.contains(lower) || lower.endsWith('_secret') || lower.endsWith('_token') || lower.endsWith('_hash');
  }

  bool _tableExists(String name) => database.db.select(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;",
        [name],
      ).isNotEmpty;

  Map<String, Object?> _jsonMap(Object? raw) {
    if (raw is! String || raw.isEmpty) return const {};
    try {
      return Map<String, Object?>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return const {};
    }
  }

  Object? _decodeJson(Object? raw) {
    if (raw is! String || raw.isEmpty) return raw;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return raw;
    }
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

  String _humanize(String value) => value
      .split('_')
      .where((entry) => entry.isNotEmpty)
      .map((entry) => entry.length <= 2 ? entry.toUpperCase() : '${entry[0].toUpperCase()}${entry.substring(1)}')
      .join(' ');
}
