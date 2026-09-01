import '../../core/database/sql_identifier.dart';
import '../../core/database/wmn_database.dart';
import '../../framework/meta/meta_service.dart';
import 'wmn_identity_context.dart';
import 'wmn_identity_service.dart';

class WmnDocTypePermissionGrant {
  const WmnDocTypePermissionGrant({required this.allowed, required this.ownerOnly});

  final Set<String> allowed;
  final Set<String> ownerOnly;

  bool allows(String action) => allowed.contains(action);
  bool allowsOwner(String action) => ownerOnly.contains(action);
}

class WmnUserPermissionValue {
  const WmnUserPermissionValue({
    required this.allowDoctype,
    required this.value,
    required this.applicableFor,
    required this.isDefault,
  });

  final String allowDoctype;
  final String value;
  final String? applicableFor;
  final bool isDefault;
}

class WmnDocTypeAccessProfile {
  const WmnDocTypeAccessProfile({
    required this.name,
    required this.tableName,
    required this.idField,
    required this.enabled,
    required this.isSubmittable,
    required this.allowCreate,
    required this.allowEdit,
    required this.allowDelete,
    required this.allowImport,
    required this.allowExport,
  });

  final String name;
  final String? tableName;
  final String idField;
  final bool enabled;
  final bool isSubmittable;
  final bool allowCreate;
  final bool allowEdit;
  final bool allowDelete;
  final bool allowImport;
  final bool allowExport;
}

class WmnPermissionSnapshot {
  const WmnPermissionSnapshot({
    required this.identity,
    required this.doctypeGrants,
    required this.doctypesWithExplicitRules,
    required this.systemPermissionCodes,
    required this.userPermissions,
  });

  final WmnIdentityContext identity;
  final Map<String, WmnDocTypePermissionGrant> doctypeGrants;
  final Set<String> doctypesWithExplicitRules;
  final Set<String> systemPermissionCodes;
  final List<WmnUserPermissionValue> userPermissions;
}

/// Central cached authorization runtime for WMN.
///
/// Role, role-permission, DocPerm and User Permission rows are loaded into a
/// compact per-user snapshot. Repeated UI/navigation permission checks do not
/// hit SQLite. Document-specific owner/share checks remain targeted reads only
/// when a document name is supplied.
class WmnPermissionService {
  WmnPermissionService({
    required this.database,
    required this.meta,
    required this.identity,
  });

  final WmnDatabase database;
  final WmnMetaService meta;
  final WmnIdentityService identity;

  static const int _snapshotCacheLimit = 4;
  static const Set<String> _securityDoctypes = <String>{
    'User','Role','Permission','User Role','Role Permission',
    'DocType Permission','User Permission','Document Share',
  };

  static const List<String> _actions = <String>[
    'read','write','create','delete','submit','cancel','amend','report',
    'import','export','share','print','email',
  ];

  final Map<String, WmnPermissionSnapshot> _snapshots =
      <String, WmnPermissionSnapshot>{};
  final Map<String, WmnDocTypeAccessProfile> _doctypeAccessCache =
      <String, WmnDocTypeAccessProfile>{};
  final Map<String, bool> _ownerColumnCache = <String, bool>{};
  int _snapshotBuildCount = 0;

  int get debugSnapshotBuildCount => _snapshotBuildCount;

  List<String> rolesFor([String? user]) =>
      List<String>.unmodifiable(snapshot(user).identity.roles);

  bool hasRole(String role, {String? user}) => snapshot(user).identity.hasRole(role);

  bool hasSystemPermission(String code, {String? user}) {
    final current = snapshot(user);
    if (current.identity.isSystemUser) return true;
    return current.systemPermissionCodes.contains(code.trim());
  }

  WmnPermissionSnapshot snapshot([String? user]) {
    final context = identity.resolve(user);
    final cached = _snapshots[context.user];
    if (cached != null && cached.identity.revision == context.revision) return cached;
    final loaded = _loadSnapshot(context);
    if (_snapshots.length >= _snapshotCacheLimit) {
      _snapshots.remove(_snapshots.keys.first);
    }
    _snapshots[context.user] = loaded;
    _snapshotBuildCount += 1;
    return loaded;
  }

