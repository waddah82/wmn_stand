import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

final List<String> errors = <String>[];
final List<String> warnings = <String>[];
late final Directory root;

void requireCheck(bool condition, String message) {
  if (!condition) errors.add(message);
}

String readText(String relative) {
  final file = File('${root.path}${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}');
  if (!file.existsSync()) {
    errors.add('missing file: $relative');
    return '';
  }
  return file.readAsStringSync();
}

Iterable<File> filesUnder(String relative, {String? extension}) sync* {
  final dir = Directory('${root.path}${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}');
  if (!dir.existsSync()) return;
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (extension == null || entity.path.endsWith(extension)) yield entity;
  }
}

String relativePath(File file) {
  final prefix = '${root.path}${Platform.pathSeparator}';
  return file.path.startsWith(prefix) ? file.path.substring(prefix.length) : file.path;
}

void verifyLocalizationHasNoDuplicateKeys() {
  final source = readText('lib/core/localization/wmn_localization.dart');
  if (source.isEmpty) return;

  String? language;
  final seen = <String, Map<String, int>>{};
  final duplicates = <String>[];
  final lines = const LineSplitter().convert(source);
  final languagePattern = RegExp(r"^\s*'(en|ar)'\s*:\s*\{");
  final keyPattern = RegExp(r"^\s*'([^']+)'\s*:");

  for (var index = 0; index < lines.length; index++) {
    final languageMatch = languagePattern.firstMatch(lines[index]);
    if (languageMatch != null) {
      language = languageMatch.group(1);
      seen.putIfAbsent(language!, () => <String, int>{});
      continue;
    }
    if (language == null) continue;
    final keyMatch = keyPattern.firstMatch(lines[index]);
    if (keyMatch == null) continue;
    final key = keyMatch.group(1)!;
    final previous = seen[language]![key];
    if (previous != null) {
      duplicates.add('$language:$key at lines $previous and ${index + 1}');
    } else {
      seen[language]![key] = index + 1;
    }
  }

  requireCheck(duplicates.isEmpty, 'duplicate localization keys: ${duplicates.join(', ')}');
}

void verifyRelativeImports() {
  final importPattern = RegExp(r'''^import\s+['"]([^'"]+)['"]''', multiLine: true);
  for (final file in filesUnder('lib', extension: '.dart')) {
    final source = file.readAsStringSync();
    for (final match in importPattern.allMatches(source)) {
      final target = match.group(1)!;
      if (target.startsWith('dart:') || target.startsWith('package:')) continue;
      final candidate = File('${file.parent.path}${Platform.pathSeparator}$target').absolute;
      requireCheck(candidate.existsSync(), 'missing import $target from ${relativePath(file)}');
    }
  }
}

