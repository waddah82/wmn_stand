import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../core/database/wmn_database.dart';
import '../../framework/model/document_service.dart';
import '../files/wmn_file_service.dart';
import 'adapters/wmn_platform_raw_adapters.dart';
import 'adapters/wmn_system_print_adapter.dart';
import 'renderers/wmn_escpos_print_renderer.dart';
import 'renderers/wmn_html_print_renderer.dart';
import 'renderers/wmn_pdf_print_renderer.dart';
import 'wmn_barcode_service.dart';
import 'wmn_print_adapter.dart';
import 'wmn_print_models.dart';
import 'wmn_print_renderer.dart';
import 'wmn_print_template_engine.dart';
import 'wmn_report_print_layout.dart';

export 'wmn_print_models.dart' show WmnPrintJob;
export 'wmn_print_renderer.dart' show WmnPrintRenderer;

/// Metadata-driven Printing/PDF engine.
///
/// Print Format, Print Settings, Printer, Print Job and File are the public
/// System DocTypes. Renderers/adapters are runtime implementations selected by
/// renderer_id/Printer metadata. Applications never depend on device details.
class WmnPrintingService {
  WmnPrintingService(
    this.database, {
    WmnFileService? files,
    this.documents,
    this.isFeatureEnabled,
    WmnPrintTemplateEngine? templates,
    WmnBarcodeService? barcodes,
  })  : files = files ?? WmnFileService(database),
        barcodes = barcodes ?? const WmnBarcodeService(),
        templates = templates ?? const WmnPrintTemplateEngine() {
    registerRenderer(const WmnHtmlPrintRenderer());
    registerRenderer(WmnPdfPrintRenderer());
    registerRenderer(const WmnEscPosPrintRenderer());
    registerAdapter(const WmnSystemPrintAdapter());
    registerAdapter(createWmnPlatformRawPrintAdapter());
  }

  final WmnDatabase database;
  final WmnFileService files;
  final WmnDocumentService? documents;
  final bool Function(String featureCode)? isFeatureEnabled;
  final WmnPrintTemplateEngine templates;
  final WmnBarcodeService barcodes;
  static const Uuid _uuid = Uuid();

  final Map<String, WmnPrintRenderer> _renderers = <String, WmnPrintRenderer>{};
  final List<WmnPrintAdapter> _adapters = <WmnPrintAdapter>[];

  List<String> get rendererIds => _renderers.keys.toList(growable: false)..sort();
  List<String> get adapterIds => _adapters.map((item) => item.adapterId).toSet().toList(growable: false)..sort();

  void registerRenderer(WmnPrintRenderer renderer, {bool replace = false}) {
    final id = renderer.rendererId.trim().toLowerCase();
    if (id.isEmpty) throw StateError('Print renderer ID is required.');
    if (!replace && _renderers.containsKey(id)) {
      throw StateError('Print renderer already registered: $id');
    }
    _renderers[id] = renderer;
  }

  void registerAdapter(WmnPrintAdapter adapter, {bool replace = false}) {
    if (replace) _adapters.removeWhere((item) => item.adapterId == adapter.adapterId);
    if (!replace && _adapters.any((item) => item.adapterId == adapter.adapterId)) {
      throw StateError('Print adapter already registered: ${adapter.adapterId}');
    }
    _adapters.add(adapter);
  }

  WmnPrintSettings settings({String name = 'Default'}) {
    final rows = database.db.select(
      'SELECT * FROM print_settings WHERE name=? AND enabled=1 LIMIT 1;',
      [name],
    );
    if (rows.isEmpty) {
      throw StateError('Enabled Print Settings record not found: $name');
    }
    final row = Map<String, Object?>.from(rows.first);
    return WmnPrintSettings(
      id: '${row['id']}',
      name: '${row['name']}',
      enabled: row['enabled'] == 1,
      previewRendererId: '${row['preview_renderer_id'] ?? 'html'}',
      pdfRendererId: '${row['pdf_renderer_id'] ?? 'pdf'}',
      paperWidthMm: _int(row['paper_width_mm']) ?? 80,
      autoPrint: row['auto_print'] == 1,
      cutPaper: row['cut_paper'] == 1,
      defaultDocumentFormatId: _nullable(row['default_document_format_id']),
      generalReportFormatId: _nullable(row['general_report_format_id']),
      defaultPrinterId: _nullable(row['default_printer_id']),
      defaultLetterHeadId: _nullable(row['default_letter_head_id']),
      defaultPrintLanguage: _nullable(row['default_print_language']),
      metadata: _map(row['metadata_json']),
    );
  }

