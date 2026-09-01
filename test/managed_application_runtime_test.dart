import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/audit/audit_service.dart';
import 'package:wmn_standalone/core/database/wmn_database.dart';
import 'package:wmn_standalone/core/documents/document_registry.dart';
import 'package:wmn_standalone/core/settings/settings_repository.dart';
import 'package:wmn_standalone/framework/frappe_compat/frappe_runtime.dart';
import 'package:wmn_standalone/framework/meta/meta_service.dart';
import 'package:wmn_standalone/framework/model/document_service.dart';
import 'package:wmn_standalone/modules/customization/data/customization_repository.dart';
import 'package:wmn_standalone/platform/scripts/wmn_managed_procedure_runtime.dart';
import 'package:wmn_standalone/platform/scripts/wmn_script_runtime.dart';
import 'package:wmn_standalone/platform/storage/wmn_storage_adapter.dart';
import 'package:wmn_standalone/platform/storage/wmn_storage_service.dart';

void main() {
  test('imported persistent document hook executes without rebuilding or restarting host', () {
    final fixture = _ManagedAppFixture();
    addTearDown(fixture.close);

    fixture.installScript(
      id: 'demo-note-validate',
      doctype: 'Managed Note',
      event: 'before_validate',
      source: <String, Object?>{
        'language': WmnManagedProcedureRuntime.language,
        'version': 1,
        'steps': <Object?>[
          <String, Object?>{
            'op': 'set',
            'path': 'doc.title',
            'value': <String, Object?>{
              'concat': <Object?>['Managed: ', <String, Object?>{'get': 'doc.title'}],
            },
          },
        ],
      },
    );

    final saved = fixture.runtime.documents.insert(
      'Managed Note',
      <String, Object?>{'title': 'Invoice'},
    );

    expect(saved['title'], 'Managed: Invoice');
  });

  test('managed application procedure may write only DocTypes owned by its source app', () {
    final fixture = _ManagedAppFixture();
    addTearDown(fixture.close);

    final source = jsonEncode(<String, Object?>{
      'language': WmnManagedProcedureRuntime.language,
      'version': 1,
      'steps': <Object?>[
        <String, Object?>{
          'op': 'db_insert',
          'doctype': 'System Note',
          'values': <String, Object?>{'title': 'Blocked'},
        },
      ],
    });

    expect(
      () => fixture.managed.execute(source, <String, Object?>{'source_app': 'demo_app'}),
      throwsStateError,
    );
    expect(fixture.documents.list('System Note').total, 0);
  });


  test('managed application may write its own engine-owned DocType without opening generic UI writes', () {
    final fixture = _ManagedAppFixture();
    addTearDown(fixture.close);

    final source = jsonEncode(<String, Object?>{
      'language': WmnManagedProcedureRuntime.language,
      'version': 1,
      'steps': <Object?>[
        <String, Object?>{
          'op': 'db_insert',
          'doctype': 'Engine Ledger',
          'values': <String, Object?>{'name': 'LEDGER-1', 'amount': 125.0},
        },
      ],
    });

    expect(
      () => fixture.documents.save('Engine Ledger', <String, Object?>{'name': 'MANUAL-1', 'amount': 1.0}),
      throwsStateError,
    );

    fixture.managed.execute(source, <String, Object?>{'source_app': 'demo_app'});
    final row = fixture.documents.get('Engine Ledger', 'LEDGER-1');
    expect(row, isNotNull);
    expect(row!['amount'], 125.0);
    expect(() => fixture.documents.delete('Engine Ledger', 'LEDGER-1'), throwsStateError);

    fixture.managed.execute(
      jsonEncode(<String, Object?>{
        'language': WmnManagedProcedureRuntime.language,
        'version': 1,
        'steps': <Object?>[
          <String, Object?>{'op': 'db_delete', 'doctype': 'Engine Ledger', 'name': 'LEDGER-1'},
        ],
      }),
      <String, Object?>{'source_app': 'demo_app'},
    );
    expect(fixture.documents.get('Engine Ledger', 'LEDGER-1'), isNull);
  });

  test('managed procedure generic map/list/string/number primitives are application-neutral', () {
    final fixture = _ManagedAppFixture();
    addTearDown(fixture.close);

    final result = fixture.managed.execute(
      jsonEncode(<String, Object?>{
        'language': WmnManagedProcedureRuntime.language,
        'version': 1,
        'steps': <Object?>[
          <String, Object?>{
            'op': 'let',
            'name': 'state',
            'value': <String, Object?>{
              'data': <String, Object?>{},
              'items': <Object?>[],
            },
          },
          <String, Object?>{
            'op': 'map_put',
            'path': 'state.data',
            'key': 'segment',
            'value': <String, Object?>{
              'slice': <String, Object?>{
                'value': '2012345003000',
                'start': 2,
                'length': 5,
              },
            },
          },
          <String, Object?>{
            'op': 'append',
            'path': 'state.items',
            'value': <String, Object?>{'to_number': '003000'},
          },
          <String, Object?>{
            'op': 'return',
            'value': <String, Object?>{
              'segment': <String, Object?>{'get': 'state.data.segment'},
              'number': <String, Object?>{'get': 'state.items.0'},
              'starts': <String, Object?>{
                'starts_with': <Object?>['2012345', '20'],
              },
              'ends': <String, Object?>{
                'ends_with': <Object?>['2012345', '45'],
              },
              'floor': <String, Object?>{'floor': 3.99},
            },
          },
        ],
      }),
      const <String, Object?>{'source_app': 'demo_app'},
    );

    expect(result, isA<Map>());
    final map = Map<String, Object?>.from(result! as Map);
    expect(map['segment'], '12345');
    expect(map['number'], 3000.0);
    expect(map['starts'], isTrue);
    expect(map['ends'], isTrue);
    expect(map['floor'], 3.0);
  });

  test('managed API Server Script method executes through persistent method binding', () {
    final fixture = _ManagedAppFixture();
    addTearDown(fixture.close);
    const path = 'apps/demo_app/sources/server/demo-total.json';
    fixture.storage.writeText(
      path,
      jsonEncode(<String, Object?>{
        'language': WmnManagedProcedureRuntime.language,
        'version': 1,
        'steps': <Object?>[
          <String, Object?>{
            'op': 'return',
            'value': <String, Object?>{
              'add': <Object?>[
                <String, Object?>{'get': 'a'},
                <String, Object?>{'get': 'b'},
              ],
            },
          },
        ],
      }),
    );
    final now = DateTime.now().toUtc().toIso8601String();
    fixture.database.db.execute(
      '''
      INSERT INTO server_scripts(
        id,name,script_type,api_method,priority,enabled,created_at,updated_at,source_storage_path
      ) VALUES (?,?, 'API', ?,0,1,?,?,?);
      ''',
      <Object?>['demo-total', 'demo-total', 'demo.total', now, now, path],
    );
    fixture.database.db.execute(
      '''
      INSERT INTO wmn_method_bindings(
        method_name,handler_kind,target,allow_guest,enabled,source_app,metadata_json,updated_at
      ) VALUES (?,'SERVER_SCRIPT',?,0,1,?,?,?);
      ''',
      <Object?>[
        'demo.total',
        'demo-total',
        'demo_app',
        jsonEncode(<String, Object?>{'script_language': WmnManagedProcedureRuntime.language}),
        now,
      ],
    );

    expect(fixture.runtime.call('demo.total', <String, Object?>{'a': 7, 'b': 5}), 12.0);
  });
}

