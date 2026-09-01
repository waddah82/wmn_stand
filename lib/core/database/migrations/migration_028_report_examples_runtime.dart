import 'dart:convert';

import 'package:sqlite3/common.dart';

import 'database_migration.dart';

/// R3.15.6 report runtime stabilization and built-in learning examples.
///
/// The examples are real Report DocType records. Query SQL starts inline only
/// for migration portability; WmnFrappeReportService.normalizeSources() moves
/// it into WMN Storage on startup so tabReport remains metadata-only.
class Migration028ReportExamplesRuntime implements DatabaseMigration {
  const Migration028ReportExamplesRuntime();

  @override
  int get version => 28;

  @override
  String get name => 'report_examples_runtime';

  @override
  void apply(CommonDatabase database) {
    final now = DateTime.now().toUtc().toIso8601String();

    final builderDefinition = <String, Object?>{
      'source_key': 'doctype:DocType',
      'columns': <Map<String, Object?>>[
        {'field': 'name', 'label': 'DocType', 'aggregate': 'NONE'},
        {'field': 'module', 'label': 'Module', 'aggregate': 'NONE'},
        {'field': 'storage_mode', 'label': 'Storage Mode', 'aggregate': 'NONE'},
        {'field': 'enabled', 'label': 'Enabled', 'aggregate': 'NONE'},
      ],
      'filters': <Map<String, Object?>>[
        {
          'field': 'module',
          'operator': 'CONTAINS',
          'value': 'WMN System',
          'parameter_name': 'module_contains',
          'label': 'Module',
          'label_ar': 'الوحدة',
          'field_type': 'Link',
          'options': 'Module',
          'required': false,
          'user_editable': true,
        },
        {
          'field': 'enabled',
          'operator': 'EQ',
          'value': 1,
          'parameter_name': 'enabled_only',
          'label': 'Enabled',
          'label_ar': 'مفعّل',
          'field_type': 'Check',
          'required': false,
          'user_editable': true,
        },
      ],
      'sorts': <Map<String, Object?>>[
        {'field': 'name', 'descending': false},
      ],
      'limit': 200,
    };

    final builderFilters = <Map<String, Object?>>[
      {
        'fieldname': 'module_contains',
        'label': 'Module',
        'label_ar': 'الوحدة',
        'fieldtype': 'Link',
        'options': 'Module',
        'required': false,
        'default': 'WMN System',
        'user_editable': true,
      },
      {
        'fieldname': 'enabled_only',
        'label': 'Enabled',
        'label_ar': 'مفعّل',
        'fieldtype': 'Check',
        'required': false,
        'default': 1,
        'user_editable': true,
      },
    ];
    final builderColumns = <Map<String, Object?>>[
      {'fieldname': 'name', 'label': 'DocType', 'aggregate': 'NONE'},
      {'fieldname': 'module', 'label': 'Module', 'aggregate': 'NONE'},
      {'fieldname': 'storage_mode', 'label': 'Storage Mode', 'aggregate': 'NONE'},
      {'fieldname': 'enabled', 'label': 'Enabled', 'aggregate': 'NONE'},
    ];

    _upsertReport(
      database,
      id: 'wmn-example-report-builder',
      reportName: 'Example - Report Builder - DocType Catalog',
      reportType: 'Report Builder',
      referenceDocType: 'DocType',
      queryDefinition: builderDefinition,
      filters: builderFilters,
      columns: builderColumns,
      metadata: _exampleMetadata(
        description: 'A no-SQL report that reads DocType metadata through the visual Report Builder model.',
        steps: const <String>[
          'Create a Report and choose Report Builder.',
          'Choose a Reference DocType / source.',
          'Select output columns.',
          'Add optional filters and sorting.',
          'Save the Report and use Show Report. The report opens and runs immediately; use Refresh after changing filters.',
        ],
        notes: const <String>[
          'This example uses DocType as its source.',
          'The Module Contains filter is editable at runtime.',
          'No SQL or script is required.',
        ],
        descriptionAr: 'تقرير بدون SQL يقرأ بيانات DocType عبر نموذج Report Builder المرئي.',
        stepsAr: const <String>[
          'أنشئ Report واختر Report Builder.',
          'اختر Reference DocType / مصدر البيانات.',
          'حدد الأعمدة التي تريد عرضها.',
          'أضف الفلاتر والترتيب عند الحاجة.',
          'احفظ التقرير ثم استخدم عرض التقرير. سيفتح التقرير ويعمل مباشرة؛ استخدم تحديث بعد تغيير الفلاتر.',
        ],
        notesAr: const <String>[
          'هذا المثال يستخدم DocType كمصدر.',
          'فلتر Module Contains قابل للتعديل وقت التشغيل.',
          'لا يحتاج SQL أو Script.',
        ],
      ),
      now: now,
      querySourceType: 'STRUCTURED',
    );

    _upsertReport(
      database,
      id: 'wmn-example-query-report',
      reportName: 'Example - Query Report - DocType Search',
      reportType: 'Query Report',
      referenceDocType: 'DocType',
      queryDefinition: <String, Object?>{
        'sql': '''SELECT name AS doctype, module, storage_mode, enabled, created_at
FROM wmn_doctypes
WHERE (%(module)s = '' OR module LIKE '%' || %(module)s || '%')
  AND (%(doctype)s = '' OR name LIKE '%' || %(doctype)s || '%')
  AND (%(created_from)s = '' OR date(created_at) >= date(%(created_from)s))
  AND (
    %(enabled_state)s = 'All'
    OR (%(enabled_state)s = 'Enabled' AND enabled = 1)
    OR (%(enabled_state)s = 'Disabled' AND enabled = 0)
  )
ORDER BY module COLLATE NOCASE, name COLLATE NOCASE
LIMIT 200''',
        'max_rows': 200,
      },
      filters: const <Map<String, Object?>>[
        {
          'fieldname': 'module',
          'label': 'Module',
          'label_ar': 'الوحدة',
          'fieldtype': 'Link',
          'options': 'Module',
          'required': false,
          'default': 'WMN System',
        },
        {
          'fieldname': 'doctype',
          'label': 'DocType Contains',
          'label_ar': 'اسم DocType يحتوي',
          'fieldtype': 'Data',
          'required': false,
          'default': '',
        },
        {
          'fieldname': 'created_from',
          'label': 'Created From',
          'label_ar': 'تاريخ الإنشاء من',
          'fieldtype': 'Date',
          'required': false,
          'default': '',
        },
        {
          'fieldname': 'enabled_state',
          'label': 'Status',
          'label_ar': 'الحالة',
          'fieldtype': 'Select',
          'options': 'All\nEnabled\nDisabled',
          'required': true,
          'default': 'All',
        },
      ],
      columns: const <Map<String, Object?>>[
        {'fieldname': 'doctype', 'label': 'DocType', 'fieldtype': 'Data'},
        {'fieldname': 'module', 'label': 'Module', 'fieldtype': 'Data'},
        {'fieldname': 'storage_mode', 'label': 'Storage Mode', 'fieldtype': 'Data'},
        {'fieldname': 'enabled', 'label': 'Enabled', 'fieldtype': 'Check'},
        {'fieldname': 'created_at', 'label': 'Created At', 'fieldtype': 'Datetime'},
      ],
      metadata: _exampleMetadata(
        description: 'A safe read-only SQL report. Filter placeholders are compiled to SQLite bound parameters.',
        steps: const <String>[
          'Create a Report and choose Query Report.',
          'Choose a Reference DocType for permission checks.',
          'Define filters and columns.',
          'Provide one read-only SELECT/WITH query.',
          'Use %(filter_name)s placeholders instead of concatenating user values.',
          'Save; WMN externalizes the SQL source into Storage automatically.',
        ],
        notes: const <String>[
          'DML, DDL, PRAGMA, ATTACH and multiple statements are blocked.',
          'This example demonstrates Link, Data, Date and Select runtime filters; all Query values are bound parameters.',
        ],
        descriptionAr: 'تقرير SQL آمن للقراءة فقط، وتتحول قيم الفلاتر إلى Bound Parameters في SQLite.',
        stepsAr: const <String>[
          'أنشئ Report واختر Query Report.',
          'اختر Reference DocType لتطبيق الصلاحيات.',
          'عرّف الفلاتر والأعمدة.',
          'اكتب استعلام SELECT أو WITH واحدًا للقراءة فقط.',
          'استخدم %(filter_name)s بدل دمج قيم المستخدم داخل SQL.',
          'احفظ التقرير وسيقوم WMN بنقل SQL تلقائيًا إلى Storage.',
        ],
        notesAr: const <String>[
          'أوامر التعديل والإنشاء وPRAGMA وATTACH وتعدد الاستعلامات ممنوعة.',
          'هذا المثال يعرض فلاتر Link وData وDate وSelect، وجميع قيم Query تمر كـBound Parameters.',
        ],
      ),
      now: now,
      querySourceType: 'INLINE',
    );

    _upsertReport(
      database,
      id: 'wmn-example-script-report',
      reportName: 'Example - Script Report - Module Summary',
      reportType: 'Script Report',
      referenceDocType: 'DocType',
      queryDefinition: const <String, Object?>{},
      filters: const <Map<String, Object?>>[
        {
          'fieldname': 'module',
          'label': 'Module',
          'label_ar': 'الوحدة',
          'fieldtype': 'Link',
          'options': 'Module',
          'required': false,
          'default': '',
        },
      ],
      columns: const <Map<String, Object?>>[
        {'fieldname': 'module', 'label': 'Module', 'fieldtype': 'Data'},
        {'fieldname': 'doctype_count', 'label': 'DocTypes', 'fieldtype': 'Int'},
        {'fieldname': 'enabled_count', 'label': 'Enabled', 'fieldtype': 'Int'},
      ],
      metadata: _exampleMetadata(
        description: 'A compiled native Script Report that calculates a module summary through a registered handler.',
        steps: const <String>[
          'Create a Report and choose Script Report.',
          'Choose a Reference DocType for permission checks.',
          'Define filters and output columns.',
          'For native code, set Script Source Type to NATIVE_HANDLER and provide a registered handler key.',
          'For managed WMN scripts, use STORAGE_FILE plus a registered managed language/executor.',
          'Save and use Show Report; the report executes immediately.',
        ],
        notes: const <String>[
          'Arbitrary Dart, Python or JavaScript is not executed dynamically.',
          'This example uses the built-in handler wmn.examples.reports.module_summary.',
        ],
        descriptionAr: 'تقرير Script يستخدم Native Handler مترجمًا ومسجلًا لحساب ملخص الوحدات.',
        stepsAr: const <String>[
          'أنشئ Report واختر Script Report.',
          'اختر Reference DocType لتطبيق الصلاحيات.',
          'عرّف الفلاتر والأعمدة الناتجة.',
          'للكود الأصلي اختر NATIVE_HANDLER وأدخل Handler Key مسجلًا.',
          'لـManaged Script استخدم STORAGE_FILE مع لغة وExecutor مسجلين.',
          'احفظ التقرير ثم استخدم عرض التقرير؛ وسيعمل مباشرة.',
        ],
        notesAr: const <String>[
          'لا يتم تشغيل Dart أو Python أو JavaScript عشوائيًا أثناء التشغيل.',
          'هذا المثال يستخدم handler مدمجًا: wmn.examples.reports.module_summary.',
        ],
      ),
      now: now,
      scriptKey: 'wmn.examples.reports.module_summary',
      scriptSourceType: 'NATIVE_HANDLER',
    );

    _setFieldDescription(
      database,
      'report_type',
      'Choose Report Builder for no-SQL reports, Query Report for safe read-only SQL, or Script Report for registered native/managed logic.',
    );
    _setFieldDescription(
      database,
      'ref_doctype',
      'DocType used as the report subject and permission boundary.',
    );
    _setFieldDescription(
      database,
      'filters_json',
      'Frappe-style runtime filters. Each filter may define fieldname, label, fieldtype, options, required/reqd, default and depends_on. Link, Dynamic Link, Date, Select, Check and numeric filters render natively.',
    );
    _setFieldDescription(
      database,
      'columns_json',
      'Output column definitions using fieldname, label and fieldtype.',
    );
    _setFieldDescription(
      database,
      'query_definition_json',
      'Structured Report Builder definition or Query Report options such as max_rows. Query SQL is externalized to Storage.',
    );
    _setFieldDescription(
      database,
      'script_key',
      'Registered native handler key for Script Reports using NATIVE_HANDLER.',
    );
  }

