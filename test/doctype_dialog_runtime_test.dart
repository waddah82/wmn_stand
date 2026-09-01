import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/audit/audit_service.dart';
import 'package:wmn_standalone/core/database/wmn_database.dart';
import 'package:wmn_standalone/core/documents/document_registry.dart';
import 'package:wmn_standalone/framework/meta/meta_service.dart';
import 'package:wmn_standalone/framework/model/document_service.dart';
import 'package:wmn_standalone/framework/ui/form/wmn_form_view.dart';
import 'package:wmn_standalone/framework/ui/list/wmn_list_view.dart';
import 'package:wmn_standalone/modules/customization/application/customization_service.dart';
import 'package:wmn_standalone/modules/customization/application/script_engine.dart';
import 'package:wmn_standalone/modules/customization/data/customization_repository.dart';

void main() {
  test('shared Form runtime exposes page and dialog presentation modes', () {
    expect(
      WmnFormPresentation.values,
      containsAll(<WmnFormPresentation>[
        WmnFormPresentation.page,
        WmnFormPresentation.dialog,
      ]),
    );
  });

  test('List runtime preserves routed forms by default', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final registry = WmnDocumentRegistry(database);
    final repository = CustomizationRepository(database);
    final audit = AuditService(database);
    final meta = WmnMetaService(
      database: database,
      registry: registry,
      customization: repository,
    );
    final documents = WmnDocumentService(
      database: database,
      meta: meta,
      customization: repository,
      audit: audit,
    );
    final customization = CustomizationService(
      repository: repository,
      registry: registry,
      scriptEngine: WmnScriptEngine(registry: registry),
      audit: audit,
    );

    meta.saveDocType(name: 'Routed Target', module: 'Platform Test');
    final widget = WmnListView(
      doctype: 'Routed Target',
      meta: meta,
      documents: documents,
      customization: customization,
    );

    expect(widget.openFormsInDialog, isFalse);
  });

  test('List runtime can keep create and edit forms inside dialogs', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final registry = WmnDocumentRegistry(database);
    final repository = CustomizationRepository(database);
    final audit = AuditService(database);
    final meta = WmnMetaService(
      database: database,
      registry: registry,
      customization: repository,
    );
    final documents = WmnDocumentService(
      database: database,
      meta: meta,
      customization: repository,
      audit: audit,
    );
    final customization = CustomizationService(
      repository: repository,
      registry: registry,
      scriptEngine: WmnScriptEngine(registry: registry),
      audit: audit,
    );

    meta.saveDocType(name: 'Dialog Target', module: 'Platform Test');
    final widget = WmnListView(
      doctype: 'Dialog Target',
      meta: meta,
      documents: documents,
      customization: customization,
      openFormsInDialog: true,
    );

    expect(widget.openFormsInDialog, isTrue);
  });
  test('Report forms can expose the native Show Report action callback', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final registry = WmnDocumentRegistry(database);
    final repository = CustomizationRepository(database);
    final audit = AuditService(database);
    final meta = WmnMetaService(database: database, registry: registry, customization: repository);
    final documents = WmnDocumentService(database: database, meta: meta, customization: repository, audit: audit);
    final customization = CustomizationService(
      repository: repository,
      registry: registry,
      scriptEngine: WmnScriptEngine(registry: registry),
      audit: audit,
    );
    final form = WmnFormView(
      doctype: 'Report',
      documentName: 'example-report',
      meta: meta,
      documents: documents,
      customization: customization,
      onOpenReport: (name) async {},
    );
    expect(form.onOpenReport, isNotNull);
  });

}
