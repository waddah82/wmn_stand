import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/audit/audit_service.dart';
import '../../core/database/wmn_database.dart';
import '../../core/database/sql_identifier.dart';
import '../../modules/customization/data/customization_repository.dart';
import '../meta/doctype_meta.dart';
import '../meta/field_control_resolver.dart';
import '../meta/meta_service.dart';
import 'naming_engine.dart';

class WmnDocumentPage {
  const WmnDocumentPage({required this.rows, required this.total, required this.offset, required this.limit});

  final List<Map<String, Object?>> rows;
  final int total;
  final int offset;
  final int limit;
}

class WmnIncomingLinkReference {
  const WmnIncomingLinkReference({
    required this.referenceDoctype,
    required this.referenceName,
    required this.sourceDoctype,
    required this.fieldName,
    this.rowIndex,
    this.dynamic = false,
  });

  final String referenceDoctype;
  final String referenceName;
  final String sourceDoctype;
  final String fieldName;
  final int? rowIndex;
  final bool dynamic;

  String get description {
    final row = rowIndex == null || rowIndex! <= 0 ? '' : ' at row $rowIndex';
    return '$referenceDoctype $referenceName$row via $sourceDoctype.$fieldName';
  }
}

typedef WmnDocumentMutationListener = void Function(String doctype);

class WmnDocumentService {
  WmnDocumentService({
    required this.database,
    required this.meta,
    required this.customization,
    required this.audit,
  });

  final WmnDatabase database;
  final WmnMetaService meta;
  final CustomizationRepository customization;
  final AuditService audit;
  static const Uuid _uuid = Uuid();
  final List<WmnDocumentMutationListener> _mutationListeners =
      <WmnDocumentMutationListener>[];

  void addMutationListener(WmnDocumentMutationListener listener) {
    if (!_mutationListeners.contains(listener)) _mutationListeners.add(listener);
  }

  void removeMutationListener(WmnDocumentMutationListener listener) {
    _mutationListeners.remove(listener);
  }

  Map<String, Object?>? get(String doctype, String name) {
    final dt = meta.doctype(doctype);
    if (dt == null) return null;
    if (dt.isSingle) return _getSingle(dt);
    if (dt.storageMode != WmnStorageMode.table || dt.tableName == null) {
      throw StateError('DocType $doctype has no physical tab table.');
    }
    return _getTable(dt, name);
  }

  WmnDocumentPage list(
    String doctype, {
    List<List<Object?>> filters = const [],
    String? search,
    List<String> fields = const [],
    List<String> searchFields = const [],
    String? sortField,
    bool descending = true,
    int limit = 20,
    int offset = 0,
  }) {
    final dt = meta.doctype(doctype);
    if (dt == null) return const WmnDocumentPage(rows: [], total: 0, offset: 0, limit: 20);
    final safeLimit = limit.clamp(1, 500).toInt();
    final safeOffset = offset < 0 ? 0 : offset;
    if (dt.isSingle) {
      return _listSingle(
        dt,
        filters: filters,
        search: search,
        fields: fields,
        searchFields: searchFields,
        limit: safeLimit,
        offset: safeOffset,
      );
    }
    if (dt.storageMode != WmnStorageMode.table || dt.tableName == null) {
      throw StateError('DocType $doctype has no physical tab table.');
    }
    return _listTable(
      dt,
      filters: filters,
      search: search,
      fields: fields,
      searchFields: searchFields,
      sortField: sortField,
      descending: descending,
      limit: safeLimit,
      offset: safeOffset,
    );
  }

  Map<String, Object?> save(
    String doctype,
    Map<String, Object?> document, {
    String? existingName,
    bool fromImport = false,
  }) =>
      _saveDocument(
        doctype,
        document,
        existingName: existingName,
        fromImport: fromImport,
        enforceGenericPolicy: true,
        auditSource: 'framework',
      );

  /// Internal write path for a trusted application-owned engine.
  ///
  /// Generic UI create/edit/import flags and [WmnDocTypeMeta.genericWrite]
  /// protect users from manually editing ledger/cache DocTypes. A managed
  /// application procedure is separately ownership-gated before it reaches
  /// this method, so it may persist those engine-owned records while keeping
  /// the same schema validation, transaction, child-table, audit and mutation
  /// behavior as the normal document service.
  Map<String, Object?> saveEngineRecord(
    String doctype,
    Map<String, Object?> document, {
    String? existingName,
  }) =>
      _saveDocument(
        doctype,
        document,
        existingName: existingName,
        enforceGenericPolicy: false,
        auditSource: 'application_engine',
      );

