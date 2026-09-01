import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/localization/wmn_localization.dart';
import '../../../modules/customization/application/customization_service.dart';
import '../../../platform/files/wmn_file_interaction_service.dart';
import '../../meta/doctype_meta.dart';
import '../../meta/field_control_resolver.dart';
import '../../meta/meta_service.dart';
import '../../model/document_service.dart';
import '../form/wmn_form_view.dart';

class WmnListView extends StatefulWidget {
  const WmnListView({
    super.key,
    required this.doctype,
    required this.meta,
    required this.documents,
    required this.customization,
    this.onDataImport,
    this.onDataExport,
    this.onOpenReport,
    this.openFormsInDialog = false,
    this.fileInteractions,
  });

  final String doctype;
  final WmnMetaService meta;
  final WmnDocumentService documents;
  final CustomizationService customization;
  final VoidCallback? onDataImport;
  final VoidCallback? onDataExport;
  final WmnOpenReportCallback? onOpenReport;
  final bool openFormsInDialog;
  final WmnFileInteractionService? fileInteractions;

  static Future<void> showManageDialog(
    BuildContext context, {
    required String doctype,
    required WmnMetaService meta,
    required WmnDocumentService documents,
    required CustomizationService customization,
    VoidCallback? onDataImport,
    VoidCallback? onDataExport,
    WmnFileInteractionService? fileInteractions,
  }) async {
    final size = MediaQuery.sizeOf(context);
    final horizontalInset = size.width < 700 ? 8.0 : 28.0;
    final verticalInset = size.height < 700 ? 8.0 : 24.0;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: horizontalInset,
          vertical: verticalInset,
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: math.min(1180.0, size.width - (horizontalInset * 2)),
          height: math.min(860.0, size.height - (verticalInset * 2)),
          child: Column(
            children: [
              Material(
                color: Theme.of(dialogContext).colorScheme.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 8, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.table_rows_outlined, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${dialogContext.wmnT('manage_records')} • $doctype',
                          style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      IconButton(
                        tooltip: dialogContext.wmnT('close'),
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: WmnListView(
                  doctype: doctype,
                  meta: meta,
                  documents: documents,
                  customization: customization,
                  onDataImport: onDataImport,
                  onDataExport: onDataExport,
                  openFormsInDialog: true,
                  fileInteractions: fileInteractions,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  State<WmnListView> createState() => _WmnListViewState();
}

class _WmnListViewState extends State<WmnListView> {
  final _search = TextEditingController();
  WmnDocTypeMeta? _meta;
  WmnListViewSettings? _settings;
  WmnDocumentPage? _page;
  List<List<Object?>> _filters = [];
  String? _sortField;
  bool _descending = true;
  int _offset = 0;
  bool _loading = true;
  String? _error;

  bool _hasPermission(String action) {
    final runtime = widget.customization.scriptEngine.frappeRuntime;
    if (runtime == null) {
      final dt = _meta;
      if (dt == null) return false;
      return switch (action) {
        'create' => dt.allowCreate,
        'write' => dt.allowEdit,
        'delete' => dt.allowDelete,
        _ => true,
      };
    }
    return runtime.permissions.hasPermission(widget.doctype, action);
  }

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant WmnListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.doctype != widget.doctype) {
      _search.clear();
      _filters = [];
      _offset = 0;
      _initialize();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _initialize() {
    final dt = widget.meta.doctype(widget.doctype);
    final settings = widget.meta.listViewSettings(widget.doctype);
    _meta = dt;
    _settings = settings;
    _filters = settings.defaultFilters.map((entry) => List<Object?>.from(entry)).toList(growable: true);
    _sortField = settings.sortField;
    _descending = settings.sortDescending;
    _load();
  }

  void _load() {
    final dt = _meta;
    final settings = _settings;
    if (dt == null || settings == null) {
      setState(() {
        _loading = false;
        _error = 'Unknown DocType: ${widget.doctype}';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fields = settings.fields.isEmpty ? dt.listFields.map((field) => field.fieldName).toList() : settings.fields;
      final page = widget.documents.list(
        widget.doctype,
        filters: _filters,
        search: _search.text,
        fields: fields,
        searchFields: settings.searchFields,
        sortField: _sortField,
        descending: _descending,
        limit: settings.pageSize,
        offset: _offset,
      );
      setState(() {
        _page = page;
        _loading = false;
      });
    } catch (error) {
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _manageLinkRecords(String doctype) async {
    final runtime = widget.customization.scriptEngine.frappeRuntime;
    final allowed = runtime?.permissions.hasPermission(doctype, 'read') ??
        widget.meta.doctype(doctype, includeFields: false) != null;
    if (!allowed || !mounted) return;
    await WmnListView.showManageDialog(
      context,
      doctype: doctype,
      meta: widget.meta,
      documents: widget.documents,
      customization: widget.customization,
      onDataImport: widget.onDataImport,
      onDataExport: widget.onDataExport,
      fileInteractions: widget.fileInteractions,
    );
  }

  Future<void> _openForm([String? name]) async {
    final bool? changed;
    if (widget.openFormsInDialog) {
      changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => WmnFormView(
          doctype: widget.doctype,
          documentName: name,
          meta: widget.meta,
          documents: widget.documents,
          customization: widget.customization,
          presentation: WmnFormPresentation.dialog,
          onManageLinkRecords: _manageLinkRecords,
          onOpenReport: widget.onOpenReport,
          fileInteractions: widget.fileInteractions,
        ),
      );
    } else {
      changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => WmnFormView(
            doctype: widget.doctype,
            documentName: name,
            meta: widget.meta,
            documents: widget.documents,
            customization: widget.customization,
            onManageLinkRecords: _manageLinkRecords,
            onOpenReport: widget.onOpenReport,
            fileInteractions: widget.fileInteractions,
          ),
        ),
      );
    }
    if (changed == true) _load();
  }

  Future<void> _delete(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.wmnT('delete')),
        content: Text('${context.wmnT('delete_record_confirm')}\n$name'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.wmnT('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.wmnT('delete'))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final runtime = widget.customization.scriptEngine.frappeRuntime;
      if (runtime != null) {
        runtime.documents.deleteDoc(widget.doctype, name);
      } else {
        widget.documents.delete(widget.doctype, name);
      }
      _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _editListSettings() async {
    final dt = _meta;
    final settings = _settings;
    if (dt == null || settings == null) return;
    final result = await showDialog<WmnListViewSettings>(
      context: context,
      builder: (_) => _ListSettingsDialog(meta: dt, initial: settings),
    );
    if (result == null) return;
    try {
      widget.meta.saveListViewSettings(widget.doctype, result);
      if (!mounted) return;
      setState(() {
        _settings = result;
        _sortField = result.sortField;
        _descending = result.sortDescending;
        _offset = 0;
      });
      _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _addFilter() async {
    final dt = _meta!;
    final result = await showDialog<List<Object?>>(
      context: context,
      builder: (_) => _FilterDialog(fields: dt.fields.where((field) => !field.hidden && !field.isLayout).toList(growable: false)),
    );
    if (result == null) return;
    setState(() {
      _filters.add(result);
      _offset = 0;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final dt = _meta;
    if (dt == null) return Center(child: Text(_error ?? widget.doctype));
    final page = _page;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(widget.doctype, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  Chip(label: Text(dt.module)),
                  if (!dt.isSingle && dt.genericWrite && _hasPermission('create'))
                    FilledButton.icon(onPressed: () => _openForm(), icon: const Icon(Icons.add), label: Text(context.wmnT('new_record'))),
                  OutlinedButton.icon(onPressed: _addFilter, icon: const Icon(Icons.filter_alt_outlined), label: Text(context.wmnT('filter'))),
                  if (dt.allowImport && widget.onDataImport != null)
                    OutlinedButton.icon(onPressed: widget.onDataImport, icon: const Icon(Icons.upload_file_outlined), label: Text(context.wmnT('data_import'))),
                  if (dt.allowExport && widget.onDataExport != null)
                    OutlinedButton.icon(onPressed: widget.onDataExport, icon: const Icon(Icons.download_outlined), label: Text(context.wmnT('data_export'))),
                  IconButton(onPressed: _editListSettings, tooltip: context.wmnT('list_settings'), icon: const Icon(Icons.view_column_outlined)),
                  IconButton(onPressed: _load, tooltip: context.wmnT('refresh'), icon: const Icon(Icons.refresh)),
                ],
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      width: constraints.maxWidth >= 600 ? 360 : constraints.maxWidth,
                      child: SearchBar(
                        controller: _search,
                        hintText: context.wmnT('search'),
                        leading: const Icon(Icons.search),
                        trailing: [
                          if (_search.text.isNotEmpty)
                            IconButton(onPressed: () { _search.clear(); _offset = 0; _load(); }, icon: const Icon(Icons.clear)),
                        ],
                        onSubmitted: (_) { _offset = 0; _load(); },
                      ),
                    ),
                    Builder(builder: (context) {
                      final sortFields = dt.fields
                          .where((field) => !field.hidden && !field.isLayout && !const {'Table', 'Table MultiSelect'}.contains(field.fieldType))
                          .toList(growable: false);
                      final sortValues = sortFields.map((field) => field.fieldName).toSet();
                      return SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<String>(
                          initialValue: _sortField != null && sortValues.contains(_sortField) ? _sortField : null,
                          decoration: InputDecoration(labelText: context.wmnT('sort_by')),
                          items: sortFields
                              .map((field) => DropdownMenuItem(value: field.fieldName, child: Text(field.label)))
                              .toList(growable: false),
                          onChanged: (value) { setState(() { _sortField = value; _offset = 0; }); _load(); },
                        ),
                      );
                    }),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, icon: Icon(Icons.arrow_upward)),
                        ButtonSegment(value: true, icon: Icon(Icons.arrow_downward)),
                      ],
                      selected: {_descending},
                      onSelectionChanged: (value) { setState(() => _descending = value.first); _load(); },
                    ),
                  ],
                ),
              ),
              if (_filters.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < _filters.length; i++)
                      InputChip(
                        label: Text('${_filters[i][0]} ${_filters[i][1]} ${_filters[i][2] ?? ''}'),
                        onDeleted: () { setState(() { _filters.removeAt(i); _offset = 0; }); _load(); },
                      ),
                    TextButton(onPressed: () { setState(() { _filters.clear(); _offset = 0; }); _load(); }, child: Text(context.wmnT('clear_filters'))),
                  ],
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        if (_error != null)
          MaterialBanner(content: Text(_error!), actions: [TextButton(onPressed: () => setState(() => _error = null), child: Text(context.wmnT('close')))]),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : page == null || page.rows.isEmpty
                  ? Center(child: Text(context.wmnT('no_data')))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final canDelete = !dt.isSingle && dt.genericWrite && _hasPermission('delete');
                        final useCards = _settings!.layout == 'CARDS' || constraints.maxWidth < 760;
                        return useCards
                            ? _MobileCards(meta: dt, rows: page.rows, settings: _settings!, onOpen: _openForm, onDelete: canDelete ? _delete : null)
                            : _DesktopTable(meta: dt, rows: page.rows, settings: _settings!, onOpen: _openForm, onDelete: canDelete ? _delete : null);
                      },
                    ),
        ),
        if (page != null)
          _Pager(
            total: page.total,
            offset: page.offset,
            limit: page.limit,
            onPrevious: page.offset <= 0 ? null : () { setState(() => _offset = (_offset - page.limit).clamp(0, page.total).toInt()); _load(); },
            onNext: page.offset + page.rows.length >= page.total ? null : () { setState(() => _offset += page.limit); _load(); },
          ),
      ],
    );
  }
}

