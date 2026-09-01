import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/common.dart';

import 'database_migration.dart';

/// R3.15 consolidates report ownership into tabReport and moves whole-object
/// content out of relational tables into the Storage Runtime.
class Migration026ReportStorageRuntime implements DatabaseMigration {
  const Migration026ReportStorageRuntime();

  @override
  int get version => 26;

  @override
  String get name => 'report_storage_runtime';

  @override
  void apply(CommonDatabase database) {
    _ensureReportColumns(database);
    _ensureReportDocTypeMetadata(database);
    database.execute(r'''
CREATE TABLE IF NOT EXISTS wmn_storage_blobs (
  storage_key TEXT PRIMARY KEY,
  content BLOB NOT NULL,
  updated_at TEXT NOT NULL
) STRICT;
''');

    _migrateStandaloneScripts(database);
    _migrateManagedHookSources(database);
    _migrateAppSourceUnits(database);
    _migrateDocTypeStudioSources(database);
    _migrateBuilderReports(database);
    _migrateScriptReports(database);
    _migrateLegacyFileContents(database);
    _rebuildReportRunLog(database);

    if (_tableExists(database, 'custom_reports')) {
      database.execute('DROP TABLE custom_reports;');
    }
    if (_tableExists(database, 'wmn_script_reports')) {
      database.execute('DROP TABLE wmn_script_reports;');
    }
    if (_tableExists(database, 'wmn_file_contents')) {
      database.execute('DROP TABLE wmn_file_contents;');
    }

    database.execute(r'''
CREATE INDEX IF NOT EXISTS idx_tab_report_runtime
ON "tabReport"(report_type, disabled, module, report_name);
CREATE INDEX IF NOT EXISTS idx_wmn_files_storage_path
ON wmn_files(storage_path);
''');
  }

  void _ensureReportColumns(CommonDatabase database) {
    _addColumn(database, 'tabReport', 'query_source_type', "TEXT NOT NULL DEFAULT 'INLINE' CHECK(query_source_type IN ('INLINE','STORAGE_FILE','STRUCTURED'))");
    _addColumn(database, 'tabReport', 'query_source_path', 'TEXT');
    _addColumn(database, 'tabReport', 'script_source_type', "TEXT NOT NULL DEFAULT 'NATIVE_HANDLER' CHECK(script_source_type IN ('NATIVE_HANDLER','STORAGE_FILE'))");
    _addColumn(database, 'tabReport', 'script_source_path', 'TEXT');
    _addColumn(database, 'tabReport', 'script_language', 'TEXT');
    _addColumn(database, 'tabReport', 'source_hash', 'TEXT');
  }