  bool hasPermission(
    String doctype,
    String action, {
    String? docname,
    Map<String, Object?>? document,
    String? user,
  }) {
    final normalizedAction = action.trim().toLowerCase();
    if (!_actions.contains(normalizedAction)) return false;

    final current = snapshot(user);
    if (current.identity.isSystemUser) return true;
    final profile = _doctypeAccess(doctype);
    if (profile == null || !profile.enabled) return false;

    final grant = current.doctypeGrants[doctype];
    if (grant != null && grant.allows(normalizedAction)) return true;

    if (_securityDoctypes.contains(doctype)) {
      if (current.systemPermissionCodes.contains('wmn.security.manage')) {
        return true;
      }
      if (grant != null && grant.allowsOwner(normalizedAction)) {
        final owner =
            document?['owner']?.toString() ?? _ownerOf(profile, docname);
        return owner != null && _sameIdentity(owner, current.identity);
      }
      return false;
    }

    if (grant != null && grant.allowsOwner(normalizedAction)) {
      final owner =
          document?['owner']?.toString() ?? _ownerOf(profile, docname);
      if (owner != null && _sameIdentity(owner, current.identity)) return true;
      return docname != null &&
          _sharedPermission(
            doctype,
            docname,
            current.identity,
            normalizedAction,
          );
    }

    if (current.doctypesWithExplicitRules.contains(doctype)) {
      return docname != null &&
          _sharedPermission(
            doctype,
            docname,
            current.identity,
            normalizedAction,
          );
    }

    if (_fallbackAllows(profile, normalizedAction)) return true;
    return docname != null &&
        _sharedPermission(
          doctype,
          docname,
          current.identity,
          normalizedAction,
        );
  }

  Map<String, List<String>> capabilities({String? user}) {
    final current = snapshot(user);
    final result = <String, List<String>>{
      'read': <String>[],
      'write': <String>[],
      'create': <String>[],
      'delete': <String>[],
      'submit': <String>[],
    };
    for (final dt in meta.doctypes()) {
      for (final action in result.keys) {
        if (hasPermission(dt.name, action, user: current.identity.user)) {
          result[action]!.add(dt.name);
        }
      }
    }
    return result;
  }

  List<String> allowedValues(
    String allowDoctype, {
    String? applicableFor,
    String? user,
  }) {
    final current = snapshot(user);
    final values = current.userPermissions.where((entry) {
      if (entry.allowDoctype != allowDoctype) return false;
      final scope = entry.applicableFor?.trim() ?? '';
      return scope.isEmpty || scope == (applicableFor ?? '');
    }).toList(growable: false)
      ..sort((left, right) {
        if (left.isDefault != right.isDefault) return left.isDefault ? -1 : 1;
        return left.value.compareTo(right.value);
      });
    return values.map((entry) => entry.value).toList(growable: false);
  }

