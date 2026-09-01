import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/database/wmn_database.dart';
import '../../platform/storage/wmn_storage_service.dart';

class WmnSourceSymbol {
  const WmnSourceSymbol({
    required this.type,
    required this.name,
    required this.lineStart,
    required this.lineEnd,
    this.lifecycleEvent,
    this.targetKind,
    this.targetName,
    required this.status,
    required this.confidence,
    this.details = const {},
  });

  final String type;
  final String name;
  final int lineStart;
  final int lineEnd;
  final String? lifecycleEvent;
  final String? targetKind;
  final String? targetName;
  final String status;
  final double confidence;
  final Map<String, Object?> details;
}

class WmnSourcePortResult {
  const WmnSourcePortResult({
    required this.language,
    required this.status,
    required this.strategy,
    required this.confidence,
    required this.convertedCode,
    required this.diagnostics,
    required this.dependencies,
    required this.symbols,
  });

  final String language;
  final String status;
  final String strategy;
  final double confidence;
  final String? convertedCode;
  final List<String> diagnostics;
  final List<String> dependencies;
  final List<WmnSourceSymbol> symbols;
}

class WmnFrappeSourcePorter {
  WmnFrappeSourcePorter({required this.database, WmnStorageService? storage})
      : storage = storage ?? WmnStorageService.forDatabase(database);

  final WmnDatabase database;
  final WmnStorageService storage;
  static const Uuid _uuid = Uuid();

  static const Set<String> _documentEvents = {
    'autoname',
    'before_insert',
    'before_validate',
    'validate',
    'before_save',
    'after_insert',
    'on_update',
    'before_submit',
    'on_submit',
    'before_cancel',
    'on_cancel',
    'on_trash',
    'after_delete',
  };