  void _ensureReportDocTypeMetadata(CommonDatabase database) {
    final now = DateTime.now().toUtc().toIso8601String();
    database.execute('''
      UPDATE wmn_doctypes
      SET metadata_json=?, updated_at=?
      WHERE name='Report';
    ''', [
      jsonEncode(<String, Object?>{
        'report_types': <String>['Report Builder', 'Query Report', 'Script Report', 'Custom Report'],
        'single_source_of_truth': true,
        'external_source_storage': true,
      }),
      now,
    ]);

    final fields = <Map<String, Object?>>[
      {'name':'report_name','label':'Report Name','type':'Data','idx':10,'reqd':1,'list':1,'filter':1,'search':1},
      {'name':'report_type','label':'Report Type','type':'Select','options':'Report Builder\nQuery Report\nScript Report\nCustom Report','idx':20,'reqd':1,'list':1,'filter':1},
      {'name':'ref_doctype','label':'Reference DocType','type':'Link','options':'DocType','idx':30,'list':1,'filter':1,'search':1},
      {'name':'module','label':'Module','type':'Link','options':'Module','idx':40,'reqd':1,'list':1,'filter':1,'search':1},
      {'name':'disabled','label':'Disabled','type':'Check','idx':50,'list':1,'filter':1},
      {'name':'is_standard','label':'System Report','type':'Check','idx':60,'read':1},
      {'name':'query_source_type','label':'Query Source Type','type':'Select','options':'INLINE\nSTORAGE_FILE\nSTRUCTURED','idx':70},
      {'name':'query_source_path','label':'Query Source Path','type':'Data','idx':80},
      {'name':'script_source_type','label':'Script Source Type','type':'Select','options':'NATIVE_HANDLER\nSTORAGE_FILE','idx':90},
      {'name':'script_key','label':'Native Handler Key','type':'Data','idx':100},
      {'name':'script_source_path','label':'Script Source Path','type':'Data','idx':110},
      {'name':'script_language','label':'Script Language','type':'Data','idx':120},
      {'name':'filters_json','label':'Filters','type':'JSON','idx':130},
      {'name':'columns_json','label':'Columns','type':'JSON','idx':140},
      {'name':'query_definition_json','label':'Structured Definition','type':'JSON','idx':150},
      {'name':'metadata_json','label':'Metadata','type':'JSON','idx':160},
      {'name':'created_at','label':'Created At','type':'Datetime','idx':170,'read':1},
      {'name':'updated_at','label':'Updated At','type':'Datetime','idx':180,'read':1},
    ];
    for (final field in fields) {
      database.execute('''
        INSERT INTO wmn_doctype_fields(
          id,doctype,fieldname,label,fieldtype,options,idx,reqd,read_only,hidden,
          in_list_view,in_standard_filter,searchable,allow_on_submit,default_json,
          depends_on,mandatory_depends_on,read_only_depends_on,fetch_from,precision,length,
          metadata_json,created_at,updated_at
        ) VALUES (?,?,?,?,?,?,?,?,?,0,?,?,?,0,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'{}',?,?)
        ON CONFLICT(doctype,fieldname) DO UPDATE SET
          label=excluded.label,fieldtype=excluded.fieldtype,options=excluded.options,idx=excluded.idx,
          reqd=excluded.reqd,read_only=excluded.read_only,in_list_view=excluded.in_list_view,
          in_standard_filter=excluded.in_standard_filter,searchable=excluded.searchable,
          updated_at=excluded.updated_at;
      ''', [
        'sys-report-${field['name']}',
        'Report',
        field['name'],
        field['label'],
        field['type'],
        field['options'],
        field['idx'],
        field['reqd'] ?? 0,
        field['read'] ?? 0,
        field['list'] ?? 0,
        field['filter'] ?? 0,
        field['search'] ?? 0,
        now,
        now,
      ]);
    }
    database.execute('''
      INSERT INTO wmn_list_view_settings(doctype,settings_json,updated_at)
      VALUES ('Report',?,?)
      ON CONFLICT(doctype) DO UPDATE SET settings_json=excluded.settings_json,updated_at=excluded.updated_at;
    ''', [
      jsonEncode(<String, Object?>{
        'fields': <String>['report_name','report_type','ref_doctype','module','disabled'],
        'search_fields': <String>['report_name','ref_doctype','module'],
        'sort_field': 'report_name',
        'sort_descending': false,
        'page_size': 50,
        'layout': 'TABLE',
      }),
      now,
    ]);
  }

  void _migrateStandaloneScripts(CommonDatabase database) {
    if (_tableExists(database, 'client_scripts') && _columnExists(database, 'client_scripts', 'script')) {
      _addColumn(database, 'client_scripts', 'source_storage_path', 'TEXT');
      final rows = database.select('SELECT id,document_type,script FROM client_scripts;');
      for (final row in rows) {
        final id = '${row['id']}';
        final scope = _storageSegment('${row['document_type']}'.toLowerCase());
        final key = 'apps/custom/scripts/client/$scope/$id.wmn';
        _storeBlob(database, key, '${row['script'] ?? ''}');
        database.execute("UPDATE client_scripts SET source_storage_path=?,script='' WHERE id=?;", [key, id]);
      }
      database.execute('ALTER TABLE client_scripts DROP COLUMN script;');
    }
    if (_tableExists(database, 'server_scripts') && _columnExists(database, 'server_scripts', 'script')) {
      _addColumn(database, 'server_scripts', 'source_storage_path', 'TEXT');
      final rows = database.select('SELECT id,script_type,document_type,script FROM server_scripts;');
      for (final row in rows) {
        final id = '${row['id']}';
        final scope = _storageSegment('${row['document_type'] ?? row['script_type']}'.toLowerCase());
        final key = 'apps/custom/scripts/server/$scope/$id.wmn';
        _storeBlob(database, key, '${row['script'] ?? ''}');
        database.execute("UPDATE server_scripts SET source_storage_path=?,script='' WHERE id=?;", [key, id]);
      }
      database.execute('ALTER TABLE server_scripts DROP COLUMN script;');
    }
  }

