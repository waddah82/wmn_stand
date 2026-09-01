import 'dart:convert';
import 'dart:typed_data';

import '../wmn_barcode_service.dart';
import '../wmn_print_models.dart';
import '../wmn_print_renderer.dart';
import '../wmn_print_template_engine.dart';
import '../wmn_report_print_layout.dart';

/// Canonical WMN print renderer.
///
/// Like Frappe, HTML/CSS/UTF-8 is the single print representation. PDF and
/// physical-print backends consume this exact HTML instead of reconstructing
/// the document with a second text/layout engine.
class WmnHtmlPrintRenderer implements WmnPrintRenderer {
  const WmnHtmlPrintRenderer();

  @override
  String get rendererId => 'html';

  @override
  Future<WmnRenderedPrint> render({
    required WmnPrintFormat format,
    required Map<String, Object?> context,
    required WmnPrintTemplateEngine templates,
    required WmnBarcodeService barcodes,
  }) async {
    var body = templates.render(format.templateText, context);
    final reportValue = context['report'];
    final reportLayout = reportValue is Map
        ? WmnReportPrintLayout.fromReport(
            Map<String, Object?>.from(reportValue),
          )
        : null;
    if (reportLayout != null) {
      body = body
          .replaceAll(
            WmnReportPrintLayout.filtersMarker,
            reportLayout.filtersHtml(),
          )
          .replaceAll(
            WmnReportPrintLayout.tableMarker,
            reportLayout.tableHtml(),
          )
          .replaceAll(
            WmnReportPrintLayout.rowCountMarker,
            '${reportLayout.rowCount}',
          );
    }
    body = body.replaceAllMapped(WmnBarcodeService.markerPattern, (match) {
      final marker = barcodes.parseMarker(match);
      if (marker == null || marker.value.trim().isEmpty) return '';
      return barcodes.svg(marker);
    });

    final languageCode = _languageCode(context, format, reportLayout);
    final direction = _isRtlLanguage(languageCode) ? 'rtl' : 'ltr';
    final letterHead = _letterHead(context);
    final dimensions = _pageDimensions(format, reportLayout);
    final html = _canonicalHtml(
      source: body,
      format: format,
      pageWidthMm: dimensions.$1,
      pageHeightMm: dimensions.$2,
      languageCode: languageCode,
      direction: direction,
      letterHead: letterHead,
    );

    final bytes = Uint8List.fromList(utf8.encode(html));
    return WmnRenderedPrint(
      rendererId: rendererId,
      bytes: bytes,
      mimeType: 'text/html; charset=utf-8',
      fileExtension: 'html',
      debugText: html,
    );
  }

  String _languageCode(
    Map<String, Object?> context,
    WmnPrintFormat format,
    WmnReportPrintLayout? report,
  ) {
    final candidates = <Object?>[
      context['print_language'],
      report?.languageCode,
      format.defaultPrintLanguage,
      'en',
    ];
    for (final candidate in candidates) {
      final value = '${candidate ?? ''}'.trim().toLowerCase();
      if (value.isNotEmpty) return value.replaceAll('_', '-');
    }
    return 'en';
  }

  Map<String, Object?>? _letterHead(Map<String, Object?> context) {
    final value = context['letter_head'];
    if (value is! Map) return null;
    return Map<String, Object?>.from(value);
  }

  (double, double) _pageDimensions(
    WmnPrintFormat format,
    WmnReportPrintLayout? report,
  ) {
    var width = format.paperWidthMm;
    var height = format.paperHeightMm;
    final orientation = '${format.metadata['orientation'] ?? ''}'
        .trim()
        .toUpperCase();
    final autoLandscape = _bool(
      format.metadata['auto_landscape'],
      fallback: true,
    );
    final landscape = orientation == 'LANDSCAPE' ||
        (orientation != 'PORTRAIT' &&
            autoLandscape &&
            report != null &&
            report.columns.length >= 7);
    if (landscape && height > width) {
      final oldWidth = width;
      width = height;
      height = oldWidth;
    }
    return (width, height);
  }

