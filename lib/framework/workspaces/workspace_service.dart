import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/database/wmn_database.dart';
import '../../core/database/sql_identifier.dart';
import '../meta/meta_service.dart';
import 'workspace_models.dart';

class WmnWorkspaceService {
  WmnWorkspaceService({required this.database, required this.meta});

  final WmnDatabase database;
  final WmnMetaService meta;
  static const Uuid _uuid = Uuid();
  static const bool dashboardChartsEnabled = true;
  static const String platformWorkspaceSeedVersion = '3.14.0';

  void ensurePlatformWorkspaces() {
    if (_platformWorkspaceSeedCurrent()) return;
    // System-owned workspaces are regenerated from the clean platform source.
    // Application/custom workspaces are never touched here.
    database.db.execute(
      "DELETE FROM [tabWorkspace] WHERE app_name IS NULL AND "
      "name IN ('WMN Platform','Developer Studio','System','Administration','Developer');",
    );

    _ensurePlatformWorkspace(
      name: 'System',
      label: 'System',
      sequenceId: -300.0,
      content: const [
        {
          'type': 'shortcut',
          'data': {'label': 'Module', 'link_type': 'DocType', 'link_to': 'Module', 'col': 4},
        },
        {
          'type': 'shortcut',
          'data': {'label': 'Page', 'link_type': 'DocType', 'link_to': 'Page', 'col': 4},
        },
        {
          'type': 'shortcut',
          'data': {'label': 'Workspace', 'link_type': 'DocType', 'link_to': 'Workspace', 'col': 4},
        },
        {
          'type': 'shortcut',
          'data': {'label': 'Report', 'link_type': 'DocType', 'link_to': 'Report', 'col': 4},
        },
        {
          'type': 'shortcut',
          'data': {
            'label': 'Workflow',
            'link_type': 'DocType',
            'link_to': 'Workflow',
            'required_feature': 'workflow.approvals',
            'col': 4,
          },
        },
        {
          'type': 'shortcut',
          'data': {
            'label': 'Workflow State',
            'link_type': 'DocType',
            'link_to': 'Workflow State',
            'required_feature': 'workflow.approvals',
            'col': 4,
          },
        },
        {
          'type': 'shortcut',
          'data': {
            'label': 'Workflow Transition',
            'link_type': 'DocType',
            'link_to': 'Workflow Transition',
            'required_feature': 'workflow.approvals',
            'col': 4,
          },
        },
        {
          'type': 'shortcut',
          'data': {
            'label': 'Workflow Action',
            'link_type': 'DocType',
            'link_to': 'Workflow Action',
            'required_feature': 'workflow.approvals',
            'col': 4,
          },
        },
        {
          'type': 'shortcut',
          'data': {
            'label': 'Print Format',
            'link_type': 'DocType',
            'link_to': 'Print Format',
            'required_feature': 'printing',
            'col': 4,
          },
        },
        {
          'type': 'shortcut',
          'data': {
            'label': 'Print Settings',
            'link_type': 'DocType',
            'link_to': 'Print Settings',
            'required_feature': 'printing',
            'col': 4,
          },
        },
        {
          'type': 'shortcut',
          'data': {
            'label': 'Printer',
            'link_type': 'DocType',
            'link_to': 'Printer',
            'required_feature': 'printing',
            'col': 4,
          },
        },
        {
          'type': 'shortcut',
          'data': {'label': 'File', 'link_type': 'DocType', 'link_to': 'File', 'col': 4},
        },
        {
          'type': 'shortcut',
          'data': {
            'label': 'Notification',
            'link_type': 'DocType',
            'link_to': 'Notification',
            'required_feature': 'system.notifications',
            'col': 4,
          },
        },
        {
          'type': 'shortcut',
          'data': {
            'label': 'Scheduled Job',
            'link_type': 'DocType',
            'link_to': 'Scheduled Job',
            'required_feature': 'system.scheduler',
            'col': 4,
          },
        },
        {
          'type': 'shortcut',
          'data': {
            'label': 'Background Job',
            'link_type': 'DocType',
            'link_to': 'Background Job',
            'required_feature': 'system.scheduler',
            'col': 4,
          },
        },
        {
          'type': 'shortcut',
          'data': {'label': 'System Setting', 'link_type': 'DocType', 'link_to': 'System Setting', 'col': 4},
        },
        {
          'type': 'shortcut',
          'data': {'label': 'System Log', 'link_type': 'DocType', 'link_to': 'System Log', 'col': 4},
        },
      ],
      metadata: const {
        'source_framework': 'WMN',
        'system_workspace': true,
        'workspace_role': 'SYSTEM',
        'required_roles': ['System Manager'],
      },
    );

    _ensurePlatformWorkspace(
      name: 'Administration',
      label: 'Administration',
      sequenceId: -200.0,
      content: const [
        {
          'type': 'shortcut',
          'data': {'label': 'User', 'link_type': 'DocType', 'link_to': 'User', 'col': 4},
        },
        {
          'type': 'shortcut',
          'data': {'label': 'Role', 'link_type': 'DocType', 'link_to': 'Role', 'col': 4},
        },
        {
          'type': 'shortcut',
          'data': {'label': 'Permission', 'link_type': 'DocType', 'link_to': 'Permission', 'col': 4},
        },
        {
          'type': 'shortcut',
          'data': {'label': 'User Role', 'link_type': 'DocType', 'link_to': 'User Role', 'col': 4},
        },
        {
          'type': 'shortcut',
          'data': {'label': 'Role Permission', 'link_type': 'DocType', 'link_to': 'Role Permission', 'col': 4},
        },
        {
          'type': 'shortcut',
          'data': {'label': 'DocType Permission', 'link_type': 'DocType', 'link_to': 'DocType Permission', 'col': 4},
        },
        {
          'type': 'shortcut',
          'data': {'label': 'User Permission', 'link_type': 'DocType', 'link_to': 'User Permission', 'col': 4},
        },
        {
          'type': 'shortcut',
          'data': {'label': 'Document Share', 'link_type': 'DocType', 'link_to': 'Document Share', 'col': 4},
        },
        {
          'type': 'shortcut',
          'data': {'label': 'Application', 'link_type': 'DocType', 'link_to': 'Application', 'col': 4},
        },
        {
          'type': 'shortcut',
          'data': {'label': 'Feature', 'link_type': 'DocType', 'link_to': 'Feature', 'col': 4},
        },
        {
          'type': 'shortcut',
          'data': {'label': 'Feature Entitlement', 'link_type': 'DocType', 'link_to': 'Feature Entitlement', 'col': 4},
        },
        {
          'type': 'shortcut',
          'data': {'label': 'Feature Activation', 'link_type': 'DocType', 'link_to': 'Feature Activation', 'col': 4},
        },
        {
          'type': 'shortcut',
          'data': {'label': 'Audit Log', 'link_type': 'DocType', 'link_to': 'Audit Log', 'col': 4},
        },
      ],
      metadata: const {
        'source_framework': 'WMN',
        'system_workspace': true,
        'workspace_role': 'ADMINISTRATION',
        'required_roles': ['System Manager'],
      },
    );

    _ensurePlatformWorkspace(
      name: 'Developer',
      label: 'Developer',
      sequenceId: -100.0,
      content: const [
        {
          'type': 'shortcut',
          'data': {'label': 'Page', 'link_type': 'DocType', 'link_to': 'Page', 'col': 4},
        },
        {
          'type': 'shortcut',
          'data': {'label': 'Workspace', 'link_type': 'DocType', 'link_to': 'Workspace', 'col': 4},
        },
        {
          'type': 'shortcut',
          'data': {'label': 'Report', 'link_type': 'DocType', 'link_to': 'Report', 'col': 4},
        },
        {
          'type': 'card',
          'data': {
            'label': 'Advanced developer tools',
            'description': 'Open Current UI from the shell button for DocType Studio, app conversion and runtime diagnostics during the transition.',
            'col': 12,
          },
        },
      ],
      metadata: const {
        'source_framework': 'WMN',
        'system_workspace': true,
        'workspace_role': 'DEVELOPER',
        'required_roles': ['System Manager'],
        'required_feature': 'developer.tools',
      },
    );
  }

