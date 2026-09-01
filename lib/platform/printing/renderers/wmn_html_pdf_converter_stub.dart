import 'dart:typed_data';

import '../wmn_print_models.dart';
import 'wmn_html_pdf_converter.dart';

WmnHtmlPdfConverter createWmnHtmlPdfConverter() =>
    const _UnsupportedHtmlPdfConverter();

class _UnsupportedHtmlPdfConverter implements WmnHtmlPdfConverter {
  const _UnsupportedHtmlPdfConverter();

  @override
  Future<Uint8List> convert({
    required String html,
    required WmnPrintFormat format,
  }) {
    throw UnsupportedError(
      'This runtime does not provide an HTML-to-PDF backend. '
      'Use browser printing or a WMN Server/Chromium PDF backend.',
    );
  }
}
