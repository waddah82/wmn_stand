import 'wmn_barcode_service.dart';
import 'wmn_print_models.dart';
import 'wmn_print_template_engine.dart';

abstract interface class WmnPrintRenderer {
  String get rendererId;

  Future<WmnRenderedPrint> render({
    required WmnPrintFormat format,
    required Map<String, Object?> context,
    required WmnPrintTemplateEngine templates,
    required WmnBarcodeService barcodes,
  });
}
