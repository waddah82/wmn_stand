import 'package:flutter/material.dart';

import '../../core/database/sql_identifier.dart';
import '../../core/localization/wmn_localization.dart';
import '../../modules/reporting/application/frappe_report_service.dart';
import '../printing/wmn_print_preview_dialog.dart';
import '../printing/wmn_printing_service.dart';
import '../ui/wmn_responsive.dart';

/// Generic native surface for application-owned Frappe-compatible reports.
///
/// Reports open and execute immediately. Runtime filters are rendered from the
/// Report DocType definition using Frappe-style field metadata. Query Reports
/// remain constrained to bound, read-only SQL through [WmnFrappeReportService].
class WmnApplicationReportPage extends StatefulWidget {
  const WmnApplicationReportPage({
    super.key,
    required this.reportName,
    required this.service,
  });

  final String reportName;
  final WmnFrappeReportService service;

  @override
  State<WmnApplicationReportPage> createState() =>
      _WmnApplicationReportPageState();
}

class _WmnApplicationReportPageState extends State<WmnApplicationReportPage> {
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  final Map<String, Object?> _filterValues = <String, Object?>{};
  WmnFrappeReportDefinition? _definition;
  WmnFrappeReportExecution? _result;
  String? _error;
  bool _loadingDefinition = true;
  bool _running = false;
  int _rowsPerPage = 50;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDefinition());
  }

  void _loadDefinition() {
    if (!mounted) return;
    try {
      final definition = widget.service.definition(widget.reportName);
      for (final controller in _controllers.values) {
        controller.dispose();
      }
      _controllers.clear();
      _filterValues.clear();
      if (definition != null) {
        for (final filter in definition.filters) {
          final key = _filterKey(filter);
          if (key == null) continue;
          final value = _normalizedDefault(filter);
          _filterValues[key] = value;
          if (_usesTextController(_fieldType(filter))) {
            _controllers[key] = TextEditingController(text: _filterText(value));
          }
        }
      }
      setState(() {
        _definition = definition;
        _loadingDefinition = false;
        _error = null;
      });
      if (definition != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _run();
        });
      }
    } catch (error) {
      setState(() {
        _definition = null;
        _loadingDefinition = false;
        _error = '$error';
      });
    }
  }

  WmnFrappeReportDefinition? _refreshDefinitionMetadata() {
    final latest = widget.service.definition(widget.reportName);
    if (latest == null) return null;
    final activeKeys = <String>{};
    for (final filter in latest.filters) {
      final key = _filterKey(filter);
      if (key == null) continue;
      activeKeys.add(key);
      if (!_filterValues.containsKey(key)) {
        _filterValues[key] = _normalizedDefault(filter);
      }
      if (_usesTextController(_fieldType(filter))) {
        _controllers.putIfAbsent(
          key,
          () => TextEditingController(text: _filterText(_filterValues[key])),
        );
      } else {
        _controllers.remove(key)?.dispose();
      }
    }
    for (final key in _controllers.keys.where((key) => !activeKeys.contains(key)).toList()) {
      _controllers.remove(key)?.dispose();
    }
    _filterValues.removeWhere((key, _) => !activeKeys.contains(key));
    _definition = latest;
    return latest;
  }

  List<Map<String, Object?>> _mergeCurrentColumnMetadata(
    List<Map<String, Object?>> executionColumns,
    List<Map<String, Object?>> declaredColumns,
  ) {
    if (declaredColumns.isEmpty) {
      return executionColumns.map(Map<String, Object?>.from).toList(growable: false);
    }
    final declared = <String, Map<String, Object?>>{};
    for (final column in declaredColumns) {
      final key = '${column['fieldname'] ?? column['field'] ?? column['name'] ?? ''}'.trim();
      if (key.isNotEmpty) declared[key] = column;
    }
    return executionColumns.map((column) {
      final key = '${column['fieldname'] ?? column['field'] ?? column['name'] ?? ''}'.trim();
      final metadata = declared[key];
      return metadata == null
          ? Map<String, Object?>.from(column)
          : <String, Object?>{...column, ...metadata, 'fieldname': key};
    }).toList(growable: false);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _run() async {
    if (_running) return;
    final latestDefinition = _refreshDefinitionMetadata();
    if (latestDefinition == null) {
      setState(() {
        _definition = null;
        _error = context.wmnT('route_not_found');
      });
      return;
    }
    final validationError = _validateFilters();
    if (validationError != null) {
      setState(() {
        _error = validationError;
        _result = null;
      });
      return;
    }
    setState(() {
      _running = true;
      _error = null;
    });
    // Give Flutter one frame to paint the filter/header state before the
    // bounded synchronous SQLite/report execution path begins.
    await WidgetsBinding.instance.endOfFrame;
    try {
      final result = widget.service.execute(
        widget.reportName,
        filters: _runtimeFilters(),
      );
      if (!mounted) return;
      setState(() => _result = result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _result = null;
        _error = '$error';
      });
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _printResult() async {
    final result = _result;
    if (result == null || _running) return;
    final definition = _refreshDefinitionMetadata();
    if (definition == null) return;
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      final currentColumns = _mergeCurrentColumnMetadata(result.columns, definition.columns);
      final columns = currentColumns
          .map((column) => '${column['fieldname'] ?? column['field'] ?? column['label'] ?? ''}'.trim())
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      final printing = WmnPrintingService(widget.service.database);
      final request = printing.reportRequest(
        reportName: definition.reportName,
        columns: columns,
        columnDefinitions: currentColumns,
        rows: result.rows,
        filters: _runtimeFilters(),
        filterDefinitions: definition.filters,
        languageCode: WmnL10nScope.controllerOf(context).languageCode,
      );
      if (!mounted) return;
      await WmnPrintPreviewDialog.show(
        context,
        printing: printing,
        request: request,
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Map<String, Object?> _runtimeFilters() {
    final result = <String, Object?>{};
    final definition = _definition;
    if (definition == null) return result;
    for (final filter in definition.filters) {
      final key = _filterKey(filter);
      if (key == null || !_filterVisible(filter)) continue;
      final value = _filterValues[key];
      if (value == null) continue;
      if (value is String && value.trim().isEmpty) continue;
      result[key] = value;
    }
    return result;
  }

  String? _validateFilters() {
    final definition = _definition;
    if (definition == null) return null;
    for (final filter in definition.filters) {
      if (!_filterVisible(filter) || !_required(filter)) continue;
      final key = _filterKey(filter);
      if (key == null) continue;
      final value = _filterValues[key];
      if (value == null || (value is String && value.trim().isEmpty)) {
        return '${_label(filter)} ${context.wmnT('required').toLowerCase()}';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingDefinition) {
      return const Center(child: CircularProgressIndicator());
    }
    final definition = _definition;
    if (definition == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error ?? context.wmnT('route_not_found')),
        ),
      );
    }
    final exampleGuide = _exampleGuide(context, definition);
    final visibleFilters = definition.filters.where(_filterVisible).toList(growable: false);
    final pageWidth = MediaQuery.sizeOf(context).width;
    return ListView(
      padding: WmnResponsive.pagePadding(pageWidth),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              definition.reportName,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            Chip(label: Text(definition.reportType)),
            Chip(label: Text(definition.module)),
            OutlinedButton.icon(
              onPressed: _running ? null : _run,
              icon: _running
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(context.wmnT('refresh')),
            ),
            if (_result != null)
              OutlinedButton.icon(
                onPressed: _running ? null : _printResult,
                icon: const Icon(Icons.print_outlined),
                label: Text(context.wmnT('print_preview')),
              ),
          ],
        ),
        if (exampleGuide != null) ...[
          const SizedBox(height: 12),
          exampleGuide,
        ],
        if (visibleFilters.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.filter_alt_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.wmnT('report_filters'),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compactFilters =
                          WmnResponsive.compactPage(constraints.maxWidth);
                      final fieldWidth = compactFilters
                          ? constraints.maxWidth
                          : 280.0;
                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final filter in visibleFilters)
                            SizedBox(
                              width: fieldWidth,
                              child: _filterWidget(filter),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_running && _result == null) ...[
          const SizedBox(height: 24),
          const Center(child: CircularProgressIndicator()),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          SelectableText(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_result != null) ...[
          const SizedBox(height: 18),
          _resultTable(context, _result!),
        ],
      ],
    );
  }

  Widget _filterWidget(Map<String, Object?> filter) {
    final key = _filterKey(filter)!;
    final type = _fieldType(filter);
    final label = _label(filter);
    final required = _required(filter);
    final description = '${filter['description'] ?? ''}'.trim();
    final decoration = InputDecoration(
      labelText: required ? '$label *' : label,
      helperText: description.isEmpty ? null : description,
    );

    if (type == 'Check') {
      return CheckboxListTile(
        key: ValueKey('report-filter:$key'),
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(required ? '$label *' : label),
        value: _bool(_filterValues[key]),
        onChanged: (value) => _setFilterValue(key, value == true ? 1 : 0),
        controlAffinity: ListTileControlAffinity.leading,
      );
    }

    if (type == 'Select') {
      final options = _selectOptions(filter);
      final current = '${_filterValues[key] ?? ''}';
      final normalized = options.contains(current) ? current : null;
      return DropdownButtonFormField<String>(
        key: ValueKey('report-filter:$key'),
        initialValue: normalized,
        decoration: decoration,
        items: options
            .map((entry) => DropdownMenuItem<String>(value: entry, child: Text(entry)))
            .toList(growable: false),
        onChanged: (value) => _setFilterValue(key, value),
      );
    }

    if (type == 'Link' || type == 'Dynamic Link') {
      final target = type == 'Link'
          ? '${filter['options'] ?? ''}'.trim()
          : '${_filterValues['${filter['options'] ?? ''}'.trim()] ?? ''}'.trim();
      return _ReportLinkFilter(
        key: ValueKey('report-filter:$key'),
        label: required ? '$label *' : label,
        initialValue: '${_filterValues[key] ?? ''}',
        targetDoctype: target,
        enabled: target.isNotEmpty,
        optionsBuilder: (query) => _linkOptions(target, query),
        onChanged: (value) => _setFilterValue(key, value),
        onSubmitted: (_) => _run(),
      );
    }

    final controller = _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: _filterText(_filterValues[key])),
    );
    final numeric = const {'Int', 'Float', 'Currency', 'Percent'}.contains(type);
    return TextField(
      key: ValueKey('report-filter:$key'),
      controller: controller,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : TextInputType.text,
      decoration: decoration.copyWith(
        suffixIcon: const {'Date', 'Datetime'}.contains(type)
            ? IconButton(
                onPressed: () => _pickFilterDate(filter, controller),
                icon: const Icon(Icons.calendar_month_outlined),
              )
            : null,
      ),
      onChanged: (value) => _setFilterValue(key, _parseFilterValue(type, value), rebuild: false),
      onSubmitted: (_) => _run(),
    );
  }

  Future<void> _pickFilterDate(
    Map<String, Object?> filter,
    TextEditingController controller,
  ) async {
    final current = DateTime.tryParse(controller.text.trim());
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
      initialDate: current ?? DateTime.now(),
    );
    if (picked == null || !mounted) return;
    final value = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    controller.text = value;
    _setFilterValue(_filterKey(filter)!, value);
  }

  void _setFilterValue(String key, Object? value, {bool rebuild = true}) {
    _filterValues[key] = value;
    if (rebuild && mounted) setState(() {});
  }

  List<String> _linkOptions(String targetDoctype, String query) {
    if (targetDoctype.trim().isEmpty) return const <String>[];
    final metaRows = widget.service.database.db.select(
      '''SELECT table_name,id_field,title_field
         FROM wmn_doctypes
         WHERE name=? AND enabled=1
         LIMIT 1;''',
      <Object?>[targetDoctype.trim()],
    );
    if (metaRows.isEmpty) return const <String>[];
    final row = metaRows.first;
    final table = '${row['table_name'] ?? ''}'.trim();
    final idField = '${row['id_field'] ?? 'id'}'.trim();
    final titleField = '${row['title_field'] ?? ''}'.trim();
    if (table.isEmpty || idField.isEmpty) return const <String>[];
    final qTable = quoteSqlIdentifier(table);
    final qId = quoteSqlIdentifier(idField);
    final search = query.trim();
    final args = <Object?>[];
    String where = '';
    if (search.isNotEmpty) {
      final like = '%$search%';
      if (titleField.isNotEmpty && titleField != idField) {
        where = 'WHERE CAST($qId AS TEXT) LIKE ? OR CAST(${quoteSqlIdentifier(titleField)} AS TEXT) LIKE ?';
        args.addAll(<Object?>[like, like]);
      } else {
        where = 'WHERE CAST($qId AS TEXT) LIKE ?';
        args.add(like);
      }
    }
    final rows = widget.service.database.db.select(
      'SELECT $qId AS value FROM $qTable $where ORDER BY $qId COLLATE NOCASE LIMIT 50;',
      args,
    );
    return rows
        .map((entry) => '${entry['value'] ?? ''}'.trim())
        .where((entry) => entry.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  bool _filterVisible(Map<String, Object?> filter) {
    if (filter['user_editable'] == false || filter['user_editable'] == 0) return false;
    final expression = '${filter['depends_on'] ?? filter['dependsOn'] ?? ''}'.trim();
    if (expression.isEmpty) return true;
    if (!expression.startsWith('eval:')) {
      return _bool(_filterValues[expression]);
    }
    final body = expression.substring(5).trim();
    final equality = RegExp(r'''^doc\.([A-Za-z0-9_]+)\s*(==|!=)\s*['"]([^'"]*)['"]$''').firstMatch(body);
    if (equality != null) {
      final actual = '${_filterValues[equality.group(1)!] ?? ''}';
      final expected = equality.group(3)!;
      return equality.group(2) == '==' ? actual == expected : actual != expected;
    }
    final direct = RegExp(r'^doc\.([A-Za-z0-9_]+)$').firstMatch(body);
    if (direct != null) return _bool(_filterValues[direct.group(1)!]);
    return true;
  }

  String _fieldType(Map<String, Object?> filter) =>
      '${filter['fieldtype'] ?? filter['field_type'] ?? 'Data'}'.trim();

  String _label(Map<String, Object?> filter) =>
      _localizedMetadataLabel(filter, _filterKey(filter) ?? '');

  String _localizedMetadataLabel(
    Map<String, Object?> metadata,
    String fallback,
  ) {
    final languageCode = WmnL10nScope.controllerOf(context)
        .languageCode
        .toLowerCase()
        .split(RegExp(r'[-_]'))
        .first;
    if (languageCode != 'en') {
      final localized = '${metadata['label_$languageCode'] ?? ''}'.trim();
      if (localized.isNotEmpty) return localized;
    }
    final label = '${metadata['label'] ?? ''}'.trim();
    return label.isEmpty ? fallback : label;
  }

  bool _required(Map<String, Object?> filter) =>
      filter['required'] == true ||
      filter['required'] == 1 ||
      filter['reqd'] == true ||
      filter['reqd'] == 1;

  Object? _normalizedDefault(Map<String, Object?> filter) {
    final raw = filter.containsKey('default') ? filter['default'] : filter['value'];
    return _parseFilterValue(_fieldType(filter), raw);
  }

  Object? _parseFilterValue(String type, Object? value) {
    if (value == null) return null;
    if (type == 'Check') return _bool(value) ? 1 : 0;
    final text = '$value'.trim();
    if (text.isEmpty) return '';
    if (type == 'Int') return int.tryParse(text) ?? text;
    if (const {'Float', 'Currency', 'Percent'}.contains(type)) {
      return num.tryParse(text) ?? text;
    }
    return text;
  }

  bool _usesTextController(String type) => !const {
        'Check',
        'Select',
        'Link',
        'Dynamic Link',
      }.contains(type);

  List<String> _selectOptions(Map<String, Object?> filter) {
    final required = _required(filter);
    final values = '${filter['options'] ?? ''}'
        .split(RegExp(r'\r?\n'))
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toSet()
        .toList(growable: true);
    if (!required) values.insert(0, '');
    return values;
  }

  String _filterText(Object? value) => value == null ? '' : '$value';

  bool _bool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return const {'1', 'true', 'yes', 'on', 'checked'}
        .contains('${value ?? ''}'.trim().toLowerCase());
  }

  Widget? _exampleGuide(
    BuildContext context,
    WmnFrappeReportDefinition definition,
  ) {
    if (definition.metadata['tutorial_example'] != true) return null;
    final isArabic = WmnL10nScope.controllerOf(context).languageCode == 'ar';
    final description = '${definition.metadata[isArabic ? 'description_ar' : 'description'] ?? definition.metadata['description'] ?? ''}'.trim();
    final rawSteps = definition.metadata[isArabic ? 'creation_steps_ar' : 'creation_steps'] ?? definition.metadata['creation_steps'];
    final rawNotes = definition.metadata[isArabic ? 'notes_ar' : 'notes'] ?? definition.metadata['notes'];
    final steps = rawSteps is List
        ? rawSteps.map((entry) => '$entry'.trim()).where((entry) => entry.isNotEmpty).toList(growable: false)
        : const <String>[];
    final notes = rawNotes is List
        ? rawNotes.map((entry) => '$entry'.trim()).where((entry) => entry.isNotEmpty).toList(growable: false)
        : const <String>[];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.school_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.wmnT('report_example_guide'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(description),
            ],
            if (steps.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(context.wmnT('how_to_create'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              for (var index = 0; index < steps.length; index++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('${index + 1}. ${steps[index]}'),
                ),
            ],
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final note in notes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('• $note'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resultTable(
    BuildContext context,
    WmnFrappeReportExecution result,
  ) {
    final columns = _columns(result);
    if (columns.isEmpty || result.rows.isEmpty) {
      return Center(child: Text(context.wmnT('no_records')));
    }
    final source = _WmnReportDataSource(
      rows: result.rows,
      columns: columns,
    );
    final availableRows = <int>{20, 50, 100, _rowsPerPage}.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text('${result.rows.length} ${context.wmnT('report_rows')}')),
            Chip(label: Text('${result.durationMs} ms')),
            if (result.message != null && result.message!.trim().isNotEmpty)
              Chip(label: Text(result.message!)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Icon(Icons.table_rows_outlined, size: 20),
            const SizedBox(width: 8),
            Text(
              context.wmnT('report_results'),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: PaginatedDataTable(
            showFirstLastButtons: true,
            showEmptyRows: false,
            rowsPerPage: _rowsPerPage,
            availableRowsPerPage: availableRows,
            onRowsPerPageChanged: (value) {
              if (value == null || value < 1) return;
              setState(() => _rowsPerPage = value);
            },
            columns: [
              for (final column in columns)
                DataColumn(label: Text(column.$2)),
            ],
            source: source,
          ),
        ),
      ],
    );
  }

  List<(String, String)> _columns(WmnFrappeReportExecution result) {
    final columns = <(String, String)>[];
    final currentColumns = _mergeCurrentColumnMetadata(
      result.columns,
      _definition?.columns ?? const <Map<String, Object?>>[],
    );
    for (final column in currentColumns) {
      final field = '${column['fieldname'] ?? column['field'] ?? ''}'.trim();
      final label = _localizedMetadataLabel(column, field);
      if (field.isNotEmpty) columns.add((field, label.isEmpty ? field : label));
    }
    if (columns.isNotEmpty) return columns;
    if (result.rows.isEmpty) return const <(String, String)>[];
    return result.rows.first.keys.map((key) => (key, key)).toList(growable: false);
  }

  String? _filterKey(Map<String, Object?> filter) {
    for (final key in const <String>['fieldname', 'field_name', 'name']) {
      final value = '${filter[key] ?? ''}'.trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }
}

class _ReportLinkFilter extends StatefulWidget {
  const _ReportLinkFilter({
    super.key,
    required this.label,
    required this.initialValue,
    required this.targetDoctype,
    required this.enabled,
    required this.optionsBuilder,
    required this.onChanged,
    required this.onSubmitted,
  });

  final String label;
  final String initialValue;
  final String targetDoctype;
  final bool enabled;
  final List<String> Function(String query) optionsBuilder;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  State<_ReportLinkFilter> createState() => _ReportLinkFilterState();
}

class _ReportLinkFilterState extends State<_ReportLinkFilter> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: _controller,
      focusNode: _focusNode,
      optionsBuilder: (value) {
        if (!widget.enabled) return const Iterable<String>.empty();
        return widget.optionsBuilder(value.text);
      },
      onSelected: (value) {
        _controller.text = value;
        widget.onChanged(value);
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: widget.enabled,
          decoration: InputDecoration(
            labelText: widget.label,
            helperText: widget.enabled
                ? widget.targetDoctype
                : context.wmnT('select_doctype_first'),
            suffixIcon: controller.text.isEmpty
                ? const Icon(Icons.link)
                : IconButton(
                    onPressed: () {
                      controller.clear();
                      widget.onChanged('');
                    },
                    icon: const Icon(Icons.clear),
                  ),
          ),
          onChanged: widget.onChanged,
          onSubmitted: (value) {
            onFieldSubmitted();
            widget.onSubmitted(value);
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final list = options.toList(growable: false);
        if (list.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: AlignmentDirectional.topStart,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 360),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final value = list[index];
                  return ListTile(
                    dense: true,
                    title: Text(value),
                    onTap: () => onSelected(value),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WmnReportDataSource extends DataTableSource {
  _WmnReportDataSource({
    required this.rows,
    required this.columns,
  });

  final List<Map<String, Object?>> rows;
  final List<(String, String)> columns;

  @override
  DataRow? getRow(int index) {
    if (index < 0 || index >= rows.length) return null;
    final row = rows[index];
    return DataRow.byIndex(
      index: index,
      cells: [
        for (final column in columns)
          DataCell(SelectableText('${row[column.$1] ?? ''}')),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => rows.length;

  @override
  int get selectedRowCount => 0;
}