  List<WmnPrintFormat> formats({bool includeDisabled = false}) {
    final rows = database.db.select(
      'SELECT * FROM print_formats ${includeDisabled ? '' : 'WHERE enabled=1'} ORDER BY name COLLATE NOCASE;',
    );
    return rows.map((row) => _format(Map<String, Object?>.from(row))).toList(growable: false);
  }

  List<WmnPrintFormat> formatsForRequest(WmnPrintRequest request) {
    final values = formats().where((format) {
      if (format.targetType == WmnPrintTargetType.platform) return true;
      if (request.sourceType == WmnPrintSourceType.document) {
        return format.targetType == WmnPrintTargetType.document &&
            format.documentType == request.documentType;
      }
      return format.targetType == WmnPrintTargetType.generalReport ||
          (format.targetType == WmnPrintTargetType.report &&
              format.reportName == request.reportName);
    }).toList();
    values.sort((a, b) {
      final target = _previewFormatRank(a, request)
          .compareTo(_previewFormatRank(b, request));
      if (target != 0) return target;
      if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return values;
  }

  List<WmnLetterHead> letterHeads({bool includeDisabled = false}) {
    final rows = database.db.select(
      'SELECT * FROM "tabLetter Head" '
      '${includeDisabled ? '' : 'WHERE disabled=0'} '
      'ORDER BY is_default DESC, name COLLATE NOCASE;',
    );
    return rows
        .map((row) => _letterHead(Map<String, Object?>.from(row)))
        .toList(growable: false);
  }

  WmnLetterHead? letterHead(String idOrName) {
    final value = idOrName.trim();
    if (value.isEmpty) return null;
    final rows = database.db.select(
      'SELECT * FROM "tabLetter Head" '
      'WHERE disabled=0 AND (name=? OR id=?) LIMIT 1;',
      <Object?>[value, value],
    );
    return rows.isEmpty
        ? null
        : _letterHead(Map<String, Object?>.from(rows.first));
  }

  WmnPrintFormat? format(String idOrCode) {
    final value = idOrCode.trim();
    if (value.isEmpty) return null;
    final rows = database.db.select(
      'SELECT * FROM print_formats WHERE (id=? OR code=?) AND enabled=1 LIMIT 1;',
      [value, value],
    );
    return rows.isEmpty ? null : _format(Map<String, Object?>.from(rows.first));
  }

  List<WmnPrinter> printers({bool includeDisabled = false}) {
    final rows = database.db.select(
      'SELECT * FROM wmn_printers ${includeDisabled ? '' : 'WHERE enabled=1'} ORDER BY name COLLATE NOCASE;',
    );
    return rows.map((row) => _printer(Map<String, Object?>.from(row))).toList(growable: false);
  }

  WmnPrinter? printer(String idOrName) {
    final value = idOrName.trim();
    if (value.isEmpty) return null;
    final rows = database.db.select(
      'SELECT * FROM wmn_printers WHERE (id=? OR name=?) AND enabled=1 LIMIT 1;',
      [value, value],
    );
    return rows.isEmpty ? null : _printer(Map<String, Object?>.from(rows.first));
  }

  WmnPrintFormat resolveFormat({
    required WmnPrintSourceType sourceType,
    String? documentType,
    String? reportName,
    String? explicitFormatId,
    String settingsName = 'Default',
  }) {
    final explicit = _nullable(explicitFormatId);
    if (explicit != null) {
      final selected = format(explicit);
      if (selected == null) throw StateError('Explicit Print Format is not enabled or does not exist: $explicit');
      _validateFormatTarget(selected, sourceType, documentType: documentType, reportName: reportName, explicit: true);
      return selected;
    }

    if (sourceType == WmnPrintSourceType.document) {
      final doctype = _required(documentType, 'Document Print request requires documentType.');
      final specific = _firstFormat(
        "target_type='DOCUMENT' AND document_type=?",
        <Object?>[doctype],
      );
      if (specific != null) return specific;
      final defaults = settings(name: settingsName);
      final configured = defaults.defaultDocumentFormatId == null ? null : format(defaults.defaultDocumentFormatId!);
      if (configured != null &&
          (configured.targetType == WmnPrintTargetType.platform ||
              (configured.targetType == WmnPrintTargetType.document && configured.documentType == doctype))) {
        return configured;
      }
      final platform = _firstFormat("target_type='PLATFORM'", const <Object?>[]);
      if (platform != null) return platform;
      throw StateError('No enabled document/platform Print Format is configured.');
    }

    final report = _required(reportName, 'Report Print request requires reportName.');
    final specific = _firstFormat(
      "target_type='REPORT' AND report_name=?",
      <Object?>[report],
    );
    if (specific != null) return specific;
    final defaults = settings(name: settingsName);
    final configured = defaults.generalReportFormatId == null ? null : format(defaults.generalReportFormatId!);
    if (configured != null && configured.targetType == WmnPrintTargetType.generalReport) return configured;
    final general = _firstFormat("target_type='GENERAL_REPORT'", const <Object?>[]);
    if (general != null) return general;
    final platform = _firstFormat("target_type='PLATFORM'", const <Object?>[]);
    if (platform != null) return platform;
    throw StateError('No enabled report/general/platform Print Format is configured.');
  }

  Future<WmnRenderedPrint> render(WmnPrintRequest request) async {
    _assertPrintingEnabled();
    final prepared = _prepare(request);
    return _renderPrepared(prepared);
  }

  Future<WmnPrintPreviewResult> preview(WmnPrintRequest request) async {
    _assertPrintingEnabled();
    final prepared = _prepare(request);
    final rendered = await _renderPrepared(prepared);
    return WmnPrintPreviewResult(
      request: prepared.request,
      format: prepared.format,
      letterHead: prepared.letterHead,
      languageCode: prepared.languageCode,
      rendered: rendered,
    );
  }

  Future<WmnPrintExecutionResult> execute(WmnPrintRequest request) async {
    _assertPrintingEnabled();
    final prepared = _prepare(request);
    final format = prepared.format;
    final rendererId = prepared.rendererId;
    final printerValue =
        _nullable(request.printerId) ?? settings().defaultPrinterId;
    final selectedPrinter =
        printerValue == null ? null : printer(printerValue);
    if (printerValue != null && selectedPrinter == null) {
      throw StateError(
        'Configured Printer is disabled or does not exist: $printerValue',
      );
    }
    if (selectedPrinter != null) _assertPrinterFeature(selectedPrinter);

    final jobId = _queue(
      request,
      format: format,
      rendererId: rendererId,
      printer: selectedPrinter,
    );
    try {
      final rendered = await _renderPrepared(prepared);
      final fileName = _fileName(request, rendered);
      final stored = await files.storeBytesAsync(
        fileName: fileName,
        bytes: rendered.bytes,
        isPrivate: true,
        attachedToDoctype: request.sourceType == WmnPrintSourceType.document
            ? request.documentType
            : 'Report',
        attachedToName: request.sourceType == WmnPrintSourceType.document
            ? request.documentName
            : request.reportName,
        metadata: <String, Object?>{
          'printing_output': true,
          'print_job_id': jobId,
          'print_format_id': format.id,
          'renderer_id': rendered.rendererId,
          'mime_type': rendered.mimeType,
          'letter_head_id': prepared.letterHead?.id,
          'print_language': prepared.languageCode,
        },
      );
      if (selectedPrinter != null) {
        final adapter = _adapters
            .where((item) => item.supports(selectedPrinter))
            .firstOrNull;
        if (adapter == null) {
          throw StateError(
            'No runtime adapter supports Printer ${selectedPrinter.name}.',
          );
        }
        await adapter.send(
          printer: selectedPrinter,
          bytes: rendered.bytes,
          mimeType: rendered.mimeType,
          fileName: fileName,
        );
      }
      _markSent(
        jobId,
        outputFileId: stored.id,
        mimeType: rendered.mimeType,
        byteCount: rendered.bytes.length,
      );
      return WmnPrintExecutionResult(
        jobId: jobId,
        format: format,
        rendered: rendered,
        outputFileId: stored.id,
        printer: selectedPrinter,
      );
    } catch (error) {
      markFailed(jobId, error);
      rethrow;
    }
  }

  WmnPrintRequest documentRequest({
    required String documentType,
    required String documentName,
    Map<String, Object?>? document,
    String? explicitFormatId,
    String? printerId,
    String? rendererId,
    String? explicitLetterHeadId,
    bool suppressLetterHead = false,
    String? languageCode,
  }) {
    final value = document ?? documents?.get(documentType, documentName);
    if (value == null) {
      throw StateError('$documentType $documentName was not found for printing.');
    }
    return WmnPrintRequest(
      sourceType: WmnPrintSourceType.document,
      sourceName: '$documentType/$documentName',
      documentType: documentType,
      documentName: documentName,
      explicitFormatId: explicitFormatId,
      printerId: printerId,
      rendererId: rendererId,
      explicitLetterHeadId: explicitLetterHeadId,
      suppressLetterHead: suppressLetterHead,
      languageCode: languageCode,
      context: <String, Object?>{
        'document': value,
        'doc': value,
        ...value,
      },
    );
  }

  WmnPrintRequest reportRequest({
    required String reportName,
    required List<String> columns,
    required List<Map<String, Object?>> rows,
    List<Map<String, Object?>> columnDefinitions = const <Map<String, Object?>>[],
    Map<String, Object?> filters = const <String, Object?>{},
    List<Map<String, Object?>> filterDefinitions = const <Map<String, Object?>>[],
    String? explicitFormatId,
    String? printerId,
    String? rendererId,
    String languageCode = 'en',
    String? explicitLetterHeadId,
    bool suppressLetterHead = false,
  }) {
    final normalizedLanguage = languageCode.trim().isEmpty
        ? 'en'
        : languageCode.trim().toLowerCase();
    final report = <String, Object?>{
      'name': reportName,
      'title': reportName,
      'columns': columns,
      'column_definitions': columnDefinitions,
      'rows': rows,
      'filters': filters,
      'filter_definitions': filterDefinitions,
      'row_count': rows.length,
      'language_code': normalizedLanguage,
      'table': WmnReportPrintLayout.tableMarker,
      'filters_block': filters.isEmpty ? '' : WmnReportPrintLayout.filtersMarker,
      'row_count_block': WmnReportPrintLayout.rowCountMarker,
    };
    return WmnPrintRequest(
      sourceType: WmnPrintSourceType.report,
      sourceName: reportName,
      reportName: reportName,
      explicitFormatId: explicitFormatId,
      printerId: printerId,
      rendererId: rendererId,
      explicitLetterHeadId: explicitLetterHeadId,
      suppressLetterHead: suppressLetterHead,
      languageCode: normalizedLanguage,
      context: <String, Object?>{'report': report, ...report},
    );
  }

  Future<WmnPrintExecutionResult> executeDocument({
    required String documentType,
    required String documentName,
    Map<String, Object?>? document,
    String? explicitFormatId,
    String? printerId,
    String? rendererId,
    String? explicitLetterHeadId,
    bool suppressLetterHead = false,
    String? languageCode,
  }) =>
      execute(
        documentRequest(
          documentType: documentType,
          documentName: documentName,
          document: document,
          explicitFormatId: explicitFormatId,
          printerId: printerId,
          rendererId: rendererId,
          explicitLetterHeadId: explicitLetterHeadId,
          suppressLetterHead: suppressLetterHead,
          languageCode: languageCode,
        ),
      );

  Future<WmnPrintExecutionResult> executeReport({
    required String reportName,
    required List<String> columns,
    required List<Map<String, Object?>> rows,
    List<Map<String, Object?>> columnDefinitions = const <Map<String, Object?>>[],
    Map<String, Object?> filters = const <String, Object?>{},
    List<Map<String, Object?>> filterDefinitions = const <Map<String, Object?>>[],
    String? explicitFormatId,
    String? printerId,
    String? rendererId,
    String languageCode = 'en',
    String? explicitLetterHeadId,
    bool suppressLetterHead = false,
  }) =>
      execute(
        reportRequest(
          reportName: reportName,
          columns: columns,
          rows: rows,
          columnDefinitions: columnDefinitions,
          filters: filters,
          filterDefinitions: filterDefinitions,
          explicitFormatId: explicitFormatId,
          printerId: printerId,
          rendererId: rendererId,
          languageCode: languageCode,
          explicitLetterHeadId: explicitLetterHeadId,
          suppressLetterHead: suppressLetterHead,
        ),
      );

  /// Backward-compatible metadata API retained for applications compiled on
  /// the R3.15 printing foundation.
  void saveFormat({
    required String code,
    required String name,
    Map<String, Object?> template = const <String, Object?>{},
    String formatType = 'PLATFORM',
    bool enabled = true,
  }) {
    final normalizedCode = code.trim();
    if (normalizedCode.isEmpty) throw StateError('Print format code is required.');
    final existing = database.db.select('SELECT id FROM print_formats WHERE code=? LIMIT 1;', [normalizedCode]);
    final id = existing.isEmpty ? _uuid.v4() : '${existing.first['id']}';
    final now = DateTime.now().toUtc().toIso8601String();
    final templateText = '${template['template_text'] ?? template['html'] ?? template['text'] ?? jsonEncode(template)}'.trim();
    if (templateText.isEmpty) throw StateError('Print format template cannot be empty.');
    database.db.execute('''
      INSERT INTO print_formats(
        id,code,name,format_type,template_json,enabled,created_at,updated_at,
        target_type,renderer_id,template_text
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(code) DO UPDATE SET
        name=excluded.name,format_type=excluded.format_type,template_json=excluded.template_json,
        enabled=excluded.enabled,target_type=excluded.target_type,renderer_id=excluded.renderer_id,
        template_text=excluded.template_text,updated_at=excluded.updated_at;
    ''', [id, normalizedCode, name, formatType, jsonEncode(template), enabled ? 1 : 0, now, now, 'PLATFORM', 'pdf', templateText]);
  }

  /// Legacy queue-only API. New code should use [execute].
  String queueDocument({
    required String documentType,
    required String documentName,
    String connectionType = 'PREVIEW',
    String? printerTarget,
  }) {
    if (documentType.trim().isEmpty || documentName.trim().isEmpty) {
      throw StateError('Document type and document name are required for printing.');
    }
    final id = _uuid.v4();
    database.db.execute('''
      INSERT INTO print_jobs(
        id,document_type,document_name,connection_type,printer_target,status,created_at,source_type,request_json
      ) VALUES (?,?,?,?,?,'PENDING',?,'DOCUMENT','{}');
    ''', [id, documentType, documentName, connectionType, printerTarget, DateTime.now().toUtc().toIso8601String()]);
    return id;
  }

  void markSent(String id) => _markSent(id, byteCount: 0);

  void markFailed(String id, Object error) {
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute(
      "UPDATE print_jobs SET status='FAILED',error_message=?,completed_at=? WHERE id=?;",
      [error.toString(), now, id],
    );
  }

  List<WmnPrintJob> jobs({String? status, int limit = 100}) {
    final rows = status == null
        ? database.db.select('SELECT * FROM print_jobs ORDER BY created_at DESC LIMIT ?;', [limit])
        : database.db.select('SELECT * FROM print_jobs WHERE status=? ORDER BY created_at DESC LIMIT ?;', [status, limit]);
    return rows.map((row) {
      final data = Map<String, Object?>.from(row);
      return WmnPrintJob(
        id: '${data['id']}',
        sourceType: wmnPrintSourceTypeFromStorage(data['source_type']),
        documentType: '${data['document_type']}',
        documentName: '${data['document_name']}',
        connectionType: '${data['connection_type']}',
        printerTarget: data['printer_target'] as String?,
        status: '${data['status']}',
        errorMessage: data['error_message'] as String?,
        createdAt: DateTime.parse('${data['created_at']}'),
        completedAt: data['completed_at'] == null ? null : DateTime.parse('${data['completed_at']}'),
        printFormatId: _nullable(data['print_format_id']),
        printerId: _nullable(data['printer_id']),
        rendererId: _nullable(data['renderer_id']),
        outputFileId: _nullable(data['output_file_id']),
        mimeType: _nullable(data['mime_type']),
        byteCount: _int(data['byte_count']) ?? 0,
      );
    }).toList(growable: false);
  }

  String _queue(
    WmnPrintRequest request, {
    required WmnPrintFormat format,
    required String rendererId,
    required WmnPrinter? printer,
  }) {
    final id = _uuid.v4();
    final sourceType = wmnPrintSourceTypeToStorage(request.sourceType);
    final documentType = request.sourceType == WmnPrintSourceType.document ? request.documentType! : 'Report';
    final documentName = request.sourceType == WmnPrintSourceType.document ? request.documentName! : request.reportName!;
    final connection = printer?.adapterId ?? 'PREVIEW';
    database.db.execute('''
      INSERT INTO print_jobs(
        id,document_type,document_name,connection_type,printer_target,status,created_at,
        source_type,print_format_id,printer_id,renderer_id,request_json
      ) VALUES (?,?,?,?,?,'PENDING',?,?,?,?,?,?);
    ''', [
      id, documentType, documentName, connection, printer?.target,
      DateTime.now().toUtc().toIso8601String(), sourceType, format.id, printer?.id,
      rendererId,
      jsonEncode(<String, Object?>{
        'source_name': request.sourceName,
        'explicit_format_id': request.explicitFormatId,
        'renderer_id': request.rendererId,
        'printer_id': request.printerId,
        'letter_head_id': request.explicitLetterHeadId,
        'suppress_letter_head': request.suppressLetterHead,
        'language_code': request.languageCode,
      }),
    ]);
    return id;
  }

  void _markSent(
    String id, {
    String? outputFileId,
    String? mimeType,
    required int byteCount,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      UPDATE print_jobs
      SET status='SENT',error_message=NULL,completed_at=?,output_file_id=?,mime_type=?,byte_count=?
      WHERE id=?;
    ''', [now, outputFileId, mimeType, byteCount, id]);
  }

  WmnPrintFormat? _firstFormat(String where, List<Object?> args) {
    final rows = database.db.select('''
      SELECT * FROM print_formats
      WHERE enabled=1 AND $where
      ORDER BY is_default DESC, updated_at DESC, name COLLATE NOCASE
      LIMIT 1;
    ''', args);
    return rows.isEmpty ? null : _format(Map<String, Object?>.from(rows.first));
  }

  WmnPrintFormat _format(Map<String, Object?> row) => WmnPrintFormat(
        id: '${row['id']}',
        code: '${row['code']}',
        name: '${row['name']}',
        targetType: wmnPrintTargetTypeFromStorage(row['target_type']),
        documentType: _nullable(row['document_type']),
        reportName: _nullable(row['report_name']),
        rendererId: '${row['renderer_id'] ?? 'pdf'}'.trim().toLowerCase(),
        templateText: '${row['template_text'] ?? ''}',
        cssText: '${row['css_text'] ?? ''}',
        letterHeadId: _nullable(row['letter_head_id']),
        defaultPrintLanguage: _nullable(row['default_print_language']),
        fontFamily: _nullable(row['font_family']),
        pdfGenerator: '${row['pdf_generator'] ?? 'AUTO'}'.trim().toUpperCase(),
        enabled: row['enabled'] == 1,
        isDefault: row['is_default'] == 1,
        paperWidthMm: _double(row['paper_width_mm']) ?? 210,
        paperHeightMm: _double(row['paper_height_mm']) ?? 297,
        marginMm: _double(row['margin_mm']) ?? 10,
        metadata: _map(row['metadata_json']),
      );

  WmnPrinter _printer(Map<String, Object?> row) => WmnPrinter(
        id: '${row['id']}',
        name: '${row['name']}',
        adapterId: '${row['connection_type'] ?? 'SYSTEM'}'.trim().toUpperCase(),
        target: _nullable(row['target']),
        platform: '${row['platform'] ?? 'ANY'}'.trim().toUpperCase(),
        enabled: row['enabled'] == 1,
        capabilities: _list(row['capabilities_json']),
        metadata: _map(row['metadata_json']),
      );

  WmnLetterHead _letterHead(Map<String, Object?> row) => WmnLetterHead(
        id: '${row['id'] ?? row['name']}',
        name: '${row['name']}',
        headerHtml: '${row['header_html'] ?? ''}',
        footerHtml: '${row['footer_html'] ?? ''}',
        cssText: '${row['css_text'] ?? ''}',
        isDefault: row['is_default'] == 1,
        enabled: row['disabled'] != 1,
        metadata: _map(row['metadata_json']),
      );

  _PreparedPrint _prepare(WmnPrintRequest request) {
    final format = resolveFormat(
      sourceType: request.sourceType,
      documentType: request.documentType,
      reportName: request.reportName,
      explicitFormatId: request.explicitFormatId,
    );
    final rendererId = (request.rendererId ?? format.rendererId)
        .trim()
        .toLowerCase();
    _assertRendererFeature(rendererId, format: format);
    final languageCode = _resolveLanguage(request, format);
    final head = _resolveLetterHead(request, format);
    final context = _printContext(
      request.context,
      languageCode: languageCode,
      letterHead: head,
    );
    return _PreparedPrint(
      request: request,
      format: format,
      rendererId: rendererId,
      languageCode: languageCode,
      letterHead: head,
      context: context,
    );
  }

  Future<WmnRenderedPrint> _renderPrepared(_PreparedPrint prepared) async {
    final renderer = _renderers[prepared.rendererId];
    if (renderer == null) {
      throw StateError(
        'Print renderer is not registered: ${prepared.rendererId}',
      );
    }
    final rendered = await renderer.render(
      format: prepared.format,
      context: prepared.context,
      templates: templates,
      barcodes: barcodes,
    );
    if (rendered.bytes.isEmpty || rendered.debugText.trim().isEmpty) {
      throw StateError('Printing renderer produced empty output.');
    }
    return rendered;
  }

  WmnLetterHead? _resolveLetterHead(
    WmnPrintRequest request,
    WmnPrintFormat format,
  ) {
    if (request.suppressLetterHead) return null;
    final explicit = _nullable(request.explicitLetterHeadId);
    if (explicit != null) {
      final selected = letterHead(explicit);
      if (selected == null) {
        throw StateError(
          'Explicit Letter Head is disabled or does not exist: $explicit',
        );
      }
      return selected;
    }
    final formatHead = _nullable(format.letterHeadId);
    if (formatHead != null) {
      final selected = letterHead(formatHead);
      if (selected != null) return selected;
    }
    if (request.sourceType == WmnPrintSourceType.document) {
      final documentValue = request.context['document'] ?? request.context['doc'];
      if (documentValue is Map) {
        final document = Map<Object?, Object?>.from(documentValue);
        final documentHead = _nullable(
          document['letter_head'] ?? document['letter_head_id'],
        );
        if (documentHead != null) {
          final selected = letterHead(documentHead);
          if (selected != null) return selected;
        }
      }
    }
    final configured = settings().defaultLetterHeadId;
    if (configured != null) {
      final selected = letterHead(configured);
      if (selected != null) return selected;
    }
    final defaults = database.db.select(
      'SELECT * FROM "tabLetter Head" '
      'WHERE disabled=0 AND is_default=1 '
      'ORDER BY updated_at DESC LIMIT 1;',
    );
    return defaults.isEmpty
        ? null
        : _letterHead(Map<String, Object?>.from(defaults.first));
  }

  String _resolveLanguage(WmnPrintRequest request, WmnPrintFormat format) {
    final candidates = <Object?>[
      request.languageCode,
      format.defaultPrintLanguage,
      if (request.context['report'] is Map)
        (request.context['report'] as Map)['language_code'],
      request.context['language_code'],
      settings().defaultPrintLanguage,
      'en',
    ];
    for (final raw in candidates) {
      final value = '${raw ?? ''}'.trim().toLowerCase();
      if (value.isNotEmpty) return value.replaceAll('_', '-');
    }
    return 'en';
  }

  Map<String, Object?> _printContext(
    Map<String, Object?> source, {
    required String languageCode,
    required WmnLetterHead? letterHead,
  }) {
    final result = <String, Object?>{...source};
    final reportValue = source['report'];
    if (reportValue is Map) {
      final report = Map<String, Object?>.from(reportValue);
      report['language_code'] = languageCode;
      result['report'] = report;
      for (final entry in report.entries) {
        if (result.containsKey(entry.key)) result[entry.key] = entry.value;
      }
    }
    result['print_language'] = languageCode;
    result['layout_direction'] = _isRtlLanguage(languageCode) ? 'rtl' : 'ltr';
    result['letter_head'] = letterHead?.toContext();
    return result;
  }

  int _previewFormatRank(
    WmnPrintFormat format,
    WmnPrintRequest request,
  ) {
    if (request.sourceType == WmnPrintSourceType.document) {
      return format.targetType == WmnPrintTargetType.document ? 0 : 1;
    }
    return switch (format.targetType) {
      WmnPrintTargetType.report => 0,
      WmnPrintTargetType.generalReport => 1,
      WmnPrintTargetType.platform => 2,
      WmnPrintTargetType.document => 3,
    };
  }

  bool _isRtlLanguage(String languageCode) {
    final primary = languageCode.toLowerCase().split(RegExp(r'[-_]')).first;
    return const <String>{'ar', 'fa', 'he', 'ur', 'ps', 'sd'}
        .contains(primary);
  }

  void _validateFormatTarget(
    WmnPrintFormat value,
    WmnPrintSourceType sourceType, {
    String? documentType,
    String? reportName,
    required bool explicit,
  }) {
    if (!explicit) return;
    if (value.targetType == WmnPrintTargetType.platform) return;
    if (value.targetType == WmnPrintTargetType.generalReport) {
      if (sourceType == WmnPrintSourceType.report) return;
      throw StateError('Explicit Print Format ${value.name} is reserved for reports.');
    }
    if (sourceType == WmnPrintSourceType.document && value.targetType != WmnPrintTargetType.document) {
      throw StateError('Explicit Print Format ${value.name} is not a document format.');
    }
    if (sourceType == WmnPrintSourceType.report && value.targetType != WmnPrintTargetType.report) {
      throw StateError('Explicit Print Format ${value.name} is not a report format.');
    }
    if (value.targetType == WmnPrintTargetType.document && value.documentType != documentType) {
      throw StateError('Print Format ${value.name} belongs to ${value.documentType}, not $documentType.');
    }
    if (value.targetType == WmnPrintTargetType.report && value.reportName != reportName) {
      throw StateError('Print Format ${value.name} belongs to ${value.reportName}, not $reportName.');
    }
  }

  void _assertPrintingEnabled() {
    if (!_featureEnabled('printing')) {
      throw StateError('Printing feature is disabled.');
    }
  }

  void _assertRendererFeature(String rendererId, {required WmnPrintFormat format}) {
    final templateUsesAdvancedCode = RegExp(
      r'{{\s*(barcode|qr)\s+',
      caseSensitive: false,
    ).hasMatch(format.templateText);
    if (rendererId == 'escpos' || templateUsesAdvancedCode) {
      _assertAdvancedPrinting();
    }
  }

  void _assertPrinterFeature(WmnPrinter printer) {
    if (const <String>{'WINDOWS_RAW','NETWORK','SERIAL','USB','BLUETOOTH'}.contains(printer.adapterId)) {
      _assertAdvancedPrinting();
    }
  }

  void _assertAdvancedPrinting() {
    if (!_featureEnabled('printing.advanced')) {
      throw StateError('Advanced Printing feature is disabled.');
    }
  }

  bool _featureEnabled(String code) {
    final check = isFeatureEnabled;
    if (check != null) return check(code);
    final rows = database.db.select('''
      SELECT f.enabled AS feature_enabled,
             COALESCE(a.enabled,1) AS activation_enabled,
             COALESCE(e.status,'GRANTED') AS entitlement_status
      FROM wmn_features f
      LEFT JOIN wmn_feature_activations a
        ON a.feature_id=f.id AND a.scope_type='INSTALLATION' AND a.scope_key='local'
      LEFT JOIN wmn_feature_entitlements e ON e.feature_id=f.id
      WHERE f.code=? LIMIT 1;
    ''', [code]);
    if (rows.isEmpty) return true;
    final row = rows.first;
    return row['feature_enabled'] == 1 &&
        row['activation_enabled'] == 1 &&
        const <String>{'GRANTED','TRIAL'}.contains('${row['entitlement_status']}');
  }

  String _fileName(WmnPrintRequest request, WmnRenderedPrint rendered) {
    final explicit = _nullable(request.outputFileName);
    if (explicit != null) return explicit.endsWith('.${rendered.fileExtension}') ? explicit : '$explicit.${rendered.fileExtension}';
    final raw = request.sourceName.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return '${raw.isEmpty ? 'wmn_print' : raw}_${DateTime.now().toUtc().millisecondsSinceEpoch}.${rendered.fileExtension}';
  }

  String _required(String? value, String message) {
    final normalized = _nullable(value);
    if (normalized == null) throw StateError(message);
    return normalized;
  }

  String? _nullable(Object? value) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty || text == 'null' ? null : text;
  }

  int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}');
  }

  double? _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}');
  }

  Map<String, Object?> _map(Object? raw) {
    if (raw is Map) return Map<String, Object?>.from(raw);
    if (raw is! String || raw.trim().isEmpty) return const <String, Object?>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, Object?>.from(decoded) : const <String, Object?>{};
    } catch (_) {
      return const <String, Object?>{};
    }
  }

  List<String> _list(Object? raw) {
    if (raw is List) return raw.map((item) => '$item').toList(growable: false);
    if (raw is! String || raw.trim().isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded.map((item) => '$item').toList(growable: false) : const <String>[];
    } catch (_) {
      return const <String>[];
    }
  }
}

class _PreparedPrint {
  const _PreparedPrint({
    required this.request,
    required this.format,
    required this.rendererId,
    required this.languageCode,
    required this.context,
    this.letterHead,
  });

  final WmnPrintRequest request;
  final WmnPrintFormat format;
  final String rendererId;
  final String languageCode;
  final WmnLetterHead? letterHead;
  final Map<String, Object?> context;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