  bool _platformWorkspaceSeedCurrent() {
    final rows = database.db.select(
      "SELECT name,metadata_json FROM [tabWorkspace] WHERE app_name IS NULL "
      "AND name IN ('System','Administration','Developer');",
    );
    if (rows.length != 3) return false;
    for (final row in rows) {
      final metadata = _decodeMap(row['metadata_json'] as String?);
      if (metadata['seed_version'] != platformWorkspaceSeedVersion) {
        return false;
      }
    }
    return true;
  }

  void _ensurePlatformWorkspace({
    required String name,
    required String label,
    required double sequenceId,
    required List<Map<String, Object?>> content,
    Map<String, Object?> metadata = const {},
  }) {
    saveWorkspace(
      name: name,
      label: label,
      module: 'WMN System',
      sequenceId: sequenceId,
      content: content,
      metadata: <String, Object?>{
        'source_framework': 'WMN',
        'system_workspace': true,
        'seed_version': platformWorkspaceSeedVersion,
        ...metadata,
      },
    );
    database.db.execute("DELETE FROM [tabWorkspaceItem] WHERE parent=? AND parenttype='Workspace' AND parentfield='items';", [name]);
    var index = 0;
    for (final entry in content) {
      final type = '${entry['type'] ?? 'card'}';
      final data = wmnMap(entry['data']);
      _saveItem(
        workspaceName: name,
        region: 'CONTENT',
        itemType: type,
        label: _nullable('${data['text'] ?? data['label'] ?? ''}'),
        linkType: _nullable('${data['link_type'] ?? ''}'),
        linkTo: _nullable('${data['link_to'] ?? ''}'),
        icon: _nullable('${data['icon'] ?? ''}'),
        index: index++,
        columnSpan: (data['col'] as num?)?.toInt() ?? 4,
        data: data,
      );
    }
  }