  Map<String, Object?> _saveDocument(
    String doctype,
    Map<String, Object?> document, {
    String? existingName,
    bool fromImport = false,
    required bool enforceGenericPolicy,
    required String auditSource,
  }) {
    final dt = meta.doctype(doctype);
    if (dt == null) throw StateError('Unknown DocType: $doctype');
    final creating = !dt.isSingle && (existingName == null || existingName.trim().isEmpty);
    if (enforceGenericPolicy) {
      if (creating && !dt.allowCreate) throw StateError('$doctype does not allow generic create.');
      if (!creating && !dt.allowEdit) throw StateError('$doctype does not allow generic edit.');
      if (dt.storageMode == WmnStorageMode.table && !dt.genericWrite) {
        throw StateError('$doctype is engine-owned and cannot be written through the generic framework.');
      }
      if (fromImport && !dt.allowImport) throw StateError('$doctype does not allow Data Import.');
    }
    if (dt.storageMode != WmnStorageMode.table || dt.tableName == null) {
      throw StateError('DocType $doctype has no physical storage.');
    }

    final resolvedExistingName = dt.isSingle ? dt.name : existingName;
    final before = creating ? null : get(doctype, resolvedExistingName!);
    if (!creating && before == null) throw StateError('$doctype $resolvedExistingName does not exist.');

    final clean = _cleanDocument(dt, document);
    if (dt.isSingle) {
      clean['name'] = dt.name;
      clean['docstatus'] = 0;
    } else if (creating) {
      clean['docstatus'] = 0;
    } else {
      final currentStatus = _int(before?['docstatus']);
      clean['docstatus'] = currentStatus;
      if (dt.isSubmittable && currentStatus == 2) {
        throw StateError('Cancelled $doctype $resolvedExistingName cannot be edited.');
      }
      if (dt.isSubmittable && currentStatus == 1) {
        _validateSubmittedUpdate(dt, before!, clean);
      }
    }
    _validate(dt, clean);

    final saved = database.transaction(() {
      if (dt.isSingle) {
        _saveSingle(dt, clean);
        _saveChildTables(dt, dt.name, clean);
        return _getSingle(dt);
      }
      final parent = _saveTable(dt, clean, existingName: existingName);
      final name = '${parent[dt.idField] ?? parent['name']}';
      _saveChildTables(dt, name, clean);
      return _getTable(dt, name) ?? parent;
    });
    audit.record(
      entityType: doctype,
      entityId: '${saved[dt.idField] ?? saved['name'] ?? dt.name}',
      action: dt.isSingle ? 'UPDATE_SINGLE' : (creating ? (fromImport ? 'IMPORT_INSERT' : 'CREATE') : (fromImport ? 'IMPORT_UPDATE' : 'UPDATE')),
      payload: {auditSource: true, 'fields': clean.keys.toList(growable: false)},
    );
    _notifyMutation(doctype);
    return saved;
  }

  Map<String, Object?> submit(String doctype, String name) {
    final dt = meta.doctype(doctype);
    if (dt == null) throw StateError('Unknown DocType: $doctype');
    if (dt.isSingle) throw StateError('Single DocType $doctype cannot be submitted.');
    if (!dt.isSubmittable) throw StateError('$doctype is not submittable.');
    if (!dt.genericWrite) throw StateError('$doctype is engine-owned and must be submitted by its native controller.');
    final doc = get(doctype, name);
    if (doc == null) throw StateError('$doctype $name does not exist.');
    final status = _int(doc['docstatus']);
    if (status != 0) throw StateError('$doctype $name must be Draft before submit.');
    _validate(dt, _cleanDocument(dt, doc));
    _setDocStatus(dt, name, 1);
    audit.record(entityType: doctype, entityId: name, action: 'SUBMIT', payload: const {'framework': true, 'docstatus': 1});
    _notifyMutation(doctype);
    return get(doctype, name)!;
  }

  Map<String, Object?> cancel(String doctype, String name) {
    final dt = meta.doctype(doctype);
    if (dt == null) throw StateError('Unknown DocType: $doctype');
    if (dt.isSingle) throw StateError('Single DocType $doctype cannot be cancelled.');
    if (!dt.isSubmittable) throw StateError('$doctype is not submittable.');
    if (!dt.genericWrite) throw StateError('$doctype is engine-owned and must be cancelled by its native controller.');
    final doc = get(doctype, name);
    if (doc == null) throw StateError('$doctype $name does not exist.');
    final status = _int(doc['docstatus']);
    if (status != 1) throw StateError('$doctype $name must be Submitted before cancel.');
    _assertNoIncomingLinks(doctype, name, forCancel: true);
    _setDocStatus(dt, name, 2);
    audit.record(entityType: doctype, entityId: name, action: 'CANCEL', payload: const {'framework': true, 'docstatus': 2});
    _notifyMutation(doctype);
    return get(doctype, name)!;
  }

  void delete(String doctype, String name) =>
      _deleteDocument(doctype, name, enforceGenericPolicy: true, auditSource: 'framework');

  /// Internal delete path paired with [saveEngineRecord].
  void deleteEngineRecord(String doctype, String name) =>
      _deleteDocument(doctype, name, enforceGenericPolicy: false, auditSource: 'application_engine');

  void _deleteDocument(
    String doctype,
    String name, {
    required bool enforceGenericPolicy,
    required String auditSource,
  }) {
    final dt = meta.doctype(doctype);
    if (dt == null) throw StateError('Unknown DocType: $doctype');
    if (enforceGenericPolicy) {
      if (!dt.allowDelete) throw StateError('$doctype does not allow generic delete.');
      if (dt.storageMode == WmnStorageMode.table && !dt.genericWrite) {
        throw StateError('$doctype is engine-owned and cannot be deleted through the generic framework.');
      }
    }
    if (dt.isSingle) throw StateError('Single DocType $doctype has one persistent logical record and cannot be deleted as a document.');
    if (dt.storageMode != WmnStorageMode.table || dt.tableName == null) {
      throw StateError('DocType $doctype has no physical tab table.');
    }
    final existing = get(doctype, name);
    if (existing == null) return;
    if (dt.isSubmittable && _int(existing['docstatus']) == 1) {
      throw StateError('Submitted $doctype $name must be cancelled before deletion.');
    }
    _assertNoIncomingLinks(doctype, name);
    final table = _identifier(dt.tableName!);
    final id = _identifier(dt.idField);
    database.transaction(() {
      _deleteChildTables(dt, name);
      database.db.execute('DELETE FROM $table WHERE $id = ?;', [name]);
      if (_tableExists('custom_field_values')) {
        database.db.execute('DELETE FROM custom_field_values WHERE document_type = ? AND document_id = ?;', [doctype, name]);
      }
    });
    audit.record(entityType: doctype, entityId: name, action: 'DELETE', payload: <String, Object?>{auditSource: true});
    _notifyMutation(doctype);
  }

