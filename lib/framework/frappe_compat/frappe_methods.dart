import 'dart:convert';

import '../../core/database/wmn_database.dart';
import '../../platform/scripts/wmn_script_runtime.dart';
import 'frappe_db_api.dart';
import 'frappe_documents.dart';
import 'frappe_meta_api.dart';
import 'frappe_permissions.dart';

typedef WmnFrappeMethodHandler = Object? Function(Map<String, Object?> args);

class WmnFrappeMethodRegistry {
  WmnFrappeMethodRegistry({
    required this.database,
    required this.db,
    required this.meta,
    required this.permissions,
    required this.documents,
    WmnScriptRuntime? scripts,
  }) {
    if (scripts != null) attachScriptRuntime(scripts);
    _registerBuiltins();
  }

  final WmnDatabase database;
  final WmnFrappeDbApi db;
  final WmnFrappeMetaApi meta;
  final WmnFrappePermissionEngine permissions;
  final WmnFrappeDocumentApi documents;
  WmnScriptRuntime? _scripts;
  final Map<String, WmnFrappeMethodHandler> _handlers = <String, WmnFrappeMethodHandler>{};
  final Map<String, Map<String, Object?>> _nativeInfo = <String, Map<String, Object?>>{};

  void attachScriptRuntime(WmnScriptRuntime scripts) => _scripts = scripts;

  void register(
    String method,
    WmnFrappeMethodHandler handler, {
    bool replace = false,
    String category = 'Runtime',
    String description = '',
  }) {
    if (!replace && _handlers.containsKey(method)) throw StateError('WMN method already registered: $method');
    _handlers[method] = handler;
    _nativeInfo[method] = <String, Object?>{
      'method_name': method,
      'handler_kind': 'NATIVE',
      'category': category,
      'description': description,
      'enabled': 1,
      'editable': false,
    };
  }

  bool contains(String method) => _handlers.containsKey(method) || _persistentBinding(method) != null;

  List<Map<String, Object?>> catalog() {
    final rows = <Map<String, Object?>>[
      for (final entry in _nativeInfo.values) Map<String, Object?>.from(entry),
    ];
    final persistent = database.db.select('''
      SELECT method_name,handler_kind,target,allow_guest,enabled,source_app,metadata_json,updated_at
      FROM wmn_method_bindings
      ORDER BY method_name COLLATE NOCASE;
    ''');
    for (final row in persistent) {
      final metadata = _jsonMap(row['metadata_json']);
      rows.add(<String, Object?>{
        'method_name': row['method_name'],
        'handler_kind': row['handler_kind'],
        'target': row['target'],
        'allow_guest': row['allow_guest'],
        'enabled': row['enabled'],
        'source_app': row['source_app'],
        'updated_at': row['updated_at'],
        'editable': metadata['wmn_custom_method'] == true && metadata['scope'] == 'SYSTEM_GLOBAL',
        ...metadata,
      });
    }
    rows.sort((a, b) => '${a['method_name']}'.compareTo('${b['method_name']}'));
    return rows;
  }

  Object? call(String method, [Map<String, Object?> args = const {}]) {
    var target = method;
    final seen = <String>{};
    while (seen.add(target)) {
      final handler = _handlers[target];
      if (handler != null) return handler(args);
      final binding = _persistentBinding(target);
      if (binding == null || binding['enabled'] != 1) break;
      final kind = binding['handler_kind'] as String;
      if (kind == 'ALIAS') {
        target = '${binding['target'] ?? ''}';
        continue;
      }
      if (kind == 'SERVER_SCRIPT') {
        return _callServerScriptMethod(method, binding, args);
      }
      if (kind == 'PORT_REQUIRED') {
        throw WmnFrappeMethodNotImplemented(method, 'Method is registered as a Frappe porting task.');
      }
      break;
    }
    throw WmnFrappeMethodNotImplemented(method, 'No native WMN method binding exists.');
  }

  Object? tryCall(String method, [Map<String, Object?> args = const {}]) {
    try {
      return call(method, args);
    } on WmnFrappeMethodNotImplemented {
      return <String, Object?>{'__wmn_unresolved_method': method};
    }
  }

