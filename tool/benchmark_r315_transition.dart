import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'package:wmn_standalone/core/database/wmn_database.dart';
import 'package:wmn_standalone/core/documents/document_registry.dart';
import 'package:wmn_standalone/framework/apps/frappe_source_porter.dart';
import 'package:wmn_standalone/framework/meta/meta_service.dart';
import 'package:wmn_standalone/modules/customization/data/customization_repository.dart';
import 'package:wmn_standalone/modules/reporting/application/frappe_report_service.dart';
import 'package:wmn_standalone/modules/reporting/application/query_report_service.dart';
import 'package:wmn_standalone/modules/reporting/application/report_builder_service.dart';
import 'package:wmn_standalone/modules/reporting/application/script_report_service.dart';
import 'package:wmn_standalone/platform/storage/wmn_storage_native.dart';
import 'package:wmn_standalone/platform/storage/wmn_storage_service.dart';

Future<Map<String, num>> runR315TransitionBenchmark() async {
  final temp = await Directory.systemTemp.createTemp('wmn-r315-benchmark-');
  try {
    final storage = WmnStorageService(WmnDirectoryStorageAdapter(temp.path));
    final results = <String, num>{};

    const smallSource = 'SELECT name, amount FROM benchmark_rows WHERE amount >= %(minimum)s ORDER BY amount';
    var watch = Stopwatch()..start();
    storage.writeText('apps/demo/reports/benchmark/query.sql', smallSource);
    storage.clearTextCache();
    final firstRead = storage.readText('apps/demo/reports/benchmark/query.sql');
    watch.stop();
    if (firstRead != smallSource) throw StateError('Small source read mismatch.');
    results['small_source_first_read_us'] = watch.elapsedMicroseconds;

    watch = Stopwatch()..start();
    for (var i = 0; i < 10000; i++) {
      storage.readText('apps/demo/reports/benchmark/query.sql');
    }
    watch.stop();
    results['small_source_cached_10000_reads_us'] = watch.elapsedMicroseconds;

    final largeBytes = Uint8List.fromList(
      List<int>.generate(10 * 1024 * 1024, (index) => index % 251, growable: false),
    );
    watch = Stopwatch()..start();
    await storage.writeBytesAsync('files/private/benchmark/10mb.bin', largeBytes);
    watch.stop();
    results['file_10mb_async_write_ms'] = watch.elapsedMilliseconds;

    watch = Stopwatch()..start();
    final largeRead = await storage.readBytesAsync('files/private/benchmark/10mb.bin');
    watch.stop();
    if (largeRead.length != largeBytes.length || largeRead.first != largeBytes.first || largeRead.last != largeBytes.last) {
      throw StateError('Large storage read mismatch.');
    }
    results['file_10mb_async_read_ms'] = watch.elapsedMilliseconds;

    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    try {
      database.db.execute('CREATE TABLE benchmark_rows(name TEXT PRIMARY KEY, amount INTEGER NOT NULL);');
      database.db.execute('''
        WITH RECURSIVE sequence(value) AS (
          SELECT 0
          UNION ALL
          SELECT value + 1 FROM sequence WHERE value < 4999
        )
        INSERT INTO benchmark_rows(name,amount)
        SELECT 'ROW-' || value, value FROM sequence;
      ''');

      final registry = WmnDocumentRegistry(database);
      final customization = CustomizationRepository(database);
      final meta = WmnMetaService(database: database, registry: registry, customization: customization);
      final reportBuilder = ReportBuilderService(database: database, customization: customization, meta: meta);
      final scripts = WmnScriptReportService(database: database, storage: storage);
      final reports = WmnFrappeReportService(
        database: database,
        reportBuilder: reportBuilder,
        queryReports: WmnQueryReportService(database: database),
        scriptReports: scripts,
        storage: storage,
      );
      reports.saveDefinition(const WmnFrappeReportDefinition(
        name: 'R315 Benchmark Report',
        reportName: 'R315 Benchmark Report',
        reportType: 'Query Report',
        module: 'Demo',
        queryDefinition: <String, Object?>{
          'sql': 'SELECT name, amount FROM benchmark_rows WHERE amount >= %(minimum)s ORDER BY amount',
          'max_rows': 5000,
        },
        filters: <Map<String, Object?>>[
          <String, Object?>{'fieldname': 'minimum', 'label': 'Minimum', 'required': true},
        ],
      ));

      watch = Stopwatch()..start();
      final execution = reports.execute('R315 Benchmark Report', filters: const <String, Object?>{'minimum': 0});
      watch.stop();
      if (execution.rows.length != 5000) throw StateError('Query Report benchmark did not return 5000 rows.');
      results['query_report_5000_rows_total_ms'] = watch.elapsedMilliseconds;
      results['query_report_engine_ms'] = execution.durationMs;

      database.db.execute('''
        INSERT INTO wmn_app_packages(
          app_name,app_title,source_framework,module_json,manifest_json,
          conversion_status,installed_at,updated_at
        ) VALUES ('bench','Bench','FRAPPE','{}','{}','IMPORTED',CURRENT_TIMESTAMP,CURRENT_TIMESTAMP);
      ''');
      final porter = WmnFrappeSourcePorter(database: database, storage: storage);
      const source = 'frappe.ui.form.on("Customer", { refresh(frm) { frappe.msgprint("Hi"); } });';
      final analysis = porter.analyzeJavaScript(source, doctype: 'Customer', sourcePath: 'customer.js');
      for (var i = 0; i < 1000; i++) {
        porter.saveSourceUnit(
          appName: 'bench',
          sourcePath: 'module_$i/source_$i.js',
          source: '$source // $i',
          result: analysis,
        );
      }

      storage.clearTextCache();
      watch = Stopwatch()..start();
      final sourceUnits = porter.sourceUnits('bench');
      watch.stop();
      if (sourceUnits.length != 1000) throw StateError('Source-unit metadata benchmark count mismatch.');
      if (sourceUnits.any((row) => row.containsKey('source_code') || row.containsKey('converted_code'))) {
        throw StateError('Source-unit list eagerly hydrated source content.');
      }
      results['source_units_1000_metadata_list_ms'] = watch.elapsedMilliseconds;

      watch = Stopwatch()..start();
      final one = porter.sourceUnit('${sourceUnits[Random(7).nextInt(sourceUnits.length)]['id']}');
      watch.stop();
      if (one == null || '${one['source_code']}'.isEmpty) throw StateError('Lazy source-unit hydration failed.');
      results['source_unit_single_hydration_us'] = watch.elapsedMicroseconds;
    } finally {
      database.close();
    }

    return results;
  } finally {
    await temp.delete(recursive: true);
  }
}