  void _notifyMutation(String doctype) {
    for (final listener in List<WmnDocumentMutationListener>.of(
      _mutationListeners,
    )) {
      try {
        listener(doctype);
      } catch (_) {
        // Cache invalidation listeners must never roll back an already
        // committed document operation.
      }
    }
  }

  List<WmnIncomingLinkReference> incomingLinkReferences(
    String doctype,
    String name, {
    bool forCancel = false,
  }) {
    final references = <WmnIncomingLinkReference>[];
    for (final sourceBase in meta.doctypes(enabledOnly: false)) {
      final source = meta.doctype(sourceBase.name);
      if (source == null) continue;
      for (final field in source.fields) {
        final control = _control(field);
        if (control.type == WmnFieldControlType.link) {
          final target = control.targetDoctype;
          if (target != doctype) continue;
          references.addAll(
            _referencesFromField(
              source,
              field.fieldName,
              name,
              targetDoctype: doctype,
              targetName: name,
              forCancel: forCancel,
            ),
          );
        } else if (control.type == WmnFieldControlType.dynamicLink) {
          final pointerField = field.options?.trim();
          if (pointerField == null || pointerField.isEmpty) continue;
          references.addAll(
            _referencesFromDynamicField(
              source,
              field.fieldName,
              pointerField,
              doctype,
              name,
              forCancel: forCancel,
            ),
          );
        }
      }
    }
    final unique = <String, WmnIncomingLinkReference>{};
    for (final reference in references) {
      final key = '${reference.referenceDoctype}\u0000${reference.referenceName}\u0000${reference.sourceDoctype}\u0000${reference.fieldName}\u0000${reference.rowIndex ?? 0}';
      unique[key] = reference;
    }
    return unique.values.toList(growable: false);
  }

  void _assertNoIncomingLinks(
    String doctype,
    String name, {
    bool forCancel = false,
  }) {
    final links = incomingLinkReferences(doctype, name, forCancel: forCancel);
    if (links.isEmpty) return;
    final first = links.first;
    final action = forCancel ? 'cancelled' : 'deleted';
    throw StateError(
      '$doctype $name cannot be $action because it is linked from ${first.description}.',
    );
  }

  List<WmnIncomingLinkReference> _referencesFromField(
    WmnDocTypeMeta source,
    String fieldName,
    String expected, {
    required String targetDoctype,
    required String targetName,
    required bool forCancel,
  }) {
    if (source.isSingle) {
      final doc = _getSingle(source);
      if (!_sameValue(doc[fieldName], expected)) return const [];
      return _referenceFromDocument(
        source,
        doc,
        fieldName,
        targetDoctype: targetDoctype,
        targetName: targetName,
        forCancel: forCancel,
      );
    }
    final ids = _documentIdsMatchingField(source, fieldName, expected);
    return _referencesForIds(
      source,
      ids,
      fieldName,
      targetDoctype: targetDoctype,
      targetName: targetName,
      forCancel: forCancel,
    );
  }

  List<WmnIncomingLinkReference> _referencesFromDynamicField(
    WmnDocTypeMeta source,
    String valueField,
    String pointerField,
    String targetDoctype,
    String targetName, {
    required bool forCancel,
  }) {
    if (source.isSingle) {
      final doc = _getSingle(source);
      if (!_sameValue(doc[pointerField], targetDoctype) || !_sameValue(doc[valueField], targetName)) {
        return const [];
      }
      return _referenceFromDocument(
        source,
        doc,
        valueField,
        targetDoctype: targetDoctype,
        targetName: targetName,
        forCancel: forCancel,
        dynamic: true,
      );
    }
    final typeIds = _documentIdsMatchingField(source, pointerField, targetDoctype);
    if (typeIds.isEmpty) return const [];
    final valueIds = _documentIdsMatchingField(source, valueField, targetName);
    if (valueIds.isEmpty) return const [];
    final ids = typeIds.intersection(valueIds);
    return _referencesForIds(
      source,
      ids,
      valueField,
      targetDoctype: targetDoctype,
      targetName: targetName,
      forCancel: forCancel,
      dynamic: true,
    );
  }

  Set<String> _documentIdsMatchingField(
    WmnDocTypeMeta source,
    String fieldName,
    Object? expected,
  ) {
    if (source.tableName == null || source.isSingle) return const <String>{};
    final table = _identifier(source.tableName!);
    final columns = _tableColumns(source.tableName!);
    final physicalId = _physicalIdField(source, columns);
    if (columns.contains(fieldName)) {
      final rows = database.db.select(
        'SELECT ${_identifier(physicalId)} FROM $table WHERE ${_identifier(fieldName)} = ?;',
        [expected],
      );
      return rows.map((row) => '${row[physicalId]}').toSet();
    }
    if (!_tableExists('custom_field_values')) return const <String>{};
    final encoded = expected == null ? null : jsonEncode(expected);
    final rows = database.db.select(
      'SELECT document_id FROM custom_field_values '
      'WHERE document_type = ? AND field_name = ? AND value_json = ?;',
      [source.name, fieldName, encoded],
    );
    return rows.map((row) => '${row['document_id']}').toSet();
  }

