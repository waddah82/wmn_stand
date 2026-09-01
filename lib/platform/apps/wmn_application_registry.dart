import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/database/wmn_database.dart';
import '../adapters/wmn_platform_adapter.dart';
import '../adapters/wmn_platform_adapter_registry.dart';
import '../capabilities/wmn_capability_registry.dart';
import '../system/wmn_platform_version.dart';
import '../system/wmn_system_module.dart';
import '../system/wmn_system_module_registry.dart';
import 'wmn_app_manifest.dart';

class WmnInstalledApplication {
  const WmnInstalledApplication({
    required this.manifest,
    required this.sourceFramework,
    required this.status,
    this.sourceRepository,
  });

  final WmnAppManifest manifest;
  final String sourceFramework;
  final String status;
  final String? sourceRepository;
}

class WmnApplicationDiagnostic {
  const WmnApplicationDiagnostic({
    required this.appName,
    required this.errors,
    required this.warnings,
  });

  final String appName;
  final List<String> errors;
  final List<String> warnings;

  bool get compatible => errors.isEmpty;
}

/// General application registry for WMN.
///
/// The registry is intentionally domain-neutral: Accounting, Retail, Hospital,
/// HR or any future application is simply an application manifest consuming
/// WMN capabilities. No application-specific service is added to System Core.
class WmnApplicationRegistry extends ChangeNotifier {
  WmnApplicationRegistry(
    this.database,
    this.systemModules,
    this.capabilities, {
    this.platformAdapters,
  });

  final WmnDatabase database;
  final WmnSystemModuleRegistry systemModules;
  final WmnCapabilityRegistry capabilities;
  final WmnPlatformAdapterRegistry? platformAdapters;

  List<WmnInstalledApplication> applications() {
    final rows = database.db.select('''
      SELECT app_name,app_title,app_version,source_framework,source_repository,
             manifest_json,conversion_status
      FROM wmn_app_packages
      ORDER BY COALESCE(app_title,app_name) COLLATE NOCASE;
    ''');
    return rows.map((row) {
      final raw = _jsonMap(row['manifest_json']);
      final manifest = WmnAppManifest.fromJson(<String, Object?>{
        ...raw,
        'name': raw['name'] ?? row['app_name'],
        'title': raw['title'] ?? row['app_title'] ?? row['app_name'],
        'version': raw['version'] ?? row['app_version'] ?? '0.0.0',
      });
      return WmnInstalledApplication(
        manifest: manifest,
        sourceFramework: '${row['source_framework'] ?? 'WMN'}',
        status: '${row['conversion_status'] ?? 'IMPORTED'}',
        sourceRepository: row['source_repository']?.toString(),
      );
    }).toList(growable: false);
  }

  WmnInstalledApplication? application(String name) {
    final matches = applications().where((entry) => entry.manifest.name == name);
    return matches.isEmpty ? null : matches.first;
  }