  String _canonicalHtml({
    required String source,
    required WmnPrintFormat format,
    required double pageWidthMm,
    required double pageHeightMm,
    required String languageCode,
    required String direction,
    required Map<String, Object?>? letterHead,
  }) {
    final font = _fontStack(format);
    final letterHeadCss = '${letterHead?['css_text'] ?? ''}'.trim();
    final qrSizeMm = _dimensionMm(format.metadata['qr_size_mm'], fallback: 20);
    final barcodeWidthMm = _dimensionMm(format.metadata['barcode_width_mm'], fallback: 55);
    final barcodeHeightMm = _dimensionMm(format.metadata['barcode_height_mm'], fallback: 16);
    final css = '''
@page {
  size: ${pageWidthMm}mm ${pageHeightMm}mm;
  margin: ${format.marginMm}mm;
}
html, body {
  margin: 0;
  padding: 0;
  color: #111827;
  background: #ffffff;
  font-family: $font;
  font-size: 10.5pt;
  line-height: 1.45;
  -webkit-print-color-adjust: exact;
  print-color-adjust: exact;
}
body { direction: $direction; }
*, *::before, *::after { box-sizing: border-box; }
.wmn-print-body { white-space: normal; }
.wmn-print-body.wmn-plain-text { white-space: pre-wrap; }
.wmn-letter-head,
.wmn-letter-footer,
.wmn-report-filters,
.wmn-report-table { white-space: normal; }
.wmn-letter-head { margin: 0 0 12px; }
.wmn-letter-footer { margin: 12px 0 0; }
.wmn-report-filters {
  display: flex;
  flex-wrap: wrap;
  gap: 6px 14px;
  margin: 8px 0 12px;
  font-size: 0.9em;
}
.wmn-report-filter { white-space: nowrap; }
.wmn-report-table {
  width: 100%;
  border-collapse: collapse;
  table-layout: auto;
}
.wmn-report-table th,
.wmn-report-table td {
  border: 1px solid #9ca3af;
  padding: 5px 6px;
  vertical-align: top;
}
.wmn-report-table th {
  font-weight: 700;
  background: #f3f4f6;
}
.wmn-report-table thead { display: table-header-group; }
.wmn-report-table tr { break-inside: avoid; page-break-inside: avoid; }
img, svg { max-width: 100%; }
svg.wmn-qr-code {
  display: inline-block !important;
  width: ${qrSizeMm}mm !important;
  height: ${qrSizeMm}mm !important;
  max-width: ${qrSizeMm}mm !important;
  max-height: ${qrSizeMm}mm !important;
  vertical-align: middle;
}
svg.wmn-barcode-code {
  display: inline-block !important;
  width: ${barcodeWidthMm}mm !important;
  height: ${barcodeHeightMm}mm !important;
  max-width: 100% !important;
  vertical-align: middle;
}
$letterHeadCss
${format.cssText}
''';

    final headerHtml = '${letterHead?['header_html'] ?? ''}'.trim();
    final footerHtml = '${letterHead?['footer_html'] ?? ''}'.trim();
    final header = headerHtml.isEmpty
        ? ''
        : '<header class="wmn-letter-head">$headerHtml</header>';
    final footer = footerHtml.isEmpty
        ? ''
        : '<footer class="wmn-letter-footer">$footerHtml</footer>';

    if (_hasHtmlDocument(source)) {
      var html = source;
      html = _normalizeHtmlTag(html, languageCode, direction);
      html = _ensureHead(html);
      html = _injectIntoHead(
        html,
        '<meta charset="utf-8">\n<style id="wmn-print-style">$css</style>',
      );
      html = _injectIntoBodyStart(html, header);
      html = _injectIntoBodyEnd(html, footer);
      return html;
    }

    return '''<!doctype html>
<html lang="${_attr(languageCode)}" dir="$direction">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<style id="wmn-print-style">$css</style>
</head>
<body>
$header
<main class="wmn-print-body${_containsMarkup(source) ? '' : ' wmn-plain-text'}">$source</main>
$footer
</body>
</html>''';
  }

