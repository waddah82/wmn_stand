import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization/wmn_localization.dart';
import '../../modules/reporting/application/report_builder_service.dart';
import '../../modules/reporting/domain/report_models.dart';

class ReportBuilderView extends StatefulWidget {
  const ReportBuilderView({super.key, required this.service});

  final ReportBuilderService service;

  @override
  State<ReportBuilderView> createState() => _ReportBuilderViewState();
}

class _ReportBuilderViewState extends State<ReportBuilderView> {
  List<WmnReportDefinition> _reports = const [];
  WmnReportDefinition? _selected;
  WmnReportResult? _result;
  String? _error;
  bool _busy = false;
  final Map<String, Object?> _runtimeFilters = <String, Object?>{};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload({String? selectId}) {
    final reports = widget.service.reports();
    WmnReportDefinition? selected;
    final targetId = selectId ?? _selected?.id;
    if (targetId != null) {
      for (final report in reports) {
        if (report.id == targetId) {
          selected = report;
          break;
        }
      }
    }
    selected ??= reports.isEmpty ? null : reports.first;
    setState(() {
      _reports = reports;
      _selected = selected;
      _result = null;
      _error = null;
      _resetRuntimeFilters(selected);
    });
  }

  Future<void> _createOrEdit([WmnReportDefinition? existing]) async {
    final value = await showDialog<_ReportEditorValue>(
      context: context,
      builder: (context) => _ReportEditorDialog(service: widget.service, existing: existing),
    );
    if (value == null || !mounted) return;
    try {
      final saved = widget.service.saveReport(
        id: existing?.id,
        name: value.name,
        sourceKey: value.sourceKey,
        columns: value.columns,
        filters: value.filters,
        sorts: value.sorts,
        limit: value.limit,
      );
      _reload(selectId: saved.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.wmnT('report_saved'))));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _delete() async {
    final report = _selected;
    if (report == null) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(context.wmnT('delete_report')),
            content: Text('${context.wmnT('confirm_delete')}: ${report.name}?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.wmnT('cancel'))),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.wmnT('delete'))),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      widget.service.deleteReport(report.id);
      _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.wmnT('report_deleted'))));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _run() async {
    final report = _selected;
    if (report == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = widget.service.run(report, runtimeFilters: Map<String, Object?>.from(_runtimeFilters));
      if (!mounted) return;
      setState(() => _result = result);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _resetRuntimeFilters(WmnReportDefinition? report) {
    _runtimeFilters.clear();
    if (report == null) return;
    for (final filter in report.filters.where((entry) => entry.userEditable)) {
      _runtimeFilters[filter.key] = filter.value;
    }
  }

  Future<void> _copyCsv() async {
    final result = _result;
    if (result == null) return;
    await Clipboard.setData(ClipboardData(text: widget.service.exportCsv(result)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.wmnT('csv_copied'))));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Row(
            children: [
              SizedBox(width: 280, child: _reportList(context)),
              const VerticalDivider(width: 1),
              Expanded(child: _reportPanel(context)),
            ],
          );
        }
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selected?.id,
                      decoration: InputDecoration(labelText: context.wmnT('saved_reports')),
                      items: _reports
                          .map((report) => DropdownMenuItem(value: report.id, child: Text(report.name)))
                          .toList(growable: false),
                      onChanged: (id) {
                        if (id == null) return;
                        setState(() {
                          _selected = _reports.firstWhere((entry) => entry.id == id);
                          _result = null;
                          _error = null;
                          _resetRuntimeFilters(_selected);
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: context.wmnT('new_report'),
                    onPressed: () => _createOrEdit(),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
            Expanded(child: _reportPanel(context)),
          ],
        );
      },
    );
  }

  Widget _reportList(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _createOrEdit(),
              icon: const Icon(Icons.add_chart),
              label: Text(context.wmnT('new_report')),
            ),
          ),
        ),
        Expanded(
          child: _reports.isEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(context.wmnT('no_saved_reports'))))
              : ListView.builder(
                  itemCount: _reports.length,
                  itemBuilder: (context, index) {
                    final report = _reports[index];
                    return ListTile(
                      selected: _selected?.id == report.id,
                      leading: const Icon(Icons.table_chart_outlined),
                      title: Text(report.name),
                      subtitle: Text(_sourceLabel(context, report.sourceKey)),
                      onTap: () => setState(() {
                        _selected = report;
                        _result = null;
                        _error = null;
                        _resetRuntimeFilters(_selected);
                      }),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _reportPanel(BuildContext context) {
    final report = _selected;
    if (report == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.addchart, size: 56),
              const SizedBox(height: 12),
              Text(context.wmnT('report_builder'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(context.wmnT('report_builder_help'), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _createOrEdit(),
                icon: const Icon(Icons.add),
                label: Text(context.wmnT('new_report')),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(report.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              Chip(label: Text(_sourceLabel(context, report.sourceKey))),
              FilledButton.icon(
                onPressed: _busy ? null : _run,
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow),
                label: Text(context.wmnT('run_report')),
              ),
              OutlinedButton.icon(
                onPressed: () => _createOrEdit(report),
                icon: const Icon(Icons.edit_outlined),
                label: Text(context.wmnT('edit')),
              ),
              OutlinedButton.icon(
                onPressed: _result == null ? null : _copyCsv,
                icon: const Icon(Icons.content_copy_outlined),
                label: Text(context.wmnT('copy_csv')),
              ),
              IconButton(
                tooltip: context.wmnT('delete_report'),
                onPressed: report.isSystem ? null : _delete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
        if (report.filters.any((entry) => entry.userEditable))
          Card(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(context.wmnT('report_filters'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: report.filters
                        .where((entry) => entry.userEditable)
                        .map((filter) => _runtimeFilterWidget(report, filter))
                        .toList(growable: false),
                  ),
                ],
              ),
            ),
          ),
        const Divider(height: 1),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: MaterialBanner(
              content: Text(_error!),
              actions: [TextButton(onPressed: () => setState(() => _error = null), child: Text(context.wmnT('close')))],
            ),
          ),
        if (_result != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                Text('${context.wmnT('report_rows')}: ${_result!.rows.length}'),
                Text('${context.wmnT('report_duration')}: ${_result!.durationMs} ${context.wmnT('milliseconds')}'),
              ],
            ),
          ),
        Expanded(
          child: _result == null
              ? Center(child: Text(context.wmnT('run_report')))
              : _result!.rows.isEmpty
                  ? Center(child: Text(context.wmnT('no_data')))
                  : _ResultTable(result: _result!),
        ),
      ],
    );
  }

  Widget _runtimeFilterWidget(WmnReportDefinition report, WmnReportFilter filter) {
    final fields = widget.service.fieldsFor(report.sourceKey);
    WmnReportField? meta;
    for (final field in fields) {
      if (field.name == filter.field) {
        meta = field;
        break;
      }
    }
    final label = filter.label ?? meta?.label ?? filter.field;
    final type = filter.fieldType.toLowerCase();
    final options = (filter.options ?? '')
        .split(RegExp(r'\r?\n'))
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    if (type == 'check') {
      final raw = _runtimeFilters[filter.key];
      final checked = raw == true || raw == 1 || '$raw'.toLowerCase() == 'true';
      return SizedBox(
        width: 240,
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('$label${filter.required ? ' *' : ''}'),
          value: checked,
          onChanged: (value) => setState(() => _runtimeFilters[filter.key] = value),
        ),
      );
    }
    if (type == 'select' && options.isNotEmpty) {
      final raw = '${_runtimeFilters[filter.key] ?? ''}'.trim();
      final selected = options.contains(raw) ? raw : null;
      return SizedBox(
        width: 240,
        child: DropdownButtonFormField<String>(
          key: ValueKey('${report.id}:${filter.key}:$selected'),
          initialValue: selected,
          decoration: InputDecoration(labelText: '$label${filter.required ? ' *' : ''}'),
          items: options.map((entry) => DropdownMenuItem(value: entry, child: Text(entry))).toList(growable: false),
          onChanged: (value) => _runtimeFilters[filter.key] = value,
        ),
      );
    }
    return SizedBox(
      width: 240,
      child: TextFormField(
        key: ValueKey('${report.id}:${filter.key}:${_runtimeFilters[filter.key] ?? ''}'),
        initialValue: '${_runtimeFilters[filter.key] ?? ''}',
        keyboardType: meta?.isNumeric == true ? const TextInputType.numberWithOptions(decimal: true, signed: true) : null,
        decoration: InputDecoration(labelText: '$label${filter.required ? ' *' : ''}'),
        onChanged: (value) => _runtimeFilters[filter.key] = value,
      ),
    );
  }

  String _sourceLabel(BuildContext context, String sourceKey) {
    final source = widget.service.source(sourceKey);
    final translated = context.wmnT(sourceKey);
    return translated == sourceKey ? source.label : translated;
  }
}

