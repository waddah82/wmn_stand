import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/database/wmn_database.dart';
import 'package:wmn_standalone/core/documents/document_registry.dart';
import 'package:wmn_standalone/framework/meta/meta_service.dart';
import 'package:wmn_standalone/modules/customization/data/customization_repository.dart';
import 'package:wmn_standalone/modules/reporting/application/frappe_report_service.dart';
import 'package:wmn_standalone/modules/reporting/application/query_report_service.dart';
import 'package:wmn_standalone/modules/reporting/application/report_builder_service.dart';
import 'package:wmn_standalone/modules/reporting/application/script_report_service.dart';
import 'package:wmn_standalone/modules/reporting/domain/report_models.dart';

void main() {
  WmnFrappeReportService createReports(WmnDatabase database, WmnScriptReportService scripts, {bool Function(String)? canReport}) {
    final registry = WmnDocumentRegistry(database);
    final customization = CustomizationRepository(database);
    final meta = WmnMetaService(database: database, registry: registry, customization: customization);
    return WmnFrappeReportService(
      database: database,
      reportBuilder: ReportBuilderService(database: database, customization: customization, meta: meta),
      queryReports: WmnQueryReportService(database: database),
      scriptReports: scripts,
      canReportOnDocType: canReport,
    );
  }

  test('Script Report executes only an explicitly registered native Dart handler from Report DocType', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final scripts = WmnScriptReportService(database: database);
    final reports = createReports(database, scripts);

    scripts.registerNativeHandler('Native Trial', (filters) {
      expect(filters['company'], 'default-company');
      return const WmnScriptReportResult(
        columns: [WmnScriptReportColumn(fieldName: 'account', label: 'Account')],
        rows: [<String, Object?>{'account': 'Cash'}],
        durationMs: 0,
      );
    });
    scripts.saveNativeDefinition(
      name: 'Native Trial',
      module: 'Accounts',
      filters: const [WmnScriptReportFilter(fieldName: 'company', label: 'Company', required: true)],
      columns: const [WmnScriptReportColumn(fieldName: 'account', label: 'Account')],
    );
    reports.saveDefinition(const WmnFrappeReportDefinition(
      name: 'Native Trial',
      reportName: 'Native Trial',
      reportType: 'Script Report',
      module: 'Accounts',
      scriptKey: 'Native Trial',
    ));

    expect(reports.execute('Native Trial', filters: const {'company': 'default-company'}).rows.single['account'], 'Cash');
    expect(database.db.select("SELECT COUNT(*) AS c FROM [tabReport] WHERE report_name='Native Trial';").single['c'], 1);
    expect(database.db.select("SELECT status,row_count FROM report_run_log WHERE report_name='Native Trial';").single['status'], 'SUCCESS');
    expect(database.db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='wmn_script_reports';"), isEmpty);

    scripts.saveNativeDefinition(name: 'Needs Port', module: 'Accounts');
    expect(() => scripts.execute('Needs Port'), throwsStateError);
  });

  test('Query Report externalizes SQL and executes one read-only parameterized SELECT', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    database.db.execute('CREATE TABLE demo_query_report(name TEXT, amount REAL);');
    database.db.execute("INSERT INTO demo_query_report VALUES ('A', 10), ('B', 20);");
    final reports = createReports(database, WmnScriptReportService(database: database));

    reports.saveDefinition(const WmnFrappeReportDefinition(
      name: 'Amounts',
      reportName: 'Amounts',
      reportType: 'Query Report',
      module: 'Demo',
      queryDefinition: {'sql': 'SELECT name, amount FROM demo_query_report WHERE amount >= %(minimum)s ORDER BY amount'},
      filters: [{'fieldname': 'minimum', 'label': 'Minimum', 'required': true}],
      columns: [
        {'fieldname': 'name', 'label': 'Name', 'fieldtype': 'Data'},
        {'fieldname': 'amount', 'label': 'Amount', 'fieldtype': 'Currency'},
      ],
    ));

    final stored = database.db.select("SELECT query_definition_json,query_source_type,query_source_path FROM [tabReport] WHERE report_name='Amounts';").single;
    expect(stored['query_source_type'], 'STORAGE_FILE');
    expect('${stored['query_definition_json']}', isNot(contains('SELECT name')));
    final sourcePath = '${stored['query_source_path']}';
    expect(sourcePath, startsWith('apps/demo/reports/amounts/'));
    expect(reports.storage.readText(sourcePath), contains('SELECT name, amount'));

    final result = reports.execute('Amounts', filters: const {'minimum': 15});
    expect(result.rows, hasLength(1));
    expect(result.rows.single['name'], 'B');
    expect(result.columns.last['fieldtype'], 'Currency');
    final log = database.db.select("SELECT status,row_count FROM report_run_log WHERE report_name='Amounts';").single;
    expect(log['status'], 'SUCCESS');
    expect(log['row_count'], 1);

    database.db.execute(
      "UPDATE [tabReport Column] SET label='Display Name',label_ar='الاسم' WHERE parent='Amounts' AND fieldname='name';",
    );
    final relabeled = reports.execute('Amounts', filters: const {'minimum': 15});
    expect(relabeled.columns.first['label'], 'Display Name');
    expect(relabeled.columns.first['label_ar'], 'الاسم');
  });

  test('managed Script Report stores source outside tabReport and executes through registered runtime', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final scripts = WmnScriptReportService(database: database);
    scripts.registerManagedExecutor('wmn-test', (source, context) {
      expect(source, 'return managed report');
      return WmnScriptReportResult(
        columns: const [WmnScriptReportColumn(fieldName: 'value', label: 'Value')],
        rows: [<String, Object?>{'value': context['value']}],
        durationMs: 0,
      );
    });
    scripts.saveManagedDefinition(
      name: 'Managed Trial',
      module: 'Demo',
      sourcePath: 'apps/demo/reports/managed_trial/report.wmn',
      language: 'wmn-test',
      source: 'return managed report',
    );
    final reports = createReports(database, scripts);
    final row = database.db.select("SELECT * FROM [tabReport] WHERE report_name='Managed Trial';").single;
    expect(row['script_source_type'], 'STORAGE_FILE');
    expect('${row['script_source_path']}', 'apps/demo/reports/managed_trial/report.wmn');
    expect('${row['metadata_json']}', isNot(contains('return managed report')));
    expect(reports.execute('Managed Trial', filters: const {'value': 42}).rows.single['value'], 42);
  });

  test('direct Report DocType Query is normalized and permission/disabled rules are enforced', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    database.db.execute('CREATE TABLE report_target(name TEXT);');
    database.db.execute("INSERT INTO report_target VALUES ('A');");
    final reports = createReports(
      database,
      WmnScriptReportService(database: database),
      canReport: (doctype) => doctype != 'Secret DocType',
    );
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO [tabReport](name,report_name,ref_doctype,report_type,module,is_standard,disabled,
        query_definition_json,filters_json,columns_json,metadata_json,created_at,updated_at)
      VALUES ('Direct Query','Direct Query',NULL,'Query Report','Demo',0,0,
        '{"sql":"SELECT name FROM report_target"}','[]','[]','{}',?,?);
    ''', [now, now]);

    expect(reports.execute('Direct Query').rows.single['name'], 'A');
    final normalized = database.db.select("SELECT query_source_type,query_source_path,query_definition_json FROM [tabReport] WHERE name='Direct Query';").single;
    expect(normalized['query_source_type'], 'STORAGE_FILE');
    expect('${normalized['query_definition_json']}', isNot(contains('SELECT name')));

    database.db.execute("UPDATE [tabReport] SET ref_doctype='Secret DocType' WHERE name='Direct Query';");
    expect(() => reports.execute('Direct Query'), throwsStateError);
    database.db.execute("UPDATE [tabReport] SET ref_doctype=NULL,disabled=1 WHERE name='Direct Query';");
    expect(() => reports.execute('Direct Query'), throwsStateError);
  });

  test('Report Builder exposes its runtime filters through the Report DocType definition', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final registry = WmnDocumentRegistry(database);
    final customization = CustomizationRepository(database);
    final meta = WmnMetaService(database: database, registry: registry, customization: customization);
    final builder = ReportBuilderService(database: database, customization: customization, meta: meta);
    final source = builder.sources.firstWhere((entry) => entry.documentType != null);
    final field = builder.fieldsFor(source.key).first;
    builder.saveReport(
      name: 'Builder Filters',
      sourceKey: source.key,
      columns: <WmnReportColumn>[WmnReportColumn(field: field.name)],
      filters: <WmnReportFilter>[
        WmnReportFilter(
          field: field.name,
          operator: WmnReportOperator.equals,
          parameterName: 'runtime_value',
          label: 'Runtime Value',
          required: true,
        ),
      ],
    );
    final reports = WmnFrappeReportService(
      database: database,
      reportBuilder: builder,
      queryReports: WmnQueryReportService(database: database),
      scriptReports: WmnScriptReportService(database: database),
    );

    final definition = reports.definition('Builder Filters')!;
    expect(definition.reportType, 'Report Builder');
    expect(definition.filters.single['fieldname'], 'runtime_value');
    expect(definition.filters.single['required'], isTrue);
  });

  test('Query Report security policy is explicit and read-only', () {
    expect(WmnQueryReportSafetyPolicy.allowsMultipleStatements, isFalse);
    expect(WmnQueryReportSafetyPolicy.allowsDataModification, isFalse);
    expect(WmnQueryReportSafetyPolicy.allowsSchemaModification, isFalse);
    expect(WmnQueryReportSafetyPolicy.allowsPragmaOrAttach, isFalse);
    expect(WmnQueryReportSafetyPolicy.requiresBoundParameters, isTrue);
    expect(WmnQueryReportSafetyPolicy.allowedStatementPrefixes, <String>{'SELECT', 'WITH'});
    expect(WmnQueryReportSafetyPolicy.forbiddenKeywords, containsAll(<String>['INSERT', 'UPDATE', 'DELETE', 'PRAGMA', 'ATTACH']));
  });

  test('Query Report rejects DML and multiple statements', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final queryReports = WmnQueryReportService(database: database);
    expect(() => queryReports.execute(sql: 'DELETE FROM tabUser'), throwsStateError);
    expect(() => queryReports.execute(sql: 'SELECT 1; SELECT 2'), throwsStateError);
    expect(() => queryReports.execute(sql: 'WITH x AS (SELECT 1) DELETE FROM tabUser'), throwsStateError);
  });

  test('Query Report safety scanner ignores SQL keywords semicolons and placeholders inside literals/comments', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final queryReports = WmnQueryReportService(database: database);
    final result = queryReports.execute(
      sql: "SELECT 'UPDATE; %(ignored)s' AS literal_value, %(actual)s AS bound_value; -- DELETE is comment",
      filters: const <String, Object?>{'actual': 7},
    );
    expect(result.rows.single['literal_value'], 'UPDATE; %(ignored)s');
    expect(result.rows.single['bound_value'], 7);
  });


  test('Query Report filter values are bound and cannot alter SQL structure', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    database.db.execute('CREATE TABLE bound_parameter_probe(name TEXT);');
    database.db.execute("INSERT INTO bound_parameter_probe VALUES ('Alpha'), ('Beta');");
    final queryReports = WmnQueryReportService(database: database);

    final result = queryReports.execute(
      sql: 'SELECT name FROM bound_parameter_probe WHERE name = %(name)s ORDER BY name',
      filters: const <String, Object?>{'name': "Alpha' OR 1=1 --"},
    );

    expect(result.rows, isEmpty);
  });

  test('Query and Script Report runtime respects commercial feature gates', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final registry = WmnDocumentRegistry(database);
    final customization = CustomizationRepository(database);
    final meta = WmnMetaService(database: database, registry: registry, customization: customization);
    final builder = ReportBuilderService(database: database, customization: customization, meta: meta);
    final scripts = WmnScriptReportService(database: database);
    final reports = WmnFrappeReportService(
      database: database,
      reportBuilder: builder,
      queryReports: WmnQueryReportService(database: database),
      scriptReports: scripts,
      isFeatureEnabled: (code) => code != 'reports.query',
    );
    reports.saveDefinition(const WmnFrappeReportDefinition(
      name: 'Blocked Query',
      reportName: 'Blocked Query',
      reportType: 'Query Report',
      module: 'Demo',
      queryDefinition: {'sql': 'SELECT 1 AS value'},
    ));
    expect(() => reports.execute('Blocked Query'), throwsStateError);
  });
}
