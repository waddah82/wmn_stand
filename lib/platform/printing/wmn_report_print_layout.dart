import 'dart:convert';

class WmnReportPrintColumn {
  const WmnReportPrintColumn({
    required this.key,
    required this.label,
    required this.fieldType,
    this.width,
  });

  final String key;
  final String label;
  final String fieldType;
  final double? width;

  bool get numeric => const <String>{
        'INT',
        'FLOAT',
        'CURRENCY',
        'PERCENT',
        'CHECK',
      }.contains(fieldType.trim().toUpperCase());
}

class WmnReportPrintFilter {
  const WmnReportPrintFilter({required this.key, required this.label, required this.value});

  final String key;
  final String label;
  final Object? value;
}

/// Pure report layout model shared by HTML and PDF renderers.
///
/// It keeps report formatting generic: report-specific business code only
/// supplies columns, rows and filters. The Print Format decides where the
/// structured filter/table blocks are placed through the markers below.
class WmnReportPrintLayout {
  const WmnReportPrintLayout({
    required this.title,
    required this.columns,
    required this.rows,
    required this.filters,
    required this.rowCount,
    required this.languageCode,
  });

  static const String tableMarker = '[[WMN_REPORT_TABLE]]';
  static const String filtersMarker = '[[WMN_REPORT_FILTERS]]';
  static const String rowCountMarker = '[[WMN_REPORT_ROW_COUNT]]';

  final String title;
  final List<WmnReportPrintColumn> columns;
  final List<Map<String, Object?>> rows;
  final List<WmnReportPrintFilter> filters;
  final int rowCount;
  final String languageCode;

  bool get hasTable => columns.isNotEmpty;
  bool get hasFilters => filters.isNotEmpty;

  factory WmnReportPrintLayout.fromReport(Map<String, Object?> report) {
    final rows = _rows(report['rows']);
    final rawLanguageCode = '${report['language_code'] ?? 'en'}'.trim().toLowerCase();
    final languageCode = rawLanguageCode.split(RegExp(r'[-_]')).first;
    final columns = _columns(
      report['columns'],
      report['column_definitions'],
      rows,
      languageCode,
    );
    final filters = _filters(
      report['filters'],
      report['filter_definitions'],
      languageCode,
    );
    final parsedCount = int.tryParse('${report['row_count'] ?? ''}');
    return WmnReportPrintLayout(
      title: '${report['title'] ?? report['name'] ?? ''}'.trim(),
      columns: columns,
      rows: rows,
      filters: filters,
      rowCount: parsedCount ?? rows.length,
      languageCode: languageCode.isEmpty ? 'en' : languageCode,
    );
  }

  List<List<Object?>> tableData() => rows
      .map(
        (row) => columns.map((column) => row[column.key]).toList(growable: false),
      )
      .toList(growable: false);

  String filtersHtml() {
    if (filters.isEmpty) return '';
    final out = StringBuffer('<div class="wmn-report-filters">');
    for (final filter in filters) {
      out
        ..write('<span class="wmn-report-filter"><strong>')
        ..write(_escape(filter.label))
        ..write(':</strong> ')
        ..write(_escape(_text(filter.value)))
        ..write('</span>');
    }
    out.write('</div>');
    return out.toString();
  }

  String tableHtml() {
    if (columns.isEmpty) return '<div class="wmn-report-empty">No columns</div>';
    final out = StringBuffer('<table class="wmn-report-table"><thead><tr>');
    for (final column in columns) {
      out
        ..write('<th>')
        ..write(_escape(column.label))
        ..write('</th>');
    }
    out.write('</tr></thead><tbody>');
    for (final row in rows) {
      out.write('<tr>');
      for (final column in columns) {
        out
          ..write('<td>')
          ..write(_escape(_text(row[column.key])))
          ..write('</td>');
      }
      out.write('</tr>');
    }
    out.write('</tbody></table>');
    return out.toString();
  }

