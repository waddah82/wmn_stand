import 'database_migration.dart';

/// R3.8 identity and permission runtime consolidation.
///
/// Security configuration remains metadata-driven, while permission evaluation
/// is owned by a lightweight cached runtime. No business-domain tables are
/// introduced here.
class Migration023IdentityPermissionsRuntime extends SqlDatabaseMigration {
  const Migration023IdentityPermissionsRuntime();

  @override
  int get version => 23;

  @override
  String get name => 'identity_permissions_runtime';

  @override
  String get sql => r'''
ALTER TABLE role_permissions ADD COLUMN id TEXT;
UPDATE role_permissions
SET id = role_id || ':' || permission_id
WHERE id IS NULL OR trim(id) = '';
CREATE UNIQUE INDEX IF NOT EXISTS idx_role_permissions_id ON role_permissions(id);

CREATE INDEX IF NOT EXISTS idx_roles_enabled_code ON roles(enabled, code, name);
CREATE INDEX IF NOT EXISTS idx_permissions_code ON permissions(code);
CREATE INDEX IF NOT EXISTS idx_role_permissions_role_granted ON role_permissions(role_id, granted, permission_id);
CREATE INDEX IF NOT EXISTS idx_wmn_doctype_permissions_doctype_role ON wmn_doctype_permissions(doctype, role, permlevel);
CREATE INDEX IF NOT EXISTS idx_wmn_user_permissions_user_enabled ON wmn_user_permissions(user_id, enabled, allow_doctype, applicable_for);

INSERT INTO permissions(id,code,module,resource,action,description,created_at)
VALUES('wmn-permission-security-manage','wmn.security.manage','Security','security','manage','Manage WMN identity and permission metadata',datetime('now'))
ON CONFLICT(code) DO NOTHING;

INSERT INTO wmn_doctypes(name,module,storage_mode,table_name,id_field,title_field,autoname,is_single,is_child,is_submittable,track_changes,allow_create,allow_edit,allow_delete,allow_import,allow_export,generic_write,is_system,enabled,metadata_json,created_at,updated_at)
VALUES
('Role Permission','Security','TABLE','role_permissions','id','permission_id',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{"security_owned":true}',datetime('now'),datetime('now')),
('DocType Permission','Security','TABLE','wmn_doctype_permissions','id','doctype',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{"security_owned":true}',datetime('now'),datetime('now')),
('User Permission','Security','TABLE','wmn_user_permissions','id','for_value',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{"security_owned":true}',datetime('now'),datetime('now')),
('Document Share','Security','TABLE','wmn_doc_shares','id','docname',NULL,0,0,0,1,1,1,1,1,1,1,1,1,'{"security_owned":true}',datetime('now'),datetime('now'))
ON CONFLICT(name) DO UPDATE SET
  module=excluded.module,storage_mode=excluded.storage_mode,table_name=excluded.table_name,id_field=excluded.id_field,
  title_field=excluded.title_field,generic_write=excluded.generic_write,is_system=1,enabled=1,
  metadata_json=excluded.metadata_json,updated_at=excluded.updated_at;

UPDATE wmn_doctypes
SET metadata_json='{"security_owned":true}', updated_at=datetime('now')
WHERE name IN ('User','Role','Permission','User Role');

UPDATE wmn_features
SET capability_ids_json='["lifecycle","doctype","metadata","create","save","sqlite","transactions","shell","i18n","system-settings","feature-registry","entitlements","feature-activation","users","roles","permissions","identity-context","permission-snapshot","user-permissions","document-sharing"]',
    updated_at=datetime('now')
WHERE code='core.platform';
''';
}