  static Map<String, Object?> _exampleMetadata({
    required String description,
    required List<String> steps,
    required List<String> notes,
    required String descriptionAr,
    required List<String> stepsAr,
    required List<String> notesAr,
  }) => <String, Object?>{
        'tutorial_example': true,
        'description': description,
        'creation_steps': steps,
        'notes': notes,
        'description_ar': descriptionAr,
        'creation_steps_ar': stepsAr,
        'notes_ar': notesAr,
      };

  static void _upsertReport(
    CommonDatabase database, {
    required String id,
    required String reportName,
    required String reportType,
    required String referenceDocType,
    required Map<String, Object?> queryDefinition,
    required List<Map<String, Object?>> filters,
    required List<Map<String, Object?>> columns,
    required Map<String, Object?> metadata,
    required String now,
    String querySourceType = 'INLINE',
    String? scriptKey,
    String scriptSourceType = 'NATIVE_HANDLER',
  }) {
    database.execute('''
      INSERT INTO [tabReport](
        name,report_name,ref_doctype,report_type,module,is_standard,disabled,
        query_definition_json,script_key,filters_json,columns_json,metadata_json,
        created_at,updated_at,query_source_type,query_source_path,
        script_source_type,script_source_path,script_language
      ) VALUES (?,?,?,?,?,1,0,?,?,?,?,?,?,?,?,NULL,?,NULL,NULL)
      ON CONFLICT(name) DO UPDATE SET
        report_name=excluded.report_name,ref_doctype=excluded.ref_doctype,
        report_type=excluded.report_type,module=excluded.module,is_standard=1,
        disabled=0,query_definition_json=excluded.query_definition_json,
        script_key=excluded.script_key,filters_json=excluded.filters_json,
        columns_json=excluded.columns_json,metadata_json=excluded.metadata_json,
        query_source_type=excluded.query_source_type,
        script_source_type=excluded.script_source_type,updated_at=excluded.updated_at;
    ''', <Object?>[
      id,
      reportName,
      referenceDocType,
      reportType,
      'WMN System',
      jsonEncode(queryDefinition),
      scriptKey,
      jsonEncode(filters),
      jsonEncode(columns),
      jsonEncode(metadata),
      now,
      now,
      querySourceType,
      scriptSourceType,
    ]);
  }

  static void _setFieldDescription(
    CommonDatabase database,
    String fieldName,
    String description,
  ) {
    final rows = database.select(
      'SELECT metadata_json FROM wmn_doctype_fields WHERE doctype=? AND fieldname=? LIMIT 1;',
      <Object?>['Report', fieldName],
    );
    if (rows.isEmpty) return;
    final raw = '${rows.first['metadata_json'] ?? '{}'}';
    Map<String, Object?> metadata = <String, Object?>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        metadata = <String, Object?>{
          for (final entry in decoded.entries) '${entry.key}': entry.value,
        };
      }
    } catch (_) {
      metadata = <String, Object?>{};
    }
    metadata['description'] = description;
    database.execute(
      'UPDATE wmn_doctype_fields SET metadata_json=?,updated_at=? WHERE doctype=? AND fieldname=?;',
      <Object?>[
        jsonEncode(metadata),
        DateTime.now().toUtc().toIso8601String(),
        'Report',
        fieldName,
      ],
    );
  }
}
