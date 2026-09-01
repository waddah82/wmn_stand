import 'dart:io';
import 'dart:typed_data';

import 'printing_transport_contract.dart';

class _IoPrintingTransport implements PrintingTransport {
  @override
  Future<void> sendNetwork(String host, int port, Uint8List bytes) async {
    if (host.trim().isEmpty) throw StateError('Printer network host is required.');
    final socket = await Socket.connect(host.trim(), port, timeout: const Duration(seconds: 5));
    try {
      socket.add(bytes);
      await socket.flush();
    } finally {
      await socket.close();
    }
  }

  @override
  Future<void> sendSerial(String portName, Uint8List bytes) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Direct serial printing is currently implemented for Windows only.');
    }
    final normalized = portName.trim().toUpperCase();
    if (!RegExp(r'^COM\d+$').hasMatch(normalized)) {
      throw StateError('A valid Windows COM port is required.');
    }
    final file = File('\\\\.\\$normalized');
    final sink = file.openWrite(mode: FileMode.writeOnly);
    try {
      sink.add(bytes);
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  @override
  Future<void> sendWindowsRaw(String printerTarget, Uint8List bytes) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows raw printer target is available on Windows only.');
    }
    final target = printerTarget.trim();
    if (target.isEmpty) throw StateError('Windows raw printer target is required.');
    // A shared printer that exposes a writable UNC raw endpoint can be used here.
    // Driver-spooler printing remains a separate platform adapter because it requires Win32 APIs.
    final sink = File(target).openWrite(mode: FileMode.writeOnly);
    try {
      sink.add(bytes);
      await sink.flush();
    } finally {
      await sink.close();
    }
  }
}

PrintingTransport createPrintingTransport() => _IoPrintingTransport();
