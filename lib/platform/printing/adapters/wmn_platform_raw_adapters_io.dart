import 'dart:io';
import 'dart:typed_data';

import '../wmn_print_adapter.dart';
import '../wmn_print_models.dart';
import 'wmn_windows_raw_spooler.dart';

class _WmnPlatformRawPrintAdapter implements WmnPrintAdapter {
  const _WmnPlatformRawPrintAdapter();

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
  }) async {
    final type = printer.adapterId.toUpperCase();
    switch (type) {
      case 'NETWORK':
        await _network(printer, bytes);
        return;
      case 'SERIAL':
        await _serial(_target(printer), bytes);
        return;
      case 'WINDOWS_RAW':
        await const WmnWindowsRawSpooler().write(_target(printer), bytes);
        return;
      case 'USB':
        if (Platform.isWindows) {
          await const WmnWindowsRawSpooler().write(_target(printer), bytes);
          return;
        }
        throw UnsupportedError(
          'Direct USB printing requires the native mobile USB adapter.',
        );
      case 'BLUETOOTH':
        final serialPort = '${printer.metadata['serial_port'] ?? ''}'.trim();
        if (Platform.isWindows && serialPort.isNotEmpty) {
          await _serial(serialPort, bytes);
          return;
        }
        throw UnsupportedError(
          'Direct Android/iOS Bluetooth GATT is a later native adapter. '
          'Windows Bluetooth serial printing can use metadata.serial_port.',
        );
      default:
        throw UnsupportedError('Unsupported raw printer adapter: $type');
    }
  }

  Future<void> _network(WmnPrinter printer, Uint8List bytes) async {
    var host = _target(printer);
    var port = _int(printer.metadata['port']) ?? 9100;
    if (host.contains(':')) {
      final split = host.lastIndexOf(':');
      final parsed = int.tryParse(host.substring(split + 1));
      if (parsed != null) {
        port = parsed;
        host = host.substring(0, split);
      }
    }
    final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
    try {
      socket.add(bytes);
      await socket.flush();
    } finally {
      await socket.close();
    }
  }

  Future<void> _serial(String portName, Uint8List bytes) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Direct serial printing is currently implemented for Windows only.');
    }
    final normalized = portName.trim().toUpperCase();
    if (!RegExp(r'^COM\d+$').hasMatch(normalized)) {
      throw StateError('A valid Windows COM port is required.');
    }
    final sink = File('\\\\.\\$normalized').openWrite(mode: FileMode.writeOnly);
    try {
      sink.add(bytes);
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  String _target(WmnPrinter printer) {
    final target = (printer.target ?? '').trim();
    if (target.isEmpty) throw StateError('${printer.name} printer target is required.');
    return target;
  }

  int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}');
  }
}

WmnPrintAdapter createWmnPlatformRawPrintAdapter() =>
    const _WmnPlatformRawPrintAdapter();
