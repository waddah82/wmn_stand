import 'dart:convert';
import 'dart:typed_data';

import '../wmn_barcode_service.dart';
import '../wmn_print_models.dart';
import '../wmn_print_renderer.dart';
import '../wmn_print_template_engine.dart';

class WmnEscPosPrintRenderer implements WmnPrintRenderer {
  const WmnEscPosPrintRenderer();

  @override
  String get rendererId => 'escpos';

  @override
  Future<WmnRenderedPrint> render({
    required WmnPrintFormat format,
    required Map<String, Object?> context,
    required WmnPrintTemplateEngine templates,
    required WmnBarcodeService barcodes,
  }) async {
    final text = templates.render(format.templateText, context);
    final out = BytesBuilder(copy: false)..add(const <int>[0x1b, 0x40]);
    var cursor = 0;
    for (final match in WmnBarcodeService.markerPattern.allMatches(text)) {
      if (match.start > cursor) {
        out.add(utf8.encode(text.substring(cursor, match.start)));
      }
      final marker = barcodes.parseMarker(match);
      if (marker != null && marker.value.isNotEmpty) {
        if (marker.kind == 'QR') {
          _addQr(out, marker.value);
        } else {
          _addCode128(out, marker.value);
        }
      }
      cursor = match.end;
    }
    if (cursor < text.length) out.add(utf8.encode(text.substring(cursor)));
    out.add(const <int>[0x0a, 0x0a, 0x0a, 0x1d, 0x56, 0x00]);
    final bytes = out.takeBytes();
    return WmnRenderedPrint(
      rendererId: rendererId,
      bytes: bytes,
      mimeType: 'application/vnd.wmn.escpos',
      fileExtension: 'bin',
      debugText: text,
    );
  }

  void _addCode128(BytesBuilder out, String value) {
    final data = <int>[0x7b, 0x42, ...utf8.encode(value)];
    if (data.length > 255) throw StateError('ESC/POS Code128 value is too long.');
    out
      ..add(const <int>[0x1d, 0x48, 0x02])
      ..add(const <int>[0x1d, 0x68, 0x50])
      ..add(<int>[0x1d, 0x6b, 0x49, data.length])
      ..add(data)
      ..add(const <int>[0x0a]);
  }

  void _addQr(BytesBuilder out, String value) {
    final data = utf8.encode(value);
    final storeLength = data.length + 3;
    final pL = storeLength & 0xff;
    final pH = (storeLength >> 8) & 0xff;
    out
      ..add(const <int>[0x1d, 0x28, 0x6b, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00])
      ..add(const <int>[0x1d, 0x28, 0x6b, 0x03, 0x00, 0x31, 0x43, 0x06])
      ..add(const <int>[0x1d, 0x28, 0x6b, 0x03, 0x00, 0x31, 0x45, 0x31])
      ..add(<int>[0x1d, 0x28, 0x6b, pL, pH, 0x31, 0x50, 0x30])
      ..add(data)
      ..add(const <int>[0x1d, 0x28, 0x6b, 0x03, 0x00, 0x31, 0x51, 0x30, 0x0a]);
  }
}
