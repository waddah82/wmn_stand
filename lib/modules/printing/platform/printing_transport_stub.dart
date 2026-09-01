import 'dart:typed_data';

import 'printing_transport_contract.dart';

class _StubPrintingTransport implements PrintingTransport {
  @override
  Future<void> sendNetwork(String host, int port, Uint8List bytes) =>
      Future.error(UnsupportedError('Raw network printing is not available on this platform.'));

  @override
  Future<void> sendSerial(String portName, Uint8List bytes) =>
      Future.error(UnsupportedError('Serial printing is not available on this platform.'));

  @override
  Future<void> sendWindowsRaw(String printerTarget, Uint8List bytes) =>
      Future.error(UnsupportedError('Windows raw printing is not available on this platform.'));
}

PrintingTransport createPrintingTransport() => _StubPrintingTransport();