  List<WmnIncomingLinkReference> _referencesForIds(
    WmnDocTypeMeta source,
    Set<String> ids,
    String fieldName, {
    required String targetDoctype,
    required String targetName,
    required bool forCancel,
    bool dynamic = false,
  }) {
    if (ids.isEmpty || source.tableName == null) return const [];
    final table = _identifier(source.tableName!);
    final columns = _tableColumns(source.tableName!);
    final physicalId = _physicalIdField(source, columns);
    final selected = <String>{
      physicalId,
      if (columns.contains('docstatus')) 'docstatus',
      if (columns.contains('parent')) 'parent',
      if (columns.contains('parenttype')) 'parenttype',
      if (columns.contains('idx')) 'idx',
    };
    final marks = List.filled(ids.length, '?').join(',');
    final rows = database.db.select(
      'SELECT ${selected.map(_identifier).join(', ')} FROM $table '
      'WHERE ${_identifier(physicalId)} IN ($marks);',
      ids.toList(growable: false),
    );
    final result = <WmnIncomingLinkReference>[];
    for (final row in rows) {
      final normalized = Map<String, Object?>.from(row);
      normalized[source.idField] ??= normalized[physicalId];
      normalized['name'] ??= normalized[physicalId];
      result.addAll(
        _referenceFromDocument(
          source,
          normalized,
          fieldName,
          targetDoctype: targetDoctype,
          targetName: targetName,
          forCancel: forCancel,
          dynamic: dynamic,
        ),
      );
    }
    return result;
  }

  List<WmnIncomingLinkReference> _referenceFromDocument(
    WmnDocTypeMeta source,
    Map<String, Object?> row,
    String fieldName, {
    required String targetDoctype,
    required String targetName,
    required bool forCancel,
    bool dynamic = false,
  }) {
    final sourceName = source.isSingle ? source.name : '${row[source.idField] ?? row['name'] ?? ''}'.trim();
    if (sourceName.isEmpty) return const [];
    var referenceDoctype = source.name;
    var referenceName = sourceName;
    var rowIndex = 0;
    var status = _int(row['docstatus']);
    if (source.isChild) {
      final parent = '${row['parent'] ?? ''}'.trim();
      final parentType = '${row['parenttype'] ?? ''}'.trim();
      rowIndex = _int(row['idx']);
      if (parent.isNotEmpty && parentType.isNotEmpty) {
        referenceDoctype = parentType;
        referenceName = parent;
        final parentDoc = get(parentType, parent);
        if (parentDoc != null) status = _int(parentDoc['docstatus']);
      }
    }
    // Frappe does not block a document because one of its own child rows or
    // one of its own fields points back to the same logical document.
    if (referenceDoctype == targetDoctype && referenceName == targetName) return const [];
    final blocks = forCancel ? status == 1 : status != 2;
    if (!blocks) return const [];
    return [
      WmnIncomingLinkReference(
        referenceDoctype: referenceDoctype,
        referenceName: referenceName,
        sourceDoctype: source.name,
        fieldName: fieldName,
        rowIndex: rowIndex <= 0 ? null : rowIndex,
        dynamic: dynamic,
      ),
    ];
  }

  WmnFieldControlResolution _control(WmnFieldMeta field) =>
      WmnFieldControlResolver.resolve(
        field,
        doctypeExists: (name) => meta.doctype(name, includeFields: false) != null,
      );

  Set<String> _tableColumns(String tableName) => database.db
      .select('PRAGMA table_info(${_identifier(tableName)});')
      .map((row) => row['name'] as String)
      .toSet();

  String _physicalIdField(WmnDocTypeMeta dt, Set<String> columns) {
    if (columns.contains(dt.idField)) return dt.idField;
    if (columns.contains('name')) return 'name';
    if (columns.contains('id')) return 'id';
    final info = database.db.select('PRAGMA table_info(${_identifier(dt.tableName!)});');
    final primary = info.where((row) => ((row['pk'] as num?)?.toInt() ?? 0) > 0).toList()
      ..sort((a, b) => ((a['pk'] as num?)?.toInt() ?? 0).compareTo((b['pk'] as num?)?.toInt() ?? 0));
    if (primary.isNotEmpty) return primary.first['name'] as String;
    throw StateError('${dt.name} has no usable physical document identity column.');
  }

  bool exists(String doctype, String name) => get(doctype, name) != null;

  void _validateSubmittedUpdate(
    WmnDocTypeMeta dt,
    Map<String, Object?> before,
    Map<String, Object?> after,
  ) {
    for (final entry in after.entries) {
      if (entry.key == 'docstatus' || entry.key == dt.idField || entry.key == 'name') continue;
      if (_sameValue(before[entry.key], entry.value)) continue;
      final field = dt.field(entry.key);
      if (field == null || !field.allowOnSubmit) {
        throw StateError('${field?.label ?? entry.key} cannot be changed after submit.');
      }
    }
  }

  void _setDocStatus(WmnDocTypeMeta dt, String name, int status) {
    final table = _identifier(dt.tableName!);
    final id = _identifier(dt.idField);
    final columns = database.db.select('PRAGMA table_info($table);').map((row) => row['name'] as String).toSet();
    if (!columns.contains('docstatus')) throw StateError('${dt.name} does not expose docstatus.');
    final now = DateTime.now().toUtc().toIso8601String();
    final updates = <String>['"docstatus" = ?'];
    final args = <Object?>[status];
    if (columns.contains('modified')) {
      updates.add('"modified" = ?');
      args.add(now);
    }
    if (columns.contains('updated_at')) {
      updates.add('"updated_at" = ?');
      args.add(now);
    }
    args.add(name);
    database.db.execute('UPDATE $table SET ${updates.join(', ')} WHERE $id = ?;', args);
  }