  List<WmnWorkspace> workspaces({bool includeHidden = false}) {
    final rows = database.db.select('''
      SELECT * FROM [tabWorkspace]
      ${includeHidden ? '' : 'WHERE is_hidden = 0'}
      ORDER BY sequence_id, label COLLATE NOCASE;
    ''');
    return rows.map(_workspace).toList(growable: false);
  }

  WmnWorkspaceBundle? bundle(String name) {
    final rows = database.db.select('SELECT * FROM [tabWorkspace] WHERE name = ? LIMIT 1;', [name]);
    if (rows.isEmpty) return null;
    final itemRows = database.db.select('''
      SELECT * FROM [tabWorkspaceItem]
      WHERE parent = ? AND parenttype='Workspace' AND parentfield='items'
      ORDER BY region, idx, name;
    ''', [name]);
    return WmnWorkspaceBundle(
      workspace: _workspace(rows.first),
      items: itemRows.map(_item).toList(growable: false),
    );
  }

  WmnWorkspace saveWorkspace({
    required String name,
    required String label,
    String module = 'Custom',
    String? appName,
    String? icon,
    String? parentPage,
    double sequenceId = 0,
    bool isPublic = true,
    bool isHidden = false,
    List<Map<String, Object?>> content = const [],
    Map<String, Object?> metadata = const {},
  }) {
    final normalized = name.trim();
    if (normalized.isEmpty) throw StateError('Workspace name is required.');
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO [tabWorkspace](
        name,label,module,app_name,icon,parent_page,sequence_id,is_public,is_hidden,
        content_json,metadata_json,created_at,updated_at
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(name) DO UPDATE SET
        label=excluded.label,module=excluded.module,app_name=excluded.app_name,icon=excluded.icon,
        parent_page=excluded.parent_page,sequence_id=excluded.sequence_id,is_public=excluded.is_public,
        is_hidden=excluded.is_hidden,content_json=excluded.content_json,metadata_json=excluded.metadata_json,
        updated_at=excluded.updated_at;
    ''', [
      normalized,
      label.trim().isEmpty ? normalized : label.trim(),
      module.trim().isEmpty ? 'Custom' : module.trim(),
      _nullable(appName),
      _nullable(icon),
      _nullable(parentPage),
      sequenceId,
      isPublic ? 1 : 0,
      isHidden ? 1 : 0,
      jsonEncode(content),
      jsonEncode(metadata),
      now,
      now,
    ]);
    return bundle(normalized)!.workspace;
  }

  WmnWorkspace importFrappeWorkspace(
    Map<String, Object?> raw, {
    required String sourceApp,
    String? sourcePath,
  }) {
    final name = '${raw['name'] ?? raw['label'] ?? ''}'.trim();
    if (name.isEmpty) throw StateError('Frappe Workspace has no name.');
    final label = '${raw['label'] ?? name}';
    final module = '${raw['module'] ?? 'Custom'}';
    final content = _decodeContent(raw['content']);
    final workspace = saveWorkspace(
      name: name,
      label: label,
      module: module,
      appName: sourceApp,
      icon: _nullable('${raw['icon'] ?? ''}'),
      parentPage: _nullable('${raw['parent_page'] ?? ''}'),
      sequenceId: (raw['sequence_id'] as num?)?.toDouble() ?? (raw['idx'] as num?)?.toDouble() ?? 0,
      isPublic: !_false(raw['public']),
      isHidden: _truthy(raw['is_hidden']),
      content: content,
      metadata: {
        'source_framework': 'FRAPPE',
        'source_path': sourcePath,
        'raw': raw,
      },
    );

    database.db.execute("DELETE FROM [tabWorkspaceItem] WHERE parent=? AND parenttype='Workspace' AND parentfield='items';", [name]);
    var index = 0;
    for (final entry in content) {
      final type = '${entry['type'] ?? 'item'}';
      final data = wmnMap(entry['data']);
      _saveItem(
        workspaceName: name,
        region: 'CONTENT',
        itemType: type,
        label: _plainLabel('${data['text'] ?? data['label'] ?? data['card_name'] ?? data['chart_name'] ?? data['number_card_name'] ?? ''}'),
        linkType: _nullable('${data['link_type'] ?? ''}'),
        linkTo: _nullable('${data['link_to'] ?? data['card_name'] ?? data['chart_name'] ?? data['number_card_name'] ?? ''}'),
        index: index++,
        columnSpan: (data['col'] as num?)?.toInt() ?? 4,
        data: entry,
      );
    }
    _importList(name, 'LINKS', raw['links']);
    _importList(name, 'SHORTCUTS', raw['shortcuts']);
    _importList(name, 'SIDEBAR', raw['sidebar_items']);
    _importList(name, 'CHARTS', raw['charts']);
    _importList(name, 'NUMBER_CARDS', raw['number_cards']);
    _importList(name, 'QUICK_LISTS', raw['quick_lists']);
    return workspace;
  }

  WmnWorkspace importFrappeSidebar(
    Map<String, Object?> raw, {
    required String sourceApp,
    required String workspaceName,
    String? sourcePath,
  }) {
    final existing = bundle(workspaceName)?.workspace;
    final workspace = existing ?? saveWorkspace(
      name: workspaceName,
      label: '${raw['label'] ?? workspaceName}',
      module: '${raw['module'] ?? workspaceName}',
      appName: sourceApp,
      icon: _nullable('${raw['header_icon'] ?? raw['icon'] ?? ''}'),
      metadata: {'source_framework': 'FRAPPE', 'source_path': sourcePath, 'sidebar_only': true},
    );
    database.db.execute("DELETE FROM [tabWorkspaceItem] WHERE parent=? AND parenttype='Workspace' AND parentfield='items' AND region='SIDEBAR';", [workspaceName]);
    _importList(workspaceName, 'SIDEBAR', raw['items']);
    return workspace;
  }

  void saveNumberCard(Map<String, Object?> raw, {required String sourceApp}) {
    final name = '${raw['name'] ?? raw['label'] ?? raw['number_card_name'] ?? ''}'.trim();
    if (name.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO wmn_number_cards(name,label,module,app_name,document_type,function,aggregate_field,report_name,filters_json,metadata_json,updated_at)
      VALUES (?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(name) DO UPDATE SET
        label=excluded.label,module=excluded.module,app_name=excluded.app_name,document_type=excluded.document_type,
        function=excluded.function,aggregate_field=excluded.aggregate_field,report_name=excluded.report_name,
        filters_json=excluded.filters_json,metadata_json=excluded.metadata_json,updated_at=excluded.updated_at;
    ''', [
      name,
      '${raw['label'] ?? name}',
      '${raw['module'] ?? 'Custom'}',
      sourceApp,
      _nullable('${raw['document_type'] ?? ''}'),
      _nullable('${raw['function'] ?? raw['type'] ?? ''}'),
      _nullable('${raw['aggregate_function_based_on'] ?? raw['aggregate_field'] ?? ''}'),
      _nullable('${raw['report_name'] ?? ''}'),
      _jsonText(raw['filters_json'] ?? raw['filters']),
      jsonEncode(raw),
      now,
    ]);
  }

