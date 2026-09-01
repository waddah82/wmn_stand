import 'dart:convert';

import 'package:sqlite3/common.dart';

import 'database_migration.dart';

/// R3.15.12 makes Report filters/columns first-class child tables, keeps
/// Query/managed Script source in Storage, and upgrades the learning examples.
///
/// Existing filters_json/columns_json are migrated once and retained only as
/// backward-compatibility snapshots. Runtime metadata prefers the child rows.
class Migration029ReportSourceEditorExamples implements DatabaseMigration {
  const Migration029ReportSourceEditorExamples();

  @override
  int get version => 29;

  @override
  String get name => 'report_source_editor_examples';

  @override
  void apply(CommonDatabase database) {
    final now = DateTime.now().toUtc().toIso8601String();
    _createChildTables(database);
    _registerChildDocTypes(database, now);
    _registerReportTableFields(database, now);
    _migrateExistingDefinitions(database, now);
    _configureReportForm(database, now);
    _upgradeScriptExample(database, now);
  }

  void _createChildTables(CommonDatabase database) {
    database.execute(r'''
CREATE TABLE IF NOT EXISTS [tabReport Filter] (
  name TEXT PRIMARY KEY,
  parent TEXT NOT NULL,
  parentfield TEXT NOT NULL DEFAULT 'filters',
  parenttype TEXT NOT NULL DEFAULT 'Report',
  idx INTEGER NOT NULL DEFAULT 0,
  fieldname TEXT NOT NULL,
  label TEXT NOT NULL,
  label_ar TEXT,
  fieldtype TEXT NOT NULL DEFAULT 'Data',
  options TEXT,
  required INTEGER NOT NULL DEFAULT 0 CHECK (required IN (0,1)),
  "default" TEXT,
  depends_on TEXT,
  user_editable INTEGER NOT NULL DEFAULT 1 CHECK (user_editable IN (0,1)),
  source_field TEXT,
  operator TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(parent) REFERENCES [tabReport](name) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_report_filter_parent
  ON [tabReport Filter](parenttype,parent,parentfield,idx);

CREATE TABLE IF NOT EXISTS [tabReport Column] (
  name TEXT PRIMARY KEY,
  parent TEXT NOT NULL,
  parentfield TEXT NOT NULL DEFAULT 'columns',
  parenttype TEXT NOT NULL DEFAULT 'Report',
  idx INTEGER NOT NULL DEFAULT 0,
  fieldname TEXT NOT NULL,
  label TEXT NOT NULL,
  label_ar TEXT,
  fieldtype TEXT NOT NULL DEFAULT 'Data',
  options TEXT,
  width REAL,
  precision INTEGER,
  alignment TEXT,
  aggregate TEXT,
  hidden INTEGER NOT NULL DEFAULT 0 CHECK (hidden IN (0,1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(parent) REFERENCES [tabReport](name) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_report_column_parent
  ON [tabReport Column](parenttype,parent,parentfield,idx);
''');
  }

