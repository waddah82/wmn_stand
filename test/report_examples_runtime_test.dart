import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/database/wmn_database.dart';
import 'package:wmn_standalone/core/localization/wmn_localization.dart';
import 'package:wmn_standalone/core/settings/settings_repository.dart';
import 'package:wmn_standalone/core/documents/document_registry.dart';
import 'package:wmn_standalone/framework/meta/meta_service.dart';
import 'package:wmn_standalone/modules/customization/data/customization_repository.dart';
import 'package:wmn_standalone/modules/reporting/application/builtin_report_handlers.dart';
import 'package:wmn_standalone/modules/reporting/application/frappe_report_service.dart';
import 'package:wmn_standalone/modules/reporting/application/query_report_service.dart';
import 'package:wmn_standalone/modules/reporting/application/report_builder_service.dart';
import 'package:wmn_standalone/modules/reporting/application/script_report_service.dart';
import 'package:wmn_standalone/platform/navigation/wmn_application_report_page.dart';

void main() {
  test('R3.15.13 installs one working learning report for each supported primary type', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final registry = WmnDocumentRegistry(database);
    final customization = CustomizationRepository(database);
    final meta = WmnMetaService(
      database: database,
      registry: registry,
      customization: customization,
    );
    final builder = ReportBuilderService(
      database: database,
      customization: customization,
      meta: meta,
    );
    final scripts = WmnScriptReportService(database: database);
    WmnBuiltinReportHandlers.register(database: database, scriptReports: scripts);
    final reports = WmnFrappeReportService(
      database: database,
      reportBuilder: builder,
      queryReports: WmnQueryReportService(database: database),
      scriptReports: scripts,
    );

    const builderName = 'Example - Report Builder - DocType Catalog';
    const queryName = 'Example - Query Report - DocType Search';
    const scriptName = 'Example - Script Report - Module Summary';

    final builderDefinition = reports.definition(builderName)!;
    final queryDefinition = reports.definition(queryName)!;
    final scriptDefinition = reports.definition(scriptName)!;

    expect(builderDefinition.reportType, 'Report Builder');
    expect(queryDefinition.reportType, 'Query Report');
    expect(scriptDefinition.reportType, 'Script Report');
    expect(builderDefinition.metadata['tutorial_example'], isTrue);
    expect(queryDefinition.metadata['tutorial_example'], isTrue);
    expect(scriptDefinition.metadata['tutorial_example'], isTrue);
    expect(scriptDefinition.scriptKey, WmnBuiltinReportHandlers.moduleSummaryKey);
    expect('${scriptDefinition.metadata['source_preview']}', contains('LEFT JOIN wmn_doctype_fields'));
    expect('${scriptDefinition.metadata['source_preview']}', contains('FROM wmn_doctypes d'));
    expect(builderDefinition.filters.map((entry) => entry['fieldtype']), containsAll(<String>['Link', 'Check']));
    expect(queryDefinition.filters.map((entry) => entry['fieldtype']), containsAll(<String>['Link', 'Data']));
    expect(scriptDefinition.filters.map((entry) => entry['fieldtype']), contains('Link'));

    final builderResult = reports.execute(builderName);
    expect(builderResult.rows, isNotEmpty);
    expect(builderResult.columns.map((entry) => entry['label']), contains('DocType'));

    final queryResult = reports.execute(queryName, filters: const <String, Object?>{'module': 'WMN'});
    expect(queryResult.rows, isNotEmpty);
    expect(queryResult.columns.map((entry) => entry['fieldname']), contains('doctype'));
    final queryRow = database.db.select(
      "SELECT query_source_type,query_source_path,query_definition_json FROM [tabReport] WHERE report_name=?;",
      <Object?>[queryName],
    ).single;
    expect(queryRow['query_source_type'], 'STORAGE_FILE');
    expect('${queryRow['query_definition_json']}', isNot(contains('SELECT name')));
    expect('${queryRow['query_source_path']}', isNotEmpty);

    final scriptResult = reports.execute(scriptName);
    expect(scriptResult.rows, isNotEmpty);
    expect(scriptResult.columns.map((entry) => entry['fieldname']), containsAll(<String>['module', 'doctype_count', 'field_count', 'required_field_count']));
  });


  testWidgets('Show Report opens and executes immediately with Frappe-style filters', (tester) async {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final registry = WmnDocumentRegistry(database);
    final customization = CustomizationRepository(database);
    final meta = WmnMetaService(database: database, registry: registry, customization: customization);
    final builder = ReportBuilderService(database: database, customization: customization, meta: meta);
    final scripts = WmnScriptReportService(database: database);
    WmnBuiltinReportHandlers.register(database: database, scriptReports: scripts);
    final reports = WmnFrappeReportService(
      database: database,
      reportBuilder: builder,
      queryReports: WmnQueryReportService(database: database),
      scriptReports: scripts,
    );
    final locale = WmnLocaleController(SettingsRepository(database));
    locale.setLanguage('en');

    await tester.pumpWidget(
      WmnL10nScope(
        controller: locale,
        child: MaterialApp(
          home: Scaffold(
            body: WmnApplicationReportPage(
              reportName: 'Example - Query Report - DocType Search',
              service: reports,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Example - Query Report - DocType Search'), findsOneWidget);
    expect(find.text('Working Example Report'), findsOneWidget);
    expect(find.text('Run Report'), findsNothing);
    expect(find.text('Refresh'), findsOneWidget);

    final pageList = find.byType(ListView).first;
    await tester.dragUntilVisible(
      find.text('Report Filters'),
      pageList,
      const Offset(0, -240),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('report-filter:module')), findsOneWidget);
    expect(find.byKey(const ValueKey('report-filter:doctype')), findsOneWidget);
    expect(find.byKey(const ValueKey('report-filter:created_from')), findsOneWidget);
    expect(find.byKey(const ValueKey('report-filter:enabled_state')), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('Report Results'),
      pageList,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Rows'), findsWidgets);
    expect(find.text('Report Results'), findsOneWidget);
    expect(find.byType(PaginatedDataTable), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byType(PaginatedDataTable),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    final tableSize = tester.getSize(find.byType(PaginatedDataTable));
    expect(tableSize.width, greaterThan(300));
    expect(tableSize.height, greaterThan(100));
    expect(find.text('DocType'), findsWidgets);
    expect(find.text('Module'), findsWidgets);
    expect(find.text('Storage Mode'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('Report metadata fields explain the three creation paths', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final fields = database.db.select('''
      SELECT fieldname,metadata_json
      FROM wmn_doctype_fields
      WHERE doctype='Report' AND fieldname IN (
        'report_type','ref_doctype','filters_json','columns_json',
        'query_definition_json','script_key'
      )
      ORDER BY fieldname;
    ''');
    expect(fields, hasLength(6));
    for (final row in fields) {
      expect('${row['metadata_json']}', contains('description'));
    }
  });
}
