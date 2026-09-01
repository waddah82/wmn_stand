import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/audit/audit_service.dart';
import 'package:wmn_standalone/core/database/wmn_database.dart';
import 'package:wmn_standalone/core/documents/document_registry.dart';
import 'package:wmn_standalone/framework/meta/meta_service.dart';
import 'package:wmn_standalone/framework/model/document_service.dart';
import 'package:wmn_standalone/modules/customization/application/customization_service.dart';
import 'package:wmn_standalone/modules/customization/application/script_engine.dart';
import 'package:wmn_standalone/modules/customization/data/customization_repository.dart';
import 'package:wmn_standalone/modules/customization/domain/customization_models.dart';

void main() {
  late WmnDatabase database;
  late WmnDocumentRegistry registry;
  late CustomizationRepository repository;
  late CustomizationService customization;
  late WmnMetaService meta;
  late WmnDocumentService documents;

  setUp(() {
    database = WmnDatabase.forTesting(sqlite3.openInMemory());
    registry = WmnDocumentRegistry(database);
    repository = CustomizationRepository(database);
    meta = WmnMetaService(database: database, registry: registry, customization: repository);
    documents = WmnDocumentService(
      database: database,
      meta: meta,
      customization: repository,
      audit: AuditService(database),
    );
    customization = CustomizationService(
      repository: repository,
      registry: registry,
      scriptEngine: WmnScriptEngine(registry: registry),
      audit: AuditService(database),
    );

    meta.saveDocType(name: 'Demo Entity', module: 'Demo', titleField: 'title');
    meta.saveField(
      doctype: 'Demo Entity',
      fieldName: 'title',
      label: 'Title',
      fieldType: 'Data',
      required: true,
      inListView: true,
      searchable: true,
    );
    meta.saveField(
      doctype: 'Demo Entity',
      fieldName: 'enabled',
      label: 'Enabled',
      fieldType: 'Check',
      defaultValue: 1,
      inListView: true,
    );
  });

  tearDown(() => database.close());

  test('customization metadata and values stay independent from the base table', () {
    final field = customization.saveCustomField(
      documentType: 'Demo Entity',
      fieldName: 'custom_segment',
      label: 'Segment',
      fieldType: WmnCustomFieldType.select,
      options: const ['A', 'B'],
      required: true,
    );
    expect(field.fieldName, 'custom_segment');

    customization.savePropertyOverride(
      documentType: 'Demo Entity',
      fieldName: 'custom_segment',
      propertyName: 'label',
      value: 'Entity Segment',
    );

    expect(
      () => documents.save('Demo Entity', {'title': 'Missing required customization', 'enabled': 1}),
      throwsA(isA<StateError>().having((error) => error.toString(), 'message', contains('Entity Segment'))),
    );

    final saved = documents.save('Demo Entity', {
      'title': 'Alpha',
      'enabled': 1,
      'custom_segment': 'A',
    });
    final name = '${saved['name']}';

    final physicalColumns = database.db
        .select('PRAGMA table_info([tabDemo Entity]);')
        .map((row) => '${row['name']}')
        .toSet();
    expect(physicalColumns, isNot(contains('custom_segment')));
    expect(
      database.db.select(
        'SELECT field_name FROM custom_field_values WHERE document_type=? AND document_id=? AND field_name=?;',
        ['Demo Entity', name, 'custom_segment'],
      ),
      isNotEmpty,
    );

    final snapshot = customization.formSnapshot(documentType: 'Demo Entity', documentId: name);
    expect(snapshot.values['custom_segment'], 'A');
    expect(snapshot.fields.single.label, 'Entity Segment');

    final merged = customization.loadMergedDocument('Demo Entity', name);
    expect(merged['title'], 'Alpha');
    expect(merged['custom_segment'], 'A');
    expect(registry.readValue('Demo Entity', name, 'custom_segment'), 'A');
  });

  test('legacy script records remain disabled while DocType Studio owns editable code', () {
    customization.saveClientScript(
      name: 'Demo Client Draft',
      documentType: 'Demo Entity',
      script: 'wmn.ui.form.on("Demo Entity", { validate(frm) {} });',
    );
    customization.saveServerScript(
      name: 'Demo Server Draft',
      documentType: 'Demo Entity',
      eventName: 'validate',
      script: 'if (!doc) wmn.throw("Missing document");',
    );

    expect(customization.clientScripts(documentType: 'Demo Entity'), hasLength(1));
    expect(customization.clientScripts(documentType: 'Demo Entity').single.enabled, isFalse);
    expect(customization.serverScripts(documentType: 'Demo Entity'), hasLength(1));
    expect(customization.serverScripts(documentType: 'Demo Entity').single.enabled, isFalse);
  });

  test('document registry exposes safe generic list and count helpers', () {
    documents.save('Demo Entity', {'title': 'Alpha', 'enabled': 1});
    documents.save('Demo Entity', {'title': 'Beta', 'enabled': 0});
    documents.save('Demo Entity', {'title': 'Gamma', 'enabled': 1});

    expect(registry.count('Demo Entity'), 3);
    expect(registry.count('Demo Entity', filters: const [['enabled', '=', 1]]), 2);

    final rows = registry.readList(
      'Demo Entity',
      fields: const ['name', 'title', 'enabled'],
      filters: const [['enabled', '=', 1]],
      orderBy: 'title',
    );
    expect(rows.map((row) => row['title']), containsAll(<String>['Alpha', 'Gamma']));
  });
}