class _ResultTable extends StatefulWidget {
  const _ResultTable({required this.result});
  final WmnReportResult result;

  @override
  State<_ResultTable> createState() => _ResultTableState();
}

class _ResultTableState extends State<_ResultTable> {
  int _rowsPerPage = 20;

  @override
  Widget build(BuildContext context) {
    final rowsPerPage = _rowsPerPage.clamp(1, widget.result.rows.length).toInt();
    final options = <int>{10, 20, 50, 100}.where((value) => value <= widget.result.rows.length).toList();
    if (!options.contains(rowsPerPage)) options.add(rowsPerPage);
    options.sort();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: PaginatedDataTable(
        showCheckboxColumn: false,
        rowsPerPage: rowsPerPage,
        availableRowsPerPage: options,
        onRowsPerPageChanged: (value) {
          if (value != null) setState(() => _rowsPerPage = value);
        },
        columns: widget.result.columns.map((column) => DataColumn(label: Text(column))).toList(growable: false),
        source: _MapDataSource(widget.result),
      ),
    );
  }
}

class _MapDataSource extends DataTableSource {
  _MapDataSource(this.result);
  final WmnReportResult result;

  @override
  DataRow? getRow(int index) {
    if (index < 0 || index >= result.rows.length) return null;
    final row = result.rows[index];
    return DataRow.byIndex(
      index: index,
      cells: result.columns.map((column) => DataCell(SelectableText('${row[column] ?? ''}'))).toList(growable: false),
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => result.rows.length;

  @override
  int get selectedRowCount => 0;
}

class _ReportEditorDialog extends StatefulWidget {
  const _ReportEditorDialog({required this.service, this.existing});

  final ReportBuilderService service;
  final WmnReportDefinition? existing;

  @override
  State<_ReportEditorDialog> createState() => _ReportEditorDialogState();
}

class _ReportEditorDialogState extends State<_ReportEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _limit;
  late String _sourceKey;
  final Map<String, WmnReportAggregate> _columns = <String, WmnReportAggregate>{};
  final List<_FilterDraft> _filters = <_FilterDraft>[];
  String? _sortField;
  bool _sortDescending = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _sourceKey = existing?.sourceKey ?? widget.service.sources.first.key;
    _name = TextEditingController(text: existing?.name ?? '');
    _limit = TextEditingController(text: '${existing?.limit ?? 500}');
    if (existing != null) {
      for (final column in existing.columns) {
        _columns[column.field] = column.aggregate;
      }
      for (final filter in existing.filters) {
        _filters.add(_FilterDraft.fromFilter(filter));
      }
      if (existing.sorts.isNotEmpty) {
        _sortField = existing.sorts.first.field;
        _sortDescending = existing.sorts.first.descending;
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _limit.dispose();
    for (final filter in _filters) {
      filter.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fields = widget.service.fieldsFor(_sourceKey);
    final selectedFieldNames = _columns.keys.toSet();
    if (_sortField != null && !selectedFieldNames.contains(_sortField)) _sortField = null;

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 920,
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.existing == null ? context.wmnT('new_report') : context.wmnT('edit_report'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(controller: _name, decoration: InputDecoration(labelText: context.wmnT('report_name'))),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _sourceKey,
                      decoration: InputDecoration(labelText: context.wmnT('data_source')),
                      items: widget.service.sources
                          .map(
                            (source) => DropdownMenuItem(
                              value: source.key,
                              child: Text(_sourceLabel(context, source)),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null || value == _sourceKey) return;
                        for (final filter in _filters) {
                          filter.dispose();
                        }
                        setState(() {
                          _sourceKey = value;
                          _columns.clear();
                          _filters.clear();
                          _sortField = null;
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    Text(context.wmnT('report_columns'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Container(
                      height: 300,
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ListView.separated(
                        itemCount: fields.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final field = fields[index];
                          final selected = _columns.containsKey(field.name);
                          final aggregate = _columns[field.name] ?? WmnReportAggregate.none;
                          final aggregateOptions = WmnReportAggregate.values.where(
                            (entry) => field.isNumeric || !const {WmnReportAggregate.sum, WmnReportAggregate.average}.contains(entry),
                          );
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: selected,
                                  onChanged: (value) => setState(() {
                                    if (value == true) {
                                      _columns[field.name] = WmnReportAggregate.none;
                                    } else {
                                      _columns.remove(field.name);
                                      if (_sortField == field.name) _sortField = null;
                                    }
                                  }),
                                ),
                                Expanded(
                                  child: Text(
                                    _fieldLabel(context, field),
                                    style: TextStyle(fontWeight: field.isCustom ? FontWeight.w700 : FontWeight.w500),
                                  ),
                                ),
                                if (field.isCustom) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.extension_outlined, size: 18)),
                                SizedBox(
                                  width: 150,
                                  child: DropdownButtonFormField<WmnReportAggregate>(
                                    initialValue: aggregateOptions.contains(aggregate) ? aggregate : WmnReportAggregate.none,
                                    decoration: InputDecoration(labelText: context.wmnT('aggregation'), isDense: true),
                                    items: aggregateOptions
                                        .map((value) => DropdownMenuItem(value: value, child: Text(_aggregateLabel(context, value))))
                                        .toList(growable: false),
                                    onChanged: !selected
                                        ? null
                                        : (value) => setState(() => _columns[field.name] = value ?? WmnReportAggregate.none),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(child: Text(context.wmnT('filters'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                        TextButton.icon(
                          onPressed: fields.isEmpty
                              ? null
                              : () => setState(() => _filters.add(_FilterDraft(field: fields.first.name))),
                          icon: const Icon(Icons.add),
                          label: Text(context.wmnT('add_filter')),
                        ),
                      ],
                    ),
                    for (var index = 0; index < _filters.length; index++) ...[
                      _filterEditor(context, index, fields),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final children = <Widget>[
                          DropdownButtonFormField<String?>(
                            initialValue: _sortField,
                            decoration: InputDecoration(labelText: context.wmnT('sort_by')),
                            items: [
                              DropdownMenuItem<String?>(value: null, child: Text(context.wmnT('none'))),
                              ...fields
                                  .where((field) => _columns.containsKey(field.name))
                                  .map((field) => DropdownMenuItem<String?>(value: field.name, child: Text(_fieldLabel(context, field)))),
                            ],
                            onChanged: (value) => setState(() => _sortField = value),
                          ),
                          DropdownButtonFormField<bool>(
                            initialValue: _sortDescending,
                            decoration: InputDecoration(labelText: context.wmnT('sort_direction')),
                            items: [
                              DropdownMenuItem(value: false, child: Text(context.wmnT('ascending'))),
                              DropdownMenuItem(value: true, child: Text(context.wmnT('descending'))),
                            ],
                            onChanged: _sortField == null ? null : (value) => setState(() => _sortDescending = value ?? false),
                          ),
                          TextField(
                            controller: _limit,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(labelText: context.wmnT('row_limit')),
                          ),
                        ];
                        if (constraints.maxWidth >= 700) {
                          return Row(
                            children: [
                              Expanded(child: children[0]),
                              const SizedBox(width: 10),
                              Expanded(child: children[1]),
                              const SizedBox(width: 10),
                              SizedBox(width: 150, child: children[2]),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            children[0],
                            const SizedBox(height: 10),
                            children[1],
                            const SizedBox(height: 10),
                            children[2],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: Text(context.wmnT('cancel'))),
                  const SizedBox(width: 8),
                  FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_outlined), label: Text(context.wmnT('save'))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterEditor(BuildContext context, int index, List<WmnReportField> fields) {
    final draft = _filters[index];
    if (!fields.any((field) => field.name == draft.field)) draft.field = fields.first.name;
    final noValue = const {WmnReportOperator.isEmpty, WmnReportOperator.isNotEmpty}.contains(draft.operator);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fieldControl = DropdownButtonFormField<String>(
            initialValue: draft.field,
            decoration: InputDecoration(labelText: context.wmnT('field_name'), isDense: true),
            items: fields.map((field) => DropdownMenuItem(value: field.name, child: Text(_fieldLabel(context, field)))).toList(growable: false),
            onChanged: (value) {
              if (value != null) setState(() => draft.field = value);
            },
          );
          final operatorControl = DropdownButtonFormField<WmnReportOperator>(
            initialValue: draft.operator,
            decoration: InputDecoration(labelText: context.wmnT('operator'), isDense: true),
            items: WmnReportOperator.values
                .map((operator) => DropdownMenuItem(value: operator, child: Text(_operatorLabel(context, operator))))
                .toList(growable: false),
            onChanged: (value) => setState(() => draft.operator = value ?? WmnReportOperator.equals),
          );
          final valueControl = TextField(
            controller: draft.value,
            enabled: !noValue,
            decoration: InputDecoration(labelText: context.wmnT('value'), isDense: true),
          );
          final remove = IconButton(
            tooltip: context.wmnT('remove'),
            onPressed: () {
              final removed = _filters.removeAt(index);
              removed.dispose();
              setState(() {});
            },
            icon: const Icon(Icons.remove_circle_outline),
          );
          if (constraints.maxWidth >= 700) {
            return Row(
              children: [
                Expanded(flex: 3, child: fieldControl),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: operatorControl),
                const SizedBox(width: 8),
                Expanded(flex: 3, child: valueControl),
                remove,
              ],
            );
          }
          return Column(
            children: [
              fieldControl,
              const SizedBox(height: 8),
              operatorControl,
              const SizedBox(height: 8),
              valueControl,
              Align(alignment: AlignmentDirectional.centerEnd, child: remove),
            ],
          );
        },
      ),
    );
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.wmnT('name_required'))));
      return;
    }
    if (_columns.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.wmnT('select_columns'))));
      return;
    }
    final limit = int.tryParse(_limit.text.trim()) ?? 500;
    Navigator.pop(
      context,
      _ReportEditorValue(
        name: _name.text.trim(),
        sourceKey: _sourceKey,
        columns: _columns.entries
            .map((entry) => WmnReportColumn(field: entry.key, aggregate: entry.value))
            .toList(growable: false),
        filters: _filters
            .map(
              (draft) => WmnReportFilter(
                field: draft.field,
                operator: draft.operator,
                value: const {WmnReportOperator.isEmpty, WmnReportOperator.isNotEmpty}.contains(draft.operator)
                    ? null
                    : draft.value.text,
              ),
            )
            .toList(growable: false),
        sorts: _sortField == null ? const [] : [WmnReportSort(field: _sortField!, descending: _sortDescending)],
        limit: limit.clamp(1, 5000).toInt(),
      ),
    );
  }

  String _sourceLabel(BuildContext context, WmnReportSource source) {
    final translated = context.wmnT(source.key);
    return translated == source.key ? source.label : translated;
  }

  String _fieldLabel(BuildContext context, WmnReportField field) {
    final translated = context.wmnT(field.name);
    return translated == field.name ? field.label : translated;
  }

  String _aggregateLabel(BuildContext context, WmnReportAggregate value) => switch (value) {
        WmnReportAggregate.none => context.wmnT('none'),
        WmnReportAggregate.count => 'COUNT',
        WmnReportAggregate.sum => 'SUM',
        WmnReportAggregate.average => 'AVG',
        WmnReportAggregate.minimum => 'MIN',
        WmnReportAggregate.maximum => 'MAX',
      };

  String _operatorLabel(BuildContext context, WmnReportOperator value) => switch (value) {
        WmnReportOperator.equals => context.wmnT('equals'),
        WmnReportOperator.notEquals => context.wmnT('not_equals'),
        WmnReportOperator.greaterThan => context.wmnT('greater_than'),
        WmnReportOperator.greaterOrEqual => context.wmnT('greater_or_equal'),
        WmnReportOperator.lessThan => context.wmnT('less_than'),
        WmnReportOperator.lessOrEqual => context.wmnT('less_or_equal'),
        WmnReportOperator.contains => context.wmnT('contains'),
        WmnReportOperator.startsWith => context.wmnT('starts_with'),
        WmnReportOperator.isEmpty => context.wmnT('is_empty'),
        WmnReportOperator.isNotEmpty => context.wmnT('is_not_empty'),
      };
}

class _FilterDraft {
  _FilterDraft({required this.field, this.operator = WmnReportOperator.equals, String value = ''})
      : value = TextEditingController(text: value);

  factory _FilterDraft.fromFilter(WmnReportFilter filter) => _FilterDraft(
        field: filter.field,
        operator: filter.operator,
        value: '${filter.value ?? ''}',
      );

  String field;
  WmnReportOperator operator;
  final TextEditingController value;

  void dispose() => value.dispose();
}

class _ReportEditorValue {
  const _ReportEditorValue({
    required this.name,
    required this.sourceKey,
    required this.columns,
    required this.filters,
    required this.sorts,
    required this.limit,
  });

  final String name;
  final String sourceKey;
  final List<WmnReportColumn> columns;
  final List<WmnReportFilter> filters;
  final List<WmnReportSort> sorts;
  final int limit;
}
