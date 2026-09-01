import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/database/wmn_database.dart';
import '../../platform/scripts/wmn_script_runtime.dart';

typedef WmnFrappeDocumentHook = void Function(Map<String, Object?> document);

class WmnFrappeHookBinding {
  const WmnFrappeHookBinding({
    required this.id,
    required this.hookType,
    this.referenceDoctype,
    this.eventName,
    this.sourceApp,
    this.sourcePath,
    required this.targetKind,
    this.target,
    this.priority = 0,
    this.enabled = true,
    this.metadata = const {},
  });

  final String id;
  final String hookType;
  final String? referenceDoctype;
  final String? eventName;
  final String? sourceApp;
  final String? sourcePath;
  final String targetKind;
  final String? target;
  final int priority;
  final bool enabled;
  final Map<String, Object?> metadata;
}

class WmnFrappeHookRegistry {
  factory WmnFrappeHookRegistry(WmnDatabase database, {WmnScriptRuntime? scripts}) =>
      WmnFrappeHookRegistry._(database, scripts);

  WmnFrappeHookRegistry._(this.database, this._scripts);

  final WmnDatabase database;
  WmnScriptRuntime? _scripts;
  Object? Function(String method, Map<String, Object?> args)? _methodInvoker;

  void attachScriptRuntime(WmnScriptRuntime scripts) => _scripts = scripts;
  void attachMethodInvoker(Object? Function(String method, Map<String, Object?> args) invoker) => _methodInvoker = invoker;
  final Map<String, List<WmnFrappeDocumentHook>> _documentHandlers = {};
  static const Uuid _uuid = Uuid();

  void onDocument(String doctype, String event, WmnFrappeDocumentHook handler) {
    _documentHandlers.putIfAbsent('$doctype::$event', () => <WmnFrappeDocumentHook>[]).add(handler);
  }

  void emitDocument(
    String doctype,
    String event,
    Map<String, Object?> document, {
    Map<String, Object?>? previous,
    String? operation,
    String? actor,
  }) {
    for (final handler in _documentHandlers['$doctype::$event'] ?? const <WmnFrappeDocumentHook>[]) {
      handler(document);
    }
    for (final handler in _documentHandlers['*::$event'] ?? const <WmnFrappeDocumentHook>[]) {
      handler(document);
    }

    // Persistent bindings are application-owned and loaded from metadata on
    // every event. This is intentional: a newly imported standard application ZIP becomes
    // executable immediately without restarting or rebuilding the Flutter host.
    for (final binding in bindings(hookType: 'DOCUMENT_EVENT', doctype: doctype, event: event)) {
      final bindingDoctype = binding.referenceDoctype?.trim();
      final bindingEvent = binding.eventName?.trim();
      if (bindingDoctype != null && bindingDoctype.isNotEmpty && bindingDoctype != '*' && bindingDoctype != doctype) continue;
      if (bindingEvent != null && bindingEvent.isNotEmpty && bindingEvent != '*' && bindingEvent != event) continue;
      _executePersistentBinding(
        binding,
        doctype: doctype,
        event: event,
        document: document,
        previous: previous,
        operation: operation,
        actor: actor,
      );
    }
  }

  void _executePersistentBinding(
    WmnFrappeHookBinding binding, {
    required String doctype,
    required String event,
    required Map<String, Object?> document,
    Map<String, Object?>? previous,
    String? operation,
    String? actor,
  }) {
    if (!binding.enabled) return;
    final context = <String, Object?>{
      'document': document,
      'previous': previous,
      'doctype': doctype,
      'event': event,
      'operation': operation,
      'actor': actor,
      'source_app': binding.sourceApp,
      'hook_id': binding.id,
    };
    if (binding.targetKind == 'METHOD') {
      final method = binding.target?.trim() ?? '';
      if (method.isEmpty) throw StateError('Managed hook ${binding.id} has no Method target.');
      final invoker = _methodInvoker;
      if (invoker == null) throw StateError('Managed Method runtime is unavailable for hook ${binding.id}.');
      invoker(method, context);
      return;
    }
    if (binding.targetKind != 'SERVER_SCRIPT') {
      if (binding.targetKind == 'PORT_REQUIRED') {
        throw StateError('Application hook ${binding.id} still requires a runtime port.');
      }
      return;
    }
    final scripts = _scripts;
    if (scripts == null) throw StateError('Managed script runtime is unavailable for hook ${binding.id}.');
    final target = binding.target?.trim() ?? '';
    if (target.isEmpty) throw StateError('Managed hook ${binding.id} has no Server Script target.');
    final rows = database.db.select(
      'SELECT id,name,source_storage_path,enabled FROM server_scripts WHERE (id=? OR name=?) LIMIT 1;',
      <Object?>[target, target],
    );
    if (rows.isEmpty) throw StateError('Managed Server Script not found for hook ${binding.id}: $target');
    final row = rows.first;
    if ((row['enabled'] as num?)?.toInt() != 1) return;
    final path = '${row['source_storage_path'] ?? ''}'.trim();
    if (path.isEmpty) throw StateError('Managed Server Script has no source path: $target');
    final sourceApp = binding.sourceApp?.trim() ?? '';
    if (sourceApp.isEmpty || !path.startsWith('apps/$sourceApp/')) {
      throw StateError('Managed hook ${binding.id} cannot execute a source owned by another application.');
    }
    final language = '${binding.metadata['script_language'] ?? 'wmn-procedure-v1'}'.trim().toLowerCase();
    scripts.executeStored(path: path, language: language, context: context);
  }

