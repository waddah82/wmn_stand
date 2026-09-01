import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/audit/audit_service.dart';
import 'package:wmn_standalone/core/database/wmn_database.dart';
import 'package:wmn_standalone/core/documents/document_registry.dart';
import 'package:wmn_standalone/framework/meta/meta_service.dart';
import 'package:wmn_standalone/framework/model/document_service.dart';
import 'package:wmn_standalone/modules/customization/data/customization_repository.dart';

void main() {
  test('Options = DocType resolves through the native DocType System DocType', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final registry = WmnDocumentRegistry(database);
    final customization = CustomizationRepository(database);
    final meta = WmnMetaService(
      database: database,
      registry: registry,
      customization: customization,
    );
    final documents = WmnDocumentService(
      database: database,
      meta: meta,
      customization: customization,
      audit: AuditService(database),
    );

    final target = meta.doctype('DocType');
    expect(target, isNotNull);
    expect(target!.tableName, 'wmn_doctypes');
    expect(target.genericWrite, isFalse);

    final result = documents.list(
      'DocType',
      fields: const <String>['name'],
      search: 'Report',
      limit: 25,
    );
    expect(result.rows.map((row) => row['name']), contains('Report'));
  });

  test('Role can be created through the generic DocType form contract with visible code', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final registry = WmnDocumentRegistry(database);
    final customization = CustomizationRepository(database);
    final meta = WmnMetaService(
      database: database,
      registry: registry,
      customization: customization,
    );
    final documents = WmnDocumentService(
      database: database,
      meta: meta,
      customization: customization,
      audit: AuditService(database),
    );

    final role = meta.doctype('Role');
    expect(role, isNotNull);
    final code = role!.field('code');
    expect(code, isNotNull);
    expect(code!.required, isTrue);
    expect(code.hidden, isFalse);
    expect(code.readOnly, isFalse);

    final saved = documents.save('Role', <String, Object?>{
      'code': 'QA_ROLE',
      'name': 'QA Role',
      'enabled': 1,
    });
    expect(saved['code'], 'QA_ROLE');
    expect(saved['name'], 'QA Role');
  });
}
