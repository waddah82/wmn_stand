import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/audit/audit_service.dart';
import 'package:wmn_standalone/core/database/wmn_database.dart';
import 'package:wmn_standalone/core/documents/document_registry.dart';
import 'package:wmn_standalone/core/settings/settings_repository.dart';
import 'package:wmn_standalone/framework/frappe_compat/frappe_runtime.dart';
import 'package:wmn_standalone/framework/frappe_compat/frappe_method_management.dart';
import 'package:wmn_standalone/framework/meta/meta_service.dart';
import 'package:wmn_standalone/framework/model/document_service.dart';
import 'package:wmn_standalone/modules/customization/application/script_engine.dart';
import 'package:wmn_standalone/modules/customization/data/customization_repository.dart';

void main() {
  late WmnDatabase database;
  late WmnMetaService meta;
  late WmnFrappeRuntime runtime;
  late WmnDocumentRegistry registry;
  late WmnDocumentService documents;

  setUp(() {
    database = WmnDatabase.forTesting(sqlite3.openInMemory());
    final audit = AuditService(database);
    final settings = SettingsRepository(database);
    registry = WmnDocumentRegistry(database);
    final customization = CustomizationRepository(database);
    meta = WmnMetaService(database: database, registry: registry, customization: customization);
    documents = WmnDocumentService(database: database, meta: meta, customization: customization, audit: audit);
    runtime = WmnFrappeRuntime.create(
      database: database,
      settings: settings,
      metaService: meta,
      documentService: documents,
      audit: audit,
    );

    meta.saveDocType(
      name: 'Demo Note',
      module: 'Demo',
      titleField: 'title',
      autoname: 'format:DEMO-.#####',
      isSubmittable: true,
    );
    meta.saveField(doctype: 'Demo Note', fieldName: 'title', label: 'Title', fieldType: 'Data', required: true, inListView: true, searchable: true);
    meta.saveField(doctype: 'Demo Note', fieldName: 'amount', label: 'Amount', fieldType: 'Currency');
    meta.saveField(doctype: 'Demo Note', fieldName: 'workflow_state', label: 'Workflow State', fieldType: 'Data');
  });

  tearDown(() => database.close());

  test('DocTypes materialize as physical tab tables and legacy JSON store is absent', () {
    final metaRow = database.db.select(
      "SELECT storage_mode,table_name,id_field FROM wmn_doctypes WHERE name='Demo Note';",
    ).first;
    expect(metaRow['storage_mode'], 'TABLE');
    expect(metaRow['table_name'], 'tabDemo Note');
    expect(metaRow['id_field'], 'name');
    expect(
      database.db.select("SELECT name FROM sqlite_master WHERE type='table' AND name='tabDemo Note';"),
      isNotEmpty,
    );
    expect(
      database.db.select("SELECT name FROM sqlite_master WHERE type='table' AND name='wmn_dynamic_documents';"),
      isEmpty,
    );
  });

  test('required fields fail in the document layer before SQLite constraints', () {
    expect(
      () => documents.save('Demo Note', {'amount': 10}),
      throwsA(isA<StateError>().having((error) => error.toString(), 'message', contains('Title'))),
    );

    final saved = documents.save('Demo Note', {
      'title': 'Validated document',
      'amount': 10,
    });
    expect(saved['name'], startsWith('DEMO-'));
    expect(saved['title'], 'Validated document');
    expect(
      database.db.select('SELECT title FROM [tabDemo Note] WHERE name=?;', [saved['name']]).first['title'],
      'Validated document',
    );
  });

  test('child DocTypes persist in their own tab tables with Frappe parent columns', () {
    meta.saveDocType(name: 'Demo Note Line', module: 'Demo', isChild: true);
    meta.saveField(
      doctype: 'Demo Note Line',
      fieldName: 'description',
      label: 'Description',
      fieldType: 'Data',
      required: true,
      inListView: true,
    );
    meta.saveField(
      doctype: 'Demo Note',
      fieldName: 'lines',
      label: 'Lines',
      fieldType: 'Table',
      options: 'Demo Note Line',
    );

    final inserted = runtime.documents.insert('Demo Note', {
      'title': 'Parent with lines',
      'lines': [
        {'description': 'Line A'},
        {'description': 'Line B'},
      ],
    });
    final name = '${inserted['name']}';
    final storedLines = database.db.select(
      'SELECT description,parent,parenttype,parentfield,idx FROM [tabDemo Note Line] WHERE parent=? ORDER BY idx;',
      [name],
    );
    expect(storedLines.length, 2);
    expect(storedLines.first['parenttype'], 'Demo Note');
    expect(storedLines.first['parentfield'], 'lines');
    expect(storedLines.first['idx'], 1);
    expect((runtime.getDoc('Demo Note', name)?['lines'] as List).length, 2);
  });

  test('Frappe-compatible Document and DB APIs are native WMN operations', () {
    final local = runtime.newDoc('Demo Note', {'title': 'Alpha', 'amount': 10});
    expect(local['__islocal'], isTrue);

    final inserted = runtime.documents.insert('Demo Note', local);
    final name = '${inserted['name']}';
    expect(name, startsWith('DEMO-'));
    expect(runtime.getDoc('Demo Note', name)?['title'], 'Alpha');
    expect(runtime.getDoc('Demo Note', name)?['owner'], 'Administrator');
    expect(runtime.getDoc('Demo Note', name)?['modified_by'], 'Administrator');
    expect(runtime.db.getValue('Demo Note', name, 'amount')?['amount'], 10);
    expect(runtime.db.exists('Demo Note', name), isTrue);
    expect(runtime.db.count('Demo Note'), 1);

    runtime.db.setValue('Demo Note', name, 'amount', 25);
    expect(runtime.db.getValue('Demo Note', name, 'amount')?['amount'], 25);

    final submitted = runtime.documents.submit('Demo Note', name);
    expect(submitted['docstatus'], 1);
    final cancelled = runtime.documents.cancel('Demo Note', name);
    expect(cancelled['docstatus'], 2);
    expect(runtime.documents.versions('Demo Note', name).length, greaterThanOrEqualTo(3));
  });

  test('workflow engine applies role-checked transitions through document lifecycle', () {
    runtime.workflow.saveWorkflow(
      id: 'demo-workflow',
      name: 'Demo Note Approval',
      doctype: 'Demo Note',
    );
    runtime.workflow.saveState(
      id: 'demo-draft',
      workflowId: 'demo-workflow',
      stateName: 'Draft',
    );
    runtime.workflow.saveState(
      id: 'demo-approved',
      workflowId: 'demo-workflow',
      stateName: 'Approved',
      docStatus: 1,
    );
    runtime.workflow.saveTransition(
      id: 'demo-approve',
      workflowId: 'demo-workflow',
      stateName: 'Draft',
      action: 'Approve',
      nextState: 'Approved',
      allowedRole: 'System Manager',
    );

    final inserted = runtime.documents.insert('Demo Note', {
      'title': 'Workflow',
      'amount': 20,
      'workflow_state': 'Draft',
    });
    final name = '${inserted['name']}';
    expect(runtime.workflow.availableActions('Demo Note', inserted).map((entry) => entry.action), contains('Approve'));
    final approved = runtime.workflow.applyAction('Demo Note', name, 'Approve');
    expect(approved['workflow_state'], 'Approved');
    expect(approved['docstatus'], 1);
    expect(runtime.workflow.history('Demo Note', name), isNotEmpty);
  });

  test('method registry, cache, jobs and realtime are runtime services', () {
    runtime.cache.set('demo', {'ok': true});
    expect((runtime.cache.get('demo') as Map)['ok'], isTrue);

    runtime.methods.register('demo.echo', (args) => {'value': args['value']});
    expect((runtime.call('demo.echo', {'value': 7}) as Map)['value'], 7);

    final job = runtime.enqueue('demo.echo', args: {'value': 8});
    expect(job, isNotEmpty);
    final result = runtime.jobs.runNext();
    expect(result?['status'], 'SUCCESS');

    runtime.publishRealtime('demo_event', {'value': 9});
    final events = database.db.select("SELECT COUNT(*) AS value FROM wmn_realtime_events WHERE event_name='demo_event';");
    expect(events.first['value'], 1);
  });

  test('global safe CRUD functions stay lifecycle-safe and Method means a code module', () {
    final created = runtime.call('wmn.db.insert', {
      'table': 'tabDemo Note',
      'values': {'title': 'Method Insert', 'amount': 11},
    }) as Map;
    final name = '${created['name']}';
    expect(name, startsWith('DEMO-'));
    expect(runtime.getDoc('Demo Note', name)?['amount'], 11);

    runtime.call('wmn.db.update', {
      'doctype': 'Demo Note',
      'name': name,
      'values': {'amount': 22},
    });
    expect(runtime.getDoc('Demo Note', name)?['amount'], 22);

    final management = WmnMethodManagementService(database: database, meta: meta);
    final nativeModules = management.systemMethodModules(runtime.methods.catalog());
    final dbModule = nativeModules.firstWhere((entry) => entry.name == 'wmn.db');
    expect(dbModule.exports, containsAll(<String>['insert', 'update', 'delete']));

    final module = management.saveCustomMethodModule(
      name: 'custom.sales.tools',
      source: '''
function create_document(args) {
  return wmn.document.insert(args);
}

function update_document(args) {
  return wmn.document.update(args);
}
''',
      description: 'Global server code module equivalent to a Frappe Python file',
      supportedApis: runtime.methods.catalog().map((row) => '${row['method_name']}').toSet(),
    );
    expect(module.name, 'custom.sales.tools');
    expect(module.status, 'VALIDATED');
    expect(module.enabled, isFalse);
    expect(module.exports, containsAll(<String>['create_document', 'update_document']));
    expect(module.dependencies, contains('wmn.document'));
    expect(
      database.db.select('SELECT reference_doctype,target_kind FROM wmn_hook_bindings WHERE id=?;', [module.id]).first['reference_doctype'],
      isNull,
    );
    expect(
      database.db.select('SELECT target_kind FROM wmn_hook_bindings WHERE id=?;', [module.id]).first['target_kind'],
      'METHOD',
    );
    final methodStorageRow = database.db.select(
      'SELECT source_path,metadata_json FROM wmn_hook_bindings WHERE id=?;',
      [module.id],
    ).first;
    final methodSourcePath = '${methodStorageRow['source_path']}';
    expect(methodSourcePath, startsWith('apps/custom/methods/'));
    expect(management.storage.exists(methodSourcePath), isTrue);
    expect(management.storage.readText(methodSourcePath), contains('function create_document'));
    expect('${methodStorageRow['metadata_json']}', isNot(contains('"source":')));

    runtime.call('wmn.db.delete', {'table': 'tabDemo Note', 'name': name});
    expect(runtime.getDoc('Demo Note', name), isNull);
  });

  test('custom system scripts are global validated drafts and are not DocType owned', () {
    final management = WmnMethodManagementService(database: database, meta: meta);
    final script = management.saveCustomSystemScript(
      name: 'custom.system.demo_script',
      source: 'wmn.document.insert({doctype: "Demo Note", values: {title: "Global"}});',
      description: 'Global script draft',
      supportedApis: runtime.methods.catalog().map((row) => '${row['method_name']}').toSet(),
    );
    expect(script.name, 'custom.system.demo_script');
    expect(script.status, 'VALIDATED');
    expect(script.enabled, isFalse);
    expect(script.revision, 1);
    expect(
      database.db.select('SELECT reference_doctype FROM wmn_hook_bindings WHERE id=?;', [script.id]).first['reference_doctype'],
      isNull,
    );
    final scriptStorageRow = database.db.select(
      'SELECT source_path,metadata_json FROM wmn_hook_bindings WHERE id=?;',
      [script.id],
    ).first;
    final scriptSourcePath = '${scriptStorageRow['source_path']}';
    expect(scriptSourcePath, startsWith('apps/custom/scripts/system/'));
    expect(management.storage.exists(scriptSourcePath), isTrue);
    expect(management.storage.readText(scriptSourcePath), contains('wmn.document.insert'));
    expect('${scriptStorageRow['metadata_json']}', isNot(contains('"source":')));
  });

  test('clean platform uses Dart metadata conditions without a JavaScript runtime', () {
    final engine = WmnScriptEngine(registry: registry, frappeRuntime: runtime);
    expect(engine.executionEnabled, isFalse);
    expect(
      engine.evaluateCondition(
        expression: 'eval:doc.amount >= 10 && doc.title != ""',
        document: const {'amount': 15, 'title': 'Runtime'},
      ),
      isTrue,
    );
  });

  test('coverage matrix exposes native Frappe API equivalents', () {
    final coverage = runtime.apiCoverage();
    expect(coverage.any((row) => row['source_api'] == 'frappe.get_doc' && row['status'] == 'NATIVE'), isTrue);
    expect(coverage.any((row) => row['source_api'] == 'frappe.db.sql' && row['status'] == 'PARTIAL'), isTrue);
    expect(coverage.any((row) => row['source_api'] == 'frappe.provide' && row['status'] == 'PENDING'), isTrue);
  });
  test('DocType Manager metadata supports custom create edit field delete and physical cleanup', () {
    final created = meta.saveDocType(
      name: 'Managed Doc',
      module: 'Custom',
      titleField: 'subject',
      autoname: 'field:subject',
      isSubmittable: true,
      allowImport: false,
      allowExport: true,
    );
    expect(created.tableName, 'tabManaged Doc');
    expect(created.idField, 'name');
    expect(created.allowImport, isFalse);

    meta.saveField(
      doctype: 'Managed Doc',
      fieldName: 'subject',
      label: 'Subject',
      fieldType: 'Data',
      required: true,
      inListView: true,
      searchable: true,
    );
    meta.saveField(
      doctype: 'Managed Doc',
      fieldName: 'notes',
      label: 'Notes',
      fieldType: 'Small Text',
    );
    expect(
      database.db.select("PRAGMA table_info([tabManaged Doc]);").map((row) => row['name']),
      containsAll(['name', 'subject', 'notes']),
    );

    final inserted = documents.save('Managed Doc', {'subject': 'MD-001', 'notes': 'First'});
    expect(inserted['name'], 'MD-001');
    final updated = documents.save('Managed Doc', {'subject': 'MD-001', 'notes': 'Updated'}, existingName: 'MD-001');
    expect(updated['notes'], 'Updated');

    meta.deleteField('Managed Doc', 'notes');
    expect(meta.fields('Managed Doc').any((field) => field.fieldName == 'notes'), isFalse);
    expect(
      database.db.select("PRAGMA table_info([tabManaged Doc]);").map((row) => row['name']),
      isNot(contains('notes')),
    );

    documents.delete('Managed Doc', 'MD-001');
    expect(documents.exists('Managed Doc', 'MD-001'), isFalse);
    meta.deleteDocType('Managed Doc');
    expect(meta.doctype('Managed Doc'), isNull);
    expect(database.db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='tabManaged Doc';"), isEmpty);
  });

  test('submitted generic documents only allow fields marked allow_on_submit and must cancel before delete', () {
    meta.saveField(
      doctype: 'Demo Note',
      fieldName: 'after_submit_note',
      label: 'After Submit Note',
      fieldType: 'Data',
      allowOnSubmit: true,
    );
    final inserted = documents.save('Demo Note', {'title': 'Lifecycle', 'amount': 10});
    final name = '${inserted['name']}';
    final submitted = documents.submit('Demo Note', name);
    expect(submitted['docstatus'], 1);

    expect(
      () => documents.save('Demo Note', {'title': 'Changed'}, existingName: name),
      throwsA(isA<StateError>()),
    );
    final allowed = documents.save(
      'Demo Note',
      {...submitted, 'after_submit_note': 'Allowed'},
      existingName: name,
    );
    expect(allowed['after_submit_note'], 'Allowed');
    expect(() => documents.delete('Demo Note', name), throwsA(isA<StateError>()));

    final cancelled = documents.cancel('Demo Note', name);
    expect(cancelled['docstatus'], 2);
    expect(
      () => documents.save('Demo Note', {...cancelled, 'after_submit_note': 'No longer editable'}, existingName: name),
      throwsStateError,
    );
    documents.delete('Demo Note', name);
    expect(documents.exists('Demo Note', name), isFalse);
  });

  test('Single DocTypes use tabSingles and remain one logical document', () {
    final settings = meta.saveDocType(
      name: 'Demo Settings',
      module: 'Demo',
      isSingle: true,
      isSubmittable: true,
      allowImport: true,
    );
    expect(settings.isSingle, isTrue);
    expect(settings.isSubmittable, isFalse);
    expect(settings.allowImport, isFalse);
    expect(settings.tableName, 'tabSingles');
    expect(
      database.db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='tabDemo Settings';"),
      isEmpty,
    );

    meta.saveField(
      doctype: 'Demo Settings',
      fieldName: 'enabled',
      label: 'Enabled',
      fieldType: 'Check',
      defaultValue: 0,
    );
    meta.saveField(
      doctype: 'Demo Settings',
      fieldName: 'note',
      label: 'Note',
      fieldType: 'Data',
    );

    final saved = runtime.documents.save(
      'Demo Settings',
      'Demo Settings',
      {'enabled': 1, 'note': 'Native Single'},
    );
    expect(saved['name'], 'Demo Settings');
    expect(saved['enabled'], 1);
    expect(saved['note'], 'Native Single');
    expect(
      database.db.select("SELECT value FROM [tabSingles] WHERE doctype='Demo Settings' AND field='note';").first['value'],
      '"Native Single"',
    );
    expect(registry.readDocument('Demo Settings', 'Demo Settings')?['note'], 'Native Single');
    expect(registry.count('Demo Settings'), 1);

    runtime.db.setSingleValue('Demo Settings', 'note', 'Changed');
    expect(runtime.db.getSingle('Demo Settings')['note'], 'Changed');
    expect(runtime.db.getSingleValue('Demo Settings', 'note'), 'Changed');
  });

  test('child table synchronization preserves retained child row names', () {
    meta.saveDocType(name: 'Stable Line', module: 'Demo', isChild: true);
    meta.saveField(
      doctype: 'Stable Line',
      fieldName: 'description',
      label: 'Description',
      fieldType: 'Data',
      required: true,
    );
    meta.saveField(
      doctype: 'Demo Note',
      fieldName: 'stable_lines',
      label: 'Stable Lines',
      fieldType: 'Table',
      options: 'Stable Line',
    );

    final inserted = runtime.documents.insert('Demo Note', {
      'title': 'Stable children',
      'stable_lines': [
        {'description': 'Keep me'},
      ],
    });
    final parentName = '${inserted['name']}';
    final first = (runtime.getDoc('Demo Note', parentName)!['stable_lines'] as List).single as Map;
    final childName = '${first['name']}';

    runtime.documents.save('Demo Note', parentName, {
      ...inserted,
      'stable_lines': [
        {...Map<String, Object?>.from(first), 'description': 'Updated'},
        {'description': 'New row'},
      ],
    });
    final after = runtime.getDoc('Demo Note', parentName)!['stable_lines'] as List;
    expect(after.length, 2);
    expect((after.first as Map)['name'], childName);
    expect((after.first as Map)['description'], 'Updated');
  });

  test('document hooks follow Frappe save submit and update-after-submit phases', () {
    meta.saveField(
      doctype: 'Demo Note',
      fieldName: 'after_submit_note',
      label: 'After Submit Note',
      fieldType: 'Data',
      allowOnSubmit: true,
    );
    final events = <String>[];
    for (final event in ['before_insert', 'before_validate', 'validate', 'before_save', 'after_insert', 'on_update']) {
      runtime.hooks.onDocument('Demo Note', event, (_) => events.add(event));
    }
    final inserted = runtime.documents.insert('Demo Note', {'title': 'Hook Order'});
    expect(events, ['before_insert', 'before_validate', 'validate', 'before_save', 'after_insert', 'on_update']);

    events.clear();
    for (final event in ['before_submit', 'on_submit']) {
      runtime.hooks.onDocument('Demo Note', event, (_) => events.add(event));
    }
    final name = '${inserted['name']}';
    runtime.documents.submit('Demo Note', name);
    expect(events, ['before_validate', 'validate', 'before_submit', 'on_update', 'on_submit']);

    events.clear();
    for (final event in ['before_update_after_submit', 'on_update_after_submit']) {
      runtime.hooks.onDocument('Demo Note', event, (_) => events.add(event));
    }
    runtime.documents.save('Demo Note', name, {'after_submit_note': 'Allowed'});
    expect(events, ['before_update_after_submit', 'on_update_after_submit']);
  });

  test('DocType field validation enforces Frappe-style metadata invariants', () {
    meta.saveDocType(name: 'Validated Meta', module: 'Custom');
    expect(
      () => meta.saveField(
        doctype: 'Validated Meta',
        fieldName: 'section',
        label: 'Section',
        fieldType: 'Section Break',
        required: true,
      ),
      throwsStateError,
    );
    expect(
      () => meta.saveField(
        doctype: 'Validated Meta',
        fieldName: 'hidden_required',
        label: 'Hidden Required',
        fieldType: 'Data',
        required: true,
        hidden: true,
      ),
      throwsStateError,
    );
    expect(
      () => meta.saveField(
        doctype: 'Validated Meta',
        fieldName: 'precision_bad',
        label: 'Precision Bad',
        fieldType: 'Currency',
        precision: 7,
      ),
      throwsStateError,
    );
    expect(
      () => meta.saveField(
        doctype: 'Validated Meta',
        fieldName: 'select_bad',
        label: 'Select Bad',
        fieldType: 'Select',
        options: 'A\\nB',
        defaultValue: 'C',
      ),
      throwsStateError,
    );
  });

  test('delete blocks active Link and Dynamic Link references like Frappe', () {
    meta.saveDocType(name: 'Reference Target', module: 'Demo');
    meta.saveField(
      doctype: 'Reference Target',
      fieldName: 'label',
      label: 'Label',
      fieldType: 'Data',
      required: true,
    );
    meta.saveDocType(name: 'Static Reference', module: 'Demo', isSubmittable: true);
    meta.saveField(
      doctype: 'Static Reference',
      fieldName: 'target',
      label: 'Target',
      fieldType: 'Link',
      options: 'Reference Target',
      required: true,
    );
    meta.saveDocType(name: 'Dynamic Reference', module: 'Demo');
    meta.saveField(
      doctype: 'Dynamic Reference',
      fieldName: 'reference_type',
      label: 'Reference Type',
      fieldType: 'Select',
      options: 'Reference Target',
    );
    meta.saveField(
      doctype: 'Dynamic Reference',
      fieldName: 'reference_name',
      label: 'Reference Name',
      fieldType: 'Dynamic Link',
      options: 'reference_type',
    );

    final target = documents.save('Reference Target', {'label': 'Protected'});
    final targetName = '${target['name']}';
    final staticRef = documents.save('Static Reference', {'target': targetName});
    final staticName = '${staticRef['name']}';

    final staticLinks = documents.incomingLinkReferences('Reference Target', targetName);
    expect(staticLinks.any((link) => link.referenceDoctype == 'Static Reference'), isTrue);
    expect(() => documents.delete('Reference Target', targetName), throwsStateError);

    documents.submit('Static Reference', staticName);
    documents.cancel('Static Reference', staticName);
    documents.delete('Reference Target', targetName);
    expect(documents.exists('Reference Target', targetName), isFalse);

    final target2 = documents.save('Reference Target', {'label': 'Dynamic Protected'});
    final target2Name = '${target2['name']}';
    final dynamicRef = documents.save('Dynamic Reference', {
      'reference_type': 'Reference Target',
      'reference_name': target2Name,
    });
    final dynamicName = '${dynamicRef['name']}';
    final dynamicLinks = documents.incomingLinkReferences('Reference Target', target2Name);
    expect(dynamicLinks.any((link) => link.dynamic && link.referenceDoctype == 'Dynamic Reference'), isTrue);
    expect(() => documents.delete('Reference Target', target2Name), throwsStateError);
    documents.delete('Dynamic Reference', dynamicName);
    documents.delete('Reference Target', target2Name);
    expect(documents.exists('Reference Target', target2Name), isFalse);
  });

  test('incoming link scan respects the physical identity of engine-owned tab tables', () {
    meta.saveDocType(name: 'Physical Target', module: 'Demo');
    meta.saveField(
      doctype: 'Physical Target',
      fieldName: 'label',
      label: 'Label',
      fieldType: 'Data',
      required: true,
    );
    final target = documents.save('Physical Target', {'label': 'Protected'});
    final targetName = '${target['name']}';

    database.db.execute('''
      CREATE TABLE [tabLegacy Dynamic Reference] (
        id TEXT PRIMARY KEY,
        party_type TEXT,
        party_id TEXT
      ) STRICT;
    ''');
    final legacy = meta.saveDocType(name: 'Legacy Dynamic Reference', module: 'Demo');
    expect(legacy.idField, 'id');
    meta.saveField(
      doctype: 'Legacy Dynamic Reference',
      fieldName: 'party_type',
      label: 'Party Type',
      fieldType: 'Select',
      options: 'Physical Target',
    );
    meta.saveField(
      doctype: 'Legacy Dynamic Reference',
      fieldName: 'party_id',
      label: 'Party',
      fieldType: 'Dynamic Link',
      options: 'party_type',
    );
    database.db.execute(
      'INSERT INTO [tabLegacy Dynamic Reference](id,party_type,party_id) VALUES (?,?,?);',
      ['LEGACY-1', 'Physical Target', targetName],
    );

    final links = documents.incomingLinkReferences('Physical Target', targetName);
    expect(links.any((link) => link.dynamic && link.referenceName == 'LEGACY-1'), isTrue);
    expect(() => documents.delete('Physical Target', targetName), throwsStateError);
  });

  test('cancel blocks a submitted backlink but ignores draft backlinks', () {
    meta.saveDocType(name: 'Cancel Target', module: 'Demo', isSubmittable: true);
    meta.saveField(
      doctype: 'Cancel Target',
      fieldName: 'label',
      label: 'Label',
      fieldType: 'Data',
      required: true,
    );
    meta.saveDocType(name: 'Cancel Reference', module: 'Demo', isSubmittable: true);
    meta.saveField(
      doctype: 'Cancel Reference',
      fieldName: 'target',
      label: 'Target',
      fieldType: 'Link',
      options: 'Cancel Target',
      required: true,
    );

    final target = documents.save('Cancel Target', {'label': 'Target'});
    final targetName = '${target['name']}';
    documents.submit('Cancel Target', targetName);
    final draftReference = documents.save('Cancel Reference', {'target': targetName});
    expect(documents.cancel('Cancel Target', targetName)['docstatus'], 2);

    final target2 = documents.save('Cancel Target', {'label': 'Target 2'});
    final target2Name = '${target2['name']}';
    documents.submit('Cancel Target', target2Name);
    final submittedReference = documents.save('Cancel Reference', {'target': target2Name});
    final submittedReferenceName = '${submittedReference['name']}';
    documents.submit('Cancel Reference', submittedReferenceName);
    expect(() => documents.cancel('Cancel Target', target2Name), throwsStateError);
    expect(documents.get('Cancel Target', target2Name)?['docstatus'], 1);

    // Keep the draft reference live to prove it does not participate in cancel checks.
    expect(documents.get('Cancel Reference', '${draftReference['name']}')?['docstatus'], 0);
  });

  test('generic list supports search filters sorting and paging from DocType metadata', () {
    documents.save('Demo Note', {'title': 'Zulu', 'amount': 30});
    documents.save('Demo Note', {'title': 'Alpha', 'amount': 10});
    documents.save('Demo Note', {'title': 'Beta', 'amount': 20});

    final searched = documents.list(
      'Demo Note',
      search: 'alp',
      fields: const ['title', 'amount'],
      searchFields: const ['title'],
      sortField: 'title',
      descending: false,
    );
    expect(searched.total, 1);
    expect(searched.rows.single['title'], 'Alpha');

    final filtered = documents.list(
      'Demo Note',
      filters: const [
        ['amount', '>=', 20],
      ],
      fields: const ['title', 'amount'],
      sortField: 'title',
      descending: false,
      limit: 1,
      offset: 1,
    );
    expect(filtered.total, 2);
    expect(filtered.rows.length, 1);
    expect(filtered.rows.single['title'], 'Zulu');
  });


  test('child table Link fields validate and persist through the native document engine', () {
    meta.saveDocType(name: 'Demo Target', module: 'Demo', titleField: 'title');
    meta.saveField(
      doctype: 'Demo Target',
      fieldName: 'title',
      label: 'Title',
      fieldType: 'Data',
      required: true,
      inListView: true,
    );
    final target = runtime.documents.insert('Demo Target', {'title': 'Target A'});
    final targetName = '${target['name']}';

    meta.saveDocType(name: 'Demo Link Line', module: 'Demo', isChild: true);
    meta.saveField(
      doctype: 'Demo Link Line',
      fieldName: 'target',
      label: 'Target',
      fieldType: 'Link',
      options: 'Demo Target',
      required: true,
      inListView: true,
    );
    meta.saveField(
      doctype: 'Demo Note',
      fieldName: 'linked_lines',
      label: 'Linked Lines',
      fieldType: 'Table',
      options: 'Demo Link Line',
    );

    final inserted = runtime.documents.insert('Demo Note', {
      'title': 'Parent with linked child',
      'linked_lines': [
        {'target': targetName},
      ],
    });
    final name = '${inserted['name']}';
    final rows = runtime.getDoc('Demo Note', name)?['linked_lines'] as List;
    expect(rows, hasLength(1));
    expect((rows.first as Map)['target'], targetName);

    expect(
      () => runtime.documents.insert('Demo Note', {
        'title': 'Invalid linked child',
        'linked_lines': const [
          {'target': 'MISSING-TARGET'},
        ],
      }),
      throwsA(isA<StateError>().having((error) => error.toString(), 'message', contains('missing Demo Target'))),
    );
  });

}