  String _fontStack(WmnPrintFormat format) {
    final configured = (format.fontFamily ?? '').trim();
    final first = configured.isEmpty ? '' : '"${_cssString(configured)}", ';
    return '$first"Inter", "Noto Sans Arabic", "Noto Sans", '
        '"Segoe UI", Roboto, Arial, sans-serif';
  }


  bool _containsMarkup(String value) =>
      RegExp(r'<\s*[A-Za-z!/][^>]*>', caseSensitive: false).hasMatch(value);

  bool _hasHtmlDocument(String value) =>
      RegExp(r'<\s*html\b', caseSensitive: false).hasMatch(value);

  String _normalizeHtmlTag(
    String source,
    String languageCode,
    String direction,
  ) {
    final pattern = RegExp(r'<html\b([^>]*)>', caseSensitive: false);
    final match = pattern.firstMatch(source);
    if (match == null) return source;
    var attrs = match.group(1) ?? '';
    attrs = attrs.replaceAll(
      RegExp(r'''\s+lang\s*=\s*(["']).*?\1''', caseSensitive: false),
      '',
    );
    attrs = attrs.replaceAll(
      RegExp(r'''\s+dir\s*=\s*(["']).*?\1''', caseSensitive: false),
      '',
    );
    return source.replaceRange(
      match.start,
      match.end,
      '<html$attrs lang="${_attr(languageCode)}" dir="$direction">',
    );
  }

  String _ensureHead(String source) {
    if (RegExp(r'<\s*head\b', caseSensitive: false).hasMatch(source)) {
      return source;
    }
    final htmlOpen = RegExp(r'<html\b[^>]*>', caseSensitive: false)
        .firstMatch(source);
    if (htmlOpen == null) return '<head></head>$source';
    return source.replaceRange(
      htmlOpen.end,
      htmlOpen.end,
      '\n<head></head>',
    );
  }

  String _injectIntoHead(String source, String fragment) {
    final close = RegExp(r'</head\s*>', caseSensitive: false).firstMatch(source);
    if (close == null) return '$fragment\n$source';
    return source.replaceRange(close.start, close.start, '$fragment\n');
  }

  String _injectIntoBodyStart(String source, String fragment) {
    if (fragment.isEmpty) return source;
    final open = RegExp(r'<body\b[^>]*>', caseSensitive: false).firstMatch(source);
    if (open == null) return '$fragment\n$source';
    return source.replaceRange(open.end, open.end, '\n$fragment');
  }

  String _injectIntoBodyEnd(String source, String fragment) {
    if (fragment.isEmpty) return source;
    final close = RegExp(r'</body\s*>', caseSensitive: false).firstMatch(source);
    if (close == null) return '$source\n$fragment';
    return source.replaceRange(close.start, close.start, '$fragment\n');
  }

  bool _isRtlLanguage(String languageCode) {
    final primary = languageCode.toLowerCase().split(RegExp(r'[-_]')).first;
    return const <String>{'ar', 'fa', 'he', 'ur', 'ps', 'sd'}.contains(primary);
  }

  String _attr(String value) =>
      const HtmlEscape(HtmlEscapeMode.attribute).convert(value);

  String _cssString(String value) => value
      .replaceAll('\\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\n', ' ')
      .replaceAll('\r', ' ');

  double _dimensionMm(Object? value, {required double fallback}) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse('${value ?? ''}'.trim());
    if (parsed == null || !parsed.isFinite || parsed <= 0) return fallback;
    return parsed.clamp(6, 120).toDouble();
  }

  bool _bool(Object? value, {required bool fallback}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = '${value ?? ''}'.trim().toLowerCase();
    if (const <String>{'1', 'true', 'yes', 'on'}.contains(text)) return true;
    if (const <String>{'0', 'false', 'no', 'off'}.contains(text)) return false;
    return fallback;
  }
}
