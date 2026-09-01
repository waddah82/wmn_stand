import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/database/wmn_database.dart';
import 'package:wmn_standalone/core/documents/document_registry.dart';
import 'package:wmn_standalone/framework/meta/meta_service.dart';
import 'package:wmn_standalone/modules/customization/data/customization_repository.dart';
import 'package:wmn_standalone/modules/reporting/application/frappe_report_service.dart';
import 'package:wmn_standalone/modules/reporting/application/query_report_service.dart';
import 'package:wmn_standalone/modules/reporting/application/report_builder_service.dart';
import 'package:wmn_standalone/modules/reporting/application/report_folder_loader.dart';
import 'package:wmn_standalone/modules/reporting/application/script_report_service.dart';

void main() {
  WmnFrappeReportService createReports(WmnDatabase database) {
    final registry = WmnDocumentRegistry(database);
    final customization = CustomizationRepository(database);
    final meta = WmnMetaService(database: database, registry: registry, customization: customization);
    final scripts = WmnScriptReportService(database: database);
    return WmnFrappeReportService(
      database: database,
      reportBuilder: ReportBuilderService(database: database, customization: customization, meta: meta),
      queryReports: WmnQueryReportService(database: database),
      scriptReports: scripts,
    );
  }

  test('Report filters and columns are first-class editable child tables', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final reports = createReports(database);

    final reportFields = database.db.select(
      "SELECT fieldname,fieldtype,options,read_only,hidden FROM wmn_doctype_fields WHERE doctype='Report' AND fieldname IN ('filters','columns') ORDER BY fieldname;",
    );
    expect(reportFields, hasLength(2));
    expect(reportFields.every((row) => row['fieldtype'] == 'Table' && row['read_only'] == 0 && row['hidden'] == 0), isTrue);
    expect(database.db.select("SELECT is_child FROM wmn_doctypes WHERE name='Report Filter';").single['is_child'], 1);
    expect(database.db.select("SELECT is_child FROM wmn_doctypes WHERE name='Report Column';").single['is_child'], 1);

    reports.saveDefinition(const WmnFrappeReportDefinition(
      name: 'Child Metadata Query',
      reportName: 'Child Metadata Query',
      reportType: 'Query Report',
      module: 'Demo',
      queryDefinition: <String, Object?>{
        'sql': 'SELECT name,module FROM wmn_doctypes WHERE module=%(module)s ORDER BY name',
      },
      filters: <Map<String, Object?>>[
        <String, Object?>{
          'fieldname': 'module',
          'label': 'Module',
          'fieldtype': 'Link',
          'options': 'Module',
          'required': true,
          'default': 'WMN System',
        },
      ],
      columns: <Map<String, Object?>>[
        <String, Object?>{'fieldname': 'name', 'label': 'DocType', 'fieldtype': 'Data'},
        <String, Object?>{'fieldname': 'module', 'label': 'Module', 'fieldtype': 'Data'},
      ],
    ));

    expect(database.db.select("SELECT COUNT(*) AS c FROM [tabReport Filter] WHERE parent='Child Metadata Query';").single['c'], 1);
    expect(database.db.select("SELECT COUNT(*) AS c FROM [tabReport Column] WHERE parent='Child Metadata Query';").single['c'], 2);
    final definition = reports.definition('Child Metadata Query')!;
    expect(definition.filters.single['fieldtype'], 'Link');
    expect(definition.columns.map((row) => row['fieldname']), containsAll(<String>['name', 'module']));
  });

  test('application report folder imports full metadata filters columns and SQL source', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final reports = createReports(database);
    final loader = WmnReportFolderLoader(reports: reports, storage: reports.storage);
    const base = 'apps/demo/reports/folder_doctypes';

    reports.storage.writeText('$base/report.json', const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'name': 'folder-doctypes',
      'report_name': 'Folder DocTypes',
      'report_type': 'Query Report',
      'module': 'Demo',
      'ref_doctype': 'DocType',
      'filters': <Map<String, Object?>>[
        <String, Object?>{
          'fieldname': 'module',
          'label': 'Module',
          'fieldtype': 'Link',
          'options': 'Module',
          'default': 'WMN System',
        },
      ],
      'columns': <Map<String, Object?>>[
        <String, Object?>{'fieldname': 'name', 'label': 'DocType', 'fieldtype': 'Data'},
        <String, Object?>{'fieldname': 'module', 'label': 'Module', 'fieldtype': 'Data'},
      ],
      'query_definition': <String, Object?>{'max_rows': 50},
    }));
    reports.storage.writeText('$base/query.sql', 'SELECT name,module FROM wmn_doctypes WHERE module=%(module)s ORDER BY name');

    final imported = loader.importFolder(base);
    expect(imported.reportName, 'Folder DocTypes');
    expect(imported.isStandard, isTrue);
    expect(imported.metadata['source_mode'], 'REPORT_FOLDER');
    expect(imported.filters.single['fieldname'], 'module');
    expect(imported.columns, hasLength(2));
    expect(imported.querySourcePath, '$base/query.sql');
    expect(reports.execute('folder-doctypes', filters: const <String, Object?>{'module': 'WMN System'}).rows, isNotEmpty);

    final exportedPath = loader.exportFolder('folder-doctypes', 'apps/demo/reports/exported_folder_doctypes');
    expect(exportedPath, 'apps/demo/reports/exported_folder_doctypes/report.json');
    expect(reports.storage.exists('apps/demo/reports/exported_folder_doctypes/query.sql'), isTrue);
    final exported = jsonDecode(reports.storage.readText(exportedPath)) as Map<String, dynamic>;
    expect(exported['filters'], isA<List>());
    expect(exported['columns'], isA<List>());
    expect(exported['query_file'], 'query.sql');
  });
}
