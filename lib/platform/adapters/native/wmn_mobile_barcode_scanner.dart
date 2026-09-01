import 'package:flutter_barcode_scanner_plus/flutter_barcode_scanner_plus.dart';

import '../contracts/wmn_platform_contracts.dart';

/// Android/iOS barcode and QR scanner backed by the native scanner plugin.
class WmnMobileBarcodeScanner implements WmnScannerAdapter {
  const WmnMobileBarcodeScanner();

  @override
  Future<String?> scanBarcode() async {
    final result = await FlutterBarcodeScanner.scanBarcode(
      '#00897B',
      'Cancel',
      true,
      ScanMode.DEFAULT,
    );
    final value = result.trim();
    if (value.isEmpty || value == '-1') return null;
    return value;
  }
}