  bool _sameValue(Object? a, Object? b) {
    if (a == b) return true;
    if (a is num && b is num) return a.toDouble() == b.toDouble();
    if (a is List || a is Map || b is List || b is Map) {
      try {
        return jsonEncode(a) == jsonEncode(b);
      } catch (_) {
        return false;
      }
    }
    return '${a ?? ''}' == '${b ?? ''}';
  }

  int _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  Map<String, Object?> _cleanDocument(WmnDocTypeMeta dt, Map<String, Object?> source) {
    final allowed = dt.fields.where((field) => !field.isLayout).map((field) => field.fieldName).toSet()
      ..addAll(const {
        'name',
        'docstatus',
        'owner',
        'creation',
        'modified',
        'modified_by',
        'idx',
        'parent',
        'parentfield',
        'parenttype',
      })
      ..add(dt.idField);
    return <String, Object?>{
      for (final entry in source.entries)
        if (allowed.contains(entry.key)) entry.key: _normalizeValue(dt.field(entry.key), entry.value),
    };
  }

  void _validate(WmnDocTypeMeta dt, Map<String, Object?> doc) {
    for (final field in dt.fields) {
      if (field.isLayout) continue;
      final value = doc[field.fieldName] ?? field.defaultValue;
      if (field.required && (value == null || (value is String && value.trim().isEmpty))) {
        throw StateError('${field.label} is required.');
      }
      if (value == null) continue;
      if (field.length != null && value is String && value.length > field.length!) {
        throw StateError('${field.label} exceeds the maximum length of ${field.length}.');
      }
      final control = _control(field);
      if (control.type == WmnFieldControlType.select &&
          control.options.isNotEmpty &&
          !control.options.contains('$value')) {
        throw StateError('${field.label} has an invalid value.');
      }
      if (control.type == WmnFieldControlType.link) {
        final target = control.targetDoctype;
        if (target != null && target.isNotEmpty && !exists(target, '$value')) {
          throw StateError('${field.label} references missing $target: $value');
        }
      } else if (control.type == WmnFieldControlType.dynamicLink) {
        final targetField = field.options?.trim();
        final target = targetField == null || targetField.isEmpty ? null : doc[targetField]?.toString().trim();
        if (target != null && target.isNotEmpty && !exists(target, '$value')) {
          throw StateError('${field.label} references missing $target: $value');
        }
      } else if (control.type == WmnFieldControlType.childTable) {
        if (value is! List) throw StateError('${field.label} must be a child table list.');
      }
    }
  }

  Map<String, Object?> _getSingle(WmnDocTypeMeta dt) {
    final doc = <String, Object?>{
      'name': dt.name,
      'docstatus': 0,
      for (final field in dt.fields)
        if (!field.isLayout && !const {'Table', 'Table MultiSelect'}.contains(field.fieldType) && field.defaultValue != null)
          field.fieldName: field.defaultValue,
    };
    if (_tableExists('tabSingles')) {
      final rows = database.db.select(
        'SELECT field,value FROM [tabSingles] WHERE doctype=? ORDER BY field;',
        [dt.name],
      );
      for (final row in rows) {
        final field = row['field'] as String;
        final raw = row['value'];
        doc[field] = _decodeJson(raw);
      }
    }
    _loadChildTables(dt, dt.name, doc);
    return doc;
  }

  Map<String, Object?> _saveSingle(WmnDocTypeMeta dt, Map<String, Object?> doc) {
    if (!_tableExists('tabSingles')) throw StateError('tabSingles is missing from the current schema.');
    final now = DateTime.now().toUtc().toIso8601String();
    final allowed = <String>{
      'name', 'owner', 'creation', 'modified', 'modified_by', 'docstatus',
      ...dt.fields
          .where((field) => !field.isLayout && !const {'Table', 'Table MultiSelect'}.contains(field.fieldType))
          .map((field) => field.fieldName),
    };
    database.db.execute('DELETE FROM [tabSingles] WHERE doctype=?;', [dt.name]);
    for (final entry in doc.entries) {
      if (!allowed.contains(entry.key) || entry.key == 'doctype') continue;
      database.db.execute(
        'INSERT INTO [tabSingles](doctype,field,value,updated_at) VALUES (?,?,?,?);',
        [dt.name, entry.key, entry.value == null ? null : jsonEncode(entry.value), now],
      );
    }
    return _getSingle(dt);
  }

  WmnDocumentPage _listSingle(
    WmnDocTypeMeta dt, {
    required List<List<Object?>> filters,
    required String? search,
    required List<String> fields,
    required List<String> searchFields,
    required int limit,
    required int offset,
  }) {
    final full = _getSingle(dt);
    if (!_singleMatches(dt, full, filters, search, searchFields) || offset > 0) {
      return WmnDocumentPage(rows: const [], total: 0, offset: offset, limit: limit);
    }
    final requested = fields.isEmpty ? dt.listFields.map((field) => field.fieldName).toList(growable: false) : fields;
    final row = <String, Object?>{
      'name': dt.name,
      for (final field in requested) field: full[field],
      if (dt.titleField != null) dt.titleField!: full[dt.titleField],
    };
    return WmnDocumentPage(rows: [row], total: 1, offset: 0, limit: limit);
  }

  bool _singleMatches(
    WmnDocTypeMeta dt,
    Map<String, Object?> doc,
    List<List<Object?>> filters,
    String? search,
    List<String> configuredSearchFields,
  ) {
    for (final filter in filters) {
      if (filter.length < 3) continue;
      final field = '${filter[0]}';
      final op = '${filter[1]}'.trim().toUpperCase();
      final expected = filter[2];
      final actual = doc[field];
      if (!_matchesFilter(actual, op, expected)) return false;
    }
    final query = search?.trim().toLowerCase();
    if (query == null || query.isEmpty) return true;
    final known = dt.fields.map((field) => field.fieldName).toSet();
    final names = configuredSearchFields.where(known.contains).toList(growable: false);
    final effective = names.isNotEmpty
        ? names
        : dt.fields
            .where((field) => field.searchable || field.inListView || field.fieldName == dt.titleField)
            .map((field) => field.fieldName)
            .take(12)
            .toList(growable: false);
    return effective.any((field) => '${doc[field] ?? ''}'.toLowerCase().contains(query));
  }