  void _migrateManagedHookSources(CommonDatabase database) {
    if (!_tableExists(database, 'wmn_hook_bindings')) return;
    final rows = database.select('''
      SELECT id,hook_type,target_kind,target,source_path,metadata_json
      FROM wmn_hook_bindings
      WHERE hook_type IN ('SYSTEM_METHOD_MODULE','SYSTEM_SCRIPT');
    ''');
    for (final row in rows) {
      final raw = row['metadata_json'];
      if (raw is! String || raw.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final metadata = <String, Object?>{for (final entry in decoded.entries) '${entry.key}': entry.value};
        final isMethod = metadata['wmn_custom_method_module'] == true && metadata['scope'] == 'SYSTEM_GLOBAL';
        final isScript = metadata['wmn_custom_system_script'] == true && metadata['scope'] == 'SYSTEM_GLOBAL';
        if (!isMethod && !isScript) continue;

        final revision = (metadata['revision'] as num?)?.toInt() ?? 0;
        final logicalName = '${isMethod ? metadata['module_name'] : metadata['script_name'] ?? row['target'] ?? row['id']}';
        final base = isMethod ? 'apps/custom/methods' : 'apps/custom/scripts/system';
        var currentPath = row['source_path']?.toString().trim() ?? '';
        final currentSource = metadata['source']?.toString() ?? '';
        var changed = false;
        if (currentSource.isNotEmpty) {
          currentPath = '$base/${_storageSegment(logicalName)}/r$revision.wmn';
          _storeBlob(database, currentPath, currentSource);
          metadata.remove('source');
          changed = true;
        }

        final revisionsRaw = metadata['revisions'];
        if (revisionsRaw is List) {
          final revisions = <Object?>[];
          for (final value in revisionsRaw) {
            if (value is! Map) {
              revisions.add(value);
              continue;
            }
            final item = <String, Object?>{for (final entry in value.entries) '${entry.key}': entry.value};
            final historicalSource = item['source']?.toString() ?? '';
            if (historicalSource.isNotEmpty) {
              final historicalRevision = (item['revision'] as num?)?.toInt() ?? 0;
              final path = '$base/${_storageSegment(logicalName)}/r$historicalRevision.wmn';
              _storeBlob(database, path, historicalSource);
              item.remove('source');
              item['source_path'] = path;
              changed = true;
            }
            revisions.add(item);
          }
          metadata['revisions'] = revisions;
        }
        if (!changed && currentPath == (row['source_path']?.toString().trim() ?? '')) continue;
        database.execute(
          'UPDATE wmn_hook_bindings SET source_path=?,metadata_json=? WHERE id=?;',
          [currentPath.isEmpty ? null : currentPath, jsonEncode(metadata), '${row['id']}'],
        );
      } catch (_) {
        // Invalid historical metadata is left untouched rather than blocking an upgrade.
      }
    }
  }

