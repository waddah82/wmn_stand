import '../../core/audit/audit_service.dart';
import '../../core/database/wmn_database.dart';
import '../../core/documents/document_lifecycle.dart';
import '../../core/settings/settings_repository.dart';
import '../meta/meta_service.dart';
import '../model/document_service.dart';
import 'frappe_cache.dart';
import 'frappe_collaboration.dart';
import 'frappe_db_api.dart';
import 'frappe_defaults.dart';
import 'frappe_documents.dart';
import 'frappe_exceptions.dart';
import 'frappe_mapper.dart';
import 'frappe_messages.dart';
import 'frappe_hooks.dart';
import 'frappe_jobs.dart';
import 'frappe_meta_api.dart';
import 'frappe_methods.dart';
import 'frappe_naming.dart';
import 'frappe_permissions.dart';
import 'frappe_utils.dart';
import 'frappe_workflow.dart';
import 'frappe_query.dart';
import 'frappe_realtime.dart';
import 'frappe_session.dart';
import '../../platform/security/wmn_identity_service.dart';
import '../../platform/security/wmn_permission_service.dart';
import '../../platform/scripts/wmn_script_runtime.dart';
import '../../platform/workflow/wmn_workflow_condition_engine.dart';
import '../../platform/workflow/wmn_workflow_runtime.dart';

class WmnFrappeRuntime {
  WmnFrappeRuntime._({
    required this.identity,
    required this.security,
    required this.session,
    required this.permissions,
    required this.meta,
    required this.db,
    required this.defaults,
    required this.messages,
    required this.mapper,
    required this.naming,
    required this.hooks,
    required this.lifecycle,
    required this.documents,
    required this.cache,
    required this.methods,
    required this.jobs,
    required this.realtime,
    required this.collaboration,
    required this.workflow,
    required this.workflowRuntime,
    required this.query,
    required this.utils,
  });

  final WmnIdentityService identity;
  final WmnPermissionService security;
  final WmnFrappeSession session;
  final WmnFrappePermissionEngine permissions;
  final WmnFrappeMetaApi meta;
  final WmnFrappeDbApi db;
  final WmnFrappeDefaults defaults;
  final WmnFrappeMessageBus messages;
  final WmnFrappeDocumentMapper mapper;
  final WmnFrappeNamingEngine naming;
  final WmnFrappeHookRegistry hooks;
  final WmnDocumentLifecycleRuntime lifecycle;
  final WmnFrappeDocumentApi documents;
  final WmnFrappeCache cache;
  final WmnFrappeMethodRegistry methods;
  final WmnFrappeJobQueue jobs;
  final WmnFrappeRealtimeBus realtime;
  final WmnFrappeCollaborationService collaboration;
  final WmnFrappeWorkflowEngine workflow;
  final WmnWorkflowRuntime workflowRuntime;
  final WmnFrappeQueryEngine query;
  final WmnFrappeUtils utils;

  factory WmnFrappeRuntime.create({
    required WmnDatabase database,
    required SettingsRepository settings,
    required WmnMetaService metaService,
    required WmnDocumentService documentService,
    required AuditService audit,
    WmnIdentityService? identityService,
    WmnPermissionService? permissionService,
    WmnDocumentLifecycleRuntime? documentLifecycle,
    WmnWorkflowConditionEngine? workflowConditions,
    bool Function(String featureCode)? isFeatureEnabled,
    WmnScriptRuntime? scriptRuntime,
  }) {
    final identity = identityService ??
        WmnIdentityService(database: database, settings: settings);
    final security = permissionService ??
        WmnPermissionService(
          database: database,
          meta: metaService,
          identity: identity,
        );
    final session = WmnFrappeSession(identity: identity);
    final permissions = WmnFrappePermissionEngine(service: security);
    final meta = WmnFrappeMetaApi(metaService);
    final db = WmnFrappeDbApi(
      database: database,
      meta: metaService,
      documents: documentService,
      permissions: permissions,
      session: session,
    );
    final defaults = WmnFrappeDefaults(database: database, session: session);
    final messages = WmnFrappeMessageBus();
    final naming = WmnFrappeNamingEngine(database: database, meta: metaService);
    final hooks = WmnFrappeHookRegistry(database, scripts: scriptRuntime);
    final lifecycle = documentLifecycle ??
        WmnDocumentLifecycleRuntime(database: database);
    lifecycle.events.on(
      doctype: '*',
      event: '*',
      handler: (event) => hooks.emitDocument(
        event.doctype,
        event.event,
        event.document,
        previous: event.previous,
        operation: event.operation,
        actor: event.actor,
      ),
    );
    final documents = WmnFrappeDocumentApi(
      database: database,
      meta: metaService,
      documents: documentService,
      permissions: permissions,
      session: session,
      naming: naming,
      audit: audit,
      lifecycle: lifecycle,
    );
    final mapper = WmnFrappeDocumentMapper(documents: documents, meta: meta);
    final cache = WmnFrappeCache(database);
    final methods = WmnFrappeMethodRegistry(
      database: database,
      db: db,
      meta: meta,
      permissions: permissions,
      documents: documents,
      scripts: scriptRuntime,
    );
    hooks.attachMethodInvoker((method, args) => methods.call(method, args));
    final jobs = WmnFrappeJobQueue(database: database, methods: methods);
    final realtime = WmnFrappeRealtimeBus(database);
    final collaboration = WmnFrappeCollaborationService(database: database, permissions: permissions, session: session);
    final workflowRuntime = WmnWorkflowRuntime(
      database: database,
      documents: WmnFrappeWorkflowDocumentGateway(documents),
      permissions: security,
      identity: identity,
      events: lifecycle.events,
      conditions: workflowConditions,
      isFeatureEnabled: isFeatureEnabled,
    );
    final workflow = WmnFrappeWorkflowEngine(workflowRuntime);
    final query = WmnFrappeQueryEngine(db);
    final utils = WmnFrappeUtils(
      db: db,
      documents: documents,
      cache: cache,
      hooks: hooks,
      session: session,
      settings: settings,
      audit: audit,
    );
    return WmnFrappeRuntime._(
      identity: identity,
      security: security,
      session: session,
      permissions: permissions,
      meta: meta,
      db: db,
      defaults: defaults,
      messages: messages,
      mapper: mapper,
      naming: naming,
      hooks: hooks,
      lifecycle: lifecycle,
      documents: documents,
      cache: cache,
      methods: methods,
      jobs: jobs,
      realtime: realtime,
      collaboration: collaboration,
      workflow: workflow,
      workflowRuntime: workflowRuntime,
      query: query,
      utils: utils,
    );
  }


