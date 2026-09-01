import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization/wmn_localization.dart';
import '../../platform/files/wmn_file_adapter.dart';
import '../../platform/files/wmn_file_interaction_service.dart';
import '../meta/meta_service.dart';
import 'data_exchange_models.dart';
import 'data_exchange_service.dart';

class WmnDataExchangePage extends StatefulWidget {
  const WmnDataExchangePage({
    super.key,
    required this.service,
    required this.meta,
    required this.fileInteractions,
  });

  final WmnDataExchangeService service;
  final WmnMetaService meta;
  final WmnFileInteractionService fileInteractions;

  @override
  State<WmnDataExchangePage> createState() => _WmnDataExchangePageState();
}

class _WmnDataExchangePageState extends State<WmnDataExchangePage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String? _doctype;
  WmnImportMode _mode = WmnImportMode.insert;
  WmnDataFormat _format = WmnDataFormat.csv;
  WmnImportPreview? _preview;
  WmnImportResult? _importResult;
  WmnExportResult? _exportResult;
  String? _selectedFileName;
  String? _csvContent;
  List<int>? _xlsxBytes;
  bool _busy = false;
  String? _error;
  final Set<String> _exportFields = {};

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    final types = widget.meta.doctypes().where((dt) => dt.allowImport || dt.allowExport).toList();
    if (types.isNotEmpty) {
      _doctype = types.first.name;
      _resetExportFields();
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _resetExportFields() {
    final dt = _doctype;
    _exportFields.clear();
    if (dt == null) return;
    _exportFields.addAll(widget.service.exportableFields(dt).take(12).map((f) => f.fieldName));
  }

  Future<void> _pickImportFile() async {
    final dt = _doctype;
    if (dt == null) return;
    try {
      const groups = <WmnFileTypeFilter>[
        WmnFileTypeFilter(
          label: 'WMN Data',
          extensions: <String>['csv', 'xlsx'],
          mimeTypes: <String>[
            'text/csv',
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ],
        ),
      ];
      final file = await widget.fileInteractions.pickFile(filters: groups);
      if (file == null) return;
      final name = file.name.toLowerCase();
      final bytes = file.bytes;
      WmnImportPreview preview;
      if (name.endsWith('.xlsx')) {
        preview = widget.service.previewXlsx(dt, bytes);
        _xlsxBytes = bytes;
        _csvContent = null;
      } else {
        final text = utf8.decode(bytes, allowMalformed: true).replaceFirst('\ufeff', '');
        preview = widget.service.previewCsv(dt, text);
        _csvContent = text;
        _xlsxBytes = null;
      }
      if (!mounted) return;
      setState(() {
        _selectedFileName = file.name;
        _preview = preview;
        _importResult = null;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _runImport() async {
    final dt = _doctype;
    if (dt == null || _busy || (_csvContent == null && _xlsxBytes == null)) return;
    setState(() { _busy = true; _error = null; });
    try {
      final result = _csvContent != null
          ? widget.service.importCsv(doctype: dt, content: _csvContent!, mode: _mode, fileName: _selectedFileName)
          : widget.service.importXlsx(doctype: dt, bytes: _xlsxBytes!, mode: _mode, fileName: _selectedFileName);
      if (mounted) setState(() => _importResult = result);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyTemplate() async {
    final dt = _doctype;
    if (dt == null) return;
    final value = widget.service.csvTemplate(dt);
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.wmnT('template_copied'))));
  }

  Future<void> _saveTemplate() async {
    final dt = _doctype;
    if (dt == null) return;
    try {
      final bytes = widget.service.xlsxTemplate(dt);
      final save = await widget.fileInteractions.exportBytes(
        fileName: '${_safe(dt)}_import_template.xlsx',
        bytes: bytes,
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (save.status == WmnFileSaveStatus.unsupported) {
        throw UnsupportedError(save.message ?? 'File export is unavailable on this platform.');
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${context.wmnT('save_file')}: $error')));
    }
  }

  Future<void> _runExport() async {
    final dt = _doctype;
    if (dt == null || _busy || _exportFields.isEmpty) return;
    setState(() { _busy = true; _error = null; });
    try {
      final result = widget.service.export(doctype: dt, format: _format, fields: _exportFields.toList(growable: false));
      if (mounted) setState(() => _exportResult = result);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveExport() async {
    final result = _exportResult;
    if (result == null) return;
    try {
      final save = await widget.fileInteractions.exportBytes(
        fileName: result.fileName,
        bytes: Uint8List.fromList(result.bytes),
        mimeType: result.mimeType,
      );
      if (save.status == WmnFileSaveStatus.unsupported) {
        throw UnsupportedError(save.message ?? 'File export is unavailable on this platform.');
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${context.wmnT('save_file')}: $error')));
    }
  }

  Future<void> _copyExport() async {
    final result = _exportResult;
    if (result == null || _format != WmnDataFormat.csv) return;
    await Clipboard.setData(ClipboardData(text: utf8.decode(result.bytes)));
  }

  @override
  Widget build(BuildContext context) {
    final doctypes = widget.meta.doctypes().where((dt) => dt.allowImport || dt.allowExport).toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.wmnT('data_import_export')),
        bottom: TabBar(controller: _tabs, tabs: [Tab(text: context.wmnT('data_import')), Tab(text: context.wmnT('data_export'))]),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: DropdownButtonFormField<String>(
              initialValue: _doctype,
              decoration: InputDecoration(labelText: context.wmnT('doctype')),
              items: doctypes.map((dt) => DropdownMenuItem(value: dt.name, child: Text('${dt.module} / ${dt.name}'))).toList(growable: false),
              onChanged: (value) => setState(() {
                _doctype = value; _preview = null; _importResult = null; _exportResult = null; _csvContent = null; _xlsxBytes = null; _resetExportFields();
              }),
            ),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          Expanded(child: TabBarView(controller: _tabs, children: [_importTab(), _exportTab()])),
        ],
      ),
    );
  }

  Widget _importTab() {
    final dt = _doctype;
    final enabled = dt != null && widget.meta.doctype(dt)?.allowImport == true;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          SizedBox(width: 240, child: DropdownButtonFormField<WmnImportMode>(
            initialValue: _mode,
            decoration: InputDecoration(labelText: context.wmnT('import_mode')),
            items: [
              DropdownMenuItem(value: WmnImportMode.insert, child: Text(context.wmnT('insert_new'))),
              DropdownMenuItem(value: WmnImportMode.update, child: Text(context.wmnT('update_existing'))),
              DropdownMenuItem(value: WmnImportMode.upsert, child: Text(context.wmnT('upsert'))),
            ],
            onChanged: enabled ? (value) => setState(() => _mode = value ?? _mode) : null,
          )),
          OutlinedButton.icon(onPressed: enabled ? _copyTemplate : null, icon: const Icon(Icons.content_copy), label: Text(context.wmnT('copy_template'))),
          OutlinedButton.icon(onPressed: enabled ? _saveTemplate : null, icon: const Icon(Icons.download_outlined), label: Text(context.wmnT('download_template'))),
          FilledButton.icon(onPressed: enabled ? _pickImportFile : null, icon: const Icon(Icons.upload_file), label: Text(context.wmnT('select_file'))),
        ]),
        if (_selectedFileName != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_selectedFileName!, style: Theme.of(context).textTheme.titleMedium)),
        if (_preview != null) ...[
          const SizedBox(height: 16),
          Text('${context.wmnT('preview')} • ${_preview!.headers.length} ${context.wmnT('fields')}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (_preview!.errors.isNotEmpty) ..._preview!.errors.map((e) => Text(e, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 8),
          SizedBox(height: 260, child: _previewTable(_preview!)),
          const SizedBox(height: 12),
          Align(alignment: AlignmentDirectional.centerStart, child: FilledButton.icon(
            onPressed: _preview!.valid && !_busy ? _runImport : null,
            icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow),
            label: Text(context.wmnT('import_records')),
          )),
        ],
        if (_importResult != null) Card(
          margin: const EdgeInsets.only(top: 16),
          child: Padding(padding: const EdgeInsets.all(16), child: Wrap(spacing: 18, runSpacing: 8, children: [
            Text('${context.wmnT('rows_success')}: ${_importResult!.successCount}'),
            Text('${context.wmnT('rows_failed')}: ${_importResult!.failedCount}'),
            Text('Job: ${_importResult!.jobId}'),
          ])),
        ),
      ],
    );
  }

  Widget _previewTable(WmnImportPreview preview) {
    if (preview.rows.isEmpty) return Center(child: Text(context.wmnT('no_data')));
    final keys = preview.rows.first.keys.toList(growable: false);
    return SingleChildScrollView(scrollDirection: Axis.horizontal, child: SingleChildScrollView(child: DataTable(
      columns: keys.map((k) => DataColumn(label: Text(k))).toList(growable: false),
      rows: preview.rows.take(20).map((row) => DataRow(cells: keys.map((k) => DataCell(Text('${row[k] ?? ''}'))).toList(growable: false))).toList(growable: false),
    )));
  }

  Widget _exportTab() {
    final dt = _doctype;
    final fields = dt == null ? const [] : widget.service.exportableFields(dt);
    final enabled = dt != null && widget.meta.doctype(dt)?.allowExport == true;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(width: 220, child: DropdownButtonFormField<WmnDataFormat>(
            initialValue: _format,
            decoration: InputDecoration(labelText: context.wmnT('file_format')),
            items: WmnDataFormat.values.map((f) => DropdownMenuItem(value: f, child: Text(f.name.toUpperCase()))).toList(growable: false),
            onChanged: (value) => setState(() => _format = value ?? _format),
          )),
          FilledButton.icon(onPressed: enabled && _exportFields.isNotEmpty && !_busy ? _runExport : null, icon: const Icon(Icons.download), label: Text(context.wmnT('export_records'))),
        ]),
        const SizedBox(height: 16),
        Text(context.wmnT('selected_fields'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 4, runSpacing: 4, children: fields.map((field) => FilterChip(
          label: Text(field.label),
          selected: _exportFields.contains(field.fieldName),
          onSelected: (selected) => setState(() => selected ? _exportFields.add(field.fieldName) : _exportFields.remove(field.fieldName)),
        )).toList(growable: false)),
        if (_exportResult != null) Card(
          margin: const EdgeInsets.only(top: 18),
          child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_exportResult!.fileName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            Text('${context.wmnT('report_rows')}: ${_exportResult!.rowCount}'),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(onPressed: _saveExport, icon: const Icon(Icons.save_alt), label: Text(context.wmnT('save_file'))),
              if (_format == WmnDataFormat.csv) OutlinedButton.icon(onPressed: _copyExport, icon: const Icon(Icons.copy), label: Text(context.wmnT('copy_csv'))),
            ]),
          ])),
        ),
      ],
    );
  }

  String _safe(String value) => value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
}