  bool _matchesFilter(Object? actual, String op, Object? expected) {
    if (op == '=' || op == '==') return _sameValue(actual, expected);
    if (op == '!=') return !_sameValue(actual, expected);
    if (op == 'LIKE') {
      final pattern = '${expected ?? ''}'.replaceAll('%', '').toLowerCase();
      return '${actual ?? ''}'.toLowerCase().contains(pattern);
    }
    if (op == 'IN' && expected is List) return expected.any((value) => _sameValue(actual, value));
    final a = actual is num ? actual.toDouble() : double.tryParse('${actual ?? ''}');
    final b = expected is num ? expected.toDouble() : double.tryParse('${expected ?? ''}');
    if (a == null || b == null) return false;
    return switch (op) {
      '>' => a > b,
      '>=' => a >= b,
      '<' => a < b,
      '<=' => a <= b,
      _ => false,
    };
  }

  Map<String, Object?>? _getTable(WmnDocTypeMeta dt, String name) {
    final table = _identifier(dt.tableName!);
    final columns = _tableColumns(dt.tableName!);
    final physicalId = _physicalIdField(dt, columns);
    final id = _identifier(physicalId);
    final rows = database.db.select('SELECT * FROM $table WHERE $id = ? LIMIT 1;', [name]);
    if (rows.isEmpty) return null;
    final doc = Map<String, Object?>.from(rows.first);
    doc[dt.idField] ??= doc[physicalId];
    doc['name'] ??= doc[physicalId];
    if (_tableExists('custom_field_values')) {
      final custom = database.db.select('''
        SELECT field_name, value_json FROM custom_field_values
        WHERE document_type = ? AND document_id = ?;
      ''', [dt.name, name]);
      for (final row in custom) {
        doc[row['field_name'] as String] = _decodeJson(row['value_json']);
      }
    }
    _loadChildTables(dt, name, doc);
    return doc;
  }


  WmnDocumentPage _listTable(
    WmnDocTypeMeta dt, {
    required List<List<Object?>> filters,
    required String? search,
    required List<String> fields,
    required List<String> searchFields,
    required String? sortField,
    required bool descending,
    required int limit,
    required int offset,
  }) {
    final table = _identifier(dt.tableName!);
    final standardNames = database.db.select('PRAGMA table_info($table);').map((row) => row['name'] as String).toSet();
    final physicalId = _physicalIdField(dt, standardNames);
    final where = _tableWhere(dt, standardNames, filters, search, searchFields);
    final requested = fields.isEmpty ? dt.listFields.map((entry) => entry.fieldName).toList() : fields;
    final standardRequested = <String>{
      physicalId,
      if (dt.titleField != null && standardNames.contains(dt.titleField)) dt.titleField!,
      ...requested.where(standardNames.contains),
    };
    final order = standardNames.contains(sortField)
        ? sortField!
        : (standardNames.contains('modified')
            ? 'modified'
            : (standardNames.contains('updated_at') ? 'updated_at' : physicalId));
    final selected = standardRequested.map(_identifier).join(', ');
    final raw = database.db.select(
      'SELECT $selected FROM $table${where.sql} ORDER BY ${_identifier(order)} ${descending ? 'DESC' : 'ASC'} LIMIT ? OFFSET ?;',
      [...where.args, limit, offset],
    );
    final countRows = database.db.select('SELECT COUNT(*) AS value FROM $table${where.sql};', where.args);
    final rows = raw.map((row) {
      final doc = Map<String, Object?>.from(row);
      doc[dt.idField] ??= doc[physicalId];
      doc['name'] ??= doc[physicalId];
      final id = '${doc[physicalId]}';
      if (requested.any((field) => !standardNames.contains(field)) && _tableExists('custom_field_values')) {
        final customRows = database.db.select('''
          SELECT field_name, value_json FROM custom_field_values
          WHERE document_type = ? AND document_id = ?;
        ''', [dt.name, id]);
        for (final custom in customRows) {
          if (requested.contains(custom['field_name'])) doc[custom['field_name'] as String] = _decodeJson(custom['value_json']);
        }
      }
      return doc;
    }).toList(growable: false);
    return WmnDocumentPage(
      rows: rows,
      total: countRows.isEmpty ? 0 : (countRows.first['value'] as int? ?? 0),
      offset: offset,
      limit: limit,
    );
  }