  Map<String, Object?>? getDoc(String doctype, String name) => documents.getDoc(doctype, name);
  Map<String, Object?>? getLazyDoc(String doctype, String name) => documents.getLazyDoc(doctype, name);
  Map<String, Object?> newDoc(String doctype, [Map<String, Object?> values = const {}]) => documents.newDoc(doctype, values);
  List<Map<String, Object?>> getList(String doctype, {List<String> fields = const [], Object? filters, int limit = 20}) =>
      db.getList(doctype, fields: fields, filters: filters, limit: limit);
  List<Map<String, Object?>> getAll(String doctype, {List<String> fields = const [], Object? filters, int limit = 500}) =>
      db.getAll(doctype, fields: fields, filters: filters, limit: limit);
  Map<String, Object?>? getMeta(String doctype) => meta.getMeta(doctype);
  bool hasPermission(String doctype, String action, {String? docname}) => permissions.hasPermission(doctype, action, docname: docname);
  List<String> getRoles([String? user]) => permissions.rolesFor(user);
  Object? call(String method, [Map<String, Object?> args = const {}]) => methods.call(method, args);
  String enqueue(String method, {Map<String, Object?> args = const {}, String queue = 'default'}) => jobs.enqueue(method, args: args, queue: queue);
  void publishRealtime(String event, Map<String, Object?> payload) => realtime.publish(event, payload);
  Object? getValue(String doctype, Object selector, Object fields) => db.getValue(doctype, selector, fields);
  Object? getSingleValue(String doctype, String fieldname) => db.getSingleValue(doctype, fieldname);
  Map<String, Object?> setValue(String doctype, String name, Object fields, [Object? value]) => db.setValue(doctype, name, fields, value);
  void setSingleValue(String doctype, String fieldname, Object? value) => db.setSingleValue(doctype, fieldname, value);
  bool exists(String doctype, Object selector) => db.exists(doctype, selector);
  int count(String doctype, {Object? filters}) => db.count(doctype, filters: filters);
  Map<String, Object?> copyDoc(String doctype, String name) => documents.copyDoc(doctype, name);
  void deleteDoc(String doctype, String name) => documents.deleteDoc(doctype, name);
  Object? getCachedValue(String doctype, Object selector, String field) => utils.getCachedValue(doctype, selector, field);
  Map<String, Object?>? getCachedDoc(String doctype, String name) => utils.getCachedDoc(doctype, name);
  String scrub(String value) => utils.scrub(value);
  String bold(Object? value) => utils.bold(value);
  String generateHash([int length = 12]) => utils.generateHash(length);
  void setUser(String user) => utils.setUser(user);
  Map<String, Object?> getSingle(String doctype) => db.getSingle(doctype);
  List<Map<String, Object?>> getValues(String doctype, Object? filters, Object fields, {int limit = 500}) =>
      db.getValues(doctype, filters, fields, limit: limit);
  Map<String, Object?>? getLastDoc(String doctype, {Object? filters, String orderBy = 'modified desc'}) =>
      db.getLastDoc(doctype, filters: filters, orderBy: orderBy);
  int getPrecision(String doctype, String fieldname, {int fallback = 2}) => meta.getPrecision(doctype, fieldname, fallback: fallback);
  Object? getDefault(String key, {String? user}) => defaults.getDefault(key, user: user);
  Object? getGlobalDefault(String key) => defaults.getGlobalDefault(key);
  void setDefault(String key, Object? value, {String? user}) => defaults.setDefault(key, value, user: user);
  WmnFrappeMessage msgprint(Object? message, {String? title, String? indicator}) =>
      messages.msgprint(message, title: title, indicator: indicator);
  Never throwValidation(Object? message) => throw WmnFrappeValidationException('${message ?? ''}');

  List<WmnFrappeHookBinding> getHooks({String? hookType, String? doctype, String? event}) =>
      hooks.bindings(hookType: hookType, doctype: doctype, event: event);

  Map<String, Object?> bootInfo() {
    final roles = permissions.rolesFor();
    return session.boot(roles: roles, capabilities: permissions.capabilities());
  }

  List<Map<String, Object?>> apiCoverage() {
    final rows = db.database.db.select(
      'SELECT source_api,family,target_api,status,source_hits,notes FROM wmn_frappe_api_coverage ORDER BY source_hits DESC,source_api;',
    );
    return rows.map((row) => Map<String, Object?>.from(row)).toList(growable: false);
  }
}