  void saveDashboardChart(Map<String, Object?> raw, {String? sourceApp}) {
    final name = '${raw['name'] ?? raw['chart_name'] ?? raw['label'] ?? ''}'.trim();
    if (name.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO wmn_dashboard_charts(name,label,module,app_name,chart_type,document_type,report_name,based_on,value_field,filters_json,metadata_json,updated_at)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(name) DO UPDATE SET
        label=excluded.label,module=excluded.module,app_name=excluded.app_name,chart_type=excluded.chart_type,
        document_type=excluded.document_type,report_name=excluded.report_name,based_on=excluded.based_on,
        value_field=excluded.value_field,filters_json=excluded.filters_json,metadata_json=excluded.metadata_json,
        updated_at=excluded.updated_at;
    ''', [
      name,
      '${raw['label'] ?? raw['chart_name'] ?? name}',
      '${raw['module'] ?? 'Custom'}',
      sourceApp,
      _nullable('${raw['type'] ?? raw['chart_type'] ?? ''}'),
      _nullable('${raw['document_type'] ?? ''}'),
      _nullable('${raw['report_name'] ?? ''}'),
      _nullable('${raw['based_on'] ?? ''}'),
      _nullable('${raw['value_based_on'] ?? raw['value_field'] ?? ''}'),
      _jsonText(raw['filters_json'] ?? raw['filters']),
      jsonEncode(raw),
      now,
    ]);
  }

  List<Map<String, Object?>> quickListRows(String doctype, {int limit = 5}) {
    final dt = meta.doctype(doctype);
    if (dt == null || dt.isChild) return const [];
    final fields = <String>{dt.idField};
    if (dt.titleField != null && dt.titleField!.trim().isNotEmpty) fields.add(dt.titleField!);
    fields.addAll(dt.listFields.take(3).map((entry) => entry.fieldName));
    try {
      return meta.registry.readList(
        doctype,
        fields: fields.toList(growable: false),
        limit: limit.clamp(1, 20).toInt(),
        descending: true,
      );
    } catch (_) {
      return const [];
    }
  }

  List<Map<String, Object?>> dashboardChartSeries(String name, {int limit = 8}) {
    final rows = database.db.select('SELECT * FROM wmn_dashboard_charts WHERE name = ? LIMIT 1;', [name]);
    if (rows.isEmpty) return const [];
    final row = rows.first;
    final doctype = row['document_type'] as String?;
    final basedOn = row['based_on'] as String?;
    final valueField = row['value_field'] as String?;
    if (doctype == null || doctype.trim().isEmpty || basedOn == null || basedOn.trim().isEmpty) return const [];
    final dt = meta.doctype(doctype);
    if (dt == null || dt.isChild) return const [];
    final availableFields = meta.registry.standardFields(doctype);
    if (!availableFields.contains(basedOn)) return const [];
    final fields = <String>[basedOn];
    if (valueField != null && valueField.trim().isNotEmpty) {
      if (!availableFields.contains(valueField)) return const [];
      fields.add(valueField);
    }
    final filters = _decodeFilters(row['filters_json'] as String?);
    List<Map<String, Object?>> docs;
    try {
      docs = meta.registry.readList(
        doctype,
        fields: fields,
        filters: filters.cast<Object?>(),
        limit: 200,
      );
    } catch (_) {
      return const [];
    }
    final grouped = <String, num>{};
    for (final doc in docs) {
      final label = '${doc[basedOn] ?? '—'}'.trim();
      if (label.isEmpty) continue;
      final rawValue = valueField == null || valueField.isEmpty ? 1 : doc[valueField];
      final value = rawValue is num ? rawValue : num.tryParse('${rawValue ?? ''}') ?? 0;
      grouped[label] = (grouped[label] ?? 0) + value;
    }
    final result = grouped.entries
        .map((entry) => <String, Object?>{'label': entry.key, 'value': entry.value})
        .toList(growable: false)
      ..sort((a, b) => ((b['value'] as num?) ?? 0).compareTo((a['value'] as num?) ?? 0));
    return result.take(limit.clamp(1, 20).toInt()).toList(growable: false);
  }

  Map<String, Object?>? dashboardChartMeta(String name) {
    final rows = database.db.select('SELECT * FROM wmn_dashboard_charts WHERE name = ? LIMIT 1;', [name]);
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.first);
  }

  Map<String, Object?>? numberCardMeta(String name) {
    final rows = database.db.select(
      'SELECT * FROM wmn_number_cards WHERE name = ? LIMIT 1;',
      [name],
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.first);
  }

  Object? numberCardValue(String name) {
    final rows = database.db.select('SELECT * FROM wmn_number_cards WHERE name = ? LIMIT 1;', [name]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    final doctype = row['document_type'] as String?;
    if (doctype == null || doctype.isEmpty) return null;
    final dt = meta.doctype(doctype);
    if (dt == null) return null;
    final function = '${row['function'] ?? 'Count'}'.toUpperCase();
    final filters = _decodeFilters(row['filters_json'] as String?);
    if (function.contains('COUNT')) {
      return meta.registry.count(doctype, filters: filters.cast<Object?>());
    }
    final field = row['aggregate_field'] as String?;
    if (field == null || field.isEmpty || dt.storageMode.name != 'table' || dt.tableName == null) return null;
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(field)) return null;
    final table = dt.tableName!;
    final aggregate = function.contains('AVERAGE') || function.contains('AVG') ? 'AVG' : function.contains('MIN') ? 'MIN' : function.contains('MAX') ? 'MAX' : 'SUM';
    final result = database.db.select(
      'SELECT $aggregate(${quoteSqlIdentifier(field)}) AS value FROM ${quoteSqlIdentifier(table)};',
    );
    return result.isEmpty ? null : result.first['value'];
  }

  void _importList(String workspaceName, String region, Object? rawList) {
    if (rawList is! List) return;
    String? currentCard;
    var index = 0;
    for (final value in rawList) {
      if (value is! Map) continue;
      final item = wmnMap(value);
      final type = '${item['type'] ?? item['link_type'] ?? 'Link'}';
      final label = _nullable('${item['label'] ?? item['name'] ?? item['chart_name'] ?? item['number_card_name'] ?? ''}');
      if (type == 'Card Break') currentCard = label;
      _saveItem(
        workspaceName: workspaceName,
        region: region,
        itemType: type,
        label: label,
        linkType: _nullable('${item['link_type'] ?? ''}'),
        linkTo: _nullable('${item['link_to'] ?? item['chart_name'] ?? item['number_card_name'] ?? ''}'),
        icon: _nullable('${item['icon'] ?? ''}'),
        parentLabel: currentCard,
        index: index++,
        hidden: _truthy(item['hidden']),
        data: item,
      );
    }
  }

  void _saveItem({
    required String workspaceName,
    required String region,
    required String itemType,
    String? label,
    String? linkType,
    String? linkTo,
    String? icon,
    String? parentLabel,
    required int index,
    int columnSpan = 4,
    bool hidden = false,
    Map<String, Object?> data = const {},
  }) {
    database.db.execute('''
      INSERT INTO [tabWorkspaceItem](
        name,parent,parenttype,parentfield,idx,region,item_type,label,link_type,link_to,
        icon,parent_label,column_span,hidden,required_feature,description,item_json,
        creation,modified,docstatus
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,0);
    ''', [
      _uuid.v4(), workspaceName, 'Workspace', 'items', index + 1, region, itemType, label,
      linkType, linkTo, icon, parentLabel, columnSpan.clamp(1, 12), hidden ? 1 : 0,
      _nullable('${data['required_feature'] ?? ''}'), _nullable('${data['description'] ?? ''}'),
      jsonEncode(data), DateTime.now().toUtc().toIso8601String(), DateTime.now().toUtc().toIso8601String(),
    ]);
  }

  WmnWorkspace _workspace(dynamic row) => WmnWorkspace(
        name: row['name'] as String,
        label: row['label'] as String,
        module: row['module'] as String,
        appName: row['app_name'] as String?,
        icon: row['icon'] as String?,
        parentPage: row['parent_page'] as String?,
        sequenceId: (row['sequence_id'] as num?)?.toDouble() ?? 0,
        isPublic: (row['is_public'] as int? ?? 1) == 1,
        isHidden: (row['is_hidden'] as int? ?? 0) == 1,
        content: wmnDecodeList(row['content_json'] as String?),
        metadata: _decodeMap(row['metadata_json'] as String?),
      );

  WmnWorkspaceItem _item(dynamic row) => WmnWorkspaceItem(
        id: row['name'] as String,
        workspaceName: row['parent'] as String,
        region: row['region'] as String,
        itemType: row['item_type'] as String,
        label: row['label'] as String?,
        linkType: row['link_type'] as String?,
        linkTo: row['link_to'] as String?,
        icon: row['icon'] as String?,
        parentLabel: row['parent_label'] as String?,
        index: row['idx'] as int? ?? 0,
        columnSpan: row['column_span'] as int? ?? 4,
        hidden: (row['hidden'] as int? ?? 0) == 1,
        data: _itemData(row),
      );

  Map<String, Object?> _itemData(dynamic row) {
    final data = <String, Object?>{..._decodeMap(row['item_json'] as String?)};
    final feature = '${row['required_feature'] ?? ''}'.trim();
    final description = '${row['description'] ?? ''}'.trim();
    if (feature.isNotEmpty) data['required_feature'] = feature;
    if (description.isNotEmpty) data['description'] = description;
    return data;
  }

  List<Map<String, Object?>> _decodeContent(Object? value) {
    if (value is List) return value.whereType<Map>().map(wmnMap).toList(growable: false);
    if (value is! String || value.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(value);
      if (decoded is! List) return const [];
      return decoded.whereType<Map>().map(wmnMap).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Map<String, Object?> _decodeMap(String? value) {
    if (value == null || value.trim().isEmpty) return const {};
    try {
      return wmnMap(jsonDecode(value));
    } catch (_) {
      return const {};
    }
  }

  List<List<Object?>> _decodeFilters(String? value) {
    if (value == null || value.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(value);
      if (decoded is List) {
        return decoded.whereType<List>().map((entry) => entry.cast<Object?>()).toList(growable: false);
      }
      if (decoded is Map) {
        return decoded.entries.map((entry) => <Object?>['${entry.key}', '=', entry.value]).toList(growable: false);
      }
    } catch (_) {}
    return const [];
  }

  String _jsonText(Object? value) {
    if (value is String) {
      try {
        return jsonEncode(jsonDecode(value));
      } catch (_) {
        return '[]';
      }
    }
    return jsonEncode(value ?? const []);
  }

  String _plainLabel(String value) => value
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&nbsp;', ' ')
      .trim();

  bool _truthy(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return const {'1', 'true', 'yes', 'on'}.contains('${value ?? ''}'.toLowerCase());
  }

  bool _false(Object? value) => value == false || value == 0 || '${value ?? ''}'.toLowerCase() == 'false';
  String? _nullable(String? value) => value == null || value.trim().isEmpty ? null : value.trim();
}
