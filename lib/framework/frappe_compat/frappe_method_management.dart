import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../core/database/wmn_database.dart';
import '../doctype_studio/doctype_code_validator.dart';
import '../doctype_studio/doctype_studio_models.dart';
import '../meta/meta_service.dart';
import '../../platform/storage/wmn_storage_service.dart';

class WmnManagedMethodModule {
  const WmnManagedMethodModule({
    required this.id,
    required this.name,
    required this.source,
    required this.status,
    required this.revision,
    required this.enabled,
    required this.exports,
    required this.dependencies,
    required this.isCustom,
    this.description,
    this.updatedAt,
    this.sourceApp,
    this.diagnostics = const [],
  });

  final String id;
  final String name;
  final String source;
  final String status;
  final int revision;
  final bool enabled;
  final List<String> exports;
  final List<String> dependencies;
  final bool isCustom;
  final String? description;
  final String? updatedAt;
  final String? sourceApp;
  final List<WmnCodeDiagnostic> diagnostics;
}

class WmnManagedSystemScript {
  const WmnManagedSystemScript({
    required this.id,
    required this.name,
    required this.source,
    required this.status,
    required this.revision,
    required this.enabled,
    this.description,
    this.updatedAt,
    this.diagnostics = const [],
  });

  final String id;
  final String name;
  final String source;
  final String status;
  final int revision;
  final bool enabled;
  final String? description;
  final String? updatedAt;
  final List<WmnCodeDiagnostic> diagnostics;
}

/// Global management for platform-wide code modules and scripts.
///
/// In WMN terminology a "Method" is a server code module: the equivalent of
/// a Python module/controller file in Frappe. A method module may export many
/// callable functions. Individual functions remain registry exports; they are
/// not modeled as separate user-owned Method records.
class WmnMethodManagementService {
  WmnMethodManagementService({required this.database, required this.meta, WmnStorageService? storage})
      : storage = storage ?? WmnStorageService.forDatabase(database);

  final WmnDatabase database;
  final WmnMetaService meta;
  final WmnStorageService storage;

  static const Uuid _uuid = Uuid();
  static const String _globalScope = 'SYSTEM_GLOBAL';
  static const String _globalScriptHookType = 'SYSTEM_SCRIPT';
  static const String _globalMethodModuleHookType = 'SYSTEM_METHOD_MODULE';
  static const String _serverModuleTargetKind = 'METHOD';