class _DesktopTable extends StatelessWidget {
  const _DesktopTable({required this.meta, required this.rows, required this.settings, required this.onOpen, this.onDelete});
  final WmnDocTypeMeta meta;
  final List<Map<String, Object?>> rows;
  final WmnListViewSettings settings;
  final ValueChanged<String> onOpen;
  final ValueChanged<String>? onDelete;

  @override
  Widget build(BuildContext context) {
    final names = settings.fields.isEmpty ? meta.listFields.map((field) => field.fieldName).toList() : settings.fields;
    final fields = names.map(meta.field).whereType<WmnFieldMeta>().toList(growable: false);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: [
            if (!settings.hideNameColumn) DataColumn(label: Text(context.wmnT('id'))),
            ...fields.map((field) => DataColumn(label: Text(field.label))),
            const DataColumn(label: SizedBox.shrink()),
          ],
          rows: rows.map((row) {
            final name = '${row[meta.idField] ?? row['name'] ?? ''}';
            return DataRow(
              onSelectChanged: (_) => onOpen(name),
              cells: [
                if (!settings.hideNameColumn) DataCell(SelectableText(name)),
                ...fields.map((field) => DataCell(Text('${row[field.fieldName] ?? ''}'))),
                DataCell(PopupMenuButton<String>(
                  onSelected: (action) { if (action == 'open') onOpen(name); if (action == 'delete') onDelete?.call(name); },
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'open', child: Text(context.wmnT('open'))),
                    if (onDelete != null) PopupMenuItem(value: 'delete', child: Text(context.wmnT('delete'))),
                  ],
                )),
              ],
            );
          }).toList(growable: false),
        ),
      ),
    );
  }
}

