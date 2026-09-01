import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/database/wmn_database.dart';

void main() {
  test('platform schema is versioned and business application metadata is not system-owned', () {
    final raw = sqlite3.openInMemory();
    final database = WmnDatabase.forTesting(raw);

    final names = raw
        .select("SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name;")
        .map((row) => row['name'] as String)
        .toSet();

    expect(names, containsAll(<String>[
      'system_meta',
      'app_settings',
      'audit_log',
      'wmn_modules',
      'wmn_doctypes',
      'wmn_doctype_fields',
      'wmn_doctype_permissions',
      'tabWorkspace',
      'wmn_workspace_items',
      'tabWorkspaceItem',
      'tabReport',
      'tabReport Filter',
      'tabReport Column',
      'wmn_storage_blobs',
      'data_import_jobs',
      'wmn_scoped_settings',
      'wmn_system_logs',
      'wmn_schedules',
      'wmn_notifications',
      'tabPage',
      'wmn_printers',
      'wmn_features',
      'wmn_feature_entitlements',
    ]));

    final registered = raw.select('SELECT name FROM wmn_doctypes;').map((row) => row['name']).toSet();
    expect(registered, isNot(contains('POS Profile')));
    expect(registered, isNot(contains('Sales Invoice')));
    expect(registered, isNot(contains('Customer')));
    expect(registered, isNot(contains('Account')));

    final modules = raw.select('SELECT name FROM wmn_modules;').map((row) => row['name']).toSet();
    expect(modules, contains('WMN System'));
    expect(modules, contains('Security'));
    expect(modules, isNot(contains('Selling')));
    expect(modules, isNot(contains('Buying')));
    expect(modules, isNot(contains('Accounts')));

    final version = raw.select(
      "SELECT value FROM system_meta WHERE key = 'schema_version';",
    ).first['value'];
    expect(version, WmnDatabase.schemaVersion.toString());
    expect(WmnDatabase.schemaVersion, 36);
    expect(names, isNot(contains('custom_reports')));
    expect(names, isNot(contains('wmn_script_reports')));
    expect(names, isNot(contains('wmn_file_contents')));

    final reportColumns = raw.select('PRAGMA table_info("tabReport");').map((row) => row['name']).toSet();
    expect(reportColumns, containsAll(<String>['query_source_type','query_source_path','script_source_type','script_source_path','script_language']));
    final sourceColumns = raw.select('PRAGMA table_info(wmn_app_source_units);').map((row) => row['name']).toSet();
    expect(sourceColumns, containsAll(<String>['source_storage_path','converted_storage_path']));
    expect(sourceColumns, isNot(contains('source_code')));
    expect(sourceColumns, isNot(contains('converted_code')));

    database.close();
  });
  test('nested platform transactions use savepoints and keep the outer transaction atomic', () {
    final raw = sqlite3.openInMemory();
    final database = WmnDatabase.forTesting(raw);
    raw.execute('CREATE TABLE nested_tx_probe(id INTEGER PRIMARY KEY, value TEXT NOT NULL);');

    database.transaction(() {
      raw.execute('INSERT INTO nested_tx_probe(value) VALUES (?);', ['outer']);
      database.transaction(() {
        raw.execute('INSERT INTO nested_tx_probe(value) VALUES (?);', ['inner']);
      });
    });

    expect(raw.select('SELECT value FROM nested_tx_probe ORDER BY id;').map((row) => row['value']).toList(), ['outer', 'inner']);

    expect(
      () => database.transaction(() {
        raw.execute('INSERT INTO nested_tx_probe(value) VALUES (?);', ['outer-rollback']);
        database.transaction(() {
          raw.execute('INSERT INTO nested_tx_probe(value) VALUES (?);', ['inner-rollback']);
        });
        throw StateError('rollback outer transaction');
      }),
      throwsA(isA<StateError>()),
    );

    expect(raw.select('SELECT value FROM nested_tx_probe ORDER BY id;').map((row) => row['value']).toList(), ['outer', 'inner']);
    database.close();
  });

}
