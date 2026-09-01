import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/wmn_database.dart';
import '../../framework/meta/meta_service.dart';
import '../storage/wmn_storage_service.dart';
import '../system/wmn_platform_version.dart';
import 'wmn_app_manifest.dart';
import 'wmn_application_registry.dart';

enum WmnApplicationBuildMode { development, test, release }

String wmnApplicationBuildModeToStorage(WmnApplicationBuildMode value) =>
    switch (value) {
      WmnApplicationBuildMode.development => 'DEVELOPMENT',
      WmnApplicationBuildMode.test => 'TEST',
      WmnApplicationBuildMode.release => 'RELEASE',
    };

WmnApplicationBuildMode wmnApplicationBuildModeFromStorage(Object? value) =>
    switch ('${value ?? ''}'.trim().toUpperCase()) {
      'RELEASE' => WmnApplicationBuildMode.release,
      'TEST' => WmnApplicationBuildMode.test,
      _ => WmnApplicationBuildMode.development,
    };

class WmnApplicationBuildProfile {
  const WmnApplicationBuildProfile({
    required this.id,
    required this.appName,
    required this.name,
    required this.mode,
    required this.targets,
    required this.includeAssets,
    required this.strictValidation,
    required this.enabled,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String appName;
  final String name;
  final WmnApplicationBuildMode mode;
  final List<String> targets;
  final bool includeAssets;
  final bool strictValidation;
  final bool enabled;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'app_name': appName,
        'name': name,
        'mode': wmnApplicationBuildModeToStorage(mode),
        'targets': targets,
        'include_assets': includeAssets,
        'strict_validation': strictValidation,
        'metadata': metadata,
      };
}

class WmnApplicationPackageDiagnostic {
  const WmnApplicationPackageDiagnostic({
    required this.errors,
    required this.warnings,
    required this.componentCounts,
  });

  final List<String> errors;
  final List<String> warnings;
  final Map<String, int> componentCounts;

  bool get valid => errors.isEmpty;
}

class WmnApplicationBuildResult {
  const WmnApplicationBuildResult({
    required this.buildId,
    required this.fileName,
    required this.bytes,
    required this.sha256,
    required this.profile,
    required this.manifest,
    required this.componentCounts,
  });

  final String buildId;
  final String fileName;
  final Uint8List bytes;
  final String sha256;
  final WmnApplicationBuildProfile profile;
  final WmnAppManifest manifest;
  final Map<String, int> componentCounts;
}

class WmnApplicationPackageInspection {
  const WmnApplicationPackageInspection({
    required this.manifest,
    required this.profile,
    required this.packageFormatVersion,
    required this.platformVersion,
    required this.schemaVersion,
    required this.componentCounts,
    required this.targets,
    required this.warnings,
  });

  final WmnAppManifest manifest;
  final WmnApplicationBuildProfile profile;
  final int packageFormatVersion;
  final String platformVersion;
  final int schemaVersion;
  final Map<String, int> componentCounts;
  final List<Map<String, Object?>> targets;
  final List<String> warnings;
}

class WmnApplicationInstallResult {
  const WmnApplicationInstallResult({
    required this.manifest,
    required this.componentCounts,
    required this.packageHash,
    required this.updatedExistingApplication,
  });

  final WmnAppManifest manifest;
  final Map<String, int> componentCounts;
  final String packageHash;
  final bool updatedExistingApplication;
}

/// Generates and installs portable WMN application packages.
///
/// The package contains application-owned metadata and managed source/assets,
/// never business records or WMN System Core files. The same standard ZIP archive
/// can be installed by Windows, Android, iOS, Web or Server runtimes as long as
/// its manifest/dependencies are compatible with the target platform.
class WmnApplicationGeneratorService {
  WmnApplicationGeneratorService({
    required this.database,
    required this.applications,
    required this.meta,
    required this.storage,
  });

  static const String packageFormat = 'wmn.application';
  static const int packageFormatVersion = 1;
  static const int maxCompressedBytes = 64 * 1024 * 1024;
  static const int maxExpandedBytes = 256 * 1024 * 1024;
  static const int maxEntries = 20000;
  static const Uuid _uuid = Uuid();

  final WmnDatabase database;
  final WmnApplicationRegistry applications;
  final WmnMetaService meta;
  final WmnStorageService storage;

  void ensureDefaultProfiles(String appName) {
    final app = applications.application(appName);
    if (app == null) throw StateError('Unknown WMN application: $appName');
    final now = DateTime.now().toUtc().toIso8601String();
    final targets = app.manifest.platformTargets.isEmpty
        ? const <String>['all']
        : app.manifest.platformTargets;
    for (final definition in const <(String, String, bool)>[
      ('Development', 'DEVELOPMENT', false),
      ('Test', 'TEST', true),
      ('Release', 'RELEASE', true),
    ]) {
      database.db.execute('''
        INSERT OR IGNORE INTO [tabApplication Build Profile](
          id,app_name,profile_name,build_mode,targets_json,include_assets,
          strict_validation,enabled,metadata_json,created_at,updated_at
        ) VALUES (?,?,?,?,?,1,?,1,'{"system_default":true}',?,?);
      ''', <Object?>[
        '$appName:${definition.$1.toLowerCase()}',
        appName,
        definition.$1,
        definition.$2,
        jsonEncode(targets),
        definition.$3 ? 1 : 0,
        now,
        now,
      ]);
    }
  }

  List<WmnApplicationBuildProfile> profiles(String appName) {
    ensureDefaultProfiles(appName);
    final rows = database.db.select('''
      SELECT * FROM [tabApplication Build Profile]
      WHERE app_name=? AND enabled=1
      ORDER BY CASE build_mode WHEN 'DEVELOPMENT' THEN 1 WHEN 'TEST' THEN 2 ELSE 3 END,
               profile_name COLLATE NOCASE;
    ''', <Object?>[appName]);
    return rows
        .map((row) => _profile(Map<String, Object?>.from(row)))
        .toList(growable: false);
  }

