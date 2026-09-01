import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../core/database/wmn_database.dart';
import '../meta/meta_service.dart';
import '../workspaces/workspace_service.dart';
import '../../platform/pages/wmn_page_service.dart';
import '../../platform/storage/wmn_storage_service.dart';
import 'frappe_app_converter.dart';
import 'frappe_source_porter.dart';

class WmnFrappeAppManifest {
  const WmnFrappeAppManifest({
    required this.appName,
    required this.appTitle,
    this.version,
    this.repository,
    this.license,
    this.publisher,
    this.description,
    this.sourceRef,
    this.modules = const [],
    this.requiredApps = const [],
  });

  final String appName;
  final String appTitle;
  final String? version;
  final String? repository;
  final String? license;
  final String? publisher;
  final String? description;
  final String? sourceRef;
  final List<String> modules;
  final List<String> requiredApps;

  Map<String, Object?> toJson() => {
        'app_name': appName,
        'app_title': appTitle,
        'version': version,
        'repository': repository,
        'license': license,
        'publisher': publisher,
        'description': description,
        'source_ref': sourceRef,
        'modules': modules,
        'required_apps': requiredApps,
      };
}

class WmnFrappeAppConversionSummary {
  const WmnFrappeAppConversionSummary({
    required this.runId,
    required this.manifest,
    required this.totalArtifacts,
    required this.convertedArtifacts,
    required this.needsPortArtifacts,
    required this.ignoredArtifacts,
    required this.failedArtifacts,
    required this.convertedDocTypes,
    required this.convertedWorkspaces,
    required this.convertedPages,
    required this.placeholderDocTypes,
    required this.portingTasks,
    required this.sourceUnits,
    required this.autoConvertedSourceUnits,
    required this.reviewSourceUnits,
    required this.sourceSymbols,
    required this.messages,
  });

  final String runId;
  final WmnFrappeAppManifest manifest;
  final int totalArtifacts;
  final int convertedArtifacts;
  final int needsPortArtifacts;
  final int ignoredArtifacts;
  final int failedArtifacts;
  final int convertedDocTypes;
  final int convertedWorkspaces;
  final int convertedPages;
  final int placeholderDocTypes;
  final int portingTasks;
  final int sourceUnits;
  final int autoConvertedSourceUnits;
  final int reviewSourceUnits;
  final int sourceSymbols;
  final List<String> messages;

  bool get isReady => failedArtifacts == 0 && needsPortArtifacts == 0;
}

class WmnFrappeAppPackageConverter {
  WmnFrappeAppPackageConverter({
    required this.database,
    required this.meta,
    required this.converter,
    required this.workspaces,
    required this.pages,
    WmnStorageService? storage,
    http.Client? httpClient,
  })  : _http = httpClient ?? http.Client(),
        sourcePorter = WmnFrappeSourcePorter(database: database, storage: storage); 

  final WmnDatabase database;
  final WmnMetaService meta;
  final WmnFrappeAppConverter converter;
  final WmnWorkspaceService workspaces;
  final WmnPageService pages;
  final WmnFrappeSourcePorter sourcePorter;
  final http.Client _http;
  static const Uuid _uuid = Uuid();

  static const int maxCompressedBytes = 250 * 1024 * 1024;
  static const int maxTextEntryBytes = 5 * 1024 * 1024;
  static const int maxArchiveEntries = 60000;

  Future<Uint8List> downloadGitHubZip({
    required String repositoryUrl,
    required String ref,
  }) async {
    final repo = _parseGitHubRepository(repositoryUrl);
    final branch = ref.trim().isEmpty ? 'develop' : ref.trim();
    final candidates = <Uri>[
      Uri.https('github.com', '/${repo.$1}/${repo.$2}/archive/refs/heads/$branch.zip'),
      Uri.https('github.com', '/${repo.$1}/${repo.$2}/archive/refs/tags/$branch.zip'),
    ];
    http.Response? last;
    for (final uri in candidates) {
      final response = await _http.get(uri, headers: const {'Accept': 'application/zip'});
      last = response;
      if (response.statusCode < 200 || response.statusCode >= 300) continue;
      if (response.bodyBytes.length > maxCompressedBytes) {
        throw StateError('App ZIP exceeds ${maxCompressedBytes ~/ (1024 * 1024)} MB safety limit.');
      }
      return response.bodyBytes;
    }
    throw StateError('GitHub download failed (${last?.statusCode ?? 'unknown'}). Check repository/ref.');
  }