class _MobileCards extends StatelessWidget {
  const _MobileCards({required this.meta, required this.rows, required this.settings, required this.onOpen, this.onDelete});
  final WmnDocTypeMeta meta;
  final List<Map<String, Object?>> rows;
  final WmnListViewSettings settings;
  final ValueChanged<String> onOpen;
  final ValueChanged<String>? onDelete;

  @override
  Widget build(BuildContext context) {
    final names = settings.fields.isEmpty ? meta.listFields.map((field) => field.fieldName).toList() : settings.fields;
    final fields = names.map(meta.field).whereType<WmnFieldMeta>().toList(growable: false);
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = rows[index];
        final name = '${row[meta.idField] ?? row['name'] ?? ''}';
        final titleField = meta.titleField == null ? null : row[meta.titleField];
        return Card(
          child: ListTile(
            title: Text('${titleField ?? name}', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(fields.take(4).map((field) => '${field.label}: ${row[field.fieldName] ?? '-'}').join('\n')),
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (action) { if (action == 'open') onOpen(name); if (action == 'delete') onDelete?.call(name); },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'open', child: Text(context.wmnT('open'))),
                if (onDelete != null) PopupMenuItem(value: 'delete', child: Text(context.wmnT('delete'))),
              ],
            ),
            onTap: () => onOpen(name),
          ),
        );
      },
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({required this.total, required this.offset, required this.limit, this.onPrevious, this.onNext});
  final int total;
  final int offset;
  final int limit;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final start = total == 0 ? 0 : offset + 1;
    final end = (offset + limit).clamp(0, total).toInt();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text('$start–$end / $total'),
            const SizedBox(width: 8),
            IconButton(onPressed: onPrevious, icon: const Icon(Icons.chevron_left)),
            IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
          ],
        ),
      ),
    );
  }
}