  _Where _tableWhere(
    WmnDocTypeMeta dt,
    Set<String> standard,
    List<List<Object?>> filters,
    String? search,
    List<String> configuredSearchFields,
  ) {
    final parts = <String>[];
    final args = <Object?>[];
    for (final filter in filters) {
      if (filter.length < 3) continue;
      final field = '${filter[0]}';
      if (!standard.contains(field)) continue;
      final op = '${filter[1]}'.trim().toUpperCase();
      final value = filter[2];
      switch (op) {
        case '=':
        case '!=':
        case '>':
        case '>=':
        case '<':
        case '<=':
        case 'LIKE':
          parts.add('${_identifier(field)} $op ?');
          args.add(value);
          break;
        case 'IN':
          if (value is List && value.isNotEmpty) {
            parts.add('${_identifier(field)} IN (${List.filled(value.length, '?').join(',')})');
            args.addAll(value);
          }
          break;
      }
    }
    final q = search?.trim();
    if (q != null && q.isNotEmpty) {
      final metadataFields = dt.fields.map((field) => field.fieldName).toSet();
      final requestedSearchFields = configuredSearchFields
          .where(metadataFields.contains)
          .where(standard.contains)
          .toSet()
          .toList(growable: false);
      final searchFields = (requestedSearchFields.isNotEmpty
              ? requestedSearchFields
              : dt.fields
                  .where((field) => field.searchable || field.inListView || field.fieldName == dt.titleField)
                  .map((field) => field.fieldName)
                  .where(standard.contains)
                  .take(8)
                  .toList(growable: false))
          .take(12)
          .toList(growable: false);
      if (searchFields.isNotEmpty) {
        parts.add('(${searchFields.map((field) => 'CAST(${_identifier(field)} AS TEXT) LIKE ?').join(' OR ')})');
        args.addAll(List.filled(searchFields.length, '%$q%'));
      }
    }
    return _Where(parts.isEmpty ? '' : ' WHERE ${parts.join(' AND ')}', args);
  }


  Map<String, Object?> _saveTable(WmnDocTypeMeta dt, Map<String, Object?> doc, {String? existingName}) {
    final table = _identifier(dt.tableName!);
    final columns = database.db.select('PRAGMA table_info($table);');
    final standard = columns.map((row) => row['name'] as String).toSet();
    final now = DateTime.now().toUtc().toIso8601String();
    final id = existingName ?? _newName(dt, doc);
    final values = <String, Object?>{for (final entry in doc.entries) if (standard.contains(entry.key)) entry.key: entry.value};
    values[dt.idField] = id;
    if (standard.contains('updated_at')) values['updated_at'] = now;
    if (standard.contains('modified')) values['modified'] = now;
    if (standard.contains('docstatus')) values['docstatus'] ??= 0;
    if (standard.contains('idx')) values['idx'] ??= 0;
    if (existingName == null) {
      if (standard.contains('created_at')) values['created_at'] = now;
      if (standard.contains('creation')) values['creation'] = now;
    }
    for (final row in columns) {
      final field = row['name'] as String;
      if (values.containsKey(field)) continue;
      final defaultValue = row['dflt_value'];
      if (defaultValue != null) continue;
      if ((row['notnull'] as int? ?? 0) == 1 && field != dt.idField && !const {'created_at', 'updated_at', 'creation', 'modified'}.contains(field)) {
        final metaField = dt.field(field);
        if (metaField?.defaultValue != null) {
          values[field] = metaField!.defaultValue;
        } else {
          throw StateError('${metaField?.label ?? field} is required.');
        }
      }
    }
    if (existingName == null) {
      final fields = values.keys.map(_identifier).join(',');
      final marks = List.filled(values.length, '?').join(',');
      database.db.execute('INSERT INTO $table($fields) VALUES ($marks);', values.values.toList(growable: false));
    } else {
      final updateEntries = values.entries.where((entry) => entry.key != dt.idField).toList(growable: false);
      if (updateEntries.isNotEmpty) {
        database.db.execute(
          'UPDATE $table SET ${updateEntries.map((entry) => '${_identifier(entry.key)} = ?').join(', ')} WHERE ${_identifier(dt.idField)} = ?;',
          [...updateEntries.map((entry) => entry.value), existingName],
        );
      }
    }
    if (_tableExists('custom_field_values')) {
      // Any metadata field that is not backed by a native table column is persisted
      // in the extension-value store. This is what lets imported Frappe DocType
      // metadata extend WMN-owned master tables without ALTER TABLE or data loss.
      final extensionValues = <String, Object?>{
        for (final field in dt.fields.where((field) => !field.isLayout && !const {'Table', 'Table MultiSelect'}.contains(field.fieldType) && !standard.contains(field.fieldName)))
          field.fieldName: doc[field.fieldName],
      };
      _saveCustomValues(dt.name, id, extensionValues);
    }
    return _getTable(dt, id)!;
  }

  void _loadChildTables(WmnDocTypeMeta dt, String parentName, Map<String, Object?> doc) {
    for (final field in dt.fields.where((field) => const {'Table', 'Table MultiSelect'}.contains(field.fieldType))) {
      final target = field.options?.trim();
      if (target == null || target.isEmpty) continue;
      final child = meta.doctype(target);
      if (child == null || child.storageMode != WmnStorageMode.table || child.tableName == null) {
        doc[field.fieldName] = const <Map<String, Object?>>[];
        continue;
      }
      final columns = database.db.select('PRAGMA table_info(${_identifier(child.tableName!)});').map((row) => row['name'] as String).toSet();
      if (!columns.containsAll(const {'parent', 'parenttype', 'parentfield', 'idx'})) {
        doc[field.fieldName] = const <Map<String, Object?>>[];
        continue;
      }
      final rows = database.db.select(
        'SELECT ${_identifier(child.idField)} FROM ${_identifier(child.tableName!)} '
        'WHERE "parent" = ? AND "parenttype" = ? AND "parentfield" = ? ORDER BY "idx", ${_identifier(child.idField)};',
        [parentName, dt.name, field.fieldName],
      );
      doc[field.fieldName] = rows
          .map((row) => get(target, '${row[child.idField]}'))
          .whereType<Map<String, Object?>>()
          .toList(growable: false);
    }
  }