  WmnFrappeHookBinding saveBinding({
    String? id,
    required String hookType,
    String? referenceDoctype,
    String? eventName,
    String? sourceApp,
    String? sourcePath,
    String targetKind = 'PORT_REQUIRED',
    String? target,
    int priority = 0,
    bool enabled = true,
    Map<String, Object?> metadata = const {},
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    final bindingId = id ?? _uuid.v4();
    database.db.execute('''
      INSERT INTO wmn_hook_bindings(
        id,hook_type,reference_doctype,event_name,source_app,source_path,target_kind,target,
        priority,enabled,metadata_json,created_at,updated_at
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET
        hook_type=excluded.hook_type,reference_doctype=excluded.reference_doctype,event_name=excluded.event_name,
        source_app=excluded.source_app,source_path=excluded.source_path,target_kind=excluded.target_kind,target=excluded.target,
        priority=excluded.priority,enabled=excluded.enabled,metadata_json=excluded.metadata_json,updated_at=excluded.updated_at;
    ''', [
      bindingId,
      hookType,
      referenceDoctype,
      eventName,
      sourceApp,
      sourcePath,
      targetKind,
      target,
      priority,
      enabled ? 1 : 0,
      jsonEncode(metadata),
      now,
      now,
    ]);
    return WmnFrappeHookBinding(
      id: bindingId,
      hookType: hookType,
      referenceDoctype: referenceDoctype,
      eventName: eventName,
      sourceApp: sourceApp,
      sourcePath: sourcePath,
      targetKind: targetKind,
      target: target,
      priority: priority,
      enabled: enabled,
      metadata: metadata,
    );
  }

  List<WmnFrappeHookBinding> bindings({String? hookType, String? doctype, String? event}) {
    final conditions = <String>['enabled=1'];
    final args = <Object?>[];
    if (hookType != null) {
      conditions.add('hook_type=?');
      args.add(hookType);
    }
    if (doctype != null) {
      conditions.add('(reference_doctype IS NULL OR reference_doctype=? OR reference_doctype=\'*\')');
      args.add(doctype);
    }
    if (event != null) {
      conditions.add('(event_name IS NULL OR event_name=? OR event_name=\'*\')');
      args.add(event);
    }
    final rows = database.db.select(
      'SELECT * FROM wmn_hook_bindings WHERE ${conditions.join(' AND ')} ORDER BY priority, id;',
      args,
    );
    return rows.map((row) {
      Map<String, Object?> metadata = const {};
      try {
        metadata = Map<String, Object?>.from(jsonDecode(row['metadata_json'] as String) as Map);
      } catch (_) {}
      return WmnFrappeHookBinding(
        id: row['id'] as String,
        hookType: row['hook_type'] as String,
        referenceDoctype: row['reference_doctype'] as String?,
        eventName: row['event_name'] as String?,
        sourceApp: row['source_app'] as String?,
        sourcePath: row['source_path'] as String?,
        targetKind: row['target_kind'] as String,
        target: row['target'] as String?,
        priority: row['priority'] as int? ?? 0,
        enabled: (row['enabled'] as int? ?? 1) == 1,
        metadata: metadata,
      );
    }).toList(growable: false);
  }
}
