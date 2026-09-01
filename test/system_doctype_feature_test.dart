import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/database/wmn_database.dart';
import 'package:wmn_standalone/core/settings/settings_repository.dart';
import 'package:wmn_standalone/platform/capabilities/wmn_capability_registry.dart';
import 'package:wmn_standalone/platform/features/wmn_feature_registry.dart';
import 'package:wmn_standalone/platform/system/wmn_system_module_registry.dart';

void main() {
  test('R3.7 registers platform configuration as System DocTypes', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);

    final rows = database.db.select(
      'SELECT name,table_name,is_system FROM wmn_doctypes WHERE is_system=1;',
    );
    final mappings = <String, String?>{
      for (final row in rows) '${row['name']}': row['table_name']?.toString(),
    };

    expect(
      mappings.keys,
      containsAll(<String>[
        'User',
        'Role',
        'Page',
        'Workspace',
        'Report',
        'Print Format',
        'Print Settings',
        'Printer',
        'Notification',
        'Scheduled Job',
        'File',
        'System Setting',
        'System Log',
        'Audit Log',
        'Background Job',
        'Feature',
        'Feature Entitlement',
        'Feature Activation',
      ]),
    );
    expect(mappings['Page'], 'tabPage');
    expect(mappings['Report'], 'tabReport');
    expect(mappings['Printer'], 'wmn_printers');
  });

  test('Report System DocType preserves Query Report and Script Report types', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);

    final row = database.db.select(
      "SELECT metadata_json FROM wmn_doctypes WHERE name='Report' LIMIT 1;",
    ).single;
    final metadata = '${row['metadata_json']}';
    expect(metadata, contains('Query Report'));
    expect(metadata, contains('Script Report'));
  });

  test('feature entitlement and user activation jointly gate optional capabilities', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final settings = SettingsRepository(database);
    final modules = WmnSystemModuleRegistry(settings);
    final features = WmnFeatureRegistry(database);
    addTearDown(features.dispose);
    final capabilities = WmnCapabilityRegistry(modules, features: features);
    addTearDown(capabilities.dispose);

    expect(capabilities.isAvailable('query-reports'), isTrue);

    final queryFeature = features.definitions().singleWhere(
          (feature) => feature.code == 'reports.query',
        );
    expect(features.setUserEnabled(queryFeature.id, false), isTrue);
    expect(capabilities.isAvailable('query-reports'), isFalse);

    expect(features.setUserEnabled(queryFeature.id, true), isTrue);
    expect(capabilities.isAvailable('query-reports'), isTrue);

    database.db.execute(
      "UPDATE wmn_feature_entitlements SET status='REVOKED' WHERE feature_id=?;",
      [queryFeature.id],
    );
    features.reload();
    expect(features.setUserEnabled(queryFeature.id, true), isFalse);
    expect(capabilities.isAvailable('query-reports'), isFalse);
  });

  test('core feature cannot be disabled by the user', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final features = WmnFeatureRegistry(database);
    addTearDown(features.dispose);

    final core = features.definitions().singleWhere(
          (feature) => feature.code == 'core.platform',
        );
    expect(core.isCore, isTrue);
    expect(core.effectiveEnabled, isTrue);
    expect(features.setUserEnabled(core.id, false), isFalse);
  });


  test('feature activation is local to the installation scope', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final phone = WmnFeatureRegistry(database, activationScopeKey: 'phone-old');
    final desktop = WmnFeatureRegistry(database, activationScopeKey: 'desktop-main');
    addTearDown(phone.dispose);
    addTearDown(desktop.dispose);

    final queryFeature = phone.definitions().singleWhere(
          (feature) => feature.code == 'reports.query',
        );
    expect(phone.setUserEnabled(queryFeature.id, false), isTrue);
    expect(phone.isFeatureEnabled('reports.query'), isFalse);
    expect(desktop.isFeatureEnabled('reports.query'), isTrue);
  });

  test('feature definitions are cached until an explicit entitlement reload', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final features = WmnFeatureRegistry(database);
    addTearDown(features.dispose);

    expect(features.byCode('reports.query')?.priceAmount, 0);
    database.db.execute(
      "UPDATE wmn_features SET price_amount=9.99 WHERE code='reports.query';",
    );
    expect(features.byCode('reports.query')?.priceAmount, 0);
    features.reload();
    expect(features.byCode('reports.query')?.priceAmount, 9.99);
  });
  test('DocType is a native read-only System DocType for Link targets', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final rows = database.db.select(
      "SELECT table_name,generic_write,allow_create,allow_edit FROM wmn_doctypes WHERE name='DocType' LIMIT 1;",
    );
    expect(rows, hasLength(1));
    expect(rows.single['table_name'], 'wmn_doctypes');
    expect(rows.single['generic_write'], 0);
    expect(rows.single['allow_create'], 0);
    expect(rows.single['allow_edit'], 0);
    final names = database.db
        .select("SELECT name FROM wmn_doctypes WHERE enabled=1 ORDER BY name;")
        .map((row) => '${row['name']}')
        .toSet();
    expect(names, containsAll(<String>['DocType', 'Report', 'Role', 'Workflow']));
  });

  test('Role System DocType exposes required editable code and name fields', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final fields = database.db.select(
      "SELECT fieldname,reqd,read_only,hidden FROM wmn_doctype_fields WHERE doctype='Role';",
    );
    final byName = <String, Map<String, Object?>>{
      for (final row in fields) '${row['fieldname']}': Map<String, Object?>.from(row),
    };
    expect(byName['code']?['reqd'], 1);
    expect(byName['code']?['read_only'], 0);
    expect(byName['code']?['hidden'], 0);
    expect(byName['name']?['reqd'], 1);
    expect(byName['name']?['hidden'], 0);
  });

}