class _ManagedAppFixture {
  _ManagedAppFixture() {
    database = WmnDatabase.forTesting(sqlite3.openInMemory());
    final audit = AuditService(database);
    final settings = SettingsRepository(database);
    final registry = WmnDocumentRegistry(database);
    final customization = CustomizationRepository(database);
    meta = WmnMetaService(
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
    storage = WmnStorageService(WmnMemoryStorageAdapter());
    scripts = WmnScriptRuntime(storage: storage);
    managed = WmnManagedProcedureRuntime(
      database: database,
      meta: meta,
      documents: documents,
    );
    scripts.registerManagedExecutor(WmnManagedProcedureRuntime.language, managed.execute);
    runtime = WmnFrappeRuntime.create(
      database: database,
      settings: settings,
      metaService: meta,
      documentService: documents,
      audit: audit,
      scriptRuntime: scripts,
    );

    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute(
      '''
      INSERT INTO wmn_app_packages(
        app_name,app_title,app_version,source_framework,module_json,manifest_json,
        conversion_status,installed_at,updated_at
      ) VALUES ('demo_app','Demo App','1.0.0','WMN','{}','{}','READY',?,?);
      ''',
      <Object?>[now, now],
    );
    meta.saveModule(name: 'Demo App');
    database.db.execute("UPDATE wmn_modules SET app_name='demo_app' WHERE name='Demo App';");
    meta.saveDocType(name: 'Managed Note', module: 'Demo App', titleField: 'title');
    meta.saveField(
      doctype: 'Managed Note',
      fieldName: 'title',
      label: 'Title',
      fieldType: 'Data',
      required: true,
    );
    meta.saveDocType(name: 'System Note', module: 'Custom', titleField: 'title');
    meta.saveField(
      doctype: 'System Note',
      fieldName: 'title',
      label: 'Title',
      fieldType: 'Data',
      required: true,
    );
    meta.saveDocType(
      name: 'Engine Ledger',
      module: 'Demo App',
      genericWrite: false,
      allowCreate: false,
      allowEdit: false,
      allowDelete: false,
    );
    meta.saveField(
      doctype: 'Engine Ledger',
      fieldName: 'amount',
      label: 'Amount',
      fieldType: 'Currency',
      required: true,
    );
  }

  late final WmnDatabase database;
  late final WmnMetaService meta;
  late final WmnDocumentService documents;
  late final WmnStorageService storage;
  late final WmnScriptRuntime scripts;
  late final WmnManagedProcedureRuntime managed;
  late final WmnFrappeRuntime runtime;

  void installScript({
    required String id,
    required String doctype,
    required String event,
    required Map<String, Object?> source,
  }) {
    final path = 'apps/demo_app/sources/server/$id.json';
    storage.writeText(path, jsonEncode(source));
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute(
      '''
      INSERT INTO server_scripts(
        id,name,script_type,document_type,event_name,priority,enabled,created_at,updated_at,source_storage_path
      ) VALUES (?,?,'DOCUMENT_EVENT',?,?,0,1,?,?,?);
      ''',
      <Object?>[id, id, doctype, event, now, now, path],
    );
    runtime.hooks.saveBinding(
      id: 'hook-$id',
      hookType: 'DOCUMENT_EVENT',
      referenceDoctype: doctype,
      eventName: event,
      sourceApp: 'demo_app',
      sourcePath: path,
      targetKind: 'SERVER_SCRIPT',
      target: id,
      metadata: const <String, Object?>{
        'script_language': WmnManagedProcedureRuntime.language,
      },
    );
  }

  void close() => database.close();
}