  WmnApplicationDiagnostic diagnose(
    WmnAppManifest manifest, {
    bool checkRuntimeTarget = true,
  }) {
    final errors = <String>[...manifest.validateStructure()];
    final warnings = <String>[];

    final minimumPlatformVersion = manifest.minimumPlatformVersion;
    if (minimumPlatformVersion != null &&
        minimumPlatformVersion.trim().isNotEmpty &&
        _compareSemanticVersions(
              WmnPlatformVersion.version,
              minimumPlatformVersion,
            ) <
            0) {
      errors.add(
        'Application requires WMN platform $minimumPlatformVersion or newer; '
        'current platform is ${WmnPlatformVersion.version}.',
      );
    }

    final installedReadyApps = <String>{
      for (final app in applications())
        if (app.status == 'READY' && app.manifest.name != manifest.name)
          app.manifest.name,
    };
    final missingApplications = manifest.requiredApplications
        .where((name) => !installedReadyApps.contains(name))
        .toSet()
        .toList()
      ..sort();
    if (missingApplications.isNotEmpty) {
      errors.add(
        'Application requires unavailable WMN applications: '
        '${missingApplications.join(', ')}',
      );
    }

    if (manifest.capabilityProfile != null) {
      try {
        final profile = capabilities.profile(manifest.capabilityProfile!);
        final missingProfile = capabilities.missing(profile.requiredCapabilities);
        if (missingProfile.isNotEmpty) {
          errors.add(
            'Capability profile ${profile.id} requires unavailable capabilities: '
            '${missingProfile.join(', ')}',
          );
        }
        final optional =
            capabilities.unavailableOptional(profile.optionalCapabilities);
        if (optional.isNotEmpty) {
          warnings.add(
            'Capability profile ${profile.id} has unavailable optional '
            'capabilities: ${optional.join(', ')}',
          );
        }
      } catch (error) {
        errors.add('$error');
      }
    }

    final adapters = platformAdapters;
    if (checkRuntimeTarget &&
        adapters != null &&
        manifest.platformTargets.isNotEmpty) {
      final runtimeTargets = _runtimeTargets(adapters.runtimePlatform);
      final targets = manifest.platformTargets
          .map((value) => value.trim().toLowerCase())
          .toSet();
      if (!targets.contains('all') &&
          runtimeTargets.isNotEmpty &&
          runtimeTargets.intersection(targets).isEmpty) {
        errors.add(
          'Application does not target the current WMN runtime platform: '
          '${runtimeTargets.first}',
        );
      }
    }

    final missingModules = manifest.requiredSystemModules.where((id) {
      try {
        final module = systemModules.definition(id);
        return !systemModules.isEnabled(id) || !_moduleExecutable(module);
      } catch (_) {
        return true;
      }
    }).toSet().toList()
      ..sort();
    if (missingModules.isNotEmpty) {
      errors.add(
        'Application requires unavailable WMN system modules: '
        '${missingModules.join(', ')}',
      );
    }

    final missingCapabilities =
        capabilities.missing(manifest.requiredCapabilities);
    if (missingCapabilities.isNotEmpty) {
      errors.add(
        'Application requires unavailable WMN capabilities: '
        '${missingCapabilities.join(', ')}',
      );
    }

    final optionalMissing =
        capabilities.unavailableOptional(manifest.optionalCapabilities);
    if (optionalMissing.isNotEmpty) {
      warnings.add(
        'Optional WMN capabilities are unavailable: '
        '${optionalMissing.join(', ')}',
      );
    }

    final existingRouteOwners = <String, String>{};
    for (final app in applications()) {
      if (app.status != 'READY' || app.manifest.name == manifest.name) continue;
      for (final path in <String>{
        ...app.manifest.routes.map((route) => route.trim()),
        ...app.manifest.routeDefinitions.map((route) => route.path.trim()),
      }) {
        if (path.isNotEmpty) existingRouteOwners[path] = app.manifest.name;
      }
    }
    final pageRoutes = database.db.select('''
      SELECT route,app_name,name FROM [tabPage]
      WHERE enabled=1 AND (app_name IS NULL OR app_name<>?);
    ''', <Object?>[manifest.name]);
    for (final row in pageRoutes) {
      final path = '${row['route'] ?? ''}'.trim();
      if (path.isEmpty) continue;
      final owner = '${row['app_name'] ?? 'WMN System'}'.trim();
      existingRouteOwners[path] = owner.isEmpty ? 'WMN System' : owner;
    }

    final routeCollisions = <String>[];
    for (final path in <String>{
      ...manifest.routes.map((route) => route.trim()),
      ...manifest.routeDefinitions.map((route) => route.path.trim()),
    }) {
      final owner = existingRouteOwners[path];
      if (owner != null) routeCollisions.add('$path ($owner)');
    }
    routeCollisions.sort();
    if (routeCollisions.isNotEmpty) {
      errors.add(
        'Application routes collide with installed applications: '
        '${routeCollisions.join(', ')}',
      );
    }

    for (final moduleName in manifest.modules.toSet()) {
      final moduleRows = database.db.select(
        'SELECT app_name FROM wmn_modules WHERE name=? LIMIT 1;',
        <Object?>[moduleName],
      );
      if (moduleRows.isEmpty) continue;
      final owner = '${moduleRows.first['app_name'] ?? ''}'.trim();
      if (owner.isNotEmpty && owner != manifest.name) {
        errors.add(
          'Application module $moduleName is already owned by $owner.',
        );
      }
    }

    return WmnApplicationDiagnostic(
      appName: manifest.name,
      errors: List<String>.unmodifiable(errors),
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  List<String> platformIssues() {
    final issues = <String>[];
    for (final app in applications()) {
      if (app.status != 'READY') continue;
      final diagnostic = diagnose(app.manifest);
      for (final error in diagnostic.errors) {
        issues.add('${app.manifest.name}: $error');
      }
    }
    return issues;
  }

  void register(WmnAppManifest manifest) {
    final diagnostic = diagnose(manifest);
    if (!diagnostic.compatible) {
      throw StateError(diagnostic.errors.join(' '));
    }

    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO wmn_app_packages(
        app_name,app_title,app_version,source_framework,module_json,manifest_json,
        conversion_status,installed_at,updated_at
      ) VALUES (?,?,?,'WMN',?,?,'READY',?,?)
      ON CONFLICT(app_name) DO UPDATE SET
        app_title=excluded.app_title,
        app_version=excluded.app_version,
        source_framework='WMN',
        module_json=excluded.module_json,
        manifest_json=excluded.manifest_json,
        conversion_status='READY',
        updated_at=excluded.updated_at;
    ''', [
      manifest.name.trim(),
      manifest.title.trim(),
      manifest.version.trim(),
      jsonEncode(<String, Object?>{'modules': manifest.modules}),
      manifest.encode(),
      now,
      now,
    ]);
    _synchronizeApplicationModules(manifest, now);
    _synchronizeApplicationDependencies(manifest, now);
    notifyListeners();
  }

  void remove(String name) {
    final row = database.db.select(
      'SELECT source_framework FROM wmn_app_packages WHERE app_name=? LIMIT 1;',
      [name],
    );
    if (row.isEmpty) return;
    if ('${row.first['source_framework']}' != 'WMN') {
      throw StateError(
        'Imported source packages are removed through the Developer/App '
        'Converter workflow.',
      );
    }

    final dependents = applications()
        .where(
          (app) =>
              app.status == 'READY' &&
              app.manifest.name != name &&
              app.manifest.requiredApplications.contains(name),
        )
        .map((app) => app.manifest.name)
        .toList()
      ..sort();
    if (dependents.isNotEmpty) {
      throw StateError(
        'Cannot remove WMN application $name; required by: '
        '${dependents.join(', ')}',
      );
    }

    database.db.execute('DELETE FROM wmn_app_packages WHERE app_name=?;', [name]);
    notifyListeners();
  }

  void _synchronizeApplicationModules(WmnAppManifest manifest, String now) {
    for (final moduleName in manifest.modules.toSet()) {
      final normalized = moduleName.trim();
      if (normalized.isEmpty) continue;
      final existing = database.db.select(
        'SELECT app_name FROM wmn_modules WHERE name=? LIMIT 1;',
        <Object?>[normalized],
      );
      if (existing.isNotEmpty) {
        final owner = '${existing.first['app_name'] ?? ''}'.trim();
        if (owner.isNotEmpty && owner != manifest.name) {
          throw StateError(
            'Application module $normalized is already owned by $owner.',
          );
        }
        database.db.execute('''
          UPDATE wmn_modules SET app_name=?,updated_at=? WHERE name=?;
        ''', <Object?>[manifest.name, now, normalized]);
        continue;
      }
      final sequenceRows = database.db.select(
        'SELECT COALESCE(MAX(sequence_id),0)+10 AS value FROM wmn_modules;',
      );
      final sequence = (sequenceRows.first['value'] as num?)?.toDouble() ?? 10;
      database.db.execute('''
        INSERT INTO wmn_modules(
          name,label,app_name,sequence_id,enabled,metadata_json,created_at,updated_at
        ) VALUES (?,?,?,?,1,?,?,?);
      ''', <Object?>[
        normalized,
        normalized,
        manifest.name,
        sequence,
        jsonEncode(<String, Object?>{
          'managed_by': 'WMN App Manifest',
          'application_owned': true,
        }),
        now,
        now,
      ]);
    }
  }

  void _synchronizeApplicationDependencies(WmnAppManifest manifest, String now) {
    database.db.execute(
      "DELETE FROM wmn_app_dependencies WHERE app_name=? AND dependency_kind='APP';",
      <Object?>[manifest.name],
    );
    final readyApps = <String>{
      for (final app in applications())
        if (app.status == 'READY' && app.manifest.name != manifest.name)
          app.manifest.name,
    };
    for (final dependency in manifest.requiredApplications.toSet()) {
      database.db.execute('''
        INSERT INTO wmn_app_dependencies(
          app_name,dependency_name,dependency_kind,required,resolved,metadata_json,updated_at
        ) VALUES (?,?,'APP',1,?,'{"source":"wmn_app_manifest"}',?)
        ON CONFLICT(app_name,dependency_name,dependency_kind) DO UPDATE SET
          required=1,resolved=excluded.resolved,metadata_json=excluded.metadata_json,
          updated_at=excluded.updated_at;
      ''', <Object?>[
        manifest.name,
        dependency,
        readyApps.contains(dependency) ? 1 : 0,
        now,
      ]);
    }
  }

  bool _moduleExecutable(WmnSystemModuleDefinition module) => module.executable;

  Set<String> _runtimeTargets(WmnRuntimePlatform platform) => switch (platform) {
        WmnRuntimePlatform.windows => <String>{'windows'},
        WmnRuntimePlatform.android => <String>{'mobile', 'android'},
        WmnRuntimePlatform.ios => <String>{'mobile', 'ios'},
        WmnRuntimePlatform.web => <String>{'web'},
        WmnRuntimePlatform.server => <String>{'server'},
        WmnRuntimePlatform.linux => <String>{'linux'},
        WmnRuntimePlatform.macos => <String>{'macos'},
        WmnRuntimePlatform.unknown => <String>{},
      };

  int _compareSemanticVersions(String left, String right) {
    final leftParts = _semanticVersionCore(left);
    final rightParts = _semanticVersionCore(right);
    for (var index = 0; index < 3; index++) {
      final comparison = leftParts[index].compareTo(rightParts[index]);
      if (comparison != 0) return comparison;
    }
    return 0;
  }

  List<int> _semanticVersionCore(String value) {
    final core = value.trim().split(RegExp(r'[-+]')).first;
    final parts = core.split('.');
    if (parts.length != 3) return const <int>[0, 0, 0];
    return parts.map((part) => int.tryParse(part) ?? 0).toList(growable: false);
  }

  Map<String, Object?> _jsonMap(Object? value) {
    if (value is! String || value.trim().isEmpty) return <String, Object?>{};
    try {
      final decoded = jsonDecode(value);
      return decoded is Map
          ? Map<String, Object?>.from(decoded)
          : <String, Object?>{};
    } catch (_) {
      return <String, Object?>{};
    }
  }
}