void verifyPlatformSchema() {
  final file = File(
    '${root.path}${Platform.pathSeparator}database${Platform.pathSeparator}reference'
    '${Platform.pathSeparator}wmn_platform_schema_v36.sqlite3',
  );
  requireCheck(file.existsSync(), 'clean platform schema v36 reference database missing');
  final schemaDump = File(
    '${root.path}${Platform.pathSeparator}database${Platform.pathSeparator}reference'
    '${Platform.pathSeparator}schema_platform_v36.sql',
  );
  requireCheck(schemaDump.existsSync(), 'clean platform schema v36 SQL dump missing');
  if (!file.existsSync()) return;

  final db = sqlite3.open(file.path, mode: OpenMode.readOnly);
  try {
    final versionRows = db.select("SELECT value FROM system_meta WHERE key='schema_version' LIMIT 1;");
    final version = versionRows.isEmpty ? null : '${versionRows.first['value']}';
    requireCheck(version == '36', 'reference DB schema_version=$version, expected 36');

    final generalReportRows = db.select(
      "SELECT template_text,metadata_json FROM print_formats WHERE code='WMN-GENERAL-REPORT' LIMIT 1;",
    );
    requireCheck(generalReportRows.length == 1, 'General Report Print Format is missing');
    if (generalReportRows.isNotEmpty) {
      final template = '${generalReportRows.first['template_text']}';
      final metadata = '${generalReportRows.first['metadata_json']}';
      requireCheck(template.contains('{{ report.table }}'), 'General Report Print Format does not use structured report.table marker');
      requireCheck(template.contains('{{ report.filters_block }}'), 'General Report Print Format does not expose report filter block');
      requireCheck(metadata.contains('structured_report'), 'General Report Print Format structured_report metadata is missing');
    }

    final docTypeRows = db.select("SELECT table_name,generic_write FROM wmn_doctypes WHERE name='DocType' LIMIT 1;");
    requireCheck(docTypeRows.length == 1, 'DocType System DocType registration missing');
    if (docTypeRows.isNotEmpty) {
      requireCheck('${docTypeRows.first['table_name']}' == 'wmn_doctypes', 'DocType does not map to wmn_doctypes');
      requireCheck('${docTypeRows.first['generic_write']}' == '0', 'DocType registry must remain read-only through generic forms');
    }
    final roleCodeRows = db.select("SELECT reqd,read_only,hidden FROM wmn_doctype_fields WHERE doctype='Role' AND fieldname='code' LIMIT 1;");
    requireCheck(roleCodeRows.length == 1, 'Role.code metadata missing');
    if (roleCodeRows.isNotEmpty) {
      requireCheck('${roleCodeRows.first['reqd']}' == '1' && '${roleCodeRows.first['read_only']}' == '0' && '${roleCodeRows.first['hidden']}' == '0', 'Role.code must be required, editable and visible');
    }

    final reportTableFields = db.select("SELECT fieldname,fieldtype,options,read_only,hidden FROM wmn_doctype_fields WHERE doctype='Report' AND fieldname IN ('filters','columns') ORDER BY fieldname;");
    requireCheck(reportTableFields.length == 2, 'Report Filters/Columns child-table fields are missing');
    requireCheck(reportTableFields.every((row) => row['fieldtype'] == 'Table' && row['read_only'] == 0 && row['hidden'] == 0), 'Report Filters/Columns must be editable visible Table fields');
    final legacyReportJsonFields = db.select("SELECT fieldname,read_only,hidden FROM wmn_doctype_fields WHERE doctype='Report' AND fieldname IN ('filters_json','columns_json','query_definition_json') ORDER BY fieldname;");
    requireCheck(legacyReportJsonFields.length == 3 && legacyReportJsonFields.every((row) => row['read_only'] == 1 && row['hidden'] == 1), 'legacy Report JSON authoring fields must remain hidden/read-only compatibility snapshots');
    final reportChildren = db.select("SELECT name,is_child,table_name FROM wmn_doctypes WHERE name IN ('Report Filter','Report Column') ORDER BY name;");
    requireCheck(reportChildren.length == 2 && reportChildren.every((row) => row['is_child'] == 1), 'Report Filter/Report Column child DocTypes are missing');
    requireCheck(db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='tabReport Filter';").isNotEmpty, 'tabReport Filter table missing');
    requireCheck(db.select("SELECT 1 FROM sqlite_master WHERE type='table' AND name='tabReport Column';").isNotEmpty, 'tabReport Column table missing');

    final exampleReports = db.select("SELECT report_name,report_type,script_key,metadata_json FROM [tabReport] WHERE name LIKE 'wmn-example-%' ORDER BY name;");
    requireCheck(exampleReports.length == 3, 'three built-in Report learning examples are required');
    final exampleTypes = exampleReports.map((row) => '${row['report_type']}').toSet();
    requireCheck(exampleTypes.containsAll(<String>{'Report Builder','Query Report','Script Report'}), 'Report learning examples do not cover all three primary types');
    requireCheck(exampleReports.every((row) => '${row['metadata_json']}'.contains('tutorial_example')), 'Report examples are missing tutorial metadata');
    requireCheck(exampleReports.any((row) => row['report_type'] == 'Script Report' && row['script_key'] == 'wmn.examples.reports.module_summary'), 'built-in Script Report example handler key missing');
    final exampleFilters = db.select("SELECT report_type,filters_json FROM [tabReport] WHERE name LIKE 'wmn-example-%';");
    final filterSurface = exampleFilters.map((row) => '${row['filters_json']}').join('\n');
    requireCheck(filterSurface.contains('"fieldtype": "Link"') || filterSurface.contains('"fieldtype":"Link"'), 'Report examples must demonstrate Link filters');
    requireCheck(filterSurface.contains('"fieldtype": "Check"') || filterSurface.contains('"fieldtype":"Check"'), 'Report examples must demonstrate Check filters');
    requireCheck(filterSurface.contains('"fieldtype": "Date"') || filterSurface.contains('"fieldtype":"Date"'), 'Report examples must demonstrate Date filters');
    requireCheck(filterSurface.contains('"fieldtype": "Select"') || filterSurface.contains('"fieldtype":"Select"'), 'Report examples must demonstrate Select filters');

    final integrityRows = db.select('PRAGMA integrity_check;');
    final integrity = integrityRows.isEmpty ? null : '${integrityRows.first.values.first}';
    requireCheck(integrity == 'ok', 'SQLite integrity_check=$integrity');
    requireCheck(db.select('PRAGMA foreign_key_check;').isEmpty, 'reference DB has foreign-key violations');

    final tables = db
        .select("SELECT name FROM sqlite_master WHERE type='table';")
        .map((row) => '${row['name']}')
        .toSet();
    const requiredTables = <String>{
      'system_meta',
      'app_settings',
      'audit_log',
      'numbering_series',
      'wmn_modules',
      'wmn_doctypes',
      'wmn_doctype_fields',
      'wmn_doctype_permissions',
      'wmn_document_versions',
      'wmn_method_bindings',
      'wmn_hook_bindings',
      'wmn_app_packages',
      'wmn_app_source_units',
      'tabSingles',
      'tabUser',
      'tabWorkspace',
      'wmn_workspace_items',
      'tabWorkspaceItem',
      'tabReport',
      'tabReport Filter',
      'tabReport Column',
      'wmn_storage_blobs',
      'file_settings',
      'data_import_jobs',
      'data_export_jobs',
      'print_formats',
      'print_settings',
      'print_jobs',
      'tabLetter Head',
      'wmn_scoped_settings',
      'wmn_system_logs',
      'wmn_schedules',
      'wmn_notifications',
      'wmn_workflows',
      'wmn_workflow_states',
      'wmn_workflow_transitions',
      'wmn_workflow_actions',
      'tabPage',
      'wmn_printers',
      'wmn_features',
      'wmn_feature_entitlements',
      'wmn_feature_activations',
    };
    final missing = requiredTables.difference(tables).toList()..sort();
    requireCheck(missing.isEmpty, 'platform schema missing tables: $missing');
    for (final legacy in const <String>{'custom_reports','wmn_script_reports','wmn_file_contents'}) {
      requireCheck(!tables.contains(legacy), 'legacy parallel storage table remains: $legacy');
    }
    final reportColumns = db.select('PRAGMA table_info("tabReport");').map((row) => '${row['name']}').toSet();
    requireCheck(reportColumns.containsAll(<String>{'query_source_type','query_source_path','script_source_type','script_source_path','script_language'}), 'Report DocType source metadata columns missing');
    final sourceColumns = db.select('PRAGMA table_info(wmn_app_source_units);').map((row) => '${row['name']}').toSet();
    requireCheck(sourceColumns.containsAll(<String>{'source_storage_path','converted_storage_path'}), 'application source storage paths missing');
    requireCheck(!sourceColumns.contains('source_code') && !sourceColumns.contains('converted_code'), 'application source code still stored in relational columns');
    for (final table in const <String>['client_scripts','server_scripts']) {
      final columns = db.select('PRAGMA table_info("$table");').map((row) => '${row['name']}').toSet();
      requireCheck(columns.contains('source_storage_path'), '$table source storage path missing');
      requireCheck(!columns.contains('script'), '$table still stores script source in SQLite');
    }
    final reportFieldRows = db.select('''
      SELECT fieldname,fieldtype,options,searchable
      FROM wmn_doctype_fields
      WHERE doctype='Report' AND fieldname IN ('ref_doctype','module');
    ''');
    final reportFields = <String, Map<String, Object?>>{
      for (final row in reportFieldRows) '${row['fieldname']}': Map<String, Object?>.from(row),
    };
    requireCheck(reportFields['ref_doctype']?['fieldtype'] == 'Link' && reportFields['ref_doctype']?['options'] == 'DocType', 'Report.ref_doctype is not a Link to DocType');
    requireCheck(reportFields['module']?['fieldtype'] == 'Link' && reportFields['module']?['options'] == 'Module', 'Report.module is not a Link to Module');

    const forbiddenBusinessTables = <String>{
      'tabAccount',
      'tabBranch',
      'tabCompany',
      'tabCoupon',
      'tabCustomer',
      'tabItem',
      'tabItem Group',
      'tabJournal Entry',
      'tabJournal Entry Account',
      'tabPayment Entry',
      'tabPayment Entry Reference',
      'tabPOS Profile',
      'tabPricing Rule',
      'tabPromotion',
      'tabPurchase Document',
      'tabSales Invoice',
      'tabSales Invoice Item',
      'tabStock Ledger Entry',
      'tabSupplier',
      'tabUOM',
      'tabWarehouse',
      'wmn_erp_source_parity',
      'wmn_core_foundation_state',
      'wmn_core_port_map',
      'cash_sessions',
      'cash_movements',
      'payments',
    };
    final forbidden = forbiddenBusinessTables.intersection(tables).toList()..sort();
    requireCheck(forbidden.isEmpty, 'business application tables exist in clean platform reference DB: $forbidden');

    final doctypes = db.select('SELECT name,module FROM wmn_doctypes;');
    final doctypeNames = doctypes.map((row) => '${row['name']}').toSet();
    requireCheck(!doctypeNames.contains('POS Profile'), 'POS Profile must not be a WMN System DocType');
    requireCheck(!doctypeNames.contains('Sales Invoice'), 'Sales Invoice must not be a WMN System DocType');
    requireCheck(!doctypeNames.contains('Customer'), 'Customer must not be a WMN System DocType');
    requireCheck(!doctypeNames.contains('Account'), 'Account must not be a WMN System DocType');
    final userRows = doctypes.where((row) => '${row['name']}' == 'User').toList(growable: false);
    requireCheck(userRows.isNotEmpty && '${userRows.first['module']}' == 'Security', 'User DocType must belong to the Security system module');


    const requiredSystemDocTypes = <String>{
      'User','Role','Permission','User Role','Application','Module','Page','Workspace',
      'Report','Print Format','Print Settings','Printer','Print Job','Notification','Scheduled Job',
      'File','File Settings','System Setting','System Log','Audit Log','Background Job',
      'Feature','Feature Entitlement','Feature Activation',
      'Role Permission','DocType Permission','User Permission','Document Share',
      'Workflow','Workflow State','Workflow Transition','Workflow Action',
    };
    final missingSystemDocTypes = requiredSystemDocTypes.difference(doctypeNames).toList()..sort();
    requireCheck(missingSystemDocTypes.isEmpty, 'system DocType foundation incomplete: $missingSystemDocTypes');
    final reportMeta = db.select("SELECT metadata_json FROM wmn_doctypes WHERE name='Report' LIMIT 1;");
    requireCheck(
      reportMeta.isNotEmpty && '${reportMeta.first['metadata_json']}'.contains('Query Report') && '${reportMeta.first['metadata_json']}'.contains('Script Report'),
      'Report System DocType must expose Query Report and Script Report types',
    );
    final pageMeta = db.select("SELECT metadata_json FROM wmn_doctypes WHERE name='Page' LIMIT 1;");
    requireCheck(
      pageMeta.isNotEmpty &&
          '${pageMeta.first['metadata_json']}'.contains('WMN_PAGE_RUNTIME') &&
          '${pageMeta.first['metadata_json']}'.contains('CUSTOM'),
      'Page System DocType runtime metadata is incomplete',
    );
    final pageFields = db
        .select("SELECT fieldname FROM wmn_doctype_fields WHERE doctype='Page';")
        .map((row) => '${row['fieldname']}')
        .toSet();
    requireCheck(
      pageFields.containsAll(<String>{
        'name','title','route','app_name','module','page_type','controller_key',
        'roles_json','permissions_json','enabled','metadata_json',
      }),
      'Page System DocType physical metadata fields are incomplete',
    );
    requireCheck(
      db.select("SELECT 1 FROM wmn_doctype_permissions WHERE doctype='Page' AND role='System Manager' AND can_read=1 AND can_write=1 LIMIT 1;").isNotEmpty,
      'Page System DocType System Manager permission seed missing',
    );
    final securityPermissionRows = db.select(
      "SELECT id,code FROM permissions WHERE code='wmn.security.manage' LIMIT 1;",
    );
    requireCheck(
      securityPermissionRows.isNotEmpty,
      'wmn.security.manage system permission seed missing',
    );

    final featureRows = db.select('SELECT code,is_core,user_toggleable FROM wmn_features WHERE enabled=1;');
    requireCheck(featureRows.any((row) => row['code']=='core.platform' && row['is_core']==1 && row['user_toggleable']==0), 'core feature protection seed missing');
    requireCheck(featureRows.any((row) => row['code']=='reports.query'), 'query-report feature seed missing');
    requireCheck(featureRows.any((row) => row['code']=='reports.script'), 'script-report feature seed missing');
    requireCheck(
      featureRows.any(
        (row) =>
            row['code'] == 'workflow.approvals' &&
            row['is_core'] == 0 &&
            row['user_toggleable'] == 1,
      ),
      'workflow approval feature must remain optional and user-toggleable',
    );
    final workflowDoctypes = db
        .select("SELECT name FROM wmn_doctypes WHERE name LIKE 'Workflow%';")
        .map((row) => '${row['name']}')
        .toSet();
    requireCheck(
      workflowDoctypes.containsAll(<String>{
        'Workflow','Workflow State','Workflow Transition','Workflow Action',
      }),
      'workflow System DocType metadata is incomplete',
    );
    final workflowMeta = db.select(
      "SELECT name,autoname,generic_write FROM wmn_doctypes WHERE name LIKE 'Workflow%' ORDER BY name;",
    );
    requireCheck(
      workflowMeta.any(
            (row) =>
                row['name'] == 'Workflow' && row['autoname'] == 'field:name',
          ) &&
          workflowMeta.any(
            (row) =>
                row['name'] == 'Workflow State' &&
                row['autoname'] == 'format:WFS-.#####',
          ) &&
          workflowMeta.any(
            (row) =>
                row['name'] == 'Workflow Transition' &&
                row['autoname'] == 'format:WFT-.#####',
          ),
      'workflow metadata IDs are not backed by the native naming engine',
    );
    requireCheck(
      workflowMeta.any(
        (row) => row['name'] == 'Workflow Action' && row['generic_write'] == 0,
      ),
      'Workflow Action history must remain read-only metadata',
    );
    requireCheck(
      db.select("SELECT 1 FROM permissions WHERE code='wmn.workflow.manage' LIMIT 1;").isNotEmpty,
      'wmn.workflow.manage system permission seed missing',
    );
    requireCheck(
      db.select('SELECT doctype,COUNT(*) AS c FROM wmn_workflows WHERE enabled=1 GROUP BY doctype HAVING COUNT(*)>1;').isEmpty,
      'reference database contains multiple enabled workflows for one DocType',
    );
    final coreFeature = db.select("SELECT capability_ids_json FROM wmn_features WHERE code='core.platform' LIMIT 1;");
    requireCheck(
      coreFeature.isNotEmpty &&
          '${coreFeature.first['capability_ids_json']}'.contains('page-runtime') &&
          '${coreFeature.first['capability_ids_json']}'.contains('page-controllers'),
      'core platform feature does not include Page runtime capabilities',
    );

    final modules = db.select('SELECT name FROM wmn_modules;').map((row) => '${row['name']}').toSet();
    requireCheck(modules.containsAll(<String>{'WMN System', 'Security', 'Workflow'}), 'platform module registry seed is incomplete');
    requireCheck(!modules.any(<String>{'Accounts', 'Selling', 'Buying', 'Stock', 'Setup'}.contains), 'business modules remain system-owned');

    final numberingColumns = db.select('PRAGMA table_info(numbering_series);').map((row) => '${row['name']}').toSet();
    requireCheck(numberingColumns.containsAll(<String>{'scope_type', 'scope_value'}), 'numbering_series is not application-neutral');
    requireCheck(!numberingColumns.contains('company_id') && !numberingColumns.contains('branch_id'), 'numbering_series still depends on ERP business scope');

    final userRoleColumns = db.select('PRAGMA table_info(user_roles);').map((row) => '${row['name']}').toSet();
    requireCheck(userRoleColumns.containsAll(<String>{'scope_type', 'scope_value'}), 'user_roles scope is not application-neutral');
    requireCheck(!userRoleColumns.contains('company_id') && !userRoleColumns.contains('branch_id'), 'user_roles still depends on Company/Branch');

    final printJobColumns = db.select('PRAGMA table_info(print_jobs);').map((row) => '${row['name']}').toSet();
    requireCheck(printJobColumns.containsAll(<String>{'document_type', 'document_name'}), 'print_jobs is not generic document-based storage');
    requireCheck(!printJobColumns.contains('invoice_id'), 'print_jobs still depends on Sales Invoice');
    requireCheck(
      printJobColumns.containsAll(<String>{'source_type','print_format_id','printer_id','renderer_id','output_file_id','mime_type','byte_count','request_json'}),
      'print_jobs v30 runtime columns are incomplete',
    );
    final printFormatColumns = db.select('PRAGMA table_info(print_formats);').map((row) => '${row['name']}').toSet();
    requireCheck(
      printFormatColumns.containsAll(<String>{'target_type','document_type','report_name','renderer_id','template_text','css_text','is_default','paper_width_mm','paper_height_mm','margin_mm','letter_head_id','default_print_language','font_family','pdf_generator'}),
      'Print Format canonical HTML/Frappe runtime columns are incomplete',
    );
    final printJobDocType = db.select("SELECT generic_write FROM wmn_doctypes WHERE name='Print Job' LIMIT 1;");
    requireCheck(printJobDocType.length == 1 && printJobDocType.first['generic_write'] == 0, 'Print Job must be a runtime-owned read-only System DocType');
    final letterHeadDocType = db.select("SELECT table_name,generic_write FROM wmn_doctypes WHERE name='Letter Head' AND enabled=1 LIMIT 1;");
    requireCheck(
      letterHeadDocType.length == 1 &&
          '${letterHeadDocType.first['table_name']}' == 'tabLetter Head' &&
          letterHeadDocType.first['generic_write'] == 1,
      'Letter Head must be a first-class editable System DocType',
    );
    final generatorTables = <String>{
      for (final row in db.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('tabApplication Build Profile','tabApplication Build');",
      ))
        '${row['name']}',
    };
    requireCheck(
      generatorTables.containsAll(
        <String>{'tabApplication Build Profile', 'tabApplication Build'},
      ),
      'Application Generator build profile/history tables are missing from schema v36',
    );
    final generatorDocTypes = db.select(
      "SELECT name,table_name,is_system FROM wmn_doctypes WHERE name IN ('Application Build Profile','Application Build');",
    );
    requireCheck(
      generatorDocTypes.length == 2 &&
          generatorDocTypes.every(
            (row) => (row['is_system'] as num?)?.toInt() == 1,
          ),
      'Application Generator System DocTypes are not registered',
    );
    final printSettingsColumns = db.select('PRAGMA table_info(print_settings);').map((row) => '${row['name']}').toSet();
    requireCheck(
      printSettingsColumns.containsAll(<String>{'default_letter_head_id','default_print_language'}),
      'Print Settings Letter Head/language defaults are missing',
    );
    final seededFormats = db.select("SELECT code,target_type,renderer_id FROM print_formats WHERE code IN ('WMN-PLATFORM-DEFAULT','WMN-GENERAL-REPORT') ORDER BY code;");
    requireCheck(seededFormats.length == 2, 'v30 platform/general Print Format seeds are missing');
    final defaultSettings = db.select("SELECT default_document_format_id,general_report_format_id FROM print_settings WHERE name='Default' AND enabled=1 LIMIT 1;");
    requireCheck(
      defaultSettings.length == 1 &&
          '${defaultSettings.first['default_document_format_id']}' == 'print-format-platform-default' &&
          '${defaultSettings.first['general_report_format_id']}' == 'print-format-general-report',
      'Default Print Settings fallback links are incomplete',
    );
    final advancedPrinting = db.select("SELECT id,enabled,metadata_json FROM wmn_features WHERE code='printing.advanced' LIMIT 1;");
    requireCheck(advancedPrinting.length == 1 && advancedPrinting.first['enabled'] == 1, 'printing.advanced feature registration is missing');

    final fileColumns = db.select('PRAGMA table_info(wmn_files);').map((row) => '${row['name']}').toSet();
    requireCheck(
      fileColumns.containsAll(<String>{
        'mime_type','source_adapter','storage_adapter','content_mode','source_reference','state',
      }),
      'Files & Attachments v31 metadata columns are incomplete',
    );
    final fileDocType = db.select("SELECT allow_create,allow_edit,allow_delete,generic_write,metadata_json FROM wmn_doctypes WHERE name='File' LIMIT 1;");
    requireCheck(
      fileDocType.length == 1 &&
          fileDocType.first['allow_create'] == 0 &&
          fileDocType.first['allow_edit'] == 0 &&
          fileDocType.first['allow_delete'] == 0 &&
          fileDocType.first['generic_write'] == 0 &&
          '${fileDocType.first['metadata_json']}'.contains('storage_optional'),
      'File must remain runtime-owned while storage mode stays optional',
    );
    final fileSettingsDocType = db.select("SELECT table_name,allow_create,allow_edit,allow_delete,generic_write FROM wmn_doctypes WHERE name='File Settings' LIMIT 1;");
    requireCheck(
      fileSettingsDocType.length == 1 &&
          '${fileSettingsDocType.first['table_name']}' == 'file_settings' &&
          fileSettingsDocType.first['allow_create'] == 0 &&
          fileSettingsDocType.first['allow_edit'] == 1 &&
          fileSettingsDocType.first['allow_delete'] == 0 &&
          fileSettingsDocType.first['generic_write'] == 1,
      'File Settings System DocType registration is incomplete',
    );
    requireCheck(
      db.select("SELECT 1 FROM wmn_doctype_permissions WHERE doctype='File Settings' AND role='System Manager' AND can_read=1 AND can_write=1 AND can_create=0 AND can_delete=0 LIMIT 1;").isNotEmpty,
      'File Settings must be explicitly managed by System Manager',
    );
    final fileSettings = db.select("SELECT default_content_mode,allow_external_reference FROM file_settings WHERE id='default' LIMIT 1;");
    requireCheck(
      fileSettings.length == 1 &&
          '${fileSettings.first['default_content_mode']}' == 'MANAGED_STORAGE' &&
          fileSettings.first['allow_external_reference'] == 1,
      'Default File Settings must preserve Managed Storage as a configurable default with External Reference enabled',
    );
    final fileModeFields = db.select("SELECT fieldname,fieldtype,options,read_only FROM wmn_doctype_fields WHERE doctype='File' AND fieldname IN ('content_mode','source_reference','storage_adapter','state') ORDER BY fieldname;");
    requireCheck(fileModeFields.length == 4 && fileModeFields.every((row) => row['read_only'] == 1), 'File runtime metadata fields must remain read-only through generic forms');

    final workspaceItemsField = db.select("SELECT fieldtype,options,read_only,hidden FROM wmn_doctype_fields WHERE doctype='Workspace' AND fieldname='items' LIMIT 1;");
    requireCheck(
      workspaceItemsField.length == 1 &&
          '${workspaceItemsField.first['fieldtype']}' == 'Table' &&
          '${workspaceItemsField.first['options']}' == 'Workspace Item' &&
          workspaceItemsField.first['read_only'] == 0 &&
          workspaceItemsField.first['hidden'] == 0,
      'Workspace must expose editable Workspace Item child rows instead of JSON authoring',
    );
    final workspaceItemDocType = db.select("SELECT is_child,table_name,generic_write FROM wmn_doctypes WHERE name='Workspace Item' LIMIT 1;");
    requireCheck(
      workspaceItemDocType.length == 1 &&
          workspaceItemDocType.first['is_child'] == 1 &&
          '${workspaceItemDocType.first['table_name']}' == 'tabWorkspaceItem' &&
          workspaceItemDocType.first['generic_write'] == 1,
      'Workspace Item child DocType registration is incomplete',
    );
    final dataJobDocTypes = db.select("SELECT name,generic_write FROM wmn_doctypes WHERE name IN ('Data Import Job','Data Export Job') ORDER BY name;");
    requireCheck(
      dataJobDocTypes.length == 2 && dataJobDocTypes.every((row) => row['generic_write'] == 0),
      'Data Import/Export history DocTypes must remain engine-owned and read-only',
    );
    requireCheck(
      db.select("SELECT 1 FROM wmn_doctype_fields WHERE doctype='Data Export Job' AND fieldname='format' AND fieldtype='Select' LIMIT 1;").isNotEmpty,
      'Data Export Job runtime metadata is incomplete',
    );
    final runtimePageTypes = db
        .select("SELECT DISTINCT page_type FROM [tabPage] WHERE name LIKE 'Runtime Lab - %';")
        .map((row) => '${row['page_type']}')
        .toSet();
    requireCheck(
      runtimePageTypes.containsAll(<String>{'STANDARD','DASHBOARD','CUSTOM','LIST','FORM','REPORT','WORKSPACE'}),
      'Runtime Laboratory does not cover all current Page runtime types: $runtimePageTypes',
    );
    final dataImportTool = db.select("SELECT page_type,controller_key FROM [tabPage] WHERE name='Data Import / Export Tool' LIMIT 1;");
    requireCheck(
      dataImportTool.length == 1 &&
          '${dataImportTool.first['page_type']}' == 'CUSTOM' &&
          '${dataImportTool.first['controller_key']}' == 'wmn.tool.data_exchange',
      'Data Import/Export must remain an executable Tool/Page instead of a generic DocType operation',
    );
    final workspaceBuilder = db.select("SELECT page_type,metadata_json FROM [tabPage] WHERE name='Workspace Builder' LIMIT 1;");
    requireCheck(
      workspaceBuilder.length == 1 &&
          '${workspaceBuilder.first['page_type']}' == 'LIST' &&
          '${workspaceBuilder.first['metadata_json']}'.contains('"doctype":"Workspace"'),
      'Workspace Builder Page is missing or does not target Workspace',
    );
    final coreRuntimeFeature = db.select("SELECT capability_ids_json FROM wmn_features WHERE code='core.platform' LIMIT 1;");
    requireCheck(
      coreRuntimeFeature.length == 1 &&
          '${coreRuntimeFeature.first['capability_ids_json']}'.contains('field-control-resolver') &&
          '${coreRuntimeFeature.first['capability_ids_json']}'.contains('workspace-builder') &&
          '${coreRuntimeFeature.first['capability_ids_json']}'.contains('data-import-tool'),
      'core.platform feature is missing R3.19 metadata/runtime capabilities',
    );

    final runtimeCatalogSource = readText('lib/platform/system/wmn_system_doctype_runtime_catalog.dart');
    final systemDocTypes = db.select("SELECT name FROM wmn_doctypes WHERE is_system=1 ORDER BY name;");
    final missingRuntimeOwners = <String>[
      for (final row in systemDocTypes)
        if (!runtimeCatalogSource.contains("doctype: '${row['name']}'")) '${row['name']}',
    ];
    requireCheck(
      missingRuntimeOwners.isEmpty,
      'System DocTypes without explicit runtime owners: $missingRuntimeOwners',
    );

    final coverage = db.select('SELECT source_api,status FROM wmn_frappe_api_coverage;');
    requireCheck(coverage.any((row) => row['source_api'] == 'frappe.get_doc' && row['status'] == 'NATIVE'), 'Frappe compatibility coverage seed missing frappe.get_doc');
  } finally {
    db.close();
  }
}


