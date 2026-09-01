import 'dart:typed_data';

import '../wmn_print_models.dart';
import 'wmn_html_pdf_converter_stub.dart'
    if (dart.library.io) 'wmn_html_pdf_converter_io.dart' as impl;

abstract interface class WmnHtmlPdfConverter {
  Future<Uint8List> convert({
    required String html,
    required WmnPrintFormat format,
  });
}

WmnHtmlPdfConverter createWmnHtmlPdfConverter() =>
    impl.createWmnHtmlPdfConverter();