  void _registerChildDocTypes(CommonDatabase database, String now) {
    for (final definition in const <Map<String, String>>[
      <String, String>{'name': 'Report Filter', 'table': 'tabReport Filter', 'title': 'label'},
      <String, String>{'name': 'Report Column', 'table': 'tabReport Column', 'title': 'label'},
    ]) {
      database.execute('''
INSERT INTO wmn_doctypes(
  name,module,storage_mode,table_name,id_field,title_field,autoname,
  is_single,is_child,is_submittable,track_changes,allow_create,allow_edit,
  allow_delete,allow_import,allow_export,generic_write,is_system,enabled,
  metadata_json,created_at,updated_at
) VALUES(?,?,?,?,?,?,NULL,0,1,0,0,1,1,1,0,1,1,1,1,?,?,?)
ON CONFLICT(name) DO UPDATE SET
  module=excluded.module,storage_mode='TABLE',table_name=excluded.table_name,
  id_field='name',title_field=excluded.title_field,is_child=1,
  allow_create=1,allow_edit=1,allow_delete=1,generic_write=1,
  is_system=1,enabled=1,metadata_json=excluded.metadata_json,
  updated_at=excluded.updated_at;
''', <Object?>[
        definition['name'],
        'WMN System',
        'TABLE',
        definition['table'],
        'name',
        definition['title'],
        jsonEncode(<String, Object?>{
          'runtime_owned': true,
          'report_child_table': true,
        }),
        now,
        now,
      ]);
    }

    _upsertFields(database, 'Report Filter', const <Map<String, Object?>>[
      {'fieldname': 'fieldname', 'label': 'Field Name', 'fieldtype': 'Data', 'idx': 10, 'reqd': 1, 'list': 1, 'search': 1},
      {'fieldname': 'label', 'label': 'Label', 'fieldtype': 'Data', 'idx': 20, 'reqd': 1, 'list': 1, 'search': 1},
      {'fieldname': 'label_ar', 'label': 'Arabic Label', 'fieldtype': 'Data', 'idx': 30},
      {'fieldname': 'fieldtype', 'label': 'Field Type', 'fieldtype': 'Select', 'options': 'Data\nLink\nDynamic Link\nDate\nDatetime\nSelect\nCheck\nInt\nFloat\nCurrency\nPercent', 'idx': 40, 'reqd': 1, 'list': 1, 'default': 'Data'},
      {'fieldname': 'options', 'label': 'Options', 'fieldtype': 'Small Text', 'idx': 50, 'list': 1},
      {'fieldname': 'required', 'label': 'Required', 'fieldtype': 'Check', 'idx': 60, 'list': 1, 'default': false},
      {'fieldname': 'default', 'label': 'Default', 'fieldtype': 'Data', 'idx': 70},
      {'fieldname': 'depends_on', 'label': 'Depends On', 'fieldtype': 'Data', 'idx': 80},
      {'fieldname': 'user_editable', 'label': 'User Editable', 'fieldtype': 'Check', 'idx': 90, 'default': true},
      {'fieldname': 'source_field', 'label': 'Source Field', 'fieldtype': 'Data', 'idx': 100},
      {'fieldname': 'operator', 'label': 'Operator', 'fieldtype': 'Select', 'options': 'EQ\nNE\nGT\nGTE\nLT\nLTE\nCONTAINS\nSTARTS_WITH\nIS_EMPTY\nIS_NOT_EMPTY', 'idx': 110, 'default': 'EQ'},
    ], now);

    _upsertFields(database, 'Report Column', const <Map<String, Object?>>[
      {'fieldname': 'fieldname', 'label': 'Field Name', 'fieldtype': 'Data', 'idx': 10, 'reqd': 1, 'list': 1, 'search': 1},
      {'fieldname': 'label', 'label': 'Label', 'fieldtype': 'Data', 'idx': 20, 'reqd': 1, 'list': 1, 'search': 1},
      {'fieldname': 'label_ar', 'label': 'Arabic Label', 'fieldtype': 'Data', 'idx': 30},
      {'fieldname': 'fieldtype', 'label': 'Field Type', 'fieldtype': 'Select', 'options': 'Data\nLink\nDynamic Link\nDate\nDatetime\nSelect\nCheck\nInt\nFloat\nCurrency\nPercent', 'idx': 40, 'reqd': 1, 'list': 1, 'default': 'Data'},
      {'fieldname': 'options', 'label': 'Options', 'fieldtype': 'Small Text', 'idx': 50, 'list': 1},
      {'fieldname': 'width', 'label': 'Width', 'fieldtype': 'Float', 'idx': 60},
      {'fieldname': 'precision', 'label': 'Precision', 'fieldtype': 'Int', 'idx': 70},
      {'fieldname': 'alignment', 'label': 'Alignment', 'fieldtype': 'Select', 'options': 'Left\nCenter\nRight', 'idx': 80},
      {'fieldname': 'aggregate', 'label': 'Aggregate', 'fieldtype': 'Select', 'options': 'NONE\nCOUNT\nSUM\nAVG\nMIN\nMAX', 'idx': 90, 'default': 'NONE'},
      {'fieldname': 'hidden', 'label': 'Hidden', 'fieldtype': 'Check', 'idx': 100, 'default': false},
    ], now);
  }

  void _registerReportTableFields(CommonDatabase database, String now) {
    _upsertFields(database, 'Report', const <Map<String, Object?>>[
      {'fieldname': 'filters', 'label': 'Filters', 'fieldtype': 'Table', 'options': 'Report Filter', 'idx': 130},
      {'fieldname': 'columns', 'label': 'Columns', 'fieldtype': 'Table', 'options': 'Report Column', 'idx': 140},
    ], now);
  }