class _FilterDialog extends StatefulWidget {
  const _FilterDialog({required this.fields});
  final List<WmnFieldMeta> fields;

  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  late WmnFieldMeta _field;
  String _operator = '=';

  @override
  void initState() {
    super.initState();
    _field = widget.fields.first;
  }
  final _value = TextEditingController();

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(context.wmnT('add_filter')),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<WmnFieldMeta>(
                initialValue: _field,
                decoration: InputDecoration(labelText: context.wmnT('field')),
                items: widget.fields.map((field) => DropdownMenuItem(value: field, child: Text(field.label))).toList(growable: false),
                onChanged: (value) { if (value != null) setState(() => _field = value); },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _operator,
                decoration: InputDecoration(labelText: context.wmnT('operator')),
                items: const ['=', '!=', '>', '>=', '<', '<=', 'LIKE'].map((op) => DropdownMenuItem(value: op, child: Text(op))).toList(),
                onChanged: (value) { if (value != null) setState(() => _operator = value); },
              ),
              const SizedBox(height: 10),
              Builder(builder: (context) {
                final control = WmnFieldControlResolver.resolve(_field);
                if (control.type == WmnFieldControlType.select && control.options.isNotEmpty) {
                  final current = control.options.contains(_value.text) ? _value.text : null;
                  return DropdownButtonFormField<String>(
                    key: ValueKey('filter:${_field.fieldName}'),
                    initialValue: current,
                    decoration: InputDecoration(labelText: context.wmnT('value')),
                    items: control.options
                        .map((entry) => DropdownMenuItem(value: entry, child: Text(entry)))
                        .toList(growable: false),
                    onChanged: (value) => _value.text = value ?? '',
                  );
                }
                return TextField(controller: _value, decoration: InputDecoration(labelText: context.wmnT('value')));
              }),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(context.wmnT('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, <Object?>[_field.fieldName, _operator, _operator == 'LIKE' ? '%${_value.text}%' : _value.text]), child: Text(context.wmnT('add'))),
        ],
      );
}