void verifyReleaseSourceTree() {
  final manifest = File(
    '${root.path}${Platform.pathSeparator}SOURCE_TREE_R3.25.0.txt',
  );
  requireCheck(manifest.existsSync(), 'R3.25.0 source-tree manifest is missing');
  if (!manifest.existsSync()) return;

  final expected = const LineSplitter()
      .convert(manifest.readAsStringSync())
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('#'))
      .toSet();
  final actual = <String>{};
  for (final folder in const <String>['lib', 'test', 'tool']) {
    for (final file in filesUnder(folder, extension: '.dart')) {
      actual.add(relativePath(file).replaceAll('\\', '/'));
    }
  }

  final missing = expected.difference(actual).toList()..sort();
  final extra = actual.difference(expected).toList()..sort();
  requireCheck(
    missing.isEmpty,
    'released source files are missing: $missing',
  );
  requireCheck(
    extra.isEmpty,
    'unexpected Dart files from another baseline are present: $extra. '
    'Extract this release into an empty directory; do not overlay releases.',
  );
}

void verifyCleanSource() {
  const forbiddenRootArtifacts = <String>{
    'APPLY.txt',
    'RUN_AFTER_APPLY.txt',
    '_APPLY_INSTRUCTIONS.txt',
    '_CHANGED_FILES.txt',
    '_DELETE_THESE_FILES.txt',
  };
  for (final entity in root.listSync(followLinks: false)) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    final historicalInstruction = name.startsWith('APPLY_') ||
        name.startsWith('APPLY_TO_') ||
        name.startsWith('DELETE_');
    requireCheck(
      !forbiddenRootArtifacts.contains(name) && !historicalInstruction,
      'historical patch/apply artifact remains in clean baseline: $name',
    );
  }

  const forbiddenDirectories = <String>[
    'lib/features/pos',
    'lib/features/sales',
    'lib/features/purchase',
    'lib/features/catalog',
    'lib/features/masters',
    'lib/features/payments',
    'lib/features/accounting',
    'lib/modules/pos',
    'lib/modules/sales',
    'lib/modules/purchase',
    'lib/modules/accounting',
    'lib/modules/inventory',
    'lib/modules/payments',
    'lib/modules/returns',
    'lib/modules/commercial',
    'lib/modules/master_data',
  ];
  for (final relative in forbiddenDirectories) {
    final dir = Directory('${root.path}${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}');
    requireCheck(!dir.existsSync(), 'business application source remains in WMN System Core: $relative');
  }

  final migrationDir = Directory('${root.path}${Platform.pathSeparator}lib${Platform.pathSeparator}core${Platform.pathSeparator}database${Platform.pathSeparator}migrations');
  final migrationNames = migrationDir
      .listSync()
      .whereType<File>()
      .map((file) => file.uri.pathSegments.last)
      .where((name) => RegExp(r'^migration_\d{3}_.+\.dart$').hasMatch(name))
      .toSet();
  const allowedPlatformMigrations = <String>{
    'migration_001_platform_baseline.dart',
    'migration_020_platform_system_reset.dart',
    'migration_021_system_services.dart',
    'migration_022_system_doctypes_and_features.dart',
    'migration_023_identity_permissions_runtime.dart',
    'migration_024_page_runtime.dart',
    'migration_025_workflow_runtime.dart',
    'migration_026_report_storage_runtime.dart',
    'migration_027_system_doctype_form_actions.dart',
    'migration_028_report_examples_runtime.dart',
    'migration_029_report_source_editor_examples.dart',
    'migration_030_printing_pdf_engine.dart',
    'migration_031_files_attachments_adapters.dart',
    'migration_032_metadata_runtime_completion.dart',
    'migration_033_printing_text_unicode_repair.dart',
    'migration_034_structured_report_printing.dart',
    'migration_035_frappe_print_runtime.dart',
    'migration_036_application_generator_packaging.dart',
  };
  final unexpectedMigrations = migrationNames.difference(allowedPlatformMigrations).toList()..sort();
  requireCheck(
    unexpectedMigrations.isEmpty,
    'unexpected migrations remain in the clean system baseline: $unexpectedMigrations',
  );

  final runner = readText('lib/core/database/migrations/migration_runner.dart');
  requireCheck(runner.contains('Migration001PlatformBaseline()'), 'clean platform baseline migration is not active');
  requireCheck(runner.contains('Migration020PlatformSystemReset()'), 'v19-to-platform upgrade bridge is not active');
  requireCheck(runner.contains('Migration022SystemDocTypesAndFeatures()'), 'v22 System DocType/feature migration is not active');
  requireCheck(runner.contains('Migration023IdentityPermissionsRuntime()'), 'v23 identity/permission runtime migration is not active');
  requireCheck(runner.contains('Migration024PageRuntime()'), 'v24 Page runtime migration is not active');
  requireCheck(runner.contains('Migration025WorkflowRuntime()'), 'v25 Workflow runtime migration is not active');
  requireCheck(runner.contains('Migration026ReportStorageRuntime()'), 'v26 Report/Storage runtime migration is not active');
  requireCheck(runner.contains('Migration027SystemDocTypeFormActions()'), 'v27 System DocType completeness migration is not active');
  requireCheck(runner.contains('Migration028ReportExamplesRuntime()'), 'v28 Report examples/runtime migration is not active');
  requireCheck(runner.contains('Migration029ReportSourceEditorExamples()'), 'v29 Report child-table/source-editor migration is not active');
  requireCheck(runner.contains('Migration030PrintingPdfEngine()'), 'v30 Printing/PDF engine migration is not active');
  requireCheck(runner.contains('Migration031FilesAttachmentsAdapters()'), 'v31 Files & Attachments adapter migration is not active');
  requireCheck(runner.contains('Migration032MetadataRuntimeCompletion()'), 'v32 Metadata/Runtime completion migration is not active');
  requireCheck(runner.contains('Migration033PrintingTextUnicodeRepair()'), 'v33 Printing text/Unicode repair migration is not active');
  requireCheck(runner.contains('Migration034StructuredReportPrinting()'), 'v34 structured report printing migration is not active');
  requireCheck(runner.contains('Migration035FrappePrintRuntime()'), 'v35 Frappe-compatible print runtime migration is not active');
  requireCheck(runner.contains('Migration036ApplicationGeneratorPackaging()'), 'v36 Application Generator & Packaging migration is not active');
  requireCheck(!runner.contains('Migration005PosOperations'), 'POS migration is still wired into runtime');

  final bootstrap = readText('lib/app/wmn_bootstrap.dart');
  final runtime = readText('lib/app/wmn_runtime.dart');
  for (final token in const <String>[
    'SalesInvoiceService',
    'PosCheckoutService',
    'PurchaseService',
    'AccountingService',
    'InventoryService',
    'CustomerRepository',
    'PosProfile',
  ]) {
    requireCheck(!bootstrap.contains(token) && !runtime.contains(token), 'business service remains in platform runtime: $token');
  }

  final nativeOpener = readText('lib/core/database/platform/database_opener_native.dart');
  final webOpener = readText('lib/core/database/platform/database_opener_web.dart');
  requireCheck(nativeOpener.contains('wmn_platform.sqlite3'), 'R3 native database must use the isolated wmn_platform.sqlite3 store');
  requireCheck(!nativeOpener.contains('wmn_standalone.sqlite3'), 'R3 native database still reuses the legacy R2 database name');
  requireCheck(webOpener.contains('wmn_platform.sqlite3') && webOpener.contains('wmn_platform_sqlite_files'), 'R3 Web database identity is not isolated from the legacy store');

  final pubspec = readText('pubspec.yaml');
  requireCheck(pubspec.contains('WMN Application Platform'), 'pubspec is not branded as the WMN Application Platform');
  // Business/application-only device packages remain forbidden in the
  // consolidated platform baseline. Printing/PDF are different: since v30
  // they are first-class Platform Capabilities, but concrete package imports
  // must remain isolated behind printing renderers/adapters.
  for (final package in const <String>[
    'mobile_scanner:',
    'camera:',
    'camera_windows:',
    'flutter_zxing:',
    'barcode_widget:',
  ]) {
    requireCheck(!RegExp('^\\s*${RegExp.escape(package)}', multiLine: true).hasMatch(pubspec), 'platform core still bundles application/device package $package');
  }

  const printingImplementationImportPrefixes = <String>[
    'lib/platform/printing/renderers/',
    'lib/platform/printing/adapters/',
  ];
  for (final file in filesUnder('lib', extension: '.dart')) {
    final relative = relativePath(file).replaceAll('\\', '/');
    final source = file.readAsStringSync();
    final importsPdf = source.contains('package:pdf/');
    final importsPrinting = source.contains('package:printing/');
    if (!importsPdf && !importsPrinting) continue;
    final isolated = printingImplementationImportPrefixes.any(relative.startsWith);
    requireCheck(
      isolated,
      'Printing/PDF implementation package leaked outside renderer/adapter boundary: $relative',
    );
  }

  requireCheck(!Directory('${root.path}${Platform.pathSeparator}assets${Platform.pathSeparator}core_foundation').existsSync(),
      'business framework reference bundles remain embedded in WMN System Core');
  requireCheck(!File('${root.path}${Platform.pathSeparator}lib${Platform.pathSeparator}framework${Platform.pathSeparator}core_foundation${Platform.pathSeparator}core_foundation_service.dart').existsSync(),
      'obsolete built-in core foundation service remains in WMN System Core');
}

