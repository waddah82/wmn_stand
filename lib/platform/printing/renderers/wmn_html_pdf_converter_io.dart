import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../wmn_print_models.dart';
import 'wmn_html_pdf_converter.dart';

WmnHtmlPdfConverter createWmnHtmlPdfConverter() =>
    const _IoHtmlPdfConverter();

/// Browser-grade HTML-to-PDF conversion used by the unified print engine.
///
/// The print engine never inspects Arabic/Latin content. Android/iOS/macOS use
/// the platform WebView conversion exposed by `printing`; desktop/server use a
/// Chromium-family executable and the same canonical HTML document.
class _IoHtmlPdfConverter implements WmnHtmlPdfConverter {
  const _IoHtmlPdfConverter();

  @override
  Future<Uint8List> convert({
    required String html,
    required WmnPrintFormat format,
  }) async {
    if (html.trim().isEmpty) {
      throw StateError('Canonical print HTML is empty.');
    }

    final generator = format.pdfGenerator.trim().toUpperCase();
    if (generator == 'PLATFORM') {
      final converted = await _platformWebView(html, format);
      if (converted != null) return converted;
      throw UnsupportedError(
        'The platform HTML print renderer is not available on '
        '${Platform.operatingSystem}.',
      );
    }
    if (generator == 'CHROMIUM') {
      return _chromium(html, format);
    }

    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      final converted = await _platformWebView(html, format);
      if (converted != null) return converted;
    }

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return _chromium(html, format);
    }

    final converted = await _platformWebView(html, format);
    if (converted != null) return converted;

    throw UnsupportedError(
      'HTML print conversion is not available on ${Platform.operatingSystem}.',
    );
  }

  Future<Uint8List?> _platformWebView(
    String html,
    WmnPrintFormat format,
  ) async {
    // Android/iOS/macOS provide the HTML renderer through the platform web
    // engine used by the printing plugin. Do not gate this call with the
    // optional capability flag: printing 5.14.x does not advertise it on
    // Android even though its Android implementation provides
    // convertHtml through WebView + PrintDocumentAdapter.
    if (!(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
      return null;
    }

    // The canonical HTML is passed unchanged. The platform web engine owns
    // Unicode, BiDi, Arabic shaping and font fallback. WMN never inspects the
    // document text to choose fonts.
    try {
      // ignore: deprecated_member_use
      final bytes = await Printing.convertHtml(
        html: html,
        format: _pageFormat(html, format),
      ).timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw StateError(
          'Platform HTML-to-PDF conversion timed out after 60 seconds.',
        ),
      );
      if (bytes.length < 4 ||
          String.fromCharCodes(bytes.take(4)) != '%PDF') {
        throw StateError('Platform HTML renderer did not produce a valid PDF.');
      }
      return bytes;
    } catch (error) {
      throw StateError(
        'Platform HTML-to-PDF conversion failed on '
        '${Platform.operatingSystem}: $error',
      );
    }
  }

  Future<Uint8List> _chromium(
    String html,
    WmnPrintFormat format,
  ) async {
    final executable = await _findChromium(format);
    if (executable == null) {
      throw StateError(
        'A Chromium/Edge HTML print renderer was not found. '
        'Install Microsoft Edge/Chromium or configure Print Format metadata '
        'pdf_browser_path. No font/content fallback renderer will be used.',
      );
    }

    final temp = await Directory.systemTemp.createTemp('wmn_html_pdf_');
    try {
      final input = File('${temp.path}${Platform.pathSeparator}print.html');
      final output = File('${temp.path}${Platform.pathSeparator}print.pdf');
      final profile = Directory('${temp.path}${Platform.pathSeparator}profile');
      await profile.create(recursive: true);
      await input.writeAsString(html, flush: true);

      final args = <String>[
        '--headless=new',
        '--disable-gpu',
        '--disable-extensions',
        '--disable-background-networking',
        '--no-pdf-header-footer',
        '--allow-file-access-from-files',
        '--user-data-dir=${profile.path}',
        '--print-to-pdf=${output.path}',
        input.uri.toString(),
      ];
      if (!Platform.isWindows && Platform.environment['USER'] == 'root') {
        args.insert(1, '--no-sandbox');
      }

      final result = await Process.run(executable, args).timeout(
        const Duration(seconds: 45),
        onTimeout: () => throw StateError(
          'Chromium HTML-to-PDF conversion timed out after 45 seconds.',
        ),
      );
      if (result.exitCode != 0 || !await output.exists()) {
        final detail = '${result.stderr}'.trim();
        throw StateError(
          'Chromium HTML-to-PDF conversion failed with exit code '
          '${result.exitCode}${detail.isEmpty ? '' : ': $detail'}',
        );
      }
      final bytes = await output.readAsBytes();
      if (bytes.length < 4 ||
          String.fromCharCodes(bytes.take(4)) != '%PDF') {
        throw StateError('Chromium did not produce a valid PDF file.');
      }
      return Uint8List.fromList(bytes);
    } finally {
      try {
        await temp.delete(recursive: true);
      } catch (_) {}
    }
  }

  PdfPageFormat _pageFormat(String html, WmnPrintFormat format) {
    var width = format.paperWidthMm;
    var height = format.paperHeightMm;
    final match = RegExp(
      r'@page\s*\{[^}]*size\s*:\s*([0-9.]+)mm\s+([0-9.]+)mm',
      caseSensitive: false,
    ).firstMatch(html);
    if (match != null) {
      width = double.tryParse('${match.group(1)}') ?? width;
      height = double.tryParse('${match.group(2)}') ?? height;
    }
    // Canonical HTML owns @page margins. Passing the same margin again to
    // the platform print framework would apply it twice and make Android PDF
    // differ from Chromium/Windows. Only physical page size belongs here.
    return PdfPageFormat(
      width * PdfPageFormat.mm,
      height * PdfPageFormat.mm,
      marginAll: 0,
    );
  }

  Future<String?> _findChromium(WmnPrintFormat format) async {
    final configured = (format.metadata['pdf_browser_path'] ?? '').toString().trim();
    final envConfigured = (Platform.environment['WMN_CHROMIUM_PATH'] ?? '').trim();
    final candidates = <String>[
      if (configured.isNotEmpty) configured,
      if (envConfigured.isNotEmpty) envConfigured,
      ..._wellKnownBrowserPaths(),
    ];
    for (final path in candidates) {
      if (await File(path).exists()) return path;
    }

    final names = Platform.isWindows
        ? const <String>['msedge.exe', 'chrome.exe', 'chromium.exe']
        : Platform.isMacOS
            ? const <String>['chromium', 'google-chrome', 'chrome']
            : const <String>[
                'chromium',
                'chromium-browser',
                'google-chrome',
                'google-chrome-stable',
              ];
    for (final name in names) {
      final resolved = await _resolveFromPath(name);
      if (resolved != null) return resolved;
    }
    return null;
  }

  List<String> _wellKnownBrowserPaths() {
    if (Platform.isWindows) {
      final programFiles = Platform.environment['ProgramFiles'];
      final programFilesX86 = Platform.environment['ProgramFiles(x86)'];
      final localAppData = Platform.environment['LOCALAPPDATA'];
      return <String>[
        if (programFilesX86 != null)
          '$programFilesX86\\Microsoft\\Edge\\Application\\msedge.exe',
        if (programFiles != null)
          '$programFiles\\Microsoft\\Edge\\Application\\msedge.exe',
        if (programFiles != null)
          '$programFiles\\Google\\Chrome\\Application\\chrome.exe',
        if (programFilesX86 != null)
          '$programFilesX86\\Google\\Chrome\\Application\\chrome.exe',
        if (localAppData != null)
          '$localAppData\\Microsoft\\Edge\\Application\\msedge.exe',
        if (localAppData != null)
          '$localAppData\\Google\\Chrome\\Application\\chrome.exe',
      ];
    }
    if (Platform.isMacOS) {
      return const <String>[
        '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
        '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
        '/Applications/Chromium.app/Contents/MacOS/Chromium',
      ];
    }
    return const <String>[
      '/usr/bin/chromium',
      '/usr/bin/chromium-browser',
      '/usr/bin/google-chrome',
      '/usr/bin/google-chrome-stable',
      '/snap/bin/chromium',
    ];
  }

  Future<String?> _resolveFromPath(String executable) async {
    try {
      final lookup = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(lookup, <String>[executable]);
      if (result.exitCode != 0) return null;
      final first = '${result.stdout}'
          .split(RegExp(r'[\r\n]+'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .firstOrNull;
      return first;
    } catch (_) {
      return null;
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
