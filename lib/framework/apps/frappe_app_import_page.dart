import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/localization/wmn_localization.dart';
import '../../platform/files/wmn_file_adapter.dart';
import '../../platform/files/wmn_file_interaction_service.dart';
import 'frappe_app_converter.dart';
import 'frappe_app_package_converter.dart';
import 'frappe_source_porting_workbench_page.dart';

class WmnFrappeAppImportPage extends StatefulWidget {
  const WmnFrappeAppImportPage({
    super.key,
    required this.converter,
    required this.packageConverter,
    required this.fileInteractions,
  });

  final WmnFrappeAppConverter converter;
  final WmnFrappeAppPackageConverter packageConverter;
  final WmnFileInteractionService fileInteractions;

  @override
  State<WmnFrappeAppImportPage> createState() => _WmnFrappeAppImportPageState();
}

class _WmnFrappeAppImportPageState extends State<WmnFrappeAppImportPage> {
  final _app = TextEditingController();
  final _repo = TextEditingController(text: 'https://github.com/frappe/erpnext');
  final _ref = TextEditingController(text: 'version-16');
  final List<String> _messages = [];
  WmnFrappeAppConversionSummary? _summary;
  List<Map<String, Object?>> _artifacts = const [];
  List<Map<String, Object?>> _tasks = const [];
  List<String> _workbenchApps = const [];
  List<Map<String, Object?>> _installedApps = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reloadInstalledApps();
  }

  void _reloadInstalledApps() {
    _installedApps = widget.packageConverter.packages();
  }


  bool get _hasImportedFrappeStack {
    final names = _installedApps.map((app) => '${app['app_name']}').toSet();
    return names.contains('frappe') && names.contains('erpnext');
  }

  @override
  void dispose() {
    _app.dispose();
    _repo.dispose();
    _ref.dispose();
    super.dispose();
  }



  Future<void> _downloadErpNextV16Stack() async {
    final erpnextStackStart = context.wmnT('erpnext_stack_start');
    final frappeCoreDownloading = context.wmnT('frappe_core_downloading');
    final erpnextDownloading = context.wmnT('erpnext_downloading');
    final erpnextStackComplete = context.wmnT('erpnext_stack_complete');
    final convertedDocTypesLabel = context.wmnT('converted_doctypes');
    final convertedWorkspacesLabel = context.wmnT('converted_workspaces');
    final convertedPagesLabel = context.wmnT('converted_pages');
    final placeholderDependenciesLabel = context.wmnT('placeholder_dependencies');
    final portingTasksLabel = context.wmnT('porting_tasks');
    final packageConverter = widget.packageConverter;

    setState(() {
      _busy = true;
      _messages
        ..clear()
        ..add(erpnextStackStart);
      _summary = null;
      _artifacts = const [];
      _tasks = const [];
      _workbenchApps = const [];
    });
    try {
      const ref = 'version-16';
      const frappeRepo = 'https://github.com/frappe/frappe';
      const erpnextRepo = 'https://github.com/frappe/erpnext';

      _messages.add(frappeCoreDownloading);
      if (mounted) setState(() {});
      final frappeBytes = await packageConverter.downloadGitHubZip(
        repositoryUrl: frappeRepo,
        ref: ref,
      );
      if (!mounted) return;
      final frappeResult = packageConverter.convertZipBytes(
        frappeBytes,
        sourceName: frappeRepo,
        sourceKind: 'GITHUB',
        sourceRef: ref,
        appNameOverride: 'frappe',
      );
      _messages.add('✓ Frappe: ${frappeResult.convertedDocTypes} DocTypes, ${frappeResult.convertedWorkspaces} Workspaces, ${frappeResult.convertedPages} Pages');

      _messages.add(erpnextDownloading);
      setState(() {});
      final erpnextBytes = await packageConverter.downloadGitHubZip(
        repositoryUrl: erpnextRepo,
        ref: ref,
      );
      if (!mounted) return;
      final erpnextResult = packageConverter.convertZipBytes(
        erpnextBytes,
        sourceName: erpnextRepo,
        sourceKind: 'GITHUB',
        sourceRef: ref,
        appNameOverride: 'erpnext',
      );
      _messages.add('✓ ERPNext: ${erpnextResult.convertedDocTypes} DocTypes, ${erpnextResult.convertedWorkspaces} Workspaces, ${erpnextResult.convertedPages} Pages');
      _messages.add(erpnextStackComplete);
      _summary = erpnextResult;
      _artifacts = <Map<String, Object?>>[
        ...packageConverter.artifacts('frappe'),
        ...packageConverter.artifacts('erpnext'),
      ];
      _tasks = <Map<String, Object?>>[
        ...packageConverter.portingTasks('frappe'),
        ...packageConverter.portingTasks('erpnext'),
      ];
      _workbenchApps = const ['frappe', 'erpnext'];
      _reloadInstalledApps();
      _messages
        ..add('$convertedDocTypesLabel: ${frappeResult.convertedDocTypes + erpnextResult.convertedDocTypes}')
        ..add('$convertedWorkspacesLabel: ${frappeResult.convertedWorkspaces + erpnextResult.convertedWorkspaces}')
        ..add('$convertedPagesLabel: ${frappeResult.convertedPages + erpnextResult.convertedPages}')
        ..add('$placeholderDependenciesLabel: ${frappeResult.placeholderDocTypes + erpnextResult.placeholderDocTypes}')
        ..add('$portingTasksLabel: ${_tasks.length}');
      setState(() {});
    } catch (error) {
      _messages.add('✗ $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importErpNextLocalStack() async {
    final files = await widget.fileInteractions.pickFiles(
      filters: const <WmnFileTypeFilter>[
        WmnFileTypeFilter(
          label: 'Frappe + ERPNext ZIPs',
          extensions: <String>['zip'],
          mimeTypes: <String>['application/zip'],
          uniformTypeIdentifiers: <String>['public.zip-archive'],
        ),
      ],
    );
    if (files.isEmpty) return;
    final ordered = [...files]..sort((a, b) {
      int rank(String value) {
        final lower = value.toLowerCase();
        if (lower.contains('frappe')) return 0;
        if (lower.contains('erpnext')) return 1;
        return 2;
      }
      return rank(a.name).compareTo(rank(b.name));
    });
    setState(() {
      _busy = true;
      _messages
        ..clear()
        ..add(context.wmnT('local_stack_conversion_start'));
      _summary = null;
      _artifacts = const [];
      _tasks = const [];
      _workbenchApps = const [];
    });
    try {
      final convertedApps = <String>[];
      WmnFrappeAppConversionSummary? last;
      for (final file in ordered) {
        final bytes = file.bytes;
        if (!mounted) return;
        _messages.add('${context.wmnT('converting_app')}: ${file.name}');
        setState(() {});
        final result = widget.packageConverter.convertZipBytes(
          bytes,
          sourceName: file.name,
          sourceKind: 'ZIP',
        );
        convertedApps.add(result.manifest.appName);
        last = result;
        _messages.add('✓ ${result.manifest.appTitle}: ${result.convertedDocTypes} DocTypes • ${result.sourceUnits} source units');
      }
      if (!mounted) return;
      _summary = last;
      _workbenchApps = convertedApps.toSet().toList(growable: false);
      _artifacts = <Map<String, Object?>>[
        for (final app in _workbenchApps) ...widget.packageConverter.artifacts(app),
      ];
      _tasks = <Map<String, Object?>>[
        for (final app in _workbenchApps) ...widget.packageConverter.portingTasks(app),
      ];
      _reloadInstalledApps();
      _messages.add(context.wmnT('local_stack_conversion_complete'));
      setState(() {});
    } catch (error) {
      _messages.add('✗ $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importZip() async {
    final file = await widget.fileInteractions.pickFile(
      filters: const <WmnFileTypeFilter>[
        WmnFileTypeFilter(
          label: 'Frappe / ERPNext app ZIP',
          extensions: <String>['zip'],
          mimeTypes: <String>['application/zip'],
          uniformTypeIdentifiers: <String>['public.zip-archive'],
        ),
      ],
    );
    if (file == null) return;
    await _convert(file.bytes, sourceName: file.name, sourceKind: 'ZIP');
  }

  Future<void> _downloadAndConvert() async {
    setState(() {
      _busy = true;
      _messages
        ..clear()
        ..add(context.wmnT('downloading_app'));
      _summary = null;
      _artifacts = const [];
      _tasks = const [];
      _workbenchApps = const [];
    });
    try {
      final bytes = await widget.packageConverter.downloadGitHubZip(repositoryUrl: _repo.text, ref: _ref.text);
      if (!mounted) return;
      _messages.add(context.wmnT('converting_app'));
      final result = widget.packageConverter.convertZipBytes(
        bytes,
        sourceName: _repo.text,
        sourceKind: 'GITHUB',
        sourceRef: _ref.text.trim(),
        appNameOverride: _nullable(_app.text),
      );
      _setSummary(result);
    } catch (error) {
      _messages.add('✗ $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _convert(List<int> bytes, {required String sourceName, required String sourceKind}) async {
    setState(() {
      _busy = true;
      _messages.clear();
      _summary = null;
      _artifacts = const [];
      _tasks = const [];
      _workbenchApps = const [];
    });
    try {
      final result = widget.packageConverter.convertZipBytes(
        bytes,
        sourceName: sourceName,
        sourceKind: sourceKind,
        appNameOverride: _nullable(_app.text),
      );
      _setSummary(result);
    } catch (error) {
      _messages.add('✗ $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setSummary(WmnFrappeAppConversionSummary result, {bool preserveMessages = false}) {
    _summary = result;
    if (!preserveMessages) _messages.clear();
    _messages
      ..add('✓ ${result.manifest.appTitle} (${result.manifest.appName})')
      ..add('${context.wmnT('converted_doctypes')}: ${result.convertedDocTypes}')
      ..add('${context.wmnT('converted_workspaces')}: ${result.convertedWorkspaces}')
      ..add('${context.wmnT('converted_pages')}: ${result.convertedPages}')
      ..add('${context.wmnT('placeholder_dependencies')}: ${result.placeholderDocTypes}')
      ..add('${context.wmnT('porting_tasks')}: ${result.portingTasks}')
      ..addAll(result.messages);
    _artifacts = widget.packageConverter.artifacts(result.manifest.appName);
    _tasks = widget.packageConverter.portingTasks(result.manifest.appName);
    _workbenchApps = [result.manifest.appName];
    _reloadInstalledApps();
    if (mounted) setState(() {});
  }

  Future<void> _importDocTypeJson() async {
    setState(() {
      _busy = true;
      _messages.clear();
    });
    try {
      final files = await widget.fileInteractions.pickFiles(
        filters: const <WmnFileTypeFilter>[
          WmnFileTypeFilter(
            label: 'Frappe DocType JSON',
            extensions: <String>['json'],
            mimeTypes: <String>['application/json'],
            uniformTypeIdentifiers: <String>['public.json'],
          ),
        ],
      );
      var converted = 0;
      for (final file in files) {
        try {
          final text = utf8.decode(file.bytes, allowMalformed: true);
          final result = widget.converter.importDocTypeJson(
            text,
            sourceApp: _nullable(_app.text) ?? 'frappe_app',
          );
          converted++;
          _messages.add('✓ ${result.doctype.name}: ${result.convertedFields} fields');
          _messages.addAll(result.warnings.map((warning) => '  • $warning'));
        } catch (error) {
          _messages.add('✗ ${file.name}: $error');
        }
      }
      if (converted > 0) {
        widget.converter.registerApp(
          appName: _nullable(_app.text) ?? 'frappe_app',
          manifest: {'converted_doctypes': converted},
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.wmnT('frappe_app_import'))),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Text(context.wmnT('frappe_package_help'), style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 14),
            if (_installedApps.isNotEmpty) ...[
              _installedAppsCard(),
              const SizedBox(height: 14),
            ],
            TextField(controller: _app, decoration: InputDecoration(labelText: context.wmnT('app_name_override'), hintText: context.wmnT('optional'))),
            const SizedBox(height: 16),

            if (!_hasImportedFrappeStack)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(context.wmnT('erpnext_v16_stack'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(context.wmnT('erpnext_stack_help')),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _busy ? null : _importErpNextLocalStack,
                          icon: const Icon(Icons.folder_zip_outlined),
                          label: Text(context.wmnT('select_local_erpnext_stack')),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _downloadErpNextV16Stack,
                          icon: const Icon(Icons.layers_outlined),
                          label: Text(context.wmnT('download_erpnext_stack')),
                        ),
                      ],
                    ),
                  ]),
                ),
              ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(context.wmnT('convert_zip_app'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(context.wmnT('convert_zip_help')),
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _importZip,
                      icon: const Icon(Icons.folder_zip_outlined),
                      label: Text(context.wmnT('select_app_zip')),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(context.wmnT('github_app_download'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  TextField(controller: _repo, decoration: InputDecoration(labelText: context.wmnT('github_repository'))),
                  const SizedBox(height: 10),
                  TextField(controller: _ref, decoration: InputDecoration(labelText: context.wmnT('git_ref'))),
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _downloadAndConvert,
                      icon: const Icon(Icons.cloud_download_outlined),
                      label: Text(context.wmnT('download_and_convert')),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            ExpansionTile(
              title: Text(context.wmnT('advanced_single_doctype_import')),
              childrenPadding: const EdgeInsets.only(bottom: 12),
              children: [
                Text(context.wmnT('frappe_import_help')),
                const SizedBox(height: 8),
                OutlinedButton.icon(onPressed: _busy ? null : _importDocTypeJson, icon: const Icon(Icons.extension_outlined), label: Text(context.wmnT('import_doctype_json'))),
              ],
            ),
            if (_busy) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: LinearProgressIndicator()),
            if (_messages.isNotEmpty) ...[
              const SizedBox(height: 16),
              for (final message in _messages) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: SelectableText(message)),
            ],
            if (_summary != null) ...[
              const SizedBox(height: 18),
              _summaryCard(_summary!),
              const SizedBox(height: 10),
              _sourceWorkbenchButtons(),
              const SizedBox(height: 10),
              _artifactList(),
              const SizedBox(height: 10),
              _taskList(),
            ],
            const SizedBox(height: 18),
            Card(child: Padding(padding: const EdgeInsets.all(14), child: Text(context.wmnT('frappe_package_limitations')))),
          ],
        ),
      );


  Widget _installedAppsCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.wmnT('imported_apps'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              for (final app in _installedApps)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.apps_outlined),
                  title: Text('${app['app_title'] ?? app['app_name']}'),
                  subtitle: Text('${app['app_name']} • ${app['app_version'] ?? ''} • ${app['conversion_status']}'),
                  trailing: IconButton(
                    tooltip: context.wmnT('source_porting_workbench'),
                    icon: const Icon(Icons.code),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => WmnSourcePortingWorkbenchPage(
                          appName: '${app['app_name']}',
                          converter: widget.packageConverter,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _sourceWorkbenchButtons() => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final appName in _workbenchApps)
            OutlinedButton.icon(
              icon: const Icon(Icons.code),
              label: Text('${context.wmnT('open_source_porting_workbench')} • $appName'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => WmnSourcePortingWorkbenchPage(
                    appName: appName,
                    converter: widget.packageConverter,
                  ),
                ),
              ),
            ),
        ],
      );

  Widget _summaryCard(WmnFrappeAppConversionSummary summary) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('${context.wmnT('artifacts')}: ${summary.totalArtifacts}')),
              Chip(label: Text('${context.wmnT('converted')}: ${summary.convertedArtifacts}')),
              Chip(label: Text('${context.wmnT('needs_port')}: ${summary.needsPortArtifacts}')),
              Chip(label: Text('${context.wmnT('failed')}: ${summary.failedArtifacts}')),
              Chip(label: Text('${context.wmnT('porting_tasks')}: ${summary.portingTasks}')),
              Chip(label: Text('${context.wmnT('source_units')}: ${summary.sourceUnits}')),
              Chip(label: Text('AUTO: ${summary.autoConvertedSourceUnits}')),
              Chip(label: Text('REVIEW: ${summary.reviewSourceUnits}')),
              Chip(label: Text('Symbols: ${summary.sourceSymbols}')),
            ],
          ),
        ),
      );

  Widget _artifactList() => ExpansionTile(
        title: Text('${context.wmnT('conversion_artifacts')} (${_artifacts.length})'),
        children: [
          for (final row in _artifacts.take(500))
            ListTile(
              dense: true,
              leading: Icon(_artifactIcon('${row['conversion_status']}')),
              title: Text('${row['artifact_type']} • ${row['target_name'] ?? row['source_path']}'),
              subtitle: Text('${row['conversion_status']} • ${row['source_path']}${row['notes'] == null ? '' : '\n${row['notes']}'}'),
            ),
          if (_artifacts.length > 500) ListTile(title: Text(context.wmnT('showing_first_500'))),
        ],
      );

  Widget _taskList() => ExpansionTile(
        title: Text('${context.wmnT('porting_tasks')} (${_tasks.length})'),
        children: [
          for (final row in _tasks.take(500))
            ListTile(
              dense: true,
              leading: const Icon(Icons.build_outlined),
              title: Text('${row['title']}'),
              subtitle: Text('${row['priority']} • ${row['task_type']} • ${row['source_path'] ?? ''}'),
            ),
          if (_tasks.length > 500) ListTile(title: Text(context.wmnT('showing_first_500'))),
        ],
      );

  IconData _artifactIcon(String status) => switch (status) {
        'CONVERTED' => Icons.check_circle_outline,
        'FAILED' => Icons.error_outline,
        'NEEDS_PORT' => Icons.build_circle_outlined,
        _ => Icons.remove_circle_outline,
      };

  String? _nullable(String value) => value.trim().isEmpty ? null : value.trim();
}
