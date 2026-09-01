import 'dart:typed_data';

import '../wmn_print_adapter.dart';
import '../wmn_print_models.dart';

class _WmnPlatformRawPrintAdapterStub implements WmnPrintAdapter {
  const _WmnPlatformRawPrintAdapterStub();

  @override
  String get adapterId => 'RAW';

  @override
  bool supports(WmnPrinter printer) => const <String>{
        'WINDOWS_RAW',
        'NETWORK',
        'SERIAL',
        'USB',
        'BLUETOOTH',
      }.contains(printer.adapterId.toUpperCase());

  @override
  Future<void> send({
    required WmnPrinter printer,
    required Uint8List bytes,
    required String mimeType,
    required String fileName,
  }) {
    return Future<void>.error(
      UnsupportedError('Raw printer adapters require a native WMN platform adapter.'),
    );
  }
}

WmnPrintAdapter createWmnPlatformRawPrintAdapter() =>
    const _WmnPlatformRawPrintAdapterStub();
