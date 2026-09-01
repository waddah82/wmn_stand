import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:wmn_standalone/core/database/wmn_database.dart';
import 'package:wmn_standalone/framework/apps/frappe_source_porter.dart';

void main() {
  test('safe Frappe form JS is rewritten to WMN compatibility APIs', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    final porter = WmnFrappeSourcePorter(database: database);
    const source = '''
frappe.ui.form.on("Customer", {
  refresh(frm) {
    frappe.msgprint("Ready");
    frappe.db.get_value("Company", "MAIN", "currency");
  }
});
''';
    final result = porter.analyzeJavaScript(source, doctype: 'Customer', sourcePath: 'customer.js');
    expect(result.status, 'AUTO_CONVERTED');
    expect(result.convertedCode, contains('wmn.ui.form.on'));
    expect(result.convertedCode, contains('wmn.db.getValue'));
    expect(result.symbols, isNotEmpty);
    database.close();
  });

  test('risky Frappe JS is preserved for review', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    final porter = WmnFrappeSourcePorter(database: database);
    const source = '''
frappe.ui.form.on("Sales Invoice", {
  refresh(frm) { frappe.call({ method: "erpnext.api.do_something" }); }
});
''';
    final result = porter.analyzeJavaScript(source, doctype: 'Sales Invoice', sourcePath: 'sales_invoice.js');
    expect(result.status, 'REVIEW');
    expect(result.diagnostics.join(' '), contains('frappe.call'));
    database.close();
  });

  test('simple Python validate hook generates a WMN server script candidate', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    final porter = WmnFrappeSourcePorter(database: database);
    const source = '''
import frappe
from frappe.model.document import Document

class Demo(Document):
    def validate(self):
        if self.total > 100:
            frappe.throw(_("Approval required"))
''';
    final result = porter.analyzePython(source, doctype: 'Demo', sourcePath: 'demo.py');
    expect(result.symbols.any((symbol) => symbol.lifecycleEvent == 'validate'), isTrue);
    expect(result.convertedCode, contains('wmn.server.on'));
    expect(result.convertedCode, contains('doc.total > 100'));
    expect(result.convertedCode, contains('wmn.throw'));
    database.close();
  });

  test('critical stock/accounting Python is never auto-converted', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    final porter = WmnFrappeSourcePorter(database: database);
    const source = '''
import frappe

def on_submit(self):
    make_gl_entries(self)
    update_stock_ledger(self)
''';
    final result = porter.analyzePython(source, doctype: 'Sales Invoice', sourcePath: 'sales_invoice.py');
    expect(result.status, isNot('AUTO_CONVERTED'));
    expect(result.symbols.any((symbol) => symbol.details['critical_engine_behavior'] == true), isTrue);
    database.close();
  });

  test('source unit stores code in WMN Storage while DB keeps paths and metadata', () {
    final database = WmnDatabase.forTesting(sqlite3.openInMemory());
    final porter = WmnFrappeSourcePorter(database: database);
    database.db.execute('''
      INSERT INTO wmn_app_packages(app_name,app_title,source_framework,module_json,manifest_json,conversion_status,installed_at,updated_at)
      VALUES ('demo','Demo','FRAPPE','{}','{}','IMPORTED',CURRENT_TIMESTAMP,CURRENT_TIMESTAMP);
    ''');
    const source = 'frappe.ui.form.on("Customer", { refresh(frm) { frappe.msgprint("Hi"); } });';
    final result = porter.analyzeJavaScript(source, doctype: 'Customer', sourcePath: 'customer.js');
    porter.saveSourceUnit(appName: 'demo', sourcePath: 'customer.js', source: source, result: result);
    final rows = porter.sourceUnits('demo');
    expect(rows, hasLength(1));
    expect(rows.first.keys, isNot(contains('source_code')));
    expect(rows.first.keys, isNot(contains('converted_code')));
    final hydrated = porter.sourceUnit('${rows.first['id']}');
    expect(hydrated, isNotNull);
    expect(hydrated!['source_code'], source);
    expect('${hydrated['converted_code']}', contains('wmn.ui.form.on'));
    final raw = database.db.select('SELECT * FROM wmn_app_source_units WHERE id=?;', [rows.first['id']]).single;
    expect('${raw['source_storage_path']}', startsWith('apps/demo/source/'));
    expect('${raw['converted_storage_path']}', startsWith('apps/demo/converted/'));
    expect(raw.keys, isNot(contains('source_code')));
    expect(raw.keys, isNot(contains('converted_code')));
    expect(porter.symbols('${rows.first['id']}'), isNotEmpty);
    database.close();
  });
}
