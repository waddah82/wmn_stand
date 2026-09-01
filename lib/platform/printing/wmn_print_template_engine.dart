import 'dart:convert';

import 'wmn_barcode_service.dart';

class WmnPrintTemplateEngine {
  const WmnPrintTemplateEngine({this.barcodes = const WmnBarcodeService()});

  final WmnBarcodeService barcodes;

  static const String tokenHelp = '''
WMN Print Template tokens

Values
  {{ field }}                 Current object field
  {{ document.field }}        Document field
  {{ report.title }}          Report metadata
  {{ now }}                   UTC render timestamp

Structured reports
  {{ report.filters_block }}  Runtime filter block
  {{ report.table }}          Structured report table
  {{ report.row_count_block }} Report row count

Child tables / collections
  {{#each items}} ... {{/each}}
  Inside a row use {{ field }} or {{ this.field }}.
  When iterating a Map use {{ key }} and {{ value }}.
  Nested each blocks are supported.

Barcode / QR
  {{ barcode field }}
  {{ qr field }}

Examples
  {{ document.name }}
  {{#each document.items}}{{ item_code }} x {{ qty }}\n{{/each}}
  {{ barcode document.name }}
  {{ qr document.name }}
''';

  String render(
    String template,
    Map<String, Object?> context, {
    DateTime? now,
  }) {
    final root = <String, Object?>{
      ...context,
      'now': (now ?? DateTime.now().toUtc()).toIso8601String(),
    };
    final normalizedTemplate = _normalizeTemplateText(template);
    final expanded = _expandLoops(normalizedTemplate, root, root);
    return _expandTokens(expanded, root, root);
  }

  String _normalizeTemplateText(String value) {
    // Historical/imported templates may contain escaped line breaks as
    // literal text. Normalize the template source only; document/report
    // values are never rewritten.
    return value
        .replaceAll(r'\r\n', '\n')
        .replaceAll(r'\n', '\n');
  }

  String _expandLoops(
    String input,
    Map<String, Object?> root,
    Map<String, Object?> local,
  ) {
    var cursor = 0;
    final out = StringBuffer();
    while (true) {
      final start = input.indexOf('{{#each ', cursor);
      if (start < 0) {
        out.write(input.substring(cursor));
        break;
      }
      out.write(input.substring(cursor, start));
      final headerEnd = input.indexOf('}}', start);
      if (headerEnd < 0) {
        out.write(input.substring(start));
        break;
      }
      final path = input.substring(start + 8, headerEnd).trim();
      final match = _matchingEachEnd(input, headerEnd + 2);
      if (match == null) {
        out.write(input.substring(start));
        break;
      }
      final body = input.substring(headerEnd + 2, match.$1);
      final value = _resolve(path, root, local);
      if (value is Iterable) {
        var index = 0;
        for (final item in value) {
          final child = _childContext(item, index: index++);
          final nested = _expandLoops(body, root, child);
          out.write(_expandTokens(nested, root, child));
        }
      } else if (value is Map) {
        var index = 0;
        for (final entry in value.entries) {
          final child = <String, Object?>{
            'this': entry.value,
            'key': '${entry.key}',
            'value': entry.value,
            'index': index++,
            if (entry.value is Map)
              ...Map<String, Object?>.from(entry.value as Map),
          };
          final nested = _expandLoops(body, root, child);
          out.write(_expandTokens(nested, root, child));
        }
      }
      cursor = match.$2;
    }
    return out.toString();
  }

  (int, int)? _matchingEachEnd(String input, int from) {
    var depth = 1;
    var cursor = from;
    while (cursor < input.length) {
      final nextOpen = input.indexOf('{{#each ', cursor);
      final nextClose = input.indexOf('{{/each}}', cursor);
      if (nextClose < 0) return null;
      if (nextOpen >= 0 && nextOpen < nextClose) {
        depth++;
        cursor = nextOpen + 8;
        continue;
      }
      depth--;
      if (depth == 0) return (nextClose, nextClose + '{{/each}}'.length);
      cursor = nextClose + '{{/each}}'.length;
    }
    return null;
  }

  Map<String, Object?> _childContext(Object? item, {required int index}) {
    if (item is Map) {
      return <String, Object?>{
        'this': item,
        'index': index,
        ...Map<String, Object?>.from(item),
      };
    }
    return <String, Object?>{'this': item, 'value': item, 'index': index};
  }

  String _expandTokens(
    String input,
    Map<String, Object?> root,
    Map<String, Object?> local,
  ) {
    return input.replaceAllMapped(RegExp(r'{{\s*([^{}]+?)\s*}}'), (match) {
      final expression = '${match.group(1)}'.trim();
      if (expression.startsWith('#') || expression.startsWith('/')) {
        return match.group(0)!;
      }
      if (expression.startsWith('barcode ')) {
        final value = _resolve(expression.substring(8).trim(), root, local);
        return barcodes.marker('BARCODE', _stringify(value));
      }
      if (expression.startsWith('qr ')) {
        final value = _resolve(expression.substring(3).trim(), root, local);
        return barcodes.marker('QR', _stringify(value));
      }
      return _stringify(_resolve(expression, root, local));
    });
  }

  Object? _resolve(
    String path,
    Map<String, Object?> root,
    Map<String, Object?> local,
  ) {
    final normalized = path.trim();
    if (normalized.isEmpty) return null;
    if (normalized == 'this') return local['this'] ?? local;
    if (local.containsKey(normalized)) return local[normalized];
    if (root.containsKey(normalized)) return root[normalized];

    final parts = normalized.split('.');
    Object? current;
    final first = parts.first;
    if (local.containsKey(first)) {
      current = local[first];
    } else if (first == 'this') {
      current = local['this'] ?? local;
    } else {
      current = root[first];
    }
    for (final part in parts.skip(1)) {
      if (current is Map) {
        current = current[part];
      } else {
        return null;
      }
    }
    return current;
  }

  String _stringify(Object? value) {
    if (value == null) return '';
    if (value is String || value is num || value is bool) return '$value';
    if (value is DateTime) return value.toUtc().toIso8601String();
    return const JsonEncoder.withIndent('  ').convert(value);
  }
}