void verifyPlatformArchitecture() {
  const requiredFiles = <String>[
    'lib/platform/kernel/wmn_kernel.dart',
    'lib/core/documents/document_event_bus.dart',
    'lib/core/documents/document_lifecycle.dart',
    'lib/platform/kernel/wmn_service_registry.dart',
    'lib/platform/kernel/wmn_extension_registry.dart',
    'lib/platform/capabilities/wmn_capability.dart',
    'lib/platform/capabilities/wmn_capability_registry.dart',
    'lib/platform/features/wmn_feature_registry.dart',
    'lib/platform/adapters/wmn_platform_adapter.dart',
    'lib/platform/adapters/wmn_platform_adapter_registry.dart',
    'lib/platform/adapters/wmn_platform_adapters_page.dart',
    'lib/platform/adapters/contracts/wmn_platform_contracts.dart',
    'lib/platform/adapters/native/wmn_flutter_native_services.dart',
    'lib/platform/adapters/native/wmn_mobile_barcode_scanner.dart',
    'lib/platform/adapters/windows/wmn_windows_platform_adapter.dart',
    'lib/platform/adapters/windows/wmn_windows_platform_adapter_io.dart',
    'lib/platform/adapters/mobile/wmn_mobile_platform_adapter.dart',
    'lib/platform/adapters/web/wmn_web_platform_adapter.dart',
    'lib/platform/adapters/server/wmn_server_platform_adapter.dart',
    'lib/platform/developer/wmn_developer_center_page.dart',
    'lib/platform/system/wmn_system_module.dart',
    'lib/platform/system/wmn_system_module_registry.dart',
    'lib/platform/system/wmn_system_modules_page.dart',
    'lib/platform/system/wmn_shell_preferences.dart',
    'lib/platform/apps/wmn_app_manifest.dart',
    'lib/platform/apps/wmn_application_registry.dart',
    'lib/platform/apps/wmn_applications_page.dart',
    'lib/platform/navigation/wmn_app_route.dart',
    'lib/platform/navigation/wmn_navigation_registry.dart',
    'lib/platform/navigation/wmn_application_report_page.dart',
    'lib/platform/pages/wmn_page.dart',
    'lib/platform/pages/wmn_page_service.dart',
    'lib/platform/pages/wmn_page_controller_registry.dart',
    'lib/platform/pages/wmn_page_runtime_view.dart',
    'lib/platform/ui/wmn_platform_shell.dart',
    'lib/platform/ui/wmn_platform_home_page.dart',
    'lib/platform/settings/wmn_platform_settings_page.dart',
    'lib/platform/reports/wmn_platform_reports_page.dart',
    'lib/platform/files/wmn_file_service.dart',
    'lib/platform/files/wmn_file_adapter.dart',
    'lib/platform/files/wmn_file_interaction_service.dart',
    'lib/platform/files/adapters/wmn_file_selector_adapter.dart',
    'lib/platform/files/adapters/wmn_native_file_dialog_adapter.dart',
    'lib/platform/files/adapters/wmn_file_reference_io.dart',
    'lib/platform/files/adapters/wmn_file_reference_stub.dart',
    'lib/platform/configuration/wmn_configuration_service.dart',
    'lib/platform/diagnostics/wmn_log_service.dart',
    'lib/platform/diagnostics/wmn_diagnostics_service.dart',
    'lib/platform/jobs/wmn_job_service.dart',
    'lib/platform/notifications/wmn_notification_service.dart',
    'lib/platform/printing/wmn_printing_service.dart',
    'lib/platform/workflow/wmn_workflow_runtime.dart',
    'lib/platform/workflow/wmn_workflow_condition_engine.dart',
    'lib/platform/services/wmn_system_services_page.dart',
    'lib/framework/meta/field_options.dart',
    'lib/framework/meta/field_control_resolver.dart',
    'lib/platform/system/wmn_system_doctype_runtime_catalog.dart',
    'lib/core/database/migrations/migration_032_metadata_runtime_completion.dart',
    'lib/core/database/migrations/migration_033_printing_text_unicode_repair.dart',
    'lib/core/database/migrations/migration_035_frappe_print_runtime.dart',
    'lib/core/database/migrations/migration_036_application_generator_packaging.dart',
    'lib/platform/printing/renderers/wmn_html_pdf_converter.dart',
    'lib/platform/printing/renderers/wmn_html_pdf_converter_io.dart',
    'lib/platform/ui/wmn_responsive.dart',
    'test/metadata_runtime_completion_test.dart',
  ];
  for (final relative in requiredFiles) {
    requireCheck(File('${root.path}${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}').existsSync(), 'platform architecture file missing: $relative');
  }

  final modules = readText('lib/platform/system/wmn_system_module_registry.dart');
  for (final id in const <String>[
    'kernel',
    'modules',
    'metadata',
    'documents',
    'data',
    'methods',
    'scripts',
    'ui',
    'workspaces',
    'reports',
    'files',
    'printing',
    'import_export',
    'localization',
    'settings',
    'security',
    'workflow',
    'scheduler',
    'audit',
    'diagnostics',
    'notifications',
    'sync',
    'server',
    'mobile',
    'windows',
    'web',
    'developer',
  ]) {
    requireCheck(modules.contains("id: '$id'"), 'system capability missing from registry: $id');
  }

  requireCheck(modules.contains('dependencyGraph'), 'system module dependency graph missing');
  requireCheck(modules.contains('enabledDependentsOf'), 'system module dependent protection missing');

  final fieldOptions = readText('lib/framework/meta/field_options.dart');
  final fieldResolver = readText('lib/framework/meta/field_control_resolver.dart');
  final metaService = readText('lib/framework/meta/meta_service.dart');
  final documentService = readText('lib/framework/model/document_service.dart');
  final runtimeCatalog = readText('lib/platform/system/wmn_system_doctype_runtime_catalog.dart');
  final formRuntime = readText('lib/framework/ui/form/wmn_form_view.dart');
  final listRuntime = readText('lib/framework/ui/list/wmn_list_view.dart');
  requireCheck(
    fieldOptions.contains(r"replaceAll(r'\n', '\n')") &&
        fieldOptions.contains("text.contains('/n')") &&
        fieldOptions.contains('jsonDecode(source)'),
    'central Select option normalizer is incomplete',
  );
  requireCheck(
    fieldResolver.contains('class WmnFieldControlResolver') &&
        fieldResolver.contains("normalized == 'AUTO'") &&
        fieldResolver.contains("field.fieldType != 'Data'") &&
        fieldResolver.contains("metadata['link_target']"),
    'effective Field Control resolver is incomplete',
  );
  requireCheck(
    metaService.contains('WmnFieldControlResolver.resolve') &&
        metaService.contains("renderAs == 'SELECT'") &&
        metaService.contains("renderAs == 'LINK'"),
    'metadata validation does not honor effective Select/Link controls',
  );
  requireCheck(
    formRuntime.contains('WmnFieldControlResolver.resolve') &&
        listRuntime.contains('WmnFieldControlResolver.resolve'),
    'Form/List runtimes are not using the shared effective field-control resolver',
  );
  requireCheck(
    documentService.contains('WmnFieldControlResolver.resolve') &&
        documentService.contains('control.type == WmnFieldControlType.select') &&
        documentService.contains('control.type == WmnFieldControlType.link') &&
        documentService.contains('incomingLinkReferences'),
    'Render As semantics are present in UI but missing from document validation/backlink runtime',
  );
  requireCheck(
    runtimeCatalog.contains('class WmnSystemDocTypeRuntimeCatalog') &&
        runtimeCatalog.contains("ownerServiceId: 'wmn.data_exchange'") &&
        runtimeCatalog.contains("ownerServiceId: 'wmn.workspaces'"),
    'System DocType runtime ownership catalog is incomplete',
  );
  requireCheck(formRuntime.contains("widget.doctype == 'Report'") && formRuntime.contains("context.wmnT('show_report')") && formRuntime.contains('_showReport'), 'Report DocType Show Report form action missing');
  requireCheck(formRuntime.contains('WmnOpenReportCallback'), 'generic Form runtime report action callback missing');

  requireCheck(formRuntime.contains('report_creation_guide') && formRuntime.contains('_reportCreationGuide'), 'Report creation guide UI missing');
  requireCheck(
    formRuntime.contains('control.type == WmnFieldControlType.childTable') &&
        formRuntime.contains('return _ChildTableField(') &&
        formRuntime.contains('class _ChildRowEditorDialog'),
    'generic child-table form runtime missing',
  );
  requireCheck(formRuntime.contains('report-query-sql-source') && formRuntime.contains("_values['query_source_type'] = 'STORAGE_FILE'"), 'Query Report SQL editor must save directly to Storage');
  requireCheck(formRuntime.contains("type == 'Report Builder'") && formRuntime.contains("definition['source_key'] = 'doctype:\$reference'") && formRuntime.contains("_values['query_source_type'] = 'STRUCTURED'"), 'Report Builder form does not rebuild structured definitions from visible child tables');
  requireCheck(formRuntime.contains('arrow_upward_outlined') && formRuntime.contains('arrow_downward_outlined'), 'child table row reordering controls missing');
  final reportFolderLoader = readText('lib/modules/reporting/application/report_folder_loader.dart');
  requireCheck(reportFolderLoader.contains('class WmnReportFolderLoader') && reportFolderLoader.contains('report.json') && reportFolderLoader.contains('query.sql'), 'Report Folder loader/import-export contract missing');
  requireCheck(reportFolderLoader.contains("'source_mode': 'REPORT_FOLDER'") && reportFolderLoader.contains('importFolder') && reportFolderLoader.contains('exportFolder'), 'Report folder source metadata or import/export methods missing');
  final reportBootstrap = readText('lib/app/wmn_bootstrap.dart');
  final reportAppRuntime = readText('lib/app/wmn_runtime.dart');
  requireCheck(
    reportBootstrap.contains("register('wmn.report_folders'") &&
        reportAppRuntime.contains('WmnReportFolderLoader'),
    'Report Folder loader is not registered in the platform runtime',
  );
  final reportPage = readText('lib/platform/navigation/wmn_application_report_page.dart');
  requireCheck(reportPage.contains('_loadingDefinition') && reportPage.contains('addPostFrameCallback') && !reportPage.contains('WmnFrappeReportDefinition? get _definition'), 'Report page must cache its definition instead of querying from build');
  requireCheck(reportPage.contains('WidgetsBinding.instance.addPostFrameCallback((_)') && reportPage.contains('if (mounted) _run();'), 'Report page must execute automatically after the definition is loaded');
  requireCheck(reportPage.contains("context.wmnT('refresh')") && !reportPage.contains("context.wmnT('run_report')"), 'Report page must use Refresh and must not expose a Run Report button');
  requireCheck(reportPage.contains('_filterWidget') && reportPage.contains("type == 'Link' || type == 'Dynamic Link'") && reportPage.contains('showDatePicker') && reportPage.contains("type == 'Select'") && reportPage.contains("type == 'Check'"), 'Frappe-style Report filter field rendering is incomplete');
  requireCheck(reportPage.contains('depends_on') && reportPage.contains('RawAutocomplete<String>'), 'Report filters must support depends_on and Link autocomplete');
  requireCheck(reportPage.contains('WidgetsBinding.instance.endOfFrame'), 'Report execution must yield one frame before synchronous execution');
  final responsiveUi = readText('lib/platform/ui/wmn_responsive.dart');
  final platformShell = readText('lib/platform/ui/wmn_platform_shell.dart');
  requireCheck(
    responsiveUi.contains('available width') &&
        responsiveUi.contains('compactShell') &&
        platformShell.contains('WmnResponsive.compactShell') &&
        reportPage.contains('WmnResponsive.pagePadding') &&
        reportPage.contains('WmnResponsive.compactPage'),
    'width-driven responsive UI contract is not consistently wired',
  );
  requireCheck(
    !platformShell.contains('Platform.isAndroid') &&
        !platformShell.contains('Platform.isWindows') &&
        !reportPage.contains('Platform.isAndroid') &&
        !reportPage.contains('Platform.isWindows'),
    'Shell/Report visual composition must not branch by operating system',
  );
  final builtInReports = readText('lib/modules/reporting/application/builtin_report_handlers.dart');
  requireCheck(builtInReports.contains('wmn.examples.reports.module_summary'), 'built-in Script Report example handler missing');
  final printTemplates = readText('lib/platform/printing/wmn_print_template_engine.dart');
  requireCheck(printTemplates.contains('_normalizeTemplateText') && printTemplates.contains("replaceAll(r'\\n', '\\n')"), 'Print template escaped-newline normalization missing');
  final pdfConverter = readText('lib/platform/printing/renderers/wmn_html_pdf_converter_io.dart');
  final pdfRenderer = readText('lib/platform/printing/renderers/wmn_pdf_print_renderer.dart');
  final htmlRenderer = readText('lib/platform/printing/renderers/wmn_html_print_renderer.dart');
  final printPreview = readText('lib/platform/printing/wmn_print_preview_dialog.dart');
  requireCheck(
    pdfConverter.contains('Printing.convertHtml') &&
        !pdfConverter.contains('Printing.info()') &&
        !pdfConverter.contains('canConvertHtml') &&
        pdfConverter.contains('Platform.isAndroid') &&
        pdfConverter.contains('--print-to-pdf=') &&
        pdfConverter.contains("format.pdfGenerator") &&
        pdfConverter.contains('Duration(seconds: 60)') &&
        pdfConverter.contains('marginAll: 0'),
    'canonical HTML print conversion/margin isolation is incomplete',
  );
  requireCheck(
    !pdfConverter.contains('package:pdf/widgets.dart') &&
        !pdfConverter.contains('/system/fonts') &&
        !pdfConverter.contains('pdf_font_path') &&
        !pdfConverter.contains('_containsArabic') &&
        !pdfConverter.contains('_containsRtl'),
    'PDF rendering must not rebuild text or inspect Arabic/font files',
  );
  requireCheck(
    pdfRenderer.contains('WmnHtmlPrintRenderer') &&
        pdfRenderer.contains('html.debugText') &&
        !pdfRenderer.contains('pw.Text('),
    'PDF renderer must consume the canonical HTML instead of rebuilding layout',
  );
  requireCheck(
    htmlRenderer.contains('<meta charset="utf-8">') &&
        htmlRenderer.contains(r'lang="${_attr(languageCode)}"') &&
        htmlRenderer.contains(r'dir="$direction"') &&
        htmlRenderer.contains(r'font-family: $font') &&
        !htmlRenderer.contains('_containsArabic'),
    'canonical HTML UTF-8/language/direction/font contract is incomplete',
  );
  requireCheck(
    !File('${root.path}${Platform.pathSeparator}lib${Platform.pathSeparator}platform${Platform.pathSeparator}printing${Platform.pathSeparator}renderers${Platform.pathSeparator}wmn_pdf_font_resolver_io.dart').existsSync() &&
        !File('${root.path}${Platform.pathSeparator}lib${Platform.pathSeparator}platform${Platform.pathSeparator}printing${Platform.pathSeparator}renderers${Platform.pathSeparator}wmn_pdf_text_runs.dart').existsSync(),
    'obsolete PDF font/text-run repair runtime remains in the clean source',
  );
  requireCheck(
    printPreview.contains('formatsForRequest') &&
        printPreview.contains('letterHeads()') &&
        printPreview.contains("languageCode: _languageCode") &&
        printPreview.contains('widget.printing.preview') &&
        !printPreview.contains('WmnPrintExecutionResult'),
    'Print Preview must switch Print Format/Letter Head/language without queuing jobs',
  );

  final platformVersion = readText('lib/platform/system/wmn_platform_version.dart');
  requireCheck(
    platformVersion.contains("static const String version = '3.25.0+127';") &&
        platformVersion.contains('static const int schemaVersion = 36;'),
    'WMN platform version/schema constants are not R3.25.0+127 / v36',
  );

  requireCheck(
    platformShell.contains('final label = entry.route.title;') &&
        !platformShell.contains(r"${entry.appTitle} · ${entry.route.title}"),
    'Application Navigation must render the route/DocType label without the application-title prefix',
  );
  final workspaceLinkPage = readText('lib/framework/workspaces/workspace_page.dart');
  requireCheck(
    workspaceLinkPage.contains('item.parentLabel') &&
        workspaceLinkPage.contains('_workspaceLinkCard') &&
        workspaceLinkPage.contains('_workspaceLinkSection'),
    'Workspace Link Card grouping through Workspace Item parent_label is missing',
  );
  final transactionBootstrap = readText('lib/app/wmn_bootstrap.dart');
  final transactionWorkspacePage = readText(
    'lib/platform/pages/wmn_transaction_workspace_page.dart',
  );
  requireCheck(
    transactionWorkspacePage.contains(
          'separatorBuilder: (_, _) => const Divider(height: 1)',
        ) &&
        !transactionWorkspacePage.contains('separatorBuilder: (_, __)') &&
        transactionWorkspacePage.contains('this.discountPercent = 0') &&
        transactionWorkspacePage.contains('_lineDiscountField'),
    'Generic transaction workspace analyzer-clean separator/discount contract is missing',
  );
  requireCheck(
    transactionWorkspacePage.contains('.toDouble()') &&
        transactionWorkspacePage.contains('final remaining = math.max(0.0,') &&
        transactionWorkspacePage.contains(
          'final change = _isReturn ? 0.0 : math.max(0.0,',
        ),
    'Generic transaction workspace numeric calculations must remain double-typed',
  );
  requireCheck(
    transactionBootstrap.contains("'wmn.page.transaction_workspace_v1'") &&
        transactionBootstrap.contains('WmnTransactionWorkspacePage(') &&
        transactionWorkspacePage.contains('class WmnTransactionWorkspacePage') &&
        transactionWorkspacePage.contains("_requiredConfig('transaction_doctype')") &&
        transactionWorkspacePage.contains("_field('transaction_lines')") &&
        transactionWorkspacePage.contains("_field('payment_line_method')") &&
        transactionBootstrap.contains("tryResolveService('wmn.native.scanner')") &&
        transactionWorkspacePage.contains('WmnScannerAdapter? scanner') &&
        transactionWorkspacePage.contains('scanBarcode()'),
    'Generic metadata-driven transaction workspace controller runtime is missing',
  );
  final managedProcedureRuntime = readText(
    'lib/platform/scripts/wmn_managed_procedure_runtime.dart',
  );
  requireCheck(
    transactionWorkspacePage.contains('barcode_resolver_method') &&
        transactionWorkspacePage.contains('pricing_resolver_method') &&
        transactionWorkspacePage.contains('widget.frappe.call(') &&
        transactionWorkspacePage.contains("_optionalField('transaction_pricing_code')") &&
        transactionWorkspacePage.contains("_optionalField('transaction_pricing_rule')") &&
        transactionWorkspacePage.contains("_optionalField('transaction_pricing_discount')"),
    'Generic transaction workspace resolver extension points are missing',
  );
  requireCheck(
    managedProcedureRuntime.contains("case 'map_put':") &&
        managedProcedureRuntime.contains("case 'append':") &&
        managedProcedureRuntime.contains("map.containsKey('slice')") &&
        managedProcedureRuntime.contains("map.containsKey('starts_with')") &&
        managedProcedureRuntime.contains("map.containsKey('ends_with')") &&
        managedProcedureRuntime.contains("map.containsKey('to_number')") &&
        managedProcedureRuntime.contains("map.containsKey('floor')") &&
        !managedProcedureRuntime.contains('.wmnapp'),
    'Generic managed-procedure collection/string/number primitives are missing or legacy package terminology remains',
  );
  for (final term in const <String>[
    'wmn_pos_extensions',
    'Barcode Structure',
    'WMN POS Promotion',
    'WMN POS Coupon',
    'WMN POS Cash Movement',
  ]) {
    requireCheck(
      !transactionWorkspacePage.contains(term) && !managedProcedureRuntime.contains(term),
      'Generic System Core must not hard-code POS extension application term: $term',
    );
  }

  const forbiddenBusinessTerms = <String>[
    'POS Invoice',
    'POS Profile',
    'POS Opening Entry',
    'POS Closing Entry',
    'Customer',
    'Item Price',
    'Mode of Payment',
    'Warehouse',
  ];
  for (final term in forbiddenBusinessTerms) {
    requireCheck(
      !transactionWorkspacePage.contains(term),
      'System Core transaction workspace must not hard-code application business term: $term',
    );
  }
  requireCheck(
    !transactionBootstrap.contains("'wmn.page.pos_v2'") &&
        !transactionBootstrap.contains("'wmn.page.transaction_cart_v1'") &&
        !File(
          '${root.path}${Platform.pathSeparator}lib${Platform.pathSeparator}platform${Platform.pathSeparator}pages${Platform.pathSeparator}wmn_transaction_cart_page.dart',
        ).existsSync(),
    'Legacy application-specific POS/cart controller aliases or source file must not remain in System Core',
  );
  final barcodeService = readText('lib/platform/printing/wmn_barcode_service.dart');
  final htmlPrintRenderer = readText('lib/platform/printing/renderers/wmn_html_print_renderer.dart');
  requireCheck(
    barcodeService.contains('wmn-qr-code') &&
        htmlPrintRenderer.contains("format.metadata['qr_size_mm']") &&
        htmlPrintRenderer.contains('svg.wmn-qr-code') &&
        htmlPrintRenderer.contains('!important'),
    'Print QR physical-size constraint is missing',
  );

  final applicationGenerator = readText('lib/platform/apps/wmn_application_generator_service.dart');
  requireCheck(
    applicationGenerator.contains("_installGeneric('tabWorkspaceItem', decoded.components['workspace_items']);") &&
        applicationGenerator.contains("'workspace_items': _rowsIn('tabWorkspaceItem', 'parent', workspaceNames),") &&
        !applicationGenerator.contains("_installGeneric('wmn_workspace_items', decoded.components['workspace_items']);"),
    'Application Generator Workspace Items are not consolidated on tabWorkspaceItem',
  );

  final capabilityRegistry = readText('lib/platform/capabilities/wmn_capability_registry.dart');
  final featureRegistry = readText('lib/platform/features/wmn_feature_registry.dart');
  final identityRuntime = readText('lib/platform/security/wmn_identity_service.dart');
  final permissionRuntime = readText('lib/platform/security/wmn_permission_service.dart');
  requireCheck(capabilityRegistry.contains('WmnCapabilityRegistry'), 'capability registry missing');
  requireCheck(capabilityRegistry.contains('WmnCapabilityStatus.planned'), 'planned capabilities are not distinguished from executable capabilities');
  requireCheck(capabilityRegistry.contains('windows_desktop'), 'capability profiles missing');
  requireCheck(capabilityRegistry.contains('platformAdapters'), 'capability registry is not runtime-adapter aware');
  requireCheck(capabilityRegistry.contains('WmnPlatformCapabilityStatus'), 'platform capability status gating missing');
  requireCheck(capabilityRegistry.contains('web_client'), 'Web capability profile missing');
  requireCheck(capabilityRegistry.contains('WmnFeatureRegistry'), 'Feature entitlement registry is not wired into capability resolution');
  requireCheck(featureRegistry.contains('wmn_feature_activations'), 'local feature activation persistence missing');
  requireCheck(featureRegistry.contains('_cache'), 'feature registry must cache its lazy entitlement snapshot');



  final workflowRuntime = readText('lib/platform/workflow/wmn_workflow_runtime.dart');
  final workflowConditions = readText('lib/platform/workflow/wmn_workflow_condition_engine.dart');
  final workflowFacade = readText('lib/framework/frappe_compat/frappe_workflow.dart');
  final workflowBootstrap = readText('lib/app/wmn_bootstrap.dart');
  requireCheck(
    workflowRuntime.contains('class WmnWorkflowRuntime') &&
        workflowRuntime.contains("event: 'before_workflow_action'") &&
        workflowRuntime.contains("event: 'after_workflow_action'") &&
        workflowRuntime.contains('database.transaction(() {') &&
        workflowRuntime.contains('Workflow state cannot be changed directly') &&
        workflowRuntime.contains('New documents must start in workflow state') &&
        workflowRuntime.contains('Only one enabled workflow is allowed') &&
        workflowRuntime.contains("hasSystemPermission('wmn.workflow.manage')") &&
        workflowRuntime.contains('Submit is controlled by workflow') &&
        workflowRuntime.contains('Cancel is controlled by workflow'),
    'native transactional workflow runtime boundary is incomplete',
  );
  requireCheck(
    workflowConditions.contains('class WmnWorkflowConditionEngine') &&
        workflowConditions.contains('Arbitrary Dart, JavaScript, Python and SQL are never executed') &&
        workflowConditions.contains('WmnWorkflowConditionRegistry'),
    'safe workflow condition contract is missing',
  );
  requireCheck(
    workflowFacade.contains('Compatibility facade over the native WMN workflow runtime') &&
        workflowFacade.contains('WmnFrappeWorkflowDocumentGateway'),
    'Frappe workflow compatibility layer does not delegate to native WMN runtime',
  );
  final compactWorkflowBootstrap = workflowBootstrap.replaceAll(
    RegExp(r'\s+'),
    '',
  );
  final frappeRuntimeSource = readText(
    'lib/framework/frappe_compat/frappe_runtime.dart',
  );
  final compactFrappeRuntimeSource = frappeRuntimeSource.replaceAll(
    RegExp(r'\s+'),
    '',
  );
  final runtimeSource = readText('lib/app/wmn_runtime.dart');
  final compactRuntimeSource = runtimeSource.replaceAll(RegExp(r'\s+'), '');
  requireCheck(
    compactWorkflowBootstrap.contains(
      "WmnExtensionPoint(id:'workflows.conditions'",
    ),
    'workflow condition extension point is not wired into Kernel extensions',
  );
  requireCheck(
    compactWorkflowBootstrap.contains(
          'finalworkflowConditionRegistry=WmnWorkflowConditionRegistry();',
        ) &&
        compactWorkflowBootstrap.contains(
          'finalworkflowConditions=WmnWorkflowConditionEngine(',
        ) &&
        compactWorkflowBootstrap.contains(
          'registry:workflowConditionRegistry',
        ) &&
        compactWorkflowBootstrap.contains(
          'workflowConditions:workflowConditions,',
        ) &&
        compactFrappeRuntimeSource.contains(
          'WmnWorkflowConditionEngine?workflowConditions',
        ) &&
        compactFrappeRuntimeSource.contains('conditions:workflowConditions'),
    'workflow condition registry is not injected into the native workflow runtime',
  );
  requireCheck(
    compactWorkflowBootstrap.contains(
          "register('wmn.workflow',frappeRuntime.workflowRuntime)",
        ) &&
        compactWorkflowBootstrap.contains(
          "register('wmn.workflow_conditions',workflowConditionRegistry)",
        ) &&
        compactWorkflowBootstrap.contains(
          "register('wmn.workflow_condition_engine',workflowConditions)",
        ),
    'workflow condition registry is not wired into Kernel services',
  );
  requireCheck(
    compactWorkflowBootstrap.contains(
          'workflowConditions:workflowConditionRegistry,',
        ) &&
        compactRuntimeSource.contains(
          'finalWmnWorkflowConditionRegistryworkflowConditions;',
        ),
    'workflow condition registry is not exposed through WmnRuntime',
  );


  final workflowTests = readText('test/workflow_runtime_test.dart');
  requireCheck(
    workflowTests.contains('new documents cannot bypass the initial workflow state') &&
        workflowTests.contains('workflow condition registry is the injected runtime registry') &&
        workflowTests.contains('workflow states with equal indexes preserve insertion order') &&
        workflowTests.contains('only one enabled workflow is allowed per DocType') &&
        workflowTests.contains('failed after-workflow hook rolls back'),
    'workflow regression coverage is incomplete',
  );

  final documentEvents = readText('lib/core/documents/document_event_bus.dart');
  final documentLifecycle = readText('lib/core/documents/document_lifecycle.dart');
  final frappeDocuments = readText('lib/framework/frappe_compat/frappe_documents.dart');
  final frappeRuntime = readText('lib/framework/frappe_compat/frappe_runtime.dart');
  final lifecycleBootstrap = readText('lib/app/wmn_bootstrap.dart');
  requireCheck(
    documentEvents.contains('class WmnDocumentEventBus') &&
        documentEvents.contains('priority') &&
        documentEvents.contains("doctype = '*'") &&
        documentEvents.contains("event = '*'"),
    'lightweight priority/wildcard document event bus missing',
  );
  requireCheck(
    documentEvents.contains('required this.document') &&
        !documentEvents.contains(': document = document'),
    'document event model regressed from initializing-formal analyzer-safe construction',
  );
  requireCheck(
    documentLifecycle.contains('class WmnDocumentLifecycleRuntime') &&
        documentLifecycle.contains("'before_insert'") &&
        documentLifecycle.contains("'before_validate'") &&
        documentLifecycle.contains("'before_save'") &&
        documentLifecycle.contains("'after_save'") &&
        documentLifecycle.contains("'before_submit'") &&
        documentLifecycle.contains("'on_submit'") &&
        documentLifecycle.contains("'before_cancel'") &&
        documentLifecycle.contains("'on_cancel'") &&
        documentLifecycle.contains("'before_delete'") &&
        documentLifecycle.contains("'after_delete'"),
    'transactional document lifecycle event contract missing',
  );
  requireCheck(
    documentLifecycle.contains('return database.transaction(() {') &&
        documentLifecycle.contains('database.transaction(() {'),
    'document lifecycle operations are not transaction-bound',
  );
  requireCheck(
    frappeDocuments.contains('lifecycle.insert(') &&
        frappeDocuments.contains('lifecycle.update(') &&
        frappeDocuments.contains('lifecycle.submit(') &&
        frappeDocuments.contains('lifecycle.cancel(') &&
        frappeDocuments.contains('lifecycle.delete('),
    'Frappe-compatible document API bypasses the WMN lifecycle runtime',
  );
  requireCheck(
    frappeRuntime.contains('lifecycle.events.on(') &&
        frappeRuntime.contains("doctype: '*'") &&
        frappeRuntime.contains("event: '*'") &&
        RegExp(
          r'hooks\.emitDocument\s*\(\s*event\.doctype\s*,\s*event\.event\s*,\s*event\.document\s*,',
        ).hasMatch(frappeRuntime) &&
        frappeRuntime.contains('previous: event.previous') &&
        frappeRuntime.contains('operation: event.operation') &&
        frappeRuntime.contains('actor: event.actor') &&
        !frappeDocuments.contains('void _emit('),
    'Frappe document hooks are not bridged through the shared event runtime',
  );
  requireCheck(
    RegExp(r"WmnExtensionPoint\s*\(\s*id:\s*'documents\.events'").hasMatch(lifecycleBootstrap) &&
        RegExp(r"register\s*\(\s*'wmn\.documents'\s*,\s*frappeRuntime\.documents\s*\)").hasMatch(lifecycleBootstrap) &&
        !RegExp(r"register\s*\(\s*'wmn\.documents'\s*,\s*documents\s*\)").hasMatch(lifecycleBootstrap) &&
        RegExp(r"register\s*\(\s*'wmn\.document_lifecycle'\s*,\s*frappeRuntime\.lifecycle\s*\)").hasMatch(lifecycleBootstrap) &&
        RegExp(r"register\s*\(\s*'wmn\.document_events'\s*,\s*frappeRuntime\.lifecycle\.events\s*\)").hasMatch(lifecycleBootstrap),
    'canonical document API/lifecycle/event services are not registered safely in the kernel',
  );
  requireCheck(
    capabilityRegistry.contains("'document-events'") &&
        capabilityRegistry.contains("'document-lifecycle'"),
    'document lifecycle capabilities missing',
  );

  final pageService = readText('lib/platform/pages/wmn_page_service.dart');
  final pageRuntime = readText('lib/platform/pages/wmn_page_runtime_view.dart');
  final pageControllers = readText('lib/platform/pages/wmn_page_controller_registry.dart');
  requireCheck(pageService.contains('cacheLimit = 12'), 'bounded lazy Page cache missing');
  requireCheck(pageService.contains('_navigationCache'), 'lazy Page navigation cache missing');
  requireCheck(pageService.contains('importFrappePage'), 'Frappe Page metadata importer missing');
  requireCheck(pageRuntime.contains('class WmnPageRuntimeView'), 'metadata-driven Page runtime view missing');
  requireCheck(pageControllers.contains('class WmnPageControllerRegistry'), 'compiled Page controller registry missing');
  requireCheck(capabilityRegistry.contains("'page-runtime'"), 'Page runtime capability missing');

  final shell = readText('lib/platform/ui/wmn_platform_shell.dart');
  final workspaceHome = readText('lib/platform/ui/wmn_workspace_home_page.dart');
  final workspaceService = readText('lib/framework/workspaces/workspace_service.dart');
  requireCheck(shell.contains('bool _legacyUi = false;'), 'workspace-first UI must be the default shell mode');
  requireCheck(shell.contains('Widget _workspaceSidebarContent('), 'workspace-first sidebar missing');
  requireCheck(shell.contains('Widget _legacySidebarContent('), 'temporary Current UI compatibility surface missing');
  final workspaceSidebarStart = shell.indexOf('Widget _workspaceSidebarContent(');
  final legacySidebarStart = shell.indexOf('Widget _legacySidebarContent(');
  final workspaceSidebar = workspaceSidebarStart >= 0 && legacySidebarStart > workspaceSidebarStart
      ? shell.substring(workspaceSidebarStart, legacySidebarStart)
      : '';
  for (final legacyRoute in <String>[
    'system_modules','applications','doctypes','methods','reports','data_exchange',
    'developer_center','app_converter','compatibility','platform_adapters','system_services','settings',
  ]) {
    requireCheck(!workspaceSidebar.contains("route: '$legacyRoute'"), 'legacy route leaked into workspace-first sidebar: $legacyRoute');
  }
  requireCheck(RegExp(r"_legacyUi\s*\?\s*'workspace_ui'\s*:\s*'current_ui'").hasMatch(shell), 'Current UI / Workspace UI switch button missing');
  requireCheck(shell.contains('r.features,'), 'shell must rebuild when user-controlled feature activation changes');
  requireCheck(
    shell.contains('final _compactScaffoldKey = GlobalKey<ScaffoldState>();') &&
        shell.contains('key: _compactScaffoldKey') &&
        shell.contains('_compactScaffoldKey.currentState?.openDrawer()'),
    'compact workspace drawer is not wired to the owning Scaffold',
  );
  requireCheck(
    shell.contains('width: collapsed ? 64 : 232'),
    'compact desktop sidebar contract missing',
  );

  final openDoctypeStart = shell.indexOf('void _openDoctype(String doctype)');
  final openDoctypeSource = openDoctypeStart < 0
      ? ''
      : shell.substring(openDoctypeStart);
  requireCheck(
    openDoctypeSource.contains('Navigator.of(context).push(') &&
        openDoctypeSource.contains('body: WmnListView(') &&
        !openDoctypeSource.contains('WmnListView.showManageDialog('),
    'normal DocType workspace opening must preserve routed List/Form navigation',
  );
  requireCheck(
    shell.contains('Future<void> _manageLinkRecords(String doctype)') &&
        shell.contains('await WmnListView.showManageDialog('),
    'Link Manage Records dialog callback is missing',
  );
  final pageRouteStart = shell.indexOf('WmnAppRouteTargetType.page =>');
  final unsupportedRouteStart = shell.indexOf(
    'WmnAppRouteTargetType.unsupported =>',
    pageRouteStart < 0 ? 0 : pageRouteStart,
  );
  final pageRouteSource = pageRouteStart < 0
      ? ''
      : shell.substring(
          pageRouteStart,
          unsupportedRouteStart > pageRouteStart
              ? unsupportedRouteStart
              : shell.length,
        );
  requireCheck(
    pageRouteSource.contains('body: WmnPageRuntimeView(') &&
        pageRouteSource.contains('onManageLinkRecords: _manageLinkRecords'),
    'Page runtime is missing the Link Manage Records callback wiring',
  );
  final workspaceRouteStart = shell.indexOf(
    'WmnAppRouteTargetType.workspace =>',
  );
  final doctypeRouteStart = shell.indexOf(
    'WmnAppRouteTargetType.doctype =>',
    workspaceRouteStart < 0 ? 0 : workspaceRouteStart,
  );
  final workspaceRouteSource = workspaceRouteStart < 0
      ? ''
      : shell.substring(
          workspaceRouteStart,
          doctypeRouteStart > workspaceRouteStart
              ? doctypeRouteStart
              : shell.length,
        );
  requireCheck(
    !workspaceRouteSource.contains('onManageLinkRecords:'),
    'Workspace route must not receive the Link Manage Records callback',
  );

  final formView = readText('lib/framework/ui/form/wmn_form_view.dart');
  final listView = readText('lib/framework/ui/list/wmn_list_view.dart');
  requireCheck(
    formView.contains('enum WmnFormPresentation { page, dialog }') &&
        formView.contains('showQuickCreateDialog(') &&
        formView.contains('widget.onSaved?.call('),
    'shared Form dialog / Quick Create runtime missing',
  );
  requireCheck(
    formView.contains('onQuickCreate') &&
        RegExp(r"hasPermission\(\s*widget\.targetDoctype,\s*'create'").hasMatch(formView) &&
        formView.contains('widget.onChanged(value);'),
    'Link Quick Create permission or auto-selection contract missing',
  );
  requireCheck(
    formView.contains('onManageRecords') &&
        formView.contains("context.wmnT('manage_records')") &&
        formView.contains('Icons.list_alt_outlined'),
    'Link Manage Records button contract missing',
  );
  requireCheck(
    listView.contains('showManageDialog(') &&
        listView.contains('openFormsInDialog: true') &&
        listView.contains('presentation: WmnFormPresentation.dialog'),
    'DocType Manage Dialog does not keep add/edit forms inside dialogs',
  );
  final appTheme = readText('lib/app/wmn_app.dart');
  requireCheck(
    appTheme.contains('visualDensity: VisualDensity.compact') &&
        appTheme.contains('minimumSize: const Size(44, 40)'),
    'compact platform control theme missing',
  );
  requireCheck(workspaceHome.contains('class WmnWorkspaceHomePage'), 'lightweight workspace home missing');
  requireCheck(
    workspaceService.contains('[tabWorkspaceItem]') && !workspaceService.contains('wmn_workspace_items'),
    'Workspace runtime must consume the Workspace Item child table, not legacy JSON/item storage',
  );
  requireCheck(workspaceService.contains("name: 'System'"), 'System workspace seed missing');
  requireCheck(workspaceService.contains("name: 'Administration'"), 'Administration workspace seed missing');
  requireCheck(workspaceService.contains("name: 'Developer'"), 'Developer workspace seed missing');
  requireCheck(workspaceService.contains("'required_feature': 'developer.tools'"), 'Developer workspace feature gate missing');
  requireCheck(workspaceService.contains("platformWorkspaceSeedVersion = '3.14.0'"), 'idempotent platform Workspace seed version missing');
  requireCheck(workspaceService.contains('if (_platformWorkspaceSeedCurrent()) return;'), 'platform Workspace seed must avoid repeated startup writes');
  final workspacePage = readText('lib/framework/workspaces/workspace_page.dart');
  requireCheck(workspacePage.contains("item.data['required_feature']"), 'workspace item feature visibility gate missing');

  requireCheck(identityRuntime.contains('class WmnIdentityService'), 'native identity runtime missing');
  requireCheck(permissionRuntime.contains('class WmnPermissionService'), 'native permission runtime missing');
  requireCheck(permissionRuntime.contains('_snapshotCacheLimit = 4'), 'bounded permission snapshot cache missing');
  requireCheck(
    permissionRuntime.contains('_doctypeAccessCache'),
    'lazy DocType access cache missing from permission runtime',
  );
  requireCheck(permissionRuntime.contains("wmn.security.manage"), 'security metadata fail-closed gate missing');
  requireCheck(
    modules.contains("id: 'security'") &&
        RegExp(r"id: 'security'[\s\S]{0,500}required: true").hasMatch(modules),
    'Security system module must remain required and non-optional',
  );
  requireCheck(
    !RegExp(r"id: 'security'[\s\S]{0,500}'authentication'").hasMatch(modules),
    'credential authentication must not be advertised before a real auth runtime exists',
  );


  final appManifest = readText('lib/platform/apps/wmn_app_manifest.dart');
  requireCheck(appManifest.contains('requiredSystemModules'), 'application manifest system-module declaration missing');
  requireCheck(appManifest.contains('requiredCapabilities'), 'application manifest required capability declaration missing');
  requireCheck(appManifest.contains('optionalCapabilities'), 'application manifest optional capability declaration missing');
  requireCheck(appManifest.contains('capabilityProfile'), 'application manifest capability profile missing');
  requireCheck(appManifest.contains('platformTargets'), 'application manifest platform target declaration missing');
  requireCheck(appManifest.contains('routeDefinitions'), 'application executable route definitions missing');
  requireCheck(appManifest.contains('requiredRoles'), 'application role gate declaration missing');
  requireCheck(appManifest.contains('List<String> pages'), 'application Page declaration missing');

  final appRegistry = readText('lib/platform/apps/wmn_application_registry.dart');
  requireCheck(appRegistry.contains('WmnApplicationDiagnostic'), 'application compatibility diagnostics missing');
  requireCheck(appRegistry.contains('capabilities.missing'), 'application registry does not enforce runtime capability availability');
  requireCheck(appRegistry.contains('requiredSystemModules'), 'application registry does not enforce required system modules');
  requireCheck(appRegistry.contains('wmn_app_packages'), 'application registry is not persisted');
  requireCheck(appRegistry.contains('routeCollisions'), 'application route collision protection missing');
  requireCheck(appRegistry.contains('_synchronizeApplicationModules'), 'application manifest module ownership synchronization missing');
  requireCheck(appRegistry.contains('_synchronizeApplicationDependencies'), 'application dependency graph synchronization missing');

  final bootstrap = readText('lib/app/wmn_bootstrap.dart');
  final appGenerator = readText('lib/platform/apps/wmn_application_generator_service.dart');
  requireCheck(appManifest.contains('List<String> assets'), 'application manifest asset declaration missing');
  requireCheck(appManifest.contains('entryRoute'), 'application manifest entry route missing');
  requireCheck(appGenerator.contains("packageFormat = 'wmn.application'"), 'WMN application package format contract missing');
  final applicationsPage = readText('lib/platform/apps/wmn_applications_page.dart');
  requireCheck(
    appGenerator.contains("fileName: '\${app.manifest.name}-\${app.manifest.version}.zip'") &&
        !appGenerator.contains('.wmnapp') &&
        applicationsPage.contains("extensions: <String>['zip']") &&
        applicationsPage.contains("webWildCards: <String>['.zip']") &&
        !applicationsPage.contains('wmnapp'),
    'Application Generator/Import UI must use standard ZIP only; legacy .wmnapp support must not remain',
  );
  requireCheck(appGenerator.contains("'checksums.sha256'"), 'application package integrity manifest missing');
  requireCheck(appGenerator.contains('WMN package contains unchecked entries'), 'application package does not reject unchecked archive entries');
  requireCheck(appGenerator.contains(r'apps/${manifest.name}/'), 'application asset ownership root is not enforced');
  requireCheck(appGenerator.contains('WmnApplicationBuildMode'), 'Development/Test/Release application build profiles missing');
  requireCheck(appGenerator.contains("'host_requirements': _hostRequirements"), 'application target host requirements are not generated from the manifest');
  requireCheck(appGenerator.contains("'android.permission.CAMERA'"), 'Android camera host declaration generation is missing');
  requireCheck(appGenerator.contains("'NSCameraUsageDescription'"), 'iOS camera usage declaration generation is missing');
  requireCheck(
    appGenerator.contains('if (diagnostic.errors.isNotEmpty)') &&
        appGenerator.contains("throw StateError(diagnostic.errors.join(' '));"),
    'application generator must never emit a package with hard validation errors',
  );
  requireCheck(
    appGenerator.contains('installPackage(') && appGenerator.contains('generatePackage('),
    'application package import/export runtime missing',
  );
  requireCheck(
    appGenerator.contains('schemaVersion > WmnPlatformVersion.schemaVersion'),
    'application package schema compatibility guard missing',
  );

  final managedProcedureRuntime = readText('lib/platform/scripts/wmn_managed_procedure_runtime.dart');
  final frappeHooks = readText('lib/framework/frappe_compat/frappe_hooks.dart');
  final frappeMethods = readText('lib/framework/frappe_compat/frappe_methods.dart');
  requireCheck(
    documentService.contains('saveEngineRecord') &&
        documentService.contains('deleteEngineRecord') &&
        documentService.contains('enforceGenericPolicy: false'),
    'managed applications cannot persist their own engine-owned ledger/cache DocTypes safely',
  );
  requireCheck(
    managedProcedureRuntime.contains("static const String language = 'wmn-procedure-v1'") &&
        managedProcedureRuntime.contains('_assertWriteAllowed') &&
        managedProcedureRuntime.contains('saveEngineRecord') &&
        managedProcedureRuntime.contains('deleteEngineRecord') &&
        !managedProcedureRuntime.contains('rawQuery') &&
        !managedProcedureRuntime.contains('Process.run'),
    'safe managed application procedure runtime is incomplete or exposes an unsafe execution surface',
  );
  requireCheck(
    bootstrap.contains('WmnManagedProcedureRuntime') &&
        bootstrap.contains('registerManagedExecutor') &&
        bootstrap.contains('scriptRuntime: scripts'),
    'managed application runtime is not registered once at platform bootstrap',
  );
  requireCheck(
    frappeHooks.contains("bindings(hookType: 'DOCUMENT_EVENT'") &&
        frappeHooks.contains('executeStored') &&
        frappeHooks.contains("path.startsWith('apps/\$sourceApp/')"),
    'persistent imported application hooks are not executable or app-source isolated',
  );
  requireCheck(
    frappeMethods.contains('_callServerScriptMethod') &&
        frappeMethods.contains("script_type'] ?? ''}' != 'API'") &&
        frappeMethods.contains('executeStored'),
    'managed application API Method execution is not wired',
  );
  for (final forbiddenComponent in const <String>[
    'business_records',
    'documents',
    'users',
    'user_roles',
    'workflow_actions',
  ]) {
    requireCheck(
      !appGenerator.contains("'$forbiddenComponent',"),
      'application package must not include runtime/business component: $forbiddenComponent',
    );
  }

  final kernel = readText('lib/platform/kernel/wmn_kernel.dart');
  requireCheck(kernel.contains('WmnServiceRegistry'), 'WMN Kernel service registry missing');
  requireCheck(kernel.contains('WmnExtensionRegistry'), 'WMN Kernel extension registry missing');
  requireCheck(kernel.contains('platformIssues()'), 'WMN Kernel does not include application compatibility in health');

  requireCheck(bootstrap.contains("register('wmn.database'"), 'WMN Kernel bootstrap service registration missing');
  requireCheck(bootstrap.contains("register('wmn.application_generator'"), 'Application Generator service is not registered in the WMN Kernel');
  requireCheck(
    bootstrap.contains("pageControllers.register(\n      'wmn.tool.data_exchange'") &&
        bootstrap.contains("register('wmn.data_exchange'"),
    'Data Import/Export Tool controller or engine registration is missing',
  );
  for (final ownerService in const <String>{
    'wmn.applications','wmn.application_generator','wmn.audit','wmn.jobs','wmn.meta','wmn.permissions','wmn.features',
    'wmn.files','wmn.notifications','wmn.pages','wmn.printing','wmn.reports','wmn.configuration',
    'wmn.identity','wmn.workflow','wmn.workspaces','wmn.data_exchange','wmn.logs',
  }) {
    requireCheck(bootstrap.contains("register('$ownerService'"), 'System DocType owner service is not registered: $ownerService');
  }
  for (final service in const <String>[
    'wmn.identity',
    'wmn.permissions',
    'wmn.configuration',
    'wmn.storage',
    'wmn.scripts',
    'wmn.files',
    'wmn.logs',
    'wmn.diagnostics',
    'wmn.jobs',
    'wmn.notifications',
    'wmn.printing',
    'wmn.platform_adapters',
    'wmn.navigation',
    'wmn.pages',
    'wmn.page_controllers',
    'wmn.query_reports',
    'wmn.script_reports',
    'wmn.reports',
  ]) {
    requireCheck(bootstrap.contains("register('$service'"), 'shared system service registration missing: $service');
  }
  requireCheck(
    bootstrap.contains('queryReports: queryReports,'),
    'WmnRuntime Query Report service wiring missing from bootstrap',
  );
  requireCheck(
    RegExp(r"WmnExtensionPoint\s*\(\s*id:\s*'shell\.navigation'").hasMatch(bootstrap),
    'WMN native extension point seeding missing',
  );
  requireCheck(
    RegExp(r"WmnExtensionPoint\s*\(\s*id:\s*'platform\.adapters'").hasMatch(bootstrap),
    'platform adapter extension point missing',
  );
  requireCheck(
    RegExp(r"WmnExtensionPoint\s*\(\s*id:\s*'pages\.controllers'").hasMatch(bootstrap),
    'Page controller extension point missing',
  );
  requireCheck(bootstrap.contains('await platformAdapters.initialize();'), 'platform adapters are not initialized before capability resolution');
  requireCheck(bootstrap.contains('kernel.start();'), 'WMN Kernel is not started by bootstrap');

  requireCheck(shell.contains("route: 'home'"), 'platform shell Home route missing');
  requireCheck(shell.contains("route: 'system_modules'"), 'platform shell System Modules route missing');
  requireCheck(shell.contains("route: 'doctypes'"), 'platform shell DocType route missing');
  requireCheck(shell.contains("route: 'methods'"), 'platform shell Method Modules route missing');
  requireCheck(shell.contains("route: 'reports'"), 'platform shell Reports route missing');
  requireCheck(shell.contains("route: 'platform_adapters'"), 'platform shell Platform Adapters route missing');
  requireCheck(shell.contains('WmnPlatformAdaptersPage'), 'Platform Adapters Center is not wired into the shell');
  requireCheck(shell.contains("route: 'system_services'"), 'platform shell System Services route missing');
  requireCheck(shell.contains('WmnSystemServicesPage'), 'System Services Center is not wired into the platform shell');
  requireCheck(shell.contains("route: 'settings'"), 'platform shell Settings route missing');
  requireCheck(shell.contains("route: 'developer_center'"), 'platform shell Developer Center route missing');
  requireCheck(shell.contains('WmnDeveloperCenterPage'), 'Developer Center is not wired into the platform shell');
  requireCheck(shell.contains('r.navigation.visibleWorkspaces()'), 'sidebar is not driven by permission-aware Workspaces');
  requireCheck(shell.contains('r.navigation.entries()'), 'application navigation is not manifest-driven');
  requireCheck(shell.contains("'app_route'"), 'application route runtime is not wired into the shell');
  requireCheck(
    shell.contains('_searchController') &&
        shell.contains('TextInputAction.search') &&
        shell.contains('onSubmitted: _runGlobalSearch') &&
        shell.contains('void _runGlobalSearch('),
    'global shell search is missing',
  );
  requireCheck(shell.contains("isEnabled('reports')"), 'optional Reports navigation is not capability-aware');
  requireCheck(shell.contains("isEnabled('developer')"), 'Developer navigation is not capability-aware');
  requireCheck(!shell.toLowerCase().contains("route: 'pos'"), 'POS route remains in platform shell');

  final navigation = readText('lib/platform/navigation/wmn_navigation_registry.dart');
  requireCheck(navigation.contains('canAccessPath'), 'application route access guard missing');
  requireCheck(navigation.contains('canAccessReport'), 'report access guard missing');
  requireCheck(navigation.contains('visibleWorkspaces'), 'permission-aware Workspace filtering missing');
  requireCheck(navigation.contains('requiredPermissions'), 'route permission enforcement missing');
  requireCheck(navigation.contains('requiredRoles'), 'route role enforcement missing');

  final workspacePageSecurity = readText('lib/framework/workspaces/workspace_page.dart');
  requireCheck(workspacePageSecurity.contains('canReadDoctype'), 'Workspace data widgets are not permission-aware');
  requireCheck(workspacePageSecurity.contains('canOpenReport'), 'Workspace Report links are not permission-aware');
  requireCheck(workspacePageSecurity.contains('_visibleItem'), 'Workspace permission-aware rendering filter missing');
  requireCheck(shell.contains('_openReport'), 'Workspace Report targets do not open through the guarded native report surface');
  requireCheck(shell.contains('routedWorkspaceNames'), 'application-owned routed Workspaces are duplicated in generic navigation');

  final frappePackageConverter = readText('lib/framework/apps/frappe_app_package_converter.dart');
  requireCheck(frappePackageConverter.contains('_syncApplicationNavigationManifest'), 'Frappe Workspace route generation missing');
  requireCheck(frappePackageConverter.contains("'route_definitions': routeDefinitions"), 'converted application manifest route definitions missing');
  requireCheck(frappePackageConverter.contains("substring(0, 8)"), 'generated Workspace route slug is not collision-hardened');

  final fileService = readText('lib/platform/files/wmn_file_service.dart');
  requireCheck(fileService.contains('WmnStorageService'), 'File service is not backed by the Storage Runtime');
  requireCheck(fileService.contains('storage.writeBytes'), 'file bytes are not externalized through Storage Runtime');
  requireCheck(!fileService.contains('INSERT INTO wmn_file_contents'), 'File service still writes BLOB content into SQLite');
  requireCheck(fileService.contains('attachedToDoctype'), 'generic document attachment contract is missing');
  final storageRuntime = readText('lib/platform/storage/wmn_storage_service.dart');
  requireCheck(storageRuntime.contains('class WmnStorageService'), 'Storage Runtime missing');
  requireCheck(storageRuntime.contains('_externalizeDatabaseBlobs'), 'native storage externalization bridge missing');
  requireCheck(storageRuntime.contains('readBytesAsync') && storageRuntime.contains('writeBytesAsync'), 'Storage Runtime async large-object API missing');
  requireCheck(storageRuntime.contains('_maxTextCacheEntries'), 'Storage Runtime small-source cache missing');
  final nativeStorage = readText('lib/platform/storage/wmn_storage_native.dart');
  requireCheck(nativeStorage.contains('readAsBytes()') && nativeStorage.contains('writeAsBytes(bytes'), 'native async directory I/O missing');
  final preMigrationStorage = readText('lib/core/database/platform/pre_migration_storage_native.dart');
  requireCheck(preMigrationStorage.contains('wmn_platform_pre_r315_v25_'), 'R3.15 automatic v25 rollback backup missing');
  requireCheck(preMigrationStorage.contains('wal_checkpoint(TRUNCATE)'), 'R3.15 rollback backup is not WAL-checkpointed');
  final scriptRuntime = readText('lib/platform/scripts/wmn_script_runtime.dart');
  requireCheck(scriptRuntime.contains('registerNativeHandler'), 'native script handler registry missing');
  requireCheck(scriptRuntime.contains('registerManagedExecutor'), 'managed script executor registry missing');
  requireCheck(scriptRuntime.contains('executeStored'), 'stored managed script execution contract missing');
  requireCheck(bootstrap.contains("id: 'storage.adapters'"), 'generic Storage adapter extension point missing');

  final customizationRepository = readText('lib/modules/customization/data/customization_repository.dart');
  requireCheck(customizationRepository.contains('source_storage_path'), 'Client/Server Script metadata is not path-backed');
  requireCheck(customizationRepository.contains('storage.writeText'), 'Client/Server Script source is not externalized');

  final configuration = readText('lib/platform/configuration/wmn_configuration_service.dart');
  requireCheck(configuration.contains('WmnConfigurationScope'), 'scoped configuration contract is missing');
  requireCheck(configuration.contains('wmn_scoped_settings'), 'scoped configuration persistence is missing');

  final jobs = readText('lib/platform/jobs/wmn_job_service.dart');
  requireCheck(jobs.contains('scheduleEvery'), 'scheduler interval contract is missing');
  requireCheck(jobs.contains('enqueueDueSchedules'), 'due-schedule enqueue contract is missing');

  final notifications = readText('lib/platform/notifications/wmn_notification_service.dart');
  requireCheck(notifications.contains('notifyInApp'), 'in-app notification foundation is missing');
  requireCheck(notifications.contains("status: 'QUEUED'"), 'external notification outbox boundary is missing');

  final diagnostics = readText('lib/platform/diagnostics/wmn_diagnostics_service.dart');
  requireCheck(diagnostics.contains('WmnDiagnosticsSnapshot'), 'diagnostics health snapshot contract is missing');

  final printing = readText('lib/platform/printing/wmn_printing_service.dart');
  requireCheck(printing.contains('WmnPrintRenderer'), 'platform-neutral print renderer contract is missing');
  requireCheck(printing.contains('queueDocument'), 'generic print-job queue contract is missing');
  requireCheck(printing.contains('resolveFormat('), 'metadata-driven Print Format resolver is missing');
  requireCheck(printing.contains("target_type='DOCUMENT'") && printing.contains("target_type='REPORT'") && printing.contains("target_type='GENERAL_REPORT'") && printing.contains("target_type='PLATFORM'"), 'Print Format fallback resolution is incomplete');
  requireCheck(printing.contains('outputFileId') && printing.contains("status='SENT'"), 'Print Job/File execution lifecycle is incomplete');
  requireCheck(printing.contains('printing.advanced'), 'advanced printing entitlement gate is missing');
  for (final path in const <String>[
    'lib/platform/printing/wmn_print_models.dart',
    'lib/platform/printing/wmn_print_template_engine.dart',
    'lib/platform/printing/wmn_report_print_layout.dart',
    'lib/platform/printing/wmn_barcode_service.dart',
    'lib/platform/printing/wmn_print_renderer.dart',
    'lib/platform/printing/wmn_print_adapter.dart',
    'lib/platform/printing/wmn_print_preview_dialog.dart',
    'lib/platform/printing/renderers/wmn_html_print_renderer.dart',
    'lib/platform/printing/renderers/wmn_pdf_print_renderer.dart',
    'lib/platform/printing/renderers/wmn_html_pdf_converter.dart',
    'lib/platform/printing/renderers/wmn_html_pdf_converter_io.dart',
    'lib/platform/printing/renderers/wmn_html_pdf_converter_stub.dart',
    'lib/platform/printing/renderers/wmn_escpos_print_renderer.dart',
    'lib/platform/printing/adapters/wmn_system_print_adapter.dart',
    'lib/platform/printing/adapters/wmn_pdf_preview_widget.dart',
    'lib/platform/printing/adapters/wmn_platform_raw_adapters.dart',
    'lib/platform/printing/adapters/wmn_platform_raw_adapters_io.dart',
    'lib/platform/printing/adapters/wmn_platform_raw_adapters_stub.dart',
    'lib/platform/printing/adapters/wmn_windows_raw_spooler.dart',
    'lib/core/database/migrations/migration_030_printing_pdf_engine.dart',
    'lib/core/database/migrations/migration_034_structured_report_printing.dart',
    'lib/core/database/migrations/migration_035_frappe_print_runtime.dart',
    'test/printing_engine_test.dart',
  ]) {
    requireCheck(File('${root.path}${Platform.pathSeparator}${path.replaceAll('/', Platform.pathSeparator)}').existsSync(), 'R3.16.1 printing runtime file missing: $path');
  }
  final pubspec = readText('pubspec.yaml');
  requireCheck(pubspec.contains('archive: 3.6.1') && pubspec.contains("image: '>=4.3.0 <4.7.0'") && pubspec.contains('pdf: 3.12.0') && pubspec.contains('printing: 5.14.3') && pubspec.contains('barcode: ^2.2.9'), 'Printing/PDF dependency compatibility set is incomplete');
  requireCheck(
    pubspec.contains('url_launcher: ^6.3.2') &&
        pubspec.contains('share_plus: ^13.3.0') &&
        pubspec.contains('connectivity_plus: ^7.3.1') &&
        pubspec.contains('device_info_plus: ^13.2.0') &&
        pubspec.contains('image_picker: ^1.2.3') &&
        pubspec.contains('file_saver: ^0.4.0') &&
        pubspec.contains('flutter_barcode_scanner_plus: ^3.0.12') &&
        !pubspec.contains('barcode_scan2:'),
    'R3.18 native adapter dependency set is incomplete',
  );
  final printingServiceSource = readText('lib/platform/printing/wmn_printing_service.dart');
  final printRendererContractSource = readText('lib/platform/printing/wmn_print_renderer.dart');
  final printAdapterContractSource = readText('lib/platform/printing/wmn_print_adapter.dart');
  requireCheck(!printingServiceSource.contains('package:pdf/') && !printingServiceSource.contains('package:printing/'), 'Printing service must remain package-neutral');
  requireCheck(!printRendererContractSource.contains('package:pdf/') && !printRendererContractSource.contains('package:printing/'), 'Print renderer contract must remain package-neutral');
  requireCheck(!printAdapterContractSource.contains('package:pdf/') && !printAdapterContractSource.contains('package:printing/'), 'Print adapter contract must remain package-neutral');
  final printTemplate = readText('lib/platform/printing/wmn_print_template_engine.dart');
  requireCheck(printTemplate.contains('tokenHelp') && printTemplate.contains('#each') && printTemplate.contains('barcode') && printTemplate.contains('qr'), 'Print Format token help/runtime is incomplete');
  final structuredHtmlRenderer = readText('lib/platform/printing/renderers/wmn_html_print_renderer.dart');
  requireCheck(structuredHtmlRenderer.contains(r'dir="$direction"') && structuredHtmlRenderer.contains('<meta charset="utf-8">') && structuredHtmlRenderer.contains('languageCode'), 'HTML print renderer language-driven RTL/UTF-8 envelope is incomplete');
  final reportPrintLayout = readText('lib/platform/printing/wmn_report_print_layout.dart');
  requireCheck(
    reportPrintLayout.contains('WMN_REPORT_TABLE') &&
        reportPrintLayout.contains('column_definitions') &&
        reportPrintLayout.contains('filter_definitions'),
    'structured report print layout model is incomplete',
  );
  requireCheck(
    htmlRenderer.contains('reportLayout.tableHtml()') && htmlRenderer.contains('reportLayout.filtersHtml()'),
    'HTML structured report table/filter rendering is incomplete',
  );
  requireCheck(
    pdfRenderer.contains('WmnHtmlPrintRenderer') &&
        pdfRenderer.contains('html.debugText') &&
        !pdfConverter.contains('pw.Table('),
    'PDF must consume the same canonical structured HTML as preview',
  );
  requireCheck(
    printingServiceSource.contains('columnDefinitions') &&
        printingServiceSource.contains('filterDefinitions') &&
        printingServiceSource.contains('languageCode') &&
        printingServiceSource.contains("'language_code'") &&
        printingServiceSource.contains('WmnReportPrintLayout.tableMarker'),
    'Printing service does not preserve structured/localized report metadata',
  );
  requireCheck(
    reportPrintLayout.contains("definition['label_\$language']") &&
        reportPrintLayout.contains("report['language_code']"),
    'structured report print layout does not resolve localized labels',
  );
  final frappeReportService = readText('lib/modules/reporting/application/frappe_report_service.dart');
  requireCheck(
    reportPage.contains('_refreshDefinitionMetadata') &&
        reportPage.contains('_mergeCurrentColumnMetadata') &&
        reportPage.contains('languageCode: WmnL10nScope.controllerOf(context).languageCode'),
    'report page does not refresh live labels before run/print',
  );
  requireCheck(
    frappeReportService.contains('_applyCurrentColumnMetadata') &&
        frappeReportService.contains('...metadata'),
    'report execution does not merge current Report Column metadata',
  );
  requireCheck(
    htmlRenderer.contains('_isRtlLanguage') &&
        htmlRenderer.contains(r'dir="$direction"') &&
        !pdfConverter.contains('WmnPdfFontResolverIo'),
    'PDF RTL/Unicode must be owned by canonical HTML and the browser text engine',
  );
  final rawAdapter = readText('lib/platform/printing/adapters/wmn_platform_raw_adapters_io.dart');
  requireCheck(rawAdapter.contains('direct Android/iOS Bluetooth GATT') || rawAdapter.contains('Direct Android/iOS Bluetooth GATT'), 'deferred Android/iOS Bluetooth GATT boundary must stay explicit');

  for (final path in const <String>[
    'lib/platform/files/wmn_file_adapter.dart',
    'lib/platform/files/wmn_file_interaction_service.dart',
    'lib/platform/files/wmn_file_service.dart',
    'lib/platform/files/adapters/wmn_file_selector_adapter.dart',
    'lib/platform/files/adapters/wmn_native_file_dialog_adapter.dart',
    'lib/platform/files/adapters/wmn_file_reference_io.dart',
    'lib/platform/files/adapters/wmn_file_reference_stub.dart',
    'lib/core/database/migrations/migration_031_files_attachments_adapters.dart',
    'test/files_attachments_adapters_test.dart',
    'test/native_adapters_test.dart',
  ]) {
    requireCheck(
      File('${root.path}${Platform.pathSeparator}${path.replaceAll('/', Platform.pathSeparator)}').existsSync(),
      'R3.17 Files & Attachments runtime file missing: $path',
    );
  }
  for (final file in filesUnder('lib', extension: '.dart')) {
    final relative = relativePath(file).replaceAll('\\', '/');
    final source = file.readAsStringSync();
    if (!source.contains('package:file_selector/')) continue;
    requireCheck(
      relative == 'lib/platform/files/adapters/wmn_file_selector_adapter.dart',
      'file_selector leaked outside the Files platform adapter boundary: $relative',
    );
  }
  const nativeAdapterPackageTokens = <String>[
    'package:url_launcher/',
    'package:share_plus/',
    'package:connectivity_plus/',
    'package:device_info_plus/',
    'package:image_picker/',
    'package:file_saver/',
    'package:flutter_barcode_scanner_plus/',
  ];
  const nativeAdapterImportPrefixes = <String>[
    'lib/platform/adapters/native/',
    'lib/platform/files/adapters/wmn_native_file_dialog_adapter.dart',
  ];
  for (final file in filesUnder('lib', extension: '.dart')) {
    final relative = relativePath(file).replaceAll('\\', '/');
    final source = file.readAsStringSync();
    if (!nativeAdapterPackageTokens.any(source.contains)) continue;
    final isolated = nativeAdapterImportPrefixes.any(
      (prefix) => prefix.endsWith('.dart') ? relative == prefix : relative.startsWith(prefix),
    );
    requireCheck(
      isolated,
      'native plugin package leaked outside the platform adapter boundary: $relative',
    );
  }
  final nativeContractsSource = readText('lib/platform/adapters/contracts/wmn_platform_contracts.dart');
  requireCheck(
    nativeContractsSource.contains('abstract interface class WmnExternalOpenAdapter') &&
        nativeContractsSource.contains('abstract interface class WmnClipboardAdapter') &&
        nativeContractsSource.contains('abstract interface class WmnConnectivityAdapter') &&
        nativeContractsSource.contains('abstract interface class WmnDeviceInfoAdapter') &&
        nativeContractsSource.contains('shareBytes'),
    'R3.18 platform-neutral native contracts are incomplete',
  );
  final mobileScannerSource = readText('lib/platform/adapters/native/wmn_mobile_barcode_scanner.dart');
  requireCheck(
    mobileScannerSource.contains('package:flutter_barcode_scanner_plus/') &&
        mobileScannerSource.contains("value == '-1'") &&
        !mobileScannerSource.contains('package:barcode_scan2/'),
    'Mobile scanner must not use the legacy barcode_scan2 Android support chain',
  );
  final nativeServicesSource = readText('lib/platform/adapters/native/wmn_flutter_native_services.dart');
  requireCheck(
    nativeServicesSource.contains('class WmnNativeShareService') &&
        nativeServicesSource.contains('class WmnNativeBrowserService') &&
        nativeServicesSource.contains('class WmnNativeClipboardService') &&
        nativeServicesSource.contains('class WmnNativeConnectivityService') &&
        nativeServicesSource.contains('class WmnNativeDeviceInfoService') &&
        nativeServicesSource.contains('class WmnNativeCameraService') &&
        nativeServicesSource.contains('class WmnNativeDownloadService'),
    'R3.18 cross-platform native service adapters are incomplete',
  );
  final nativeFileDialogSource = readText('lib/platform/files/adapters/wmn_native_file_dialog_adapter.dart');
  requireCheck(
    nativeFileDialogSource.contains('class WmnNativeFileDialogAdapter') &&
        nativeFileDialogSource.contains('FileSaver.instance.saveAs') &&
        nativeFileDialogSource.contains('supportsExternalReferences => _selector.supportsExternalReferences'),
    'R3.18 native save/export adapter or external-reference boundary is incomplete',
  );
  final fileServiceSource = readText('lib/platform/files/wmn_file_service.dart');
  final fileInteractionSource = readText('lib/platform/files/wmn_file_interaction_service.dart');
  final fileAdapterSource = readText('lib/platform/files/wmn_file_adapter.dart');
  requireCheck(
    fileServiceSource.contains('WmnFileContentMode') &&
        fileServiceSource.contains('managedStorage') &&
        fileServiceSource.contains('externalReference') &&
        fileServiceSource.contains('registerExternalReference') &&
        fileServiceSource.contains('file_settings'),
    'optional Managed Storage / External Reference file lifecycle is incomplete',
  );
  requireCheck(
    fileInteractionSource.contains('contentMode ?? defaultContentMode') &&
        fileInteractionSource.contains('Choose Managed Storage for this file'),
    'per-operation file content-mode selection or explicit unsupported behavior is missing',
  );
  requireCheck(
    fileAdapterSource.contains('WmnFileDialogAdapter') &&
        fileAdapterSource.contains('WmnFileReferenceAdapter'),
    'file dialog/reference adapter contracts are incomplete',
  );
  final fileMigrationSource = readText('lib/core/database/migrations/migration_031_files_attachments_adapters.dart');
  requireCheck(
    fileMigrationSource.contains("'MANAGED_STORAGE','EXTERNAL_REFERENCE'") &&
        fileMigrationSource.contains("'File Settings'") &&
        fileMigrationSource.contains('storage_optional'),
    'v31 storage-optional metadata migration is incomplete',
  );
  final attachmentsFormSource = readText('lib/framework/ui/form/wmn_form_view.dart');
  requireCheck(
    attachmentsFormSource.contains('_showAttachments') &&
        attachmentsFormSource.contains('_chooseAttachmentMode') &&
        attachmentsFormSource.contains("context.wmnT('attachments')"),
    'generic DocType attachment UI is not wired to the Files runtime',
  );

  final platformRegistry = readText('lib/platform/adapters/wmn_platform_adapter_registry.dart');
  requireCheck(platformRegistry.contains('runtimePlatform'), 'runtime platform detection/registry missing');
  requireCheck(platformRegistry.contains('knownCapabilityIds'), 'platform adapter capability inventory missing');
  requireCheck(platformRegistry.contains('resolveService'), 'platform adapter service resolution missing');

  final windowsAdapter = readText('lib/platform/adapters/windows/wmn_windows_platform_adapter_io.dart');
  requireCheck(windowsAdapter.contains('WmnWindowsPlatformService'), 'Windows platform service missing');
  requireCheck(windowsAdapter.contains('getApplicationSupportDirectory'), 'Windows filesystem integration missing');
  requireCheck(windowsAdapter.contains('discoverDevices'), 'Windows device discovery foundation missing');
  requireCheck(!windowsAdapter.contains('Process.run(command'), 'Windows adapter must not expose arbitrary command execution');
  requireCheck(windowsAdapter.contains("id: 'files.external-reference'") && windowsAdapter.contains('WmnPlatformCapabilityStatus.available'), 'Windows external file-reference capability is missing');
  requireCheck(
    windowsAdapter.contains("id: 'external-open'") &&
        windowsAdapter.contains("id: 'windows.share'") &&
        windowsAdapter.contains("id: 'windows.clipboard'") &&
        windowsAdapter.contains("id: 'windows.connectivity'") &&
        windowsAdapter.contains("serviceId: 'wmn.native.device-info'"),
    'Windows native open/share/clipboard/connectivity/device-info capabilities are incomplete',
  );

  final mobileAdapter = readText('lib/platform/adapters/mobile/wmn_mobile_platform_adapter_io.dart');
  requireCheck(mobileAdapter.contains('mobile.sms.read'), 'Mobile SMS contract capability missing');
  requireCheck(mobileAdapter.contains('mobile.whatsapp.share'), 'Mobile WhatsApp share contract capability missing');
  requireCheck(mobileAdapter.contains('mobile.permissions'), 'Mobile permissions contract capability missing');
  requireCheck(mobileAdapter.contains("id: 'files.external-reference'") && mobileAdapter.contains('WmnPlatformCapabilityStatus.unavailable'), 'Mobile external-reference limitation must remain explicit until scoped-storage adapter work');
  requireCheck(
    mobileAdapter.contains("id: 'files.save'") &&
        mobileAdapter.contains("id: 'mobile.share'") &&
        mobileAdapter.contains("id: 'mobile.camera'") &&
        mobileAdapter.contains("id: 'mobile.scanner'") &&
        mobileAdapter.contains("id: 'mobile.connectivity'") &&
        mobileAdapter.contains("serviceId: 'wmn.native.device-info'"),
    'Mobile native save/share/camera/scanner/connectivity/device-info capabilities are incomplete',
  );
  requireCheck(
    mobileAdapter.contains("id: 'mobile.bluetooth-gatt'") &&
        mobileAdapter.contains('WmnPlatformCapabilityStatus.planned'),
    'Mobile BLE GATT must remain an explicit planned boundary until host manifests/permissions are generated',
  );

  final webAdapter = readText('lib/platform/adapters/web/wmn_web_platform_adapter.dart');
  requireCheck(webAdapter.contains("id: 'files.external-reference'") && webAdapter.contains('WmnPlatformCapabilityStatus.unavailable'), 'Web external-reference limitation must remain explicit');
  requireCheck(
    webAdapter.contains("id: 'web.download'") &&
        webAdapter.contains("id: 'web.share'") &&
        webAdapter.contains("id: 'web.clipboard'") &&
        webAdapter.contains("id: 'web.connectivity'") &&
        webAdapter.contains("id: 'web.camera'") &&
        webAdapter.contains("serviceId: 'wmn.native.device-info'"),
    'Web native browser/download/share/clipboard/connectivity/device-info/camera foundation is incomplete',
  );

  final serverAdapter = readText('lib/platform/adapters/server/wmn_server_platform_adapter.dart');
  requireCheck(serverAdapter.contains('server.api') && serverAdapter.contains('server.tokens'), 'Server API/token contracts missing');

  final workspaces = readText('lib/framework/workspaces/workspace_service.dart');
  requireCheck(workspaces.contains('ensurePlatformWorkspaces()'), 'platform workspace seeding missing');
  requireCheck(!workspaces.contains('ensureCoreWorkspaces()'), 'legacy auto-business workspace generator remains');
  requireCheck(workspaces.contains('dashboardChartsEnabled = true'), 'dashboard charts are not enabled');
  requireCheck(workspaces.contains('dashboardChartSeries('), 'native dashboard chart aggregation engine missing');

  requireCheck(!workspacePage.contains('customer_name') && !workspacePage.contains('item_name') && !workspacePage.contains('supplier_name'), 'Workspace rendering still contains business-specific field assumptions');

  final reports = readText('lib/modules/reporting/application/report_builder_service.dart');
  requireCheck(reports.contains('static const List<WmnReportSource> _sources = <WmnReportSource>[];'), 'report sources are not application-driven');

  final customization = readText('lib/modules/customization/application/customization_service.dart');
  requireCheck(customization.contains('static const List<String> customizableDocumentTypes = <String>[];'), 'customization service still hardcodes business DocTypes');

  final database = readText('lib/core/database/wmn_database.dart');
  requireCheck(database.contains(r"SAVEPOINT $savepoint"), 'nested platform transaction SAVEPOINT support missing');
  requireCheck(database.contains('ROLLBACK TO SAVEPOINT'), 'nested platform transaction rollback support missing');
}

