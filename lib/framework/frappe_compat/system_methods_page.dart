import 'package:flutter/material.dart';

import '../../core/localization/wmn_localization.dart';
import 'frappe_method_management.dart';
import 'frappe_runtime.dart';

class WmnSystemMethodsPage extends StatefulWidget {
  const WmnSystemMethodsPage({super.key, required this.runtime});

  final WmnFrappeRuntime runtime;

  @override
  State<WmnSystemMethodsPage> createState() => _WmnSystemMethodsPageState();
}

class _WmnSystemMethodsPageState extends State<WmnSystemMethodsPage> {
  late final WmnMethodManagementService _management = WmnMethodManagementService(
    database: widget.runtime.db.database,
    meta: widget.runtime.meta.meta,
  );
  String? _error;

  Set<String> get _supportedApis {
    final values = widget.runtime.methods
        .catalog()
        .map((entry) => '${entry['method_name'] ?? ''}')
        .where((entry) => entry.isNotEmpty)
        .toSet();
    for (final module in _management.customMethodModules()) {
      for (final exportName in module.exports) {
        values.add('${module.name}.$exportName');
      }
    }
    return values;
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: Text(context.wmnT('system_scripts_methods')),
            bottom: TabBar(
              isScrollable: true,
              tabs: [
                Tab(text: context.wmnT('system_method_modules')),
                Tab(text: context.wmnT('system_scripts')),
                Tab(text: context.wmnT('custom_method_modules')),
                Tab(text: context.wmnT('custom_scripts')),
              ],
            ),
          ),
          body: Column(
            children: [
              if (_error != null)
                MaterialBanner(
                  content: Text(_error!),
                  actions: [
                    TextButton(
                      onPressed: () => setState(() => _error = null),
                      child: Text(context.wmnT('close')),
                    ),
                  ],
                ),
              Expanded(
                child: TabBarView(
                  children: [
                    _systemMethodModules(),
                    _systemScripts(),
                    _customMethodModules(),
                    _customScripts(),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _systemMethodModules() {
    final modules = _management.systemMethodModules(widget.runtime.methods.catalog());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(context.wmnT('system_method_modules_help')),
          ),
        ),
        const SizedBox(height: 8),
        if (modules.isEmpty)
          Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(context.wmnT('no_data')))),
        for (final module in modules)
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: SelectableText(module.name),
              subtitle: Text([
                module.status,
                '${module.exports.length} ${context.wmnT('module_exports')}',
                if ((module.sourceApp ?? '').isNotEmpty) module.sourceApp!,
              ].join(' • ')),
              trailing: const Icon(Icons.lock_outline),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              children: [
                if ((module.description ?? '').isNotEmpty)
                  Align(alignment: AlignmentDirectional.centerStart, child: Text(module.description!)),
                if ((module.description ?? '').isNotEmpty) const SizedBox(height: 10),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(context.wmnT('module_exports'), style: Theme.of(context).textTheme.titleSmall),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final exportName in module.exports) Chip(label: SelectableText(exportName)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _systemScripts() {
    final rows = widget.runtime.db.database.db.select('''
      SELECT hook_type,reference_doctype,event_name,target_kind,target,source_app,source_path,priority,enabled
      FROM wmn_hook_bindings
      WHERE target_kind NOT IN ('SERVER_SCRIPT','METHOD')
        AND (reference_doctype IS NULL OR reference_doctype='' OR reference_doctype='*')
      ORDER BY hook_type,event_name,priority,target;
    ''');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(context.wmnT('system_scripts_help')),
          ),
        ),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(context.wmnT('no_data')))),
        for (final row in rows)
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_tree_outlined),
              title: Text([
                '${row['hook_type']}',
                if ('${row['event_name'] ?? ''}'.isNotEmpty) '${row['event_name']}',
              ].join(' • ')),
              subtitle: Text([
                '${row['target_kind']}',
                if ('${row['target'] ?? ''}'.isNotEmpty) '${row['target']}',
                if ('${row['source_app'] ?? ''}'.isNotEmpty) '${row['source_app']}',
                if ('${row['source_path'] ?? ''}'.isNotEmpty) '${row['source_path']}',
              ].join(' • ')),
              trailing: const Icon(Icons.lock_outline),
            ),
          ),
      ],
    );
  }

  Widget _customMethodModules() {
    final rows = _management.customMethodModules();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: Text(context.wmnT('custom_method_modules_help'))),
            FilledButton.icon(
              onPressed: () => _editMethodModule(),
              icon: const Icon(Icons.add),
              label: Text(context.wmnT('add_custom_method_module')),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(context.wmnT('no_data')))),
        for (final row in rows)
          Card(
            child: ListTile(
              leading: const Icon(Icons.description_outlined),
              title: SelectableText(row.name),
              subtitle: Text([
                row.status,
                '${context.wmnT('revision')} ${row.revision}',
                '${row.exports.length} ${context.wmnT('module_exports')}',
                if (row.dependencies.isNotEmpty) '${row.dependencies.length} ${context.wmnT('module_dependencies')}',
                if (row.diagnostics.isNotEmpty) '${row.diagnostics.length} ${context.wmnT('diagnostics')}',
                if ((row.description ?? '').isNotEmpty) row.description!,
              ].join(' • ')),
              trailing: PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'edit') await _editMethodModule(existing: row);
                  if (value == 'delete') await _deleteMethodModule(row);
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'edit', child: Text(context.wmnT('edit'))),
                  PopupMenuItem(value: 'delete', child: Text(context.wmnT('delete'))),
                ],
              ),
              onTap: () => _editMethodModule(existing: row),
            ),
          ),
      ],
    );
  }

  Widget _customScripts() {
    final rows = _management.customScripts();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: Text(context.wmnT('custom_scripts_help'))),
            FilledButton.icon(
              onPressed: () => _editScript(),
              icon: const Icon(Icons.add),
              label: Text(context.wmnT('add_custom_script')),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(context.wmnT('no_data')))),
        for (final row in rows)
          Card(
            child: ListTile(
              leading: const Icon(Icons.code_outlined),
              title: SelectableText(row.name),
              subtitle: Text([
                row.status,
                '${context.wmnT('revision')} ${row.revision}',
                if (row.diagnostics.isNotEmpty) '${row.diagnostics.length} ${context.wmnT('diagnostics')}',
                if ((row.description ?? '').isNotEmpty) row.description!,
              ].join(' • ')),
              trailing: PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'edit') await _editScript(existing: row);
                  if (value == 'delete') await _deleteScript(row);
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'edit', child: Text(context.wmnT('edit'))),
                  PopupMenuItem(value: 'delete', child: Text(context.wmnT('delete'))),
                ],
              ),
              onTap: () => _editScript(existing: row),
            ),
          ),
      ],
    );
  }

  Future<void> _editMethodModule({WmnManagedMethodModule? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? 'custom.');
    final descriptionController = TextEditingController(text: existing?.description ?? '');
    final sourceController = TextEditingController(
      text: existing?.source ??
          'function example(args) {\n'
              '  return wmn.document.insert(args);\n'
              '}\n',
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing == null
            ? context.wmnT('add_custom_method_module')
            : context.wmnT('edit_custom_method_module')),
        content: SizedBox(
          width: 820,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  enabled: existing == null,
                  decoration: InputDecoration(
                    labelText: context.wmnT('method_module_name'),
                    helperText: 'custom.sales.tools',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  maxLines: 2,
                  decoration: InputDecoration(labelText: context.wmnT('description')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: sourceController,
                  minLines: 16,
                  maxLines: 28,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    labelText: context.wmnT('method_module_source'),
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(context.wmnT('method_module_help')),
                  ),
                ),
                if (existing != null && existing.exports.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text('${context.wmnT('module_exports')}: ${existing.exports.join(', ')}'),
                  ),
                ],
                if (existing != null && existing.dependencies.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text('${context.wmnT('module_dependencies')}: ${existing.dependencies.join(', ')}'),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(context.wmnT('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(context.wmnT('validate_and_save'))),
        ],
      ),
    );

    final moduleName = nameController.text;
    final description = descriptionController.text;
    final source = sourceController.text;
    nameController.dispose();
    descriptionController.dispose();
    sourceController.dispose();
    if (saved != true) return;
    _guard(() {
      final module = _management.saveCustomMethodModule(
        id: existing?.id,
        name: existing?.name ?? moduleName,
        source: source,
        description: description,
        supportedApis: _supportedApis,
      );
      if (module.diagnostics.isNotEmpty) {
        final first = module.diagnostics.first;
        _error = '${module.status}: ${first.severity} ${first.code ?? ''} ${first.message}'.trim();
      }
    });
  }

  Future<void> _editScript({WmnManagedSystemScript? existing}) async {
    final nameController = TextEditingController(text: existing?.name ?? 'custom.');
    final descriptionController = TextEditingController(text: existing?.description ?? '');
    final sourceController = TextEditingController(text: existing?.source ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing == null ? context.wmnT('add_custom_script') : context.wmnT('edit_custom_script')),
        content: SizedBox(
          width: 780,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  enabled: existing == null,
                  decoration: InputDecoration(
                    labelText: context.wmnT('script_name'),
                    helperText: 'custom.system.script_name',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  maxLines: 2,
                  decoration: InputDecoration(labelText: context.wmnT('description')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: sourceController,
                  minLines: 14,
                  maxLines: 24,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    labelText: context.wmnT('script_source'),
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(context.wmnT('global_script_activation_help')),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(context.wmnT('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(context.wmnT('validate_and_save'))),
        ],
      ),
    );

    final scriptName = nameController.text;
    final description = descriptionController.text;
    final source = sourceController.text;
    nameController.dispose();
    descriptionController.dispose();
    sourceController.dispose();
    if (saved != true) return;
    _guard(() {
      final script = _management.saveCustomSystemScript(
        id: existing?.id,
        name: existing?.name ?? scriptName,
        source: source,
        description: description,
        supportedApis: _supportedApis,
      );
      if (script.diagnostics.isNotEmpty) {
        final first = script.diagnostics.first;
        _error = '${script.status}: ${first.severity} ${first.code ?? ''} ${first.message}'.trim();
      }
    });
  }

  Future<void> _deleteMethodModule(WmnManagedMethodModule module) async {
    final confirmed = await _confirmDelete(module.name, context.wmnT('delete_custom_method_module_confirm'));
    if (confirmed) _guard(() => _management.deleteCustomMethodModule(module.id));
  }

  Future<void> _deleteScript(WmnManagedSystemScript script) async {
    final confirmed = await _confirmDelete(script.name, context.wmnT('delete_custom_script_confirm'));
    if (confirmed) _guard(() => _management.deleteCustomScript(script.id));
  }

  Future<bool> _confirmDelete(String name, String message) async =>
      (await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.wmnT('delete')),
          content: Text('$message\n$name'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.wmnT('cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.wmnT('delete'))),
          ],
        ),
      )) ??
      false;

  void _guard(VoidCallback action) {
    try {
      _error = null;
      action();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }
}
