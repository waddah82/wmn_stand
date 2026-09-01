import 'dart:typed_data';

abstract interface class PrintingTransport {
  Future<void> sendNetwork(String host, int port, Uint8List bytes);
  Future<void> sendSerial(String portName, Uint8List bytes);
  Future<void> sendWindowsRaw(String printerTarget, Uint8List bytes);
}
