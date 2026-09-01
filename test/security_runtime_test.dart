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

void main() {
  test('security System DocTypes are native metadata over platform tables', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final rows = database.db.select(
      "SELECT name,table_name FROM wmn_doctypes WHERE module='Security';",
    );
    final mapping = <String, String>{
      for (final row in rows) '${row['name']}': '${row['table_name']}',
    };
    expect(
      mapping.keys,
      containsAll(<String>[
        'User','Role','Permission','User Role','Role Permission',
        'DocType Permission','User Permission','Document Share',
      ]),
    );
    expect(mapping['Role Permission'], 'role_permissions');
  });

  test('repeated permission checks reuse one lightweight user snapshot', () {
    final fixture = _SecurityFixture.create();
    addTearDown(fixture.dispose);
    fixture.runtime.permissions.rolesFor();
    fixture.runtime.permissions.hasPermission('User', 'read');
    fixture.runtime.permissions.hasPermission('Role', 'read');
    fixture.runtime.permissions.rolesFor();
    expect(fixture.runtime.security.debugSnapshotBuildCount, 1);
  });

  test('role permission codes and DocType permissions resolve from one snapshot', () {
    final fixture = _SecurityFixture.create(user: 'demo-security-user');
    addTearDown(fixture.dispose);
    final now = DateTime.now().toUtc().toIso8601String();
    fixture.database.db.execute(
      'INSERT INTO roles(id,code,name,is_system,enabled,created_at,updated_at) VALUES (?,?,?,?,?,?,?);',
      <Object?>['role-security','SECURITY_USER','Security User',0,1,now,now],
    );
    fixture.database.db.execute(
      'INSERT INTO permissions(id,code,module,resource,action,description,created_at) VALUES (?,?,?,?,?,?,?);',
      <Object?>[
        'permission-demo-console',
        'demo.security.console',
        'Security',
        'security',
        'console',
        'Demo global permission',
        now,
      ],
    );
    fixture.database.db.execute(
      'INSERT INTO role_permissions(role_id,permission_id,granted,id) VALUES (?,?,?,?);',
      <Object?>[
        'role-security',
        'permission-demo-console',
        1,
        'role-security:permission-demo-console',
      ],
    );
    fixture.database.db.execute(
      'INSERT INTO user_roles(id,user_id,role_id,assigned_at) VALUES (?,?,?,?);',
      <Object?>['user-role-security','demo-security-user','role-security',now],
    );
    fixture.database.db.execute('''
      INSERT INTO wmn_doctype_permissions(
        id,doctype,role,permlevel,can_read,can_write,can_create,can_delete,
        can_submit,can_cancel,can_amend,can_report,can_import,can_export,
        can_share,can_print,can_email,if_owner,metadata_json
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
    ''', <Object?>[
      'docperm-security-role','User','Security User',0,
      1,0,0,0,0,0,0,0,0,0,0,0,0,0,'{}',
    ]);
    fixture.runtime.permissions.invalidate();
    expect(fixture.runtime.permissions.hasSystemPermission('demo.security.console'), isTrue);
    expect(fixture.runtime.permissions.hasPermission('User', 'read'), isTrue);
    expect(fixture.runtime.permissions.hasPermission('User', 'write'), isFalse);
    expect(fixture.runtime.security.debugSnapshotBuildCount, 1);
  });

  test('document shares cannot bypass Security System DocType gates', () {
    final fixture = _SecurityFixture.create(user: 'demo-security-user');
    addTearDown(fixture.dispose);
    final now = DateTime.now().toUtc().toIso8601String();
    fixture.database.db.execute(
      '''
      INSERT INTO wmn_doc_shares(
        id,doctype,docname,user_id,can_read,can_write,can_share,can_submit,
        created_by,created_at,updated_at
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?);
      ''',
      <Object?>[
        'share-security-user',
        'User',
        'demo-security-user',
        'demo-security-user',
        1,
        1,
        1,
        0,
        'Administrator',
        now,
        now,
      ],
    );
    fixture.runtime.permissions.invalidate();
    expect(
      fixture.runtime.permissions.hasPermission(
        'User',
        'write',
        docname: 'demo-security-user',
      ),
      isFalse,
    );
  });

  test('changing the session user reuses cached identities when possible', () {
    final fixture = _SecurityFixture.create(user: 'demo-security-user');
    addTearDown(fixture.dispose);
    expect(fixture.runtime.permissions.rolesFor(), contains('All'));
    expect(fixture.runtime.permissions.hasPermission('User', 'write'), isFalse);
    expect(fixture.runtime.security.debugSnapshotBuildCount, 1);
    fixture.runtime.session.setUser('Guest');
    expect(fixture.runtime.permissions.rolesFor(), contains('Guest'));
    expect(fixture.runtime.security.debugSnapshotBuildCount, 2);
    fixture.runtime.session.setUser('demo-security-user');
    expect(fixture.runtime.permissions.rolesFor(), contains('All'));
    expect(fixture.runtime.security.debugSnapshotBuildCount, 2);
  });
}

class _SecurityFixture {
  _SecurityFixture({required this.database, required this.runtime});
  final WmnDatabase database;
  final WmnFrappeRuntime runtime;

  static _SecurityFixture create({String user = 'Administrator'}) {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    final settings = SettingsRepository(database);
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute(
      'INSERT INTO [tabUser](id,username,display_name,role,enabled,created_at,updated_at) VALUES (?,?,?,?,?,?,?);',
      <Object?>['demo-security-user','demo-security-user','Demo Security User','USER',1,now,now],
    );
    settings.setString('frappe_compat.current_user', user);
    final registry = WmnDocumentRegistry(database);
    final customization = CustomizationRepository(database);
    final meta = WmnMetaService(database: database, registry: registry, customization: customization);
    final audit = AuditService(database);
    final documents = WmnDocumentService(
      database: database,
      meta: meta,
      customization: customization,
      audit: audit,
    );
    final runtime = WmnFrappeRuntime.create(
      database: database,
      settings: settings,
      metaService: meta,
      documentService: documents,
      audit: audit,
    );
    return _SecurityFixture(database: database, runtime: runtime);
  }

  void dispose() => database.close();
}