  WmnFrappeAppConversionSummary convertZipBytes(
    List<int> bytes, {
    required String sourceName,
    String sourceKind = 'ZIP',
    String? sourceRef,
    String? appNameOverride,
  }) {
    if (bytes.isEmpty) throw StateError('Empty app ZIP.');
    if (bytes.length > maxCompressedBytes) {
      throw StateError('App ZIP exceeds ${maxCompressedBytes ~/ (1024 * 1024)} MB safety limit.');
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    if (archive.length > maxArchiveEntries) {
      throw StateError('App archive has too many entries (${archive.length}).');
    }

    final textFiles = <String, String>{};
    for (final entry in archive) {
      if (!entry.isFile || entry.size > maxTextEntryBytes || !_interestingTextPath(entry.name)) continue;
      final raw = entry.content;
      try {
        textFiles[_normalizePath(entry.name)] = utf8.decode(raw, allowMalformed: true);
      } catch (_) {}
    }
    if (textFiles.isEmpty) throw StateError('No Frappe app metadata was found in the ZIP.');

    final manifest = _detectManifest(
      textFiles,
      sourceName: sourceName,
      sourceRef: sourceRef,
      appNameOverride: appNameOverride,
    );
    converter.registerApp(
      appName: manifest.appName,
      title: manifest.appTitle,
      version: manifest.version,
      sourceFramework: 'FRAPPE',
      repository: manifest.repository,
      sourceRef: sourceRef,
      license: manifest.license,
      manifest: manifest.toJson(),
      modules: manifest.modules,
      status: 'IMPORTED',
    );
    _saveManifestDependencies(manifest);

    final runId = _uuid.v4();
    final started = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO wmn_app_conversion_runs(id,app_name,source_name,source_kind,source_ref,status,started_at)
      VALUES (?,?,?,?,?,'RUNNING',?);
    ''', [runId, manifest.appName, sourceName, sourceKind, sourceRef, started]);
    database.db.execute("DELETE FROM wmn_porting_tasks WHERE app_name = ? AND status = 'TODO';", [manifest.appName]);
    database.db.execute('BEGIN IMMEDIATE;');

    try {
      final messages = <String>[];
    final linkTargets = <String>{};
    var docTypes = 0;
    var workspaceCount = 0;
    var pageCount = 0;
    var placeholderCount = 0;

    final hooksPath = textFiles.keys.where((path) => path.endsWith('/hooks.py') || path == 'hooks.py').toList()
      ..sort((a, b) => a.length.compareTo(b.length));
    if (hooksPath.isNotEmpty) _scanHooks(manifest.appName, runId, hooksPath.first, textFiles[hooksPath.first]!);

    final jsonPaths = textFiles.keys.where((path) => path.endsWith('.json')).toList()..sort();
    for (final path in jsonPaths) {
      final text = textFiles[path]!;
      Object? decoded;
      try {
        decoded = jsonDecode(text);
      } catch (error) {
        _artifact(manifest.appName, runId, 'JSON', path, text, 'FAILED', notes: 'Invalid JSON: $error');
        continue;
      }

      if (decoded is List && _isFixturePath(path)) {
        _convertFixtureList(manifest.appName, runId, path, decoded, text);
        continue;
      }
      if (decoded is! Map) continue;
      final raw = _map(decoded);
      final doctypeMarker = '${raw['doctype'] ?? ''}';
      try {
        if (doctypeMarker == 'DocType' && raw['fields'] is List) {
          final result = converter.importDocTypeJson(text, sourceApp: manifest.appName);
          docTypes++;
          for (final field in result.doctype.fields) {
            if ((field.fieldType == 'Link' || field.fieldType == 'Table' || field.fieldType == 'Table MultiSelect') &&
                (field.options?.trim().isNotEmpty ?? false)) {
              linkTargets.add(field.options!.trim());
            }
          }
          _artifact(
            manifest.appName,
            runId,
            'DOCTYPE',
            path,
            text,
            'CONVERTED',
            targetType: 'DocType',
            targetName: result.doctype.name,
            notes: result.warnings.join('\n'),
          );
          if (result.warnings.isNotEmpty) messages.add('${result.doctype.name}: ${result.warnings.length} warning(s)');
          _scanSiblingController(manifest.appName, runId, path, textFiles, result.doctype.name);
          continue;
        }
        if (doctypeMarker == 'Workspace' || path.contains('/workspace/')) {
          final workspace = workspaces.importFrappeWorkspace(raw, sourceApp: manifest.appName, sourcePath: path);
          workspaceCount++;
          _artifact(manifest.appName, runId, 'WORKSPACE', path, text, 'CONVERTED', targetType: 'Workspace', targetName: workspace.name);
          continue;
        }
        if (doctypeMarker == 'Page' || path.contains('/page/')) {
          final page = pages.importFrappePage(
            raw,
            sourceApp: manifest.appName,
            sourcePath: path,
          );
          pageCount++;
          _artifact(
            manifest.appName,
            runId,
            'PAGE',
            path,
            text,
            'CONVERTED',
            targetType: 'Page',
            targetName: page.name,
            notes: page.controllerKey == null
                ? 'Frappe Page metadata converted to WMN Page.'
                : 'Page metadata converted. Any custom JavaScript controller is preserved for explicit WMN controller porting.',
          );
          continue;
        }
        if (doctypeMarker == 'Workspace Sidebar' || path.contains('/workspace_sidebar/')) {
          final workspaceName = '${raw['name'] ?? _workspaceNameFromPath(path)}';
          final workspace = workspaces.importFrappeSidebar(raw, sourceApp: manifest.appName, workspaceName: workspaceName, sourcePath: path);
          _artifact(manifest.appName, runId, 'WORKSPACE_SIDEBAR', path, text, 'CONVERTED', targetType: 'Workspace', targetName: workspace.name);
          continue;
        }
        if (doctypeMarker == 'Number Card' || path.contains('/number_card/')) {
          workspaces.saveNumberCard(raw, sourceApp: manifest.appName);
          final name = '${raw['name'] ?? raw['label'] ?? raw['number_card_name'] ?? ''}';
          _artifact(manifest.appName, runId, 'NUMBER_CARD', path, text, 'CONVERTED', targetType: 'Number Card', targetName: name);
          continue;
        }
        if (doctypeMarker == 'Dashboard Chart' || path.contains('/dashboard_chart/')) {
          workspaces.saveDashboardChart(raw, sourceApp: manifest.appName);
          final name = '${raw['name'] ?? raw['chart_name'] ?? ''}';
          _artifact(manifest.appName, runId, 'DASHBOARD_CHART', path, text, 'CONVERTED', targetType: 'Dashboard Chart', targetName: name);
          continue;
        }
        if (doctypeMarker == 'Report' || path.contains('/report/')) {
          _convertReportDefinition(manifest.appName, runId, path, raw, text, textFiles);
          continue;
        }
      } catch (error) {
        _artifact(manifest.appName, runId, 'JSON', path, text, 'FAILED', notes: '$error');
      }
    }

    for (final target in linkTargets.toList()..sort()) {
      if (_ignoreLinkTarget(target) || meta.doctype(target, includeFields: false) != null) continue;
      try {
        meta.saveDocType(
          name: target,
          module: 'Frappe Compatibility',
          titleField: 'name',
          autoname: 'field:name',
          metadata: {
            'source_framework': 'FRAPPE',
            'source_app': manifest.appName,
            'placeholder_dependency': true,
          },
        );
        meta.saveField(
          doctype: target,
          fieldName: 'name',
          label: target,
          fieldType: 'Data',
          required: true,
          inListView: true,
          searchable: true,
          index: 1,
          metadata: const {'placeholder_dependency': true},
        );
        placeholderCount++;
        final artifactId = _artifact(
          manifest.appName,
          runId,
          'DEPENDENCY_PLACEHOLDER',
          'dependency:$target',
          target,
          'NEEDS_PORT',
          targetType: 'DocType',
          targetName: target,
          notes: 'Referenced by imported Link/Table metadata but not provided by the app ZIP.',
        );
        _task(
          appName: manifest.appName,
          artifactId: artifactId,
          taskType: 'MISSING_DEPENDENCY',
          title: 'Port dependency DocType: $target',
          sourcePath: 'dependency:$target',
          priority: 'HIGH',
          details: {'doctype': target},
        );
      } catch (error) {
        messages.add('Dependency $target: $error');
      }
    }

    _scanAppLevelFiles(manifest.appName, runId, textFiles);
    _syncDiscoveredModules(manifest.appName);
    _syncApplicationNavigationManifest(manifest.appName);
    final counts = _runCounts(runId);
    final finalStatus = counts.failed > 0 ? 'PARTIAL' : counts.needsPort > 0 ? 'PARTIAL' : 'READY';
    final taskCount = _taskCount(manifest.appName);
    final sourceStats = _sourceStats(manifest.appName);
    database.db.execute('''
      UPDATE wmn_app_conversion_runs SET
        status=?,total_artifacts=?,converted_artifacts=?,porting_artifacts=?,failed_artifacts=?,summary_json=?,completed_at=?
      WHERE id=?;
    ''', [
      counts.failed > 0 ? 'PARTIAL' : 'COMPLETED',
      counts.total,
      counts.converted,
      counts.needsPort,
      counts.failed,
      jsonEncode({
        'doctypes': docTypes,
        'workspaces': workspaceCount,
        'pages': pageCount,
        'placeholder_doctypes': placeholderCount,
        'porting_tasks': taskCount,
        'source_units': sourceStats.total,
        'auto_converted_source_units': sourceStats.autoConverted,
        'review_source_units': sourceStats.review,
        'source_symbols': sourceStats.symbols,
      }),
      DateTime.now().toUtc().toIso8601String(),
      runId,
    ]);
    database.db.execute('UPDATE wmn_app_packages SET conversion_status=?,updated_at=? WHERE app_name=?;', [
      finalStatus,
      DateTime.now().toUtc().toIso8601String(),
      manifest.appName,
    ]);
    database.db.execute('COMMIT;');

      return WmnFrappeAppConversionSummary(
        runId: runId,
        manifest: manifest,
        totalArtifacts: counts.total,
        convertedArtifacts: counts.converted,
        needsPortArtifacts: counts.needsPort,
        ignoredArtifacts: counts.ignored,
        failedArtifacts: counts.failed,
        convertedDocTypes: docTypes,
        convertedWorkspaces: workspaceCount,
        convertedPages: pageCount,
        placeholderDocTypes: placeholderCount,
        portingTasks: taskCount,
        sourceUnits: sourceStats.total,
        autoConvertedSourceUnits: sourceStats.autoConverted,
        reviewSourceUnits: sourceStats.review,
        sourceSymbols: sourceStats.symbols,
        messages: List.unmodifiable(messages),
      );
    } catch (error) {
      try {
        database.db.execute('ROLLBACK;');
      } catch (_) {}
      final completed = DateTime.now().toUtc().toIso8601String();
      database.db.execute(
        "UPDATE wmn_app_conversion_runs SET status='FAILED',summary_json=?,completed_at=? WHERE id=?;",
        [jsonEncode({'error': '$error'}), completed, runId],
      );
      database.db.execute(
        "UPDATE wmn_app_packages SET conversion_status='FAILED',updated_at=? WHERE app_name=?;",
        [completed, manifest.appName],
      );
      rethrow;
    }
  }


  void _syncApplicationNavigationManifest(String appName) {
    final rows = database.db.select(
      'SELECT manifest_json FROM wmn_app_packages WHERE app_name=? LIMIT 1;',
      [appName],
    );
    if (rows.isEmpty) return;
    final rawManifest = rows.first['manifest_json']?.toString();
    Map<String, Object?> manifest = <String, Object?>{};
    if (rawManifest != null && rawManifest.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawManifest);
        if (decoded is Map) {
          manifest = <String, Object?>{
            for (final entry in decoded.entries) '${entry.key}': entry.value,
          };
        }
      } catch (_) {}
    }

    final appWorkspaces = workspaces
        .workspaces(includeHidden: true)
        .where((workspace) => workspace.appName == appName)
        .toList(growable: false)
      ..sort((left, right) {
        final order = left.sequenceId.compareTo(right.sequenceId);
        if (order != 0) return order;
        return left.label.toLowerCase().compareTo(right.label.toLowerCase());
      });

    final appPages = pages.applicationPages(appName);
    final routeDefinitions = <Map<String, Object?>>[];
    for (final workspace in appWorkspaces) {
      routeDefinitions.add(<String, Object?>{
        'path': '/apps/$appName/workspaces/${_routeSlug(workspace.name)}',
        'title': workspace.label,
        'target_type': 'workspace',
        'target': workspace.name,
        if (workspace.icon != null) 'icon': workspace.icon,
        'section': workspace.module,
        'order': workspace.sequenceId,
        'show_in_navigation': !workspace.isHidden,
        'required_roles': _workspaceRouteRoles(workspace.metadata),
      });
    }
    for (final page in appPages) {
      routeDefinitions.add(<String, Object?>{
        'path': page.route,
        'title': page.title,
        'target_type': 'page',
        'target': page.name,
        if (page.icon != null) 'icon': page.icon,
        'section': page.section ?? page.module,
        'order': page.order,
        'show_in_navigation': page.showInNavigation,
        'required_roles': page.roles,
        'required_permissions': page.permissions,
      });
    }

    manifest = <String, Object?>{
      ...manifest,
      'routes': routeDefinitions
          .map((route) => '${route['path']}')
          .toList(growable: false),
      'route_definitions': routeDefinitions,
      'workspaces': appWorkspaces
          .map((workspace) => workspace.name)
          .toList(growable: false),
      'pages': appPages.map((page) => page.name).toList(growable: false),
      'required_system_modules': <String>{
        ..._stringList(manifest['required_system_modules']),
        if (appWorkspaces.isNotEmpty) 'workspaces',
        if (appPages.isNotEmpty) 'ui',
      }.toList(growable: false),
      'required_capabilities': <String>{
        ..._stringList(manifest['required_capabilities']),
        if (appPages.isNotEmpty) 'page-runtime',
      }.toList(growable: false),
    };
    database.db.execute(
      'UPDATE wmn_app_packages SET manifest_json=?,updated_at=? WHERE app_name=?;',
      <Object?>[
        jsonEncode(manifest),
        DateTime.now().toUtc().toIso8601String(),
        appName,
      ],
    );
  }

  List<String> _workspaceRouteRoles(Map<String, Object?> metadata) {
    final result = <String>{};
    final raw = metadata['raw'];
    if (raw is Map) {
      final roles = raw['roles'];
      if (roles is List) {
        for (final entry in roles) {
          if (entry is Map) {
            final role = '${entry['role'] ?? entry['name'] ?? ''}'.trim();
            if (role.isNotEmpty) result.add(role);
          } else {
            final role = '$entry'.trim();
            if (role.isNotEmpty) result.add(role);
          }
        }
      }
    }
    return result.toList(growable: false)..sort();
  }

  List<String> _stringList(Object? value) => value is List
      ? value
          .map((entry) => '$entry'.trim())
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false)
      : const <String>[];

  String _routeSlug(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final digest = sha256.convert(utf8.encode(value)).toString().substring(0, 8);
    return normalized.isEmpty ? digest : '$normalized-$digest';
  }

  List<Map<String, Object?>> packages() => database.db
      .select('SELECT * FROM wmn_app_packages ORDER BY app_title COLLATE NOCASE, app_name;')
      .map((row) => Map<String, Object?>.from(row))
      .toList(growable: false);

  List<Map<String, Object?>> artifacts(String appName, {String? status}) {
    final where = status == null ? 'WHERE app_name = ?' : 'WHERE app_name = ? AND conversion_status = ?';
    final args = status == null ? <Object?>[appName] : <Object?>[appName, status];
    return database.db
        .select('SELECT * FROM wmn_app_artifacts $where ORDER BY conversion_status, artifact_type, source_path;', args)
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  List<Map<String, Object?>> portingTasks(String appName) => database.db
      .select('SELECT * FROM wmn_porting_tasks WHERE app_name = ? ORDER BY status, priority DESC, title;', [appName])
      .map((row) => Map<String, Object?>.from(row))
      .toList(growable: false);

  List<Map<String, Object?>> sourceUnits(String appName, {String? status}) => sourcePorter.sourceUnits(appName, status: status);

  Map<String, Object?>? sourceUnit(String id, {bool hydrate = true}) =>
      sourcePorter.sourceUnit(id, hydrate: hydrate);

  List<Map<String, Object?>> sourceSymbols(String sourceUnitId) => sourcePorter.symbols(sourceUnitId);

  int reanalyzeStoredSources(String appName) {
    final rows = database.db.select('''
      SELECT u.*,a.target_type,a.target_name
      FROM wmn_app_source_units u
      LEFT JOIN wmn_app_artifacts a ON a.id=u.artifact_id
      WHERE u.app_name=? AND u.language IN ('PYTHON','JAVASCRIPT')
      ORDER BY u.language,u.source_path;
    ''', [appName]);
    if (rows.isEmpty) return 0;
    var updated = 0;
    database.db.execute('BEGIN IMMEDIATE;');
    try {
      for (final row in rows) {
        final language = '${row['language'] ?? ''}';
        final sourcePath = '${row['source_path'] ?? ''}';
        final source = sourcePorter.readStoredSource(Map<String, Object?>.from(row));
        final targetType = '${row['target_type'] ?? ''}';
        final doctype = targetType == 'DocType' && row['target_name'] != null
            ? '${row['target_name']}'
            : null;
        final result = language == 'PYTHON'
            ? sourcePorter.analyzePython(source, doctype: doctype, sourcePath: sourcePath)
            : sourcePorter.analyzeJavaScript(source, doctype: doctype, sourcePath: sourcePath);
        sourcePorter.saveSourceUnit(
          appName: appName,
          sourcePath: sourcePath,
          source: source,
          result: result,
          artifactId: row['artifact_id'] as String?,
        );
        if (language == 'JAVASCRIPT' &&
            doctype != null &&
            result.convertedCode != null &&
            result.convertedCode!.contains('wmn.ui.form.on')) {
          _saveClientScriptCandidate(
            appName: appName,
            doctype: doctype,
            sourcePath: sourcePath,
            script: result.convertedCode!,
            name: '${result.status == 'AUTO_CONVERTED' ? 'Auto-converted' : 'Review'} • $appName • $doctype',
          );
        }
        if (language == 'PYTHON' &&
            doctype != null &&
            result.convertedCode != null &&
            result.convertedCode!.trim().isNotEmpty) {
          _saveDisabledServerScriptCandidates(
            appName: appName,
            doctype: doctype,
            sourcePath: sourcePath,
            convertedCode: result.convertedCode!,
            symbols: result.symbols,
          );
        }
        updated++;
      }
      database.db.execute('COMMIT;');
      return updated;
    } catch (_) {
      database.db.execute('ROLLBACK;');
      rethrow;
    }
  }

  WmnFrappeAppManifest _detectManifest(
    Map<String, String> files, {
    required String sourceName,
    String? sourceRef,
    String? appNameOverride,
  }) {
    final hooksPaths = <String>[
      for (final path in files.keys)
        if (path.endsWith('/hooks.py') || path == 'hooks.py') path,
    ]..sort((a, b) => a.length.compareTo(b.length));
    final hooks = hooksPaths.isEmpty ? '' : files[hooksPaths.first]!;
    final detectedName = _assignment(hooks, 'app_name') ?? _safeAppName(sourceName);
    final appName = appNameOverride?.trim().isNotEmpty == true ? appNameOverride!.trim() : detectedName;
    final title = _assignment(hooks, 'app_title') ?? _humanize(appName);
    final modulesPath = files.keys.where((path) => path.endsWith('/modules.txt')).toList();
    final modules = modulesPath.isEmpty
        ? <String>[]
        : files[modulesPath.first]!
            .split(RegExp(r'\r?\n'))
            .map((entry) => entry.trim())
            .where((entry) => entry.isNotEmpty && !entry.startsWith('#'))
            .toSet()
            .toList()
      ..sort();
    final initPaths = files.keys.where((path) => path.endsWith('/$appName/__init__.py') || path.endsWith('/__init__.py')).toList()
      ..sort((a, b) => a.length.compareTo(b.length));
    String? version;
    for (final path in initPaths) {
      version = _assignment(files[path]!, '__version__');
      if (version != null) break;
    }
    version ??= _assignment(hooks, 'develop_version');
    final pyprojectPaths = files.keys.where((path) => path.endsWith('/pyproject.toml') || path == 'pyproject.toml').toList()
      ..sort((a, b) => a.length.compareTo(b.length));
    final pyproject = pyprojectPaths.isEmpty ? '' : files[pyprojectPaths.first]!;
    final requiredApps = <String>{
      ..._stringListAssignment(hooks, 'required_apps'),
      ..._frappeDependencies(pyproject),
    }.toList()..sort();
    return WmnFrappeAppManifest(
      appName: appName,
      appTitle: title,
      version: version,
      repository: _assignment(hooks, 'source_link'),
      license: _assignment(hooks, 'app_license'),
      publisher: _assignment(hooks, 'app_publisher'),
      description: _assignment(hooks, 'app_description'),
      sourceRef: sourceRef,
      modules: modules,
      requiredApps: requiredApps,
    );
  }

  void _scanHooks(String appName, String runId, String path, String source) {
    final artifactId = _artifact(appName, runId, 'HOOKS', path, source, 'NEEDS_PORT', notes: 'hooks.py is parsed as metadata only; Python is never executed.');
    const hooks = <String, String>{
      'doc_events': 'DOCUMENT_EVENTS',
      'override_doctype_class': 'OVERRIDE_DOCTYPE_CLASS',
      'extend_doctype_class': 'EXTEND_DOCTYPE_CLASS',
      'override_whitelisted_methods': 'OVERRIDE_API',
      'scheduler_events': 'SCHEDULER',
      'permission_query_conditions': 'PERMISSION_QUERY',
      'has_permission': 'HAS_PERMISSION',
      'doctype_js': 'DOCTYPE_JS',
      'doctype_list_js': 'DOCTYPE_LIST_JS',
      'before_install': 'INSTALL_HOOK',
      'after_install': 'INSTALL_HOOK',
      'after_app_install': 'INSTALL_HOOK',
      'boot_session': 'BOOT_SESSION',
      'fixtures': 'FIXTURES',
      'jinja': 'JINJA',
    };
    for (final entry in hooks.entries) {
      if (!RegExp('(^|\\n)\\s*${RegExp.escape(entry.key)}\\s*=', multiLine: true).hasMatch(source)) continue;
      _task(
        appName: appName,
        artifactId: artifactId,
        taskType: entry.value,
        title: 'Port Frappe hook: ${entry.key}',
        sourcePath: path,
        priority: const {'DOCUMENT_EVENTS', 'PERMISSION_QUERY', 'HAS_PERMISSION', 'OVERRIDE_DOCTYPE_CLASS'}.contains(entry.value) ? 'HIGH' : 'MEDIUM',
        details: {'hook': entry.key},
      );
    }
  }

  void _scanSiblingController(
    String appName,
    String runId,
    String jsonPath,
    Map<String, String> files,
    String doctype,
  ) {
    final base = jsonPath.substring(0, jsonPath.length - 5);
    for (final extension in const ['.py', '.js']) {
      final path = '$base$extension';
      final source = files[path];
      if (source == null) continue;
      final type = extension == '.py' ? 'PYTHON_CONTROLLER' : 'DOCTYPE_JS';
      final artifactId = _artifact(appName, runId, type, path, source, 'NEEDS_PORT', targetType: 'DocType', targetName: doctype);
      _task(
        appName: appName,
        artifactId: artifactId,
        taskType: extension == '.py' ? 'PYTHON_CONTROLLER' : 'CLIENT_SCRIPT_PORT',
        title: '${extension == '.py' ? 'Port controller' : 'Review client script'}: $doctype',
        sourcePath: path,
        priority: extension == '.py' ? 'HIGH' : 'MEDIUM',
        details: {'doctype': doctype},
      );
      if (extension == '.js' && source.contains('frappe.ui.form.on')) {
        final port = sourcePorter.analyzeJavaScript(source, doctype: doctype, sourcePath: path);
        _saveClientScriptCandidate(
          appName: appName,
          doctype: doctype,
          sourcePath: path,
          script: port.convertedCode ?? source,
          name: '${port.status == 'AUTO_CONVERTED' ? 'Auto-converted' : 'Review'} • $appName • $doctype',
        );
      }
    }
  }

  void _convertReportDefinition(
    String appName,
    String runId,
    String path,
    Map<String, Object?> raw,
    String source,
    Map<String, String> files,
  ) {
    final name = '${raw['report_name'] ?? raw['name'] ?? _humanize(_basenameWithoutExtension(path))}'.trim();
    final reportType = '${raw['report_type'] ?? 'Report'}';
    final base = path.substring(0, path.length - 5);
    final js = files['$base.js'];
    final py = files['$base.py'];
    final filters = js == null ? const <Map<String, Object?>>[] : _extractFrappeReportFilters(js);
    final artifactId = _artifact(
      appName,
      runId,
      'REPORT',
      path,
      source,
      'NEEDS_PORT',
      targetType: reportType,
      targetName: name,
      notes: 'Report metadata and runtime filters were discovered. Frappe Python/SQL is not executed inside WMN.',
      metadata: {'runtime_filters': filters, 'reference_doctype': raw['ref_doctype']},
    );
    if (js != null) {
      _artifact(appName, runId, 'REPORT_JS', '$base.js', js, 'NEEDS_PORT', targetType: 'Report', targetName: name, metadata: {'runtime_filters': filters});
    }
    if (py != null) {
      _artifact(appName, runId, 'REPORT_PYTHON', '$base.py', py, 'NEEDS_PORT', targetType: 'Report', targetName: name);
    }
    _saveDisabledScriptReportStub(
      appName: appName,
      name: name,
      module: '${raw['module'] ?? 'Custom'}',
      referenceDocType: _nullable('${raw['ref_doctype'] ?? ''}'),
      reportType: reportType,
      filters: filters,
      sourcePath: path,
    );
    _task(
      appName: appName,
      artifactId: artifactId,
      taskType: 'REPORT_PORT',
      title: 'Port $reportType: $name',
      sourcePath: path,
      priority: 'MEDIUM',
      details: {'report_name': name, 'report_type': reportType, 'runtime_filters': filters},
    );
  }

  void _saveDisabledScriptReportStub({
    required String appName,
    required String name,
    required String module,
    required String reportType,
    required List<Map<String, Object?>> filters,
    required String sourcePath,
    String? referenceDocType,
  }) {
    final existing = database.db.select(
      'SELECT name FROM [tabReport] WHERE report_name = ? AND module = ? LIMIT 1;',
      [name, module],
    );
    final id = existing.isEmpty ? _uuid.v4() : existing.first['name'] as String;
    final now = DateTime.now().toUtc().toIso8601String();
    final normalizedType = const <String>{'Report Builder', 'Query Report', 'Script Report', 'Custom Report'}.contains(reportType)
        ? reportType
        : 'Script Report';
    database.db.execute('''
      INSERT INTO [tabReport](
        name,report_name,ref_doctype,report_type,module,is_standard,disabled,
        query_definition_json,script_key,filters_json,columns_json,metadata_json,
        created_at,updated_at,script_source_type,script_source_path,script_language
      ) VALUES (?,?,?,?,?,0,1,'{}',?,?,'[]',?,?,?,'NATIVE_HANDLER',NULL,NULL)
      ON CONFLICT(name) DO UPDATE SET
        report_name=excluded.report_name,ref_doctype=excluded.ref_doctype,
        report_type=excluded.report_type,module=excluded.module,disabled=1,
        script_key=excluded.script_key,filters_json=excluded.filters_json,
        metadata_json=excluded.metadata_json,updated_at=excluded.updated_at;
    ''', [
      id,
      name,
      referenceDocType,
      normalizedType,
      module.trim().isEmpty ? 'Custom' : module.trim(),
      name,
      jsonEncode(filters),
      jsonEncode(<String, Object?>{
        'imported_app': appName,
        'source_path': sourcePath,
        'original_report_type': reportType,
        'port_required': true,
      }),
      now,
      now,
    ]);
  }

  void _convertFixtureList(String appName, String runId, String path, List raw, String source) {
    var converted = 0;
    var needsPort = 0;
    for (final item in raw.whereType<Map>()) {
      final row = _map(item);
      final doctype = '${row['doctype'] ?? ''}';
      try {
        if (doctype == 'Custom Field') {
          _importCustomFieldFixture(row);
          converted++;
        } else if (doctype == 'Property Setter') {
          if (_importPropertySetterFixture(row)) {
            converted++;
          } else {
            needsPort++;
          }
        } else if (doctype == 'Client Script') {
          final target = '${row['dt'] ?? row['reference_doctype'] ?? ''}'.trim();
          final script = '${row['script'] ?? ''}';
          if (target.isNotEmpty && script.isNotEmpty) {
            _saveDisabledClientScript(appName: appName, doctype: target, sourcePath: path, script: script, name: '${row['name'] ?? 'Imported Client Script'}');
          }
          needsPort++;
        } else if (doctype == 'Server Script' || doctype == 'Workflow' || doctype == 'Print Format' || doctype == 'Report') {
          needsPort++;
          _task(
            appName: appName,
            taskType: 'FIXTURE_PORT',
            title: 'Port $doctype fixture: ${row['name'] ?? ''}',
            sourcePath: path,
            priority: doctype == 'Server Script' || doctype == 'Workflow' ? 'HIGH' : 'MEDIUM',
            details: row,
          );
        }
      } catch (_) {
        needsPort++;
      }
    }
    final status = needsPort > 0 ? 'NEEDS_PORT' : converted > 0 ? 'CONVERTED' : 'IGNORED';
    _artifact(appName, runId, 'FIXTURES', path, source, status, notes: '$converted fixture(s) converted; $needsPort require porting.');
  }

  void _importCustomFieldFixture(Map<String, Object?> row) {
    final target = '${row['dt'] ?? row['document_type'] ?? ''}'.trim();
    final fieldName = '${row['fieldname'] ?? row['field_name'] ?? ''}'.trim();
    if (target.isEmpty || fieldName.isEmpty || meta.doctype(target, includeFields: false) == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final fieldType = _customFieldType('${row['fieldtype'] ?? 'Data'}');
    final options = '${row['options'] ?? ''}'
        .split(RegExp(r'\r?\n'))
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    database.db.execute('''
      INSERT INTO custom_fields(
        id,document_type,field_name,label,field_type,insert_after,options_json,default_value_json,
        required,read_only,hidden,in_list_view,searchable,sort_order,enabled,created_at,updated_at
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(document_type,field_name) DO UPDATE SET
        label=excluded.label,field_type=excluded.field_type,insert_after=excluded.insert_after,options_json=excluded.options_json,
        default_value_json=excluded.default_value_json,required=excluded.required,read_only=excluded.read_only,
        hidden=excluded.hidden,in_list_view=excluded.in_list_view,searchable=excluded.searchable,updated_at=excluded.updated_at;
    ''', [
      _uuid.v4(),
      target,
      fieldName,
      '${row['label'] ?? _humanize(fieldName)}',
      fieldType,
      _nullable('${row['insert_after'] ?? ''}'),
      jsonEncode(options),
      row['default'] == null ? null : jsonEncode(row['default']),
      _truthy(row['reqd']) ? 1 : 0,
      _truthy(row['read_only']) ? 1 : 0,
      _truthy(row['hidden']) ? 1 : 0,
      _truthy(row['in_list_view']) ? 1 : 0,
      (_truthy(row['search_index']) || _truthy(row['in_global_search'])) ? 1 : 0,
      (row['idx'] as num?)?.toInt() ?? 0,
      1,
      now,
      now,
    ]);
  }

  bool _importPropertySetterFixture(Map<String, Object?> row) {
    final target = '${row['doc_type'] ?? row['doctype_or_field'] ?? ''}'.trim();
    final field = '${row['field_name'] ?? ''}'.trim();
    final property = _propertyName('${row['property'] ?? ''}');
    if (target.isEmpty || field.isEmpty || property == null || meta.doctype(target, includeFields: false) == null) return false;
    Object? value = row['value'];
    final type = '${row['property_type'] ?? ''}';
    if (type == 'Check') value = _truthy(value);
    if (type == 'Int') value = int.tryParse('$value') ?? value;
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO property_overrides(id,document_type,field_name,property_name,value_json,enabled,created_at,updated_at)
      VALUES (?,?,?,?,?,1,?,?)
      ON CONFLICT(document_type,field_name,property_name) DO UPDATE SET value_json=excluded.value_json,enabled=1,updated_at=excluded.updated_at;
    ''', [_uuid.v4(), target, field, property, jsonEncode(value), now, now]);
    return true;
  }

  void _saveDisabledClientScript({
    required String appName,
    required String doctype,
    required String sourcePath,
    required String script,
    String? name,
  }) {
    _saveClientScriptCandidate(
      appName: appName,
      doctype: doctype,
      sourcePath: sourcePath,
      script: script,
      name: name,
    );
  }

  void _saveClientScriptCandidate({
    required String appName,
    required String doctype,
    required String sourcePath,
    required String script,
    String? name,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    final scriptName = name ?? '$appName • $doctype • ${_basenameWithoutExtension(sourcePath)}';
    final existing = database.db.select('SELECT id FROM client_scripts WHERE name = ? LIMIT 1;', [scriptName]);
    final id = existing.isEmpty ? _uuid.v4() : existing.first['id'] as String;
    final storagePath = 'apps/${_storageSegment(appName)}/scripts/client/${_storageSegment(doctype)}/$id.js';
    sourcePorter.storage.writeText(storagePath, script);
    database.db.execute('''
      INSERT INTO client_scripts(id,name,document_type,source_storage_path,priority,enabled,created_at,updated_at)
      VALUES (?,?,?,?,0,?,?,?)
      ON CONFLICT(id) DO UPDATE SET document_type=excluded.document_type,source_storage_path=excluded.source_storage_path,enabled=excluded.enabled,updated_at=excluded.updated_at;
    ''', [id, scriptName, doctype, storagePath, 0, now, now]);
  }

  void _scanAppLevelFiles(String appName, String runId, Map<String, String> files) {
    for (final entry in files.entries) {
      final path = entry.key;
      if (database.db.select(
        'SELECT 1 FROM wmn_app_artifacts WHERE app_name=? AND run_id=? AND source_path=? LIMIT 1;',
        [appName, runId, path],
      ).isNotEmpty) {
        continue;
      }
      final lower = path.toLowerCase();
      final source = entry.value;
      if (lower.endsWith('/modules.txt') || lower.endsWith('/__init__.py') || lower.endsWith('/pyproject.toml')) {
        _artifact(appName, runId, 'APP_METADATA', path, source, 'CONVERTED');
        continue;
      }
      if (lower.endsWith('/readme.md') || lower.endsWith('/license') || lower.endsWith('/license.md') || lower.endsWith('/changelog.md')) {
        _artifact(appName, runId, 'DOCUMENTATION', path, source, 'IGNORED', notes: 'Documentation/license file preserved in the source package; no runtime conversion is required.');
        continue;
      }
      if (lower.endsWith('/patches.txt')) {
        final artifactId = _artifact(appName, runId, 'PATCHES', path, source, 'NEEDS_PORT', notes: 'Frappe database patches cannot execute in WMN. Review for data/schema migrations.');
        _task(appName: appName, artifactId: artifactId, taskType: 'PATCH_PORT', title: 'Review Frappe patches', sourcePath: path, priority: 'HIGH');
        continue;
      }
      if (lower.endsWith('.py')) {
        final artifactId = _artifact(appName, runId, 'PYTHON_MODULE', path, source, 'NEEDS_PORT', notes: 'Python is inventory-only and is never executed by WMN.');
        _task(
          appName: appName,
          artifactId: artifactId,
          taskType: 'PYTHON_MODULE_PORT',
          title: 'Port Python module: ${_basenameWithoutExtension(path)}',
          sourcePath: path,
          priority: _pythonPriority(lower),
        );
        continue;
      }
      if (lower.endsWith('.js')) {
        final artifactId = _artifact(appName, runId, 'JAVASCRIPT_MODULE', path, source, 'NEEDS_PORT', notes: 'JavaScript behavior is preserved and analyzed for WMN compatibility; browser/Frappe globals are never executed directly.');
        _task(
          appName: appName,
          artifactId: artifactId,
          taskType: 'JAVASCRIPT_MODULE_PORT',
          title: 'Review JavaScript module: ${_basenameWithoutExtension(path)}',
          sourcePath: path,
          priority: source.contains('frappe.') || source.contains('cur_frm') ? 'MEDIUM' : 'LOW',
        );
        continue;
      }
      if (lower.endsWith('.ts') || lower.endsWith('.tsx') || lower.endsWith('.jsx') || lower.endsWith('.vue')) {
        final artifactId = _artifact(appName, runId, 'FRONTEND_SOURCE', path, source, 'NEEDS_PORT', notes: 'Frontend source is preserved for WMN Flutter/UI porting.');
        _task(
          appName: appName,
          artifactId: artifactId,
          taskType: 'FRONTEND_SOURCE_PORT',
          title: 'Port frontend source: ${_basenameWithoutExtension(path)}',
          sourcePath: path,
          priority: 'MEDIUM',
        );
        continue;
      }
      if (lower.endsWith('.html')) {
        final dynamicTemplate = source.contains('{{') || source.contains('{%') || source.contains('frappe.');
        final artifactId = _artifact(
          appName,
          runId,
          'HTML_TEMPLATE',
          path,
          source,
          dynamicTemplate ? 'NEEDS_PORT' : 'IGNORED',
          notes: dynamicTemplate ? 'Jinja/Frappe HTML template preserved for WMN template conversion.' : 'Static HTML preserved; no runtime conversion required.',
        );
        if (dynamicTemplate) {
          _task(
            appName: appName,
            artifactId: artifactId,
            taskType: 'TEMPLATE_PORT',
            title: 'Port Jinja/HTML template: ${_basenameWithoutExtension(path)}',
            sourcePath: path,
            priority: 'LOW',
          );
        }
        continue;
      }
      if (lower.endsWith('.sql')) {
        final artifactId = _artifact(appName, runId, 'SQL_SOURCE', path, source, 'NEEDS_PORT', notes: 'SQL is preserved for analysis only and is never executed directly by WMN.');
        _task(
          appName: appName,
          artifactId: artifactId,
          taskType: 'SQL_PORT',
          title: 'Port SQL query: ${_basenameWithoutExtension(path)}',
          sourcePath: path,
          priority: 'HIGH',
        );
        continue;
      }
      if (lower.endsWith('.css') || lower.endsWith('.scss')) {
        _artifact(appName, runId, 'STYLE_SOURCE', path, source, 'IGNORED', notes: 'Web styling is preserved as reference; WMN uses Flutter widgets/themes.');
        continue;
      }
      if (lower.endsWith('.json')) {
        String? marker;
        try {
          final decoded = jsonDecode(source);
          if (decoded is Map) marker = '${decoded['doctype'] ?? ''}'.trim();
        } catch (_) {}
        final artifactId = _artifact(
          appName,
          runId,
          marker?.isNotEmpty == true ? 'FRAPPE_RECORD' : 'JSON_METADATA',
          path,
          source,
          marker?.isNotEmpty == true ? 'NEEDS_PORT' : 'IGNORED',
          notes: marker?.isNotEmpty == true ? 'Unsupported Frappe record type: $marker' : 'Unrecognized JSON metadata retained in the conversion inventory.',
          metadata: marker?.isNotEmpty == true ? {'doctype': marker} : const {},
        );
        if (marker?.isNotEmpty == true) {
          _task(
            appName: appName,
            artifactId: artifactId,
            taskType: 'FRAPPE_RECORD_PORT',
            title: 'Port Frappe record: $marker',
            sourcePath: path,
            priority: const {'Workflow', 'Server Script', 'Print Format', 'Web Form', 'Page'}.contains(marker) ? 'HIGH' : 'MEDIUM',
            details: {'doctype': marker},
          );
        }
        continue;
      }
      _artifact(appName, runId, 'SOURCE_METADATA', path, source, 'IGNORED');
    }
  }

  void _saveManifestDependencies(WmnFrappeAppManifest manifest) {
    final now = DateTime.now().toUtc().toIso8601String();
    for (final dependency in manifest.requiredApps) {
      final name = dependency.trim();
      if (name.isEmpty) continue;
      final resolved = database.db.select('SELECT 1 FROM wmn_app_packages WHERE app_name=? LIMIT 1;', [name]).isNotEmpty;
      database.db.execute('''
        INSERT INTO wmn_app_dependencies(app_name,dependency_name,dependency_kind,source_path,required,resolved,metadata_json,updated_at)
        VALUES (?,?,'APP','hooks.py',1,?,'{}',?)
        ON CONFLICT(app_name,dependency_name,dependency_kind) DO UPDATE SET resolved=excluded.resolved,updated_at=excluded.updated_at;
      ''', [manifest.appName, name, resolved ? 1 : 0, now]);
    }
    database.db.execute('''
      UPDATE wmn_app_dependencies SET resolved=1,updated_at=?
      WHERE dependency_kind='APP' AND dependency_name IN (SELECT app_name FROM wmn_app_packages);
    ''', [now]);
  }

  void _syncDiscoveredModules(String appName) {
    final names = <String>{};
    for (final row in database.db.select('SELECT module,metadata_json FROM wmn_doctypes WHERE module IS NOT NULL;')) {
      try {
        final raw = jsonDecode('${row['metadata_json'] ?? '{}'}');
        if (raw is Map && '${raw['source_app'] ?? ''}' == appName) names.add('${row['module'] ?? ''}'.trim());
      } catch (_) {}
    }
    for (final row in database.db.select('SELECT module FROM [tabWorkspace] WHERE app_name = ?;', [appName])) {
      names.add('${row['module'] ?? ''}'.trim());
    }
    for (final row in database.db.select('SELECT module FROM [tabPage] WHERE app_name = ?;', [appName])) {
      names.add('${row['module'] ?? ''}'.trim());
    }
    final now = DateTime.now().toUtc().toIso8601String();
    var sequence = 10.0;
    for (final name in names.where((entry) => entry.isNotEmpty).toList()..sort()) {
      database.db.execute('''
        INSERT INTO wmn_modules(name,label,app_name,sequence_id,enabled,metadata_json,created_at,updated_at)
        VALUES (?,?,?,?,1,?,?,?)
        ON CONFLICT(name) DO UPDATE SET app_name=excluded.app_name,label=excluded.label,updated_at=excluded.updated_at;
      ''', [name, name, appName, sequence, jsonEncode({'source_framework': 'FRAPPE'}), now, now]);
      sequence += 10;
    }
  }

  String _pythonPriority(String path) {
    if (path.endsWith('/install.py') || path.endsWith('/setup.py') || path.contains('/patches/')) return 'HIGH';
    if (path.contains('/api/') || path.contains('/integrations/') || path.contains('/overrides/')) return 'HIGH';
    return 'MEDIUM';
  }

  String _artifact(
    String appName,
    String runId,
    String type,
    String path,
    String source,
    String status, {
    String? targetType,
    String? targetName,
    String? notes,
    Map<String, Object?> metadata = const {},
  }) {
    final existing = database.db.select(
      'SELECT id FROM wmn_app_artifacts WHERE app_name=? AND source_path=? AND artifact_type=? LIMIT 1;',
      [appName, path, type],
    );
    final id = existing.isEmpty ? _uuid.v4() : existing.first['id'] as String;
    database.db.execute('''
      INSERT INTO wmn_app_artifacts(
        id,app_name,run_id,artifact_type,source_path,source_hash,target_type,target_name,conversion_status,notes,metadata_json,created_at
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(app_name,source_path,artifact_type) DO UPDATE SET
        run_id=excluded.run_id,source_hash=excluded.source_hash,target_type=excluded.target_type,target_name=excluded.target_name,
        conversion_status=excluded.conversion_status,notes=excluded.notes,metadata_json=excluded.metadata_json,created_at=excluded.created_at;
    ''', [
      id,
      appName,
      runId,
      type,
      path,
      sha256.convert(utf8.encode(source)).toString(),
      targetType,
      targetName,
      status,
      notes,
      jsonEncode(metadata),
      DateTime.now().toUtc().toIso8601String(),
    ]);
    _analyzeAndPreserveSource(
      appName: appName,
      artifactId: id,
      type: type,
      path: path,
      source: source,
      targetType: targetType,
      targetName: targetName,
    );
    return id;
  }

  void _analyzeAndPreserveSource({
    required String appName,
    required String artifactId,
    required String type,
    required String path,
    required String source,
    String? targetType,
    String? targetName,
  }) {
    final lower = path.toLowerCase();
    WmnSourcePortResult? result;
    if (lower.endsWith('.py') || type.contains('PYTHON') || type == 'HOOKS') {
      result = sourcePorter.analyzePython(
        source,
        doctype: targetType == 'DocType' ? targetName : null,
        sourcePath: path,
      );
    } else if (lower.endsWith('.js') || type.contains('JAVASCRIPT') || type == 'DOCTYPE_JS' || type == 'REPORT_JS') {
      result = sourcePorter.analyzeJavaScript(
        source,
        doctype: targetType == 'DocType' ? targetName : null,
        sourcePath: path,
      );
    } else if (lower.endsWith('.ts') || lower.endsWith('.tsx') || lower.endsWith('.jsx') || lower.endsWith('.vue')) {
      result = WmnSourcePortResult(
        language: lower.endsWith('.ts') || lower.endsWith('.tsx') ? 'TYPESCRIPT' : 'JAVASCRIPT',
        status: 'NEEDS_PORT',
        strategy: 'FRONTEND_TO_FLUTTER_PORT',
        confidence: 0.15,
        convertedCode: null,
        diagnostics: const ['Frontend framework source must be redesigned as Flutter/WMN UI; original source is preserved.'],
        dependencies: const [],
        symbols: const [],
      );
    } else if (lower.endsWith('.html')) {
      result = WmnSourcePortResult(
        language: 'HTML',
        status: source.contains('{{') || source.contains('{%') || source.contains('frappe.') ? 'NEEDS_PORT' : 'IGNORED',
        strategy: 'TEMPLATE_REFERENCE',
        confidence: 0.2,
        convertedCode: null,
        diagnostics: const ['HTML/Jinja source is retained as a reference for WMN print/web template conversion.'],
        dependencies: const [],
        symbols: const [],
      );
    } else if (lower.endsWith('.sql')) {
      result = const WmnSourcePortResult(
        language: 'SQL',
        status: 'NEEDS_PORT',
        strategy: 'SQL_TO_WMN_QUERY_PORT',
        confidence: 0.1,
        convertedCode: null,
        diagnostics: ['Raw SQL is never executed automatically. Convert it to WMN repositories/report queries with parameters and permission checks.'],
        dependencies: [],
        symbols: [],
      );
    } else if (lower.endsWith('.css') || lower.endsWith('.scss')) {
      result = const WmnSourcePortResult(
        language: 'CSS',
        status: 'IGNORED',
        strategy: 'STYLE_REFERENCE',
        confidence: 0.1,
        convertedCode: null,
        diagnostics: ['Web styling is preserved as a visual reference; WMN uses Flutter themes/widgets.'],
        dependencies: [],
        symbols: [],
      );
    }
    if (result == null) return;
    sourcePorter.saveSourceUnit(
      appName: appName,
      sourcePath: path,
      source: source,
      result: result,
      artifactId: artifactId,
    );
    if (result.language == 'PYTHON' &&
        targetType == 'DocType' &&
        targetName != null &&
        result.convertedCode != null &&
        result.convertedCode!.trim().isNotEmpty) {
      _saveDisabledServerScriptCandidates(
        appName: appName,
        doctype: targetName,
        sourcePath: path,
        convertedCode: result.convertedCode!,
        symbols: result.symbols,
      );
    }
  }

  void _saveDisabledServerScriptCandidates({
    required String appName,
    required String doctype,
    required String sourcePath,
    required String convertedCode,
    required List<WmnSourceSymbol> symbols,
  }) {
    final autoEvents = symbols
        .where((symbol) => symbol.status == 'AUTO_CONVERTED' && symbol.lifecycleEvent != null)
        .map((symbol) => symbol.lifecycleEvent!)
        .toSet()
        .toList(growable: false)
      ..sort();
    if (autoEvents.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    for (final event in autoEvents) {
      final name = 'Auto-port • $appName • $doctype • $event';
      final existing = database.db.select(
        "SELECT id FROM server_scripts WHERE script_type='DOCUMENT_EVENT' AND name=? LIMIT 1;",
        [name],
      );
      final id = existing.isEmpty ? _uuid.v4() : existing.first['id'] as String;
      final storagePath = 'apps/${_storageSegment(appName)}/scripts/server/${_storageSegment(doctype)}/${_storageSegment(event)}/$id.wmn';
      sourcePorter.storage.writeText(storagePath, convertedCode);
      database.db.execute('''
        INSERT INTO server_scripts(
          id,name,script_type,document_type,event_name,api_method,source_storage_path,priority,enabled,created_at,updated_at
        ) VALUES (?,?, 'DOCUMENT_EVENT', ?, ?, NULL, ?, 0, 0, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          document_type=excluded.document_type,event_name=excluded.event_name,source_storage_path=excluded.source_storage_path,
          enabled=0,updated_at=excluded.updated_at;
      ''', [id, name, doctype, event, storagePath, now, now]);
      final artifactRows = database.db.select(
        'SELECT id FROM wmn_app_artifacts WHERE app_name=? AND source_path=? ORDER BY created_at DESC LIMIT 1;',
        [appName, sourcePath],
      );
      if (artifactRows.isNotEmpty) {
        _task(
          appName: appName,
          artifactId: artifactRows.first['id'] as String,
          taskType: 'SERVER_SCRIPT_REVIEW',
          title: 'Review auto-ported server event: $doctype.$event',
          sourcePath: sourcePath,
          priority: 'MEDIUM',
          details: {
            'doctype': doctype,
            'event': event,
            'generated_server_script': name,
            'disabled_by_default': true,
          },
        );
      }
    }
  }

  ({int total, int autoConverted, int review, int needsPort, int symbols}) _sourceStats(String appName) {
    int count(String where, [List<Object?> args = const []]) {
      final rows = database.db.select('SELECT COUNT(*) AS value FROM wmn_app_source_units WHERE app_name=? AND $where;', [appName, ...args]);
      return rows.isEmpty ? 0 : (rows.first['value'] as int? ?? 0);
    }
    final symbolRows = database.db.select('''
      SELECT COUNT(*) AS value FROM wmn_porting_symbols s
      INNER JOIN wmn_app_source_units u ON u.id=s.source_unit_id
      WHERE u.app_name=?;
    ''', [appName]);
    return (
      total: count('1=1'),
      autoConverted: count('conversion_status=?', ['AUTO_CONVERTED']),
      review: count('conversion_status=?', ['REVIEW']),
      needsPort: count('conversion_status=?', ['NEEDS_PORT']),
      symbols: symbolRows.isEmpty ? 0 : (symbolRows.first['value'] as int? ?? 0),
    );
  }

  void _task({
    required String appName,
    String? artifactId,
    required String taskType,
    required String title,
    String? sourcePath,
    String priority = 'MEDIUM',
    Map<String, Object?> details = const {},
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO wmn_porting_tasks(id,app_name,artifact_id,task_type,title,source_path,priority,status,details_json,created_at,updated_at)
      VALUES (?,?,?,?,?,?,?,'TODO',?,?,?);
    ''', [_uuid.v4(), appName, artifactId, taskType, title, sourcePath, priority, jsonEncode(details), now, now]);
  }

  ({int total, int converted, int needsPort, int ignored, int failed}) _runCounts(String runId) {
    int count(String status) {
      final rows = database.db.select('SELECT COUNT(*) AS value FROM wmn_app_artifacts WHERE run_id=? AND conversion_status=?;', [runId, status]);
      return rows.isEmpty ? 0 : rows.first['value'] as int? ?? 0;
    }
    final converted = count('CONVERTED');
    final needsPort = count('NEEDS_PORT');
    final ignored = count('IGNORED');
    final failed = count('FAILED');
    return (total: converted + needsPort + ignored + failed, converted: converted, needsPort: needsPort, ignored: ignored, failed: failed);
  }

  int _taskCount(String appName) {
    final rows = database.db.select("SELECT COUNT(*) AS value FROM wmn_porting_tasks WHERE app_name=? AND status != 'IGNORED';", [appName]);
    return rows.isEmpty ? 0 : rows.first['value'] as int? ?? 0;
  }

  List<Map<String, Object?>> _extractFrappeReportFilters(String js) {
    final result = <Map<String, Object?>>[];
    final blocks = RegExp(r'''\{[^{}]{0,1600}?fieldname\s*:\s*['"]([^'"]+)['"][^{}]{0,1600}?\}''', multiLine: true, dotAll: true);
    for (final match in blocks.allMatches(js)) {
      final block = match.group(0)!;
      final fieldName = match.group(1)!;
      String? pick(String key) => RegExp('''${RegExp.escape(key)}\\s*:\\s*['"]([^'"]*)['"]''', multiLine: true).firstMatch(block)?.group(1);
      final reqdMatch = RegExp(r'reqd\s*:\s*(1|true)', caseSensitive: false).hasMatch(block);
      result.add({
        'fieldname': fieldName,
        'label': pick('label') ?? _humanize(fieldName),
        'fieldtype': pick('fieldtype') ?? 'Data',
        'options': pick('options'),
        'default': pick('default'),
        'reqd': reqdMatch,
      });
      if (result.length >= 50) break;
    }
    return result;
  }

  String _customFieldType(String frappeType) => switch (frappeType) {
        'Int' => 'INT',
        'Float' || 'Percent' || 'Duration' => 'FLOAT',
        'Currency' => 'CURRENCY',
        'Check' => 'CHECK',
        'Select' => 'SELECT',
        'Date' => 'DATE',
        'Datetime' => 'DATETIME',
        'Link' || 'Dynamic Link' => 'LINK',
        'JSON' => 'JSON',
        'Text' || 'Small Text' || 'Long Text' || 'Text Editor' || 'Code' || 'HTML' => 'TEXT',
        _ => 'DATA',
      };

  String? _propertyName(String frappeProperty) => switch (frappeProperty) {
        'label' => 'label',
        'reqd' => 'required',
        'read_only' => 'read_only',
        'hidden' => 'hidden',
        'default' => 'default',
        'options' => 'options',
        'in_list_view' => 'in_list_view',
        'search_index' || 'in_global_search' => 'searchable',
        _ => null,
      };

  (String, String) _parseGitHubRepository(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'https' || !const {'github.com', 'www.github.com'}.contains(uri.host.toLowerCase())) {
      throw StateError('Only HTTPS github.com repository URLs are supported.');
    }
    final parts = uri.pathSegments.where((entry) => entry.isNotEmpty).toList();
    if (parts.length < 2 || !_safeRepoPart(parts[0]) || !_safeRepoPart(parts[1].replaceAll('.git', ''))) {
      throw StateError('Invalid GitHub repository URL.');
    }
    return (parts[0], parts[1].replaceAll('.git', ''));
  }

  bool _interestingTextPath(String path) {
    final normalized = _normalizePath(path).toLowerCase();
    return normalized.endsWith('.json') ||
        normalized.endsWith('.py') ||
        normalized.endsWith('.js') ||
        normalized.endsWith('.ts') ||
        normalized.endsWith('.tsx') ||
        normalized.endsWith('.jsx') ||
        normalized.endsWith('.vue') ||
        normalized.endsWith('.html') ||
        normalized.endsWith('.css') ||
        normalized.endsWith('.scss') ||
        normalized.endsWith('.sql') ||
        normalized.endsWith('.yaml') ||
        normalized.endsWith('.yml') ||
        normalized.endsWith('.txt') ||
        normalized.endsWith('.toml') ||
        normalized.endsWith('.md');
  }

  bool _isFixturePath(String path) => path.contains('/fixtures/') || path.endsWith('/fixtures.json');
  bool _ignoreLinkTarget(String value) => value.isEmpty || value.startsWith('eval:') || value.contains('\n') || value.contains(',') || value.contains('.');
  bool _safeRepoPart(String value) => RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(value);
  String _normalizePath(String path) => path.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), '');
  String _workspaceNameFromPath(String path) => _humanize(_basenameWithoutExtension(path));
  String _storageSegment(String value) {
    final safe = value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9._-]+'), '_');
    return safe.replaceAll(RegExp(r'^[_\.]+|[_\.]+$'), '').isEmpty ? 'custom' : safe.replaceAll(RegExp(r'^[_\.]+|[_\.]+$'), '');
  }

  String _basenameWithoutExtension(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }

  String _safeAppName(String sourceName) {
    final base = _basenameWithoutExtension(sourceName).replaceAll(RegExp(r'-(develop|version-[0-9]+|v?[0-9].*)$'), '');
    final safe = base.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
    return safe.isEmpty ? 'frappe_app' : safe;
  }

  String? _assignment(String source, String key) {
    final escaped = RegExp.escape(key);
    final single = RegExp("^\\s*$escaped\\s*=\\s*'(.*?)'", multiLine: true).firstMatch(source);
    if (single != null) return single.group(1)?.trim();
    final double = RegExp('^\\s*$escaped\\s*=\\s*"(.*?)"', multiLine: true).firstMatch(source);
    return double?.group(1)?.trim();
  }

  List<String> _frappeDependencies(String source) {
    if (source.trim().isEmpty) return const [];
    final lines = source.split(RegExp(r'\r?\n'));
    var inSection = false;
    final result = <String>[];
    for (final raw in lines) {
      final line = raw.trim();
      if (line.startsWith('[')) {
        inSection = line == '[tool.bench.frappe-dependencies]';
        continue;
      }
      if (!inSection || line.isEmpty || line.startsWith('#')) continue;
      final match = RegExp(r'^([A-Za-z0-9_.-]+)\s*=').firstMatch(line);
      if (match != null) result.add(match.group(1)!);
    }
    return result.toSet().toList(growable: false);
  }

  List<String> _stringListAssignment(String source, String key) {
    final match = RegExp('^\\s*${RegExp.escape(key)}\\s*=\\s*\\[([\\s\\S]*?)\\]', multiLine: true).firstMatch(source);
    if (match == null) return const [];
    return RegExp(r'''['"]([^'"]+)['"]''')
        .allMatches(match.group(1)!)
        .map((entry) => entry.group(1)!.trim())
        .where((entry) => entry.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  Map<String, Object?> _map(Map raw) => {for (final entry in raw.entries) '${entry.key}': _normalize(entry.value)};
  Object? _normalize(Object? value) {
    if (value is Map) return _map(value);
    if (value is List) return value.map(_normalize).toList(growable: false);
    return value;
  }

  String _humanize(String value) => value
      .replaceAll('_', ' ')
      .split(RegExp(r'\s+'))
      .where((entry) => entry.isNotEmpty)
      .map((entry) => '${entry[0].toUpperCase()}${entry.substring(1)}')
      .join(' ');

  String? _nullable(String? value) => value == null || value.trim().isEmpty ? null : value.trim();
  bool _truthy(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return const {'1', 'true', 'yes', 'on'}.contains('${value ?? ''}'.toLowerCase());
  }
}
