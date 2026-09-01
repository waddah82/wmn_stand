-- WMN Platform schema v23 delta: Identity & Permissions Runtime
ALTER TABLE role_permissions ADD COLUMN id TEXT;
UPDATE role_permissions SET id = role_id || ':' || permission_id WHERE id IS NULL OR trim(id) = '';
CREATE UNIQUE INDEX IF NOT EXISTS idx_role_permissions_id ON role_permissions(id);
-- Security System DocType registrations are executed by Migration023IdentityPermissionsRuntime.