  /// Builds the protected system Method-module catalog from the callable
  /// function registry. Example: wmn.db contains insert/update/delete exports.
  List<WmnManagedMethodModule> systemMethodModules(List<Map<String, Object?>> methodCatalog) {
    final grouped = <String, List<Map<String, Object?>>>{};
    for (final row in methodCatalog) {
      if (row['wmn_custom_method'] == true || row['editable'] == true) continue;
      final functionName = '${row['method_name'] ?? ''}'.trim();
      if (functionName.isEmpty || !functionName.contains('.')) continue;
      final moduleName = _moduleNameForFunction(functionName);
      grouped.putIfAbsent(moduleName, () => <Map<String, Object?>>[]).add(row);
    }

    final result = <WmnManagedMethodModule>[];
    for (final entry in grouped.entries) {
      final rows = entry.value..sort((a, b) => '${a['method_name']}'.compareTo('${b['method_name']}'));
      final exports = rows
          .map((row) => _exportNameForFunction('${row['method_name']}'))
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false)
        ..sort();
      final sourceApps = rows
          .map((row) => '${row['source_app'] ?? ''}'.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false)
        ..sort();
      final descriptions = rows
          .map((row) => '${row['description'] ?? ''}'.trim())
          .where((value) => value.isNotEmpty)
          .take(3)
          .join(' • ');
      result.add(WmnManagedMethodModule(
        id: entry.key,
        name: entry.key,
        source: '',
        status: 'NATIVE',
        revision: 0,
        enabled: true,
        exports: exports,
        dependencies: const [],
        isCustom: false,
        description: descriptions.isEmpty ? null : descriptions,
        sourceApp: sourceApps.isEmpty ? 'WMN Runtime' : sourceApps.join(', '),
      ));
    }
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  }

  List<WmnManagedMethodModule> customMethodModules() {
    final rows = database.db.select('''
      SELECT id,target,enabled,source_app,source_path,metadata_json,updated_at
      FROM wmn_hook_bindings
      WHERE hook_type=? AND target_kind=?
      ORDER BY target COLLATE NOCASE;
    ''', [_globalMethodModuleHookType, _serverModuleTargetKind]);
    final result = <WmnManagedMethodModule>[];
    for (final row in rows) {
      final metadata = _jsonMap(row['metadata_json']);
      if (metadata['wmn_custom_method_module'] != true || metadata['scope'] != _globalScope) continue;
      final diagnostics = (metadata['diagnostics'] as List? ?? const [])
          .whereType<Map>()
          .map((entry) => WmnCodeDiagnostic.fromJson(Map<String, Object?>.from(entry)))
          .toList(growable: false);
      result.add(WmnManagedMethodModule(
        id: '${row['id']}',
        name: '${metadata['module_name'] ?? row['target'] ?? ''}',
        source: _readStoredSource(row['source_path']?.toString(), metadata['source']?.toString()),
        status: '${metadata['status'] ?? 'DRAFT'}',
        revision: (metadata['revision'] as num?)?.toInt() ?? 0,
        enabled: (row['enabled'] as int? ?? 0) == 1,
        exports: _stringList(metadata['exports']),
        dependencies: _stringList(metadata['dependencies']),
        isCustom: true,
        description: metadata['description']?.toString(),
        updatedAt: row['updated_at']?.toString(),
        sourceApp: row['source_app']?.toString(),
        diagnostics: diagnostics,
      ));
    }
    return result;
  }

  WmnCodeValidationResult validateMethodModule({
    required String source,
    required Set<String> supportedApis,
  }) {
    final base = const WmnDocTypeCodeValidator().validateSystemScript(
      source: source,
      supportedApis: supportedApis,
    );
    final diagnostics = <WmnCodeDiagnostic>[...base.diagnostics];
    final exports = _detectExports(source);
    if (exports.isEmpty) {
      diagnostics.add(const WmnCodeDiagnostic(
        severity: 'WARNING',
        code: 'NO_MODULE_EXPORTS',
        message: 'No callable functions were detected in this server Method module.',
      ));
    }
    return WmnCodeValidationResult(diagnostics: diagnostics);
  }

  WmnManagedMethodModule saveCustomMethodModule({
    String? id,
    required String name,
    required String source,
    String? description,
    required Set<String> supportedApis,
  }) {
    final normalizedName = name.trim();
    _validateCustomName(normalizedName);
    final validation = validateMethodModule(source: source, supportedApis: supportedApis);
    final existing = id == null
        ? database.db.select('''
            SELECT id,source_path,metadata_json FROM wmn_hook_bindings
            WHERE hook_type=? AND target_kind=? AND target=? LIMIT 1;
          ''', [_globalMethodModuleHookType, _serverModuleTargetKind, normalizedName])
        : database.db.select(
            'SELECT id,source_path,metadata_json FROM wmn_hook_bindings WHERE id=? LIMIT 1;',
            [id],
          );
    if (existing.isNotEmpty) {
      final existingMetadata = _jsonMap(existing.first['metadata_json']);
      if (existingMetadata['wmn_custom_method_module'] != true || existingMetadata['scope'] != _globalScope) {
        throw StateError('System/native Method module cannot be replaced: $normalizedName');
      }
    }

    final existingMetadata = existing.isEmpty ? <String, Object?>{} : _jsonMap(existing.first['metadata_json']);
    final previousRevision = (existingMetadata['revision'] as num?)?.toInt() ?? 0;
    final previousPath = existing.isEmpty ? null : existing.first['source_path']?.toString();
    final revisions = <Object?>[
      ...(existingMetadata['revisions'] as List? ?? const <Object?>[]),
      if (existingMetadata.isNotEmpty)
        <String, Object?>{
          'revision': previousRevision,
          if (previousPath != null && previousPath.isNotEmpty) 'source_path': previousPath,
          'status': '${existingMetadata['status'] ?? 'DRAFT'}',
          'source_hash': '${existingMetadata['source_hash'] ?? ''}',
          'exports': existingMetadata['exports'] ?? const <Object?>[],
          'dependencies': existingMetadata['dependencies'] ?? const <Object?>[],
          'created_at': '${existingMetadata['updated_at'] ?? ''}',
        },
    ];
    if (revisions.length > 50) revisions.removeRange(0, revisions.length - 50);

    final now = DateTime.now().toUtc().toIso8601String();
    final nextRevision = previousRevision + 1;
    final bindingId = existing.isNotEmpty ? '${existing.first['id']}' : (id ?? _uuid.v4());
    final sourcePath = 'apps/custom/methods/${_storageSegment(normalizedName)}/r$nextRevision.wmn';
    storage.writeText(sourcePath, source);
    final metadata = <String, Object?>{
      'wmn_custom_method_module': true,
      'scope': _globalScope,
      'module_name': normalizedName,
      'module_type': 'SERVER_METHOD_MODULE',
      'frappe_equivalent': 'PYTHON_MODULE_FILE',
      'language': 'WMN_SERVER_MODULE',
      'description': description?.trim() ?? '',
      'status': validation.isValid ? 'VALIDATED' : 'DRAFT',
      'activation_gated': true,
      'revision': nextRevision,
      'source_hash': sha256.convert(utf8.encode(source)).toString(),
      'exports': _detectExports(source),
      'dependencies': _detectDependencies(source),
      'diagnostics': validation.diagnostics.map((entry) => entry.toJson()).toList(growable: false),
      'revisions': revisions,
      'updated_at': now,
    };

    database.db.execute('''
      INSERT INTO wmn_hook_bindings(
        id,hook_type,reference_doctype,event_name,source_app,source_path,target_kind,target,
        priority,enabled,metadata_json,created_at,updated_at
      ) VALUES (?,?,NULL,NULL,'WMN Custom',?, ?,?,0,0,?,?,?)
      ON CONFLICT(id) DO UPDATE SET
        hook_type=excluded.hook_type,
        reference_doctype=NULL,
        event_name=NULL,
        source_app=excluded.source_app,
        source_path=excluded.source_path,
        target_kind=excluded.target_kind,
        target=excluded.target,
        priority=0,
        enabled=0,
        metadata_json=excluded.metadata_json,
        updated_at=excluded.updated_at;
    ''', [
      bindingId,
      _globalMethodModuleHookType,
      sourcePath,
      _serverModuleTargetKind,
      normalizedName,
      jsonEncode(metadata),
      now,
      now,
    ]);

    return customMethodModules().firstWhere((entry) => entry.id == bindingId);
  }

  void deleteCustomMethodModule(String id) {
    final rows = database.db.select(
      'SELECT source_path,metadata_json FROM wmn_hook_bindings WHERE id=? LIMIT 1;',
      [id],
    );
    if (rows.isEmpty) throw StateError('Unknown Method module: $id');
    final metadata = _jsonMap(rows.first['metadata_json']);
    if (metadata['wmn_custom_method_module'] != true || metadata['scope'] != _globalScope) {
      throw StateError('System/native Method module cannot be modified.');
    }
    _deleteStoredSources(rows.first['source_path']?.toString(), metadata);
    database.db.execute('DELETE FROM wmn_hook_bindings WHERE id=?;', [id]);
  }

  List<WmnManagedSystemScript> customScripts() {
    final rows = database.db.select('''
      SELECT id,target,enabled,source_path,metadata_json,updated_at
      FROM wmn_hook_bindings
      WHERE hook_type=? AND target_kind='SERVER_SCRIPT'
      ORDER BY target COLLATE NOCASE;
    ''', [_globalScriptHookType]);
    final result = <WmnManagedSystemScript>[];
    for (final row in rows) {
      final metadata = _jsonMap(row['metadata_json']);
      if (metadata['wmn_custom_system_script'] != true || metadata['scope'] != _globalScope) continue;
      final diagnostics = (metadata['diagnostics'] as List? ?? const [])
          .whereType<Map>()
          .map((entry) => WmnCodeDiagnostic.fromJson(Map<String, Object?>.from(entry)))
          .toList(growable: false);
      result.add(WmnManagedSystemScript(
        id: '${row['id']}',
        name: '${metadata['script_name'] ?? row['target'] ?? ''}',
        source: _readStoredSource(row['source_path']?.toString(), metadata['source']?.toString()),
        status: '${metadata['status'] ?? 'DRAFT'}',
        revision: (metadata['revision'] as num?)?.toInt() ?? 0,
        enabled: (row['enabled'] as int? ?? 0) == 1,
        description: metadata['description']?.toString(),
        updatedAt: row['updated_at']?.toString(),
        diagnostics: diagnostics,
      ));
    }
    return result;
  }

  WmnCodeValidationResult validateSystemScript({
    required String source,
    required Set<String> supportedApis,
  }) =>
      const WmnDocTypeCodeValidator().validateSystemScript(source: source, supportedApis: supportedApis);

  WmnManagedSystemScript saveCustomSystemScript({
    String? id,
    required String name,
    required String source,
    String? description,
    required Set<String> supportedApis,
  }) {
    final normalizedName = name.trim();
    _validateCustomName(normalizedName);
    final validation = validateSystemScript(source: source, supportedApis: supportedApis);
    final existing = id == null
        ? database.db.select('''
            SELECT id,source_path,metadata_json FROM wmn_hook_bindings
            WHERE hook_type=? AND target_kind='SERVER_SCRIPT' AND target=? LIMIT 1;
          ''', [_globalScriptHookType, normalizedName])
        : database.db.select(
            'SELECT id,source_path,metadata_json FROM wmn_hook_bindings WHERE id=? LIMIT 1;',
            [id],
          );
    if (existing.isNotEmpty) {
      final existingMetadata = _jsonMap(existing.first['metadata_json']);
      if (existingMetadata['wmn_custom_system_script'] != true || existingMetadata['scope'] != _globalScope) {
        throw StateError('System/native script cannot be replaced: $normalizedName');
      }
    }

    final existingMetadata = existing.isEmpty ? <String, Object?>{} : _jsonMap(existing.first['metadata_json']);
    final previousRevision = (existingMetadata['revision'] as num?)?.toInt() ?? 0;
    final previousPath = existing.isEmpty ? null : existing.first['source_path']?.toString();
    final revisions = <Object?>[
      ...(existingMetadata['revisions'] as List? ?? const <Object?>[]),
      if (existingMetadata.isNotEmpty)
        <String, Object?>{
          'revision': previousRevision,
          if (previousPath != null && previousPath.isNotEmpty) 'source_path': previousPath,
          'status': '${existingMetadata['status'] ?? 'DRAFT'}',
          'source_hash': '${existingMetadata['source_hash'] ?? ''}',
          'created_at': '${existingMetadata['updated_at'] ?? ''}',
        },
    ];
    if (revisions.length > 50) revisions.removeRange(0, revisions.length - 50);

    final now = DateTime.now().toUtc().toIso8601String();
    final nextRevision = previousRevision + 1;
    final bindingId = existing.isNotEmpty ? '${existing.first['id']}' : (id ?? _uuid.v4());
    final sourcePath = 'apps/custom/scripts/system/${_storageSegment(normalizedName)}/r$nextRevision.wmn';
    storage.writeText(sourcePath, source);
    final metadata = <String, Object?>{
      'wmn_custom_system_script': true,
      'scope': _globalScope,
      'script_name': normalizedName,
      'language': 'WMN_SERVER_SCRIPT',
      'description': description?.trim() ?? '',
      'status': validation.isValid ? 'VALIDATED' : 'DRAFT',
      'activation_gated': true,
      'revision': nextRevision,
      'source_hash': sha256.convert(utf8.encode(source)).toString(),
      'diagnostics': validation.diagnostics.map((entry) => entry.toJson()).toList(growable: false),
      'revisions': revisions,
      'updated_at': now,
    };

    database.db.execute('''
      INSERT INTO wmn_hook_bindings(
        id,hook_type,reference_doctype,event_name,source_app,source_path,target_kind,target,
        priority,enabled,metadata_json,created_at,updated_at
      ) VALUES (?,?,NULL,NULL,'WMN Custom',?,'SERVER_SCRIPT',?,0,0,?,?,?)
      ON CONFLICT(id) DO UPDATE SET
        hook_type=excluded.hook_type,
        reference_doctype=NULL,
        event_name=NULL,
        source_app=excluded.source_app,
        source_path=excluded.source_path,
        target_kind='SERVER_SCRIPT',
        target=excluded.target,
        priority=0,
        enabled=0,
        metadata_json=excluded.metadata_json,
        updated_at=excluded.updated_at;
    ''', [bindingId, _globalScriptHookType, sourcePath, normalizedName, jsonEncode(metadata), now, now]);

    return customScripts().firstWhere((entry) => entry.id == bindingId);
  }

  void deleteCustomScript(String id) {
    final rows = database.db.select(
      'SELECT source_path,metadata_json FROM wmn_hook_bindings WHERE id=? LIMIT 1;',
      [id],
    );
    if (rows.isEmpty) throw StateError('Unknown system script: $id');
    final metadata = _jsonMap(rows.first['metadata_json']);
    if (metadata['wmn_custom_system_script'] != true || metadata['scope'] != _globalScope) {
      throw StateError('System/native script cannot be modified.');
    }
    _deleteStoredSources(rows.first['source_path']?.toString(), metadata);
    database.db.execute('DELETE FROM wmn_hook_bindings WHERE id=?;', [id]);
  }

  String _readStoredSource(String? sourcePath, String? legacySource) {
    final path = sourcePath?.trim() ?? '';
    if (path.isNotEmpty && storage.exists(path)) return storage.readText(path);
    return legacySource ?? '';
  }

  void _deleteStoredSources(String? currentPath, Map<String, Object?> metadata) {
    final keys = <String>{};
    final current = currentPath?.trim() ?? '';
    if (current.isNotEmpty) keys.add(current);
    for (final raw in metadata['revisions'] as List? ?? const <Object?>[]) {
      if (raw is! Map) continue;
      final path = raw['source_path']?.toString().trim() ?? '';
      if (path.isNotEmpty) keys.add(path);
    }
    for (final key in keys) {
      if (storage.exists(key)) storage.delete(key);
    }
  }

  String _storageSegment(String value) {
    final safe = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_').replaceAll(RegExp(r'_+'), '_');
    final trimmed = safe.replaceAll(RegExp(r'^[_\.]+|[_\.]+$'), '');
    return trimmed.isEmpty ? 'unknown' : trimmed;
  }

  List<String> _detectExports(String source) {
    final names = <String>{};
    final patterns = <RegExp>[
      RegExp(r'\bfunction\s+([A-Za-z_][A-Za-z0-9_]*)\s*\('),
      RegExp(r'^\s*def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(', multiLine: true),
      RegExp(r'^\s*export\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(', multiLine: true),
    ];
    for (final pattern in patterns) {
      for (final match in pattern.allMatches(source)) {
        final value = match.group(1)?.trim() ?? '';
        if (value.isNotEmpty && !value.startsWith('_')) names.add(value);
      }
    }
    final result = names.toList(growable: false)..sort();
    return result;
  }

  List<String> _detectDependencies(String source) {
    final dependencies = <String>{};
    final calls = RegExp(r'\b((?:wmn|frappe|custom)(?:\.[A-Za-z_][A-Za-z0-9_]*)+)\s*\(');
    for (final match in calls.allMatches(source)) {
      final functionName = match.group(1) ?? '';
      if (!functionName.contains('.')) continue;
      dependencies.add(_moduleNameForFunction(functionName));
    }
    for (final match in RegExp(r'^\s*use\s+((?:wmn|frappe|custom)(?:\.[A-Za-z_][A-Za-z0-9_]*)+)\s*;?$', multiLine: true).allMatches(source)) {
      final moduleName = match.group(1)?.trim() ?? '';
      if (moduleName.isNotEmpty) dependencies.add(moduleName);
    }
    final result = dependencies.toList(growable: false)..sort();
    return result;
  }

  String _moduleNameForFunction(String functionName) {
    final index = functionName.lastIndexOf('.');
    return index <= 0 ? functionName : functionName.substring(0, index);
  }

  String _exportNameForFunction(String functionName) {
    final index = functionName.lastIndexOf('.');
    return index < 0 ? functionName : functionName.substring(index + 1);
  }

  void _validateCustomName(String value) {
    if (!value.startsWith('custom.')) {
      throw StateError('Custom system names must start with custom.');
    }
    if (!RegExp(r'^custom\.[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*$').hasMatch(value)) {
      throw StateError('Invalid custom system name: $value');
    }
  }

  List<String> _stringList(Object? raw) => (raw as List? ?? const <Object?>[])
      .map((entry) => '$entry'.trim())
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);

  Map<String, Object?> _jsonMap(Object? raw) {
    if (raw is Map) return Map<String, Object?>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, Object?>.from(decoded);
      } catch (_) {}
    }
    return <String, Object?>{};
  }
}
