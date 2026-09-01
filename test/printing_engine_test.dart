import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/database/wmn_database.dart';
import 'package:wmn_standalone/core/database/migrations/migration_033_printing_text_unicode_repair.dart';
import 'package:wmn_standalone/core/database/migrations/migration_034_structured_report_printing.dart';
import 'package:wmn_standalone/platform/printing/renderers/wmn_html_pdf_converter.dart';
import 'package:wmn_standalone/platform/printing/renderers/wmn_html_print_renderer.dart';
import 'package:wmn_standalone/platform/printing/renderers/wmn_pdf_print_renderer.dart';
import 'package:wmn_standalone/platform/printing/wmn_barcode_service.dart';
import 'package:wmn_standalone/platform/printing/wmn_print_models.dart';
import 'package:wmn_standalone/platform/printing/wmn_report_print_layout.dart';
import 'package:wmn_standalone/platform/printing/wmn_print_template_engine.dart';
import 'package:wmn_standalone/platform/printing/wmn_printing_service.dart';

void main() {
  test('schema v30 exposes Printing System DocTypes and runtime fields', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);

    expect(WmnDatabase.schemaVersion, greaterThanOrEqualTo(30));
    final doctypes = database.db
        .select("SELECT name FROM wmn_doctypes WHERE name IN ('Print Format','Print Settings','Printer','Print Job','File');")
        .map((row) => '${row['name']}')
        .toSet();
    expect(doctypes, containsAll(<String>{'Print Format','Print Settings','Printer','Print Job','File'}));
    final columns = database.db
        .select('PRAGMA table_info(print_formats);')
        .map((row) => '${row['name']}')
        .toSet();
    expect(columns, containsAll(<String>{
      'target_type','document_type','report_name','renderer_id','template_text',
      'css_text','is_default','paper_width_mm','paper_height_mm','margin_mm',
    }));
    expect(
      database.db.select("SELECT generic_write FROM wmn_doctypes WHERE name='Print Job';").single['generic_write'],
      0,
    );
  });

  test('v33 repair upgrades an already-v32 escaped General Report template', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    database.db.execute(
      "UPDATE print_formats SET template_text=? WHERE code='WMN-GENERAL-REPORT';",
      <Object?>[r'Header\n\n{{ report.title }}\n'],
    );
    const Migration033PrintingTextUnicodeRepair().apply(database.db);
    final row = database.db.select(
      "SELECT template_text FROM print_formats WHERE code='WMN-GENERAL-REPORT' LIMIT 1;",
    ).single;
    final template = '${row['template_text']}';
    expect(template, isNot(contains(r'\n')));
    expect(template, contains('\n'));
  });


  test('v34 migration replaces the protected flattened General Report layout with structured markers', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    database.db.execute(
      "UPDATE print_formats SET template_text='{{ report.title }} flattened' WHERE code='WMN-GENERAL-REPORT';",
    );
    const Migration034StructuredReportPrinting().apply(database.db);
    final row = database.db.select(
      "SELECT template_text,metadata_json FROM print_formats WHERE code='WMN-GENERAL-REPORT' LIMIT 1;",
    ).single;
    expect('${row['template_text']}', contains('{{ report.table }}'));
    expect('${row['template_text']}', contains('{{ report.filters_block }}'));
    expect('${row['metadata_json']}', contains('structured_report'));
  });

  test('Frappe-compatible print runtime remains active under schema v36', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    expect(WmnDatabase.schemaVersion, 36);
    final version = database.db.select(
      "SELECT value FROM system_meta WHERE key='schema_version' LIMIT 1;",
    ).single['value'];
    expect('$version', '36');
    final columns = database.db
        .select('PRAGMA table_info(print_formats);')
        .map((row) => '${row['name']}')
        .toSet();
    expect(columns, containsAll(<String>{
      'letter_head_id',
      'default_print_language',
      'font_family',
      'pdf_generator',
    }));
    expect(
      database.db.select(
        "SELECT COUNT(*) AS count FROM wmn_doctypes WHERE name='Letter Head' AND enabled=1;",
      ).single['count'],
      1,
    );
  });

  test('preview resolves Letter Head and language without creating Print Job', () async {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    database.db.execute('''
      INSERT INTO "tabLetter Head"(
        id,name,header_html,footer_html,css_text,is_default,disabled,metadata_json
      ) VALUES(?,?,?,?,?,1,0,'{}');
    ''', <Object?>[
      'company-head',
      'Company',
      '<div>شركة WMN | WMN Company</div>',
      '<div>Footer</div>',
      '.wmn-letter-head { font-weight: 700; }',
    ]);
    final service = WmnPrintingService(database);
    final request = service.reportRequest(
      reportName: 'Preview Test',
      columns: const <String>['label'],
      rows: const <Map<String, Object?>>[
        <String, Object?>{'label': 'Customer العميل'},
      ],
      rendererId: 'html',
      languageCode: 'ar',
    );
    final before = service.jobs().length;
    final preview = await service.preview(request);
    expect(service.jobs().length, before);
    expect(preview.letterHead?.id, 'company-head');
    expect(preview.languageCode, 'ar');
    expect(preview.rendered.debugText, contains('<html lang="ar" dir="rtl">'));
    expect(preview.rendered.debugText, contains('شركة WMN | WMN Company'));
    expect(preview.rendered.debugText, contains('Customer العميل'));
  });

  test('mixed Arabic and English text is preserved without content-driven direction switching', () async {
    const renderer = WmnHtmlPrintRenderer();
    const format = WmnPrintFormat(
      id: 'mixed-script-html',
      code: 'MIXED-SCRIPT-HTML',
      name: 'Mixed Script HTML',
      targetType: WmnPrintTargetType.document,
      rendererId: 'html',
      templateText: '<p>Customer العميل 123</p>',
      enabled: true,
      isDefault: false,
      paperWidthMm: 210,
      paperHeightMm: 297,
      marginMm: 10,
      documentType: 'Demo',
    );

    final english = await renderer.render(
      format: format,
      context: const <String, Object?>{'print_language': 'en'},
      templates: const WmnPrintTemplateEngine(),
      barcodes: const WmnBarcodeService(),
    );
    final arabic = await renderer.render(
      format: format,
      context: const <String, Object?>{'print_language': 'ar'},
      templates: const WmnPrintTemplateEngine(),
      barcodes: const WmnBarcodeService(),
    );

    expect(english.debugText, contains('<html lang="en" dir="ltr">'));
    expect(arabic.debugText, contains('<html lang="ar" dir="rtl">'));
    expect(english.debugText, contains('Customer العميل 123'));
    expect(arabic.debugText, contains('Customer العميل 123'));
  });

  test('general report format uses real line breaks instead of escaped newline text', () async {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final row = database.db.select(
      "SELECT template_text FROM print_formats WHERE code='WMN-GENERAL-REPORT' LIMIT 1;",
    ).single;
    final template = '${row['template_text']}';
    expect(template, isNot(contains(r'\n')));
    expect(template, contains('\n'));

    final service = WmnPrintingService(database);
    final rendered = await service.render(
      const WmnPrintRequest(
        sourceType: WmnPrintSourceType.report,
        sourceName: 'Line Break Regression',
        reportName: 'Line Break Regression',
        rendererId: 'html',
        context: <String, Object?>{
          'report': <String, Object?>{
            'title': 'Line Break Regression',
            'rows': <Map<String, Object?>>[
              <String, Object?>{'module': 'WMN System', 'count': 2},
              <String, Object?>{'module': 'Security', 'count': 1},
            ],
          },
        },
      ),
    );
    expect(rendered.debugText, isNot(contains(r'\n')));
    expect(rendered.debugText, contains('\n'));
  });

  test('template engine normalizes historical escaped line breaks at runtime', () {
    const engine = WmnPrintTemplateEngine();
    final rendered = engine.render(r'Header\n\nRow 1\nRow 2', const <String, Object?>{});
    expect(rendered, 'Header\n\nRow 1\nRow 2');
    expect(rendered, isNot(contains(r'\n')));
  });

  test('template engine expands child tables, nested maps, barcode and QR tokens', () {
    const engine = WmnPrintTemplateEngine();
    final output = engine.render(
      '''{{ document.name }}\n{{#each document.items}}{{ item_code }}={{ qty }};{{/each}}\n{{#each report.filters}}{{ key }}={{ value }};{{/each}}\n{{ barcode document.name }}\n{{ qr document.name }}''',
      <String, Object?>{
        'document': <String, Object?>{
          'name': 'DOC-0001',
          'items': <Map<String, Object?>>[
            <String, Object?>{'item_code': 'A', 'qty': 2},
            <String, Object?>{'item_code': 'B', 'qty': 3},
          ],
        },
        'report': <String, Object?>{
          'filters': <String, Object?>{'status': 'Open'},
        },
      },
      now: DateTime.utc(2026, 8, 30),
    );

    expect(output, contains('DOC-0001'));
    expect(output, contains('A=2;B=3;'));
    expect(output, contains('status=Open;'));
    expect(WmnBarcodeService.markerPattern.allMatches(output), hasLength(2));
  });

  test('Print Format selection is explicit then specific then general then platform', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final service = WmnPrintingService(database);
    final now = DateTime.now().toUtc().toIso8601String();

    database.db.execute('''
      INSERT INTO print_formats(
        id,code,name,format_type,template_json,enabled,created_at,updated_at,
        target_type,document_type,renderer_id,template_text,is_default
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?);
    ''', <Object?>[
      'doc-format','DOC-FORMAT','Document Format','DOCUMENT','{}',1,now,now,
      'DOCUMENT','Demo Document','html','{{ document.name }}',1,
    ]);
    database.db.execute('''
      INSERT INTO print_formats(
        id,code,name,format_type,template_json,enabled,created_at,updated_at,
        target_type,report_name,renderer_id,template_text,is_default
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?);
    ''', <Object?>[
      'report-format','REPORT-FORMAT','Report Format','REPORT','{}',1,now,now,
      'REPORT','Demo Report','html','{{ report.title }}',1,
    ]);

    expect(
      service.resolveFormat(
        sourceType: WmnPrintSourceType.document,
        documentType: 'Demo Document',
      ).id,
      'doc-format',
    );
    expect(
      service.resolveFormat(
        sourceType: WmnPrintSourceType.report,
        reportName: 'Demo Report',
      ).id,
      'report-format',
    );
    expect(
      service.resolveFormat(
        sourceType: WmnPrintSourceType.report,
        reportName: 'Other Report',
      ).code,
      'WMN-GENERAL-REPORT',
    );
    expect(
      service.resolveFormat(
        sourceType: WmnPrintSourceType.document,
        documentType: 'Other Document',
      ).code,
      'WMN-PLATFORM-DEFAULT',
    );
    expect(
      () => service.resolveFormat(
        sourceType: WmnPrintSourceType.report,
        reportName: 'Other Report',
        explicitFormatId: 'report-format',
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('HTML renderer expands child rows and emits real barcode SVG', () async {
    const renderer = WmnHtmlPrintRenderer();
    const format = WmnPrintFormat(
      id: 'html-test',
      code: 'HTML-TEST',
      name: 'HTML Test',
      targetType: WmnPrintTargetType.document,
      rendererId: 'html',
      templateText: '<h1>{{ document.name }}</h1>{{#each document.items}}<p>{{ item_code }}</p>{{/each}}{{ barcode document.name }}',
      enabled: true,
      isDefault: false,
      paperWidthMm: 210,
      paperHeightMm: 297,
      marginMm: 10,
      documentType: 'Demo',
    );
    final result = await renderer.render(
      format: format,
      context: const <String, Object?>{
        'document': <String, Object?>{
          'name': 'DOC-HTML',
          'items': <Map<String, Object?>>[
            <String, Object?>{'item_code': 'ITEM-1'},
          ],
        },
      },
      templates: const WmnPrintTemplateEngine(),
      barcodes: const WmnBarcodeService(),
    );
    final html = utf8.decode(result.bytes);
    expect(html, contains('DOC-HTML'));
    expect(html, contains('ITEM-1'));
    expect(html.toLowerCase(), contains('<svg'));
    expect(result.mimeType, startsWith('text/html'));
  });

  test('HTML renderer constrains QR to Print Format physical size', () async {
    const renderer = WmnHtmlPrintRenderer();
    const format = WmnPrintFormat(
      id: 'qr-size-test',
      code: 'QR-SIZE-TEST',
      name: 'QR Size Test',
      targetType: WmnPrintTargetType.document,
      rendererId: 'html',
      templateText: '{{ qr document.name }}',
      enabled: true,
      isDefault: false,
      paperWidthMm: 210,
      paperHeightMm: 297,
      marginMm: 10,
      documentType: 'Demo',
      metadata: <String, Object?>{'qr_size_mm': 18},
    );
    final result = await renderer.render(
      format: format,
      context: const <String, Object?>{
        'document': <String, Object?>{'name': 'DOC-QR'},
      },
      templates: const WmnPrintTemplateEngine(),
      barcodes: const WmnBarcodeService(),
    );
    final html = utf8.decode(result.bytes);
    expect(html, contains('class="wmn-qr-code"'));
    expect(html, contains('width: 18.0mm !important'));
    expect(html, contains('height: 18.0mm !important'));
  });

  test('HTML/template content converts to a real PDF payload', () async {
    final renderer = WmnPdfPrintRenderer(converter: const _FakeHtmlPdfConverter());
    const format = WmnPrintFormat(
      id: 'pdf-test',
      code: 'PDF-TEST',
      name: 'PDF Test',
      targetType: WmnPrintTargetType.document,
      rendererId: 'pdf',
      templateText: '<h1>{{ document.name }}</h1><p>مرحبا WMN</p>{{#each document.items}}<div>{{ item_code }} x {{ qty }}</div>{{/each}}{{ qr document.name }}',
      enabled: true,
      isDefault: false,
      paperWidthMm: 210,
      paperHeightMm: 297,
      marginMm: 10,
      documentType: 'Demo',
    );
    final result = await renderer.render(
      format: format,
      context: const <String, Object?>{
        'document': <String, Object?>{
          'name': 'DOC-PDF',
          'items': <Map<String, Object?>>[
            <String, Object?>{'item_code': 'ITEM-1', 'qty': 2},
          ],
        },
      },
      templates: const WmnPrintTemplateEngine(),
      barcodes: const WmnBarcodeService(),
    );
    expect(result.mimeType, 'application/pdf');
    expect(result.bytes.length, greaterThan(200));
    expect(ascii.decode(result.bytes.take(4).toList()), '%PDF');
    expect(result.debugText, contains('ITEM-1'));
  });

  test('execution stores output in File and closes Print Job', () async {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final service = WmnPrintingService(database);

    final result = await service.executeReport(
      reportName: 'Runtime Report',
      columns: const <String>['name','value'],
      rows: const <Map<String, Object?>>[
        <String, Object?>{'name': 'A', 'value': 1},
      ],
      rendererId: 'html',
    );

    final jobs = service.jobs(status: 'SENT');
    expect(jobs.single.id, result.jobId);
    expect(jobs.single.outputFileId, result.outputFileId);
    expect(jobs.single.byteCount, result.rendered.bytes.length);
    expect(service.files.file(result.outputFileId), isNotNull);
    expect(service.files.readBytes(result.outputFileId), isNotEmpty);
  });

  test('advanced printing entitlement gates ESC/POS and raw transports', () async {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final service = WmnPrintingService(database);
    database.db.execute('''
      UPDATE wmn_feature_activations SET enabled=0
      WHERE feature_id='feature-advanced-printing' AND scope_type='INSTALLATION' AND scope_key='local';
    ''');

    await expectLater(
      service.render(
        const WmnPrintRequest(
          sourceType: WmnPrintSourceType.report,
          sourceName: 'Feature Report',
          reportName: 'Feature Report',
          rendererId: 'escpos',
          context: <String, Object?>{
            'report': <String, Object?>{'title': 'Feature Report', 'rows': <Object?>[]},
          },
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });
  test('advanced printing entitlement gates Barcode/QR template tokens', () async {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final service = WmnPrintingService(database);
    final now = DateTime.now().toUtc().toIso8601String();
    database.db.execute('''
      INSERT INTO print_formats(
        id,code,name,format_type,template_json,enabled,created_at,updated_at,
        target_type,document_type,renderer_id,template_text,is_default
      ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?);
    ''', <Object?>[
      'barcode-doc-format','BARCODE-DOC','Barcode Document','DOCUMENT','{}',1,now,now,
      'DOCUMENT','Demo','html','{{ barcode document.name }}',0,
    ]);
    database.db.execute('''
      UPDATE wmn_feature_activations SET enabled=0
      WHERE feature_id='feature-advanced-printing' AND scope_type='INSTALLATION' AND scope_key='local';
    ''');

    await expectLater(
      service.render(
        const WmnPrintRequest(
          sourceType: WmnPrintSourceType.document,
          sourceName: 'Barcode Document',
          documentType: 'Demo',
          documentName: 'DOC-1',
          explicitFormatId: 'barcode-doc-format',
          context: <String, Object?>{
            'document': <String, Object?>{'name': 'DOC-1'},
          },
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });


  test('general report format renders a structured table with column labels and filters', () async {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final service = WmnPrintingService(database);

    final formatRow = database.db.select(
      "SELECT template_text,metadata_json FROM print_formats WHERE code='WMN-GENERAL-REPORT' LIMIT 1;",
    ).single;
    expect('${formatRow['template_text']}', contains('{{ report.table }}'));
    expect('${formatRow['template_text']}', contains('{{ report.filters_block }}'));
    expect('${formatRow['metadata_json']}', contains('structured_report'));

    final html = await service.render(
      const WmnPrintRequest(
        sourceType: WmnPrintSourceType.report,
        sourceName: 'Structured Report',
        reportName: 'Structured Report',
        rendererId: 'html',
        context: <String, Object?>{
          'report': <String, Object?>{
            'title': 'Structured Report',
            'columns': <String>['doctype', 'count'],
            'column_definitions': <Map<String, Object?>>[
              <String, Object?>{'fieldname': 'doctype', 'label': 'DocType', 'fieldtype': 'Data'},
              <String, Object?>{'fieldname': 'count', 'label': 'Count', 'fieldtype': 'Int'},
            ],
            'filters': <String, Object?>{'module': 'WMN System'},
            'filter_definitions': <Map<String, Object?>>[
              <String, Object?>{'fieldname': 'module', 'label': 'Module'},
            ],
            'rows': <Map<String, Object?>>[
              <String, Object?>{'doctype': 'Application', 'count': 2},
              <String, Object?>{'doctype': 'Page', 'count': 4},
            ],
            'row_count': 2,
            'table': WmnReportPrintLayout.tableMarker,
            'filters_block': WmnReportPrintLayout.filtersMarker,
            'row_count_block': WmnReportPrintLayout.rowCountMarker,
          },
        },
      ),
    );
    expect(html.debugText, contains('<table class="wmn-report-table">'));
    expect(html.debugText, contains('<th>DocType</th>'));
    expect(html.debugText, contains('<th>Count</th>'));
    expect(html.debugText, contains('<strong>Module:</strong> WMN System'));
    expect(html.debugText, isNot(contains(WmnReportPrintLayout.tableMarker)));
  });

  test('structured report layout resolves current localized column and filter labels', () {
    final english = WmnReportPrintLayout.fromReport(const <String, Object?>{
      'language_code': 'en',
      'columns': <String>['doctype'],
      'column_definitions': <Map<String, Object?>>[
        <String, Object?>{'fieldname': 'doctype', 'label': 'Document Type', 'label_ar': 'نوع المستند'},
      ],
      'filters': <String, Object?>{'module': 'WMN System'},
      'filter_definitions': <Map<String, Object?>>[
        <String, Object?>{'fieldname': 'module', 'label': 'Module Name', 'label_ar': 'اسم الوحدة'},
      ],
      'rows': <Map<String, Object?>>[
        <String, Object?>{'doctype': 'Application'},
      ],
    });
    final arabic = WmnReportPrintLayout.fromReport(const <String, Object?>{
      'language_code': 'ar',
      'columns': <String>['doctype'],
      'column_definitions': <Map<String, Object?>>[
        <String, Object?>{'fieldname': 'doctype', 'label': 'Document Type', 'label_ar': 'نوع المستند'},
      ],
      'filters': <String, Object?>{'module': 'WMN System'},
      'filter_definitions': <Map<String, Object?>>[
        <String, Object?>{'fieldname': 'module', 'label': 'Module Name', 'label_ar': 'اسم الوحدة'},
      ],
      'rows': <Map<String, Object?>>[
        <String, Object?>{'doctype': 'Application'},
      ],
    });
    expect(english.columns.single.label, 'Document Type');
    expect(english.filters.single.label, 'Module Name');
    expect(arabic.columns.single.label, 'نوع المستند');
    expect(arabic.filters.single.label, 'اسم الوحدة');
  });

  test('general report PDF consumes the canonical structured HTML', () async {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final service = _serviceWithFakePdf(database);

    final result = await service.executeReport(
      reportName: 'Structured PDF Report',
      columns: const <String>['doctype', 'module', 'enabled'],
      columnDefinitions: const <Map<String, Object?>>[
        <String, Object?>{'fieldname': 'doctype', 'label': 'DocType', 'fieldtype': 'Data'},
        <String, Object?>{'fieldname': 'module', 'label': 'Module', 'fieldtype': 'Data'},
        <String, Object?>{'fieldname': 'enabled', 'label': 'Enabled', 'fieldtype': 'Check'},
      ],
      rows: const <Map<String, Object?>>[
        <String, Object?>{'doctype': 'Application', 'module': 'WMN System', 'enabled': 1},
        <String, Object?>{'doctype': 'Page', 'module': 'WMN System', 'enabled': 1},
      ],
      filters: const <String, Object?>{'module': 'WMN System'},
      filterDefinitions: const <Map<String, Object?>>[
        <String, Object?>{'fieldname': 'module', 'label': 'Module'},
      ],
      rendererId: 'pdf',
    );
    expect(result.rendered.mimeType, 'application/pdf');
    expect(ascii.decode(result.rendered.bytes.take(4).toList()), '%PDF');
    expect(result.rendered.debugText, contains('<table class="wmn-report-table">'));
    expect(result.rendered.debugText, contains('<th>DocType</th>'));
    expect(result.rendered.debugText, contains('<td>Application</td>'));
    expect(result.rendered.debugText, isNot(contains('doctype: Application')));
    expect(result.rendered.debugText, isNot(contains(WmnReportPrintLayout.tableMarker)));
  });


  test('canonical PDF HTML preserves mixed Arabic English text without splitting', () async {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    addTearDown(database.close);
    final service = _serviceWithFakePdf(database);

    final result = await service.executeReport(
      reportName: 'Mixed Script PDF Report',
      columns: const <String>['invoice', 'customer'],
      columnDefinitions: const <Map<String, Object?>>[
        <String, Object?>{
          'fieldname': 'invoice',
          'label': 'Invoice No',
          'label_ar': 'رقم Invoice',
          'fieldtype': 'Data',
        },
        <String, Object?>{
          'fieldname': 'customer',
          'label': 'Customer',
          'label_ar': 'Customer العميل',
          'fieldtype': 'Data',
        },
      ],
      rows: const <Map<String, Object?>>[
        <String, Object?>{'invoice': 'INV-0001', 'customer': 'WMN'},
      ],
      rendererId: 'pdf',
      languageCode: 'ar',
    );

    expect(result.rendered.mimeType, 'application/pdf');
    expect(ascii.decode(result.rendered.bytes.take(4).toList()), '%PDF');
    expect(result.rendered.debugText, contains('رقم Invoice'));
    expect(result.rendered.debugText, contains('Customer العميل'));
  });

}


WmnPrintingService _serviceWithFakePdf(WmnDatabase database) {
  final service = WmnPrintingService(database);
  service.registerRenderer(
    WmnPdfPrintRenderer(converter: const _FakeHtmlPdfConverter()),
    replace: true,
  );
  return service;
}

class _FakeHtmlPdfConverter implements WmnHtmlPdfConverter {
  const _FakeHtmlPdfConverter();

  @override
  Future<Uint8List> convert({
    required String html,
    required WmnPrintFormat format,
  }) async {
    final payload = <int>[...ascii.encode('%PDF-1.4\n')];
    while (payload.length < 320) {
      payload.addAll(ascii.encode('WMN-CANONICAL-HTML-PDF\n'));
    }
    return Uint8List.fromList(payload);
  }
}