  void _configureReportForm(CommonDatabase database, String now) {
    database.execute('''
UPDATE wmn_doctype_fields SET read_only=0,hidden=0,updated_at=?
WHERE doctype='Report' AND fieldname IN ('report_name','report_type','ref_doctype','module','disabled','script_source_type','script_key','script_language','filters','columns');
''', <Object?>[now]);

    database.execute('''
UPDATE wmn_doctype_fields SET read_only=1,hidden=1,updated_at=?
WHERE doctype='Report' AND fieldname IN (
  'query_source_type','query_source_path','script_source_path',
  'filters_json','columns_json','query_definition_json','metadata_json',
  'created_at','updated_at'
);
''', <Object?>[now]);

    database.execute('''
UPDATE wmn_doctype_fields SET metadata_json=?,updated_at=?
WHERE doctype='Report' AND fieldname='filters';
''', <Object?>[
      jsonEncode(<String, Object?>{
        'description': 'Frappe-style filter rows. Add/edit/reorder filters as child records; JSON editing is no longer required.',
      }),
      now,
    ]);
    database.execute('''
UPDATE wmn_doctype_fields SET metadata_json=?,updated_at=?
WHERE doctype='Report' AND fieldname='columns';
''', <Object?>[
      jsonEncode(<String, Object?>{
        'description': 'Output column rows. Add/edit/reorder columns as child records.',
      }),
      now,
    ]);
    database.execute('''
UPDATE wmn_doctype_fields SET metadata_json=?,updated_at=?
WHERE doctype='Report' AND fieldname='query_source_path';
''', <Object?>[
      jsonEncode(<String, Object?>{
        'description': 'Internal Storage path. The Report form edits Query SQL through the source editor instead.',
        'external_source': true,
      }),
      now,
    ]);
  }

  void _migrateExistingDefinitions(CommonDatabase database, String now) {
    final reports = database.select(
      'SELECT name,report_type,query_definition_json,filters_json,columns_json FROM [tabReport] ORDER BY name;',
    );
    for (final report in reports) {
      final parent = '${report['name']}';
      final filterExists = database.select(
        "SELECT 1 FROM [tabReport Filter] WHERE parent=? AND parenttype='Report' AND parentfield='filters' LIMIT 1;",
        <Object?>[parent],
      ).isNotEmpty;
      final columnExists = database.select(
        "SELECT 1 FROM [tabReport Column] WHERE parent=? AND parenttype='Report' AND parentfield='columns' LIMIT 1;",
        <Object?>[parent],
      ).isNotEmpty;
      final definition = _decodeMap(report['query_definition_json']);
      if (!filterExists) {
        final filters = _decodeList(report['filters_json']);
        final builderFilters = _builderFilterMap(definition);
        for (var index = 0; index < filters.length; index++) {
          final row = filters[index];
          final fieldname = '${row['fieldname'] ?? row['field_name'] ?? row['name'] ?? ''}'.trim();
          if (fieldname.isEmpty) continue;
          final builder = builderFilters[fieldname];
          _insertFilter(database, parent, index + 1, <String, Object?>{
            ...row,
            'source_field': row['source_field'] ?? builder?['field'] ?? fieldname,
            'operator': row['operator'] ?? builder?['operator'] ?? 'EQ',
          }, now);
        }
      }
      if (!columnExists) {
        final columns = _decodeList(report['columns_json']);
        for (var index = 0; index < columns.length; index++) {
          _insertColumn(database, parent, index + 1, columns[index], now);
        }
      }
    }
  }

