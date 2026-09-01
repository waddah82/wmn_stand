import '../wmn_barcode_service.dart';
import '../wmn_print_models.dart';
import '../wmn_print_renderer.dart';
import '../wmn_print_template_engine.dart';
import 'wmn_html_pdf_converter.dart';
import 'wmn_html_print_renderer.dart';

/// PDF is a transport/output of the canonical HTML print document.
///
/// No report data, Unicode text, or Arabic/Latin runs are rebuilt here.
class WmnPdfPrintRenderer implements WmnPrintRenderer {
  WmnPdfPrintRenderer({WmnHtmlPdfConverter? converter})
      : converter = converter ?? createWmnHtmlPdfConverter();

  final WmnHtmlPdfConverter converter;

  @override
  String get rendererId => 'pdf';

  @override
  Future<WmnRenderedPrint> render({
    required WmnPrintFormat format,
    required Map<String, Object?> context,
    required WmnPrintTemplateEngine templates,
    required WmnBarcodeService barcodes,
  }) async {
    final html = await const WmnHtmlPrintRenderer().render(
      format: format,
      context: context,
      templates: templates,
      barcodes: barcodes,
    );
    final bytes = await converter.convert(
      html: html.debugText,
      format: format,
    );
    return WmnRenderedPrint(
      rendererId: rendererId,
      bytes: bytes,
      mimeType: 'application/pdf',
      fileExtension: 'pdf',
      debugText: html.debugText,
    );
  }
}