  void saveAlias(String method, String target, {String? sourceApp}) {
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO wmn_method_bindings(method_name,handler_kind,target,source_app,updated_at)
      VALUES (?,'ALIAS',?,?,?)
      ON CONFLICT(method_name) DO UPDATE SET
        handler_kind='ALIAS',target=excluded.target,source_app=excluded.source_app,enabled=1,updated_at=excluded.updated_at;
    ''', [method, target, sourceApp, now]);
  }

  void markPortRequired(String method, {String? sourceApp, String? sourcePath, Map<String, Object?> metadata = const {}}) {
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO wmn_method_bindings(method_name,handler_kind,target,source_app,metadata_json,updated_at)
      VALUES (?,'PORT_REQUIRED',?,?,?,?)
      ON CONFLICT(method_name) DO UPDATE SET
        handler_kind='PORT_REQUIRED',target=excluded.target,source_app=excluded.source_app,
        metadata_json=excluded.metadata_json,updated_at=excluded.updated_at;
    ''', [method, sourcePath, sourceApp, jsonEncode(metadata), now]);
  }

  Map<String, Object?>? _persistentBinding(String method) {
    final rows = database.db.select('SELECT * FROM wmn_method_bindings WHERE method_name=? LIMIT 1;', [method]);
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.first);
  }

  void _registerBuiltins() {
    register('frappe.client.get', (args) {
      final dt = '${args['doctype'] ?? ''}';
      final name = '${args['name'] ?? ''}';
      if (dt.isEmpty || name.isEmpty) return null;
      if (!permissions.hasPermission(dt, 'read', docname: name)) return null;
      return db.documents.get(dt, name);
    });
    register('frappe.client.get_value', (args) {
      final dt = '${args['doctype'] ?? args['dt'] ?? ''}';
      final field = args['fieldname'] ?? args['field'] ?? 'name';
      final selector = args['filters'] ?? args['name'];
      if (dt.isEmpty || selector == null) return null;
      return db.getValue(dt, selector, field);
    });
    register('frappe.client.get_list', (args) => _list(args, ignorePermissions: false));
    register('frappe.client.get_all', (args) => _list(args, ignorePermissions: true));
    register('frappe.client.get_count', (args) {
      final dt = '${args['doctype'] ?? ''}';
      return dt.isEmpty ? 0 : db.count(dt, filters: args['filters']);
    });
    register('frappe.client.set_value', (args) {
      final dt = '${args['doctype'] ?? ''}';
      final name = '${args['name'] ?? ''}';
      final field = args['fieldname'] ?? args['field'];
      if (dt.isEmpty || name.isEmpty || field == null) return null;
      return db.setValue(dt, name, field, args['value']);
    });
    register('frappe.client.get_single_value', (args) {
      final dt = '${args['doctype'] ?? ''}';
      final field = '${args['field'] ?? args['fieldname'] ?? ''}';
      return dt.isEmpty || field.isEmpty ? null : db.getSingleValue(dt, field);
    });
    register('frappe.client.get_count', (args) {
      final dt = '${args['doctype'] ?? ''}';
      return dt.isEmpty ? 0 : db.count(dt, filters: args['filters']);
    }, replace: true);
    register('frappe.desk.search.search_link', (args) {
      final dt = '${args['doctype'] ?? ''}';
      final txt = '${args['txt'] ?? ''}';
      if (dt.isEmpty) return const <Object?>[];
      final metaValue = meta.getMeta(dt);
      final title = metaValue?['title_field']?.toString() ?? 'name';
      final rows = db.getList(
        dt,
        fields: <String>{'name', title}.toList(growable: false),
        filters: args['filters'],
        search: txt,
        limit: 20,
      );
      return rows
          .map((row) => <String, Object?>{
                'value': row['name'],
                'description': row[title] ?? row['name'],
              })
          .toList(growable: false);
    });
    register('frappe.contacts.address_and_contact.filter_dynamic_link_doctypes', (_) => db.meta.doctypes().map((entry) => entry.name).toList(growable: false));
    register(
      'wmn.table.insert',
      _tableInsert,
      category: 'Safe Table CRUD',
      description: 'Insert a document row through the WMN document lifecycle. Accepts doctype/table and values.',
    );
    register(
      'wmn.db.insert',
      _tableInsert,
      category: 'Safe Database CRUD',
      description: 'Global safe Insert Into Table interface. Resolves the registered DocType and uses the document lifecycle.',
    );
    register(
      'wmn.table.update',
      _tableUpdate,
      category: 'Safe Table CRUD',
      description: 'Update one document row by identity through the WMN document lifecycle.',
    );
    register(
      'wmn.db.update',
      _tableUpdate,
      category: 'Safe Database CRUD',
      description: 'Global safe Update Table interface. Uses permissions, validation and document hooks.',
    );
    register(
      'wmn.table.delete',
      _tableDelete,
      category: 'Safe Table CRUD',
      description: 'Delete one document row by identity through WMN permissions and delete protection.',
    );
    register(
      'wmn.db.delete',
      _tableDelete,
      category: 'Safe Database CRUD',
      description: 'Global safe Delete From Table interface. Uses permissions and reference protection.',
    );
    register(
      'wmn.document.insert',
      _documentInsert,
      category: 'Document CRUD',
      description: 'Create a DocType document using permissions, naming, validation and hooks.',
    );
    register(
      'wmn.document.update',
      _documentUpdate,
      category: 'Document CRUD',
      description: 'Update a DocType document using permissions, validation and hooks.',
    );
    register(
      'wmn.document.delete',
      _documentDelete,
      category: 'Document CRUD',
      description: 'Delete a DocType document using permissions and reference protection.',
    );
    register('wmn.framework.get_meta', (args) => meta.getMeta('${args['doctype'] ?? ''}'));
  }

  Object? _callServerScriptMethod(
    String method,
    Map<String, Object?> binding,
    Map<String, Object?> args,
  ) {
    final metadata = _jsonMap(binding['metadata_json']);
    if (metadata['wmn_custom_method'] == true && metadata['scope'] == 'SYSTEM_GLOBAL') {
      return _callLegacyManagedCustomMethod(method, binding, args);
    }
    final scripts = _scripts;
    if (scripts == null) {
      throw WmnFrappeMethodNotImplemented(method, 'Managed script runtime is unavailable.');
    }
    final sourceApp = '${binding['source_app'] ?? ''}'.trim();
    if (sourceApp.isEmpty) {
      throw WmnFrappeMethodNotImplemented(method, 'Managed application method has no source_app owner.');
    }
    final target = '${binding['target'] ?? ''}'.trim();
    if (target.isEmpty) {
      throw WmnFrappeMethodNotImplemented(method, 'Managed application method has no Server Script target.');
    }
    final rows = database.db.select(
      'SELECT id,name,script_type,api_method,source_storage_path,enabled FROM server_scripts WHERE (id=? OR name=?) LIMIT 1;',
      <Object?>[target, target],
    );
    if (rows.isEmpty) {
      throw WmnFrappeMethodNotImplemented(method, 'Managed Server Script was not found: $target');
    }
    final row = rows.first;
    if ((row['enabled'] as num?)?.toInt() != 1) {
      throw WmnFrappeMethodNotImplemented(method, 'Managed Server Script is disabled: $target');
    }
    if ('${row['script_type'] ?? ''}' != 'API') {
      throw WmnFrappeMethodNotImplemented(method, 'Server Script $target is not an API script.');
    }
    final apiMethod = '${row['api_method'] ?? ''}'.trim();
    if (apiMethod.isNotEmpty && apiMethod != method) {
      throw WmnFrappeMethodNotImplemented(method, 'Server Script $target belongs to API method $apiMethod.');
    }
    final path = '${row['source_storage_path'] ?? ''}'.trim();
    if (path.isEmpty || !path.startsWith('apps/$sourceApp/')) {
      throw WmnFrappeMethodNotImplemented(method, 'Managed method cannot execute a source owned by another application.');
    }
    final language = '${metadata['script_language'] ?? 'wmn-procedure-v1'}'.trim().toLowerCase();
    return scripts.executeStored(
      path: path,
      language: language,
      context: <String, Object?>{
        ...args,
        'args': Map<String, Object?>.from(args),
        'method': method,
        'source_app': sourceApp,
      },
    );
  }

  Object? _callLegacyManagedCustomMethod(
    String method,
    Map<String, Object?> binding,
    Map<String, Object?> args,
  ) {
    final metadata = _jsonMap(binding['metadata_json']);
    if (metadata['wmn_custom_method'] != true || metadata['scope'] != 'SYSTEM_GLOBAL') {
      throw WmnFrappeMethodNotImplemented(
        method,
        'Server-script execution is gated; this path only supports legacy managed safe function bindings.',
      );
    }
    final target = '${metadata['target_method'] ?? binding['target'] ?? ''}'.trim();
    const allowedTargets = <String>{
      'wmn.document.insert',
      'wmn.document.update',
      'wmn.document.delete',
      'wmn.table.insert',
      'wmn.table.update',
      'wmn.table.delete',
      'wmn.db.insert',
      'wmn.db.update',
      'wmn.db.delete',
    };
    if (!allowedTargets.contains(target) || target == method) {
      throw WmnFrappeMethodNotImplemented(method, 'Unsupported managed global target: $target');
    }
    final handler = _handlers[target];
    if (handler == null) throw WmnFrappeMethodNotImplemented(method, 'Global target is not registered: $target');
    return handler(args);
  }

  Object? _tableInsert(Map<String, Object?> args) {
    final dt = _safeTableDocType(args);
    final values = _objectMap(args['values'] ?? args['data'] ?? args['document']);
    if (values.isEmpty) throw StateError('wmn.table.insert requires a non-empty values map.');
    return documents.insert(dt, values);
  }

  Object? _tableUpdate(Map<String, Object?> args) {
    final dt = _safeTableDocType(args);
    final name = '${args['name'] ?? args['id'] ?? args['document_name'] ?? ''}'.trim();
    if (name.isEmpty) throw StateError('wmn.table.update requires name/id.');
    final values = _objectMap(args['values'] ?? args['data'] ?? args['document']);
    if (values.isEmpty) throw StateError('wmn.table.update requires a non-empty values map.');
    return documents.save(dt, name, values);
  }

  Object? _tableDelete(Map<String, Object?> args) {
    final dt = _safeTableDocType(args);
    final name = '${args['name'] ?? args['id'] ?? args['document_name'] ?? ''}'.trim();
    if (name.isEmpty) throw StateError('wmn.table.delete requires name/id.');
    documents.deleteDoc(dt, name);
    return <String, Object?>{'deleted': true, 'doctype': dt, 'name': name};
  }

  Object? _documentInsert(Map<String, Object?> args) {
    final dt = '${args['doctype'] ?? ''}'.trim();
    if (dt.isEmpty) throw StateError('wmn.document.insert requires doctype.');
    return documents.insert(dt, _objectMap(args['values'] ?? args['data'] ?? args['document']));
  }

  Object? _documentUpdate(Map<String, Object?> args) {
    final dt = '${args['doctype'] ?? ''}'.trim();
    final name = '${args['name'] ?? args['id'] ?? args['document_name'] ?? ''}'.trim();
    if (dt.isEmpty || name.isEmpty) throw StateError('wmn.document.update requires doctype and name/id.');
    return documents.save(dt, name, _objectMap(args['values'] ?? args['data'] ?? args['document']));
  }

  Object? _documentDelete(Map<String, Object?> args) {
    final dt = '${args['doctype'] ?? ''}'.trim();
    final name = '${args['name'] ?? args['id'] ?? args['document_name'] ?? ''}'.trim();
    if (dt.isEmpty || name.isEmpty) throw StateError('wmn.document.delete requires doctype and name/id.');
    documents.deleteDoc(dt, name);
    return <String, Object?>{'deleted': true, 'doctype': dt, 'name': name};
  }

  String _safeTableDocType(Map<String, Object?> args) {
    final requestedDoctype = '${args['doctype'] ?? ''}'.trim();
    final requestedTable = '${args['table'] ?? ''}'.trim();
    final all = meta.meta.doctypes(enabledOnly: false);
    dynamic dt = requestedDoctype.isNotEmpty ? meta.meta.doctype(requestedDoctype) : null;
    if (dt == null && requestedTable.isNotEmpty) {
      for (final entry in all) {
        if (entry.tableName == requestedTable) {
          dt = entry;
          break;
        }
      }
    }
    if (dt == null) throw StateError('Unknown DocType/table: ${requestedDoctype.isNotEmpty ? requestedDoctype : requestedTable}');
    if (dt.isSingle) throw StateError('${dt.name} is a Single DocType and has no document table CRUD interface.');
    if (dt.isChild) throw StateError('${dt.name} is a child DocType and must be changed through its parent.');
    if (!dt.genericWrite) throw StateError('${dt.name} is owned by a native application engine; direct table methods are blocked.');
    if (requestedTable.isNotEmpty && dt.tableName != requestedTable) {
      throw StateError('Table $requestedTable is not the registered table for ${dt.name}.');
    }
    return dt.name;
  }

  Map<String, Object?> _objectMap(Object? value) {
    if (value is Map<String, Object?>) return Map<String, Object?>.from(value);
    if (value is Map) return Map<String, Object?>.from(value);
    return <String, Object?>{};
  }

  Map<String, Object?> _jsonMap(Object? value) {
    if (value is Map<String, Object?>) return Map<String, Object?>.from(value);
    if (value is Map) return Map<String, Object?>.from(value);
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, Object?>.from(decoded);
      } catch (_) {}
    }
    return <String, Object?>{};
  }

  Object _list(Map<String, Object?> args, {required bool ignorePermissions}) {
    final dt = '${args['doctype'] ?? ''}';
    if (dt.isEmpty) return const <Object?>[];
    final rawFields = args['fields'];
    final fields = rawFields is List ? rawFields.map((entry) => '$entry').toList(growable: false) : const <String>[];
    final limit = (args['limit_page_length'] as num?)?.toInt() ?? (args['limit'] as num?)?.toInt() ?? 20;
    final offset = (args['limit_start'] as num?)?.toInt() ?? 0;
    return db.getList(
      dt,
      fields: fields,
      filters: args['filters'],
      orderBy: args['order_by']?.toString(),
      limit: limit,
      offset: offset,
      ignorePermissions: ignorePermissions,
    );
  }
}

class WmnFrappeMethodNotImplemented implements Exception {
  const WmnFrappeMethodNotImplemented(this.method, this.message);
  final String method;
  final String message;
  @override
  String toString() => 'WmnFrappeMethodNotImplemented($method): $message';
}
