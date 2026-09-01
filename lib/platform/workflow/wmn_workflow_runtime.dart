import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/database/wmn_database.dart';
import '../../core/documents/document_event_bus.dart';
import '../security/wmn_identity_service.dart';
import '../security/wmn_permission_service.dart';
import 'wmn_workflow_condition_engine.dart';

abstract interface class WmnWorkflowDocumentGateway {
  Map<String, Object?>? get(String doctype, String name);
  Map<String, Object?> save(String doctype, String name, Map<String, Object?> values);
  Map<String, Object?> submit(String doctype, String name);
  Map<String, Object?> cancel(String doctype, String name);
}

class WmnWorkflowState {
  const WmnWorkflowState({
    required this.id,
    required this.name,
    required this.docStatus,
    required this.index,
    this.allowEditRole,
  });

  final String id;
  final String name;
  final int docStatus;
  final int index;
  final String? allowEditRole;
}

class WmnWorkflowTransition {
  const WmnWorkflowTransition({
    required this.id,
    required this.state,
    required this.action,
    required this.nextState,
    required this.index,
    this.allowedRole,
    this.condition,
    this.conditionHandler,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String state;
  final String action;
  final String nextState;
  final int index;
  final String? allowedRole;
  final String? condition;
  final String? conditionHandler;
  final Map<String, Object?> metadata;
}

class WmnWorkflowDefinition {
  const WmnWorkflowDefinition({
    required this.id,
    required this.name,
    required this.doctype,
    required this.stateField,
    required this.enabled,
    required this.sendEmail,
    required this.states,
    required this.transitions,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String name;
  final String doctype;
  final String stateField;
  final bool enabled;
  final bool sendEmail;
  final List<WmnWorkflowState> states;
  final List<WmnWorkflowTransition> transitions;
  final Map<String, Object?> metadata;

  WmnWorkflowState? state(String name) {
    for (final state in states) {
      if (state.name == name) return state;
    }
    return null;
  }

  WmnWorkflowState? get initialState => states.isEmpty ? null : states.first;
}

class WmnWorkflowAction {
  const WmnWorkflowAction({
    required this.action,
    required this.nextState,
    this.allowedRole,
    this.condition,
  });

  final String action;
  final String nextState;
  final String? allowedRole;
  final String? condition;
}

/// Native WMN workflow and approval runtime.
///
/// Definitions load lazily by DocType into a bounded cache. Workflow state
/// changes, document lifecycle operations and action history share one outer
/// transaction so a failed hook/approval never leaves partial state behind.
class WmnWorkflowRuntime {
  WmnWorkflowRuntime({
    required this.database,
    required this.documents,
    required this.permissions,
    required this.identity,
    required this.events,
    WmnWorkflowConditionEngine? conditions,
    this.isFeatureEnabled,
  }) : conditions = conditions ?? WmnWorkflowConditionEngine() {
    _bindings.addAll(<WmnDocumentEventBinding>[
      events.on(
        doctype: '*',
        event: 'before_insert',
        priority: -80,
        handler: _beforeInsert,
      ),
      events.on(
        doctype: '*',
        event: 'validate',
        priority: -70,
        handler: _validateStateMutation,
      ),
      events.on(
        doctype: '*',
        event: 'before_update_after_submit',
        priority: -70,
        handler: _validateStateMutation,
      ),
      events.on(
        doctype: '*',
        event: 'before_submit',
        priority: -70,
        handler: _blockDirectSubmit,
      ),
      events.on(
        doctype: '*',
        event: 'before_cancel',
        priority: -70,
        handler: _blockDirectCancel,
      ),
    ]);
  }

  final WmnDatabase database;
  final WmnWorkflowDocumentGateway documents;
  final WmnPermissionService permissions;
  final WmnIdentityService identity;
  final WmnDocumentEventBus events;
  final WmnWorkflowConditionEngine conditions;
  final bool Function(String featureCode)? isFeatureEnabled;

  static const Uuid _uuid = Uuid();
  static const int _cacheLimit = 32;
  final Map<String, WmnWorkflowDefinition?> _cache =
      <String, WmnWorkflowDefinition?>{};
  final Set<String> _activeTransitions = <String>{};
  final List<WmnDocumentEventBinding> _bindings = <WmnDocumentEventBinding>[];
  int _loadCount = 0;

  int get debugLoadCount => _loadCount;
  bool get enabled => isFeatureEnabled?.call('workflow.approvals') ?? true;

  WmnWorkflowDefinition? workflowFor(String doctype) {
    if (!enabled) return null;
    final key = doctype.trim();
    if (_cache.containsKey(key)) return _cache[key];
    final loaded = _load(key);
    if (_cache.length >= _cacheLimit) _cache.remove(_cache.keys.first);
    _cache[key] = loaded;
    _loadCount += 1;
    return loaded;
  }

  void invalidate({String? doctype}) {
    if (doctype == null) {
      _cache.clear();
    } else {
      _cache.remove(doctype.trim());
    }
  }

  List<WmnWorkflowAction> availableActions(
    String doctype,
    Map<String, Object?> document,
  ) {
    final workflow = workflowFor(doctype);
    if (workflow == null) return const <WmnWorkflowAction>[];
    final docname = _docname(document);
    if (docname.isNotEmpty &&
        !permissions.hasPermission(
          doctype,
          'write',
          docname: docname,
          document: document,
        )) {
      return const <WmnWorkflowAction>[];
    }

    final stateName = _stateName(workflow, document);
    final roles = permissions.rolesFor().toSet();
    final result = <WmnWorkflowAction>[];
    for (final transition in workflow.transitions) {
      if (transition.state != stateName) continue;
      final role = transition.allowedRole?.trim() ?? '';
      if (role.isNotEmpty && !roles.contains(role)) continue;
      if (!conditions.evaluate(
        transition.condition,
        document,
        handlerKey: transition.conditionHandler,
        metadata: transition.metadata,
      )) {
        continue;
      }
      result.add(
        WmnWorkflowAction(
          action: transition.action,
          nextState: transition.nextState,
          allowedRole: transition.allowedRole,
          condition: transition.condition,
        ),
      );
    }
    return result;
  }

  bool canEdit(String doctype, Map<String, Object?> document) {
    final workflow = workflowFor(doctype);
    if (workflow == null) return true;
    final state = workflow.state(_stateName(workflow, document));
    final role = state?.allowEditRole?.trim() ?? '';
    return role.isEmpty || permissions.rolesFor().contains(role);
  }

  Map<String, Object?> applyAction(
    String doctype,
    String docname,
    String action, {
    String? comment,
  }) {
    if (!enabled) throw StateError('Workflow approvals feature is disabled.');
    final workflow = workflowFor(doctype);
    if (workflow == null) throw StateError('No enabled workflow for $doctype.');
    final document = documents.get(doctype, docname);
    if (document == null) throw StateError('$doctype $docname does not exist.');
    final fromState = _stateName(workflow, document);
    final allowed = availableActions(doctype, document)
        .where((entry) => entry.action == action)
        .toList(growable: false);
    if (allowed.isEmpty) {
      throw StateError('Workflow action $action is not allowed from $fromState.');
    }
    final transition = workflow.transitions.firstWhere(
      (entry) =>
          entry.state == fromState &&
          entry.action == action &&
          entry.nextState == allowed.first.nextState,
    );
    final targetState = workflow.state(transition.nextState);
    if (targetState == null) {
      throw StateError('Unknown workflow state: ${transition.nextState}.');
    }

    final guard = _guardKey(doctype, docname);
    return database.transaction(() {
      _activeTransitions.add(guard);
      try {
        events.emit(
          WmnDocumentEvent(
            doctype: doctype,
            event: 'before_workflow_action',
            operation: 'workflow',
            document: document,
            actor: identity.currentUser,
            metadata: <String, Object?>{
              'workflow': workflow.name,
              'action': action,
              'from_state': fromState,
              'to_state': targetState.name,
            },
          ),
        );

        final updated = <String, Object?>{
          ...document,
          workflow.stateField: targetState.name,
        };
        var saved = documents.save(doctype, docname, updated);
        final currentDocStatus = _intValue(document['docstatus']);
        if (targetState.docStatus == 1 && currentDocStatus == 0) {
          saved = documents.submit(doctype, docname);
        } else if (targetState.docStatus == 2 && currentDocStatus == 1) {
          saved = documents.cancel(doctype, docname);
        } else if (targetState.docStatus != currentDocStatus) {
          throw StateError(
            'Workflow transition cannot change docstatus from '
            '$currentDocStatus to ${targetState.docStatus}.',
          );
        }

        database.db.execute('''
          INSERT INTO wmn_workflow_actions(
            id,workflow_id,doctype,docname,action,from_state,to_state,
            user_id,status,comment,created_at
          ) VALUES (?,?,?,?,?,?,?,?,?,?,?);
        ''', <Object?>[
          _uuid.v4(),
          workflow.id,
          doctype,
          docname,
          action,
          fromState,
          targetState.name,
          identity.currentUser,
          'COMPLETED',
          comment,
          DateTime.now().toUtc().toIso8601String(),
        ]);

        events.emit(
          WmnDocumentEvent(
            doctype: doctype,
            event: 'after_workflow_action',
            operation: 'workflow',
            document: saved,
            previous: document,
            actor: identity.currentUser,
            metadata: <String, Object?>{
              'workflow': workflow.name,
              'action': action,
              'from_state': fromState,
              'to_state': targetState.name,
            },
          ),
        );
        return saved;
      } finally {
        _activeTransitions.remove(guard);
      }
    });
  }

  List<Map<String, Object?>> history(
    String doctype,
    String docname, {
    int limit = 100,
  }) {
    final safeLimit = limit.clamp(1, 500);
    return database.db
        .select('''
          SELECT id,workflow_id,doctype,docname,action,from_state,to_state,
                 user_id,status,comment,created_at
          FROM wmn_workflow_actions
          WHERE doctype=? AND docname=?
          ORDER BY created_at DESC,id DESC LIMIT ?;
        ''', <Object?>[doctype, docname, safeLimit])
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  void saveWorkflow({
    required String id,
    required String name,
    required String doctype,
    String stateField = 'workflow_state',
    bool enabled = true,
    bool sendEmail = false,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    _requireManage('Workflow');
    final existing = database.db.select(
      'SELECT doctype FROM wmn_workflows WHERE id=? LIMIT 1;',
      <Object?>[id],
    );
    final previousDoctype = existing.isEmpty ? null : '${existing.first['doctype']}';
    if (enabled) {
      final conflicts = database.db.select(
        'SELECT id,name FROM wmn_workflows '
        'WHERE doctype=? AND enabled=1 AND id<>? LIMIT 1;',
        <Object?>[doctype, id],
      );
      if (conflicts.isNotEmpty) {
        throw StateError(
          'Only one enabled workflow is allowed for $doctype. '
          'Disable ${conflicts.first['name']} first.',
        );
      }
    }
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO wmn_workflows(
        id,name,doctype,state_field,enabled,send_email,metadata_json,created_at,updated_at
      ) VALUES (?,?,?,?,?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET
        name=excluded.name,doctype=excluded.doctype,state_field=excluded.state_field,
        enabled=excluded.enabled,send_email=excluded.send_email,
        metadata_json=excluded.metadata_json,updated_at=excluded.updated_at;
    ''', <Object?>[
      id,name,doctype,stateField,enabled ? 1 : 0,sendEmail ? 1 : 0,
      jsonEncode(metadata),now,now,
    ]);
    if (previousDoctype != null && previousDoctype != doctype) {
      invalidate(doctype: previousDoctype);
    }
    invalidate(doctype: doctype);
  }

  void saveState({
    required String id,
    required String workflowId,
    required String stateName,
    int docStatus = 0,
    String? allowEditRole,
    int index = 0,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    _requireManage('Workflow State');
    final existing = database.db.select(
      'SELECT workflow_id FROM wmn_workflow_states WHERE id=? LIMIT 1;',
      <Object?>[id],
    );
    final previousWorkflowId =
        existing.isEmpty ? null : '${existing.first['workflow_id']}';
    database.db.execute('''
      INSERT INTO wmn_workflow_states(
        id,workflow_id,state_name,doc_status,allow_edit_role,idx,metadata_json
      ) VALUES (?,?,?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET
        workflow_id=excluded.workflow_id,state_name=excluded.state_name,
        doc_status=excluded.doc_status,allow_edit_role=excluded.allow_edit_role,
        idx=excluded.idx,metadata_json=excluded.metadata_json;
    ''', <Object?>[
      id,workflowId,stateName,docStatus,allowEditRole,index,jsonEncode(metadata),
    ]);
    if (previousWorkflowId != null && previousWorkflowId != workflowId) {
      _invalidateWorkflowId(previousWorkflowId);
    }
    _invalidateWorkflowId(workflowId);
  }

  void saveTransition({
    required String id,
    required String workflowId,
    required String stateName,
    required String action,
    required String nextState,
    String? allowedRole,
    String? condition,
    int index = 0,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    _requireManage('Workflow Transition');
    final existing = database.db.select(
      'SELECT workflow_id FROM wmn_workflow_transitions WHERE id=? LIMIT 1;',
      <Object?>[id],
    );
    final previousWorkflowId =
        existing.isEmpty ? null : '${existing.first['workflow_id']}';
    database.db.execute('''
      INSERT INTO wmn_workflow_transitions(
        id,workflow_id,state_name,action,next_state,allowed_role,
        condition_expression,idx,metadata_json
      ) VALUES (?,?,?,?,?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET
        workflow_id=excluded.workflow_id,state_name=excluded.state_name,
        action=excluded.action,next_state=excluded.next_state,
        allowed_role=excluded.allowed_role,condition_expression=excluded.condition_expression,
        idx=excluded.idx,metadata_json=excluded.metadata_json;
    ''', <Object?>[
      id,workflowId,stateName,action,nextState,allowedRole,condition,index,
      jsonEncode(metadata),
    ]);
    if (previousWorkflowId != null && previousWorkflowId != workflowId) {
      _invalidateWorkflowId(previousWorkflowId);
    }
    _invalidateWorkflowId(workflowId);
  }

  List<String> validateWorkflow(String doctype) {
    final workflow = workflowFor(doctype);
    if (workflow == null) return <String>['No enabled workflow for $doctype.'];
    final issues = <String>[];
    if (workflow.states.isEmpty) {
      issues.add('Workflow has no states.');
    } else if (workflow.initialState!.docStatus != 0) {
      issues.add('Workflow initial state must use docstatus 0.');
    }
    final names = workflow.states.map((state) => state.name).toSet();
    for (final transition in workflow.transitions) {
      if (!names.contains(transition.state)) {
        issues.add('Unknown source state: ${transition.state}.');
      }
      if (!names.contains(transition.nextState)) {
        issues.add('Unknown target state: ${transition.nextState}.');
      }
      if (!conditions.isSupported(
        transition.condition,
        handlerKey: transition.conditionHandler,
      )) {
        issues.add('Unsupported condition on action ${transition.action}.');
      }
    }
    return issues;
  }

  void dispose() {
    for (final binding in _bindings) {
      events.remove(binding);
    }
    _bindings.clear();
    _cache.clear();
  }

  WmnWorkflowDefinition? _load(String doctype) {
    final rows = database.db.select(
      'SELECT * FROM wmn_workflows WHERE doctype=? AND enabled=1 '
      'ORDER BY name COLLATE NOCASE LIMIT 2;',
      <Object?>[doctype],
    );
    if (rows.isEmpty) return null;
    if (rows.length > 1) {
      throw StateError(
        'Multiple enabled workflows found for $doctype. '
        'Only one enabled workflow is allowed per DocType.',
      );
    }
    final row = rows.first;
    final workflowId = '${row['id']}';
    final states = database.db
        .select(
          'SELECT * FROM wmn_workflow_states WHERE workflow_id=? '
          'ORDER BY idx,rowid;',
          <Object?>[workflowId],
        )
        .map(
          (state) => WmnWorkflowState(
            id: '${state['id']}',
            name: '${state['state_name']}',
            docStatus: _intValue(state['doc_status']),
            index: _intValue(state['idx']),
            allowEditRole: _nullable(state['allow_edit_role']),
          ),
        )
        .toList(growable: false);
    final transitions = database.db
        .select(
          'SELECT * FROM wmn_workflow_transitions WHERE workflow_id=? '
          'ORDER BY idx,rowid;',
          <Object?>[workflowId],
        )
        .map((transition) {
          final metadata = _decodeMap(transition['metadata_json']);
          return WmnWorkflowTransition(
            id: '${transition['id']}',
            state: '${transition['state_name']}',
            action: '${transition['action']}',
            nextState: '${transition['next_state']}',
            allowedRole: _nullable(transition['allowed_role']),
            condition: _nullable(transition['condition_expression']),
            conditionHandler: _nullable(metadata['condition_handler']),
            index: _intValue(transition['idx']),
            metadata: metadata,
          );
        })
        .toList(growable: false);
    return WmnWorkflowDefinition(
      id: workflowId,
      name: '${row['name']}',
      doctype: '${row['doctype']}',
      stateField: '${row['state_field'] ?? 'workflow_state'}',
      enabled: _intValue(row['enabled']) == 1,
      sendEmail: _intValue(row['send_email']) == 1,
      states: states,
      transitions: transitions,
      metadata: _decodeMap(row['metadata_json']),
    );
  }

  void _requireManage(String doctype) {
    if (permissions.hasSystemPermission('wmn.workflow.manage') ||
        permissions.hasPermission(doctype, 'write') ||
        permissions.hasPermission(doctype, 'create')) {
      return;
    }
    throw StateError('Not permitted to manage workflow metadata.');
  }

  void _invalidateWorkflowId(String workflowId) {
    final rows = database.db.select(
      'SELECT doctype FROM wmn_workflows WHERE id=? LIMIT 1;',
      <Object?>[workflowId],
    );
    if (rows.isNotEmpty) invalidate(doctype: '${rows.first['doctype']}');
  }

  void _beforeInsert(WmnDocumentEvent event) {
    final workflow = workflowFor(event.doctype);
    if (workflow == null) return;
    final initial = workflow.initialState;
    if (initial == null) {
      throw StateError('Workflow ${workflow.name} has no initial state.');
    }
    if (initial.docStatus != 0) {
      throw StateError('Workflow initial state must use docstatus 0.');
    }
    final requested = '${event.document[workflow.stateField] ?? ''}'.trim();
    if (requested.isNotEmpty && requested != initial.name) {
      throw StateError(
        'New documents must start in workflow state ${initial.name}.',
      );
    }
    event.document[workflow.stateField] = initial.name;
  }

  void _validateStateMutation(WmnDocumentEvent event) {
    final workflow = workflowFor(event.doctype);
    if (workflow == null) return;
    final current = _stateName(workflow, event.document);
    final configuredState = workflow.state(current);
    if (configuredState == null) {
      throw StateError('Unknown workflow state $current for ${event.doctype}.');
    }
    final docname = _docname(event.document);
    final guarded = docname.isNotEmpty &&
        _activeTransitions.contains(_guardKey(event.doctype, docname));
    if (!guarded && configuredState.docStatus != _intValue(event.document['docstatus'])) {
      throw StateError(
        'Workflow state $current requires docstatus ${configuredState.docStatus}.',
      );
    }
    final previous = event.previous;
    if (previous != null) {
      final before = _stateName(workflow, previous);
      if (before != current && !guarded) {
        throw StateError(
          'Workflow state cannot be changed directly. Use a workflow action.',
        );
      }
    }
    if (!guarded && !canEdit(event.doctype, event.document)) {
      throw StateError('Current workflow state does not allow this user to edit.');
    }
  }

  void _blockDirectSubmit(WmnDocumentEvent event) {
    final workflow = workflowFor(event.doctype);
    if (workflow == null) return;
    final docname = _docname(event.document);
    if (docname.isNotEmpty &&
        _activeTransitions.contains(_guardKey(event.doctype, docname))) {
      return;
    }
    throw StateError('Submit is controlled by workflow. Use a workflow action.');
  }

  void _blockDirectCancel(WmnDocumentEvent event) {
    final workflow = workflowFor(event.doctype);
    if (workflow == null) return;
    final docname = _docname(event.document);
    if (docname.isNotEmpty &&
        _activeTransitions.contains(_guardKey(event.doctype, docname))) {
      return;
    }
    throw StateError('Cancel is controlled by workflow. Use a workflow action.');
  }

  String _stateName(
    WmnWorkflowDefinition workflow,
    Map<String, Object?> document,
  ) {
    final value = '${document[workflow.stateField] ?? ''}'.trim();
    return value.isNotEmpty ? value : (workflow.initialState?.name ?? '');
  }

  static String _docname(Map<String, Object?> document) =>
      '${document['name'] ?? document['id'] ?? ''}'.trim();

  static String _guardKey(String doctype, String docname) => '$doctype::$docname';

  static int _intValue(Object? value) =>
      value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;

  static String? _nullable(Object? value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? null : text;
  }

  static Map<String, Object?> _decodeMap(Object? value) {
    final source = '${value ?? ''}'.trim();
    if (source.isEmpty) return <String, Object?>{};
    try {
      final decoded = jsonDecode(source);
      return decoded is Map
          ? Map<String, Object?>.from(decoded)
          : <String, Object?>{};
    } catch (_) {
      return <String, Object?>{};
    }
  }
}