class _ListSettingsDialog extends StatefulWidget {
  const _ListSettingsDialog({required this.meta, required this.initial});

  final WmnDocTypeMeta meta;
  final WmnListViewSettings initial;

  @override
  State<_ListSettingsDialog> createState() => _ListSettingsDialogState();
}

class _ListSettingsDialogState extends State<_ListSettingsDialog> {
  late final Set<String> _fields;
  late final Set<String> _searchFields;
  late String? _sortField;
  late bool _sortDescending;
  late int _pageSize;
  late bool _hideNameColumn;
  late String _layout;

  List<WmnFieldMeta> get _availableFields => widget.meta.fields
      .where((field) => !field.hidden && !field.isLayout && !const {'Table', 'Table MultiSelect'}.contains(field.fieldType))
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _fields = widget.initial.fields.toSet();
    _searchFields = widget.initial.searchFields.toSet();
    _sortField = widget.initial.sortField;
    _sortDescending = widget.initial.sortDescending;
    _pageSize = widget.initial.pageSize;
    _hideNameColumn = widget.initial.hideNameColumn;
    _layout = widget.initial.layout == 'CARDS' ? 'CARDS' : 'TABLE';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(context.wmnT('list_settings')),
        content: SizedBox(
          width: 680,
          height: 620,
          child: ListView(
            children: [
              Text(context.wmnT('visible_columns'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _availableFields
                    .map((field) => FilterChip(
                          label: Text(field.label),
                          selected: _fields.contains(field.fieldName),
                          onSelected: (value) => setState(() {
                            if (value) {
                              _fields.add(field.fieldName);
                            } else {
                              _fields.remove(field.fieldName);
                            }
                          }),
                        ))
                    .toList(growable: false),
              ),
              const SizedBox(height: 18),
              Text(context.wmnT('search_fields'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _availableFields
                    .where((field) => !field.isBoolean)
                    .map((field) => FilterChip(
                          label: Text(field.label),
                          selected: _searchFields.contains(field.fieldName),
                          onSelected: (value) => setState(() {
                            if (value) {
                              _searchFields.add(field.fieldName);
                            } else {
                              _searchFields.remove(field.fieldName);
                            }
                          }),
                        ))
                    .toList(growable: false),
              ),
              const SizedBox(height: 18),
              Builder(builder: (context) {
                final availableFields = _availableFields;
                final values = availableFields.map((field) => field.fieldName).toSet();
                return DropdownButtonFormField<String>(
                  initialValue: _sortField != null && values.contains(_sortField) ? _sortField : null,
                  decoration: InputDecoration(labelText: context.wmnT('sort_by')),
                  items: availableFields
                      .map((field) => DropdownMenuItem(value: field.fieldName, child: Text(field.label)))
                      .toList(growable: false),
                  onChanged: (value) => setState(() => _sortField = value),
                );
              }),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.wmnT('sort_descending')),
                value: _sortDescending,
                onChanged: (value) => setState(() => _sortDescending = value),
              ),
              DropdownButtonFormField<int>(
                initialValue: const {10, 20, 50, 100, 200}.contains(_pageSize) ? _pageSize : 20,
                decoration: InputDecoration(labelText: context.wmnT('page_size')),
                items: const [10, 20, 50, 100, 200]
                    .map((value) => DropdownMenuItem(value: value, child: Text('$value')))
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) setState(() => _pageSize = value);
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _layout,
                decoration: InputDecoration(labelText: context.wmnT('list_layout')),
                items: [
                  DropdownMenuItem(value: 'TABLE', child: Text(context.wmnT('table_layout'))),
                  DropdownMenuItem(value: 'CARDS', child: Text(context.wmnT('cards_layout'))),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _layout = value);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.wmnT('hide_name_column')),
                value: _hideNameColumn,
                onChanged: (value) => setState(() => _hideNameColumn = value),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(context.wmnT('cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              WmnListViewSettings(
                fields: _fields.toList(growable: false),
                searchFields: _searchFields.toList(growable: false),
                defaultFilters: widget.initial.defaultFilters,
                sortField: _sortField,
                sortDescending: _sortDescending,
                pageSize: _pageSize,
                hideNameColumn: _hideNameColumn,
                layout: _layout,
              ),
            ),
            child: Text(context.wmnT('save')),
          ),
        ],
      );
}
