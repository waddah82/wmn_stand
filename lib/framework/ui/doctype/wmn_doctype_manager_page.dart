import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/localization/wmn_localization.dart';
import '../../meta/doctype_meta.dart';
import '../../meta/meta_service.dart';
import 'wmn_doctype_studio_page.dart';

class WmnDocTypeManagerPage extends StatefulWidget {
  const WmnDocTypeManagerPage({super.key, required this.meta});

  final WmnMetaService meta;

  @override
  State<WmnDocTypeManagerPage> createState() => _WmnDocTypeManagerPageState();
}

class _WmnDocTypeManagerPageState extends State<WmnDocTypeManagerPage> {
  final _search = TextEditingController();
  String? _selectedName;
  String? _error;

  @override
  void initState() {
    super.initState();
    final rows = widget.meta.doctypes(enabledOnly: false);
    if (rows.isNotEmpty) _selectedName = rows.first.name;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<WmnDocTypeMeta> get _rows {
    final rows = widget.meta.doctypes(enabledOnly: false);
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return rows;
    return rows
        .where((entry) =>
            entry.name.toLowerCase().contains(query) ||
            entry.module.toLowerCase().contains(query) ||
            (entry.tableName?.toLowerCase().contains(query) ?? false))
        .toList(growable: false);
  }

  WmnDocTypeMeta? get _selected {
    final name = _selectedName;
    if (name == null) return null;
    return widget.meta.doctype(name);
  }

  void _reload({String? select}) {
    if (!mounted) return;
    setState(() {
      _error = null;
      if (select != null) _selectedName = select;
      if (_selectedName != null && widget.meta.doctype(_selectedName!, includeFields: false) == null) {
        final rows = widget.meta.doctypes(enabledOnly: false);
        _selectedName = rows.isEmpty ? null : rows.first.name;
      }
    });
  }

  Future<void> _createDocType() async {
    final result = await showDialog<_DocTypeDraft>(
      context: context,
      builder: (_) => _DocTypeDialog(modules: widget.meta.modules(enabledOnly: false)),
    );
    if (result == null) return;
    try {
      final saved = widget.meta.saveDocType(
        name: result.name,
        module: result.module,
        titleField: _nullable(result.titleField),
        autoname: _nullable(result.autoname),
        isSingle: result.isSingle,
        isChild: result.isChild,
        isSubmittable: result.isSubmittable,
        trackChanges: result.trackChanges,
        allowCreate: result.allowCreate,
        allowEdit: result.allowEdit,
        allowDelete: result.allowDelete,
        allowImport: result.allowImport,
        allowExport: result.allowExport,
        genericWrite: true,
        enabled: result.enabled,
        metadata: const {'managed_by': 'WMN DocType Manager'},
      );
      _reload(select: saved.name);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _editDocType(WmnDocTypeMeta dt) async {
    if (dt.isSystem || !dt.genericWrite) return;
    final result = await showDialog<_DocTypeDraft>(
      context: context,
      builder: (_) => _DocTypeDialog(existing: dt, modules: widget.meta.modules(enabledOnly: false)),
    );
    if (result == null) return;
    try {
      widget.meta.saveDocType(
        name: dt.name,
        module: result.module,
        titleField: _nullable(result.titleField),
        autoname: _nullable(result.autoname),
        isSingle: result.isSingle,
        isChild: result.isChild,
        isSubmittable: result.isSubmittable,
        trackChanges: result.trackChanges,
        allowCreate: result.allowCreate,
        allowEdit: result.allowEdit,
        allowDelete: result.allowDelete,
        allowImport: result.allowImport,
        allowExport: result.allowExport,
        genericWrite: true,
        enabled: result.enabled,
        metadata: dt.metadata,
      );
      _reload(select: dt.name);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  void _validateDocType(WmnDocTypeMeta dt) {
    try {
      widget.meta.validateDocTypeDefinition(dt.name);
      if (!mounted) return;
      setState(() => _error = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${context.wmnT('doctype_valid')}: ${dt.name}')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _deleteDocType(WmnDocTypeMeta dt) async {
    if (dt.isSystem || !dt.genericWrite) return;
    final references = widget.meta.doctypeReferences(dt.name);
    if (references.isNotEmpty) {
      setState(() => _error = '${context.wmnT('doctype_still_referenced')}: ${references.join(', ')}');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.wmnT('delete_doctype')),
        content: Text('${context.wmnT('delete_doctype_confirm')}\n${dt.name}\n${dt.tableName ?? ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.wmnT('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.wmnT('delete'))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      widget.meta.deleteDocType(dt.name);
      _selectedName = null;
      _reload();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _addField(WmnDocTypeMeta dt) async {
    if (dt.isSystem || !dt.genericWrite) return;
    final result = await showDialog<_FieldDraft>(
      context: context,
      builder: (_) => _FieldDialog(
        meta: widget.meta,
        doctype: dt,
        nextIndex: dt.fields.isEmpty ? 1 : dt.fields.map((entry) => entry.index).reduce((a, b) => a > b ? a : b) + 1,
      ),
    );
    if (result == null) return;
    await _saveField(dt, result);
  }

  Future<void> _editField(WmnDocTypeMeta dt, WmnFieldMeta field) async {
    if (dt.isSystem || !dt.genericWrite) return;
    final result = await showDialog<_FieldDraft>(
      context: context,
      builder: (_) => _FieldDialog(meta: widget.meta, doctype: dt, existing: field, nextIndex: field.index),
    );
    if (result == null) return;
    await _saveField(dt, result);
  }

  Future<void> _saveField(WmnDocTypeMeta dt, _FieldDraft field) async {
    try {
      final metadata = <String, Object?>{
        ...?dt.field(field.fieldName)?.metadata,
      };
      if (field.description.trim().isEmpty) {
        metadata.remove('description');
      } else {
        metadata['description'] = field.description.trim();
      }
      if (field.renderAs == 'AUTO') {
        metadata.remove('render_as');
      } else {
        metadata['render_as'] = field.renderAs;
      }
      widget.meta.saveField(
        doctype: dt.name,
        fieldName: field.fieldName,
        label: field.label,
        fieldType: field.fieldType,
        options: _nullable(field.options),
        index: field.index,
        required: field.required,
        readOnly: field.readOnly,
        hidden: field.hidden,
        inListView: field.inListView,
        inStandardFilter: field.inStandardFilter,
        searchable: field.searchable,
        allowOnSubmit: field.allowOnSubmit,
        defaultValue: _parseDefault(field.defaultValue),
        dependsOn: _nullable(field.dependsOn),
        mandatoryDependsOn: _nullable(field.mandatoryDependsOn),
        readOnlyDependsOn: _nullable(field.readOnlyDependsOn),
        fetchFrom: _nullable(field.fetchFrom),
        precision: int.tryParse(field.precision.trim()),
        length: int.tryParse(field.length.trim()),
        metadata: metadata,
      );
      _reload(select: dt.name);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _deleteField(WmnDocTypeMeta dt, WmnFieldMeta field) async {
    if (dt.isSystem || !dt.genericWrite) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.wmnT('delete_field')),
        content: Text('${context.wmnT('delete_field_confirm')}\n${field.fieldName}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.wmnT('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.wmnT('delete'))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      widget.meta.deleteField(dt.name, field.fieldName);
      _reload(select: dt.name);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  void _moveField(WmnDocTypeMeta dt, int index, int delta) {
    if (dt.isSystem || !dt.genericWrite) return;
    final ordered = [...dt.fields]..sort((a, b) => a.index.compareTo(b.index));
    final target = index + delta;
    if (index < 0 || target < 0 || index >= ordered.length || target >= ordered.length) return;
    final item = ordered.removeAt(index);
    ordered.insert(target, item);
    try {
      widget.meta.reorderFields(dt.name, ordered.map((entry) => entry.fieldName).toList(growable: false));
      _reload(select: dt.name);
    } catch (error) {
      setState(() => _error = error.toString());
    }
  }

  Future<void> _createModule() async {
    final controller = TextEditingController();
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(dialogContext.wmnT('new_module')),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(labelText: dialogContext.wmnT('module_label')),
            onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(dialogContext.wmnT('cancel'))),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
              child: Text(dialogContext.wmnT('save')),
            ),
          ],
        ),
      );
      if (name == null || name.trim().isEmpty) return;
      widget.meta.saveModule(name: name.trim());
      _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${context.wmnT('module_saved')}: ${name.trim()}')));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      controller.dispose();
    }
  }

  Future<void> _openStudio(WmnDocTypeMeta dt) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WmnDocTypeStudioPage(meta: widget.meta, doctypeName: dt.name),
      ),
    );
    _reload(select: dt.name);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(context.wmnT('doctype_manager')),
          actions: [
            OutlinedButton.icon(
              onPressed: _createModule,
              icon: const Icon(Icons.view_module_outlined),
              label: Text(context.wmnT('new_module')),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _createDocType,
              icon: const Icon(Icons.add),
              label: Text(context.wmnT('new_doctype')),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            if (_error != null)
              MaterialBanner(
                content: Text(_error!),
                actions: [TextButton(onPressed: () => setState(() => _error = null), child: Text(context.wmnT('close')))],
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 900) {
                    return Row(
                      children: [
                        SizedBox(width: 330, child: _browser()),
                        const VerticalDivider(width: 1),
                        Expanded(child: _details()),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      SizedBox(height: 260, child: _browser()),
                      const Divider(height: 1),
                      Expanded(child: _details()),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      );

  Widget _browser() {
    final rows = _rows;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: SearchBar(
            controller: _search,
            leading: const Icon(Icons.search),
            hintText: context.wmnT('search_doctype'),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final dt = rows[index];
              return ListTile(
                dense: true,
                selected: _selectedName == dt.name,
                leading: Icon(dt.isSystem ? Icons.lock_outline : Icons.description_outlined),
                title: Text(dt.name),
                subtitle: Text('${dt.module} • ${dt.tableName ?? '-'}'),
                trailing: dt.enabled ? null : const Icon(Icons.visibility_off_outlined, size: 18),
                onTap: () => setState(() => _selectedName = dt.name),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _details() {
    final dt = _selected;
    if (dt == null) return Center(child: Text(context.wmnT('no_data')));
    final editable = !dt.isSystem && dt.genericWrite;
    final fields = [...dt.fields]..sort((a, b) => a.index.compareTo(b.index));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(dt.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            Chip(label: Text(dt.module)),
            Chip(label: Text(dt.tableName ?? '-')),
            if (dt.isSystem) Chip(label: Text(context.wmnT('system_doctype'))),
            if (dt.isChild) Chip(label: Text(context.wmnT('child_doctype'))),
            if (dt.isSubmittable) Chip(label: Text(context.wmnT('submittable'))),
            FilledButton.icon(
              onPressed: () => _openStudio(dt),
              icon: const Icon(Icons.code_outlined),
              label: Text(context.wmnT('open_doctype_studio')),
            ),
            OutlinedButton.icon(
              onPressed: () => _validateDocType(dt),
              icon: const Icon(Icons.verified_outlined),
              label: Text(context.wmnT('validate_doctype')),
            ),
            if (editable)
              OutlinedButton.icon(onPressed: () => _editDocType(dt), icon: const Icon(Icons.edit_outlined), label: Text(context.wmnT('edit_doctype'))),
            if (editable)
              OutlinedButton.icon(onPressed: () => _deleteDocType(dt), icon: const Icon(Icons.delete_outline), label: Text(context.wmnT('delete_doctype'))),
          ],
        ),
        const SizedBox(height: 10),
        if (dt.isSystem)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(context.wmnT('system_doctype_read_only')),
            ),
          ),
        _DocTypeSummary(dt: dt),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: Text(context.wmnT('fields'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
            if (editable)
              FilledButton.icon(onPressed: () => _addField(dt), icon: const Icon(Icons.add), label: Text(context.wmnT('new_field'))),
          ],
        ),
        const SizedBox(height: 8),
        if (fields.isEmpty)
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(context.wmnT('no_data'))))
        else
          ...fields.asMap().entries.map((entry) => _FieldCard(
                field: entry.value,
                editable: editable,
                canMoveUp: entry.key > 0,
                canMoveDown: entry.key < fields.length - 1,
                onEdit: () => _editField(dt, entry.value),
                onDelete: () => _deleteField(dt, entry.value),
                onMoveUp: () => _moveField(dt, entry.key, -1),
                onMoveDown: () => _moveField(dt, entry.key, 1),
              )),
      ],
    );
  }

  String? _nullable(String value) => value.trim().isEmpty ? null : value.trim();

  Object? _parseDefault(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } catch (_) {
      return text;
    }
  }
}

class _DocTypeSummary extends StatelessWidget {
  const _DocTypeSummary({required this.dt});