void verifySafeExtensionRuntime() {
  final reportPage = readText('lib/platform/navigation/wmn_application_report_page.dart');
  final engine = readText('lib/modules/customization/application/script_engine.dart');
  requireCheck(engine.contains('bool get executionEnabled => false;'), 'generic script execution must remain gated');

  final methods = readText('lib/framework/frappe_compat/frappe_methods.dart');
  for (final api in const <String>[
    'wmn.db.insert',
    'wmn.db.update',
    'wmn.db.delete',
    'wmn.document.insert',
    'wmn.document.update',
    'wmn.document.delete',
  ]) {
    requireCheck(methods.contains("'$api'"), 'safe system API missing: $api');
  }

  final management = readText('lib/framework/frappe_compat/frappe_method_management.dart');
  requireCheck(management.contains('PYTHON_MODULE_FILE'), 'Method Modules are not represented as Python-module equivalents');
  requireCheck(management.contains('SYSTEM_METHOD_MODULE'), 'global System Method Module management missing');
  requireCheck(management.contains('SYSTEM_GLOBAL'), 'global extension scope missing');
  requireCheck(management.contains('WmnStorageService'), 'managed Method/System Script source storage runtime missing');
  requireCheck(management.contains('storage.writeText'), 'managed Method/System Script source is not externalized');
  requireCheck(management.contains('source_path'), 'managed Method/System Script source path metadata missing');
  requireCheck(!management.contains("'source': source"), 'managed Method/System Script source still stored inline in metadata');

  final storageMigration = readText('lib/core/database/migrations/migration_026_report_storage_runtime.dart');
  requireCheck(storageMigration.contains('_migrateManagedHookSources'), 'legacy Method/System Script storage migration missing');

  final reports = readText('lib/modules/reporting/application/script_report_service.dart');
  requireCheck(reports.contains('[tabReport]'), 'Script Report is not sourced from the Report DocType');
  requireCheck(reports.contains('scriptRuntime.executeStored'), 'managed Script Report storage execution missing');
  requireCheck(reports.contains('scriptRuntime.executeNative'), 'native Script Report handler execution missing');
  requireCheck(!reports.contains('wmn_script_reports'), 'Script Report parallel definition table returned');
  requireCheck(reports.contains('[tabReport Filter]') && reports.contains('[tabReport Column]'), 'Script Report runtime does not read child-table filters/columns');
  final frappeReports = readText('lib/modules/reporting/application/frappe_report_service.dart');
  requireCheck(frappeReports.contains('_reportFilterRows') && frappeReports.contains('_reportColumnRows') && frappeReports.contains('_replaceReportChildren'), 'Report dispatcher child-table metadata runtime missing');
  final sourcePorter = readText('lib/framework/apps/frappe_source_porter.dart');
  requireCheck(!sourcePorter.contains('.map((row) => hydrateSourceUnit'), 'App source-unit lists still eagerly load source files');
  requireCheck(sourcePorter.contains('Map<String, Object?>? sourceUnit('), 'Lazy single source-unit hydration API is missing');
  final studio = readText('lib/framework/doctype_studio/doctype_studio_service.dart');
  requireCheck(!studio.contains('_hydrateRevision(WmnStudioRevision.fromJson'), 'DocType Studio revision list still eagerly reads revision files');
  requireCheck(studio.contains('String revisionSource('), 'DocType Studio lazy revision source resolver is missing');
  requireCheck(File('${root.path}${Platform.pathSeparator}tool${Platform.pathSeparator}benchmark_r315_transition.dart').existsSync(), 'R3.15 transition benchmark tool is missing');
  requireCheck(reportPage.contains('PaginatedDataTable'), 'Report result UI does not paginate large row sets');
  requireCheck(reportPage.contains('_WmnReportDataSource'), 'Report paginated data source missing');
  requireCheck(reportPage.contains("context.wmnT('report_results')"), 'Report results heading is missing');
  final reportResultsStart = reportPage.indexOf("context.wmnT('report_results')");
  final reportResultsEnd = reportPage.indexOf('List<(String, String)> _columns');
  final reportResultsUi = reportResultsStart >= 0 && reportResultsEnd > reportResultsStart
      ? reportPage.substring(reportResultsStart, reportResultsEnd)
      : '';
  requireCheck(
    reportResultsUi.contains('SizedBox(') &&
        reportResultsUi.contains('width: double.infinity') &&
        reportResultsUi.contains('PaginatedDataTable('),
    'Report table is not bound directly to the finite report-page width',
  );
  requireCheck(
    !reportResultsUi.contains('SingleChildScrollView(') &&
        !reportResultsUi.contains('Scrollbar('),
    'Report table must not be wrapped by an outer horizontal scroll viewport',
  );
  requireCheck(reportPage.contains('showEmptyRows: false'), 'Report table should not reserve invisible empty rows');
  requireCheck(!reports.contains('JsRuntime') && !reports.contains('package:jsf'), 'Script Reports must not depend on JSF');

  final queryReports = readText('lib/modules/reporting/application/query_report_service.dart');
  requireCheck(queryReports.contains('class WmnQueryReportSafetyPolicy'), 'Query Report safety policy missing');
  requireCheck(queryReports.contains('allowsDataModification = false'), 'Query Report write boundary missing');
  requireCheck(queryReports.contains('allowsSchemaModification = false'), 'Query Report schema-write boundary missing');
  requireCheck(queryReports.contains('allowsMultipleStatements = false'), 'Query Report multi-statement boundary missing');
  requireCheck(
    RegExp(r"allowedStatementPrefixes\s*=\s*<String>\{[\s\S]*?'SELECT'[\s\S]*?'WITH'").hasMatch(queryReports),
    'Query Report SELECT/WITH allow-list missing',
  );
  requireCheck(queryReports.contains('forbiddenKeywords'), 'Query Report forbidden-keyword guard missing');
  requireCheck(queryReports.contains('requiresBoundParameters = true'), 'Query Report bound-parameter policy missing');
  requireCheck(
    RegExp(r'''final\s+compiled\s*=\s*_compileBoundParameters\(''').hasMatch(queryReports),
    'Query Report bound-parameter compiler invocation missing',
  );
  requireCheck(
    RegExp(r'''\.write\(\s*['"]\?['"]\s*\)''').hasMatch(queryReports),
    'Query Report placeholder-to-SQLite-parameter compilation missing',
  );
  requireCheck(
    RegExp(r'''parameters\.add\(\s*effectiveFilters\[name\]\s*\)''').hasMatch(queryReports),
    'Query Report compiled parameter collection missing',
  );
  requireCheck(
    RegExp(
      r'''<Object\?>\[\s*\.\.\.parameters\s*,\s*safeMax\s*\+\s*1\s*\]''',
    ).hasMatch(queryReports),
    'Query Report compiled parameters are not passed to SQLite execution',
  );
}

