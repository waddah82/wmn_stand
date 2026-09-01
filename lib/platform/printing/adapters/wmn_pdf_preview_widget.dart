import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:printing/printing.dart';

/// UI adapter that keeps the third-party Printing package outside the
/// platform-neutral preview dialog and Printing service contracts.
class WmnPdfPreviewWidget extends StatelessWidget {
  const WmnPdfPreviewWidget({
    super.key,
    required this.bytes,
    required this.fileName,
  });

  final Uint8List bytes;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    return PdfPreview(
      build: (_) async => bytes,
      canChangeOrientation: false,
      canChangePageFormat: false,
      canDebug: false,
      allowSharing: true,
      allowPrinting: true,
      pdfFileName: fileName,
    );
  }
}