  WmnSourcePortResult analyzePython(
    String source, {
    String? doctype,
    required String sourcePath,
  }) {
    final lines = source.split(RegExp(r'\r?\n'));
    final symbols = <WmnSourceSymbol>[];
    final diagnostics = <String>[];
    final dependencies = <String>{};
    final convertedHooks = <String>[];

    final importPattern = RegExp(r'^\s*(?:from\s+([A-Za-z0-9_.]+)\s+import|import\s+([A-Za-z0-9_., ]+))');
    for (final line in lines) {
      final match = importPattern.firstMatch(line);
      if (match == null) continue;
      final first = match.group(1);
      if (first != null) {
        dependencies.add(first.split('.').first);
      } else {
        for (final name in (match.group(2) ?? '').split(',')) {
          final value = name.trim().split(' ').first;
          if (value.isNotEmpty) dependencies.add(value.split('.').first);
        }
      }
    }

    final functionPattern = RegExp(r'^(\s*)(?:async\s+)?def\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*:');
    var i = 0;
    while (i < lines.length) {
      final match = functionPattern.firstMatch(lines[i]);
      if (match == null) {
        i++;
        continue;
      }
      final indent = match.group(1)!.length;
      final name = match.group(2)!;
      final start = i;
      var end = i;
      for (var j = i + 1; j < lines.length; j++) {
        final candidate = lines[j];
        if (candidate.trim().isEmpty || candidate.trimLeft().startsWith('#')) {
          end = j;
          continue;
        }
        final leading = candidate.length - candidate.trimLeft().length;
        if (leading <= indent && (functionPattern.hasMatch(candidate) || candidate.trimLeft().startsWith('class '))) break;
        end = j;
      }
      final body = lines.sublist(start + 1, end + 1).join('\n');
      final decorators = _decoratorsBefore(lines, start, indent);
      final whitelisted = decorators.any((value) => value.contains('frappe.whitelist'));
      final lifecycle = _documentEvents.contains(name) ? name : null;
      final analysis = _analyzePythonBody(body);
      String status = 'NEEDS_PORT';
      double confidence = 0.25;
      String? converted;
      if (lifecycle != null && doctype != null && analysis.safeForAutomaticPort) {
        converted = _convertSimplePythonLifecycle(body, doctype: doctype, event: lifecycle);
        if (converted != null) {
          status = 'AUTO_CONVERTED';
          confidence = 0.86;
          convertedHooks.add(converted);
        }
      } else if ((lifecycle != null || whitelisted) && !analysis.hasCriticalEngineBehavior) {
        status = 'REVIEW';
        confidence = 0.55;
      }
      if (analysis.hasCriticalEngineBehavior) {
        status = 'NEEDS_PORT';
        confidence = 0.15;
      }
      symbols.add(WmnSourceSymbol(
        type: lifecycle != null ? 'DOCUMENT_EVENT' : whitelisted ? 'WHITELISTED_API' : 'FUNCTION',
        name: name,
        lineStart: start + 1,
        lineEnd: end + 1,
        lifecycleEvent: lifecycle,
        targetKind: lifecycle != null ? 'SERVER_SCRIPT' : whitelisted ? 'WMN_API' : null,
        targetName: doctype,
        status: status,
        confidence: confidence,
        details: {
          'whitelisted': whitelisted,
          'uses_db_read': analysis.usesDbRead,
          'uses_db_write': analysis.usesDbWrite,
          'uses_raw_sql': analysis.usesRawSql,
          'uses_background_jobs': analysis.usesBackgroundJobs,
          'critical_engine_behavior': analysis.hasCriticalEngineBehavior,
        },
      ));
      i = end + 1;
    }

    final hasCritical = symbols.any((symbol) => symbol.details['critical_engine_behavior'] == true);
    final autoCount = symbols.where((symbol) => symbol.status == 'AUTO_CONVERTED').length;
    final reviewCount = symbols.where((symbol) => symbol.status == 'REVIEW').length;
    final needsCount = symbols.where((symbol) => symbol.status == 'NEEDS_PORT').length;
    if (hasCritical) diagnostics.add('Contains accounting/stock/manufacturing or direct-write behavior that must map to WMN native engines.');
    if (dependencies.any((item) => item != 'frappe' && !_pythonStdlib.contains(item))) {
      diagnostics.add('Uses external Python package(s); these require a WMN integration/native replacement.');
    }

    final status = needsCount == 0 && reviewCount == 0 && autoCount > 0
        ? 'AUTO_CONVERTED'
        : autoCount > 0 || reviewCount > 0
            ? 'REVIEW'
            : 'NEEDS_PORT';
    final confidence = symbols.isEmpty
        ? 0.15
        : symbols.map((entry) => entry.confidence).reduce((a, b) => a + b) / symbols.length;
    return WmnSourcePortResult(
      language: 'PYTHON',
      status: status,
      strategy: autoCount > 0 ? 'PYTHON_AST_LITE_TO_WMN_SERVER_SCRIPT' : 'PYTHON_ANALYSIS',
      confidence: confidence.clamp(0, 1).toDouble(),
      convertedCode: convertedHooks.isEmpty ? null : convertedHooks.join('\n\n'),
      diagnostics: List.unmodifiable(diagnostics),
      dependencies: dependencies.toList()..sort(),
      symbols: List.unmodifiable(symbols),
    );
  }

