import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/audit/audit_service.dart';
import 'package:wmn_standalone/core/database/wmn_database.dart';
import 'package:wmn_standalone/core/documents/document_registry.dart';
import 'package:wmn_standalone/framework/meta/doctype_meta.dart';
import 'package:wmn_standalone/framework/meta/field_control_resolver.dart';
import 'package:wmn_standalone/framework/meta/field_options.dart';
import 'package:wmn_standalone/framework/meta/meta_service.dart';
import 'package:wmn_standalone/framework/model/document_service.dart';
import 'package:wmn_standalone/framework/workspaces/workspace_service.dart';
import 'package:wmn_standalone/modules/customization/data/customization_repository.dart';
import 'package:wmn_standalone/platform/system/wmn_system_doctype_runtime_catalog.dart';

void main() {
  test('Select option normalizer accepts real, escaped, legacy and JSON separators', () {
    expect(WmnFieldOptions.normalize('0\n1\n2'), <String>['0', '1', '2']);
    expect(WmnFieldOptions.normalize(r'0\n1\n2'), <String>['0', '1', '2']);
    expect(WmnFieldOptions.normalize('0/n1/n2'), <String>['0', '1', '2']);
    expect(WmnFieldOptions.normalize('["0","1","2","1"]'), <String>['0', '1', '2']);
  });

  test('Data storage can resolve to Select or Link without changing SQL type', () {
    const selectField = WmnFieldMeta(
      fieldName: 'state',
      label: 'State',
      fieldType: 'Data',
      options: r'DRAFT\nACTIVE\nCLOSED',
      metadata: <String, Object?>{'render_as': 'SELECT'},
    );
    final select = WmnFieldControlResolver.resolve(selectField);
    expect(select.type, WmnFieldControlType.select);
    expect(select.options, <String>['DRAFT', 'ACTIVE', 'CLOSED']);
    expect(selectField.fieldType, 'Data');

    const autoSelectField = WmnFieldMeta(
      fieldName: 'priority',
      label: 'Priority',
      fieldType: 'Data',
      options: 'Low/nMedium/nHigh',
      metadata: <String, Object?>{'render_as': 'AUTO'},
    );
    final autoSelect = WmnFieldControlResolver.resolve(autoSelectField);
    expect(autoSelect.type, WmnFieldControlType.select);
    expect(autoSelect.options, <String>['Low', 'Medium', 'High']);

    const linkField = WmnFieldMeta(
      fieldName: 'reference_type',
      label: 'Reference Type',
      fieldType: 'Data',
      metadata: <String, Object?>{
        'render_as': 'LINK',
        'link_target': 'DocType',
      },
    );
    final link = WmnFieldControlResolver.resolve(
      linkField,
      doctypeExists: (name) => name == 'DocType',
    );
    expect(link.type, WmnFieldControlType.link);
    expect(link.targetDoctype, 'DocType');
  });

  test('Data rendered as Select or Link keeps document validation and backlink semantics', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final registry = WmnDocumentRegistry(database);
    final customization = CustomizationRepository(database);
    final meta = WmnMetaService(database: database, registry: registry, customization: customization);
    final documents = WmnDocumentService(
      database: database,
      meta: meta,
      customization: customization,
      audit: AuditService(database),
    );

    meta.saveDocType(name: 'Render Target', module: 'WMN System');
    meta.saveField(
      doctype: 'Render Target',
      fieldName: 'label',
      label: 'Label',
      fieldType: 'Data',
      required: true,
    );
    meta.saveDocType(name: 'Rendered Reference', module: 'WMN System');
    meta.saveField(
      doctype: 'Rendered Reference',
      fieldName: 'state',
      label: 'State',
      fieldType: 'Data',
      options: 'OPEN/nCLOSED',
      metadata: const <String, Object?>{'render_as': 'SELECT'},
    );
    meta.saveField(
      doctype: 'Rendered Reference',
      fieldName: 'target',
      label: 'Target',
      fieldType: 'Data',
      options: 'Render Target',
      metadata: const <String, Object?>{'render_as': 'LINK'},
    );

    final target = documents.save('Render Target', <String, Object?>{'label': 'Protected'});
    final targetName = '${target['name']}';
    expect(
      () => documents.save('Rendered Reference', <String, Object?>{'state': 'INVALID', 'target': targetName}),
      throwsStateError,
    );
    expect(
      () => documents.save('Rendered Reference', const <String, Object?>{'state': 'OPEN', 'target': 'missing'}),
      throwsStateError,
    );
    documents.save('Rendered Reference', <String, Object?>{'state': 'OPEN', 'target': targetName});
    expect(
      documents.incomingLinkReferences('Render Target', targetName).any(
            (entry) => entry.referenceDoctype == 'Rendered Reference' && entry.fieldName == 'target',
          ),
      isTrue,
    );
    expect(() => documents.delete('Render Target', targetName), throwsStateError);
  });

  test('Meta engine treats Data Render As Link and Dynamic Link as real references', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final meta = WmnMetaService(
      database: database,
      registry: WmnDocumentRegistry(database),
      customization: CustomizationRepository(database),
    );

    meta.saveDocType(name: 'Meta Target', module: 'Custom');
    meta.saveField(
      doctype: 'Meta Target',
      fieldName: 'label',
      label: 'Label',
      fieldType: 'Data',
    );
    meta.saveDocType(name: 'Meta Source', module: 'Custom');
    meta.saveField(
      doctype: 'Meta Source',
      fieldName: 'target_type',
      label: 'Target Type',
      fieldType: 'Data',
      options: 'Meta Target/nDocType',
      metadata: const <String, Object?>{'render_as': 'SELECT'},
    );
    meta.saveField(
      doctype: 'Meta Source',
      fieldName: 'target',
      label: 'Target',
      fieldType: 'Data',
      metadata: const <String, Object?>{
        'render_as': 'LINK',
        'link_target': 'Meta Target',
      },
    );
    meta.saveField(
      doctype: 'Meta Source',
      fieldName: 'auto_target',
      label: 'Auto Target',
      fieldType: 'Data',
      options: 'Meta Target',
    );
    meta.saveField(
      doctype: 'Meta Source',
      fieldName: 'dynamic_target',
      label: 'Dynamic Target',
      fieldType: 'Data',
      options: 'target_type',
      metadata: const <String, Object?>{'render_as': 'DYNAMIC_LINK'},
    );

    meta.validateDocTypeDefinition('Meta Source');
    final targetReferences = meta.doctypeReferences('Meta Target');
    expect(targetReferences, contains('Meta Source.target (Link)'));
    expect(targetReferences, contains('Meta Source.auto_target (Link)'));
    expect(meta.fieldReferences('Meta Source', 'target_type'), contains('dynamic_target.options'));
    expect(() => meta.deleteField('Meta Source', 'target_type'), throwsStateError);
    expect(() => meta.deleteDocType('Meta Target'), throwsStateError);
  });

  test('schema v32 exposes Workspace as Parent plus Child Table and Data Import as Tool history', () {
    final raw = sqlite3.openInMemory();
    final database = WmnDatabase.forTesting(raw);
    addTearDown(database.close);
    final meta = WmnMetaService(
      database: database,
      registry: WmnDocumentRegistry(database),
      customization: CustomizationRepository(database),
    );

    expect(WmnDatabase.schemaVersion, greaterThanOrEqualTo(32));
    final workspace = meta.doctype('Workspace');
    final items = workspace?.field('items');
    expect(items?.fieldType, 'Table');
    expect(items?.options, 'Workspace Item');
    expect(meta.doctype('Workspace Item')?.isChild, isTrue);
    expect(meta.doctype('Data Import Job')?.genericWrite, isFalse);
    expect(meta.doctype('Data Export Job')?.genericWrite, isFalse);
    expect(meta.doctype('Data Export Job')?.field('format')?.selectOptions, <String>['CSV', 'JSON']);

    final pageTypes = raw
        .select("SELECT DISTINCT page_type FROM [tabPage] WHERE name LIKE 'Runtime Lab - %' ORDER BY page_type;")
        .map((row) => row['page_type'])
        .toSet();
    expect(
      pageTypes,
      containsAll(<String>{'STANDARD', 'DASHBOARD', 'CUSTOM', 'LIST', 'FORM', 'REPORT', 'WORKSPACE'}),
    );
    expect(
      raw.select("SELECT controller_key FROM [tabPage] WHERE name='Data Import / Export Tool';").single['controller_key'],
      'wmn.tool.data_exchange',
    );
    final workspaceBuilder = raw
        .select("SELECT page_type,metadata_json FROM [tabPage] WHERE name='Workspace Builder';")
        .single;
    expect(workspaceBuilder['page_type'], 'LIST');
    expect('${workspaceBuilder['metadata_json']}', contains('"doctype":"Workspace"'));
  });

  test('Workspace generic form rows persist through the same table consumed by Workspace runtime', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final registry = WmnDocumentRegistry(database);
    final customization = CustomizationRepository(database);
    final meta = WmnMetaService(database: database, registry: registry, customization: customization);
    final documents = WmnDocumentService(
      database: database,
      meta: meta,
      customization: customization,
      audit: AuditService(database),
    );
    final workspaces = WmnWorkspaceService(database: database, meta: meta);

    documents.save('Workspace', <String, Object?>{
      'name': 'Table Workspace Test',
      'label': 'Table Workspace Test',
      'module': 'WMN System',
      'sequence_id': 500,
      'is_public': 1,
      'is_hidden': 0,
      'items': <Map<String, Object?>>[
        <String, Object?>{
          'region': 'CONTENT',
          'item_type': 'shortcut',
          'label': 'Pages',
          'link_type': 'DocType',
          'link_to': 'Page',
          'column_span': 4,
          'hidden': 0,
        },
      ],
    });

    final bundle = workspaces.bundle('Table Workspace Test');
    expect(bundle, isNotNull);
    expect(bundle!.items, hasLength(1));
    expect(bundle.items.single.label, 'Pages');
    expect(bundle.items.single.linkTo, 'Page');
    expect(
      database.db.select(
        "SELECT COUNT(*) AS c FROM [tabWorkspaceItem] WHERE parent='Table Workspace Test' AND parenttype='Workspace' AND parentfield='items';",
      ).single['c'],
      1,
    );
  });

  test('every System DocType declares an explicit runtime owner', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final systemDocTypes = database.db
        .select('SELECT name FROM wmn_doctypes WHERE is_system=1 ORDER BY name;')
        .map((row) => '${row['name']}')
        .toSet();
    final bindings = WmnSystemDocTypeRuntimeCatalog.bindings;
    final catalogDocTypes = bindings.map((entry) => entry.doctype).toSet();
    expect(catalogDocTypes, systemDocTypes);
    for (final entry in bindings) {
      expect(entry.ownerServiceId.trim(), isNotEmpty, reason: entry.doctype);
      final row = database.db
          .select('SELECT generic_write FROM wmn_doctypes WHERE name=? LIMIT 1;', <Object?>[entry.doctype])
          .single;
      expect(entry.genericEditingAllowed, row['generic_write'] == 1, reason: entry.doctype);
    }
  });
}