  void _upgradeScriptExample(CommonDatabase database, String now) {
    database.execute(
      '''UPDATE [tabReport]
         SET columns_json=?, metadata_json=?, updated_at=?
         WHERE name='wmn-example-script-report' OR report_name='Example - Script Report - Module Summary';''',
      <Object?>[
        jsonEncode(const <Map<String, Object?>>[
          <String, Object?>{'fieldname': 'module', 'label': 'Module', 'fieldtype': 'Data'},
          <String, Object?>{'fieldname': 'doctype_count', 'label': 'DocTypes', 'fieldtype': 'Int'},
          <String, Object?>{'fieldname': 'field_count', 'label': 'Fields', 'fieldtype': 'Int'},
          <String, Object?>{'fieldname': 'required_field_count', 'label': 'Required Fields', 'fieldtype': 'Int'},
        ]),
        jsonEncode(<String, Object?>{
          'tutorial_example': true,
          'description': 'A compiled native Script Report that joins DocType metadata with field metadata and returns a module summary.',
          'description_ar': 'تقرير Script مترجم يستخدم JOIN حقيقي بين جدول DocTypes وجدول الحقول ثم يعرض ملخص الوحدات.',
          'creation_steps': <String>[
            'Create a Report and choose Script Report.',
            'Choose a Reference DocType for permission checks.',
            'Define filters and output columns in the child tables.',
            'Use a registered NATIVE_HANDLER key for compiled Dart logic.',
            'The built-in example joins wmn_doctypes and wmn_doctype_fields.',
          ],
          'source_preview': _scriptSourcePreview,
        }),
        now,
      ],
    );

    final rows = database.select(
      "SELECT name FROM [tabReport] WHERE name='wmn-example-script-report' OR report_name='Example - Script Report - Module Summary' LIMIT 1;",
    );
    if (rows.isEmpty) return;
    final parent = '${rows.first['name']}';
    database.execute(
      "DELETE FROM [tabReport Column] WHERE parent=? AND parenttype='Report' AND parentfield='columns';",
      <Object?>[parent],
    );
    for (var index = 0; index < _scriptColumns.length; index++) {
      _insertColumn(database, parent, index + 1, _scriptColumns[index], now);
    }
  }

  void _upsertFields(
    CommonDatabase database,
    String doctype,
    List<Map<String, Object?>> fields,
    String now,
  ) {
    for (final field in fields) {
      final fieldname = '${field['fieldname']}';
      database.execute('''
INSERT INTO wmn_doctype_fields(
  id,doctype,fieldname,label,fieldtype,options,idx,reqd,read_only,hidden,
  in_list_view,in_standard_filter,searchable,allow_on_submit,default_json,
  depends_on,mandatory_depends_on,read_only_depends_on,fetch_from,precision,
  length,metadata_json,created_at,updated_at
) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,0,?,NULL,NULL,NULL,NULL,NULL,NULL,'{}',?,?)
ON CONFLICT(doctype,fieldname) DO UPDATE SET
  label=excluded.label,fieldtype=excluded.fieldtype,options=excluded.options,
  idx=excluded.idx,reqd=excluded.reqd,read_only=excluded.read_only,
  hidden=excluded.hidden,in_list_view=excluded.in_list_view,
  in_standard_filter=excluded.in_standard_filter,searchable=excluded.searchable,
  default_json=excluded.default_json,updated_at=excluded.updated_at;
''', <Object?>[
        'r31512-${_slug(doctype)}-$fieldname',
        doctype,
        fieldname,
        field['label'] ?? fieldname,
        field['fieldtype'] ?? 'Data',
        field['options'],
        field['idx'] ?? 0,
        field['reqd'] == 1 ? 1 : 0,
        field['read_only'] == 1 ? 1 : 0,
        field['hidden'] == 1 ? 1 : 0,
        field['list'] == 1 ? 1 : 0,
        field['filter'] == 1 ? 1 : 0,
        field['search'] == 1 ? 1 : 0,
        field.containsKey('default') ? jsonEncode(field['default']) : null,
        now,
        now,
      ]);
    }
  }

  void _insertFilter(
    CommonDatabase database,
    String parent,
    int idx,
    Map<String, Object?> row,
    String now,
  ) {
    final fieldname = '${row['fieldname'] ?? row['field_name'] ?? row['name'] ?? ''}'.trim();
    if (fieldname.isEmpty) return;
    database.execute('''
INSERT OR REPLACE INTO [tabReport Filter](
  name,parent,parentfield,parenttype,idx,fieldname,label,label_ar,fieldtype,
  options,required,"default",depends_on,user_editable,source_field,operator,
  created_at,updated_at
) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
''', <Object?>[
      '$parent-filter-$idx',
      parent,
      'filters',
      'Report',
      idx,
      fieldname,
      row['label'] ?? fieldname,
      row['label_ar'],
      row['fieldtype'] ?? row['field_type'] ?? 'Data',
      row['options'],
      _truthy(row['required'] ?? row['reqd']) ? 1 : 0,
      row['default'] ?? row['value'],
      row['depends_on'],
      row['user_editable'] == false || row['user_editable'] == 0 ? 0 : 1,
      row['source_field'] ?? fieldname,
      row['operator'] ?? 'EQ',
      now,
      now,
    ]);
  }

