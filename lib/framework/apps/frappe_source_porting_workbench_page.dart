import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/localization/wmn_localization.dart';
import 'frappe_app_package_converter.dart';

class WmnSourcePortingWorkbenchPage extends StatefulWidget {
  const WmnSourcePortingWorkbenchPage({
    super.key,
    required this.appName,
    required this.converter,
  });

  final String appName;
  final WmnFrappeAppPackageConverter converter;

  @override
  State<WmnSourcePortingWorkbenchPage> createState() => _WmnSourcePortingWorkbenchPageState();
}

class _WmnSourcePortingWorkbenchPageState extends State<WmnSourcePortingWorkbenchPage> {
  final _search = TextEditingController();
  String _status = 'REVIEW';
  String _language = 'ALL';
  bool _reanalyzing = false;
  late List<Map<String, Object?>> _units;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    _units = widget.converter.sourceUnits(widget.appName);
  }

  int _count(String status) => _units.where((row) => '${row['conversion_status'] ?? ''}' == status).length;

  List<Map<String, Object?>> get _filtered {
    final query = _search.text.trim().toLowerCase();
    return _units.where((row) {
      final status = '${row['conversion_status'] ?? ''}';
      final language = '${row['language'] ?? ''}';
      if (_status != 'ALL' && status != _status) return false;
      if (_language != 'ALL' && language != _language) return false;
      if (query.isEmpty) return true;
      return '${row['source_path'] ?? ''}'.toLowerCase().contains(query) ||
          language.toLowerCase().contains(query) ||
          '${row['conversion_strategy'] ?? ''}'.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: Text('${context.wmnT('source_porting_workbench')} • ${widget.appName}'),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 10),
            child: FilledButton.tonalIcon(
              onPressed: _reanalyzing ? null : _reanalyze,
              icon: _reanalyzing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_fix_high_outlined),
              label: Text(_reanalyzing ? 'Re-analyzing…' : 'Re-analyze'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 360,
                      child: TextField(
                        controller: _search,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          labelText: context.wmnT('search_source_files'),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    DropdownButton<String>(
                      value: _status,
                      items: const [
                        DropdownMenuItem(value: 'ALL', child: Text('ALL')),
                        DropdownMenuItem(value: 'AUTO_CONVERTED', child: Text('AUTO CONVERTED')),
                        DropdownMenuItem(value: 'REVIEW', child: Text('REVIEW')),
                        DropdownMenuItem(value: 'NEEDS_PORT', child: Text('NEEDS PORT')),
                        DropdownMenuItem(value: 'FAILED', child: Text('FAILED')),
                        DropdownMenuItem(value: 'IGNORED', child: Text('IGNORED')),
                      ],
                      onChanged: (value) => setState(() => _status = value ?? 'REVIEW'),
                    ),
                    DropdownButton<String>(
                      value: _language,
                      items: const [
                        DropdownMenuItem(value: 'ALL', child: Text('ALL LANGUAGES')),
                        DropdownMenuItem(value: 'PYTHON', child: Text('PYTHON')),
                        DropdownMenuItem(value: 'JAVASCRIPT', child: Text('JAVASCRIPT')),
                        DropdownMenuItem(value: 'JSON', child: Text('JSON')),
                        DropdownMenuItem(value: 'CSS', child: Text('CSS')),
                      ],
                      onChanged: (value) => setState(() => _language = value ?? 'ALL'),
                    ),
                    Chip(label: Text('${context.wmnT('source_units')}: ${rows.length}/${_units.length}')),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _summaryChip('AUTO', _count('AUTO_CONVERTED'), 'AUTO_CONVERTED'),
                    _summaryChip('REVIEW', _count('REVIEW'), 'REVIEW'),
                    _summaryChip('NEEDS PORT', _count('NEEDS_PORT'), 'NEEDS_PORT'),
                    _summaryChip('FAILED', _count('FAILED'), 'FAILED'),
                    _summaryChip('IGNORED', _count('IGNORED'), 'IGNORED'),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: rows.isEmpty
                ? Center(child: Text(context.wmnT('no_source_units')))
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final confidence = ((row['confidence'] as num?)?.toDouble() ?? 0) * 100;
                      final language = '${row['language'] ?? ''}';
                      return ListTile(
                        leading: Icon(_languageIcon(language)),
                        title: Text('${row['source_path'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${row['conversion_status']} • ${row['conversion_strategy']} • ${confidence.toStringAsFixed(0)}%'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openUnit(row),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, int count, String status) => ActionChip(
        label: Text('$label $count'),
        onPressed: () => setState(() => _status = status),
      );

  IconData _languageIcon(String language) => switch (language) {
        'PYTHON' => Icons.data_object_outlined,
        'JAVASCRIPT' => Icons.javascript,
        'JSON' => Icons.data_object,
        'CSS' => Icons.palette_outlined,
        'SQL' => Icons.storage_outlined,
        _ => Icons.description_outlined,
      };

  Future<void> _reanalyze() async {
    setState(() => _reanalyzing = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final updated = widget.converter.reanalyzeStoredSources(widget.appName);
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Re-analyzed $updated Python/JavaScript source units.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Re-analysis failed: $error')));
    } finally {
      if (mounted) setState(() => _reanalyzing = false);
    }
  }

  Future<void> _openUnit(Map<String, Object?> row) async {
    final id = '${row['id'] ?? ''}';
    final hydrated = widget.converter.sourceUnit(id) ?? row;
    final symbols = widget.converter.sourceSymbols(id);
    final source = '${hydrated['source_code'] ?? ''}';
    final converted = '${hydrated['converted_code'] ?? ''}';
    final diagnostics = _decodeList(hydrated['diagnostics_json']);
    final dependencies = _decodeList(hydrated['dependencies_json']);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              title: Text('${hydrated['source_path'] ?? ''}'),
              bottom: const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: 'Original'),
                  Tab(text: 'Converted'),
                  Tab(text: 'Symbols'),
                  Tab(text: 'Diagnostics'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                _sourcePane(source),
                _sourcePane(converted.isEmpty ? context.wmnT('no_auto_conversion') : converted),
                _symbolsPane(symbols),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('${context.wmnT('conversion_status')}: ${hydrated['conversion_status']}'),
                    Text('${context.wmnT('conversion_strategy')}: ${hydrated['conversion_strategy']}'),
                    Text('${context.wmnT('confidence')}: ${(((hydrated['confidence'] as num?)?.toDouble() ?? 0) * 100).toStringAsFixed(1)}%'),
                    const SizedBox(height: 12),
                    Text(context.wmnT('diagnostics'), style: Theme.of(context).textTheme.titleMedium),
                    for (final item in diagnostics) ListTile(dense: true, leading: const Icon(Icons.warning_amber_outlined), title: Text(item)),
                    const SizedBox(height: 8),
                    Text(context.wmnT('dependencies'), style: Theme.of(context).textTheme.titleMedium),
                    for (final item in dependencies) ListTile(dense: true, leading: const Icon(Icons.account_tree_outlined), title: Text(item)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sourcePane(String source) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          source,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
      );

  Widget _symbolsPane(List<Map<String, Object?>> symbols) => ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: symbols.length,
        itemBuilder: (context, index) {
          final symbol = symbols[index];
          return Card(
            child: ListTile(
              title: Text('${symbol['symbol_type']} • ${symbol['symbol_name']}'),
              subtitle: Text(
                'L${symbol['line_start'] ?? '?'}–${symbol['line_end'] ?? '?'} • ${symbol['conversion_status']} • ${(((symbol['confidence'] as num?)?.toDouble() ?? 0) * 100).toStringAsFixed(0)}%',
              ),
              trailing: symbol['lifecycle_event'] == null ? null : Chip(label: Text('${symbol['lifecycle_event']}')),
            ),
          );
        },
      );

  List<String> _decodeList(Object? value) {
    try {
      final decoded = jsonDecode('${value ?? '[]'}');
      if (decoded is List) return decoded.map((entry) => '$entry').toList(growable: false);
    } catch (_) {}
    return const [];
  }
}