  String debugTableText() {
    final out = StringBuffer();
    out.writeln(columns.map((column) => column.label).join(' | '));
    for (final row in tableData()) {
      out.writeln(row.map(_text).join(' | '));
    }
    return out.toString().trimRight();
  }

  static List<Map<String, Object?>> _rows(Object? raw) {
    if (raw is! Iterable) return const <Map<String, Object?>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item))
        .toList(growable: false);
  }

  static List<WmnReportPrintColumn> _columns(
    Object? rawColumns,
    Object? rawDefinitions,
    List<Map<String, Object?>> rows,
    String languageCode,
  ) {
    final requested = rawColumns is Iterable
        ? rawColumns.map((item) => '$item'.trim()).where((item) => item.isNotEmpty).toList(growable: false)
        : const <String>[];
    final definitions = <String, Map<String, Object?>>{};
    final definitionOrder = <String>[];
    if (rawDefinitions is Iterable) {
      for (final item in rawDefinitions.whereType<Map>()) {
        final map = Map<String, Object?>.from(item);
        final key = '${map['fieldname'] ?? map['field'] ?? map['name'] ?? map['label'] ?? ''}'.trim();
        if (key.isEmpty) continue;
        definitions[key] = map;
        definitionOrder.add(key);
      }
    }
    final keys = requested.isNotEmpty
        ? requested
        : definitionOrder.isNotEmpty
            ? definitionOrder
            : rows.isEmpty
                ? const <String>[]
                : rows.first.keys.toList(growable: false);
    return keys.map((key) {
      final definition = definitions[key] ?? const <String, Object?>{};
      final label = _localizedLabel(definition, key, languageCode);
      final fieldType = '${definition['fieldtype'] ?? definition['type'] ?? 'Data'}'.trim();
      return WmnReportPrintColumn(
        key: key,
        label: label.isEmpty ? key : label,
        fieldType: fieldType.isEmpty ? 'Data' : fieldType,
        width: _double(definition['width']),
      );
    }).toList(growable: false);
  }

  static List<WmnReportPrintFilter> _filters(
    Object? raw,
    Object? rawDefinitions,
    String languageCode,
  ) {
    if (raw is! Map) return const <WmnReportPrintFilter>[];
    final labels = <String, String>{};
    if (rawDefinitions is Iterable) {
      for (final item in rawDefinitions.whereType<Map>()) {
        final map = Map<String, Object?>.from(item);
        final key = '${map['fieldname'] ?? map['field'] ?? map['name'] ?? ''}'.trim();
        final label = _localizedLabel(map, key, languageCode);
        if (key.isNotEmpty && label.isNotEmpty) labels[key] = label;
      }
    }
    return raw.entries
        .where((entry) => _text(entry.value).trim().isNotEmpty)
        .map(
          (entry) => WmnReportPrintFilter(
            key: '${entry.key}',
            label: labels['${entry.key}'] ?? _humanize('${entry.key}'),
            value: entry.value,
          ),
        )
        .toList(growable: false);
  }

  static String _localizedLabel(
    Map<String, Object?> definition,
    String fallback,
    String languageCode,
  ) {
    final language = languageCode.trim().toLowerCase().split(RegExp(r'[-_]')).first;
    if (language.isNotEmpty && language != 'en') {
      final localized = '${definition['label_$language'] ?? ''}'.trim();
      if (localized.isNotEmpty) return localized;
    }
    final label = '${definition['label'] ?? ''}'.trim();
    return label.isEmpty ? fallback : label;
  }

  static String _humanize(String value) {
    final normalized = value.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    if (normalized.isEmpty) return value;
    return normalized
        .split(RegExp(r'\s+'))
        .map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  static String _text(Object? value) {
    if (value == null) return '';
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is String || value is num || value is bool) return '$value';
    return jsonEncode(value);
  }

  static String _escape(String value) => const HtmlEscape(HtmlEscapeMode.element).convert(value);

  static double? _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}');
  }
}
