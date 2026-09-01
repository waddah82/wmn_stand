import 'dart:typed_data';

import 'package:printing/printing.dart';

import '../wmn_print_adapter.dart';
import '../wmn_print_models.dart';

/// Driver-backed system print dialog for PDF output.
class WmnSystemPrintAdapter implements WmnPrintAdapter {
  const WmnSystemPrintAdapter();

  @override
  String get adapterId => 'SYSTEM';

  @override
  bool supports(WmnPrinter printer) =>
      printer.enabled &&
      const <String>{'SYSTEM', 'WEB'}.contains(printer.adapterId.toUpperCase());

  @override
  Future<void> send({
    required WmnPrinter printer,
    required Uint8List bytes,
    required String mimeType,
    required String fileName,
  }) async {
    if (mimeType != 'application/pdf') {
      throw StateError('System print adapter requires PDF output.');
    }
    final printed = await Printing.layoutPdf(
      name: fileName,
      onLayout: (_) async => bytes,
    );
    if (!printed) throw StateError('System print dialog did not complete the print job.');
  }
}
