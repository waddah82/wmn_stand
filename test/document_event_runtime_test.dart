import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/audit/audit_service.dart';
import 'package:wmn_standalone/core/database/wmn_database.dart';
import 'package:wmn_standalone/core/documents/document_event_bus.dart';
import 'package:wmn_standalone/core/documents/document_registry.dart';
import 'package:wmn_standalone/core/settings/settings_repository.dart';
import 'package:wmn_standalone/framework/frappe_compat/frappe_runtime.dart';
import 'package:wmn_standalone/framework/meta/meta_service.dart';
import 'package:wmn_standalone/framework/model/document_service.dart';
import 'package:wmn_standalone/modules/customization/data/customization_repository.dart';

void main() {
  test('document event bus supports priority and wildcard handlers', () {
    final bus = WmnDocumentEventBus();
    final calls = <String>[];
    bus.on(
      doctype: '*',
      event: 'validate',
      priority: 20,
      handler: (_) => calls.add('wildcard-late'),
    );
    bus.on(
      doctype: 'Demo Note',
      event: 'validate',
      priority: -10,
      handler: (_) => calls.add('doctype-first'),
    );
    bus.emit(
      WmnDocumentEvent(
        doctype: 'Demo Note',
        event: 'validate',
        operation: 'update',
        document: <String, Object?>{'name': 'DEMO-1'},
      ),
    );
    expect(calls, <String>['doctype-first', 'wildcard-late']);
  });

  test('before lifecycle events can mutate the document before persistence', () {
    final fixture = _LifecycleFixture();
    addTearDown(fixture.close);
    fixture.runtime.hooks.onDocument('Lifecycle Note', 'before_save', (doc) {
      doc['title'] = 'Changed by lifecycle';
    });

    final saved = fixture.runtime.documents.insert(
      'Lifecycle Note',
      <String, Object?>{'title': 'Original'},
    );

    expect(saved['title'], 'Changed by lifecycle');
    expect(
      fixture.documents.get('Lifecycle Note', '${saved['name']}')?['title'],
      'Changed by lifecycle',
    );
  });

  test('after-event failure rolls back document, version and audit writes', () {
    final fixture = _LifecycleFixture(trackChanges: true);
    addTearDown(fixture.close);
    fixture.runtime.hooks.onDocument('Lifecycle Note', 'after_save', (_) {
      throw StateError('extension failed');
    });

    expect(
      () => fixture.runtime.documents.insert(
        'Lifecycle Note',
        <String, Object?>{'title': 'Rollback me'},
      ),
      throwsStateError,
    );

    expect(fixture.documents.list('Lifecycle Note').total, 0);
    expect(
      fixture.database.db
          .select(
            "SELECT COUNT(*) AS c FROM wmn_document_versions WHERE doctype='Lifecycle Note';",
          )
          .first['c'],
      0,
    );
    expect(
      fixture.database.db
          .select(
            "SELECT COUNT(*) AS c FROM audit_log WHERE entity_type='Lifecycle Note';",
          )
          .first['c'],
      0,
    );
  });

  test('delete lifecycle emits before_delete and after_delete around removal', () {
    final fixture = _LifecycleFixture();
    addTearDown(fixture.close);
    final saved = fixture.runtime.documents.insert(
      'Lifecycle Note',
      <String, Object?>{'title': 'Delete me'},
    );
    final events = <String>[];
    fixture.runtime.hooks.onDocument(
      'Lifecycle Note',
      'before_delete',
      (_) => events.add('before_delete'),
    );
    fixture.runtime.hooks.onDocument(
      'Lifecycle Note',
      'after_delete',
      (_) => events.add('after_delete'),
    );

    fixture.runtime.documents.deleteDoc('Lifecycle Note', '${saved['name']}');

    expect(events, <String>['before_delete', 'after_delete']);
    expect(fixture.documents.get('Lifecycle Note', '${saved['name']}'), isNull);
  });
}

class _LifecycleFixture {
  _LifecycleFixture({bool trackChanges = false}) {
    database = WmnDatabase.forTesting(sqlite3.openInMemory());
    final audit = AuditService(database);
    final settings = SettingsRepository(database);
    final registry = WmnDocumentRegistry(database);
    final customization = CustomizationRepository(database);
    final meta = WmnMetaService(
      database: database,
      registry: registry,
      customization: customization,
    );
    documents = WmnDocumentService(
      database: database,
      meta: meta,
      customization: customization,
      audit: audit,
    );
    runtime = WmnFrappeRuntime.create(
      database: database,
      settings: settings,
      metaService: meta,
      documentService: documents,
      audit: audit,
    );
    meta.saveDocType(
      name: 'Lifecycle Note',
      module: 'Demo',
      titleField: 'title',
      autoname: 'format:LIFE-.#####',
      trackChanges: trackChanges,
    );
    meta.saveField(
      doctype: 'Lifecycle Note',
      fieldName: 'title',
      label: 'Title',
      fieldType: 'Data',
      required: true,
    );
  }

  late final WmnDatabase database;
  late final WmnDocumentService documents;
  late final WmnFrappeRuntime runtime;

  void close() => database.close();
}