void main() {
  final script = File.fromUri(Platform.script).absolute;
  root = script.parent.parent;

  final pubspec = readText('pubspec.yaml');
  final versionMatch = RegExp(r'^version:\s*([^\s]+)', multiLine: true).firstMatch(pubspec);
  final releaseVersion = versionMatch?.group(1) ?? 'unknown';
  requireCheck(versionMatch != null, 'pubspec version is missing');
  requireCheck(releaseVersion == '3.25.0+127', 'pubspec version is $releaseVersion, expected 3.25.0+127');
  requireCheck(!RegExp(r'^\s*jsf:', multiLine: true).hasMatch(pubspec), 'jsf dependency must not exist');

  verifyReleaseSourceTree();
  verifyRelativeImports();
  final queryRuntime = readText('lib/modules/reporting/application/query_report_service.dart');
  requireCheck(queryRuntime.contains('class WmnQueryReportService'), 'native Query Report runtime missing');
  requireCheck(queryRuntime.contains('Query Report must start with SELECT or WITH'), 'Query Report read-only guard missing');
  final reportRuntime = readText('lib/modules/reporting/application/frappe_report_service.dart');
  requireCheck(reportRuntime.contains("_requireFeature('reports.query')"), 'Query Report feature gate missing');
  requireCheck(reportRuntime.contains("_requireFeature('reports.script')"), 'Script Report feature gate missing');
  verifyLocalizationHasNoDuplicateKeys();
  verifyCleanSource();
  verifyPlatformSchema();
  verifyPlatformArchitecture();
  verifySafeExtensionRuntime();

  if (warnings.isNotEmpty) {
    for (final warning in warnings) {
      stdout.writeln('WARNING: $warning');
    }
  }

  if (errors.isNotEmpty) {
    stdout.writeln('WMN PLATFORM VERIFICATION: FAIL');
    for (final error in errors) {
      stdout.writeln(' - $error');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln('WMN PLATFORM VERIFICATION: PASS');
  stdout.writeln(' - version: $releaseVersion');
  stdout.writeln(' - schema: v36 Application Generator & Packaging + v35 Frappe-compatible printing');
  stdout.writeln(' - business applications: removed from WMN System Core');
  stdout.writeln(' - shell: one width-driven responsive UI; narrow Windows and mobile share the compact layout');
  stdout.writeln(' - kernel: service registry + native extension points + transactional document event runtime');
  stdout.writeln(' - system modules: versioned contracts + dependency-first lifecycle + protected enable/disable');
  stdout.writeln(' - capabilities: versioned contracts + dependencies + profiles + protected optional state');
  stdout.writeln(' - applications: manifest diagnostics + executable Page/Workspace/DocType/Report routes + roles/permission gates');
  stdout.writeln(' - generator: portable manifest/metadata/source/assets packaging + ownership/dependency/integrity validation + import/install + build profiles/history');
  stdout.writeln(' - system DocTypes: security/pages/reports/workflows/printing/jobs/files/file-settings/features mapped to native tables');
  stdout.writeln(' - Page runtime: lazy metadata loading + declarative renderer + compiled controller extension point');
  stdout.writeln(' - reports: Report DocType is the single source; Query SQL and managed scripts externalized to Storage; native/managed Script Runtime');
  stdout.writeln(' - report printing: structured columns/filters + real HTML/PDF tables + repeated PDF headers + auto-landscape');
  stdout.writeln(' - PDF: canonical HTML/CSS/UTF-8 -> platform/Chromium backend; no text inspection or font-file resolver');
  stdout.writeln(' - workflows: lazy native approvals + role transitions + safe conditions + atomic history/rollback');
  stdout.writeln(' - feature control: entitlement + user activation; no automatic device disabling');
  stdout.writeln(' - developer center: kernel/capabilities/apps/extensions visibility');
  stdout.writeln(' - system services: files/attachments/configuration/logs/diagnostics/jobs/notifications + executable Printing/PDF runtime');
  stdout.writeln(' - documents: transactional lifecycle + priority/wildcard event bus + rollback-safe hooks/audit/versioning');
  stdout.writeln(' - managed applications: portable wmn-procedure-v1 lifecycle/API logic; no per-app Flutter rebuild required');
  stdout.writeln(' - transaction workspace: generic metadata-driven cart/session/scanner/payment/return page capability; application resources and fields remain package-owned');
  stdout.writeln(' - application extension points: generic barcode/pricing resolvers + safe managed-procedure map/string/number primitives; no POS-extension business terms in System Core');
  stdout.writeln(' - Method Modules/Scripts: global managed extensions, execution gated');
  stdout.writeln(' - Dashboard Charts: native local aggregation enabled');
  stdout.writeln(' - platform adapters: executable open/share/clipboard/connectivity/device-info + mobile camera/scanner + native file export; explicit unsupported boundaries preserved');
  stdout.writeln(' - field controls: normalized Select options + storage-independent Render As resolver for Data/Select/Link semantics');
  stdout.writeln(' - workspaces: Workspace + Workspace Item child-table builder; no JSON/code authoring required');
  stdout.writeln(' - data exchange: Data Import/Export remains a Tool + engine with read-only Job history DocTypes');
  stdout.writeln(' - runtime laboratory: STANDARD/DASHBOARD/CUSTOM/LIST/FORM/REPORT/WORKSPACE pages are seeded for regression testing');
  stdout.writeln(' - System DocTypes: every system metadata surface declares an explicit runtime owner service');
}
