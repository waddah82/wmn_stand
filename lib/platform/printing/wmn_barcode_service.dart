import 'dart:convert';

import 'package:barcode/barcode.dart';

class WmnBarcodeMarker {
  const WmnBarcodeMarker({required this.kind, required this.value});

  final String kind;
  final String value;
}

/// Barcode/QR utility shared by HTML, PDF and ESC/POS renderers.
///
/// Templates keep device concerns out of metadata by emitting deterministic
/// markers. Renderers convert those markers to their native representation.
class WmnBarcodeService {
  const WmnBarcodeService();

  static final RegExp markerPattern = RegExp(
    r'\[\[WMN:(BARCODE|QR):([A-Za-z0-9_-]+)\]\]',
  );

  String marker(String kind, String value) {
    final normalizedKind = kind.trim().toUpperCase() == 'QR' ? 'QR' : 'BARCODE';
    final payload = base64Url.encode(utf8.encode(value)).replaceAll('=', '');
    return '[[WMN:$normalizedKind:$payload]]';
  }

  WmnBarcodeMarker? parseMarker(Match match) {
    try {
      final kind = '${match.group(1)}';
      final payload = '${match.group(2)}';
      return WmnBarcodeMarker(
        kind: kind,
        value: utf8.decode(base64Url.decode(base64Url.normalize(payload))),
      );
    } catch (_) {
      return null;
    }
  }

  String svg(WmnBarcodeMarker marker, {double width = 220, double height = 72}) {
    final isQr = marker.kind == 'QR';
    final barcode = isQr ? Barcode.qrCode() : Barcode.code128();
    final effectiveWidth = isQr ? height : width;
    final value = barcode.toSvg(
      marker.value,
      width: effectiveWidth,
      height: height,
      drawText: !isQr,
    );
    final cssClass = isQr ? 'wmn-qr-code' : 'wmn-barcode-code';
    return value.replaceFirst('<svg ', '<svg class="$cssClass" ');
  }
}