  void addUserPermission({
    required String id,
    required String userId,
    required String allowDoctype,
    required String value,
    String? applicableFor,
    bool isDefault = false,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO wmn_user_permissions(
        id,user_id,allow_doctype,for_value,applicable_for,is_default,created_at,updated_at
      ) VALUES (?,?,?,?,?,?,?,?)
      ON CONFLICT(user_id,allow_doctype,for_value,applicable_for) DO UPDATE SET
        is_default=excluded.is_default,updated_at=excluded.updated_at,enabled=1;
    ''', <Object?>[
      id,userId,allowDoctype,value,applicableFor,isDefault ? 1 : 0,now,now,
    ]);
    invalidate(user: userId);
  }

  void invalidate({String? user}) {
    if (user == null) {
      _snapshots.clear();
      identity.invalidate();
      return;
    }
    final normalized = user.trim();
    final keys = <String>{normalized};
    final rows = database.db.select(
      'SELECT id,username FROM [tabUser] WHERE id=? OR username=? LIMIT 1;',
      <Object?>[normalized, normalized],
    );
    if (rows.isNotEmpty) {
      keys.add('${rows.first['id']}');
      keys.add('${rows.first['username']}');
    }
    for (final key in keys) {
      _snapshots.remove(key);
      identity.invalidate(user: key);
    }
  }

  void invalidateMetadata({String? doctype}) {
    if (doctype == null) {
      _doctypeAccessCache.clear();
      _ownerColumnCache.clear();
      return;
    }
    final normalized = doctype.trim();
    _doctypeAccessCache.remove(normalized);
    _ownerColumnCache.remove(normalized);
  }

  WmnPermissionSnapshot _loadSnapshot(WmnIdentityContext context) {
    if (context.isSystemUser) {
      return WmnPermissionSnapshot(
        identity: context,
        doctypeGrants: const <String, WmnDocTypePermissionGrant>{},
        doctypesWithExplicitRules: const <String>{},
        systemPermissionCodes: const <String>{},
        userPermissions: const <WmnUserPermissionValue>[],
      );
    }

    final roles = context.roles;
    final mutableGrants = <String, Map<String, Set<String>>>{};
    final explicitDoctypes = <String>{};
    final systemPermissions = <String>{};

    if (roles.isNotEmpty) {
      final placeholders = List<String>.filled(roles.length, '?').join(',');
      final docRows = database.db.select(
        'SELECT * FROM wmn_doctype_permissions '
        'WHERE role IN ($placeholders) AND permlevel = 0;',
        <Object?>[...roles],
      );
      for (final row in docRows) {
        final doctype = '${row['doctype']}';
        explicitDoctypes.add(doctype);
        final bucket = mutableGrants.putIfAbsent(
          doctype,
          () => <String, Set<String>>{
            'allowed': <String>{},
            'owner': <String>{},
          },
        );
        final ifOwner = (row['if_owner'] as int? ?? 0) == 1;
        for (final action in _actions) {
          final column = _actionColumn(action);
          if (column == null || (row[column] as int? ?? 0) != 1) continue;
          if (ifOwner) {
            if (!bucket['allowed']!.contains(action)) bucket['owner']!.add(action);
          } else {
            bucket['allowed']!.add(action);
            bucket['owner']!.remove(action);
          }
        }
      }

      final rolePermissionRows = database.db.select(
        'SELECT DISTINCT p.code FROM role_permissions rp '
        'JOIN roles r ON r.id = rp.role_id '
        'JOIN permissions p ON p.id = rp.permission_id '
        'WHERE rp.granted = 1 AND r.enabled = 1 '
        'AND (r.name IN ($placeholders) OR r.code IN ($placeholders));',
        <Object?>[...roles, ...roles],
      );
      for (final row in rolePermissionRows) {
        final code = '${row['code'] ?? ''}'.trim();
        if (code.isNotEmpty) systemPermissions.add(code);
      }
    }

    final userPermissions = <WmnUserPermissionValue>[];
    final userId = context.userId;
    if (userId != null) {
      final rows = database.db.select('''
        SELECT allow_doctype,for_value,applicable_for,is_default
        FROM wmn_user_permissions
        WHERE user_id = ? AND enabled = 1;
      ''', <Object?>[userId]);
      for (final row in rows) {
        userPermissions.add(
          WmnUserPermissionValue(
            allowDoctype: '${row['allow_doctype']}',
            value: '${row['for_value']}',
            applicableFor: _nullable(row['applicable_for']),
            isDefault: (row['is_default'] as int? ?? 0) == 1,
          ),
        );
      }
    }

    final grants = <String, WmnDocTypePermissionGrant>{};
    for (final entry in mutableGrants.entries) {
      grants[entry.key] = WmnDocTypePermissionGrant(
        allowed: Set<String>.unmodifiable(entry.value['allowed']!),
        ownerOnly: Set<String>.unmodifiable(entry.value['owner']!),
      );
    }

    return WmnPermissionSnapshot(
      identity: context,
      doctypeGrants: Map<String, WmnDocTypePermissionGrant>.unmodifiable(grants),
      doctypesWithExplicitRules: Set<String>.unmodifiable(explicitDoctypes),
      systemPermissionCodes: Set<String>.unmodifiable(systemPermissions),
      userPermissions: List<WmnUserPermissionValue>.unmodifiable(userPermissions),
    );
  }

  WmnDocTypeAccessProfile? _doctypeAccess(String doctype) {
    final normalized = doctype.trim();
    if (normalized.isEmpty) return null;
    final cached = _doctypeAccessCache[normalized];
    if (cached != null) return cached;

    final rows = database.db.select('''
      SELECT name,table_name,id_field,enabled,is_submittable,allow_create,
             allow_edit,allow_delete,allow_import,allow_export
      FROM wmn_doctypes
      WHERE name = ?
      LIMIT 1;
    ''', <Object?>[normalized]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final profile = WmnDocTypeAccessProfile(
      name: normalized,
      tableName: _nullable(row['table_name']),
      idField: '${row['id_field'] ?? 'name'}',
      enabled: (row['enabled'] as int? ?? 0) == 1,
      isSubmittable: (row['is_submittable'] as int? ?? 0) == 1,
      allowCreate: (row['allow_create'] as int? ?? 0) == 1,
      allowEdit: (row['allow_edit'] as int? ?? 0) == 1,
      allowDelete: (row['allow_delete'] as int? ?? 0) == 1,
      allowImport: (row['allow_import'] as int? ?? 0) == 1,
      allowExport: (row['allow_export'] as int? ?? 0) == 1,
    );
    _doctypeAccessCache[normalized] = profile;
    return profile;
  }

  bool _fallbackAllows(WmnDocTypeAccessProfile profile, String action) =>
      switch (action) {
        'read' || 'report' || 'print' || 'email' => true,
        'create' => profile.allowCreate,
        'write' => profile.allowEdit,
        'delete' => profile.allowDelete,
        'submit' || 'cancel' || 'amend' =>
          profile.isSubmittable && profile.allowEdit,
        'import' => profile.allowImport,
        'export' => profile.allowExport,
        'share' => profile.allowEdit,
        _ => false,
      };

  String? _ownerOf(WmnDocTypeAccessProfile profile, String? docname) {
    if (docname == null) return null;
    final table = profile.tableName;
    if (table == null || !_safeIdentifier(profile.idField)) return null;

    final hasOwner = _ownerColumnCache.putIfAbsent(profile.name, () {
      final tableSql = quoteSqlIdentifier(table);
      return database.db
          .select('PRAGMA table_info($tableSql);')
          .any((row) => row['name'] == 'owner');
    });
    if (!hasOwner) return null;

    final tableSql = quoteSqlIdentifier(table);
    final idSql = quoteSqlIdentifier(profile.idField);
    final rows = database.db.select(
      'SELECT owner FROM $tableSql WHERE $idSql = ? LIMIT 1;',
      <Object?>[docname],
    );
    return rows.isEmpty ? null : rows.first['owner'] as String?;
  }

  bool _sharedPermission(
    String doctype,
    String docname,
    WmnIdentityContext current,
    String action,
  ) {
    final userId = current.userId ?? current.user;
    final column = switch (action) {
      'read' || 'report' || 'print' || 'email' => 'can_read',
      'write' || 'delete' => 'can_write',
      'share' => 'can_share',
      'submit' || 'cancel' => 'can_submit',
      _ => null,
    };
    if (column == null) return false;
    final rows = database.db.select(
      'SELECT $column AS allowed FROM wmn_doc_shares '
      'WHERE doctype=? AND docname=? AND user_id=? LIMIT 1;',
      <Object?>[doctype, docname, userId],
    );
    return rows.isNotEmpty && (rows.first['allowed'] as int? ?? 0) == 1;
  }

  bool _sameIdentity(String owner, WmnIdentityContext current) =>
      owner == current.user || owner == current.userId;

  String? _actionColumn(String action) => switch (action) {
        'read' => 'can_read',
        'write' => 'can_write',
        'create' => 'can_create',
        'delete' => 'can_delete',
        'submit' => 'can_submit',
        'cancel' => 'can_cancel',
        'amend' => 'can_amend',
        'report' => 'can_report',
        'import' => 'can_import',
        'export' => 'can_export',
        'share' => 'can_share',
        'print' => 'can_print',
        'email' => 'can_email',
        _ => null,
      };

  String? _nullable(Object? value) {
    final normalized = '${value ?? ''}'.trim();
    return normalized.isEmpty ? null : normalized;
  }

  bool _safeIdentifier(String value) =>
      RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value);
}