  WmnSourcePortResult analyzeJavaScript(
    String source, {
    String? doctype,
    required String sourcePath,
  }) {
    final diagnostics = <String>[];
    final dependencies = <String>{};
    final symbols = <WmnSourceSymbol>[];
    final executableSource = _jsExecutableSurface(source);
    final originalApis = RegExp(r'\bfrappe\.([A-Za-z_][A-Za-z0-9_.]*)')
        .allMatches(executableSource)
        .map((match) => match.group(1)!)
        .toSet();
    dependencies.addAll(originalApis.map((api) => 'frappe.${api.split('.').first}'));

    var converted = source;
    const replacements = <String, String>{
      'frappe.ui.form.on': 'wmn.ui.form.on',
      'frappe.db.get_value': 'wmn.db.getValue',
      'frappe.db.get_list': 'wmn.db.getList',
      'frappe.db.get_all': 'wmn.db.getList',
      'frappe.db.get_count': 'wmn.db.getCount',
      'frappe.db.exists': 'wmn.db.exists',
      'frappe.model.remove_from_locals': 'wmn.model.removeFromLocals',
      'frappe.model.with_doctype': 'wmn.model.withDocType',
      'frappe.model.get_value': 'wmn.model.getValue',
      'frappe.model.set_value': 'wmn.model.setValue',
      'frappe.contacts.get_last_doc': 'wmn.contacts.getLastDoc',
      'frappe.phone_call.handler': 'wmn.phoneCall.handler',
      'frappe.dynamic_link': 'wmn.dynamicLink',
      'frappe.boot.user.can_create': 'wmn.permissions.canCreate',
      'frappe.session.user': 'wmn.session.user',
      'frappe.get_meta': 'wmn.meta.get',
      'frappe.set_route': 'wmn.router.setRoute',
      'frappe.run_serially': 'wmn.runSerially',
      'frappe.timeout': 'wmn.timeout',
      'frappe.msgprint': 'wmn.msgprint',
      'frappe.throw': 'wmn.throw',
      'frappe.utils.now': 'wmn.utils.now',
      'window.open': 'wmn.actions.openUrl',
      'frappe.call': 'wmn.call',
      'frappe.xcall': 'wmn.xcall',
    };
    final ordered = replacements.entries.toList()
      ..sort((left, right) => right.key.length.compareTo(left.key.length));
    for (final entry in ordered) {
      converted = converted.replaceAll(entry.key, entry.value);
    }

    final reviewCapabilities = <String>{};
    void markIf(String needle, String capability) {
      if (executableSource.contains(needle)) reviewCapabilities.add(capability);
    }

    markIf('frappe.call', 'BACKEND_METHOD_CALL');
    markIf('frappe.xcall', 'BACKEND_METHOD_CALL');
    markIf('frappe.request', 'BACKEND_REQUEST');
    markIf('frappe.contacts', 'FRAPPE_CONTACTS_CONTEXT');
    markIf('frappe.dynamic_link', 'DYNAMIC_LINK_CONTEXT');
    markIf('frappe.phone_call', 'PHONE_CALL_PLATFORM_CAPABILITY');
    markIf('frappe.boot', 'BOOT_PERMISSION_CONTEXT');
    markIf('frappe.model.with_doctype', 'META_CONTEXT');
    markIf('frappe.get_meta', 'META_CONTEXT');
    markIf('frappe.model.set_value', 'CHILD_LOCALS_CONTEXT');
    markIf('frappe.model.remove_from_locals', 'LOCAL_MODEL_CACHE');
    markIf('frappe.run_serially', 'ASYNC_SEMANTICS');
    markIf('frappe.timeout', 'ASYNC_SEMANTICS');
    markIf('frappe.set_route', 'NAVIGATION_ACTION');
    markIf('window.open', 'EXTERNAL_URL_ACTION');
    markIf('locals[', 'CHILD_LOCALS_CONTEXT');
    markIf('cur_frm', 'LEGACY_CUR_FRM');
    markIf('frappe.realtime', 'REALTIME_API');
    markIf('frappe.require', 'DYNAMIC_ASSET_LOADING');
    markIf('frappe.db.sql', 'RAW_SQL');
    markIf('frappe.db.set_value', 'DIRECT_DB_WRITE');
    markIf('frappe.db.delete_doc', 'DIRECT_DB_WRITE');
    markIf('fetch(', 'BROWSER_NETWORK');
    markIf('XMLHttpRequest', 'BROWSER_NETWORK');
    markIf('WebSocket', 'BROWSER_NETWORK');

    final methodPattern = RegExp(r'''\bmethod\s*:\s*['"]([^'"]+)['"]''');
    final backendMethods = methodPattern
        .allMatches(source)
        .map((match) => match.group(1)!)
        .where((value) => value.contains('.'))
        .toSet()
        .toList(growable: false)
      ..sort();
    for (final method in backendMethods) {
      dependencies.add('method:$method');
    }
    if (backendMethods.isNotEmpty) {
      diagnostics.add(
        'frappe.call backend method mapping required: ${backendMethods.join(', ')}. WMN preserves the call contract but does not execute Frappe Python methods.',
      );
    }

    final executableConverted = _jsExecutableSurface(converted);
    final unresolvedFrappe = RegExp(r'\bfrappe\.([A-Za-z_][A-Za-z0-9_.]*)')
        .allMatches(executableConverted)
        .map((match) => 'frappe.${match.group(1)!}')
        .toSet()
        .toList(growable: false)
      ..sort();
    if (unresolvedFrappe.isNotEmpty) {
      reviewCapabilities.add('UNRESOLVED_FRAPPE_API');
      diagnostics.add('Unresolved Frappe API(s) after rewrite: ${unresolvedFrappe.join(', ')}');
    }

    final unsafeBrowser = <String>[];
    for (final token in const ['window.', 'document.', 'fetch(', 'XMLHttpRequest', 'WebSocket']) {
      if (executableConverted.contains(token)) unsafeBrowser.add(token);
    }
    if (unsafeBrowser.isNotEmpty) {
      reviewCapabilities.add('UNSUPPORTED_BROWSER_API');
      diagnostics.add('Unsupported browser API(s) remain after rewrite: ${unsafeBrowser.join(', ')}');
    }

    final hookPattern = RegExp(r'''(?:frappe|wmn)\.ui\.form\.on\s*\(\s*['"]([^'"]+)['"]''');
    final hookTypes = <String>{};
    for (final match in hookPattern.allMatches(converted)) {
      final hookDoctype = match.group(1)!;
      hookTypes.add(hookDoctype);
      symbols.add(WmnSourceSymbol(
        type: 'FORM_HOOK',
        name: hookDoctype,
        lineStart: _lineForOffset(converted, match.start),
        lineEnd: _lineForOffset(converted, match.end),
        targetKind: 'CLIENT_SCRIPT',
        targetName: hookDoctype,
        status: 'REVIEW',
        confidence: 0.70,
        details: {
          'source_doctype': doctype,
          'requires_child_event_bridge': doctype != null && hookDoctype != doctype,
        },
      ));
    }
    if (doctype != null && hookTypes.any((value) => value != doctype)) {
      reviewCapabilities.add('CHILD_DOCTYPE_HOOK');
      diagnostics.add('Contains child/secondary DocType form hooks. WMN preserves them, but child-row event dispatch requires the child-form bridge.');
    }

    final compatibilityReferences = <String, String>{
      'wmn.call': 'BACKEND_METHOD_CALL',
      'wmn.xcall': 'BACKEND_METHOD_CALL',
      'wmn.contacts.getLastDoc': 'FRAPPE_CONTACTS_CONTEXT',
      'wmn.dynamicLink': 'DYNAMIC_LINK_CONTEXT',
      'wmn.phoneCall.handler': 'PHONE_CALL_PLATFORM_CAPABILITY',
      'wmn.actions.openUrl': 'EXTERNAL_URL_ACTION',
      'wmn.permissions.canCreate': 'BOOT_PERMISSION_CONTEXT',
      'wmn.model.setValue': 'CHILD_LOCALS_CONTEXT',
    };
    for (final entry in compatibilityReferences.entries) {
      if (!converted.contains(entry.key)) continue;
      final matches = RegExp(RegExp.escape(entry.key)).allMatches(converted);
      for (final match in matches) {
        symbols.add(WmnSourceSymbol(
          type: 'COMPAT_API',
          name: entry.key,
          lineStart: _lineForOffset(converted, match.start),
          lineEnd: _lineForOffset(converted, match.end),
          targetKind: 'WMN_COMPATIBILITY_API',
          targetName: doctype,
          status: 'REVIEW',
          confidence: 0.65,
          details: {'capability': entry.value},
        ));
      }
    }

    if (reviewCapabilities.isNotEmpty) {
      final sorted = reviewCapabilities.toList(growable: false)..sort();
      diagnostics.add('Review capability mapping: ${sorted.join(', ')}');
    }

    final hasFormHook = hookPattern.hasMatch(converted);
    final canAutoConvert = hasFormHook &&
        reviewCapabilities.isEmpty &&
        unresolvedFrappe.isEmpty &&
        unsafeBrowser.isEmpty;
    final status = canAutoConvert ? 'AUTO_CONVERTED' : hasFormHook ? 'REVIEW' : 'NEEDS_PORT';
    final penalty = (reviewCapabilities.length * 0.055) +
        (unresolvedFrappe.isNotEmpty ? 0.12 : 0) +
        (unsafeBrowser.isNotEmpty ? 0.12 : 0);
    final confidence = status == 'AUTO_CONVERTED'
        ? 0.96
        : status == 'REVIEW'
            ? (0.88 - penalty).clamp(0.35, 0.82).toDouble()
            : 0.25;

    for (var index = 0; index < symbols.length; index++) {
      final symbol = symbols[index];
      if (symbol.type != 'FORM_HOOK') continue;
      symbols[index] = WmnSourceSymbol(
        type: symbol.type,
        name: symbol.name,
        lineStart: symbol.lineStart,
        lineEnd: symbol.lineEnd,
        lifecycleEvent: symbol.lifecycleEvent,
        targetKind: symbol.targetKind,
        targetName: symbol.targetName,
        status: status == 'AUTO_CONVERTED' ? 'AUTO_CONVERTED' : 'REVIEW',
        confidence: status == 'AUTO_CONVERTED' ? 0.96 : confidence,
        details: symbol.details,
      );
    }

    return WmnSourcePortResult(
      language: 'JAVASCRIPT',
      status: status,
      strategy: hasFormHook ? 'FRAPPE_JS_COMPATIBILITY_REWRITE_V2' : 'JAVASCRIPT_ANALYSIS',
      confidence: confidence,
      convertedCode: hasFormHook ? converted : null,
      diagnostics: List.unmodifiable(diagnostics),
      dependencies: dependencies.toList()..sort(),
      symbols: List.unmodifiable(symbols),
    );
  }
  String saveSourceUnit({
    required String appName,
    required String sourcePath,
    required String source,
    required WmnSourcePortResult result,
    String? artifactId,
  }) {
    final existing = database.db.select(
      'SELECT id,source_storage_path,converted_storage_path FROM wmn_app_source_units WHERE app_name=? AND source_path=? AND language=? LIMIT 1;',
      [appName, sourcePath, result.language],
    );
    final id = existing.isEmpty ? _uuid.v4() : existing.first['id'] as String;
    final sourceStoragePath = existing.isEmpty || '${existing.first['source_storage_path'] ?? ''}'.trim().isEmpty
        ? _sourceStorageKey(appName, sourcePath, id: id, converted: false)
        : '${existing.first['source_storage_path']}';
    final convertedStoragePath = result.convertedCode == null
        ? null
        : (existing.isEmpty || '${existing.first['converted_storage_path'] ?? ''}'.trim().isEmpty
            ? _sourceStorageKey(appName, sourcePath, id: id, converted: true)
            : '${existing.first['converted_storage_path']}');

    storage.writeText(sourceStoragePath, source);
    if (result.convertedCode != null && convertedStoragePath != null) {
      storage.writeText(convertedStoragePath, result.convertedCode!);
    } else if (existing.isNotEmpty) {
      final oldConverted = '${existing.first['converted_storage_path'] ?? ''}'.trim();
      if (oldConverted.isNotEmpty && storage.exists(oldConverted)) storage.delete(oldConverted);
    }

    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO wmn_app_source_units(
        id,app_name,artifact_id,source_path,language,source_storage_path,converted_storage_path,conversion_strategy,
        conversion_status,confidence,review_status,diagnostics_json,dependencies_json,created_at,updated_at
      ) VALUES (?,?,?,?,?,?,?,?,?,?, 'UNREVIEWED',?,?,?,?)
      ON CONFLICT(app_name,source_path,language) DO UPDATE SET
        artifact_id=excluded.artifact_id,source_storage_path=excluded.source_storage_path,
        converted_storage_path=excluded.converted_storage_path,
        conversion_strategy=excluded.conversion_strategy,conversion_status=excluded.conversion_status,
        confidence=excluded.confidence,diagnostics_json=excluded.diagnostics_json,
        dependencies_json=excluded.dependencies_json,updated_at=excluded.updated_at;
    ''', [
      id,
      appName,
      artifactId,
      sourcePath,
      result.language,
      sourceStoragePath,
      convertedStoragePath,
      result.strategy,
      result.status,
      result.confidence,
      jsonEncode(result.diagnostics),
      jsonEncode(result.dependencies),
      now,
      now,
    ]);
    database.db.execute('DELETE FROM wmn_porting_symbols WHERE source_unit_id=?;', [id]);
    for (final symbol in result.symbols) {
      database.db.execute('''
        INSERT INTO wmn_porting_symbols(
          id,source_unit_id,symbol_type,symbol_name,line_start,line_end,lifecycle_event,target_kind,target_name,
          conversion_status,confidence,details_json
        ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?);
      ''', [
        _uuid.v4(), id, symbol.type, symbol.name, symbol.lineStart, symbol.lineEnd,
        symbol.lifecycleEvent, symbol.targetKind, symbol.targetName, symbol.status,
        symbol.confidence, jsonEncode(symbol.details),
      ]);
    }
    for (final dependency in result.dependencies) {
      if (dependency.trim().isEmpty || dependency == 'frappe' || dependency == appName) continue;
      database.db.execute('''
        INSERT INTO wmn_app_dependencies(app_name,dependency_name,dependency_kind,source_path,required,resolved,metadata_json,updated_at)
        VALUES (?,?,?, ?,1,0,'{}',?)
        ON CONFLICT(app_name,dependency_name,dependency_kind) DO UPDATE SET source_path=excluded.source_path,updated_at=excluded.updated_at;
      ''', [
        appName,
        dependency,
        result.language == 'PYTHON' ? 'PYTHON_PACKAGE' : 'JAVASCRIPT_PACKAGE',
        sourcePath,
        now,
      ]);
    }
    return id;
  }

  /// Lists source-unit metadata without reading source files from Storage.
  ///
  /// This keeps the workbench/list path cheap even for applications containing
  /// thousands of source files. Use [sourceUnit] only when the user opens a
  /// specific unit and needs its original/converted content.
  List<Map<String, Object?>> sourceUnits(String appName, {String? status}) {
    final where = status == null ? 'app_name=?' : 'app_name=? AND conversion_status=?';
    final args = status == null ? <Object?>[appName] : <Object?>[appName, status];
    return database.db
        .select('SELECT * FROM wmn_app_source_units WHERE $where ORDER BY language,conversion_status,source_path;', args)
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
  }

  Map<String, Object?>? sourceUnit(String id, {bool hydrate = true}) {
    final rows = database.db.select(
      'SELECT * FROM wmn_app_source_units WHERE id=? LIMIT 1;',
      [id],
    );
    if (rows.isEmpty) return null;
    final row = Map<String, Object?>.from(rows.first);
    return hydrate ? hydrateSourceUnit(row) : row;
  }

  Map<String, Object?> hydrateSourceUnit(Map<String, Object?> row) {
    final hydrated = Map<String, Object?>.from(row);
    hydrated['source_code'] = readStoredSource(row);
    hydrated['converted_code'] = readStoredConvertedSource(row);
    return hydrated;
  }

  String readStoredSource(Map<String, Object?> row) {
    final key = '${row['source_storage_path'] ?? ''}'.trim();
    if (key.isEmpty) return '';
    return storage.exists(key) ? storage.readText(key) : '';
  }

  String? readStoredConvertedSource(Map<String, Object?> row) {
    final key = '${row['converted_storage_path'] ?? ''}'.trim();
    if (key.isEmpty) return null;
    return storage.exists(key) ? storage.readText(key) : null;
  }

  String _sourceStorageKey(String appName, String sourcePath, {required String id, required bool converted}) {
    final app = _safeSegment(appName);
    final normalized = sourcePath.replaceAll('\\', '/');
    final parts = normalized
        .split('/')
        .where((part) => part.trim().isNotEmpty && part != '.' && part != '..')
        .map(_safeSegment)
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    final relative = parts.isEmpty ? '$id.txt' : parts.join('/');
    return converted ? 'apps/$app/converted/$relative.converted' : 'apps/$app/source/$relative';
  }

  String _safeSegment(String value) => value
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^[_\.]+|[_\.]+$'), '');

  List<Map<String, Object?>> symbols(String sourceUnitId) => database.db
      .select('SELECT * FROM wmn_porting_symbols WHERE source_unit_id=? ORDER BY line_start,symbol_name;', [sourceUnitId])
      .map((row) => Map<String, Object?>.from(row))
      .toList(growable: false);

  List<String> _decoratorsBefore(List<String> lines, int index, int indent) {
    final result = <String>[];
    for (var i = index - 1; i >= 0; i--) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      final leading = line.length - line.trimLeft().length;
      if (leading != indent || !line.trimLeft().startsWith('@')) break;
      result.insert(0, line.trim());
    }
    return result;
  }

  _PythonBodyAnalysis _analyzePythonBody(String body) {
    final lower = body.toLowerCase();
    final usesRawSql = lower.contains('frappe.db.sql') || lower.contains('frappe.qb') || lower.contains('querybuilder');
    final usesDbWrite = lower.contains('frappe.db.set_value') ||
        lower.contains('frappe.db.delete') ||
        lower.contains('.db_update(') ||
        lower.contains('.insert(') ||
        lower.contains('.save(') ||
        lower.contains('.submit(') ||
        lower.contains('frappe.db.commit') ||
        lower.contains('frappe.db.rollback');
    final usesDbRead = lower.contains('frappe.db.get_value') ||
        lower.contains('frappe.db.get_list') ||
        lower.contains('frappe.get_all') ||
        lower.contains('frappe.get_list') ||
        lower.contains('frappe.get_doc') ||
        lower.contains('frappe.get_cached_value');
    final usesBackgroundJobs = lower.contains('frappe.enqueue') || lower.contains('enqueue_after_commit') || lower.contains('scheduler');
    final critical = RegExp(
      r'\b(make_gl_entries|gl entry|stock ledger|stock_entry|stock entry|valuation|repost|general ledger|payment ledger|bin update|serial and batch|manufacturing|work order|bom)\b',
      caseSensitive: false,
    ).hasMatch(body);
    final unsupportedControl = RegExp(r'^\s*(for|while|try|except|with|match|yield|raise|assert)\b', multiLine: true).hasMatch(body);
    final unsupportedCalls = lower.contains('frappe.call') || lower.contains('frappe.get_doc') || lower.contains('frappe.new_doc');
    return _PythonBodyAnalysis(
      usesDbRead: usesDbRead,
      usesDbWrite: usesDbWrite,
      usesRawSql: usesRawSql,
      usesBackgroundJobs: usesBackgroundJobs,
      hasCriticalEngineBehavior: critical,
      safeForAutomaticPort: !usesDbWrite && !usesRawSql && !usesBackgroundJobs && !critical && !unsupportedControl && !unsupportedCalls,
    );
  }

  String? _convertSimplePythonLifecycle(String body, {required String doctype, required String event}) {
    final sourceLines = body.split(RegExp(r'\r?\n'));
    final minIndent = sourceLines
        .where((line) => line.trim().isNotEmpty)
        .map((line) => line.length - line.trimLeft().length)
        .fold<int?>(null, (value, entry) => value == null || entry < value ? entry : value) ??
        0;
    final output = <String>[];
    final indentStack = <int>[minIndent - 1];
    for (final rawLine in sourceLines) {
      if (rawLine.trim().isEmpty || rawLine.trimLeft().startsWith('#')) continue;
      final indent = rawLine.length - rawLine.trimLeft().length;
      var text = rawLine.trim();
      while (indentStack.length > 1 && indent <= indentStack.last) {
        indentStack.removeLast();
        output.add('${_indent(indentStack.length - 1)}}');
      }
      if (text == 'pass') continue;
      if (text.startsWith('if ') && text.endsWith(':')) {
        final expr = _pythonExpression(text.substring(3, text.length - 1));
        if (expr == null) return null;
        output.add('${_indent(indentStack.length - 1)}if ($expr) {');
        indentStack.add(indent);
        continue;
      }
      final throwMatch = RegExp(r'''^frappe\.throw\s*\(\s*(?:_\()?\s*['"]([^'"]+)['"]\s*\)?\s*\)\s*$''').firstMatch(text);
      if (throwMatch != null) {
        output.add('${_indent(indentStack.length - 1)}wmn.throw(${jsonEncode(throwMatch.group(1))});');
        continue;
      }
      final msgMatch = RegExp(r'''^frappe\.msgprint\s*\(\s*(?:_\()?\s*['"]([^'"]+)['"]\s*\)?\s*\)\s*$''').firstMatch(text);
      if (msgMatch != null) {
        output.add('${_indent(indentStack.length - 1)}wmn.msgprint(${jsonEncode(msgMatch.group(1))});');
        continue;
      }
      final assignMatch = RegExp(r'^self\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$').firstMatch(text);
      if (assignMatch != null) {
        final expr = _pythonExpression(assignMatch.group(2)!);
        if (expr == null) return null;
        output.add('${_indent(indentStack.length - 1)}doc.${assignMatch.group(1)} = $expr;');
        continue;
      }
      final returnMatch = RegExp(r'^return(?:\s+(.+))?$').firstMatch(text);
      if (returnMatch != null) {
        final value = returnMatch.group(1);
        if (value == null) {
          output.add('${_indent(indentStack.length - 1)}return;');
        } else {
          final expr = _pythonExpression(value);
          if (expr == null) return null;
          output.add('${_indent(indentStack.length - 1)}return $expr;');
        }
        continue;
      }
      return null;
    }
    while (indentStack.length > 1) {
      indentStack.removeLast();
      output.add('${_indent(indentStack.length - 1)}}');
    }
    if (output.isEmpty) return null;
    return '''wmn.server.on(${jsonEncode(doctype)}, {
  ${jsonEncode(event)}: function(doc, context) {
${output.map((line) => '    $line').join('\n')}
  }
});''';
  }

  String? _pythonExpression(String source) {
    var value = source.trim();
    if (RegExp(r'\b(lambda|await|yield|for\s+.+\s+in|\{|\[.+\s+for\s+)\b').hasMatch(value)) return null;
    value = value
        .replaceAllMapped(RegExp(r'\bself\.([A-Za-z_][A-Za-z0-9_]*)'), (match) => 'doc.${match.group(1)}')
        .replaceAll(RegExp(r'\bNone\b'), 'null')
        .replaceAll(RegExp(r'\bTrue\b'), 'true')
        .replaceAll(RegExp(r'\bFalse\b'), 'false')
        .replaceAll(RegExp(r'\band\b'), '&&')
        .replaceAll(RegExp(r'\bor\b'), '||')
        .replaceAll(RegExp(r'\bnot\s+'), '!');
    final dbGet = RegExp(r'''frappe\.db\.get_value\s*\(\s*(['"][^'"]+['"])\s*,\s*([^,]+)\s*,\s*(['"][^'"]+['"])\s*\)''');
    value = value.replaceAllMapped(dbGet, (match) => 'wmn.db.getValue(${match.group(1)}, ${match.group(2)}, ${match.group(3)})');
    if (value.contains('frappe.') || value.contains('self.') || value.contains(' get_doc(')) return null;
    return value;
  }

  String _indent(int depth) => List<String>.filled(depth < 0 ? 0 : depth, '  ').join();

  int _lineForOffset(String source, int offset) => '\n'.allMatches(source.substring(0, offset)).length + 1;


  String _jsExecutableSurface(String source) {
    final chars = source.split('');
    var inSingle = false;
    var inDouble = false;
    var inTemplate = false;
    var inLineComment = false;
    var inBlockComment = false;
    var escaped = false;
    for (var index = 0; index < chars.length; index++) {
      final current = chars[index];
      final next = index + 1 < chars.length ? chars[index + 1] : '';
      if (inLineComment) {
        if (current == '\n' || current == '\r') {
          inLineComment = false;
        } else {
          chars[index] = ' ';
        }
        continue;
      }
      if (inBlockComment) {
        if (current == '*' && next == '/') {
          chars[index] = ' ';
          chars[index + 1] = ' ';
          index++;
          inBlockComment = false;
        } else if (current != '\n' && current != '\r') {
          chars[index] = ' ';
        }
        continue;
      }
      if (inSingle || inDouble || inTemplate) {
        if (escaped) {
          if (current != '\n' && current != '\r') chars[index] = ' ';
          escaped = false;
          continue;
        }
        if (current == '\\') {
          chars[index] = ' ';
          escaped = true;
          continue;
        }
        final closes = (inSingle && current == "'") ||
            (inDouble && current == '"') ||
            (inTemplate && current == '`');
        if (closes) {
          chars[index] = ' ';
          inSingle = false;
          inDouble = false;
          inTemplate = false;
        } else if (current != '\n' && current != '\r') {
          chars[index] = ' ';
        }
        continue;
      }
      if (current == '/' && next == '/') {
        chars[index] = ' ';
        chars[index + 1] = ' ';
        index++;
        inLineComment = true;
      } else if (current == '/' && next == '*') {
        chars[index] = ' ';
        chars[index + 1] = ' ';
        index++;
        inBlockComment = true;
      } else if (current == "'") {
        chars[index] = ' ';
        inSingle = true;
      } else if (current == '"') {
        chars[index] = ' ';
        inDouble = true;
      } else if (current == '`') {
        chars[index] = ' ';
        inTemplate = true;
      }
    }
    return chars.join();
  }

  static const Set<String> _pythonStdlib = {
    'abc','argparse','ast','asyncio','base64','bisect','calendar','collections','concurrent','contextlib','copy','csv','dataclasses','datetime','decimal','difflib','email','enum','functools','glob','hashlib','heapq','hmac','html','http','importlib','inspect','io','itertools','json','logging','math','operator','os','pathlib','pickle','random','re','secrets','shlex','shutil','socket','sqlite3','statistics','string','subprocess','sys','tempfile','textwrap','threading','time','traceback','types','typing','unittest','urllib','uuid','warnings','xml','zipfile',
  };
}

class _PythonBodyAnalysis {
  const _PythonBodyAnalysis({
    required this.usesDbRead,
    required this.usesDbWrite,
    required this.usesRawSql,
    required this.usesBackgroundJobs,
    required this.hasCriticalEngineBehavior,
    required this.safeForAutomaticPort,
  });

  final bool usesDbRead;
  final bool usesDbWrite;
  final bool usesRawSql;
  final bool usesBackgroundJobs;
  final bool hasCriticalEngineBehavior;
  final bool safeForAutomaticPort;
}