  final WmnDocTypeMeta dt;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 14,
            runSpacing: 10,
            children: [
              _Pair(label: context.wmnT('physical_table'), value: dt.tableName ?? '-'),
              _Pair(label: context.wmnT('title_field'), value: dt.titleField ?? '-'),
              _Pair(label: context.wmnT('autoname'), value: dt.autoname ?? '-'),
              _Pair(label: context.wmnT('allow_create'), value: _yesNo(context, dt.allowCreate)),
              _Pair(label: context.wmnT('allow_edit'), value: _yesNo(context, dt.allowEdit)),
              _Pair(label: context.wmnT('allow_delete'), value: _yesNo(context, dt.allowDelete)),
              _Pair(label: context.wmnT('allow_import'), value: _yesNo(context, dt.allowImport)),
              _Pair(label: context.wmnT('allow_export'), value: _yesNo(context, dt.allowExport)),
            ],
          ),
        ),
      );

  static String _yesNo(BuildContext context, bool value) => context.wmnT(value ? 'yes' : 'no');
}

class _Pair extends StatelessWidget {
  const _Pair({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 220,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 2),
            SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _FieldCard extends StatelessWidget {
  const _FieldCard({
    required this.field,
    required this.editable,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onEdit,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final WmnFieldMeta field;
  final bool editable;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: CircleAvatar(child: Text('${field.index}')),
          title: Text('${field.label}  •  ${field.fieldName}', style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text([
            field.fieldType,
            if ('${field.metadata['render_as'] ?? ''}'.trim().isNotEmpty) '${context.wmnT('render_as')}: ${field.metadata['render_as']}',
            if (field.options?.trim().isNotEmpty == true) '${context.wmnT('options')}: ${field.options}',
            if (field.required) context.wmnT('required'),
            if (field.readOnly) context.wmnT('read_only'),
            if (field.inListView) context.wmnT('in_list_view'),
            if (field.searchable) context.wmnT('searchable'),
          ].join(' • ')),
          trailing: editable
              ? PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'edit') onEdit();
                    if (action == 'delete') onDelete();
                    if (action == 'up') onMoveUp();
                    if (action == 'down') onMoveDown();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'edit', child: Text(context.wmnT('edit'))),
                    if (canMoveUp) PopupMenuItem(value: 'up', child: Text(context.wmnT('move_up'))),
                    if (canMoveDown) PopupMenuItem(value: 'down', child: Text(context.wmnT('move_down'))),
                    PopupMenuItem(value: 'delete', child: Text(context.wmnT('delete'))),
                  ],
                )
              : null,
        ),
      );
}

