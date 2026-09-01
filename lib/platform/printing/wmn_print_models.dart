import 'dart:typed_data';

enum WmnPrintSourceType { document, report }

enum WmnPrintTargetType { document, report, generalReport, platform }

class WmnPrintFormat {
  const WmnPrintFormat({
    required this.id,
    required this.code,
    required this.name,
    required this.targetType,
    required this.rendererId,
    required this.templateText,
    required this.enabled,
    required this.isDefault,
    required this.paperWidthMm,
    required this.paperHeightMm,
    required this.marginMm,
    this.documentType,
    this.reportName,
    this.cssText = '',
    this.letterHeadId,
    this.defaultPrintLanguage,
    this.fontFamily,
    this.pdfGenerator = 'AUTO',
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String code;
  final String name;
  final WmnPrintTargetType targetType;
  final String rendererId;
  final String templateText;
  final bool enabled;
  final bool isDefault;
  final double paperWidthMm;
  final double paperHeightMm;
  final double marginMm;
  final String? documentType;
  final String? reportName;
  final String cssText;
  final String? letterHeadId;
  final String? defaultPrintLanguage;
  final String? fontFamily;
  final String pdfGenerator;
  final Map<String, Object?> metadata;
}

class WmnPrinter {
  const WmnPrinter({
    required this.id,
    required this.name,
    required this.adapterId,
    required this.platform,
    required this.enabled,
    this.target,
    this.capabilities = const <String>[],
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String name;
  final String adapterId;
  final String? target;
  final String platform;
  final bool enabled;
  final List<String> capabilities;
  final Map<String, Object?> metadata;
}

class WmnPrintSettings {
  const WmnPrintSettings({
    required this.id,
    required this.name,
    required this.enabled,
    required this.previewRendererId,
    required this.pdfRendererId,
    required this.paperWidthMm,
    required this.autoPrint,
    required this.cutPaper,
    this.defaultDocumentFormatId,
    this.generalReportFormatId,
    this.defaultPrinterId,
    this.defaultLetterHeadId,
    this.defaultPrintLanguage,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String name;
  final bool enabled;
  final String previewRendererId;
  final String pdfRendererId;
  final int paperWidthMm;
  final bool autoPrint;
  final bool cutPaper;
  final String? defaultDocumentFormatId;
  final String? generalReportFormatId;
  final String? defaultPrinterId;
  final String? defaultLetterHeadId;
  final String? defaultPrintLanguage;
  final Map<String, Object?> metadata;
}

class WmnPrintRequest {
  const WmnPrintRequest({
    required this.sourceType,
    required this.sourceName,
    required this.context,
    this.documentType,
    this.documentName,
    this.reportName,
    this.explicitFormatId,
    this.printerId,
    this.rendererId,
    this.outputFileName,
    this.explicitLetterHeadId,
    this.suppressLetterHead = false,
    this.languageCode,
  });

  final WmnPrintSourceType sourceType;
  final String sourceName;
  final Map<String, Object?> context;
  final String? documentType;
  final String? documentName;
  final String? reportName;
  final String? explicitFormatId;
  final String? printerId;
  final String? rendererId;
  final String? outputFileName;
  final String? explicitLetterHeadId;
  final bool suppressLetterHead;
  final String? languageCode;

  WmnPrintRequest copyWith({
    String? explicitFormatId,
    bool clearExplicitFormatId = false,
    String? printerId,
    String? rendererId,
    String? outputFileName,
    String? explicitLetterHeadId,
    bool clearExplicitLetterHeadId = false,
    bool? suppressLetterHead,
    String? languageCode,
  }) =>
      WmnPrintRequest(
        sourceType: sourceType,
        sourceName: sourceName,
        context: context,
        documentType: documentType,
        documentName: documentName,
        reportName: reportName,
        explicitFormatId: clearExplicitFormatId ? null : (explicitFormatId ?? this.explicitFormatId),
        printerId: printerId ?? this.printerId,
        rendererId: rendererId ?? this.rendererId,
        outputFileName: outputFileName ?? this.outputFileName,
        explicitLetterHeadId: clearExplicitLetterHeadId
            ? null
            : (explicitLetterHeadId ?? this.explicitLetterHeadId),
        suppressLetterHead: suppressLetterHead ?? this.suppressLetterHead,
        languageCode: languageCode ?? this.languageCode,
      );
}

class WmnLetterHead {
  const WmnLetterHead({
    required this.id,
    required this.name,
    required this.headerHtml,
    required this.footerHtml,
    required this.cssText,
    required this.isDefault,
    required this.enabled,
    this.metadata = const <String, Object?>{},
  });

  final String id;
  final String name;
  final String headerHtml;
  final String footerHtml;
  final String cssText;
  final bool isDefault;
  final bool enabled;
  final Map<String, Object?> metadata;

  Map<String, Object?> toContext() => <String, Object?>{
        'id': id,
        'name': name,
        'header_html': headerHtml,
        'footer_html': footerHtml,
        'css_text': cssText,
        'is_default': isDefault,
      };
}

class WmnRenderedPrint {
  const WmnRenderedPrint({
    required this.rendererId,
    required this.bytes,
    required this.mimeType,
    required this.fileExtension,
    required this.debugText,
  });

  final String rendererId;
  final Uint8List bytes;
  final String mimeType;
  final String fileExtension;
  final String debugText;

  bool get isEmpty => bytes.isEmpty;
}

class WmnPrintPreviewResult {
  const WmnPrintPreviewResult({
    required this.request,
    required this.format,
    required this.languageCode,
    required this.rendered,
    this.letterHead,
  });

  final WmnPrintRequest request;
  final WmnPrintFormat format;
  final WmnLetterHead? letterHead;
  final String languageCode;
  final WmnRenderedPrint rendered;
}

class WmnPrintExecutionResult {
  const WmnPrintExecutionResult({
    required this.jobId,
    required this.format,
    required this.rendered,
    required this.outputFileId,
    this.printer,
  });

  final String jobId;
  final WmnPrintFormat format;
  final WmnRenderedPrint rendered;
  final String outputFileId;
  final WmnPrinter? printer;
}

class WmnPrintJob {
  const WmnPrintJob({
    required this.id,
    required this.sourceType,
    required this.documentType,
    required this.documentName,
    required this.connectionType,
    required this.status,
    required this.createdAt,
    required this.byteCount,
    this.printerTarget,
    this.errorMessage,
    this.completedAt,
    this.printFormatId,
    this.printerId,
    this.rendererId,
    this.outputFileId,
    this.mimeType,
  });

  final String id;
  final WmnPrintSourceType sourceType;
  final String documentType;
  final String documentName;
  final String connectionType;
  final String? printerTarget;
  final String status;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? printFormatId;
  final String? printerId;
  final String? rendererId;
  final String? outputFileId;
  final String? mimeType;
  final int byteCount;
}

WmnPrintTargetType wmnPrintTargetTypeFromStorage(Object? value) {
  return switch ('${value ?? ''}'.trim().toUpperCase()) {
    'REPORT' => WmnPrintTargetType.report,
    'GENERAL_REPORT' => WmnPrintTargetType.generalReport,
    'PLATFORM' => WmnPrintTargetType.platform,
    _ => WmnPrintTargetType.document,
  };
}

String wmnPrintTargetTypeToStorage(WmnPrintTargetType value) => switch (value) {
      WmnPrintTargetType.document => 'DOCUMENT',
      WmnPrintTargetType.report => 'REPORT',
      WmnPrintTargetType.generalReport => 'GENERAL_REPORT',
      WmnPrintTargetType.platform => 'PLATFORM',
    };

WmnPrintSourceType wmnPrintSourceTypeFromStorage(Object? value) =>
    '${value ?? ''}'.trim().toUpperCase() == 'REPORT'
        ? WmnPrintSourceType.report
        : WmnPrintSourceType.document;

String wmnPrintSourceTypeToStorage(WmnPrintSourceType value) =>
    value == WmnPrintSourceType.report ? 'REPORT' : 'DOCUMENT';