  void _saveChildTables(WmnDocTypeMeta dt, String parentName, Map<String, Object?> doc) {
    for (final field in dt.fields.where((field) => const {'Table', 'Table MultiSelect'}.contains(field.fieldType))) {
      final target = field.options?.trim();
      if (target == null || target.isEmpty) continue;
      final child = meta.doctype(target);
      if (child == null || child.storageMode != WmnStorageMode.table || child.tableName == null) {
        throw StateError('Child DocType $target is not available as a physical table.');
      }
      final childTable = _identifier(child.tableName!);
      final columns = database.db.select('PRAGMA table_info($childTable);').map((row) => row['name'] as String).toSet();
      if (!columns.containsAll(const {'parent', 'parenttype', 'parentfield', 'idx'})) {
        throw StateError('Child DocType $target does not expose Frappe parent columns.');
      }

      final existingRows = database.db.select(
        'SELECT ${_identifier(child.idField)} FROM $childTable '
        'WHERE "parent" = ? AND "parenttype" = ? AND "parentfield" = ?;',
        [parentName, dt.name, field.fieldName],
      );
      final existingNames = existingRows.map((row) => '${row[child.idField]}').toSet();
      final retainedNames = <String>{};

      final rawRows = doc[field.fieldName];
      if (rawRows != null && rawRows is! List) {
        throw StateError('${field.label} must be a child table list.');
      }
      var index = 0;
      for (final raw in (rawRows as List? ?? const [])) {
        if (raw is! Map) throw StateError('${field.label} contains an invalid child row.');
        index++;
        final row = <String, Object?>{
          for (final entry in raw.entries) '${entry.key}': entry.value,
          'parent': parentName,
          'parenttype': dt.name,
          'parentfield': field.fieldName,
          'idx': index,
        };
        final requestedName = '${row[child.idField] ?? row['name'] ?? ''}'.trim();
        final existingName = requestedName.isNotEmpty && existingNames.contains(requestedName) ? requestedName : null;
        if (existingName == null) {
          // A child name from another parent must never be re-parented silently.
          row.remove(child.idField);
          if (child.idField != 'name') row.remove('name');
        }
        final cleanChild = _cleanDocument(child, row);
        _validate(child, cleanChild);
        final saved = _saveTable(child, cleanChild, existingName: existingName);
        retainedNames.add('${saved[child.idField] ?? saved['name']}');
      }

      final removedNames = existingNames.difference(retainedNames);
      if (removedNames.isNotEmpty) {
        final marks = List.filled(removedNames.length, '?').join(',');
        database.db.execute(
          'DELETE FROM $childTable WHERE "parent" = ? AND "parenttype" = ? AND "parentfield" = ? '
          'AND ${_identifier(child.idField)} IN ($marks);',
          [parentName, dt.name, field.fieldName, ...removedNames],
        );
      }
    }
  }

  void _deleteChildTables(WmnDocTypeMeta dt, String parentName) {
    for (final field in dt.fields.where((field) => const {'Table', 'Table MultiSelect'}.contains(field.fieldType))) {
      final target = field.options?.trim();
      if (target == null || target.isEmpty) continue;
      final child = meta.doctype(target, includeFields: false);
      if (child == null || child.storageMode != WmnStorageMode.table || child.tableName == null) continue;
      final table = _identifier(child.tableName!);
      final columns = database.db.select('PRAGMA table_info($table);').map((row) => row['name'] as String).toSet();
      if (!columns.containsAll(const {'parent', 'parenttype', 'parentfield'})) continue;
      database.db.execute(
        'DELETE FROM $table WHERE "parent" = ? AND "parenttype" = ? AND "parentfield" = ?;',
        [parentName, dt.name, field.fieldName],
      );
    }
  }


  void _saveCustomValues(String doctype, String id, Map<String, Object?> values) {
    final now = DateTime.now().toUtc().toIso8601String();
    for (final entry in values.entries) {
      if (entry.value == null) {
        database.db.execute('DELETE FROM custom_field_values WHERE document_type=? AND document_id=? AND field_name=?;', [doctype, id, entry.key]);
      } else {
        database.db.execute('''
          INSERT INTO custom_field_values(document_type,document_id,field_name,value_json,updated_at)
          VALUES (?,?,?,?,?)
          ON CONFLICT(document_type,document_id,field_name) DO UPDATE SET
            value_json=excluded.value_json,updated_at=excluded.updated_at;
        ''', [doctype, id, entry.key, jsonEncode(entry.value), now]);
      }
    }
  }

  String _newName(WmnDocTypeMeta dt, Map<String, Object?> doc) {
    final generated = WmnNamingEngine(database: database, meta: meta).nameFor(dt.name, doc);
    if (generated != null && generated.trim().isNotEmpty) return generated.trim();
    return _uuid.v4();
  }

  Object? _normalizeValue(WmnFieldMeta? field, Object? value) {
    if (field == null || value == null) return value;
    if (value is String && value.trim().isEmpty) return null;
    if (field.fieldType == 'JSON' && value is! String) {
      return jsonEncode(value);
    }
    if (field.isBoolean) {
      if (value is bool) return value ? 1 : 0;
      final text = '$value'.toLowerCase().trim();
      return const {'1', 'true', 'yes', 'y', 'on'}.contains(text) ? 1 : 0;
    }
    if (field.fieldType == 'Int') return value is num ? value.toInt() : int.tryParse('$value') ?? value;
    if (field.isNumeric) return value is num ? value : num.tryParse('$value') ?? value;
    return value;
  }

  Object? _decodeJson(Object? value) {
    if (value is! String || value.isEmpty) return value;
    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }

  bool _tableExists(String name) => database.db.select(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;",
        [name],
      ).isNotEmpty;

  String _identifier(String value) => quoteSqlIdentifier(value);
}

class _Where {
  const _Where(this.sql, this.args);
  final String sql;
  final List<Object?> args;
}