  void _migrateAppSourceUnits(CommonDatabase database) {
    if (!_tableExists(database, 'wmn_app_source_units')) return;
    final hasLegacySource = _columnExists(database, 'wmn_app_source_units', 'source_code');
    if (!hasLegacySource) return;
    _addColumn(database, 'wmn_app_source_units', 'source_storage_path', 'TEXT');
    _addColumn(database, 'wmn_app_source_units', 'converted_storage_path', 'TEXT');
    final rows = database.select('SELECT * FROM wmn_app_source_units ORDER BY app_name,source_path;');
    for (final row in rows) {
      final id = '${row['id']}';
      final app = _storageSegment('${row['app_name']}');
      final relative = _storageRelativePath('${row['source_path']}', fallback: '$id.txt');
      final sourceKey = 'apps/$app/source/$relative';
      final convertedKey = 'apps/$app/converted/$relative.converted';
      final source = '${row['source_code'] ?? ''}';
      final converted = row['converted_code']?.toString();
      _storeBlob(database, sourceKey, source);
      if (converted != null && converted.isNotEmpty) _storeBlob(database, convertedKey, converted);
      database.execute('''
        UPDATE wmn_app_source_units
        SET source_storage_path=?, converted_storage_path=?, source_code='', converted_code=NULL
        WHERE id=?;
      ''', [sourceKey, converted == null || converted.isEmpty ? null : convertedKey, id]);
    }
    // sqlite3 bundled with WMN supports DROP COLUMN. Removing the legacy text
    // columns keeps upgraded databases aligned with a fresh R3.15 schema.
    database.execute('ALTER TABLE wmn_app_source_units DROP COLUMN source_code;');
    database.execute('ALTER TABLE wmn_app_source_units DROP COLUMN converted_code;');
  }

  void _migrateDocTypeStudioSources(CommonDatabase database) {
    if (!_tableExists(database, 'wmn_doctypes')) return;
    final rows = database.select('SELECT name,metadata_json FROM wmn_doctypes;');
    for (final row in rows) {
      final raw = row['metadata_json'];
      if (raw is! String || raw.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final metadata = <String, Object?>{for (final e in decoded.entries) '${e.key}': e.value};
        final studioRaw = metadata['wmn_doctype_studio'];
        if (studioRaw is! Map) continue;
        final studio = <String, Object?>{for (final e in studioRaw.entries) '${e.key}': e.value};
        final doctype = '${row['name']}';
        final slug = _storageSegment(doctype.toLowerCase());
        var changed = false;
        final artifactsRaw = studio['artifacts'];
        if (artifactsRaw is Map) {
          final artifacts = <String, Object?>{for (final e in artifactsRaw.entries) '${e.key}': e.value};
          for (final entry in artifacts.entries.toList()) {
            if (entry.value is! Map) continue;
            final artifact = <String, Object?>{for (final e in (entry.value as Map).entries) '${e.key}': e.value};
            final source = artifact['source']?.toString() ?? '';
            if (source.isEmpty) continue;
            final revision = (artifact['revision'] as num?)?.toInt() ?? 0;
            final key = 'apps/custom/doctypes/$slug/${_storageSegment(entry.key.toLowerCase())}/r$revision.wmn';
            _storeBlob(database, key, source);
            artifact.remove('source');
            artifact['source_path'] = key;
            artifacts[entry.key] = artifact;
            changed = true;
          }
          studio['artifacts'] = artifacts;
        }
        final revisionsRaw = studio['revisions'];
        if (revisionsRaw is List) {
          final revisions = <Object?>[];
          for (final value in revisionsRaw) {
            if (value is! Map) {
              revisions.add(value);
              continue;
            }
            final revision = <String, Object?>{for (final e in value.entries) '${e.key}': e.value};
            final source = revision['source']?.toString() ?? '';
            if (source.isNotEmpty) {
              final kind = _storageSegment('${revision['kind'] ?? 'code'}'.toLowerCase());
              final number = (revision['revision'] as num?)?.toInt() ?? 0;
              final key = 'apps/custom/doctypes/$slug/$kind/r$number.wmn';
              _storeBlob(database, key, source);
              revision.remove('source');
              revision['source_path'] = key;
              changed = true;
            }
            revisions.add(revision);
          }
          studio['revisions'] = revisions;
        }
        if (!changed) continue;
        metadata['wmn_doctype_studio'] = studio;
        database.execute('UPDATE wmn_doctypes SET metadata_json=? WHERE name=?;', [jsonEncode(metadata), doctype]);
      } catch (_) {
        // Invalid historical metadata is left untouched rather than blocking an upgrade.
      }
    }
  }

