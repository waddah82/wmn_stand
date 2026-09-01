import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/audit/audit_service.dart';
import 'package:wmn_standalone/core/database/wmn_database.dart';
import 'package:wmn_standalone/core/documents/document_registry.dart';
import 'package:wmn_standalone/core/settings/settings_repository.dart';
import 'package:wmn_standalone/framework/frappe_compat/frappe_runtime.dart';
import 'package:wmn_standalone/framework/meta/doctype_meta.dart';
import 'package:wmn_standalone/framework/meta/meta_service.dart';
import 'package:wmn_standalone/framework/model/document_service.dart';
import 'package:wmn_standalone/modules/customization/data/customization_repository.dart';
import 'package:wmn_standalone/platform/workflow/wmn_workflow_condition_engine.dart';

void main() {
  late WmnDatabase database;
  late WmnMetaService meta;
  late WmnFrappeRuntime runtime;
  late WmnWorkflowConditionRegistry workflowConditionRegistry;

  setUp(() {
    database = WmnDatabase.forTesting(sqlite3.openInMemory());
    final audit = AuditService(database);
    final settings = SettingsRepository(database);
    final registry = WmnDocumentRegistry(database);
    final customization = CustomizationRepository(database);
    meta = WmnMetaService(
      database: database,
      registry: registry,
      customization: customization,
    );
    final documents = WmnDocumentService(
      database: database,
      meta: meta,
      customization: customization,
      audit: audit,
    );
    workflowConditionRegistry = WmnWorkflowConditionRegistry();
    final workflowConditions = WmnWorkflowConditionEngine(
      registry: workflowConditionRegistry,
    );
    runtime = WmnFrappeRuntime.create(
      database: database,
      settings: settings,
      metaService: meta,
      documentService: documents,
      audit: audit,
      workflowConditions: workflowConditions,
    );

    meta.saveDocType(
      name: 'Approval Note',
      module: 'Demo',
      titleField: 'title',
      autoname: 'format:APR-.#####',
      isSubmittable: true,
    );
    meta.saveField(
      doctype: 'Approval Note',
      fieldName: 'title',
      label: 'Title',
      fieldType: 'Data',
      required: true,
    );
    meta.saveField(
      doctype: 'Approval Note',
      fieldName: 'amount',
      label: 'Amount',
      fieldType: 'Currency',
    );
    meta.saveField(
      doctype: 'Approval Note',
      fieldName: 'workflow_state',
      label: 'Workflow State',
      fieldType: 'Data',
      allowOnSubmit: true,
    );
  });

  tearDown(() => database.close());

  void configureWorkflow({String? condition}) {
    runtime.workflow.saveWorkflow(
      id: 'approval-note-workflow',
      name: 'Approval Note Workflow',
      doctype: 'Approval Note',
    );
    runtime.workflow.saveState(
      id: 'approval-draft',
      workflowId: 'approval-note-workflow',
      stateName: 'Draft',
      allowEditRole: 'System Manager',
      index: 0,
    );
    runtime.workflow.saveState(
      id: 'approval-approved',
      workflowId: 'approval-note-workflow',
      stateName: 'Approved',
      docStatus: 1,
      allowEditRole: 'System Manager',
      index: 10,
    );
    runtime.workflow.saveTransition(
      id: 'approval-transition',
      workflowId: 'approval-note-workflow',
      stateName: 'Draft',
      action: 'Approve',
      nextState: 'Approved',
      allowedRole: 'System Manager',
      condition: condition,
      index: 10,
    );
  }



  test('Workflow list settings never select the hidden id field', () {
    final workflow = meta.doctype('Workflow')!;
    expect(workflow.field('id')?.hidden, isTrue);

    final defaults = meta.listViewSettings('Workflow');
    expect(defaults.sortField, 'name');

    // Simulate an older installation that persisted the physical hidden ID
    // as the selected sort field. Reading settings must normalize it before
    // the value reaches DropdownButtonFormField.
    meta.saveListViewSettings(
      'Workflow',
      const WmnListViewSettings(sortField: 'id', sortDescending: true),
    );
    final normalized = meta.listViewSettings('Workflow');
    expect(normalized.sortField, 'name');
    final visibleSortFields = workflow.fields
        .where((field) => !field.hidden && !field.isLayout)
        .map((field) => field.fieldName)
        .toSet();
    expect(visibleSortFields.contains(normalized.sortField), isTrue);
  });

  test('workflow condition registry is the injected runtime registry', () {
    expect(
      runtime.workflowRuntime.conditions.registry,
      same(workflowConditionRegistry),
    );
  });

  test('workflow metadata is exposed as System DocTypes and commercial feature', () {
    final doctypes = database.db
        .select(
          "SELECT name FROM wmn_doctypes WHERE name LIKE 'Workflow%' ORDER BY name;",
        )
        .map((row) => '${row['name']}')
        .toSet();
    expect(
      doctypes,
      containsAll(<String>{
        'Workflow',
        'Workflow State',
        'Workflow Transition',
        'Workflow Action',
      }),
    );
    final feature = database.db.select(
      "SELECT code FROM wmn_features WHERE code='workflow.approvals';",
    );
    expect(feature, isNotEmpty);
  });

  test('new documents cannot bypass the initial workflow state', () {
    configureWorkflow();
    expect(
      () => runtime.documents.insert('Approval Note', <String, Object?>{
        'title': 'Bypass attempt',
        'amount': 150,
        'workflow_state': 'Approved',
      }),
      throwsStateError,
    );
    expect(runtime.count('Approval Note'), 0);
  });

  test('workflow states with equal indexes preserve insertion order', () {
    runtime.workflow.saveWorkflow(
      id: 'equal-index-workflow',
      name: 'Equal Index Workflow',
      doctype: 'Approval Note',
    );
    runtime.workflow.saveState(
      id: 'z-draft-state',
      workflowId: 'equal-index-workflow',
      stateName: 'Draft',
    );
    runtime.workflow.saveState(
      id: 'a-approved-state',
      workflowId: 'equal-index-workflow',
      stateName: 'Approved',
      docStatus: 1,
    );

    final workflow = runtime.workflowRuntime.workflowFor('Approval Note');
    expect(workflow?.initialState?.name, 'Draft');
    expect(workflow?.initialState?.docStatus, 0);
  });

  test('only one enabled workflow is allowed per DocType', () {
    configureWorkflow();
    expect(
      () => runtime.workflow.saveWorkflow(
        id: 'approval-note-workflow-2',
        name: 'Second Approval Note Workflow',
        doctype: 'Approval Note',
      ),
      throwsStateError,
    );
  });

  test('workflow owns initial state and blocks direct state or submit bypasses', () {
    configureWorkflow();
    final created = runtime.documents.insert('Approval Note', <String, Object?>{
      'title': 'Controlled',
      'amount': 10,
    });
    final name = '${created['name']}';
    expect(created['workflow_state'], 'Draft');

    expect(
      () => runtime.documents.save(
        'Approval Note',
        name,
        <String, Object?>{'workflow_state': 'Approved'},
      ),
      throwsStateError,
    );
    expect(
      () => runtime.documents.submit('Approval Note', name),
      throwsStateError,
    );
    expect(runtime.getDoc('Approval Note', name)?['workflow_state'], 'Draft');
    expect(runtime.getDoc('Approval Note', name)?['docstatus'], 0);
  });

  test('safe declarative conditions gate approval actions without script execution', () {
    configureWorkflow(
      condition: '{"field":"amount","op":"gte","value":100}',
    );
    final created = runtime.documents.insert('Approval Note', <String, Object?>{
      'title': 'Conditional',
      'amount': 20,
    });
    final name = '${created['name']}';
    expect(runtime.workflow.availableActions('Approval Note', created), isEmpty);

    final updated = runtime.documents.save(
      'Approval Note',
      name,
      <String, Object?>{'amount': 120},
    );
    expect(
      runtime.workflow.availableActions('Approval Note', updated).map((entry) => entry.action),
      contains('Approve'),
    );

    final conditions = WmnWorkflowConditionEngine();
    expect(
      conditions.evaluate('amount > 100', <String, Object?>{'amount': 120}),
      isFalse,
    );
  });

  test('approval transition submits atomically and records history', () {
    configureWorkflow();
    final created = runtime.documents.insert('Approval Note', <String, Object?>{
      'title': 'Approve me',
      'amount': 150,
    });
    final name = '${created['name']}';
    final approved = runtime.workflow.applyAction(
      'Approval Note',
      name,
      'Approve',
      comment: 'Reviewed',
    );

    expect(approved['workflow_state'], 'Approved');
    expect(approved['docstatus'], 1);
    final history = runtime.workflow.history('Approval Note', name);
    expect(history, hasLength(1));
    expect(history.first['action'], 'Approve');
    expect(history.first['from_state'], 'Draft');
    expect(history.first['to_state'], 'Approved');
    expect(history.first['comment'], 'Reviewed');
  });

  test('failed after-workflow hook rolls back document state and action history', () {
    configureWorkflow();
    final created = runtime.documents.insert('Approval Note', <String, Object?>{
      'title': 'Rollback approval',
      'amount': 150,
    });
    final name = '${created['name']}';
    final binding = runtime.lifecycle.events.on(
      doctype: 'Approval Note',
      event: 'after_workflow_action',
      handler: (_) => throw StateError('approval extension failed'),
    );
    addTearDown(() => runtime.lifecycle.events.remove(binding));

    expect(
      () => runtime.workflow.applyAction('Approval Note', name, 'Approve'),
      throwsStateError,
    );
    final stored = runtime.getDoc('Approval Note', name)!;
    expect(stored['workflow_state'], 'Draft');
    expect(stored['docstatus'], 0);
    expect(runtime.workflow.history('Approval Note', name), isEmpty);
  });

  test('workflow definitions are lazy cached until invalidated', () {
    configureWorkflow();
    final native = runtime.workflowRuntime;
    final before = native.debugLoadCount;
    expect(native.workflowFor('Approval Note'), isNotNull);
    expect(native.workflowFor('Approval Note'), isNotNull);
    expect(native.debugLoadCount, before + 1);
    native.invalidate(doctype: 'Approval Note');
    expect(native.workflowFor('Approval Note'), isNotNull);
    expect(native.debugLoadCount, before + 2);
  });
}