class _DocTypeDraft {
  const _DocTypeDraft({
    required this.name,
    required this.module,
    required this.titleField,
    required this.autoname,
    required this.isSingle,
    required this.isChild,
    required this.isSubmittable,
    required this.trackChanges,
    required this.allowCreate,
    required this.allowEdit,
    required this.allowDelete,
    required this.allowImport,
    required this.allowExport,
    required this.enabled,
  });

  final String name;
  final String module;
  final String titleField;
  final String autoname;
  final bool isSingle;
  final bool isChild;
  final bool isSubmittable;
  final bool trackChanges;
  final bool allowCreate;
  final bool allowEdit;
  final bool allowDelete;
  final bool allowImport;
  final bool allowExport;
  final bool enabled;
}

class _DocTypeDialog extends StatefulWidget {
  const _DocTypeDialog({this.existing, required this.modules});

  final WmnDocTypeMeta? existing;
  final List<String> modules;

  @override
  State<_DocTypeDialog> createState() => _DocTypeDialogState();
}

class _DocTypeDialogState extends State<_DocTypeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(text: widget.existing?.name ?? '');
  late String _module = widget.existing?.module ?? (widget.modules.contains('Custom') ? 'Custom' : widget.modules.first);
  late final TextEditingController _titleField = TextEditingController(text: widget.existing?.titleField ?? '');
  late final TextEditingController _autoname = TextEditingController(text: widget.existing?.autoname ?? '');
  late bool _isSingle = widget.existing?.isSingle ?? false;
  late bool _isChild = widget.existing?.isChild ?? false;
  late bool _isSubmittable = widget.existing?.isSubmittable ?? false;
  late bool _trackChanges = widget.existing?.trackChanges ?? true;
  late bool _allowCreate = widget.existing?.allowCreate ?? true;
  late bool _allowEdit = widget.existing?.allowEdit ?? true;
  late bool _allowDelete = widget.existing?.allowDelete ?? true;
  late bool _allowImport = widget.existing?.allowImport ?? true;
  late bool _allowExport = widget.existing?.allowExport ?? true;
  late bool _enabled = widget.existing?.enabled ?? true;

  @override
  void dispose() {
    _name.dispose();
    _titleField.dispose();
    _autoname.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.existing == null ? context.wmnT('new_doctype') : context.wmnT('edit_doctype')),
        content: SizedBox(
          width: 620,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _name,
                    readOnly: widget.existing != null,
                    decoration: InputDecoration(labelText: context.wmnT('doctype_name')),
                    validator: (value) => value == null || value.trim().isEmpty ? context.wmnT('required') : null,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: widget.modules.contains(_module) ? _module : widget.modules.first,
                    decoration: InputDecoration(labelText: context.wmnT('module_label')),
                    items: widget.modules
                        .map((entry) => DropdownMenuItem(value: entry, child: Text(entry)))
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) setState(() => _module = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: _titleField, decoration: InputDecoration(labelText: context.wmnT('title_field'))),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _autoname,
                    decoration: InputDecoration(labelText: context.wmnT('autoname'), helperText: 'field:fieldname / format:...'),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _Flag(label: context.wmnT('single_doctype'), value: _isSingle, onChanged: (value) => setState(() => _isSingle = value)),
                      _Flag(label: context.wmnT('child_doctype'), value: _isChild, onChanged: (value) => setState(() => _isChild = value)),
                      _Flag(label: context.wmnT('submittable'), value: _isSubmittable, onChanged: (value) => setState(() => _isSubmittable = value)),
                      _Flag(label: context.wmnT('track_changes'), value: _trackChanges, onChanged: (value) => setState(() => _trackChanges = value)),
                      _Flag(label: context.wmnT('allow_create'), value: _allowCreate, onChanged: (value) => setState(() => _allowCreate = value)),
                      _Flag(label: context.wmnT('allow_edit'), value: _allowEdit, onChanged: (value) => setState(() => _allowEdit = value)),
                      _Flag(label: context.wmnT('allow_delete'), value: _allowDelete, onChanged: (value) => setState(() => _allowDelete = value)),
                      _Flag(label: context.wmnT('allow_import'), value: _allowImport, onChanged: (value) => setState(() => _allowImport = value)),
                      _Flag(label: context.wmnT('allow_export'), value: _allowExport, onChanged: (value) => setState(() => _allowExport = value)),
                      _Flag(label: context.wmnT('enabled'), value: _enabled, onChanged: (value) => setState(() => _enabled = value)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(context.wmnT('cancel'))),
          FilledButton(
            onPressed: () {
              if (!(_formKey.currentState?.validate() ?? false)) return;
              Navigator.pop(
                context,
                _DocTypeDraft(
                  name: _name.text.trim(),
                  module: _module,
                  titleField: _titleField.text.trim(),
                  autoname: _autoname.text.trim(),
                  isSingle: _isSingle,
                  isChild: _isChild,
                  isSubmittable: _isSubmittable,
                  trackChanges: _trackChanges,
                  allowCreate: _allowCreate,
                  allowEdit: _allowEdit,
                  allowDelete: _allowDelete,
                  allowImport: _allowImport,
                  allowExport: _allowExport,
                  enabled: _enabled,
                ),
              );
            },
            child: Text(context.wmnT('save')),
          ),
        ],
      );
}