  WmnApplicationBuildProfile saveProfile({
    String? id,
    required String appName,
    required String name,
    required WmnApplicationBuildMode mode,
    required List<String> targets,
    bool includeAssets = true,
    bool strictValidation = true,
    bool enabled = true,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    if (applications.application(appName) == null) {
      throw StateError('Unknown WMN application: $appName');
    }
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) throw StateError('Build profile name is required.');
    final normalizedTargets = _normalizeTargets(targets);
    final entityId = id?.trim().isNotEmpty == true ? id!.trim() : _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO [tabApplication Build Profile](
        id,app_name,profile_name,build_mode,targets_json,include_assets,
        strict_validation,enabled,metadata_json,created_at,updated_at
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET
        app_name=excluded.app_name,profile_name=excluded.profile_name,
        build_mode=excluded.build_mode,targets_json=excluded.targets_json,
        include_assets=excluded.include_assets,
        strict_validation=excluded.strict_validation,enabled=excluded.enabled,
        metadata_json=excluded.metadata_json,updated_at=excluded.updated_at;
    ''', <Object?>[
      entityId,
      appName,
      normalizedName,
      wmnApplicationBuildModeToStorage(mode),
      jsonEncode(normalizedTargets),
      includeAssets ? 1 : 0,
      strictValidation ? 1 : 0,
      enabled ? 1 : 0,
      jsonEncode(metadata),
      now,
      now,
    ]);
    final row = database.db.select(
      'SELECT * FROM [tabApplication Build Profile] WHERE id=? LIMIT 1;',
      <Object?>[entityId],
    );
    return _profile(Map<String, Object?>.from(row.first));
  }

  List<Map<String, Object?>> builds(String appName, {int limit = 50}) {
    final safeLimit = limit.clamp(1, 500);
    return database.db
        .select('''
          SELECT * FROM [tabApplication Build]
          WHERE app_name=? ORDER BY created_at DESC LIMIT ?;
        ''', <Object?>[appName, safeLimit])
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  WmnApplicationPackageDiagnostic validateBuild(
    String appName, {
    WmnApplicationBuildProfile? profile,
  }) {
    final app = applications.application(appName);
    if (app == null) {
      return const WmnApplicationPackageDiagnostic(
        errors: <String>['Application is not registered.'],
        warnings: <String>[],
        componentCounts: <String, int>{},
      );
    }
    final selectedProfile = profile ?? _preferredProfile(appName);
    final errors = <String>[
      ...app.manifest.validateStructure(),
      ...applications
          .diagnose(app.manifest, checkRuntimeTarget: false)
          .errors,
    ];
    final warnings = <String>[
      ...applications
          .diagnose(app.manifest, checkRuntimeTarget: false)
          .warnings,
    ];

    final modules = app.manifest.modules.toSet();
    for (final module in modules) {
      final rows = database.db.select(
        'SELECT app_name FROM wmn_modules WHERE name=? LIMIT 1;',
        <Object?>[module],
      );
      if (rows.isEmpty) {
        errors.add('Application module is not registered: $module');
        continue;
      }
      final owner = '${rows.first['app_name'] ?? ''}'.trim();
      if (owner != appName) {
        errors.add(
          'Application module $module is owned by ${owner.isEmpty ? 'no application' : owner}, not $appName.',
        );
      }
    }

    final ownedDoctypes = _ownedDocTypes(app.manifest);
    final systemDocTypes = _rowsIn(
      'wmn_doctypes',
      'name',
      ownedDoctypes,
      extraWhere: 'is_system=1',
    );
    if (systemDocTypes.isNotEmpty) {
      errors.add('System DocTypes cannot be packaged by an application.');
    }

    final prefix = 'apps/${app.manifest.name}/';
    for (final asset in app.manifest.assets) {
      String key;
      try {
        key = storage.normalizeKey(asset);
      } catch (error) {
        errors.add('$error');
        continue;
      }
      if (!key.startsWith(prefix)) {
        errors.add('Application asset must live below $prefix: $key');
      } else if (!storage.exists(key)) {
        errors.add('Application asset does not exist: $key');
      }
    }

    final ownedFields = _rowsIn(
      'wmn_doctype_fields',
      'doctype',
      ownedDoctypes,
    );
    for (final field in ownedFields) {
      final fieldType = '${field['fieldtype'] ?? ''}'.trim();
      if (!const <String>{'Link', 'Table', 'Table MultiSelect'}.contains(fieldType)) {
        continue;
      }
      final target = '${field['options'] ?? ''}'.trim();
      if (target.isEmpty || ownedDoctypes.contains(target)) continue;
      final targetRows = database.db.select(
        'SELECT module,is_system FROM wmn_doctypes WHERE name=? LIMIT 1;',
        <Object?>[target],
      );
      if (targetRows.isEmpty) {
        final message = 'Field ${field['doctype']}.${field['fieldname']} references unavailable DocType $target.';
        if (selectedProfile.strictValidation) {
          errors.add(message);
        } else {
          warnings.add(message);
        }
        continue;
      }
      if ((targetRows.first['is_system'] as num?)?.toInt() == 1) continue;
      final targetModule = '${targetRows.first['module'] ?? ''}'.trim();
      final ownerRows = database.db.select(
        'SELECT app_name FROM wmn_modules WHERE name=? LIMIT 1;',
        <Object?>[targetModule],
      );
      final owner = ownerRows.isEmpty ? '' : '${ownerRows.first['app_name'] ?? ''}'.trim();
      if (owner.isNotEmpty &&
          owner != appName &&
          !app.manifest.requiredApplications.contains(owner)) {
        final message = 'Field ${field['doctype']}.${field['fieldname']} depends on $target from application $owner, but $owner is not declared in required_applications.';
        if (selectedProfile.strictValidation) {
          errors.add(message);
        } else {
          warnings.add(message);
        }
      }
    }

    final targetSet = _expandTargets(selectedProfile.targets.toSet());
    final manifestTargets = _expandTargets(app.manifest.platformTargets.toSet());
    if (manifestTargets.isNotEmpty &&
        targetSet.intersection(manifestTargets).isEmpty) {
      errors.add(
        'Build profile targets do not intersect application targets: ${selectedProfile.targets.join(', ')}.',
      );
    }

    final components = _collectComponents(app.manifest);
    final nativeScriptReports = (components['reports'] ?? const <Map<String, Object?>>[])
        .where(
          (row) =>
              '${row['report_type'] ?? ''}' == 'Script Report' &&
              '${row['script_source_type'] ?? ''}' == 'NATIVE_HANDLER',
        )
        .map((row) => '${row['report_name'] ?? row['name']}')
        .toList(growable: false);
    final nativeMethods = (components['method_bindings'] ?? const <Map<String, Object?>>[])
        .where((row) => '${row['handler_kind'] ?? ''}' == 'NATIVE')
        .map((row) => '${row['method_name'] ?? ''}')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    final nativeHooks = (components['hook_bindings'] ?? const <Map<String, Object?>>[])
        .where((row) => '${row['target_kind'] ?? ''}' == 'NATIVE')
        .map((row) => '${row['id'] ?? ''}')
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    if (nativeScriptReports.isNotEmpty || nativeMethods.isNotEmpty || nativeHooks.isNotEmpty) {
      final message = 'Application contains compiled native handlers that are not portable metadata: '
          '${<String>[...nativeScriptReports, ...nativeMethods, ...nativeHooks].join(', ')}.';
      if (selectedProfile.strictValidation) {
        errors.add(message);
      } else {
        warnings.add(message);
      }
    }

    final counts = <String, int>{
      for (final entry in components.entries) entry.key: entry.value.length,
    };
    if (ownedDoctypes.isEmpty && app.manifest.modules.isNotEmpty) {
      warnings.add('Application has modules but no application-owned DocTypes.');
    }
    if (selectedProfile.mode == WmnApplicationBuildMode.release &&
        app.manifest.entryRoute == null &&
        app.manifest.routes.isEmpty &&
        app.manifest.routeDefinitions.isEmpty &&
        app.manifest.workspaces.isEmpty) {
      warnings.add('Release package has no declared entry route/workspace.');
    }

    return WmnApplicationPackageDiagnostic(
      errors: List<String>.unmodifiable(errors.toSet()),
      warnings: List<String>.unmodifiable(warnings.toSet()),
      componentCounts: Map<String, int>.unmodifiable(counts),
    );
  }

  WmnApplicationBuildResult generatePackage(
    String appName, {
    String profileName = 'Release',
  }) {
    final app = applications.application(appName);
    if (app == null) throw StateError('Unknown WMN application: $appName');
    if (app.sourceFramework != 'WMN') {
      throw StateError(
        'Only native WMN applications can be generated. Convert imported source packages to READY WMN metadata first.',
      );
    }
    final profile = _profileByName(appName, profileName);
    final diagnostic = validateBuild(appName, profile: profile);
    if (diagnostic.errors.isNotEmpty) {
      throw StateError(diagnostic.errors.join(' '));
    }

    final buildId = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    _recordBuildStart(buildId, app.manifest, profile, now);
    try {
      final components = _collectComponents(app.manifest);
      final archiveEntries = <String, Uint8List>{};
      final sourceIndex = _collectManagedSources(components, archiveEntries);
      final assetIndex = profile.includeAssets
          ? _collectAssets(app.manifest, archiveEntries)
          : const <Map<String, Object?>>[];

      for (final entry in components.entries) {
        archiveEntries['metadata/${entry.key}.json'] = _jsonBytes(entry.value);
      }
      archiveEntries['metadata/sources.json'] = _jsonBytes(sourceIndex);
      archiveEntries['assets/index.json'] = _jsonBytes(assetIndex);
      archiveEntries['targets/index.json'] = _jsonBytes(
        _targetDescriptors(app.manifest, profile),
      );

      final componentCounts = <String, int>{
        for (final entry in components.entries) entry.key: entry.value.length,
        'managed_sources': sourceIndex.length,
        'assets': assetIndex.length,
      };
      final envelope = <String, Object?>{
        'package_format': packageFormat,
        'package_format_version': packageFormatVersion,
        'generated_by': 'WMN Application Platform',
        'platform_version': WmnPlatformVersion.version,
        'schema_version': WmnPlatformVersion.schemaVersion,
        'build_id': buildId,
        'built_at': now,
        'profile': profile.toJson(),
        'manifest': app.manifest.toJson(),
        'component_counts': componentCounts,
        'warnings': diagnostic.warnings,
      };
      archiveEntries['wmn_app.json'] = _jsonBytes(envelope);
      archiveEntries['checksums.sha256'] = Uint8List.fromList(
        utf8.encode(_checksumText(archiveEntries)),
      );

      final archive = Archive();
      final paths = archiveEntries.keys.toList()..sort();
      for (final path in paths) {
        final bytes = archiveEntries[path]!;
        archive.addFile(ArchiveFile(path, bytes.length, bytes));
      }
      final encoded = ZipEncoder().encode(archive);
      if (encoded == null) throw StateError('WMN application ZIP encoding failed.');
      final bytes = Uint8List.fromList(encoded);
      if (bytes.length > maxCompressedBytes) {
        throw StateError(
          'Generated application package exceeds ${maxCompressedBytes ~/ (1024 * 1024)} MB.',
        );
      }
      final hash = sha256.convert(bytes).toString();
      _recordBuildSuccess(
        buildId,
        hash: hash,
        size: bytes.length,
        manifest: app.manifest,
        componentCounts: componentCounts,
      );
      return WmnApplicationBuildResult(
        buildId: buildId,
        fileName: '${app.manifest.name}-${app.manifest.version}.zip',
        bytes: bytes,
        sha256: hash,
        profile: profile,
        manifest: app.manifest,
        componentCounts: Map<String, int>.unmodifiable(componentCounts),
      );
    } catch (error) {
      _recordBuildFailure(buildId, '$error');
      rethrow;
    }
  }

  WmnApplicationPackageInspection inspectPackage(List<int> bytes) {
    final decoded = _decodePackage(bytes);
    return decoded.inspection;
  }

  WmnApplicationInstallResult installPackage(
    List<int> bytes, {
    bool allowUpdate = true,
    bool allowDowngrade = false,
  }) {
    final decoded = _decodePackage(bytes);
    if (decoded.inspection.schemaVersion > WmnPlatformVersion.schemaVersion) {
      throw StateError(
        'Application package requires WMN schema ${decoded.inspection.schemaVersion}; '
        'current schema is ${WmnPlatformVersion.schemaVersion}.',
      );
    }
    final manifest = decoded.inspection.manifest;
    final existing = applications.application(manifest.name);
    if (existing != null && !allowUpdate) {
      throw StateError('Application is already installed: ${manifest.name}');
    }
    if (existing != null &&
        !allowDowngrade &&
        _compareSemanticVersions(manifest.version, existing.manifest.version) < 0) {
      throw StateError(
        'Application package ${manifest.name} ${manifest.version} is older than '
        'the installed version ${existing.manifest.version}.',
      );
    }
    if (existing != null && existing.sourceFramework != 'WMN') {
      throw StateError(
        'Cannot install a native WMN package over an imported ${existing.sourceFramework} source package.',
      );
    }

    final diagnostic = applications.diagnose(manifest);
    if (!diagnostic.compatible) {
      throw StateError(diagnostic.errors.join(' '));
    }
    _validatePackageOwnership(decoded);

    final sourceRemap = <String, String>{};
    for (final source in decoded.sources) {
      final original = '${source['storage_key'] ?? ''}'.trim();
      final archivePath = '${source['archive_path'] ?? ''}'.trim();
      final payload = decoded.files[archivePath];
      if (original.isEmpty || payload == null) {
        throw StateError('Invalid managed source entry in package.');
      }
      final digest = sha256.convert(payload).toString();
      final suffix = _safeFileName(original.split('/').last);
      final target = storage.normalizeKey(
        'apps/${manifest.name}/sources/$digest/$suffix',
      );
      storage.writeBytes(target, payload);
      sourceRemap[original] = target;
    }

    for (final asset in decoded.assets) {
      final key = storage.normalizeKey('${asset['storage_key'] ?? ''}');
      final requiredPrefix = 'apps/${manifest.name}/';
      if (!key.startsWith(requiredPrefix)) {
        throw StateError('Package asset escapes application storage root: $key');
      }
      final archivePath = '${asset['archive_path'] ?? ''}'.trim();
      final payload = decoded.files[archivePath];
      if (payload == null) throw StateError('Missing package asset payload: $archivePath');
      storage.writeBytes(key, payload);
    }

    database.db.execute('BEGIN IMMEDIATE;');
    try {
      applications.register(manifest);
      _installGeneric('wmn_modules', decoded.components['modules']);
      _installDocTypes(decoded.components, manifest);
      _installGeneric('roles', decoded.components['roles']);
      _installGeneric('permissions', decoded.components['permissions']);
      _installGeneric('role_permissions', decoded.components['role_permissions']);
      _installGeneric('wmn_doctype_permissions', decoded.components['doctype_permissions']);
      _installGeneric('wmn_list_view_settings', decoded.components['list_views']);
      _installGeneric('custom_fields', decoded.components['custom_fields']);
      _installGeneric('property_overrides', decoded.components['property_overrides']);
      _installGeneric('numbering_series', decoded.components['numbering_series']);
      _installGeneric('tabWorkspace', decoded.components['workspaces']);
      _installGeneric('tabWorkspaceItem', decoded.components['workspace_items']);
      _installGeneric('tabPage', decoded.components['pages']);
      _installReports(decoded.components, sourceRemap);
      _installGeneric('tabReport Filter', decoded.components['report_filters']);
      _installGeneric('tabReport Column', decoded.components['report_columns']);
      _installGeneric('print_formats', decoded.components['print_formats']);
      _installScripts(decoded.components, sourceRemap);
      _installGeneric('wmn_workflows', decoded.components['workflows']);
      _installGeneric('wmn_workflow_states', decoded.components['workflow_states']);
      _installGeneric('wmn_workflow_transitions', decoded.components['workflow_transitions']);
      _installGeneric('wmn_method_bindings', decoded.components['method_bindings']);
      _installGeneric('wmn_hook_bindings', decoded.components['hook_bindings']);
      _installGeneric('wmn_number_cards', decoded.components['number_cards']);
      _installGeneric('wmn_dashboard_charts', decoded.components['dashboard_charts']);
      database.db.execute('COMMIT;');
    } catch (_) {
      database.db.execute('ROLLBACK;');
      rethrow;
    }

    ensureDefaultProfiles(manifest.name);
    final packageHash = sha256.convert(bytes).toString();
    _recordImportedPackage(manifest, decoded.inspection.profile, packageHash, bytes.length, decoded.inspection.componentCounts);
    return WmnApplicationInstallResult(
      manifest: manifest,
      componentCounts: decoded.inspection.componentCounts,
      packageHash: packageHash,
      updatedExistingApplication: existing != null,
    );
  }

  Map<String, List<Map<String, Object?>>> _collectComponents(
    WmnAppManifest manifest,
  ) {
    final doctypes = _ownedDocTypes(manifest);
    final contributionDoctypes = <String>{
      ...doctypes,
      ...manifest.metadataContributions.map((value) => value.trim()).where((value) => value.isNotEmpty),
    };
    final workspaceRows = _rowsWhere(
      'tabWorkspace',
      'app_name=?',
      <Object?>[manifest.name],
    );
    final workspaceNames = workspaceRows.map((row) => '${row['name']}').toSet();
    final pageRows = _rowsWhere('tabPage', 'app_name=?', <Object?>[manifest.name]);
    final reportRows = _rowsIn('tabReport', 'module', manifest.modules.toSet());
    final reportIds = reportRows.map((row) => '${row['name']}').toSet();
    final reportNames = reportRows.map((row) => '${row['report_name']}').toSet();
    final workflowRows = _rowsIn('wmn_workflows', 'doctype', contributionDoctypes);
    final workflowIds = workflowRows.map((row) => '${row['id']}').toSet();

    final doctypePermissionRows = _rowsIn('wmn_doctype_permissions', 'doctype', contributionDoctypes);
    final workflowRoleNames = <String>{};
    for (final row in doctypePermissionRows) {
      final role = '${row['role'] ?? ''}'.trim();
      if (role.isNotEmpty) workflowRoleNames.add(role);
    }
    for (final row in _rowsIn('wmn_workflow_states', 'workflow_id', workflowIds)) {
      final role = '${row['allow_edit_role'] ?? ''}'.trim();
      if (role.isNotEmpty) workflowRoleNames.add(role);
    }
    final transitionRows = _rowsIn('wmn_workflow_transitions', 'workflow_id', workflowIds);
    for (final row in transitionRows) {
      final role = '${row['allowed_role'] ?? ''}'.trim();
      if (role.isNotEmpty) workflowRoleNames.add(role);
    }
    final roleNames = <String>{...manifest.requiredRoles, ...workflowRoleNames};
    final roleRows = roleNames.isEmpty
        ? const <Map<String, Object?>>[]
        : database.db
            .select(
              'SELECT * FROM roles WHERE is_system=0 AND (id IN (${_marks(roleNames.length)}) OR code IN (${_marks(roleNames.length)}) OR name IN (${_marks(roleNames.length)}));',
              <Object?>[...roleNames, ...roleNames, ...roleNames],
            )
            .map((row) => Map<String, Object?>.from(row))
            .toList(growable: false);
    final roleIds = roleRows.map((row) => '${row['id']}').toSet();

    final permissionRows = <Map<String, Object?>>[];
    if (manifest.permissions.isNotEmpty) {
      permissionRows.addAll(_rowsIn('permissions', 'code', manifest.permissions.toSet()));
    }
    if (manifest.modules.isNotEmpty) {
      for (final row in _rowsIn('permissions', 'module', manifest.modules.toSet())) {
        if (!permissionRows.any((existing) => existing['id'] == row['id'])) {
          permissionRows.add(row);
        }
      }
    }
    final permissionIds = permissionRows.map((row) => '${row['id']}').toSet();
    final rolePermissionRows = roleIds.isEmpty || permissionIds.isEmpty
        ? const <Map<String, Object?>>[]
        : database.db
            .select(
              'SELECT * FROM role_permissions WHERE role_id IN (${_marks(roleIds.length)}) AND permission_id IN (${_marks(permissionIds.length)});',
              <Object?>[...roleIds, ...permissionIds],
            )
            .map((row) => Map<String, Object?>.from(row))
            .toList(growable: false);

    final clientScriptRows = _rowsIn('client_scripts', 'document_type', contributionDoctypes);
    final methodRows = _rowsWhere('wmn_method_bindings', 'source_app=?', <Object?>[manifest.name]);
    final hookRows = _rowsWhere('wmn_hook_bindings', 'source_app=?', <Object?>[manifest.name]);
    final serverScriptRows = _collectServerScripts(contributionDoctypes, methodRows, hookRows);

    return <String, List<Map<String, Object?>>>{
      'modules': _rowsWhere('wmn_modules', 'app_name=?', <Object?>[manifest.name]),
      'doctypes': _rowsIn('wmn_doctypes', 'name', doctypes),
      'doctype_fields': _rowsIn('wmn_doctype_fields', 'doctype', doctypes),
      'doctype_permissions': doctypePermissionRows,
      'list_views': _rowsIn('wmn_list_view_settings', 'doctype', doctypes),
      'custom_fields': _rowsIn('custom_fields', 'document_type', contributionDoctypes),
      'property_overrides': _rowsIn('property_overrides', 'document_type', contributionDoctypes),
      'numbering_series': _rowsIn('numbering_series', 'document_type', doctypes)
          .map((row) => <String, Object?>{...row, 'next_value': 1})
          .toList(growable: false),
      'roles': roleRows,
      'permissions': permissionRows,
      'role_permissions': rolePermissionRows,
      'workspaces': workspaceRows,
      'workspace_items': _rowsIn('tabWorkspaceItem', 'parent', workspaceNames),
      'pages': pageRows,
      'reports': reportRows,
      'report_filters': _rowsIn('tabReport Filter', 'parent', reportIds),
      'report_columns': _rowsIn('tabReport Column', 'parent', reportIds),
      'print_formats': _collectPrintFormats(manifest, contributionDoctypes, reportNames),
      'client_scripts': clientScriptRows,
      'server_scripts': serverScriptRows,
      'workflows': workflowRows,
      'workflow_states': _rowsIn('wmn_workflow_states', 'workflow_id', workflowIds),
      'workflow_transitions': transitionRows,
      'method_bindings': methodRows,
      'hook_bindings': hookRows,
      'number_cards': _rowsWhere('wmn_number_cards', 'app_name=?', <Object?>[manifest.name]),
      'dashboard_charts': _rowsWhere('wmn_dashboard_charts', 'app_name=?', <Object?>[manifest.name]),
    };
  }

  Set<String> _ownedDocTypes(WmnAppManifest manifest) {
    if (manifest.modules.isEmpty) return <String>{};
    return _rowsIn('wmn_doctypes', 'module', manifest.modules.toSet(), extraWhere: 'is_system=0')
        .map((row) => '${row['name']}')
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  List<Map<String, Object?>> _collectPrintFormats(
    WmnAppManifest manifest,
    Set<String> doctypes,
    Set<String> reportNames,
  ) {
    if (!_tableExists('print_formats')) return const <Map<String, Object?>>[];
    final result = <Map<String, Object?>>[];
    final all = database.db.select('SELECT * FROM print_formats ORDER BY code COLLATE NOCASE;');
    for (final raw in all) {
      final row = Map<String, Object?>.from(raw);
      final documentType = '${row['document_type'] ?? ''}'.trim();
      final reportName = '${row['report_name'] ?? ''}'.trim();
      final metadata = _jsonMap(row['metadata_json']);
      if (doctypes.contains(documentType) ||
          reportNames.contains(reportName) ||
          '${metadata['app_name'] ?? ''}'.trim() == manifest.name) {
        result.add(row);
      }
    }
    return result;
  }

  List<Map<String, Object?>> _collectServerScripts(
    Set<String> doctypes,
    List<Map<String, Object?>> methods,
    List<Map<String, Object?>> hooks,
  ) {
    if (!_tableExists('server_scripts')) return const <Map<String, Object?>>[];
    final candidates = <String>{};
    for (final row in methods) {
      if ('${row['handler_kind'] ?? ''}' == 'SERVER_SCRIPT') {
        final value = '${row['target'] ?? ''}'.trim();
        if (value.isNotEmpty) candidates.add(value);
      }
    }
    for (final row in hooks) {
      if ('${row['target_kind'] ?? ''}' == 'SERVER_SCRIPT') {
        final value = '${row['target'] ?? ''}'.trim();
        if (value.isNotEmpty) candidates.add(value);
      }
    }
    final rows = database.db.select('SELECT * FROM server_scripts ORDER BY name COLLATE NOCASE;');
    return rows.map((row) => Map<String, Object?>.from(row)).where((row) {
      final documentType = '${row['document_type'] ?? ''}'.trim();
      final id = '${row['id'] ?? ''}'.trim();
      final name = '${row['name'] ?? ''}'.trim();
      return doctypes.contains(documentType) || candidates.contains(id) || candidates.contains(name);
    }).toList(growable: false);
  }

  List<Map<String, Object?>> _collectManagedSources(
    Map<String, List<Map<String, Object?>>> components,
    Map<String, Uint8List> archiveEntries,
  ) {
    final paths = <String>{};
    for (final row in components['client_scripts'] ?? const <Map<String, Object?>>[]) {
      final value = '${row['source_storage_path'] ?? ''}'.trim();
      if (value.isNotEmpty) paths.add(value);
    }
    for (final row in components['server_scripts'] ?? const <Map<String, Object?>>[]) {
      final value = '${row['source_storage_path'] ?? ''}'.trim();
      if (value.isNotEmpty) paths.add(value);
    }
    for (final row in components['reports'] ?? const <Map<String, Object?>>[]) {
      for (final column in const <String>['query_source_path', 'script_source_path']) {
        final value = '${row[column] ?? ''}'.trim();
        if (value.isNotEmpty) paths.add(value);
      }
    }

    final result = <Map<String, Object?>>[];
    for (final original in paths.toList()..sort()) {
      final normalized = storage.normalizeKey(original);
      if (!storage.exists(normalized)) {
        throw StateError('Managed application source does not exist: $normalized');
      }
      final bytes = storage.readBytes(normalized);
      final hash = sha256.convert(bytes).toString();
      final archivePath = 'sources/$hash-${_safeFileName(normalized.split('/').last)}';
      archiveEntries[archivePath] = bytes;
      result.add(<String, Object?>{
        'storage_key': normalized,
        'archive_path': archivePath,
        'sha256': hash,
        'size': bytes.length,
      });
    }
    return result;
  }

  List<Map<String, Object?>> _collectAssets(
    WmnAppManifest manifest,
    Map<String, Uint8List> archiveEntries,
  ) {
    final result = <Map<String, Object?>>[];
    for (final raw in manifest.assets) {
      final key = storage.normalizeKey(raw);
      final requiredPrefix = 'apps/${manifest.name}/';
      if (!key.startsWith(requiredPrefix)) {
        throw StateError('Application asset must live below $requiredPrefix: $key');
      }
      if (!storage.exists(key)) throw StateError('Application asset not found: $key');
      final bytes = storage.readBytes(key);
      final hash = sha256.convert(bytes).toString();
      final relative = key.substring(requiredPrefix.length);
      final archivePath = 'assets/files/${_safeArchivePath(relative)}';
      archiveEntries[archivePath] = bytes;
      result.add(<String, Object?>{
        'storage_key': key,
        'archive_path': archivePath,
        'sha256': hash,
        'size': bytes.length,
      });
    }
    return result;
  }

  List<Map<String, Object?>> _targetDescriptors(
    WmnAppManifest manifest,
    WmnApplicationBuildProfile profile,
  ) {
    final profileTargets = _expandTargets(profile.targets.toSet());
    final manifestTargets = _expandTargets(manifest.platformTargets.toSet());
    final targets = (manifestTargets.isEmpty
            ? profileTargets
            : profileTargets.intersection(manifestTargets))
        .toList()
      ..sort();
    final declaredCapabilities = <String>{
      ...manifest.requiredCapabilities,
      ...manifest.optionalCapabilities,
    };
    return targets.map((target) {
      return <String, Object?>{
        'target': target,
        'application_id': manifest.name,
        'display_name': manifest.title,
        'version': manifest.version,
        'entry_route': manifest.entryRoute ??
            (manifest.routeDefinitions.isNotEmpty
                ? manifest.routeDefinitions.first.path
                : manifest.routes.isNotEmpty
                    ? manifest.routes.first
                    : null),
        'package_runtime': 'WMN',
        'host_requirements': _hostRequirements(target, declaredCapabilities),
      };
    }).toList(growable: false);
  }


  Set<String> _expandTargets(Set<String> rawTargets) {
    const allTargets = <String>{
      'windows',
      'android',
      'ios',
      'web',
      'server',
      'linux',
      'macos',
    };
    if (rawTargets.isEmpty || rawTargets.contains('all')) {
      return <String>{...allTargets};
    }
    final result = <String>{};
    for (final raw in rawTargets) {
      final target = raw.trim().toLowerCase();
      if (target == 'mobile') {
        result.addAll(const <String>{'android', 'ios'});
      } else if (target.isNotEmpty) {
        result.add(target);
      }
    }
    return result;
  }

  Map<String, Object?> _hostRequirements(
    String rawTarget,
    Set<String> capabilities,
  ) {
    final target = rawTarget.trim().toLowerCase();
    bool hasAny(Set<String> ids) => ids.any(capabilities.contains);
    final camera = hasAny(<String>{
      'camera',
      'scanner',
      'mobile.camera',
      'mobile.scanner',
      'web.camera',
      'windows.camera',
      'windows.scanner',
    });
    final clipboard = hasAny(<String>{
      'clipboard',
      'web.clipboard',
      'windows.clipboard',
    });
    final share = hasAny(<String>{
      'share',
      'mobile.share',
      'mobile.whatsapp.share',
      'web.share',
      'windows.share',
    });

    switch (target) {
      case 'android':
      case 'mobile':
        return <String, Object?>{
          'android_permissions': <String>[
            if (camera) 'android.permission.CAMERA',
          ],
          'android_features': <Map<String, Object?>>[
            if (camera)
              <String, Object?>{
                'name': 'android.hardware.camera',
                'required': false,
              },
          ],
          'notes': <String>[
            if (camera) 'Camera permission is required only because the application declares camera/scanner capability.',
          ],
        };
      case 'ios':
        return <String, Object?>{
          'info_plist': <String, String>{
            if (camera)
              'NSCameraUsageDescription':
                  'Camera access is required by an enabled application capability.',
          },
        };
      case 'web':
        return <String, Object?>{
          'secure_context_features': <String>[
            if (camera) 'camera',
            if (clipboard) 'clipboard',
            if (share) 'share',
          ],
          'browser_policy':
              'Runtime browser permissions and user gestures remain authoritative.',
        };
      case 'windows':
        return const <String, Object?>{
          'manifest_capabilities': <String>[],
          'notes': <String>[
            'Current WMN Windows adapters require no additional generated host capability declarations.',
          ],
        };
      default:
        return const <String, Object?>{};
    }
  }

  _DecodedPackage _decodePackage(List<int> rawBytes) {
    if (rawBytes.isEmpty) throw StateError('Empty WMN application package.');
    if (rawBytes.length > maxCompressedBytes) {
      throw StateError('WMN application package exceeds the compressed safety limit.');
    }
    final archive = ZipDecoder().decodeBytes(rawBytes, verify: false);
    if (archive.length > maxEntries) {
      throw StateError('WMN application package has too many entries.');
    }
    final files = <String, Uint8List>{};
    var expanded = 0;
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final path = _safeArchivePath(entry.name);
      if (files.containsKey(path)) {
        throw StateError('WMN application package contains duplicate entry: $path');
      }
      expanded += entry.size;
      if (expanded > maxExpandedBytes) {
        throw StateError('WMN application package exceeds the expanded safety limit.');
      }
      final content = entry.content;
      files[path] = content is Uint8List
          ? Uint8List.fromList(content)
          : Uint8List.fromList(List<int>.from(content as List));
    }
    final checksumBytes = files['checksums.sha256'];
    if (checksumBytes == null) throw StateError('WMN package checksum manifest is missing.');
    _verifyChecksums(files, utf8.decode(checksumBytes));

    final envelopeBytes = files['wmn_app.json'];
    if (envelopeBytes == null) throw StateError('WMN package manifest is missing.');
    final envelope = _decodeMap(envelopeBytes, 'wmn_app.json');
    if ('${envelope['package_format'] ?? ''}' != packageFormat) {
      throw StateError('Unsupported application package format.');
    }
    final formatVersion = (envelope['package_format_version'] as num?)?.toInt() ?? 0;
    if (formatVersion != packageFormatVersion) {
      throw StateError(
        'Unsupported WMN application package format version: $formatVersion.',
      );
    }
    final manifestRaw = envelope['manifest'];
    if (manifestRaw is! Map) throw StateError('WMN package contains no application manifest.');
    final manifest = WmnAppManifest.fromJson(Map<String, Object?>.from(manifestRaw));
    final structureIssues = manifest.validateStructure();
    if (structureIssues.isNotEmpty) throw StateError(structureIssues.join(' '));

    final profileRaw = envelope['profile'];
    if (profileRaw is! Map) throw StateError('WMN package build profile is missing.');
    final profileMap = Map<String, Object?>.from(profileRaw);
    final profile = WmnApplicationBuildProfile(
      id: '${profileMap['id'] ?? 'package'}',
      appName: manifest.name,
      name: '${profileMap['name'] ?? 'Package'}',
      mode: wmnApplicationBuildModeFromStorage(profileMap['mode']),
      targets: _strings(profileMap['targets']),
      includeAssets: profileMap['include_assets'] != false,
      strictValidation: profileMap['strict_validation'] != false,
      enabled: true,
      metadata: profileMap['metadata'] is Map
          ? Map<String, Object?>.from(profileMap['metadata'] as Map)
          : const <String, Object?>{},
    );

    final components = <String, List<Map<String, Object?>>>{};
    for (final name in _componentNames) {
      final bytes = files['metadata/$name.json'];
      components[name] = bytes == null ? <Map<String, Object?>>[] : _decodeListOfMaps(bytes, 'metadata/$name.json');
    }
    final sources = files['metadata/sources.json'] == null
        ? <Map<String, Object?>>[]
        : _decodeListOfMaps(files['metadata/sources.json']!, 'metadata/sources.json');
    final assets = files['assets/index.json'] == null
        ? <Map<String, Object?>>[]
        : _decodeListOfMaps(files['assets/index.json']!, 'assets/index.json');
    final targets = files['targets/index.json'] == null
        ? <Map<String, Object?>>[]
        : _decodeListOfMaps(files['targets/index.json']!, 'targets/index.json');
    final counts = envelope['component_counts'] is Map
        ? <String, int>{
            for (final entry in (envelope['component_counts'] as Map).entries)
              '${entry.key}': (entry.value as num?)?.toInt() ?? 0,
          }
        : <String, int>{for (final entry in components.entries) entry.key: entry.value.length};
    final warnings = _strings(envelope['warnings']);
    final inspection = WmnApplicationPackageInspection(
      manifest: manifest,
      profile: profile,
      packageFormatVersion: formatVersion,
      platformVersion: '${envelope['platform_version'] ?? ''}',
      schemaVersion: (envelope['schema_version'] as num?)?.toInt() ?? 0,
      componentCounts: Map<String, int>.unmodifiable(counts),
      targets: List<Map<String, Object?>>.unmodifiable(targets),
      warnings: List<String>.unmodifiable(warnings),
    );
    return _DecodedPackage(
      inspection: inspection,
      files: files,
      components: components,
      sources: sources,
      assets: assets,
    );
  }

  void _validatePackageOwnership(_DecodedPackage package) {
    final manifest = package.inspection.manifest;
    final modules = manifest.modules.toSet();
    for (final row in package.components['modules'] ?? const <Map<String, Object?>>[]) {
      if ('${row['app_name'] ?? ''}' != manifest.name) {
        throw StateError('Package contains a module owned by another application.');
      }
      if (!modules.contains('${row['name'] ?? ''}')) {
        throw StateError('Package module is not declared in the App Manifest: ${row['name']}');
      }
    }
    for (final row in package.components['doctypes'] ?? const <Map<String, Object?>>[]) {
      if ((row['is_system'] as num?)?.toInt() == 1) {
        throw StateError('Application package cannot install System DocTypes.');
      }
      if (!modules.contains('${row['module'] ?? ''}')) {
        throw StateError('Packaged DocType is outside the application modules: ${row['name']}');
      }
    }
    for (final component in const <String>['workspaces', 'pages', 'number_cards', 'dashboard_charts']) {
      for (final row in package.components[component] ?? const <Map<String, Object?>>[]) {
        if ('${row['app_name'] ?? ''}' != manifest.name) {
          throw StateError('Package component $component has invalid application ownership.');
        }
      }
    }
    for (final asset in package.assets) {
      final key = storage.normalizeKey('${asset['storage_key'] ?? ''}');
      if (!key.startsWith('apps/${manifest.name}/')) {
        throw StateError('Package asset escapes application storage root: $key');
      }
    }
  }

  void _installDocTypes(
    Map<String, List<Map<String, Object?>>> components,
    WmnAppManifest manifest,
  ) {
    for (final row in components['doctypes'] ?? const <Map<String, Object?>>[]) {
      meta.saveDocType(
        name: '${row['name']}',
        module: '${row['module'] ?? 'Custom'}',
        titleField: _nullable(row['title_field']),
        autoname: _nullable(row['autoname']),
        isSingle: _bool(row['is_single']),
        isChild: _bool(row['is_child']),
        isSubmittable: _bool(row['is_submittable']),
        trackChanges: _bool(row['track_changes'], fallback: true),
        allowCreate: _bool(row['allow_create'], fallback: true),
        allowEdit: _bool(row['allow_edit'], fallback: true),
        allowDelete: _bool(row['allow_delete'], fallback: true),
        allowImport: _bool(row['allow_import'], fallback: true),
        allowExport: _bool(row['allow_export'], fallback: true),
        genericWrite: _bool(row['generic_write'], fallback: true),
        enabled: _bool(row['enabled'], fallback: true),
        metadata: <String, Object?>{
          ..._jsonMap(row['metadata_json']),
          'app_name': manifest.name,
          'packaged_by': 'WMN Application Generator',
        },
      );
    }
    for (final row in components['doctype_fields'] ?? const <Map<String, Object?>>[]) {
      meta.saveField(
        id: _nullable(row['id']),
        doctype: '${row['doctype']}',
        fieldName: '${row['fieldname']}',
        label: '${row['label'] ?? row['fieldname']}',
        fieldType: '${row['fieldtype'] ?? 'Data'}',
        options: _nullable(row['options']),
        index: (row['idx'] as num?)?.toInt() ?? 0,
        required: _bool(row['reqd']),
        readOnly: _bool(row['read_only']),
        hidden: _bool(row['hidden']),
        inListView: _bool(row['in_list_view']),
        inStandardFilter: _bool(row['in_standard_filter']),
        searchable: _bool(row['searchable']),
        allowOnSubmit: _bool(row['allow_on_submit']),
        defaultValue: _decodeJsonValue(row['default_json']),
        dependsOn: _nullable(row['depends_on']),
        mandatoryDependsOn: _nullable(row['mandatory_depends_on']),
        readOnlyDependsOn: _nullable(row['read_only_depends_on']),
        fetchFrom: _nullable(row['fetch_from']),
        precision: (row['precision'] as num?)?.toInt(),
        length: (row['length'] as num?)?.toInt(),
        validateReferences: true,
        metadata: _jsonMap(row['metadata_json']),
      );
    }
  }

  void _installReports(
    Map<String, List<Map<String, Object?>>> components,
    Map<String, String> sourceRemap,
  ) {
    final rows = components['reports'];
    if (rows == null) return;
    final remapped = rows.map((row) {
      final copy = Map<String, Object?>.from(row);
      for (final column in const <String>['query_source_path', 'script_source_path']) {
        final original = '${copy[column] ?? ''}'.trim();
        if (original.isNotEmpty && sourceRemap.containsKey(original)) {
          copy[column] = sourceRemap[original];
        }
      }
      return copy;
    }).toList(growable: false);
    _installGeneric('tabReport', remapped);
  }

  void _installScripts(
    Map<String, List<Map<String, Object?>>> components,
    Map<String, String> sourceRemap,
  ) {
    for (final component in const <String>['client_scripts', 'server_scripts']) {
      final rows = components[component];
      if (rows == null) continue;
      final remapped = rows.map((row) {
        final copy = Map<String, Object?>.from(row);
        final original = '${copy['source_storage_path'] ?? ''}'.trim();
        if (original.isNotEmpty && sourceRemap.containsKey(original)) {
          copy['source_storage_path'] = sourceRemap[original];
        }
        return copy;
      }).toList(growable: false);
      _installGeneric(component, remapped);
    }
  }

  void _installGeneric(String table, List<Map<String, Object?>>? rows) {
    if (rows == null || rows.isEmpty) return;
    if (!_tableExists(table)) throw StateError('Required package table is unavailable: $table');
    final tableColumns = database.db
        .select('PRAGMA table_info(${_quote(table)});')
        .map((row) => '${row['name']}')
        .toSet();
    final primaryKeys = database.db
        .select('PRAGMA table_info(${_quote(table)});')
        .where((row) => ((row['pk'] as num?)?.toInt() ?? 0) > 0)
        .toList()
      ..sort((a, b) => ((a['pk'] as num?)?.toInt() ?? 0).compareTo((b['pk'] as num?)?.toInt() ?? 0));
    final pkNames = primaryKeys.map((row) => '${row['name']}').toList(growable: false);
    if (pkNames.isEmpty) throw StateError('Package table has no primary key: $table');

    for (final raw in rows) {
      final row = <String, Object?>{
        for (final entry in raw.entries)
          if (tableColumns.contains(entry.key)) entry.key: entry.value,
      };
      if (row.isEmpty || pkNames.any((pk) => !row.containsKey(pk))) {
        throw StateError('Package row is missing the primary key for $table.');
      }
      final columns = row.keys.toList(growable: false);
      final updates = columns.where((column) => !pkNames.contains(column)).toList(growable: false);
      final conflict = pkNames.map(_quote).join(',');
      final updateSql = updates.isEmpty
          ? 'DO NOTHING'
          : 'DO UPDATE SET ${updates.map((column) => '${_quote(column)}=excluded.${_quote(column)}').join(',')}';
      database.db.execute(
        'INSERT INTO ${_quote(table)}(${columns.map(_quote).join(',')}) '
        'VALUES (${_marks(columns.length)}) ON CONFLICT($conflict) $updateSql;',
        <Object?>[for (final column in columns) row[column]],
      );
    }
  }

  void _recordBuildStart(
    String buildId,
    WmnAppManifest manifest,
    WmnApplicationBuildProfile profile,
    String now,
  ) {
    database.db.execute('''
      INSERT INTO [tabApplication Build](
        id,app_name,app_version,profile_name,build_mode,targets_json,
        package_format,package_format_version,status,manifest_json,summary_json,created_at
      ) VALUES (?,?,?,?,?,?,'WMNAPP',?,'GENERATING',?,'{}',?);
    ''', <Object?>[
      buildId,
      manifest.name,
      manifest.version,
      profile.name,
      wmnApplicationBuildModeToStorage(profile.mode),
      jsonEncode(profile.targets),
      packageFormatVersion,
      manifest.encode(),
      now,
    ]);
  }

  void _recordBuildSuccess(
    String buildId, {
    required String hash,
    required int size,
    required WmnAppManifest manifest,
    required Map<String, int> componentCounts,
  }) {
    database.db.execute('''
      UPDATE [tabApplication Build]
      SET status='READY',package_hash=?,package_size=?,manifest_json=?,summary_json=?,
          completed_at=? WHERE id=?;
    ''', <Object?>[
      hash,
      size,
      manifest.encode(),
      jsonEncode(<String, Object?>{'component_counts': componentCounts}),
      DateTime.now().toUtc().toIso8601String(),
      buildId,
    ]);
  }

  void _recordBuildFailure(String buildId, String error) {
    database.db.execute('''
      UPDATE [tabApplication Build]
      SET status='FAILED',error_text=?,completed_at=? WHERE id=?;
    ''', <Object?>[
      error,
      DateTime.now().toUtc().toIso8601String(),
      buildId,
    ]);
  }

  void _recordImportedPackage(
    WmnAppManifest manifest,
    WmnApplicationBuildProfile profile,
    String packageHash,
    int size,
    Map<String, int> componentCounts,
  ) {
    database.db.execute('''
      INSERT INTO [tabApplication Build](
        id,app_name,app_version,profile_name,build_mode,targets_json,
        package_format,package_format_version,status,package_hash,package_size,
        manifest_json,summary_json,created_at,completed_at
      ) VALUES (?,?,?,?,?,?,'WMNAPP',?,'IMPORTED',?,?,?,?,?,?);
    ''', <Object?>[
      _uuid.v4(),
      manifest.name,
      manifest.version,
      profile.name,
      wmnApplicationBuildModeToStorage(profile.mode),
      jsonEncode(profile.targets),
      packageFormatVersion,
      packageHash,
      size,
      manifest.encode(),
      jsonEncode(<String, Object?>{'component_counts': componentCounts}),
      DateTime.now().toUtc().toIso8601String(),
      DateTime.now().toUtc().toIso8601String(),
    ]);
  }

  WmnApplicationBuildProfile _preferredProfile(String appName) {
    final all = profiles(appName);
    return all.firstWhere(
      (profile) => profile.mode == WmnApplicationBuildMode.release,
      orElse: () => all.first,
    );
  }

  WmnApplicationBuildProfile _profileByName(String appName, String name) {
    final normalized = name.trim().toLowerCase();
    final matches = profiles(appName).where(
      (profile) => profile.name.trim().toLowerCase() == normalized,
    );
    if (matches.isEmpty) {
      throw StateError('Unknown application build profile: $appName / $name');
    }
    return matches.first;
  }

  WmnApplicationBuildProfile _profile(Map<String, Object?> row) =>
      WmnApplicationBuildProfile(
        id: '${row['id']}',
        appName: '${row['app_name']}',
        name: '${row['profile_name']}',
        mode: wmnApplicationBuildModeFromStorage(row['build_mode']),
        targets: _strings(_decodeJsonValue(row['targets_json'])),
        includeAssets: _bool(row['include_assets'], fallback: true),
        strictValidation: _bool(row['strict_validation'], fallback: true),
        enabled: _bool(row['enabled'], fallback: true),
        metadata: _jsonMap(row['metadata_json']),
      );

  List<String> _normalizeTargets(List<String> values) {
    const allowed = <String>{
      'all', 'windows', 'android', 'ios', 'mobile', 'web', 'server', 'linux', 'macos',
    };
    final result = values
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    if (result.isEmpty) result.add('all');
    final invalid = result.where((value) => !allowed.contains(value)).toList();
    if (invalid.isNotEmpty) throw StateError('Unknown build targets: ${invalid.join(', ')}');
    return result.toList(growable: false)..sort();
  }

  List<Map<String, Object?>> _rowsWhere(
    String table,
    String where,
    List<Object?> args,
  ) {
    if (!_tableExists(table)) return const <Map<String, Object?>>[];
    return database.db
        .select('SELECT * FROM ${_quote(table)} WHERE $where;', args)
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  List<Map<String, Object?>> _rowsIn(
    String table,
    String column,
    Set<String> values, {
    String? extraWhere,
  }) {
    if (values.isEmpty || !_tableExists(table)) return const <Map<String, Object?>>[];
    final suffix = extraWhere == null || extraWhere.trim().isEmpty ? '' : ' AND $extraWhere';
    return database.db
        .select(
          'SELECT * FROM ${_quote(table)} WHERE ${_quote(column)} IN (${_marks(values.length)})$suffix;',
          <Object?>[...values],
        )
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  bool _tableExists(String table) => database.db.select(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;",
        <Object?>[table],
      ).isNotEmpty;

  String _checksumText(Map<String, Uint8List> entries) {
    final paths = entries.keys.where((path) => path != 'checksums.sha256').toList()..sort();
    return '${paths.map((path) => '${sha256.convert(entries[path]!)}  $path').join('\n')}\n';
  }

  void _verifyChecksums(Map<String, Uint8List> files, String text) {
    final checksummed = <String>{};
    for (final rawLine in const LineSplitter().convert(text)) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final separator = line.indexOf('  ');
      if (separator <= 0) throw StateError('Invalid WMN package checksum line.');
      final expected = line.substring(0, separator).trim().toLowerCase();
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) {
        throw StateError('Invalid WMN package checksum digest.');
      }
      final path = _safeArchivePath(line.substring(separator + 2).trim());
      if (path == 'checksums.sha256') {
        throw StateError('Checksum manifest cannot checksum itself.');
      }
      if (!checksummed.add(path)) {
        throw StateError('Duplicate WMN package checksum entry: $path');
      }
      final payload = files[path];
      if (payload == null) throw StateError('Checksummed package entry is missing: $path');
      final actual = sha256.convert(payload).toString();
      if (actual != expected) throw StateError('WMN package checksum mismatch: $path');
    }
    final packageFiles = files.keys.where((path) => path != 'checksums.sha256').toSet();
    final unchecked = packageFiles.difference(checksummed).toList()..sort();
    if (unchecked.isNotEmpty) {
      throw StateError(
        'WMN package contains unchecked entries: ${unchecked.join(', ')}',
      );
    }
    final missing = checksummed.difference(packageFiles).toList()..sort();
    if (missing.isNotEmpty) {
      throw StateError(
        'WMN package checksum manifest references unavailable entries: ${missing.join(', ')}',
      );
    }
  }

  Uint8List _jsonBytes(Object? value) =>
      Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(value)));

  Map<String, Object?> _decodeMap(Uint8List bytes, String path) {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map) throw StateError('Invalid JSON object: $path');
    return Map<String, Object?>.from(value);
  }

  List<Map<String, Object?>> _decodeListOfMaps(Uint8List bytes, String path) {
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! List) throw StateError('Invalid JSON list: $path');
    return value.map((entry) {
      if (entry is! Map) throw StateError('Invalid metadata row in $path');
      return Map<String, Object?>.from(entry);
    }).toList(growable: false);
  }

  static const List<String> _componentNames = <String>[
    'modules',
    'doctypes',
    'doctype_fields',
    'doctype_permissions',
    'list_views',
    'custom_fields',
    'property_overrides',
    'numbering_series',
    'roles',
    'permissions',
    'role_permissions',
    'workspaces',
    'workspace_items',
    'pages',
    'reports',
    'report_filters',
    'report_columns',
    'print_formats',
    'client_scripts',
    'server_scripts',
    'workflows',
    'workflow_states',
    'workflow_transitions',
    'method_bindings',
    'hook_bindings',
    'number_cards',
    'dashboard_charts',
  ];

  static List<String> _strings(Object? value) => value is List
      ? value.map((entry) => '$entry'.trim()).where((entry) => entry.isNotEmpty).toSet().toList(growable: false)
      : const <String>[];

  static Map<String, Object?> _jsonMap(Object? value) {
    if (value is Map) return Map<String, Object?>.from(value);
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, Object?>.from(decoded);
      } catch (_) {}
    }
    return const <String, Object?>{};
  }

  static Object? _decodeJsonValue(Object? value) {
    if (value == null) return null;
    if (value is! String) return value;
    final text = value.trim();
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } catch (_) {
      return value;
    }
  }

  static bool _bool(Object? value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = '${value ?? ''}'.trim().toLowerCase();
    if (const <String>{'1', 'true', 'yes', 'on'}.contains(normalized)) return true;
    if (const <String>{'0', 'false', 'no', 'off'}.contains(normalized)) return false;
    return fallback;
  }

  static String? _nullable(Object? value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty || text.toLowerCase() == 'null' ? null : text;
  }

  static String _quote(String identifier) => '"${identifier.replaceAll('"', '""')}"';
  static String _marks(int count) => List<String>.filled(count, '?').join(',');

  static int _compareSemanticVersions(String left, String right) {
    final leftParts = _semanticVersionCore(left);
    final rightParts = _semanticVersionCore(right);
    for (var index = 0; index < 3; index++) {
      final comparison = leftParts[index].compareTo(rightParts[index]);
      if (comparison != 0) return comparison;
    }
    return 0;
  }

  static List<int> _semanticVersionCore(String value) {
    final core = value.trim().split(RegExp(r'[-+]')).first;
    final parts = core.split('.');
    if (parts.length != 3) return const <int>[0, 0, 0];
    return parts
        .map((part) => int.tryParse(part) ?? 0)
        .toList(growable: false);
  }

  static String _safeArchivePath(String raw) {
    final normalized = raw.trim().replaceAll('\\', '/');
    if (normalized.isEmpty || normalized.startsWith('/')) {
      throw StateError('Unsafe application package path: $raw');
    }
    final parts = normalized.split('/');
    if (parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw StateError('Unsafe application package path: $raw');
    }
    return parts.join('/');
  }

  static String _safeFileName(String raw) {
    final normalized = raw.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return normalized.isEmpty ? 'source.txt' : normalized;
  }
}

class _DecodedPackage {
  const _DecodedPackage({
    required this.inspection,
    required this.files,
    required this.components,
    required this.sources,
    required this.assets,
  });

  final WmnApplicationPackageInspection inspection;
  final Map<String, Uint8List> files;
  final Map<String, List<Map<String, Object?>>> components;
  final List<Map<String, Object?>> sources;
  final List<Map<String, Object?>> assets;
}