  void _insertColumn(
    CommonDatabase database,
    String parent,
    int idx,
    Map<String, Object?> row,
    String now,
  ) {
    final fieldname = '${row['fieldname'] ?? row['field_name'] ?? row['field'] ?? ''}'.trim();
    if (fieldname.isEmpty) return;
    database.execute('''
INSERT OR REPLACE INTO [tabReport Column](
  name,parent,parentfield,parenttype,idx,fieldname,label,label_ar,fieldtype,
  options,width,precision,alignment,aggregate,hidden,created_at,updated_at
) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?);
''', <Object?>[
      '$parent-column-$idx',
      parent,
      'columns',
      'Report',
      idx,
      fieldname,
      row['label'] ?? fieldname,
      row['label_ar'],
      row['fieldtype'] ?? row['field_type'] ?? 'Data',
      row['options'],
      row['width'],
      row['precision'],
      row['alignment'],
      row['aggregate'] ?? 'NONE',
      _truthy(row['hidden']) ? 1 : 0,
      now,
      now,
    ]);
  }

  Map<String, Map<String, Object?>> _builderFilterMap(Map<String, Object?> definition) {
    final result = <String, Map<String, Object?>>{};
    final raw = definition['filters'];
    if (raw is! List) return result;
    for (final entry in raw.whereType<Map>()) {
      final map = <String, Object?>{for (final item in entry.entries) '${item.key}': item.value};
      final field = '${map['field'] ?? ''}'.trim();
      final parameter = '${map['parameter_name'] ?? ''}'.trim();
      final key = parameter.isEmpty ? field : parameter;
      if (key.isNotEmpty) result[key] = map;
    }
    return result;
  }

  Map<String, Object?> _decodeMap(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return <String, Object?>{};
    try {
      final value = jsonDecode(raw);
      if (value is! Map) return <String, Object?>{};
      return <String, Object?>{for (final entry in value.entries) '${entry.key}': entry.value};
    } catch (_) {
      return <String, Object?>{};
    }
  }

  List<Map<String, Object?>> _decodeList(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return <Map<String, Object?>>[];
    try {
      final value = jsonDecode(raw);
      if (value is! List) return <Map<String, Object?>>[];
      return value.whereType<Map>().map((entry) => <String, Object?>{
            for (final item in entry.entries) '${item.key}': item.value,
          }).toList(growable: false);
    } catch (_) {
      return <Map<String, Object?>>[];
    }
  }

  bool _truthy(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return const {'1', 'true', 'yes', 'y', 'on'}.contains('${value ?? ''}'.trim().toLowerCase());
  }

  String _slug(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  static const List<Map<String, Object?>> _scriptColumns = <Map<String, Object?>>[
    <String, Object?>{'fieldname': 'module', 'label': 'Module', 'fieldtype': 'Data'},
    <String, Object?>{'fieldname': 'doctype_count', 'label': 'DocTypes', 'fieldtype': 'Int'},
    <String, Object?>{'fieldname': 'field_count', 'label': 'Fields', 'fieldtype': 'Int'},
    <String, Object?>{'fieldname': 'required_field_count', 'label': 'Required Fields', 'fieldtype': 'Int'},
  ];

  static const String _scriptSourcePreview = r"""final module = '${filters['module'] ?? ''}'.trim();
final rows = database.db.select('''
  SELECT d.module,
         COUNT(DISTINCT d.name) AS doctype_count,
         COUNT(f.id) AS field_count,
         SUM(CASE WHEN f.reqd=1 THEN 1 ELSE 0 END) AS required_field_count
  FROM wmn_doctypes d
  LEFT JOIN wmn_doctype_fields f ON f.doctype = d.name
  WHERE (? = '' OR d.module LIKE '%' || ? || '%')
  GROUP BY d.module
  ORDER BY doctype_count DESC, d.module COLLATE NOCASE
  LIMIT 200;
''', <Object?>[module, module]);""";
}