class _Flag extends StatelessWidget {
  const _Flag({required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => FilterChip(label: Text(label), selected: value, onSelected: onChanged);
}

class _FieldDraft {
  const _FieldDraft({
    required this.fieldName,
    required this.label,
    required this.fieldType,
    required this.options,
    required this.index,
    required this.required,
    required this.readOnly,
    required this.hidden,
    required this.inListView,
    required this.inStandardFilter,
    required this.searchable,
    required this.allowOnSubmit,
    required this.defaultValue,
    required this.dependsOn,
    required this.mandatoryDependsOn,
    required this.readOnlyDependsOn,
    required this.fetchFrom,
    required this.precision,
    required this.length,
    required this.description,
    required this.renderAs,
  });

  final String fieldName;
  final String label;
  final String fieldType;
  final String options;
  final int index;
  final bool required;
  final bool readOnly;
  final bool hidden;
  final bool inListView;
  final bool inStandardFilter;
  final bool searchable;
  final bool allowOnSubmit;
  final String defaultValue;
  final String dependsOn;
  final String mandatoryDependsOn;
  final String readOnlyDependsOn;
  final String fetchFrom;
  final String precision;
  final String length;
  final String description;
  final String renderAs;
}

class _FieldDialog extends StatefulWidget {
  const _FieldDialog({required this.meta, required this.doctype, required this.nextIndex, this.existing});

  final WmnMetaService meta;
  final WmnDocTypeMeta doctype;
  final WmnFieldMeta? existing;
  final int nextIndex;

  @override
  State<_FieldDialog> createState() => _FieldDialogState();
}

class _FieldDialogState extends State<_FieldDialog> {
  static const _fieldTypes = <String>[
    'Data', 'Small Text', 'Long Text', 'Text', 'Text Editor', 'Code', 'HTML', 'JSON',
    'Int', 'Float', 'Currency', 'Percent', 'Duration', 'Check', 'Select', 'Link',
    'Dynamic Link', 'Date', 'Datetime', 'Time', 'Table', 'Table MultiSelect',
    'Section Break', 'Column Break', 'Tab Break',
  ];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fieldName = TextEditingController(text: widget.existing?.fieldName ?? '');
  late final TextEditingController _label = TextEditingController(text: widget.existing?.label ?? '');
  late final TextEditingController _options = TextEditingController(text: widget.existing?.options ?? '');
  late final TextEditingController _defaultValue = TextEditingController(text: _defaultText(widget.existing?.defaultValue));
  late final TextEditingController _dependsOn = TextEditingController(text: widget.existing?.dependsOn ?? '');
  late final TextEditingController _mandatoryDependsOn = TextEditingController(text: widget.existing?.mandatoryDependsOn ?? '');
  late final TextEditingController _readOnlyDependsOn = TextEditingController(text: widget.existing?.readOnlyDependsOn ?? '');
  late final TextEditingController _fetchFrom = TextEditingController(text: widget.existing?.fetchFrom ?? '');
  late final TextEditingController _precision = TextEditingController(text: widget.existing?.precision?.toString() ?? '');
  late final TextEditingController _length = TextEditingController(text: widget.existing?.length?.toString() ?? '');
  late final TextEditingController _description = TextEditingController(text: '${widget.existing?.metadata['description'] ?? ''}');
  late String _fieldType = widget.existing?.fieldType ?? 'Data';
  late String _renderAs = '${widget.existing?.metadata['render_as'] ?? 'AUTO'}'.trim().toUpperCase();
  late bool _required = widget.existing?.required ?? false;
  late bool _readOnly = widget.existing?.readOnly ?? false;
  late bool _hidden = widget.existing?.hidden ?? false;
  late bool _inListView = widget.existing?.inListView ?? false;
  late bool _inStandardFilter = widget.existing?.inStandardFilter ?? false;
  late bool _searchable = widget.existing?.searchable ?? false;
  late bool _allowOnSubmit = widget.existing?.allowOnSubmit ?? false;

  static String _defaultText(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    return jsonEncode(value);
  }

  @override
  void dispose() {
    _fieldName.dispose();
    _label.dispose();
    _options.dispose();
    _defaultValue.dispose();
    _dependsOn.dispose();
    _mandatoryDependsOn.dispose();
    _readOnlyDependsOn.dispose();
    _fetchFrom.dispose();
    _precision.dispose();
    _length.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? context.wmnT('edit_field') : context.wmnT('new_field')),
      content: SizedBox(
        width: 680,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _fieldName,
                        readOnly: editing,
                        decoration: InputDecoration(labelText: context.wmnT('field_name')),
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.isEmpty) return context.wmnT('required');
                          if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(text)) return context.wmnT('invalid_field_name');
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _label,
                        decoration: InputDecoration(labelText: context.wmnT('label')),
                        validator: (value) => value == null || value.trim().isEmpty ? context.wmnT('required') : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _fieldType,
                  decoration: InputDecoration(
                    labelText: context.wmnT('field_type'),
                    helperText: editing ? context.wmnT('field_type_storage_guard') : null,
                  ),
                  items: _fieldTypes.map((entry) => DropdownMenuItem(value: entry, child: Text(entry))).toList(growable: false),
                  onChanged: (value) => setState(() => _fieldType = value ?? _fieldType),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: const <String>{
                    'AUTO', 'TEXT', 'SELECT', 'LINK', 'DYNAMIC_LINK', 'CHECKBOX',
                    'NUMBER', 'MULTILINE', 'DATE', 'DATETIME', 'TIME',
                  }.contains(_renderAs) ? _renderAs : 'AUTO',
                  decoration: InputDecoration(
                    labelText: context.wmnT('render_as'),
                    helperText: context.wmnT('render_as_help'),
                  ),
                  items: const <String>[
                    'AUTO', 'TEXT', 'SELECT', 'LINK', 'DYNAMIC_LINK', 'CHECKBOX',
                    'NUMBER', 'MULTILINE', 'DATE', 'DATETIME', 'TIME',
                  ].map((entry) => DropdownMenuItem(value: entry, child: Text(entry))).toList(growable: false),
                  onChanged: (value) => setState(() => _renderAs = value ?? 'AUTO'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _options,
                  minLines: 1,
                  maxLines: 5,
                  decoration: InputDecoration(labelText: context.wmnT('options'), helperText: _optionsHelp(context)),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: TextField(controller: _defaultValue, decoration: InputDecoration(labelText: context.wmnT('default_value')))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: _length, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.wmnT('length')))),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: _precision, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: context.wmnT('precision')))),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(controller: _fetchFrom, decoration: InputDecoration(labelText: context.wmnT('fetch_from'))),
                const SizedBox(height: 10),
                TextField(controller: _dependsOn, decoration: InputDecoration(labelText: context.wmnT('depends_on'))),
                const SizedBox(height: 10),
                TextField(controller: _mandatoryDependsOn, decoration: InputDecoration(labelText: context.wmnT('mandatory_depends_on'))),
                const SizedBox(height: 10),
                TextField(controller: _readOnlyDependsOn, decoration: InputDecoration(labelText: context.wmnT('read_only_depends_on'))),
                const SizedBox(height: 10),
                TextField(controller: _description, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: context.wmnT('description'))),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _Flag(label: context.wmnT('required'), value: _required, onChanged: (value) => setState(() => _required = value)),
                    _Flag(label: context.wmnT('read_only'), value: _readOnly, onChanged: (value) => setState(() => _readOnly = value)),
                    _Flag(label: context.wmnT('hidden'), value: _hidden, onChanged: (value) => setState(() => _hidden = value)),
                    _Flag(label: context.wmnT('in_list_view'), value: _inListView, onChanged: (value) => setState(() => _inListView = value)),
                    _Flag(label: context.wmnT('standard_filter'), value: _inStandardFilter, onChanged: (value) => setState(() => _inStandardFilter = value)),
                    _Flag(label: context.wmnT('searchable'), value: _searchable, onChanged: (value) => setState(() => _searchable = value)),
                    _Flag(label: context.wmnT('allow_on_submit'), value: _allowOnSubmit, onChanged: (value) => setState(() => _allowOnSubmit = value)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.wmnT('cancel'))),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.pop(
              context,
              _FieldDraft(
                fieldName: _fieldName.text.trim(),
                label: _label.text.trim(),
                fieldType: _fieldType,
                options: _options.text.trim(),
                index: widget.existing?.index ?? widget.nextIndex,
                required: _required,
                readOnly: _readOnly,
                hidden: _hidden,
                inListView: _inListView,
                inStandardFilter: _inStandardFilter,
                searchable: _searchable,
                allowOnSubmit: _allowOnSubmit,
                defaultValue: _defaultValue.text,
                dependsOn: _dependsOn.text,
                mandatoryDependsOn: _mandatoryDependsOn.text,
                readOnlyDependsOn: _readOnlyDependsOn.text,
                fetchFrom: _fetchFrom.text,
                precision: _precision.text,
                length: _length.text,
                description: _description.text,
                renderAs: _renderAs,
              ),
            );
          },
          child: Text(context.wmnT('save')),
        ),
      ],
    );
  }

  String _optionsHelp(BuildContext context) {
    if (_fieldType == 'Link' || _renderAs == 'LINK') return context.wmnT('link_options_help');
    if (_fieldType == 'Dynamic Link' || _renderAs == 'DYNAMIC_LINK') {
      return context.wmnT('dynamic_link_options_help');
    }
    if (const {'Table', 'Table MultiSelect'}.contains(_fieldType)) {
      return context.wmnT('table_options_help');
    }
    if (_fieldType == 'Select' || _renderAs == 'SELECT') return context.wmnT('select_options_help');
    return context.wmnT('optional');
  }
}
