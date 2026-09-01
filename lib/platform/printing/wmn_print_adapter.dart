import 'dart:typed_data';

import 'wmn_print_models.dart';

abstract interface class WmnPrintAdapter {
  String get adapterId;

  bool supports(WmnPrinter printer);

  Future<void> send({
    required WmnPrinter printer,
    required Uint8List bytes,
    required String mimeType,
    required String fileName,
  });
}
