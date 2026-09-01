import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/audit/audit_service.dart';
import 'package:wmn_standalone/core/database/wmn_database.dart';
import 'package:wmn_standalone/core/documents/document_registry.dart';
import 'package:wmn_standalone/framework/meta/meta_service.dart';
import 'package:wmn_standalone/framework/model/document_service.dart';
import 'package:wmn_standalone/modules/customization/data/customization_repository.dart';
import 'package:wmn_standalone/modules/customization/domain/customization_models.dart';
import 'package:wmn_standalone/modules/reporting/application/report_builder_service.dart';
import 'package:wmn_standalone/modules/reporting/domain/report_models.dart';

void main() {
  test('report builder discovers application DocTypes dynamically', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final customization = CustomizationRepository(database);
    final registry = WmnDocumentRegistry(database);
    final meta = WmnMetaService(database: database, registry: registry, customization: customization);
    final documents = WmnDocumentService(
      database: database,
      meta: meta,
      customization: customization,
      audit: AuditService(database),
    );
    final service = ReportBuilderService(database: database, customization: customization, meta: meta);

    meta.saveDocType(name: 'Demo Report Row', module: 'Demo', titleField: 'title');
    meta.saveField(doctype: 'Demo Report Row', fieldName: 'title', label: 'Title', fieldType: 'Data', required: true, inListView: true);
    meta.saveField(doctype: 'Demo Report Row', fieldName: 'group_name', label: 'Group Name', fieldType: 'Data', inListView: true);
    meta.saveField(doctype: 'Demo Report Row', fieldName: 'amount', label: 'Amount', fieldType: 'Currency');

    customization.saveCustomField(
      documentType: 'Demo Report Row',
      fieldName: 'custom_region',
      label: 'Region',
      fieldType: WmnCustomFieldType.data,
      inListView: true,
    );

    final a = documents.save('Demo Report Row', {'title': 'Alpha', 'group_name': 'Retail', 'amount': 100});
    final b = documents.save('Demo Report Row', {'title': 'Beta', 'group_name': 'Retail', 'amount': 200});
    customization.saveCustomValues('Demo Report Row', '${a['name']}', const {'custom_region': 'North'});
    customization.saveCustomValues('Demo Report Row', '${b['name']}', const {'custom_region': 'South'});

    expect(service.sources.map((entry) => entry.key), contains('doctype:Demo Report Row'));
    final fieldNames = service.fieldsFor('doctype:Demo Report Row').map((field) => field.name);
    expect(fieldNames, containsAll(<String>['title', 'group_name', 'amount', 'custom_region']));

    final detail = service.saveReport(
      name: 'Demo Regions',
      sourceKey: 'doctype:Demo Report Row',
      columns: const [
        WmnReportColumn(field: 'title'),
        WmnReportColumn(field: 'custom_region'),
      ],
      filters: const [
        WmnReportFilter(field: 'group_name', operator: WmnReportOperator.equals, value: 'Retail'),
      ],
      sorts: const [WmnReportSort(field: 'title')],
    );
    final persisted = database.db.select('SELECT report_type,query_source_type FROM [tabReport] WHERE name=?;', [detail.id]).single;
    expect(persisted['report_type'], 'Report Builder');
    expect(persisted['query_source_type'], 'STRUCTURED');
    expect(database.db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='custom_reports';"), isEmpty);
    final childColumns = database.db.select(
      "SELECT fieldname,label FROM [tabReport Column] WHERE parent=? AND parenttype='Report' ORDER BY idx;",
      [detail.id],
    );
    expect(childColumns.map((row) => row['label']), containsAll(<String>['Title', 'Region']));
    final childFilters = database.db.select(
      "SELECT fieldname,label FROM [tabReport Filter] WHERE parent=? AND parenttype='Report' ORDER BY idx;",
      [detail.id],
    );
    expect(childFilters.single['label'], 'Group Name');

    final result = service.run(detail);
    expect(result.rows.length, 2);
    expect(result.rows.any((row) => row['Region'] == 'North'), isTrue);
    expect(result.rows.any((row) => row['Region'] == 'South'), isTrue);
  });
}