  String _storageSegment(String value) {
    final safe = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_').replaceAll(RegExp(r'_+'), '_');
    final trimmed = safe.replaceAll(RegExp(r'^[_\.]+|[_\.]+$'), '');
    return trimmed.isEmpty ? 'unknown' : trimmed;
  }

  String _storageRelativePath(String value, {required String fallback}) {
    final parts = value
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.trim().isNotEmpty && part != '.' && part != '..')
        .map(_storageSegment)
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    return parts.isEmpty ? fallback : parts.join('/');
  }

  void _migrateBuilderReports(CommonDatabase database) {
    if (!_tableExists(database, 'custom_reports')) return;
    final rows = database.select('SELECT * FROM custom_reports ORDER BY created_at;');
    for (final row in rows) {
      final id = '${row['id']}';
      final name = '${row['name']}';
      Map<String, Object?> definition = <String, Object?>{};
      final raw = row['definition_json'];
      if (raw is String && raw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            definition = <String, Object?>{for (final entry in decoded.entries) '${entry.key}': entry.value};
          }
        } catch (_) {}
      }
      definition['source_key'] = '${row['source_key']}';
      final now = '${row['updated_at'] ?? row['created_at'] ?? DateTime.now().toUtc().toIso8601String()}';
      database.execute('''
        INSERT INTO "tabReport"(
          name,report_name,ref_doctype,report_type,module,is_standard,disabled,
          query_definition_json,script_key,filters_json,columns_json,metadata_json,
          created_at,updated_at,query_source_type
        ) VALUES (?,?,NULL,'Report Builder','Custom',?,?,?,NULL,'[]','[]','{}',?,?, 'STRUCTURED')
        ON CONFLICT(name) DO NOTHING;
      ''', [
        id,
        name,
        row['is_system'] ?? 0,
        (row['enabled'] as int? ?? 1) == 1 ? 0 : 1,
        jsonEncode(definition),
        '${row['created_at'] ?? now}',
        now,
      ]);
    }
  }

  void _migrateScriptReports(CommonDatabase database) {
    if (!_tableExists(database, 'wmn_script_reports')) return;
    final rows = database.select('SELECT * FROM wmn_script_reports ORDER BY created_at;');
    for (final row in rows) {
      final id = '${row['id']}';
      final name = '${row['name']}';
      final rawScript = '${row['script'] ?? ''}';
      final isNative = rawScript.startsWith('native:');
      final scriptKey = isNative ? rawScript.substring(7).trim() : name;
      String? sourcePath;
      String sourceType = 'NATIVE_HANDLER';
      String? language;
      if (!isNative && rawScript.trim().isNotEmpty) {
        sourcePath = 'scripts/legacy/$id.wmn';
        sourceType = 'STORAGE_FILE';
        language = 'wmn-legacy';
        _storeBlob(database, sourcePath, rawScript);
      }
      final now = '${row['updated_at'] ?? row['created_at'] ?? DateTime.now().toUtc().toIso8601String()}';
      database.execute('''
        INSERT INTO "tabReport"(
          name,report_name,ref_doctype,report_type,module,is_standard,disabled,
          query_definition_json,script_key,filters_json,columns_json,metadata_json,
          created_at,updated_at,script_source_type,script_source_path,script_language
        ) VALUES (?,?,?,'Script Report',?,?,?,?,?,?,?,'{}',?,?,?,?,?)
        ON CONFLICT(name) DO UPDATE SET
          report_type='Script Report',module=excluded.module,ref_doctype=excluded.ref_doctype,
          disabled=excluded.disabled,script_key=excluded.script_key,
          filters_json=excluded.filters_json,columns_json=excluded.columns_json,
          script_source_type=excluded.script_source_type,
          script_source_path=excluded.script_source_path,
          script_language=excluded.script_language,updated_at=excluded.updated_at;
      ''', [
        id,
        name,
        row['reference_doctype'],
        '${row['module'] ?? 'Custom'}',
        row['is_system'] ?? 0,
        (row['enabled'] as int? ?? 1) == 1 ? 0 : 1,
        '{}',
        scriptKey,
        '${row['filters_json'] ?? '[]'}',
        '${row['columns_json'] ?? '[]'}',
        '${row['created_at'] ?? now}',
        now,
        sourceType,
        sourcePath,
        language,
      ]);
    }
  }

  void _migrateLegacyFileContents(CommonDatabase database) {
    if (!_tableExists(database, 'wmn_file_contents')) return;
    final rows = database.select('''
      SELECT f.id,f.file_name,f.is_private,c.content,c.updated_at
      FROM wmn_files f JOIN wmn_file_contents c ON c.file_id=f.id;
    ''');
    for (final row in rows) {
      final id = '${row['id']}';
      final safeName = '${row['file_name']}'.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
      final key = 'files/${row['is_private'] == 1 ? 'private' : 'public'}/$id/$safeName';
      final value = row['content'];
      if (value is Uint8List) {
        database.execute('''
          INSERT INTO wmn_storage_blobs(storage_key,content,updated_at) VALUES (?,?,?)
          ON CONFLICT(storage_key) DO UPDATE SET content=excluded.content,updated_at=excluded.updated_at;
        ''', [key, value, '${row['updated_at']}']);
      } else if (value is List<int>) {
        database.execute('''
          INSERT INTO wmn_storage_blobs(storage_key,content,updated_at) VALUES (?,?,?)
          ON CONFLICT(storage_key) DO UPDATE SET content=excluded.content,updated_at=excluded.updated_at;
        ''', [key, Uint8List.fromList(value), '${row['updated_at']}']);
      }
      database.execute(
        'UPDATE wmn_files SET storage_path=?,file_url=? WHERE id=?;',
        [key, 'wmn://$key', id],
      );
    }
  }

  void _rebuildReportRunLog(CommonDatabase database) {
    if (!_tableExists(database, 'report_run_log')) return;
    database.execute(r'''
CREATE TABLE report_run_log_v26 (
  id TEXT PRIMARY KEY,
  report_id TEXT,
  report_name TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('SUCCESS','ERROR')),
  row_count INTEGER NOT NULL DEFAULT 0,
  duration_ms INTEGER NOT NULL DEFAULT 0,
  error_text TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (report_id) REFERENCES "tabReport"(name) ON DELETE SET NULL
) STRICT;
''');
    database.execute('''
      INSERT INTO report_run_log_v26(id,report_id,report_name,status,row_count,duration_ms,error_text,created_at)
      SELECT id,
        CASE WHEN report_id IN (SELECT name FROM "tabReport") THEN report_id ELSE NULL END,
        report_name,status,row_count,duration_ms,error_text,created_at
      FROM report_run_log;
    ''');
    database.execute('DROP TABLE report_run_log;');
    database.execute('ALTER TABLE report_run_log_v26 RENAME TO report_run_log;');
    database.execute('CREATE INDEX idx_report_run_log_created ON report_run_log(created_at DESC, status);');
  }

  void _storeBlob(CommonDatabase database, String key, String source) {
    database.execute('''
      INSERT INTO wmn_storage_blobs(storage_key,content,updated_at) VALUES (?,?,?)
      ON CONFLICT(storage_key) DO UPDATE SET content=excluded.content,updated_at=excluded.updated_at;
    ''', [key, Uint8List.fromList(utf8.encode(source)), DateTime.now().toUtc().toIso8601String()]);
  }

  void _addColumn(CommonDatabase database, String table, String column, String definition) {
    if (_columnExists(database, table, column)) return;
    database.execute('ALTER TABLE "$table" ADD COLUMN "$column" $definition;');
  }

  bool _tableExists(CommonDatabase database, String table) => database.select(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;",
        [table],
      ).isNotEmpty;

  bool _columnExists(CommonDatabase database, String table, String column) => database
      .select('PRAGMA table_info("$table");')
      .any((row) => '${row['name']}' == column);
}
